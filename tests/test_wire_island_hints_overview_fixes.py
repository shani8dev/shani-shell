"""Static checks for the tool cross-wiring: the Island's idle live activities,
the first-run Start Hints, the Overview's quick chips and the Ring's Tools hub.

These are QML windows with no runtime in pytest, so each wiring is checked at
source level (the style of test_wire_nettools_fixes.py).
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def body(src, marker):
    """The balanced `{ ... }` block that follows `marker`."""
    start = src.index(marker)
    brace = src.index("{", start)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[brace : i + 1]
    raise AssertionError(f"unbalanced block after {marker}")


def test_island_activates_the_three_no_op_live_activities():
    s = source("shani/Modules/Island/Island.qml")
    live = body(s, "readonly property var liveActivity:")
    # each placeholder now acts on the thing it reports, without touching the
    # rest state (the final `return null` is still there)
    assert (
        'text: "Photo in " + Camera.countdown + "…", color: Theme.accent, run: () => { Ui.closeAll(); Ui.photos = true; }'
        in live
    )
    assert (
        'text: Tr.t("Writing it down…"), color: Theme.accent, run: () => Ui.openNotes()'
        in live
    )
    assert (
        'text: Tr.t("Backing up…"), color: Theme.accent, run: () => { Ui.closeAll(); Ui.backup = true; }'
        in live
    )
    assert "run: () => {}" not in live
    assert "return null;\n    }" in live


def test_start_hints_teaches_the_launcher_tool_operator():
    s = source("shani/Modules/Hints/StartHints.qml")
    # one more entry in the existing hints model - no new state was added
    assert 'model: [{ keys: "Super + Space", what: Tr.t("open an app' in s
    assert "find tools: type tool: for Dictionary, Podcasts, Network Tools and Gateway" in s
    assert "Settings.data.startHintsDone" in s  # the existing dismissal still owns it


def test_overview_has_tool_chips_that_use_the_existing_search_path():
    s = source("shani/Modules/Overview/OverviewSearch.qml")
    assert "readonly property var toolChips:" in s
    for q in ("tool:dictionary", "tool:podcasts", "tool:network", "tool:gateway"):
        assert f'query: "{q}"' in s
    # a chip goes through search(), which applies the field filter and hands
    # over to the launcher - it never bypasses the operator logic
    assert "onClicked: { win.search(modelData.query); }" in s
    assert 'Ui.toggleLauncher(f + (text || ""))' in s
    # chips live in the empty-field browse row, which is now always available
    assert 'visible: win.typed === ""' in s
    assert "model: win.toolChips" in s


def test_ring_has_a_tools_hub_without_growing_past_eight_keys():
    s = source("shani/Modules/Ring/Ring.qml")
    root = body(s, "function root()")
    # the hub is a sub-slice under Apps, so the root keeps its eight keys
    assert (
        len([ln for ln in root.splitlines() if ln.startswith("            { label:")])
        == 8
    )
    assert 'label: Tr.t("Tools"), icon: "tools", children:' in root
    for label, flag in (
        ("Dictionary", "dictionary"),
        ("Podcasts", "podcasts"),
        ("Network Tools", "netTools"),
        ("Gateway", "gateway"),
    ):
        assert f'label: Tr.t("{label}")' in root
        assert f"Ui.{flag} = true;" in root
    assert 'Ui.toggleLauncher("tool:")' in root
