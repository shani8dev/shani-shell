# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=media-depth)
# ---- Media Player: sound tracks, subtitles (inside and beside), resume, tags and cover, mini player ----
M=/tmp/media-depth; rm -rf $M; mkdir -p $M
printf '1\n00:00:00,000 --> 00:03:00,000\nHello from inside\n' > $M/inner.srt
printf '1\n00:00:00,000 --> 00:03:00,000\n<i>Hello from the file</i>\n' > $M/film.srt
ffmpeg -loglevel error -f lavfi -i testsrc=size=320x240:rate=10 -f lavfi -i sine=frequency=440 -f lavfi -i sine=frequency=660 -i $M/inner.srt \
    -t 180 -map 0:v -map 1:a -map 2:a -map 3:s -c:v libx264 -preset ultrafast -c:a libopus -b:a 32k -c:s srt \
    -metadata:s:a:0 language=eng -metadata:s:a:1 language=hin -metadata:s:s:0 language=eng $M/film.mkv 2>/dev/null
magick -size 300x300 gradient:orange-purple $M/cover.jpg 2>/dev/null || convert -size 300x300 gradient:orange-purple $M/cover.jpg
ffmpeg -loglevel error -f lavfi -i sine=frequency=500:duration=5 -i $M/cover.jpg -map 0 -map 1 -c:a libmp3lame -c:v mjpeg -disposition:v attached_pic \
    -metadata title="Test Song" -metadata artist="Shani Band" -metadata album="First Light" $M/song.mp3 2>/dev/null

ipc mediaOpen "$M/film.mkv"
waitfor "d['mediaAudioTracks'] == 2" 10 && result media-two-sound-tracks PASS || result media-two-sound-tracks FAIL "$(q "['mediaAudioTracks']") tracks"
waitfor "d['mediaSubtitleFile'].endswith('film.srt') and d['mediaCue'] == 'Hello from the file'" 8 \
    && result media-subtitle-file-beside PASS || result media-subtitle-file-beside FAIL "file '$(q "['mediaSubtitleFile']")' cue '$(q "['mediaCue']")'"
sleep 1; shot media-subtitles 0.2

# resume: left at about a minute, it starts there again
ipc mediaSeek 60; sleep 6.5
ipc mediaClose; sleep 2
ipc mediaOpen "$M/film.mkv"
# the clock, not only the note: a seek too early is dropped (it once said 1:03 at 0:01)
waitfor "d['mediaResumedFrom'] >= 55 and d['mediaPosition'] >= 55" 10 && result media-resumes-where-left PASS "at $(q "['mediaPosition']") s" || result media-resumes-where-left FAIL "note $(q "['mediaResumedFrom']"), clock $(q "['mediaPosition']")"
sleep 0.6; shot media-resumed 0.2

# Showtime's "Take screenshot": the frame on screen saved as a picture
rm -rf "$HOME/Pictures/Screenshots"
ipc mediaSaveFrame
waitfor "d['mediaFrameSaved'] != ''" 10
f=$(q "['mediaFrameSaved']")
[ -f "$f" ] && [ "$(magick identify -format '%wx%h' "$f" 2>&1)" = 320x240 ] && case "$f" in "$HOME/Pictures/Screenshots/film "*.png) true;; *) false;; esac \
    && result media-save-frame PASS "$f" || result media-save-frame FAIL "$f $(magick identify -format '%wx%h' "$f" 2>&1)"

# the mini player: small, floating, on every workspace
ipc mediaMini true
waitfor "d['mediaMini'] and d['mediaPinned'] >= 1" 6 && sleep 1 \
    && niri msg -j windows | python3 -c "import json,sys; w=[x for x in json.load(sys.stdin) if (x['title'] or '').endswith('Media Player')]; sys.exit(0 if w and w[0]['is_floating'] and w[0]['layout']['window_size'][0] <= 600 else 1)" \
    && result media-mini-player-floats-and-pins PASS || result media-mini-player-floats-and-pins FAIL "mini $(q "['mediaMini']") pinned $(q "['mediaPinned']"); $(niri msg -j windows | python3 -c "import json,sys; print([(x['title'], x['is_floating'], x['layout']['window_size']) for x in json.load(sys.stdin)])" 2>&1 | cut -c1-200)"
shot media-mini 0.4
ipc mediaMini false
waitfor "not d['mediaMini'] and d['mediaPinned'] == 0" 6 && result media-mini-player-back PASS || result media-mini-player-back FAIL "pinned $(q "['mediaPinned']")"

# a song's own tags and cover, when the Library does not know it
ipc mediaOpen "$M/song.mp3"
waitfor "d['mediaTagLine'] == 'Test Song — Shani Band' and d['mediaCover'] != ''" 10 \
    && result media-song-tags-and-cover PASS || result media-song-tags-and-cover FAIL "tags '$(q "['mediaTagLine']")' cover '$(q "['mediaCover']")'"
sleep 1; shot media-song-cover 0.2
ipc mediaClose; ipc closeAll

# ---- a subtitle track that is a moment out: move it whole -----------------
# the cues are 0..180 s; a +1 s shift must move the line out at once, and a
# reset must put it back, without touching the file
ipc mediaOpen "$M/film.mkv"
waitfor "d['mediaCue'] == 'Hello from the file'" 8
before=$(q "['mediaSubShift']")
i=0
until [ "$(q "['mediaSubShift']")" != "$before" ] || [ $i -ge 20 ]; do
    timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" press "button:^Later$" >/dev/null 2>&1
    sleep 0.3; i=$((i+1))
done
[ "$(q "['mediaSubShift']")" != "$before" ] \
    && result media-subtitle-shift-moves-it PASS "$(q "['mediaSubShift']")" \
    || result media-subtitle-shift-moves-it FAIL "still $(q "['mediaSubShift']")"
# and the cue still shows: a shift is a move, not a mute
sleep 1
[ -n "$(q "['mediaCue']")" ] && result media-subtitle-shift-keeps-the-line PASS "$(q "['mediaCue']")" || result media-subtitle-shift-keeps-the-line FAIL "no cue after the shift"
ipc mediaOpen "$M/film.mkv"
waitfor "d['mediaSubShift'] == 0" 6 && result media-subtitle-shift-resets-per-file PASS || result media-subtitle-shift-resets-per-file FAIL "$(q "['mediaSubShift']")"
