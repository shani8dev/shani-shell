"""Static checks for the settings navigation, toast and slider-label fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_settings_has_clickable_breadcrumb_without_changing_escape():
    w = read("shani/Modules/Settings/SettingsWindow.qml")
    assert "function crumbBack()" in w
    assert "Accessible.onPressAction: winRoot.crumbBack()" in w
    assert (
        "KeyFocus { name: crumbSettings.text; onActivated: winRoot.crumbBack() }" in w
    )
    assert 'text: "›"' in w
    assert "crumbSubpage" in w
    # Escape must still close the whole window, not unwind the trail.
    assert "Keys.onEscapePressed: Ui.settingsOpen = false" in w
    # The control-centre variant gets its own crumb back to the grid.
    p = read("shani/Modules/Settings/SettingsPage.qml")
    assert 'text: Tr.t("Settings")' in p
    assert 'onClicked: Ui.settingsCat = ""' in p


def test_control_centre_renders_its_own_toast():
    p = read("shani/Modules/Settings/SettingsPage.qml")
    assert "Toast {" in p
    assert 'message: !page.inWindow ? page.toastMsg : ""' in p
    assert "showUndo: page.toastUndo !== undefined" in p
    assert "onUndo: page.undoToast()" in p
    # The chips that prompted this still feed that message.
    assert "page.showToast(" in p


def test_sliderrow_uses_human_label_for_accessibility():
    s = read("shani/Common/SliderRow.qml")
    assert 'property string label: ""' in s
    assert "Accessible.name: root.readableName" in s
    assert "name: root.readableName" in s
    assert "tip: root.readableName" in s
    assert "Accessible.name: root.icon" not in s
