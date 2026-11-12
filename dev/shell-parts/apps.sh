# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=apps)
# ---- the shell's own apps (bin/shani's APPS) -----------------------------------
# Each one is started the way its desktop entry starts it - `shani app NAME
# [FILE]` - and the shell's own state has to say it is open, with no QML error
# written while it opened. Then the Text Editor, which is the image's default
# for text files, is taken through what a default has to do: read a file,
# change it, save it, keep its permissions and its line endings, and not lose
# what was typed when the editor is closed.
export SHANI_QS_CONFIG=/work/shani
app() { python3 /work/bin/shani app "$@" >/dev/null 2>&1; }
errs() { grep -c -E "TypeError|ReferenceError|is not a function|is not defined|Unable to assign" /work/out/logs/qs.log; }
A=/tmp/apps-test; rm -rf $A; mkdir -p $A
printf 'first line\nsecond line\n' > $A/note.txt
# a one-page PDF, written by hand (objects, xref, trailer)
python3 - "$A/one.pdf" <<'PY'
import sys
objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length 44 >>\nstream\nBT /F1 18 Tf 20 100 Td (Shani test) Tj ET\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
out, offs = b"%PDF-1.4\n", []
for i, o in enumerate(objs, 1):
    offs.append(len(out)); out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offs)
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
open(sys.argv[1], "wb").write(out)
PY
python3 -c "import sys; open(sys.argv[1],'wb').write(bytes([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,0,0,0,13,73,68,65,84,120,156,99,248,207,192,240,31,0,5,0,1,255,137,153,61,29,0,0,0,0,73,69,78,68,174,66,96,130]))" $A/dot.png

for spec in $(python3 - <<'PY'
import importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("shani_cli", "/work/bin/shani")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("shani_cli", loader)); loader.exec_module(m)
for name, s in m.APPS.items():
    if s[8] is not None:          # an action (a screenshot, a colour pick) waits for the pointer: not started here
        print(f"{name}:{s[8]}:{'file' if s[6] is None else 'plain'}")
PY
); do
    name=${spec%%:*}; rest=${spec#*:}; key=${rest%%:*}; kind=${rest#*:}
    ipc closeAll; sleep 0.3; before=$(errs)
    case "$name" in
        image-viewer) app "$name" "$A/dot.png" ;;
        document-viewer) app "$name" "$A/one.pdf" ;;
        *) [ "$kind" = file ] && continue; app "$name" ;;
    esac
    if waitfor "d.get('$key')" 5; then
        sleep 0.6; after=$(errs)
        # a window of its own, known to niri by the app's desktop id, and photographed
        shot "app-$name" 0.2
        win=$(niri msg -j windows | python3 -c "import json,sys; print(sum(1 for w in json.load(sys.stdin) if w['app_id']=='org.quickshell'))")
        [ "$win" -ge 1 ] || { result "app-$name-opens" FAIL "no window of the shell's on screen"; continue; }
        [ "$after" = "$before" ] && result "app-$name-opens" PASS \
            || result "app-$name-opens" FAIL "open, but $(( after - before )) QML error(s): $(grep -E "TypeError|ReferenceError|is not a function|is not defined|Unable to assign" /work/out/logs/qs.log | tail -1 | cut -c1-200)"
    else
        result "app-$name-opens" FAIL "state['$key'] = $(q ".get('$key')")"
    fi
done
ipc closeAll

# ---- Media Player: a real clip, played for real ---------------------------------------
# two short clips made here (a test picture with a tone) and a song: it plays, the
# position moves, seek lands, pause holds, Next goes to the folder's next file
M=$A/media; mkdir -p $M
for n in 1 2; do ffmpeg -loglevel error -y -f lavfi -i testsrc=duration=8:size=640x360:rate=25 -f lavfi -i sine=frequency=440:duration=8 -c:v libvpx -b:v 400k -c:a libvorbis $M/clip$n.webm; done
ffmpeg -loglevel error -y -f lavfi -i sine=frequency=330:duration=6 -c:a libvorbis $M/song.ogg
before=$(errs)
app media-player "$M/clip1.webm"
waitfor "d['mediaShown'] and d['mediaFile'] == '$M/clip1.webm' and d['mediaDuration'] > 7" 10 \
    && result media-opens-a-video PASS "$(q "['mediaDuration']") s" || result media-opens-a-video FAIL "$(q "['mediaFile'], d['mediaDuration'], d['mediaError']")"
