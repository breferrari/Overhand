-- ValorCheatMenu / game.lua
-- Finding the player, the attribute sets and the game's own developer cheat manager.
-- Author: BryanHudson

local G = {}

G.TAG = "[ValorCheatMenu]"
G.VERSION = "1.3.2"

-- ---------------------------------------------------------------------------
-- Logging for bug reports
-- Everything goes to the UE4SS console/log AND to Mods/ValorCheatMenu/ValorCheatMenu.log.
-- The file is opened, appended and closed for every line so nothing is lost when the game crashes.
-- G.Debug lines are only written while "Debug Logging" is on in the menu.
-- ---------------------------------------------------------------------------

local scriptDir = (debug.getinfo(1, "S").source:match("^@(.*[\\/])")) or ""
G.MOD_DIR = scriptDir:gsub("[Ss]cripts[\\/]$", "")
G.LOG_FILE = G.MOD_DIR .. "ValorCheatMenu.log"
G.REPORT_FILE = G.MOD_DIR .. "ValorCheatMenu-BugReport.txt"
G.debugOn = false

local recent = {}       -- last lines, for the bug report
local RECENT_MAX = 150

local function writeLine(line)
    recent[#recent + 1] = line
    if #recent > RECENT_MAX then table.remove(recent, 1) end
    pcall(function()
        local f = io.open(G.LOG_FILE, "a")
        if f then
            f:write(line, "\n")
            f:close()
        end
    end)
end

function G.Log(msg)
    local line = os.date("%H:%M:%S") .. " " .. tostring(msg)
    print(G.TAG .. " " .. tostring(msg) .. "\n")
    writeLine(line)
end

function G.Debug(msg)
    if G.debugOn then G.Log("[debug] " .. tostring(msg)) end
end

function G.RecentLines() return recent end

-- New session: keep one old log, start a fresh one.
function G.StartLog()
    pcall(function()
        local f = io.open(G.LOG_FILE, "r")
        if f then
            f:close()
            os.remove(G.LOG_FILE .. ".old")
            os.rename(G.LOG_FILE, G.LOG_FILE .. ".old")
        end
    end)
    writeLine("==== Valor Mortis Cheat Menu v" .. G.VERSION .. " | session " .. os.date("%Y-%m-%d %H:%M:%S") .. " ====")
end

-- Runs fn and logs any error with a stack trace (where = what was running).
function G.Safe(where, fn, ...)
    local ok, a, b = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, ...)
    if not ok then
        G.Log("ERROR in " .. where .. ": " .. tostring(a))
        return nil
    end
    return a, b
end

function G.Try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

function G.Valid(obj)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj:IsValid() end)
    return ok and v == true
end

function G.Addr(obj)
    return G.Try(function() return obj:GetAddress() end)
end

local function notDefault(obj)
    local name = G.Try(function() return obj:GetFullName() end)
    return name ~= nil and not name:find("Default__", 1, true)
end

-- ---------------------------------------------------------------------------
-- Player
-- ---------------------------------------------------------------------------

local cache = {}

function G.ResetCache()
    cache = {}
end

function G.Controller()
    if G.Valid(cache.pc) then return cache.pc end
    cache.pc = nil
    for _, pc in ipairs(FindAllOf("BP_PlayerController_C") or {}) do
        if G.Valid(pc) and notDefault(pc) then
            cache.pc = pc
            break
        end
    end
    return cache.pc
end

-- The real playable William (not the loading-screen character).
function G.Player()
    if G.Valid(cache.player) then return cache.player end
    cache.player = nil
    local pc = G.Controller()
    if not pc then return nil end
    local pawn = G.Try(function() return pc.Pawn end)
    if not G.Valid(pawn) then return nil end
    local cls = G.Try(function() return pawn:GetClass():GetFName():ToString() end)
    if cls ~= "BP_PlayerCharacter_C" then return nil end
    cache.player = pawn
    return pawn
end

function G.Movement()
    local p = G.Player()
    if not p then return nil end
    local m = G.Try(function() return p.CharacterMovement end)
    if G.Valid(m) then return m end
