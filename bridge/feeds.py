#!/usr/bin/env python3
"""RSS and Atom feeds for the shell's reader.

A subscription list in ~/.config/shani-shell/feeds.json (OPML-shaped:
{"feeds": [{"title", "url"}]}), fetched with the standard library only —
urllib for the bytes, ElementTree for the XML — and cached in
~/.cache/shani-shell/feeds.json so opening the reader is instant and a feed
that is down does not block the others.

Commands, one JSON answer on stdout:

  list                  [{"title", "url", "items", "unread"}]
  items <url>           [{"id", "title", "link", "date", "summary", "read"}]
  article <url> <id>    {"title", "link", "date", "text"}
  add <url> [title]     {"ok": true}
  remove <url>          {"ok": true}
  refresh               {"ok": true, "feeds": N, "items": N}
  markread <url> <id>   {"ok": true}
  markunread <url> <id> {"ok": true}
  nextunread <url> [id] {"ok": true, "id": "...", "title": "..."} or {"ok": false}
  search <query>        [{url, feed, id, title, summary, date, read}]
  settags <url> <a,b>   {"ok": true, "tags": [...]}
  tags                  ["tech", "news", ...]
  save <url> <id>       {"ok": true, "saved": true|false, "id": "...", "url": "..."}
  saved                 [{url, id, title, feed, date, summary, read, enclosure}]
  discover <url>        [{href, type, title}]  feed links a site advertises

Read state is kept per feed+id in the cache, so "unread" survives a restart
and a refresh does not bring an article back as unread.

Two more things a reader needs: moving the subscription list in and out
(OPML 2.0, the format every other reader writes - `export` prints it, `import`
takes a file of it, ours or another reader's), and refreshing on its own
(`interval <minutes>` says how often, 0 turns it off; the shell asks `due` when
its timer fires and only the feeds older than that are fetched).
"""

import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
CONF = HOME / ".config/shani-shell/feeds.json"
CACHE = HOME / ".cache/shani-shell/feeds.json"
UA = "shani-shell/1.0 (feed reader)"
TIMEOUT = 12
DEFAULT_OPML_TITLE = "Feeds"

RSS = "{http://purl.org/rss/1.0/}"
ATOM = "{http://www.w3.org/2005/Atom}"
DC = "{http://purl.org/dc/elements/1.1/}"


def _load(path, default):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default


def _save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def subs():
    return _load(CONF, {"feeds": []}).get("feeds", [])


def conf():
    return _load(CONF, {"feeds": [], "interval": 0})


def interval():
    try:
        return max(0, int(conf().get("interval", 0) or 0))
    except Exception:
        return 0


def cache():
    return _load(CACHE, {"feeds": {}, "read": {}})


def save_cache(c):
    _save(CACHE, c)


def text_of(el):
    if el is None:
        return ""
    return re.sub(r"\s+", " ", "".join(el.itertext())).strip()


def find_text(el, name):
    """The title of an RSS item and of an Atom entry are in different
    namespaces; try the plain name, then Atom's, then RSS 1.0's."""
    if el is None:
        return ""
    for cand in (el.find(name), el.find(ATOM + name), el.find(RSS + name)):
        if cand is not None:
            return text_of(cand)
    return ""


def strip_html(s):
    """RSS descriptions are HTML; the reader shows text (no remote images)."""
    s = re.sub(r"<(script|style)\b.*?</\1>", " ", s or "", flags=re.S | re.I)
    s = re.sub(r"<[^>]+>", " ", s)
    return re.sub(r"\s+", " ", html.unescape(s)).strip()


def parse_date(s):
    if not s:
        return ""
    try:
        return parsedate_to_datetime(s).astimezone(timezone.utc).isoformat()
    except Exception:
        pass
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc).isoformat()
        except Exception:
            continue
    return ""


def fetch(url):
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
        },
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read()


