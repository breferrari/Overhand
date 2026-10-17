-- games/valormortis/features/resources.lua
-- Infinite Ammo (optionally still reloading), Healing Flasks and Consumables, No Item Cooldowns,
-- Keep Catalysts On Death and Refill Everything.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Game = require("game.game")
local App = require("core.app")
local Health = require("game.features.health")
local Hud = require("game.features.hud")
local Gas = require("gas.gas")

local Resources = {}

local try, isValid = Unreal.Try, Unreal.IsValid

-- ---------------------------------------------------------------------------
-- Flasks and ammo
-- ---------------------------------------------------------------------------

function Resources.FillFlasks()
    local flasksSet = Game.AttributeSet("Flasks")
    if flasksSet then Gas.FillAttribute(flasksSet, "HealingFlasks", "HealingFlasksMax") end
end

local AMMO_TYPES = { "Pistol", "Blunderbuss", "Rifle" }

-- reserveOnly: keep the reserve full but leave the clip to the game (you still reload).
function Resources.FillAmmo(reserveOnly)
    local rangedSet = Game.AttributeSet("Ranged")
    if not rangedSet then return end
    local changed = false
    for _, ammoType in ipairs(AMMO_TYPES) do
        if Gas.FillAttribute(rangedSet, ammoType .. "Ammo", "Max" .. ammoType .. "Ammo") then changed = true end
        if not reserveOnly and Gas.FillAttribute(rangedSet, ammoType .. "AmmoInClip", "Max" .. ammoType .. "AmmoInClip") then
            changed = true
        end
    end
    -- Values written directly do not reach the HUD by themselves.
    if changed then
        Hud.RefreshWeapons()
        Hud.RefreshTokens()
    end
end

-- ---------------------------------------------------------------------------
-- Cooldowns and catalysts
-- ---------------------------------------------------------------------------

local nextCooldownResetAt = 0

local function resetItemCooldowns()
    if os.clock() < nextCooldownResetAt then return end
    nextCooldownResetAt = os.clock() + 0.25
    local inventory, player = Game.Inventory(), Game.Player()
    if inventory and player then
        try(function() inventory:TrySetAllConsumableInventoryItemsCooldown(player, 0.0) end)
    end
end

-- Keep Catalysts On Death. Once William is back on his feet, his deathmark is picked up for him
-- right away. Some deaths leave no deathmark (poison, some boss fights) and still take the
-- catalysts: for those, the catalysts he had just before dying are given back. Catalysts are the Exp
-- set's ExpPoints; giving goes through the game's own AddExperiencePointsToPlayer.
local DEATHMARK_GRACE = 3         -- seconds after getting up for the game to place its deathmark
local GIVE_BACK_WITHIN = 60       -- a longer death (menus, loading) is not ours to judge
local catalysts = {
    deathmarkRetryAt = {},        -- deathmark address -> clock time of the next pickup attempt
    lastCount = nil,              -- catalysts while alive, read every tick
    beforeDeath = nil,            -- catalysts when he died
    diedAt = nil,
    checkAt = nil,                -- after getting up: when to compare
    sawDeathmark = false,         -- this death left a deathmark (picking it up gives them back)
}

local function catalystCount()
    local expSet = Game.AttributeSet("Exp")
    return expSet and Gas.GetAttribute(expSet, "ExpPoints")
end

local function pickUpDeathmark(player)
    local deathmark = try(function() return player.DeathmarkRef end)
    if not isValid(deathmark) then return end
    catalysts.sawDeathmark = true
    local address = Unreal.AddressOf(deathmark)
    if os.clock() < (catalysts.deathmarkRetryAt[address] or 0) then return end
    catalysts.deathmarkRetryAt[address] = os.clock() + 3
    if try(function() deathmark:ForcePickup() return true end) then
        Log.Info("deathmark picked up (catalysts kept)")
    end
end

local function giveBackLostCatalysts()
    local now, count = catalystCount(), catalysts.beforeDeath
    catalysts.beforeDeath, catalysts.checkAt = nil, nil
    if catalysts.sawDeathmark or not (now and count) or now >= count - 0.5 then return end
    local missing = math.floor(count - now + 0.5)
    local combatUtils = Game.CombatUtils()
    local given = isValid(combatUtils) and try(function() combatUtils:AddExperiencePointsToPlayer(missing) return true end)
    Log.Info("keep catalysts: " .. (given and "gave back " or "could not give back ") .. missing .. " catalysts lost on a death without a deathmark")
end

local function keepCatalysts()
    local player = Game.Player()
    if not player then return end
    local alive = Game.IsPlayerAlive() and try(function() return player.bRespawning end) ~= true
    if not alive then
        if not catalysts.diedAt then
            catalysts.diedAt, catalysts.beforeDeath, catalysts.sawDeathmark = os.clock(), catalysts.lastCount, false
        end
        return
    end
    if catalysts.diedAt then
        if os.clock() - catalysts.diedAt < GIVE_BACK_WITHIN then catalysts.checkAt = os.clock() + DEATHMARK_GRACE end
        catalysts.diedAt = nil
    end
    pickUpDeathmark(player)
    if catalysts.checkAt and os.clock() >= catalysts.checkAt then giveBackLostCatalysts() end
    if not catalysts.checkAt then catalysts.lastCount = catalystCount() end
end

local function forgetCatalysts()
    catalysts.lastCount, catalysts.beforeDeath, catalysts.diedAt, catalysts.checkAt = nil, nil, nil, nil
end

-- ---------------------------------------------------------------------------
-- Consumables: the game's item database lists every consumable (grenades, syringes, potions, ...).
-- We watch how many William carries and give back whatever was used up. (Hooks on the "use item"
-- functions do not work: the game calls them from C++.) The same poll keeps the most he carried
-- of each this session, which Refill Everything puts back.
-- ---------------------------------------------------------------------------

