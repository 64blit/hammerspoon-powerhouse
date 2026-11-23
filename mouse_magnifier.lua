-------------------------------------------------
-- Mouse Magnifier with Recording
--
-- Zoom range: from "fit whole screen" (zoom < 1) up to 5x+.
-- Recording: ffmpeg avfoundation, live crop to canvas frame, h264 videotoolbox -> mp4 (+ gif/webm).
-------------------------------------------------

local env = require("env_loader")
local home = os.getenv("HOME") or ""

local magMenu = hs.menubar.new()
local magCanvas = nil
local magTimer = nil
local magZoom = 2
local magDragTap = nil
local magClickTap = nil
local magLockedScreen = nil

-- Performance knobs
local MAG_FPS = tonumber(env.get("MAGNIFIER_FPS", "25")) or 25
local MAG_FRAME_INTERVAL = 1 / MAG_FPS
local MIN_CANVAS = 150

-- Canvas element indices
local EL_BG, EL_IMG, EL_CURSOR, EL_RING, EL_BORDER = 1, 2, 3, 4, 5
local EL_ZIN_BG, EL_ZIN_TXT, EL_ZOUT_BG, EL_ZOUT_TXT = 6, 7, 8, 9
local EL_FIT_BG, EL_FIT_TXT, EL_REC_BG, EL_REC_ICON = 10, 11, 12, 13
local EL_RESIZE_BG, EL_RESIZE_TXT = 14, 15
local UI_ELEMENTS = {EL_BORDER, EL_ZIN_BG, EL_ZIN_TXT, EL_ZOUT_BG, EL_ZOUT_TXT,
                     EL_FIT_BG, EL_FIT_TXT, EL_REC_BG, EL_REC_ICON, EL_RESIZE_BG, EL_RESIZE_TXT}

-- Button hit boxes (canvas coords)
local BTN = {
    zoomIn  = {x = 10,  y = 10, w = 30, h = 30},
    zoomOut = {x = 50,  y = 10, w = 30, h = 30},
    fit     = {x = 90,  y = 10, w = 30, h = 30},
    record  = {x = 130, y = 10, w = 30, h = 30},
}

local magFocus = {x = 0, y = 0}
local magClickAnim = {active = false, startTime = 0}
local magZoomPulse = 0
local CLICK_ANIM_DURATION = tonumber(env.get("MAGNIFIER_CLICK_DURATION", "0.6")) or 0.6  -- seconds
local CLICK_ZOOM_PULSE = tonumber(env.get("MAGNIFIER_CLICK_PULSE", "0.04")) or 0.04     -- fraction of current zoom

local magState = {
    isDragging = false,
    isResizing = false,
    startMousePos = nil,
    startCanvasFrame = nil,
}

local magDirty = true   -- force a redraw (zoom / resize changed)

-- Recording State
local magRecording = false
local magStartTime = 0
local magRecordBasePath = env.getPath("MAGNIFIER_RECORDINGS_PATH", "~/Movies/Screen Captures")
local magRecordAudio = (env.get("MAGNIFIER_RECORD_AUDIO", "0") == "1")
local magExportGif = (env.get("MAGNIFIER_EXPORT_GIF", "1") == "1")
local magExportWebm = (env.get("MAGNIFIER_EXPORT_WEBM", "0") == "1")
local magCurrentSessionPath = nil
local magRecordingTask = nil
local magUIHidden = false

local function detectBin(envKey, candidates)
    local configured = env.getPath(envKey)
    if configured and configured ~= "" then return configured end
    for _, p in ipairs(candidates) do
        if hs.fs.attributes(p) then return p end
    end
    return candidates[1]
end

local FFMPEG = detectBin("FFMPEG_PATH", { "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg" })
local GIFSKI = detectBin("GIFSKI_PATH", { "/opt/homebrew/bin/gifski", "/usr/local/bin/gifski" })
local MAG_RECORD_FPS = tonumber(env.get("MAGNIFIER_RECORD_FPS", "30")) or 30

-- Forward declarations
local toggleMagRecording
local setMagUIVisible

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function inBox(b, x, y)
    return x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h