def parse_feed(data, url):
    """RSS 2.0 / RSS 1.0 / Atom into a title and a list of items."""
    root = ET.fromstring(data)
    title = ""
    items = []

    channel = root.find("channel")
    if channel is None:
        channel = root
    title = find_text(channel, "title")

    for it in channel.iter():
        tag = it.tag.split("}")[-1]
        if tag != "item" and tag != "entry":
            continue
        link = ""
        for cand in it.findall("link") + it.findall(ATOM + "link"):
            rel = cand.get("rel") or "alternate"
            href = cand.get("href")
            if href and rel == "alternate":
                link = href
                break
            if not href and cand.text:
                link = cand.text.strip()
        if not link:
            guid = it.find("guid")
            link = text_of(guid) or url
        summary = ""
        for name in ("description", "summary", "encoded", "content"):
            el = it.find(name)
            if el is None:
                el = it.find(ATOM + name)
            if el is not None and el.text:
                summary = el.text
                break
        published = ""
        for name in ("pubDate", "published", "updated", "date"):
            el = it.find(name)
            if el is None:
                el = it.find(ATOM + name) or it.find(DC + "date")
            if el is not None and el.text:
                published = parse_date(el.text)
                if published:
                    break
        ident = ""
        for name in ("guid", "id"):
            el = it.find(name)
            if el is None:
                el = it.find(ATOM + name)
            if el is not None and el.text:
                ident = el.text.strip()
                break
        # RSS puts a podcast episode in <enclosure>; Atom in a rel=enclosure
        # link. Keep it with the item so the reader can offer the audio file.
        enclosure = {}
        for el in it.iter():
            tag = el.tag.split("}")[-1]
            if tag == "enclosure":
                enc_url = el.get("url") or ""
                enc_type = el.get("type") or ""
                enc_len = el.get("length") or ""
            elif tag == "link" and (el.get("rel") or "") == "enclosure":
                enc_url = el.get("href") or ""
                enc_type = el.get("type") or ""
                enc_len = el.get("length") or ""
            else:
                continue
            if enc_url:
                enclosure = {"url": enc_url, "type": enc_type, "length": enc_len}
                break
        items.append(
            {
                "id": ident or link,
                "title": strip_html(find_text(it, "title")) or "(untitled)",
                "link": link,
                "date": published,
                "summary": strip_html(summary)[:400],
                "enclosure": enclosure,
            }
        )
    return title, items


def refresh_one(feed, c):
    url = feed["url"]
    try:
        title, items = parse_feed(fetch(url), url)
    except Exception as exc:  # a dead feed must not stop the rest
        old = c["feeds"].get(url)
        return {
            "title": feed.get("title") or url,
            "url": url,
            "items": len(old["items"]) if old else 0,
            "error": str(exc)[:120],
        }
    if title and not feed.get("title"):
        feed["title"] = title
    old = c["feeds"].get(url) or {"items": []}
    seen = {i["id"] for i in old["items"]}
    fresh = [i for i in items if i["id"] not in seen]
    merged = fresh + [i for i in old["items"] if i["id"] in {x["id"] for x in items}]
    merged.sort(key=lambda i: i.get("date") or "", reverse=True)
    c["feeds"][url] = {
        "title": feed.get("title") or title or url,
        "items": merged[:200],
        # when this feed last answered, so "refresh every hour" only fetches
        # what is due and the shell needs no timer per feed
        "fetched": datetime.now(timezone.utc).isoformat(),
    }
    return {"title": c["feeds"][url]["title"], "url": url, "items": len(merged)}


def unread_count(c, url):
    read = c.get("read", {})
    return sum(
        1
        for i in c["feeds"].get(url, {}).get("items", [])
        if (url + "|" + i["id"]) not in read
    )


def _tags(feed):
    """Tags are stored on the subscription, as a list or a comma string."""
    value = feed.get("tags") or []
    if isinstance(value, str):
        value = [t.strip() for t in value.split(",") if t.strip()]
    return value


def cmd_list():
    c = cache()
    out = []
    for f in subs():
        e = c["feeds"].get(f["url"]) or {"items": []}
        out.append(
            {
                "title": e.get("title") or f.get("title") or f["url"],
                "url": f["url"],
                "items": len(e.get("items", [])),
                "unread": unread_count(c, f["url"]),
                "tags": _tags(f),
            }
        )
    return out


def cmd_next_unread(c, url, current=""):
    """The next unread article after `current`, wrapping round the feed."""
    items = c["feeds"].get(url, {}).get("items", [])
    read = c.get("read", {})
    if not items:
        return {"ok": False}
    start = 0
    for idx, i in enumerate(items):
        if i["id"] == current:
            start = idx + 1
            break
    for k in range(len(items)):
        i = items[(start + k) % len(items)]
        if i["id"] == current:  # never land back on the article we are in
            continue
        if (url + "|" + i["id"]) not in read:
            return {"ok": True, "id": i["id"], "title": i.get("title", "")}
    return {"ok": False}


