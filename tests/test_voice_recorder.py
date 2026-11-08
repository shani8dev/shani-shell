"""Voice Recorder (feature-voice-recorder): GNOME Sound Recorder parity.

- The backend contract, exercised for real: pw-record --rate 48000
  --channels 1 --format opus writes a valid Ogg Opus file; SIGSTOP freezes
  it (pause), SIGCONT resumes it, SIGINT finalises it (stop keeps the
  file) — the exact script Services/VoiceRecorder.qml runs.
- The level analyser embedded in the service: its Python peak maths, fed
  synthetic f32 samples, prints the peak.
- Wiring: the panel follows the QrView PanelWindow pattern, Ui owns the
  open flag (and closeAll clears it), shell.qml lazy-loads the panel and
  exposes the voiceRecorder* IPC functions, and bin/shani's `voice` group
  maps onto functions that really exist in shell.qml.
"""
import importlib.machinery
import importlib.util
import math
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
SVC = SHANI / "Services/VoiceRecorder.qml"
PANEL = SHANI / "Modules/VoiceRecorder/VoiceRecorderPanel.qml"
CLI = ROOT / "bin" / "shani"

pw_record = shutil.which("pw-record")
needs_pw = pytest.mark.skipif(pw_record is None, reason="pw-record is not installed")


def load_cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(CLI))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


# ---- the backend contract, for real ----------------------------------------

@needs_pw
def test_record_pause_resume_stop_with_pw_record(tmp_path):
    """The QML wrapper script: background pw-record, pid printed, wait."""
    script = (
        'mkdir -p "$1" || exit 1; '
        'pw-record --rate 48000 --channels 1 --format opus "$2" 2>/dev/null & '
        'rp=$!; echo "pid $rp"; wait $rp'
    )
    out = tmp_path / "Voice Recorder"
    f = out / "Voice Recorder 2026-11-08 14-20-05.opus"
    p = subprocess.Popen(["sh", "-c", script, "sh", str(out), str(f)],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    line = p.stdout.readline()
    assert line.startswith("pid "), line
    rp = int(line.split()[1])
    time.sleep(1.2)

    # pause: SIGSTOP freezes the capture — the file stops growing
    import os
    os.kill(rp, signal.SIGSTOP)
    time.sleep(0.3)
    s1 = f.stat().st_size
    time.sleep(1.0)
    assert f.stat().st_size == s1, "a paused recording must not grow"
    # resume: SIGCONT, the file grows again
    os.kill(rp, signal.SIGCONT)
    time.sleep(1.0)
    assert f.stat().st_size > s1, "a resumed recording must grow again"
    # stop: SIGINT finalises the container; the file is kept
    os.kill(rp, signal.SIGINT)
    p.wait(timeout=10)
    assert f.exists() and f.stat().st_size > 0
    assert f.read_bytes()[:4] == b"OggS", "not an Ogg container"
    if shutil.which("ffprobe"):
        r = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "stream=codec_name",
             "-show_entries", "format=duration", "-of", "csv", str(f)],
            capture_output=True, text=True)
        assert "opus" in r.stdout.lower(), r.stdout
        dur = float(r.stdout.strip().split(",")[-1])
        assert dur > 1.0


def _analyser_python():
    t = SVC.read_text()
    m = re.search(r"python3 -u -c \\'(.*?)\\'', \"sh\"\]", t, re.S)
    assert m, "the analyser python is not embedded in the service"
    return m.group(1).replace('\\"', '"')


def test_level_analyser_prints_the_peak():
    code = _analyser_python()
    # 0.2 s of a 0.5-amplitude tone at 48 kHz, then 0.2 s of silence:
    # the analyser prints one peak per ~100 ms window.
    loud = b"".join(struct.pack("<f", 0.5 * math.sin(2 * math.pi * 440 * i / 48000))
                    for i in range(9600))
    quiet = struct.pack("<f", 0.0) * 9600
    r = subprocess.run([sys.executable, "-u", "-c", code], input=loud + quiet,
                       capture_output=True, timeout=30)
    assert r.returncode == 0, r.stderr.decode()
    vals = [float(x) for x in r.stdout.decode().split()]
    assert vals and abs(vals[0] - 0.5) < 0.01, vals
    assert len(vals) >= 3 and vals[-1] < 0.05, vals


# ---- the service ------------------------------------------------------------

