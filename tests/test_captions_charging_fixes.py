"""Static guards for CaptionBar / ChargeFx fixes found by reading the two
overlays (none of these specific defects are in docs/GAPS*.md).

Both are layer-shell surfaces with keyboardFocus None, so a live compositor is
needed to *see* them; each test instead pins the source wiring that fixes the
bug. No i18n catalog is edited here - only keys already in template.json are
used, and the last test enforces that.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAP = ROOT / "shani" / "Modules" / "Captions" / "CaptionBar.qml"
CHG = ROOT / "shani" / "Modules" / "Charging" / "ChargeFx.qml"


def read(path):
    return path.read_text(encoding="utf-8")


def section(src, start, stop):
    """Text between two landmarks, so a fix cannot hide elsewhere in the file."""
    return src.split(start, 1)[1].split(stop, 1)[0]


def test_caption_shows_the_two_newest_chunks():
    """ElideLeft is ignored with wrapMode: Wrap (Qt docs), so the third buffered
    chunk pushed the two on-screen lines up and the newest caption was clipped."""
    t = read(CAP)
    cap = section(
        t, "        Text {\n            anchors.fill: parent", "        }\n    }"
    )
    assert 'Captions.lines.slice(-2).join(" ")' in cap
    assert "Captions.lines.length ?" in cap
    # the misleading elide is gone: it never worked with wrapped text
    assert "elide: Text.ElideLeft" not in t


def test_caption_status_label_cannot_overflow_the_card():
    """A raw stderr line is unbounded; pin width + right elide + one line."""
    t = read(CAP)
    status = section(
        t,
        "            Text {\n                // keep a long",
        "        }\n        Text {",
    )
    assert "width: blurCard.width - 36" in status
    assert "elide: Text.ElideRight" in status
    assert "maximumLineCount: 1" in status


def test_caption_error_does_not_outrank_live_captions():
    """pulseaudio writes warnings to stderr routinely; once a caption arrives
    the red error label used to stay up forever and hide the real status."""
    t = read(CAP)
    status = section(
        t,
        "            Text {\n                // keep a long",
        "        }\n        Text {",
    )
    assert status.count("Captions.error && !Captions.text") == 2  # text + color
    assert "text: Captions.error ?" not in status
    assert "color: Captions.error ?" not in status


def test_charging_card_does_not_claim_charging_when_full():
    t = read(CHG)
    label = section(
        t, "            // plugging in an already-full", "            color: Theme.dim"
    )
    assert 'Power.full ? Tr.t("Full")' in label
    # the old binding said "Charging" for FullyCharged
    assert (
        'text: Power.charging && Power.timeLeft ? Power.timeLeft : Tr.t("Charging")'
        not in t
    )


def test_charging_card_has_an_accessible_name():
    t = read(CHG)
    card = section(t, "        strong: true", "        opacity: win.shown ? 1 : 0")
    assert "Accessible.role: Accessible.AlertMessage" in card
    assert "Accessible.name:" in card
    assert 'Power.full ? Tr.t("Full") : Tr.t("Charging")' in card


def test_new_translations_are_not_introduced_here():
    """The catalogs are owned by another change; only existing keys are safe."""
    template = json.loads(
        (ROOT / "shani" / "i18n" / "template.json").read_text(encoding="utf-8")
    )
    for path in (CAP, CHG):
        for key in re.findall(r'Tr\.t\("([^"]+)"\)', read(path)):
            assert key in template, f"{path.name}: new Tr.t key {key!r}"
