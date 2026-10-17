-- ValorianSheet / features/damage.lua
-- Scaling damage before it lands. The game deals damage through MTCombatUtils functions; we hook
-- them and scale the damage values:
--   incoming (target is William): God Mode blocks it (Damage Taken works on resistances instead,
--     see features/defense.lua)
--   outgoing (attacker is William or something he fired): One-Hit Kills / Damage Multiplier
-- Only the hit is changed, nothing is saved. The hooks are registered once, the first time any of
-- these cheats is on, and do nothing while they are all off.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")

local Damage = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local ONE_HIT_FACTOR = 100000

local hooksRegistered = false
local callDepth = 0

-- Hooked function -> parameter positions (1-based, after the context object) of the damage values,
-- the target and the attacker.
local DAMAGE_FUNCTIONS = {
    DealMeleeDamage = { damage = { 1 }, target = 2, attacker = 4 },
    DealRangedDamage = { damage = { 1 }, target = 2, attacker = 4 },
    DealExplosiveDamage = { damage = { 1 }, target = 2, attacker = 4 },
    DealEnvironmentalDamage = { damage = { 1 }, target = 2, attacker = 4 },
    DealCriticalDamage = { damage = { 1 }, target = 2, attacker = 4 },
    DealIgniteDamage = { damage = { 1 }, target = 2, attacker = 3 },
    DealInfectionDamage = { damage = { 1 }, target = 2, attacker = 3 },
    DealCrystallizationDamage = { damage = { 1 }, target = 2, attacker = 3 },
    DealDamage = { damage = { 2 }, target = 3, attacker = 4 },
    DealDamageWithEffect = { damage = { 3 }, target = 4, attacker = 5 },
    DealCombinedDamage = { damage = { 2, 3, 4, 5, 7, 8, 10 }, target = 12, attacker = 13 },
}

-- William, or something he fired (a projectile or grenade: its Instigator is William).
local function isFromPlayer(actor)
    if Game.IsPlayer(actor) then return true end
    return isValid(actor) and Game.IsPlayer(try(function() return actor.Instigator end))
end

local function scaleDamage(layout, params, factor)
    for _, position in ipairs(layout.damage) do
        local param = params[position]
        local value = param and Unreal.TryNumber(function() return param:get() end)
        if value and value > 0 then try(function() param:set(value * factor) end) end
    end
end

local function onDamage(functionName, ...)
    local layout, params = DAMAGE_FUNCTIONS[functionName], { ... }
    local targetParam, attackerParam = params[layout.target], params[layout.attacker]
    local settings = State.settings

    if Game.IsPlayer(targetParam and try(function() return targetParam:get() end)) then
        if not settings.godMode then return end
        scaleDamage(layout, params, 0)
        Log.Limited("incoming damage", 3, "God Mode blocked a hit (" .. functionName .. ")")
        return
    end

    if isFromPlayer(attackerParam and try(function() return attackerParam:get() end)) then
        local factor = settings.oneHitKills and ONE_HIT_FACTOR or (settings.damageMultiplier or 1)
        if factor == 1 then return end
        scaleDamage(layout, params, factor)
        Log.Limited("outgoing damage", 3, "your damage x" .. factor .. " (" .. functionName .. ")")
    end
end

local function registerHooks()
    if hooksRegistered then return end
    hooksRegistered = true
    local functionNames = {}
    for functionName in pairs(DAMAGE_FUNCTIONS) do functionNames[#functionNames + 1] = functionName end
    -- When one damage function calls another through script, only the outer one is scaled.
    local hooked = Game.HookCombatUtils(functionNames, function(functionName, ...)
        callDepth = callDepth + 1
        if callDepth == 1 then pcall(onDamage, functionName, ...) end
    end, function()
        callDepth = math.max(callDepth - 1, 0)
    end)
    Log.Info("damage: hooked " .. hooked .. " damage functions")
end

function Damage.Tick()
    if hooksRegistered then return end
    local settings = State.settings
    if settings.godMode or settings.oneHitKills or (settings.damageMultiplier or 1) ~= 1 then
        registerHooks()
    end
end

return Damage
