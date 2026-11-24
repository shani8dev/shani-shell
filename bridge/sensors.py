#!/usr/bin/env python3
"""sensors — hardware readings from the kernel's hwmon tree, for the shell.

The same files the `sensors` command reads, with the stdlib only: no shell, no
root, no packages and no daemon. One JSON array on stdout, shaped for a list of
rows in the System Monitor:

    [{"name": "coretemp", "label": "Package id 0", "value": 54.0,
      "unit": "°C", "type": "temp", "max": 85.0, "crit": 95.0, "level": 0}]

value/max/crit are in display units (°C, V, RPM); max/crit are 0 for classes
with no meaningful limit (fans, voltage without a limit file), and temperature
uses 80/95 °C defaults when the chip advertises none. level is 0 normal,
1 at/above max, 2 at/above crit — the bar's amber/red cue.
SHANI_HWMON_ROOT points at a stand-in tree for tests/dev; it defaults to
/sys/class/hwmon. Anything unreadable is skipped, never an error.
"""

import glob
import json
import os
import re

HWMON_ROOT = os.environ.get("SHANI_HWMON_ROOT", "/sys/class/hwmon")

# sysfs prefix -> (display unit, scale to display units, decimal places)
KINDS = {
    "temp": ("°C", 0.001, 1),  # millidegrees C
    "in": ("V", 0.001, 3),  # millivolts
    "fan": ("RPM", 1, 0),  # revolutions per minute
}
FALLBACK_LABEL = {"temp": "Temperature", "in": "Voltage", "fan": "Fan"}
# Many chips advertise no limit files at all; without a fallback a boiling
# package would still read as normal. Fan and voltage limits are board-specific.
DEFAULT_TEMP_MAX = 80.0
DEFAULT_TEMP_CRIT = 95.0
ATTR_RE = re.compile(r"^(temp|in|fan)(\d+)_input$")


def text(path):
    """First line of a sysfs file, or "" when it is missing/unreadable."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.readline().strip()
    except (OSError, ValueError):
        return ""


def number(path, typ):
    """A scaled reading, or None for a missing/garbage file."""
    raw = text(path)
    if not raw:
        return None
    _, scale, digits = KINDS[typ]
    try:
        value = float(raw.split()[0]) * scale
    except (ValueError, IndexError, OverflowError):
        return None
    return round(value, digits) if digits else int(round(value))


def chip_name(chip):
    return text(os.path.join(chip, "name")) or os.path.basename(chip.rstrip("/"))


def severity(value, high, crit):
    """0 normal, 1 at/above the warning max, 2 at/above the critical limit."""
    if crit > 0 and value >= crit:
        return 2
    if high > 0 and value >= high:
        return 1
    return 0


def read_sensors(root=None):
    """Every readable input in every hwmon*, in chip/type/index order."""
    base = root if root is not None else HWMON_ROOT
    out = []
    try:
        chips = sorted(glob.glob(os.path.join(base, "hwmon*")))
    except OSError:
        return out
    for chip in chips:
        if not os.path.isdir(chip):
            continue
        try:
            entries = sorted(os.listdir(chip))
        except OSError:
            continue
        name = chip_name(chip)
        attrs = []
        for entry in entries:
            m = ATTR_RE.match(entry)
            if m:
                attrs.append(
                    (
                        list(KINDS).index(m.group(1)),
                        int(m.group(2)),
                        entry,
                        m.group(1),
                        m.group(2),
                    )
                )
        for _, n, attr, typ, index in sorted(attrs):
            value = number(os.path.join(chip, attr), typ)
            if value is None:
                continue
            prefix = typ + str(index)
            high = number(os.path.join(chip, prefix + "_max"), typ) or 0
            crit = 0
            if typ == "in":
                crit = number(os.path.join(chip, prefix + "_crit_max"), typ) or 0
                if not crit:
                    crit = number(os.path.join(chip, prefix + "_crit"), typ) or 0
            elif typ == "temp":
                crit = number(os.path.join(chip, prefix + "_crit"), typ) or 0
            if typ == "temp":
                high = high or DEFAULT_TEMP_MAX
                crit = crit or DEFAULT_TEMP_CRIT
            # shortcut: fan *_max/*_min are target/alarm speeds, not danger
            # highs, and undervoltage has no slot in the row shape: neither
            # gets a severity cue. Add a `min` field if those are ever needed.
            out.append(
                {
                    "name": name,
                    "label": text(os.path.join(chip, prefix + "_label"))
                    or (FALLBACK_LABEL[typ] + " " + str(n)),
                    "value": value,
                    "unit": KINDS[typ][0],
                    "type": typ,
                    "max": high,
                    "crit": crit,
                    "level": severity(value, high, crit),
                }
            )
    return out


def main():
    print(json.dumps(read_sensors()))


if __name__ == "__main__":
    main()
