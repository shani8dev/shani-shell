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

SOCK = os.environ.get("SHANI_CHRONOA_SOCK", "/run/user/0/shani-chronoa.sock")

MASCOT_NAME = "org.shani.Chronoa.Mascot"
MASCOT_PATH = "/org/shani/Chronoa/Mascot"
MASCOT_IFACE = "org.shani.Chronoa.Mascot"

WINDOWS_NAME = "org.shani.Chronoa.Windows"
WINDOWS_PATH = "/org/shani/Chronoa/Windows"
WINDOWS_IFACE = "org.shani.Chronoa.Windows"

GATEWAY_NAME = "dev.shani.chronoa.Gateways"
GATEWAY_PATH = "/dev/shani/chronoa/Gateways"
GATEWAY_IFACE = "dev.shani.chronoa.Gateways"

AGENT_NAME = "dev.shani.chronoa.Agent"
AGENT_PATH = "/dev/shani/chronoa/Agent"
AGENT_IFACE = "dev.shani.chronoa.Agent"

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
                   "visible": state_holder.get("visible", True)})
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
    try:
        call(AGENT_NAME, AGENT_PATH, AGENT_IFACE, "Approve",
             GLib.Variant("(ss)", (turn_id, decision)), timeout=4000)
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
        invocation.return_value(GLib.Variant("(b)", (False,)))
    elif method in ("Rect", "Notch"):
        broadcast({"type": "mascot-rect"})
        invocation.return_value(GLib.Variant("(iiii)", (0, 0, 1920, 44)))
    elif method == "PanelHeight":
        invocation.return_value(GLib.Variant("(i)", (44,)))
    elif method == "Pointer":
        invocation.return_value(GLib.Variant("(ii)", (0, 0)))
    elif method == "Scale":
        invocation.return_value(None)
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
    if ev.get("event") == "reply":
        broadcast({"type": "event", "event": "reply",
                   "text": ev.get("text", ""), "append": True})
    else:
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
    print(f"bridge up: {SOCK}", flush=True)
    main_loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
