# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=chronoa-settings)
# ---- Settings > Chronoa: the headless engine's ten read-only pages and its
#      switch. dev/session.sh stands in for the Agent (real Inventory shapes)
#      and for `systemctl --user shani-chronoa-engine.service`, so this checks
#      the real shell path without starting a GTK window or a real service.
LOG="${SHANI_CHRONOA_SYSTEMCTL_LOG:-/tmp/fake-chronoa-systemctl/calls}"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
# a busy box can start the shell a moment after the suite's first probe: wait
# for state before driving it, so a dropped first IPC is not read as a bug here
_wait=0
until [ "$(q "['settingsLoaded']" 2>/dev/null)" = True ] || [ $_wait -ge 60 ]; do
    sleep 0.25; _wait=$((_wait + 1))
done

# engine off first: the page says the service is down and shows the read-only
# data as data, not as a blank or a traceback.
ipc chronoaSettingsPage status
waitfor "d['settingsOpen'] == True and d['settingsCat'] == 'chronoa'" 8 \
    && result chronoa-settings-opens PASS || result chronoa-settings-opens FAIL "$(q "['settingsCat']")"
waitfor "d['chronoaState'].get('page') == 'status' and d['chronoaState'].get('ready') == True" 10 \
    && result chronoa-status-reads PASS || result chronoa-status-reads FAIL "$(q "['chronoaState']")"
[ "$(q "['chronoaState'].get('service')")" = inactive ] \
    && result chronoa-engine-off-state PASS "service inactive" \
    || result chronoa-engine-off-state FAIL "$(q "['chronoaState']")"
shot chronoa-settings-off 0.4

# the switch runs the same singleton the click runs, through the stand-in:
# one `start` of the exact unit, as the person (no pkexec, no root).
ipc chronoaEngine on
waitfor "d['chronoaState'].get('service') == 'active'" 8 \
    && result chronoa-switch-starts-engine PASS || result chronoa-switch-starts-engine FAIL "$(q "['chronoaState']")"
grep -qx "start shani-chronoa-engine.service" "$LOG" \
    && result chronoa-switch-unit PASS "$(head -1 "$LOG")" \
    || result chronoa-switch-unit FAIL "$(head -3 "$LOG")"
grep -qiE "pkexec|sudo" "$LOG" && result chronoa-switch-no-root FAIL "$(head -3 "$LOG")" \
    || result chronoa-switch-no-root PASS
shot chronoa-settings-status 0.4

# every section comes from Agent.Inventory and shows the stand-in's own rows.
# The marker is a value from dev/fake-chronoa-agent.py, not a label written in
# this check, so a page that renders only headings cannot pass.
for page in status models skills capabilities routines triggers memory privacy senses conversations; do
    case "$page" in
        status|models) marker="local-test-model" ;;
        skills) marker="check_weather" ;;
        capabilities) marker="Check the weather" ;;
        routines) marker="Good morning" ;;
        triggers) marker="Low battery" ;;
        memory) marker="Prefers trains to flights" ;;
        privacy|senses) marker="senses.screen.read" ;;
        conversations) marker="Trip planning" ;;
    esac
    ipc chronoaSettingsPage "$page"
    waitfor "d['chronoaState'].get('page') == '$page' and d['chronoaState'].get('ready') == True and d['chronoaState'].get('count', 0) > 0" 10
    state=$(q "['chronoaState']")
    echo "$state" | grep -qF "$marker" \
        && result "chronoa-page-$page" PASS "$marker" \
        || result "chronoa-page-$page" FAIL "$state"
    shot "chronoa-settings-$page" 0.3
done

# no GTK app is started by this page: the shell never execs shani-chronoa.
grep -q "gapplication action dev.shani.chronoa" /work/out/logs/qs.log \
    && result chronoa-no-gtk-settings FAIL "gapplication action was called" \
    || result chronoa-no-gtk-settings PASS

ipc chronoaEngine off
waitfor "d['chronoaState'].get('service') == 'inactive'" 8 \
    && result chronoa-switch-stops-engine PASS || result chronoa-switch-stops-engine FAIL "$(q "['chronoaState']")"
grep -qx "stop shani-chronoa-engine.service" "$LOG" \
    && result chronoa-switch-stop-unit PASS "$(tail -1 "$LOG")" \
    || result chronoa-switch-stop-unit FAIL "$(tail -3 "$LOG")"

ipc closeAll
