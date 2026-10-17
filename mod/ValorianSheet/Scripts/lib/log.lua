-- ValorianSheet / lib/log.lua
-- Session log for bug reports. Every line goes to the UE4SS console and to ValorianSheet.log.
-- The file is opened, appended and closed for every line so nothing is lost when the game crashes.
-- Log.Debug lines are only written while Debug Logging is on (Misc tab).

local Paths = require("lib.paths")

local Log = {}

Log.TAG = "[ValorianSheet]"
Log.FILE = Paths.InModFolder("ValorianSheet.log")
Log.debugEnabled = false

local recentLines = {}       -- the last lines, for the bug report
local RECENT_LINE_LIMIT = 150

local function writeLine(line)
    recentLines[#recentLines + 1] = line
    if #recentLines > RECENT_LINE_LIMIT then table.remove(recentLines, 1) end
    pcall(function()
        local file = io.open(Log.FILE, "a")
        if file then
            file:write(line, "\n")
            file:close()
        end
    end)
end

function Log.Info(message)
    print(Log.TAG .. " " .. tostring(message) .. "\n")
    writeLine(os.date("%H:%M:%S") .. " " .. tostring(message))
end

function Log.Debug(message)
    if Log.debugEnabled then Log.Info("[debug] " .. tostring(message)) end
end

function Log.RecentLines() return recentLines end

-- New session: keep the previous log as .old, start a fresh one.
function Log.StartSession(header)
    pcall(function()
        local file = io.open(Log.FILE, "r")
        if file then
            file:close()
            os.remove(Log.FILE .. ".old")
            os.rename(Log.FILE, Log.FILE .. ".old")
        end
    end)
    writeLine("==== " .. header .. " | session " .. os.date("%Y-%m-%d %H:%M:%S") .. " ====")
end

-- Runs fn; an error is logged with its stack trace (context = what was running) instead of raised.
function Log.Guarded(context, fn, ...)
    local ok, first, second = xpcall(fn, function(err) return debug.traceback(tostring(err), 2) end, ...)
    if not ok then
        Log.Info("ERROR in " .. context .. ": " .. tostring(first))
        return nil
    end
    return first, second
end

return Log