local consumables = {
    tags = nil,            -- every consumable item tag, from the item database (built once)
    lastCounts = {},       -- tag -> count at the last poll (while Infinite Consumables is on)
    unrefillable = {},     -- tags whose give-back did not stick
    verifyNextPoll = {},   -- tags given back on the last poll
    peakCounts = {},       -- tag -> the most carried this session
    nextPollAt = 0,
}

function Resources.ConsumableTags()
    if consumables.tags then return consumables.tags end
    local tags = {}
    Game.ForEachDatabaseItem("ConsumableItemsMap", function(tagName) tags[#tags + 1] = tagName end)
    if #tags == 0 then return nil end
    table.sort(tags)
    consumables.tags = tags
    Log.Info("consumables: " .. #tags .. " items")
    return tags
end

-- After items were added by us: count from what William carries now.
function Resources.StartNewCount(itemTag)
    consumables.lastCounts = {}
    if itemTag then consumables.peakCounts[itemTag] = nil end
end

local function giveBack(tag, count)
    local lastCount = consumables.lastCounts[tag]
    if consumables.verifyNextPoll[tag] then
        -- we gave this one back on the last poll: did it arrive?
        consumables.verifyNextPoll[tag] = nil
        if lastCount and count < lastCount then
            consumables.unrefillable[tag] = true
            Log.Info("consumable " .. tag .. ": give back did not stick (" .. count .. "/" .. lastCount .. "), skipping it")
        end
        consumables.lastCounts[tag] = count
    elseif lastCount and count < lastCount and not consumables.unrefillable[tag] then
        local used = lastCount - count
        if Game.AddItem(tag, used) then
            Log.Debug("consumable " .. tag .. " +" .. used .. " (given back)")
            consumables.verifyNextPoll[tag] = true
        else
            consumables.unrefillable[tag] = true
            Log.Info("consumable " .. tag .. ": AddInventoryItem failed, skipping it")
        end
    elseif not lastCount or count > lastCount then
        consumables.lastCounts[tag] = count
    end
end

-- Every 0.25 s while Infinite Consumables is on, every 1 s otherwise (peak counts only).
local function pollConsumables()
    if os.clock() < consumables.nextPollAt then return end
    local infinite = App.settings.infiniteConsumables == true
    consumables.nextPollAt = os.clock() + (infinite and 0.25 or 1)
    if not infinite then consumables.lastCounts = {} end
    local tags = Resources.ConsumableTags()
    if not tags then return end
    for _, tag in ipairs(tags) do
        local count = Game.ItemCount(tag)
        if count then
            if count > (consumables.peakCounts[tag] or 0) then consumables.peakCounts[tag] = count end
            if infinite then giveBack(tag, count) end
        end
    end
end

local function refillConsumables()
    local tags = Resources.ConsumableTags()
    if not tags then return 0 end
    local refilled = 0
    for _, tag in ipairs(tags) do
        if not tag:find("Catalyst", 1, true) then
            local count, peak = Game.ItemCount(tag), consumables.peakCounts[tag]
            if count and peak and count < peak and Game.AddItem(tag, peak - count) then
                refilled = refilled + 1
            end
        end
    end
    Resources.StartNewCount()
    return refilled
end

-- ---------------------------------------------------------------------------
-- Refill Everything: the game's own restore effects (like resting at a lantern), so the HUD and
-- everything else follows. Ammo has no lantern effect, it is filled directly.
-- ---------------------------------------------------------------------------

local EFFECTS_FOLDER = "/Game/Minotaur/Gameplay/GAS/GameplayEffects/"
local REFILL_EFFECTS = {
    EFFECTS_FOLDER .. "GE_FullHeal.GE_FullHeal_C",
    EFFECTS_FOLDER .. "GE_FullStamina.GE_FullStamina_C",
    EFFECTS_FOLDER .. "GE_HealingFlasksRestore.GE_HealingFlasksRestore_C",
    EFFECTS_FOLDER .. "GE_RestoreNephtoglobinAtLantern.GE_RestoreNephtoglobinAtLantern_C",
}

function Resources.RefillEverything()
    local applied = 0
    for _, effectPath in ipairs(REFILL_EFFECTS) do
        if Gas.ApplyEffect(effectPath) then applied = applied + 1 end
    end
    -- Also fill the attributes directly, in case an effect does not apply in this state.
    Health.FillHealth()
    Health.FillStamina()
    Health.FillNephtoglobin()
    Resources.FillFlasks()
    Resources.FillAmmo()
    local refilledItems = refillConsumables()
    Log.Info("refill: " .. applied .. "/" .. #REFILL_EFFECTS .. " restore effects, " .. refilledItems .. " consumables refilled")
    App.status = "Health, stamina, nephtoglobin, flasks, ammo and items refilled"
end

-- ---------------------------------------------------------------------------

function Resources.Tick()
    local settings = App.settings
    if settings.infiniteFlasks then Resources.FillFlasks() end
    if settings.infiniteAmmo then Resources.FillAmmo(settings.ammoReload) end
    if settings.noItemCooldowns then resetItemCooldowns() end
    if settings.keepCatalysts then Log.Guarded("keep catalysts", keepCatalysts) else forgetCatalysts() end
    pollConsumables()
end

Unreal.OnWorldReset(function()
    catalysts.deathmarkRetryAt = {}
    forgetCatalysts()
    -- peak counts too: after loading another save, Refill must not top it up to this one's counts
    consumables.lastCounts, consumables.unrefillable, consumables.verifyNextPoll, consumables.peakCounts = {}, {}, {}, {}
end)

return Resources
