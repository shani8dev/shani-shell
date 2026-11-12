#!/usr/bin/env python3
"""mpris-player — the shell's Media Player, as an MPRIS player on the session bus.

QtMultimedia plays, but it is not an MPRIS player: without this the bar's
"now playing", the sidebar's media card, the lock screen and the media keys
(which all read MPRIS) never saw what the shell itself was playing.

    mpris-player.py         run while the Media Player is open

stdin, one JSON object a line, from Services/PlayQueue - the state as it is:
    {"status": "Playing"|"Paused"|"Stopped", "title": "…", "url": "file:///…",
     "length": seconds, "position": seconds, "volume": 0..1, "rate": 1,
     "canNext": bool, "canPrevious": bool, "loop": "None"|"Track", "shuffle": bool}
    {"seeked": seconds}           the position jumped (MPRIS's Seeked signal)

stdout, one JSON object a line, what a client (playerctl, the bar) asked:
    {"op": "play"|"pause"|"toggle"|"stop"|"next"|"previous"|"raise"|"quit"}
    {"op": "seek", "to": seconds}       absolute, already computed from Seek's offset
    {"op": "volume", "value": 0..1}  {"op": "rate", "value": r}
    {"op": "loop", "value": "None"|"Track"|"Playlist"}  {"op": "shuffle", "value": bool}
    {"op": "open", "uri": "…"}

The bus name is org.mpris.MediaPlayer2.shani_media; it goes when stdin closes
(the window closed, the shell quit).
"""
from __future__ import annotations