end

local function stopMagDrag()
    if magDragTap then magDragTap:stop() end
    magState.isDragging = false
    magState.isResizing = false
    magState.startMousePos = nil
    magState.startCanvasFrame = nil
end

-- Zoom at which the entire locked screen fits inside the canvas
local function fitZoom()
    if not magCanvas or not magLockedScreen then return 1 end
    local f = magCanvas:frame()
    local s = magLockedScreen:fullFrame()
    return math.min(f.w / s.w, f.h / s.h)
end

local function setZoom(z, silent)
    local minZ = fitZoom()
    z = math.max(minZ, math.min(z, 10))
    magZoom = z
    magDirty = true
    hs.settings.set("magnifier_zoom", magZoom)
    if not silent then
        if math.abs(z - minZ) < 0.001 then
            hs.alert.show(string.format("Zoom: %.2fx (whole screen)", magZoom), 0.6)
        else
            hs.alert.show(string.format("Zoom: %.2fx", magZoom), 0.6)
        end
    end
end

local function zoomIn()
    if magZoom >= 1 then setZoom(magZoom + 0.25) else setZoom(math.min(1, magZoom * 1.25)) end
end

local function zoomOut()
    if magZoom > 1 then setZoom(math.max(1, magZoom - 0.25)) else setZoom(magZoom * 0.8) end
end

local function zoomFit()
    setZoom(fitZoom())
end

-------------------------------------------------
-- Frame update
-------------------------------------------------

local function updateMagnifier()
    if not magCanvas or not magLockedScreen then return end

    local mousePos = hs.mouse.absolutePosition()
    magDirty = false

    local screenFrame = magLockedScreen:fullFrame()

    -- Clamp focus to locked screen
    magFocus.x = math.max(screenFrame.x, math.min(mousePos.x, screenFrame.x + screenFrame.w))
    magFocus.y = math.max(screenFrame.y, math.min(mousePos.y, screenFrame.y + screenFrame.h))

    -- Click animation
    if magClickAnim.active then
        local elapsed = hs.timer.secondsSinceEpoch() - magClickAnim.startTime
        if elapsed < CLICK_ANIM_DURATION then
            local progress = elapsed / CLICK_ANIM_DURATION
            -- Gentle ease in/out: sine hump 0 -> 1 -> 0
            local hump = math.sin(progress * math.pi)
            magZoomPulse = hump * CLICK_ZOOM_PULSE * magZoom
            magCanvas[EL_RING].strokeColor = {red = 0, green = 1, blue = 0.3, alpha = 1 - progress}
            magCanvas[EL_RING].radius = 4 + progress * 36
        else
            magClickAnim.active = false
            magZoomPulse = 0
            magCanvas[EL_RING].strokeColor = {red = 0, green = 1, blue = 0.3, alpha = 0}
            magCanvas[EL_RING].radius = 1
        end
    end

    local canvasFrame = magCanvas:frame()
    local w, h = canvasFrame.w, canvasFrame.h
    local effectiveZoom = magZoom + magZoomPulse

    -- Capture area (absolute coords). Never larger than the screen itself.
    local captureW = math.min(w / effectiveZoom, screenFrame.w)
    local captureH = math.min(h / effectiveZoom, screenFrame.h)
    local captureX = magFocus.x - captureW / 2
    local captureY = magFocus.y - captureH / 2

    captureX = math.max(screenFrame.x, math.min(captureX, screenFrame.x + screenFrame.w - captureW))
    captureY = math.max(screenFrame.y, math.min(captureY, screenFrame.y + screenFrame.h - captureH))

    local snapshot = magLockedScreen:snapshot(
        hs.geometry.rect(captureX - screenFrame.x, captureY - screenFrame.y, captureW, captureH))
    if snapshot then
        magCanvas[EL_IMG].image = snapshot
    end

    -- The image is scaled proportionally and centred, so work out the real
    -- on-canvas scale + letterbox offset (identity when zoom >= 1).
    local drawScale = math.min(w / captureW, h / captureH)
    local offX = (w - captureW * drawScale) / 2
    local offY = (h - captureH * drawScale) / 2

    local cursorX = offX + (mousePos.x - captureX) * drawScale
    local cursorY = offY + (mousePos.y - captureY) * drawScale

    -- Cursor overlay: full size at >= 1x, shrinks with the view when zoomed out
    local k = math.max(0.25, math.min(1, drawScale))
    magCanvas[EL_CURSOR].frame = {x = cursorX - 16 * k, y = cursorY, w = 64 * k, h = 64 * k}
    magCanvas[EL_CURSOR].transformation = hs.canvas.matrix.translate(-12 * k, 0)
    magCanvas[EL_RING].center = {x = cursorX, y = cursorY}
