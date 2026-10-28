#!/usr/bin/env python3
"""mock-chronoa — stands in for the Chronoa app while the shell is being built.

It owns the two names a real Chronoa owns on the session bus:

  dev.shani.chronoa.Gateways   Submit(gateway, text) -> reply   (exists today)
  dev.shani.chronoa.Agent      Turn(text) -> id, Approve(id, decision),
                               Event(json) signal                 (proposed)

and it calls back into the shell exactly as the real app does:

  org.shani.Chronoa.Mascot.Status(title, detail)
  org.shani.Chronoa.Windows.Cue(text, hold)

Nothing here is part of Chronoa: it exists so the shell's half of the contract
can be exercised end to end. The turn content is scripted, not model output.
"""

from __future__ import annotations

import json
import sys
import threading
import time
import uuid
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

# the contract lives with the bridge, the mock's counterpart
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bridge"))

from agent_contract import BUS_NAME as AGENT_NAME  # noqa: E402
from agent_contract import IFACE as AGENT_IFACE  # noqa: E402
from agent_contract import PATH as AGENT_PATH  # noqa: E402

GATEWAY_NAME = "dev.shani.chronoa.Gateways"
GATEWAY_PATH = "/dev/shani/chronoa/Gateways"
GATEWAY_IFACE = "dev.shani.chronoa.Gateways"

MASCOT_NAME = "org.shani.Chronoa.Mascot"
MASCOT_PATH = "/org/shani/Chronoa/Mascot"
MASCOT_IFACE = "org.shani.Chronoa.Mascot"

WINDOWS_NAME = "org.shani.Chronoa.Windows"
WINDOWS_PATH = "/org/shani/Chronoa/Windows"
WINDOWS_IFACE = "org.shani.Chronoa.Windows"

AGENT_XML = """
<node>
  <interface name="dev.shani.chronoa.Agent">
    <method name="Turn">
      <arg type="s" name="text" direction="in"/>
      <arg type="s" name="turn" direction="out"/>
    </method>
    <method name="Approve">
      <arg type="s" name="turn" direction="in"/>
      <arg type="s" name="decision" direction="in"/>
      <arg type="b" name="ok" direction="out"/>
    </method>
    <signal name="Event"><arg type="s" name="json"/></signal>
  </interface>
</node>
"""

GATEWAY_XML = """
<node>
  <interface name="dev.shani.chronoa.Gateways">
    <method name="Submit">
      <arg type="s" name="gateway" direction="in"/>
      <arg type="s" name="text" direction="in"/>
      <arg type="s" name="reply" direction="out"/>
    </method>
  </interface>
</node>
"""

conn = None
pending: dict = {}
pending_lock = threading.Lock()


def emit(ev: dict) -> None:
    conn.emit_signal(None, AGENT_PATH, AGENT_IFACE, "Event",
                     GLib.Variant("(s)", (json.dumps(ev),)))


def dbus_call(name, path, iface, method, params, timeout=1200):
    try:
        conn.call_sync(name, path, iface, method, params, None,
                       Gio.DBusCallFlags.NO_AUTO_START, timeout, None)
    except Exception:
        pass


def status(title: str, detail: str = "") -> None:
    dbus_call(MASCOT_NAME, MASCOT_PATH, MASCOT_IFACE, "Status",
              GLib.Variant("(ss)", (title, detail)))


def cue(text: str, hold: bool = False) -> None:
    dbus_call(WINDOWS_NAME, WINDOWS_PATH, WINDOWS_IFACE, "Cue",
              GLib.Variant("(sb)", (text, hold)))


def speak(text: str, delay: float = 0.035) -> None:
    """Stream a reply in word-ish chunks, the way a token stream arrives."""
    words = text.split(" ")
    for i, word in enumerate(words):
        piece = word if i == 0 else " " + word
        emit({"event": "reply", "text": piece})
        time.sleep(delay)


BATTERY = (
    "Battery is at 78% and discharging at about 11.4 W. Two processes account "
    "for most of it: the local model server has kept four threads busy for 41 "
    "minutes (~6.1 W), and Chrome is running 23 renderers (~3.2 W). Pausing the "
    "model server when it is idle should buy back roughly 40 minutes of runtime. "
    "Want me to set that up as a rule?"
)

TIDY = "Moved 14 files from Desktop into Documents/Inbox and left a manifest you can undo in one step."

SCREEN = (
    "You are in the ShaniOS shell spike: niri 26.04 nested under weston, "
    "Quickshell 0.3.2 on top, and the CDN dashboard open behind this panel. "
    "The panel is composited by niri with ext-background-effect, not by a "
    "backdrop-filter in the app."
)

DEFAULT = (
    "I can run that as a task. Nothing here is sent off the machine: the turn "
    "is handled by the local model server, and any tool that changes something "
    "asks you first. Say the word and I will start."
)


