-- core/runner.lua
-- The per-tick loop for the game's features. The game registers:
--   Runner.Configure { identity = function() -> the player character or nil, ... }
--   Runner.AddFeature(name, tick)          applies settings every tick (each guarded on its own)
--   Runner.AddWorldCheck(name, check, giveUpSeconds)
--                                          once per world: retried every tick until check() returns
--                                          true, or until giveUpSeconds have passed (nil: no limit)
--   Runner.OnTickStart(fn)                 runs first in every tick (e.g. a per-tick snapshot)
-- When the identity object changes (a new save, a map change, a respawn into a new character) the
-- world is reset (Unreal.ResetWorld), which runs every module's Unreal.OnWorldReset callback.

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")

local Runner = {}

local config = {
    identity = function() return nil end,
    settleSeconds = 2,          -- after the character appears, before anything is applied
    worldChangeSeconds = 3,     -- after a map starts loading
    waitingStatus = "Waiting for a loaded save...",
    readyStatus = "Ready",
}
local features = {}         -- { name, tick }
local worldChecks = {}      -- { name, check, giveUpSeconds, done, giveUpAt }
local tickStartHooks = {}

local session = { readyAt = 0, identityAddress = nil }

function Runner.Configure(options)
    for key, value in pairs(options) do config[key] = value end
end

function Runner.AddFeature(name, tick) features[#features + 1] = { name = name, tick = tick } end
function Runner.OnTickStart(fn) tickStartHooks[#tickStartHooks + 1] = fn end

function Runner.AddWorldCheck(name, check, giveUpSeconds)
    worldChecks[#worldChecks + 1] = { name = name, check = check, giveUpSeconds = giveUpSeconds, done = false }
end

local function startWorld()
    Unreal.ResetWorld()
    session.readyAt = os.clock() + config.settleSeconds
    for _, worldCheck in ipairs(worldChecks) do
        worldCheck.done = false
        worldCheck.giveUpAt = worldCheck.giveUpSeconds and (session.readyAt + worldCheck.giveUpSeconds) or math.huge
    end
    App.status = config.readyStatus
end

local function runWorldChecks()
    for _, worldCheck in ipairs(worldChecks) do
        if not worldCheck.done then
            local ok, done = Log.Guarded(worldCheck.name, worldCheck.check)
            worldCheck.done = ok and done == true
            if not worldCheck.done and os.clock() >= worldCheck.giveUpAt then
                Log.Info(worldCheck.name .. ": could not run, skipped for this world")
                worldCheck.done = true
            end
        end
    end
end

function Runner.Tick()
    if os.clock() < session.readyAt then return end
    for _, hook in ipairs(tickStartHooks) do hook() end
    local identity = config.identity()
    if not identity then
        App.status = config.waitingStatus
        session.identityAddress = nil
        return
    end
    local address = Unreal.AddressOf(identity)
    if address ~= session.identityAddress then
        Log.Info("player found")
        session.identityAddress = address
        startWorld()
        return
    end
    runWorldChecks()
    for _, feature in ipairs(features) do Log.Guarded(feature.name, feature.tick) end
end

-- A map is loading: wait for it. The character that appears next starts a new world.
function Runner.OnWorldChange(reason)
    Log.Debug("world change: " .. tostring(reason))
    session.identityAddress = nil
    session.readyAt = os.clock() + config.worldChangeSeconds
end

return Runner
