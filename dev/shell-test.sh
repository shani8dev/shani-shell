#!/bin/sh
# usage: shell-test.sh   (inside shani-shell-dev, repo at /work)
#   run it with `sh dev/check.sh shell` (or idle / a11y) from the host
#   (SYS_PTRACE: the idle-cost check traces what the shell starts; SHELL_TEST_ONLY=idle runs just that)
# Every check drives the real thing — wpctl, notify-send, niri actions, wtype
# keystrokes, gdbus into the bridge, the settings file — then reads the shell's
# own answer (`ipc call shani state`). Prints RESULT lines; shots in out/shots.
. /work/dev/session.sh
SHOTS=/work/out/shots
mkdir -p "$SHOTS"     # not in git (a run's output): made here
fail=0
result() {
    echo "RESULT $1 $2${3:+ ($3)}"
    [ "$2" = PASS ] || fail=1
}
# a hung shell must fail the next check, not stall the run
st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }
q() { st | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)"; }
ipc() { qs -p /work/shani ipc call shani "$@" >/dev/null 2>&1; }
shot() { sleep "${2:-0.8}"; grim "$SHOTS/$1.png"; }
# the suite runs longer than the default idle lock (5 min) between keyboard
# inputs: no dimming, lock or screen-off unless a test sets them itself
settings() { python3 -c 'import json,sys; d={"dimAfter":0,"lockAfter":0,"screenOffAfter":0,"lockAfterBattery":0,"screenOffAfterBattery":0,"startHintsDone":True}; d.update(json.loads(sys.argv[1])); print(json.dumps(d), end="")' "$1" > "$SHANI_SHELL_SETTINGS"; sleep 1.5; }
waitfor() {   # waitfor <python expr over d> <seconds>
    i=0
    while [ $i -lt $(( $2 * 4 )) ]; do
        st | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)" 2>/dev/null && return 0
        sleep 0.25; i=$((i+1))
    done
    return 1
}

# ---- loads clean -------------------------------------------------------------
# (no system bus logind/polkit session in a container: those two warnings are expected)
bad=$(grep -E "TypeError|ReferenceError|Unable to assign|is not a function|is not defined|caused by|ERROR" /work/out/logs/qs.log \
      | grep -v -E "ZINK|libvulkan|polkit" | head -5)
[ -z "$bad" ] && result shell-loads-clean PASS || { result shell-loads-clean FAIL; echo "$bad"; }
# nothing below means anything if the shell is not running
if ! st >/dev/null 2>&1 || [ -z "$(st)" ]; then
    echo "the shell is not running — stopping here"; tail -20 /work/out/logs/qs.log; exit 1
fi
[ "$(q "['settingsLoaded']")" = True ] && result settings-loaded PASS || result settings-loaded FAIL

# ---- what the shell costs while nothing happens ---------------------------------------
# 30 s idle: the programs the shell starts (every poll that forks is a
# wakeup on a laptop), the shell's own CPU time, and its memory. The budget is
# the point: a new always-on poller shows up here as a FAIL, not as a battery
# complaint months later. Measured once nobody has touched it for 20 s+ (the
# Island stops blinking then): the first seconds are loading, not idling.
sleep 25
qpid=$(pgrep -o -x qs)
pid0=$(cut -d' ' -f5 /proc/loadavg); cpu0=$(awk '{print $14+$15}' /proc/$qpid/stat)
sleep 30
pid1=$(cut -d' ' -f5 /proc/loadavg); cpu1=$(awk '{print $14+$15}' /proc/$qpid/stat)
session=$(( (pid1 - pid0) * 2 )); cpu=$(( (cpu1 - cpu0) * 10 / 30 )); rss=$(awk '/VmRSS/{print int($2/1024)}' /proc/$qpid/status)
# then the shell's own: every program it starts in 30 s (strace on its execve
# calls - after the CPU count, since tracing slows what it watches)
timeout 30 strace -f -qq -e trace=execve -p "$qpid" 2>/tmp/idle-exec.txt
execs=$(grep -c 'execve(' /tmp/idle-exec.txt); forks=$(( execs * 2 ))
who=$(grep -o 'execve("[^"]*", \["[^"]*"\(, "[^"]*"\)\{0,2\}' /tmp/idle-exec.txt | sed 's/execve("[^"]*", \[//; s/"//g' \
      | sort | uniq -c | sort -rn | head -8 | tr '\n' ';')
idle="shell: $forks programs/min, CPU ${cpu} ms/s, ${rss} MB; whole session $session/min"
if grep -q "attach:\|Operation not permitted" /tmp/idle-exec.txt || ! command -v strace >/dev/null; then
    result idle-cost FAIL "could not trace the shell (run the container with --cap-add SYS_PTRACE): $(head -1 /tmp/idle-exec.txt)"
else
    [ "$forks" -le "${IDLE_FORK_BUDGET:-12}" ] && [ "$cpu" -le 15 ] && result idle-cost PASS "$idle" || result idle-cost FAIL "$idle"
fi
echo "  idle programs by command: $who"
# and the whole session's (one sampler, so it adds no programs of its own): a
# daemon stuck restarting shows here by name, and wakes the shell as it goes
python3 - <<'PY'
import os, time, collections
seen = set(os.listdir("/proc")); new = collections.Counter(); end = time.time() + 10
while time.time() < end:
    now = set(p for p in os.listdir("/proc") if p.isdigit())
    for p in now - seen:
        try: new[open(f"/proc/{p}/cmdline", "rb").read().replace(b"\0", b" ").decode()[:70] or open(f"/proc/{p}/comm").read().strip()] += 1
        except OSError: pass
    seen |= now; time.sleep(0.05)
print("  session programs in 10 s:", "; ".join(f"{n} {c}" for c, n in new.most_common(6)) or "none")
PY
# ---- perf: what the shell costs in time, memory and frames, each with a budget ----------
# The guard against slow decay: each number here was measured, and a change that
# pushes one past its budget fails by name. Budgets are for this container's
# software rendering (every buffer in the shell's own memory); a GPU costs less.
# frames: with nothing happening, nothing should redraw (a minute tick of the clock at most)
n0=$(wc -l < /work/out/logs/qs.log); sleep 15
frames=$(tail -n +"$n0" /work/out/logs/qs.log | grep -c "frame rendered")
wins=$(tail -n +"$n0" /work/out/logs/qs.log | grep "frame rendered" | grep -o "window 0x[0-9a-f]*" | sort -u | wc -l)
[ "$frames" -le "${IDLE_FRAME_BUDGET:-6}" ] && result perf-idle-frames PASS "$frames frames in 15 s, $wins windows" || result perf-idle-frames FAIL "$frames frames in 15 s from $wins windows (budget ${IDLE_FRAME_BUDGET:-6}): a surface redraws while nothing changes"
# memory at rest
rss0=$(awk '/VmRSS/{print int($2/1024)}' /proc/$qpid/status)
[ "$rss0" -le "${IDLE_RSS_BUDGET:-520}" ] && result perf-idle-memory PASS "$rss0 MB" || result perf-idle-memory FAIL "$rss0 MB (budget ${IDLE_RSS_BUDGET:-520} MB)"
# open speed: the surfaces people open most, from the command to the shell saying it is up
opened() { t0=$(date +%s%N); ipc "$@"; i=0; until [ "$(q "$WATCH")" = True ] || [ $i -ge 40 ]; do sleep 0.025; i=$((i+1)); done; echo $(( ($(date +%s%N) - t0) / 1000000 )); }
WATCH="['launcher']"; tl=$(opened launcher ""); ipc closeAll; sleep 0.5
WATCH="['controlCenter']"; ts=$(opened toggleControlCenter); ipc closeAll; sleep 0.5
worst=$(printf "%s\n%s\n" "$tl" "$ts" | sort -n | tail -1)
[ "$worst" -le "${OPEN_MS_BUDGET:-600}" ] && result perf-open-speed PASS "launcher ${tl} ms, sidebar ${ts} ms" || result perf-open-speed FAIL "launcher ${tl} ms, sidebar ${ts} ms (budget ${OPEN_MS_BUDGET:-600} ms)"
# leaks: open and close the big surfaces again and again; after the first round
# (caches filling) memory must settle, not climb
cycle() { ipc launcher ""; sleep 0.6; ipc closeAll; ipc toggleControlCenter; sleep 0.6; ipc closeAll; ipc layoutSwitcher; sleep 0.6; ipc closeAll; niri msg action toggle-overview; sleep 0.6; niri msg action toggle-overview; sleep 0.4; }
# One reading swings by ±30 MB here (software rendering's buffers come and go -
# measured: 600, 659, 624 MB in successive rounds, the same before and after a
# change), so the lowest of three is compared, early against late: a spike is
# not a leak, and a leak raises the floor.
rssnow() { awk '/VmRSS/{print int($2/1024)}' /proc/$qpid/status; }
floor3() { m=999999; for k in 1 2 3; do cycle; sleep 0.5; v=$(rssnow); [ "$v" -lt "$m" ] && m=$v; done; echo $m; }
cycle; rss1=$(floor3)
for i in 1 2 3 4; do cycle; done; rss2=$(floor3)
grow=$((rss2 - rss1))
[ "$grow" -le "${LEAK_MB_BUDGET:-24}" ] && result perf-no-leak PASS "${grow} MB, lowest of 3 early vs late over 11 rounds (${rss1} -> ${rss2} MB)" || result perf-no-leak FAIL "+$grow MB lowest-of-3 floor over 11 rounds of launcher/sidebar/layouts/overview (${rss1} -> ${rss2} MB, budget ${LEAK_MB_BUDGET:-24})"
# startup: a fresh shell, from launch to its first answer (and its frames' render cost)
kill "$qpid"; while kill -0 "$qpid" 2>/dev/null; do sleep 0.1; done
t0=$(date +%s%N)
QS_ICON_THEME=Adwaita QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true" qs -p /work/shani >>/work/out/logs/qs.log 2>&1 &
i=0; until st >/dev/null 2>&1 || [ $i -ge 300 ]; do sleep 0.05; i=$((i+1)); done
boot=$(( ($(date +%s%N) - t0) / 1000000 )); qpid=$(pgrep -o -x qs); sleep 2
[ "$boot" -le "${STARTUP_MS_BUDGET:-3500}" ] && result perf-startup PASS "$boot ms" || result perf-startup FAIL "$boot ms (budget ${STARTUP_MS_BUDGET:-3500} ms)"
echo "  render cost per frame (ms, last 60): $(grep -o 'render=[0-9]*' /work/out/logs/qs.log | tail -60 | sort | uniq -c | sort -rn | head -4 | tr '\n' ' ')"
# SHELL_TEST_ONLY=idle (or perf): just these, for working on what the shell costs
[ "${SHELL_TEST_ONLY:-}" = idle ] || [ "${SHELL_TEST_ONLY:-}" = perf ] && exit $fail

# the overview's backdrop wallpaper exists only while the overview is open (a
# backdrop surface the rest of the time is redrawn once a second, idle)
layers() { niri msg -j layers | python3 -c "import json,sys; print(sum(1 for l in json.load(sys.stdin) if l['namespace'] == 'shani-backdrop'))"; }
niri msg action open-overview; sleep 1; on=$(layers)
niri msg action close-overview; sleep 1.2; off=$(layers)
[ "$on" -ge 1 ] && [ "$off" = 0 ] && result overview-backdrop-only-while-open PASS || result overview-backdrop-only-while-open FAIL "open: $on, closed: $off"

# ---- accessibility: every control on each surface has a name -----------------------------
# shani-testbed's AT-SPI client (mounted at /testbed): what Orca would read. An
# unnamed control is announced as just "button". Each surface is opened and
# linted; the unnamed ones are listed.
A11Y=/testbed/lib/a11y_client.py
if [ -f "$A11Y" ] && python3 -c "import gi; gi.require_version('Atspi','2.0')" 2>/dev/null; then
    lint() {   # lint <name> : the surface already open
        sleep 1
        out=$(timeout 20 python3 "$A11Y" lint 2>&1); rc=$?
        n=$(printf '%s\n' "$out" | grep -c .)
        [ $rc = 0 ] && result "a11y-$1" PASS || result "a11y-$1" FAIL "$n unnamed: $(printf '%s' "$out" | head -6 | tr '\n' ';' | cut -c1-400)"
    }
    timeout 20 python3 "$A11Y" tree --max-depth 3 >/dev/null 2>&1 || echo "  (the shell is not on the accessibility bus: $(timeout 20 python3 "$A11Y" tree --max-depth 2 2>&1 | head -2))"
    lint bar
    ipc toggleControlCenter; lint control-centre
    # and it is drawn at all: the lint passes on an empty panel (the bar's
    # controls are named), so its tiles must be there - a section that hid
    # itself (QML's visible is the effective one) left the panel blank once
    shot 25b-control-centre 0.6
    t=$(timeout 20 python3 "$A11Y" find "Night light" 2>/dev/null | head -1); d=$(timeout 20 python3 "$A11Y" find "Do Not Disturb" 2>/dev/null | head -1)
    [ -n "$t" ] && [ -n "$d" ] && result control-centre-drawn PASS || result control-centre-drawn FAIL "Night light: ${t:-none}; Do Not Disturb: ${d:-none}"
    ipc closeAll
    ipc launcher ""; lint launcher; ipc closeAll
    for c in personal notifications network displays windows sound access input time apps search printers sharing backup automations privacy chronoa account users power about ; do ipc settingsCategory $c; lint "settings-$c"; [ "${SHELL_TEST_ONLY:-}" = a11y ] && shot "settings-$c" 0.2; done
    niri msg -j windows > /work/out/logs/windows-with-settings.json 2>/dev/null
    ipc closeAll
    ipc toggleChronoa; lint chronoa; ipc toggleChronoa; ipc closeAll
    waitfor "not d['chronoaOpen']" 3 || echo "  (Chronoa did not close)"
else
    result a11y-client SKIP "no /testbed/lib/a11y_client.py or Atspi typelib"
fi
[ "${SHELL_TEST_ONLY:-}" = a11y ] && exit $fail

# ---- niri event stream ---------------------------------------------------------
foot -a shani-demo -T "Terminal one" sleep 600 >/dev/null 2>&1 &
sleep 1
niri msg action focus-workspace 2
foot -a shani-demo -T "Terminal two" sleep 600 >/dev/null 2>&1 &
waitfor "d['windows'] >= 2 and d['focusedWorkspace'] == 2" 6 \
    && result niri-workspaces-and-windows PASS || result niri-workspaces-and-windows FAIL "$(st)"
waitfor "d['focusedTitle'] == 'Terminal two'" 4 \
    && result niri-focused-window PASS || result niri-focused-window FAIL "$(q "['focusedTitle']")"
niri msg action focus-workspace 1

# ---- audio + OSD ---------------------------------------------------------------
waitfor "d['audioReady']" 6 && result audio-ready PASS || result audio-ready FAIL
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.30
waitfor "d['volume'] == 30" 3 && result volume-follows-wpctl PASS || result volume-follows-wpctl FAIL "$(q "['volume']")"
ipc volumeUp
waitfor "d['volume'] == 35" 3 && result volume-ipc-step PASS || result volume-ipc-step FAIL "$(q "['volume']")"
shot 20-osd-volume 0.2

# ---- notifications, DND ------------------------------------------------------
n0=$(q "['notifications']"); p0=$(q "['popups']")
notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
waitfor "d['notifications'] == $n0 + 1 and d['popups'] == min($p0 + 1, 4)" 4 \
    && result notification-popup PASS || result notification-popup FAIL "$(st)"
shot 21-notification-popup 0.3
ipc dnd
p1=$(q "['popups']")
notify-send -a Backup "Backup finished" "142 files, 3.1 GB"
waitfor "d['notifications'] == $n0 + 2" 4 && sleep 0.3
[ "$(q "['popups']")" -le "$p1" ] && [ "$(q "['dnd']")" = True ] \
    && result dnd-suppresses-popups PASS || result dnd-suppresses-popups FAIL "$(st)"
notify-send -u critical -a Power "Battery low" "5% left"
waitfor "d['notifications'] == $n0 + 3 and d['popups'] >= 1" 4 \
    && result dnd-lets-critical-through PASS || result dnd-lets-critical-through FAIL "$(st)"
ipc dnd

# ---- settings file is live -----------------------------------------------------
settings '{"caffeine": true, "doNotDisturb": false}'
waitfor "d['caffeine'] is True" 4 && result settings-hot-reload PASS || result settings-hot-reload FAIL "$(st)"
ipc caffeine
sleep 1.2
grep -q '"caffeine": false' "$SHANI_SHELL_SETTINGS" \
    && result settings-written-back PASS || result settings-written-back FAIL "$(cat "$SHANI_SHELL_SETTINGS")"

# ---- launcher ------------------------------------------------------------------
ipc launcher "=2*(3+4)^2"
waitfor "d['topResult'] == '= 98'" 3 && result launcher-calculator PASS || result launcher-calculator FAIL "$(q "['topResult']")"
shot 22-launcher-calc 0.3
ipc launcher "text"
waitfor "d['topResult'] == 'Text Editor'" 3 && result launcher-app-search PASS || result launcher-app-search FAIL "$(q "['topResult']")"
shot 23-launcher-apps 0.3
ipc launcher ""
shot 42-launcher-full 0.6
ipc launcher "Terminal two"
waitfor "d['topResult'] == 'Terminal two'" 3 && result launcher-finds-windows PASS || result launcher-finds-windows FAIL "$(q "['topResult']")"
ipc launcher "dark"
waitfor "d['topResult'] == 'Dark style'" 3 && result launcher-finds-actions PASS || result launcher-finds-actions FAIL "$(q "['topResult']")"
before=$(q "['dark']")
wtype -k Return
waitfor "str(d['dark']) != '$before'" 3 && result launcher-action-runs PASS || result launcher-action-runs FAIL
mkdir -p /root/Documents && echo "Q3 numbers" > /root/Documents/quarterly-report.txt
ipc launcher "quarterly"
waitfor "d['topResult'] == 'quarterly-report.txt'" 5 && result launcher-finds-files PASS || result launcher-finds-files FAIL "$(q "['topResult']")"
shot 43-launcher-file 0.6      # Quick Look: the text preview in the side pane
wtype -M ctrl -k Return -m ctrl
sleep 1
grep -q "The file: /root/Documents/quarterly-report.txt" /work/out/logs/mock.log \
    && result launcher-ctrl-enter-asks-about-file PASS || result launcher-ctrl-enter-asks-about-file FAIL "$(tail -2 /work/out/logs/mock.log)"
ipc launcher "Q3 numbers"      # only inside the file, not in its name
waitfor "d['topResult'] == 'quarterly-report.txt'" 6 && result launcher-searches-inside-files PASS || result launcher-searches-inside-files FAIL "$(q "['topResult']")"
ipc launcher "5 km in miles"
waitfor "d['topResult'] == '= 3.106856 miles'" 3 && result launcher-converts-units PASS || result launcher-converts-units FAIL "$(q "['topResult']")"
ipc launcher "100 f to c"
waitfor "d['topResult'] == '= 37.777778 c'" 3 && result launcher-converts-temperature PASS || result launcher-converts-temperature FAIL "$(q "['topResult']")"
ipc launcher "100 usd in inr"
waitfor "d['topResult'] == 'Convert 100 usd in inr with Chronoa'" 3 && result launcher-currency-goes-to-chronoa PASS || result launcher-currency-goes-to-chronoa FAIL "$(q "['topResult']")"
ipc launcher "why is my laptop slow"
waitfor "d['topResult'].startswith('Ask Chronoa')" 3 && result launcher-ask-fallback PASS || result launcher-ask-fallback FAIL "$(q "['topResult']")"
ipc closeAll

# ---- Island: Chronoa's companion, approvals answered in place ----------------
waitfor "d['bridge'] and d['chronoa'] != 'offline'" 5 && result island-bridge-online PASS || result island-bridge-online FAIL "$(st)"
M="--session --dest org.shani.Chronoa.Mascot --object-path /org/shani/Chronoa/Mascot"
gdbus call $M --method org.shani.Chronoa.Mascot.Host 2>&1 | grep -q "island" \
    && result island-host-answers PASS || result island-host-answers FAIL
magick -size 64x64 xc:none -fill '#ff7f50' -draw 'circle 32,32 32,4' -fill '#08110f' \
    -draw 'rectangle 22,24 27,36' -draw 'rectangle 37,24 42,36' /tmp/frame.png
gdbus call $M --method org.shani.Chronoa.Mascot.Art /tmp/frame.png 2>&1 | grep -q true \
    && waitfor "d['art'] == '/tmp/frame.png'" 3 \
    && result island-shows-chronoa-art PASS || result island-shows-chronoa-art FAIL "$(q "['art']")"
