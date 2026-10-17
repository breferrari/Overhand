-- ValorianSheet / ui/game_menus.lua
-- Is one of the game's own menus open (pause, inventory, lantern, death screen, ...)? They bring
-- their own cursor, and ours must not open on top of them.
--
-- The game creates these widgets once and keeps them, so every widget found is kept and checked
-- directly afterwards. A menu class that has no widget yet is searched for at most once a minute,
-- and only when the player presses the menu key, never per tick.

local Unreal = require("lib.unreal")
local Game = require("game")
local State = require("state")

local GameMenus = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local MENU_CLASSES = {
    "WBP_PauseMenu_C", "WBP_PanelSettings_C", "WBP_PlayerInventory_C", "WBP_LanternMenu_C",
    "WBP_ProgressionMenu_C", "WBP_PlayerJournal_C", "WBP_PlayerQuests_C", "WBP_FastTravel_C",
    "WBP_SaveManager_C", "WBP_DeathScreen_C", "WBP_PlayerArsenal_C", "WBP_PlayerStorage_C",
    "WBP_MessageBox_C",
}
local SEARCH_INTERVAL = 60

local knownWidgets = {}      -- class name -> list of widgets
local nextSearchAt = {}      -- class name -> clock time

local function isShowing(widget)
    local activated = try(function() return widget:IsActivated() end)
    if activated ~= nil then return activated end
    return try(function() return widget:IsInViewport() and widget:IsVisible() end) == true
end

local function liveWidgets(className)
    local alive = {}
    for _, widget in ipairs(knownWidgets[className] or {}) do
        if isValid(widget) then alive[#alive + 1] = widget end
    end
    knownWidgets[className] = alive
    return alive
end

-- Only the widgets found so far (cheap; used while our menu is open).
function GameMenus.FindOpenKnown()
    for _, className in ipairs(MENU_CLASSES) do
        for _, widget in ipairs(liveWidgets(className)) do
            if isShowing(widget) then return widget, className end
        end
    end
    return nil
end

-- Also searches for menu classes not found yet (at most once a minute each). Used on the menu key.
function GameMenus.FindOpen()
    local now = State.clock()
    for _, className in ipairs(MENU_CLASSES) do
        if #liveWidgets(className) == 0 and now >= (nextSearchAt[className] or 0) then
            nextSearchAt[className] = now + SEARCH_INTERVAL
            local found = {}
            for _, widget in ipairs(FindAllOf(className) or {}) do
                if Unreal.IsLiveObject(widget) then found[#found + 1] = widget end
            end
            knownWidgets[className] = found
        end
    end
    return GameMenus.FindOpenKnown()
end

function GameMenus.IsGamePaused()
    local statics, controller = Game.GameplayStatics(), Game.Controller()
    return controller ~= nil and try(function() return statics:IsGamePaused(controller) end) == true
end

-- After a map change every widget belonged to the old world.
function GameMenus.Reset()
    knownWidgets = {}
    nextSearchAt = {}
end

return GameMenus
