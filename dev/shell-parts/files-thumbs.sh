# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-thumbs)
# ---- Files: thumbnails for what is not a picture (freedesktop cache) ----
# A PDF's first page through pdftoppm and an office file through the image's own
# gsf-office thumbnailer (/usr/share/thumbnailers) - into ~/.cache/thumbnails.
T=/tmp/files-thumbs; rm -rf $T; mkdir -p $T
printf '%%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' > $T/doc.pdf
printf 'just words' > $T/notes.txt
rm -rf "$HOME/.cache/thumbnails"
ipc filesOpen "$T"
waitfor "'doc.pdf' in d['filesThumbs']" 15 && ls "$HOME"/.cache/thumbnails/normal/*.png >/dev/null 2>&1 \
    && result files-thumbnail-pdf PASS || result files-thumbnail-pdf FAIL "$(q "['filesThumbs']") $(ls -R $HOME/.cache/thumbnails 2>&1 | head -5 | tr '\n' ' ')"
[ "$(q "['filesThumbs']" | grep -c notes.txt)" = 0 ] && ls "$HOME"/.cache/thumbnails/fail/shani-files/*.png >/dev/null 2>&1 \
    && result files-thumbnail-none-marked PASS || result files-thumbnail-none-marked FAIL "$(ls -R $HOME/.cache/thumbnails/fail 2>&1 | head -3)"
shot files-thumbs 0.3
rm -rf $T; ipc closeAll
