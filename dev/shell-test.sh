#!/bin/sh
# usage: shell-test.sh   (inside shani-shell-dev, repo at /work)
#   docker run --rm -v "$PWD":/work shani-shell-dev sh /work/dev/shell-test.sh
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
st() { qs -p /work/shani ipc call shani state 2>/dev/null; }
q() { st | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)"; }
ipc() { qs -p /work/shani ipc call shani "$@" >/dev/null 2>&1; }
shot() { sleep "${2:-0.8}"; grim "$SHOTS/$1.png"; }
settings() { printf '%s' "$1" > "$SHANI_SHELL_SETTINGS"; sleep 1.5; }
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
notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
waitfor "d['notifications'] == 1 and d['popups'] == 1" 4 \
    && result notification-popup PASS || result notification-popup FAIL "$(st)"
shot 21-notification-popup 0.3
ipc dnd
notify-send -a Backup "Backup finished" "142 files, 3.1 GB"
waitfor "d['notifications'] == 2" 4 && sleep 0.3
[ "$(q "['popups']")" -le 1 ] && [ "$(q "['dnd']")" = True ] \
    && result dnd-suppresses-popups PASS || result dnd-suppresses-popups FAIL "$(st)"
notify-send -u critical -a Power "Battery low" "5% left"
waitfor "d['popups'] >= 1 and d['notifications'] == 3" 4 \
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
shot 43-launcher-file 0.4
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
settings '{"wallpaper": "/tmp/lens-bg.png"}'
waitfor "d['wallpaper'] == '/tmp/lens-bg.png'" 3 && result wallpaper-follows-setting PASS || result wallpaper-follows-setting FAIL
niri msg action focus-workspace 3
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

# ---- lock screen: PAM, wrong then right ----------------------------------------
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

# ---- idle: the lock stage fires on its own --------------------------------------
waitfor "not d['locked']" 4 || { echo "still locked before the idle check"; exit 1; }
settings '{"dimAfter": 0, "lockAfter": 3, "screenOffAfter": 0}'
waitfor "d['locked']" 10 && result idle-locks PASS || result idle-locks FAIL "$(st)"
wtype "shani-test" -k Return
waitfor "not d['locked']" 6
settings '{}'

echo "--- qs warnings"; grep -E "WARN|ERROR" /work/logs/qs.log | grep -v -E "ZINK|libvulkan" | sort | uniq -c | sort -rn | head -15
[ "$fail" = 0 ]
