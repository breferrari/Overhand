-- ValorianSheet / lib/override.lua
-- Overrides with vanilla restore.
-- The game changes speeds and multipliers on its own (sprint, buffs, ...). An override remembers the
-- value the game wants (the base) and writes compute(base); when the game writes a new value, that
-- becomes the new base. restore() puts the base back.
--
-- Gameplay attributes are saved into the save file, so a changed attribute survives save/load. To
-- never mistake our own value for vanilla, every attribute value we write is kept in a ledger
-- (State.attributeLedger, persisted in settings.cfg): { vanilla = x, written = y }. When the
-- attribute later reads y again (after a load, or after the cheat was switched off while the game was
-- closed), its real value is x. Only BaseValue is compared: buffs change CurrentValue and must not
-- count as vanilla.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Settings = require("settings")

local Override = {}
Override.__index = Override

-- How a value is read and written. Module-level: these run every tick for every active override.
local function readProperty(object, propertyName) return object[propertyName] end
local function writeProperty(object, propertyName, value) object[propertyName] = value end

local PROPERTY = {
    read = function(object, name) return Unreal.TryNumber(readProperty, object, name) end,
    write = function(object, name, value) pcall(writeProperty, object, name, value) end,
}
-- An attribute's CurrentValue: rebuilt by the game from BaseValue (on load, on recalculation), so
-- like a property it is never saved and needs no ledger.
local CURRENT_VALUE = { read = Game.GetAttribute, write = Game.SetCurrentValue }

-- entries: object address -> property/attribute name -> entry
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

function Override.RecordInLedger(attributeName, entry)
    State.attributeLedger[attributeName] = entry
    Settings.MarkDirty()
end

function Override.NearlyEqual(a, b)
    return math.abs(a - b) <= math.max(0.0001, math.abs(b) * 0.0001)
end

-- factorOrFunction: a number multiplies the base, a function computes the value from the base.
local function compute(factorOrFunction, base)
    if type(factorOrFunction) == "function" then return factorOrFunction(base) end
    return base * factorOrFunction
end

-- A value that is not saved, through an accessor pair (see PROPERTY / CURRENT_VALUE).
local function overrideUnsaved(override, accessor, object, name, factorOrFunction)
    local current = accessor.read(object, name)
    if not current then return end
    local entry, byName = entryFor(override, object, name)
    if not byName then return end
    if not entry then
        entry = { object = object, name = name, accessor = accessor, base = current }
        byName[name] = entry
        Log.Debug(name .. ": vanilla " .. tostring(current))
    elseif entry.written and not Override.NearlyEqual(current, entry.written) then
        Log.Debug(name .. ": game set " .. tostring(current) .. ", new base")
        entry.base = current
    end
    local wanted = compute(factorOrFunction, entry.base)
    if not Override.NearlyEqual(current, wanted) then accessor.write(object, name, wanted) end
    entry.written = wanted
end

-- A plain number property (CharacterMovement.MaxWalkSpeed, ...).
function Override:property(object, propertyName, factorOrFunction)
    overrideUnsaved(self, PROPERTY, object, propertyName, factorOrFunction)
end

-- An attribute's CurrentValue (e.g. the resistances): changed live only, never saved.
function Override:currentValue(set, attributeName, factorOrFunction)
    overrideUnsaved(self, CURRENT_VALUE, set, attributeName, factorOrFunction)
end

-- A gameplay attribute (FGameplayAttributeData).
function Override:attribute(set, attributeName, factorOrFunction)
    local currentBase = Game.GetBaseValue(set, attributeName)
    if not currentBase then return end
    local entry, byName = entryFor(self, set, attributeName)
    if not byName then return end
    if not entry then
        local vanilla = currentBase
        local recorded = State.attributeLedger[attributeName]
        if recorded and Override.NearlyEqual(currentBase, recorded.written) then
            Log.Info(attributeName .. ": " .. currentBase .. " is our own value from last time, vanilla is " .. recorded.vanilla)
            vanilla = recorded.vanilla
        end
        entry = { set = set, attributeName = attributeName, base = vanilla }
        byName[attributeName] = entry
        Log.Debug(attributeName .. ": vanilla " .. tostring(vanilla))
    elseif entry.written and not Override.NearlyEqual(currentBase, entry.written) then
        Log.Debug(attributeName .. ": game set base " .. tostring(currentBase) .. ", new vanilla")
        entry.base = currentBase
    end
    local wanted = compute(factorOrFunction, entry.base)
    if not Override.NearlyEqual(currentBase, wanted) then
        Game.SetBaseValueKeepModifiers(set, attributeName, wanted)
    end
    if entry.written ~= wanted or not State.attributeLedger[attributeName] then
        Override.RecordInLedger(attributeName, { vanilla = entry.base, written = wanted })
    end
    entry.written = wanted
end

-- An unsaved value still holding ours gets its base back.
local function restoreUnsaved(entry)
    if not Unreal.IsValid(entry.object) then return end
    local current = entry.accessor.read(entry.object, entry.name)
    if current and entry.written and Override.NearlyEqual(current, entry.written) then
        entry.accessor.write(entry.object, entry.name, entry.base)
    end
end

function Override:restore()
    forEachEntry(self, function(entry)
        if entry.accessor then
            restoreUnsaved(entry)
        else
            if Unreal.IsValid(entry.set) then
                Game.SetBaseValueKeepModifiers(entry.set, entry.attributeName, entry.base)
                Log.Debug(entry.attributeName .. ": back to vanilla " .. tostring(entry.base))
            end
            Override.RecordInLedger(entry.attributeName, nil)
        end
    end)
    self.entries = {}
end

-- World reset: objects that survive it (the same William after a restart) get their vanilla
-- unsaved values back, so the next apply starts from the real base instead of our own value.
-- Saved attributes keep our value: the ledger recognises it on the next apply.
function Override:release()
    forEachEntry(self, function(entry)
        if entry.accessor then restoreUnsaved(entry) end
    end)
    self.entries = {}
end

function Override:isActive() return next(self.entries) ~= nil end

return Override
