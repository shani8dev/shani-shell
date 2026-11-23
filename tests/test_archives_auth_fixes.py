"""Small gaps in the Archives / Authenticator windows (static checks: Quickshell
needs a session).

1. one Process is shared by add / remove / scan — a second click must not
   overwrite the first request while it is still in flight,
2. the setup-key form keeps the secret after Cancel (and issuer/account after
   Add), so a stale key reappears the next time the form opens,
3. "No codes yet" flashes while the first list is still running,
4. a typed unlock password survives switching to a different archive,
5. a failed Compress is silent: entries are empty, so the result row at the
   bottom of the window cannot render Archive.error.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUTH = ROOT / "shani/Modules/Authenticator/AuthenticatorWindow.qml"
ARCH = ROOT / "shani/Modules/Archives/ArchivesWindow.qml"


def test_auth_writer_is_serialised():
    qml = AUTH.read_text(encoding="utf-8")

    # Add and Remove share `writer`; both must refuse a second job at once.
    add = qml.split('text: Tr.t("Add")', 1)[1].split("\n                }", 1)[0]
    assert "&& !writer.running" in add
    remove = qml.split("visible: !row.modelData.fromKey", 1)[1].split("onClicked:", 1)[
        0
    ]
    assert "enabled: !writer.running" in remove

    # the secret must still travel on stdin, never in argv
    assert 'writer.payload = args[0] === "add"' in qml
    assert (
        'writer.command = ["python3", win.tool].concat(writer.payload ? [args[0]] : args);'
        in qml
    )


def test_auth_setup_form_is_cleared():
    qml = AUTH.read_text(encoding="utf-8")
    clear = qml.split("function clearForm()", 1)[1].split("\n", 1)[0]
    for field in ("issuer.text", "account.text", "key.text"):
        assert field + ' = ""' in clear

    cancel = qml.split('Tr.t("Enter a setup key")', 1)[1].split("\n", 1)[0]
    assert "if (!win.adding) win.clearForm()" in cancel

    add = qml.split('text: Tr.t("Add")', 1)[1].split("\n                }", 1)[0]
    assert "win.clearForm()" in add
    # the secret is read into the payload before the field is wiped
    assert add.index("win.run(") < add.index("win.clearForm()")


def test_auth_empty_state_waits_for_refresh():
    qml = AUTH.read_text(encoding="utf-8")
    assert "visible: list.count === 0 && !lister.running" in qml


def test_archives_unlock_prompt_is_cleared():
    qml = ARCH.read_text(encoding="utf-8")
    clear = qml.split("function clearPrompt()", 1)[1].split("\n", 1)[0]
    assert 'pw.text = ""' in clear

    # opening another archive drops the half-typed password with it
    assert "win.clearPrompt(); Archive.open(paths[0]);" in qml

    # and so does the prompt going away (unlock, cancel, close)
    conn = qml.split("Connections { target: Archive", 1)[1].split("\n", 1)[0]
    assert "pw.forceActiveFocus()" in conn
    assert "else win.clearPrompt()" in conn


def test_archives_compress_errors_are_shown():
    qml = ARCH.read_text(encoding="utf-8")
    compress = qml.split("// ---- Compress", 1)[1].split("// ---- what is inside", 1)[0]
    err = compress.split('visible: Archive.error !== ""', 1)[1][:250]
    assert "text: Archive.error" in err
    assert "color: Theme.danger" in err
    assert "wrapMode: Text.Wrap" in err
    # unlike the result row, this must not depend on entries (empty while creating)
    assert "Archive.entries" not in err
