"""Player (Decibels parity) and Fonts (font-viewer parity), checked statically.

The static checks mirror tests/test_wiring.py: the rich controls are wired
through the same surfaces, the empty states still hold, and the registration
in shell.qml, Ui.qml and bin/shani cannot drift from the IPC names.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- Player: queue, repeat/shuffle, seek drag, volume, gapless, lyrics ----

def test_player_queue_from_folder_with_mpris_tracklist_fallback():
    t = read("shani/Modules/Player/Player.qml")
    # folder queue: a music folder scanned for audio files, capped for perf
    assert "musicFolder" in t
    assert "queue" in t
    assert "openUri" in t and "openQueueItem" in t
    assert "FolderDialog" in t
    assert "head -200" in t or "head -" in t
    # the MPRIS tracklist is the source where available; Quickshell does not
    # expose it yet, so the folder queue is the documented fallback
    assert "tracklist" in t.lower()
    assert "tracklistItems" in t or "tracklist" in t
    # no player running: the empty state holds and the queue still works
    assert "EmptyState" in t and "No player" in t
    assert "xdg-open" in t  # fallback when no player is following


def test_player_repeat_shuffle_volume_seek_gapless_lyrics():
    t = read("shani/Modules/Player/Player.qml")
    # repeat cycling off -> playlist -> track, shuffle toggle
    assert "loopState" in t and "MprisLoopState" in t
    assert "cycleRepeat" in t and "toggleShuffle" in t
    assert "shuffle" in t and "shuffleSupported" in t
    assert "loopSupported" in t
    # seekbar with time display + drag
    assert "fmt(" in t and "fmtRemaining" in t
    assert "dragging" in t
    assert "onPressed" in t and "onPositionChanged" in t and "onReleased" in t
    assert "canSeek" in t
    # per-player volume (the followed player's own level, not the system)
    assert "volume" in t and "volumeSupported" in t
    assert "SliderRow" in t
    # gapless info: MPRIS does not advertise it, so it is said plainly
    assert "Gapless" in t or "gapless" in t.lower()
    # lyrics via the existing Lyrics service (LRCLIB, Settings > Sound)
    assert "Lyrics.wanted" in t
    assert "Lyrics.lineAt" in t
    assert "Lyrics.lines" in t
    # source picker still follows Media.players (Media.qml itself is unchanged)
    assert "Media.players" in t and "preferredPlayer" in t


def test_media_service_is_unchanged():
    t = read("shani/Services/Media.qml")
    assert "readonly property var current" in t
    assert "function cycle()" in t
    # the small handle — a queue/audition in here would be a service rewrite
    assert len(t.split("\n")) < 40
    assert "tracklist" not in t and "shuffle" not in t


# ---- Fonts: family/style, preview, size, copy, install ----

def test_fonts_family_style_preview_size_copy():
    t = read("shani/Modules/Fonts/FontsPanel.qml")
    # family + style from fc-list, sorted, capped
    assert "fc-list" in t and "family" in t and "style" in t
    assert "slice(0, 400)" in t
    # live preview text entry
    assert "previewField" in t and "preview" in t
    assert "TextField" in t
    # size slider: 10..48 pt, bound into the delegate (was fixed 15)
    assert "previewSize" in t
    assert "10" in t and "48" in t
    assert "font.pixelSize: win.previewSize" in t
    # copying the family name (click, key, and the shell's clipboard)
    assert "clipboardText" in t
    assert "copyFamily" in t


def test_fonts_install_from_file_refreshes_cache_without_freezing():
    t = read("shani/Modules/Fonts/FontsPanel.qml")
    assert "installFont" in t and "Install a font" in t
    assert "FileDialog" in t
    # the file lands in the per-user font dir and the cache is rebuilt,
    # after a Process — never on the UI thread
    assert "fc-cache" in t
    assert ".local/share/fonts" in t or "_fonts" in t
    assert "installFontProc" in t and "Process" in t
    assert "onExited" in t
    assert "refresh()" in t


# ---- registration: shell.qml, Ui.qml, bin/shani -------------------------

def test_player_and_fonts_are_registered():
    shell = read("shani/shell.qml")
    assert "LazyLoader { active: Ui.player; Player {} }" in shell
    assert "LazyLoader { active: Ui.fonts; FontsPanel {} }" in shell
    assert "function togglePlayer(" in shell
    assert "function toggleFonts(" in shell
    ui = read("shani/Common/Ui.qml")
    assert "property bool player" in ui
    assert "property bool fonts" in ui
    assert "player = false" in ui and "fonts = false" in ui
    # the rich IPC the CLI drives, and the state it reads back
    for fn in ["function playerSeek(", "function playerVolume(", "function playerShuffle(",
               "function playerRepeat(", "function playerOpen(", "function fontInstall(",
               "function fontCopy("]:
        assert fn in shell, fn
    for key in ["playerVolume", "playerShuffle", "playerLoop", "playerPosition",
                "playerSeekable"]:
        assert key in shell, key
    assert "player: Ui.player" in shell and "fonts: Ui.fonts" in shell


def test_cli_reaches_the_rich_controls():
    cli = read("bin/shani")
    # media: the seek/volume/repeat/shuffle/queue verbs
    assert '("seek", ["SECONDS"]' in cli
    assert '("volume", ["LEVEL"]' in cli
    assert '("shuffle", []' in cli
    assert '("repeat", []' in cli
    assert '("open", ["PATH"]' in cli
    # fonts: its own group, with install + copy
    assert '"fonts"' in cli
    assert '("install", ["PATH"]' in cli
    assert '("copy", ["FAMILY"]' in cli
    assert '("fontInstall"' in cli or '"fontInstall"' in cli
    assert '"fontCopy"' in cli
    for (group, cmd), ipc in [
        (("media", "seek"), "playerSeek"), (("media", "volume"), "playerVolume"),
        (("media", "shuffle"), "playerShuffle"), (("media", "repeat"), "playerRepeat"),
        (("media", "open"), "playerOpen"), (("fonts", "install"), "fontInstall"),
        (("fonts", "copy"), "fontCopy"), (("fonts", "open"), "toggleFonts"),
    ]:
        # the tuple appears in the table as ("group", "cmd"): "ipc"
        assert f'("{group}", "{cmd}")' in cli and ipc in cli, (group, cmd, ipc)
