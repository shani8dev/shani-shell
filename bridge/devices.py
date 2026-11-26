#!/usr/bin/env python3
"""devices — the shell's Devices window: Android tools, pairing and radios.

Each call prints one JSON answer, like the other bridges. The engines are the
vendored ``phone`` modules, imported only when a command needs them, so a
machine with no phone backends still gets an answer instead of a traceback.

    devices.py android <verb> [serial] [arg]   {ok,error,out}; info adds {devices,info}
        verbs: info, battery, storage, screenshot, record, link, app, file
    devices.py connect <kind> [value [code]]   {ok,error}
        kinds: android (adb pair), bluetooth (BlueZ pair), phone (KDE Connect pair)
    devices.py screen <start|stop|state> [area:transport] [touch] [type]
        {ok,error,state,mode,touch,type}; area window|screen, transport auto|usb|wifi|
        bluetooth. A bare area or transport is still accepted. SHANI_SCREEN_MODE
        supplies the mode when none is given.
    devices.py fm <start|stop|state|tune> [frequency]  {ok,error,state,frequency}
        SHANI_FM runs a stand-in that answers each verb with JSON.
    devices.py nfc <read|write> [text]         {ok,error,text}
        SHANI_NFC runs a stand-in for nfc-list and nfc-mfultralight.
    devices.py ir <list|send> [code]           {ok,error,codes}
        SHANI_IR runs a stand-in for irsend and ir-keytable.
        list with a remote's name lists its buttons; send takes remote:button
    devices.py lines                           [{id,name,ready,kind}]
        kind is landline, setup, phone, modem or sip
    devices.py sip-list                        [{name,username,domain,...}] (no password)
    devices.py sip-add <json>                  {ok,error}
    devices.py sip-update <id> <json>          {ok,error}
    devices.py sip-remove <id>                 {ok,error}
    devices.py landline-state                  {ok,error,state}
    devices.py landline-setup <host>           {ok,error,state}
    devices.py landline-finish <code>          {ok,error,state}
    devices.py landline-forget                 {ok,error,state}

Helpers are overridable for tests, as in containers.py: SHANI_ADB, SHANI_DBUS,
SHANI_KDECONNECT, SHANI_BLUETOOTHCTL, SHANI_NFC, SHANI_IR, SHANI_FM and
SHANI_SCREEN_MODE.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

BRIDGE = Path(__file__).resolve().parent
NOT_INSTALLED = "the phone backends are not installed"

SCREEN_MODES = ("auto", "usb", "wifi", "bluetooth")
SCREEN_STATE = "device-screen.json"
FM_STATE = "device-fm.json"

#: A short-lived bridge process cannot keep fm_radio's play list alive, so the
#: tuner runs in its own process; SIGTERM ends it and atexit stops the radio.
FM_RUNNER = (
    "import signal, sys, time;"
    "sys.path.insert(0, sys.argv[1]);"
    "from phone import fm_radio;"
    "signal.signal(signal.SIGTERM, lambda *_: sys.exit(0));"
    "print(fm_radio.run({'action': 'tune', 'frequency': sys.argv[2]}), flush=True);"
    "time.sleep(86400)"
)

_FAILURE = (
    "not installed",
    "no android device",
    "no device ",
    "did not answer",
    "could not",
    "failed",
    "refused",
    "is not a file",
    "already exists",
    "give ",
    "refusing",
    "nothing ",
    "not understood",
    "must be",
)


def _module(name: str):
    """Import one vendored engine, or None when it is not usable here."""
    try:
        return __import__(name, fromlist=["*"])
    except Exception:  # noqa: BLE001 - any import failure means "not installed"
        return None


def _tool(var: str, default: str) -> list[str]:
    return shlex.split(os.environ.get(var) or default) or [default]


def _ok(error: str | None = None) -> dict:
    return {"ok": not error, "error": error or ""}


def _said(proc) -> str:
    """The one useful line a command said, and nothing else."""
    text = (
        (getattr(proc, "stderr", "") or "") + "\n" + (getattr(proc, "stdout", "") or "")
    )
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return lines[-1][:160] if lines else ""


def _run(argv: list[str], what: str) -> dict:
    """Run a helper; a tool that is missing is an honest answer, not a crash."""
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        return _ok(what + " needs a tool that is not installed")
    except (OSError, subprocess.TimeoutExpired) as exc:
        return _ok(str(exc)[:160])
    return _ok(
        None if proc.returncode == 0 else (_said(proc) or what + " did not work")
    )


# --- small state files, beside the other phone state --------------------------


def _state_path(name: str) -> Path:
    paths = _module("phone.paths")
    base = (
        paths.state_home()
        if paths is not None
        else Path(
            os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        )
    )
    return Path(base) / "shani-shell" / name


def _read_state(name: str) -> dict:
    try:
        row = json.loads(_state_path(name).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return row if isinstance(row, dict) else {}


def _write_state(name: str, row: dict) -> None:
    target = _state_path(name)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(json.dumps(row), encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, target)


def _clear_state(name: str) -> None:
    try:
        _state_path(name).unlink()
    except OSError:
        pass


def _alive(pid: Any) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, TypeError, ValueError):
        return False


def _spawn(argv: list[str], name: str, row: dict, log: str) -> dict:
    """Start a detached stream or tuner and remember its pid."""
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(
        part for part in (str(BRIDGE), env.get("PYTHONPATH", "")) if part
    )
    try:
        target = _state_path(log)
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "ab") as out:
            proc = subprocess.Popen(
                argv,
                cwd=str(BRIDGE),
                env=env,
                stdout=out,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
    except (OSError, subprocess.SubprocessError) as exc:
        return _ok(str(exc)[:160])
    row["pid"] = proc.pid
    row["when"] = int(time.time())
    _write_state(name, row)
    return _ok()


# --- adb stand-in -------------------------------------------------------------


def _with_adb(mod, pair: bool = False):
    """Point a vendored module's adb call at SHANI_ADB for one command.

    android.py and adb_pair.py run a plain ``adb``; they have no override of
    their own, so the call is patched here and put back immediately after.
    Returns a restore function, or None when there is nothing to override.
    """
    binary = (shlex.split(os.environ.get("SHANI_ADB") or "") or [""])[0]
    original = getattr(mod, "_adb", None)
    if not binary or original is None:
        return None
    if pair:

        def patched(*args, timeout=20, **_kwargs):
            try:
                proc = subprocess.run(
                    [binary, *args],
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                    stdin=subprocess.DEVNULL,
                )
            except FileNotFoundError:
                return 127, "adb (android-tools) is not installed"
            except subprocess.TimeoutExpired:
                return 124, "adb did not answer in time"
            return proc.returncode, ((proc.stdout or "") + (proc.stderr or "")).strip()
    else:

        def patched(args, serial="", binary_output=False, timeout=60, **kwargs):
            # android.screenshot calls this with `binary=True`; accept that too
            # so the stand-in sees the exact same call the real adb would.
            raw = bool(binary_output or kwargs.get("binary"))
            argv = [binary] + (["-s", serial] if serial else []) + list(args)
            return subprocess.run(
                argv,
                capture_output=True,
                timeout=timeout,
                check=False,
                text=not raw,
            )

    mod._adb = patched

    def restore():
        mod._adb = original

    return restore


# --- the commands -------------------------------------------------------------


def _android_rows(mod) -> list[dict]:
    """The handsets as rows: serial, model and how each is attached."""
    try:
        text = str(mod.list_devices() or "")
    except Exception:  # noqa: BLE001 - a tool that cannot list has no rows
        return []
    rows = []
    for line in text.splitlines():
        if not line.strip().startswith("-"):
            continue
        parts = line.strip().lstrip("-").split()
        if len(parts) < 2:
            continue
        serial = parts[0]
        state = parts[-1].strip("()")
        model = " ".join(parts[1:-1]).strip()
        rows.append(
            {
                "serial": serial,
                "model": model,
                "name": model,
                "state": state,
                "via": "wifi" if ":" in serial else "usb",
            }
        )
    return rows


def _android_info(mod, serial: str) -> dict:
    """A list of phones and one phone's facts, for the window's cards."""
    devices = _android_rows(mod)
    info = {"serial": serial, "model": "", "battery": "", "storage": "", "text": ""}
    if not serial:
        return {"ok": True, "error": "", "devices": devices, "info": info, "out": ""}
    try:
        said = str(mod.info(serial) or "")
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "error": str(exc)[:160],
            "devices": devices,
            "info": info,
            "out": "",
        }
    info["text"] = said
    model = re.match(r"([^,]+), Android", said)
    info["model"] = (model.group(1).strip() if model else "") or next(
        (d["model"] for d in devices if d["serial"] == serial), ""
    )
    battery = re.search(r"battery (\d+%[^;,]*)", said)
    info["battery"] = battery.group(1).strip() if battery else ""
    storage = re.search(r"([0-9.]+[KMGT]?) free", said)
    info["storage"] = storage.group(1) if storage else ""
    error = said if any(word in said.lower() for word in _FAILURE) else ""
    return {
        "ok": not error,
        "error": error,
        "devices": devices,
        "info": info,
        "out": "" if error else said,
    }


def _battery_facts(text: str) -> dict:
    """The phone's own dumpsys battery, as numbers a card can show."""

    def value(key: str) -> str:
        found = re.search(
            r"^\s*" + key.replace(" ", r"\s+") + r":\s*(\S+)", text, re.MULTILINE
        )
        return found.group(1) if found else ""

    level, scale = value("level"), value("scale") or "100"
    return {
        "level": int(level) if level.isdigit() else -1,
        "scale": int(scale) if scale.isdigit() else 100,
        "charging": any(
            value(k).lower() == "true"
            for k in ("AC powered", "USB powered", "Wireless powered")
        ),
        "status": value("status"),
        "health": value("health"),
        "voltage": value("voltage"),
        "temperature": value("temperature"),
    }


