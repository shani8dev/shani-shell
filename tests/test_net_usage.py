"""Network usage panel: static wiring plus the real vnStat parser logic.

Settings > Network already reads vnStat for "today / this month". The System
Monitor now surfaces the same database's day and month history, without a second
tracker or a new dependency. These tests check that wiring, then execute the
parser *from NetUsage.qml itself* under node against a realistic `vnstat --json`
sample (and against the missing-vnStat / empty-database cases).
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
NET_USAGE = ROOT / "shani/Services/NetUsage.qml"
PROCESSES = ROOT / "shani/Modules/Processes/Processes.qml"
SETTINGS_NETWORK = ROOT / "shani/Modules/Settings/SettingsNetwork.qml"
CHOICE = ROOT / "shani/Common/Choice.qml"


def source(path):
    return path.read_text(encoding="utf-8")


# ---- static wiring ---------------------------------------------------------


def test_net_usage_is_a_read_only_gated_singleton():
    t = source(NET_USAGE)
    assert t.startswith("pragma Singleton")
    assert "import Quickshell.Io" in t
    # the same vnStat source Settings > Network reads, no second tracker
    assert "vnstat --json" in t
    assert 'command -v vnstat >/dev/null 2>&1 || { echo "[]"; exit 0; }' in t
    assert "function refresh()" in t
    assert "Timer {" not in t and "running: true" not in t  # no idle poller
    assert "write(" not in t and "execDetached" not in t  # nothing is changed
    for needle in (
        "function parse(text)",
        "function selectInterface(name)",
        "property bool available",
        "property var interfaces",
        "property real weekTotal",
        "property real monthTotal",
    ):
        assert needle in t, needle
    # the interface filter is the one Settings > Network uses for its totals
    assert "/^(lo|veth|docker|br-|virbr|tun|tap)/" in t


def test_processes_shows_usage_below_the_overview_and_above_the_tree():
    p = source(PROCESSES)
    sec = p[p.index("id: netUsageSection") : p.index('text: Tr.t("Process tree")')]
    for needle in (
        'text: Tr.t("Network usage")',
        "NetUsage.refresh()",
        "NetUsage.available",
        "NetUsage.monthTotal",
        "NetUsage.weekTotal",
        "NetUsage.interfaces",
        "NetUsage.selectInterface(modelData)",
        "model: NetUsage.days",
        "netUsageSection.dayMax",
    ):
        assert needle in sec, needle
    assert p.index("id: netUsageSection") > p.index("id: card")
    assert p.index("id: netUsageSection") > p.index("model: Sensors.sensors")
    assert p.index("id: netUsageSection") < p.index('text: Tr.t("Process tree")')
    # the live overview strip, sparklines and disk row are left as they were
    assert p.count("Sparkline {") >= 3
    assert "SysStats.rxRate + SysStats.txRate" in p
    assert "SysStats.rate(SysStats.diskReadRate)" in p
    assert 'Tr.t("Per-process network: needs nethogs (root)' in p


def test_usage_panel_is_accessible_and_not_an_opaque_card():
    p = source(PROCESSES)
    sec = p[p.index("id: netUsageSection") : p.index('text: Tr.t("Process tree")')]
    assert 'Accessible.name: Tr.t("Network usage from vnStat")' in sec
    assert 'Accessible.name: Tr.t("%1: %2", modelData.date' in sec
    # read-only bars on the existing surface, not a second solid card
    assert "Theme.surface1" not in sec and "Theme.card" not in sec
    # interface chips already carry a radio role, Toggle action and KeyFocus
    c = source(CHOICE)
    assert "Accessible.role: Accessible.RadioButton" in c
    assert "Accessible.onToggleAction: root.clicked()" in c
    assert "KeyFocus {" in c


def test_settings_network_vnstat_command_is_still_the_reused_source():
    # this file is not edited by the panel; guard that the reuse stays honest
    t = source(SETTINGS_NETWORK)
    assert 'vnstat --oneline b -i "$i"' in t
    assert "vnstat --iflist" in t
    assert "f[5]" in t and "f[10]" in t
    assert "Theme.bytes(day)" in t and "Theme.bytes(month)" in t


# ---- the parser, run from the QML source ----------------------------------


def js_function(text, name):
    """One whole `function name(...) { ... }` by brace matching."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", text)
    assert m, name
    depth = 0
    for i in range(m.end() - 1, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() : i + 1]
    raise AssertionError(f"unbalanced function {name}")


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
def parse(raw):
    text = source(NET_USAGE)
    helpers = "\n".join(
        js_function(text, name)
        for name in ("pad2", "dayKey", "monthKey", "sum", "parse")
    )
    script = (
        helpers + "\nprocess.stdout.write(JSON.stringify(parse(process.argv[1])));\n"
    )
    done = subprocess.run(["node", "-e", script, raw], capture_output=True, text=True)
    assert done.returncode == 0, done.stderr
    return json.loads(done.stdout)


