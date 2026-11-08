"""Contacts surface over Shani Link's address book (feature-contacts).

Checked statically (QML + CLI) and against the bridge (bridge/contacts.py):

- The bridge reads/writes the same vCard folder Shani Link uses
  ($XDG_DATA_HOME/shani-link/contacts/, shani_link/contacts.py folder()),
  one .vcf per contact, vCard 4.0 (BEGIN:VCARD, UID, FN, TEL, EMAIL),
  with an atomic write and SHANI_CONTACTS_DIR override for tests.
- Add/list/search/edit/delete round-trip through the bridge CLI; search
  matches name, phone digits and email, accent-folded; malformed input is
  exit 3; importing a vCard with a UID already here is a copy, not an
  overwrite (contacts.py rule).
- No Evolution Data Server, no EDS/EBook bindings anywhere.
- Wiring: Ui.contacts declared and reset by closeAll(), shell.qml
  LazyLoader + Contacts in _services + IPC functions + state, the panel
  has list/search/add/edit/delete/copy/Call/import, and bin/shani's
  contacts group maps onto real IPC names.
"""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
BRIDGE = ROOT / "bridge" / "contacts.py"
CLI = ROOT / "bin" / "shani"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def run_contacts(directory, *args):
    env = dict(os.environ)
    env["SHANI_CONTACTS_DIR"] = str(directory)
    return subprocess.run([sys.executable, str(BRIDGE), *args],
                          capture_output=True, text=True, timeout=30, env=env)


def listed(directory, query=None):
    args = ["list"] + ([query] if query is not None else [])
    r = run_contacts(directory, *args)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


# ---- the bridge ------------------------------------------------------------------

def test_bridge_add_list_roundtrip(tmp_path):
    d = tmp_path / "contacts"
    assert listed(d) == []
    r = run_contacts(d, "add", '{"name":"Amma Kumbhar","phone":"+91 98765 43210","email":"amma@example.com"}')
    assert r.returncode == 0, r.stderr
    uid = json.loads(r.stdout)["uid"]
    assert uid
    rows = listed(d)
    assert len(rows) == 1
    row = rows[0]
    assert row["uid"] == uid
    assert row["name"] == "Amma Kumbhar"
    assert row["phone"] == "+91 98765 43210"
    assert row["email"] == "amma@example.com"
    # the file is a vCard 4.0 Shani Link's serialize writes
    vcf = d / f"{uid}.vcf"
    assert vcf.is_file()
    text = vcf.read_text(encoding="utf-8")
    assert "BEGIN:VCARD" in text and "VERSION:4.0" in text
    assert "FN:Amma Kumbhar" in text
    assert "TEL;TYPE=cell:+91 98765 43210" in text
    assert "EMAIL;TYPE=home:amma@example.com" in text
    assert "UID:urn:uuid:" in text


def test_bridge_search_matches_name_phone_digits_and_email(tmp_path):
    d = tmp_path / "contacts"
    run_contacts(d, "add", '{"name":"José García","phone":"+91 98765 43210","email":"jose@example.com"}')
    run_contacts(d, "add", '{"name":"Bob Smith","phone":"+1 555 010 2030","email":"bob@work.example"}')
    assert len(listed(d)) == 2
    assert [c["name"] for c in listed(d, "jose")] == ["José García"]
    assert [c["name"] for c in listed(d, "José")] == ["José García"]  # accent-folded both ways
    assert [c["name"] for c in listed(d, "98765")] == ["José García"]  # digits inside a formatted number
    assert [c["name"] for c in listed(d, "bob@work")] == ["Bob Smith"]
    assert listed(d, "no-such-person") == []


