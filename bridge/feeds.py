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

Read state is kept per feed+id in the cache, so "unread" survives a restart
and a refresh does not bring an article back as unread.
"""

import html
import json
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
CONF = HOME / ".config/shani-shell/feeds.json"
CACHE = HOME / ".cache/shani-shell/feeds.json"
UA = "shani-shell/1.0 (feed reader)"
TIMEOUT = 12

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
        items.append(
            {
                "id": ident or link,
                "title": strip_html(find_text(it, "title")) or "(untitled)",
                "link": link,
                "date": published,
                "summary": strip_html(summary)[:400],
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
    }
    return {"title": c["feeds"][url]["title"], "url": url, "items": len(merged)}


def unread_count(c, url):
    read = c.get("read", {})
    return sum(
        1
        for i in c["feeds"].get(url, {}).get("items", [])
        if (url + "|" + i["id"]) not in read
    )


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
            }
        )
    return out


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
        for i in c["feeds"].get(url, {}).get("items", []):
            j = dict(i)
            j["read"] = (url + "|" + i["id"]) in read
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
    else:
        print(json.dumps({"error": "unknown command: " + cmd}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
