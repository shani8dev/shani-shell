"""Pass-19 archive-safety leftovers (static checks: Quickshell needs a session).

1. a bomb / no-space preflight runs before any extraction,
2. a create password needs confirmation and a minimum length before Create,
3. a requested password for a tar format is refused, not silently dropped.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARCHIVE = ROOT / "shani/Services/Archive.qml"
WINDOW = ROOT / "shani/Modules/Archives/ArchivesWindow.qml"


def body(src, header, close="\n    }"):
    return src.split(header, 1)[1].split(close, 1)[0]


def test_bomb_and_disk_guard_runs_before_extraction():
    qml = ARCHIVE.read_text()

    # extract() only probes the destination's free space and the archive size;
    # the actual extractor is started later, from extractNow()
    probe = body(qml, "function extract(where) {")
    assert 'df -PB1 -- "$1"' in probe
    assert 'stat -c %s -- "$2"' in probe
    assert "spaceProbe.running = true" in probe
    assert "extractor.running = true" not in probe

    guard = qml.split("id: spaceProbe", 1)[1].split("function extractNow", 1)[0]
    assert "root.totalSize" in guard  # cumulative expected size is enforced
    assert "exp > free" in guard  # refuses when disk is full
    assert "exp > arc * 100" in guard  # refuses a tiny-archive/big-payload bomb
    assert "root.extractNow(root.probeWhere)" in guard
    assert 'Tr.t("Not enough free space' in qml
    assert (
        'Tr.t("Refusing to extract: this archive looks like a decompression bomb")'
        in qml
    )
    assert "extractor.running = true" in body(qml, "function extractNow(where) {")

    # closing the window while probing must not start an extraction afterwards
    cancel = body(qml, "function cancel() {")
    assert "spaceProbe.running = false" in cancel
    assert "root.probeThenExtract = false" in cancel


def test_create_password_needs_confirmation_and_a_minimum():
    qml = WINDOW.read_text()
    assert "id: archPassConfirm" in qml
    assert 'placeholder: Tr.t("Confirm password")' in qml

    ok = qml.split("readonly property bool passOk:", 1)[1].split("\n\n", 1)[0]
    assert "archPass.text.length >= 4" in ok
    assert "archPass.text === archPassConfirm.text" in ok
    hint = qml.split("readonly property string passHint:", 1)[1].split("\n\n", 1)[0]
    assert 'Tr.t("Password must be at least 4 characters")' in hint
    assert 'Tr.t("Passwords do not match")' in hint

    assert "enabled: !Archive.creating && win.passOk" in qml
    assert "win.clearPass()" in qml  # no secret left in the UI or Archive.newPass


def test_password_for_a_tar_format_is_refused():
    qml = ARCHIVE.read_text()
    create = body(qml, "function create(given, ext, name, pass) {")
    refusal = create.split('if (pw && ext !== "zip" && ext !== "7z")', 1)[1]
    assert 'Tr.t("A password cannot protect a tar archive' in refusal
    assert "return;" in refusal
    # the refusal happens before the archive is started or its options built
    assert create.index('ext !== "7z"') < create.index("root.creating = true")
    assert create.index('ext !== "7z"') < create.index("const opts =")
