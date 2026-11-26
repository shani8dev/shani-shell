"""bridge/phone_tools.py: one JSON answer per command, even with no backends.

Every command is run through main() against a stand-in script written into
tmp_path (the way dev/fake-*.py override bridge helpers), and against a missing
backend. The phone engines are fakes here: no D-Bus, no Bluetooth, no real
settings file.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import phone_tools as pt  # noqa: E402


def call(capsys, *argv):
    """Run the CLI entry point; one line of JSON, no other chatter."""
    assert pt.main(["phone_tools.py", *[str(a) for a in argv]]) == 0
    lines = [line for line in capsys.readouterr().out.splitlines() if line.strip()]
    assert len(lines) == 1, lines
    assert "Traceback" not in lines[0]
    return json.loads(lines[0])


def stand_in(tmp_path, name, body):
    path = tmp_path / name
    path.write_text("#!/bin/sh\n" + body + "\n", encoding="utf-8")
    path.chmod(0o755)
    return path


def modules(monkeypatch, **named):
    """Only the named phone engines exist; every other one is absent."""
    monkeypatch.setattr(pt, "_module", lambda name: named.get(name))


def no_backends(monkeypatch, tmp_path):
    modules(monkeypatch)
    for var in (
        "SHANI_MUSIC",
        "SHANI_FILES_SEND",
        "SHANI_PHONE_REMOTE",
        "SHANI_PHONE_LINK",
        "SHANI_AUDIO",
        "SHANI_DBUS",
    ):
        monkeypatch.delenv(var, raising=False)
    monkeypatch.setenv("SHANI_FILES_DIR", str(tmp_path / "empty"))
    (tmp_path / "empty").mkdir()
    monkeypatch.setenv("SHANI_DBUS", str(tmp_path / "no-gdbus"))


class FakeSettings:
    def __init__(self, data=None):
        self.data = dict(data or {})
        self.writes = []

    def get_bool(self, key, default=False):
        return bool(self.data.get(key, default))

    def set_bool(self, key, value):
        self.data[key] = bool(value)
        self.writes.append((key, bool(value)))

    def all(self):
        return {key: self.get_bool(key, key in pt.DEFAULT_ON) for key in pt.SWITCH_KEYS}


class Device:
    def __init__(self, ident, name, paired=True, reachable=True):
        self.id, self.name = ident, name
        self.paired, self.reachable = paired, reachable


class FakePhone:
    def __init__(self, devices=()):
        self.list = list(devices)
        self.calls = []

    def devices(self):
        return list(self.list)

    def act(self, device, action, payload=""):
        self.calls.append((device.id, action, payload))
        return True, ""


class FakeLan:
    def __init__(self, paired=None, status=("not paired", "no phone yet"), found=()):
        self.paired = dict(paired or {})
        self.status = status
        self.found = list(found)
        self.forgot = False
        self.sent = None

    def paired_device(self):
        return dict(self.paired)

    def pairing_status(self):
        return self.status

    def forget_pairing(self):
        self.forgot = True

    def listen_once(self, timeout=3.0):
        return list(self.found)

    def send_file(self, host, path):
        self.sent = (host, path)
        return True, "file offered"


class FakeLanPhone:
    def __init__(self, pair_answer="Paired: with the phone."):
        self.pair_answer = pair_answer
        self.calls = []

    def remember(self, address):
        self.calls.append(("remember", address))

    def announce(self):
        self.calls.append(("announce",))
        return "Announced this computer."

    def pair(self, host):
        self.calls.append(("pair", host))
        return self.pair_answer


class FakeAudio:
    def __init__(self, gateways=(), where="phone", ok=True, path="/org/pipewire/gw1"):
        self.list = list(gateways)
        self.where = where
        self.ok = ok
        self.path = path
        self.set_calls = []

    def gateways(self):
        return list(self.list)

    def audio_route(self, gateway):
        return self.where, "active"

    def set_audio_route(self, gateway, where):
        self.set_calls.append((gateway, where))
        if self.ok:
            self.where = where
        return self.ok, "" if self.ok else "the phone refused"


# --- music ------------------------------------------------------------------


def test_music_stand_in_answers_every_action(tmp_path, monkeypatch, capsys):
    script = stand_in(
        tmp_path,
        "music.sh",
        """
