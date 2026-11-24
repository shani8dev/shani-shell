"""Static checks for the competitive Feeds / Tasks / Translate fixes in this pass.

Competitors read: GNOME Feed Reader and Feedly (a feed click must leave the
Saved pile), Todoist and GNOME Todo (re-date an existing task, keyboard quick
add), DeepL and Google Translate (swap carries the answer back into the source
box; model readiness shown on open). EDS and the local model are not in the
container, so what is pinned here is the shipped QML wiring.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEEDS = "shani/Modules/Feeds/FeedsWindow.qml"
TASKS = "shani/Modules/Tasks/TasksWindow.qml"
TASKS_SERVICE = "shani/Services/Tasks.qml"
TRANSLATE = "shani/Modules/Translate/TranslateWindow.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_feed_click_leaves_the_saved_view():
    # In Feedly/GNOME Feed Reader picking a subscription always shows that
    # subscription. Ours kept showing "Saved articles" after the click.
    s = read(FEEDS)
    assert "win.leaveSearch(); win.savedShown = false; Feeds.open(modelData.url)" in s
    # the Saved chip is still the way back into the pile
    assert "win.savedShown = !win.savedShown" in s
    assert 'win.savedShown ? Tr.t("Saved articles")' in s


def test_swap_carries_the_answer_into_the_source_box():
    # DeepL/Google swap the two panes; ours re-translated the same source text.
    s = read(TRANSLATE)
    fn = s[s.index("function swap()") : s.index("function checkEndpoint()")]
    assert 'win.error === "" && win.mode !== "batch"' in fn
    assert 'win.result : ""' in fn
    assert 'if (translated !== "") input.text = translated' in fn
    assert 'if (input.text.trim() !== "") win.go()' in fn
    assert "Settings.data.translateTo = target" in fn  # chosen language still saved


def test_model_status_is_checked_when_the_window_opens():
    # A blank status line is indistinguishable from an unchecked endpoint;
    # DeepL shows readiness immediately.
    s = read(TRANSLATE)
    conn = s[s.index("Connections {") : s.index("function swap()")]
    assert "target: win" in conn
    assert (
        "function onVisibleChanged() { if (win.visible) win.checkEndpoint() }" in conn
    )
    assert "statusProc.command" in s
    assert 'Tr.t("Local model ready")' in s


def test_existing_task_can_be_re_dated():
    # Todoist lets any task be re-dated; Tasks.setDue() existed with no caller.
    s = read(TASKS)
    assert "property var dueTask: null" in s
    assert "property real editDue: 0" in s
    assert 'icon: "x-office-calendar"' in s
    assert "win.dueTask = row.modelData; win.editDue = row.modelData.due || 0" in s
    picker = s[s.index("// due date of an existing task") : s.index("// sort:")]
    assert "model: win.dueOptions" in picker
    assert "Tasks.setDue(win.dueTask, modelData[1])" in picker
    assert "win.dueTask = null" in picker
    assert "function setDue(t, due)" in read(TASKS_SERVICE)


def test_ctrl_n_focuses_the_add_field():
    # Todoist's quick-add shortcut: from anywhere in the window, not just when
    # the field already has focus.
    s = read(TASKS)
    keys = s[s.index("Keys.onPressed: e => {") : s.index("ColumnLayout {")]
    assert "(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N" in keys
    assert "field.forceActiveFocus()" in keys
    assert "e.accepted = true" in keys
