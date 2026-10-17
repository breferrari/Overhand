-- ValorianSheet / features/bug_report.lua
-- One text file with the settings, the game state and the last log lines.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Paths = require("lib.paths")
local Game = require("game")
local State = require("state")
local DevActions = require("features.dev_actions")

local BugReport = {}

local REPORT_FILE = Paths.InModFolder("ValorianSheet-BugReport.txt")

local function attributeLine(setName, attributeNames)
    local set = Game.AttributeSet(setName)
    if not set then return setName .. ": not found" end
    local parts = {}
    for _, attributeName in ipairs(attributeNames) do
        parts[#parts + 1] = attributeName .. "=" .. tostring(Game.GetAttribute(set, attributeName))
    end
    return setName .. ": " .. table.concat(parts, ", ")
end

function BugReport.Write()
    local lines = {}
    local function add(line) lines[#lines + 1] = line end

    add(Game.NAME .. " v" .. Game.VERSION .. " - bug report")
    add("Written: " .. os.date("%Y-%m-%d %H:%M:%S"))
    add("")
    add("== Settings ==")
    for _, key in ipairs(State.SortedSettingKeys()) do add(key .. " = " .. tostring(State.settings[key])) end
    add("")
    add("== Game state ==")
    local player = Game.Player()
    add("status: " .. tostring(State.status))
    add("player: " .. (player and "found" or "NOT found"))
    add("cheat manager: " .. (Game.CheatManager() and "found" or "NOT found"))
    add("inventory subsystem: " .. (Game.Inventory() and "found" or "NOT found"))
    add("noclip active: " .. tostring(State.noClipActive))
    if player then
        add(attributeLine("Health", { "Health", "MaxHealth", "DamageMultiplier" }))
        add(attributeLine("Stamina", { "Stamina", "MaxStamina" }))
        add(attributeLine("Blood", { "BloodPoints", "MaxBloodPoints" }))
        add(attributeLine("Flasks", { "HealingFlasks", "HealingFlasksMax" }))
        add(attributeLine("Ranged", { "PistolAmmo", "PistolAmmoInClip", "RangedDamageMultiplier" }))
        add(attributeLine("Melee", { "MeleeDamageMultiplier", "ParryWindowAdjustment" }))
        local movement = Game.Movement()
        if movement then
            add("movement: mode=" .. tostring(Unreal.Try(function() return movement.MovementMode end))
                .. ", MaxWalkSpeed=" .. tostring(Unreal.Try(function() return movement.MaxWalkSpeed end))
                .. ", JumpZVelocity=" .. tostring(Unreal.Try(function() return movement.JumpZVelocity end)))
        end
    end
    add(DevActions.Describe())
    add("")
    add("== Last log lines ==")
    for _, line in ipairs(Log.RecentLines()) do add(line) end

    local ok = Paths.WriteFile(REPORT_FILE, table.concat(lines, "\n") .. "\n")
    Log.Info(ok and ("bug report written: " .. REPORT_FILE) or ("could not write " .. REPORT_FILE))
    State.status = ok and "Saved ValorianSheet-BugReport.txt in the mod folder" or "Could not write the bug report"
end

return BugReport
