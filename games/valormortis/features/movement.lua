-- games/valormortis/features/movement.lua
-- Movement Speed, Jump Height, Instant Sprint, Toggle Sprint, NoClip and Game Speed.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Override = require("core.override")
local Game = require("game.game")
local App = require("core.app")
local Shared = require("game.shared")

local Movement = {}

local try, isValid = Unreal.Try, Unreal.IsValid
local MODE = Game.MOVEMENT_MODE

local speedOverride = Override.new()
local jumpOverride = Override.new()
local accelerationOverride = Override.new()
local flyOverride = Override.new()

local INSTANT_ACCELERATION = 40
local FLY_SPEED = 1200
local FLY_BRAKING = 6000

-- ---------------------------------------------------------------------------
-- NoClip: fly mode without collision. Space / A = up, Ctrl / C / B = down.
-- ---------------------------------------------------------------------------

local UP_KEYS = { "SpaceBar", "Gamepad_FaceButton_Bottom" }
local DOWN_KEYS = { "LeftControl", "C", "Gamepad_FaceButton_Right" }

local function anyKeyDown(keyNames)
    for _, keyName in ipairs(keyNames) do
        if Game.IsKeyDown(keyName) then return true end
    end
    return false
end

local function setNoClip(enabled)
    local player, movement = Game.Player(), Game.Movement()
    if not player or not movement then return end
    if enabled then
        try(function() player:SetActorEnableCollision(false) end)
        try(function() movement:SetMovementMode(MODE.FLYING, 0) end)
    else
        flyOverride:restore()
        try(function() player:SetActorEnableCollision(true) end)
        try(function() movement:SetMovementMode(MODE.FALLING, 0) end)
        Shared.safeLandingUntil = os.clock() + 4 -- no fall damage when dropping out of NoClip
    end
    Shared.noClipActive = enabled
    Log.Info("noclip " .. (enabled and "ON" or "OFF"))
end

local function flyWithNoClip(movement)
    if try(function() return movement.MovementMode end) ~= MODE.FLYING then
        try(function() movement:SetMovementMode(MODE.FLYING, 0) end)
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
-- ---------------------------------------------------------------------------

local toggleSprintSet = false

local function applyToggleSprint()
    local enabled = App.settings.toggleSprint == true
    if not enabled and not toggleSprintSet then return end
    for _, ability in ipairs(Unreal.FindAllCached("sprintAbilities", "GA_Sprint_C", 5)) do
        local isToggle = try(function() return ability.bGamepadInput end)
        if enabled and isToggle == false then
            try(function() ability.bGamepadInput = true end)
            if not toggleSprintSet then Log.Info("toggle sprint: sprint ability set to toggle") end
            toggleSprintSet = true
        elseif not enabled and isToggle == true then
            try(function() ability.bGamepadInput = false end)
        end
    end
    if not enabled then toggleSprintSet = false end
end

-- ---------------------------------------------------------------------------
-- Speed, jump, acceleration, game speed
-- ---------------------------------------------------------------------------

-- override:property while wanted, back to vanilla once it is not.
local function applyOverride(override, wanted, movement, propertyName, factorOrFunction)
    if wanted then
        override:property(movement, propertyName, factorOrFunction)
    elseif override:isActive() then
        override:restore()
    end
end

local function applyMovementOverrides(movement)
    local settings = App.settings
    local walking = not Shared.noClipActive
    applyOverride(speedOverride, walking and settings.movementSpeed ~= 1, movement, "MaxWalkSpeed", settings.movementSpeed)
    if speedOverride:isActive() then speedOverride:property(movement, "MaxWalkSpeedCrouched", settings.movementSpeed) end
    -- Jump height grows with the square of the launch speed.
    applyOverride(jumpOverride, settings.jumpHeight ~= 1, movement, "JumpZVelocity", math.sqrt(settings.jumpHeight))
    -- Instant Sprint: full speed the moment you start running (no speed-up phase). On the ground
    -- only: in the air the huge acceleration would steer away the momentum of jumps and swings.
    local mode = Unreal.TryNumber(function() return movement.MovementMode end)
    local onGround = mode == Game.MOVEMENT_MODE.WALKING or mode == Game.MOVEMENT_MODE.NAV_WALKING
    applyOverride(accelerationOverride, walking and onGround and settings.instantSprint, movement, "MaxAcceleration", INSTANT_ACCELERATION)
end

local appliedGameSpeed = 1

local function applyGameSpeed()
    local gameSpeed = App.settings.gameSpeed or 1
    if gameSpeed == appliedGameSpeed then return end
    local statics, player = Unreal.GameplayStatics(), Game.Player()
    if isValid(statics) and player and try(function()
        statics:SetGlobalTimeDilation(player, gameSpeed)
        return true
    end) then
        appliedGameSpeed = gameSpeed
    end
end

-- ---------------------------------------------------------------------------

function Movement.Tick()
    if App.settings.noClip ~= Shared.noClipActive then setNoClip(App.settings.noClip) end
    local movement = Game.Movement()
    if movement then
        if Shared.noClipActive then flyWithNoClip(movement) end
        applyMovementOverrides(movement)
    end
    applyToggleSprint()
    applyGameSpeed()
end

Unreal.OnWorldReset(function()
    speedOverride:release()
    jumpOverride:release()
    accelerationOverride:release()
    flyOverride:release()
    appliedGameSpeed = 1
    Shared.noClipActive = false
end)

return Movement
