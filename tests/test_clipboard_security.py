"""Static guards for clipboard security fixes (each maps to one fix).

These assert the source stays in the fixed shape; runtime behaviour is already
covered by test_clipboard_crypto.py.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLIPBOARD = (ROOT / "shani/Services/Clipboard.qml").read_text()
FEEDS = (ROOT / "shani/Modules/Feeds/FeedsWindow.qml").read_text()


def test_toggling_encryption_restarts_watcher_through_wrapper():
    # fix 1: session starts `wl-paste --watch cliphist store` directly, so the
    # enable flow itself must relaunch the watcher via clipboard-watch.sh
    assert "function restartWatcher()" in CLIPBOARD
    assert "clipboard-watch.sh" in CLIPBOARD
    body = CLIPBOARD[CLIPBOARD.index("function setEncrypted") :]
    body = body[: body.index("}")]
    assert "restartWatcher()" in body
    # the un-editable session line is documented for whoever can change it
    assert "dev/niri/session.kdl:85" in CLIPBOARD
    assert "spawn-at-startup" in CLIPBOARD


def test_thumbnail_decode_keeps_command_out_of_loop_args():
    # fix 2: "$@" must be only the cliphist/python command; the id:path entries
    # come from a separate argument, else the loop decodes its own prefix tokens
    assert 'for e in "$@"' not in CLIPBOARD
    assert "shift 2" in CLIPBOARD
    assert 'join("\\n")' in CLIPBOARD
    thumbs = CLIPBOARD[CLIPBOARD.index("thumbs.command") :]
    thumbs = thumbs[: thumbs.index("thumbs.running")]
    assert 'printf "%s\\\\n" "$list"' in thumbs
    assert '"$@" decode "$id"' in thumbs


def test_feed_title_ignores_rich_text():
    # fix 3: an <img> in a feed title must not make Qt auto-detect RichText
    pos = FEEDS.index("text: Feeds.articleTitle")
    block = FEEDS[pos : FEEDS.index("}", pos)]
    assert "textFormat: Text.PlainText" in block
