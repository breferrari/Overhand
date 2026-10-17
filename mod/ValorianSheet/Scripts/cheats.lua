-- ValorianSheet / cheats.lua
-- Runs every feature module once per tick, and resets the world state when William changes (a new
-- save, a map change, a respawn). Feature modules register their own per-world reset with
-- Unreal.OnWorldReset; Unreal.ResetWorld runs them all.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Settings = require("settings")
local Health = require("features.health")
local Movement = require("features.movement")
local Combat = require("features.combat")
local Resources = require("features.resources")
local Buffs = require("features.buffs")
local Give = require("features.give")
local DevActions = require("features.dev_actions")
local SavedValues = require("features.saved_values")

local Cheats = {}

local session = {
    readyAt = 0,                  -- nothing is applied before then (the world is still loading)
    playerAddress = nil,          -- the William the per-world state belongs to
    savedValuesChecked = false,
    brokenWeaponsChecked = false,
}

Unreal.OnWorldReset(function()
    session.savedValuesChecked = false
    session.brokenWeaponsChecked = false
end)

function Cheats.Tick()
    if os.clock() < session.readyAt then return end
    Game.BeginTick()
    local player = Game.Player()
    if not player then
        State.status = "Waiting for a loaded save..."
        session.playerAddress = nil
        return
    end
    local address = Unreal.AddressOf(player)
    if address ~= session.playerAddress then
        Log.Info("player found")
        Unreal.ResetWorld()
        session.playerAddress = address
        session.readyAt = os.clock() + 2
        State.status = "Ready"
        return
    end

    if not session.savedValuesChecked then
        session.savedValuesChecked = true
        Log.Guarded("check saved values", SavedValues.Check)
    end
    if not session.brokenWeaponsChecked then
        session.brokenWeaponsChecked = Unreal.Try(Give.RemoveBrokenWeapons) == true
    end

    DevActions.Tick()
    Health.Tick()
    Resources.Tick()
    Movement.Tick()
    Combat.Tick()
    Buffs.Tick()
end

-- A map is loading: wait for it. The new William resets the world state when he appears (his
-- address differs), which is the single place the reset happens.
function Cheats.OnWorldChange(reason)
    Log.Debug("world change: " .. tostring(reason))
    session.playerAddress = nil
    session.readyAt = os.clock() + 3
end

-- Every cheat back to vanilla (the features restore the game's values on their next tick).
function Cheats.TurnEverythingOff()
    for key, value in pairs(State.defaults) do
        if not State.NOT_A_CHEAT[key] then State.settings[key] = value end
    end
    Settings.MarkDirty()
    State.status = "Everything is back to vanilla"
    Log.Info("everything turned off")
end

return Cheats
