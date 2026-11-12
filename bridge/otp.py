#!/usr/bin/env python3
"""otp — two-factor codes (TOTP, RFC 6238) for the Authenticator, with the
secrets in the keyring.

    otp.py list                  [{"id", "issuer", "account", "code", "period", "digits", "remaining"}]
    otp.py add 'otpauth://totp/Issuer:me@example.com?secret=…&issuer=…'
    otp.py add '{"issuer": …, "account": …, "secret": "BASE32", "digits": 6, "period": 30, "algorithm": "SHA1"}'
    otp.py remove ID
    otp.py scan-screen           the person picks part of the screen (slurp), the
                                 QR code there is read (grim + zbarimg) and added

The secrets are kept by the Secret Service (gnome-keyring, the one the image
runs and unlocks at sign-in), one item an account, under the schema
"dev.shani.otp" - never in a file of the shell's, never printed: `list` gives
the codes, not the secrets. Exit 2 when there is no Secret Service, 3 on bad
input (a URI that is not a TOTP one, a secret that is not base32).

This is for the person's accounts on websites and apps. One-time codes for
signing in to this computer (pam_oath) are Cassini's (Security > TOTP).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import struct
import subprocess
import sys
import time
import uuid
from urllib.parse import parse_qs, unquote, urlparse

SCHEMA_NAME = "dev.shani.otp"
ALGORITHMS = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}


# ---- the codes: pure, tested against RFC 6238's own table -----------------------
def b32decode(secret: str) -> bytes:
    s = secret.replace(" ", "").replace("-", "").upper()
    s += "=" * (-len(s) % 8)
    try:
        key = base64.b32decode(s, casefold=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise ValueError("the secret is not base32") from exc
    if not key:
        raise ValueError("the secret is empty")
    return key


def totp(key: bytes, at: float, period: int = 30, digits: int = 6, algorithm: str = "SHA1") -> str:
    counter = int(at // period)
    mac = hmac.new(key, struct.pack(">Q", counter), ALGORITHMS[algorithm]).digest()
    offset = mac[-1] & 0x0F
    number = struct.unpack(">I", mac[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(number % (10 ** digits)).zfill(digits)


def parse(text: str) -> dict:
    """An otpauth:// URI, or the same fields as JSON, into a checked entry."""
    text = text.strip()
    if text.startswith("otpauth://"):
        u = urlparse(text)
        if u.netloc != "totp":
            raise ValueError("only time-based codes (otpauth://totp/…) are supported")
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        label = unquote(u.path.lstrip("/"))
        issuer, _, account = label.partition(":") if ":" in label else ("", "", label)
        entry = {"issuer": q.get("issuer") or issuer.strip(), "account": account.strip(), "secret": q.get("secret", ""),
                 "digits": int(q.get("digits", 6)), "period": int(q.get("period", 30)), "algorithm": q.get("algorithm", "SHA1").upper()}
    else:
        try:
            entry = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError("not an otpauth:// address") from exc
        if not isinstance(entry, dict):
            raise ValueError("not an otpauth:// address")
        entry = {"issuer": str(entry.get("issuer", "")).strip(), "account": str(entry.get("account", "")).strip(),
                 "secret": str(entry.get("secret", "")), "digits": int(entry.get("digits", 6)),
                 "period": int(entry.get("period", 30)), "algorithm": str(entry.get("algorithm", "SHA1")).upper()}
    if entry["algorithm"] not in ALGORITHMS:
        raise ValueError(f"unknown algorithm {entry['algorithm']}")
    if entry["digits"] not in (6, 7, 8) or not 10 <= entry["period"] <= 300:
        raise ValueError("digits must be 6 to 8 and the period 10 to 300 seconds")
    b32decode(entry["secret"])                     # refuses a secret that is not base32
    if not entry["issuer"] and not entry["account"]:
        raise ValueError("the code needs a name (an issuer or an account)")
    entry["secret"] = entry["secret"].replace(" ", "").upper()
    return entry


