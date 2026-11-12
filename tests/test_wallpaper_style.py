"""WallpaperStyle: the Omarchy theme-extractor parity, on Matugen (no new extractor).

- Matugen.previewFor runs the same `matugen wall` invocation themeReload
  runs, isolated, so the live palette is untouched until Apply.
- WallpaperStyle.apply is the cp workaround (matugen only reads the current
  wallpaper file): copy the picture over it, then Matugen.reload().
- Wiring: Ui.wallpaperStyle + closeAll, shell LazyLoader + IPC (themeFromImage),
  bin/shani `aether` group, and the palette persisted as named themes.
"""
import importlib.machinery
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def load_cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin" / "shani"))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


# ---- reuse, not a new extractor ---------------------------------------------

def test_preview_reuses_the_theme_reload_matugen_call():
    t = read("shani/Common/Matugen.qml")
    assert "function previewFor(" in t
    assert "previewPalette" in t
    # the same command `run` issues, with the explicit image and every flag
    run_cmd = t[t.index('command: ["matugen", "wall"'):]
    for flag in ("--config", "--mode", "--type", "--contrast", "--source-color-index"):
        assert flag in t, flag
        assert flag in run_cmd, flag
    # isolated output, so previewing does not clobber the live palette
    assert "aether-preview.json" in t and "aether-preview.toml" in t
    # the same colour template themeReload renders through
    assert "tplColors" in t and "colors.json.tpl" in t


def test_apply_never_writes_over_a_file_and_points_the_wallpaper_at_the_picture():
    """Apply copied the picture over the current wallpaper's file - often the
    person's own photo, replaced on disk. It sets the wallpaper instead."""
    t = SERVICE.read_text() if "SERVICE" in globals() else (ROOT / "shani/Services/WallpaperStyle.qml").read_text()
    code = "\n".join(l for l in t.splitlines() if not l.strip().startswith("//"))
    assert "cp --" not in code and "cpProc" not in code
    assert "Settings.data.wallpaper = root.image" in code and "Matugen.reload()" in code

def test_no_new_extractor_was_written():
    # only the matugen shell-out may derive colours — no ColorQuantizer or
    # palette maths in the new WallpaperStyle code
    for rel in ("shani/Services/WallpaperStyle.qml", "shani/Modules/Settings/SettingsWallpaperStyle.qml"):
        t = read(rel)
        assert "ColorQuantizer" not in t, rel
        assert "hslSaturation" not in t, rel


# ---- panel contract -----------------------------------------------------------

def test_aether_panel_shows_preview_and_the_documented_behaviour():
    t = read("shani/Modules/Settings/SettingsWallpaperStyle.qml")
    assert "property bool active" in t   # a part of Settings > Personalisation, not a window
    assert "SettingsWallpaperStyle {" in read("shani/Modules/Settings/SettingsPage.qml")
    assert "Matugen.previewPalette" in t, "the palette Matugen derives"
    assert "Extract palette" in t
    assert "Apply as wallpaper + colours" in t
    assert "Save theme" in t
    assert "(cp)" not in t, "nothing in the UI talks of copying over a file"
    assert "Browse" in t and "Use last wallpaper" in t
    assert "FileDialog" in t, "pick an image"


def test_saved_themes_are_listed():
    t = read("shani/Modules/Settings/SettingsWallpaperStyle.qml")
    assert "Settings.data.wallpaperStyleThemes" in t
    assert "wallpaperStyleThemes" in read("shani/Common/Settings.qml")


# ---- registration -------------------------------------------------------------

def test_opening_it_opens_settings_personalisation():
    t = read("shani/Services/WallpaperStyle.qml")
    assert 'Ui.openSettings("personal", "section:colours")' in t
    assert "property bool wallpaperStyle" not in read("shani/Common/Ui.qml")


def test_shell_lazy_loads_panel_and_exposes_ipc():
    t = read("shani/shell.qml")
    assert "WallpaperStyle" in t.split("_services")[1].split("]")[0]
    for fn in ("themeFromImage", "wallpaperStyleOpen", "wallpaperStyleClose",
               "wallpaperStyleExtract", "wallpaperStyleApply", "wallpaperStyleSaveTheme"):
        assert f"function {fn}(" in t, fn
    for key in ("wallpaperStyleShown", "wallpaperStyleImage", "wallpaperStylePalette", "wallpaperStyleThemes"):
        assert key in t, key


def test_cli_aether_group_maps_onto_real_ipc_functions():
    mod = load_cli()
    assert "wallpaper-style" in mod.GROUPS
    names = {name for name, _, _ in mod.GROUPS["wallpaper-style"]}
    assert {"theme-from-image", "open", "extract", "apply", "save", "close"} <= names
    for cmd in names:
        assert ("wallpaper-style", cmd) in mod.IPC_NAMES, cmd
    assert mod.IPC_NAMES[("wallpaper-style", "theme-from-image")] == "themeFromImage"
    shell = read("shani/shell.qml")
    for name in mod.IPC_NAMES.values():
        if name == "themeFromImage" or name.startswith("wallpaperStyle"):
            assert f"function {name}(" in shell, name
