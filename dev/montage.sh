#!/bin/sh
# usage: montage.sh   (inside shani-shell-dev, after demo.sh and a shell run:
#        `sh dev/check.sh montage`)
# out/demos/*.gif (captions already in them) and the suite's own screenshots
# (out/shots) -> out/demos/tour.mp4: one 1280x720 H.264 video for places that do
# not play a GIF (LinkedIn shows a GIF as a still). A title card, the desktop in
# proportion - sign-in, finding things, the apps, languages, the phone, and the
# assistant as one part of it, not the whole of it - and an end card.
# from what the repo keeps (docs/demos, docs/shots, docs/apps), not a test run's leftovers
GIFS=/work/docs/demos; SHOTS=/work/docs/shots; OUT=/work/out/demos; T=/tmp/montage; rm -rf $T; mkdir -p $T $OUT
FONT=/usr/share/fonts/inter/InterVariable.ttf
BG=0x16110e
card() {   # card NAME "big line" "small line" seconds
    printf '%s' "$2" > $T/$1-a.txt; printf '%s' "$3" > $T/$1-b.txt
    ffmpeg -y -loglevel error -f lavfi -i "color=c=$BG:s=1280x720:r=30:d=$4" -vf \
        "drawtext=fontfile=$FONT:textfile=$T/$1-a.txt:fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h/2)-70,
         drawtext=fontfile=$FONT:textfile=$T/$1-b.txt:fontsize=30:fontcolor=0xf0a070:x=(w-text_w)/2:y=(h/2)+20" \
        -c:v libx264 -pix_fmt yuv420p -r 30 $T/$1.mp4
}
clip() {   # a GIF, fitted into 1280x720 on the brand background, at 30 fps
    ffmpeg -y -loglevel error -i $GIFS/$1.gif -vf \
        "scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=$BG,fps=30,format=yuv420p" \
        -c:v libx264 -crf 20 -preset slow -r 30 $T/$1.mp4
}
still() {  # still NAME FILE "caption": a screenshot, captioned, for 3 seconds
    [ -f "$2" ] || { echo "no $2" >&2; return 1; }
    printf '%s' "$3" > $T/$1.txt
    ffmpeg -y -loglevel error -loop 1 -t 3 -i "$2" -vf \
        "scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=$BG,
         drawtext=fontfile=$FONT:textfile=$T/$1.txt:fontsize=30:fontcolor=white:box=1:boxcolor=0x16110e@0.82:boxborderw=14:x=(w-text_w)/2:y=h-text_h-30,
         fps=30,format=yuv420p" -c:v libx264 -crf 20 -r 30 $T/$1.mp4
}
n=0; : > $T/list.txt
add() { [ -f $T/$1.mp4 ] && echo "file '$T/$1.mp4'" >> $T/list.txt && n=$((n+1)); }

card start "Shani Shell" "The desktop of Shani OS - click, don't type" 3; add start; n=0
still desktop /work/docs/showcase-desktop.jpg "A complete desktop on niri"; add desktop
still face $SHOTS/greeter.jpg "Sign in by face, fingerprint, a key - or the password"; add face
still overview /work/docs/more/overview.jpg "Every window, at a glance"; add overview
for g in ring effects quicklook lens; do [ -f $GIFS/$g.gif ] && clip $g; add $g; done
# six of the apps side by side (docs/apps: the README's gallery)
A=/work/docs/apps
ffmpeg -y -loglevel error -i $A/files.jpg -i $A/document-viewer.jpg -i $A/media-player.jpg -i $A/maps.jpg -i $A/weather.jpg -i $A/photos.jpg \
    -filter_complex "[0]scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2:color=$BG[a];[1]scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2:color=$BG[b];[2]scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2:color=$BG[c];[3]scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2:color=$BG[d];[4]scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2:color=$BG[e];[5]scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2:color=$BG[f];[a][b][c][d][e][f]xstack=inputs=6:layout=0_0|w0_0|w0+w1_0|0_h0|w0_h0|w0+w1_h0" \
    -frames:v 1 $T/apps-grid.png
still apps $T/apps-grid.png "39 apps of its own"; add apps
[ -f $GIFS/osk.gif ] && clip osk; add osk
[ -f $GIFS/dictation.gif ] && clip dictation; add dictation
still setup $SHOTS/setup-marathi.jpg "First setup in six languages"; add setup
still call $SHOTS/call.jpg "Your phone's calls ring on the Island"; add call
for g in island writing; do [ -f $GIFS/$g.gif ] && clip $g; add $g; done
card end "shani.dev" "github.com/shani8dev/shani-shell" 3; echo "file '$T/end.mp4'" >> $T/list.txt

ffmpeg -y -loglevel error -f concat -safe 0 -i $T/list.txt -c copy -movflags +faststart $OUT/tour.mp4
ffmpeg -y -loglevel error -ss 4 -i $OUT/tour.mp4 -frames:v 1 $OUT/tour-poster.jpg
echo "MONTAGE $n parts, $(ffprobe -v error -show_entries format=duration -of csv=p=0 $OUT/tour.mp4 | cut -d. -f1) s, $(du -k $OUT/tour.mp4 | cut -f1) KB"
