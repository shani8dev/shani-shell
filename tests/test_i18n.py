"""The translation catalogs (shani/i18n/*.json) and the strings they cover.

Common/Tr.qml reads shani/i18n/<lang>.json and falls back to the English when a
key is missing, so a missing key is invisible - the UI just shows English. A
stale key is the opposite: a string nobody uses any more, still waiting to be
translated. tools/i18n.py can extract and check both; this pins the invariants so
a catalog cannot drift without a test failing.

Every key in every catalog is checked (parametrised), and so is the template
itself - a broken entry is a missing translation for every language.
"""

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
I18N = ROOT / "shani/i18n"
CATALOGS = sorted(p.stem for p in I18N.glob("*.json") if p.stem != "template")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def i18n_tool():
    spec = importlib.util.spec_from_file_location("i18n", ROOT / "tools/i18n.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TEMPLATE = load(I18N / "template.json")
KEYS = sorted(TEMPLATE)
QML_STRINGS = i18n_tool().strings()


def catalog(lang):
    return load(I18N / f"{lang}.json")


def cat_keys():
    return sorted((lang, key) for lang in CATALOGS for key in catalog(lang))


# ---- the template ----------------------------------------------------------


def test_the_template_is_an_object():
    assert isinstance(TEMPLATE, dict) and TEMPLATE


def test_the_template_has_no_empty_keys():
    assert [k for k in TEMPLATE if not k.strip()] == []


def test_the_template_is_what_the_qml_asks_for():
    """extract writes it from the QML; if they disagree, a string is either
    untranslatable or already translated under a name nobody uses."""
    assert set(QML_STRINGS) == set(KEYS)


def test_the_template_keys_are_sorted():
    assert KEYS == sorted(KEYS)


# ---- every catalog ---------------------------------------------------------


def test_there_is_a_catalog_to_check():
    assert CATALOGS


@pytest.mark.parametrize("lang", CATALOGS)
def test_the_catalog_is_an_object(lang):
    assert isinstance(catalog(lang), dict) and catalog(lang)


@pytest.mark.parametrize("lang", CATALOGS)
def test_every_key_in_the_catalog_exists_in_the_template(lang):
    stale = [k for k in catalog(lang) if k not in TEMPLATE]
    assert stale == []


@pytest.mark.parametrize("lang", CATALOGS)
def test_no_translation_is_empty(lang):
    empty = [k for k, v in catalog(lang).items() if not str(v).strip()]
    assert empty == []


@pytest.mark.parametrize("lang", CATALOGS)
def test_no_translation_is_just_the_english_again(lang):
    """A value equal to its key is an untranslated placeholder left behind."""
    same = [k for k, v in catalog(lang).items() if str(v).strip() == k.strip()]
    assert same == []


@pytest.mark.parametrize("lang", CATALOGS)
def test_the_catalog_is_valid_utf8_text(lang):
    for k, v in catalog(lang).items():
        assert isinstance(k, str) and isinstance(v, str)


# ---- every key, one at a time ----------------------------------------------


@pytest.mark.parametrize("lang,key", cat_keys())
def test_the_key_is_translated_to_something(lang, key):
    assert str(catalog(lang)[key]).strip() != ""


@pytest.mark.parametrize("lang,key", cat_keys())
def test_the_translation_is_not_the_english(lang, key):
    assert str(catalog(lang)[key]).strip() != key.strip()


# ---- how much is covered ---------------------------------------------------


@pytest.mark.parametrize("lang", CATALOGS)
def test_the_coverage_is_reported_and_reasonable(lang):
    done = len(catalog(lang))
    assert done > 500, f"{lang} covers {done} of {len(KEYS)}"


@pytest.mark.parametrize("lang", CATALOGS)
def test_the_catalog_is_a_subset_of_the_template(lang):
    assert set(catalog(lang)) <= set(KEYS)


# ---- the QML side ----------------------------------------------------------


def test_every_qml_that_translates_imports_common():
    """Tr lives in qs.Common; a file that calls Tr.t without importing it shows
    the raw call as text."""
    bad = []
    for p in ROOT.rglob("*.qml"):
        if p.name == "Tr.qml":
            continue
        text = p.read_text(encoding="utf-8")
        if (
            "Tr.t(" in text
            and "import qs.Common" not in text
            and p.parent.name != "Common"
        ):
            bad.append(str(p.relative_to(ROOT)))
    assert bad == []
