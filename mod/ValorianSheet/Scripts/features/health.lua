-- ValorianSheet / features/health.lua
-- Survival: God Mode, Infinite Stamina / Nephtoglobin, Fall Damage, Max Health and Health
-- Regeneration. (Damage Taken is features/defense.lua.)

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Override = require("lib.override")
local Game = require("game")
local State = require("state")
local Hud = require("features.hud")
local Combat = require("features.combat")

local Health = {}

local try, isValid = Unreal.Try, Unreal.IsValid

-- ---------------------------------------------------------------------------
-- Healing
-- A heal path asks the game to heal (so its HUD and effects follow). The first heal checks that
-- health really rose; if it did not, that path writes health directly from then on and tells the
-- health bar. Each path decides once and logs its choice once.
-- ---------------------------------------------------------------------------

-- path: { label, apply = function(healthSet, amount) -> true when the call went through, method }
local function addHealth(path, healthSet, health, maxHealth, amount)
    if amount <= 0.01 then return end
    if path.method ~= "direct" and path.apply(healthSet, amount) then
        if path.method == "game" then return end
        local healthAfter = Game.GetAttribute(healthSet, "Health")
        if healthAfter and healthAfter >= health + amount * 0.5 then
            path.method = "game"
            Log.Info(path.label .. ": healing through the game")
            return
        end
    end
    if path.method ~= "direct" then
        path.method = "direct"
        Log.Info(path.label .. ": the game's heal did not apply, writing health directly")
    end
    local newHealth = math.min(maxHealth, health + amount)
    Game.SetAttribute(healthSet, "Health", newHealth)
    Hud.UpdateHealthBar(newHealth, maxHealth)
end

-- God Mode / Refill: MTCombatUtils:Overheal (a GameplayEffect, the bar animates as usual).
local overhealPath = {
    label = "full heal",
    apply = function(healthSet, amount)
        local combatUtils, player = Game.CombatUtils(), Game.Player()
        if not isValid(combatUtils) or not player then return false end
        local ok = try(function() combatUtils:Overheal(amount, player) return true end) == true
        -- Overheal may go above max; we never leave William overhealed
        local health, maxHealth = Game.GetAttribute(healthSet, "Health"), Game.GetAttribute(healthSet, "MaxHealth")
        if health and maxHealth and health > maxHealth then Game.SetAttribute(healthSet, "Health", maxHealth) end
        return ok
    end,
}

function Health.FillHealth()
    local healthSet, health, maxHealth = Game.PlayerHealth()
    if healthSet then addHealth(overhealPath, healthSet, health, maxHealth, maxHealth - health) end
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
-- Max Health: MaxHealth times the factor (a saved attribute, so through the ledger). Current health
-- moves with every change of max health so the bar keeps its fill; a save that already holds our
-- value (the ledger knows it) changes nothing and gets no free heal.
-- ---------------------------------------------------------------------------

local maxHealthOverride = Override.new()

local function applyMaxHealth()
    local factor = State.settings.maxHealthFactor or 1
    if factor == 1 and not maxHealthOverride:isActive() then return end
    local healthSet, health, maxHealthBefore = Game.PlayerHealth()
    if not healthSet then return end
    if factor ~= 1 then
        maxHealthOverride:attribute(healthSet, "MaxHealth", factor)
    else
        maxHealthOverride:restore()
    end
    local maxHealthAfter = Game.GetAttribute(healthSet, "MaxHealth")
    if maxHealthAfter and health > 0 and not Override.NearlyEqual(maxHealthAfter, maxHealthBefore) then
        local scaledHealth = math.min(health * maxHealthAfter / maxHealthBefore, maxHealthAfter)
        Game.SetAttribute(healthSet, "Health", scaledHealth)
        Log.Debug(string.format("max health %.0f -> %.0f, health %.0f -> %.0f", maxHealthBefore, maxHealthAfter, health, scaledHealth))
    end
end

-- ---------------------------------------------------------------------------
-- Health Regeneration (the approach of AeonGreyh's Passive Health Regen): health points per second,
-- starting a while after the last hit, up to a share of max health, optionally only out of combat.
-- Applied four times a second through GASCompanion's SetAttributeValue on the Health attribute the
-- game's own GE_AddHealth effect modifies, so the game and its HUD see a normal attribute change.
-- ---------------------------------------------------------------------------

local REGEN_STEP_SECONDS = 0.25
local ADD_HEALTH_EFFECT = "/Game/Minotaur/Gameplay/GAS/GameplayEffects/GE_AddHealth.Default__GE_AddHealth_C"
local COMPANION_LIBRARY = "/Script/GASCompanion.Default__GSCBlueprintFunctionLibrary"

local regen = { lastHealth = nil, lastHitAt = -math.huge, lastStepAt = nil, healthAttribute = nil, nextAttributeSearchAt = 0 }

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

local function getCompanionCore(library, player) return library:GetCompanionCoreComponent(player) end
local function setAttributeValue(core, attribute, value) core:SetAttributeValue(attribute, value) end

local regenPath = {
    label = "health regeneration",
    apply = function(healthSet, amount)
        local library, player, attribute = Unreal.Static(COMPANION_LIBRARY), Game.Player(), healthAttribute()
        local core = isValid(library) and player and try(getCompanionCore, library, player)
        local base = Game.GetBaseValue(healthSet, "Health")
        if not isValid(core) or not attribute or not base then return false end
        return pcall(setAttributeValue, core, attribute, base + amount)
    end,
}

local function regenerateHealth()
    local settings = State.settings
    local perSecond = settings.regenPerSecond or 0
    local healthSet, health, maxHealth
    if perSecond > 0 then healthSet, health, maxHealth = Game.PlayerHealth() end
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

    addHealth(regenPath, healthSet, health, maxHealth, math.min(perSecond * math.min(elapsed, 1), missing))
    regen.lastHealth = Game.GetAttribute(healthSet, "Health")
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
    Log.Guarded("max health", applyMaxHealth)
    Log.Guarded("health bar length", Hud.KeepHealthBarLength) -- after Max Health was applied this tick
end

Unreal.OnWorldReset(function()
    maxHealthOverride:release()
    regen.lastHealth, regen.lastStepAt = nil, nil
    -- fallCurve is not reset: the curve is a game asset that outlives the world, and resetting would
    -- take our scaled values for the originals. A different curve is noticed by its address.
end)

return Health
