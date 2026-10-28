#!/usr/bin/env python3
"""osk-layout — keyboard layouts for the shell's screen keyboard, from xkb.

The screen keyboard can show any layout the system's xkeyboard-config knows
(every script Linux has a keyboard for — the same source stevia draws its
layouts from). Rather than re-implementing xkb, this asks libxkbcommon itself
what each key produces: it compiles the layout's keymap and reads the base and
shifted keysym of every key on the four main rows.

    osk-layout.py --list            every layout and variant, as JSON
    osk-layout.py in+marathi        that layout's rows, as JSON

Rows are [{"n": base, "s": shifted}], number row first. Keys that produce no
printable character are left out.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROWS = [
    [f"AE{i:02d}" for i in range(1, 13)],
    [f"AD{i:02d}" for i in range(1, 13)],
    [f"AC{i:02d}" for i in range(1, 12)],
    ["LSGT"] + [f"AB{i:02d}" for i in range(1, 11)],
]
RULES = [Path("/usr/share/xkeyboard-config-2/rules/evdev.xml"), Path("/usr/share/X11/xkb/rules/evdev.xml")]


class RuleNames(ctypes.Structure):
    _fields_ = [(n, ctypes.c_char_p) for n in ("rules", "model", "layout", "variant", "options")]


def _lib():
    lib = ctypes.CDLL(ctypes.util.find_library("xkbcommon") or "libxkbcommon.so.0")
    lib.xkb_context_new.restype = ctypes.c_void_p
    lib.xkb_context_new.argtypes = [ctypes.c_int]
    lib.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    lib.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(RuleNames), ctypes.c_int]
    lib.xkb_keymap_key_by_name.restype = ctypes.c_uint32
    lib.xkb_keymap_key_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
    lib.xkb_keymap_key_get_syms_by_level.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
    lib.xkb_keysym_to_utf8.restype = ctypes.c_int
    lib.xkb_keysym_to_utf8.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
    return lib


def _char(lib, keymap, code: int, level: int) -> str:
    syms = ctypes.POINTER(ctypes.c_uint32)()
    if lib.xkb_keymap_key_get_syms_by_level(keymap, code, 0, level, ctypes.byref(syms)) < 1:
        return ""
    buf = ctypes.create_string_buffer(16)
    if lib.xkb_keysym_to_utf8(syms[0], buf, 16) <= 0:
        return ""
    text = buf.value.decode("utf-8", "replace")
    return text if text.isprintable() and text.strip() else ""


def layout(spec: str) -> dict:
    name, _, variant = spec.partition("+")
    lib = _lib()
    ctx = lib.xkb_context_new(0)
    names = RuleNames(b"evdev", b"pc105", name.encode(), variant.encode(), b"")
    keymap = lib.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0)
    if not keymap:
        raise SystemExit(f"xkb does not know the layout {spec!r}")
    rows = []
    for row in ROWS:
        keys = []
        for key in row:
            code = lib.xkb_keymap_key_by_name(keymap, key.encode())
            base = _char(lib, keymap, code, 0)
            if base:
                keys.append({"n": base, "s": _char(lib, keymap, code, 1) or base})
        if keys:
            rows.append(keys)
    meta = next((x for x in catalogue() if x["id"] == spec), {})
    return {"id": spec, "name": meta.get("name", spec), "langs": meta.get("langs", []), "rows": rows}


def catalogue() -> list[dict]:
    rules = next((p for p in RULES if p.exists()), None)
    if rules is None:
        return []
    out = []
    for lay in ET.parse(rules).getroot().iter("layout"):
        ci = lay.find("configItem")
        lid = ci.findtext("name")
        langs = [x.text for x in ci.iter("iso639Id")]
        out.append({"id": lid, "name": ci.findtext("description"), "langs": langs})
        for var in lay.iter("variant"):
            vi = var.find("configItem")
            vlangs = [x.text for x in vi.iter("iso639Id")] or langs
            out.append({"id": f"{lid}+{vi.findtext('name')}", "name": vi.findtext("description"), "langs": vlangs})
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    data = catalogue() if argv[1] == "--list" else layout(argv[1])
    json.dump(data, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
