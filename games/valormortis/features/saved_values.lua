-- games/valormortis/features/saved_values.lua
-- Checked once after every load: attribute values the game saved while a cheat was on.

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
    ParryWindowAdjustment = { set = "Melee", cheatOn = function() return App.settings.perfectParry or App.settings.claymoreParry end },
    StaminaMeleeCostMultiplier = { set = "Stamina", cheatOn = function() return (App.settings.staminaCost or 1) ~= 1 end },
    StaminaDodgeCostMultiplier = { set = "Stamina", cheatOn = function() return (App.settings.staminaCost or 1) ~= 1 end },
    StaminaBlockCostMultiplier = { set = "Stamina", cheatOn = function() return (App.settings.staminaCost or 1) ~= 1 end },
}

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

-- Returns true once everything could be checked (the caller retries until then).
function SavedValues.Check()
    return restoreLedgerValues()
end

return SavedValues
