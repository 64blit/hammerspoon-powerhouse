-------------------------------------------------
-- Text-to-Speech (Read Aloud) with Optional LLM Cliffnotes Summarization
--
-- Supported TTS engines (configurable via TTS_ENGINE in ~/.hammerspoon/.env
-- or live via the Read Aloud menubar):
--   • auto       — Local Kokoro (if KOKORO_TTS_DIR configured) → OpenRouter (if key set) → macOS say
--   • kokoro     — Offline local Kokoro-82M via kokoro_speak.py (falls back to macOS say)
--   • openrouter — Cloud TTS via openrouter_tts.py (falls back to macOS say)
--   • say        — Native macOS `say` (instant, zero setup, fully offline)
--
-- Hotkeys:
--   ⌃⌥S   = Read selection verbatim (or stop speaking)
--   ⌃⌥⇧S  = Summarize selection into spoken cliffnotes (OpenRouter) & speak
-------------------------------------------------

local env = require("env_loader")
local menuIcon = hs.menubar.new()

local KOKORO_DIR = env.getPath("KOKORO_TTS_DIR", "")
local KOKORO_VOICE = env.get("KOKORO_TTS_VOICE", "bm_george")
local KOKORO_MODEL_DIR = env.getPath(
    "KOKORO_TTS_MODEL_DIR",
    (KOKORO_DIR ~= "" and (KOKORO_DIR .. "/weights/Kokoro-82M-bf16") or "")
)
local KOKORO_PY = env.getPath(
    "KOKORO_TTS_PYTHON",
    (KOKORO_DIR ~= "" and (KOKORO_DIR .. "/.venv/bin/python") or "")
)
local KOKORO_CONFLICT_PATTERN = env.get("KOKORO_CONFLICT_PATTERN", "")
local KOKORO_SCRIPT = hs.configdir .. "/kokoro_speak.py"
local KOKORO_VOLUME_FILE = "/tmp/hammerspoon_kokoro_volume" -- kokoro_speak.py reads it before each chunk
local OPENROUTER_SCRIPT = hs.configdir .. "/openrouter_tts.py"
local SAY_TEXT_FILE = "/tmp/hammerspoon_say_text.txt"

local VALID_ENGINES = { auto = true, kokoro = true, openrouter = true, say = true }
local selectedEngine = (env.get("TTS_ENGINE", "auto") or "auto"):lower()
if not VALID_ENGINES[selectedEngine] then selectedEngine = "auto" end

local currentSound = nil
local openrouterTask = nil -- OpenRouter TTS or the summary call
local kokoroTask = nil
local sayTask = nil        -- local fallback voice: macOS `say` (no network, no model)
local requestId = 0        -- bumped on every new request / stop; stale task callbacks are ignored

local playVolumes = { 0.25, 0.5, 0.75, 1.0 }
local currentVolIndex = 4  -- Default to 100%

local function running(t) return t ~= nil and t:isRunning() end

local function isBusy()
    return running(openrouterTask) or running(kokoroTask) or running(sayTask)
        or (currentSound and currentSound:isPlaying())
end

local updateIcon -- forward declaration

local function writeKokoroVolume()
    local f = io.open(KOKORO_VOLUME_FILE, "w")
    if f then
        f:write(string.format("%.2f", playVolumes[currentVolIndex]))
        f:close()
    end
end

local function setVolume(idx)
    currentVolIndex = idx
    writeKokoroVolume() -- Kokoro: applies from the next sentence chunk
    if currentSound and currentSound:isPlaying() then
        currentSound:pause()
        currentSound:volume(playVolumes[currentVolIndex])
        currentSound:resume()
    end
    updateIcon()
end

-- Update menubar icon
function updateIcon()
    if isBusy() then
        menuIcon:setTitle(string.format("🔊 %d%%", playVolumes[currentVolIndex] * 100))
        menuIcon:setTooltip("Read Aloud: speaking")
    else
        menuIcon:setTitle("🔈")
        menuIcon:setTooltip("Read Aloud: idle")
    end
end