def cmd_search(c, query):
    """One flat result list from every cached feed, best match first.

    A title hit outranks one buried in the summary or body; a hit in the feed's
    name is a weaker signal. Equal scores fall back to newest first.
    """
    q = (query or "").strip().lower()
    if not q:
        return []
    known = {f["url"]: f for f in subs()}
    read = c.get("read", {})
    out = []
    for url, e in c.get("feeds", {}).items():
        feed = known.get(url, {})
        title = e.get("title") or feed.get("title") or url
        for i in e.get("items", []):
            title_hit = q in i.get("title", "").lower()
            feed_hit = q in title.lower()
            hay = " ".join(
                (i.get("title", ""), i.get("summary", ""), i.get("text", ""))
            ).lower()
            if not (title_hit or feed_hit or q in hay):
                continue
            score = (3 if title_hit else 0) + (1 if feed_hit else 0)
            row = dict(i)
            row.update(
                {
                    "url": url,
                    "feed": title,
                    "read": (url + "|" + i["id"]) in read,
                }
            )
            out.append((score, row))
    out.sort(key=lambda pair: (pair[0], pair[1].get("date") or ""), reverse=True)
    return [row for _, row in out]


def cmd_settags(url, raw):
    tags = [t.strip() for t in re.split(r"[,;]+", raw or "") if t.strip()]
    feeds = subs()
    for f in feeds:
        if f["url"] == url:
            f["tags"] = tags
            break
    else:
        return {"ok": False, "error": "no such feed"}
    d = conf()
    d["feeds"] = feeds
    _save(CONF, d)
    return {"ok": True, "tags": tags}


def cmd_taglist():
    return sorted({t for f in subs() for t in _tags(f)})


def _attr(tag, name):
    m = re.search(
        r"\b%s\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))" % re.escape(name),
        tag,
        re.I,
    )
    return (m.group(1) or m.group(2) or m.group(3) or "") if m else ""


def discover(url, data=None):
    """The feed links a site advertises, made absolute against that site."""
    if data is None:
        data = fetch(url)
    markup = data.decode("utf-8", "replace") if isinstance(data, bytes) else str(data)
    out, seen = [], set()
    for m in re.finditer(r"<link\b[^>]*>", markup, re.I):
        tag = m.group(0)
        href = _attr(tag, "href")
        typ = _attr(tag, "type").lower()
        rel = _attr(tag, "rel").lower()
        if not href:
            continue
        if not (
            "rss" in typ
            or "atom" in typ
            or "xml" in typ
            or "feed" in rel
            or "alternate" in rel
        ):
            continue
        full = urllib.parse.urljoin(url, href)
        if full in seen:
            continue
        seen.add(full)
        out.append({"href": full, "type": typ, "title": _attr(tag, "title")})
    return out


def resolve_feed(url, title=""):
    """A site URL becomes the feed it advertises; a feed URL stays as it is."""
    try:
        data = fetch(url)
    except Exception:
        return url, title
    try:
        _, items = parse_feed(data, url)
        if items:
            return url, title
    except Exception:
        pass
    try:
        found = discover(url, data)
    except Exception:
        found = []
    if found:
        return found[0]["href"], title or found[0].get("title", "")
    return url, title


def cmd_save(c, url, ident):
    key = url + "|" + ident
    saved = c.setdefault("saved", {})
    on = not bool(saved.get(key))
    if on:
        saved[key] = True
    else:
        saved.pop(key, None)
    save_cache(c)
    return {"ok": True, "saved": on, "id": ident, "url": url}


def cmd_saved(c):
    read = c.get("read", {})
    kept = c.get("saved", {})
    out = []
    for url, e in c.get("feeds", {}).items():
        for i in e.get("items", []):
            if not kept.get(url + "|" + i["id"]):
                continue
            row = dict(i)
            row.update(
                {
                    "url": url,
                    "feed": e.get("title") or url,
                    "read": (url + "|" + i["id"]) in read,
                }
            )
            out.append(row)
    out.sort(key=lambda r: r.get("date") or "", reverse=True)
    return out


