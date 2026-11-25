"""Honest feedback: static hooks and the small rules behind them.

Every surface must say what actually happened. These tests cover the four ways
it goes wrong here: a success in a danger tone, a failed Process whose stderr
nobody reads, a save button that commits nothing, and a busy flag that never
clears. The pure rules are the decision tables the QML encodes; the static
checks make sure the QML still encodes them.
"""

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- pure rules -----------------------------------------------------------

# ok/error/warn/busy are the four states a command can end in. "busy" is
# neutral: never a success, never a failure.
STATUS_TONE = {
    "ok": "ok",
    "saved": "ok",
    "error": "error",
    "failed": "error",
    "warn": "warn",
    "busy": "busy",
    "running": "busy",
}


def tone_for(status):
    return STATUS_TONE.get(status, "info")


def note_ok(note):
    """SysServices writes exactly these two strings on success."""
    return note in ("Saved", "Job removed")


def can_commit(busy, valid, changed=True):
    return not busy and valid and changed


def body_needs_full_contrast(tone):
    return tone in ("error", "danger", "warn")


@pytest.mark.parametrize(
    "status,tone",
    [
        ("ok", "ok"),
        ("saved", "ok"),
        ("error", "error"),
        ("failed", "error"),
        ("warn", "warn"),
        ("busy", "busy"),
        ("running", "busy"),
        ("unknown", "info"),
    ],
)
def test_status_maps_to_one_tone(status, tone):
    assert tone_for(status) == tone
    assert (tone == "ok") == (status in ("ok", "saved"))
    assert (tone == "error") == (status in ("error", "failed"))


@pytest.mark.parametrize(
    "note,ok",
    [
        ("Saved", True),
        ("Job removed", True),
        ("", False),
        ("Could not start unit x", False),
    ],
)
def test_services_note_is_not_painted_danger_on_success(note, ok):
    assert note_ok(note) is ok


@pytest.mark.parametrize(
    "busy,valid,changed,allowed",
    [
        (False, True, True, True),
        (True, True, True, False),  # busy disables save
        (False, False, True, False),
        (False, True, False, False),
        (True, False, False, False),
    ],
)
def test_busy_or_invalid_input_never_commits(busy, valid, changed, allowed):
    assert can_commit(busy, valid, changed) is allowed


@pytest.mark.parametrize(
    "tone,contrast",
    [
        ("ok", False),
        ("info", False),
        ("accent", False),
        ("warn", True),
        ("error", True),
        ("danger", True),
    ],
)
def test_only_problem_tones_need_full_contrast(tone, contrast):
    assert body_needs_full_contrast(tone) is contrast


# ---- static hooks ---------------------------------------------------------

banner = read("shani/Common/InfoBanner.qml")
sessions = read("shani/Services/Sessions.qml")
sshkeys = read("shani/Services/SshKeys.qml")
services_win = read("shani/Modules/Services/ServicesWindow.qml")
settings_account = read("shani/Modules/Settings/SettingsAccount.qml")
files_panel = read("shani/Modules/Files/FilesPanel.qml")


def test_info_banner_paints_every_status_with_its_own_tone():
    assert 'tone: "info"' in banner
    assert 'tone === "ok" ? Theme.accent' in banner
    assert 'tone === "warn" ? Theme.amber' in banner
    assert 'tone === "error" || tone === "danger" ? Theme.danger' in banner
    assert 'tone === "accent" ? Theme.accent' in banner
    assert "Accessible.name: banner.title" in banner


def test_info_banner_never_buries_a_problem_in_a_dim_label():
    # Body text is dim only for neutral/success tones; errors get Theme.text.
    assert (
        'color: banner.tone === "error" || banner.tone === "danger" || banner.tone === "warn" ? Theme.text : Theme.dim'
        in banner
    )


def test_services_window_uses_the_note_flag_not_a_color_guess():
    assert "readonly property bool noteOk:" in services_win
    assert 'Tr.t("Saved")' in services_win
    assert 'Tr.t("Job removed")' in services_win
    assert 'tone: win.noteOk ? "ok" : "error"' in services_win
    assert "InfoBanner {" in services_win
    assert "color: SysServices.note" not in services_win


def test_session_save_failure_is_not_reported_as_success():
    assert 'onSaveFailed: root.error = Tr.t("Could not save the session")' in sessions


def test_session_probe_failure_is_visible_and_stops_the_chain():
    assert "stderr: StdioCollector" in sessions
    assert "onExited: code => {" in sessions
    assert 'root.error = Tr.t("Could not open %1").arg(probe.attempted)' in sessions
    assert "root.pendingPaths = []" in sessions
    assert 'if (root.error !== "" || !root.pendingPaths.length)' in sessions


def test_sshkey_read_failure_is_visible_and_busy_always_clears():
    assert "stderr: StdioCollector {}" in sshkeys
    assert 'root.error = code !== 0 ? Tr.t("Could not read the keys") : ""' in sshkeys
    # both writers clear busy in the stdout handler and on a nonzero exit
    assert sshkeys.count("root.busy = false") >= 4
    assert sshkeys.count("onExited: code =>") == 3


def test_busy_disables_the_commit_buttons():
    assert "enabled: SshKeys.editable && !SshKeys.busy" in settings_account
    assert 'enabled: sshInput.text.trim() !== "" && !SshKeys.busy' in settings_account
    assert "enabled: usbBox.confirmed && !Files.usbBusy" in files_panel
