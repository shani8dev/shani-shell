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
#
# Every shot may carry an EXPECTATION: a python expression over `d`, the shell's
# own state IPC (see `state` in shani/shell.qml), that has to be true before the
# frame is taken. A shot whose expectation never comes true is logged as FAIL and
# the run exits non-zero — a surface that never opened is not a render. The run
# also fails on any QML error or binding loop written to qs.log while it ran.
#
# What is rendered: the desktop, the island, the control centre and each of its
# sections, the dock, the switcher, the ring, the layout switcher, the OSDs, the
# notification shapes, the modem surfaces, Chronoa, the lock screen, the
# overview, the display-confirm and Bluetooth dialogs, QR/tour/ruler, the Lens,
# the on-screen keyboard, captions, the launcher (six ways), the Settings window
# and every category in it, settings search, assistive touch, flash alerts, the
# share sheet, EVERY app in bin/shani's table (bin/shani is the list, so it
# cannot drift), the Media Player's library/playing/Radio/Live TV pages and the
# Clocks tabs, and the surfaces that are not apps: writing tools, Quick Look,
# the wallpaper style, What's new and the screensaver. Files and Disk Usage are
# normal AppWindows now, so they are photographed too. Only true layer-shell
# overlays (the file picker) stay out: the nested niri draws no Overlay layer.
set -eu

MODE="shell"
OUTDIR="/work/out/renders"
ONE_NAME=""
ONE_IPC=""
ONE_DELAY="1.5"

