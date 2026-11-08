"""Aether: the Omarchy theme-extractor parity, on Matugen (no new extractor).

- Matugen.previewFor runs the same `matugen wall` invocation themeReload
  runs, isolated, so the live palette is untouched until Apply.
- Aether.apply is the cp workaround (matugen only reads the current
  wallpaper file): copy the picture over it, then Matugen.reload().
- Wiring: Ui.aether + closeAll, shell LazyLoader + IPC (themeFromImage),
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


def test_apply_copies_over_the_wallpaper_file_then_reloads():
    t = read("shani/Services/Aether.qml")
    assert "Matugen.reload()" in t, "the same call themeReload makes"
    assert 'cp -- "$1" "$2"' in t, "copy over the wallpaper path first"
    assert "Matugen.previewFor" in t, "extract reuses Matugen"
    assert "Settings.data.adaptivePalette = true" in t, "the regen must be used"
    assert "Settings.data.aetherThemes" in t, "named themes persist in Settings"


def test_no_new_extractor_was_written():
    # only the matugen shell-out may derive colours — no ColorQuantizer or
    # palette maths in the new Aether code
    for rel in ("shani/Services/Aether.qml", "shani/Modules/Aether/AetherPanel.qml"):
        t = read(rel)
        assert "ColorQuantizer" not in t, rel
        assert "hslSaturation" not in t, rel


# ---- panel contract -----------------------------------------------------------

def test_aether_panel_shows_preview_and_the_documented_behaviour():
    t = read("shani/Modules/Aether/AetherPanel.qml")
    assert "PanelWindow" in t and 'WlrLayershell.namespace: "shani-aether"' in t
    assert "Matugen.previewPalette" in t, "the palette Matugen derives"
    assert "Extract palette" in t
    assert "Apply as wallpaper + colours" in t
    assert "Save theme" in t
    assert "(cp)" in t and "themeReload" in t, "the cp behaviour is documented in the UI"
    assert "Browse" in t and "Use last wallpaper" in t
    assert "FileDialog" in t, "pick an image"
    assert "Escape" in t, "the QrView keyboard way"


def test_saved_themes_are_listed():
    t = read("shani/Modules/Aether/AetherPanel.qml")
    assert "Settings.data.aetherThemes" in t
    assert "aetherThemes" in read("shani/Common/Settings.qml")


# ---- registration -------------------------------------------------------------

def test_ui_flag_and_close_all():
    t = read("shani/Common/Ui.qml")
    assert "property bool aether: false" in t
    close_all = t[t.index("function closeAll()"):]
    assert "aether = false" in close_all.split("}")[0]


def test_shell_lazy_loads_panel_and_exposes_ipc():
    t = read("shani/shell.qml")
    assert "import qs.Modules.Aether" in t
    assert "LazyLoader { active: Ui.aether; AetherPanel {} }" in t
    assert "Aether" in t.split("_services")[1].split("]")[0]
    for fn in ("themeFromImage", "aetherOpen", "aetherClose",
               "aetherExtract", "aetherApply", "aetherSaveTheme"):
        assert f"function {fn}(" in t, fn
    for key in ("aetherShown", "aetherImage", "aetherPalette", "aetherThemes"):
        assert key in t, key


def test_cli_aether_group_maps_onto_real_ipc_functions():
    mod = load_cli()
    assert "aether" in mod.GROUPS
    names = {name for name, _, _ in mod.GROUPS["aether"]}
    assert {"theme-from-image", "open", "extract", "apply", "save", "close"} <= names
    for cmd in names:
        assert ("aether", cmd) in mod.IPC_NAMES, cmd
    assert mod.IPC_NAMES[("aether", "theme-from-image")] == "themeFromImage"
    shell = read("shani/shell.qml")
    for name in mod.IPC_NAMES.values():
        if name == "themeFromImage" or name.startswith("aether"):
            assert f"function {name}(" in shell, name