end

-------------------------------------------------
-- Canvas build / teardown
-------------------------------------------------

local function buttonPair(idxBg, idxTxt, box, label, textSize)
    magCanvas[idxBg] = {
        type = "rectangle",
        fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95},
        strokeColor = {white = 1},
        strokeWidth = 1,
        roundedRectRadii = {xRadius = 4, yRadius = 4},
        frame = {x = box.x, y = box.y, w = box.w, h = box.h},
    }
    magCanvas[idxTxt] = {
        type = "text",
        text = label,
        textColor = {white = 1},
        textSize = textSize or 22,
        textAlignment = "center",
        frame = {x = box.x, y = box.y + 2, w = box.w, h = box.h},
    }
end

local function closeMagnifier()
    local frame = magCanvas:frame()
    hs.settings.set("magnifier_x", frame.x)
    hs.settings.set("magnifier_y", frame.y)
    hs.settings.set("magnifier_w", frame.w)
    hs.settings.set("magnifier_h", frame.h)
    hs.settings.set("magnifier_zoom", magZoom)

    if magTimer then magTimer:stop() end
    magTimer = nil
    if magRecording then toggleMagRecording() end
    stopMagDrag()
    if magDragTap then magDragTap:stop(); magDragTap = nil end
    if magClickTap then magClickTap:stop(); magClickTap = nil end
    magCanvas:delete()
    magCanvas = nil
    magLockedScreen = nil
    magUIHidden = false
end

