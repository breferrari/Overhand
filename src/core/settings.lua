-- core/settings.lua
-- Persistence, plain text in the mod folder:
--   settings.cfg   App.settings (key=value), plus lines other modules register with
--                  Settings.RegisterLines (e.g. the ledger as ledger.<name>=...)
--   extra files    whole files other modules register with Settings.RegisterFile (e.g. teleports.txt)
-- Anything that changes persisted state calls Settings.MarkDirty(); the main loop calls
-- Settings.SaveIfDirty() every tick, which writes at most once a second.

local App = require("core.app")
local Log = require("core.log")
local Paths = require("core.paths")

local Settings = {}

local SETTINGS_FILE = Paths.InModFolder("settings.cfg")
local SAVE_INTERVAL = 1

local dirty = false
local nextSaveAt = 0
local lineStores = {}   -- prefix -> { read(name, text), write() -> { name = text } }
local fileStores = {}   -- { path, read(content), write() -> content }

-- Lines in settings.cfg named "<prefix>.<name>=<text>".
function Settings.RegisterLines(prefix, store) lineStores[prefix] = store end

-- A file of its own in the mod folder.
function Settings.RegisterFile(fileName, store)
    fileStores[#fileStores + 1] = { path = Paths.InModFolder(fileName), read = store.read, write = store.write }
end

local function writeOrLog(path, content)
    local ok, err = Paths.WriteFile(path, content)
    if not ok then Log.Info("could not write " .. path .. ": " .. tostring(err)) end
end

-- 3.0 -> "3", 0.75 -> "0.75", true -> "true"
local function formatValue(value)
    return tostring(type(value) == "number" and math.tointeger(value) or value)
end

local function settingsText()
    local lines = { "# " .. App.name .. " settings. Changed from the in-game menu." }
    for _, key in ipairs(App.SortedSettingKeys()) do
        if not App.sessionOnly[key] then lines[#lines + 1] = key .. "=" .. formatValue(App.settings[key]) end
    end
    for prefix, store in pairs(lineStores) do
        for name, text in pairs(store.write()) do lines[#lines + 1] = prefix .. "." .. name .. "=" .. text end
    end
    return table.concat(lines, "\n") .. "\n"
end

local function saveNow()
    dirty = false
    nextSaveAt = os.clock() + SAVE_INTERVAL
    writeOrLog(SETTINGS_FILE, settingsText())
    for _, store in ipairs(fileStores) do writeOrLog(store.path, store.write()) end
end

function Settings.MarkDirty() dirty = true end

function Settings.SaveIfDirty()
    if dirty and os.clock() >= nextSaveAt then saveNow() end
end

-- Converts text to the type of the setting's default; ignores what does not fit.
local function applySetting(key, text)
    local defaultValue = App.defaults[key]
    if defaultValue == nil or App.sessionOnly[key] then return end
    local value
    if type(defaultValue) == "boolean" then
        if text == "true" then value = true elseif text == "false" then value = false end
    else
        value = tonumber(text)
    end
    if value ~= nil then App.settings[key] = value end
end

local function loadSettings(content)
    for line in content:gmatch("[^\r\n]+") do
        local key, text = line:match("^%s*([%w%.]+)%s*=%s*(.-)%s*$")
        local prefix, name = (key or ""):match("^(%w+)%.(.+)$")
        if prefix and lineStores[prefix] then
            lineStores[prefix].read(name, text)
        elseif key then
            applySetting(key, text)
        end
    end
end

-- Reads every file. First start (no settings.cfg): writes the defaults so the file is there to look at.
function Settings.Load()
    local settings = Paths.ReadFile(SETTINGS_FILE)
    if not settings then
        saveNow()
        return
    end
    loadSettings(settings)
    for _, store in ipairs(fileStores) do
        local content = Paths.ReadFile(store.path)
        if content then store.read(content) end
    end
end

return Settings
