"""WAVE 3 adversarial QA — regressions for the bug classes already found here.

Read-only: this file never edits QML or bridge source. Each check pins the
CORRECT behaviour, so it passes on fixed code and fails the moment a fix is
undone. A per-file check fakes no instantiation: it either runs the very same
JavaScript/Python the surface runs, or pins a guard in the source.

Files still landing are skipped with a loud reason rather than failing: a
missing file is not a bug in code that does not exist yet. As soon as a wave-3
file appears, every check for it becomes live.

The bug classes hunted here (all seen once in this repo already):
  * null/undefined derefs in bindings after Loader teardown -> `obj && obj[k]`
  * pkexec used for a READ-ONLY status -> direct reads only
  * arrays mutated in place (no reassignment -> no binding signal)
  * timers/pollers running while `wanted` is false (idle cost)
  * user paths interpolated into shell strings (must be argv)
  * unbounded caches/lists (need caps)
  * missing Accessible names on new interactive controls
  * i18n strings absent from template.json (breaks test_i18n)
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge"
if str(BRIDGE) not in sys.path:
    sys.path.insert(0, str(BRIDGE))

NODE = shutil.which("node") or shutil.which("nodejs")
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))

# The wave-3 files, as named by the wave plan.
WAVE3 = (
    "shani/Services/SpeedDial.qml",
    "shani/Services/SpeedDial.js",
    "shani/Services/Sensors.qml",
    "bridge/sensors.py",
    "shani/Services/NetUsage.qml",
    "shani/Services/TouchMode.qml",
    "shani/Services/RecentFiles.qml",
    "shani/Common/Accents.js",
)


def src(rel: str) -> str:
    """Read a wave-3 file, or skip the test while that subagent has not landed it."""
    path = ROOT / rel
    if not path.exists():
        pytest.skip(f"wave-3 file has not landed yet: {rel}")
    return path.read_text(encoding="utf-8")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def source_of(text: str, name: str) -> str:
    """One `function name(...) { ... }` verbatim, braces matched."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", text)
    assert m, f"function {name}() not found"
    depth = 0
    for j in range(m.end() - 1, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() : j + 1]
    raise AssertionError(f"unterminated function {name}()")


