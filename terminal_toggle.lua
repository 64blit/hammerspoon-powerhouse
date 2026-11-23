-- Terminal Server Toggle Module (Self-Contained)
local HS_DIR = hs.configdir .. "/terminal_server"
local START_SCRIPT = HS_DIR .. "/start.sh"
local STOP_SCRIPT = HS_DIR .. "/stop.sh"

local terminalMenu = hs.menubar.new()
local _isTerminalRunning = false

-- Function to check if the server is actually running
local function checkTerminalStatus(callback)
    hs.task.new("/usr/bin/nc", function(exitCode)
        _isTerminalRunning = (exitCode == 0)
        
        if _isTerminalRunning then
            terminalMenu:setTitle("🐚")
            terminalMenu:setTooltip("Terminal Server: ONLINE")
        else
            terminalMenu:setTitle("🚫")
            terminalMenu:setTooltip("Terminal Server: OFFLINE")
        end
        if callback then callback(_isTerminalRunning) end
    end, { "-z", "-w", "1", "127.0.0.1", "7681" }):start()
end

-- Tool paths (hs.task runs with a minimal PATH, so detect across ARM/Intel Homebrew & ~/.local/bin)
local function detectBin(candidates)
    for _, p in ipairs(candidates) do
        if hs.fs.attributes(p) then return p end
    end
    return candidates[1]
end

local TAILSCALE_BIN = detectBin({
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    "/opt/homebrew/bin/tailscale",
    "/usr/local/bin/tailscale",
})
local PYTHON3_BIN = detectBin({ "/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3" })
local UV_BIN = detectBin({
    (os.getenv("HOME") or "") .. "/.local/bin/uv",
    "/opt/homebrew/bin/uv",
    "/usr/local/bin/uv",
})
local QR_PNG_PATH = "/tmp/tailscale_magic_qr.png"

-- Fetch the Tailscale magic URL, then call cb(url) on success or cb(nil) on failure.
local function fetchTailscaleURL(cb)
    local cmd = string.format(
        "%s status --json | %s -c \"import sys, json; data=json.load(sys.stdin); print('https://' + data['Self']['DNSName'].rstrip('.'))\"",
        TAILSCALE_BIN, PYTHON3_BIN
    )
    hs.task.new("/bin/bash", function(exitCode, out, err)
        local url = (out or ""):gsub("%s+", "")
        if exitCode == 0 and url ~= "" then
            cb(url)
        else
            print(string.format("[terminal_toggle] fetchTailscaleURL failed exit=%s out=%q err=%q",
                tostring(exitCode), out or "", err or ""))
            cb(nil)
        end
    end, { "-c", cmd }):start()
end

local function copyTailscaleURL()
    fetchTailscaleURL(function(url)
        if url then
            hs.pasteboard.setContents(url)
            hs.alert.show("Copied Magic Link: " .. url, 2)
        else
            hs.alert.show("Failed to get Tailscale URL", 2)
        end
    end)
end

-- QR popup state
local qrCanvas = nil
local qrEscapeTap = nil

local function dismissQR()
    if qrCanvas then qrCanvas:delete(); qrCanvas = nil end
    if qrEscapeTap then qrEscapeTap:stop(); qrEscapeTap = nil end
end

local function renderQRCanvas(url)
    local img = hs.image.imageFromPath(QR_PNG_PATH)
    if not img then
        hs.alert.show("QR image missing", 2)
        return
    end

    local screen = hs.screen.mainScreen():frame()
    local size = 360
    local pad = 16
    local textH = 28
    local frameW = size + pad * 2
    local frameH = size + pad * 2 + textH
    local rect = {
        x = screen.x + (screen.w - frameW) / 2,
        y = screen.y + (screen.h - frameH) / 2,
        w = frameW, h = frameH,
    }

    qrCanvas = hs.canvas.new(rect):level("overlay"):behavior({ "canJoinAllSpaces" })
    qrCanvas[#qrCanvas + 1] = {
        type = "rectangle", action = "fill",
        fillColor = { white = 1, alpha = 0.97 },
        roundedRectRadii = { xRadius = 12, yRadius = 12 },
    }
    qrCanvas[#qrCanvas + 1] = {
        type = "image", image = img,
        frame = { x = pad, y = pad, w = size, h = size },
    }
    qrCanvas[#qrCanvas + 1] = {
        type = "text",
        text = url,
        textColor = { white = 0.1 },
        textSize = 12,
        textAlignment = "center",
        frame = { x = pad, y = pad + size + 4, w = size, h = textH },
    }
    qrCanvas:mouseCallback(function() dismissQR() end)
    qrCanvas:clickActivating(false)
    qrCanvas:canvasMouseEvents(true, true, false, false)
    qrCanvas:show()

    qrEscapeTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
        if ev:getKeyCode() == hs.keycodes.map["escape"] then
            dismissQR()
            return true
        end
        return false
    end):start()
