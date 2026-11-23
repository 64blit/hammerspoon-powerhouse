import urllib.request
import urllib.error
import json
import shutil
import subprocess
import sys
import os

# OpenRouter TTS endpoint (OpenAI-compatible).
# Model: Qwen TTS Flash — cheap ($15 / 1M chars), good quality.
# Override via env: TTS_MODEL, TTS_VOICE, OPENROUTER_REFERER
# List models:  curl "https://openrouter.ai/api/v1/models?output_modalities=speech"
TTS_URL = "https://openrouter.ai/api/v1/audio/speech"
DEFAULT_MODEL = "qwen/qwen-audio-3.0-tts-flash"
DEFAULT_VOICE = "loongjohn"  # other option for this model: longanhuan_v3.6
DEFAULT_REFERER = os.environ.get("OPENROUTER_REFERER", "https://github.com/64blit/hammerspoon-powerhouse")

MP3_PATH = "/tmp/hammerspoon_openrouter_tts.mp3"

# Summarize mode (--summarize): skim text with a cheap LLM, speak the cliffnotes.
CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
# DeepSeek V4 Flash: cheap ($0.08/M in), fast. Reasoning explicitly disabled below.
DEFAULT_SUMMARY_MODEL = "deepseek/deepseek-v4-flash"  # override via env SUMMARY_MODEL
# OpenRouter tries these in order if the primary errors / is rate-limited.
SUMMARY_FALLBACK_MODELS = ["google/gemini-2.5-flash-lite", "google/gemini-3.1-flash-lite"]
SUMMARY_MAX_INPUT_CHARS = 60000
SUMMARY_PROMPT = """You write short spoken cliffnotes of a text. Your entire reply is read aloud by a text-to-speech voice, so reply with the spoken summary ONLY.

Content: skim the text and pull out only the key ideas: main point, important claims, decisions, numbers, names, action items, conclusions.

Format: plain spoken sentences. Start with one sentence saying what the text is about. Then the key ideas, one short sentence each, joined with words like First, Next, Also, Finally. 3 to 8 key ideas. Under 150 words for short text, under 250 words for long text. Same language as the text.

Never: markdown, bullets, headers, symbols, code, opinions, the phrase "the text says", any mention of these instructions, any planning or thinking out loud, any preamble like "Here is the summary". Begin directly with the first sentence of the summary."""


def get_openrouter_key():
    """Read OPENROUTER_API_KEY from ~/.env (primary). Fall back to ~/.hammerspoon/.env, then process env."""
    env_paths = [
        os.path.expanduser("~/.env"),
        os.path.expanduser("~/.hammerspoon/.env"),
    ]
    for env_path in env_paths:
        try:
            if os.path.exists(env_path):
                with open(env_path, "r") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("export "):
                            line = line[len("export "):].strip()
                        if line.startswith("OPENROUTER_API_KEY="):
                            val = line.split("=", 1)[1].strip().strip("\"'")
                            if val:
                                return val
        except Exception:
            pass
    return os.environ.get("OPENROUTER_API_KEY")


