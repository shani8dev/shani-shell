# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-dnd)
# ---- Files: what a drop does (filesDrop: the same function the drop areas call) ----
# The drag gesture itself needs a real pointer, which this nested session cannot
# have without moving the host's (dev/session.sh: ydotool needs the host's
# uinput) - tests/test_qml_patterns.py holds that every tile and row is a drag
# source and that the drop areas are there. On the same drive a drop moves; from
# another drive it copies (files.py job auto); Ctrl's copy is mode "copy".
D=/tmp/files-dnd; rm -rf $D; mkdir -p $D/a $D/b/sub
printf 'one' > $D/a/one.txt; printf 'two' > $D/a/two.txt
ipc filesOpen "$D/a"; sleep 1
# two files and a web link: the link is no file, so two move
ipc filesDrop "$D/b/sub" "$(printf 'file://%s\nfile://%s\nhttps://example.org/x.txt' "$D/a/one.txt" "$D/a/two.txt")" auto
waitfor "not d['filesJobRunning'] and d['filesUndo'] == '2 moved here'" 8 && [ -f $D/b/sub/one.txt ] && [ ! -e $D/a/one.txt ] \
    && result files-drop-moves-on-the-same-drive PASS || result files-drop-moves-on-the-same-drive FAIL "undo '$(q "['filesUndo']")' $(ls $D/a $D/b/sub | tr '\n' ' ')"
ipc filesUndo; sleep 1.5
[ -f $D/a/one.txt ] && [ ! -e $D/b/sub/one.txt ] && result files-drop-undo PASS || result files-drop-undo FAIL "$(ls $D/a $D/b/sub | tr '\n' ' ')"
ipc filesDrop "$D/b" "file://$D/a/two.txt" copy >/dev/null
# (the file itself: the Undo label may already say "copied here" from an earlier test)
for i in $(seq 1 32); do [ -f $D/b/two.txt ] && break; sleep 0.25; done
waitfor "not d['filesJobRunning'] and 'copied here' in d['filesUndo']" 8 && [ -f $D/b/two.txt ] && [ -f $D/a/two.txt ] \
    && result files-drop-ctrl-copies PASS || result files-drop-ctrl-copies FAIL "$(ls $D/a $D/b | tr '\n' ' ')"
# onto the folder it is already in: nothing runs, nothing to undo is added
u=$(q "['filesUndo']"); ipc filesDrop "$D/a" "file://$D/a/one.txt" auto; sleep 1.5
[ "$(q "['filesUndo']")" = "$u" ] && [ "$(ls $D/a | tr '\n' ' ')" = "one.txt two.txt " ] \
    && result files-drop-onto-where-it-is-nothing PASS || result files-drop-onto-where-it-is-nothing FAIL "undo '$(q "['filesUndo']")' $(ls $D/a | tr '\n' ' ')"
rm -rf $D; ipc closeAll
