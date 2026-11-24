"""Deep pass: editor font-family choice and its line/column status bar.

Static assertions pin the QML wiring; the pure logic tests mirror the small
line/column and font-list functions so the arithmetic is checked without a
QML runtime.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text(
    encoding="utf-8"
)


def test_font_picker_uses_system_fonts():
    assert "Qt.fontFamilies()" in PANEL
    assert 'icon: "preferences-desktop-font"' in PANEL
    assert "ComboBox" in PANEL
    assert "Monospace (default)" in PANEL


def test_font_choice_persists_without_settings_qml():
    assert "import Quickshell.Io" in PANEL
    assert "JsonAdapter" in PANEL
    assert "writeAdapter()" in PANEL
    assert "text-editor-font.json" in PANEL
    assert "function setFontFamily(f)" in PANEL
    # the editor follows the chosen family, defaulting to the shell's mono font
    assert "font.family: win.fontFamily" in PANEL
    assert "fontFamily: fontPrefs.family || Theme.mono" in PANEL


def test_line_column_status_is_visible():
    assert 'Tr.t("Line") + " "' in PANEL
    assert 'Tr.t("column") + " "' in PANEL
    assert 'Tr.t("lines")' in PANEL
    assert 'Tr.t("words")' in PANEL
    assert 'Tr.t("characters")' in PANEL


def test_insert_datetime_survives_concurrent_work():
    # the first wave's button must not be lost by the font toolbar edit
    assert "function insertDateTime()" in PANEL
    assert 'icon: "entry-calendar"' in PANEL
    assert "Insert date and time" in PANEL


# ---- pure logic -------------------------------------------------------------


def line_col(text, pos):
    """Mirror of the status bar's math in TextEditorPanel.qml (both 1-based)."""
    before = text[: max(0, pos)]
    line = before.count("\n") + 1  # split("\\n").length
    col = len(before) - before.rfind("\n")  # length - lastIndexOf("\\n")
    return line, col


def test_line_col_math():
    assert line_col("", 0) == (1, 1)
    assert line_col("abc", 0) == (1, 1)
    assert line_col("abc", 2) == (1, 3)
    assert line_col("abc", 3) == (1, 4)
    assert line_col("abc\n", 4) == (2, 1)
    assert line_col("abc\ndef", 5) == (2, 2)
    assert line_col("a\nb\nc", 5) == (3, 2)
    assert line_col("a\r\nb", 4) == (2, 2)  # CRLF: the \r stays in line 1
    # a caret past the end is clamped by the substring, as in QML
    assert line_col("a\nb", 99) == (2, 2)


def font_model(families):
    """Mirror of win.fontFamilies: a monospace default then the system fonts."""
    return ["Monospace (default)"] + list(families)


def stored_family(model, index):
    """Index 0 asks for the shell's mono font, persisted as an empty string."""
    return "" if index == 0 else model[index]


def effective_family(stored, mono="JetBrains Mono"):
    """fontFamily: fontPrefs.family || Theme.mono."""
    return stored or mono


def test_font_model_and_default():
    model = font_model(["DejaVu Sans", "Noto Sans"])
    assert model[0] == "Monospace (default)"
    assert stored_family(model, 0) == ""
    assert effective_family(stored_family(model, 0)) == "JetBrains Mono"
    assert effective_family(stored_family(model, 2)) == "Noto Sans"
