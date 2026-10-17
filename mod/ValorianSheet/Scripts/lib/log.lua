-- ValorianSheet / lib/log.lua
-- Session log for bug reports. Every line goes to the UE4SS console and to ValorianSheet.log.
-- The file is opened, appended and closed for every line so nothing is lost when the game crashes.
-- Debug lines are only written while Debug logging is on (State.settings.debugLogging).

local Paths = require("lib.paths")
local State = require("state")

local Log = {}

local TAG = "[ValorianSheet]"
local LOG_FILE = Paths.InModFolder("ValorianSheet.log")
local RECENT_LINE_LIMIT = 150
local ERROR_REPEAT_SECONDS = 5

local recentLines = {}         -- the last lines, for the bug report
local limitedCounts = {}       -- Log.Limited key -> lines written
local lastErrorAt = {}         -- Log.Guarded context -> clock time of the last error line

local function writeLine(line)
    recentLines[#recentLines + 1] = line
    if #recentLines > RECENT_LINE_LIMIT then table.remove(recentLines, 1) end
    pcall(function()
        local file = io.open(LOG_FILE, "a")
        if file then
            file:write(line, "\n")
            file:close()
        end
    end)
end

function Log.IsDebugEnabled() return State.settings.debugLogging == true end

function Log.Info(message)
    print(TAG .. " " .. tostring(message) .. "\n")
    writeLine(os.date("%H:%M:%S") .. " " .. tostring(message))
end

function Log.Debug(message)
    if Log.IsDebugEnabled() then Log.Info("[debug] " .. tostring(message)) end
end

-- For lines that repeat (every hit, every dodge): the first `limit` per key, or all with Debug logging.
function Log.Limited(key, limit, message)
    local count = (limitedCounts[key] or 0) + 1
    limitedCounts[key] = count
    if count <= limit or Log.IsDebugEnabled() then Log.Info(message) end
end

function Log.RecentLines() return recentLines end

-- New session: keep the previous log as .old, start a fresh one.
function Log.StartSession(header)
    if Paths.Exists(LOG_FILE) then
        os.remove(LOG_FILE .. ".old")
        os.rename(LOG_FILE, LOG_FILE .. ".old")
    end
    writeLine("==== " .. header .. " | session " .. os.date("%Y-%m-%d %H:%M:%S") .. " ====")
end

local function withTraceback(err) return debug.traceback(tostring(err), 2) end

-- Runs fn; an error is logged with its stack trace instead of raised. The same context logs at most
-- one error every few seconds, so a failure on a per-tick path does not flood the log.
function Log.Guarded(context, fn, ...)
    local ok, err = xpcall(fn, withTraceback, ...)
    if ok then return true end
    if os.clock() >= (lastErrorAt[context] or -math.huge) + ERROR_REPEAT_SECONDS then
        lastErrorAt[context] = os.clock()
        Log.Info("ERROR in " .. context .. ": " .. tostring(err))
    end
    return false
end

return Log
