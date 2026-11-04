#!/usr/bin/env python3
"""launch-app - start an installed app the way its desktop file asks.

  launch-app.py ID [--action NAME] [--gpu auto|discrete|default]
                   [--env K=V ...] [--args "..."] [FILE ...]

Everything the shell starts goes through here, on GLib's desktop-file
launcher (Gio.DesktopAppInfo - what GNOME starts apps with), so the XDG rules
are GLib's: field codes (%f %u %F %U), Path, DBusActivatable, desktop actions,
startup notification. On top of it, what GLib leaves to the desktop:

- Terminal=true: the command in a terminal - $SHANI_TERMINAL (the shell's
  default terminal), else xdg-terminal-exec, else foot.
- The graphics card: --gpu discrete, or the app's own PrefersNonDefaultGPU=true
  (KDE: X-KDE-RunOnDiscreteGpu=true) with --gpu auto, runs it on the card that
  is not the default. Its environment comes from switcheroo-control (the
  card's own variables), else NVIDIA PRIME render offload when the NVIDIA
  driver is loaded, else DRI_PRIME=1 when there are two render nodes. --gpu
  default never moves it.
- --env K=V and --args: the person's own launch options for this app.

Prints one JSON line: {"ok": true, "gpu": "...", "env": {...}, "how": "..."}.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

NVIDIA_OFFLOAD = {"__NV_PRIME_RENDER_OFFLOAD": "1", "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
                  "__VK_LAYER_NV_optimus": "NVIDIA_only", "__NV_PRIME_RENDER_OFFLOAD_PROVIDER": "NVIDIA-G0"}


def switcheroo_other() -> dict | None:
    """The non-default card's environment from switcheroo-control, or None."""
    tool = os.environ.get("SHANI_SWITCHEROOCTL") or shutil.which("switcherooctl")
    if not tool:
        return None
    try:
        out = subprocess.run([tool, "list"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    cards, cur = [], None
    for line in out.splitlines():
        key, _, val = line.strip().partition(":")
        val = val.strip()
        if key == "Device":
            cur = {"default": False, "env": {}}
            cards.append(cur)
        elif cur is not None and key == "Default":
            cur["default"] = val.lower().startswith("yes")
        elif cur is not None and key == "Environment":
            for kv in val.split():
                k, _, v = kv.partition("=")
                if k:
                    cur["env"][k] = v
    other = next((c for c in cards if not c["default"]), None)
    return other["env"] if other and len(cards) > 1 else None


def discrete_env() -> tuple[dict, str]:
    env = switcheroo_other()
    if env:
        return env, "switcheroo-control"
    if Path(os.environ.get("SHANI_NVIDIA_PROC", "/proc/driver/nvidia/version")).exists():
        return dict(NVIDIA_OFFLOAD), "nvidia-prime"
    render = list(Path(os.environ.get("SHANI_DRI_DIR", "/dev/dri")).glob("renderD*"))
    if len(render) > 1:
        return {"DRI_PRIME": "1"}, "dri-prime"
    return {}, "one card"


def terminal_argv() -> list[str]:
    # the terminal the person chose (the shell passes it) first, then the
    # system's choice (xdg-terminal-exec), then foot
    if os.environ.get("SHANI_TERMINAL"):
        return [os.environ["SHANI_TERMINAL"], "-e"]
    if shutil.which("xdg-terminal-exec"):
        return ["xdg-terminal-exec"]
    return ["foot", "-e"]


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 64
    app_id, rest = argv[1], argv[2:]
    action, gpu, extra_env, extra_args, files = "", "auto", {}, [], []
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--action":
            action, i = rest[i + 1], i + 2
        elif a == "--gpu":
            gpu, i = rest[i + 1], i + 2
        elif a == "--env":
            k, _, v = rest[i + 1].partition("=")
            if k:
                extra_env[k] = v
            i += 2
        elif a == "--args":
            extra_args, i = shlex.split(rest[i + 1]), i + 2
        else:
            files.append(rest[i])
            i += 1

    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    info = Gio.DesktopAppInfo.new(app_id if app_id.endswith(".desktop") else app_id + ".desktop")
    if info is None:
        print(json.dumps({"ok": False, "error": f"no app {app_id}"}))
        return 1

    prefers = info.get_boolean("PrefersNonDefaultGPU") or info.get_boolean("X-KDE-RunOnDiscreteGpu")
    env, how = {}, "default card"
    if gpu == "discrete" or (gpu == "auto" and prefers):
        env, how = discrete_env()
    env.update(extra_env)

    ctx = Gio.AppLaunchContext()
    for k, v in env.items():
        ctx.setenv(k, v)
    uris = [Gio.File.new_for_commandline_arg(f).get_uri() for f in files]

    try:
        if info.get_boolean("Terminal") or extra_args:
            # the command line ourselves: a terminal around it, or the person's own arguments
            cmd = info.get_commandline() or ""
            parts = [p for p in shlex.split(cmd) if not (len(p) == 2 and p.startswith("%"))]
            parts += extra_args + files
            if info.get_boolean("Terminal"):
                parts = terminal_argv() + parts
            wd = info.get_string("Path") or None
            subprocess.Popen(parts, env={**os.environ, **env}, cwd=wd, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            how_launched = "terminal" if info.get_boolean("Terminal") else "command"
        elif action:
            info.launch_action(action, ctx)
            how_launched = "action"
        else:
            info.launch_uris(uris, ctx)
            how_launched = "glib"
    except (GLib.Error, OSError) as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        return 1
    print(json.dumps({"ok": True, "gpu": how, "env": env, "how": how_launched}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