import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = os.environ.get("SHANI_MPRIS_NAME", "org.mpris.MediaPlayer2.shani_media")
PATH = "/org/mpris/MediaPlayer2"
TRACK = "/dev/shani/media/track"

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/><method name="Previous"/><method name="Pause"/>
    <method name="PlayPause"/><method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition"><arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/></method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Player:
    def __init__(self, conn: Gio.DBusConnection):
        self.conn = conn
        self.state = {"status": "Stopped", "title": "", "url": "", "length": 0.0, "position": 0.0, "volume": 1.0,
                      "rate": 1.0, "canNext": False, "canPrevious": False, "loop": "None", "shuffle": False}

    # ---- what the bus reads ----------------------------------------------------
    def metadata(self) -> GLib.Variant:
        s = self.state
        md = {"mpris:trackid": GLib.Variant("o", TRACK)}
        if s["title"]:
            md["xesam:title"] = GLib.Variant("s", s["title"])
        if s["url"]:
            md["xesam:url"] = GLib.Variant("s", s["url"])
        if s["length"] > 0:
            md["mpris:length"] = GLib.Variant("x", int(s["length"] * 1e6))
        return GLib.Variant("a{sv}", md)

    def prop(self, iface: str, name: str) -> GLib.Variant | None:
        s = self.state
        if iface == ROOT_IFACE:
            return {
                "CanQuit": GLib.Variant("b", True), "CanRaise": GLib.Variant("b", True),
                "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", "Media Player"),
                "DesktopEntry": GLib.Variant("s", "dev.shani.MediaPlayer"),
                "SupportedUriSchemes": GLib.Variant("as", ["file"]),
                "SupportedMimeTypes": GLib.Variant("as", ["video/mp4", "video/webm", "video/x-matroska", "audio/mpeg", "audio/flac", "audio/ogg"]),
            }.get(name)
        playing = s["title"] != ""
        return {
            "PlaybackStatus": GLib.Variant("s", s["status"]), "LoopStatus": GLib.Variant("s", s["loop"]),
            "Rate": GLib.Variant("d", float(s["rate"])), "Shuffle": GLib.Variant("b", bool(s["shuffle"])),
            "Metadata": self.metadata(), "Volume": GLib.Variant("d", float(s["volume"])),
            "Position": GLib.Variant("x", int(s["position"] * 1e6)),
            "MinimumRate": GLib.Variant("d", 0.25), "MaximumRate": GLib.Variant("d", 4.0),
            "CanGoNext": GLib.Variant("b", bool(s["canNext"])), "CanGoPrevious": GLib.Variant("b", bool(s["canPrevious"]) or playing),
            "CanPlay": GLib.Variant("b", playing), "CanPause": GLib.Variant("b", playing),
            "CanSeek": GLib.Variant("b", playing and s["length"] > 0), "CanControl": GLib.Variant("b", True),
        }.get(name)

    # ---- what a client asked -----------------------------------------------------
    def call(self, conn, sender, path, iface, method, params, invocation):
        p = params.unpack()
        ops = {"Play": "play", "Pause": "pause", "PlayPause": "toggle", "Stop": "stop", "Next": "next",
               "Previous": "previous", "Raise": "raise", "Quit": "quit"}
        if method in ops:
            emit({"op": ops[method]})
        elif method == "Seek":
            emit({"op": "seek", "to": max(0.0, self.state["position"] + p[0] / 1e6)})
        elif method == "SetPosition":
            if p[0] == TRACK and 0 <= p[1] / 1e6 <= max(self.state["length"], 0):
                emit({"op": "seek", "to": p[1] / 1e6})
        elif method == "OpenUri":
            emit({"op": "open", "uri": p[0]})
        invocation.return_value(None)

    def get(self, conn, sender, path, iface, name):
        return self.prop(iface, name)

    def set(self, conn, sender, path, iface, name, value):
        v = value.unpack()
        key = {"Volume": "volume", "Rate": "rate", "LoopStatus": "loop", "Shuffle": "shuffle"}.get(name)
        if key is None:
            return False
        emit({"op": key, "value": v})
        return True

    # ---- the state, from the shell -------------------------------------------------
    def update(self, new: dict) -> None:
        if "seeked" in new:
            self.state["position"] = float(new["seeked"])
            self.conn.emit_signal(None, PATH, PLAYER_IFACE, "Seeked", GLib.Variant("(x)", (int(self.state["position"] * 1e6),)))
            return
        changed = [k for k, v in new.items() if k in self.state and self.state[k] != v]
        self.state.update({k: v for k, v in new.items() if k in self.state})
        # Position is not announced (MPRIS: clients ask for it); the rest is
        names = {"status": ["PlaybackStatus", "CanPlay", "CanPause"], "title": ["Metadata", "CanPlay", "CanPause", "CanSeek", "CanGoPrevious"],
                 "url": ["Metadata"], "length": ["Metadata", "CanSeek"], "volume": ["Volume"], "rate": ["Rate"],
                 "canNext": ["CanGoNext"], "canPrevious": ["CanGoPrevious"], "loop": ["LoopStatus"], "shuffle": ["Shuffle"]}
        props = {}
        for k in changed:
            for n in names.get(k, []):
                props[n] = self.prop(PLAYER_IFACE, n)
        if props:
            self.conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                  GLib.Variant("(sa{sv}as)", (PLAYER_IFACE, props, [])))


def main() -> int:
    loop = GLib.MainLoop()
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    player = Player(conn)
    for iface in node.interfaces:
        conn.register_object(PATH, iface, player.call, player.get, player.set)
    Gio.bus_own_name_on_connection(conn, BUS_NAME, Gio.BusNameOwnerFlags.NONE, None, lambda *_: loop.quit())

    stdin = GLib.IOChannel.unix_new(sys.stdin.fileno())

    def readable(channel, cond):
        if cond & (GLib.IO_HUP | GLib.IO_ERR):
            loop.quit()
            return False
        line = channel.readline()
        if not line:
            loop.quit()
            return False
        try:
            obj = json.loads(line)
            if isinstance(obj, dict):
                player.update(obj)
        except json.JSONDecodeError:
            pass
        return True

    GLib.io_add_watch(stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, readable)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
