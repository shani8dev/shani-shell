"""Static guards for the pass-21 document-workflow data-loss fixes.

Both fixes change on-disk behaviour that a source check can pin down: a
second PDF save must never overwrite the earlier signed copy, and deleting
a notebook must move its folder to .trash rather than rm -rf it.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SIGNER = ROOT / "shani" / "Services" / "PdfSigner.qml"
NOTES = ROOT / "shani" / "Services" / "QuickNotes.qml"


def test_pdf_signer_signed_copy_name_has_a_timestamp():
    """Re-signing yields a new filename, so the previous file survives."""
    t = SIGNER.read_text(encoding="utf-8")
    body = t[t.index("function pdfSignerPathFor(") : t.index("// ---- open:")]
    assert "Qt.formatDateTime" in body, "output name carries a timestamp"
    assert '" - signed " + stamp + ".pdf"' in body, "timestamp is part of the filename"
    assert '" - signed.pdf")' not in body, "the old fixed-name output is gone"


def test_delete_notebook_moves_folder_to_trash_instead_of_rm_rf():
    """Deleting a notebook is recoverable: its folder goes to .trash."""
    t = NOTES.read_text(encoding="utf-8")
    body = t[t.index("function deleteNotebook(") : t.index("function escapeHtml(")]
    assert "rm -rf" not in body, "no permanent recursive delete"
    assert "root.trashDir" in body, "the folder goes where notes are trashed"
    assert 'root.trashDir + "/notebook-" + n + "-" + stamp' in body, "unique trash name"
    assert '\'mkdir -p "$1" && mv -f -- "$2" "$3"\'' in body, (
        "reuse the note trash move"
    )
