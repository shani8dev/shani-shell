"""bridge/devwatch.py against a scratch /dev: cameras appearing, opened, closed."""
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

BRIDGE = Path(__file__).resolve().parents[1] / "bridge" / "devwatch.py"


def test_events(tmp_path):
    (tmp_path / "video0").touch()
    (tmp_path / "null").touch()
    p = subprocess.Popen([sys.executable, str(BRIDGE)], env=dict(os.environ, DEVWATCH_DIR=str(tmp_path)),
                         stdout=subprocess.PIPE, text=True)
    lines = []
    threading.Thread(target=lambda: [lines.append(x.strip()) for x in p.stdout], daemon=True).start()

    def wait(cond):
        for _ in range(100):
            if cond():
                return True
            time.sleep(0.02)
        return False
    try:
        assert wait(lambda: "ready" in lines)
        open(tmp_path / "null").close()                  # not a camera: nothing
        with open(tmp_path / "video0"):
            assert wait(lambda: "open video0" in lines)
        assert wait(lambda: "close video0" in lines)
        (tmp_path / "video2").touch()                    # plugged in, and then watched
        assert wait(lambda: lines.count("devices") >= 1)
        open(tmp_path / "video2").close()
        assert wait(lambda: "open video2" in lines and "close video2" in lines)
        os.unlink(tmp_path / "video2")                   # unplugged
        assert wait(lambda: lines.count("devices") >= 2)
        assert not any("null" in x for x in lines), lines
    finally:
        p.kill()
        p.wait()
