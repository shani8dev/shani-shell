"""Static assertions for the greeter/setup craft fixes (power, back, Wi-Fi, locale)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_setup_has_two_tap_power_controls():
    s = read("setup/shell.qml")
    # sleep is one tap; restart/power off are the greeter's two-tap pattern
    assert '"systemctl", "suspend"' in s
    assert '"system-reboot", name: "Restart", cmd: "reboot"' in s
    assert '"system-shutdown", name: "Power off", cmd: "poweroff"' in s
    assert "property bool armed: false" in s
    assert "press again to confirm" in s
    assert "powerKey.armed ? Quickshell.execDetached" in s


def test_chronoa_page_has_back_button():
    s = read("setup/shell.qml")
    start = s.index("Continue control inside the chronoa page")
    block = s[start : start + 700]
    assert 'text: root.t("back")' in block
    assert "onClicked: root.back()" in block


def test_wifi_failure_is_shown_beside_the_row():
    s = read("setup/shell.qml")
    assert 'property string failed: ""' in s
    assert "function onConnectionFailed(reason)" in s
    assert "netPage.failed = wRow.modelData.name" in s
    assert 'Tr.t("Could not connect — try again")' in s


def test_greeter_clock_uses_system_locale():
    g = read("greeter/shell.qml")
    assert "property string systemLocale:" in g
    assert "Qt.locale(root.systemLocale" in g
    assert "Qt.formatTime(clock.date, root.clockLocale, Locale.ShortFormat)" in g
    assert "Qt.formatDate(clock.date, root.clockLocale, Locale.LongFormat)" in g
    assert '"HH:mm"' not in g
    assert '"dddd, d MMMM"' not in g


def test_setup_validation_error_is_loud():
    s = read("setup/shell.qml")
    # a disabled Start must say why, in red, not in dim footnote text
    assert (
        'root.status.startsWith("error") || root.accountProblem !== "" ? Theme.danger : Theme.dim'
        in s
    )
    start = s.index('text: root.t("adminNote")')
    block = s[start : start + 240]
    assert "color: Theme.dim" in block
    assert "font.pixelSize: 12 * Theme.fontScale" in block


def test_greeter_error_offers_a_next_step():
    g = read("greeter/shell.qml")
    assert 'text: "Check what you typed and try again."' in g
