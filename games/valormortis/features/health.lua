-- games/valormortis/features/health.lua
-- Survival: God Mode, Infinite Stamina / Nephtoglobin, Fall Damage, Max Health and Health
-- Regeneration. (Damage Taken is features/defense.lua.)

local Unreal = require("core.unreal")
local Log = require("core.log")
local Override = require("core.override")
local Game = require("game.game")
local App = require("core.app")
local Hud = require("game.features.hud")
local Combat = require("game.features.combat")
local Gas = require("gas.gas")
local Shared = require("game.shared")

local Health = {}

local try, isValid = Unreal.Try, Unreal.IsValid

-- ---------------------------------------------------------------------------
-- Healing
-- A heal path asks the game to heal (so its HUD and effects follow). Every heal checks that health
-- really rose; a heal that did not land is written directly instead, and the health bar is told.
-- Nothing is decided for good: the game's path is tried again on the next heal.
-- ---------------------------------------------------------------------------

-- path: { label, apply = function(healthSet, amount) -> true when the call went through }
local function addHealth(path, healthSet, health, maxHealth, amount)
    if amount <= 0.01 then return end
    if path.apply(healthSet, amount) then
        local healthAfter = Gas.GetAttribute(healthSet, "Health")
        if healthAfter and healthAfter >= health + amount * 0.5 then
            Log.Limited(path.label .. " game", 1, path.label .. ": healing through the game")
            return
        end
    end
    Log.Limited(path.label .. " direct", 3, path.label .. ": the game's heal did not apply, writing health directly")
    local newHealth = math.min(maxHealth, health + amount)
    Gas.SetAttribute(healthSet, "Health", newHealth)
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
        local health, maxHealth = Gas.GetAttribute(healthSet, "Health"), Gas.GetAttribute(healthSet, "MaxHealth")
        if health and maxHealth and health > maxHealth then Gas.SetAttribute(healthSet, "Health", maxHealth) end
        return ok
    end,
}

function Health.FillHealth()
    local healthSet, health, maxHealth = Game.PlayerHealth()
    if healthSet then addHealth(overhealPath, healthSet, health, maxHealth, maxHealth - health) end
end

function Health.FillStamina()
    local staminaSet = Game.AttributeSet("Stamina")
    if staminaSet then Gas.FillAttribute(staminaSet, "Stamina", "MaxStamina") end
end

function Health.FillNephtoglobin()
    local bloodSet = Game.AttributeSet("Blood")
    if bloodSet then Gas.FillAttribute(bloodSet, "BloodPoints", "MaxBloodPoints") end
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
    local factor = App.settings.fallDamage or 1
    if factor <= 0 or App.settings.godMode then factor = 1 end
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
-- moves with our own changes of max health, so the bar keeps its fill: it is scaled from the max
-- health we wrote last (or, when switching on, the max health just before) to the one we write now.
-- A change the game makes in between (a level-up) is not ours to scale. After a load the save may
-- already hold our value; then the switch-on write changes nothing and gives no free heal.
-- ---------------------------------------------------------------------------

local maxHealthOverride = Override.new()
local lastWrittenMaxHealth = nil

local function applyMaxHealth()
    local factor = App.settings.maxHealthFactor or 1
    local wasActive = maxHealthOverride:isActive()
    if factor == 1 and not wasActive then return end
    local healthSet, health, maxHealthBefore = Game.PlayerHealth()
    if not healthSet then return end
    if factor ~= 1 then
        maxHealthOverride:apply(Gas.BASE_VALUE, healthSet, "MaxHealth", factor)
    else
        maxHealthOverride:restore()
    end
    local maxHealthAfter = Gas.GetAttribute(healthSet, "MaxHealth")
    if not maxHealthAfter then return end
    local previous = wasActive and lastWrittenMaxHealth or maxHealthBefore
    lastWrittenMaxHealth = factor ~= 1 and maxHealthAfter or nil
    if previous and health > 0 and not Override.NearlyEqual(maxHealthAfter, previous) then
        local scaledHealth = math.min(health * maxHealthAfter / previous, maxHealthAfter)
        Gas.SetAttribute(healthSet, "Health", scaledHealth)
        Log.Debug(string.format("max health %.0f -> %.0f, health %.0f -> %.0f", previous, maxHealthAfter, health, scaledHealth))
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
        local base = Gas.GetBaseValue(healthSet, "Health")
        if not isValid(core) or not attribute or not base then return false end
        return pcall(setAttributeValue, core, attribute, base + amount)
    end,
}

local function regenerateHealth()
    local settings = App.settings
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
    regen.lastHealth = Gas.GetAttribute(healthSet, "Health")
end

-- ---------------------------------------------------------------------------

function Health.Tick()
    local settings = App.settings
    if settings.godMode then Health.FillHealth() end
    if settings.infiniteStamina and not (settings.staminaOnlyOutOfCombat and Combat.IsInCombat()) then
        Health.FillStamina()
    end
    if settings.infiniteNephtoglobin then Health.FillNephtoglobin() end
    -- God Mode covers falls too: fall damage does not go through the damage functions we hook.
    if (settings.fallDamage or 1) <= 0 or settings.godMode or os.clock() < Shared.safeLandingUntil then
        cancelFallHeight()
    end
    Log.Guarded("fall damage", applyFallDamageCurve)
    Log.Guarded("health regeneration", regenerateHealth)
    Log.Guarded("max health", applyMaxHealth)
    Log.Guarded("health bar length", Hud.KeepHealthBarLength) -- after Max Health was applied this tick
end

Unreal.OnWorldReset(function()
    maxHealthOverride:release()
    lastWrittenMaxHealth = nil
    regen.lastHealth, regen.lastStepAt = nil, nil
    -- fallCurve is not reset: the curve is a game asset that outlives the world, and resetting would
    -- take our scaled values for the originals. A different curve is noticed by its address.
end)

return Health