# ---- OPML 2.0: the subscription list in and out ---------------------------
def opml_export():
    """The feeds as an OPML 2.0 document - what every other reader reads.

    Each feed is one <outline> with the text the spec requires (the title) and
    xmlUrl (the feed). A reader that groups feeds writes nested outlines; ours
    is flat, which every reader accepts.
    """
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<opml version="2.0">',
        "  <head>",
        "    <title>%s</title>" % html.escape(DEFAULT_OPML_TITLE),
        "  </head>",
        "  <body>",
    ]
    for f in subs():
        e = cache()["feeds"].get(f["url"]) or {}
        title = e.get("title") or f.get("title") or f["url"]
        lines.append(
            '    <outline type="rss" text="%s" title="%s" xmlUrl="%s"/>'
            % (
                html.escape(title, quote=True),
                html.escape(title, quote=True),
                html.escape(f["url"], quote=True),
            )
        )
    lines += ["  </body>", "</opml>", ""]
    return "\n".join(lines)


def opml_urls(path):
    """Every xmlUrl in an OPML file, in document order.

    Also accepts our own feeds.json, so a copy of the old list can go back in.
    """
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
    if raw.lstrip().startswith("{"):
        try:
            return [f["url"] for f in json.loads(raw).get("feeds", []) if f.get("url")]
        except Exception:
            return []
    root = ET.fromstring(raw)
    found = []
    for el in root.iter():
        if el.tag.split("}")[-1] != "outline":
            continue
        url = (el.get("xmlUrl") or "").strip()
        if url and url not in found:
            found.append(url)
    return found


def cmd_import(path):
    urls = opml_urls(path)
    have = {f["url"] for f in subs()}
    feeds = subs()
    added = 0
    c = cache()
    for url in urls:
        if url in have:
            continue
        feeds.append({"title": "", "url": url})
        have.add(url)
        added += 1
        refresh_one({"title": "", "url": url}, c)
    _save(CONF, {"feeds": feeds, "interval": interval()})
    save_cache(c)
    return {"added": added, "known": len(urls) - added, "feeds": len(feeds)}


# ---- refreshing on its own -------------------------------------------------
def _older_than(iso, minutes):
    if not iso:
        return True
    try:
        seen = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except Exception:
        return True
    if seen.tzinfo is None:
        seen = seen.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) - seen >= timedelta(minutes=minutes)


def cmd_due():
    """Refresh the feeds whose last answer is older than the interval.

    Called by the shell's timer, not on a schedule of its own: nothing wakes up
    unless the reader is open and the interval is set.
    """
    minutes = interval()
    if minutes <= 0:
        return {"refreshed": 0, "interval": 0}
    c = cache()
    n = 0
    for f in subs():
        e = c["feeds"].get(f["url"]) or {}
        if _older_than(e.get("fetched"), minutes):
            refresh_one(f, c)
            n += 1
    if n:
        save_cache(c)
    return {"refreshed": n, "interval": minutes}


def cmd_status():
    c = cache()
    stamps = [e.get("fetched") for e in c["feeds"].values() if e.get("fetched")]
    stamps.sort()
    return {
        "interval": interval(),
        "last": stamps[-1] if stamps else "",
        "feeds": len(subs()),
    }


