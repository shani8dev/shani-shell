# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=viewer-formats)
# ---- the Image Viewer opens what Loupe did: one picture of each kind ----
# Made here with ImageMagick (its own readers write them), then opened in the
# Viewer, which reads through Qt's plugins (qt6-imageformats, kimageformats).
# A kind ImageMagick cannot write here is SKIP, not PASS.
F=/tmp/viewer-formats; rm -rf $F; mkdir -p $F
for e in png jpg gif bmp webp tiff avif heic jxl psd tga pcx exr hdr dds qoi ppm pgm pbm xpm xbm ico svgz; do
    if [ "$e" = svgz ]; then
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="32"><rect width="64" height="32" fill="red"/></svg>' | gzip > $F/s.svgz
    else
        magick -size 64x32 gradient:red-blue "$F/s.$e" 2>/dev/null || { result "viewer-opens-$e" SKIP "ImageMagick cannot write .$e here"; continue; }
    fi
    ipc openViewer "$F/s.$e"
    # ready: Qt read it, or the ImageMagick copy shown where Qt could not
    waitfor "d['viewerLoad'] == 'ready' and d['viewerFile'].endswith('s.$e')" 8
    [ "$(q "['viewerLoad']")" = ready ] && result "viewer-opens-$e" PASS || result "viewer-opens-$e" FAIL "$(q "['viewerLoad']")"
done
rm -rf $F; ipc closeAll
