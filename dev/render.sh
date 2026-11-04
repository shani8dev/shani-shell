#!/bin/sh
# render.sh — render every shani-shell surface to PNG
#
# usage: sh /work/dev/render.sh [mode] [outdir]        (inside shani-shell-dev, repo at /work)
#        sh /work/dev/render.sh --one <name> [ipc-cmd] [delay] [outdir]
#
# modes:
#   shell    the shell's surfaces (default)                    → <outdir>/shell/
#   greeter  the greetd login screen (creates throwaway users) → <outdir>/greeter/
#   setup    the first-login Setup wizard (fresh container, no ordinary accounts)
#                                                              → <outdir>/setup/
#   all      setup → greeter → shell, in this order, with a full teardown between
#
# default outdir: /work/out/renders
#
# container runs (host):
#   docker run --rm -v "$PWD":/work shani-shell-dev sh /work/dev/render.sh          # shell
#   docker run --rm -v "$PWD":/work shani-shell-dev sh /work/dev/render.sh greeter
#   docker run --rm -v "$PWD":/work shani-shell-dev sh /work/dev/render.sh setup
#   docker run --rm -v "$PWD":/work shani-shell-dev sh /work/dev/render.sh all
# `setup` refuses to run if an ordinary (UID ≥ 1000) account exists — the wizard is
# only offered on a machine with none. `all` runs it first, before `greeter` creates
# one. `setup` never completes the wizard, so no account is created by the render.
#
# Capturing is only as honest as the activation behind it. Three failure modes the
# old scripts had, fixed here:
#
#   1. `controlCenter <section>` expands a sidebar section; the only valid ids are
#      wifi|bluetooth|vpn|audio|power|access|display|timer|focus|record|phone
#      (Ui.expanded). Passing Settings-style names (network, windows, sound, …) set
#      an expansion no view reads — the PNGs showed the untouched sidebar labelled
#      as those pages. Use `settingsCategory <id>` for Settings pages (full list,
#      with printers and account) and the ids above for the sidebar.
#   2. `flashAlert` and `scratchpadToggle` are not IPC commands at all: the call
#      failed silently and grim photographed the unchanged screen. Flash alerts
#      need `setting flashAlerts true` + a notification; scratchpads are niri
#      windows, not a shell surface, and are not rendered here.
#   3. The lock screen is a Wayland session lock: `closeAll` does NOT unlock it,
#      so every capture after the old "lock-screen" shot photographed a locked
#      screen. The script sets root's password (root:shani-test, as the test
#      suite does) and types it with wtype before continuing.
#
# KEY: IPC commands with arguments use eval so multi-word args (e.g.
#      `launcher "text"`) are passed as a single quoted argument, not split.
set -eu

MODE="shell"
OUTDIR="/work/out/renders"
ONE_NAME=""
ONE_IPC=""
ONE_DELAY="1.5"

# ---- parse args -----------------------------------------------------------
if [ "${1:-}" = "--one" ]; then
    MODE="one"
    ONE_NAME="${2:?usage: render.sh --one <name> [ipc-cmd] [delay] [outdir]}"
    ONE_IPC="${3:-}"
    ONE_DELAY="${4:-1.5}"
    OUTDIR="${5:-/work/out/renders/shell}"
    mkdir -p "$OUTDIR"
elif [ "${1:-}" = "shell" ] || [ "${1:-}" = "greeter" ] || [ "${1:-}" = "setup" ] || [ "${1:-}" = "all" ]; then
    MODE="$1"
    OUTDIR="${2:-$OUTDIR}"
    mkdir -p "$OUTDIR"
