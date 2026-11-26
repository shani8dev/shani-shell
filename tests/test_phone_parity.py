"""Phone parity: history actions, Undo and the new-message contact picker.

QML cannot run under pytest here, so the bridge verbs are driven exactly as the
windows call them (argv in, one JSON line out). The stand-ins are stricter than
a permissive fake: an unknown call id or an empty number is refused, so a
client that passes the wrong value cannot look as if it worked.
"""

import json
import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import link  # noqa: E402

ROW = {
    "id": "c1",
    "line": "phone",
    "number": "9844444444",
    "name": "Asha Patil",
    "direction": "in",
    "missed": False,
    "when": 1000,
    "seconds": 95,
}
ROW2 = {
    "id": "c2",
    "line": "landline",
    "number": "9911111111",
    "name": "",
    "direction": "out",
    "missed": False,
    "when": 2000,
    "seconds": 30,
}


class StrictCallsLog:
    """The calls engine stand-in: only an id it holds may be deleted."""

    def __init__(self, rows=()):
        self.rows = [dict(r) for r in rows]
        self.restored = []

    def delete(self, ident):
        if not any(r["id"] == ident for r in self.rows):
            raise ValueError("no such call id")
        self.rows = [r for r in self.rows if r["id"] != ident]
        return True

    def clear_for_undo(self):
        old = self.rows
        self.rows = []
        return old

    def restore(self, old):
        have = {r["id"] for r in self.rows}
        self.rows += [dict(r) for r in old if r["id"] not in have]
        self.restored.append(list(old))


class Contact:
    def __init__(self, full_name="", phones=None):
        self.full_name = full_name
        self.phones = phones or []

    def display_name(self):
        return self.full_name

    def numbers(self):
        return [value for _kind, value in self.phones]


class StrictBook:
    def __init__(self):
        self.saved = []

    def all(self):
        return list(self.saved)

    def save(self, contact):
        if not any(str(value).strip() for _kind, value in contact.phones):
            raise ValueError("a contact needs a number")
        self.saved.append(contact)
        return contact


class StrictContacts:
    """The address book stand-in: the real `contact-new` shape."""

    def __init__(self):
        self._book = StrictBook()

    def Contact(self, full_name="", phones=None):
        return Contact(full_name, phones)

    def book(self):
        return self._book

    def search(self, query):
        return [
            c
            for c in self._book.all()
            if str(query).casefold() in c.display_name().casefold()
        ]


@pytest.fixture
def calls(monkeypatch, tmp_path):
    log = StrictCallsLog([ROW, ROW2])
    monkeypatch.setattr(link, "calls_log", log)
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    return log


@pytest.fixture
def book(monkeypatch):
    mod = StrictContacts()
    monkeypatch.setattr(link, "contacts_mod", mod)
    return mod


def run(monkeypatch, capsys, *argv):
    """One bridge invocation, exactly as `link.py <cmd> <args>` is called."""
    monkeypatch.setattr(link.sys, "argv", ["link.py", *argv])
    code = link.main()
    lines = capsys.readouterr().out.strip().splitlines()
    return code, json.loads(lines[-1])


# ---- delete one row --------------------------------------------------------


def test_delete_passes_the_id_and_refuses_an_unknown_one(calls, monkeypatch, capsys):
    code, got = run(monkeypatch, capsys, "call-delete", "c1")
    assert (code, got) == (0, {"ok": True, "error": ""})
    assert [r["id"] for r in calls.rows] == ["c2"]

    # the stand-in rejects an id it does not hold; the bridge answers, no crash
    code, got = run(monkeypatch, capsys, "call-delete", "c1")
    assert code == 0 and got == {"ok": False, "error": "no such call id"}
    assert [r["id"] for r in calls.rows] == ["c2"]


def test_delete_negative_controls(calls, monkeypatch, capsys):
    code, got = run(monkeypatch, capsys, "call-delete")
    assert code == 2 and got["ok"] is False and "needs an id" in got["error"]
    code, got = run(monkeypatch, capsys, "call-delete", "")
    assert code == 0 and got["ok"] is False and "no call" in got["error"]
    assert len(calls.rows) == 2


# ---- clear all, then Undo --------------------------------------------------