def _storage_facts(text: str) -> dict:
    """`df -h /sdcard`'s last line, as the fields it actually printed."""
    lines = [line.split() for line in text.splitlines() if line.strip()]
    parts = lines[-1] if lines else []
    return {
        "total": parts[1] if len(parts) > 1 else "",
        "used": parts[2] if len(parts) > 2 else "",
        "free": parts[3] if len(parts) > 3 else "",
        "use": parts[4] if len(parts) > 4 else "",
        "mounted": parts[-1] if parts else "",
    }


def _android_blank() -> dict:
    """The shape an info answer keeps even when no phone can be read."""
    return {
        "devices": [],
        "info": {"serial": "", "model": "", "battery": "", "storage": "", "text": ""},
    }


def cmd_android(verb: str, serial: str = "", arg: str = "") -> dict:
    mod = _module("phone.android")
    if mod is None:
        answer = {"ok": False, "error": NOT_INSTALLED, "out": ""}
        if verb == "info":
            answer.update(_android_blank())
        return answer
    verb = str(verb or "").strip().lower()
    serial, arg = str(serial or "").strip(), str(arg or "").strip()
    if not os.environ.get("SHANI_ADB") and hasattr(mod, "available"):
        try:
            if not mod.available():
                answer = {
                    "ok": False,
                    "error": getattr(mod, "NO_ADB", "adb is not installed"),
                    "out": "",
                }
                if verb == "info":
                    answer.update(_android_blank())
                return answer
        except Exception:  # noqa: BLE001 - a probe is not the command itself
            pass
    restore = _with_adb(mod)
    try:
        # No serial named: ask the engine which phone is actually ready, so an
        # empty answer is never passed off as information about a phone.
        if not serial and hasattr(mod, "ready_serial"):
            try:
                picked, problem = mod.ready_serial()
                if problem:
                    answer = {"ok": False, "error": problem, "out": ""}
                    if verb == "info":
                        answer.update(_android_blank())
                    return answer
                serial = picked
            except Exception:  # noqa: BLE001 - the verb below can still say why
                pass
        try:
            if verb == "info":
                return _android_info(mod, serial)
            if verb == "battery":
                out = mod._shell(serial, "dumpsys", "battery")
            elif verb == "storage":
                out = mod._shell(serial, "df", "-h", "/sdcard")
            elif verb == "screenshot":
                out = mod.screenshot(serial, Path(arg) if arg else None)
            elif verb == "record":
                seconds = int(arg) if arg.isdigit() else 30
                out = mod.record(serial, seconds)
            elif verb == "link":
                out = (
                    mod.open_url(serial, arg)
                    if arg.lower().startswith(("http://", "https://"))
                    else mod.list_devices()
                )
            elif verb == "app":
                out = mod.apps(serial, arg)
            elif verb == "file":
                out = (
                    mod.push(serial, Path(arg))
                    if arg
                    else mod._shell(serial, "ls", "/sdcard/Download/")
                )
            else:
                return {
                    "ok": False,
                    "error": "android needs info, battery, storage, screenshot, "
                    "record, link, app or file",
                    "out": "",
                }
        except Exception as exc:  # noqa: BLE001 - an engine failure is an answer
            return {"ok": False, "error": str(exc)[:160], "out": ""}
    finally:
        if restore is not None:
            restore()
    out = str(out or "")
    error = out if any(word in out.lower() for word in _FAILURE) else ""
    answer = {"ok": not error, "error": error, "out": "" if error else out}
    if verb == "battery":
        answer["battery"] = _battery_facts(out) if not error else {}
    elif verb == "storage":
        answer["storage"] = _storage_facts(out) if not error else {}
    return answer


