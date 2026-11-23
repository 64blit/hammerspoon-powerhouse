"""Speak text offline using a local Kokoro-82M TTS directory.

Called by text_to_speech.lua via hs.task.

Configuration (via CLI flags, process environment, ~/.hammerspoon/.env, or ~/.env):
    KOKORO_TTS_DIR       Path to local Kokoro runtime directory containing:
                         .venv/bin/python, engines.py, specs.py, and
                         weights/Kokoro-82M-bf16/ (or override KOKORO_TTS_MODEL_DIR)
    KOKORO_TTS_MODEL_DIR Optional explicit path to Kokoro model weights directory
    KOKORO_TTS_VOICE     Voice ID (default: bm_george)
    KOKORO_TTS_SPEED     Playback speed multiplier (default: 1.0)

Usage:
    <venv>/bin/python kokoro_speak.py [--dir <path>] [--voice <name>] [--volume 0.0-1.0] < text
    <venv>/bin/python kokoro_speak.py [--dir <path>] --check   # verify paths only

Offline only (HF_HUB_OFFLINE=1). Text is split by sentence; chunk N+1 is
synthesised while chunk N plays via afplay so audio starts quickly.

stdout markers read by Lua: "PLAYING" once the first chunk starts, "DONE" at the end.
Exit codes: 0 ok, 3 model/voice/venv files missing, 4 model load failed,
5 synth/playback failed, 143 stopped (SIGTERM from Lua: active afplay is killed too).
"""
from __future__ import annotations

import os

# Before any HF / transformers import: never touch the network.
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
os.environ.setdefault("TQDM_DISABLE", "1")

import re
import shutil
import signal
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

AFPLAY = "/usr/bin/afplay"
VOLUME_FILE = Path("/tmp/hammerspoon_kokoro_volume")  # Lua writes it; read before each chunk
TMP_PREFIX = "hs-kokoro-tts-"  # Lua's stop pkills "afplay.*hs-kokoro-tts-" as a backstop

MAX_CHUNK = 300  # chars; short first chunk = fast time-to-first-audio
FIRST_CHUNK = 120

_player: subprocess.Popen | None = None
_tmpdir: str | None = None


def _load_dotenv_values() -> dict[str, str]:
    """Read key=value pairs from ~/.hammerspoon/.env then ~/.env (first wins)."""
    values: dict[str, str] = {}
    for env_path in (Path.home() / ".hammerspoon" / ".env", Path.home() / ".env"):
        if not env_path.is_file():
            continue
        try:
            for raw in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export "):].strip()
                if "=" not in line:
                    continue
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().strip("\"'")
                if key and val and key not in values:
                    values[key] = val
        except OSError:
            pass
    return values


def _get_cfg(key: str, default: str = "", dotenv: dict[str, str] | None = None) -> str:
    val = os.environ.get(key)
    if val:
        return val
    if dotenv and key in dotenv:
        return dotenv[key]
    return default


def resolve_config(args: list[str]) -> tuple[Path | None, Path | None, str, Path | None, float]:
    dotenv = _load_dotenv_values()

    dir_arg = None
    if "--dir" in args:
        idx = args.index("--dir")
        if idx + 1 < len(args):
            dir_arg = args[idx + 1]
    base_raw = dir_arg or _get_cfg("KOKORO_TTS_DIR", "", dotenv)
    base_dir = Path(os.path.expanduser(base_raw)) if base_raw else None

    model_raw = _get_cfg("KOKORO_TTS_MODEL_DIR", "", dotenv)
    if model_raw:
        model_dir = Path(os.path.expanduser(model_raw))
    elif base_dir is not None:
        model_dir = base_dir / "weights" / "Kokoro-82M-bf16"
    else:
        model_dir = None

    voice_arg = None
    if "--voice" in args:
        idx = args.index("--voice")
        if idx + 1 < len(args):
            voice_arg = args[idx + 1]
    voice = voice_arg or _get_cfg("KOKORO_TTS_VOICE", "bm_george", dotenv)

    voice_file = (model_dir / "voices" / f"{voice}.safetensors") if model_dir is not None else None

    speed_raw = _get_cfg("KOKORO_TTS_SPEED", "1.0", dotenv)
    try:
        speed = float(speed_raw)
    except ValueError:
        speed = 1.0

    return base_dir, model_dir, voice, voice_file, speed


def required_paths(base_dir: Path | None, model_dir: Path | None, voice_file: Path | None) -> list[Path]:
    if base_dir is None or model_dir is None or voice_file is None:
        return []
    return [
        base_dir / "engines.py",
        base_dir / "specs.py",
        model_dir / "config.json",
        model_dir / "kokoro-v1_0.safetensors",
        voice_file,
        Path(AFPLAY),
    ]


def missing_paths(base_dir: Path | None, model_dir: Path | None, voice_file: Path | None) -> list[str]:
    if base_dir is None:
        return ["KOKORO_TTS_DIR not configured"]
    return [str(p) for p in required_paths(base_dir, model_dir, voice_file) if not p.exists()]


