#!/bin/sh
# usage: session.sh   (inside shani-shell-dev, repo at /work)
# Brings up what a niri login has, minus the hardware: headless weston as the
# parent output, a session bus, PipeWire + WirePlumber with a null sink, the
# bridge, mock Chronoa, niri (the dev keybind config) and the shell from the
# checkout. Logs go to /work/out/logs. Sourced by the tests in dev/.
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
export SHANI_SCRCPY=/work/dev/fake-scrcpy.sh SHANI_ADB=/work/dev/fake-adb.sh SHANI_LAUNCHER_ENTRY_TOOL=/work/bridge/launcher-entry.py SHANI_APPFILTER_TOOL=/work/dev/fake-appfilter.sh SHANI_LAUNCH_TOOL=/work/bridge/launch-app.py
# a keyboard's Caps Lock and Num Lock lights, where the kernel keeps them
export SHANI_LEDS_DIR=/tmp/fake-leds
for k in capslock numlock; do mkdir -p "/tmp/fake-leds/input3::$k"; echo 0 > "/tmp/fake-leds/input3::$k/brightness"; done
# a writable backlight device for the container (its real intel_backlight is
# read-only in this environment); the QML uses brightnessctl -m -l output
mkdir -p /tmp/fake-backlight/sys/class/backlight/shani-fake /tmp/fake-backlight/bin
echo 100 > /tmp/fake-backlight/sys/class/backlight/shani-fake/max_brightness
echo 50 > /tmp/fake-backlight/sys/class/backlight/shani-fake/brightness
chmod -R a+w /tmp/fake-backlight/sys/class/backlight
cat > /tmp/fake-backlight/bin/brightnessctl << 'SHIM'
#!/bin/sh
if [ "$1" = "-m" ] && [ "$2" = "-l" ]; then
    echo "shani-fake,backlight,$(cat /tmp/fake-backlight/sys/class/backlight/shani-fake/brightness 2>/dev/null || echo 50),$(cat /tmp/fake-backlight/sys/class/backlight/shani-fake/brightness 2>/dev/null || echo 50)%,100"
    exit 0
fi
DEVICE=""; SET_CMD=""; VAL=""
while [ $# -gt 0 ]; do case "$1" in -q) shift;; -d) DEVICE="$2"; shift 2;; set) SET_CMD="$1"; shift;; *) if echo "$1" | grep -qE '^[0-9]+%$'; then VAL="$1"; fi; shift;; esac; done
if [ -n "$DEVICE" ] && [ -n "$SET_CMD" ] && [ -n "$VAL" ]; then PCT=$(echo "$VAL" | tr -d '%'); echo "$PCT" > /tmp/fake-backlight/sys/class/backlight/$DEVICE/brightness 2>/dev/null || echo "$PCT" > /tmp/fake-backlight/sys/class/backlight/shani-fake/brightness; fi
exit 0
SHIM
chmod +x /tmp/fake-backlight/bin/brightnessctl
export PATH=/tmp/fake-backlight/bin:$PATH
# an ambient light sensor the suite can drive (the container's hardware has none)
export SHANI_LUX_FILE=/tmp/fake-lux
echo 300 > "$SHANI_LUX_FILE"
# the lock screen's PAM file in its real place: its "include login" resolves
# against the directory it sits in, so a copy elsewhere can never authenticate
install -Dm644 /work/data/pam.d/shani-lock /etc/pam.d/shani-lock
# face/fingerprint on the lock screen: "set up" while /tmp/bio-available exists, and a
# face "seen" while /tmp/face-match does (the biometric conversation's pam_exec)
export SHANI_BIOMETRIC_PROBE="test -e /tmp/bio-available"
# lyrics from a local stand-in for lrclib.net (dev/shell-test.sh serves it)
export SHANI_LYRICS_URL=http://127.0.0.1:8799/api/search
export SHANI_WALLHAVEN_URL=http://127.0.0.1:8799/api/v1/search
# face sign-in: the real helper, against a stand-in daemon the suite starts (and an
# infrared camera, as `linux-hello cameras` would say)
export SHANI_FACE_TOOL=/work/bridge/face.py SHANI_FACE_SOCK=/tmp/lh.sock SHANI_FACE_CAMERAS=" [IR CAMERA]"
# a magnetometer for the compass tile (monitor-sensor's own words, then waiting)
export SHANI_COMPASS_CMD='echo "Compass heading changed: 90.0"; exec sleep 6011'
printf '#!/bin/sh\ntest -e /tmp/face-match\n' > /usr/local/bin/fake-face && chmod +x /usr/local/bin/fake-face
printf 'auth sufficient pam_exec.so quiet /usr/local/bin/fake-face\nauth requisite pam_deny.so\n' > /etc/pam.d/shani-lock-biometric
# the desktop package's input-method default (English + Hindi phonetic)
[ -f /work/dev/fcitx5-profile ] && install -Dm644 /work/dev/fcitx5-profile /etc/xdg/fcitx5/profile
mkdir -p "$XDG_RUNTIME_DIR" /work/out/logs /root/Videos && chmod 700 "$XDG_RUNTIME_DIR"
L=/work/out/logs

# a taller headless screen for one run: SHANI_SCREEN=1400 makes the render 1920x1400
# (verification of surfaces that sit lower in the sidebar than one screen otherwise shows)
weston --backend=headless-backend.so --shell=kiosk-shell.so --width=1920 --height="${SHANI_SCREEN:-1080}" \
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

# input emulation for interactive verification (real clicks and keys):
# ydotoold opens /dev/uinput, which the container only gets when run with
# --device /dev/uinput — without it the daemon just fails to start. Client and
# daemon agree on the socket's default: /tmp/.ydotool_socket.
if [ -c /dev/uinput ] && command -v ydotoold >/dev/null 2>&1; then
    ydotoold >$L/ydotoold.log 2>&1 &
    sleep 0.3
fi

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
mkdir -p /usr/share/backgrounds/shani && cp /work/assets/shani-dark.jpg /work/assets/shani-night.jpg /work/assets/shani-light.jpg /usr/share/backgrounds/shani/
# idle off from the start (the tests drive the shell over IPC, which is not input).
# More for this run: SHANI_SETTINGS_EXTRA, JSON merged over it (python3, when here).
printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "lockAfterBattery": 0, "screenOffAfterBattery": 0, "startHintsDone": true}' > "$SHANI_SHELL_SETTINGS"
if [ -n "${SHANI_SETTINGS_EXTRA:-}" ] && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; d = json.loads(sys.argv[1]); d.update(json.loads(sys.argv[2])); print(json.dumps(d))' \
        "$(cat "$SHANI_SHELL_SETTINGS")" "$SHANI_SETTINGS_EXTRA" > "$SHANI_SHELL_SETTINGS"
fi
# the tests keep Adwaita (fixed icons to compare); the showcase passes the image's own
export QS_ICON_THEME=${QS_ICON_THEME:-Adwaita} QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
# every frame the shell renders, per window, into qs.log: what shell-test's
# perf-* checks count (a surface redrawing while nothing changes is GPU and battery)
date +%s%N > /tmp/qs-started
QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true" qs -p /work/shani >$L/qs.log 2>&1 &
sleep 4