gdbus call $M --method org.shani.Chronoa.Mascot.Art /nonexistent.png 2>&1 | grep -q false \
    && result island-art-refuses-missing-file PASS || result island-art-refuses-missing-file FAIL
gdbus call $M --method org.shani.Chronoa.Mascot.Rect | python3 -c "
import re,sys; v=list(map(int,re.findall(r'-?\d+',sys.stdin.read()))); sys.exit(0 if v[2]>0 and v[3]>0 and 800<v[0]<1100 else 1)" \
    && result island-reports-mascot-rect PASS || result island-reports-mascot-rect FAIL "$(gdbus call $M --method org.shani.Chronoa.Mascot.Rect)"
ipc ask "Tidy my desktop"
waitfor "d['approval'] is not None" 6 && result island-approval-appears PASS || result island-approval-appears FAIL "$(st)"
shot 24-island-approval 0.5
ipc approve "Allow this once"
waitfor "d['approval'] is None and d['chronoa'] in ('idle', 'speaking')" 8 \
    && result island-approval-answered PASS || result island-approval-answered FAIL "$(st)"
ipc closeChronoa

# ---- sidebar -------------------------------------------------------------------
ipc controlCenter audio
waitfor "d['controlCenter'] and d['expanded'] == 'audio'" 3 && result sidebar-opens PASS || result sidebar-opens FAIL
shot 25-sidebar 0.6
ipc closeAll

# ---- Alt+Tab: most recent first, the previous window preselected -----------------
niri msg action focus-workspace 2
sleep 0.6
niri msg action focus-workspace 1
waitfor "d['focusedTitle'] == 'Terminal one'" 3
ipc switcher
waitfor "d['switcher']" 3 && result switcher-opens PASS || result switcher-opens FAIL
shot 33-switcher 0.4
wtype -k Return
waitfor "not d['switcher'] and d['focusedTitle'] == 'Terminal two'" 4 \
    && result switcher-flips-to-previous-window PASS || result switcher-flips-to-previous-window FAIL "$(q "['focusedTitle']")"
niri msg action focus-workspace 1

# ---- input method: fcitx5 (started by the session's niri config) ---------------
niri msg action focus-workspace 1
sleep 0.5
waitfor "d['inputMethod'] == 'keyboard-us'" 6 && result im-fcitx5-running PASS || result im-fcitx5-running FAIL "$(q "['inputMethod']")"
ipc inputMethod
waitfor "d['inputMethod'] == 'm17n_hi_itrans'" 4 && result im-switches-to-hindi-phonetic PASS || result im-switches-to-hindi-phonetic FAIL "$(q "['inputMethod']")"
shot 37-input-method 0.4
ipc inputMethod

# ---- screen keyboard: Marathi through the virtual-keyboard protocol -------------
# the launcher holds keyboard focus; the keyboard never takes it, so what it
# types lands there — tapped through the same path as a finger (oskPress)
ipc launcher ""
ipc osk
waitfor "d['osk']" 3 && result osk-shows PASS || result osk-shows FAIL
ipc oskLanguage
waitfor "d['oskLang'] == 'mr'" 3 && result osk-switches-to-marathi PASS || result osk-switches-to-marathi FAIL "$(q "['oskLang']")"
shot 38-osk-marathi 0.5
for k in न म स ् त ए; do ipc oskPress "$k"; sleep 0.35; done
# न म स ् त + ए after a consonant -> the matra े : नमस्ते
waitfor "d['topResult'] == 'Ask Chronoa: नमस्ते'" 4 && result osk-types-marathi-with-smart-matra PASS \
    || result osk-types-marathi-with-smart-matra FAIL "$(q "['topResult']") / typed $(q "['oskTyped']")"
shot 39-osk-typed 0.3
ipc osk
ipc closeAll

# any xkb layout: Russian and Tamil, generated from the system's xkb data
settings '{"oskLanguages": ["en", "ru", "in+tam"]}'
ipc launcher ""
ipc osk
waitfor "d['oskLang'] == 'en'" 4 || result osk-list-change-keeps-a-sane-language FAIL "$(q "['oskLang']")"
ipc oskLanguage
waitfor "d['oskLang'] == 'ru'" 4 || result osk-xkb-russian FAIL "language did not switch: $(q "['oskLang']")"
sleep 1.5
ipc oskPress "й"; sleep 0.4; ipc oskPress "ц"; sleep 0.4
waitfor "d['topResult'] == 'Ask Chronoa: йц'" 4 && result osk-xkb-russian PASS || result osk-xkb-russian FAIL "$(q "['topResult']")"
shot 40-osk-russian 0.4
ipc oskLanguage
waitfor "d['oskLang'] == 'in+tam'" 4 || result osk-xkb-tamil FAIL "language did not switch: $(q "['oskLang']")"
sleep 1
ipc launcher ""              # a fresh field: the Russian letters are still in the old one
sleep 0.5
for k in வ ண க ் க ம ்; do ipc oskPress "$k"; sleep 0.3; done
waitfor "d['topResult'] == 'Ask Chronoa: வணக்கம்'" 4 && result osk-xkb-tamil PASS || result osk-xkb-tamil FAIL "$(q "['topResult']")"
shot 41-osk-tamil 0.4
ipc osk
ipc closeAll
settings '{}'


