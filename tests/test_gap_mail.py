"""Mail gaps: Cc/Bcc, saved attachments, flags and archive, view source and
opt-in remote images.

The command dispatcher is driven with a private config and fake IMAP/SMTP
objects, so each assertion follows the same path the service takes.
"""

import contextlib
import email
import email.policy
import importlib.machinery
import importlib.util
import io
import json
import sys
from email.message import EmailMessage
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/mail.py"
SERVICE = ROOT / "shani/Services/Mail.qml"
WINDOW = ROOT / "shani/Modules/Mail/MailWindow.qml"


def load(tmp=None):
    loader = importlib.machinery.SourceFileLoader("mail_gap_under_test", str(BRIDGE))
    spec = importlib.util.spec_from_loader("mail_gap_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    if tmp is not None:
        mod.CONF = tmp / "mail.json"
    return mod


def run(mod, *args):
    buf = io.StringIO()
    old = sys.argv
    sys.argv = ["mail.py"] + list(args)
    try:
        with contextlib.redirect_stdout(buf):
            rc = mod.main()
    finally:
        sys.argv = old
    return rc, json.loads(buf.getvalue() or "null")


def raw_mail():
    m = EmailMessage()
    m["From"] = "a@b.c"
    m["To"] = "d@e.f"
    m["Subject"] = "Hi"
    m.set_content("hello body")
    m.add_attachment(
        b"ATTACH-BYTES",
        maintype="application",
        subtype="octet-stream",
        filename="note.bin",
    )
    return m.as_bytes()


def raw_html_mail():
    m = EmailMessage()
    m["From"] = "a@b.c"
    m["To"] = "d@e.f"
    m["Subject"] = "Html"
    m.set_content("plain")
    m.add_alternative('<p>Hi</p><img src="http://tracker/x.png">', subtype="html")
    return m.as_bytes()


class FakeBox:
    def __init__(self, raw=b"", flags=b"\\Seen"):
        self.raw, self.flags, self.calls = raw, flags, []

    def select(self, *a, **k):
        self.calls.append(("select",) + a)

    def fetch(self, uid, what):
        self.calls.append(("fetch", uid, what))
        if what == "(FLAGS)":
            return ("OK", [self.flags])
        return ("OK", [(b"1", self.raw)])

    def search(self, *a):
        return ("OK", [b"1"])

    def store(self, *a):
        self.calls.append(("store",) + a)

    def copy(self, *a):
        self.calls.append(("copy",) + a)

    def expunge(self):
        self.calls.append(("expunge",))

    def logout(self):
        pass


class FakeSMTP:
    last = None

    def __init__(self, *a, **k):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        pass

    def login(self, *a):
        pass

    def ehlo(self):
        pass

    def has_extn(self, name):
        return False

    def starttls(self, *a):
        pass

    def send_message(self, msg, to_addrs=None):
        FakeSMTP.last = (msg, to_addrs)


def test_attachment_data_decodes_only_the_listed_parts():
    m = load()
    msg = email.message_from_bytes(raw_mail(), policy=email.policy.default)
    assert [a["name"] for a in m.attachments_of(msg)] == ["note.bin"]
    name, payload = m.attachment_data(msg, 0)
    assert name == "note.bin" and payload == b"ATTACH-BYTES"
    assert m.attachment_data(msg, 4) is None


def test_save_attachment_command_writes_the_decoded_bytes(tmp_path, monkeypatch):
    m = load(tmp_path)
    monkeypatch.setattr(m, "imap_connect", lambda c: FakeBox(raw=raw_mail()))
    out = tmp_path / "saved.bin"
    rc, answer = run(m, "saveattachment", "1", "0", str(out))
    assert rc == 0 and answer["ok"] is True
    assert out.read_bytes() == b"ATTACH-BYTES"
    assert answer["name"] == "note.bin" and answer["size"] == len(b"ATTACH-BYTES")


def test_send_accepts_cc_and_bcc_without_leaking_the_bcc(monkeypatch):
    m = load()
    monkeypatch.setattr(m.smtplib, "SMTP_SSL", FakeSMTP)
    monkeypatch.setattr(m, "password", lambda: "")
    FakeSMTP.last = None
    rc, answer = run(m, "send", "to@x", "Subject", "Body", "cc@x", "bcc@x")
    assert rc == 0 and answer["ok"]
    msg, recipients = FakeSMTP.last
    assert msg["To"] == "to@x" and msg["Cc"] == "cc@x"
    assert "Bcc" not in msg
    assert recipients == ["to@x", "cc@x", "bcc@x"]


def test_flag_mark_unread_and_archive_reach_imap(monkeypatch):
    m = load()
    box = FakeBox()
    monkeypatch.setattr(m, "imap_connect", lambda c: box)
    rc, answer = run(m, "flag", "1", "\\Flagged", "1")
    assert rc == 0 and answer["ok"]
    assert ("store", b"1", "+FLAGS", "\\Flagged") in box.calls
    run(m, "markunread", "1")
    assert ("store", b"1", "-FLAGS", "\\Seen") in box.calls
    run(m, "move", "1", "Archive")
    assert ("copy", b"1", '"Archive"') in box.calls
    assert ("expunge",) in box.calls


def test_list_and_read_report_the_starred_flag(monkeypatch):
    m = load()
    monkeypatch.setattr(
        m, "imap_connect", lambda c: FakeBox(raw=raw_mail(), flags=b"\\Flagged")
    )
    rc, rows = run(m, "list", "INBOX")
    assert rc == 0 and rows[0]["starred"] is True
    rc, message = run(m, "read", "1")
    assert rc == 0 and message["starred"] is True


def test_source_returns_the_message_as_it_arrived(monkeypatch):
    m = load()
    monkeypatch.setattr(m, "imap_connect", lambda c: FakeBox(raw=raw_mail()))
    rc, answer = run(m, "source", "1")
    assert rc == 0 and "Subject: Hi" in answer["source"]


def test_remote_images_are_opt_in_and_scripts_stay_stripped(tmp_path, monkeypatch):
    m = load(tmp_path)
    html = '<p>Hi</p><img src="http://tracker/x.png"><script>alert(1)</script>'
    assert "[image]" in m.safe_html(html)
    assert "tracker" not in m.safe_html(html)
    assert "tracker" in m.safe_html(html, True)
    assert "alert" not in m.safe_html(html, True)
    rc, answer = run(m, "setremote", "1")
    assert rc == 0 and answer["remote"] is True and m.conf()["remoteImages"] is True
    monkeypatch.setattr(m, "imap_connect", lambda c: FakeBox(raw=raw_html_mail()))
    rc, message = run(m, "read", "1")
    assert rc == 0 and "tracker" in message["html"]


def test_mailhog_accepts_source_save_attachment_and_flags(tmp_path, monkeypatch):
    m = load(tmp_path)
    m.save_conf(
        {"kind": "mailhog", "mailhog": {"url": "http://127.0.0.1:8025"}, "account": {}}
    )
    payload = {
        "messages": [
            {
                "ID": "1",
                "Raw": "Subject: Hi\n\nbody",
                "Content": {
                    "Headers": {"From": ["a@b.c"], "Subject": ["Hi"]},
                    "Body": "body",
                    "Attachments": [
                        {
                            "Name": "x.txt",
                            "Content-Type": "text/plain",
                            "Size": 5,
                            "Content": "aGVsbG8=",
                        }
                    ],
                },
            }
        ]
    }
    monkeypatch.setattr(m, "mh_get", lambda url, path: payload)
    rc, answer = run(m, "source", "1")
    assert rc == 0 and "Subject: Hi" in answer["source"]
    out = tmp_path / "x.txt"
    rc, answer = run(m, "saveattachment", "1", "0", str(out))
    assert rc == 0 and out.read_bytes() == b"hello"
    rc, answer = run(m, "flag", "1", "\\Flagged", "1")
    assert rc == 0 and answer["ok"]


def test_ui_wires_the_new_mail_commands():
    service = SERVICE.read_text()
    window = WINDOW.read_text()
    for cmd in ("markunread", "flag", "move", "source", "saveattachment", "setremote"):
        assert '"%s"' % cmd in service
    assert "ccBox" in window and "bccBox" in window
    assert "Save attachment" in window and "View source" in window
    assert "Load images" in window and "Archive" in window
