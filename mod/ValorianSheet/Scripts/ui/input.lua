-- ValorianSheet / ui/input.lua
-- Keys and the game's input while the menu is open.
--
-- Key presses are only queued here; the menu handles them on the game thread in its tick, so no
-- game object is touched from the key callback.

local Unreal = require("lib.unreal")
local Game = require("game")

local Input = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local pendingCommands = {}

function Input.Bind(key, command)
    RegisterKeyBind(key, function()
        pendingCommands[#pendingCommands + 1] = command
    end)
end

-- The commands queued since the last call, oldest first.
function Input.TakePending()
    local commands = pendingCommands
    pendingCommands = {}
    return commands
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
