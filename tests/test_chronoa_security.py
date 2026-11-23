"""Static guards for the pass-20 voice/Chronoa privacy fixes.

Each test maps to one fix from docs/GAPS-RESEARCH.md. Neither needs a running
shell: both fixes are about source shape, and runtime behaviour is unchanged.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/Chronoa/ChronoaPanel.qml").read_text(encoding="utf-8")
DICTATION = (ROOT / "shani/Services/Dictation.qml").read_text(encoding="utf-8")


def _fn(src, name):
    """Body of `function name(...) { ... }`, up to its matching closing brace."""
    pos = src.index("function " + name + "(")
    brace = src.index("{", pos)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[brace : i + 1]
    raise AssertionError(name + ": unbalanced braces")


def _after(src, anchor):
    return src[src.index(anchor) :]


def test_approval_decision_is_semantic_and_fails_closed():
    # The IPC path passes a code, not necessarily an exact option label. The old
    # optionFor() forwarded options[0] (allow) for any unknown code, so
    # `chronoa approve deny` granted "Allow this once".
    fn = _fn(PANEL, "optionFor")
    assert "options[0]" not in fn
    assert "indexOf(decision)" in fn  # exact labels still win
    for token in ("deny", "reject", "cancel", "always", "once"):
        assert token in fn  # codes mapped by meaning
    assert '"deny";' in fn and '? "deny"' in fn  # unknown -> deny, never grant
    assert "options.find" in fn  # pick the matching label
    kind = _fn(PANEL, "optionKind")
    assert kind.index("deny") < kind.index("allow")  # "Never allow" is a denial


def test_dictation_wav_is_deleted_after_stt_and_on_cancel():
    # Raw speech used to sit at a fixed XDG_RUNTIME_DIR path forever. Both exits
    # now route through the rm -f helper (the Captions.qml cleanup pattern).
    drop = _fn(DICTATION, "dropWav")
    assert 'execDetached(["rm", "-f", "--", root.wav])' in drop
    stt = _after(DICTATION, "id: stt")
    stt = stt[stt.index("onExited:") :]
    assert "root.dropWav()" in stt  # done transcribing
    rec = _after(DICTATION, "id: rec")
    rec = rec[rec.index("onExited:") : rec.index("id: stt")]
    assert 'root.phase !== "recording"' in rec
    assert "root.dropWav()" in rec  # cancelled: no STT will read it
