"""Static checks for quick-panel and notification-centre fixes.

The shell's QML is not loadable in this suite, so every fix is asserted against
its source: the panel's slider drag survives a value change, its selection
cannot go out of range, and the centre's filter and Clear actions stay honest
to keyboard and screen-reader users.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QP = (ROOT / "shani/Modules/QuickPanel/QuickPanel.qml").read_text(encoding="utf-8")
SB = (ROOT / "shani/Modules/ControlCenter/SidebarNotifications.qml").read_text(
    encoding="utf-8"
)


def test_quickpanel_repeater_model_is_stable_across_level_changes():
    """rows is rebuilt on every adjust; a new JS array would kill an active drag."""
    assert "model: win.rowIndexes" in QP
    assert "model: win.rows" not in QP  # the volatile array is not the model
    assert "property var rowIndexes: []" in QP
    assert "rowIndexes = idx" in QP  # rebuilt only when the length changes
    # the delegate reads the row live instead of from a frozen modelData object
    assert "required property int modelData" in QP
    assert "readonly property var rowData: win.rows[modelData]" in QP
    assert "row.rowData.adjust(steps)" in QP
    assert "modelData.value" not in QP
    assert "row.modelData" not in QP


def test_quickpanel_selection_clamps_when_rows_shrink():
    """Closing the app behind the panel must not leave a stale, invisible cursor."""
    handler = QP[QP.index("onRowsChanged: {") :]
    handler = handler[: handler.index("\n    }")]
    assert "rows.length > 0" in handler
    assert "sel = Math.min(sel, rows.length - 1)" in handler


def test_notification_filter_dies_with_the_field_that_set_it():
    """The search box auto-hides at five notifications; a stale filter hid rows."""
    field = SB[SB.index("TextField {") :]
    field = field[: field.index("\n    }")]
    assert "visible: Notifs.count + Notifs.earlier.length > 5" in field
    assert 'onVisibleChanged: if (!visible) filter = ""' in field


def test_group_clear_buttons_name_their_app():
    """Every group has a 'Clear' button; AT must hear which stack it empties."""
    assert 'text: Tr.t("Clear")' in SB
    assert 'Accessible.name: Tr.t("Clear all from %1").arg(group.modelData.app)' in SB


def test_earlier_clear_actions_are_named_for_assistive_tech():
    """The bulk clear and the per-row tap-to-clear must be understandable aloud."""
    assert 'Accessible.name: Tr.t("Clear all earlier notifications")' in SB
    assert 'Accessible.description: subtitle + ". " + Tr.t("Click to clear it")' in SB
