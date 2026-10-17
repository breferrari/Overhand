-- ValorianSheet / features/health.lua
-- Survival: God Mode, Infinite Stamina / Nephtoglobin, Fall Damage, Damage Taken, Max Health and
-- Health Regeneration.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Override = require("lib.override")
local Game = require("game")
local State = require("state")
local Hud = require("features.hud")
local Combat = require("features.combat")
local Damage = require("features.damage")

local Health = {}

local try, isValid = Unreal.Try, Unreal.IsValid

-- ---------------------------------------------------------------------------
-- Healing
-- Heals through the game's own heal (MTCombatUtils:Overheal, a GameplayEffect, so the health bar
-- animates as usual). If that does not raise his health, the value is written directly and the
-- health bar is told.
-- ---------------------------------------------------------------------------

local healMethod = nil -- "game" / "direct", logged once

local function healTo(healthSet, health, maxHealth, targetHealth)
    targetHealth = math.min(targetHealth, maxHealth)
    if targetHealth <= health + 0.01 then return end
    local combatUtils, player = Game.CombatUtils(), Game.Player()
    if healMethod ~= "direct" and isValid(combatUtils) and player then
        try(function() combatUtils:Overheal(targetHealth - health, player) end)
        local healthAfter = Game.GetAttribute(healthSet, "Health")
        if healthAfter and healthAfter >= targetHealth - 0.5 then
            if healthAfter > maxHealth then Game.SetAttribute(healthSet, "Health", maxHealth) end -- no overheal from us
            if healMethod ~= "game" then
                healMethod = "game"
                Log.Info("healing through the game's heal effect")
            end
            return
        end
        if healMethod == nil then Log.Info("game heal did not apply, writing health directly") end
        healMethod = "direct"
    end
    Game.SetAttribute(healthSet, "Health", targetHealth)
    Hud.UpdateHealthBar(targetHealth, maxHealth)
end

function Health.FillHealth()
    local healthSet, health, maxHealth = Game.PlayerHealth()
    if healthSet then healTo(healthSet, health, maxHealth, maxHealth) end
end

function Health.FillStamina()
    local staminaSet = Game.AttributeSet("Stamina")
    if staminaSet then Game.FillAttribute(staminaSet, "Stamina", "MaxStamina") end
end

function Health.FillNephtoglobin()
    local bloodSet = Game.AttributeSet("Blood")
    if bloodSet then Game.FillAttribute(bloodSet, "BloodPoints", "MaxBloodPoints") end
end

-- ---------------------------------------------------------------------------
-- Fall damage
-- 0 %: while William is falling his "highest point" moves down with him, so the game measures a fall
-- of almost zero when he lands. Partial: his FallDamageCurve (fall height -> damage) is scaled. The
-- curve is a game asset that is not saved; the original values come back at 100 %.
-- ---------------------------------------------------------------------------

local function cancelFallHeight()
    local player, movement = Game.Player(), Game.Movement()
    if not player or not movement then return end
    if try(function() return movement.MovementMode end) == Game.MOVEMENT_MODE.FALLING then
        try(function() player:SetLastApexHeightToCurrentPosition() end)
    end
end

local fallCurve = { address = nil, originalValues = nil, appliedFactor = 1 }

local function forEachCurveKey(curve, visit)
    try(function()
        curve.FloatCurve.Keys:ForEach(function(index, element) visit(index, element:get()) end)
    end)
end

local function applyFallDamageCurve()
    local factor = State.settings.fallDamage or 1
    if factor <= 0 or State.settings.godMode then factor = 1 end
    if factor == fallCurve.appliedFactor and factor == 1 then return end
    local player = Game.Player()
    local curve = player and try(function() return player.FallDamageCurve end)
    if not isValid(curve) then return end
    local address = Unreal.AddressOf(curve)
    if address ~= fallCurve.address then
        fallCurve.address, fallCurve.originalValues, fallCurve.appliedFactor = address, {}, 1
        forEachCurveKey(curve, function(index, key) fallCurve.originalValues[index] = key.Value end)
    end
    if factor == fallCurve.appliedFactor then return end
    forEachCurveKey(curve, function(index, key)
        local original = fallCurve.originalValues[index]
        if type(original) == "number" then key.Value = original * factor end
    end)
    fallCurve.appliedFactor = factor
    Log.Info(string.format("fall damage: %d%%", math.floor(factor * 100 + 0.5)))
