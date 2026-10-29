#!/bin/sh
# usage: showcase.sh   (inside shani-shell-dev, repo at /work)
# Stages the desktop for docs/showcase-*.png with real pieces only: Chronoa's
# own mascot art pushed through the Island's Art() call, a real approval from
# (mock) Chronoa, real notifications, a real MPRIS player, real apps.
# the desktop as installed, not as tested: shani-desktop-niri's gsettings
# defaults (mounted at /desktop: Papirus-Dark, Inter, dark, adw-gtk3), the icon
# theme shani-shell.service reads from them, and the shell's own defaults (no
# settings written). Apps the dev image lacks but the dock pins by default
# (Vivaldi, Cassini, Chronoa) get stand-in launchers with their real icons
# (/shani: the sibling repos).
if [ -d /desktop/usr/share/glib-2.0/schemas ]; then
    cp /desktop/usr/share/glib-2.0/schemas/*.gschema.override /usr/share/glib-2.0/schemas/ && glib-compile-schemas /usr/share/glib-2.0/schemas
fi
export QS_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
A=/root/.local/share/applications; I=/root/.local/share/icons/hicolor/scalable/apps; mkdir -p $A $I
[ -f /shani/shani-cassini/data/dev.shani.cassini.svg ] && cp /shani/shani-cassini/data/dev.shani.cassini.svg $I/
[ -f /shani/shani-chronoa/usr/share/icons/hicolor/scalable/apps/shani-chronoa.svg ] && cp /shani/shani-chronoa/usr/share/icons/hicolor/scalable/apps/shani-chronoa.svg $I/
for e in "com.vivaldi.Vivaldi:Vivaldi:vivaldi" "dev.shani.cassini:Cassini:dev.shani.cassini" "shani-chronoa:Chronoa:shani-chronoa"; do
    IFS=: read id name icon <<EOF
$e
EOF
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nIcon=%s\n' "$name" "$icon" > "$A/$id.desktop"
done
. /work/dev/session.sh
ipc() { qs -p /work/shani ipc call shani "$@" >/dev/null 2>&1; }
M="--session --dest org.shani.Chronoa.Mascot --object-path /org/shani/Chronoa/Mascot"

# the shell's defaults, as on a first login (only the idle lock kept away while staging)
printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0}' > "$SHANI_SHELL_SETTINGS"

# Chronoa's mascot, drawn by Chronoa's own art module (exported by the caller)
magick -background none /work/showcase/mascot-thinking.svg -resize 64x64 /tmp/mascot.png
gdbus call $M --method org.shani.Chronoa.Mascot.Art /tmp/mascot.png >/dev/null

magick -size 300x300 gradient:'#7fd1c1'-'#1b2a3a' -fill '#0b0d12' -font DejaVu-Sans-Bold -pointsize 54 \
    -gravity center -annotate 0 'LO-FI\nORBIT' /tmp/cover.png
python3 /work/dev/fake-mpris.py "Orbit of Saturn" "Kaavya & the Rings" /tmp/cover.png >/dev/null 2>&1 &

dbus-update-activation-environment WAYLAND_DISPLAY >/dev/null 2>&1
gnome-text-editor /work/README.md >/dev/null 2>&1 &
sleep 2
foot -a shani-demo -T "~/Projects/shani" sh -c 'printf "\033[36m~/Projects/shani\033[0m \$ shani-deploy --status\n\n  slot   A  (active)  2026.10.27  verified\n  slot   B            2026.10.21  verified\n  next   update ready  ·  312 MB  ·  signed\n\n\033[36m~/Projects/shani\033[0m \$ "; sleep 600' >/dev/null 2>&1 &
sleep 1.5
gnome-calculator >/dev/null 2>&1 &
sleep 2.5

notify-send -a Cassini -i system-software-update "Update ready" "ShaniOS 2026.10.28 is signed and staged in slot B. Reboot when convenient."
notify-send -a Mail -i mail-unread "Lunch at 1?" "Priya: the usual place, I'll book a table."
sleep 1

# 1: the desktop — Chronoa asks, in the Island, without opening anything
ipc ask "Tidy my desktop"
sleep 2.4
grim /work/docs/showcase-desktop.png

# 2: the sidebar
ipc approve "Allow this once"
sleep 2.5
ipc controlCenter wifi
sleep 1.2
grim /work/docs/showcase-sidebar.png
ipc closeAll

# 3: the Ring, at the pointer
ipc ring
sleep 0.8
grim /work/docs/showcase-ring.png
# the overview: every workspace with its windows, live (Super+O, the dock's grid button)
ipc closeAll; niri msg action toggle-overview; sleep 1.2
grim /work/docs/showcase-overview.png
niri msg action toggle-overview; sleep 0.6
ipc closeAll

# 4: the screen keyboard over the text editor (fcitx5 steps aside for it)
niri msg action focus-window --id "$(niri msg -j windows | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if 'TextEditor' in (w['app_id'] or '')))")"
sleep 0.6
ipc osk
ipc oskLanguage
sleep 1
# महाराष्ट्र, tapped as a person would: आ after a consonant becomes its matra
for k in म ह आ र आ ष ् ट ् र space; do qs -p /work/shani ipc call shani oskPress "$k" >/dev/null 2>&1; sleep 0.3; done
sleep 1
grim /work/docs/showcase-osk.png
ipc oskLanguage
ipc osk
sleep 1

# 5: the launcher, answering a question it has no app for
ipc launcher "why is my laptop slow"
sleep 1
grim /work/docs/showcase-launcher.png
ipc closeAll
