#!/bin/bash

# 1. Stop Tailscale serve
echo "🛑 Stopping Tailscale serve..."
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --https=443 off 2>/dev/null || tailscale serve --https=443 off

# 2. Kill the ttyd server and the ttyd backend
echo "💀 Killing ttyd processes..."
lsof -ti:7681,7682 | xargs kill -9 2>/dev/null

echo "✅ Terminal server stopped."