case "$1" in
  status) echo '{"state":"Playing","title":"Song","artist":"Singer","player":"Desk","summary":"Playing Song"}' ;;
  *) echo '{"state":"Paused","title":"Next","artist":"Band","player":"Desk","summary":"Paused Next"}' ;;
esac
""",
    )
    monkeypatch.setenv("SHANI_MUSIC", str(script))
    got = call(capsys, "music", "status")
    assert got["ok"] is True and got["error"] == ""
    assert (got["state"], got["title"], got["artist"], got["player"]) == (
        "Playing",
        "Song",
        "Singer",
        "Desk",
    )
    assert got["summary"] == "Playing Song"
    for action in ("play", "pause", "toggle", "next", "previous"):
        assert call(capsys, "music", action)["title"] == "Next"


def test_music_stand_in_error_is_an_answer(tmp_path, monkeypatch, capsys):
    script = stand_in(tmp_path, "music.sh", 'echo \'{"error":"player is offline"}\'')
    monkeypatch.setenv("SHANI_MUSIC", str(script))
    got = call(capsys, "music", "play")
    assert got["ok"] is False and got["error"] == "player is offline"
    assert got["state"] == "" and got["summary"] == ""


def test_music_reads_mpris_and_controls_the_current_player(monkeypatch, capsys):
    calls = []
    mpris = SimpleNamespace(
        current=lambda: "org.mpris.MediaPlayer2.player",
        status=lambda player: "Playing",
        metadata=lambda player: {
            "xesam:title": "Song",
            "xesam:artist": ["Singer", "Other"],
        },
        identity=lambda player: "Music Desk",
        control=lambda action: (calls.append(action), "play: Song")[1],
    )
    modules(monkeypatch, **{"phone.mpris": mpris})
    got = call(capsys, "music", "status")
    assert got["ok"] is True
    assert (got["state"], got["title"], got["artist"], got["player"]) == (
        "Playing",
        "Song",
        "Singer",
        "Music Desk",
    )
    assert got["summary"] == "Playing Singer - Song"
    assert call(capsys, "music", "next")["ok"] is True
    assert calls == ["next"]


def test_music_mpris_refusal_is_an_error(monkeypatch, capsys):
    mpris = SimpleNamespace(
        current=lambda: "org.mpris.MediaPlayer2.player",
        status=lambda player: "Paused",
        metadata=lambda player: {},
        identity=lambda player: "Desk",
        control=lambda action: "The player did not take it: no track",
    )
    modules(monkeypatch, **{"phone.mpris": mpris})
    got = call(capsys, "music", "pause")
    assert got["ok"] is False and "did not take it" in got["error"]
    assert got["state"] == "Paused"


def test_music_falls_back_to_the_phones_player(monkeypatch, capsys):
    calls = []
    mpris = SimpleNamespace(current=lambda: None)
    bluez = SimpleNamespace(
        avrcp_players=lambda: [("/org/bluez/avrcp/player0", "Pixel")],
        avrcp_status=lambda path: ("Playing", "Phone Song by Phone Band"),
        avrcp=lambda path, action: (calls.append((path, action)), (True, ""))[1],
    )
    modules(monkeypatch, **{"phone.mpris": mpris, "phone.phone_bluez": bluez})
    got = call(capsys, "music", "status")
    assert (got["state"], got["title"], got["artist"], got["player"]) == (
        "Playing",
        "Phone Song",
        "Phone Band",
        "Pixel",
    )
    assert call(capsys, "music", "previous")["ok"] is True
    assert calls == [("/org/bluez/avrcp/player0", "previous")]


def test_music_without_any_backend_is_honest(monkeypatch, tmp_path, capsys):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, "music", "status")
    assert got["ok"] is True and got["error"] == ""
    assert got["state"] == "" and got["summary"] == "Nothing is playing right now."


@pytest.mark.parametrize("action", ["", "stop", "rewind"])
def test_music_bad_action(capsys, action):
    got = call(capsys, "music", action)
    assert got["ok"] is False and "music needs" in got["error"]


# --- files: received ---------------------------------------------------------


def test_received_files_are_newest_first(tmp_path, monkeypatch, capsys):
    folder = tmp_path / "downloads"
    folder.mkdir()
    now = time.time()
    for name, age in (("old.txt", 300), ("new.txt", 10), ("mid.png", 120)):
        path = folder / name
        path.write_bytes(b"x" * len(name))
        os.utime(path, (now - age, now - age))
    monkeypatch.setenv("SHANI_FILES_DIR", str(folder))
    got = call(capsys, "files", "received")
    assert got["ok"] is True and got["folder"] == str(folder)
    assert [row["name"] for row in got["files"]] == ["new.txt", "mid.png", "old.txt"]
    assert got["files"][0]["path"] == str(folder / "new.txt")
    assert got["files"][0]["size"] == len("new.txt")
    assert len(got["files"][0]["when"]) == 16
    assert [row["name"] for row in call(capsys, "files", "received", "1")["files"]] == [
        "new.txt"
    ]


def test_received_files_with_bad_or_missing_folder(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("SHANI_FILES_DIR", str(tmp_path / "gone"))
    got = call(capsys, "files", "received")
    assert got["ok"] is False and "could not be read" in got["error"]
    assert got["files"] == []
    monkeypatch.setenv("SHANI_FILES_DIR", str(tmp_path))
    assert call(capsys, "files", "received", "abc")["ok"] is False


def test_received_files_without_backend_is_an_empty_answer(
    monkeypatch, tmp_path, capsys
):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, "files", "received")
    assert (
        got["ok"] is True
        and got["files"] == []
        and got["folder"] == str(tmp_path / "empty")
    )


# --- files: send -------------------------------------------------------------


def test_send_stand_in_gets_the_path_and_logs_it(tmp_path, monkeypatch, capsys):
    log = tmp_path / "send.log"
    script = stand_in(
        tmp_path, "send.sh", 'printf "%s\\n" "$*" >> "$SHANI_FILES_LOG"; echo sent'
    )
    monkeypatch.setenv("SHANI_FILES_SEND", str(script))
    monkeypatch.setenv("SHANI_FILES_LOG", str(log))
    got = call(capsys, "files", "send", "/tmp/a file.txt")
    assert got["ok"] is True and got["error"] == ""
    assert log.read_text().strip().splitlines()[-1] == "/tmp/a file.txt"


def test_send_uses_paired_reachable_phone(monkeypatch, capsys):
    phone = FakePhone([Device("aa", "Pixel"), Device("bb", "Old", reachable=False)])
    modules(monkeypatch, **{"phone.phone": phone})
    target = Path(__file__)
    got = call(capsys, "files", "send", str(target))
    assert got["ok"] is True
    assert phone.calls == [("aa", "share", str(target))]


def test_send_honours_a_named_device_and_refuses_an_unknown_one(monkeypatch, capsys):
    phone = FakePhone([Device("aa", "Pixel")])
    modules(monkeypatch, **{"phone.phone": phone})
    got = call(capsys, "files", "send", str(__file__), "Pixel")
    assert got["ok"] is True and phone.calls[0][0] == "aa"
    assert call(capsys, "files", "send", str(__file__), "Nobody")["ok"] is False


def test_send_falls_back_to_the_wi_fi_link(monkeypatch, capsys):
    lan = FakeLan({"deviceName": "Pixel", "address": "192.168.1.4"})
    modules(monkeypatch, **{"phone.lan_link": lan})
    got = call(capsys, "files", "send", str(__file__))
    assert got["ok"] is True and lan.sent == ("192.168.1.4", str(__file__))


def test_send_bad_input_and_no_phone(monkeypatch, tmp_path, capsys):
    no_backends(monkeypatch, tmp_path)
    assert call(capsys, "files", "send")["ok"] is False
    assert call(capsys, "files", "send", str(tmp_path / "gone.txt"))["ok"] is False
    assert (
        call(capsys, "files", "send", str(__file__))["error"]
        == "no paired phone is connected"
    )


# --- files: receive ----------------------------------------------------------


def test_receive_state_on_off_and_best_effort_service(monkeypatch, tmp_path, capsys):
    settings = FakeSettings()
    modules(
        monkeypatch, **{"phone.settings": SimpleNamespace(Settings=lambda: settings)}
    )
    assert call(capsys, "files", "receive", "state")["on"] is False
    assert call(capsys, "files", "receive", "on")["on"] is True
    assert settings.writes == [(pt.RECEIVE_KEY, True)]
    assert call(capsys, "files", "receive", "state")["on"] is True
    assert call(capsys, "files", "receive", "off")["on"] is False
    assert settings.writes[-1] == (pt.RECEIVE_KEY, False)


def test_receive_bad_verb_and_missing_backend(monkeypatch, tmp_path, capsys):
    no_backends(monkeypatch, tmp_path)
    assert call(capsys, "files", "receive", "maybe")["ok"] is False
    assert call(capsys, "files", "receive", "state")["ok"] is False


def test_files_bad_verb(capsys):
    got = call(capsys, "files", "delete", "x")
    assert got["ok"] is False and "files needs" in got["error"]


# --- remote ------------------------------------------------------------------


def test_remote_stand_in_logs_the_key(tmp_path, monkeypatch, capsys):
    log = tmp_path / "remote.log"
    script = stand_in(
        tmp_path,
        "remote.sh",
        """
