-------------------------------------------------
-- Environment & Secrets Loader
-- Loads configuration and API keys from:
--   1. ~/.hammerspoon/.env   (machine-local overrides, gitignored)
--   2. ~/.env                (global user secrets)
--   3. System environment variables (os.getenv)
-------------------------------------------------

local M = {}
local _envCache = {}
local _loaded = false

-- Expand a leading "~/" to $HOME/
function M.expandPath(p)
    if type(p) ~= "string" then return p end
    local home = os.getenv("HOME") or ""
    if p == "~" then return home end
    if p:sub(1, 2) == "~/" then
        return home .. p:sub(2)
    end
    return p
end

-- Parse a single .env file into the cache (does not overwrite existing keys)
local function parseEnvFile(filePath)
    local f = io.open(filePath, "r")
    if not f then return false end

    for line in f:lines() do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^#") then
            -- Strip optional leading "export "
            local cleaned = trimmed:gsub("^export%s+", "")
            local key, val = cleaned:match("^([%w_]+)%s*=%s*(.*)$")
            if key and val then
                -- Strip surrounding single or double quotes
                val = val:match('^"(.*)"$') or val:match("^'(.*)'$") or val
                if _envCache[key] == nil then
                    _envCache[key] = val
                end
            end
        end
    end
    f:close()
    return true
end

function M.load()
    if _loaded then return _envCache end
    _envCache = {}

    -- 1. Try ~/.hammerspoon/.env
    local localEnv = hs.configdir .. "/.env"
    parseEnvFile(localEnv)

    -- 2. Try ~/.env (user home root)
    local home = os.getenv("HOME") or ""
    if home ~= "" then
        local homeEnv = home .. "/.env"
        parseEnvFile(homeEnv)
    end

    _loaded = true
    return _envCache
end

-- Retrieve an environment variable with an optional fallback
function M.get(key, fallback)
    if not _loaded then M.load() end
    if _envCache[key] ~= nil and _envCache[key] ~= "" then
        return _envCache[key]
    end
    local sysVal = os.getenv(key)
    if sysVal and sysVal ~= "" then
        return sysVal
    end
    return fallback
end

-- Retrieve a path environment variable with "~" expansion
function M.getPath(key, fallback)
    local val = M.get(key, fallback)
    if val == nil then return nil end
    return M.expandPath(val)
end

-- Retrieve a boolean environment variable (1/true/yes/on vs 0/false/no/off)
function M.getBool(key, default)
    local raw = M.get(key)
    if raw == nil then return default == true end
    local lower = tostring(raw):lower()
    if lower == "1" or lower == "true" or lower == "yes" or lower == "on" then
        return true
    elseif lower == "0" or lower == "false" or lower == "no" or lower == "off" then
        return false
    end
    return default == true
end

-- Check if a key exists and is non-empty
function M.has(key)
    local val = M.get(key)
    return val ~= nil and val ~= ""
end

-- Force reload .env files
function M.reload()
    _loaded = false
    return M.load()
end

-- Return all loaded key-value pairs
function M.getAll()
    if not _loaded then M.load() end
    return _envCache
end

-- Auto-load on require
M.load()

return M
