"""Static guards for the incoming-OBEX transfer fixes in ObexReceive.qml."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVC = ROOT / "shani/Services/ObexReceive.qml"


def src():
    return SVC.read_text()


def test_received_paths_reject_absolute_traversal():
    s = src()
    assert "function safeName(n)" in s
    assert "function inStore(p)" in s
    assert r"\.\.(\/|$)" in s  # no ".." path segment
    assert "if (!root.inStore(m.received)) return" in s
    assert "if (!root.inStore(done.path))" in s
    assert "root.safeName(ask.msg.file)" in s


def test_open_urls_are_percent_encoded():
    s = src()
    assert "function fileUrl(p)" in s
    assert 'p.split("/").map(encodeURIComponent).join("/")' in s
    assert "Qt.openUrlExternally(root.fileUrl(done.path))" in s
    assert '"file://" + done.path' not in s


def test_stale_approvals_cannot_approve_new_transfer():
    s = src()
    assert "property int agentGen: 0" in s
    assert "onRunningChanged: { if (running) root.agentGen++ }" in s
    assert "{ msg: m, gen: root.agentGen }" in s
    assert "gen !== root.agentGen" in s
    assert 'root.answer(ask.msg.id, text.trim() === "accept", ask.gen)' in s


def test_approval_notification_expires():
    s = src()
    assert '"-t", "60000"' in s
    assert "-A" in s and "accept=Accept" in s and "decline=Decline" in s
    assert "onStreamFinished" in s


def test_configured_dir_is_sanitized():
    s = src()
    assert "function cleanDir(d)" in s
    assert r"return d.replace(/^~(?=\/)/, home)" in s
    assert r"/[\x00-\x1f]/.test(d)" in s
    assert r'root.cleanDir(Quickshell.env("SHANI_OBEX_DIR")' in s
    assert 'command: ["python3", root.tool].concat(root.dir ? [root.dir] : [])' in s