printf '%s %s\\n' "$1" "$2" >> "$SHANI_PHONE_REMOTE_LOG"
echo '{"on":true,"status":"connected","note":"Pressed shutter"}'
""",
    )
    monkeypatch.setenv("SHANI_PHONE_REMOTE", str(script))
    monkeypatch.setenv("SHANI_PHONE_REMOTE_LOG", str(log))
    got = call(capsys, "remote", "press", "shutter")
    assert got["ok"] is True and got["on"] is True
    assert got["status"] == "connected" and got["note"] == "Pressed shutter"
    assert log.read_text().strip().splitlines()[-1] == "press shutter"


def test_remote_reads_and_sets_the_switch(monkeypatch, capsys):
    settings = FakeSettings()
    remote = SimpleNamespace(
        KEYS=pt.REMOTE_KEYS,
        status=lambda: (
            settings.get_bool(pt.REMOTE_KEY),
            "The phone is connected and listening.",
        ),
        press=lambda key: f"Pressed {key} on the phone.",
        type_text=lambda text: f"Typed {len(text)} characters.",
    )
    modules(
        monkeypatch,
        **{
            "phone.settings": SimpleNamespace(Settings=lambda: settings),
            "phone.phone_remote": remote,
        },
    )
    got = call(capsys, "remote", "status")
    assert got == {
        "ok": True,
        "error": "",
        "on": False,
        "status": "off",
        "note": "The phone is connected and listening.",
    }
    assert call(capsys, "remote", "on")["on"] is True
    status = call(capsys, "remote", "status")
    assert status["on"] is True and status["status"] == "connected"
    assert (
        call(capsys, "remote", "press", "volume_up")["note"]
        == "Pressed volume_up on the phone."
    )
    assert call(capsys, "remote", "type", "hello")["note"] == "Typed 5 characters."
    assert call(capsys, "remote", "off")["on"] is False
    assert settings.writes == [(pt.REMOTE_KEY, True), (pt.REMOTE_KEY, False)]


def test_remote_bad_key_and_bad_verb(monkeypatch, tmp_path, capsys):
    no_backends(monkeypatch, tmp_path)
    assert call(capsys, "remote", "press", "self_destruct")["ok"] is False
    assert call(capsys, "remote", "type")["ok"] is False
    assert call(capsys, "remote", "dance")["ok"] is False


def test_remote_without_backend_still_answers(monkeypatch, tmp_path, capsys):
    settings = FakeSettings()
    modules(
        monkeypatch, **{"phone.settings": SimpleNamespace(Settings=lambda: settings)}
    )
    got = call(capsys, "remote", "status")
    assert got["ok"] is True and got["on"] is False and "not installed" in got["note"]


# --- link --------------------------------------------------------------------


def test_link_stand_in_logs_the_verb(tmp_path, monkeypatch, capsys):
    log = tmp_path / "link.log"
    script = stand_in(
        tmp_path,
        "link.sh",
        """
