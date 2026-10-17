-- ValorianSheet / features/teleport.lua
-- Up to 5 saved positions, kept per area. State.teleports is persisted by settings.lua.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Settings = require("settings")

local Teleport = {}

local try = Unreal.Try

Teleport.SLOT_COUNT = 5

local function savedPosition(slot)
    local position = State.teleports[tostring(slot)]
    if type(position) == "table" and type(position.x) == "number" then return position end
    return nil
end

function Teleport.SlotName(slot)
    local position = State.teleports[tostring(slot)]
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
        State.status = "Could not read your position"
        return
    end
    local yaw = Unreal.TryNumber(function() return controller:GetControlRotation().Yaw end) or 0
    local previous = State.teleports[tostring(slot)]
    State.teleports[tostring(slot)] = {
        map = Game.MapName(),
        x = location.X, y = location.Y, z = location.Z,
        yaw = yaw,
        name = type(previous) == "table" and previous.name or nil,
    }
    Settings.MarkDirty()
    Log.Info(string.format("position %d (%s) saved: %s %.0f %.0f %.0f",
        slot, Teleport.SlotName(slot), Game.MapName(), location.X, location.Y, location.Z))
    State.status = Teleport.SlotName(slot) .. " saved"
end

function Teleport.GoTo(slot)
    local position = savedPosition(slot)
    if not position then
        State.status = Teleport.SlotName(slot) .. " is empty, save it first"
        return
    end
    if position.map ~= Game.MapName() then
        State.status = Teleport.SlotName(slot) .. " was saved in another area"
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
    State.safeLandingUntil = os.clock() + 3
    Log.Info("teleport to position " .. slot .. " (" .. Teleport.SlotName(slot) .. ")" .. (moved and "" or " FAILED"))
    State.status = moved and ("Teleported to " .. Teleport.SlotName(slot)) or "Teleport failed"
end

return Teleport
