-- game/game.lua
-- Access to Valor Mortis itself: the player, his components and attribute sets, the world
-- subsystems, items and the game's own developer cheat manager. Generic Unreal access is in
-- core/unreal.lua, generic GAS access in gas/gas.lua. Every object lookup is cached for the current
-- world.

local Unreal = require("core.unreal")
local Log = require("core.log")
local Gas = require("gas.gas")

local Game = {}

-- CharacterMovement.MovementMode values.
Game.MOVEMENT_MODE = { FALLING = 3, FLYING = 5 }

local try, isValid, addressOf = Unreal.Try, Unreal.IsValid, Unreal.AddressOf

-- ---------------------------------------------------------------------------
-- Player
-- ---------------------------------------------------------------------------

function Game.Controller()
    return Unreal.FindCached("controller", "BP_PlayerController_C", 1)
end

local function readPawn(controller) return controller.Pawn end

-- The real playable William (not the loading-screen character).
function Game.Player()
    local cached = Unreal.GetCached("player")
    if cached then return cached end
    local controller = Game.Controller()
    local pawn = controller and try(readPawn, controller)
    if not isValid(pawn) or Unreal.ClassNameOf(pawn) ~= "BP_PlayerCharacter_C" then return nil end
    return Unreal.Remember("player", pawn)
end

-- Is this actor William?
function Game.IsPlayer(actor)
    local player = Game.Player()
    return player ~= nil and isValid(actor) and addressOf(actor) == addressOf(player)
end

local function readProperty(object, propertyName) return object[propertyName] end

local function playerComponent(propertyName)
    local cacheKey = "component_" .. propertyName
    local cached = Unreal.GetCached(cacheKey)
    if cached then return cached end
    local player = Game.Player()
    local component = player and try(readProperty, player, propertyName)
    if isValid(component) then return Unreal.Remember(cacheKey, component) end
    return nil
end

function Game.Movement() return playerComponent("CharacterMovement") end
function Game.AttributesNotifier() return playerComponent("AttributesNotifierComponent") end
function Game.AbilitySystem() return playerComponent("AbilitySystemComponent") end

function Game.IsKeyDown(keyName) return Unreal.IsKeyDown(Game.Controller(), keyName) end

-- ---------------------------------------------------------------------------
-- Attribute sets
-- ---------------------------------------------------------------------------

-- Sets the attributes notifier keeps a pointer to.
local NOTIFIER_SETS = {
    Health = "HealthAttributes",
    Stamina = "StaminaAttributes",
    Blood = "BloodAttributes",
    Flasks = "FlasksAttributes",
    Ranged = "RangedAttributes",
    Exp = "ExpAttributes",
}

-- Sets that have to be looked up by class (owned by the player).
local CLASS_SETS = {
    Melee = "MeleeAttributeSet",
    Movement = "MovementAttributeSet",
}

local function isOwnedByPlayer(object)
    local owner = try(function() return object:GetOuter() end)
    return Game.IsPlayer(owner)
end

function Game.AttributeSet(setName)
    local cacheKey = "set_" .. setName
    local cached = Unreal.GetCached(cacheKey)
    if cached then return cached end
    if NOTIFIER_SETS[setName] then
        local notifier = Game.AttributesNotifier()
        local set = notifier and try(readProperty, notifier, NOTIFIER_SETS[setName])
        if isValid(set) then return Unreal.Remember(cacheKey, set) end
        return nil
    end
    if not CLASS_SETS[setName] or not Game.Player() then return nil end
    return Unreal.FindCached(cacheKey, CLASS_SETS[setName], 2, isOwnedByPlayer)
end

-- healthSet, health, maxHealth; nil when there is no player or the values are not readable.
function Game.PlayerHealth()
    local healthSet = Game.AttributeSet("Health")
    local health = healthSet and Gas.GetAttribute(healthSet, "Health")
    local maxHealth = healthSet and Gas.GetAttribute(healthSet, "MaxHealth")
    if not health or not maxHealth or maxHealth <= 0 then return nil end
    return healthSet, health, maxHealth
end

function Game.IsPlayerAlive()
    local _, health = Game.PlayerHealth()
    return health ~= nil and health > 0
end

-- ---------------------------------------------------------------------------
-- World
-- ---------------------------------------------------------------------------

function Game.CombatUtils() return Unreal.Static("/Script/MinotaurCore.Default__MTCombatUtils") end

function Game.Inventory() return Unreal.FindCached("inventory", "InventorySubsystem", 2) end
function Game.SaveSubsystem() return Unreal.FindCached("save", "SaveSubsystem", 2) end