def test_bridge_edit_and_delete(tmp_path):
    d = tmp_path / "contacts"
    uid = json.loads(run_contacts(
        d, "add", '{"name":"Old Name","phone":"111","email":"old@example.com"}').stdout)["uid"]
    r = run_contacts(d, "edit", json.dumps(
        {"uid": uid, "name": "New Name", "phone": "222", "email": "new@example.com"}))
    assert r.returncode == 0, r.stderr
    row = listed(d)[0]
    assert row["name"] == "New Name" and row["phone"] == "222" and row["email"] == "new@example.com"
    r = run_contacts(d, "delete", json.dumps({"uid": uid}))
    assert r.returncode == 0, r.stderr
    assert listed(d) == []
    # deleting/editing what is not there is an error, never a crash
    assert run_contacts(d, "delete", json.dumps({"uid": uid})).returncode == 3
    assert run_contacts(d, "edit", json.dumps(
        {"uid": uid, "name": "x"})).returncode == 3


def test_bridge_import_vcard_is_a_copy_not_an_overwrite(tmp_path):
    d = tmp_path / "contacts"
    vcf = tmp_path / "book.vcf"
    vcf.write_text("BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:imported-1\r\n"
                   "FN:Jose Import\r\nTEL;TYPE=cell:+91 88888 77777\r\n"
                   "EMAIL;TYPE=home:jose@example.com\r\nEND:VCARD\r\n",
                   encoding="utf-8")
    r = run_contacts(d, "import", str(vcf))
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["count"] == 1
    assert [c["name"] for c in listed(d, "jose")] == ["Jose Import"]
    # importing the same UID again keeps both: a copy, never a silent replace
    r = run_contacts(d, "import", str(vcf))
    assert r.returncode == 0 and json.loads(r.stdout)["count"] == 1
    assert len(listed(d, "jose")) == 2
    # the JSON form the shell's importVCard sends is read too
    other = tmp_path / "one.vcf"
    other.write_text("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Bare Path\r\nEND:VCARD\r\n", encoding="utf-8")
    assert run_contacts(d, "import", json.dumps({"path": str(other)})).returncode == 0
    assert any(c["name"] == "Bare Path" for c in listed(d))


def test_bridge_rejects_bad_input_with_exit_3(tmp_path):
    d = tmp_path / "contacts"
    assert run_contacts(d, "add", "not json").returncode == 3
    assert run_contacts(d, "add", '{"phone":"123"}').returncode == 3  # no name
    assert run_contacts(d, "add", "[1, 2]").returncode == 3
    assert run_contacts(d, "delete", "{}").returncode == 3          # no uid
    assert run_contacts(d, "bogus").returncode == 3
    assert run_contacts(d, "import", str(tmp_path / "missing.vcf")).returncode == 3