local function stopSpeaking()
    requestId = requestId + 1
    if running(openrouterTask) then openrouterTask:terminate() end
    if running(sayTask) then sayTask:terminate() end
    if running(kokoroTask) then
        kokoroTask:terminate() -- SIGTERM: kokoro_speak.py kills its afplay too
        -- Backstop in case the python process could not handle the signal.
        hs.task.new("/usr/bin/pkill", nil, { "-f", "afplay.*hs-kokoro-tts-" }):start()
    end
    if currentSound and currentSound:isPlaying() then
        currentSound:stop()
    end
    updateIcon()
end

local function kokoroMissing()
    if KOKORO_DIR == "" or KOKORO_PY == "" or KOKORO_MODEL_DIR == "" then
        return "KOKORO_TTS_DIR not configured"
    end
    local required = {
        KOKORO_PY,
        KOKORO_SCRIPT,
        KOKORO_MODEL_DIR .. "/kokoro-v1_0.safetensors",
        KOKORO_MODEL_DIR .. "/voices/" .. KOKORO_VOICE .. ".safetensors",
    }
    for _, p in ipairs(required) do
        if not hs.fs.attributes(p) then return p end
    end
    return nil
end

-- Optional memory-pressure & concurrent batch-job diagnostic (logged only).
-- Set /tmp/hammerspoon_kokoro_force to silence the note.
local function kokoroPressureNote()
    if hs.fs.attributes("/tmp/hammerspoon_kokoro_force") then return nil end
    if KOKORO_CONFLICT_PATTERN ~= "" then
        local cmd = string.format("/usr/bin/pgrep -f %q 2>/dev/null | head -1", KOKORO_CONFLICT_PATTERN)
        local p = io.popen(cmd)
        if p then
            local out = p:read("*a") or ""
            p:close()
            if out:match("%d+") then return "concurrent TTS batch job detected" end
        end
    end
    local s = io.popen("/usr/sbin/sysctl -n vm.swapusage 2>/dev/null")
    if s then
        local line = s:read("*a") or ""
        s:close()
        local free = line:match("free = ([%d%.]+)M")
        if free and tonumber(free) < 3000 then
            return string.format("memory tight (swap free %.0f MB)", tonumber(free))
        end
    end
    return nil
end

local function firstLine(s)
    return ((s or ""):match("^[^\n]*") or ""):sub(1, 120)
end

-- Native macOS `say` (zero network, zero model dependencies).
local function speakLocal(text, id, note)
    local f = io.open(SAY_TEXT_FILE, "w")
    if not f then
        hs.alert.show("TTS Error: cannot write " .. SAY_TEXT_FILE)
        return
    end
    f:write(text)
    f:close()
    sayTask = hs.task.new("/usr/bin/say", function(exitCode, stdOut, stdErr)
        if id ~= requestId then return end
        if exitCode ~= 0 then
            hs.alert.show("TTS Error (say): " .. firstLine(stdErr))
            print("TTS say Exit: " .. tostring(exitCode) .. " Err: " .. tostring(stdErr))
        end
        updateIcon()
    end, { "-f", SAY_TEXT_FILE })
    sayTask:start()
    hs.alert.show("🔊 macOS say" .. (note and (" — " .. note) or ""), 2)
    updateIcon()
end

-- OpenRouter cloud TTS (requires OPENROUTER_API_KEY).
local function speakOpenRouter(text, id, label)
    if not env.has("OPENROUTER_API_KEY") then
        hs.alert.show("OPENROUTER_API_KEY missing → macOS say", 2)
        speakLocal(text, id, "fallback")
        return
    end

    hs.alert.show("Generating audio (OpenRouter)...")
    openrouterTask = hs.task.new("/usr/bin/python3", function(exitCode, stdOut, stdErr)
        if id ~= requestId then return end
        if exitCode == 0 and (stdOut or ""):match("SUCCESS") then
            local audioPath = "/tmp/hammerspoon_openrouter_tts.mp3"
            currentSound = hs.sound.getByFile(audioPath)
            if currentSound then
                currentSound:volume(playVolumes[currentVolIndex])
                currentSound:setCallback(function()
                    updateIcon()
                end)
                currentSound:play()
                hs.alert.show("🔊 OpenRouter TTS" .. (label and (" — " .. label) or ""), 1.5)
            else
                hs.alert.show("TTS Error: could not load audio → macOS say", 2)
                speakLocal(text, id, "fallback")
            end
            updateIcon()
        else
            print("TTS OpenRouter Exit: " .. tostring(exitCode) .. " Err: " .. tostring(stdErr))
            hs.alert.show("OpenRouter TTS failed → macOS say", 2)
            speakLocal(text, id, "fallback")
        end
    end, { OPENROUTER_SCRIPT })

    openrouterTask:setInput(text)
    openrouterTask:start()
    openrouterTask:closeInput()
    updateIcon()
