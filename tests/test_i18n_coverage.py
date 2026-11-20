"""Every literal passed to Tr.t() should be in the template catalog.

A string missed here is untranslatable in every language, silently.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text())


def test_every_translated_literal_has_a_catalog_key():
    missing = []
    for path in sorted((ROOT / "shani").rglob("*.qml")):
        for m in re.finditer(
            r'Tr\.t\(\s*("(?:[^"\\]|\\.)*")', path.read_text(encoding="utf-8")
        ):
            literal = json.loads(m.group(1))
            if literal not in TEMPLATE:
                missing.append(f"{path.relative_to(ROOT)}: {literal[:60]}")
    assert not missing, "literals missing from i18n/template.json: " + "; ".join(
        missing
    )
