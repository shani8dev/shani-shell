"""Static guards for the pass-21 IME / OSK fixes.

One test per fix: fresh-install profile watching, stale state on fcitx5 death,
and masking the remote OSK draft for secret fields. Source-only on purpose —
there is no QML runtime here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IME = (ROOT / "shani/Services/Ime.qml").read_text(encoding="utf-8")
KEYBOARD = (ROOT / "shani/Modules/Osk/Keyboard.qml").read_text(encoding="utf-8")


def _line(src, anchor):
    for line in src.splitlines():
        if anchor in line:
            return line
    raise AssertionError(anchor)


def test_fresh_install_profile_watch_covers_system_path():
    # The shipped two-method profile lives in /etc/xdg on a fresh install;
    # watching only ~/.config left methods=0 and the 2 s poll never started.
    assert 'Quickshell.env("XDG_CONFIG_DIRS")' in IME
    assert '"/etc/xdg"' in IME
    assert IME.count("fcitx5/profile") >= 2
    # Independent counts so one view's load-failure cannot zero the other's
    # result (both views load asynchronously, order not guaranteed).
    assert "_userMethods" in IME and "_systemMethods" in IME
    assert "root.updateMethods()" in IME


def test_fcitx5_death_clears_ime_state():
    # stdout only updates on success; a non-zero exit with no output used to
    # leave the old method and running:true forever.
    query = IME[IME.index("id: query") : IME.index("property int methods")]
    assert "onExited:" in query
    assert "queryOut.text.trim()" in query
    assert 'root.current = ""' in query
    assert "root.running = false" in query
    # stop() must drop the label immediately, not wait for a recheck.
    stop = _line(IME, "function stop()")
    assert 'root.current = ""' in stop
    assert "root.running = false" in stop


def test_remote_draft_is_masked_for_secret_targets():
    # The draft is our own rendering, so it bypasses the field's echoMode.
    assert "shownDraft" in KEYBOARD
    assert "echoMode !== TextInput.Normal" in KEYBOARD
    assert '"•".repeat(Osk.draft.length)' in KEYBOARD
    rendered = _line(KEYBOARD, "win.shownDraft")
    assert "win.shownDraft" in rendered
    assert "Osk.draft +" not in rendered
    # Documented limit: shell.qml still dumps the raw text into state.
    assert "state dumps" in KEYBOARD
