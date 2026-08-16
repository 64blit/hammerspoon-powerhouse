-------------------------------------------------
-- Screen Translator
-- Magnifier-style screen capture with Apple Vision OCR + Apple Translate
-- overlays.
--
-- Two canvases:
--   * srcCanvas: thin border on the locked screen marking the capture
--     region. Draggable + resizable. Border is drawn OUTSIDE the capture
--     rect so it is not included in the snapshot.
--   * trCanvas:  floating output window that mirrors the captured region
--     at whatever size you resize it to (effective zoom = trCanvas size /
--     srcCanvas size). Translated text is drawn over the matching OCR
--     bounding boxes.
--
-- Requires:
--   1. translator_helper/ocr_helper  (built by translator_helper/build.sh)
--   2. A macOS Shortcut named `HSTranslate` that accepts text input,
--      runs the "Translate Text" action, and returns the translated text.
-------------------------------------------------

-- ===== Config =====
local OVERLAY_DEFAULT_W   = 700
local OVERLAY_DEFAULT_H   = 500
local SRC_DEFAULT_W       = 500
local SRC_DEFAULT_H       = 320
local MIN_W, MIN_H        = 200, 140
local SRC_BORDER          = 12      -- thickness of source rect indicator (also drag-grab area)
local SNAPSHOT_FPS        = 30      -- mirror refresh
local TRANSLATE_INTERVAL  = 2.5     -- seconds between live re-translates
-- Single shortcut that auto-detects source language and translates to English
-- (or whatever target is configured inside Shortcuts.app).
local TRANSLATE_SHORTCUT  = "HSTranslate_ko_en"
local OCR_LANGS           = "ja-JP,zh-Hans,zh-Hant,ko-KR,en-US"

local helperDir   = hs.configdir .. "/translator_helper"
local OCR_HELPER  = helperDir .. "/ocr_helper"
local BUILD_SH    = helperDir .. "/build.sh"

-- ===== State =====
local trCanvas         = nil
local srcParts         = nil   -- {top, bottom, left, right, resize} canvases
local srcRect          = nil   -- {x, y, w, h} absolute screen-coord capture rect
local trLockedScreen   = nil
local trLiveTimer      = nil
local trTranslateTimer = nil
local trDragTap        = nil
local srcDragTap       = nil
local paused           = false
local busy             = false
local lastItems        = {}
local snapW, snapH     = 0, 0
local lastSrcRect      = nil   -- absolute screen-coord rect last translated

local trState = {
    isDragging = false,
    isResizing = false,
    startMousePos = nil,
    startCanvasFrame = nil,
}

local srcState = {
    isDragging = false,
    isResizing = false,
    startMousePos = nil,
    startCanvasFrame = nil,
}

-- Fixed canvas element indices for trCanvas (controls + chrome). Dynamic
-- translated text overlays start at FIRST_OVERLAY_IDX and are cleared each
-- translate.
local IDX = {
    IMAGE        = 1,
    BORDER       = 2,
    DRAG_BG      = 3,
    DRAG_TEXT    = 4,
    PAUSE_BG     = 5,
    PAUSE_TEXT   = 6,
    TRANS_BG     = 7,
    TRANS_TEXT   = 8,
    CLOSE_BG     = 9,
    CLOSE_TEXT   = 10,
    RESIZE_BG    = 11,
    RESIZE_TEXT  = 12,
}
local FIRST_OVERLAY_IDX = 13

-- Control chip geometry (top-left bar)
local CHIP_Y, CHIP_H = 8, 26
local DRAG_X,  DRAG_W  = 8,   28
local PAUSE_X, PAUSE_W = 42,  86
local TRANS_X, TRANS_W = 134, 120
local CLOSE_W          = 26
local TOP_BAR_H        = CHIP_Y + CHIP_H + 8   -- reserved strip for chips; image + overlays live below this

-- ===== Helpers =====
local function ensureHelper()
    if hs.fs.attributes(OCR_HELPER) then return true end
    hs.alert.show("Building OCR helper…")
    local ok = os.execute("bash " .. BUILD_SH .. " >/tmp/ocr_build.log 2>&1")
    if not ok or not hs.fs.attributes(OCR_HELPER) then
        hs.alert.show("OCR helper build failed (see /tmp/ocr_build.log)")
        return false
    end
    return true
end

-- Absolute screen-coord rect that is currently being captured.
local function getSourceRect()
    if not srcRect then return nil end
    return {x = srcRect.x, y = srcRect.y, w = srcRect.w, h = srcRect.h}
