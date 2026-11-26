#!/usr/bin/env python3
"""contacts — Phone's address book for the shell, as JSON.

    contacts.py list [QUERY]        [{uid, name, phone, email, ...}] sorted by name
    contacts.py search QUERY        same as list QUERY (live search)
    contacts.py add '<json>'        {"name": "…", "phone": "…", "email": "…", "groups": [], "self": false}
    contacts.py edit '<json>'       {"uid": "…", "name": "…", "phone": "…", "email": "…", "groups": [], "self": false}
    contacts.py delete '<json>'     {"uid": "…"} (a bare uid string is also read)
    contacts.py import '<path>'     a .vcf path, or '{"path": "…"}' (same contract)
    contacts.py get '<uid>'         one contact as JSON
    contacts.py vcard '<uid>'       one contact's raw vCard (for a QR code)
    contacts.py export-all [UIDS]   every card (or just these uids), as .vcf text
    contacts.py phone               [{uid, name, numbers, emails}] from the phone
    contacts.py save-phone '<json>' copy a phone contact here, with a fresh uid
    contacts.py delete-many '["uid", …]'   delete several cards at once
    contacts.py list [QUERY] [sort] sort: name (default), given or family

List prints a JSON array; writes print {"ok": true, "uid": "…"} (import prints
{"ok": true, "count": N}). Exit 3 is bad input (malformed JSON, no name, no uid,
unknown command). There is no "no service" state: an absent folder is an empty
book, and the first write creates it. The book lives in the shell's vCard folder —
`$XDG_DATA_HOME/shani-shell/contacts/` (see `phone/contacts.py`: `folder()` and
`paths.data_home()`) — one `.vcf` per contact, named by its UID.
`SHANI_CONTACTS_DIR` overrides that folder for tests.

The phone is a different, read-only source: `phone` asks the phone tools for
its contacts and never writes to the phone. `SHANI_CONTACTS_PHONE_TOOL`
overrides the reader for tests (argv in, JSON out; no arguments are passed).
`SHANI_PHONE_TOOL` stays reserved for the Phone service's own tool.

When `phone.contacts` is importable (the shell ships it in `bridge/`), its
`folder()` is the folder and its `parse`/`serialize` rules are the format's
source of truth — the subset re-implemented here writes the same vCard 4.0
and reads the same files. Standard library only.

No Evolution Data Server, no EDS/EBook bindings: the shell keeps its own
vCard files, and this tool reads exactly those.
"""

from __future__ import annotations

import calendar
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import unicodedata
import uuid
from pathlib import Path


def folder() -> Path:
    override = os.environ.get("SHANI_CONTACTS_DIR", "")
    if override:
        return Path(override)
    try:
        from phone import contacts as _link  # type: ignore

        return Path(_link.folder())
    except Exception:  # noqa: BLE001 - no package: the XDG rule below is the API's
        pass
    configured = os.environ.get("XDG_DATA_HOME", "")
    base = (
        Path(configured)
        if configured and Path(configured).is_absolute()
        else Path.home() / ".local" / "share"
    )
    return base / "shani-shell" / "contacts"


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
    joined = " ".join(
        p for p in (contact.get("given", ""), contact.get("family", "")) if p
    )
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
    names = fold_text(
        " ".join(
            (
                contact.get("name", ""),
                contact.get("given", ""),
                contact.get("family", ""),
            )
        )
    )
    if all(word in names for word in q.split()):
        return True
    if any(
        q in fold_text(item.get("address", "")) for item in contact.get("emails") or []
    ):
        return True
    wanted = digits(q)
    if len(wanted) >= 2:
        return any(
            wanted in digits(item.get("number", ""))
            for item in contact.get("phones") or []
        )
    return False


def sort_key(contact: dict, sort_by: str = "name") -> tuple[str, str]:
    if sort_by == "family":
        return (fold_text(contact.get("family", "")), fold_text(_display(contact)))
    if sort_by == "given":
        return (fold_text(contact.get("given", "")), fold_text(_display(contact)))
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
            cur.append(value[i : i + 2])
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


def _param(head: str, key: str) -> str:
    """A vCard parameter (e.g. TYPE=work) from a property's head."""
    for part in _split(head, ";"):
        name, sep, value = part.partition("=")
        if sep and name.strip().upper() == key:
            return value.strip().strip('"')
    return ""


