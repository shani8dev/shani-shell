"""bridge/link.py: the phone backends behind the Calls and Messages apps.

The bridge is thin — it turns phone's objects into JSON rows — so what is
pinned here is the mapping, and the two promises it makes to the window: a
device nobody could read is still listed (battery -1), and a missing phone
is an answer rather than a traceback.
"""

import importlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import link  # noqa: E402


class Device:
    """What phone.phone.devices() yields: a NamedTuple, here a stand-in."""

    def __init__(self, id, name, reachable=True, paired=True, path=""):
        self.id = id
        self.name = name
        self.reachable = reachable
        self.paired = paired
        self.path = path


class Message:
    def __init__(self, thread, addresses, body, date, incoming, read):
        self.thread = thread
        self.addresses = addresses
        self.body = body
        self.date = date  # milliseconds, as Android reports them
        self.incoming = incoming
        self.read = read


class FakePhone:
    def __init__(self, devices=(), battery=None, conversations=(), fail=None):
        self._devices = list(devices)
        self._battery = battery or {}
        self._conversations = list(conversations)
        self._fail = fail
        self.calls = []

    def backend(self):
        return "kdeconnect"

    def places_calls(self):
        return True

    def devices(self):
        return list(self._devices)

    def battery(self, device):
        return self._battery.get(device.id)

    def act(self, device, action, payload=""):
        if self._fail:
            raise RuntimeError(self._fail)
        self.calls.append((device.id, action, payload))
        return True, ""

    def conversations(self, device):
        return list(self._conversations)

    def thread_messages(self, device, thread, limit=10):
        return [m for m in self._conversations if m.thread == thread]

    def send_sms(self, device, addresses, text, thread=""):
        if self._fail:
            raise RuntimeError(self._fail)
        self.calls.append(("sms", addresses, text))


@pytest.fixture
def phone(monkeypatch):
    fake = FakePhone()
    monkeypatch.setattr(link, "phone", fake)
    return fake


@pytest.fixture
def no_link(monkeypatch):
    """phone is not installed: every command must still answer."""
    for name in ("phone", "calls_log", "contacts_mod", "lines"):
        monkeypatch.setattr(link, name, None)


# ---- devices ---------------------------------------------------------------


def test_devices_carry_battery_and_flags(phone):
    phone._devices = [
        Device("aa", "Pixel", reachable=True, paired=True),
        Device("bb", "Old", reachable=False, paired=False),
    ]
    phone._battery = {"aa": (80, True)}
    got = link.cmd_devices()
    assert [d["name"] for d in got] == ["Pixel", "Old"]
    assert got[0]["battery"] == 80 and got[0]["charging"] is True
    assert got[1]["paired"] is False


def test_a_battery_that_cannot_be_read_is_minus_one(phone):
    phone._devices = [Device("aa", "Pixel")]
    phone._battery = {}  # nothing reported
    assert link.cmd_devices()[0]["battery"] == -1


def test_ring_uses_the_named_device(phone):
    phone._devices = [Device("aa", "Pixel")]
    assert link.cmd_ring("aa")["ok"] is True
    assert phone.calls == [("aa", "ring", "")]


def test_ring_with_no_phone_says_so(phone):
    assert link.cmd_ring()["ok"] is False
    assert "no phone" in link.cmd_ring()["error"].lower()


def test_a_failing_action_is_reported_not_raised(phone):
    phone._devices = [Device("aa", "Pixel")]
    phone._fail = "the phone did not answer"
    got = link.cmd_ring("aa")
    assert got["ok"] is False and "did not answer" in got["error"]


# ---- calls -----------------------------------------------------------------


def test_calls_are_newest_first_with_names(monkeypatch, phone):
    class Log:
        @staticmethod
        def rows():
            return [
                {
                    "id": "1",
                    "line": "landline",
                    "number": "123",
                    "name": "Asha",
                    "direction": "in",
                    "missed": True,
                    "when": 200,
                    "seconds": 0,
                },
                {
                    "id": "2",
                    "line": "sim",
                    "number": "456",
                    "name": "",
                    "direction": "out",
                    "missed": False,
                    "when": 100,
                    "seconds": 95,
                },
            ]

    monkeypatch.setattr(link, "calls_log", Log)
    got = link.cmd_calls()
    assert [c["id"] for c in got] == ["1", "2"]
    assert got[0]["missed"] is True and got[1]["seconds"] == 95