end

local function layoutSrcParts()
    if not srcParts or not srcRect then return end
    local r = srcRect
    local b = SRC_BORDER
    -- Edge strips form hollow ring around srcRect — interior is empty so
    -- clicks pass through to apps beneath. Strips are wide (b) for easy
    -- grab but render only a 1px line on the srcRect-facing edge.
    srcParts.top   :frame({x = r.x - b,     y = r.y - b,     w = r.w + 2*b, h = b})
    srcParts.bottom:frame({x = r.x - b,     y = r.y + r.h,   w = r.w + 2*b, h = b})
    srcParts.left  :frame({x = r.x - b,     y = r.y,         w = b,         h = r.h})
    srcParts.right :frame({x = r.x + r.w,   y = r.y,         w = b,         h = r.h})

    -- Position 1px line element[2] per edge (canvas-local coords)
    srcParts.top[2].frame    = {x = b, y = b - 1,   w = r.w, h = 1}
    srcParts.bottom[2].frame = {x = b, y = 0,       w = r.w, h = 1}
    srcParts.left[2].frame   = {x = b - 1, y = 0,   w = 1,   h = r.h}
    srcParts.right[2].frame  = {x = 0, y = 0,       w = 1,   h = r.h}

    local rs = 14
    srcParts.resize:frame({x = r.x + r.w - rs/2, y = r.y + r.h - rs/2, w = rs + b, h = rs + b})

    -- Visible drag-handle button above top edge
    local hw, hh = 72, 18
    srcParts.handle:frame({
        x = r.x + (r.w - hw) / 2,
        y = r.y - b - hh + 2,
        w = hw, h = hh,
    })
end

local function captureSnapshot()
    if not trLockedScreen or not srcRect then return nil end
    local rect = getSourceRect()
    if not rect then return nil end
    local sf = trLockedScreen:fullFrame()

    -- Clamp to screen bounds
    local x = math.max(sf.x, rect.x)
    local y = math.max(sf.y, rect.y)
    local r = math.min(sf.x + sf.w, rect.x + rect.w)
    local b = math.min(sf.y + sf.h, rect.y + rect.h)
    local w, h = r - x, b - y
    if w <= 1 or h <= 1 then return nil end

    -- screen:snapshot takes screen-relative coordinates
    local relRect = hs.geometry.rect(x - sf.x, y - sf.y, w, h)
    return trLockedScreen:snapshot(relRect)
end

-- Compute scale + offsets used to map snapshot pixel coords to trCanvas
-- coords. Image fills the entire canvas (imageScaling=scaleProportionally),
-- letterboxed and centered. OCR overlays use the same transform so they
-- track the image exactly even if chips overlap the top.
local function fitScale()
    if not trCanvas or snapW <= 0 or snapH <= 0 then return 1, 0, 0 end
    local f = trCanvas:frame()
    local s = math.min(f.w / snapW, f.h / snapH)
    local offX = (f.w - snapW * s) / 2
    local offY = (f.h - snapH * s) / 2
    return s, offX, offY
end

-- Set image frame to the exact letterboxed rect computed from snapW/snapH.
-- This guarantees the rendered image and OCR overlays share the same
-- transform regardless of what hs.image:size() reports.
local function layoutImageElement()
    if not trCanvas or snapW <= 0 or snapH <= 0 then return end
    local s, offX, offY = fitScale()
    trCanvas[IDX.IMAGE].frame = {
        x = offX, y = offY,
        w = snapW * s, h = snapH * s,
    }
end

-- Rebuild only the translated text overlays beyond the fixed control indices.
local function repaintOverlays()
    if not trCanvas then return end
    layoutImageElement()
    while trCanvas:elementCount() >= FIRST_OVERLAY_IDX do
        trCanvas:removeElement(trCanvas:elementCount())
    end
    local s, offX, offY = fitScale()
    for _, it in ipairs(lastItems or {}) do
        local x = offX + it.x * s
        local y = offY + it.y * s
        local w = it.w * s
        local h = it.h * s
        if w > 2 and h > 2 then
            trCanvas:appendElements({
                type = "rectangle", action = "fill",
                fillColor = {red=0,green=0,blue=0,alpha=0.82},
                frame = {x=x, y=y, w=w, h=h},
                roundedRectRadii = {xRadius=2, yRadius=2},
            })
            trCanvas:appendElements({
                type = "text",
                text = it.translated or it.text or "",
                textSize = math.max(9, math.floor(h * 0.72)),
                textColor = {white=1, alpha=1},
                textAlignment = "left",
                frame = {x=x+3, y=y, w=w-6, h=h},
            })
        end
    end
