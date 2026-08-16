-------------------------------------------------
-- Mouse Magnifier with Recording
-------------------------------------------------

local magMenu = hs.menubar.new()
local magCanvas = nil
local magTimer = nil
local magZoom = 2
local magDragTap = nil
local magClickTap = nil  -- For detecting clicks anywhere
local magLockedScreen = nil  -- The screen object we are locked to

-- State for smooth focus interpolation
local magFocus = {x = 0, y = 0}

-- State for click animation
local magClickAnim = {
    active = false,
    startTime = 0,
    ringSize = 0
}
local magBaseZoom = 2  -- Base zoom level
local magZoomPulse = 0  -- Additional zoom from click animation

-- State for drag/resize
local magState = {
    isDragging = false,
    isResizing = false,
    startMousePos = nil,
    startCanvasFrame = nil
}

local env = require("env_loader")
local home = os.getenv("HOME") or ""

-- Recording State
local magRecording = false
local magRecordCount = 0
local magRecordBasePath = env.get("MAGNIFIER_RECORDINGS_PATH", home .. "/Movies/Screen Captures")
local magCurrentSessionPath = nil
local magRecordingTask = nil

local function stopMagDrag()
    if magDragTap then
        magDragTap:stop()
    end
    magState.isDragging = false
    magState.isResizing = false
    magState.startMousePos = nil
    magState.startCanvasFrame = nil
end

-- Forward declaration
local toggleMagRecording

-- Cache for UI components to handle visibility toggling



local function updateMagnifier()
    if not magCanvas or not magLockedScreen then return end
    
    local mousePos = hs.mouse.absolutePosition()
    local screenFrame = magLockedScreen:fullFrame()
    
    -- Clamp target to the locked screen bounds (absolute coords)
    local targetX = math.max(screenFrame.x, math.min(mousePos.x, screenFrame.x + screenFrame.w))
    local targetY = math.max(screenFrame.y, math.min(mousePos.y, screenFrame.y + screenFrame.h))
    
    -- Smooth interpolation (Lerp) for the image content
    local lerpFactor = 1.0
    magFocus.x = magFocus.x + (targetX - magFocus.x) * lerpFactor
    magFocus.y = magFocus.y + (targetY - magFocus.y) * lerpFactor
    
    -- Handle click animation
    if magClickAnim.active then
        local elapsed = hs.timer.secondsSinceEpoch() - magClickAnim.startTime
        local duration = 0.4  -- Animation duration in seconds
        
        if elapsed < duration then
            local progress = elapsed / duration
            -- Expanding ring animation
            magClickAnim.ringSize = progress * 40
            -- Zoom pulse: quick zoom in then back out
            local zoomProgress = 1 - math.abs(progress * 2 - 1)  -- 0 -> 1 -> 0
            magZoomPulse = zoomProgress * 0.1
            
            -- Update ring element (index 11) - grow radius directly
            if magCanvas[11] then
                local ringAlpha = 1 - progress
                magCanvas[11].strokeColor = {red = 0, green = 1, blue = 0.3, alpha = ringAlpha}
                magCanvas[11].radius = magClickAnim.ringSize
            end
        else
            magClickAnim.active = false
            magZoomPulse = 0
            if magCanvas[11] then
                magCanvas[11].strokeColor = {red = 0, green = 1, blue = 0.3, alpha = 0}
                magCanvas[11].radius = 1
            end
        end
    end
    
    local canvasFrame = magCanvas:frame()
    local w = canvasFrame.w
    local h = canvasFrame.h
    
    -- Calculate effective zoom (base + pulse)
    local effectiveZoom = magZoom + magZoomPulse
    
    -- Calculate capture area centered on the smooth focus point (absolute coords)
    local captureW = w / effectiveZoom
    local captureH = h / effectiveZoom
    local captureX = magFocus.x - (captureW / 2)
    local captureY = magFocus.y - (captureH / 2)

    -- Clamp capture area to screen bounds to prevent showing off-screen blackness
    if captureX < screenFrame.x then captureX = screenFrame.x end
    if captureY < screenFrame.y then captureY = screenFrame.y end
    if captureX + captureW > screenFrame.x + screenFrame.w then captureX = screenFrame.x + screenFrame.w - captureW end
    if captureY + captureH > screenFrame.y + screenFrame.h then captureY = screenFrame.y + screenFrame.h - captureH end
    
    -- Convert absolute coordinates to screen-relative coordinates
    local relativeX = captureX - screenFrame.x
    local relativeY = captureY - screenFrame.y
    
    local captureRect = hs.geometry.rect(relativeX, relativeY, captureW, captureH)
    
    -- Capture from the LOCKED screen using screen-relative coordinates
    local snapshot = magLockedScreen:snapshot(captureRect)
    
    if snapshot then
        magCanvas[1].image = snapshot
    end

    -- Update Cursor Position (Index 2)
    -- Calculate where the mouse is relative to the captured area (source pixels)
    local mouseRelX = mousePos.x - captureX
    local mouseRelY = mousePos.y - captureY
    
    -- Convert to canvas pixels
    local cursorCanvasX = mouseRelX * effectiveZoom
    local cursorCanvasY = mouseRelY * effectiveZoom
    
    if magCanvas[2] then
        
        magCanvas[2].frame = {
            x = cursorCanvasX - 16, -- Center 64px width on point
            y = cursorCanvasY , -- Center 64px height on point
            w = 64,
            h = 64
        }
        -- Keep the transformation from before which seemed to adjust the hotspot
        magCanvas[2].transformation = hs.canvas.matrix.translate(-12, 0)
    end
    
    -- Update Click Animation Ring (Index 11) to match cursor position
    if magCanvas[11] then
        magCanvas[11].center = {x = cursorCanvasX, y = cursorCanvasY}
    end
