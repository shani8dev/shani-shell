"""The phone service can be activated by its D-Bus name on an installed system.

The engine was shipped without a user unit or an activation file, so a call
placed from the shell reached no owner. These are the three files that fix it,
checked together: the bus name must be the one the engine owns, the unit must
be the one the activation file names, and the launcher must be able to import
the engine from where the package puts it. The negative controls make a drift
in any one of them a test failure rather than a silent "NameHasNoOwner".
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNIT = ROOT / "data/systemd/shani-phone.service"
DBUS = ROOT / "data/dbus/dev.shani.Shell.Phone.service"
LAUNCHER = ROOT / "bin/shani-phone"
ENGINE = ROOT / "bridge/phone/service.py"


def _ini(path):
    out, section = {}, ""
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            section = line
            out[section] = {}
        elif "=" in line:
            key, value = line.split("=", 1)
            out.setdefault(section, {})[key.strip()] = value.strip()
    return out


def test_bus_name_matches_the_engine_that_owns_it():
    bus_name = re.search(r'^BUS_NAME = "([^"]+)"', ENGINE.read_text(), re.M).group(1)
    unit = _ini(UNIT)
    activation = _ini(DBUS)
    assert unit["[Service]"]["BusName"] == bus_name
    assert activation["[D-BUS Service]"]["Name"] == bus_name
    assert bus_name not in ("dev.shani.Link", ""), "wrong bus: another engine owns it"


def test_activation_file_names_the_unit_and_the_same_launcher():
    unit = _ini(UNIT)
    activation = _ini(DBUS)
    assert activation["[D-BUS Service]"]["SystemdService"] == UNIT.name
    assert unit["[Service]"]["Type"] == "dbus"
    assert activation["[D-BUS Service]"]["Exec"] == unit["[Service]"]["ExecStart"]
    assert activation["[D-BUS Service]"]["Exec"].endswith("/shani-phone")


def test_launcher_imports_the_engine_from_the_package_path():
    text = LAUNCHER.read_text(encoding="utf-8")
    assert "/usr/lib/shani-shell" in text
    assert "from phone.service import main" in text
    assert "phone/service.py" not in text, "the package's module path is phone.service"


def test_launcher_is_executable():
    assert LAUNCHER.stat().st_mode & 0o111, "D-Bus cannot Exec a non-executable file"