end

-- Local Kokoro TTS; falls back to macOS `say` if missing or fails before playback.
local function speakKokoroOrFallback(text, id, label)
    local missing = kokoroMissing()
    if missing then
        print("TTS: Kokoro unavailable: " .. missing)
        hs.alert.show("Kokoro unavailable → macOS say", 2)
        speakLocal(text, id, "fallback")
        return
    end

    local pressure = kokoroPressureNote()
    if pressure then
        print("TTS: running Kokoro (" .. pressure .. ")")
    end

    hs.alert.show("Generating audio (Kokoro)...")
    writeKokoroVolume()
    local started = false

    kokoroTask = hs.task.new(KOKORO_PY, function(exitCode, stdOut, stdErr)
        if id ~= requestId then return end -- stopped or replaced
        if exitCode == 0 then
            updateIcon()
            return
        end
        print("TTS Kokoro Exit: " .. tostring(exitCode))
        print("TTS Kokoro Err: " .. tostring(stdErr))
        if started then
            hs.alert.show("Kokoro stopped mid-way: " .. firstLine(stdErr))
            updateIcon()
        else
            hs.alert.show("Kokoro failed → macOS say", 2)
            speakLocal(text, id, "fallback")
        end
    end, function(task, stdOut, stdErr)
        if not started and id == requestId and (stdOut or ""):match("PLAYING") then
            started = true
            hs.alert.show("🔊 Kokoro " .. KOKORO_VOICE .. (label and (" — " .. label) or ""), 1.5)
            updateIcon()
        end
        return true
    end, {
        KOKORO_SCRIPT,
        "--dir", KOKORO_DIR,
        "--voice", KOKORO_VOICE,
        "--volume", string.format("%.2f", playVolumes[currentVolIndex]),
    })

    kokoroTask:setInput(text)
    kokoroTask:start()
    kokoroTask:closeInput() -- kokoro_speak.py reads stdin until EOF
    updateIcon()
end

local function effectiveEngine()
    if selectedEngine ~= "auto" then return selectedEngine end
    if not kokoroMissing() then return "kokoro" end
    if env.has("OPENROUTER_API_KEY") then return "openrouter" end
    return "say"
end

local function dispatchSpeak(text, id, label)
    local eng = effectiveEngine()
    if eng == "kokoro" then
        speakKokoroOrFallback(text, id, label)
    elseif eng == "openrouter" then
        speakOpenRouter(text, id, label)
    else
        speakLocal(text, id, label)
    end
end