# Everything a render writes stays in out/ (git-ignored). A directory given
# outside it - `render.sh --one x '' 1 /work/renderone` once left 143 MB of PNGs
# in the repo root - is taken as a name under out/renders instead.
in_out() {
    case "$1" in
        /work/out/*) printf '%s' "$1" ;;
        *) printf '/work/out/renders/%s' "$(basename "$1")" ;;
    esac
}

# ---- parse args -----------------------------------------------------------
if [ "${1:-}" = "--one" ]; then
    MODE="one"
    ONE_NAME="${2:?usage: render.sh --one <name> [ipc-cmd] [delay] [outdir]}"
    ONE_IPC="${3:-}"
    ONE_DELAY="${4:-1.5}"
    OUTDIR=$(in_out "${5:-/work/out/renders/shell}")
    mkdir -p "$OUTDIR"
elif [ "${1:-}" = "matrix" ]; then
    MODE=matrix
    OUTDIR=$(in_out "${2:-/work/out/renders/matrix/${SHANI_FORM_FACTOR:-computer}}")
    mkdir -p "$OUTDIR"
elif [ "${1:-}" = "shell" ] || [ "${1:-}" = "greeter" ] || [ "${1:-}" = "setup" ] || [ "${1:-}" = "all" ]; then
    MODE="$1"
    OUTDIR=$(in_out "${2:-$OUTDIR}")
    mkdir -p "$OUTDIR"
elif [ $# -ge 1 ]; then
    # backwards compatible: render.sh <outdir> renders the shell
    OUTDIR=$(in_out "$1")
    mkdir -p "$OUTDIR"
else
    mkdir -p "$OUTDIR"
fi

# ---- shared helpers --------------------------------------------------------
log() { printf '%s\n' "$*" >&2; }

# ipc/ipc_line, st, q, waitfor (seconds), result, shot, settings_merge: the
# helpers every harness shares (dev/harness.sh)
. /work/dev/harness.sh

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
    rm -f "$_out"/*.png   # no stale shots from an earlier run
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
    rm -f "$_out"/*.png
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

    QS_ARGS="-c shani-setup"; QS_TARGET=setup; SHOTS="$_out"
    call() { ipc_line "$@" || log "warn: setup IPC failed: $*"; }

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
# The same key surfaces on every form factor (sh dev/check.sh render=matrix runs
# one session per kind of screen, SHANI_FORM_FACTOR) and, on a computer, every
# desktop layout of the Layout switcher. What the full render shows once, at
# 1920x1080 on a computer, this shows at each size people actually use.
MATRIX_LAYOUTS="default laptop tablet phone handheld tv classroom focus classic minimal dashboard taskbar centred launcher"   # LayoutSwitcher.qml presets, in order
matrix_scenes() {
    ff="${SHANI_FORM_FACTOR:-computer}"
    capture desktop "" 1.5
    ipc_line "launcher ''"; sleep 1.5; capture_current launcher 0.5 "d['launcher']"
    close_all
    capture sidebar "toggleControlCenter" 1.5 "d['controlCenter']"
    capture settings "settings" 2 "d['settingsOpen']"
    close_all
    notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
    sleep 2; capture_current notification 0.5 "d['popups'] > 0"
    close_all
    ipc closeAll; sleep 0.6
    python3 /work/bin/shani app files >/dev/null 2>&1 || true
    waitfor "d.get('filesShown')" 10 && capture_current app-files 1.0 "d.get('filesShown')"
    ipc closeAll; sleep 0.6
    case "$ff" in
        handheld|tv) capture quick-panel "quickPanel true" 1.5 "d['quickPanel']"; ipc quickPanel false; close_all ;;
    esac
    ipc_line lock; sleep 2
    capture_current lock 0.5 "d['locked']"
    wtype shani-test; sleep 0.3; wtype -k Return
    waitfor "not d['locked']" 12 || { echo "lock did not unlock"; exit 1; }
    # this kind's own layout; a computer shows every one. Each is kept through
    # the switcher (layoutUse tries it on, Return keeps it), the way a person picks one
    case "$ff" in
        computer) ids=$MATRIX_LAYOUTS ;;
        board)    ids=classroom ;;
        projector) ids=focus ;;
        *)        ids=$ff ;;
    esac
    for id in $ids; do
        ipc_line "layoutUse $id"
        waitfor "d['layoutSwitcher'] and d['layoutTrying'] == '$id'" 6 || log "warn: layout $id not tried on"
        sleep 0.6
        [ "$id" = "${ids%% *}" ] && capture_current "layout-switcher-$id" 0.5 "d['layoutSwitcher']"
        wtype -k Return
        if waitfor "d['layoutPreset'] == '$id' and not d['layoutSwitcher']" 8; then
            python3 /work/bin/shani app files >/dev/null 2>&1 || true
            waitfor "d.get('filesShown')" 10 || true
            capture_current "layout-$id" 1.5 "d['layoutPreset'] == '$id'"
        else
            last_bad="layout-$id"; failed=$((failed+1)); shot_result "layout-$id"
        fi
        ipc closeAll; sleep 0.6
    done
    # back to the default for whatever runs next
    ipc_line "layoutUse default"; waitfor "d['layoutSwitcher']" 5; sleep 0.5; wtype -k Return
    waitfor "d['layoutPreset'] == 'default'" 8 || log "warn: layout not restored"
}

render_shell() {
    _out="$OUTDIR/shell"
    [ "$MODE" = matrix ] && _out="$OUTDIR"
    mkdir -p "$_out"
    rm -f "$_out"/*.png
    OUTDIR="$_out"
    # Software shows Flathub's real catalogue (baked into the image), not the suite's fixture
    export SHANI_REAL_CATALOGUE=1
    . /work/dev/session.sh
    # `shani app` (below) speaks to the shell through qs: without this it looks
    # for a config named "shani" under ~/.config/quickshell and finds none (the
    # suite sets the same variable, dev/shell-parts/apps.sh)
    export SHANI_QS_CONFIG=/work/shani

    BASE="$OUTDIR/01-desktop-rest.png"   # the plain desktop, captured by shot 01
    # dismissAll, not closeAll: closeAll only closes the panels Ui tracks, so
    # the ruler banner, the Lens, live captions, the QR/share cards and old
    # notification pop-ups used to stay on screen for every later shot.
    # Wait until the panels really cleared: a stuck surface used to stay up for
    # the next capture, which then photographed it instead of its own subject.
    close_all() {
        ipc_line dismissAll
        waitfor "not d.get('controlCenter') and not d.get('launcher') and not d.get('settingsOpen') and not d.get('chronoaOpen') and not d.get('ring') and not d.get('switcher') and not d.get('layoutSwitcher') and d.get('expanded', '') == ''" 12 \
            || log "warn: closeAll — a surface did not clear before the next shot"
        sleep 0.5
    }

    # wait for shell to load
    i=0
    until st >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); [ $i -ge 60 ] && { echo "shell never loaded"; exit 1; }; done
    echo "shell loaded"

    n=0
    failed=0
    last_bad=""
    # Only shots whose subject is a centred window/panel can be judged by their
    # centre. This is the same set tests/test_render_surfaces.py checks; island,
    # OSD, dock and notification shots are exempt — their subject is not centred.
    needs_visual() {
        [ -n "$2" ] || return 1                  # opt-in: a declared want only
        case "$1" in
            app-*|media-*|clocks-*|quick-look*|settings-*|launcher-*|overview-*) return 0 ;;
        esac
        return 1
    }
    # Is the centre of a frame effectively still the plain desktop? Mean abs
    # channel diff over the centre band; a real surface differs by >= 40, a
    # never-drew surface by < 1. Pillow is already a dependency. A missing
    # baseline or a broken image is NOT a blank (fail safe, never false-FAIL).
    frame_is_blank() {
        [ -f "$BASE" ] || return 1
        if python3 - "$1" "$BASE" <<'PY'
import sys
try:
    from PIL import Image
    W, H = 96, 54
    def crop(p):
        im = Image.open(p).convert("RGB").resize((W, H))
        px = list(im.getdata())
        return [px[y * W + x] for y in range(int(H * 0.15), int(H * 0.85))
                             for x in range(int(W * 0.22), int(W * 0.78))]
    a, b = crop(sys.argv[1]), crop(sys.argv[2])
    diff = sum(abs(v - c) for p, q in zip(a, b) for v, c in zip(p, q)) / (len(a) * 3)
    sys.exit(0 if diff < 12 else 1)
except Exception:
    sys.exit(1)
PY
        then return 0; fi
        return 1
    }
    # Shoot one frame. If a centred surface looks blank even though its state
    # said it was up, reissue the opening IPC once and recapture before failing.
    shoot() {
        _name="$1"; _want="$2"; _cmd="$3"
        _path="$OUTDIR/$(printf '%02d' "$n")-$_name.png"
        grim "$_path"
        if needs_visual "$_name" "$_want" && frame_is_blank "$_path"; then
            [ -n "$_cmd" ] && ipc_line "$_cmd"
            [ -n "$_want" ] && waitfor "$_want" 10 || true
            sleep 1.5
            grim "$_path"
            if frame_is_blank "$_path"; then
                failed=$((failed+1)); last_bad="$_name"
                log "FAIL: $_name — state said $_want but no surface drew"
            fi
        fi
    }
    # capture() takes a 4th argument: a python expression over `d`, the state
    # IPC's JSON, that must be true once the surface is up. Without one a failed
    # IPC or a section id nothing reads leaves the PREVIOUS surface on screen and
    # the PNG looks plausible — the failure mode this script exists to avoid, so
    # every shot of a surface this script knows a state key for now checks it.
    capture() {
        name="$1"; cmd="$2"; delay="${3:-1.5}"; want="${4:-}"
        close_all
        last_bad=""
        if ! open_surface "$name" "$cmd" "$want"; then
            failed=$((failed+1)); last_bad="$name"
            log "FAIL: $name — the shell's state never said: $want"
        fi
        sleep "$delay"
        n=$((n+1)); shoot "$name" "$want" "$cmd"
        echo "[$n] $name"
        shot_result "$name"
    }
    # An IPC can be lost to a busy shell (the full run fires hundreds back to
    # back); reissue it once before calling the surface a failure.
    open_surface() {
        [ -z "$3" ] && return 0          # no expectation: nothing to wait for
        [ -n "$2" ] && ipc_line "$2"
        waitfor "$3" 20 && return 0
        [ -n "$2" ] && { ipc_line "$2"; sleep 1; }
        waitfor "$3" 20
    }
    # capture what is already on screen (the surface was opened by the caller;
    # closeAll must NOT run first — it would dismiss what is being photographed)
    capture_current() {
        name="$1"; delay="${2:-0.5}"; want="${3:-}"
        last_bad=""
        check_want "$name" "$want"
        sleep "$delay"
        n=$((n+1)); shoot "$name" "$want" "$LAST_IPC"
        echo "[$n] $name"
        shot_result "$name"
    }
    check_want() {
        if [ -n "$2" ] && ! waitfor "$2" 40; then
            failed=$((failed+1)); last_bad="$1"
            log "FAIL: $1 — the shell's state never said: $2"
        fi
        return 0
    }
    # one RESULT line per shot, so dev/check.sh's summary counts what was
    # rendered and what never came up (the suites' convention)
    # one RESULT per scene, through the shared result (dev/harness.sh)
    shot_result() {
        if [ "$last_bad" = "$1" ]; then
            result "shot-$1" FAIL "the surface never came up"
        else
            result "shot-$1" PASS
        fi
    }

    # the lock screen unlocks with a password, not IPC — set one, as the test
    # suite does, and unlock through the keyboard after the lock shots
    echo 'root:shani-test' | chpasswd

    if [ "$MODE" = matrix ]; then
        matrix_scenes
    else

    # ---- core desktop (window-free: the wallpaper is the subject) ---------------
    capture desktop-rest "" 1.5
    ipc_line setting darkMode false
    waitfor "not d['dark']" 20 || log "warn: light theme not applied"
    sleep 2.5   # the wallpaper cross-fade is Theme.anim*4 — let it finish
    capture desktop-light "" 0.8
    ipc_line setting darkMode true
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
    ipc_line "ask 'Tidy my desktop'"; sleep 2.5
    capture_current island-working 0.5
    i=0
    until [ "$(st 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('approval'))" 2>/dev/null)" != "None" ] && [ $i -lt 30 ]; do sleep 0.5; i=$((i+1)); done
    if [ $i -lt 30 ]; then
        capture_current island-approval 0.5
        ipc_line "approve 'Allow this once'"; sleep 2
    fi
    close_all
    ipc_line askIsland; sleep 1.5
    capture_current island-ask 0.5
    # leaving the ask field open would keep the island in "Enter to send,
    # Esc to close" mode for every shot until the ring's Escape — close it here
    ipc_line closeChronoa; sleep 0.5
    close_all
    ipc_line timer 1; sleep 1.5
    capture_current island-timer 0.5
    ipc_line timer 0; sleep 0.5
    # nested niri gives the recorder a 0×0 frame: this captures the region-select
    # stage (slurp), which is what a person sees first — not a live recording
    ipc_line record; sleep 1.5
    capture_current island-record 0.5
    ipc_line record; sleep 0.5           # stop/cancel
    ipc_line dnd; sleep 1.5
    capture_current island-dnd 0.5
    ipc_line dnd; sleep 0.5
    ipc_line caffeine; sleep 1.5
    capture_current island-caffeine 0.5
    ipc_line caffeine; sleep 0.5
    close_all

    # ---- control centre: main + every section id Ui.expanded understands ------
    # (only these expand a panel in the sidebar; on hardware wifi/bluetooth/vpn/
    #  phone also need an adapter/device, headless captures show the resting UI)
    capture cc-main "toggleControlCenter" 1.5 "d['controlCenter'] and d['expanded'] == ''"
    for sec in wifi bluetooth vpn audio power access display timer focus record phone; do
        capture "cc-$sec" "controlCenter $sec" 1.2 "d['controlCenter'] and d['expanded'] == '$sec'"
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
    ipc_line dockMenu foot; sleep 1
    capture_current dock-menu 0.5 "d['dockMenu'] != ''"
    ipc_line "dockMenu ''"; sleep 0.5
    close_all

    # ---- switcher (the two foot windows from the top) ---------------------------
    capture switcher-open "switcher" 1.5 "d['switcher']"
    close_all
    killall -9 foot 2>/dev/null || true     # from here on, window-free
    sleep 1

    # ---- ring (pie menu), at the pointer and one level deep ---------------------
    capture ring-main "ring" 1.5 "d['ring']"
    close_all
    ipc_line ringAt 300 500; sleep 1.2
    capture_current ring-at-point 0.5 "d['ring']"
    wtype -k Escape; sleep 0.5
    close_all
    ipc_line ring; sleep 1; wtype 8; sleep 1
    capture_current ring-sub 0.5     # Power slice: a ring of its own
    wtype -k Escape; sleep 0.5
    close_all

    # ---- layout switcher ---------------------------------------------------------
    capture layout-switcher "layoutSwitcher" 1.5 "d['layoutSwitcher']"
    close_all

    # ---- OSD ----------------------------------------------------------------------
    # The pill lives 1.6 s and a slider OSD carries no words (`osdLabel` is only
    # the last label an OSD said), so what is checked here is the EFFECT: the IPC
    # has to have moved the value. The null sink starts at maximum, so the volume
    # is lowered first - raising a volume already at 100 % changes nothing and
    # draws no OSD at all.
    # the null sink starts late in a fresh boot; wait for a real volume before
    # asking it to move, and reissue once if the first IPC was lost
    waitfor "d['volume'] is not None" 40 || log "warn: no audio sink in this render"
    ipc_line volumeDown; sleep 0.6
    waitfor "d['volume'] < 100" 10 || { ipc_line volumeDown; sleep 0.6; }
    capture_current osd-volume-down 0.6 "d['volume'] < 100"
    ipc_line volumeUp;        sleep 0.4; capture_current osd-volume 0.6 "d['volume'] == 100"
    ipc_line volumeMute;      sleep 0.4; capture_current osd-mute 0.6 "d['muted']"
    ipc_line volumeMute;      sleep 0.5
    ipc_line micMute;         sleep 0.4; capture_current osd-mic-mute 0.6
    ipc_line micMute;         sleep 0.5
    ipc_line brightnessUp;    sleep 0.4; capture_current osd-brightness-up 0.6
    ipc_line brightnessDown;  sleep 0.4; capture_current osd-brightness-down 0.6
    brightnessctl set 50% >/dev/null 2>&1 || true

    # ---- notifications -------------------------------------------------------------
    # the daemon starts lazily and can drop the very first message: warm it up
    notify-send -a Warmup "render warmup" "ignored" >/dev/null 2>&1 || true
    sleep 1.5
    notify-send -a Mail "Lunch at 1?" "Priya: the usual place, I'll book a table."
    sleep 2; capture_current notification-popup 0.5 "d['popups'] > 0"
    # notify-send -A waits for the action to be picked, so it would block the
    # render forever; background it and stop it after the shot (the daemon keeps
    # the notification on screen, actions and all)
    notify-send -a Messages -A reply=Reply -A call=Call "Asha" "Are we still on for 6?" &
    actions_pid=$!
    sleep 2; capture_current notification-actions 0.5 "d['popups'] > 0"  # inline actions on the popup
    kill "$actions_pid" 2>/dev/null || true
    notify-send -u critical -a Power "Battery low" "5% left"
    sleep 1; capture_current notification-critical 0.5 "d['popups'] > 0"
    ipc_line dnd
    notify-send -a Backup "Backup finished" "142 files, 3.1 GB"
    sleep 1; capture_current notification-dnd 0.5 "d['popups'] > 0"
    ipc_line dnd

    # ---- the SMS/call path (fake modem drives the real shell code) ---------------
    echo '{"modem": {"path": "/m/0", "state": "registered", "locked": "", "operator": "Jio", "signal": 63, "number": "+9198", "voice": true, "messaging": true}}' > /tmp/modem-ask
    sleep 1.5
    echo '{"sms": {"path": "/s/1", "from": "+919811111111", "text": "Your code is 482913", "time": ""}}' > /tmp/modem-ask
    waitfor "d['smsTo'] == '+919811111111' and d['modemDialog'] == 'sms'" 10
    sleep 0.5; capture_current notification-sms 0.5   # with Reply / Copy actions
    echo '{"call": {"path": "/c/1", "number": "+919844444444", "state": "ringing-in", "incoming": true}}' > /tmp/modem-ask
    # a ring is the shell's own card, driven by the phone backend's call state
    python3 - <<'PY'
import json, pathlib, time
p = pathlib.Path("/root/.local/state/shani-shell"); p.mkdir(parents=True, exist_ok=True)
(p / "incoming-call.json").write_text(json.dumps({"id": "r1", "name": "Asha Patil", "number": "+919844444444", "line": "modem", "when": int(time.time())}))
PY
    waitfor "d['incoming'].startswith('Asha Patil')" 10
    sleep 0.5; capture_current modem-call 0.5         # the call card and the call
    python3 -c 'import pathlib; pathlib.Path("/root/.local/state/shani-shell/incoming-call.json").unlink(missing_ok=True)'
    echo '{"call": {"path": "/c/1", "number": "+919844444444", "state": "terminated", "incoming": true}}' > /tmp/modem-ask
    sleep 1
    ipc_line textMessage +919822222222; sleep 1.2
    capture_current modem-sms-composer 0.5 "d['smsTo'] != ''"
    close_all

    # ---- chronoa panel ------------------------------------------------------------
    capture chronoa-panel-idle "toggleChronoa" 1.5 "d['chronoaOpen']"
    ipc_line "ask 'What is using my battery?'"; sleep 3
    capture_current chronoa-panel-thinking 0.5 "d['chronoaOpen']"
    sleep 5
    capture_current chronoa-panel-speaking 0.5 "d['chronoaOpen']"
    ipc_line closeChronoa; sleep 0.5
    close_all

    # ---- lock screen (unlock by typing the password) -------------------------------
    ipc_line lock; sleep 2
    capture_current lock-screen 0.5 "d['locked']"
    wtype wrong-password; sleep 0.3; wtype -k Return; sleep 2.5
    capture_current lock-wrong 0.5 "d['locked']"       # the refusal, in place
    wtype shani-test; sleep 0.3; wtype -k Return
    waitfor "not d['locked']" 12 || { echo "lock did not unlock — later shots would be of a locked screen"; exit 1; }

    # ---- overview (niri's) + typing in it -------------------------------------------
    # Typing in the overview hands the text to the launcher and closes the
    # overview (Modules/Overview/OverviewSearch.qml): the second shot is the
    # launcher that came of it, so that is what has to be up.
    niri msg action open-overview || true; sleep 1.5
    capture_current overview-open 0.5 "d['overview']"
    wtype calc; sleep 1.2
    capture_current overview-search 0.5 "d['launcher']"
    wtype -k Escape; sleep 0.3
    niri msg action close-overview 2>/dev/null || true
    sleep 0.5
    close_all

    # ---- display confirm (niri applies, keeps or reverts) ---------------------------
    ipc_line display "winit scale 1.5"
    waitfor "d['displayPending']" 10
    capture_current display-confirm 0.5 "d['displayPending']"
    ipc_line displayKeep; sleep 1
    ipc_line display "winit scale 1"; sleep 2

    # ---- bluetooth pairing (fake agent drives the real shell dialog) ---------------
    rm -f /tmp/bt-ask /tmp/bt-answers
    echo '{"ask": "confirm", "id": 7, "device": "Pixel 8", "passkey": "012345"}' > /tmp/bt-ask
    waitfor "d['btAsk'] == 'confirm:Pixel 8'" 10
    capture_current bt-pair-confirm 0.5 "d['btAsk'] != ''"
    ipc_line "btAnswer true ''"; sleep 1
    echo '{"show": "passkey", "device": "K380", "passkey": "045123", "entered": 0}' > /tmp/bt-ask
    waitfor "d['btShow'] == 'K380'" 10
    capture_current bt-passkey 0.5 "d['btShow'] != ''"
    echo '{"cancel": true}' > /tmp/bt-ask; sleep 1

    # ---- QR, tour, ruler -------------------------------------------------------------
    capture qr-code "qr 'Wi-Fi' 'ShaniOS Guest'" 1.5 "d['qrShown']"
    close_all
    capture tour "tour" 1.5 "d['tour']"
    close_all
    capture ruler "ruler" 1.5 "d['rulerShown']"
    close_all

    # ---- lens (frozen selection, read offline) -----------------------------------------
    capture lens-ready "lensRegion '260,460 1400x160'" 3.5 "d['lens'] != ''"
    close_all

    # ---- processes, magnifier, annotate ------------------------------------------------
    capture processes "processes" 1.5 "d['processes'] > 0"
    close_all
    capture magnifier "magnifier" 1.5 "d['magnifier']"
    close_all
    capture annotate "annotate" 1.5 "d['annotate']"
    close_all

    # ---- on-screen keyboard -------------------------------------------------------------
    capture osk-main "osk" 1.5 "d['osk']"
    ipc_line oskLanguage; sleep 0.5
    capture_current osk-language 0.5 "d['oskLang'] != ''"
    ipc_line osk; sleep 0.5
    close_all

    # ---- captions ----------------------------------------------------------------------
    capture captions "captions" 1.5 "d['captions']"
    close_all

    # ---- launcher: empty → answers → full grid; clipboard mode --------------------------
    capture "launcher-empty" "launcher ''" 1.5 "d['launcher']"
    ipc_line launcher text;       sleep 1.5; capture_current launcher-apps 0.5 "d['launcher']"
    ipc_line "launcher '= 2*(3+4)^2'"; sleep 1.5; capture_current launcher-calc 0.5 "d['launcher']"
    ipc_line "launcher ':grinning face'"; sleep 1.5; capture_current launcher-emoji 0.5 "d['launcher']"
    ipc_line launcher quarterly;  sleep 1.5; capture_current launcher-files 0.5 "d['launcher']"
    ipc_line "launcher '5 km in miles'"; sleep 1.5; capture_current launcher-convert 0.5 "d['launcher']"
    ipc_line launcher dark;       sleep 1.5; capture_current launcher-actions 0.5 "d['launcher']"
    ipc_line "launcher ''";         sleep 1.5; capture_current launcher-full 0.5 "d['launcher']"
    wl-copy "render clipboard probe"; sleep 0.5
    ipc_line "launcher 'c probe'";  sleep 1.5
    waitfor "d['launcher']" 10 || { ipc_line "launcher 'c probe'"; sleep 1.5; }
    capture_current launcher-clipboard 0.5 "d['launcher']"
    close_all

    # ---- settings window: main + every category (incl. printers and account) -----------
    # The category ids come from SettingsPage's own `cats` table, so a page added
    # there is rendered here without anyone remembering to add it (storage and
    # screen time were missing from this list while nothing checked it).
    cats=$(python3 - <<'PY'
import re
src = open("/work/shani/Modules/Settings/SettingsPage.qml").read()
print(" ".join(re.findall(r'id: "([a-z]+)", words:', src)))
PY
    )
    if [ -z "$cats" ]; then
        failed=$((failed+1)); log "FAIL: no settings categories read from SettingsPage.qml"
    fi
    capture settings-main "settings" 2 "d['settingsOpen']"
    for cat in $cats; do
        capture "settings-$cat" "settingsCategory $cat" 1.5 "d['settingsOpen'] and d['settingsCat'] == '$cat'"
    done
    close_all
    # ---- settings search: highlighted matches + empty state -----------------------
    ipc_line settings; sleep 1.5
    wtype proxy; sleep 1.5
    capture_current settings-search-proxy 0.5 "d['settingsOpen']"
    # clear the query and show the empty state by searching for nonsense
    # type a query with no matches to exercise the empty state
    close_all
    ipc_line settings; sleep 1.5
    wtype zzzzzzz; sleep 1.2
    capture_current settings-search-empty 0.5 "d['settingsOpen']"
    close_all
    # ---- settings: search folders empty state -----------------------------------
    settings_merge '{"searchFiles": true, "searchFolders": []}'
    sleep 1
    capture "settings-search-empty-folders" "settingsCategory search" 1.5 "d['settingsOpen'] and d['settingsCat'] == 'search'"
    settings_merge '{"searchFiles": false}'
    sleep 0.5
    close_all

    # ---- assistive touch (floating button) ----------------------------------------------
    # set it, don't toggle it: an earlier step may already have turned it on
    settings_merge '{"assistiveTouch": true}'
    sleep 1.5
    capture_current assistive-touch 0.5 "d['assistiveTouch']"
    # leave it on: clearing it here made the check re-run against a false state
    close_all

    # ---- flash alerts (edge glow on a notification; opt-in setting) ---------------------
    ipc_line setting flashAlerts true; sleep 0.5
    notify-send -a Mail "Flash test" "the edge glows"
    waitfor "d['lastFlash'] != ''" 10
    capture_current flash-alert 0.5 "d['lastFlash'] != ''"
    ipc_line setting flashAlerts false; sleep 0.5
    close_all

    # ---- share sheet ----------------------------------------------------------------------
    touch /tmp/test-share.txt
    ipc_line share /tmp/test-share.txt; sleep 1.5
    capture_current share-sheet 0.5 "len(d['shareTargets']) > 0"
    rm -f /tmp/test-share.txt
    close_all

    # ---- the shell's own windows: every app in bin/shani's table -----------------
    # One table feeds `shani app`, the desktop entries and dev/shell-parts/apps.sh,
    # so reading it here is what keeps this list from drifting. A row with no state
    # key is an action (a screenshot, a colour pick): it waits for the pointer and
    # is not a window to photograph. capture_current, not capture: closeAll is
    # called by hand, because dismissAll leaves an app window open and the next
    # shot would carry it.
    F=/tmp/render-fixtures; rm -rf "$F"; mkdir -p "$F"
    cp /work/assets/shani-dark.jpg "$F/photo.jpg"
    printf 'first line\nsecond line\n' > "$F/note.txt"
    # a one-page PDF, written by hand (objects, xref, trailer) - as apps.sh does
    python3 - "$F/one.pdf" <<'PY'
import sys
objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length 44 >>\nstream\nBT /F1 18 Tf 20 100 Td (Shani test) Tj ET\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
out, offs = b"%PDF-1.4\n", []
for i, o in enumerate(objs, 1):
    offs.append(len(out)); out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offs)
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
open(sys.argv[1], "wb").write(out)
PY
    python3 - "$F/pack.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("readme.txt", "Shani render fixture\n")
    z.writestr("notes/todo.txt", "one\ntwo\n")
PY
    ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=25" -f lavfi -i "sine=frequency=440" \
        -t 3 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$F/clip.mp4" 2>/dev/null \
        || log "warn: no video fixture (ffmpeg), the media player and video trimmer shots will be empty"

    for spec in $(python3 - <<'PY'
import importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("shani_cli", "/work/bin/shani")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("shani_cli", loader)); loader.exec_module(m)
# Files and Disk Usage are AppWindows now; only the picker is a layer-shell
# overlay that the nested niri cannot photograph (driven by the test suite)
OVERLAYS = set()
for name, s in m.APPS.items():
    if s[8] is None or name in OVERLAYS:
        continue
    print(f"{name}:{s[8]}")
PY
    ); do
        name=${spec%%:*}; key=${spec#*:}
        case "$name" in
            text-editor)     set -- "$name" "$F/note.txt" ;;
            image-viewer)    set -- "$name" "$F/photo.jpg" ;;
            document-viewer) set -- "$name" "$F/one.pdf" ;;
            archive-manager) set -- "$name" "$F/pack.zip" ;;
            pdf-signer)      set -- "$name" "$F/one.pdf" ;;
            media-player|video-trimmer)
                             if [ -f "$F/clip.mp4" ]; then set -- "$name" "$F/clip.mp4"; else set -- "$name"; fi ;;
            *)               set -- "$name" ;;
        esac
        ipc_line closeAll; sleep 0.6
        python3 /work/bin/shani app "$@" >/dev/null 2>&1 || true
        # the CLI's IPC can be dropped under the load of 100+ prior shots
        waitfor "d.get('$key')" 10 || { ipc_line closeAll; sleep 0.6; python3 /work/bin/shani app "$@" >/dev/null 2>&1 || true; }
        capture_current "app-$name" 1.0 "d.get('$key')"
    done
    ipc_line closeAll; sleep 0.5
    close_all

    # ---- Software, as a store: the front page (in the apps above), a search with
    #      the Snap Store's apps after Flathub's, installed, command-line tools ----
    # the app scenes above leave their own windows (Camera, Health...): clear them first
    ipc_line dismissAll; close_all
    niri msg --json windows 2>/dev/null | python3 -c "import json,sys; print(' '.join(str(w['id']) for w in json.load(sys.stdin)))" \
        | tr ' ' '\n' | while read -r id; do [ -n "$id" ] && niri msg action close-window --id "$id" 2>/dev/null; done
    sleep 1.5
    # the store's front page, once the catalogue's index is built (the first ask builds it)
    ipc_line "softwareTab explore"; sleep 6
    capture_current software-home 1.5 "d['softwareShown']"
    ipc_line "softwareSearch music"; sleep 4
    capture_current software-search 1.5 "d['softwareShown']"
    ipc_line "softwareTab installed"; sleep 2
    capture_current software-installed 1.0 "d['softwareShown']"
    ipc_line "softwareTab tools"; sleep 2
    capture_current software-tools 1.0 "d['softwareShown']"
    ipc_line closeAll; sleep 0.5

    # ---- the Media Player's pages, each with real content behind it ----
    capture media-radio "radioShow featured" 1.5 "len(d['radioStations']) > 0"
    close_all
    capture media-live-tv "liveTvOpen" 3 "len(d['liveTvChannels']) >= 100"
    close_all
    # the library and now-playing views need the player open first, so two IPCs
    ipc_line "mediaOpen ''"; sleep 1; ipc_line "mediaPage library"; sleep 1
    capture_current media-library 1.0 "d['mediaShown'] and d['mediaPage'] == 'library'"
    close_all
    if [ -f "$F/clip.mp4" ]; then
        ipc_line "mediaOpen '$F/clip.mp4'"; sleep 1.5
        capture_current media-playing 1.0 "d['mediaShown'] and d['mediaPage'] == 'playing'"
        close_all
    fi

    # ---- the Clocks tabs, each a distinct view behind the same window ----
    for tab in alarms stopwatch timer; do
        capture "clocks-$tab" "clocksOpen $tab" 1.2 "d['clocksShown'] and d['clocksTab'] == '$tab'"
    done
    close_all

    # ---- the surfaces that are not apps (they open from an IPC, not a window id) ----
    # the writing tools act on the selection, else on the clipboard: give it text
    wl-copy "The quick brown fox jumps over the lazy dog."
    capture writing-tools "writingTools" 1.2 "d['writingShown']"
    close_all
    # the file chooser alone is still a layer-shell overlay, which the nested
    # niri cannot photograph; the suite drives it instead
    capture quick-look "quickLook '$F/note.txt'" 1.5 "d['quickLookShown']"
    close_all
    capture wallpaper-style "wallpaperStyleOpen '$F/photo.jpg'" 1.5 "d['wallpaperStyleShown']"
    close_all
    # "What's new" is a notification, not a window: a version the shell has not
    # told about yet, then the check (WhatsNew reads /etc/shani-version)
    printf '99.0.0-render\n' > /etc/shani-version
    ipc_line whatsNewCheck; sleep 2
    capture_current whats-new 0.5 "d['whatsNewShown'] != ''"
    close_all
    # the screensaver's cover, previewed (its state key is the idle saver, not the preview)
    capture screensaver "screenSaverPreview" 1.5 "d['screenSaverPreview']"
    close_all

    # ---- surfaces behind a setting or a passing state ----------------------------
    # dev/surfaces.tsv lists every surface shell.qml loads; these are the ones
    # the default session never shows (tools/surfaces.py check finds the next one)
    # the left rail is on by default (so in every render above); off, the dock
    # shows the workspaces instead
    settings_merge '{"leftRail": true}'
    waitfor "d.get('leftRail')" 10 || log "warn: left rail setting not applied"
    capture_current left-rail 1.5 "d.get('leftRail')"
    settings_merge '{"leftRail": false}'
    waitfor "not d.get('leftRail')" 10 || log "warn: left rail setting not cleared"
    capture_current dock-workspaces 1.5 "not d.get('leftRail')"
    settings_merge '{"leftRail": true}'
    settings_merge '{"desktopWidgets": ["agenda", "battery", "note", "clocks"]}'
    sleep 2.5
    capture_current more-widgets 0.5
    settings_merge '{"desktopWidgets": []}'
    capture backup-panel "backupOpen" 1.5 "d['backupShown']"
    close_all
    capture calibrate-touch "calibrateStart touch" 1.2 "d['calibrating'] == 'touch'"
    ipc_line calibrateCancel; sleep 0.5
    ipc_line "screenshotPin '$F/photo.jpg'"
    waitfor "d['screenshotPinned']" 10 || log "warn: screenshot pin did not open"
    capture_current pinned-screenshot 1.0 "d['screenshotPinned']"
    ipc_line "screenshotPin '$F/photo.jpg'"; sleep 0.5
    rm -rf "$F"

    fi   # the full set of scenes

    # ---- what makes a render run a failure --------------------------------------
    # Qt warns rather than failing when a layout's minimum is wider than the
    # window, when a binding loops, or when a handler throws: the render still
    # looks plausible at a glance. The guard is the log. Only QML's own words
    # count - the compositor's MESA and font noise is not ours.
    # LazyLoader compile errors are the dangerous case: the Ui flag flips (so
    # the state expectation PASSes) but the window never maps and the frame is
    # bare wallpaper. Quickshell logs these as WARN `qs:@/...:line:col: msg`,
    # not "QML ERROR", so they previously passed silently. Catch them here.
    compile_bad=$(grep -aE "qs:@/.*(Unexpected token|Cannot assign to non-existent property|Cannot assign a value directly|is not a type|is not a function|Unknown type|is not a valid|Expected token)" /work/out/logs/qs.log | head -5)
    if [ -n "$compile_bad" ]; then
        echo "QML COMPILE ERROR in $n renders:" >&2
        printf '%s\n' "$compile_bad" >&2
        failed=$((failed+1))
    fi
    bad=$(grep -aE "QQuickLayout|Layout::|is larger than|does not fit|Unable to (fit|arrange)|Binding loop|TypeError|ReferenceError|is not a function|is not defined|Unable to assign" /work/out/logs/qs.log | head -5)
    if [ -n "$bad" ]; then
        echo "QML ERROR in $n renders:" >&2
        printf '%s\n' "$bad" >&2
        failed=$((failed+1))
    fi
    if [ "$failed" -gt 0 ]; then
        echo "=== FAILED: $failed surface(s) never came up (see the FAIL lines above) ===" >&2
        exit 1
    fi

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
    matrix)  render_shell ;;
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
