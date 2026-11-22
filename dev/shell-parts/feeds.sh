# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=feeds)
# ---- the feed reader's subscription list: OPML out and in, and refreshing on
#      its own. The bridge is a real python program over a real file
#      (dev/fake-feed.py serves two feeds on 127.0.0.1:8731), so an import that
#      adds a feed really fetches it, and the exported document really names it.
CONF=/root/.config/shani-shell/feeds.json
CACHE=/root/.cache/shani-shell/feeds.json
TOOL=${SHANI_FEEDS_TOOL:-/work/bridge/feeds.py}

python3 /work/dev/fake-feed.py 8731 >/dev/null 2>&1 &
FAKE_PID=$!
trap 'kill $FAKE_PID 2>/dev/null' EXIT
sleep 0.8

rm -f "$CONF" "$CACHE" /tmp/opml-test.opml /tmp/opml-foreign.opml
# start from one known feed, titled by the feed itself
python3 "$TOOL" add http://127.0.0.1:8731/rss >/dev/null 2>&1 || true
ipc feedsOpen; sleep 1.5

# ---- OPML out -------------------------------------------------------------
ipc feedsExport /tmp/opml-test.opml
i=0; until [ -s /tmp/opml-test.opml ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
if python3 - "$TOOL" /tmp/opml-test.opml <<'PY'
import sys, urllib.request, xml.etree.ElementTree as ET
doc = ET.parse(sys.argv[2]).getroot()
if doc.tag != "opml" or doc.get("version") != "2.0":
    sys.exit(1)
urls = [o.get("xmlUrl") for o in doc.iter() if o.tag.split("}")[-1] == "outline" and o.get("xmlUrl")]
if "http://127.0.0.1:8731/rss" not in urls:
    sys.exit(1)
# the title comes from the feed, not the address - the list read it
texts = [o.get("text") or "" for o in doc.iter() if o.tag.split("}")[-1] == "outline"]
if not any("Example" in t or "example" in t.lower() for t in texts):
    sys.exit(1)
PY
then result feeds-opml-exported PASS; else result feeds-opml-exported FAIL "$(head -c 200 /tmp/opml-test.opml 2>&1 | tr '\n' ';')"; fi

# ---- OPML in: another reader's file, nested, with one feed already here -----
cat > /tmp/opml-foreign.opml <<'OPML'
<?xml version="1.0" encoding="utf-8"?>
<opml version="1.1">
  <head><title>Someone else's subscriptions</title></head>
  <body>
    <outline text="News">
      <outline type="rss" text="Second" xmlUrl="http://127.0.0.1:8731/atom"/>
    </outline>
    <outline type="rss" text="Already here" xmlUrl="http://127.0.0.1:8731/rss"/>
  </body>
</opml>
OPML
ipc feedsImport /tmp/opml-foreign.opml
i=0
until [ "$(python3 -c 'import json,sys; print(len(json.load(open("/root/.config/shani-shell/feeds.json"))["feeds"]))' 2>/dev/null)" = 2 ] || [ $i -ge 24 ]; do sleep 0.25; i=$((i+1)); done
n=$(python3 -c 'import json; print(len(json.load(open("/root/.config/shani-shell/feeds.json"))["feeds"]))' 2>/dev/null)
[ "$n" = 2 ] && result feeds-opml-imported PASS "$(python3 -c 'import json; print(",".join(f["url"] for f in json.load(open("/root/.config/shani-shell/feeds.json"))["feeds"]))')" \
    || result feeds-opml-imported FAIL "$n feeds"

# ---- the exported list goes back in without doubling ----------------------
ipc feedsImport /tmp/opml-test.opml
i=0
until [ "$(python3 -c 'import json; print(len(json.load(open("/root/.config/shani-shell/feeds.json"))["feeds"]))' 2>/dev/null)" = 2 ] || [ $i -ge 16 ]; do sleep 0.25; i=$((i+1)); done
n=$(python3 -c 'import json; print(len(json.load(open("/root/.config/shani-shell/feeds.json"))["feeds"]))' 2>/dev/null)
[ "$n" = 2 ] && result feeds-opml-import-is-idempotent PASS || result feeds-opml-import-is-idempotent FAIL "$n feeds"

# ---- refreshing on its own -------------------------------------------------
ipc feedsInterval 30
i=0; until [ "$(python3 -c 'import json; print(json.load(open("/root/.config/shani-shell/feeds.json")).get("interval"))' 2>/dev/null)" = 30 ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
[ "$(python3 -c 'import json; print(json.load(open("/root/.config/shani-shell/feeds.json")).get("interval"))' 2>/dev/null)" = 30 ] \
    && result feeds-refresh-interval-set PASS || result feeds-refresh-interval-set FAIL "$(python3 -c 'import json; print(json.load(open("/root/.config/shani-shell/feeds.json")).get("interval"))' 2>/dev/null)"

# a feed fetched a moment ago is not due; one never fetched is
python3 - "$CACHE" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
p = sys.argv[1]
c = json.load(open(p))
for url, e in c.get("feeds", {}).items():
    e["fetched"] = datetime.now(timezone.utc).isoformat()
json.dump(c, open(p, "w"))
PY
due_now=$(python3 "$TOOL" due | python3 -c 'import json,sys; print(json.load(sys.stdin)["refreshed"])')
[ "$due_now" = 0 ] && result feeds-not-due-is-skipped PASS || result feeds-not-due-is-skipped FAIL "$due_now refreshed"

python3 - "$CACHE" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
p = sys.argv[1]
c = json.load(open(p))
old = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()
for e in c.get("feeds", {}).values():
    e["fetched"] = old
json.dump(c, open(p, "w"))
PY
due_old=$(python3 "$TOOL" due | python3 -c 'import json,sys; print(json.load(sys.stdin)["refreshed"])')
[ "$due_old" = 2 ] && result feeds-stale-is-refreshed PASS || result feeds-stale-is-refreshed FAIL "$due_old refreshed"

ipc feedsInterval 0
ipc closeAll
rm -f "$CONF" "$CACHE" /tmp/opml-test.opml /tmp/opml-foreign.opml