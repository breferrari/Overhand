-- ValorianSheet / settings.lua
-- Persistence: settings.cfg (settings and attribute ledger) and teleports.txt, plain text in the mod
-- folder. Anything that changes persisted state calls Settings.MarkDirty(); the main loop calls
-- Settings.SaveIfDirty() every tick, which writes at most once a second.
--
-- On the first start (no settings.cfg yet) the settings of the Valor Mortis Cheat Menu (config.json,
-- teleports.txt) and of AeonGreyh's Passive Health Regen (PassiveHealthRegen.cfg) are imported if
-- those mods are installed next to this one.

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
    local lines = { "# ValorianSheet settings. Changed from the in-game menu (F6)." }
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

-- Returns the raw key -> text pairs it read (for migrations).
local function loadSettings(content)
    local raw = {}
    for line in content:gmatch("[^\r\n]+") do
        local key, text = line:match("^%s*([%w%.]+)%s*=%s*(.-)%s*$")
        if key and key:find("^ledger%.") then
            local vanilla, written = text:match("^([^,]+),([^,]+)$")
            if tonumber(vanilla) and tonumber(written) then
                State.attributeLedger[key:sub(#"ledger." + 1)] = { vanilla = tonumber(vanilla), written = tonumber(written) }
            end
        elseif key then
            raw[key] = text
            applySetting(key, text)
        end
    end
    return raw
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

-- ---------------------------------------------------------------------------
-- First start: import from other mods
-- ---------------------------------------------------------------------------

-- Valor Mortis Cheat Menu config.json key -> ours. Its Health Regeneration (a share of max health)
-- has no equivalent here; regeneration comes from Passive Health Regen's settings instead.
local CHEAT_MENU_KEYS = {
    godMode = "godMode", infStamina = "infiniteStamina", staminaOutOfCombat = "staminaOnlyOutOfCombat",
    infBlood = "infiniteNephtoglobin", fallDamage = "fallDamage", dmgTaken = "damageTaken",
    maxHealthMult = "maxHealthFactor", speedMult = "movementSpeed", jumpMult = "jumpHeight",
    gameSpeed = "gameSpeed", toggleSprint = "toggleSprint", instantSprint = "instantSprint",
    oneHit = "oneHitKills", dmgMult = "damageMultiplier", alwaysParry = "perfectParry",
    parryMult = "parryWindow", dodgeMult = "dodgeWindow", infAmmo = "infiniteAmmo",
    infFlasks = "infiniteFlasks", infConsumables = "infiniteConsumables", infBuffs = "infiniteBuffs",
    noCooldown = "noItemCooldowns", keepCatalysts = "keepCatalysts", ignoreCosts = "noAbilityCosts",
    debugLog = "debugLogging",
}

local function importCheatMenu()
    local json = Paths.ReadFile(Paths.CHEAT_MENU_FOLDER .. "config.json")
    if json then
        for oldKey, text in json:gmatch('"(%w+)"%s*:%s*([%w%.%-%+]+)') do
            if CHEAT_MENU_KEYS[oldKey] then applySetting(CHEAT_MENU_KEYS[oldKey], text) end
            if oldKey == "noFall" and text == "true" then State.settings.fallDamage = 0 end
        end
        local ledgerBlock = json:match('"attrLedger"%s*:%s*(%b{})')
        for attributeName, entry in (ledgerBlock or ""):gmatch('"(%w+)"%s*:%s*(%b{})') do
            local vanilla = tonumber(entry:match('"vanilla"%s*:%s*([%d%.%-eE]+)'))
            local written = tonumber(entry:match('"written"%s*:%s*([%d%.%-eE]+)'))
            if vanilla and written then State.attributeLedger[attributeName] = { vanilla = vanilla, written = written } end
        end
        Log.Info("imported settings from the Valor Mortis Cheat Menu")
    end
    local teleports = Paths.ReadFile(Paths.CHEAT_MENU_FOLDER .. "teleports.txt")
    if teleports then
        loadTeleports(teleports)
        Log.Info("imported teleports from the Valor Mortis Cheat Menu")
    end
end

local function importPassiveHealthRegen()
    local cfg = Paths.ReadFile(Paths.PASSIVE_REGEN_FOLDER .. "PassiveHealthRegen.cfg")
    if not cfg then return end
    local values = {}
    for key, number in cfg:gmatch("(%w+)%s*=%s*(-?[%d%.]+)") do values[key] = tonumber(number) end
    local enabled = (values.Enabled or 0) > 0
    State.settings.regenPerSecond = enabled and (values.HealthPerSecond or 5) or 0
    State.settings.regenDelay = values.DelayAfterDamage or State.settings.regenDelay
    State.settings.regenMaxPercent = values.MaxPercent or State.settings.regenMaxPercent
    State.settings.regenOnlyOutOfCombat = (values.OutOfCombatOnly or 0) > 0
    Log.Info("imported settings from Passive Health Regen")
end

-- settings.cfg from 1.0.0 (regeneration was a share of max health, "regenRate"): take Passive
-- Health Regen's settings if it is installed (the 1.1.0 install switched it off), otherwise turn an
-- enabled old regeneration into its default of 5 health per second.
local function migrateFrom100(raw)
    if raw.regenPerSecond then return end
    importPassiveHealthRegen()
    if State.settings.regenPerSecond == 0 and (tonumber(raw.regenRate) or 0) > 0 then
        State.settings.regenPerSecond = 5
    end
    Log.Info("settings: migrated Health Regeneration from 1.0.0")
    Settings.MarkDirty()
end

function Settings.Load()
    local settings = Paths.ReadFile(SETTINGS_FILE)
    if settings then
        migrateFrom100(loadSettings(settings))
        loadTeleports(Paths.ReadFile(TELEPORTS_FILE) or "")
        return
    end
    importCheatMenu()
    importPassiveHealthRegen()
    saveNow()
end

return Settings
