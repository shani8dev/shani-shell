#!/bin/sh
# usage: session.sh   (inside shani-shell-dev, repo at /work)
# Brings up what a niri login has, minus the hardware: headless weston as the
# parent output, a session bus, PipeWire + WirePlumber with a null sink, the
# bridge, mock Chronoa, niri (the dev keybind config) and the shell from the
# checkout. Logs go to /work/logs. Sourced by the tests in dev/.
export XDG_RUNTIME_DIR=/run/user/0 HOME=/root USER=root XDG_SESSION_TYPE=wayland
# a login has a UTF-8 locale; C would make every non-ASCII comparison fail
export LANG=C.UTF-8 PYTHONUTF8=1
export SHANI_OSK_LAYOUT_TOOL=/work/bridge/osk-layout.py
export XDG_CONFIG_HOME=/root/.config SHANI_SHELL_SETTINGS=/tmp/shani-settings.json
# the lock screen's PAM file in its real place: its "include login" resolves
# against the directory it sits in, so a copy elsewhere can never authenticate
install -Dm644 /work/data/pam.d/shani-lock /etc/pam.d/shani-lock
# the desktop package's input-method default (English + Hindi phonetic)
[ -f /work/dev/fcitx5-profile ] && install -Dm644 /work/dev/fcitx5-profile /etc/xdg/fcitx5/profile
mkdir -p "$XDG_RUNTIME_DIR" /work/logs /root/Videos && chmod 700 "$XDG_RUNTIME_DIR"
L=/work/logs

weston --backend=headless-backend.so --shell=kiosk-shell.so --width=1920 --height=1080 \
    --socket=wayland-parent --idle-time=0 --no-config >$L/weston.log 2>&1 &
sleep 1.5
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address=1 | head -1)
export DBUS_SESSION_BUS_ADDRESS

# a system bus with the real daemons the shell's services talk to; no
# hardware behind them, but their D-Bus APIs are the real ones
mkdir -p /run/dbus
dbus-daemon --system --fork --nopidfile 2>$L/dbus-system.log
sleep 0.5
/usr/lib/upowerd >$L/upower.log 2>&1 &
/usr/lib/power-profiles-daemon >$L/ppd.log 2>&1 &
NetworkManager --no-daemon >$L/nm.log 2>&1 &
/usr/lib/bluetooth/bluetoothd -n >$L/bluetoothd.log 2>&1 &
sleep 1

pipewire >$L/pipewire.log 2>&1 &
sleep 0.5
wireplumber >$L/wireplumber.log 2>&1 &
pipewire-pulse >$L/pipewire-pulse.log 2>&1 &
sleep 1.5
pactl load-module module-null-sink sink_name=speakers sink_properties=device.description=Speakers >/dev/null 2>&1
pactl load-module module-null-sink sink_name=hdmi sink_properties=device.description=HDMI >/dev/null 2>&1
pactl load-module module-null-source source_name=mic >/dev/null 2>&1 || true
pactl set-default-sink speakers 2>/dev/null

python3 /work/dev/mock-chronoa.py >$L/mock.log 2>&1 &
python3 /work/bridge/chronoa-bridge.py >$L/bridge.log 2>&1 &
sleep 0.5

WAYLAND_DISPLAY=wayland-parent niri -c "${NIRI_CONFIG:-/work/dev/niri/session.kdl}" >$L/niri.log 2>&1 &
i=0
until [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done
export WAYLAND_DISPLAY=wayland-1
export NIRI_SOCKET=$(ls "$XDG_RUNTIME_DIR"/niri.wayland-1.*.sock | head -1)

qs -p /work/shani >$L/qs.log 2>&1 &
sleep 4
