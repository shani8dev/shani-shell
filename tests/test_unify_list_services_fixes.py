"""Uniform list rows and service singletons across the new apps.

There is no QML runtime in pytest, so these are static reads of the shipped
QML: the shared controls' contracts, the IRC window's delegates, and the five
service singletons' status vocabulary and Process result paths.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def block(text, start):
    """The `{ … }` body that follows a marker, by brace matching."""
    i = text.index("{", text.index(start))
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1 : j]
    raise AssertionError("unbalanced block after " + start)


def delegates(text):
    """(kind, body) for every `delegate: Kind { … }` in a QML file."""
    out = []
    for m in re.finditer(r"delegate:\s*(\w+)\s*\{", text):
        i = m.end() - 1
        depth = 0
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    out.append((m.group(1), text[i + 1 : j]))
                    break
    return out


LISTROW = source("shani/Common/ListRow.qml")
CHOICE = source("shani/Common/Choice.qml")
WINDOW = source("shani/Modules/Irc/IrcWindow.qml")
SERVICES = {
    name: source("shani/Services/%s.qml" % name)
    for name in ("Irc", "Health", "Vpn", "CloudSync", "Podcasts")
}


# ---- 1. shared row contract --------------------------------------------------


def test_listrow_forwards_columns_to_keyfocus():
    assert re.search(r"property int columns: 0", LISTROW)
    focus = block(LISTROW, "KeyFocus {")
    assert re.search(r"columns:\s*root\.columns", focus)
    assert "onActivated: root.clicked()" in focus


def test_listrow_selected_is_spoken_for_every_instance():
    # a StaticText role cannot carry selection: keep the ListItem role for all
    # instances so Accessible.selected is announced on value rows too
    assert "Accessible.role: Accessible.ListItem" in LISTROW
    assert "Accessible.role: interactive ?" not in LISTROW
    assert re.search(r"Accessible\.selected:\s*root\.selected", LISTROW)
    assert re.search(r"visible:\s*root\.selected", LISTROW)  # the check in the tail


# ---- 2. shared choice contract -----------------------------------------------


def test_choice_names_fall_back_to_text():
    assert re.search(r'property string accessibleName: ""', CHOICE)
    assert re.search(
        r"Accessible\.name:\s*root\.accessibleName !== \"\" \? root\.accessibleName : root\.text",
        CHOICE,
    )


def test_choice_keyboard_nav_reaches_every_usable_instance():
    focus = block(CHOICE, "KeyFocus {")
    assert "root.enabled && root.visible" in focus
    assert re.search(r"columns:\s*root\.columns", focus)
    assert "onActivated: root.clicked()" in focus


# ---- 3. the owned window's lists ---------------------------------------------


def test_irc_delegates_all_use_listrow_with_no_hand_rolled_mousearea():
    found = delegates(WINDOW)
    assert len(found) == 3
    for kind, body in found:
        assert kind == "ListRow", kind
        assert re.search(r"\btitle\s*:", body), "row has no title"
        assert "Accessible.name:" in body
        assert "Accessible.role:" in body
    assert "MouseArea {" not in WINDOW
    assert "RowLayout {" not in "\n".join(body for _, body in found)


def test_irc_channels_delegate_keeps_selection_unread_and_keyboard_contract():
    body = delegates(WINDOW)[0][1]
    for token in (
        "icon:",
        "title: modelData",
        "subtitle:",
        "trailing:",
        "selected: modelData === Irc.activeChannel",
        "onClicked: Irc.markRead(modelData)",
        "Accessible.role: Accessible.ListItem",
        "Irc.unread[modelData]",
        "Irc.mentions[modelData]",
    ):
        assert token in body, token


# ---- 4. uniform service status vocabulary ------------------------------------


@pytest.mark.parametrize("name", sorted(SERVICES))
def test_service_exposes_one_busy_guard_note_error_and_missing_tool(name):
    text = SERVICES[name]
    for prop in (
        "property bool busy:",
        "property string note:",
        "property string error:",
    ):
        assert re.search(prop, text), "%s: %s" % (name, prop)
    assert "not installed" in text, "%s: no graceful missing-tool answer" % name


@pytest.mark.parametrize("name", sorted(SERVICES))
def test_service_has_a_single_run_and_finished_entry_point(name):
    text = SERVICES[name]
    assert re.search(r"function run\(", text), name
    assert re.search(r"function finished\(", text), name
    assert len(re.findall(r"function run\(", text)) == 1, name
    assert len(re.findall(r"function finished\(", text)) == 1, name


def test_health_queues_on_one_guard_and_degrades_without_its_tool():
    text = SERVICES["Health"]
    assert "if (job.running || root.busy)" in text
    assert "code === 127" in text
    assert 'Tr.t("The health service is not installed")' in text


def test_vpn_runs_from_one_guard_and_finishes_through_one_handler():
    text = SERVICES["Vpn"]
    assert (
        "function invoke(cmd, args, subject) { return root.run(cmd, args, subject); }"
        in text
    )
    assert "if (root.busy) return false;" in block(text, "function run(")
    assert (
        "onExited: code => root.finished(root.pending, root.subject, code, vpnOut.text, vpnErr.text)"
        in text
    )
    done = block(text, "function finished(")
    assert "root.busy = false;" in done and 'root.pending = "";' in done
    assert 'Tr.t("nmcli is not installed")' in text


def test_cloudsync_funnels_daemon_events_through_finished():
    text = SERVICES["CloudSync"]
    assert "root.finished(e);" in block(text, "stdout: SplitParser {")
    done = block(text, "function finished(")
    assert (
        'if (e.event === "jobs") { root.jobs = e.jobs || []; root.busy = false; }'
        in done
    )
    assert 'root.note = e.message || "";' in done
    assert "root.busy = false;" in block(text, "onExited:")


def test_podcasts_and_irc_drain_busy_and_report_a_missing_tool():
    jobs = block(SERVICES["Podcasts"], "function run(")
    assert "root.busy = true;" in jobs
    pod = SERVICES["Podcasts"]
    assert "onExited: code => {\n            root.busy = false;" in pod
    assert "code === 127" in pod and 'Tr.t("The feed service is not installed")' in pod

    irc = SERVICES["Irc"]
    assert "root.busy = true;" in block(irc, "function connect()")
    assert "root.busy = false;" in block(irc, "onExited:")
    assert "code === 127" in irc and 'Tr.t("The IRC service is not installed")' in irc
