#!/bin/sh
# usage: session.sh   (inside shani-shell-dev, repo at /work)
# Brings up what a niri login has, minus the hardware: headless weston as the
# parent output, a session bus, PipeWire + WirePlumber with a null sink, the
# bridge, mock Chronoa, niri (the dev keybind config) and the shell from the
# checkout. Logs go to /work/logs. Sourced by the tests in dev/.
export XDG_RUNTIME_DIR=/run/user/0 HOME=/root USER=root XDG_SESSION_TYPE=wayland
# a login has a UTF-8 locale; C would make every non-ASCII comparison fail
export LANG=C.UTF-8 PYTHONUTF8=1
export SHANI_OSK_LAYOUT_TOOL=/work/bridge/osk-layout.py SHANI_SEARCH_PROVIDERS_TOOL=/work/bridge/search-providers.py
# voice typing without Chronoa in the image: whisper.cpp and its tiny model
export SHANI_DICTATE_TOOL=/work/bridge/dictate.py SHANI_DICTATE_ENGINE=whisper-cli
export SHANI_WHISPER_MODEL=/opt/whisper/ggml-tiny.en.bin
# no Bluetooth in a container: a stand-in for bridge/bt-agent.py (tests/test_bt_agent.py
# runs the real one against a fake BlueZ) that asks what /tmp/bt-ask holds
export SHANI_BT_AGENT=/work/dev/fake-bt-agent.py SHANI_OBEX_AGENT=/work/dev/fake-obex-agent.py
# no camera either: a stand-in for libcamera's cam (dev/fake-cam.sh)
export SHANI_CAM_TOOL=/work/dev/fake-cam.sh
export SHANI_NIRI_CONFIG=/work/dev/niri/session.kdl
# the first-login tour would sit over every other check; one test opens it by hand
export SHANI_NO_TOUR=1
export SHANI_BACKUP_TOOL=/work/dev/fake-backup.sh
export SHANI_DEVWATCH_TOOL=/work/bridge/devwatch.py
export SHANI_TRANSLATE_TOOL=/work/dev/fake-translate.py
export SHANI_DYNAMIC_LOCK_GRACE=1500     # ms: the dynamic-lock test waits 1.5 s, not 30
export SHANI_AGENDA_TOOL=/work/bridge/agenda.py SHANI_MODEM_TOOL=/work/dev/fake-modem.py
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
# printing (Settings > Printers): a real cupsd, with one file-backed printer
command -v cupsd >/dev/null && { mkdir -p /run/cups; cupsd -f >$L/cupsd.log 2>&1 & for i in 1 2 3 4 5 6 7 8 9 10; do [ -S /run/cups/cups.sock ] && break; sleep 0.3; done
    lpadmin -p Office_Laser -E -v file:///tmp/printed.out 2>>$L/cupsd.log; }
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

# the accessibility bus, and Qt exposing its tree on it (what Orca reads)
/usr/lib/at-spi-bus-launcher --launch-immediately >$L/atspi.log 2>&1 &
sleep 0.5
# the wallpapers where the package installs them
mkdir -p /usr/share/backgrounds/shani && cp /work/assets/shani-dark.jpg /work/assets/shani-light.jpg /usr/share/backgrounds/shani/
# idle off from the start (the tests drive the shell over IPC, which is not input)
printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "lockAfterBattery": 0, "screenOffAfterBattery": 0}' > "$SHANI_SHELL_SETTINGS"
QS_ICON_THEME=Adwaita QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 qs -p /work/shani >$L/qs.log 2>&1 &
sleep 4
