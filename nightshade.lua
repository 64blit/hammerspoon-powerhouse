-------------------------------------------------
-- Nightshade Module (Software Overlay Edition)
-- This approach bypasses High-End Display limitations (HDR / Reference Modes)
-- by drawing a 'click-through' tinted rectangle over every active screen.
-------------------------------------------------
local nightshade = {}

-- Store canvases globally so they aren't garbage collected
nightshade.canvases = {}

-- Default Configuration
local config = {
    strength = 0.5,         -- Alpha of the overlay (0.0 to 1.0, e.g., 0.2 is a 20% warm tint)
    color = { red = 1.0, green = 0.45, blue = 0.0 }, -- Warm Orange/Amber tint
    nightStart = "20:00",   -- Start time 
    nightEnd = "07:00"      -- End time
}

local function isNightTime()
    local current = os.date("*t")
    local hours = current.hour + (current.min / 60.0)
    
    local sH, sM = config.nightStart:match("(%d+):(%d+)")
    local eH, eM = config.nightEnd:match("(%d+):(%d+)")
    if not sH or not eH then return false end
    
    local startH = tonumber(sH) + (tonumber(sM)/60)
    local endH = tonumber(eH) + (tonumber(eM)/60)
    
    if startH > endH then
        -- Crosses midnight (e.g. 20:00 to 07:00)
        return hours >= startH or hours < endH
    else
        -- Same day (e.g. 18:00 to 23:00)
        return hours >= startH and hours < endH
    end
end

function nightshade.enable()
    if #nightshade.canvases > 0 then return end -- already enabled
    
    for _, screen in ipairs(hs.screen.allScreens()) do
        local f = screen:fullFrame()
        local c = hs.canvas.new(f)
        
        -- Set to a very high level (just below cursor) to overlay all windows
        c:level(hs.canvas.windowLevels.cursor - 1)
        
        -- Make it ignore the window cycle, stay stationary, and span all spaces
        -- Importantly, without a mouseCallback, hs.canvas acts strictly click-through!
        c:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + 
                   hs.drawing.windowBehaviors.stationary + 
                   hs.drawing.windowBehaviors.ignoresCycle)
        
        c:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = { 
                red = config.color.red, 
                green = config.color.green, 
                blue = config.color.blue, 
                alpha = config.strength 
            },
            compositeRule = "multiply",
            frame = { x = 0, y = 0, w = f.w, h = f.h }
        })
        c:show()
        table.insert(nightshade.canvases, c)
    end
end

function nightshade.disable()
    for _, c in ipairs(nightshade.canvases) do
        c:delete()
    end
    nightshade.canvases = {}
end

local checkTimer = nil

function nightshade.start(customConfig)
    if customConfig then
        for k, v in pairs(customConfig) do
            config[k] = v
        end
    end
    
    -- Evaluate immediately upon startup / reload
    if isNightTime() then 
        nightshade.enable() 
    else 
        nightshade.disable() 
    end
    
    -- Start periodic time-check (runs every 60 seconds)
    if checkTimer then checkTimer:stop() end
    checkTimer = hs.timer.doEvery(60, function()
        if isNightTime() then
            nightshade.enable()
        else
            nightshade.disable()
        end
    end)
end

function nightshade.stop()
    if checkTimer then checkTimer:stop() end
    nightshade.disable()
end

function nightshade.toggle()
    if #nightshade.canvases > 0 then
        nightshade.disable()
    else
        nightshade.enable()
    end
end

return nightshade
