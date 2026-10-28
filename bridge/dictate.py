#!/usr/bin/env python3
"""dictate — transcribe one recording for the screen keyboard's mic key.

    dictate.py LANGUAGE WAV        prints the transcript on stdout

The engine is Chronoa's own when Chronoa is installed: the same model and
backend its voice uses (`whisper-model` / the installed tier, `stt-backend`),
built by `stt.build_stt` — so dictation and talking to Chronoa never disagree
about which speech model this machine has. Without Chronoa, whisper.cpp's
`whisper-cli` with $SHANI_WHISPER_MODEL or the first ggml model found.

LANGUAGE is the keyboard's: "en", "mr", or an xkb layout's ISO 639 code; it is
handed to the engine so Marathi is heard as Marathi. Unknown -> "auto".
"""

from __future__ import annotations

import glob
import os
import shutil
import array
import math
import re
import subprocess
import sys
import wave

# xkb names languages in ISO 639-2/3; whisper wants ISO 639-1
ISO1 = {
    "eng": "en", "mar": "mr", "hin": "hi", "tam": "ta", "tel": "te", "ben": "bn", "guj": "gu",
    "kan": "kn", "mal": "ml", "pan": "pa", "ori": "or", "ory": "or", "san": "sa", "nep": "ne",
    "urd": "ur", "asm": "as", "rus": "ru", "ukr": "uk", "ara": "ar", "fas": "fa", "per": "fa",
    "heb": "he", "ell": "el", "gre": "el", "tha": "th", "fra": "fr", "fre": "fr", "deu": "de",
    "ger": "de", "spa": "es", "ita": "it", "por": "pt", "nld": "nl", "dut": "nl", "pol": "pl",
    "tur": "tr", "jpn": "ja", "kor": "ko", "zho": "zh", "chi": "zh", "vie": "vi", "ind": "id",
}
CHRONOA_LIB = "/usr/lib/shani-chronoa"
MODEL_GLOBS = [
    os.path.expanduser("~/.local/share/shani-chronoa/models/ggml-*.bin"),
    os.path.expanduser("~/.local/share/whisper/ggml-*.bin"),
    "/usr/share/whisper.cpp/models/ggml-*.bin",
    "/opt/whisper/ggml-*.bin",
]


# near silence (about -50 dBFS): whisper hears "you" or "Thank you." in it, so
# it is not handed to the engine at all — live captions record silence often.
# Judged by the loudest 100 ms, not the whole clip: a short phrase in a long,
# mostly quiet recording is still speech.
SILENCE_RMS = 100


def is_silent(wav: str) -> bool:
    """True for a 16-bit recording with nothing above the noise floor."""
    try:
        with wave.open(wav) as w:
            if w.getsampwidth() != 2:
                return False
            samples = array.array("h", w.readframes(w.getnframes()))
    except (OSError, EOFError, wave.Error):
        return False
    if sys.byteorder == "big":
        samples.byteswap()
    if not samples:
        return True
    step = max(1, w.getframerate() * w.getnchannels() // 10)
    loudest = max(math.sqrt(sum(x * x for x in samples[i:i + step]) / len(samples[i:i + step]))
                  for i in range(0, len(samples), step))
    return loudest < SILENCE_RMS


# whisper marks what is not speech: "[BLANK_AUDIO]", "(speaking in foreign
# language)", "*music*" — not words to type or caption
ANNOTATION = re.compile(r"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*")


def clean(text: str) -> str:
    return " ".join(ANNOTATION.sub(" ", text).split())


def language(code: str) -> str:
    code = (code or "").lower()
    if len(code) == 2:
        return code
    return ISO1.get(code, "auto")


def with_chronoa(lang: str, wav: str) -> str | None:
    if os.environ.get("SHANI_DICTATE_ENGINE") == "whisper-cli" or not os.path.isdir(CHRONOA_LIB):
        return None
    sys.path.insert(0, CHRONOA_LIB)
    try:
        from shani_chronoa import stt
        from shani_chronoa.config import ChronoaConfig
        from shani_chronoa.hardware_profile import HardwareProfile
    except Exception:  # noqa: BLE001 - a broken install falls back, it does not fail dictation
        return None
    config = ChronoaConfig()
    model = config.whisper_model or stt.installed_model(HardwareProfile().get_whisper_model())
    engine = stt.build_stt(model=model, language=lang, backend=config.stt_backend)
    if not engine.is_available():
        return None
    return engine.transcribe(wav)


def with_whisper_cli(lang: str, wav: str) -> str:
    cli = shutil.which("whisper-cli")
    model = os.environ.get("SHANI_WHISPER_MODEL") or next(
        (m for g in MODEL_GLOBS for m in sorted(glob.glob(g))), "")
    if not cli or not model:
        raise SystemExit("no speech model: install shani-chronoa (or whisper-cpp and a ggml model)")
    out = subprocess.run([cli, "-m", model, "-l", lang, "-nt", "-np", "-f", wav],
                         capture_output=True, text=True, timeout=300)
    if out.returncode != 0:
        raise SystemExit(out.stderr.strip()[-300:] or "whisper-cli failed")
    return out.stdout


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    lang, wav = language(argv[1]), argv[2]
    if is_silent(wav):
        print("")
        return 0
    text = with_chronoa(lang, wav)
    if text is None:
        text = with_whisper_cli(lang, wav)
    print(clean(text))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
