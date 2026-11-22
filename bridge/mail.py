#!/usr/bin/env python3
"""Mail for the shell's reader.

Two backends behind one set of commands:

  imap    a real account over IMAP (imaplib) and SMTP (smtplib)
  mailhog a developer mail server (MailHog/Mailpit): reading through its HTTP
          API, sending to its SMTP on localhost:1025 — no account, no password,
          so the whole reader can be driven by the test suite

Settings in ~/.config/shani-shell/mail.json:
  {"kind": "imap"|"mailhog", "mailhog": {"url": "http://127.0.0.1:8025"},
   "imap": {"host": "", "port": 993, "user": "", "ssl": true},
   "smtp": {"host": "", "port": 587, "user": "", "ssl": true},
   "account": {"name": "", "email": ""}}

The IMAP/SMTP password comes from $SHANI_MAIL_PASSWORD, else from the secret
service (`secret-tool lookup service shani-mail`), never from this file.

Commands, one JSON answer on stdout:
  state                 {"kind", "account": {"name","email"}}
  folders               [{"name", "unread", "total"}]
  list <folder>         [{"uid", "from", "subject", "date", "snippet", "unread"}]
  read <uid>            {"from", "to", "subject", "date", "text"}
  markread <uid>        {"ok": true}
  delete <uid>          {"ok": true}
  send <to> <subject> <body>
"""

import email
import email.policy
import html
import imaplib
import json
import os
import re
import smtplib
import ssl
import sys
import urllib.parse
import urllib.request
from email.header import decode_header, make_header
from email.utils import formatdate, parsedate_to_datetime
from pathlib import Path

CONF = Path(os.path.expanduser("~")) / ".config/shani-shell/mail.json"
TIMEOUT = 20