def _type(value: str, default: str) -> str:
    """The first TYPE the form understands; 'cell' is vCard's mobile."""
    for label in _split(value, ","):
        label = label.strip().strip('"').lower()
        if label in ("home", "work", "mobile", "cell", "other"):
            return "mobile" if label == "cell" else label
    return default


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
            current = {
                "uid": "",
                "name": "",
                "given": "",
                "family": "",
                "phones": [],
                "emails": [],
                "groups": [],
                "self": False,
                "favorite": False,
                "avatar": "",
                "birthday": "",
                "addresses": [],
                "org": "",
                "role": "",
                "urls": [],
                "note": "",
                "extras": [],
            }
            continue
        if current is None:
            continue
        # Unknown properties (X-*, PRODID, …) stay verbatim so a later save
        # cannot silently destroy them. The fields the editor owns are parsed
        # into named values and written back by serialize().
        if name not in (
            "BEGIN",
            "VERSION",
            "UID",
            "FN",
            "N",
            "TEL",
            "EMAIL",
            "CATEGORIES",
            "X-SHANI-SELF",
            "X-SHANI-FAVORITE",
            "PHOTO",
            "BDAY",
            "ADR",
            "ORG",
            "ROLE",
            "NOTE",
            "URL",
            "END",
        ):
            current["extras"].append(line)
            continue
        if name == "END":
            if (
                _display(current) != "Unnamed contact"
                or current["phones"]
                or current["emails"]
            ):
                current["name"] = (
                    _display(current) if not current["name"] else current["name"]
                )
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
                current["phones"].append(
                    {"type": _type(_param(head, "TYPE"), "mobile"), "number": number}
                )
        elif name == "EMAIL":
            address = re.sub(r"^mailto:", "", _unescape(value).strip(), flags=re.I)
            if address:
                current["emails"].append(
                    {"type": _type(_param(head, "TYPE"), "home"), "address": address}
                )
        elif name == "CATEGORIES":
            for group in _split(value, ","):
                group = _unescape(group).strip()
                if group and group not in current["groups"]:
                    current["groups"].append(group)
        elif name == "X-SHANI-SELF":
            current["self"] = value.strip().lower() in ("1", "true", "yes")
        elif name == "X-SHANI-FAVORITE":
            current["favorite"] = value.strip().lower() in ("1", "true", "yes")
        elif name == "PHOTO":
            current["avatar"] = _unescape(value.strip())
        elif name == "BDAY":
            current["birthday"] = value
        elif name == "ADR":
            parts = [_unescape(p) for p in _split(value, ";")] + [""] * 7
            current["addresses"].append(
                {
                    "type": _type(_param(head, "TYPE"), "home"),
                    "po": parts[0],
                    "extended": parts[1],
                    "street": parts[2],
                    "locality": parts[3],
                    "region": parts[4],
                    "code": parts[5],
                    "country": parts[6],
                }
            )
        elif name == "ORG":
            current["org"] = _unescape(_split(value, ";")[0])
        elif name == "ROLE":
            current["role"] = _unescape(value)
        elif name == "NOTE":
            current["note"] = _unescape(value)
        elif name == "URL":
            # A URI is not vCard text: commas and semicolons belong to it.
            current["urls"].append(value)
    for c in found:
        if not c["name"]:
            joined = " ".join(p for p in (c.get("given", ""), c.get("family", "")) if p)
            c["name"] = joined.strip()
    return found


# --- vCard: writing (4.0, as Phone's serialize writes) ------------------------


