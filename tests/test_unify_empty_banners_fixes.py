"""Static checks for uniform empty states, banners and status notes.

The shell has no QML runner in this test environment, so the five owned windows
and the two shared components are checked as text, like the other QML tests.
Every check guards one of the fixes: a window stops hand-rolling a state, the
two shared components speak the same token vocabulary, and no empty state is a
dead end.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


EMPTY = read("shani/Common/EmptyState.qml")
BANNER = read("shani/Common/InfoBanner.qml")
WINDOWS = {
    "cloud": read("shani/Modules/Cloud/CloudPanel.qml"),
    "vpn": read("shani/Modules/Vpn/VpnPanel.qml"),
    "health": read("shani/Modules/Health/HealthWindow.qml"),
    "irc": read("shani/Modules/Irc/IrcWindow.qml"),
    "restore": read("shani/Modules/Settings/SettingsSystemRestore.qml"),
}


def block_at(src, pos):
    """Return the balanced {...} object beginning at pos (QML as text)."""
    brace = src.index("{", pos)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[pos : i + 1]
    raise AssertionError("unbalanced object at %d" % pos)


def block(src, marker):
    return block_at(src, src.index(marker))


def empty_states(src):
    return [block_at(src, m.start()) for m in re.finditer(r"EmptyState \{", src)]


def text_blocks(src):
    return [block_at(src, m.start()) for m in re.finditer(r"(?m)^\s*Text \{", src)]


# ---- fix 1: the shared components use the same additive token names --------------


def test_shared_components_use_the_same_additive_tokens():
    for token in ("iconSize", "padding", "accessibleRole"):
        assert "property int %s:" % token in EMPTY, token
        assert "property int %s:" % token in BANNER, token
    # every text in both components scales with the large-text setting
    # (Theme.type() applies fontScale: docs/DESIGN.md)
    assert EMPTY.count("* Theme.fontScale") + EMPTY.count("Theme.type(") == 2
    assert BANNER.count("* Theme.fontScale") + BANNER.count("Theme.type(") == 2
    # tokens are really used, not just declared
    assert "spacing: root.padding" in EMPTY
    assert "size: root.iconSize" in EMPTY
    assert "margins: banner.padding" in BANNER
    assert BANNER.count("size: banner.iconSize") == 2
    assert "radius: banner.cornerRadius" in BANNER
    assert "property int cornerRadius: Theme.radius" in BANNER


# ---- fix 2: both shared components carry an accessible role and name -------------


def test_shared_components_expose_role_and_name_in_both_palettes():
    assert "Accessible.role: root.accessibleRole" in EMPTY
    assert (
        'Accessible.name: root.title.length ? root.title + ". " + root.subtitle'
        in EMPTY
    )
    assert "Accessible.role: banner.accessibleRole" in BANNER
    assert "Accessible.name: banner.title" in BANNER
    # colours come from Theme tokens, never a literal that breaks in light mode
    for component in (EMPTY, BANNER):
        assert "Theme.text" in component and "Theme.dim" in component
        assert not re.search(r"#[0-9a-fA-F]{3,8}", component)


# ---- fix 3: VPN error and note rows are banners -----------------------------------


def test_vpn_error_and_note_use_info_banner():
    vpn = WINDOWS["vpn"]
    assert 'objectName: "vpn-error"' in vpn and 'objectName: "vpn-note"' in vpn
    error = block(vpn, 'objectName: "vpn-error"')
    assert 'visible: Vpn.error !== ""' in error
    assert 'tone: "error"' in error
    assert 'Tr.t("Could not load VPN connections")' in error
    assert "color: Theme.danger" not in error
    note = block(vpn, 'objectName: "vpn-note"')
    assert "tone:" in note and "color: Theme.accent" not in note
    empty = block(vpn, 'objectName: "vpn-empty"')
    assert "actionText:" in empty and "subtitle:" in empty


# ---- fix 4: cloud window-level and per-job errors are banners ---------------------


def test_cloud_error_rows_use_info_banner():
    cloud = WINDOWS["cloud"]
    top = block(cloud, 'objectName: "cloud-error"')
    assert "!CloudSync.available" in top and "CloudSync.error" in top
    assert "win.notice" in top and 'tone: "error"' in top
    assert 'Tr.t("Could not sync")' in top
    row = block(cloud, 'objectName: "cloud-job-error"')
    assert "row.modelData.error" in row and 'tone: "error"' in row
    assert "color: Theme.danger" not in row


# ---- fix 5: health status rows are banners with a status-bar role -----------------


def test_health_status_rows_keep_the_statusbar_role():
    health = WINDOWS["health"]
    error = block(health, 'objectName: "health-error"')
    assert 'visible: Health.error !== ""' in error
    assert "accessibleRole: Accessible.StatusBar" in error
    assert 'Tr.t("Could not load health data")' in error
    note = block(health, 'objectName: "health-note"')
    assert "accessibleRole: Accessible.StatusBar" in note
    assert health.count("Accessible.role: Accessible.StatusBar") >= 2
    loading = block(health, 'objectName: "health-loading"')
    assert "actionText:" in loading


# ---- fix 6: IRC uses one banner for status/error and empty states for lists -------


def test_irc_status_error_and_three_empty_states_use_shared_components():
    irc = WINDOWS["irc"]
    assert 'objectName: "irc-status"' in irc and 'objectName: "irc-error"' in irc
    assert 'visible: Irc.error !== ""' in irc
    assert 'tone: Irc.status === "connected" ? "ok"' in irc
    assert irc.count("EmptyState {") >= 3
    for title in (
        "No channels — connect and join one",
        "No messages yet — say hello",
        "Connect and join a channel to start chatting",
    ):
        assert 'Tr.t("%s")' % title in irc, title
    # moving rows to components must not drop the names of the remaining controls
    assert irc.count("Accessible.name:") >= 8


# ---- fix 7: System Restore keeps its state markers while using the widgets --------


def test_system_restore_states_keep_markers_and_use_shared_components():
    panel = WINDOWS["restore"]
    for marker in (
        "system-restore-error",
        "system-restore-offline",
        "system-restore-empty",
        "system-restore-note",
        "system-restore-busy",
        "system-restore-action-error",
        "system-restore-no-dry-run",
    ):
        assert 'objectName: "%s"' % marker in panel, marker
    empty = block(panel, 'objectName: "system-restore-empty"')
    assert (
        'visible: !SystemRestore.loading && SystemRestore.error === "" && SystemRestore.slots.length === 0'
        in empty
    )
    assert 'Tr.t("Nothing yet")' in empty
    assert "actionText:" in empty
    assert panel.count("InfoBanner {") >= 5


# ---- fix 8: failures are announced with a consistent "Could not ..." title --------


def test_failure_vocabulary_is_consistent():
    phrases = {
        "vpn": "Could not load VPN connections",
        "cloud": "Could not sync",
        "health": "Could not load health data",
        "irc": "Could not connect",
        "restore": "Could not load slots",
    }
    for name, phrase in phrases.items():
        assert 'Tr.t("%s")' % phrase in WINDOWS[name], name
    assert 'Tr.t("Nothing yet")' in WINDOWS["restore"]
    assert sum('Tr.t("Try again")' in src for src in WINDOWS.values()) >= 2


# ---- fix 9: no empty state is a dead end -------------------------------------------


def test_every_empty_state_has_an_action_or_a_next_step():
    next_step = re.compile(
        r"subtitle:.*(Log|Import|Choose|Connect|Join|Refresh|below|conversation)"
    )
    for name, src in WINDOWS.items():
        for empty in empty_states(src):
            assert "actionText:" in empty or next_step.search(empty), (
                name,
                empty[:100],
            )


# ---- fix 10: no bare red/green status Text is left in the owned windows ------------


def test_no_hand_rolled_status_text_rows_remain():
    status_signals = (
        "Vpn.error",
        "Vpn.note",
        "CloudSync.error",
        "win.notice",
        "Health.error",
        "Health.note",
        "Irc.error",
        "SystemRestore.error",
        "SystemRestore.note",
        "SystemRestore.actionError",
    )
    for name, src in WINDOWS.items():
        for row in text_blocks(src):
            for signal in status_signals:
                assert not (
                    signal in row
                    and ("color: Theme.danger" in row or "color: Theme.accent" in row)
                ), (name, signal)


# ---- fix 11: the edited QML files stay clean --------------------------------------


def test_edited_qml_files_stay_clean():
    for rel, text in {
        "shani/Common/EmptyState.qml": EMPTY,
        "shani/Common/InfoBanner.qml": BANNER,
        **WINDOWS,
    }.items():
        assert text.endswith("\n"), rel
        assert "\t" not in text, rel
        assert "console.log" not in text, rel
