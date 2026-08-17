-------------------------------------------------
-- 64blit Code Intelligence Module
-- Provides semantic code search, codebase ingestion,
-- and URL-to-Markdown scraping integrated with Hammerspoon.
-------------------------------------------------

local M = {}
local webview = require("hs.webview")
local env = require("env_loader")

local SERVER_URL = env.get("CODE_INTEL_URL", "http://127.0.0.1:9991")
local CLI_BIN = env.get("CODE_INTEL_BIN")

-- Auto-detect 64blit-code-intel CLI path if not explicitly provided
if not CLI_BIN or CLI_BIN == "" then
    local home = os.getenv("HOME") or ""
    local candidates = {
        home .. "/Documents/_SPACE/bin/64blit-code-intel",
        "/usr/local/bin/64blit-code-intel",
        "/opt/homebrew/bin/64blit-code-intel",
        home .. "/.local/bin/64blit-code-intel",
    }
    for _, p in ipairs(candidates) do
        if hs.fs.attributes(p) then
            CLI_BIN = p
            break
        end
    end
end
CLI_BIN = CLI_BIN or "64blit-code-intel"

local crawlsDir = env.get("CODE_INTEL_CRAWLS_DIR", (os.getenv("HOME") or "") .. "/Documents/Crawls")

-- State
local _isOnline = false
local _patternCount = 0
local _llmStatus = "checking..."
local _searchWindow = nil
local _statusTimer = nil
local _activeTask = nil

local codeIntelMenu = hs.menubar.new()

-------------------------------------------------
-- Server Status & Stats Check
-------------------------------------------------
function M.checkStatus(callback)
    local healthUrl = SERVER_URL .. "/health"
    hs.http.asyncGet(healthUrl, nil, function(code, body)
        if code == 200 then
            _isOnline = true
            -- Fetch stats via JSON-RPC
            local rpcBody = hs.json.encode({
                jsonrpc = "2.0",
                id = 1,
                method = "tools/call",
                params = { name = "stats", arguments = {} }
            })
            local headers = { ["Content-Type"] = "application/json" }
            hs.http.asyncPost(SERVER_URL .. "/", rpcBody, headers, function(rCode, rBody)
                if rCode == 200 then
                    local data = hs.json.decode(rBody)
                    if data and data.result and data.result.content and data.result.content[1] then
                        local txt = data.result.content[1].text or ""
                        local count = txt:match("Total patterns:%s*(%d+)")
                        if count then _patternCount = tonumber(count) end
                    end
                end
                M.updateMenubar()
                if callback then callback(true, _patternCount) end
            end)
        else
            _isOnline = false
            _patternCount = 0
            M.updateMenubar()
            if callback then callback(false, 0) end
        end
    end)
end

function M.updateMenubar()
    if not codeIntelMenu then return end
    if _activeTask then
        codeIntelMenu:setTitle("⚙️")
        codeIntelMenu:setTooltip("Code Intelligence: Task in progress...")
    elseif _isOnline then
        codeIntelMenu:setTitle("🧠")
        codeIntelMenu:setTooltip(string.format("Code Intelligence: Online (%d patterns)", _patternCount))
    else
        codeIntelMenu:setTitle("💤")
        codeIntelMenu:setTooltip("Code Intelligence: Offline")
    end
end

-------------------------------------------------
-- Server Lifecycle
-------------------------------------------------
function M.startServer()
    hs.alert.show("Starting Code Intelligence Server...", 2)
    hs.task.new("/bin/bash", function(exitCode, out, err)
        hs.timer.doAfter(2, function()
            M.checkStatus(function(online)
                if online then
                    hs.alert.show("✅ Code Intelligence Server Online", 2)
                else
                    hs.alert.show("⚠️ Check server logs: 64blit-code-intel logs", 3)
                end
            end)
        end)
    end, { "-lc", CLI_BIN .. " start" }):start()
end

function M.stopServer()
    hs.alert.show("Stopping Code Intelligence Server...", 2)
    hs.task.new("/bin/bash", function(exitCode, out, err)
        _isOnline = false
        M.updateMenubar()
        hs.alert.show("🛑 Code Intelligence Server Stopped", 2)
    end, { "-lc", CLI_BIN .. " stop" }):start()
