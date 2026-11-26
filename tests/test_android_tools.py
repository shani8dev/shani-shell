"""bridge/android_tools.py: one JSON answer per command, even with no backends.

Every command is run through main() against the dev stand-ins (fake-adb-full.py,
fake-android-phone.py) and against small SHANI_* scripts, the way the other
bridge tests do. No call reaches a real phone; no test needs a backend.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))
sys.path.insert(0, str(ROOT / "dev"))

import android_tools as at  # noqa: E402

# dev/fake-android-phone.py has hyphens in its name; load it by path.
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "fake_android_phone", ROOT / "dev" / "fake-android-phone.py"
)
fake_android_phone = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fake_android_phone)

ADB = str(ROOT / "dev" / "fake-adb-full.py")
PY = sys.executable
SERIAL = "0A1B2C3D"
BT_ADDR = "0C:52:34:9A:1B:2C"


def call(capsys, *argv):
    """One line of JSON out of the CLI entry point, never a traceback."""
    assert at.main(["android_tools.py", *[str(a) for a in argv]]) == 0
    lines = [line for line in capsys.readouterr().out.splitlines() if line.strip()]
    assert len(lines) == 1, lines
    assert "Traceback" not in lines[0]
    return json.loads(lines[0])


def sh(tmp_path, name, body):
    path = tmp_path / name
    path.write_text("#!/bin/sh\n" + body + "\n", encoding="utf-8")
    path.chmod(0o755)
    return str(path)


def phone(tmp_path, name="phone"):
    return fake_android_phone.build(tmp_path / name)


def adb_env(monkeypatch, tmp_path, tree=None):
    tree = tree or phone(tmp_path)
    monkeypatch.setenv("SHANI_ADB", PY + " " + ADB)
    monkeypatch.setenv("SHANI_FAKE_PHONE_DIR", str(tree))
    monkeypatch.setenv("SHANI_ADB_LOG", str(tmp_path / "adb.log"))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    return tree


def no_backends(monkeypatch, tmp_path):
    monkeypatch.setattr(at.shutil, "which", lambda name: None)
    for var in (
        "SHANI_ADB",
        "SHANI_ADB_LOG",
        "SHANI_FAKE_PHONE_DIR",
        "SHANI_BTCTL",
        "SHANI_BTCTL_LOG",
        "SHANI_OBEX",
        "SHANI_DBUS",
        "SHANI_BT_AGENT",
        "SHANI_BACKUP_CANCEL",
    ):
        monkeypatch.delenv(var, raising=False)
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))


def bt_script(tmp_path, name="bt.sh", paired=True, connected=True, discoverable=True):
    """A bluetoothctl stand-in: paired phone, its info, optional discoverability."""
    rows = 'printf "Device %s Pixel 7\\n" "' + BT_ADDR + '"' if paired else ":"
    conn = 'printf "\\tConnected: yes\\n"' if connected else ":"
    disc = "yes" if discoverable else "no"
    return sh(
        tmp_path,
        name,
        """
case "$1" in
  paired-devices|devices) %s ;;
  scan|power|agent|default-agent) : ;;
  pair) echo "Pairing successful" ;;
  connect) echo "Connection successful" ;;
  remove) printf "forget %%s\\n" "$2" >> "$SHANI_BTCTL_LOG" ;;
  info|show)
    printf "\\tName: Pixel 7\\n\\tPaired: yes\\n"
    %s
    printf "\\tDiscoverable: %s\\n"
    ;;
