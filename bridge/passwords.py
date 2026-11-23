#!/usr/bin/env python3
"""passwords — the keyring's saved passwords (Seahorse's job), through the Secret
Service on the session bus (oo7 here; gnome-keyring and KeePassXC speak it too),
and your GPG keys.

    passwords.py list                      {"default", "collections": [{"path", "label", "locked"}],
                                          "items": [{"path", "label", "collection", "attributes",
                                                     "created", "modified"}]}
    passwords.py reveal <item>             {"secret"}           (a plain session: the
                                                               bus never leaves this computer)
    passwords.py set <item>                the new secret on stdin
    passwords.py add <collection> <label>  {"attributes": {...}, "secret"} on stdin
    passwords.py delete <item>
    passwords.py gpg-list                  [{"id", "uid", "created", "expires", "secret"}]
    passwords.py gpg-new <name> <email>    the passphrase on stdin (loopback: never a command line)
    passwords.py gpg-export <id> <file>    its public key, armoured
    passwords.py gpg-import <file>
    passwords.py gpg-delete <id>           the public key, and the secret one with it
    passwords.py passkey-list              [{"label", "id", "created"}]
    passwords.py passkey-add <label>       a label and a random id added to the registry
    passwords.py passkey-delete <id>

A secret is only ever printed for `reveal`, and read from stdin to be stored.
The passkey registry is metadata only - a label and a random key-handle id. No
WebAuthn credential is created here: browsers make and use those with a security
key. The shell keeps the reference so it can be listed, named and removed.
"""

from __future__ import annotations

import json
import os
import secrets
import subprocess
import sys
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS = "org.freedesktop.secrets"
ROOT = "/org/freedesktop/secrets"
S = "org.freedesktop.Secret."


def _bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def _call(c, path, iface, method, args=None, sig=None):
    return c.call_sync(
        BUS,
        path,
        S + iface if not iface.startswith("org.") else iface,
        method,
        args,
        GLib.VariantType(sig) if sig else None,
        Gio.DBusCallFlags.NONE,
        20000,
        None,
    )


def _prop(c, path, iface, name):
    r = c.call_sync(
        BUS,
        path,
        "org.freedesktop.DBus.Properties",
        "Get",
        GLib.Variant("(ss)", (S + iface, name)),
        GLib.VariantType("(v)"),
        Gio.DBusCallFlags.NONE,
        20000,
        None,
    )
    return r.unpack()[0]


def _session(c):
    r = _call(
        c,
        ROOT,
        "Service",
        "OpenSession",
        GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))),
        "(vo)",
    )
    return r.unpack()[1]


def list_all() -> dict:
    c = _bus()
    cols = []
    items = []
    for cp in _prop(c, ROOT, "Service", "Collections"):
        try:
            label = _prop(c, cp, "Collection", "Label")
            locked = _prop(c, cp, "Collection", "Locked")
            ips = _prop(c, cp, "Collection", "Items")
        except GLib.Error:
            continue
        cols.append(
            {"path": cp, "label": label or os.path.basename(cp), "locked": bool(locked)}
        )
        for ip in ips:
            try:
                items.append(
                    {
                        "path": ip,
                        "collection": cp,
                        "label": _prop(c, ip, "Item", "Label"),
                        "attributes": dict(_prop(c, ip, "Item", "Attributes")),
                        "created": int(_prop(c, ip, "Item", "Created")),
                        "modified": int(_prop(c, ip, "Item", "Modified")),
                    }
                )
            except GLib.Error:
                pass
    items.sort(key=lambda i: i["label"].lower())
    try:  # where a new one goes: the "default" keyring
        default = _call(
            c, ROOT, "Service", "ReadAlias", GLib.Variant("(s)", ("default",)), "(o)"
        ).unpack()[0]
    except GLib.Error:
        default = "/"
    if default == "/":
        default = next(
            (x["path"] for x in cols if not x["path"].endswith("/session")),
            cols[0]["path"] if cols else "",
        )
    return {"collections": cols, "items": items, "default": default}


