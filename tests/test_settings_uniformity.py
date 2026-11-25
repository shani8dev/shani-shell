"""Static uniformity checks for the Settings pages.

The CRUD pages share one shape: full-width SwitchRows with a hint, a primary
Save button that is gated on and shows the page's busy flag, and an InfoBanner
for the save result (tone ``ok`` or ``error``). A row is a ListRow, never a
hand-rolled Rectangle with a MouseArea and a Text. These checks catch drift
without starting the shell; they deliberately sample the pages that carry
that shape, not the custom grids (SettingsInput, SettingsPage) or the slot
cards (SettingsSystemRestore) where a raw Rectangle is the right widget.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = ROOT / "shani/Modules/Settings"

# Pages whose toggles are full-width settings rows: every SwitchRow owes a hint.
HINT_PAGES = [
    "SettingsDateLanguage.qml",
    "SettingsNetwork.qml",
    "SettingsPowerKeys.qml",
    "SettingsSearch.qml",
    "SettingsSharing.qml",
    "SettingsWindows.qml",
]

# Pages that use a list of tappable rows rather than a bespoke grid/card.
ROW_PAGES = HINT_PAGES + [
    "SettingsJournal.qml",
    "SettingsModules.qml",
    "SettingsPrinters.qml",
    "SettingsSecurity.qml",
]

# (page, button label, busy expression) for every primary/save button whose
# busy state is the shared save feedback. All matching buttons must have both
# `enabled: !...` and `busy: ...`.
SAVE_BUTTONS = [
    ("SettingsDateLanguage.qml", "Save NTP servers", "page.ntpBusy"),
    ("SettingsJournal.qml", "Save", "page.busy"),
    ("SettingsModules.qml", "Save", "page.busy"),
    ("SettingsNetwork.qml", "Save resolved", "page.resolvedBusy"),
    ("SettingsPowerKeys.qml", "Save", "writer.running"),
    ("SettingsSecurity.qml", "Save policy", "page.pwBusy"),
    ("SettingsSecurity.qml", "Save hosts", "page.hostsBusy"),
    ("SettingsSecurity.qml", "Save sudo rules", "page.sudoersBusy"),
    ("SettingsSecurity.qml", "Save faillock", "page.faillockBusy"),
    ("SettingsSecurity.qml", "Save login defaults", "page.loginDefsBusy"),
    ("SettingsSecurity.qml", "Save", "coredumpSet.running"),
    ("SettingsSharing.qml", "Save allow list", "act.running"),
]

# Status notes that used to be raw Text with an ad-hoc accent/danger ternary.
TONE_PAGES = [
    "SettingsDateLanguage.qml",
    "SettingsJournal.qml",
    "SettingsModules.qml",
    "SettingsNetwork.qml",
    "SettingsPowerKeys.qml",
    "SettingsPrinters.qml",
    "SettingsSecurity.qml",
    "SettingsSharing.qml",
    "SettingsSystemRestore.qml",
]


def source(name):
    return (SETTINGS / name).read_text(encoding="utf-8")


def blank_strings(text):
    """Blank string literals so braces inside messages do not end a block."""
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)


def objects(text, kind, blank=True):
    """Yield (line, body) for every `Kind { ... }` block, strings blanked."""
    if blank:
        text = blank_strings(text)
    for match in re.finditer(r"\b" + re.escape(kind) + r"\s*\{", text):
        start = match.end() - 1
        depth = 0
        end = None
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        if end is None:
            continue
        yield text.count("\n", 0, match.start()) + 1, text[start + 1 : end]


def test_settings_pages_exist():
    for name in set(HINT_PAGES + ROW_PAGES + TONE_PAGES):
        assert (SETTINGS / name).is_file(), f"missing Settings page: {name}"


def test_full_width_toggles_have_hints():
    for name in HINT_PAGES:
        text = source(name)
        assert "SwitchRow" in text, f"{name}: no SwitchRow found"
        for line, body in objects(text, "SwitchRow"):
            assert re.search(r"(?<![\w.])hint\s*:", body), (
                f"{name}:{line}: SwitchRow without a hint"
            )


def test_rows_use_the_shared_listrow_widget():
    """A Rectangle with a MouseArea, a Text and a Row/Column is a list row."""
    for name in ROW_PAGES:
        text = source(name)
        assert "import qs.Common" in text, f"{name}: no shared widget import"
        for line, body in objects(text, "Rectangle"):
            looks_like_row = (
                "MouseArea" in body
                and re.search(r"\bText\s*\{", body)
                and re.search(r"\b(Row|RowLayout|Column|ColumnLayout)\s*\{", body)
            )
            assert not looks_like_row, f"{name}:{line}: raw Rectangle used as a row"


def test_save_buttons_are_gated_on_and_show_busy():
    for name, label, busy in SAVE_BUTTONS:
        text = source(name)
        matches = [
            (line, body)
            for line, body in objects(text, "Button", blank=False)
            if f'text: Tr.t("{label}")' in body
        ]
        assert matches, f"{name}: no Save button labelled {label!r}"
        for line, body in matches:
            assert re.search(r"(?<![\w.])enabled\s*:", body), (
                f"{name}:{line}: {label} not gated while busy"
            )
            assert re.search(
                r"(?<![\w.])busy\s*:\s*" + re.escape(busy) + r"\b", body
            ), f"{name}:{line}: {label} has no busy state ({busy})"


def test_status_notes_are_banners_not_coloured_text():
    """A result message is an InfoBanner with a tone, not a Text guessing a
    colour from the message's wording."""
    for name in TONE_PAGES:
        text = source(name)
        for line, body in objects(text, "Text"):
            assert not re.search(r"\.indexOf\(\"saved\"\)\s*\?", body), (
                f"{name}:{line}: status Text still guesses its colour"
            )
        for line, body in objects(text, "InfoBanner"):
            assert re.search(r"(?<![\w.])tone\s*:", body), (
                f"{name}:{line}: InfoBanner without a tone"
            )
            assert not re.search(r"tone\s*:\s*Theme\.", body), (
                f"{name}:{line}: InfoBanner tone must be a named tone, not a colour"
            )
