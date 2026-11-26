# Harness stand-ins for the shell's System pages. Sourced by dev/session.sh so
# every shell part drives the same fixed state: dev/fake-system-*.py, the
# dev/fake-* stand-ins the pages' bridge commands already support, and fixture
# files under /tmp/fake-system. Nothing here writes to the real machine.
FS=/tmp/fake-system
mkdir -p "$FS/bin-net" "$FS/bin-access" "$FS/bin-bg" "$FS/bin-boot" "$FS/bin-misc" "$FS/audit" "$FS/nut" "$FS/access" "$FS/virt" "$FS/bg" "$FS/cron/cron.d" "$FS/cron/cron.hourly" "$FS/cron/cron.daily" "$FS/pam" "$FS/polkit" "$FS/reports"
: > "$FS/kvm"

# One stand-in file, several tool names (the bridges pass the path directly).
for t in flatpak snap ostree lspci glxinfo; do ln -sf /work/dev/fake-system-info.py "$FS/bin-net/$t"; done
ln -sf /work/dev/fake-system-info.py "$FS/bin-net/shani-etc-changes"
for t in mdadm pvs vgs lvs btrfs compsize smartctl; do ln -sf /work/dev/fake-system-disks.py "$FS/bin-net/$t"; done
for t in resolvectl systemctl ss avahi-browse caddy cloudflared; do ln -sf /work/dev/fake-system-net.py "$FS/bin-net/$t"; done
for t in systemctl ssh-keygen; do ln -sf /work/dev/fake-system-access.py "$FS/bin-access/$t"; done
for t in systemctl ausearch; do ln -sf /work/dev/fake-system-bg.py "$FS/bin-bg/$t"; done
for t in virsh lxc lxd machinectl; do ln -sf /work/dev/fake-system-virt.py "$FS/bin-net/$t"; done

# The shell's pages reach their bridge modules through these overrides.
export SHANI_SYSTEM_FIRMWARE_TOOL=/work/bridge/system_firmware.py
export SHANI_SYSTEM_HEALTH_TOOL=/work/bridge/system_health.py
export SHANI_SYSTEM_MAINTENANCE_TOOL=/work/bridge/system_maintenance.py
export SHANI_SYSTEM_APPS_TOOL=/work/bridge/system_apps.py
export SHANI_SYSTEM_MACHINE_TOOL=/work/bridge/system_machine.py
export SHANI_SYSTEM_DISKS_TOOL=/work/bridge/system_disks.py
export SHANI_SYSTEM_NET_TOOL=/work/bridge/system_net.py
export SHANI_SYSTEM_ACCESS_TOOL=/work/bridge/system_access.py
export SHANI_SYSTEM_VIRT_TOOL=/work/bridge/system_virt.py
export SHANI_SYSTEM_BG_TOOL=/work/bridge/system_background.py

# Firmware, checks and root-only maintenance.
export SHANI_FWUPDMGR=/work/dev/fake-fwupdmgr.py FAKE_FWUPDMGR="$FS/firmware"
export SHANI_SYSTEM_HEALTH=/work/dev/fake-shani-health.py FAKE_SHANI_HEALTH="$FS/health"
export SHANI_SYSTEM_PKEXEC="" SHANI_DEPLOY=/work/dev/fake-system-root.py
export SHANI_HEALTH=/work/dev/fake-system-root.py SHANI_RESET=/work/dev/fake-system-root.py
export SHANI_REPORT_DIR="$FS/reports" FAKE_SYSTEM_ROOT="$FS/root"
mkdir -p "$FS/firmware" "$FS/health" "$FS/root"

# Versions, graphics, /etc changes and persistence.
export SHANI_SYSTEM_FLATPAK="$FS/bin-net/flatpak" SHANI_SYSTEM_SNAP="$FS/bin-net/snap"
export SHANI_OSTREE="$FS/bin-net/ostree" SHANI_OS_RELEASE=/work/data/os-release.fixture
export SHANI_LSPCI="$FS/bin-net/lspci" SHANI_GLXINFO="$FS/bin-net/glxinfo"
export SHANI_SYSTEM_DRI_DIR="$FS/dri" FAKE_SYSTEM_INFO="$FS/info"
export SHANI_ETC_CHANGES="python3 $FS/bin-net/shani-etc-changes"
printf 'ID=shani\nPRETTY_NAME="ShaniOS (test)"\nVERSION_ID=2026.10.28\n' > "$FS/os-release"
export SHANI_OS_RELEASE="$FS/os-release"
mkdir -p "$FS/dri" "$FS/data/accounts" "$FS/data/apps" && : > "$FS/dri/renderD128"
printf '25 0 0:24 / / rw,relatime - overlay overlay rw,lowerdir=/data/lower\n36 25 253:1 /home /var/lib/accounts rw,relatime - ext4 /dev/nvme0n1p4 rw\n49 25 0:35 /data/apps /var/lib/apps rw,relatime - overlay overlay rw\n' > "$FS/mountinfo"
export SHANI_MOUNTINFO="$FS/mountinfo" SHANI_DATA_DIR="$FS/data" SHANI_DATA_SIZE=