printf '%s %s\\n' "$1" "$2" >> "$SHANI_PHONE_LINK_LOG"
echo '{"paired":true,"name":"Pixel","address":"192.168.1.4","status":"paired","note":"Done","findable":true}'
""",
    )
    monkeypatch.setenv("SHANI_PHONE_LINK", str(script))
    monkeypatch.setenv("SHANI_PHONE_LINK_LOG", str(log))
    got = call(capsys, "link", "pair", "192.168.1.4")
    assert got["ok"] is True and got["name"] == "Pixel"
    assert got["paired"] is True and got["findable"] is True
    assert log.read_text().strip().splitlines()[-1] == "pair 192.168.1.4"


def test_link_state_find_and_findable(monkeypatch, capsys):
    settings = FakeSettings()
    lan = FakeLan(
        {"deviceName": "Pixel", "address": "192.168.1.4"},
        ("paired", "with Pixel"),
        [{"deviceName": "Pixel", "address": "10.0.0.2"}],
    )
    helper = FakeLanPhone()
    modules(
        monkeypatch,
        **{
            "phone.lan_link": lan,
            "phone.lan_phone": helper,
            "phone.settings": SimpleNamespace(Settings=lambda: settings),
        },
    )
    state = call(capsys, "link", "state")
    assert state["paired"] is True and state["name"] == "Pixel"
    assert state["status"] == "paired" and state["address"] == "192.168.1.4"
    found = call(capsys, "link", "find")
    assert found["ok"] is True and "Found 1" in found["note"]
    assert ("remember", "10.0.0.2") in helper.calls
    on = call(capsys, "link", "findable", "on")
    assert on["findable"] is True and ("announce",) in helper.calls
    assert settings.writes[-1] == (pt.FINDABLE_KEY, True)
    assert call(capsys, "link", "findable", "off")["findable"] is False
    assert call(capsys, "link", "forget")["paired"] is False and lan.forgot is True


def test_link_pair_and_bad_input(monkeypatch, tmp_path, capsys):
    settings = FakeSettings()
    lan = FakeLan()
    helper = FakeLanPhone()
    modules(
        monkeypatch,
        **{
            "phone.lan_link": lan,
            "phone.lan_phone": helper,
            "phone.settings": SimpleNamespace(Settings=lambda: settings),
        },
    )
    got = call(capsys, "link", "pair", "10.0.0.3")
    assert got["ok"] is True and got["status"] == "paired"
    assert ("pair", "10.0.0.3") in helper.calls
    assert call(capsys, "link", "pair")["ok"] is False
    assert call(capsys, "link", "findable", "maybe")["ok"] is False
    assert call(capsys, "link", "dance")["ok"] is False
    no_backends(monkeypatch, tmp_path)
    assert call(capsys, "link", "state")["ok"] is False


# --- background --------------------------------------------------------------


def test_switch_keys_match_the_engines_list():
    from phone import settings as engine

    assert pt.SWITCH_KEYS == engine.KEYS
    assert len(pt.SWITCH_ROWS) == 14


def test_background_lists_every_switch_in_plain_words(monkeypatch, capsys):
    settings = FakeSettings({pt.RECEIVE_KEY: True})
    modules(
        monkeypatch, **{"phone.settings": SimpleNamespace(Settings=lambda: settings)}
    )
    got = call(capsys, "background", "list")
    assert got["ok"] is True and got["total"] == 14 and len(got["switches"]) == 14
    assert [row["key"] for row in got["switches"]] == list(pt.SWITCH_KEYS)
    assert all(set(row) == {"key", "label", "detail", "on"} for row in got["switches"])
    assert got["on"] == 3  # two defaults plus Receive files
    text = " ".join(
        row["label"] + " " + row["detail"] for row in got["switches"]
    ).lower()
    for word in (
        "kde",
        "gsconnect",
        "obex",
        "dbus",
        "gatt",
        "pipewire",
        "avrcp",
    ):
        assert word not in text


def test_background_set_saves_and_refuses_unknown_keys(monkeypatch, capsys):
    settings = FakeSettings()
    modules(
        monkeypatch, **{"phone.settings": SimpleNamespace(Settings=lambda: settings)}
    )
    key = "watch-weather-enabled"
    got = call(capsys, "background", "set", key, "on")
    assert (
        got["ok"] is True and got["on"] is True and settings.writes[-1] == (key, True)
    )
    assert call(capsys, "background", "set", key, "off")["on"] is False
    assert call(capsys, "background", "set", "not-a-switch", "on")["ok"] is False
    assert call(capsys, "background", "set", key, "maybe")["ok"] is False
    assert call(capsys, "background", "dance")["ok"] is False


def test_background_without_settings(monkeypatch, tmp_path, capsys):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, "background", "list")
    assert got["ok"] is False and got["switches"] == [] and got["total"] == 0


# --- audio -------------------------------------------------------------------


def test_audio_stand_in(tmp_path, monkeypatch, capsys):
    log = tmp_path / "audio.log"
    script = stand_in(
        tmp_path,
        "audio.sh",
        """
