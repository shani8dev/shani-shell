# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=pad-reach)
# ---- everything in the shell reached with keys and a controller alone ----
# The desktop as it starts (bar, dock, widgets), then each app in bin/shani's APPS
# (the viewers with a picture and a PDF to show) and Quick Settings and the launcher,
# one at a time: the shell lists what takes a click but no focus in every surface
# that is showing (Ui.navAuditAll: a MouseArea or TapHandler with no Common/KeyFocus
# or field around it) - what the d-pad, Tab and a pad's A could never reach. One
# result each; an app's own result leaves out what the desktop already had.
# Pointer by nature (the colour picker, the ruler, the magnifier, Lens: a pad has
# the right stick's pointer for them) are skipped. Between surfaces and at the end
# everything is dismissed (closeAll leaves the Tour, which holds the keyboard).
audit() { qs -p /work/shani ipc call shani navAuditAll 2>/dev/null; }
mkdir -p /tmp/pad-reach
python3 - <<'PY'
import fitz
d = fitz.open(); p = d.new_page(); p.insert_text((72, 72), "Pad reach"); d.save("/tmp/pad-reach/doc.pdf")
pm = fitz.Pixmap(fitz.csRGB, fitz.IRect(0, 0, 64, 48), 0); pm.clear_with(200); pm.save("/tmp/pad-reach/pic.png")
PY
ipc closeAll; ipc dismissAll; sleep 0.8
base=$(audit)
n=$(printf '%s' "$base" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo -1)
# the audit itself looked: the bar, the dock and the wallpaper are windows that show
w=$(q "['navAuditWindows']")
[ "${w:-0}" -ge 2 ] && result pad-reach-audit-looks PASS "$w windows" || result pad-reach-audit-looks FAIL "it looked into ${w:-0} windows"
[ "$n" = 0 ] && result pad-reach-desktop PASS || result pad-reach-desktop FAIL "$n reached only by a click: $(printf '%s' "$base" | head -c 900)"
printf '%s' "$base" > /tmp/pad-reach/base.json

apps=$(python3 - <<'PY'
from importlib.machinery import SourceFileLoader
import importlib.util
spec = importlib.util.spec_from_loader("shani_cli", SourceFileLoader("shani_cli", "/work/bin/shani"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
pointer = {"color-picker", "screen-ruler", "magnifier", "lens", "screenshot", "screen-recorder", "live-captions"}
seen = set()
for name, t in m.APPS.items():
    if t[1] in seen or name in pointer: continue
    seen.add(t[1])
    mimes = t[5] or []
    arg = "/tmp/pad-reach/doc.pdf" if "application/pdf" in mimes else "/tmp/pad-reach/pic.png" if "image/png" in mimes and not t[6] else ""
    print("%s\t%s" % (name, arg))
print("quick-settings\t"); print("launcher\t")
PY
)
tab=$(printf '\t')
while IFS="$tab" read -r name arg <&3; do
    [ -n "$name" ] || continue
    ipc closeAll; ipc dismissAll; sleep 0.4
    case "$name" in
        quick-settings) ipc controlCenter "" ;;
        launcher) ipc launcher "" ;;
        *) SHANI_QS_CONFIG=/work/shani timeout 10 python3 /work/bin/shani app "$name" $arg >/dev/null 2>&1 ;;
    esac
    sleep 1.6      # shown, its lists read in
    out=$(audit)
    new=$(printf '%s' "$out" | python3 -c "
import json, sys
base = set(json.load(open('/tmp/pad-reach/base.json')) or [])
now = json.load(sys.stdin)
print(json.dumps([x for x in now if x not in base]))" 2>/dev/null || echo '["(no answer)"]')
    n=$(printf '%s' "$new" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    if [ "$n" = 0 ]; then result "pad-reach-$name" PASS
    else result "pad-reach-$name" FAIL "$n reached only by a click: $(printf '%s' "$new" | python3 -c "import json,sys; print(' | '.join(json.load(sys.stdin)[:8]))")"
    fi
done 3<<APPS
$apps
APPS
ipc closeAll; ipc dismissAll