def cmd_connect(kind: str, value: str = "", code: str = "") -> dict:
    kind = str(kind or "").strip().lower()
    value, code = str(value or "").strip(), str(code or "").strip()
    if kind == "android":
        mod = _module("phone.adb_pair")
        if mod is None:
            return _ok(NOT_INSTALLED)
        restore = _with_adb(mod, pair=True)
        try:
            ok, why = mod.pair(value, code) if code else mod.connect(value)
        except Exception as exc:  # noqa: BLE001
            return _ok(str(exc)[:160])
        finally:
            if restore is not None:
                restore()
        return _ok(None if ok else (why or "the phone did not answer"))
    if kind == "bluetooth":
        if not value:
            return _ok("give the Bluetooth address to pair")
        object_path = (
            "/org/bluez/hci0/dev_" + value.replace(":", "_").replace("-", "_").upper()
        )
        return _run(
            _tool("SHANI_DBUS", "gdbus")
            + [
                "call",
                "--system",
                "--dest",
                "org.bluez",
                "--object-path",
                object_path,
                "--method",
                "org.bluez.Device1.Pair",
            ],
            "Bluetooth pairing",
        )
    if kind == "phone":
        if not value:
            return _ok("give the phone id to pair")
        return _run(
            _tool("SHANI_KDECONNECT", "kdeconnect-cli")
            + [
                "-d",
                value,
                "--pair",
            ],
            "phone pairing",
        )
    return _ok("connect android, bluetooth or phone")


