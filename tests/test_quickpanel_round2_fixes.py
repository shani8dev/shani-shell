"""Static checks for QuickPanel round-2 fixes.

QML is not loadable in this suite, so fixes are asserted against source:
accessible dialog identity, button state/press feedback for AT, selected-row
exposure, and a null-safe row lookup during delegate rebuilds.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QP = (ROOT / "shani/Modules/QuickPanel/QuickPanel.qml").read_text(encoding="utf-8")


def _delegate_block() -> str:
    start = QP.index("delegate: Rectangle {")
    # the delegate ends at the Repeater's closing braces; slice to next row-level
    # marker after the MouseArea to keep the block local.
    tail = QP[start:]
    return tail[: tail.index("\n                }\n            }\n")]


def test_quickpanel_card_is_named_dialog_for_at():
    """Overlay panels need an accessible name so screen readers identify them."""
    card = QP[QP.index("id: card") : QP.index("// a finger swipes it away")]
    assert "Accessible.role: Accessible.Dialog" in card
    assert 'Accessible.name: Tr.t("Quick panel")' in card


def test_quickpanel_button_rows_expose_state_and_press_action():
    """Toggle/button rows must expose state text and be activatable by AT."""
    delegate = _delegate_block()
    # Button rows (value < 0) expose their visible state; sliders are covered by
    # the separate Accessible.value gap in GAPS.md, so do not bake values here.
    assert (
        'Accessible.description: rowData.value < 0 ? (rowData.text || "") : ""'
        in delegate
    )
    assert "Accessible.onPressAction: {" in delegate
    assert "if (rowData.run) rowData.run();" in delegate
    assert "else if (rowData.adjust) rowData.adjust(1);" in delegate


def test_quickpanel_selected_row_is_exposed_to_at():
    """Keyboard selection is visual; AT also needs the selected row state."""
    delegate = _delegate_block()
    assert "readonly property bool here: index === win.sel" in delegate
    assert "Accessible.selected: here" in delegate


def test_quickpanel_rowdata_lookup_is_null_safe():
    """Delegates can briefly outlive row rebuilds; a missing row must not crash."""
    assert (
        'readonly property var rowData: win.rows[modelData] || ({ key: "", label: "", icon: "", value: -1, text: "", adjust: null, run: null })'
        in QP
    )
