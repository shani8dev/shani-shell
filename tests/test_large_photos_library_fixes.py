"""A photo library, not a grid of tiles: competitive fixes against GNOME Photos,
Digikam and Apple Photos.

The shell has no QML runtime here, so every behaviour is asserted against the
source that implements it. One test per behaviour; each new branch (persistence,
hashing, shell import script, keyboard state) has at least one assertion.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PHOTOS = ROOT / "shani/Modules/Photos/PhotosWindow.qml"


def source():
    return PHOTOS.read_text(encoding="utf-8")


def test_favourites_persist_and_get_their_own_filter():
    """GNOME Photos / Apple Photos: a heart survives a rescan and can be filtered."""
    s = source()
    assert "function favoriteOf(path)" in s
    assert "function setFavorite(path, fav)" in s
    assert "function toggleFavorite(path)" in s
    # stored in the same per-photo file as ratings, through argv slots
    assert "{ favorite: !!fav }" in s
    assert (
        '["python3", "-c", win.metaWriteCode, win.metaFile, JSON.stringify(win.meta)]'
        in s
    )
    assert '["favorites", Tr.t("Favorites")]' in s
    assert 'filter === "favorites" ? favoriteOf(p.path) : true' in s
    # tile and details both expose the heart; F is the keyboard path
    assert 'icon: win.favoriteOf(tile.modelData.path) ? "starred" : "non-starred"' in s
    assert "event.key === Qt.Key_F) { win.toggleFavorite(at)" in s


def test_rating_floor_and_batch_rating():
    """Digikam's 'four stars and up', applied to a selection in one write."""
    s = source()
    assert "property int minRating: 0" in s
    assert "minRating === 0 || ratingOf(p.path) >= minRating" in s
    assert 'text: modelData + "★+"' in s
    assert "win.minRating = win.minRating === modelData ? 0 : modelData" in s
    assert "function rateSelected(stars)" in s
    assert "{ rating: stars }" in s
    assert 'text: "★".repeat(modelData)' in s  # the batch star row


def test_duplicate_detection_keeps_the_first_copy():
    """Digikam / Apple Photos Duplicates: hash the library, keep one, trash extras."""
    s = source()
    assert "property var duplicatePaths: []" in s
    assert "readonly property string duplicatesCode:" in s
    for needed in (
        "hashlib.sha256()",
        "if d in seen: dup.append(p)",
        "else: seen[d]=p",
        "os.walk(root)",
    ):
        assert needed in s, needed
    assert "function findDuplicates()" in s
    assert '["python3", "-c", win.duplicatesCode, win.pictures]' in s
    assert "function trashDuplicates()" in s
    assert "Files.trash(doomed, r =>" in s  # extras go to the trash, not rm
    assert '["duplicates", Tr.t("Duplicates")]' in s
    assert 'filter === "duplicates" ? duplicatePaths.indexOf(p.path) >= 0 : true' in s
    assert 'win.filter === "duplicates" && win.duplicatePaths.length > 0' in s


def test_folder_navigation_and_grouping():
    """Digikam's folder tree, flattened to chips; a folder is also a group key."""
    s = source()
    assert "property string folderFilter: ''" not in s  # QML uses double quotes here
    assert 'property string folderFilter: ""' in s
    assert "function folderOf(path)" in s
    assert "readonly property var folders:" in s
    assert 'folderOf(p.path).indexOf(folderFilter + "/") === 0' in s
    assert '["folder", Tr.t("Folder")]' in s
    assert 'win.groupBy === "folder" ? (folderOf(p.path) || Tr.t("Pictures"))' in s
    assert 'text: Tr.t("All folders")' in s


