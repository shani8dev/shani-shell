#!/usr/bin/env python3
"""playlist — read and write .m3u queues for the Media Player.

argv only, stdlib only:

    playlist.py write <path> <json>   {"entries": [{"path": ..., "title": ...}]}
    playlist.py read  <path>          {"entries": [...], "count": n}

A path reaches this program as its own argv element and is never handed to a
shell; no filename is ever built into a command string. Entries are either a
scheme:// URL or a filesystem path (a relative one is resolved next to the
playlist). Control characters and empty entries are dropped. All answers are
one line of JSON on stdout; failures are {"error": "..."} with a non-zero exit.
"""

from __future__ import annotations

import json
import os
import re
import sys

URL = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*://")


def is_url(path: str) -> bool:
    return bool(URL.match(path))


def clean_path(path, base: str = "") -> str:
    """One media entry: a URL unchanged, or an absolute path to open.

    A relative path in a playlist is read next to that playlist, not next to
    the shell's working directory. Nothing here starts a process.
    """
    p = str(path or "").strip()
    if not p or any(ord(c) < 32 for c in p):
        return ""
    if is_url(p):
        return p
    if not os.path.isabs(p):
        if not base:
            return ""
        p = os.path.join(base, p)
    return os.path.normpath(p)


def parse_m3u(text: str, base: str = "") -> dict:
    """#EXTM3U / #EXTINF lines into [{ path, title }], in file order."""
    entries: list[dict] = []
    title = ""
    for raw in str(text).replace("\r", "").split("\n"):
        line = raw.strip()
        if line.startswith("#EXTINF:"):
            info = line[len("#EXTINF:") :].strip()
            title = info.split(",", 1)[1].strip() if "," in info else ""
        elif line.startswith("#") or not line:
            continue
        else:
            path = clean_path(line, base)
            if path:
                entries.append({"path": path, "title": title})
            title = ""
    return {"entries": entries, "count": len(entries)}


def render_m3u(entries) -> str:
    """[{ path, title }] back to a small, standard #EXTM3U playlist."""
    out = ["#EXTM3U"]
    for item in entries or []:
        if not isinstance(item, dict):
            continue
        path = clean_path(item.get("path"))
        if not path:
            continue
        title = str(item.get("title") or "").replace("\r", " ").replace("\n", " ")
        title = title or path.rsplit("/", 1)[-1]
        out.append("#EXTINF:-1," + title)
        out.append(path)
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("read", "write"):
        print(
            json.dumps(
                {"error": "usage: playlist.py read <path> | write <path> <json>"}
            )
        )
        return 2
    op, raw = argv[1], argv[2]
    target = clean_path(raw)
    if not target or is_url(target):
        print(json.dumps({"error": "a local playlist path is required"}))
        return 1
    try:
        if op == "read":
            with open(target, "r", encoding="utf-8", errors="replace") as f:
                result = parse_m3u(f.read(), os.path.dirname(target))
        else:
            if len(argv) < 4:
                print(json.dumps({"error": "write needs the entries as JSON"}))
                return 2
            data = json.loads(argv[3])
            entries = data.get("entries", []) if isinstance(data, dict) else data
            text = render_m3u(entries)
            with open(target, "w", encoding="utf-8") as f:
                f.write(text)
            result = {
                "ok": True,
                "count": sum(
                    1 for line in text.splitlines() if line.startswith("#EXTINF:")
                ),
            }
    except (OSError, ValueError, TypeError) as exc:
        print(json.dumps({"error": str(exc)}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
