"""Knowledge-base upgrade for Notes, benchmarked against Obsidian, GNOME
Notes/Bijiben and Apple Notes.

The two surfaces are Quickshell QML. Wiring is checked statically; the pure
logic added to QuickNotes.qml is lifted out of the source and run under Node so
the operator parser, the Markdown renderer, the pin/tag branches and the
template bodies are genuinely exercised, not just grepped. The shell snippets
that touch the vault are run against a tmp_path vault as well.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SERVICE = (ROOT / "shani/Services/QuickNotes.qml").read_text(encoding="utf-8")
PANEL = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text(encoding="utf-8")


def section(src: str, start: str, end: str) -> str:
    i = src.index(start)
    return src[i : src.index(end, i)]


def js_func(name: str) -> str:
    """One 4-space-indented `function name(...) { ... }` from the service."""
    m = re.search(r"^    function " + re.escape(name) + r"\(", SERVICE, re.M)
    assert m, name
    end = re.search(r"^    \}", SERVICE[m.end() :], re.M)
    assert end, name
    return SERVICE[m.start() : m.end() + end.end()]


PRELUDE = r"""
const root = ROOT_JSON;
var notes = NOTES_JSON;
const Qt = { formatDateTime: () => "2026-11-24" };
function valid(name) {
    return String(name || "").trim().replace(/\.md$/, "").replace(/[\/\\:*?"<>|]/g, " ").replace(/\s+/g, " ").trim();
}
function validNotebook(name) { return valid(name); }
function set(t) { root.text = t; }
function tags() {
    const out = [], re = /#[A-Za-z0-9_-]+/g;
    let m;
    while ((m = re.exec(String(root.text || ""))) !== null)
        if (out.indexOf(m[0]) < 0) out.push(m[0]);
    return out;
}
"""


def node_eval(expr, funcs, root=None, notes=None):
    """Run lifted QML/JS functions in Node and return the JSON result."""
    if shutil.which("node") is None:
        pytest.skip("node is needed to exercise the QML JS logic")
    root = root or {}
    links = ""
    if "parseQuery" in funcs:
        links += "root.parseQuery = parseQuery;\n"
    if "matchesOperators" in funcs:
        links += "root.matchesOperators = matchesOperators;\n"
    js = (
        PRELUDE.replace("ROOT_JSON", json.dumps(root)).replace(
            "NOTES_JSON", json.dumps(notes or [])
        )
        + "\n"
        + "\n".join(js_func(f) for f in funcs)
        + "\n"
        + links
        + "console.log(JSON.stringify("
        + expr
        + "));\n"
    )
    r = subprocess.run(["node", "-e", js], capture_output=True, text=True, timeout=15)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def script_of(prop: str) -> str:
    m = re.search(r"readonly property string " + prop + r": '(.*?)'", SERVICE)
    assert m, prop
    return m.group(1)


def command_of(pid: str) -> str:
    """The shell script in `command: ["sh", "-c", '...', "sh", ...]`."""
    i = SERVICE.index("id: " + pid)
    m = re.search(r"command: \[\"sh\", \"-c\", '(.*?)', \"sh\"", SERVICE[i : i + 1400])
    assert m, pid
    return m.group(1)


# ---- 1. Markdown preview / raw toggle ---------------------------------------


def test_markdown_preview_toggle_is_wired_both_ways():
    assert "function markdownHtml(md)" in SERVICE
    assert "function markdownInline(s)" in SERVICE
    assert "let out = escapeHtml(s);" in SERVICE  # raw HTML is escaped first
    for token in (
        "<b>",
        "<i>",
        "<ul>",
        "<li>",
        "<blockquote>",
        "<hr>",
        "<pre>",
        "wiki:$1",
    ):
        assert token in SERVICE, token
    assert "property bool previewMode" in PANEL
    assert (
        'Shortcut { sequence: "Ctrl+E"; onActivated: win.previewMode = !win.previewMode }'
        in PANEL
    )
    # The reading view moved to a safe in-QML PlainText parser (NotesMarkdown)
    # in wave 5; RichText and the service-side markdownHtml() were removed so
    # a note can never inject markup. The toggle and gated links still work.
    assert "NotesMarkdown {" in PANEL
    assert "textFormat: Text.PlainText" in PANEL
    assert (
        'Shortcut { sequence: "Ctrl+E"; onActivated: win.previewMode = !win.previewMode }'
        in PANEL
    )
    assert "!win.previewMode" in PANEL  # the raw editor hides while reading


def test_markdown_renderer_renders_subset_and_escapes_html():
    out = node_eval(
        "markdownHtml('# Head\\n\\n**bold** and *it* with [[Target]]\\n\\n- [ ] task\\n- plain\\n\\n```\\n<code>\\n```\\n\\n> quote\\n\\n---')",
        ["escapeHtml", "markdownInline", "markdownHtml"],
    )
    assert "<h1>Head</h1>" in out
    assert "<b>bold</b>" in out and "<i>it</i>" in out
    assert "<a href='wiki:Target'>[[Target]]</a>" in out
    assert "☐ task" in out and "<li>plain</li>" in out
    assert "<pre>&lt;code&gt;\n</pre>" in out  # a note cannot inject markup
    assert "<blockquote>quote</blockquote>" in out and "<hr>" in out
    inline = node_eval(
        "markdownInline('<script>x</script> `a*b` [x](https://e.test)')",
        ["escapeHtml", "markdownInline"],
    )
    assert "&lt;script&gt;" in inline and "<script>" not in inline
    assert "<font face='monospace'>a*b</font>" in inline
    assert "<a href='https://e.test'>x</a>" in inline


# ---- 2. Wiki links + backlinks ----------------------------------------------


def test_backlinks_scan_and_pane():
    assert "function backlinks(id)" in SERVICE
    assert "function updateBacklinks()" in SERVICE
    assert "property var backlinkResults" in SERVICE
    assert 'grep -liF -- "$needle"' in SERVICE
    assert '"[[" + name + "]]"' in SERVICE
    assert "s !== backlinkProc.targetId" in SERVICE  # a note never links to itself
    drawer = section(PANEL, "// Obsidian's backlinks pane:", "// Move/copy")
    assert "win.showBacklinks" in drawer
    assert "model: Services.QuickNotes.backlinkResults" in drawer
    assert "No notes link here yet" in drawer
    assert "Services.QuickNotes.updateBacklinks()" in PANEL
    assert "Services.QuickNotes.jumpTo(modelData)" in PANEL  # chips create stubs


def test_backlink_grep_script_finds_only_real_links(tmp_path):
    (tmp_path / "a.md").write_text("See [[Target]] here\n")
    (tmp_path / "b.md").write_text("See [[Other]] here\n")
    r = subprocess.run(
        ["sh", "-c", script_of("backlinkScript"), "sh", str(tmp_path), "[[Target]]"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert r.returncode == 0, r.stderr
    assert [line for line in r.stdout.splitlines() if line] == ["a"]


# ---- 3. Pinning --------------------------------------------------------------


def test_pins_are_metadata_survive_restart_and_sort_first():
    pins = section(SERVICE, "// ---- knowledge base:", "// Templates:")
    assert 'pinnedFile: root.dir + "/.pinned"' in pins
    assert "function isPinned(id)" in SERVICE
    assert "function togglePin(id)" in SERVICE
    assert "list.splice(i, 1)" in pins and "list.push(key)" in pins
    assert 'printf "%s\\\\n" "$2"' in pins
    assert "root.isPinned(a.id) ? 0 : 1" in section(
        SERVICE, "function sortedNotes(", "function changeNotebook("
    )
    assert "Services.QuickNotes.isPinned(win.currentId)" in PANEL
    assert 'Tr.t("Pin this note")' in PANEL
    assert '"★ "' in PANEL and 'Tr.t("pinned")' in PANEL
    assert 'Shortcut { sequence: "Ctrl+Shift+P"' in PANEL


def test_pin_file_round_trip(tmp_path):
    target = tmp_path / ".pinned"
    ids = ["work/Target", "Inbox"]
    subprocess.run(
        ["sh", "-c", 'printf "%s\\n" "$2" > "$1"', "sh", str(target), "\n".join(ids)],
        check=True,
        timeout=15,
    )
    assert [line for line in target.read_text().splitlines() if line] == ids


# ---- 4. Note templates -------------------------------------------------------


def test_templates_are_builtin_plus_custom_files():
    assert "function templates()" in SERVICE
    assert '["Meeting", "Journal", "Checklist"]' in SERVICE
    assert "function templateBody(name)" in SERVICE
    assert "function createFromTemplate(template, name, notebook)" in SERVICE
    block = section(SERVICE, "function createFromTemplate(", "// Markdown preview")
    assert 'printf "%s" "$2" > "$3"' in block  # built-in body
    assert 'cp -f -- "$2" "$3"' in block  # custom .templates/<name>.md
    write = section(SERVICE, "id: templateCreate", "function createFromTemplate(")
    assert "root.open(pendingName, pendingNotebook)" in write  # after the write
    assert "win.selectedTemplate" in PANEL and "win.newFromTemplate()" in PANEL


def test_template_bodies_are_written_before_opening(tmp_path):
    bodies = {
        n: node_eval("templateBody(" + json.dumps(n) + ")", ["templateBody"])
        for n in ("Meeting", "Journal", "Checklist")
    }
    assert "# Meeting" in bodies["Meeting"] and "- [ ]" in bodies["Meeting"]
    assert "## Gratitude" in bodies["Journal"] and "2026-11-24" in bodies["Journal"]
    assert bodies["Checklist"].count("- [ ]") == 2
    assert node_eval("templateBody('Custom')", ["templateBody"]) == ""
    dest = tmp_path / "new.md"
    subprocess.run(
        [
            "sh",
            "-c",
            'mkdir -p "$1" && printf "%s" "$2" > "$3"',
            "sh",
            str(tmp_path),
            bodies["Meeting"],
            str(dest),
        ],
        check=True,
        timeout=15,
    )
    assert dest.read_text() == bodies["Meeting"]


# ---- 5. Export as Markdown and HTML -----------------------------------------


def test_markdown_export_keeps_html_export_and_uses_save_dialog():
    assert "function exportMarkdown(dest)" in SERVICE
    assert "function exportMarkdownDialog()" in SERVICE
    assert 'mode: "save"' in section(
        SERVICE, "function exportMarkdownDialog(", "// Notebooks are folders"
    )
    assert 'defaultName: root.current + ".md"' in SERVICE
    assert "property string lastExportedMd" in SERVICE
    assert (
        "property string lastExported" in SERVICE
        and "function exportHtml(dest)" in SERVICE
    )
    assert 'Tr.t("Export MD")' in PANEL and 'Tr.t("Export HTML")' in PANEL
    assert "Services.QuickNotes.exportMarkdownDialog()" in PANEL


# ---- 6. Version navigation ---------------------------------------------------


def test_versions_are_previewed_stepped_then_restored():
    assert "function previewVersion(path)" in SERVICE
    assert "property string versionPreview" in SERVICE
    assert 'Tr.t("This version could not be read")' in SERVICE  # error state
    assert "function restoreVersion(path)" in SERVICE  # keep the old path
    assert "function stepVersion(delta)" in PANEL
    assert "win.historyIndex = Math.max(0, Math.min(h.length - 1" in PANEL
    assert 'Tr.t("Previous")' in PANEL and 'Tr.t("Next")' in PANEL
    assert 'Tr.t("Restore this version")' in PANEL
    assert "Services.QuickNotes.historyList[win.historyIndex]" in PANEL
    assert "No earlier versions yet" in PANEL
    assert "Services.QuickNotes.restoreVersion(" in PANEL


# ---- 7. Tag management -------------------------------------------------------


def test_tags_are_added_removed_and_collected_across_notes():
    for fn in ("validTag", "addTag", "removeTag"):
        assert "function " + fn + "(" in SERVICE
    assert "property var noteTags" in SERVICE and "property var allTagsList" in SERVICE
    assert 'grep -hoE "#[A-Za-z0-9_-]+"' in SERVICE
    assert "paste -sd, -" in SERVICE
    assert "(?![A-Za-z0-9_-])" in SERVICE  # removeTag must not eat #tagged
    assert "id: tagField" in PANEL and "win.addTagFromField()" in PANEL
    assert "win.removeSelectedTag()" in PANEL


def test_tag_branches_and_index(tmp_path):
    root = {"text": "Line one #work\n- [ ] call #home\n"}
    assert node_eval(
        "[validTag('#work'), validTag('bad tag'), validTag('')]", ["validTag"], root
    ) == ["#work", "", ""]
    after_add = node_eval(
        "(addTag('#later'), root.text)", ["validTag", "addTag"], dict(root)
    )
    assert after_add.endswith("\n#later")
    dupe = node_eval("(addTag('#work'), root.text)", ["validTag", "addTag"], dict(root))
    assert dupe == root["text"]  # a tag is never added twice
    after_remove = node_eval(
        "(removeTag('#work'), root.text)", ["validTag", "removeTag"], dict(root)
    )
    assert "#work" not in after_remove and "#home" in after_remove
    assert "Line one" in after_remove
    custom = " #[Link]("  # punctuation is not a tag
    (tmp_path / "a.md").write_text("#work #home " + custom)
    (tmp_path / "b.md").write_text("#home\n")
    r = subprocess.run(
        ["sh", "-c", command_of("tagList"), "sh", str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert r.returncode == 0, r.stderr
    rows = dict(line.split("\t", 1) for line in r.stdout.splitlines() if "\t" in line)
    assert "#home,#work" in rows["a"] and rows["b"] == "#home"


# ---- 8. Search operators -----------------------------------------------------


def test_search_operator_branches_are_wired():
    for fn in ("parseQuery", "searchBodyTerm", "matchesOperators", "filterNotes"):
        assert "function " + fn + "(" in SERVICE
    for token in (
        "out.exact.push",
        "out.exclude.push",
        "out.tags.push",
        "out.notebooks.push",
        "out.names.push",
        "p.exact.some",
        "p.text.some",
        "p.exclude.some",
        "p.tags.some",
        "p.notebooks.some",
        "p.names.some",
    ):
        assert token in SERVICE, token
    assert "root.searchBodyTerm(raw)" in SERVICE
    assert 'root.matchesOperators(s, p, "")' in SERVICE
    assert (
        "model: Services.QuickNotes.sortedNotes(Services.QuickNotes.filterNotes("
        "win.filterText, win.selectedNotebook, win.tagFilter))" in PANEL
    )


def test_parse_query_recognises_every_operator():
    funcs = ["parseQuery", "searchBodyTerm"]
    p = node_eval(
        "parseQuery('tag:work notebook:team name:Plan -draft \"exact phrase\" hello')",
        funcs,
    )
    assert (
        p["tags"] == ["work"] and p["notebooks"] == ["team"] and p["names"] == ["plan"]
    )
    assert (
        p["exclude"] == ["draft"]
        and p["exact"] == ["exact phrase"]
        and p["text"] == ["hello"]
    )
    assert node_eval("searchBodyTerm('\"two words\" tag:work')", funcs) == "two words"
    assert node_eval("searchBodyTerm('tag:work')", funcs) == "#work"
    assert node_eval("searchBodyTerm('tag:work')", funcs) != node_eval(
        "searchBodyTerm('')", funcs
    )
    assert node_eval("searchBodyTerm('')", funcs) == ""


def test_matches_operators_and_filter_notes():
    funcs = ["parseQuery", "matchesOperators", "filterNotes"]
    root = {
        "previews": {"team/Plan": "a plan for work", "Inbox": "quick note"},
        "noteTags": {"team/Plan": "#work,#home", "Inbox": "#home"},
    }
    notes = [
        {"id": "team/Plan", "name": "Plan", "notebook": "team", "mtime": 1},
        {"id": "Inbox", "name": "Inbox", "notebook": "", "mtime": 2},
    ]
    p = node_eval(
        "parseQuery('tag:work notebook:team name:plan \"plan for\" -draft')",
        funcs,
        root,
    )
    assert (
        node_eval(
            "matchesOperators('team/Plan', " + json.dumps(p) + ", '', '')",
            funcs,
            root,
            notes,
        )
        is True
    )
    assert (
        node_eval(
            "matchesOperators('Inbox', " + json.dumps(p) + ", '', '')",
            funcs,
            root,
            notes,
        )
        is False
    )
    for query, want in (
        ("tag:home", 2),
        ("tag:work", 1),
        ("notebook:team", 1),
        ("name:inbox", 1),
        ("plan", 1),
        ("-work", 1),
        ("draft", 0),
    ):
        got = node_eval(
            "filterNotes(" + json.dumps(query) + ", '', '').length", funcs, root, notes
        )
        assert got == want, (query, got)
    assert node_eval("filterNotes('work', 'other', '').length", funcs, root, notes) == 0
    assert node_eval("filterNotes('', '', 'home').length", funcs, root, notes) == 2
    assert node_eval("filterNotes('', '', 'work').length", funcs, root, notes) == 1


# ---- 9. Notebook move / copy -------------------------------------------------


def test_notebook_move_and_copy_refuse_collisions():
    for fn in ("changeNotebook", "moveToNotebook", "copyToNotebook"):
        assert "function " + fn + "(" in SERVICE
    block = section(SERVICE, "function changeNotebook(", "function moveToNotebook(")
    assert (
        "from === to" in block
        and "notes.some(x => x.name === n && x.notebook === to)" in block
    )
    assert '\'mv -f -- "$2" "$3"\'' in block and '\'cp -f -- "$2" "$3"\'' in block
    assert (
        "noteMove.reloadOpen" in block
        and "if (code === 0 && reloadOpen) file.reload();" in SERVICE
    )
    assert "win.targetNotebook" in PANEL
    assert 'Tr.t("Move here")' in PANEL and 'Tr.t("Copy here")' in PANEL
    assert "Services.QuickNotes.moveToNotebook(" in PANEL
    assert "Services.QuickNotes.copyToNotebook(" in PANEL
    assert "Move refused" in PANEL and "Copy refused" in PANEL


def test_move_and_copy_shell_ops(tmp_path):
    src_dir, dst_dir = tmp_path / "from", tmp_path / "to"
    src_dir.mkdir()
    dst_dir.mkdir()
    (src_dir / "a.md").write_text("body")
    subprocess.run(
        [
            "sh",
            "-c",
            'mkdir -p "$1" && cp -f -- "$2" "$3"',
            "sh",
            str(dst_dir),
            str(src_dir / "a.md"),
            str(dst_dir / "a.md"),
        ],
        check=True,
        timeout=15,
    )
    assert (src_dir / "a.md").read_text() == (dst_dir / "a.md").read_text() == "body"
    subprocess.run(
        [
            "sh",
            "-c",
            'mkdir -p "$1" && mv -f -- "$2" "$3"',
            "sh",
            str(dst_dir),
            str(src_dir / "a.md"),
            str(dst_dir / "b.md"),
        ],
        check=True,
        timeout=15,
    )
    assert not (src_dir / "a.md").exists() and (dst_dir / "b.md").read_text() == "body"


# ---- 10. Keyboard-first editing ---------------------------------------------


def test_keyboard_first_shortcuts_and_stepping():
    for seq in (
        "Ctrl+N",
        "Ctrl+F",
        "Ctrl+E",
        "Ctrl+B",
        "Ctrl+I",
        "Ctrl+K",
        "Ctrl+Shift+P",
        "Ctrl+Shift+F",
        "Ctrl+Shift+T",
        "Alt+Down",
        "Alt+Up",
    ):
        assert 'sequence: "' + seq + '"' in PANEL, seq
    assert "function stepNote(delta)" in PANEL
    assert "function stepVersion(delta)" in PANEL
    assert 'win.wrapSelection("[[", "]]")' in PANEL
    assert (
        "bodyField.forceActiveFocus()" in PANEL
        and "tagField.forceActiveFocus()" in PANEL
    )
    assert "id: bodyField" in PANEL and "id: tagField" in PANEL
    step = section(PANEL, "function stepNote(delta)", "function stepVersion(delta)")
    assert 'n.id.indexOf("/")' in step and "win.currentId" in step
    assert "Services.QuickNotes.open(" in step


# ---- 11. Accessible names and empty/error states ----------------------------


def test_new_controls_name_themselves_for_at_spi():
    for name in (
        "Switch to raw Markdown",
        "Pin this note",
        "Backlink from %1",
        "Preview of %1",
        "Version preview",
        "Template %1",
        "pinned",
    ):
        assert 'Tr.t("' + name + '")' in PANEL, name
    assert "Accessible.role: Accessible.ListItem" in PANEL
    assert "Accessible.role: Accessible.StatusBar" in PANEL
    assert "Accessible.role: Accessible.Document" in PANEL
    # the editor itself still has its empty state
    assert 'Tr.t("No note selected")' in PANEL


def test_empty_and_error_states_have_a_message_and_a_way_out():
    for msg in (
        "No note contains that text",
        "No earlier versions yet",
        "No notes link here yet",
        "This version could not be read",
        "The clipboard has no image",
        "No note matches",
    ):
        assert msg in PANEL or msg in SERVICE, msg
    assert 'win.statusText !== "" || Services.QuickNotes.lockError !== ""' in PANEL
    assert (
        'text: Services.QuickNotes.lockError !== "" ? Services.QuickNotes.lockError : win.statusText'
        in PANEL
    )
    assert "Clear the filter" in PANEL
    assert "win.statusText = " in PANEL


# ---- 12. No regressions in the laundry this feature sits on -----------------


def test_existing_note_safety_and_laundry_still_present():
    assert "file.setText(root.text)" in SERVICE and "interval: 600" in SERVICE
    assert "function links()" in SERVICE and "function jumpTo(name)" in SERVICE
    assert (
        "function snapshot()" in SERVICE and "function trashList" not in SERVICE
    )  # Process id, not function
    assert "id: trashList" in SERVICE and "id: histProc" in SERVICE
    assert "function exportHtml(dest)" in SERVICE and "function printNote()" in SERVICE
    assert "Services.QuickNotes.diskChanged" in PANEL
    assert "Services.QuickNotes.restore(modelData)" in PANEL
    assert "model: Services.QuickNotes.bodyResults" in PANEL
    assert "model: Services.QuickNotes.tags()" in PANEL
