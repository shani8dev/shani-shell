"""Static checks for the overview search/stats and Island fixes.

Each test is one bug a person hits: a hand-over timer that fires after the
search was already committed or cancelled, a query that cannot be corrected,
a stats card that is blank until the first process sample, and an Island that
keeps the exclusive keyboard for a field the approval card has hidden.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCH = "shani/Modules/Overview/OverviewSearch.qml"
STATS = "shani/Modules/Overview/OverviewStats.qml"
ISLAND = "shani/Modules/Island/Island.qml"


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def block(text, needle):
    """The brace-counted {...} that follows the first occurrence of `needle`."""
    start = text.index(needle)
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
    raise AssertionError(f"unterminated block after {needle!r}")


def test_committing_or_cancelling_stops_the_handover_timer():
    text = source(SEARCH)
    # search() opens/closes the launcher itself; the timer that would hand the
    # query over 220 ms later must not toggle it again
    assert "handOver.stop()" in block(text, "function search(text)")
    # Escape, and Enter with nothing typed, close without calling search()
    keys = block(text, "Keys.onPressed")
    assert re.search(
        r'Key_Escape \|\| win\.typed === ""\)\s*\{\s*handOver\.stop\(\)', keys
    ), keys


def test_backspace_corrects_the_query():
    keys = block(source(SEARCH), "Keys.onPressed")
    assert "Qt.Key_Backspace" in keys
    assert "win.typed.slice(0, -1)" in keys
    # handled before the generic text insertion, or the key is appended
    assert keys.index("Qt.Key_Backspace") < keys.index("win.typed += e.text")
    # an emptied query has nothing to hand over
    assert re.search(
        r"if \(win\.typed !== \"\"\)\s*handOver\.restart\(\);\s*else\s*handOver\.stop\(\)",
        keys,
    ), keys


def test_stats_card_says_it_is_still_reading():
    text = source(STATS)
    assert re.search(r"visible: TopProcesses\.list\.length === 0", text)
    assert re.search(r'note: Tr\.t\("Reading…"\)', text)
    # reused catalog string: no template edit needed for this fix
    catalog = json.loads(source("shani/i18n/template.json"))
    assert "Reading…" in catalog


def test_approval_cancels_an_open_question_field():
    text = source(ISLAND)
    handler = block(text, "onHasApprovalChanged")
    assert "asking = false" in handler
    assert 'askInput.text = ""' in handler
    # Ui.askIsland() must not open the invisible field under an approval either
    assert "if (win.hasApproval)" in block(text, "function onAskRequested()")


def test_ask_field_focus_follows_the_ask_mode():
    field = block(source(ISLAND), "TextInput {")
    assert "id: askInput" in field
    assert re.search(r'focus: win\.mode === "ask"', field), field
    assert re.search(r'visible: win\.mode === "ask"', field), field
