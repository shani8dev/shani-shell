"""A wrapping Text placed in a ColumnLayout/RowLayout must be given a width.

Without Layout.fillWidth (or a width), a layout gives a Text its implicit
width, which is the whole text on one line: wrapMode never wraps and the text
runs under its neighbours. Calls' subtitle ran under the call history this way,
and the setup wizard's Chronoa page did the same.
"""
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
import re
import pathlib
WIDTH = re.compile(r'^\s*(Layout\.(fillWidth|preferredWidth|maximumWidth)|width|anchors\.(fill|left|right)|anchors\s*\{)')
def scan(path):
    lines = pathlib.Path(path).read_text(errors='replace').split('\n')
    stack = []   # (type, start_line, props set, has_width)
    hits = []
    for i, l in enumerate(lines, 1):
        code = re.sub(r'//.*$', '', l)
        m = re.match(r'^\s*([A-Z][\w.]*)\s*\{', code)
        opens = code.count('{'); closes = code.count('}')
        if m and not re.match(r'^\s*[A-Z][\w.]*\s*\{[^{}]*\}\s*$', code):
            stack.append([m.group(1), i, False, False])
        elif m:  # one-line object
            t = m.group(1); body = code
            parent = stack[-1][0] if stack else ''
            if t == 'Text' and re.search(r'wrapMode:\s*Text\.(Wrap|WordWrap|WrapAnywhere)', body) and parent in ('ColumnLayout', 'RowLayout') \
               and not re.search(r'Layout\.(fillWidth|preferredWidth|maximumWidth)|\bwidth:|anchors', body):
                hits.append(i)
            continue
        else:
            if stack:
                if re.search(r'wrapMode:\s*Text\.(Wrap|WordWrap|WrapAnywhere)', code): stack[-1][2] = True
                if WIDTH.search(code): stack[-1][3] = True
        net = opens - closes - (1 if m else 0)
        for _ in range(max(0, -net)):
            if stack:
                t, start, wrap, width = stack.pop()
                parent = stack[-1][0] if stack else ''
                if t == 'Text' and wrap and not width and parent in ('ColumnLayout', 'RowLayout'):
                    hits.append(start)
    return hits


FILES = sorted({*ROOT.glob("shani/**/*.qml"), ROOT / "greeter" / "shell.qml", ROOT / "setup" / "shell.qml"})


def test_wrapping_text_in_a_layout_has_a_width():
    bad = [f"{p.relative_to(ROOT)}:{n}" for p in FILES for n in scan(p)]
    assert not bad, "wrapping Text with no width in a layout (add Layout.fillWidth: true):\n" + "\n".join(bad)


def test_the_check_sees_the_old_calls_subtitle(tmp_path):
    q = tmp_path / "x.qml"
    q.write_text("ColumnLayout {\n    Text {\n        text: \"a long line\"\n        wrapMode: Text.Wrap\n    }\n"
                 "    Text { text: \"b\"; wrapMode: Text.Wrap }\n"
                 "    Text {\n        Layout.fillWidth: true\n        wrapMode: Text.Wrap\n    }\n}\n")
    assert scan(q) == [2, 6]


# ---- a container anchored left and right needs a height --------------------
# Mail's offline banner was a Rectangle anchored top/left/right with no height:
# its background never drew and its text was painted over the folder list.
def scan_zero_height(p):
    L = pathlib.Path(p).read_text(errors='replace').split('\n'); hits = []
    for i, l in enumerate(L):
        if not re.match(r'^\s*(Rectangle|Item)\s*\{\s*$', l): continue
        ind = len(l) - len(l.lstrip()); body = []; j = i + 1
        while j < len(L) and not (L[j].strip() == '}' and len(L[j]) - len(L[j].lstrip()) == ind):
            body.append(L[j]); j += 1
        own = [b for b in body if len(b) - len(b.lstrip()) == ind + 4]
        o = '\n'.join(own)
        horiz = re.search(r'anchors\s*\{[^}]*\bleft\b[^}]*\bright\b|anchors\.left', o)
        vert = re.search(r'\b(height|implicitHeight|Layout\.(preferredHeight|fillHeight|minimumHeight))\s*:|anchors\s*\{[^}]*\b(bottom|fill|verticalCenter)\b|anchors\.(bottom|fill|verticalCenter)', o)
        fills = re.search(r'anchors\s*\{\s*fill:\s*parent|anchors\.fill:\s*parent', '\n'.join(body))
        if horiz and not vert and fills: hits.append(i + 1)
    return hits


def test_anchored_containers_have_a_height():
    bad = [f"{p.relative_to(ROOT)}:{n}" for p in FILES for n in scan_zero_height(p)]
    assert not bad, "a container with a filling child but no height (it draws nothing):\n" + "\n".join(bad)


def test_the_check_sees_the_old_mail_banner(tmp_path):
    q = tmp_path / "x.qml"
    q.write_text("Item {\n    Rectangle {\n        anchors { top: parent.top; left: parent.left; right: parent.right }\n"
                 "        RowLayout {\n            anchors.fill: parent\n        }\n    }\n}\n")
    assert scan_zero_height(q) == [2]
