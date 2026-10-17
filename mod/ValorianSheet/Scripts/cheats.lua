-- ValorianSheet / cheats.lua
-- Runs every feature module once per tick, and resets them when the world changes.
-- The features live in features/; each has a Tick (apply State.settings) and a Reset (forget
-- everything that belonged to the old world).

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Override = require("lib.override")
local Game = require("game")
local State = require("state")
local Health = require("features.health")
local Movement = require("features.movement")
local Combat = require("features.combat")
local Resources = require("features.resources")
local Buffs = require("features.buffs")
local Give = require("features.give")
local DevActions = require("features.dev_actions")
local SavedValues = require("features.saved_values")

local Cheats = {}

local clock = State.clock

local session = {
    readyAt = 0,                  -- nothing is applied before then (the world is still loading)
    playerAddress = nil,          -- the William the state below belongs to
    savedValuesChecked = false,
    brokenWeaponsChecked = false,
}

local function resetForNewWorld()
    Unreal.ResetCache()
    Health.Reset()
    Movement.Reset()
    Combat.Reset()
    Resources.Reset()
    Buffs.Reset()
    session.savedValuesChecked = false
    session.brokenWeaponsChecked = false
end

function Cheats.Tick()
    if clock() < session.readyAt then return end
    local player = Game.Player()
    if not player then
        State.status = "Waiting for a loaded save..."
        session.playerAddress = nil
        return
    end
    local address = Unreal.AddressOf(player)
    if address ~= session.playerAddress then
        session.playerAddress = address
        Log.Info("player found")
        resetForNewWorld()
        session.readyAt = clock() + 2
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
    Override.FlushLedger()
end

function Cheats.OnWorldChange(reason)
    Log.Debug("world change: " .. tostring(reason))
    resetForNewWorld()
    session.readyAt = clock() + 3
end

-- Every setting back to vanilla (the features restore the game's values on their next tick).
function Cheats.TurnEverythingOff()
    for key, value in pairs(State.defaults) do State.settings[key] = value end
    Log.Info("everything turned off")
end

-- Wraps a menu action that needs a loaded save.
function Cheats.RequiresSave(action)
    return function(...)
        if not Game.Player() then
            State.status = "Load a save first"
            return
        end
        return action(...)
    end
end

return Cheats
