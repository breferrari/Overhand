-- games/valormortis/features/give.lua
-- One-shot gifts: catalysts, upgrade materials, consumables, a chosen item, weapons, abilities, gems.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Game = require("game.game")
local App = require("core.app")
local Resources = require("game.features.resources")
local DevActions = require("game.features.dev_actions")
local Gas = require("gas.gas")

local Give = {}

local try, isValid = Unreal.Try, Unreal.IsValid

-- The upgrade materials the developers' cheat manager lists.
local function upgradeMaterialTags()
    local cheatManager = Game.CheatManager()
    local materials = cheatManager and try(function() return cheatManager.UpgradeMaterials end)
    return materials and Gas.TagNamesIn(materials) or {}
end

function Give.Catalysts(amount)
    local combatUtils = Game.CombatUtils()
    if isValid(combatUtils) and try(function() combatUtils:AddExperiencePointsToPlayer(amount) return true end) then
        Log.Info("added " .. amount .. " catalysts")
        App.status = "Added " .. amount .. " catalysts"
    else
        App.status = "Could not add catalysts"
    end
end

function Give.UpgradeMaterials(amount)
    local given = 0
    for _, tag in ipairs(upgradeMaterialTags()) do
        if Game.AddItem(tag, amount) then given = given + 1 end
    end
    App.status = given > 0 and ("Added " .. amount .. " of " .. given .. " materials") or "No materials found"
end

-- `amount` of every consumable; catalysts have their own buttons.
function Give.EveryConsumable(amount)
    local tags = Resources.ConsumableTags()
    if not tags then
        App.status = "Item database not found"
        return
    end
    local given = 0
    for _, tag in ipairs(tags) do
        if not tag:find("Catalyst", 1, true) and Game.AddItem(tag, amount) then given = given + 1 end
    end
    Resources.StartNewCount()
    Log.Info("added " .. amount .. " of " .. given .. " consumables")
    App.status = "Added " .. amount .. " of " .. given .. " consumables"
end

-- ---------------------------------------------------------------------------
-- Give Item: one item from the game's item database, any amount. Quest items (NarrativeItemsMap,
-- plus the items quests hand out or take back) are their own category: they help with a stuck
-- quest, but given too early they can skip parts of one.
-- ---------------------------------------------------------------------------

Give.CATEGORIES = {
    { label = "Consumables", databaseMap = "ConsumableItemsMap" },
    { label = "Materials", databaseMap = "MaterialItemsMap" },
    { label = "Instant", databaseMap = "InstantItemsMap" },
    { label = "Quest Items", databaseMap = "NarrativeItemsMap", questActions = { "QuestAction_GrantItems", "QuestAction_RemoveItems" } },
}

local catalog = nil   -- category label -> sorted list of { label, tag }

-- "Items.Consumable.Grenade.Oil" -> "Grenade Oil"
local GENERIC_TAG_PARTS = {
    Items = true, Item = true, Inventory = true, Consumable = true, Consumables = true,
    Material = true, Materials = true, Instant = true, Upgrade = true, Upgrades = true, Narrative = true, Quest = true,
}

