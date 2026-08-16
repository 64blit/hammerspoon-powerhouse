import urllib.request
import urllib.error
import json
import sys
import os

def get_openai_key():
    # Check system environment first
    key = os.environ.get("OPENAI_API_KEY") or os.environ.get("OPEN_API_KEY") or os.environ.get("OPENROUTER_API_KEY")
    if key:
        return key

    # Check ~/.hammerspoon/.env then ~/.env
    env_paths = [
        os.path.expanduser("~/.hammerspoon/.env"),
        os.path.expanduser("~/.env")
    ]
    for env_path in env_paths:
        try:
            if os.path.exists(env_path):
                with open(env_path, "r") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("OPENAI_API_KEY=") or line.startswith("OPEN_API_KEY=") or line.startswith("OPENROUTER_API_KEY="):
                            return line.split('=', 1)[1].strip('"\'')
        except:
            pass
    return None

def main():
    text = sys.stdin.read().strip()
    if not text:
        return

    api_key = get_openai_key()
    if not api_key:
        print("OPENAI_API_KEY / OPEN_API_KEY not found in ~/.hammerspoon/.env or ~/.env", file=sys.stderr)
        sys.exit(1)

    url = "https://api.openai.com/v1/audio/speech"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    # Use the dedicated TTS model rather than a conversational chat completions model.
    data = {
        "model": "tts-1",
        "input": text,
        "voice": "alloy",
        "response_format": "mp3"
    }

    req = urllib.request.Request(url, data=json.dumps(data).encode("utf-8"), headers=headers)
    
    try:
        with urllib.request.urlopen(req) as resp:
            mp3_path = "/tmp/hammerspoon_openrouter_tts.mp3"
            with open(mp3_path, "wb") as f_out:
                f_out.write(resp.read())
            
        # Boost the baseline volume by 300% (since OpenAI's TTS is inherently mastered too quiet)
        boost_path = "/tmp/hammerspoon_openrouter_tts_boosted.mp3"
        ret = os.system(f'/opt/homebrew/bin/ffmpeg -y -i {mp3_path} -filter:a "volume=5.0,atempo=1.5" {boost_path} >/dev/null 2>&1')
        if ret == 0 and os.path.exists(boost_path):
            os.replace(boost_path, mp3_path)
            
        print("SUCCESS", mp3_path)

    except urllib.error.HTTPError as e:
        print(f"HTTPError: {e.code} - {e.read().decode()}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
