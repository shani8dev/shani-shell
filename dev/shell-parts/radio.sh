# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=radio)
# ---- Media Player > Radio (Shortwave parity) against a stand-in radio-browser.info
#      (dev/fake-radio.py): popular, near you, a genre, a search; a station plays
#      (its stream heard as playing), is counted with the directory, kept as a favourite ----
rm -f /tmp/fake-radio-counted
ipc radioShow popular
waitfor "d['radioStations'] == ['Akashvani Pune', 'Bollywood Hits', 'Night Jazz']" 10 && result radio-popular PASS || result radio-popular FAIL "$(q "['radioStations'], d['radioShowing']")"
shot radio 0.3
ipc radioShow "genre:jazz"
waitfor "d['radioStations'] == ['Night Jazz']" 8 && result radio-genre PASS || result radio-genre FAIL "$(q "['radioStations']")"
ipc radioShow "search:bolly"
waitfor "d['radioStations'] == ['Bollywood Hits']" 8 && result radio-search PASS || result radio-search FAIL "$(q "['radioStations']")"
ipc radioPlay "Bollywood Hits"
waitfor "d['mediaPlayerPlaying'] and d['mediaName'] == 'Bollywood Hits'" 15 && result radio-plays PASS || result radio-plays FAIL "$(q "['mediaPlayerPlaying'], d['mediaName'], d['mediaFile']")"
for i in $(seq 1 20); do grep -q u-bolly /tmp/fake-radio-counted 2>/dev/null && break; sleep 0.25; done
grep -q u-bolly /tmp/fake-radio-counted 2>/dev/null && result radio-play-counted PASS || result radio-play-counted FAIL "$(cat /tmp/fake-radio-counted 2>&1)"
ipc radioFavourite "Bollywood Hits"; ipc radioShow favourites
waitfor "d['radioFavourites'] == ['Bollywood Hits'] and d['radioStations'] == ['Bollywood Hits']" 6 && result radio-favourite PASS || result radio-favourite FAIL "$(q "['radioFavourites'], d['radioStations']")"
ipc radioFavourite "Bollywood Hits"

# ---- FM radio: one home, Media Player > Radio > FM --------------------------
# The tuner is dev/fake-fm.py (dev/session.sh points SHANI_FM at it). Its state
# file and call log are the evidence: a click must reach the stand-in, not just
# repaint a label. A11Y names come from Common controls (KeyFocus + Accessible).
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
FM=/work/dev/fake-fm.py
FM_LOG=${SHANI_FM_LOG:-/tmp/fake-fm-calls}
TREE=/tmp/radio-fm-tree.txt
press() {
    for label in "$@"; do
        timeout 12 python3 "$A11Y" press "$label" >/dev/null 2>&1 && return 0
    done
    return 1
}
audit() { qs -p /work/shani ipc call shani navAuditAll 2>/dev/null; }
# a fresh, stopped tuner (keep the log: the view asks for state when built)
SHANI_FM="$FM" python3 /work/bridge/devices.py fm stop >/dev/null 2>&1
audit > /tmp/radio-fm-audit-base.json

# the Devices gadgets link reaches the same Radio page; one home for FM
ipc devicesOpen; sleep 0.5
press "radio button:^Gadgets$"
press "button:^Open FM radio$" \
    && result radio-fm-devices-link PASS || result radio-fm-devices-link FAIL "no Open FM radio link"
waitfor "d['mediaPage'] == 'radio'" 8 \
    && result radio-fm-devices-link-opens PASS || result radio-fm-devices-link-opens FAIL "$(q "['mediaPage']")"
ipc devicesClose; sleep 0.3

ipc radioShow popular
waitfor "d['mediaPage'] == 'radio'" 5 || echo "  (radio page not up: $(q "['mediaPage']") )"
press "radio button:^FM radio$" \
    && result radio-fm-source PASS \
    || result radio-fm-source FAIL "Media Player has no FM source chip"
sleep 0.6
if timeout 12 python3 "$A11Y" find "text field:^Find a station$" >/dev/null 2>&1; then
    result radio-fm-internet-hidden FAIL "the station search stayed on the FM page"
else
    result radio-fm-internet-hidden PASS
fi
timeout 12 python3 "$A11Y" find "Frequency" >/dev/null 2>&1 \
    && result radio-fm-controls-drawn PASS || result radio-fm-controls-drawn FAIL "no frequency field on the FM page"
grep -q '^state$' "$FM_LOG" 2>/dev/null \
    && result radio-fm-state-asked PASS || result radio-fm-state-asked FAIL "$(cat "$FM_LOG" 2>&1)"
shot radio-fm-idle 0.5