def _escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\r\n", "\n")
        .replace("\n", "\\n")
    )


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
        number = (
            (item.get("number") or "").strip()
            if isinstance(item, dict)
            else str(item).strip()
        )
        if number:
            lines.append(
                f"TEL;TYPE={item.get('type', 'cell') if isinstance(item, dict) else 'cell'}:{_escape(number)}"
            )
    for item in contact.get("emails") or []:
        address = (
            (item.get("address") or "").strip()
            if isinstance(item, dict)
            else str(item).strip()
        )
        if address:
            lines.append(
                f"EMAIL;TYPE={item.get('type', 'home') if isinstance(item, dict) else 'home'}:{_escape(address)}"
            )
    groups = [str(g).strip() for g in (contact.get("groups") or []) if str(g).strip()]
    if groups:
        lines.append("CATEGORIES:" + ",".join(_escape(g) for g in groups))
    if contact.get("self"):
        lines.append("X-SHANI-SELF:1")
    if contact.get("favorite"):
        lines.append("X-SHANI-FAVORITE:1")
    if contact.get("avatar"):
        lines.append("PHOTO;VALUE=URI:" + _escape(str(contact["avatar"])))
    if str(contact.get("birthday", "")).strip():
        lines.append("BDAY:" + str(contact["birthday"]).strip())
    for item in contact.get("addresses") or []:
        if not isinstance(item, dict):
            continue
        parts = [
            _escape(str(item.get(key, "") or ""))
            for key in (
                "po",
                "extended",
                "street",
                "locality",
                "region",
                "code",
                "country",
            )
        ]
        kind = _type(str(item.get("type", "home")), "home")
        lines.append(f"ADR;TYPE={kind}:" + ";".join(parts))
    if str(contact.get("org", "")).strip():
        lines.append("ORG:" + _escape(str(contact["org"])))
    if str(contact.get("role", "")).strip():
        lines.append("ROLE:" + _escape(str(contact["role"])))
    if str(contact.get("note", "")).strip():
        lines.append("NOTE:" + _escape(str(contact["note"])))
    for url in contact.get("urls") or []:
        value = str(url).strip()
        if value:
            lines.append("URL:" + value)
    # a card read before these fields were owned may still carry them in extras
    owned = {"BDAY", "ADR", "ORG", "ROLE", "NOTE", "URL"}
    for extra in contact.get("extras") or []:
        head = extra.split(":", 1)[0].split(".")[-1].split(";", 1)[0].strip().upper()
        if head in owned:
            continue
        if ":" in extra and extra not in lines:
            lines.append(extra)
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
    phones = [
        {"type": p.get("type", "cell"), "number": p.get("number", "")}
        for p in contact.get("phones") or []
    ]
    emails = [
        {"type": e.get("type", "home"), "address": e.get("address", "")}
        for e in contact.get("emails") or []
    ]
    return {
        "uid": contact.get("uid", ""),
        "name": contact.get("name") or _display(contact),
        "given": contact.get("given", ""),
        "family": contact.get("family", ""),
        "phone": phones[0]["number"] if phones else "",
        "email": emails[0]["address"] if emails else "",
        "phones": phones,
        "emails": emails,
        "groups": list(contact.get("groups") or []),
        "self": bool(contact.get("self", False)),
        "favorite": bool(contact.get("favorite", False)),
        "avatar": str(contact.get("avatar", "") or ""),
        "birthday": str(contact.get("birthday", "") or ""),
        "addresses": [
            {
                k: str(v or "")
                for k, v in (address or {}).items()
                if k
                in (
                    "type",
                    "po",
                    "extended",
                    "street",
                    "locality",
                    "region",
                    "code",
                    "country",
                )
            }
            for address in (contact.get("addresses") or [])
            if isinstance(address, dict)
        ],
        "org": str(contact.get("org", "") or ""),
        "role": str(contact.get("role", "") or ""),
        "urls": [str(u) for u in (contact.get("urls") or []) if str(u).strip()],
        "note": str(contact.get("note", "") or ""),
    }


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


def list_contacts(query: str = "", sort_by: str = "name") -> list[dict]:
    contacts = [c for c in all_contacts() if matches(c, query)]
    contacts.sort(key=lambda c: sort_key(c, sort_by))
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


def _make(
    name: str,
    phone: str,
    email: str,
    uid: str = "",
    groups=None,
    is_self: bool = False,
) -> dict:
    given, family = _split_name(name)
    return {
        "uid": uid,
        "name": name.strip(),
        "given": given,
        "family": family,
        "phones": [{"type": "cell", "number": phone.strip()}]
        if (phone or "").strip()
        else [],
        "emails": [{"type": "home", "address": email.strip()}]
        if (email or "").strip()
        else [],
        "groups": [str(g).strip() for g in (groups or []) if str(g).strip()],
        "self": bool(is_self),
        "favorite": False,
        "avatar": "",
    }


