"""bridge/mail.py: saving an attachment.

The reader lists attachments but cannot save them, so this pins the whole path:
the fake MailHog's seeded attachment is decoded and written byte for byte, a
name that could escape the picked path is refused, an index that is not there
is an error, and the command's JSON answer has the shape the shell reads.

The stand-in server (dev/fake-mailhog.py) is imported the way the other bridge
tests load their bridge - the same seeded message the shell suite uses - and
its /api/v2/messages reply is handed to the bridge, so no socket is opened.
"""

import base64
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/mail.py"
FAKE = ROOT / "dev/fake-mailhog.py"

CFG = {"kind": "mailhog", "mailhog": {"url": "http://127.0.0.1:8025"}}


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def load_both():
    return load("mail_under_test", BRIDGE), load("fake_mailhog_under_test", FAKE)


def serve(monkeypatch, m, messages):
    """The bridge reads MailHog over HTTP; hand it a canned list instead."""
    monkeypatch.setattr(m, "mh_get", lambda url, path: {"messages": messages})


def run(m, *args):
    """One bridge command, as the shell runs it: argv in, one JSON line out."""
    buf = io.StringIO()
    old = sys.argv
    sys.argv = ["mail.py"] + list(args)
    try:
        with contextlib.redirect_stdout(buf):
            code = m.main()
    finally:
        sys.argv = old
    return code, json.loads(buf.getvalue())


def test_the_fake_lists_its_attachment(monkeypatch):
    """The listing the shell shows must stay ['readme.txt']."""
    m, fake = load_both()
    serve(monkeypatch, m, fake.MESSAGES)
    read = m.mh_read(CFG["mailhog"]["url"], "mail-1", {})
    assert [a["name"] for a in read["attachments"]] == ["readme.txt"]
    assert read["attachments"][0]["size"] == len(fake.README)


def test_saving_an_attachment_writes_the_exact_bytes(tmp_path, monkeypatch):
    m, fake = load_both()
    serve(monkeypatch, m, fake.MESSAGES)
    dest = tmp_path / "readme.txt"

    out = m.save_attachment(CFG, "mail-1", 0, str(dest))

    assert out["ok"] is True
    assert out["name"] == "readme.txt"
    assert out["path"] == str(dest)
    assert out["size"] == len(fake.README)
    assert dest.read_bytes() == b"Shani shell readme.\n"


@pytest.mark.parametrize("name", ["../evil.txt", "/etc/passwd", "dir/file.txt"])
def test_a_name_that_could_escape_is_refused(tmp_path, monkeypatch, name):
    m, _ = load_both()
    serve(
        monkeypatch,
        m,
        [
            {
                "ID": "mail-9",
                "Content": {
                    "Headers": {"From": ["a@b.c"]},
                    "Body": "body",
                    "Attachments": [
                        {
                            "Name": name,
                            "Content-Type": "text/plain",
                            "Content": base64.b64encode(b"payload").decode("ascii"),
                        }
                    ],
                },
            }
        ],
    )
    dest = tmp_path / "evil.txt"

    out = m.save_attachment(CFG, "mail-9", 0, str(dest))

    assert "ok" not in out
    assert "error" in out
    assert not dest.exists()


def test_a_missing_index_is_an_error(tmp_path, monkeypatch):
    m, fake = load_both()
    serve(monkeypatch, m, fake.MESSAGES)
    dest = tmp_path / "out.bin"

    for index in (5, -1):
        out = m.save_attachment(CFG, "mail-1", index, str(dest))
        assert "error" in out, index
        assert "ok" not in out, index
        assert not dest.exists()


def test_the_command_answers_one_json_line(tmp_path, monkeypatch):
    """The shell parses one JSON object: ok and path, or an error."""
    m, fake = load_both()
    serve(monkeypatch, m, fake.MESSAGES)
    m.CONF = tmp_path / "mail.json"
    m.CONF.write_text(json.dumps(CFG), encoding="utf-8")
    dest = tmp_path / "readme.txt"

    code, out = run(m, "save", "mail-1", "0", str(dest))

    assert code == 0
    assert out["ok"] is True
    assert out["path"] == str(dest)
    assert out["name"] == "readme.txt"
    assert dest.read_bytes() == b"Shani shell readme.\n"

    code, out = run(m, "save", "mail-1", "9", str(dest))
    assert code == 0
    assert out == {"error": "no such attachment"}


def test_a_mailhog_message_without_attachment_bytes_is_parsed_as_mime(
    tmp_path, monkeypatch
):
    """Older MailHog lists {Name, Content-Type, Size} only; the part is in Body."""
    m, _ = load_both()
    boundary = "B"
    body = (
        "--B\n"
        "Content-Type: text/plain\n\n"
        "body\n"
        "--B\n"
        'Content-Type: text/plain; name="note.txt"\n'
        'Content-Disposition: attachment; filename="note.txt"\n'
        "Content-Transfer-Encoding: base64\n\n"
        + base64.b64encode(b"note bytes").decode("ascii")
        + "\n"
        "--B--\n"
    )
    serve(
        monkeypatch,
        m,
        [
            {
                "ID": "mail-3",
                "Content": {
                    "Headers": {
                        "From": ["a@b.c"],
                        "MIME-Version": ["1.0"],
                        "Content-Type": ['multipart/mixed; boundary="%s"' % boundary],
                    },
                    "Body": body,
                },
            }
        ],
    )
    dest = tmp_path / "note.txt"

    out = m.save_attachment(CFG, "mail-3", 0, str(dest))

    assert out["ok"] is True
    assert out["name"] == "note.txt"
    assert dest.read_bytes() == b"note bytes"
