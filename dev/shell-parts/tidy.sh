# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=tidy)
# ---- Tidy and name: Downloads sorted by kind (shown first, undone), a name from Chronoa ----
T=/tmp/tidy-test/Downloads; rm -rf /tmp/tidy-test; mkdir -p $T
for f in a.jpg b.png song.mp3 doc.pdf notes.txt app.AppImage film.mkv still.crdownload; do printf x > "$T/$f"; done
ipc filesTidy "$T"
waitfor "d['tidyPlanned'] == 7" 6 && result tidy-plans-by-kind PASS "$(q "['tidyGroups']")" || result tidy-plans-by-kind FAIL "$(q "['tidyPlanned'], d['tidyGroups']")"
sleep 0.6; shot tidy-plan 0.2
ipc filesTidyApply
waitfor "d['tidyMoved'] == 7 and d['tidyCanUndo']" 6 && [ -f $T/Pictures/a.jpg ] && [ -f $T/Installers/app.AppImage ] && [ -f $T/still.crdownload ] \
    && result tidy-sorts PASS || result tidy-sorts FAIL "moved $(q "['tidyMoved']"); $(ls -R $T | tr '\n' ' ')"
ipc filesTidyUndo
waitfor "not d['tidyCanUndo']" 6 && [ -f $T/a.jpg ] && [ ! -e $T/Pictures ] && result tidy-undo-puts-back PASS || result tidy-undo-puts-back FAIL "$(ls $T | tr '\n' ' ')"

# a name from the file's own words (the mock's Write: "[suggest] ..." - the real model in chronoa-real.sh)
printf 'Electricity bill for March from City Power\n' > /tmp/tidy-test/scan0001.txt
ipc filesSuggestName /tmp/tidy-test/scan0001.txt
waitfor "d['nameSuggestion'].endswith('.txt') and not d['naming']" 8 && result tidy-suggests-a-name PASS "$(q "['nameSuggestion']")" || result tidy-suggests-a-name FAIL "suggestion '$(q "['nameSuggestion']")' error '$(q "['nameError']")'"
printf '\000\001' > /tmp/tidy-test/blob.bin
ipc filesSuggestName /tmp/tidy-test/blob.bin
waitfor "d['nameError'] != ''" 6 && result tidy-no-words-no-name PASS || result tidy-no-words-no-name FAIL "$(q "['nameSuggestion']")"
ipc closeAll
