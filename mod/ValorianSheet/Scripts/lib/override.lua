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

local Override = {}
Override.__index = Override

local try = Unreal.Try

function Override.new() return setmetatable({ entries = {} }, Override) end

-- ---------------------------------------------------------------------------
-- Ledger
-- ---------------------------------------------------------------------------

local ledgerDirty = false
local nextLedgerSaveAt = 0

function Override.RecordInLedger(attributeName, entry)
    State.attributeLedger[attributeName] = entry
    ledgerDirty = true
end

-- Persists the ledger, at most once a second.
function Override.FlushLedger()
    if not ledgerDirty or State.clock() < nextLedgerSaveAt then return end
    ledgerDirty = false
    nextLedgerSaveAt = State.clock() + 1
    if State.onLedgerChanged then pcall(State.onLedgerChanged, State.attributeLedger) end
end

function Override.NearlyEqual(a, b)
    return math.abs(a - b) <= math.max(0.0001, math.abs(b) * 0.0001)
end

-- ---------------------------------------------------------------------------
-- Overrides
-- ---------------------------------------------------------------------------

-- factorOrFunction: a number multiplies the base, a function computes the value from the base.
local function asComputation(factorOrFunction)
    if type(factorOrFunction) == "function" then return factorOrFunction end
    return function(base) return base * factorOrFunction end
end

-- A plain number property (CharacterMovement.MaxWalkSpeed, ...).
function Override:property(object, propertyName, factorOrFunction)
    local current = try(function() return object[propertyName] end)
    if type(current) ~= "number" then return end
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
    local wanted = asComputation(factorOrFunction)(entry.base)
    if math.abs(current - wanted) > 0.001 then
        try(function() object[propertyName] = wanted end)
    end
    entry.written = wanted
end

-- A gameplay attribute (FGameplayAttributeData).
function Override:attribute(set, attributeName, factorOrFunction)
    local base = Game.GetBaseValue(set, attributeName)
    if type(base) ~= "number" then return end
    local key = tostring(Unreal.AddressOf(set)) .. ":" .. attributeName
    local entry = self.entries[key]
    if not entry then
        local recorded = State.attributeLedger[attributeName]
        if recorded and Override.NearlyEqual(base, recorded.written) then
            Log.Info(attributeName .. ": " .. base .. " is our own value from last time, vanilla is " .. recorded.vanilla)
            base = recorded.vanilla
        end
        entry = { set = set, attributeName = attributeName, base = base }
        self.entries[key] = entry
        Log.Debug(attributeName .. ": vanilla " .. tostring(base))
    elseif entry.written and not Override.NearlyEqual(base, entry.written) then
        Log.Debug(attributeName .. ": game set base " .. tostring(base) .. ", new vanilla")
        entry.base = base
    end
    local wanted = asComputation(factorOrFunction)(entry.base)
    if not Override.NearlyEqual(Game.GetBaseValue(set, attributeName), wanted) then
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
            local current = try(function() return entry.object[entry.propertyName] end)
            if type(current) == "number" and entry.written and math.abs(current - entry.written) < 0.001 then
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
