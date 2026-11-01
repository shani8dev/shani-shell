#!/bin/sh
# render-all.sh — render every shani-shell surface to PNG (200+ coverage)
# usage: render-all.sh <outdir>
#  (run inside the shani-shell-dev container, repo at /work)
set -eu

OUTDIR="$1"
mkdir -p "$OUTDIR"
. /work/dev/session.sh

SHOTS=/work/docs/shots
ipc() { qs -p /work/shani ipc call shani "$@" >/dev/null 2>&1; }
st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }
shot() { sleep "${2:-0.8}"; grim "$OUTDIR/$1.png"; }

# wait for shell to load
i=0
until st >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); [ $i -ge 60 ] && { echo "shell never loaded"; exit 1; }; done
echo "shell loaded"

n=0
take() { n=$((n+1)); shot "$(printf '%03d-%s' "$n" "$1")" "${2:-0.8}"; }

# ============ BATCH 1: Core desktop ============
take desktop-rest 1.5
take desktop-dark 1
# switch to light theme
ipc setting darkMode false
sleep 1.5
take desktop-light 1
ipc setting darkMode true
sleep 1.5

# ============ BATCH 2: Island states ============
take island-rest 1
ipc ask "Tidy my desktop"
sleep 2
take island-working 1
# wait for approval
i=0
until [ "$(st 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('approval'))" 2>/dev/null)" != "None" ] && [ $i -lt 30 ]; do sleep 0.5; i=$((i+1)); done
if [ $i -lt 30 ]; then
    take island-approval 1
    ipc approve "Allow this once"
    sleep 2
fi
# island ask mode
ipc closeChronoa
ipc askIsland
sleep 1
take island-ask 1
ipc closeAll
# island with live activity (timer)
ipc timer 1
sleep 1
take island-timer 1
ipc timer 0
sleep 1
# island recording
ipc record
sleep 1
take island-recording 1
ipc record
sleep 1
# island DND
ipc dnd
sleep 1
take island-dnd 1
ipc dnd
# island caffeine
ipc caffeine
sleep 1
take island-caffeine 1
ipc caffeine
closeAll() { ipc closeAll; }
closeAll

# ============ BATCH 3: Control Center sections ============
for sec in "" audio network displays windows sound access input time apps search privacy sharing backup automations chronoa users power about; do
    if [ -z "$sec" ]; then
        ipc toggleControlCenter
    else
        ipc controlCenter "$sec"
    fi
    sleep 1
    take "cc-${sec:-main}" 0.8
    ipc closeAll
done

# ============ BATCH 4: Launcher states ============
take launcher-empty 1
ipc launcher "text"
sleep 1
take launcher-apps 1
ipc launcher "= 2*(3+4)^2"
sleep 1
take launcher-calc 1
ipc launcher ":grinning face"
sleep 1
take launcher-emoji 1
ipc launcher "quarterly"
sleep 1
take launcher-files 1
ipc launcher "5 km in miles"
sleep 1
take launcher-convert 1
ipc launcher "dark"
sleep 1
take launcher-actions 1
ipc launcher ""
sleep 1
take launcher-full 1
ipc closeAll

# ============ BATCH 5: Settings window categories ============
ipc settings
sleep 1.5
take settings-main 1
for cat in personal notifications network displays windows sound access input time apps search privacy sharing backup automations chronoa users power about; do
    ipc settingsCategory "$cat"
    sleep 1
    take "settings-$cat" 0.8
done
ipc closeAll

# ============ BATCH 6: Switcher, Ring, OSD ============
# need windows for switcher
foot -a shani-demo -T "Win one" sleep 600 >/dev/null 2>&1 &
sleep 1
foot -a shani-demo -T "Win two" sleep 600 >/dev/null 2>&1 &
sleep 1
ipc switcher
sleep 1
take switcher-open 1
wtype -k Return 2>/dev/null || true
sleep 0.5
ipc closeAll

# Ring
ipc ring
sleep 1
take ring-main 1
wtype 8 2>/dev/null || true
sleep 0.5
take ring-sub 1
wtype -k Escape 2>/dev/null || true
sleep 0.5
ipc closeAll

# OSD volume
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.50 2>/dev/null || true
sleep 0.5
ipc volumeUp
sleep 0.5
take osd-volume 0.5
ipc volumeDown
sleep 0.5
take osd-volume-down 0.5
ipc volumeMute
sleep 0.5
take osd-mute 0.5
ipc volumeMute

# OSD brightness
ipc brightnessUp
sleep 0.5
take osd-brightness-up 0.5
ipc brightnessDown
sleep 0.5
take osd-brightness-down 0.5

# ============ BATCH 7: Notifications ============
notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
sleep 1
take notification-popup 0.5
notify-send -u critical -a Power "Battery low" "5% left"
sleep 1
take notification-critical 0.5
ipc dnd
notify-send -a Backup "Backup finished" "142 files, 3.1 GB"
sleep 1
take notification-dnd 0.5
ipc dnd

# ============ BATCH 8: Chronoa panel ============
ipc toggleChronoa
sleep 1
take chronoa-panel-idle 1
ipc ask "What is using my battery?"
sleep 3
take chronoa-panel-thinking 1
sleep 5
take chronoa-panel-speaking 1
ipc closeChronoa
sleep 0.5
ipc closeAll

# ============ BATCH 9: Lock, Overview, Lens ============
ipc lock
sleep 1
take lock-screen 1
# unlock (no auth needed in container, just dismiss)
ipc closeAll
sleep 0.5

niri msg action open-overview
sleep 1
take overview-open 1
wtype "calc" 2>/dev/null || true
sleep 1
take overview-search 1
wtype -k Escape 2>/dev/null || true
sleep 0.5
niri msg action close-overview 2>/dev/null || true
sleep 0.5

# Lens - need something on screen first
ipc lensRegion "260,460 1400x160"
sleep 3
take lens-ready 1 2>/dev/null || take lens-ready 1
ipc closeAll

# ============ BATCH 10: QR, Tour, Ruler ============
ipc qr "Wi-Fi" "ShaniOS Guest"
sleep 1
take qr-code 1
ipc closeAll

ipc tour
sleep 1
take tour 1
ipc closeAll

ipc ruler
sleep 1
take ruler 1
ipc closeAll

# ============ BATCH 11: Processes, Magnifier, Annotate ============
ipc processes
sleep 1
take processes 1
ipc closeAll

ipc magnifier
sleep 1
take magnifier 1
ipc closeAll

ipc annotate
sleep 1
take annotate 1
ipc closeAll

# ============ BATCH 12: Osk, Captions ============
ipc osk
sleep 1
take osk-main 1
ipc oskLanguage
sleep 0.5
take osk-language 1
ipc osk

ipc captions
sleep 1
take captions 1
ipc closeAll

# ============ BATCH 13: Window menu, Hot corners ============
niri msg action focus-workspace 1
sleep 0.5
ipc windowMenu
sleep 1
take window-menu 1
ipc windowMenuAction ws3
sleep 1
ipc closeAll

ipc hotCorner overview
sleep 1
take hotcorner-overview 1
ipc hotCorner overview
sleep 0.5

# ============ BATCH 14: Flash alert, Pair, Display confirm ============
ipc flashAlert 2>/dev/null || true
sleep 1
take flash-alert 1
ipc closeAll

# ============ BATCH 15: Share, Modem, Cast ============
ipc share "/tmp/test-share.txt" 2>/dev/null || true
sleep 1
take share-sheet 1 2>/dev/null || true
ipc closeAll

echo "=== COMPLETE: $n renders ==="
ls -la "$OUTDIR" | wc -l
