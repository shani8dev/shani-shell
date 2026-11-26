#!/usr/bin/env python3
"""system_nfs — the NFS exports drop-in, read and staged as plain data.

    system_nfs.py exports                 (no stdin)
    system_nfs.py stage                   (one JSON object on stdin)
    system_nfs.py set                     (one JSON object on stdin)

The file is a drop-in, never /etc/exports itself. Only this grammar is
understood; a line it cannot read whole is reported in "unreadable" and is
never silently rewritten. Stage validates before it builds text; the write
itself goes through the administrator helper via pkexec, with the content and
its digest on stdin and the verb in argv. No content appears in argv, a log or
a file this bridge writes.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys

EXPORTS_FILE = os.environ.get(
    "SHANI_EXPORTS_FILE", "/etc/exports.d/50-shani-shell.exports"
)
PKEXEC = shlex.split(os.environ.get("SHANI_SYSTEM_PKEXEC", "pkexec"))
ADMIN_TOOL = os.environ.get("SHANI_ADMIN_TOOL", "/usr/lib/shani-shell/shani-admin.py")
TIMEOUT = 120

HEADER = "# Managed by this system"

OPTIONS = (
    "ro",
    "rw",
    "sync",
    "async",
    "no_subtree_check",
    "root_squash",
    "no_root_squash",
    "all_squash",
)
RISKY = ("no_root_squash", "all_squash")
EXCLUSIVE = (
    ("ro", "rw"),
    ("sync", "async"),
    ("root_squash", "no_root_squash", "all_squash"),
)

_PATH = re.compile(r"/[A-Za-z0-9._+@-]*(?:/[A-Za-z0-9._+@-]*)*\Z")
_CLIENT = re.compile(
    r"(?:\*"
    r"|@[A-Za-z0-9_][A-Za-z0-9_.-]*"
    r"|[0-9]{1,3}(?:\.[0-9]{1,3}){3}(?:/[0-9]{1,2})?"
    r"|[0-9A-Fa-f]*:[0-9A-Fa-f:.]*"
    r"|[A-Za-z0-9_][A-Za-z0-9_.-]*)\Z"
)
_SPEC = re.compile(r"([^\s()]+)(?:\(([^()]*)\))?")
_FIRST = re.compile(r"\s*(\S+)(?:\s+(.*))?$", re.S)


def order_options(options):
    """Options in the canonical order, with repeats dropped."""
    wanted = set(options)
    return [name for name in OPTIONS if name in wanted]


def conflicting(options):
    """The first two options that contradict each other, or None."""
    picked = set(options)
    for group in EXCLUSIVE:
        present = [name for name in group if name in picked]
        if len(present) > 1:
            return (present[0], present[1])
    return None


def valid_path(path):
    """One absolute token, no quoting and no traversal."""
    return bool(
        isinstance(path, str) and path and ".." not in path and _PATH.match(path)
    )


def valid_client(client):
    """*, @netgroup, IPv4[/prefix], IPv6 or a host name."""
    return bool(isinstance(client, str) and client and _CLIENT.match(client))


def valid_option(name):
    return name in OPTIONS


def _split_comment(line):
    """A trailing '#' comment, split only at a token boundary."""
    for i, ch in enumerate(line):
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i], line[i:]
    return line, ""


def _parse_specs(body):
    """Client specs in a line's body, or None if the body is not readable."""
    specs = []
    at = 0
    while at < len(body):
        if body[at] in " \t":
            at += 1
            continue
        match = _SPEC.match(body, at)
        if match is None:
            return None
        raw = match.group(2)
        options = []
        if raw is not None:
            options = [part.strip() for part in raw.split(",")]
            if any(not name for name in options):
                return None
        specs.append({"client": match.group(1), "options": options})
        at = match.end()
    return specs or None


def parse_export_line(raw):
    """(row, kind) for one line; kind is "row", "keep" or "unreadable"."""
    line = raw.rstrip("\r\n")
    if not line.strip():
        return None, "keep"
    body, _comment = _split_comment(line)
    if not body.strip():
        return None, "keep"
    first = _FIRST.match(body)
    if first is None:
        return None, "unreadable"
    path = first.group(1)
    specs = _parse_specs(first.group(2) or "")
    if specs is None or not valid_path(path):
        return None, "unreadable"
    clients = []
    warnings = []
    for spec in specs:
        if not valid_client(spec["client"]):
            return None, "unreadable"
        if any(not valid_option(name) for name in spec["options"]):
            return None, "unreadable"
        if conflicting(spec["options"]) is not None:
            return None, "unreadable"
        ordered = order_options(spec["options"])
        risk = [name for name in ordered if name in RISKY]
        for name in risk:
            if name not in warnings:
                warnings.append(name)
        clients.append({"client": spec["client"], "options": ordered, "warnings": risk})
    return (
        {
            "path": path,
            "clients": clients,
            "warnings": warnings,
            "raw": line,
            "editable": True,
        },
        "row",
    )


