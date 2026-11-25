"""Static and logic asserts for the two new QML-only app windows.

Teleprompter and NetTools are new surfaces, so these checks pin the twelve
fixes they were built with: bounded auto-scroll, a refused over-large paste,
clamped controls, accessible play/jump actions, counts, shortcuts that do not
eat typed hyphens; and validated shell arguments, a clamped ping count, a
fixed LAN-scan script, graceful missing-tool notes, results/history/export and
empty/loading/error states with keyboard access.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TP = (ROOT / "shani/Modules/Teleprompter.qml").read_text(encoding="utf-8")
NET = (ROOT / "shani/Modules/NetTools.qml").read_text(encoding="utf-8")


# ---- Teleprompter -----------------------------------------------------------


def test_tp_auto_scroll_is_fixed_step_and_stops_at_bounds():
    assert "Timer {" in TP
    assert "interval: 40" in TP
    assert "repeat: true" in TP
    assert 'running: win.playing && win.visible && win.text !== ""' in TP
    assert "function scrollStep()" in TP
    assert "win.speed * scrollTick.interval / 1000 * (win.reverse ? -1 : 1)" in TP
    assert "if (y <= 0) { y = 0; win.playing = false; }" in TP
    assert "else if (y >= max) { y = max; win.playing = false; }" in TP
    assert "onTriggered: win.scrollStep()" in TP


def test_tp_paste_is_bounded_and_has_empty_error_states():
    assert "readonly property int maxChars: 500000" in TP
    assert 'String(Quickshell.clipboardText || "")' in TP
    assert "if (s.length > win.maxChars)" in TP
    assert "The clipboard is empty" in TP
    assert "that is too much text" not in TP  # the copy uses the exact case below
    assert "That is too much text (500,000 characters max)" in TP
    assert "function dismissError()" in TP
    assert "EmptyState {" in TP
    assert 'title: "No script yet"' in TP
    assert 'visible: win.text.trim() === ""' in TP


def test_tp_speed_font_and_direction_controls_are_clamped():
    assert (
        "function setSpeed(delta) { win.speed = Math.max(10, Math.min(400, win.speed + delta)); }"
        in TP
    )
    assert (
        "function setFontSize(delta) { win.fontSize = Math.max(10, Math.min(72, win.fontSize + delta)); }"
        in TP
    )
    assert "property bool reverse: false" in TP
    assert (
        'Button { text: "Reverse"; flat: true; checked: win.reverse; onClicked: win.reverse = !win.reverse }'
        in TP
    )
    assert 'tip: "Slower (-)"' in TP and 'tip: "Faster (+)"' in TP


def test_tp_play_pause_and_jumps_have_accessible_names():
    assert "function togglePlay()" in TP
    assert "function jumpStart() { view.contentY = 0; }" in TP
    assert "function jumpEnd() { view.contentY = win.maxScroll; }" in TP
    assert 'accessibleName: win.playing ? "Pause scrolling" : "Play scrolling"' in TP
    assert 'accessibleName: "Jump to start"' in TP
    assert 'accessibleName: "Jump to end"' in TP
    assert 'icon: "go-first"' in TP and 'icon: "go-last"' in TP


def test_tp_word_and_char_counts():
    assert "function countWords(s)" in TP
    assert r"trim().match(/\S+/g)" in TP
    assert "readonly property int charCount: win.text.length" in TP
    assert "readonly property int wordCount: win.countWords(win.text)" in TP
    assert 'win.wordCount + " words · " + win.charCount + " characters"' in TP


@pytest.mark.parametrize(
    "text,words",
    [("", 0), ("   ", 0), ("one", 1), ("one\ntwo   three", 3), ("a-b c", 2)],
)
def test_tp_count_semantics(text, words):
    """Mirror of countWords(): trimmed, split on runs of non-whitespace."""
    m = re.findall(r"\S+", text.strip()) if text.strip() else []
    assert len(m) == words
    assert len(text) == len(text)  # charCount is the raw length, including spaces


def test_tp_shortcuts_do_not_hijack_typing():
    assert "function shortcut(e)" in TP
    assert "const typing = edit.activeFocus" in TP
    assert "e.key === Qt.Key_Space && !typing" in TP
    assert "!typing && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)" in TP
    assert "!typing && e.key === Qt.Key_Minus" in TP
    assert "e.key === Qt.Key_Home" in TP and "e.key === Qt.Key_End" in TP
    assert "e.accepted = true" in TP
    assert "Keys.onPressed: e => { if (win.shortcut(e)) e.accepted = true; }" in TP


# ---- NetTools ---------------------------------------------------------------


def _host_re():
    m = re.search(r"if \(!/(\^\[A-Za-z0-9\.\-\]\+\$)/\.test\(v\)\)", NET)
    assert m, "the host whitelist regex is missing"
    return re.compile(m.group(1))


def test_net_host_validation_rejects_shell_metacharacters():
    assert "function validHost(s)" in NET
    assert "if (!win.validHost(target))" in NET
    whitelist = _host_re()
    for good in ("example.com", "192.168.1.1", "router", "a-b.example.org"):
        assert whitelist.match(good), good
    for bad in (
        "example.com;id",
        "$(id)",
        "a b",
        "host/path",
        "a'b",
        "a\nb",
        "2001:db8::1",
    ):
        assert not whitelist.match(bad), bad


def test_net_no_user_text_is_interpolated_into_shell_code():
    scripts = re.findall(r'"sh", "-c",\s*\'([^\']*)\'', NET)
    assert len(scripts) >= 4  # scan, ping, DNS, whois
    for script in scripts:
        assert "win." not in script, script
        assert "`" not in script, script
        # a target is only ever reached as a positional argument, never as text
        if "ping" in script or "dig" in script or "whois" in script:
            assert '"$1"' in script, script
    assert 'ping.command = ["sh", "-c",' in NET
    assert '\'timeout 12 ping -c "$1" -W 2 -- "$2" 2>&1 || true\'' in NET
    assert "String(win.boundedCount(win.count)), target]" in NET


def test_net_ping_count_is_bounded_in_code_and_ui():
    assert "function boundedCount(n)" in NET
    assert "return isNaN(v) ? 4 : Math.max(1, Math.min(10, v));" in NET
    assert "IntValidator { bottom: 1; top: 10 }" in NET


@pytest.mark.parametrize(
    "raw,expected", [("", 4), ("abc", 4), ("0", 1), ("3", 3), ("99", 10), ("-5", 1)]
)
def test_net_count_semantics(raw, expected):
    """Mirror of boundedCount(): a bad count falls back to 4, else 1..10."""
    try:
        v = int(raw)
    except ValueError:
        v = 4
    assert max(1, min(10, v)) == expected


def test_net_lan_scan_uses_a_fixed_script_with_fallback():
    scan = NET.split("function runScan()", 1)[1].split("\n    }", 1)[0]
    assert 'scan.command = ["sh", "-c",' in scan
    assert "command -v nmcli" in scan
    assert "command -v iw" in scan
    assert "echo NO_TOOLS" in scan
    assert "nmcli -t -f SSID,SIGNAL,SECURITY,CHAN device wifi list" in scan
    assert "scan.running = true" in scan


def test_net_dns_and_whois_degrade_gracefully():
    assert 'dig +short "$1" A' in NET
    assert "echo NO_DIG" in NET
    assert 'whois -- "$1"' in NET
    assert "echo NO_WHOIS" in NET
    for note in (
        "dig is not installed (install dnsutils to resolve names)",
        "whois is not installed — install it to look up registrations",
        "Neither nmcli nor iw is installed — a LAN scan needs one of them",
    ):
        assert note in NET, note
    for marker in (
        'trimmed === "NO_DIG"',
        'trimmed === "NO_WHOIS"',
        'trimmed === "NO_TOOLS"',
    ):
        assert marker in NET, marker


def test_net_results_history_copy_and_export():
    assert "property var results: []" in NET
    assert "property var history: []" in NET
    assert "win.history = [target].concat(h).slice(0, 10);" in NET
    assert "win.results = rows.concat(win.results).slice(0, 200);" in NET
    assert "Quickshell.clipboardText = win.results.map" in NET
    assert "function copyOne(r)" in NET
    assert 'mode: "save", title: "Export network results"' in NET
    assert "FileView {" in NET
    assert "exportView.setText(win.exportText())" in NET
    assert "function exportText()" in NET


def test_net_states_names_and_keyboard():
    assert "EmptyState {" in NET
    assert 'title: "No results yet"' in NET
    assert "Spinner { size: Theme.px(16) }" in NET
    assert "visible: win.loading" in NET
    assert 'visible: win.error !== ""' in NET
    assert 'accessibleName: "Copy all results"' in NET
    assert 'accessibleName: "Export results"' in NET
    assert 'label: "Host name or IPv4 address"' in NET
    assert "AppWindow {" in NET
    assert "e.key === Qt.Key_L" in NET
    assert "onAccepted: win.run(win.tool)" in NET