local function toggleMagnifier()
    if magCanvas then
        closeMagnifier()
        return
    end

    magLockedScreen = hs.mouse.getCurrentScreen()
    local screenFrame = magLockedScreen:fullFrame()
    local mousePos = hs.mouse.absolutePosition()
    magFocus.x, magFocus.y = mousePos.x, mousePos.y
    magDirty = true

    local savedZoom = hs.settings.get("magnifier_zoom")
    if savedZoom then magZoom = savedZoom end

    local startW = hs.settings.get("magnifier_w") or 300
    local startH = hs.settings.get("magnifier_h") or 300
    local savedX = hs.settings.get("magnifier_x")
    local savedY = hs.settings.get("magnifier_y")
    local startX, startY

    if savedX and savedY then
        for _, screen in pairs(hs.screen.allScreens()) do
            local sFrame = screen:fullFrame()
            if (savedX < sFrame.x + sFrame.w) and (savedX + startW > sFrame.x) and
               (savedY < sFrame.y + sFrame.h) and (savedY + startH > sFrame.y) then
                startX, startY = savedX, savedY
                break
            end
        end
    end

    if not startX then
        startX = mousePos.x + 30
        startY = mousePos.y + 30
        if startX + startW > screenFrame.x + screenFrame.w then startX = mousePos.x - startW - 30 end
        if startY + startH > screenFrame.y + screenFrame.h then startY = mousePos.y - startH - 30 end
    end

    magCanvas = hs.canvas.new({x = startX, y = startY, w = startW, h = startH})

    magCanvas[EL_BG] = {
        type = "rectangle",
        action = "fill",
        fillColor = {black = 1},
        frame = {x = 0, y = 0, w = "100%", h = "100%"},
    }

    magCanvas[EL_IMG] = {
        type = "image",
        action = "fill",
        imageScaling = "scaleProportionally",
        imageAlignment = "center",
        frame = {x = 0, y = 0, w = "100%", h = "100%"},
    }

    local cursorPath = env.getPath("MAGNIFIER_CURSOR_PATH", hs.configdir .. "/assets/cursor_hand.png")
    local cursorImg = hs.image.imageFromPath(cursorPath)
        or hs.image.imageFromName("NSHandCursor")
        or hs.image.imageFromName("NSDefaultCursor")
    magCanvas[EL_CURSOR] = {
        type = "image",
        image = cursorImg,
        frame = {x = "49%", y = "50%", w = 64, h = 64},
        transformation = hs.canvas.matrix.translate(-12, 0),
        imageAlpha = 0.9,
    }

    magCanvas[EL_RING] = {
        type = "circle",
        action = "stroke",
        center = {x = "50%", y = "50%"},
        radius = 1,
        strokeColor = {red = 0, green = 1, blue = 0.3, alpha = 0},
        strokeWidth = 3,
    }

    magCanvas[EL_BORDER] = {
        type = "rectangle",
        action = "stroke",
        strokeColor = {white = 1},
        strokeWidth = 4,
        frame = {x = 0, y = 0, w = "100%", h = "100%"},
    }

    buttonPair(EL_ZIN_BG, EL_ZIN_TXT, BTN.zoomIn, "+")
    buttonPair(EL_ZOUT_BG, EL_ZOUT_TXT, BTN.zoomOut, "−")
    buttonPair(EL_FIT_BG, EL_FIT_TXT, BTN.fit, "⤢", 18)

    magCanvas[EL_REC_BG] = {
        type = "rectangle",
        fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95},
        strokeColor = {white = 1},
        strokeWidth = 1,
        roundedRectRadii = {xRadius = 4, yRadius = 4},
        frame = {x = BTN.record.x, y = BTN.record.y, w = BTN.record.w, h = BTN.record.h},
    }
    magCanvas[EL_REC_ICON] = {
        type = "circle",
        action = "fill",
        fillColor = {red = 1, green = 0, blue = 0, alpha = 1},
        center = {x = BTN.record.x + 15, y = BTN.record.y + 15},
        radius = 6,
    }

    magCanvas[EL_RESIZE_BG] = {
        type = "rectangle",
        fillColor = {red = 0.2, green = 0.2, blue = 0.2, alpha = 0.8},
        strokeColor = {white = 1, alpha = 0.5},
        strokeWidth = 1,
        frame = {x = "100%", y = "100%", w = 20, h = 20},
        transformation = hs.canvas.matrix.translate(-20, -20),
    }
    magCanvas[EL_RESIZE_TXT] = {
        type = "text",
        text = "⌟",
        textColor = {white = 1, alpha = 0.9},
        textSize = 16,
        textAlignment = "center",
        frame = {x = "100%", y = "100%", w = 20, h = 20},
        transformation = hs.canvas.matrix.translate(-20, -20),
    }

    magCanvas:level(hs.drawing.windowLevels.floating)
    magCanvas:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    magCanvas:canvasMouseEvents(true, true, false, false)
    magCanvas:clickActivating(false)
    magCanvas:show()

    -- Global click detection for the click ring
    magClickTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function()
        magClickAnim.active = true
        magClickAnim.startTime = hs.timer.secondsSinceEpoch()
        return false
    end)
    magClickTap:start()

    -- Drag / resize (global so it keeps working outside the window)
    magDragTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp}, function(e)
        if not magState.isDragging and not magState.isResizing then return false end
        if e:getType() == hs.eventtap.event.types.leftMouseUp then
            stopMagDrag()
            magDirty = true
            return false
        end
        local cur = hs.mouse.absolutePosition()
        local dx = cur.x - magState.startMousePos.x
        local dy = cur.y - magState.startMousePos.y
        if magState.isDragging and magCanvas then
            magCanvas:topLeft({x = magState.startCanvasFrame.x + dx, y = magState.startCanvasFrame.y + dy})
        elseif magState.isResizing and magCanvas then
            magCanvas:size({
                w = math.max(MIN_CANVAS, magState.startCanvasFrame.w + dx),
                h = math.max(MIN_CANVAS, magState.startCanvasFrame.h + dy),
            })
            -- Keep zoom >= fit as the frame shrinks
            if magZoom < fitZoom() then setZoom(fitZoom(), true) end
            magDirty = true
        end
        return false
    end)

    magCanvas:mouseCallback(function(canvas, event, id, x, y)
        if event ~= "mouseDown" then return end
        local f = canvas:frame()

        if not magUIHidden then
            if inBox(BTN.zoomIn, x, y) then zoomIn(); return end
            if inBox(BTN.zoomOut, x, y) then zoomOut(); return end
            if inBox(BTN.fit, x, y) then zoomFit(); return end
        end
        -- Record button stays clickable while its UI is hidden (to stop recording)
        if inBox(BTN.record, x, y) then toggleMagRecording(); return end

        magState.startMousePos = hs.mouse.absolutePosition()
        magState.startCanvasFrame = f
        if x > (f.w - 25) and y > (f.h - 25) then
            magState.isResizing = true
        else
            magState.isDragging = true
        end
        if magDragTap then magDragTap:start() end
    end)

    -- Clamp restored zoom to what fits
    if magZoom < fitZoom() then setZoom(fitZoom(), true) end

    -- Self-scheduling frame loop: next frame is queued only after this one
    -- finishes drawing, so slow snapshots never pile up into a burst.
    local function frameLoop()
        if not magCanvas then return end
        local t0 = hs.timer.secondsSinceEpoch()
        local ok, err = pcall(updateMagnifier)
        if not ok then print("MagRecorder frame error: " .. tostring(err)) end
        local elapsed = hs.timer.secondsSinceEpoch() - t0
        local wait = math.max(0.002, MAG_FRAME_INTERVAL - elapsed)
        magTimer = hs.timer.doAfter(wait, frameLoop)
    end
    frameLoop()
