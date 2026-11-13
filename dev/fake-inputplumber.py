#!/usr/bin/env python3
"""A stand-in for InputPlumber on the system bus, for the suite (dev/shell-parts/
inputplumber.sh): org.shadowblip.InputPlumber with the Manager, one controller
(CompositeDevice0, "Legion Go Controller") and its D-Bus target device - the
interfaces and properties of bindings/dbus-xml in InputPlumber 0.84.

Presses come from a FIFO, one "<event> <value>" per line (`echo "ui_guide 1" >
/tmp/fake-inputplumber`), and are let through the way InputPlumber does: none in
intercept mode 0, only the guide button in 1 (which switches the device to 2, as
the real daemon does), everything in 2. Every change asked of it is logged to
/tmp/fake-inputplumber.log (targets=..., intercept=..., manageAll=...).
"""
import os
import threading

from gi.repository import Gio, GLib

BUS = "org.shadowblip.InputPlumber"
P = "/org/shadowblip/InputPlumber"
FIFO = "/tmp/fake-inputplumber"
LOG = "/tmp/fake-inputplumber.log"

XML = """<node>
 <interface name="org.shadowblip.InputManager">
  <property name="GamepadOrder" type="as" access="readwrite"/>
  <property name="ManageAllDevices" type="b" access="readwrite"/>
  <property name="SupportedTargetDeviceIds" type="as" access="read"/>
  <property name="SupportedTargetDevices" type="as" access="read"/>
  <property name="Version" type="s" access="read"/>
 </interface>
 <interface name="org.shadowblip.Input.CompositeDevice">
  <property name="Name" type="s" access="read"/>
  <property name="PersistentId" type="s" access="read"/>
  <property name="ProfileName" type="s" access="read"/>
  <property name="ProfilePath" type="s" access="read"/>
  <property name="InterceptMode" type="u" access="readwrite"/>
  <property name="TargetDevices" type="as" access="readwrite"/>
  <property name="DbusDevices" type="as" access="read"/>
 </interface>
 <interface name="org.shadowblip.Input.DBusDevice">
  <signal name="InputEvent"><arg name="event" type="s"/><arg name="value" type="d"/></signal>
  <property name="Name" type="s" access="read"/>
 </interface>
</node>"""
info = Gio.DBusNodeInfo.new_for_xml(XML)
IFACE = {i.name: i for i in info.interfaces}

state = {
    P + "/Manager": {"GamepadOrder": GLib.Variant("as", []), "ManageAllDevices": GLib.Variant("b", False),
                     "SupportedTargetDeviceIds": GLib.Variant("as", ["xb360", "xbox-elite", "xbox-series", "ds5", "deck", "gamepad"]),
                     "SupportedTargetDevices": GLib.Variant("as", ["Microsoft X-Box 360", "Microsoft X-Box Elite", "Microsoft X-Box Series",
                                                                   "Sony DualSense", "Valve Steam Deck", "Generic Gamepad"]),
                     "Version": GLib.Variant("s", "0.84.0-fake")},
    P + "/CompositeDevice0": {"Name": GLib.Variant("s", "Legion Go Controller"), "PersistentId": GLib.Variant("s", "lgo"),
                              "ProfileName": GLib.Variant("s", "Default"), "ProfilePath": GLib.Variant("s", ""),
                              "InterceptMode": GLib.Variant("u", 0),
                              "TargetDevices": GLib.Variant("as", ["xbox-elite", "keyboard", "mouse"]),
                              "DbusDevices": GLib.Variant("as", [P + "/devices/target/dbus0"])},
    P + "/devices/target/dbus0": {"Name": GLib.Variant("s", "DBus Device")},
}
IFACE_OF = {P + "/Manager": "org.shadowblip.InputManager", P + "/CompositeDevice0": "org.shadowblip.Input.CompositeDevice",
            P + "/devices/target/dbus0": "org.shadowblip.Input.DBusDevice"}


def log(line):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def changed(conn, path, name):
    conn.emit_signal(None, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                     GLib.Variant("(sa{sv}as)", (IFACE_OF[path], {name: state[path][name]}, [])))


def get_property(_conn, _sender, path, _iface, name):
    return state[path][name]


def set_property(conn, _sender, path, _iface, name, value):
    state[path][name] = value
    short = {"InterceptMode": "intercept", "TargetDevices": "targets", "ManageAllDevices": "manageAll"}.get(name, name)
    v = value.unpack()
    log(f"{short}={','.join(v) if isinstance(v, list) else (str(v).lower() if isinstance(v, bool) else v)}")
    changed(conn, path, name)
    return True


def press(conn, event, value):
    dev = P + "/CompositeDevice0"
    mode = state[dev]["InterceptMode"].unpack()
    if mode == 0 or (mode == 1 and event != "ui_guide"):
        log(f"to-game={event}")
        return
    if mode == 1 and event == "ui_guide" and value > 0:
        state[dev]["InterceptMode"] = GLib.Variant("u", 2)       # the guide button takes the controller, as InputPlumber does
        changed(conn, dev, "InterceptMode")
    conn.emit_signal(None, P + "/devices/target/dbus0", "org.shadowblip.Input.DBusDevice", "InputEvent",
                     GLib.Variant("(sd)", (event, float(value))))


def reader(conn):
    while True:
        with open(FIFO, encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) == 2:
                    GLib.idle_add(press, conn, parts[0], float(parts[1]))


def on_bus(conn, _name):
    for path, iface in IFACE_OF.items():
        conn.register_object(path, IFACE[iface], None, get_property, set_property)


def on_name(conn, _name):
    if not os.path.exists(FIFO):
        os.mkfifo(FIFO)
    threading.Thread(target=reader, args=(conn,), daemon=True).start()


open(LOG, "w").close()
Gio.bus_own_name(Gio.BusType.SYSTEM, BUS, Gio.BusNameOwnerFlags.NONE, on_bus, on_name, None)
GLib.MainLoop().run()
