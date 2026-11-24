"""Static wiring and pure logic for the OSK's paste, repeat and one-handed modes.

There is no QML runtime in pytest here, so the source assertions pin the wiring
(which key calls which service function, which timers exist) and the pure tests
mirror the small arithmetic in Osk.qml / Keyboard.qml: repeat timing bounds,
clipboard-as-argv safety and the one-handed board geometry. No network, no
shell, no clipboard access.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OSK = (ROOT / "shani/Services/Osk.qml").read_text(encoding="utf-8")
KEYBOARD = (ROOT / "shani/Modules/Osk/Keyboard.qml").read_text(encoding="utf-8")
LAUNCHER = (ROOT / "shani/Modules/Launcher/Launcher.qml").read_text(encoding="utf-8")

DELAY = 400
INTERVAL = 80
MARGIN = 8
FRACTION = 0.82
SIDES = ["center", "left", "right"]


def block(src: str, start: str, end: str) -> str:
    i = src.index(start)
    return src[i : src.index(end, i)]


PASTE = block(OSK, "function paste()", "// repeat is input")
REPEAT = block(OSK, "readonly property int repeatDelay", "// handwriting:")
HAND = block(OSK, "function cycleHand()", "// ---- paste")


# ---- pure logic (mirrors Osk.qml / Keyboard.qml) ------------------------------


def repeat_schedule(
    delay: int = DELAY, interval: int = INTERVAL, count: int = 6
) -> list[int]:
    """Osk.press() fires at delay, then every interval while the key is held."""
    return [delay + i * interval for i in range(count)]


def paste_argv(text: str) -> list[str]:
    """The exact argv Osk.paste() hands to execDetached: one element, no shell."""
    return ["wtype", "--", text]


def normalize_hand(value: str) -> str:
    return value if value in SIDES else "center"


def cycle_hand(current: str) -> str:
    return SIDES[(SIDES.index(normalize_hand(current)) + 1) % len(SIDES)]


def qml_round(value: float) -> int:
    return math.floor(value + 0.5)  # QML Math.round, not Python's banker's round


def board_geometry(screen_w: int, hand: str) -> tuple[int, int]:
    """(x, width) of the board for a hand, mirroring Keyboard.qml's bindings."""
    hand = normalize_hand(hand)
    avail = screen_w - 2 * MARGIN
    width = avail if hand == "center" else qml_round(avail * FRACTION)
    x = screen_w - MARGIN - width if hand == "right" else MARGIN
    return x, width


# ---- key repeat ---------------------------------------------------------------


def test_repeat_timing_is_bounded_and_increasing():
    assert 200 <= DELAY <= 800, "initial delay must be a short hold, not a click"
    assert 30 <= INTERVAL <= 200, "repeat rate must be fast but not a flood"
    times = repeat_schedule()
    assert times[0] == DELAY
    assert all(b - a == INTERVAL for a, b in zip(times, times[1:]))
    assert times == sorted(times) and len(times) == len(set(times))


def test_repeat_timers_mirror_the_pure_constants():
    assert f"repeatDelay: {DELAY}" in OSK
    assert f"repeatInterval: {INTERVAL}" in OSK
    assert "id: repeatDelayTimer" in REPEAT and "id: repeatTick" in REPEAT
    assert "repeat: true" in REPEAT
    assert "repeatTick.restart()" in REPEAT
    assert "root.press(root.repeatKey)" in REPEAT
    # no timer may be running before a key is held (idle must be silent)
    assert "running: true" not in REPEAT


def test_repeat_stops_on_release_hide_and_remote():
    assert "function stopRepeat()" in REPEAT
    stop = block(REPEAT, "function stopRepeat()", "Timer {")
    assert "repeatDelayTimer.stop()" in stop and "repeatTick.stop()" in stop
    area = block(KEYBOARD, "MouseArea {", "pressAndHoldInterval")
    assert "onReleased: Osk.stopRepeat()" in area
    assert "onCanceled: Osk.stopRepeat()" in area
    assert "Osk.startRepeat(key.repeatKey)" in area
    assert "root.stopRepeat()" in OSK[OSK.index("onShownChanged:") :]


def test_only_plain_keys_repeat():
    binding = block(KEYBOARD, "repeatKey: modelData.n", "Layout.fillWidth")
    assert 'modelData.n === "⌫" ? "BackSpace"' in binding
    assert 'modelData.n !== "⇧"' in binding
    assert "modelData.n.length === 1" in binding
    assert "property string repeatKey:" in KEYBOARD  # declared on the Key component


