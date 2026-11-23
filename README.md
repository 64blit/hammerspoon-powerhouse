# ⚡ Hammerspoon Powerhouse

A modular, open-source macOS productivity kit and AI copilot built on [Hammerspoon](https://www.hammerspoon.org/). Designed with a clean **public/private separation layer** so you can share, fork, pull, and push updates without ever losing or leaking your API keys, private scripts, or machine-specific paths.

---

## ✨ What's Included

### ⚡ 1. Unified Command Palette (`⌥Z`)
Spotlight-style keyboard launcher for every tool, workflow, code search, and note:
- **Fuzzy Command Search**: Filter every installed module, scraper, AI action, and utility instantly.
- **Slash Commands**:
  - `/code <query>` — Semantic vector search across indexed codebases
  - `/zk <query>` — Search local Zettelkasten Markdown notes (`ZETTELKASTEN_NOTES_DIR`)
  - `/chat` — Launch the floating AI Chatbox
- **Extensible**: Add private commands from `local_init.lua` via `command_palette.registerCommand(...)`.

### 🖼️ 2. Visual Image Scraper & Markdown Doc Crawler
- **Visual Image Picker**: Enter any URL to extract page images, preview them in a paginated dark-mode WebView gallery, select the ones you want, and batch-download them to `~/Downloads/scraped-images`.
- **64blit Code Intelligence (Optional Backend)**: Deep semantic vector search HUD (`⌃⌥⌘K`), search highlighted text (`⌃⌥⌘S`), codebase ingestion (`⌃⌥⌘I`), and recursive URL-to-Markdown docset scraping (`~/Documents/Crawls/`).

### 🔍 3. Mouse Magnifier & Hardware Screen Recorder (`⌃⌥⌘M` / `⌃⌥⌘R`)
- Smooth cursor-following magnifier spanning from **Fit Whole Screen** (`⌃⌥⌘0`) up to **10x** zoom with subtle click-pulse animations.
- Live hardware-accelerated recording (`ffmpeg` + Apple `h264_videotoolbox`) cropped directly to the magnifier frame, outputting **MP4** plus optional **GIF** (`gifski`) and **WebM** exports.

### 🔊 4. Multi-Engine Read Aloud & Cliffnotes Summarizer (`⌃⌥S` / `⌃⌥⇧S`)
- **`⌃⌥S` (Read Verbatim)** / **`⌃⌥⇧S` (Summarize to Spoken Cliffnotes & Read)**.
- **Multi-Engine Support** (switchable live from the menubar or `TTS_ENGINE` in `.env`):
  1. **Local Kokoro-82M** (fully offline sentence-chunked synthesis when `KOKORO_TTS_DIR` is configured)
  2. **OpenRouter Cloud TTS** (high-quality speech via `OPENROUTER_API_KEY`)
  3. **macOS `say`** (zero-config built-in offline fallback — works immediately out of the box)

### 💬 5. Floating AI Chatbox (`⌃⌥⌘A`)
- Streaming multi-model assistant (OpenRouter — Claude, Gemini, GPT, Grok, DeepSeek, or custom model IDs).
- Full Markdown rendering, syntax highlighting, one-click code copy buttons, and persistent conversation state.

### ✨ 6. LLM Text Refiner & Dialect Translator (`⌃⌥⌘D/F/G/S/E`)
- Select text anywhere on macOS to polish speech-to-text dictation in place for **Coding Prompts** (`⌃⌥⌘D`), **Chat/DM** (`⌃⌥⌘F`), or **Email** (`⌃⌥⌘G`), or translate **EN ↔ ES** (`⌃⌥⌘S` / `⌃⌥⌘E`).
- Automatically routes to `XAI_API_KEY` (x.ai Grok), `OPENROUTER_API_KEY`, or `OPENAI_API_KEY`.

### 🈳 7. Live Screen Translator & Apple Vision OCR (`⌃⌥⌘Y`)
- Draggable/resizable capture frame with native Apple Vision OCR (`ocr_helper.swift`) and real-time translated text overlays drawn directly over matching bounding boxes.
- Dual backend: bundled local Node.js Google Translate server + optional Apple Translation CLI fallback.

### 🐚 8. Web Terminal Server & Mobile QR Pairing (`⌘⌥M` / `⌘⌥Q`)
- One-click web terminal (`ttyd` + mobile virtual keyboard wrapper `ttyd_mobile.html`).
- Automatic Tailscale HTTPS exposure + scannable on-screen QR code for instant iPhone/iPad access.

### 🛠️ 9. Everyday Utilities & Unified Menubar Hub (`🧰`)
- **Window Picture-in-Picture** (`⌃⌥⌘T`): Pin any focused window as a live floating thumbnail.
- **Keystroke Visualizer**: Clean HUD displaying modifier chords & keys for demos and screen recordings.
- **Nightshade**: Click-through software redshift overlay that works even on Apple XDR / Reference Mode displays.
- **Official Spoons**: Bundled `ClipboardTool` (`⌘⌥V`) and `Caffeine` (`⌃⌥⌘C`).
- **Unified Menubar Hub (`🧰`)**: Consolidates all tools under one clean icon and supports `menubar_hub.registerTool(...)` for private modules.

---

## 🚀 Quickstart (2 Minutes)

### 1. Prerequisites
- macOS 13+ (Apple Silicon or Intel)
- [Hammerspoon](https://www.hammerspoon.org/) (`brew install --cask hammerspoon`)
- [Homebrew](https://brew.sh/) (for optional CLI tools like `ffmpeg`, `gifski`, `uv`, `ttyd`)

### 2. Clone & Run Installer
```bash
git clone https://github.com/64blit/hammerspoon-powerhouse.git ~/.hammerspoon
cd ~/.hammerspoon
./install.sh
```

`install.sh` is safe and idempotent:
- Creates `~/.hammerspoon/.env` from `.env.example` (never overwrites existing files)
- Creates `~/.hammerspoon/local_init.lua` from `local_init.example.lua` (never overwrites existing files)
- Installs a **git `pre-commit` privacy guard** so you can never accidentally commit secrets or private paths
- Optionally installs Homebrew dependencies (`ffmpeg`, `gifski`, `uv`, `ttyd`) and builds the OCR/translator helpers

### 3. Add Optional API Keys
Edit `~/.hammerspoon/.env` (or keep global keys in `~/.env`):
```env
OPENROUTER_API_KEY=sk-or-...
XAI_API_KEY=xai-...
```
> **Zero-key start:** Command Palette, Magnifier/Recorder, Window PiP, Keystroke Visualizer, Nightshade, Image Scraper, Clipboard History, Caffeine, and Read Aloud (`macOS say`) all work immediately without any API keys.

### 4. Grant macOS Permissions & Launch
1. Open **Hammerspoon** and grant **Accessibility** and **Screen Recording** permissions in System Settings.
2. Press **`⌥Z`** (`Option + Z`) to open the Command Palette, or click **`🧰`** in your menubar!

---

## 🔒 Keeping Private Stuff Safe (Never Lose, Never Leak)

This kit is structured so you can keep `~/.hammerspoon` directly synced with GitHub while keeping private scripts, local paths, and credentials completely isolated:

| Layer | File / Directory | Tracked in Git? | Purpose |
| :--- | :--- | :---: | :--- |
| **Secrets & Paths** | `~/.hammerspoon/.env` or `~/.env` | ❌ Gitignored | API keys, local binary/model paths, module `ENABLE_*` flags |
| **Private Hooks** | `~/.hammerspoon/local_init.lua` | ❌ Gitignored | Machine-specific `require()` calls, custom hotkeys, private startup code |
| **Private Modules** | `~/.hammerspoon/private/*.lua` | ❌ Gitignored | Private Lua modules (auto-added to `package.path`) |
| **Local Backups** | `~/.hammerspoon/.local_backups/` | ❌ Gitignored | Personal snapshots and `.bak` files |
| **Commit Guard** | `scripts/audit_privacy.sh` | ✅ Tracked | Blocks commits containing keys, `/Users/...` paths, `.env`, or external symlinks |

### Extending Privately Without Merge Conflicts
Copy [`local_init.example.lua`](local_init.example.lua) to `local_init.lua`:
```lua
-- Load a private module from ~/.hammerspoon/private/
require("my_internal_helper")

-- Register a private command in the Option+Z Command Palette
require("command_palette").registerCommand({
    id = "my_private_action",
    title = "Open Internal Dashboard",
    category = "Private",
    icon = "🔒",
    fn = function() hs.urlevent.openURL("https://internal.example.com") end,
})

-- Add a private submenu to the unified 🧰 Menubar Hub
require("menubar_hub").registerTool({
    title = "Internal Tools",
    icon = function() return "🔒" end,
    buildMenu = function()
        return { { title = "Ping", fn = function() hs.alert.show("Pong") end } }
    end,
})
```

### Run the Privacy Audit Anytime
```bash
./scripts/audit_privacy.sh
```
The same script is automatically installed as `.git/hooks/pre-commit` when you run `./install.sh`.

---

## ⌨️ Default Keybindings

| Shortcut | Module | Action |
| :--- | :--- | :--- |
| `⌥Z` | **Command Palette** | Open Unified Command Palette & Search Center |
| `⌃⌥⌘A` | **AI Chatbox** | Toggle floating multi-model LLM chatbox |
| `⌃⌥⌘M` | **Mouse Magnifier** | Toggle cursor magnifier |
| `⌃⌥⌘R` | **Magnifier Recorder** | Start / stop hardware MP4 + GIF screen recording |
| `⌃⌥⌘=` / `-` / `0` | **Mouse Magnifier** | Zoom in / zoom out / fit whole screen |
| `⌃⌥S` | **Read Aloud** | Speak selected text aloud (or stop) |
| `⌃⌥⇧S` | **Cliffnotes TTS** | Summarize selection via LLM and speak aloud |
| `⌃⌥⌘D` / `F` / `G` | **Text Refiner** | Refine dictation for Coding / Chat / Email |
| `⌃⌥⌘S` / `E` | **Text Refiner** | Translate selection EN→ES / ES→EN |
| `⌃⌥⌘Y` / `⇧Y` / `P` | **Screen Translator** | Toggle OCR overlay / translate now / pause |
| `⌘⌥M` / `U` / `Q` | **Web Terminal** | Toggle `ttyd` server / copy Tailscale link / show QR |
| `⌃⌥⌘T` | **Window PiP** | Pin focused window as Picture-in-Picture |
| `⌃⌥⌘K` | **Code Intel / Keystrokes** | Code Search HUD / Keystroke Visualizer toggle |
| `⌃⌥⌘I` | **Code Intel** | Prompt folder picker to ingest codebase |
| `⌘⌥V` | **ClipboardTool** | Open clipboard history manager |
| `⌃⌥⌘C` | **Caffeine** | Toggle display sleep prevention |

*Disable any module cleanly in `~/.hammerspoon/.env` with `ENABLE_<MODULE>=0` (see [`.env.example`](.env.example)).*

---

## 📁 Repository Structure

```text
~/.hammerspoon/
├── init.lua                   # Master entrypoint, safe module loader & local_init hook
├── env_loader.lua             # Layered .env loader (~/.hammerspoon/.env -> ~/.env -> OS env)
├── install.sh                 # Safe, idempotent setup script + pre-commit hook installer
├── scripts/
│   └── audit_privacy.sh       # Secret, path & private-file leak scanner
├── .env.example               # Documented configuration & module toggle template
├── local_init.example.lua     # Template for private extensions (copy to local_init.lua)
├── command_palette.lua        # Unified Option+Z Spotlight palette + registerCommand API
├── menubar_hub.lua            # Unified 🧰 menubar hub + registerTool API
├── code_intel.lua             # Code Intelligence HUD, doc crawler & visual Image Scraper
├── ai_chatbox.lua             # Streaming floating AI Chatbox (OpenRouter)
├── text_refiner.lua           # In-place dictation polisher & translator
├── text_to_speech.lua         # Multi-engine Read Aloud (Kokoro / OpenRouter / macOS say)
├── kokoro_speak.py            # Offline sentence-chunked Kokoro-82M synthesizer
├── openrouter_tts.py          # OpenRouter TTS & Cliffnotes LLM summarizer
├── mouse_magnifier.lua        # Magnifier + hardware MP4/GIF/WebM recorder
├── window_translator.lua      # Apple Vision OCR & real-time screen translation overlay
├── translator_helper/         # Swift Vision OCR helper & Node.js translation server
├── terminal_toggle.lua        # Web terminal controller & Tailscale QR overlay
├── terminal_server/           # ttyd launch scripts & mobile virtual keyboard UI
├── window_overlay.lua         # Floating Picture-in-Picture window mirror
├── keystroke_visualizer.lua   # On-screen keystroke HUD
├── nightshade.lua             # Software redshift screen tint overlay
├── spoons_setup.lua           # ClipboardTool & Caffeine configuration
├── install_tools.lua          # In-app one-click Homebrew dependency installer
├── assets/                    # Static icons & cursor assets
└── Spoons/                    # Bundled official Spoons
```

---

## 🤝 Contributing & License

Contributions, bug reports, and module PRs are welcome! Before committing, run `./scripts/audit_privacy.sh` to verify no local paths or credentials are staged.

Released under the [MIT License](LICENSE).