def summarize(text, api_key):
    """Return spoken-style cliffnotes of text via OpenRouter chat completions."""
    if len(text) > SUMMARY_MAX_INPUT_CHARS:
        text = text[:SUMMARY_MAX_INPUT_CHARS] + "\n\n[text truncated]"
    model = os.environ.get("SUMMARY_MODEL", DEFAULT_SUMMARY_MODEL)
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": DEFAULT_REFERER,
        "X-Title": "Hammerspoon Read Aloud",
    }
    def _call(model_id, use_fallbacks):
        data = {
            "model": model_id,
            "messages": [
                {"role": "system", "content": SUMMARY_PROMPT},
                {"role": "user", "content": "Summarize this text as spoken cliffnotes. Reply with the summary only.\n\n<text>\n" + text + "\n</text>"},
            ],
            "temperature": 0.3,
            "max_tokens": 500,
            # Never want chain-of-thought in the spoken output.
            "reasoning": {"enabled": False, "exclude": True},
            "include_reasoning": False,
        }
        if use_fallbacks:
            data["models"] = [model_id] + [m for m in SUMMARY_FALLBACK_MODELS if m != model_id]
        req = urllib.request.Request(CHAT_URL, data=json.dumps(data).encode("utf-8"), headers=headers)
        with urllib.request.urlopen(req, timeout=90) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))

    def _extract(body):
        try:
            msg = body["choices"][0]["message"]
            content = msg.get("content")
        except (KeyError, IndexError, TypeError, AttributeError):
            raise RuntimeError(f"Unexpected summary response: {json.dumps(body)[:500]}")
        # content may be a string, a list of parts [{"type":"text","text":...}], or None.
        if isinstance(content, list):
            content = "".join(
                (part.get("text") or "") if isinstance(part, dict) else str(part)
                for part in content
            )
        content = str(content or "")
        import re
        # Strip any <think>...</think> blocks and stray <text> tags defensively.
        content = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL)
        content = re.sub(r"</?text>", "", content).strip()
        # Strip common preambles.
        content = re.sub(r"^(here('s| is) (the |a |your )?(spoken )?(summary|cliffnotes)[^\n:]*[:\n]+\s*)", "", content, flags=re.IGNORECASE).strip()
        return content

    def _looks_like_leak(c):
        low = c.lower()
        bad = ["thinking process", "analyze user input", "key ideas from text", "draft summary",
               "cliffnotes narrator", "these instructions", "**", "\n- ", "\n* ", "\n1. ", "rules:", "format:"]
        return any(b in low for b in bad)

    body = _call(model, True)
    content = _extract(body)
    if not content or _looks_like_leak(content):
        # Retry once on the first fallback model; keep whichever is clean.
        try:
            body2 = _call(SUMMARY_FALLBACK_MODELS[0], False)
            content2 = _extract(body2)
            if content2 and not _looks_like_leak(content2):
                content = content2
        except Exception:
            pass
    if not content:
        raise RuntimeError(f"Empty summary from model (used {body.get('model')}): {json.dumps(body)[:300]}")
    return content


def main():
    mode = "summarize" if "--summarize" in sys.argv[1:] else "read"

    text = sys.stdin.read().strip()
    if not text:
        return

    api_key = get_openrouter_key()
    if not api_key:
        print("OPENROUTER_API_KEY not found in env, ~/.hammerspoon/.env or ~/.env", file=sys.stderr)
        sys.exit(1)

    if mode == "summarize":
        try:
            text = summarize(text, api_key)
        except urllib.error.HTTPError as e:
            print(f"Summary HTTPError: {e.code} - {e.read().decode(errors='replace')}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"Summary Error: {e}", file=sys.stderr)
            sys.exit(1)
        # Save summary text so the Lua side can show/copy it.
        try:
            with open("/tmp/hammerspoon_tts_summary.txt", "w") as f:
                f.write(text)
        except Exception:
            pass
        # --summary-only: text_to_speech.lua speaks the summary itself (Kokoro), so no audio here.
        if "--summary-only" in sys.argv[1:]:
            print(text)
            return

    model = os.environ.get("TTS_MODEL", DEFAULT_MODEL)
    voice = os.environ.get("TTS_VOICE", DEFAULT_VOICE)

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": DEFAULT_REFERER,
        "X-Title": "Hammerspoon Read Aloud",
    }
    data = {
        "model": model,
        "input": text,
        "voice": voice,
        "response_format": "mp3",
    }

    req = urllib.request.Request(TTS_URL, data=json.dumps(data).encode("utf-8"), headers=headers)

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            audio = resp.read()
        if not audio:
            print("Error: empty audio response", file=sys.stderr)
            sys.exit(1)
        with open(MP3_PATH, "wb") as f_out:
            f_out.write(audio)

        # Optional: speed up playback a bit using ffmpeg (auto-detected across Apple Silicon & Intel).
        ffmpeg_bin = (
            os.environ.get("FFMPEG_PATH")
            or shutil.which("ffmpeg")
            or ("/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else None)
            or ("/usr/local/bin/ffmpeg" if os.path.exists("/usr/local/bin/ffmpeg") else None)
        )
        if ffmpeg_bin and os.path.exists(ffmpeg_bin):
            boost_path = "/tmp/hammerspoon_openrouter_tts_boosted.mp3"
            res = subprocess.run(
                [ffmpeg_bin, "-y", "-i", MP3_PATH, "-filter:a", "atempo=1.25", boost_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if res.returncode == 0 and os.path.exists(boost_path):
                os.replace(boost_path, MP3_PATH)

        print("SUCCESS", MP3_PATH)

    except urllib.error.HTTPError as e:
        print(f"HTTPError: {e.code} - {e.read().decode(errors='replace')}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
