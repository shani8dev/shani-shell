#!/usr/bin/env python3
"""Stands in for mdadm, pvs, vgs, lvs, btrfs, compsize and smartctl
(tests/test_system_disks.py): invoked by basename through symlinks, with fixed,
realistic reports and no writes. SHANI_MDSTAT may point at a fixture file.

Every call is appended to $FAKE_SYSTEM_DISKS/calls as "name args...". Set
FAKE_SYSTEM_DISKS_FAIL to space-separated commands that should fail, optionally
with an argument to match, e.g. "vgs btrfs:usage smartctl:sdb".
"""

import json
import os
import sys

D = os.environ.get("FAKE_SYSTEM_DISKS", "/tmp/fake-system-disks")
os.makedirs(D, exist_ok=True)
prog = os.path.basename(sys.argv[0])
args = sys.argv[1:]
joined = " ".join(args)
with open(os.path.join(D, "calls"), "a") as log:
    log.write(" ".join([prog, *args]) + "\n")


def fails() -> bool:
    for token in os.environ.get("FAKE_SYSTEM_DISKS_FAIL", "").replace(",", " ").split():
        parts = token.split(":", 1)
        if parts[0] == prog and (len(parts) == 1 or parts[1] in joined):
            return True
    return False


def die(msg: str):
    print(msg, file=sys.stderr)
    sys.exit(1)


if fails():
    die("%s: simulated failure" % prog)

if prog == "mdadm":
    if args[:1] != ["--detail"] or len(args) != 2:
        die("mdadm: only --detail DEVICE is supported")
    print(
        """%s:
           Version : 1.2
        Raid Level : raid1
        Array Size : 976630336 (931.51 GiB 1000.07 GB)
      Raid Devices : 2
     Total Devices : 2
             State : clean, degraded
    Active Devices : 1
   Working Devices : 1
    Failed Devices : 1
     Spare Devices : 0"""
        % args[1]
    )

elif prog in ("pvs", "vgs", "lvs"):
    if "--reportformat" not in args:
        die("%s: --reportformat json expected" % prog)
    reports = {
        "pvs": {
            "pv": [
                {"pv_name": "/dev/sda1", "vg_name": "vg0", "pv_size": "9.31G"},
                {"pv_name": "/dev/sdb1", "vg_name": "vg0", "pv_size": "9.31G"},
            ]
        },
        "vgs": {
            "vg": [
                {"vg_name": "vg0", "vg_size": "18.62G", "vg_free": "4.00G"},
            ]
        },
        "lvs": {
            "lv": [
                {
                    "lv_name": "root",
                    "vg_name": "vg0",
                    "lv_size": "10.00G",
                    "lv_attr": "-wi-ao----",
                },
                {
                    "lv_name": "swap",
                    "vg_name": "vg0",
                    "lv_size": "2.00G",
                    "lv_attr": "-wi-ao----",
                },
                {
                    "lv_name": "home",
                    "vg_name": "vg0",
                    "lv_size": "4.62G",
                    "lv_attr": "-wi-ao----",
                },
            ]
        },
    }
    print(json.dumps({"report": [reports[prog]]}))

elif prog == "btrfs":
    if args == ["subvolume", "list", "/"]:
        print("""ID 256 gen 42 top level 5 path @
ID 257 gen 42 top level 5 path @home
ID 258 gen 42 top level 5 path @var
ID 259 gen 42 top level 257 path @home/.snapshots""")
    elif args == ["filesystem", "usage", "/"]:
        print("""Overall:
    Device size:                 100.00GiB
    Device allocated:             42.00GiB
    Device unallocated:           58.00GiB
    Used:                         40.00GiB
    Free (estimated):             57.00GiB""")
    elif args == ["filesystem", "scrub", "status", "/"]:
        print("""UUID: 4d2e1f80-1234-4c56-8a90-abcdef123456
Scrub started:    Wed Nov 25 10:00:00 2026
Status:           finished
Duration:         0:00:09
Total to scrub:   40.00GiB
Rate:             4.44GiB/s
Error summary:    no errors found""")
    else:
        die("btrfs: unknown command")

elif prog == "compsize":
    if args:
        die("compsize: no arguments expected")
    print("""Processed 12345 extents, 5 files, 1 regular files
Type       Perc     Disk Usage   Uncompressed Referenced
TOTAL       64%       1.2G         1.9G         1.9G
none       100%       100M         100M         100M
zlib        60%       1.1G         1.8G         1.8G""")

elif prog == "smartctl":
    if args[:2] != ["-H", "-A"] or len(args) != 3:
        die("smartctl: only -H -A DEVICE is supported")
    dev = os.path.basename(args[2])
    model = "Samsung SSD 980 PRO 1TB" if "nvme" in dev else "WDC WD10EZEX-00BN5A0"
    print(
        """smartctl 7.4 2023-08-01 r5530 [x86_64-linux-6.8.0] (local build)
Copyright (C) 2002-23, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF INFORMATION SECTION ===
Device Model:     %s
Serial Number:    WD-WMC1T0000000
Firmware Version: 80.00A80

=== START OF SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED

SMART Attributes Data Structure revision number: 16
Vendor Specific SMART Attributes with Thresholds:
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always       -       0
194 Temperature_Celsius     0x0022   032   055   000    Old_age   Always       -       32 (Min/Max 20/40)
"""
        % model
    )

else:
    die("unknown tool: " + prog)
