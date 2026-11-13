"""bridge/tidy.py: Downloads sorted by kind, never over a file, and undone exactly."""
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("tidy", ROOT / "bridge/tidy.py")
tidy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tidy)


def folder(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    d = tmp_path / "Downloads"
    d.mkdir()
    for name in ("photo.JPG", "report.pdf", "song.mp3", "app.AppImage", "notes.txt", "film.part", ".hidden.png", "weird.xyz"):
        (d / name).write_text(name)
    (d / "Pictures").mkdir()
    (d / "Pictures" / "photo.JPG").write_text("already there")
    return d


def test_plan_sorts_by_kind_and_never_over_a_file(tmp_path, monkeypatch):
    d = folder(tmp_path, monkeypatch)
    plan = {Path(m["from"]).name: (m["group"], Path(m["to"]).name) for m in tidy.plan(d)}
    assert plan["photo.JPG"] == ("Pictures", "photo (2).JPG")      # the name was taken
    assert plan["report.pdf"][0] == "Documents" and plan["notes.txt"][0] == "Documents"
    assert plan["song.mp3"][0] == "Music" and plan["app.AppImage"][0] == "Installers"
    # still downloading, hidden, or of no known kind: left where it is
    assert "film.part" not in plan and ".hidden.png" not in plan and "weird.xyz" not in plan


def test_apply_then_undo_puts_everything_back(tmp_path, monkeypatch):
    d = folder(tmp_path, monkeypatch)
    before = sorted(p.name for p in d.iterdir())
    assert tidy.apply(d)["moved"] == 5
    assert (d / "Documents" / "report.pdf").read_text() == "report.pdf"
    assert (d / "Pictures" / "photo.JPG").read_text() == "already there"
    assert tidy.undo()["restored"] == 5
    assert sorted(p.name for p in d.iterdir()) == before          # the empty folders it made are gone too
    assert not tidy.journal_file().exists()


def test_undo_does_not_write_over_a_file_that_came_since(tmp_path, monkeypatch):
    d = folder(tmp_path, monkeypatch)
    tidy.apply(d)
    (d / "report.pdf").write_text("a new download with the same name")
    got = tidy.undo()
    assert got["restored"] == 4 and got["left"] == 1
    assert (d / "report.pdf").read_text() == "a new download with the same name"
    assert json.loads(tidy.journal_file().read_text())["moves"][0]["from"].endswith("report.pdf")


def test_text_for_naming(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("Invoice  number 42\n\nfrom   Acme")
    assert tidy.text_of(f) == "Invoice number 42 from Acme"
    b = tmp_path / "b.bin"
    b.write_bytes(b"\x00\x01binary")
    assert tidy.text_of(b) == ""
