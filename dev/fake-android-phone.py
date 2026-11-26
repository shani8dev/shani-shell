#!/usr/bin/env python3
"""Build the stand-in phone tree for the Android tools' live check and tests.

    python3 dev/fake-android-phone.py <folder>

The folder is what dev/fake-adb-full.py reads when SHANI_FAKE_PHONE_DIR points
at it: /sdcard media under sdcard/, and contacts.vcf, sms.txt and calls.txt for
the content queries. Dates are fixed so a second backup copies nothing. No
hardware, no app, no real phone data.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime
from pathlib import Path

#: (relative path under sdcard/, bytes, fixed mtime)
MEDIA = (
    ("DCIM/Camera/IMG_0001.jpg", b"photo one\n" + b"x" * 2048, "2026-01-02 10:30:00"),
    ("DCIM/Camera/IMG_0002.jpg", b"photo two\n" + b"y" * 3072, "2026-02-03 11:45:00"),
    ("DCIM/Camera/IMG_0003.jpg", b"photo three\n" + b"z" * 1024, "2026-03-04 09:15:00"),
    ("Pictures/PIC_0001.png", b"\x89PNG\r\n\x1a\n" + b"p" * 512, "2026-01-11 08:05:00"),
    ("Movies/clip.mp4", b"movie bytes" + b"m" * 8192, "2026-02-20 18:30:00"),
    ("Download/report.pdf", b"%PDF-1.4 report " + b"r" * 640, "2026-01-15 14:20:00"),
    ("Download/song.mp3", b"ID3 song" + b"s" * 1536, "2026-02-01 12:00:00"),
    ("Documents/notes.txt", b"Meeting notes from the phone.\n", "2026-03-01 16:10:00"),
    ("Documents/todo.txt", b"Buy milk; call home.\n", "2026-03-02 17:00:00"),
)

VCF = """BEGIN:VCARD
VERSION:3.0
FN:Alice Smith
TEL;TYPE=CELL:+15550100
END:VCARD
BEGIN:VCARD
VERSION:3.0
FN:Bob Patil
TEL;TYPE=CELL:+15550101
END:VCARD
BEGIN:VCARD
VERSION:3.0
FN:Carol Dias
TEL;TYPE=CELL:+15550102
END:VCARD
"""

SMS = (
    "+15550100|1767311400000|Lunch on Friday",
    "+15550101|1767397800000|The train is at nine",
    "+15550102|1767484200000|Thanks, see you then",
)

CALLS = (
    "Alice Smith|+15550100|1767311400000|2",
    "Bob Patil|+15550101|1767397800000|3",
    "Unknown|+15550199|1767484200000|1",
)


def stamp(raw: str) -> float:
    return datetime.strptime(raw, "%Y-%m-%d %H:%M:%S").timestamp()


def build(folder: Path) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    for relative, content, when in MEDIA:
        target = folder / "sdcard" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        os.utime(target, (stamp(when), stamp(when)))
    (folder / "contacts.vcf").write_text(VCF, encoding="utf-8")
    (folder / "sms.txt").write_text("\n".join(SMS) + "\n", encoding="utf-8")
    (folder / "calls.txt").write_text("\n".join(CALLS) + "\n", encoding="utf-8")
    return folder


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: fake-android-phone.py <folder>", file=sys.stderr)
        return 2
    print(build(Path(sys.argv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
