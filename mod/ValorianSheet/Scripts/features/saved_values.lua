-- ValorianSheet / features/saved_values.lua
-- Checked once after every load: attribute values the game saved while a cheat was on.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Override = require("lib.override")
local Game = require("game")
local State = require("state")

local SavedValues = {}

-- Attribute -> the set it lives in, and whether its cheat is on right now.
local LEDGER_ATTRIBUTES = {
    MaxHealth = { set = "Health", cheatOn = function() return (State.settings.maxHealthFactor or 1) ~= 1 end },
    ParryWindowAdjustment = { set = "Melee", cheatOn = function() return State.settings.perfectParry == true end },
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

local function repairDamageMultipliers()
    local repaired = 0
    for _, multiplier in ipairs(DAMAGE_MULTIPLIERS) do
        local set = Game.AttributeSet(multiplier.set)
        local base = set and Game.GetBaseValue(set, multiplier.attribute)
        local default = defaultBaseValue(multiplier.className, multiplier.attribute)
        if base and base >= default * 1.4 then
            Game.SetBaseValueKeepModifiers(set, multiplier.attribute, default)
            Log.Info("repaired " .. multiplier.attribute .. ": " .. base .. " -> " .. default)
            repaired = repaired + 1
        end
    end
    if repaired > 0 then State.status = "Repaired your damage values (left over from an old cheat menu)" end
end

-- Returns false while an attribute set in the ledger is not readable yet (try again later).
local function restoreLedgerValues()
    local allChecked = true
    for attributeName, recorded in pairs(State.attributeLedger) do
        local known = LEDGER_ATTRIBUTES[attributeName]
        local set = known and Game.AttributeSet(known.set)
        local base = set and Game.GetBaseValue(set, attributeName)
        if not known then
            Override.RecordInLedger(attributeName, nil)
        elseif not base then
            allChecked = false
        else
            if not Override.NearlyEqual(base, recorded.written) then
                Log.Debug(attributeName .. ": saved value " .. base .. " is not ours, ledger entry dropped")
                Override.RecordInLedger(attributeName, nil)
            elseif known.cheatOn() then
                -- still on: the override picks up the real vanilla value from the ledger
                if attributeName == "MaxHealth" and recorded.vanilla > 0 then
                    State.appliedMaxHealthFactor = recorded.written / recorded.vanilla
                end
            else
                Game.SetBaseValueKeepModifiers(set, attributeName, recorded.vanilla)
                if attributeName == "MaxHealth" and recorded.written > 0 then
                    local health = Game.GetAttribute(set, "Health")
                    if health then
                        Game.SetAttribute(set, "Health", math.min(health * recorded.vanilla / recorded.written, recorded.vanilla))
                    end
                end
                Log.Info(attributeName .. ": put back to vanilla " .. recorded.vanilla .. " (was saved while the cheat was on)")
                Override.RecordInLedger(attributeName, nil)
            end
        end
    end
    return allChecked
end

-- Returns true once everything could be checked; until then the cheats wait (see cheats.lua), so
-- Max Health is never applied on top of a value saved last session.
function SavedValues.Check()
    repairDamageMultipliers()
    return restoreLedgerValues()
end

return SavedValues
