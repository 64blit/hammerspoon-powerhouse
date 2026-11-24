-------------------------------------------------
-- Unified Command Palette (Option + Z)
-- Spotlight-style HUD for all Hammerspoon tools, AI actions, and shortcuts.
-------------------------------------------------

local M = {}
local webview = require("hs.webview")

local paletteWindow = nil

-- All available actions in the Command Palette
local COMMANDS = {
    -- AI Copilot & Transforms
    {
        id = "ai_chat",
        title = "Open AI Chatbox",
        category = "AI Copilot",
        icon = "💬",
        shortcut = "⌃⌥⌘A",
        keywords = "ai chat chatbox openrouter gemini claude grok llm ask",
        fn = function()
            local chat = require("ai_chatbox")
            chat.toggleChatbox()
        end
    },
    {
        id = "refine_coding",
        title = "Refine Selection: For Coding Prompt",
        category = "Text Refiner",
        icon = "🛠️",
        shortcut = "⌃⌥⌘D",
        keywords = "refine coding prompt dictation clean vibe code",
        fn = function()
            local refiner = require("text_refiner")
            refiner.refineCoding()
        end
    },
    {
        id = "refine_chat",
        title = "Refine Selection: For Chat / DM",
        category = "Text Refiner",
        icon = "✨",
        shortcut = "⌃⌥⌘F",
        keywords = "refine chat dm message grammar polish spelling tone",
        fn = function()
            local refiner = require("text_refiner")
            refiner.refineChat()
        end
    },
    {
        id = "refine_email",
        title = "Refine Selection: Format as Email",
        category = "Text Refiner",
        icon = "✉️",
        shortcut = "⌃⌥⌘G",
        keywords = "refine email format professional polish write",
        fn = function()
            local refiner = require("text_refiner")
            refiner.refineEmail()
        end
    },
    {
        id = "refine_translate_es",
        title = "Translate Selection: English → Spanish",
        category = "Text Refiner",
        icon = "🇲🇽",
        shortcut = "⌃⌥⌘S",
        keywords = "translate spanish english es es-mx",
        fn = function()
            local refiner = require("text_refiner")
            refiner.translateToSpanish()
        end
    },
    {
        id = "refine_translate_en",
        title = "Translate Selection: Spanish → English",
        category = "Text Refiner",
        icon = "🇺🇸",
        shortcut = "⌃⌥⌘E",
        keywords = "translate english spanish en",
        fn = function()
            local refiner = require("text_refiner")
            refiner.translateToEnglish()
        end
    },

    -- Audio / Read Aloud
    {
        id = "read_aloud",
        title = "Read Aloud Selection (TTS)",
        category = "Audio",
        icon = "🔊",
        shortcut = "⌃⌥S",
        keywords = "tts text to speech read aloud speak voice audio kokoro",
        fn = function()
            hs.eventtap.keyStroke({"ctrl", "alt"}, "S")
        end
    },
    {
        id = "summarize_aloud",
        title = "Summarize Selection Aloud (Cliffnotes TTS)",
        category = "Audio",
        icon = "🗒️",
        shortcut = "⌃⌥⇧S",
        keywords = "tts summarize summary cliffnotes key ideas skim read aloud speak voice audio",
        fn = function()
            hs.eventtap.keyStroke({"ctrl", "alt", "shift"}, "S")
        end
    },

    -- Screen, Vision & Capture
    {
        id = "mouse_magnifier",
        title = "Mouse Magnifier & Screen Recorder",
        category = "Capture",
        icon = "🔍",
        shortcut = "⌃⌥⌘M",
        keywords = "mouse magnifier zoom recording gif mp4 webm screen capture",
        fn = function()
            local mm = require("mouse_magnifier")
            mm.toggle()
        end
    },
    {
        id = "screen_translator",
        title = "Screen Translator & OCR Overlay",
        category = "Vision",
        icon = "🈳",
        shortcut = "⌃⌥⌘Y",
        keywords = "screen translator ocr vision translation japanese chinese korean",
        fn = function()
            local tr = require("window_translator")
            tr.toggle()
        end
    },
    {
        id = "scrape_images",
        title = "Scrape Images from Website URL",
        category = "Capture",
        icon = "🖼️",
        shortcut = "",
        keywords = "scrape images pictures download website url extract gallery photos",
        fn = function()
            local scraper = require("image_scraper")
            scraper.promptScrapeImages()
        end
    },
    {
        id = "open_scraped_images",
        title = "Open Scraped Images Folder",
        category = "Capture",
        icon = "📁",
        shortcut = "",
        keywords = "open scraped images folder directory downloads gallery",
        fn = function()
            local scraper = require("image_scraper")
            scraper.openImagesFolder()
        end
    },

    -- Terminal, Display & Window Utilities
    {
        id = "terminal_toggle",
        title = "Web Terminal & Mobile QR Link",
        category = "Terminal",
        icon = "🐚",
        shortcut = "⌘⌥M",
        keywords = "terminal ttyd web shell tailscale qr pairing mobile",
        fn = function()
            local tt = require("terminal_toggle")
            tt.toggle()
        end
    },
    {
        id = "window_pip",
        title = "Window Picture-in-Picture Overlay",
        category = "Window",
        icon = "🖼️",
        shortcut = "⌃⌥⌘T",
        keywords = "window pip picture overlay float pin mirror",
        fn = function()
            hs.eventtap.keyStroke({"ctrl", "alt", "cmd"}, "T")
        end
    },
    {
        id = "keystroke_hud",
        title = "Keystroke Visualizer HUD",
        category = "Tools",
        icon = "⌨️",
        shortcut = "⌃⌥⌘K",
        keywords = "keystroke visualizer hud keys overlay shortcuts demo",
        fn = function()
            local kv = require("keystroke_visualizer")
            kv.toggle()
        end
    },
    {
        id = "nightshade_toggle",
        title = "Nightshade: Toggle Screen Redshift",
        category = "Display",
        icon = "🌅",
        shortcut = "",
        keywords = "nightshade redshift flux orange warm screen overlay display",
        fn = function()
            local ns = require("nightshade")
            ns.toggle()
        end
    },
    {
        id = "clipboard_tool",
        title = "Clipboard History Manager",
        category = "System",
        icon = "📋",
        shortcut = "⌘⌥V",
        keywords = "clipboard history pasteboard copy paste clips",
        fn = function()
            hs.eventtap.keyStroke({"cmd", "alt"}, "v")
        end
    },
    {
        id = "caffeine_toggle",
        title = "Caffeine: Toggle Sleep Prevention",
        category = "System",
        icon = "☕",
        shortcut = "⌃⌥⌘C",
        keywords = "caffeine awake sleep prevent display stay on",
        fn = function()
            if spoon and spoon.Caffeine then
                spoon.Caffeine:toggle()
            end
        end
    },
    {
        id = "install_dependencies",
        title = "Install Tools & Dependencies (Homebrew)",
        category = "System",
        icon = "📦",
        shortcut = "",
        keywords = "install tools brew dependencies ffmpeg uv gifski",
        fn = function()
            local it = require("install_tools")
            it.installAll()
        end
    },
    {
        id = "reload_config",
        title = "Reload Hammerspoon Configuration",
        category = "System",
        icon = "🔄",
        shortcut = "",
        keywords = "reload hammerspoon restart refresh config lua",
        fn = function()
            hs.reload()
        end
    },
}

