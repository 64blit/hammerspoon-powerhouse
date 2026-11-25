-------------------------------------------------
-- Image Scraper
-- Extract images from any webpage URL, preview and pick them in a
-- paginated dark-mode WebView gallery, and batch-download locally.
-------------------------------------------------

local M = {}
local webview = require("hs.webview")
local env = require("env_loader")

local _imageWindow = nil
local imagesDir = env.getPath("IMAGE_SCRAPER_DIR", "~/Downloads/scraped-images")

local IMAGE_PICKER_HTML = [=[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  :root {
      --bg: #1e1e1e;
      --bg-card: #252526;
      --border: #3e3e42;
      --accent: #3b82f6;
      --accent-hover: #2563eb;
      --text: #f3f4f6;
      --text-dim: #9ca3af;
  }
  * { box-sizing: border-box; }
  body {
    background-color: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    margin: 0; padding: 0;
    display: flex; flex-direction: column;
    height: 100vh; overflow: hidden;
  }
  .header {
    padding: 12px 18px;
    background: #181818;
    border-bottom: 1px solid var(--border);
    display: flex; justify-content: space-between; align-items: center;
    flex-shrink: 0;
  }
  .header .title { font-size: 14px; font-weight: 600; }
  .header .url { font-size: 12px; color: var(--text-dim); max-width: 480px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .grid {
    flex: 1; overflow-y: auto; padding: 16px;
    display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px;
    grid-auto-rows: max-content; align-content: start;
  }
  .card {
    position: relative;
    background: var(--bg-card);
    border: 2px solid var(--border);
    border-radius: 8px;
    overflow: hidden; cursor: pointer;
    display: flex; flex-direction: column;
    transition: border-color 0.1s;
  }
  .card.selected { border-color: var(--accent); }
  .card .thumb {
    position: relative; width: 100%; height: 200px; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    background: #141414; overflow: hidden; padding: 6px;
  }
  .card img {
    max-width: 100%; max-height: 100%;
    width: auto; height: auto;
    display: block;
  }
  .card .name {
    padding: 6px 8px; font-size: 11px; color: var(--text-dim);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .card .check {
    position: absolute; top: 6px; left: 6px; z-index: 2; width: 22px; height: 22px;
    border-radius: 50%; background: rgba(0,0,0,0.55); border: 1.5px solid rgba(255,255,255,0.4);
    display: flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 700; color: transparent;
  }
  .card.selected .check { background: var(--accent); border-color: white; color: white; }
  .footer {
    padding: 12px 18px;
    background: #181818;
    border-top: 1px solid var(--border);
    display: flex; justify-content: space-between; align-items: center;
    flex-shrink: 0;
  }
  .footer .count { font-size: 13px; color: var(--text-dim); }
  .btn {
    border: none; border-radius: 6px; padding: 9px 16px;
    font-size: 13px; font-weight: 500; cursor: pointer;
  }
  .btn-dl { background: var(--accent); color: white; }
  .btn-dl:hover { background: var(--accent-hover); }
  .btn-dl:disabled { background: #374151; color: var(--text-dim); cursor: default; }
  .btn-ghost { background: transparent; color: var(--text-dim); border: 1px solid var(--border); margin-right: 8px; }
  .btn-ghost:hover { color: var(--text); }
  .btn-ghost:disabled { opacity: 0.35; cursor: default; }
  .pager { display: flex; align-items: center; gap: 4px; }
  .page-label { font-size: 12px; color: var(--text-dim); min-width: 80px; text-align: center; }
  .card.err .thumb::after {
    content: '✕'; position: absolute; top: 0; left: 0; width: 100%; height: 100%;
    display: flex; align-items: center; justify-content: center;
    color: var(--text-dim); font-size: 24px; background: #141414;
  }
</style>
</head>
<body>
  <div class="header">
    <div class="title">🖼️ Select images to download</div>
    <div class="url" id="pageUrl"></div>
  </div>
  <div class="grid" id="grid"></div>
  <div class="footer">
    <div class="count" id="count">0 selected</div>
    <div class="pager">
      <button class="btn btn-ghost" id="prevBtn" onclick="changePage(-1)">◀ Prev</button>
      <span class="page-label" id="pageLabel"></span>
      <button class="btn btn-ghost" id="nextBtn" onclick="changePage(1)">Next ▶</button>
    </div>
    <div>
      <button class="btn btn-ghost" onclick="togglePage()">Select Page</button>
      <button class="btn btn-ghost" onclick="toggleAll()">Select All</button>
      <button class="btn btn-dl" id="dlBtn" disabled onclick="download()">Download Selected</button>
    </div>
  </div>
  <script>
    const PAGE_SIZE = 24;
    let items = [];
    let page = 0;

    function post(msg) {
      window.webkit.messageHandlers.imageScraperHandler.postMessage(msg);
    }

    function pageCount() {
      return Math.max(1, Math.ceil(items.length / PAGE_SIZE));
    }

    function updateCount() {
      const n = items.filter(i => i.selected).length;
      document.getElementById('count').textContent = n + ' of ' + items.length + ' selected';
      document.getElementById('dlBtn').disabled = (n === 0);
      document.getElementById('pageLabel').textContent = 'Page ' + (page + 1) + ' / ' + pageCount();
      document.getElementById('prevBtn').disabled = (page === 0);
      document.getElementById('nextBtn').disabled = (page >= pageCount() - 1);
    }

    function renderPage() {
      const grid = document.getElementById('grid');
      grid.innerHTML = '';
      const start = page * PAGE_SIZE;
      const slice = items.slice(start, start + PAGE_SIZE);
      slice.forEach((item, i) => {
        const idx = start + i;
        const name = item.url.split('/').pop().split('?')[0] || 'image';
        const card = document.createElement('div');
        card.className = 'card' + (item.selected ? ' selected' : '');
        card.id = 'card-' + idx;
        card.innerHTML =
          '<div class="check">✓</div>' +
          '<div class="thumb"><img src="' + item.url.replace(/"/g, '&quot;') + '"' +
          ' onerror="this.closest(\'.card\').classList.add(\'err\')"></div>' +
          '<div class="name">' + name.replace(/</g, '&lt;') + '</div>';
        card.onclick = () => {
          item.selected = !item.selected;
          card.classList.toggle('selected', item.selected);
          updateCount();
        };
        grid.appendChild(card);
      });
      grid.scrollTop = 0;
      updateCount();
    }

    function changePage(delta) {
      const next = page + delta;
      if (next < 0 || next >= pageCount()) return;
      page = next;
      renderPage();
    }

    function loadImages(pageUrl, urls) {
      document.getElementById('pageUrl').textContent = pageUrl;
      items = urls.map(u => ({ url: u, selected: false }));
      page = 0;
      renderPage();
    }

    function togglePage() {
      const start = page * PAGE_SIZE;
      const slice = items.slice(start, start + PAGE_SIZE);
      const target = !slice.every(i => i.selected);
      slice.forEach((i, idx) => {
        i.selected = target;
        const el = document.getElementById('card-' + (start + idx));
        if (el) el.classList.toggle('selected', target);
      });
      updateCount();
    }

    function toggleAll() {
      const target = !items.every(i => i.selected);
      items.forEach(i => { i.selected = target; });
      renderPage();
    }

    function download() {
      const selected = items.filter(i => i.selected).map(i => i.url);
      if (selected.length > 0) post('download:' + JSON.stringify(selected));
    }

    document.addEventListener('keydown', e => {
      if (e.key === 'Escape') post('close');
      if (e.key === 'ArrowLeft') changePage(-1);
      if (e.key === 'ArrowRight') changePage(1);
    });
  </script>
</body>
</html>
]=]

-- Resolve possibly-relative image src against the page URL
local function resolveImageURL(src, pageUrl)
    if src:match("^https?://") then return src end
    if src:match("^//") then
        local scheme = pageUrl:match("^(https?):") or "https"
        return scheme .. ":" .. src
    end
    local root = pageUrl:match("^(https?://[^/]+)")
    if not root then return nil end
    if src:match("^/") then return root .. src end
    if src:match("^data:") then return nil end
    local dir = pageUrl:match("^(.*/)[^/]*$") or (root .. "/")
    return dir .. src
end

local function extractImageURLs(html, pageUrl)
    local seen, urls = {}, {}
    local function add(src)
        src = src:gsub("&amp;", "&")
        local resolved = resolveImageURL(src, pageUrl)
        if resolved and not seen[resolved] then
            seen[resolved] = true
            table.insert(urls, resolved)
        end
    end
    for src in html:gmatch("<img[^>]-src%s*=%s*[\"']([^\"']+)[\"']") do
        if #urls >= 200 then break end
        add(src)
    end
    for content in html:gmatch("<meta[^>]-property%s*=%s*[\"']og:image[\"'][^>]-content%s*=%s*[\"']([^\"']+)[\"']") do
        add(content)
    end
    return urls
end

local function safeFilename(url, index)
    local name = url:match("([^/]+)$") or ""
    name = name:gsub("%?.*$", ""):gsub("[^%w%.%-_]", "_")
    if name == "" or not name:match("%.%w+$") then
        name = string.format("image-%03d.jpg", index)
    end
    return string.format("%03d-%s", index, name)
end

local HTTP_HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
}

local function downloadImages(urls)
    hs.fs.mkdir(imagesDir)
    local outDir = string.format("%s/%s", imagesDir, os.date("%Y%m%d-%H%M%S"))
    hs.fs.mkdir(outDir)

    local remaining = #urls
    local okCount, failCount = 0, 0
    hs.alert.show(string.format("⬇️ Downloading %d images...", remaining), 2)

    for i, url in ipairs(urls) do
        hs.http.asyncGet(url, HTTP_HEADERS, function(code, body)
            if code == 200 and body and #body > 0 then
                local f = io.open(outDir .. "/" .. safeFilename(url, i), "wb")
                if f then
                    f:write(body)
                    f:close()
                    okCount = okCount + 1
                else
                    failCount = failCount + 1
                end
            else
                failCount = failCount + 1
                print("[image_scraper] Image download failed (" .. tostring(code) .. "): " .. url)
            end
            remaining = remaining - 1
            if remaining == 0 then
                hs.notify.new({
                    title = "Image Scrape Complete",
                    informativeText = string.format("%d saved, %d failed\n%s", okCount, failCount, outDir)
                }):send()
                hs.pasteboard.setContents(outDir)
                local choice = hs.dialog.blockAlert(
                    "🖼️ Images Downloaded",
                    string.format("%d saved, %d failed\n\nSaved in: %s\n(Path copied to clipboard)", okCount, failCount, outDir),
                    "Open Folder", "Done"
                )
                if choice == "Open Folder" then
                    hs.task.new("/usr/bin/open", nil, { outDir }):start()
                end
            end
        end)
    end
end

function M.scrapeImages(url)
    if not url or url == "" then return end
    hs.alert.show("🖼️ Fetching page images...", 2)
    hs.http.asyncGet(url, HTTP_HEADERS, function(code, body)
        print("[image_scraper] fetch: HTTP " .. tostring(code) .. " len " .. tostring(body and #body or 0))
        if code ~= 200 or not body then
            hs.alert.show("❌ Failed to fetch page (HTTP " .. tostring(code) .. ")", 4)
            return
        end
        local urls = extractImageURLs(body, url)
        print("[image_scraper] found " .. #urls .. " image urls")
        if #urls == 0 then
            hs.alert.show("No images found on page", 3)
            return
        end

        if _imageWindow then
            _imageWindow:delete()
            _imageWindow = nil
        end

        local rect = { x = 0, y = 0, w = 900, h = 680 }
        local screen = hs.screen.mainScreen()
        local frame = screen:fullFrame()
        rect.x = frame.x + (frame.w - rect.w) / 2
        rect.y = frame.y + (frame.h - rect.h) / 2

        local userContent = hs.webview.usercontent.new("imageScraperHandler")
        userContent:setCallback(function(msg)
            if type(msg.body) ~= "string" then return end
            if msg.body == "close" then
                if _imageWindow then
                    _imageWindow:delete()
                    _imageWindow = nil
                end
            elseif msg.body:match("^download:") then
                local selected = hs.json.decode(msg.body:sub(10))
                if _imageWindow then
                    _imageWindow:delete()
                    _imageWindow = nil
                end
                if selected and #selected > 0 then
                    downloadImages(selected)
                end
            end
        end)

        local prefs = {}
        prefs.developerExtrasEnabled = true
        local win = webview.new(rect, prefs, userContent)
        win:windowStyle(1 | 2 | 8 | 16)
        win:windowTitle("Image Scraper — select and confirm (Esc to close)")
        win:level(hs.drawing.windowLevels.floating)
        win:allowGestures(true)
        win:deleteOnClose(true)
        win:windowCallback(function(action)
            if action == "closing" and _imageWindow == win then
                _imageWindow = nil
            end
        end)

        win:html(IMAGE_PICKER_HTML)
        win:show()
        _imageWindow = win

        hs.timer.doAfter(0.4, function()
            if _imageWindow then
                _imageWindow:evaluateJavaScript(string.format(
                    "loadImages(%q, %s);", url, hs.json.encode(urls)))
            end
        end)
    end)
end

function M.promptScrapeImages()
    local btn, url = hs.dialog.textPrompt(
        "Scrape Images from Website",
        "Enter website URL to extract images (you confirm before download):",
        "https://", "Start", "Cancel")
    if btn == "Start" and url and url:match("^https?://") then
        M.scrapeImages(url)
    end
end

function M.openImagesFolder()
    hs.fs.mkdir(imagesDir)
    hs.task.new("/usr/bin/open", nil, { imagesDir }):start()
end

-------------------------------------------------
-- Menubar Integration
-------------------------------------------------
local imageMenu = hs.menubar.new()

function M.buildMenu()
    return {
        { title = "🖼️ Scrape Images from URL...", fn = function() M.promptScrapeImages() end },
        { title = "📁 Open Scraped Images Folder", fn = function() M.openImagesFolder() end },
    }
end

if imageMenu then
    imageMenu:setTitle("🖼️")
    imageMenu:setTooltip("Image Scraper")
    imageMenu:setMenu(M.buildMenu)
end

return {
    title = "Image Scraper",
    icon = function() return "🖼️" end,
    buildMenu = M.buildMenu,
    menubar = imageMenu,
    scrapeImages = M.scrapeImages,
    promptScrapeImages = M.promptScrapeImages,
    openImagesFolder = M.openImagesFolder,
    imageWindow = function() return _imageWindow end,
}
