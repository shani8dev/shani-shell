# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=archives)
# ---- Archive Manager: passwords, one item out, Compress ----
R=/tmp/archive-test; rm -rf $R; mkdir -p $R/src/sub
printf 'secret-content\n' > $R/src/s.txt; printf 'inner\n' > $R/src/sub/inner.txt
( cd $R/src && bsdtar --format zip --options zip:encryption=zipcrypt --passphrase hunter2 -cf $R/locked.zip s.txt sub )

# a protected archive asks for its password - it does not hang (bsdtar alone would loop forever)
ipc archiveOpen "$R/locked.zip"; waitfor "d['archiveEntries'] > 0" 6
ipc archiveExtract ""
waitfor "d['archivePassword'] and not d['archiveExtracting']" 8 \
    && result archive-asks-for-the-password PASS || result archive-asks-for-the-password FAIL "password $(q "['archivePassword']"), extracting $(q "['archiveExtracting']"), error '$(q "['archiveError']")'"
[ -z "$(ls -d $R/locked* 2>/dev/null | grep -v 'locked.zip$')" ] && result archive-no-half-made-folder PASS || result archive-no-half-made-folder FAIL "$(ls $R)"
shot archive-password 0.2
ipc archiveUnlock "wrong"
waitfor "d['archivePassword'] and 'not right' in d['archiveError']" 8 && result archive-wrong-password-said PASS || result archive-wrong-password-said FAIL "$(q "['archiveError']")"
ipc archiveUnlock "hunter2"
waitfor "d['archiveExtractedTo'] != ''" 8 && [ "$(cat "$(q "['archiveExtractedTo']")/s.txt" 2>/dev/null)" = secret-content ] \
    && result archive-right-password-extracts PASS || result archive-right-password-extracts FAIL "to '$(q "['archiveExtractedTo']")' error '$(q "['archiveError']")'"

# one item, beside the archive, never over a file of the same name
printf 'already here\n' > $R/s.txt
ipc archiveExtractOne "s.txt"
waitfor "d['archiveExtractedTo'].endswith('s (2).txt')" 8 && [ "$(cat "$R/s (2).txt")" = secret-content ] && [ "$(cat $R/s.txt)" = "already here" ] \
    && result archive-extract-one-beside PASS || result archive-extract-one-beside FAIL "to '$(q "['archiveExtractedTo']")' error '$(q "['archiveError']")'; $(ls $R | tr '\n' ' ')"

# Compress: files into a zip, and a 7z, that read back
ipc archiveCompress "$(printf '%s\n%s' "$R/src/s.txt" "$R/src/sub")" zip
waitfor "d['archiveMade'].endswith('.zip') and not d['archiveCreating']" 10 && bsdtar -tf "$(q "['archiveMade']")" | grep -q "sub/inner.txt" \
    && result archive-compress-zip PASS "$(q "['archiveMade']")" || result archive-compress-zip FAIL "made '$(q "['archiveMade']")' error '$(q "['archiveError']")'"
shot archive-compress 0.2
ipc archiveCompress "$R/src/s.txt" 7z
waitfor "d['archiveMade'].endswith('s.7z')" 10 && bsdtar -tf "$(q "['archiveMade']")" | grep -q "s.txt" \
    && result archive-compress-7z PASS || result archive-compress-7z FAIL "made '$(q "['archiveMade']")' error '$(q "['archiveError']")'"
ls -a $R/src | grep -q "^.shani-archive" && result archive-no-temp-left FAIL || result archive-no-temp-left PASS
ipc archiveClose; ipc closeAll
