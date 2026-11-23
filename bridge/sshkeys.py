#!/usr/bin/env python3
"""sshkeys — the keys in ~/.ssh/authorized_keys, read and edited as the person.

    sshkeys.py list                 JSON: {"path", "keys":[{index,type,comment,fingerprint,options}], "note"}
    sshkeys.py add --key TEXT       append one public key line
    sshkeys.py remove --index N     remove key N (0-based in the listed keys)

No root, no pkexec: authorized_keys is the user's own file. A continued line
(trailing backslash) is refused for editing because rewriting it safely is not
worth the complexity; the file is left alone. SHANI_SSH_KEYGEN overrides ssh-keygen.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

KEY_TYPES = ("ssh-", "ecdsa-sha2-", "sk-ssh-", "sk-ecdsa-")
B64 = re.compile(r"[A-Za-z0-9+/]+={0,2}$")


def path():
    return os.path.join(os.path.expanduser("~"), ".ssh", "authorized_keys")


def _keygen():
    return os.environ.get("SHANI_SSH_KEYGEN", "ssh-keygen")


def _read_lines(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return []


def _is_key_line(line):
    s = line.strip()
    if not s or s.startswith("#"):
        return False
    # options may precede type; find first key type token
    parts = s.split()
    for i, tok in enumerate(parts):
        if tok.startswith(KEY_TYPES):
            return i
    return False


def _parse_key(line):
    s = line.rstrip("\n")
    idx = _is_key_line(s)
    if idx is False:
        return None
    parts = s.split()
    options = " ".join(parts[:idx])
    rest = parts[idx:]
    ktype = rest[0] if rest else ""
    blob = rest[1] if len(rest) > 1 else ""
    comment = " ".join(rest[2:]) if len(rest) > 2 else ""
    return {"type": ktype, "blob": blob, "comment": comment, "options": options, "raw": s}


def _fingerprints(p, count):
    kg = _keygen()
    if not shutil.which(kg):
        return [], "ssh-keygen is not installed, so fingerprints cannot be shown."
    try:
        r = subprocess.run([kg, "-lf", p], capture_output=True, text=True, timeout=10)
    except Exception as exc:  # noqa: BLE001
        return [], f"Could not read fingerprints: {exc}"
    if r.returncode != 0:
        msg = (r.stderr or r.stdout).strip().splitlines()
        return [], msg[0] if msg else "ssh-keygen could not read the file."
    fps = []
    for line in r.stdout.splitlines():
        # "256 SHA256:... comment (ED25519)" or "256 SHA256:... no comment (ED25519)"
        m = re.search(r"(SHA256:\S+|MD5:[0-9a-f:]+)", line)
        fps.append(m.group(1) if m else line.split()[1] if len(line.split()) > 1 else "")
    if len(fps) != count:
        return [], "The fingerprint count did not match the keys, so none are shown."
    return fps, ""


def _has_continuation(lines):
    return any(l.rstrip().endswith("\\") and not l.rstrip().endswith("\\\\") for l in lines)


def cmd_list(_a):
    p = path()
    lines = _read_lines(p)
    keys = []
    note = ""
    if _has_continuation(lines):
        note = "This file has a continued line; it can be read but not edited here."
    for i, line in enumerate(lines):
        k = _parse_key(line)
        if k:
            keys.append({**k, "line": i})
    fps, fp_note = _fingerprints(p, len(keys))
    if fp_note and not note:
        note = fp_note
    for i, k in enumerate(keys):
        k["fingerprint"] = fps[i] if i < len(fps) else ""
        k.pop("blob", None)
        k.pop("raw", None)
    return {"path": p, "exists": os.path.exists(p), "keys": keys, "note": note,
            "editable": not _has_continuation(lines)}


def _validate_key(text):
    s = text.strip()
    if not s:
        return "Paste a public key."
    if "\n" in s or "\r" in s:
        return "Paste one key, not a whole file."
    parsed = _parse_key(s)
    if not parsed:
        return "That does not look like an SSH public key."
    if not parsed["type"].startswith(KEY_TYPES):
        return f"{parsed['type']} is not a key type this page accepts."
    if not B64.match(parsed["blob"]):
        return "The key data is not valid base64."
    return ""


def cmd_add(a):
    p = path()
    err = _validate_key(a.key or "")
    if err:
        return {"ok": False, "error": err}
    lines = _read_lines(p)
    if _has_continuation(lines):
        return {"ok": False, "error": "This file has a continued line and cannot be edited here."}
    os.makedirs(os.path.dirname(p), mode=0o700, exist_ok=True)
    # normalize: one key line
    parsed = _parse_key(a.key.strip())
    line = " ".join(x for x in [parsed["options"], parsed["type"], parsed["blob"], parsed["comment"]] if x)
    # don't duplicate exact same blob
    for k in lines:
        pk = _parse_key(k)
        if pk and pk["blob"] == parsed["blob"]:
            return {"ok": False, "error": "That key is already here."}
    new_lines = lines[:]
    if new_lines and new_lines[-1].strip():
        new_lines.append("")
    new_lines.append(line)
    with open(p, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines).rstrip("\n") + "\n")
    os.chmod(p, 0o600)
    return {"ok": True}


def cmd_remove(a):
    p = path()
    lines = _read_lines(p)
    if _has_continuation(lines):
        return {"ok": False, "error": "This file has a continued line and cannot be edited here."}
    # find the nth key line
    key_lines = [i for i, l in enumerate(lines) if _parse_key(l)]
    if a.index < 0 or a.index >= len(key_lines):
        return {"ok": False, "error": "That key is no longer there."}
    del lines[key_lines[a.index]]
    with open(p, "w", encoding="utf-8") as f:
        text = "\n".join(lines)
        f.write(text.rstrip("\n") + ("\n" if text.strip() else ""))
    if os.path.exists(p):
        os.chmod(p, 0o600)
    return {"ok": True}


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    a = sub.add_parser("add"); a.add_argument("--key", required=True)
    r = sub.add_parser("remove"); r.add_argument("--index", type=int, required=True)
    args = ap.parse_args()
    fn = {"list": cmd_list, "add": cmd_add, "remove": cmd_remove}[args.cmd]
    json.dump(fn(args), sys.stdout)
    print()


if __name__ == "__main__":
    main()
