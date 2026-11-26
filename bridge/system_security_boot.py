#!/usr/bin/env python3
"""system_security_boot — encryption, TPM2, Secure Boot and recovery keys.

    system_security_boot.py status
    system_security_boot.py enroll          (passphrase [+ PIN] on stdin)
    system_security_boot.py remove          (y on stdin, gen-efi's own prompt)
    system_security_boot.py recovery-key    (passphrase on stdin)
    system_security_boot.py header-backup <absolute-path>
    system_security_boot.py enroll-mok
    system_security_boot.py cleanup-mok

Every call needs root, so each runs gen-efi through pkexec: the shell's polkit
agent says why before it asks for a password. Secrets travel on stdin only:
line 1 is the passphrase, optional line 2 is the PIN. Never argv, never a log,
never a file this bridge writes. SHANI_SECURITY_PKEXEC / SHANI_GEN_EFI override
the two commands.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys

PKEXEC = shlex.split(os.environ.get("SHANI_SECURITY_PKEXEC", "pkexec"))
GEN_EFI = os.environ.get("SHANI_GEN_EFI", "/usr/local/bin/gen-efi")
ACTIONS = {
    "status",
    "enroll",
    "remove",
    "recovery-key",
    "header-backup",
    "enroll-mok",
    "cleanup-mok",
}
TIMEOUT = 120


def _run(args: list[str], stdin: bytes | None = None):
    if not PKEXEC or not shutil.which(PKEXEC[0]):
        return None, f"{PKEXEC[0] if PKEXEC else 'pkexec'} is not available"
    try:
        return subprocess.run(
            PKEXEC + args,
            input=stdin,
            capture_output=True,
            timeout=TIMEOUT,
        ), ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)


def _failure(r, fallback: str) -> str:
    """One short line of why: a runner failure or the tool's last error line."""
    if r is None:
        return fallback[:300]
    lines = (
        (r.stderr or b"").decode("utf-8", "replace").replace("\r", "\n").splitlines()
    )
    return ((lines[-1].strip() if lines else None) or f"exit {r.returncode}")[:300]


def _read_json(args: list[str]):
    r, error = _run(args)
    if r is None or r.returncode != 0:
        return None, _failure(r, error)
    try:
        data = json.loads(r.stdout.decode("utf-8", "replace"))
    except ValueError:
        return None, "invalid JSON from gen-efi"
    return (data if isinstance(data, dict) else None), (
        "" if isinstance(data, dict) else "invalid JSON from gen-efi"
    )


def status() -> dict:
    """Merge gen-efi's two JSON documents, keeping the fields it actually has."""
    tpm, tpm_error = _read_json([GEN_EFI, "tpm2-status", "--json"])
    policy, policy_error = _read_json([GEN_EFI, "pcrlock-status", "--json"])
    result = {
        "ok": True,
        "encrypted": False,
        "tpm2_present": False,
        "tpm2_enrolled": False,
        "tpm2_pin": False,
        "tpm2_slots": 0,
        "secure_boot": False,
        "luks": {
            "version": "",
            "cipher": "",
            "kdf": "",
            "keyslots": None,
            "device": "",
        },
        "policy": {
            "available": False,
            "mode": None,
            "literal_pcrs": None,
            "policy_hash": None,
            "entry_tokens": [],
            "path": None,
        },
        "error": "",
    }
    if tpm:
        result["encrypted"] = tpm.get("encrypted", False)
        result["tpm2_present"] = tpm.get("tpm2_present", False)
        result["tpm2_enrolled"] = tpm.get("tpm2_enrolled", False)
        result["tpm2_pin"] = tpm.get("tpm2_pin", False)
        result["tpm2_slots"] = tpm.get("tpm2_slots", 0)
        result["secure_boot"] = tpm.get("secure_boot", False)
        result["luks"] = {
            "version": tpm.get("luks_version", ""),
            "cipher": tpm.get("luks_cipher", ""),
            "kdf": tpm.get("luks_kdf", ""),
            "keyslots": tpm.get("luks_keyslots_in_use"),
            "device": tpm.get("luks_device", ""),
        }
    if policy:
        result["policy"] = {
            "available": policy.get("pcrlock_policy_available", False),
            "mode": policy.get("enrolled_mode"),
            "literal_pcrs": policy.get("literal_pcrs"),
            "policy_hash": policy.get("policy_hash"),
            "entry_tokens": policy.get("entry_tokens", []),
            "path": policy.get("pcrlock_policy_path"),
        }
        if not tpm:
            result["luks"]["device"] = policy.get("luks_device") or ""
    errors = [e for e in (tpm_error, policy_error) if e]
    result["ok"] = tpm is not None and policy is not None and not errors
    result["error"] = errors[0] if errors else ""
    return result


