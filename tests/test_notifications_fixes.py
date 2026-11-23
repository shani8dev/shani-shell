"""Static checks for five notification fixes.

QML cannot be loaded in this suite, so each fix gets one focused assertion over
the source it lives in: a popup's countdown pauses while the card is used and
while its surface is hidden, a critical notification is never folded into a
stack, all popups can be cleared at once, and the card's screen-reader name
carries the app and the urgency.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CARD = (ROOT / "shani/Modules/Notifications/NotificationCard.qml").read_text(
    encoding="utf-8"
)
POPUPS = (ROOT / "shani/Modules/Notifications/Popups.qml").read_text(encoding="utf-8")


def _slice(text, start, end):
    return text[text.index(start) : text.index(end, text.index(start))]


def test_countdown_pauses_while_the_card_is_in_use():
    """Menu, reply focus, finger down and swipe all hold the timer, not only hover."""
    block = _slice(
        CARD, "readonly property bool interacting", "readonly property bool critical"
    )
    for term in (
        "more",
        "contextMenu && contextMenu.visible",
        "replyField && replyField.activeFocus",
        "tap.pressed",
        "swipe.active",
    ):
        assert term in block, term
    assert "id: replyField" in CARD, "the reply field is addressable"
    assert "id: tap" in CARD, "the card's press state is addressable"
    assert "paused: running && (hover.hovered || pc.interacting)" in POPUPS
    assert "paused: running && hover.hovered" not in POPUPS, (
        "hover-only pause was the gap"
    )


def test_countdown_stops_while_the_surface_is_hidden():
    """A popup must not expire behind the control centre, lock screen or launcher."""
    assert "running: win.visible && !pc.critical" in POPUPS


def test_critical_notification_is_never_folded_into_a_stack():
    """An incoming call keeps its red edge and Urgent label, ungrouped."""
    groups = _slice(POPUPS, "function groupPopups()", "function clearPopups()")
    assert "NotificationUrgency.Critical" in groups
    assert '"critical:" + n.id' in groups


def test_all_popups_can_be_cleared_at_once():
    """Critical popups never expire, so one press must clear the pile."""
    assert "function clearPopups()" in POPUPS
    clear = _slice(POPUPS, "function clearPopups()", "function toggleGroup")
    assert "for (const n of Notifs.popups.slice())" in clear
    assert "n.dismiss();" in clear
    assert "win.expanded = ({})" in clear, "a cleared stack leaves no stale open state"
    assert "visible: Notifs.popups.length > 1" in POPUPS
    assert 'Tr.t("Clear all")' in POPUPS
    assert "onClicked: win.clearPopups()" in POPUPS


def test_card_names_app_and_urgency_to_a_screen_reader():
    """Two 'New message' cards are distinguishable, and a critical one is spoken."""
    name = _slice(
        CARD, "Accessible.name: root.notification", "Accessible.onPressAction"
    )
    assert 'Tr.t("Urgent") + ", "' in name
    assert 'root.notification.appName + ": "' in name
    assert "root.notification.summary" in name
    # the fallback app name is localised in both surfaces
    assert 'Tr.t("Notification")' in CARD
    assert 'Tr.t("Notification")' in POPUPS
    assert '|| "Notification"' not in CARD
    assert '|| "Notification"' not in POPUPS
