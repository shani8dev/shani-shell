"""Static regressions for the Player / LockScreen fixes.

QML does not run under pytest, so each test pins the small source change that
keeps a typed property defined, a dead control disabled, and a privacy gate
from printing the literal "undefined".
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_lock_art_source_never_assigns_undefined_to_url():
    """Image.source is a url; a player with no art must get "", not undefined."""
    lock = source("shani/Modules/Lock/LockScreen.qml")
    assert (
        'source: nowPlaying.player ? (nowPlaying.player.trackArtUrl || "") : ""' in lock
    )
    assert 'source: nowPlaying.player ? nowPlaying.player.trackArtUrl : ""' not in lock


def test_lock_media_card_needs_a_title_or_identity():
    """'undefined' !== "" is true, so the old guard drew an empty media card."""
    lock = source("shani/Modules/Lock/LockScreen.qml")
    assert (
        "visible: Settings.data.lockScreenMedia && !!(player && (player.trackTitle || player.identity))"
        in lock
    )
    assert 'player !== null && player.trackTitle !== ""' not in lock
    assert (
        'nowPlaying.player.trackTitle || nowPlaying.player.identity || Tr.t("Unknown track")'
        in lock
    )
    assert (
        'text: nowPlaying.player ? (nowPlaying.player.trackArtist || "") : ""' in lock
    )


def test_lock_transport_buttons_follow_player_capabilities():
    """The Player panel disables these; the lock card must not offer dead keys."""
    lock = source("shani/Modules/Lock/LockScreen.qml")
    assert "enabled: nowPlaying.player && nowPlaying.player.canGoPrevious" in lock
    assert "enabled: nowPlaying.player && nowPlaying.player.canGoNext" in lock
    assert "enabled: nowPlaying.player && nowPlaying.player.canControl" in lock


def test_lock_preview_does_not_print_undefined_summary():
    """A notification with no summary must leave the title at the app name."""
    lock = source("shani/Modules/Lock/LockScreen.qml")
    assert '(modelData.summary || "")' in lock
    assert "+ modelData.summary" not in lock


def test_player_can_unpin_the_preferred_player():
    """Choosing a source sets preferredPlayer; without Auto there is no way back."""
    player = source("shani/Modules/Player/Player.qml")
    assert 'onClicked: Settings.data.preferredPlayer = ""' in player
    assert 'title: Tr.t("Auto")' in player
    assert "selected: !Settings.data.preferredPlayer" in player
