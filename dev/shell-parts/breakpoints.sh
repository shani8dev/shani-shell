# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=breakpoints)
# ---- width breakpoints (docs/FORM-FACTORS.md): a phone's width ----
# The dev screen made phone-narrow by its scale (1920 / 4 = 480 logical pixels):
# Settings becomes one pane at a time - the page, a way back to the categories,
# a category opening its page again - and a computer's width brings both back.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
niri msg output winit scale 4 >/dev/null 2>&1; sleep 1.5
ipc settingsCategory sound
waitfor "d['settingsOpen'] and d['settingsCompact'] and d['settingsShowingPage']" 6 \
    && result breakpoints-settings-one-pane PASS || result breakpoints-settings-one-pane FAIL "$(q "['settingsOpen'], d['settingsCompact'], d['settingsShowingPage']")"
shot breakpoints-settings-page 0.4
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "Categories" >/dev/null 2>&1
    waitfor "not d['settingsShowingPage']" 4 && result breakpoints-settings-back-to-categories PASS || result breakpoints-settings-back-to-categories FAIL "$(q "['settingsShowingPage']")"
    shot breakpoints-settings-categories 0.3
fi
ipc settingsCategory network
waitfor "d['settingsShowingPage']" 4 && result breakpoints-settings-category-opens-page PASS || result breakpoints-settings-category-opens-page FAIL
ipc toggleControlCenter; sleep 1; shot breakpoints-quick-settings 0.3; ipc closeAll
ipc launcher ""; sleep 1; shot breakpoints-launcher 0.3; ipc closeAll
niri msg output winit scale 1 >/dev/null 2>&1; sleep 1.5
ipc settingsCategory sound
waitfor "d['settingsOpen'] and not d['settingsCompact']" 6 && result breakpoints-settings-two-panes-again PASS || result breakpoints-settings-two-panes-again FAIL "$(q "['settingsCompact']")"
ipc closeAll
