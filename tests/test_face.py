"""bridge/face.py against a stand-in for linux-hello's daemon socket."""
import getpass
import json
import os
import socket
import subprocess
import sys
import threading
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent / "bridge" / "face.py"


def serve(path: str, answer) -> threading.Thread:
    srv = socket.socket(socket.AF_UNIX)
    srv.bind(path)
    srv.listen(4)

    def loop():
        while True:
            try:
                conn, _ = srv.accept()
            except OSError:
                return
            with conn:
                req = json.loads(conn.makefile().readline())
                conn.sendall((json.dumps(answer(req)) + "\n").encode())

    t = threading.Thread(target=loop, daemon=True)
    t.start()
    return t


def run(tmp_path, *args, cameras=" [IR CAMERA]"):
    env = dict(os.environ, SHANI_FACE_SOCK=str(tmp_path / "lh.sock"), SHANI_FACE_CAMERAS=cameras)
    out = subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True, env=env, timeout=30)
    return json.loads(out.stdout)


def test_probe_sees_the_camera_the_service_and_a_saved_face(tmp_path) -> None:
    serve(str(tmp_path / "lh.sock"), lambda req: {"type": "status", "ready": True, "camera_found": True,
                                                  "camera_path": "/dev/video2", "enrolled_users": [getpass.getuser()]})
    assert run(tmp_path, "probe") == {"installed": True, "camera": True, "on": True, "saved": True}


def test_probe_with_the_service_off_says_so(tmp_path) -> None:
    got = run(tmp_path, "probe")             # no socket at all
    assert got["on"] is False and got["saved"] is False and got["camera"] is True


def test_no_infrared_camera_no_face_sign_in(tmp_path) -> None:
    assert run(tmp_path, "probe", cameras="Device: /dev/video0")["camera"] is False


def test_enroll_asks_for_this_user_and_reports_the_views(tmp_path) -> None:
    seen = []
    serve(str(tmp_path / "lh.sock"), lambda req: (seen.append(req), {"type": "enroll", "success": True, "score": 0.9,
                                                                     "total_enrolled": 2, "message": "ok"})[1])
    assert run(tmp_path, "enroll", "left") == {"ok": True, "views": 2, "message": "ok"}
    assert seen == [{"action": "enroll", "username": getpass.getuser(), "label": "left"}]


def test_enroll_refused_is_reported_not_claimed(tmp_path) -> None:
    serve(str(tmp_path / "lh.sock"), lambda req: {"type": "error", "message": "Not allowed"})
    got = run(tmp_path, "enroll", "center")
    assert got["ok"] is False and got["message"] == "Not allowed"