end

-------------------------------------------------
-- UI hide / show for clean recordings
-------------------------------------------------

setMagUIVisible = function(visible)
    if not magCanvas then return end
    if visible == (not magUIHidden) then return end
    for _, i in ipairs(UI_ELEMENTS) do
        if magCanvas[i] then
            if visible then
                magCanvas[i].action = magCanvas[i].type == "text" and "fill"
                    or (i == EL_BORDER and "stroke")
                    or (i == EL_REC_ICON and "fill")
                    or "strokeAndFill"
            else
                magCanvas[i].action = "skip"
            end
        end
    end
    magUIHidden = not visible
end

-------------------------------------------------
-- Recording
-------------------------------------------------

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function buildPostScript(sessionPath)
    -- Runs after output.mp4 is finalised. Each export is independent.
    local lines = {
        "cd " .. shq(sessionPath) .. " || exit 1",
        "LOG=convert.log; : > \"$LOG\"",
        "[ -s output.mp4 ] || { echo 'no output.mp4' >>\"$LOG\"; exit 1; }",
    }
    if magExportGif then
        table.insert(lines, "if [ -x " .. shq(GIFSKI) .. " ]; then")
        table.insert(lines, "  mkdir -p frames && " .. shq(FFMPEG) .. " -y -hide_banner -loglevel error -i output.mp4 -vf \"fps=15,scale='min(800,iw)':-2\" frames/frame%04d.png >>\"$LOG\" 2>&1 && " .. shq(GIFSKI) .. " --fps 15 --quality 70 -o output.gif frames/*.png >>\"$LOG\" 2>&1 || echo 'gif failed' >>\"$LOG\"")
        table.insert(lines, "  rm -rf frames")
        table.insert(lines, "else echo 'gifski not found, skipping gif' >>\"$LOG\"; fi")
    end
    if magExportWebm then
        table.insert(lines, shq(FFMPEG) .. " -y -hide_banner -loglevel error -i output.mp4 -c:v libvpx-vp9 -b:v 0 -crf 32 -deadline realtime -cpu-used 8 -row-mt 1 -an output.webm >>\"$LOG\" 2>&1 || echo 'webm failed' >>\"$LOG\"")
    end
    table.insert(lines, "open .")
    table.insert(lines, "exit 0")
    return table.concat(lines, "\n")