end

function G.Notifier()
    local p = G.Player()
    if not p then return nil end
    local n = G.Try(function() return p.AttributesNotifierComponent end)
    if G.Valid(n) then return n end
end

-- Attribute sets the notifier keeps a pointer to.
local notifierSets = {
    Health = "HealthAttributes",
    Stamina = "StaminaAttributes",
    Blood = "BloodAttributes",
    Flasks = "FlasksAttributes",
    Ranged = "RangedAttributes",
    Exp = "ExpAttributes",
}

-- Attribute sets we have to look up by class (owned by the player).
local classSets = {
    Melee = "MeleeAttributeSet",
    Movement = "MovementAttributeSet",
}

function G.Set(name)
    local key = "set_" .. name
    if G.Valid(cache[key]) then return cache[key] end
    cache[key] = nil

    if notifierSets[name] then
        local n = G.Notifier()
        if not n then return nil end
        local s = G.Try(function() return n[notifierSets[name]] end)
        if G.Valid(s) then cache[key] = s end
        return cache[key]
    end

    local cls = classSets[name]
    local p = G.Player()
    if not cls or not p then return nil end
    local pAddr = G.Addr(p)
    for _, s in ipairs(FindAllOf(cls) or {}) do
        if G.Valid(s) and notDefault(s) then
            local outer = G.Try(function() return s:GetOuter() end)
            if G.Valid(outer) and G.Addr(outer) == pAddr then
                cache[key] = s
                break
            end
        end
    end
    return cache[key]
end

function G.GetAttr(set, name)
    return G.Try(function() return set[name].CurrentValue end)
end

function G.SetAttr(set, name, value)
    G.Try(function()
        local a = set[name]
        if a.BaseValue ~= value then a.BaseValue = value end
        if a.CurrentValue ~= value then a.CurrentValue = value end
    end)
end

-- Keep "name" at the current value of "maxName".
-- Returns true when the value was changed.
function G.FillAttr(set, name, maxName)
    local max = G.GetAttr(set, maxName)
    local cur = G.GetAttr(set, name)
    if type(max) == "number" and type(cur) == "number" and max > 0 and cur < max then
        G.SetAttr(set, name, max)
        return true
    end
    return false
end

function G.IsAlive()
    local s = G.Set("Health")
    local h = s and G.GetAttr(s, "Health")
    return type(h) == "number" and h > 0
end

-- ---------------------------------------------------------------------------
-- Static helpers
-- ---------------------------------------------------------------------------

local statics = {}
function G.Static(path)
    if G.Valid(statics[path]) then return statics[path] end
    statics[path] = StaticFindObject(path)
    return statics[path]
end

function G.CombatUtils()
    return G.Static("/Script/MinotaurCore.Default__MTCombatUtils")
end

function G.GameplayStatics()
    return G.Static("/Script/Engine.Default__GameplayStatics")
end

function G.Inventory()
    if G.Valid(cache.inventory) then return cache.inventory end
    cache.inventory = nil
    for _, s in ipairs(FindAllOf("InventorySubsystem") or {}) do
        if G.Valid(s) and notDefault(s) then
            cache.inventory = s
            break
        end
    end
    return cache.inventory
end

function G.Save()
    if G.Valid(cache.save) then return cache.save end
    cache.save = nil
    for _, s in ipairs(FindAllOf("SaveSubsystem") or {}) do
        if G.Valid(s) and notDefault(s) then
            cache.save = s
            break
        end
    end
    return cache.save
end

-- Applies one of the game's GameplayEffects to William (loads it if it is not in memory yet).
function G.ApplyEffect(path)
    local p = G.Player()
    local asc = p and G.Try(function() return p.AbilitySystemComponent end)
    if not G.Valid(asc) then
        G.Log("apply " .. path .. ": no ability system")
        return false
    end
    local cls = StaticFindObject(path)
    if not G.Valid(cls) and LoadAsset then
        G.Try(LoadAsset, (path:gsub("%.[^.]+$", "")))
        cls = StaticFindObject(path)
    end
    if not G.Valid(cls) then
        G.Log("apply " .. path .. ": effect not found")
        return false
    end
    local ok, err = pcall(function() asc:BP_ApplyGameplayEffectToSelf(cls, 1.0, asc:MakeEffectContext()) end)
    if not ok then G.Log("apply " .. path .. " failed: " .. tostring(err)) end
    return ok