end

function M.restartServer()
    hs.alert.show("Restarting Code Intelligence Server...", 2)
    hs.task.new("/bin/bash", function(exitCode, out, err)
        hs.timer.doAfter(3, function()
            M.checkStatus(function(online)
                if online then
                    hs.alert.show("✅ Code Intelligence Server Restarted", 2)
                else
                    hs.alert.show("⚠️ Restart failed. Check logs.", 3)
                end
            end)
        end)
    end, { "-lc", CLI_BIN .. " restart" }):start()
end

function M.openLogs()
    local cmd = string.format("tell application \"Terminal\" to do script \"%s logs 50\"", CLI_BIN)
    hs.osascript.applescript(cmd)
end

-------------------------------------------------
-- Ingest Codebase / Folder
-------------------------------------------------
function M.ingestFolder(targetPath, tags, reset)
    if not targetPath or targetPath == "" then
        local chosen = hs.dialog.chooseFolder("Select a Project / Folder to Index")
        if not chosen then return end
        targetPath = chosen
    end

    local tagArgs = ""
    if tags and tags ~= "" then
        tagArgs = string.format(" --tags %q", tags)
    end
    local resetArgs = reset and " --reset" or ""

    local cmd = string.format("%s ingest %q%s%s", CLI_BIN, targetPath, tagArgs, resetArgs)
    
    hs.alert.show(string.format("📥 Ingesting %s...", hs.fs.displayName(targetPath) or targetPath), 3)
    _activeTask = true
    M.updateMenubar()

    hs.task.new("/bin/bash", function(exitCode, out, err)
        _activeTask = false
        M.updateMenubar()
        if exitCode == 0 then
            hs.notify.new({
                title = "Code Intelligence Ingest Complete",
                informativeText = "Successfully indexed: " .. targetPath
            }):send()
            hs.alert.show("✅ Ingestion Complete!", 3)
            M.checkStatus()
        else
            hs.notify.new({
                title = "Code Intelligence Ingest Error",
                informativeText = err or out or "Unknown error"
            }):send()
            hs.alert.show("❌ Ingestion Failed (see console)", 4)
            print("[code_intel] Ingest failed: " .. tostring(err or out))
        end
    end, { "-lc", cmd }):start()
end

function M.promptIngestFolder()
    local chosen = hs.dialog.chooseFolder("Select Codebase Folder to Index")
    if not chosen then return end
    
    local btn, tags = hs.dialog.textPrompt(
        "Semantic Tags",
        "Enter comma-separated tags for filtering (e.g. svelte, frontend, api):",
        "",
        "Start Ingestion",
        "Cancel"
    )
    if btn == "Start Ingestion" then
        M.ingestFolder(chosen, tags, false)
    end
end

function M.openCrawlsFolder()
    hs.fs.mkdir(crawlsDir)
    hs.task.new("/usr/bin/open", nil, { crawlsDir }):start()
end