# Disks and filesystems.
export SHANI_MDSTAT="$FS/mdstat" FAKE_SYSTEM_DISKS="$FS/disks" \
       SHANI_MDADM="$FS/bin-net/mdadm" SHANI_PVS="$FS/bin-net/pvs" SHANI_VGS="$FS/bin-net/vgs" \
       SHANI_LVS="$FS/bin-net/lvs" SHANI_BTRFS="$FS/bin-net/btrfs" \
       SHANI_COMPSIZE="$FS/bin-net/compsize" SHANI_SMARTCTL="$FS/bin-net/smartctl"
printf 'Personalities : [raid1]\nmd127 : active raid1 sda1[0] sdb1[1]\n      976630336 blocks super 1.2 [2/2] [UU]\n' > "$FS/mdstat"

# Network services. One systemctl stand-in answers units for all three pages.
cat > "$FS/systemctl" <<'SH'
#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
unit = args[-1] if args else ""
if "smartd" in unit:
    target = "/tmp/fake-system/bin-misc/systemctl"
elif "auditd" in unit:
    target = "/tmp/fake-system/audit/systemctl"
else:
    which = "access" if any(x in unit for x in ("sssd", "slapd")) else "bg" if "ananicy" in unit else "net"
    target = "/tmp/fake-system/bin-%s/systemctl" % which
os.execv(target, ["systemctl"] + args)
SH
chmod +x "$FS/systemctl"
export SHANI_SYSTEM_SYSTEMCTL="$FS/systemctl" SHANI_SYSTEMCTL="$FS/systemctl"
export FAKE_SYSTEM_NET="$FS/net" SHANI_RESOLV_CONF="$FS/net/resolv.conf" \
       SHANI_CADDYFILE="$FS/net/Caddyfile" SHANI_CLOUDFLARED_DIR="$FS/net/cloudflared-config" \
       SHANI_EXIM_CONF="$FS/net/exim.conf" SHANI_SYSCTL_FILE="$FS/net/ip_forward"
python3 /work/dev/fake-system-net.py fixtures

# Sign-in and access fixtures: none of these hold a real secret.
export FAKE_SYSTEM_ACCESS="$FS/access" SHANI_NSSWITCH="$FS/nsswitch" \
       SHANI_KRB5_CONF="$FS/krb5.conf" SHANI_SYSTEM_PAM_DIR="$FS/pam" \
       SHANI_PKCS11_CONF="$FS/pkcs11.conf" SHANI_PKCS11_MAP="$FS/subject_mapping" \
       SHANI_POLKIT_DIR="$FS/polkit" SHANI_SUDOERS="$FS/sudoers" \
       SHANI_SSHD_CONF="$FS/sshd.conf" SHANI_LSM_FILE="$FS/lsm" \
       SHANI_SYSTEM_SSH_KEYGEN="$FS/bin-access/ssh-keygen" SHANI_AUTHORIZED_KEYS="$FS/authorized_keys" \
       SHANI_OATH_FILE="$FS/users.oath"
printf 'passwd: files sss\ngroup: files sss\nshadow: files sss\n' > "$FS/nsswitch"
printf '[libdefaults]\n default_realm = EXAMPLE.LAN\n[domain_realm]\n .example.lan = EXAMPLE.LAN\n' > "$FS/krb5.conf"
printf 'auth sufficient pam_krb5.so\n' > "$FS/pam/system-auth"
printf 'mapper = uid\nprovider = /usr/lib/p11-kit/pkcs11.so\n' > "$FS/pkcs11.conf"
printf 'alice -> alice\nbob -> bob\n' > "$FS/subject_mapping"
printf 'polkit.addRule(function(a) { if (a.id == "org.freedesktop.systemd1.manage-units") return polkit.Result.YES; });\n' > "$FS/polkit/50-shell.rules"
printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$FS/sudoers"
printf 'PasswordAuthentication no\nPubkeyAuthentication yes\n' > "$FS/sshd.conf"
printf 'capability,yama,landlock\n' > "$FS/lsm"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTests alice@laptop\n' > "$FS/authorized_keys"
printf 'TOTP/T30 alice - 123456 6 30\n' > "$FS/users.oath"

