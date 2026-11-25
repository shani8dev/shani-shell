# The one set of harness helpers. Every harness sources this file instead of
# defining its own: dev/shell-test.sh (and its parts), dev/render.sh,
# dev/demo.sh, dev/showcase.sh, dev/greeter-test.sh. The copies had drifted:
# waitfor's second argument was seconds in the suite but half-second ticks in
# the render, the suite's waitfor overwrote the caller's `i`, and `ipc` was
# eval'd in one place and passed through in the others.
#
# Which shell the helpers talk to (set before sourcing, or later):
#   QS_ARGS    qs's selector       default: -p /work/shani   (setup: -c shani-setup)
#   QS_TARGET  the IPC target      default: shani            (setup: setup)
#   SHOTS      where shot() writes default: /tmp
#
#   ipc  ARGS...          call the shell; arguments pass through unchanged
#   ipc_line "CMD ARGS"   one string, word-split with shell quoting (render's scenes)
#   st                    the shell's state() as JSON
#   q    PYEXPR           print d<PYEXPR> from the state, e.g. q "['dark']"
#   waitfor PYEXPR SECS   until the expression over d is true; 1 on timeout
#   result NAME STATUS [DETAIL]   one RESULT line; FAIL sets fail=1
#   shot NAME [DELAY]     grim the screen into $SHOTS/NAME.png
#   settings JSON         the suite's quiet defaults, updated with JSON (replaces the file)
#   settings_merge JSON   update the current settings file with JSON

: "${QS_ARGS:=-p /work/shani}"
: "${QS_TARGET:=shani}"
: "${SHOTS:=/tmp}"
fail=${fail:-0}

ipc() { qs $QS_ARGS ipc call "$QS_TARGET" "$@" >/dev/null 2>&1; }
# One quoted command string OR unquoted words: $* joins every arg so
# `ipc_line dockMenu foot` sends both words (with $1 only "dockMenu" went out).
ipc_line() { eval "qs $QS_ARGS ipc call $QS_TARGET $*" >/dev/null 2>&1 || true; LAST_IPC="$*"; }
st() { timeout 5 qs $QS_ARGS ipc call "$QS_TARGET" state 2>/dev/null; }
q() { st | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)"; }

# seconds, polled four times a second; its own counter, so a caller's loop
# variable survives (the suite's parts had to avoid `i` for this reason)
waitfor() {
    _wf=0
    while [ "$_wf" -lt $(( ${2:-10} * 4 )) ]; do
        st | python3 -c "import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
sys.exit(0 if ($1) else 1)" >/dev/null 2>&1 && return 0
        sleep 0.25
        _wf=$((_wf + 1))
    done
    return 1
}

result() {
    echo "RESULT $1 $2${3:+ ($3)}"
    if [ "$2" = FAIL ]; then fail=1; fi   # a SKIP (a mode not on, hardware not there) is not a failure
}

shot() { sleep "${2:-0.8}"; grim "$SHOTS/$1.png" 2>/dev/null || true; }   # a missing frame must not stop a suite

# the suite runs longer than the default idle lock (5 min) between keyboard
# inputs: no dimming, lock or screen-off unless a test sets them itself
# (the dock's pins: the dev image's own Nautilus and GNOME Text Editor, whose
# jump lists and launcher entries the dock checks use)
settings() {
    python3 -c 'import json,sys; d={"dimAfter":0,"lockAfter":0,"screenOffAfter":0,"lockAfterBattery":0,"screenOffAfterBattery":0,"startHintsDone":True,"dynamicLockGrace":1500,"dockPinned":["org.gnome.Nautilus","com.vivaldi.Vivaldi","foot","dev.shani.cassini","shani-chronoa","org.gnome.TextEditor"]}; d.update(json.loads(sys.argv[1])); print(json.dumps(d), end="")' "$1" > "$SHANI_SHELL_SETTINGS"
    sleep 1.5
}

settings_merge() {
    SHANI_MERGE_JSON="$1" python3 -c 'import json,os
p = os.environ["SHANI_SHELL_SETTINGS"]
with open(p) as f:
    text = f.read()
cur = json.loads(text) if text.strip() else {}
cur.update(json.loads(os.environ["SHANI_MERGE_JSON"]))
with open(p, "w") as f:
    json.dump(cur, f)'
}
