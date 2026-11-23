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
  read <uid>            {"from", "to", "subject", "date", "text", "html", "attachments", "starred"}
  markread <uid>        {"ok": true}
  markunread <uid>      {"ok": true}
  flag <uid> <flag> <on> [folder]   e.g. \\Flagged for a star
  move <uid> <folder>   move to another folder (Archive)
  source <uid>          {"source": "..."}  the message as it arrived
  save <uid> <index> <dest> [folder]  decode one MIME part to a file
  setremote <0|1>       opt in to remote images in HTML mail
  delete <uid>          {"ok": true}
  send <to> <subject> <body> [cc] [bcc]
"""

import base64
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


def save_conf(data):
    CONF.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONF.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, CONF)


def cmd_setremote(on):
    """Opt in to remote images in HTML mail; scripts stay stripped either way."""
    d = conf()
    d["remoteImages"] = bool(on)
    save_conf(d)
    return {"ok": True, "remote": bool(on)}


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


def safe_html(markup, allow_remote=False):
    """An HTML mail body, made safe to hand to a text renderer.

    Qt's TextDocument renders a subset of HTML - no JavaScript, no plugins -
    but it will happily load an <img src="http://…">, which is how a sender
    learns that the message was opened. Everything that reaches outside the
    message goes: scripts, styles, frames, objects, event handlers, and remote
    images (replaced by a word, so the layout does not pretend). Links keep
    their text; only the href is dropped for a javascript: or data: one.
    """
    s = markup or ""
    s = re.sub(
        r"<(script|style|iframe|object|embed|link|meta)\b.*?</\1>",
        " ",
        s,
        flags=re.S | re.I,
    )
    s = re.sub(
        r"<(script|style|iframe|object|embed|link|meta)\b[^>]*/?>", " ", s, flags=re.I
    )
    s = re.sub(r"\son[a-z]+\s*=\s*\"[^\"]*\"", " ", s, flags=re.I)
    s = re.sub(r"\son[a-z]+\s*=\s*'[^']*'", " ", s, flags=re.I)
    s = re.sub(r"\son[a-z]+\s*=\s*[^ >]+", " ", s, flags=re.I)
    # remote images are off unless the person opted in: a tracker pixel is how
    # a sender learns the message was opened. Scripts and handlers stay out in
    # either case; only the image itself is conditional.
    if not allow_remote:
        s = re.sub(r"<img\b[^>]*>", " [image] ", s, flags=re.I)
    # href/src that is not http, https, mailto or a fragment
    s = re.sub(
        r"(href|src)\s*=\s*\"\s*(?!https?:|mailto:|#|/)[^\"]*\"", "", s, flags=re.I
    )
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


def attachment_parts(message):
    """The MIME parts with a filename, in the order the reader lists them."""
    return [
        p
        for p in message.walk()
        if p.get_content_maintype() != "multipart" and p.get_filename()
    ]


def attachment_data(message, index):
    """(name, bytes) for one listed attachment, or None if it is not there."""
    parts = attachment_parts(message)
    if index < 0 or index >= len(parts):
        return None
    part = parts[index]
    return decoded(part.get_filename() or ""), part.get_payload(decode=True) or b""


def attachments_of(message):
    """What came with it: [{name, type, size}] - nothing is fetched here, the
    reader names what it could save."""
    out = []
    for part in attachment_parts(message):
        payload = part.get_payload(decode=True) or b""
        out.append(
            {
                "name": decoded(part.get_filename()),
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


def search_rank(row, q):
    """Relevance of a hit: subject outranks sender, which outranks the body."""
    return (
        (3 if q in (row.get("subject") or "").lower() else 0)
        + (2 if q in (row.get("from") or "").lower() else 0)
        + (1 if q in (row.get("snippet") or "").lower() else 0)
    )


def date_rank(row):
    """Sortable timestamp from a Date header; an unreadable date sorts oldest."""
    try:
        return parsedate_to_datetime(row.get("date") or "").timestamp()
    except Exception:
        return 0


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
                "starred": False,
            }
        )
    return out


def mh_search(url, query):
    """MailHog has no search of its own, and its API hands over the messages
    anyway: look through sender, subject and the body here."""
    q = (query or "").strip().lower()
    if not q:
        return mh_messages(url, "INBOX")
    hits = [
        m
        for m in mh_messages(url, "INBOX")
        if q in m["from"].lower()
        or q in m["subject"].lower()
        or q in (m.get("snippet") or "").lower()
    ]
    hits.sort(key=lambda m: (search_rank(m, q), date_rank(m)), reverse=True)
    return hits


def mh_read(url, uid, cfg=None):
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
                "html": safe_html(html, bool((cfg or {}).get("remoteImages"))),
                "attachments": atts,
                "starred": False,
            }
    return {"error": "no such message"}


def mh_message(content):
    """The body MailHog keeps, put back into a MIME message.

    The API stores the headers and the body apart (Content.Headers,
    Content.Body); joining them is what the email module can walk, and it is
    where the parts live when Content.Attachments carries no bytes.
    """
    lines = []
    for key, values in (content.get("Headers") or {}).items():
        for value in values or []:
            lines.append("%s: %s" % (key, decoded(value)))
    body = content.get("Body") or ""
    raw = "\r\n".join(lines) + "\r\n\r\n" + body
    return email.message_from_string(raw, policy=email.policy.default)


def mh_attachment_data(url, uid, index):
    """(name, bytes) of one MailHog attachment.

    The API's Content.Attachments carries the bytes base64 in its "Content"
    (MailHog's own MIME field is base64 too); a server that lists only
    {Name, Content-Type, Size} still has the part in Content.Body, so that is
    parsed as MIME when the list has no bytes for this index.
    """
    data = mh_get(url, "/api/v2/messages?limit=100")
    for raw in data.get("messages") or data.get("items") or []:
        if str(raw.get("ID")) != uid:
            continue
        content = raw.get("Content") or {}
        atts = content.get("Attachments") or []
        if 0 <= index < len(atts):
            meta = atts[index] if isinstance(atts[index], dict) else {}
            payload = meta.get("Content")
            if isinstance(payload, str):
                try:
                    payload = base64.b64decode(payload)
                except Exception:
                    payload = payload.encode("utf-8", "replace")
            if payload is not None:
                name = decoded(meta.get("Name") or meta.get("Filename") or "attachment")
                return name, payload
        return attachment_data(mh_message(content), index)
    return None


def mh_source(url, uid):
    """The raw message MailHog keeps, or a reconstruction from its headers."""
    data = mh_get(url, "/api/v2/messages?limit=100")
    for raw in data.get("messages") or data.get("items") or []:
        if str(raw.get("ID")) != uid:
            continue
        if raw.get("Raw"):
            return {"source": raw["Raw"]}
        content = raw.get("Content") or {}
        lines = []
        for key, values in (content.get("Headers") or {}).items():
            for value in values or []:
                lines.append("%s: %s" % (key, decoded(value)))
        lines += ["", content.get("Body") or content.get("Text") or ""]
        return {"source": "\n".join(lines)}
    return {"error": "no such message"}


# ---- imap ------------------------------------------------------------------


def imap_connect(c):
    imap = c.get("imap") or {}
    host, port = imap.get("host", ""), int(imap.get("port", 993))
    local = host in ("localhost", "127.0.0.1", "::1") or host.startswith("127.")
    # Implicit TLS on 993; port 143 must explicitly upgrade with STARTTLS before
    # any credentials are sent. Never LOGIN in the clear to a remote server.
    implicit = imap.get("ssl", port == 993)
    if implicit:
        box = imaplib.IMAP4_SSL(
            host, port, ssl_context=ssl.create_default_context(), timeout=TIMEOUT
        )
    else:
        box = imaplib.IMAP4(host, port, timeout=TIMEOUT)
        if not local:
            box.ehlo()
            if box.has_capability("STARTTLS"):
                box.starttls(ssl_context=ssl.create_default_context())
                box.ehlo()
            else:
                box.logout()
                raise ValueError(
                    "The mail server does not offer STARTTLS — refusing to send the password in the clear"
                )
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
                    "starred": b"\\Flagged" in flags,
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
        ql = q.lower()
        out.sort(key=lambda m: (search_rank(m, ql), date_rank(m)), reverse=True)
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
        flags = b""
        try:
            typ, fdata = box.fetch(uid.encode(), "(FLAGS)")
            flags = fdata[0] or b""
        except Exception:
            pass
        return {
            "from": sender(m.get("From", "")),
            "to": address(decoded(m.get("To", ""))),
            "subject": decoded(m.get("Subject", "")),
            "date": m.get("Date", ""),
            "text": text or strip_html(html),
            "html": safe_html(html, bool(c.get("remoteImages"))),
            "attachments": attachments_of(m),
            "starred": b"\\Flagged" in flags,
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
        box.store(uid.encode(), "+FLAGS" if on else "-FLAGS", flag)
        return {"ok": True}
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_move(c, uid, target, folder="INBOX"):
    """Copy to the target folder, then delete the original (an archive)."""
    box = imap_connect(c)
    try:
        box.select(folder or "INBOX", readonly=False)
        box.copy(uid.encode(), '"%s"' % target)
        box.store(uid.encode(), "+FLAGS", "\\Deleted")
        box.expunge()
        return {"ok": True}
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_source(c, uid, folder="INBOX"):
    box = imap_connect(c)
    try:
        box.select(folder or "INBOX", readonly=True)
        typ, msg = box.fetch(uid.encode(), "(BODY.PEEK[])")
        raw = msg[0][1] if msg and isinstance(msg[0], tuple) else b""
        return {"source": raw.decode("utf-8", "replace")}
    finally:
        try:
            box.logout()
        except Exception:
            pass


def imap_attachment_data(c, uid, index, folder="INBOX"):
    box = imap_connect(c)
    try:
        box.select(folder or "INBOX", readonly=True)
        typ, msg = box.fetch(uid.encode(), "(BODY.PEEK[])")
        raw = msg[0][1] if msg and isinstance(msg[0], tuple) else b""
        return attachment_data(
            email.message_from_bytes(raw, policy=email.policy.default), index
        )
    finally:
        try:
            box.logout()
        except Exception:
            pass


def save_attachment(c, uid, index, path, folder="INBOX"):
    """Decode one MIME part straight to a path the person picked in a dialog."""
    try:
        index = int(index)
    except Exception:
        return {"error": "attachment number must be a whole number"}
    kind = (c.get("kind") or "imap").lower()
    if kind == "mailhog":
        url = (c.get("mailhog") or {}).get("url", "http://127.0.0.1:8025")
        got = mh_attachment_data(url, uid, index)
    else:
        got = imap_attachment_data(c, uid, index, folder)
    if not got:
        return {"error": "no such attachment"}
    name, payload = got
    # the reader picks the path, not the attachment: a name with a separator or
    # a parent hop is refused rather than quietly written where it points
    if "/" in name or ".." in name:
        return {"error": "attachment name is not safe to save"}
    target = Path(path).expanduser() if path else None
    if target is None or str(target) in ("", "."):
        return {"error": "no path to save to"}
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "wb") as fh:
            fh.write(payload)
    except OSError as exc:
        return {"error": str(exc) or "could not write the attachment"}
    return {"ok": True, "name": name, "path": str(target), "size": len(payload)}


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


def _recipients(*fields):
    """Split address fields into one flat, trimmed recipient list."""
    out = []
    for field in fields:
        for addr in (field or "").split(","):
            addr = addr.strip()
            if addr and addr not in out:
                out.append(addr)
    return out


def send(c, to, subject, body, cc="", bcc=""):
    smtp = c.get("smtp") or {}
    host, port = smtp.get("host", ""), int(smtp.get("port", 587))
    user = smtp.get("user", "")
    pw = password()
    msg = email.message.EmailMessage()
    msg["From"] = (c.get("account") or {}).get("email") or user
    msg["To"] = to
    if cc:
        msg["Cc"] = cc
    msg["Subject"] = subject
    msg["Date"] = formatdate(localtime=True)
    msg.set_content(body)
    # Bcc must reach the server but never appear in the headers recipients see.
    # Passing an explicit envelope sidesteps send_message's header-derived list.
    recipients = _recipients(to, cc, bcc)
    local = host in ("localhost", "127.0.0.1", "::1") or host.startswith("127.")
    # Implicit TLS (SMTP_SSL) belongs on 465. Port 587/25 use STARTTLS. An
    # explicit `ssl:true` for 465 still works; otherwise derive it from the port
    # so a fresh config on 587 cannot silently wrap the wrong protocol.
    implicit = smtp.get("ssl", port == 465)
    if implicit:
        with smtplib.SMTP_SSL(
            host, port, timeout=TIMEOUT, context=ssl.create_default_context()
        ) as s:
            if user and pw:
                s.login(user, pw)
            s.send_message(msg, to_addrs=recipients)
    else:
        with smtplib.SMTP(host, port, timeout=TIMEOUT) as s:
            s.ehlo()
            # MailHog and a local relay often have no STARTTLS at all; a remote
            # provider must offer it, otherwise do not send credentials in clear.
            if s.has_extn("starttls"):
                s.starttls(context=ssl.create_default_context())
                s.ehlo()
            elif not local and user and pw:
                return {
                    "error": "The mail server does not offer STARTTLS — refusing to send the password in the clear"
                }
            if user and pw:
                s.login(user, pw)
            s.send_message(msg, to_addrs=recipients)
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
            print(
                json.dumps(
                    {
                        "kind": "mailhog",
                        "account": c.get("account") or {},
                        "remoteImages": bool(c.get("remoteImages")),
                    }
                )
            )
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
            print(json.dumps(mh_read(url, args[0], c), ensure_ascii=False))
            return 0
        if cmd == "search":
            print(
                json.dumps(mh_search(url, args[0] if args else ""), ensure_ascii=False)
            )
            return 0
        if cmd in ("markread", "markunread", "flag", "move", "delete"):
            # MailHog is a development sink: it has no flags or folders.
            print(json.dumps({"ok": True}))
            return 0
        if cmd == "source":
            print(json.dumps(mh_source(url, args[0]), ensure_ascii=False))
            return 0
        if cmd in ("save", "saveattachment"):
            if len(args) < 3:
                print(json.dumps({"error": "saveattachment needs uid, index and path"}))
                return 2
            print(
                json.dumps(
                    save_attachment(c, args[0], args[1], args[2]), ensure_ascii=False
                )
            )
            return 0
        if cmd == "setremote":
            print(json.dumps(cmd_setremote(args[0] == "1" if args else False)))
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
                        args[3] if len(args) > 3 else "",
                        args[4] if len(args) > 4 else "",
                    )
                )
            )
            return 0
        print(json.dumps({"error": "unknown command: " + cmd}))
        return 2

    if cmd == "state":
        print(
            json.dumps(
                {
                    "kind": "imap",
                    "account": c.get("account") or {},
                    "remoteImages": bool(c.get("remoteImages")),
                }
            )
        )
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
        print(
            json.dumps(
                imap_read(c, args[0], args[1] if len(args) > 1 else "INBOX"),
                ensure_ascii=False,
            )
        )
        return 0
    if cmd == "search":
        print(
            json.dumps(
                imap_search(c, args[0], args[1] if len(args) > 1 else "INBOX"),
                ensure_ascii=False,
            )
        )
        return 0
    if cmd == "markread":
        print(
            json.dumps(
                imap_flag(
                    c, args[0], "\\Seen", True, args[1] if len(args) > 1 else "INBOX"
                )
            )
        )
        return 0
    if cmd == "markunread":
        print(
            json.dumps(
                imap_flag(
                    c, args[0], "\\Seen", False, args[1] if len(args) > 1 else "INBOX"
                )
            )
        )
        return 0
    if cmd == "flag":
        if len(args) < 3:
            print(json.dumps({"error": "flag needs uid, flag and on/off"}))
            return 2
        print(
            json.dumps(
                imap_flag(
                    c,
                    args[0],
                    args[1],
                    args[2] == "1",
                    args[3] if len(args) > 3 else "INBOX",
                )
            )
        )
        return 0
    if cmd == "move":
        if len(args) < 2:
            print(json.dumps({"error": "move needs a uid and a folder"}))
            return 2
        print(
            json.dumps(
                imap_move(c, args[0], args[1], args[2] if len(args) > 2 else "INBOX")
            )
        )
        return 0
    if cmd == "source":
        print(
            json.dumps(
                imap_source(c, args[0], args[1] if len(args) > 1 else "INBOX"),
                ensure_ascii=False,
            )
        )
        return 0
    if cmd in ("save", "saveattachment"):
        if len(args) < 3:
            print(json.dumps({"error": "saveattachment needs uid, index and path"}))
            return 2
        print(
            json.dumps(
                save_attachment(
                    c, args[0], args[1], args[2], args[3] if len(args) > 3 else "INBOX"
                ),
                ensure_ascii=False,
            )
        )
        return 0
    if cmd == "setremote":
        print(json.dumps(cmd_setremote(args[0] == "1" if args else False)))
        return 0
    if cmd == "delete":
        print(
            json.dumps(imap_delete(c, args[0], args[1] if len(args) > 1 else "INBOX"))
        )
        return 0
    if cmd == "send":
        if len(args) < 3:
            print(json.dumps({"error": "send needs to, subject and body"}))
            return 2
        print(
            json.dumps(
                send(
                    c,
                    args[0],
                    args[1],
                    args[2],
                    args[3] if len(args) > 3 else "",
                    args[4] if len(args) > 4 else "",
                )
            )
        )
        return 0
    print(json.dumps({"error": "unknown command: " + cmd}))
    return 2


if __name__ == "__main__":
    sys.exit(main())
