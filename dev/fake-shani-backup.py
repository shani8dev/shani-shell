#!/usr/bin/env python3
"""Stand-in for shani-backup's CLI, with the real parser and --json answers.

The shell's bridge talks to this through SHANI_BACKUP_TOOL in dev/session.sh.
Every call is recorded (SHANI_BACKUP_CALLS); state lives in a JSON file
(SHANI_BACKUP_FAKE_STATE), so a check can seed an error or an empty drive.
Only argparse knows the options: an option the real CLI rejects is rejected
here too, rather than quietly accepted by a shell case statement.
"""

import argparse
import json
import os
import sys
import re

STATE_PATH = os.environ.get("SHANI_BACKUP_FAKE_STATE", "/tmp/shani-backup-fake.json")
CALLS_PATH = os.environ.get("SHANI_BACKUP_CALLS", "/tmp/shani-backup-calls.log")

DEFAULTS = {
    "repository": "/run/media/root/USB",
    "reachable": True,
    "set_up": True,
    "schedule": {"on": True, "time": "21:15"},
    "backups": [
        {
            "id": "ab12cd34",
            "time": "2026-11-26T21:15:03+05:30",
            "paths": ["/root"],
            "size": 12345,
        }
    ],
    "home_snapshots": [
        {
            "name": "daily-2026-11-26",
            "path": "/home/.snapshots/root/daily-2026-11-26",
            "whole": False,
        },
        {
            "name": "manual-2026-11-25_10-00-00",
            "path": "/home/.snapshots/root/manual-2026-11-25_10-00-00",
            "whole": False,
        },
    ],
    "snapshots": ["/home/.snapshots/root/daily-2026-11-26"],
    "restore_test": {
        "ok": True,
        "at": 1764167103,
        "snapshot": "ab12cd34",
        "file": "/root/notes.txt",
    },
    "error": None,
}


def load_state():
    """Defaults with any seeded keys overlaid; a missing file is the default."""
    state = json.loads(json.dumps(DEFAULTS))
    try:
        with open(STATE_PATH) as f:
            seeded = json.load(f)
    except (OSError, ValueError):
        seeded = {}
    for key in (
        "repository",
        "reachable",
        "set_up",
        "backups",
        "home_snapshots",
        "snapshots",
        "restore_test",
        "error",
    ):
        if key in seeded:
            state[key] = seeded[key]
    if isinstance(seeded.get("schedule"), dict):
        state["schedule"].update(seeded["schedule"])
    return state


def save_state(state):
    try:
        parent = os.path.dirname(STATE_PATH)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(STATE_PATH + ".tmp", "w") as f:
            json.dump(state, f)
        os.replace(STATE_PATH + ".tmp", STATE_PATH)
    except OSError:
        pass


def record_call():
    try:
        parent = os.path.dirname(CALLS_PATH)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(CALLS_PATH, "a") as f:
            f.write(" ".join(sys.argv[1:]) + "\n")
    except OSError:
        pass