function M.scrapeURL(url, mode)
    -- mode: "markdown" (default) or "ingest"
    if not url or url == "" then return end

    if mode == "ingest" then
        local cmd = string.format("%s ingest %q --deep", CLI_BIN, url)
        hs.alert.show("🕸️ Ingesting documentation: " .. url, 3)
        _activeTask = true
        M.updateMenubar()

        hs.task.new("/bin/bash", function(exitCode, out, err)
            _activeTask = false
            M.updateMenubar()
            if exitCode == 0 then
                hs.alert.show("✅ Documentation Indexed Successfully!", 3)
                M.checkStatus()
            else
                hs.alert.show("❌ Docs Ingestion Failed", 4)
                print("[code_intel] Docs ingest failed: " .. tostring(err or out))
            end
        end, { "-lc", cmd }):start()
    else
        -- Scrape to Markdown files in crawlsDir
        hs.fs.mkdir(crawlsDir)
        local cmd = string.format("%s scrape %q --deep --distill --output %q", CLI_BIN, url, crawlsDir)
        hs.alert.show("🕸️ Scraping docs to Markdown...", 3)
        _activeTask = true
        M.updateMenubar()

        hs.task.new("/bin/bash", function(exitCode, out, err)
            _activeTask = false
            M.updateMenubar()
            if exitCode == 0 then
                -- Find newest generated markdown file
                local newestFile = nil
                local newestMtime = 0
                for f in hs.fs.dir(crawlsDir) do
                    if f:match("%.md$") then
                        local full = crawlsDir .. "/" .. f
                        local attrs = hs.fs.attributes(full)
                        if attrs and attrs.modification > newestMtime then
                            newestMtime = attrs.modification
                            newestFile = full
                        end
                    end
                end

                if newestFile then
                    hs.pasteboard.setContents(newestFile)
                else
                    hs.pasteboard.setContents(crawlsDir)
                end

                hs.notify.new({
                    title = "URL Scrape Complete",
                    informativeText = "Saved to " .. crawlsDir
                }):send()
                hs.alert.show("✅ Markdown Crawl Complete!", 3)

                local choice = hs.dialog.blockAlert(
                    "🕸️ Scrape Complete",
                    string.format("Successfully scraped %s\n\nSaved in: %s\n(Path copied to clipboard)", url, crawlsDir),
                    "Open Markdown File",
                    "Open Folder",
                    "Done"
                )
                if choice == "Open Markdown File" and newestFile then
                    hs.task.new("/usr/bin/open", nil, { newestFile }):start()
                elseif choice == "Open Folder" or (choice == "Open Markdown File" and not newestFile) then
                    hs.task.new("/usr/bin/open", nil, { crawlsDir }):start()
                end
            else
                hs.alert.show("❌ Crawl Failed (see console)", 4)
                print("[code_intel] Scrape failed: " .. tostring(err or out))
            end
        end, { "-lc", cmd }):start()
    end
end

function M.promptScrapeURL(mode)
    local title = (mode == "ingest") and "Ingest Documentation URL" or "Scrape Website to Markdown"
    local desc = (mode == "ingest")
        and "Enter documentation URL to index into vector database:"
        or "Enter website/documentation URL to crawl and convert to Markdown:"
    
    local btn, url = hs.dialog.textPrompt(title, desc, "https://", "Start", "Cancel")
    if btn == "Start" and url and url:match("^https?://") then
        M.scrapeURL(url, mode)
    end
end