# ---- paste --------------------------------------------------------------------


def test_clipboard_is_one_argv_element_not_shell_text():
    hostile = 'a"; rm -rf ~/$(whoami) `id`\nb'
    assert paste_argv(hostile) == ["wtype", "--", hostile]
    assert " ".join(paste_argv(hostile)) != hostile  # never flattened into a command
    assert '"sh", "-c"' not in PASTE
    assert "'" not in PASTE  # no shell quoting anywhere in the paste path


def test_paste_uses_the_existing_wtype_path_and_guards():
    assert "Quickshell.clipboardText" in PASTE
    assert 'String(Quickshell.clipboardText || "")' in PASTE
    assert 'text === "" || Lock.locked' in PASTE
    assert 'Quickshell.execDetached(["wtype", "--", text])' in PASTE
    assert "draft += text" in PASTE  # remote mode keeps its own draft
    assert "typed = (typed + text).slice(-16)" in PASTE


def test_paste_key_is_wired_and_named():
    row = block(KEYBOARD, "// paste types the clipboard", "// one-handed:")
    assert "icon: 'edit-paste'" in row.replace('"', "'")  # icon name, any quoting
    assert 'accessibleName: Tr.t("Paste")' in row
    assert "onTapped: Osk.paste()" in row


# ---- one-handed mode ----------------------------------------------------------


def test_hand_cycles_through_three_states_and_normalizes_unknown():
    assert cycle_hand("center") == "left"
    assert cycle_hand("left") == "right"
    assert cycle_hand("right") == "center"
    assert cycle_hand("garbage") == "left"  # an unknown value is centered first
    assert normalize_hand("garbage") == "center"
    assert f"const sides = {SIDES!r}".replace("'", '"') in OSK


def test_one_handed_geometry_is_mirrored_and_bounded():
    for screen in (1920, 1280, 800, 400):
        cx, cw = board_geometry(screen, "center")
        assert (cx, cw) == (MARGIN, screen - 2 * MARGIN)
        lx, lw = board_geometry(screen, "left")
        rx, rw = board_geometry(screen, "right")
        assert lx == MARGIN and rx == screen - MARGIN - rw
        assert lw == rw and 0 < lw < cw
        assert lx + lw <= screen and rx >= 0
    assert "0.82" in KEYBOARD
    assert "Theme.px(8)" in KEYBOARD
    assert 'x: Osk.hand === "right"' in KEYBOARD
    assert 'readonly property bool oneHanded: Osk.hand !== "center"' in KEYBOARD


def test_hand_is_persisted_in_osk_json_not_a_settings_key():
    adapter = block(OSK, "JsonAdapter {", "}\n    }")
    assert "property string hand:" in adapter
    assert "prefs.hand = root.hand" in OSK
    assert "settingsMerge" not in OSK
    for bad in (
        "Settings.data.oskHand",
        "Settings.data.oskSize",
        "Settings.data.oskOpacity",
    ):
        assert bad not in OSK


def test_hand_toggle_is_visible_named_and_in_the_options_menu():
    key = block(KEYBOARD, "// one-handed:", "Key { Layout.fillWidth")
    assert "onTapped: Osk.cycleHand()" in key
    assert 'Tr.t("Keyboard") + ": "' in key
    assert 'Tr.t("Left")' in key and 'Tr.t("Right")' in key and 'Tr.t("Center")' in key
    menu = block(KEYBOARD, 'icon: "input-keyboard"', "}\n            }\n        }")
    assert "onClicked: Osk.cycleHand()" in menu
    assert "Accessible.role: Accessible.Button" in KEYBOARD
    assert "Accessible.name: key.accessibleName" in KEYBOARD
    assert "Accessible.onPressAction: key.tapped()" in KEYBOARD
    assert 'accessibleName: Tr.t("Paste")' in KEYBOARD


# ---- honest skip --------------------------------------------------------------


def test_emoji_page_is_left_to_the_launcher_picker():
    # The launcher already ships the full Unicode emoji/character picker backed
    # by the system's emoji-test.txt; a second, smaller fixed list on the OSK
    # would duplicate it and wtype cannot reliably type multi-codepoint emoji.
    assert re.search(r'page: "[^"]*"', OSK)
    assert "emoji" not in re.findall(
        r'property string page: "([^"]+)"', OSK + "\n" + KEYBOARD
    )
    assert "emoji-test.txt" in LAUNCHER
    assert "Clipboard.typeText" in LAUNCHER
