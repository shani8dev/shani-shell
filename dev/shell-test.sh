#!/bin/sh
# usage: shell-test.sh   (inside shani-shell-dev, repo at /work)
#   docker run --rm --cap-add SYS_PTRACE -v "$PWD":/work shani-shell-dev sh /work/dev/shell-test.sh
#   (SYS_PTRACE: the idle-cost check traces what the shell starts; SHELL_TEST_ONLY=idle runs just that)
# Every check drives the real thing — wpctl, notify-send, niri actions, wtype
# keystrokes, gdbus into the bridge, the settings file — then reads the shell's
# own answer (`ipc call shani state`). Prints RESULT lines; shots in docs/shots.
. /work/dev/session.sh
SHOTS=/work/docs/shots
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
settings() { python3 -c 'import json,sys; d={"dimAfter":0,"lockAfter":0,"screenOffAfter":0,"lockAfterBattery":0,"screenOffAfterBattery":0}; d.update(json.loads(sys.argv[1])); print(json.dumps(d), end="")' "$1" > "$SHANI_SHELL_SETTINGS"; sleep 1.5; }
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
bad=$(grep -E "TypeError|ReferenceError|Unable to assign|is not a function|is not defined|caused by|ERROR" /work/logs/qs.log \
      | grep -v -E "ZINK|libvulkan|polkit" | head -5)
[ -z "$bad" ] && result shell-loads-clean PASS || { result shell-loads-clean FAIL; echo "$bad"; }
# nothing below means anything if the shell is not running
if ! st >/dev/null 2>&1 || [ -z "$(st)" ]; then
    echo "the shell is not running — stopping here"; tail -20 /work/logs/qs.log; exit 1
fi
[ "$(q "['settingsLoaded']")" = True ] && result settings-loaded PASS || result settings-loaded FAIL

# ---- what the shell costs while nothing happens ---------------------------------------
# 30 s idle: the programs the shell starts (every poll that forks is a
# wakeup on a laptop), the shell's own CPU time, and its memory. The budget is
# the point: a new always-on poller shows up here as a FAIL, not as a battery
# complaint months later.
sleep 3
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
# SHELL_TEST_ONLY=idle: just this, for working on what the shell costs
[ "${SHELL_TEST_ONLY:-}" = idle ] && exit $fail

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
    ipc toggleControlCenter; lint control-centre; ipc closeAll
    ipc launcher ""; lint launcher; ipc closeAll
    for c in personal notifications network displays windows sound access input time apps search printers sharing backup automations privacy chronoa account users power about ; do ipc settingsCategory $c; lint "settings-$c"; done; ipc closeAll
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
grep -q "The file: /root/Documents/quarterly-report.txt" /work/logs/mock.log \
    && result launcher-ctrl-enter-asks-about-file PASS || result launcher-ctrl-enter-asks-about-file FAIL "$(tail -2 /work/logs/mock.log)"
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
magick -size 64x64 xc:none -fill '#7fd1c1' -draw 'circle 32,32 32,4' -fill '#08110f' \
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
    || result dictation-transcribes FAIL "$(tail -3 /work/logs/qs.log)"
waitfor "d['topResult'].endswith(d['dictated'])" 4 && result dictation-types-into-field PASS || result dictation-types-into-field FAIL "$(q "['topResult']")"
ipc osk
ipc closeAll
pactl set-default-source mic 2>/dev/null

# ---- launcher: emoji, and what you use ranks first ------------------------------
ipc launcher ":grinning face"
waitfor "d['topResult'].startswith('😀')" 4 && result launcher-emoji PASS || result launcher-emoji FAIL "$(q "['topResult']")"
ipc launcher "text edit"
waitfor "d['topResult'] == 'Text Editor'" 3
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
shot 45-sidebar-shelf 0.6
ipc closeAll

# ---- the light theme, and the accent from the wallpaper ------------------------
ipc setting darkMode false
waitfor "d['bg'] == '#eef1f4'" 3 && result theme-follows-dark-style PASS || result theme-follows-dark-style FAIL "$(q "['bg']")"
shot 47-light-desktop 0.6
ipc controlCenter ""
shot 48-light-sidebar 0.8
ipc closeAll
ipc setting darkMode true
waitfor "d['bg'] == '#0b0d12'" 3
magick -size 1920x1080 gradient:'#ff7a18'-'#ffb347' /tmp/orange.png
settings '{"wallpaperLight": "", "wallpaperDark": "", "wallpaper": "/tmp/orange.png", "accentFromWallpaper": true}'
# an orange wallpaper must give an orange accent: red well above blue
waitfor "int(d['accent'][1:3],16) > int(d['accent'][5:7],16) + 60" 10 && result accent-from-wallpaper PASS "$(q "['accent']")" \
    || result accent-from-wallpaper FAIL "$(q "['accent']")"
