-- games/valormortis/features/saved_values.lua
-- Checked once after every load: attribute values the game saved while a cheat was on.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Override = require("core.override")
local Ledger = require("core.ledger")
local Game = require("game.game")
local App = require("core.app")
local Gas = require("gas.gas")

local SavedValues = {}

-- Attribute -> the set it lives in, and whether its cheat is on right now.
local LEDGER_ATTRIBUTES = {
    MaxHealth = { set = "Health", cheatOn = function() return (App.settings.maxHealthFactor or 1) ~= 1 end },
    ParryWindowAdjustment = { set = "Melee", cheatOn = function() return App.settings.perfectParry == true end },
}

local function defaultBaseValue(className, attributeName)
    local defaults = Unreal.Static("/Script/MinotaurCore.Default__" .. className)
    local value = defaults and Unreal.TryNumber(function() return defaults[attributeName].BaseValue end)
    if value and value >= 0.05 and value <= 20 then return value end
    return 1
end

-- Valor Mortis Cheat Menu 1.1.0 and older wrote One-Hit Kills (x1000) and the Damage Multiplier
-- (up to x10) into the saved damage multipliers. The game never changes their base value itself
-- (weapon and gem bonuses are effects on top), so a base of 1.4x the game's default or more can only
-- come from that and is put back to the default. Active bonuses are kept.
local DAMAGE_MULTIPLIERS = {
    { set = "Melee", className = "MeleeAttributeSet", attribute = "MeleeDamageMultiplier" },
    { set = "Ranged", className = "RangedAttributeSet", attribute = "RangedDamageMultiplier" },
}

-- Returns false (and repairs nothing) while a damage attribute set is not readable yet.
local function repairDamageMultipliers()
    local found = {}
    for index, multiplier in ipairs(DAMAGE_MULTIPLIERS) do
        local set = Game.AttributeSet(multiplier.set)
        local base = set and Gas.GetBaseValue(set, multiplier.attribute)
        if not base then return false end
        found[index] = { set = set, base = base }
    end
    local repaired = 0
    for index, multiplier in ipairs(DAMAGE_MULTIPLIERS) do
        local set, base = found[index].set, found[index].base
        local default = defaultBaseValue(multiplier.className, multiplier.attribute)
        if base >= default * 1.4 then
            Gas.SetBaseValueKeepModifiers(set, multiplier.attribute, default)
            Log.Info("repaired " .. multiplier.attribute .. ": " .. base .. " -> " .. default)
            repaired = repaired + 1
        end
    end
    if repaired > 0 then App.status = "Repaired your damage values (left over from an old cheat menu)" end
    return true
end

-- Returns false while an attribute set in the ledger is not readable yet (try again later).
local function restoreLedgerValues()
    local allChecked = true
    Ledger.ForEach(function(attributeName, recorded)
        local known = LEDGER_ATTRIBUTES[attributeName]
        local set = known and Game.AttributeSet(known.set)
        local base = set and Gas.GetBaseValue(set, attributeName)
        if not known then
            Ledger.Record(attributeName, nil)
        elseif not base then
            allChecked = false
        elseif not Override.NearlyEqual(base, recorded.written) then
            Log.Debug(attributeName .. ": saved value " .. base .. " is not ours, ledger entry dropped")
            Ledger.Record(attributeName, nil)
        elseif not known.cheatOn() then -- (still on: the override picks up the vanilla value itself)
            Gas.SetBaseValueKeepModifiers(set, attributeName, recorded.vanilla)
            if attributeName == "MaxHealth" and recorded.written > 0 then
                local health = Gas.GetAttribute(set, "Health")
                if health then
                    Gas.SetAttribute(set, "Health", math.min(health * recorded.vanilla / recorded.written, recorded.vanilla))
                end
            end
            Log.Info(attributeName .. ": put back to vanilla " .. recorded.vanilla .. " (was saved while the cheat was on)")
            Ledger.Record(attributeName, nil)
        end
    end)
    return allChecked
end

-- Returns true once everything could be checked (the caller retries until then); each part runs
-- once per world.
local repairDone = false
function SavedValues.Check()
    repairDone = repairDone or repairDamageMultipliers()
    return restoreLedgerValues() and repairDone
end

Unreal.OnWorldReset(function() repairDone = false end)

return SavedValues
