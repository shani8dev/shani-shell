# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-nautilus)
# ---- Nautilus parity: Redo, Shift+Delete (gone for good, the rest of the trash
#      kept), Nautilus scripts run with the chosen files ----
N=/tmp/files-nautilus; rm -rf $N; mkdir -p $N/a $N/b; printf x > $N/a/doc.txt; printf y > $N/keep-in-trash.txt
ipc filesOpen "$N/a"; sleep 1
# redo: trashed, undone (put back), redone (trashed again)
ipc filesSelect "$N/a/doc.txt"; ipc filesTrash; waitfor "'doc.txt' not in d['filesNames']" 5
ipc filesUndo; waitfor "'doc.txt' in d['filesNames']" 5
waitfor "d['filesRedo'] != ''" 4
ipc filesRedo
waitfor "'doc.txt' not in d['filesNames']" 5 && result files-redo PASS || result files-redo FAIL "$(q "['filesNames'], d['filesRedo'], d['filesError']")"
ipc filesUndo; waitfor "'doc.txt' in d['filesNames']" 5
# delete for good: only that one leaves the trash; what was in the trash before stays
ipc filesOpen "$N"; sleep 0.8; ipc filesSelect "$N/keep-in-trash.txt"; ipc filesTrash; sleep 1; ipc filesOpen "$N/a"; sleep 0.8
before=$(ls "$HOME/.local/share/Trash/files" | grep -c keep-in-trash)
ipc filesDeleteNow "$N/a/doc.txt"
waitfor "'doc.txt' not in d['filesNames']" 6; sleep 0.5
[ ! -e $N/a/doc.txt ] && ! ls "$HOME/.local/share/Trash/files" | grep -q '^doc' && [ "$(ls "$HOME/.local/share/Trash/files" | grep -c keep-in-trash)" = "$before" ] && [ "$before" -ge 1 ] \
    && result files-delete-for-good PASS || result files-delete-for-good FAIL "$(ls "$HOME/.local/share/Trash/files" | tr '\n' ' ')"
# a Nautilus script: listed, and run with the chosen files and Nautilus's variables
S="$HOME/.local/share/nautilus/scripts"; mkdir -p "$S"
printf '#!/bin/sh\nprintf "%%s|%%s|%%s" "$PWD" "$1" "$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS" > /tmp/script-ran\n' > "$S/Note_it"; chmod +x "$S/Note_it"
printf z > $N/a/pic.jpg; rm -f /tmp/script-ran
ipc filesLoadScripts; waitfor "'Note it' in d['filesScripts']" 5
ipc filesRunScript "Note it" "$N/a/pic.jpg"
for i in $(seq 1 20); do [ -s /tmp/script-ran ] && break; sleep 0.25; done
[ "$(cat /tmp/script-ran 2>/dev/null)" = "$N/a|$N/a/pic.jpg|$N/a/pic.jpg" ] && result files-nautilus-scripts PASS || result files-nautilus-scripts FAIL "$(cat /tmp/script-ran 2>&1)"
rm -rf "$S/Note_it" $N /tmp/script-ran; ipc closeAll
