#!/bin/sh
# usage: session.sh   (inside shani-shell-dev, repo at /work)
# Brings up what a niri login has, minus the hardware: headless weston as the
# parent output, a session bus, PipeWire + WirePlumber with a null sink, the
# bridge, mock Chronoa, niri (the dev keybind config) and the shell from the
# checkout. Logs go to /work/out/logs. Sourced by the tests in dev/.
export XDG_RUNTIME_DIR=/run/user/0 HOME=/root USER=root XDG_SESSION_TYPE=wayland
# a login has a UTF-8 locale; C would make every non-ASCII comparison fail
export LANG=C.UTF-8 PYTHONUTF8=1
export SHANI_OSK_LAYOUT_TOOL=/work/bridge/osk-layout.py SHANI_OSK_PREDICT_TOOL=/work/bridge/osk-predict.py SHANI_SEARCH_PROVIDERS_TOOL=/work/bridge/search-providers.py
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
# shani-backup stand-in: the real parser and the real --json shapes, so the
# backup bridge is exercised as it will be on a machine with shani-backup
export SHANI_BACKUP_TOOL=/work/dev/fake-shani-backup.py
export SHANI_BACKUP_BRIDGE=/work/bridge/backup.py
export SHANI_BACKUP_PKEXEC=
# Settings > Chronoa reads the headless engine's Agent.Inventory and switches
# its user unit. Stand-ins: the Agent serves the ten real inventory shapes (and
# delegates turns to dev/mock-chronoa.py); systemctl --user only knows the
# shani-chronoa-engine.service unit and records every call for the live check.
export SHANI_CHRONOA_AGENT=/work/dev/fake-chronoa-agent.py
export SHANI_CHRONOA_SYSTEMCTL=/work/dev/fake-chronoa-systemctl.py
export SHANI_CHRONOA_SYSTEMCTL_LOG=/tmp/fake-chronoa-systemctl/calls
export SHANI_DEVWATCH_TOOL=/work/bridge/devwatch.py SHANI_FEEDS_TOOL=/work/bridge/feeds.py SHANI_MAIL_TOOL=/work/bridge/mail.py SHANI_AUTOSTART_TOOL=/work/bridge/autostart.py SHANI_MEDIAINFO_TOOL=/work/dev/fake-mediainfo.sh SHANI_EXIV2_TOOL=/work/dev/fake-exiv2.sh
# devices plugged in: the real watcher over recorded udev events (dev/udev/, written
# into the FIFO /tmp/udev-events by the suite), a second monitor through a niri
# shim, a gaming mouse (fake ratbagctl), a security key (fake fido2-token and
# pamu2fcfg) and controllers from /tmp/input-devices (a /proc/bus/input/devices)
export SHANI_PLUGWATCH_TOOL=/work/bridge/plugwatch.py SHANI_UDEVADM=/work/dev/fake-udevadm.sh
export SHANI_RATBAG_TOOL=/work/bridge/ratbag.py SHANI_RATBAGCTL=/work/dev/fake-ratbagctl.py
export SHANI_U2F_TOOL=/work/bridge/u2f.py SHANI_FIDO2_TOKEN=/work/dev/fake-fido2-token.sh SHANI_PAMU2FCFG=/work/dev/fake-pamu2fcfg.sh
# what there is to type on: a laptop's keyboard (dev/udev-db/), unless a test swaps
# the file for one without (and then says so with a udev event); tablet mode from
# a FIFO standing in for the switch's node
cp /work/dev/udev-db/laptop.txt /tmp/udev-db
export SHANI_INPUT_KINDS_TOOL=/work/bridge/input-kinds.py SHANI_UDEV_DB=/tmp/udev-db
export SHANI_MOUNTS_TOOL=/work/bridge/mounts.py SHANI_GIO=/work/dev/fake-gio.sh
export SHANI_UINPUT=/nonexistent/uinput SHANI_GAMEPAD_TOOL=/work/bridge/gamepad.py SHANI_INPUT_DEVICES=/tmp/input-devices SHANI_INPUT_DIR=/tmp/fake-input
mkdir -p /tmp/fake-input /tmp/fake-bin && : > /tmp/input-devices
REAL_NIRI=$(command -v niri) && export REAL_NIRI && ln -sf /work/dev/fake-niri-outputs.sh /tmp/fake-bin/niri
export SHANI_TRANSLATE_TOOL=/work/dev/fake-translate.py
# the dynamic-lock grace is a Settings key now (dynamicLockGrace): shell-test.sh
# sets it to 1.5 s in its base settings, so the phone-leaves test runs the real path
export SHANI_AGENDA_TOOL=/work/bridge/agenda.py SHANI_MODEM_TOOL=/work/dev/fake-modem.py
export XDG_CONFIG_HOME=/root/.config SHANI_SHELL_SETTINGS=/tmp/shani-settings.json
export SHANI_SCRCPY=/work/dev/fake-scrcpy.sh SHANI_ADB=/work/dev/fake-adb-full.py SHANI_NFC=/work/dev/fake-nfc.py SHANI_IR=/work/dev/fake-ir.py SHANI_FM=/work/dev/fake-fm.py SHANI_LAUNCHER_ENTRY_TOOL=/work/bridge/launcher-entry.py SHANI_APPFILTER_TOOL=/work/dev/fake-appfilter.sh SHANI_LAUNCH_TOOL=/work/bridge/launch-app.py SHANI_APPMENU_TOOL=/work/bridge/appmenu.py SHANI_INPUTPLUMBER_TOOL=/work/bridge/inputplumber.py SHANI_UPS_TOOL=/work/bridge/ups.py SHANI_UPSC=/work/dev/fake-upsc.sh SHANI_YKMAN=/work/dev/fake-ykman.sh
# the shell's own apps, as the package installs them: their desktop entries
# (the launcher's app list, the dock's and the switcher's icon for an app window)
python3 /work/bin/shani app --write-desktop /root/.local/share/applications
export SHANI_CHARACTERS_TOOL=/work/bridge/characters.py SHANI_PHONE_TOOL=/work/bridge/link.py SHANI_DEVICES_TOOL=/work/bridge/devices.py SHANI_PHONE_TOOLS_TOOL=/work/bridge/phone_tools.py SHANI_ANDROID_TOOLS_TOOL=/work/bridge/android_tools.py SHANI_MUSIC="python3 /work/dev/fake-phone-tools.py music" SHANI_FILES_SEND="python3 /work/dev/fake-phone-tools.py files-send" SHANI_PHONE_REMOTE="python3 /work/dev/fake-phone-tools.py remote" SHANI_PHONE_LINK="python3 /work/dev/fake-phone-tools.py link" SHANI_AUDIO="python3 /work/dev/fake-phone-tools.py audio" SHANI_PHONE_TOOLS_STATE=/tmp/fake-phone-tools.json SHANI_FILES_DIR=/tmp/fake-phone-files-inbox SHANI_FILES_LOG=/tmp/fake-phone-files-calls SHANI_PHONE_REMOTE_LOG=/tmp/fake-phone-remote-calls SHANI_PHONE_LINK_LOG=/tmp/fake-phone-link-calls SHANI_AUDIO_LOG=/tmp/fake-phone-audio-calls SHANI_SERVICES_TOOL=/work/bridge/services.py
# an Android phone with no app on it: the adb stand-in reads this fake phone tree
export SHANI_FAKE_PHONE_DIR=/tmp/fake-android-phone SHANI_BACKUP_CANCEL=/tmp/android-backup-cancel
python3 /work/dev/fake-android-phone.py "$SHANI_FAKE_PHONE_DIR" >/dev/null 2>&1
# Maintenance writes keep their own deploy stand-in; the system pages' reads
# and verification use SHANI_SYSTEM_DEPLOY from dev/fake-system-env.sh.
export SHANI_DEPLOY=/work/dev/fake-system-root.py
export SHANI_BOOTINFO_TOOL=/work/bridge/bootinfo.py SHANI_CRONTAB=/work/dev/fake-crontab.sh SHANI_ZIPADD_TOOL=/work/bridge/zipadd.py SHANI_ARCHIVE_EXTRACT_TOOL=/work/bridge/zipcrypt.py
export SHANI_PDFFORM_TOOL=/work/bridge/pdfform.py SHANI_TIDY_TOOL=/work/bridge/tidy.py SHANI_BATTERY_TOOL=/work/bridge/battery.py SHANI_MPRIS_TOOL=/work/bridge/mpris-player.py SHANI_TASKS_TOOL=/work/bridge/tasks.py SHANI_MUSIC_LIBRARY_TOOL=/work/bridge/music-library.py SHANI_CLEANUP_TOOL=/work/bridge/cleanup.py SHANI_OTP_TOOL=/work/bridge/otp.py SHANI_NEARBY_TOOL=/work/bridge/nearby.py SHANI_CONVERT_TOOL=/work/bridge/convert.py
# no sweep of the host's network from the test session; a stand-in firewall-cmd records what it is asked
export SHANI_NEARBY_SUBNET=0 SHANI_NEARBY_PEERS=127.0.0.1:53399 SHANI_FIREWALL_CMD=/work/dev/fake-firewall-cmd.sh
# the file manager's backend: the listing, the watch and the trash
export SHANI_FILES_TOOL=/work/bridge/files.py SHANI_FILES_JOB_DELAY_FILE=/tmp/files-job-delay
export SHANI_REPORT_TOOL=/work/bridge/system-report.py SHANI_HEALTH_TOOL=/work/bridge/health-check.py SHANI_FITNESS_TOOL=/work/bridge/health.py SHANI_WATCH_FAKE=/tmp/fake-watch.json
# Settings > System: stand-ins for fwupd, shani-health, mdadm, lvs, resolvectl…
# and the bridge tools that read them (dev/fake-system-env.sh is a harness part).
. /work/dev/fake-system-env.sh
# Settings > Security > Encryption and boot: gen-efi's stand-in answers the same
# JSON as the real tool. "env" stands in for pkexec: no password is asked, and
# every call still goes through the bridge's privileged-command path.
export SHANI_SECURITY_BOOT_TOOL=/work/bridge/system_security_boot.py
export SHANI_GEN_EFI=/work/dev/fake-gen-efi.py
export SHANI_SECURITY_PKEXEC=env FAKE_GEN_EFI_DIR=/tmp/fake-gen-efi
mkdir -p "$FAKE_GEN_EFI_DIR"
printf '%s' "${FAKE_GEN_EFI_STATE:-encrypted-tpm}" > "$FAKE_GEN_EFI_DIR/state"
# Settings > Power > what can wake this computer: the bridge reads a stand-in
# /sys (dev/shell-parts/wake-sources.sh makes it), and the administrator
# actions are recorded, not run (dev/fake-admin.sh; the real one: dev/admin-test.sh)
export SHANI_WAKEUP_TOOL=/work/bridge/wakeup.py SHANI_SYSFS=/tmp/fake-sys
# Settings > Controllers > lights: bridge/lighting.py reads SHANI_LEDS_DIR (below)
export SHANI_LIGHTING_TOOL=/work/bridge/lighting.py SHANI_POWERLIMIT_TOOL=/work/bridge/powerlimit.py
export SHANI_ADMIN_TOOL=/work/dev/fake-admin.sh
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
export PATH=/tmp/fake-backlight/bin:/tmp/fake-bin:$PATH
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
export SHANI_HANDWRITING_TOOL=/work/bridge/handwriting.py
export SHANI_COMPASS_CMD='echo "Compass heading changed: 90.0"; exec sleep 6011'
# an accelerometer: write a way to hold it into /tmp/accel ("left-up"...) and it says so
export SHANI_ACCEL_CMD='while :; do if [ -f /tmp/accel ]; then echo "    Accelerometer orientation changed: $(cat /tmp/accel)"; rm -f /tmp/accel; fi; sleep 0.3; done'
printf '#!/bin/sh\ntest -e /tmp/face-match\n' > /usr/local/bin/fake-face && chmod +x /usr/local/bin/fake-face
printf 'auth sufficient pam_exec.so quiet /usr/local/bin/fake-face\nauth requisite pam_deny.so\n' > /etc/pam.d/shani-lock-biometric
# the desktop package's input-method default (English + Hindi phonetic)
[ -f /work/dev/fcitx5-profile ] && install -Dm644 /work/dev/fcitx5-profile /etc/xdg/fcitx5/profile
mkdir -p "$XDG_RUNTIME_DIR" /work/out/logs /root/Videos && chmod 700 "$XDG_RUNTIME_DIR"
L=/work/out/logs