end

local function refreshControlVisuals()
    if not trCanvas then return end
    local f = trCanvas:frame()
    local closeX = f.w - CLOSE_W - 8

    trCanvas[IDX.PAUSE_BG].fillColor =
        paused and {red=0.55,green=0.18,blue=0.18,alpha=0.95}
                or {red=0.18,green=0.45,blue=0.22,alpha=0.95}
    trCanvas[IDX.PAUSE_TEXT].text = paused and "▶  Resume" or "❚❚  Pause"

    trCanvas[IDX.TRANS_BG].fillColor =
        busy and {red=0.35,green=0.35,blue=0.35,alpha=0.95}
              or {red=0.20,green=0.42,blue=0.72,alpha=0.95}
    trCanvas[IDX.TRANS_TEXT].text = busy and "Translating…" or "Translate Now"

    trCanvas[IDX.CLOSE_BG].frame  = {x=closeX, y=CHIP_Y, w=CLOSE_W, h=CHIP_H}
    trCanvas[IDX.CLOSE_TEXT].frame = {x=closeX, y=CHIP_Y+3, w=CLOSE_W, h=CHIP_H-4}
end

local function shortcutName() return TRANSLATE_SHORTCUT end

-- ===== Translation pipeline =====
-- Dual-backend translation engine:
-- Primary: local translate_server (Google Translate Node server on 127.0.0.1:27892)
-- Secondary / Fallback: Apple Translation CLI (translator_helper/bin/translate)
local TRANSLATE_BIN    = helperDir .. "/bin/translate"
local TRANSLATE_SERVER = helperDir .. "/translate_server/server.js"
local TRANSLATE_TGT    = "en"
local serverTask       = nil

local function findNodeBin()
    local candidates = {
        "/usr/local/bin/node",
        "/opt/homebrew/bin/node",
    }
    local home = os.getenv("HOME")
    if home then
        table.insert(candidates, home .. "/.nvm/versions/node/v22.20.0/bin/node")
    end
    for _, p in ipairs(candidates) do
        if hs.fs.attributes(p) then return p end
    end
    return "node"
end

local function getPort()
    local f = io.open("/tmp/hs_translate_port.txt", "r")
    if f then
        local p = f:read("*a")
        f:close()
        p = p and p:gsub("%s+", "")
        if p and #p > 0 and tonumber(p) then return tonumber(p) end
    end
    return 27892
end

local function ensureServer(cb)
    local port = getPort()
    hs.http.asyncGet("http://127.0.0.1:" .. port .. "/health", nil, function(status, body)
        if status == 200 and body == "ok" then
            if cb then cb(true, port) end
            return
        end
        if not hs.fs.attributes(TRANSLATE_SERVER) then
            if cb then cb(false, nil) end
            return
        end
        local nodeBin = findNodeBin()
        serverTask = hs.task.new(nodeBin, function(rc, out, err)
            print(string.format("[window_translator] translate_server exited rc=%s err=%q", tostring(rc), err or ""))
            serverTask = nil
        end, { TRANSLATE_SERVER })
        if serverTask then
            serverTask:start()
            hs.timer.doAfter(0.4, function()
                local p = getPort()
                if cb then cb(true, p) end
            end)
        else
            if cb then cb(false, nil) end
        end
    end)
end

local function translateBatchApple(items, done)
    if not hs.fs.attributes(TRANSLATE_BIN) then
        for _, it in ipairs(items) do it.translated = it.text end
        done(items); return
    end
    local pending = #items
    for _, it in ipairs(items) do
        local task = hs.task.new(TRANSLATE_BIN,
            function(rc, sout, serr)
                local out = sout and sout:gsub("^%s+", ""):gsub("%s+$", "") or ""
                if rc == 0 and #out > 0 and out ~= it.text then
                    it.translated = out
                else
                    it.translated = it.text
                end
                pending = pending - 1
                if pending == 0 then done(items) end
            end,
            {"--to", TRANSLATE_TGT, it.text or ""})
        task:start()
    end
end