shot 49-accent-orange 0.6
settings '{}'

# ---- day/night wallpaper -----------------------------------------------------------
settings '{"wallpaperLight": "/tmp/lens-bg.png", "wallpaperDark": "/tmp/orange.png"}'
waitfor "d['wallpaperNow'] == '/tmp/orange.png'" 3 && ipc setting darkMode false \
    && waitfor "d['wallpaperNow'] == '/tmp/lens-bg.png'" 3 && result wallpaper-follows-style PASS || result wallpaper-follows-style FAIL "$(q "['wallpaperNow']")"
ipc setting darkMode true
settings '{}'

# ---- fullscreen holds notifications ---------------------------------------------
niri msg action focus-workspace 1; sleep 0.4
niri msg action fullscreen-window
waitfor "d['fullscreen'] and d['quiet']" 4 && result fullscreen-is-quiet PASS || result fullscreen-is-quiet FAIL "$(st)"
p0=$(q "['popups']")
notify-send -a Mail "During the film" "should wait"
sleep 1
[ "$(q "['popups']")" -le "$p0" ] && result fullscreen-holds-notifications PASS || result fullscreen-holds-notifications FAIL
niri msg action fullscreen-window
waitfor "not d['fullscreen']" 4

# ---- screenshot -> annotate / ask -----------------------------------------------
n0=$(q "['notifications']")
niri msg action screenshot-screen
waitfor "d['lastScreenshot'] != ''" 6 && result screenshot-reaches-shell PASS "$(q "['lastScreenshot']")" || result screenshot-reaches-shell FAIL
waitfor "d['notifications'] > $n0" 4 && result screenshot-offers-actions PASS || result screenshot-offers-actions FAIL
shot 51-screenshot-offer 0.6

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
ipc launcher "12*12"
waitfor "'From Calculator' in d['launcherSections']" 12 && result launcher-search-providers PASS || result launcher-search-providers FAIL "$(q "['launcherSections']")"
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
grep -q "Summarise these notifications" /work/logs/mock.log && result notifications-summary-asks-chronoa PASS || result notifications-summary-asks-chronoa FAIL
settings '{"hiddenTiles": ["lens"], "tileOrder": ["chronoa", "dnd"]}'
ipc controlCenter ""
waitfor "d['tilesShown'][:2] == ['chronoa', 'dnd'] and 'lens' not in d['tilesShown']" 4 && result tiles-reordered-and-hidden PASS || result tiles-reordered-and-hidden FAIL "$(q "['tilesShown']")"
shot 55-sidebar-tiles-mic 0.6
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
waitfor "d['lens'] == 'idle'" 4 && grep -q "look_at_image: /run/user/0/shani-lens-" /work/logs/mock.log \
    && grep -q "SHANI LENS READS THIS" /work/logs/mock.log \
    && result lens-asks-chronoa-with-image PASS || result lens-asks-chronoa-with-image FAIL "$(tail -3 /work/logs/mock.log)"
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
f1=$(q "['flashes']")
notify-send -a Calendar "Held back" "dnd"
sleep 1
[ "$(q "['flashes']")" = "$f1" ] && result flash-respects-dnd PASS || result flash-respects-dnd FAIL
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
waitfor "d['settingsCat'] == '' and d['expanded'] == 'settings'" 3
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
wtype -k Return
waitfor "d['expanded'] == 'settings' and d['settingsCat'] == 'time'" 3 && result launcher-opens-settings-category PASS || result launcher-opens-settings-category FAIL "$(st)"
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
[ "$(g icon-theme)" = "'Papirus-Dark'" ] && [ "$(g accent-color)" = "'teal'" ] && [ "$(g monospace-font-name)" = "'JetBrains Mono 11'" ] \
    && result default-look-for-apps PASS || result default-look-for-apps FAIL "$(g icon-theme) $(g accent-color) $(g monospace-font-name)"
