-- core/log.lua
-- Session log for bug reports. Every line goes to the UE4SS console and to <App.name>.log in the
-- mod folder. The file is opened, appended and closed for every line so nothing is lost when the
-- game crashes. Debug lines are only written while App.settings.debugLogging is on.

local App = require("core.app")
local Paths = require("core.paths")

local Log = {}

local RECENT_LINE_LIMIT = 150
local ERROR_REPEAT_SECONDS = 5

local recentLines = {}         -- the last lines, for the bug report
local limitedCounts = {}       -- Log.Limited key -> lines written
local lastErrorAt = {}         -- Log.Guarded context -> clock time of the last error line

local function logFile() return Paths.InModFolder(App.name .. ".log") end

local function writeLine(line)
    recentLines[#recentLines + 1] = line
    if #recentLines > RECENT_LINE_LIMIT then table.remove(recentLines, 1) end
    pcall(function()
        local file = io.open(logFile(), "a")
        if file then
            file:write(line, "\n")
            file:close()
        end
    end)
end

function Log.IsDebugEnabled() return App.settings.debugLogging == true end

function Log.Info(message)
    print("[" .. App.name .. "] " .. tostring(message) .. "\n")
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
function Log.StartSession()
    local file = logFile()
    if Paths.Exists(file) then
        os.remove(file .. ".old")
        os.rename(file, file .. ".old")
    end
    writeLine("==== " .. App.name .. " v" .. App.version .. " | session " .. os.date("%Y-%m-%d %H:%M:%S") .. " ====")
end

local function withTraceback(err) return debug.traceback(tostring(err), 2) end

-- Runs fn; an error is logged with its stack trace instead of raised. The same context logs at most
-- one error every few seconds, so a failure on a per-tick path does not flood the log.
-- Returns true and fn's first result, or false.
function Log.Guarded(context, fn, ...)
    local ok, result = xpcall(fn, withTraceback, ...)
    if ok then return true, result end
    if os.clock() >= (lastErrorAt[context] or -math.huge) + ERROR_REPEAT_SECONDS then
        lastErrorAt[context] = os.clock()
        Log.Info("ERROR in " .. context .. ": " .. tostring(result))
    end
    return false
end

return Log
