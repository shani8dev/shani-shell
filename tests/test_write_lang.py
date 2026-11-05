"""Handwriting's language (shani/Services/WriteLang.js): the screen keyboard's language,
hand-made or an xkb layout, to the Tesseract data the image ships. Run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Services" / "WriteLang.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def tess(ids):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(%s.map(tesseractLang)));" % json.dumps(ids)
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def test_the_hand_made_and_short_ids():
    ids = ["en", "mr", "hi", "ta", "te", "bn", "gu", "kn", "ml", "pa", "or", "ur", "sa", "de", "fr", "es"]
    assert tess(ids) == ["eng", "mar", "hin", "tam", "tel", "ben", "guj", "kan", "mal", "pan", "ori", "urd", "san", "deu", "fra", "spa"]


def test_the_xkb_layouts_of_those_languages():
    ids = ["in", "in+bolnagri", "in+hin-wx", "in+marathi", "in+mar-kagapa", "in+tam", "in+tamilnet", "lk+tam_unicode",
           "in+tel-sarala", "in+ben_probhat", "bd", "bd+probhat", "in+guj", "in+kan-kagapa", "in+mal_lalitha",
           "in+guru", "in+jhelum", "in+ori-wx", "in+urd-phonetic", "pk", "pk+urd-crulp", "in+san-kagapa"]
    assert tess(ids) == ["hin", "hin", "hin", "mar", "mar", "tam", "tam", "tam", "tel", "ben", "ben", "ben", "guj", "kan", "mal",
                         "pan", "pan", "ori", "urd", "urd", "urd", "san"]


def test_anything_else_is_english():
    assert tess(["ru", "pk+snd", "in+sat", "in+eng", "np"]) == ["eng", "eng", "eng", "eng", "eng"]