elif [ $# -ge 1 ]; then
    # backwards compatible: render.sh <outdir> renders the shell
    OUTDIR="$1"
    mkdir -p "$OUTDIR"
else
    mkdir -p "$OUTDIR"
fi

# ---- shared helpers --------------------------------------------------------
log() { printf '%s\n' "$*" >&2; }

# merge keys into the live settings file (it is watched; applies on write)
settings_merge() {
    SHANI_MERGE_JSON="$1" python3 -c 'import json,os
p = os.environ["SHANI_SHELL_SETTINGS"]
cur = json.load(open(p)) if open(p).read().strip() else {}
cur.update(json.loads(os.environ["SHANI_MERGE_JSON"]))
json.dump(cur, open(p, "w"))'
}

# wait (up to $2 * 0.5 s, default 15 s) for a python expression over state → 0
waitfor() {
    _i=0
    while [ "$_i" -lt "${2:-30}" ]; do
        st 2>/dev/null | python3 -c "import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
sys.exit(0 if ($1) else 1)" >/dev/null 2>&1 && return 0
        sleep 0.5
        _i=$((_i+1))
    done
    return 1
}

# teardown between compositor sessions (used by `all`): everything from a phase
# is killed and the wayland sockets are removed before the next phase boots one
teardown() {
    pkill -f 'qs -c shani' 2>/dev/null || true
    pkill -f 'chronoa-bridge.py' 2>/dev/null || true
    pkill -f 'mock-chronoa.py' 2>/dev/null || true
    pkill -f 'shani-setup' 2>/dev/null || true
    pkill -f 'fake-greetd.py' 2>/dev/null || true
    pkill -f 'fake-modem.py' 2>/dev/null || true
    pkill -f 'fake-bt-agent.py' 2>/dev/null || true
    pkill -x niri 2>/dev/null || true
    pkill -x weston 2>/dev/null || true
    pkill -x foot 2>/dev/null || true
    sleep 1
    rm -f "$XDG_RUNTIME_DIR"/wayland-parent* "$XDG_RUNTIME_DIR"/wayland-1* "$XDG_RUNTIME_DIR"/niri.*.sock /run/user/0/wayland-parent* /run/user/0/wayland-1* 2>/dev/null || true
}

# ===========================================================================
# SINGLE-SURFACE MODE
# ===========================================================================
if [ "$MODE" = "one" ]; then
    . /work/dev/session.sh
    st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }
    i=0
    until st >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); [ $i -ge 60 ] && { echo "shell never loaded"; exit 1; }; done
    # PRERUN: shell commands to stage the scene first (settings, notifications, apps)
    [ -n "${PRERUN:-}" ] && { eval "$PRERUN"; sleep 1.5; }
    eval "qs -p /work/shani ipc call shani dismissAll" >/dev/null 2>&1
    sleep 0.8
    if [ -n "$ONE_IPC" ]; then
        eval "qs -p /work/shani ipc call shani $ONE_IPC" >/dev/null 2>&1
    fi
    sleep "$ONE_DELAY"
    grim "$OUTDIR/$ONE_NAME.png"
    echo "captured $OUTDIR/$ONE_NAME.png"
    exit 0
fi

