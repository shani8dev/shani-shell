"""Software gaps: ODRS, featured, versions, add-ons, repositories."""

import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge"


def read(rel):
    return (ROOT / rel).read_text()


def load(name):
    import importlib.machinery
    import importlib.util

    loader = importlib.machinery.SourceFileLoader(name, str(BRIDGE / (name + ".py")))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(mod)
    return mod


def test_odrs_ratings_are_in_the_bridge_and_the_app_page():
    b = read("bridge/appstore.py")
    assert "def rating(app_id" in b and "ratingCount" in b
    assert "odrs.gnome.org/1.0/reviews/api/reviews/" in b
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "appCol.a.ratingCount" in w and "appCol.a.reviews" in w


def test_featured_picks_and_addons():
    b = read("bridge/appstore.py")
    assert "FEATURED_IDS" in b and "def featured()" in b
    assert '"type": "addon"' in b and "def addons(app_id" in b
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "win.loadFeatured()" in w and '"repositories"' in w


def test_version_history_and_age_warning():
    b = read("bridge/appstore.py")
    assert '"releases": releases[:8]' in b and "ageDays" in b
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "appCol.a.releases" in w and "appCol.a.ageDays > 730" in w


def test_repository_enable_disable():
    b = read("bridge/appstore.py")
    assert "remote-modify" in b and "--enable" in b and '"remote-toggle"' in b
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "win.toggleRemote(" in w and "win.loadRemotes()" in w


def test_rating_averages_reviews_without_network(tmp_path):
    os.environ["SHANI_ODRS"] = str(tmp_path / "odrs.json")
    try:
        (tmp_path / "odrs.json").write_text(
            json.dumps(
                [
                    {"rating": 5, "summary": "great", "review": "works"},
                    {"rating": 3, "summary": "ok", "review": "fine"},
                ]
            )
        )
        appstore = load("appstore")
        r = appstore.rating("org.example.App")
        assert r["rating"] == 4.0 and r["ratingCount"] == 2
    finally:
        os.environ.pop("SHANI_ODRS", None)