def node(prog: str):
    assert NODE, "node is required"
    out = subprocess.run(
        [NODE, "-e", prog], capture_output=True, text=True, timeout=30, check=True
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


def objects(text: str, kind: str):
    """Every `Kind { ... }` as (line, body), braces matched (strings blanked)."""
    # blank strings so `}` inside a literal is not treated as a brace
    clean = re.sub(
        r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'', lambda m: " " * len(m.group()), text
    )
    out = []
    for m in re.finditer(r"\b" + re.escape(kind) + r"\s*\{", clean):
        depth = 0
        for j in range(m.end() - 1, len(clean)):
            if clean[j] == "{":
                depth += 1
            elif clean[j] == "}":
                depth -= 1
                if depth == 0:
                    out.append(
                        (text.count("\n", 0, m.start()) + 1, text[m.start() : j + 1])
                    )
                    break
    return out


def tr_strings(text: str):
    """Every literal Tr.t("...") key in a source file.

    Unescape the way tools/i18n.py does: a `\\"` in QML source is a plain `"`
    in the catalog key, so this must agree with test_i18n's extractor.
    """
    return set(
        m.replace('\\"', '"').replace("\\\\", "\\")
        for m in re.findall(r'Tr\.t\(\s*"((?:[^"\\]|\\.)*)"\s*\)', text)
    )


# ---------------------------------------------------------------------------
# NetUsage.qml (landed) — read-only vnStat history for the System Monitor.
# ---------------------------------------------------------------------------


def netusage_prog() -> str:
    s = src("shani/Services/NetUsage.qml")
    return "\n".join(
        source_of(s, name) for name in ("pad2", "dayKey", "monthKey", "sum", "parse")
    )


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_netusage_parse_caps_history_and_drops_virtual_interfaces():
    """History must be bounded (7 days / 6 months) and lo/docker/veth dropped."""
    out = node(
        netusage_prog()
        + r"""
var days = [];
for (var i = 0; i < 12; i++) days.push({ date: { year: 2026, month: 11, day: i + 1 }, rx: 100, tx: 20 });
var months = [];
for (var i = 1; i <= 9; i++) months.push({ date: { year: 2026, month: i }, rx: 1000, tx: 200 });
var doc = [{ interfaces: [
  { name: "lo", traffic: { day: days, month: months } },
  { name: "vethXY", traffic: { day: days, month: months } },
  { name: "docker0", traffic: { day: days, month: months } },
  { name: "eth0", traffic: { day: days, month: months } }
]}];
var parsed = parse(JSON.stringify(doc));
process.stdout.write(JSON.stringify({
  interfaces: parsed.interfaces,
  days: parsed.byInterface.eth0.days.length,
  months: parsed.byInterface.eth0.months.length,
  week: parsed.byInterface.eth0.week,
  month: parsed.byInterface.eth0.month,
  oldest: parsed.byInterface.eth0.days[0].date,
  newest: parsed.byInterface.eth0.days[6].date
}));"""
    )
    assert out["interfaces"] == ["eth0"], out
    assert out["days"] == 7, "day history is unbounded"
    assert out["months"] == 6, "month history is unbounded"
    assert out["week"] == 7 * 120, out
    assert out["month"] == 1200, out
    assert out["newest"] == "2026-11-12", out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_netusage_parse_survives_garbage_and_missing_traffic():
    s = src("shani/Services/NetUsage.qml")
    prog = (
        "\n".join(
            source_of(s, n) for n in ("pad2", "dayKey", "monthKey", "sum", "parse")
        )
        + r"""
var results = [parse(""), parse("not json"), parse("{}"),
  parse(JSON.stringify([{ interfaces: [{ name: "eth0" }] }])),
  parse(JSON.stringify([{ interfaces: [null, {}] }]))];
process.stdout.write(JSON.stringify(results.map(function (r) {
  return { n: r.interfaces.length, keys: Object.keys(r.byInterface).length,
           days: r.byInterface.eth0 ? r.byInterface.eth0.days.length : -1 };
})));"""
    )
    out = node(prog)
    for r in out[:3] + out[4:]:
        assert r["n"] == 0 and r["keys"] == 0, r
    # a real interface with no traffic is still shown, with empty history
    assert out[3] == {"n": 1, "keys": 1, "days": 0}, out[3]


def test_netusage_has_no_idle_poller():
    """The monitor calls refresh() when opened; no timer may tick while idle."""
    s = src("shani/Services/NetUsage.qml")
    assert "Timer" not in s, "NetUsage must not carry a poller"


def test_netusage_reads_vnstat_without_pkexec_and_without_shell_interpolation():
    """Read-only status: a fixed argv command, no user data in the shell string."""
    s = src("shani/Services/NetUsage.qml")
    assert "pkexec" not in s
    line = next(l for l in s.splitlines() if "command:" in l)
    assert 'command: ["sh", "-c",' in line, line
    for bad in ("+ path", "+ root.", "${", "%1", ".arg("):
        assert bad not in line, (bad, line)


def test_netusage_reassigns_property_arrays_not_push():
    s = src("shani/Services/NetUsage.qml")
    for field in ("byInterface", "interfaces", "days", "months"):
        assert re.search(r"root\." + field + r"\s*=", s), field
        assert not re.search(r"root\." + field + r"\.push\(", s), field


# ---------------------------------------------------------------------------
# Sensors — direct sysfs reads in Python, a gated reader in QML.
# ---------------------------------------------------------------------------


def test_sensors_bridge_reads_sysfs_with_no_shell_no_root_no_pkexec():
    s = src("bridge/sensors.py")
    for bad in ("pkexec", "os.system", "shell=True", "subprocess", "sh -c"):
        assert bad not in s, f"sensors.py uses {bad}"
    assert 'open(path, "r"' in s, "status must be a direct file read"
    assert "glob.glob(" in s and "ATTR_RE" in s


def test_sensors_bridge_scales_levels_and_skips_garbage(tmp_path):
    """A tiny fake hwmon tree: millidegrees -> °C, thresholds -> level 0/1/2."""
    import sensors  # noqa: E402 (conftest puts bridge/ on sys.path)

    chip = tmp_path / "hwmon0"
    chip.mkdir()
    (chip / "name").write_text("coretemp\n", encoding="utf-8")
    (chip / "temp1_input").write_text("54000\n", encoding="utf-8")
    (chip / "temp1_label").write_text("Package id 0\n", encoding="utf-8")
    (chip / "temp1_max").write_text("85000\n", encoding="utf-8")
    (chip / "temp1_crit").write_text("95000\n", encoding="utf-8")
    (chip / "temp2_input").write_text("96000\n", encoding="utf-8")  # critical
    (chip / "temp2_crit").write_text("95000\n", encoding="utf-8")
    (chip / "temp3_input").write_text("garbage\n", encoding="utf-8")  # skipped
    (chip / "fan1_input").write_text("1200\n", encoding="utf-8")
    (chip / "in1_input").write_text("1200\n", encoding="utf-8")

    rows = sensors.read_sensors(str(tmp_path))
    by_label = {r["label"]: r for r in rows}
    assert "Package id 0" in by_label, rows
    pkg = by_label["Package id 0"]
    assert pkg["name"] == "coretemp"
    assert pkg["value"] == 54.0 and pkg["unit"] == "°C"
    assert pkg["max"] == 85.0 and pkg["crit"] == 95.0 and pkg["level"] == 0
    assert by_label["Temperature 2"]["level"] == 2, rows
    assert not any(r["label"] == "Temperature 3" for r in rows), (
        "garbage was not skipped"
    )
    assert by_label["Fan 1"]["value"] == 1200 and by_label["Fan 1"]["unit"] == "RPM"
    assert (
        by_label["Voltage 1"]["value"] == 1.2 and by_label["Voltage 1"]["unit"] == "V"
    )
    assert all(json.loads(json.dumps(rows)) == rows for _ in range(1))


def test_sensors_bridge_is_robust_to_a_missing_hwmon_tree():
    import sensors  # noqa: E402

    assert sensors.read_sensors("/nonexistent/hwmon/root") == []


def test_sensors_qml_gates_its_poller_and_clears_state_when_unwanted():
    s = src("shani/Services/Sensors.qml")
    assert "running: root.wanted" in s
    assert "if (!wanted)" in s
    assert "root.sensors = []" in s and "run.running = false" in s
    assert "if (root.loading || !root.wanted) return" in s
    assert "pkexec" not in s
    line = next(l for l in s.splitlines() if "command:" in l)
    assert 'command: ["python3", root.tool]' in line


# ---------------------------------------------------------------------------
# Speed dial — pure rules, so run the very same JS in node.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_speeddial_canonicalises_paths_and_deduplicates():
    s = src("shani/Services/SpeedDial.js")
    out = node(
        s.replace(".pragma library", "")
        + r"""
var home = "/home/u";
var same = canonical("/a/./b/", home) === canonical("/a//b", home)
       && canonical("~/docs", home) === "/home/u/docs";
var d = { sections: [{ name: "Work", entries: [
  { name: "A", path: "/a/./b", pinnedAt: 100 },
  { name: "B", path: "/a//b", pinnedAt: 200 },
  { name: "C", path: "~/docs", pinnedAt: 300 }
] }] };
var norm = normalise(d, home);
process.stdout.write(JSON.stringify({
  same: same,
  kept: norm.sections[0].entries.map(function (e) { return e.name; }),
  entries: entries(norm, "Work").map(function (e) { return e.name; })
}));"""
    )
    assert out["same"], "canonical() did not collapse equivalent paths"
    assert out["kept"] == ["A", "C"], out
    assert out["entries"] == ["C", "A"], "newest-first ordering is wrong"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_speeddial_caps_sections_and_entries_and_refuses_bad_names():
    s = src("shani/Services/SpeedDial.js")
    out = node(
        s.replace(".pragma library", "")
        + r"""
var sections = [], entries = [];
for (var i = 0; i < 20; i++) sections.push({ name: "S" + i, entries: [] });
for (var j = 0; j < 60; j++) entries.push({ name: "E" + j, path: "/p" + j, pinnedAt: j });
var data = { sections: [{ name: "S0", entries: entries }].concat(sections) };
var n = normalise(data, "/home/u");
process.stdout.write(JSON.stringify({
  sections: n.sections.length,
  entries: n.sections[0].entries.length,
  evilName: cleanName("__proto__") === "" && cleanName("../x") === "" && cleanName("a/b") === "",
  overflowSection: addSection(n, "S0") === null
}));"""
    )
    assert out["sections"] <= 12, out
    assert out["entries"] <= 40, out
    assert out["evilName"], "cleanName accepted a prototype/path key"
    assert out["overflowSection"], "duplicate section was not refused"


# ---------------------------------------------------------------------------
# CuboCore accent — Accents.js already exists; check its behaviour AND its use.
# ---------------------------------------------------------------------------


QT_SHIM = """
var Qt = {
    rgba: function (r, g, b, a) { return { r: r, g: g, b: b, a: a === undefined ? 1 : a }; },
    color: function (c) {
        if (typeof c === "string") {
            var h = c.replace("#", "");
            if (h.length === 3)
                h = h.split("").map(function (x) { return x + x; }).join("");
            var v = parseInt(h, 16);
            return { r: ((v >> 16) & 255) / 255, g: ((v >> 8) & 255) / 255, b: (v & 255) / 255, a: 1 };
        }
        return { r: c.r, g: c.g, b: c.b, a: c.a === undefined ? 1 : c.a };
    }
};
"""


def accent_modules() -> str:
    out = [QT_SHIM]
    for ns, rel in (
        ("Contrast", "shani/Common/Contrast.js"),
        ("Hct", "shani/Common/Hct.js"),
        ("Accents", "shani/Common/Accents.js"),
    ):
        s = read(rel).replace(".pragma library", "")
        s = re.sub(r'^\.import\s+"[^"]+"\s+as\s+\w+\s*$', "", s, flags=re.M)
        # expose the module-level globals the file uses as well as its functions
        names = re.findall(r"^function\s+(\w+)\s*\(", s, flags=re.M)
        names += re.findall(r"^var\s+(\w+)\s*=", s, flags=re.M)
        names = list(dict.fromkeys(n for n in names if n != "Qt"))
        out.append(
            "var %s = (function () {\n%s\nreturn { %s };\n})();"
            % (ns, s, ", ".join(f"{n}: {n}" for n in names))
        )
    return "\n".join(out)


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_accents_override_honours_the_chosen_hue_and_keeps_contrast():
    """A custom colour must move the matching slot's hue, not just retint all."""
    out = node(
        accent_modules()
        + """
var primary = { r: 1, g: 0.5, b: 0.31 };
var plain = Accents.derive(primary, false, {});
var custom = Accents.derive(primary, false, { blue: "#00ff00" });
var ratios = Object.keys(custom).map(function (k) {
    return Contrast.ratio(custom[k].onContainer, custom[k].container);
});
process.stdout.write(JSON.stringify({
  slots: Object.keys(custom),
  sameRed: Math.abs(Contrast.ratio(plain.red.container, custom.red.container) - 1) < 0.001,
  blueHueDelta: Math.abs(Hct.toHct(plain.blue.container).hue - Hct.toHct(custom.blue.container).hue),
  worst: Math.min.apply(Math, ratios)
}));"""
    )
    assert len(out["slots"]) == 8, out
    assert out["sameRed"], "an override to blue changed the red slot"
    assert out["blueHueDelta"] > 5, "the blue override was ignored"
    assert out["worst"] >= 4.5, out


def test_accents_are_wired_into_a_real_surface():
    """Dead-code gap: derive() existed for years; wave 3 must actually use it.
    Any QML surface consuming the API counts — do not pin one implementation."""
    users = [
        str(p.relative_to(ROOT))
        for p in (ROOT / "shani").rglob("*.qml")
        if p.name != "Accents.js"
        and re.search(
            r"\bAccents\.(?:derive|derivePreset|accentInk)\s*\(",
            p.read_text(encoding="utf-8"),
        )
    ]
    assert users, "Accents.derive()/derivePreset() is never called from QML — dead code"


# ---------------------------------------------------------------------------
# Cross-file invariants, applied to every wave-3 surface as it lands.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("rel", WAVE3)
def test_wave3_string_literals_are_all_in_the_i18n_template(rel):
    missing = sorted(tr_strings(src(rel)) - set(TEMPLATE))
    assert missing == [], f"{rel}: untranslated strings: {missing}"


@pytest.mark.parametrize(
    "rel",
    (
        "shani/Modules/Launcher/Launcher.qml",
        "shani/Modules/Processes/Processes.qml",
        "shani/Modules/Calendar/CalendarPanel.qml",
        "shani/Modules/Settings/SettingsPage.qml",
        "shani/Modules/Files/FilesPanel.qml",
        "shani/Modules/Files/SpeedDialPanel.qml",
    ),
)
def test_wave3_touched_surfaces_keep_their_strings_in_the_template(rel):
    """New rows in an existing surface are just as able to break test_i18n."""
    missing = sorted(tr_strings(read(rel)) - set(TEMPLATE))
    assert missing == [], f"{rel}: untranslated strings: {missing}"


@pytest.mark.parametrize("rel", [r for r in WAVE3 if r.endswith(".qml")])
def test_wave3_status_reads_never_use_pkexec(rel):
    s = src(rel)
    assert "pkexec" not in s, f"{rel}: pkexec in a status/read-only path"


@pytest.mark.parametrize("rel", [r for r in WAVE3 if r.endswith(".qml")])
def test_wave3_property_arrays_are_reassigned_not_mutated(rel):
    s = src(rel)
    bad = re.findall(
        r"(?:root|win|page|service)\.[\w.]+\.(?:push|splice|sort|reverse)\(", s
    )
    assert bad == [], f"{rel}: in-place mutation of a property array: {bad}"


@pytest.mark.parametrize("rel", [r for r in WAVE3 if r.endswith(".qml")])
def test_wave3_interactive_controls_have_accessible_names(rel):
    """A bare MouseArea is invisible to AT-SPI unless it carries a name."""
    s = src(rel)
    bad = []
    for line, body in objects(s, "MouseArea"):
        if "Accessible.name" not in body and "Accessible.role" not in body:
            bad.append(line)
    assert bad == [], f"{rel}: unnamed MouseArea at lines {bad}"


@pytest.mark.parametrize("rel", [r for r in WAVE3 if r.endswith(".qml")])
def test_wave3_derefs_are_guarded_after_loader_teardown(rel):
    """Bindings must read `obj && obj[key]`; an unguarded read throws once the
    Loader is torn down and `obj` becomes undefined."""
    s = src(rel)
    bad = []
    for i, line in enumerate(s.splitlines(), 1):
        # `Foo.bar[baz]` / `Foo.bar["key"]` directly inside a binding/visible/
        # text expression, with no `Foo.bar &&` on the same expression.
        if re.search(r"\b(?:root|win|page|service)\.[\w.]+\[[^\]]+\]", line):
            name = re.match(r"\s*(\w+(?:\.\w+)+)\[", line)
            if name and (name.group(1) + " &&") not in line:
                bad.append((i, line.strip()[:90]))
    assert bad == [], f"{rel}: unguarded deref in binding: {bad}"


# ---------------------------------------------------------------------------
# Re-check of the wave-1/2 fixes. These must never be silently undone.
# ---------------------------------------------------------------------------


def test_processes_new_sections_keep_labels_translatable():
    """The sensors/net-usage rows must stay localisable. Removing Tr.t() to make
    the i18n extractor stop complaining hides the strings instead of fixing them."""
    s = read("shani/Modules/Processes/Processes.qml")
    block = s[s.index("// ---- Hardware sensors") : s.index('Tr.t("Process tree")')]
    bad = []
    for i, line in enumerate(block.splitlines(), 1):
        if not re.search(
            r"\b(?:text|label|placeholder|tip|Accessible\.name)\s*:", line
        ):
            continue
        stripped = re.sub(r"Tr\.t\([^)]*\)", "", line)
        stripped = re.sub(r'(?:===|!==)\s*"[^"]*"', "", stripped)  # type checks
        if re.search(r'"[A-Za-z][A-Za-z ]{2,}', stripped):
            bad.append((i, line.strip()[:100]))
    assert bad == [], f"Processes.qml hardcodes user-facing labels: {bad}"

    severity = source_of(s, "sensorSeverity")
    assert "Tr.t(" in severity, "sensor severity words are not translatable"


def test_touch_detection_uses_the_existing_chain_not_a_second_service():
    """Touch auto-detection already exists (input-kinds -> InputKinds ->
    FormFactor -> Theme.touchTarget). Wave 3 must not add a duplicate poll loop."""
    assert not (ROOT / "shani/Services/TouchMode.qml").exists(), (
        "a second TouchMode service appeared — extend InputKinds instead"
    )
    kinds = read("shani/Services/InputKinds.qml")
    assert "interval:" not in kinds, "the touch chain gained an idle poller"
    assert "onInputRevChanged" in kinds
    form = read("shani/Services/FormFactor.qml")
    assert "touch: InputKinds.touchscreen" in form


def test_calendar_cell_marker_labels_are_translatable():
    """CalendarPanel's new day-cell markers carry user-visible labels; a bare
    English literal in an Accessible.name or the legend is untranslatable."""
    s = read("shani/Modules/Calendar/CalendarPanel.qml")
    fn = source_of(s, "cellA11yName")
    assert 'Tr.t("Holiday")' in fn, (
        'CalendarPanel.cellA11yName hardcodes "Holiday" instead of Tr.t()'
    )
    block = s[s.index("function cellA11yName") : s.index("// ---- week timetable")]
    untranslated = re.sub(r'Tr\.t\(\s*"[^"]*"\s*\)', "", block)
    leftover = " ".join(s.strip() for s in re.findall(r'"([^"]*)"', untranslated))
    assert not re.search(r"\b(?:Holiday|Holidays|more)\b", leftover), (
        f"calendar cell legend/a11y name has raw English labels: {leftover!r}"
    )


def test_w12_logind_derefs_still_guarded():
    """SettingsPowerKeys.qml — the page.logind deref was fixed once already."""
    s = read("shani/Modules/Settings/SettingsPowerKeys.qml")
    assert "(page.logind && page.logind[modelData])" in s
    assert '(page.logind && page.logind["IdleActionSec"])' in s


def test_w12_read_only_status_never_uses_pkexec():
    """SettingsStorage + SettingsPrinters: adminCmd is for writes only."""
    for rel, proc in (
        ("shani/Modules/Settings/SettingsStorage.qml", "fstrimGet"),
        ("shani/Modules/Settings/SettingsPrinters.qml", "cbGet"),
    ):
        s = read(rel)
        assert "// read-only status: no pkexec" in s, rel
        line = next(l for l in s.splitlines() if "id: " + proc in l)
        assert "pkexec" not in line and "adminCmd" not in line, (rel, line)


def test_w12_stats_polling_is_gated_by_wanted():
    s = read("shani/Services/SysStats.qml")
    assert s.count("running: root.wanted") >= 2
    assert "if (!wanted)" in s
    assert "root.lastDisk = null" in s


def test_w12_paths_are_passed_as_argv_not_a_shell_string():
    meta = read("shani/Services/FileMeta.qml")
    assert 'meta.command = ["python3", root.tool, p]' in meta
    assert "sh -c" not in meta and "shell: true" not in meta
    sessions = read("shani/Services/Sessions.qml")
    assert (
        'probe.command = ["sh", "-c", \'[ -d "$1" ] && echo dir || echo file\', "sh", p]'
        in sessions
    )


def test_w12_split_selection_is_copied_before_mutation():
    from_regex = source_of(read("shani/Services/Files.qml"), "selectSplit")
    assert not re.search(
        r"const\s+s\s*=\s*root\._splitPaths\s*;", from_regex
    ) or not re.search(r"\bs\.(?:splice|push|sort|reverse)\(", from_regex)


def test_w12_batch_results_are_reassigned():
    s = read("shani/Services/Archive.qml")
    assert "root.batchDone.push(" not in s
    assert "root.batchFailed.push(" not in s


def test_w12_playback_clamps_are_not_bypassed():
    s = read("shani/Services/PlayQueue.qml")
    assert "function clampVolume(v)" in s
    assert "function clampSeek(seconds, length)" in s
    assert "root.seekRequested(clampSeek(c.to, root.duration))" in s


def test_w12_i18n_extraction_still_covers_the_tree():
    """A new Tr.t literal without a template key breaks test_i18n; this pins
    the invariant locally with a clear, wave-3-specific message."""
    for rel in WAVE3:
        path = ROOT / rel
        if not path.exists():
            continue
        missing = sorted(tr_strings(path.read_text(encoding="utf-8")) - set(TEMPLATE))
        assert missing == [], f"{rel}: {missing}"