local function translateBatch(items, done)
    if #items == 0 then done(items) return end

    local texts = {}
    for _, it in ipairs(items) do
        table.insert(texts, it.text or "")
    end

    ensureServer(function(ok, port)
        if ok and port then
            local url = "http://127.0.0.1:" .. port .. "/translate"
            local headers = { ["Content-Type"] = "application/json" }
            local body = hs.json.encode({ texts = texts, to = TRANSLATE_TGT })

            hs.http.asyncPost(url, body, headers, function(status, respBody)
                if status == 200 and respBody then
                    local parsed = hs.json.decode(respBody)
                    if parsed and parsed.translations and #parsed.translations == #items then
                        for i, it in ipairs(items) do
                            local tr = parsed.translations[i]
                            if tr and tr.text and #tr.text > 0 then
                                it.translated = tr.text
                            else
                                it.translated = it.text
                            end
                        end
                        done(items)
                        return
                    end
                end
                translateBatchApple(items, done)
            end)
        else
            translateBatchApple(items, done)
        end
    end)
end

-- Read PNG pixel dimensions directly from file header. Removes any guesswork
-- about points vs pixels from hs.image:size().
local function pngPixelSize(path)
    local f = io.open(path, "rb")
    if not f then return nil, nil end
    f:seek("set", 16) -- skip 8-byte PNG signature + 8-byte IHDR chunk header
    local data = f:read(8)
    f:close()
    if not data or #data < 8 then return nil, nil end
    local b1,b2,b3,b4,b5,b6,b7,b8 = data:byte(1,8)
    local w = b1*0x1000000 + b2*0x10000 + b3*0x100 + b4
    local h = b5*0x1000000 + b6*0x10000 + b7*0x100 + b8
    return w, h
end

local function snapshotPixelSize(img)
    -- Fallback: save to a temp PNG and read header. Used by live tick which
    -- doesn't have a saved file around. We cache last known dims.
    local sz = img:size()
    local scale = 1
    if trLockedScreen then
        local mode = trLockedScreen:currentMode()
        if mode and mode.scale then scale = mode.scale end
    end
    return sz.w * scale, sz.h * scale
end

local function doTranslate()
    if busy or not trCanvas then return end
    local img = captureSnapshot()
    if not img then return end
    trCanvas[IDX.IMAGE].image = img
    lastSrcRect = getSourceRect()

    busy = true
    refreshControlVisuals()

    local tmpPath = os.tmpname() .. ".png"
    img:saveToFile(tmpPath)
    -- Read actual PNG pixel dims so snapW/snapH match the coordinate space
    -- the OCR helper sees. No more points-vs-pixels guesswork.
    local pw, ph = pngPixelSize(tmpPath)
    if pw and ph then
        snapW, snapH = pw, ph
    else
        snapW, snapH = snapshotPixelSize(img)
    end

    local task = hs.task.new(OCR_HELPER,
        function(rc, sout, serr)
            os.remove(tmpPath)
            if rc ~= 0 then
                busy = false
                print("[window_translator] OCR error rc=" .. tostring(rc) .. " : " .. (serr or ""))
                refreshControlVisuals()
                return
            end
            local ok, items = pcall(hs.json.decode, sout or "[]")
            if not ok or type(items) ~= "table" then
                busy = false
                refreshControlVisuals()
                return
            end
            translateBatch(items, function(translated)
                lastItems = translated
                busy = false
                refreshControlVisuals()
                repaintOverlays()
            end)
        end,
        {tmpPath, OCR_LANGS})
    task:start()
end

-- ===== Live mirror tick =====
local function tick()
    if not trCanvas then return end
    local img = captureSnapshot()
    if img then
        trCanvas[IDX.IMAGE].image = img
        -- Don't update snapW/snapH from img:size() here — those would be in
        -- points and conflict with the pixel-based dims set in doTranslate.
        -- Live tick just refreshes pixel data inside the same frame.
    end
end

-- ===== Drag / resize =====
local function stopTrDrag()
    if trDragTap then trDragTap:stop() end
    trState.isDragging = false
    trState.isResizing = false
    trState.startMousePos = nil
    trState.startCanvasFrame = nil
end

local function stopSrcDrag()
    if srcDragTap then srcDragTap:stop() end
    srcState.isDragging = false
    srcState.isResizing = false
    srcState.startMousePos = nil
    srcState.startCanvasFrame = nil
end

local function persistFrames()
    if trCanvas then
        local f = trCanvas:frame()
        hs.settings.set("translator_x", f.x)
        hs.settings.set("translator_y", f.y)
        hs.settings.set("translator_w", f.w)
        hs.settings.set("translator_h", f.h)
    end
    if srcRect then
        hs.settings.set("translator_src_x", srcRect.x)
        hs.settings.set("translator_src_y", srcRect.y)
        hs.settings.set("translator_src_w", srcRect.w)
        hs.settings.set("translator_src_h", srcRect.h)
    end