end

-- ---------------------------------------------------------------------------
-- Max Health and Damage Taken
-- Max Health: MaxHealth times the factor; current health is scaled with it so the bar keeps its fill.
-- Damage Taken: the damage hooks (features/damage.lua) scale hits before they land. For damage that
-- does not go through those functions, (1 - factor) of every loss is given back right after the hit.
-- ---------------------------------------------------------------------------

local maxHealthOverride = Override.new()
local lastHealth = nil

local function applyMaxHealthAndDamageTaken()
    local factor = State.settings.maxHealthFactor or 1
    local damageTaken = State.settings.damageTaken or 1
    if factor == 1 and State.appliedMaxHealthFactor == 1 and not maxHealthOverride:isActive() and damageTaken >= 1 then
        lastHealth = nil
        return
    end
    local healthSet = Game.AttributeSet("Health")
    if not healthSet then
        lastHealth = nil
        return
    end

    if factor ~= 1 then
        maxHealthOverride:attribute(healthSet, "MaxHealth", factor)
    elseif maxHealthOverride:isActive() then
        maxHealthOverride:restore()
    end
    if factor ~= State.appliedMaxHealthFactor then
        local _, health, maxHealth = Game.PlayerHealth()
        if health and health > 0 then
            local scaledHealth = math.min(health * factor / State.appliedMaxHealthFactor, maxHealth)
            Game.SetAttribute(healthSet, "Health", scaledHealth)
            Log.Debug("max health x" .. factor .. ": MaxHealth=" .. maxHealth .. ", Health " .. health .. " -> " .. scaledHealth)
        end
        State.appliedMaxHealthFactor = factor
        lastHealth = nil -- our own change, not damage
    end

    local _, health, maxHealth = Game.PlayerHealth()
    if not health then return end
    local tookHit = lastHealth and health < lastHealth - 0.5 and health > 0
    if damageTaken < 1 and tookHit and not Damage.ReducedRecently() then
        local loss = lastHealth - health
        healTo(healthSet, health, maxHealth, health + loss * (1 - damageTaken))
        local healthAfter = Game.GetAttribute(healthSet, "Health") or health
        Log.Debug(string.format("damage taken %.0f%% (fallback): lost %.1f, gave back %.1f", damageTaken * 100, loss, healthAfter - health))
        health = healthAfter
    end
    lastHealth = health
end

