# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=apps-phone)
# ---- every shell app at a phone's width -------------------------------------
# Run with SHANI_WIDTH=412 SHANI_SCREEN=915, as dev/check.sh's render=matrix:phone
# does. The shell is told it is a phone first: that is the profile whose touch
# targets are 44 px and whose windows open maximised under the status bar. This
# part opens every app bin/shani knows, from the same command its desktop entry
# uses, and photographs each one. A window that opens but overflows is visible
# in out/shots/phone-app-*.png.
settings '{"formFactors": {"winit": "phone"}}'
waitfor "d['formFactor'] == 'phone'" 6 \
    && result apps-phone-profile PASS || result apps-phone-profile FAIL "$(q "['formFactor']")"
python3 - <<'PY' && result apps-phone-screen PASS || result apps-phone-screen FAIL "the nested screen is not a phone"
import json, os, subprocess
out = next(iter(json.loads(subprocess.check_output(["niri", "msg", "-j", "outputs"])).values()))["logical"]
assert out["width"] == int(os.environ.get("SHANI_WIDTH", "1920")), out
assert out["height"] == int(os.environ.get("SHANI_SCREEN", "1080")), out
PY

# changing the form factor raises a "The Phone layout" card: clear it once, so
# the photographs show the app, not a notification hanging over its toolbar
ipc dismissAll; sleep 1

export SHANI_QS_CONFIG=/work/shani
app() { python3 /work/bin/shani app "$@" >/dev/null 2>&1; }
errs() { grep -c -E "TypeError|ReferenceError|is not a function|is not defined|Unable to assign" /work/out/logs/qs.log; }

A=/tmp/apps-phone-test; rm -rf "$A"; mkdir -p "$A"
printf 'first line\nsecond line\n' > "$A/note.txt"
cp /work/assets/shani-dark.jpg "$A/photo.jpg"
python3 - "$A/one.pdf" <<'PY'
import sys
objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length 44 >>\nstream\nBT /F1 18 Tf 20 100 Td (Shani test) Tj ET\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
out, offs = b"%PDF-1.4\n", []
for i, o in enumerate(objs, 1):
    offs.append(len(out)); out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offs)
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, len(out))
open(sys.argv[1], "wb").write(out)
PY
python3 - "$A/pack.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("readme.txt", "Shani phone check\n")
    z.writestr("notes/todo.txt", "one\ntwo\n")
PY
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=25" -f lavfi -i "sine=frequency=440" \
    -t 3 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$A/clip.mp4" 2>/dev/null || true

for spec in $(python3 - <<'PY'
import importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("shani_cli", "/work/bin/shani")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("shani_cli", loader)); loader.exec_module(m)
for name, s in m.APPS.items():
    if s[8] is not None:          # an action (a screenshot, a colour pick) waits for the pointer: not a window
        print(f"{name}:{s[8]}")
PY
); do
    name=${spec%%:*}; key=${spec#*:}
    ipc closeAll; sleep 0.3; before=$(errs)
    case "$name" in
        text-editor)     set -- "$name" "$A/note.txt" ;;
        image-viewer)    set -- "$name" "$A/photo.jpg" ;;
        document-viewer) set -- "$name" "$A/one.pdf" ;;
        archive-manager) set -- "$name" "$A/pack.zip" ;;
        pdf-signer)      set -- "$name" "$A/one.pdf" ;;
        media-player|converter|video-trimmer) set -- "$name" "$A/clip.mp4" ;;
        *)               set -- "$name" ;;
    esac
    app "$@"
    if waitfor "d.get('$key')" 8; then
        sleep 0.6; after=$(errs)
        shot "phone-app-$name" 0.3
        # on a phone niri opens the app maximised: the whole width, under the bar
        python3 - <<'PY' && result "app-$name-fills-phone-width" PASS \
            || result "app-$name-fills-phone-width" FAIL "the window is narrower than the phone"
import json, subprocess
w = json.loads(subprocess.check_output(["niri", "msg", "-j", "focused-window"]))
o = next(iter(json.loads(subprocess.check_output(["niri", "msg", "-j", "outputs"])).values()))["logical"]
assert w["layout"]["tile_size"][0] >= o["width"] * 0.90, (w["layout"], o)
PY
        [ "$after" = "$before" ] && result "app-$name-opens-on-phone" PASS \
            || result "app-$name-opens-on-phone" FAIL "open, but $(( after - before )) QML error(s): $(grep -E "TypeError|ReferenceError|is not a function|is not defined|Unable to assign" /work/out/logs/qs.log | tail -1 | cut -c1-200)"
    else
        result "app-$name-opens-on-phone" FAIL "state['$key'] = $(q ".get('$key')")"
    fi
done
ipc closeAll
settings '{}'