local function getCommandsJson()
    local list = {}
    for _, c in ipairs(COMMANDS) do
        table.insert(list, {
            id = c.id,
            title = c.title,
            category = c.category,
            icon = c.icon,
            shortcut = c.shortcut or "",
            keywords = c.keywords or "",
        })
    end
    return hs.json.encode(list)
end

local PALETTE_HTML = [=[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  :root {
      --bg: #1c1c1e;
      --bg-card: #28282b;
      --bg-hover: #2563eb;
      --bg-selected: #2563eb;
      --border: rgba(255, 255, 255, 0.12);
      --text: #f3f4f6;
      --text-dim: #9ca3af;
      --text-muted: #6b7280;
      --accent: #3b82f6;
      --badge-bg: rgba(255, 255, 255, 0.08);
      --badge-text: #cbd5e1;
      --shortcut-bg: rgba(0, 0, 0, 0.35);
  }
  * { box-sizing: border-box; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    margin: 0;
    padding: 0;
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    user-select: none;
    -webkit-user-select: none;
    border-radius: 12px;
    border: 1px solid var(--border);
  }
  .search-container {
    display: flex;
    align-items: center;
    padding: 14px 18px;
    border-bottom: 1px solid var(--border);
    gap: 12px;
    background: #141416;
  }
  .search-icon {
    font-size: 18px;
    opacity: 0.7;
  }
  .search-input {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    color: var(--text);
    font-size: 16px;
    font-weight: 400;
  }
  .search-input::placeholder {
    color: var(--text-muted);
    font-size: 14.5px;
  }
  .mode-badge {
    display: none;
    background: var(--accent);
    color: white;
    font-size: 11px;
    font-weight: 600;
    padding: 3px 8px;
    border-radius: 4px;
    text-transform: uppercase;
  }
  .list-container {
    flex: 1;
    overflow-y: auto;
    padding: 8px;
  }
  .list-container::-webkit-scrollbar {
    width: 6px;
  }
  .list-container::-webkit-scrollbar-thumb {
    background: rgba(255, 255, 255, 0.15);
    border-radius: 3px;
  }
  .command-item {
    display: flex;
    align-items: center;
    padding: 10px 14px;
    border-radius: 8px;
    cursor: pointer;
    gap: 12px;
    transition: background 0.08s ease;
  }
  .command-item:hover, .command-item.selected {
    background: var(--bg-selected);
    color: white;
  }
  .item-icon {
    font-size: 18px;
    width: 24px;
    text-align: center;
  }
  .item-details {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    overflow: hidden;
  }
  .item-title {
    font-size: 14px;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .item-category {
    font-size: 11px;
    color: var(--text-dim);
  }
  .command-item:hover .item-category, .command-item.selected .item-category {
    color: rgba(255, 255, 255, 0.8);
  }
  .item-shortcut {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    font-size: 12px;
    padding: 3px 8px;
    border-radius: 5px;
    background: var(--shortcut-bg);
    color: var(--badge-text);
    border: 1px solid rgba(255, 255, 255, 0.08);
  }
  .command-item:hover .item-shortcut, .command-item.selected .item-shortcut {
    border-color: rgba(255, 255, 255, 0.3);
    color: white;
  }
  .footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 18px;
    border-top: 1px solid var(--border);
    font-size: 11.5px;
    color: var(--text-dim);
    background: #141416;
  }
  .footer-hints {
    display: flex;
    gap: 14px;
  }
  .hint-key {
    background: rgba(255, 255, 255, 0.1);
    padding: 2px 5px;
    border-radius: 3px;
    font-family: ui-monospace, monospace;
    font-size: 10.5px;
    color: var(--text);
  }
  .empty-state {
    padding: 30px 20px;
    text-align: center;
    color: var(--text-muted);
    font-size: 14px;
  }
</style>
</head>
<body>
  <div class="search-container">
    <span class="search-icon">⚡</span>
    <span id="modeBadge" class="mode-badge">AI Chat</span>
    <input type="text" id="searchInput" class="search-input" placeholder="Search commands or type /chat to open AI..." autofocus>
  </div>

  <div id="listContainer" class="list-container"></div>

  <div class="footer">
    <div class="footer-hints">
      <span><span class="hint-key">↑↓</span> Navigate</span>
      <span><span class="hint-key">↵</span> Run</span>
      <span><span class="hint-key">esc</span> Dismiss</span>
    </div>
    <div style="opacity: 0.8;">
      <b>Hammerspoon Powerhouse</b>
    </div>
  </div>

  <script>
    const ALL_COMMANDS = COMMANDS_PLACEHOLDER;
    let filtered = [...ALL_COMMANDS];
    let selectedIndex = 0;

    const searchInput = document.getElementById('searchInput');
    const listContainer = document.getElementById('listContainer');
    const modeBadge = document.getElementById('modeBadge');

    function sendToHammerspoon(payload) {
      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.paletteHandler) {
          window.webkit.messageHandlers.paletteHandler.postMessage(JSON.stringify(payload));
        }
      } catch (err) {
        console.error("Hammerspoon message error:", err);
      }
    }

    function renderList() {
      if (filtered.length === 0) {
        listContainer.innerHTML = `
          <div class="empty-state">
            <p>No matching commands found.</p>
          </div>
        `;
        return;
      }

      let html = "";
      filtered.forEach((cmd, idx) => {
        const isSel = idx === selectedIndex;
        html += `
          <div class="command-item ${isSel ? 'selected' : ''}" onclick="runIndex(${idx})" onmouseenter="selectIndex(${idx})">
            <span class="item-icon">${cmd.icon || '⚡'}</span>
            <div class="item-details">
              <span class="item-title">${escapeHtml(cmd.title)}</span>
              <span class="item-category">${escapeHtml(cmd.category)}</span>
            </div>
            ${cmd.shortcut ? `<span class="item-shortcut">${escapeHtml(cmd.shortcut)}</span>` : ''}
          </div>
        `;
      });

      listContainer.innerHTML = html;

      const selectedEl = listContainer.querySelector('.selected');
      if (selectedEl) {
        selectedEl.scrollIntoView({ block: 'nearest' });
      }
    }

    function selectIndex(idx) {
      selectedIndex = idx;
      const items = listContainer.querySelectorAll('.command-item');
      items.forEach((el, i) => {
        el.classList.toggle('selected', i === idx);
      });
    }

    function filterCommands() {
      const raw = searchInput.value.trim();
      const q = raw.toLowerCase();

      if (!raw) {
        modeBadge.style.display = 'none';
        filtered = [...ALL_COMMANDS];
      } else if (q.startsWith('/chat ') || q.startsWith('chat ') || q.startsWith('/ai ') || q.startsWith('ai ')) {
        modeBadge.style.display = 'inline-block';
        modeBadge.textContent = 'AI Chat';
        const chatQ = raw.replace(/^\/?(?:chat|ai)\s+/i, '');
        filtered = [
          {
            id: "custom_chat",
            title: `Open AI Chatbox: "${chatQ}"`,
            category: "AI Copilot",
            icon: "💬",
            shortcut: "↵",
            query: chatQ
          }
        ];
      } else {
        modeBadge.style.display = 'none';
        const matched = ALL_COMMANDS.filter(cmd => {
          const matchTitle = cmd.title.toLowerCase().includes(q);
          const matchCat = cmd.category.toLowerCase().includes(q);
          const matchKw = cmd.keywords && cmd.keywords.toLowerCase().includes(q);
          return matchTitle || matchCat || matchKw;
        });

        filtered = matched.length > 0 ? matched : [
          {
            id: "custom_chat",
            title: `Ask AI Chatbox: "${raw}"`,
            category: "AI Copilot",
            icon: "💬",
            shortcut: "↵",
            query: raw
          }
        ];
      }

      selectedIndex = 0;
      renderList();
    }

    function runIndex(idx) {
      if (idx >= 0 && idx < filtered.length) {
        const cmd = filtered[idx];
        sendToHammerspoon({ action: cmd.id, query: cmd.query || searchInput.value.trim() });
      }
    }

    searchInput.addEventListener('input', filterCommands);

    window.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        selectedIndex = (selectedIndex + 1) % (filtered.length || 1);
        renderList();
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        selectedIndex = (selectedIndex - 1 + (filtered.length || 1)) % (filtered.length || 1);
        renderList();
      } else if (e.key === 'Enter') {
        e.preventDefault();
        runIndex(selectedIndex);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        sendToHammerspoon({ action: "close" });
      }
    });

    function escapeHtml(str) {
      return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    renderList();
  </script>
</body>
</html>
]=]

