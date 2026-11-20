# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=viewer-edit)
# ---- the picture viewer edits (Loupe parity): crop, the turn and flip, saved ----
# A 400x200 picture, turned right and cropped to its left half by a quarter:
# what is saved must be the picture as shown - 200 wide, 400 tall, then cropped.
V=/tmp/viewer-edit; rm -rf $V; mkdir -p $V
magick -size 400x200 xc:red -fill blue -draw "rectangle 0,0 199,199" $V/pic.png
ipc openViewer "$V/pic.png"; sleep 1.5
ipc viewerEdit; ipc viewerRotate; sleep 0.3
ipc viewerCrop 0 0 0.5 0.25
[ "$(q "['viewerEditing']")" = True ] && result viewer-edit-mode PASS || result viewer-edit-mode FAIL
shot viewer-edit 0.3
ipc viewerSave copy
waitfor "d['viewerSaved'].endswith('pic (edited).png') and not d['viewerEditing']" 10 \
    && [ "$(magick identify -format '%wx%h' "$V/pic (edited).png")" = 100x100 ] && [ "$(magick identify -format '%wx%h' $V/pic.png)" = 400x200 ] \
    && result viewer-crop-saves-a-copy PASS || result viewer-crop-saves-a-copy FAIL "$(q "['viewerSaved'], d['viewerAction']") $(ls $V | tr '\n' ' ')"
# turned right, the top-left of what is shown is the original's bottom-left: blue
case "$(magick "$V/pic (edited).png" -format '%[pixel:p{5,5}]' info:)" in blue|"srgb(0,0,255)") true;; *) false;; esac && result viewer-crop-is-what-was-shown PASS \
    || result viewer-crop-is-what-was-shown FAIL "$(magick "$V/pic (edited).png" -format '%[pixel:p{5,5}]' info:)"
# Replace: the edit in place, the original in the trash
ipc openViewer "$V/pic.png"; sleep 1; ipc viewerEdit; ipc viewerCrop 0 0 0.5 1; ipc viewerSave replace
waitfor "d['viewerSaved'] == '$V/pic.png' and not d['viewerEditing']" 10 && [ "$(magick identify -format '%wx%h' $V/pic.png)" = 200x200 ] \
    && ls "$HOME/.local/share/Trash/files/" | grep -q '^pic' && result viewer-replace-keeps-the-original-in-trash PASS \
    || result viewer-replace-keeps-the-original-in-trash FAIL "$(magick identify -format '%wx%h' $V/pic.png) $(ls $HOME/.local/share/Trash/files 2>&1 | tr '\n' ' ')"
# markup (Drawing's job): a green stroke across the middle of a white picture,
# turned right first - it lands where it was drawn on the turned picture
magick -size 300x100 xc:white $V/note.png
ipc openViewer "$V/note.png"; sleep 1; ipc viewerEdit; ipc viewerRotate; sleep 0.3
ipc viewerStroke "#33d17a" "0.5 0.1;0.5 0.9"
shot viewer-markup 0.3
ipc viewerSave copy
waitfor "d['viewerSaved'].endswith('note (edited).png') and not d['viewerEditing']" 10
mid=$(magick "$V/note (edited).png" -format '%[pixel:p{50,150}]' info: 2>&1); edge=$(magick "$V/note (edited).png" -format '%[pixel:p{5,150}]' info: 2>&1)
[ "$(magick identify -format '%wx%h' "$V/note (edited).png" 2>&1)" = 100x300 ] && [ "$mid" = "srgb(51,209,122)" ] && [ "$edge" = white -o "$edge" = "srgb(255,255,255)" ] \
    && result viewer-markup-saved PASS || result viewer-markup-saved FAIL "$(magick identify -format '%wx%h' "$V/note (edited).png" 2>&1) mid $mid edge $edge"
# Drawing parity: a box, words and a blurred corner, burned in where they were put
magick -size 200x200 pattern:checkerboard $V/marks.png
ipc openViewer "$V/marks.png"; sleep 1; ipc viewerEdit; sleep 0.3
ipc viewerTool box; ipc viewerStroke "#0000ff" "0.55 0.55;0.9 0.9"
ipc viewerTool blur; ipc viewerStroke "#000000" "0 0;0.45 0.45"
ipc viewerText 0.1 0.98 "Hello"
shot viewer-marks 0.3
ipc viewerSave copy
waitfor "d['viewerSaved'].endswith('marks (edited).png')" 10
o="$V/marks (edited).png"
box=$(magick "$o" -format '%[pixel:p{110,150}]' info: 2>&1)
sd() { magick "$o" -crop "$1" -colorspace gray -format '%[fx:standard_deviation]' info: 2>&1; }
blurred=$(sd 70x70+10+10); sharp=$(sd 60x60+120+20)
python3 -c "import sys; sys.exit(0 if float('$blurred') < float('$sharp') / 2 else 1)" 2>/dev/null && case "$box" in blue|"srgb(0,0,255)") true;; *) false;; esac \
    && result viewer-draw-box-blur-text PASS || result viewer-draw-box-blur-text FAIL "box $box blurred $blurred sharp $sharp"
# Loupe parity: an animated GIF plays (its frames), set as wallpaper, saved smaller
magick -size 40x40 xc:red xc:blue -set delay 20 -loop 0 $V/anim.gif
ipc openViewer "$V/anim.gif"
waitfor "d['viewerFrames'] == 2" 8 && result viewer-plays-animation PASS || result viewer-plays-animation FAIL "$(q "['viewerFrames'], d['viewerLoad']")"
was=$(q "['wallpaperSetting']")
magick -size 64x64 xc:orange $V/wall.png; ipc openViewer "$V/wall.png"; sleep 0.8
ipc viewerWallpaper
waitfor "d['wallpaperSetting'] == '$V/wall.png'" 4 && result viewer-set-wallpaper PASS || result viewer-set-wallpaper FAIL "$(q "['wallpaperSetting']")"
ipc wallpaperSet "$was"
magick -size 400x200 xc:green $V/big.png
ipc openViewer "$V/big.png"; sleep 1; ipc viewerEdit; ipc viewerResize "50%"; ipc viewerSave copy
waitfor "d['viewerSaved'].endswith('big (edited).png')" 10 && [ "$(magick identify -format '%wx%h' "$V/big (edited).png")" = 200x100 ] \
    && result viewer-resize-on-save PASS || result viewer-resize-on-save FAIL "$(magick identify -format '%wx%h' "$V/big (edited).png" 2>&1)"
rm -rf $V; ipc closeAll
