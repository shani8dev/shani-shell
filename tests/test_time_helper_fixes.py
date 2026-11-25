"""One seconds-to-clock helper (Common/Time.js) instead of five hand-rolled ones.

The helper is plain JS with `.pragma library`, so node executes it directly —
the only way to check the boundary cases a QML label cannot show. The QML
surfaces cannot run under pytest here, so each site is checked on source:
it imports the helper, uses it, kept its binding and font, and names the
bare duration labels for assistive technology.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TIME_JS = ROOT / "shani/Common/Time.js"
SITES = {
    "media": ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml",
    "desktop": ROOT / "shani/Modules/Background/DesktopWidgets.qml",
    "sidebar": ROOT / "shani/Modules/ControlCenter/SidebarNowPlaying.qml",
    "quicklook": ROOT / "shani/Modules/QuickLook/QuickLookSheet.qml",
    "player": ROOT / "shani/Modules/MediaPlayer/OtherPlayersPage.qml",
}
SRC = {name: path.read_text(encoding="utf-8") for name, path in SITES.items()}

NODE = shutil.which("node") or shutil.which("nodejs")
node_mark = pytest.mark.skipif(NODE is None, reason="node is not installed")


@pytest.fixture(scope="module")
def js():
    """The helper with `.pragma library` dropped, as a plain script."""
    body = TIME_JS.read_text(encoding="utf-8")
    return "\n".join(
        line for line in body.splitlines() if not line.startswith(".pragma")
    )


@node_mark
def call(js, fn, seconds):
    """One helper call, returned as JSON."""
    prog = (
        js + "\nconsole.log(JSON.stringify(" + fn + "(" + json.dumps(seconds) + ")));\n"
    )
    out = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


# ---- the helper ------------------------------------------------------------


def test_helper_is_a_pragma_library():
    body = TIME_JS.read_text(encoding="utf-8")
    assert body.splitlines()[0].strip() == ".pragma library"
    for fn in ("clock", "clockLong", "duration"):
        assert "function " + fn + "(seconds)" in body
    assert "Math.floor" in body and 'padStart(2, "0")' in body


@node_mark
@pytest.mark.parametrize(
    "seconds,want",
    [
        (0, "0:00"),
        (5, "0:05"),
        (59, "0:59"),
        (60, "1:00"),
        (61, "1:01"),
        (65.9, "1:05"),
        (3599, "59:59"),
        (3600, "60:00"),
    ],
)
def test_clock(js, seconds, want):
    assert call(js, "clock", seconds) == want


@node_mark
@pytest.mark.parametrize(
    "seconds,want",
    [
        (0, "0:00"),
        (59, "0:59"),
        (3599, "59:59"),
        (3600, "1:00:00"),
        (3661, "1:01:01"),
        (7322, "2:02:02"),
    ],
)
def test_clock_long_adds_hours_past_an_hour(js, seconds, want):
    assert call(js, "clockLong", seconds) == want


@node_mark
@pytest.mark.parametrize(
    "seconds,want",
    [
        (0, "0-00-00"),
        (5, "0-00-05"),
        (65, "0-01-05"),
        (3600, "1-00-00"),
        (3661, "1-01-01"),
    ],
)
def test_duration_keeps_the_frame_stamp_format(js, seconds, want):
    assert call(js, "duration", seconds) == want


@node_mark
def test_missing_seconds_are_zero(js):
    assert call(js, "clock", None) == "0:00"
    assert call(js, "clockLong", None) == "0:00"
    assert call(js, "duration", None) == "0-00-00"


# ---- the five sites --------------------------------------------------------


def test_every_site_imports_the_helper():
    for name, src in SRC.items():
        assert 'import "../../Common/Time.js" as Time' in src, name


def test_no_hand_rolled_formatter_survives():
    for name, src in SRC.items():
        assert 'padStart(2, "0")' not in src, name
        assert '+ ":" + String(' not in src, name
        assert ' + "-" + String(' not in src, name
    assert "function fmt(s)" not in SRC["desktop"]
    assert "function fmt(s)" not in SRC["player"]


@pytest.mark.parametrize(
    "name,expr,count",
    [
        ("media", "Time.duration(", 1),
        ("desktop", "Time.clock(", 2),
        ("sidebar", "Time.clock(", 2),
        ("sidebar", "Time.clockLong(", 2),
        ("quicklook", "Time.clock(", 2),
        ("player", "Time.clock(", 3),
    ],
)
def test_each_site_calls_the_helper(name, expr, count):
    assert SRC[name].count(expr) == count


def test_surrounding_bindings_and_fonts_are_kept():
    assert "text: Time.clock(mediaWin.player ? mediaWin.shown : 0)" in SRC["desktop"]
    assert "font.family: Theme.mono" in SRC["desktop"]
    assert "Time.clockLong(np.shown)" in SRC["sidebar"]
    assert '+ " / " + Time.clockLong(len)' in SRC["sidebar"]
    assert (
        "text: player.duration > 0 ? Time.clock(player.position / 1000)"
        in SRC["quicklook"]
    )
    assert '+ " / " + Time.clock(player.duration / 1000) : ""' in SRC["quicklook"]
    assert "font.family: Theme.font" in SRC["quicklook"]
    assert 'text: win.player ? Time.clock(win.shown) : "0:00"' in SRC["player"]
    assert "win.fmtRemaining(win.shown, seek.len)" in SRC["player"]
    assert "function fmtRemaining(pos, len)" in SRC["player"]
    assert "Math.max(0, len - pos)" in SRC["player"]


@pytest.mark.parametrize(
    "name,names",
    [
        ("desktop", ("Elapsed %1", "Total %1")),
        ("sidebar", ("Elapsed %1", "Total %1")),
        ("quicklook", ("Position %1",)),
        ("player", ("Elapsed %1", "Remaining %1", "Total %1")),
    ],
)
def test_bare_duration_labels_are_named(name, names):
    for readable in names:
        assert 'Accessible.name: Tr.t("' + readable + '").arg(text)' in SRC[name], (
            name,
            readable,
        )
