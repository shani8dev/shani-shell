#!/bin/sh
# render.sh — render every shani-shell surface to PNG
#
# usage: render.sh [outdir]                 # full render of all surfaces
#        render.sh --one <name> [ipc-cmd] [delay]   # render ONE surface for systematic review
#
# Full render: renders every shell surface (desktop, island, CC tiles, launcher,
# settings, switcher, ring, OSD, notifications, Chronoa panel, lock, overview,
# lens, QR, tour, ruler, processes, magnifier, annotate, osk, captions, window
# menu, hot corners, flash alert, share) to numbered PNGs in <outdir>.
#
# Single-surface mode: renders just one surface so you can look at the image,
# check the corresponding QML code, fix any issue, then re-render and verify.
#
# KEY: IPC commands with arguments use `eval` so multi-word args (e.g.
#      `launcher "text"`) are passed as a single quoted argument, not split.
set -eu

MODE="full"
OUTDIR=""
ONE_NAME=""
ONE_IPC=""
ONE_DELAY="1.5"

# ---- parse args -----------------------------------------------------------
if [ "$1" = "--one" ]; then
    MODE="one"
    ONE_NAME="$2"
    ONE_IPC="${3:-}"
    ONE_DELAY="${4:-1.5}"
    shift 4
elif [ $# -ge 1 ]; then
    OUTDIR="$1"
    shift
fi

mkdir -p "$OUTDIR"
. /work/dev/session.sh

# ---- helpers --------------------------------------------------------------
# ipc: send a command to the shell. Uses eval so multi-word args stay quoted.
ipc() { eval "qs -p /work/shani ipc call shani $*" >/dev/null 2>&1; }
st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }
close_all() { eval "qs -p /work/shani ipc call shani closeAll" >/dev/null 2>&1; sleep 0.8; }

# wait for shell to load
i=0
until st >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); [ $i -ge 60 ] && { echo "shell never loaded"; exit 1; }; done
echo "shell loaded"

n=0

# ---- full-render capture helper -------------------------------------------
capture() {
    local name="$1"
    local cmd="$2"
    local delay="${3:-1.5}"
    close_all
    sleep 0.3
    if [ -n "$cmd" ]; then
        eval "qs -p /work/shani ipc call shani $cmd" >/dev/null 2>&1
    fi
    sleep "$delay"
    grim "$OUTDIR/$name.png"
    n=$((n+1))
    echo "[$n] $name"
}

# ---- single-surface mode --------------------------------------------------
if [ "$MODE" = "one" ]; then
    close_all
    sleep 0.3
    if [ -n "$ONE_IPC" ]; then
        eval "qs -p /work/shani ipc call shani $ONE_IPC" >/dev/null 2>&1
    fi
    sleep "$ONE_DELAY"
    grim "$OUTDIR/${ONE_NAME}.png"
    echo "captured $OUTDIR/${ONE_NAME}.png"
    exit 0
fi

# ===========================================================================
# FULL RENDER — every surface, one by one
# ===========================================================================

# ---- BATCH 1: Core desktop --------------------------------------------------
capture "01-desktop-rest" "" 1.5

# Theme: light
eval "qs -p /work/shani ipc call shani setting darkMode false" >/dev/null 2>&1; sleep 2
capture "02-desktop-light" "" 0.5

# Theme: dark
eval "qs -p /work/shani ipc call shani setting darkMode true" >/dev/null 2>&1; sleep 2
capture "03-desktop-dark" "" 0.5

# ---- BATCH 2: Island states -----------------------------------------------
capture "04-island-rest" "" 1
eval "qs -p /work/shani ipc call shani ask 'Tidy my desktop'" >/dev/null 2>&1; sleep 2.5
capture "05-island-working" "" 0.5
# wait for approval
i=0
until [ "$(st 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('approval'))" 2>/dev/null)" != "None" ] && [ $i -lt 30 ]; do sleep 0.5; i=$((i+1)); done
if [ $i -lt 30 ]; then
    capture "06-island-approval" "" 0.5
    eval "qs -p /work/shani ipc call shani approve 'Allow this once'" >/dev/null 2>&1; sleep 2
