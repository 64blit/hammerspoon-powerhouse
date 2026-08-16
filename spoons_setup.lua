-------------------------------------------------
-- Spoon Plugins Setup
-------------------------------------------------

spoon.SpoonInstall:andUse("ClipboardTool", {
  start = true,
  config = {
    hist_size = 50,              -- how many clipboard entries to keep
    frequency = 0.8,             -- how often (seconds) to check for new clips
    show_in_menubar = true,      -- shows a little menu bar icon
    paste_on_select = false,     -- don't auto-paste when selecting
    deduplicate = true           -- remove duplicates
  },
  hotkeys = {
    toggle_clipboard = {{"cmd", "alt"}, "v"}
  }
})

-------------------------------------------------
-- Caffeine
-------------------------------------------------
spoon.SpoonInstall:andUse("Caffeine", {
  start = true,
  hotkeys = {
    toggle = {{"cmd", "alt", "ctrl"}, "C"}
  }
})

-- MicMute replaced by terminal_toggle.lua
-- spoon.SpoonInstall:andUse("MicMute", {
--   hotkeys = {
--     toggle = {{"cmd", "alt"}, "M"}
--   }
-- })
