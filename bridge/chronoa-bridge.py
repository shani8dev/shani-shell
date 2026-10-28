#!/usr/bin/env python3
"""shani-chronoa-shell-bridge — the D-Bus face of the shell.

Chronoa already knows how to talk to a Linux shell. It calls:

  org.shani.Chronoa.Mascot   Status(title, detail), Show(visible), Art(path),
                             Rect()/Notch(), PanelHeight(), Pointer(), Scale()
  org.shani.Chronoa.Windows  Cue(text, hold)      -- the tool-call pill

and accepts text through:

  dev.shani.chronoa.Gateways  Submit(gateway, text) -> reply   (ask-only)

Quickshell cannot export D-Bus objects, so this process owns those names and
bridges them to the shell over a unix socket (one JSON object per line).

The shell -> bridge side also carries the one interface Chronoa does not have
yet: a turn stream. `dev.shani.chronoa.Agent` is the proposed contract
(Turn(text) -> id, Approve(id, decision), Event(json) signal). When the name is
absent the bridge falls back to Gateways.Submit and says so.
"""

from __future__ import annotations

import json
import os
import socket
import socketserver
import sys
import threading

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from agent_contract import BUS_NAME as AGENT_NAME  # noqa: E402
from agent_contract import IFACE as AGENT_IFACE  # noqa: E402
from agent_contract import PATH as AGENT_PATH  # noqa: E402
from logind import Logind  # noqa: E402
from turn_filter import TurnFilter  # noqa: E402

SOCK = os.environ.get("SHANI_CHRONOA_SOCK") or os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}",
    "shani-chronoa.sock")

MASCOT_NAME = "org.shani.Chronoa.Mascot"
MASCOT_PATH = "/org/shani/Chronoa/Mascot"
MASCOT_IFACE = "org.shani.Chronoa.Mascot"

WINDOWS_NAME = "org.shani.Chronoa.Windows"
WINDOWS_PATH = "/org/shani/Chronoa/Windows"
WINDOWS_IFACE = "org.shani.Chronoa.Windows"

GATEWAY_NAME = "dev.shani.chronoa.Gateways"
GATEWAY_PATH = "/dev/shani/chronoa/Gateways"
GATEWAY_IFACE = "dev.shani.chronoa.Gateways"

APP_NAME = "dev.shani.chronoa"
APP_PATH = "/dev/shani/chronoa"

MASCOT_XML = """
<node>
  <interface name="org.shani.Chronoa.Mascot">
    <method name="Art">
      <arg type="s" name="path" direction="in"/>
      <arg type="b" name="loaded" direction="out"/>
    </method>
    <method name="Status">
      <arg type="s" name="title" direction="in"/>
      <arg type="s" name="detail" direction="in"/>
    </method>
    <method name="Rect">
      <arg type="i" name="x" direction="out"/>
      <arg type="i" name="y" direction="out"/>
      <arg type="i" name="w" direction="out"/>
      <arg type="i" name="h" direction="out"/>
    </method>
    <method name="Notch">
      <arg type="i" name="x" direction="out"/>
      <arg type="i" name="y" direction="out"/>
      <arg type="i" name="w" direction="out"/>
      <arg type="i" name="h" direction="out"/>
    </method>
    <method name="PanelHeight"><arg type="i" name="height" direction="out"/></method>
    <method name="Pointer">
      <arg type="i" name="x" direction="out"/>
      <arg type="i" name="y" direction="out"/>
    </method>
    <method name="Show"><arg type="b" name="visible" direction="in"/></method>
    <method name="Scale"><arg type="i" name="factor" direction="in"/></method>
    <method name="Host"><arg type="s" name="presentation" direction="out"/></method>
  </interface>
</node>
"""

WINDOWS_XML = """
<node>
  <interface name="org.shani.Chronoa.Windows">
    <method name="Cue">
      <arg type="s" name="text" direction="in"/>
      <arg type="b" name="hold" direction="in"/>
    </method>
  </interface>
</node>
"""

clients: set = set()
clients_lock = threading.Lock()
conn_holder: dict = {}
state_holder: dict = {}
# Reported by the shell ("geometry" op); zero until it has drawn the Island.
geometry: dict = {"mascot": (0, 0, 0, 0), "island": (0, 0, 0, 0), "panel": 48}
turn_filter = TurnFilter()
logind = Logind(lambda obj: broadcast(obj))


def broadcast(obj: dict) -> None:
    line = (json.dumps(obj, ensure_ascii=False) + "\n").encode()
    with clients_lock:
        dead = []
        for wfile in clients:
            try:
                wfile.write(line)
                wfile.flush()
            except Exception:
                dead.append(wfile)
        for wfile in dead:
            clients.discard(wfile)


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        with clients_lock:
            clients.add(self.wfile)
        broadcast({"type": "hello", "state": state_holder.get("state", "idle"),
                   "title": state_holder.get("title", "Ready when you are"),
                   "detail": state_holder.get("detail", ""),
                   "visible": state_holder.get("visible", True),
                   "art": state_holder.get("art", ""),
                   "scale": state_holder.get("scale", 1)})
        try:
            for raw in self.rfile:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    msg = json.loads(raw)
                except Exception:
                    continue
                threading.Thread(target=handle_request, args=(msg,), daemon=True).start()
        except Exception:
            pass
        finally:
            with clients_lock:
                clients.discard(self.wfile)


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def bus():
    return conn_holder["conn"]


