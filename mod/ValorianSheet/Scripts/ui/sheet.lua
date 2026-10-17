-- ValorianSheet / ui/sheet.lua
-- What the menu shows: six tabs, each row bound to a setting or an action of a feature module.

local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Cheats = require("cheats")
local Menu = require("ui.menu")
local Combat = require("features.combat")
local Resources = require("features.resources")
local Give = require("features.give")
local Teleport = require("features.teleport")
local BugReport = require("features.bug_report")

local Sheet = {}

local requiresSave = Cheats.RequiresSave

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

local function labeled(pairsList)
    local options = {}
    for _, entry in ipairs(pairsList) do options[#options + 1] = { label = entry[1], value = entry[2] } end
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
        Menu.Choice("Regeneration", labeled({ { "Off (vanilla)", 0 }, { "1% / s", 0.01 }, { "2% / s", 0.02 },
            { "5% / s", 0.05 }, { "10% / s", 0.1 } }), "regenRate"),
        Menu.Choice("Starts after a hit", labeled({ { "right away", 0 }, { "2 s", 2 }, { "5 s", 5 }, { "10 s", 10 } }), "regenDelay"),
        Menu.Toggle("Only out of combat", "regenOnlyOutOfCombat"),
    }
end

local selectedSlot = 1

local function movementTab()
    local slotAccessor = { get = function() return selectedSlot end, set = function(slot) selectedSlot = slot end }
    local function slotOptions()
        local options = {}
        for slot = 1, Teleport.SLOT_COUNT do options[slot] = { label = slot .. ": " .. Teleport.Describe(slot), value = slot } end
        return options
    end
    return {
        Menu.Toggle("NoClip (Space up, Ctrl down)", "noClip"),
        Menu.Choice("Movement Speed", factorOptions({ 1, 1.25, 1.5, 2, 3, 5 }), "movementSpeed"),
        Menu.Choice("Jump Height", factorOptions({ 1, 1.5, 2, 3, 5, 10 }), "jumpHeight"),
        Menu.Choice("Game Speed", factorOptions({ 0.25, 0.5, 0.75, 1, 1.5, 2 }, "1x (normal)"), "gameSpeed"),
        Menu.Toggle("Toggle Sprint (keyboard)", "toggleSprint"),
        Menu.Toggle("Instant Sprint", "instantSprint"),
        Menu.Section("Teleport (kept per area)"),
        Menu.Choice("Slot", slotOptions, slotAccessor),
        Menu.Action("Save position here", requiresSave(function() Teleport.SaveHere(selectedSlot) end)),
        Menu.Action("Teleport to slot", requiresSave(function() Teleport.GoTo(selectedSlot) end)),
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
        Menu.Action("Kill all enemies nearby", requiresSave(Combat.KillEnemiesNearby), "Kills every enemy within 60 m."),
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
        Menu.Action("Refill everything", requiresSave(Resources.RefillEverything)),
    }
end

local giveCategory = Give.CATEGORIES[1].label
local giveEntry = nil
local giveAmount = 5

local function giveTab()
    local categoryOptions = {}
    for _, category in ipairs(Give.CATEGORIES) do categoryOptions[#categoryOptions + 1] = { label = category.label, value = category.label } end
    local function itemOptions()
        local catalog = Game.Player() and Give.Catalog()
        local entries = catalog and catalog[giveCategory]
        if not entries or #entries == 0 then return { { label = "(load a save first)", value = nil } } end
        local options = {}
        for index, entry in ipairs(entries) do options[index] = { label = entry.label, value = entry } end
        if not giveEntry then giveEntry = entries[1] end
        return options
    end
    return {
        Menu.Action("+1,000 Catalysts", requiresSave(function() Give.Catalysts(1000) end)),
        Menu.Action("+10,000 Catalysts", requiresSave(function() Give.Catalysts(10000) end)),
        Menu.Action("+99 of every upgrade material", requiresSave(function() Give.UpgradeMaterials(99) end)),
        Menu.Action("+5 of every consumable", requiresSave(function() Give.EveryConsumable(5) end)),
        Menu.Action("Unlock all weapons", requiresSave(Give.AllWeapons), "Adds every weapon to this save. This can not be undone."),
        Menu.Action("Unlock all abilities", requiresSave(Give.AllAbilities), "Unlocks every ability on this save. This can not be undone."),
        Menu.Action("Unlock all gems", requiresSave(Give.AllGems), "Adds every gem to this save. This can not be undone."),
        Menu.Section("Give Item"),
        Menu.Choice("Category", categoryOptions, {
            get = function() return giveCategory end,
            set = function(label) giveCategory, giveEntry = label, nil end,
        }),
        Menu.Choice("Item", itemOptions, {
            get = function() return giveEntry end,
            set = function(entry) giveEntry = entry end,
        }, { slider = true }),
        Menu.Choice("Amount", labeled({ { "1", 1 }, { "5", 5 }, { "10", 10 }, { "25", 25 }, { "50", 50 },
            { "99", 99 }, { "250", 250 }, { "999", 999 } }), {
            get = function() return giveAmount end,
            set = function(amount) giveAmount = amount end,
        }, { wrap = false }),
        Menu.Action("Give", requiresSave(function() Give.Item(giveEntry, giveAmount) end)),
    }
end

local function miscTab(saveSettings)
    return {
        Menu.Action("Turn everything off", function()
            Cheats.TurnEverythingOff()
            saveSettings()
            State.status = "Everything is back to vanilla"
        end, "Sets every cheat back to vanilla."),
        Menu.Toggle("Debug logging", {
            get = function() return Log.debugEnabled end,
            set = function(enabled)
                Log.debugEnabled = enabled
                Log.Info("debug logging " .. (enabled and "ON" or "OFF"))
                saveSettings()
            end,
        }),
        Menu.Action("Write bug report", BugReport.Write),
        Menu.Info(function() return Game.NAME .. " v" .. Game.VERSION end),
    }
end

-- saveSettings: persists State.settings (called after changes that are not a settings key).
function Sheet.Build(saveSettings)
    Menu.AddTab("Survival", survivalTab())
    Menu.AddTab("Movement", movementTab())
    Menu.AddTab("Combat", combatTab())
    Menu.AddTab("Items", itemsTab())
    Menu.AddTab("Give", giveTab())
    Menu.AddTab("Misc", miscTab(saveSettings))
end

return Sheet
