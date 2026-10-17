-- ValorianSheet / settings.lua
-- Persistence: settings.cfg (settings and attribute ledger) and teleports.txt, plain text in the mod
-- folder. Anything that changes persisted state calls Settings.MarkDirty(); the main loop calls
-- Settings.SaveIfDirty() every tick, which writes at most once a second.

local Log = require("lib.log")
local Paths = require("lib.paths")
local State = require("state")

local Settings = {}

local SETTINGS_FILE = Paths.InModFolder("settings.cfg")
local TELEPORTS_FILE = Paths.InModFolder("teleports.txt")
local SAVE_INTERVAL = 1

local dirty = false
local nextSaveAt = 0

local function writeOrLog(path, content)
    local ok, err = Paths.WriteFile(path, content)
    if not ok then Log.Info("could not write " .. path .. ": " .. tostring(err)) end
end

-- Converts text to the type of the setting's default; nil when it does not fit.
local function applySetting(key, text)
    local defaultValue = State.defaults[key]
    if defaultValue == nil or State.SESSION_ONLY[key] then return end
    local value
    if type(defaultValue) == "boolean" then
        if text == "true" then value = true elseif text == "false" then value = false end
    else
        value = tonumber(text)
    end
    if value ~= nil then State.settings[key] = value end
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

-- 3.0 -> "3", 0.75 -> "0.75", true -> "true"
local function formatValue(value)
    return tostring(type(value) == "number" and math.tointeger(value) or value)
end

local function settingsText()
    local lines = { "# ValorianSheet settings. Changed from the in-game menu (F5)." }
    for _, key in ipairs(State.SortedSettingKeys()) do
        if not State.SESSION_ONLY[key] then lines[#lines + 1] = key .. "=" .. formatValue(State.settings[key]) end
    end
    for attributeName, recorded in pairs(State.attributeLedger) do
        lines[#lines + 1] = string.format("ledger.%s=%s,%s", attributeName, tostring(recorded.vanilla), tostring(recorded.written))
    end
    return table.concat(lines, "\n") .. "\n"
end

-- One line per slot: slot|map|x|y|z|yaw|name (the Valor Mortis Cheat Menu's format).
local function teleportsText()
    local slots = {}
    for slot in pairs(State.teleports) do slots[#slots + 1] = tonumber(slot) end
    table.sort(slots)
    local lines = {}
    for _, slot in ipairs(slots) do
        local position = State.teleports[tostring(slot)]
        local name = (position.name or ""):gsub("[|\r\n]", " ")
        lines[#lines + 1] = string.format("%d|%s|%s|%s|%s|%s|%s", slot, position.map or "",
            tostring(position.x or ""), tostring(position.y or ""), tostring(position.z or ""),
            tostring(position.yaw or ""), name)
    end
    return table.concat(lines, "\n") .. "\n"
end

local function saveNow()
    dirty = false
    nextSaveAt = os.clock() + SAVE_INTERVAL
    writeOrLog(SETTINGS_FILE, settingsText())
    writeOrLog(TELEPORTS_FILE, teleportsText())
end

function Settings.MarkDirty() dirty = true end

function Settings.SaveIfDirty()
    if dirty and os.clock() >= nextSaveAt then saveNow() end
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

local function loadSettings(content)
    for line in content:gmatch("[^\r\n]+") do
        local key, text = line:match("^%s*([%w%.]+)%s*=%s*(.-)%s*$")
        if key and key:find("^ledger%.") then
            local vanilla, written = text:match("^([^,]+),([^,]+)$")
            if tonumber(vanilla) and tonumber(written) then
                State.attributeLedger[key:sub(#"ledger." + 1)] = { vanilla = tonumber(vanilla), written = tonumber(written) }
            end
        elseif key then
            applySetting(key, text)
        end
    end
end

local function loadTeleports(content)
    for line in content:gmatch("[^\r\n]+") do
        local slot, map, x, y, z, yaw, name = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if slot then
            State.teleports[slot] = {
                map = map ~= "" and map or nil,
                x = tonumber(x), y = tonumber(y), z = tonumber(z),
                yaw = tonumber(yaw),
                name = name ~= "" and name or nil,
            }
        end
    end
end

function Settings.Load()
    local settings = Paths.ReadFile(SETTINGS_FILE)
    if not settings then
        saveNow() -- first start: write the defaults so the file is there to look at
        return
    end
    loadSettings(settings)
    loadTeleports(Paths.ReadFile(TELEPORTS_FILE) or "")
end

return Settings