# ---- window menu on the bar's title -------------------------------------------
niri msg action focus-workspace 1
sleep 0.5
# which window, asked before the menu opens: the menu takes the keyboard,
# and while it is up no window has focus
wid=$(niri msg -j focused-window | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
ipc windowMenu
waitfor "d['windowMenu']" 3 && result window-menu-opens PASS || result window-menu-opens FAIL
shot 44-window-menu 0.4
ipc windowMenuAction ws3
sleep 1
# the window's workspace index now, from niri's own view
widx() { python3 -c "
import json, subprocess
wins = json.loads(subprocess.run(['niri','msg','-j','windows'], capture_output=True, text=True).stdout)
spaces = json.loads(subprocess.run(['niri','msg','-j','workspaces'], capture_output=True, text=True).stdout)
w = next(x for x in wins if x['id'] == $1)
print(next(s['idx'] for s in spaces if s['id'] == w['workspace_id']))"; }
[ "$(widx "$wid")" = 3 ] && result window-menu-moves-window PASS || result window-menu-moves-window FAIL "window $wid on workspace $(widx "$wid")"
niri msg action move-window-to-workspace --window-id "$wid" --focus false 1
# snap layouts: "A third" sets the column to a third of the screen
niri msg action focus-window --id "$wid"; sleep 0.3
ipc windowMenu
waitfor "d['windowMenu']" 3
ipc windowMenuAction third
sleep 0.8
ratio=$(python3 -c "
import json, subprocess
w = next(x for x in json.loads(subprocess.run(['niri','msg','-j','windows'], capture_output=True, text=True).stdout) if x['id'] == $wid)
o = list(json.loads(subprocess.run(['niri','msg','-j','outputs'], capture_output=True, text=True).stdout).values())[0]
print(round(w['layout']['tile_size'][0] / o['logical']['width'], 2))")
python3 -c "import sys; sys.exit(0 if 0.25 <= float('$ratio') <= 0.4 else 1)" 2>/dev/null \
    && result window-menu-snap-third PASS "$ratio" || result window-menu-snap-third FAIL "width ratio $ratio"
niri msg action set-column-width 50%

# ---- minimise and show desktop (familiar from Windows and macOS) ---------------------------
niri msg action focus-window --id "$wid"; sleep 0.3
vis0=$(q "['visibleWorkspaces']"); here=$(widx "$wid")
ipc minimiseWindow "$wid"
waitfor "$wid in d['minimised'] and d['visibleWorkspaces'] == $vis0" 4 \
    && result window-minimise PASS || result window-minimise FAIL "$(q "['minimised'], d['visibleWorkspaces']") (was $vis0)"
ipc restoreWindow "$wid"
waitfor "$wid not in d['minimised']" 4 && [ "$(widx "$wid")" = "$here" ] \
    && result window-restore PASS || result window-restore FAIL "$(q "['minimised']") on $(widx "$wid"), wanted $here"
n=$(niri msg -j windows | python3 -c "import json,sys; ws=[w for w in json.load(sys.stdin)]; print(len(ws))")
ipc showDesktop
waitfor "len(d['minimised']) >= 1 and $wid in d['minimised']" 4 && result show-desktop PASS "$(q "['minimised']")" || result show-desktop FAIL "$(q "['minimised']")"
ipc showDesktop
waitfor "d['minimised'] == []" 4 && result show-desktop-again-restores PASS || result show-desktop-again-restores FAIL "$(q "['minimised']")"

# ---- start hints: an empty workspace shows the keys that reach everything ----------------
hints() { niri msg -j layers | python3 -c "import json,sys; print(sum(1 for l in json.load(sys.stdin) if l['namespace'] == 'shani-start-hints'))"; }
niri msg action focus-workspace 99; sleep 0.5          # the empty one at the end
settings '{"startHintsDone": false}'
h1=$(hints); shot 26i-start-hints 0.3
settings '{"startHintsDone": false, "launcherOpens": 5}'
h2=$(hints)
[ "$h1" -ge 1 ] && [ "$h2" = 0 ] && result start-hints-shown-then-retired PASS || result start-hints-shown-then-retired FAIL "fresh $h1, after 5 launches $h2"
settings '{}'; niri msg action focus-workspace 1

# ---- the wallpaper and GNOME's setting for it (the Wallpaper portal writes that key) ----
magick -size 64x64 xc:'#336699' /tmp/portal-wall.png 2>/dev/null
gsettings set org.gnome.desktop.background picture-uri "file:///tmp/portal-wall.png"
gsettings set org.gnome.desktop.background picture-uri-dark "file:///tmp/portal-wall.png"
waitfor "d['wallpaperNow'] == '/tmp/portal-wall.png'" 4 && result wallpaper-follows-portal PASS || result wallpaper-follows-portal FAIL "$(q "['wallpaperNow']")"
ipc setting wallpaperDark /usr/share/backgrounds/shani/shani-dark.jpg; ipc setting wallpaperLight /usr/share/backgrounds/shani/shani-light.jpg; sleep 1
case "$(gsettings get org.gnome.desktop.background picture-uri-dark)" in *shani-dark.jpg*) result wallpaper-written-for-apps PASS ;; *) result wallpaper-written-for-apps FAIL "$(gsettings get org.gnome.desktop.background picture-uri-dark)" ;; esac

# ---- what to do with a file (after Tangerine): the card offers what fits, the result lands beside it ----
mkdir -p /tmp/fa; magick -size 80x60 xc:'#cc6633' /tmp/fa/photo.png
ipc fileActions /tmp/fa/photo.png
waitfor "'webp' in d['fileActions'] and 'png' in d['fileActions'] and 'ask' in d['fileActions']" 3 && result file-actions-for-image PASS || result file-actions-for-image FAIL "$(q "['fileActions']")"
shot 26j-file-actions 0.3
ipc fileAction webp
waitfor "d['fileActionLast'] == '/tmp/fa/photo.webp'" 8 && [ -s /tmp/fa/photo.webp ] && result file-action-converts PASS || result file-action-converts FAIL "$(q "['fileActionLast']") $(ls /tmp/fa)"
ffmpeg -y -loglevel error -f lavfi -i testsrc=size=160x120:rate=10 -t 2 /tmp/fa/clip.mp4 2>/dev/null
ipc fileActions /tmp/fa/clip.mp4; sleep 0.3; ipc fileAction gif
waitfor "d['fileActionLast'] == '/tmp/fa/clip.gif'" 15 && [ -s /tmp/fa/clip.gif ] && result file-action-video-gif PASS || result file-action-video-gif FAIL "$(q "['fileActionLast']") $(ls /tmp/fa)"

# ---- fit a size limit (a form's photo: 20-50 KB, 200x230 px): within it, exactly that size ----
magick -size 2400x1800 plasma:fractal /tmp/fa/big.jpg
ipc fileActions /tmp/fa/big.jpg; sleep 0.3; ipc fileFit 50 20 200 230
waitfor "d['fileActionLast'].endswith('.jpg') and '20 KB-50 KB' in d['fileActionLast']" 15
f=$(q "['fileActionLast']"); sz=$(stat -c%s "$f" 2>/dev/null || echo 0); dim=$(magick identify -format "%wx%h" "$f" 2>/dev/null)
[ "$sz" -ge 20480 ] && [ "$sz" -le 51200 ] && [ "$dim" = 200x230 ] && result file-fit-size-limit PASS "$((sz/1024)) KB $dim" || result file-fit-size-limit FAIL "'$f' $sz bytes $dim"

# ---- desktop layouts: a click tries one on for real, Esc puts it back, Enter keeps it --------
lsw() { niri msg -j layers | python3 -c "import json,sys; print(sum(1 for l in json.load(sys.stdin) if l['namespace'] == 'shani-layout-switcher'))"; }
kdl="${XDG_CONFIG_HOME:-$HOME/.config}/niri/shani-input.kdl"
before=$(q "['winWidth'], d['widgets'], d['dockHides']")
ipc layoutSwitcher
waitfor "d['layoutSwitcher']" 3 && [ "$(lsw)" -ge 1 ] && result layout-switcher-opens PASS || result layout-switcher-opens FAIL "$(q "['layoutSwitcher']") layers $(lsw)"
shot 26k-layout-switcher 0.4
wtype -k Right   # Shani -> Classic: windows open full width, widgets down the left
waitfor "d['winWidth'] == 1 and 'agenda' in d['widgets']" 3 && sleep 1.2 && grep -q "proportion 1.00" "$kdl" && niri validate -c "${NIRI_CONFIG:-/work/dev/niri/session.kdl}" >/dev/null 2>&1 && niri msg -j windows >/dev/null && result layout-tries-on PASS || result layout-tries-on FAIL "$(q "['winWidth'], d['widgets']") $(grep -o 'proportion [0-9.]*' "$kdl")"
shot 26l-layout-classic 0.3
wtype -k Escape
waitfor "not d['layoutSwitcher']" 3 && [ "$(q "['winWidth'], d['widgets'], d['dockHides']")" = "$before" ] && result layout-cancel-restores PASS || result layout-cancel-restores FAIL "$(q "['winWidth'], d['widgets'], d['dockHides']") vs $before"
ipc layoutSwitcher; waitfor "d['layoutSwitcher']" 3
# each key tries a layout on for real (niri reloads): the next one waits for it
wtype -k Right; waitfor "'agenda' in d['widgets']" 3
wtype -k Right; waitfor "d['widgets'] == [] and d['dockHides']" 3; sleep 0.3
wtype -k Return    # Focus, kept
waitfor "not d['layoutSwitcher'] and d['layoutPreset'] == 'focus' and d['dockHides'] and d['widgets'] == []" 3 && result layout-keeps PASS || result layout-keeps FAIL "$(q "['layoutPreset'], d['dockHides'], d['widgets']")"
settings '{}'

# ---- desktop icons: the Desktop folder's files down the left, or stacks by kind ----------
layer() { niri msg -j layers | python3 -c "import json,sys; print(sum(1 for l in json.load(sys.stdin) if l['namespace'] == '$1'))"; }
ipc setting desktopIcons true; sleep 0.5      # off by default (only Classic and Dashboard turn them on)
[ -d /root/Desktop ] && result desktop-folder-made PASS || result desktop-folder-made FAIL "no /root/Desktop: the icons would list / instead"
[ "$(layer shani-desktop-icons)" = 0 ] && result desktop-empty-shows-nothing PASS || result desktop-empty-shows-nothing FAIL "$(layer shani-desktop-icons) layers on an empty desktop"
printf 'q3\n' > /root/Desktop/report.txt; printf 'notes\n' > /root/Desktop/notes.md; magick -size 32x32 xc:teal /root/Desktop/photo.png; mkdir -p /root/Desktop/Projects
i=0; until [ "$(layer shani-desktop-icons)" -ge 1 ] || [ $i -ge 12 ]; do sleep 0.25; i=$((i+1)); done
if [ -f "$A11Y" ]; then
    t=$(timeout 20 python3 "$A11Y" find "button:^report.txt$" 2>/dev/null | head -1)
    [ -n "$t" ] && result desktop-icons-show-files PASS || result desktop-icons-show-files FAIL "layers $(layer shani-desktop-icons)"
    shot 26m-desktop-icons 0.3
    ipc setting deskStacks true; sleep 1
    t=$(timeout 20 python3 "$A11Y" find "button:^Documents \(2\)$" 2>/dev/null | head -1)
    [ -n "$t" ] && result desktop-stacks-by-kind PASS || result desktop-stacks-by-kind FAIL "$(timeout 20 python3 "$A11Y" find "button:\(" 2>&1 | head -3 | tr '\n' ';')"
    ipc setting deskStacks false
else
    [ "$(layer shani-desktop-icons)" -ge 1 ] && result desktop-icons-show-files PASS || result desktop-icons-show-files FAIL
fi
ipc setting desktopIcons false; sleep 1
[ "$(layer shani-desktop-icons)" = 0 ] && result desktop-icons-switch-off PASS || result desktop-icons-switch-off FAIL "$(layer shani-desktop-icons) layers"
ipc setting desktopIcons true
rm -rf /root/Desktop/report.txt /root/Desktop/notes.md /root/Desktop/photo.png /root/Desktop/Projects

# ---- desktop widgets: each one on its own layer, there while switched on, gone when off ----
settings '{"desktopWidgets": ["clock", "agenda", "note", "clocks"]}'
ok=1; for w in agenda note clocks; do [ "$(layer shani-desk-$w)" -ge 1 ] || ok=0; done
[ $ok = 1 ] && result desktop-widgets-show PASS || result desktop-widgets-show FAIL "agenda $(layer shani-desk-agenda) note $(layer shani-desk-note) clocks $(layer shani-desk-clocks)"
shot 26n-desktop-widgets 0.3
settings '{"desktopWidgets": ["clock"]}'
[ "$(layer shani-desk-agenda)$(layer shani-desk-note)$(layer shani-desk-clocks)" = 000 ] && result desktop-widgets-hide PASS || result desktop-widgets-hide FAIL
settings '{}'

# ---- the dock and bar step aside (Plank's intelligent hide, the default) ---------------
# smart: in view while windows sit beside it, away while one is moved over it, back after
settings '{}'
foot --app-id=hide-test sh -c 'sleep 120' >/dev/null 2>&1 &
HPID=$!
i=0; until niri msg -j windows | grep -q '"hide-test"' || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
hid=$(niri msg -j windows | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if w['app_id'] == 'hide-test'))")
waitfor "d['dockMode'] == 'smart' and d['dockShown'] and d['barShown']" 3 && result dock-smart-stays-for-tiled PASS || result dock-smart-stays-for-tiled FAIL "$(q "['dockMode'], d['dockShown']")"
niri msg action toggle-window-floating --id "$hid"; sleep 0.3
niri msg action move-floating-window --id "$hid" -y +3000
waitfor "not d['dockShown']" 3 && result dock-smart-steps-aside PASS || result dock-smart-steps-aside FAIL "$(niri msg -j windows | python3 -c "import json,sys; print([w['layout'] for w in json.load(sys.stdin) if w['app_id'] == 'hide-test'])")"
waitfor "d['dockHintSeen']" 2 && result dock-says-where-it-went PASS || result dock-says-where-it-went FAIL
shot 26o-dock-stepped-aside 0.3
niri msg action move-floating-window --id "$hid" -y -3000
waitfor "d['dockShown']" 3 && result dock-smart-comes-back PASS || result dock-smart-comes-back FAIL "$(niri msg -j windows | python3 -c "import json,sys; print([w['layout'] for w in json.load(sys.stdin) if w['app_id'] == 'hide-test'])")"
# the bar, smart: away while that window is over the top; the Island asking brings it back
ipc setting barVisibility smart; sleep 0.5
waitfor "not d['barShown']" 3 && result bar-smart-steps-aside PASS || result bar-smart-steps-aside FAIL "$(q "['barMode'], d['barShown']")"
ipc askIsland
waitfor "d['barShown']" 3 && result bar-back-for-the-island PASS || result bar-back-for-the-island FAIL
wtype -k Escape; sleep 0.3; ipc closeAll       # the ask field holds the keyboard until Esc
# hide: the windows get the whole height, the dock waits at the edge
ipc setting dockVisibility hide; niri msg action toggle-window-floating --id "$hid"; sleep 0.5
waitfor "not d['dockShown']" 3 && result dock-hide-waits-at-edge PASS || result dock-hide-waits-at-edge FAIL
kill $HPID 2>/dev/null; settings '{}'

# ---- the bar's window controls: minimise, maximise, close, for any window --------------
winid() { niri msg -j windows | python3 -c "import json,sys; print(next((w['id'] for w in json.load(sys.stdin) if w['app_id'] == '$1'), ''))"; }
width() { niri msg -j windows | python3 -c "import json,sys; print(next((int(w['layout']['tile_size'][0]) for w in json.load(sys.stdin) if w['id'] == $1), 0))"; }
if [ -f "$A11Y" ]; then
    foot --app-id=ctl-test sh -c 'sleep 120' >/dev/null 2>&1 &
    i=0; until [ -n "$(winid ctl-test)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    cid=$(winid ctl-test); niri msg action focus-window --id "$cid"; sleep 0.5
    w0=$(width "$cid")
    timeout 20 python3 "$A11Y" press "button:^Maximise$" >/dev/null 2>&1; sleep 0.8
    w1=$(width "$cid")
    [ "$w1" -gt "$w0" ] && result bar-window-maximise PASS "$w0 -> $w1 px" || result bar-window-maximise FAIL "$w0 -> $w1 px"
    timeout 20 python3 "$A11Y" press "button:^Minimise" >/dev/null 2>&1
    waitfor "$cid in d['minimised']" 3 && result bar-window-minimise PASS || result bar-window-minimise FAIL "$(q "['minimised']")"
    niri msg action close-window --id "$cid"
    foot --app-id=ctl-test2 sh -c 'sleep 120' >/dev/null 2>&1 &
    i=0; until [ -n "$(winid ctl-test2)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    niri msg action focus-window --id "$(winid ctl-test2)"; sleep 0.5
    timeout 20 python3 "$A11Y" press "button:^Close" >/dev/null 2>&1
    i=0; while [ -n "$(winid ctl-test2)" ] && [ $i -lt 12 ]; do sleep 0.25; i=$((i+1)); done
    [ -z "$(winid ctl-test2)" ] && result bar-window-close PASS || result bar-window-close FAIL "still open"

    # ---- the overview's card: CPU and memory, and Close all asks first ---------------------
    n0=$(q "['windows']")
    niri msg action open-overview; sleep 1
    [ "$(layer shani-overview-stats)" -ge 1 ] && timeout 20 python3 "$A11Y" find "button:^Close all windows$" >/dev/null 2>&1 \
        && result overview-card-shows PASS || result overview-card-shows FAIL "layers $(layer shani-overview-stats)"
    shot 26p-overview-card 0.3
    timeout 20 python3 "$A11Y" press "button:^Close all windows$" >/dev/null 2>&1; sleep 0.4
    timeout 20 python3 "$A11Y" find "button:^Close [0-9]+ windows" >/dev/null 2>&1 && [ "$(q "['windows']")" = "$n0" ] \
        && result overview-close-all-asks-first PASS || result overview-close-all-asks-first FAIL "windows $(q "['windows']") (was $n0)"
    niri msg action close-overview; sleep 0.5

    # ---- the weather, offered in one click when nothing is set ---------------------------
    settings '{}'
    ipc toggleControlCenter; sleep 0.8
    timeout 20 python3 "$A11Y" press "radio button:^where I am$" >/dev/null 2>&1; sleep 1
    grep -q '"useLocation": *true' "$SHANI_SHELL_SETTINGS" && result weather-offered-in-one-click PASS || result weather-offered-in-one-click FAIL "useLocation not set"
    ipc closeAll; settings '{}'
fi

# ---- the Island rides on the bar: a hidden bar takes it along -------------------------------
ipc setting barVisibility hide; sleep 1
[ "$(layer shani-island)" = 0 ] && result island-hides-with-the-bar PASS || result island-hides-with-the-bar FAIL "$(layer shani-island) island layers with the bar hidden"
ipc setting barVisibility always; sleep 0.5
[ "$(layer shani-island)" -ge 1 ] && result island-back-with-the-bar PASS || result island-back-with-the-bar FAIL
settings '{}'

# ---- the drop shelf (Yoink's, in the dock): kept by reference, first in the Shelf, put away
printf 'kept' > "/tmp/kept for later.txt"
ipc shelfPark "/tmp/kept for later.txt"
waitfor "'/tmp/kept for later.txt' in d['shelfParked'] and d['shelfItems'][0] == 'kept for later.txt'" 3 \
    && result shelf-keeps-a-dropped-file PASS || result shelf-keeps-a-dropped-file FAIL "$(q "['shelfParked'], d['shelfItems'][:3]")"
sleep 1; grep -rqs "kept for later" /root/.local/state/quickshell 2>/dev/null && result shelf-survives-a-restart PASS || result shelf-survives-a-restart FAIL "not written under ~/.local/state/quickshell"
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" find "button:^Shelf$" >/dev/null 2>&1 && result shelf-tile-in-dock PASS || result shelf-tile-in-dock FAIL
fi
ipc shelfUnpark "/tmp/kept for later.txt"
waitfor "d['shelfParked'] == []" 3 && [ -f "/tmp/kept for later.txt" ] && result shelf-puts-away-keeps-the-file PASS || result shelf-puts-away-keeps-the-file FAIL "$(q "['shelfParked']")"

# ---- picked in the launcher, typed where you were (Win+. and Win+V's way) ------------------
# a terminal reading its keyboard into a file: what arrives is what the person would see
typein() { rm -f "$2"; foot --app-id="$1" sh -c "stty raw -echo; head -c $3 > $2" >/dev/null 2>&1 &
    i=0; until [ -n "$(winid "$1")" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    niri msg action focus-window --id "$(winid "$1")"; sleep 0.5; }
typein emoji-in /tmp/emoji-typed 4
ipc launcher ":grinning face"; waitfor "d['topResult'] == 'grinning face'" 4; sleep 0.3
wtype -k Return
i=0; until [ -s /tmp/emoji-typed ] || [ $i -ge 16 ]; do sleep 0.25; i=$((i+1)); done
[ "$(cat /tmp/emoji-typed 2>/dev/null)" = "😀" ] && result launcher-emoji-typed-in PASS || result launcher-emoji-typed-in FAIL "got '$(cat /tmp/emoji-typed 2>/dev/null)'"
niri msg action close-window --id "$(winid emoji-in)" 2>/dev/null
printf 'paste-me-4791' | wl-copy; sleep 0.6; printf 'something-else' | wl-copy; sleep 0.6
typein paste-in-term /tmp/pasted 13
ipc launcher "c paste-me"; waitfor "d['topResult'].startswith('paste-me')" 4; sleep 0.3
wtype -k Return
i=0; until [ -s /tmp/pasted ] || [ $i -ge 16 ]; do sleep 0.25; i=$((i+1)); done
[ "$(cat /tmp/pasted 2>/dev/null)" = "paste-me-4791" ] && result launcher-clipboard-pasted-in-terminal PASS || result launcher-clipboard-pasted-in-terminal FAIL "got '$(cat /tmp/pasted 2>/dev/null)'"
niri msg action close-window --id "$(winid paste-in-term)" 2>/dev/null

# ---- Do Not Disturb, for how long: it ends by itself ------------------------------------
if [ -f "$A11Y" ]; then
    settings '{}'; ipc controlCenter dnd; sleep 0.8
    timeout 20 python3 "$A11Y" press "^For 1 hour$" >/dev/null 2>&1; sleep 0.6
    waitfor "d['dnd'] and d['dndUntil'] > 0" 3 && result dnd-for-an-hour PASS || result dnd-for-an-hour FAIL "$(q "['dnd'], d['dndUntil']")"
    ipc closeAll
fi
# ends by itself: a time already past turns it off (after the shell's own save of the
# hour above has landed, so it does not write over this)
sleep 1
settings '{"doNotDisturb": true, "dndUntil": 1000}'
waitfor "not d['dnd'] and d['dndUntil'] == 0" 20 && result dnd-ends-by-itself PASS || result dnd-ends-by-itself FAIL "$(q "['dnd'], d['dndUntil']")"
settings '{}'

# ---- the overview: Enter with nothing typed goes to the window picked, not the launcher
ipc closeAll; niri msg action open-overview; sleep 1
wtype -k Return; sleep 0.8
waitfor "not d['overview'] and not d['launcher']" 3 && result overview-enter-picks-window PASS || result overview-enter-picks-window FAIL "$(q "['overview'], d['launcher']")"
ipc closeAll

# ---- screen saver: the clock cover, here by its preview; a key ends it ---------------------
cov() { niri msg -j layers | python3 -c "import json,sys; print(sum(1 for l in json.load(sys.stdin) if l['namespace'] == 'shani-screensaver'))"; }
ipc screenSaverPreview
waitfor "d['screenSaver']" 3 && [ "$(cov)" -ge 1 ] && result screensaver-shows PASS || result screensaver-shows FAIL "$(q "['screenSaver']") layers $(cov)"
shot 26g-screensaver 0.4
wtype -k space
waitfor "not d['screenSaver']" 3 && result screensaver-key-ends PASS || result screensaver-key-ends FAIL

# ---- the charger going in: the ring card, then gone by itself ------------------------------
chg() { niri msg -j layers | python3 -c "import json,sys; print(sum(1 for l in json.load(sys.stdin) if l['namespace'] == 'shani-charging'))"; }
ipc chargingPreview; sleep 0.8; c1=$(chg)
shot 26h-charging 0.2
sleep 3.2; c2=$(chg)
[ "$c1" -ge 1 ] && [ "$c2" = 0 ] && result charging-animation PASS || result charging-animation FAIL "during $c1, after $c2"

# ---- a notification's own sound (the spec's sound-name hint) wins over ours -------------------
notify-send -a Timer -h string:sound-name:complete "Done" "the bread is ready"
waitfor "d['notifLastSound'].endswith('/complete.oga')" 3 && result notification-sound-name PASS || result notification-sound-name FAIL "$(q "['notifLastSound']")"

# ---- scratchpads: the drop-down terminal starts, goes away, comes back (Mod+`) ---------
padw() { niri msg -j windows | python3 -c "import json,sys; w=[x for x in json.load(sys.stdin) if x['app_id']=='shani-pad-terminal']; print(w[0]['id'] if w else '')"; }
ipc scratchpad terminal
i=0; while [ -z "$(padw)" ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i+1)); done; pid_=$(padw)
fl=$(niri msg -j windows | python3 -c "import json,sys; print(next((x['is_floating'] for x in json.load(sys.stdin) if x['app_id']=='shani-pad-terminal'), None))")
[ -n "$pid_" ] && [ "$fl" = True ] && result scratchpad-starts-floating PASS || result scratchpad-starts-floating FAIL "window '$pid_' floating $fl"
niri msg action focus-window --id "$pid_" 2>/dev/null; sleep 0.4
ipc scratchpad terminal
waitfor "$pid_ in d['minimised'] and d['scratchpad'] == 'hidden'" 4 && result scratchpad-hides PASS || result scratchpad-hides FAIL "$(q "['scratchpad'], d['minimised']")"
ipc scratchpad terminal
waitfor "$pid_ not in d['minimised'] and d['scratchpad'] == 'shown' and d['focusedTitle'] is not None" 4 && result scratchpad-comes-back PASS || result scratchpad-comes-back FAIL "$(q "['scratchpad'], d['minimised']")"
niri msg action close-window --id "$pid_" 2>/dev/null

# ---- on every workspace: a pinned window follows to each workspace shown --------------
niri msg action focus-workspace "$here"; sleep 0.3
ipc pinWindow "$wid"
waitfor "$wid in d['pinned']" 3 || true
# (not 3: by now that is the hidden "minimised" workspace, which pinned windows rightly skip)
# by workspace, not number: the one it leaves may be emptied, and niri renumbers
focusedws() { niri msg -j workspaces | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if w['is_focused']))"; }
wsof() { niri msg -j windows | python3 -c "import json,sys; print(next(w['workspace_id'] for w in json.load(sys.stdin) if w['id'] == $1))"; }
niri msg action focus-workspace 2; sleep 1
[ "$(wsof "$wid")" = "$(focusedws)" ] && result pinned-window-follows PASS || result pinned-window-follows FAIL "window $wid on workspace id $(wsof "$wid"), focused $(focusedws)"
ipc pinWindow "$wid"
waitfor "$wid not in d['pinned']" 3 || true
was=$(wsof "$wid"); niri msg action focus-workspace 99; sleep 1     # the empty one at the end
[ "$(wsof "$wid")" = "$was" ] && [ "$(focusedws)" != "$was" ] && result unpinned-window-stays PASS || result unpinned-window-stays FAIL "window $wid on workspace id $(wsof "$wid"), was $was"
niri msg action move-window-to-tiling --id "$wid" 2>/dev/null
niri msg action move-window-to-workspace --window-id "$wid" --focus false "$here"; niri msg action focus-workspace "$here"

# the dock's own buttons, below: the window pinned above floats over the dock, and the
# default intelligent hide rightly steps aside for it - these are about the buttons
# (the hiding has its own checks), so the dock stays up while they run
ipc setting dockVisibility always; sleep 0.5
# ---- workspaces on the dock (Pantheon's): a tile each, "+" starts a new one -------------
if [ -f "$A11Y" ]; then
    t=$(timeout 20 python3 "$A11Y" find "button:^Workspace 1, " 2>/dev/null | head -1)
    [ -n "$t" ] && result dock-workspace-tiles PASS "$t" || result dock-workspace-tiles FAIL "dock shown $(q "['dockShown']"): $(timeout 20 python3 "$A11Y" find "button:Workspace" 2>&1 | head -3 | tr '\n' ';')"
    ws0=$(q "['focusedWorkspace']")
    timeout 20 python3 "$A11Y" press "button:^New workspace$" >/dev/null 2>&1
    waitfor "d['focusedWorkspace'] > $ws0 and d['focusedTitle'] is None" 4 && result dock-new-workspace PASS "$(q "['focusedWorkspace']")" || result dock-new-workspace FAIL "$(q "['focusedWorkspace']") (was $ws0)"
    shot 26e-dock-workspaces 0.3
    niri msg action focus-workspace "$here"
fi

# ---- badges: an app's unread notifications on its dock icon ---------------------------
notify-send -a "Text Editor" -h string:desktop-entry:org.gnome.TextEditor "Draft saved" "notes.txt"
waitfor "d['badges'].get('org.gnome.texteditor', 0) >= 1" 3 && result dock-badge-count PASS || result dock-badge-count FAIL "$(q "['badges']")"
if [ -f "$A11Y" ]; then
    a=$(timeout 20 python3 "$A11Y" find "button:^Text Editor, 1 notification$" 2>/dev/null | head -1)
    [ -n "$a" ] && result dock-badge-announced PASS || result dock-badge-announced FAIL "$(timeout 20 python3 "$A11Y" find "button:Text Editor" 2>&1 | head -3 | tr '\n' ';')"
fi
shot 26a-dock-badge 0.2
# an app's own count and progress (LauncherEntry, a session-bus signal) win over its notifications
waitfor "d['launcherEntryReady']" 5 || true
le() { gdbus emit --session --object-path /com/canonical/unity/launcherentry/1 --signal com.canonical.Unity.LauncherEntry.Update "'application://org.gnome.TextEditor.desktop'" "$1" >/dev/null; }
le "{'count': <int64 7>, 'count-visible': <true>, 'progress': <0.5>, 'progress-visible': <true>}"
waitfor "d['launcherEntries'].get('org.gnome.texteditor', {}).get('count') == 7" 3 && result launcher-entry-heard PASS || result launcher-entry-heard FAIL "$(q "['launcherEntries']")"
if [ -f "$A11Y" ]; then
    a=$(timeout 20 python3 "$A11Y" find "button:^Text Editor, 7 notifications, 50% done$" 2>/dev/null | head -1)
    [ -n "$a" ] && result dock-shows-app-count-and-progress PASS || result dock-shows-app-count-and-progress FAIL "$(timeout 20 python3 "$A11Y" find "button:Text Editor" 2>&1 | head -3 | tr '\n' ';')"
fi
shot 26c-dock-progress 0.2
le "{'count-visible': <false>, 'progress-visible': <false>}"

# ---- files dropped on a dock icon open in that app (gio launch, its desktop file) ----
mkdir -p /root/.local/share/applications
printf '#!/bin/sh\nfor f; do echo "$f"; done > /tmp/dropped\n' > /tmp/drop-test.sh; chmod +x /tmp/drop-test.sh
printf '[Desktop Entry]\nType=Application\nName=Drop test\nExec=/tmp/drop-test.sh %%F\n' > /root/.local/share/applications/shani-drop-test.desktop
printf 'hello' > "/tmp/a dropped file.txt"; rm -f /tmp/dropped
ipc openFilesWith shani-drop-test "/tmp/a dropped file.txt"
i=0; while [ ! -s /tmp/dropped ] && [ $i -lt 12 ]; do sleep 0.25; i=$((i+1)); done
grep -qx "/tmp/a dropped file.txt" /tmp/dropped 2>/dev/null && result dock-drop-opens-file PASS || result dock-drop-opens-file FAIL "$(cat /tmp/dropped 2>&1 | head -2 | tr '\n' ';')"
ipc setting dockVisibility smart

# ---- reopening apps: the apps open now are kept for the next sign-in ----------------------
foot -a foot -T "Reopen me" sleep 600 >/dev/null 2>&1 &
waitfor "'foot' in d['reopenSaved']" 10 && result reopen-apps-kept PASS || result reopen-apps-kept FAIL "$(q "['reopenSaved']")"
nf() { niri msg -j windows | python3 -c "import json,sys; print(sum(1 for w in json.load(sys.stdin) if w['app_id'] == 'foot'))"; }
f0=$(nf); ipc setting reopenApps always; ipc reopenOffer
i=0; while [ "$(nf)" -le "$f0" ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i+1)); done
[ "$(nf)" -gt "$f0" ] && result reopen-apps-reopens PASS "$(q "['reopenOffered']")" || result reopen-apps-reopens FAIL "foot windows $(nf), offered $(q "['reopenOffered']")"
ipc setting reopenApps ask
for id in $(niri msg -j windows | python3 -c "import json,sys; print(' '.join(str(w['id']) for w in json.load(sys.stdin) if w['app_id'] == 'foot'))"); do niri msg action close-window --id "$id"; done

# ---- Caps Lock / Num Lock: the LED, shown when it changes ----------------------------------
echo 1 > "/tmp/fake-leds/input3::capslock/brightness"
waitfor "d['capsLock']" 3 && result caps-lock-seen PASS || result caps-lock-seen FAIL "$(q "['capsLock']")"
shot 26b-caps-lock-osd 0.1
echo 0 > "/tmp/fake-leds/input3::capslock/brightness"
waitfor "not d['capsLock']" 3 && result caps-lock-off-seen PASS || result caps-lock-off-seen FAIL

# ---- ambient-sensor brightness: follow the sensor, floor, stop when the person says so ----
# the container has no backlight, so the service computes and reports the level
# (SHANI_LUX_FILE=300 at 300 lx → (300-15)/385 → 74 %) without stepping hardware
settings '{"adaptiveBrightness":true}'
waitfor "d['ambientSensor'] and d['ambientEnabled'] and d['ambientTarget'] == 74" 6 \
    && result ambient-follows-sensor PASS || result ambient-follows-sensor FAIL "$(q "['ambientSensor','ambientEnabled','ambientTarget','ambientLux']")"
shot 26c-ambient-osd 0.1
echo 60 > "$SHANI_LUX_FILE"     # dim room: the floor is 0.12, so the level must sink to ~12
waitfor "d['ambientTarget'] <= 17" 90 \
    && result ambient-dims-to-floor PASS || result ambient-dims-to-floor FAIL "$(q "['ambientTarget','ambientLux']")"
echo 300 > "$SHANI_LUX_FILE"
settings '{"adaptiveBrightness":false}'
waitfor "not d['ambientEnabled'] and d['ambientTarget'] <= 17" 4 \
    && result ambient-off-stops PASS || result ambient-off-stops FAIL "$(q "['ambientEnabled','ambientTarget']")"
# a person's own change holds the sensor off 30 s — real hardware only, testbed

# ---- saved networks: metered ("limit background data") and auto-connect, through nmcli ----
if [ -f "$A11Y" ]; then
    ln -sf /work/dev/fake-nmcli.sh /usr/local/bin/nmcli; rm -f /tmp/nm-log /tmp/nm-metered /tmp/nm-auto
    ipc settingsCategory network; sleep 1.2
    timeout 20 python3 "$A11Y" press "check box:^Limit background data$" >/dev/null 2>&1; sleep 0.8
    [ "$(cat /tmp/nm-metered 2>/dev/null)" = yes ] && result network-metered-set PASS || result network-metered-set FAIL "$(tail -3 /tmp/nm-log 2>&1 | tr '\n' ';')"
    timeout 20 python3 "$A11Y" press "check box:^Connect automatically$" >/dev/null 2>&1; sleep 0.8
    [ "$(cat /tmp/nm-auto 2>/dev/null)" = no ] && result network-autoconnect-off PASS || result network-autoconnect-off FAIL "$(tail -3 /tmp/nm-log 2>&1 | tr '\n' ';')"
    shot 26d-saved-networks 0.3
    ipc closeAll; rm -f /usr/local/bin/nmcli
fi

# ---- parental controls: an app the app filter blocks is not offered ---------------------
ipc launcher "Files"; waitfor "d['topResult'] == 'Files'" 4 || true
echo org.gnome.Nautilus > /tmp/appfilter-blocked; ipc closeAll; ipc appFilterRefresh
waitfor "'org.gnome.Nautilus' in d['appsBlocked']" 4 || true
ipc launcher "Files"; sleep 1
[ "$(q "['topResult']")" != Files ] && result app-filter-hides-from-launcher PASS || result app-filter-hides-from-launcher FAIL "$(q "['topResult']")"
ipc closeAll
if [ -f "$A11Y" ]; then
    a=$(timeout 20 python3 "$A11Y" find "button:^Files" 2>/dev/null | head -1)
    [ -z "$a" ] && result app-filter-hides-from-dock PASS || result app-filter-hides-from-dock FAIL "$a"
fi
rm -f /tmp/appfilter-blocked; ipc appFilterRefresh
waitfor "d['appsBlocked'] == []" 4 || true

# ---- remote desktop (Sunshine, niri discussion #680): its user service is the switch ----
if [ -f "$A11Y" ]; then
    ln -sf /work/dev/fake-systemctl-user.sh /usr/local/bin/systemctl; printf '#!/bin/sh\n' > /usr/local/bin/sunshine; chmod +x /usr/local/bin/sunshine
    rm -f /tmp/sun-on /tmp/systemctl-user.log
    ipc settingsCategory sharing; sleep 1.5
    pr=$(timeout 40 python3 "$A11Y" press "check box:^Remote desktop \(Sunshine\)$" 2>&1); sleep 1
    [ -f /tmp/sun-on ] && grep -q "enable --now app-dev.lizardbyte.app.Sunshine.service" /tmp/systemctl-user.log \
        && result remote-desktop-switch PASS || result remote-desktop-switch FAIL "press: $pr; $(tr '\n' ';' < /tmp/systemctl-user.log 2>&1)"
    d=$(timeout 40 python3 "$A11Y" find "check box:^Remote desktop" 2>/dev/null | head -1)
    shot 26f-remote-desktop 0.3
    ipc closeAll; rm -f /usr/local/bin/systemctl /usr/local/bin/sunshine /tmp/sun-on
fi

# ---- the phone's screen (scrcpy): the phones adb sees, mirrored by serial ----------------
waitfor "d['mirrorDevices'] == ['Pixel 7']" 4 && result mirror-lists-phone PASS || result mirror-lists-phone FAIL "$(q "['mirrorDevices']")"
rm -f /tmp/scrcpy-args; ipc mirrorPhone 0A1B2C3D; sleep 0.8
grep -qx 0A1B2C3D /tmp/scrcpy-args 2>/dev/null && grep -qx "Pixel 7" /tmp/scrcpy-args && result mirror-starts-scrcpy PASS || result mirror-starts-scrcpy FAIL "$(tr '\n' ' ' < /tmp/scrcpy-args 2>&1)"

# ---- windows by a loose name over IPC (scripts, a phone over SSH) ----------------------
r() { qs -p /work/shani ipc call shani "$@" 2>/dev/null; }
r windowList | python3 -c "import json,sys; l=json.load(sys.stdin); sys.exit(0 if any(w['title'] == 'Terminal two' for w in l) else 1)" \
    && result window-list-ipc PASS || result window-list-ipc FAIL "$(r windowList | head -c 300)"
out=$(r windowFocus "terminal TWO")
waitfor "d['focusedTitle'] == 'Terminal two'" 3 && result window-focus-by-name PASS "$out" || result window-focus-by-name FAIL "$out / $(q "['focusedTitle']")"
r windowFocus "no-such-window" | grep -q "no window matches" && result window-focus-no-match PASS || result window-focus-no-match FAIL
tw=$(niri msg -j windows | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if w['title'] == 'Terminal two'))")
# to Terminal one's workspace (by number; numbers past it may be the hidden "minimised" one)
one=$(niri msg -j windows | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if w['title'] == 'Terminal one'))")
r windowMove "terminal two" "$(widx "$one")" >/dev/null; sleep 1
[ "$(wsof "$tw")" = "$(wsof "$one")" ] && result window-move-by-name PASS || result window-move-by-name FAIL "on $(wsof "$tw"), wanted $(wsof "$one")"
r swapMonitors | grep -q "needs two monitors" && result swap-monitors-needs-two PASS || result swap-monitors-needs-two FAIL

