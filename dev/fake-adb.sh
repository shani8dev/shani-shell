#!/bin/sh
# adb, for the tests: one phone on USB
[ "$1" = devices ] && printf 'List of devices attached\n0A1B2C3D       device usb:1-2 product:panther model:Pixel_7 device:panther transport_id:1\n\n'