def test_full_screen_slideshow_walks_the_filtered_library():
    """Viewer's slideshow walks one folder; ours walks exactly what the grid shows."""
    s = source()
    assert "property bool slideshow: false" in s
    assert "function startSlideshow(path)" in s
    assert "function stopSlideshow()" in s
    assert "function slideNext()" in s and "function slidePrev()" in s
    assert "win.shown[win.slideIndex].path" in s  # the filtered set, not a folder
    assert "onTriggered: win.slideNext()" in s
    assert "id: slideOverlay" in s and "anchors.fill: parent" in s
    for key in ("Escape", "Left", "Right", "Space"):
        assert "event.key === Qt.Key_" + key in s, key
    assert "win.stopSlideshow(); event.accepted = true" in s
    assert "if (win.slideshow)   // the overlay owns the keys while it is up" in s


def test_grid_keyboard_navigation_and_accessibility():
    """KeyFocus already gives Enter/Space/arrows; teach it the grid's columns."""
    s = source()
    assert "columns: monthCol.cols   // Up / Down jump a row of the grid" in s
    assert "Accessible.role: Accessible.Graphic" in s
    assert 'Accessible.name: tile.modelData.path.split("/").pop()' in s
    assert "win.focusPath = tile.modelData.path" in s
    for key in ("Key_S", "Key_F", "Key_C", "Key_R", "Key_O", "Key_D"):
        assert "event.key === Qt." + key in s, key


def test_metadata_actions_copy_reveal_and_open_with():
    """Finder/Nautilus/Digikam: path to clipboard, reveal in Files, open with."""
    s = source()
    assert "function copyPath(path) { if (path) Files.copyPath(path); }" in s
    assert (
        "function reveal(path)" in s
        and 'Files.show(at === 0 ? "/" : p.substring(0, at))' in s
    )
    assert 'Quickshell.execDetached(["gio", "open", "--", path])' in s
    for icon in ('icon: "edit-copy"', 'icon: "folder-open"', 'icon: "system-run"'):
        assert icon in s, icon


def test_missing_pictures_folder_and_contextual_empty_states():
    """An actionable error, and a distinct message for each empty view."""
    s = source()
    assert "property string scanError: ''" not in s
    assert 'property string scanError: ""' in s
    assert 'dirCheck.command = ["test", "-d", win.pictures]' in s
    assert 'Tr.t("Pictures folder not found: %1", win.pictures)' in s
    for title in (
        'Tr.t("No favorites yet")',
        'Tr.t("No duplicates found")',
        'Tr.t("No photos match that search")',
    ):
        assert title in s, title
    assert (
        'actionText: win.scanError !== "" ? Tr.t("Open Files") : Tr.t("Clear filters")'
        in s
    )
    assert "Files.show(win.pictures);" in s


def test_shift_click_range_selection():
    """Finder's shift-click range, anchored on the last plain click."""
    s = source()
    assert "property string focusAnchor: ''" not in s
    assert 'property string focusAnchor: ""' in s
    assert "Qt.ControlModifier | Qt.ShiftModifier" in s  # unchanged modifier path
    assert "mouse.modifiers & Qt.ShiftModifier" in s
    assert "const lo = Math.min(a, b), hi = Math.max(a, b);" in s
    assert "for (let i = lo; i <= hi; i++)" in s


def test_album_writes_are_routed_to_a_real_function():
    """`Photos.createAlbum` had no service singleton behind it."""
    s = source()
    # the album writer lives in a local QtObject helper (QML ids cannot start
    # uppercase; the concurrent wave renamed it photosApi)
    assert "photosApi" in s or "id: Photos" in s
    assert "function createAlbum(name, paths) { win.createAlbum(name, paths); }" in s
    assert "function createAlbum(name, photoPaths)" in s
    # the + Album button passed photo objects; the writer needs paths
    assert "const selected = win.shown.map(p => p.path);" in s


def test_dated_import_is_safe_and_opt_in():
    """Digikam-style dated folders; off by default and never deletes the source."""
    s = source()
    assert "property bool importDated: false" in s
    assert "win.importDated" in s
    assert 'date -r "$f" +%Y/%Y-%m' in s
    assert 'cp -n -- "$f" "$d/$t/"' in s
    # the import script only copies: no source deletion hides a name collision
    import_script = s.split("function importPhotos")[1].split("importer.command")[0]
    assert "rm " not in import_script and "trash" not in import_script