printf '%s\\n' "$1" >> "$SHANI_AUDIO_LOG"
echo '{"where":"pc","note":"Call sound goes to the pc."}'
""",
    )
    monkeypatch.setenv("SHANI_AUDIO", str(script))
    monkeypatch.setenv("SHANI_AUDIO_LOG", str(log))
    for verb in ("state", "pc", "phone"):
        got = call(capsys, "audio", verb)
        assert got["ok"] is True and got["where"] == "pc"
        assert got["note"] == "Call sound goes to the pc."
    lines = log.read_text().splitlines()
    assert (lines.count("state"), lines.count("pc"), lines.count("phone")) == (2, 2, 2)


def test_audio_reads_and_moves_the_call_sound(monkeypatch, capsys):
    audio = FakeAudio([("/org/pipewire/gw1", "Pixel", "AA:BB")], where="phone")
    modules(monkeypatch, **{"phone.bt_telephony": audio})
    got = call(capsys, "audio", "state")
    assert got == {
        "ok": True,
        "error": "",
        "where": "phone",
        "note": "Call sound goes to the phone.",
    }
    moved = call(capsys, "audio", "pc")
    assert moved["ok"] is True and moved["where"] == "pc"
    assert audio.set_calls == [("/org/pipewire/gw1", "pc")]


def test_audio_no_gateway_and_refusal(monkeypatch, capsys):
    audio = FakeAudio([], ok=False)
    modules(monkeypatch, **{"phone.bt_telephony": audio})
    got = call(capsys, "audio", "state")
    assert got["ok"] is True and got["where"] == ""
    assert got["note"] == "No phone is connected for call audio."
    audio.list = [("/org/pipewire/gw1", "Pixel", "AA:BB")]
    refused = call(capsys, "audio", "phone")
    assert refused["ok"] is False and "refused" in refused["error"]


def test_audio_bad_verb_and_missing_backend(monkeypatch, tmp_path, capsys):
    assert call(capsys, "audio", "loudspeaker")["ok"] is False
    no_backends(monkeypatch, tmp_path)
    assert call(capsys, "audio", "state")["ok"] is False


# --- the real command line ---------------------------------------------------


def test_cli_prints_exactly_one_json_line(tmp_path, monkeypatch):
    script = stand_in(
        tmp_path,
        "music.sh",
        """
