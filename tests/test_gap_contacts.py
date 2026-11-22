"""Contacts gaps: favorites, avatars, sort, QR vcard, export, and the UI."""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "contacts.py"
SERVICE = (ROOT / "shani/Services/Contacts.qml").read_text()
WINDOW = (ROOT / "shani/Modules/Contacts/ContactsWindow.qml").read_text()


def run(args, tmp_path):
    env = {
        **os.environ,
        "SHANI_CONTACTS_DIR": str(tmp_path),
        "XDG_DATA_HOME": str(tmp_path),
    }
    return subprocess.run(
        ["python3", str(BRIDGE)] + args, capture_output=True, text=True, env=env
    )


def _add(tmp_path, name="Ada Lovelace"):
    out = json.loads(
        run(
            ["add", json.dumps({"name": name, "phone": "+1 555 0100"})], tmp_path
        ).stdout
    )
    return out["uid"]


def test_favorite_and_avatar_round_trip(tmp_path):
    uid = _add(tmp_path)
    run(
        [
            "edit",
            json.dumps(
                {
                    "uid": uid,
                    "name": "Ada Lovelace",
                    "phone": "+1 555 0100",
                    "favorite": True,
                    "avatar": "/home/ada/photo.jpg",
                }
            ),
        ],
        tmp_path,
    )
    card = (tmp_path / f"{uid}.vcf").read_text()
    assert "X-SHANI-FAVORITE:1" in card
    assert "PHOTO;VALUE=URI:" in card
    listed = json.loads(run(["list"], tmp_path).stdout)
    assert listed[0]["favorite"] is True
    assert listed[0]["avatar"] == "/home/ada/photo.jpg"


def test_edit_without_favorite_keeps_it(tmp_path):
    uid = _add(tmp_path)
    run(
        ["edit", json.dumps({"uid": uid, "name": "Ada Lovelace", "favorite": True})],
        tmp_path,
    )
    run(["edit", json.dumps({"uid": uid, "name": "Ada King"})], tmp_path)
    assert json.loads(run(["list"], tmp_path).stdout)[0]["favorite"] is True


def test_sort_by_given_and_family(tmp_path):
    _add(tmp_path, "Zoe Ada")
    _add(tmp_path, "Ada Zoe")
    by_name = [
        c["name"] for c in json.loads(run(["list", "", "name"], tmp_path).stdout)
    ]
    by_family = [
        c["family"] for c in json.loads(run(["list", "", "family"], tmp_path).stdout)
    ]
    assert by_name == ["Ada Zoe", "Zoe Ada"]
    assert by_family == sorted(by_family)
    assert run(["list", "", "bogus"], tmp_path).returncode == 3


def test_vcard_and_export_all(tmp_path):
    uid = _add(tmp_path)
    one = run(["vcard", uid], tmp_path)
    assert one.returncode == 0 and "BEGIN:VCARD" in one.stdout
    everything = run(["export-all"], tmp_path)
    assert everything.stdout.count("BEGIN:VCARD") == 1
    assert run(["vcard", "missing"], tmp_path).returncode == 3


def test_setgroups_and_setself_keep_arrays():
    assert "setGroups(uid, groups)" in SERVICE
    # the bug was sending only c.phone/c.email, which flattened multi-valued cards
    assert "phones: c.phones || []" in SERVICE
    assert "emails: c.emails || []" in SERVICE
    assert SERVICE.count("phones: c.phones || []") >= 3  # groups, self, favourite


def test_ui_multiple_typed_phones_emails_detail_qr_and_sort():
    assert "property var editPhones" in WINDOW and "property var editEmails" in WINDOW
    assert 'win.setPhone(index, "number", text)' in WINDOW
    assert (
        '"tel:"' in WINDOW and '"mailto:"' in WINDOW and "openstreetmap.org" in WINDOW
    )
    assert "Contacts.vcard(" in WINDOW
    assert 'Qr.show(name || "Contact", text)' in WINDOW
    assert "Contacts.toggleFavorite(" in WINDOW
    assert '["family", "Family"]' in WINDOW
    assert "Contacts.exportAll(paths[0])" in WINDOW
    assert "modelData.avatar" in WINDOW