-------------------------------------------------
-- Interactive Semantic Search Webview HUD
-------------------------------------------------
local SEARCH_HTML = [=[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<style>
  :root {
      --bg: #1e1e1e;
      --bg-card: #252526;
      --bg-input: #2d2d2d;
      --border: #3e3e42;
      --accent: #3b82f6;
      --accent-hover: #2563eb;
      --text: #f3f4f6;
      --text-dim: #9ca3af;
      --text-muted: #6b7280;
      --code-bg: #141414;
      --badge-bg: #1e3a8a;
      --badge-text: #93c5fd;
      --card-border: #333338;
  }
  * { box-sizing: border-box; }
  body {
    background-color: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    height: 100vh;
    overflow: hidden;
  }
  .search-header {
    padding: 14px 18px 12px;
    background: #181818;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex-shrink: 0;
  }
  .input-row {
    display: flex;
    gap: 8px;
    align-items: center;
  }
  .search-input {
    flex: 1;
    background: var(--bg-input);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 10px 14px;
    color: var(--text);
    font-size: 15px;
    outline: none;
    transition: border-color 0.15s;
  }
  .search-input:focus {
    border-color: var(--accent);
  }
  .tag-input {
    width: 140px;
    background: var(--bg-input);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 10px 12px;
    color: var(--text);
    font-size: 13px;
    outline: none;
  }
  .btn-search {
    background: var(--accent);
    color: white;
    border: none;
    border-radius: 6px;
    padding: 10px 18px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s;
  }
  .btn-search:hover { background: var(--accent-hover); }
  .status-bar {
    display: flex;
    justify-content: space-between;
    font-size: 12px;
    color: var(--text-dim);
    padding: 0 2px;
  }
  .content-area {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .solution-box {
    background: #1a2234;
    border: 1px solid #2563eb;
    border-radius: 8px;
    padding: 14px 18px;
  }
  .solution-title {
    font-weight: 600;
    font-size: 14px;
    color: #60a5fa;
    margin-bottom: 8px;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .solution-body {
    font-size: 13.5px;
    line-height: 1.55;
    color: #e2e8f0;
  }
  .result-card {
    background: var(--bg-card);
    border: 1px solid var(--card-border);
    border-radius: 8px;
    overflow: hidden;
    transition: border-color 0.15s;
  }
  .result-card:hover {
    border-color: #555;
  }
  .card-header {
    background: #202022;
    padding: 10px 14px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--card-border);
  }
  .file-path {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 13px;
    color: #93c5fd;
    word-break: break-all;
  }
  .card-actions {
    display: flex;
    gap: 6px;
  }
  .btn-action {
    background: #333;
    color: #eee;
    border: none;
    border-radius: 4px;
    padding: 4px 8px;
    font-size: 11px;
    cursor: pointer;
  }
  .btn-action:hover { background: #444; }
  .badge-sim {
    background: var(--badge-bg);
    color: var(--badge-text);
    font-size: 11px;
    padding: 2px 6px;
    border-radius: 4px;
    font-weight: 500;
  }
  .code-container {
    background: var(--code-bg);
    padding: 12px 14px;
    overflow-x: auto;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 12.5px;
    line-height: 1.5;
    margin: 0;
  }
  pre { margin: 0; }
  code { font-family: inherit; }
  .empty-state {
    text-align: center;
    color: var(--text-muted);
    margin-top: 60px;
    font-size: 14px;
  }
  .spinner {
    display: inline-block;
    width: 16px;
    height: 16px;
    border: 2px solid rgba(255,255,255,0.3);
    border-radius: 50%;
    border-top-color: white;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>
  <div class="search-header">
    <div class="input-row">
      <input type="text" id="queryInput" class="search-input" placeholder="Search patterns, errors, architectures, or code snippets..." autofocus>
      <input type="text" id="tagInput" class="tag-input" placeholder="Tags (e.g. svelte,api)">
      <button id="btnSearch" class="btn-search" onclick="doSearch()">Search</button>
    </div>
    <div class="status-bar">
      <span id="statusText">Ready</span>
      <span id="metaText">Server: 127.0.0.1:9991</span>
    </div>
  </div>

  <div id="contentArea" class="content-area">
    <div class="empty-state">
      <h3>🔍 64blit Code Intelligence</h3>
      <p>Type a natural language query or pattern to search across all indexed codebases.</p>
      <p style="font-size:12px; color:#777;">Press <b>Enter</b> to search • Click <b>Copy</b> or <b>Open in VSCode</b> on results</p>
    </div>
  </div>

  <script>
    const queryInput = document.getElementById('queryInput');
    const tagInput = document.getElementById('tagInput');
    const btnSearch = document.getElementById('btnSearch');
    const statusText = document.getElementById('statusText');
    const contentArea = document.getElementById('contentArea');

    queryInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') doSearch();
    });
    tagInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') doSearch();
    });

    function setInitialQuery(q) {
      if (q) {
        queryInput.value = q;
        doSearch();
      }
    }

    async function doSearch() {
      const q = queryInput.value.trim();
      if (!q) return;
      
      const tags = tagInput.value.trim();
      statusText.innerHTML = '<span class="spinner"></span> Searching...';
      btnSearch.disabled = true;

      try {
        const payload = {
          jsonrpc: "2.0",
          id: Date.now(),
          method: "tools/call",
          params: {
            name: "search_code",
            arguments: {
              query: q,
              limit: 5,
              tags: tags || undefined
            }
          }
        };

        const res = await fetch("http://127.0.0.1:9991/", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload)
        });

        const data = await res.json();
        btnSearch.disabled = false;

        if (data.error) {
          statusText.textContent = "Error: " + data.error.message;
          contentArea.innerHTML = `<div class="empty-state" style="color:#ef4444;">Error: ${data.error.message}</div>`;
          return;
        }

        const rawText = (data.result && data.result.content && data.result.content[0]) ? data.result.content[0].text : "";
        renderResults(rawText);
        statusText.textContent = "Search complete";
      } catch (err) {
        btnSearch.disabled = false;
        statusText.textContent = "Server unreachable";
        contentArea.innerHTML = `<div class="empty-state" style="color:#f87171;">Could not connect to Code Intelligence server at http://127.0.0.1:9991.<br><br>Make sure the server is started from the menubar.</div>`;
      }
    }

    function copyText(txt, btn) {
      navigator.clipboard.writeText(txt);
      const prev = btn.textContent;
      btn.textContent = "✓ Copied";
      setTimeout(() => btn.textContent = prev, 1500);
    }

    function openInEditor(path) {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.codeIntelHandler) {
        window.webkit.messageHandlers.codeIntelHandler.postMessage("open:" + path);
      }
    }

    function renderResults(rawText) {
      if (!rawText || rawText.includes("❌ No relevant code patterns found") || rawText.includes("No patterns found")) {
        contentArea.innerHTML = '<div class="empty-state">No matching code patterns found for this query.</div>';
        return;
      }

      let html = "";
      
      // Parse AI synthesized solution if present
      if (rawText.includes("✨ AI SYNTHESIZED SOLUTION") || rawText.includes("💡 Solution:")) {
        const solutionMatch = rawText.match(/(?:✨ AI SYNTHESIZED SOLUTION.*?|💡 Solution:)\n=*\n([\s\S]*?)\n=*\n/);
        if (solutionMatch) {
          const solutionMd = solutionMatch[1].trim();
          html += `
            <div class="solution-box">
              <div class="solution-title">✨ AI Synthesized Guidance</div>
              <div class="solution-body">${marked.parse(solutionMd)}</div>
            </div>
          `;
        }
      }

      // Parse Result Cards (Result N (Similarity: X%))
      const resultBlocks = rawText.split(/--- Result \d+/);
      let matchCount = 0;

      for (let i = 1; i < resultBlocks.length; i++) {
        const block = resultBlocks[i];
        const simMatch = block.match(/\(Similarity:\s*([\d\.]+%?)\)/);
        const fileMatch = block.match(/📁 File:\s*([^\n]+)/);
        const codeMatch = block.match(/📝 Code snippet:\n([\s\S]*)/);

        if (fileMatch) {
          matchCount++;
          const similarity = simMatch ? simMatch[1] : "Matched";
          const filePath = fileMatch[1].trim();
          let snippet = codeMatch ? codeMatch[1].trim() : "";
          
          // Clean up trailing line numbers if any
          const cleanCode = snippet.replace(/^\s*\d+:\s/gm, '');

          html += `
            <div class="result-card">
              <div class="card-header">
                <span class="file-path">${filePath}</span>
                <div class="card-actions">
                  <span class="badge-sim">${similarity}</span>
                  <button class="btn-action" onclick="copyText(${JSON.stringify(cleanCode)}, this)">Copy Code</button>
                  <button class="btn-action" onclick="copyText(${JSON.stringify(filePath)}, this)">Copy Path</button>
                  <button class="btn-action" style="background:#2563eb;" onclick="openInEditor(${JSON.stringify(filePath)})">Open in VSCode</button>
                </div>
              </div>
              <pre class="code-container"><code class="hljs">${hljs.highlightAuto(cleanCode).value}</code></pre>
            </div>
          `;
        }
      }

      if (matchCount === 0 && !html) {
        // Fallback: render entire raw markdown
        html = `<div class="solution-box"><div class="solution-body">${marked.parse(rawText)}</div></div>`;
      }

      contentArea.innerHTML = html;
    }
  </script>