echo '{"state":"Playing","title":"Song","artist":"Singer","player":"Desk","summary":"Playing Song"}'
""",
    )
    env = dict(os.environ)
    env["SHANI_MUSIC"] = str(script)
    env["SHANI_FILES_DIR"] = str(tmp_path / "empty")
    (tmp_path / "empty").mkdir()
    proc = subprocess.run(
        [sys.executable, str(ROOT / "bridge" / "phone_tools.py"), "music", "status"],
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    assert proc.returncode == 0 and proc.stderr == ""
    assert len(proc.stdout.strip().splitlines()) == 1
    assert json.loads(proc.stdout)["title"] == "Song"


@pytest.mark.parametrize(
    "argv",
    [
        ("music", "status"),
        ("files", "received"),
        ("files", "send"),
        ("files", "receive", "state"),
        ("remote", "status"),
        ("link", "state"),
        ("background", "list"),
        ("audio", "state"),
        (),
        ("unknown",),
    ],
)
def test_every_command_answers_without_backends(monkeypatch, tmp_path, capsys, argv):
    no_backends(monkeypatch, tmp_path)
    got = call(capsys, *argv)
    assert isinstance(got, dict) and "ok" in got and "error" in got
    assert isinstance(got["ok"], bool) and isinstance(got["error"], str)
