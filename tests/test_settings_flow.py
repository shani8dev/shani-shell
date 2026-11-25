"""Settings must be one coherent, searchable place.

Static hooks into the three files that define the flow — SettingsPage's `cats`
list and its Loader registrations, SettingsIndex's search entries, and the
Ui.openSettings targets scattered across the shell — plus pure-logic checks on
the parsed data. Nothing here starts the shell: a broken link or a stale
keyword only shows up when someone opens Settings, so pin it at the source.
"""

import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
SETTINGS = SHANI / "Modules/Settings"
PAGE = SETTINGS / "SettingsPage.qml"
INDEX = SETTINGS / "SettingsIndex.js"

# words that add no search value on their own
STOPWORDS = {
    "a",
    "an",
    "the",
    "and",
    "or",
    "of",
    "to",
    "from",
    "on",
    "off",
    "up",
    "in",
    "it",
    "for",
    "is",
    "with",
}


def text(path):
    return Path(path).read_text(encoding="utf-8")


def category_data():
    """The `cats` array: [(id, words, label, icon), ...] in display order."""
    block = re.search(r"readonly property var cats: (\[.*?\])\n", text(PAGE), re.S)
    assert block, "SettingsPage.qml: the cats list no longer parses"
    items = re.findall(
        r'\{\s*id:\s*"([^"]+)",\s*words:\s*"([^"]*)",\s*label:\s*(?:Tr\.t\()?"([^"]*)"\)?,\s*icon:\s*"([^"]*)"\s*\}',
        block.group(1),
    )
    assert items, "SettingsPage.qml: no categories parsed from cats"
    return items


def index_entries():
    """SettingsIndex's searchable rows: dicts with key, label, cat, words, link."""
    out = []
    for row in text(INDEX).splitlines():
        if not re.match(r"\s*\{\s*key:", row):
            continue
        key = re.search(r'key:\s*"([^"]+)"', row)
        cat = re.search(r'cat:\s*"([^"]+)"', row)
        if not (key and cat):
            continue
        words = re.search(r'words:\s*"([^"]*)"', row)
        link = re.search(r'link:\s*"([^"]+)"', row)
        out.append(
            {
                "key": key.group(1),
                "cat": cat.group(1),
                "words": (words.group(1) if words else "").split(),
                "link": link.group(1) if link else None,
            }
        )
    assert len(out) > 100, "SettingsIndex.js: the entries list no longer parses"
    return out


def deep_link_targets():
    """Every category string a caller can ask Settings to open."""
    targets = set()
    for path in SHANI.rglob("*"):
        if path.suffix not in (".qml", ".js"):
            continue
        body = text(path)
        patterns = (
            r'openSettings\(\s*"([^"]+)"',
            r'settingsCategory\(\s*"([^"]+)"',
            r'settingsCat\s*=\s*"([^"]+)"',
        )
        for pattern in patterns:
            targets.update(re.findall(pattern, body))
    return {t for t in targets if t}  # "" is the intentional "show the grid" link


def loader_pages():
    """cat -> source text of the page that renders it.

    SettingsPage has both separate `Settings*.qml` components and inline
    sections inside its Loaders; both count as a page for that cat.
    """
    lines = text(PAGE).splitlines()
    current = None
    inline = defaultdict(list)
    for line in lines:
        hit = re.search(r'active:\s*(?:page\.)?cat\s*===\s*"([^"]+)"', line)
        if hit:
            current = hit.group(1)
        if current:
            inline[current].append(line)

    component_cat = {}
    for path in SETTINGS.glob("Settings*.qml"):
        if path.stem == "SettingsPage":
            continue
        for i, line in enumerate(lines):
            if not re.search(r"\b" + re.escape(path.stem) + r"\s*\{", line):
                continue
            for j in range(i, -1, -1):
                hit = re.search(r'active:\s*(?:page\.)?cat\s*===\s*"([^"]+)"', lines[j])
                if hit:
                    component_cat[str(path)] = hit.group(1)
                    break
            break

    pages = {cat: "\n".join(bits) for cat, bits in inline.items()}
    for path, cat in component_cat.items():
        pages[cat] = pages.get(cat, "") + "\n" + text(path)
    return pages


