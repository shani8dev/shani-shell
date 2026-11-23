#!/usr/bin/env python3
"""disks — disk management for the shell, through pkexec.

    disks.py list                   JSON array of block devices (lsblk)
    disks.py relabel DEVICE LABEL   change a filesystem label in place (no reformat)
    disks.py fsck DEVICE            read-only filesystem check (fsck -n)
    disks.py badblocks DEVICE       non-destructive bad-block scan (badblocks -n)
    disks.py health DEVICE          JSON object with SMART health (smartctl)
    disks.py erase-quick DEVICE     wipe filesystem signatures (wipefs -a)
    disks.py erase-secure DEVICE    zero the first 100 MB (dd)
    disks.py format DEVICE FSTYPE [LABEL]
                                    create a filesystem (mkfs.*)
    disks.py encrypt DEVICE FSTYPE PASSPHRASE
                                    LUKS format + open + mkfs inside
    disks.py install-stick DEVICE ISO
                                    write an ISO to a USB drive (dd)
    disks.py smart DEVICE            full SMART attribute table + self-test log
    disks.py smart-status DEVICE     remaining % of a running self-test (poll)
    disks.py smart-test DEVICE short|long|conveyance
                                    start a SMART self-test
    disks.py benchmark DEVICE        read-only sequential read speed
    disks.py take-ownership DEVICE   chown the mounted filesystem to the user

All write operations need root (pkexec). The caller (Services/Disks.qml)
runs this through pkexec, so this script runs as root.

Exit codes: 0 = success, 1 = polkit dismissed (not an error), 2+ = failure.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def _bare(name: str) -> str:
    s = str(name or "")
    return s[5:] if s.startswith("/dev/") else s


def _flatten(devices: list[dict]):
    for d in devices:
        yield d
        yield from _flatten(d.get("children") or [])


def protected_devices(devices: list[dict]) -> set[str]:
    """Whole disks backing '/' plus every device beneath them.

    lsblk reports the mountpoint on the node holding the filesystem, which may
    be a partition or a mapper device. Walking up PKNAME reaches the whole disk
    and walking the tree down covers all of its partitions, so neither the
    system disk nor any sibling partition can be wiped while the system runs.
    """
    all_devs = list(_flatten(devices))
    by_name = {_bare(d.get("name")): d for d in all_devs}
    tree_parent = {}

    def index_parents(nodes, parent=""):
        for d in nodes:
            name = _bare(d.get("name"))
            if parent:
                tree_parent[name] = parent
            index_parents(d.get("children") or [], name)

    index_parents(devices)

    def top(name):
        seen = set()
        while name and name in by_name and name not in seen:
            seen.add(name)
            # PKNAME is a direct kernel parent; the lsblk tree is the fallback
            # for older util-linux builds that omit the column.
            parent = _bare(by_name[name].get("pkname")) or tree_parent.get(name, "")
            if not parent or parent not in by_name:
                return name
            name = parent
        return name

    roots = {
        top(_bare(d.get("name")))
        for d in all_devs
        if "/" in (d.get("mountpoints") or [])
    }
    out = set()
    for d in all_devs:
        name = _bare(d.get("name"))
        if name and top(name) in roots:
            out.add(os.path.realpath("/dev/" + name))
    return out


def _current_disks() -> list[dict]:
    r = run(["lsblk", "-J", "-p", "-o", "NAME,PKNAME,MOUNTPOINTS"])
    if r.returncode != 0:
        return []
    try:
        return json.loads(r.stdout).get("blockdevices", [])
    except json.JSONDecodeError:
        return []


def _block_running_root(device: str) -> bool:
    """Refuse a destructive op on the system disk, or when root is unknown."""
    protected = protected_devices(_current_disks())
    if not protected:
        print(
            json.dumps({"error": "Refusing: cannot identify the running system disk"})
        )
        return True
    if os.path.realpath(device) in protected:
        print(json.dumps({"error": "Refusing to change the running system disk"}))
        return True
    return False


def passphrase_ok(passphrase: str) -> bool:
    return len(passphrase or "") >= 8


def device_fstype(device: str) -> str:
    r = run(["lsblk", "-no", "FSTYPE", device])
    return (
        (r.stdout.strip().splitlines() or [""])[0].strip() if r.returncode == 0 else ""
    )


def relabel(device: str, label: str) -> int:
    """Change a filesystem label in place — no reformat, no data loss."""
    if _block_running_root(device):
        return 1
    label = str(label or "").strip()
    if not label or len(label) > 256 or any(ord(c) < 32 for c in label):
        print(json.dumps({"error": "Invalid label"}))
        return 1
    fstype = device_fstype(device).lower()
    tools = {
        "ext2": ["e2label", device, label],
        "ext3": ["e2label", device, label],
        "ext4": ["e2label", device, label],
        "vfat": ["dosfslabel", device, label],
        "fat16": ["dosfslabel", device, label],
        "fat32": ["dosfslabel", device, label],
        "xfs": ["xfs_admin", "-L", label, device],
        "btrfs": ["btrfs", "filesystem", "label", device, label],
        "exfat": ["exfatlabel", device, label],
        "ntfs": ["ntfslabel", device, label],
    }
    cmd = tools.get(fstype)
    if not cmd:
        print(
            json.dumps(
                {
                    "error": "Relabel is not supported for %s"
                    % (fstype or "this filesystem")
                }
            )
        )
        return 1
    if not shutil.which(cmd[0]):
        print(json.dumps({"error": "%s is not installed" % cmd[0]}))
        return 1
    r = run(cmd)
    if r.returncode != 0:
        print(
            json.dumps(
                {"error": (r.stderr.strip().splitlines() or ["relabel failed"])[-1]}
            )
        )
        return 1
    print(json.dumps({"ok": True, "label": label}))
    return 0


def fsck_check(device: str) -> int:
    """Read-only filesystem check — fsck -n never repairs anything."""
    if _block_running_root(device):
        return 1
    r = run(["fsck", "-n", device])
    print(
        json.dumps(
            {
                "ok": True,
                "code": r.returncode,
                "output": (r.stdout + "\n" + r.stderr).strip() or "No issues reported",
            }
        )
    )
    return 0


def badblocks_scan(device: str) -> int:
    """Non-destructive bad-block scan — -n writes test patterns but keeps data."""
    if _block_running_root(device):
        return 1
    r = run(["badblocks", "-n", "-s", device])
    print(
        json.dumps(
            {
                "ok": True,
                "code": r.returncode,
                "output": (r.stdout + "\n" + r.stderr).strip() or "No bad blocks found",
            }
        )
    )
    return 0


def list_disks() -> int:
    """Print lsblk JSON for the shell to parse."""
    r = run(
        [
            "lsblk",
            "-J",
            "-p",
            "-o",
            "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,LABEL,MODEL,RM,HOTPLUG,RO,TRAN,ROTA",
        ]
    )
    if r.returncode != 0:
        print(f"lsblk failed: {r.stderr}", file=sys.stderr)
        return 1
    print(r.stdout)
    return 0


def check_health(device: str) -> int:
    """Return SMART health as JSON."""
    if not shutil.which("smartctl"):
        print(json.dumps({"error": "smartctl is not installed (smartmontools)"}))
        return 1
    r = run(["smartctl", "-a", "-j", device])
    if r.returncode != 0 and not r.stdout:
        print(f"smartctl failed: {r.stderr}", file=sys.stderr)
        return 1
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        print(json.dumps({"error": "could not parse smartctl output"}))
        return 1
    # extract the interesting bits
    health = {
        "overall": data.get("smart_status", {}).get("passed", "unknown"),
        "model": data.get("model_name", ""),
        "serial": data.get("serial_number", ""),
        "temp": data.get("temperature", {}).get("current", 0),
        "hours": data.get("power_on_time", {}).get("hours", 0),
    }
    print(json.dumps(health))
    return 0


def erase_quick(device: str) -> int:
    """Wipe filesystem signatures — fast, not secure."""
    if _block_running_root(device):
        return 1
    if not shutil.which("wipefs"):
        print("wipefs is not installed (util-linux)", file=sys.stderr)
        return 1
    r = run(["wipefs", "-a", device])
    if r.returncode != 0:
        print(r.stderr.strip(), file=sys.stderr)
        return 1
    print(json.dumps({"ok": True}))
    return 0


def erase_secure(device: str) -> int:
    """Zero the first 100 MB — slower but safer than quick erase."""
    if _block_running_root(device):
        return 1
    r = run(["dd", "if=/dev/zero", f"of={device}", "bs=1M", "count=100", "status=none"])
    if r.returncode != 0:
        print(r.stderr.strip(), file=sys.stderr)
        return 1
    # also wipefs to clear any remaining signatures
    run(["wipefs", "-a", device])
    print(json.dumps({"ok": True}))
    return 0


def format_disk(device: str, fstype: str, label: str) -> int:
    """Create a new filesystem."""
    if _block_running_root(device):
        return 1
    tools = {
        "ext4": ["mkfs.ext4", "-F", device],
        "btrfs": ["mkfs.btrfs", "-f", device],
        "vfat": ["mkfs.vfat", "-F", "32", device],
        "xfs": ["mkfs.xfs", "-f", device],
        "exfat": ["mkfs.exfat", device],
    }
    cmd = tools.get(fstype)
    if not cmd:
        print(f"unknown filesystem type: {fstype}", file=sys.stderr)
        return 1
    if label:
        # add label flag based on fstype
        if fstype in ("ext4", "btrfs"):
            cmd = cmd[:-1] + ["-L", label, device]
        elif fstype == "vfat":
            cmd = cmd[:-1] + ["-n", label, device]
        elif fstype == "xfs":
            cmd = cmd[:-1] + ["-L", label, device]
    r = run(cmd)
    if r.returncode != 0:
        print(r.stderr.strip() or r.stdout.strip(), file=sys.stderr)
        return 1
    print(json.dumps({"ok": True}))
    return 0


def encrypt_disk(device: str, fstype: str, passphrase: str) -> int:
    """LUKS format + open + create filesystem inside."""
    if _block_running_root(device):
        return 1
    if not passphrase_ok(passphrase):
        print(json.dumps({"error": "Passphrase must be at least 8 characters"}))
        return 1
    if not shutil.which("cryptsetup"):
        print("cryptsetup is not installed (cryptsetup)", file=sys.stderr)
        return 1
    # LUKS format
    r = run(
        ["cryptsetup", "luksFormat", "--batch-mode", device],
        input=passphrase,
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print(r.stderr.strip(), file=sys.stderr)
        return 1
    # open
    r = run(
        ["cryptsetup", "luksOpen", device, "shani-disk-unlock"],
        input=passphrase,
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print(r.stderr.strip(), file=sys.stderr)
        return 1
    # format inside
    mapper = "/dev/mapper/shani-disk-unlock"
    rc = format_disk(mapper, fstype, "")
    # close
    run(["cryptsetup", "luksClose", "shani-disk-unlock"])
    if rc != 0:
        return rc
    print(json.dumps({"ok": True}))
    return 0


def install_stick(device: str, iso: str) -> int:
    """Write an ISO to a USB drive."""
    if _block_running_root(device):
        return 1
    if not os.path.isfile(iso):
        print(f"ISO not found: {iso}", file=sys.stderr)
        return 1
    r = run(["dd", f"if={iso}", f"of={device}", "bs=4M", "status=progress"])
    if r.returncode != 0:
        print(r.stderr.strip(), file=sys.stderr)
        return 1
    # sync
    run(["sync"])
    print(json.dumps({"ok": True}))
    return 0


# ---- detailed SMART and self-tests -------------------------------------------------
def smart_details(device: str) -> int:
    """The full smartctl report, reduced to what a details dialog can show."""
    if not shutil.which("smartctl"):
        print(json.dumps({"error": "smartctl is not installed (smartmontools)"}))
        return 1
    r = run(["smartctl", "-a", "-j", device])
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        print(json.dumps({"error": "could not parse smartctl output"}))
        return 1
    attrs = []
    for a in data.get("ata_smart_attributes", {}).get("table", []):
        attrs.append(
            {
                "id": a.get("id"),
                "name": a.get("name", ""),
                "value": a.get("value"),
                "worst": a.get("worst"),
                "thresh": a.get("thresh"),
                "raw": (a.get("raw") or {}).get("value", ""),
            }
        )
    tests = []
    log = data.get("ata_smart_self_test_log", {}).get("standard", {})
    for t in log.get("table", [])[:8]:
        tests.append(
            {
                "type": t.get("test_type", ""),
                "status": t.get("status", {}).get("string", ""),
                "hours": t.get("when", {}).get("hours", ""),
                "remaining": t.get("progress", {}).get("remaining", "")
                if isinstance(t.get("progress"), dict)
                else "",
            }
        )
    out = {
        "error": None,
        "overall": data.get("smart_status", {}).get("passed", "unknown"),
        "model": data.get("model_name", ""),
        "serial": data.get("serial_number", ""),
        "temp": data.get("temperature", {}).get("current", 0),
        "hours": data.get("power_on_time", {}).get("hours", 0),
        "attributes": attrs,
        "tests": tests,
        "capacity": data.get("user_capacity", {}).get("bytes", 0),
        "selfTest": bool(
            data.get("ata_smart_features", {}).get("self_tests", {}).get("supported")
        ),
    }
    print(json.dumps(out))
    return 0


def smart_status(device: str) -> int:
    """Cheap poll: is a self-test running, and how much is left?"""
    if not shutil.which("smartctl"):
        print(json.dumps({"error": "smartctl is not installed (smartmontools)"}))
        return 1
    r = run(["smartctl", "-a", "-j", device])
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        print(json.dumps({"error": "could not parse smartctl output"}))
        return 1
    table = (
        data.get("ata_smart_self_test_log", {}).get("standard", {}).get("table") or []
    )
    entry = table[0] if table else {}
    status = (entry.get("status") or {}).get("string", "") or ""
    progress = entry.get("progress") if isinstance(entry.get("progress"), dict) else {}
    remaining_txt = str(progress.get("remaining", "") or "")
    match = re.search(r"(\d+)", remaining_txt)
    remaining = int(match.group(1)) if match else -1
    print(
        json.dumps(
            {
                "ok": True,
                "active": "in progress" in status.lower(),
                "remaining": remaining,
                "status": status,
            }
        )
    )
    return 0


def smart_test(device: str, kind: str) -> int:
    """Start a short, extended/long or conveyance SMART self-test."""
    kinds = {
        "short": "short",
        "long": "long",
        "extended": "long",
        "conveyance": "conveyance",
    }
    if kind not in kinds:
        print(json.dumps({"error": "unknown self-test: %s" % kind}))
        return 1
    if not shutil.which("smartctl"):
        print(json.dumps({"error": "smartctl is not installed (smartmontools)"}))
        return 1
    r = run(["smartctl", "-t", kinds[kind], device])
    if r.returncode != 0:
        print(
            json.dumps(
                {
                    "error": (
                        r.stderr.strip().splitlines()
                        or r.stdout.strip().splitlines()
                        or ["self-test failed"]
                    )[-1]
                }
            )
        )
        return 1
    print(json.dumps({"ok": True, "test": kinds[kind]}))
    return 0


def benchmark(device: str) -> int:
    """Read-only sequential read speed over the first 64 MiB (no writes)."""
    if not device.startswith("/dev/"):
        print(json.dumps({"error": "not a device path"}))
        return 1
    block = 1024 * 1024
    limit = 64 * block
    total = 0
    started = time.monotonic()
    try:
        with open(device, "rb", buffering=0) as f:
            while total < limit:
                data = f.read(block)
                if not data:
                    break
                total += len(data)
    except OSError as e:
        print(json.dumps({"error": str(e)}))
        return 1
    seconds = max(0.001, time.monotonic() - started)
    print(
        json.dumps(
            {
                "bytes": total,
                "seconds": round(seconds, 2),
                "mbps": round(total / block / seconds, 1),
            }
        )
    )
    return 0


def take_ownership(device: str) -> int:
    """Give the mounted filesystem of a removable disk to the signed-in user."""
    r = run(["lsblk", "-no", "MOUNTPOINTS", device])
    points = [p for p in r.stdout.splitlines() if p.strip()]
    if not points:
        print(json.dumps({"error": "the device is not mounted"}))
        return 1
    uid = os.environ.get("SUDO_UID") or str(os.getuid())
    gid = os.environ.get("SUDO_GID") or str(os.getgid())
    r = run(["chown", "-R", uid + ":" + gid, points[0]])
    if r.returncode != 0:
        print(
            json.dumps(
                {
                    "error": (
                        r.stderr.strip().splitlines() or ["could not take ownership"]
                    )[-1]
                }
            )
        )
        return 1
    print(json.dumps({"ok": True, "path": points[0]}))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: disks.py list | relabel DEVICE LABEL | fsck DEVICE | "
            "badblocks DEVICE | health DEVICE | erase-quick DEVICE | "
            "erase-secure DEVICE | format DEVICE FSTYPE [LABEL] | "
            "encrypt DEVICE FSTYPE PASSPHRASE | install-stick DEVICE ISO | "
            "smart-status DEVICE | smart-test DEVICE TYPE",
            file=sys.stderr,
        )
        return 2
    cmd = argv[1]

    if cmd == "list":
        return list_disks()

    if cmd == "relabel":
        if len(argv) < 4:
            print("relabel needs a device and a label", file=sys.stderr)
            return 2
        return relabel(argv[2], argv[3])

    if cmd == "fsck":
        if len(argv) < 3:
            print("fsck needs a device", file=sys.stderr)
            return 2
        return fsck_check(argv[2])

    if cmd == "badblocks":
        if len(argv) < 3:
            print("badblocks needs a device", file=sys.stderr)
            return 2
        return badblocks_scan(argv[2])

    if cmd == "health":
        if len(argv) < 3:
            print("health needs a device", file=sys.stderr)
            return 2
        return check_health(argv[2])

    if cmd == "erase-quick":
        if len(argv) < 3:
            print("erase-quick needs a device", file=sys.stderr)
            return 2
        return erase_quick(argv[2])

    if cmd == "erase-secure":
        if len(argv) < 3:
            print("erase-secure needs a device", file=sys.stderr)
            return 2
        return erase_secure(argv[2])

    if cmd == "format":
        if len(argv) < 4:
            print("format needs a device and fstype", file=sys.stderr)
            return 2
        label = argv[4] if len(argv) > 4 else ""
        return format_disk(argv[2], argv[3], label)

    if cmd == "encrypt":
        if len(argv) < 5:
            print("encrypt needs a device, fstype, and passphrase", file=sys.stderr)
            return 2
        return encrypt_disk(argv[2], argv[3], argv[4])

    if cmd == "install-stick":
        if len(argv) < 4:
            print("install-stick needs a device and ISO path", file=sys.stderr)
            return 2
        return install_stick(argv[2], argv[3])

    if cmd == "smart":
        if len(argv) < 3:
            print("smart needs a device", file=sys.stderr)
            return 2
        return smart_details(argv[2])

    if cmd == "smart-status":
        if len(argv) < 3:
            print("smart-status needs a device", file=sys.stderr)
            return 2
        return smart_status(argv[2])

    if cmd == "smart-test":
        if len(argv) < 4:
            print("smart-test needs a device and a test type", file=sys.stderr)
            return 2
        return smart_test(argv[2], argv[3])

    if cmd == "benchmark":
        if len(argv) < 3:
            print("benchmark needs a device", file=sys.stderr)
            return 2
        return benchmark(argv[2])

    if cmd == "take-ownership":
        if len(argv) < 3:
            print("take-ownership needs a device", file=sys.stderr)
            return 2
        return take_ownership(argv[2])

    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
