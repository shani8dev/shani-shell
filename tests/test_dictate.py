"""dictate.py: silence never reaches the speech engine.

Whisper writes "you" for a silent recording; live captions record a lot of
silence, so the silent check runs first. The real script is run (no engine is
needed: a silent file must come back empty without one).
"""
from __future__ import annotations

import array
import math
import os
import subprocess
import sys
import wave
from pathlib import Path

import dictate

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "dictate.py"


def write(path: Path, samples: list[int]) -> Path:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(array.array("h", samples).tobytes())
    return path


def tone(amplitude: int) -> list[int]:
    return [int(amplitude * math.sin(2 * math.pi * 440 * i / 16000)) for i in range(16000)]


def test_silence_and_hiss_are_silent(tmp_path):
    assert dictate.is_silent(str(write(tmp_path / "zero.wav", [0] * 16000)))
    assert dictate.is_silent(str(write(tmp_path / "hiss.wav", tone(60))))
    assert dictate.is_silent(str(write(tmp_path / "empty.wav", [])))


def test_speech_level_is_not_silent(tmp_path):
    assert not dictate.is_silent(str(write(tmp_path / "voice.wav", tone(3000))))


def test_short_phrase_in_long_quiet_clip_is_not_silent(tmp_path):
    clip = [0] * 16000 * 4
    clip[16000:16000 + 3200] = tone(3000)[:3200]     # 0.2 s of speech in 4 s
    assert not dictate.is_silent(str(write(tmp_path / "phrase.wav", clip)))


def test_annotations_are_not_words():
    assert dictate.clean("[BLANK_AUDIO]") == ""
    assert dictate.clean(" (speaking in foreign language)\n") == ""
    assert dictate.clean("*music* Good morning [laughs] everyone.") == "Good morning everyone."


def test_unreadable_file_is_left_to_the_engine(tmp_path):
    bad = tmp_path / "bad.wav"
    bad.write_bytes(b"not a wav")
    assert not dictate.is_silent(str(bad))


def test_silent_recording_prints_nothing_without_an_engine(tmp_path):
    wav = write(tmp_path / "zero.wav", [0] * 16000)
    env = dict(os.environ, PATH="/nonexistent", SHANI_DICTATE_ENGINE="whisper-cli")
    out = subprocess.run([sys.executable, str(TOOL), "en", str(wav)], capture_output=True, text=True, env=env, timeout=30)
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == ""