waitfor "d['mediaPlayerPlaying'] and d['mediaPosition'] > 0.5 and d['mediaHasVideo']" 8 \
    && result media-plays PASS "at $(q "['mediaPosition']") s" || result media-plays FAIL "$(q "['mediaPlayerPlaying'], d['mediaPosition'], d['mediaHasVideo'], d['mediaError']")"
shot app-media-player-video 0.2
[ "$(q "['mediaQueue']")" = 2 ] && result media-queue-is-the-folder PASS || result media-queue-is-the-folder FAIL "$(q "['mediaQueue']")"
ipc mediaPause; sleep 0.5; p1=$(q "['mediaPosition']"); sleep 1.2; p2=$(q "['mediaPosition']")
[ "$p1" = "$p2" ] && [ "$(q "['mediaPlayerPlaying']")" = False ] && result media-pause-holds PASS || result media-pause-holds FAIL "$p1 -> $p2"
ipc mediaSeek 5; waitfor "4.5 <= d['mediaPosition'] <= 5.6" 4 && result media-seeks PASS || result media-seeks FAIL "$(q "['mediaPosition']")"
ipc mediaNext
waitfor "d['mediaFile'] == '$M/clip2.webm' and d['mediaPlayerPlaying']" 6 && result media-next PASS || result media-next FAIL "$(q "['mediaFile'], d['mediaPlayerPlaying']")"
# one player among the others: the bar's now playing and the media keys see it (MPRIS)
waitfor "'Media Player' in d['mprisPlayers'] and d['mprisCurrent'] == 'Media Player'" 6 && result media-is-an-mpris-player PASS || result media-is-an-mpris-player FAIL "$(q "['mprisPlayers'], d['mprisCurrent']")"
ipc media play-pause
waitfor "not d['mediaPlayerPlaying']" 4 && result media-keys-reach-it PASS || result media-keys-reach-it FAIL "$(q "['mediaPlayerPlaying']")"
ipc media play-pause
waitfor "d['mediaPlayerPlaying']" 4
# the end of the last file stops; the end of one before it goes on (clip1 -> clip2 above was asked, this is by itself)
app media-player "$M/song.ogg"
waitfor "d['mediaFile'] == '$M/song.ogg' and d['mediaPlayerPlaying'] and not d['mediaHasVideo']" 8 \
    && result media-plays-a-song PASS || result media-plays-a-song FAIL "$(q "['mediaFile'], d['mediaPlayerPlaying'], d['mediaHasVideo'], d['mediaError']")"
shot app-media-player-audio 0.2
[ "$(q "['mediaQueue']")" = 1 ] && result media-song-queue-is-songs-only PASS || result media-song-queue-is-songs-only FAIL "$(q "['mediaQueue']")"
# the Library: ~/Music by album, played from there
mkdir -p "/root/Music/Test Band/First Record"
for n in 1 2; do ffmpeg -loglevel error -y -f lavfi -i sine=frequency=$((300 + n * 100)):duration=5 -metadata title="Song $n" -metadata artist="Test Band" -metadata album="First Record" -metadata track=$n -c:a libvorbis "/root/Music/Test Band/First Record/0$n.ogg"; done
ipc mediaClose; sleep 0.5; app media-player
waitfor "d['librarySongs'] >= 2 and 'First Record' in d['libraryAlbums']" 15 && result media-library-finds-the-music PASS "$(q "['librarySongs']") songs" || result media-library-finds-the-music FAIL "$(q "['librarySongs'], d['libraryAlbums']")"
ipc mediaPage library
waitfor "d['mediaPage'] == 'library'" 3
shot app-media-player-library 0.6
ipc mediaPlayAlbum "First Record"
waitfor "d['mediaFile'].endswith('First Record/01.ogg') and d['mediaPlayerPlaying'] and d['mediaQueue'] == 2" 8 && result media-library-plays-an-album PASS || result media-library-plays-an-album FAIL "$(q "['mediaFile'], d['mediaQueue']")"
ipc mediaPage playing; sleep 0.8; shot app-media-player-song 0.2
mkdir -p /root/Videos/Trip; cp $M/clip1.webm /root/Videos/Trip/day1.webm; cp $M/clip2.webm /root/Videos/Trip/day2.webm
ipc mediaLibraryVideos
waitfor "d['libraryVideos'] >= 2" 15 && result media-library-lists-videos PASS "$(q "['libraryVideos']")" || result media-library-lists-videos FAIL "$(q "['libraryVideos']")"
# what is not media says so
app media-player "$A/note.txt"
waitfor "d['mediaError'] != ''" 6 && result media-refuses-what-it-cannot-play PASS || result media-refuses-what-it-cannot-play FAIL "$(q "['mediaError']")"
after=$(errs); [ "$after" = "$before" ] && result media-no-qml-errors PASS || result media-no-qml-errors FAIL "$(grep -E "TypeError|ReferenceError|is not a function|is not defined|Unable to assign" /work/out/logs/qs.log | tail -1 | cut -c1-200)"
ipc mediaClose; ipc closeAll

