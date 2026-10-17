-- core/bug_report.lua
-- One text file with the settings, the sections the game adds (BugReport.AddSection) and the last
-- log lines: <App.name>-BugReport.txt in the mod folder.

local App = require("core.app")
local Log = require("core.log")
local Paths = require("core.paths")

local BugReport = {}

local sections = {}   -- { title, lines() -> list of strings }

function BugReport.AddSection(title, lines) sections[#sections + 1] = { title = title, lines = lines } end

function BugReport.Write()
    local fileName = App.name .. "-BugReport.txt"
    local lines = {}
    local function add(line) lines[#lines + 1] = line end

    add(App.name .. " v" .. App.version .. " - bug report")
    add("Written: " .. os.date("%Y-%m-%d %H:%M:%S"))
    add("Status: " .. tostring(App.status))
    add("")
    add("== Settings ==")
    for _, key in ipairs(App.SortedSettingKeys()) do add(key .. " = " .. tostring(App.settings[key])) end
    for _, section in ipairs(sections) do
        add("")
        add("== " .. section.title .. " ==")
        local ok, sectionLines = Log.Guarded("bug report section " .. section.title, section.lines)
        for _, line in ipairs(ok and sectionLines or { "(could not be read)" }) do add(line) end
    end
    add("")
    add("== Last log lines ==")
    for _, line in ipairs(Log.RecentLines()) do add(line) end

    local ok = Paths.WriteFile(Paths.InModFolder(fileName), table.concat(lines, "\n") .. "\n")
    Log.Info(ok and ("bug report written: " .. fileName) or ("could not write " .. fileName))
    App.status = ok and ("Saved " .. fileName .. " in the mod folder") or "Could not write the bug report"
end

return BugReport
