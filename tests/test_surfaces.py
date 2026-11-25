"""Every surface the shell loads is photographed by some harness (dev/surfaces.tsv).

The list of surfaces comes from shani/shell.qml, not from the harnesses: the
left rail (behind Settings.data.leftRail) was in no render for months because
coverage was counted from what the harnesses happened to capture.
"""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("surfaces", ROOT / "tools" / "surfaces.py")
assert spec is not None and spec.loader is not None
surfaces = importlib.util.module_from_spec(spec)
spec.loader.exec_module(surfaces)


def test_every_surface_is_catalogued_and_photographed():
    problems = surfaces.check()
    assert not problems, "\n".join(problems)


def test_the_code_list_finds_the_surfaces_behind_settings_and_state():
    code = surfaces.surfaces()
    assert code["LeftRail"] == "Settings.data.leftRail"
    assert code["AssistiveTouch"] == "Settings.data.assistiveTouch"
    for always in ("Bar", "Island", "Launcher", "Sidebar", "LockScreen", "Ring", "Switcher"):
        assert always in code, always
    assert len(code) > 100


def test_a_new_surface_without_a_capture_is_reported(monkeypatch):
    real = surfaces.surfaces
    monkeypatch.setattr(surfaces, "surfaces", lambda: {**real(), "BrandNewPanel": "Ui.brandNew"})
    assert any("BrandNewPanel" in p for p in surfaces.check())


def test_a_capture_no_harness_takes_is_reported(monkeypatch):
    real = surfaces.catalog
    monkeypatch.setattr(surfaces, "catalog",
                        lambda: {**real(), "LeftRail": (["left-rail-gone"], "")})
    assert any("left-rail-gone" in p for p in surfaces.check())
