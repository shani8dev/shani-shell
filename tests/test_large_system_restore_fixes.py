"""Static and JS-unit guards for the thin System Restore panel.

The shell does not own rollback: `shani-deploy --rollback` does. These tests
pin that the panel only reads `shani-deploy --status`, asks twice before
handing a slot switch to pkexec, and says plainly that file-level restores
stay in Backup. The parser is extracted from the QML and run under node
against the `shani-deploy --status` shape used in dev/shell-parts and its
`--status --json` contract.
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SERVICE_PATH = ROOT / "shani/Services/SystemRestore.qml"
PANEL_PATH = ROOT / "shani/Modules/Settings/SettingsSystemRestore.qml"
SERVICE = SERVICE_PATH.read_text(encoding="utf-8")
PANEL = PANEL_PATH.read_text(encoding="utf-8")

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")

# Verbatim shape from dev/showcase.sh / dev/render.sh, with the fields the
# parser accepts alongside it.
STATUS_FIXTURE = """  slot   A  (active)  2026.10.27  verified
  slot   B            2026.10.21  1.4 GB  verified
  previous slot  B
  current slot   A
  next   update ready  ·  312 MB  ·  signed
"""

JSON_FIXTURE = json.dumps(
    {
        "version": "20261121",
        "profile": "niri",
        "channel": "stable",
        "booted_slot": "green",
        "current_slot": "blue",
        "previous_slot": "blue",
        "candidate_boot": True,
        "update_available": "20261122",
        "reboot_needed": True,
        "boot_markers": {"reboot_needed": True},
        "boot_failure": "",
        "auto_rollback_done": False,
    }
)


def _parser_js():
    """Slice the parser by its markers (brace counting breaks on regexes)."""
    start = SERVICE.index("// ---- parser:begin")
    end = SERVICE.index("// ---- parser:end")
    assert start < end
    return SERVICE[start:end]


def _parse(text):
    js = _parser_js() + (
        "\nvar out = parseStatus(" + json.dumps(text) + ");"
        "process.stdout.write(JSON.stringify(out));"
    )
    result = subprocess.run([node, "-e", js], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


# ---- 1. read path degrades honestly -----------------------------------------


def test_status_is_read_only_and_non_zero_becomes_an_error():
    assert (
        '"command -v shani-deploy >/dev/null || exit 3; exec shani-deploy --status"'
        in SERVICE
    )
    assert "onExited: code => {" in SERVICE
    assert "if (code !== 0) {" in SERVICE
    assert (
        'code === 3\n                    ? Tr.t("shani-deploy is not installed; system slots cannot be read.")'
        in SERVICE
    )
    assert "root.error = p" not in SERVICE  # no fabricated state on failure
    assert "root.slots = p.slots;" in SERVICE  # success assigns parsed data


# ---- 2. tolerant parser: human-readable fixture -----------------------------


@node_mark
def test_parser_reads_slots_active_and_optional_metadata():
    out = _parse(STATUS_FIXTURE)
    assert [s["id"] for s in out["slots"]] == ["A", "B"]
    assert out["activeSlot"] == "A"
    assert out["previousSlot"] == "B"
    assert [s["state"] for s in out["slots"]] == ["active", "passive"]
    assert out["slots"][0]["date"] == "2026.10.27"
    assert out["slots"][1]["date"] == "2026.10.21"
    assert out["slots"][1]["size"] == "1.4 GB"
    assert out["slots"][1]["health"].lower() == "verified"
    assert out["upgradePending"] is True
    assert out["parsed"] is True


# ---- 3. tolerant parser: JSON contract, empty and junk ----------------------


@node_mark
def test_parser_accepts_json_contract_and_degrades_on_junk():
    out = _parse(JSON_FIXTURE)
    assert out["activeSlot"] == "green"
    assert out["previousSlot"] == "blue"
    assert [s["state"] for s in out["slots"]] == ["active", "passive"]
    assert out["rebootNeeded"] is True
    assert out["upgradePending"] is True
    assert out["channel"] == "stable"
    pending = [s for s in out["slots"] if s["id"] == "blue"][0]
    assert pending["pending"] is True  # current != booted: starts after restart
    assert _parse("")["parsed"] is False
    junk = _parse("some unrelated warning\nno slots here\n")
    assert junk["slots"] == []
    assert "did not report any installed slots" in junk["note"]


# ---- 4. actions use the existing rollback verb ------------------------------


def test_actions_call_the_existing_rollback_and_refuse_other_slots():
    assert (
        '"command -v shani-deploy >/dev/null || exit 3; exec pkexec '
        '/usr/local/bin/shani-deploy --rollback"'
    ) in SERVICE
    assert "function switchSlot(slot) {" in SERVICE
    assert "function restorePrevious() {" in SERVICE
    assert "target !== root.previousSlot" in SERVICE
    assert "shani-deploy can only switch back to the previous slot." in SERVICE
    assert 'root.startRollback(Tr.t("Switching back to slot %1…", target));' in SERVICE
    assert 'root.startRollback(Tr.t("Going back to the previous system…"));' in SERVICE
    assert "if (root.busy) return;" in SERVICE  # single flight


# ---- 5. two-tap confirm ------------------------------------------------------


def test_panel_arms_before_switching():
    assert 'property string confirming: ""' in PANEL
    assert "if (panel.confirming === slot.id) {" in PANEL
    assert "SystemRestore.switchSlot(slot.id);" in PANEL
    assert "panel.confirming = slot.id;" in PANEL
    assert "const id = SystemRestore.previousSlot;" in PANEL
    assert "if (panel.confirming === id) {" in PANEL
    assert "SystemRestore.restorePrevious();" in PANEL
    assert 'Tr.t("Tap again to switch to slot %1", modelData.id)' in PANEL
    assert 'Tr.t("Tap again to go back")' in PANEL


# ---- 6. slot cards ----------------------------------------------------------


def test_slot_cards_label_states_and_show_dates_and_sizes():
    for label in ("Running now", "Previous system · kept for rollback", "Other system"):
        assert 'Tr.t("' + label + '")' in PANEL
    assert 'objectName: "system-restore-slot-" + modelData.id' in PANEL
    assert (
        'modelData.date !== "" || modelData.size !== "" || modelData.health !== ""'
        in PANEL
    )
    assert 'modelData.pending ? Tr.t("starts after restart") : ""' in PANEL
    assert 'visible: modelData.state === "passive"' in PANEL


# ---- 7. dry run is capability-gated -----------------------------------------


def test_dry_run_is_advertised_not_assumed():
    assert "function probeDryRun() {" in SERVICE
    assert "shani-deploy --help 2>&1 | grep -q -- '--dry-run'" in SERVICE
    assert "function preview() {" in SERVICE
    assert "if (!root.dryRunSupported) {" in SERVICE
    assert "exec shani-deploy --dry-run" in SERVICE
    assert 'objectName: "system-restore-no-dry-run"' in PANEL
    assert "has no dry run for a slot switch" in PANEL
    assert (
        "visible: SystemRestore.dryRunSupported || SystemRestore.previewLines.length > 0"
        in PANEL
    )


# ---- 8. busy / progress / error / offline / empty ----------------------------


def test_every_state_has_an_explicit_face():
    for marker in (
        "system-restore-busy",
        "system-restore-action-error",
        "system-restore-error",
        "system-restore-offline",
        "system-restore-empty",
        "system-restore-note",
    ):
        assert 'objectName: "' + marker + '"' in PANEL
    assert "visible: SystemRestore.busy" in PANEL
    assert "visible: SystemRestore.progress.length > 0" in PANEL
    assert 'visible: SystemRestore.error !== ""' in PANEL
    assert (
        'visible: !SystemRestore.loading && SystemRestore.error === "" && SystemRestore.slots.length === 0'
        in PANEL
    )
    assert (
        'root.actionError = Tr.t("That needed administrator rights and was not given.");'
        in SERVICE
    )


# ---- 9. AT names and keyboard reach -----------------------------------------


def test_panel_is_named_and_keyboard_reachable():
    assert 'objectName: "system-restore-panel"' in PANEL
    assert "focus: active" in PANEL
    assert "Keys.onPressed: event => {" in PANEL
    for key in (
        "Qt.Key_Return",
        "Qt.Key_Enter",
        "Qt.Key_Escape",
        "Qt.Key_1",
        "Qt.Key_2",
    ):
        assert key in PANEL
    assert "Accessible.name: panel.labelFor(modelData)" in PANEL
    assert "Accessible.name: text" in PANEL
    assert "Accessible.name: SystemRestore.error" in PANEL


# ---- 10. scope is stated -----------------------------------------------------


def test_scope_note_separates_slot_switch_from_file_restore():
    assert 'objectName: "system-restore-scope"' in PANEL
    assert "blue-green slot switch" in PANEL
    assert "does not restore individual files" in PANEL
    assert "stays in Backup" in PANEL
    assert (
        "The slot switch is set. Restart to finish; no files were restored." in SERVICE
    )


# ---- 11-17. btrfs / shani-backup snapshot bridge and its panel half ----------
# ---- 11-. btrfs / shani-backup snapshot bridge and its panel half -----------
# ---- 11-. btrfs / shani-backup snapshot bridge and its panel half -----------
