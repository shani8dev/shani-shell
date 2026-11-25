"""The shell's minimal IRC client: bridge, service, window and wiring.

The bridge is driven here with a fake socket, so nothing in this file touches
the network. The QML is checked statically (there is no QML runtime in pytest):
the tests pin the wiring a real session needs - a long-running Process, the
window's controls, accessible names, and the empty/error states.
"""

import importlib.machinery
import importlib.util
import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location("shani_irc", ROOT / "bridge" / "irc.py")
irc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(irc)

BRIDGE = (ROOT / "bridge/irc.py").read_text(encoding="utf-8")
SERVICE = (ROOT / "shani/Services/Irc.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "shani/Modules/Irc/IrcWindow.qml").read_text(encoding="utf-8")
UI = (ROOT / "shani/Common/Ui.qml").read_text(encoding="utf-8")
SHELL = (ROOT / "shani/shell.qml").read_text(encoding="utf-8")
SHELL_APPS = (ROOT / "shani/Services/ShellApps.js").read_text(encoding="utf-8")


class FakeSocket:
    """Just enough of a socket for sendall/recv/close; no real network."""

    def __init__(self, inbox=None):
        self.sent = []
        self.inbox = list(inbox or [])
        self.closed = False

    def sendall(self, data):
        self.sent.append(data.decode("utf-8"))

    def recv(self, _n):
        if not self.inbox:
            raise BlockingIOError
        return self.inbox.pop(0)

    def close(self):
        self.closed = True


@pytest.fixture
def session():
    events, sock = [], FakeSocket()
    client = irc.IrcClient(make_socket=lambda host, port: sock, out=events.append)
    client.handle(
        {
            "op": "connect",
            "server": "irc.example",
            "port": 6667,
            "nick": "tester",
            "tls": False,
        }
    )
    client.feed(":irc.example 001 tester :Welcome")
    return client, sock, events


# ---- bridge: the protocol over one persistent socket --------------------------


def test_bridge_is_a_long_running_process_not_a_one_shot_cli():
    assert "def main()" in BRIDGE
    assert "select.select" in BRIDGE
    assert "sys.stdin.readline()" in BRIDGE
    assert "while True" in BRIDGE
    for op in ("connect", "join", "part", "say", "quit"):
        assert 'op == "%s"' % op in BRIDGE
    assert 'op in ("channels", "channel")' in BRIDGE
    assert 'op in ("messages", "poll")' in BRIDGE


def test_connect_handshake_and_status_on_a_single_socket(session):
    client, sock, events = session
    assert client.status == "connected"
    assert sock.sent[0].startswith("NICK tester")
    assert sock.sent[1].startswith("USER tester")
    # many commands later: still the same socket, never reopened
    before = len(sock.sent)
    client.handle({"op": "join", "channel": "#shani"})
    assert sock.sent[-1] == "JOIN #shani\r\n"
    assert len(sock.sent) == before + 1
    assert events[0]["event"] == "status" and events[0]["status"] == "connecting"
    assert any(e["event"] == "status" and e["status"] == "connected" for e in events)


def test_join_part_channels_and_nicks(session):
    client, sock, events = session
    client.handle({"op": "join", "channel": "general"})
    client.handle({"op": "join", "channel": "#other"})
    assert client.channels == ["#general", "#other"]
    client.feed(":irc.example 353 tester = #general :alice bob tester")
    assert client.nicks["#general"] == ["alice", "bob", "tester"]
    assert any(
        e["event"] == "nicks" and e["nicks"] == client.nicks["#general"] for e in events
    )
    listed = client.channels_now()
    assert listed == ["#general", "#other"]
    assert events[-1]["event"] == "channels" and events[-1]["channels"] == listed
    client.handle({"op": "part", "channel": "#other"})
    assert client.channels == ["#general"]
    assert sock.sent[-1] == "PART #other\r\n"


def test_messages_since_and_mention_highlight(session):
    client, _sock, events = session
    client.feed(":alice!u@h PRIVMSG #general :hello tester, welcome")
    client.feed(":bob!u@h PRIVMSG #general :just saying hi")
    assert len(client.messages) == 2
    assert client.messages[0]["mention"] is True
    assert client.messages[1]["mention"] is False
    assert client.messages[0]["channel"] == "#general"
    assert client.messages[0]["nick"] == "alice"
    assert client.messages[0]["time"]
    # since is an incremental cursor, so a poll never replays the timeline
    assert [m["seq"] for m in client.messages_since(1)] == [2]
    assert any(e["event"] == "message" and e["message"]["mention"] for e in events)
    # your own line is never a mention of yourself
    client.handle({"op": "say", "channel": "#general", "text": "tester here"})
    assert client.messages[-1]["nick"] == "tester"
    assert client.messages[-1]["mention"] is False


def test_ping_reply_and_socket_read_are_driven_by_the_loop(session):
    client, sock, events = session
    client.feed("PING :abc123")
    assert sock.sent[-1] == "PONG :abc123\r\n"
    sock.inbox.append(b":carol!u@h PRIVMSG #general :from the wire\r\n")
    client.read()
    assert client.messages[-1]["text"] == "from the wire"
    sock.inbox.append(b"")  # EOF: connection went away
    client.read()
    assert client.status == "disconnected"
    assert sock.closed


def test_connect_failure_and_nick_collision_report_errors():
    def refuse(host, port):
        raise OSError("no route")

    c = irc.IrcClient(make_socket=refuse, out=lambda _e: None)
    c.handle({"op": "connect", "server": "irc.example", "nick": "tester"})
    assert c.status == "error" and "no route" in c.error
    sock = FakeSocket()
    events = []
    c = irc.IrcClient(make_socket=lambda h, p: sock, out=events.append)
    c.handle({"op": "connect", "server": "irc.example", "nick": "tester"})
    c.feed(":irc.example 433 * tester :Nickname is already in use")
    assert c.status == "error" and "in use" in c.error
    c.handle({"op": "nonsense"})
    assert events[-1]["event"] == "error"


def test_quit_closes_the_socket_and_clears_the_view(session):
    client, sock, events = session
    client.handle({"op": "join", "channel": "#general"})
    client.handle({"op": "quit"})
    assert sock.sent[-1] == "QUIT :bye\r\n"
    assert sock.closed and client.channels == []
    assert events[-1]["event"] == "status" and events[-1]["status"] == "disconnected"


# ---- service: a long-running Process, not a per-command job -------------------


def test_service_drives_one_process_over_stdin():
    assert "pragma Singleton" in SERVICE
    assert "Process {" in SERVICE
    assert "stdinEnabled: true" in SERVICE
    assert 'command: ["python3", root.tool]' in SERVICE
    assert "SplitParser { onRead: line => root.onLine(line) }" in SERVICE
    assert "irc.py" in SERVICE
    assert (
        "function send(obj)" in SERVICE and "proc.write(JSON.stringify(obj)" in SERVICE
    )
    assert "function connect()" in SERVICE
    assert "function join(channel)" in SERVICE
    assert "function part(channel)" in SERVICE
    assert "function say(channel, text)" in SERVICE
    assert "function quit()" in SERVICE and "function reconnect()" in SERVICE
    assert "function markRead(channel)" in SERVICE
    for key in (
        "status",
        "error",
        "channels",
        "nicks",
        "messages",
        "unread",
        "mentions",
        "activeChannel",
    ):
        assert ("property" in SERVICE) and key in SERVICE


def test_service_keeps_unread_and_mention_counts():
    assert "function noteMessage(msg)" in SERVICE
    assert "if (!root.shown || msg.channel !== root.activeChannel)" in SERVICE
    assert "if (msg.mention)" in SERVICE
    assert "root.lastSeq = msg.seq" in SERVICE
    assert 'op: "messages", since: root.lastSeq' in SERVICE
    assert 'msg.event === "message"' in SERVICE
    assert 'msg.event === "messages"' in SERVICE
    assert 'msg.event === "nicks"' in SERVICE
    assert 'msg.event === "status"' in SERVICE


# ---- window: the parts a person actually uses ---------------------------------


def test_window_has_the_server_form_and_channel_join():
    for needle in (
        'appName: "IRC"',
        "visible: Ui.irc",
        "onGone: Ui.irc = false",
        "irc-server",
        "irc-port",
        "irc-nick",
        "tlsBox",
        "function connectClicked()",
        "function joinClicked()",
        "id: joinField",
        "id: joinButton",
        "Irc.join(ch)",
    ):
        assert needle in WINDOW, needle
    assert (
        'text: (Irc.status === "disconnected" || Irc.status === "error") ? Tr.t("Connect") : Tr.t("Disconnect")'
        in WINDOW
    )


def test_window_has_timeline_send_nicks_and_unread_badges():
    for needle in (
        "function shownMessages()",
        "function nicksFor(channel)",
        "id: timeline",
        "model: win.shownMessages()",
        "modelData.time",
        "modelData.nick",
        "modelData.mention",
        "id: sendField",
        "function sendClicked()",
        "Irc.say(",
        "Irc.markRead(modelData)",
        "Irc.unread[modelData]",
        "Irc.mentions[modelData]",
        "win.nicksFor(Irc.activeChannel)",
    ):
        assert needle in WINDOW, needle
    assert (
        'color: modelData.mention ? Theme.alpha(Theme.accent, 0.16) : "transparent"'
        in WINDOW
    )


def test_window_has_reconnect_status_empty_and_error_states_and_at_names():
    assert "function statusText()" in WINDOW
    assert "id: reconnectButton" in WINDOW and "Irc.reconnect()" in WINDOW
    assert 'visible: Irc.error !== ""' in WINDOW
    assert 'Tr.t("No channels — connect and join one")' in WINDOW
    assert 'Tr.t("No messages yet — say hello")' in WINDOW
    assert 'Tr.t("Connect and join a channel to start chatting")' in WINDOW
    assert WINDOW.count("Accessible.name:") >= 8
    assert 'Accessible.name: Tr.t("Use TLS")' in WINDOW
    assert "Accessible.role: Accessible.ListItem" in WINDOW
    assert "onVisibleChanged: Irc.shown = visible" in WINDOW


# ---- wiring: one property, one loader, one IPC pair, one state key ------------


def test_ui_has_exactly_one_new_bool_and_shell_loads_the_window():
    assert re.search(r"^\s*property bool irc: false\b", UI, re.M)
    assert len(re.findall(r"property bool irc: false", UI)) == 1
    assert 'LazyLoader { active: Ui.irc; source: "Modules/Irc/IrcWindow.qml" }' in SHELL
    assert "Irc," in SHELL  # singleton stays alive


def test_shell_exposes_the_ipc_and_the_state_key():
    assert "function ircOpen() { Ui.closeAll(); Ui.irc = true; }" in SHELL
    assert "function ircClose() { Ui.irc = false; }" in SHELL
    assert re.search(r"\bircShown: Ui\.irc\b", SHELL)


def _cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
    mod = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("shani_cli", loader)
    )
    loader.exec_module(mod)
    return mod


def test_app_entry_agrees_with_shell_apps_and_describes_a_real_window():
    cli = _cli()
    spec = cli.APPS["irc"]
    assert spec[0] == "dev.shani.Irc" and spec[1] == "IRC"
    assert spec[6] == ["ircOpen"] and spec[8] == "ircShown"
    ids = json.loads(re.search(r"var ids = (\{.*?\});", SHELL_APPS, re.S).group(1))
    assert ids["IRC"] == "dev.shani.Irc"
    assert {s[1]: s[0] for s in cli.APPS.values()} == ids
    entry = cli.desktop_entry("irc")
    assert "Exec=shani app irc" in entry and "NoDisplay=true" not in entry