SCREEN_AREAS = ("window", "screen")


def _screen_answer(
    state: str,
    mode: str = "",
    touch: bool = False,
    typing: bool = False,
    error: str = "",
    ok: bool = True,
) -> dict:
    return {
        "ok": ok,
        "error": error,
        "state": state,
        "mode": mode,
        "touch": bool(touch),
        "type": bool(typing),
    }


def _screen_mode(raw: str) -> tuple[str, str, str]:
    """Split `area:transport`; a bare area or transport still works."""
    text = str(raw or "").strip().lower()
    if ":" in text:
        area, transport = text.split(":", 1)
    elif text in SCREEN_AREAS:
        area, transport = text, "auto"
    else:
        area, transport = "screen", text or "auto"
    if area not in SCREEN_AREAS or transport not in SCREEN_MODES:
        return "", "", "mode must be window|screen:auto|usb|wifi|bluetooth"
    return area, transport, ""


def _switch(raw: Any) -> bool:
    return str(raw or "").strip().lower() in ("1", "true", "yes", "on")


def cmd_screen(verb: str, mode: str = "", touch: Any = "", typing: Any = "") -> dict:
    if _module("phone.screen_stream") is None:
        return _screen_answer("off", error=NOT_INSTALLED, ok=False)
    verb = str(verb or "").strip().lower()
    if verb == "state":
        row = _read_state(SCREEN_STATE)
        if not row or not _alive(row.get("pid", 0)):
            _clear_state(SCREEN_STATE)
            return _screen_answer("off")
        return _screen_answer(
            "on",
            str(row.get("mode") or ""),
            bool(row.get("touch")),
            bool(row.get("type")),
        )
    if verb == "stop":
        row = _read_state(SCREEN_STATE)
        try:
            if row.get("pid"):
                os.kill(int(row["pid"]), signal.SIGTERM)
        except (OSError, TypeError, ValueError):
            pass
        _clear_state(SCREEN_STATE)
        return _screen_answer("off")
    if verb == "start":
        chosen = (
            str(mode or "").strip() or os.environ.get("SHANI_SCREEN_MODE") or "auto"
        )
        area, transport, why = _screen_mode(chosen)
        if why:
            return _screen_answer("off", error=why, ok=False)
        label = f"{area}:{transport}"
        touches, types = _switch(touch), _switch(typing)
        argv = [sys.executable, "-m", "phone.screen_stream", "--transport", transport]
        if area == "window":
            argv.append("--window")
        # screen_stream has one switch for input devices: it opens touch, pen
        # and keyboard together, so either choice turns it on.
        if touches or types:
            argv.append("--touch")
        answer = _spawn(
            argv,
            SCREEN_STATE,
            {
                "state": "on",
                "mode": label,
                "area": area,
                "transport": transport,
                "touch": touches,
                "type": types,
            },
            "device-screen.log",
        )
        if not answer["ok"]:
            return _screen_answer("off", error=answer["error"], ok=False)
        return _screen_answer("on", label, touches, types)
    return _screen_answer("off", error="screen needs start, stop or state", ok=False)


