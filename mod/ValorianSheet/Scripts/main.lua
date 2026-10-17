-- main.lua
-- Entry point (UE4SS loads Scripts/main.lua). Loads the game's module, which defines the app and
-- registers its features and menu, then drives everything from one game-thread loop.
-- Layout and rules: docs/ARCHITECTURE.md. Bringing the menu to another game: docs/PORTING.md.

local GAME = "valormortis"   -- games/<GAME>/init.lua

require("games." .. GAME .. ".init")

local Log = require("core.log")
local Settings = require("core.settings")
local Runner = require("core.runner")
local Menu = require("core.ui.menu")

Log.StartSession()
Settings.Load()
Menu.BindKeys()

pcall(RegisterLoadMapPreHook, function() Runner.OnWorldChange("load map") end)
pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function() Runner.OnWorldChange("client restart") end)

-- Everything runs on the game thread (no LoopAsync): Lua is not thread-safe, and an async loop next
-- to game-thread hooks corrupts the Lua state. The loop function is kept in a global so the garbage
-- collector cannot collect it.
ModTick = function()
    Log.Guarded("menu", Menu.Tick)
    Log.Guarded("tick", Runner.Tick)
    Log.Guarded("save settings", Settings.SaveIfDirty)
end
ModTickHandle = LoopInGameThreadWithDelay(33, ModTick)

Log.Info("loaded, press F5 or L3 + R3 in game")
