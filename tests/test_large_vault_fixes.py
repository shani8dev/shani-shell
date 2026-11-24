"""The large Passwords + Authenticator ("vault") upgrade.

Competitors read for this pass: KeePassXC (folders/favourites, strength meter,
generator-to-entry handoff, per-field copy, auto-lock), Bitwarden (vault search,
folder chips, secure notes, import/export feedback, copy countdown) and
1Password (favourites/recent, OTP grouping, live copy countdown, AT names, empty
and error states). Aegis informed the OTP search/grouping behaviour.

There is no Quickshell runtime in this container, so the shipped QML branches
are pinned as static assertions, as the other app-window suites do. The two
pieces of non-trivial logic (strength scoring and folder/favourite/recent
filtering) are also driven as unit tests through Node, which is the same JS
engine the bindings use.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PW = ROOT / "shani/Modules/Passwords/PasswordsWindow.qml"
AUTH = ROOT / "shani/Modules/Authenticator/AuthenticatorWindow.qml"


def read(path):
    return path.read_text(encoding="utf-8")


def block(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def braced(text, start):
    """The `{ ... }` from `start` onward, brace-matched (QML JS is JS)."""
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start : j + 1]
    raise AssertionError("unbalanced braces")


def function_src(text, name):
    return braced(text, text.index("function " + name + "("))


def property_src(text, name):
    full = braced(text, text.index("readonly property var " + name + ":"))
    return full[full.index("{") :]


def run_js(script):
    if shutil.which("node") is None:
        pytest.skip("node is needed to drive the QML JS bindings")
    r = subprocess.run(
        ["node", "-e", script], capture_output=True, text=True, timeout=30
    )
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


# ---- 1. folders / favourites / recent ---------------------------------------


def test_vault_has_folder_favourite_and_recent_filters():
    s = read(PW)
    assert 'property string folderFilter: ""' in s
    assert '["favourites", Tr.t("Favourites")], ["recent", Tr.t("Recent")]' in s
    assert "readonly property var folders:" in s
    assert "readonly property var shownItems:" in s
    assert "model: win.shownItems" in s
    assert 'Tr.t("Try another word or clear the folder filter")' in s
    # the categories come from real item attributes, with the local overlay on top
    assert (
        'return win.metaFor(i).category || a.category || a.folder || Tr.t("Other");'
        in s
    )
    assert (
        "next.recent = [key].concat((next.recent || []).filter(k => k !== key)).slice(0, 8);"
        in s
    )
    assert "e.opened = Date.now();" in s


def test_unit_folder_favourite_and_recent_filtering(tmp_path):
    """The same JS the bindings run: meta wins over item attributes, and
    Recent is newest-first while Favourites and a folder just narrow the list."""
    s = read(PW)
    src = "\n".join(
        [
            "const Tr = { t: s => s };",
            function_src(s, "metaKey"),
            function_src(s, "metaFor"),
            function_src(s, "categoryOf"),
            function_src(s, "isFav"),
            function_src(s, "isRecent"),
            "const items = ["
            "{path:'/a', label:'Alpha', modified:100, attributes:{site:'a.test', category:'Work'}},"
            "{path:'/b', label:'Beta', modified:200, attributes:{site:'b.test'}},"
            "{path:'/c', label:'Gamma', modified:300, attributes:{site:'c.test'}}];",
            "const meta = {'/b':{category:'Personal', favorite:true, opened:222},"
            "'/c':{opened:333}, recent:['/c','/b']};",
            "const win = { items: items, meta: meta, visibleItems: items, folderFilter: '',"
            "  metaKey: metaKey, metaFor: metaFor, categoryOf: categoryOf,"
            "  isFav: isFav, isRecent: isRecent };",
            "Object.defineProperty(win, 'shownItems', { get: function () { "
            + property_src(s, "shownItems")
            + " } });",
            "const labels = () => win.shownItems.map(i => i.label);",
            "const out = { categories: items.map(i => win.categoryOf(i)),"
            "  fav: win.isFav(items[1]), recent: win.isRecent(items[2]), all: labels() };",
            "win.folderFilter = 'favourites'; out.favourites = labels();",
            "win.folderFilter = 'recent'; out.recentList = labels();",
            "win.folderFilter = 'Work'; out.work = labels();",
            "console.log(JSON.stringify(out));",
        ]
    )
    out = run_js(src)
    assert out["categories"] == ["Work", "Personal", "Other"]
    assert out["fav"] is True and out["recent"] is True
    assert out["all"] == ["Alpha", "Beta", "Gamma"]
    assert out["favourites"] == ["Beta"]
    assert out["recentList"] == ["Gamma", "Beta"]
    assert out["work"] == ["Alpha"]


# ---- 2. keyring-backed vault details ----------------------------------------


def test_vault_details_are_saved_in_the_keyring_over_stdin():
    s = read(PW)
    assert '"put", "shani-vault-meta"' in s
    assert '["python3", win.tool, "lookup", "shani-vault-meta"]' in s
    assert "const blob = JSON.stringify({ secret: JSON.stringify(next) });" in s
    assert "if (metaWriter.running) metaWriter.nextPayload = blob;" in s
    assert (
        'onStarted: { if (payload) { write(payload); payload = ""; stdinEnabled = false; } }'
        in s
    )
    assert (
        'win.items = (r.items || []).filter(i => (i.attributes || {})["shani-id"] !== "shani-vault-meta")'
        in s
    )
    assert "if (metaWriter.running || win.metaDirty) return;" in s
    # no cleartext sidecar file for notes
    assert "vault-meta.json" not in s


# ---- 3. strength meter ------------------------------------------------------


def test_strength_meter_is_live_and_local():
    s = read(PW)
    assert "function strength(p)" in s
    assert "readonly property var newStrength: win.strength(win.draftPassword)" in s
    assert "onTextChanged: win.draftPassword = text" in s
    assert "model: 4" in s
    assert "Accessible.role: Accessible.StatusBar" in s
    assert 'Tr.t("Generated a password - check its strength before saving")' in s


def test_unit_strength_scoring_branches(tmp_path):
    s = read(PW)
    src = "\n".join(
        [
            "const Tr = { t: s => s };",
            function_src(s, "strength"),
            "const samples = ['', 'password', '123456', 'abcdefgh', 'Abcdefgh1!',"
            " 'LongerPassw0rd!2026'];",
            "console.log(JSON.stringify(samples.map(p => strength(p).score)));",
        ]
    )
    scores = run_js(src)
    assert scores[0] == 0  # empty
    assert scores[1] == 0 and scores[2] == 0  # common / digit-only
    assert scores[4] > scores[3]  # classes earn a point
    assert scores[5] == 4  # long + all classes


# ---- 4. generator -> entry --------------------------------------------------


def test_generator_uses_python_secrets_and_hands_off_to_the_form():
    s = read(PW)
    gen = block(s, "function generateForForm()", "    // Export/import vault")
    assert "import secrets, string" in gen
    assert 'gen.command = ["python3", "-c"' in gen
    assert "secrets.choice(alphabet)" in gen
    assert "Math.random(" not in s
    assert "newSecret.text = pw;" in s
    assert 'Button { text: Tr.t("Generate")' in s
    assert "attrs.category = newCategory.text.trim();" in s


# ---- 5. field-level copy with countdown ------------------------------------


def test_copy_reveals_fields_on_stdin_and_counts_down_the_wipe():
    s = read(PW)
    assert "copier.payload = r.secret;" in s
    assert "function copyUser(i) {" in s
    assert "win.clipboardLeft = 45;" in s
    assert (
        "Timer { id: clipTick; interval: 1000; repeat: true; running: win.clipboardLeft > 0;"
        in s
    )
    assert 'Tr.t("Clipboard clears in %1 s", win.clipboardLeft)' in s
    assert (
        'onTriggered: { Quickshell.execDetached(["wl-copy", "--clear"]); win.clipboardLeft = 0; }'
        in s
    )
    line = next(l for l in s.splitlines() if "Copy the key-handle id" in l)
    assert "Quickshell.clipboardText = prow.modelData.id" in line
    assert "clearTimer.restart()" in line and "win.clipboardLeft = 45" in line


# ---- 6. secure notes --------------------------------------------------------


def test_secure_notes_stay_in_the_keyring_and_are_hidden_until_asked():
    s = read(PW)
    assert "m.note = note;" in s
    assert 'win.setMetaField(prow.modelData, "note", changedNote.text.trim())' in s
    assert "function toggleNote(i)" in s
    assert "win.shownNotePath === prow.modelData.path && !win.uiLocked" in s
    assert 'win.shownNotePath = ""; }' in s  # both hide paths drop the note
    assert (
        'Tr.t("Secure note for %1: %2", prow.modelData.label, win.noteOf(prow.modelData))'
        in s
    )


# ---- 7. lock / auto-lock state ----------------------------------------------


def test_auto_lock_conceals_without_faking_a_keyring_lock():
    s = read(PW)
    assert "Timer { id: idleTimer; interval: 300000;" in s
    assert 'win.uiLockedReason = "idle"' in s
    assert 'win.uiLockedReason = "screen";' in s
    assert "readonly property bool keyringLocked:" in s and "c.locked" in s
    assert "visible: win.uiLocked || win.keyringLocked" in s
    assert "if (win.keyringLocked) win.refresh();" in s
    assert 'else { win.uiLockedReason = ""; idleTimer.restart(); }' in s
    # no password prompt that would pretend to unlock the system keyring
    overlay = block(
        s, "    Rectangle {\n        anchors.fill: parent\n        z: 10", "    }\n}"
    )
    assert "TextField" not in overlay


# ---- 8. import / export feedback --------------------------------------------


def test_import_export_report_counts_and_never_export_secrets():
    s = read(PW)
    assert 'text: Tr.t("Import…")' in s and 'text: Tr.t("Export…")' in s
    assert 'defaultName: "shani-vault.json"' in s
    assert 'format: "shani-vault-1"' in s
    assert 'with open(sys.argv[1], "x", encoding="utf-8")' in s  # never overwrite
    assert (
        'Tr.t("Exported details for %1 entries - passwords stay in the keyring", win.items.length)'
        in s
    )
    assert (
        'Tr.t("Imported details for %1 entr%2", count, count === 1 ? "y" : "ies")' in s
    )
    assert 'win.error = Tr.t("That file is not a Shani vault export");' in s
    assert 'win.error = Tr.t("Could not export the vault details");' in s
    export = block(s, "function exportVault(path)", "    function importVault(path)")
    assert "secret" not in export


# ---- 9. keyboard + AT names -------------------------------------------------


def test_keyboard_shortcuts_and_named_status_lines():
    p, a = read(PW), read(AUTH)
    assert "e.key === Qt.Key_F" in p and "e.key === Qt.Key_N" in p
    assert 'label: Tr.t("Folder")' in p and 'label: Tr.t("Secure note")' in p
    assert p.count("Accessible.name:") >= 8
    assert a.count("Accessible.name:") >= 5


# ---- 10. empty / error states -----------------------------------------------


def test_password_empty_and_error_states_are_explicit():
    s = read(PW)
    assert (
        'win.items.length ? Tr.t("Nothing matches") : Tr.t("No passwords saved yet")'
        in s
    )
    assert "win.shownItems.length === 0 && !lister.running" in s
    assert 'visible: win.error !== ""' in s
    assert 'Button { text: Tr.t("Try again"); onClicked: win.refresh() }' in s
    assert "model: win.shownItems" in s


# ---- 11. OTP search / grouping ----------------------------------------------


def test_otp_search_and_issuer_grouping():
    s = read(AUTH)
    assert 'property string searchText: ""' in s
    assert "readonly property var visibleAccounts:" in s
    assert "model: win.visibleAccounts" in s
    assert "readonly property var issuers:" in s
    assert 'Tr.t("Group by issuer")' in s
    assert 'section.property: win.grouped ? "issuer" : ""' in s
    assert "section.delegate: Rectangle {" in s
    assert 'Tr.t("Find a code")' in s
    assert 'win.visibleAccounts.length + " / " + win.accounts.length' in s


# ---- 12. OTP rollover bug ---------------------------------------------------


def test_otp_refresh_waits_for_the_turn_not_exactly_second_zero():
    s = read(AUTH)
    assert "(Math.floor(Date.now() / 1000) % a.period) >= a.period - 1" in s
    assert "% a.period) === 0" not in s
    assert "if (win.clipboardLeft > 0) win.clipboardLeft--;" in s


# ---- 13. OTP copy countdown + lock ------------------------------------------


def test_otp_codes_are_copied_on_stdin_with_a_visible_countdown():
    s = read(AUTH)
    assert "win.clipboardLeft = 45;" in s
    assert 'Tr.t("Code copied - clipboard clears in %1 s", win.clipboardLeft)' in s
    assert "target: Lock" in s
    assert 'Quickshell.execDetached(["wl-copy", "--clear"]);' in s
    assert "win.copyClip(a.code);" in s and "win.copyClip(r.code);" in s
    assert "Quickshell.clipboardText = a.code" not in s


# ---- 14. OTP empty / error states -------------------------------------------


def test_otp_empty_error_and_retry_states():
    s = read(AUTH)
    assert "visible: list.count === 0 && !lister.running" in s
    assert (
        'win.searchText !== "" || win.groupFilter !== "" ? Tr.t("Nothing matches")' in s
    )
    assert 'code === 2 ? Tr.t("The keyring is not running")' in s
    assert 'actionText: win.available ? "" : Tr.t("Try again")' in s
    assert "action: win.refresh()" in s


# ---- 15. no secrets in argv, still ------------------------------------------


def test_no_secret_is_ever_placed_in_argv():
    p, a = read(PW), read(AUTH)
    assert 'act.payload = payload || "";' in p
    assert 'onStarted: { if (payload !== "") write(payload);' in p
    assert 'writer.payload = args[0] === "add"' in a
    assert (
        'writer.command = ["python3", win.tool].concat(writer.payload ? [args[0]] : args);'
        in a
    )
    for line in p.splitlines() + a.splitlines():
        if "command:" not in line:
            continue
        assert "newSecret.text" not in line
        assert "changed.text" not in line
        assert "key.text" not in line
