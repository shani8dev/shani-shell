#!/usr/bin/env python3
"""Stands in for systemctl --user ($FAKE_COMPOSE): user units kept in units.json,
the same state the podman-compose stand-in uses. Calls and failures go to calls and
errors in that dir. Tool from argv[0] or FAKE_SYSTEMCTL_USER_TOOL.

The verbs every bridge uses work here: daemon-reload, start, stop, enable,
disable (--now included), show (with -p/--property and --value), is-enabled and
is-active. A verb systemctl itself does not have is rejected, not accepted.
"""

import json, os, sys, traceback

D = os.environ["FAKE_COMPOSE"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
os.makedirs(D, exist_ok=True)
S = os.path.join(D, "units.json")
st = json.load(open(S)) if os.path.exists(S) else {}


def canon(s):
    s = s.lower()
    if s.endswith(".py"):
        s = s[:-3]
    if s.startswith("fake-"):
        s = s[5:]
    return s


name = canon(
    os.environ.get("FAKE_SYSTEMCTL_USER_TOOL") or os.path.basename(sys.argv[0])
)
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(name + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


def unit_state(unit):
    return st.get(unit) or {}


def set_state(unit, **changes):
    state = dict(unit_state(unit))
    state.update(changes)
    st[unit] = state
    save()


def fail(message, code=1):
    print("systemctl: " + message, file=sys.stderr)
    sys.exit(code)


rc = 0
if not a or a[0] != "--user":
    fail("only --user is supported")
else:
    args = a[1:]
    v = args[0] if args else ""
    if v == "daemon-reload":
        pass
    elif v in ("start", "stop", "enable", "disable") and len(args) > 1:
        unit = args[-1]
        if v == "enable":
            set_state(unit, active=True, enabled=True)
        elif v == "disable":
            set_state(unit, active=False, enabled=False, next=0)
        elif v == "start":
            set_state(unit, active=True)
        else:
            set_state(unit, active=False, next=0)
    elif v == "is-enabled" and len(args) == 2:
        unit = args[1]
        on = bool(unit_state(unit).get("enabled", unit_state(unit).get("active")))
        print("enabled" if on else "disabled")
        rc = 0 if on else 1
    elif v == "is-active" and len(args) == 2:
        on = bool(unit_state(args[1]).get("active"))
        print("active" if on else "inactive")
        rc = 0 if on else 3
    elif v == "show" and len(args) > 1:
        props, values_only, unit = [], False, ""
        i = 1
        while i < len(args):
            word = args[i]
            if word in ("-p", "--property"):
                i += 1
                if i >= len(args):
                    fail("unsupported show")
                props.append(args[i])
            elif word == "--value":
                values_only = True
            elif word.startswith("--property="):
                props.append(word.split("=", 1)[1])
            elif word.startswith("-"):
                fail("unsupported show")
            else:
                unit = word
            i += 1
        if not unit:
            fail("unsupported show")
        state = unit_state(unit)
        active = bool(state.get("active"))
        unit_file = "enabled" if state.get("enabled", active) else "disabled"
        next_usec = int(state.get("next") or 0)
        values = {
            "ActiveState": "active" if active else "inactive",
            "SubState": "running" if active else "dead",
            "Description": (unit[:-8] if unit.endswith(".service") else unit)
            + " service",
            "UnitFileState": unit_file,
            "NextElapseUSecRealtime": str(next_usec),
            "NextElapseUSecMonotonic": "0",
        }
        unknown = [p for p in props if p not in values]
        if unknown:
            fail("unsupported show: " + unknown[0])
        for p in props or list(values):
            print(values[p] if values_only else p + "=" + values[p])
    else:
        fail("unknown command: %s" % v)
sys.exit(rc)