</body>
</html>
]=]

function M.toggleSearchHUD(initialQuery)
    if _searchWindow then
        _searchWindow:delete()
        _searchWindow = nil
        return
    end

    local rect = {x = 0, y = 0, w = 820, h = 620}
    local screen = hs.screen.mainScreen()
    local frame = screen:fullFrame()
    rect.x = frame.x + (frame.w - rect.w) / 2
    rect.y = frame.y + (frame.h - rect.h) / 2

    local userContent = hs.webview.usercontent.new("codeIntelHandler")
    userContent:setCallback(function(msg)
        if type(msg.body) == "string" and msg.body:match("^open:") then
            local path = hs.http.urlUnescape(msg.body:sub(6))
            if path and path ~= "" then
                hs.task.new("/usr/bin/open", nil, { "-a", "Visual Studio Code", path }):start()
            end
        end
    end)

    local prefs = {}
    prefs.developerExtrasEnabled = true
    _searchWindow = webview.new(rect, prefs, userContent)
    _searchWindow:windowStyle(1 | 2 | 8 | 16)
    _searchWindow:windowTitle("64blit Code Intelligence Search (Esc to close)")
    _searchWindow:level(hs.drawing.windowLevels.floating)
    _searchWindow:allowGestures(true)
    _searchWindow:allowTextEntry(true)
    _searchWindow:deleteOnClose(true)

    _searchWindow:windowCallback(function(action)
        if action == "closing" then
            _searchWindow = nil
        end
    end)

    _searchWindow:html(SEARCH_HTML)
    _searchWindow:show()

    if initialQuery and initialQuery ~= "" then
        hs.timer.doAfter(0.4, function()
            if _searchWindow then
                _searchWindow:evaluateJavaScript(string.format("setInitialQuery(%q);", initialQuery))
            end
        end)
    end
