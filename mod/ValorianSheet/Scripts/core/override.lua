-- core/override.lua
-- Overrides with vanilla restore.
-- The game changes speeds, multipliers and stats on its own (sprint, buffs, ...). An override
-- remembers the value the game wants (the base) and writes compute(base); when the game writes a new
-- value, that becomes the new base. restore() puts the base back.
--
-- What is overridden is described by an accessor: { read(object, name) -> number or nil,
-- write(object, name, value), saved = boolean }.
--   Override.PROPERTY    a plain number property (CharacterMovement.MaxWalkSpeed, ...)
--   gas/gas.lua          BASE_VALUE (saved) and CURRENT_VALUE (not saved) of GAS attributes
-- A saved value survives save/load, so every value written through a saved accessor is kept in the
-- ledger (core/ledger.lua) to never mistake our own value for vanilla.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Ledger = require("core.ledger")

local Override = {}
Override.__index = Override

-- Module-level callees: these run every tick for every active override.
local function readProperty(object, propertyName) return object[propertyName] end
local function writeProperty(object, propertyName, value) object[propertyName] = value end

Override.PROPERTY = {
    read = function(object, name) return Unreal.TryNumber(readProperty, object, name) end,
    write = function(object, name, value) pcall(writeProperty, object, name, value) end,
    saved = false,
}

function Override.NearlyEqual(a, b)
    return math.abs(a - b) <= math.max(0.0001, math.abs(b) * 0.0001)
end

-- entries: object address -> name -> { object, name, accessor, base, written }
function Override.new() return setmetatable({ entries = {} }, Override) end

local function entryFor(override, object, name)
    local address = Unreal.AddressOf(object)
    if not address then return nil, nil end
    local byName = override.entries[address]
    if not byName then
        byName = {}
        override.entries[address] = byName
    end
    return byName[name], byName
end

local function forEachEntry(override, visit)
    for _, byName in pairs(override.entries) do
        for _, entry in pairs(byName) do visit(entry) end
    end
end

-- factorOrFunction: a number multiplies the base, a function computes the value from the base.
local function compute(factorOrFunction, base)
    if type(factorOrFunction) == "function" then return factorOrFunction(base) end
    return base * factorOrFunction
end

-- Writes compute(base) to object's value `name` through accessor, adopting the game's own changes
-- as the new base.
function Override:apply(accessor, object, name, factorOrFunction)
    local current = accessor.read(object, name)
    if not current then return end
    local entry, byName = entryFor(self, object, name)
    if not byName then return end
    if not entry then
        local base = current
        local recorded = accessor.saved and Ledger.Get(name)
        if recorded and Override.NearlyEqual(current, recorded.written) then
            Log.Info(name .. ": " .. current .. " is our own value from last time, vanilla is " .. recorded.vanilla)
            base = recorded.vanilla
        end
        entry = { object = object, name = name, accessor = accessor, base = base }
        byName[name] = entry
        Log.Debug(name .. ": vanilla " .. tostring(base))
    elseif entry.written and not Override.NearlyEqual(current, entry.written) then
        Log.Debug(name .. ": game set " .. tostring(current) .. ", new base")
        entry.base = current
    end
    local wanted = compute(factorOrFunction, entry.base)
    if not Override.NearlyEqual(current, wanted) then accessor.write(object, name, wanted) end
    if accessor.saved and (entry.written ~= wanted or not Ledger.Get(name)) then
        Ledger.Record(name, { vanilla = entry.base, written = wanted })
    end
    entry.written = wanted
end

function Override:property(object, propertyName, factorOrFunction)
    self:apply(Override.PROPERTY, object, propertyName, factorOrFunction)
end

local function restoreEntry(entry)
    local saved = entry.accessor.saved
    if Unreal.IsValid(entry.object) then
        if saved then
            entry.accessor.write(entry.object, entry.name, entry.base)
            Log.Debug(entry.name .. ": back to vanilla " .. tostring(entry.base))
        else
            -- only while it still holds ours (the game may have set its own value since)
            local current = entry.accessor.read(entry.object, entry.name)
            if current and entry.written and Override.NearlyEqual(current, entry.written) then
                entry.accessor.write(entry.object, entry.name, entry.base)
            end
        end
    end
    if saved then Ledger.Record(entry.name, nil) end
end

-- Everything back to vanilla (the cheat was switched off).
function Override:restore()
    forEachEntry(self, restoreEntry)
    self.entries = {}
end

-- World reset: objects that survive it (the same character after a restart) get their unsaved
-- values back, so the next apply starts from the real base instead of our own value. Saved values
-- keep ours: the ledger recognises it on the next apply.
function Override:release()
    forEachEntry(self, function(entry)
        if not entry.accessor.saved then restoreEntry(entry) end
    end)
    self.entries = {}
end

function Override:isActive() return next(self.entries) ~= nil end

return Override
