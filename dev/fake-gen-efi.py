#!/usr/bin/env python3
"""Stand-in for ../shani-deploy/scripts/gen-efi.sh (tests/test_system_security_boot.py).

Accepts only the forms the bridge uses; everything else is usage + exit 2.
State lives in $FAKE_GEN_EFI_DIR/state (default /tmp/fake-gen-efi/state):
encrypted-tpm (default), encrypted-tpm-pin, encrypted-no-tpm, plain.
Every call is logged to $FAKE_GEN_EFI_DIR/calls as subcommand + options only:
stdin, passphrases, PINs and recovery keys are never logged or echoed.
FAKE_GEN_EFI_FAIL=<subcommand> makes one subcommand fail for negative tests.
"""

import json
import os
import secrets
import sys

D = os.environ.get("FAKE_GEN_EFI_DIR", "/tmp/fake-gen-efi")
STATE = os.path.join(D, "state")
CALLS = os.path.join(D, "calls")
STATES = ("encrypted-tpm", "encrypted-tpm-pin", "encrypted-no-tpm", "plain")
KEY_ALPHABET = "cbdefghijklnrtuv"


def usage() -> None:
    print(
        "usage: fake-gen-efi.py tpm2-status --json|pcrlock-status --json|"
        "enroll-tpm2 --stdin [--with-pin]|remove-tpm2|recovery-key --stdin|"
        "luks-header-backup|enroll-mok|cleanup-mok",
        file=sys.stderr,
    )


def read_state() -> str:
    try:
        with open(STATE) as f:
            value = f.read().strip()
    except OSError:
        value = "encrypted-tpm"
    return value if value in STATES else "encrypted-tpm"


def write_state(value: str) -> None:
    os.makedirs(D, exist_ok=True)
    with open(STATE, "w") as f:
        f.write(value + "\n")


def log_call(args: list[str]) -> None:
    os.makedirs(D, exist_ok=True)
    with open(CALLS, "a") as f:
        f.write(" ".join(args) + "\n")


def status_docs(value: str) -> tuple[dict, dict]:
    """Exact field names and types from gen-efi's two jq documents."""
    encrypted = value != "plain"
    enrolled = value in ("encrypted-tpm", "encrypted-tpm-pin")
    device = "/dev/nvme0n1p3" if encrypted else ""
    tpm = {
        "encrypted": encrypted,
        "tpm2_present": value in ("encrypted-tpm", "encrypted-tpm-pin"),
        "tpm2_enrolled": enrolled,
        "tpm2_slots": 1 if enrolled else 0,
        "tpm2_pin": value == "encrypted-tpm-pin",
        "secure_boot": encrypted,
        "luks_device": device,
        "luks_version": "2" if encrypted else "",
        "luks_cipher": "aes-xts-plain64" if encrypted else "",
        "luks_kdf": "argon2id" if encrypted else "",
        "luks_keyslots_in_use": 1 if encrypted else None,
    }
    if value == "encrypted-tpm":
        policy = {
            "pcrlock_policy_available": True,
            "pcrlock_policy_path": "/etc/secureboot/pcrlock.json",
            "enrolled_mode": "literal",
            "literal_pcrs": "7",
            "policy_hash": None,
            "entry_tokens": ["tok-a", "tok-b"],
            "luks_device": device,
        }
    elif value == "encrypted-tpm-pin":
        policy = {
            "pcrlock_policy_available": True,
            "pcrlock_policy_path": "/etc/secureboot/pcrlock.json",
            "enrolled_mode": "pcrlock",
            "literal_pcrs": None,
            "policy_hash": "b0d3" * 16,
            "entry_tokens": ["tok-a"],
            "luks_device": device,
        }
    elif value == "encrypted-no-tpm":
        policy = {
            "pcrlock_policy_available": True,
            "pcrlock_policy_path": "/etc/secureboot/pcrlock.json",
            "enrolled_mode": None,
            "literal_pcrs": None,
            "policy_hash": None,
            "entry_tokens": [],
            "luks_device": device,
        }
    else:
        policy = {
            "pcrlock_policy_available": False,
            "pcrlock_policy_path": None,
            "enrolled_mode": None,
            "literal_pcrs": None,
            "policy_hash": None,
            "entry_tokens": [],
            "luks_device": None,
        }
    return tpm, policy


def main(args: list[str]) -> int:
    if not args:
        usage()
        return 2
    cmd = args[0]
    if cmd in ("tpm2-status", "pcrlock-status"):
        if args != [cmd, "--json"]:
            usage()
            return 2
    elif cmd == "enroll-tpm2":
        if args not in (
            ["enroll-tpm2", "--stdin"],
            ["enroll-tpm2", "--stdin", "--with-pin"],
        ):
            usage()
            return 2
    elif cmd == "recovery-key":
        if args != ["recovery-key", "--stdin"]:
            usage()
            return 2
    elif cmd in ("remove-tpm2", "luks-header-backup", "enroll-mok", "cleanup-mok"):
        if len(args) != 1:
            usage()
            return 2
    else:
        usage()
        return 2

    log_call(args)
    if os.environ.get("FAKE_GEN_EFI_FAIL") == cmd:
        print(f"gen-efi: {cmd} failed", file=sys.stderr)
        return 1

    value = read_state()
    if cmd in ("tpm2-status", "pcrlock-status"):
        tpm, policy = status_docs(value)
        print(json.dumps(tpm if cmd == "tpm2-status" else policy))
    elif cmd == "enroll-tpm2":
        sys.stdin.buffer.read()  # discard passphrase and PIN
        write_state("encrypted-tpm-pin" if "--with-pin" in args else "encrypted-tpm")
    elif cmd == "remove-tpm2":
        confirm = sys.stdin.buffer.read()
        if confirm.lower().startswith(b"y"):
            write_state("encrypted-no-tpm")
    elif cmd == "recovery-key":
        sys.stdin.buffer.read()  # discard passphrase
        groups = [
            "".join(secrets.choice(KEY_ALPHABET) for _ in range(8)) for _ in range(8)
        ]
        print("RECOVERY_KEY=" + "-".join(groups))
    elif cmd == "luks-header-backup":
        sys.stdout.buffer.write(b"LUKS\xba\xbe" + b"\x00" * 128 + b"fake header")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