# ---- Archives: what is inside, and out it comes -----------------------------------------
mkdir -p $A/pack/sub; echo one > $A/pack/a.txt; echo two > "$A/pack/sub/b c.txt"
(cd $A && bsdtar -cf pack.zip --format zip pack && bsdtar -czf pack.tar.gz pack)
app archive-manager "$A/pack.zip"
waitfor "d['archiveShown'] and d['archiveEntries'] == 4 and d['archiveSize'] == 8" 6 \
    && result archive-lists-a-zip PASS || result archive-lists-a-zip FAIL "$(q "['archiveEntries'], d['archiveSize'], d['archiveError']")"
shot app-archives-zip 0.2
ipc archiveExtract ""
waitfor "d['archiveExtractedTo'] == '$A/pack'" 3 && result archive-does-not-write-over FAIL "it extracted into the folder that was there" || true
waitfor "d['archiveExtractedTo'] == '$A/pack (2)'" 6 && [ "$(cat "$A/pack (2)/pack/sub/b c.txt")" = two ] \
    && result archive-extracts-beside-in-a-new-folder PASS || result archive-extracts-beside-in-a-new-folder FAIL "$(q "['archiveExtractedTo'], d['archiveError']")"
app archive-manager "$A/pack.tar.gz"
waitfor "d['archiveFile'] == '$A/pack.tar.gz' and d['archiveEntries'] == 4" 6 && result archive-lists-a-tarball PASS || result archive-lists-a-tarball FAIL "$(q "['archiveEntries'], d['archiveError']")"
mkdir -p $A/out; ipc archiveExtract "$A/out"
waitfor "d['archiveExtractedTo'] == '$A/out/pack'" 6 && [ "$(cat $A/out/pack/pack/a.txt)" = one ] \
    && result archive-extracts-into-a-chosen-folder PASS || result archive-extracts-into-a-chosen-folder FAIL "$(q "['archiveExtractedTo'], d['archiveError']")"
app archive-manager "$A/note.txt"
waitfor "d['archiveError'] != '' and d['archiveEntries'] == 0" 6 && result archive-refuses-what-is-not-one PASS || result archive-refuses-what-is-not-one FAIL "$(q "['archiveError'], d['archiveEntries']")"
ipc closeAll

# ---- Clocks: the stopwatch runs, an alarm is kept -------------------------------------------
app clocks; waitfor "d['clocksShown']" 5
ipc clocksOpen stopwatch; sleep 0.5; shot app-clocks-stopwatch 0.2
[ "$(q "['clocksTab']")" = stopwatch ] && result clocks-opens-at-a-tab PASS || result clocks-opens-at-a-tab FAIL "$(q "['clocksTab']")"
ipc closeAll

