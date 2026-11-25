"""Uniform two-tap confirms: migrated surfaces use shani/Common/ConfirmButton.qml.

Static checks pin each migrated site to the shared component and make sure the
old flag + Timer + label-flip is gone. The node check exercises the same
armed -> confirmed -> disarmed state machine the component implements.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def confirm_block(text, ident):
    """The ConfirmButton {...} block carrying `ident`."""
    start = text.index("id: " + ident)
    open_brace = text.index("{", text.rfind("ConfirmButton", 0, start))
    depth = 0
    for i in range(open_brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace : i + 1]
    raise AssertionError("unterminated ConfirmButton block for " + ident)


MIGRATED = [
    # (file, id, text, armedText, onConfirmed, stale tokens)
    (
        "shani/Modules/Settings/SettingsPage.qml",
        "resetSectionConfirm",
        'text: Tr.t("Reset this section")',
        'armedText: Tr.t("Tap again to reset")',
        "onConfirmed: page.resetSection()",
        ["confirmResetSection", "sectionResetTimer"],
    ),
    (
        "shani/Modules/Settings/SettingsPage.qml",
        "resetAllConfirm",
        'text: Tr.t("Reset all settings to their defaults")',
        'armedText: Tr.t("Tap again to reset everything")',
        "onConfirmed: page.resetAll()",
        ["confirmingReset", "resetTimer"],
    ),
    (
        "shani/Modules/Tasks/TasksWindow.qml",
        "bulkDeleteConfirm",
        'text: Tr.t("Delete")',
        'armedText: Tr.t("Tap again to delete")',
        "onConfirmed: win.bulkDelete()",
        ["confirmBulk", "bulkTimer"],
    ),
    (
        "shani/Modules/Tasks/TasksWindow.qml",
        "clearDoneConfirm",
        'text: Tr.t("Clear done")',
        'armedText: Tr.t("Tap again to clear done")',
        "onConfirmed: win.clearDone()",
        ["confirmClear", "clearTimer"],
    ),
    (
        "shani/Modules/Services/ServicesWindow.qml",
        "cronRemoveConfirm",
        'text: Tr.t("Remove")',
        'armedText: Tr.t("Tap again to remove")',
        "onConfirmed: SysServices.cronRemove(modelData.index)",
        ["confirmCron", "cronConfirmTimer"],
    ),
    (
        "shani/Modules/Software/SoftwareWindow.qml",
        "removeAppConfirm",
        'text: Tr.t("Remove")',
        'armedText: Tr.t("Click again to remove")',
        'onConfirmed: win.runJob(["remove", appCol.a.id], appCol.a.id)',
        ["win.removing === appCol.a.id"],
    ),
    (
        "shani/Modules/Notes/NotesPanel.qml",
        "deleteNoteConfirm",
        'text: Tr.t("Delete")',
        'armedText: Tr.t("Tap again to delete")',
        "onConfirmed: Services.QuickNotes.remove(Services.QuickNotes.current, Services.QuickNotes.currentNotebook)",
        ["property bool confirmDelete", "deleteTimer"],
    ),
]


@pytest.mark.parametrize("rel,ident,text,armed_text,confirmed,stale", MIGRATED)
def test_migrated_surface_uses_confirm_button(
    rel, ident, text, armed_text, confirmed, stale
):
    s = read(rel)
    b = confirm_block(s, ident)
    assert text in b
    assert armed_text in b
    assert "interval: 4000" in b
    assert confirmed in b
    assert "Timer {" not in b  # no hand-rolled timer inside a migrated surface
    for token in stale:
        assert token not in s, (ident, token)


def test_no_stale_confirm_flags_left_behind():
    """The six migrated flags/timers must not survive anywhere in Modules."""
    sources = "\n".join(
        p.read_text(encoding="utf-8") for p in (ROOT / "shani/Modules").rglob("*.qml")
    )
    for stale in (
        "confirmResetSection",
        "confirmingReset",
        "confirmBulk",
        "confirmClear",
        "confirmCron",
        "sectionResetTimer",
        "cronConfirmTimer",
    ):
        assert stale not in sources, stale


def test_confirm_button_implements_the_expected_state_machine():
    src = read("shani/Common/ConfirmButton.qml")
    assert "property bool armed: false" in src
    assert "root.confirmed(root.value)" in src
    assert "root.disarm()" in src
    assert "root.armed = true; timer.restart()" in src
    assert "onTriggered: root.armed = false" in src


@pytest.mark.skipif(shutil.which("node") is None, reason="node not available")
def test_armed_confirmed_and_timeout_timing():
    """Model of ConfirmButton.qml: first click arms, second confirms once,
    the timeout and disarm() both cancel without firing the action."""
    js = r"""
    // mirrors ConfirmButton.qml onClicked / onTriggered / disarm()
    function makeButton() {
      const out = { armed: false, confirmed: 0, fired: 0 };
      function click() {
        if (out.armed) { out.confirmed++; out.fired++; out.armed = false; }
        else { out.armed = true; }
      }
      function timeout() { out.armed = false; }          // timer.onTriggered
      function disarm() { out.armed = false; }           // caller cancels
      return { out, click, timeout, disarm };
    }
    const a = makeButton();
    a.click();                       // arm
    const armed = { ...a.out };
    a.click();                       // confirm
    const confirmed = { ...a.out };
    a.click();                       // a fresh arm, not a second confirm
    const rearmed = { ...a.out };

    const b = makeButton();
    b.click(); b.timeout(); b.click();  // timed-out tap must only re-arm
    const afterTimeout = { ...b.out };

    const c = makeButton();
    c.click(); c.disarm(); c.click();   // explicit cancel must only re-arm
    const afterDisarm = { ...c.out };

    console.log(JSON.stringify({ armed, confirmed, rearmed, afterTimeout, afterDisarm }));
    """
    result = subprocess.run(
        ["node", "-e", js], capture_output=True, text=True, check=True
    )
    timing = json.loads(result.stdout.strip())

    assert timing["armed"] == {"armed": True, "confirmed": 0, "fired": 0}
    assert timing["confirmed"] == {"armed": False, "confirmed": 1, "fired": 1}
    assert timing["rearmed"] == {"armed": True, "confirmed": 1, "fired": 1}
    assert timing["afterTimeout"] == {"armed": True, "confirmed": 0, "fired": 0}
    assert timing["afterDisarm"] == {"armed": True, "confirmed": 0, "fired": 0}