end

-- avfoundation "Capture screen N" follows CGDisplay order == hs.screen.allScreens() order.
local function avScreenIndex(screen)
    for i, s in ipairs(hs.screen.allScreens()) do
        if s:id() == screen:id() then return i - 1 end
    end
    return 0
end

local function startRecording()
    local date = os.date("%Y-%m-%d_%H-%M-%S")
    magCurrentSessionPath = magRecordBasePath .. "/" .. date
    hs.execute("mkdir -p " .. shq(magCurrentSessionPath))
    if not hs.fs.attributes(magCurrentSessionPath) then
        hs.alert.show("Cannot create " .. magCurrentSessionPath)
        return
    end

    local frame = magCanvas:frame()

    -- Screen the canvas centre sits on (may differ from the magnified screen)
    local cx, cy = frame.x + frame.w / 2, frame.y + frame.h / 2
    local screen = hs.screen.mainScreen()
    for _, s in ipairs(hs.screen.allScreens()) do
        local sf = s:fullFrame()
        if cx >= sf.x and cx < sf.x + sf.w and cy >= sf.y and cy < sf.y + sf.h then
            screen = s; break
        end
    end
    local sf = screen:fullFrame()
    local scale = (screen:currentMode() or {}).scale or 1
    local function even(v) return math.floor(v / 2) * 2 end
    local cropW = even(math.min(frame.w, sf.x + sf.w - frame.x) * scale)
    local cropH = even(math.min(frame.h, sf.y + sf.h - frame.y) * scale)
    local cropX = even(math.max(0, frame.x - sf.x) * scale)
    local cropY = even(math.max(0, frame.y - sf.y) * scale)

    local outFile = magCurrentSessionPath .. "/output.mp4"
    local args = {
        "-hide_banner", "-loglevel", "error", "-y",
        "-f", "avfoundation",
        "-capture_cursor", "1",
        "-capture_mouse_clicks", "1",
        "-framerate", tostring(MAG_RECORD_FPS),
        "-pixel_format", "uyvy422",
        "-i", string.format("Capture screen %d:%s", avScreenIndex(screen), magRecordAudio and "default" or "none"),
        "-vf", string.format("crop=%d:%d:%d:%d", cropW, cropH, cropX, cropY),
        "-c:v", "h264_videotoolbox", "-b:v", "8M",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
    }
    if magRecordAudio then
        table.insert(args, "-c:a"); table.insert(args, "aac")
        table.insert(args, "-b:a"); table.insert(args, "128k")
    end
    table.insert(args, outFile)

    print("MagRecorder: " .. FFMPEG .. " " .. table.concat(args, " "))

    local sessionPath = magCurrentSessionPath
    magRecordingTask = hs.task.new(FFMPEG, function(exitCode, stdOut, stdErr)
        magRecordingTask = nil
        print(string.format("MagRecorder: ffmpeg exited code=%s stderr=%s", tostring(exitCode), (stdErr or ""):sub(1, 500)))
        local attrs = hs.fs.attributes(outFile)
        if not attrs or attrs.size == 0 then
            hs.alert.show("Recording failed (no file)\n" .. (stdErr or ""), 4)
            print("MagRecorder ffmpeg error: code=" .. tostring(exitCode) .. " " .. (stdErr or ""))
            return
        end

        hs.alert.show("Recording saved\n" .. sessionPath, 2)
        hs.task.new("/bin/bash", function(c, o, e)
            if c ~= 0 then
                hs.alert.show("GIF/WebM export failed — see convert.log", 4)
                print("MagRecorder export error: " .. (e or "") .. (o or ""))
            end
        end, {"-c", buildPostScript(sessionPath)}):start()
    end, args)

    if not magRecordingTask:start() then
        hs.alert.show("Could not start ffmpeg at " .. FFMPEG)
        magRecordingTask = nil
        return
    end

    magRecording = true
    magStartTime = hs.timer.secondsSinceEpoch()
    setMagUIVisible(false)
    hs.alert.show("Recording started", 1)
