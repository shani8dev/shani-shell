"""Wave 5 deep pass: group dismissal, capped popups, tray overflow, app stacks.

There is no QML runtime in pytest, so the QML side is pinned with static hooks
and the small algorithms are mirrored in plain Python. The mirrors are the
cases a render cannot stage: four popups from one app, a tray with exactly the
cap, and a group dismissed while an open header remembers it.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POPUPS = (ROOT / "shani/Modules/Notifications/Popups.qml").read_text(encoding="utf-8")
BAR = (ROOT / "shani/Modules/Bar/Bar.qml").read_text(encoding="utf-8")
SWITCHER = (ROOT / "shani/Modules/Switcher/Switcher.qml").read_text(encoding="utf-8")

POPUP_CAP = 4  # Notifs.qml: root.popups = ...slice(-4)
TRAY_CAP = 6  # Bar.qml: bar.trayCap
CRITICAL = "critical"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def section(text, start, stop):
    """One function/block, so an identical string elsewhere cannot satisfy a test."""
    return text.split(start, 1)[1].split(stop, 1)[0]


# ---- pure logic: mirrors of the QML ----------------------------------------


def note(nid, app, critical=False, desktop=""):
    return {
        "id": nid,
        "appName": app,
        "desktopEntry": desktop,
        "urgency": CRITICAL if critical else "normal",
        "dismissed": False,
    }


def app_key(n):
    """Popups.qml appKey, plus Notifs.qml's desktop-entry-first key set."""
    return str(n.get("desktopEntry") or n.get("appName") or "").lower() or "other"


def group_popups(popups):
    """Popups.qml groupPopups: reverse into newest-first, fold by app key
    and by the name/desktop id an app may send in only some notices."""
    out, by_key, by_name = [], {}, {}
    for n in list(popups)[::-1]:
        critical = n["urgency"] == CRITICAL
        key = "critical:" + str(n["id"]) if critical else app_key(n)
        name = (n["appName"] or "").lower()
        desktop = (n["desktopEntry"] or "").lower()
        g = by_key.get(key)
        if not g and not critical:
            g = by_name.get(name) or by_name.get(desktop)
        if g:
            by_key[key] = g
        else:
            g = {"key": key, "name": n["appName"], "items": []}
            out.append(g)
            by_key[key] = g
        if not critical:
            if name:
                by_name[name] = g
            if desktop:
                by_name[desktop] = g
        g["items"].append(n)
    return [g for g in out if g["items"]]


def add_popup(popups, n):
    """Notifs.qml onNotification: keep at most POPUP_CAP popups, newest last."""
    return (list(popups) + [n])[-POPUP_CAP:]


def drop_popup(popups, n):
    """Notifs.qml dropPopup: one card leaves, the others stay in their stack."""
    return [p for p in popups if p is not n]


def dismiss_group(group, expanded):
    """Popups.qml dismissGroup: every non-critical card, and no stale open key."""
    for n in group["items"]:
        if n["urgency"] != CRITICAL:
            n["dismissed"] = True
    rest = {k: v for k, v in expanded.items() if k != group["key"]}
    return rest


def tray_split(items, cap=TRAY_CAP):
    """Bar.qml trayShown / trayOverflow: one cap, no gaps, no duplicates."""
    return list(items)[:cap], list(items)[cap:]


def group_windows(mru):
    """Switcher.qml buildGroups: first sighting of an app keeps its MRU slot."""
    out, by_key = [], {}
    for w in mru:
        key = str(w.get("app_id") or "").lower() or "other"
        if key not in by_key:
            by_key[key] = {"key": key, "windows": []}
            out.append(by_key[key])
        by_key[key]["windows"].append(w)
    return out


# ---- QML hooks: the features still live in the files that own them ---------


def test_group_dismissal_is_wired_to_a_named_button():
    fn = section(POPUPS, "function dismissGroup(g)", "component PopupCard:")
    assert "for (const n of g.items.slice())" in fn
    assert "n.urgency !== NotificationUrgency.Critical" in fn
    assert "n.dismiss();" in fn
    assert "delete e[g.key];" in fn, "an emptied stack must forget it was open"
    header = section(POPUPS, "readonly property string stackName:", "Repeater {")
    assert 'Tr.t("Dismiss %1 notifications from %2"' in header
    assert "win.dismissGroup(stack.modelData)" in header
    assert 'icon: "window-close"' in header
    # the header's own MouseArea sits *under* the row, or it would eat the button
    assert POPUPS.index("cursorShape: Qt.PointingHandCursor") < POPUPS.index(
        "id: stackHead"
    )
    assert "Accessible.onPressAction: win.toggleGroup(stack.modelData.key)" in POPUPS


def test_grouping_key_and_critical_exception_are_preserved():
    assert (
        'String((n && n.desktopEntry) || (n && n.appName) || "").toLowerCase()'
        in POPUPS
    )
    assert "Notifs.popups.slice().reverse()" in POPUPS
    assert '"critical:" + n.id' in POPUPS
    assert "return out.filter(g => g.items.length > 0);" in POPUPS
    assert (
        "model: stack.multi ? (stack.open ? stack.modelData.items : []) : stack.modelData.items"
        in POPUPS
    )
    grouping = section(POPUPS, "function groupPopups()", "function clearPopups()")
    assert "const out = [], byKey = {}, byName = {};" in grouping
    assert "g = (name && byName[name]) || (desktop && byName[desktop]);" in grouping
    assert "if (!critical) {" in grouping, "critical notices never join by name"


