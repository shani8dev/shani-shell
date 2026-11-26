"""Files to and from the paired phone have one UI, used by Calls and Devices.

The bridge verbs (files send/received/receive) are covered in test_phone_tools.py;
these guards pin that a person can reach them from a window: the picker sends,
the received list opens a file and shows it in Files, and the Files app's
context menu offers the same send.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_devices_has_a_files_tab_that_uses_the_shared_view():
    win = read("shani/Modules/Devices/DevicesWindow.qml")
    assert '["files", Tr.t("Files")]' in win
    assert 'visible: win.tab === "files"' in win
    assert "PhoneFiles {" in win
    assert 'Tr.t("Send a file")' in win


def test_one_phone_files_view_serves_calls_and_devices():
    shared = read("shani/Common/PhoneFiles.qml")
    assert "PhoneTools.filesSend(paths[0])" in shared
    assert "Ui.filePicker.open({" in shared
    assert 'Tr.t("Receive files from the phone")' in shared
    assert "model: PhoneTools.files" in shared
    assert "Files.openEntry(modelData.path)" in shared
    assert 'Files.select(p, "single")' in shared
    assert read("shani/Modules/Calls/FilesTab.qml").strip().endswith("PhoneFiles {}")


def test_files_context_menu_can_send_to_the_phone():
    files = read("shani/Modules/Files/FilesPanel.qml")
    assert 'Tr.t("Send to phone")' in files
    assert "PhoneTools.filesSend(e.path)" in files


def test_live_part_drives_send_received_and_open():
    part = read("dev/shell-parts/devices.sh")
    assert "radio button:^Files$" in part
    assert "filePickerAccept" in part
    assert "Asha-photo.jpg" in part
    assert "Open Asha-photo.jpg" in part
    assert "Show Asha-photo.jpg in Files" in part