end

local function toggleMagnifier()
    -- If already open, close it
    if magCanvas then
        -- Save current settings before closing
        local frame = magCanvas:frame()
        hs.settings.set("magnifier_x", frame.x)
        hs.settings.set("magnifier_y", frame.y)
        hs.settings.set("magnifier_w", frame.w)
        hs.settings.set("magnifier_h", frame.h)
        hs.settings.set("magnifier_zoom", magZoom)
        
        if magTimer then magTimer:stop() end
        magTimer = nil
        if magRecordingTask then
            magRecordingTask:interrupt()
            magRecordingTask = nil
        end
        stopMagDrag()
        if magDragTap then
            magDragTap:stop()
            magDragTap = nil
        end
        if magClickTap then
            magClickTap:stop()
            magClickTap = nil
        end
        magCanvas:delete()
        magCanvas = nil
        magLockedScreen = nil
        magRecording = false -- Ensure recording state is reset


        return
    end
    
    -- Lock to the screen where the mouse currently is
    magLockedScreen = hs.mouse.getCurrentScreen()
    local screenFrame = magLockedScreen:fullFrame()
    local mousePos = hs.mouse.absolutePosition()
    
    -- Initialize focus immediately so there's no swoop-in from (0,0)
    magFocus.x = mousePos.x
    magFocus.y = mousePos.y
    
    -- Load saved settings or use defaults
    local savedZoom = hs.settings.get("magnifier_zoom")
    if savedZoom then magZoom = savedZoom end
    
    local savedW = hs.settings.get("magnifier_w") or 300
    local savedH = hs.settings.get("magnifier_h") or 300
    local savedX = hs.settings.get("magnifier_x")
    local savedY = hs.settings.get("magnifier_y")
    
    local startW, startH = savedW, savedH
    local startX, startY
    
    if savedX and savedY then


        local isOnScreen = false
        for _, screen in pairs(hs.screen.allScreens()) do
            local sFrame = screen:fullFrame()
            if (savedX < sFrame.x + sFrame.w) and (savedX + startW > sFrame.x) and
               (savedY < sFrame.y + sFrame.h) and (savedY + startH > sFrame.y) then
                isOnScreen = true
                break
            end
        end

        if isOnScreen then
            startX = savedX
            startY = savedY
        end
    end

    if not startX then
        -- Calculate default position near mouse
        startX = mousePos.x + 30
        startY = mousePos.y + 30
        
        -- Keep window on screen
        if startX + startW > screenFrame.x + screenFrame.w then
            startX = mousePos.x - startW - 30
        end
        if startY + startH > screenFrame.y + screenFrame.h then
            startY = mousePos.y - startH - 30
        end
    end

    magCanvas = hs.canvas.new({x = startX, y = startY, w = startW, h = startH})
    
    -- 1. Image (Bottom Layer)
    magCanvas[1] = {
        type = "image",
        action = "fill",
        frame = {x = 0, y = 0, w = "100%", h = "100%"}
    }
    
    -- 2. Cursor image indicator (top-middle aligned to center)
    local cursorPath = env.get("MAGNIFIER_CURSOR_PATH", hs.configdir .. "/assets/cursor_hand.png")
    local cursorImg = hs.image.imageFromPath(cursorPath) or hs.image.imageFromName("NSHandCursor") or hs.image.imageFromName("NSDefaultCursor")
    magCanvas[2] = {
        type = "image",
        image = cursorImg,
        frame = {x = "49%", y = "50%", w = 64, h = 64},
        transformation = hs.canvas.matrix.translate(-12, 0),  -- offset left by half width, no vertical offset
        imageAlpha = 0.9
    }

    -- 3. (Reserved - was outer ring, now unused but keeping index for click animation)
    magCanvas[3] = {
        type = "circle",
        action = "stroke",
        center = {x = "50%", y = "50%"},
        radius = 1,
        strokeColor = {red = 0, green = 0, blue = 0, alpha = 0},
        strokeWidth = 0
    }
    
    -- 4. Border
    magCanvas[4] = {
        type = "rectangle",
        action = "stroke",
        strokeColor = {white = 1},
        strokeWidth = 4,
        frame = {x = 0, y = 0, w = "100%", h = "100%"}
    }
    
    -- 5. Zoom In Button Background
    magCanvas[5] = {
        type = "rectangle",
        fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95},
        strokeColor = {white = 1},
        strokeWidth = 1,
        roundedRectRadii = {xRadius = 4, yRadius = 4},
        frame = {x = 10, y = 10, w = 30, h = 30}
    }
    -- 6. Zoom In Button Text
    magCanvas[6] = {
        type = "text",
        text = "+",
        textColor = {white = 1},
        textSize = 22,
        textAlignment = "center",
        frame = {x = 10, y = 12, w = 30, h = 30}
    }
    
    -- 7. Zoom Out Button Background
    magCanvas[7] = {
        type = "rectangle",
        fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95},
        strokeColor = {white = 1},
        strokeWidth = 1,
        roundedRectRadii = {xRadius = 4, yRadius = 4},
        frame = {x = 50, y = 10, w = 30, h = 30}
    }
    -- 8. Zoom Out Button Text
    magCanvas[8] = {
        type = "text",
        text = "−",
        textColor = {white = 1},
        textSize = 22,
        textAlignment = "center",
        frame = {x = 50, y = 12, w = 30, h = 30}
    }

    -- 9. Resize Handle
    magCanvas[9] = {
        type = "rectangle",
        fillColor = {red = 0.2, green = 0.2, blue = 0.2, alpha = 0.8},
        strokeColor = {white = 1, alpha = 0.5},
        strokeWidth = 1,
        frame = {x = "100%", y = "100%", w = 20, h = 20},
        transformation = hs.canvas.matrix.translate(-20, -20)
    }
    magCanvas[10] = {
        type = "text",
        text = "⌟",
        textColor = {white = 1, alpha = 0.9},
        textSize = 16,
        textAlignment = "center",
        frame = {x = "100%", y = "100%", w = 20, h = 20},
        transformation = hs.canvas.matrix.translate(-20, -20)
    }
    
    -- 11. Click animation ring (initially invisible)
    magCanvas[11] = {
        type = "circle",
        action = "stroke",
        center = {x = "50%", y = "50%"},
        radius = 1,
        strokeColor = {red = 0, green = 1, blue = 0.3, alpha = 0},
        strokeWidth = 3
    }

    -- 12. Record Button Background
    magCanvas[12] = {
        type = "rectangle",
        fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95},
        strokeColor = {white = 1},
        strokeWidth = 1,
        roundedRectRadii = {xRadius = 4, yRadius = 4},
        frame = {x = 90, y = 10, w = 30, h = 30}
    }
    
    -- 13. Record Button Icon (Red Circle initially)
    magCanvas[13] = {
        type = "circle",
        action = "fill",
        fillColor = {red = 1, green = 0, blue = 0, alpha = 1},
        center = {x = 105, y = 25},
        radius = 6,
        frame = {x = 90, y = 10, w = 30, h = 30}
    }
    
    magCanvas:level(hs.drawing.windowLevels.floating)
    magCanvas:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    
    -- Enable mouse events on the canvas
    magCanvas:canvasMouseEvents(true, true, false, true) -- mouseDown, mouseUp, mouseEnterExit, mouseMoved
    magCanvas:clickActivating(false) -- Don't activate app on click
    
    magCanvas:show()
    
    -- Global click detection for click animation
    magClickTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(e)
        -- Trigger click animation
        magClickAnim.active = true
        magClickAnim.startTime = hs.timer.secondsSinceEpoch()
        magClickAnim.ringSize = 0
        return false  -- Don't consume the event
    end)
    magClickTap:start()
    
    -- EventTap for Dragging/Resizing (handles mouse even outside window)
    magDragTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp}, function(e)
        if not magState.isDragging and not magState.isResizing then return false end
        
        local evtType = e:getType()
        if evtType == hs.eventtap.event.types.leftMouseUp then
            stopMagDrag()
            return false
        end
        
        local currentMouse = hs.mouse.absolutePosition()
        local dx = currentMouse.x - magState.startMousePos.x
        local dy = currentMouse.y - magState.startMousePos.y
        
        if magState.isDragging and magCanvas then
            magCanvas:topLeft({
                x = magState.startCanvasFrame.x + dx,
                y = magState.startCanvasFrame.y + dy
            })
        elseif magState.isResizing and magCanvas then
            local newW = math.max(150, magState.startCanvasFrame.w + dx)
            local newH = math.max(150, magState.startCanvasFrame.h + dy)
            magCanvas:size({w = newW, h = newH})
        end
        return false
    end)
    
    -- Canvas Click Handler
    magCanvas:mouseCallback(function(canvas, event, id, x, y)
        if event == "mouseDown" then
            local f = canvas:frame()
            
            -- Check Zoom In button area (10-40 x, 10-40 y)
            if x >= 10 and x <= 40 and y >= 10 and y <= 40 then
                magZoom = magZoom + 0.25
                hs.alert.show("Zoom: " .. magZoom .. "x")
                return
            end
            
            -- Check Zoom Out button area (50-80 x, 10-40 y)
            if x >= 50 and x <= 80 and y >= 10 and y <= 40 then
                magZoom = math.max(1, magZoom - 0.25)
                hs.alert.show("Zoom: " .. magZoom .. "x")
                return
            end


            
            -- Check Record Button area (90-120 x, 10-40 y)
            if x >= 90 and x <= 120 and y >= 10 and y <= 40 then
                toggleMagRecording()
                return
            end
            
            -- Prepare for drag or resize
            magState.startMousePos = hs.mouse.absolutePosition()
            magState.startCanvasFrame = f
            
            -- Check Resize area (bottom-right 25x25)
            if x > (f.w - 25) and y > (f.h - 25) then
                magState.isResizing = true
            else
                magState.isDragging = true
            end
            
            -- Start global event tap
            if magDragTap then magDragTap:start() end
        end
    end)
    
    -- Start the update timer
    magTimer = hs.timer.doEvery(0.01, updateMagnifier) -- ~60fps