end

-- ---------------------------------------------------------------------------
-- The developers' cheat manager (BP_MTCheatManager), shipped with the game.
-- ---------------------------------------------------------------------------

function G.CheatManager()
    local pc = G.Controller()
    if not pc then return nil end
    local cm = G.Try(function() return pc.CheatManager end)
    if G.Valid(cm) then return cm end
end

-- Calls one of the dev cheat functions (GodMode, NoClip, ...). Returns true when the call went through.
function G.DevCheat(fnName)
    local cm = G.CheatManager()
    if not cm then
        G.Log("dev cheat " .. fnName .. ": no cheat manager")
        return false
    end
    local ok, err = pcall(function() cm[fnName](cm) end)
    if ok then
        G.Log("dev cheat " .. fnName .. " called")
    else
        G.Log("dev cheat " .. fnName .. " failed: " .. tostring(err))
    end
    return ok
end

-- Sets a console variable through the game's console ("Cheat.GodMode 1").
function G.SetCVar(name, value)
    local ksl = G.Static("/Script/Engine.Default__KismetSystemLibrary")
    local pc = G.Controller()
    if not G.Valid(ksl) or not pc then return false end
    local ok = G.Try(function() ksl:ExecuteConsoleCommand(pc, name .. " " .. tostring(value), pc) return true end) == true
    G.Debug("console: " .. name .. " " .. tostring(value) .. (ok and "" or " (failed)"))
    return ok
end

-- Reads a console variable of the game (the dev cheats keep their on/off state in CVars like Cheat.GodMode).
function G.CVarBool(name)
    local ksl = G.Static("/Script/Engine.Default__KismetSystemLibrary")
    if not G.Valid(ksl) then return nil end
    local v = G.Try(function() return ksl:GetConsoleVariableBoolValue(name) end)
    if type(v) == "boolean" then return v end
    return nil
end

-- ---------------------------------------------------------------------------
-- Safe UEHelpers for ModMenu
-- The shared UEHelpers.GetPlayerController can throw in this game ("UFunction expected 0 parameters"),
-- and an error inside ModMenu's tick loop makes UE4SS drop its Lua tick hook (crash). ModMenu gets a
-- copy where every function is protected and GetPlayerController uses our own lookup.
-- ---------------------------------------------------------------------------

function G.InstallSafeUEHelpers()
    local okReal, real = pcall(require, "UEHelpers.UEHelpers")
    if not okReal or type(real) ~= "table" then real = {} end
    local function invalid()
        local ok, o = pcall(CreateInvalidObject)
        return ok and o or nil
    end
    local shim = {}
    for k, v in pairs(real) do
        if type(v) == "function" then
            shim[k] = function(...)
                local ok, a, b = pcall(v, ...)
                if ok then return a, b end
                G.Debug("UEHelpers." .. k .. " error: " .. tostring(a))
                return invalid()
            end
        else
            shim[k] = v
        end
    end
    shim.GetPlayerController = function()
        local pc = G.Controller()
        if pc then return pc end
        -- main menu etc.: any local player controller
        for _, c in ipairs(FindAllOf("PlayerController") or {}) do
            if G.Valid(c) and G.Try(function() return c:IsLocalController() end) == true then
                return c
            end
        end
        return invalid()
    end
    shim.GetPlayer = function()
        local pc = G.Controller()
        local pawn = pc and G.Try(function() return pc.Pawn end)
        if G.Valid(pawn) then return pawn end
        return invalid()
    end
    package.loaded["UEHelpers.UEHelpers"] = shim
    package.loaded["UEHelpers"] = shim
end

return G
