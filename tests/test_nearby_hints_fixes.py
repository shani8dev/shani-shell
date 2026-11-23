"""Static asserts for Nearby and Start Hints gap fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_nearby_device_subtitle_not_inverted():
    text = source("shani/Modules/Nearby/NearbyWindow.qml")
    # When files are pending, the subtitle should show device info, not "choose files first".
    assert (
        'Nearby.pending.length ? [modelData.deviceModel, modelData.ip].filter(x => x).join("  ·  ") : Tr.t("Click to choose files first")'
        in text
    )


def test_nearby_receive_progress_text_direction_aware():
    text = source("shani/Modules/Nearby/NearbyWindow.qml")
    assert 'tr.modelData.direction === "receive"' in text
    assert 'Tr.t("Receiving: %1%")' in text
    assert 'Tr.t("Receiving…")' in text
    # Send path still present.
    assert 'Tr.t("Sending to %1: %2%")' in text


def test_nearby_note_dismissible():
    text = source("shani/Modules/Nearby/NearbyWindow.qml")
    # Note should be clearable by the user.
    assert 'Nearby.note = ""' in text
    assert 'tip: Tr.t("Dismiss")' in text or 'Accessible.name: Tr.t("Dismiss")' in text


def test_nearby_show_received_guards_empty_files():
    text = source("shani/Modules/Nearby/NearbyWindow.qml")
    assert "(tr.modelData.files || []).length > 0" in text


def test_start_hints_have_accessible_name():
    text = source("shani/Modules/Hints/StartHints.qml")
    assert "Accessible.role: Accessible.Pane" in text
    assert "Accessible.name:" in text
