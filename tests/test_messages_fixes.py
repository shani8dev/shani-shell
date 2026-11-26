"""Three pass-20 Messages fixes: read state, new conversations, drafts.

The bridge test uses the repo's fake-phone style (no phone, no devices);
the two QML tests are static so a file no runtime opens is still checked.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import link  # noqa: E402


class Message:
    def __init__(self, thread, address, read):
        self.thread = thread
        self.addresses = (address,)
        self.body = "hello"
        self.date = 1_700_000_000_000
        self.incoming = True
        self.read = read


class Device:
    id = "aa"
    name = "Pixel"
    paired = True
    reachable = True


class FakePhone:
    def __init__(self, rows):
        self.rows = rows

    def devices(self):
        return [Device()]

    def battery(self, device):
        return None

    def conversations(self, device):
        return list(self.rows)


def _unread():
    return [m["unread"] for m in link.cmd_messages()]


def test_read_marks_a_thread_read_and_persists_it(monkeypatch, tmp_path):
    """Fix 1: link.py read <thread> clears the dot, and only that thread's."""
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    rows = [Message("t1", "+4471", False), Message("t2", "+4472", False)]
    monkeypatch.setattr(link, "phone", FakePhone(rows))

    assert _unread() == [True, True]
    assert link.cmd_read("t1") == {"ok": True, "error": ""}
    assert _unread() == [False, True]

    # a fresh bridge invocation reads the same state back from disk
    assert '"t1"' in (tmp_path / "shani-shell" / "link-read.json").read_text()
    assert link._read_state() == {"t1"}


def test_no_thread_match_opens_a_new_composer():
    """Fix 2: a number without a thread opens the existing composer, not nothing."""
    win = (ROOT / "shani/Modules/Messages/MessagesWindow.qml").read_text()
    svc = (ROOT / "shani/Services/Link.qml").read_text()
    assert "else Link.startConversation(want);" in win
    assert "function startConversation(number)" in svc
    body = svc[
        svc.index("function startConversation") : svc.index("function clearDraft")
    ]
    assert "showThread(" in body  # reuses the composer state, no new window


def test_drafts_survive_switches_and_clear_only_on_send():
    """Fix 3: per-thread draft map saved on switch, restored, cleared on send."""
    svc = (ROOT / "shani/Services/Link.qml").read_text()
    win = (ROOT / "shani/Modules/Messages/MessagesWindow.qml").read_text()
    assert "property var drafts: ({})" in svc
    assert "root.drafts[root.openThread] = root.draft" in svc
    assert 'root.draft = root.drafts[id] || ""' in svc
    assert 'run("read", [id])' in svc
    assert "delete root.drafts[root.openThread]" in svc
    assert "text: Link.draft" in win
    assert "Link.clearDraft();" in win
