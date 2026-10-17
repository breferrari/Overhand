-- ValorianSheet / features/combat.lua
-- Combat state, Every Block Is A Perfect Parry, Parry Window, Dodge Window and Kill All Enemies Nearby.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Override = require("lib.override")
local Game = require("game")
local State = require("state")

local Combat = {}

local try, isValid, addressOf = Unreal.Try, Unreal.IsValid, Unreal.AddressOf
local clock = State.clock

-- ---------------------------------------------------------------------------
-- In a fight? The game's CombatSubsystem knows; checked at most 4 times a second. The subsystems
-- are kept (Game.Subsystem), so a check never searches.
-- ---------------------------------------------------------------------------

local combatState = { checkedAt = -1, inCombat = false }

function Combat.IsInCombat()
    if clock() - combatState.checkedAt < 0.25 then return combatState.inCombat end
    combatState.checkedAt = clock()
    local inCombat = nil
    local combatSubsystem = Game.Subsystem("CombatSubsystem")
    if combatSubsystem then inCombat = try(function() return combatSubsystem:IsInCombat() end) end
    if inCombat == nil then
        local enemyInfo = Game.Subsystem("EnemyInfoSubsystem")
        local enemiesInCombat = enemyInfo and try(function() return enemyInfo.EnemiesInCombatState:GetArrayNum() end)
        if type(enemiesInCombat) == "number" then inCombat = enemiesInCombat > 0 end
    end
    inCombat = inCombat == true
    if inCombat ~= combatState.inCombat then Log.Debug("combat: " .. (inCombat and "started" or "ended")) end
    combatState.inCombat = inCombat
    return inCombat
end

-- ---------------------------------------------------------------------------
-- Every Block Is A Perfect Parry: a huge parry window on William's side (the attribute the
-- "Forgiving Parry" gem raises) and no parry cooldown / spam penalty on his weapon.
-- ---------------------------------------------------------------------------

local perfectParryOverride = Override.new()
local EXTRA_PARRY_WINDOW = 5.0

local function applyPerfectParry(enabled)
    if not enabled then
        if perfectParryOverride:isActive() then perfectParryOverride:restore() end
        return
    end
    local meleeSet = Game.AttributeSet("Melee")
    if meleeSet then
        perfectParryOverride:attribute(meleeSet, "ParryWindowAdjustment", function(base) return base + EXTRA_PARRY_WINDOW end)
    end
    local player = Game.Player()
    local weapon = player and try(function() return player.CurrentMeleeWeapon end)
    if isValid(weapon) then
        perfectParryOverride:property(weapon, "PerfectParryCooldown", 0)
        perfectParryOverride:property(weapon, "PerfectParrySpamReduction", 0)
    end
end

-- ---------------------------------------------------------------------------
-- Parry Window: when an enemy hit reaches William's block, the game checks the attack's
-- PerfectParryOpeningTime (MTCombatUtils:CheckBlockMelee / ...ForProperties / CheckBlockProjectile).
-- We scale that value for this one check (the attack data is a copy, nothing is saved).
-- ---------------------------------------------------------------------------

local parryHooks = { registered = false, scaledChecks = 0 }
local BLOCK_CHECK_FUNCTIONS = { "CheckBlockMelee", "CheckBlockMeleeForProperties", "CheckBlockProjectile" }

local function onBlockCheck(functionName, attackDataParam, blockerParam)
    local factor = State.settings.parryWindow or 1
    if factor == 1 then return end
    local player = Game.Player()
    local blocker = blockerParam and try(function() return blockerParam:get() end)
    if not player or not isValid(blocker) or addressOf(blocker) ~= addressOf(player) then return end
    local attackData = try(function() return attackDataParam:get() end)
    local openingTime = attackData and try(function() return attackData.PerfectParryOpeningTime end)
    if type(openingTime) ~= "number" then return end
    try(function() attackData.PerfectParryOpeningTime = openingTime * factor end)
    local after = try(function() return attackDataParam:get().PerfectParryOpeningTime end)
    if type(after) == "number" and math.abs(after - openingTime * factor) > 0.0001 then
        -- the struct came back as a copy: write it back as a whole
        try(function() attackDataParam:set(attackData) end)
        after = try(function() return attackDataParam:get().PerfectParryOpeningTime end)
    end
    parryHooks.scaledChecks = parryHooks.scaledChecks + 1
    if parryHooks.scaledChecks <= 3 or Log.debugEnabled then
        Log.Info(string.format("parry window x%s (%s): %.3f -> %s", tostring(factor), functionName, openingTime, tostring(after)))
    end
end

local function registerParryHooks()
    if parryHooks.registered then return end
    parryHooks.registered = true
    local hooked = 0
    for _, functionName in ipairs(BLOCK_CHECK_FUNCTIONS) do
        local ok = pcall(RegisterHook, "/Script/MinotaurCore.MTCombatUtils:" .. functionName, function(_, attackData, blocker)
            pcall(onBlockCheck, functionName, attackData, blocker)
        end)
        if ok then hooked = hooked + 1 end
    end
    Log.Info("parry window: hooked " .. hooked .. " block checks")