end

local magSavedActions = {}

local function setMagUIVisible(visible)
    if not magCanvas then return end
    
    -- Determine current state by checking the Border element (index 4)
    -- If index 4 is 'skip', we assume the UI is hidden.
    local isHidden = false
    if magCanvas[4] and magCanvas[4].action == "skip" then
        isHidden = true
    end
    
    -- Avoid redundant updates
    if (visible and not isHidden) or (not visible and isHidden) then
        return
    end
    
    local indices = {4, 5, 6, 7, 8, 9, 10, 12, 13}
    local elements = magCanvas:canvasElements()
    
    if not visible then
        -- HIDE: Save actions and set to 'skip'
        for _, i in ipairs(indices) do
            if elements[i] then
                magSavedActions[i] = elements[i].action
                elements[i].action = "skip"
            end
        end
    else
        -- RESTORE: Restore saved actions
        for _, i in ipairs(indices) do
            if elements[i] then
                -- Unconditionally restore. If magSavedActions[i] is nil, 
                -- this sets action to nil, reverting to default (as expected)
                elements[i].action = magSavedActions[i]
            end
        end
    end
    
    magCanvas:replaceElements(elements)
end

toggleMagRecording = function()
    -- Only work if magnifier is open
    if not magCanvas then 
        hs.alert.show("Magnifier not open")
        return 
    end

    if magRecording then
        -- STOP RECORDING
        magRecording = false
        
        -- Restore UI (brings back Border and Record Button)
        setMagUIVisible(true)
        
        -- Stop the FFmpeg Task safely via Interrupt (SIGINT) to separate file
        if magRecordingTask then
            magRecordingTask:interrupt()
            magRecordingTask = nil
        end
        
        local duration = hs.timer.secondsSinceEpoch() - (magStartTime or 0)
        hs.alert.show(string.format("Recording Stopped (%.1fs)\nProcessing...", duration))
        
    else
        -- START RECORDING
        local date = os.date("%Y-%m-%d_%H-%M-%S")
        magCurrentSessionPath = magRecordBasePath .. "/" .. date
        hs.execute("mkdir -p '" .. magCurrentSessionPath .. "'")
        
        magRecording = true
        magStartTime = hs.timer.secondsSinceEpoch()
        
        -- Hide UI (Border, Buttons) for clean recording
        setMagUIVisible(false)
        
        hs.alert.show("Recording Started")
        
        -- Setup Recording Parameters
        local frame = magCanvas:frame()
        
        -- Identify the screen the canvas is primarily on
        local centerX = frame.x + (frame.w / 2)
        local centerY = frame.y + (frame.h / 2)
        local centerPoint = hs.geometry.point(centerX, centerY)
        
        local screen = hs.screen.mainScreen() -- Default
        local displayIndex = 1
        
        -- Iterate all screens to find which one contains the center point
        local allScreens = hs.screen.allScreens()
        for i, s in ipairs(allScreens) do
            local sFrame = s:fullFrame()
            -- Check if center point is within this screen's frame
            if centerX >= sFrame.x and centerX < (sFrame.x + sFrame.w) and
               centerY >= sFrame.y and centerY < (sFrame.y + sFrame.h) then
                screen = s
                displayIndex = i
                break
            end
        end
        
        -- DEBUG: Log framing info
        local scale = screen:currentMode().scale or 2.0
        local screenFrame = screen:fullFrame()
        
        local logContent = string.format([[
MagRecorder Start:
  Canvas Frame: %s
  Screen Frame: %s
  Screen ID: %s
  Display Index: %d
  Scale: %s
]], hs.inspect(frame), hs.inspect(screenFrame), screen:id(), displayIndex, tostring(scale))
        
        -- Helper to ensure dimensions are even
        local function makeEven(v) return math.floor(v / 2) * 2 end
        
        -- Calculate crop dimensions relative to screen origin
        local relX = frame.x - screenFrame.x
        local relY = frame.y - screenFrame.y
        
        local cropW = makeEven(frame.w * scale)
        local cropH = makeEven(frame.h * scale)
        local cropX = makeEven(relX * scale)
        local cropY = makeEven(relY * scale)
        
        local cropFilter = string.format("crop=%d:%d:%d:%d", cropW, cropH, cropX, cropY)
        logContent = logContent .. "  Crop Filter: " .. cropFilter .. "\n"
        
        local ffmpeg = "/usr/sbin/screencapture"
        local rawFile = magCurrentSessionPath .. "/raw.mov"
        
        -- Use user-adjusted display index if needed, otherwise default to calculated
        -- NOTE: If the user previously needed 'i + 1', they can modify 'displayIndex' here.
        -- displayIndex = displayIndex + 1 
        
        local args = {
            "-v",           -- Video mode
            "-C",           -- Capture cursor
            "-k",           -- Show clicks
            "-g",           -- Record audio (default input)
            "-D", tostring(displayIndex),
            rawFile
        }
        
        logContent = logContent .. "  Command: " .. ffmpeg .. " " .. hs.inspect(args) .. "\n"
        
        -- Print log to Console
        print(logContent)
        
        -- Write log to file
        local f = io.open("/tmp/hs_mag_debug.txt", "w")
        if f then f:write(logContent); f:close() end
        
        -- Start Recording Task
        magRecordingTask = hs.task.new(ffmpeg, function(exitCode, stdOut, stdErr)
            if not hs.fs.attributes(rawFile) then
                hs.alert.show("Recording Failed (No File)")
                print("Screencapture Error: " .. (stdErr or "Unknown"))
                return
            end

            hs.alert.show("Recording finished. Starting conversion...")
            
            -- Full verbose logging for the conversion command
            local cmd = string.format(
                'cd "%s" && ' ..
                '/opt/homebrew/bin/ffmpeg -i raw.mov -vf "%s" -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k output.mp4 && ' ..
                '/opt/homebrew/bin/ffmpeg -i raw.mov -vf "%s" -c:v libvpx-vp9 -b:v 0 -crf 30 -pix_fmt yuva420p output.webm && ' ..
                'mkdir -p frames && ' ..
                '/opt/homebrew/bin/ffmpeg -i raw.mov -vf "%s" -r 20 frames/frame%%04d.png && ' ..
                '/opt/homebrew/bin/gifski --fps 15 --quality 70 -o output.gif frames/frame*.png && ' ..
                'rm -rf frames raw.mov && ' ..
                'open .',
                magCurrentSessionPath, cropFilter, cropFilter, cropFilter
            )
            
            print("  Conversion CMD: " .. cmd)
            
            hs.task.new("/bin/bash", function(c, o, e)
                if c == 0 then
                    hs.alert.show("Processing Complete!")
                else
                    hs.alert.show("Processing Failed")
                    print("Conversion Error: " .. (e or "unknown")) 
                    print("Conversion Output: " .. (o or ""))
                end
            end, {"-c", cmd}):start()
            
        end, args)
        
        magRecordingTask:start()
    end
