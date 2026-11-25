"""Static checks for the notification card's four cheap gesture fixes.

The shell's QML cannot be loaded in this suite, so each fix gets one focused
assertion over the card's source: the dismiss paths agree, a swipe has a visual
cue, hover-only buttons are readable on touch, and a long press / right click
opens a menu without fighting the swipe handler.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CARD = ROOT / "shani/Modules/Notifications/NotificationCard.qml"
TEXT = CARD.read_text(encoding="utf-8")


def test_every_dismiss_path_uses_one_helper():
    """X, swipe and Delete all dismiss *and* close; Delete used to only close."""
    helper = TEXT[TEXT.index("function dismissCard()") :]
    helper = helper[: helper.index("\n    }")]
    assert "root.notification.dismiss();" in helper
    assert "root.done();" in helper
    # the three callers: the X button, the swipe release, the Delete key
    assert TEXT.count("root.dismissCard()") >= 3
    assert "onClicked: root.dismissCard()" in TEXT
    assert "Keys.onDeletePressed: root.dismissCard()" in TEXT
    assert "Keys.onDeletePressed: root.done()" not in TEXT
    # no path still does the old two-line dismiss inline
    assert "root.notification.dismiss();\n            root.done();" not in TEXT


def test_swipe_reveals_a_coloured_strip():
    """The card's backing strip becomes visible in proportion to the swipe."""
    cue = TEXT[TEXT.index("// a swipe reveals this backing strip") :]
    cue = cue[: cue.index("\n    }")]
    assert "color: Theme.red" in cue
    assert "opacity: Math.abs(slide.x) / root.width" in cue
    assert "id: swipe" in TEXT  # the DragHandler whose translation drives it


def test_touch_profile_forces_header_buttons_on():
    """A finger has no hover: use the FormFactor pattern, not a hover-only fade."""
    assert (
        'readonly property bool touchFirst: ["tablet", "phone", "board"].indexOf(FormFactor.focused.profile) >= 0'
        in TEXT
    )
    assert TEXT.count("opacity: root.touchFirst || hover.hovered") == 2
    assert "opacity: root.touchFirst || hover.hovered || root.more ? 1 : 0.55" in TEXT
    assert (
        "opacity: root.touchFirst || hover.hovered || root.critical ? 1 : 0.55" in TEXT
    )


def test_long_press_and_right_click_open_a_menu_without_fighting_the_drag():
    """Hold rejects the drag grab and swallows the click; three menu actions."""
    assert 'import "../../Common/Gestures.js" as Hold' in TEXT
    assert "acceptedButtons: Qt.LeftButton | Qt.RightButton" in TEXT
    assert "property var held: Hold.state()" in TEXT
    assert "onPressed: Hold.press(held)" in TEXT
    assert "onPressAndHold: {" in TEXT and "Hold.hold(held)" in TEXT
    assert "Hold.swallowed(held)" in TEXT
    assert "swipe.enabled = false" in TEXT  # reject the drag grab on a hold
    assert "swipe.enabled = true" in TEXT  # restore it on release
    assert "e.button === Qt.RightButton" in TEXT
    assert "root.openMenu(" in TEXT

    # a real menu, reusing the codebase's Common components (as DesktopIcons does)
    menu = TEXT[TEXT.index("// long press / right click") :]
    assert "visible: false" in menu
    assert "Glass {" in menu and "ListRow {" in menu and "Repeater {" in menu
    for label in ("Copy text", "Mute app", "Open app settings"):
        assert f'Tr.t("{label}")' in menu, label
    assert "Quickshell.clipboardText" in menu
    assert "Notifs.setSilenced" in menu
    assert 'Ui.openSettings("notifications"' in menu
