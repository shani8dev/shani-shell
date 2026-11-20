# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-lock)
# ---- passwords: a file sealed (gpg) and opened again, a PDF locked (a PDF
#      password) and read in the Document Viewer after its password ----
E=/tmp/files-lock; rm -rf $E; mkdir -p $E
printf 'bank pin 1234' > $E/notes.txt
ipc filesOpen "$E"; sleep 1
ipc filesAskLock lock "$E/notes.txt"
waitfor "d['filesLocker'] == 'lock'" 4; shot files-lock 0.2
ipc filesLockWith "open sesame" gpg
waitfor "d['filesLockResult'] == '$E/notes.txt.gpg'" 10 && ! grep -q 'bank pin' $E/notes.txt.gpg \
    && result files-lock-file PASS || result files-lock-file FAIL "$(q "['filesLockResult'], d['filesLockError']")"
ipc filesAskLock unlock "$E/notes.txt.gpg"; sleep 0.3
ipc filesLockWith "nope" ""
waitfor "d['filesLockError'] != ''" 10 && [ "$(q "['filesLocker']")" = unlock ] && result files-unlock-wrong-password PASS || result files-unlock-wrong-password FAIL "$(q "['filesLockError'], d['filesLocker']")"
ipc filesLockWith "open sesame" ""
waitfor "d['filesLockResult'] == '$E/notes 2.txt'" 10 && [ "$(cat "$E/notes 2.txt")" = "bank pin 1234" ] \
    && result files-unlock-file PASS || result files-unlock-file FAIL "$(q "['filesLockResult'], d['filesLockError']")"
# a ZIP with a password (the default for anything but a PDF): 7-Zip-compatible AES
ipc filesAskLock lock "$E/notes 2.txt"; sleep 0.3; ipc filesLockWith "zip pw" ""
waitfor "d['filesLockResult'] == '$E/notes 2.zip'" 10 && ! grep -q 'bank pin' "$E/notes 2.zip" \
    && result files-lock-zip PASS || result files-lock-zip FAIL "$(q "['filesLockResult'], d['filesLockError']")"
ipc filesAskLock unlock "$E/notes 2.zip"; sleep 0.3; ipc filesLockWith "zip pw" ""
waitfor "d['filesLockResult'] == '$E/notes 2'" 10 && [ "$(cat "$E/notes 2/notes 2.txt")" = "bank pin 1234" ] \
    && result files-unlock-zip PASS || result files-unlock-zip FAIL "$(q "['filesLockResult'], d['filesLockError']")"
# a PDF: locked with a PDF password; the Document Viewer asks for it
if python3 -c 'import pymupdf' 2>/dev/null; then
    python3 -c 'import pymupdf,sys; d=pymupdf.open(); d.new_page().insert_text((72,72),"secret plans"); d.save(sys.argv[1])' $E/plans.pdf
    ipc filesAskLock lock "$E/plans.pdf"; sleep 0.3; ipc filesLockWith "hunter2" ""
    waitfor "d['filesLockResult'] == '$E/plans (locked).pdf'" 10 && result files-lock-pdf PASS || result files-lock-pdf FAIL "$(q "['filesLockResult'], d['filesLockError']")"
    ipc openPdf "$E/plans (locked).pdf"
    waitfor "d['pdfNeedsPassword']" 10 && result pdf-asks-password PASS || result pdf-asks-password FAIL "$(q "['pdfNeedsPassword'], d['pdfError']")"
    shot pdf-password 0.2
    ipc pdfUnlock wrong; waitfor "d['pdfPasswordError'] != ''" 8
    ipc pdfUnlock hunter2
    waitfor "d['pdfPages'] == 1 and not d['pdfNeedsPassword']" 15 && result pdf-opens-with-password PASS || result pdf-opens-with-password FAIL "$(q "['pdfPages'], d['pdfNeedsPassword'], d['pdfPasswordError'], d['pdfError']")"
    ipc closeAll; sleep 0.5
    ls ${XDG_CACHE_HOME:-$HOME/.cache}/shani-pdf/unlocked-*.pdf >/dev/null 2>&1 && result pdf-unlocked-copy-removed FAIL "still there" || result pdf-unlocked-copy-removed PASS
fi
# an encrypted folder (gocryptfs needs /dev/fuse: only where the container has it)
if command -v gocryptfs >/dev/null && [ -c /dev/fuse ]; then
    ipc filesAskLock vault-new "$E"; sleep 0.3; ipc filesLockWith "pw" "Private"
    waitfor "d['filesLockResult'] == '$E/Private'" 10 && [ -f $E/Private/gocryptfs.conf ] && result files-vault-new PASS || result files-vault-new FAIL "$(q "['filesLockError']")"
    ipc filesOpen "$E/Private"
    waitfor "d['filesLocker'] == 'vault-open'" 6; ipc filesLockWith "pw" ""
    waitfor "d['filesPath'].endswith('/vaults/Private')" 10 && result files-vault-open PASS || result files-vault-open FAIL "$(q "['filesPath'], d['filesLockError']")"
    fusermount3 -u "$(q "['filesPath']")" 2>/dev/null
fi
ipc closeAll; rm -rf $E
