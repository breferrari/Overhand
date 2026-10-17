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
local Defense = require("features.defense")
local Movement = require("features.movement")
local Combat = require("features.combat")
local Resources = require("features.resources")
local Buffs = require("features.buffs")
local Give = require("features.give")
local DevActions = require("features.dev_actions")
local SavedValues = require("features.saved_values")

local Cheats = {}

local SETTLE_SECONDS = 2               -- after William appears, before anything is applied
local SAVED_VALUES_TIMEOUT = 10        -- the cheats stop waiting for the saved-values check after this
local SAVED_VALUES_RETRY = 0.5

local FEATURES = {
    { name = "dev actions", tick = DevActions.Tick },
    { name = "health", tick = Health.Tick },
    { name = "damage taken", tick = Defense.Tick },
    { name = "resources", tick = Resources.Tick },
    { name = "movement", tick = Movement.Tick },
    { name = "combat", tick = Combat.Tick },
    { name = "buffs", tick = Buffs.Tick },
}

local session = {
    readyAt = 0,                  -- nothing is applied before then (the world is still loading)
    playerAddress = nil,          -- the William the per-world state belongs to
    savedValuesChecked = false,
    savedValuesDeadline = 0,
    nextSavedValuesTryAt = 0,
    brokenWeaponsChecked = false,
}

Unreal.OnWorldReset(function()
    session.savedValuesChecked = false
    session.brokenWeaponsChecked = false
end)

-- The saved-values check must run before any feature touches attributes; it is retried until the
-- attribute sets are readable. Returns true once the features may run.
local function checkSavedValues()
    if session.savedValuesChecked then return true end
    if os.clock() < session.nextSavedValuesTryAt then return false end
    session.nextSavedValuesTryAt = os.clock() + SAVED_VALUES_RETRY
    local ok, allChecked = Log.Guarded("check saved values", SavedValues.Check)
    local done = ok and allChecked == true
    if done or os.clock() >= session.savedValuesDeadline then
        if not done then Log.Info("saved values: attribute sets not readable, continuing without the check") end
        session.savedValuesChecked = true
    end
    return session.savedValuesChecked
end

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
        session.readyAt = os.clock() + SETTLE_SECONDS
        session.savedValuesDeadline = session.readyAt + SAVED_VALUES_TIMEOUT
        State.status = "Ready"
        return
    end

    if not checkSavedValues() then return end
    if not session.brokenWeaponsChecked then
        session.brokenWeaponsChecked = Unreal.Try(Give.RemoveBrokenWeapons) == true
    end
    for _, feature in ipairs(FEATURES) do Log.Guarded(feature.name, feature.tick) end
end

-- A map is loading: wait for it. The new William resets the world state when he appears; the same
-- William after a restart resets it too (overrides hand back their vanilla values, see Override:release).
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