-- The world William is in (his outer's outer), e.g. to pick the subsystem of this world.
function Game.World()
    local player = Game.Player()
    return player and try(function() return player:GetOuter():GetOuter() end)
end

function Game.WorldTime()
    local statics, player = Unreal.GameplayStatics(), Game.Player()
    return player and Unreal.TryNumber(function() return statics:GetTimeSeconds(player) end)
end

function Game.MapName()
    local world = Game.World()
    return world and try(function() return world:GetFName():ToString() end) or "?"
end

-- Hooks MTCombatUtils functions; onCall(functionName, params...) runs before each call, afterCall
-- (optional) after it. Returns how many hooks were registered.
function Game.HookCombatUtils(functionNames, onCall, afterCall)
    local hooked = 0
    for _, functionName in ipairs(functionNames) do
        local path = "/Script/MinotaurCore.MTCombatUtils:" .. functionName
        local function before(_, ...) onCall(functionName, ...) end
        local ok
        if afterCall then
            ok = pcall(RegisterHook, path, before, function() afterCall(functionName) end)
        else
            ok = pcall(RegisterHook, path, before)
        end
        if ok then hooked = hooked + 1 end
    end
    return hooked
end

-- ---------------------------------------------------------------------------
-- Items (gameplay tags)
-- ---------------------------------------------------------------------------

-- How many of an item William carries.
function Game.ItemCount(tagName)
    local saveSubsystem = Game.SaveSubsystem()
    if not saveSubsystem then return nil end
    return Unreal.TryNumber(function() return saveSubsystem:TryGetInventoryItemCount(Gas.Tag(tagName)) end)
end

function Game.AddItem(tagName, amount)
    local inventory = Game.Inventory()
    if not inventory then return false end
    return try(function()
        inventory:AddInventoryItem(Gas.Tag(tagName), amount)
        return true
    end) == true
end

-- Calls visit(tagName, itemProperties) for every item in one map of the game's item database
-- (ConsumableItemsMap, MaterialItemsMap, ...). Each category maps to its real items
-- (Items.Consumable.Grenade -> ...Grenade.Regular, ...Oil); a category without sub items counts as
-- one item (itemProperties nil). Returns false before a save is loaded.
function Game.ForEachDatabaseItem(mapName, visit)
    local inventory = Game.Inventory()
    local database = inventory and try(readProperty, inventory, "InventoryDatabaseAsset")
    if not isValid(database) then return false end
    try(function()
        database[mapName]:ForEach(function(categoryKey, category)
            local visited = 0
            try(function()
                category:get().ItemMap:ForEach(function(itemKey, itemProperties)
                    local tagName = Gas.TagNameOf(itemKey)
                    if tagName then
                        visited = visited + 1
                        visit(tagName, try(function() return itemProperties:get() end))
                    end
                end)
            end)
            local categoryTag = visited == 0 and Gas.TagNameOf(categoryKey)
            if categoryTag then visit(categoryTag, nil) end
        end)
    end)
    return true
end

-- ---------------------------------------------------------------------------
-- The developers' cheat manager (BP_MTCheatManager), shipped with the game.
-- Its C++ cheat functions (GodMode, NoClip, ...) are empty in the release build and its Cheat.* CVars
-- do not exist, so every cheat has its own implementation. The cheat manager is only used for its
-- data (weapon and material lists), its working Blueprint cheat actions (gems, ability unlocks) and
-- the engine's IgnoreCosts toggle.
-- ---------------------------------------------------------------------------

function Game.CheatManager()
    local controller = Game.Controller()
    local cheatManager = controller and try(readProperty, controller, "CheatManager")
    if isValid(cheatManager) then return cheatManager end
    return nil
end

-- Calls one of the dev cheat functions. Returns true when the call went through.
function Game.CallDevCheat(functionName)
    local cheatManager = Game.CheatManager()
    if not cheatManager then
        Log.Info("dev cheat " .. functionName .. ": no cheat manager")
        return false
    end
    local ok, err = pcall(function() cheatManager[functionName](cheatManager) end)
    Log.Info("dev cheat " .. functionName .. (ok and " called" or (" failed: " .. tostring(err))))
    return ok
end

function Game.ReadConsoleBool(variableName)
    local systemLibrary = Unreal.Static("/Script/Engine.Default__KismetSystemLibrary")
    if not isValid(systemLibrary) then return nil end
    local value = try(function() return systemLibrary:GetConsoleVariableBoolValue(variableName) end)
    if type(value) == "boolean" then return value end
    return nil
end

return Game
