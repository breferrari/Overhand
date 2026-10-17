-- ValorianSheet / game.lua
-- Access to Valor Mortis itself: the player, his components and attribute sets, the world
-- subsystems, items, active effects and the game's own developer cheat manager.
-- Every object lookup is cached for the current world (lib/unreal.lua).

local Unreal = require("lib.unreal")
local Log = require("lib.log")

local Game = {}

Game.NAME = "ValorianSheet"
Game.VERSION = "1.1.0"

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

local function readCurrentValue(set, attributeName) return set[attributeName].CurrentValue end
local function readBaseValue(set, attributeName) return set[attributeName].BaseValue end

function Game.GetAttribute(set, attributeName) return Unreal.TryNumber(readCurrentValue, set, attributeName) end
function Game.GetBaseValue(set, attributeName) return Unreal.TryNumber(readBaseValue, set, attributeName) end

function Game.SetAttribute(set, attributeName, value)
    try(function()
        local attribute = set[attributeName]
        if attribute.BaseValue ~= value then attribute.BaseValue = value end
        if attribute.CurrentValue ~= value then attribute.CurrentValue = value end
    end)
end

-- Sets BaseValue and moves CurrentValue by the same amount, so active buffs are kept.
function Game.SetBaseValueKeepModifiers(set, attributeName, value)
    try(function()
        local attribute = set[attributeName]
        local oldBase, current = attribute.BaseValue, attribute.CurrentValue
        attribute.BaseValue = value
        attribute.CurrentValue = current + (value - oldBase)
    end)
end

-- Raises attributeName to the current value of maxAttributeName. Returns true when it changed.
function Game.FillAttribute(set, attributeName, maxAttributeName)
    local maximum = Game.GetAttribute(set, maxAttributeName)
    local current = Game.GetAttribute(set, attributeName)
    if maximum and current and maximum > 0 and current < maximum then
        Game.SetAttribute(set, attributeName, maximum)
        return true
    end
    return false
end

-- healthSet, health, maxHealth; nil when there is no player or the values are not readable.
function Game.PlayerHealth()
    local healthSet = Game.AttributeSet("Health")
    local health = healthSet and Game.GetAttribute(healthSet, "Health")
    local maxHealth = healthSet and Game.GetAttribute(healthSet, "MaxHealth")
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
function Game.GameplayStatics() return Unreal.Static("/Script/Engine.Default__GameplayStatics") end
function Game.WidgetLibrary() return Unreal.Static("/Script/UMG.Default__WidgetBlueprintLibrary") end

function Game.Inventory() return Unreal.FindCached("inventory", "InventorySubsystem", 2) end
function Game.SaveSubsystem() return Unreal.FindCached("save", "SaveSubsystem", 2) end

-- The world William is in (his outer's outer), e.g. to pick the subsystem of this world.
function Game.World()
    local player = Game.Player()
    return player and try(function() return player:GetOuter():GetOuter() end)
end

function Game.WorldTime()
    local statics, player = Game.GameplayStatics(), Game.Player()
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
-- Items
-- ---------------------------------------------------------------------------

-- Gameplay tag structs, built once per tag name.
local itemTags = {}
function Game.ItemTag(tagName)
    local tag = itemTags[tagName]
    if not tag then
        tag = { TagName = FName(tagName) }
        itemTags[tagName] = tag
    end
    return tag
end

-- The tag name in a gameplay-tag parameter or array element, or nil ("None" counts as nil).
function Game.TagNameOf(tagParam)
    local name = try(function() return tagParam:get().TagName:ToString() end)
    if name and name ~= "None" then return name end
    return nil
end

-- The tag names in a gameplay-tag container (e.g. the cheat manager's UpgradeMaterials).
function Game.TagNamesIn(tagContainer)
    local names = {}
    try(function()
        tagContainer.GameplayTags:ForEach(function(_, element)
            names[#names + 1] = Game.TagNameOf(element)
        end)
    end)
    return names
end

-- How many of an item William carries.
function Game.ItemCount(tagName)
    local saveSubsystem = Game.SaveSubsystem()
    if not saveSubsystem then return nil end
    return Unreal.TryNumber(function() return saveSubsystem:TryGetInventoryItemCount(Game.ItemTag(tagName)) end)
end

function Game.AddItem(tagName, amount)
    local inventory = Game.Inventory()
    if not inventory then return false end
    return try(function()
        inventory:AddInventoryItem(Game.ItemTag(tagName), amount)
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
                    local tagName = Game.TagNameOf(itemKey)
                    if tagName then
                        visited = visited + 1
                        visit(tagName, try(function() return itemProperties:get() end))
                    end
                end)
            end)
            local categoryTag = visited == 0 and Game.TagNameOf(categoryKey)
            if categoryTag then visit(categoryTag, nil) end
        end)
    end)
    return true
end

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------

-- Applies one of the game's GameplayEffects to William (loads it if it is not in memory yet).
function Game.ApplyEffect(effectPath)
    local abilitySystem = Game.AbilitySystem()
    if not abilitySystem then
        Log.Info("apply " .. effectPath .. ": no ability system")
        return false
    end
    local effectClass = StaticFindObject(effectPath)
    if not isValid(effectClass) and LoadAsset then
        try(LoadAsset, (effectPath:gsub("%.[^.]+$", "")))
        effectClass = StaticFindObject(effectPath)
    end
    if not isValid(effectClass) then
        Log.Info("apply " .. effectPath .. ": effect not found")
        return false
    end
    local ok, err = pcall(function()
        abilitySystem:BP_ApplyGameplayEffectToSelf(effectClass, 1.0, abilitySystem:MakeEffectContext())
    end)
    if not ok then Log.Info("apply " .. effectPath .. " failed: " .. tostring(err)) end
    return ok
end

local function activeEffectArray()
    local abilitySystem = Game.AbilitySystem()
    return abilitySystem and try(function() return abilitySystem.ActiveGameplayEffects.GameplayEffects_Internal end)
end

function Game.ActiveEffectCount()
    local effects = activeEffectArray()
    return effects and Unreal.TryNumber(function() return effects:GetArrayNum() end) or 0
end

-- William's active GameplayEffects as { effect, className, definition, startTime }, read once per
-- tick and shared by every feature that looks at them (Game.BeginTick starts a new tick).
local tickNumber = 0
local effectSnapshot = { tick = -1, entries = {} }
local classNameByDefinition = {}   -- definition address -> class name (resolving it is 3 calls)

function Game.BeginTick() tickNumber = tickNumber + 1 end

function Game.ActiveEffects()
    if effectSnapshot.tick == tickNumber then return effectSnapshot.entries end
    local entries = {}
    local effects = activeEffectArray()
    if effects then
        local ok, err = pcall(function()
            effects:ForEach(function(_, element)
                local effect = element:get()
                local definition = try(function() return effect.Spec.Def end)
                local address = definition and addressOf(definition)
                local className = address and classNameByDefinition[address]
                if address and not className then
                    className = Unreal.ClassNameOf(definition)
                    classNameByDefinition[address] = className
                end
                entries[#entries + 1] = {
                    effect = effect,
                    className = className,
                    definition = definition,
                    startTime = Unreal.TryNumber(function() return effect.StartWorldTime end),
                }
            end)
        end)
        if not ok then Log.Debug("active effects: " .. tostring(err)) end
    end
    effectSnapshot.tick, effectSnapshot.entries = tickNumber, entries
    return entries
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

Unreal.OnWorldReset(function() classNameByDefinition = {} end)

return Game