# ===========================================================================
# GREETER — the greetd login screen, run the way greetd runs it: a bare niri
# whose spawn line is `qs -c shani-greeter`, against dev/fake-greetd.py
# (user "shani" / password "shani"; user "otp" → password then a visible Code:)
# ===========================================================================
render_greeter() {
    _out="$OUTDIR/greeter"
    mkdir -p "$_out"
    export XDG_RUNTIME_DIR=/run/user/0
    mkdir -p "$XDG_RUNTIME_DIR" /work/out/logs
    chmod 700 "$XDG_RUNTIME_DIR"
    teardown

    # the login screen needs accounts to exist; fresh images have none (root only)
    id shani >/dev/null 2>&1 || useradd -m -c "Shani Tester" -s /bin/bash shani
    id asha  >/dev/null 2>&1 || useradd -m -c "Asha Patil" -s /bin/bash asha

    export GREETD_SOCK="$XDG_RUNTIME_DIR/greetd.sock"
    pkill -f fake-greetd.py 2>/dev/null || true
    nohup python3 /work/dev/fake-greetd.py > /work/out/logs/greetd.log 2>&1 &

    mkdir -p /root/.config/quickshell
    ln -sfn /work/greeter /root/.config/quickshell/shani-greeter

    # a minimal greetd niri: full-screen greeter, nothing else
    cat > /tmp/shani-greetd.kdl << 'KDL'
prefer-no-csd

hotkey-overlay {
    skip-at-startup
}

layout {
    background-color "#0b0d12"
}

spawn-at-startup "qs" "-c" "shani-greeter"
KDL

    if ! pgrep -f 'weston --backend=headless' >/dev/null; then
        nohup weston --backend=headless-backend.so --shell=kiosk-shell.so \
            --width=1920 --height=1080 --socket=wayland-parent --idle-time=0 \
            --no-config --log=/work/out/logs/weston.log >/work/out/logs/weston.out 2>&1 &
        sleep 2
    fi

    start_greetd_niri() {
        rm -f "$XDG_RUNTIME_DIR"/wayland-1 "$XDG_RUNTIME_DIR"/wayland-1.lock
        # (an assignment produced by expansion is not parsed as an assignment,
        #  so the variable is exported or unset explicitly)
        if [ -n "${SHANI_GREETER_USER:-}" ]; then
            export SHANI_GREETER_USER
        else
            unset SHANI_GREETER_USER
        fi
        SHANI_GREETER_WALLPAPER=/work/assets/shani-dark.jpg WAYLAND_DISPLAY=wayland-parent \
            nohup niri -c /tmp/shani-greetd.kdl > /work/out/logs/greetd-niri.log 2>&1 &
        _niri=$!
        i=0
        until { pgrep -f 'qs -c shani-greeter' >/dev/null && [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; } || [ $i -ge 40 ]; do
            sleep 0.25; i=$((i + 1))
        done
        export WAYLAND_DISPLAY=wayland-1
        sleep 2   # first frame + focus
    }

    # ---- 1. the login screen (two accounts → the avatar list is shown) -------
    SHANI_GREETER_USER= start_greetd_niri
    grim "$_out/01-greeter-login.png"
    # ---- 2. wrong password → the error state ---------------------------------
    wtype shani; sleep 0.2; wtype -k Return; sleep 0.3
    wtype nope;  sleep 0.2; wtype -k Return; sleep 1.5
    grim "$_out/02-greeter-auth-failed.png"
    kill "$_niri" 2>/dev/null; sleep 0.5

    # ---- 3. OTP account: password then a second, visible prompt --------------
    # fake-greetd expects the otp account's password to be its user name ("otp")
    SHANI_GREETER_USER=otp start_greetd_niri
    wtype otp; sleep 0.2; wtype -k Return; sleep 1.5
    grim "$_out/03-greeter-otp-code.png"
    kill "$_niri" 2>/dev/null; sleep 0.5

    pkill -f fake-greetd.py 2>/dev/null || true
    teardown
    log "greeter renders → $_out"
}

# ===========================================================================
# SETUP — the first-login wizard, the way greetd starts it on a machine with
# no ordinary account. The wizard is walked page by page over IPC (like a
# person clicking); it is NOT completed, so no account is created.
# ===========================================================================
render_setup() {
    if getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { f = 1 } END { exit !f }'; then
        log "refusing: an ordinary account already exists — the first-boot path is only for a machine with none"
        exit 1
    fi
    _out="$OUTDIR/setup"
    mkdir -p "$_out"
    export XDG_RUNTIME_DIR=/run/user/0
    mkdir -p "$XDG_RUNTIME_DIR" /work/out/logs
    chmod 700 "$XDG_RUNTIME_DIR"
    teardown

    export GREETD_SOCK="$XDG_RUNTIME_DIR/greetd.sock"
    pkill -f fake-greetd.py 2>/dev/null || true
    nohup python3 /work/dev/fake-greetd.py > /work/out/logs/greetd.log 2>&1 &
    sleep 0.5

    mkdir -p /root/.config/quickshell
    ln -sfn /work/setup /root/.config/quickshell/shani-setup
    export SHANI_OSK_LAYOUT_TOOL=/work/bridge/osk-layout.py

    cat > /tmp/shani-setup.kdl << 'KDL'
prefer-no-csd

hotkey-overlay {
    skip-at-startup
}

layout {
    background-color "#0b0d12"
}

spawn-at-startup "qs" "-c" "shani-setup"
KDL

    if ! pgrep -f 'weston --backend=headless' >/dev/null; then
        nohup weston --backend=headless-backend.so --shell=kiosk-shell.so \
            --width=1920 --height=1080 --socket=wayland-parent --idle-time=0 \
            --no-config --log=/work/out/logs/weston.log >/work/out/logs/weston.out 2>&1 &
        sleep 2
    fi

    rm -f "$XDG_RUNTIME_DIR"/wayland-1 "$XDG_RUNTIME_DIR"/wayland-1.lock
    SHANI_GREETER_WALLPAPER=/work/assets/shani-dark.jpg WAYLAND_DISPLAY=wayland-parent \
        nohup niri -c /tmp/shani-setup.kdl > /work/out/logs/setup-niri.log 2>&1 &
    _niri=$!
    i=0
    until { pgrep -f 'qs -c shani-setup' >/dev/null && [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; } || [ $i -ge 40 ]; do
        sleep 0.25; i=$((i + 1))
    done
    export WAYLAND_DISPLAY=wayland-1
    sleep 2

    st() { timeout 5 qs -c shani-setup ipc call setup state 2>/dev/null; }
    call() { qs -c shani-setup ipc call setup "$@" >/dev/null 2>&1 || log "warn: setup IPC failed: $*"; }
    shot() { sleep "${2:-0.8}"; grim "$_out/$1.png"; }

    i=0; until st >/dev/null 2>&1 || [ $i -ge 30 ]; do sleep 0.5; i=$((i + 1)); done

    shot 01-setup-welcome 1.5
    call set locale mr_IN.UTF-8; shot 02-setup-marathi 1.0
    call set locale de_DE.UTF-8; shot 03-setup-german 1.0
    call set locale en_US.UTF-8
    call next; sleep 1; call set keymap "us,in+marathi"; shot 04-setup-keyboard 1.0
    call next; sleep 1; shot 05-setup-network 1.0
    call set timezone Asia/Kolkata
    call next; sleep 1; shot 06-setup-time 1.0
    call next; sleep 1; call set fullname "Shani Tester"; sleep 1.5
    shot 07-setup-account 1.0
    call set password shani; call set password2 nope; sleep 0.8
    shot 08-setup-password-mismatch 0.8
    call set password2 shani   # leave the form valid (the wizard itself is never completed)

    kill "$_niri" 2>/dev/null || true
    pkill -f fake-greetd.py 2>/dev/null || true
    teardown
    log "setup renders → $_out"
}

# ===========================================================================
# SHELL — every shell surface, in capture order
# ===========================================================================
render_shell() {
    _out="$OUTDIR/shell"
    mkdir -p "$_out"
    OUTDIR="$_out"
    . /work/dev/session.sh

    ipc() { eval "qs -p /work/shani ipc call shani $*" >/dev/null 2>&1 || true; }
    st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }
    # dismissAll, not closeAll: closeAll only closes the panels Ui tracks, so
    # the ruler banner, the Lens, live captions, the QR/share cards and old
    # notification pop-ups used to stay on screen for every later shot
    close_all() { ipc dismissAll; sleep 0.8; }

    # wait for shell to load
    i=0
    until st >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); [ $i -ge 60 ] && { echo "shell never loaded"; exit 1; }; done
    echo "shell loaded"

    n=0
    # close everything, optionally run an IPC command, wait, capture
    capture() {
        name="$1"; cmd="$2"; delay="${3:-1.5}"
        close_all
        if [ -n "$cmd" ]; then ipc "$cmd"; fi
        sleep "$delay"
        n=$((n+1)); grim "$OUTDIR/$(printf '%02d' "$n")-$name.png"
        echo "[$n] $name"
    }
    # capture what is already on screen (the surface was opened by the caller;
    # closeAll must NOT run first — it would dismiss what is being photographed)
    capture_current() {
        name="$1"; delay="${2:-0.5}"
        sleep "$delay"
        n=$((n+1)); grim "$OUTDIR/$(printf '%02d' "$n")-$name.png"
        echo "[$n] $name"
    }

    # the lock screen unlocks with a password, not IPC — set one, as the test
    # suite does, and unlock through the keyboard after the lock shots
    echo 'root:shani-test' | chpasswd

    # ---- core desktop (window-free: the wallpaper is the subject) ---------------
    capture desktop-rest "" 1.5
    ipc setting darkMode false
    waitfor "not d['dark']" 20 || log "warn: light theme not applied"
    sleep 2.5   # the wallpaper cross-fade is Theme.anim*4 — let it finish
    capture desktop-light "" 0.8
    ipc setting darkMode true
    waitfor "d['dark']" 20 || log "warn: dark theme not applied"
    sleep 2.5   # the wallpaper cross-fade is Theme.anim*4 — let it finish
    capture desktop-dark "" 0.8

    # ---- desktop widgets + island now-playing (fake player) -------------------
    settings_merge '{"desktopWidgets": ["clock", "weather", "stats", "media"]}'
    python3 /work/dev/fake-mpris.py "Render Probe" "Shani" >/dev/null 2>&1 &
    MPRIS=$!
    sleep 2.5
    capture_current desktop-widgets 0.5
    capture_current island-media 0.5  # idle island carries the now-playing activity
    kill $MPRIS 2>/dev/null || true
    settings_merge '{"desktopWidgets": []}'
    sleep 1

    # ---- island ----------------------------------------------------------------
    capture island-rest "" 1
    ipc "ask 'Tidy my desktop'"; sleep 2.5
    capture_current island-working 0.5
    i=0
    until [ "$(st 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('approval'))" 2>/dev/null)" != "None" ] && [ $i -lt 30 ]; do sleep 0.5; i=$((i+1)); done
    if [ $i -lt 30 ]; then
        capture_current island-approval 0.5
        ipc "approve 'Allow this once'"; sleep 2
    fi
    close_all
    ipc askIsland; sleep 1.5
    capture_current island-ask 0.5
    # leaving the ask field open would keep the island in "Enter to send,
    # Esc to close" mode for every shot until the ring's Escape — close it here
    ipc closeChronoa; sleep 0.5
    close_all
    ipc timer 1; sleep 1.5
    capture_current island-timer 0.5
    ipc timer 0; sleep 0.5
    # nested niri gives the recorder a 0×0 frame: this captures the region-select
    # stage (slurp), which is what a person sees first — not a live recording
    ipc record; sleep 1.5
    capture_current island-record 0.5
    ipc record; sleep 0.5           # stop/cancel
    ipc dnd; sleep 1.5
    capture_current island-dnd 0.5
    ipc dnd; sleep 0.5
    ipc caffeine; sleep 1.5
    capture_current island-caffeine 0.5
    ipc caffeine; sleep 0.5
    close_all

    # ---- control centre: main + every section id Ui.expanded understands ------
    # (only these expand a panel in the sidebar; on hardware wifi/bluetooth/vpn/
    #  phone also need an adapter/device, headless captures show the resting UI)
    capture cc-main "toggleControlCenter" 1.5
    for sec in wifi bluetooth vpn audio power access display timer focus record phone; do
        capture "cc-$sec" "controlCenter $sec" 1.2
    done
    close_all

    # ---- dock -------------------------------------------------------------------
    # two throwaway windows, needed only by the dock menu and the window switcher.
    # They run real shells with plausible output (an empty black terminal makes a
    # bad screenshot), and they are killed right after the switcher — every later
    # shot must show the desktop, not two windows.
    foot -a shani-demo -T "Win one" sh -c 'printf "\033[36m~/Projects/shani\033[0m $ shani-deploy --status\n\n  slot   A  (active)  2026.10.27  verified\n  slot   B            2026.10.21  verified\n  next   update ready  ·  312 MB  ·  signed\n\n\033[36m~/Projects/shani\033[0m $ "; sleep 600' >/dev/null 2>&1 &
    foot -a shani-demo -T "Win two" sh -c 'printf "\033[36m~\033[0m $ systemctl --user status shani-shell\n\n  Active: active (running)\n  Main PID: 912 (qs)\n  Memory: 84.2M\n\n\033[36m~\033[0m $ "; sleep 600' >/dev/null 2>&1 &
    sleep 1.5
    ipc dockMenu foot; sleep 1
    capture_current dock-menu 0.5
    ipc "dockMenu ''"; sleep 0.5
    close_all

    # ---- switcher (the two foot windows from the top) ---------------------------
    capture switcher-open "switcher" 1.5
    close_all
    killall -9 foot 2>/dev/null || true     # from here on, window-free
    sleep 1

    # ---- ring (pie menu), at the pointer and one level deep ---------------------
    capture ring-main "ring" 1.5
    close_all
    ipc ringAt 300 500; sleep 1.2
    capture_current ring-at-point 0.5
    wtype -k Escape; sleep 0.5
    close_all
    ipc ring; sleep 1; wtype 8; sleep 1
    capture_current ring-sub 0.5     # Power slice: a ring of its own
    wtype -k Escape; sleep 0.5
    close_all

    # ---- layout switcher ---------------------------------------------------------
    capture layout-switcher "layoutSwitcher" 1.5
    close_all

    # ---- OSD ----------------------------------------------------------------------
    ipc volumeUp;        sleep 1; capture_current osd-volume 0.5
    ipc volumeDown;      sleep 1; capture_current osd-volume-down 0.5
    ipc volumeMute;      sleep 1; capture_current osd-mute 0.5
    ipc volumeMute;      sleep 0.5
    ipc micMute;         sleep 1; capture_current osd-mic-mute 0.5
    ipc micMute;         sleep 0.5
    ipc brightnessUp;    sleep 1; capture_current osd-brightness-up 0.5
    ipc brightnessDown;  sleep 1; capture_current osd-brightness-down 0.5
    brightnessctl set 50% >/dev/null 2>&1 || true

    # ---- notifications -------------------------------------------------------------
    notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
    sleep 1; capture_current notification-popup 0.5
    # notify-send -A waits for the action to be picked, so it would block the
    # render forever; background it and stop it after the shot (the daemon keeps
    # the notification on screen, actions and all)
    notify-send -a Messages -A reply=Reply -A call=Call "Asha" "Are we still on for 6?" &
    actions_pid=$!
    sleep 1; capture_current notification-actions 0.5  # inline actions on the popup
    kill "$actions_pid" 2>/dev/null || true
    notify-send -u critical -a Power "Battery low" "5% left"
    sleep 1; capture_current notification-critical 0.5
    ipc dnd
    notify-send -a Backup "Backup finished" "142 files, 3.1 GB"
    sleep 1; capture_current notification-dnd 0.5
    ipc dnd

    # ---- the SMS/call path (fake modem drives the real shell code) ---------------
    echo '{"modem": {"path": "/m/0", "state": "registered", "locked": "", "operator": "Jio", "signal": 63, "number": "+9198", "voice": true, "messaging": true}}' > /tmp/modem-ask
    sleep 1.5
    echo '{"sms": {"path": "/s/1", "from": "+919811111111", "text": "Your code is 482913", "time": ""}}' > /tmp/modem-ask
    waitfor "'+919811111111' in d['notificationSummaries']" 10
    sleep 0.5; capture_current notification-sms 0.5   # with Reply / Copy actions
    echo '{"call": {"path": "/c/1", "number": "+919844444444", "state": "ringing-in", "incoming": true}}' > /tmp/modem-ask
    waitfor "d['islandActivity'].startswith('Call from +919844444444')" 10
    sleep 0.5; capture_current modem-call 0.5         # island activity + call notification
    echo '{"call": {"path": "/c/1", "number": "+919844444444", "state": "terminated", "incoming": true}}' > /tmp/modem-ask
    sleep 1
    ipc textMessage +919822222222; sleep 1.2
    capture_current modem-sms-composer 0.5
    close_all

    # ---- chronoa panel ------------------------------------------------------------
    capture chronoa-panel-idle "toggleChronoa" 1.5
    ipc "ask 'What is using my battery?'"; sleep 3
    capture_current chronoa-panel-thinking 0.5
    sleep 5
    capture_current chronoa-panel-speaking 0.5
    ipc closeChronoa; sleep 0.5
    close_all

    # ---- lock screen (unlock by typing the password) -------------------------------
    ipc lock; sleep 2
    capture_current lock-screen 0.5
    wtype wrong-password; sleep 0.3; wtype -k Return; sleep 2.5
    capture_current lock-wrong 0.5                    # the refusal, in place
    wtype shani-test; sleep 0.3; wtype -k Return
    waitfor "not d['locked']" 12 || { echo "lock did not unlock — later shots would be of a locked screen"; exit 1; }

    # ---- overview (niri's) + typing in it -------------------------------------------
    niri msg action open-overview || true; sleep 1.5
    capture_current overview-open 0.5
    wtype calc; sleep 1.2
    capture_current overview-search 0.5
    wtype -k Escape; sleep 0.3
    niri msg action close-overview 2>/dev/null || true
    sleep 0.5
    close_all

    # ---- display confirm (niri applies, keeps or reverts) ---------------------------
    ipc display "winit scale 1.5"
    waitfor "d['displayPending']" 10
    capture_current display-confirm 0.5
    ipc displayKeep; sleep 1
    ipc display "winit scale 1"; sleep 2

    # ---- bluetooth pairing (fake agent drives the real shell dialog) ---------------
    rm -f /tmp/bt-ask /tmp/bt-answers
    echo '{"ask": "confirm", "id": 7, "device": "Pixel 8", "passkey": "012345"}' > /tmp/bt-ask
    waitfor "d['btAsk'] == 'confirm:Pixel 8'" 10
    capture_current bt-pair-confirm 0.5
    ipc "btAnswer true ''"; sleep 1
    echo '{"show": "passkey", "device": "K380", "passkey": "045123", "entered": 0}' > /tmp/bt-ask
    waitfor "d['btShow'] == 'K380'" 10
    capture_current bt-passkey 0.5
    echo '{"cancel": true}' > /tmp/bt-ask; sleep 1

    # ---- QR, tour, ruler -------------------------------------------------------------
    capture qr-code "qr 'Wi-Fi' 'ShaniOS Guest'" 1.5
    close_all
    capture tour "tour" 1.5
    close_all
    capture ruler "ruler" 1.5
    close_all

    # ---- lens (frozen selection, read offline) -----------------------------------------
    capture lens-ready "lensRegion '260,460 1400x160'" 3.5
    close_all

    # ---- processes, magnifier, annotate ------------------------------------------------
    capture processes "processes" 1.5
    close_all
    capture magnifier "magnifier" 1.5
    close_all
    capture annotate "annotate" 1.5
    close_all

    # ---- on-screen keyboard -------------------------------------------------------------
    capture osk-main "osk" 1.5
    ipc oskLanguage; sleep 0.5
    capture_current osk-language 0.5
    ipc osk; sleep 0.5
    close_all

    # ---- captions ----------------------------------------------------------------------
    capture captions "captions" 1.5
    close_all

    # ---- launcher: empty → answers → full grid; clipboard mode --------------------------
    capture "launcher-empty" "launcher ''" 1.5
    ipc launcher text;       sleep 1.5; capture_current launcher-apps 0.5
    ipc "launcher '= 2*(3+4)^2'"; sleep 1.5; capture_current launcher-calc 0.5
    ipc "launcher ':grinning face'"; sleep 1.5; capture_current launcher-emoji 0.5
    ipc launcher quarterly;  sleep 1.5; capture_current launcher-files 0.5
    ipc "launcher '5 km in miles'"; sleep 1.5; capture_current launcher-convert 0.5
    ipc launcher dark;       sleep 1.5; capture_current launcher-actions 0.5
    ipc "launcher ''";         sleep 1.5; capture_current launcher-full 0.5
    wl-copy "render clipboard probe"; sleep 0.5
    ipc "launcher 'c probe'";  sleep 1.5; capture_current launcher-clipboard 0.5
    close_all

    # ---- settings window: main + every category (incl. printers and account) -----------
    capture settings-main "settings" 2
    for cat in personal notifications network displays windows sound access input time apps search printers sharing backup automations privacy chronoa account users power about; do
        capture "settings-$cat" "settingsCategory $cat" 1.5
    done
    close_all
    # ---- settings search: highlighted matches + empty state -----------------------
    ipc settings; sleep 1.5
    wtype proxy; sleep 1.5
    capture_current settings-search-proxy 0.5
    # clear the query and show the empty state by searching for nonsense
    # type a query with no matches to exercise the empty state
    close_all
    ipc settings; sleep 1.5
    wtype zzzzzzz; sleep 1.2
    capture_current settings-search-empty 0.5
    close_all
    # ---- settings: search folders empty state -----------------------------------
    settings_merge '{"searchFiles": true, "searchFolders": []}'
    sleep 1
    capture "settings-search-empty-folders" "settingsCategory search" 1.5
    settings_merge '{"searchFiles": false}'
    sleep 0.5
    close_all

    # ---- assistive touch (floating button) ----------------------------------------------
    ipc smartTouch; sleep 1.5
    capture_current assistive-touch 0.5
    ipc smartTouch; sleep 0.5
    close_all

    # ---- flash alerts (edge glow on a notification; opt-in setting) ---------------------
    ipc setting flashAlerts true; sleep 0.5
    notify-send -a Mail "Flash test" "the edge glows"
    sleep 0.6
    capture_current flash-alert 0.5
    ipc setting flashAlerts false; sleep 0.5
    close_all

    # ---- share sheet ----------------------------------------------------------------------
    touch /tmp/test-share.txt
    ipc share /tmp/test-share.txt; sleep 1.5
    capture_current share-sheet 0.5
    rm -f /tmp/test-share.txt
    close_all

    echo "=== COMPLETE: $n renders → $OUTDIR ==="
    ls "$OUTDIR" | wc -l

    # ---- cleanup --------------------------------------------------------------------------
    killall -9 foot 2>/dev/null || true
    rm -f /tmp/test-share.txt /tmp/bt-ask /tmp/bt-answers /tmp/modem-ask /tmp/modem-answers 2>/dev/null || true
}

# ===========================================================================
# dispatch
# ===========================================================================
case "$MODE" in
    shell)   render_shell ;;
    greeter) render_greeter ;;
    setup)   render_setup ;;
    all)
        export XDG_RUNTIME_DIR=/run/user/0
        render_setup
        render_greeter
        render_shell
        ;;
esac
# the container writes as root: make the output manageable from the host
chmod -R a+rwX "$OUTDIR" 2>/dev/null || true
