-- ValorianSheet / ui/game_menus.lua
-- Is one of the game's own menus open (pause, inventory, lantern, death screen, ...)? They bring
-- their own cursor, and ours must not open on top of them.
--
-- The game creates these widgets once and keeps them, so the widgets found are kept (a per-world
-- cache) and checked directly afterwards. A menu class without a widget yet is searched for at most
-- once a minute, and only when the player presses the menu key, never per tick.

local Unreal = require("lib.unreal")
local Game = require("game")

local GameMenus = {}

local try = Unreal.Try

local MENU_CLASSES = {
    "WBP_PauseMenu_C", "WBP_PanelSettings_C", "WBP_PlayerInventory_C", "WBP_LanternMenu_C",
    "WBP_ProgressionMenu_C", "WBP_PlayerJournal_C", "WBP_PlayerQuests_C", "WBP_FastTravel_C",
    "WBP_SaveManager_C", "WBP_DeathScreen_C", "WBP_PlayerArsenal_C", "WBP_PlayerStorage_C",
    "WBP_MessageBox_C",
}
local SEARCH_INTERVAL = 60

local function isShowing(widget)
    local activated = try(function() return widget:IsActivated() end)
    if activated ~= nil then return activated end
    return try(function() return widget:IsInViewport() and widget:IsVisible() end) == true
end

local function findOpen(widgetsOf)
    for _, className in ipairs(MENU_CLASSES) do
        for _, widget in ipairs(widgetsOf(className)) do
            if isShowing(widget) then return widget, className end
        end
    end
    return nil
end

-- Only the widgets found so far (cheap; used while our menu is open).
function GameMenus.FindOpenKnown()
    return findOpen(function(className) return Unreal.GetCachedList("gameMenu_" .. className) end)
end

-- Also searches for menu classes without a widget yet (at most once a minute each). For the menu key.
function GameMenus.FindOpen()
    return findOpen(function(className) return Unreal.FindAllCached("gameMenu_" .. className, className, SEARCH_INTERVAL) end)
end

function GameMenus.IsGamePaused()
    local statics, controller = Game.GameplayStatics(), Game.Controller()
    return controller ~= nil and try(function() return statics:IsGamePaused(controller) end) == true
end

return GameMenus
