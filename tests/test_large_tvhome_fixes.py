"""Static asserts for the TV home's upgrade (Modules/TvHome/TvHome.qml): the
remote's Menu is reorder mode, the opened card pulses, grab-and-drag reorders
a shelf's menu, the clock is padded with the locale's AM/PM, the quickview
opens the open window in front of the home, F3 turns the open-apps list off,
sounds go with the actions, opening by key takes the screen fullscreen, toasts
and the new strings exist - all in the existing module, not a second one.

Static checks only - Quickshell's QML cannot run under pytest.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "shani/Modules/TvHome/TvHome.qml"


def _source():
    return SRC.read_text(encoding="utf-8")


def _block(src, start, end):
    return src[src.index(start) : src.index(end) + len(end)]


def _hints(src):
    return src[src.index("id: hints") : src.index("delegate: Row {")]


def test_the_module_still_has_its_shelves_and_power():
    src = _source()
    # the original surface, untouched by the upgrade
    for shelf in (
        'id: "open", title: Tr.t("Open now"), big: true',
        'id: "pinned", title: Tr.t("Pinned")',
        'id: "games", title: Tr.t("Games")',
        'id: "settings", title: Tr.t("Settings")',
        'id: "power", title: Tr.t("Power")',
    ):
        assert shelf in src, shelf
    for pw in ("power:suspend", "power:reboot", "power:poweroff", "power:logout"):
        assert pw in src
    assert "Settings.data.dockPinned" in src
    assert "AppFilter.allowed(a.id)" in src


def test_open_shelves_carry_the_window_for_the_quickview():
    src = _source()
    assert "w: w, run: () => { Ui.tvHome = false; Niri.focusWin(w); }" in src


def test_the_opened_card_pulses():
    src = _source()
    # activate() bumps the pulse state and the card reads it
    assert "win.openedAt++;" in src
    assert "win.pulseKey = c.key;" in src
    assert "win.pulseStep = 6;" in src
    assert (
        "readonly property bool pulse: here && win.pulseKey === card.modelData.key && win.pulseStep > 0"
        in src
    )
    assert "scale: here ? 1.06 * (pulse ? 1.28 : 1) : 1.0" in src
    # the pulse beats down, and the card stops pulsing
    assert (
        "Timer { id: pulseTimer; interval: Theme.mot(150); running: win.pulseStep > 0"
        in src
    )
    assert "win.pulseStep--" in src


def test_reorder_is_grab_and_drag_plus_remote_mode():
    src = _source()
    # the menu's order, applied when the shelves are built
    assert "property var order: ({})" in src
    assert "function ordered(id, items)" in src
    assert 'win.ordered("open", open)' in src
    assert 'win.ordered("apps", apps.map(appItem))' in src
    # a shelf can be reordered by delta from the current card
    assert "function reorderCurrent(delta)" in src
    assert "win.order = Object.assign({}, win.order, { [s.id]: list });" in src
    # the mouse drags the card
    assert "DragHandler" in src
    assert (
        "DragHandler" in src and "win.reorderCurrent(translation.x > 0 ? 1 : -1)" in src
    )


def test_the_remote_reorders_and_hints_it():
    src = _source()
    assert "property bool reorder" in src
    assert (
        'case Qt.Key_Menu: win.reorder = !win.reorder; SystemSounds.play("bell"); break;'
        in src
    )
    assert (
        "case Qt.Key_Left: win.reorder ? win.reorderCurrent(-1) : win.move(0, -1); break;"
        in src
    )
    assert (
        "case Qt.Key_Right: win.reorder ? win.reorderCurrent(1) : win.move(0, 1); break;"
        in src
    )
    hints = _hints(src)
    assert 'Tr.t("Move")' in hints and 'Tr.t("Done")' in hints
    assert 'Tr.t("Reorder")' in hints and 'key: "Menu"' in hints


def test_sounds_go_with_the_actions():
    src = _source()
    assert 'SystemSounds.play(viaKeys ? "bell" : "complete");' in src
    assert 'SystemSounds.play("bell");' in src
    assert 'SystemSounds.play("dialog-information");' in src
    # the actions: activate, reorder, quickview open, the F3 toggle
    assert "win.activate(true); break;" in src
    assert (
        'case Qt.Key_F3: win.noList = !win.noList; SystemSounds.play("bell"); break;'
        in src
    )


def test_the_quickview_opens_and_closes_a_window():
    src = _source()
    assert "property var quick: null" in src
    assert "property bool quickOpen: false" in src
    assert "function openQuick()" in src
    assert "function closeQuick(what)" in src
    assert "id: quickview" in src
    assert "visible: win.quickOpen" in src
    # the buttons: Close closes the window, Focus focuses it
    assert (
        'run: () => win.closeQuick(w => Niri.action("close-window", "--id", w.id))'
        in src
    )
    assert "run: () => win.closeQuick(w => Niri.focusWin(w))" in src
    # the double tap and F5 open it
    assert "onDoubleClicked: win.openQuick();" in src
    assert "case Qt.Key_F5: win.openQuick(); break;" in src


def test_the_clock_is_padded_with_the_locale_am_pm():
    src = _source()
    assert "function amText()" in src
    assert "const loc = Qt.locale();" in src
    assert 'Qt.formatTime(clock.date, "hh:mm") + win.amText()' in src
    assert 'Qt.formatTime(clock.date, "HH:mm")' in src
    # the top of the home reads win.timeText
    assert "text: win.timeText" in src


def test_opening_by_key_takes_the_screen_fullscreen():
    src = _source()
    assert 'property string pendingApp: ""' in src
    assert (
        "Timer { id: openTimer; interval: 320; onTriggered: Niri.fullscreenWindow(win.pendingApp); }"
        in src
    )
    assert "function openApp(a) {" in src
    assert "Launch.app(a.id);" in src
    # keys pass through a Keys.onPressed branch that opens by keys
    assert "win.activate(true); break;" in src


def test_nolist_hides_and_shows_the_open_shelf():
    src = _source()
    assert "property bool noList: false" in src
    assert 'win.ordered("open", open)' in src
    # the shelves drop the open shelf while noList is set
    assert '!(s.id === "open" && win.noList)' in src


def test_toasts_and_strings():
    src = _source()
    assert "import QtQuick.Layouts" in src
    assert 'property string toastMsg: ""' in src
    assert "function toast(msg)" in src
    assert "message: win.toastMsg" in src
    assert 'win.toast(Tr.t("Opening %1").arg(c.label));' in src
    # new strings, via Tr.t as the rest of the module
    for s in (
        'Tr.t("Reorder")',
        'Tr.t("Move")',
        'Tr.t("Done")',
        'Tr.t("List")',
        'Tr.t("No list")',
        'Tr.t("Close")',
        'Tr.t("Focus")',
        'Tr.t("Opening %1")',
    ):
        assert s in src, s


def test_the_old_key_contract_is_kept():
    # the upgrade adds keys but keeps the ones earlier tests pin
    src = _source()
    handler = src.split("Keys.onPressed: e => {", 1)[1].split("\n        }", 1)[0]
    assert "Ui.keysActivated = true;" in handler
    assert "Qt.callLater(() => Ui.keysActivated = false);" in handler
    assert handler.index("default: return;") < handler.index("Ui.keysActivated = true;")
    assert 'win.shelves[0].id === "open"' in src
    assert "Accessible.onPressAction: { card.choose(); win.activate(); }" in src
