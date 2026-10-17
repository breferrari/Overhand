-- games/valormortis/features/teleport.lua
-- Up to 5 saved positions, kept per area, in teleports.txt (one line per slot:
-- slot|map|x|y|z|yaw|name, the Valor Mortis Cheat Menu's format).

local Unreal = require("core.unreal")
local Log = require("core.log")
local Game = require("games.valormortis.game")
local App = require("core.app")
local Settings = require("core.settings")
local Shared = require("games.valormortis.shared")

local Teleport = {}

local try = Unreal.Try

Teleport.SLOT_COUNT = 5

local positions = {}   -- slot number (string) -> { map, x, y, z, yaw, name }

Settings.RegisterFile("teleports.txt", {
    read = function(content)
        for line in content:gmatch("[^\r\n]+") do
            local slot, map, x, y, z, yaw, name = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
            if slot then
                positions[slot] = {
                    map = map ~= "" and map or nil,
                    x = tonumber(x), y = tonumber(y), z = tonumber(z),
                    yaw = tonumber(yaw),
                    name = name ~= "" and name or nil,
                }
            end
        end
    end,
    write = function()
        local slots = {}
        for slot in pairs(positions) do slots[#slots + 1] = tonumber(slot) end
        table.sort(slots)
        local lines = {}
        for _, slot in ipairs(slots) do
            local position = positions[tostring(slot)]
            lines[#lines + 1] = string.format("%d|%s|%s|%s|%s|%s|%s", slot, position.map or "",
                tostring(position.x or ""), tostring(position.y or ""), tostring(position.z or ""),
                tostring(position.yaw or ""), ((position.name or ""):gsub("[|\r\n]", " ")))
        end
        return table.concat(lines, "\n") .. "\n"
    end,
})

local function savedPosition(slot)
    local position = positions[tostring(slot)]
    if type(position) == "table" and type(position.x) == "number" then return position end
    return nil
end

function Teleport.SlotName(slot)
    local position = positions[tostring(slot)]
    local name = type(position) == "table" and position.name
    if type(name) == "string" and name:match("%S") then return name end
    return "Position " .. slot
end

-- "Position 2", "Position 2 (empty)" or "Position 2 (other area)", for the menu.
-- currentMap: Game.MapName(), read once by the caller for all slots.
function Teleport.Describe(slot, currentMap)
    local position = savedPosition(slot)
    if not position then return Teleport.SlotName(slot) .. " (empty)" end
    if currentMap ~= "?" and position.map ~= currentMap then return Teleport.SlotName(slot) .. " (other area)" end
    return Teleport.SlotName(slot)
end

function Teleport.SaveHere(slot)
    local player, controller = Game.Player(), Game.Controller()
    local location = try(function() return player:K2_GetActorLocation() end)
    if not location then
        App.status = "Could not read your position"
        return
    end
    local yaw = Unreal.TryNumber(function() return controller:GetControlRotation().Yaw end) or 0
    local previous = positions[tostring(slot)]
    positions[tostring(slot)] = {
        map = Game.MapName(),
        x = location.X, y = location.Y, z = location.Z,
        yaw = yaw,
        name = type(previous) == "table" and previous.name or nil,
    }
    Settings.MarkDirty()
    Log.Info(string.format("position %d (%s) saved: %s %.0f %.0f %.0f",
        slot, Teleport.SlotName(slot), Game.MapName(), location.X, location.Y, location.Z))
    App.status = Teleport.SlotName(slot) .. " saved"
end

function Teleport.GoTo(slot)
    local position = savedPosition(slot)
    if not position then
        App.status = Teleport.SlotName(slot) .. " is empty, save it first"
        return
    end
    if position.map ~= Game.MapName() then
        App.status = Teleport.SlotName(slot) .. " was saved in another area"
        return
    end
    local player, controller, movement = Game.Player(), Game.Controller(), Game.Movement()
    if movement then try(function() movement.Velocity = { X = 0, Y = 0, Z = 0 } end) end
    local moved = try(function()
        player:K2_SetActorLocation({ X = position.x, Y = position.y, Z = position.z }, false, {}, true)
        return true
    end)
    if controller and type(position.yaw) == "number" then
        try(function() controller:SetControlRotation({ Pitch = 0, Yaw = position.yaw, Roll = 0 }) end)
    end
    Shared.safeLandingUntil = os.clock() + 3
    Log.Info("teleport to position " .. slot .. " (" .. Teleport.SlotName(slot) .. ")" .. (moved and "" or " FAILED"))
    App.status = moved and ("Teleported to " .. Teleport.SlotName(slot)) or "Teleport failed"
end

return Teleport
