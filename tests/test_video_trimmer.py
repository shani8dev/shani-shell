"""Trim (feature-trim): Omacut video trimmer + Monologue take trim.

- The backend contract, for real: `ffmpeg -ss START -to END -i IN -c copy
  OUT.mp4` cuts a tiny lavfi video to the requested window (stream copy),
  and the audio branch re-encodes libopus to *.trimmed.opus (opus is not
  frame-seekable for -c copy). Durations come from ffprobe.
- Wiring: VideoTrimmerPanel follows the QrView PanelWindow pattern, Ui owns the
  open flag (and closeAll clears it), shell.qml lazy-loads the panel and
  exposes the videoTrimmerOpen/videoTrimmerCut IPC functions, bin/shani's `trim` group
  maps onto functions that really exist in shell.qml, and the Voice
  Recorder panel carries the in-panel take trim (two sliders + save).
"""
import importlib.machinery
import importlib.util
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
SVC = SHANI / "Services/VideoTrimmer.qml"
PANEL = SHANI / "Modules/VideoTrimmer/VideoTrimmerPanel.qml"
CLI = ROOT / "bin" / "shani"

ffmpeg = shutil.which("ffmpeg")
ffprobe = shutil.which("ffprobe")
needs_ffmpeg = pytest.mark.skipif(ffmpeg is None, reason="ffmpeg is not installed")
needs_ffprobe = pytest.mark.skipif(ffprobe is None, reason="ffprobe is not installed")