end

-- ===== Mouse handlers =====
local function onTrMouse(canvas, msg, _, x, y)
    if msg ~= "mouseDown" then return end
    local f = canvas:frame()
    local closeX = f.w - CLOSE_W - 8

    if x >= PAUSE_X and x <= PAUSE_X + PAUSE_W and y >= CHIP_Y and y <= CHIP_Y + CHIP_H then
        paused = not paused
        refreshControlVisuals()
        if not paused then doTranslate() end
        return
    end
    if x >= TRANS_X and x <= TRANS_X + TRANS_W and y >= CHIP_Y and y <= CHIP_Y + CHIP_H then
        doTranslate()
        return
    end
    if x >= closeX and x <= closeX + CLOSE_W and y >= CHIP_Y and y <= CHIP_Y + CHIP_H then
        require("window_translator").stop()
        return
    end

    trState.startMousePos = hs.mouse.absolutePosition()
    trState.startCanvasFrame = f
    if x > (f.w - 25) and y > (f.h - 25) then
        trState.isResizing = true
    else
        trState.isDragging = true
    end
    if trDragTap then trDragTap:start() end
end

local function onSrcMouse(canvas, msg, _, _, _)
    if msg ~= "mouseDown" or not srcRect then return end
    srcState.startMousePos = hs.mouse.absolutePosition()
    srcState.startCanvasFrame = {x=srcRect.x, y=srcRect.y, w=srcRect.w, h=srcRect.h}
    if srcParts and canvas == srcParts.resize then
        srcState.isResizing = true
    else
        srcState.isDragging = true
    end
    if srcDragTap then srcDragTap:start() end
end

-- ===== Module API =====
local M = {}

local function loadSrcFrame()
    local sf = trLockedScreen:fullFrame()
    local w = hs.settings.get("translator_src_w") or SRC_DEFAULT_W
    local h = hs.settings.get("translator_src_h") or SRC_DEFAULT_H
    local x = hs.settings.get("translator_src_x")
    local y = hs.settings.get("translator_src_y")
    local onScreen = false
    if x and y then
        for _, scr in pairs(hs.screen.allScreens()) do
            local s = scr:fullFrame()
            if (x < s.x + s.w) and (x + w > s.x)
               and (y < s.y + s.h) and (y + h > s.y) then
                onScreen = true; break
            end
        end
    end
    if not onScreen then
        local mp = hs.mouse.absolutePosition()
        x = mp.x - w / 2
        y = mp.y - h / 2
        if x < sf.x then x = sf.x + 40 end
        if y < sf.y then y = sf.y + 40 end
        if x + w > sf.x + sf.w then x = sf.x + sf.w - w - 40 end
        if y + h > sf.y + sf.h then y = sf.y + sf.h - h - 40 end
    end
    return {x = x, y = y, w = w, h = h}
end

local function loadTrFrame()
    local w = hs.settings.get("translator_w") or OVERLAY_DEFAULT_W
    local h = hs.settings.get("translator_h") or OVERLAY_DEFAULT_H
    local x = hs.settings.get("translator_x")
    local y = hs.settings.get("translator_y")
    local sf = hs.screen.mainScreen():frame()
    local onScreen = false
    if x and y then
        for _, scr in pairs(hs.screen.allScreens()) do
            local s = scr:fullFrame()
            if (x < s.x + s.w) and (x + w > s.x)
               and (y < s.y + s.h) and (y + h > s.y) then
                onScreen = true; break
            end
        end
    end
    if not onScreen then
        x = sf.x + sf.w - w - 20
        y = sf.y + sf.h - h - 40
    end
    return {x = x, y = y, w = w, h = h}
end

local function makeEdgeCanvas(lineColor, opts)
    opts = opts or {}
    local c = hs.canvas.new({x=0, y=0, w=10, h=10})
    -- Element 1: transparent click-target covering full strip (drag-grab area)
    c[1] = {
        type = "rectangle", action = "fill",
        fillColor = {white=0, alpha=0.01},
        frame = {x=0, y=0, w="100%", h="100%"},
    }
    -- Element 2: 1px visible line, positioned by layoutSrcParts (or full-fill
    -- for resize corner if opts.solid).
    if opts.solid then
        c[2] = {
            type = "rectangle", action = "fill",
            fillColor = lineColor,
            frame = {x=0, y=0, w="100%", h="100%"},
        }
    else
        c[2] = {
            type = "rectangle", action = "fill",
            fillColor = lineColor,
            frame = {x=0, y=0, w=1, h=1},
        }
    end
    c:level(hs.canvas.windowLevels.floating)
    c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    c:canvasMouseEvents(true, true, false, false)
    c:clickActivating(false)
    c:mouseCallback(onSrcMouse)
    return c