def test_service_records_opus_from_the_music_folder():
    t = SVC.read_text()
    assert "pw-record --rate 48000 --channels 1 --format opus" in t
    assert 'XDG_MUSIC_DIR' in t and '"/Voice Recorder"' in t
    assert ".opus" in t
    assert "yyyy-MM-dd hh-mm-ss" in t          # date-stamped names
    assert 'command -v pw-record' in t         # availability probe


def test_service_pause_resume_stop_signals():
    t = SVC.read_text()
    assert '"-STOP"' in t and '"-CONT"' in t and '"-INT"' in t
    assert "function pause(" in t and "function resume(" in t
    assert "function stop(" in t and "function toggle(" in t
    assert 'state === "recording"' in t        # the timer runs only then


def test_service_timer_is_hh_mm_ss_and_level_is_bounded():
    t = SVC.read_text()
    assert 'padStart(2, "0")' in t and t.count('padStart(2, "0")') >= 3
    assert "Math.min(1, v)" in t and "Math.max(0" in t
    assert "--format f32" in t                # the analyser stream


def test_service_list_rename_delete_play():
    t = SVC.read_text()
    assert "ls -t" in t and 'head -100' in t  # newest-first listing
    assert '"gio", "rename"' in t and '"gio", "trash"' in t
    assert ".opus" in t and "cleanName" in t   # rename keeps the extension
    assert "Media.current" in t and "openUri" in t and "xdg-open" in t
    assert "function refresh(" in t and "function play(" in t


# ---- the panel ---------------------------------------------------------------

def test_panel_follows_the_qrview_pattern():
    t = PANEL.read_text()
    assert "PanelWindow" in t
    assert "visible: Ui.voiceRecorder && !Lock.locked" in t
    assert 'WlrLayershell.namespace: "shani-voice-recorder"' in t
    assert "WlrKeyboardFocus.Exclusive" in t
    assert "Keys.onEscapePressed: Ui.voiceRecorder = false" in t
    assert "Theme.scrim" in t and "Glass" in t and "Theme.radiusLarge" in t


def test_panel_has_record_pause_timer_level_and_rows():
    t = PANEL.read_text()
    assert "VoiceRecorder.toggle()" in t                 # big record button
    assert "VoiceRecorder.togglePause()" in t            # pause / resume
    assert "VoiceRecorder.elapsed" in t                  # HH:MM:SS timer
    assert "VoiceRecorder.level" in t                    # input level meter
    assert "VoiceRecorder.recordings" in t               # the file list
    assert "VoiceRecorder.play(" in t
    assert "VoiceRecorder.rename(" in t
    assert "VoiceRecorder.trash(" in t
    assert "No recordings yet" in t                      # the empty state
    assert "TextField" in t                              # inline rename


# ---- registration -------------------------------------------------------------

def test_ui_flag_and_close_all():
    t = (SHANI / "Common/Ui.qml").read_text()
    assert "property bool voiceRecorder: false" in t
    close_all = t[t.index("function closeAll()"):]
    assert "voiceRecorder = false" in close_all.split("}")[0]


def test_shell_lazy_loads_panel_and_exposes_ipc():
    t = (SHANI / "shell.qml").read_text()
    assert "LazyLoader { active: Ui.voiceRecorder; VoiceRecorderPanel {} }" in t
    assert "import qs.Modules.VoiceRecorder" in t
    assert "VoiceRecorder" in t.split("_services")[1].split("]")[0]
    for fn in ("voiceRecorderOpen", "voiceRecorderClose", "voiceRecorderToggle",
               "voiceRecorderRecord", "voiceRecorderPause", "voiceRecorderStop",
               "voiceRecorderPlay"):
        assert f"function {fn}(" in t, fn
    for key in ("voiceRecorder", "voiceRecording", "voiceElapsed", "voiceFiles", "voiceFile"):
        assert key in t, key


def test_cli_voice_group_maps_onto_real_ipc_functions():
    mod = load_cli()
    assert "voice" in mod.GROUPS
    for cmd in ("open", "close", "toggle", "record", "pause", "stop", "play"):
        assert ("voice", cmd) in mod.IPC_NAMES, cmd
    shell = (SHANI / "shell.qml").read_text()
    for name in mod.IPC_NAMES.values():
        if name.startswith("voiceRecorder"):
            assert f"function {name}(" in shell, name
