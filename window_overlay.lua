-------------------------------------------------
-- Window Overlay (Picture-in-Picture)
-------------------------------------------------

local overlay = nil
local timer = nil
local captureWin = nil
local overlayWidth, overlayHeight = 400, 300  -- adjust size

local function toggleOverlay()
    if timer then
        -- Stop updating
        timer:stop()
        timer = nil
        if overlay then
            overlay:delete()
            overlay = nil
        end
        captureWin = nil
        return
    end

    -- Capture the currently focused window
    captureWin = hs.window.focusedWindow()
    if not captureWin then return end

    -- Position overlay in bottom-right of main screen
    local screenFrame = hs.screen.mainScreen():frame()
    local x = screenFrame.x + screenFrame.w - overlayWidth - 20
    local y = screenFrame.y + screenFrame.h - overlayHeight - 40

    -- Create overlay if it doesn't exist
    overlay = hs.drawing.image(hs.geometry.rect(x, y, overlayWidth, overlayHeight), hs.image.imageFromName("NSApplicationIcon"))
    overlay:setLevel(hs.drawing.windowLevels.floating)
    overlay:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    overlay:show()

    -- Update screenshot every 0.1 seconds
    timer = hs.timer.doEvery(0.1, function()
        if captureWin and captureWin:isVisible() then
            local img = captureWin:snapshot()  -- only original window
            overlay:setImage(img)
        end
    end)
end

hs.hotkey.bind({"ctrl","alt","cmd"}, "T", toggleOverlay)
