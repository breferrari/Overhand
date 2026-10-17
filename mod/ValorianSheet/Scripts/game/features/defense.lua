-- game/features/defense.lua
-- Damage Taken (the approach of AeonGreyh's Defense Multiplier): William's resistance attributes are
-- raised so the game's own damage calculation lets through only the chosen share of every hit.
-- A resistance r lets (1 - r) of the damage through; for a share s we write 1 - (1 - r) * s.
--
-- Only CurrentValue is changed (Override:currentValue); the game rebuilds it from BaseValue, so
-- nothing is saved. A recalculation by the game (a buff, a gem) is taken as the new vanilla and
-- scaled again: the resistances are re-applied whenever William's active effects change, and every
-- 0.25 s in case something else changed them.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Override = require("core.override")
local Game = require("game.game")
local App = require("core.app")
local Gas = require("gas.gas")

local Defense = {}

local RESISTANCES = { "MeleeResistance", "RangedResistance", "ExplosiveResistance", "MagicResistance" }
local REAPPLY_SECONDS = 0.25

local resistanceOverride = Override.new()
local applied = { share = nil, effectCount = -1, nextAt = 0 }

local appliedShare = 1
local function scaled(resistance)
    if resistance > 1 then return resistance end -- already immune to this damage type
    return 1 - (1 - resistance) * appliedShare
end

function Defense.Tick()
    local share = App.settings.damageTaken or 1
    if share >= 1 then
        if resistanceOverride:isActive() then resistanceOverride:restore() end
        applied.share = nil
        return
    end
    local effectCount = Gas.ActiveEffectCount()
    if share == applied.share and effectCount == applied.effectCount and os.clock() < applied.nextAt then return end
    local healthSet = Game.AttributeSet("Health")
    if not healthSet then return end
    appliedShare = share
    local readable = 0
    for _, name in ipairs(RESISTANCES) do
        if Gas.GetAttribute(healthSet, name) then
            readable = readable + 1
            resistanceOverride:apply(Gas.CURRENT_VALUE, healthSet, name, scaled)
        end
    end
    if readable == 0 then
        Log.Limited("damage taken unreadable", 1, "damage taken: no resistance attribute readable on the health set, the cheat cannot work")
    elseif applied.share ~= share then
        Log.Info(string.format("damage taken: %d%% (%d resistances raised)", math.floor(share * 100 + 0.5), readable))
    end
    applied.share, applied.effectCount, applied.nextAt = share, effectCount, os.clock() + REAPPLY_SECONDS
end

Unreal.OnWorldReset(function()
    resistanceOverride:release()
    applied.share = nil
end)

return Defense
