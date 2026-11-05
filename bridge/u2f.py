#!/usr/bin/env python3
"""u2f — a security key (FIDO2/U2F) to sign in with: pam-u2f's key file, kept by the person.

  u2f.py probe       JSON: {"key": a key is plugged in, "keys": its name(s), "registered": n}
  u2f.py register    one line per step: "touch" (touch the key now), then "done" or "failed: …"
  u2f.py remove      forget every registered key (the file goes)

The file is pam_u2f's default, ~/.config/Yubico/u2f_keys: one line, the user's
name then a credential per key ("alice:cred1:cred2"). A second key is appended
to that line - `pamu2fcfg -n` prints it without the name for exactly this - so
registering never loses the first. It must belong to the person (pam_u2f refuses
a file someone else owns), so it is written here, as them, never with pkexec.
The lock screen and the sign-in screen read it through pam_u2f (sufficient,
nouserok: no file is no key, never a way in).

SHANI_FIDO2_TOKEN and SHANI_PAMU2FCFG replace fido2-token and pamu2fcfg (the tests).
"""

import json
import os
import pwd
import shlex
import subprocess
import sys


def tool(env, default):
    return shlex.split(os.environ.get(env, default))


def user():
    return pwd.getpwuid(os.getuid()).pw_name


def keyfile():
    return os.path.join(os.path.expanduser("~"), ".config", "Yubico", "u2f_keys")


def line_of(name):
    try:
        with open(keyfile()) as f:
            for line in f:
                if line.split(":", 1)[0] == name:
                    return line.rstrip("\n")
    except OSError:
        pass
    return ""


def probe():
    try:
        out = subprocess.run(tool("SHANI_FIDO2_TOKEN", "fido2-token") + ["-L"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        out = ""
    # "/dev/hidraw4: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)"
    keys = [line.rsplit("(", 1)[-1].rstrip(")") if "(" in line else "Security key"
            for line in out.splitlines() if line.startswith("/dev/")]
    line = line_of(user())
    return {"key": bool(keys), "keys": keys, "registered": max(0, len(line.split(":")) - 1) if line else 0}


def write(lines):
    path = keyfile()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("".join(x + "\n" for x in lines))
    os.replace(tmp, path)


def register():
    name = user()
    old = line_of(name)
    print("touch", flush=True)
    cmd = tool("SHANI_PAMU2FCFG", "pamu2fcfg") + ["-u", name] + (["-n"] if old else [])
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"failed: {e}", flush=True)
        return 1
    cred = p.stdout.strip()
    if p.returncode != 0 or not cred:
        print("failed: " + ((p.stderr.strip().splitlines() or ["the key did not answer"])[-1]), flush=True)
        return 1
    if old:
        new = old + (cred if cred.startswith(":") else ":" + cred)
    else:
        new = cred if cred.startswith(name + ":") else name + ":" + cred.lstrip(":")
    others = []
    try:
        with open(keyfile()) as f:
            others = [x.rstrip("\n") for x in f if x.strip() and x.split(":", 1)[0] != name]
    except OSError:
        pass
    write(others + [new])
    print("done", flush=True)
    return 0


def remove():
    name = user()
    try:
        with open(keyfile()) as f:
            others = [x.rstrip("\n") for x in f if x.strip() and x.split(":", 1)[0] != name]
    except OSError:
        return 0
    if others:
        write(others)
    else:
        os.unlink(keyfile())
    return 0


def main(argv):
    cmd = argv[1] if len(argv) == 2 else ""
    if cmd == "probe":
        print(json.dumps(probe()))
        return 0
    if cmd == "register":
        return register()
    if cmd == "remove":
        return remove()
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
