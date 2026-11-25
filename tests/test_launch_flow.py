"""The OPEN/LAUNCH flow is one path, not one per surface.

Static hooks pin the wiring that needs a running shell; the mapping and route
rules are lifted out of the QML and run in node, so these tests exercise the
very functions the surfaces use instead of a Python copy of them:

  * app name -> launcher folder (AppGrid) and chip (Launcher),
  * launcher settings deep links -> every Settings category,
  * launcher / Quick Look file hits -> Files' own route dispatcher.

The files with concurrent work (shell.qml, ShellApps.js, bin/shani) are read
only here.
"""

import importlib.machinery
import importlib.util
import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
APPGRID = SHANI / "Modules/Launcher/AppGrid.qml"
LAUNCHER = SHANI / "Modules/Launcher/Launcher.qml"
ACTIONS = SHANI / "Modules/Launcher/LauncherActions.qml"
ENTRIES = SHANI / "Services/LauncherEntries.qml"
SHEET = SHANI / "Modules/QuickLook/QuickLookSheet.qml"
FILES = SHANI / "Services/Files.qml"
SETTINGS = SHANI / "Modules/Settings/SettingsPage.qml"
PANEL = SHANI / "Modules/Files/FilesPanel.qml"
SHELLAPPS = SHANI / "Services/ShellApps.js"
NODE = shutil.which("node") or shutil.which("nodejs")


def read(path):
    return Path(path).read_text(encoding="utf-8")


def qml_function(text, name):
    """One function's verbatim source, from its signature to its closing brace."""
    m = re.search(r"\n    function " + re.escape(name) + r"\(", text)
    assert m, name
    start = text.index("{", m.start())
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() + 1 : i + 1]
    raise AssertionError("unclosed function " + name)


def call(js, expr):
    r = subprocess.run(
        [NODE, "-e", js + "\nconsole.log(JSON.stringify(" + expr + "));\n"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout.strip().splitlines()[-1])


def cli_apps():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
    module = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("shani_cli", loader)
    )
    loader.exec_module(module)
    return module.APPS


# ---- 1. app name -> category ---------------------------------------------------


def grid_logic():
    src = read(APPGRID)
    folders = re.search(r"readonly property var folders: (\[[^\]]*\])", src).group(1)
    aliases = "{" + re.search(r"folderAliases: \(\{([^}]*)\}\)", src).group(1) + "}"
    return (
        "var root = { folders: "
        + folders
        + ", folderAliases: "
        + aliases
        + ", tags: {} };\n"
        + qml_function(src, "folderOf")
        + "\n"
        + qml_function(src, "tagsOf")
        + "\n"
    )


def test_no_dead_app_folder_chip():
    """Every chip the launcher draws must be able to match a real app."""
    chips = json.loads(
        re.search(
            r"readonly property var categories: (\[[^\]]*\])", read(LAUNCHER)
        ).group(1)
    )
    labels = dict(
        re.findall(
            r'(\w+):\s*"([^"]+)"',
            "{"
            + re.search(r"categoryNames: \(\{([^}]*)\}\)", read(LAUNCHER)).group(1)
            + "}",
        )
    )
    assert "All" in chips
    # the chip ids are freedesktop categories; "Internet" is only a label
    assert "Network" in chips and "Internet" not in chips
    assert labels.get("Network") == "Internet"

    categories = set()
    for spec in cli_apps().values():
        categories.update(
            c.strip().rstrip(";") for c in spec[4].split(";") if c.strip()
        )
    # Game is a standard freedesktop folder for the person's own games, not a
    # shell app; every other chip must name a category a shipped app declares.
    assert set(chips) - {"All", "Game"} <= categories, (
        set(chips) - {"All", "Game"} - categories
    )


def test_network_apps_land_in_the_internet_folder():
    js = grid_logic()
    # freedesktop says "Network"; the folder the eye looks in says "Internet"
    network_apps = [s for s in cli_apps().values() if "Network" in s[4].split(";")]
    assert len(network_apps) >= 2
    for spec in network_apps:
        app = {"id": spec[0], "categories": [c for c in spec[4].split(";") if c]}
        assert call(js, "folderOf(" + json.dumps(app) + ")") == "Internet", spec[1]
    # an aliased category is not also left as a stray free-form tag
    tags = call(
        js, 'tagsOf({"id": "dev.shani.Mail", "categories": ["Network", "MyTag"]})'
    )
    assert "Network" not in tags and "MyTag" in tags


def test_shell_window_names_still_map_to_one_desktop_id():
    """The title a window carries has to resolve to the entry the dock pins."""
    text = read(SHELLAPPS)
    ids = json.loads(re.search(r"var ids = (\{.*?\});", text, re.S).group(1))
    table = {s[1]: s[0] for s in cli_apps().values()}
    assert ids == table
    assert 'var at = t.lastIndexOf(" \\u2014 ")' in text


# ---- 2. deep-link keyword coverage --------------------------------------------


def settings_categories():
    block = re.search(
        r"readonly property var cats: (\[[^\n]*\])", read(SETTINGS)
    ).group(1)
    return re.findall(r'id: "([a-z]+)"', block)


