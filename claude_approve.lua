-------------------------------------------------
-- Claude Always Approve Toggle (commented out)
-- Menu bar icon to toggle ~/.claude_always_approve
-------------------------------------------------

-- local claudeMenuItem = nil
-- local claudeAlwaysApproveFile = os.getenv("HOME") .. "/.claude_always_approve"

-- local function claudeAlwaysApproveExists()
--     local f = io.open(claudeAlwaysApproveFile, "r")
--     if f then
--         f:close()
--         return true
--     end
--     return false
-- end

-- local function createClaudeAlwaysApprove()
--     local f = io.open(claudeAlwaysApproveFile, "w")
--     if f then
--         f:close()
--         return true
--     end
--     return false
-- end

-- local function deleteClaudeAlwaysApprove()
--     return os.remove(claudeAlwaysApproveFile)
-- end

-- local function toggleClaudeAlwaysApprove()
--     if claudeAlwaysApproveExists() then
--         deleteClaudeAlwaysApprove()
--         hs.notify.new({title="Claude", informativeText="Always approve disabled"}):send()
--     else
--         createClaudeAlwaysApprove()
--         hs.notify.new({title="Claude", informativeText="Always approve enabled"}):send()
--     end
--     -- Update menu title
--     if claudeMenuItem then
--         local isEnabled = claudeAlwaysApproveExists()
--         claudeMenuItem:setTitle(isEnabled and "C✓" or "C")
--     end
-- end

-- -- Create menu bar item
-- claudeMenuItem = hs.menubar.new()
-- if claudeMenuItem then
--     -- Set initial title based on current state
--     local isEnabled = claudeAlwaysApproveExists()
--     claudeMenuItem:setTitle(isEnabled and "C✓" or "C")
--     claudeMenuItem:setClickCallback(toggleClaudeAlwaysApprove)
--     claudeMenuItem:setTooltip("Click to toggle Claude Always Approve")
-- end
