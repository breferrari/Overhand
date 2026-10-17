-- ValorianSheet / features/dev_actions.lua
-- What still works of the developers' cheat manager: its Blueprint cheat actions (gems, ability
-- unlocks) and the engine's ability-cost toggle (No Ability Costs).

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")

local DevActions = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local function findAction(actionName)
    local cheatManager = Game.CheatManager()
    local actions = cheatManager and try(function() return cheatManager.CheatActions end)
    local found = nil
    try(function()
        actions:ForEach(function(_, element)
            local action = element:get()
            if not found and isValid(action) and try(function() return action.ActionName:ToString() end) == actionName then
                found = action
            end
        end)
    end)
    return found
end

local function runAction(actionName)
    local action = findAction(actionName)
    if not action then
        Log.Info("dev action '" .. actionName .. "' not found")
        return false
    end
    local ok, err = pcall(function() action:PerformAction() end)
    Log.Info("dev action '" .. actionName .. "' " .. (ok and "performed" or ("failed: " .. tostring(err))))
    return ok
end

-- Runs several actions; the status line says how many went through.
function DevActions.RunAll(actionNames, label)
    local done = 0
    for _, actionName in ipairs(actionNames) do
        if runAction(actionName) then done = done + 1 end
    end
    State.status = label .. ": " .. done .. "/" .. #actionNames .. " done"
end

-- ---------------------------------------------------------------------------
-- No Ability Costs: the engine's GAS cheat (its toggle works in release builds). Our own record of
-- the state decides; the console variable is only logged (it is not reliable to re-toggle from).
-- ---------------------------------------------------------------------------

local abilityCostsIgnored = false
local lastToggleAt = -math.huge

function DevActions.Tick()
    local wanted = State.settings.noAbilityCosts == true
    if abilityCostsIgnored == wanted or os.clock() - lastToggleAt < 1.5 then return end
    lastToggleAt = os.clock()
    if Game.CallDevCheat("IgnoreCostsToggle") then
        abilityCostsIgnored = wanted
        Log.Debug("AbilitySystem.IgnoreCosts now reads " .. tostring(Game.ReadConsoleBool("AbilitySystem.IgnoreCosts")))
    end
end

function DevActions.Describe()
    return "AbilitySystem.IgnoreCosts reads " .. tostring(Game.ReadConsoleBool("AbilitySystem.IgnoreCosts"))
end

return DevActions
