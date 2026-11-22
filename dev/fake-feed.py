#!/usr/bin/env python3
"""Two feeds for the shell's reader to fetch: a small RSS 2.0 and a small Atom
document, served on 127.0.0.1 so a test needs no network and no proxy.

    python3 dev/fake-feed.py [port]

The title is "Example feed" (RSS) and "Example atom" (Atom), so a test can tell
that the reader really parsed the feed and did not just keep the address.
"""

import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RSS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Example feed</title>
    <link>http://127.0.0.1/</link>
    <description>A feed that is always there</description>
    <item>
      <title>First post</title>
      <link>http://127.0.0.1/first</link>
      <guid>first</guid>
      <pubDate>Mon, 02 Nov 2026 10:00:00 +0000</pubDate>
      <description>&lt;p&gt;Hello from the RSS feed.&lt;/p&gt;</description>
    </item>
    <item>
      <title>Second post</title>
      <link>http://127.0.0.1/second</link>
      <guid>second</guid>
      <pubDate>Tue, 03 Nov 2026 10:00:00 +0000</pubDate>
      <description>Two is still small.</description>
    </item>
  </channel>
</rss>
"""

ATOM = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Example atom</title>
  <id>urn:uuid:2e3b0a0e-0000-0000-0000-000000000001</id>
  <updated>2026-11-03T10:00:00Z</updated>
  <entry>
    <title>An atom entry</title>
    <id>urn:uuid:atom-1</id>
    <link href="http://127.0.0.1/atom-entry"/>
    <updated>2026-11-03T10:00:00Z</updated>
    <summary>Atom, not RSS.</summary>
  </entry>
</feed>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/rss":
            body, kind = RSS, "application/rss+xml"
        elif path == "/atom":
            body, kind = ATOM, "application/atom+xml"
        else:
            self.send_error(404)
            return
        raw = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8731
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
