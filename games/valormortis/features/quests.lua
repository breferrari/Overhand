-- games/valormortis/features/quests.lua
-- The Quests tab: the active quests with what their current step asks for, read from the world's
-- QuestSubsystem (GameQuests: tag -> quest, ActiveQuests). Read only: finishing or resetting a quest
-- from outside breaks the game's quest system (its EndQuest / ResetQuest expect state only the
-- quest's own triggers set up).
-- The list is built when the tab first needs it after a load, and again on Refresh.
-- WriteReport dumps the quests' structure (by reflection) to find how a step links to the items it
-- needs, for a quest helper.
-- (Found by Valor Mortis Cheat Menu 1.4.0; not yet confirmed in game here.)

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")
local Paths = require("core.paths")
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

-- Menu options: the active quests, A-Z.
local NOT_LOADED = { { label = "(load a save first)", value = nil } }
local NONE_ACTIVE = { { label = "(no active quest)", value = nil } }

function Quests.Options()
    if cache.options then return cache.options end
    local subsystem = Game.Player() and questSubsystem()
    if not subsystem then return NOT_LOADED end
    local byTag, options, total = readQuests(subsystem), {}, 0
    for tag, quest in pairs(byTag) do
        total = total + 1
        if quest.active and not quest.completed then options[#options + 1] = { label = quest.title, value = tag } end
    end
    if total == 0 then return NOT_LOADED end
    table.sort(options, function(a, b) return a.label:lower() < b.label:lower() end)
    cache.options, cache.byTag = #options > 0 and options or NONE_ACTIVE, byTag
    Log.Info("quests: " .. #options .. " active of " .. total)
    return cache.options
end

-- The chosen quest: its state and what its current step asks for.
function Quests.Describe(tag)
    local quest = tag and cache.byTag and cache.byTag[tag]
    if not quest then return "" end
    local step = try(function() return quest.object.CurrentQuestStep.StepDescription:ToString() end)
    return stateText(quest) .. ((step and step ~= "") and (": " .. step) or "")
end

-- How many quests are active (for the tab's info line), or nil before the list was read.
function Quests.ActiveCount()
    local options = cache.options
    if not options then return nil end
    return options == NONE_ACTIVE and 0 or #options
end

-- ---------------------------------------------------------------------------
-- The quest report: what the game's quest objects hold, read by reflection (property names, types,
-- values one level deep), plus every quest action object with its owner chain and item tags.
-- ---------------------------------------------------------------------------

local MAX_ARRAY_ITEMS = 12

local function describeValue(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" or kind == "string" then return tostring(value) end
    if kind ~= "userdata" and kind ~= "table" then return kind end
    local text = try(function() return value:ToString() end)
    if type(text) == "string" then return '"' .. text .. '"' end
    local fullName = try(function() return value:GetFullName() end)
    if type(fullName) == "string" then return fullName end
    local count = Unreal.TryNumber(function() return value:GetArrayNum() end)
    if count then
        local items = {}
        try(function()
            value:ForEach(function(index, element)
                if index <= MAX_ARRAY_ITEMS then items[#items + 1] = describeValue(try(function() return element:get() end)) end
            end)
        end)
        return "[" .. count .. "] " .. table.concat(items, ", ")
    end
    local tag = try(function() return value.TagName:ToString() end)
    if type(tag) == "string" then return "tag " .. tag end
    return "(struct)"
end

-- Every property of object: "  Name (Type) = value".
local function dumpProperties(lines, object, indent)
    local class = try(function() return object:GetClass() end)
    if not class then return end
    try(function()
        class:ForEachProperty(function(property)
            local name = try(function() return property:GetFName():ToString() end) or "?"
            local typeName = try(function() return property:GetClass():GetFName():ToString() end) or "?"
            local value = try(function() return object[name] end)
            lines[#lines + 1] = indent .. name .. " (" .. typeName .. ") = " .. describeValue(value)
        end)
    end)
end

local function ownerChain(object)
    local names, current = {}, object
    for _ = 1, 6 do
        current = try(function() return current:GetOuter() end)
        local name = current and try(function() return current:GetFullName() end)
        if not name then break end
        names[#names + 1] = name
    end
    return table.concat(names, "  <  ")
end

local QUEST_ACTION_CLASSES = { "QuestAction", "QuestAction_GrantItems", "QuestAction_RemoveItems" }
local QUEST_PIECE_CLASSES = { "QuestStep", "QuestObjective", "QuestCondition", "QuestTrigger" }

function Quests.WriteReport()
    local subsystem = Game.Player() and questSubsystem()
    if not subsystem then
        App.status = "Load a save first"
        return
    end
    local lines, byTag = { "# Overhand quest report: active quests and the quest objects around them", "" }, readQuests(subsystem)
    for tag, quest in pairs(byTag) do
        if quest.active and not quest.completed then
            lines[#lines + 1] = "== " .. quest.title .. "  [" .. tag .. "]  " .. stateText(quest)
            lines[#lines + 1] = "  object: " .. (try(function() return quest.object:GetFullName() end) or "?")
            dumpProperties(lines, quest.object, "  ")
            local step = try(function() return quest.object.CurrentQuestStep end)
            if step then
                lines[#lines + 1] = "  -- current step: " .. describeValue(step)
                if try(function() return step:GetClass() end) then dumpProperties(lines, step, "    ") end
            end
            lines[#lines + 1] = ""
        end
    end
    for _, className in ipairs(QUEST_ACTION_CLASSES) do
        local found = Unreal.FindAllLive(className)
        lines[#lines + 1] = "== " .. className .. ": " .. #found .. " objects"
        for _, action in ipairs(found) do
            lines[#lines + 1] = "  " .. (try(function() return action:GetFullName() end) or "?")
            lines[#lines + 1] = "    owners: " .. ownerChain(action)
            lines[#lines + 1] = "    items: " .. table.concat(Gas.TagNamesIn(try(function() return action.ItemTags end)), ", ")
            if className == "QuestAction" then dumpProperties(lines, action, "    ") end
        end
        lines[#lines + 1] = ""
    end
    for _, className in ipairs(QUEST_PIECE_CLASSES) do
        local found = Unreal.FindAllLive(className)
        lines[#lines + 1] = "== " .. className .. ": " .. #found .. " objects"
        for index, piece in ipairs(found) do
            if index > 3 then break end   -- a sample is enough to see the shape
            lines[#lines + 1] = "  " .. (try(function() return piece:GetFullName() end) or "?")
            dumpProperties(lines, piece, "    ")
        end
        lines[#lines + 1] = ""
    end
    local fileName = App.name .. "-Quests.txt"
    local ok = Paths.WriteFile(Paths.InModFolder(fileName), table.concat(lines, "\n") .. "\n")
    Log.Info("quest report: " .. #lines .. " lines written to " .. fileName)
    App.status = ok and ("Quest report saved to " .. fileName) or ("Could not write " .. fileName)
end

function Quests.Refresh()
    cache.options, cache.byTag = nil, nil
    Quests.Options()
end

Unreal.OnWorldReset(function() cache.options, cache.byTag = nil, nil end)

return Quests
