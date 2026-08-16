#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# 1. Kill any existing instances
lsof -ti:7681,7682 | xargs kill -9 2>/dev/null

# 2. Start the server
echo "🚀 Starting terminal server on :7681..."
nohup ./ttyd_server > ttyd_log.txt 2>&1 &
sleep 2

# 3. Serve via Tailscale
echo "🔗 Exposing via Tailscale..."
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --https=443 off 2>/dev/null
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --bg http://127.0.0.1:7681

echo "✅ Terminal is ready!"