# ---- the dock's menu: an app's open windows by title, and its own actions (jump list) ----
if [ -f "$A11Y" ]; then
    ipc dockMenu shani-demo; sleep 0.8
    a=$(timeout 20 python3 "$A11Y" find "menu item:^Terminal one$" 2>/dev/null | head -1); b=$(timeout 20 python3 "$A11Y" find "menu item:^Terminal two$" 2>/dev/null | head -1)
    [ -n "$a" ] && [ -n "$b" ] && result dock-menu-windows PASS || result dock-menu-windows FAIL "$(timeout 20 python3 "$A11Y" find "menu item:" 2>&1 | head -8 | tr '\n' ';')"
    shot 26-dock-menu 0.2
    ipc dockMenu org.gnome.Nautilus; sleep 0.8
    a=$(timeout 20 python3 "$A11Y" find "menu item:^New Window$" 2>/dev/null | head -1)
    [ -n "$a" ] && result dock-menu-jump-list PASS || result dock-menu-jump-list FAIL "$(timeout 20 python3 "$A11Y" find "menu item:" 2>&1 | head -8 | tr '\n' ';')"
    ipc closeAll
    waitfor "True" 1; a=$(timeout 20 python3 "$A11Y" find "menu item:^New Window$" 2>/dev/null | head -1)
    [ -z "$a" ] && result dock-menu-closes PASS || result dock-menu-closes FAIL "still shown"
fi

# ---- voice typing: espeak-ng speaks, the mic hears it, whisper types it ---------
# the "microphone" is the speakers' monitor, so what is played is what is heard
pactl set-default-source speakers.monitor
espeak-ng -w /tmp/said.wav "good morning everyone"
ipc launcher ""
ipc osk
sleep 0.5
ipc dictate
waitfor "d['dictation'] == 'recording'" 3 && result dictation-records PASS || result dictation-records FAIL
shot 46-osk-dictating 0.3
paplay /tmp/said.wav
sleep 0.8
ipc dictate
waitfor "d['dictation'] == 'idle' and d['dictated'] != ''" 40 && result dictation-transcribes PASS "heard: $(q "['dictated']")" \
    || result dictation-transcribes FAIL "$(tail -3 /work/out/logs/qs.log)"
waitfor "d['topResult'].endswith(d['dictated'])" 4 && result dictation-types-into-field PASS || result dictation-types-into-field FAIL "$(q "['topResult']")"
ipc osk
ipc closeAll
pactl set-default-source mic 2>/dev/null

# ---- launcher: emoji, and what you use ranks first ------------------------------
ipc launcher ":grinning face"
waitfor "d['topResult'] == 'grinning face'" 4 && result launcher-emoji PASS || result launcher-emoji FAIL "$(q "['topResult']")"
ipc launcher "text edit"
waitfor "d['topResult'] == 'Text Editor'" 3; sleep 0.4
wtype -k Return
sleep 1.5
ipc launcher ""
waitfor "d['topResult'] == 'Text Editor'" 3 && result launcher-ranks-by-use PASS || result launcher-ranks-by-use FAIL "$(q "['topResult']")"
ipc closeAll

# ---- per-app mixer --------------------------------------------------------------
paplay --raw /dev/zero >/dev/null 2>&1 &
PLAY=$!
waitfor "d['players'] >= 1" 5 && result mixer-sees-app-stream PASS || result mixer-sees-app-stream FAIL "$(q "['players']")"
ipc controlCenter audio
shot 34-mixer 0.6
ipc settings
shot 35-settings 0.8
ipc closeAll
kill $PLAY 2>/dev/null
parecord -d speakers.monitor /dev/null >/dev/null 2>&1 &
REC=$!
waitfor "d['micInUse']" 5 && result privacy-mic-in-use PASS || result privacy-mic-in-use FAIL
shot 36-mic-in-use 0.3
kill $REC 2>/dev/null
waitfor "not d['micInUse']" 5 && result privacy-mic-released PASS || result privacy-mic-released FAIL

# ---- focus modes ------------------------------------------------------------
before=$(q "['notifications']"); pops=$(q "['popups']")
ipc focus Work
waitfor "d['focus'] == 'Work'" 3 && result focus-mode-on PASS || result focus-mode-on FAIL
notify-send -a Mail "Lunch?" "held back during Work"
waitfor "d['notifications'] > $before" 3
[ "$(q "['popups']")" -le "$pops" ] && result focus-holds-notifications PASS || result focus-holds-notifications FAIL "$(st)"
notify-send -u critical -a Power "Critical" "always through"
waitfor "d['popups'] >= 1" 3 && result focus-lets-critical-through PASS || result focus-lets-critical-through FAIL
ipc focus Sleep
waitfor "d['focus'] == 'Sleep' and d['nightLightRunning']" 3 && result focus-sleep-warms-screen PASS || result focus-sleep-warms-screen FAIL "$(st)"
ipc focus ""
waitfor "d['focus'] == ''" 3 && result focus-mode-off PASS || result focus-mode-off FAIL
# a schedule covering now turns Work on by itself
from=$(date -d '-5 min' +%H:%M); to=$(date -d '+30 min' +%H:%M); day=$(date +%w)
settings "{\"focusModes\": [{\"name\": \"Work\", \"icon\": \"x-office-document\", \"allow\": [], \"schedule\": {\"days\": [$day], \"from\": \"$from\", \"to\": \"$to\", \"on\": true}}]}"
waitfor "d['focusScheduled'] == 'Work' and d['focus'] == 'Work'" 5 && result focus-schedule-applies PASS || result focus-schedule-applies FAIL "$(q "['focusScheduled']")"
settings '{}'

# ---- hot corners (the action; a nested niri has no pointer to push) -----------
ipc hotCorner overview
waitfor "d['overview']" 3 && result hot-corner-opens-overview PASS || result hot-corner-opens-overview FAIL "$(q "['hotCorner']")"
ipc hotCorner overview
waitfor "not d['overview']" 3

# ---- screen time and the shelf -------------------------------------------------
niri msg action focus-workspace 1
sleep 16
waitfor "d['screenTimeTotal'] >= 15" 3 && result screen-time-counts PASS || result screen-time-counts FAIL "$(q "['screenTimeTotal']")"
mkdir -p /root/Pictures/Screenshots && cp /tmp/frame.png /root/Pictures/Screenshots/Screenshot-test.png
ipc controlCenter ""
waitfor "d['shelf'] >= 1" 4 && result shelf-shows-new-screenshot PASS || result shelf-shows-new-screenshot FAIL
shot 45-sidebar-shelf 2.5
ipc closeAll

# ---- the light theme, and the accent from the wallpaper ------------------------
ipc setting darkMode false
waitfor "sum(int(d['bg'][i:i+2],16) for i in (1,3,5)) > 3*215" 3 && result theme-follows-dark-style PASS || result theme-follows-dark-style FAIL "$(q "['bg']")"
shot 47-light-desktop 0.6
ipc controlCenter ""
shot 48-light-sidebar 2.5
ipc closeAll
ipc setting darkMode true
waitfor "sum(int(d['bg'][i:i+2],16) for i in (1,3,5)) < 3*30" 3
magick -size 1920x1080 gradient:'#ff7a18'-'#ffb347' /tmp/orange.png
settings '{"wallpaperLight": "", "wallpaperDark": "", "wallpaper": "/tmp/orange.png", "accentFromWallpaper": true}'
# an orange wallpaper must give an orange accent: red well above blue
waitfor "int(d['accent'][1:3],16) > int(d['accent'][5:7],16) + 60" 10 && result accent-from-wallpaper PASS "$(q "['accent']")" \
    || result accent-from-wallpaper FAIL "$(q "['accent']")"
shot 49-accent-orange 0.6
# a cold wallpaper must be taken just as faithfully: blue well above red
# (wallpaperDark/Light must be cleared too: their defaults are the bundled pair,
# which override the single wallpaper while the style is dark)
magick -size 1920x1080 gradient:'#0a2a6b'-'#4e87ee' /tmp/blue.png
settings '{"wallpaperLight": "", "wallpaperDark": "", "wallpaper": "/tmp/blue.png", "accentFromWallpaper": true}'
waitfor "int(d['accent'][5:7],16) > int(d['accent'][1:3],16) + 40" 10 && result accent-follows-cold-wall PASS "$(q "['accent']")" \
    || result accent-follows-cold-wall FAIL "$(q "['accent']")"
settings '{}'

# ---- day/night wallpaper -----------------------------------------------------------
settings '{"wallpaperLight": "/tmp/lens-bg.png", "wallpaperDark": "/tmp/orange.png"}'
waitfor "d['wallpaperNow'] == '/tmp/orange.png'" 3 && ipc setting darkMode false \
    && waitfor "d['wallpaperNow'] == '/tmp/lens-bg.png'" 3 && result wallpaper-follows-style PASS || result wallpaper-follows-style FAIL "$(q "['wallpaperNow']")"
ipc setting darkMode true
settings '{}'

# ---- fullscreen holds notifications ---------------------------------------------
niri msg action focus-workspace 1; sleep 0.4
corners() { niri msg -j layers | python3 -c "import json,sys; print(sum(1 for l in json.load(sys.stdin) if l['namespace'] == 'shani-hot-corner'))"; }
cn=$(corners)
niri msg action fullscreen-window
waitfor "d['fullscreen'] and d['quiet']" 4 && result fullscreen-is-quiet PASS || result fullscreen-is-quiet FAIL "$(st)"
p0=$(q "['popups']")
notify-send -a Mail "During the film" "should wait"
sleep 1
[ "$(q "['popups']")" -le "$p0" ] && result fullscreen-holds-notifications PASS || result fullscreen-holds-notifications FAIL
# hot corners step aside over a fullscreen window, unless chosen (Pantheon's option)
c0=$(corners); ipc setting hotCornersInFullscreen true; sleep 0.6; c1=$(corners); ipc setting hotCornersInFullscreen false
[ "$cn" -ge 1 ] && result hot-corners-exist PASS "$cn" || result hot-corners-exist FAIL "no hot-corner surfaces"
[ "$cn" -ge 1 ] && [ "$c0" = 0 ] && [ "$c1" -ge 1 ] && result hot-corners-off-in-fullscreen PASS || result hot-corners-off-in-fullscreen FAIL "normal: $cn, fullscreen: $c0, with the option: $c1"
niri msg action fullscreen-window
waitfor "not d['fullscreen']" 4

# ---- screenshot -> annotate / ask -----------------------------------------------
n0=$(q "['notifications']")
niri msg action screenshot-screen
waitfor "d['lastScreenshot'] != ''" 6 && result screenshot-reaches-shell PASS "$(q "['lastScreenshot']")" || result screenshot-reaches-shell FAIL
waitfor "d['notifications'] > $n0" 4 && result screenshot-offers-actions PASS || result screenshot-offers-actions FAIL
shot 51-screenshot-offer 0.6
# a click on it opens the picture (xdg-open, here a stand-in that writes down what it got)
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > /tmp/opened\n' > /usr/local/bin/xdg-open; chmod +x /usr/local/bin/xdg-open; rm -f /tmp/opened
ipc notificationAct "Screenshot saved" default
i=0; while [ ! -s /tmp/opened ] && [ $i -lt 12 ]; do sleep 0.25; i=$((i+1)); done
[ "$(cat /tmp/opened 2>/dev/null)" = "$(q "['lastScreenshot']")" ] && result screenshot-click-opens PASS || result screenshot-click-opens FAIL "opened: $(cat /tmp/opened 2>&1)"
rm -f /usr/local/bin/xdg-open

# ---- copied pictures in the clipboard history --------------------------------------
wl-copy --type image/png < /tmp/orange.png
sleep 1
ipc launcher "c "
waitfor "d['clipImages'] >= 1 and d['topResult'].startswith('Image')" 6 && result clipboard-image-entry PASS "$(q "['topResult']")" || result clipboard-image-entry FAIL "$(q "['topResult']")"
sleep 1
shot 52-clipboard-image 0.4
ipc closeAll

# ---- this round: live activities, search providers, snooze, summary, tiles --------
ipc timer 1
waitfor "d['islandActivity'].startswith('Focus · ')" 3 && result island-live-activity PASS "$(q "['islandActivity']")" || result island-live-activity FAIL "$(q "['islandActivity']")"
shot 53-island-activity 0.4
ipc timer 0
# an app's own answers (GNOME Calculator's provider): a factorial (3+ characters, as providers are asked), which the
# launcher's calculator leaves to it ...
ipc launcher "10!"
waitfor "'From Calculator' in d['launcherSections']" 12 && result launcher-search-providers PASS || result launcher-search-providers FAIL "$(q "['launcherSections']")"
# ... and a sum the launcher answered itself is not answered twice
ipc launcher "12*12"
sleep 4
[ "$(q "['launcherSections']")" = "['Calculator', 'More']" ] && result launcher-calc-not-twice PASS || result launcher-calc-not-twice FAIL "$(q "['launcherSections']")"
shot 54-launcher-providers 0.4
ipc closeAll
notify-send -a Mail "Snooze me" "back soon"
sleep 0.8
n1=$(q "['notifications']")
ipc snoozeLatest 0
waitfor "d['snoozed'] == 1 and d['notifications'] == $n1 - 1" 3 && result notification-snoozed PASS || result notification-snoozed FAIL "$(st)"
waitfor "d['snoozed'] == 0 and 'Snooze me' in d['notificationSummaries']" 30 && result notification-snooze-returns PASS || result notification-snooze-returns FAIL "$(st)"
ipc summarize
sleep 1.5
grep -q "Summarise these notifications" /work/out/logs/mock.log && result notifications-summary-asks-chronoa PASS || result notifications-summary-asks-chronoa FAIL
settings '{"hiddenTiles": ["lens"], "tileOrder": ["chronoa", "dnd"]}'
ipc controlCenter ""
waitfor "d['tilesShown'][:2] == ['chronoa', 'dnd'] and 'lens' not in d['tilesShown']" 4 && result tiles-reordered-and-hidden PASS || result tiles-reordered-and-hidden FAIL "$(q "['tilesShown']")"
shot 55-sidebar-tiles-mic 2.5
# arranging in place: "Edit tiles" shows the hidden one too; pressing it shows it for good
if [ -f "$A11Y" ]; then
    pr=$(timeout 40 python3 "$A11Y" press "button:^Edit tiles$" 2>&1)
    waitfor "'lens' in d['tilesShown']" 3 && result tiles-edit-shows-hidden PASS || result tiles-edit-shows-hidden FAIL "press: $pr"
    shot 55b-tiles-editing 0.4
    pr=$(timeout 40 python3 "$A11Y" press "check box:^Lens, hidden$" 2>&1)
    waitfor "'lens' not in d['hiddenTiles']" 3 && result tiles-edit-unhides PASS || result tiles-edit-unhides FAIL "press: $pr; hidden $(q "['hiddenTiles']")"
    timeout 40 python3 "$A11Y" press "button:^Done$" >/dev/null 2>&1
    waitfor "'lens' in d['tilesShown']" 3 && result tiles-edit-done-keeps PASS || result tiles-edit-done-keeps FAIL "$(q "['tilesShown']")"
fi
ipc closeAll
settings '{}'

# ---- accessibility ------------------------------------------------------------
ipc controlCenter ""
sleep 1
python3 /work/dev/a11y-tree.py "do not disturb" > /tmp/a11y.txt 2>&1
grep -qi "check box	Do Not Disturb" /tmp/a11y.txt && result a11y-tiles-readable-by-orca PASS "$(head -1 /tmp/a11y.txt)" \
    || result a11y-tiles-readable-by-orca FAIL "$(head -3 /tmp/a11y.txt)"
ipc closeAll
ipc setting largeText true
waitfor "d['fontScale'] == 1.25" 3 && result a11y-large-text PASS || result a11y-large-text FAIL
ipc setting highContrast true
waitfor "d['contrast'] and d['bg'] == '#000000'" 3 && result a11y-high-contrast PASS || result a11y-high-contrast FAIL "$(q "['bg']")"
ipc controlCenter access
shot 56-accessibility 0.8
ipc closeAll
ipc setting largeText false
ipc setting highContrast false
ipc setting monoAudio true
waitfor "d['sinkName'] == 'shani-mono'" 6 && result a11y-mono-audio PASS || result a11y-mono-audio FAIL "$(q "['sinkName']")"
ipc setting monoAudio false
waitfor "d['sinkName'] != 'shani-mono'" 6 && result a11y-mono-audio-off PASS || result a11y-mono-audio-off FAIL

