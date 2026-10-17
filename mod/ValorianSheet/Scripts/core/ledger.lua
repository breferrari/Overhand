-- core/ledger.lua
-- Values we wrote into game state that the game saves (e.g. a GAS attribute's BaseValue):
-- name -> { vanilla = x, written = y }. When the saved value later reads y again (after a load, or
-- after the cheat was switched off while the game was closed), its real value is x.
-- Persisted in settings.cfg as ledger.<name>=<vanilla>,<written>.

local Settings = require("core.settings")

local Ledger = {}

local entries = {}

function Ledger.Get(name) return entries[name] end

function Ledger.Record(name, entry)
    entries[name] = entry
    Settings.MarkDirty()
end

-- Calls visit(name, entry) for every entry; visit may remove entries.
function Ledger.ForEach(visit)
    local names = {}
    for name in pairs(entries) do names[#names + 1] = name end
    for _, name in ipairs(names) do visit(name, entries[name]) end
end

Settings.RegisterLines("ledger", {
    read = function(name, text)
        local vanilla, written = text:match("^([^,]+),([^,]+)$")
        if tonumber(vanilla) and tonumber(written) then
            entries[name] = { vanilla = tonumber(vanilla), written = tonumber(written) }
        end
    end,
    write = function()
        local lines = {}
        for name, entry in pairs(entries) do lines[name] = tostring(entry.vanilla) .. "," .. tostring(entry.written) end
        return lines
    end,
})

return Ledger
