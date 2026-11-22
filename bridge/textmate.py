#!/usr/bin/env python3
"""textmate — read TextMate .tmLanguage (plist XML or JSON) and .tmTheme files
and print them as JSON for the shell's TextMate highlighter.

    textmate.py grammar PATH     a .tmLanguage file -> normalized JSON grammar
    textmate.py theme PATH       a .tmTheme file -> [{ scope, foreground, fontStyle }]
    textmate.py list DIR         scan a folder, print { grammars: [...], themes: [...] }

TextMate grammars are property lists (XML or binary); .tmTheme is a plist too.
Python's plistlib reads both with the standard library. The shell cannot parse
plists, so this bridge converts them to JSON. Standard library only.
"""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path


def read_plist(path: Path):
    """Read an XML/binary plist or a JSON file."""
    raw = path.read_bytes()
    if raw.lstrip().startswith(b"{") or raw.lstrip().startswith(b"["):
        return json.loads(raw.decode("utf-8", errors="replace"))
    return plistlib.loads(raw)


def normalize_grammar(data: dict) -> dict:
    """Keep the fields the highlighter needs, recursively normalizing patterns."""

    def norm_pattern(p):
        if not isinstance(p, dict):
            return {}
        out = {}
        for key in (
            "name",
            "match",
            "begin",
            "end",
            "include",
            "comment",
            "captures",
            "beginCaptures",
            "endCaptures",
        ):
            if key in p:
                out[key] = p[key]
        if "patterns" in p and isinstance(p["patterns"], list):
            out["patterns"] = [norm_pattern(x) for x in p["patterns"]]
        if "repository" in p and isinstance(p["repository"], dict):
            out["repository"] = {k: norm_pattern(v) for k, v in p["repository"].items()}
        return out

    out = {
        "name": data.get("name", ""),
        "scopeName": data.get("scopeName", ""),
        "fileTypes": data.get("fileTypes", []),
        "patterns": [
            norm_pattern(p) for p in (data.get("patterns") or []) if isinstance(p, dict)
        ],
    }
    if isinstance(data.get("repository"), dict):
        out["repository"] = {k: norm_pattern(v) for k, v in data["repository"].items()}
    return out


def parse_grammar(path_str: str) -> int:
    path = Path(path_str)
    try:
        data = read_plist(path)
    except Exception as exc:  # noqa: BLE001
        print(f"could not read grammar: {exc}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print("grammar is not an object", file=sys.stderr)
        return 1
    print(json.dumps(normalize_grammar(data), ensure_ascii=False))
    return 0


def parse_theme(path_str: str) -> int:
    path = Path(path_str)
    try:
        data = read_plist(path)
    except Exception as exc:  # noqa: BLE001
        print(f"could not read theme: {exc}", file=sys.stderr)
        return 1
    settings = data.get("settings") or data.get("colors") or []
    out = []
    for s in settings:
        if not isinstance(s, dict):
            continue
        sc = s.get("scope", "")
        tok = s.get("settings") or {}
        if isinstance(tok, dict):
            out.append(
                {
                    "scope": sc
                    if isinstance(sc, str)
                    else " ".join(sc)
                    if isinstance(sc, list)
                    else "",
                    "foreground": tok.get("foreground", ""),
                    "background": tok.get("background", ""),
                    "fontStyle": tok.get("fontStyle", ""),
                }
            )
    print(json.dumps(out, ensure_ascii=False))
    return 0


def list_bundles(dir_str: str) -> int:
    d = Path(dir_str)
    grammars, themes = [], []
    if d.is_dir():
        for p in sorted(d.rglob("*")):
            if not p.is_file():
                continue
            low = p.name.lower()
            if low.endswith(".tmlanguage"):
                try:
                    g = normalize_grammar(read_plist(p))
                    grammars.append(
                        {
                            "path": str(p),
                            "name": g["name"] or p.stem,
                            "scopeName": g["scopeName"],
                            "fileTypes": g["fileTypes"],
                        }
                    )
                except Exception:  # noqa: BLE001
                    pass
            elif low.endswith(".tmtheme"):
                themes.append({"path": str(p), "name": p.stem})
    print(json.dumps({"grammars": grammars, "themes": themes}, ensure_ascii=False))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(
            "usage: textmate.py grammar PATH | theme PATH | list DIR", file=sys.stderr
        )
        return 2
    cmd = argv[1]
    if cmd == "grammar":
        return parse_grammar(argv[2])
    if cmd == "theme":
        return parse_theme(argv[2])
    if cmd == "list":
        return list_bundles(argv[2])
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
