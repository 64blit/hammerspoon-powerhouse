-- Install Tools: one-click brew install of CLI dependencies the hammerspoon
-- modules shell out to. Sequential installs (brew locks), progress via alerts +
-- console.

local M = {}

local BREW = "/opt/homebrew/bin/brew"
if not hs.fs.attributes(BREW) then
    BREW = "/usr/local/bin/brew"
end

-- Runtime dependencies pulled in by the hammerspoon modules. Each entry is a
-- brew formula plus the on-disk paths we accept as "already installed" — that
-- way binaries installed outside brew (e.g. uv via curl into ~/.local/bin)
-- aren't reinstalled.
local HOME = os.getenv("HOME")
local DEPS = {
    {
        formula = "ffmpeg",
        bins = { "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg" },
        desc = "Video/audio encoder (mouse_magnifier, TTS)",
    },
    {
        formula = "gifski",
        bins = { "/opt/homebrew/bin/gifski", "/usr/local/bin/gifski" },
        desc = "High-quality GIF encoder (mouse_magnifier)",
    },
    {
        formula = "uv",
        bins = {
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            HOME .. "/.local/bin/uv",
        },
        desc = "Fast Python package runner (terminal_toggle QR code)",
    },
}

-- Post-install hooks: run after brew installs finish. Each entry is a
-- function(callback(ok)) — performs a side install (clone+build, npm, etc.).
local function buildTranslateCli(cb)
    local binPath = hs.configdir .. "/translator_helper/bin/translate"
    if hs.fs.attributes(binPath) then cb(true); return end
    print("[install_tools] building translate-cli (Apple Translation)…")
    local script = string.format([[
set -e
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
/usr/bin/git clone --depth 1 https://github.com/scriptingosx/translate-cli >/tmp/translate_cli_build.log 2>&1
cd translate-cli
/usr/bin/swift build -c release >>/tmp/translate_cli_build.log 2>&1
mkdir -p %q
cp .build/release/translate %q
]], hs.configdir .. "/translator_helper/bin", binPath)
    local t = hs.task.new("/bin/bash", function(rc, out, err)
        if rc == 0 and hs.fs.attributes(binPath) then
            print("[install_tools] translate-cli installed at " .. binPath)
            cb(true)
        else
            print(string.format("[install_tools] translate-cli build failed rc=%s err=%q (see /tmp/translate_cli_build.log)",
                tostring(rc), err or ""))
            cb(false)
        end
    end, {"-lc", script})
    t:start()
end

local function installTranslateServerDeps(cb)
    local serverDir = hs.configdir .. "/translator_helper/translate_server"
    local nodeModules = serverDir .. "/node_modules"
    if hs.fs.attributes(nodeModules) then cb(true); return end
    print("[install_tools] installing translate-server npm dependencies…")
    local t = hs.task.new("/bin/bash", function(rc, out, err)
        if rc == 0 then
            print("[install_tools] translate-server npm dependencies installed")
            cb(true)
        else
            print(string.format("[install_tools] npm install failed rc=%s err=%q", tostring(rc), err or ""))
            cb(false)
        end
    end, {"-lc", "cd " .. string.format("%q", serverDir) .. " && npm install"})
    t:start()
end

local POST_HOOKS = {
    { name = "translate-cli (Apple Translation)", fn = buildTranslateCli },
    { name = "translate-server (Google Translate)", fn = installTranslateServerDeps },
}

local function depOnDisk(dep)
    for _, p in ipairs(dep.bins or {}) do
        if hs.fs.attributes(p) then return true end
    end
    return false
end

local installInProgress = false

local function brewExists()
    return hs.fs.attributes(BREW) ~= nil
end

