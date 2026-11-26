#!/usr/bin/env python3
"""u2f — a security key (FIDO2/U2F) to sign in with: pam-u2f's key file, kept by the person.

  u2f.py probe       JSON: {"key": a key is plugged in, "keys": its name(s), "registered": n}
  u2f.py register    one line per step: "touch" (touch the key now), then "done" or "failed: …"
  u2f.py remove      forget every registered key (the file goes)
  u2f.py config      JSON: the PAM modules' settings, the key count and the manager's version
  u2f.py config-set  JSON on stdin: {"target", "settings", "confirm"} -> one JSON object

The file is pam_u2f's default, ~/.config/Yubico/u2f_keys: one line, the user's
name then a credential per key ("alice:cred1:cred2"). A second key is appended
to that line - `pamu2fcfg -n` prints it without the name for exactly this - so
registering never loses the first. It must belong to the person (pam_u2f refuses
a file someone else owns), so it is written here, as them, never with pkexec.
The lock screen and the sign-in screen read it through pam_u2f (sufficient,
nouserok: no file is no key, never a way in).

The PAM modules' own files are root-owned: `config-set` stages the new text and
sends it on stdin to the administrator helper through pkexec. No config text or
secret ever goes in argv. SHANI_FIDO2_TOKEN and SHANI_PAMU2FCFG replace fido2-token
and pamu2fcfg; SHANI_PAM_U2F_CONF, SHANI_PAM_YUBICO_CONF, SHANI_YKMAN,
SHANI_SYSTEM_PKEXEC and SHANI_ADMIN_TOOL replace the system commands (the tests).
"""

