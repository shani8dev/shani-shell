"""Gaps closed in Photos: a sort-order control, multi-select with batch ops, an
EXIF details panel fed by PhotoMeta, and per-photo ratings/tags. These are QML
surfaces, so the checks read the source: a function and the control that calls
it must both be present, and persistence must go through argv slots, never an
interpolated shell string.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PHOTOS = ROOT / "shani/Modules/Photos/PhotosWindow.qml"
META = ROOT / "shani/Services/PhotoMeta.qml"


def test_sort_order_control_reaches_the_groups():
    t = PHOTOS.read_text(encoding="utf-8")
    assert 'property string sortOrder: "newest"' in t
    for order in ('"newest"', '"oldest"', '"name"'):
        assert order in t, order
    # the sort is applied where groups are built, not hardwired into scan()
    assert 'sortOrder === "oldest"' in t and 'sortOrder === "name"' in t
    assert "for (const p of list)" in t and "group.items.push(p)" in t


def test_multiselect_with_batch_trash_and_album():
    t = PHOTOS.read_text(encoding="utf-8")
    assert "property var selected: []" in t
    assert "function toggleSelect(path)" in t and "function clearSelect()" in t
    assert "function trashSelected()" in t and "Files.trash(paths" in t
    assert "function albumSelected()" in t and "Photos.createAlbum(name" in t
    assert "Qt.ControlModifier | Qt.ShiftModifier" in t  # how tiles are selected
    assert 'Tr.t("%1 selected"' in t and "Add to album" in t and "Move to trash" in t


def test_exif_details_panel_uses_photometa():
    photos = PHOTOS.read_text(encoding="utf-8")
    meta = META.read_text(encoding="utf-8")
    assert (
        "property string detailPath" in photos
        and "property bool detailsShown" in photos
    )
    assert "PhotoMeta.read(win.detailPath)" in photos
    assert "model: PhotoMeta.details" in photos
    # PhotoMeta now reads a full set of tags and exposes an explicit file override
    for tag in (
        "Exif.Photo.FNumber",
        "Exif.Photo.ISOSpeedRatings",
        "Exif.Photo.LensModel",
        "Exif.Photo.ExposureTime",
        "Exif.Photo.FocalLength",
    ):
        assert tag in meta, tag
    assert "property var details: []" in meta and "function read(path)" in meta
    assert "fileOverride" in meta and "-pv" in meta


def test_ratings_and_tags_persist_without_shell_interpolation():
    t = PHOTOS.read_text(encoding="utf-8")
    assert (
        "function setRating(path, stars)" in t and "function setTags(path, tags)" in t
    )
    assert "function ratingOf(path)" in t and "function tagsOf(path)" in t
    assert "metaWriteCode" in t and "metaFile" in t and "shani-photos/meta.json" in t
    # values travel as separate argv slots, not inside the shell/python string
    assert (
        '["python3", "-c", win.metaWriteCode, win.metaFile, JSON.stringify(win.meta)]'
        in t
    )
    # the detail panel draws both
    assert (
        "win.ratingOf(win.detailPath)" in t and "win.setTags(win.detailPath, text)" in t
    )
