-- Valor Mortis Cheat Menu
-- Author: BryanHudson
-- One menu for all cheats. Uses the game's own developer cheat manager where it exists,
-- plus our own attribute-based cheats as a fallback and for the extras.
-- Menu UI: ModMenu by Matthew Arvidson (MIT), see LICENSE-ModMenu.txt.
--
-- Bug reports: Misc tab -> "Write Bug Report" creates ValorCheatMenu-BugReport.txt in this folder.
-- ValorCheatMenu.log (this session) and ValorCheatMenu.log.old (last session) are written always;
-- "Debug Logging" in the Misc tab adds detailed lines.

local MENU_KEY = Key.F6
local MENU_KEY_NAME = "F6"

local G = require("game")
G.StartLog()

local C = require("cheats")

-- ModMenu must get the crash-safe UEHelpers before it loads.
G.InstallSafeUEHelpers()
local ModMenu = require("ModMenu")
local Config = ModMenu.ConfigManager

-- ---------------------------------------------------------------------------
-- Settings (Mods/ValorCheatMenu/config.json)
-- ---------------------------------------------------------------------------

-- Not restored on start: you would load into a save flying through walls.
-- invisible: not in 1.0 (enemies still notice the player), kept off until it works.
local SESSION_ONLY = { noClip = true, invisible = true }

local defaults = { dock = "left", debugLog = false }
for k, v in pairs(C.want) do defaults[k] = v end
G.Safe("config init", Config.Init, { id = "ValorCheatMenu", defaults = defaults })

for k, v in pairs(C.want) do
    local saved = G.Try(Config.Get, k)
    if type(saved) == type(v) and not SESSION_ONLY[k] then C.want[k] = saved end
end
G.debugOn = G.Try(Config.Get, "debugLog") == true

-- 1.3.0: "No Fall Damage" became the "Fall Damage" setting (0 % = no fall damage).
if C.want.noFall then
    C.want.noFall = false
    C.want.fallDamage = 0
    pcall(Config.Set, "noFall", false)
    pcall(Config.Set, "fallDamage", 0)
end

-- Saved teleport positions: own file teleports.txt, one line per slot
-- (slot|map|x|y|z|yaw|name). Older test builds kept them in config.json.
local TP_FILE = G.MOD_DIR .. "teleports.txt"
local function loadTeleports()
    local t = {}
    local f = io.open(TP_FILE, "r")
    if f then
        for line in f:lines() do
            local slot, map, x, y, z, yaw, name = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
            if slot then
                t[slot] = { map = map ~= "" and map or nil, x = tonumber(x), y = tonumber(y), z = tonumber(z),
                    yaw = tonumber(yaw), name = name ~= "" and name or nil }
            end
        end
        f:close()
        return t
    end
    local old = G.Try(Config.Get, "teleports")
    return type(old) == "table" and old or t
end
C.teleports = loadTeleports()
C.onTeleportsChange = function(t)
    local ok, err = pcall(function()
        local f = assert(io.open(TP_FILE, "w"))
        for slot = 1, 9 do
            local e = t[tostring(slot)]
            if type(e) == "table" then
                local name = (e.name or ""):gsub("[|\r\n]", " ")
                f:write(string.format("%d|%s|%s|%s|%s|%s|%s\n", slot, e.map or "", tostring(e.x or ""), tostring(e.y or ""),
                    tostring(e.z or ""), tostring(e.yaw or ""), name))
            end
        end
        f:close()
    end)
    if not ok then G.Log("teleports: could not save (" .. tostring(err) .. ")") end
end

-- Values we wrote into attributes the game saves (see Override:attr in cheats.lua).
local ledger = G.Try(Config.Get, "attrLedger")
C.ledger = type(ledger) == "table" and ledger or {}
C.onLedgerChange = function(l)
    local copy = {}
    for k, v in pairs(l) do copy[k] = v end
    pcall(Config.Set, "attrLedger", next(copy) and copy or nil)
end

