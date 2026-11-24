"""Upstream-parity gaps closed by wiring features the services already had."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text()


def test_photos_filter_chips_are_live():
    s = read("shani/Modules/Photos/PhotosWindow.qml")
    old = 'readonly property var shown: photos.filter(p => activeAlbum === ""'
    assert old not in s  # the album-only filter is gone
    assert 'filter === "camera"' in s
    assert 'filter === "all"' in s
    assert "/Screenshot/i.test(p.path)" in s


def test_terminal_exposes_test_import_and_search():
    s = read("shani/Modules/Terminal/TerminalAppWindow.qml")
    assert "TerminalApp.testConnection(modelData" in s
    assert "TerminalApp.importKey(paths[0]" in s
    assert "hostQuery" in s and "win.hostQuery.trim().toLowerCase()" in s


def test_processes_can_find_a_process():
    s = read("shani/Modules/Processes/Processes.qml")
    assert "procQuery" in s
    assert "win.shownList" in s and "model: win.shownList" in s
    assert 'String(x.p.name || "")' in s


def test_software_searches_as_you_type():
    s = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "id: liveSearch" in s
    assert "onTextChanged: liveSearch.restart()" in s
    assert "q.text.trim().length >= 3" in s


def test_mail_reply_forward_and_date():
    w = read("shani/Modules/Mail/MailWindow.qml")
    svc = read("shani/Services/Mail.qml")
    assert "function startCompose(" in w
    assert 'Tr.t("Reply")' in w and 'Tr.t("Forward")' in w
    assert "function replySubject()" in w
    assert "property string date" in svc
    assert "Mail.when(modelData.date)" in w


def test_feeds_and_photos_show_the_data_they_already_have():
    f = read("shani/Modules/Feeds/FeedsWindow.qml")
    assert "modelData.summary" in f