# a preset is one click (and one KeyFocus press) to the tuner
press "radio button:^98.3 MHz$" \
    && result radio-fm-preset-clickable PASS || result radio-fm-preset-clickable FAIL "no 98.3 MHz preset"
i=0; until grep -q '^tune 98.3$' "$FM_LOG" 2>/dev/null || [ $i -ge 16 ]; do sleep 0.25; i=$((i+1)); done
grep -q '^tune 98.3$' "$FM_LOG" 2>/dev/null \
    && result radio-fm-preset-tunes PASS || result radio-fm-preset-tunes FAIL "$(tail -4 "$FM_LOG" 2>&1)"

# a custom frequency is typed into the field and started
press "text field:^For example 91.1$" "text field:^Frequency in MHz$"
wtype "98.5"
press "button:^Start$"
waitfor "d['fmState'] in ('running', 'on') and abs(d['fmFrequency'] - 98.5) < 0.01" 10 \
    && result radio-fm-state PASS \
    || result radio-fm-state FAIL "$(q "['fmState'], d['fmFrequency']")"
grep -q '^start 98.5$' "$FM_LOG" 2>/dev/null \
    && result radio-fm-start-reaches-tuner PASS || result radio-fm-start-reaches-tuner FAIL "$(cat "$FM_LOG" 2>&1)"
shot radio-fm-playing 0.4
shot radio-fm 0.4

# every clickable in the Media Player has a keyboard path (Ui.navAuditAll)
audit > /tmp/radio-fm-audit-now.json
new=$(python3 - <<'PY' 2>/dev/null || echo '[]'
import json
base = json.load(open('/tmp/radio-fm-audit-base.json')) or []
now = json.load(open('/tmp/radio-fm-audit-now.json')) or []
print(json.dumps([x for x in now if x not in base]))
PY
)
n=$(printf '%s' "$new" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo -1)
[ "$n" = 0 ] && result radio-fm-keyboard-reach PASS \
    || result radio-fm-keyboard-reach FAIL "$n reached only by a click: $new"

# controls must not overlap: read the on-screen boxes out of the A11Y tree and
# compare every pair of named controls. A box wholly inside another is a child
# control (a field's TextInput inside its well), not an overlap.
timeout 20 python3 "$A11Y" tree --max-depth 16 > "$TREE" 2>/dev/null || true
python3 - "$TREE" > /tmp/radio-fm-boxes.txt <<'PY'
import re, sys
ROLES = {"button", "radio button", "check box", "toggle button", "text",
         "entry", "password text", "combo box", "list item", "tree item"}
boxes = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.search(r"\]\s+([a-z][a-z ]+)\s+'([^']*)'.*@(-?\d+),(-?\d+) (\d+)x(\d+)", line)
    if not m:
        continue
    role, name, x, y, w, h = m.group(1), m.group(2), *map(int, m.groups()[2:])
    if role not in ROLES or not name or w <= 0 or h <= 0 or y < 0 or w > 2000:
        continue
    a = (x, y, x + w, y + h)
    if any(a[0] >= b[0] and a[1] >= b[1] and a[2] <= b[2] and a[3] <= b[3] or
           b[0] >= a[0] and b[1] >= a[1] and b[2] <= a[2] and b[3] <= a[3]
           for _, _, b in boxes):
        continue
    boxes.append((name, role, a))
print("  FM boxes:", "; ".join("%s %s (%d,%d %dx%d)" % (r, n, a[0], a[1], a[2]-a[0], a[3]-a[1]) for n, r, a in boxes))
bad = []
for i, (n1, r1, a) in enumerate(boxes):
    for n2, r2, b in boxes[i + 1:]:
        ow = min(a[2], b[2]) - max(a[0], b[0])
        oh = min(a[3], b[3]) - max(a[1], b[1])
        if ow > 0 and oh > 0:
            frac = ow * oh / min((a[2]-a[0])*(a[3]-a[1]), (b[2]-b[0])*(b[3]-b[1]))
            if frac > 0.2:
                bad.append((n1, n2, round(frac, 2)))
print("  overlapping:", bad or "none")
sys.exit(1 if bad else 0)
PY
box_rc=$?
cat /tmp/radio-fm-boxes.txt
[ "$box_rc" = 0 ] && result radio-fm-controls-no-overlap PASS \
    || result radio-fm-controls-no-overlap FAIL "$(grep overlapping /tmp/radio-fm-boxes.txt)"

press "button:^Stop$"
waitfor "d['fmState'] == 'off' or d['fmState'] == 'stopped'" 6 \
    && result radio-fm-stops PASS || result radio-fm-stops FAIL "$(q "['fmState']")"
ipc mediaClose; ipc closeAll