def test_a_call_log_that_cannot_be_read_is_empty(monkeypatch, phone):
    class Log:
        @staticmethod
        def rows():
            raise OSError("no log")

    monkeypatch.setattr(link, "calls_log", Log)
    assert link.cmd_calls() == []


# ---- contacts --------------------------------------------------------------


def test_contacts_come_from_the_address_book(monkeypatch, phone):
    class Contact:
        name = "Asha"
        numbers = ["99118811111"]
        emails = ["asha@example.com"]

    class Book:
        def all(self):
            return [Contact()]

    class Mod:
        @staticmethod
        def search(query):
            return []

        @staticmethod
        def book():
            return Book()

    monkeypatch.setattr(link, "contacts_mod", Mod)
    got = link.cmd_contacts()
    assert got == [
        {"name": "Asha", "numbers": ["99118811111"], "emails": ["asha@example.com"]}
    ]


# ---- messages --------------------------------------------------------------


def test_messages_name_the_sender_from_the_book(monkeypatch, phone):
    phone._devices = [Device("aa", "Pixel")]
    phone._conversations = [
        Message("t1", ("+4471",), "see you at six", 1_700_000_000_000, True, False)
    ]

    class Book:
        def all(self):
            return []

    class Mod:
        @staticmethod
        def book():
            return Book()

        @staticmethod
        def name_for(number, book):
            return "Asha"

    monkeypatch.setattr(link, "contacts_mod", Mod)
    got = link.cmd_messages()
    assert len(got) == 1
    assert got[0]["name"] == "Asha"
    assert got[0]["text"] == "see you at six"
    assert got[0]["when"] == 1_700_000_000  # milliseconds -> seconds
    assert got[0]["unread"] is True


def test_a_thread_is_the_messages_of_one_conversation(phone):
    phone._devices = [Device("aa", "Pixel")]
    phone._conversations = [
        Message("t1", ("+4471",), "hello", 1_700_000_000_000, True, True)
    ]
    got = link.cmd_thread("t1")
    assert got[0]["incoming"] is True


# ---- dialling --------------------------------------------------------------


def test_dial_goes_out_on_the_picked_line(monkeypatch, phone):
    class Lines:
        @staticmethod
        def pick(line=""):
            return line or "landline"

        @staticmethod
        def dial(which, number):
            return None

    monkeypatch.setattr(link, "lines", Lines)
    got = link.cmd_dial("12345")
    assert got["ok"] is True and got["line"] == "landline"


def test_dial_says_why_it_could_not(monkeypatch, phone):
    class Lines:
        @staticmethod
        def pick(line=""):
            raise RuntimeError("the landline is not configured")

        @staticmethod
        def dial(which, number):
            return None

    monkeypatch.setattr(link, "lines", Lines)
    got = link.cmd_dial("12345")
    assert got["ok"] is False and "landline" in got["error"]


# ---- with no phone at all ---------------------------------------------


def test_state_without_phone_still_answers(no_link):
    got = link.cmd_state()
    assert got["devices"] == 0 and got["backend"] == "" and got["placesCalls"] is False


def test_every_command_answers_when_phone_is_missing(no_link):
    assert link.cmd_devices() == []
    assert link.cmd_calls() == []
    assert link.cmd_contacts() == []
    assert link.cmd_messages() == []
    assert link.cmd_ring()["ok"] is False


def test_the_main_entry_point_rejects_a_command_it_does_not_know():
    import subprocess

    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/link.py"), "nonsense"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 2
    assert "unknown command" in out.stdout


def test_the_vendored_backends_import_without_gtk():
    """The copy in bridge/phone is what the bridge uses, and importing the
    parts it needs must not pull in gi (there is no GTK in the shell's runtime)."""
    # Other tests in the suite legitimately import gi (D-Bus agents), so check
    # only that importing these backends does not *add* it in a fresh process.
    code = (
        "import importlib,sys;"
        "import phone.phone,phone.calls_log,phone.contacts,phone.lines;"
        "print('gi' in sys.modules)"
    )
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "bridge")
    out = subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, env=env
    )
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == "False"


# ---- call matching and the incoming card ------------------------------------


class Contact:
    def __init__(self, name, numbers=(), emails=()):
        self.name = name
        self.numbers = list(numbers)
        self.emails = list(emails)


