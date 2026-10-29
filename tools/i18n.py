#!/usr/bin/env python3
"""The shell's translations (Common/Tr.qml reads shani/i18n/<lang>.json).

  tools/i18n.py wrap      put the plain English literals of the shown properties
                          (text, title, label, hint, placeholder, subtitle, tip,
                          Accessible.name) through Tr.t(); idempotent
  tools/i18n.py extract   every Tr.t("...") string -> shani/i18n/template.json
  tools/i18n.py check     per catalog: how many are translated, missing, stale
                          (exit 1 if a catalog has a key no QML uses any more)

A catalog maps English -> translation; a missing key shows the English.
Strings built by concatenation are not wrapped by `wrap`; write Tr.t("…%1…", x)
for those by hand.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "shani"
I18N = ROOT / "i18n"
PROPS = r"(?:text|title|label|hint|placeholder|subtitle|tip|Accessible\.name)"
LITERAL = re.compile(r'(\b' + PROPS + r'\s*:\s*)"((?:[^"\\]|\\.){2,}?)"(?=\s*[,;}\n])')
CALL = re.compile(r'Tr\.t\("((?:[^"\\]|\\.)*)"')


def qml_files():
    return sorted(p for p in ROOT.rglob("*.qml") if p.name != "Tr.qml")


def wrap() -> int:
    changed = 0
    for p in qml_files():
        s = p.read_text()

        def sub(m):
            text = m.group(2)
            if not re.search(r"[A-Za-z]{2}", text) or text.startswith(("file:", "/", "http")):
                return m.group(0)
            return f'{m.group(1)}Tr.t("{text}")'
        new = LITERAL.sub(sub, s)
        if new != s:
            if "qs.Common" not in new and p.parent.name != "Common":
                new = re.sub(r"(^import QtQuick\n)", r"\1import qs.Common\n", new, count=1, flags=re.M)
            p.write_text(new)
            changed += 1
    print(f"wrapped strings in {changed} files")
    return 0


def strings() -> list:
    out = set()
    for p in qml_files():
        # the literal as QML reads it: its escapes (\" \n \\) undone, its
        # Unicode left alone (unicode_escape would re-read UTF-8 as Latin-1:
        # "·" became "Â·" and no such key ever matched)
        out.update(json.loads('"' + m.group(1) + '"') for m in CALL.finditer(p.read_text()))
    return sorted(out)


def extract() -> int:
    I18N.mkdir(exist_ok=True)
    keys = strings()
    (I18N / "template.json").write_text(json.dumps({k: "" for k in keys}, ensure_ascii=False, indent=1) + "\n")
    print(f"{len(keys)} strings -> {I18N / 'template.json'}")
    return 0


def check() -> int:
    keys = set(strings())
    bad = 0
    for p in sorted(I18N.glob("*.json")):
        if p.name == "template.json":
            continue
        cat = json.loads(p.read_text())
        done = {k for k, v in cat.items() if v and k in keys}
        stale = sorted(k for k in cat if k not in keys)
        print(f"{p.stem}: {len(done)}/{len(keys)} translated, {len(keys) - len(done)} missing, {len(stale)} stale")
        for k in stale[:10]:
            print(f"   stale: {k!r}")
        bad += bool(stale)
    return 1 if bad else 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    sys.exit({"wrap": wrap, "extract": extract, "check": check}.get(cmd, lambda: print(__doc__) or 2)())
