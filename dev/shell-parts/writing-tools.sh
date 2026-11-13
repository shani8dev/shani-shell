# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=writing-tools)
# ---- writing tools: the selected text, Chronoa's version (Agent.Write), Replace ----
# Against the mock, whose Write answers "[<first word of the instruction>] <text>";
# CHRONOA=real puts the real model behind the same calls (chronoa-real.sh).
printf 'teh cat sat' | wl-copy --primary
ipc writingTools
waitfor "d['writingShown'] and d['writingSource'] == 'teh cat sat' and d['writingFrom'] == 'selection'" 5 \
    && result writing-tools-take-the-selection PASS || result writing-tools-take-the-selection FAIL "$(q "['writingShown'], d['writingSource'], d['writingFrom']")"
ipc writingToolsChoose 0                     # Proofread
waitfor "d['writingResult'] == '[fix] teh cat sat' and not d['writingBusy']" 10 \
    && result writing-tools-chronoa-writes PASS || result writing-tools-chronoa-writes FAIL "result '$(q "['writingResult']")' error '$(q "['writingError']")'"
sleep 0.5; shot writing-tools 0.2
ipc writingToolsTranslate "Deutsch"
waitfor "d['writingResult'] == '[translate] teh cat sat'" 10 && result writing-tools-translate PASS || result writing-tools-translate FAIL "$(q "['writingResult']")"
ipc writingToolsClose

# a failure is said, not shown as an empty answer
printf 'please fail' | wl-copy --primary
ipc writingTools; waitfor "d['writingSource'] == 'please fail'" 5; ipc writingToolsChoose 1
waitfor "'asked to fail' in d['writingError'] and not d['writingBusy']" 10 && result writing-tools-error-in-words PASS || result writing-tools-error-in-words FAIL "$(q "['writingError']")"
ipc writingToolsClose

# Replace: the result goes back into the window that had the text (a terminal: Ctrl+Shift+V)
rm -f /tmp/wt-out
foot -a footwt sh -c 'IFS= read -r l; printf "%s" "$l" > /tmp/wt-out; sleep 3' >/dev/null 2>&1 &
waitfor "d['windows'] >= 1" 6; sleep 1
wid=$(niri msg -j windows | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if w['app_id']=='footwt'))" 2>/dev/null)
niri msg action focus-window --id "$wid"; sleep 0.4
printf 'helo world' | wl-copy --primary
ipc writingTools; waitfor "d['writingSource'] == 'helo world'" 5
ipc writingToolsChoose 4                     # Shorter
waitfor "d['writingResult'] == '[make] helo world'" 10
ipc writingToolsReplace; sleep 1.5
wtype -k Return; sleep 1
[ "$(cat /tmp/wt-out 2>/dev/null)" = "[make] helo world" ] && result writing-tools-replace-pastes-back PASS \
    || result writing-tools-replace-pastes-back FAIL "the terminal got '$(cat /tmp/wt-out 2>&1)'"
pkill -f "wt-out" 2>/dev/null

# nothing selected: what was copied
wl-copy --primary --clear; printf 'from the clipboard' | wl-copy
ipc writingTools
waitfor "d['writingSource'] == 'from the clipboard' and d['writingFrom'] == 'clipboard'" 5 \
    && result writing-tools-fall-back-to-clipboard PASS || result writing-tools-fall-back-to-clipboard FAIL "$(q "['writingSource'], d['writingFrom']")"
ipc writingToolsClose; ipc closeAll
