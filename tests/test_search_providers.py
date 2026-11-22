"""bridge/search-providers.py: what the launcher shows from other apps.

The launcher's "what the apps found" section is this bridge: it reads
GNOME's SearchProvider2 .ini files and asks each app over D-Bus. What is
pinned here is the filtering, which is where a bad .ini would otherwise take
the whole search down: a provider of the wrong version, one turned off by
default, or one missing a field, is skipped - and two apps on the same bus
are only asked once.
"""

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import importlib.util

_spec = importlib.util.spec_from_file_location("search_providers", ROOT / "bridge/search-providers.py")
sp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sp)


class FakeApp:
    def __init__(self, name="Example", icon="example"):
        self._name = name
        self._icon = icon

    def get_name(self):
        return self._name

    def get_icon(self):
        return None


class FakeAppInfo:
    """Stands in for Gio.DesktopAppInfo: only the ids we wrote are found."""

    known = set()

    @staticmethod
    def new(desktop_id):
        return FakeApp() if desktop_id in FakeAppInfo.known else None


class FakeGio:
    """Only what providers() reaches for: a desktop id that is installed."""

    DesktopAppInfo = FakeAppInfo


@pytest.fixture
def providers(tmp_path, monkeypatch):
    d = tmp_path / "gnome-shell" / "search-providers"
    d.mkdir(parents=True)
    monkeypatch.setattr(sp, "DIRS", [str(d)])
    monkeypatch.setattr(sp, "Gio", FakeGio)

    def write(name, body):
        (d / name).write_text(body, encoding="utf-8")

    def good(
        desktop="Example.desktop",
        bus="org.example.Search",
        path="/org/example/Search",
        extra="",
    ):
        FakeAppInfo.known.add(desktop)
        write(
            f"{desktop[:-8]}.ini",
            "[Shell Search Provider]\n"
            f"DesktopId={desktop}\n"
            f"BusName={bus}\n"
            f"ObjectPath={path}\n" + extra,
        )

    return d, write, good


def names(got):
    return [b for _app, b, _p in got]


def test_a_good_ini_yields_a_provider(providers):
    _d, _w, good = providers
    good()
    assert names(sp.providers()) == ["org.example.Search"]


def test_version_one_is_skipped(providers):
    _d, _w, good = providers
    good(extra="Version=1\n")
    assert names(sp.providers()) == []


def test_default_disabled_is_skipped(providers):
    _d, _w, good = providers
    good(extra="DefaultDisabled=true\n")
    assert names(sp.providers()) == []


def test_a_desktop_id_that_is_not_installed_is_skipped(providers):
    d, write, good = providers
    good()
    # the .ini is there but nothing installed claims the desktop id
    FakeAppInfo.known.clear()
    assert names(sp.providers()) == []


@pytest.mark.parametrize("field", ["BusName", "ObjectPath", "DesktopId"])
def test_a_missing_field_is_skipped(providers, field):
    _d, write, _good = providers
    lines = [
        "[Shell Search Provider]",
        "DesktopId=Example.desktop",
        "BusName=org.example.Search",
        "ObjectPath=/org/example/Search",
    ]
    lines = [x for x in lines if not x.startswith(field + "=")]
    FakeAppInfo.known.add("Example.desktop")
    write("x.ini", "\n".join(lines) + "\n")
    assert names(sp.providers()) == []


def test_two_apps_on_one_bus_are_only_asked_once(providers):
    _d, write, good = providers
    good(desktop="One.desktop", bus="org.example.Search")
    good(desktop="Two.desktop", bus="org.example.Search")
    assert names(sp.providers()) == ["org.example.Search"]


def test_a_broken_ini_does_not_stop_the_others(providers):
    _d, write, good = providers
    write("a.ini", "not an ini at all\n")
    good(desktop="One.desktop", bus="org.example.One")
    assert names(sp.providers()) == ["org.example.One"]


def test_an_ini_without_the_section_is_skipped(providers):
    _d, write, good = providers
    write("a.ini", "[Something Else]\nBusName=org.example.X\n")
    assert names(sp.providers()) == []


def test_the_object_path_is_handed_back(providers):
    _d, _w, good = providers
    good(path="/org/example/Other")
    assert [p for _a, _b, p in sp.providers()] == ["/org/example/Other"]


# ---- the command line --------------------------------------------------------


def test_query_answers_json():
    """With nothing to ask, the answer is an empty list - never a traceback."""
    import subprocess

    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/search-providers.py"), "query", "zzz-nothing"],
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert out.returncode == 0
    assert isinstance(json.loads(out.stdout), list)


def test_an_unknown_command_is_refused():
    import subprocess

    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/search-providers.py"), "nonsense"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 2
    assert out.stderr.strip() != ""