@pytest.fixture
def book(monkeypatch):
    rows = [
        Contact("Asha Rao", ["+91 98765 43210"], ["asha@example.com"]),
        Contact("Ben", ["+44 7700 900123"]),
    ]

    class Mod:
        @staticmethod
        def search(query):
            return [c for c in rows if query.casefold() in c.name.casefold()]

        @staticmethod
        def book():
            class Book:
                @staticmethod
                def all():
                    return rows

            return Book()

    monkeypatch.setattr(link, "contacts_mod", Mod)
    return rows


def test_match_uses_the_address_book_search(book):
    got = link.cmd_match("asha")
    assert [c["name"] for c in got] == ["Asha Rao"]
    assert got[0]["numbers"] == ["+91 98765 43210"]


def test_match_finds_a_number_when_search_cannot(book, monkeypatch):
    class Mod:
        @staticmethod
        def search(query):
            return []  # the book only searches names; the bridge filters numbers

        @staticmethod
        def book():
            class Book:
                @staticmethod
                def all():
                    return book

            return Book()

    monkeypatch.setattr(link, "contacts_mod", Mod)
    assert [c["name"] for c in link.cmd_match("98765")] == ["Asha Rao"]
    assert [c["name"] for c in link.cmd_match("900123")] == ["Ben"]
    assert link.cmd_match("nobody") == []
    assert link.cmd_match("") == []


def test_match_works_without_a_backend(no_link):
    assert link.cmd_match("asha") == []
    assert link.cmd_match("98765") == []


class CallState:
    def __init__(self, row=None, trace=None):
        self.row = row or {}
        self.trace = trace if trace is not None else []
        self.cleared = []

    def current(self):
        return dict(self.row)

    def clear(self, call=None):
        self.cleared.append(call)
        self.trace.append("clear")
        self.row = {}
        return True


class Done:
    returncode = 0
    stdout = ""
    stderr = ""


def test_incoming_reads_the_shared_call_state(monkeypatch):
    state = CallState(
        {"id": "c1", "name": "Asha", "number": "123", "line": "landline", "when": 1000}
    )
    monkeypatch.setattr(link, "call_state", state)
    assert link.cmd_incoming()["name"] == "Asha"


def test_incoming_without_a_call_state_is_empty(no_link, monkeypatch):
    monkeypatch.setattr(link, "call_state", None)
    assert link.cmd_incoming() == {}


def test_call_action_clears_then_answers_on_the_line(monkeypatch):
    trace = []
    state = CallState(
        {"id": "c1", "name": "Asha", "number": "123", "line": "landline", "when": 1000},
        trace,
    )
    monkeypatch.setattr(link, "call_state", state)
    monkeypatch.setenv("SHANI_DBUS", "/fake/gdbus")
    seen = []

    def run(argv, **_kwargs):
        seen.append((argv, list(trace)))
        trace.append("gdbus")
        return Done()

    monkeypatch.setattr(link.subprocess, "run", run)
    got = link.cmd_call_action("c1", "answer")
    assert got == {"ok": True, "error": ""}
    assert state.row == {} and state.cleared == ["c1"]
    assert seen[0][1] == ["clear"]  # the card is gone before the service is asked
    argv = seen[0][0]
    assert argv[:7] == [
        "/fake/gdbus",
        "call",
        "--session",
        "--dest",
        "dev.shani.Shell.Phone",
        "--object-path",
        "/dev/shani/Shell/Phone/Calls",
    ]
    assert argv[7] == "--method"
    assert argv[8] == "dev.shani.Shell.Phone.Calls.Answer"
    assert argv[9] == "landline"


def test_decline_hangs_up(monkeypatch):
    state = CallState(
        {"id": "c2", "line": "sip-abc", "name": "", "number": "", "when": 1}
    )
    monkeypatch.setattr(link, "call_state", state)
    monkeypatch.setenv("SHANI_DBUS", "gdbus")
    seen = []
    monkeypatch.setattr(
        link.subprocess, "run", lambda argv, **kw: seen.append(argv) or Done()
    )
    assert link.cmd_call_action("c2", "decline")["ok"] is True
    assert seen[0][8] == "dev.shani.Shell.Phone.Calls.Hangup"
    assert seen[0][9] == "sip-abc"


def test_call_action_is_quietly_ok_without_gdbus(monkeypatch):
    state = CallState(
        {"id": "c1", "line": "landline", "name": "", "number": "", "when": 1}
    )
    monkeypatch.setattr(link, "call_state", state)
    monkeypatch.setenv("SHANI_DBUS", "/nowhere/gdbus")
    monkeypatch.setattr(
        link.subprocess,
        "run",
        lambda *a, **kw: (_ for _ in ()).throw(FileNotFoundError()),
    )
    got = link.cmd_call_action("c1", "answer")
    assert got == {"ok": True, "error": ""}
    assert state.row == {}


