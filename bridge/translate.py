#!/usr/bin/env python3
"""translate — on-machine translation with Chronoa's local model, for the shell.

  translate.py strings LANG < ["English", ...]
      translate UI strings the catalog lacks into LANG, in batches, and merge
      them into ~/.cache/shani-shell/i18n/LANG.json (Common/Tr.qml reads it
      after the reviewed catalog, which always wins). A string already in the
      cache is not asked again. Prints how many were added.
  translate.py text LANG < "any text"
      one translation, for the launcher's "Translate" on copied text; prints
      the translation.

Only the local model is used: llama.cpp's llama-server, which Chronoa runs on
127.0.0.1:8765 and which speaks the OpenAI API (SHANI_TRANSLATE_URL replaces
it, for the tests). Nothing goes to the network - when the model is not there
this says so and exits 2, and the shell keeps the English. A reply that is not
a translation (empty, unchanged, or not the JSON asked for) is dropped, never
cached as one.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

URL = os.environ.get("SHANI_TRANSLATE_URL", "http://127.0.0.1:8765/v1/chat/completions")
NAMES = {"mr": "Marathi", "hi": "Hindi", "de": "German", "es": "Spanish", "fr": "French", "bn": "Bengali",
         "ta": "Tamil", "te": "Telugu", "kn": "Kannada", "ml": "Malayalam", "gu": "Gujarati", "pa": "Punjabi",
         "ur": "Urdu", "it": "Italian", "pt": "Portuguese", "ru": "Russian", "ja": "Japanese", "zh": "Chinese",
         "ar": "Arabic", "nl": "Dutch", "pl": "Polish", "tr": "Turkish", "en": "English"}
KEEP = "Chronoa, Cassini, ShaniOS, Wi-Fi, Bluetooth, VPN, QR, USB, KDE Connect, Tailscale, UEFI, Miracast"
BATCH = 25


def cache_file(lang: str) -> Path:
    base = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "shani-shell" / "i18n" / f"{lang}.json"


def ask(prompt: str, timeout: float = 300) -> str:
    body = {"messages": [{"role": "user", "content": prompt + " /no_think"}], "temperature": 0.1, "max_tokens": 3000}
    req = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.load(r)["choices"][0]["message"]["content"]
    # a thinking model may still wrap its answer
    return out.split("</think>")[-1].strip()


def _json_object(text: str) -> dict:
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return {}
    try:
        got = json.loads(text[start:end + 1])
    except ValueError:
        return {}
    return got if isinstance(got, dict) else {}


def translate_strings(lang: str, strings: list[str]) -> dict:
    name = NAMES.get(lang, lang)
    out = {}
    for i in range(0, len(strings), BATCH):
        chunk = strings[i:i + BATCH]
        prompt = (f"Translate these labels from a computer desktop's menus and settings into {name}. "
                  f"Use the short, natural wording a phone or computer in {name} would show. "
                  f"Keep these names as they are: {KEEP}. Keep %1, %2 and any symbols. "
                  "Answer with only a JSON object mapping each English label to its translation.\n\n"
                  + json.dumps(chunk, ensure_ascii=False))
        got = _json_object(ask(prompt))
        for k in chunk:
            v = got.get(k)
            # not a translation: missing, empty, the English back, or a placeholder lost
            if not isinstance(v, str) or not v.strip() or v.strip() == k:
                continue
            if any(f"%{n}" in k and f"%{n}" not in v for n in range(1, 4)):
                continue
            out[k] = v.strip()
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("strings", "text"):
        print(__doc__, file=sys.stderr)
        return 64
    mode, lang = argv[1], argv[2]
    try:
        if mode == "text":
            text = sys.stdin.read().strip()
            if not text:
                return 64
            print(ask(f"Translate this into {NAMES.get(lang, lang)}. Answer with only the translation.\n\n{text}"))
            return 0
        wanted = [s for s in json.load(sys.stdin) if isinstance(s, str) and s.strip()]
        path = cache_file(lang)
        have = json.loads(path.read_text()) if path.exists() else {}
        todo = [s for s in dict.fromkeys(wanted) if s not in have]
        if not todo:
            print(0)
            return 0
        new = translate_strings(lang, todo)
        if new:
            path.parent.mkdir(parents=True, exist_ok=True)
            merged = {**have, **new}
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps(dict(sorted(merged.items())), ensure_ascii=False, indent=1))
            tmp.replace(path)
        print(len(new))
        return 0
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        print(f"translate: the local model did not answer ({getattr(e, 'reason', e)}); nothing was sent elsewhere",
              file=sys.stderr)
        return 2
    except (KeyError, ValueError) as e:
        print(f"translate: the model's answer could not be read: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