end

local function stopRecording()
    magRecording = false
    setMagUIVisible(true)
    if magRecordingTask then
        magRecordingTask:interrupt()   -- SIGINT: ffmpeg finalises the mp4
    end
    hs.alert.show(string.format("Recording stopped (%.1fs)", hs.timer.secondsSinceEpoch() - magStartTime), 1.5)
end

toggleMagRecording = function()
    if not magCanvas then
        hs.alert.show("Magnifier not open")
        return
    end
    if magRecording then stopRecording() else startRecording() end
end

-------------------------------------------------
-- Menubar Dropdown
-------------------------------------------------

local function openRecordingsFolder()
    hs.execute("mkdir -p " .. shq(magRecordBasePath) .. " && open " .. shq(magRecordBasePath))
end

local function refreshMagMenuIcon()
    if not magMenu then return end
    if magRecording then
        magMenu:setTitle("🔴"); magMenu:setTooltip("Magnifier: Recording")
    elseif magCanvas then
        magMenu:setTitle("🔍"); magMenu:setTooltip("Magnifier: ON")
    else
        magMenu:setTitle("🔎"); magMenu:setTooltip("Magnifier: OFF")
    end
end

local function buildMagMenu()
    refreshMagMenuIcon()
    local magnifierOpen = magCanvas ~= nil
    local zoomItems = {
        {title = "Fit Whole Screen", fn = zoomFit},
        {title = "-"},
    }
    for _, z in ipairs({0.5, 0.75, 1, 1.5, 2, 2.5, 3, 4, 5}) do
        table.insert(zoomItems, {
            title = string.format("%.2gx", z),
            checked = (math.abs(magZoom - z) < 0.01),
            fn = function() setZoom(z) end,
        })
    end

    return {
        { title = magnifierOpen and "Close Magnifier" or "Open Magnifier", fn = toggleMagnifier },
        { title = magRecording and "Stop Recording" or "Start Recording",
          fn = toggleMagRecording, disabled = not magnifierOpen },
        { title = "-" },
        { title = "Zoom Level", menu = zoomItems, disabled = not magnifierOpen },
        { title = "Open Recordings Folder", fn = openRecordingsFolder },
        { title = "-" },
        { title = "Hotkeys", disabled = true },
        { title = "  Toggle Magnifier  ⌃⌥⌘M", disabled = true },
        { title = "  Toggle Recording  ⌃⌥⌘R", disabled = true },
        { title = "  Zoom In / Out     ⌃⌥⌘= / ⌃⌥⌘-", disabled = true },
        { title = "  Fit Whole Screen  ⌃⌥⌘0", disabled = true },
    }
end

if magMenu then
    magMenu:setMenu(buildMagMenu)
    refreshMagMenuIcon()
end

-- Keep the menubar icon in sync with state changes
local _origToggleMagnifier = toggleMagnifier
toggleMagnifier = function(...)
    local r = _origToggleMagnifier(...)
    refreshMagMenuIcon()
    return r
end

local _origToggleMagRecording = toggleMagRecording
toggleMagRecording = function(...)
    local r = _origToggleMagRecording(...)
    refreshMagMenuIcon()
    return r
end

hs.hotkey.bind({"ctrl", "alt", "cmd"}, "M", toggleMagnifier)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "R", toggleMagRecording)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "=", function() if magCanvas then zoomIn() end end)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "-", function() if magCanvas then zoomOut() end end)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "0", function() if magCanvas then zoomFit() end end)

return {
    title = "Magnifier / Screen Recording",
    icon = function()
        if magRecording then return "🔴"
        elseif magCanvas then return "🔍"
        else return "🔎" end
    end,
    buildMenu = buildMagMenu,
    menubar = magMenu,
    toggle = function() return toggleMagnifier() end,
    toggleRecording = function() return toggleMagRecording() end,
    zoomFit = zoomFit,
    isOpen = function() return magCanvas ~= nil end,
    isRecording = function() return magRecording end,
    _update = updateMagnifier,
}