def cmd_interval(minutes):
    try:
        n = max(0, min(7 * 24 * 60, int(minutes)))
    except Exception:
        return {"error": "interval must be whole minutes"}
    d = conf()
    d["feeds"] = subs()
    d["interval"] = n
    _save(CONF, d)
    return {"interval": n}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: feeds.py <command> [args]"}))
        return 2
    cmd = sys.argv[1]
    c = cache()

    if cmd == "list":
        print(json.dumps(cmd_list(), ensure_ascii=False))
    elif cmd == "items":
        url = sys.argv[2]
        read = c.get("read", {})
        items = []
        saved = c.get("saved", {})
        for i in c["feeds"].get(url, {}).get("items", []):
            j = dict(i)
            j["read"] = (url + "|" + i["id"]) in read
            j["saved"] = (url + "|" + i["id"]) in saved
            items.append(j)
        print(json.dumps(items, ensure_ascii=False))
    elif cmd == "article":
        url, ident = sys.argv[2], sys.argv[3]
        for i in c["feeds"].get(url, {}).get("items", []):
            if i["id"] == ident:
                print(
                    json.dumps(
                        {
                            "title": i["title"],
                            "link": i["link"],
                            "date": i["date"],
                            "text": i.get("summary", ""),
                            "saved": (url + "|" + i["id"]) in c.get("saved", {}),
                            "enclosure": i.get("enclosure", {}),
                        },
                        ensure_ascii=False,
                    )
                )
                return 0
        print(json.dumps({"error": "no such article"}))
        return 1
    elif cmd == "add":
        url = sys.argv[2].strip()
        title = sys.argv[3] if len(sys.argv) > 3 else ""
        # a site address becomes the feed it advertises (RSS/Atom discovery)
        url, title = resolve_feed(url, title)
        feeds = subs()
        if not any(f["url"] == url for f in feeds):
            feeds.append({"title": title, "url": url})
            _save(CONF, {"feeds": feeds})
        refresh_one({"title": title, "url": url}, c)
        save_cache(c)
        print(
            json.dumps(
                {
                    "ok": True,
                    "feed": {
                        "title": title or url,
                        "url": url,
                        "items": len(c["feeds"].get(url, {}).get("items", [])),
                    },
                }
            )
        )
    elif cmd == "remove":
        url = sys.argv[2]
        _save(CONF, {"feeds": [f for f in subs() if f["url"] != url]})
        c["feeds"].pop(url, None)
        save_cache(c)
        print(json.dumps({"ok": True}))
    elif cmd == "refresh":
        n = 0
        for f in subs():
            refresh_one(f, c)
            n += 1
        save_cache(c)
        print(json.dumps({"ok": True, "feeds": n}))
    elif cmd == "markread":
        url, ident = sys.argv[2], sys.argv[3]
        c.setdefault("read", {})[url + "|" + ident] = True
        save_cache(c)
        print(json.dumps({"ok": True}))
    elif cmd == "markunread":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "markunread needs a feed and an id"}))
            return 2
        url, ident = sys.argv[2], sys.argv[3]
        c.get("read", {}).pop(url + "|" + ident, None)
        save_cache(c)
        print(json.dumps({"ok": True, "id": ident, "url": url}))
    elif cmd == "nextunread":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "nextunread needs a feed"}))
            return 2
        print(
            json.dumps(
                cmd_next_unread(
                    c, sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
                )
            )
        )
    elif cmd == "search":
        print(
            json.dumps(
                cmd_search(c, sys.argv[2] if len(sys.argv) > 2 else ""),
                ensure_ascii=False,
            )
        )
    elif cmd == "settags":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "settags needs a feed and tags"}))
            return 2
        print(json.dumps(cmd_settags(sys.argv[2], sys.argv[3])))
    elif cmd == "tags":
        print(json.dumps(cmd_taglist(), ensure_ascii=False))
    elif cmd == "save":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "save needs a feed and an id"}))
            return 2
        print(json.dumps(cmd_save(c, sys.argv[2], sys.argv[3])))
    elif cmd == "saved":
        print(json.dumps(cmd_saved(c), ensure_ascii=False))
    elif cmd == "discover":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "discover needs an address"}))
            return 2
        try:
            print(json.dumps(discover(sys.argv[2]), ensure_ascii=False))
        except Exception as exc:
            print(json.dumps({"error": str(exc)[:120]}))
    elif cmd == "markall":
        # Mark every cached article read; with a url, only that feed's items.
        url = sys.argv[2] if len(sys.argv) > 2 else ""
        read = c.setdefault("read", {})
        feeds = [url] if url else list(c.get("feeds", {}))
        n = 0
        for f in feeds:
            for i in c["feeds"].get(f, {}).get("items", []):
                key = f + "|" + i["id"]
                if not read.get(key):
                    n += 1
                read[key] = True
        save_cache(c)
        print(json.dumps({"ok": True, "marked": n}))
    elif cmd == "export":
        sys.stdout.write(opml_export())
    elif cmd == "import":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "import needs a file"}))
            return 2
        print(json.dumps(cmd_import(sys.argv[2])))
    elif cmd == "interval":
        print(json.dumps(cmd_interval(sys.argv[2] if len(sys.argv) > 2 else 0)))
    elif cmd == "due":
        print(json.dumps(cmd_due()))
    elif cmd == "status":
        print(json.dumps(cmd_status()))
    else:
        print(json.dumps({"error": "unknown command: " + cmd}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