# ---- focus timer, processes, weather ---------------------------------------------
ipc timer 1
waitfor "50 <= d['timerLeft'] <= 60 and d['focus'] == 'Work'" 3 && result timer-starts-work-focus PASS || result timer-starts-work-focus FAIL "$(st)"
ipc timer 0
waitfor "d['timerLeft'] == 0 and d['focus'] == ''" 3 && result timer-stop-ends-focus PASS || result timer-stop-ends-focus FAIL
ipc processes
waitfor "d['processes'] >= 3" 5 && result processes-listed PASS || result processes-listed FAIL
shot 50-processes 0.4
ipc closeAll
if curl -sf --max-time 5 -o /dev/null https://api.open-meteo.com; then
    ipc weather Pune
    waitfor "d['weather'] != ''" 20 && result weather-from-open-meteo PASS "$(q "['weather']")" || result weather-from-open-meteo FAIL
    ipc weather ""
else
    echo "RESULT weather-from-open-meteo SKIP (no network in this container)"
fi

# ---- blur: what is behind a shell surface is blurred, not just shown through -----------
# a sharp checkerboard wallpaper, the windows put away, the Ring (centred: no
# pointer here) over it; a patch of the bare disc (between the hub and the
# slices, no icons) varies far less with blur on than off - squares averaged away
magick -size 1920x1080 pattern:checkerboard -colorspace gray -level 45%,55% /tmp/checker.png     # 15 px squares, black and white
ipc showDesktop; sleep 0.5
spread() { magick "$1" -crop 16x16+984+453 +repage -colorspace gray -format "%[fx:standard_deviation*1000]" info: | cut -d. -f1; }
settings '{"wallpaperLight": "", "wallpaperDark": "", "wallpaper": "/tmp/checker.png", "blur": true}'; sleep 1.5
ipc ring; sleep 0.8; grim /tmp/blur-on.png; ipc closeAll
settings '{"wallpaperLight": "", "wallpaperDark": "", "wallpaper": "/tmp/checker.png", "blur": false}'; sleep 1.5
ipc ring; sleep 0.8; grim /tmp/blur-off.png; ipc closeAll
on=$(spread /tmp/blur-on.png); off=$(spread /tmp/blur-off.png)
[ "${on:-999}" -lt $(( ${off:-0} * 6 / 10 )) ] && result ring-blurs-behind PASS "spread $on with blur, $off without" || result ring-blurs-behind FAIL "spread $on with blur, $off without"
cp /tmp/blur-on.png "$SHOTS/30b-ring-blur.png" 2>/dev/null
settings '{}'
ipc showDesktop; sleep 0.5

# ---- the overview (GNOME's Activities): niri's live view, the shell's search on top ----
niri msg action open-overview
waitfor "d['overview'] and d['overviewSearch']" 3 && result overview-search-shown PASS || result overview-search-shown FAIL "$(q "['overview'], d['overviewSearch']")"
shot 30c-overview 0.4
wtype "calc"
waitfor "d['launcher'] and d['launcherQuery'] == 'calc' and not d['overview']" 4 \
    && result overview-typing-searches PASS || result overview-typing-searches FAIL "$(q "['launcher'], d['launcherQuery'], d['overview']")"
ipc closeAll
niri msg action open-overview; sleep 0.5; wtype -k Escape
waitfor "not d['overview']" 3 && result overview-escape-closes PASS || result overview-escape-closes FAIL
niri msg action close-overview 2>/dev/null

# ---- the Ring (pie menu): by keyboard, since nothing here can move a pointer ----
ipc ring
waitfor "d['ring']" 3 && result ring-opens PASS || result ring-opens FAIL
shot 31-ring 0.4
wtype 8                      # Power: a slice with its own ring
waitfor "d['ringDepth'] == 1" 3 && result ring-opens-sub-ring PASS || result ring-opens-sub-ring FAIL "$(q "['ringDepth']")"
shot 32-ring-sub 0.4
wtype -k Escape
waitfor "d['ringDepth'] == 0 and d['ring']" 3 && result ring-steps-back PASS || result ring-steps-back FAIL
before=$(q "['muted']")
wtype 4; sleep 0.4; wtype 4  # Media -> Mute
waitfor "not d['ring'] and str(d['muted']) != '$before'" 3 && result ring-acts PASS || result ring-acts FAIL "$(st)"
ipc volumeMute

