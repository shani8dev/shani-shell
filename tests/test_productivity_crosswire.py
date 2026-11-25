"""Productivity cross-wiring: Notes, Calendar and Contacts use each other's
existing APIs. No new store: notes are QuickNotes' Markdown files, the day is
Agenda's showDay signal, the card is Contacts.selected.

QML cannot run under pytest here, so the surface hooks are checked on source and
the small JS helpers are lifted out of the shipped QML and run under Node, then
compared with a Python reference.
"""

import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text(encoding="utf-8")
CALENDAR = (ROOT / "shani/Modules/Calendar/CalendarPanel.qml").read_text(
    encoding="utf-8"
)
CONTACTS = (ROOT / "shani/Modules/Contacts/ContactsWindow.qml").read_text(
    encoding="utf-8"
)
QUICKNOTES = (ROOT / "shani/Services/QuickNotes.qml").read_text(encoding="utf-8")
AGENDA = (ROOT / "shani/Services/Agenda.qml").read_text(encoding="utf-8")
CONTACTS_SERVICE = (ROOT / "shani/Services/Contacts.qml").read_text(encoding="utf-8")

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is needed for the QML JS")


def js_func(src, name):
    """One `function name(...) { ... }` from a QML file, braces balanced."""
    m = re.search(r"^    function " + re.escape(name) + r"\(", src, re.M)
    assert m, name
    start = src.index("{", m.end() - 1)
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[m.start() : i + 1]
    raise AssertionError("unbalanced function " + name)


def node_eval(expr, funcs, prelude=""):
    js = prelude + r"""
var Time = {
  clockPadded: function(t){ t=String(t||""); return t.length>=5?t:t.padStart(5,"0"); },
  dayKey: function(when){ var d=when instanceof Date?when:typeof when==="string"?new Date(when):new Date(Number(when)||Date.now()); if(!d||isNaN(d.getTime())) return ""; return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0"); },
  clock: function(s){ s=Number(s)||0; return Math.floor(s/60)+":"+String(Math.floor(s%60)).padStart(2,"0"); },
  hhmmss: function(s){ s=Number(s)||0; return String(Math.floor(s/3600)).padStart(2,"0")+":"+String(Math.floor(s%3600/60)).padStart(2,"0")+":"+String(Math.floor(s%60)).padStart(2,"0"); }
};
""" + "\n".join(js_func(src, name) for src, name in funcs)
    js += "\nconsole.log(JSON.stringify(" + expr + "));\n"
    r = subprocess.run(["node", "-e", js], capture_output=True, text=True, timeout=15)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def section(src, start, end):
    i = src.index(start)
    return src[i : src.index(end, i)]


# ---- the shipped hooks -------------------------------------------------------


def test_calendar_event_detail_opens_a_prefilled_note():
    detail = section(
        CALENDAR, "// ---- click-to-view detail sheet", 'Shortcut { sequence: "Escape"'
    )
    assert 'text: Tr.t("Add note")' in detail
    assert 'Accessible.name: Tr.t("Add a note for this event")' in detail
    assert "onClicked: win.noteForEvent(win.viewingEvent)" in detail
    for needle in (
        "function noteForEvent(e)",
        "function eventNoteName(e)",
        "function eventNoteBody(e)",
        "Ui.openNotes()",
        'QuickNotes.create(name, "")',
        "QuickNotes.set(win.pendingNoteBody)",
        "noteFill.restart()",
    ):
        assert needle in CALENDAR, needle
    # an existing note of the same name is opened, not overwritten
    assert (
        'QuickNotes.notes.some(n => n.name === name && n.notebook === "")' in CALENDAR
    )
    assert 'QuickNotes.open(name, "")' in CALENDAR


def test_contact_detail_opens_a_prefilled_note_and_selects_from_a_link():
    for needle in (
        "function onSelectedChanged() { if (Contacts.selected) win.showContact(Contacts.selected); }",
        "function contactToNote(c)",
        "function contactNoteName(c)",
        "function contactNoteBody(c)",
        "Ui.openNotes()",
        'QuickNotes.create(name, "")',
        "QuickNotes.set(win.pendingNoteBody)",
        'text: Tr.t("Add to note")',
        'Accessible.name: Tr.t("Add this contact to a note")',
        "onClicked: win.contactToNote(detailCol.c)",
    ):
        assert needle in CONTACTS, needle
    assert "property var selected: null" in CONTACTS_SERVICE
    assert "function showContact(c)" in CONTACTS


def test_notes_link_chips_resolve_across_surfaces_without_touching_the_preview():
    for needle in (
        "function wikiLinkTarget(name)",
        "function followWikiLink(name)",
        "onClicked: win.followWikiLink(modelData)",
        'Accessible.name: Tr.t("Follow the link %1").arg(modelData)',
        "Services.Agenda.openCalendar()",
        "Services.Agenda.showDay(target.when)",
        "Services.Contacts.selected = c",
        "Ui.openContacts()",
        "Services.QuickNotes.jumpTo(name)",
    ):
        assert needle in PANEL, needle
    # wave 5's reading view still hands wiki links to the note service
    prev = section(PANEL, "// Reading view:", "// Wiki links")
    assert "onWikiLink: name => Services.QuickNotes.jumpTo(name)" in prev
    assert "NotesMarkdown {" in prev
    # the APIs used above already exist in the services
    assert "signal showDay(real when)" in AGENDA
    assert "function openCalendar()" in AGENDA
    assert "function create(name, notebook)" in QUICKNOTES
    assert "function set(t)" in QUICKNOTES
    assert "function valid(name)" in QUICKNOTES
    # no new store, no raw colours on the new controls
    assert 'QuickNotes.dir + "/crosswire"' not in PANEL


