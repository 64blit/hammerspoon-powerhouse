-------------------------------------------------
-- Menubar Hub
-- Loads each custom tool, hides its individual menubar icon, and
-- composes one unified dropdown with a submenu per tool.
-------------------------------------------------

local hub = hs.menubar.new()
local installTools = require("install_tools")

-- Load tool modules in display order. Each module returns:
--   { title, icon (fn -> string), buildMenu (fn -> table), menubar (hs.menubar) }
local tools = {
    require("code_intel"),
    require("terminal_toggle"),
    require("mouse_magnifier"),
    require("window_translator"),
    require("text_to_speech"),
    require("text_refiner"),
    require("keystroke_visualizer"),
}

-- Hide each tool's individual menubar icon so only the hub shows.
for _, t in ipairs(tools) do
    if t and t.menubar and t.menubar.removeFromMenuBar then
        t.menubar:removeFromMenuBar()
    end
end

local function buildHubMenu()
    local items = {
        {
            title = "⚡ Command Palette  ⌥Z",
            fn = function()
                local cp = require("command_palette")
                cp.toggle()
            end
        },
        { title = "-" },
    }
    for i, t in ipairs(tools) do
        if t and t.buildMenu then
            if i > 1 then table.insert(items, { title = "-" }) end
            local prefix = t.icon and (t.icon() .. "  ") or ""
            table.insert(items, {
                title = prefix .. (t.title or "Tool"),
                menu = t.buildMenu(),
            })
        end
    end
    table.insert(items, { title = "-" })
    table.insert(items, {
        title = "📦 Install Tools (brew)",
        fn = function() installTools.installAll() end,
    })
    table.insert(items, {
        title = "Reload Hammerspoon",
        fn = function() hs.reload() end,
    })
    return items
end

-- Compose a status emoji that surfaces the most "active" tool.
local function refreshHubIcon()
    if not hub then return end
    local active = nil
    for _, t in ipairs(tools) do
        if t and t.icon then
            local ic = t.icon()
            -- Surface noisy/active states first
            if ic == "🔴" or ic == "🔊" then
                active = ic
                break
            end
        end
    end
    hub:setTitle(active or "🧰")
    hub:setTooltip("Custom Tools")
end

if hub then
    hub:setMenu(buildHubMenu)
    refreshHubIcon()
    -- Periodically refresh the icon so recording / speaking states show through.
    hs.timer.doEvery(2, refreshHubIcon)
end

return {
    hub = hub,
    tools = tools,
    refresh = refreshHubIcon,
}
