#!/usr/bin/env python3
"""characters — a searchable Unicode character table for the shell.

  characters.py search QUERY [--limit N]
      print a JSON array [{ch, name, cat, cp}] for the best matches.
      An empty QUERY browses the curated table (first 240 entries).
  characters.py get
      print the whole curated table as JSON (for tools that want it local).

Where the names come from, in order:

* /usr/share/unicode/emoji/emoji-test.txt, when the unicode package is
  installed (the same file the launcher's ":" prefix already reads; its
  "fully-qualified … # E1.0 name" lines carry each emoji's name). It is
  absent here (no unicode package), so this file is the fallback below.
* otherwise (and always, for the rest of Unicode) Python's unicodedata
  over a curated set of blocks: ASCII symbols, Latin, Greek, Cyrillic,
  Hebrew, Arabic, the Indic blocks (Devanagari … Malayalam), general
  punctuation, currency, letterlike symbols, arrows, mathematical
  operators, miscellaneous technical, dingbats, miscellaneous symbols,
  CJK punctuation, fullwidth forms, mathematical alphanumeric symbols
  and the emoji planes (1F000-1FAFF).

  The `ucd` tool (unicode-character-database) was checked (`command -v
  ucd`): not installed, so it is not used. If it were, its database is
  the same public Unicode data unicodedata ships, so the matches would
  be the same.

Matching mirrors the launcher's ":" ranking: a name that *starts* with
the query beats a word that starts with one of its words, which beats a
plain substring. Extra aliases broaden it (arrow, check, heart, star,
rupee, …); a multi-word query matches when every word starts some word
of the name or an alias.
"""

from __future__ import annotations

import json
import os
import sys
import unicodedata

EMOJI_TEST = os.environ.get("SHANI_EMOJI_TEST", "/usr/share/unicode/emoji/emoji-test.txt")

# curated blocks (inclusive ranges); everything editable in the shell's
# Character panel lives in one of these
RANGES = [
    (0x0021, 0x007E),   # ASCII printable
    (0x00A0, 0x02FF),   # Latin-1 supplement + Latin extended
    (0x0370, 0x03FF),   # Greek
    (0x0400, 0x04FF),   # Cyrillic
    (0x0590, 0x05FF),   # Hebrew
    (0x0600, 0x06FF),   # Arabic
    (0x0900, 0x097F),   # Devanagari
    (0x0980, 0x09FF),   # Bengali
    (0x0A00, 0x0A7F),   # Gurmukhi
    (0x0A80, 0x0AFF),   # Gujarati
    (0x0B00, 0x0B7F),   # Oriya
    (0x0B80, 0x0BFF),   # Tamil
    (0x0C00, 0x0C7F),   # Telugu
    (0x0C80, 0x0CFF),   # Kannada
    (0x0D00, 0x0D7F),   # Malayalam
    (0x2000, 0x206F),   # general punctuation, currency, letterlike
    (0x2070, 0x2BFF),   # superscripts … arrows, math, technical, dingbats
    (0x3000, 0x30FF),   # CJK symbols, kana
    (0xFF00, 0xFFEF),   # fullwidth / halfwidth forms
    (0x1D400, 0x1D7FF), # mathematical alphanumeric
    (0x1F000, 0x1FAFF), # mahjong … symbols and pictographs (emoji too)
]

# words people type for a glyph, beyond its Unicode name
ALIASES = {
    "arrow": "ARROW",
    "check": "CHECK MARK",
    "cross": "CROSS",
    "heart": "HEAVY BLACK HEART",
    "star": "STAR",
    "smile": "SMILING FACE",
    "rupee": "INDIAN RUPEE SIGN",
    "omega": "GREEK SMALL LETTER OMEGA",
    "infinity": "INFINITY",
    "bullet": "BULLET",
    "bullet point": "BULLET",
    "tick": "CHECK MARK",
    "x": "MULTIPLICATION X",
    "degree": "DEGREE SIGN",
    "copyright": "COPYRIGHT SIGN",
    "registered": "REGISTERED SIGN",
    "trademark": "TRADE MARK SIGN",
    "section": "SECTION SIGN",
    "paragraph": "PILCROW SIGN",
    "snowman": "SNOWMAN",
    "sun": "BLACK SUN WITH RAYS",
    "moon": "CRESCENT MOON",
    "musical": "MUSICAL NOTE",
    "note": "MUSICAL NOTE",
    "female": "FEMALE SIGN",
    "male": "MALE SIGN",
    "rupee sign": "INDIAN RUPEE SIGN",
    "math": "OPERATOR",
    "math symbol": "OPERATOR",
    "greek": "GREEK",
    "devanagari": "DEVANAGARI",
    "bengali": "BENGALI",
}

