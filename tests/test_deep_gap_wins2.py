"""More fixes from the second-pass deep gap audit."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text()


def test_trimmer_never_overwrites_a_previous_cut():
    s = read("shani/Services/VideoTrimmer.qml")
    assert "trimmed-" in s and "formatDateTime(new Date()," in s
    assert '".trimmed.mp4"' not in s and '".trimmed.opus"' not in s


def test_camera_picker_and_mic_toggle():
    svc = read("shani/Services/Camera.qml")
    panel = read("shani/Modules/Camera/CameraPanel.qml")
    assert "root.selected >= 0 ? root.selected" in svc
    assert "property bool withAudio" in svc
    assert "const mic = withAudio" in svc
    assert 'Tr.t("Mic")' in panel


def test_weather_wind_and_temperature_curve():
    w = read("shani/Modules/Weather/WeatherWindow.qml")
    assert "modelData.wind" in w
    assert "tempCurve" in w and "Sparkline" in w


def test_editor_word_and_char_count():
    s = read("shani/Modules/TextEditor/TextEditorPanel.qml")
    assert 'Tr.t("words")' in s and 'Tr.t("characters")' in s


def test_calendar_import_and_quick_add():
    s = read("shani/Modules/Calendar/CalendarPanel.qml")
    assert "Agenda.importFile(paths[0])" in s
    assert 'Tr.t("Quick add' in s
    # the parser now anchors relative phrases on the selected day
    assert "_parseNaturalDateTime(entry, selectedDate)" in s
