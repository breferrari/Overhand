-- ValorianSheet / features/give.lua
-- One-shot gifts: catalysts, upgrade materials, consumables, a chosen item, weapons, abilities, gems.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Resources = require("features.resources")
local DevActions = require("features.dev_actions")

local Give = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local function tagNamesOf(tagContainer)
    local names = {}
    try(function()
        tagContainer.GameplayTags:ForEach(function(_, element)
            local name = try(function() return element:get().TagName:ToString() end)
            if name and name ~= "None" then names[#names + 1] = name end
        end)
    end)
    return names
end

function Give.Catalysts(amount)
    local combatUtils = Game.CombatUtils()
    if not isValid(combatUtils) then return end
    if try(function() combatUtils:AddExperiencePointsToPlayer(amount) return true end) then
        Log.Info("added " .. amount .. " catalysts")
        State.status = "Added " .. amount .. " catalysts"
    else
        State.status = "Could not add catalysts"
    end
end

-- The upgrade materials the developers' cheat manager lists, `amount` of each.
function Give.UpgradeMaterials(amount)
    local cheatManager = Game.CheatManager()
    if not cheatManager then
        State.status = "Cheat manager not found"
        return
    end
    local given = 0
    for _, tag in ipairs(tagNamesOf(try(function() return cheatManager.UpgradeMaterials end))) do
        if Game.AddItem(tag, amount) then given = given + 1 end
    end
    State.status = given > 0 and ("Added " .. amount .. " of " .. given .. " materials") or "No materials found"
end

-- `amount` of every consumable; catalysts have their own buttons.
function Give.EveryConsumable(amount)
    local tags = Resources.ConsumableTags()
    if not tags then
        State.status = "Item database not found"
        return
    end
    local given = 0
    for _, tag in ipairs(tags) do
        if not tag:find("Catalyst", 1, true) and Game.AddItem(tag, amount) then given = given + 1 end
    end
    Resources.StartNewCount()
    Log.Info("added " .. amount .. " of " .. given .. " consumables")
    State.status = "Added " .. amount .. " of " .. given .. " consumables"
end

-- ---------------------------------------------------------------------------
-- Give Item: one item from the game's item database, any amount. Story items (NarrativeItemsMap)
-- are left out on purpose: they can break quests.
-- ---------------------------------------------------------------------------

Give.CATEGORIES = {
    { label = "Consumables", databaseMap = "ConsumableItemsMap" },
    { label = "Materials", databaseMap = "MaterialItemsMap" },
    { label = "Instant", databaseMap = "InstantItemsMap" },
}

local catalog = nil   -- category label -> sorted list of { label, tag }

-- "Items.Consumable.Grenade.Oil" -> "Grenade Oil"
local GENERIC_TAG_PARTS = {
    Items = true, Item = true, Inventory = true, Consumable = true, Consumables = true,
    Material = true, Materials = true, Instant = true, Upgrade = true, Upgrades = true,
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

local function addEntry(list, seenTags, tag, itemProperties)
    if not tag or tag == "None" or seenTags[tag] then return end
    seenTags[tag] = true
    list[#list + 1] = { label = (itemProperties and inGameName(itemProperties)) or readableTag(tag), tag = tag }
end

-- Built once a save is loaded (nil before).
function Give.Catalog()
    if catalog then return catalog end
    local inventory = Game.Inventory()
    local database = inventory and try(function() return inventory.InventoryDatabaseAsset end)
    if not isValid(database) then return nil end
    local result, total = {}, 0
    for _, category in ipairs(Give.CATEGORIES) do
        local list, seenTags = {}, {}
        try(function()
            database[category.databaseMap]:ForEach(function(categoryKey, categoryItems)
                local before = #list
                try(function()
                    categoryItems:get().ItemMap:ForEach(function(itemKey, itemProperties)
                        addEntry(list, seenTags, try(function() return itemKey:get().TagName:ToString() end),
                            try(function() return itemProperties:get() end))
                    end)
                end)
                if #list == before then
                    addEntry(list, seenTags, try(function() return categoryKey:get().TagName:ToString() end), nil)
                end
            end)
        end)
        if category.label == "Materials" then
            -- the materials the cheat manager lists, in case the database misses some
            local cheatManager = Game.CheatManager()
            local materials = cheatManager and try(function() return cheatManager.UpgradeMaterials end)
            for _, tag in ipairs(materials and tagNamesOf(materials) or {}) do addEntry(list, seenTags, tag, nil) end
        end
        table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
        result[category.label] = list
        total = total + #list
    end
    if total == 0 then return nil end
    catalog = result
    Log.Info(string.format("give item: %d consumables, %d materials, %d instant items",
        #result.Consumables, #result.Materials, #result.Instant))
    return catalog
end

function Give.Item(entry, amount)
    if not entry then
        State.status = "Pick an item first"
        return
    end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return end
    local countBefore = Game.ItemCount(entry.tag)
    local ok = Game.AddItem(entry.tag, amount)
    Resources.StartNewCount(entry.tag)
    Log.Info(string.format("give item %s x%d: %s (count %s -> %s)", entry.tag, amount, ok and "ok" or "failed",
        tostring(countBefore), tostring(Game.ItemCount(entry.tag))))
    State.status = ok and ("Added " .. amount .. "x " .. entry.label) or ("Could not add " .. entry.label)
end

-- ---------------------------------------------------------------------------
-- Weapons, abilities, gems
-- The weapons in the cheat manager that are really in the game. "WeaponGrenade" (Crystal Grenade) is
-- an unfinished leftover: it does nothing and takes the Claymore's place on the weapon wheel, so it
-- is left out and removed from saves that got it from older cheat menu versions.
-- ---------------------------------------------------------------------------

local WEAPON_FIELDS = { "PlayerSaber", "WeaponPistol", "WeaponFlamethrower", "WeaponRifle",
    "WeaponClaymore", "WeaponBlunderbuss", "WeaponShield", "WeaponRapier", "WeaponStasis" }
local BROKEN_WEAPON_FIELDS = { "WeaponGrenade" }
local WEAPON_LISTS = { "RangedWeapons", "MeleeWeapons", "TwoHandedWeapons" }

function Give.AllWeapons()
    local player, cheatManager = Game.Player(), Game.CheatManager()
    if not cheatManager then
        State.status = "Cheat manager not found"
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
    State.status = "Unlocked " .. unlocked .. " weapons"
end

-- Removes the broken leftover weapons from the player's weapon lists. A list is only rebuilt after a
-- test append proved this UE4SS version can grow arrays, so a list is never left emptied.
-- Returns true once the check could run (player and cheat manager present).
function Give.RemoveBrokenWeapons()
    local player, cheatManager = Game.Player(), Game.CheatManager()
    if not isValid(player) or not cheatManager then return false end
    local brokenByAddress = {}
    for _, field in ipairs(BROKEN_WEAPON_FIELDS) do
        local weapon = try(function() return cheatManager[field] end)
        if isValid(weapon) then brokenByAddress[Unreal.AddressOf(weapon)] = field end
    end
    if next(brokenByAddress) == nil then return true end

    local cleanedLists = 0
    for _, listName in ipairs(WEAPON_LISTS) do
        Log.Guarded("clean " .. listName, function()
            local weapons = player[listName]
            local kept, foundBroken = {}, false
            weapons:ForEach(function(_, element)
                local weapon = element:get()
                if isValid(weapon) and brokenByAddress[Unreal.AddressOf(weapon)] then
                    foundBroken = true
                else
                    kept[#kept + 1] = weapon
                end
            end)
            if not foundBroken then return end
            local count = weapons:GetArrayNum()
            local canGrow = try(function()
                weapons[count + 1] = kept[1] or weapons[1]
                return weapons:GetArrayNum() == count + 1
            end)
            if not canGrow then
                Log.Info("could not remove the Crystal Grenade from " .. listName .. " (array cannot grow)")
                return
            end
            weapons:Empty()
            for index, weapon in ipairs(kept) do weapons[index] = weapon end
            Log.Info(listName .. ": removed the Crystal Grenade, " .. #kept .. " weapons kept")
            cleanedLists = cleanedLists + 1
        end)
    end

    -- never leave the broken weapon in his hand
    local equipped = try(function() return player.CurrentRangedWeapon end)
    if isValid(equipped) and brokenByAddress[Unreal.AddressOf(equipped)] then
        local pistol = try(function() return cheatManager.WeaponPistol end)
        if isValid(pistol) then try(function() player:EquipRangedWeapon(pistol, false, true, true) end) end
    end
    if cleanedLists > 0 then
        local notifier = Game.AttributesNotifier()
        if notifier then try(function() notifier:RequestWeaponRefresh() end) end
        State.status = "Removed the broken Crystal Grenade from your weapon wheel"
    end
    return true
end

function Give.AllAbilities()
    DevActions.RunAll({ "Unlock Grappling", "Unlock Stasis", "Unlock Neptho Interactions", "Unlock Leveling Up" }, "Abilities")
end

function Give.AllGems()
    DevActions.RunAll({ "Unlock all gems" }, "Gems")
end

return Give
