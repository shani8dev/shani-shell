"""bridge/devices.py: the Devices window's bridge over the vendored engines.

Every command is checked with a stand-in module, so no test needs adb, BlueZ,
an SDR or a landline. Stream state lives under a relocated XDG_STATE_HOME.
"""

import importlib.util
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


@pytest.fixture
def bridge(monkeypatch, tmp_path):
    spec = importlib.util.spec_from_file_location(
        "devices_under_test", ROOT / "bridge" / "devices.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    modules = {}
    monkeypatch.setattr(mod, "_module", lambda name: modules.get(name))
    return mod, modules, tmp_path


class Done:
    def __init__(self, out="", err="", rc=0):
        self.stdout, self.stderr, self.returncode = out, err, rc


# ---- android -----------------------------------------------------------------


class Android:
    def info(self, serial):
        return f"Pixel on {serial}"

    def apps(self, serial, query=""):
        return f"apps matching {query or 'all'}"

    def push(self, serial, source):
        return f"sent {Path(source).name}"

    def open_url(self, serial, url):
        return f"Opened {url}"

    def screenshot(self, serial, target=None):
        return "Saved the phone's screen"

    def record(self, serial, seconds=30):
        return f"Recorded {seconds}s"

    def list_devices(self):
        return "Connected: one phone"

    def _shell(self, serial, *cmd):
        return " ".join(cmd)


def test_android_passes_serial_and_argument_to_the_engine(bridge):
    mod, modules, _ = bridge
    modules["phone.android"] = Android()
    got = mod.cmd_android("info", "abc")
    assert (got["ok"], got["error"], got["out"]) == (True, "", "Pixel on abc")
    assert isinstance(got["devices"], list) and got["info"]["text"] == "Pixel on abc"
    assert mod.cmd_android("app", "abc", "cam")["out"] == "apps matching cam"
    assert mod.cmd_android("file", "abc", "/tmp/a.txt")["out"] == "sent a.txt"
    assert (
        mod.cmd_android("link", "abc", "https://example.org")["out"]
        == "Opened https://example.org"
    )
    assert mod.cmd_android("battery", "abc")["out"] == "dumpsys battery"
    assert mod.cmd_android("storage", "abc")["out"] == "df -h /sdcard"
    assert mod.cmd_android("screenshot", "abc")["out"] == "Saved the phone's screen"
    assert mod.cmd_android("record", "abc", "12")["out"] == "Recorded 12s"
    assert mod.cmd_android("link", "abc")["out"] == "Connected: one phone"


def test_battery_and_storage_come_back_as_values(bridge):
    mod, modules, _ = bridge

    class Facts(Android):
        def _shell(self, serial, *cmd):
            if cmd == ("dumpsys", "battery"):
                return (
                    "Current Battery Service state:\n  AC powered: false\n"
                    "  USB powered: true\n  level: 76\n  scale: 100\n"
                    "  voltage: 3900000\n  temperature: 250"
                )
            return (
                "Filesystem Size Used Avail Use% Mounted on\n"
                "/dev/block/mmcblk0p1 116G 61G 50G 55% /sdcard"
            )

    modules["phone.android"] = Facts()
    battery = mod.cmd_android("battery", "abc")
    assert battery["battery"]["level"] == 76 and battery["battery"]["charging"] is True
    assert "level: 76" in battery["out"]
    storage = mod.cmd_android("storage", "abc")
    assert storage["storage"]["free"] == "50G" and "50G" in storage["out"]


def test_screenshot_uses_the_adb_binary_output_keyword(bridge, monkeypatch):
    mod, modules, _ = bridge

    class Shooter(Android):
        def _adb(self, *args, **kwargs):
            raise AssertionError("the plain adb must not be used with SHANI_ADB set")

        def screenshot(self, serial, target=None):
            proc = self._adb(
                ["exec-out", "screencap", "-p"], serial, binary_output=True
            )
            return "png" if proc.stdout else "no png"

    modules["phone.android"] = Shooter()
    monkeypatch.setenv("SHANI_ADB", "/fake/adb")
    seen = []
    monkeypatch.setattr(
        mod.subprocess,
        "run",
        lambda argv, **kw: seen.append((argv, kw)) or Done(out=b"\x89PNG"),
    )
    got = mod.cmd_android("screenshot", "abc")
    assert got["ok"] is True and got["out"] == "png"
    assert seen[0][0][:3] == ["/fake/adb", "-s", "abc"]
    assert seen[0][1]["text"] is False  # raw PNG, not text


def test_an_android_failure_is_an_answer(bridge):
    mod, modules, _ = bridge

    class Broken(Android):
        def info(self, serial):
            return "adb (android-tools) is not installed."

    modules["phone.android"] = Broken()
    got = mod.cmd_android("info", "abc")
    assert (got["ok"], got["error"], got["out"]) == (
        False,
        "adb (android-tools) is not installed.",
        "",
    )
    assert got["devices"] == [] and "not installed" in got["info"]["text"]
    assert mod.cmd_android("nonsense")["ok"] is False


def test_android_honours_shani_adb(bridge, monkeypatch):
    mod, modules, _ = bridge

    class RealAdb(Android):
        def _adb(self, *args, **kwargs):
            raise AssertionError("the plain adb must not be used with SHANI_ADB set")

        def info(self, serial):
            return self._adb(["shell", "dumpsys", "battery"], serial).stdout

    android = RealAdb()
    modules["phone.android"] = android
    monkeypatch.setenv("SHANI_ADB", "/fake/adb")
    seen = []
    monkeypatch.setattr(
        mod.subprocess, "run", lambda argv, **kw: seen.append(argv) or Done(out="80%")
    )
    got = mod.cmd_android("info", "abc")
    assert (got["ok"], got["error"], got["out"]) == (True, "", "80%")
    assert seen[0][:3] == ["/fake/adb", "-s", "abc"]
    assert android._adb.__func__ is RealAdb._adb  # the override was put back


def test_android_without_a_backend_answers(bridge):
    mod, _modules, _ = bridge
    got = mod.cmd_android("info")
    assert (got["ok"], got["error"], got["out"]) == (False, mod.NOT_INSTALLED, "")
    assert got["devices"] == [] and got["info"]["text"] == ""


def test_android_says_when_adb_is_missing(bridge, monkeypatch):
    mod, modules, _ = bridge
    monkeypatch.delenv("SHANI_ADB", raising=False)

    class Missing(Android):
        NO_ADB = "adb (android-tools) is not installed."

        @staticmethod
        def available():
            return False

    modules["phone.android"] = Missing()
    got = mod.cmd_android("info", "abc")
    assert (got["ok"], got["error"], got["out"]) == (
        False,
        "adb (android-tools) is not installed.",
        "",
    )
    assert got["devices"] == []


# ---- pairing -----------------------------------------------------------------


def test_connect_android_uses_adb_pair(bridge, monkeypatch):
    mod, modules, _ = bridge
    calls = []

    class AdbPair:
        def pair(self, address, code):
            calls.append(("pair", address, code))
            return True, "paired"

        def connect(self, address):
            calls.append(("connect", address))
            return True, "connected"

    modules["phone.adb_pair"] = AdbPair()
    assert mod.cmd_connect("android", "192.168.1.2:37099", "123456") == {
        "ok": True,
        "error": "",
    }
    assert mod.cmd_connect("android", "192.168.1.2:5555")["ok"] is True
    assert calls == [
        ("pair", "192.168.1.2:37099", "123456"),
        ("connect", "192.168.1.2:5555"),
    ]


def test_connect_android_reports_a_bad_code(bridge):
    mod, modules, _ = bridge

    class AdbPair:
        def pair(self, address, code):
            return False, "the code did not match"

    modules["phone.adb_pair"] = AdbPair()
    got = mod.cmd_connect("android", "192.168.1.2:37099", "000000")
    assert got["ok"] is False and "code did not match" in got["error"]


def test_connect_phone_uses_android_debugging(bridge, monkeypatch):
    """Pairing a phone uses Bluetooth or adb, never an app on the handset."""
    mod, modules, _ = bridge

    class AdbPair:
        def connect(self, address):
            assert address == "192.168.1.2:37099"
            return True, ""

        def pair(self, address, code):
            return True, ""

    modules["phone.adb_pair"] = AdbPair()
    got = mod.cmd_connect("phone", "192.168.1.2:37099")
    assert got["ok"] is True and got["error"] == ""


def test_connect_bluetooth_uses_gdbus_on_the_device(bridge, monkeypatch):
    mod, _modules, _ = bridge
    monkeypatch.setenv("SHANI_DBUS", "/fake/gdbus")
    seen = []
    monkeypatch.setattr(
        mod.subprocess, "run", lambda argv, **kw: seen.append(argv) or Done()
    )
    assert mod.cmd_connect("bluetooth", "AA:BB:CC:DD:EE:FF")["ok"] is True
    argv = seen[0]
    assert argv[:2] == ["/fake/gdbus", "call"]
    assert "--system" in argv and "--dest" in argv
    assert "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF" in argv
    assert "org.bluez.Device1.Pair" in argv


def test_connect_says_when_a_helper_failed_or_is_missing(bridge, monkeypatch):
    mod, _modules, _ = bridge
    monkeypatch.setenv("SHANI_DBUS", "gdbus")
    monkeypatch.setattr(
        mod.subprocess, "run", lambda *a, **kw: Done(err="Permission denied", rc=1)
    )
    got = mod.cmd_connect("bluetooth", "AA:BB:CC:DD:EE:FF")
    assert got["ok"] is False and "Permission denied" in got["error"]
    monkeypatch.setattr(
        mod.subprocess,
        "run",
        lambda *a, **kw: (_ for _ in ()).throw(FileNotFoundError()),
    )
    assert "not installed" in mod.cmd_connect("phone", "1234")["error"]
    assert mod.cmd_connect("unknown")["ok"] is False


# ---- screen and radio streams -------------------------------------------------


def test_screen_start_state_and_stop(bridge, monkeypatch):
    mod, modules, tmp_path = bridge
    modules["phone.screen_stream"] = type("Screen", (), {"PORT": 8090})
    seen = []

    class Popen:
        def __init__(self, argv, **kwargs):
            self.pid = 4242
            seen.append((argv, kwargs))

    monkeypatch.setattr(mod.subprocess, "Popen", Popen)
    monkeypatch.setattr(mod, "_alive", lambda pid: True)
    assert mod.cmd_screen("start", "wifi", "1", "0") == {
        "ok": True,
        "error": "",
        "state": "on",
        "mode": "screen:wifi",
        "touch": True,
        "type": False,
    }
    assert seen[0][0][1:4] == ["-m", "phone.screen_stream", "--transport"]
    assert seen[0][0][4] == "wifi" and seen[0][0][-1] == "--touch"
    assert seen[0][1]["start_new_session"] is True
    row = json.loads((tmp_path / "shani-shell" / "device-screen.json").read_text())
    assert row["pid"] == 4242 and row["mode"] == "screen:wifi"
    assert row["touch"] is True and row["type"] is False
    state = mod.cmd_screen("state")
    assert state["mode"] == "screen:wifi" and state["touch"] is True
    monkeypatch.setattr(mod, "_alive", lambda pid: False)
    assert mod.cmd_screen("state")["state"] == "off"

    mod.cmd_screen("start", "usb")
    killed = []
    monkeypatch.setattr(mod.os, "kill", lambda pid, sig: killed.append((pid, sig)))
    assert mod.cmd_screen("stop")["state"] == "off"
    assert killed == [(4242, mod.signal.SIGTERM)]
    assert mod.cmd_screen("state")["state"] == "off"


def test_screen_honours_the_env_mode_and_rejects_bad_modes(bridge, monkeypatch):
    mod, modules, _ = bridge
    modules["phone.screen_stream"] = object()
    monkeypatch.setenv("SHANI_SCREEN_MODE", "bluetooth")
    seen = []
    monkeypatch.setattr(
        mod.subprocess,
        "Popen",
        lambda argv, **kw: seen.append(argv) or type("P", (), {"pid": 1})(),
    )
    assert mod.cmd_screen("start")["mode"] == "screen:bluetooth"
    assert seen[0][-1] == "bluetooth"
    assert mod.cmd_screen("start", "satellite")["ok"] is False
    assert mod.cmd_screen("nonsense")["ok"] is False


def test_screen_combines_the_area_and_transport(bridge, monkeypatch):
    mod, modules, tmp_path = bridge
    modules["phone.screen_stream"] = object()
    seen = []
    monkeypatch.setattr(
        mod.subprocess,
        "Popen",
        lambda argv, **kw: seen.append(argv) or type("P", (), {"pid": 7})(),
    )
    got = mod.cmd_screen("start", "window:usb", "0", "1")
    assert (got["mode"], got["touch"], got["type"]) == ("window:usb", False, True)
    assert "--window" in seen[0] and "--touch" in seen[0]
    assert seen[0][4] == "usb"
    row = json.loads((tmp_path / "shani-shell" / "device-screen.json").read_text())
    assert row["area"] == "window" and row["transport"] == "usb"
    assert mod.cmd_screen("start", "screen")["mode"] == "screen:auto"
    assert "--window" not in seen[1]


def test_screen_main_takes_the_touch_and_type_arguments(bridge, monkeypatch, capsys):
    mod, modules, _ = bridge
    modules["phone.screen_stream"] = object()
    seen = []
    monkeypatch.setattr(
        mod.subprocess,
        "Popen",
        lambda argv, **kw: seen.append(argv) or type("P", (), {"pid": 8})(),
    )
    monkeypatch.setattr(
        mod.sys,
        "argv",
        ["devices.py", "screen", "start", "window:wifi", "1", "1"],
    )
    assert mod.main() == 0
    assert json.loads(capsys.readouterr().out)["mode"] == "window:wifi"
    assert seen[0][-2:] == ["--touch"] or "--touch" in seen[0]


def test_fm_start_state_and_stop(bridge, monkeypatch):
    mod, modules, tmp_path = bridge
    modules["phone.fm_radio"] = type(
        "Fm", (), {"_frequency": staticmethod(lambda args: (98.6e6, ""))}
    )
    seen = []

    class Popen:
        def __init__(self, argv, **kwargs):
            self.pid = 909
            seen.append(argv)

    monkeypatch.setattr(mod.subprocess, "Popen", Popen)
    monkeypatch.setattr(mod, "_alive", lambda pid: True)
    assert mod.cmd_fm("tune", "98.6") == {
        "ok": True,
        "error": "",
        "state": "on",
        "frequency": "98.6",
    }
    assert seen[0][1] == "-c" and "fm_radio.run" in seen[0][2]
    assert seen[0][4] == "98.6"
    assert mod.cmd_fm("state") == {
        "ok": True,
        "error": "",
        "state": "on",
        "frequency": "98.6",
    }
    monkeypatch.setattr(mod, "_alive", lambda pid: False)
    assert mod.cmd_fm("state")["state"] == "off"
    mod.cmd_fm("start", "99.1")
    killed = []
    monkeypatch.setattr(mod.os, "kill", lambda pid, sig: killed.append(pid))
    assert mod.cmd_fm("stop")["state"] == "off"
    assert killed == [909]


def test_fm_needs_a_station(bridge, monkeypatch):
    mod, modules, _ = bridge
    modules["phone.fm_radio"] = type(
        "Fm", (), {"_frequency": staticmethod(lambda args: (0, "Which frequency?"))}
    )
    assert mod.cmd_fm("tune", "")["ok"] is False
    assert "frequency" in mod.cmd_fm("start")["error"]


# ---- NFC and infrared ---------------------------------------------------------


def test_fm_uses_a_stand_in_when_shani_fm_is_set(bridge, monkeypatch, tmp_path):
    mod, _, _ = bridge
    fake = tmp_path / "fake-fm.py"
    fake.write_text(
        "#!/usr/bin/env python3\n"
        "import json,sys\n"
        "print(json.dumps({'state': 'running' if sys.argv[1] in "
        "('start', 'tune', 'state') else 'off', 'frequency': '98.6'}))\n",
        encoding="utf-8",
    )
    fake.chmod(0o755)
    monkeypatch.setenv("SHANI_FM", str(fake))
    assert mod.cmd_fm("start", "98.6")["state"] == "on"
    assert mod.cmd_fm("state") == {
        "ok": True,
        "error": "",
        "state": "on",
        "frequency": "98.6",
        "out": '{"state": "running", "frequency": "98.6"}',
    }
    assert mod.cmd_fm("stop")["state"] == "off"


def test_nfc_read_returns_the_tag_text(bridge):
    mod, modules, _ = bridge

    class Nfc:
        def _run(self, arguments):
            return (
                "The tag says:\nhello"
                if arguments["action"] == "read"
                else "Wrote a link to the sticker: https://example.org"
            )

    modules["phone.nfc"] = Nfc()
    assert mod.cmd_nfc("read") == {"ok": True, "error": "", "text": "hello"}
    got = mod.cmd_nfc("write", "https://example.org")
    assert got["ok"] is True and "Wrote a link" in got["text"]


def test_nfc_says_when_no_tag_answered(bridge):
    mod, modules, _ = bridge

    class Nfc:
        def _run(self, arguments):
            return "No tag was read: nfc-list is not installed"

    modules["phone.nfc"] = Nfc()
    got = mod.cmd_nfc("read")
    assert got["ok"] is False and "No tag" in got["error"] and got["text"] == ""
    assert mod.cmd_nfc("write")["ok"] is False


def test_nfc_honours_the_shani_nfc_stand_in(bridge, monkeypatch, tmp_path):
    mod, modules, _ = bridge
    modules["phone.nfc"] = object()  # the stand-in, not the vendored engine
    monkeypatch.setenv("SHANI_NFC", str(ROOT / "dev" / "fake-nfc.py"))
    monkeypatch.setenv("SHANI_NFC_LOG", str(tmp_path / "nfc-calls"))
    monkeypatch.setenv("SHANI_NFC_STATE", str(tmp_path / "tag.txt"))
    got = mod.cmd_nfc("read")
    assert got["ok"] is True and "Asha Patil" in got["text"]
    assert (tmp_path / "nfc-calls").read_text().strip() == "read"
    written = mod.cmd_nfc("write", "new tag")
    assert written["ok"] is True and "Written" in written["text"]
    assert "new tag" in mod.cmd_nfc("read")["text"]


def test_ir_honours_the_shani_ir_stand_in(bridge, monkeypatch, tmp_path):
    mod, modules, _ = bridge
    modules["phone.ir_remote"] = object()
    monkeypatch.setenv("SHANI_IR", str(ROOT / "dev" / "fake-ir.py"))
    monkeypatch.setenv("SHANI_IR_LOG", str(tmp_path / "ir-calls"))
    got = mod.cmd_ir("list")
    assert got == {"ok": True, "error": "", "codes": ["tv"], "out": "tv"}
    assert mod.cmd_ir("list", "tv")["codes"] == ["power", "on", "volume-up"]
    sent = mod.cmd_ir("send", "tv:power")
    assert sent["ok"] is True and "Sent power of tv" in sent["out"]
    assert "SEND_ONCE" not in (tmp_path / "ir-calls").read_text()


def test_ir_lists_remotes_buttons_and_sends_a_code(bridge):
    mod, modules, _ = bridge
    sent = []

    class Ir:
        def remotes(self):
            return ["tv", "fan"], ""

        def keys(self, remote):
            return (
                (["power", "volume"], "") if remote == "tv" else ([], "no such remote")
            )

        def send_key(self, remote, key):
            sent.append((remote, key))
            return f"Sent {key} of {remote}."

    modules["phone.ir_remote"] = Ir()
    assert mod.cmd_ir("list") == {"ok": True, "error": "", "codes": ["tv", "fan"]}
    assert mod.cmd_ir("list", "tv")["codes"] == ["power", "volume"]
    assert mod.cmd_ir("list", "none")["ok"] is False
    assert mod.cmd_ir("send", "tv:power")["ok"] is True
    assert mod.cmd_ir("send", "fan")["ok"] is False
    assert sent == [("tv", "power")]


# ---- lines, SIP accounts and the landline ------------------------------------


def test_lines_offer_setup_when_the_landline_is_not_set_up(bridge):
    mod, modules, _ = bridge
    modules["phone.lines"] = type(
        "Lines",
        (),
        {
            "available": staticmethod(
                lambda: [
                    {"id": "phone", "name": "Phone", "ready": True},
                    {"id": "sip-abc", "name": "Ada", "ready": False},
                ]
            )
        },
    )
    modules["phone.landline"] = type(
        "Landline", (), {"is_set_up": staticmethod(lambda: False)}
    )
    got = mod.cmd_lines()
    assert got[0] == {"id": "phone", "name": "Phone", "ready": True, "kind": "phone"}
    assert got[1]["kind"] == "sip"
    assert got[-1] == {
        "id": "landline",
        "name": "Landline",
        "ready": False,
        "kind": "setup",
    }
    modules["phone.landline"] = type(
        "Landline", (), {"is_set_up": staticmethod(lambda: True)}
    )
    assert len(mod.cmd_lines()) == 2


def test_sip_list_never_shows_a_password(bridge):
    mod, modules, _ = bridge

    class Sip:
        def accounts(self):
            return [
                {
                    "id": "abc",
                    "name": "Ada",
                    "username": "ada",
                    "domain": "example.org",
                    "password": "secret",
                }
            ]

        def _public(self, row):
            return {k: v for k, v in row.items() if k != "password"}

    modules["phone.sip_accounts"] = Sip()
    got = mod.cmd_sip_list()
    assert got[0]["name"] == "Ada" and "password" not in got[0]


def test_sip_list_falls_back_to_the_public_view(bridge):
    mod, modules, _ = bridge

    class Sip:
        def _load(self):
            return [{"id": "abc", "password": "secret"}]

        def _public(self, row):
            return {k: v for k, v in row.items() if k != "password"}

    modules["phone.sip_accounts"] = Sip()
    assert mod.cmd_sip_list() == [{"id": "abc"}]


def test_sip_add_update_remove_answer_without_leaking_a_password(bridge):
    mod, modules, _ = bridge
    calls = []

    class Sip:
        def add_account(self, fields):
            calls.append(("add", fields))

        def update_account(self, ident, fields):
            calls.append(("update", ident, fields))

        def remove_account(self, ident):
            calls.append(("remove", ident))
            return ident == "abc"

    modules["phone.sip_accounts"] = Sip()
    assert mod.cmd_sip_add('{"username":"ada","password":"secret"}') == {
        "ok": True,
        "error": "",
    }
    assert mod.cmd_sip_update("abc", '{"name":"Ada"}')["ok"] is True
    assert mod.cmd_sip_remove("abc")["ok"] is True
    assert mod.cmd_sip_remove("nope")["ok"] is False
    assert calls[0] == ("add", {"username": "ada", "password": "secret"})
    assert "secret" in str(calls)  # it went in, never came back out in an answer
    assert mod.cmd_sip_add("not json")["ok"] is False


def test_landline_setup_finish_and_forget(bridge):
    mod, modules, _ = bridge
    state = {"set_up": False}

    class Landline:
        def is_set_up(self):
            return state["set_up"]

        def ready(self):
            return True

        def enabled(self):
            return True

        def status(self):
            return "Registered"

        def setup_start(self, host):
            return "code sent to ****4321"

        def setup_finish(self, code):
            state["set_up"] = True
            return "100123"

        def forget(self):
            state["set_up"] = False

    modules["phone.landline"] = Landline()
    assert mod.cmd_landline("state")["state"]["set_up"] is False
    assert (
        mod.cmd_landline("setup", "192.168.1.1")["state"]["sent_to"]
        == "code sent to ****4321"
    )
    assert mod.cmd_landline("finish", "123456")["state"]["number"] == "100123"
    full = mod.cmd_landline("state")
    assert full["ok"] is True and full["state"]["ready"] is True
    assert full["state"]["status"] == "Registered"
    assert mod.cmd_landline("forget")["state"]["set_up"] is False
    assert mod.cmd_landline("setup")["ok"] is False
    assert mod.cmd_landline("nonsense")["ok"] is False


# ---- no backends at all -------------------------------------------------------


def test_every_command_answers_with_no_backends(bridge):
    mod, _modules, _ = bridge
    answers = [
        mod.cmd_android("info"),
        mod.cmd_connect("android", "1.2.3.4:1234", "123456"),
        mod.cmd_screen("state"),
        mod.cmd_fm("state"),
        mod.cmd_nfc("read"),
        mod.cmd_ir("list"),
        mod.cmd_lines(),
        mod.cmd_sip_list(),
        mod.cmd_sip_add("{}"),
        mod.cmd_sip_update("1", "{}"),
        mod.cmd_sip_remove("1"),
        mod.cmd_landline("state"),
        mod.cmd_landline("setup", "host"),
        mod.cmd_landline("finish", "1234"),
        mod.cmd_landline("forget"),
    ]
    for answer in answers:
        json.dumps(answer)  # a bridge answer is always JSON, never a traceback


def test_the_main_entry_point_rejects_an_unknown_command(bridge, monkeypatch, capsys):
    mod, _, _ = bridge
    monkeypatch.setattr(mod.sys, "argv", ["devices.py", "nonsense"])
    assert mod.main() == 2
    assert "unknown command" in capsys.readouterr().out