def build_parser():
    p = argparse.ArgumentParser(description="Shani Backup utility")
    p.add_argument("--version", action="version", version="%(prog)s test")
    sub = p.add_subparsers(dest="command")

    backup = sub.add_parser(
        "backup", help="Back up your home folder to the backup drive (restic)"
    )
    backup.add_argument("source", nargs="?")
    backup.add_argument("--destination")
    backup.add_argument("--scheduled", action="store_true")
    backup.add_argument("--json", action="store_true")

    restore = sub.add_parser("restore", help="Restore a backup into a new folder")
    restore.add_argument("target")
    restore.add_argument("--snapshot", default="latest")
    restore.add_argument("--from", dest="repository")
    restore.add_argument("--json", action="store_true")

    backups = sub.add_parser("backups", help="The backups on the backup drive")
    backups.add_argument("action", nargs="?", choices=["list"], default="list")
    backups.add_argument("--json", action="store_true")

    opn = sub.add_parser("open", help="Open the app")
    opn.add_argument("page", nargs="?", choices=["home", "backups"], default="home")

    snapshot = sub.add_parser("snapshot", help="Manage Btrfs snapshots")
    snap_sub = snapshot.add_subparsers(dest="snapshot_command")
    create = snap_sub.add_parser("create")
    create.add_argument("source")
    create.add_argument("destination")
    create.add_argument("--readonly", action="store_true")
    create.add_argument("--json", action="store_true")
    listing = snap_sub.add_parser("list")
    listing.add_argument("path")
    listing.add_argument("--json", action="store_true")
    delete = snap_sub.add_parser("delete")
    delete.add_argument("snapshot")
    delete.add_argument("--json", action="store_true")

    home = sub.add_parser(
        "home", help="Snapshots of home folders under /home/.snapshots"
    )
    home_sub = home.add_subparsers(dest="home_command")
    h = home_sub.add_parser("snapshot")
    h.add_argument("user", nargs="?")
    h.add_argument("--json", action="store_true")
    h = home_sub.add_parser("list")
    h.add_argument("user", nargs="?")
    h.add_argument("--json", action="store_true")
    h = home_sub.add_parser("daily")
    h.add_argument("--keep", type=int, default=14)
    h.add_argument("--json", action="store_true")
    h = home_sub.add_parser("predeploy")
    h.add_argument("--keep", type=int, default=2)
    h.add_argument("--json", action="store_true")
    h = home_sub.add_parser("remove")
    h.add_argument("name")
    h.add_argument("--user")
    h.add_argument("--json", action="store_true")

    schedule = sub.add_parser("schedule", help="Manage backup schedule")
    schedule.add_argument("--enable", action="store_true")
    schedule.add_argument("--disable", action="store_true")
    schedule.add_argument("--at", metavar="HH:MM")
    return p


def out(payload, ok, as_json):
    """One JSON object, or a human line. Seeded error turns any answer into
    ok:false with the backend's own error, exactly as cli.py's _json_out."""
    error = payload.get("_error")
    payload.pop("_error", None)
    if error:
        ok = False
        payload["ok"] = False
        payload["error"] = error
    if as_json:
        print(json.dumps(payload))
    elif error:
        print("Error: " + error)
    return 0 if ok else 1


