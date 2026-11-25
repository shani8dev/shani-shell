"""Catch renders where a surface never actually came up.

The render harness (dev/render.sh) waits on the shell's state key before it
photographs a surface.  An IPC can set that key while the window never draws —
`shani app` flags `Ui.dictionary`, for instance, but a broken LazyLoader leaves
only the wallpaper on screen.  The shot is then logged PASS and the PNG is
indistinguishable from the desktop, so a human scrolling the contact sheet is
the only thing that notices.

This test looks at the pixels instead of the log.  For every shot that is meant
to show a window or a full panel, it compares the centre of the frame with the
plain-desktop reference (`01-desktop-rest.png`).  A frame whose centre is
effectively the wallpaper never showed the surface it claims to show.

The separation is wide: real surfaces differ by >= 40 mean channel values,
blank ones by < 1.  The threshold of 12 sits in the empty middle.

Opt-in: set SHANI_RENDER_CHECK=1 after `sh dev/check.sh render=shell` to run
these.  Plain `pytest` skips them so the unit suite stays independent of
whether render artifacts happen to be on disk:

    SHANI_RENDER_CHECK=1 python3 -m pytest -q tests/test_render_surfaces.py

Needs Pillow and numpy (already used by the render harness image checks).
"""

import os
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
RENDER_DIR = ROOT / "out/renders/shell"
REF = RENDER_DIR / "01-desktop-rest.png"

# surface-name prefixes that must draw a window/panel in the middle of the
# screen. Desktop-only, island, OSD, notification, dock and control-centre
# shots are deliberately excluded: their subject is not a centred window.
SURFACE = re.compile(
    r"^\d+-(app-|media-|clocks-|quick-look|settings-|launcher-|overview-)"
)

# mean abs channel difference from the desktop centre. Blank = ~0.4, real = >=40.
BLANK_THRESHOLD = 12.0

# fraction of the frame used for the comparison (the window/panel centre).
Y0, Y1 = 0.15, 0.85
X0, X1 = 0.22, 0.78
SIZE = (96, 54)


def _center(path, reference):
    from PIL import Image
    import numpy as np

    def crop(p):
        im = Image.open(p).convert("RGB").resize(SIZE)
        a = np.asarray(im, dtype=np.int16)
        return a[
            int(SIZE[1] * Y0) : int(SIZE[1] * Y1), int(SIZE[0] * X0) : int(SIZE[0] * X1)
        ]

    return float(np.abs(crop(reference) - crop(path)).mean())


@pytest.fixture(scope="module")
def frames():
    if os.environ.get("SHANI_RENDER_CHECK") != "1":
        pytest.skip("render check is opt-in — set SHANI_RENDER_CHECK=1")
    pytest.importorskip("PIL")
    pytest.importorskip("numpy")
    if not REF.exists() or not any(RENDER_DIR.glob("*.png")):
        pytest.skip("no render artifacts — run `sh dev/check.sh render=shell` first")
    return sorted(
        p for p in RENDER_DIR.glob("*.png") if SURFACE.match(p.name) and p != REF
    )


def test_surface_frames_show_a_surface(frames):
    """No surface shot may be visually just the plain desktop."""
    blank = [(p.name, _center(p, REF)) for p in frames]
    blank = [(name, d) for name, d in blank if d < BLANK_THRESHOLD]
    assert not blank, (
        "surfaces never came up (IPC set the state, window never drew): "
        + ", ".join(f"{name} ({d:.1f})" for name, d in blank)
    )


def test_media_playing_shows_the_player():
    """The one shot the harness already flags is also visually blank.

    Keeping this explicit documents the known failure and pins the expected
    name, so a future harness fix can flip both together.
    """
    if os.environ.get("SHANI_RENDER_CHECK") != "1":
        pytest.skip("render check is opt-in — set SHANI_RENDER_CHECK=1")
    shot = RENDER_DIR / "170-media-playing.png"
    if not shot.exists():
        pytest.skip("no render artifacts")
    assert _center(shot, REF) >= BLANK_THRESHOLD, (
        "170-media-playing.png is still the plain desktop — the media page "
        "never came up"
    )
