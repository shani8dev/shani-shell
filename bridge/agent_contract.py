"""Agent contract: the turn stream with approval, plus read-only inventory.

Implemented by `shani_chronoa.agent_service.AgentService`. This is the shell's
copy of Chronoa's contract, used by `chronoa-bridge.py` and `dev/mock-chronoa.py`
so neither can call a method the engine does not have. Keep it in step with
`shani-chronoa/usr/lib/shani-chronoa/shani_chronoa/agent_contract.py`.

Methods:
  (The full method list is the XML below, copied from Chronoa's file;
  tests/test_agent_contract.py fails when the two differ.)

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
    <method name="TurnWith">
      <arg name="text" type="s" direction="in"/>
      <arg name="options_json" type="s" direction="in"/>
      <arg name="turn_id" type="s" direction="out"/>
    </method>
    <method name="Approve">
      <arg name="turn_id" type="s" direction="in"/>
      <arg name="decision" type="s" direction="in"/>
      <arg name="ok" type="b" direction="out"/>
    </method>
    <method name="Cancel">
      <arg name="turn_id" type="s" direction="in"/>
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
    <method name="SettingsList">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="SettingsGet">
      <arg name="name" type="s" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="SettingsSet">
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="s" direction="in"/>
      <arg name="confirm" type="b" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="SettingsPreset">
      <arg name="name" type="s" direction="in"/>
      <arg name="confirm" type="b" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="SettingsEmail">
      <arg name="values_json" type="s" direction="in"/>
      <arg name="confirm" type="b" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="ModelsList">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="ModelsUse">
      <arg name="name" type="s" direction="in"/>
      <arg name="confirm" type="b" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="SetupState">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="SetupStep">
      <arg name="step" type="s" direction="in"/>
      <arg name="value" type="s" direction="in"/>
      <arg name="confirm" type="b" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="Conversations">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="ConversationsResume">
      <arg name="ref" type="s" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="ConversationsRename">
      <arg name="ref" type="s" direction="in"/>
      <arg name="title" type="s" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="ConversationsDelete">
      <arg name="ref" type="s" direction="in"/>
      <arg name="confirm" type="b" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="MemoryList">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="MemoryDecide">
      <arg name="id" type="s" direction="in"/>
      <arg name="decision" type="s" direction="in"/>
      <arg name="confirm" type="b" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="Routines">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="RoutinesRun">
      <arg name="name" type="s" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="Triggers">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="Notices">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="NoticesDismiss">
      <arg name="id" type="s" direction="in"/>
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="VoiceEngines">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="Activity">
      <arg name="json" type="s" direction="out"/>
    </method>
    <method name="DiagnosticsProbe">
      <arg name="json" type="s" direction="out"/>
    </method>
    <signal name="Event">
      <arg name="json" type="s"/>
    </signal>
  </interface>
</node>
"""
