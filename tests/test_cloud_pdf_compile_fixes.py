"""Static checks for QML compile errors in Cloud and PdfSigner panels.

A shared-control refactor left two stale property writes that stop the
windows from rendering: Accessible.value on a Rectangle and echoMode on
the shared TextField. Both now use the canonical property.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


CLOUD = read("shani/Modules/Cloud/CloudPanel.qml")
PDF = read("shani/Modules/PdfSigner/PdfSignerPanel.qml")


def test_cloud_no_accessible_value_assignment():
    """Accessible.value is not an assignable property; the bad write is gone."""
    assert "Accessible.value:" not in CLOUD


def test_cloud_progressbar_uses_own_value_property():
    """ProgressBar semantics use the object's own 0..1 `value` property."""
    assert "property real value: win.percent(row.modelData)" in CLOUD
    assert "Accessible.role: Accessible.ProgressBar" in CLOUD
    assert 'Accessible.name: Tr.t("Progress of %1").arg(row.modelData.id)' in CLOUD


def test_pdf_no_echomode_assignment():
    """The shared TextField has no echoMode; the stale write is gone."""
    assert "echoMode" not in PDF


def test_pdf_password_uses_secret_and_keeps_at_name():
    """Password field masks via `secret` and keeps its label/accepted handler."""
    assert "secret: true" in PDF
    assert 'placeholder: Tr.t("Password")' in PDF
    assert 'label: Tr.t("Password")' in PDF
    assert "onAccepted: PdfSigner.setPassword(text)" in PDF