# ---- the keyring -----------------------------------------------------------------
def secret_api():
    import gi
    gi.require_version("Secret", "1")
    from gi.repository import Secret
    schema = Secret.Schema.new(SCHEMA_NAME, Secret.SchemaFlags.NONE,
                               {"id": Secret.SchemaAttributeType.STRING, "issuer": Secret.SchemaAttributeType.STRING,
                                "account": Secret.SchemaAttributeType.STRING})
    return Secret, schema


def items():
    Secret, schema = secret_api()
    found = Secret.password_search_sync(schema, {}, Secret.SearchFlags.ALL | Secret.SearchFlags.UNLOCK | Secret.SearchFlags.LOAD_SECRETS, None)
    out = []
    for item in found or []:
        attrs = item.get_attributes()
        value = item.get_secret()
        try:
            stored = json.loads(value.get_text() if value else "{}")
        except json.JSONDecodeError:
            continue
        out.append((attrs.get("id", ""), stored))
    return out


def add(entry: dict) -> str:
    Secret, schema = secret_api()
    ident = uuid.uuid4().hex[:12]
    label = "Two-factor code: " + " ".join(x for x in (entry["issuer"], entry["account"]) if x)
    Secret.password_store_sync(schema, {"id": ident, "issuer": entry["issuer"], "account": entry["account"]},
                               Secret.COLLECTION_DEFAULT, label, json.dumps(entry), None)
    return ident


def remove(ident: str) -> bool:
    Secret, schema = secret_api()
    return bool(Secret.password_clear_sync(schema, {"id": ident}, None))


def listing(now: float | None = None) -> list[dict]:
    now = time.time() if now is None else now
    out = []
    for ident, e in items():
        try:
            code = totp(b32decode(e["secret"]), now, e.get("period", 30), e.get("digits", 6), e.get("algorithm", "SHA1"))
        except (ValueError, KeyError):
            code = ""
        period = int(e.get("period", 30))
        out.append({"id": ident, "issuer": e.get("issuer", ""), "account": e.get("account", ""), "code": code,
                    "period": period, "digits": int(e.get("digits", 6)), "remaining": period - int(now % period)})
    return sorted(out, key=lambda x: (x["issuer"].lower(), x["account"].lower()))


def scan_screen() -> str:
    """The person draws a box round a QR code on the screen; its text."""
    pick = subprocess.run(["slurp"], capture_output=True, text=True)
    if pick.returncode != 0 or not pick.stdout.strip():
        raise ValueError("nothing was picked")
    shot = subprocess.run(["grim", "-g", pick.stdout.strip(), "-"], capture_output=True)
    if shot.returncode != 0:
        raise ValueError("the screen could not be read")
    read = subprocess.run(["zbarimg", "--quiet", "--raw", "-"], input=shot.stdout, capture_output=True)
    text = read.stdout.decode(errors="replace").strip()
    if not text:
        raise ValueError("no QR code there")
    return text.splitlines()[0]


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "list"
    try:
        if cmd == "list":
            print(json.dumps(listing()))
        elif cmd in ("add", "scan-screen"):
            text = scan_screen() if cmd == "scan-screen" else (argv[2] if len(argv) > 2 else sys.stdin.read())
            entry = parse(text)
            print(json.dumps({"ok": True, "id": add(entry), "issuer": entry["issuer"], "account": entry["account"]}))
        elif cmd == "remove" and len(argv) > 2:
            print(json.dumps({"ok": remove(argv[2])}))
        else:
            print("usage: otp.py list | add URI | remove ID | scan-screen", file=sys.stderr)
            return 3
    except ValueError as exc:
        print(f"otp: {exc}", file=sys.stderr)
        return 3
    except Exception as exc:  # noqa: BLE001 - no Secret Service, or it refused
        print(f"otp: no keyring ({exc})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
