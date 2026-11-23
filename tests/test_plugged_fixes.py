"""Plugged/plugwatch fixes: plain USB drives, braille at the lock screen,
and cancelling stale notification actions when a device is unplugged.

The bridge tests are real unit tests; the QML assertions follow the repo's
static-gap-test pattern (the render harness compiles the QML separately).
"""

import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def load_plugwatch():
    loader = importlib.machinery.SourceFileLoader(
        "plugwatch_fix", str(ROOT / "bridge" / "plugwatch.py")
    )
    mod = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("plugwatch_fix", loader)
    )
    loader.exec_module(mod)
    return mod


def drive_props(**extra):
    p = {
        "SUBSYSTEM": "usb",
        "DEVTYPE": "usb_device",
        "ACTION": "add",
        "ID_VENDOR_FROM_DATABASE": "SanDisk",
        "ID_MODEL_FROM_DATABASE": "Cruzer Blade",
        "ID_SERIAL": "Sandisk_Cruzer_Blade_1234",
        "ID_USB_INTERFACES": ":080650:",
        "DEVNAME": "/dev/bus/usb/001/012",
    }
    p.update(extra)
    return p


def test_bridge_classifies_plain_usb_mass_storage_as_drive():
    """USB interface class 0x08 -> a `drive`, without changing existing kinds."""
    plugwatch = load_plugwatch()
    c = plugwatch.classify(drive_props())
    assert c == ("drive", "SanDisk Cruzer Blade", "Sandisk_Cruzer_Blade_1234")

    # the more specific kinds still win, and an unmatched usb device is still silent
    assert plugwatch.classify(drive_props(ID_MTP_DEVICE="1"))[0] == "phone"
    assert plugwatch.classify(drive_props(ID_GPHOTO2="1"))[0] == "camera"
    assert (
        plugwatch.classify(drive_props(ID_USB_INTERFACES=":0b0000:"))[0] == "cardreader"
    )
    assert plugwatch.classify(drive_props(ID_USB_INTERFACES="")) is None
    # an empty name still gets a usable title
    assert (
        plugwatch.classify(
            drive_props(ID_VENDOR_FROM_DATABASE="", ID_MODEL_FROM_DATABASE="")
        )[1]
        == "USB drive"
    )


def test_bridge_drive_json_schema_is_stable():
    """add/remove lines for a drive keep the exact documented key set."""
    plugwatch = load_plugwatch()
    events = "\n\n".join(
        "\n".join(
            ["KERNEL[1.0] add /devices/x (usb)"] + [f"{k}={v}" for k, v in p.items()]
        )
        for p in (drive_props(), drive_props(ACTION="remove"))
    )
    out = io.StringIO()
    plugwatch.run(io.StringIO(events + "\n\n"), out=out)
    lines = [json.loads(x) for x in out.getvalue().splitlines()]
    assert [x["event"] for x in lines] == ["add", "remove"]
    assert set(lines[0]) == {"event", "kind", "name", "key"}
    assert set(lines[1]) == {"event", "kind", "key"}
    assert lines[0]["kind"] == "drive" and lines[1]["kind"] == "drive"


def test_qml_greets_drive_and_opens_it_in_files():
    """A drive greeting with an action, routed to Files, refreshing Devices."""
    s = read("shani/Services/Plugged.qml")
    assert '"drive": {' in s
    assert 'Tr.t("A USB drive. Its files are in Files.")' in s
    assert '["files", Tr.t("Open in Files")]' in s
    assert 'if (kind === "drive")' in s and 'Files.show("")' in s
    # Files reloads its Devices list off exactly this signal, and `drive` is not
    # in the exclusion list, so the existing bump covers it.
    assert "storageRev++" in s and 'e.kind !== "security-key")' in s
    assert "function onStorageRevChanged()" in read("shani/Services/Files.qml")


def test_qml_arrival_side_effects_run_before_the_greeting_gate():
    """Braille (and the iPhone note) must be applied even when no card is shown."""
    s = read("shani/Services/Plugged.qml")
    body = s[s.index("function greet(") : s.index("// the rest: one sentence")]
    call = "if (!seen[id] && more[kind] && more[kind].arrived)\n            more[kind].arrived(name);"
    gate = "if (seen[id] || !Settings.data.plugGreetings || Lock.locked)"
    assert call in body and gate in body
    assert body.index(call) < body.index(gate)
    assert "m.arrived(name)" not in body
    assert "Settings.data.screenReader = true" in s
    assert "Settings.data.iphoneNoteDone = true" in s


def test_qml_cancels_pending_askers_on_remove():
    """An unplugged device cannot leave a clickable action behind."""
    s = read("shani/Services/Plugged.qml")
    assert "property var askers: ({})" in s
    assert "function forgetAsker(kind, key)" in s
    assert 'if (e.event === "remove")' in s
    assert "root.askers[id].destroy();" in s
    assert "root.forgetAsker(e.kind, e.key);" in s
    assert "a[id] = p;" in s  # each greeting's process is tracked
    assert "root.forgetAsker(proc.kind, proc.key); destroy();" in s
