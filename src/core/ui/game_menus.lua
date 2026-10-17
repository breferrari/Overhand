-- core/ui/game_menus.lua
-- Is one of the game's own menus open (pause, inventory, death screen, ...)? They bring their own
-- cursor, and ours must not open on top of them. The game lists its menu widget classes with
-- GameMenus.Configure.
--
-- Games create these widgets once and keep them, so the widgets found are kept (a per-world cache)
-- and checked directly afterwards. A menu class without a widget yet is searched for at most once a
-- minute, and only when the player presses the menu key, never per tick.

local Unreal = require("core.unreal")

local GameMenus = {}

local try = Unreal.Try

local menuClasses = {}
local SEARCH_INTERVAL = 60

-- classNames: the game's menu widget classes, e.g. { "WBP_PauseMenu_C", ... }
function GameMenus.Configure(classNames) menuClasses = classNames end

local function isShowing(widget)
    local activated = try(function() return widget:IsActivated() end)
    if activated ~= nil then return activated end
    return try(function() return widget:IsInViewport() and widget:IsVisible() end) == true
end

local function findOpen(widgetsOf)
    for _, className in ipairs(menuClasses) do
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

function GameMenus.IsGamePaused(controller)
    local statics = Unreal.GameplayStatics()
    return controller ~= nil and try(function() return statics:IsGamePaused(controller) end) == true
end

return GameMenus
