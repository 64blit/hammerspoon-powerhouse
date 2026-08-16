-------------------------------------------------
-- Text-to-Speech with LLM Summarization
-- Summarizes selected text via x.ai, then speaks via OpenRouter (openai/gpt-audio-mini)
-------------------------------------------------

local menuIcon = hs.menubar.new()

local currentSound = nil
local openrouterTask = nil

local playVolumes = {.25, .5, 0.75, 1}
local currentVolIndex = 4 -- Default to 100%

-- System prompt: produce a spoken-word summary
local PROMPT_SUMMARIZE = "You are a professional text-to-speech narrator. Read the exact text provided aloud clearly and naturally. Do not add, omit, summarize, or modify any words. Do not acknowledge the prompt."

local function isBusy()
    return (openrouterTask and openrouterTask:isRunning()) or (currentSound and currentSound:isPlaying())
end

local updateIcon -- forward declaration

local function setVolume(idx)
    currentVolIndex = idx
    if currentSound and currentSound:isPlaying() then
        currentSound:pause()
        currentSound:volume(playVolumes[currentVolIndex])
        currentSound:resume()
    end
    updateIcon()
end

-- update menubar icon
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
    if openrouterTask and openrouterTask:isRunning() then
        openrouterTask:terminate()
    end
    if currentSound and currentSound:isPlaying() then
        currentSound:stop()
    end
    updateIcon()
end

local function summarizeAndSpeak(text)
    hs.alert.show("Generating audio...")
    stopSpeaking()

    local scriptPath = os.getenv("HOME") .. "/.hammerspoon/openrouter_tts.py"

    openrouterTask = hs.task.new("/usr/bin/python3", function(exitCode, stdOut, stdErr)
        if exitCode == 0 and stdOut:match("SUCCESS") then
            local audioPath = "/tmp/hammerspoon_openrouter_tts.mp3"
            currentSound = hs.sound.getByFile(audioPath)
            if currentSound then
                currentSound:volume(playVolumes[currentVolIndex])
                currentSound:setCallback(function(state)
                    updateIcon()
                end)
                currentSound:play()
            else
                hs.alert.show("TTS Error: Could not load audio file")
            end
            updateIcon()
        else
            hs.alert.show("TTS Error")
            print("TTS Error Exit: " .. tostring(exitCode))
            print("TTS Error Out: " .. tostring(stdOut))
            print("TTS Error Err: " .. tostring(stdErr))
            updateIcon()
        end
    end, { scriptPath, PROMPT_SUMMARIZE })

    openrouterTask:setInput(text)
    openrouterTask:start()
    updateIcon()
end

-- Copy selected text, then summarize and speak
local function speakSelection()
    hs.eventtap.keyStroke({"cmd"}, "c") -- copy selection
    hs.timer.doAfter(0.2, function()
        local text = hs.pasteboard.getContents()
        if text and text ~= "" then
            summarizeAndSpeak(text)
        else
            hs.alert.show("No text selected")
        end
    end)
end

local function speakClipboard()
    local text = hs.pasteboard.getContents()
    if text and text ~= "" then
        summarizeAndSpeak(text)
    else
        hs.alert.show("Clipboard is empty")
    end
end

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

    return {
        { title = busy and "Stop Speaking" or "Speak Selection",
          fn = busy and stopSpeaking or speakSelection },
        { title = "Speak Clipboard", fn = speakClipboard, disabled = busy },
        { title = "-" },
        { title = "Volume", menu = volumeItems },
        { title = "-" },
        { title = "Hotkey", disabled = true },
        { title = "  Toggle Speech  ⌃⌥S", disabled = true },
    }
end

menuIcon:setMenu(buildTTSMenu)
updateIcon()

-- hotkey toggle (ctrl+alt+S)
hs.hotkey.bind({"ctrl", "alt"}, "S", function()
    if isBusy() then
        stopSpeaking()
    else
        speakSelection()
    end
    updateIcon()
end)

return {
    title = "Read Aloud",
    icon = function() return isBusy() and "🔊" or "🔈" end,
    buildMenu = buildTTSMenu,
    menubar = menuIcon,
}
