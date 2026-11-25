"""Wave 6 deep pass: typed contact fields and calendar descriptions.

QML cannot run under pytest here, so the surface wiring is checked on source and
the small JS helpers are executed with node against a Python reference. The
bridges are exercised for real: contacts.py in a temporary vCard folder, and
agenda.py's iCalendar writer/reader against a temporary .ics store (no EDS
bindings needed).
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge"
CONTACTS_TOOL = BRIDGE / "contacts.py"
WINDOW = (ROOT / "shani/Modules/Contacts/ContactsWindow.qml").read_text(
    encoding="utf-8"
)
SERVICE = (ROOT / "shani/Services/Contacts.qml").read_text(encoding="utf-8")
AGENDA = (ROOT / "shani/Services/Agenda.qml").read_text(encoding="utf-8")
PANEL = (ROOT / "shani/Modules/Calendar/CalendarPanel.qml").read_text(encoding="utf-8")

sys.path.insert(0, str(BRIDGE))
import agenda  # noqa: E402

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")

LABELS = ("home", "work", "mobile", "other")
TYPE_CHOICES = (
    "model: win.phoneTypes",
    "selected: win.phoneType(phone.type) === modelData[0]",
    'onClicked: win.setPhone(row, "type", modelData[0])',
    "selected: win.emailType(email.type) === modelData[0]",
    'onClicked: win.setEmail(row, "type", modelData[0])',
    'win.editPhones = win.editPhones.concat([{ type: "mobile", number: "" }])',
    'win.editEmails = win.editEmails.concat([{ type: "home", address: "" }])',
)


# ---- contacts: pure type rules ------------------------------------------------


def normalise(value, default):
    """Python mirror of the form's four labels; vCard's cell means mobile."""
    label = str(value or "").strip().strip('"').lower()
    if label == "cell":
        return "mobile" if default == "mobile" else default
    return label if label in LABELS else default


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("home", "home"),
        ("WORK", "work"),
        ("cell", "mobile"),
        ("mobile", "mobile"),
        ("other", "other"),
        ("fax", "mobile"),
        ("", "mobile"),
        (None, "mobile"),
    ],
)
def test_phone_type_rules(raw, expected):
    assert normalise(raw, "mobile") == expected


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("home", "home"),
        ("work", "work"),
        ("cell", "home"),  # a phone label is not an email label
        ("other", "other"),
        ("", "home"),
        (None, "home"),
    ],
)
def test_email_type_rules(raw, expected):
    assert normalise(raw, "home") == expected


def _js_functions(source, names):
    parts = []
    for name in names:
        start = source.index("function " + name + "(")
        brace = source.index("{", start)
        depth = 0
        for i in range(brace, len(source)):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    parts.append(source[start : i + 1])
                    break
        else:
            raise AssertionError("unbalanced function " + name)
    return "\n".join(parts)


@node_mark
def test_shipping_js_type_helpers_match_the_rules():
    helpers = _js_functions(WINDOW, ["phoneType", "emailType"])
    script = """
        const win = { phoneTypes: %s };
        %s
        process.stdout.write(JSON.stringify({
            phone: [null, "", "home", "WORK", "cell", "mobile", "other", "fax"].map(phoneType),
            email: [null, "", "home", "work", "cell", "other"].map(emailType)
        }));
    """ % (json.dumps([[x, x] for x in LABELS]), helpers)
    got = json.loads(subprocess.check_output([node, "-e", script], text=True))
    assert got["phone"] == [
        normalise(x, "mobile")
        for x in (None, "", "home", "work", "cell", "mobile", "other", "fax")
    ]
    assert got["email"] == [
        normalise(x, "home") for x in (None, "", "home", "work", "cell", "other")
    ]


# ---- contacts: static surface hooks -------------------------------------------


def test_form_uses_type_choices_not_free_text():
    for needle in TYPE_CHOICES:
        assert needle in WINDOW, needle
    assert 'placeholder: "cell / home / work"' not in WINDOW
    assert 'placeholder: "home / work"' not in WINDOW
    assert "readonly property var phoneTypes:" in WINDOW
    for label in ("Home", "Work", "Mobile", "Other"):
        assert '"%s"' % label in WINDOW


def test_form_rows_and_actions_have_names():
    assert 'Accessible.name: "Phone " + (row + 1) + ", type "' in WINDOW
    assert 'Accessible.name: "Email " + (row + 1) + ", type "' in WINDOW
    assert 'label: Tr.t("Phone number %1", index + 1)' in WINDOW
    assert 'label: "Email address " + (index + 1)' in WINDOW
    assert 'Accessible.name: Tr.t("Add another phone number")' in WINDOW
    assert 'Accessible.name: "Add another email address"' in WINDOW
    assert "Accessible.ignored" not in WINDOW  # no hidden/unlabelled cards


def test_detail_shows_normalised_types():
    assert 'text: win.phoneType(modelData.type) + ": "' in WINDOW
    assert 'text: win.emailType(modelData.type) + ": "' in WINDOW
    assert 'Accessible.name: win.phoneType(modelData.type) + " phone: "' in WINDOW
    assert 'Accessible.name: win.emailType(modelData.type) + " email: "' in WINDOW
    assert '"tel:"' in WINDOW and '"mailto:"' in WINDOW


def test_service_forwards_the_typed_arrays():
    for fn in ("function add(", "function edit("):
        start = SERVICE.index(fn)
        end = SERVICE.index("\n    function ", start + len(fn))
        body = SERVICE[start:end]
        assert "phones: d.phones || []" in body
        assert "emails: d.emails || []" in body


# ---- contacts: the real bridge, typed fields round-trip ------------------------


def run_contacts(args, tmp_path):
    env = {
        **os.environ,
        "SHANI_CONTACTS_DIR": str(tmp_path),
        "XDG_DATA_HOME": str(tmp_path),
    }
    return subprocess.run(
        ["python3", str(CONTACTS_TOOL)] + args, capture_output=True, text=True, env=env
    )


def test_vcard_typed_phones_and_emails_roundtrip(tmp_path):
    uid = json.loads(
        run_contacts(
            [
                "add",
                json.dumps(
                    {
                        "name": "Ada Lovelace",
                        "phones": [
                            {"type": "work", "number": "+1 555 0101"},
                            {"type": "mobile", "number": "+1 555 0102"},
                            {"type": "home", "number": "+1 555 0103"},
                        ],
                        "emails": [
                            {"type": "work", "address": "ada@work.example"},
                            {"type": "home", "address": "ada@home.example"},
                        ],
                    }
                ),
            ],
            tmp_path,
        ).stdout
    )["uid"]

    raw = (tmp_path / (uid + ".vcf")).read_text()
    assert "TEL;TYPE=work:+1 555 0101" in raw
    assert "TEL;TYPE=mobile:+1 555 0102" in raw
    assert "EMAIL;TYPE=work:ada@work.example" in raw

    row = json.loads(run_contacts(["list"], tmp_path).stdout)[0]
    assert [(p["type"], p["number"]) for p in row["phones"]] == [
        ("work", "+1 555 0101"),
        ("mobile", "+1 555 0102"),
        ("home", "+1 555 0103"),
    ]
    assert [(e["type"], e["address"]) for e in row["emails"]] == [
        ("work", "ada@work.example"),
        ("home", "ada@home.example"),
    ]
    assert row["phone"] == "+1 555 0101" and row["email"] == "ada@work.example"


def test_vcard_import_maps_cell_to_mobile_and_keeps_unknown_defaults(tmp_path):
    card = tmp_path.parent / "typed.vcf"
    card.write_text(
        "\r\n".join(
            [
                "BEGIN:VCARD",
                "VERSION:4.0",
                "FN:Grace Hopper",
                "TEL;TYPE=cell:+1 555 0200",
                "TEL;TYPE=work,VOICE:+1 555 0201",
                "TEL;TYPE=fax:+1 555 0202",
                'EMAIL;TYPE="work":grace@navy.example',
                "EMAIL;TYPE=x-other:grace@other.example",
                "END:VCARD",
                "",
            ]
        ),
        encoding="utf-8",
    )
    assert (
        json.loads(run_contacts(["import", str(card)], tmp_path).stdout)["count"] == 1
    )
    row = json.loads(run_contacts(["list"], tmp_path).stdout)[0]
    assert [p["type"] for p in row["phones"]] == ["mobile", "work", "mobile"]
    assert [e["type"] for e in row["emails"]] == ["work", "home"]


# ---- calendar: real bridge, description round-trip in a temporary store -------

STAMP = 1767600000  # 2026-01-05 09:00 UTC, a fixed minute for the tests
EVENT = {
    "summary": "Standup",
    "start": STAMP,
    "end": STAMP + 3600,
    "location": "Room 1",
}


def test_agenda_description_roundtrips_through_an_ics_store(tmp_path):
    store = tmp_path / "event.ics"
    store.write_text(
        agenda._ical_text(
            {**EVENT, "description": "First line\nSecond line, with, commas"}
        ),
        encoding="utf-8",
    )
    assert agenda._prop(store.read_text(), "DESCRIPTION") == (
        "First line\nSecond line, with, commas"
    )

    store.write_text(
        agenda._replace_event_fields(
            store.read_text(), {**EVENT, "description": "Rewritten notes"}
        ),
        encoding="utf-8",
    )
    assert agenda._prop(store.read_text(), "DESCRIPTION") == "Rewritten notes"

    # an edit that does not mention description must not erase it
    kept = agenda._replace_event_fields(store.read_text(), EVENT)
    assert agenda._prop(kept, "DESCRIPTION") == "Rewritten notes"


def test_agenda_readback_ignores_the_alarms_own_description():
    import types

    alarm_only = "\r\n".join(
        [
            "BEGIN:VEVENT",
            "UID:abc",
            "DTSTART:20260105T090000",
            "DTEND:20260105T100000",
            "SUMMARY:Standup",
            "BEGIN:VALARM",
            "TRIGGER:-PT10M",
            "ACTION:DISPLAY",
            "DESCRIPTION:Event reminder",
            "END:VALARM",
            "END:VEVENT",
            "",
        ]
    )
    original = agenda.bindings
    agenda.bindings = lambda: (
        None,
        None,
        types.SimpleNamespace(component_as_ical_string=lambda comp: alarm_only),
    )
    try:
        extras = agenda._event_extras(object())
    finally:
        agenda.bindings = original
    assert extras["description"] == ""
    assert extras["alarm"] == 10  # the trigger is still read from the alarm


# ---- calendar: static surface hooks (including the wave-3 cell markers) -------


def test_form_has_a_description_field_and_writes_it():
    assert "id: fDescription" in PANEL
    assert 'placeholder: "Description / notes"' in PANEL
    assert 'label: "Description"' in PANEL
    assert 'fDescription.text = e.description || ""' in PANEL
    assert 'fDescription.text = ""' in PANEL  # a new event starts empty
    assert "description: fDescription.text.trim()" in PANEL
    assert 'description: String(payload.description || "")' in AGENDA
    assert 'description: e.description || ""' in PANEL  # drag/reschedule keeps it


def test_detail_shows_the_description_with_a_name():
    assert "visible: !!((win.viewingEvent || {}).description)" in PANEL
    assert 'text: (win.viewingEvent || {}).description || ""' in PANEL
    assert 'Accessible.name: Tr.t("Description: %1", text)' in PANEL
    assert "function viewEvent(e)" in PANEL
    assert "function editViewed()" in PANEL


def test_wave3_cell_markers_survived():
    for needle in (
        "readonly property int cellDotCap: 3",
        "function isHolidayEvent(e)",
        "function cellDotCount(day)",
        "function cellOverflow(day)",
        "function cellA11yName(day)",
        "id: cellMarkers",
        "model: win.cellDotCount(monthCell.day)",
        'text: "+" + win.cellOverflow(monthCell.day)',
        "win.cellHolidays(monthCell.day).length > 0",
        "rotation: 45",
        "Accessible.ignored: true",
        'Tr.t("Holidays")',
    ):
        assert needle in PANEL, needle
