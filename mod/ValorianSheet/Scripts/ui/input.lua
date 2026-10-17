-- ValorianSheet / ui/input.lua
-- Keyboard and controller input for the menu, and the game's input while the menu is open.
--
-- Keyboard presses arrive through UE4SS key binds and are only queued here; the controller is
-- polled from the menu's tick. The menu handles both on the game thread, so no game object is
-- touched from a key callback.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")

local Input = {}

local try, isValid = Unreal.Try, Unreal.IsValid

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

-- Logs the first few controller commands, so a test shows whether presses reach us.
local function queueFromController(command)
    Log.Limited("controller", 20, "controller: " .. command)
    queue(command)
end

function Input.PollController(menuOpen)
    -- L3 + R3: L3 is read first, R3 only while L3 is held (one call per tick while closed)
    local toggleDown = Game.IsKeyDown(TOGGLE_BUTTONS[1]) and Game.IsKeyDown(TOGGLE_BUTTONS[2])
    if toggleDown and not toggleHeld then queueFromController("toggle") end
    toggleHeld = toggleDown
    if not menuOpen then
        held = {}
        return
    end
    local now = os.clock()
    for _, button in ipairs(MENU_BUTTONS) do
        if Game.IsKeyDown(button.key) then
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
-- While the menu is open the game gets no input: the player does not move or look around, game
-- menus do not open on Esc, and the mouse cursor is shown (for the sliders).
-- ---------------------------------------------------------------------------

local blocked = nil   -- { player, controller, uiInputMode }

function Input.BlockGame(controller)
    if blocked or not isValid(controller) then return end
    local player = Game.Player()
    if player then try(function() player:DisableInput(controller) end) end
    try(function() controller:SetIgnoreLookInput(true) end)
    try(function() controller:SetIgnoreMoveInput(true) end)
    try(function() controller.bShowMouseCursor = true end)
    local widgetLibrary = Game.WidgetLibrary()
    local uiInputMode = try(function() widgetLibrary:SetInputMode_UIOnlyEx(controller, nil, 0, true) return true end)
        or try(function() widgetLibrary:SetInputMode_UIOnlyEx(controller, nil, 0) return true end)
    blocked = { player = player, controller = controller, uiInputMode = uiInputMode == true }
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
    local widgetLibrary = Game.WidgetLibrary()
    if handOverTo then
        try(function() widgetLibrary:SetInputMode_GameAndUIEx(controller, handOverTo, 0, false, false) end)
        try(function() handOverTo:SetFocus() end)
        return
    end
    try(function() controller.bShowMouseCursor = false end)
    if state.uiInputMode then
        local ok = try(function() widgetLibrary:SetInputMode_GameOnly(controller, true) return true end)
        if not ok then try(function() widgetLibrary:SetInputMode_GameOnly(controller) end) end
    end
end

-- After a map change the controller is gone; nothing to restore.
function Input.Forget() blocked = nil end

return Input