# a differently shaped headless screen for one run: SHANI_SCREEN=1400 makes the
# render 1920x1400 (surfaces that sit lower than one screen otherwise shows);
# SHANI_WIDTH=412 SHANI_SCREEN=915 is a phone, so portrait can be tested at the
# width a phone really has - the form-factor profile only changes the scale, and
# every other check here assumes the 1920x1080 default
weston --backend=headless-backend.so --shell=kiosk-shell.so --width="${SHANI_WIDTH:-1920}" --height="${SHANI_SCREEN:-1080}" \
    --socket=wayland-parent --idle-time=0 --no-config >$L/weston.log 2>&1 &
sleep 1.5
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address=1 | head -1)
export DBUS_SESSION_BUS_ADDRESS

# a system bus with the real daemons the shell's services talk to; no
# hardware behind them, but their D-Bus APIs are the real ones
mkdir -p /run/dbus
# InputPlumber's bus policy, as its package ships it (the stand-in below owns its name)
mkdir -p /etc/dbus-1/system.d
cat > /etc/dbus-1/system.d/org.shadowblip.InputPlumber.conf <<'POLICY'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root"><allow own="org.shadowblip.InputPlumber"/></policy>
  <policy context="default"><allow send_destination="org.shadowblip.InputPlumber"/></policy>
