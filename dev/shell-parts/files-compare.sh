# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-compare)
# ---- Files > Compare (Meld's job): two texts side by side, two folders ----
E=/tmp/files-compare; rm -rf $E; mkdir -p $E/a $E/b
printf 'one\ntwo\nthree\n' > $E/a/x.txt; printf 'one\nTWO\nthree\nfour\n' > $E/b/x.txt
printf 'only' > $E/a/left.txt
ipc filesOpen "$E/a"; sleep 1
ipc filesCompare "$E/a/x.txt" "$E/b/x.txt"
waitfor "d['filesCompare'] and not json.loads(d['filesCompare'])['loading']" 6
c=$(q "['filesCompare']")
case "$c" in *'"kind":"text"'*'"changes":2'*'"rows":4'*) result files-compare-text PASS ;; *) result files-compare-text FAIL "$c" ;; esac
shot files-compare 0.3
# merging (Meld): the left's "two" copied over the right's "TWO", the right saved;
# its old version in the trash
ipc filesCompareTake 1 true; sleep 0.3; ipc filesCompareSave true
for i in $(seq 1 20); do grep -qx two $E/b/x.txt && break; sleep 0.25; done
[ "$(cat $E/b/x.txt)" = "$(printf 'one\ntwo\nthree\nfour')" ] && ls "$HOME/.local/share/Trash/files" | grep -q '^x' \
    && result files-compare-merge PASS || result files-compare-merge FAIL "$(cat $E/b/x.txt | tr '\n' '|') $(ls $HOME/.local/share/Trash/files 2>&1 | tr '\n' ' ')"
wtype -k Escape; sleep 0.5
[ -z "$(q "['filesCompare']")" ] && result files-compare-escape PASS || result files-compare-escape FAIL "$(q "['filesCompare']")"
ipc filesCompare "$E/a" "$E/b"
waitfor "d['filesCompare'] and not json.loads(d['filesCompare'])['loading']" 6
c=$(q "['filesCompare']")
case "$c" in *'"kind":"folders"'*'"changes":2'*) result files-compare-folders PASS ;; *) result files-compare-folders FAIL "$c" ;; esac
wtype -k Escape; sleep 0.3
rm -rf $E; ipc closeAll
