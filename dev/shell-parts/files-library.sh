# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-library)
# ---- ES File Explorer parity: every file of a kind (the sidebar's All pictures
#      ...), a folder opened to phones behind a QR code, duplicates found ----
L="$HOME/lib-test"; rm -rf "$L"; mkdir -p "$L/a" "$L/b" "$L/.hidden"
printf sun > "$L/a/sunset.jpg"; printf beach > "$L/b/beach.png"; printf hidden > "$L/.hidden/no.png"; printf song > "$L/a/song.mp3"
ipc filesOpen "kind:pictures"
waitfor "d['filesPath'] == 'kind:pictures' and 'sunset.jpg' in d['filesNames'] and 'beach.png' in d['filesNames']" 10 \
    && [ "$(q "['filesNames']" | grep -c "no.png")" = 0 ] && result files-all-pictures PASS || result files-all-pictures FAIL "$(q "['filesPath'], d['filesNames'][:10]")"
shot files-all-pictures 0.2
# open to phones: the link answers with the folder's files, and a QR code shows it
ipc filesServe "$L/a" false
waitfor "d['filesServedUrl'] != '' and d['qrShown']" 10 && result files-serve-qr PASS || result files-serve-qr FAIL "$(q "['filesServedUrl'], d['qrShown'], d['filesError']")"
u=$(q "['filesServedUrl']" | sed 's|//[^:/]*:|//127.0.0.1:|')
curl -fsS "$u" | grep -q sunset.jpg && curl -fsS "${u%/*/}/" -o /dev/null -w '%{http_code}' 2>/dev/null | grep -q 404 \
    && result files-serve-lists PASS || result files-serve-lists FAIL "$u: $(curl -sS "$u" 2>&1 | head -c 200)"
ipc filesServeStop
waitfor "d['filesServedUrl'] == '' and not d['qrShown']" 6 && ! curl -fsS "$u" >/dev/null 2>&1 && result files-serve-stops PASS || result files-serve-stops FAIL "$(q "['filesServedUrl']")"
# Disk Usage > Duplicates: two copies of a photo; marking every copy but the oldest
# marks the newer one; the trash takes it (and only it)
ipc closeAll; printf 'same bytes' > "$L/a/sunset.jpg"; touch -d '2020-01-01' "$L/a/sunset.jpg"; printf 'same bytes' > "$L/b/sunset copy.jpg"
ipc diskUsageOpen "$L"; sleep 1; ipc diskUsageView dupes
waitfor "d['diskUsageDupes'] == [2]" 15 && result diskusage-duplicates PASS || result diskusage-duplicates FAIL "$(q "['diskUsageDupes'], d['diskUsageView']")"
shot diskusage-dupes 0.2
ipc diskUsageMarkExtras; sleep 0.3
[ "$(q "['diskUsageMarkedPaths']")" = "['$L/b/sunset copy.jpg']" ] && result diskusage-marks-the-copy PASS || result diskusage-marks-the-copy FAIL "$(q "['diskUsageMarkedPaths']")"
ipc diskUsageTrashMarked
waitfor "d['diskUsageDupes'] == []" 15 && [ -f "$L/a/sunset.jpg" ] && [ ! -e "$L/b/sunset copy.jpg" ] && result diskusage-duplicate-trashed PASS || result diskusage-duplicate-trashed FAIL "$(q "['diskUsageDupes'], d['diskUsageLast']")"
ipc diskUsageView big
waitfor "d['diskUsageBig'] >= 3" 10 && result diskusage-biggest PASS || result diskusage-biggest FAIL "$(q "['diskUsageBig']")"
ipc closeAll; rm -rf "$L"
# cloud drives: a stand-in rclone (no network here) - added, listed in the sidebar,
# opened (mounted) with a click
cat > /usr/local/bin/rclone <<'R'
#!/bin/sh
c=/tmp/fake-rclone; touch $c
case "$1" in
listremotes) cat $c ;;
config) case "$2" in create) printf '%s: %s\n' "$3" "$4" >> $c ;; delete) grep -v "^$3: " $c > $c.n; mv $c.n $c ;; esac ;;
mount) mkdir -p "$3"; printf 'hello' > "$3/from-the-cloud.txt" ;;
esac
R
chmod +x /usr/local/bin/rclone; rm -f /tmp/fake-rclone
ipc filesOpen "$HOME"; sleep 1
ipc filesCloudAdd "Work Drive" drive "" "" ""
waitfor "'Work Drive:drive' in d['filesClouds']" 8 && result files-cloud-added PASS || result files-cloud-added FAIL "$(q "['filesClouds'], d['filesCloudError']")"
ipc filesCloudOpen "Work Drive"
waitfor "d['filesPath'].endswith('/cloud/Work Drive') and 'from-the-cloud.txt' in d['filesNames']" 8 && result files-cloud-opens PASS || result files-cloud-opens FAIL "$(q "['filesPath'], d['filesError']")"
shot files-cloud 0.2
rm -f /usr/local/bin/rclone /tmp/fake-rclone; ipc closeAll
# Open as administrator: gvfs's admin:// (fake-gio stands in: mounted, then its path)
: > /tmp/gio-log; ipc filesOpenAsAdmin /etc true
waitfor "d['filesAsAdmin']" 8 && grep -q '^mount admin:///etc' /tmp/gio-log && result files-open-as-admin PASS || result files-open-as-admin FAIL "$(q "['filesPath'], d['filesError']") $(cat /tmp/gio-log | tr '\n' ';')"
ipc closeAll