def main():
    record_call()
    state = load_state()
    args = build_parser().parse_args()
    cmd = args.command
    as_json = getattr(args, "json", False)
    error = state.get("error")

    if cmd == "backup":
        payload = {
            "ok": True,
            "snapshot": "ab12cd34",
            "restore_test": {"ok": True, "detail": "/root/notes.txt"},
            "_error": error,
        }
        if not error:
            if not state["backups"]:
                state["backups"].append(dict(DEFAULTS["backups"][0]))
            save_state(state)
        if as_json:
            return out(payload, True, True)
        if error:
            return out(payload, True, False)
        for pct, name in (
            (12, "/root/notes.txt"),
            (58, "/root/pictures/photo.jpg"),
            (100, "/root/notes.txt"),
        ):
            print(f"\r{pct:3d}%  {name[-60:]:60}", end="", flush=True)
        print()
        print("Backed up: ab12cd34")
        print("Restore test: restored /root/notes.txt")
        return 0

    if cmd == "restore":
        payload = {"ok": True, "target": args.target, "_error": error}
        if not error:
            save_state(state)
        if as_json:
            return out(payload, True, True)
        if error:
            return out(payload, True, False)
        print(f"Restored into {args.target}")
        return 0

    if cmd == "backups":
        payload = {
            "ok": True,
            "repository": state["repository"],
            "reachable": state["reachable"],
            "set_up": state["set_up"],
            "schedule": dict(state["schedule"]),
            "backups": state["backups"],
            "restore_test": dict(state["restore_test"]),
            "_error": error,
        }
        if as_json:
            return out(payload, True, True)
        if error:
            return out(payload, True, False)
        print(f"Backup drive: {state['repository'] or '(none)'}")
        for s in state["backups"]:
            print(f"  {s['id']}  {s.get('time', '')[:16].replace('T', ' ')}")
        return 0

    if cmd == "open":
        print(f"Opened {args.page}")
        return 0

    if cmd == "snapshot":
        if args.snapshot_command == "create":
            payload = {
                "ok": True,
                "source": args.source,
                "destination": args.destination,
                "readonly": args.readonly,
                "_error": error,
            }
            if not error:
                if args.destination not in state["snapshots"]:
                    state["snapshots"].append(args.destination)
                save_state(state)
            if as_json:
                return out(payload, True, True)
            if error:
                return out(payload, True, False)
            print(f"Created snapshot of {args.source} at {args.destination}")
            return 0
        if args.snapshot_command == "list":
            payload = {
                "ok": True,
                "path": args.path,
                "snapshots": state["snapshots"],
                "count": len(state["snapshots"]),
                "elsewhere": 0,
                "note": None,
                "_error": error,
            }
            if error:
                payload["snapshots"] = []
                payload["count"] = None
                payload["elsewhere"] = None
                payload["note"] = None
            if as_json:
                return out(payload, True, True)
            if error:
                return out(payload, True, False)
            print("Snapshots:")
            for snap in state["snapshots"]:
                print(f"  {snap}")
            return 0
        if args.snapshot_command == "delete":
            payload = {"ok": True, "snapshot": args.snapshot, "_error": error}
            if not error:
                state["snapshots"] = [
                    s for s in state["snapshots"] if s != args.snapshot
                ]
                save_state(state)
            if as_json:
                return out(payload, True, True)
            if error:
                return out(payload, True, False)
            print(f"Deleted snapshot {args.snapshot}")
            return 0
        build_parser().parse_args(["snapshot", "--help"])
        return 1

    if cmd == "home":
        user = getattr(args, "user", None) or "root"
        if args.home_command == "list":
            payload = {
                "ok": True,
                "user": user,
                "snapshots": state["home_snapshots"],
                "_error": error,
            }
            if error:
                payload["snapshots"] = []
            if as_json:
                return out(payload, True, True)
            if error:
                return out(payload, True, False)
            for s in state["home_snapshots"]:
                print(f"{s['name']:28} {s['path']}")
            return 0
        if args.home_command in ("daily", "predeploy"):
            detail = f"{args.keep} kept" if args.keep else "all kept"
            payload = {
                "ok": True,
                "results": [{"who": user, "ok": True, "detail": detail}],
                "_error": error,
            }
            if error:
                payload["results"] = [{"who": user, "ok": False, "detail": error}]
            if as_json:
                return out(payload, True, True)
            if error:
                return out(payload, True, False)
            for r in payload["results"]:
                print(f"{r['who']}: {'ok' if r['ok'] else 'FAILED'} {r['detail']}")
            return 0
        if args.home_command == "snapshot":
            name = "manual-2026-11-26_10-00-00"
            path = f"/home/.snapshots/{user}/{name}"
            payload = {"ok": True, "path": path, "_error": error}
            if not error:
                state["home_snapshots"].append(
                    {"name": name, "path": path, "whole": False}
                )
                save_state(state)
            if as_json:
                return out(payload, True, True)
            if error:
                return out(payload, True, False)
            print(path)
            return 0
        if args.home_command == "remove":
            payload = {"ok": True, "_error": error}
            if not error:
                state["home_snapshots"] = [
                    s for s in state["home_snapshots"] if s["name"] != args.name
                ]
                save_state(state)
            if as_json:
                return out(payload, True, True)
            if error:
                return out(payload, True, False)
            print(f"Removed {args.name}")
            return 0
        return 1

    if cmd == "schedule":
        if error:
            return out({"_error": error}, True, False)
        if args.enable or args.disable or args.at:
            on = not args.disable and (args.enable or state["schedule"]["on"])
            if args.at:
                if not (
                    re.fullmatch(r"\d{2}:\d{2}", args.at)
                    and int(args.at[:2]) < 24
                    and int(args.at[3:]) < 60
                ):
                    print(f"Error: {args.at!r} is not a time of day (HH:MM)")
                    return 1
                state["schedule"]["time"] = args.at
            state["schedule"]["on"] = on
            save_state(state)
            print(
                "Daily backup "
                + (f"on, at {state['schedule']['time']}" if on else "off")
            )
            return 0
        print(
            f"Daily backup: {'on' if state['schedule']['on'] else 'off'}, at {state['schedule']['time']}"
        )
        print(f"Backup drive: {state['repository'] or '(none chosen)'}")
        return 0

    build_parser().print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