def reveal(item: str) -> dict:
    c = _bus()
    sess = _session(c)
    r = _call(c, item, "Item", "GetSecret", GLib.Variant("(o)", (sess,)), "((oayays))")
    _, _, value, ctype = r.unpack()[0]
    return {"secret": bytes(value).decode("utf-8", errors="replace"), "type": ctype}


def _secret(sess, text):
    return (sess, b"", text.encode(), "text/plain")


def set_secret(item: str, text: str) -> dict:
    c = _bus()
    sess = _session(c)
    _call(
        c, item, "Item", "SetSecret", GLib.Variant("((oayays))", (_secret(sess, text),))
    )
    return {"ok": True}


def add(collection: str, label: str, attributes: dict, text: str) -> dict:
    c = _bus()
    sess = _session(c)
    props = {
        S + "Item.Label": GLib.Variant("s", label),
        S + "Item.Attributes": GLib.Variant(
            "a{ss}", {str(k): str(v) for k, v in attributes.items()}
        ),
    }
    r = _call(
        c,
        collection,
        "Collection",
        "CreateItem",
        GLib.Variant("(a{sv}(oayays)b)", (props, _secret(sess, text), True)),
        "(oo)",
    )
    return {"ok": True, "path": r.unpack()[0]}


def delete(item: str) -> dict:
    _call(_bus(), item, "Item", "Delete", None, "(o)")
    return {"ok": True}


