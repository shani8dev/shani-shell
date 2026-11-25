"""Static parity check for the settings search index and its category groups.

Both surfaces are QML/JS but must agree with Common/Settings.qml: a key the
sidebar counts must be findable, and a tile that shows a "N customised" badge
must have a group to count in. Nothing here starts the shell.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "shani/Modules/Settings/SettingsIndex.js"
PAGE = ROOT / "shani/Modules/Settings/SettingsPage.qml"
SETTINGS = ROOT / "shani/Common/Settings.qml"

# the keys the audit found in `groups` but missing from `entries`
GROUP_ONLY_KEYS = [
    "whisperModel",
    "middlePaste",
    "lockPreviews",
    "lockScreenClock",
    "lockScreenMedia",
    "autoPowerSaver",
    "profileOnBattery",
    "profilePluggedIn",
    "displays",
    "oskLanguages",
    "touchX",
    "touchY",
    "customBinds",
]


def source(path):
    return Path(path).read_text(encoding="utf-8")


def entry_rows(idx):
    return [ln for ln in idx.splitlines() if re.match(r"\s*\{\s*key:", ln)]


def entry_keys(idx):
    return {re.search(r'key:\s*"([^"]+)"', ln).group(1) for ln in entry_rows(idx)}


def group_block(idx):
    return idx.split("var groups = {", 1)[1].split("\n};", 1)[0]


def group_categories(idx):
    return set(re.findall(r"^\s*(\w+):\s*\[", group_block(idx), re.M))


def grouped_settings(idx):
    # only the array values are quoted; the category keys are bare identifiers
    return set(re.findall(r'"([^"]+)"', group_block(idx)))


def category_ids():
    block = re.search(r"readonly property var cats: (\[.*?\])\n", source(PAGE), re.S)
    assert block, "SettingsPage.qml: cats list no longer parses"
    return set(re.findall(r'id:\s*"([^"]+)"', block.group(1)))


def scalar_setting_keys():
    body = source(SETTINGS)
    pairs = re.findall(r"^\s*property\s+(\w+)\s+(\w+)\s*(?::|\()", body, re.M)
    return {name for typ, name in pairs if typ in {"bool", "int", "real", "string"}}


def test_every_category_has_a_group():
    idx = source(INDEX)
    cats = category_ids()
    assert group_categories(idx) == cats, (
        "groups/cats drift: "
        f"missing={sorted(cats - group_categories(idx))}, "
        f"orphan={sorted(group_categories(idx) - cats)}"
    )


def test_every_counted_setting_has_a_search_entry():
    idx = source(INDEX)
    assert len(entry_rows(idx)) > 100, "SettingsIndex.js: entries no longer parse"
    missing = sorted(grouped_settings(idx) - entry_keys(idx))
    assert not missing, f"grouped keys a person cannot search for: {missing}"


def test_every_searchable_scalar_is_counted_by_its_section():
    idx = source(INDEX)
    ungrouped = sorted(
        (entry_keys(idx) & scalar_setting_keys()) - grouped_settings(idx)
    )
    assert not ungrouped, f"searchable scalars with no customised count: {ungrouped}"


def test_audit_group_only_keys_are_now_searchable():
    rows = "\n".join(entry_rows(source(INDEX)))
    for key in GROUP_ONLY_KEYS:
        assert f'key: "{key}"' in rows, f"{key}: still missing from search"


def test_gesture_settings_have_an_entry_and_a_switch_row():
    idx = source(INDEX)
    page = source(PAGE)
    for key, label in (
        ("leftRail", "Left workspace rail"),
        ("edgeSwipes", "Edge swipes"),
    ):
        row = next((ln for ln in entry_rows(idx) if f'key: "{key}"' in ln), None)
        assert row, f"{key}: no search entry"
        assert f'label: "{label}"' in row and 'cat: "personal"' in row, row
        assert f'Tr.t("{label}")' in page, f"{key}: no labelled control"
        assert re.search(rf"checked:\s*page\.d\.{key}\b", page), f"{key}: no SwitchRow"