# ---- screen recording ----------------------------------------------------------
# wf-recorder 0.6 gets a 0x0 frame size from a *nested* niri (no GPU here; grim
# still captures), so a real recording is checked on a real output in
# shani-testbed. What is checked here: the tile runs it, and a failure reaches
# the user as a notification instead of a silent nothing.
before=$(q "['notifications']")
ipc record
sleep 3
ipc record
waitfor "not d['recording']" 6
f=$(ls /root/Videos/Recordings/*.mp4 2>/dev/null | head -1)
if [ -n "$f" ] && [ "$(stat -c %s "$f")" -gt 1000 ]; then
    result screen-record-file PASS
elif waitfor "d['notifications'] > $before" 3; then
    result screen-record-failure-is-reported PASS "no frames from nested niri; real output: testbed"
else
    result screen-record-failure-is-reported FAIL "neither a file nor a notice"
fi

# ---- Lens: select a region, read it, ask about it --------------------------------
magick -size 1920x1080 xc:'#0b0d12' -fill '#e8eef5' -font DejaVu-Sans -pointsize 84 \
    -gravity center -annotate 0 'SHANI LENS READS THIS' /tmp/lens-bg.png
settings '{"wallpaperLight": "", "wallpaperDark": "", "wallpaper": "/tmp/lens-bg.png"}'
waitfor "d['wallpaper'] == '/tmp/lens-bg.png'" 3 && result wallpaper-follows-setting PASS || result wallpaper-follows-setting FAIL
niri msg action focus-workspace 3
# an earlier step may have left a window here; it would cover the text
for id in $(niri msg -j windows | python3 -c "import json,sys,subprocess; sp=json.loads(subprocess.run(['niri','msg','-j','workspaces'],capture_output=True,text=True).stdout); cur=[s['id'] for s in sp if s['is_focused']][0]; print(' '.join(str(w['id']) for w in json.load(sys.stdin) if w['workspace_id']==cur))"); do
    niri msg action move-window-to-workspace --window-id "$id" --focus false 1
done
sleep 1.5
ipc lensRegion "260,460 1400x160"
waitfor "d['lens'] == 'ready'" 15 && st | python3 -c "import json,sys; t=json.load(sys.stdin)['lensText']; sys.exit(0 if 'SHANI LENS READS THIS' in t.upper() else 1)" \
    && result lens-reads-text PASS || result lens-reads-text FAIL "$(q "['lensText']")"
shot 28-lens 0.4
wtype "what does this say?" -k Return
waitfor "d['lens'] == 'idle'" 4 && grep -q "look_at_image: /run/user/0/shani-lens-" /work/out/logs/mock.log \
    && grep -q "SHANI LENS READS THIS" /work/out/logs/mock.log \
    && result lens-asks-chronoa-with-image PASS || result lens-asks-chronoa-with-image FAIL "$(tail -3 /work/out/logs/mock.log)"
niri msg action focus-workspace 1

# ---- smart copy: the Island offers one next step --------------------------------
ipc smartCopy "https://shani.dev/download"
waitfor "d['smart'].startswith('Open shani.dev') and d['islandActivity'] == d['smart']" 3 \
    && result smart-link-on-island PASS || result smart-link-on-island FAIL "$(q "['smart']")"
shot 60-smart-island 0.3
printf 'Traceback (most recent call last):\n  File "x.py"\nValueError: no' | wl-copy
waitfor "d['smart'].startswith('Ask Chronoa')" 3 \
    && result smart-copied-error PASS || result smart-copied-error FAIL "clipboard change not seen: $(q "['smart']")"
ipc smartCopy "शनि ओएस मराठी"
waitfor "d['smart'].startswith('Translate')" 3 && result smart-translate-script PASS || result smart-translate-script FAIL "$(q "['smart']")"
# translated here, by the local model (a stand-in), shown in a notification - never a web page
rm -f /tmp/translate-down
ipc smartRun
waitfor "'Translation' in d['notificationSummaries']" 5 && grep -q "TRANSLATED(शनि ओएस मराठी)" "${XDG_RUNTIME_DIR:-/tmp}/shani-translation" \
    && result smart-translate-local PASS || result smart-translate-local FAIL "$(q "['notificationSummaries']")"
touch /tmp/translate-down
ipc smartCopy "शनि ओएस मराठी"; ipc smartRun
waitfor "'Could not translate' in d['notificationSummaries']" 5 && result smart-translate-no-model-says-so PASS || result smart-translate-no-model-says-so FAIL "$(q "['notificationSummaries']")"
rm -f /tmp/translate-down
ipc smartCopy "plain words"
waitfor "d['smart'] == ''" 3 && result smart-quiet-on-plain-text PASS || result smart-quiet-on-plain-text FAIL "$(q "['smart']")"

# ---- select to speak: the primary selection is read aloud -----------------------
printf 'shani reads this aloud' | wl-copy --primary
ipc readAloud
waitfor "d['spoken'] == 'shani reads this aloud'" 4 && result read-aloud-selection PASS || result read-aloud-selection FAIL "$(q "['spoken']")"

# ---- live captions: what plays is written out -------------------------------------
espeak-ng -w /tmp/cap.wav "the weather is lovely today"
ipc captions
waitfor "d['captions']" 3 && result captions-on PASS || result captions-on FAIL
sleep 0.5
paplay /tmp/cap.wav; paplay /tmp/cap.wav; paplay /tmp/cap.wav
waitfor "'lovely' in d['captionText'].lower()" 30 && result captions-transcribe-playback PASS "$(q "['captionText']")" \
    || result captions-transcribe-playback FAIL "$(q "['captionText']")"
shot 61-captions 0.2
ipc captions
waitfor "not d['captions']" 3 && result captions-off PASS || result captions-off FAIL

# ---- live transcribe: the mic (here the speakers' monitor, see voice typing), saved
rm -rf /root/Documents/Transcripts
ipc transcribe
waitfor "d['captions'] and d['captionSource'] == 'mic'" 3 && result transcribe-on PASS || result transcribe-on FAIL "$(st)"
sleep 0.5
paplay /tmp/cap.wav; paplay /tmp/cap.wav
waitfor "'lovely' in d['captionText'].lower()" 30 && result transcribe-hears-mic PASS "$(q "['captionText']")" \
    || result transcribe-hears-mic FAIL "$(q "['captionText']")"
shot 66-transcribe 0.2
grep -qi lovely /root/Documents/Transcripts/*.txt 2>/dev/null && result transcribe-saved PASS || result transcribe-saved FAIL "$(ls -R /root/Documents 2>&1 | head -5)"
ipc captions
waitfor "d['captions'] and d['captionSource'] == 'speakers'" 4 && result captions-switch-source PASS || result captions-switch-source FAIL "$(st)"
ipc captions
waitfor "not d['captions']" 3

# ---- flash and speak alerts ---------------------------------------------------------
settings '{"flashAlerts": true, "speakNotifications": true}'
f0=$(q "['flashes']")
notify-send -a Calendar "Standup in five" "room 2"
waitfor "d['flashes'] > $f0" 3 && result flash-alert PASS || result flash-alert FAIL "$(q "['flashes']")"
shot 67-flash 0.05
waitfor "d['spoken'] == 'Calendar: Standup in five'" 3 && result speak-notification PASS || result speak-notification FAIL "$(q "['spoken']")"
ipc dnd
waitfor "d['dnd']" 3; sleep 1       # on, and the alert before it done flashing
f1=$(q "['flashes']")
notify-send -a Calendar "Held back" "dnd"
sleep 1
# held back: it did not flash (a critical one from elsewhere in the run may, as it should)
[ "$(q "['lastFlash']")" != "Held back" ] && result flash-respects-dnd PASS || result flash-respects-dnd FAIL "$(q "['flashes']") vs $f1, last: $(q "['lastFlash']")"
ipc dnd
settings '{}'

# ---- Bluetooth pairing: the agent's questions are answered in the shell -------------
rm -f /tmp/bt-answers
echo '{"ask": "confirm", "id": 7, "device": "Pixel 8", "passkey": "012345"}' > /tmp/bt-ask
waitfor "d['btAsk'] == 'confirm:Pixel 8'" 4 && result bt-pair-asks PASS || result bt-pair-asks FAIL "$(q "['btAsk']")"
shot 68-bt-pair 0.4
ipc btAnswer true ""
waitfor "d['btAsk'] == ''" 3
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s /tmp/bt-answers ] && break; sleep 0.2; done   # the stand-in polls every 0.3 s
grep -q '"id": 7, "ok": true' /tmp/bt-answers 2>/dev/null || grep -q '"id":7,"ok":true' /tmp/bt-answers \
    && result bt-pair-answer-reaches-agent PASS || result bt-pair-answer-reaches-agent FAIL "$(cat /tmp/bt-answers 2>&1)"
echo '{"ask": "pin", "id": 8, "device": "Old Keyboard"}' > /tmp/bt-ask
waitfor "d['btAsk'] == 'pin:Old Keyboard'" 4
sleep 0.6     # the dialog takes the keyboard once it maps
wtype "0000" -k Return
waitfor "d['btAsk'] == ''" 3 && grep -q '"value":"0000"' /tmp/bt-answers \
    && result bt-pin-typed PASS || result bt-pin-typed FAIL "$(cat /tmp/bt-answers 2>&1)"
echo '{"show": "passkey", "device": "K380", "passkey": "045123", "entered": 0}' > /tmp/bt-ask
waitfor "d['btShow'] == 'K380'" 4 && result bt-passkey-shown PASS || result bt-passkey-shown FAIL
shot 69-bt-passkey 0.3
echo '{"cancel": true}' > /tmp/bt-ask
waitfor "d['btShow'] == ''" 3 && result bt-cancel-closes PASS || result bt-cancel-closes FAIL

# ---- a file over Bluetooth: asked about as a notification; arrival announced -----------
echo '{"ask": "push", "id": 3, "device": "Pixel 8", "file": "IMG_2041.jpg", "size": 2381904}' > /tmp/obex-ask
waitfor "'Pixel 8 is sending a file' in d['notificationSummaries']" 4 && result bluetooth-push-asks PASS || result bluetooth-push-asks FAIL "$(q "['notificationSummaries']")"
shot 90-bluetooth-push 0.4
echo '{"received": "/root/Downloads/IMG_2041.jpg"}' > /tmp/obex-ask
waitfor "d['bluetoothReceived'] == 1 and 'File received' in d['notificationSummaries']" 4 && result bluetooth-received-announced PASS || result bluetooth-received-announced FAIL

# ---- notification card: avatar letter, picture with badge, actions row ----------------
notify-send -a Messages -i mail-unread -h string:image-path:/tmp/frame.png -A reply=Reply -A call=Call "Asha" "Are we still on for 6?" &
notify-send -a "Build bot" "Pipeline passed" "shani-shell · main · 4 min"
shot 70-notification-cards 1.0

# ---- settings categories: input, default apps, language, about -----------------------
ipc settings
waitfor "d['settingsOpen']" 3
shot 71-settings-categories 0.6
# input: the shell writes niri's include, niri reloads it
ipc settingsCategory input
waitfor "d['settingsCat'] == 'input'" 3
shot 72-settings-input 0.6
settings '{"tapToClick": false, "keyRepeatRate": 45, "touchpadSpeed": 0.4}'
sleep 1
f=/root/.config/niri/shani-input.kdl
grep -q 'repeat-rate 45' $f && ! grep -q '^        tap$' $f && grep -q 'accel-speed 0.40' $f \
    && result input-settings-written PASS || result input-settings-written FAIL "$(cat $f 2>&1)"
niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 && result input-include-valid PASS || result input-include-valid FAIL "$(niri validate -c /work/dev/niri/session.kdl 2>&1 | tail -3)"
settings '{}'
# keyboard layouts: the shell writes them, niri reloads the include and has both
settings '{"kbLayouts": ["us", "in+marathi"], "kbSwitch": "grp:alt_shift_toggle"}'
waitfor "True" 1
for i in 1 2 3 4 5 6; do niri msg -j keyboard-layouts 2>/dev/null | grep -q Marathi && break; sleep 0.5; done
niri msg -j keyboard-layouts 2>/dev/null | grep -q Marathi && grep -q 'options "grp:alt_shift_toggle"' $f \
    && result keyboard-layouts-reach-niri PASS "$(niri msg -j keyboard-layouts | python3 -c 'import json,sys; print(json.load(sys.stdin)["names"])')" \
    || result keyboard-layouts-reach-niri FAIL "$(cat $f; niri msg keyboard-layouts 2>&1)"
waitfor "'Marathi' in d['layout'] or True" 1
shot 76-settings-layouts 0.4
settings '{}'
for i in 1 2 3 4 5 6; do niri msg -j keyboard-layouts 2>/dev/null | grep -q Marathi || break; sleep 0.5; done
niri msg -j keyboard-layouts 2>/dev/null | grep -q Marathi && result keyboard-layouts-removed FAIL || result keyboard-layouts-removed PASS

# ---- per-app window rules: the shell writes the include, niri floats foot -----
settings '{"windowRules": [{"app": "foot", "float": true}]}'
sleep 1
f=/root/.config/niri/shani-windows.kdl
grep -Fq 'match app-id="^foot$"' $f && grep -q 'open-floating true' $f \
    && result window-rules-written PASS || result window-rules-written FAIL "$(cat $f 2>&1)"
niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 && result window-include-valid PASS || result window-include-valid FAIL "$(niri validate -c /work/dev/niri/session.kdl 2>&1 | tail -3)"
foot >/dev/null 2>&1 &
i=0; float=""
while [ $i -lt 12 ]; do
    sleep 0.5
    float=$(niri msg -j windows 2>/dev/null | python3 -c 'import json,sys; w=json.load(sys.stdin); print(any(x["app_id"]=="foot" and x["is_floating"] for x in w))' 2>/dev/null)
    [ "$float" = "True" ] && break
    i=$((i+1))
done
[ "$float" = "True" ] && result window-rule-foot-floats PASS || result window-rule-foot-floats FAIL "$(niri msg -j windows 2>&1 | head -c 200)"
settings '{}'

# ---- world clocks on the calendar ---------------------------------------------
settings '{"worldClocks": ["Asia/Tokyo"]}'
ipc toggleControlCenter
waitfor "len(d['worldClocks']) and d['worldClocks'][0]['city'] == 'Tokyo' and d['worldClocks'][0]['time']" 8 \
    && result world-clocks-shown PASS "$(q "['worldClocks']")" || result world-clocks-shown FAIL "$(q "['worldClocks']")"
ipc controlCenter ""
settings '{}'

# ---- per-app audio routing, balance, reduce transparency, storage, switch user ----
hp=$(pactl load-module module-null-sink sink_name=headphones sink_properties=device.description=headphones 2>/dev/null)
python3 -c "
import wave, struct, math
w=wave.open('/tmp/sine.wav','w')
w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
for i in range(44100 * 8):
    w.writeframes(struct.pack('<h', int(3000*math.sin(2*math.pi*440*i/44100))))
w.close()
" 2>/dev/null
pw-play /tmp/sine.wav >/dev/null 2>&1 & play=$!
# an app handed to another device: the shell moves its stream (pactl), the graph shows it there
waitfor "len(d['streams']) >= 1" 6 || true
node=$(st | python3 -c "import json,sys; s=json.load(sys.stdin)['streams']; m=[x for x in s if 'play' in x['name'].lower()] or s; print(m[0]['node'] if m else '')" 2>/dev/null)
[ -n "$node" ] && ipc playerSink "$node" headphones
waitfor "any(s.get('sink') == 'headphones' for s in d['streams'])" 6 && result player-route-headphones PASS || result player-route-headphones FAIL "node $node: $(q "['streams']") / $(pactl list sink-inputs short 2>&1 | tr '\t\n' ' ;')"
kill $play 2>/dev/null
# balance: the quieter side loses a share, the louder keeps the volume; centred, both are even again
vols() { pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | tr -d % | head -2 | tr '\n' ' '; }
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.50; sleep 0.5
settings '{"audioBalance": -40}'
set -- $(vols); [ "${1:-0}" = 50 ] && [ "${2:-0}" = 30 ] && result balance-applied PASS "L $1 R $2" || result balance-applied FAIL "L ${1:-?} R ${2:-?}"
settings '{}'
set -- $(vols); [ "${1:-0}" = 50 ] && [ "${2:-0}" = 50 ] && result balance-centred-again PASS || result balance-centred-again FAIL "L ${1:-?} R ${2:-?}"
settings '{"reduceTransparency": true}'
waitfor "d['reduceTransparency']" 3 && result reduce-transparency-on PASS || result reduce-transparency-on FAIL "$(q "['reduceTransparency']")"
settings '{"reduceTransparency": false}'
ipc storageScan
sleep 4
waitfor "len(d.get('storageSizes',[])) > 0" 8 && result storage-scanned PASS || result storage-scanned FAIL "$(q "['storageSizes']")"
[ -n "$hp" ] && pactl unload-module "$hp"     # this one only: the others are the session's speakers

ipc settingsCategory account
sleep 1.2
shot 77-settings-account 0.3
# default apps: a fake app that opens text
mkdir -p /root/.local/share/applications
printf '[Desktop Entry]\nType=Application\nName=Scribble\nExec=true %%f\nMimeType=text/plain;\n' > /root/.local/share/applications/scribble.desktop
ipc settingsCategory apps
sleep 1.5
shot 73-settings-apps 0.3
# what the page runs to set one (gio mime), and what an app then gets from GLib
gio mime text/plain scribble.desktop >/dev/null
LC_ALL=C gio mime text/plain | grep -q 'Default application for .*: scribble.desktop' && grep -q 'text/plain=scribble.desktop' /root/.config/mimeapps.list \
    && result default-apps-gio-mime PASS || result default-apps-gio-mime FAIL "$(LC_ALL=C gio mime text/plain 2>&1 | head -2)"
ipc settingsCategory time
sleep 1.5
shot 74-settings-date-language 0.3
ipc settingsCategory about
sleep 1.5
shot 75-settings-about 0.3
ipc closeAll

# ---- the launcher finds settings by what people call them --------------------------
for pair in "timezone:Date & language" "time zone:Date & language" "add user:Users" "password:Your account" "default browser:Default apps" "touchpad:Keyboard & input" "hostname:About this computer"; do
    ipc launcher "${pair%%:*}"
    waitfor "d['topResult'] == '${pair#*:}'" 4 && result "launcher-finds-$(echo ${pair%%:*} | tr ' ' -)" PASS || result "launcher-finds-$(echo ${pair%%:*} | tr ' ' -)" FAIL "$(q "['topResult']")"
done
ipc launcher "timezone"; waitfor "d['topResult'] == 'Date & language'" 3
sleep 0.4      # the field set over IPC, not typed: give the layer the keyboard first
wtype -k Return
waitfor "d['settingsOpen'] and d['settingsCat'] == 'time'" 3 && result launcher-opens-settings-category PASS || result launcher-opens-settings-category FAIL "$(st)"
ipc closeAll

# ---- per-app notifications: no pop-ups for one app, one app through DND -------------
notify-send -a Chatty "first" "seen once"
sleep 1
settings '{"notifApps": ["Chatty", "Pager"], "silentApps": ["Chatty"], "dndAllowedApps": ["Pager"]}'
n0=$(q "['notifications']")
notify-send -a Chatty "Chatty again" "should be quiet"
waitfor "d['notifications'] > $n0" 3
q "['popupSummaries']" | grep -q 'Chatty again' && result silent-app-no-popup FAIL || result silent-app-no-popup PASS
q "['notificationSummaries']" | grep -q 'Chatty again' && result silent-app-kept-in-history PASS || result silent-app-kept-in-history FAIL
ipc dnd
notify-send -a Pager "Paged" "through DND"
notify-send -a Other "Held" "by DND"
waitfor "'Paged' in d['popupSummaries']" 3 && result dnd-allowed-app-comes-through PASS || result dnd-allowed-app-comes-through FAIL "$(q "['popupSummaries']")"
q "['popupSummaries']" | grep -q "'Held'\|\"Held\"" && result dnd-holds-others FAIL || result dnd-holds-others PASS
ipc dnd
settings '{}'

# ---- night light on a schedule: what wlsunset is asked for ----------------------------
settings '{"nightLightSchedule": "custom", "nightLightFrom": "20:30", "nightLightTo": "06:45"}'
waitfor "d['nightLightMode'] == 'custom' and '-S 06:45 -s 20:30' in d['nightLightCommand']" 3 \
    && result night-light-custom-hours PASS || result night-light-custom-hours FAIL "$(q "['nightLightCommand']")"
settings '{"nightLightSchedule": "sunset", "weatherLat": 18.52, "weatherLon": 73.86}'
waitfor "d['nightLightMode'] == 'sunset' and '-l 18.52 -L 73.86' in d['nightLightCommand']" 3 \
    && result night-light-sunset-by-location PASS || result night-light-sunset-by-location FAIL "$(q "['nightLightCommand']")"
settings '{}'

# ---- icons, fonts and cursor: apps through gsettings, niri's pointer, the shell's font --
ipc settingsCategory personal
settings '{"iconTheme": "Pop", "cursorTheme": "Pop", "cursorSize": 32, "uiFont": "DejaVu Sans", "uiFontSize": 12, "monoFont": "DejaVu Sans Mono", "monoFontSize": 13}'
sleep 1.5
g() { gsettings get org.gnome.desktop.interface "$1"; }
[ "$(g icon-theme)" = "'Pop'" ] && [ "$(g cursor-theme)" = "'Pop'" ] && [ "$(g cursor-size)" = 32 ] \
    && [ "$(g font-name)" = "'DejaVu Sans 12'" ] && [ "$(g monospace-font-name)" = "'DejaVu Sans Mono 13'" ] \
    && result look-reaches-apps PASS || result look-reaches-apps FAIL "$(g icon-theme) $(g cursor-theme) $(g cursor-size) $(g font-name) $(g monospace-font-name)"
grep -q 'xcursor-theme "Pop"' /root/.config/niri/shani-input.kdl && grep -q 'xcursor-size 32' /root/.config/niri/shani-input.kdl \
    && niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 && result cursor-reaches-niri PASS || result cursor-reaches-niri FAIL
waitfor "d['iconsNeedRestart']" 3 && result icon-theme-offers-restart PASS || result icon-theme-offers-restart FAIL
shot 78-settings-look 0.6
settings '{}'

# ---- sound effects: measured at the real output -----------------------------------
tone() { python3 -c "import math,wave,array,sys; f=float(sys.argv[1]); w=wave.open(sys.argv[2],'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000); w.writeframes(array.array('h',[int(8000*math.sin(2*math.pi*f*i/48000)) for i in range(48000*2) for _ in (0,1)]).tobytes())" "$1" "$2"; }
level() {   # play $1 into the default output, record what reaches the speakers, print its RMS
    timeout 2.6 parecord -d speakers.monitor --rate 48000 --channels 1 --format s16le --raw /tmp/rec.raw 2>/dev/null &
    sleep 0.3; paplay "$1"; wait
    python3 -c "import array,math; a=array.array('h',open('/tmp/rec.raw','rb').read()); a=a[len(a)//4:len(a)*3//4]; print(int(math.sqrt(sum(x*x for x in a)/max(1,len(a)))))"
}
tone 1000 /tmp/t1k.wav; tone 4000 /tmp/t4k.wav
pactl set-default-sink speakers; sleep 0.5
settings '{"fxEnabled": true}'
waitfor "d['fxRunning'] and d['sinkName'] == 'effect_input.shani' and d['fxTarget'] == 'speakers'" 8 \
    && result fx-becomes-the-output PASS || result fx-becomes-the-output FAIL "$(q "['fxRunning'], d['sinkName'], d['fxTarget'], d['fxError']")"
shot 79-settings-sound 0.2
flat1k=$(level /tmp/t1k.wav); flat4k=$(level /tmp/t4k.wav)
settings '{"fxEnabled": true, "fxEq": [0, 0, 0, 0, 0, -12, 0, 0, 0, 0]}'
sleep 2; waitfor "d['fxRunning'] and d['sinkName'] == 'effect_input.shani'" 6
cut1k=$(level /tmp/t1k.wav); cut4k=$(level /tmp/t4k.wav)
python3 -c "import sys; f1,f4,c1,c4=map(int,sys.argv[1:]); sys.exit(0 if f1>50 and c1<0.4*f1 and c4>0.7*f4 else 1)" "$flat1k" "$flat4k" "$cut1k" "$cut4k" \
    && result fx-eq-cuts-its-band PASS "1 kHz $flat1k→$cut1k, 4 kHz $flat4k→$cut4k" || result fx-eq-cuts-its-band FAIL "1 kHz $flat1k→$cut1k, 4 kHz $flat4k→$cut4k $(q "['fxError']")"
settings '{}'
waitfor "not d['fx'] and d['sinkName'] == 'speakers'" 5 && result fx-off-restores-output PASS || result fx-off-restores-output FAIL "$(q "['sinkName']")"

# loudness levelling: a tone ten times quieter comes out far less than ten times quieter
qtone() { python3 -c "import math,wave,array,sys; a=float(sys.argv[1]); w=wave.open(sys.argv[2],'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000); w.writeframes(array.array('h',[int(a*math.sin(2*math.pi*1000*i/48000)) for i in range(48000*5) for _ in (0,1)]).tobytes())" "$1" "$2"; }
qlevel() {
    timeout 5.6 parecord -d speakers.monitor --rate 48000 --channels 1 --format s16le --raw /tmp/rec.raw 2>/dev/null &
    sleep 0.3; paplay "$1"; wait
    python3 -c "import array,math; a=array.array('h',open('/tmp/rec.raw','rb').read()); a=a[len(a)*3//5:len(a)*4//5]; print(int(math.sqrt(sum(x*x for x in a)/max(1,len(a)))))"
}
qtone 600 /tmp/quiet.wav; qtone 6000 /tmp/loud.wav
settings '{"fxEnabled": true, "fxLoudness": true}'
waitfor "d['fxRunning'] and d['sinkName'] == 'effect_input.shani'" 8 && result fx-loudness-graph-loads PASS || result fx-loudness-graph-loads FAIL "$(q "['fxError']")"
lq=$(qlevel /tmp/quiet.wav); ll=$(qlevel /tmp/loud.wav)
python3 -c "import sys; q,l=map(int,sys.argv[1:]); sys.exit(0 if q>0 and l/q < 4 else 1)" "$lq" "$ll" \
    && result fx-loudness-evens-out PASS "quiet $lq, loud $ll (10x apart going in)" || result fx-loudness-evens-out FAIL "quiet $lq, loud $ll"
settings '{}'
waitfor "d['sinkName'] == 'speakers'" 5

# night mode (SC4 compressor): the same two tones come out much closer together,
# and the chain loads with the LADSPA plugin in it
settings '{"fxEnabled": true, "fxCompress": "night"}'
waitfor "d['fxRunning'] and d['sinkName'] == 'effect_input.shani'" 8 && result fx-compressor-graph-loads PASS || result fx-compressor-graph-loads FAIL "$(q "['fxError']")"
cq=$(qlevel /tmp/quiet.wav); cl=$(qlevel /tmp/loud.wav)
python3 -c "import sys; q,l=map(int,sys.argv[1:]); sys.exit(0 if q>0 and l/q < 5 else 1)" "$cq" "$cl" \
    && result fx-night-mode-compresses PASS "quiet $cq, loud $cl (10x apart going in)" || result fx-night-mode-compresses FAIL "quiet $cq, loud $cl"
settings '{}'
waitfor "d['sinkName'] == 'speakers'" 5

# microphone noise suppression: the cleaned-up source becomes the default, and goes
src0=$(q "['sourceName']")
settings '{"micNoise": true}'
waitfor "d['micRunning'] and d['sourceName'] == 'effect_output.shani_mic'" 8 && result mic-noise-suppression-on PASS || result mic-noise-suppression-on FAIL "$(q "['sourceName'], d['micError']")"
settings '{}'
waitfor "d['sourceName'] == '$src0'" 5 && result mic-noise-suppression-off PASS || result mic-noise-suppression-off FAIL "$(q "['sourceName']")"

# ---- displays: niri applies the shell's output block; kept, or reverted by itself ------
ipc settingsCategory displays
ipc display winit scale 1.5
waitfor "d['displayPending'] and 'winit:1.5@' in d['displays']" 5 && result display-change-applies PASS "$(q "['displays']")" || result display-change-applies FAIL "$(q "['displays']") $(cat /root/.config/niri/shani-input.kdl | grep -A3 output)"
shot 85-display-confirm 0.3
ipc displayKeep
sleep 1
waitfor "not d['displayPending'] and 'winit:1.5@' in d['displays']" 3 && grep -q 'scale 1.5' /root/.config/niri/shani-input.kdl \
    && result display-kept PASS || result display-kept FAIL "$(q "['displays']")"
ipc display winit scale 1.25
waitfor "'winit:1.25@' in d['displays']" 5
waitfor "not d['displayPending'] and 'winit:1.5@' in d['displays']" 20 && result display-reverts-unanswered PASS || result display-reverts-unanswered FAIL "$(q "['displays']")"
ipc display winit off true
sleep 1
q "['displayPending']" | grep -q False && q "['displays']" | grep -q 'winit:1' && result last-screen-stays-on PASS || result last-screen-stays-on FAIL "$(st)"
shot 86-settings-displays 0.3
settings '{}'
waitfor "'winit:1@' in d['displays']" 5

# ---- camera: a photo through the shell's still path (fake cam), video failure reported ----
waitfor "d['cameras'] == 1" 12 && result camera-listed PASS || result camera-listed FAIL "$(q "['cameras']")"
ipc photo
waitfor "d['cameraPhase'] == 'counting'" 2 && result photo-counts-down PASS || result photo-counts-down FAIL "$(q "['cameraPhase']")"
shot 87-photo-countdown 0.2
waitfor "d['cameraPhase'] == 'idle' and d['cameraLast'].endswith('.png')" 10
f=$(q "['cameraLast']")
python3 -c "import sys,struct; b=open(sys.argv[1],'rb').read(); sys.exit(0 if b[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', b[16:24])==(64,48) else 1)" "$f" 2>/dev/null \
    && result photo-saved-as-png PASS "$f" || result photo-saved-as-png FAIL "$f $(ls -la "$(dirname "$f")" 2>&1 | tail -2)"
waitfor "'Photo taken' in d['notificationSummaries']" 4 && result photo-notifies PASS || result photo-notifies FAIL
ipc video
waitfor "d['cameraPhase'] == 'idle' and 'Video stopped' in d['notificationSummaries']" 12 \
    && result video-without-camera-node-reported PASS || result video-without-camera-node-reported FAIL "$(q "['cameraPhase']")"

# ---- media keys reach the playing player; notifications chime -----------------------
python3 /work/dev/fake-mpris.py "Test Song" "Test Artist" >/dev/null 2>&1 &
MPRIS=$!
waitfor "d['mediaPlaying']" 5
ipc media play-pause
waitfor "not d['mediaPlaying']" 3 && result media-key-pauses PASS || result media-key-pauses FAIL
ipc media play-pause
waitfor "d['mediaPlaying']" 3 && result media-key-plays PASS || result media-key-plays FAIL
# two players: the card's switch picks the one followed, and the media keys go to it
FAKE_MPRIS_NAME="Second Player" FAKE_MPRIS_BUS=second python3 /work/dev/fake-mpris.py "Other Song" "Other" >/dev/null 2>&1 &
MPRIS2=$!
waitfor "True" 1; sleep 1.5
before=$(q "['mediaPlayer']")
ipc nextPlayer
waitfor "d['mediaPlayer'] not in ('', '$before')" 3 && grep -q '"preferredPlayer"' "$SHANI_SHELL_SETTINGS" \
    && result media-player-switch PASS "$before -> $(q "['mediaPlayer']")" || result media-player-switch FAIL "$before -> $(q "['mediaPlayer']")"
kill $MPRIS2 2>/dev/null
waitfor "d['mediaPlayer'] == 'Shani Player'" 4 && result media-player-gone-falls-back PASS || result media-player-gone-falls-back FAIL "$(q "['mediaPlayer']")"
settings '{}'
# lyrics (switched on): looked up while the card shows, the line at the position
mkdir -p /tmp/lrc/api; printf '[{"trackName":"Test Song","syncedLyrics":"[00:00.00] first line\\n[00:01.50] second line"}]' > /tmp/lrc/api/search
(cd /tmp/lrc && python3 -c "
import http.server, socketserver
class H(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, p): return super().translate_path(p.split('?')[0])
    def log_message(self, *a): pass
socketserver.TCPServer(('127.0.0.1', 8799), H).serve_forever()" >/dev/null 2>&1 &)
settings '{"lyrics": true}'
ipc toggleControlCenter
waitfor "d['lyricsLines'] == 2" 8 && result lyrics-fetched PASS || result lyrics-fetched FAIL "$(q "['lyricsLines']")"
ipc closeAll
settings '{}'
kill $MPRIS 2>/dev/null
s0=$(q "['notifSounds']")
notify-send -a Chime "Ding" "a sound"
waitfor "d['notifSounds'] > $s0" 3 && result notification-sound PASS || result notification-sound FAIL
settings '{"notifSound": false}'
s1=$(q "['notifSounds']")
notify-send -a Chime "Quiet" "no sound"
sleep 1
[ "$(q "['notifSounds']")" = "$s1" ] && result notification-sound-off PASS || result notification-sound-off FAIL
settings '{}'

# ---- windows, special keys, your own shortcut: all through niri's include ---------------
f=/root/.config/niri/shani-input.kdl
settings '{"winGaps": 6, "winFocusFollowsMouse": false, "winAnimations": false, "kbCompose": "ralt", "kbCaps": "caps:escape", "customBinds": [{"key": "Mod+Alt+J", "title": "test bind", "command": "touch /tmp/bind-ran"}]}'
sleep 1.5
grep -q 'gaps 6' $f && ! grep -q 'focus-follows-mouse' $f && grep -q 'animations' $f && grep -q 'options "compose:ralt,caps:escape"' $f \
    && niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 && result windows-and-keys-reach-niri PASS || result windows-and-keys-reach-niri FAIL "$(niri validate -c /work/dev/niri/session.kdl 2>&1 | tail -2; cat $f)"
# niri does not run binds for virtual-keyboard input (wtype), so the press itself
# is a real-keyboard check; here: the bind as niri will load it
grep -q 'Mod+Alt+J hotkey-overlay-title="test bind" { spawn "sh" "-c" "touch /tmp/bind-ran"; }' $f \
    && result own-shortcut-in-niri PASS || result own-shortcut-in-niri FAIL "$(grep -A2 '^binds' $f)"
ipc settingsCategory input
shot 88-settings-shortcuts 0.8
settings '{}'

# ---- trash emptied by age; proxy reaches GNOME settings and the environment -----------
T=/root/.local/share/Trash; mkdir -p $T/files $T/info
for n in old new; do echo x > $T/files/$n.txt; printf '[Trash Info]\nPath=/root/%s.txt\nDeletionDate=2026-01-01T00:00:00\n' $n > $T/info/$n.txt.trashinfo; done
touch -d '40 days ago' $T/info/old.txt.trashinfo
settings '{"trashDays": 30}'
waitfor "d['trashEmptied'] == 1" 5 && [ ! -e $T/files/old.txt ] && [ -e $T/files/new.txt ] && result trash-emptied-by-age PASS || result trash-emptied-by-age FAIL "$(ls $T/files)"
settings '{"proxyMode": "manual", "proxyHttp": "proxy.lan:3128"}'
sleep 1.5
[ "$(gsettings get org.gnome.system.proxy mode)" = "'manual'" ] && [ "$(gsettings get org.gnome.system.proxy.http host)" = "'proxy.lan'" ] \
    && [ "$(gsettings get org.gnome.system.proxy.http port)" = 3128 ] && grep -q 'http_proxy=http://proxy.lan:3128/' /root/.config/environment.d/50-shani-proxy.conf \
    && result proxy-applied PASS || result proxy-applied FAIL "$(gsettings get org.gnome.system.proxy mode) $(gsettings get org.gnome.system.proxy.http host)"
settings '{}'
sleep 1.5
[ "$(gsettings get org.gnome.system.proxy mode)" = "'none'" ] && [ ! -e /root/.config/environment.d/50-shani-proxy.conf ] && result proxy-off PASS || result proxy-off FAIL
ipc settingsCategory privacy
shot 89-settings-privacy 0.6

# ---- the volume click ------------------------------------------------------------------
v0=$(q "['systemSoundsPlayed']")
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.30
waitfor "d['systemSoundsPlayed'] > $v0" 3 && result volume-click PASS || result volume-click FAIL
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.35

# ---- defaults: the dark wallpaper and the look apps are given ------------------------
settings '{}'
waitfor "d['wallpaperNow'] == '/usr/share/backgrounds/shani/shani-dark.jpg'" 4 && result default-wallpaper-dark PASS || result default-wallpaper-dark FAIL "$(q "['wallpaperNow']")"
g() { gsettings get org.gnome.desktop.interface "$1"; }
[ "$(g icon-theme)" = "'Papirus-Dark'" ] && [ "$(g accent-color)" = "'orange'" ] && [ "$(g monospace-font-name)" = "'JetBrains Mono 11'" ] \
    && result default-look-for-apps PASS || result default-look-for-apps FAIL "$(g icon-theme) $(g accent-color) $(g monospace-font-name)"
settings '{"accentName": "purple", "accentFromWallpaper": false}'
waitfor "d['accent'] == '#dc8add'" 3 && [ "$(g accent-color)" = "'purple'" ] && result accent-choice PASS || result accent-choice FAIL "$(q "['accent']") $(g accent-color)"
# one material: the background leans to the accent's hue (purple: blue above green)
waitfor "int(d['bg'][5:7],16) > int(d['bg'][3:5],16)" 3 && result palette-follows-accent PASS "$(q "['bg']")" || result palette-follows-accent FAIL "$(q "['bg'], d['accent']")"

# ---- mouse and touchpad details, Num Lock, middle-click paste -------------------------
settings '{"tpAccel": "flat", "tpClick": "button-areas", "tpScrollMethod": "edge", "tpOffWithMouse": true, "numlock": false, "mouseAccel": "flat", "middlePaste": false}'
sleep 1.5
f=/root/.config/niri/shani-input.kdl
grep -q 'click-method "button-areas"' $f && grep -q 'scroll-method "edge"' $f && grep -q 'disabled-on-external-mouse' $f && ! grep -q '^ *numlock$' $f \
    && [ "$(grep -c 'accel-profile "flat"' $f)" = 2 ] && niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 && [ "$(g gtk-enable-primary-paste)" = false ] \
    && result pointer-details-reach-niri PASS || result pointer-details-reach-niri FAIL "$(niri validate -c /work/dev/niri/session.kdl 2>&1 | tail -1)"

# ---- a drawing tablet and a touchscreen on one screen ------------------------------------
settings '{"tabletOutput": "winit", "tabletLeftHanded": true, "touchOutput": "winit"}'
sleep 1.5
[ "$(grep -c 'map-to-output "winit"' $f)" = 2 ] && grep -q '^ *left-handed$' $f && niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 \
    && result tablet-touch-map-to-output PASS || result tablet-touch-map-to-output FAIL "$(grep -A3 'tablet\|touch' $f | head -6 | tr '\n' ' ') $(niri validate -c /work/dev/niri/session.kdl 2>&1 | tail -1)"
settings '{}'

# ---- wellbeing: a break reminder after the stretch, a daily reminder past the limit ------
settings '{"screenTime": true, "breakEveryMinutes": 20, "screenLimitMinutes": 120}'
ipc wellbeingNow 1300 7300
waitfor "'Time for a break' in d['notificationSummaries'] and \"Today's screen time is up\" in d['notificationSummaries']" 4 \
    && result wellbeing-reminders PASS || result wellbeing-reminders FAIL "$(q "['notificationSummaries'][-4:]")"
n0=$(q "['notificationSummaries'].count(\"Today's screen time is up\")")
ipc wellbeingNow 1300 7400
sleep 1
[ "$(q "['notificationSummaries'].count(\"Today's screen time is up\")")" = "$n0" ] && result wellbeing-limit-once-a-day PASS || result wellbeing-limit-once-a-day FAIL
settings '{}'

# ---- automatic dark style, scrollbars, bar options -----------------------------------
from=$(date -d '-1 min' +%H:%M); to=$(date -d '+60 min' +%H:%M)
settings "{\"darkMode\": false, \"darkSchedule\": \"custom\", \"darkFrom\": \"$from\", \"darkTo\": \"$to\", \"showScrollbars\": true}"
waitfor "d['dark']" 5 && result dark-style-on-schedule PASS || result dark-style-on-schedule FAIL
[ "$(g overlay-scrolling)" = false ] && result scrollbars-always PASS || result scrollbars-always FAIL

# ---- volume: the key step, and above 100 % only when allowed ---------------------------
settings '{"volumeStep": 10}'
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.50; sleep 0.5
ipc volumeUp; sleep 0.5
v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
[ "$v" = 0.60 ] && result volume-step PASS || result volume-step FAIL "$v"
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0; sleep 0.5; ipc volumeUp; sleep 0.5
[ "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')" = 1.00 ] && result volume-capped-at-100 PASS || result volume-capped-at-100 FAIL
settings '{"overAmplify": true, "volumeStep": 10}'
ipc volumeUp; sleep 0.5
[ "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')" = 1.10 ] && result volume-over-100-when-allowed PASS || result volume-over-100-when-allowed FAIL "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)"
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.35

# ---- search: what the launcher may look at; slideshow; the Island's activities ---------
settings '{"searchCalc": false}'
ipc launcher "12*12"
sleep 1.5
q "['topResult']" | grep -q '^= 144' && result search-calc-off FAIL || result search-calc-off PASS
ipc closeAll
settings '{"slideshowDir": "/usr/share/backgrounds/shani", "slideshowMinutes": 5}'
waitfor "d['wallpaperNow'].startswith('/usr/share/backgrounds/shani/shani-') and d['wallpaperNow'] != ''" 4 && result wallpaper-slideshow PASS "$(q "['wallpaperNow']")" || result wallpaper-slideshow FAIL "$(q "['wallpaperNow']")"
settings '{"islandActivities": false}'
ipc timer 1
sleep 1
[ "$(q "['islandActivity']")" = "" ] && result island-activities-off PASS || result island-activities-off FAIL "$(q "['islandActivity']")"
ipc timer 0
settings '{"popupPosition": "bottom-right"}'
notify-send -a Test "Bottom right" "a pop-up"
shot 92-popup-bottom 0.6
settings '{}'

# ---- QR codes: a link from the clipboard, decoded back from the picture ------------------
printf 'https://shani.dev/qr-check' | wl-copy; sleep 0.5
ipc launcher "clipboard qr"
waitfor "d['topResult'] == 'Clipboard as a QR code'" 3
wtype -k Return
waitfor "d['qrShown']" 4 && [ "$(zbarimg -q --raw "$(q "['qrImage']")" 2>/dev/null)" = "https://shani.dev/qr-check" ] \
    && result qr-code-decodes PASS || result qr-code-decodes FAIL "$(zbarimg -q --raw "$(q "['qrImage']")" 2>&1 | head -1)"
shot 93-qr 0.4
wtype -k Escape
waitfor "not d['qrShown']" 3 && result qr-closes PASS || result qr-closes FAIL

# ---- a recording made into a GIF and a smaller video (ffmpeg) ------------------------------
ffmpeg -y -loglevel error -f lavfi -i testsrc=size=1280x720:rate=30 -f lavfi -i sine=frequency=440 -t 3 -c:v libx264 -pix_fmt yuv420p -c:a aac /tmp/rec-test.mp4
ipc recordingToGif /tmp/rec-test.mp4
waitfor "d['converted'] == '/tmp/rec-test.gif'" 30 && head -c 6 /tmp/rec-test.gif | grep -q GIF89a && result recording-to-gif PASS "$(stat -c %s /tmp/rec-test.gif) bytes" || result recording-to-gif FAIL "$(q "['converted']")"
ipc recordingShrink /tmp/rec-test.mp4
waitfor "d['converted'] == '/tmp/rec-test (smaller).mp4'" 30 && [ -s "/tmp/rec-test (smaller).mp4" ] && result recording-smaller PASS || result recording-smaller FAIL "$(q "['converted']")"

# ---- the CPU's temperature, from the kernel's sensor (the host's, seen through /sys) -------
if ls /sys/class/hwmon/*/name >/dev/null 2>&1 && grep -qxE 'coretemp|k10temp|zenpower|cpu_thermal|soc_thermal' /sys/class/hwmon/*/name; then
    ipc setting showSysStats true      # sampled only while shown: the bar's chip shows it
    waitfor "d['cpuTemp'] > 10 and d['cpuTemp'] < 120" 8 && result cpu-temperature PASS "$(q "['cpuTemp']") °C" || result cpu-temperature FAIL "$(q "['cpuTemp']")"
else
    result cpu-temperature SKIP "no CPU sensor visible here"
fi
ipc setting showSysStats false

# ---- the agenda: events from Evolution Data Server's own "Personal" calendar ------------
cal=/root/.local/share/evolution/calendar/system
mkdir -p $cal
t1=$(date -u -d '+3 hours' +%Y%m%dT%H%M00Z); t2=$(date -u -d '+4 hours' +%Y%m%dT%H%M00Z)
w1=$(date -u -d '-7 days +5 hours' +%Y%m%dT%H%M00Z); w2=$(date -u -d '-7 days +6 hours' +%Y%m%dT%H%M00Z)
printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//shani//test//EN\r\nBEGIN:VEVENT\r\nUID:one@test\r\nDTSTAMP:%s\r\nDTSTART:%s\r\nDTEND:%s\r\nSUMMARY:Design review\r\nLOCATION:Room 2\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:weekly@test\r\nDTSTAMP:%s\r\nDTSTART:%s\r\nDTEND:%s\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:Weekly sync\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$t1" "$t1" "$t2" "$w1" "$w1" "$w2" > $cal/calendar.ics
ipc agendaRefresh
# EDS can still be starting when the first refresh asks (it answers [] then, and the
# next poll is 30 s away): ask again once rather than wait out the poll
waitfor "'Design review' in d['agenda']" 12 || ipc agendaRefresh
waitfor "'Design review' in d['agenda'] and 'Weekly sync' in d['agenda']" 30 && result agenda-from-eds PASS "$(q "['agenda']")" \
    || result agenda-from-eds FAIL "$(q "['agenda']") $(python3 /work/bridge/agenda.py 2>&1 | tail -1)"
ipc controlCenter ""
shot 94-agenda 0.8
ipc closeAll

# ---- the launcher's file search from plocate's index --------------------------------------
mkdir -p /root/Documents/projects && touch /root/Documents/projects/zebra-quarterly-plan.odt
updatedb 2>/dev/null
ipc launcher "zebra-quarterly"
waitfor "d['topResult'] == 'zebra-quarterly-plan.odt'" 6 && result launcher-files-from-plocate PASS || result launcher-files-from-plocate FAIL "$(q "['topResult']")"
ipc closeAll

# ---- the SIM modem (a stand-in for bridge/modem.py; tests/test_modem.py runs the real one) --
rm -f /tmp/modem-answers
echo '{"modem": {"path": "/m/0", "state": "locked", "locked": "sim-pin", "operator": "", "signal": 0, "number": "", "voice": true, "messaging": true}}' > /tmp/modem-ask
waitfor "d['modem'] == 'locked/sim-pin/' and 'The SIM card is locked' in d['notificationSummaries']" 5 && result sim-locked-asks PASS || result sim-locked-asks FAIL "$(q "['modem']")"
echo '{"modem": {"path": "/m/0", "state": "registered", "locked": "", "operator": "Jio", "signal": 63, "number": "", "voice": true, "messaging": true}}' > /tmp/modem-ask
waitfor "d['modem'] == 'registered/unlocked/Jio'" 4
echo '{"sms": {"path": "/s/1", "from": "+919811111111", "text": "Your code is 482913", "time": ""}}' > /tmp/modem-ask
waitfor "'+919811111111' in d['notificationSummaries']" 4 && result sms-notifies PASS || result sms-notifies FAIL
shot 95-sms 0.4
# a modem call rings once - shani-link's notification - not a second one from the shell
n0=$(q "['notificationSummaries'].count('Call from +919844444444')")
echo '{"call": {"path": "/c/1", "number": "+919844444444", "state": "ringing-in", "incoming": true}}' > /tmp/modem-ask
sleep 1.5
[ "$(q "['notificationSummaries'].count('Call from +919844444444')")" = "$n0" ] && result call-rings-once PASS || result call-rings-once FAIL "the shell rang too"
notify-send -a "Shani Link" -h string:category:call.incoming -u critical -A answer=Answer -A decline=Decline "Call from +919844444444" "on your mobile" &
waitfor "d['islandActivity'].startswith('Call from +919844444444')" 4 && result call-ringing-on-island PASS || result call-ringing-on-island FAIL "$(q "['islandActivity']")"
shot 96-call-ringing 0.3
echo '{"call": {"path": "/c/1", "number": "+919844444444", "state": "terminated", "incoming": true}}' > /tmp/modem-ask
waitfor "d['modemCall'] == ''" 4
ipc textMessage "+919822222222"
waitfor "d['modemDialog'] == 'sms'" 3
sleep 0.6
wtype "On my way" -k Return
sleep 1
grep -q '"to":"+919822222222","text":"On my way"' /tmp/modem-answers 2>/dev/null && result sms-composer-sends PASS || result sms-composer-sends FAIL "$(cat /tmp/modem-answers 2>&1)"

# ---- the first-login tour: five cards and "Make it yours", Enter through them, remembered --
ipc tour
waitfor "d['tour']" 3 && result tour-opens PASS || result tour-opens FAIL
shot 91-tour 0.6
for i in 1 2 3 4 5; do wtype -k Return; sleep 0.3; done
shot 91b-tour-make-it-yours 0.3
# its last card opens the layout picker itself (and the tour counts as seen)
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "button:^Desktop layout" >/dev/null 2>&1
    waitfor "d['layoutSwitcher'] and not d['tour']" 3 && result tour-opens-layouts PASS || result tour-opens-layouts FAIL "$(q "['layoutSwitcher'], d['tour']")"
    wtype -k Escape; waitfor "not d['layoutSwitcher']" 3
else
    wtype -k Return
fi
waitfor "not d['tour']" 3; sleep 1   # the settings file is written a moment later
grep -q '"tourSeen": *true' /tmp/shani-settings.json && result tour-finishes-and-remembers PASS || result tour-finishes-and-remembers FAIL "$(grep -o '"tourSeen"[^,]*' /tmp/shani-settings.json)"
settings '{}'

# ---- search inside Settings: "proxy" opens Network ----------------------------------
ipc settings
waitfor "d['settingsOpen']" 3
sleep 0.6
wtype "proxy" -k Return
waitfor "d['settingsCat'] == 'network'" 3 && result settings-search-finds-category PASS || result settings-search-finds-category FAIL "$(q "['settingsCat']")"
ipc closeAll

# ---- recording a part of the screen: Escape at the selection is not a failure ---------
settings '{"recordArea": "region", "recordSound": "desktop"}'
f0=$(q "['notificationSummaries'].count('Recording failed')")
ipc record
for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x slurp >/dev/null && break; sleep 0.3; done
sleep 0.5
wtype -k Escape
sleep 1.5
pgrep -x slurp >/dev/null && result record-region-selection-ends FAIL "slurp still running" || result record-region-selection-ends PASS
[ "$(q "['notificationSummaries'].count('Recording failed')")" = "$f0" ] && result record-region-cancel-is-quiet PASS || result record-region-cancel-is-quiet FAIL
[ "$(q "['recording']")" = False ] || ipc record
ipc record
for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x slurp >/dev/null && break; sleep 0.3; done
ipc record
sleep 1
pgrep -x slurp >/dev/null && { result record-stop-ends-selection FAIL; pkill -x slurp; } || result record-stop-ends-selection PASS
settings '{}'

# ---- one clipboard entry removed (Shift+Delete in the launcher's clipboard mode) -------
printf 'remove-me-4711' | wl-copy; sleep 0.8
printf 'keep-me-4712' | wl-copy; sleep 0.8
ipc launcher "c remove-me"
waitfor "d['topResult'].startswith('remove-me-4711')" 4
wtype -M shift -k Delete -m shift; sleep 1
cliphist list | grep -q remove-me-4711 && result clipboard-entry-removed FAIL || { cliphist list | grep -q keep-me-4712 && result clipboard-entry-removed PASS || result clipboard-entry-removed FAIL "took the others too"; }
ipc closeAll

# ---- a clipboard entry pinned (Ctrl+P): kept through clearing the history -------------
printf 'pin-me-4713' | wl-copy; sleep 0.8
ipc launcher "c pin-me"
waitfor "d['topResult'].startswith('pin-me-4713')" 4
wtype -M ctrl -k p -m ctrl; sleep 1
grep -q pin-me-4713 "$SHANI_SHELL_SETTINGS" && result clipboard-pin PASS || result clipboard-pin FAIL "$(cat "$SHANI_SHELL_SETTINGS" | head -c 300)"
ipc closeAll

# ---- clipboard history can be cleared ------------------------------------------------
printf 'secret-token-123' | wl-copy; sleep 0.8
cliphist list | grep -q secret-token-123 || echo "  (cliphist did not store it)"
ipc launcher "clear clipboard"
waitfor "d['topResult'] == 'Clear clipboard history'" 3
top=$(q "['topResult']")
wtype -k Return
# clearing waits for the clipboard to settle before it wipes the history
for i in 1 2 3 4 5 6; do sleep 0.5; cliphist list | grep -q secret-token-123 || break; done
cliphist list | grep -q secret-token-123 && result clipboard-history-cleared FAIL "Enter ran: $top; history: $(cliphist list | head -2 | tr '\n' ' ')" || result clipboard-history-cleared PASS
ipc closeAll; sleep 0.3
ipc launcher "c pin-me"
waitfor "'Pinned' in d['launcherSections'] and d['topResult'].startswith('pin-me-4713')" 4 \
    && result clipboard-pin-survives-clearing PASS || result clipboard-pin-survives-clearing FAIL "$(q "['launcherSections']")"
ipc closeAll

# ---- pop-up duration follows the setting --------------------------------------------
settings '{"popupSeconds": 4}'
notify-send -a Test "Four seconds" "then gone"
waitfor "'Four seconds' in d['popupSummaries']" 2
sleep 3; q "['popupSummaries']" | grep -q 'Four seconds' && waitfor "'Four seconds' not in d['popupSummaries']" 3 \
    && result popup-duration-setting PASS || result popup-duration-setting FAIL "$(q "['popups']")"
settings '{}'

# ---- call recording: both sides into one file -----------------------------------
rm -rf /root/Recordings/Calls
ipc callRecord
waitfor "d['callRecording']" 4 && result call-record-starts PASS || result call-record-starts FAIL "$(tail -3 /work/out/logs/qs.log)"
shot 62-call-record 0.3
paplay /tmp/cap.wav
ipc callRecord
waitfor "not d['callRecording']" 4
f=$(ls /root/Recordings/Calls/*.ogg 2>/dev/null | head -1)
[ -n "$f" ] && [ "$(stat -c %s "$f")" -gt 2000 ] && result call-record-file PASS "$(stat -c %s "$f") bytes" \
    || result call-record-file FAIL "$(ls -la /root/Recordings/Calls 2>&1)"

# ---- magnifier and smart touch ------------------------------------------------------
ipc magnifier
waitfor "d['magnifier']" 3 && result magnifier-opens PASS || result magnifier-opens FAIL
shot 63-magnifier 0.8
wtype -k Escape
waitfor "not d['magnifier']" 3 && result magnifier-escape-closes PASS || result magnifier-escape-closes FAIL
ipc smartTouch
waitfor "d['assistiveTouch']" 3 && result smart-touch-on PASS || result smart-touch-on FAIL
shot 64-smart-touch 0.4
ipc ringAt 300 500
waitfor "d['ring']" 3 && result ring-opens-at-point PASS || result ring-opens-at-point FAIL
shot 65-ring-at-bubble 0.4
wtype -k Escape
waitfor "not d['ring']" 3
ipc smartTouch

# ---- share sheet: one Share… for a file ---------------------------------------------
printf 'shared words' > /tmp/share-me.txt
ipc share /tmp/share-me.txt
waitfor "'Copy its path' in d['shareTargets'] and 'Nearby devices (LocalSend)' in d['shareTargets']" 4 \
    && result share-sheet-targets PASS || result share-sheet-targets FAIL "$(q "['shareTargets']")"
shot 70-share-sheet 0.4
n=$(q "['shareTargets'].index('Copy its path')")
for i in $(seq 1 "$n"); do wtype -k Down; sleep 0.1; done
wtype -k Return
waitfor "d['shareDone'] == 'Copy its path' and d['shareTargets'] == []" 3 && [ "$(wl-paste -n)" = /tmp/share-me.txt ] \
    && result share-copies-path PASS || result share-copies-path FAIL "$(q "['shareDone']") / $(wl-paste -n)"

# ---- drawing on the screen: opens, saves a screenshot with it, closes -------------------
rm -rf /root/Pictures/Screenshots
ipc annotate
waitfor "d['annotate']" 3 && result annotate-opens PASS || result annotate-opens FAIL
shot 71-annotate 0.4
wtype s
for i in $(seq 1 20); do ls /root/Pictures/Screenshots/Drawing*.png >/dev/null 2>&1 && break; sleep 0.25; done
ls /root/Pictures/Screenshots/Drawing*.png >/dev/null 2>&1 && result annotate-saves PASS || result annotate-saves FAIL "$(tail -2 /work/out/logs/qs.log)"
wtype -k Escape
waitfor "not d['annotate']" 3 && result annotate-closes PASS || result annotate-closes FAIL

# ---- a call from any app (Chronoa's phone, a VoIP app): carried on the Island -----------
rm -f /tmp/call-answer
( a=$(notify-send -a Phone -u critical -h string:category:call.incoming -A answer=Answer -A decline=Decline "Asha Patil" "Calling on your phone"); echo "$a" > /tmp/call-answer ) &
waitfor "d['islandActivity'].startswith('Asha Patil')" 5 && result island-carries-incoming-call PASS "$(q "['islandActivity']")" || result island-carries-incoming-call FAIL "$(q "['islandActivity']")"
ipc answerCall
for i in $(seq 1 12); do [ -s /tmp/call-answer ] && break; sleep 0.25; done
[ "$(cat /tmp/call-answer 2>/dev/null)" = answer ] && result island-answers-call PASS || result island-answers-call FAIL "$(cat /tmp/call-answer 2>&1)"
waitfor "not d['islandActivity'].startswith('Asha Patil')" 4 && result island-call-ends PASS || result island-call-ends FAIL "$(q "['islandActivity']")"

# ---- replying from a notification (the "inline-reply" action; Chronoa's phone texts) ---
# the app keeps its connection and waits for NotificationReplied, as Chronoa does
rm -f /tmp/replied
python3 /work/dev/reply-client.py "Message from Asha" > /tmp/replied 2>&1 &
waitfor "'Message from Asha' in d['notificationSummaries']" 4
ipc notificationReply "Message from Asha" "On my way"
for i in $(seq 1 16); do grep -q "On my way" /tmp/replied 2>/dev/null && break; sleep 0.25; done
grep -q "On my way" /tmp/replied 2>/dev/null && result notification-inline-reply PASS || result notification-inline-reply FAIL "$(cat /tmp/replied 2>&1)"

# ---- Settings > Printers: CUPS's printers, a per-person default, a job waiting ----------
if [ -S /run/cups/cups.sock ]; then
    ipc settingsCategory printers
    sleep 1.5
    waitfor "any(p.startswith('Office_Laser:') for p in d['printersSeen'])" 5 \
        && result printers-listed PASS || result printers-listed FAIL "$(lpstat -p 2>&1 | head -2)"
    # what its buttons run, as this person (no administrator): a default of
    # their own (lpstat -d follows it), and a job handed to CUPS shows as waiting.
    # Whether CUPS then prints it is CUPS's (a raw file queue here never runs).
    lpoptions -d Office_Laser >/dev/null && lpstat -d | grep -q ": Office_Laser$" \
        && result printers-default-per-person PASS || result printers-default-per-person FAIL "$(lpstat -d 2>&1)"
    # held, so it stays in the queue (a raw file queue here may finish or drop it at once)
    printf 'test page\n' > /tmp/tp.txt; lp -d Office_Laser -H hold /tmp/tp.txt >/dev/null
    ipc closeAll; sleep 0.3; ipc settingsCategory printers; sleep 1.5
    waitfor "'Office_Laser:default:1' in d['printersSeen']" 5 \
        && result printers-job-waiting PASS || result printers-job-waiting FAIL "page: $(q "['printersSeen']"); lpstat -o: $(lpstat -o 2>&1 | head -2 | tr '\n' ' ')"
    waitfor "any(':default:' in p for p in d['printersSeen'])" 3 \
        && result printers-shows-default PASS || result printers-shows-default FAIL "$(q "['printersSeen']")"
    cancel -a Office_Laser 2>/dev/null
    ipc closeAll
else
    result printers-listed SKIP "no cupsd in this image"
fi

# ---- Settings > Backup: what Shani Backup says, and Open goes to its page ---------------
rm -f /tmp/backup-opened
ipc settingsCategory backup
waitfor "'2 snapshots on this disk · latest today' in d['backupSummary'] and 'every day at 21:15' in d['backupSummary']" 5 \
    && result settings-backup-summary PASS "$(q "['backupSummary']")" || result settings-backup-summary FAIL "$(q "['backupSummary']")"
shot 72-settings-backup 0.4
ipc closeAll
ipc launcher "earlier versions"
waitfor "d['topResult'] == 'Earlier versions of my files'" 4
wtype -k Return; sleep 0.8
grep -q "^open home$" /tmp/backup-opened 2>/dev/null && result launcher-opens-earlier-versions PASS || result launcher-opens-earlier-versions FAIL "$(q "['topResult']") / $(cat /tmp/backup-opened 2>&1)"

# ---- automations: sound to HDMI turns Do not disturb on, once ---------------------------
pactl set-default-sink speakers; sleep 0.5
settings '{"automations": [{"when": "output", "is": "HDMI", "then": "dnd", "arg": "on", "on": true}]}'
sleep 0.5
[ "$(q "['dnd']")" = False ] && result automation-waits PASS || result automation-waits FAIL "fired before its moment"
pactl set-default-sink hdmi
waitfor "d['dnd'] and len(d['automationsFired']) == 1" 4 && result automation-fires PASS "$(q "['automationsFired']")" \
    || result automation-fires FAIL "$(q "['automationsFired']") dnd=$(q "['dnd']")"
pactl set-default-sink speakers; sleep 0.5
settings '{}'

# ---- lock screen: PAM, wrong then right ----------------------------------------
cp /tmp/frame.png /root/.face          # the avatar the lock screen shows
echo 'root:shani-test' | chpasswd
ipc lock
waitfor "d['locked'] and d['lockSecure']" 5 && result lock-engages PASS || result lock-engages FAIL "$(st)"
shot 26-lock 0.6
wtype "wrong-password" -k Return
sleep 2.5
[ "$(q "['locked']")" = True ] && result lock-refuses-wrong-password PASS || result lock-refuses-wrong-password FAIL
shot 27-lock-wrong 0.2
wtype "shani-test" -k Return
waitfor "not d['locked']" 6 && result lock-unlocks-with-password PASS || result lock-unlocks-with-password FAIL "$(st)"
[ "$(q "['locked']")" = False ] || { echo "still locked: the checks below would pass for the wrong reason"; exit 1; }
ipc lock
waitfor "d['locked']" 4 && result lock-relocks PASS || result lock-relocks FAIL
# a photo from the lock screen, without unlocking; only it is shown there
if [ -f "$A11Y" ]; then
    sleep 1; timeout 20 python3 "$A11Y" press "button:^Take a photo$" >/dev/null 2>&1
    waitfor "d['lockPhotos'] == 1 and d['locked']" 12 && result lock-screen-camera PASS "$(q "['cameraLast']")" || result lock-screen-camera FAIL "$(q "['lockPhotos'], d['cameraPhase']")"
    shot 27b-lock-camera 0.4
fi
wtype "shani-test" -k Return
waitfor "not d['locked']" 6
[ "$(q "['lockPhotos']")" = 0 ] && result lock-photos-forgotten-on-unlock PASS || result lock-photos-forgotten-on-unlock FAIL

# ---- a click on a notification brings its app forward -----------------------------
foot --app-id=raise-me sh -c "sleep 60" >/dev/null 2>&1 &
foot --app-id=on-top sh -c "sleep 60" >/dev/null 2>&1 &
i=0; until [ -n "$(winid raise-me)" ] && [ -n "$(winid on-top)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
niri msg action focus-window --id "$(winid on-top)"; sleep 0.4
notify-send -a raise-me "Raise me" "click this"; sleep 1
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "^Raise me" >/dev/null 2>&1; sleep 0.8
    [ "$(niri msg -j focused-window | python3 -c 'import json,sys; print(json.load(sys.stdin)["app_id"])')" = raise-me ] \
        && result notification-click-raises-app PASS || result notification-click-raises-app FAIL
fi
niri msg action close-window --id "$(winid raise-me)" 2>/dev/null; niri msg action close-window --id "$(winid on-top)" 2>/dev/null

# ---- face / fingerprint: a second conversation beside the password -------------------
touch /tmp/bio-available /tmp/face-match
ipc lock
waitfor "d['locked']" 4
waitfor "not d['locked']" 8 && result lock-unlocks-with-face PASS || result lock-unlocks-with-face FAIL "$(st)"
rm -f /tmp/face-match
ipc lock
waitfor "d['locked']" 4; sleep 6
[ "$(q "['locked']")" = True ] && result lock-face-miss-stays-locked PASS || result lock-face-miss-stays-locked FAIL
wtype "shani-test" -k Return
waitfor "not d['locked']" 6 && result lock-password-beside-face PASS || result lock-password-beside-face FAIL "$(st)"
rm -f /tmp/bio-available

# ---- an app's pop-ups off from its own notification; the lock screen's power keys
if [ -f "$A11Y" ]; then
    ipc closeAll
    notify-send -a Chatty "Chatty says hi" "again and again"; sleep 1
    timeout 20 python3 "$A11Y" press "^More actions$" >/dev/null 2>&1; sleep 0.5
    timeout 20 python3 "$A11Y" press "^No pop-ups from Chatty$" >/dev/null 2>&1; sleep 1
    grep -q '"Chatty"' "$SHANI_SHELL_SETTINGS" && result notification-silence-app PASS || result notification-silence-app FAIL
    settings '{}'
    ipc lock; waitfor "d['locked']" 4; sleep 1
    timeout 20 python3 "$A11Y" find "button:^Shut down$" >/dev/null 2>&1 && result lock-power-keys PASS || result lock-power-keys FAIL
    wtype "shani-test" -k Return; waitfor "not d['locked']" 6
fi

# ---- a screenshot on a timer: counted down, then the whole screen ----------------------
rm -f /root/Pictures/Screenshots/* 2>/dev/null
if [ -f "$A11Y" ]; then
    ipc controlCenter screenshot; sleep 0.8
    timeout 20 python3 "$A11Y" press "^Whole screen in 3 seconds$" >/dev/null 2>&1; sleep 1.2
    c=$(q "['shotCountdown']")
    waitfor "d['shotCountdown'] == 0" 6
    sleep 1.5; n=$(ls /root/Pictures/Screenshots 2>/dev/null | wc -l)
    [ "$c" -gt 0 ] 2>/dev/null && [ "$n" -ge 1 ] && result screenshot-on-a-timer PASS "counting $c, then $n file" || result screenshot-on-a-timer FAIL "countdown=$c files=$n"
fi

# ---- notifications unread at a restart are written down, to be shown again ---------
notify-send -a Keeper "Kept across restarts" "read me later"
i=0; until grep -rqs "Kept across restarts" /root/.local/state/quickshell || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
grep -rqs "Kept across restarts" /root/.local/state/quickshell && result notification-history-kept PASS || result notification-history-kept FAIL

# ---- the dock's trash: full or empty at a glance -------------------------------------
settings '{"dockVisibility": "always"}'
printf 'bin me' > /tmp/bin-me.txt; gio trash /tmp/bin-me.txt 2>/dev/null
waitfor "d['trashCount'] >= 1" 4 && result dock-trash-sees-it PASS "$(q "['trashCount']")" || result dock-trash-sees-it FAIL "$(q "['trashCount']")"
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" find "button:^Trash$" >/dev/null 2>&1 && result dock-trash-tile PASS || result dock-trash-tile FAIL
fi
gio trash --empty 2>/dev/null
waitfor "d['trashCount'] == 0" 4 && result dock-trash-empties PASS || result dock-trash-empties FAIL "$(q "['trashCount']")"
settings '{}'

# ---- a workspace named, and the name taken off again ------------------------------------
ipc renameWorkspace 1 "Mail"; sleep 1
niri msg -j workspaces | grep -q '"Mail"' && result workspace-named PASS || result workspace-named FAIL
ipc renameWorkspace 1 ""; sleep 1
niri msg -j workspaces | grep -q '"Mail"' && result workspace-name-cleared FAIL || result workspace-name-cleared PASS

# ---- a bar button of your own: a command's output, refreshed --------------------------
settings '{"barCommands": [{"command": "echo hello-from-bar", "every": 0, "click": "touch /tmp/bar-clicked"}]}'
if [ -f "$A11Y" ]; then
    sleep 1.5
    timeout 20 python3 "$A11Y" press "^hello-from-bar$" >/dev/null 2>&1 && sleep 0.8
    [ -e /tmp/bar-clicked ] && result bar-own-button PASS || result bar-own-button FAIL
fi
settings '{}'

# ---- wallpapers found online (a local stand-in for Wallhaven): searched, saved ------
mkdir -p /tmp/lrc/api/v1; cp /work/assets/shani-dark.jpg /tmp/lrc/wall-a1b2c3.jpg 2>/dev/null || convert -size 64x64 xc:navy /tmp/lrc/wall-a1b2c3.jpg
printf '{"data":[{"id":"a1b2c3","path":"http://127.0.0.1:8799/wall-a1b2c3.jpg","resolution":"1920x1080","thumbs":{"small":"http://127.0.0.1:8799/wall-a1b2c3.jpg"}}]}' > /tmp/lrc/api/v1/search
pgrep -f "serve_forever" >/dev/null || (cd /tmp/lrc && python3 -c "
import http.server, socketserver
class H(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, p): return super().translate_path(p.split('?')[0])
    def log_message(self, *a): pass
socketserver.TCPServer(('127.0.0.1', 8799), H).serve_forever()" >/dev/null 2>&1 &); sleep 0.5
ipc wallpaperSearch "night"
waitfor "d['onlineWalls'] == 1" 6 && result wallpaper-online-search PASS || result wallpaper-online-search FAIL "$(q "['onlineWalls']")"
ipc wallpaperFetch 0
waitfor "d['onlineWallSaved'].endswith('wallhaven-a1b2c3.jpg')" 8 && [ -s /root/Pictures/Wallpapers/wallhaven-a1b2c3.jpg ] \
    && result wallpaper-online-saved PASS || result wallpaper-online-saved FAIL "$(q "['onlineWallSaved']")"

# ---- the compass: read while the sidebar is open, and only then ----------------------
ipc closeAll; sleep 0.5
ipc toggleControlCenter
waitfor "d['compassHeading'] == 90 and 'compass' in d['tilesShown']" 4 && result compass-reads-heading PASS || result compass-reads-heading FAIL "$(q "['compassHeading']")"
ipc closeAll
waitfor "d['compassHeading'] == -1" 3 && ! pgrep -fx "sleep 6011" >/dev/null && result compass-stops-when-closed PASS || result compass-stops-when-closed FAIL "$(q "['compassHeading']")"

# ---- face sign-in from Settings: on, then five looks reach the daemon -------------------
rm -f /tmp/lh.sock /tmp/lh-asked; python3 -c "
import json, os, socket
s = socket.socket(socket.AF_UNIX); s.bind('/tmp/lh.sock'); s.listen(4); n = 0
while True:
    c, _ = s.accept(); req = json.loads(c.makefile().readline())
    if req['action'] == 'enroll':
        n += 1; open('/tmp/lh-asked', 'a').write(req['label'] + '\\n')
        c.sendall((json.dumps({'type': 'enroll', 'success': True, 'score': 0.9, 'total_enrolled': n, 'message': 'ok'}) + '\\n').encode())
    else:
        c.sendall((json.dumps({'type': 'status', 'ready': True, 'camera_found': True, 'camera_path': '/dev/video2', 'enrolled_users': []}) + '\\n').encode())
    c.close()" >/dev/null 2>&1 &
LH=$!
sleep 0.5
if [ -f "$A11Y" ]; then
    ipc settingsCategory account; sleep 2
    timeout 20 python3 "$A11Y" press "^Set up my face$" >/dev/null 2>&1
    i=0; until [ "$(wc -l < /tmp/lh-asked 2>/dev/null)" = 5 ] || [ $i -ge 60 ]; do sleep 0.5; i=$((i+1)); done
    [ "$(tr '\n' ' ' < /tmp/lh-asked 2>/dev/null)" = "center look_left look_right look_up look_down " ] \
        && result settings-face-setup PASS || result settings-face-setup FAIL "asked: $(tr '\n' ' ' < /tmp/lh-asked 2>/dev/null)"
    ipc closeAll
fi
kill $LH 2>/dev/null

# ---- notification rules apply: one dropped, one kept without a pop-up ----------------------
mkdir -p /root/.config/shani-shell
printf '{"rules": [{"pattern": "spammy-offer", "action": "block"}, {"pattern": "quiet-digest", "action": "hide"}]}' > /root/.config/shani-shell/notif-rules.json
sleep 1.5
n0=$(q "['notifications']"); p0=$(q "['popups']")
notify-send -a Shop "A spammy-offer for you" "50% off"; sleep 1
[ "$(q "['notifications']")" = "$n0" ] && result notification-rule-drops PASS || result notification-rule-drops FAIL "$(q "['notifications']") vs $n0"
notify-send -a News "Your quiet-digest" "5 stories"; sleep 1
[ "$(q "['notifications']")" -gt "$n0" ] && [ "$(q "['popups']")" = "$p0" ] && result notification-rule-hides PASS || result notification-rule-hides FAIL "$(q "['notifications']"), popups $(q "['popups']") vs $p0"
rm -f /root/.config/shani-shell/notif-rules.json

# ---- the shortcuts page: niri's real binds (it once listed keys bound to nothing) ---------
if [ -f "$A11Y" ]; then
    ipc settingsCategory input; sleep 2
    timeout 20 python3 "$A11Y" find "^Clipboard history$" >/dev/null 2>&1 && timeout 20 python3 "$A11Y" find "^Minimise$" >/dev/null 2>&1 \
        && result shortcuts-page-reads-niri PASS || result shortcuts-page-reads-niri FAIL
    ipc closeAll
fi
settings '{"customBinds": [{"key": "Mod+Alt+J", "title": "Open my files", "command": "xdg-open \"$HOME\""}]}'
sleep 1.5
grep -q 'Mod+Alt+J hotkey-overlay-title="Open my files"' "${XDG_CONFIG_HOME:-$HOME/.config}/niri/shani-input.kdl" && niri validate -c "${NIRI_CONFIG:-/work/dev/niri/session.kdl}" >/dev/null 2>&1 \
    && result custom-shortcut-written PASS || result custom-shortcut-written FAIL "$(grep -c 'Mod+Alt+J' "${XDG_CONFIG_HOME:-$HOME/.config}/niri/shani-input.kdl" 2>/dev/null)"
settings '{}'

# ---- dynamic lock: the paired phone goes away → locked after the grace ---------------
settings '{"dynamicLockDevice": "AA:BB:CC:DD:EE:FF"}'
waitfor "d['dynamicLockDevice'] == 'AA:BB:CC:DD:EE:FF' and not d['locked']" 6 || true
ipc dynamicLockAway
waitfor "d['locked'] and d['dynamicLocks'] == 1" 6 && result dynamic-lock PASS || result dynamic-lock FAIL "$(q "['dynamicLocks']")"
wtype "shani-test" -k Return
waitfor "not d['locked']" 6
settings '{}'

# ---- idle: the lock stage fires on its own --------------------------------------
waitfor "not d['locked']" 4 || { echo "still locked before the idle check"; exit 1; }
settings '{"dimAfter": 0, "lockAfter": 3, "screenOffAfter": 0}'
waitfor "d['locked']" 10 && result idle-locks PASS || result idle-locks FAIL "$(st)"
wtype "shani-test" -k Return
waitfor "not d['locked']" 6
settings '{}'

# ---- the shell in Marathi (shani/i18n/mr.json), read as a screen reader would -----------
pkill -x qs; sleep 1
SHANI_SHELL_LANG=mr QS_ICON_THEME=Adwaita QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 qs -p /work/shani >>/work/out/logs/qs.log 2>&1 &
waitfor "d['language'] == 'mr' and d['sampleWord'] == 'सूचना'" 15 && result i18n-marathi-catalog PASS || result i18n-marathi-catalog FAIL "$(q "['language']") / $(q "['sampleWord']")"
if [ -f /testbed/lib/a11y_client.py ]; then
    sleep 2
    timeout 20 python3 /testbed/lib/a11y_client.py find "button:झटपट सेटिंग्ज" >/dev/null 2>&1 \
        && result i18n-marathi-bar PASS || result i18n-marathi-bar FAIL "$(timeout 20 python3 /testbed/lib/a11y_client.py observe 2>&1 | head -8 | tr '\n' ';')"
fi

echo "--- qs warnings"; grep -E "WARN|ERROR" /work/out/logs/qs.log | grep -v -E "ZINK|libvulkan" | sort | uniq -c | sort -rn | head -15
[ "$fail" = 0 ]