# ---- Python reference for the pure logic ------------------------------------


def valid_name(value):
    """Mirror of QuickNotes.valid(), the shipped note-name sanitizer."""
    s = re.sub(r"\.md$", "", str(value or "").strip())
    s = re.sub(r'[\/\\:*?"<>|]', " ", s)
    return re.sub(r"\s+", " ", s).strip()


def ref_link(name, contacts):
    raw = str(name or "").strip()
    m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", raw)
    if m:
        y, mo, d = map(int, m.groups())
        try:
            datetime(y, mo, d)
        except ValueError:
            pass
        else:
            return {"kind": "date", "label": raw, "uid": "", "dateOk": True}
    for c in contacts:
        if str(c["name"]).strip().lower() == raw.lower():
            return {
                "kind": "contact",
                "label": c["name"],
                "uid": c["uid"],
                "dateOk": None,
            }
    return {"kind": "note", "label": raw, "uid": "", "dateOk": None}


def ref_event_name(summary):
    return valid_name(summary) or "Event"


def ref_contact_name(name):
    return "Contact: " + valid_name(name) if valid_name(name) else "Contact"


CONTACT_ROWS = [
    {"uid": "u1", "name": "Ada Lovelace"},
    {"uid": "u2", "name": "Grace Hopper"},
]


@node_mark
def test_shipped_link_parser_matches_the_reference():
    names = [
        "2026-11-25",
        "2026-02-30",
        "2026-1-5",
        "ada lovelace",
        "Grace Hopper",
        "Meeting",
        "",
        None,
    ]
    expr = """(() => {
        const shape = n => {
            const t = wikiLinkTarget(n);
            return { kind: t.kind, label: t.label, uid: t.uid || "",
                     dateOk: t.kind === "date" ? t.when === new Date(2026, 10, 25).getTime() : null };
        };
        return %s.map(shape);
    })()""" % json.dumps(names)
    prelude = "const Services = { Contacts: { contacts: %s } };\n" % json.dumps(
        CONTACT_ROWS
    )
    got = node_eval(expr, [(PANEL, "wikiLinkTarget")], prelude)
    assert got == [ref_link(n, CONTACT_ROWS) for n in names]


@node_mark
def test_shipped_link_router_goes_to_calendar_contacts_or_notes():
    expr = """(() => {
        followWikiLink("2026-11-25");
        followWikiLink("Ada Lovelace");
        followWikiLink("Meeting");
        return seen;
    })()"""
    prelude = """
        const seen = [];
        const Services = {
            Contacts: { contacts: %s, selected: null },
            Agenda: { openCalendar: () => seen.push("calendar"),
                      showDay: w => seen.push("day:" + (w === new Date(2026, 10, 25).getTime())) },
            QuickNotes: { jumpTo: n => seen.push("note:" + n) }
        };
        const Ui = { openContacts: () => seen.push("contacts") };
        const win = { wikiLinkTarget: wikiLinkTarget };
    """ % json.dumps(CONTACT_ROWS)
    got = node_eval(
        expr, [(PANEL, "wikiLinkTarget"), (PANEL, "followWikiLink")], prelude
    )
    assert got == ["calendar", "day:true", "contacts", "note:Meeting"]


@node_mark
def test_shipped_note_names_and_bodies_match_the_reference():
    prelude = """
        const Tr = { t: s => { const o = new String(s);
                               o.arg = v => s.replace("%1", String(v)); return o; } };
        const QuickNotes = (function(){ __VALID__; return { valid: valid }; })();
    """.replace("__VALID__", js_func(QUICKNOTES, "valid"))
    funcs = [
        (CALENDAR, "eventNoteName"),
        (CALENDAR, "isoDay"),
        (CALENDAR, "eventNoteBody"),
        (CONTACTS, "contactNoteName"),
        (CONTACTS, "contactNoteBody"),
    ]
    expr = """(() => {
        const start = new Date(2026, 10, 25, 9, 0).getTime() / 1000;
        globalThis.win = { isoDay: isoDay };
        return {
            eventNames: [null, "", "  Standup / review: today  ", "Ideas.md"].map(s => eventNoteName({summary: s})),
            contactNames: [{name: ""}, {name: "Ada Lovelace"}].map(contactNoteName),
            eventBody: eventNoteBody({summary: "Standup", start: start,
                location: "Room 1", description: "Agenda"}),
            contactBody: contactNoteBody({name: "Ada Lovelace",
                email: "ada@x.test", phone: "+1 555"})
        };
    })()"""
    got = node_eval(expr, funcs, prelude)
    assert got["eventNames"] == [
        ref_event_name(s) for s in (None, "", "  Standup / review: today  ", "Ideas.md")
    ]
    assert got["contactNames"] == [ref_contact_name(s) for s in ("", "Ada Lovelace")]
    assert got["eventBody"] == (
        "# Standup\n\n- Date: [[2026-11-25]]\n- Location: Room 1\n\nAgenda\n"
    )
    assert got["contactBody"] == (
        "# Ada Lovelace\n\n- Email: ada@x.test\n- Phone: +1 555\n\n[[Ada Lovelace]]\n"
    )


def test_prefilled_notes_link_back_to_a_date_or_a_card():
    # the body is written with the same link syntax the Notes chips resolve
    assert '- Date: [[" + win.isoDay(' in CALENDAR
    assert 'return body + "\\n[[" + name + "]]\\n"' in CONTACTS