end

-------------------------------------------------
-- Menubar Dropdown
-------------------------------------------------
local function openRecordingsFolder()
    hs.execute("mkdir -p '" .. magRecordBasePath .. "' && open '" .. magRecordBasePath .. "'")
end

local function setMagZoom(z)
    magZoom = z
    hs.settings.set("magnifier_zoom", magZoom)
    hs.alert.show("Zoom: " .. magZoom .. "x")
end

local function refreshMagMenuIcon()
    if not magMenu then return end
    if magRecording then
        magMenu:setTitle("🔴")
        magMenu:setTooltip("Magnifier: Recording")
    elseif magCanvas then
        magMenu:setTitle("🔍")
        magMenu:setTooltip("Magnifier: ON")
    else
        magMenu:setTitle("🔎")
        magMenu:setTooltip("Magnifier: OFF")
    end
end

local function buildMagMenu()
    refreshMagMenuIcon()
    local magnifierOpen = magCanvas ~= nil
    local zoomOptions = {1, 1.5, 2, 2.5, 3, 4, 5}
    local zoomItems = {}
    for _, z in ipairs(zoomOptions) do
        table.insert(zoomItems, {
            title = string.format("%.2gx", z),
            checked = (math.abs(magZoom - z) < 0.01),
            fn = function() setMagZoom(z) end,
        })
    end

    return {
        { title = magnifierOpen and "Close Magnifier" or "Open Magnifier",
          fn = toggleMagnifier },
        { title = magRecording and "Stop Recording" or "Start Recording",
          fn = toggleMagRecording, disabled = not magnifierOpen },
        { title = "-" },
        { title = "Zoom Level", menu = zoomItems, disabled = not magnifierOpen },
        { title = "Open Recordings Folder", fn = openRecordingsFolder },
        { title = "-" },
        { title = "Hotkeys", disabled = true },
        { title = "  Toggle Magnifier  ⌃⌥⌘M", disabled = true },
        { title = "  Toggle Recording  ⌃⌥⌘R", disabled = true },
    }
end

if magMenu then
    magMenu:setMenu(buildMagMenu)
    refreshMagMenuIcon()
end

-- Wrap state-changing functions so the icon stays in sync
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

-- Re-bind hotkeys to the wrapped versions
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "M", toggleMagnifier)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "R", toggleMagRecording)

return {
    title = "Magnifier / Screen Recording",
    icon = function()
        if magRecording then return "🔴"
        elseif magCanvas then return "🔍"
        else return "🔎" end
    end,
    buildMenu = buildMagMenu,
    menubar = magMenu,
}