</busconfig>
POLICY
dbus-daemon --system --fork --nopidfile 2>$L/dbus-system.log
sleep 0.5
# InputPlumber, stood in for (dev/fake-inputplumber.py): one handheld controller,
# its intercept modes, presses from /tmp/fake-inputplumber
python3 /work/dev/fake-inputplumber.py >$L/fake-inputplumber.log 2>&1 &
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

# Chronoa: the scripted mock (the suite: the same answers every run), or with
# CHRONOA=real the real shani-chronoa app from ../shani-chronoa (dev/check.sh
# mounts it at /chronoa, on the host network so it reaches the model on
# 127.0.0.1:8765) - started below, once niri is up, as it is a window
[ "${CHRONOA:-mock}" = real ] && [ -x /chronoa/usr/bin/shani-chronoa ] || python3 "${SHANI_CHRONOA_AGENT:-/work/dev/mock-chronoa.py}" >$L/mock.log 2>&1 &
# Maps: OpenStreetMap's tiles, Nominatim and OSRM stood in for (dev/fake-osm.py), so
# the suite has the same answers every run and does not load OSM's servers; with
# SHANI_ONLINE=1 (dev/check.sh) the real ones (dev/shell-parts/maps-online.sh)
if [ "${SHANI_ONLINE:-}" != 1 ]; then
    python3 /work/dev/fake-osm.py 8797 >$L/fake-osm.log 2>&1 &
    python3 /work/dev/fake-radio.py 8798 >$L/fake-radio.log 2>&1 &
    export SHANI_RADIO_API=http://127.0.0.1:8798
    export SHANI_MAP_TILES="http://127.0.0.1:8797/tiles/{key}.png" SHANI_MAP_SEARCH=http://127.0.0.1:8797/search SHANI_MAP_ROUTE=http://127.0.0.1:8797
