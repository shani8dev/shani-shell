# The screen keyboard's word engine, live (bridge/osk-predict.py through
# Services/Osk): autocorrect on space and its undo, learning the next word,
# a swipe decoded into a word, capitals at a sentence's start, the emoji panel.
# Typed through the same path as a finger (oskPress), into the launcher's field
# (read back as launcherText: what the field holds, not what it matches).
ipc launcher ""
ipc osk
waitfor "d['osk'] and d['oskEngine']" 8 && result osk-engine-runs-with-the-keyboard PASS \
    || result osk-engine-runs-with-the-keyboard FAIL "osk $(q "['osk']") engine $(q "['oskEngine']")"
waitfor "d['oskShift']" 3 && result osk-capital-at-the-start PASS || result osk-capital-at-the-start FAIL "shift $(q "['oskShift']")"
for k in t e h; do ipc oskPress "$k"; sleep 0.25; done
waitfor "d['oskCorrection'] == 'the'" 4 && result osk-offers-a-correction PASS || result osk-offers-a-correction FAIL "$(q "['oskCorrection']") predicted $(q "['oskPredicted']")"
ipc oskPress space
waitfor "d['launcherText'] == 'the '" 4 && result osk-autocorrects-on-space PASS || result osk-autocorrects-on-space FAIL "$(q "['launcherText']")"
ipc oskPress BackSpace
waitfor "d['launcherText'] == 'teh'" 4 && result osk-backspace-undoes-the-correction PASS || result osk-backspace-undoes-the-correction FAIL "$(q "['launcherText']")"
ipc oskPress space            # kept as typed: the undone correction is not made again
waitfor "d['launcherText'] == 'teh '" 4 && result osk-undone-correction-stays-undone PASS || result osk-undone-correction-stays-undone FAIL "$(q "['launcherText']")"
shot osk-smart-correction 0.3
ipc osk
ipc closeAll

# learning: a pair typed once is offered next time
ipc launcher ""
ipc osk
waitfor "d['oskEngine']" 8
# Use a nonce outside the autocorrect distance of words in the system dictionary.
for k in s e e space y o u space z q x v j k space; do ipc oskPress "$k"; sleep 0.2; done
ipc osk; ipc closeAll
ipc launcher ""
ipc osk
waitfor "d['oskEngine']" 8
for k in y o u space; do ipc oskPress "$k"; sleep 0.2; done
waitfor "'zqxvjk' in d['oskPredicted']" 4 && result osk-learns-the-next-word PASS || result osk-learns-the-next-word FAIL "$(q "['oskPredicted']")"
shot osk-smart-next-word 0.3
ipc osk; ipc closeAll

# a swipe: the press typed the first letter; the word replaces it
ipc launcher ""
ipc osk
waitfor "d['oskEngine']" 8
ipc oskPress h; sleep 0.2
ipc oskSwipe hgfdertyuioklo
waitfor "d['launcherText'] == 'hello '" 4 && result osk-swipe-types-a-word PASS || result osk-swipe-types-a-word FAIL "$(q "['launcherText']") typed $(q "['oskTyped']")"
ipc osk; ipc closeAll

# the emoji panel: Unicode's groups, and an emoji typed like a key
ipc launcher ""
ipc osk
ipc oskPage emoji
waitfor "d['oskPage'] == 'emoji' and d['emojiGroups'] >= 8" 6 && result osk-emoji-panel-has-the-groups PASS \
    || result osk-emoji-panel-has-the-groups FAIL "page $(q "['oskPage']") groups $(q "['emojiGroups']")"
shot osk-smart-emoji 0.5
ipc oskPress "😀"
waitfor "d['launcherText'] == '😀'" 4 && result osk-types-an-emoji PASS || result osk-types-an-emoji FAIL "$(q "['launcherText']")"
ipc oskPage clip
waitfor "d['oskPage'] == 'clip'" 3 && result osk-clipboard-panel-opens PASS || result osk-clipboard-panel-opens FAIL "$(q "['oskPage']")"
shot osk-smart-clipboard 0.4
ipc oskPage letters
ipc osk; ipc closeAll
