# ⚡ Hammerspoon Powerhouse & 64blit Code Intelligence

A modular, extensible macOS productivity environment and AI copilot built on [Hammerspoon](https://www.hammerspoon.org/). Features semantic vector code search, codebase ingestion, documentation scrapers, floating AI chatboxes, screen translation OCR, picture-in-picture overlays, and unified menubar control.

---

## ✨ Features

### ⚡ 1. Unified Command Palette (`⌥Z` / `Option+Z`)
A sleek, spotlight-style command center for macOS that lets you access every tool, search codebases, query notes, or prompt AI from a single keyboard-driven launcher:
- **Instant Action Filtering**: Fuzzy search across all custom Spoons, screen tools, terminal, and AI modules.
- **Slash Commands**: Type `/code <query>` to search code vectors, `/chat <prompt>` to ask the AI assistant, or `/zk <query>` to search Zettelkasten memory notes.
- **Full Keyboard Control**: `↑`/`↓` to navigate, `Enter` to run, `Esc` to dismiss.

### 🧠 2. 64blit Code Intelligence
Deep semantic vector search and codebase ingestion powered by BGE-Large embeddings and ChromaDB.
- **Semantic Code Search HUD (`⌃⌥⌘K`)**: Spotlight-style floating window with instant vector search across all indexed codebases, AI synthesized architecture guidance, and formatted code snippets with syntax highlighting and line numbers.
- **Search Selection (`⌃⌥⌘S`)**: Instant vector search for highlighted text or error messages anywhere across macOS.
- **Codebase / Folder Ingestion (`⌃⌥⌘I`)**: Point-and-click folder indexing with custom semantic tags (e.g. `svelte,api,python`).
- **URL to Markdown Scraper**: Full recursive documentation crawler that outputs clean consolidated & split Markdown files with frontmatter and tables of contents (`~/Documents/Crawls/`).
- **Direct Docs Ingestion**: Crawl and vector-index remote API documentation directly into the active vector DB.
- **Server Lifecycle**: Start, stop, restart, and monitor the local MCP/HTTP FastAPI server (`http://127.0.0.1:9991`) from the menubar.

### 💬 3. Floating AI Chatbox (`⌃⌥⌘A`)
- Instant multi-model AI assistant (OpenRouter, Gemini, Claude, Groq).
- Rendered with Markdown formatting, syntax highlighting, and persistent conversation history.
- Quick shortcut to trigger anywhere without switching desktop workspaces.

### 🪄 4. LLM Text Refiner
- Highlight text in any application and refine it in place or in a floating dialog.
- Built-in prompts for Summarization, Grammar/Tone Correction, Translation, Code Review, and Architecture Analysis.

### 🈳 5. Real-time Screen Translator & Vision OCR
- Draggable and resizable screen capture region with Apple Vision text recognition.
- Overlays translations directly over matching OCR bounding boxes.
- Powered by native Apple Translation CLI and Vision framework.

### 🐚 6. Web Terminal Server & Mobile QR Pairing
- Self-contained web terminal powered by `ttyd`.
- Generates a QR code and magic link via Tailscale for remote terminal access on iPhone/iPad.

### 🔍 7. Mouse Magnifier & Screen Recorder
- Zoom magnifier tracking cursor movement with smooth interpolation.
- High-fps screen recording and GIF exporter powered by `ffmpeg` and `gifski`.

### 🌅 8. Nightshade (Software Redshift Overlay)
- True software color-tint overlay across all displays that bypasses Apple XDR / Reference Mode display limitations.
- Automatic scheduled day/night transitions.

### 🔊 9. Text-to-Speech / Read Aloud (`⌃⌥S`)
- High-fidelity speech generation with automatic volume boost and audio filtering.

### 🖼️ 10. Window Overlay / Picture-in-Picture (`⌃⌥⌘T`)
- Pin any active window as a floating Picture-in-Picture thumbnail in the corner of your workspace.

### ⌨️ 11. Keystroke Visualizer
- On-screen heads-up display displaying real-time modifier keys and shortcuts for tutorials and demos.

### 🧰 12. Unified Menubar Hub
- Consolidates all custom tools under a single dynamic menubar icon (`🧰`), keeping the macOS status bar clean.

---

## ⌨️ Global Keybindings

| Shortcut | Tool | Description |
| :--- | :--- | :--- |
| `⌥Z` | **Command Palette** | Open Unified Command Palette & Search Center |
| `⌃⌥⌘K` | **Code Search HUD** | Open 64blit Code Intelligence Spotlight search |
| `⌃⌥⌘S` | **Search Selection** | Search highlighted text in Code Intelligence |
| `⌃⌥⌘I` | **Ingest Codebase** | Prompt folder picker to index a project into vector DB |
| `⌃⌥⌘A` | **AI Chatbox** | Toggle floating OpenRouter / LLM chatbox |
| `⌃⌥⌘T` | **Window PiP** | Toggle Picture-in-Picture overlay for focused window |
| `⌃⌥S` | **Read Aloud** | Speak selected text aloud |
| `⌘⌥V` | **Clipboard Tool** | Open clipboard history manager |
| `⌃⌥⌘C` | **Caffeine** | Prevent system sleep |

*(All hotkeys are customizable in `init.lua`)*

---

## 🚀 Quickstart & Installation

### 1. Prerequisites
- macOS 13+ (Ventura, Sonoma, Sequoia)
- [Hammerspoon](https://www.hammerspoon.org/) (`brew install --cask hammerspoon`)
- Homebrew (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)

### 2. Clone Repository
Clone directly into your Hammerspoon directory:
```bash
git clone https://github.com/64blit/hammerspoon-powerhouse.git ~/.hammerspoon
```

### 3. Configure Secrets & Environment
Copy the example template to `~/.hammerspoon/.env` (or populate `~/.env`):
```bash
cp ~/.hammerspoon/.env.example ~/.hammerspoon/.env
```
Edit `~/.hammerspoon/.env` and add your API keys:
```env
OPENROUTER_API_KEY=your_openrouter_key
XAI_API_KEY=your_xai_key
OPENAI_API_KEY=your_openai_key
GEMINI_API_KEY=your_gemini_key
```

### 4. One-Click Dependency Installation
1. Start **Hammerspoon**.
2. Click the **🧰** Menubar Hub icon and select **📦 Install Tools (brew)**.
3. This automatically installs and verifies:
   - `ffmpeg` (Audio/video encoding)
   - `gifski` (GIF export)
   - `uv` (Fast Python package runner)
   - `translate-cli` & OCR helpers (Apple Vision & Translation)

### 5. Reload Hammerspoon
Press `Reload Hammerspoon` in the menu or restart Hammerspoon.

---

## 📁 Repository Structure

```
~/.hammerspoon/
├── init.lua                   # Master entrypoint & hotkey orchestrator
├── menubar_hub.lua            # Unified dropdown hub for all tools
├── env_loader.lua             # Secure environment & secrets manager
├── .env.example               # Template configuration file
├── code_intel.lua             # 64blit Code Intelligence (Search HUD, Ingest, Scraper)
├── ai_chatbox.lua             # Floating Webview AI Chatbox
├── text_refiner.lua           # Quick LLM text transforms (xAI/OpenAI)
├── window_translator.lua      # Apple Vision OCR & Translation overlay
├── translator_helper/         # Swift OCR helper & Translation server
├── terminal_toggle.lua        # Web terminal server & Tailscale QR pairing
├── terminal_server/           # ttyd server scripts and mobile UI
├── mouse_magnifier.lua        # Smooth mouse zoom & screen recorder
├── nightshade.lua             # Software redshift screen filter
├── text_to_speech.lua         # Text-to-Speech audio player
├── openrouter_tts.py          # Python TTS synthesizer
├── window_overlay.lua         # Picture-in-Picture window overlay
├── keystroke_visualizer.lua   # HUD keystroke visualizer
├── spoons_setup.lua           # Spoons (ClipboardTool, Caffeine)
├── install_tools.lua          # Automated Homebrew & CLI installer
├── assets/                    # Static assets & icons
└── Spoons/                    # Hammerspoon official Spoons
```

---

## 🤝 Contributing & License

Contributions, bug reports, and suggestions are welcome!

Released under the [MIT License](LICENSE).
