"""Static guards for the three lock-screen notification privacy fixes.

Fix 1: "hide content" must suppress the summary on the lock screen too.
Fix 2: the unread count must not be drawn twice.
Fix 3: previews must honour the same silence/rule filtering as pop-ups.
No QML runtime is exercised here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = (ROOT / "shani/Modules/Lock/LockScreen.qml").read_text(encoding="utf-8")


def _preview_repeater():
    pos = LOCK.index("model: Settings.data.lockPreviews")
    return LOCK[pos : LOCK.index("}", pos)]


def test_lock_preview_hides_summary_when_hide_content_on():
    rep = _preview_repeater()
    assert "hideContent: Settings.data.notifHideContent" in rep
    assert rep.count("modelData.summary") == 1
    line = next(l for l in rep.splitlines() if "modelData.summary" in l)
    assert "text: hideContent ? app :" in line  # summary only in the visible branch


def test_unread_count_is_not_rendered_twice():
    assert "Settings.data.lockPreviews && Notifs.count" not in LOCK
    assert '"1 notification"' not in LOCK
    assert (
        LOCK.count("Notifs.count === 1 ?") == 1
    )  # only the kept row's Accessible.name
    assert 'name: "preferences-system-notifications"' in LOCK


def test_lock_previews_apply_silence_and_rule_filtering():
    rep = _preview_repeater()
    assert "root.previews.slice(0, 3)" in rep
    assert "Notifs.list.slice(0, 3)" not in rep
    assert "import Quickshell.Services.Notifications" in LOCK
    fn = LOCK[LOCK.index("function previewable") :]
    fn = fn[: fn.index("\n    }")]
    assert "NotificationUrgency.Critical" in fn
    assert "Notifs._filterNotification" in fn
    assert 'verdict !== "block"' in fn and 'verdict !== "hide"' in fn
    assert "Settings.data.silentApps" in fn