import hashlib
import json
import os
import pwd
import re
import shlex
import shutil
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
        out = subprocess.run(
            tool("SHANI_FIDO2_TOKEN", "fido2-token") + ["-L"],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        out = ""
    # "/dev/hidraw4: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)"
    keys = [
        line.rsplit("(", 1)[-1].rstrip(")") if "(" in line else "Security key"
        for line in out.splitlines()
        if line.startswith("/dev/")
    ]
    line = line_of(user())
    return {
        "key": bool(keys),
        "keys": keys,
        "registered": max(0, len(line.split(":")) - 1) if line else 0,
    }


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
        p = subprocess.run(
            cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"failed: {e}", flush=True)
        return 1
    cred = p.stdout.strip()
    if p.returncode != 0 or not cred:
        print(
            "failed: "
            + ((p.stderr.strip().splitlines() or ["the key did not answer"])[-1]),
            flush=True,
        )
        return 1
    if old:
        new = old + (cred if cred.startswith(":") else ":" + cred)
    else:
        new = cred if cred.startswith(name + ":") else name + ":" + cred.lstrip(":")
    others = []
    try:
        with open(keyfile()) as f:
            others = [
                x.rstrip("\n") for x in f if x.strip() and x.split(":", 1)[0] != name
            ]
    except OSError:
        pass
    write(others + [new])
    print("done", flush=True)
    return 0


def remove():
    name = user()
    try:
        with open(keyfile()) as f:
            others = [
                x.rstrip("\n") for x in f if x.strip() and x.split(":", 1)[0] != name
            ]
    except OSError:
        return 0
    if others:
        write(others)
    else:
        os.unlink(keyfile())
    return 0


# The PAM modules' configuration: codes only here, plain words belong to the UI.
FIDO2_KEYS = {
    "authfile",
    "origin",
    "appid",
    "alwaysok",
    "nouserok",
    "interactive",
    "cue",
    "nodetect",
    "expand",
    "sshformat",
    "openasuser",
    "manual",
    "debug",
}
YUBICO_KEYS = {
    "authfile",
    "id",
    "key",
    "alwaysok",
    "try_first_pass",
    "use_first_pass",
    "always_prompt",
    "nullok",
    "ldap_starttls",
    "ldap_bind_as_user",
    "urllist",
    "mode",
    "debug",
    "debug_file",
    "chalresp_path",
}
FIDO2_VALUES = {"authfile", "origin", "appid"}
YUBICO_VALUES = {
    "authfile",
    "id",
    "key",
    "urllist",
    "mode",
    "debug_file",
    "chalresp_path",
}
DANGEROUS = {"fido2": ("alwaysok", "nouserok"), "yubico": ("alwaysok",)}
BAD_CHARS = ";\n\r`$|&"
MODES = ("client", "challenge-response")


def conf_path(target):
    if target == "fido2":
        return os.environ.get("SHANI_PAM_U2F_CONF", "/etc/security/pam_u2f.conf")
    return os.environ.get("SHANI_PAM_YUBICO_CONF", "/etc/security/pam_yubico.conf")


def module_of(target):
    return "pam_u2f.so" if target == "fido2" else "pam_yubico.so"


def keys_of(target):
    return (
        (FIDO2_KEYS, FIDO2_VALUES)
        if target == "fido2"
        else (YUBICO_KEYS, YUBICO_VALUES)
    )


def option_parts(token):
    key, sep, value = token.partition("=")
    return key, bool(sep), value


def truthy(value):
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    return bool(value)


def blank_conf(target, path):
    result = {
        "available": False,
        "values": {},
        "flags": [],
        "knownOnly": True,
        "path": path,
    }
    if target == "yubico":
        result["modes"] = list(MODES)
        result["mode"] = ""
    return result


def parse_conf_text(target, text):
    """Read one PAM config: stable keys and codes, never a credential or a secret."""
    keys, value_keys = keys_of(target)
    module = module_of(target)
    result = blank_conf(target, "")
    found = False
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            tokens = shlex.split(line)
        except ValueError:
            result["knownOnly"] = False
            continue
        if module not in tokens:
            continue
        found = True
        for token in tokens[tokens.index(module) + 1 :]:
            key, has_eq, value = option_parts(token)
            if key not in keys:
                result["knownOnly"] = False
                continue
            if key in value_keys:
                result["values"][key] = "[hidden]" if key == "key" else value
            elif has_eq and value not in ("", "1"):
                result["knownOnly"] = False
            elif key not in result["flags"]:
                result["flags"].append(key)
    result["available"] = found
    if target == "yubico":
        result["mode"] = result["values"].get("mode", "")
    return result


def parse_conf(target):
    path = conf_path(target)
    try:
        with open(path) as f:
            text = f.read()
    except FileNotFoundError:
        return blank_conf(target, path), ""
    except OSError as exc:
        return blank_conf(
            target, path
        ), f"cannot read {os.path.basename(path)}: {exc.strerror or 'error'}"
    result = parse_conf_text(target, text)
    result["path"] = path
    return result, ""


def count_authfile(path):
    if not path:
        return 0
    try:
        with open(os.path.expanduser(path)) as f:
            return sum(
                1 for line in f if line.strip() and not line.lstrip().startswith("#")
            )
    except OSError:
        return 0


def ykman_status():
    cmd = tool("SHANI_YKMAN", "ykman")
    try:
        p = subprocess.run(
            cmd + ["--version"],
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"available": False, "version": ""}, str(exc)[:200]
    text = p.stdout.strip()
    if p.returncode != 0 or not text:
        line = (p.stderr.strip().splitlines() or ["ykman did not report a version"])[-1]
        return {"available": False, "version": ""}, line[:200]
    match = re.search(r"\d+(?:\.\d+)+", text)
    return {
        "available": True,
        "version": match.group(0) if match else text.splitlines()[0],
    }, ""


def config():
    fido2, error = parse_conf("fido2")
    fido2["authfileCount"] = count_authfile(fido2["values"].get("authfile", ""))
    yubico, error2 = parse_conf("yubico")
    ykman, error3 = ykman_status()
    return {
        "fido2": fido2,
        "yubico": yubico,
        "registered": probe()["registered"],
        "ykman": ykman,
        "error": error or error2 or error3,
    }


def base_validate(target, settings):
    if target not in ("fido2", "yubico"):
        return "unknown target"
    if not isinstance(settings, dict):
        return "settings must be an object"
    keys, _ = keys_of(target)
    for key, value in settings.items():
        if not isinstance(key, str) or key not in keys:
            return f"unknown setting {key}"
        text = value if isinstance(value, str) else str(value)
        if any(char in text for char in BAD_CHARS):
            return f"unsafe value for {key}"
        if isinstance(value, (list, dict)):
            return f"bad value for {key}"
    if target == "yubico" and "mode" in settings:
        if settings["mode"] not in MODES:
            return "mode must be client or challenge-response"
    return ""


def needs_confirmation(target, settings, current, confirm):
    current_flags = parse_conf_text(target, current)["flags"]
    for flag in DANGEROUS[target]:
        if flag in settings and truthy(settings[flag]) and flag not in current_flags:
            if confirm != flag:
                return ("" if not confirm else f"type {flag} to confirm"), flag
    return "", ""


def render_setting(key, value, value_keys):
    if key in value_keys:
        if value is False or value is None:
            return ""
        return f"{key}={1 if value is True else value}"
    return key if truthy(value) else ""


def stage_text(target, settings, current):
    """Merge settings into a config, keeping every line it cannot express as-is."""
    module = module_of(target)
    keys, value_keys = keys_of(target)
    out, applied = [], False
    for line in current.splitlines(keepends=True):
        if line.endswith("\r\n"):
            body, ending = line[:-2], "\r\n"
        elif line.endswith("\n"):
            body, ending = line[:-1], "\n"
        else:
            body, ending = line, ""
        stripped = body.strip()
        if not stripped:
            out.append(line)
            continue
        try:
            tokens = shlex.split(stripped)
        except ValueError:
            out.append(line)
            continue
        if module not in tokens:
            out.append(line)
            continue
        index = tokens.index(module)
        options = tokens[index + 1 :]
        if any(option_parts(token)[0] not in keys for token in options):
            out.append(line)
            continue
        if applied:
            out.append(line)
            continue
        seen = set()
        new_options = []
        for token in options:
            key = option_parts(token)[0]
            seen.add(key)
            if key in settings:
                rendered = render_setting(key, settings[key], value_keys)
                if rendered:
                    new_options.append(rendered)
            else:
                new_options.append(token)
        for key, value in settings.items():
            if key not in seen:
                rendered = render_setting(key, value, value_keys)
                if rendered:
                    new_options.append(rendered)
        out.append(" ".join(tokens[: index + 1] + new_options) + (ending or "\n"))
        applied = True
    if not applied:
        if out and not out[-1].endswith(("\n", "\r")):
            out[-1] += "\n"
        if not current.strip():
            out.append("# Managed by this system\n")
        additions = [
            render_setting(key, value, value_keys) for key, value in settings.items()
        ]
        additions = [item for item in additions if item]
        out.append(
            "auth sufficient "
            + module
            + (" " + " ".join(additions) if additions else "")
            + "\n"
        )
    return "".join(out)


def shanios_pam_config_set(target, text, digest):
    """The one call to the ShaniOS-only privileged helper: text and digest on stdin."""
    pkexec = tool("SHANI_SYSTEM_PKEXEC", "pkexec")
    admin = tool("SHANI_ADMIN_TOOL", "/usr/lib/shani-shell/shani-admin.py")
    if not pkexec or shutil.which(pkexec[0]) is None:
        return False, "pkexec is not available"
    request = json.dumps({"target": target, "text": text, "sha256": digest})
    try:
        p = subprocess.run(
            pkexec + admin + ["pam-config-set"],
            input=request.encode("utf-8"),
            capture_output=True,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)[:200]
    if p.returncode != 0:
        line = (
            p.stderr.decode("utf-8", "replace").strip().splitlines()
            or ["helper failed"]
        )[-1]
        return False, line[:200]
    try:
        answer = json.loads(p.stdout.decode("utf-8", "replace"))
    except ValueError:
        return False, "invalid answer from the administrator helper"
    if answer.get("ok") is True:
        return True, ""
    return False, str(
        answer.get("error") or "the administrator helper refused the write"
    )[:200]


def config_set(request):
    request = request if isinstance(request, dict) else {}
    target = request.get("target", "")
    settings = request.get("settings", {})
    confirm = request.get("confirm", "")
    if not isinstance(confirm, str):
        confirm = ""

    def answer(ok, error="", needs=""):
        return {
            "ok": bool(ok),
            "error": error,
            "needsConfirm": needs,
            "config": config(),
        }

    error = base_validate(target, settings)
    if error:
        return answer(False, error)
    path = conf_path(target)
    try:
        with open(path) as f:
            current = f.read()
    except FileNotFoundError:
        current = ""
    except OSError as exc:
        return answer(
            False, f"cannot read {os.path.basename(path)}: {exc.strerror or 'error'}"
        )
    error, needs = needs_confirmation(target, settings, current, confirm)
    if error or needs:
        return answer(False, error, needs)
    text = stage_text(target, settings, current)
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    ok, error = shanios_pam_config_set(target, text, digest)
    if not ok:
        return answer(False, error)
    return answer(True)


def main(argv):
    cmd = argv[1] if len(argv) == 2 else ""
    if cmd == "probe":
        print(json.dumps(probe()))
        return 0
    if cmd == "register":
        return register()
    if cmd == "remove":
        return remove()
    if cmd == "config":
        print(json.dumps(config()))
        return 0
    if cmd == "config-set":
        try:
            request = json.loads(sys.stdin.read())
        except (ValueError, OSError):
            request = None
        print(json.dumps(config_set(request)))
        return 0
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
