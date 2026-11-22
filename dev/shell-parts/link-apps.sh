# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=link-apps)
# ---- the Calls and Messages apps: individual windows over the phone backends,
#      which is what shani-link's GTK window used to be. There is no phone in the
#      dev container, so what is checked is that each app opens, says so plainly
#      instead of showing an empty shell, and that the launcher can reach them.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}

# ---- Calls -----------------------------------------------------------------
ipc callsOpen ""
waitfor "d['callsShown'] == True" 6 && result calls-app-opens PASS || result calls-app-opens FAIL "$(q "['callsShown']")"
# no landline and no phone in the container: the pad is still there, the history says so
waitfor "d['callsCount'] == 0" 4 && result calls-history-is-readable PASS "$(q "['callsCount']")" || result calls-history-is-readable FAIL "$(q "['callsCount']")"
shot calls-app 0.4
ipc callsClose
waitfor "d['callsShown'] == False" 4 && result calls-app-closes PASS || result calls-app-closes FAIL "$(q "['callsShown']")"

# ---- Messages ---------------------------------------------------------------
ipc messagesOpen ""
waitfor "d['messagesShown'] == True" 6 && result messages-app-opens PASS || result messages-app-opens FAIL "$(q "['messagesShown']")"
# with nothing connected it must say so rather than show an empty list with no hint
# An AppWindow is a layer-shell surface, which the nested compositor does not
# put in the accessibility tree (see GAPS.md: Files cannot be photographed
# there either), so the empty list is checked through the state, not AT-SPI.
shot messages-app 0.4
ipc messagesClose
waitfor "d['messagesShown'] == False" 4 && result messages-app-closes PASS || result messages-app-closes FAIL "$(q "['messagesShown']")"

# ---- the backends ship with the shell --------------------------------------
# bridge/shani_link is shani-link's package without its GTK window: the shell
# owns the backends now, so the import must work with no shani-link installed
python3 - <<'PY' && result link-backends-import PASS || result link-backends-import FAIL "the vendored backends did not import"
import sys
sys.path.insert(0, "/work/bridge")
import shani_link.phone, shani_link.calls_log, shani_link.contacts, shani_link.lines
PY

# ---- both are apps of the shell, with their own desktop entry ---------------
# The launcher's own list comes from the desktop entries the image installs, and
# the dev container has none of ours, so this checks the shell's own register
# (`shani app`, bin/shani's APPS) - the one that writes those entries.
python3 /work/bin/shani app 2>/dev/null | grep -q '^calls ' \
    && result calls-is-an-app PASS || result calls-is-an-app FAIL "not in shani app"
python3 /work/bin/shani app 2>/dev/null | grep -q '^messages ' \
    && result messages-is-an-app PASS || result messages-is-an-app FAIL "not in shani app"
ipc closeAll