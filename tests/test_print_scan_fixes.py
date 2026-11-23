"""Printer/scanner fixes from the pass-19 research (static wiring checks).

1. Scanner must not hand --format=pdf to scanimage: scan PNG, wrap with the
   repo's pdfform.py topdf (PyMuPDF).
2. A scan must be cancellable and bounded by a watchdog timer.
3. Printing.printFile must refuse non pdf/image/text paths before lp.
4. Add-printer can pass optional username/password through lpadmin/lpoptions.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_pdf_scan_uses_png_then_pdfform_topdf():
    t = read("shani/Modules/Scanner/ScannerPanel.qml")
    assert '["pdf", "PDF"]' in t, "PDF stays a choice in the UI"
    assert 'pdfTool: Quickshell.env("SHANI_PDFFORM_TOOL")' in t
    assert "/usr/lib/shani-shell/pdfform.py" in t
    assert "--format=png" in t, "scanimage gets PNG for a PDF request"
    assert "topdf" in t, "one-page PDF made by the existing PyMuPDF helper"
    assert '".png"' in t or '+ ".png"' in t, "intermediate PNG path"
    assert 'if (format === "pdf")' in t, "PDF scans take the conversion branch"
    cmds = [l for l in t.splitlines() if "'mkdir -p" in l and "scanimage" in l]
    assert len(cmds) == 2 and any("--format=png" in l for l in cmds), (
        "no raw PDF format sent"
    )
    h = read("bridge/pdfform.py")
    assert 'argv[1] == "topdf"' in h and "def topdf" in h


def test_scan_can_be_cancelled_and_times_out():
    t = read("shani/Modules/Scanner/ScannerPanel.qml")
    assert "function stopScan(note)" in t
    assert "scanProc.running = false" in t, "Cancel kills the scanner"
    assert 'Tr.t("Cancel")' in t
    assert "interval: 120000" in t, "120 s watchdog"
    assert "watchdog.restart()" in t and "watchdog.stop()" in t
    assert "onTriggered: win.stopScan" in t
    assert "if (win.cancelled) return;" in t, "a kill must not overwrite the note"
    assert 'Tr.t("The scan took too long and was stopped")' in t


def test_printing_refuses_unprintable_files():
    t = read("shani/Services/Printing.qml")
    assert "import qs.Common" in t, "Tr.t for the refusal message"
    assert "function printable(path)" in t
    allow = t.split("return [", 1)[1].split("].indexOf", 1)[0]
    for ext in ("pdf", "png", "jpg", "txt", "md"):
        assert '"' + ext + '"' in allow, ext + " is printable"
    for ext in ("zip", "deb", "iso", "appimage"):
        assert '"' + ext + '"' not in allow, ext + " must be refused"
    assert "if (!printable(path))" in t
    assert 'lastError = Tr.t("This file type cannot be printed")' in t
    assert "return false" in t and '["lp", "--", path]' in t, (
        "lp only for allowed paths"
    )


def test_add_printer_passes_credentials():
    t = read("shani/Modules/Settings/SettingsPrinters.qml")
    assert "function add(name, uri, user, password)" in t
    assert '"auth-info-required=username,password"' in t
    assert '"auth-info=" + a.user + ":" + a.password' in t
    assert "id: userField" in t and "id: passField" in t
    # Common/TextField wraps a TextInput and re-exports it as `secret`, not
    # Qt's echoMode; both spellings are fine as long as the password is hidden
    assert "secret: true" in t or "echoMode: TextInput.Password" in t
    assert "pendingAuth" in t and "authStore.command" in t
    calls = [line for line in t.splitlines() if "page.add(" in line]
    assert len(calls) >= 3, "every add entry point passes the credentials"
    assert all("userField" in line for line in calls), "no caller drops the credentials"
