"""The file-chooser portal's option mapping: what the shell's picker is told."""

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("portal", ROOT / "bridge/portal.py")
portal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portal)


def test_open_file_maps_filters_and_start_folder():
    opts = portal.options_for(
        "OpenFile",
        "Open a picture",
        {
            "multiple": True,
            "current_folder": bytearray(b"/home/asha/Pictures\0"),
            "filters": [("Pictures", [(0, "*.png"), (0, "*.jpg"), (1, "image/gif")])],
        },
    )
    assert opts["mode"] == "open" and opts["multiple"] is True
    assert opts["folder"] == "/home/asha/Pictures"
    assert set(opts["filters"]) >= {"png", "jpg", "gif"}


def test_save_file_takes_name_and_folder_from_current_file():
    opts = portal.options_for(
        "SaveFile",
        "Save as",
        {
            "current_file": bytearray(b"/home/asha/notes.txt\0"),
            "current_name": "",
        },
    )
    assert opts["mode"] == "save"
    assert opts["folder"] == "/home/asha" and opts["name"] == "notes.txt"


def test_uris_escape_spaces_and_non_ascii():
    assert portal.uri("/home/asha/My Photos/गणेश.txt") == (
        "file:///home/asha/My%20Photos/%E0%A4%97%E0%A4%A3%E0%A5%87%E0%A4%B6.txt"
    )