def _fm_frequency(mod, raw: str) -> tuple[str, str]:
    text = str(raw or "").strip()
    if not text:
        return "", "give a frequency to tune, like 98.6"
    checker = getattr(mod, "_frequency", None)
    if checker is not None:
        try:
            _hz, why = checker({"frequency": text})
        except Exception as exc:  # noqa: BLE001
            return "", str(exc)[:160]
        if why:
            return "", why
    return text, ""


def _fm_answer_from(said: str, fallback: str = "") -> dict:
    """The stand-in's JSON, as the bridge's own {state, frequency} answer."""
    try:
        row = json.loads(said)
    except (TypeError, ValueError):
        row = {}
    if not isinstance(row, dict):
        row = {}
    state = str(row.get("state") or "").strip().lower()
    state = "on" if state in ("on", "running", "playing", "started") else "off"
    return {
        "ok": True,
        "error": "",
        "state": state,
        "frequency": str(row.get("frequency") or fallback or ""),
        "out": said,
    }


def cmd_fm(verb: str, frequency: str = "") -> dict:
    verb = str(verb or "").strip().lower()
    override = _override("SHANI_FM")
    if override:
        if verb not in ("start", "tune", "stop", "state"):
            return {
                "ok": False,
                "error": "fm needs start, tune, stop or state",
                "state": "off",
                "frequency": "",
            }
        args = [verb]
        if verb in ("start", "tune") and str(frequency or "").strip():
            args.append(str(frequency).strip())
        got = _standalone(override, args)
        if "error" in got:
            return {"ok": False, "error": got["error"], "state": "off", "frequency": ""}
        return _fm_answer_from(got.get("out", ""), str(frequency or ""))
    mod = _module("phone.fm_radio")
    if mod is None:
        return {"ok": False, "error": NOT_INSTALLED, "state": "off", "frequency": ""}
    if verb == "state":
        row = _read_state(FM_STATE)
        if not row or not _alive(row.get("pid", 0)):
            _clear_state(FM_STATE)
            return {"ok": True, "error": "", "state": "off", "frequency": ""}
        return {
            "ok": True,
            "error": "",
            "state": "on",
            "frequency": str(row.get("frequency") or ""),
        }
    if verb == "stop":
        row = _read_state(FM_STATE)
        try:
            if row.get("pid"):
                os.kill(int(row["pid"]), signal.SIGTERM)
        except (OSError, TypeError, ValueError):
            pass
        _clear_state(FM_STATE)
        return {"ok": True, "error": "", "state": "off", "frequency": ""}
    if verb in ("start", "tune"):
        raw = str(frequency or "").strip() or str(
            _read_state(FM_STATE).get("frequency") or ""
        )
        chosen, why = _fm_frequency(mod, raw)
        if why:
            return {"ok": False, "error": why, "state": "off", "frequency": ""}
        answer = _spawn(
            [sys.executable, "-c", FM_RUNNER, str(BRIDGE), chosen],
            FM_STATE,
            {"state": "on", "frequency": chosen},
            "device-fm.log",
        )
        if not answer["ok"]:
            return {
                "ok": False,
                "error": answer["error"],
                "state": "off",
                "frequency": "",
            }
        return {"ok": True, "error": "", "state": "on", "frequency": chosen}
    return {
        "ok": False,
        "error": "fm needs start, tune, stop or state",
        "state": "off",
        "frequency": "",
    }