def call(bus_name, path, iface, method, params, timeout=8000):
    return bus().call_sync(bus_name, path, iface, method, params, None,
                           Gio.DBusCallFlags.NO_AUTO_START, timeout, None)


def has_owner(name: str) -> bool:
    try:
        r = bus().call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                            "org.freedesktop.DBus", "NameHasOwner",
                            GLib.Variant("(s)", (name,)), None,
                            Gio.DBusCallFlags.NONE, 1000, None)
        return bool(r.unpack()[0])
    except Exception:
        return False


# ---- shell -> Chronoa ----------------------------------------------------

def handle_request(msg: dict) -> None:
    op = msg.get("op")
    if op == "ask":
        ask(msg.get("text", ""))
    elif op == "action":
        action(msg.get("name", ""))
    elif op == "approve":
        approve(msg.get("id", ""), msg.get("decision", "deny"))
    elif op == "ping":
        broadcast({"type": "pong"})
    elif op == "geometry":
        # Where the shell draws the companion, in logical pixels: Chronoa aims
        # the mascot's gaze from Rect() and sizes nothing else from it.
        for key in ("mascot", "island"):
            if isinstance(msg.get(key), list) and len(msg[key]) == 4:
                geometry[key] = tuple(int(v) for v in msg[key])
        if isinstance(msg.get("panel"), (int, float)):
            geometry["panel"] = int(msg["panel"])
    elif op == "locked":
        logind.locked(bool(msg.get("locked")))
    elif op == "release-sleep":
        # "lock before suspend" is off: let sleep go without a lock
        logind.release_sleep()


def ask(text: str) -> None:
    text = (text or "").strip()
    if not text:
        return
    broadcast({"type": "event", "event": "thinking", "text": ""})
    if has_owner(AGENT_NAME):
        try:
            r = call(AGENT_NAME, AGENT_PATH, AGENT_IFACE, "Turn",
                     GLib.Variant("(s)", (text,)), timeout=4000)
            turn_id = r.unpack()[0]
            broadcast({"type": "turn", "id": turn_id})
            # Events that raced ahead of the Turn reply are ours too.
            for ev in turn_filter.take(turn_id):
                forward_event(ev)
            return
        except Exception as exc:
            broadcast({"type": "error", "text": f"Agent.Turn failed: {exc}"})
            return
    if has_owner(GATEWAY_NAME):
        try:
            call(GATEWAY_NAME, GATEWAY_PATH, GATEWAY_IFACE, "Submit",
                 GLib.Variant("(ss)", ("shell", text)), timeout=120000)
            broadcast({"type": "notice",
                       "text": "Handed to Chronoa's own window (gateway reply lands there)."})
            broadcast({"type": "event", "event": "done", "text": ""})
        except Exception as exc:
            broadcast({"type": "error", "text": f"Submit refused: {exc}"})
        return
    broadcast({"type": "error",
               "text": "Chronoa is not running (no Agent and no Gateways on the bus)."})


def action(name: str) -> None:
    if not name:
        return
    try:
        if name.startswith("page:"):
            call(APP_NAME, APP_PATH, "dev.shani.chronoa", "show-page",
                 GLib.Variant("(s)", (name[5:],)), timeout=4000)
        else:
            # org.freedesktop.Application.ActivateAction
            bus().call_sync(APP_NAME, APP_PATH, "org.freedesktop.Application",
                            "ActivateAction",
                            GLib.Variant("(sava{sv})", (name, [], {})), None,
                            Gio.DBusCallFlags.NO_AUTO_START, 4000, None)
        broadcast({"type": "notice", "text": f"asked Chronoa to {name.replace('-', ' ')}"})
    except Exception as exc:
        broadcast({"type": "error", "text": f"action {name} failed: {exc}"})


def approve(turn_id: str, decision: str) -> None:
    if not turn_id:
        broadcast({"type": "error", "text": "approval had no turn id"})
        return
    try:
        r = call(AGENT_NAME, AGENT_PATH, AGENT_IFACE, "Approve",
                 GLib.Variant("(ss)", (turn_id, decision)), timeout=4000)
        accepted = bool(r.unpack()[0]) if r is not None else False
        if not accepted:
            # The card was answered after its wait had already ended (timeout,
            # or a newer question for the same turn). Saying so is better than
            # letting the panel show a decision that reached nothing.
            broadcast({"type": "event", "event": "approval_closed", "id": turn_id})
            broadcast({"type": "notice",
                       "text": "That approval had already expired, so nothing changed."})
    except Exception as exc:
        broadcast({"type": "error", "text": f"approval failed: {exc}"})


