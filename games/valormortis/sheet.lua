-- games/valormortis/sheet.lua
-- What the menu shows: six tabs, each row bound to a setting or an action of a feature module, with
-- the description the menu shows while the row is selected. Actions need a loaded save unless
-- marked { anytime = true }.

local App = require("core.app")
local Log = require("core.log")
local Settings = require("core.settings")
local BugReport = require("core.bug_report")
local Menu = require("core.ui.menu")
local IconFinder = require("core.ui.icon_finder")
local Game = require("game.game")
local Combat = require("game.features.combat")
local Resources = require("game.features.resources")
local Give = require("game.features.give")
local Teleport = require("game.features.teleport")

local Sheet = {}

-- { 1, 1.5, 2 } -> "1x · vanilla", "1.5x", "2x"
local function factorOptions(values, vanillaLabel)
    local options = {}
    for _, value in ipairs(values) do
        local label = value .. "x"
        if value == 1 then label = vanillaLabel or "1x · vanilla" end
        if value < 1 then label = label .. " · harder" end
        options[#options + 1] = { label = label, value = value }
    end
    return options
end

-- { 1, 0.5, 0 } -> "100% · vanilla", "50%", "0%"
local function percentOptions(values, lastLabel)
    local options = {}
    for index, value in ipairs(values) do
        local label = math.floor(value * 100 + 0.5) .. "%"
        if value == 1 then label = label .. " · vanilla" end
        if index == #values and lastLabel then label = label .. " · " .. lastLabel end
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
        Menu.Toggle("God Mode", "godMode", { description = "Hits and falls do no damage." }),
        Menu.Toggle("Infinite Stamina", "infiniteStamina",
            { description = "Stamina stays full: sprint, dodge and attack without running dry." }),
        Menu.Toggle("only out of combat", "staminaOnlyOutOfCombat", { sub = true,
            description = "Infinite Stamina only while you are not fighting. In a fight, stamina works as the game intends." }),
        Menu.Toggle("Infinite Nephtoglobin", "infiniteNephtoglobin", { description = "Your Nephtoglobin stays full." }),
        Menu.Choice("Fall Damage", percentOptions({ 1, 0.75, 0.5, 0.25, 0 }, "none"), "fallDamage",
            { description = "How much damage a fall does. At 0% you can drop from any height." }),
        Menu.Choice("Damage Taken", percentOptions({ 1, 0.75, 0.5, 0.25, 0.1 }), "damageTaken",
            { description = "The share of every hit that gets through, applied through your resistances like the game's own armour." }),
        Menu.Choice("Max Health", factorOptions({ 1, 1.5, 2, 3, 5 }), "maxHealthFactor",
            { description = "Multiplies your maximum health. The health bar keeps its normal length." }),
        Menu.Section("Health Regeneration"),
        Menu.Choice("Regeneration", labeled({ { "Off · vanilla", 0 }, { "1 HP/s", 1 }, { "2 HP/s", 2 },
            { "5 HP/s", 5 }, { "10 HP/s", 10 }, { "20 HP/s", 20 }, { "50 HP/s", 50 } }), "regenPerSecond",
            { description = "Heals you a little every second, through the game's own health attribute." }),
        Menu.Choice("starts after a hit", labeled({ { "right away", 0 }, { "2 s · default", 2 }, { "5 s", 5 }, { "10 s", 10 } }),
            "regenDelay", { sub = true, description = "How long after the last hit before healing starts." }),
        Menu.Choice("heals up to", labeled({ { "25%", 25 }, { "50%", 50 }, { "75%", 75 }, { "100% · default", 100 } }),
            "regenMaxPercent", { sub = true, description = "Healing stops at this share of your maximum health." }),
        Menu.Toggle("only out of combat", "regenOnlyOutOfCombat",
            { sub = true, description = "Regeneration pauses while you are in a fight." }),
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
        Menu.Toggle("NoClip", "noClip", { description =
            "Fly through walls. Space or A goes up; Ctrl, C or B goes down. Always off when the game starts." }),
        Menu.Choice("Movement Speed", factorOptions({ 1, 1.25, 1.5, 2, 3, 5 }), "movementSpeed",
            { description = "How fast you walk and run." }),
        Menu.Choice("Jump Height", factorOptions({ 1, 1.5, 2, 3, 5, 10 }), "jumpHeight", { description = "How high you jump." }),
        Menu.Choice("Game Speed", factorOptions({ 0.25, 0.5, 0.75, 1, 1.5, 2 }, "1x · normal"), "gameSpeed",
            { description = "Slows down or speeds up the whole game, enemies and all." }),
        Menu.Toggle("Toggle Sprint (keyboard)", "toggleSprint",
            { description = "Press sprint once to keep running, as the controller already does." }),
        Menu.Toggle("Instant Sprint", "instantSprint", { description = "Full speed the moment you start running." }),
        Menu.Section("Teleport"),
        Menu.Choice("Slot", slotOptions, slot, { description = "Five saved positions, kept separately for every area." }),
        Menu.Action("Save position here", function()
            Teleport.SaveHere(slot.get())
            slotCache.options = nil -- the slot's description changed
        end, { description = "Saves where you stand into the selected slot." }),
        Menu.Action("Teleport to slot", function() Teleport.GoTo(slot.get()) end,
            { description = "Takes you to the position saved in the selected slot." }),
    }