-- Launch Terminal.app with the official Homebrew installer one-liner.
-- The installer needs sudo + interactive prompts, so we hand off to Terminal
-- rather than trying to drive it from hs.task.
local function installBrewInteractive(onAccept)
    local choice = hs.dialog.blockAlert(
        "Homebrew not found",
        "Homebrew is required to install ffmpeg, gifski, etc.\n\n" ..
        "Click Install to open Terminal and run the official Homebrew installer. " ..
        "You'll be prompted for your password.\n\n" ..
        "After Homebrew finishes installing, click \"Install Tools\" again to " ..
        "install the dependencies.",
        "Install", "Cancel"
    )
    if choice ~= "Install" then return end

    local script = [[
tell application "Terminal"
    activate
    do script "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
end tell
]]
    local ok, _, err = hs.osascript.applescript(script)
    if ok then
        hs.alert.show("Follow prompts in Terminal. Re-run Install Tools after.", 5)
        if onAccept then onAccept() end
    else
        print("[install_tools] failed to launch Terminal: " .. hs.inspect(err))
        hs.alert.show("Could not open Terminal — see console", 4)
    end
end

local function getInstalled(cb)
    hs.task.new(BREW, function(exitCode, out, err)
        local set = {}
        if exitCode == 0 then
            for line in (out or ""):gmatch("[^\r\n]+") do
                set[line] = true
            end
        else
            print(string.format("[install_tools] brew list failed exit=%s err=%q",
                tostring(exitCode), err or ""))
        end
        cb(set)
    end, { "list", "--formula" }):start()
end

local function brewInstall(formula, cb)
    print("[install_tools] brew install " .. formula)
    hs.task.new(BREW, function(exitCode, out, err)
        if exitCode == 0 then
            print("[install_tools] installed " .. formula)
            cb(true)
        else
            print(string.format("[install_tools] failed %s exit=%s out=%q err=%q",
                formula, tostring(exitCode), out or "", err or ""))
            cb(false)
        end
    end, { "install", formula }):start()
end

local function installSequential(missing, idx, results, finalCb)
    if idx > #missing then
        finalCb(results)
        return
    end
    local dep = missing[idx]
    hs.alert.show(string.format("Installing %s (%d/%d)…", dep.formula, idx, #missing), 2)
    brewInstall(dep.formula, function(ok)
        results[dep.formula] = ok
        installSequential(missing, idx + 1, results, finalCb)
    end)
end

function M.installAll()
    if installInProgress then
        hs.alert.show("Install already in progress", 2)
        return
    end
    if not brewExists() then
        installInProgress = false
        installBrewInteractive()
        return
    end
    installInProgress = true
    hs.alert.show("Checking dependencies…", 1)
    getInstalled(function(installed)
        local missing = {}
        for _, dep in ipairs(DEPS) do
            if not depOnDisk(dep) and not installed[dep.formula] then
                table.insert(missing, dep)
            end
        end
        if #missing == 0 then
            hs.alert.show("✓ All tools already installed", 2)
            installInProgress = false
            return
        end
        local names = {}
        for _, d in ipairs(missing) do table.insert(names, d.formula) end
        hs.alert.show("Installing: " .. table.concat(names, ", ") .. " (may take a minute)", 4)
        installSequential(missing, 1, {}, function(results)
            local okCount, failed = 0, {}
            for _, d in ipairs(missing) do
                if results[d.formula] then okCount = okCount + 1
                else table.insert(failed, d.formula) end
            end
            if #failed == 0 then
                hs.alert.show("✓ Installed " .. okCount .. " tool(s)", 3)
            else
                hs.alert.show("Failed: " .. table.concat(failed, ", ") .. " (see console)", 5)
            end
            -- Run post-install hooks (npm install, etc.) regardless of brew
            -- result so users who already had node still get translate-server
            -- deps.
            local function runHook(i)
                if i > #POST_HOOKS then
                    installInProgress = false
                    return
                end
                local hook = POST_HOOKS[i]
                hs.alert.show("Post-install: " .. hook.name .. "…", 2)
                hook.fn(function(ok)
                    if not ok then
                        hs.alert.show("Post-install failed: " .. hook.name, 4)
                    end
                    runHook(i + 1)
                end)
            end
            runHook(1)
        end)
    end)
end

M.deps = DEPS
M.brewPath = BREW

return M