esac
"""
        % (rows, conn, disc),
    )


class FakeSettings:
    def __init__(self, data=None):
        self.data = dict(data or {})
        self.writes = []

    def get_bool(self, key, default=False):
        return bool(self.data.get(key, default))

    def set_bool(self, key, value):
        self.data[key] = bool(value)
        self.writes.append((key, bool(value)))


# --- state --------------------------------------------------------------------


def test_state_reads_the_adb_phone(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    got = call(capsys, "state")
    assert got["ok"] is True and got["error"] == ""
    assert (got["paired"], got["serial"], got["via"]) == (True, SERIAL, "adb")
    assert got["name"] == "Pixel 7" and got["battery"] == "76%, charging"


def test_state_falls_back_to_bluetooth(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    monkeypatch.setenv("SHANI_BTCTL", bt_script(tmp_path))
    got = call(capsys, "state")
    assert got["ok"] is True and got["paired"] is True
    assert got["via"] == "bluetooth" and got["serial"] == BT_ADDR
    assert got["name"] == "Pixel 7"


def test_state_without_any_backend(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, "state")
    assert got["ok"] is True and got["paired"] is False and got["via"] == ""
    assert got["serial"] == "" and got["battery"] == ""


# --- backup -------------------------------------------------------------------


def test_backup_copies_media_contacts_texts_calls(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    folder = tmp_path / "backup"
    got = call(capsys, "backup", str(folder), "all")
    assert got["ok"] is True and got["error"] == ""
    names = {row["name"] for row in got["copied"]}
    assert {"IMG_0001.jpg", "clip.mp4", "report.pdf", "notes.txt"} <= names
    assert all(set(row) == {"name", "size", "when"} for row in got["copied"])
    assert (got["contacts"], got["messages"], got["calls"]) == (3, 3, 3)
    assert (folder / "DCIM" / "Camera" / "IMG_0001.jpg").is_file()
    assert (folder / "Download" / "report.pdf").is_file()
    assert (folder / "contacts.vcf").read_text().count("BEGIN:VCARD") == 3
    assert len((folder / "messages.txt").read_text().splitlines()) == 3
    assert (folder / at.MANIFEST).is_file()
    assert "Copied 9" in got["summary"]


def test_second_backup_copies_nothing(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    folder = tmp_path / "backup"
    first = call(capsys, "backup", str(folder))
    second = call(capsys, "backup", str(folder))
    assert len(first["copied"]) == 9
    assert second["copied"] == [] and second["skipped"] == 9
    assert (second["contacts"], second["messages"], second["calls"]) == (0, 0, 0)


@pytest.mark.parametrize(
    "category,expected",
    [
        ("photos", {"IMG_0001.jpg", "clip.mp4"}),
        ("downloads", {"report.pdf", "song.mp3"}),
        ("documents", {"notes.txt", "todo.txt"}),
    ],
)
def test_backup_categories(tmp_path, monkeypatch, capsys, category, expected):
    adb_env(monkeypatch, tmp_path)
    got = call(capsys, "backup", str(tmp_path / category), category)
    assert got["ok"] is True
    assert expected <= {row["name"] for row in got["copied"]}
    assert (got["contacts"], got["messages"]) == (0, 0)


def test_backup_contacts_only_and_messages_only(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    only_contacts = call(capsys, "backup", str(tmp_path / "c"), "contacts")
    assert only_contacts["copied"] == [] and only_contacts["contacts"] == 3
    only_messages = call(capsys, "backup", str(tmp_path / "m"), "messages")
    assert only_messages["copied"] == [] and only_messages["messages"] == 3
    assert only_messages["calls"] == 3


def test_backup_cancellation(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    stop = tmp_path / "stop"
    wrapper = sh(
        tmp_path,
        "wrap.sh",
        """
for arg in "$@"; do
    [ "$arg" = pull ] && { : > "$CANCEL_FILE"; break; }
done
exec %s %s "$@"
"""
        % (PY, ADB),
    )
    monkeypatch.setenv("SHANI_ADB", wrapper)
    monkeypatch.setenv("CANCEL_FILE", str(stop))
    monkeypatch.setenv("SHANI_BACKUP_CANCEL", str(stop))
    got = call(capsys, "backup", str(tmp_path / "backup"))
    assert got["ok"] is True and got["cancelled"] is True
    assert len(got["copied"]) == 1
    assert (
        len(json.loads((tmp_path / "backup" / at.MANIFEST).read_text())["files"]) == 1
    )


def test_contacts_refusal_is_an_honest_error(tmp_path, monkeypatch, capsys):
    tree = adb_env(monkeypatch, tmp_path)
    wrapper = sh(
        tmp_path,
        "refuse.sh",
        """
case " $* " in
  *" content query "*) echo "Error: permission denied" >&2; exit 1 ;;
esac
exec %s %s "$@"
"""
        % (PY, ADB),
    )
    monkeypatch.setenv("SHANI_ADB", wrapper)
    monkeypatch.setenv("SHANI_FAKE_PHONE_DIR", str(tree))
    monkeypatch.setattr(at, "_module", lambda name: None)
    got = call(capsys, "contacts", "list")
    assert got["ok"] is False and "permission denied" in got["error"]
    assert got["contacts"] == [] and "Traceback" not in got["error"]
    backup = call(capsys, "backup", str(tmp_path / "b"), "contacts")
    assert backup["ok"] is False and "permission denied" in backup["error"]


def test_backup_bad_folder_and_bad_category(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    assert call(capsys, "backup")["ok"] is False
    assert call(capsys, "backup", str(tmp_path / "b"), "nonsense")["ok"] is False


# --- import photos ------------------------------------------------------------


def test_import_photos_dates_and_twice_runs_nothing(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    dest = tmp_path / "photos"
    first = call(capsys, "import-photos", str(dest))
    assert first["ok"] is True and len(first["copied"]) == 5
    assert (dest / "Pixel-7" / "2026" / "01" / "IMG_0001.jpg").is_file()
    assert (dest / "Pixel-7" / "2026" / "02" / "IMG_0002.jpg").is_file()
    second = call(capsys, "import-photos", str(dest))
    assert second["copied"] == [] and "No new photos" in second["note"]


def test_import_photos_cancellation(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    stop = tmp_path / "stop"
    wrapper = sh(
        tmp_path,
        "wrap.sh",
        """
