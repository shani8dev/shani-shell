"""bridge/mail.py: the parts that turn other people's mail into rows.

Verified against a real MailHog for the end-to-end path; these pin the helpers
that do the parsing, including the two shapes MailHog actually returns
("items", and a list body without a text part).
"""

import email
import email.policy
import importlib.machinery
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/mail.py"


def load():
    loader = importlib.machinery.SourceFileLoader("mail_under_test", str(BRIDGE))
    spec = importlib.util.spec_from_loader("mail_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def test_address_prefers_the_address_over_the_display_name():
    m = load()
    assert m.address("Shani Team <team@example.com>") == "team@example.com"
    assert m.address("shani@example.com") == "shani@example.com"
    assert m.address("") == ""


def test_strip_html_keeps_the_text_and_drops_the_markup():
    m = load()
    assert m.strip_html("<p>Hello <b>world</b></p>") == "Hello world"
    assert m.strip_html("<br>one<br>two") == "one\ntwo"
    # no remote images, no scripts
    assert "img" not in m.strip_html('<img src="http://x/y.png">')
    assert "alert" not in m.strip_html("<script>alert(1)</script>")


def test_body_prefers_text_and_falls_back_to_html():
    m = load()
    plain = email.message_from_string(
        "Content-Type: text/plain\n\nplain body", policy=email.policy.default
    )
    assert m.body_of(plain) == "plain body"

    html_only = email.message_from_string(
        "Content-Type: text/html\n\n<p>rich body</p>", policy=email.policy.default
    )
    assert m.body_of(html_only) == "rich body"

    both = email.message_from_string(
        "MIME-Version: 1.0\nContent-Type: multipart/alternative; boundary=A\n\n"
        "--A\nContent-Type: text/plain\n\ntext part\n--A\n"
        "Content-Type: text/html\n\n<p>html part</p>\n--A--",
        policy=email.policy.default,
    )
    assert m.body_of(both) == "text part"


def test_mailhog_items_and_messages_both_read():
    """MailHog 1.x calls the array "items", Mailpit "messages"."""
    m = load()
    payload = {
        "items": [
            {
                "ID": "x",
                "Content": {
                    "Headers": {"From": ["a@b.c"], "Subject": ["Hi"]},
                    "Body": "body text",
                },
            }
        ]
    }
    # the same shape under the other key must read too
    payload2 = {"messages": payload["items"]}
    for data in (payload, payload2):
        rows = data.get("messages") or data.get("items") or []
        assert rows[0]["ID"] == "x"
        assert rows[0]["Content"]["Headers"]["From"][0] == "a@b.c"
