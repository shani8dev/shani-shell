"""Contract tests for the shared Common component set and its docs.

Three guarantees, all static (no shell, no node):

1. Every ``shani/Common`` component is named in ``docs/COMPONENTS.md`` — the
   catalog cannot silently drop a widget.
2. Every module that uses a documented shared widget imports ``qs.Common`` and
   does not shadow it with a local file or a ``component`` redefinition.
3. Spot-checks that five repeated patterns are not hand-rolled where a shared
   equivalent exists (the rule: fix in the component, not per call site).

Run: ``python3 -m pytest tests/test_component_contracts.py -q``.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani/Common"
MODULES = ROOT / "shani/Modules"
COMPONENTS_DOC = ROOT / "docs/COMPONENTS.md"

# License / data blobs that are not components.
NON_COMPONENTS = {"Apache-2.0.txt", "world-land.js"}

# The canonical widget for each repeated pattern, and the module files that
# are allowed to use a variant only by extending the shared one.
SHARED_WIDGETS = [
    "ListRow",
    "EmptyState",
    "InfoBanner",
    "ConfirmButton",
    "BusyNote",
    "SearchField",
]


def common_components():
    files = list(COMMON.glob("*.qml")) + list(COMMON.glob("*.js"))
    return sorted(p.name for p in files if p.name not in NON_COMPONENTS)


def module_files():
    return sorted(MODULES.rglob("*.qml"))


def read(path):
    return path.read_text(encoding="utf-8")


# ---- 1. docs list every component ------------------------------------------


def test_docs_list_every_common_component():
    doc = read(COMPONENTS_DOC)
    missing = [name for name in common_components() if name not in doc]
    assert not missing, f"docs/COMPONENTS.md is missing: {missing}"


def test_components_doc_names_each_shared_widget():
    doc = read(COMPONENTS_DOC)
    for widget in SHARED_WIDGETS:
        assert f"{widget}.qml" in doc or widget in doc, widget


# ---- 2. import + no-shadow contract ----------------------------------------


def uses(text, widget):
    return re.search(r"\b" + re.escape(widget) + r"\s*\{", text) is not None


@pytest.mark.parametrize("widget", SHARED_WIDGETS)
def test_consumers_import_common_and_do_not_shadow(widget):
    consumers = [p for p in module_files() if uses(read(p), widget)]
    assert consumers, f"no module uses {widget}; contract is stale"
    for path in consumers:
        text = read(path)
        assert "import qs.Common" in text, f"{path} uses {widget} without import"
        # no local file shadows the shared name
        assert not (path.parent / f"{widget}.qml").exists(), path
        # no inline redefinition of the shared component
        assert not re.search(
            r"^\s*component\s+" + re.escape(widget) + r"\b", text, flags=re.M
        ), f"{path} redefines {widget}"


# ---- 3. spot-check: five patterns are not hand-rolled ----------------------


def test_busy_note_not_hand_rolled():
    """No module draws its own Row { Spinner; Text } busy row."""
    offenders = []
    for path in module_files():
        text = read(path)
        if "Spinner {" in text and re.search(r"\bRow\s*\{", text):
            # a real hand-roll pairs a Spinner with a Row wrapper and a Text
            if re.search(r"Spinner\s*\{[^}]*\}", text) and "BusyNote" not in text:
                offenders.append(str(path.relative_to(ROOT)))
    assert not offenders, f"hand-rolled busy rows (use BusyNote): {offenders}"


def test_no_local_file_shadows_a_shared_widget():
    for path in module_files():
        if path.name in {f"{w}.qml" for w in SHARED_WIDGETS}:
            pytest.fail(f"local shadow of a shared widget: {path}")


def test_listrow_is_the_only_row_widget_in_common():
    """ListRow is the canonical list row; no second row widget in Common."""
    rows = [
        p.name
        for p in COMMON.glob("*.qml")
        if re.search(r"property string title\b", read(p))
        and re.search(r"property string subtitle\b", read(p))
    ]
    assert "ListRow.qml" in rows
    # only ListRow carries the title+subtitle+selected row contract;
    # EmptyState is a centered placeholder, not a selectable row.
    allowed = {"ListRow.qml", "EmptyState.qml"}
    others = [r for r in rows if r not in allowed]
    assert not others, f"competing row widgets: {others}"


def test_searchfield_and_textfield_are_distinct_contracts():
    sf = read(COMMON / "SearchField.qml")
    tf = read(COMMON / "TextField.qml")
    assert "signal cleared()" in sf and "showClear" in sf
    assert "signal accepted()" in tf and "secret" in tf
    # SearchField is the search box; it must not be a bare text field copy
    assert "SearchField" not in tf


def test_confirm_button_owns_the_two_tap_state():
    cb = read(COMMON / "ConfirmButton.qml")
    assert "signal confirmed(string id)" in cb
    assert "function disarm()" in cb
    assert "armedText" in cb
    # the armed timer lives in the component, not in each caller
    assert re.search(r"interval:\s*4000", cb)


def test_empty_state_and_info_banner_share_the_scale():
    for name in ("EmptyState.qml", "InfoBanner.qml"):
        text = read(COMMON / name)
        for prop in ("iconSize", "padding", "accessibleRole"):
            assert re.search(r"property int " + prop + r"\b", text), (name, prop)
