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
[ "$(q "['archiveProtected']")" = True ] \
    && result archive-reports-protected PASS || result archive-reports-protected FAIL "$(q "['archiveProtected']")"
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

# a lone compressed file (not a tar): shown as the one file inside, taken out
# beside it with bsdcat, never over a file of the same name (bsdtar alone: "Unrecognized archive format")
printf 'notes-content\n' > $R/notes.txt; xz -k $R/notes.txt; zstd -q $R/notes.txt -o $R/notes.txt.zst
ipc archiveOpen "$R/notes.txt.xz"
waitfor "d['archiveEntries'] == 1 and not d['archiveReading']" 6 && [ -z "$(q "['archiveError']")" ] \
    && result archive-lone-compressed-listed PASS || result archive-lone-compressed-listed FAIL "entries $(q "['archiveEntries']") error '$(q "['archiveError']")'"
ipc archiveExtract ""
waitfor "d['archiveExtractedTo'].endswith('notes (2).txt')" 8 && [ "$(cat "$R/notes (2).txt")" = notes-content ] && [ "$(cat $R/notes.txt)" = notes-content ] \
    && result archive-lone-compressed-extracts-beside PASS || result archive-lone-compressed-extracts-beside FAIL "to '$(q "['archiveExtractedTo']")' error '$(q "['archiveError']")'; $(ls $R | tr '\n' ' ')"
ipc archiveOpen "$R/notes.txt.zst"
waitfor "d['archiveEntries'] == 1" 6 && result archive-lone-zst-listed PASS || result archive-lone-zst-listed FAIL "error '$(q "['archiveError']")'"
printf 'not compressed at all' > $R/fake.gz
ipc archiveOpen "$R/fake.gz"
waitfor "'Not an archive' in d['archiveError']" 6 && result archive-bad-lone-file-said PASS || result archive-bad-lone-file-said FAIL "entries $(q "['archiveEntries']") error '$(q "['archiveError']")'"
ipc archiveClose

# ---- adding to an archive that is open, and making a protected one ----------
# a zip can be added to (bridge/zipadd.py - libarchive cannot append to one);
# a compressed tar cannot, and says so instead of quietly doing nothing
( cd $R/src && bsdtar -acf $R/plain.zip s.txt sub )
ipc archiveOpen "$R/plain.zip"; waitfor "d['archiveEntries'] > 0" 6
[ "$(q "['archiveProtected']")" = False ] \
    && result archive-plain-is-not-protected PASS || result archive-plain-is-not-protected FAIL "$(q "['archiveProtected']")"
[ "$(q "['archiveCanAppend']")" = True ] && result archive-zip-can-be-added-to PASS || result archive-zip-can-be-added-to FAIL "$(q "['archiveCanAppend']")"
printf 'added-later\n' > $R/src/late.txt
ipc archiveAppend "$R/src/late.txt"
# the name it takes is its path from the archive's own folder
waitfor "any(n.endswith('late.txt') for n in (d['archiveNames'] or []))" 8 \
    && result archive-added-to-the-zip PASS "$(q "['archiveNames']")" || result archive-added-to-the-zip FAIL "$(q "['archiveNames']") error '$(q "['archiveError']")'"

# a protected archive is refused, not silently rewritten as a readable one
ipc archiveOpen "$R/locked.zip"; waitfor "d['archiveEntries'] > 0" 6
ipc archiveUnlock "hunter2"; sleep 0.5
printf 'nope\n' > $R/src/no.txt
ipc archiveAppend "$R/src/no.txt"; sleep 1.8
grep -q 'protected' <<<"$(q "['archiveError']")" && result archive-protected-refused PASS "$(q "['archiveError']")" || result archive-protected-refused FAIL "$(q "['archiveError']")"
# and the archive itself is unchanged by the refusal
bsdtar --passphrase hunter2 -tf "$R/locked.zip" | grep -q 'late' && result archive-protected-refusal-changed-it FAIL "it was rewritten" || result archive-protected-refusal-changed-it PASS

# a tar.gz cannot be appended to by bsdtar - it says so in words
( cd $R/src && bsdtar -czf $R/plain.tar.gz s.txt )
ipc archiveOpen "$R/plain.tar.gz"; waitfor "d['archiveEntries'] > 0" 6
[ "$(q "['archiveCanAppend']")" = False ] && result archive-compressed-tar-refused PASS || result archive-compressed-tar-refused FAIL "$(q "['archiveCanAppend']")"

# a password on Compress: the archive it makes opens with that password and not without
ipc archiveCompressWith "$R/src/s.txt" zip "open sesame"
waitfor "d['archiveMade'].endswith('.zip') and not d['archiveCreating']" 10 \
    && result archive-compress-with-password-made PASS "$(q "['archiveMade']")" || result archive-compress-with-password-made FAIL "made '$(q "['archiveMade']")' error '$(q "['archiveError']")'"
PZW=$(q "['archiveMade']")
# the names are readable in a zip without the password (only the contents are
# encrypted), so what proves it is the content: the wrong one gives nothing
wrong=$(bsdtar --passphrase "wrong-one" -xOf "$PZW" s.txt 2>/dev/null | head -c 400)
[ "$wrong" = "secret-content" ] && result archive-password-is-needed FAIL "the wrong password gave the content" \
    || result archive-password-is-needed PASS
bsdtar --passphrase "open sesame" -xOf "$PZW" s.txt 2>/dev/null | grep -q 'secret-content' \
    && result archive-password-opens-it PASS || result archive-password-opens-it FAIL "$(bsdtar --passphrase 'open sesame' -tf "$PZW" 2>&1 | tr '\n' ';')"

ipc archiveClose; ipc closeAll
