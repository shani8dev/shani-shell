"""Static wiring checks for the busy indicators and the converter's cancel."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def start_body(rel):
    text = read(rel)
    return text.split("function start(what, args, redraw) {", 1)[1].split("\n    }", 1)[
        0
    ]


def test_mail_sets_busy_in_start():
    # every command goes through start(); finished() is the only place that clears it
    assert "root.busy = true" in start_body("shani/Services/Mail.qml")


def test_feeds_sets_busy_in_start():
    # open/search/add/update all reach start(), so the indicator covers each
    assert "root.busy = true" in start_body("shani/Services/Feeds.qml")


def test_converter_can_cancel_a_working_job():
    text = read("shani/Modules/Converter/ConverterWindow.qml")
    assert "worker.running = false" in text
    assert 'visible: row.modelData.state === "working"' in text
    assert 'Tr.t("Cancel")' in text