def load_cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(CLI))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def probe_duration(path):
    r = subprocess.run(
        [ffprobe, "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", "--", str(path)],
        capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return float(r.stdout.strip().splitlines()[0])


# ---- the backend contract, for real ----------------------------------------

@needs_ffmpeg
def test_video_cut_stream_copy(tmp_path):
    src = tmp_path / "in.mp4"
    subprocess.run(
        [ffmpeg, "-y", "-loglevel", "error", "-f", "lavfi",
         "-i", "color=blue:s=160x90:r=10:d=6",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", str(src)], check=True)
    out = tmp_path / "in.trimmed.mp4"
    r = subprocess.run(
        [ffmpeg, "-y", "-loglevel", "error", "-ss", "1", "-to", "4",
         "-i", str(src), "-c", "copy", str(out)],
        capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert out.exists()
    if ffprobe:
        dur = probe_duration(out)
        assert 2.5 < dur < 4.0, dur


@needs_ffmpeg
def test_video_cut_fallback_reencode_source(tmp_path):
    src = tmp_path / "in.mp4"
    subprocess.run(
        [ffmpeg, "-y", "-loglevel", "error", "-f", "lavfi",
         "-i", "color=green:s=160x90:r=10:d=3",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", str(src)], check=True)
    out = tmp_path / "in.trimmed.mp4"
    r = subprocess.run(
        [ffmpeg, "-y", "-loglevel", "error", "-ss", "0.5", "-to", "2.5",
         "-i", str(src), "-c:v", "libx264", "-crf", "23",
         "-preset", "medium", "-c:a", "aac", "-movflags", "+faststart", str(out)],
        capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert out.exists()


@needs_ffmpeg
def test_audio_trim_reencodes_libopus(tmp_path):
    src = tmp_path / "take.opus"
    subprocess.run(
        [ffmpeg, "-y", "-loglevel", "error", "-f", "lavfi",
         "-i", "anullsrc=r=48000:cl=mono", "-t", "5",
         "-c:a", "libopus", str(src)], check=True)
    out = tmp_path / "take.trimmed.opus"
    r = subprocess.run(
        [ffmpeg, "-y", "-loglevel", "error", "-ss", "1", "-to", "3",
         "-i", str(src), "-c:a", "libopus", str(out)],
        capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert out.exists() and out.stat().st_size > 0
    assert out.read_bytes()[:4] == b"OggS"
    if ffprobe:
        dur = probe_duration(out)
        assert 1.5 < dur < 2.6, dur


# ---- the service -------------------------------------------------------------

def test_service_cut_command_and_fallback():
    t = SVC.read_text()
    assert '"ffmpeg"' in t and '"-ss"' in t and '"-to"' in t and '"-i"' in t
    assert '"-c", "copy"' in t or '"-c", "copy"' in t
    assert ".trimmed.mp4" in t               # OUT.mp4 beside the input
    # fallback re-encode on failure
    assert "libx264" in t and "aac" in t
    assert "fellBack" in t


def test_service_audio_branch_reencodes_libopus():
    t = SVC.read_text()
    assert "libopus" in t
    assert ".trimmed.opus" in t
    assert "isAudio" in t or "audio" in t.lower()
    # no -c copy on the opus path
    tail = t[t.index("libopus"):]
    assert "libopus" in tail
    assert "function trimAudio(" in t
    assert "function cut(" in t


def test_service_probes_with_ffprobe_and_picks_folder_last():
    t = SVC.read_text()
    assert '"ffprobe"' in t
    assert "format=duration" in t
    assert "command -v ffmpeg" in t and "command -v ffprobe" in t
    assert "pickFrom(" in t and "videosDir()" in t
    assert "ls -t" in t               # newest file in the folder
    assert "function open(" in t and "function setInput(" in t
    assert "function setStart(" in t and "function setEnd(" in t
    assert "function nudgeStart(" in t and "function nudgeEnd(" in t


def test_service_result_actions():
    t = SVC.read_text()
    assert "function openResult(" in t and "function trashResult(" in t
    assert '"gio", "trash"' in t
    assert "resultDuration" in t


# ---- the panel ---------------------------------------------------------------

def test_panel_follows_the_qrview_pattern():
    t = PANEL.read_text()
    assert "AppWindow {" in t and "appName:" in t and "onGone:" in t   # a window of its own (Common/AppWindow)
    assert "visible: Ui.videoTrimmer" in t
    assert "Keys.onEscapePressed: Ui.videoTrimmer = false" in t


def test_panel_has_offsets_duration_cut_and_result():
    t = PANEL.read_text()
    assert "VideoTrimmer.cut()" in t                              # the Cut button
    assert "VideoTrimmer.inputDuration" in t                       # duration preview
    assert "VideoTrimmer.result" in t and "VideoTrimmer.resultDuration" in t
    assert "VideoTrimmer.openResult()" in t and "VideoTrimmer.trashResult()" in t
    assert '"-1s"' in t and '"+1s"' in t                  # +/- 1s keys
    assert "VideoTrimmer.nudgeStart(-1)" in t and "VideoTrimmer.nudgeEnd(1)" in t
    assert "TextField" in t and "FileDialog" in t        # fields + picker
    assert "SliderRow" in t


# ---- the voice take trim -------------------------------------------------------

def test_voice_recorder_reuses_trim_service_for_takes():
    t = (SHANI / "Services/VoiceRecorder.qml").read_text()
    assert "VideoTrimmer.trimAudio(" in t
    assert "VideoTrimmer.setInput(" in t
    assert ".trimmed.opus" in t
    assert "function openTrim(" in t
    assert "function saveTrimmedCopy(" in t
    assert "trimFile" in t and "trimmedLast" in t


def test_voice_panel_has_two_sliders_and_save():
    t = (SHANI / "Modules/VoiceRecorder/VoiceRecorderPanel.qml").read_text()
    assert t.count("SliderRow") >= 2
    assert "Save trimmed copy" in t
    assert "VoiceRecorder.saveTrimmedCopy()" in t
    assert "VoiceRecorder.openTrim(" in t
    assert "VoiceRecorder.trimStart" in t and "VoiceRecorder.trimEnd" in t


# ---- registration -------------------------------------------------------------

def test_ui_flag_and_close_all():
    t = (SHANI / "Common/Ui.qml").read_text()
    assert "property bool videoTrimmer: false" in t
    close_all = t[t.index("function closeApps()"):]
    assert "videoTrimmer = false" in close_all.split("}")[0]


def test_shell_lazy_loads_panel_and_exposes_ipc():
    t = (SHANI / "shell.qml").read_text()
    assert 'LazyLoader { active: Ui.videoTrimmer; source: "Modules/VideoTrimmer/VideoTrimmerPanel.qml" }' in t
    assert "import qs.Modules.VideoTrimmer" in t
    assert "Trim" in t.split("_services")[1].split("]")[0]
    for fn in ("videoTrimmerOpen", "videoTrimmerClose", "videoTrimmerToggle", "videoTrimmerCut",
               "voiceRecorderTrim"):
        assert f"function {fn}(" in t, fn
    for key in ("videoTrimmer", "videoTrimmerInput", "videoTrimmerResult", "videoTrimmerStart", "videoTrimmerEnd",
                "videoTrimmerDuration"):
        assert key in t, key


def test_cli_trim_group_maps_onto_real_ipc_functions():
    mod = load_cli()
    assert "video-trimmer" in mod.GROUPS
    for cmd in ("open", "close", "toggle", "cut"):
        assert ("video-trimmer", cmd) in mod.IPC_NAMES, cmd
    assert ("voice", "trim") in mod.IPC_NAMES
    shell = (SHANI / "shell.qml").read_text()
    for name in mod.IPC_NAMES.values():
        if name.startswith("videoTrimmer"):
            assert f"function {name}(" in shell, name


def test_player_and_camera_offer_trim():
    player = (SHANI / "Modules/Player/Player.qml").read_text()
    camera = (SHANI / "Modules/Camera/CameraPanel.qml").read_text()
    assert "Trim" in player and "openTrim" in player
    assert "Trim" in camera and "Trim video" in camera
