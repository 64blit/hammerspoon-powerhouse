#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# 1. Kill any existing instances
lsof -ti:7681,7682 | xargs kill -9 2>/dev/null || true

# 2. Start the terminal server on :7681
# Uses custom ./ttyd_server wrapper if present, otherwise falls back to Homebrew `ttyd`.
if [ -x "./ttyd_server" ]; then
    echo "🚀 Starting custom ttyd_server on :7681..."
    nohup ./ttyd_server > ttyd_log.txt 2>&1 &
else
    TTYD_BIN="$(command -v ttyd || echo "")"
    [ -z "$TTYD_BIN" ] && [ -x "/opt/homebrew/bin/ttyd" ] && TTYD_BIN="/opt/homebrew/bin/ttyd"
    [ -z "$TTYD_BIN" ] && [ -x "/usr/local/bin/ttyd" ] && TTYD_BIN="/usr/local/bin/ttyd"

    if [ -z "$TTYD_BIN" ]; then
        echo "❌ ttyd not found. Install with: brew install ttyd"
        exit 1
    fi

    TMUX_BIN="$(command -v tmux || echo "")"
    [ -z "$TMUX_BIN" ] && [ -x "/opt/homebrew/bin/tmux" ] && TMUX_BIN="/opt/homebrew/bin/tmux"
    [ -z "$TMUX_BIN" ] && [ -x "/usr/local/bin/tmux" ] && TMUX_BIN="/usr/local/bin/tmux"

    INDEX_ARGS=()
    [ -f "./ttyd_mobile.html" ] && INDEX_ARGS=(-I ./ttyd_mobile.html)

    echo "🚀 Starting ttyd on :7681..."
    if [ -n "$TMUX_BIN" ]; then
        nohup "$TTYD_BIN" -p 7681 -W "${INDEX_ARGS[@]}" "$TMUX_BIN" new-session -A -s main /bin/zsh > ttyd_log.txt 2>&1 &
    else
        nohup "$TTYD_BIN" -p 7681 -W "${INDEX_ARGS[@]}" /bin/zsh > ttyd_log.txt 2>&1 &
    fi
fi
sleep 2

# 3. Expose via Tailscale if installed
TS_BIN=""
[ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ] && TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[ -z "$TS_BIN" ] && TS_BIN="$(command -v tailscale || echo "")"

if [ -n "$TS_BIN" ]; then
    echo "🔗 Exposing via Tailscale..."
    "$TS_BIN" serve --https=443 off 2>/dev/null || true
    "$TS_BIN" serve --bg http://127.0.0.1:7681
else
    echo "ℹ️  Tailscale not found — terminal is running locally at http://127.0.0.1:7681"
fi

echo "✅ Terminal is ready!"
