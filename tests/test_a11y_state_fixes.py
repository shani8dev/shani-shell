"""Static asserts for the pass-21 accessibility *state* fixes.

A role with a name but no state is silent to a screen reader: it cannot say
which tab is active, how far a progress ring has got, or whether a disclosure
is open. These check the three shared controls that gained that state.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def value_of(text, prop):
    m = re.search(r"(?<![\w.])" + re.escape(prop) + r"\s*:\s*([^\n]+)", text)
    assert m, f"{prop} is missing"
    return m.group(1).strip()


def test_pagetab_announces_which_tab_is_selected():
    text = source("shani/Common/SegmentedTabs.qml")
    assert "Accessible.role: Accessible.PageTab" in text
    selected = value_of(text, "Accessible.selected")
    assert "segment.index" in selected and "tabs.currentIndex" in selected, selected


def test_statusring_announces_its_progress_value():
    text = source("shani/Common/StatusRing.qml")
    assert "Accessible.role: Accessible.ProgressBar" in text
    # Accessible.value is NOT a valid Qt Quick attached property — Qt reads the
    # value off the item's own `value` property, bounded by min/max properties.
    assert "Accessible.value" not in text
    assert value_of(text, "property real value") == "1.0"
    assert value_of(text, "property real minimumValue") == "0"
    assert value_of(text, "property real maximumValue") == "1"
    # An unnamed ring is just "progress bar"; the fallback makes it identifiable.
    assert re.search(r"Accessible\.name:.*Tr\.t\(", text), "no translated fallback name"


def test_disclosure_button_announces_expanded_state():
    text = source("shani/Common/Advanced.qml")
    assert "Accessible.role: Accessible.Button" in text
    assert value_of(text, "Accessible.checkable") == "true"
    assert value_of(text, "Accessible.checked") == "root.open"
    # State only: a toggle action here would duplicate the existing press action.
    assert "onToggleAction" not in text