def _from_payload(payload: dict, name: str) -> dict:
    """Build a contact from a UI payload, honouring typed phones/emails arrays.

    The old path read only the `phone`/`email` strings, so a duplicate merge
    (which sends arrays) silently saved a card with no phone or email at all.
    """
    phones = payload.get("phones")
    emails = payload.get("emails")
    if not isinstance(phones, list):
        phones = (
            [{"type": "cell", "number": str(payload.get("phone", "")).strip()}]
            if str(payload.get("phone", "")).strip()
            else []
        )
    if not isinstance(emails, list):
        emails = (
            [{"type": "home", "address": str(payload.get("email", "")).strip()}]
            if str(payload.get("email", "")).strip()
            else []
        )
    return {
        "uid": str(payload.get("uid", "")),
        "name": name.strip(),
        "given": str(payload.get("given", "")),
        "family": str(payload.get("family", "")),
        "phones": [
            {"type": p.get("type", "cell"), "number": str(p.get("number", ""))}
            for p in phones
            if isinstance(p, dict) and str(p.get("number", "")).strip()
        ],
        "emails": [
            {"type": e.get("type", "home"), "address": str(e.get("address", ""))}
            for e in emails
            if isinstance(e, dict) and str(e.get("address", "")).strip()
        ],
        "groups": [
            str(g).strip() for g in (payload.get("groups") or []) if str(g).strip()
        ],
        "self": bool(payload.get("self", False)),
        "favorite": bool(payload.get("favorite", False)),
        "avatar": str(payload.get("avatar", "") or ""),
        "birthday": str(payload.get("birthday", "") or "").strip(),
        "addresses": [
            {
                key: str(item.get(key, "") or "")
                for key in (
                    "type",
                    "po",
                    "extended",
                    "street",
                    "locality",
                    "region",
                    "code",
                    "country",
                )
            }
            for item in (payload.get("addresses") or [])
            if isinstance(item, dict)
            and any(
                str(item.get(k, "") or "").strip()
                for k in (
                    "street",
                    "locality",
                    "region",
                    "code",
                    "country",
                    "po",
                    "extended",
                )
            )
        ],
        "org": str(payload.get("org", "") or "").strip(),
        "role": str(payload.get("role", "") or "").strip(),
        "urls": [str(u).strip() for u in (payload.get("urls") or []) if str(u).strip()],
        "note": str(payload.get("note", "") or ""),
    }


# --- the phone's book (read-only) and bulk actions -------------------------------