def settings_links():
    block = re.search(r"settingsLinks: \[(.*?)\n    \]", read(ENTRIES), re.S).group(1)
    return re.findall(
        r'\{\s*id: "([a-z]+)",\s*label: "([^"]+)",\s*words: "([^"]+)",\s*icon: "([^"]+)"\s*\}',
        block,
    )


def generated_and_explicit_links():
    out = {cat: "" for cat, _label, _words, _icon in settings_links()}
    for cat in re.findall(r'openSettings\("([a-z]+)"\)', read(ACTIONS)):
        out[cat] = out.get(cat, "")
    return out


def test_every_settings_category_has_a_launcher_deep_link():
    links = generated_and_explicit_links()
    missing = [c for c in settings_categories() if c not in links]
    assert missing == [], "unreachable settings categories: " + ", ".join(missing)
    # the generated half must really be generated, not a second hand-written list
    assert "LauncherEntries.settingsLinks.map(link =>" in read(ACTIONS)
    assert "launcher.openSettings(link.id)" in read(ACTIONS)


def test_generated_links_have_unique_ids_words_and_icons():
    links = settings_links()
    assert len(links) >= 10
    assert len({c for c, *_ in links}) == len(links)
    for cat, label, words, icon in links:
        assert cat in settings_categories(), cat
        assert label and icon, cat
        assert len(words.split()) >= 5, (cat, words)
        # every label is already in the catalogue; search must not add new strings
        catalog = json.loads(read(ROOT / "shani/i18n/template.json"))
        assert label in catalog, label


@pytest.mark.parametrize(
    "word,category",
    [
        ("duckduckgo", "search"),
        ("cups", "printers"),
        ("smb", "sharing"),
        ("firewalld", "firewall"),
        ("restic", "backup"),
        ("rollback", "boot"),
        ("fwupd", "updates"),
        ("apparmor", "security"),
        ("journald", "journal"),
        ("wellbeing", "screentime"),
    ],
)
def test_a_real_search_word_reaches_its_settings_page(word, category):
    """The words are the same ones Settings' own category search uses."""
    links = {c: w for c, _label, w, _icon in settings_links()}
    assert category in links
    assert any(w.startswith(word) for w in links[category].split()), (word, category)


# ---- 3. route agreement between the open paths --------------------------------


def test_files_is_the_one_open_dispatcher():
    service = read(FILES)
    panel = read(PANEL)
    launcher = read(LAUNCHER)
    sheet = read(SHEET)
    # Files itself: route first, xdg-open only for what no shell app owns
    assert "if (root.openRoute([p]))" in service
    assert service.index("if (root.openRoute([p]))") < service.index(
        'Quickshell.execDetached(["xdg-open", p])'
    )
    # double click, launcher hit and Quick Look's Open all call that dispatcher
    assert "Files.openEntry(e.path)" in panel
    assert "run: () => Files.openEntry(p)" in launcher
    assert "run: () => Qt.openUrlExternally(Files.uriOf(p))" not in launcher
    assert "Keys.onReturnPressed: win.openIt()" in sheet
    assert 'text: Tr.t("Open"); onClicked: win.openIt()' in sheet
    open_it = qml_function(sheet, "openIt")
    assert "Files.openEntry(p)" in open_it
    assert "QuickLook.openIt()" not in sheet


def test_show_in_files_reveals_the_file_in_its_folder():
    sheet = read(SHEET)
    fn = qml_function(sheet, "showInFiles")
    assert 'Files.select(p, "single")' in fn
    assert 'Tr.t("Show in Files"); onClicked: win.showInFiles(QuickLook.path)' in sheet
    js = (
        """
var calls = [];
var Files = { show: p => calls.push(["show", p]), select: (p, m) => calls.push(["select", p, m]) };
var QuickLook = { close: () => calls.push(["close"]) };
"""
        + fn
    )
    assert call(
        js, '(function () { showInFiles("/home/me/Pics/a.txt"); return calls; })()'
    ) == [
        ["show", "/home/me/Pics"],
        ["select", "/home/me/Pics/a.txt", "single"],
        ["close"],
    ]
    assert call(js, '(function () { showInFiles("/a.txt"); return calls; })()') == [
        ["show", "/"],
        ["select", "/a.txt", "single"],
        ["close"],
    ]


@pytest.mark.parametrize(
    "path,expected",
    [
        ("/notes/ideas.md", "text"),
        ("/pics/photo.JPG", "viewer"),
        ("/docs/paper.pdf", "pdf"),
        ("/music/song.mp3", "media"),
        ("/tmp/bundle.zip", "archive"),
        ("/people/card.vcf", "contacts"),
    ],
)
def test_the_launcher_and_files_choose_the_same_app(path, expected):
    """Launcher file results call Files.openEntry, whose choice is this table."""
    routes = "\n".join(
        qml_function(read(FILES), n) for n in ("routeForPath", "routeForPaths")
    )
    assert call(routes, "routeForPath(" + json.dumps(path) + ', "")') == expected