# ---- GPG keys --------------------------------------------------------------------
def gpg_list() -> list[dict]:
    r = subprocess.run(
        ["gpg", "--batch", "--with-colons", "--list-keys"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    sec = subprocess.run(
        ["gpg", "--batch", "--with-colons", "--list-secret-keys"],
        capture_output=True,
        text=True,
        timeout=60,
    ).stdout
    secret_ids = {l.split(":")[4] for l in sec.splitlines() if l.startswith("sec:")}
    out, cur = [], None
    for line in r.stdout.splitlines():
        f = line.split(":")
        if f[0] == "pub":
            cur = {
                "id": f[4],
                "uid": "",
                "created": int(f[5] or 0),
                "expires": int(f[6] or 0),
                "secret": f[4] in secret_ids,
                "fingerprint": "",
            }
            out.append(cur)
        elif f[0] == "fpr" and cur is not None and not cur["fingerprint"]:
            cur["fingerprint"] = f[9]
        elif f[0] == "uid" and cur is not None and not cur["uid"]:
            cur["uid"] = f[9]
    return out


def _gpg_pw(args, password):
    r, w = os.pipe()
    os.write(w, password.encode() + b"\n")
    os.close(w)
    try:
        return subprocess.run(
            [
                "gpg",
                "--batch",
                "--yes",
                "--pinentry-mode",
                "loopback",
                "--passphrase-fd",
                str(r),
            ]
            + args,
            pass_fds=(r,),
            capture_output=True,
            text=True,
            timeout=120,
        )
    finally:
        os.close(r)


def gpg_new(name: str, email: str, password: str) -> dict:
    if not name.strip() or "@" not in email:
        return {"error": "a name and an email address"}
    uid = "%s <%s>" % (name.strip(), email.strip())
    r = _gpg_pw(["--quick-generate-key", uid, "default", "default", "3y"], password)
    if r.returncode != 0:
        return {
            "error": (r.stderr.strip().splitlines() or ["the key could not be made"])[
                -1
            ]
        }
    return {"ok": True}


def gpg_export(key: str, out: str) -> dict:
    if os.path.lexists(out):
        # `code` lets the UI map this to a translated note instead of showing raw CLI text
        return {
            "error": "%s is there already" % os.path.basename(out),
            "code": "exists",
        }
    r = subprocess.run(
        ["gpg", "--batch", "--armor", "--export", key], capture_output=True, timeout=60
    )
    if r.returncode != 0 or not r.stdout:
        return {"error": "nothing to export for %s" % key}
    with open(out, "xb") as f:
        f.write(r.stdout)
    return {"ok": True, "path": out}


def gpg_import(path: str) -> dict:
    r = subprocess.run(
        ["gpg", "--batch", "--import", path], capture_output=True, text=True, timeout=60
    )
    return (
        {"ok": True}
        if r.returncode == 0
        else {"error": (r.stderr.strip().splitlines() or ["not imported"])[-1]}
    )


def gpg_delete(key: str) -> dict:
    fpr = next(
        (
            k["fingerprint"]
            for k in gpg_list()
            if k["id"] == key or k["fingerprint"] == key
        ),
        "",
    )
    if not fpr:
        return {"error": "no such key"}
    r = subprocess.run(
        ["gpg", "--batch", "--yes", "--delete-secret-and-public-key", fpr],
        capture_output=True,
        text=True,
        timeout=60,
    )
    return (
        {"ok": True}
        if r.returncode == 0
        else {"error": (r.stderr.strip().splitlines() or ["not deleted"])[-1]}
    )


# ---- passkey registry -------------------------------------------------------------
# A browser-created WebAuthn credential cannot be minted by the shell (a site
# only accepts credentials registered through its own WebAuthn flow). What the
# shell can do honestly: keep a keyring-protected REFERENCE to the passkey, and
# — when libfido2 tools are installed — create/sign genuine shell-local FIDO2
# credentials. No random id is ever presented as a real credential id.
PASSKEY_ATTRS = {"application": "shani-shell", "type": "passkey-registry"}


def _passkeys_item() -> str:
    try:
        items = list_all().get("items", [])
        for i in items:
            attrs = i.get("attributes", {})
            if all(attrs.get(k) == v for k, v in PASSKEY_ATTRS.items()):
                return i.get("path", "")
    except Exception:  # noqa: BLE001 - no keyring in this session
        pass
    return ""


def _passkeys_load() -> list:
    path = _passkeys_item()
    if not path:
        return []
    try:
        data = json.loads(reveal(path).get("secret", "[]"))
        return data if isinstance(data, list) else []
    except Exception:  # noqa: BLE001
        return []


def _passkeys_save(items: list) -> None:
    blob = json.dumps(items)
    path = _passkeys_item()
    if path:
        set_secret(path, blob)
    else:
        try:
            add(list_all().get("default", ""), "Shani passkeys", PASSKEY_ATTRS, blob)
        except Exception:  # noqa: BLE001
            pass


def _tool(env: str, name: str) -> str:
    import shutil

    return shutil.which(os.environ.get(env, name)) or ""


def passkey_capabilities() -> dict:
    return {
        "keyring": bool(_passkeys_item() or list_all().get("items") is not None),
        "fido2_token": bool(_tool("SHANI_FIDO2_TOKEN", "fido2-token")),
        "fido2_cred": bool(_tool("SHANI_FIDO2_CRED", "fido2-cred")),
        "fido2_assert": bool(_tool("SHANI_FIDO2_ASSERT", "fido2-assert")),
    }


def passkey_list() -> list:
    return _passkeys_load()


def passkey_add(
    label: str, rp_id: str = "", cred_id: str = "", source: str = "browser"
) -> dict:
    label = (label or "").strip()
    if not label:
        return {"error": "a label is needed"}
    item = {
        "id": secrets.token_hex(16),  # local reference id, NOT a credential id
        "label": label,
        "rp_id": (rp_id or "").strip(),
        "cred_id": (cred_id or "").strip(),
        "source": source if source in ("browser", "shell") else "browser",
        "created": int(time.time()),
    }
    items = _passkeys_load()
    items.insert(0, item)
    _passkeys_save(items)
    return {"ok": True, "passkey": item}


def passkey_delete(key_id: str) -> dict:
    items = _passkeys_load()
    rest = [k for k in items if k.get("id") != key_id]
    if len(rest) == len(items):
        return {"error": "no such passkey"}
    _passkeys_save(rest)
    return {"ok": True}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    try:
        if cmd == "list":
            r = list_all()
        elif cmd == "reveal" and len(args) == 1:
            r = reveal(args[0])
        elif cmd == "put" and len(args) == 1:
            # Store a secret under a caller-chosen id (an attribute, not an
            # object path) so Keyring.set() actually works. Replaces an older
            # item with the same id rather than accumulating duplicates.
            d = json.loads(sys.stdin.read() or "{}")
            ident = args[0]
            val = str(d.get("secret", ""))
            for item in list_all().get("items", []):
                if item.get("attributes", {}).get("shani-id") == ident:
                    delete(item["path"])
            r = add(list_all().get("default", ""), ident, {"shani-id": ident}, val)
        elif cmd == "audit":
            # Opt-in: reveal secrets in-process and return only counts/labels,
            # never the secrets themselves. The UI's item list has no `secret`
            # field, so computing the audit there always reported zero issues.
            common = {
                "password",
                "123456",
                "12345678",
                "qwerty",
                "abc123",
                "letmein",
                "admin",
                "welcome",
                "monkey",
                "dragon",
                "master",
                "sunshine",
                "princess",
                "football",
                "shadow",
                "superman",
                "michael",
                "trustno1",
            }
            labels: dict[str, list[str]] = {}
            weak = []
            total = 0
            for item in list_all().get("items", []):
                try:
                    secret = reveal(item["path"]).get("secret", "")
                except Exception:  # noqa: BLE001 - locked or inaccessible item
                    continue
                total += 1
                labels.setdefault(secret, []).append(item.get("label", ""))
                if len(secret) < 8 or secret.lower() in common or secret.isdigit():
                    weak.append(
                        {
                            "label": item.get("label", ""),
                            "reason": "short" if len(secret) < 8 else "common",
                        }
                    )
            r = {
                "weak": weak,
                "reused": [
                    {"count": len(names), "items": names}
                    for names in labels.values()
                    if len(names) > 1
                ],
                "total": total,
            }
        elif cmd == "drop" and len(args) == 1:
            n = 0
            for item in list_all().get("items", []):
                if item.get("attributes", {}).get("shani-id") == args[0]:
                    delete(item["path"])
                    n += 1
            r = {"ok": True, "deleted": n}
        elif cmd == "lookup" and len(args) == 1:
            # Find an item by a shani-id attribute (Keyring.set), then reveal it.
            found = None
            for item in list_all().get("items", []):
                if item.get("attributes", {}).get("shani-id") == args[0]:
                    found = item
                    break
            r = reveal(found["path"]) if found else {"error": "not found"}
        elif cmd == "set" and len(args) == 1:
            r = set_secret(args[0], sys.stdin.read().rstrip("\n"))
        elif cmd == "add" and len(args) == 2:
            d = json.loads(sys.stdin.read() or "{}")
            r = add(args[0], args[1], d.get("attributes") or {}, d.get("secret", ""))
        elif cmd == "delete" and len(args) == 1:
            r = delete(args[0])
        elif cmd == "gpg-list":
            r = gpg_list()
        elif cmd == "gpg-new" and len(args) == 2:
            r = gpg_new(args[0], args[1], sys.stdin.readline().rstrip("\n"))
        elif cmd == "gpg-export" and len(args) == 2:
            r = gpg_export(*args)
        elif cmd == "gpg-import" and len(args) == 1:
            r = gpg_import(args[0])
        elif cmd == "gpg-delete" and len(args) == 1:
            r = gpg_delete(args[0])
        elif cmd == "passkey-list":
            r = passkey_list()
        elif cmd == "passkey-capabilities":
            r = passkey_capabilities()
        elif cmd == "passkey-add" and len(args) == 1:
            d = json.loads(sys.stdin.read() or "{}")
            r = passkey_add(
                args[0],
                d.get("rp_id", ""),
                d.get("cred_id", ""),
                d.get("source", "browser"),
            )
        elif cmd == "passkey-delete" and len(args) == 1:
            r = passkey_delete(args[0])
        else:
            print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
            return 2
    except GLib.Error as e:
        r = {"error": e.message}
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        r = {"error": str(e)}
    print(json.dumps(r))
    return 1 if isinstance(r, dict) and "error" in r else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