def phone_contacts() -> list[dict]:
    """Contacts on the connected phone, or [] when none is connected.

    The phone tools own the read; this bridge only normalises their answer.
    SHANI_CONTACTS_PHONE_TOOL replaces that reader in tests. No arguments are
    passed to it, so a stand-in can reject options the real reader rejects.
    """
    override = shlex.split(os.environ.get("SHANI_CONTACTS_PHONE_TOOL", ""))
    tool = override or [
        sys.executable,
        str(Path(__file__).with_name("android_tools.py")),
        "contacts",
        "list",
    ]
    try:
        done = subprocess.run(tool, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return []
    if done.returncode != 0:
        return []
    try:
        data = json.loads(done.stdout)
    except (json.JSONDecodeError, TypeError):
        return []
    if isinstance(data, dict):
        data = data.get("contacts") or []
    if not isinstance(data, list):
        return []
    rows = []
    for item in data:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        numbers = [
            str(n).strip()
            for n in (
                item.get("numbers") or ([item["number"]] if item.get("number") else [])
            )
            if str(n).strip()
        ]
        emails = [
            str(e).strip()
            for e in (
                item.get("emails") or ([item["email"]] if item.get("email") else [])
            )
            if str(e).strip()
        ]
        if not name and not numbers and not emails:
            continue
        rows.append(
            {
                "uid": str(item.get("uid") or "").strip()
                or ("phone:" + (name or numbers[0])),
                "name": name or numbers[0],
                "numbers": numbers,
                "emails": emails,
            }
        )
    return rows


def save_phone(contact: dict) -> dict:
    """Copy one phone contact here under a fresh uid; never overwrite a card."""
    if not isinstance(contact, dict):
        raise ValueError("expected a JSON object")
    name = str(contact.get("name") or "").strip()
    numbers = [str(n).strip() for n in (contact.get("numbers") or []) if str(n).strip()]
    emails = [str(e).strip() for e in (contact.get("emails") or []) if str(e).strip()]
    if not name and not numbers and not emails:
        raise ValueError("a phone contact needs a name or a number")
    shown = name or numbers[0]
    payload = {
        "name": shown,
        "phones": [{"type": "cell", "number": n} for n in numbers],
        "emails": [{"type": "home", "address": e} for e in emails],
    }
    return save(_from_payload(payload, shown))


def delete_contacts(uids: list[str]) -> dict:
    """Delete several cards once: say what went and what was already missing."""
    deleted, missing = [], []
    for uid in dict.fromkeys(uids):
        target = str(uid).strip()
        if not target:
            continue
        (deleted if delete_contact(target) else missing).append(target)
    return {"ok": True, "deleted": deleted, "missing": missing}


def valid_birthday(value: str) -> bool:
    """YYYY-MM-DD or --MM-DD, with a real month and day."""
    text = str(value or "").strip()
    if not text:
        return True
    if re.fullmatch(r"--\d{2}-\d{2}", text):
        year, month, day = 2000, int(text[2:4]), int(text[5:7])
    else:
        found = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", text)
        if not found:
            return False
        year, month, day = (int(part) for part in found.groups())
    try:
        return 1 <= month <= 12 and 1 <= day <= calendar.monthrange(year, month)[1]
    except ValueError:
        return False


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: contacts.py list [QUERY] | add|edit|delete '<json>' | import PATH",
            file=sys.stderr,
        )
        return 3
    command = argv[1]
    if command == "phone":
        print(json.dumps(phone_contacts(), ensure_ascii=False))
        return 0
    if command in ("save-phone", "delete-many"):
        if len(argv) < 3:
            print(f"Invalid argument: {command} needs a value", file=sys.stderr)
            return 3
        try:
            payload = json.loads(argv[2])
        except json.JSONDecodeError as exc:
            print(f"Invalid argument: {exc}", file=sys.stderr)
            return 3
        if command == "save-phone":
            try:
                saved = save_phone(payload)
            except ValueError as exc:
                print(f"Invalid argument: {exc}", file=sys.stderr)
                return 3
            print(json.dumps({"ok": True, "uid": saved["uid"]}))
            return 0
        if isinstance(payload, dict):
            payload = payload.get("uids")
        if not isinstance(payload, list):
            print("Invalid argument: delete-many needs a list of uids", file=sys.stderr)
            return 3
        print(json.dumps(delete_contacts([str(uid) for uid in payload])))
        return 0
    if command in ("list", "search"):
        query = argv[2] if len(argv) > 2 else ""
        sort_by = argv[3] if len(argv) > 3 else "name"
        if sort_by not in ("name", "given", "family"):
            print(
                "Invalid argument: sort must be name, given or family", file=sys.stderr
            )
            return 3
        print(json.dumps(list_contacts(query, sort_by), ensure_ascii=False))
        return 0
    if command in ("add", "edit", "delete", "import", "get", "vcard", "export-all"):
        if len(argv) < 3 and command != "export-all":
            print(f"Invalid argument: {command} needs a value", file=sys.stderr)
            return 3
        raw = argv[2] if len(argv) > 2 else ""
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
        if command == "vcard":
            found = get_contact(raw)
            if found is None:
                print(f"Invalid argument: no contact with uid {raw!r}", file=sys.stderr)
                return 3
            print(_file(raw).read_text(encoding="utf-8", errors="replace"), end="")
            return 0
        if command == "export-all":
            uids = None
            if raw:
                try:
                    asked = json.loads(raw)
                except json.JSONDecodeError as exc:
                    print(f"Invalid argument: {exc}", file=sys.stderr)
                    return 3
                if not isinstance(asked, list):
                    print(
                        "Invalid argument: export-all needs a list of uids",
                        file=sys.stderr,
                    )
                    return 3
                uids = set(str(uid) for uid in asked)
            for card in all_contacts():
                if uids is not None and card["uid"] not in uids:
                    continue
                source = _file(card["uid"])
                if source.is_file():
                    print(source.read_text(encoding="utf-8", errors="replace"), end="")
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
        if command in ("add", "edit") and not valid_birthday(
            payload.get("birthday", "")
        ):
            print(
                "Invalid argument: birthday must be year-month-day or --month-day",
                file=sys.stderr,
            )
            return 3
        if command == "add":
            name = str(payload.get("name", "")).strip()
            if not name:
                print("Invalid argument: a contact needs a name", file=sys.stderr)
                return 3
            saved = save(_from_payload(payload, name))
            print(json.dumps({"ok": True, "uid": saved["uid"]}))
            return 0
        if command == "edit":
            uid = str(payload.get("uid", "")).strip()
            name = str(payload.get("name", "")).strip()
            if not uid or not name:
                print("Invalid argument: edit needs a uid and a name", file=sys.stderr)
                return 3
            existing = get_contact(uid)
            if existing is None:
                print(f"Invalid argument: no contact with uid {uid!r}", file=sys.stderr)
                return 3
            edited = _from_payload(payload, name)
            edited["uid"] = uid
            if "groups" not in payload:
                edited["groups"] = list(existing.get("groups") or [])
            if "self" not in payload:
                edited["self"] = bool(existing.get("self"))
            if "favorite" not in payload:
                edited["favorite"] = bool(existing.get("favorite"))
            if "avatar" not in payload:
                edited["avatar"] = str(existing.get("avatar", "") or "")
            # Editing only the fields the UI owns must not drop the others.
            for key, empty in (
                ("birthday", ""),
                ("addresses", []),
                ("org", ""),
                ("role", ""),
                ("urls", []),
                ("note", ""),
            ):
                if key not in payload:
                    edited[key] = existing.get(key) or empty
            edited["extras"] = existing.get("extras", [])
            saved = save(edited)
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
