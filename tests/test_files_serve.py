"""bridge/files.py serve: one process answering many requests, each the same as
`files.py <args>` would print; a bad request answered, not the end of it; the
commands that read stdin refused; and stdin is not where a command's own program
reads (gio asking for a password would swallow the next request)."""
import json
import subprocess
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "files.py"


def serve(reqs):
    r = subprocess.run([sys.executable, str(BRIDGE), "serve"], input="".join(json.dumps(x) + "\n" for x in reqs),
                       capture_output=True, text=True, timeout=30)
    return [json.loads(l) for l in r.stdout.splitlines()]


def test_answers_like_separate_runs(tmp_path):
    (tmp_path / "a.txt").write_text("a"); (tmp_path / "sub").mkdir()
    one = subprocess.run([sys.executable, str(BRIDGE), "list", str(tmp_path)], capture_output=True, text=True).stdout.strip()
    out = serve([{"id": 1, "args": ["list", str(tmp_path)]}, {"id": 2, "args": ["mkdir", str(tmp_path / "new")]},
                 {"id": 3, "args": ["list", str(tmp_path)]}])
    assert [o["id"] for o in out] == [1, 2, 3]
    assert out[0]["out"] == one
    assert sorted(e["name"] for e in json.loads(out[2]["out"])["entries"]) == ["a.txt", "new", "sub"]


def test_bad_requests_and_stdin_commands(tmp_path):
    out = serve([{"id": 1, "args": ["nonsense"]}, {"id": 2, "args": ["connect", "smb://x"]}, {"id": 3, "args": ["unlock", "/dev/x"]},
                 {"id": 4, "args": ["free", str(tmp_path)]}])
    assert "unknown command" in json.loads(out[0]["out"])["error"]
    assert "not answered over serve" in json.loads(out[1]["out"])["error"] and "not answered over serve" in json.loads(out[2]["out"])["error"]
    assert "free" in json.loads(out[3]["out"])


def test_a_commands_program_does_not_wait_on_the_requests(tmp_path, monkeypatch):
    """Files keeps the worker's stdin open and sends one request at a time. A
    program a command runs that reads stdin (gio asking for a password) must get
    end-of-file at once, as it did in a process of its own - not hang there until
    the watchdog. gio stands in, reading stdin; `devices` runs it with none given."""
    import select
    fake = tmp_path / "gio"
    fake.write_text("#!/bin/sh\nread -r x\nexit 2\n"); fake.chmod(0o755)
    monkeypatch.setenv("SHANI_GIO", str(fake))
    p = subprocess.Popen([sys.executable, str(BRIDGE), "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        p.stdin.write(json.dumps({"id": 1, "args": ["devices"]}) + "\n"); p.stdin.flush()
        ready, _, _ = select.select([p.stdout], [], [], 5)
        assert ready, "the worker hung on a command's program reading stdin"
        assert json.loads(p.stdout.readline())["id"] == 1
    finally:
        p.kill(); p.wait()