settings '{"accentName": "purple"}'
waitfor "d['accent'] == '#dc8add'" 3 && [ "$(g accent-color)" = "'purple'" ] && result accent-choice PASS || result accent-choice FAIL "$(q "['accent']") $(g accent-color)"

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
    waitfor "d['cpuTemp'] > 10 and d['cpuTemp'] < 120" 8 && result cpu-temperature PASS "$(q "['cpuTemp']") °C" || result cpu-temperature FAIL "$(q "['cpuTemp']")"
else
    result cpu-temperature SKIP "no CPU sensor visible here"
fi

# ---- the agenda: events from Evolution Data Server's own "Personal" calendar ------------
cal=/root/.local/share/evolution/calendar/system
mkdir -p $cal
t1=$(date -u -d '+3 hours' +%Y%m%dT%H%M00Z); t2=$(date -u -d '+4 hours' +%Y%m%dT%H%M00Z)
w1=$(date -u -d '-7 days +5 hours' +%Y%m%dT%H%M00Z); w2=$(date -u -d '-7 days +6 hours' +%Y%m%dT%H%M00Z)
printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//shani//test//EN\r\nBEGIN:VEVENT\r\nUID:one@test\r\nDTSTAMP:%s\r\nDTSTART:%s\r\nDTEND:%s\r\nSUMMARY:Design review\r\nLOCATION:Room 2\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:weekly@test\r\nDTSTAMP:%s\r\nDTSTART:%s\r\nDTEND:%s\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:Weekly sync\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$t1" "$t1" "$t2" "$w1" "$w1" "$w2" > $cal/calendar.ics
ipc agendaRefresh
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
echo '{"call": {"path": "/c/1", "number": "+919844444444", "state": "ringing-in", "incoming": true}}' > /tmp/modem-ask
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

# ---- the first-login tour: five cards, Enter through them, remembered ------------------
ipc tour
waitfor "d['tour']" 3 && result tour-opens PASS || result tour-opens FAIL
shot 91-tour 0.6
for i in 1 2 3 4 5; do wtype -k Return; sleep 0.3; done
waitfor "not d['tour']" 3; sleep 1   # the settings file is written a moment later
grep -q '"tourSeen": *true' /tmp/shani-settings.json && result tour-finishes-and-remembers PASS || result tour-finishes-and-remembers FAIL "$(grep -o '"tourSeen"[^,]*' /tmp/shani-settings.json)"
settings '{}'

# ---- search inside Settings: "proxy" opens Network ----------------------------------
ipc settings
waitfor "d['expanded'] == 'settings' and d['settingsCat'] == ''" 3
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
waitfor "d['callRecording']" 4 && result call-record-starts PASS || result call-record-starts FAIL "$(tail -3 /work/logs/qs.log)"
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
ls /root/Pictures/Screenshots/Drawing*.png >/dev/null 2>&1 && result annotate-saves PASS || result annotate-saves FAIL "$(tail -2 /work/logs/qs.log)"
wtype -k Escape
waitfor "not d['annotate']" 3 && result annotate-closes PASS || result annotate-closes FAIL

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
wtype "shani-test" -k Return
waitfor "not d['locked']" 6

# ---- dynamic lock: the paired phone goes away → locked after the grace ---------------
settings '{"dynamicLockDevice": "AA:BB:CC:DD:EE:FF"}'
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
SHANI_SHELL_LANG=mr QS_ICON_THEME=Adwaita QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 qs -p /work/shani >>/work/logs/qs.log 2>&1 &
waitfor "d['language'] == 'mr' and d['sampleWord'] == 'सूचना'" 15 && result i18n-marathi-catalog PASS || result i18n-marathi-catalog FAIL "$(q "['language']") / $(q "['sampleWord']")"
if [ -f /testbed/lib/a11y_client.py ]; then
    sleep 2
    timeout 20 python3 /testbed/lib/a11y_client.py find "button:झटपट सेटिंग्ज" >/dev/null 2>&1 \
        && result i18n-marathi-bar PASS || result i18n-marathi-bar FAIL "$(timeout 20 python3 /testbed/lib/a11y_client.py observe 2>&1 | head -8 | tr '\n' ';')"
fi

echo "--- qs warnings"; grep -E "WARN|ERROR" /work/logs/qs.log | grep -v -E "ZINK|libvulkan" | sort | uniq -c | sort -rn | head -15
[ "$fail" = 0 ]
