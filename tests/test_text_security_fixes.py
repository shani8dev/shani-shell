"""Static guards for text-rendering security fixes in Mail and Notifications.

Each test maps to one fix: mail headers must not be RichText, the empty folder
must not lie while loading/searching, and notification bodies must be escaped
and rendered as plain text. Runtime behaviour is not exercised here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIL = (ROOT / "shani/Modules/Mail/MailWindow.qml").read_text(encoding="utf-8")
NOTIF = (ROOT / "shani/Modules/Notifications/NotificationCard.qml").read_text(
    encoding="utf-8"
)


def _block(src, anchor):
    """The QML item/line starting at `anchor`, up to its first closing brace."""
    pos = src.index(anchor)
    return src[pos : src.index("}", pos)]


def test_mail_subject_and_from_are_plain_text():
    # fix 1: untrusted subject/from must not be auto-detected as RichText — an
    # <img> in either could otherwise trigger a remote image load.
    assert "textFormat: Text.PlainText" in _block(MAIL, "text: Mail.subject")
    assert "textFormat: Text.PlainText" in _block(MAIL, "text: Mail.from")


def test_mail_empty_state_ignores_busy_and_reports_search():
    # fix 2: "Nothing in this folder" must not show while a load/search is in
    # flight, and a query with no hits says so instead.
    empty = _block(MAIL, "visible: Mail.messages.length === 0")
    assert "!Mail.busy" in empty
    assert "Mail.query" in empty
    assert "No matches for" in empty


def test_notification_body_is_plain_text_without_html_escaping():
    # fix 3: StyledText honoured <font>/<a>/<b> and ignored elide. With
    # Text.PlainText Qt shows markup literally, so HTML-escaping here would make
    # a body containing "&" display "&amp;" — the body must pass through as-is.
    fn = NOTIF[NOTIF.index("function safeBody") :]
    fn = fn[: fn.index("\n")]
    assert "&amp;" not in fn and "&lt;" not in fn and "&gt;" not in fn
    assert ".replace(" not in fn
    body = _block(NOTIF, 'text: root.hideContent ? "" : root.safeBody')
    assert "textFormat: Text.PlainText" in body
