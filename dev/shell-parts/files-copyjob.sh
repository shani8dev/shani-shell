# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-copyjob)
# ---- TeraCopy's features in Files' copies: pause/resume with speed, verify, a rule
#      asked once for taken names, Copy to…, checksums made and tested, history ----
C=/tmp/files-copyjob; rm -rf $C; mkdir -p $C/src $C/dest
head -c 4000000 /dev/urandom > $C/src/big.bin; printf one > $C/src/a.txt; printf old > $C/dest/a.txt; touch -d 2020-01-01 $C/dest/a.txt
ipc filesOpen "$C/src"; sleep 1
ipc filesVerify true
echo 1.5 > /tmp/files-job-delay                          # a slow drive: 1.5 s a megabyte (one chunk)
ipc filesCopyTo copy "$C/src/big.bin" "$C/dest"
waitfor "d['filesJobRunning'] and d['filesJobRate'] > 0" 8 && result files-copy-speed PASS || result files-copy-speed FAIL "$(q "['filesJobRunning'], d['filesJobRate']")"
ipc filesJobPause
waitfor "d['filesJobPaused']" 5; d1=$(q "['filesJobDone']"); sleep 1.2; d2=$(q "['filesJobDone']")
[ "$(q "['filesJobPaused']")" = True ] && [ "$d1" = "$d2" ] && result files-copy-pause PASS || result files-copy-pause FAIL "paused $(q "['filesJobPaused']") $d1 -> $d2"
shot files-copy-paused 0.2
ipc filesJobPause; echo 0 > /tmp/files-job-delay
waitfor "not d['filesJobRunning']" 30 && [ "$(md5sum < $C/src/big.bin)" = "$(md5sum < $C/dest/big.bin)" ] && result files-copy-resumes-and-verifies PASS || result files-copy-resumes-and-verifies FAIL "$(q "['filesJobRunning'], d['filesError']")"
# a taken name: asked once; "Replace where different" replaces it (the old one to the trash)
ipc filesCopyTo copy "$C/src/a.txt" "$C/dest"
waitfor "d['filesConflict'] == ['a.txt']" 6 && result files-copy-asks-once PASS || result files-copy-asks-once FAIL "$(q "['filesConflict']")"
ipc filesConflictAnswer differs
waitfor "not d['filesJobRunning'] and d['filesConflict'] == []" 10; sleep 0.5
[ "$(cat $C/dest/a.txt)" = one ] && grep -rqx old "$HOME/.local/share/Trash/files" 2>/dev/null && result files-copy-replace-to-trash PASS || result files-copy-replace-to-trash FAIL "$(cat $C/dest/a.txt) $(ls $HOME/.local/share/Trash/files 2>&1 | tr '\n' ' ')"
# checksums: made, then tested (one file changed afterwards: said so)
ipc filesChecksums "$C/dest"
waitfor "not d['filesJobRunning']" 10; sleep 0.5
s=$(ls $C/dest.sha256 $C/*.sha256 2>/dev/null | head -1)
[ -n "$s" ] && grep -q 'dest/big.bin' "$s" && result files-checksums-made PASS || result files-checksums-made FAIL "$(ls $C)"
ipc filesCheckSums "$s"
waitfor "d['filesLastCheck'] != ''" 10 && [ "$(q "['filesLastCheck']")" = '{"good":2,"bad":0,"missing":0}' ] && result files-checksums-match PASS || result files-checksums-match FAIL "$(q "['filesLastCheck']")"
printf changed > $C/dest/a.txt; ipc filesCheckSums "$s"
waitfor "'\"bad\":1' in d['filesLastCheck']" 10 && result files-checksums-catch-a-change PASS || result files-checksums-catch-a-change FAIL "$(q "['filesLastCheck']")"
ipc filesHistory
waitfor "d['filesCopyHistory'] >= 4" 6 && result files-copy-history PASS || result files-copy-history FAIL "$(q "['filesCopyHistory']")"
shot files-copy-history 0.2
ipc filesVerify false; rm -f /tmp/files-job-delay; ipc closeAll; rm -rf $C
