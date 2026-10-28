#!/bin/sh
# usage: shot.sh <output.png>
export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-1
sleep 0.4
grim "$1"
identify "$1"
