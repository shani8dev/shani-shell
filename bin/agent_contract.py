"""Proposed Agent contract: turn stream with approval.

This is a proposal, not a replacement. It is the contract Chronoa's own
shell-side bridge (`chronoa-bridge.py`) expects, and which the gateway's
fire-and-forget `Submit` does not provide.

Methods:
  Turn(text) -> turn_id        # starts a turn; reply lands via Event
  Approve(id, decision)         # user approves/denies a turn step

Signal:
  Event(json)                   # stream of turn events to the caller

Not implemented in core: this is the interface shape for the harness side.
"""

BUS_NAME = "dev.shani.chronoa.Agent"
PATH = "/dev/shani/chronoa/Agent"
IFACE = "dev.shani.chronoa.Agent"

# Introspection XML (matches the bridge's subscription and the mock's registration)
XML = """
<node>
  <interface name="dev.shani.chronoa.Agent">
    <method name="Turn">
      <arg type="s" name="text" direction="in"/>
      <arg type="s" name="turn_id" direction="out"/>
    </method>
    <method name="Approve">
      <arg type="s" name="turn_id" direction="in"/>
      <arg type="s" name="decision" direction="in"/>
    </method>
    <signal name="Event"><arg type="s" name="json"/></signal>
  </interface>
</node>
"""