def test_tray_cap_and_drawer_are_still_wired():
    assert "readonly property int trayCap: 6" in BAR
    assert "trayShown: Array.from(SystemTray.items || []).slice(0, bar.trayCap)" in BAR
    assert "trayOverflow: Array.from(SystemTray.items || []).slice(bar.trayCap)" in BAR
    assert "visible: bar.trayOverflow.length > 0" in BAR
    assert "visible: bar.trayOpen && bar.trayOverflow.length > 0" in BAR
    assert "model: bar.trayOverflow" in BAR
    drawer = section(BAR, "component TrayButton: Item", "SystemClock {")
    assert "inDrawer: true" in drawer
    assert "it.hasMenu && trayMenu.open()" in drawer, "drawer icons keep their menus"
    assert "onShownChanged:" in BAR and "bar.trayOpen = false" in BAR


def test_switcher_app_grouping_is_still_wired():
    assert "property bool grouped: true" in SWITCHER
    assert "readonly property var groups: win.buildGroups()" in SWITCHER
    assert "model: win.grouped ? win.groups : win.list" in SWITCHER
    assert 'Tr.t("%1 windows", cell.windowCount)' in SWITCHER
    assert "e.key === Qt.Key_G" in SWITCHER
    assert "e.key === Qt.Key_Q && (e.modifiers & Qt.ShiftModifier)" in SWITCHER


# ---- pure logic: the cases a screenshot cannot stage ------------------------


def test_popups_from_one_app_fold_into_one_newest_first_stack():
    mails = [note(1, "Mail"), note(2, "Mail", desktop="org.kde.mail")]
    chat = note(3, "Messages")
    groups = group_popups([mails[0], chat, mails[1]])
    assert [g["key"] for g in groups] == ["org.kde.mail", "messages"]
    assert groups[0]["name"] == "Mail"
    # the notice without a desktop entry joins the one that had it
    assert [n["id"] for n in groups[0]["items"]] == [2, 1]


def test_critical_and_unnamed_notices_get_their_own_tiles():
    call = note(7, "Phone", critical=True)
    other = note(8, "")
    groups = group_popups([call, other, note(9, "")])
    assert [g["key"] for g in groups] == ["other", "critical:7"]
    assert len(groups[0]["items"]) == 2, "missing app names share one 'other' stack"
    assert groups[1]["items"] == [call]


def test_popup_cap_keeps_the_newest_four_even_when_one_app_floods():
    popups = []
    for i in range(7):
        popups = add_popup(popups, note(i, "Chat"))
    assert len(popups) == POPUP_CAP
    assert [n["id"] for n in popups] == [3, 4, 5, 6]
    assert len(group_popups(popups)) == 1
    assert len(group_popups(popups)[0]["items"]) == POPUP_CAP


def test_dismissing_one_card_shrinks_the_stack_and_an_empty_stack_disappears():
    popups = [note(1, "Mail"), note(2, "Mail")]
    assert len(group_popups(popups)[0]["items"]) == 2
    popups = drop_popup(popups, popups[0])
    assert len(group_popups(popups)[0]["items"]) == 1
    popups = drop_popup(popups, popups[0])
    assert group_popups(popups) == [], "no empty header left behind"


def test_dismissing_a_group_clears_every_card_and_its_open_state():
    popups = [note(1, "Mail"), note(2, "Mail"), note(3, "Chat")]
    groups = group_popups(popups)
    expanded = {groups[0]["key"]: True, groups[1]["key"]: True}
    left = dismiss_group(groups[0], expanded)
    assert all(n["dismissed"] for n in groups[0]["items"])
    assert not groups[1]["items"][0]["dismissed"], "another app is untouched"
    assert list(left) == [groups[1]["key"]]
    assert dismiss_group(groups[1], left) == {}


def test_tray_cap_math_needs_a_more_button_only_past_the_boundary():
    for count in (0, 1, TRAY_CAP):
        shown, overflow = tray_split([f"icon{i}" for i in range(count)])
        assert len(shown) == count and overflow == []
        assert bool(overflow) is False, "no '⋯' button for a tray that fits"
    shown, overflow = tray_split([f"icon{i}" for i in range(TRAY_CAP + 3)])
    assert len(shown) == TRAY_CAP
    assert overflow == [f"icon{i}" for i in range(TRAY_CAP, TRAY_CAP + 3)]
    assert shown + overflow == [f"icon{i}" for i in range(TRAY_CAP + 3)]


def test_switcher_collapses_windows_but_keeps_mru_order():
    mru = [
        {"id": 1, "app_id": "Foot"},
        {"id": 2, "app_id": "foot"},
        {"id": 3, "app_id": "Chrome"},
    ]
    groups = group_windows(mru)
    assert [g["key"] for g in groups] == ["foot", "chrome"]
    assert [w["id"] for w in groups[0]["windows"]] == [1, 2]
    assert sum(len(g["windows"]) for g in groups) == len(mru)
