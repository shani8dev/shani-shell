# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=file-portal)
# ---- the file-chooser portal backend (bridge/portal.py): a sandboxed app's Open and
#      Save dialogs are the shell's own picker - called as xdg-desktop-portal calls
#      it (org.freedesktop.impl.portal.FileChooser), answered with file URIs ----
P=/tmp/portal-test; rm -rf $P; mkdir -p "$P/Pictures"; printf x > "$P/Pictures/sea view.png"; printf x > "$P/Pictures/notes.txt"
SHANI_QS_CONFIG=/work/shani python3 /work/bridge/portal.py >/work/out/logs/portal.log 2>&1 & ppid=$!
sleep 1
# Open: a picture (the app's filter: *.png), chosen and accepted
python3 /work/dev/portal-call.py OpenFile /org/freedesktop/portal/desktop/request/1_1/t1 "Open a picture" "$P/Pictures" "" png > $P/open.out 2>&1 &
waitfor "d['pickerShown']" 8
[ "$(q "['pickerPath']")" = "$P/Pictures" ] && result portal-starts-in-the-apps-folder PASS || result portal-starts-in-the-apps-folder FAIL "$(q "['pickerPath']")"
ipc filePickerSelect "$P/Pictures/sea view.png"; sleep 0.3; ipc filePickerAccept
for i in $(seq 1 30); do [ -s $P/open.out ] && break; sleep 0.2; done
[ "$(cat $P/open.out)" = "0 file://$P/Pictures/sea%20view.png" ] && result portal-open-file PASS || result portal-open-file FAIL "$(cat $P/open.out)"
# Save: the name the app suggests, in the folder it suggests
python3 /work/dev/portal-call.py SaveFile /org/freedesktop/portal/desktop/request/1_1/t2 "Save" "$P" report.odt > $P/save.out 2>&1 &
waitfor "d['pickerShown']" 8; echo "SAVEPATH $(q "['pickerPath']")"; sleep 0.3; ipc filePickerAccept
for i in $(seq 1 30); do [ -s $P/save.out ] && break; sleep 0.2; done
[ "$(cat $P/save.out)" = "0 file://$P/report.odt" ] && result portal-save-file PASS || result portal-save-file FAIL "$(cat $P/save.out) picker at $(q "['pickerPath']")"
# Cancel: the app is told so (response 1)
python3 /work/dev/portal-call.py OpenFile /org/freedesktop/portal/desktop/request/1_1/t3 "Open" "" > $P/cancel.out 2>&1 &
waitfor "d['pickerShown']" 8; sleep 0.3; ipc filePickerClose
for i in $(seq 1 30); do [ -s $P/cancel.out ] && break; sleep 0.2; done
[ "$(cat $P/cancel.out | tr -d ' ')" = "1" ] && result portal-cancel PASS || result portal-cancel FAIL "$(cat $P/cancel.out)"
kill $ppid 2>/dev/null; rm -rf $P; ipc closeAll
