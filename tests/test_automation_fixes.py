"""Static checks for the pass-22 automation/hooks fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_rules_can_be_edited_in_place():
    s = read("shani/Modules/Settings/SettingsAutomations.qml")
    # a rule row has an Edit button that loads that rule back into the form
    assert (
        'icon: "document-edit"; tip: Tr.t("Edit"); onClicked: page.loadRule(modelData, index)'
        in s
    )
    # the form tracks which rule it is editing and switches its button to Save
    assert "property int editIndex: -1" in s
    assert 'page.editIndex >= 0 ? Tr.t("Save") : Tr.t("Add")' in s
    # saving overwrites the edited rule in place instead of always appending
    assert "Object.assign(l[page.editIndex], rule)" in s
    assert "onClicked: page.saveRule()" in s


def test_fired_is_bounded_and_timestamped():
    s = read("shani/Services/Automations.qml")
    firing = next(l for l in s.splitlines() if "fired = fired.concat" in l)
    assert "slice(-50)" in firing
    assert "{ at: new Date().toISOString(), rule:" in firing
