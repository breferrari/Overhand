-- ValorianSheet / features/defense.lua
-- Damage Taken (the approach of AeonGreyh's Defense Multiplier): William's resistance attributes are
-- raised so the game's own damage calculation lets through only the chosen share of every hit.
-- A resistance r lets (1 - r) of the damage through; for a share s we write 1 - (1 - r) * s.
--
-- Only CurrentValue is written; the game rebuilds it from BaseValue on load, so nothing is saved.
-- When the game recalculates a resistance (a buff, a gem) it overwrites our value; that new value is
-- taken as the new vanilla and scaled again on the next tick.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")

local Defense = {}

local RESISTANCES = { "MeleeResistance", "RangedResistance", "ExplosiveResistance", "MagicResistance" }

-- resistance name -> { vanilla, written }, for the current health set
local tracked = {}
local loggedShare = nil

local function readCurrentValue(set, name) return set[name].CurrentValue end
local function writeCurrentValue(set, name, value) set[name].CurrentValue = value end

local function scaleResistance(healthSet, name, share)
    local current = Unreal.TryNumber(readCurrentValue, healthSet, name)
    if not current then return end
    local entry = tracked[name]
    if not entry then
        entry = { vanilla = current }
        tracked[name] = entry
    elseif entry.written and math.abs(current - entry.written) > 0.0001 then
        entry.vanilla = current -- the game recalculated it
    end
    if entry.vanilla > 1 then -- already immune to this damage type: leave it
        entry.written = nil
        return
    end
    local wanted = 1 - (1 - entry.vanilla) * share
    if math.abs(current - wanted) > 0.0001 then pcall(writeCurrentValue, healthSet, name, wanted) end
    entry.written = wanted
end

-- Puts the vanilla values back where ours are still in place.
local function restoreResistances(healthSet)
    for name, entry in pairs(tracked) do
        local current = healthSet and Unreal.TryNumber(readCurrentValue, healthSet, name)
        if current and entry.written and math.abs(current - entry.written) <= 0.0001 then
            pcall(writeCurrentValue, healthSet, name, entry.vanilla)
        end
    end
    tracked = {}
end

function Defense.Tick()
    local share = State.settings.damageTaken or 1
    if share >= 1 then
        if next(tracked) then restoreResistances(Game.AttributeSet("Health")) end
        loggedShare = nil
        return
    end
    local healthSet = Game.AttributeSet("Health")
    if not healthSet then return end
    for _, name in ipairs(RESISTANCES) do scaleResistance(healthSet, name, share) end
    if loggedShare ~= share then
        loggedShare = share
        Log.Info(string.format("damage taken: %d%% (resistances raised)", math.floor(share * 100 + 0.5)))
    end
end

-- A surviving health set gets its vanilla resistances back, so the next tick starts from them.
Unreal.OnWorldReset(function()
    restoreResistances(Unreal.GetCached("set_Health"))
    loggedShare = nil
end)

return Defense
