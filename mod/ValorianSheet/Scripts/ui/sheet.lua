-- ValorianSheet / ui/sheet.lua
-- What the menu shows: six tabs, each row bound to a setting or an action of a feature module.
-- Actions need a loaded save unless marked { anytime = true }.

local Game = require("game")
local Cheats = require("cheats")
local Menu = require("ui.menu")
local Combat = require("features.combat")
local Resources = require("features.resources")
local Give = require("features.give")
local Teleport = require("features.teleport")
local BugReport = require("features.bug_report")

local Sheet = {}

-- { 1, 1.5, 2 } -> "1x (vanilla)", "1.5x", "2x"
local function factorOptions(values, vanillaLabel)
    local options = {}
    for _, value in ipairs(values) do
        local label = value .. "x"
        if value == 1 then label = vanillaLabel or "1x (vanilla)" end
        if value < 1 then label = label .. " (harder)" end
        options[#options + 1] = { label = label, value = value }
    end
    return options
end

-- { 1, 0.5, 0 } -> "100% (vanilla)", "50%", "0%"
local function percentOptions(values, lastLabel)
    local options = {}
    for index, value in ipairs(values) do
        local label = math.floor(value * 100 + 0.5) .. "%"
        if value == 1 then label = label .. " (vanilla)" end
        if index == #values and lastLabel then label = label .. " " .. lastLabel end
        options[#options + 1] = { label = label, value = value }
    end
    return options
end

-- { { "label", value }, ... } -> options
local function labeled(entries)
    local options = {}
    for _, entry in ipairs(entries) do options[#options + 1] = { label = entry[1], value = entry[2] } end
    return options
end

-- ---------------------------------------------------------------------------

local function survivalTab()
    return {
        Menu.Toggle("God Mode", "godMode"),
        Menu.Toggle("Infinite Stamina", "infiniteStamina"),
        Menu.Toggle("  ...only out of combat", "staminaOnlyOutOfCombat"),
        Menu.Toggle("Infinite Nephtoglobin", "infiniteNephtoglobin"),
        Menu.Choice("Fall Damage", percentOptions({ 1, 0.75, 0.5, 0.25, 0 }, "(none)"), "fallDamage"),
        Menu.Choice("Damage Taken", percentOptions({ 1, 0.75, 0.5, 0.25, 0.1 }), "damageTaken"),
        Menu.Choice("Max Health", factorOptions({ 1, 1.5, 2, 3, 5 }), "maxHealthFactor"),
        Menu.Section("Health Regeneration"),
        Menu.Choice("Regeneration", labeled({ { "Off (vanilla)", 0 }, { "1 HP / s", 1 }, { "2 HP / s", 2 },
            { "5 HP / s", 5 }, { "10 HP / s", 10 }, { "20 HP / s", 20 }, { "50 HP / s", 50 } }), "regenPerSecond"),
        Menu.Choice("Starts after a hit", labeled({ { "right away", 0 }, { "2 s", 2 }, { "5 s", 5 }, { "10 s", 10 } }), "regenDelay"),
        Menu.Choice("Heals up to", labeled({ { "25%", 25 }, { "50%", 50 }, { "75%", 75 }, { "100%", 100 } }), "regenMaxPercent"),
        Menu.Toggle("Only out of combat", "regenOnlyOutOfCombat"),
    }
end

local function movementTab()
    local slot = Menu.Value(1)
    local slotCache = { map = nil, options = nil }
    local function slotOptions()
        local map = Game.MapName()
        if slotCache.map ~= map or not slotCache.options then
            slotCache.map, slotCache.options = map, {}
            for index = 1, Teleport.SLOT_COUNT do
                slotCache.options[index] = { label = index .. ": " .. Teleport.Describe(index, map), value = index }
            end
        end
        return slotCache.options
    end
    return {
        Menu.Toggle("NoClip (Space up, Ctrl down)", "noClip"),
        Menu.Choice("Movement Speed", factorOptions({ 1, 1.25, 1.5, 2, 3, 5 }), "movementSpeed"),
        Menu.Choice("Jump Height", factorOptions({ 1, 1.5, 2, 3, 5, 10 }), "jumpHeight"),
        Menu.Choice("Game Speed", factorOptions({ 0.25, 0.5, 0.75, 1, 1.5, 2 }, "1x (normal)"), "gameSpeed"),
        Menu.Toggle("Toggle Sprint (keyboard)", "toggleSprint"),
        Menu.Toggle("Instant Sprint", "instantSprint"),
        Menu.Section("Teleport (kept per area)"),
        Menu.Choice("Slot", slotOptions, slot),
        Menu.Action("Save position here", function()
            Teleport.SaveHere(slot.get())
            slotCache.options = nil -- the slot's description changed
        end),
        Menu.Action("Teleport to slot", function() Teleport.GoTo(slot.get()) end),
    }
end

local function combatTab()
    return {
        Menu.Toggle("One-Hit Kills", "oneHitKills"),
        Menu.Choice("Damage Multiplier", factorOptions({ 1, 1.5, 2, 3, 5, 10 }), "damageMultiplier"),
        Menu.Toggle("Every Block Is A Perfect Parry", "perfectParry"),
        Menu.Choice("Parry Window", factorOptions({ 0.5, 0.75, 1, 1.5, 2, 4, 6 }), "parryWindow"),
        Menu.Choice("Dodge Window", factorOptions({ 0.5, 0.75, 1, 1.5, 2, 3, 4 }), "dodgeWindow"),
        Menu.Section("Actions"),
        Menu.Action("Kill all enemies nearby", Combat.KillEnemiesNearby, { confirm = "Kills every enemy within 60 m." }),
    }
end

local function itemsTab()
    return {
        Menu.Toggle("Infinite Ammo (no reload)", "infiniteAmmo"),
        Menu.Toggle("Infinite Healing Flasks", "infiniteFlasks"),
        Menu.Toggle("Infinite Consumables", "infiniteConsumables"),
        Menu.Toggle("Infinite Buffs", "infiniteBuffs"),
        Menu.Toggle("No Item Cooldowns", "noItemCooldowns"),
        Menu.Toggle("Keep Catalysts On Death", "keepCatalysts"),
        Menu.Toggle("No Ability Costs", "noAbilityCosts"),
        Menu.Section("Actions"),
        Menu.Action("Refill everything", Resources.RefillEverything),
    }
end

local NO_ITEMS = { { label = "(load a save first)", value = nil } }

local function giveTab()
    local entry = Menu.Value(nil)
    local amount = Menu.Value(5)
    local categoryOptions = {}
    for _, category in ipairs(Give.CATEGORIES) do categoryOptions[#categoryOptions + 1] = { label = category.label, value = category.label } end
    local category = Menu.Value(categoryOptions[1].value)
    local selectCategory = {
        get = category.get,
        set = function(label)
            category.set(label)
            entry.set(nil)
        end,
    }

    -- Rebuilt only when the category or the catalog changes.
    local itemCache = { category = nil, entries = nil, options = nil }
    local function itemOptions()
        local catalog = Game.Player() and Give.Catalog()
        local entries = catalog and catalog[category.get()]
        if not entries or #entries == 0 then return NO_ITEMS end
        if itemCache.entries ~= entries then
            itemCache.entries, itemCache.options = entries, {}
            for index, itemEntry in ipairs(entries) do itemCache.options[index] = { label = itemEntry.label, value = itemEntry } end
        end
        if not entry.get() then entry.set(entries[1]) end
        return itemCache.options
    end

    return {
        Menu.Action("+1,000 Catalysts", function() Give.Catalysts(1000) end),
        Menu.Action("+10,000 Catalysts", function() Give.Catalysts(10000) end),
        Menu.Action("+99 of every upgrade material", function() Give.UpgradeMaterials(99) end),
        Menu.Action("+5 of every consumable", function() Give.EveryConsumable(5) end),
        Menu.Action("Unlock all weapons", Give.AllWeapons, { confirm = "Adds every weapon to this save. This can not be undone." }),
        Menu.Action("Unlock all abilities", Give.AllAbilities, { confirm = "Unlocks every ability on this save. This can not be undone." }),
        Menu.Action("Unlock all gems", Give.AllGems, { confirm = "Adds every gem to this save. This can not be undone." }),
        Menu.Section("Give Item"),
        Menu.Choice("Category", categoryOptions, selectCategory),
        Menu.Choice("Item", itemOptions, entry, { slider = true }),
        Menu.Choice("Amount", labeled({ { "1", 1 }, { "5", 5 }, { "10", 10 }, { "25", 25 }, { "50", 50 },
            { "99", 99 }, { "250", 250 }, { "999", 999 } }), amount, { wrap = false }),
        Menu.Action("Give", function() Give.Item(entry.get(), amount.get()) end),
    }
end

local function miscTab()
    return {
        Menu.Action("Turn everything off", Cheats.TurnEverythingOff, { confirm = "Sets every cheat back to vanilla.", anytime = true }),
        Menu.Toggle("Debug logging", "debugLogging"),
        Menu.Action("Write bug report", BugReport.Write, { anytime = true }),
        Menu.Info(function() return Game.NAME .. " v" .. Game.VERSION end),
    }
end

function Sheet.Build()
    Menu.AddTab("Survival", survivalTab())
    Menu.AddTab("Movement", movementTab())
    Menu.AddTab("Combat", combatTab())
    Menu.AddTab("Items", itemsTab())
    Menu.AddTab("Give", giveTab())
    Menu.AddTab("Misc", miscTab())
end

return Sheet
