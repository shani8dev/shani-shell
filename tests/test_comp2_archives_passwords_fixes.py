"""Competitive research (File Roller / Ark / macOS Archive Utility,
GNOME Passwords and Keys / KeePassXC / 1Password / Aegis) — five QML fixes.

Static checks: this container has no QML runtime or live keyring, so each fix is
asserted against the source it lives in. One test per behaviour.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


ARCHIVES = "shani/Modules/Archives/ArchivesWindow.qml"
AUTH = "shani/Modules/Authenticator/AuthenticatorWindow.qml"
PASSWORDS = "shani/Modules/Passwords/PasswordsWindow.qml"


def test_archives_cancel_stops_a_running_job():
    """File Roller and Ark expose a Cancel for a long extract/compress. The
    Archive service already had cancel(); the window gave no way to call it
    short of closing. A button appears whenever any job is in flight."""
    s = read(ARCHIVES)
    assert (
        "readonly property bool busy: Archive.reading || Archive.extracting || Archive.creating || Archive.appending"
        in s
    )
    assert "visible: win.busy" in s
    assert "onClicked: Archive.cancel()" in s


def test_archives_entry_list_can_be_filtered_by_name():
    """Ark's 'Find' narrows the entry list. A short filename filter over the
    listed paths replaces the model, with a count and a 'nothing matches'
    empty state when the filter excludes everything."""
    s = read(ARCHIVES)
    assert 'property string entryFilter: ""' in s
    assert (
        "return Archive.entries.filter(e => e.path.toLowerCase().indexOf(q) >= 0);" in s
    )
    assert "model: win.visibleEntries" in s
    assert 'placeholderText: Tr.t("Find a file in the archive")' in s
    assert "win.visibleEntries.length === 0" in s
    assert ': Tr.t("Nothing matches")' in s


def test_authenticator_copies_otp_through_stdin_and_clears_it():
    """Aegis/1Password wipe a copied OTP. Six digits slip past cliphist's
    secret filter, so the code now goes through wl-copy's stdin (never argv)
    and a 45 s timer clears it — for both normal and security-key codes."""
    s = read(AUTH)
    assert 'command: ["wl-copy"]' in s
    assert 'onStarted: { write(payload); payload = ""; stdinEnabled = false; }' in s
    assert (
        "Timer { id: clearTimer; interval: 45000;" in s
        and 'Quickshell.execDetached(["wl-copy", "--clear"])' in s
    )
    assert "win.copyClip(a.code);" in s
    assert "win.copyClip(r.code);" in s
    assert "Quickshell.clipboardText = a.code" not in s
    assert "Quickshell.clipboardText = r.code" not in s


def test_passwords_can_copy_a_username_without_revealing_the_secret():
    """KeePassXC/1Password copy the username as a separate action. It is a
    plain attribute, so no bridge reveal is needed; the same wl-copy pipe and
    45 s wipe as the password action are reused."""
    s = read(PASSWORDS)
    assert 'return a.username || a.user || a.account || "";' in s
    assert "function copyUser(i) {" in s
    assert 'tip: Tr.t("Copy the username for %1", prow.modelData.label)' in s
    assert "onClicked: win.copyUser(prow.modelData)" in s
    assert 'Tr.t("%1 username copied - the clipboard forgets it in 45 s", i.label)' in s


def test_passwords_search_has_a_clear_button_and_match_count():
    """GNOME Passwords and KeePassXC let you clear a search in one click and
    see how many entries remain. The query already filtered the list; the
    clear control and the 'N / total' readout were missing."""
    s = read(PASSWORDS)
    assert 'tip: Tr.t("Clear search")' in s
    assert 'onClicked: { search.text = ""; search.input.forceActiveFocus(); }' in s
    assert 'text: win.visibleItems.length + " / " + win.items.length' in s
