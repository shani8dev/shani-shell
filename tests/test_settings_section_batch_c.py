"""Settings batch C: DevTools, Displays, Firewall, GamingMouse, Input, Journal
adopt SettingsSection/SettingRow where shape fits, keeping labels/actions/keys."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_devtools_uses_settings_section_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsDevTools.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Developer tools")' in s
    assert (
        "Quick install of common tools. Installing asks for your password (pkexec) and uses this system's package manager."
        in s
    )
    assert 'text: tool.installed ? Tr.t("Installed") : Tr.t("Install")' in s
    assert "pkexec pacman -S --needed --noconfirm " in s
    assert "pkexec apt-get install -y " in s
    assert "pkexec dnf install -y " in s
    assert "command -v " in s
    assert "install.running = true;" in s


def test_displays_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsDisplays.qml")
    assert s.count("SettingsSection {") >= 3
    assert 'title: Tr.t("Displays")' in s
    assert 'title: Tr.t("Scale presets")' in s
    assert 'title: Tr.t("Graphics")' in s
    assert "Displays.refresh()" in s
    assert "Displays.apply_all(" in s
    assert 'Tr.t("Drag a screen to where it stands on your desk.")' in s
    assert 'label: Tr.t("Resolution")' in s
    assert 'label: Tr.t("Refresh rate")' in s
    assert 'label: Tr.t("Scale")' in s
    assert 'label: Tr.t("Kind of screen")' in s
    assert 'label: Tr.t("Shell size")' in s
    assert 'label: Tr.t("Rotation")' in s
    assert 'text: Tr.t("Variable refresh rate")' in s
    assert 'label: Tr.t("Colour depth")' in s
    assert 'label: Tr.t("Resolution of your own")' in s
    assert 'text: Tr.t("Start the session on this screen")' in s
    assert 'text: Tr.t("This is a VR headset")' in s
    assert "Displays.toggleMirror(page.selected)" in s
    assert 'text: Tr.t("60 Hz on battery")' in s
    assert 'text: Tr.t("Rotate the screen automatically")' in s
    assert "Settings.data.niriRenderDevice" in s


def test_firewall_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsFirewall.qml")
    assert s.count("SettingsSection {") >= 4
    assert 'title: Tr.t("Firewall")' in s
    assert 'title: Tr.t("Default zone")' in s
    assert 'title: Tr.t("Rules")' in s
    assert 'title: Tr.t("Zones")' in s
    assert "Firewall.setEnabled(on)" in s
    assert "Firewall.setDefaultZone(modelData)" in s
    assert "Firewall.removePort(page.editing.name, modelData)" in s
    assert "Firewall.addPort(page.editing.name, portField.text.trim())" in s
    assert "Firewall.removeService(page.editing.name, modelData)" in s
    assert "Firewall.addService(page.editing.name, serviceField.text.trim())" in s
    assert "Firewall.removeRich(page.editing.name, modelData)" in s
    assert "Firewall.addRich(page.editing.name, ruleField.text.trim())" in s
    assert "Firewall.newZone(zoneField.text.trim())" in s
    assert "Firewall.deleteZone(gone)" in s
    assert 'text: Tr.t("Rich rules")' in s


def test_gaming_mouse_uses_settings_section_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsGamingMouse.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Gaming mouse")' in s
    assert '["python3", page.tool, "probe"]' in s
    assert 'page.change(["dpi", dev.modelData.id, v])' in s
    assert 'page.change(["rate", dev.modelData.id, v])' in s
    assert 'page.change(["button", dev.modelData.id, btn.modelData.index, v])' in s
    assert 'text: Tr.t("Buttons")' in s
    assert "page.buttonName(btn.modelData.index)" in s
    assert "page.actionLabel(btn.modelData.action)" in s


def test_input_uses_settings_sections_and_keeps_keys():
    s = read("shani/Modules/Settings/SettingsInput.qml")
    assert s.count("SettingsSection {") >= 6
    assert 'title: Tr.t("Keyboard layouts")' in s
    assert 'title: Tr.t("Touchpad")' in s
    assert 'title: Tr.t("Mouse")' in s
    assert 'title: Tr.t("Pointing stick & trackball")' in s
    assert 'title: Tr.t("Pointer")' in s
    assert 'title: Tr.t("Drawing tablet & touchscreen")' in s
    assert 'title: Tr.t("Keyboard")' in s
    assert "page.d.kbLayouts = l;" in s
    assert "page.d.kbSwitch = v" in s
    assert "page.d.kbPerWindow = on" in s
    assert "page.d.tapToClick = on" in s
    assert "page.d.naturalScroll = on" in s
    assert "page.d.mouseNaturalScroll = on" in s
    assert "page.d.leftHanded = on" in s
    assert "page.d.cursorHideTyping = on" in s
    assert "page.d.doubleClickSpeed = v" in s
    assert 'Calibrate.start("touch")' in s
    assert 'Calibrate.start("tablet")' in s
    assert "page.d.kbdBacklight = modelData.id" in s
    assert "page.d.numlock = on" in s
    assert "page.d.keyRepeatDelay = v" in s
    assert "page.d.keyRepeatRate = v" in s
    assert "page.d.kbCompose = v" in s
    assert "page.d.kbCaps = v" in s


def test_journal_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsJournal.qml")
    assert s.count("SettingsSection {") >= 2
    assert 'title: Tr.t("Journal")' in s
    assert 'title: Tr.t("Recent log")' in s
    assert "page.save()" in s
    assert "page.vacuum()" in s
    assert "page.loadLog()" in s
    assert '["journalctl", "-n", "80", "--no-pager", "-o", "short"]' in s
    assert "journald-set" in s
    assert "journald-vacuum" in s
    assert "page.storage = modelData;" in s
    assert "page.confirmingStorage" in s
