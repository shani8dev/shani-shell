"""Static guards for five new Logs / Quick Look fixes.

Both surfaces are driven by live processes (journalctl, MediaPlayer) that the
suite cannot start, so each test pins the wiring in the QML source instead.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG = "shani/Modules/Logs/LogsPanel.qml"
QUICK = "shani/Modules/QuickLook/QuickLookSheet.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_logs_follow_does_not_restart_a_slow_read():
    """A 3 s tick used to restart a still-running journalctl; the older read's
    finish then landed last and replaced fresh rows with stale ones."""
    q = read(LOG)
    fn = q.split("function readJournal() {")[1].split("onVisibleChanged")[0]
    assert "if (!win.visible || journal.running)" in fn
    assert fn.index("journal.running") < fn.index("win.loading = true")


def test_logs_failure_is_not_reported_as_an_empty_journal():
    """stdout's "empty" used to mask a non-zero exit, so a failed read said
    "The journal is empty right now" instead of "could not be read"."""
    q = read(LOG)
    stdout = q.split("stdout: StdioCollector {")[1].split("stderr:")[0]
    # a specific stderr error wins over the generic "empty" marker
    assert (
        'win.journalError = win.journalError || (out.length ? "" : "empty")' in stdout
    )
    exited = q.split("onExited: code => {")[1].split(
        "Item { anchors.fill: parent; focus: win.visible"
    )[0]
    assert (
        'code !== 0 && (win.journalError === "" || win.journalError === "empty")'
        in exited
    )
    assert 'win.journalError = "unreadable"' in exited


def test_logs_zero_search_matches_are_explained():
    """Filtering to nothing left a blank list with only "0 shown" in the
    footer; that is not the same state as an empty journal."""
    q = read(LOG)
    assert 'Tr.t("No entries match this filter")' in q
    assert (
        "visible: win.shown.length === 0 && win.entries.length > 0 && !win.loading" in q
    )
    # the genuine empty-journal state stays as it was
    assert "visible: win.entries.length === 0 && !win.loading" in q


def test_quicklook_pdf_page_url_is_percent_encoded():
    """The preview image encoded the file path per segment, but the rendered
    PDF page was concatenated raw, so '#'/'?' in a cache path broke it."""
    q = read(QUICK)
    assert (
        'function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }'
        in q
    )
    assert (
        'readonly property string url: QuickLook.path ? fileUrl(QuickLook.path) : ""'
        in q
    )
    assert 'QuickLook.kind === "pdf" ? fileUrl(QuickLook.page) : win.url' in q
    assert '"file://" + QuickLook.page' not in q


def test_quicklook_play_pause_is_reachable_by_key_and_assistive_tech():
    """Video's play/pause was a bare MouseArea (silent to AT and off the tab
    order); audio's had AT but no keyboard focus."""
    q = read(QUICK)
    assert q.count('Accessible.name: Tr.t("Play or pause")') >= 2
    assert q.count("Accessible.onPressAction: player.playbackState") >= 2
    assert q.count('KeyFocus { name: Tr.t("Play or pause")') >= 2
    assert "MouseArea { anchors.fill: parent; onClicked: player.playbackState" not in q
