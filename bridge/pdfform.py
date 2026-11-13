#!/usr/bin/env python3
"""pdfform — the Document Viewer's PyMuPDF half: a PDF's form fields and a filled
copy of it ("Fill in"), and a PDF copy of what is not a PDF.

    pdfform.py fields FILE       [{"name", "type": text|checkbox|choice|radio, "value", "options", "page"}]
    pdfform.py fill FILE         values as JSON on stdin ({"name": "value" | true/false});
                                 prints {"saved": path}
    pdfform.py topdf OUT FILE... an e-book (EPUB, FB2, MOBI), XPS or CBZ - or, with several
                                 FILEs, pictures in that order (a comic's pages) - as one PDF

The filled copy goes beside the original as "<name> (filled).pdf" (or
"(filled 2)" ...): the original is never written over, and the copy keeps
its fields, so it can be filled again.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import pymupdf as fitz      # PyMuPDF; "fitz" is its old, deprecated name
except ImportError:  # pragma: no cover - the package depends on python-pymupdf
    try:
        import fitz
    except ImportError:
        fitz = None

KINDS = {}
if fitz is not None:
    KINDS = {fitz.PDF_WIDGET_TYPE_TEXT: "text", fitz.PDF_WIDGET_TYPE_CHECKBOX: "checkbox",
             fitz.PDF_WIDGET_TYPE_COMBOBOX: "choice", fitz.PDF_WIDGET_TYPE_LISTBOX: "choice",
             fitz.PDF_WIDGET_TYPE_RADIOBUTTON: "radio"}


def fields(path: str) -> list:
    out, seen = [], set()
    with fitz.open(path) as doc:
        for page in doc:
            for w in page.widgets() or []:
                kind = KINDS.get(w.field_type)
                if not kind or not w.field_name or w.field_name in seen:
                    continue
                seen.add(w.field_name)
                value = w.field_value
                if kind == "checkbox":
                    value = value not in (False, None, "", "Off")
                out.append({"name": w.field_name, "label": w.field_label or w.field_name, "type": kind,
                            "value": value if value is not None else "",
                            "options": list(w.choice_values or []) if kind == "choice" else [],
                            "page": page.number})
    return out


def free(original: Path) -> Path:
    target = original.with_name(f"{original.stem} (filled).pdf")
    n = 2
    while target.exists():
        target = original.with_name(f"{original.stem} (filled {n}).pdf")
        n += 1
    return target


def fill(path: str, values: dict) -> dict:
    src = Path(path)
    target = free(src)
    with fitz.open(path) as doc:
        for page in doc:
            for w in page.widgets() or []:
                if w.field_name not in values:
                    continue
                v = values[w.field_name]
                kind = KINDS.get(w.field_type)
                if kind == "checkbox":
                    w.field_value = w.on_state() if v in (True, "true", "on", "yes", 1) else "Off"
                elif kind == "radio":
                    w.field_value = v
                else:
                    w.field_value = str(v)
                w.update()
        part = target.with_name(target.name + ".part")
        doc.save(str(part), garbage=1, deflate=True)
    part.rename(target)
    return {"saved": str(target)}


def topdf(out: str, inputs: list) -> dict:
    """MuPDF reads e-books, XPS, CBZ and pictures; each becomes PDF pages, in order."""
    with fitz.open() as pdf:
        for name in inputs:
            with fitz.open(name) as src:
                if src.is_pdf:
                    pdf.insert_pdf(src)
                    continue
                with fitz.open("pdf", src.convert_to_pdf()) as pages:
                    pdf.insert_pdf(pages)
        if not pdf.page_count:
            raise ValueError("nothing in it to show")
        pdf.save(out, garbage=1, deflate=True)
    return {"saved": out}


def main(argv: list[str]) -> int:
    if fitz is None:
        print(json.dumps({"error": "PyMuPDF (python-pymupdf) is not installed"}))
        return 3
    try:
        if len(argv) >= 3 and argv[1] == "fields":
            print(json.dumps(fields(argv[2])))
            return 0
        if len(argv) >= 4 and argv[1] == "topdf":
            print(json.dumps(topdf(argv[2], argv[3:])))
            return 0
        if len(argv) >= 3 and argv[1] == "fill":
            print(json.dumps(fill(argv[2], json.loads(sys.stdin.read() or "{}"))))
            return 0
    except (RuntimeError, ValueError, OSError) as exc:
        print(json.dumps({"error": str(exc)}))
        return 1
    print("usage: pdfform.py fields FILE | fill FILE < values.json | topdf OUT FILE...", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