for arg in "$@"; do
    [ "$arg" = pull ] && { : > "$CANCEL_FILE"; break; }
done
exec %s %s "$@"
"""
        % (PY, ADB),
    )
    monkeypatch.setenv("SHANI_ADB", wrapper)
    monkeypatch.setenv("CANCEL_FILE", str(stop))
    monkeypatch.setenv("SHANI_BACKUP_CANCEL", str(stop))
    got = call(capsys, "import-photos", str(tmp_path / "photos"))
    assert got["ok"] is True and len(got["copied"]) == 1
    assert "Stopped at your request" in got["note"]


# --- cancel --------------------------------------------------------------------


def test_cancel_writes_stop_file_and_works_without_backend(
    tmp_path, monkeypatch, capsys
):
    no_backends(monkeypatch, tmp_path)
    stop = tmp_path / "stop"
    monkeypatch.setenv("SHANI_BACKUP_CANCEL", str(stop))
    got = call(capsys, "cancel")
    assert got["ok"] is True and got["cancelled"] is True and stop.is_file()
    monkeypatch.delenv("SHANI_BACKUP_CANCEL", raising=False)
    assert call(capsys, "cancel")["ok"] is False


def test_new_backup_clears_a_stale_stop_file(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    stop = tmp_path / "stop"
    stop.write_text("old\n")
    monkeypatch.setenv("SHANI_BACKUP_CANCEL", str(stop))
    got = call(capsys, "backup", str(tmp_path / "b"), "photos")
    assert got["cancelled"] is False and len(got["copied"]) == 5


# --- auto import --------------------------------------------------------------


def test_auto_import_on_off_and_once_per_connection(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    settings = FakeSettings()
    monkeypatch.setattr(at, "_settings", lambda: settings)
    assert call(capsys, "auto-import", "state")["on"] is False
    assert call(capsys, "auto-import", "on")["on"] is True
    assert settings.writes[-1] == (at.AUTO_KEY, True)
    assert call(capsys, "auto-import", "state")["on"] is True
    assert call(capsys, "auto-import", "check", "SERIAL-1")["run"] is True
    assert call(capsys, "auto-import", "check", "SERIAL-1")["run"] is False
    assert call(capsys, "auto-import", "check", "SERIAL-2")["run"] is True
    assert call(capsys, "auto-import", "off")["on"] is False
    assert call(capsys, "auto-import", "check", "SERIAL-3")["run"] is False
    assert call(capsys, "auto-import", "dance")["ok"] is False


# --- restore, contacts send, copy ---------------------------------------------


def test_restore_push_and_vcf_intent(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    folder = tmp_path / "restore"
    folder.mkdir()
    (folder / "notes.txt").write_text("back to the phone\n")
    (folder / "contacts.vcf").write_text("BEGIN:VCARD\nEND:VCARD\n")
    got = call(capsys, "restore", str(folder))
    assert got["ok"] is True and "notes.txt" in got["pushed"]
    assert got["contacts"] is True and "contacts app" in got["note"]
    log = (tmp_path / "adb.log").read_text()
    assert (
        "push" in log
        and "text/vcard" in log
        and "file:///sdcard/Download/contacts.vcf" in log
    )


def test_restore_media_recursive_and_single_file(tmp_path, monkeypatch, capsys):
    tree = adb_env(monkeypatch, tmp_path)
    folder = tmp_path / "media"
    call(capsys, "backup", str(folder), "all")
    got = call(capsys, "restore", str(folder))
    assert got["ok"] is True and "DCIM/Camera/IMG_0001.jpg" in got["pushed"]
    assert "Download/report.pdf" in got["pushed"]
    assert "file(s)" in got["note"]
    assert (tree / "sdcard" / "DCIM" / "Camera" / "IMG_0001.jpg").is_file()
    one = call(capsys, "restore", str(folder), "file", "Download/report.pdf")
    assert one["ok"] is True and one["pushed"] == ["Download/report.pdf"]
    assert "report.pdf" in one["note"]
    missing = call(capsys, "restore", str(folder), "file", "gone.txt")
    assert missing["ok"] is False


def test_restore_vcf_mode_only(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    folder = tmp_path / "backup"
    call(capsys, "backup", str(folder), "contacts")
    got = call(capsys, "restore", str(folder), "vcf")
    assert got["ok"] is True and got["contacts"] is True
    assert got["pushed"] == ["Download/contacts.vcf"]
    assert "text/vcard" in (tmp_path / "adb.log").read_text()


def test_copy_bare_folder_name(tmp_path, monkeypatch, capsys):
    tree = adb_env(monkeypatch, tmp_path)
    source = tmp_path / "song.mp3"
    source.write_bytes(b"audio")
    got = call(capsys, "copy", str(source), "Music")
    assert got["ok"] is True and got["via"] == "adb"
    assert (tree / "sdcard" / "Music" / "song.mp3").is_file()
    assert "/sdcard/Music/song.mp3" in (tmp_path / "adb.log").read_text()


def test_contacts_send_vcf(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    vcf = tmp_path / "friends.vcf"
    vcf.write_text("BEGIN:VCARD\nFN:Friend\nEND:VCARD\n")
    got = call(capsys, "contacts", "send", str(vcf))
    assert got["ok"] is True and got["sent"] is True
    assert "file:///sdcard/Download/friends.vcf" in (tmp_path / "adb.log").read_text()
    assert call(capsys, "contacts", "send", str(tmp_path / "gone.vcf"))["ok"] is False
    assert call(capsys, "contacts", "dance")["ok"] is False


def test_copy_via_adb(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    source = tmp_path / "song.mp3"
    source.write_bytes(b"audio")
    got = call(capsys, "copy", str(source), "/sdcard/Music")
    assert got["ok"] is True and got["sent"] is True and got["via"] == "adb"
    assert "push" in (tmp_path / "adb.log").read_text()


def test_copy_falls_back_to_obex(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    monkeypatch.setenv("SHANI_BTCTL", bt_script(tmp_path))
    obex = sh(tmp_path, "obex.sh", 'echo "sent"')
    monkeypatch.setenv("SHANI_OBEX", obex)
    source = tmp_path / "pic.jpg"
    source.write_bytes(b"image")
    got = call(capsys, "copy", str(source), "/sdcard/Download")
    assert got["ok"] is True and got["sent"] is True and got["via"] == "bluetooth"


# --- install ------------------------------------------------------------------


def test_install_result_and_failure(tmp_path, monkeypatch, capsys):
    tree = adb_env(monkeypatch, tmp_path)
    apk = tmp_path / "app.apk"
    apk.write_bytes(b"apk")
    got = call(capsys, "install", str(apk))
    assert got["ok"] is True and got["result"] == "Success"
    (tree / "refuse-install").write_text("no\n")
    refused = call(capsys, "install", str(apk))
    assert refused["ok"] is False and "INSTALL_FAILED" in refused["result"]
    assert call(capsys, "install", str(tmp_path / "gone.apk"))["ok"] is False


# --- tethering ----------------------------------------------------------------


def test_tether_usb_path_and_plain_help(tmp_path, monkeypatch, capsys):
    tree = adb_env(monkeypatch, tmp_path)
    on = call(capsys, "tether", "usb")
    assert on["ok"] is True and on["on"] is True and "internet" in on["note"]
    (tree / "usb-tether-off").write_text("no\n")
    helped = call(capsys, "tether", "usb")
    assert helped["on"] is False and "Settings" in helped["note"]
    assert "USB tethering" in helped["note"]


def test_tether_bt_and_state_paths(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    monkeypatch.setenv("SHANI_BTCTL", bt_script(tmp_path))
    monkeypatch.setenv("SHANI_DBUS", sh(tmp_path, "dbus.sh", 'echo "<true>"'))
    got = call(capsys, "tether", "bt")
    assert got["ok"] is True and got["on"] is True
    assert call(capsys, "tether", "state")["on"] is True
    assert call(capsys, "tether", "dance")["ok"] is False


def test_tether_without_a_phone_says_what_to_tap(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, "tether", "usb")
    assert got["ok"] is True and got["on"] is False and "USB tethering" in got["note"]
    bt = call(capsys, "tether", "bt")
    assert bt["ok"] is True and "Pair the phone" in bt["note"]


# --- calendar -----------------------------------------------------------------


def test_calendar_is_one_short_note(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, "calendar")
    assert got["ok"] is True and "account" in got["note"]
    assert "Calendar > Accounts" in got["note"] and "no direct sync" in got["note"]


# --- pairing ------------------------------------------------------------------


def test_pair_bluetooth(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    log = tmp_path / "bt.log"
    monkeypatch.setenv("SHANI_BTCTL_LOG", str(log))
    monkeypatch.setenv("SHANI_BTCTL", bt_script(tmp_path))
    got = call(capsys, "pair", "bluetooth", BT_ADDR)
    assert got["ok"] is True and got["paired"] is True
    assert got["address"] == BT_ADDR and got["name"] == "Pixel 7"
    assert call(capsys, "pair", "bluetooth", "nonsense")["ok"] is False
    assert call(capsys, "pair", "carrier-pigeon")["ok"] is False


def test_pair_wifi_adb(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    got = call(capsys, "pair", "wifi", "192.168.1.20:37099", "123456")
    assert got["ok"] is True and got["paired"] is True
    assert got["address"] == "192.168.1.20:37099"
    assert "pair" in (tmp_path / "adb.log").read_text()
    assert call(capsys, "pair", "wifi", "bad-address", "123456")["ok"] is False
    assert call(capsys, "pair", "wifi", "192.168.1.20:37099", "abc")["ok"] is False


def test_forget_bluetooth_and_wifi(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    log = tmp_path / "bt.log"
    monkeypatch.setenv("SHANI_BTCTL_LOG", str(log))
    monkeypatch.setenv("SHANI_BTCTL", bt_script(tmp_path))
    got = call(capsys, "forget")
    assert got["ok"] is True and "forget " + BT_ADDR in log.read_text()
    assert got["paired"] is True  # the stand-in still lists it; honest answer


def test_find_bluetooth_and_adb(tmp_path, monkeypatch, capsys):
    adb_env(monkeypatch, tmp_path)
    monkeypatch.setenv("SHANI_BTCTL", bt_script(tmp_path))
    got = call(capsys, "find")
    assert got["ok"] is True and len(got["devices"]) == 2
    kinds = {row["kind"] for row in got["devices"]}
    assert {"bluetooth", "adb"} <= kinds
    assert "Found 2" in got["note"]


def test_find_without_backends(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, "find")
    assert got["ok"] is True and got["devices"] == [] and "No phones" in got["note"]


def test_findable_agent_and_switch(tmp_path, monkeypatch, capsys):
    no_backends(monkeypatch, tmp_path)
    agent = sh(tmp_path, "agent.sh", "echo '{\"on\":true}'")
    monkeypatch.setenv("SHANI_BT_AGENT", agent)
    assert call(capsys, "findable", "on")["on"] is True
    assert call(capsys, "findable", "state")["on"] is True
    monkeypatch.delenv("SHANI_BT_AGENT")
    monkeypatch.setenv("SHANI_BTCTL", bt_script(tmp_path, discoverable=False))
    assert call(capsys, "findable", "state")["on"] is False
    assert call(capsys, "findable", "maybe")["ok"] is False


# --- the real command line and no-backend shape --------------------------------


def test_cli_prints_exactly_one_json_line(tmp_path, monkeypatch):
    adb_env(monkeypatch, tmp_path)
    env = dict(os.environ)
    proc = subprocess.run(
        [PY, str(ROOT / "bridge" / "android_tools.py"), "state"],
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    assert proc.returncode == 0 and proc.stderr == ""
    assert len(proc.stdout.strip().splitlines()) == 1
    assert json.loads(proc.stdout)["serial"] == SERIAL


@pytest.mark.parametrize(
    "argv",
    [
        ("state",),
        ("backup", "/tmp/backup-none"),
        ("restore", "/tmp/backup-none"),
        ("import-photos", "/tmp/photos-none"),
        ("auto-import", "state"),
        ("contacts", "list"),
        ("copy", "/tmp/none.mp3", "/sdcard/Download"),
        ("install", "/tmp/none.apk"),
        ("tether", "state"),
        ("calendar",),
        ("pair", "bluetooth", BT_ADDR),
        ("pair", "wifi", "1.2.3.4:5555", "123456"),
        ("forget",),
        ("find",),
        ("findable", "state"),
        ("cancel",),
        (),
        ("unknown",),
    ],
)
def test_every_command_answers_without_backends(tmp_path, monkeypatch, capsys, argv):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, *argv)
    assert isinstance(got, dict) and "ok" in got and "error" in got
    assert isinstance(got["ok"], bool) and isinstance(got["error"], str)
    assert "Traceback" not in got["error"]
