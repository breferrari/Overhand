-- games/valormortis/features/quests.lua
-- The Quests tab: every quest of the game with its state and what its current step asks for, read
-- from the world's QuestSubsystem (GameQuests: tag -> quest, ActiveQuests). Read only: finishing or
-- resetting a quest from outside breaks the game's quest system (its EndQuest / ResetQuest expect
-- state only the quest's own triggers set up).
-- The list is built when the tab first needs it after a load, and again on Refresh.
-- (Found by Valor Mortis Cheat Menu 1.4.0; not yet confirmed in game here.)

local Unreal = require("core.unreal")
local Log = require("core.log")
local Game = require("game.game")
local Gas = require("gas.gas")

local Quests = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local cache = { options = nil, byTag = nil }

local function questSubsystem() return Unreal.FindCached("questSubsystem", "QuestSubsystem", 2) end

-- "Quests.Main.FindTheDoctor" -> "Find The Doctor" (when the quest has no title of its own)
local function readableTag(tag)
    local last = tag:match("([^%.]+)$") or tag
    return (last:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"))
end

local function stateText(quest)
    if quest.completed then return "done" end
    if quest.active then return "active, step " .. tostring((quest.step or 0) + 1) end
    return "not started"
end

-- tag -> { object, title, active, completed, step }
local function readQuests(subsystem)
    local active, quests = {}, {}
    try(function()
        subsystem.ActiveQuests:ForEach(function(keyParam)
            local tag = Gas.TagNameOf(keyParam)
            if tag then active[tag] = true end
        end)
    end)
    try(function()
        subsystem.GameQuests:ForEach(function(keyParam, questParam)
            local tag = Gas.TagNameOf(keyParam)
            local object = try(function() return questParam:get() end)
            if not (tag and isValid(object)) then return end
            local state = try(function() return object.PersistentState end)
            local title = try(function() return object.QuestTitle:ToString() end)
            quests[tag] = {
                object = object,
                title = (title and title ~= "") and title or readableTag(tag),
                active = active[tag] == true or (state ~= nil and try(function() return state.bQuestActive end) == true),
                completed = state ~= nil and try(function() return state.bQuestCompleted end) == true,
                step = state and Unreal.TryNumber(function() return state.CurrentQuestStepIndex end),
            }
        end)
    end)
    return quests
end

-- Menu options: active quests first, then not started, then done; each A-Z.
local NOT_LOADED = { { label = "(load a save first)", value = nil } }

function Quests.Options()
    if cache.options then return cache.options end
    local subsystem = Game.Player() and questSubsystem()
    if not subsystem then return NOT_LOADED end
    local byTag, options = readQuests(subsystem), {}
    for tag, quest in pairs(byTag) do
        local rank = quest.active and not quest.completed and 1 or (quest.completed and 3 or 2)
        options[#options + 1] = { label = quest.title .. " (" .. stateText(quest) .. ")", value = tag, rank = rank, title = quest.title }
    end
    if #options == 0 then return NOT_LOADED end
    table.sort(options, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.title:lower() < b.title:lower()
    end)
    cache.options, cache.byTag = options, byTag
    Log.Info("quests: " .. #options .. " in the game")
    return options
end

-- The chosen quest: its state and what its current step asks for.
function Quests.Describe(tag)
    local quest = tag and cache.byTag and cache.byTag[tag]
    if not quest then return "" end
    local step = try(function() return quest.object.CurrentQuestStep.StepDescription:ToString() end)
    return stateText(quest) .. ((step and step ~= "") and (": " .. step) or "")
end

function Quests.Refresh()
    cache.options, cache.byTag = nil, nil
    Quests.Options()
end

Unreal.OnWorldReset(function() cache.options, cache.byTag = nil, nil end)

return Quests
