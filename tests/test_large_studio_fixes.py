"""Static checks for the large-studio fixes — the creator studio: template
pickers, wizard for multi-file projects, export, script generation, live feed
tailing, dashboard widgets, search, sorting and undo/redo of recent actions.

These QML files are only loaded by Quickshell, so the tests assert on source
rather than instantiating the types.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STUDIO_WIN = ROOT / "shani/Modules/Studio/StudioWindow.qml"
STUDIO_SVC = ROOT / "shani/Services/Studio.qml"


def test_template_pickers_cover_the_four_starting_points():
    """Fix 1: Generate offers Console app, Log viewer, Status board, Server monitor."""
    t = STUDIO_SVC.read_text()
    assert "property var templates: [" in t
    for tid in ("console-app", "log-viewer", "status-board", "server-monitor"):
        assert f'"{tid}"' in t
    assert "function templateDescription(id)" in t
    assert "function generateFromTemplate(id)" in t
    assert "Studio.generateFromTemplate(modelData.id)" in STUDIO_WIN.read_text()


def test_wizard_for_multi_file_projects():
    """Fix 2: startWizard/wizardNext/wizardPrev/wizardFinish drive a step list."""
    t = STUDIO_SVC.read_text()
    assert "property bool wizardActive: false" in t
    assert "function startWizard(name, files)" in t
    assert "wizardActive = true;" in t
    assert "function wizardCount()" in t
    assert "function wizardNext()" in t and "function wizardPrev()" in t
    assert "function wizardFinish()" in t
    w = STUDIO_WIN.read_text()
    assert "Studio.wizardActive && Studio.wizardCount > 0" in w
    assert 'Tr.t("Step %1 of %2", Studio.wizardStep + 1, Studio.wizardCount())' in w
    assert "Studio.wizardNext()" in w and "Studio.wizardFinish()" in w


def test_export_copies_the_app_folder():
    """Fix 3: exportApp copies the app directory to a path."""
    t = STUDIO_SVC.read_text()
    assert "function exportApp(app, path)" in t
    assert 'cp -r "$src" "$dst/"' in t
    assert "Studio.exportApp(" in STUDIO_WIN.read_text()


def test_script_generation_asks_chronoa():
    """Fix 4: generateScript asks Chronoa for run.sh."""
    t = STUDIO_SVC.read_text()
    assert "function generateScript(app)" in t
    assert "run.sh" in t
    assert "Studio.generateScript(" in STUDIO_WIN.read_text()


def test_live_feed_tailing():
    """Fix 5: tailApp/stopTail follow the logs of an app."""
    t = STUDIO_SVC.read_text()
    assert "function tailApp(app)" in t
    assert "function stopTail()" in t
    assert "property bool tailing: false" in t
    assert "tail -F" in t
    w = STUDIO_WIN.read_text()
    assert "Studio.tailApp(modelData)" in w
    assert "Studio.stopTail()" in w


def test_dashboard_widgets():
    """Fix 6: widgetTypes + addWidget list what a project added."""
    t = STUDIO_SVC.read_text()
    assert 'property var widgetTypes: ["stat", "graph", "log", "button"]' in t
    assert "function addWidget(app, type)" in t
    assert "property var widgets: []" in t
    w = STUDIO_WIN.read_text()
    assert "model: Studio.widgetTypes" in w
    assert "Studio.addWidget(win.selectedApp, modelData)" in w


def test_search_and_sorting():
    """Fix 7/8: search filters by name/path, sortApps sorts by name or date."""
    t = STUDIO_SVC.read_text()
    assert 'property string searchText: ""' in t
    assert "function search(q)" in t
    assert (
        '(String(a.name) + " " + String(a.path)).toLowerCase().indexOf(needle) >= 0'
        in t
    )
    assert 'property string sortBy: "name"' in t
    assert "function sortApps(key)" in t
    w = STUDIO_WIN.read_text()
    assert 'placeholder: Tr.t("Search apps")' in w
    assert 'Studio.sortApps("name")' in w and 'Studio.sortApps("createdAt")' in w


def test_undo_redo_of_recent_actions():
    """Fix 9: recentActions with undoLast/redoLast, truncating redo."""
    t = STUDIO_SVC.read_text()
    assert "property var recentActions: []" in t
    assert "property int actionIndex: -1" in t
    assert "property var undone: []" in t
    assert "function recordAction(type, name)" in t
    assert "function undoLast()" in t and "function redoLast()" in t
    assert "root.recentActions.slice(0, root.actionIndex + 1)" in t


def test_code_preview_and_syntax_check():
    """Fix 10/11: preview reads main.qml; lintApp runs qmllint."""
    t = STUDIO_SVC.read_text()
    assert 'property string previewPath: ""' in t
    assert 'property string previewText: ""' in t
    assert "function preview(app)" in t
    assert "function lintApp(app)" in t
    assert "qmllint" in t
    w = STUDIO_WIN.read_text()
    assert "Studio.preview(modelData)" in w
    assert "Studio.lintApp(modelData)" in w


def test_window_has_an_undo_redo_toolbar():
    """The header shows Undo/Redo while there is anything to undo or redo."""
    w = STUDIO_WIN.read_text()
    assert 'icon: "edit-undo"' in w
    assert "Studio.actionIndex >= 0" in w
    assert "Studio.undoLast()" in w
    assert "Studio.redoLast()" in w
