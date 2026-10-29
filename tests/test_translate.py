"""bridge/translate.py against a fake local model (the OpenAI chat API llama-server speaks).

The fake answers like a small model can: one good translation, one that hands
the English back, one that loses the %1, one key missing. Only the good one may
reach the cache; a string in the cache is never asked again; no model means
exit 2 and no cache, never a fallback anywhere else.
"""
import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

BRIDGE = Path(__file__).resolve().parents[1] / "bridge" / "translate.py"


class Model(BaseHTTPRequestHandler):
    asked: list = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        prompt = body["messages"][0]["content"]
        Model.asked.append(prompt)
        if "Answer with only the translation" in prompt:
            answer = "शुभ प्रभात"
        else:
            answer = "<think></think>Here you go:\n" + json.dumps({
                "Night light": "रात्रीचा प्रकाश", "Power off": "Power off",
                "volume %1%": "आवाज", "Search": ""}, ensure_ascii=False)
        out = json.dumps({"choices": [{"message": {"content": answer}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *a):
        pass


def run(args, stdin, env):
    return subprocess.run([sys.executable, str(BRIDGE), *args], input=stdin, capture_output=True, text=True, env=env, timeout=30)


def test_only_real_translations_are_cached(tmp_path):
    srv = HTTPServer(("127.0.0.1", 0), Model)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    env = dict(os.environ, SHANI_TRANSLATE_URL=f"http://127.0.0.1:{srv.server_port}/v1/chat/completions",
               XDG_CACHE_HOME=str(tmp_path))
    try:
        wanted = json.dumps(["Night light", "Power off", "volume %1%", "Search", "Missing one"])
        r = run(["strings", "mr"], wanted, env)
        assert r.returncode == 0 and r.stdout.strip() == "1", r.stdout + r.stderr
        cache = json.loads((tmp_path / "shani-shell/i18n/mr.json").read_text())
        assert cache == {"Night light": "रात्रीचा प्रकाश"}
        # brand names and Wi-Fi are named as kept; the language is named
        assert "Marathi" in Model.asked[0] and "Wi-Fi" in Model.asked[0]

        Model.asked.clear()
        r = run(["strings", "mr"], json.dumps(["Night light"]), env)
        assert r.stdout.strip() == "0" and Model.asked == []        # cached: not asked again

        r = run(["text", "mr"], "Good morning", env)
        assert r.returncode == 0 and r.stdout.strip() == "शुभ प्रभात"
    finally:
        srv.shutdown()


def test_no_model_means_no_translation_and_says_so(tmp_path):
    env = dict(os.environ, SHANI_TRANSLATE_URL="http://127.0.0.1:9/v1/chat/completions", XDG_CACHE_HOME=str(tmp_path))
    r = run(["strings", "hi"], json.dumps(["Night light"]), env)
    assert r.returncode == 2 and "nothing was sent elsewhere" in r.stderr
    assert not (tmp_path / "shani-shell").exists()
