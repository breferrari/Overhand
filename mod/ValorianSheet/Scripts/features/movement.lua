-- ValorianSheet / features/movement.lua
-- Movement Speed, Jump Height, Instant Sprint, Toggle Sprint, NoClip and Game Speed.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Override = require("lib.override")
local Game = require("game")
local State = require("state")

local Movement = {}

local try, isValid = Unreal.Try, Unreal.IsValid
local clock = State.clock

local speedOverride = Override.new()
local jumpOverride = Override.new()
local accelerationOverride = Override.new()
local flyOverride = Override.new()

local MOVEMENT_MODE_FALLING, MOVEMENT_MODE_FLYING = 3, 5
local INSTANT_ACCELERATION = 40
local FLY_SPEED = 1200
local FLY_BRAKING = 6000

-- ---------------------------------------------------------------------------
-- NoClip: fly mode without collision. Space / A = up, Ctrl / C / B = down.
-- ---------------------------------------------------------------------------

local UP_KEYS = { "SpaceBar", "Gamepad_FaceButton_Bottom" }
local DOWN_KEYS = { "LeftControl", "C", "Gamepad_FaceButton_Right" }
local keyStructs = {}

local function anyKeyDown(keyNames)
    local controller = Game.Controller()
    if not controller then return false end
    for _, keyName in ipairs(keyNames) do
        keyStructs[keyName] = keyStructs[keyName] or { KeyName = FName(keyName) }
        if try(function() return controller:IsInputKeyDown(keyStructs[keyName]) end) == true then return true end
    end
    return false
end

local function setNoClip(enabled)
    local player, movement = Game.Player(), Game.Movement()
    if not player or not movement then return end
    if enabled then
        try(function() player:SetActorEnableCollision(false) end)
        try(function() movement:SetMovementMode(MOVEMENT_MODE_FLYING, 0) end)
    else
        flyOverride:restore()
        try(function() player:SetActorEnableCollision(true) end)
        try(function() movement:SetMovementMode(MOVEMENT_MODE_FALLING, 0) end)
        State.safeLandingUntil = clock() + 4 -- no fall damage when dropping out of NoClip
    end
    State.noClipActive = enabled
    Log.Info("noclip " .. (enabled and "ON" or "OFF"))
end

local function flyWithNoClip()
    local movement = Game.Movement()
    if not movement then return end
    if try(function() return movement.MovementMode end) ~= MOVEMENT_MODE_FLYING then
        try(function() movement:SetMovementMode(MOVEMENT_MODE_FLYING, 0) end)
    end
    flyOverride:property(movement, "MaxFlySpeed", function() return FLY_SPEED end)
    flyOverride:property(movement, "BrakingDecelerationFlying", function() return FLY_BRAKING end)
    local verticalSpeed = 0
    if anyKeyDown(UP_KEYS) then
        verticalSpeed = FLY_SPEED
    elseif anyKeyDown(DOWN_KEYS) then
        verticalSpeed = -FLY_SPEED
    end
    try(function()
        local velocity = movement.Velocity
        movement.Velocity = { X = velocity.X, Y = velocity.Y, Z = verticalSpeed }
    end)
end

-- ---------------------------------------------------------------------------
-- Toggle Sprint: on a gamepad the game's sprint ability (GA_Sprint) already works as a toggle; it
-- keeps a flag for that. With Toggle Sprint on we set that flag for the keyboard too.
-- The ability instances are kept and only searched again when none of them is alive any more
-- (at most every 5 s).
-- ---------------------------------------------------------------------------

local sprint = { abilities = {}, nextSearchAt = 0, toggleSet = false }

local function anyAlive(objects)
    for _, object in ipairs(objects) do
        if isValid(object) then return true end
    end
    return false
end

local function applyToggleSprint()
    local enabled = State.settings.toggleSprint == true
    if not enabled and not sprint.toggleSet then return end
    if not anyAlive(sprint.abilities) and clock() >= sprint.nextSearchAt then
        sprint.nextSearchAt = clock() + 5
        sprint.abilities = {}
        for _, ability in ipairs(FindAllOf("GA_Sprint_C") or {}) do
            if Unreal.IsLiveObject(ability) then sprint.abilities[#sprint.abilities + 1] = ability end
        end
    end
    for _, ability in ipairs(sprint.abilities) do
        if isValid(ability) then
            local isToggle = try(function() return ability.bGamepadInput end)
            if enabled and isToggle == false then
                try(function() ability.bGamepadInput = true end)
                if not sprint.toggleSet then Log.Info("toggle sprint: sprint ability set to toggle") end
                sprint.toggleSet = true
            elseif not enabled and sprint.toggleSet and isToggle == true then
                try(function() ability.bGamepadInput = false end)
            end
        end
    end
    if not enabled then sprint.toggleSet = false end
end

-- ---------------------------------------------------------------------------
-- Speed, jump, acceleration, game speed
-- ---------------------------------------------------------------------------

local function applyMovementOverrides()
    local movement, settings = Game.Movement(), State.settings

    if settings.movementSpeed ~= 1 and movement and not State.noClipActive then
        speedOverride:property(movement, "MaxWalkSpeed", settings.movementSpeed)
        speedOverride:property(movement, "MaxWalkSpeedCrouched", settings.movementSpeed)
    elseif speedOverride:isActive() and (settings.movementSpeed == 1 or State.noClipActive) then
        speedOverride:restore()
    end

    if settings.jumpHeight ~= 1 and movement then
        -- Jump height grows with the square of the launch speed.
        jumpOverride:property(movement, "JumpZVelocity", math.sqrt(settings.jumpHeight))
    elseif settings.jumpHeight == 1 and jumpOverride:isActive() then
        jumpOverride:restore()
    end

    -- Instant Sprint: full speed the moment you start running (no speed-up phase)
    if settings.instantSprint and movement and not State.noClipActive then
        accelerationOverride:property(movement, "MaxAcceleration", INSTANT_ACCELERATION)
    elseif accelerationOverride:isActive() and (not settings.instantSprint or State.noClipActive) then
        accelerationOverride:restore()
    end
end

local appliedGameSpeed = 1

local function applyGameSpeed()
    local gameSpeed = State.settings.gameSpeed or 1
    if gameSpeed == appliedGameSpeed then return end
    local statics, player = Game.GameplayStatics(), Game.Player()
    if isValid(statics) and player and try(function()
        statics:SetGlobalTimeDilation(player, gameSpeed)
        return true
    end) then
        appliedGameSpeed = gameSpeed
    end
end

-- ---------------------------------------------------------------------------

function Movement.Tick()
    if State.settings.noClip ~= State.noClipActive then setNoClip(State.settings.noClip) end
    if State.noClipActive then flyWithNoClip() end
    applyMovementOverrides()
    applyToggleSprint()
    applyGameSpeed()
end

function Movement.Reset()
    speedOverride:forget()
    jumpOverride:forget()
    accelerationOverride:forget()
    flyOverride:forget()
    sprint.abilities, sprint.nextSearchAt = {}, 0
    appliedGameSpeed = 1
    State.noClipActive = false
end

return Movement