def test_call_action_reports_a_service_that_refused(monkeypatch):
    state = CallState(
        {"id": "c1", "line": "landline", "name": "", "number": "", "when": 1}
    )
    monkeypatch.setattr(link, "call_state", state)
    monkeypatch.setenv("SHANI_DBUS", "gdbus")

    class Failed:
        returncode = 1
        stdout = ""
        stderr = "Error: no such service"

    monkeypatch.setattr(link.subprocess, "run", lambda *a, **kw: Failed())
    got = link.cmd_call_action("c1", "answer")
    assert got["ok"] is True  # the card still goes away
    assert "no such service" in got["error"]
    assert state.row == {}


def test_call_action_without_a_state_or_backend_still_answers(no_link, monkeypatch):
    monkeypatch.setattr(link, "call_state", None)
    monkeypatch.delenv("SHANI_DBUS", raising=False)
    monkeypatch.setattr(link.subprocess, "run", lambda *a, **kw: Done())
    assert link.cmd_call_action("c1", "answer") == {"ok": True, "error": ""}
    assert link.cmd_call_action("c1", "maybe")["ok"] is False


# ---- the state file itself ---------------------------------------------------


def test_a_ring_is_written_atomically_with_private_permissions(tmp_path, monkeypatch):
    from phone import call_state

    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    row = call_state.ring("c1", "Asha", "12345", "landline")
    target = tmp_path / "shani-shell" / "incoming-call.json"
    assert json.loads(target.read_text()) == row
    assert target.stat().st_mode & 0o777 == 0o600
    assert not (target.with_name("incoming-call.json.tmp")).exists()
    assert call_state.current() == row


def test_a_repeat_ring_keeps_the_first_time_and_a_new_one_replaces(
    tmp_path, monkeypatch
):
    import time

    from phone import call_state

    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    first = call_state.ring("c1", "Asha", "123", "landline")
    time.sleep(0.01)
    assert call_state.ring("c1", "Someone else", "999", "phone") == first
    assert call_state.current()["name"] == "Asha"
    assert call_state.ring("c2", "Ben", "456", "phone")["id"] == "c2"
    assert call_state.current()["id"] == "c2"


def test_call_action_is_logged_for_the_live_check(monkeypatch, tmp_path):
    log = tmp_path / "phone-call-actions"
    monkeypatch.setenv("SHANI_PHONE_CALL_LOG", str(log))
    state = CallState(
        {"id": "c1", "line": "phone", "name": "", "number": "", "when": 1}
    )
    monkeypatch.setattr(link, "call_state", state)
    monkeypatch.setenv("SHANI_DBUS", "gdbus")
    monkeypatch.setattr(link.subprocess, "run", lambda *a, **kw: Done())
    link.cmd_call_action("c1", "decline")
    assert log.read_text(encoding="utf-8") == "c1 decline\n"


def test_contacts_read_a_real_vcard_folder(tmp_path, monkeypatch):
    from phone import contacts as real

    folder = tmp_path / "shani-shell" / "contacts"
    folder.mkdir(parents=True)
    (folder / "asha.vcf").write_text(
        "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Asha Patil\r\n"
        "TEL;TYPE=CELL:+91 98444 44444\r\nEMAIL:asha@example.com\r\nEND:VCARD\r\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("SHANI_CONTACTS_DIR", str(folder))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    monkeypatch.setattr(link, "contacts_mod", real)
    got = link.cmd_contacts("98444")
    assert len(got) == 1
    assert got[0]["name"] == "Asha Patil"
    assert "+91 98444 44444" in got[0]["numbers"]
    assert got[0]["emails"] == ["asha@example.com"]


def test_an_old_ring_is_gone_and_clear_respects_the_id(tmp_path, monkeypatch):
    import time

    from phone import call_state

    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    call_state.ring("c1", "Asha", "123", "landline")
    target = tmp_path / "shani-shell" / "incoming-call.json"
    old = json.loads(target.read_text())
    old["when"] = int(time.time()) - 91
    target.write_text(json.dumps(old))
    assert call_state.current() == {}
    assert not target.exists()
    call_state.ring("c2", "Ben", "456", "phone")
    assert call_state.clear("other") is False and call_state.current()["id"] == "c2"
    assert call_state.clear("c2") is True and call_state.current() == {}
