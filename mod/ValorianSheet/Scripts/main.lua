-- ValorianSheet / main.lua
-- Entry point (UE4SS loads Scripts/main.lua). Loads the settings, builds the menu and drives
-- everything from one game-thread loop. Layout and rules: docs/ARCHITECTURE.md.

local Log = require("lib.log")
local Game = require("game")
local Settings = require("settings")
local Cheats = require("cheats")
local Menu = require("ui.menu")
local Sheet = require("ui.sheet")

Log.StartSession(Game.NAME .. " v" .. Game.VERSION)
Settings.Load()
Sheet.Build()
Menu.BindKeys()

local function onWorldChange(reason) Cheats.OnWorldChange(reason) end
pcall(RegisterLoadMapPreHook, function() onWorldChange("load map") end)
pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function() onWorldChange("client restart") end)

-- Everything runs on the game thread (no LoopAsync): Lua is not thread-safe, and an async loop next
-- to game-thread hooks corrupts the Lua state. The loop function is kept in a global so the garbage
-- collector cannot collect it.
ValorianSheetTick = function()
    Log.Guarded("menu", Menu.Tick)
    Log.Guarded("tick", Cheats.Tick)
    Log.Guarded("save settings", Settings.SaveIfDirty)
end
ValorianSheetTickHandle = LoopInGameThreadWithDelay(33, ValorianSheetTick)

Log.Info("loaded, press F5 in game")
