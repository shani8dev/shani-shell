# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=lean-launch)
# ---- apps start without GTK 3: gtk-launch is moved aside for this part ----
# The shell used to need gtk3 for one program, gtk-launch (an automation's
# "open an app", a shortcut that opens one, the browser key). They go through
# bridge/launch-app.py (GLib) now; this proves nothing still calls gtk-launch.
GL=$(command -v gtk-launch 2>/dev/null); [ -n "$GL" ] && mv "$GL" /tmp/gtk-launch.aside
A=/root/.local/share/applications; mkdir -p $A; rm -f /tmp/lean-opened
printf '[Desktop Entry]\nType=Application\nName=Lean test\nExec=sh -c "echo %s >> /tmp/lean-opened"\n' opened > $A/shani-lean-test.desktop
command -v gtk-launch >/dev/null && result lean-no-gtk-launch FAIL "still on PATH" || result lean-no-gtk-launch PASS

# an automation's "open an app"
pactl set-default-sink speakers; sleep 0.5
settings '{"automations": [{"when": "output", "is": "HDMI", "then": "open", "arg": "shani-lean-test", "on": true}]}'
sleep 0.5; pactl set-default-sink hdmi
for i in $(seq 20); do [ -s /tmp/lean-opened ] && break; sleep 0.25; done
[ "$(cat /tmp/lean-opened 2>/dev/null)" = opened ] && result lean-automation-opens-an-app PASS \
    || result lean-automation-opens-an-app FAIL "fired $(q "['automationsFired']"), opened '$(cat /tmp/lean-opened 2>&1)'"
pactl set-default-sink speakers; sleep 0.3; settings '{}'

# the browser key (XF86WWW): the default browser's desktop file, through launch-app.py
rm -f /tmp/lean-opened
if command -v xdg-settings >/dev/null; then
    xdg-settings set default-web-browser shani-lean-test.desktop 2>/dev/null
    # niri does not run its binds for a virtual keyboard (wtype), so the bind's
    # own command, read from the config, is spawned by niri - in niri's environment
    cmd=$(grep -m1 XF86WWW /work/dev/niri/session.kdl | python3 -c 'import sys; l = sys.stdin.read(); print(l.split(chr(34) + "-c" + chr(34) + " " + chr(34), 1)[1].rsplit(chr(34) + ";", 1)[0].replace(chr(92) + chr(34), chr(34)))')
    niri msg action spawn -- sh -c "$cmd"
    for i in $(seq 20); do [ -s /tmp/lean-opened ] && break; sleep 0.25; done
    [ "$(cat /tmp/lean-opened 2>/dev/null)" = opened ] && result lean-browser-key-opens-the-browser PASS \
        || result lean-browser-key-opens-the-browser FAIL "default '$(xdg-settings get default-web-browser 2>&1)', opened '$(cat /tmp/lean-opened 2>&1)'"
else
    result lean-browser-key-opens-the-browser SKIP "no xdg-settings in this image"
fi
rm -f $A/shani-lean-test.desktop
[ -f /tmp/gtk-launch.aside ] && mv /tmp/gtk-launch.aside "$GL"