def test_bridge_uses_shani_link_folder_without_eds(tmp_path):
    t = read("bridge/contacts.py")
    assert "shani-link" in t and "contacts" in t
    assert "SHANI_CONTACTS_DIR" in t and "XDG_DATA_HOME" in t
    for binding in ("from gi.repository", "import gi", "EDataServer.", "EBook.", "ECal."):
        assert binding not in t, binding
    # the same words must not appear as bindings in the shell side either
    for rel in ("shani/Services/Contacts.qml", "shani/Modules/Contacts/ContactsPanel.qml"):
        s = read(rel)
        for binding in ("from gi.repository", "EDataServer.", "EBook.", "ECal."):
            assert binding not in s, (rel, binding)
    spec = importlib.util.spec_from_file_location("contacts_bridge", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    os.environ["SHANI_CONTACTS_DIR"] = str(tmp_path / "x")
    try:
        assert str(mod.folder()) == str(tmp_path / "x")
    finally:
        del os.environ["SHANI_CONTACTS_DIR"]


# ---- the service -----------------------------------------------------------------

def test_contacts_service_drives_the_bridge():
    t = read("shani/Services/Contacts.qml")
    assert "SHANI_CONTACTS_TOOL" in t and "contacts.py" in t
    assert "Process" in t and '"list"' in t
    assert '"add"' in t and '"edit"' in t and '"delete"' in t and '"import"' in t
    for fn in ("function refresh(", "function search(", "function addContact(",
               "function editContact(", "function deleteContact(", "function importVCard(",
               "function copyText(", "function copyPhone(", "function copyEmail(",
               "function callNumber(", "function textNumber("):
        assert fn in t, fn
    # copy uses the shell clipboard; Call hands off to the modem / dial pad
    assert "Quickshell.clipboardText" in t and "lastCopied" in t
    assert "Modem.callNumber" in t and "lastCalled" in t
    # Text opens the shell SMS dialog (the Ui textMessage path)
    assert 'Ui.modemDialog = "sms"' in t and "Ui.smsTo" in t


# ---- the panel -------------------------------------------------------------------

def test_contacts_panel_is_a_qrview_panelwindow():
    t = read("shani/Modules/Contacts/ContactsPanel.qml")
    assert "PanelWindow" in t
    assert "visible: Ui.contacts && !Lock.locked" in t
    assert 'WlrLayershell.namespace: "shani-contacts"' in t
    assert "BackgroundEffect.blurRegion" in t
    assert "Keys.onEscapePressed" in t


def test_contacts_panel_has_list_search_add_edit_delete_copy_call_import():
    t = read("shani/Modules/Contacts/ContactsPanel.qml")
    # list of records with name, phone and email, plus the empty state
    assert "Contacts.contacts" in t and "modelData.name" in t
    assert "modelData.phone" in t and "modelData.email" in t
    assert "EmptyState" in t
    # live search
    assert "Search contacts" in t and "Contacts.search(" in t
    # add / edit / delete form (name + phone + email)
    for name in ("function openEditor(", "function saveEditor(", "function deleteEditor(", "function closeEditor("):
        assert name in t, name
    assert "Contacts.addContact(" in t and "Contacts.editContact(" in t and "Contacts.deleteContact(" in t
    for field in ("fName", "fPhone", "fEmail"):
        assert field in t, field
    assert "A contact needs a name" in t
    # click-to-copy for phone and email, reachable by key too
    assert "copyPhone" in t and "copyEmail" in t
    assert "Copy phone number" in t and "Copy email address" in t
    assert "KeyFocus" in t
    # Call hands the number to Shani Link's dial pad, stated plainly
    assert '"Call"' in t or "Call" in t
    assert "Modem.callNumber" in t or "contactsCall" in t
    assert "Shani Link" in t
    # import a vCard from a file (a native picker, like Fonts)
    assert "Import vCard" in t and "FileDialog" in t and ".vcf" in t
    assert "Contacts.importVCard(" in t


# ---- registration ----------------------------------------------------------------

def test_contacts_is_registered_in_shell_and_ui():
    shell = read("shani/shell.qml")
    assert "LazyLoader { active: Ui.contacts; ContactsPanel {} }" in shell
    assert "import qs.Modules.Contacts" in shell
    assert ", Contacts," in shell or "[Idle" in shell and "Contacts" in shell
    for fn in ("function toggleContacts(", "function openContacts(", "function contactsSearch(",
               "function contactsAdd(", "function contactsEdit(", "function contactsDelete(",
               "function contactsImport(", "function contactsCall(", "function contactsCopy(",
               "function contactsRefresh("):
        assert fn in shell, fn
    assert "contactsShown" in shell and "contactsCount" in shell and "contactsQuery" in shell
    assert "contacts: Ui.contacts" in shell
    ui = read("shani/Common/Ui.qml")
    assert "property bool contacts" in ui
    assert "contacts = false" in ui


def test_cli_contacts_group_maps_onto_real_ipc_functions():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(CLI))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    assert "contacts" in mod.GROUPS
    for cmd in ("open", "toggle", "close", "refresh", "search", "add", "edit", "delete", "import", "call", "copy"):
        assert any(name == cmd for name, _, _ in mod.GROUPS["contacts"]), cmd
        assert ("contacts", cmd) in mod.IPC_NAMES, (cmd, mod.IPC_NAMES)
    shell = read("shani/shell.qml")
    for (group, _sub), ipc in mod.IPC_NAMES.items():
        if group == "contacts":
            assert f"function {ipc}(" in shell, ipc
