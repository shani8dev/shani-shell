# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-ops)
# ---- Files: copy / cut / paste with other apps, undo, the trash, Properties,
# batch rename, bookmarks, search through folders ----
R=/root/fo; rm -rf $R; mkdir -p $R/a $R/b $R/deep/x/y
echo one > $R/a/note.txt; echo pic > $R/a/photo.jpg; echo bill > "$R/deep/x/y/electricity bill.pdf"
names() { q "['filesNames']"; }
ipc filesOpen $R/b; sleep 1.2

# copy, paste: a copy here; undo takes it away (to the trash, not gone)
ipc filesCopy "$R/a/note.txt"; sleep 0.4
[ "$(wl-paste -n --type text/uri-list 2>/dev/null)" = "file:///root/fo/a/note.txt" ] \
    && result files-copy-is-other-apps-clipboard PASS || result files-copy-is-other-apps-clipboard FAIL "$(wl-paste --list-types 2>&1 | tr '\n' ' ')"
ipc filesPaste $R/b
waitfor "'note.txt' in d['filesNames']" 5 && [ -f $R/a/note.txt ] && result files-paste-copies PASS || result files-paste-copies FAIL "$(names)"
ipc filesPaste $R/b
waitfor "'note (2).txt' in d['filesNames']" 5 && result files-paste-never-writes-over PASS || result files-paste-never-writes-over FAIL "$(names)"
ipc filesUndo
waitfor "'note (2).txt' not in d['filesNames']" 5 && result files-undo-paste PASS || result files-undo-paste FAIL "$(names)"

# cut, paste: moved; the clipboard is spent; undo moves it back
ipc filesCut "$R/a/photo.jpg"; sleep 0.4; ipc filesPaste $R/b
waitfor "'photo.jpg' in d['filesNames']" 5 && [ ! -e $R/a/photo.jpg ] && result files-cut-paste-moves PASS || result files-cut-paste-moves FAIL "$(names); a: $(ls $R/a)"
ipc filesUndo
for i in $(seq 20); do [ -e $R/a/photo.jpg ] && break; sleep 0.25; done
[ -e $R/a/photo.jpg ] && [ ! -e $R/b/photo.jpg ] && result files-undo-move PASS || result files-undo-move FAIL "a: $(ls $R/a); b: $(ls $R/b)"

# files copied in another app paste here (text/uri-list from anyone)
echo other > /root/from-app.txt; wl-copy --type text/uri-list "file:///root/from-app.txt"; sleep 0.3
ipc filesPaste $R/b
waitfor "'from-app.txt' in d['filesNames']" 5 && result files-paste-from-another-app PASS || result files-paste-from-another-app FAIL "$(names)"

# rename, then undo
ipc filesRename "$R/b/from-app.txt" "renamed.txt"
waitfor "'renamed.txt' in d['filesNames']" 5; ipc filesUndo
waitfor "'from-app.txt' in d['filesNames'] and 'renamed.txt' not in d['filesNames']" 5 && result files-undo-rename PASS || result files-undo-rename FAIL "$(names)"

# several renamed at once, then undo
ipc filesBatchRename "Holiday #" "$R/b/note.txt
$R/b/from-app.txt"
waitfor "'Holiday 1.txt' in d['filesNames'] and 'Holiday 2.txt' in d['filesNames']" 5 && result files-batch-rename PASS || result files-batch-rename FAIL "$(names)"
ipc filesUndo
waitfor "'note.txt' in d['filesNames'] and 'from-app.txt' in d['filesNames']" 5 && result files-undo-batch-rename PASS || result files-undo-batch-rename FAIL "$(names)"

# the trash: in, undo; in again, put back from the trash; emptied
ipc filesSelect "$R/b/note.txt"; ipc filesTrash
waitfor "'note.txt' not in d['filesNames']" 5; ipc filesUndo
waitfor "'note.txt' in d['filesNames']" 5 && result files-undo-trash PASS || result files-undo-trash FAIL "$(names)"
ipc filesSelect "$R/b/note.txt"; ipc filesTrash; waitfor "'note.txt' not in d['filesNames']" 5
ipc filesOpen /root/.local/share/Trash/files
waitfor "'note.txt' in d['filesTrashNames']" 5
ipc filesPutBack /root/.local/share/Trash/files/note.txt
for i in $(seq 20); do [ -e $R/b/note.txt ] && break; sleep 0.25; done
[ -e $R/b/note.txt ] && result files-put-back-from-trash PASS || result files-put-back-from-trash FAIL "trash $(q "['filesTrashNames']")"
echo gone > $R/b/junk.txt; ipc filesOpen $R/b; sleep 0.8; ipc filesSelect "$R/b/junk.txt"; ipc filesTrash; sleep 0.8
ipc filesOpen /root/.local/share/Trash/files; waitfor "len(d['filesTrashNames']) > 0" 5
ipc filesEmptyTrash
waitfor "d['filesTrashNames'] == []" 5 && [ -z "$(ls /root/.local/share/Trash/files)" ] && result files-empty-trash PASS || result files-empty-trash FAIL "$(ls /root/.local/share/Trash/files)"

# Properties: counted through the folder
ipc filesOpen $R; sleep 0.8
ipc filesProps "$R/deep"
waitfor "d['filesProps'] and json.loads(d['filesProps']).get('files') == 1 and json.loads(d['filesProps']).get('dirs') == 3" 5 \
    && result files-properties PASS || result files-properties FAIL "$(q "['filesProps']")"
shot files-properties 0.2
ipc filesProps ""; ipc closeAll; ipc filesOpen $R; sleep 0.6

# a bookmark in the sidebar (GTK's file)
ipc filesBookmark $R/deep true
waitfor "'$R/deep' in d['filesBookmarks']" 5 && grep -q "file:///root/fo/deep" /root/.config/gtk-3.0/bookmarks \
    && result files-bookmark-in-sidebar PASS || result files-bookmark-in-sidebar FAIL "$(q "['filesBookmarks']")"
ipc filesBookmark $R/deep false

# search through the folders under this one
ipc filesSearchDeep true; ipc filesSearch "electricity"
waitfor "d['filesNames'] == ['electricity bill.pdf']" 6 && result files-search-through-folders PASS || result files-search-through-folders FAIL "$(names)"
ipc filesSearch ""; ipc filesSearchDeep false
waitfor "'deep' in d['filesNames']" 5 && result files-search-cleared-shows-folder PASS || result files-search-cleared-shows-folder FAIL "$(names)"
ipc closeAll
