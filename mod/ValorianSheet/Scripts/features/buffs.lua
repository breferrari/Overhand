-- ValorianSheet / features/buffs.lua
-- Infinite Buffs: potions, weapon coatings and pistol boosts never run out.
-- Every active buff gets a very long duration; the old one comes back when the cheat is switched
-- off. Buffs are saved with their remaining time, so after a load with the cheat off, buffs that
-- still have our long time get 2 more minutes.
--
-- When an effect's timer runs out the game checks Spec.Duration again and keeps the effect if the
-- duration was made longer, so a longer Spec.Duration is all it takes.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Hud = require("features.hud")

local Buffs = {}

local try = Unreal.Try

local BUFF_EFFECTS = {
    GE_Bubble_C = true, GE_ProtectionPotion_C = true, GE_StaminaPotion_C = true, GE_Rage_C = true,
    GE_FlamingCoating_C = true, GE_SharpCoating_C = true, GE_StasisCoating_C = true,
    GE_FlamingBoost_C = true, GE_PreciseBoost_C = true, GE_StasisBoost_C = true, GE_ConcussingBoost_C = true,
}
local LONG_DURATION = 36000       -- 10 hours
local LEFTOVER_DURATION = 120     -- what a leftover long buff gets when the cheat is off

local buffs = {
    nextScanAt = 0,
    originalDurations = {},   -- buff key -> its duration before we extended it
    peakStacks = {},          -- buff key -> the highest stack count seen
    stackHandles = {},        -- effect handle id -> { handle, peak }, to tell the HUD about refills
    stackHookRegistered = false,
}

local function keyOf(entry, precision)
    return entry.className .. "@" .. string.format(precision, entry.startTime)
end

local function extendBuffs()
    if os.clock() < buffs.nextScanAt then return end
    local enabled = State.settings.infiniteBuffs == true
    buffs.nextScanAt = os.clock() + (enabled and 0.1 or 0.5)
    local worldTime = Game.WorldTime()
    if not worldTime then return end
    local seen = {}
    local refreshHud = false

    for _, entry in ipairs(Game.ActiveEffects()) do
        if entry.className and BUFF_EFFECTS[entry.className] and entry.startTime then
            local activeEffect, key = entry.effect, keyOf(entry, "%.2f")
            seen[key] = true

            -- Coatings and pistol boosts count hits/shots as stacks: keep the highest count.
            local stacks = Unreal.TryNumber(function() return activeEffect.Spec.StackCount end)
            if enabled and stacks and stacks > 0 then
                local peak = buffs.peakStacks[key]
                if not peak or stacks > peak then
                    buffs.peakStacks[key] = stacks
                elseif stacks < peak then
                    try(function() activeEffect.Spec.StackCount = peak end)
                    refreshHud = true
                end
            end

            local duration = Unreal.TryNumber(function() return activeEffect.Spec.Duration end)
            local elapsed = worldTime - entry.startTime
            if duration and duration > 0 and enabled and duration - elapsed < LONG_DURATION / 2 then
                buffs.originalDurations[key] = buffs.originalDurations[key] or duration
                try(function() activeEffect.Spec.Duration = elapsed + LONG_DURATION end)
                Log.Info(string.format("infinite buff %s: %.0fs left -> extended", entry.className, duration - elapsed))
            elseif duration and duration > 0 and not enabled and duration - elapsed > LONG_DURATION / 4 then
                local restored = buffs.originalDurations[key] or (elapsed + LEFTOVER_DURATION)
                if restored <= elapsed then restored = elapsed + 1 end
                try(function() activeEffect.Spec.Duration = restored end)
                Log.Info(string.format("buff %s back to normal: %.0fs left", entry.className, restored - elapsed))
                buffs.originalDurations[key] = nil
            end
        end
    end

    for key in pairs(buffs.peakStacks) do
        if not seen[key] or not enabled then buffs.peakStacks[key] = nil end
    end
    if not enabled then buffs.stackHandles = {} end
    if refreshHud then
        -- The HUD only redraws buff counters when asked: ask it, and tell it about the stack change.
        Hud.RefreshTokens()
        local notifier = Game.AttributesNotifier()
        for _, stackHandle in pairs(buffs.stackHandles) do
            try(function() notifier:OnGameplayEffectStackChanged(stackHandle.handle, stackHandle.peak, stackHandle.peak - 1) end)
        end
    end
end

-- When the game changes a buff's stacks it tells the attributes notifier (with the effect handle).
-- We keep those handles so we can tell the HUD about our refill.
local function registerStackHook()
    if buffs.stackHookRegistered then return end
    buffs.stackHookRegistered = true
    local hookPath = "/Script/MinotaurCore.PlayerAttributesNotifier:OnGameplayEffectStackChanged"
    local ok = pcall(RegisterHook, hookPath, function(_, handleParam, newStackParam, oldStackParam)
        if State.settings.infiniteBuffs ~= true then return end
        local handleId = Unreal.TryNumber(function() return handleParam:get().Handle end)
        local newStack = Unreal.TryNumber(function() return newStackParam:get() end)
        local oldStack = Unreal.TryNumber(function() return oldStackParam:get() end)
        if handleId and newStack and oldStack and newStack < oldStack then
            local previous = buffs.stackHandles[handleId]
            buffs.stackHandles[handleId] = {
                handle = { Handle = handleId, bPassedFiltersAndWasExecuted = true },
                peak = math.max(oldStack, previous and previous.peak or 0),
            }
        end
    end)
    Log.Info("infinite buffs: stack hook " .. (ok and "on" or "not available"))
end

-- Debug logging only: logs every effect that appears on or leaves William.
local watchedEffects = {}

local function logEffectChanges()
    local worldTime = Game.WorldTime() or 0
    local current = {}
    for _, entry in ipairs(Game.ActiveEffects()) do
        local key = (entry.className or "?") .. "@" .. string.format("%.3f", entry.startTime or 0)
        current[key] = true
        if not watchedEffects[key] then
            watchedEffects[key] = true
            local duration = try(function() return entry.effect.Spec.Duration end)
            Log.Debug(string.format("effect on: %s (duration %s, at %.2f)", entry.className or "?", tostring(duration), worldTime))
        end
    end
    for key in pairs(watchedEffects) do
        if not current[key] then
            watchedEffects[key] = nil
            Log.Debug(string.format("effect off: %s (at %.2f)", key:match("^[^@]+"), worldTime))
        end
    end
end

function Buffs.Tick()
    if State.settings.infiniteBuffs then registerStackHook() end
    Log.Guarded("infinite buffs", extendBuffs)
    if Log.IsDebugEnabled() then Log.Guarded("effect log", logEffectChanges) end
end

Unreal.OnWorldReset(function()
    buffs.originalDurations, buffs.peakStacks, buffs.stackHandles = {}, {}, {}
    watchedEffects = {}
end)

return Buffs
