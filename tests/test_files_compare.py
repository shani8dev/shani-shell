"""bridge/files.py compare (Meld parity): two texts line by line, two folders by
what is only in one and what differs (looking inside sub-folders), two other
files by whether they are the same."""
import json
import subprocess
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "files.py"


def cmp(a, b):
    return json.loads(subprocess.run([sys.executable, str(BRIDGE), "compare", str(a), str(b)], capture_output=True, text=True).stdout)


def test_two_texts(tmp_path):
    a = tmp_path / "a.txt"; a.write_text("one\ntwo\nthree\nfour\n")
    b = tmp_path / "b.txt"; b.write_text("one\nTWO\nthree\nfour\nfive\n")
    r = cmp(a, b)
    assert r["kind"] == "text" and r["changes"] == 2
    rows = [(x["tag"], x["l"], x["r"]) for x in r["rows"]]
    assert rows == [("equal", "one", "one"), ("replace", "two", "TWO"), ("equal", "three", "three"),
                    ("equal", "four", "four"), ("insert", None, "five")]
    assert r["rows"][4]["rn"] == 5 and r["rows"][4]["ln"] == 0


def test_two_folders(tmp_path):
    a = tmp_path / "a"; b = tmp_path / "b"
    for d in (a, b):
        (d / "sub").mkdir(parents=True); (d / "same.txt").write_text("x")
    (a / "sub" / "x.txt").write_text("1"); (b / "sub" / "x.txt").write_text("2")
    (a / "left.txt").write_text(""); (b / "right.txt").write_text("")
    r = cmp(a, b)
    assert r["kind"] == "folders"
    assert {(x["path"], x["state"]) for x in r["rows"]} == {("left.txt", "only-left"), ("right.txt", "only-right"), ("sub/x.txt", "differs")}


def test_binaries_and_mixed(tmp_path):
    a = tmp_path / "a.bin"; a.write_bytes(b"\0\1\2"); b = tmp_path / "b.bin"; b.write_bytes(b"\0\1\2")
    assert cmp(a, b) == {"kind": "binary", "same": True}
    b.write_bytes(b"\0\1\3")
    assert cmp(a, b)["same"] is False
    assert "error" in cmp(a, tmp_path)
