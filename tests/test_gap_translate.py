"""Translate gaps: source language + swap, endpoint status, file/HTML, batch strings."""

import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/translate.py"
WINDOW = (ROOT / "shani/Modules/Translate/TranslateWindow.qml").read_text()


class Model(BaseHTTPRequestHandler):
    asked: list = []

    def reply(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # /v1/models for the status check
        self.reply({"data": []})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Model.asked.append(body["messages"][0]["content"])
        self.reply({"choices": [{"message": {"content": "ANSWER"}}]})

    def log_message(self, *a):
        pass


def run(args, stdin, env):
    return subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        input=stdin,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )


def test_source_prompt_file_html_and_status(tmp_path):
    srv = HTTPServer(("127.0.0.1", 0), Model)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_port}/v1/chat/completions"
    env = dict(os.environ, SHANI_TRANSLATE_URL=url, XDG_CACHE_HOME=str(tmp_path))
    try:
        assert run(["status"], "", env).stdout.count("ok") >= 1
        assert run(["text", "hi", "mr"], "नमस्ते", env).returncode == 0
        assert "from Marathi into Hindi" in Model.asked[-1]
        # old two-argument callers still work
        assert run(["text", "hi"], "hello", env).returncode == 0
        assert "Translate this into Hindi" in Model.asked[-1]
        # HTML tags and entities are stripped before the model sees the text
        html = (
            "<html><script>x()</script><p>Hello <b>world</b> &amp; friends</p></html>"
        )
        assert run(["file", "en", "auto", "--html"], html, env).returncode == 0
        assert "Hello world & friends" in Model.asked[-1]
        assert "<b>" not in Model.asked[-1] and "x()" not in Model.asked[-1]
    finally:
        srv.shutdown()


def test_status_reports_no_model(tmp_path):
    env = dict(os.environ, SHANI_TRANSLATE_URL="http://127.0.0.1:9/v1/chat/completions")
    r = run(["status"], "", env)
    assert r.returncode == 2 and "not running" in r.stdout


def test_window_source_and_swap():
    assert 'property string source: "auto"' in WINDOW
    assert "function swap()" in WINDOW
    assert "source = target" in WINDOW and "target = old" in WINDOW
    assert '[["auto", Tr.t("Auto")]].concat(win.languages)' in WINDOW
    assert "win.swap()" in WINDOW and "exchange-positions" in WINDOW
    assert "win.target, win.source, win.mode" in WINDOW  # source reaches the bridge


def test_window_endpoint_status_ui():
    assert (
        "SHANI_TRANSLATE_URL" in WINDOW
        and "SHANI_TRANSLATE_URL" in (ROOT / "bridge/translate.py").read_text()
    )
    assert "function checkEndpoint()" in WINDOW and '"$2" status' in WINDOW
    assert "id: endpointField" in WINDOW and "win.checkEndpoint()" in WINDOW
    assert "Local model ready" in WINDOW and "Local model not running" in WINDOW


def test_window_file_and_batch_modes():
    assert 'property string mode: "text"' in WINDOW
    assert "function openFile()" in WINDOW and 'mode: "open"' in WINDOW
    assert 'win.mode = /\\.(html?|htm)$/i.test(paths[0]) ? "file" : "text"' in WINDOW
    assert 'python3 "$2" "$3" "$4" "$5" "$6"' in WINDOW  # cmd + lang + source + --html
    assert '"--html" : ""' in WINDOW
    assert 'win.mode === "batch"' in WINDOW and '"$2" strings "$3"' in WINDOW
    assert "Added %1 translations" in WINDOW
