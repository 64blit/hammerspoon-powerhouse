-- Hammerspoon Configuration
-- Each feature is split into its own module file for maintainability.

-- Load environment variables & secrets first
require("env_loader")

-- Load SpoonInstall (needed by spoons_setup)
hs.loadSpoon("SpoonInstall")

-------------------------------------------------
-- Module Loading
-------------------------------------------------
require("spoons_setup")         -- ClipboardTool, Caffeine
require("window_overlay")       -- Picture-in-Picture window overlay (Ctrl+Alt+Cmd+T)
require("claude_approve")       -- Claude Always Approve toggle (optional)

-------------------------------------------------
-- 64blit Code Intelligence
-------------------------------------------------
local code_intel = require("code_intel")
-- Global hotkey for Semantic Code Search Spotlight HUD
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "K", function() code_intel.toggleSearchHUD() end)
-- Global hotkey to search selected text
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "S", function() code_intel.searchSelection() end)
-- Global hotkey to prompt for folder ingestion
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "I", function() code_intel.promptIngestFolder() end)

-------------------------------------------------
-- AI Chatbox (OpenRouter / LLM)
-------------------------------------------------
local ai_chatbox = require("ai_chatbox")
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "A", ai_chatbox.toggleChatbox)

-------------------------------------------------
-- Unified Menubar Hub
-- (loads code_intel, terminal_toggle, mouse_magnifier,
--  window_translator, text_to_speech, text_refiner, keystroke_visualizer)
-------------------------------------------------
require("menubar_hub")
