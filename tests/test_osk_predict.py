"""The screen keyboard's word engine (bridge/osk-predict.py), run for real."""
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bridge" / "osk-predict.py"
HAS_WORDS = Path("/usr/share/hunspell/en_US.dic").exists() or Path("/usr/share/dict/words").exists()


def ask(tmp_path, *reqs):
    env = {"XDG_DATA_HOME": str(tmp_path), "HOME": str(tmp_path), "PATH": "/usr/bin:/bin"}
    out = subprocess.run([sys.executable, str(TOOL)], input="".join(json.dumps(r) + "\n" for r in reqs),
                         capture_output=True, text=True, env=env, check=True, timeout=60).stdout
    return [json.loads(l) for l in out.splitlines()]


def test_completes_the_word_being_typed(tmp_path):
    [r] = ask(tmp_path, {"op": "suggest", "lang": "en", "word": "tom"})
    assert r["words"][0] == "tomorrow" and len(r["words"]) <= 3


@pytest.mark.skipif(not HAS_WORDS, reason="no system dictionary")
@pytest.mark.parametrize("typed,fixed", [
    ("teh", "the"), ("hte", "the"), ("helo", "hello"), ("recieve", "receive"),
    ("becuase", "because"), ("tommorow", "tomorrow"), ("wiht", "with"), ("adn", "and"),
])
def test_corrects_the_slips_people_make(tmp_path, typed, fixed):
    [r] = ask(tmp_path, {"op": "suggest", "lang": "en", "word": typed})
    assert r["correction"] == fixed


def test_a_known_word_is_never_corrected(tmp_path):
    [r] = ask(tmp_path, {"op": "suggest", "lang": "en", "word": "good"})
    assert r["correction"] is None


def test_learns_what_comes_next_and_keeps_it(tmp_path):
    ask(tmp_path, {"op": "learn", "lang": "en", "text": "see you tomorrow"})
    [r] = ask(tmp_path, {"op": "suggest", "lang": "en", "prev": "see you", "word": ""})
    assert r["words"] == ["tomorrow"]
    saved = json.loads((tmp_path / "shani-shell" / "osk-words-en.json").read_text())
    assert saved["bi"]["you"]["tomorrow"] == 1


def test_forget_wipes_what_was_learned(tmp_path):
    ask(tmp_path, {"op": "learn", "lang": "en", "text": "zyxwordz here"}, {"op": "forget"})
    assert not list((tmp_path / "shani-shell").glob("osk-words-*"))


def test_a_swipe_finds_the_word_along_its_path(tmp_path):
    # h → e → l → o, passing the keys between
    [r] = ask(tmp_path, {"op": "swipe", "lang": "en", "keys": "hgfdertyuioklo"})
    assert r["words"][0] == "hello"


def test_bad_input_does_not_stop_the_engine(tmp_path):
    out = ask(tmp_path, {"op": "nope"}, {"op": "suggest", "lang": "en", "word": "tom"})
    assert out[0]["error"] and out[1]["words"]