-- ---------------------------------------------------------------------------
-- Health Regeneration (the approach of AeonGreyh's Passive Health Regen): health points per second,
-- starting a while after the last hit, up to a share of max health, optionally only out of combat.
-- Applied four times a second through GASCompanion's SetAttributeValue on the Health attribute the
-- game's own GE_AddHealth effect modifies, so the game and its HUD see a normal attribute change.
-- If that path is not available, health is written directly and the health bar is told.
-- ---------------------------------------------------------------------------

local REGEN_STEP_SECONDS = 0.25
local ADD_HEALTH_EFFECT = "/Game/Minotaur/Gameplay/GAS/GameplayEffects/GE_AddHealth.Default__GE_AddHealth_C"
local COMPANION_LIBRARY = "/Script/GASCompanion.Default__GSCBlueprintFunctionLibrary"

local regen = {
    lastHealth = nil, lastHitAt = -math.huge, lastStepAt = nil,
    healthAttribute = nil, nextAttributeSearchAt = 0,
    method = nil,   -- "attributes" / "direct": decided by the first step that healed, logged once
}

-- The FGameplayAttribute for Health, taken from GE_AddHealth's modifiers (looked up every 5 s until found).
local function healthAttribute()
    if regen.healthAttribute or os.clock() < regen.nextAttributeSearchAt then return regen.healthAttribute end
    regen.nextAttributeSearchAt = os.clock() + 5
    local addHealth = Unreal.Static(ADD_HEALTH_EFFECT)
    if not isValid(addHealth) then return nil end
    try(function()
        addHealth.Modifiers:ForEach(function(_, element)
            local attribute = element:get().Attribute
            if not regen.healthAttribute and attribute.AttributeName:ToString() == "Health" then
                regen.healthAttribute = attribute
            end
        end)
    end)
    return regen.healthAttribute
end

local function addHealthThroughAttributeSystem(healthSet, amount)
    local library, player, attribute = Unreal.Static(COMPANION_LIBRARY), Game.Player(), healthAttribute()
    local core = isValid(library) and player and try(function() return library:GetCompanionCoreComponent(player) end)
    if not isValid(core) or not attribute then return false end
    local base = Game.GetBaseValue(healthSet, "Health")
    return base ~= nil and try(function() core:SetAttributeValue(attribute, base + amount) return true end) == true
end

local function regenerateHealth()
    local settings = State.settings
    local perSecond = settings.regenPerSecond or 0
    if perSecond <= 0 then
        regen.lastHealth, regen.lastStepAt = nil, nil
        return
    end
    local healthSet, health, maxHealth = Game.PlayerHealth()
    if not healthSet then
        regen.lastHealth, regen.lastStepAt = nil, nil
        return
    end
    local now = os.clock()
    if regen.lastHealth and health < regen.lastHealth - 0.01 then regen.lastHitAt = now end
    regen.lastHealth = health

    local missing = maxHealth * math.min(100, math.max(0, settings.regenMaxPercent or 100)) / 100 - health
    local waiting = health <= 0 or missing <= 0.001
        or now - regen.lastHitAt < (settings.regenDelay or 2)
        or (settings.regenOnlyOutOfCombat and Combat.IsInCombat())
    if waiting then
        regen.lastStepAt = nil
        return
    end
    if not regen.lastStepAt then
        regen.lastStepAt = now
        return
    end
    local elapsed = now - regen.lastStepAt
    if elapsed < REGEN_STEP_SECONDS then return end
    regen.lastStepAt = now

    local amount = math.min(perSecond * math.min(elapsed, 1), missing)
    if regen.method ~= "direct" and addHealthThroughAttributeSystem(healthSet, amount) then
        local healthAfter = Game.GetAttribute(healthSet, "Health")
        if healthAfter and healthAfter >= health + amount * 0.5 then
            regen.lastHealth = healthAfter
            if regen.method ~= "attributes" then
                regen.method = "attributes"
                Log.Info(string.format("health regeneration: %s health per second, through the attribute system", tostring(perSecond)))
            end
            return
        end
    end
    -- the attribute path is missing or did not raise health: write it directly from now on
    if regen.method ~= "direct" then
        regen.method = "direct"
        Log.Info(string.format("health regeneration: %s health per second, written directly", tostring(perSecond)))
    end
    Game.SetAttribute(healthSet, "Health", health + amount)
    Hud.UpdateHealthBar(health + amount, maxHealth)
    regen.lastHealth = Game.GetAttribute(healthSet, "Health") or health + amount
end

-- ---------------------------------------------------------------------------

function Health.Tick()
    local settings = State.settings
    if settings.godMode then Health.FillHealth() end
    if settings.infiniteStamina and not (settings.staminaOnlyOutOfCombat and Combat.IsInCombat()) then
        Health.FillStamina()
    end
    if settings.infiniteNephtoglobin then Health.FillNephtoglobin() end
    -- God Mode covers falls too: fall damage does not go through the damage functions we hook.
    if (settings.fallDamage or 1) <= 0 or settings.godMode or os.clock() < State.safeLandingUntil then
        cancelFallHeight()
    end
    Log.Guarded("fall damage", applyFallDamageCurve)
    Log.Guarded("health regeneration", regenerateHealth)
    Log.Guarded("damage hooks", Damage.Tick)
    Log.Guarded("max health and damage taken", applyMaxHealthAndDamageTaken)
    Log.Guarded("health bar length", Hud.KeepHealthBarLength) -- after Max Health was applied this tick
end

Unreal.OnWorldReset(function()
    maxHealthOverride:release()
    State.appliedMaxHealthFactor = 1
    lastHealth = nil
    regen.lastHealth, regen.lastStepAt = nil, nil
    -- fallCurve is not reset: the curve is a game asset that outlives the world, and resetting would
    -- take our scaled values for the originals. A different curve is noticed by its address.
end)

return Health
