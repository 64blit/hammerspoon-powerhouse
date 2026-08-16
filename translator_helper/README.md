# Window Translator helper

Companion files for `window_translator.lua`.

## What's here

- `translate_server/` — Node.js translation HTTP server using `@iamtraction/google-translate`.
- `ocr_helper.swift` — Vision-framework OCR helper. Reads an image path, prints
  JSON `[{text,confidence,x,y,w,h}, ...]` in image pixel coordinates.
- `build.sh` — compiles `ocr_helper.swift` -> `ocr_helper`.
- `ocr_helper` — compiled binary (generated).

The Lua module auto-builds the binary and manages `translate_server` on first use.

## Translation Engine

`window_translator.lua` uses a dual-backend approach:
1. **Primary**: Local `translate_server` (HTTP service on `127.0.0.1:27892`) providing fast batch translations via Google Translate.
2. **Fallback**: Apple Translation CLI (`bin/translate`).

1. Open the **Shortcuts** app.
2. New shortcut, name it exactly **`HSTranslate`**.
3. Settings:
   - "Use as Quick Action" off (not required).
   - In the right-hand sidebar set **"Receive Text input from Shortcuts"**.
4. Add a single **Translate Text** action:
   - Text: `Shortcut Input`
   - From: `Detect Language`
   - To: your target language (e.g. English)
5. Make sure the last action's result is the **Stop and output** of the
   shortcut (Translate Text already returns text — you can drop a "Stop and
   output" action set to the translated text to be explicit).

Smoke test from terminal:

```bash
echo "bonjour le monde" | shortcuts run HSTranslate
# -> hello world
```

If that prints the translation, the Lua module will work.

## Hotkeys

- `ctrl+alt+cmd+Y`       — toggle overlay on the focused window
- `ctrl+alt+cmd+shift+Y` — translate now (single shot)
- `ctrl+alt+cmd+P`       — pause / resume live translation

## Permissions

First run needs:
- **Screen Recording** for Hammerspoon (window snapshots).
- **Automation** prompt for Hammerspoon -> Shortcuts (allow once).