fi
close_all
eval "qs -p /work/shani ipc call shani askIsland" >/dev/null 2>&1; sleep 1.5
capture "07-island-ask" "" 0.5
close_all
eval "qs -p /work/shani ipc call shani timer 1" >/dev/null 2>&1; sleep 1.5
capture "08-island-timer" "" 0.5
eval "qs -p /work/shani ipc call shani timer 0" >/dev/null 2>&1; sleep 0.5
eval "qs -p /work/shani ipc call shani record" >/dev/null 2>&1; sleep 1.5
capture "09-island-recording" "" 0.5
eval "qs -p /work/shani ipc call shani record" >/dev/null 2>&1; sleep 0.5
eval "qs -p /work/shani ipc call shani dnd" >/dev/null 2>&1; sleep 1.5
capture "10-island-dnd" "" 0.5
eval "qs -p /work/shani ipc call shani dnd" >/dev/null 2>&1; sleep 0.5
eval "qs -p /work/shani ipc call shani caffeine" >/dev/null 2>&1; sleep 1.5
capture "11-island-caffeine" "" 0.5
eval "qs -p /work/shani ipc call shani caffeine" >/dev/null 2>&1; sleep 0.5
close_all

# ---- BATCH 3: Control Center all sections -------------------------------
capture "12-cc-main" "toggleControlCenter" 1.5
for sec in audio network displays windows sound access input time apps search privacy sharing backup automations chronoa users power about; do
    capture "cc-${sec}" "controlCenter $sec" 1.2
done
close_all

# ---- BATCH 4: Launcher states --------------------------------------------
capture "launcher-empty" "launcher ''" 1.5
eval "qs -p /work/shani ipc call shani launcher text" >/dev/null 2>&1; sleep 1.5
capture "launcher-apps" "" 0.5
eval "qs -p /work/shani ipc call shani launcher '= 2*(3+4)^2'" >/dev/null 2>&1; sleep 1.5
capture "launcher-calc" "" 0.5
eval "qs -p /work/shani ipc call shani launcher ':grinning face'" >/dev/null 2>&1; sleep 1.5
capture "launcher-emoji" "" 0.5
eval "qs -p /work/shani ipc call shani launcher quarterly" >/dev/null 2>&1; sleep 1.5
capture "launcher-files" "" 0.5
eval "qs -p /work/shani ipc call shani launcher '5 km in miles'" >/dev/null 2>&1; sleep 1.5
capture "launcher-convert" "" 0.5
eval "qs -p /work/shani ipc call shani launcher dark" >/dev/null 2>&1; sleep 1.5
capture "launcher-actions" "" 0.5
eval "qs -p /work/shani ipc call shani launcher ''" >/dev/null 2>&1; sleep 1.5
capture "launcher-full" "" 0.5
close_all

# ---- BATCH 5: Settings main + all categories ------------------------------
capture "settings-main" "settings" 2
for cat in personal notifications network displays windows sound access input time apps search privacy sharing backup automations chronoa users power about; do
    capture "settings-${cat}" "settingsCategory $cat" 1.5
done
close_all

# ---- BATCH 6: Switcher (needs windows) -----------------------------------
foot -a shani-demo -T "Win one" sleep 600 >/dev/null 2>&1 &
sleep 1
foot -a shani-demo -T "Win two" sleep 600 >/dev/null 2>&1 &
sleep 1
capture "switcher-open" "switcher" 1.5
close_all

# ---- BATCH 7: Ring -------------------------------------------------------
capture "ring-main" "ring" 1.5
close_all