local function settingsLine()
    local keys, parts = {}, {}
    for k in pairs(C.want) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = C.want[k]
        if v ~= false and v ~= 1 then parts[#parts + 1] = k .. "=" .. tostring(v) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "all off"
end
G.Log("settings at start: " .. settingsLine() .. (G.debugOn and " | debug logging ON" or ""))

local function save(key, value)
    if C.want[key] ~= value then
        G.Log("menu: " .. key .. " -> " .. tostring(value))
    end
    C.want[key] = value
    if not SESSION_ONLY[key] then pcall(Config.Set, key, value) end
end

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Game menus (pause, inventory, lantern, ...): they bring their own cursor. Our menu and a game
-- menu must not be open at the same time, both would fight over the mouse cursor.
-- ---------------------------------------------------------------------------

local GAME_MENUS = {
    "WBP_PauseMenu_C", "WBP_PanelSettings_C", "WBP_PlayerInventory_C", "WBP_LanternMenu_C",
    "WBP_ProgressionMenu_C", "WBP_PlayerJournal_C", "WBP_PlayerQuests_C", "WBP_FastTravel_C",
    "WBP_SaveManager_C", "WBP_DeathScreen_C", "WBP_PlayerArsenal_C", "WBP_PlayerStorage_C",
    "WBP_MessageBox_C",
}

local function activeGameMenu()
    for _, cls in ipairs(GAME_MENUS) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            local name = G.Try(function() return w:GetFullName() end) or ""
            if G.Valid(w) and not name:find("Default__", 1, true) then
                local on = G.Try(function() return w:IsActivated() end)
                if on == nil then
                    on = G.Try(function() return w:IsInViewport() and w:IsVisible() end)
                end
                if on == true then return w, cls end
            end
        end
    end
    return nil
end

ModMenu.Init({
    title = "VALOR MORTIS CHEAT MENU",
    instanceId = "ValorCheatMenu",
    key = MENU_KEY,
    keyHint = MENU_KEY_NAME,
    keyName = MENU_KEY_NAME,
    dock = G.Try(Config.Get, "dock") or "left",
    theme = "dark",
    tabs = { "Player", "Combat", "Items", "Misc" },
    ignoreLook = true,
    consoleCommand = "cheatmenu",
    canOpen = function()
        local _, cls = activeGameMenu()
        if cls then
            G.Debug("menu not opened, game menu is open: " .. cls)
            return false, "Close the game menu first, then press " .. MENU_KEY_NAME
        end
        return true
    end,
    debug = G.debugOn,
    colors = {
        textAccent = { R = 0.78, G = 0.10, B = 0.10, A = 1.0 },
    },
})

ModMenu.OnDockChange(function(side) pcall(Config.Set, "dock", side) end)

local function toggle(id, label)
    return {
        type = "checkbox",
        id = id,
        label = label,
        default = C.want[id] == true,
        onChange = function(on) save(id, on == true) end,
    }
end

local function multiplier(id, label, values)
    local options = {}
    for _, v in ipairs(values) do
        table.insert(options, { label = (v == 1 and "1x (vanilla)" or (tostring(v) .. "x")), value = tostring(v) })
    end
    return {
        type = "dropdown",
        id = id,
        label = label,
        options = options,
        default = tostring(C.want[id] or 1),
        onChange = function(value)
            local n = tonumber(value)
            if n then save(id, n) end
        end,
    }
end

local function action(id, label, fn, confirm, variant)
    return {
        type = "button",
        id = id,
        label = label,
        variant = variant,
        confirm = confirm,
        onClick = function()
            G.Log("menu: button " .. id)
            G.Safe("button " .. id, fn)
        end,
    }
end

-- Player ---------------------------------------------------------------------

ModMenu.Register({
    id = "Survival",
    title = "Survival",
    tab = "Player",
    items = {
        toggle("godMode", "God Mode"),
        toggle("infStamina", "Infinite Stamina"),
        toggle("staminaOutOfCombat", "Infinite Stamina only out of combat"),
        toggle("infBlood", "Infinite Nephtoglobin"),
        toggle("noClip", "NoClip (Space up, Ctrl down)"),
        {
            type = "dropdown",
            id = "fallDamage",
            label = "Fall Damage",
            options = {
                { label = "100% (vanilla)", value = "1" }, { label = "75%", value = "0.75" }, { label = "50%", value = "0.5" },
                { label = "25%", value = "0.25" }, { label = "0% (no fall damage)", value = "0" },
            },
            default = tostring(C.want.fallDamage or 1),
            onChange = function(value) local n = tonumber(value) if n then save("fallDamage", n) end end,
        },
        {
            type = "dropdown",
            id = "dmgTaken",
            label = "Damage Taken",
            options = {
                { label = "100% (vanilla)", value = "1" }, { label = "75%", value = "0.75" }, { label = "50%", value = "0.5" },
                { label = "25%", value = "0.25" }, { label = "10%", value = "0.1" },
            },
            default = tostring(C.want.dmgTaken or 1),
            onChange = function(value) local n = tonumber(value) if n then save("dmgTaken", n) end end,
        },
        multiplier("maxHealthMult", "Max Health", { 1, 1.5, 2, 3, 5 }),
        {
            type = "dropdown",
            id = "regenRate",
            label = "Health Regeneration",
            options = {
                { label = "Off (vanilla)", value = "0" }, { label = "1% per second", value = "0.01" },
                { label = "2% per second", value = "0.02" }, { label = "5% per second", value = "0.05" },
                { label = "10% per second", value = "0.1" },
            },
            default = tostring(C.want.regenRate or 0),
            onChange = function(value) local n = tonumber(value) if n then save("regenRate", n) end end,
        },
        {
            type = "dropdown",
            id = "regenDelay",
            label = "Regeneration starts after a hit",
            options = {
                { label = "right away", value = "0" }, { label = "2 seconds", value = "2" },
                { label = "5 seconds", value = "5" }, { label = "10 seconds", value = "10" },
            },
            default = tostring(C.want.regenDelay or 2),
            onChange = function(value) local n = tonumber(value) if n then save("regenDelay", n) end end,
        },
        toggle("regenOutOfCombat", "Health Regeneration only out of combat"),
    },
})

ModMenu.Register({
    id = "Movement",
    title = "Movement",
    tab = "Player",
    items = {
        multiplier("speedMult", "Movement Speed", { 1, 1.25, 1.5, 2, 3, 5 }),
        multiplier("jumpMult", "Jump Height", { 1, 1.5, 2, 3, 5, 10 }),
        multiplier("gameSpeed", "Game Speed", { 0.25, 0.5, 0.75, 1, 1.5, 2 }),
        toggle("toggleSprint", "Toggle Sprint (keyboard)"),
        toggle("instantSprint", "Instant Sprint (full speed at once)"),
    },
})

local function teleportRow(slot)
    local saved = C.teleports[tostring(slot)]
    return {
        type = "row",
        items = {
            {
                type = "textinput",
                id = "posName" .. slot,
                label = tostring(slot),
                default = type(saved) == "table" and type(saved.name) == "string" and saved.name or "",
                placeholder = "Name it...",
                maxLength = 24,
                fieldWidth = 150,
                labelWidth = 20,
                onChange = function(text) C.RenamePosition(slot, text) end,
            },
            action("savePos" .. slot, "Save", function() C.SavePosition(slot) end, nil, "info"),
            action("goPos" .. slot, "Teleport", function() C.TeleportTo(slot) end, nil, "primary"),
        },
    }
end

ModMenu.Register({
    id = "Teleport",
    title = "Teleport",
    tab = "Player",
    items = {
        { type = "label", label = "Name a spot, press Save where you stand, Teleport back any time (kept per area)." },
        teleportRow(1),
        teleportRow(2),
        teleportRow(3),
        teleportRow(4),
        teleportRow(5),
    },
})

-- Combat ---------------------------------------------------------------------

ModMenu.Register({
    id = "Combat",
    title = "Combat",
    tab = "Combat",
    items = {
        toggle("oneHit", "One-Hit Kills"),
        toggle("alwaysParry", "Every Block Is A Perfect Parry"),
        {
            type = "dropdown",
            id = "parryMult",
            label = "Parry Window",
            options = {
                { label = "0.5x (harder)", value = "0.5" }, { label = "0.75x (harder)", value = "0.75" },
                { label = "1x (vanilla)", value = "1" }, { label = "1.5x", value = "1.5" }, { label = "2x", value = "2" },
                { label = "4x", value = "4" }, { label = "6x", value = "6" },
            },
            default = tostring(C.want.parryMult or 1),
            onChange = function(value) local n = tonumber(value) if n then save("parryMult", n) end end,
        },
        {
            type = "dropdown",
            id = "dodgeMult",
            label = "Dodge Window",
            options = {
                { label = "0.5x (harder)", value = "0.5" }, { label = "0.75x (harder)", value = "0.75" },
                { label = "1x (vanilla)", value = "1" }, { label = "1.5x", value = "1.5" }, { label = "2x", value = "2" },
                { label = "3x", value = "3" }, { label = "4x", value = "4" },
            },
            default = tostring(C.want.dodgeMult or 1),
            onChange = function(value) local n = tonumber(value) if n then save("dodgeMult", n) end end,
        },
        multiplier("dmgMult", "Damage Multiplier", { 1, 1.5, 2, 3, 5, 10 }),
        { type = "separator" },
        action("killNearby", "Kill All Enemies Nearby", function() C.KillNearby() end,
            { title = "Kill all enemies nearby?", message = "Kills every enemy within 60 m.", confirmLabel = "Kill" }, "danger"),
    },
})

-- Items ----------------------------------------------------------------------

ModMenu.Register({
    id = "Resources",
    title = "Resources",
    tab = "Items",
    items = {
        toggle("infAmmo", "Infinite Ammo (no reload)"),
        toggle("infFlasks", "Infinite Healing Flasks"),
        toggle("infConsumables", "Infinite Consumables"),
        toggle("infBuffs", "Infinite Buffs (potions, coatings, pistol boosts)"),
        toggle("noCooldown", "No Item Cooldowns"),
        toggle("keepCatalysts", "Keep Catalysts On Death"),
        toggle("ignoreCosts", "No Ability Costs"),
        { type = "separator" },
        action("refill", "Refill Everything", function() C.RefillAll() end, nil, "primary"),
    },
})

ModMenu.Register({
    id = "Give",
    title = "Give",
    tab = "Items",
    items = {
        action("cat1k", "+1,000 Catalysts", function() C.AddCatalysts(1000) end, nil, "success"),
        action("cat10k", "+10,000 Catalysts", function() C.AddCatalysts(10000) end, nil, "success"),
        action("materials", "+99 Upgrade Materials", function() C.AddMaterials(99) end, nil, "success"),
        action("consumables", "+5 Of Every Consumable", function() C.AddConsumables(5) end, nil, "success"),
        { type = "separator" },
        action("weapons", "Unlock All Weapons", function() C.UnlockWeapons() end,
            { title = "Unlock all weapons?", message = "Adds every weapon to this save. This can not be undone.", confirmLabel = "Unlock" }, "warning"),
        action("abilities", "Unlock All Abilities", function()
            C.Actions({ "Unlock Grappling", "Unlock Stasis", "Unlock Neptho Interactions", "Unlock Leveling Up" }, "Abilities")
        end, { title = "Unlock all abilities?", message = "Unlocks every ability on this save. This can not be undone.", confirmLabel = "Unlock" }, "warning"),
        action("gems", "Unlock All Gems", function() C.Actions({ "Unlock all gems" }, "Gems") end,
            { title = "Unlock all gems?", message = "Adds every gem to this save. This can not be undone.", confirmLabel = "Unlock" }, "warning"),
    },
})

-- Give Item: one item of your choice, any amount.
local giveCategory = "Consumables"
local giveLoaded = false

local function giveOptions()
    local cat = C.ItemCatalog()
    return cat and cat[giveCategory] or nil
end

local function fillGiveList()
    local opts = giveOptions()
    if not opts then return false end
    pcall(ModMenu.SetOptions, "GiveItem", "item", opts, false)
    return true
end

local categoryOptions = {}
for _, c in ipairs(C.ITEM_CATEGORIES) do categoryOptions[#categoryOptions + 1] = c.key end

ModMenu.Register({
    id = "GiveItem",
    title = "Give Item",
    tab = "Items",
    items = {
        {
            type = "dropdown",
            id = "category",
            label = "Category",
            options = categoryOptions,
            default = giveCategory,
            onChange = function(value)
                if not value or value == giveCategory then return end
                giveCategory = value
                G.Debug("give item: category " .. value)
                G.Safe("give item list", fillGiveList)
            end,
        },
        {
            type = "dropdown",
            id = "item",
            label = "Item",
            searchable = true,
            placeholder = "Load a save, then pick an item...",
            allowEmpty = true,
            maxVisible = 400,
            listMaxHeight = 320,
            options = { { label = "(load a save first)", value = "" } },
            onExpand = function()
                if not giveLoaded then giveLoaded = G.Safe("give item list", fillGiveList) == true end
            end,
        },
        { type = "number", id = "count", label = "Amount", default = 5, min = 1, max = 999, integer = true },
        action("giveItem", "Give", function()
            C.GiveItem(ModMenu.Get("GiveItem", "item"), ModMenu.Get("GiveItem", "count"))
        end, nil, "success"),
    },
})

-- Misc -----------------------------------------------------------------------

local TOGGLES = {
    Survival = { "godMode", "infStamina", "staminaOutOfCombat", "infBlood", "noClip", "regenOutOfCombat" },
    Movement = { "toggleSprint", "instantSprint" },
    Combat = { "oneHit", "alwaysParry" },
    Resources = { "infAmmo", "infFlasks", "infConsumables", "infBuffs", "noCooldown", "keepCatalysts", "ignoreCosts" },
}

ModMenu.Register({
    id = "Misc",
    title = "Misc",
    tab = "Misc",
    items = {
        { type = "label", id = "status", label = C.status },
        action("reset", "Turn Everything Off", function()
            C.ResetAll()
            for k, v in pairs(C.want) do pcall(Config.Set, k, v) end
            for section, ids in pairs(TOGGLES) do
                for _, id in ipairs(ids) do pcall(ModMenu.Set, section, id, false) end
            end
            pcall(ModMenu.Set, "Movement", "speedMult", "1")
            pcall(ModMenu.Set, "Movement", "jumpMult", "1")
            pcall(ModMenu.Set, "Movement", "gameSpeed", "1")
            pcall(ModMenu.Set, "Combat", "dmgMult", "1")
            pcall(ModMenu.Set, "Survival", "dmgTaken", "1")
            pcall(ModMenu.Set, "Survival", "maxHealthMult", "1")
            pcall(ModMenu.Set, "Combat", "parryMult", "1")
            pcall(ModMenu.Set, "Combat", "dodgeMult", "1")
            pcall(ModMenu.Set, "Survival", "fallDamage", "1")
            pcall(ModMenu.Set, "Survival", "regenRate", "0")
            pcall(ModMenu.Set, "Survival", "regenDelay", "2")
            G.Log("everything turned off")
        end, { title = "Turn everything off?", message = "Sets every cheat back to vanilla.", confirmLabel = "Turn off" }, "danger"),
    },
})

ModMenu.Register({
    id = "Support",
    title = "Bug Reports",
    tab = "Misc",
    items = {
        { type = "label", label = "Found a bug? Press Write Bug Report and attach the file to your report." },
        action("report", "Write Bug Report", function() C.WriteBugReport() end, nil, "info"),
        {
            type = "checkbox",
            id = "debugLog",
            label = "Debug Logging (more detail in the log)",
            default = G.debugOn,
            onChange = function(on)
                G.debugOn = on == true
                pcall(Config.Set, "debugLog", G.debugOn)
                G.Log("debug logging " .. (G.debugOn and "ON" or "OFF"))
            end,
        },
        { type = "label", label = "Valor Mortis Cheat Menu v" .. G.VERSION .. " by BryanHudson" },
        { type = "label", label = "Menu UI: ModMenu by Matthew Arvidson (MIT)" },
    },
})

local lastStatus = nil
-- Loads the Give Item list once, a moment after the first menu open (heavier than one tick).
GiveLoadFn = function()
    if not giveLoaded then giveLoaded = G.Safe("give item list", fillGiveList) == true end
end
local giveLoadPending = false
local giveLoadAt = 0
GiveLoadWrapper = function()
    giveLoadPending = false
    GiveLoadFn()
end
ModMenu.OnOpen(function()
    lastStatus = nil
    G.Debug("menu opened")
    if not giveLoaded and not giveLoadPending then
        -- off the click stack: building the list is heavier than one tick
        -- runs from the main tick a moment later (no new UE4SS delayed action from inside a callback)
        giveLoadPending = true
        giveLoadAt = os.clock() + 0.05
    end
end)

-- ---------------------------------------------------------------------------
-- Loop
-- ---------------------------------------------------------------------------

pcall(RegisterLoadMapPreHook, function() G.Safe("map change", C.OnMapChange, "load map") end)
pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
    G.Safe("client restart", C.OnMapChange, "client restart")
end)

-- The whole mod runs on the game thread only (no LoopAsync): Lua is not thread-safe and an async
-- loop next to game-thread hooks/menus corrupts the Lua state (random UE4SS crashes).
-- The loop function is kept in a module-level variable so the Lua GC can not collect it.
local nextErrorLog = 0
local function onTickError(e) return debug.traceback(tostring(e), 2) end

-- A game menu opened while our menu is open (Esc): close ours and hand the cursor back to the game menu.
local nextMenuCheck = 0
local function watchGameMenus()
    if os.clock() < nextMenuCheck or not ModMenu.IsOpen() then return end
    nextMenuCheck = os.clock() + 0.1
    local w, cls = activeGameMenu()
    if not w then return end
    G.Log("game menu opened (" .. cls .. "), closing the cheat menu")
    pcall(ModMenu.Close)
    local pc = G.Controller()
    local lib = G.Static("/Script/UMG.Default__WidgetBlueprintLibrary")
    if pc then
        G.Try(function()
            pc.bShowMouseCursor = true
            pc.bEnableClickEvents = true
            pc.bEnableMouseOverEvents = true
        end)
        if G.Valid(lib) then
            local ok = G.Try(function() lib:SetInputMode_GameAndUIEx(pc, w, 0, false, false) return true end)
                or G.Try(function() lib:SetInputMode_GameAndUIEx(pc, w, 0, false) return true end)
            G.Debug("cursor handed back to " .. cls .. (ok and "" or " (input mode failed)"))
        end
        G.Try(function() w:SetFocus() end)
    end
end

TickFn = function()
    if giveLoadPending and os.clock() >= giveLoadAt then pcall(GiveLoadWrapper) end
    pcall(watchGameMenus)
    local ok, err = xpcall(C.Tick, onTickError)
    if not ok and os.clock() >= nextErrorLog then
        nextErrorLog = os.clock() + 5
        G.Log("ERROR in tick: " .. tostring(err))
    end
    if C.status ~= lastStatus and ModMenu.IsOpen() then
        lastStatus = C.status
        pcall(ModMenu.SetLabel, "Misc", "status", C.status)
    end
end
TickHandle = LoopInGameThreadWithDelay(33, TickFn)

G.Log("loaded, press " .. MENU_KEY_NAME .. " in game (console: cheatmenu)")