-- mode: "read" (verbatim) or "summarize" (cliffnotes)
local function speakText(text, mode)
    mode = mode or "read"
    stopSpeaking()
    local id = requestId

    if mode ~= "summarize" then
        dispatchSpeak(text, id, nil)
        return
    end

    hs.alert.show("Summarizing...")
    openrouterTask = hs.task.new("/usr/bin/python3", function(exitCode, stdOut, stdErr)
        if id ~= requestId then return end
        local summary = (stdOut or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if exitCode == 0 and summary ~= "" then
            dispatchSpeak(summary, id, "summary")
        else
            hs.alert.show("TTS Error: " .. firstLine(stdErr))
            print("TTS Summary Exit: " .. tostring(exitCode))
            print("TTS Summary Err: " .. tostring(stdErr))
            updateIcon()
        end
    end, { OPENROUTER_SCRIPT, "--summarize", "--summary-only" })

    openrouterTask:setInput(text)
    openrouterTask:start()
    openrouterTask:closeInput()
    updateIcon()
end

-- Copy selected text, then speak (mode: "read" | "summarize")
local function withSelection(mode)
    hs.eventtap.keyStroke({ "cmd" }, "c")
    hs.timer.doAfter(0.2, function()
        local text = hs.pasteboard.getContents()
        if text and text ~= "" then
            speakText(text, mode)
        else
            hs.alert.show("No text selected")
        end
    end)
end

local function speakSelection() withSelection("read") end
local function summarizeSelection() withSelection("summarize") end

local function withClipboard(mode)
    local text = hs.pasteboard.getContents()
    if text and text ~= "" then
        speakText(text, mode)
    else
        hs.alert.show("Clipboard is empty")
    end
end

local function speakClipboard() withClipboard("read") end
local function summarizeClipboard() withClipboard("summarize") end

local function buildTTSMenu()
    local busy = isBusy()
    local volumeItems = {}
    for i, v in ipairs(playVolumes) do
        table.insert(volumeItems, {
            title = string.format("%d%%", v * 100),
            checked = (i == currentVolIndex),
            fn = function() setVolume(i) end,
        })
    end

    local engineOptions = {
        { key = "auto",       label = "Auto (" .. effectiveEngine() .. ")" },
        { key = "kokoro",     label = "Kokoro (Local Offline)" .. (kokoroMissing() and " — not configured" or "") },
        { key = "openrouter", label = "OpenRouter TTS" .. (env.has("OPENROUTER_API_KEY") and "" or " — needs API key") },
        { key = "say",        label = "macOS say (Built-in)" },
    }
    local engineItems = {}
    for _, opt in ipairs(engineOptions) do
        table.insert(engineItems, {
            title = opt.label,
            checked = (selectedEngine == opt.key),
            fn = function()
                selectedEngine = opt.key
                hs.alert.show("TTS Engine: " .. opt.key, 1.5)
            end,
        })
    end

    local activeEng = effectiveEngine()
    local voiceLabel = activeEng == "kokoro" and ("Kokoro (" .. KOKORO_VOICE .. ")")
        or (activeEng == "openrouter" and "OpenRouter TTS")
        or "macOS say (local)"

    return {
        { title = busy and "Stop Speaking" or "Speak Selection",
          fn = busy and stopSpeaking or speakSelection },
        { title = "Summarize Selection (Cliffnotes)", fn = summarizeSelection, disabled = busy },
        { title = "-" },
        { title = "Speak Clipboard", fn = speakClipboard, disabled = busy },
        { title = "Summarize Clipboard", fn = summarizeClipboard, disabled = busy },
        { title = "-" },
        { title = "Engine: " .. voiceLabel, menu = engineItems },
        { title = "Volume", menu = volumeItems },
        { title = "-" },
        { title = "Hotkey", disabled = true },
        { title = "  Toggle Speech  ⌃⌥S", disabled = true },
        { title = "  Summarize Selection  ⌃⌥⇧S", disabled = true },
    }
end

menuIcon:setMenu(buildTTSMenu)
updateIcon()

-- Hotkey toggle (ctrl+alt+S)
hs.hotkey.bind({ "ctrl", "alt" }, "S", function()
    if isBusy() then
        stopSpeaking()
    else
        speakSelection()
    end
    updateIcon()
end)

-- Hotkey: summarize selection (ctrl+alt+shift+S)
hs.hotkey.bind({ "ctrl", "alt", "shift" }, "S", function()
    if isBusy() then
        stopSpeaking()
    else
        summarizeSelection()
    end
    updateIcon()
end)

return {
    title = "Read Aloud",
    icon = function() return isBusy() and "🔊" or "🔈" end,
    buildMenu = buildTTSMenu,
    menubar = menuIcon,
    speakSelection = speakSelection,
    summarizeSelection = summarizeSelection,
    speakClipboard = speakClipboard,
    summarizeClipboard = summarizeClipboard,
    stop = stopSpeaking,
    isBusy = isBusy,
}