def _override(var: str) -> list[str]:
    """A SHANI_* binary, as argv, or [] when the variable is unset."""
    raw = os.environ.get(var) or ""
    return shlex.split(raw) if raw.strip() else []


def _standalone(binary: list[str], args: list[str]) -> dict:
    """Ask a stand-in directly; its words are the answer, not a traceback."""
    try:
        proc = subprocess.run(binary + args, capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        return {"error": (binary[0] or "the helper") + " is not installed"}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"error": str(exc)[:160]}
    said = ((proc.stdout or "") + (proc.stderr or "")).strip()
    if proc.returncode != 0:
        return {"error": said or "the helper did not answer"}
    return {"out": said}


def cmd_nfc(verb: str, text: str = "") -> dict:
    mod = _module("phone.nfc")
    if mod is None:
        return {"ok": False, "error": NOT_INSTALLED, "text": ""}
    verb = str(verb or "").strip().lower()
    if verb not in ("read", "write"):
        return {"ok": False, "error": "nfc needs read or write", "text": ""}
    override = _override("SHANI_NFC")
    if override:
        args = ["read"] if verb == "read" else ["write", str(text).strip()]
        if verb == "write" and not str(text or "").strip():
            return {
                "ok": False,
                "error": "give the text to write to the tag",
                "text": "",
            }
        got = _standalone(override, args)
        if "error" in got:
            return {"ok": False, "error": got["error"], "text": ""}
        said = got.get("out", "")
        if said.startswith("The tag says:"):
            said = said.split("\n", 1)[-1].strip()
        return {"ok": True, "error": "", "text": said, "out": got.get("out", "")}
    arguments: dict[str, str] = {"action": verb}
    if verb == "write":
        if not str(text or "").strip():
            return {
                "ok": False,
                "error": "give the text to write to the tag",
                "text": "",
            }
        arguments["text"] = str(text).strip()
    engine = getattr(mod, "_run", None) or getattr(mod, "run", None)
    if engine is None:
        return {"ok": False, "error": NOT_INSTALLED, "text": ""}
    try:
        said = str(engine(arguments) or "")
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)[:160], "text": ""}
    if any(
        word in said.lower()
        for word in (
            "no tag was read",
            "write what",
            "not understood",
            "refus",
            "could not",
            "not installed",
            "nothing was",
            "reader(s) found",
        )
    ):
        return {"ok": False, "error": said, "text": ""}
    if said.startswith("The tag says:\n"):
        said = said.split("\n", 1)[1]
    return {"ok": True, "error": "", "text": said}