end

local function buildSrcCanvas(sFrame)
    -- srcRect = captured region in absolute screen coords. Five thin canvases
    -- form a hollow ring around it (top/bottom/left/right + bottom-right
    -- resize corner). Interior of the ring is empty, so clicks pass through
    -- to underlying apps.
    srcRect = {x = sFrame.x, y = sFrame.y, w = sFrame.w, h = sFrame.h}
    local edgeColor   = {red=1, green=0.55, blue=0.1, alpha=0.95}
    local resizeColor = {red=1, green=0.55, blue=0.1, alpha=0.95}
    srcParts = {
        top    = makeEdgeCanvas(edgeColor),
        bottom = makeEdgeCanvas(edgeColor),
        left   = makeEdgeCanvas(edgeColor),
        right  = makeEdgeCanvas(edgeColor),
        resize = makeEdgeCanvas(resizeColor, {solid = true}),
        handle = makeEdgeCanvas(edgeColor, {solid = true}),
    }
    srcParts.handle[3] = {
        type = "text", text = "⋮⋮ drag",
        textColor = {white=1, alpha=1}, textSize = 11, textAlignment = "center",
        frame = {x=0, y=1, w="100%", h="100%"},
    }
    srcParts.resize[3] = {
        type = "text", text = "⌟",
        textColor = {white=1, alpha=0.95}, textSize = 14, textAlignment = "center",
        frame = {x=0, y=-2, w="100%", h="100%"},
    }
    layoutSrcParts()
    for _, c in pairs(srcParts) do c:show() end
end