def test_clear_returns_one_use_undo_token_and_restore_round_trips(
    calls, tmp_path, monkeypatch, capsys
):
    code, got = run(monkeypatch, capsys, "call-clear")
    assert code == 0 and got["ok"] is True and got["error"] == ""
    token = got["undo"]
    assert len(token) > 10 and calls.rows == []

    saved = tmp_path / "shani-shell" / "call-undo.json"
    data = json.loads(saved.read_text(encoding="utf-8"))
    assert data == {"token": token, "rows": [ROW, ROW2]}
    assert os.stat(saved).st_mode & 0o777 == 0o600  # call data is private

    code, got = run(monkeypatch, capsys, "call-restore", token)
    assert (code, got) == (0, {"ok": True, "error": ""})
    assert [r["id"] for r in calls.rows] == ["c1", "c2"]
    assert not saved.exists()  # Undo cannot be used twice


def test_undo_rejects_a_wrong_or_missing_token(calls, monkeypatch, capsys):
    run(monkeypatch, capsys, "call-clear")
    for bad in ("not-the-token", "bogus-token"):
        code, got = run(monkeypatch, capsys, "call-restore", bad)
        assert code == 0 and got["ok"] is False and "nothing to undo" in got["error"]
    code, got = run(monkeypatch, capsys, "call-restore")
    assert code == 2 and got["ok"] is False and "needs the undo id" in got["error"]
    assert calls.restored == [] and calls.rows == []


def test_restore_merges_a_call_logged_after_the_clear(calls, monkeypatch, capsys):
    _code, got = run(monkeypatch, capsys, "call-clear")
    calls.rows.append(dict(ROW2, id="c3"))  # the service logged one meanwhile
    assert run(monkeypatch, capsys, "call-restore", got["undo"])[1]["ok"] is True
    assert sorted(r["id"] for r in calls.rows) == ["c1", "c2", "c3"]


# ---- save as a contact -----------------------------------------------------


def test_save_writes_the_name_and_number_and_skips_a_duplicate(
    book, calls, monkeypatch, capsys
):
    code, got = run(monkeypatch, capsys, "call-save", "Asha Patil", "9844444444")
    assert (code, got) == (0, {"ok": True, "error": "", "saved": True})
    c = book.book().saved[0]
    assert c.display_name() == "Asha Patil" and c.numbers() == ["9844444444"]

    code, got = run(monkeypatch, capsys, "call-save", "Asha", "9844444444")
    assert code == 0 and got["ok"] is True and got["saved"] is False
    assert len(book.book().saved) == 1  # a duplicate does not add a card


def test_save_negative_controls(book, calls, monkeypatch, capsys):
    code, got = run(monkeypatch, capsys, "call-save", "Bob", "  ")
    assert code == 0 and got == {
        "ok": False,
        "error": "no number to save",
        "saved": False,
    }
    code, got = run(monkeypatch, capsys, "call-save", "Bob")
    assert code == 2 and got["saved"] is False and "needs a name" in got["error"]
    assert book.book().saved == []


def test_missing_engines_are_answers_not_tracebacks(monkeypatch, capsys):
    monkeypatch.setattr(link, "calls_log", None)
    monkeypatch.setattr(link, "contacts_mod", None)
    assert (
        run(monkeypatch, capsys, "call-delete", "c1")[1]["error"] == link.NOT_INSTALLED
    )
    assert run(monkeypatch, capsys, "call-clear")[1] == {
        "ok": False,
        "error": link.NOT_INSTALLED,
        "undo": "",
    }
    assert run(monkeypatch, capsys, "call-save", "Asha", "98444")[1] == {
        "ok": False,
        "error": link.NOT_INSTALLED,
        "saved": False,
    }


# ---- the windows render the verbs; they hold no logic ----------------------


def test_calls_window_wires_every_history_action():
    win = (ROOT / "shani/Modules/Calls/CallsWindow.qml").read_text(encoding="utf-8")
    svc = (ROOT / "shani/Services/Link.qml").read_text(encoding="utf-8")
    for call in (
        "Link.message(",
        "Link.saveCall(",
        "Link.deleteCall(",
        "Link.clearCalls()",
        "Link.undoClear()",
    ):
        assert call in win
    assert win.count("ConfirmButton {") >= 2  # delete one, clear all
    for verb in ("call-delete", "call-clear", "call-restore", "call-save"):
        assert f'run("{verb}"' in svc
    assert "property string callUndo" in svc


def test_messages_window_picks_a_contact_from_link():
    msg = (ROOT / "shani/Modules/Messages/MessagesWindow.qml").read_text(
        encoding="utf-8"
    )
    assert "Picks {" in msg
    assert "Link.contacts.map(" in msg
    assert 'Tr.t("New message")' in msg
    assert "Link.startConversation(v);" in msg  # a tap starts the composer
    assert 'objectName: "newMessageRecipient"' in msg  # typing stays optional