def cmd_ir(verb: str, code: str = "") -> dict:
    mod = _module("phone.ir_remote")
    if mod is None:
        return {"ok": False, "error": NOT_INSTALLED, "codes": []}
    verb = str(verb or "").strip().lower()
    code = str(code or "").strip()
    override = _override("SHANI_IR")
    if override:
        if verb == "list":
            got = _standalone(override, ["list"] + ([code] if code else []))
            if "error" in got:
                return {"ok": False, "error": got["error"], "codes": []}
            said = got.get("out", "")
            codes = [line.split()[-1] for line in said.splitlines() if line.strip()]
            return {
                "ok": bool(codes),
                "error": "" if codes else said,
                "codes": codes,
                "out": said,
            }
        if verb == "send":
            remote, _, key = code.partition(":")
            if not key:
                remote, _, key = code.partition("/")
            if not remote or not key:
                return {
                    "ok": False,
                    "error": "give the remote and button, as remote:button",
                    "codes": [],
                }
            got = _standalone(override, ["send", remote + ":" + key])
            said = got.get("out", "")
            ok = "sent" in said.lower()
            return {
                "ok": ok,
                "error": got.get("error", "") if not ok else "",
                "codes": [],
                "out": said,
            }
        return {"ok": False, "error": "ir needs list or send", "codes": []}
    try:
        if verb == "list":
            if code:
                names, why = mod.keys(code)
            else:
                names, why = mod.remotes()
            names = list(names or [])
            return {"ok": bool(names), "error": "" if names else why, "codes": names}
        if verb == "send":
            remote, _, key = code.partition(":")
            if not key:
                remote, _, key = code.partition("/")
            if not remote or not key:
                return {
                    "ok": False,
                    "error": "give the remote and button, as remote:button",
                    "codes": [],
                }
            said = str(mod.send_key(remote, key) or "")
            ok = said.startswith("Sent ")
            return {"ok": ok, "error": "" if ok else said, "codes": []}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)[:160], "codes": []}
    return {"ok": False, "error": "ir needs list or send", "codes": []}


def _line_kind(line_id: str) -> str:
    if line_id.startswith("sip-"):
        return "sip"
    return line_id if line_id in ("landline", "phone", "modem") else "other"


def cmd_lines() -> list[dict]:
    mod = _module("phone.lines")
    if mod is None:
        return []
    try:
        rows = list(mod.available())
    except Exception:  # noqa: BLE001
        rows = []
    out = [
        {
            "id": str(r.get("id") or ""),
            "name": str(r.get("name") or ""),
            "ready": bool(r.get("ready")),
            "kind": _line_kind(str(r.get("id") or "")),
        }
        for r in rows
        if isinstance(r, dict)
    ]
    landline = _module("phone.landline")
    if landline is not None:
        try:
            if not landline.is_set_up() and not any(r["id"] == "landline" for r in out):
                out.append(
                    {
                        "id": "landline",
                        "name": "Landline",
                        "ready": False,
                        "kind": "setup",
                    }
                )
        except Exception:  # noqa: BLE001
            pass
    return out


def _sip_fields(raw: str) -> tuple[dict, str]:
    try:
        fields = json.loads(raw)
    except (TypeError, ValueError):
        return {}, "the account must be JSON"
    return (
        (fields, "")
        if isinstance(fields, dict)
        else ({}, "the account must be an object")
    )


def cmd_sip_list() -> list[dict]:
    mod = _module("phone.sip_accounts")
    if mod is None:
        return []
    try:
        if hasattr(mod, "accounts"):
            rows = mod.accounts()
        else:  # an engine with only the file readers
            rows = mod._load()
        public = getattr(mod, "_public", lambda row: dict(row))
        return [
            {key: value for key, value in public(row).items() if key != "password"}
            for row in rows
            if isinstance(row, dict)
        ]
    except Exception:  # noqa: BLE001
        return []


def cmd_sip_add(raw: str) -> dict:
    mod = _module("phone.sip_accounts")
    if mod is None:
        return _ok(NOT_INSTALLED)
    fields, why = _sip_fields(raw)
    if why:
        return _ok(why)
    try:
        mod.add_account(fields)
    except Exception as exc:  # noqa: BLE001
        return _ok(str(exc)[:160])
    return _ok()


def cmd_sip_update(account_id: str, raw: str) -> dict:
    mod = _module("phone.sip_accounts")
    if mod is None:
        return _ok(NOT_INSTALLED)
    fields, why = _sip_fields(raw)
    if why:
        return _ok(why)
    try:
        mod.update_account(str(account_id or "").strip(), fields)
    except Exception as exc:  # noqa: BLE001
        return _ok(str(exc)[:160])
    return _ok()


def cmd_sip_remove(account_id: str) -> dict:
    mod = _module("phone.sip_accounts")
    if mod is None:
        return _ok(NOT_INSTALLED)
    try:
        if not mod.remove_account(str(account_id or "").strip()):
            return _ok("that account no longer exists")
    except Exception as exc:  # noqa: BLE001
        return _ok(str(exc)[:160])
    return _ok()


