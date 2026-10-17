-- ValorianSheet / features/damage.lua
-- Scaling damage before it lands. The game deals damage through MTCombatUtils functions; we hook
-- them and scale the damage values:
--   incoming (target is William): God Mode = 0, otherwise the Damage Taken share
--   outgoing (attacker is William or something he fired): One-Hit Kills / Damage Multiplier
-- Only the hit is changed, nothing is saved. The hooks are registered once, the first time any of
-- these cheats is on, and do nothing while they are all off.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")

local Damage = {}

local try, isValid, addressOf = Unreal.Try, Unreal.IsValid, Unreal.AddressOf

local ONE_HIT_FACTOR = 100000

local hooks = {
    registered = false,
    lastIncomingAt = -99,
    incomingLogs = 0,
    outgoingLogs = 0,
    callDepth = 0,
}

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

-- Is this actor William, or something he fired (a projectile or grenade: its Instigator is William)?
local function isFromPlayer(actor, playerAddress)
    if not isValid(actor) then return false end
    if addressOf(actor) == playerAddress then return true end
    local instigator = try(function() return actor.Instigator end)
    return isValid(instigator) and addressOf(instigator) == playerAddress
end

local function scaleDamage(layout, params, factor)
    for _, position in ipairs(layout.damage) do
        local param = params[position]
        local value = param and try(function() return param:get() end)
        if type(value) == "number" and value > 0 then
            try(function() param:set(value * factor) end)
        end
    end
end

local function onDamage(functionName, layout, params)
    local player = Game.Player()
    if not player then return end
    local playerAddress = addressOf(player)
    local targetParam, attackerParam = params[layout.target], params[layout.attacker]
    local target = targetParam and try(function() return targetParam:get() end)
    local attacker = attackerParam and try(function() return attackerParam:get() end)
    local settings = State.settings

    if isValid(target) and addressOf(target) == playerAddress then
        local factor = settings.godMode and 0 or (settings.damageTaken or 1)
        if factor >= 1 then return end
        scaleDamage(layout, params, factor)
        hooks.lastIncomingAt = State.clock()
        hooks.incomingLogs = hooks.incomingLogs + 1
        if hooks.incomingLogs <= 3 or Log.debugEnabled then
            Log.Info("damage reduced before the hit (" .. functionName .. ")")
        end
        return
    end

    if isFromPlayer(attacker, playerAddress) then
        local factor = settings.oneHitKills and ONE_HIT_FACTOR or (settings.damageMultiplier or 1)
        if factor == 1 then return end
        scaleDamage(layout, params, factor)
        hooks.outgoingLogs = hooks.outgoingLogs + 1
        if hooks.outgoingLogs <= 3 or Log.debugEnabled then
            Log.Info("your damage x" .. factor .. " (" .. functionName .. ")")
        end
    end
end

local function registerHooks()
    if hooks.registered then return end
    hooks.registered = true
    local hooked = 0
    for functionName, layout in pairs(DAMAGE_FUNCTIONS) do
        -- When one damage function calls another through script, only the outer one is scaled.
        local ok = pcall(RegisterHook, "/Script/MinotaurCore.MTCombatUtils:" .. functionName, function(_, ...)
            hooks.callDepth = hooks.callDepth + 1
            if hooks.callDepth == 1 then pcall(onDamage, functionName, layout, { ... }) end
        end, function()
            hooks.callDepth = math.max(hooks.callDepth - 1, 0)
        end)
        if ok then hooked = hooked + 1 end
    end
    Log.Info("damage: hooked " .. hooked .. " damage functions")
end

-- Did a hook reduce incoming damage in the last half second? (then the fallback in health.lua waits)
function Damage.ReducedRecently() return State.clock() - hooks.lastIncomingAt < 0.5 end

function Damage.Tick()
    local settings = State.settings
    if (settings.damageTaken or 1) < 1 or settings.godMode or settings.oneHitKills
        or (settings.damageMultiplier or 1) ~= 1 then
        registerHooks()
    end
end

return Damage