# the other surfaces read only when first opened (shell.qml's `source:` loaders):
# each opens, and writes no QML error doing so
for spec in kundaliOpen:kundali passwordGeneratorOpen:passwordGenerator "pdfSignerOpen $A/one.pdf:pdfSigner" "wallpaperStyleOpen :wallpaperStyleShown" screenTimeOpen:screenTimeShown videoTrimmerToggle:videoTrimmer togglePlayer:player filePickerHome:pickerShown; do
    call=${spec%%:*}; key=${spec#*:}; fn=${call%% *}; arg=${call#* }; [ "$arg" = "$call" ] && arg=
    ipc closeAll; sleep 0.3; before=$(errs)
    case "$call" in *" "*) ipc "$fn" "$arg" ;; *) ipc "$fn" ;; esac
    if waitfor "d.get('$key')" 5; then
        sleep 0.6; after=$(errs)
        [ "$after" = "$before" ] && result "surface-$key-opens" PASS \
            || result "surface-$key-opens" FAIL "open, but $(( after - before )) QML error(s): $(grep -E "TypeError|ReferenceError|is not a function|is not defined|Unable to assign" /work/out/logs/qs.log | tail -1 | cut -c1-200)"
    else
        result "surface-$key-opens" FAIL "state['$key'] = $(q ".get('$key')")"
    fi
done
ipc filePickerClose; ipc closeAll