def turn_thread(tid: str, text: str) -> None:
    # what was asked, for the shell tests to assert on (dev/shell-test.sh)
    print(json.dumps({"turn": text}), flush=True)
    low = text.lower()
    status("Thinking", text[:70])
    emit({"event": "thinking", "text": ""})
    time.sleep(0.55)

    if any(w in low for w in ("tidy", "clean", "organise", "organize", "desktop")):
        emit({"event": "tool", "text": "Chronoa: Scanning ~/Desktop (14 files)"})
        cue("Chronoa: Scanning ~/Desktop")
        time.sleep(0.7)
        emit({"event": "approval", "id": tid,
              "text": "Chronoa wants to move 14 files",
              "options": ["Allow this once", "Deny"],
              "detail": "Desktop → Documents/Inbox. Every move is logged; "
                        "`chronoa undo` reverses the whole batch."})
        status("Thinking", "waiting for your approval")
        event = pending.get(tid)
        if event is None or not event.wait(90):
            emit({"event": "approval_closed", "id": tid})
            emit({"event": "reply", "text": "No answer, so I left the Desktop alone."})
            emit({"event": "done", "text": ""})
            status("Ready when you are", "")
            return
        grant = pending.pop(tid + ":decision", "Deny")
        pending.pop(tid, None)
        pending.pop(tid + ":decision", None)
        if grant != "Allow this once":
            emit({"event": "reply", "text": "Cancelled — nothing was moved."})
            emit({"event": "done", "text": ""})
            status("Ready when you are", "")
            return
        emit({"event": "tool", "text": "Chronoa: Moving 14 files → Documents/Inbox"})
        cue("Chronoa: Moved 14 files to Documents/Inbox", True)
        time.sleep(0.8)
        speak(TIDY)
        emit({"event": "done", "text": ""})
        status("Ready when you are", "")
        return

    if any(w in low for w in ("battery", "power", "drain", "eating")):
        emit({"event": "tool", "text": "Chronoa: Reading battery and power profile"})
        cue("Chronoa: Reading battery and power profile")
        time.sleep(0.65)
        emit({"event": "tool", "text": "Chronoa: Listing top energy consumers (41 min)"})
        cue("Chronoa: Listing top energy consumers")
        time.sleep(0.55)
        status("Speaking", "battery summary")
        speak(BATTERY)
        emit({"event": "done", "text": ""})
        status("Ready when you are", "")
        return

    if any(w in low for w in ("screen", "summar", "looking at", "this page")):
        emit({"event": "tool", "text": "Chronoa: Reading the focused window"})
        cue("Chronoa: Reading the focused window")
        time.sleep(0.7)
        status("Speaking", "screen summary")
        speak(SCREEN)
        emit({"event": "done", "text": ""})
        status("Ready when you are", "")
        return

    emit({"event": "tool", "text": "Chronoa: Planning the task"})
    cue("Chronoa: Planning the task")
    time.sleep(0.5)
    status("Speaking", "")
    speak(DEFAULT)
    emit({"event": "done", "text": ""})
    status("Ready when you are", "")


def on_agent_call(connection, sender, path, iface, method, params, invocation):
    global pending
    if method == "Turn":
        text = params.unpack()[0]
        tid = uuid.uuid4().hex[:8]
        pending[tid] = threading.Event()
        threading.Thread(target=turn_thread, args=(tid, text), daemon=True).start()
        invocation.return_value(GLib.Variant("(s)", (tid,)))
    elif method == "Approve":
        tid, decision = params.unpack()
        pending[tid + ":decision"] = decision
        event = pending.get(tid)
        if event is not None:
            event.set()
        invocation.return_value(GLib.Variant("(b)", (event is not None,)))
    else:
        invocation.return_dbus_error("dev.shani.chronoa.Error.Unknown", method)


def on_gateway_call(connection, sender, path, iface, method, params, invocation):
    if method == "Submit":
        _gateway, text = params.unpack()
        tid = uuid.uuid4().hex[:8]
        pending[tid] = threading.Event()
        threading.Thread(target=turn_thread, args=(tid, text), daemon=True).start()
        invocation.return_value(GLib.Variant("(s)", ("",)))
    else:
        invocation.return_dbus_error("dev.shani.chronoa.Error.Unknown", method)


def main() -> int:
    global conn
    loop = GLib.MainLoop()

    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    conn.register_object(AGENT_PATH,
                         Gio.DBusNodeInfo.new_for_xml(AGENT_XML).interfaces[0],
                         on_agent_call, None, None)
    conn.register_object(GATEWAY_PATH,
                         Gio.DBusNodeInfo.new_for_xml(GATEWAY_XML).interfaces[0],
                         on_gateway_call, None, None)

    for name in (AGENT_NAME, GATEWAY_NAME):
        Gio.bus_own_name_on_connection(conn, name, Gio.BusNameOwnerFlags.NONE, None, None)

    print("mock chronoa up", flush=True)
    loop.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
