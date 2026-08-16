-------------------------------------------------
-- Unified Command Palette (Option + Z)
-- Spotlight-style HUD for all Hammerspoon actions,
-- Code Intelligence, AI tools, and system shortcuts.
-------------------------------------------------

local M = {}
local webview = require("hs.webview")
local env = require("env_loader")

local paletteWindow = nil

-- Define all available actions in the Command Palette
local COMMANDS = {
    -- Code Intelligence
    {
        id = "code_search",
        title = "Semantic Code Search (HUD)",
        category = "Code Intel",
        icon = "🔍",
        shortcut = "⌃⌥⌘K",
        keywords = "search code intel semantic bge vector chromadb pattern query",
        fn = function()
            local ci = require("code_intel")
            ci.toggleSearchHUD()
        end
    },
    {
        id = "code_search_selection",
        title = "Search Selected Code / Error",
        category = "Code Intel",
        icon = "🔎",
        shortcut = "⌃⌥⌘S",
        keywords = "search selection error highlighted code pattern",
        fn = function()
            local ci = require("code_intel")
            ci.searchSelection()
        end
    },
    {
        id = "code_ingest_folder",
        title = "Ingest Codebase / Folder",
        category = "Code Intel",
        icon = "📥",
        shortcut = "⌃⌥⌘I",
        keywords = "ingest scan folder codebase index tags vector repository",
        fn = function()
            local ci = require("code_intel")
            ci.promptIngestFolder()
        end
    },
    {
        id = "code_scrape_md",
        title = "Scrape Website URL to Markdown",
        category = "Code Intel",
        icon = "🕸️",
        shortcut = "",
        keywords = "scrape crawl website url markdown docset distill",
        fn = function()
            local ci = require("code_intel")
            ci.promptScrapeURL("markdown")
        end
    },
    {
        id = "code_ingest_docs",
        title = "Ingest Documentation URL to Vector DB",
        category = "Code Intel",
        icon = "📚",
        shortcut = "",
        keywords = "ingest docs documentation url crawl index vector",
        fn = function()
            local ci = require("code_intel")
            ci.promptScrapeURL("ingest")
        end
    },
    {
        id = "code_restart_server",
        title = "Restart Code Intelligence Server",
        category = "Code Intel",
        icon = "🔄",
        shortcut = "",
        keywords = "restart server code intel mcp fast api",
        fn = function()
            local ci = require("code_intel")
            ci.restartServer()
        end
    },
    {
        id = "code_view_logs",
        title = "View Code Intelligence Server Logs",
        category = "Code Intel",
        icon = "📜",
        shortcut = "",
        keywords = "logs server tail code intel",
        fn = function()
            local ci = require("code_intel")
            ci.openLogs()
        end
    },

    -- AI Tools
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
        id = "refine_summarize",
        title = "Refine: Summarize Selection",
        category = "Text Refiner",
        icon = "📝",
        shortcut = "",
        keywords = "refine summarize summary selection text shorten tl;dr",
        fn = function()
            local refiner = require("text_refiner")
            refiner.summarize()
        end
    },
    {
        id = "refine_grammar",
        title = "Refine: Fix Grammar & Polish",
        category = "Text Refiner",
        icon = "✨",
        shortcut = "",
        keywords = "refine fix grammar polish spelling tone improve",
        fn = function()
            local refiner = require("text_refiner")
            refiner.fixGrammar()
        end
    },
    {
        id = "refine_explain",
        title = "Refine: Explain Selection",
        category = "Text Refiner",
        icon = "💡",
        shortcut = "",
        keywords = "refine explain concept code selection teach clarify",
        fn = function()
            local refiner = require("text_refiner")
            refiner.explain()
        end
    },
    {
        id = "refine_code_review",
        title = "Refine: Code Review & Suggestions",
        category = "Text Refiner",
        icon = "🧐",
        shortcut = "",
        keywords = "refine code review audit bugs optimization refactor",
        fn = function()
            local refiner = require("text_refiner")
            refiner.codeReview()
        end
    },

    -- Vision & OCR
    {
        id = "screen_translator",
        title = "Screen Translator & OCR Overlay",
        category = "Vision",
        icon = "🈳",
        shortcut = "",
        keywords = "screen translator ocr vision translation japanese chinese korean",
        fn = function()
            local tr = require("window_translator")
            tr.toggle()
        end
    },

    -- Terminal & Utilities
    {
        id = "terminal_toggle",
        title = "Web Terminal & Mobile QR Link",
        category = "Terminal",
        icon = "🐚",
        shortcut = "",
        keywords = "terminal ttyd web shell tailscale qr pairing mobile",
        fn = function()
            local tt = require("terminal_toggle")
            tt.toggleServer()
        end
    },
    {
        id = "mouse_magnifier",
        title = "Mouse Magnifier & Screen Recorder",
        category = "Tools",
        icon = "🔍",
        shortcut = "",
        keywords = "mouse magnifier zoom recording gif screen capture",
        fn = function()
            local mm = require("mouse_magnifier")
            mm.toggle()
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
        id = "read_aloud",
        title = "Read Aloud Selection (TTS)",
        category = "Audio",
        icon = "🔊",
        shortcut = "⌃⌥S",
        keywords = "tts text to speech read aloud speak voice audio",
        fn = function()
            local tts = require("text_to_speech")
            hs.eventtap.keyStroke({"ctrl", "alt"}, "S")
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
        shortcut = "",
        keywords = "keystroke visualizer hud keys overlay shortcuts",
        fn = function()
            local kv = require("keystroke_visualizer")
            kv.toggle()
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
    -- Knowledge & Memory (Zettelkasten)
    {
        id = "zk_open_notes",
        title = "Open Zettelkasten Memory Notes",
        category = "Knowledge Graph",
        icon = "🧠",
        shortcut = "",
        keywords = "zettelkasten memory notes knowledge second brain obsidian concepts",
        fn = function()
            local home = os.getenv("HOME") or ""
            local notesDir = home .. "/Documents/_SPACE/knowledge/notes"
            hs.task.new("/usr/bin/open", nil, { notesDir }):start()
            hs.alert.show("🧠 Opened Zettelkasten Notes Folder", 2)
        end
    },
    {
        id = "zk_search_notes",
        title = "Search Zettelkasten Notes (/zk)",
        category = "Knowledge Graph",
        icon = "📖",
        shortcut = "",
        keywords = "zettelkasten search notes memory concepts references",
        fn = function()
            local btn, q = hs.dialog.textPrompt("Search Zettelkasten Memory", "Enter keyword or tag to search across memory notes:", "", "Search", "Cancel")
            if btn == "Search" and q and q ~= "" then
                local home = os.getenv("HOME") or ""
                local notesDir = home .. "/Documents/_SPACE/knowledge/notes"
                local cmd = string.format("cd %q && grep -inR %q .", notesDir, q)
                hs.task.new("/bin/bash", function(rc, out, err)
                    if rc == 0 and out and out ~= "" then
                        hs.dialog.blockAlert("Zettelkasten Search Results", out, "OK")
                    else
                        hs.alert.show("No matching notes found for: " .. q, 2)
                    end
                end, { "-lc", cmd }):start()
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

-- Convert commands table to JSON for Webview
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
      --bg: rgba(26, 26, 28, 0.95);
      --bg-card: rgba(38, 38, 42, 0.7);
      --bg-hover: #2563eb;
      --bg-selected: #1d4ed8;
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
    backdrop-filter: blur(24px);
    -webkit-backdrop-filter: blur(24px);
  }
  .search-container {
    display: flex;
    align-items: center;
    padding: 14px 18px;
    border-bottom: 1px solid var(--border);
    gap: 12px;
    background: rgba(20, 20, 22, 0.6);
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
    font-size: 17px;
    font-weight: 400;
  }
  .search-input::placeholder {
    color: var(--text-muted);
    font-size: 15px;
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
  .command-item.selected {
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
  .command-item.selected .item-category {
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
  .command-item.selected .item-shortcut {
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
    background: rgba(18, 18, 20, 0.5);
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
    <span id="modeBadge" class="mode-badge">Code</span>
    <input type="text" id="searchInput" class="search-input" placeholder="Type a command, or /code, /chat, /zk..." autofocus>
  </div>

  <div id="listContainer" class="list-container"></div>

  <div class="footer">
    <div class="footer-hints">
      <span><span class="hint-key">↑↓</span> Navigate</span>
      <span><span class="hint-key">↵</span> Run</span>
      <span><span class="hint-key">esc</span> Dismiss</span>
    </div>
    <div style="opacity: 0.8;">
      <b>64blit Powerhouse</b>
    </div>
  </div>

  <script>
    const ALL_COMMANDS = COMMANDS_PLACEHOLDER;
    let filtered = [...ALL_COMMANDS];
    let selectedIndex = 0;

    const searchInput = document.getElementById('searchInput');
    const listContainer = document.getElementById('listContainer');
    const modeBadge = document.getElementById('modeBadge');

    function renderList() {
      if (filtered.length === 0) {
        listContainer.innerHTML = `
          <div class="empty-state">
            <p>No exact command matches.</p>
            <p style="font-size:12px; color:#888;">Press <b>Enter</b> to search <b>${escapeHtml(searchInput.value)}</b> in Code Intelligence.</p>
          </div>
        `;
        return;
      }

      let html = "";
      filtered.forEach((cmd, idx) => {
        const isSel = idx === selectedIndex;
        html += `
          <div class="command-item ${isSel ? 'selected' : ''}" onclick="runIndex(${idx})">
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

      // Ensure active item is visible
      const selectedEl = listContainer.querySelector('.selected');
      if (selectedEl) {
        selectedEl.scrollIntoView({ block: 'nearest' });
      }
    }

    function filterCommands() {
      const q = searchInput.value.trim().toLowerCase();
      
      if (!q) {
        modeBadge.style.display = 'none';
        filtered = [...ALL_COMMANDS];
      } else if (q.startsWith('/code ') || q.startsWith('/search ')) {
        modeBadge.style.display = 'inline-block';
        modeBadge.textContent = 'Code Intel';
        const searchQ = q.replace(/^\/(?:code|search)\s+/, '');
        filtered = [
          {
            id: "custom_code_search",
            title: `Search Codebase for "${searchQ}"`,
            category: "Code Intelligence",
            icon: "🔍",
            shortcut: "↵",
            query: searchQ
          }
        ];
      } else if (q.startsWith('/chat ')) {
        modeBadge.style.display = 'inline-block';
        modeBadge.textContent = 'AI Chat';
        const chatQ = q.replace(/^\/chat\s+/, '');
        filtered = [
          {
            id: "custom_chat",
            title: `Ask AI: "${chatQ}"`,
            category: "AI Copilot",
            icon: "💬",
            shortcut: "↵",
            query: chatQ
          }
        ];
      } else if (q.startsWith('/zk ') || q.startsWith('/note ')) {
        modeBadge.style.display = 'inline-block';
        modeBadge.textContent = 'Zettelkasten';
        const noteQ = q.replace(/^\/(?:zk|note)\s+/, '');
        filtered = [
          {
            id: "custom_zk",
            title: `Search Memory Notes for "${noteQ}"`,
            category: "Knowledge Graph",
            icon: "🧠",
            shortcut: "↵",
            query: noteQ
          }
        ];
      } else {
        modeBadge.style.display = 'none';
        filtered = ALL_COMMANDS.filter(cmd => {
          const matchTitle = cmd.title.toLowerCase().includes(q);
          const matchCat = cmd.category.toLowerCase().includes(q);
          const matchKw = cmd.keywords && cmd.keywords.toLowerCase().includes(q);
          return matchTitle || matchCat || matchKw;
        });
      }

      selectedIndex = 0;
      renderList();
    }

    function runIndex(idx) {
      if (idx >= 0 && idx < filtered.length) {
        const cmd = filtered[idx];
        const payload = JSON.stringify({ action: cmd.id, query: cmd.query || searchInput.value.trim() });
        window.location.hash = "exec:" + encodeURIComponent(payload);
      } else if (searchInput.value.trim()) {
        // Fallback: search query in Code Intelligence
        const payload = JSON.stringify({ action: "code_search_query", query: searchInput.value.trim() });
        window.location.hash = "exec:" + encodeURIComponent(payload);
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
        window.location.hash = "close";
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

    local rect = {x = 0, y = 0, w = 680, h = 420}
    local screen = hs.screen.mainScreen()
    local frame = screen:fullFrame()
    rect.x = frame.x + (frame.w - rect.w) / 2
    rect.y = frame.y + (frame.h - rect.h) * 0.28 -- Place gracefully in upper-middle third

    local userContent = hs.webview.usercontent.new("paletteHandler")
    userContent:setCallback(function(msg)
        if type(msg.body) == "string" then
            if msg.body == "close" then
                M.close()
            elseif msg.body:match("^exec:") then
                local raw = hs.http.urlUnescape(msg.body:sub(6))
                local data = hs.json.decode(raw) or {}
                M.close()
                M.handleAction(data.action, data.query)
            end
        end
    end)

    local prefs = {}
    prefs.developerExtrasEnabled = true
    paletteWindow = webview.new(rect, prefs, userContent)
    
    -- Frameless, floating spotlight style
    paletteWindow:windowStyle(0) -- borderless
    paletteWindow:level(hs.drawing.windowLevels.floating)
    paletteWindow:allowGestures(false)
    paletteWindow:allowTextEntry(true)
    paletteWindow:deleteOnClose(true)
    paletteWindow:shadow(true)

    paletteWindow:windowCallback(function(action)
        if action == "closing" then
            paletteWindow = nil
        end
    end)

    local commandsJson = getCommandsJson()
    local html = PALETTE_HTML:gsub("COMMANDS_PLACEHOLDER", commandsJson)
    paletteWindow:html(html)
    paletteWindow:show()
    paletteWindow:hswindow():focus()
end

function M.close()
    if paletteWindow then
        paletteWindow:delete()
        paletteWindow = nil
    end
end

function M.handleAction(actionId, query)
    if not actionId then return end

    if actionId == "custom_code_search" or actionId == "code_search_query" then
        local ci = require("code_intel")
        ci.toggleSearchHUD(query)
        return
    elseif actionId == "custom_chat" then
        local chat = require("ai_chatbox")
        chat.toggleChatbox()
        return
    elseif actionId == "custom_zk" then
        local home = os.getenv("HOME") or ""
        local notesDir = home .. "/Documents/_SPACE/knowledge/notes"
        if query and query ~= "" then
            local cmd = string.format("cd %q && grep -inR %q .", notesDir, query)
            hs.task.new("/bin/bash", function(rc, out, err)
                if rc == 0 and out and out ~= "" then
                    hs.dialog.blockAlert(string.format("Zettelkasten Results for %q", query), out, "Open Notes Folder", "Close")
                    hs.task.new("/usr/bin/open", nil, { notesDir }):start()
                else
                    hs.alert.show("No memory notes found matching: " .. query, 2)
                    hs.task.new("/usr/bin/open", nil, { notesDir }):start()
                end
            end, { "-lc", cmd }):start()
        else
            hs.task.new("/usr/bin/open", nil, { notesDir }):start()
        end
        return
    end

    for _, cmd in ipairs(COMMANDS) do
        if cmd.id == actionId and cmd.fn then
            cmd.fn()
            return
        end
    end
end

-- Bind Option + Z global hotkey
hs.hotkey.bind({"alt"}, "z", function()
    M.toggle()
end)

return M