# ----------------------------------------------------------------------------- text
def _split_long(s: str, limit: int) -> list[str]:
    """Split a too-long sentence at the comma/semicolon (else space) nearest the limit."""
    out: list[str] = []
    while len(s) > limit:
        cut = max(s.rfind(", ", 0, limit), s.rfind("; ", 0, limit), s.rfind(": ", 0, limit))
        if cut < limit // 3:
            cut = s.rfind(" ", 0, limit)
        if cut <= 0:
            cut = limit
        out.append(s[: cut + 1].strip())
        s = s[cut + 1 :].strip()
    if s:
        out.append(s)
    return out


def chunk_text(text: str) -> list[str]:
    """Sentence chunks: the first is short (fast start), later ones packed up to MAX_CHUNK chars."""
    text = re.sub(r"[ \t]+", " ", text.replace("\r", "")).strip()
    sentences: list[str] = []
    for para in re.split(r"\n\s*\n|\n", text):
        para = para.strip()
        if not para:
            continue
        for s in re.split(r"(?<=[.!?…])[\"')\]]*\s+", para):
            s = s.strip()
            if s:
                sentences.extend(_split_long(s, MAX_CHUNK))
    chunks: list[str] = []
    for s in sentences:
        limit = FIRST_CHUNK if len(chunks) == 1 else MAX_CHUNK  # only the first chunk stays short
        if chunks and len(chunks[-1]) + 1 + len(s) <= limit:
            chunks[-1] = f"{chunks[-1]} {s}"
        else:
            chunks.append(s)
    return chunks


# ----------------------------------------------------------------------------- audio
def write_wav(path: str, audio, sr: int) -> None:
    import numpy as np

    pcm = (np.clip(audio, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_volume(default: float) -> float:
    try:
        return max(0.0, min(1.0, float(VOLUME_FILE.read_text().strip())))
    except (OSError, ValueError):
        return default


def wait_player() -> int:
    global _player
    if _player is None:
        return 0
    rc = _player.wait()
    _player = None
    return rc


def cleanup() -> None:
    if _player is not None and _player.poll() is None:
        _player.kill()
    if _tmpdir:
        shutil.rmtree(_tmpdir, ignore_errors=True)


def on_term(signum, _frame) -> None:
    cleanup()
    os._exit(128 + signum)


# ----------------------------------------------------------------------------- engine
def load_engine(base_dir: Path):
    if str(base_dir) not in sys.path:
        sys.path.append(str(base_dir))  # append: never shadow stdlib / this folder
    import specs  # noqa: E402
    import engines  # noqa: E402

    specs.configure_offline_env()
    eng = engines.KokoroEngine()
    eng.load()
    return eng, engines


def synth(eng, engines_mod, text: str, voice: str, voice_file: Path, speed: float):
    lang = "b" if voice.startswith("b") else "a"
    return engines_mod._collect(
        eng.model.generate(text=text, voice=str(voice_file), speed=speed, lang_code=lang)
    )


def main() -> int:
    global _player, _tmpdir
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)

    args = sys.argv[1:]
    base_dir, model_dir, voice, voice_file, speed = resolve_config(args)
    missing = missing_paths(base_dir, model_dir, voice_file)

    if "--check" in args:
        print("MISSING " + " | ".join(missing) if missing else "OK")
        return 3 if missing else 0
    if missing:
        print("Kokoro files missing: " + " | ".join(missing), file=sys.stderr)
        return 3

    volume = 1.0
    if "--volume" in args:
        try:
            volume = float(args[args.index("--volume") + 1])
        except (IndexError, ValueError):
            pass

    chunks = chunk_text(sys.stdin.read())
    if not chunks:
        print("DONE", flush=True)
        return 0

    assert base_dir is not None and voice_file is not None
    try:
        eng, engines_mod = load_engine(base_dir)
    except Exception as e:  # noqa: BLE001 - any load failure means "use the fallback engine"
        print(f"Kokoro load failed: {type(e).__name__}: {e}", file=sys.stderr)
        return 4

    _tmpdir = tempfile.mkdtemp(prefix=TMP_PREFIX)
    try:
        for i, chunk in enumerate(chunks):
            audio, sr = synth(eng, engines_mod, chunk, voice, voice_file, speed)
            wav = os.path.join(_tmpdir, f"{i:04d}.wav")
            write_wav(wav, audio, sr)
            if wait_player() not in (0, None):
                raise RuntimeError("afplay failed")
            _player = subprocess.Popen([AFPLAY, "-v", f"{read_volume(volume):.2f}", wav])
            if i == 0:
                print("PLAYING", flush=True)
        if wait_player() != 0:
            raise RuntimeError("afplay failed")
    except Exception as e:  # noqa: BLE001
        print(f"Kokoro synth/playback failed: {type(e).__name__}: {e}", file=sys.stderr)
        return 5
    finally:
        cleanup()
    print("DONE", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