# Virtualization readiness and inventory.
export FAKE_SYSTEM_VIRT="$FS/virt" SHANI_KVM_PATH="$FS/kvm" SHANI_MODULES_FILE="$FS/modules" \
       SHANI_SYSTEM_VIRSH="$FS/bin-net/virsh" SHANI_SYSTEM_LXC="$FS/bin-net/lxc" \
       SHANI_SYSTEM_LXD="$FS/bin-net/lxd" SHANI_SYSTEM_MACHINECTL="$FS/bin-net/machinectl" \
       SHANI_LXD_SOCKET="$FS/lxd.socket"
printf 'kvm 16384 1 - Live 0xffffffff\nkvm_intel 4096 0 - Live 0xffffffff\n' > "$FS/modules"
: > "$FS/lxd.socket"

# Background services and the audit log.
export FAKE_SYSTEM_BG="$FS/bg" SHANI_CRONTAB_ROOT="$FS/cron" \
       SHANI_ANANICY="$FS/bin-bg/systemctl" SHANI_AUSEARCH="$FS/bin-bg/ausearch" \
       SHANI_INTERRUPTS="$FS/interrupts"
printf '# system crontab\n17 * * * * root cd / && echo tick\n' > "$FS/crontab"
printf '0 3 * * * root /usr/local/bin/shani-clean\n' > "$FS/cron/cron.d/clean"
printf '         CPU0       CPU1\n  0:         10          4   IO-APIC   2-edge      timer\n  1:          0         42   IO-APIC   1-edge      i8042\n  8:        100          0   IO-APIC   8-edge      rtc0\n' > "$FS/interrupts"

# ---- Boot checks, storage analysis, audit events, UPS policy, banned IPs ----
# One stand-in file per tool name, reached by symlink through its own basename.
for t in shani-deploy sbctl mokutil; do ln -sf /work/dev/fake-boot-tools.py "$FS/bin-boot/$t"; done
for t in ausearch systemctl; do ln -sf /work/dev/fake-audit.py "$FS/audit/$t"; done
ln -sf /work/dev/fake-upsmon.py "$FS/nut/shani-cassini-save"
ln -sf /work/dev/fake-unit-state.py "$FS/bin-misc/systemctl"
ln -sf /work/dev/fake-system-net.py "$FS/bin-net/fail2ban-client"
export SHANI_DEPLOY=/work/dev/fake-system-deploy.sh SHANI_SBCTL="$FS/bin-boot/sbctl" \
       SHANI_MOKUTIL="$FS/bin-boot/mokutil" FAKE_BOOT_TOOLS_DIR="$FS/boot"
export SHANI_SYSTEM_PKEXEC=/work/dev/fake-pkexec.sh FAKE_PKEXEC_LOG="$FS/pkexec-calls"
export SHANI_AUSEARCH="$FS/audit/ausearch" SHANI_AUDIT_LOG="$FS/audit/audit.log" FAKE_AUDIT="$FS/audit"
export SHANI_CASSINI_SAVE="$FS/nut/shani-cassini-save" SHANI_UPSMON_CONF="$FS/nut/upsmon.conf" \
       FAKE_UPMON="$FS/nut"
export SHANI_FAIL2BAN_CLIENT="$FS/bin-net/fail2ban-client"
export SHANI_SMARTD_CONF="$FS/smartd.conf" FAKE_UNIT_SMARTD=active
printf 'DEVICESCAN -d removable -n standby -m root -M exec /usr/share/smartmontools/smartd-runner\n' > "$SHANI_SMARTD_CONF"
printf '# managed by the desktop\nMINSUPPLIES 1\nSHUTDOWNCMD "/sbin/shutdown -h +0"\nPOWERDOWNFLAG /etc/killpower\nDEADTIME 15\nFINALDELAY 0\nPOLLFREQ 5\nPOLLFREQALERT 5\nMONITOR myups@localhost 1 monitor pass primary\n' > "$SHANI_UPSMON_CONF"
printf "%s\n" "type=USER_LOGIN msg=audit(1710000000.100:42): pid=100 uid=0 auid=1000 msg='op=login id=\"alice\"'" > "$SHANI_AUDIT_LOG"
mkdir -p "$FS/boot" "$FS/root"