def secret_lines(raw: bytes) -> tuple[str, str, str]:
    """Read the two-line stdin protocol; refuse anything a line cannot hold."""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return "", "", "secrets must be UTF-8 text"
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not 1 <= len(lines) <= 2:
        return "", "", "expected a passphrase line and an optional PIN line"
    if not lines[0]:
        return "", "", "empty passphrase"
    if len(lines) == 2 and not lines[1]:
        return "", "", "empty PIN"
    return lines[0], (lines[1] if len(lines) == 2 else ""), ""


def enroll(passphrase: str, pin: str = "") -> dict:
    args = [GEN_EFI, "enroll-tpm2", "--stdin"]
    if pin:
        args.append("--with-pin")
    stdin = (passphrase + "\n" + (pin + "\n" if pin else "")).encode("utf-8")
    r, error = _run(args, stdin)
    ok = r is not None and r.returncode == 0
    return {"ok": ok, "error": "" if ok else _failure(r, error)}


def remove() -> dict:
    # gen-efi asks y/N itself; "y" is a confirmation, not a secret.
    r, error = _run([GEN_EFI, "remove-tpm2"], b"y\n")
    ok = r is not None and r.returncode == 0
    return {"ok": ok, "error": "" if ok else _failure(r, error)}


def recovery_key(passphrase: str) -> dict:
    r, error = _run(
        [GEN_EFI, "recovery-key", "--stdin"], (passphrase + "\n").encode("utf-8")
    )
    if r is None or r.returncode != 0:
        return {"ok": False, "key": "", "error": _failure(r, error)}
    for line in r.stdout.decode("utf-8", "replace").splitlines():
        if line.startswith("RECOVERY_KEY="):
            key = line.split("=", 1)[1].strip()
            if key:
                return {"ok": True, "key": key, "error": ""}
    return {"ok": False, "key": "", "error": "no recovery key in tool output"}


def header_backup(path: str) -> dict:
    r, error = _run([GEN_EFI, "luks-header-backup"])
    if r is None or r.returncode != 0:
        return {"ok": False, "path": path, "bytes": 0, "error": _failure(r, error)}
    data = r.stdout
    if not data.startswith(b"LUKS\xba\xbe"):
        return {
            "ok": False,
            "path": path,
            "bytes": 0,
            "error": "no LUKS header in tool output",
        }
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(path, 0o600)
    except OSError as exc:
        return {"ok": False, "path": path, "bytes": 0, "error": str(exc)}
    return {"ok": True, "path": path, "bytes": len(data), "error": ""}


def run_action(subcommand: str) -> dict:
    r, error = _run([GEN_EFI, subcommand])
    ok = r is not None and r.returncode == 0
    return {"ok": ok, "error": "" if ok else _failure(r, error)}


def usage() -> None:
    print(
        "usage: system_security_boot.py status|enroll|remove|recovery-key|"
        "header-backup <absolute-path>|enroll-mok|cleanup-mok",
        file=sys.stderr,
    )


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in ACTIONS:
        usage()
        return 2
    action = argv[1]
    if action == "header-backup":
        if len(argv) != 3 or not argv[2] or not os.path.isabs(argv[2]):
            usage()
            return 2
        result = header_backup(argv[2])
    else:
        if len(argv) != 2:
            usage()
            return 2
        if action == "status":
            result = status()
        elif action == "remove":
            result = remove()
        elif action in ("enroll-mok", "cleanup-mok"):
            result = run_action(action)
        else:
            passphrase, pin, error = secret_lines(sys.stdin.buffer.read())
            if error or (action == "recovery-key" and pin):
                result = {
                    "ok": False,
                    "error": error or "expected only a passphrase line",
                }
            elif action == "recovery-key":
                result = recovery_key(passphrase)
            else:
                result = enroll(passphrase, pin)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
