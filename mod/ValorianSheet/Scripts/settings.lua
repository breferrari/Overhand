-- ValorianSheet / settings.lua
-- Persistence: settings.cfg (settings, debug logging, attribute ledger) and teleports.txt.
-- Both are plain text in the mod folder. On the first start, the Valor Mortis Cheat Menu's
-- config.json and teleports.txt are imported if that mod is installed next to this one.

local Log = require("lib.log")
local Paths = require("lib.paths")
local State = require("state")

local Settings = {}

Settings.FILE = Paths.InModFolder("settings.cfg")
Settings.TELEPORTS_FILE = Paths.InModFolder("teleports.txt")

local function readFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("a")
    file:close()
    return content
end

local function writeFile(path, content)
    local ok, err = pcall(function()
        local file = assert(io.open(path, "w"))
        file:write(content)
        file:close()
    end)
    if not ok then Log.Info("could not write " .. path .. ": " .. tostring(err)) end
end

-- Converts text to the type of the default value; nil when it does not fit.
local function parseValue(text, defaultValue)
    if type(defaultValue) == "boolean" then
        if text == "true" then return true end
        if text == "false" then return false end
        return nil
    end
    return tonumber(text)
end

local function applySetting(key, text)
    local defaultValue = State.defaults[key]
    if defaultValue == nil or State.SESSION_ONLY[key] then return end
    local value = parseValue(text, defaultValue)
    if value ~= nil then State.settings[key] = value end
end

-- ---------------------------------------------------------------------------
-- settings.cfg
-- ---------------------------------------------------------------------------

function Settings.Save()
    local lines = { "# ValorianSheet settings. Changed from the in-game menu (F6)." }
    local keys = {}
    for key in pairs(State.settings) do
        if not State.SESSION_ONLY[key] then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do lines[#lines + 1] = key .. "=" .. tostring(State.settings[key]) end
    lines[#lines + 1] = "debugLogging=" .. tostring(Log.debugEnabled)
    for attributeName, recorded in pairs(State.attributeLedger) do
        lines[#lines + 1] = string.format("ledger.%s=%s,%s", attributeName, tostring(recorded.vanilla), tostring(recorded.written))
    end
    writeFile(Settings.FILE, table.concat(lines, "\n") .. "\n")
end

local function loadSettingsFile(content)
    for line in content:gmatch("[^\r\n]+") do
        local key, text = line:match("^%s*([%w%.]+)%s*=%s*(.-)%s*$")
        if key == "debugLogging" then
            Log.debugEnabled = text == "true"
        elseif key and key:find("^ledger%.") then
            local vanilla, written = text:match("^([^,]+),([^,]+)$")
            if tonumber(vanilla) and tonumber(written) then
                State.attributeLedger[key:sub(#"ledger." + 1)] = { vanilla = tonumber(vanilla), written = tonumber(written) }
            end
        elseif key then
            applySetting(key, text)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Import from the Valor Mortis Cheat Menu (config.json, flat keys + attrLedger)
-- ---------------------------------------------------------------------------

local CHEAT_MENU_KEYS = {
    godMode = "godMode", infStamina = "infiniteStamina", staminaOutOfCombat = "staminaOnlyOutOfCombat",
    infBlood = "infiniteNephtoglobin", fallDamage = "fallDamage", dmgTaken = "damageTaken",
    maxHealthMult = "maxHealthFactor", regenRate = "regenRate", regenDelay = "regenDelay",
    regenOutOfCombat = "regenOnlyOutOfCombat", speedMult = "movementSpeed", jumpMult = "jumpHeight",
    gameSpeed = "gameSpeed", toggleSprint = "toggleSprint", instantSprint = "instantSprint",
    oneHit = "oneHitKills", dmgMult = "damageMultiplier", alwaysParry = "perfectParry",
    parryMult = "parryWindow", dodgeMult = "dodgeWindow", infAmmo = "infiniteAmmo",
    infFlasks = "infiniteFlasks", infConsumables = "infiniteConsumables", infBuffs = "infiniteBuffs",
    noCooldown = "noItemCooldowns", keepCatalysts = "keepCatalysts", ignoreCosts = "noAbilityCosts",
}

local function importCheatMenuConfig(json)
    for oldKey, text in json:gmatch('"(%w+)"%s*:%s*([%w%.%-%+]+)') do
        if CHEAT_MENU_KEYS[oldKey] then applySetting(CHEAT_MENU_KEYS[oldKey], text) end
        if oldKey == "noFall" and text == "true" then State.settings.fallDamage = 0 end
        if oldKey == "debugLog" then Log.debugEnabled = text == "true" end
    end
    local ledgerBlock = json:match('"attrLedger"%s*:%s*(%b{})')
    if ledgerBlock then
        for attributeName, entry in ledgerBlock:gmatch('"(%w+)"%s*:%s*(%b{})') do
            local vanilla = tonumber(entry:match('"vanilla"%s*:%s*([%d%.%-eE]+)'))
            local written = tonumber(entry:match('"written"%s*:%s*([%d%.%-eE]+)'))
            if vanilla and written then State.attributeLedger[attributeName] = { vanilla = vanilla, written = written } end
        end
    end
end

-- ---------------------------------------------------------------------------
-- teleports.txt: one line per slot, slot|map|x|y|z|yaw|name (same format as the Cheat Menu's)
-- ---------------------------------------------------------------------------

local function parseTeleports(content)
    local teleports = {}
    for line in content:gmatch("[^\r\n]+") do
        local slot, map, x, y, z, yaw, name = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if slot then
            teleports[slot] = {
                map = map ~= "" and map or nil,
                x = tonumber(x), y = tonumber(y), z = tonumber(z),
                yaw = tonumber(yaw),
                name = name ~= "" and name or nil,
            }
        end
    end
    return teleports
end

function Settings.SaveTeleports()
    local lines = {}
    for slot = 1, 9 do
        local position = State.teleports[tostring(slot)]
        if type(position) == "table" then
            local name = (position.name or ""):gsub("[|\r\n]", " ")
            lines[#lines + 1] = string.format("%d|%s|%s|%s|%s|%s|%s", slot, position.map or "",
                tostring(position.x or ""), tostring(position.y or ""), tostring(position.z or ""),
                tostring(position.yaw or ""), name)
        end
    end
    writeFile(Settings.TELEPORTS_FILE, table.concat(lines, "\n") .. "\n")
end

-- ---------------------------------------------------------------------------

function Settings.Load()
    local content = readFile(Settings.FILE)
    if content then
        loadSettingsFile(content)
    else
        local cheatMenuConfig = readFile(Paths.CHEAT_MENU_FOLDER .. "config.json")
        if cheatMenuConfig then
            importCheatMenuConfig(cheatMenuConfig)
            Log.Info("imported settings from the Valor Mortis Cheat Menu")
        end
        Settings.Save()
    end

    local teleports = readFile(Settings.TELEPORTS_FILE)
    if not teleports then
        teleports = readFile(Paths.CHEAT_MENU_FOLDER .. "teleports.txt")
        if teleports then Log.Info("imported teleports from the Valor Mortis Cheat Menu") end
    end
    State.teleports = teleports and parseTeleports(teleports) or {}
    if teleports and not Paths.Exists(Settings.TELEPORTS_FILE) then Settings.SaveTeleports() end
end

return Settings
