-- ValorianSheet / features/resources.lua
-- Infinite Ammo, Healing Flasks and Consumables, No Item Cooldowns, Keep Catalysts On Death and
-- Refill Everything.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Health = require("features.health")

local Resources = {}

local try, isValid = Unreal.Try, Unreal.IsValid
local clock = State.clock

-- ---------------------------------------------------------------------------
-- Flasks and ammo
-- ---------------------------------------------------------------------------

function Resources.FillFlasks()
    local flasksSet = Game.AttributeSet("Flasks")
    if flasksSet then Game.FillAttribute(flasksSet, "HealingFlasks", "HealingFlasksMax") end
end

local AMMO_TYPES = { "Pistol", "Blunderbuss", "Rifle" }

function Resources.FillAmmo()
    local rangedSet = Game.AttributeSet("Ranged")
    if not rangedSet then return end
    local changed = false
    for _, ammoType in ipairs(AMMO_TYPES) do
        if Game.FillAttribute(rangedSet, ammoType .. "Ammo", "Max" .. ammoType .. "Ammo") then changed = true end
        if Game.FillAttribute(rangedSet, ammoType .. "AmmoInClip", "Max" .. ammoType .. "AmmoInClip") then changed = true end
    end
    -- Values written directly do not reach the HUD by themselves: tell the ammo display.
    if changed then
        local notifier = Game.AttributesNotifier()
        if notifier then
            try(function() notifier:RequestWeaponRefresh() end)
            try(function() notifier:RequestTokenRefresh() end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Cooldowns and catalysts
-- ---------------------------------------------------------------------------

local nextCooldownResetAt = 0

local function resetItemCooldowns()
    if clock() < nextCooldownResetAt then return end
    nextCooldownResetAt = clock() + 0.25
    local inventory, player = Game.Inventory(), Game.Player()
    if inventory and player then
        try(function() inventory:TrySetAllConsumableInventoryItemsCooldown(player, 0.0) end)
    end
end

-- Once William is back on his feet, pick his deathmark up for him right away.
local deathmarkRetryAt = {}   -- deathmark address -> clock time of the next pickup attempt

local function pickUpDeathmark()
    local player = Game.Player()
    if not player or not Game.IsPlayerAlive() then return end
    if try(function() return player.bRespawning end) == true then return end
    local deathmark = try(function() return player.DeathmarkRef end)
    if not isValid(deathmark) then return end
    local address = Unreal.AddressOf(deathmark)
    if deathmarkRetryAt[address] and clock() < deathmarkRetryAt[address] then return end
    deathmarkRetryAt[address] = clock() + 3
    if try(function() deathmark:ForcePickup() return true end) then
        Log.Info("deathmark picked up (catalysts kept)")
    end
end

-- ---------------------------------------------------------------------------
-- Consumables: the game's item database lists every consumable (grenades, syringes, potions, ...).
-- We watch how many William carries and give back whatever was used up. (Hooks on the "use item"
-- functions do not work: the game calls them from C++.)
-- ---------------------------------------------------------------------------

local consumables = {
    tags = nil,            -- every consumable item tag, from the item database
    lastCounts = {},       -- tag -> count at the last poll
    unrefillable = {},     -- tags whose give-back did not stick
    verifyNextPoll = {},   -- tags given back on the last poll
    peakCounts = {},       -- tag -> the most carried this session (for Refill Everything)
    nextPollAt = 0,
    nextPeakAt = 0,
}

-- The database maps a category (Items.Consumable.Grenade) to its real items
-- (Items.Consumable.Grenade.Regular, ...Oil). We want the real items.
function Resources.ConsumableTags()
    if consumables.tags then return consumables.tags end
    local inventory = Game.Inventory()
    local database = inventory and try(function() return inventory.InventoryDatabaseAsset end)
    if not isValid(database) then return nil end
    local tags, categoryCount = {}, 0
    try(function()
        database.ConsumableItemsMap:ForEach(function(categoryKey, category)
            categoryCount = categoryCount + 1
            local before = #tags
            try(function()
                category:get().ItemMap:ForEach(function(itemKey)
                    local tag = try(function() return itemKey:get().TagName:ToString() end)
                    if tag and tag ~= "None" then tags[#tags + 1] = tag end
                end)
            end)
            if #tags == before then
                -- a category without sub items: use the category tag itself
                local tag = try(function() return categoryKey:get().TagName:ToString() end)
                if tag and tag ~= "None" then tags[#tags + 1] = tag end
            end
        end)
    end)
    if #tags == 0 then return nil end
    table.sort(tags)
    consumables.tags = tags
    Log.Info("consumables: " .. #tags .. " items in " .. categoryCount .. " categories")
    return tags
end

-- After items were added by us: count from what William carries now.
function Resources.StartNewCount(itemTag)
    consumables.lastCounts = {}
    if itemTag then consumables.peakCounts[itemTag] = nil end
end

local function giveBackUsedConsumables()
    if clock() < consumables.nextPollAt then return end
    consumables.nextPollAt = clock() + 0.25
    local tags = Resources.ConsumableTags()
    if not tags then return end
    for _, tag in ipairs(tags) do
        local count = Game.ItemCount(tag)
        if count then
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
    end
end

-- Once a second: remember the most William carried of every consumable.
local function trackPeakCounts()
    if clock() < consumables.nextPeakAt then return end
    consumables.nextPeakAt = clock() + 1
    local tags = Resources.ConsumableTags()
    if not tags then return end
    for _, tag in ipairs(tags) do
        local count = Game.ItemCount(tag)
        if count and count > (consumables.peakCounts[tag] or 0) then consumables.peakCounts[tag] = count end
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
        if Game.ApplyEffect(effectPath) then applied = applied + 1 end
    end
    -- Also fill the attributes directly, in case an effect does not apply in this state.
    Health.FillHealth()
    Health.FillStamina()
    Health.FillNephtoglobin()
    Resources.FillFlasks()
    Resources.FillAmmo()
    local refilledItems = refillConsumables()
    Log.Info("refill: " .. applied .. "/" .. #REFILL_EFFECTS .. " restore effects, " .. refilledItems .. " consumables refilled")
    State.status = "Health, stamina, nephtoglobin, flasks, ammo and items refilled"
end

-- ---------------------------------------------------------------------------

function Resources.Tick()
    local settings = State.settings
    if settings.infiniteFlasks then Resources.FillFlasks() end
    if settings.infiniteAmmo then Resources.FillAmmo() end
    if settings.noItemCooldowns then resetItemCooldowns() end
    if settings.keepCatalysts then pickUpDeathmark() end
    if settings.infiniteConsumables then
        giveBackUsedConsumables()
    else
        consumables.lastCounts = {}
    end
    trackPeakCounts()
end

function Resources.Reset()
    deathmarkRetryAt = {}
    consumables.lastCounts, consumables.unrefillable, consumables.verifyNextPoll = {}, {}, {}
end

return Resources
