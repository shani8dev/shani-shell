#!/usr/bin/env python3
"""contacts — Shani Link's address book for the shell, as JSON.

    contacts.py list [QUERY]        [{uid, name, phone, email, ...}] sorted by name
    contacts.py search QUERY        same as list QUERY (live search)
    contacts.py add '<json>'        {"name": "…", "phone": "…", "email": "…"}
    contacts.py edit '<json>'       {"uid": "…", "name": "…", "phone": "…", "email": "…"}
    contacts.py delete '<json>'     {"uid": "…"} (a bare uid string is also read)
    contacts.py import '<path>'     a .vcf path, or '{"path": "…"}' (same contract)
    contacts.py get '<uid>'         one contact as JSON

List prints a JSON array; writes print {"ok": true, "uid": "…"} (import prints
{"ok": true, "count": N}). Exit 3 is bad input (malformed JSON, no name, no uid,
unknown command). There is no "no service" state: an absent folder is an empty
book, and the first write creates it. The book lives in Shani Link's vCard
folder — `$XDG_DATA_HOME/shani-link/contacts/` (see shani-link
`shani_link/contacts.py`: `folder()` and `paths.data_home()`) — one `.vcf` per
contact, named by its UID. `SHANI_CONTACTS_DIR` overrides that folder for tests.

When `shani_link.contacts` is importable (Shani Link installed, or
`~/Documents/shani/shani-link` on `sys.path`), its `folder()` is the folder
and its `parse`/`serialize` rules are the format's source of truth — the
subset re-implemented here below writes the same vCard 4.0 and reads the same
files, so the two never disagree about a contact. Standard library only.

No Evolution Data Server, no EDS/EBook bindings: Shani Link keeps its own
vCard files, and this tool reads exactly those.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import unicodedata
import uuid
from pathlib import Path

# Let a checkout of shani-link serve the import (the dev machine keeps it at
# ~/Documents/shani/shani-link); an installed package needs no path help.
for _candidate in (Path.home() / "Documents/shani/shani-link",):
    if (_candidate / "shani_link" / "contacts.py").is_file() and str(_candidate) not in sys.path:
        sys.path.insert(0, str(_candidate))


def folder() -> Path:
    override = os.environ.get("SHANI_CONTACTS_DIR", "")
    if override:
        return Path(override)
    try:
        from shani_link import contacts as _link  # type: ignore

        return Path(_link.folder())
    except Exception:  # noqa: BLE001 - no package: the XDG rule below is the API's
        pass
    configured = os.environ.get("XDG_DATA_HOME", "")
    base = Path(configured) if configured and Path(configured).is_absolute() else Path.home() / ".local" / "share"
    return base / "shani-link" / "contacts"


# --- searching and sorting (the documented rules of contacts.py) -----------------

def fold_text(text: str) -> str:
    """Lowercase with accents removed, so "jose" finds "José"."""
    decomposed = unicodedata.normalize("NFKD", text or "")
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch)).casefold()


def digits(text: str) -> str:
    return re.sub(r"\D", "", text or "")


def _display(contact: dict) -> str:
    name = (contact.get("name") or "").strip()
    if name:
        return name
    joined = " ".join(p for p in (contact.get("given", ""), contact.get("family", "")) if p)
    if joined.strip():
        return joined.strip()
    for key in ("phones", "emails"):
        for item in contact.get(key) or []:
            value = item.get("number") or item.get("address") or ""
            if value.strip():
                return value.strip()
    return "Unnamed contact"


def matches(contact: dict, query: str) -> bool:
    q = fold_text((query or "").strip())
    if not q:
        return True
    names = fold_text(" ".join((contact.get("name", ""), contact.get("given", ""),
                                contact.get("family", ""))))
    if all(word in names for word in q.split()):
        return True
    if any(q in fold_text(item.get("address", "")) for item in contact.get("emails") or []):
        return True
    wanted = digits(q)
    if len(wanted) >= 2:
        return any(wanted in digits(item.get("number", "")) for item in contact.get("phones") or [])
    return False


def sort_key(contact: dict) -> tuple[str, str]:
    shown = _display(contact)
    return (fold_text(shown), fold_text(shown))


# --- vCard: reading (2.1, 3.0 and 4.0) --------------------------------------------

def _unfold(text: str) -> list[str]:
    raw = re.sub(r"\r\n|\r", "\n", text)
    raw = re.sub(r"\n[ \t]", "", raw)
    return [line for line in raw.split("\n") if line.strip()]


def _unescape(value: str) -> str:
    return re.sub(r"\\(.)", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def _split(value: str, sep: str) -> list[str]:
    parts, cur, i = [], [], 0
    while i < len(value):
        ch = value[i]
        if ch == "\\" and i + 1 < len(value):
            cur.append(value[i:i + 2])
            i += 2
            continue
        if ch == sep:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    parts.append("".join(cur))
    return parts


def parse(text: str) -> list[dict]:
    """Every contact in `text`, one or many vCards."""
    found: list[dict] = []
    current: dict | None = None
    for line in _unfold(text):
        if ":" not in line:
            continue
        head, _, value = line.partition(":")
        name = head.split(".")[-1].split(";", 1)[0].strip().upper()
        value = value.strip()
        if name == "BEGIN" and value.upper() == "VCARD":
            current = {"uid": "", "name": "", "given": "", "family": "",
                       "phones": [], "emails": []}
            continue
        if current is None:
            continue
        if name == "END":
            if _display(current) != "Unnamed contact" or current["phones"] or current["emails"]:
                current["name"] = _display(current) if not current["name"] else current["name"]
                found.append(current)
            current = None
            continue
        if name == "UID":
            current["uid"] = re.sub(r"^urn:uuid:", "", value, flags=re.I)
        elif name == "FN":
            current["name"] = _unescape(value).strip()
        elif name == "N":
            parts = [_unescape(p).strip() for p in _split(value, ";")] + [""] * 2
            current["family"], current["given"] = parts[0], parts[1]
        elif name == "TEL":
            number = re.sub(r"^tel:", "", _unescape(value).strip(), flags=re.I)
            if number:
                current["phones"].append({"type": "cell", "number": number})
        elif name == "EMAIL":
            address = re.sub(r"^mailto:", "", _unescape(value).strip(), flags=re.I)
            if address:
                current["emails"].append({"type": "home", "address": address})
    for c in found:
        if not c["name"]:
            joined = " ".join(p for p in (c.get("given", ""), c.get("family", "")) if p)
            c["name"] = joined.strip()
    return found


# --- vCard: writing (4.0, as Shani Link's serialize writes) ------------------------

def _escape(value: str) -> str:
    return (value.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
            .replace("\r\n", "\n").replace("\n", "\\n"))


def _fold(line: str) -> str:
    """Longer than 75 octets continues on the next line, never cutting a UTF-8 char."""
    out, cur, size = [], "", 0
    for ch in line:
        n = len(ch.encode("utf-8"))
        if size + n > 75:
            out.append(cur)
            cur, size = " ", 1
        cur += ch
        size += n
    out.append(cur)
    return "\r\n".join(out)


def _split_name(name: str) -> tuple[str, str]:
    parts = [p for p in name.strip().split() if p]
    if not parts:
        return "", ""
    if len(parts) == 1:
        return parts[0], ""
    return " ".join(parts[:-1]), parts[-1]


def serialize(contact: dict) -> str:
    name = _display(contact)
    given = contact.get("given", "")
    family = contact.get("family", "")
    if not given and not family:
        given, family = _split_name(name)
    lines = ["BEGIN:VCARD", "VERSION:4.0"]
    if contact.get("uid"):
        lines.append(f"UID:urn:uuid:{contact['uid']}")
    lines.append("FN:" + _escape(name))
    lines.append(f"N:{_escape(family)};{_escape(given)};;;")
    for item in contact.get("phones") or []:
        number = (item.get("number") or "").strip() if isinstance(item, dict) else str(item).strip()
        if number:
            lines.append(f"TEL;TYPE={item.get('type', 'cell') if isinstance(item, dict) else 'cell'}:{_escape(number)}")
    for item in contact.get("emails") or []:
        address = (item.get("address") or "").strip() if isinstance(item, dict) else str(item).strip()
        if address:
            lines.append(f"EMAIL;TYPE={item.get('type', 'home') if isinstance(item, dict) else 'home'}:{_escape(address)}")
    lines.append("END:VCARD")
    return "".join(_fold(ln) + "\r\n" for ln in lines)


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", suffix=".vcf", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# --- the book on disk (one .vcf per contact, named by UID) ------------------------

def _file(uid: str) -> Path:
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", uid)
    return folder() / f"{safe}.vcf"


def _to_json(contact: dict) -> dict:
    phones = [{"type": p.get("type", "cell"), "number": p.get("number", "")} for p in contact.get("phones") or []]
    emails = [{"type": e.get("type", "home"), "address": e.get("address", "")} for e in contact.get("emails") or []]
    return {"uid": contact.get("uid", ""), "name": contact.get("name") or _display(contact),
            "given": contact.get("given", ""), "family": contact.get("family", ""),
            "phone": phones[0]["number"] if phones else "",
            "email": emails[0]["address"] if emails else "",
            "phones": phones, "emails": emails}


def all_contacts() -> list[dict]:
    where = folder()
    if not where.is_dir():
        return []
    found = []
    for card in sorted(where.glob("*.vcf")):
        try:
            text = card.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for contact in parse(text)[:1]:
            contact["uid"] = contact["uid"] or card.stem
            found.append(contact)
    return found


def list_contacts(query: str = "") -> list[dict]:
    contacts = [c for c in all_contacts() if matches(c, query)]
    contacts.sort(key=sort_key)
    return [_to_json(c) for c in contacts]


def get_contact(uid: str) -> dict | None:
    return next((c for c in all_contacts() if c["uid"] == uid), None)


def save(contact: dict) -> dict:
    saved = dict(contact)
    uid = saved.get("uid", "")
    if not uid or uid.startswith("phone:"):
        saved["uid"] = str(uuid.uuid4())
    if not saved.get("name"):
        saved["name"] = _display(saved)
    _atomic_write(_file(saved["uid"]), serialize(saved).encode("utf-8"))
    return saved


def delete_contact(uid: str) -> bool:
    try:
        _file(uid).unlink()
    except FileNotFoundError:
        return False
    return True


def import_text(text: str) -> list[dict]:
    have = {c["uid"] for c in all_contacts()}
    added = []
    for contact in parse(text):
        if contact["uid"] in have:
            contact["uid"] = ""  # a copy, never an overwrite (contacts.py rule)
        added.append(save(contact))
    return added


def import_file(path: str) -> list[dict]:
    with open(path, encoding="utf-8", errors="replace") as fh:
        return import_text(fh.read())


def _make(name: str, phone: str, email: str, uid: str = "") -> dict:
    given, family = _split_name(name)
    return {"uid": uid, "name": name.strip(), "given": given, "family": family,
            "phones": [{"type": "cell", "number": phone.strip()}] if (phone or "").strip() else [],
            "emails": [{"type": "home", "address": email.strip()}] if (email or "").strip() else []}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: contacts.py list [QUERY] | add|edit|delete '<json>' | import PATH", file=sys.stderr)
        return 3
    command = argv[1]
    if command in ("list", "search"):
        query = argv[2] if len(argv) > 2 else ""
        print(json.dumps(list_contacts(query), ensure_ascii=False))
        return 0
    if command in ("add", "edit", "delete", "import", "get"):
        if len(argv) < 3:
            print(f"Invalid argument: {command} needs a value", file=sys.stderr)
            return 3
        raw = argv[2]
        if command == "import":
            path = raw
            if raw.lstrip().startswith("{"):
                try:
                    path = str(json.loads(raw).get("path", ""))
                except (json.JSONDecodeError, AttributeError) as exc:
                    print(f"Invalid argument: {exc}", file=sys.stderr)
                    return 3
            if not path or not Path(path).is_file():
                print(f"Invalid argument: no vCard file at {path!r}", file=sys.stderr)
                return 3
            added = import_file(path)
            print(json.dumps({"ok": True, "count": len(added)}))
            return 0
        if command == "get":
            found = get_contact(raw)
            if found is None:
                print(f"Invalid argument: no contact with uid {raw!r}", file=sys.stderr)
                return 3
            print(json.dumps(_to_json(found), ensure_ascii=False))
            return 0
        # add / edit / delete take a JSON object; delete also reads a bare uid
        if command == "delete" and not raw.lstrip().startswith("{"):
            payload = {"uid": raw}
        else:
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError as exc:
                print(f"Invalid argument: {exc}", file=sys.stderr)
                return 3
            if not isinstance(payload, dict):
                print("Invalid argument: expected a JSON object", file=sys.stderr)
                return 3
        if command == "add":
            name = str(payload.get("name", "")).strip()
            if not name:
                print("Invalid argument: a contact needs a name", file=sys.stderr)
                return 3
            saved = save(_make(name, str(payload.get("phone", "")), str(payload.get("email", ""))))
            print(json.dumps({"ok": True, "uid": saved["uid"]}))
            return 0
        if command == "edit":
            uid = str(payload.get("uid", "")).strip()
            name = str(payload.get("name", "")).strip()
            if not uid or not name:
                print("Invalid argument: edit needs a uid and a name", file=sys.stderr)
                return 3
            if get_contact(uid) is None:
                print(f"Invalid argument: no contact with uid {uid!r}", file=sys.stderr)
                return 3
            saved = save(_make(name, str(payload.get("phone", "")), str(payload.get("email", "")), uid))
            print(json.dumps({"ok": True, "uid": saved["uid"]}))
            return 0
        # delete
        uid = str(payload.get("uid", "")).strip()
        if not uid:
            print("Invalid argument: delete needs a uid", file=sys.stderr)
            return 3
        if not delete_contact(uid):
            print(f"Invalid argument: no contact with uid {uid!r}", file=sys.stderr)
            return 3
        print(json.dumps({"ok": True, "uid": uid}))
        return 0
    print(f"Invalid argument: unknown command {command!r}", file=sys.stderr)
    return 3


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
