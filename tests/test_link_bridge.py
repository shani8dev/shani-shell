"""bridge/link.py: the phone backends behind the Calls and Messages apps.

The bridge is thin — it turns shani_link's objects into JSON rows — so what is
pinned here is the mapping, and the two promises it makes to the window: a
device nobody could read is still listed (battery -1), and a missing shani_link
is an answer rather than a traceback.
"""

import importlib
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import link  # noqa: E402


class Device:
    """What shani_link.phone.devices() yields: a NamedTuple, here a stand-in."""

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
    """shani_link is not installed: every command must still answer."""
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


# ---- with no shani_link at all ---------------------------------------------


def test_state_without_shani_link_still_answers(no_link):
    got = link.cmd_state()
    assert got["devices"] == 0 and got["backend"] == "" and got["placesCalls"] is False


def test_every_command_answers_when_shani_link_is_missing(no_link):
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
    """The copy in bridge/shani_link is what the bridge uses, and importing the
    parts it needs must not pull in gi (there is no GTK in the shell's runtime)."""
    # Other tests in the suite legitimately import gi (D-Bus agents), so check
    # only that importing these backends does not *add* it in a fresh process.
    code = (
        "import importlib,sys;"
        "import shani_link.phone,shani_link.calls_log,shani_link.contacts,shani_link.lines;"
        "print('gi' in sys.modules)"
    )
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "bridge")
    out = subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, env=env
    )
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == "False"
