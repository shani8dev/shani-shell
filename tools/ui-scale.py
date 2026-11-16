#!/usr/bin/env python3
"""ui-scale — draw the shell's fixed sizes through Theme.px(), so they follow the
kind of screen (docs/FORM-FACTORS.md: a TV, a handheld, a classroom board draw
everything larger; a computer draws it as designed).

  tools/ui-scale.py apply [FILE...]   rewrite literal sizes to Theme.px(N)
  tools/ui-scale.py check [FILE...]   list literal sizes still left (exit 1 if any)

Default files: every .qml under shani/Modules and shani/Common, except Theme.qml.

What it rewrites, and only that:
  - a QML size binding or a size property's default with a bare number
    (`property real size: 18` in Icon is every icon's size): `width: 320`, `Layout.preferredWidth: 90`,
    `anchors.margins: 12`, `spacing: 6`, `radius: 10`, `size: 22` ...
    -> `width: Theme.px(320)`
  - a text size: `font.pixelSize: 13 * Theme.fontScale` / `(13 * Theme.fontScale)`
    -> `Theme.px(13) * Theme.fontScale`
Left alone: 0, 1 and 2 (hairlines and nothing), numbers inside expressions,
JS object literals (`{ width: 300, ... }` - data, not layout), and shani/Services
(numbers there are data: window widths written into niri's config, sample rates).

On a computer Theme.ui is 1 and Math.round(n * 1) is n: nothing moves. The
render and shell suites check that.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = (r"(?:Layout\.)?(?:preferredWidth|preferredHeight|minimumWidth|minimumHeight|maximumWidth|maximumHeight"
         r"|leftMargin|rightMargin|topMargin|bottomMargin|margins)"
         r"|anchors\.(?:margins|leftMargin|rightMargin|topMargin|bottomMargin|horizontalCenterOffset|verticalCenterOffset)"
         r"|implicitWidth|implicitHeight|width|height|spacing|rowSpacing|columnSpacing|radius|size|pixelSize"
         r"|padding|leftPadding|rightPadding|topPadding|bottomPadding|font\.pixelSize")
# a binding: start of line or after `;` / `{`, the name, a number, then the end of the binding
BIND = re.compile(r"(?P<pre>(?:^|[;{])\s*(?:(?:readonly\s+)?property\s+(?:int|real)\s+)?)(?P<name>" + NAMES
                  + r")\s*:\s*(?P<n>\d{1,4})(?P<post>(?=\s*(?:;|\}|//|$)))", re.M)
# only the number is replaced: brackets around it belong to the expression
# (Math.round(10 * Theme.fontScale) must stay a call)
FONT = re.compile(r"\b(?P<n>\d{1,3}(?:\.\d+)?)\s*\*\s*Theme\.fontScale")


def files(args):
    if args:
        return [Path(a) for a in args]
    out = []
    for d in ("shani/Modules", "shani/Common"):
        out += [p for p in sorted((ROOT / d).rglob("*.qml")) if p.name != "Theme.qml"]
    return out


def in_js_object(line, start):
    """a `{ width: 300, ... }` data literal, not a QML binding: a comma follows
    on the same line before the next `;`/`}`, or a `({` opens it"""
    rest = line[start:]
    cut = min([i for i in (rest.find(";"), rest.find("}")) if i >= 0] or [len(rest)])
    return "," in rest[:cut] or "({" in line[:start]


def convert(text):
    out = []
    count = 0
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("//") or stripped.startswith("*"):
            out.append(line)
            continue

        def bind(m):
            nonlocal count
            if int(m.group("n")) < 3 or in_js_object(line, m.start("name")):
                return m.group(0)
            count += 1
            return f"{m.group('pre')}{m.group('name')}: Theme.px({m.group('n')}){m.group('post')}"

        def font(m):
            nonlocal count
            n = m.group("n")
            if "Theme.px(" in line[max(0, m.start() - 9):m.start()]:
                return m.group(0)
            count += 1
            return f"Theme.px({n}) * Theme.fontScale"

        line = BIND.sub(bind, line)
        line = FONT.sub(font, line)
        out.append(line)
    return "\n".join(out), count


def main(argv):
    if not argv or argv[0] not in ("apply", "check"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    total = 0
    for f in files(argv[1:]):
        text = f.read_text(encoding="utf-8")
        new, n = convert(text)
        if n:
            total += n
            if argv[0] == "apply":
                f.write_text(new, encoding="utf-8")
            else:
                print(f"{f.relative_to(ROOT) if f.is_absolute() else f}: {n}")
    print(f"{'rewrote' if argv[0] == 'apply' else 'left'}: {total}")
    return 1 if argv[0] == "check" and total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
