-------------------------------------------------
-- Menubar Hub
-- Loads each enabled custom tool, hides its individual menubar icon, and
-- composes one unified dropdown with a submenu per tool.
-------------------------------------------------

local env = require("env_loader")
local hub = hs.menubar.new()
local installTools = require("install_tools")

-- Tool manifest: { moduleName, envFlag }
-- Each module returns:
--   { title, icon (fn -> string), buildMenu (fn -> table), menubar (hs.menubar) }
local TOOL_SPECS = {
    { name = "code_intel",           flag = "ENABLE_CODE_INTEL" },
    { name = "terminal_toggle",      flag = "ENABLE_TERMINAL_SERVER" },
    { name = "mouse_magnifier",      flag = "ENABLE_MAGNIFIER" },
    { name = "window_translator",    flag = "ENABLE_TRANSLATOR" },
    { name = "text_to_speech",       flag = "ENABLE_TTS" },
    { name = "text_refiner",         flag = "ENABLE_TEXT_REFINER" },
    { name = "keystroke_visualizer", flag = "ENABLE_KEYSTROKE_VIS" },
}

local tools = {}

local function hideIndividualIcon(t)
    if t and t.menubar and t.menubar.removeFromMenuBar then
        t.menubar:removeFromMenuBar()
    end
end

for _, spec in ipairs(TOOL_SPECS) do
    if env.getBool(spec.flag, true) then
        local ok, mod = pcall(require, spec.name)
        if ok and mod then
            table.insert(tools, mod)
            hideIndividualIcon(mod)
        elseif not ok then
            print(string.format("[menubar_hub] Failed to load %s: %s", spec.name, tostring(mod)))
        end
    end
end

local function buildHubMenu()
    local items = {}
    if env.getBool("ENABLE_COMMAND_PALETTE", true) then
        table.insert(items, {
            title = "⚡ Command Palette  ⌥Z",
            fn = function()
                local ok, cp = pcall(require, "command_palette")
                if ok and cp and cp.toggle then cp.toggle() end
            end
        })
        table.insert(items, { title = "-" })
    end

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
    hub:setTooltip("Hammerspoon Powerhouse")
end

-- Allow local_init.lua or private modules to register additional menubar submenus
local function registerTool(tool)
    if type(tool) ~= "table" then return end
    table.insert(tools, tool)
    hideIndividualIcon(tool)
    refreshHubIcon()
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
    registerTool = registerTool,
}