end

-- Search selected text anywhere on macOS
function M.searchSelection()
    hs.eventtap.keyStroke({"cmd"}, "c")
    hs.timer.doAfter(0.2, function()
        local text = hs.pasteboard.getContents()
        if text and text ~= "" then
            M.toggleSearchHUD(text)
        else
            M.toggleSearchHUD()
        end
    end)
end

-------------------------------------------------
-- Menubar Dropdown Builder
-------------------------------------------------
function M.buildMenu()
    local statusTitle = _isOnline 
        and string.format("🟢 Server Online (%d patterns)", _patternCount)
        or "🔴 Server Offline"

    return {
        { title = "Code Intelligence", disabled = true },
        { title = statusTitle, disabled = true },
        { title = "-" },
        { title = "🔍 Semantic Code Search (HUD)...", fn = function() M.toggleSearchHUD() end },
        { title = "🔎 Search Selected Text", fn = function() M.searchSelection() end },
        { title = "-" },
        { title = "📥 Ingest Codebase / Folder...", fn = function() M.promptIngestFolder() end },
        { title = "🕸️ Scrape URL to Markdown...", fn = function() M.promptScrapeURL("markdown") end },
        { title = "📚 Ingest Documentation URL...", fn = function() M.promptScrapeURL("ingest") end },
        { title = "📁 Open Scraped Markdown Folder...", fn = function() M.openCrawlsFolder() end },
        { title = "-" },
        { title = "🚀 Start Server", fn = M.startServer, disabled = _isOnline },
        { title = "🛑 Stop Server", fn = M.stopServer, disabled = not _isOnline },
        { title = "🔄 Restart Server", fn = M.restartServer },
        { title = "📜 View Server Logs", fn = M.openLogs },
        { title = "🔄 Refresh Status", fn = function() M.checkStatus(function() hs.alert.show("Status Refreshed", 1) end) end },
    }
end

-- Periodic status check (every 30 seconds)
_statusTimer = hs.timer.doEvery(30, function()
    M.checkStatus()
end)

-- Initial check
M.checkStatus()

return {
    title = "Code Intelligence",
    icon = function()
        if _activeTask then return "⚙️" end
        return _isOnline and "🧠" or "💤"
    end,
    buildMenu = M.buildMenu,
    menubar = codeIntelMenu,
    toggleSearchHUD = M.toggleSearchHUD,
    searchSelection = M.searchSelection,
    ingestFolder = M.ingestFolder,
    promptIngestFolder = M.promptIngestFolder,
    scrapeURL = M.scrapeURL,
    promptScrapeURL = M.promptScrapeURL,
    startServer = M.startServer,
    stopServer = M.stopServer,
    restartServer = M.restartServer,
    checkStatus = M.checkStatus,
}
