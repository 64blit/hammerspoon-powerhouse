-------------------------------------------------
-- Hammerspoon Powerhouse — Master Entrypoint
-- Modular macOS productivity & AI copilot kit.
-------------------------------------------------

-- Allow requiring custom modules from ~/.hammerspoon/local/
package.path = hs.configdir .. "/local/?.lua;" .. package.path

-- Enable AppleScript and CLI IPC execution
hs.allowAppleScript(true)
pcall(function() require("hs.ipc") end)

-- Load environment variables first
local env = require("env_loader")

local function safeLoad(moduleName)
    local ok, mod = pcall(require, moduleName)
    if not ok then
        print(string.format("[init] Failed to load %s: %s", moduleName, tostring(mod)))
        return nil
    end
    return mod
end

-- Load SpoonInstall (needed by spoons_setup)
if env.getBool("ENABLE_SPOONS", true) then
    if hs.loadSpoon("SpoonInstall") then
        safeLoad("spoons_setup")         -- ClipboardTool, Caffeine
    else
        print("[init] SpoonInstall not found in Spoons/; skipping spoons_setup")
    end
end

-------------------------------------------------
-- Core Modules (toggleable via ~/.hammerspoon/.env)
-------------------------------------------------
if env.getBool("ENABLE_WINDOW_OVERLAY", true) then
    safeLoad("window_overlay")           -- Picture-in-Picture overlay (⌃⌥⌘T)
end

if env.getBool("ENABLE_COMMAND_PALETTE", true) then
    safeLoad("command_palette")          -- Unified Command Palette (⌥Z)
end

-------------------------------------------------
-- AI Chatbox (OpenRouter / Multi-Model LLM)
-------------------------------------------------
if env.getBool("ENABLE_AI_CHATBOX", true) then
    local ai_chatbox = safeLoad("ai_chatbox")
    if ai_chatbox then
        hs.hotkey.bind({"ctrl", "alt", "cmd"}, "A", ai_chatbox.toggleChatbox)
    end
end

-------------------------------------------------
-- Nightshade (Optional Scheduled Redshift Overlay)
-------------------------------------------------
if env.getBool("ENABLE_NIGHTSHADE", false) then
    local nightshade = safeLoad("nightshade")
    if nightshade then
        nightshade.start()
    end
end

-------------------------------------------------
-- Unified Menubar Hub
-- Consolidates enabled tools under one 🧰 icon.
-------------------------------------------------
if env.getBool("ENABLE_MENUBAR_HUB", true) then
    safeLoad("menubar_hub")
end

-------------------------------------------------
-- Optional User Extensions (local_init.lua)
-------------------------------------------------
local localInitPath = hs.configdir .. "/local_init.lua"
if hs.fs.attributes(localInitPath) then
    local ok, err = pcall(dofile, localInitPath)
    if not ok then
        print("[init] Error in local_init.lua: " .. tostring(err))
        hs.alert.show("local_init.lua error — see Console", 4)
    end
end
