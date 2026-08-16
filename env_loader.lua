-------------------------------------------------
-- Environment & Secrets Loader
-- Loads configuration and API keys from:
--   1. ~/.hammerspoon/.env
--   2. ~/.env
--   3. System environment variables (os.getenv)
-------------------------------------------------

local M = {}
local _envCache = {}
local _loaded = false

-- Parse a single .env file into the cache (does not overwrite existing keys)
local function parseEnvFile(filePath)
    local f = io.open(filePath, "r")
    if not f then return false end

    for line in f:lines() do
        -- Trim leading/trailing whitespace
        local trimmed = line:match("^%s*(.-)%s*$")
        -- Skip empty lines and comments
        if trimmed ~= "" and not trimmed:match("^#") then
            -- Match KEY=VALUE (supports optional export KEY=VALUE)
            local key, val = trimmed:match("^(?:export%s+)?([%w_]+)%s*=%s*(.*)$")
            if not key then
                key, val = trimmed:match("^([%w_]+)%s*=%s*(.*)$")
            end
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