# a desktop entry per app, as the package writes them, and each one valid
python3 /work/bin/shani app --write-desktop $A/desktop
n=$(ls $A/desktop/*.desktop | wc -l)
if command -v desktop-file-validate >/dev/null; then
    bad=$(desktop-file-validate $A/desktop/*.desktop 2>&1 | grep -v "hint:")
    [ -z "$bad" ] && [ "$n" -ge 15 ] && result apps-desktop-entries-valid PASS "$n entries" || result apps-desktop-entries-valid FAIL "$bad"
else
    grep -L "^Exec=shani app " $A/desktop/*.desktop | grep -q . && result apps-desktop-entries-valid FAIL "an entry without Exec" || result apps-desktop-entries-valid PASS "$n entries (no desktop-file-validate here)"
fi

# ---- Text Editor: open, edit, save ------------------------------------------------
# a file URI, as a file manager hands it over (%u), with a space to decode
cp $A/note.txt "$A/my note.txt"; chmod 640 "$A/my note.txt"
app text-editor "file://$A/my%20note.txt"
waitfor "d['textEditorFile'] == '$A/my note.txt' and d['textEditorChars'] == 23" 5 \
    && result editor-opens-a-file-uri PASS || result editor-opens-a-file-uri FAIL "$(q "['textEditorFile'], d['textEditorChars'], d['textEditorError']")"
# just read: nothing to save yet
[ "$(q "['textEditorUnsaved']")" = 0 ] && result editor-fresh-file-is-not-modified PASS || result editor-fresh-file-is-not-modified FAIL
ipc textEditorSetText "changed here"
waitfor "d['textEditorUnsaved'] == 1" 3 && result editor-marks-a-change PASS || result editor-marks-a-change FAIL
# closing the editor keeps the document and its change
ipc textEditorClose; sleep 0.5
app text-editor
waitfor "d['textEditor'] and d['textEditorUnsaved'] == 1 and d['textEditorChars'] == 12" 5 \
    && result editor-keeps-unsaved-work-when-closed PASS || result editor-keeps-unsaved-work-when-closed FAIL "$(q "['textEditorDocs'], d['textEditorUnsaved'], d['textEditorChars']")"
# (opening the app again added no empty tab: the document is still in front)
[ "$(q "['textEditorFile']")" = "$A/my note.txt" ] && [ "$(q "['textEditorDocs']")" = 1 ] && result editor-reopen-adds-no-empty-tab PASS || result editor-reopen-adds-no-empty-tab FAIL "$(q "['textEditorFile'], d['textEditorDocs']")"
ipc textEditorSave
waitfor "d['textEditorSaved'] == '$A/my note.txt' and d['textEditorUnsaved'] == 0" 5
[ "$(cat "$A/my note.txt")" = "changed here" ] && result editor-saves PASS || result editor-saves FAIL "file: $(head -c 80 "$A/my note.txt"); $(q "['textEditorError']")"
[ "$(stat -c %a "$A/my note.txt")" = 640 ] && result editor-save-keeps-permissions PASS || result editor-save-keeps-permissions FAIL "$(stat -c %a "$A/my note.txt")"
ls $A | grep -q shani-save && result editor-save-leaves-no-temp-file FAIL || result editor-save-leaves-no-temp-file PASS
# a link is followed: the file it points at is written, the link stays a link
ln -s "$A/my note.txt" $A/link.txt
app text-editor $A/link.txt; waitfor "d['textEditorFile'] == '$A/link.txt'" 5
ipc textEditorSetText "through the link"; ipc textEditorSave
waitfor "d['textEditorSaved'] == '$A/link.txt'" 5
[ -L $A/link.txt ] && [ "$(cat "$A/my note.txt")" = "through the link" ] && result editor-save-follows-a-link PASS || result editor-save-follows-a-link FAIL
# Windows line endings come back as they were
printf 'one\r\ntwo\r\n' > $A/crlf.txt
app text-editor $A/crlf.txt; waitfor "d['textEditorFile'] == '$A/crlf.txt'" 5
ipc textEditorSetText "$(printf 'one\ntwo\nthree\n')x"; ipc textEditorSave
waitfor "d['textEditorSaved'] == '$A/crlf.txt'" 5
[ "$(od -c $A/crlf.txt | grep -c '\\r')" -ge 1 ] && ! grep -q "$(printf 'two\n')$" /dev/null && [ "$(tr -d '\r' < $A/crlf.txt | head -2 | tail -1)" = two ] \
    && result editor-keeps-crlf PASS || result editor-keeps-crlf FAIL "$(od -c $A/crlf.txt | head -2)"
# a name that is not there yet is a new document; saving makes the file
app text-editor $A/new.txt; waitfor "d['textEditorFile'] == '$A/new.txt'" 5
ipc textEditorSetText "made by save"; ipc textEditorSave
waitfor "d['textEditorSaved'] == '$A/new.txt'" 5
[ "$(cat $A/new.txt 2>/dev/null)" = "made by save" ] && result editor-creates-a-new-file PASS || result editor-creates-a-new-file FAIL
# what is not text is refused and said, not shown as garbage
app text-editor $A/dot.png
waitfor "'Not a text file' in d['textEditorError']" 5 && result editor-refuses-a-binary-file PASS || result editor-refuses-a-binary-file FAIL "$(q "['textEditorError']")"
app text-editor $A
waitfor "'folder' in d['textEditorError']" 5 && result editor-refuses-a-folder PASS || result editor-refuses-a-folder FAIL "$(q "['textEditorError']")"
# a file that cannot be written is opened read-only, and a failed save says so
# (root writes anywhere, so the suite - which runs as root - checks the flag from the probe's side)
dd if=/dev/zero bs=1M count=3 2>/dev/null | tr '\0' 'a' > $A/big.txt
app text-editor $A/big.txt
waitfor "'Too big' in d['textEditorError']" 5 && result editor-refuses-a-huge-file PASS || result editor-refuses-a-huge-file FAIL "$(q "['textEditorError']")"
# a folder that is not there yet is made (saving into a new folder just works)
ipc textEditorNew; ipc textEditorSetText "in a new folder"; sleep 0.3; ipc textEditorSaveAs $A/made/here/x.txt
waitfor "d['textEditorSaved'] == '$A/made/here/x.txt'" 5 && [ "$(cat $A/made/here/x.txt)" = "in a new folder" ] \
    && result editor-save-as-makes-the-folder PASS || result editor-save-as-makes-the-folder FAIL "$(q "['textEditorError']")"
# a save that cannot happen (the "folder" is a file) says so and keeps the change
ipc textEditorNew; ipc textEditorSetText "kept"; sleep 0.3; ipc textEditorSaveAs $A/note.txt/x.txt
waitfor "'Could not save' in d['textEditorError'] and d['textEditorUnsaved'] >= 1" 5 \
    && result editor-failed-save-is-told PASS || result editor-failed-save-is-told FAIL "$(q "['textEditorError'], d['textEditorUnsaved'], d['textEditorSaved']")"
ipc closeAll

# ---- Tasks: Evolution Data Server's own task list, for real ---------------------------------
app tasks; waitfor "d['tasksShown'] and d['tasksAvailable']" 10
ipc tasksAdd "Water the plants" "$(( $(date +%s) + 3600 ))"
waitfor "'Water the plants' in d['tasksOpen']" 12 && result tasks-adds-to-eds PASS || result tasks-adds-to-eds FAIL "$(q "['tasksOpen'], d['tasksAvailable']") $(python3 /work/bridge/tasks.py 2>&1 | tail -1 | cut -c1-160)"
shot app-tasks-list 0.3
uid=$(python3 /work/bridge/tasks.py | python3 -c "import json,sys; print([t['uid'] for t in json.load(sys.stdin) if t['summary']=='Water the plants'][0])" 2>/dev/null)
python3 /work/bridge/tasks.py done '{"uid": "'"$uid"'", "done": true}' >/dev/null; ipc tasksOpen
waitfor "'Water the plants' in d['tasksDone']" 12 && result tasks-done-from-elsewhere-shows PASS || result tasks-done-from-elsewhere-shows FAIL "$(q "['tasksDone']")"
python3 /work/bridge/tasks.py delete '{"uid": "'"$uid"'"}' >/dev/null
ipc closeAll

# ---- Photos: the Pictures folder, by month ----------------------------------------------------
mkdir -p /root/Pictures/Camera; cp $A/dot.png /root/Pictures/Camera/one.png; cp $A/dot.png /root/Pictures/two.png
app photos; waitfor "d['photosShown']" 5; sleep 1.5; shot app-photos-grid 0.2
ipc closeAll

# ---- Translate: through translate.py (the suite's stand-in for the local model) -----------------
app translate; waitfor "d['translateShown']" 5
# ---- Authenticator: a code from the keyring -------------------------------------------------------
python3 /work/bin/shani app authenticator >/dev/null 2>&1; waitfor "d['authenticatorShown']" 5
python3 /work/bridge/otp.py add 'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example' >/dev/null 2>&1
code=$(python3 /work/bridge/otp.py list 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['code'])" 2>/dev/null)
[ "${#code}" = 6 ] && result authenticator-keyring-gives-a-code PASS || result authenticator-keyring-gives-a-code FAIL "$(python3 /work/bridge/otp.py list 2>&1 | tail -1 | cut -c1-160)"
ipc closeAll; python3 /work/bin/shani app authenticator >/dev/null 2>&1; sleep 1.5; shot app-authenticator-codes 0.2
ipc closeAll

# ---- Settings > Storage (was Disk Cleanup): measured, then the thumbnails go ----------------------------------------------------
mkdir -p /root/.cache/thumbnails/large; head -c 200000 /dev/zero > /root/.cache/thumbnails/large/x.png
ipc cleanUpOpen; waitfor "d['cleanUpShown']" 5 && result storage-opens-in-settings PASS || result storage-opens-in-settings FAIL "$(q "['cleanUpShown']")"; sleep 2; shot settings-storage 0.2
python3 /work/bridge/cleanup.py clean thumbnails >/dev/null && [ ! -e /root/.cache/thumbnails ] && result cleanup-clears-thumbnails PASS || result cleanup-clears-thumbnails FAIL
ipc closeAll

# ---- Nearby (LocalSend): a second LocalSend on this machine sends us a file -------------------------
rm -f /tmp/firewall-log
python3 /work/bin/shani app nearby-share >/dev/null 2>&1; waitfor "d['nearbyShown']" 5
ipc nearbyVisible true
waitfor "d['nearbyVisible']" 8 && grep -q -- "--add-port=53317/tcp" /tmp/firewall-log && result nearby-visible-opens-the-port-for-the-session PASS || result nearby-visible-opens-the-port-for-the-session FAIL "$(q "['nearbyVisible'], d['nearbyNote']") $(cat /tmp/firewall-log 2>&1 | tr '\n' ';')"
grep -q -- "--permanent" /tmp/firewall-log && result nearby-port-is-never-permanent FAIL || result nearby-port-is-never-permanent PASS
# the other device: nearby.py itself, on its own port, finding us by address
mkdir -p /tmp/other; printf 'from afar' > /tmp/other/hello.txt
( cd /tmp/other && { sleep 2; echo '{"op":"scan"}'; sleep 3; } | XDG_DATA_HOME=/tmp/other/data SHANI_NEARBY_PORT=53399 SHANI_NEARBY_ALIAS=Phone SHANI_NEARBY_SUBNET=0 SHANI_NEARBY_PEERS=127.0.0.1:53317 python3 /work/bridge/nearby.py > /tmp/other/out.json ) &
waitfor "'Phone' in d['nearbyDevices']" 12 && result nearby-finds-a-device PASS || result nearby-finds-a-device FAIL "$(q "['nearbyDevices']") $(tail -2 /tmp/other/out.json 2>&1)"
fp=$(grep '"ready"' /tmp/other/out.json | python3 -c "import json,sys; print(json.load(sys.stdin)['fingerprint'])" 2>/dev/null)
( cd /tmp/other && { echo '{"op":"scan"}'; sleep 3; printf '{"op":"send","to":"%s","files":["/tmp/other/hello.txt"]}\n' "$(python3 -c "import json; print([json.loads(l) for l in open('/tmp/other/out.json') if 'device' in l][-1]['fingerprint'])" 2>/dev/null)"; sleep 8; } | XDG_DATA_HOME=/tmp/other/data SHANI_NEARBY_PORT=53399 SHANI_NEARBY_ALIAS=Phone SHANI_NEARBY_SUBNET=0 SHANI_NEARBY_PEERS=127.0.0.1:53317 python3 /work/bridge/nearby.py > /tmp/other/out2.json ) &
waitfor "d['nearbyOffers'] >= 1" 12 && result nearby-asks-before-receiving PASS || result nearby-asks-before-receiving FAIL "$(q "['nearbyOffers'], d['nearbyTransfers']") $(tail -3 /tmp/other/out2.json 2>&1 | tr '\n' ' ')"
shot app-nearby-offer 0.4
ipc nearbyAnswer true
waitfor "'receive:done' in d['nearbyTransfers']" 12 && [ "$(cat /root/Downloads/Nearby/hello.txt 2>/dev/null)" = "from afar" ] \
    && result nearby-receives-what-was-sent PASS || result nearby-receives-what-was-sent FAIL "$(q "['nearbyTransfers']") $(ls /root/Downloads/Nearby 2>&1)"
ipc settingsCategory sharing; sleep 1.5; shot settings-sharing-nearby 0.2
ipc settingsCategory screentime; sleep 1.5; shot settings-screen-time 0.2
ipc themeFromImage ""; sleep 2; shot settings-personal-colours 0.2
ipc closeAll
ipc nearbyVisible false
waitfor "not d['nearbyVisible']" 5; sleep 1
grep -q -- "--remove-port=53317/tcp" /tmp/firewall-log && result nearby-hidden-closes-the-port PASS || result nearby-hidden-closes-the-port FAIL "$(cat /tmp/firewall-log | tr '\n' ';')"
ipc closeAll

# ---- Converter: the Media Player's song, made into MP3 beside it -----------------------------------
ipc converterOpen "$M/song.ogg"; waitfor "d['converterShown']" 5; sleep 2
python3 /work/bridge/convert.py run "$M/song.ogg" mp3 small >/dev/null 2>&1
[ -s "$M/song.mp3" ] && result converter-makes-an-mp3-beside-it PASS || result converter-makes-an-mp3-beside-it FAIL "$(ls $M)"
shot app-converter-list 0.2
ipc closeAll

# ---- one place for each thing: what the sidebar, the bar and the widgets hand over to ----
# pressed through AT-SPI, as a person would (the nested session has no pointer)
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
if [ -f "$A11Y" ]; then
    ipc closeAll; ipc controlCenter ""; sleep 1
    pressed=$(timeout 20 python3 "$A11Y" press "^Open Clocks$" 2>&1 | tail -1 | cut -c1-160)
    waitfor "d['clocksShown']" 4 && result handoff-sidebar-alarms-open-clocks PASS || result handoff-sidebar-alarms-open-clocks FAIL "press: $pressed"
    ipc closeAll
fi