def conf():
    try:
        with open(CONF, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {"kind": "imap", "imap": {}, "smtp": {}, "account": {}}


def password():
    pw = os.environ.get("SHANI_MAIL_PASSWORD", "")
    if pw:
        return pw
    try:
        import subprocess

        out = subprocess.run(
            ["secret-tool", "lookup", "service", "shani-mail"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def decoded(value):
    """A header with RFC 2047 words -> text."""
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return str(value)


def strip_html(s):
    s = re.sub(r"<(script|style)\b.*?</\1>", " ", s or "", flags=re.S | re.I)
    s = re.sub(r"<br\s*/?>|</p>", "\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"\n{3,}", "\n\n", s).strip()


def part_text(part):
    """EmailMessage has get_content(); a compat32 Message does not."""
    try:
        return part.get_content()
    except AttributeError:
        payload = part.get_payload(decode=True)
        if payload is None:
            return part.get_payload() or ""
        return payload.decode(part.get_content_charset() or "utf-8", "replace")


def safe_html(markup):
    """An HTML mail body, made safe to hand to a text renderer.

    Qt's TextDocument renders a subset of HTML - no JavaScript, no plugins -
    but it will happily load an <img src="http://…">, which is how a sender
    learns that the message was opened. Everything that reaches outside the
    message goes: scripts, styles, frames, objects, event handlers, and remote
    images (replaced by a word, so the layout does not pretend). Links keep
    their text; only the href is dropped for a javascript: or data: one.
    """
    s = markup or ""
    s = re.sub(r"<(script|style|iframe|object|embed|link|meta)\b.*?</\1>", " ", s, flags=re.S | re.I)
    s = re.sub(r"<(script|style|iframe|object|embed|link|meta)\b[^>]*/?>", " ", s, flags=re.I)
    s = re.sub(r"\son[a-z]+\s*=\s*\"[^\"]*\"", " ", s, flags=re.I)
    s = re.sub(r"\son[a-z]+\s*=\s*'[^']*'", " ", s, flags=re.I)
    s = re.sub(r"\son[a-z]+\s*=\s*[^ >]+", " ", s, flags=re.I)
    s = re.sub(r"<img\b[^>]*>", " [image] ", s, flags=re.I)
    # href/src that is not http, https, mailto or a fragment
    s = re.sub(r"(href|src)\s*=\s*\"\s*(?!https?:|mailto:|#|/)[^\"]*\"", "", s, flags=re.I)
    s = re.sub(r"(href|src)\s*=\s*'\s*(?!https?:|mailto:|#|/)[^']*'", "", s, flags=re.I)
    return s


def bodies_of(message):
    """(text, html) - both as they came. A message with an HTML part and a text
    part has both; one with only HTML gets the HTML shown as text as well, so a
    reader that cannot render it still has something to say."""
    text, html_part = "", ""
    if message.is_multipart():
        for part in message.walk():
            if part.get_content_type() == "text/plain":
                text += part_text(part)
            elif part.get_content_type() == "text/html":
                html_part += part_text(part)
    elif message.get_content_type() == "text/html":
        html_part = part_text(message)
    else:
        text = part_text(message)
    return (text.strip(), html_part.strip())


def body_of(message):
    """The readable body: text/plain first, else the HTML stripped."""
    text, html_part = bodies_of(message)
    return (text or strip_html(html_part)).strip()


def attachments_of(message):
    """What came with it: [{name, type, size}] - nothing is fetched here, the
    reader names what it could save."""
    out = []
    for part in message.walk():
        if part.get_content_maintype() == "multipart":
            continue
        name = part.get_filename()
        if not name:
            continue
        payload = part.get_payload(decode=True) or b""
        out.append(
            {
                "name": decoded(name),
                "type": part.get_content_type(),
                "size": len(payload),
            }
        )
    return out


def address(value):
    """getaddresses returns (name, address): the address is what we want, and
    a bare address has an empty name."""
    addrs = email.utils.getaddresses([value or ""])
    if not addrs:
        return (value or "").strip()
    name, addr = addrs[0]
    return (addr or name).strip()


def sender(value):
    """Who it is from, as a person reads it: the name the sender gave, or the
    bare address when there is none."""
    addrs = email.utils.getaddresses([value or ""])
    if not addrs:
        return decoded(value)
    name, addr = addrs[0]
    return (decoded(name) or addr or "").strip()


# ---- mailhog ---------------------------------------------------------------


def mh_get(url, path):
    req = urllib.request.Request(url.rstrip("/") + path)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read() or b"{}")


def mh_messages(url, folder):
    if folder not in ("INBOX", "All", ""):
        return []
    data = mh_get(url, "/api/v2/messages?limit=100")
    out = []
    # MailHog 1.x calls the array "items", Mailpit "messages"
    for m in data.get("messages") or data.get("items") or []:
        content = m.get("Content") or {}
        headers = content.get("Headers") or {}
        # the list view has Body but not always Text
        snippet = strip_html(
            content.get("Text") or content.get("Body") or content.get("HTML") or ""
        )
        out.append(
            {
                "uid": str(m.get("ID")),
                "from": sender((headers.get("From") or [""])[0]),
                "subject": decoded((headers.get("Subject") or [""])[0]),
                "date": (headers.get("Date") or [""])[0],
                "snippet": snippet[:200],
                "unread": False,
            }
        )
    return out


def mh_search(url, query):
    """MailHog has no search of its own, and its API hands over the messages
    anyway: look through sender, subject and the body here."""
    q = (query or "").strip().lower()
    if not q:
        return mh_messages(url, "INBOX")
    return [
        m
        for m in mh_messages(url, "INBOX")
        if q in m["from"].lower()
        or q in m["subject"].lower()
        or q in (m.get("snippet") or "").lower()
    ]


def mh_read(url, uid):
    """MailHog's list already carries the content, and its single-message path
    does not accept every ID (a Message-ID with '=' and '@' 404s), so find the
    message in the list instead."""
    for m in mh_messages(url, "INBOX"):
        if m["uid"] != uid:
            continue
        # mh_messages keeps only a snippet; read the full content again
        data = mh_get(url, "/api/v2/messages?limit=100")
        for raw in data.get("messages") or data.get("items") or []:
            if str(raw.get("ID")) != uid:
                continue
            content = raw.get("Content") or {}
            headers = content.get("Headers") or {}
            text = content.get("Text") or ""
            html = content.get("HTML") or ""
            if not text and html:
                text = strip_html(html)
            atts = []
            for name in content.get("Attachments") or []:
                meta = name if isinstance(name, dict) else {}
                atts.append(
                    {
                        "name": decoded(meta.get("Name") or meta.get("Filename") or ""),
                        "type": meta.get("Content-Type") or "",
                        "size": int(meta.get("Size") or 0),
                    }
                )
            return {
                "from": sender((headers.get("From") or [""])[0]),
                "to": ", ".join(address(x) for x in headers.get("To") or []),
                "subject": decoded((headers.get("Subject") or [""])[0]),
                "date": (headers.get("Date") or [""])[0],
                "text": text,
                "html": safe_html(html),
                "attachments": atts,
            }
    return {"error": "no such message"}


# ---- imap ------------------------------------------------------------------


def imap_connect(c):
    imap = c.get("imap") or {}
    host, port = imap.get("host", ""), int(imap.get("port", 993))
    if imap.get("ssl", True):
        box = imaplib.IMAP4_SSL(host, port, ssl_context=ssl.create_default_context())
    else:
        box = imaplib.IMAP4(host, port)
    user = imap.get("user", "")
    pw = password()
    if user and pw:
        box.login(user, pw)
    return box


def imap_folders(c):
    box = imap_connect(c)
    try:
        status, rows = box.list()
        out = []
        for line in rows or []:
            # (\\HasNoChildren) "/" "INBOX"
            name = line.decode(errors="replace").split(' "/" ')[-1].strip().strip('"')
            if not name:
                continue
            try:
                box.select('"%s"' % name, readonly=True)
                typ, data = box.search(None, "UNSEEN")
                unread = len((data[0] or b"").split())
                typ, data = box.search(None, "ALL")
                total = len((data[0] or b"").split())
            except Exception:
                unread = total = 0
            out.append({"name": name, "unread": unread, "total": total})
        return out
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_list(c, folder):
    box = imap_connect(c)
    try:
        box.select('"%s"' % folder)
        typ, data = box.search(None, "ALL")
        ids = (data[0] or b"").split()
        out = []
        for uid in reversed(ids[-100:]):
            typ, msg = box.fetch(uid, "(BODY.PEEK[])")
            raw = msg[0][1] if msg and isinstance(msg[0], tuple) else b""
            m = email.message_from_bytes(raw, policy=email.policy.default)
            flags = b"\\Seen"
            try:
                typ, fdata = box.fetch(uid, "(FLAGS)")
                flags = fdata[0] or b""
            except Exception:
                pass
            out.append(
                {
                    "uid": uid.decode(),
                    "from": sender(m.get("From", "")),
                    "subject": decoded(m.get("Subject", "")) or "(no subject)",
                    "date": m.get("Date", ""),
                    "snippet": body_of(m)[:200].replace("\n", " "),
                    "unread": b"\\Seen" not in flags,
                }
            )
        return out
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_search(c, query, folder="INBOX"):
    """IMAP's own SEARCH (TEXT), so the server does the looking - the reader is
    not asked to fetch a whole mailbox to find one word."""
    q = (query or "").strip()
    if not q:
        return imap_list(c, folder)
    box = imap_connect(c)
    try:
        box.select(folder)
        typ, data = box.uid("SEARCH", "CHARSET", "UTF-8", "TEXT", q)
        uids = (data[0] or b"").split() if data else []
        out = []
        for uid in uids[-100:]:
            typ, msg = box.uid(
                "FETCH", uid, "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])"
            )
            raw = msg[0][1] if msg and isinstance(msg[0], tuple) else b""
            m = email.message_from_bytes(raw)
            out.append(
                {
                    "uid": uid.decode(),
                    "from": sender(m.get("From", "")),
                    "subject": decoded(m.get("Subject", "")) or "(no subject)",
                    "date": m.get("Date", ""),
                    "snippet": q,
                    "unread": False,
                }
            )
        return out
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_read(c, uid, folder="INBOX"):
    box = imap_connect(c)
    try:
        box.select(folder or "INBOX")
        typ, msg = box.fetch(uid.encode(), "(BODY.PEEK[])")
        raw = msg[0][1] if msg and isinstance(msg[0], tuple) else b""
        m = email.message_from_bytes(raw, policy=email.policy.default)
        text, html = bodies_of(m)
        return {
            "from": sender(m.get("From", "")),
            "to": address(decoded(m.get("To", ""))),
            "subject": decoded(m.get("Subject", "")),
            "date": m.get("Date", ""),
            "text": text or strip_html(html),
            "html": safe_html(html),
            "attachments": attachments_of(m),
        }
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_flag(c, uid, flag, on, folder="INBOX"):
    box = imap_connect(c)
    try:
        box.select(folder or "INBOX")
        box.store(uid.encode(), ("+%s" if on else "-%s") % flag, "FLAGS")
        return {"ok": True}
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_delete(c, uid, folder="INBOX"):
    box = imap_connect(c)
    try:
        box.select(folder or "INBOX")
        box.store(uid.encode(), "+FLAGS", "\\Deleted")
        box.expunge()
        return {"ok": True}
    finally:
        try:
            box.logout()
        except Exception:
            pass


# ---- sending ---------------------------------------------------------------


def send(c, to, subject, body):
    smtp = c.get("smtp") or {}
    host, port = smtp.get("host", ""), int(smtp.get("port", 587))
    user = smtp.get("user", "")
    pw = password()
    msg = email.message.EmailMessage()
    msg["From"] = (c.get("account") or {}).get("email") or user
    msg["To"] = to
    msg["Subject"] = subject
    msg["Date"] = formatdate(localtime=True)
    msg.set_content(body)
    if smtp.get("ssl", True):
        with smtplib.SMTP_SSL(
            host, port, timeout=TIMEOUT, context=ssl.create_default_context()
        ) as s:
            if user and pw:
                s.login(user, pw)
            s.send_message(msg)
    else:
        with smtplib.SMTP(host, port, timeout=TIMEOUT) as s:
            s.ehlo()
            # MailHog and a local relay often have no STARTTLS at all
            if s.has_extn("starttls"):
                s.starttls(context=ssl.create_default_context())
                s.ehlo()
            if user and pw:
                s.login(user, pw)
            s.send_message(msg)
    return {"ok": True}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: mail.py <command> [args]"}))
        return 2
    cmd, args = sys.argv[1], sys.argv[2:]
    c = conf()
    kind = (c.get("kind") or "imap").lower()
    # mailhog's SMTP is local and unauthenticated; a real account uses its own
    if kind == "mailhog":
        url = (c.get("mailhog") or {}).get("url", "http://127.0.0.1:8025")
        if cmd == "state":
            print(json.dumps({"kind": "mailhog", "account": c.get("account") or {}}))
            return 0
        if cmd == "folders":
            msgs = mh_messages(url, "INBOX")
            print(json.dumps([{"name": "INBOX", "unread": 0, "total": len(msgs)}]))
            return 0
        if cmd == "list":
            print(
                json.dumps(
                    mh_messages(url, args[0] if args else "INBOX"), ensure_ascii=False
                )
            )
            return 0
        if cmd == "read":
            print(json.dumps(mh_read(url, args[0]), ensure_ascii=False))
            return 0
        if cmd == "search":
            print(json.dumps(mh_search(url, args[0] if args else ""), ensure_ascii=False))
            return 0
        if cmd in ("markread", "delete"):
            print(json.dumps({"ok": True}))
            return 0
        if cmd == "send":
            if len(args) < 3:
                print(json.dumps({"error": "send needs to, subject and body"}))
                return 2
            # MailHog's SMTP is on 1025 on the same host as its API
            host = urllib.parse.urlparse(url).hostname or "127.0.0.1"
            print(
                json.dumps(
                    send(
                        {
                            "smtp": {"host": host, "port": 1025, "ssl": False},
                            "account": c.get("account") or {},
                        },
                        args[0],
                        args[1],
                        args[2],
                    )
                )
            )
            return 0
        print(json.dumps({"error": "unknown command: " + cmd}))
        return 2

    if cmd == "state":
        print(json.dumps({"kind": "imap", "account": c.get("account") or {}}))
        return 0
    if cmd == "folders":
        print(json.dumps(imap_folders(c), ensure_ascii=False))
        return 0
    if cmd == "list":
        print(
            json.dumps(imap_list(c, args[0] if args else "INBOX"), ensure_ascii=False)
        )
        return 0
    if cmd == "read":
        print(json.dumps(imap_read(c, args[0], args[1] if len(args) > 1 else "INBOX"), ensure_ascii=False))
        return 0
    if cmd == "search":
        print(json.dumps(imap_search(c, args[0], args[1] if len(args) > 1 else "INBOX"), ensure_ascii=False))
        return 0
    if cmd == "markread":
        print(json.dumps(imap_flag(c, args[0], "\\Seen", True, args[1] if len(args) > 1 else "INBOX")))
        return 0
    if cmd == "delete":
        print(json.dumps(imap_delete(c, args[0], args[1] if len(args) > 1 else "INBOX")))
        return 0
    if cmd == "send":
        if len(args) < 3:
            print(json.dumps({"error": "send needs to, subject and body"}))
            return 2
        print(json.dumps(send(c, args[0], args[1], args[2])))
        return 0
    print(json.dumps({"error": "unknown command: " + cmd}))
    return 2


if __name__ == "__main__":
    sys.exit(main())