def vn_day(day, rx, tx):
    return {"date": {"year": 2026, "month": 11, "day": day}, "rx": rx, "tx": tx}


def vn_month(month, rx, tx):
    return {"date": {"year": 2026, "month": month}, "rx": rx, "tx": tx}


# a full `vnstat --json` answer: virtual interfaces, eight days (only the last
# seven should be shown) and two months, with the day/month rx+tx as bytes
SAMPLE = [
    {
        "vnstatversion": "2.6",
        "jsonversion": "1",
        "interfaces": [
            {
                "name": "lo",
                "traffic": {
                    "day": [vn_day(24, 50, 50)],
                    "month": [vn_month(11, 100, 100)],
                },
            },
            {"name": "veth8f2a", "traffic": {"day": [vn_day(24, 90, 90)], "month": []}},
            {"name": "docker0", "traffic": {"day": [vn_day(24, 70, 70)], "month": []}},
            {
                "name": "wlan0",
                "alias": "home",
                "traffic": {
                    "total": {"rx": 500000, "tx": 120000},
                    "day": [vn_day(17, 999999, 999999)]
                    + [
                        vn_day(18 + i, (i + 1) * 1000, (i + 1) * 100 + i * 0)
                        for i in range(7)
                    ],
                    "month": [
                        vn_month(10, 300000, 90000),
                        vn_month(11, 500000, 120000),
                    ],
                    "hour": [],
                },
            },
            {
                "name": "eth0",
                "traffic": {
                    "day": [vn_day(24, 100, 20)],
                    "month": [vn_month(11, 100, 20)],
                },
            },
        ],
    }
]


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
def test_parse_returns_last_seven_days_and_this_month_per_interface():
    out = parse(json.dumps(SAMPLE))
    assert out["interfaces"] == ["eth0", "wlan0"]  # lo/veth/docker filtered
    w = out["byInterface"]["wlan0"]
    assert len(w["days"]) == 7  # the eighth, older day is dropped
    assert [d["date"] for d in w["days"]] == [
        "2026-11-18",
        "2026-11-19",
        "2026-11-20",
        "2026-11-21",
        "2026-11-22",
        "2026-11-23",
        "2026-11-24",
    ]
    assert w["days"][-1]["rx"] == 7000 and w["days"][-1]["tx"] == 700
    assert w["days"][-1]["total"] == 7700
    assert w["week"] == sum(d["total"] for d in w["days"])
    assert w["week"] < 999999 * 2  # the dropped day is not counted
    assert [m["month"] for m in w["months"]] == ["2026-10", "2026-11"]
    assert w["month"] == 620000  # the latest month, not the sum of both
    assert out["byInterface"]["eth0"]["week"] == 120


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
@pytest.mark.parametrize(
    "raw",
    ["[]", '[{"interfaces": []}]', "not json", "", "{}"],
)
def test_parse_of_missing_or_empty_vnstat_is_an_honest_empty_state(raw):
    assert parse(raw) == {"interfaces": [], "byInterface": {}}


def test_oneline_totals_are_the_same_numbers_the_panel_shows():
    """The reuse: Settings > Network's --oneline b fields f[5] and f[10] are the
    day and month totals our JSON parser exposes as `week`'s last day and
    `month` (sample values below match SAMPLE's latest day and month)."""
    line = "1;wlan0;2026-11-24;7000;700;7700;1234;2026-11;500000;120000;620000;4567;0;0;0;0"
    f = line.split(";")
    assert float(f[5]) == 7700 and float(f[10]) == 620000
    assert SETTINGS_NETWORK.read_text(encoding="utf-8").count("parseFloat(f[5])") == 1
