"""Picasa-style features in Photos: People, Places, timeline, nested tags,
batch rename, collage, smart albums, Auto Organize and a filmstrip.

QML has no runtime here, so wiring is asserted against the source. Each embedded
Python helper (rename / organize / collage / GPS) is compiled and, where it does
not need an external tool, run against a temporary library.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PHOTOS = ROOT / "shani/Modules/Photos/PhotosWindow.qml"


def source():
    return PHOTOS.read_text(encoding="utf-8")


def embedded(name):
    """Return an inline `readonly property string <name>: '…'` as real Python."""
    m = re.search(
        r"readonly property string " + name + r": '((?:[^'\\]|\\.)*)'", source()
    )
    assert m, name
    return m.group(1).replace("\\n", "\n")


def run(code, *args, env=None):
    return subprocess.run(
        [sys.executable, "-c", code, *map(str, args)],
        capture_output=True,
        text=True,
        env=env,
        check=True,
    ).stdout


# ---- wiring ------------------------------------------------------------------


def test_people_view_tags_names_and_has_an_empty_state():
    s = source()
    assert (
        'property string view: "photos"' in s
        and 'property string personFilter: ""' in s
    )
    assert '["people", Tr.t("People")]' in s  # the view chip
    assert "function peopleOf(path)" in s and "function tagPeopleSelected()" in s
    assert (
        "people: win.splitTags(" in s and "saveMeta()" in s
    )  # names persist with ratings
    assert "model: win.people" in s and 'text: modelData.name + " ("' in s
    assert 'Tr.t("No people tagged yet")' in s  # empty state
    assert (
        'personFilter === "" || splitTags(peopleOf(p.path)).indexOf(personFilter)' in s
    )


def test_places_reads_gps_and_degrades_when_no_reader_is_installed():
    s = source()
    code = embedded("gpsCode")
    assert 'shutil.which("exiv2") or shutil.which("exiftool")' in code
    assert "Exif.GPSInfo.GPSLatitude" in code and "GPSLongitudeRef" in code
    assert "function scanPlaces()" in s and "gpsProc.command" in s
    assert "function openSelectedPlace()" in s and "openstreetmap.org/?mlat=" in s
    assert "property bool placesTool: true" in s
    assert 'Tr.t("Location reader not installed")' in s
    assert 'Tr.t("No photos with location")' in s
    assert '["places", Tr.t("Places")]' in s


def test_timeline_scrubber_jumps_and_steps_by_month():
    s = source()
    assert 'property string timelinePeriod: ""' in s
    assert "readonly property var timelinePeriods:" in s
    assert 'return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2)' in s
    assert "function stepTimeline(dir)" in s and "id: scrubRow" in s
    assert "Qt.Key_BracketLeft" in s and "Qt.Key_BracketRight" in s
    assert 'timelinePeriod === "" || monthKey(p.time) === timelinePeriod' in s


def test_keyword_tags_are_nested_and_can_be_added_or_removed():
    s = source()
    assert 'property string tagFilter: ""' in s
    assert 'split(",").map(s => s.trim()).filter(Boolean)' in s
    assert (
        "function addTagSelected(tag)" in s and "function removeTagSelected(tag)" in s
    )
    assert 'placeholderText: Tr.t("Tag, e.g. Family > Kids")' in s
    assert "model: win.allTags" in s
    assert 'tagFilter === "" || splitTags(tagsOf(p.path)).indexOf(tagFilter)' in s
    assert 'Tr.t("No keyword tags yet' in s


def test_batch_rename_pads_hashes_and_remaps_metadata():
    s = source()
    assert (
        "id: renameField" in s
        and 'placeholderText: Tr.t("Pattern, e.g. Venice-2026-###")' in s
    )
    assert (
        "function renameSelected()" in s and "function applyPathMap(map, message)" in s
    )
    code = embedded("renameCode")
    assert 'if ch=="#": n+=1' in code and "str(i).zfill(n)" in code
    assert "os.rename(p,dest)" in code
    # keys follow the files, so ratings/tags/people survive a rename
    assert "m[map[old]] = m[old]; delete m[old]" in s


def test_collage_uses_imagemagick_and_explains_a_missing_tool():
    s = source()
    code = embedded("collageCode")
    for tool in ("montage", "magick", "convert"):
        assert f'shutil.which("{tool}")' in code, tool
    assert '"-geometry","200x200+4+4"' in code
    assert 'r.error === "no tool"' in s
    assert 'Tr.t("Install ImageMagick (montage) to make collages")' in s
    assert "function makeCollage()" in s


def test_smart_albums_are_saved_searches_persisted_as_json():
    s = source()
    assert "property string smartFile:" in s and '"/smart-albums.json"' in s
    assert (
        "function saveSmartAlbum(name)" in s and "function smartMatches(p, name)" in s
    )
    for rule in ("minRating", "favoriteOnly", "fromYear", "tag"):
        assert f"r.{rule}" in s, rule
    assert 'activeSmart === "" || smartMatches(p, activeSmart)' in s
    assert "model: win.smartAlbums" in s and 'Tr.t("No smart albums yet' in s


def test_auto_organize_moves_loose_photos_into_year_month_folders():
    s = source()
    code = embedded("organizeCode")
    assert 'time.strftime("%Y/%m"' in code
    assert "parts[-3].isdigit() and len(parts[-2])==2" in code  # skip already dated
    assert "os.rename(p,dest)" in code
    assert "function autoOrganizeSelected()" in s
    assert 'Tr.t("Organized %1 photo%2 into year/month folders"' in s


def test_filmstrip_and_thumbnail_size_are_persisted():
    s = source()
    assert "property int tileSize: 150" in s and "property bool filmstrip: false" in s
    assert (
        '"/prefs.json"' in s
        and "function savePrefs()" in s
        and "function loadPrefs()" in s
    )
    assert 'icon: "zoom-fit-best"' in s and "onMoved: v =>" in s
    assert "width / win.tileSize" in s
    assert "orientation: ListView.Horizontal" in s and "model: win.shown" in s
    assert "Qt.Key_G" in s and "Qt.Key_Plus" in s


def test_new_controls_have_accessible_names_and_shortcuts():
    s = source()
    # Choice/Button/SliderRow name themselves; the custom bits say it explicitly
    for text in (
        'label: Tr.t("Person name")',
        'label: Tr.t("Keyword tag")',
        'label: Tr.t("Rename pattern")',
        'Accessible.name: Tr.t("Filmstrip photo %1"',
    ):
        assert text in s, text
    for key in ("Qt.Key_P", "Qt.Key_L", "Qt.Key_T", "Qt.ShiftModifier"):
        assert key in s, key
    assert "personField.activeFocus || tagNameField.activeFocus" in s
    assert "onAction: win.scanPlaces()" in s and 'Tr.t("Scan again")' in s


# ---- the embedded helpers really work ----------------------------------------


def test_all_embedded_scripts_compile():
    for name in ("renameCode", "organizeCode", "collageCode", "gpsCode"):
        compile(embedded(name), name, "exec")


def test_rename_helper_pads_and_avoids_collisions(tmp_path):
    for name in ("IMG_0001.JPG", "IMG_0002.JPG"):
        (tmp_path / name).write_bytes(b"x")
    # a pre-existing target forces the -2 suffix
    (tmp_path / "Venice-2026-001.JPG").write_bytes(b"old")
    paths = [str(tmp_path / "IMG_0001.JPG"), str(tmp_path / "IMG_0002.JPG")]
    out = json.loads(run(embedded("renameCode"), "Venice-2026-###", json.dumps(paths)))
    assert out[paths[0]].endswith("Venice-2026-001-2.JPG")
    assert out[paths[1]].endswith("Venice-2026-002.JPG")
    assert (tmp_path / "Venice-2026-001-2.JPG").exists()


def test_organize_helper_moves_only_loose_photos(tmp_path):
    import time

    loose = tmp_path / "loose.jpg"
    loose.write_bytes(b"x")
    stamp = time.mktime((2025, 3, 14, 12, 0, 0, 0, 0, -1))
    os.utime(loose, (stamp, stamp))
    dated = tmp_path / "2025" / "03" / "keep.jpg"
    dated.parent.mkdir(parents=True)
    dated.write_bytes(b"y")
    out = json.loads(
        run(
            embedded("organizeCode"),
            str(tmp_path),
            json.dumps([str(loose), str(dated)]),
        )
    )
    assert out == {str(loose): str(tmp_path / "2025" / "03" / "loose.jpg")}
    assert (tmp_path / "2025" / "03" / "loose.jpg").exists()
    assert str(dated) not in out  # already in a dated folder


def test_gps_and_collage_helpers_report_a_missing_tool(tmp_path):
    bare = {**os.environ, "PATH": str(tmp_path)}  # no exiv2, exiftool or montage
    gps = json.loads(run(embedded("gpsCode"), "[]", env=bare))
    assert gps == {"tool": False, "data": {}}
    collage = json.loads(
        run(embedded("collageCode"), "[]", str(tmp_path / "collage.jpg"), env=bare)
    )
    assert collage == {"ok": False, "error": "no tool"}


def test_gps_dms_parsing_handles_rational_degrees_and_hemispheres():
    code = embedded("gpsCode")
    fns = code[code.index("def num(s):") : code.index("data={}")]
    ns = {}
    exec(fns, ns)  # noqa: S102 - our own inline helper, no external input
    assert abs(ns["dms"]("12 30 0", "N") - 12.5) < 1e-9
    assert abs(ns["dms"]("12 30 0", "S") + 12.5) < 1e-9
    assert abs(ns["dms"]("77 12 1800/100", "W") + 77.205) < 1e-9
    assert ns["dms"]("", "") is None  # a photo without GPS stays unplaced
