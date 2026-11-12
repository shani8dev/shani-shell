"""bridge/nearby.py, two of it, on this machine: one finds the other, sends it
files over TLS, the other is asked and accepts - or declines - and what arrives
is what was sent, under a safe name. LocalSend's protocol both ways; a real
phone is not part of this (see docs/GAPS.md)."""
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "nearby.py"
pytestmark = pytest.mark.skipif(not shutil.which("openssl"), reason="openssl is not installed")


class Peer:
    def __init__(self, tmp, name, port, peers=""):
        env = dict(os.environ, XDG_DATA_HOME=str(tmp / name / "data"), SHANI_NEARBY_PORT=str(port), SHANI_NEARBY_ALIAS=name,
                   SHANI_NEARBY_DIR=str(tmp / name / "inbox"), SHANI_NEARBY_PEERS=peers, SHANI_NEARBY_SUBNET="0",
                   SHANI_NEARBY_OFFER_TIMEOUT="8")
        self.p = subprocess.Popen([sys.executable, str(TOOL)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
        self.events = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.ready = self.wait("ready")
        self.inbox = tmp / name / "inbox"

    def _read(self):
        for line in self.p.stdout:
            self.events.put(json.loads(line))

    def say(self, **cmd):
        self.p.stdin.write(json.dumps(cmd) + "\n")
        self.p.stdin.flush()

    def wait(self, event, timeout=15, **match):
        end = time.time() + timeout
        while time.time() < end:
            try:
                e = self.events.get(timeout=end - time.time())
            except queue.Empty:
                break
            if e.get("event") == event and all(e.get(k) == v for k, v in match.items()):
                return e
        raise AssertionError(f"no {event} {match}")

    def close(self):
        self.p.stdin.close()
        self.p.wait(timeout=10)


@pytest.fixture
def pair(tmp_path):
    a = Peer(tmp_path, "Alpha", 53411)
    b = Peer(tmp_path, "Beta", 53412, peers="127.0.0.1:53411")
    a.say(op="visible", on=True)
    assert a.wait("visible")["on"] is True
    yield a, b
    b.close()
    a.close()


def test_found_sent_accepted_and_arrives_whole(tmp_path, pair):
    a, b = pair
    b.say(op="scan")
    dev = b.wait("device", alias="Alpha")
    assert dev["fingerprint"] == a.ready["fingerprint"] and dev["protocol"] == "https"
    one = tmp_path / "photo.jpg"
    one.write_bytes(os.urandom(300_000))
    two = tmp_path / "notes.txt"
    two.write_text("hello")
    b.say(op="send", to=dev["fingerprint"], files=[str(one), str(two)])
    offer = a.wait("offer")
    assert offer["from"] == "Beta" and sorted(f["name"] for f in offer["files"]) == ["notes.txt", "photo.jpg"]
    assert not a.inbox.exists() or not list(a.inbox.iterdir())       # nothing written before the answer
    a.say(op="answer", session=offer["session"], accept=True)
    b.wait("finished", direction="send")
    got = a.wait("finished", direction="receive")
    assert sorted(Path(p).name for p in got["files"]) == ["notes.txt", "photo.jpg"]
    assert (a.inbox / "photo.jpg").read_bytes() == one.read_bytes()


def test_declined_writes_nothing(tmp_path, pair):
    a, b = pair
    b.say(op="scan")
    dev = b.wait("device", alias="Alpha")
    f = tmp_path / "x.bin"
    f.write_bytes(b"x" * 10)
    b.say(op="send", to=dev["fingerprint"], files=[str(f)])
    a.say(op="answer", session=a.wait("offer")["session"], accept=False)
    assert "declined" in b.wait("failed", direction="send")["error"]
    assert not a.inbox.exists() or not list(a.inbox.iterdir())


def test_a_name_cannot_climb_out_of_the_inbox(tmp_path, pair):
    import importlib.util
    spec = importlib.util.spec_from_file_location("nearby", TOOL)
    nearby = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(nearby)
    assert nearby.safe_name("../../.bashrc") == "bashrc"
    assert nearby.safe_name("/etc/passwd") == "passwd"
    assert nearby.safe_name("..\\..\\win.ini") == "win.ini"
    assert nearby.safe_name("") == "file"
    (tmp_path / "in").mkdir()
    (tmp_path / "in" / "a.txt").write_text("1")
    assert nearby.unique(tmp_path / "in", "a.txt").name == "a (2).txt"


def test_not_visible_means_no_one_can_send(tmp_path):
    lone = Peer(tmp_path, "Gamma", 53413, peers="127.0.0.1:53414")
    shut = Peer(tmp_path, "Delta", 53414)         # never made visible
    lone.say(op="scan")
    assert lone.wait("scanned")["count"] == 0
    lone.close()
    shut.close()