# ---- BATCH 8: OSD --------------------------------------------------------
eval "qs -p /work/shani ipc call shani volumeUp" >/dev/null 2>&1; sleep 1
capture "osd-volume" "" 0.5
eval "qs -p /work/shani ipc call shani brightnessUp" >/dev/null 2>&1; sleep 1
capture "osd-brightness-up" "" 0.5
eval "qs -p /work/shani ipc call shani volumeMute" >/dev/null 2>&1; sleep 1
capture "osd-mute" "" 0.5
eval "qs -p /work/shani ipc call shani volumeMute" >/dev/null 2>&1; sleep 0.5

# ---- BATCH 9: Notifications ----------------------------------------------
notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
sleep 1
capture "notification-popup" "" 0.5
notify-send -u critical -a Power "Battery low" "5% left"
sleep 1
capture "notification-critical" "" 0.5
eval "qs -p /work/shani ipc call shani dnd" >/dev/null 2>&1
notify-send -a Backup "Backup finished" "142 files, 3.1 GB"
sleep 1
capture "notification-dnd" "" 0.5
eval "qs -p /work/shani ipc call shani dnd" >/dev/null 2>&1

# ---- BATCH 10: Chronoa panel ---------------------------------------------
capture "chronoa-panel-idle" "toggleChronoa" 1.5
eval "qs -p /work/shani ipc call shani ask 'What is using my battery?'" >/dev/null 2>&1; sleep 3
capture "chronoa-panel-thinking" "" 0.5
sleep 5
capture "chronoa-panel-speaking" "" 0.5
eval "qs -p /work/shani ipc call shani closeChronoa" >/dev/null 2>&1; sleep 0.5
close_all

# ---- BATCH 11: Lock, Overview --------------------------------------------
capture "lock-screen" "lock" 1.5
close_all
sleep 0.5
niri msg action open-overview; sleep 1.5
capture "overview-open" "" 0.5
niri msg action close-overview 2>/dev/null || true
sleep 0.5
close_all

# ---- BATCH 12: QR, Tour, Ruler -------------------------------------------
capture "qr-code" "qr 'Wi-Fi' 'ShaniOS Guest'" 1.5
close_all
capture "tour" "tour" 1.5
close_all
capture "ruler" "ruler" 1.5
close_all

# ---- BATCH 13: Lens ------------------------------------------------------
capture "lens-ready" "lensRegion '260,460 1400x160'" 3.5
close_all

# ---- BATCH 14: Processes, Magnifier, Annotate ----------------------------
capture "processes" "processes" 1.5
close_all
capture "magnifier" "magnifier" 1.5
close_all
capture "annotate" "annotate" 1.5
close_all

# ---- BATCH 15: Osk, Captions ---------------------------------------------
capture "osk-main" "osk" 1.5
eval "qs -p /work/shani ipc call shani oskLanguage" >/dev/null 2>&1; sleep 0.5
capture "osk-language" "" 0.5
eval "qs -p /work/shani ipc call shani osk" >/dev/null 2>&1
close_all
capture "captions" "captions" 1.5
close_all

# ---- BATCH 16: Window menu, Hot corners ----------------------------------
niri msg action focus-workspace 1; sleep 0.5
capture "window-menu" "windowMenu" 1.5
eval "qs -p /work/shani ipc call shani windowMenuAction ws3" >/dev/null 2>&1; sleep 1
close_all
eval "qs -p /work/shani ipc call shani hotCorner overview" >/dev/null 2>&1; sleep 1.5
capture "hotcorner-overview" "" 0.5
eval "qs -p /work/shani ipc call shani hotCorner overview" >/dev/null 2>&1; sleep 0.5

# ---- BATCH 17: Flash alert -----------------------------------------------
eval "qs -p /work/shani ipc call shani flashAlert" >/dev/null 2>&1 || true
sleep 1.5
capture "flash-alert" "" 0.5
close_all

# ---- BATCH 18: Share -----------------------------------------------------
touch /tmp/test-share.txt
eval "qs -p /work/shani ipc call shani share '/tmp/test-share.txt'" >/dev/null 2>&1 || true
sleep 1.5
capture "share-sheet" "" 0.5
close_all

echo "=== COMPLETE: $n renders ==="
ls "$OUTDIR" | wc -l
