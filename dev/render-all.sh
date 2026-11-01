#!/bin/sh
# render-all.sh — render every shani-shell surface to PNG
# usage: render-all.sh <outdir>
#  (run inside the shani-shell-dev container, repo at /work)
set -eu

OUTDIR="$1"
mkdir -p "$OUTDIR"
. /work/dev/session.sh

SHOTS=/work/docs/shots
ipc() { qs -p /work/shani ipc call shani "$@" >/dev/null 2>&1; }
st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }
shot() { sleep "${2:-1}"; grim "$OUTDIR/$1.png"; }

# wait for shell to load
i=0
until st >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); [ $i -ge 60 ] && { echo "shell never loaded"; exit 1; }; done
echo "shell loaded"

# 1: bare desktop — bar + island + dock (rest state)
shot 01-desktop-rest 1.5

# 2: island working (ask something that triggers tool steps)
ipc ask "Tidy my desktop"
sleep 2
shot 02-island-working 1

# 3: island approval (mock-chronoa sends an approval for "tidy" queries)
i=0
until [ "$(st 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('approval'))" 2>/dev/null)" != "None" ] && [ $i -lt 40 ]; do sleep 0.5; i=$((i+1)); done
if [ $i -lt 40 ]; then
    shot 03-island-approval 1
else
    echo "no approval appeared, skipping 03"
fi

# 4: island ask mode (click the line -> question field)
ipc closeChronoa
ipc askIsland
sleep 1
shot 04-island-ask 1

# 5: sidebar / control center
ipc closeAll
ipc toggleControlCenter
sleep 1
shot 05-sidebar 1

# 6: sidebar audio tiles
ipc controlCenter audio
sleep 1
shot 06-sidebar-audio 1

# 7: launcher empty (frequent apps)
ipc closeAll
ipc launcher ""
sleep 1
shot 07-launcher-empty 1

# 8: launcher with query (apps)
ipc launcher "text"
sleep 1
shot 08-launcher-apps 1

# 9: launcher calculation
ipc launcher "= 2*(3+4)^2"
sleep 1
shot 09-launcher-calc 1

# 10: chronoa panel (full conversation)
ipc closeAll
ipc toggleChronoa
sleep 1
shot 10-chronoa-panel 1

# 11: settings window
ipc settings
sleep 1.5
shot 11-settings 1

# 12: settings appearance
ipc settingsCategory appearance
sleep 1
shot 12-settings-appearance 1

# 13: switcher (alt-tab)
ipc closeAll
niri msg action focus-workspace 1
sleep 0.5
ipc switcher
sleep 1
shot 13-switcher 1

# 14: ring (pie menu)
ipc closeAll
ipc ring
sleep 1
shot 14-ring 1

# 15: notification popup
ipc closeAll
notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
sleep 1
shot 15-notification 1

# 16: dock (always visible, capture as part of desktop)
shot 16-dock 1

echo "ALL RENDERS DONE in $OUTDIR"
ls -la "$OUTDIR"
