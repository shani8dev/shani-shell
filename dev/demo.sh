#!/bin/sh
# usage: demo.sh [scene ...]   (inside shani-shell-dev, repo at /work; via `sh dev/check.sh demo`)
# Records what only this desktop does as short GIFs for the README, in the real
# nested session: out/demos/<scene>.gif. Each scene drives the shell the way a
# person would (keys, the shell's own IPC for what a pointer would click) and is
# filmed frame by frame with grim - wf-recorder gets no frames from a nested
# niri - then made a GIF with ffmpeg's two-pass palette.
# Scenes that need a model say so and are skipped on mock Chronoa; run them with
# CHRONOA=real sh dev/check.sh demo (the model on 127.0.0.1:8765).
#   scenes: island ring osk dictation quicklook tidy lens writing ask replies apps
OUT=/work/out/demos; mkdir -p $OUT
if [ -d /desk/usr/share/glib-2.0/schemas ]; then
    cp /desk/usr/share/glib-2.0/schemas/*.gschema.override /usr/share/glib-2.0/schemas/ 2>/dev/null && glib-compile-schemas /usr/share/glib-2.0/schemas
fi
export QS_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
. /work/dev/session.sh
ipc() { qs -p /work/shani ipc call shani "$@" >/dev/null 2>&1; }
st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }
q() { st | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)"; }
waitfor() {   # waitfor <python expr over d> <seconds>
    i=0
    while [ $i -lt $(( $2 * 4 )) ]; do
        st | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)" 2>/dev/null && return 0
        sleep 0.25; i=$((i+1))
    done
    return 1
}
printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "startHintsDone": true}' > "$SHANI_SHELL_SETTINGS"
real=no; [ "${CHRONOA:-}" = real ] && real=yes

# ---- the camera ---------------------------------------------------------------
# rec NAME: frames at half size, as fast as grim gives them. hold / go: the camera
# pauses while a model thinks (a GIF of a wait is a GIF nobody watches; the
# first moment of it is kept, so the thinking is seen). stopcam: stop, and make
# the GIF at the rate the frames were really taken, so it plays in real time.
FPS=12
# rec NAME [GEOMETRY]: a region ("x,y WxH" of the 1920x1080 screen) is filmed at
# full size - the part that matters, readable - else the whole screen at half
rec() {
    NAME=$1; F=/tmp/frames-$NAME; rm -rf $F; mkdir -p $F; ACTIVE=0
    GEOM=${2:-}
    ( n=0; while [ ! -f $F/stop ]; do
          if [ -f $F/hold ]; then sleep 0.1; continue; fi
          f=$F/$(printf %05d $n).jpg
          if [ -n "$GEOM" ]; then grim -g "$GEOM" -t jpeg -q 90 $f; else grim -s 0.5 -t jpeg -q 90 $f; fi 2>/dev/null
          n=$((n+1))
      done ) &
    REC=$!; T0=$(date +%s.%N)
}
# say "TEXT": a caption from this frame on (until the next one), burned into the
# GIF - what the person pressed, and what is happening - so a viewer learns the keys
say() {
    printf '%s\n' "$(ls $F | grep -c 'jpg$')" >> $F/caps.idx
    printf '%s' "$1" > $F/cap$(wc -l < $F/caps.idx).txt
}
CAPFONT=/usr/share/fonts/inter/InterVariable.ttf
captions() {   # the drawtext filters for the captions said, at the GIF's rate
    [ -f $F/caps.idx ] || return 0
    python3 - "$F" "$1" "$2" "$CAPFONT" "${CAPS:-bottom}" <<'PY'
import sys
F, n, rate, font = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
pos = "26" if sys.argv[5] == "top" else "h-text_h-26"   # CAPS=top: where the scene's own controls are at the bottom
starts = [int(x) for x in open(F + "/caps.idx").read().split()]
out = []
for i, a in enumerate(starts):
    b = starts[i + 1] if i + 1 < len(starts) else n
    out.append(f",drawtext=fontfile={font}:textfile={F}/cap{i + 1}.txt:fontsize=24:fontcolor=white"
               f":box=1:boxcolor=0x16110e@0.82:boxborderw=12:x=(w-text_w)/2:y={pos}"
               f":enable='between(t\\,{a / rate:.2f}\\,{b / rate:.2f})'")
print("".join(out), end="")
PY
}
hold() { sleep 1.2; touch $F/hold; ACTIVE=$(python3 -c "print($ACTIVE + $(date +%s.%N) - $T0)"); }
go() { rm -f $F/hold; T0=$(date +%s.%N); }
stopcam() {
    touch $F/stop; wait $REC 2>/dev/null
    n=$(ls $F/*.jpg 2>/dev/null | wc -l)
    rate=$(python3 -c "print(round($n / ($ACTIVE + $(date +%s.%N) - $T0), 2))")
    caps=$(captions $n $rate)
    ffmpeg -y -loglevel error -framerate $rate -i $F/%05d.jpg \
        -vf "fps=$FPS,scale='min(960,iw)':-2:flags=lanczos$caps,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
        -loop 0 $OUT/$NAME.gif
    cp $F/$(printf %05d $((n * 2 / 3))).jpg $OUT/$NAME.jpg 2>/dev/null     # a still, for where a GIF will not play
    echo "DEMO $NAME $(du -k $OUT/$NAME.gif | cut -f1) KB, $n frames at $rate/s"
}
calm() { ipc dismissAll; ipc closeAll; sleep 0.8; }

# ---- a working day's files, and the wallpaper drawn before anything is filmed ----
dbus-update-activation-environment WAYLAND_DISPLAY >/dev/null 2>&1
mkdir -p /root/Documents /root/Downloads /root/Pictures /root/Videos
printf 'hey team, i think we shoud move the review to thursday\nbecuase half of us is out on wednesday.\nlet me no if that work for everone\n' > /root/Documents/draft.txt
cp /work/assets/shani-dark.jpg /root/Pictures/saturn-dusk.jpg; cp /work/assets/shani-night.jpg /root/Pictures/saturn-night.jpg
cp /work/assets/shani-light.jpg /root/Pictures/saturn-day.jpg
ffmpeg -loglevel error -f lavfi -i testsrc2=size=640x360:rate=24 -t 4 -pix_fmt yuv420p /root/Pictures/clip.mp4 2>/dev/null
python3 -c "
import pymupdf
d = pymupdf.open(); p = d.new_page()
p.insert_text((72, 96), 'Quarterly review', fontsize=28)
p.insert_textbox(pymupdf.Rect(72, 130, 520, 700), open('/work/FEATURES.md').read()[:1800], fontsize=10)
d.save('/root/Pictures/review.pdf')" 2>/dev/null
for f in IMG_2041.jpg IMG_2042.jpg invoice-march.pdf setup-2.4.AppImage song.mp3 talk.mkv notes.txt slides.pptx; do printf x > /root/Downloads/$f; done
cp /work/assets/shani-night.jpg /root/Downloads/IMG_2041.jpg
waitfor "True" 10; sleep 4; calm
# the real Chronoa opens its own window (and its first-run setup); the clips are
# of the desktop, so its windows go to workspace 2 - it keeps running behind them
if [ $real = yes ]; then
    GSETTINGS_SCHEMA_DIR=/chronoa/usr/share/glib-2.0/schemas gsettings set org.shani.chronoa setup-complete true 2>/dev/null
    sleep 2
    for id in $(niri msg -j windows | python3 -c "import json,sys; print(' '.join(str(w['id']) for w in json.load(sys.stdin) if 'chronoa' in (w['app_id'] or '').lower() or 'Chronoa' in (w['title'] or '')))"); do
        niri msg action move-window-to-workspace --window-id $id --focus false 2 2>/dev/null
    done
    niri msg action focus-workspace 1; sleep 1
fi

# ---- scenes ---------------------------------------------------------------------
scene_island() {     # Chronoa asks before it acts - in the bar, answered without opening anything
    rec island "400,0 1120x420"; say "You ask Chronoa to tidy the Desktop"; sleep 1.2
    ipc ask "Tidy my desktop"; sleep 1.6
    say "Before it moves a file, it asks - right in the bar"; sleep 2
    say "One click: Allow this once"; sleep 0.6
    ipc approve "Allow this once"; sleep 1.2
    say "Done, and every move can be undone"; sleep 2.5
    stopcam; calm
}
scene_ring() {       # the pie menu at the pointer (Mod+X)
    rec ring "600,260 720x600"; say "Super + X"; sleep 0.8
    ipc ring; sleep 0.6
    say "The Ring: everything, at the pointer"; sleep 2.4
    ipc closeAll; sleep 0.8
    stopcam; calm
}
scene_osk() {        # Marathi on the screen keyboard: आ after a consonant becomes its matra
    # big enough to read in a GIF: the editor's own font setting, for this scene only
    gsettings set org.gnome.TextEditor use-system-font false; gsettings set org.gnome.TextEditor custom-font 'Noto Sans 40'
    gnome-text-editor >/dev/null 2>&1 & sleep 3
    ipc osk; ipc oskLanguage; sleep 1
    rec osk; say "The screen keyboard in Marathi - a vowel after a consonant becomes its sign"; sleep 0.6
    for k in म ह आ र आ ष ् ट ् र; do qs -p /work/shani ipc call shani oskPress "$k" >/dev/null 2>&1; sleep 0.45; done
    sleep 1.5; stopcam
    ipc oskLanguage; ipc osk; pkill -f gnome-text-editor; gsettings reset org.gnome.TextEditor use-system-font; calm
}
scene_dictation() {  # voice typing: the screen keyboard's mic, words heard and typed - all on this computer
    # what is "said" is played into the microphone (the speakers' monitor), as the suite does:
    # espeak-ng speaks, whisper (Chronoa's speech engine) hears it
    pactl set-default-source speakers.monitor
    espeak-ng -s 140 -w /tmp/said.wav "Please send me the photos from the trip"
    gsettings set org.gnome.TextEditor use-system-font false; gsettings set org.gnome.TextEditor custom-font 'Noto Sans 30'
    gnome-text-editor >/dev/null 2>&1 & sleep 3
    ipc osk; sleep 1
    rec dictation; say "Tap the keyboard's microphone, and speak"; sleep 1
    ipc dictate; sleep 0.6
    paplay /tmp/said.wav; sleep 0.4
    ipc dictate; say "Heard on this computer - nothing leaves it"; sleep 1; hold
    waitfor "d['dictation'] == 'idle' and d['dictated'] != ''" 60; go
    say "Typed where you were"; sleep 3
    stopcam
    ipc osk; pkill -f gnome-text-editor; gsettings reset org.gnome.TextEditor use-system-font; calm
}
scene_quicklook() {  # Space on a file in Files: a look without opening its app, arrows to the next
    ipc filesOpen /root/Pictures; sleep 2
    i=0; until q "['navFocus']" | grep -qE "^(clip|review|saturn)" || [ $i -ge 25 ]; do wtype -k Tab; sleep 0.2; i=$((i+1)); done
    rec quicklook "380,30 1160x990"; say "Files: press Space on any file"; sleep 1
    wtype -k space; sleep 1.2
    say "Quick Look - no app opened"; sleep 1
    say "Right arrow: the next file - videos, PDFs, pictures"
    for i in 1 2 3; do wtype -k Right; sleep 1.8; done
    wtype -k Escape; sleep 0.8
    stopcam; calm
}
scene_tidy() {       # a messy Downloads sorted by kind, shown first - and undone in one click
    ipc filesOpen /root/Downloads; sleep 2
    rec tidy "460,40 1000x960"; say "A messy Downloads folder - click Tidy"; sleep 1.4
    ipc filesTidy /root/Downloads; waitfor "d['tidyPlanned'] > 0" 6
    say "It shows where everything will go, first"; sleep 2.5
    say "Sort them"
    ipc filesTidyApply; waitfor "d['tidyCanUndo']" 6; sleep 2.2
    say "Changed your mind? Undo puts every file back"; sleep 0.8
    ipc filesTidyUndo; waitfor "not d['tidyCanUndo']" 6; sleep 2
    stopcam; calm
}
scene_lens() {       # part of the screen read: its words, copy, ask Chronoa
    gnome-text-editor /root/Documents/draft.txt >/dev/null 2>&1 & sleep 3
    rec lens "440,40 1040x700"; say "Super + S: select any part of the screen"; sleep 1.2
    ipc lensRegion "200,120 1500x220"; sleep 1.2
    say "Lens reads it on this computer: copy, search, translate - or ask Chronoa"; sleep 4
    CAPS=top stopcam; ipc closeAll; pkill -f gnome-text-editor; calm
}
scene_apps() {       # a still of each app, maximised, with something in it, for the README's gallery
    mkdir -p $OUT/apps
    gsettings set org.gnome.TextEditor use-system-font false; gsettings set org.gnome.TextEditor custom-font 'Noto Sans 20'
    ( cd /root/Pictures && bsdtar -acf /root/Downloads/photos.zip saturn-dusk.jpg saturn-day.jpg review.pdf )
    # more pictures for Photos and Files: crops of the wallpapers
    for n in 1 2 3 4 5 6; do
        magick /work/assets/shani-dark.jpg -gravity center -crop "$((40 + n * 8))%x$((40 + n * 8))%+$((n * 90 - 300))+$((n * 40 - 120))" +repage -resize 1600x /root/Pictures/dusk-$n.jpg 2>/dev/null
    done
    # a song with its cover, for the Media Player
    ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=330:duration=30" -i /work/assets/shani-dark.jpg -map 0 -map 1 \
        -c:a libmp3lame -c:v mjpeg -disposition:v attached_pic -metadata title="Orbit of Saturn" -metadata artist="Kaavya & the Rings" \
        -metadata album="Dusk" /root/Downloads/orbit-of-saturn.mp3 2>/dev/null
    ipc weather "Pune"; sleep 3
    for spec in "files:/root/Pictures" "document-viewer:/root/Pictures/review.pdf" "media-player:/root/Downloads/orbit-of-saturn.mp3" \
                "image-viewer:/root/Pictures/saturn-dusk.jpg" "archive-manager:/root/Downloads/photos.zip" \
                photos maps weather clocks calculator system-monitor settings; do
        app=${spec%%:*}; file=${spec#*:}; [ "$file" = "$spec" ] && file=
        SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app $app $file >/dev/null 2>&1
        sleep 2.5; niri msg action maximize-column 2>/dev/null; sleep 1
        [ $app = maps ] && { ipc mapsSearch "Shaniwar Wada, Pune"; sleep 4; ipc mapsRefresh; sleep 12; }
        sleep 1.5
        # a floating window (it is not maximised) is photographed with a margin of the
        # desktop around it, from niri's own geometry; a tiled one fills the screen
        geom=$(niri msg -j focused-window | python3 -c "
import json, sys
w = json.load(sys.stdin) or {}
L = w.get('layout') or {}
if not w.get('is_floating') or not L.get('tile_pos_in_workspace_view'):
    sys.exit()
(x, y), (tw, th) = L['tile_pos_in_workspace_view'], L['tile_size']
m = 110; x0, y0 = max(0, int(x) - m), max(0, int(y) + 50 - m)
print(f'{x0},{y0} {min(1920 - x0, int(tw) + 2 * m)}x{min(1080 - y0, int(th) + 2 * m)}')")
        if [ -n "$geom" ]; then grim -g "$geom" -t jpeg -q 88 $OUT/apps/$app.jpg; else grim -s 0.5 -t jpeg -q 88 $OUT/apps/$app.jpg; fi && echo "APP $app ${geom:-full}"
        calm
    done
}
scene_popups() {     # just the notification pop-ups (scene_more takes them too)
    M=$OUT/more; mkdir -p $M
    notify-send -a Mail -i mail-unread "Lunch at 1?" "Priya: the usual place, I'll book a table."
    notify-send -a Calendar -i x-office-calendar "Design review in 10 minutes" "Room 4 · with Arun and Meera"
    notify-send -a "Shani OS" -i system-software-update "An update is ready" "Restart when it suits you: it is already on the other slot."
    sleep 2; grim -g "1300,30 620x520" -t jpeg -q 88 $M/notifications.jpg && echo "MORE notifications"; calm
}
scene_more() {       # stills of what the clips do not show, each staged cleanly (README "More of it")
    M=$OUT/more; mkdir -p $M
    snap() { grim ${2:+-g "$2"} -t jpeg -q 88 $M/$1.jpg && echo "MORE $1"; }
    magick /work/assets/shani-dark.jpg -resize 300x300^ -gravity center -extent 300x300 /tmp/cover.png
    python3 /work/dev/fake-mpris.py "Orbit of Saturn" "Kaavya & the Rings" /tmp/cover.png >/dev/null 2>&1 & MP=$!
    sleep 1.5
    # a few real windows to work with
    gnome-text-editor /root/Documents/draft.txt >/dev/null 2>&1 & sleep 1.5
    SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app image-viewer /root/Pictures/saturn-dusk.jpg >/dev/null 2>&1; sleep 1.5
    SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app files /root/Pictures >/dev/null 2>&1; sleep 2
    niri msg action toggle-overview; sleep 1.5; snap overview; niri msg action toggle-overview; sleep 1
    ipc switcher; sleep 1.2; snap switcher "360,250 1200x560"; wtype -k Escape; sleep 0.8
    ipc launcher "5 km in miles"; sleep 1.8; snap launcher-answer "380,0 1160x560"; ipc closeAll; sleep 0.6
    ipc closeAll; Ui_close() { ipc dismissAll; ipc closeAll; }
    notify-send -a Mail -i mail-unread "Lunch at 1?" "Priya: the usual place, I'll book a table."
    notify-send -a Calendar -i x-office-calendar "Design review in 10 minutes" "Room 4 · with Arun and Meera"
    notify-send -a "Shani OS" -i system-software-update "An update is ready" "Restart when it suits you: it is already on the other slot."
    sleep 2; snap notifications "1300,30 620x520"; sleep 0.6
    ipc controlCenter audio; sleep 1.5; snap mixer "1360,0 560x900"; ipc closeAll; sleep 0.6
    ipc settingsAt access ""; sleep 2; snap accessibility "300,60 1320x900"; ipc closeAll; sleep 0.6
    ipc settingsAt power ""; sleep 2.5; snap battery "300,60 1320x900"; ipc closeAll; sleep 0.6
    # the lock screen, with what is playing
    echo 'root:shani-test' | chpasswd; cp /tmp/cover.png /root/.face
    ipc lock; sleep 2.5; snap lock
    wtype "shani-test" -k Return; sleep 2
    # no windows: the desktop's widgets, then the light style
    pkill -f gnome-text-editor; ipc closeAll; ipc dismissAll; sleep 1
    printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "startHintsDone": true, "desktopWidgets": ["clock", "weather", "media", "battery"]}' > "$SHANI_SHELL_SETTINGS"
    ipc weather "Pune"; sleep 3; snap widgets
    ipc setting darkMode false; sleep 2.5
    SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app files /root/Pictures >/dev/null 2>&1; sleep 2; snap light
    ipc closeAll; ipc setting darkMode true
    printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "startHintsDone": true}' > "$SHANI_SHELL_SETTINGS"
    kill $MP 2>/dev/null; calm
}
scene_effects() {    # windows that open beautifully: Dissolve, then Pop (Settings > Windows)
    rec effects "380,90 1160x900"
    for style in dissolve pop; do
        printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "startHintsDone": true, "winMotion": "%s", "winSpeed": 4, "winCorners": 18, "winShadow": "deep"}' $style > "$SHANI_SHELL_SETTINGS"
        sleep 3
        say "$(printf %s "$style" | sed 's/^./\U&/') - Settings > Windows"
        foot -a shani-look -T "Look $style" sh -c 'printf "\033[1;38;5;209m  %s\033[0m\n\n" "Windows that open beautifully"; ls -l --color=always /usr/bin | head -40; sleep 60' >/dev/null 2>&1 &
        sleep 3.5; niri msg action close-window; sleep 2.5
    done
    stopcam
    pkill -f "Look " 2>/dev/null
    printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "startHintsDone": true}' > "$SHANI_SHELL_SETTINGS"; calm
}
# ---- with a model (CHRONOA=real) ---------------------------------------------------
scene_writing() {    # Writing tools on any selected text: proofread by Chronoa, put back in place
    [ $real = yes ] || { echo "DEMO writing SKIP (needs CHRONOA=real)"; return; }
    gsettings set org.gnome.TextEditor use-system-font false; gsettings set org.gnome.TextEditor custom-font 'Noto Sans 22'
    gnome-text-editor /root/Documents/draft.txt >/dev/null 2>&1 & sleep 3
    niri msg action maximize-column 2>/dev/null; sleep 0.8
    wtype -M ctrl -k a -m ctrl; sleep 0.5
    rec writing "0,40 1440x810"; say "Select text in any app"; sleep 1.4
    say "Press Super + Shift + W"; sleep 0.8
    qs -c shani ipc call shani writingTools >/dev/null 2>&1 || ipc writingTools    # what niri runs for the key
    sleep 1.4
    say "Proofread - by Chronoa, on this computer"; ipc writingToolsChoose 0; hold
    waitfor "not d['writingBusy'] and d['writingResult'] != ''" 200; go; sleep 2.5
    say "Replace: the fixed text goes back where it was"; ipc writingToolsReplace; sleep 2.8
    stopcam; pkill -f gnome-text-editor; gsettings reset org.gnome.TextEditor use-system-font; calm
}
scene_ask() {        # the launcher answers what no app does: Ctrl+Enter asks Chronoa
    [ $real = yes ] || { echo "DEMO ask SKIP (needs CHRONOA=real)"; return; }
    rec ask "380,0 1160x900"; say "Super + Space, and type a question"; sleep 0.8
    ipc launcher ""; sleep 0.6
    wtype -d 70 "why is my laptop slow"; sleep 1
    say "Ctrl + Enter asks Chronoa"; sleep 0.8
    wtype -M ctrl -k Return -m ctrl; hold
    waitfor "d['chronoa'] in ('idle', 'ready') and len(d['chronoaReply']) > 60" 240; go
    say "It looks at this machine and answers - no app, no browser"; sleep 5
    stopcam; ipc closeChronoa; calm
}
scene_replies() {    # a message arrives with replies already written - one click sends one
    [ $real = yes ] || { echo "DEMO replies SKIP (needs CHRONOA=real)"; return; }
    # pop-ups stay as long as Settings > Notifications says; long enough here for the model
    printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "startHintsDone": true, "popupSeconds": 600}' > "$SHANI_SHELL_SETTINGS"; sleep 1.5
    rec replies "1240,40 680x420"; say "A message arrives"; sleep 0.8
    python3 /work/dev/reply-client.py "Are you coming to dinner tonight?" >/dev/null 2>&1 & sleep 2.5; hold
    waitfor "any(s.startswith('Are you coming to dinner') for s in d['smartReplies'])" 200; go
    say "Chronoa has written replies - on this computer"; sleep 3.5
    say "One click sends one"; sleep 0.6
    ipc notificationSuggestedReply "Are you coming to dinner tonight?" 0; sleep 2.2
    printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "startHintsDone": true}' > "$SHANI_SHELL_SETTINGS"
    stopcam; calm
}

for s in ${*:-island ring osk dictation quicklook tidy lens writing ask replies}; do
    if command -v scene_$s >/dev/null 2>&1 || type scene_$s >/dev/null 2>&1; then
        scene_$s
    else
        echo "DEMO $s SKIP (no such scene)"
    fi
done
ls -la $OUT
