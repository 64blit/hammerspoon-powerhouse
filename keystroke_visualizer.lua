-------------------------------------------------
-- Keystroke Visualizer
-------------------------------------------------

local keyVisCanvas = nil
local keyVisTap = nil
local keyVisTimer = nil

local function hideKeyVis()
    if keyVisCanvas then
        keyVisCanvas:hide()
    end
end

local function showKeystroke(text)
    if not keyVisCanvas then
        keyVisCanvas = hs.canvas.new({x=0, y=0, w=0, h=0})
        keyVisCanvas:level(hs.drawing.windowLevels.overlay)
        keyVisCanvas:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
        
        -- Background
        keyVisCanvas[1] = {
            type = "rectangle",
            action = "fill",
            fillColor = {red=0.1, green=0.1, blue=0.1, alpha=0.9},
            roundedRectRadii = {xRadius=10, yRadius=10},
            strokeColor = {white=1, alpha=0.8},
            strokeWidth = 2
        }
        
        -- Text
        keyVisCanvas[2] = {
            type = "text",
            text = "",
            textSize = 40,
            textColor = {white=1},
            textAlignment = "center",
        }
    end

    -- Update text
    keyVisCanvas[2].text = text
    
    -- Measure text size for dynamic background
    local styledText = hs.styledtext.new(text, {font={size=40}, color={white=1}})
    local size = hs.drawing.getTextDrawingSize(styledText)
    
    local padX = 40
    local padY = 20
    local w = math.max(100, size.w + padX)
    local h = size.h + padY
    
    -- Position on the screen where the mouse is
    local screen = hs.mouse.getCurrentScreen()
    local screenFrame = screen:fullFrame()
    local x = screenFrame.x + screenFrame.w - w - 40
    local y = screenFrame.y + screenFrame.h - h - 40
    
    keyVisCanvas:frame({x=x, y=y, w=w, h=h})
    keyVisCanvas:show()
    
    -- Auto-hide after 2 seconds
    if keyVisTimer then keyVisTimer:stop() end
    keyVisTimer = hs.timer.doAfter(2.0, hideKeyVis)
end

local keyMap = {
    ["return"] = "⏎", ["delete"] = "⌫", ["forwarddelete"] = "⌦",
    ["escape"] = "⎋", ["space"] = "␣", ["tab"] = "⇥",
    ["up"] = "↑", ["down"] = "↓", ["left"] = "←", ["right"] = "→",
    ["pageup"] = "PgUp", ["pagedown"] = "PgDn", ["home"] = "Home", ["end"] = "End",
    ["f1"]="F1", ["f2"]="F2", ["f3"]="F3", ["f4"]="F4", ["f5"]="F5",
    ["f6"]="F6", ["f7"]="F7", ["f8"]="F8", ["f9"]="F9", ["f10"]="F10",
    ["f11"]="F11", ["f12"]="F12"
}

local function modString(flags)
    local mods = ""
    if flags.ctrl then mods = mods .. "⌃ " end
    if flags.alt then mods = mods .. "⌥ " end
    if flags.shift then mods = mods .. "⇧ " end
    if flags.cmd then mods = mods .. "⌘ " end
    if flags.fn then mods = mods .. "fn " end
    return mods
end

local function onKeyDown(event)
    local flags = event:getFlags()
    local keyCode = event:getKeyCode()
    local keyName = hs.keycodes.map[keyCode]

    local charDisplay = ""
    if keyMap[keyName] then
        charDisplay = keyMap[keyName]
    elseif keyName then
        if #keyName == 1 then
            charDisplay = string.upper(keyName)
        else
            charDisplay = keyName
        end
    end

    showKeystroke(modString(flags) .. charDisplay)
    return false
end

-- Modifier-only presses (Ctrl, Cmd, Alt, Shift, fn) come through as
-- flagsChanged, not keyDown. Render the active modifier set; if no
-- modifiers remain pressed, hide immediately.
local function onFlagsChanged(event)
    local flags = event:getFlags()
    local mods = modString(flags)
    if mods == "" then
        hideKeyVis()
    else
        showKeystroke(mods)
    end
    return false
end

local keyVisMenu = hs.menubar.new()

local function refreshKeyVisIcon()
    if not keyVisMenu then return end
    if keyVisTap then
        keyVisMenu:setTitle("⌨️")
        keyVisMenu:setTooltip("Keystroke Display: ON")
    else
        keyVisMenu:setTitle("⌨")
        keyVisMenu:setTooltip("Keystroke Display: OFF")
    end
end

local function toggleKeystrokeVisualizer()
    if keyVisTap then
        keyVisTap:stop()
        keyVisTap = nil
        hideKeyVis()
        hs.alert.show("Keystroke Display OFF")
    else
        keyVisTap = hs.eventtap.new({
            hs.eventtap.event.types.keyDown,
            hs.eventtap.event.types.flagsChanged,
        }, function(event)
            local t = event:getType()
            if t == hs.eventtap.event.types.flagsChanged then
                return onFlagsChanged(event)
            else
                return onKeyDown(event)
            end
        end)
        keyVisTap:start()
        hs.alert.show("Keystroke Display ON")
    end
    refreshKeyVisIcon()
end

local function buildKeyVisMenu()
    local on = keyVisTap ~= nil
    return {
        { title = on and "Disable Keystroke Display" or "Enable Keystroke Display",
          fn = toggleKeystrokeVisualizer },
        { title = "-" },
        { title = "Hotkey", disabled = true },
        { title = "  Toggle  ⌃⌥⌘K", disabled = true },
    }
end

if keyVisMenu then
    keyVisMenu:setMenu(buildKeyVisMenu)
    refreshKeyVisIcon()
end

hs.hotkey.bind({"ctrl", "alt", "cmd"}, "K", toggleKeystrokeVisualizer)

return {
    title = "Keystroke Display",
    icon = function() return keyVisTap and "⌨️" or "⌨" end,
    buildMenu = buildKeyVisMenu,
    menubar = keyVisMenu,
}
