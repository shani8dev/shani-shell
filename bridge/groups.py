#!/usr/bin/env python3
"""groups — feature group memberships (read-only). Changes go through shani-admin.py user-group.

    groups.py list   JSON: {"groups":[{"name","desc","members":[...]}], "people":[...]}
"""

from __future__ import annotations

import grp
import json
import pwd
import sys

# group -> plain description
MANAGED = {
    "sambashare": "Share folders on the network",
    "libvirt": "Run and manage virtual machines",
    "kvm": "Use hardware virtualisation directly",
    "uucp": "Use serial devices (boards, modems)",
    "video": "Reach video devices directly",
    "input": "Read input devices directly",
    "realtime": "Low-latency audio",
    "wireshark": "Capture network traffic without root",
    "docker": "Use Docker without sudo (root-equivalent)",
}


def people():
    out = []
    for p in pwd.getpwall():
        if 1000 <= p.pw_uid < 60000 and not p.pw_shell.endswith(("nologin", "false")):
            out.append(p.pw_name)
    return sorted(out)


def main():
    if len(sys.argv) < 2 or sys.argv[1] != "list":
        print(json.dumps({"error": "usage: groups.py list"})); return 2
    primary = {}
    for p in pwd.getpwall():
        primary.setdefault(p.pw_gid, set()).add(p.pw_name)
    groups = []
    for name, desc in MANAGED.items():
        try:
            g = grp.getgrnam(name)
        except KeyError:
            continue
        members = sorted(set(g.gr_mem) | primary.get(g.gr_gid, set()))
        groups.append({"name": name, "desc": desc, "members": members})
    print(json.dumps({"groups": groups, "people": people()}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