-------------------------------------------------
-- Palette Window Management
-------------------------------------------------
function M.toggle()
    if paletteWindow then
        paletteWindow:delete()
        paletteWindow = nil
        return
    end

    local rect = {x = 0, y = 0, w = 680, h = 440}
    local screen = hs.screen.mainScreen()
    local frame = screen:fullFrame()
    rect.x = frame.x + (frame.w - rect.w) / 2
    rect.y = frame.y + (frame.h - rect.h) * 0.28

    local userContent = hs.webview.usercontent.new("paletteHandler")
    userContent:setCallback(function(msg)
        local raw = msg.body
        local data = {}
        if type(raw) == "string" then
            data = hs.json.decode(raw) or { action = raw }
        elseif type(raw) == "table" then
            data = raw
        end

        if data.action == "close" then
            M.close()
            return
        end

        if data.action then
            M.close()
            hs.timer.doAfter(0.05, function()
                M.handleAction(data.action, data.query)
            end)
        end
    end)

    local prefs = {}
    prefs.developerExtrasEnabled = true
    paletteWindow = webview.new(rect, prefs, userContent)

    paletteWindow:windowStyle(0) -- borderless floating spotlight
    paletteWindow:level(hs.drawing.windowLevels.floating)
    paletteWindow:allowGestures(false)
    paletteWindow:allowTextEntry(true)
    paletteWindow:deleteOnClose(true)
    paletteWindow:windowCallback(function(action)
        if action == "closing" then
            paletteWindow = nil
        end
    end)

    local commandsJson = getCommandsJson()
    local html = PALETTE_HTML:gsub("COMMANDS_PLACEHOLDER", function() return commandsJson end)
    paletteWindow:html(html)
    paletteWindow:show()

    hs.timer.doAfter(0.1, function()
        if paletteWindow then
            local win = paletteWindow:hswindow()
            if win then win:focus() end
        end
    end)
end

function M.close()
    if paletteWindow then
        paletteWindow:delete()
        paletteWindow = nil
    end
end

function M.handleAction(actionId, query)
    if not actionId then return end

    if actionId == "custom_chat" then
        local chat = require("ai_chatbox")
        chat.toggleChatbox()
        return
    end

    for _, cmd in ipairs(COMMANDS) do
        if cmd.id == actionId and cmd.fn then
            cmd.fn()
            return
        end
    end
end

-- Allow local_init.lua or private modules to register extra palette commands
function M.registerCommand(cmd)
    if type(cmd) ~= "table" or not cmd.id or not cmd.title then return end
    for i, existing in ipairs(COMMANDS) do
        if existing.id == cmd.id then
            COMMANDS[i] = cmd
            return
        end
    end
    table.insert(COMMANDS, cmd)
end

-- Bind Option + Z global hotkey
hs.hotkey.bind({"alt"}, "z", function()
    M.toggle()
end)

return M
