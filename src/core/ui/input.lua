-- core/ui/input.lua
-- Keyboard and controller input for the menu, and the game's input while the menu is open.
--
-- Keyboard presses arrive through UE4SS key binds and are only queued here; the controller is
-- polled from the menu's tick. The menu handles both on the game thread, so no game object is
-- touched from a key callback. The menu passes the player controller and character in through
-- Input.Configure.

local Unreal = require("core.unreal")
local Log = require("core.log")

local Input = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local config = {
    controller = function() return nil end,   -- the player controller
    player = function() return nil end,       -- the player character (its own input is disabled)
}

function Input.Configure(options)
    for key, value in pairs(options) do config[key] = value end
end

local pendingCommands = {}

local function queue(command) pendingCommands[#pendingCommands + 1] = command end

function Input.Bind(key, command)
    RegisterKeyBind(key, function() queue(command) end)
end

-- The commands queued since the last call, oldest first.
function Input.TakePending()
    local commands = pendingCommands
    pendingCommands = {}
    return commands
end

-- ---------------------------------------------------------------------------
-- Controller: L3 + R3 (both sticks clicked) opens and closes the menu. While it is open: D-pad
-- selects and changes (held: repeats), A uses, B closes, LB / RB switch tabs.
-- ---------------------------------------------------------------------------

local TOGGLE_BUTTONS = { "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick" }
local MENU_BUTTONS = {
    { key = "Gamepad_DPad_Up", command = "up", repeats = true },
    { key = "Gamepad_DPad_Down", command = "down", repeats = true },
    { key = "Gamepad_DPad_Left", command = "left", repeats = true },
    { key = "Gamepad_DPad_Right", command = "right", repeats = true },
    { key = "Gamepad_FaceButton_Bottom", command = "enter" },
    { key = "Gamepad_FaceButton_Right", command = "close" },
    { key = "Gamepad_LeftShoulder", command = "previousTab" },
    { key = "Gamepad_RightShoulder", command = "nextTab" },
}
local REPEAT_DELAY, REPEAT_INTERVAL = 0.4, 0.12

local toggleHeld = false
local held = {}            -- button key -> clock time of its next repeat (while held)

-- Logs the first controller commands, so a test shows whether presses reach us.
local function queueFromController(command)
    Log.Limited("controller", 20, "controller: " .. command)
    queue(command)
end

function Input.PollController(menuOpen)
    local controller = config.controller()
    -- L3 + R3: L3 is read first, R3 only while L3 is held (one call per tick while closed)
    local toggleDown = Unreal.IsKeyDown(controller, TOGGLE_BUTTONS[1]) and Unreal.IsKeyDown(controller, TOGGLE_BUTTONS[2])
    if toggleDown and not toggleHeld then queueFromController("toggleWithController") end
    toggleHeld = toggleDown
    if not menuOpen then
        held = {}
        return
    end
    local now = os.clock()
    for _, button in ipairs(MENU_BUTTONS) do
        if Unreal.IsKeyDown(controller, button.key) then
            local nextRepeatAt = held[button.key]
            if not nextRepeatAt then
                queueFromController(button.command)
                held[button.key] = now + REPEAT_DELAY
            elseif button.repeats and now >= nextRepeatAt then
                queueFromController(button.command)
                held[button.key] = now + REPEAT_INTERVAL
            end
        else
            held[button.key] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- While the menu is open the character does not move, look around or act: his own input is
-- disabled and the controller ignores move and look input.
--   Opened with the keyboard: UI-only input mode (no mouse cursor: nothing in the menu is clicked); game
--     menus do not open on Esc.
--   Opened with the controller: game-and-UI input mode, because in UI-only mode the game stops
--     processing controller buttons and the menu could not read them (tested in Valor Mortis). The
--     game's own controller actions (Start / pause) still work; a game menu that opens closes ours.
-- ---------------------------------------------------------------------------

local blocked = nil   -- { player, controller, changedInputMode }

local function setUiOnly(widgetLibrary, controller)
    return try(function() widgetLibrary:SetInputMode_UIOnlyEx(controller, nil, 0, true) return true end)
        or try(function() widgetLibrary:SetInputMode_UIOnlyEx(controller, nil, 0) return true end)
end

local function setGameAndUi(widgetLibrary, controller)
    return try(function() widgetLibrary:SetInputMode_GameAndUIEx(controller, nil, 0, false, false) return true end)
        or try(function() widgetLibrary:SetInputMode_GameAndUIEx(controller, nil, 0, false) return true end)
end

function Input.BlockGame(withController)
    local controller = config.controller()
    if blocked or not isValid(controller) then return end
    local player = config.player()
    if player then try(function() player:DisableInput(controller) end) end
    try(function() controller:SetIgnoreLookInput(true) end)
    try(function() controller:SetIgnoreMoveInput(true) end)
    local widgetLibrary = Unreal.WidgetLibrary()
    local changed = withController and setGameAndUi(widgetLibrary, controller) or setUiOnly(widgetLibrary, controller)
    blocked = { player = player, controller = controller, changedInputMode = changed == true }
end

-- handOverTo: a game menu that opened while ours was open; it gets the cursor and focus.
function Input.UnblockGame(handOverTo)
    local state = blocked
    blocked = nil
    if not state then return end
    local controller = state.controller
    if isValid(state.player) and isValid(controller) then try(function() state.player:EnableInput(controller) end) end
    if not isValid(controller) then return end
    try(function() controller:SetIgnoreLookInput(false) end)
    try(function() controller:SetIgnoreMoveInput(false) end)
    local widgetLibrary = Unreal.WidgetLibrary()
    if handOverTo then
        try(function() widgetLibrary:SetInputMode_GameAndUIEx(controller, handOverTo, 0, false, false) end)
        try(function() handOverTo:SetFocus() end)
        return
    end
    try(function() controller.bShowMouseCursor = false end)
    if state.changedInputMode then
        local ok = try(function() widgetLibrary:SetInputMode_GameOnly(controller, true) return true end)
        if not ok then try(function() widgetLibrary:SetInputMode_GameOnly(controller) end) end
    end
end

-- After a map change the controller is gone; nothing to restore.
function Input.Forget() blocked = nil end

return Input
