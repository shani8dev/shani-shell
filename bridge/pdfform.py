#!/usr/bin/env python3
"""pdfform — the Document Viewer's PyMuPDF half: a PDF's form fields and a filled
copy of it ("Fill in"), and a PDF copy of what is not a PDF.

    pdfform.py fields FILE       [{"name", "type": text|checkbox|choice|radio, "value", "options", "page"}]
    pdfform.py fill FILE         values as JSON on stdin ({"name": "value" | true/false});
                                 prints {"saved": path}
    pdfform.py topdf OUT FILE... an e-book (EPUB, FB2, MOBI), XPS or CBZ - or, with several
                                 FILEs, pictures in that order (a comic's pages) - as one PDF
    pdfform.py links FILE                    [{"page", "kind": uri|goto|named, ...}]
    pdfform.py attachments FILE              [{"index", "name", "size"}]
    pdfform.py attachment-save FILE INDEX OUT  save one embedded file
    pdfform.py annotations FILE              [{"page", "type", "content", "title"}]
    pdfform.py bookmarks FILE | bookmark-add FILE PAGE TITLE | bookmark-remove FILE PAGE
                                 the reader's own bookmarks, kept by the document's md5
                                 (no PDF library needed for these three)

The filled copy goes beside the original as "<name> (filled).pdf" (or
"(filled 2)" ...): the original is never written over, and the copy keeps
its fields, so it can be filled again.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

try:
    import pymupdf as fitz  # PyMuPDF; "fitz" is its old, deprecated name
except ImportError:  # pragma: no cover - the package depends on python-pymupdf
    try:
        import fitz
    except ImportError:
        fitz = None

KINDS = {}
if fitz is not None:
    KINDS = {
        fitz.PDF_WIDGET_TYPE_TEXT: "text",
        fitz.PDF_WIDGET_TYPE_CHECKBOX: "checkbox",
        fitz.PDF_WIDGET_TYPE_COMBOBOX: "choice",
        fitz.PDF_WIDGET_TYPE_LISTBOX: "choice",
        fitz.PDF_WIDGET_TYPE_RADIOBUTTON: "radio",
    }


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
                options = []
                if kind == "choice":
                    options = list(w.choice_values or [])
                elif kind == "radio":
                    # a radio group is many widgets with one name: expose the
                    # states so the reader can draw the group's choices
                    try:
                        options = [
                            k
                            for k in (w.button_states() or {}).keys()
                            if k not in ("Off", "off")
                        ]
                    except (AttributeError, RuntimeError, ValueError):
                        options = []
                out.append(
                    {
                        "name": w.field_name,
                        "label": w.field_label or w.field_name,
                        "type": kind,
                        "value": value if value is not None else "",
                        "options": options,
                        "page": page.number,
                    }
                )
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
                    w.field_value = (
                        w.on_state() if v in (True, "true", "on", "yes", 1) else "Off"
                    )
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


# ---- the reader's own bookmarks (independent of PyMuPDF) ---------------------


def bookmarks_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "shani" / "pdf-bookmarks.json"


def file_key(path: str) -> str:
    """Content md5: the same document keeps its marks however it is named."""
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_bookmarks() -> dict:
    try:
        data = json.loads(bookmarks_file().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _write_bookmarks(data: dict) -> None:
    path = bookmarks_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".shani-pdfbm-", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)


def bookmarks(path: str) -> dict:
    return {"bookmarks": _read_bookmarks().get(file_key(path), [])}


def bookmark_add(path: str, page, title: str) -> dict:
    key = file_key(path)
    data = _read_bookmarks()
    marks = data.setdefault(key, [])
    page = int(page)
    if not any(m.get("page") == page for m in marks):
        marks.append({"page": page, "title": title or "Page %d" % (page + 1)})
        marks.sort(key=lambda m: m["page"])
        _write_bookmarks(data)
    return {"bookmarks": marks}


def bookmark_remove(path: str, page) -> dict:
    key = file_key(path)
    data = _read_bookmarks()
    marks = [m for m in data.get(key, []) if m.get("page") != int(page)]
    if marks:
        data[key] = marks
    else:
        data.pop(key, None)
    _write_bookmarks(data)
    return {"bookmarks": marks}


# ---- links, embedded files and annotations (need PyMuPDF) --------------------


def links(path: str) -> dict:
    out = []
    goto = getattr(fitz, "LINK_GOTO", 1)
    uri = getattr(fitz, "LINK_URI", 2)
    named = getattr(fitz, "LINK_NAMED", 4)
    with fitz.open(path) as doc:
        for pno, page in enumerate(doc):
            for link in page.get_links() or []:
                kind = link.get("kind")
                if kind == uri:
                    out.append({"page": pno, "kind": "uri", "uri": link.get("uri", "")})
                elif kind in (goto, getattr(fitz, "LINK_GOTOR", 5)):
                    out.append(
                        {
                            "page": pno,
                            "kind": "goto",
                            "target": int(link.get("page", -1)) + 1,
                        }
                    )
                elif kind == named:
                    out.append(
                        {"page": pno, "kind": "named", "name": link.get("name", "")}
                    )
    return {"links": out}


def attachments(path: str) -> dict:
    out = []
    with fitz.open(path) as doc:
        for i in range(doc.embfile_count()):
            info = doc.embfile_info(i) or {}
            out.append(
                {
                    "index": i,
                    "name": info.get("name") or info.get("filename", ""),
                    "size": info.get("size", 0),
                }
            )
    return {"attachments": out}


def attachment_save(path: str, index, out: str) -> dict:
    with fitz.open(path) as doc:
        data = doc.embfile_get(int(index))
    Path(out).write_bytes(data)
    return {"saved": out, "size": len(data)}


def annotations(path: str) -> dict:
    out = []
    with fitz.open(path) as doc:
        for pno, page in enumerate(doc):
            for annot in page.annots() or []:
                info = annot.info or {}
                kind = annot.type
                if isinstance(kind, (tuple, list)):
                    kind = kind[1] if len(kind) > 1 else str(kind[0])
                out.append(
                    {
                        "page": pno,
                        "type": str(kind),
                        "content": info.get("content", ""),
                        "title": info.get("title", ""),
                    }
                )
    return {"annotations": out}


def main(argv: list[str]) -> int:
    # The reader's own bookmarks need no PDF library and are served first.
    if len(argv) >= 3 and argv[1] in ("bookmarks", "bookmark-add", "bookmark-remove"):
        try:
            if argv[1] == "bookmarks":
                print(json.dumps(bookmarks(argv[2])))
            elif argv[1] == "bookmark-add" and len(argv) >= 5:
                print(json.dumps(bookmark_add(argv[2], argv[3], argv[4])))
            elif argv[1] == "bookmark-remove" and len(argv) >= 4:
                print(json.dumps(bookmark_remove(argv[2], argv[3])))
            else:
                print(
                    json.dumps(
                        {
                            "error": "usage: bookmarks FILE | bookmark-add FILE PAGE TITLE | bookmark-remove FILE PAGE"
                        }
                    )
                )
                return 2
        except OSError as exc:
            print(json.dumps({"error": str(exc)}))
            return 1
        return 0
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
        if len(argv) >= 3 and argv[1] == "links":
            print(json.dumps(links(argv[2])))
            return 0
        if len(argv) >= 3 and argv[1] == "attachments":
            print(json.dumps(attachments(argv[2])))
            return 0
        if len(argv) >= 5 and argv[1] == "attachment-save":
            print(json.dumps(attachment_save(argv[2], argv[3], argv[4])))
            return 0
        if len(argv) >= 3 and argv[1] == "annotations":
            print(json.dumps(annotations(argv[2])))
            return 0
    except (RuntimeError, ValueError, OSError) as exc:
        print(json.dumps({"error": str(exc)}))
        return 1
    print(
        "usage: pdfform.py fields FILE | fill FILE < values.json | topdf OUT FILE... | links FILE | attachments FILE | attachment-save FILE INDEX OUT | annotations FILE | bookmarks FILE",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
