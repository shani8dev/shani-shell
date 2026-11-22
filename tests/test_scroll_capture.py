"""bridge/scroll-capture.py: stitching a scrolling screenshot.

grim and slop are not in the test image, so what is pinned here is the part
that decides whether a long screenshot is any good: how much of one capture
duplicates the bottom of the previous one, and what the stitched image looks
like. Getting this wrong is a screenshot with a band repeated or lost - it does
not fail loudly, it just looks wrong.
"""

import random
import sys
from pathlib import Path

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import importlib.util

_spec = importlib.util.spec_from_file_location(
    "scroll_capture", ROOT / "bridge/scroll-capture.py"
)
sc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sc)


def document(width, height, seed=7):
    """A page where every row is its own colour. Random, not a pattern: a
    repeating colour would match rows that are not duplicates."""
    rnd = random.Random(seed)
    rows = [(rnd.randrange(256), rnd.randrange(256), 8) for _ in range(height)]
    img = Image.new("RGB", (width, height))
    px = img.load()
    for y, c in enumerate(rows):
        for x in range(width):
            px[x, y] = c
    return img


def capture(doc, top, height):
    """What a screenshot of the document from row `top` looks like."""
    out = Image.new("RGB", (doc.width, height))
    out.paste(doc.crop((0, top, doc.width, top + height)), (0, 0))
    return out


def save(img, path):
    img.save(path)
    return path


# ---- finding the overlap ---------------------------------------------------


def test_an_exact_overlap_is_found():
    doc = document(40, 400)
    a = capture(doc, 0, 200)  # document rows 0..199
    b = capture(doc, 180, 100)  # rows 180..279: 20 rows repeat
    assert sc.find_overlap(a, b) == 20


def test_no_overlap_is_zero():
    a = document(40, 100, seed=1)
    b = document(40, 100, seed=2)
    assert sc.find_overlap(a, b) == 0


def test_a_capture_entirely_within_the_previous_one_is_all_overlap():
    """Scrolled less than a screen: nothing new, so all of b repeats a."""
    doc = document(30, 200)
    a = capture(doc, 0, 100)
    b = capture(doc, 0, 100)
    assert sc.find_overlap(a, b) == 100


def test_a_capture_after_a_short_scroll_shares_most_of_itself():
    doc = document(30, 300)
    a = capture(doc, 0, 200)
    b = capture(doc, 20, 200)  # 180 of b's 200 rows repeat a
    assert sc.find_overlap(a, b) == 180


def test_different_widths_do_not_overlap():
    a = document(40, 100, seed=3)
    b = document(20, 100, seed=3)
    assert sc.find_overlap(a, b) == 0


def test_the_overlap_never_exceeds_the_shorter_capture():
    doc = document(20, 500)
    a = capture(doc, 0, 500)
    b = capture(doc, 480, 50)
    assert sc.find_overlap(a, b) <= 50


# ---- stitching -------------------------------------------------------------


def test_one_part_is_copied_through(tmp_path):
    p = save(document(30, 60), tmp_path / "a.png")
    out = tmp_path / "out.png"
    assert sc.stitch([p], out) is True
    with Image.open(out) as img:
        assert img.size == (30, 60)


def test_nothing_to_stitch_is_refused(tmp_path):
    assert sc.stitch([], tmp_path / "out.png") is False


def test_two_parts_with_no_overlap_are_stacked(tmp_path):
    a = save(document(30, 60, seed=4), tmp_path / "a.png")
    b = save(document(30, 40, seed=5), tmp_path / "b.png")
    out = tmp_path / "out.png"
    sc.stitch([a, b], out)
    with Image.open(out) as img:
        assert img.size == (30, 100)  # no rows shared, none removed


def test_a_stitched_pair_has_no_repeated_band(tmp_path):
    """The point of the whole thing: 180 shared rows come out once."""
    doc = document(30, 600)
    a = save(capture(doc, 0, 200), tmp_path / "a.png")
    b = save(capture(doc, 20, 200), tmp_path / "b.png")
    out = tmp_path / "out.png"
    sc.stitch([a, b], out)
    with Image.open(out) as img:
        assert img.size == (30, 220)  # 200 + 200 - 180 shared
        # row 200 of the result is document row 200 (the first new one)
        assert img.getpixel((0, 200))[:3] == tuple(doc.getpixel((0, 200))[:3])


def test_the_output_folder_is_made_if_it_is_missing(tmp_path):
    p = save(document(30, 40), tmp_path / "a.png")
    out = tmp_path / "deep" / "out.png"
    assert sc.stitch([p], out) is True
    assert out.exists()


# ---- the command line -------------------------------------------------------


def test_stitch_needs_parts(tmp_path):
    import subprocess

    out = tmp_path / "out.png"
    done = subprocess.run(
        [
            sys.executable,
            str(ROOT / "bridge/scroll-capture.py"),
            "stitch",
            str(tmp_path),
            str(out),
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.exists() is False  # it said no, it did not write junk
