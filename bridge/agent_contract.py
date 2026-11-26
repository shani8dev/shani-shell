"""Agent contract: the turn stream with approval, plus read-only inventory.

Implemented by `shani_chronoa.agent_service.AgentService`. This is the shell's
copy of Chronoa's contract, used by `chronoa-bridge.py` and `dev/mock-chronoa.py`
so neither can call a method the engine does not have. Keep it in step with
`shani-chronoa/usr/lib/shani-chronoa/shani_chronoa/agent_contract.py`.

Methods:
  Turn(text) -> turn_id        # starts a turn; reply lands via Event
  Approve(turn_id, decision) -> ok  # decision is the option label
  Write(instruction, text) -> result
  FindFiles(query, limit) -> json
  Inventory(section) -> json   # read-only facts for a shell panel

Signal:
  Event(json)                   # stream of turn events to the caller
"""

BUS_NAME = "dev.shani.chronoa.Agent"
PATH = "/dev/shani/chronoa/Agent"
IFACE = "dev.shani.chronoa.Agent"

#: The introspection XML. Interpolated so the name cannot drift from `IFACE`.
XML = f"""<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="{IFACE}">
    <method name="Turn">
      <arg name="text" type="s" direction="in"/>
      <arg name="turn_id" type="s" direction="out"/>
    </method>
    <method name="Approve">
      <arg name="turn_id" type="s" direction="in"/>
      <arg name="decision" type="s" direction="in"/>
      <arg name="ok" type="b" direction="out"/>
    </method>
    <method name="Write">
      <arg name="instruction" type="s" direction="in"/>
      <arg name="text" type="s" direction="in"/>
      <arg name="result" type="s" direction="out"/>
    </method>
    <method name="FindFiles">
      <arg name="query" type="s" direction="in"/>
      <arg name="limit" type="i" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="Inventory">
      <arg name="section" type="s" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <signal name="Event">
      <arg name="json" type="s"/>
    </signal>
  </interface>
</node>
"""
