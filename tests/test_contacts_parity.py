"""Parity with the reference contacts window: phone source, bulk actions, fields.

The bridges run for real against a temporary vCard folder and a rejecting phone
stand-in (`dev/fake-contacts-phone.py` through SHANI_CONTACTS_PHONE_TOOL). The
QML is checked on source: Qt cannot run under pytest here, and
dev/shell-parts/contacts-parity.sh drives the surfaces for real.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "contacts.py"
FAKE = ROOT / "dev" / "fake-contacts-phone.py"
SERVICE = (ROOT / "shani/Services/Contacts.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "shani/Modules/Contacts/ContactsWindow.qml").read_text(
    encoding="utf-8"
)


def run(args, tmp_path, mode="rows", with_tool=True):
    env = {
        **os.environ,
        "SHANI_CONTACTS_DIR": str(tmp_path),
        "XDG_DATA_HOME": str(tmp_path),
        "SHANI_CONTACTS_PHONE_MODE": mode,
    }
    env.pop("SHANI_CONTACTS_PHONE_TOOL", None)
    if with_tool:
        env["SHANI_CONTACTS_PHONE_TOOL"] = f"{sys.executable} {FAKE}"
    return subprocess.run(
        [sys.executable, str(BRIDGE)] + args,
        capture_output=True,
        text=True,
        env=env,
    )


def phone_tool(*args, mode="rows", log=None):
    env = {**os.environ, "SHANI_CONTACTS_PHONE_MODE": mode}
    if log:
        env["SHANI_CONTACTS_PHONE_LOG"] = str(log)
    return subprocess.run(
        [sys.executable, str(FAKE), *args], capture_output=True, text=True, env=env
    )


def add(tmp_path, name, **extra):
    payload = {"name": name, "phone": "+1 555 0100", **extra}
    out = run(["add", json.dumps(payload)], tmp_path)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)["uid"]


# ---- phone source: rows, honest empty state, rejecting stand-in ---------------


def test_phone_source_rows_and_empty_state(tmp_path):
    rows = json.loads(run(["phone"], tmp_path).stdout)
    assert [r["name"] for r in rows] == ["Alice Smith", "Bob Patil"]
    assert rows[0]["numbers"] == ["+15550100"]
    assert rows[0]["emails"] == ["alice@example.com"]
    assert all(r["uid"] for r in rows)

    assert json.loads(run(["phone"], tmp_path, mode="empty").stdout) == []
    assert json.loads(run(["phone"], tmp_path, mode="error").stdout) == []
    assert json.loads(run(["phone"], tmp_path, with_tool=False).stdout) == []


def test_phone_stand_in_rejects_options(tmp_path):
    log = tmp_path / "phone-reads.log"
    assert json.loads(phone_tool(log=log).stdout)["contacts"]
    assert phone_tool("--bogus").returncode == 3
    assert json.loads(log.read_text().splitlines()[0])["argv"] == []


# ---- save here: a copy under a fresh uid, never an overwrite ------------------


def test_save_phone_copies_without_overwriting(tmp_path):
    source = json.loads(run(["phone"], tmp_path).stdout)[0]
    first = json.loads(run(["save-phone", json.dumps(source)], tmp_path).stdout)
    second = json.loads(run(["save-phone", json.dumps(source)], tmp_path).stdout)
    assert first["ok"] and second["ok"]
    assert first["uid"] != second["uid"]
    assert first["uid"] != source["uid"]
    cards = sorted(tmp_path.glob("*.vcf"))
    assert len(cards) == 2
    assert all("FN:Alice Smith" in card.read_text() for card in cards)
    assert "+15550100" in cards[0].read_text()
    assert "alice@example.com" in cards[0].read_text()
    assert len(json.loads(run(["list"], tmp_path).stdout)) == 2


def test_save_phone_rejects_malformed_input(tmp_path):
    assert run(["save-phone", "[]"], tmp_path).returncode == 3
    assert run(["save-phone", "{}"], tmp_path).returncode == 3
    assert run(["save-phone", "not json"], tmp_path).returncode == 3


# ---- multi-select actions -----------------------------------------------------


def test_delete_many_reports_deleted_and_missing(tmp_path):
    a = add(tmp_path, "Ada Lovelace")
    b = add(tmp_path, "Grace Hopper")
    add(tmp_path, "Alan Turing")
    out = run(["delete-many", json.dumps([a, "not-there", b])], tmp_path)
    assert out.returncode == 0, out.stderr
    answer = json.loads(out.stdout)
    assert answer["deleted"] == [a, b]
    assert answer["missing"] == ["not-there"]
    assert [c["name"] for c in json.loads(run(["list"], tmp_path).stdout)] == [
        "Alan Turing"
    ]
    assert run(["delete-many", '"uid"'], tmp_path).returncode == 3
    assert run(["delete-many"], tmp_path).returncode == 3


def test_export_selected_uses_the_existing_vcard_path(tmp_path):
    a = add(tmp_path, "Ada Lovelace")
    b = add(tmp_path, "Grace Hopper")
    one = run(["export-all", json.dumps([a])], tmp_path).stdout
    assert one.count("BEGIN:VCARD") == 1 and a in one and b not in one
    both = run(["export-all"], tmp_path).stdout
    assert both.count("BEGIN:VCARD") == 2
    assert run(["export-all", '"uid"'], tmp_path).returncode == 3


# ---- the rest of the card -----------------------------------------------------


FULL = {
    "birthday": "1815-12-10",
    "addresses": [
        {
            "type": "home",
            "street": "12 Analytical Way",
            "locality": "London",
            "region": "",
            "code": "NW1",
            "country": "UK",
        }
    ],
    "org": "Analytical Engines",
    "role": "Countess",
    "urls": ["https://example.com/ada", "https://example.org/notes"],
    "note": "First programmer",
}


def test_extra_fields_round_trip_and_survive_a_partial_edit(tmp_path):
    uid = add(tmp_path, "Ada Lovelace", **FULL)
    card = (tmp_path / f"{uid}.vcf").read_text()
    for line in (
        "BDAY:1815-12-10",
        "ADR;TYPE=home:;;12 Analytical Way;London;;NW1;UK",
        "ORG:Analytical Engines",
        "ROLE:Countess",
        "NOTE:First programmer",
        "URL:https://example.com/ada",
        "URL:https://example.org/notes",
    ):
        assert line in card, line

    row = json.loads(run(["list"], tmp_path).stdout)[0]
    assert row["birthday"] == FULL["birthday"]
    assert row["org"] == FULL["org"] and row["role"] == FULL["role"]
    assert row["note"] == FULL["note"] and row["urls"] == FULL["urls"]
    assert row["addresses"][0]["locality"] == "London"

    # the buttons that toggle groups/favourites send a partial payload
    assert (
        run(["edit", json.dumps({"uid": uid, "name": "Ada King"})], tmp_path).returncode
        == 0
    )
    saved = (tmp_path / f"{uid}.vcf").read_text()
    assert "FN:Ada King" in saved
    for line in ("BDAY:1815-12-10", "ORG:Analytical Engines", "NOTE:First programmer"):
        assert line in saved, line

    # an edit that owns the fields replaces them, including clearing a URL list
    updated = {
        "uid": uid,
        "name": "Ada King",
        "birthday": "--12-10",
        "addresses": [],
        "org": "Royal Society",
        "role": "Patron",
        "urls": ["https://example.com/king"],
        "note": "Later years",
    }
    assert run(["edit", json.dumps(updated)], tmp_path).returncode == 0
    row = json.loads(run(["list"], tmp_path).stdout)[0]
    assert row["birthday"] == "--12-10" and row["addresses"] == []
    assert row["org"] == "Royal Society" and row["urls"] == ["https://example.com/king"]


def test_bad_birthday_is_rejected(tmp_path):
    assert (
        run(
            ["add", json.dumps({"name": "A", "birthday": "yesterday"})], tmp_path
        ).returncode
        == 3
    )
    assert (
        run(
            ["add", json.dumps({"name": "A", "birthday": "1815-13-40"})], tmp_path
        ).returncode
        == 3
    )


# ---- the surfaces call the new verbs -----------------------------------------


def test_ui_wires_the_phone_source_and_bulk_actions():
    for needle in (
        'text: Tr.t("From the phone")',
        "Contacts.refreshPhone()",
        "function savePhone(c)",
        '"save-phone"',
        "function removeMany(uids)",
        '"delete-many"',
        "onConfirmed: {\n                    Contacts.removeMany(win.chosen);",
        "Contacts.exportAll(paths[0], win.chosen)",
        'text: Tr.t("Save here")',
        "win.savePhoneContact(detailCol.c)",
    ):
        assert needle in WINDOW or needle in SERVICE, needle
    assert "ConfirmButton {" in WINDOW
    assert 'Tr.t("No contacts on the phone")' in WINDOW


def test_editor_has_labelled_extra_fields():
    for needle in (
        'label: Tr.t("Birthday")',
        'label: Tr.t("Street address %1", index + 1)',
        'label: Tr.t("City %1", index + 1)',
        'label: Tr.t("Organisation")',
        'label: Tr.t("Role")',
        'label: Tr.t("Websites")',
        'label: Tr.t("Note")',
        "win.setAddress(index,",
        "birthday: win.editBirthday.trim()",
        "note: win.editNote",
    ):
        assert needle in WINDOW, needle