end

local function combatTab()
    return {
        Menu.Toggle("One-Hit Kills", "oneHitKills", { description = "Every hit you land kills." }),
        Menu.Choice("Damage Multiplier", factorOptions({ 1, 1.5, 2, 3, 5, 10 }), "damageMultiplier",
            { description = "Multiplies the damage you deal." }),
        Menu.Toggle("Every Block Is A Perfect Parry", "perfectParry",
            { description = "Any block counts as a perfectly timed parry." }),
        Menu.Choice("Parry Window", factorOptions({ 0.5, 0.75, 1, 1.5, 2, 4, 6 }), "parryWindow",
            { description = "How long the parry timing window lasts. Wider is easier." }),
        Menu.Choice("Dodge Window", factorOptions({ 0.5, 0.75, 1, 1.5, 2, 3, 4 }), "dodgeWindow",
            { description = "How long a dodge keeps you invulnerable." }),
        Menu.Section("Actions"),
        Menu.Action("Kill all enemies nearby", Combat.KillEnemiesNearby,
            { confirm = "Kills every enemy within 60 m.", description = "Kills every enemy within 60 m. Asks to confirm." }),
    }
end

local function itemsTab()
    return {
        Menu.Toggle("Infinite Ammo", "infiniteAmmo", { description = "The pistol never runs out and never needs a reload." }),
        Menu.Toggle("Infinite Healing Flasks", "infiniteFlasks", { description = "Drinking a healing flask does not use it up." }),
        Menu.Toggle("Infinite Consumables", "infiniteConsumables",
            { description = "Grenades, syringes and other consumables come back after you use them." }),
        Menu.Toggle("Infinite Buffs", "infiniteBuffs", { description = "Potions, weapon coatings and pistol boosts never wear off." }),
        Menu.Toggle("No Item Cooldowns", "noItemCooldowns", { description = "Items can be used again right away." }),
        Menu.Toggle("Keep Catalysts On Death", "keepCatalysts",
            { description = "After a death, your dropped catalysts are picked up for you as soon as you are back on your feet." }),
        Menu.Toggle("No Ability Costs", "noAbilityCosts", { description = "Abilities cost nothing to use." }),
        Menu.Section("Actions"),
        Menu.Action("Refill everything", Resources.RefillEverything,
            { description = "Health, flasks, ammo and consumables back to full, like resting at a lantern." }),
    }
end

local NO_ITEMS = { { label = "(load a save first)", value = nil } }
local NOT_UNDONE = " This can not be undone."

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

    -- an action that can not be undone asks first, and says so in its description
    local function unlock(label, run, what)
        return Menu.Action(label, run, { confirm = what .. NOT_UNDONE, description = what .. NOT_UNDONE })
    end

    return {
        Menu.Action("+1,000 Catalysts", function() Give.Catalysts(1000) end, { description = "Adds 1,000 catalysts." }),
        Menu.Action("+10,000 Catalysts", function() Give.Catalysts(10000) end, { description = "Adds 10,000 catalysts." }),
        Menu.Action("+99 of every upgrade material", function() Give.UpgradeMaterials(99) end,
            { description = "Adds 99 of every upgrade material." }),
        Menu.Action("+5 of every consumable", function() Give.EveryConsumable(5) end,
            { description = "Adds 5 of every consumable." }),
        unlock("Unlock all weapons", Give.AllWeapons, "Adds every weapon to this save."),
        unlock("Unlock all abilities", Give.AllAbilities, "Unlocks every ability on this save."),
        unlock("Unlock all gems", Give.AllGems, "Adds every gem to this save."),
        Menu.Section("Give Item"),
        Menu.Choice("Category", categoryOptions, selectCategory, { description = "What kind of item to give." }),
        Menu.Choice("Item", itemOptions, entry, { slider = true,
            description = "The item to give. With the mouse, the slider scrolls through long lists." }),
        Menu.Choice("Amount", labeled({ { "1", 1 }, { "5", 5 }, { "10", 10 }, { "25", 25 }, { "50", 50 },
            { "99", 99 }, { "250", 250 }, { "999", 999 } }), amount, { wrap = false, description = "How many to give." }),
        Menu.Action("Give", function() Give.Item(entry.get(), amount.get()) end,
            { description = "Gives the chosen amount of the chosen item." }),
    }
end

local function turnEverythingOff()
    App.ResetCheats()
    Settings.MarkDirty()
    App.status = "Everything is back to vanilla"
    Log.Info("everything turned off")
end

local function miscTab()
    return {
        Menu.Action("Turn everything off", turnEverythingOff, { confirm = "Sets every cheat back to vanilla.", anytime = true,
            description = "Every cheat back to vanilla. Debug logging stays as it is." }),
        Menu.Toggle("Debug logging", "debugLogging",
            { description = "Writes more detail to " .. App.name .. ".log, for bug reports." }),
        Menu.Action("Write bug report", BugReport.Write, { anytime = true, description =
            "Writes " .. App.name .. "-BugReport.txt into the mod folder: settings, game state and the last log lines." }),
        Menu.Action("Find controller button icons", IconFinder.WriteReport, { description =
            "Lists the game's controller button images in " .. App.name .. "-ButtonIcons.txt, so the menu can use them." }),
        Menu.Info(function() return App.name .. " v" .. App.version end),
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
