#!/usr/bin/env python3
"""ratbag — a gaming mouse's own settings, through libratbag's ratbagctl.

  ratbag.py probe                     JSON: {"devices": [{id, name, dpi, dpis, rate, rates, buttons}]}
  ratbag.py dpi    DEVICE N           the active resolution's DPI (one of the device's own)
  ratbag.py rate   DEVICE N           the polling rate (Hz)
  ratbag.py button DEVICE N ACTION    left | right | middle | back | forward | disabled | key:KEY_…

Settings > Keyboard & input shows the page only when probe lists a device;
ratbagd starts on demand (D-Bus activation) when ratbagctl asks it. Settings
are written to the mouse itself, so they follow it to another computer.
Buttons are libratbag's numbers: 1 left, 2 right, 3 middle, 4 back, 5 forward.
SHANI_RATBAGCTL replaces ratbagctl (the tests' dev/fake-ratbagctl.sh).
"""

import json
import os
import re
import shlex
import subprocess
import sys

ACTIONS = {"left": "1", "right": "2", "middle": "3", "back": "4", "forward": "5"}
NAMES = {v: k for k, v in ACTIONS.items()}
# a mouse may offer hundreds of DPI steps (100 … 25600 by 50): offer the usual ones it has
COMMON_DPI = [400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000, 6400, 8000, 12000, 16000, 25600]


def ctl(*args):
    cmd = shlex.split(os.environ.get("SHANI_RATBAGCTL", "ratbagctl")) + list(args)
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    return p.returncode, p.stdout, p.stderr


def ints(text):
    return [int(x) for x in re.findall(r"\d+", text)]


def presets(dpis, current):
    if len(dpis) <= 12:
        out = list(dpis)
    else:
        out = [d for d in COMMON_DPI if d in dpis] or [dpis[0], dpis[len(dpis) // 2], dpis[-1]]
    if current and current not in out:
        out.append(current)
    return sorted(set(out))


def action_of(text):
    """ratbagctl's "is mapped to …" -> a choice the page shows."""
    m = re.match(r"'button (\d+)'", text)
    if m:
        return NAMES.get(m.group(1), "button " + m.group(1))
    m = re.match(r"key '(\w+)'", text)
    if m:
        return "key:" + m.group(1)
    if text == "none":
        return "disabled"
    return text.strip("'")


def info(dev):
    rc, out, _ = ctl(dev, "info")
    if rc != 0:
        return None
    d = {"id": dev, "name": "", "dpi": 0, "rate": 0, "buttons": []}
    in_active = False
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Profile "):
            in_active = "(active)" in s
        elif not in_active:
            continue
        elif s.startswith("Report Rate:"):
            d["rate"] = (ints(s) or [0])[0]
        elif re.match(r"\d+: \d+(x\d+)?dpi.*\(active\)", s):
            d["dpi"] = ints(s.split(":", 1)[1])[0]
        elif s.startswith("Button:"):
            m = re.match(r"Button: (\d+) is mapped to (.*)", s)
            if m:
                d["buttons"].append({"index": int(m.group(1)), "action": action_of(m.group(2))})
    return d


def probe():
    rc, out, _ = ctl("list")
    devices = []
    for line in out.splitlines() if rc == 0 else []:
        m = re.match(r"(\S+):\s+(.*\S)", line)
        if not m:
            continue
        d = info(m.group(1))
        if not d:
            continue
        d["name"] = m.group(2)
        d["dpis"] = presets(ints(ctl(d["id"], "dpi", "get-all")[1]), d["dpi"])
        d["rates"] = sorted(set(ints(ctl(d["id"], "rate", "get-all")[1])))
        devices.append(d)
    return {"devices": devices}


def change(argv):
    kind, dev = argv[0], argv[1]
    if kind == "dpi" and len(argv) == 3 and argv[2].isdigit():
        args = [dev, "dpi", "set", argv[2]]
    elif kind == "rate" and len(argv) == 3 and argv[2].isdigit():
        args = [dev, "rate", "set", argv[2]]
    elif kind == "button" and len(argv) == 4 and argv[2].isdigit():
        a = argv[3]
        if a in ACTIONS:
            args = [dev, "button", argv[2], "action", "set", "button", ACTIONS[a]]
        elif a == "disabled":
            args = [dev, "button", argv[2], "action", "set", "disabled"]
        elif re.fullmatch(r"key:KEY_[A-Z0-9_]+", a):
            args = [dev, "button", argv[2], "action", "set", "key", a[4:]]
        else:
            return {"ok": False, "error": "unknown action " + a}
    else:
        return {"ok": False, "error": "usage"}
    rc, _, err = ctl(*args)
    return {"ok": rc == 0, "error": "" if rc == 0 else (err.strip().splitlines() or ["failed"])[-1]}


def main(argv):
    try:
        if argv[1:2] == ["probe"]:
            print(json.dumps(probe()))
            return 0
        if len(argv) >= 4 and argv[1] in ("dpi", "rate", "button"):
            r = change(argv[1:])
            print(json.dumps(r))
            return 0 if r["ok"] else 1
    except (OSError, subprocess.TimeoutExpired) as e:   # no libratbag, or ratbagd not answering
        print(json.dumps({"devices": [], "ok": False, "error": str(e)}))
        return 1
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
