# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=fonts-file)
# ---- Fonts opens a font file (GNOME Font Viewer parity): shown, then installed ----
# A .ttf, an .otf and a .ttc from the image's own fonts, copied under new names so
# their families are judged from the file; one is installed into ~/.local/share/fonts.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
F=/tmp/fonts-file; rm -rf $F; mkdir -p $F
for e in ttf otf ttc; do f=$(find /usr/share/fonts -name "*.$e" | head -1); [ -n "$f" ] && cp "$f" "$F/sample.$e"; done
for e in ttf otf ttc; do
    [ -f "$F/sample.$e" ] || { result "fonts-file-$e" SKIP "no .$e in the image"; continue; }
    fam=$(fc-scan --format '%{family[0]}\n' "$F/sample.$e" 2>/dev/null | head -1)   # a .ttc: its first face
    ipc fontsOpenFile "$F/sample.$e"
    # the family Qt read is fontconfig's, and it is known to be installed (it came from /usr/share/fonts)
    waitfor "d['fontFileFamily'] == '$fam' and d['fontFileInstalled']" 6 && result "fonts-file-$e-shown" PASS \
        || result "fonts-file-$e-shown" FAIL "read '$(q "['fontFileFamily']")' installed $(q "['fontFileInstalled']") fc-scan '$fam'"
done
# its details, as GNOME Font Viewer shows them (fc-query): the version and the format
if [ -f "$F/sample.ttf" ]; then
    ipc fontsOpenFile "$F/sample.ttf"
    waitfor "'version' in d['fontFileDetails'] and 'TrueType' in d['fontFileDetails']" 6 && result fonts-file-details PASS || result fonts-file-details FAIL "$(q "['fontFileDetails']")"
fi
shot fonts-file 0.3
# not a font: said so, no Install
printf 'not a font' > $F/broken.ttf; ipc fontsOpenFile "$F/broken.ttf"
waitfor "d['fontFileFamily'] == '!'" 6 && result fonts-file-not-a-font-said PASS || result fonts-file-not-a-font-said FAIL "$(q "['fontFileFamily']")"
rm -rf $F "$HOME/.local/share/fonts/renamed.ttf"; ipc closeAll