def _landline_state(mod) -> dict:
    state: dict[str, Any] = {
        "set_up": False,
        "ready": False,
        "enabled": False,
        "status": "",
    }
    try:
        state["set_up"] = bool(mod.is_set_up())
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)[:160], "state": state}
    if state["set_up"]:
        for key, method in (
            ("ready", "ready"),
            ("enabled", "enabled"),
            ("status", "status"),
        ):
            try:
                value = getattr(mod, method)()
                state[key] = str(value) if key == "status" else bool(value)
            except Exception:  # noqa: BLE001 - one unread field is not the whole line
                pass
    return {"ok": True, "error": "", "state": state}


def cmd_landline(verb: str, value: str = "") -> dict:
    mod = _module("phone.landline")
    if mod is None:
        return {"ok": False, "error": NOT_INSTALLED, "state": {}}
    verb = str(verb or "").strip().lower()
    value = str(value or "").strip()
    if verb == "state":
        return _landline_state(mod)
    try:
        if verb == "setup":
            if not value:
                return {
                    "ok": False,
                    "error": "give the router's address or let it find one",
                    "state": {},
                }
            return {
                "ok": True,
                "error": "",
                "state": {"set_up": False, "sent_to": str(mod.setup_start(value))},
            }
        if verb == "finish":
            if not value:
                return {
                    "ok": False,
                    "error": "give the code that was texted to you",
                    "state": {},
                }
            return {
                "ok": True,
                "error": "",
                "state": {"set_up": True, "number": str(mod.setup_finish(value))},
            }
        if verb == "forget":
            mod.forget()
            return {"ok": True, "error": "", "state": {"set_up": False}}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)[:160], "state": {}}
    return {
        "ok": False,
        "error": "landline needs state, setup, finish or forget",
        "state": {},
    }


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: devices.py <command> [args]"}))
        return 2
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "android":
        answer: Any = cmd_android(
            args[0] if args else "",
            args[1] if len(args) > 1 else "",
            " ".join(args[2:]),
        )
        code = 0  # an honest answer, even when the verb failed
    elif cmd == "connect":
        answer = cmd_connect(
            args[0] if args else "",
            args[1] if len(args) > 1 else "",
            " ".join(args[2:]),
        )
        code = 0
    elif cmd == "screen":
        answer = cmd_screen(
            args[0] if args else "",
            args[1] if len(args) > 1 else "",
            args[2] if len(args) > 2 else "",
            args[3] if len(args) > 3 else "",
        )
        code = 0
    elif cmd == "fm":
        answer = cmd_fm(args[0] if args else "", " ".join(args[1:]))
        code = 0
    elif cmd == "nfc":
        answer = cmd_nfc(args[0] if args else "", " ".join(args[1:]))
        code = 0
    elif cmd == "ir":
        answer = cmd_ir(args[0] if args else "", " ".join(args[1:]))
        code = 0
    elif cmd == "lines":
        answer = cmd_lines()
        code = 0
    elif cmd == "sip-list":
        answer = cmd_sip_list()
        code = 0
    elif cmd == "sip-add":
        answer = (
            cmd_sip_add(" ".join(args)) if args else _ok("sip-add needs an account")
        )
        code = 0
    elif cmd == "sip-update":
        answer = (
            cmd_sip_update(args[0], " ".join(args[1:]))
            if len(args) > 1
            else _ok("sip-update needs an id and an account")
        )
        code = 0
    elif cmd == "sip-remove":
        answer = cmd_sip_remove(args[0]) if args else _ok("sip-remove needs an id")
        code = 0
    elif cmd == "landline-state":
        answer = cmd_landline("state")
        code = 0
    elif cmd == "landline-setup":
        answer = cmd_landline("setup", " ".join(args))
        code = 0
    elif cmd == "landline-finish":
        answer = cmd_landline("finish", " ".join(args))
        code = 0
    elif cmd == "landline-forget":
        answer = cmd_landline("forget")
        code = 0
    else:
        answer = {"error": "unknown command: " + cmd}
        code = 2
    print(json.dumps(answer, ensure_ascii=False))
    return code


if __name__ == "__main__":
    sys.exit(main())