fi
# Live TV: the shell's M3U reader, used by the Media Player > Live TV page
export SHANI_LIVETV_TOOL=/work/bridge/live-tv.py
# Podman, Distrobox and the systemd tools stood in for (by the name each is run
# as): the Containers window's listing and actions, with nothing pulled or booted
mkdir -p /tmp/fake-podman/bin
for t in podman distrobox; do ln -sf /work/dev/fake-podman.py /tmp/fake-podman/bin/$t; done
for t in machinectl importctl systemd-vmspawn; do ln -sf /work/dev/fake-machinectl.py /tmp/fake-podman/bin/$t; done
export FAKE_PODMAN=/tmp/fake-podman SHANI_PODMAN=/tmp/fake-podman/bin/podman SHANI_DISTROBOX=/tmp/fake-podman/bin/distrobox
export SHANI_MACHINECTL=/tmp/fake-podman/bin/machinectl SHANI_IMPORTCTL=/tmp/fake-podman/bin/importctl SHANI_VMSPAWN=/tmp/fake-podman/bin/systemd-vmspawn
# LXD, Apptainer, libvirt, Waydroid, compose and user services stood in for too:
for spec in "lxc:/tmp/fake-lxc:dev/fake-lxc.py" "lxd:/tmp/fake-lxc:dev/fake-lxc.py" \
            "apptainer:/tmp/fake-apptainer:dev/fake-apptainer.py" \
            "virsh:/tmp/fake-virsh:dev/fake-virsh.py" "virt-viewer:/tmp/fake-virsh:dev/fake-virsh.py" \
            "waydroid:/tmp/fake-waydroid:dev/fake-waydroid.py" "waydroid-helper:/tmp/fake-waydroid:dev/fake-waydroid.py" \
            "podman-compose:/tmp/fake-compose:dev/fake-compose.py" "systemctl:/tmp/fake-compose:dev/fake-systemctl-user.py"; do
    tool=${spec%%:*}; rest=${spec#*:}; dir=${rest%%:*}; fake=${rest#*:}
    mkdir -p "$dir/bin"
    ln -sf "/work/$fake" "$dir/bin/$tool"
done
export FAKE_LXC=/tmp/fake-lxc FAKE_APPTAINER=/tmp/fake-apptainer FAKE_VIRSH=/tmp/fake-virsh
export FAKE_WAYDROID=/tmp/fake-waydroid FAKE_COMPOSE=/tmp/fake-compose
export SHANI_LXC=/tmp/fake-lxc/bin/lxc SHANI_LXD=/tmp/fake-lxc/bin/lxd
export SHANI_APPTAINER=/tmp/fake-apptainer/bin/apptainer SHANI_APPTAINER_FOLDER=/tmp/fake-apptainer/images
FAKE_APPTAINER=/tmp/fake-apptainer python3 /work/dev/fake-apptainer.py --version >/dev/null 2>&1 || true   # seed its images
export SHANI_VIRSH=/tmp/fake-virsh/bin/virsh SHANI_VIRT_VIEWER=/tmp/fake-virsh/bin/virt-viewer SHANI_KVM=1
export SHANI_WAYDROID=/tmp/fake-waydroid/bin/waydroid SHANI_WAYDROID_HELPER=/tmp/fake-waydroid/bin/waydroid-helper SHANI_PKEXEC=
export SHANI_COMPOSE=/tmp/fake-compose/bin/podman-compose SHANI_SYSTEMCTL=/tmp/fake-compose/bin/systemctl
export SHANI_QUADLET_DIR=/tmp/fake-quadlet
# udisks2 stood in for on the session bus (tests/fixtures/fake_udisks.py): a USB
# stick and the computer's own disk; a write lands in /tmp/fake-udisks/sdb.img
mkdir -p /tmp/fake-udisks
FAKE_LUKS=1 FAKE_UDISKS_DIR=/tmp/fake-udisks python3 -W ignore /work/tests/fixtures/fake_udisks.py >$L/fake-udisks.log 2>&1 &
export SHANI_UDISKS_BUS=session SHANI_DRIVES_TOOL=/work/bridge/drives.py SHANI_LOCK_TOOL=/work/bridge/lock.py SHANI_SERVE_TOOL=/work/bridge/serve.py SHANI_DUPES_TOOL=/work/bridge/dupes.py SHANI_IMGEDIT_TOOL=/work/bridge/imgedit.py SHANI_CLOUD_TOOL=/work/bridge/cloud.py SHANI_FLATPERM_TOOL=/work/bridge/flatperm.py SHANI_PASSWORDS_TOOL=/work/bridge/passwords.py SHANI_APPSTORE_TOOL=/work/bridge/appstore.py SHANI_CONTAINERS_TOOL=/work/bridge/containers.py SHANI_APPSTREAM=${SHANI_APPSTREAM:-/work/tests/fixtures/appstream.xml} SHANI_SNAP=/work/dev/fake-snap.sh FAKE_SNAP_DIR=/tmp/fake-snap
# the renders show Flathub's real catalogue (baked into the image); the suite keeps
# the two-app fixture its checks count on
if [ -n "${SHANI_REAL_CATALOGUE:-}" ]; then
    for f in /var/lib/flatpak/appstream/flathub/*/active/appstream.xml.gz; do [ -f "$f" ] && export SHANI_APPSTREAM="$f"; done
fi
rm -rf /tmp/fake-snap
python3 /work/bridge/chronoa-bridge.py >$L/bridge.log 2>&1 &
sleep 0.5

# foot as the image has it: shani-desktop-niri.install puts its foot.ini in /etc/xdg/foot
[ -f /desk/usr/share/shani-desktop-niri/foot.ini ] && install -Dm644 /desk/usr/share/shani-desktop-niri/foot.ini /etc/xdg/foot/foot.ini
WAYLAND_DISPLAY=wayland-parent niri -c "${NIRI_CONFIG:-/work/dev/niri/session.kdl}" >$L/niri.log 2>&1 &
i=0
until [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done
export WAYLAND_DISPLAY=wayland-1
export NIRI_SOCKET=$(ls "$XDG_RUNTIME_DIR"/niri.wayland-1.*.sock | head -1)

if [ "${CHRONOA:-mock}" = real ] && [ -x /chronoa/usr/bin/shani-chronoa ]; then
    # its schema from the source tree; the shell owns the phone backends now
    GSETTINGS_SCHEMA_DIR=/chronoa/usr/share/glib-2.0/schemas \
        python3 /chronoa/usr/bin/shani-chronoa >$L/chronoa.log 2>&1 &
    i=0; until gdbus introspect --session --dest dev.shani.chronoa.Agent --object-path /dev/shani/chronoa/Agent >/dev/null 2>&1 || [ $i -ge 120 ]; do sleep 0.25; i=$((i+1)); done
    echo "  real Chronoa: $(grep -o 'Using the local llama.cpp server at [^ ]*' $L/chronoa.log | head -1 || echo 'no model found')"
fi

# the accessibility bus, and Qt exposing its tree on it (what Orca reads)
/usr/lib/at-spi-bus-launcher --launch-immediately >$L/atspi.log 2>&1 &
sleep 0.5
# the wallpapers where the package installs them
mkdir -p /usr/share/backgrounds/shani && cp /work/assets/shani-dark.jpg /work/assets/shani-night.jpg /work/assets/shani-light.jpg /usr/share/backgrounds/shani/
# "What's new" after an update: the shipped summary where the package puts
# it, and a version file the whats-new shell part can bump
mkdir -p /usr/share/shani && cp /work/data/whats-new.md /usr/share/shani/ && printf '0.0.0-test\n' > /etc/shani-version
# idle off from the start (the tests drive the shell over IPC, which is not input).
# More for this run: SHANI_SETTINGS_EXTRA, JSON merged over it (python3, when here).
printf '{"dimAfter": 0, "lockAfter": 0, "screenOffAfter": 0, "lockAfterBattery": 0, "screenOffAfterBattery": 0, "startHintsDone": true, "dockPinned": ["org.gnome.Nautilus", "com.vivaldi.Vivaldi", "foot", "shani-chronoa", "org.gnome.TextEditor"]}' > "$SHANI_SHELL_SETTINGS"
if [ -n "${SHANI_SETTINGS_EXTRA:-}" ] && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; d = json.loads(sys.argv[1]); d.update(json.loads(sys.argv[2])); print(json.dumps(d))' \
        "$(cat "$SHANI_SHELL_SETTINGS")" "$SHANI_SETTINGS_EXTRA" > "$SHANI_SHELL_SETTINGS"
fi
# the image's own icon theme (shani-desktop-niri's gschema override); and
# accessibility on, so the suite can press controls through AT-SPI
export QS_ICON_THEME=${QS_ICON_THEME:-Papirus-Dark} QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
# every frame the shell renders, per window, into qs.log: what shell-test's
# perf-* checks count (a surface redrawing while nothing changes is GPU and battery)
date +%s%N > /tmp/qs-started
# the keyring, made and unlocked with a password as pam_oo7 does at sign-in (the
# Authenticator keeps its secrets there; needs the container's IPC_LOCK).
# oo7-daemon stays in the foreground: started in the background, its readiness
# is its name on the session bus.
printf 'test' | /usr/lib/oo7-daemon --login >$L/keyring.log 2>&1 &
i=0; until busctl --user status org.freedesktop.secrets >/dev/null 2>&1 || [ $i -ge 40 ]; do sleep 0.1; i=$((i+1)); done
# as shani-shell.service: the shell's windows draw their own header (Common/AppWindow)
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true" qs -p /work/shani >$L/qs.log 2>&1 &
sleep 4