local function readableTag(tag)
    local parts = {}
    for part in tag:gmatch("[^%.]+") do
        if not GENERIC_TAG_PARTS[part] then parts[#parts + 1] = part end
    end
    local name = #parts >= 2 and (parts[#parts - 1] .. " " .. parts[#parts]) or (parts[1] or tag)
    return (name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"))
end

-- The item's in-game name from its UI data, if the game has one.
local function inGameName(itemProperties)
    local name = nil
    try(function()
        itemProperties.UIData.TextStats:ForEach(function(keyParam, valueParam)
            if name then return end
            local key = try(function() return keyParam:get().TagName:ToString() end) or ""
            local text = try(function() return valueParam:get():ToString() end)
            if text and text ~= "" and (key:find("Name") or key:find("Title")) then name = text end
        end)
    end)
    return name
end

-- Built once a save is loaded (nil before).
function Give.Catalog()
    if catalog then return catalog end
    local result, total = {}, 0
    for _, category in ipairs(Give.CATEGORIES) do
        local list, seenTags = {}, {}
        local function add(tag, itemProperties)
            if seenTags[tag] then return end
            seenTags[tag] = true
            list[#list + 1] = { label = (itemProperties and inGameName(itemProperties)) or readableTag(tag), tag = tag }
        end
        Game.ForEachDatabaseItem(category.databaseMap, add)
        if category.label == "Materials" then
            -- the materials the cheat manager lists, in case the database misses some
            for _, tag in ipairs(upgradeMaterialTags()) do add(tag, nil) end
        end
        -- the items the quests themselves grant or take (one search per class, when the catalog is built)
        for _, className in ipairs(category.questActions or {}) do
            for _, action in ipairs(Unreal.FindAllLive(className)) do
                for _, tag in ipairs(Gas.TagNamesIn(try(function() return action.ItemTags end))) do add(tag, nil) end
            end
        end
        table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
        result[category.label] = list
        total = total + #list
    end
    if total == 0 then return nil end
    catalog = result
    local counts = {}
    for _, category in ipairs(Give.CATEGORIES) do counts[#counts + 1] = #result[category.label] .. " " .. category.label:lower() end
    Log.Info("give item: " .. table.concat(counts, ", "))
    return catalog
end

-- A give is checked again a moment later and the status says what really changed: past what
-- William can carry, the game puts the rest in his storage (confirmed in game), so the count he
-- carries can stay the same.
local VERIFY_AFTER = 1
local pendingGive = nil   -- { entry, amount, countBefore, checkAt }

local function reportGive(give)
    local countAfter = Game.ItemCount(give.entry.tag)
    local before, label = give.countBefore, give.entry.label
    Log.Info(string.format("give item %s x%d: count %s -> %s", give.entry.tag, give.amount, tostring(before), tostring(countAfter)))
    if not (before and countAfter) then
        App.status = "Gave " .. give.amount .. "x " .. label
    elseif countAfter > before then
        App.status = string.format("%s: %d -> %d", label, before, countAfter)
    else
        -- past what William can carry, the game puts the rest in his storage
        App.status = string.format("%s: you carry the most (%d); the rest went to storage", label, countAfter)
    end
end

function Give.Item(entry, amount)
    if not entry then
        App.status = "Pick an item first"
        return
    end
    local countBefore = Game.ItemCount(entry.tag)
    if not Game.AddItem(entry.tag, amount) then
        App.status = "Could not add " .. entry.label
        Log.Info("give item " .. entry.tag .. " x" .. amount .. ": the call failed")
        return
    end
    Resources.StartNewCount(entry.tag)
    pendingGive = { entry = entry, amount = amount, countBefore = countBefore, checkAt = os.clock() + VERIFY_AFTER }
    App.status = "Giving " .. amount .. "x " .. entry.label .. "..."
end

function Give.Tick()
    if pendingGive and os.clock() >= pendingGive.checkAt then
        local give = pendingGive
        pendingGive = nil
        reportGive(give)
    end
end

-- ---------------------------------------------------------------------------
-- Weapons, abilities, gems
-- The weapons in the cheat manager that are really in the game. "WeaponGrenade" (Crystal Grenade) is
-- an unfinished leftover: it does nothing and takes the Claymore's place on the weapon wheel, so it
-- is left out.
-- ---------------------------------------------------------------------------

local WEAPON_FIELDS = { "PlayerSaber", "WeaponPistol", "WeaponFlamethrower", "WeaponRifle",
    "WeaponClaymore", "WeaponBlunderbuss", "WeaponShield", "WeaponRapier", "WeaponStasis" }

function Give.AllWeapons()
    local player, cheatManager = Game.Player(), Game.CheatManager()
    if not cheatManager then
        App.status = "Cheat manager not found"
        return
    end
    local unlocked = 0
    for _, field in ipairs(WEAPON_FIELDS) do
        local weapon = try(function() return cheatManager[field] end)
        if isValid(weapon) and try(function() player:AcquireWeapon(weapon, true) return true end) then
            unlocked = unlocked + 1
        else
            Log.Info("weapon " .. field .. ": could not be acquired")
        end
    end
    App.status = "Unlocked " .. unlocked .. " weapons"
end

function Give.AllAbilities()
    DevActions.RunAll({ "Unlock Grappling", "Unlock Stasis", "Unlock Neptho Interactions", "Unlock Leveling Up" }, "Abilities")
end

function Give.AllGems()
    DevActions.RunAll({ "Unlock all gems" }, "Gems")
end

return Give
