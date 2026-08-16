# Prompt: Recreate the Mobile Terminal Action Bar

You are a coding agent. Your task is to add a mobile-friendly virtual keyboard / action bar to a web-based terminal site. Follow this spec end-to-end. Do not improvise the protocol, layout, or key codes — match them exactly. Only deviate when the host terminal demands a different integration (see "Integration variants" below), and document any deviation in a comment.

---

## 1. Goal

The host site renders a terminal in the browser (typically `ttyd`, `gotty`, `Wetty`, `xterm.js`, or any iframe-embeddable PTY). On phones, the on-screen keyboard lacks Esc, Tab, Ctrl, arrows, pipes, brackets, etc. — making CLIs like vim, tmux, and Claude Code unusable.

Build a thin wrapper page that:

1. Embeds the existing terminal inside an iframe so the upstream terminal code stays untouched.
2. Renders a 3-row action bar fixed below the iframe.
3. Forwards key events into the terminal via `postMessage` (with a fallback that walks the iframe's window to find an xterm.js instance and calls `term.send(data)` directly).

Deliverable: **one static HTML file**, no build step, no external dependencies, works on iOS Safari and Android Chrome.

---

## 2. Architecture

```
┌────────────────────────────────────────────┐
│  wrapper.html  (this file — what you build)│
│  ┌──────────────────────────────────────┐  │
│  │  <iframe src="/ttyd/">               │  │  ← unmodified upstream terminal
│  │      xterm.js running inside         │  │
│  │      window.addEventListener(        │  │  ← optional listener you may
│  │        'message', e => term.send(    │  │    need to inject if upstream
│  │          e.data.data))               │  │    doesn't already accept
│  │  </iframe>                           │  │    postMessage input
│  └──────────────────────────────────────┘  │
│  ┌──────────────────────────────────────┐  │
│  │  #kb-bar                             │  │
│  │  ┌────────────────────────────────┐  │  │
│  │  │ Row 1: Esc Tab Ctrl Alt Shift  │  │  │  ← modifiers + nav
│  │  │        ^C ◀ ▲ ▼ ▶              │  │  │
│  │  ├────────────────────────────────┤  │  │
│  │  │ Row 2: 1 2 3 … / - _ = + | \   │  │  │  ← symbols (scrollable)
│  │  ├────────────────────────────────┤  │  │
│  │  │ Row 3: [text input] RET  SEND  │  │  │  ← free-form text
│  │  └────────────────────────────────┘  │  │
│  └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

Communication contract: every action posts the same shape to the iframe.

```js
iframe.contentWindow.postMessage({ type: 'input', data: '<bytes to write to PTY>' }, '*');
```

`data` is the raw string the terminal would receive from a real keypress (e.g. `\x1b` for Esc, `\x03` for Ctrl-C, `\x1b[A` for Up arrow, `ls\r` for typed text + Enter).

---

## 3. Reference implementation

This is the canonical wrapper. Copy it verbatim, then adjust only the iframe `src` and (if needed) the injection block.

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <title>Terminal</title>
    <style>
        body, html { margin: 0; padding: 0; height: 100%; background: #000; font-family: -apple-system, system-ui, sans-serif; overflow: hidden; color: #fff; }
        #container { display: flex; flex-direction: column; height: 100vh; }
        #terminal-frame { flex-grow: 1; border: none; width: 100%; background: #000; }

        #kb-bar {
            background: #121212;
            border-top: 1px solid #333;
            padding: 6px;
            display: flex;
            flex-direction: column;
            gap: 6px;
            user-select: none;
            padding-bottom: env(safe-area-inset-bottom, 6px);
        }
        .kb-row { display: flex; gap: 4px; justify-content: space-between; align-items: center; overflow-x: auto; -webkit-overflow-scrolling: touch; scrollbar-width: none; }
        .kb-row::-webkit-scrollbar { display: none; }

        .kb-btn {
            background: #2a2a2a;
            color: #efefef;
            border: 1px solid #444;
            padding: 10px 0;
            border-radius: 6px;
            font-size: 11px;
            font-weight: 600;
            cursor: pointer;
            min-width: 45px;
            flex: 1;
            text-align: center;
            transition: all 0.05s;
            box-shadow: 0 1px 3px rgba(0,0,0,0.4);
            text-transform: uppercase;
            flex-shrink: 0;
            touch-action: manipulation;
        }
        .kb-btn:active { background: #444; transform: translateY(1px); box-shadow: none; }
        .kb-btn.active { background: #007acc; border-color: #009eff; color: white; box-shadow: 0 0 8px rgba(0,122,204,0.5); }
        .kb-btn.special { background: #3d3d3d; }
        .kb-btn.danger { background: #552222; }
        .kb-btn.success { background: #1e7e34; border-color: #28a745; }
        .kb-btn.char { text-transform: none; min-width: 38px; font-size: 14px; padding: 8px 0; }

        .kb-input-wrap { display: flex; flex: 3; gap: 4px; min-width: 150px; }
        .kb-input {
            flex: 1;
            background: #000;
            color: #00ff00;
            border: 1px solid #444;
            padding: 10px;
            border-radius: 6px;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 16px;            /* 16px prevents iOS auto-zoom on focus */
            outline: none;
            min-width: 50px;
        }
        .kb-input:focus { border-color: #007acc; }
        .send-btn { flex: 0.6; min-width: 60px; }
        .enter-btn { flex: 1; font-weight: bold; min-width: 80px; }
    </style>
</head>
<body>
    <div id="container">
        <iframe src="/ttyd/" id="terminal-frame"></iframe>

        <div id="kb-bar">
            <!-- Row 1: Modifiers & Navigation -->
            <div class="kb-row">
                <div class="kb-btn special" onmousedown="event.preventDefault(); sendKey('Esc')">Esc</div>
                <div class="kb-btn special" onmousedown="event.preventDefault(); sendKey('Tab')">Tab</div>
                <div id="ctrl-toggle"  class="kb-btn" onmousedown="event.preventDefault(); toggleMod('Ctrl')">Ctrl</div>
                <div id="alt-toggle"   class="kb-btn" onmousedown="event.preventDefault(); toggleMod('Alt')">Alt</div>
                <div id="shift-toggle" class="kb-btn" onmousedown="event.preventDefault(); toggleMod('Shift')">Shift</div>
                <div class="kb-btn danger" onmousedown="event.preventDefault(); sendKey('Ctrl-C')">^C</div>
                <div class="kb-btn" onmousedown="event.preventDefault(); sendKey('Left')">◀</div>
                <div class="kb-btn" onmousedown="event.preventDefault(); sendKey('Up')">▲</div>
                <div class="kb-btn" onmousedown="event.preventDefault(); sendKey('Down')">▼</div>
                <div class="kb-btn" onmousedown="event.preventDefault(); sendKey('Right')">▶</div>
            </div>

            <!-- Row 2: Numbers & Symbols (scrollable) -->
            <div class="kb-row">
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('1')">1</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('2')">2</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('3')">3</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('4')">4</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('5')">5</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('6')">6</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('7')">7</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('8')">8</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('9')">9</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('0')">0</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('/')">/</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('-')">-</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('_')">_</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('=')">=</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('+')">+</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('|')">|</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('\\\\')">\</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey(':')">:</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey(';')">;</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('\\\'')">'</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('\\\"')">"</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('?')">?</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('!')">!</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('@')">@</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('#')">#</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('$')">$</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('.')">.</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey(',')">,</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('<')">&lt;</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('>')">&gt;</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('(')">(</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey(')')">)</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('[')">[</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey(']')">]</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('{')">{</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('}')">}</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('`')">`</div>
                <div class="kb-btn char" onmousedown="event.preventDefault(); sendKey('~')">~</div>
            </div>

            <!-- Row 3: Free-form text input -->
            <div class="kb-row">
                <div class="kb-input-wrap">
                    <input type="text" id="kb-text" class="kb-input" placeholder="Text..." autocomplete="off" autocapitalize="none" spellcheck="false">
                </div>
                <div class="kb-btn special enter-btn" onmousedown="event.preventDefault(); sendKey('Enter')">RET</div>
                <div class="kb-btn success send-btn"  onmousedown="event.preventDefault(); sendText()">SEND</div>
            </div>
        </div>
    </div>

    <script>
        // ── Sticky modifier state ──────────────────────────────────────────
        let mods = { Ctrl: false, Alt: false, Shift: false };
        let termInstance = null;
        const input = document.getElementById('kb-text');

        function toggleMod(m) {
            mods[m] = !mods[m];
            document.getElementById(m.toLowerCase() + '-toggle').classList.toggle('active', mods[m]);
            input.focus();
        }
        function resetMods() {
            mods.Ctrl = mods.Alt = mods.Shift = false;
            ['ctrl', 'alt', 'shift'].forEach(id =>
                document.getElementById(id + '-toggle').classList.remove('active'));
        }

        // ── Iframe / terminal handles ──────────────────────────────────────
        function getIframeWindow() {
            const f = document.getElementById('terminal-frame');
            return f ? f.contentWindow : null;
        }

        // Fallback: walk the iframe window looking for an xterm.js instance
        // (one that exposes .send() and either .element or ._core). Used only
        // if postMessage isn't being honored by the upstream page.
        function findTerminalRecursively(obj, depth = 0) {
            if (!obj || depth > 3) return null;
            if (obj.send && (obj.element || obj._core)) return obj;
            for (const k of ['term', 'terminal', 'app', 'TTYD_TERMINAL', 'xterm']) {
                if (obj[k]) {
                    const found = findTerminalRecursively(obj[k], depth + 1);
                    if (found) return found;
                }
            }
            return null;
        }
        function getTerminal() {
            if (termInstance && termInstance.send) return termInstance;
            const win = getIframeWindow();
            if (!win) return null;
            try { termInstance = findTerminalRecursively(win); } catch (_) { /* cross-origin */ }
            return termInstance;
        }

        // ── Key translation (named key → bytes) ────────────────────────────
        // Extend KEY_MAP to add new chord shortcuts (e.g. 'Ctrl-R': '\x12').
        const KEY_MAP = {
            'Esc':    '\x1b',
            'Tab':    '\t',         // overridden to '\x1b[Z' if Shift armed
            'Enter':  '\r',
            'Up':     '\x1b[A',
            'Down':   '\x1b[B',
            'Right':  '\x1b[C',
            'Left':   '\x1b[D',
            'Ctrl-C': '\x03',
            'Ctrl-D': '\x04',
            'Ctrl-L': '\x0c',
            'Ctrl-Z': '\x1a',
            'Ctrl-W': '\x17',
        };

        function sendKey(key) {
            const win = getIframeWindow();
            if (!win) return;

            // Shift+Tab is a different sequence
            let data = key === 'Tab' && mods.Shift ? '\x1b[Z' : KEY_MAP[key];

            if (!data) {
                // Single printable char path with optional modifiers
                if (key.length === 1) {
                    if (mods.Ctrl) {
                        // Ctrl-A → 0x01, Ctrl-Z → 0x1A; only meaningful for letters
                        data = String.fromCharCode(key.toUpperCase().charCodeAt(0) - 64);
                    } else if (mods.Alt) {
                        data = '\x1b' + key;        // Alt-X → ESC X
                    } else if (mods.Shift) {
                        data = key.toUpperCase();
                    } else {
                        data = key;
                    }
                } else {
                    data = key; // unknown named key → literal
                }
            } else if (key.length > 1 && !key.startsWith('Ctrl-') && mods.Alt) {
                // Alt + arrow / Alt + Esc etc.
                data = '\x1b' + data;
            }

            if (data) postToTerminal(win, data);
            resetMods();
            input.focus();
        }

        function sendText() {
            const win = getIframeWindow();
            if (input.value && win) {
                postToTerminal(win, input.value + '\r');
                input.value = '';
            }
            resetMods();
            input.focus();
        }

        function postToTerminal(win, data) {
            // Primary path: postMessage. Upstream page (or injected listener)
            // is expected to call term.send(e.data.data).
            win.postMessage({ type: 'input', data }, '*');

            // Fallback: same-origin direct call if postMessage isn't wired.
            const term = getTerminal();
            if (term && term.send) {
                try { term.send(data); } catch (_) { /* already handled */ }
            }
        }

        // ── Physical keyboard bridge (when a Bluetooth keyboard is paired) ─
        input.addEventListener('keydown', (e) => {
            const specialKeys = ['Tab', 'Escape'];
            const isSpecial = specialKeys.includes(e.key) || e.key.startsWith('Arrow');
            if (mods.Ctrl || mods.Alt || mods.Shift || isSpecial) {
                if (e.key.length === 1 || isSpecial) {
                    e.preventDefault();
                    let k = e.key;
                    if (k === 'Escape') k = 'Esc';
                    if (k.startsWith('Arrow')) k = k.slice(5); // ArrowUp → Up
                    sendKey(k);
                }
            } else if (e.key === 'Enter') {
                e.preventDefault();
                sendText();
            }
        });

        // Autofocus the input so the soft keyboard pops up on page load.
        window.addEventListener('load', () => setTimeout(() => input.focus(), 500));
    </script>
</body>
</html>
```

---

## 4. Integration variants

### 4a. Upstream page already accepts `postMessage({type:'input', data})`

Nothing to do. The wrapper above works unmodified.

### 4b. Upstream is xterm.js but no message listener (most ttyd builds)

Same-origin: the `getTerminal()` fallback walks the iframe window and calls `term.send(data)` directly.

If that fails (the bundle hides the instance), inject a listener into the upstream page. Two ways:

**Option 1 — patch the upstream HTML** (preferred when you control the server):

```html
<!-- inject before </body> in the upstream terminal page -->
<script>
window.addEventListener('message', (e) => {
    if (e.data && e.data.type === 'input' && typeof e.data.data === 'string') {
        // ttyd exposes the terminal as window.term in most builds
        const t = window.term || (window.TTYD_TERMINAL && window.TTYD_TERMINAL.term);
        if (t && t.send) t.send(e.data.data);
    }
});
</script>
```

**Option 2 — proxy with a tiny rewriter.** If the terminal is served by ttyd at `/ttyd/` and you're fronting it (nginx, Caddy, Tailscale `serve`), use a sub_filter/rewrite to inject the script. Example nginx:

```nginx
location /ttyd/ {
    proxy_pass http://127.0.0.1:7681/;
    sub_filter '</body>' '<script>window.addEventListener("message",e=>{if(e.data&&e.data.type==="input"){const t=window.term;if(t&&t.send)t.send(e.data.data);}});</script></body>';
    sub_filter_once on;
    proxy_set_header Accept-Encoding "";   # required so sub_filter sees plain HTML
}
```

### 4c. Upstream is a different terminal (Wetty, gotty, custom xterm.js)

- **Wetty / gotty:** both expose `window.term` (xterm.js) — Option 1 works as-is.
- **Custom WebSocket terminals:** replace `t.send(data)` with whatever your client uses to push bytes upstream (often `ws.send(data)` or `socket.emit('input', data)`).

### 4d. Cross-origin iframe

`postMessage` still works across origins. The `getTerminal()` fallback will silently fail (DOM access blocked) — that's expected. You **must** inject the listener (4b option 1 or 2) on the upstream side; there's no other way in.

---

## 5. Customization recipes

| Want to… | Do this |
| --- | --- |
| Add a new chord (e.g. Ctrl-R reverse-search) | Add `'Ctrl-R': '\x12'` to `KEY_MAP`, then add a button: `<div class="kb-btn danger" onmousedown="event.preventDefault(); sendKey('Ctrl-R')">^R</div>` |
| Add F-keys | Map them in `KEY_MAP`: `'F1':'\x1bOP','F2':'\x1bOQ','F3':'\x1bOR','F4':'\x1bOS','F5':'\x1b[15~','F6':'\x1b[17~',…` |
| Page Up / Down / Home / End | `'Home':'\x1b[H','End':'\x1b[F','PgUp':'\x1b[5~','PgDn':'\x1b[6~'` |
| Macro buttons (e.g. inject `git status\r`) | New button: `onmousedown="event.preventDefault(); postToTerminal(getIframeWindow(),'git status\r')"` |
| Theme it light | Swap the dark hex values in CSS — keep the `.active`/`.danger`/`.success` semantics |
| Hide the bar in landscape | `@media (orientation: landscape) and (max-height: 500px) { #kb-bar { display: none; } }` |
| Stop the soft keyboard from appearing automatically | Remove the `setTimeout(...input.focus()...)` in the load listener and set `inputmode="none"` on `#kb-text` |

---

## 6. Critical implementation rules — do not violate

1. **Use `onmousedown` with `event.preventDefault()`, not `onclick`.** `onclick` fires after blur, which dismisses the soft keyboard between every tap. `mousedown` + preventDefault keeps focus on the text input.
2. **`#kb-text` font-size must be ≥ 16px.** iOS Safari auto-zooms on focus into any input smaller than that.
3. **`touch-action: manipulation`** on `.kb-btn` is what kills the 300 ms tap delay — don't drop it.
4. **`padding-bottom: env(safe-area-inset-bottom, …)`** on `#kb-bar` so the home-indicator on notched iPhones doesn't overlap the row.
5. **`viewport-fit=cover`** in the meta tag is required for `env(safe-area-inset-*)` to resolve to non-zero.
6. Modifiers are **sticky** (tap once → armed → consumed by next key) and **auto-clear** after every send. Don't make them momentary.
7. Ctrl-letter math (`charCodeAt - 64`) only makes sense for ASCII letters A–Z. Don't apply it to digits or symbols — pass those through unchanged.
8. Shift+Tab is `\x1b[Z`, not `\t`. Handle it before falling into the generic branch.
9. Always call `resetMods()` and `input.focus()` after a send — both for UX and so a re-armed Ctrl doesn't leak into the next tap.
10. Use `postMessage` first, terminal-walk second. The walk fails on cross-origin and is brittle across xterm.js versions; postMessage is the durable contract.

---

## 7. Verification checklist

After implementing, verify on a real phone (not just devtools' device emulator):

- [ ] Tap **Esc** in vim → exits insert mode.
- [ ] Tap **Tab** at a shell prompt → completes.
- [ ] Tap **Shift** then **Tab** → reverse-completes / cycles backward.
- [ ] Tap **Ctrl** then **C** in the input field → sends SIGINT.
- [ ] Tap **^C** button while a command is running → kills it.
- [ ] Arrow buttons move the cursor in vim and recall history at the shell.
- [ ] Type `ls -la` in the input field, tap **SEND** → executes (`ls -la\n`).
- [ ] Type `htop`, tap **RET** instead of SEND → also executes (Enter sent).
- [ ] Pipe `|`, brackets `[]`, backslash `\`, quotes `'"` all reach the terminal as the right byte.
- [ ] After a Ctrl-tap, the blue active state clears as soon as the next key is sent.
- [ ] On iPhone with a notch, the bottom row sits above the home indicator, not under it.
- [ ] Pinch-zoom does nothing (viewport meta blocks it).
- [ ] Soft keyboard appears on load and stays up between button taps.

If any item fails, re-read the matching rule in §6 before changing the spec.

---

## 8. Output format

Return a single HTML file. No README, no build instructions, no commentary unless the user explicitly asks. If you injected a listener into the upstream page (variant 4b/4c), include that injection as a second file or a clearly delimited code block, and state which option (HTML patch vs. proxy rewrite) you chose and why.
