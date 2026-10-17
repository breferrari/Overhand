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

local try = Unreal.Try

function Override.new() return setmetatable({ entries = {} }, Override) end

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

-- A plain number property (CharacterMovement.MaxWalkSpeed, ...).
function Override:property(object, propertyName, factorOrFunction)
    local current = Unreal.TryNumber(function() return object[propertyName] end)
    if not current then return end
    local key = tostring(Unreal.AddressOf(object)) .. ":" .. propertyName
    local entry = self.entries[key]
    if not entry then
        entry = { object = object, propertyName = propertyName, base = current }
        self.entries[key] = entry
        Log.Debug(propertyName .. ": vanilla " .. tostring(current))
    elseif entry.written and math.abs(current - entry.written) > 0.001 then
        Log.Debug(propertyName .. ": game set " .. tostring(current) .. ", new base")
        entry.base = current
    end
    local wanted = compute(factorOrFunction, entry.base)
    if math.abs(current - wanted) > 0.001 then
        try(function() object[propertyName] = wanted end)
    end
    entry.written = wanted
end

-- A gameplay attribute (FGameplayAttributeData).
function Override:attribute(set, attributeName, factorOrFunction)
    local currentBase = Game.GetBaseValue(set, attributeName)
    if not currentBase then return end
    local key = tostring(Unreal.AddressOf(set)) .. ":" .. attributeName
    local entry = self.entries[key]
    if not entry then
        local vanilla = currentBase
        local recorded = State.attributeLedger[attributeName]
        if recorded and Override.NearlyEqual(currentBase, recorded.written) then
            Log.Info(attributeName .. ": " .. currentBase .. " is our own value from last time, vanilla is " .. recorded.vanilla)
            vanilla = recorded.vanilla
        end
        entry = { set = set, attributeName = attributeName, base = vanilla }
        self.entries[key] = entry
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

function Override:restore()
    for _, entry in pairs(self.entries) do
        if entry.object and Unreal.IsValid(entry.object) then
            local current = Unreal.TryNumber(function() return entry.object[entry.propertyName] end)
            if current and entry.written and math.abs(current - entry.written) < 0.001 then
                try(function() entry.object[entry.propertyName] = entry.base end)
            end
        elseif entry.set then
            if Unreal.IsValid(entry.set) then
                Game.SetBaseValueKeepModifiers(entry.set, entry.attributeName, entry.base)
                Log.Debug(entry.attributeName .. ": back to vanilla " .. tostring(entry.base))
            end
            Override.RecordInLedger(entry.attributeName, nil)
        end
    end
    self.entries = {}
end

-- After a map change: the objects are gone, nothing to restore.
function Override:forget() self.entries = {} end

function Override:isActive() return next(self.entries) ~= nil end

return Override
