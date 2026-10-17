-- games/valormortis/features/progression.lua
-- Free Respec: resetting your upgrades in the lantern's level-up menu costs catalysts per level
-- (CharacterProgressionDatabase.RespecCosts, a map level -> cost). While the option is on every cost
-- is 0. The database is a game asset: nothing is saved, and the costs it had come back when the
-- option is switched off. The database is looked up at most every 5 s until found, then kept.
-- (Found by Valor Mortis Cheat Menu 1.4.0; not yet confirmed in game here.)

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")

local Progression = {}

local try = Unreal.Try

-- originalCosts: level -> cost, while ours are written; checkAt: the next look at the costs
local respec = { database = nil, originalCosts = nil, checkAt = 0 }
local CHECK_INTERVAL = 2

local function progressionDatabase()
    return Unreal.FindCached("progressionDatabase", "CharacterProgressionDatabase", 5)
end

local function readCosts(database)
    local costs, count = {}, 0
    try(function()
        database.RespecCosts:ForEach(function(levelParam, costParam)
            local level, cost = try(function() return levelParam:get() end), try(function() return costParam:get() end)
            if level ~= nil and type(cost) == "number" then
                costs[level] = cost
                count = count + 1
            end
        end)
    end)
    return costs, count
end

-- costOf(level, cost) -> the cost to write.
local function writeCosts(database, costOf)
    try(function()
        database.RespecCosts:ForEach(function(levelParam, costParam)
            local level = try(function() return levelParam:get() end)
            local cost = try(function() return costParam:get() end)
            local wanted = costOf(level, cost)
            if wanted ~= nil and wanted ~= cost then costParam:set(wanted) end
        end)
    end)
end

local function zero() return 0 end

local function restoreCosts()
    local database, original = respec.database, respec.originalCosts
    respec.originalCosts = nil
    if not (Unreal.IsValid(database) and original) then return end
    writeCosts(database, function(level) return original[level] end)
    Log.Info("free respec off: respec costs back")
end

function Progression.Tick()
    if not App.settings.freeRespec then
        if respec.originalCosts then restoreCosts() end
        return
    end
    if os.clock() < respec.checkAt then return end
    respec.checkAt = os.clock() + CHECK_INTERVAL
    local database = progressionDatabase()
    if not database then return end
    if not respec.originalCosts or Unreal.AddressOf(database) ~= Unreal.AddressOf(respec.database) then
        local costs, count = readCosts(database)
        if count == 0 then
            Log.Limited("free respec", 1, "free respec: the respec costs are not readable")
            return
        end
        respec.database, respec.originalCosts = database, costs
        Log.Info("free respec: " .. count .. " respec costs set to 0")
    end
    writeCosts(database, zero)   -- every check: undoes a reload of the asset
end

return Progression
