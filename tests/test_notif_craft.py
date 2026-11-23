"""Static checks for notification-design fixes (suppression reasons, urgent badge,
lock-screen DND chip). QML is data here: assert the source carries each affordance.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTIFS = (ROOT / "shani/Services/Notifs.qml").read_text()
CARD = (ROOT / "shani/Modules/Notifications/NotificationCard.qml").read_text()
LOCK = (ROOT / "shani/Modules/Lock/LockScreen.qml").read_text()


def test_suppressed_notices_record_app_and_reason():
    assert "property var suppressed" in NOTIFS, "a rolling suppression list is exposed"
    assert "function _noteSuppressed" in NOTIFS
    assert "slice(-8)" in NOTIFS, "the list stays small"
    for reason in ("silent-app", "focus", "dnd", "quiet"):
        assert '"%s"' % reason in NOTIFS, "reason %s is recorded" % reason
    assert "function suppressionText" in NOTIFS, "reasons have localised text"
    assert "Tr.t(" in NOTIFS.split("function suppressionText")[1].split("}")[0]


def test_critical_badge_has_urgent_text():
    assert 'Tr.t("Urgent")' in CARD, "critical notifications carry a text badge"
    assert "visible: root.critical" in CARD
    assert "Accessible.role: Accessible.StaticText" in CARD


def test_lock_screen_shows_dnd_chip():
    assert "visible: Notifs.dnd" in LOCK, "DND has a lock-screen presence"
    assert 'Tr.t("DND on")' in LOCK
    assert "Notifs.dndUntilText" in LOCK, "the chip shows when DND turns itself off"
