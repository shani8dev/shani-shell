"""System overview in the System Monitor: one strip, four links, no new reader.

The surface used to make you leave the process list to discover Disks, Disk
Usage, battery health and About for yourself. The links mapping is data in the
QML, so it can be checked here without starting a shell: parse the array and the
switch, then replay what each link would open.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROCESSES = "shani/Modules/Processes/Processes.qml"

# label -> (action, the calls that action must make, in order)
EXPECTED_LINKS = [
    ("Disks", "disks", ["Ui.closeAll()", "Ui.disks = true", "Disks.refresh()"]),
    ("Disk usage", "diskUsage", ["DiskUsage.open()"]),
    ("Battery & wellbeing", "power", ['Ui.openSettings("power")']),
    ("About this computer", "about", ['Ui.openSettings("about")']),
]


def qml():
    return (ROOT / PROCESSES).read_text(encoding="utf-8")


def overview_block(text):
    """The strip, from its section heading to the sparkline row it precedes."""
    start = text.index('text: "System overview"')
    end = text.index("// the last minute, from the samples SysStats")
    return text[start:end]


def parse_links(text):
    """The { label, action } rows of win.overviewLinks, in display order."""
    block = text[
        text.index("readonly property var overviewLinks") : text.index(
            "function openOverviewLink"
        )
    ]
    found = re.findall(
        r'\{\s*label:\s*Tr\.t\("([^"]+)"\),\s*action:\s*"([^"]+)"\s*\}', block
    )
    return found


def parse_cases(text):
    """action -> the statements of its switch branch in openOverviewLink."""
    fn = text[text.index("function openOverviewLink") :]
    fn = fn[: fn.index("\n    }")]
    cases = {}
    for action, body in re.findall(r'case\s+"([^"]+)":\s*(.*?)\n\s*break;', fn, re.S):
        cases[action] = [c.strip() for c in body.split(";") if c.strip()]
    return cases


# ---- the numbers are the existing samples ----------------------------------


def test_overview_sits_above_the_sparklines_and_uses_only_sysstats():
    text = qml()
    block = overview_block(text)
    assert text.index("System overview") < text.index("Sparkline {")
    for expr in (
        "SysStats.cpu",
        "SysStats.mem",
        "SysStats.diskReadRate + SysStats.diskWriteRate",
        "SysStats.rxRate + SysStats.txRate",
        "SysStats.temp",
        "SysStats.load1",
    ):
        assert expr in block, expr
    # the per-process disk I/O row the first pass added is still by the graphs
    assert 'Tr.t("Disk I/O")' in text
    assert "SysStats.rate(SysStats.diskReadRate)" in text
    assert "SysStats.rate(SysStats.diskWriteRate)" in text
    assert text.count("Sparkline {") == 3


def test_no_second_poller_or_reader_was_added():
    text = qml()
    # the confirmation timer is the only timer this window has ever had
    assert text.count("Timer {") == 1
    for forbidden in (
        "FileView",
        "StdioCollector",
        "Process {",
        "Qt.createQmlObject",
        "Launch.app",
    ):
        assert forbidden not in text, forbidden


# ---- the links are named, keyboard reachable and not opaque cards ----------


def test_link_buttons_use_theme_tokens_and_have_accessible_names():
    block = overview_block(qml())
    assert "model: win.overviewLinks" in block
    assert 'kind: "outline"' in block  # transparent fill, Theme.stroke border
    assert 'Accessible.name: Tr.t("Open %1", modelData.label)' in block
    assert "onClicked: win.openOverviewLink(modelData.action)" in block
    # Common/Button supplies KeyFocus, so these are in the tab chain; no new
    # opaque Rectangle was introduced for the strip
    assert "Rectangle {" not in block
    assert not re.search(r'color:\s*"#', block)
    for token in ("Theme.accent", "Theme.blue", "Theme.amber", "Theme.dim", "Theme.px"):
        assert token in block, token


# ---- pure logic: label -> action -> one existing surface -------------------


def test_overview_links_map_to_exactly_one_existing_surface():
    text = qml()
    links = parse_links(text)
    cases = parse_cases(text)
    assert links == [(label, action) for label, action, _ in EXPECTED_LINKS]
    assert set(cases) == {action for _, action, _ in EXPECTED_LINKS}
    for label, action, calls in EXPECTED_LINKS:
        assert cases[action] == calls, (label, action, cases.get(action))
        # a link may open something, never end a process or tear the shell down
        for statement in cases[action]:
            assert "TopProcesses.end(" not in statement
            assert "Ui.processes = false" not in statement
            assert "Ui.closeApps()" not in statement
            assert "Qt.callLater" not in statement