# ---- Chronoa -> shell ----------------------------------------------------

def on_mascot_call(connection, sender, path, iface, method, params, invocation):
    if method == "Status":
        title, detail = params.unpack()
        state = "idle"
        low = (title or "").lower()
        for probe in ("listening", "thinking", "speaking", "working"):
            if probe in low:
                state = probe
        state_holder.update(state=state, title=title, detail=detail)
        broadcast({"type": "state", "state": state, "title": title, "detail": detail})
        invocation.return_value(None)
    elif method == "Show":
        visible = params.unpack()[0]
        state_holder["visible"] = bool(visible)
        broadcast({"type": "mascot", "visible": bool(visible)})
        invocation.return_value(None)
    elif method == "Art":
        # Chronoa writes each frame atomically (tmp + rename) and asks us to
        # load it. "Loaded" must be the truth: on False it hides the companion
        # rather than leave a stale frame looking live.
        path = params.unpack()[0]
        ok = os.path.isfile(path) and os.access(path, os.R_OK)
        if ok:
            state_holder["art"] = path
            state_holder["rev"] = state_holder.get("rev", 0) + 1
            broadcast({"type": "art", "path": path, "rev": state_holder["rev"]})
        invocation.return_value(GLib.Variant("(b)", (ok,)))
    elif method == "Rect":
        invocation.return_value(GLib.Variant("(iiii)", geometry["mascot"]))
    elif method == "Notch":
        invocation.return_value(GLib.Variant("(iiii)", geometry["island"]))
    elif method == "PanelHeight":
        invocation.return_value(GLib.Variant("(i)", (geometry["panel"],)))
    elif method == "Pointer":
        invocation.return_value(GLib.Variant("(ii)", (0, 0)))
    elif method == "Scale":
        state_holder["scale"] = int(params.unpack()[0])
        broadcast({"type": "scale", "factor": state_holder["scale"]})
        invocation.return_value(None)
    elif method == "Host":
        # The shell draws the companion itself (the Island in its bar);
        # Chronoa's mascot.create() gives a host the strip surface.
        invocation.return_value(GLib.Variant("(s)", ("island",)))
    else:
        invocation.return_dbus_error("org.shani.Chronoa.Error.Unknown", method)


def on_windows_call(connection, sender, path, iface, method, params, invocation):
    if method == "Cue":
        text, hold = params.unpack()
        broadcast({"type": "cue", "text": text, "hold": bool(hold)})
        invocation.return_value(None)
    else:
        invocation.return_dbus_error("org.shani.Chronoa.Error.Unknown", method)


def on_agent_event(connection, sender, path, iface, signal, params):
    payload = params.unpack()[0]
    try:
        ev = json.loads(payload)
    except Exception:
        return
    if not isinstance(ev, dict):
        return
    # Every client on the bus sees every turn. Only render ours.
    if turn_filter.see(ev):
        forward_event(ev)


def forward_event(ev: dict) -> None:
    if ev.get("event") == "reply":
        # Replies arrive in chunks and are appended to one bubble; say so
        # instead of making the panel guess from an empty previous chunk.
        broadcast({"type": "event", "event": "reply", "turn": ev.get("turn"),
                   "text": ev.get("text", ""), "append": True})
    else:
        ev = dict(ev)
        ev["type"] = "event"
        broadcast(ev)


def own(name, on_acquired):
    Gio.bus_own_name(Gio.BusType.SESSION, name, Gio.BusNameOwnerFlags.NONE,
                     on_acquired, None, None)


def main() -> int:
    for path in (SOCK,):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    server = Server(SOCK, Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    os.chmod(SOCK, 0o600)

    main_loop = GLib.MainLoop()

    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    conn_holder["conn"] = connection

    connection.register_object(MASCOT_PATH, Gio.DBusNodeInfo.new_for_xml(MASCOT_XML).interfaces[0],
                               on_mascot_call, None, None)
    connection.register_object(WINDOWS_PATH, Gio.DBusNodeInfo.new_for_xml(WINDOWS_XML).interfaces[0],
                               on_windows_call, None, None)
    connection.signal_subscribe(AGENT_NAME, AGENT_IFACE, "Event", AGENT_PATH,
                                None, Gio.DBusSignalFlags.NONE, on_agent_event)

    # One connection owns both names: a client calling Windows must land on the
    # same connection the object is registered on.
    Gio.bus_own_name_on_connection(connection, MASCOT_NAME, Gio.BusNameOwnerFlags.NONE,
                                   None, None)
    Gio.bus_own_name_on_connection(connection, WINDOWS_NAME, Gio.BusNameOwnerFlags.NONE,
                                   None, None)
    logind.start()
    print(f"bridge up: {SOCK}", flush=True)
    main_loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