function M.start()
    if trCanvas then M.stop() end
    if not ensureHelper() then return end

    -- Lock to the screen where the mouse currently is (like magnifier)
    trLockedScreen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()

    local srcFrame = loadSrcFrame()
    buildSrcCanvas(srcFrame)

    local trFrame = loadTrFrame()
    trCanvas = hs.canvas.new(trFrame)

    -- 1. Image (snapshot mirror). Frame is set explicitly by
    --    layoutImageElement so it matches the OCR overlay transform exactly.
    trCanvas[IDX.IMAGE] = {
        type = "image",
        frame = {x=0, y=0, w="100%", h="100%"},
        imageScaling = "scaleToFit",
        imageAlignment = "topLeft",
    }
    -- 2. Border
    trCanvas[IDX.BORDER] = {
        type = "rectangle", action = "stroke",
        strokeColor = {white=1, alpha=0.6}, strokeWidth = 2,
        frame = {x=0, y=0, w="100%", h="100%"},
    }
    -- 3 + 4: Drag handle chip (top-left)
    trCanvas[IDX.DRAG_BG] = {
        type = "rectangle", action = "fill",
        fillColor = {red=0.15,green=0.15,blue=0.15,alpha=0.95},
        strokeColor = {white=1, alpha=0.5}, strokeWidth = 1,
        roundedRectRadii = {xRadius=4, yRadius=4},
        frame = {x=DRAG_X, y=CHIP_Y, w=DRAG_W, h=CHIP_H},
    }
    trCanvas[IDX.DRAG_TEXT] = {
        type = "text", text = "⋮⋮",
        textColor = {white=1}, textSize = 14, textAlignment = "center",
        frame = {x=DRAG_X, y=CHIP_Y+4, w=DRAG_W, h=CHIP_H-4},
    }
    -- 5 + 6: Pause chip
    trCanvas[IDX.PAUSE_BG] = {
        type = "rectangle", action = "fill",
        fillColor = {red=0.18,green=0.45,blue=0.22,alpha=0.95},
        strokeColor = {white=1, alpha=0.5}, strokeWidth = 1,
        roundedRectRadii = {xRadius=4, yRadius=4},
        frame = {x=PAUSE_X, y=CHIP_Y, w=PAUSE_W, h=CHIP_H},
    }
    trCanvas[IDX.PAUSE_TEXT] = {
        type = "text", text = "❚❚  Pause",
        textColor = {white=1}, textSize = 12, textAlignment = "center",
        frame = {x=PAUSE_X, y=CHIP_Y+5, w=PAUSE_W, h=CHIP_H-6},
    }
    -- 5 + 6: Translate Now chip
    trCanvas[IDX.TRANS_BG] = {
        type = "rectangle", action = "fill",
        fillColor = {red=0.20,green=0.42,blue=0.72,alpha=0.95},
        strokeColor = {white=1, alpha=0.5}, strokeWidth = 1,
        roundedRectRadii = {xRadius=4, yRadius=4},
        frame = {x=TRANS_X, y=CHIP_Y, w=TRANS_W, h=CHIP_H},
    }
    trCanvas[IDX.TRANS_TEXT] = {
        type = "text", text = "Translate Now",
        textColor = {white=1}, textSize = 12, textAlignment = "center",
        frame = {x=TRANS_X, y=CHIP_Y+5, w=TRANS_W, h=CHIP_H-6},
    }
    -- 9 + 10: Close chip
    trCanvas[IDX.CLOSE_BG] = {
        type = "rectangle", action = "fill",
        fillColor = {red=0.45,green=0.13,blue=0.13,alpha=0.95},
        strokeColor = {white=1, alpha=0.5}, strokeWidth = 1,
        roundedRectRadii = {xRadius=4, yRadius=4},
        frame = {x = trFrame.w - CLOSE_W - 8, y=CHIP_Y, w=CLOSE_W, h=CHIP_H},
    }
    trCanvas[IDX.CLOSE_TEXT] = {
        type = "text", text = "✕",
        textColor = {white=1}, textSize = 14, textAlignment = "center",
        frame = {x = trFrame.w - CLOSE_W - 8, y=CHIP_Y+3, w=CLOSE_W, h=CHIP_H-4},
    }
    -- 9 + 10: Resize handle (bottom right)
    trCanvas[IDX.RESIZE_BG] = {
        type = "rectangle", action = "fill",
        fillColor = {red=0.2,green=0.2,blue=0.2,alpha=0.85},
        strokeColor = {white=1, alpha=0.5}, strokeWidth = 1,
        frame = {x="100%", y="100%", w=20, h=20},
        transformation = hs.canvas.matrix.translate(-20, -20),
    }
    trCanvas[IDX.RESIZE_TEXT] = {
        type = "text", text = "⌟",
        textColor = {white=1, alpha=0.9}, textSize = 16, textAlignment = "center",
        frame = {x="100%", y="100%", w=20, h=20},
        transformation = hs.canvas.matrix.translate(-20, -20),
    }

    trCanvas:level(hs.canvas.windowLevels.floating)
    trCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    trCanvas:canvasMouseEvents(true, true, false, false)
    trCanvas:clickActivating(false)
    trCanvas:mouseCallback(onTrMouse)
    trCanvas:show()

    paused = false
    busy = false
    lastItems = {}
    snapW, snapH = 0, 0
    lastSrcRect = nil

    -- Eventtap for trCanvas drag/resize
    trDragTap = hs.eventtap.new(
        {hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp},
        function(e)
            if not trState.isDragging and not trState.isResizing then return false end
            local et = e:getType()
            if et == hs.eventtap.event.types.leftMouseUp then
                stopTrDrag()
                persistFrames()
                refreshControlVisuals()
                repaintOverlays()
                return false
            end
            local cur = hs.mouse.absolutePosition()
            local dx = cur.x - trState.startMousePos.x
            local dy = cur.y - trState.startMousePos.y
            if trState.isDragging and trCanvas then
                trCanvas:topLeft({
                    x = trState.startCanvasFrame.x + dx,
                    y = trState.startCanvasFrame.y + dy,
                })
            elseif trState.isResizing and trCanvas then
                local newW = math.max(MIN_W, trState.startCanvasFrame.w + dx)
                local newH = math.max(MIN_H, trState.startCanvasFrame.h + dy)
                trCanvas:size({w = newW, h = newH})
                refreshControlVisuals()
                repaintOverlays()
            end
            return false
        end)

    -- Eventtap for srcCanvas drag/resize
    srcDragTap = hs.eventtap.new(
        {hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp},
        function(e)
            if not srcState.isDragging and not srcState.isResizing then return false end
            local et = e:getType()
            if et == hs.eventtap.event.types.leftMouseUp then
                stopSrcDrag()
                persistFrames()
                lastItems = {}
                repaintOverlays()
                if not paused then doTranslate() end
                return false
            end
            local cur = hs.mouse.absolutePosition()
            local dx = cur.x - srcState.startMousePos.x
            local dy = cur.y - srcState.startMousePos.y
            if srcState.isDragging and srcRect then
                srcRect.x = srcState.startCanvasFrame.x + dx
                srcRect.y = srcState.startCanvasFrame.y + dy
                layoutSrcParts()
            elseif srcState.isResizing and srcRect then
                srcRect.w = math.max(MIN_W, srcState.startCanvasFrame.w + dx)
                srcRect.h = math.max(MIN_H, srcState.startCanvasFrame.h + dy)
                layoutSrcParts()
            end
            return false
        end)

    -- Timers
    trLiveTimer = hs.timer.doEvery(1/SNAPSHOT_FPS, tick)
    trTranslateTimer = hs.timer.doEvery(TRANSLATE_INTERVAL, function()
        if paused or busy then return end
        -- Re-translate when source rect has moved/resized OR on interval
        doTranslate()
    end)

    refreshControlVisuals()
    doTranslate()
