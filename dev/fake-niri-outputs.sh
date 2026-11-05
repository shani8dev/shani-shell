#!/bin/sh
# Put first on PATH as `niri` in the dev session: everything goes to the real
# niri, except `niri msg -j outputs` while /tmp/fake-monitor exists - then a
# second monitor, HDMI-A-1, is listed beside the nested one (a nested niri has
# one output and cannot be given another). The plug-in tests use it.
REAL=${REAL_NIRI:-/usr/bin/niri}
if [ "$*" = "msg -j outputs" ] && [ -e /tmp/fake-monitor ]; then
    "$REAL" msg -j outputs | python3 -c '
import json, sys
o = json.load(sys.stdin)
o["HDMI-A-1"] = {"name": "HDMI-A-1", "make": "Dell Inc.", "model": "DELL U2723QE", "serial": None,
    "physical_size": [600, 340], "modes": [{"width": 3840, "height": 2160, "refresh_rate": 60000, "is_preferred": True}],
    "current_mode": 0, "is_custom_mode": False, "vrr_supported": False, "vrr_enabled": False,
    "logical": {"x": 1920, "y": 0, "width": 2560, "height": 1440, "scale": 1.5, "transform": "Normal"}}
print(json.dumps(o))'
    exit 0
fi
exec "$REAL" "$@"