_cache = None


def _emoji_entries():
    """(char, name) pairs from emoji-test.txt, when it is there."""
    entries = []
    try:
        with open(EMOJI_TEST, encoding="utf-8") as f:
            for line in f:
                if "; fully-qualified" not in line:
                    continue
                tail = line.split("#", 1)[-1].strip()
                if not tail:
                    continue
                glyph = tail.split(" ")[0]
                name = tail.split(" ", 1)[-1] if " " in tail else ""
                if glyph and name:
                    entries.append((glyph, name.upper()))
    except OSError:
        pass
    return entries


def iter_entries():
    """every character in the curated table, in code-point order."""
    global _cache
    if _cache is not None:
        return _cache
    seen = {}
    for lo, hi in RANGES:
        for cp in range(lo, hi + 1):
            ch = chr(cp)
            cat = unicodedata.category(ch)
            if cat in ("Cc", "Cn", "Co"):
                continue
            try:
                name = unicodedata.name(ch)
            except ValueError:
                continue
            seen[cp] = {"ch": ch, "name": name, "cat": cat, "cp": cp}
    for glyph, name in _emoji_entries():
        cp = ord(glyph[0]) if len(glyph) == 1 else None
        if cp is None:
            continue
        if cp not in seen:
            cat = ""
            try:
                cat = unicodedata.category(chr(cp))
            except ValueError:
                pass
            seen[cp] = {"ch": glyph, "name": name, "cat": cat, "cp": cp}
    _cache = [seen[k] for k in sorted(seen)]
    return _cache


def _entry_words(entry):
    words = set(entry["name"].lower().split())
    low = entry["name"].lower()
    for alias, needle in ALIASES.items():
        if needle.lower() in low:
            words.update(alias.split())
            words.add(alias.split()[-1])
    return words


def score_for(entry, query):
    """0 = no match, else higher is a better match."""
    q = query.strip().lower()
    if q == "":
        return 1
    name = entry["name"].lower()
    words = _entry_words(entry)
    if name == q:
        return 100
    if name.startswith(q):
        return 80
    # every typed word may start a name word
    if all(any(w.startswith(t) for w in words) for t in q.split()):
        return 60
    if q in name or q in _alias_text(entry):
        return 40
    if any(q in w for w in words):
        return 30
    return 0


def _alias_text(entry):
    name = entry["name"].lower()
    return " ".join(a for a, n in ALIASES.items() if n.lower() in name)


def search(query, limit=240):
    """the best `limit` matches for `query`, best first."""
    entries = iter_entries()
    q = (query or "").strip()
    if q == "":
        # browsing: symbols and script letters first, not the table's start
        return entries[:limit]
    scored = [(score_for(e, q), e) for e in entries]
    scored = [(s, e) for s, e in scored if s > 0]
    scored.sort(key=lambda t: (-t[0], t[1]["cp"]))
    return [e for _, e in scored[:limit]]


def main(argv):
    if len(argv) < 2:
        print("usage: characters.py search QUERY [--limit N] | get", file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "get":
        print(json.dumps(iter_entries(), ensure_ascii=False))
        return 0
    if cmd == "search":
        query = argv[2] if len(argv) > 2 and not argv[2].startswith("--") else ""
        limit = 240
        if "--limit" in argv:
            i = argv.index("--limit")
            try:
                limit = int(argv[i + 1])
            except (IndexError, ValueError):
                pass
        print(json.dumps(search(query, limit), ensure_ascii=False))
        return 0
    print("usage: characters.py search QUERY [--limit N] | get", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
