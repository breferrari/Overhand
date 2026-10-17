-- games/valormortis/init.lua
-- Wires Valor Mortis into core: defines the app, registers the features and once-per-world checks
-- with the runner, configures GAS and the menu, and adds the game's part of the bug report.
-- main.lua requires this once; nothing in core knows about Valor Mortis.

require("games.valormortis.app")

local Unreal = require("core.unreal")
local Runner = require("core.runner")
local BugReport = require("core.bug_report")
local Menu = require("core.ui.menu")
local Gas = require("gas.gas")
local Game = require("games.valormortis.game")
local Shared = require("games.valormortis.shared")
local Sheet = require("games.valormortis.sheet")
local Health = require("games.valormortis.features.health")
local Defense = require("games.valormortis.features.defense")
local Damage = require("games.valormortis.features.damage")
local Resources = require("games.valormortis.features.resources")
local Movement = require("games.valormortis.features.movement")
local Combat = require("games.valormortis.features.combat")
local Buffs = require("games.valormortis.features.buffs")
local Give = require("games.valormortis.features.give")
local DevActions = require("games.valormortis.features.dev_actions")
local SavedValues = require("games.valormortis.features.saved_values")

Gas.Configure({ abilitySystem = Game.AbilitySystem })

Runner.Configure({ identity = Game.Player })
Runner.OnTickStart(Gas.BeginTick)
Runner.AddWorldCheck("check saved values", SavedValues.Check, 10)
Runner.AddWorldCheck("remove broken weapons", Give.RemoveBrokenWeapons)
Runner.AddFeature("dev actions", DevActions.Tick)
Runner.AddFeature("health", Health.Tick)
Runner.AddFeature("damage taken", Defense.Tick)
Runner.AddFeature("damage hooks", Damage.Tick)
Runner.AddFeature("resources", Resources.Tick)
Runner.AddFeature("movement", Movement.Tick)
Runner.AddFeature("combat", Combat.Tick)
Runner.AddFeature("buffs", Buffs.Tick)

Menu.Configure({
    controller = Game.Controller,
    player = Game.Player,
    isReady = function() return Game.Player() ~= nil end,
    gameMenuClasses = {
        "WBP_PauseMenu_C", "WBP_PanelSettings_C", "WBP_PlayerInventory_C", "WBP_LanternMenu_C",
        "WBP_ProgressionMenu_C", "WBP_PlayerJournal_C", "WBP_PlayerQuests_C", "WBP_FastTravel_C",
        "WBP_SaveManager_C", "WBP_DeathScreen_C", "WBP_PlayerArsenal_C", "WBP_PlayerStorage_C",
        "WBP_MessageBox_C",
    },
    -- The game's own button images, by chip label (find candidates with Misc > Find controller
    -- button icons). Chips are drawn for every button without one.
    buttonIcons = {},
})

local function attributeLine(setName, attributeNames)
    local set = Game.AttributeSet(setName)
    if not set then return setName .. ": not found" end
    local parts = {}
    for _, attributeName in ipairs(attributeNames) do
        parts[#parts + 1] = attributeName .. "=" .. tostring(Gas.GetAttribute(set, attributeName))
    end
    return setName .. ": " .. table.concat(parts, ", ")
end

BugReport.AddSection("Game state", function()
    local lines = {
        "player: " .. (Game.Player() and "found" or "NOT found"),
        "cheat manager: " .. (Game.CheatManager() and "found" or "NOT found"),
        "inventory subsystem: " .. (Game.Inventory() and "found" or "NOT found"),
        "noclip active: " .. tostring(Shared.noClipActive),
        DevActions.Describe(),
    }
    if Game.Player() then
        lines[#lines + 1] = attributeLine("Health", { "Health", "MaxHealth", "MeleeResistance", "RangedResistance" })
        lines[#lines + 1] = attributeLine("Stamina", { "Stamina", "MaxStamina" })
        lines[#lines + 1] = attributeLine("Blood", { "BloodPoints", "MaxBloodPoints" })
        lines[#lines + 1] = attributeLine("Flasks", { "HealingFlasks", "HealingFlasksMax" })
        lines[#lines + 1] = attributeLine("Ranged", { "PistolAmmo", "PistolAmmoInClip", "RangedDamageMultiplier" })
        lines[#lines + 1] = attributeLine("Melee", { "MeleeDamageMultiplier", "ParryWindowAdjustment" })
        local movement = Game.Movement()
        if movement then
            lines[#lines + 1] = "movement: mode=" .. tostring(Unreal.Try(function() return movement.MovementMode end))
                .. ", MaxWalkSpeed=" .. tostring(Unreal.Try(function() return movement.MaxWalkSpeed end))
        end
    end
    return lines
end)

Sheet.Build()