end

local function showTailscaleQR()
    fetchTailscaleURL(function(url)
        if not url then
            hs.alert.show("Failed to get Tailscale URL", 2)
            return
        end
        hs.pasteboard.setContents(url)
        local py = string.format([[
import qrcode
qr = qrcode.QRCode(box_size=10, border=2)
qr.add_data(%q)
qr.make(fit=True)
img = qr.make_image(fill_color='black', back_color='white')
img.save(%q)
]], url, QR_PNG_PATH)
        hs.task.new(UV_BIN, function(exitCode, out, err)
            if exitCode == 0 then
                renderQRCanvas(url)
            else
                print(string.format("[terminal_toggle] qr generation failed exit=%s out=%q err=%q",
                    tostring(exitCode), out or "", err or ""))
                hs.alert.show("Failed to render QR", 2)
            end
        end, { "run", "--with", "qrcode", "--with", "pillow", "python", "-c", py }):start()
    end)
end

-- Function to Toggle the Server
local function toggleTerminalServer()
    if _isTerminalRunning then
        hs.alert.show("Stopping Terminal...", 1)
        hs.task.new("/bin/bash", function()
            hs.alert.show("Terminal Server Stopped", 2)
            checkTerminalStatus()
        end, { STOP_SCRIPT }):start()
    else
        hs.alert.show("Starting Terminal & Tailscale...", 2)
        hs.task.new("/bin/bash", function(exitCode, out, err)
            if exitCode == 0 then
                hs.alert.show("Terminal Live!", 2)
                -- Wait a moment for Tailscale to settle, then copy URL automatically
                hs.timer.doAfter(2, copyTailscaleURL)
            else
                hs.alert.show("Start Failed", 2)
            end
            checkTerminalStatus()
        end, { START_SCRIPT }):start()
    end
end

local function buildTerminalMenu()
    return {
        { title = _isTerminalRunning and "Stop Terminal Server" or "Start Terminal Server",
          fn = toggleTerminalServer },
        { title = "Copy Magic Link (Tailscale)",
          fn = copyTailscaleURL, disabled = not _isTerminalRunning },
        { title = "Show Magic Link QR",
          fn = showTailscaleQR, disabled = not _isTerminalRunning },
        { title = "-" },
        { title = "Check Status", fn = function() checkTerminalStatus() end },
        { title = "-" },
        { title = "Hotkeys", disabled = true },
        { title = "  Toggle Server  ⌘⌥M", disabled = true },
        { title = "  Copy URL       ⌘⌥U", disabled = true },
        { title = "  Show QR        ⌘⌥Q", disabled = true },
    }
end

if terminalMenu then
    terminalMenu:setMenu(buildTerminalMenu)
    hs.timer.doEvery(30, checkTerminalStatus)
    checkTerminalStatus()
end

-- Hotkey: Toggle
hs.hotkey.bind({"cmd", "alt"}, "M", toggleTerminalServer)

-- Hotkey: Copy URL (Cmd+Alt+U)
hs.hotkey.bind({"cmd", "alt"}, "U", copyTailscaleURL)

-- Hotkey: Show QR (Cmd+Alt+Q)
hs.hotkey.bind({"cmd", "alt"}, "Q", showTailscaleQR)

return {
    title = "Terminal Server",
    icon = function() return _isTerminalRunning and "🐚" or "🚫" end,
    buildMenu = buildTerminalMenu,
    menubar = terminalMenu,
    toggle = toggleTerminalServer,
    copyUrl = copyTailscaleURL,
    showQR = showTailscaleQR,
}
