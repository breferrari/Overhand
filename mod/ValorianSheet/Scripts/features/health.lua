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
local clock = State.clock

-- ---------------------------------------------------------------------------
-- Healing
-- Heals through the game's own heal (MTCombatUtils:Overheal, a GameplayEffect, so the health bar
-- animates as usual). If that does not raise his health, the value is written directly and the
-- health bar is told.
-- ---------------------------------------------------------------------------

local healMethod = nil -- "game" / "direct", logged once

function Health.HealTo(healthSet, targetHealth)
    local health = Game.GetAttribute(healthSet, "Health")
    local maxHealth = Game.GetAttribute(healthSet, "MaxHealth")
    if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then return end
    targetHealth = math.min(targetHealth, maxHealth)
    if targetHealth <= health + 0.01 then return end

    local combatUtils, player = Game.CombatUtils(), Game.Player()
    if healMethod ~= "direct" and isValid(combatUtils) and player then
        try(function() combatUtils:Overheal(targetHealth - health, player) end)
        local healthAfter = Game.GetAttribute(healthSet, "Health")
        if type(healthAfter) == "number" and healthAfter >= targetHealth - 0.5 then
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
    local healthSet = Game.AttributeSet("Health")
    local maxHealth = healthSet and Game.GetAttribute(healthSet, "MaxHealth")
    if type(maxHealth) == "number" then Health.HealTo(healthSet, maxHealth) end
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

local MOVEMENT_MODE_FALLING = 3

local function cancelFallHeight()
    local player, movement = Game.Player(), Game.Movement()
    if not player or not movement then return end
    if try(function() return movement.MovementMode end) == MOVEMENT_MODE_FALLING then
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
    local healthSet = Game.AttributeSet("Health")
    if not healthSet then
        lastHealth = nil
        return
    end

    local factor = State.settings.maxHealthFactor or 1
    if factor ~= 1 then
        maxHealthOverride:attribute(healthSet, "MaxHealth", factor)
    elseif maxHealthOverride:isActive() then
        maxHealthOverride:restore()
    end
    if factor ~= State.appliedMaxHealthFactor then
        local health = Game.GetAttribute(healthSet, "Health")
        local maxHealth = Game.GetAttribute(healthSet, "MaxHealth")
        if type(health) == "number" and type(maxHealth) == "number" and health > 0 then
            local scaledHealth = math.min(health * factor / State.appliedMaxHealthFactor, maxHealth)
            Game.SetAttribute(healthSet, "Health", scaledHealth)
            Log.Debug("max health x" .. factor .. ": MaxHealth=" .. maxHealth .. ", Health " .. health .. " -> " .. scaledHealth)
        end
        State.appliedMaxHealthFactor = factor
        lastHealth = nil -- our own change, not damage
    end

    local health = Game.GetAttribute(healthSet, "Health")
    if type(health) ~= "number" then return end
    local damageTaken = State.settings.damageTaken or 1
    local tookHit = lastHealth and health < lastHealth - 0.5 and health > 0
    if damageTaken < 1 and tookHit and not Damage.ReducedRecently() then
        local loss = lastHealth - health
        Health.HealTo(healthSet, health + loss * (1 - damageTaken))
        local healthAfter = Game.GetAttribute(healthSet, "Health") or health
        Log.Debug(string.format("damage taken %.0f%% (fallback): lost %.1f, gave back %.1f", damageTaken * 100, loss, healthAfter - health))
        health = healthAfter
    end
    lastHealth = health
end

-- ---------------------------------------------------------------------------
-- Health Regeneration: a share of max health per second, starting a few seconds after the last hit
-- (optionally only out of combat). Applied in small steps four times a second, written directly so
-- the game's heal effect and sound do not fire every step.
-- ---------------------------------------------------------------------------

local regen = { lastHealth = nil, lastHitAt = -99, lastStepAt = nil, logged = false }

local function regenerateHealth()
    local settings = State.settings
    local rate = settings.regenRate or 0
    local healthSet = Game.AttributeSet("Health")
    local health = healthSet and Game.GetAttribute(healthSet, "Health")
    local maxHealth = healthSet and Game.GetAttribute(healthSet, "MaxHealth")
    if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
        regen.lastHealth, regen.lastStepAt = nil, nil
        return
    end
    local now = clock()
    if regen.lastHealth and health < regen.lastHealth - 0.01 then regen.lastHitAt = now end
    regen.lastHealth = health

    local waiting = rate <= 0 or health <= 0 or health >= maxHealth
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
    if elapsed < 0.25 then return end
    regen.lastStepAt = now

    local newHealth = math.min(maxHealth, health + maxHealth * rate * math.min(elapsed, 1))
    Game.SetAttribute(healthSet, "Health", newHealth)
    Hud.UpdateHealthBar(newHealth, maxHealth)
    regen.lastHealth = Game.GetAttribute(healthSet, "Health") or newHealth
    if not regen.logged then
        regen.logged = true
        Log.Info(string.format("health regeneration: %.0f%% of max health per second", rate * 100))
    end
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
    if (settings.fallDamage or 1) <= 0 or settings.godMode or clock() < State.safeLandingUntil then
        cancelFallHeight()
    end
    Log.Guarded("fall damage", applyFallDamageCurve)
    Log.Guarded("health regeneration", regenerateHealth)
    Damage.Tick()
    applyMaxHealthAndDamageTaken()
    Log.Guarded("health bar length", Hud.KeepHealthBarLength) -- after Max Health was applied this tick
end

function Health.Reset()
    maxHealthOverride:forget()
    State.appliedMaxHealthFactor = 1
    lastHealth = nil
    Hud.Reset()
end

-- After a load: the save may hold a Max Health factor we wrote last session (see saved_values.lua).
function Health.AssumeAppliedFactor(factor) State.appliedMaxHealthFactor = factor end

return Health
