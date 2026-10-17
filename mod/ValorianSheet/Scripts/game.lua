-- ValorianSheet / game.lua
-- Access to Valor Mortis itself: the player, his attribute sets, the world subsystems and the
-- game's own developer cheat manager. Every lookup is cached (Unreal.FindCached).

local Unreal = require("lib.unreal")
local Log = require("lib.log")

local Game = {}

Game.NAME = "ValorianSheet"
Game.VERSION = "1.0.0"

local try, isValid = Unreal.Try, Unreal.IsValid

-- ---------------------------------------------------------------------------
-- Player
-- ---------------------------------------------------------------------------

function Game.Controller()
    return Unreal.FindCached("controller", "BP_PlayerController_C", 1)
end

-- The real playable William (not the loading-screen character).
function Game.Player()
    local cached = Unreal.GetCached("player")
    if cached then return cached end
    local controller = Game.Controller()
    if not controller then return nil end
    local pawn = try(function() return controller.Pawn end)
    if not isValid(pawn) or Unreal.ClassNameOf(pawn) ~= "BP_PlayerCharacter_C" then return nil end
    return Unreal.Remember("player", pawn)
end

local function playerComponent(propertyName)
    local player = Game.Player()
    local component = player and try(function() return player[propertyName] end)
    if isValid(component) then return component end
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

function Game.AttributeSet(setName)
    local cacheKey = "set_" .. setName
    local cached = Unreal.GetCached(cacheKey)
    if cached then return cached end

    if NOTIFIER_SETS[setName] then
        local notifier = Game.AttributesNotifier()
        local set = notifier and try(function() return notifier[NOTIFIER_SETS[setName]] end)
        if isValid(set) then return Unreal.Remember(cacheKey, set) end
        return nil
    end

    local className = CLASS_SETS[setName]
    local player = Game.Player()
    if not className or not player then return nil end
    local playerAddress = Unreal.AddressOf(player)
    return Unreal.FindCached(cacheKey, className, 2, function(set)
        local owner = try(function() return set:GetOuter() end)
        return isValid(owner) and Unreal.AddressOf(owner) == playerAddress
    end)
end

function Game.GetAttribute(set, attributeName)
    return try(function() return set[attributeName].CurrentValue end)
end

function Game.GetBaseValue(set, attributeName)
    return try(function() return set[attributeName].BaseValue end)
end

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
    if type(maximum) == "number" and type(current) == "number" and maximum > 0 and current < maximum then
        Game.SetAttribute(set, attributeName, maximum)
        return true
    end
    return false
end

function Game.IsPlayerAlive()
    local healthSet = Game.AttributeSet("Health")
    local health = healthSet and Game.GetAttribute(healthSet, "Health")
    return type(health) == "number" and health > 0
end

-- ---------------------------------------------------------------------------
-- World
-- ---------------------------------------------------------------------------

function Game.CombatUtils() return Unreal.Static("/Script/MinotaurCore.Default__MTCombatUtils") end
function Game.GameplayStatics() return Unreal.Static("/Script/Engine.Default__GameplayStatics") end
function Game.WidgetLibrary() return Unreal.Static("/Script/UMG.Default__WidgetBlueprintLibrary") end

function Game.Inventory() return Unreal.FindCached("inventory", "InventorySubsystem", 2) end
function Game.SaveSubsystem() return Unreal.FindCached("save", "SaveSubsystem", 2) end

-- World subsystems (combat state, enemy info). Kept until they die with the world.
function Game.Subsystem(className) return Unreal.FindCached("subsystem_" .. className, className, 5) end

function Game.WorldTime()
    local statics, player = Game.GameplayStatics(), Game.Player()
    return player and try(function() return statics:GetTimeSeconds(player) end)
end

function Game.MapName()
    local player = Game.Player()
    return player and try(function() return player:GetOuter():GetOuter():GetFName():ToString() end) or "?"
end

-- How many of an item (gameplay tag name) William carries.
function Game.ItemCount(itemTag)
    local saveSubsystem = Game.SaveSubsystem()
    local count = saveSubsystem and try(function()
        return saveSubsystem:TryGetInventoryItemCount({ TagName = FName(itemTag) })
    end)
    if type(count) == "number" then return count end
    return nil
end

function Game.AddItem(itemTag, amount)
    local inventory = Game.Inventory()
    if not inventory then return false end
    return try(function()
        inventory:AddInventoryItem({ TagName = FName(itemTag) }, amount)
        return true
    end) == true
end

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

-- Calls visit(activeEffect, effectClassName, effectDefinition) for every active GameplayEffect on
-- William (ActiveGameplayEffects.GameplayEffects_Internal: Spec.Def, Spec.Duration, StartWorldTime).
function Game.ForEachActiveEffect(visit)
    local abilitySystem = Game.AbilitySystem()
    local effects = abilitySystem and try(function()
        return abilitySystem.ActiveGameplayEffects.GameplayEffects_Internal
    end)
    if not effects then return false end
    local ok, err = pcall(function()
        effects:ForEach(function(_, element)
            local activeEffect = element:get()
            local definition = try(function() return activeEffect.Spec.Def end)
            visit(activeEffect, definition and Unreal.ClassNameOf(definition), definition)
        end)
    end)
    if not ok then Log.Debug("active effects: " .. tostring(err)) end
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
    local cheatManager = controller and try(function() return controller.CheatManager end)
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
