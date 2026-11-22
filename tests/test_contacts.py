"""Contacts bridge: the same vCard folder, and edits that don't lose data."""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "contacts.py"

VCARD = "\r\n".join(
    [
        "BEGIN:VCARD",
        "VERSION:4.0",
        "UID:urn:uuid:11111111-2222-3333-4444-555555555555",
        "FN:Ada Lovelace",
        "N:Lovelace;Ada;;;",
        "TEL;TYPE=cell:+1 555 0100",
        "EMAIL;TYPE=home:ada@example.com",
        "BDAY:1815-12-10",
        "ORG:Analytical Engines Ltd",
        "ADR;TYPE=home:;;12 Analytical Way;London;;;UK",
        "NOTE:First programmer",
        "URL:https://example.com/ada",
        "END:VCARD",
        "",
    ]
)


def run(args, tmp_path):
    env = {
        **os.environ,
        "SHANI_CONTACTS_DIR": str(tmp_path),
        "XDG_DATA_HOME": str(tmp_path),
    }
    return subprocess.run(
        ["python3", str(BRIDGE)] + args, capture_output=True, text=True, env=env
    )


def test_import_then_edit_preserves_unknown_vcard_fields(tmp_path):
    assert json.loads(run(["import", str(_write_card(tmp_path))], tmp_path).stdout)[
        "ok"
    ]
    listings = json.loads(run(["list"], tmp_path).stdout)
    assert len(listings) == 1
    uid = listings[0]["uid"]

    edited = json.loads(
        run(
            [
                "edit",
                json.dumps(
                    {
                        "uid": uid,
                        "name": "Ada King",
                        "phone": "+1 555 0199",
                        "email": "ada@new.example",
                        "groups": ["friends"],
                    }
                ),
            ],
            tmp_path,
        ).stdout
    )
    assert edited["uid"] == uid
    saved = (tmp_path / f"{uid}.vcf").read_text()
    # Fields the UI doesn't own survive the edit unchanged.
    for line in (
        "BDAY:1815-12-10",
        "ORG:Analytical Engines Ltd",
        "NOTE:First programmer",
        "URL:https://example.com/ada",
    ):
        assert line in saved, line
    assert "ADR;TYPE=home:" in saved
    # Fields the UI does own are updated.
    assert "FN:Ada King" in saved
    assert "+1 555 0199" in saved
    assert "ada@new.example" in saved


def test_edit_keeps_multiple_typed_phones_and_emails(tmp_path):
    out = json.loads(
        run(
            ["add", json.dumps({"name": "Grace Hopper", "phone": "+1 555 0101"})],
            tmp_path,
        ).stdout
    )
    uid = out["uid"]
    merged = json.loads(
        run(
            [
                "edit",
                json.dumps(
                    {
                        "uid": uid,
                        "name": "Grace Hopper",
                        "phones": [
                            {"type": "cell", "number": "+1 555 0101"},
                            {"type": "work", "number": "+1 555 0102"},
                        ],
                        "emails": [
                            {"type": "home", "address": "grace@home.example"},
                            {"type": "work", "address": "grace@navy.example"},
                        ],
                    }
                ),
            ],
            tmp_path,
        ).stdout
    )
    assert merged["ok"]
    card = (tmp_path / f"{uid}.vcf").read_text()
    assert "+1 555 0101" in card and "+1 555 0102" in card
    assert "grace@home.example" in card and "grace@navy.example" in card


def test_plain_add_still_works(tmp_path):
    out = json.loads(
        run(
            ["add", json.dumps({"name": "Grace Hopper", "phone": "+1 555 0101"})],
            tmp_path,
        ).stdout
    )
    assert out["ok"] and out["uid"]
    assert json.loads(run(["list"], tmp_path).stdout)[0]["name"] == "Grace Hopper"


def _write_card(tmp_path):
    path = tmp_path.parent / "incoming.vcf"
    path.write_text(VCARD, encoding="utf-8")
    return path
