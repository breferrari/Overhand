-- games/valormortis/features/combat.lua
-- Combat state, Every Block Is A Perfect Parry, Parry Window, Dodge Window and Kill All Enemies Nearby.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Override = require("core.override")
local Game = require("game.game")
local App = require("core.app")
local Gas = require("gas.gas")

local Combat = {}

local try, isValid = Unreal.Try, Unreal.IsValid

-- ---------------------------------------------------------------------------
-- In a fight? The world's EnemyInfoSubsystem lists the enemies that are fighting William (the check
-- AeonGreyh's Passive Health Regen uses). The subsystem of William's own world is kept; the answer
-- is re-read at most 4 times a second.
-- ---------------------------------------------------------------------------

local combatState = { checkedAt = -math.huge, inCombat = false }

local function enemyInfoOfThisWorld()
    local cached = Unreal.GetCached("enemyInfo")
    if cached then return cached end
    -- a miss: search (at most every 5 s) for the subsystem whose outer is William's world
    local worldAddress = Unreal.AddressOf(Game.World())
    return Unreal.FindCached("enemyInfo", "EnemyInfoSubsystem", 5, function(subsystem)
        local outer = try(function() return subsystem:GetOuter() end)
        return worldAddress ~= nil and Unreal.AddressOf(outer) == worldAddress
    end)
end

function Combat.IsInCombat()
    if os.clock() - combatState.checkedAt < 0.25 then return combatState.inCombat end
    combatState.checkedAt = os.clock()
    local enemyInfo = enemyInfoOfThisWorld()
    local inCombat = false
    if enemyInfo then
        try(function()
            enemyInfo.EnemiesInCombatState:ForEach(function(_, element)
                if not inCombat and isValid(element:get()) then inCombat = true end
            end)
        end)
    end
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

local function applyPerfectParry()
    if not App.settings.perfectParry then
        if perfectParryOverride:isActive() then perfectParryOverride:restore() end
        return
    end
    local meleeSet = Game.AttributeSet("Melee")
    if meleeSet then
        perfectParryOverride:apply(Gas.BASE_VALUE, meleeSet, "ParryWindowAdjustment", function(base) return base + EXTRA_PARRY_WINDOW end)
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

local parryHooksRegistered = false

local function onBlockCheck(functionName, attackDataParam, blockerParam)
    local factor = App.settings.parryWindow or 1
    if factor == 1 then return end
    if not Game.IsPlayer(blockerParam and try(function() return blockerParam:get() end)) then return end
    local attackData = try(function() return attackDataParam:get() end)
    local openingTime = attackData and Unreal.TryNumber(function() return attackData.PerfectParryOpeningTime end)
    if not openingTime then return end
    try(function() attackData.PerfectParryOpeningTime = openingTime * factor end)
    local after = Unreal.TryNumber(function() return attackDataParam:get().PerfectParryOpeningTime end)
    if after and math.abs(after - openingTime * factor) > 0.0001 then
        -- the struct came back as a copy: write it back as a whole
        try(function() attackDataParam:set(attackData) end)
        after = Unreal.TryNumber(function() return attackDataParam:get().PerfectParryOpeningTime end)
    end
    Log.Limited("parry window", 3, string.format("parry window x%s (%s): %.3f -> %s", tostring(factor), functionName, openingTime, tostring(after)))
end

local function registerParryHooks()
    if parryHooksRegistered then return end
    parryHooksRegistered = true
    local hooked = Game.HookCombatUtils({ "CheckBlockMelee", "CheckBlockMeleeForProperties", "CheckBlockProjectile" },
        function(functionName, attackData, blocker) pcall(onBlockCheck, functionName, attackData, blocker) end)
    Log.Info("parry window: hooked " .. hooked .. " block checks")
end

-- ---------------------------------------------------------------------------
-- Dodge Window: every dodge gives William GE_Invincibility for a short time (0.25 s in 1.0); hits in
-- that time are dodged perfectly. We make that effect last longer (the game checks the duration again
-- when it runs out) or remove it earlier for the harder settings.
-- The effect list is only read when its length changes (a dodge adds effects) or while an early
-- removal is pending.
-- ---------------------------------------------------------------------------

local DODGE_EFFECTS = { GE_DodgeAttackEnabled_C = true, GE_Dodge_WaitingForInput_C = true, GE_DodgeCooldown_C = true }
local dodges = { handled = {}, lastEffectCount = -1, removalPending = false }

local function applyDodgeWindow()
    local factor = App.settings.dodgeWindow or 1
    if factor == 1 then
        dodges.handled, dodges.lastEffectCount, dodges.removalPending = {}, -1, false
        return
    end
    local effectCount = Gas.ActiveEffectCount()
    if effectCount == dodges.lastEffectCount and not dodges.removalPending then return end
    dodges.lastEffectCount = effectCount
    local worldTime = Game.WorldTime()
    if not worldTime then return end

    local invincibilities, dodgeStartTimes = {}, {}
    for _, entry in ipairs(Gas.ActiveEffects()) do
        if entry.startTime and entry.className == "GE_Invincibility_C" then
            invincibilities[#invincibilities + 1] = entry
        elseif entry.startTime and DODGE_EFFECTS[entry.className] then
            dodgeStartTimes[#dodgeStartTimes + 1] = entry.startTime
        end
    end

    local abilitySystem = Game.AbilitySystem()
    local stillActive = {}
    dodges.removalPending = false
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
            local duration = Unreal.TryNumber(function() return invincibility.effect.Spec.Duration end)
            if duration and duration > 0 and duration < 5 then
                handled = { wantedDuration = duration * factor }
                dodges.handled[key] = handled
                if factor > 1 then try(function() invincibility.effect.Spec.Duration = handled.wantedDuration end) end
                Log.Limited("dodge window", 3, string.format("dodge window x%s: %.2f s -> %.2f s", tostring(factor), duration, handled.wantedDuration))
            end
        end
        -- harder settings: end the invincibility early
        if handled and factor < 1 and not handled.removed then
            if worldTime - invincibility.startTime >= handled.wantedDuration and abilitySystem then
                handled.removed = true
                local effectClass = try(function() return invincibility.definition:GetClass() end)
                try(function() abilitySystem:RemoveActiveGameplayEffectBySourceEffect(effectClass, nil, -1) end)
                Gas.InvalidateActiveEffects()
            else
                dodges.removalPending = true
            end
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
    local playerLocation = try(function() return player:K2_GetActorLocation() end)
    if not playerLocation then return end
    local killed = 0
    for _, enemy in ipairs(Unreal.FindAllLive("EnemyCharacter")) do
        local location = try(function() return enemy:K2_GetActorLocation() end)
        local health = Unreal.TryNumber(function() return enemy.HealthAttributes.Health.CurrentValue end)
        if location and health and health > 0 then
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
    Log.Info("killed " .. killed .. " enemies nearby")
    App.status = "Killed " .. killed .. " enemies nearby"
end

-- ---------------------------------------------------------------------------

function Combat.Tick()
    if (App.settings.parryWindow or 1) ~= 1 then registerParryHooks() end
    applyPerfectParry()
    Log.Guarded("dodge window", applyDodgeWindow)
end

Unreal.OnWorldReset(function()
    perfectParryOverride:release()
    dodges.handled, dodges.lastEffectCount, dodges.removalPending = {}, -1, false
    combatState.checkedAt = -math.huge
end)

return Combat