end

-- ---------------------------------------------------------------------------
-- Dodge Window: every dodge gives William GE_Invincibility for a short time (0.25 s in 1.0); hits in
-- that time are dodged perfectly. We make that effect last longer (the game checks the duration again
-- when it runs out) or remove it earlier for the harder settings.
-- ---------------------------------------------------------------------------

local DODGE_EFFECTS = { GE_DodgeAttackEnabled_C = true, GE_Dodge_WaitingForInput_C = true, GE_DodgeCooldown_C = true }
local dodges = { handled = {}, logs = 0 }   -- handled: invincibility start time -> { wantedDuration, removed }

local function applyDodgeWindow()
    local factor = State.settings.dodgeWindow or 1
    if factor == 1 then
        if next(dodges.handled) then dodges.handled = {} end
        return
    end
    local worldTime = Game.WorldTime()
    if type(worldTime) ~= "number" then return end

    local invincibilities, dodgeStartTimes = {}, {}
    Game.ForEachActiveEffect(function(activeEffect, className, definition)
        local startTime = try(function() return activeEffect.StartWorldTime end)
        if not className or type(startTime) ~= "number" then return end
        if className == "GE_Invincibility_C" then
            invincibilities[#invincibilities + 1] = {
                effect = activeEffect,
                startTime = startTime,
                effectClass = try(function() return definition:GetClass() end),
            }
        elseif DODGE_EFFECTS[className] then
            dodgeStartTimes[#dodgeStartTimes + 1] = startTime
        end
    end)

    local abilitySystem = Game.AbilitySystem()
    local stillActive = {}
    for _, invincibility in ipairs(invincibilities) do
        local key = string.format("%.3f", invincibility.startTime)
        stillActive[key] = true
        local fromDodge = false
        for _, dodgeStart in ipairs(dodgeStartTimes) do
            if math.abs(dodgeStart - invincibility.startTime) < 0.1 then
                fromDodge = true
                break
            end
        end
        local handled = dodges.handled[key]
        if fromDodge and not handled then
            local duration = try(function() return invincibility.effect.Spec.Duration end)
            if type(duration) == "number" and duration > 0 and duration < 5 then
                handled = { wantedDuration = duration * factor }
                dodges.handled[key] = handled
                if factor > 1 then try(function() invincibility.effect.Spec.Duration = handled.wantedDuration end) end
                dodges.logs = dodges.logs + 1
                if dodges.logs <= 3 or Log.debugEnabled then
                    Log.Info(string.format("dodge window x%s: %.2f s -> %.2f s", tostring(factor), duration, handled.wantedDuration))
                end
            end
        end
        -- harder settings: end the invincibility early
        local expired = handled and worldTime - invincibility.startTime >= handled.wantedDuration
        if expired and factor < 1 and not handled.removed and abilitySystem then
            handled.removed = true
            try(function() abilitySystem:RemoveActiveGameplayEffectBySourceEffect(invincibility.effectClass, nil, -1) end)
        end
    end
    for key in pairs(dodges.handled) do
        if not stillActive[key] then dodges.handled[key] = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Kill every enemy within 60 m (one search, on the button press only).
-- ---------------------------------------------------------------------------

local KILL_RADIUS = 6000   -- Unreal units (cm)

function Combat.KillEnemiesNearby()
    local player = Game.Player()
    local playerLocation = player and try(function() return player:K2_GetActorLocation() end)
    if not playerLocation then return end
    local killed = 0
    for _, enemy in ipairs(FindAllOf("EnemyCharacter") or {}) do
        if isValid(enemy) then
            local location = try(function() return enemy:K2_GetActorLocation() end)
            local health = try(function() return enemy.HealthAttributes.Health.CurrentValue end)
            if location and type(health) == "number" and health > 0 then
                local dx, dy, dz = location.X - playerLocation.X, location.Y - playerLocation.Y, location.Z - playerLocation.Z
                local inRange = dx * dx + dy * dy + dz * dz < KILL_RADIUS * KILL_RADIUS
                if inRange and try(function()
                    enemy:KillCharacter(player, { GameplayTags = {}, ParentTags = {} })
                    return true
                end) then
                    killed = killed + 1
                end
            end
        end
    end
    Log.Info("killed " .. killed .. " enemies nearby")
    State.status = "Killed " .. killed .. " enemies nearby"
end

-- ---------------------------------------------------------------------------

function Combat.Tick()
    if (State.settings.parryWindow or 1) ~= 1 then registerParryHooks() end
    applyPerfectParry(State.settings.perfectParry == true)
    Log.Guarded("dodge window", applyDodgeWindow)
end

function Combat.Reset()
    perfectParryOverride:forget()
    dodges.handled = {}
end

return Combat