end

function M.stop()
    persistFrames()
    if trLiveTimer      then trLiveTimer:stop();      trLiveTimer = nil      end
    if trTranslateTimer then trTranslateTimer:stop(); trTranslateTimer = nil end
    stopTrDrag()
    stopSrcDrag()
    if trDragTap  then trDragTap:stop();  trDragTap  = nil end
    if srcDragTap then srcDragTap:stop(); srcDragTap = nil end
    if trCanvas   then trCanvas:delete();  trCanvas  = nil end
    if srcParts then
        for _, c in pairs(srcParts) do c:delete() end
        srcParts = nil
    end
    srcRect = nil
    trLockedScreen = nil
    lastItems = {}
    snapW, snapH = 0, 0
    if serverTask then
        serverTask:terminate()
        serverTask = nil
    end
    paused = false
    busy = false
    lastSrcRect = nil
end

function M.toggle()
    if trCanvas then M.stop() else M.start() end
end

function M.translateNow()
    if trCanvas then doTranslate() end
end

function M.togglePause()
    if not trCanvas then return end
    paused = not paused
    refreshControlVisuals()
    if not paused then doTranslate() end
end

function M.isOpen() return trCanvas ~= nil end
function M.isPaused() return paused end
function M.isBusy() return busy end

-- ===== Hotkeys =====
hs.hotkey.bind({"ctrl","alt","cmd"},         "Y", function() M.toggle() end)
hs.hotkey.bind({"ctrl","alt","cmd","shift"}, "Y", function() M.translateNow() end)
hs.hotkey.bind({"ctrl","alt","cmd"},         "P", function() M.togglePause() end)

-- ===== Menubar shape (consumed by menubar_hub) =====
local trMenu = hs.menubar.new()

local function iconChar()
    if busy then return "🌀"
    elseif paused and trCanvas then return "⏸"
    elseif trCanvas then return "🌐"
    else return "🈂️" end
end

local function refreshTrMenuIcon()
    if not trMenu then return end
    trMenu:setTitle(iconChar())
    trMenu:setTooltip("Screen Translator")
end

local function buildTrMenu()
    refreshTrMenuIcon()
    local open = trCanvas ~= nil
    return {
        { title = open and "Close Translator" or "Open Translator",
          fn = function() M.toggle() end },
        { title = paused and "Resume Live Translate" or "Pause Live Translate",
          fn = function() M.togglePause() end,
          disabled = not open },
        { title = "Translate Now",
          fn = function() M.translateNow() end,
          disabled = not open },
        { title = "-" },
        { title = "Rebuild OCR Helper",
          fn = function()
              os.remove(OCR_HELPER)
              if ensureHelper() then hs.alert.show("OCR helper built") end
          end },
        { title = "Edit HSTranslate Shortcut",
          fn = function() hs.execute("open -a Shortcuts") end },
        { title = "-" },
        { title = "Hotkeys", disabled = true },
        { title = "  Toggle Overlay     ⌃⌥⌘Y",  disabled = true },
        { title = "  Translate Now      ⌃⌥⌘⇧Y", disabled = true },
        { title = "  Pause / Resume     ⌃⌥⌘P",  disabled = true },
    }
end

if trMenu then
    trMenu:setMenu(buildTrMenu)
    refreshTrMenuIcon()
end

return {
    title = "Screen Translator",
    icon = iconChar,
    buildMenu = buildTrMenu,
    menubar = trMenu,
    toggle = M.toggle,
    start = M.start,
    stop = M.stop,
    translateNow = M.translateNow,
    togglePause = M.togglePause,
    isOpen = M.isOpen,
}