def key_locations():
    """setting key -> cats whose page actually writes/reads `d.<key>`."""
    lines = text(PAGE).splitlines()
    current = None
    inline_cat = {}
    for i, line in enumerate(lines):
        hit = re.search(r'active:\s*(?:page\.)?cat\s*===\s*"([^"]+)"', line)
        if hit:
            current = hit.group(1)
        inline_cat[i] = current

    component_cat = {}
    for path in SETTINGS.glob("Settings*.qml"):
        if path.stem == "SettingsPage":
            continue
        for i, line in enumerate(lines):
            if re.search(r"\b" + re.escape(path.stem) + r"\s*\{", line):
                for j in range(i, -1, -1):
                    hit = re.search(
                        r'active:\s*(?:page\.)?cat\s*===\s*"([^"]+)"', lines[j]
                    )
                    if hit:
                        component_cat[str(path)] = hit.group(1)
                        break
                break

    found = defaultdict(set)
    paths = [PAGE] + sorted(SETTINGS.glob("Settings*.qml"))
    for path in paths:
        for i, line in enumerate(text(path).splitlines()):
            cat = inline_cat[i] if path == PAGE else component_cat.get(str(path))
            if not cat:
                continue
            for a, b in re.findall(
                r"\b(?:page\.)?d\.(\w+)\b|\bSettings\.data\.(\w+)\b", line
            ):
                found[a or b].add(cat)
    return found


def meaningful(words):
    return {
        w.lower().strip("-&,")
        for w in words
        if w.lower().strip("-&,") not in STOPWORDS and len(w) > 1
    }


# ---- the category list -----------------------------------------------------


def test_no_duplicate_category_ids():
    ids = [c[0] for c in category_data()]
    assert len(ids) == len(set(ids)), (
        f"duplicate category ids: {sorted({i for i in ids if ids.count(i) > 1})}"
    )


def test_every_category_has_at_least_three_meaningful_keywords():
    for cat, words, _label, _icon in category_data():
        words = meaningful(words.split())
        assert len(words) >= 3, f"{cat}: only {sorted(words)}"


def test_every_keyword_is_grounded_in_its_own_category():
    """A keyword that only describes a control on another page is stale: it
    sends the person to an empty section. Require each category to have at
    least three words that really occur in its page or in its index entries."""
    pages = loader_pages()
    entries = defaultdict(list)
    for e in index_entries():
        entries[e["cat"]].extend(e["words"])
    for cat, words, _label, _icon in category_data():
        live = set(
            re.findall(
                r"[a-z]+", (pages.get(cat, "") + " " + " ".join(entries[cat])).lower()
            )
        )
        grounded = [w for w in meaningful(words.split()) if w in live]
        assert len(grounded) >= 3, (
            f"{cat}: only {sorted(grounded)} grounded in its own page/index"
        )


def test_every_category_has_a_loader_page():
    """The reverse of the orphan-page check: a tile that opens nothing."""
    ids = {c[0] for c in category_data()}
    page = text(PAGE)
    missing = [cat for cat in ids if f'page.cat === "{cat}"' not in page]
    assert not missing, f"categories with no Loader: {missing}"


# ---- deep links and the search index --------------------------------------


def test_deep_link_targets_resolve_to_a_registered_category():
    ids = {c[0] for c in category_data()}
    bad = sorted(deep_link_targets() - ids)
    assert not bad, f"Ui.openSettings targets with no category: {bad}"


def test_indexed_entries_resolve_to_a_registered_category():
    ids = {c[0] for c in category_data()}
    bad = sorted({e["cat"] for e in index_entries()} - ids)
    assert not bad, f"search entries pointing at unknown categories: {bad}"


def test_index_entries_point_at_the_page_hosting_the_control():
    """Search flashes a control on `entry.cat`; if the control really lives on
    another page the jump silently lands nowhere. Keys with no `d.<key>` in a
    page (app deep links, read-only rows) have no page to check."""
    locations = key_locations()
    bad = []
    for e in index_entries():
        cats = locations.get(e["key"])
        if cats and e["cat"] not in cats:
            bad.append((e["key"], e["cat"], sorted(cats)))
    assert not bad, f"search entries on the wrong page: {bad}"


def test_app_links_have_a_flag_map_entry():
    """A `link:` is an IPC, not a category. SettingsPage maps each one to a Ui
    flag; an unmapped link is a silent dead end for a search result."""
    page = text(PAGE)
    block = re.search(r"readonly property var linkFlags: \(\{(.*?)\}\)", page, re.S)
    assert block, "SettingsPage.qml: linkFlags map is gone"
    mapped = set(re.findall(r'(\w+Open):\s*"', block.group(1)))
    for e in index_entries():
        if e["link"]:
            assert e["link"] in mapped, (
                f"{e['key']}: link {e['link']} is not mapped to a Ui flag"
            )
