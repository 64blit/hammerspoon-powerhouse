#!/usr/bin/env bash
# ==============================================================================
# Hammerspoon Powerhouse — Installer
#
# Safe, idempotent setup script:
#   • Never overwrites existing ~/.hammerspoon/.env or local_init.lua
#   • Installs optional Homebrew CLI dependencies & builds native OCR helper
#
# Usage:
#   ./install.sh                  # interactive setup
#   ./install.sh --no-deps        # skip Homebrew / npm / Swift builds
#   ./install.sh --yes            # accept defaults non-interactively
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.hammerspoon"

INSTALL_DEPS=1
AUTO_YES=0

for arg in "$@"; do
    case "$arg" in
        --no-deps) INSTALL_DEPS=0 ;;
        -y|--yes)  AUTO_YES=1 ;;
        -h|--help)
            echo "Usage: ./install.sh [--yes] [--no-deps]"
            exit 0
            ;;
    esac
done

confirm() {
    local prompt="$1"
    if [[ "$AUTO_YES" == "1" ]]; then
        return 0
    fi
    read -r -p "$prompt [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]
}

echo "⚡ Hammerspoon Powerhouse — Setup"
echo "=================================="

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "❌ This kit requires macOS."
    exit 1
fi

# 1. Check Hammerspoon.app
if [[ ! -d "/Applications/Hammerspoon.app" && ! -d "$HOME/Applications/Hammerspoon.app" ]]; then
    echo "⚠️  Hammerspoon.app not found in /Applications."
    if command -v brew >/dev/null 2>&1 && confirm "Install Hammerspoon via Homebrew?"; then
        brew install --cask hammerspoon
    else
        echo "   Download manually from https://www.hammerspoon.org/"
    fi
else
    echo "✅ Hammerspoon.app detected"
fi

# 2. Ensure kit is installed at ~/.hammerspoon
if [[ "$SCRIPT_DIR" != "$TARGET_DIR" ]]; then
    echo "📁 Script is running from: $SCRIPT_DIR"
    if [[ -e "$TARGET_DIR" && ! -L "$TARGET_DIR" ]]; then
        BACKUP_DIR="${TARGET_DIR}.backup.$(date +%Y%m%d-%H%M%S)"
        if confirm "Existing ~/.hammerspoon found. Back it up to $BACKUP_DIR and link this repo?"; then
            mv "$TARGET_DIR" "$BACKUP_DIR"
            ln -s "$SCRIPT_DIR" "$TARGET_DIR"
            echo "✅ Backed up previous config to $BACKUP_DIR and symlinked $TARGET_DIR -> $SCRIPT_DIR"
        else
            echo "ℹ️  Leaving ~/.hammerspoon untouched; configuring in $SCRIPT_DIR"
            TARGET_DIR="$SCRIPT_DIR"
        fi
    elif [[ ! -e "$TARGET_DIR" ]]; then
        if confirm "Symlink $TARGET_DIR -> $SCRIPT_DIR?"; then
            ln -s "$SCRIPT_DIR" "$TARGET_DIR"
            echo "✅ Symlinked $TARGET_DIR -> $SCRIPT_DIR"
        else
            TARGET_DIR="$SCRIPT_DIR"
        fi
    fi
fi

cd "$TARGET_DIR"

# 3. Provision config templates without overwriting existing files
if [[ ! -f "$TARGET_DIR/.env" ]]; then
    cp "$TARGET_DIR/.env.example" "$TARGET_DIR/.env"
    chmod 600 "$TARGET_DIR/.env"
    echo "✅ Created ~/.hammerspoon/.env from .env.example"
else
    echo "✅ Preserved existing ~/.hammerspoon/.env"
fi

if [[ ! -f "$TARGET_DIR/local_init.lua" ]]; then
    cp "$TARGET_DIR/local_init.example.lua" "$TARGET_DIR/local_init.lua"
    echo "✅ Created ~/.hammerspoon/local_init.lua from template"
else
    echo "✅ Preserved existing ~/.hammerspoon/local_init.lua"
fi

# 4. Optional CLI dependencies & native helpers
if [[ "$INSTALL_DEPS" == "1" ]]; then
    if command -v brew >/dev/null 2>&1; then
        if confirm "Install optional Homebrew CLI tools (ffmpeg, gifski, uv, ttyd)?"; then
            for formula in ffmpeg gifski uv ttyd; do
                if brew list --formula "$formula" >/dev/null 2>&1; then
                    echo "  ✓ $formula already installed"
                else
                    echo "  → Installing $formula..."
                    brew install "$formula" || echo "  ⚠️  Skipped $formula (install failed)"
                fi
            done
        fi
    else
        echo "ℹ️  Homebrew not found — skip CLI install (or click 'Install Tools' in the 🧰 menubar later)."
    fi

    # Compile Apple Vision OCR helper if swiftc is available
    if command -v swiftc >/dev/null 2>&1 && [[ ! -x "$TARGET_DIR/translator_helper/ocr_helper" ]]; then
        echo "🔨 Compiling Apple Vision OCR helper..."
        bash "$TARGET_DIR/translator_helper/build.sh" || echo "⚠️  OCR helper build failed (will retry on first use)"
    fi

    # Install translate_server Node.js deps if npm is available
    if command -v npm >/dev/null 2>&1 && [[ ! -d "$TARGET_DIR/translator_helper/translate_server/node_modules" ]]; then
        echo "📦 Installing Screen Translator Node.js dependencies..."
        (cd "$TARGET_DIR/translator_helper/translate_server" && npm install --silent) || echo "⚠️  npm install failed"
    fi
fi

echo ""
echo "🎉 Setup Complete!"
echo "--------------------------------------------------"
echo "Next steps:"
echo "  1. Add optional API keys in ~/.hammerspoon/.env"
echo "  2. Launch Hammerspoon and grant Accessibility + Screen Recording permissions"
echo "  3. Press Option + Z (⌥Z) to open the Unified Command Palette!"