def exports():
    """Read the drop-in. Missing file is empty, not an error."""
    result = {
        "path": EXPORTS_FILE,
        "rows": [],
        "kept": [],
        "unreadable": [],
        "error": "",
    }
    try:
        with open(EXPORTS_FILE, encoding="utf-8", errors="replace") as fh:
            raws = fh.read().splitlines()
    except FileNotFoundError:
        return result
    except OSError as exc:
        result["error"] = f"{EXPORTS_FILE}: {exc.strerror or exc}"
        return result
    for raw in raws:
        row, kind = parse_export_line(raw)
        if kind == "row":
            result["rows"].append(row)
        elif kind == "keep":
            result["kept"].append(raw)
        else:
            result["unreadable"].append(raw)
    return result


def stage(req):
    """Validate the requested rows and build the full drop-in text."""
    rows_in = req.get("rows") or []
    other = req.get("other") or []
    out = {
        "text": "",
        "sha256": "",
        "rows": [],
        "other": [],
        "warnings": [],
        "refuse": False,
        "error": "",
    }

    def refuse(code):
        out["refuse"] = True
        out["error"] = code
        return out

    if not isinstance(rows_in, list) or not isinstance(other, list):
        return refuse("bad_request")
    if not rows_in and req.get("confirm") != "REMOVE ALL":
        return refuse("needsConfirm")

    validated = []
    warnings = []
    for row in rows_in:
        if not isinstance(row, dict):
            return refuse("bad_request")
        path = row.get("path", "")
        if not valid_path(path):
            return refuse("bad_path")
        clients_in = row.get("clients") or []
        if not isinstance(clients_in, list) or not clients_in:
            return refuse("bad_client")
        clients = []
        for client_in in clients_in:
            if not isinstance(client_in, dict):
                return refuse("bad_request")
            client = client_in.get("client", "")
            if not valid_client(client):
                return refuse("bad_client")
            options = list(client_in.get("options") or [])
            if any(not valid_option(name) for name in options):
                return refuse("unknown_option")
            if conflicting(options) is not None:
                return refuse("exclusive_clash")
            ordered = order_options(options)
            risk = [name for name in ordered if name in RISKY]
            for name in risk:
                if name not in warnings:
                    warnings.append(name)
            clients.append({"client": client, "options": ordered})
        validated.append({"path": path, "clients": clients})

    clean_other = []
    for line in other:
        if not isinstance(line, str) or "\n" in line or "\r" in line:
            return refuse("bad_other")
        if line.strip() == HEADER:
            continue
        clean_other.append(line)

    lines = [HEADER]
    for row in validated:
        body = row["path"] + "".join(
            " "
            + client["client"]
            + ("(" + ",".join(client["options"]) + ")" if client["options"] else "")
            for client in row["clients"]
        )
        lines.append(body)
    lines.extend(clean_other)
    text = "\n".join(lines) + "\n"
    out.update(
        text=text,
        sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(),
        rows=validated,
        other=clean_other,
        warnings=warnings,
    )
    return out


def shani_admin_write(verb, payload):
    """The only call to a ShaniOS-only tool here: the helper through pkexec.

    File content and digest travel together on stdin; argv carries only the
    helper path and the verb, so a process listing cannot read an export.
    """
    if not PKEXEC:
        return {"ok": False, "error": "pkexec is not available"}
    cmd = PKEXEC + [ADMIN_TOOL, verb]
    try:
        proc = subprocess.run(
            cmd,
            input=json.dumps(payload).encode("utf-8"),
            capture_output=True,
            timeout=TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)}
    if proc.returncode != 0:
        lines = (proc.stderr or b"").decode("utf-8", "replace").strip().splitlines()
        return {"ok": False, "error": lines[-1] if lines else f"exit {proc.returncode}"}
    data = {}
    try:
        data = json.loads((proc.stdout or b"").decode("utf-8", "replace"))
    except ValueError:
        pass
    if isinstance(data, dict):
        if data.get("ok") is False:
            return {"ok": False, "error": str(data.get("error") or "helper refused")}
        mode = str(data.get("mode", "") or "")
        owner = str(data.get("owner", "") or "")
        return {"ok": True, "error": "", "mode": mode, "owner": owner}
    return {"ok": True, "error": "", "mode": "", "owner": ""}


def set_exports(req):
    """Stage, write through the helper, then read back."""
    staged = stage(req)
    if staged["refuse"] or staged["error"]:
        return {
            "ok": False,
            "error": staged["error"] or "stage_refused",
            "mode": "",
            "owner": "",
            "exports": exports(),
        }
    result = shani_admin_write(
        "nfs-exports-set", {"text": staged["text"], "sha256": staged["sha256"]}
    )
    if not result["ok"]:
        return {
            "ok": False,
            "error": result["error"],
            "mode": "",
            "owner": "",
            "exports": exports(),
        }
    return {
        "ok": True,
        "error": "",
        "mode": result["mode"],
        "owner": result["owner"],
        "exports": exports(),
    }


VERBS = {"exports": lambda req: exports(), "stage": stage, "set": set_exports}


def main(argv):
    if len(argv) != 2 or argv[1] not in VERBS:
        print(json.dumps({"error": "usage: system_nfs.py " + "|".join(VERBS)}))
        return 2
    req = {}
    if argv[1] in ("stage", "set"):
        try:
            req = json.loads(sys.stdin.read(65536) or "{}")
            if not isinstance(req, dict):
                raise ValueError
        except ValueError:
            print(json.dumps({"error": "expected one JSON object on stdin"}))
            return 2
    print(json.dumps(VERBS[argv[1]](req)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
