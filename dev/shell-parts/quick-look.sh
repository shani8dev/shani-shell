# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=quick-look)
# ---- Quick Look: each kind of file seen without its app; Space in Files; Left/Right ----
Q=/tmp/quicklook-test; rm -rf $Q; mkdir -p $Q/folder
printf 'import sys\n\ndef hello(name):\n    # say it\n    print("hello", name, 42)\n' > $Q/code.py
cp /work/assets/shani-dark.jpg $Q/picture.jpg
ffmpeg -loglevel error -f lavfi -i testsrc=size=320x240:rate=10 -t 3 -pix_fmt yuv420p $Q/clip.mp4 2>/dev/null
ffmpeg -loglevel error -f lavfi -i sine=frequency=440:duration=3 $Q/tone.ogg 2>/dev/null
bsdtar -acf $Q/bundle.zip -C $Q code.py 2>/dev/null
touch $Q/folder/a.txt $Q/folder/b.txt
head -c 3000 /dev/urandom > $Q/blob.bin
magick -size 400x500 xc:white -fill black -pointsize 36 -annotate +40+120 'Quick Look' $Q/doc.pdf 2>/dev/null \
    || convert -size 400x500 xc:white -fill black -pointsize 36 -annotate +40+120 'Quick Look' $Q/doc.pdf 2>/dev/null
for spec in code.py:text picture.jpg:image clip.mp4:video tone.ogg:audio bundle.zip:archive folder:folder blob.bin:other doc.pdf:pdf; do
    f=${spec%%:*}; want=${spec#*:}
    [ -e "$Q/$f" ] || continue
    SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani quick-look open "$Q/$f" >/dev/null 2>&1   # through the CLI, as a person would
    case $want in
        text|archive|folder) ready="d['quickLookText'] > 0" ;;
        pdf) ready="d['quickLookPage'] != ''" ;;
        *) ready="True" ;;
    esac
    if waitfor "d['quickLookShown'] and d['quickLookKind'] == '$want' and $ready" 8; then
        sleep 0.8; shot "quicklook-$want" 0.2; result "quicklook-shows-$want" PASS
    else
        result "quicklook-shows-$want" FAIL "kind $(q "['quickLookKind']"), text $(q "['quickLookText']"), page '$(q "['quickLookPage']")', error '$(q "['quickLookError']")'"
    fi
done
ipc quickLookClose
waitfor "not d['quickLookShown']" 3 && result quicklook-closes PASS || result quicklook-closes FAIL

# Space in Files, on the file the keyboard is on; then Right walks to the next one
ipc filesOpen "$Q"; sleep 1.5
# Tab until the keyboard is on one of the files (the shell names what has focus)
i=0; until q "['navFocus']" | grep -qE "^(blob|bundle|clip|code|doc|folder|picture|tone)" || [ $i -ge 25 ]; do wtype -k Tab; sleep 0.25; i=$((i+1)); done
on=$(q "['navFocus']")
wtype -k space; sleep 0.8
if waitfor "d['quickLookShown']" 4; then
    first=$(q "['quickLookKind']")
    wtype -k Right; sleep 0.8
    shot quicklook-from-files 0.2
    [ "$(q "['quickLookKind']")" != "" ] && result quicklook-space-in-files PASS "on '$on': $first, then Right: $(q "['quickLookKind']")" || result quicklook-space-in-files FAIL
else
    result quicklook-space-in-files FAIL "Space in Files opened nothing (keyboard on '$on', current '$(q "['filesCurrent']" 2>&1)')"
fi
ipc quickLookClose; ipc closeAll

# Ctrl+Y on a file the launcher found
mkdir -p /root/Documents; printf 'a note to look at\n' > /root/Documents/quicklook-note.txt
ipc launcher "quicklook-note"
if waitfor "d['launcherFiles'] > 0" 8; then
    sleep 0.4; wtype -M ctrl -k y -m ctrl
    waitfor "d['quickLookShown'] and d['quickLookKind'] == 'text'" 5 && result quicklook-from-launcher PASS || result quicklook-from-launcher FAIL "$(q "['quickLookShown'], d['quickLookKind']")"
else
    result quicklook-from-launcher FAIL "the launcher did not find it: top '$(q "['topResult']")'"
fi
ipc quickLookClose; ipc closeAll; rm -f /root/Documents/quicklook-note.txt
