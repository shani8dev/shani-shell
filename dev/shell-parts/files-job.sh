# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-job)
# ---- Files: a big copy says how far it is, can be stopped, and holds nothing up ----
# The copy runs as its own process (files.py job); the suite's slow drive
# (/tmp/files-job-delay: seconds per 1 MiB chunk) keeps it going long enough to watch.
J=/tmp/files-job; rm -rf $J; mkdir -p $J/src $J/dest
head -c $((24 << 20)) /dev/urandom > $J/src/big.bin
echo 0.15 > /tmp/files-job-delay
ipc filesOpen "$J/dest"; sleep 1
printf 'file://%s\n' "$J/src/big.bin" | wl-copy --type text/uri-list
ipc filesPaste "$J/dest"
waitfor "d['filesJobRunning'] and d['filesJobDone'] > 0 and d['filesJobTotal'] == $((24 << 20))" 8 \
    && result files-job-progress PASS || result files-job-progress FAIL "running $(q "['filesJobRunning']") done $(q "['filesJobDone']") total $(q "['filesJobTotal']")"
shot files-job 0.2
# while it copies, the folder is still listed and a new folder is still made: nothing waits on the copy
ipc filesOpen "$J/src"; sleep 1.5
[ "$(q "['filesEntries']")" -ge 1 ] && [ "$(q "['filesJobRunning']")" = True ] \
    && result files-job-holds-nothing-up PASS || result files-job-holds-nothing-up FAIL "entries $(q "['filesEntries']") running $(q "['filesJobRunning']")"
ipc filesCancelJob
waitfor "not d['filesJobRunning']" 8 && [ -z "$(ls $J/dest)" ] && [ "$(stat -c %s $J/src/big.bin)" = $((24 << 20)) ] \
    && result files-job-stop-leaves-nothing-half PASS || result files-job-stop-leaves-nothing-half FAIL "$(ls -la $J/dest | tail -2) running $(q "['filesJobRunning']")"
# and a copy that runs to the end is whole, with Undo
echo 0 > /tmp/files-job-delay
ipc filesPaste "$J/dest"
# (the file itself, whole: the Undo label may already say "copied here" from an earlier test)
for i in $(seq 1 60); do [ "$(stat -c %s $J/dest/big.bin 2>/dev/null)" = $((24 << 20)) ] && break; sleep 0.25; done
waitfor "not d['filesJobRunning'] and 'copied here' in d['filesUndo']" 15 && [ "$(sha256sum < $J/src/big.bin)" = "$(sha256sum < $J/dest/big.bin)" ] \
    && result files-job-copy-whole PASS || result files-job-copy-whole FAIL "undo '$(q "['filesUndo']")' $(ls -la $J/dest | tail -1)"
rm -f /tmp/files-job-delay; rm -rf $J; ipc closeAll
