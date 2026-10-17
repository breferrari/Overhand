-- ValorianSheet / main.lua
-- Entry point (UE4SS loads Scripts/main.lua). Wires settings, the cheats and the menu together and
-- drives everything from one game-thread loop.
--
-- Layout:
--   lib/        logging, file paths, safe Unreal access + cached lookups, overrides with restore
--   game.lua    access to Valor Mortis (player, attribute sets, subsystems, dev cheat manager)
--   state.lua   settings and runtime state shared by the menu and the features
--   features/   one module per feature group, each with Tick and Reset
--   cheats.lua  runs the features every tick and resets them on world changes
--   settings.lua persistence (settings.cfg, teleports.txt)
--   ui/         the menu: widgets, input, game-menu detection, framework, and its content (sheet)

local Log = require("lib.log")
local Game = require("game")

Log.StartSession(Game.NAME .. " v" .. Game.VERSION)

local State = require("state")
local Settings = require("settings")
local Cheats = require("cheats")
local Menu = require("ui.menu")
local Sheet = require("ui.sheet")

Settings.Load()
State.onLedgerChanged = Settings.Save
State.onTeleportsChanged = Settings.SaveTeleports

Menu.onSettingChanged = function(key, value)
    Log.Info("menu: " .. key .. " -> " .. tostring(value))
    Settings.Save()
end
Sheet.Build(Settings.Save)
Menu.BindKeys()

local function onWorldChange(reason)
    Log.Guarded("world change", Cheats.OnWorldChange, reason)
    Log.Guarded("menu world change", Menu.OnWorldChange)
end
pcall(RegisterLoadMapPreHook, function() onWorldChange("load map") end)
pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function() onWorldChange("client restart") end)

-- Everything runs on the game thread (no LoopAsync): Lua is not thread-safe, and an async loop next
-- to game-thread hooks corrupts the Lua state. The loop function is kept in a global so the garbage
-- collector cannot collect it.
local nextTickErrorLogAt = 0
local function tracebackOf(err) return debug.traceback(tostring(err), 2) end

ValorianSheetTick = function()
    Log.Guarded("menu", Menu.Tick)
    local ok, err = xpcall(Cheats.Tick, tracebackOf)
    if not ok and State.clock() >= nextTickErrorLogAt then
        nextTickErrorLogAt = State.clock() + 5
        Log.Info("ERROR in tick: " .. tostring(err))
    end
end
ValorianSheetTickHandle = LoopInGameThreadWithDelay(33, ValorianSheetTick)

Log.Info("loaded, press F6 in game")
