-- gas/gas.lua
-- Helpers for games built on Unreal's Gameplay Ability System (GAS): attributes, active gameplay
-- effects, gameplay tags, and the override accessors for attributes. Knows nothing about a game:
-- the game passes the character's AbilitySystemComponent with Gas.Configure.

local Unreal = require("core.unreal")
local Log = require("core.log")

local Gas = {}

local try, isValid, addressOf = Unreal.Try, Unreal.IsValid, Unreal.AddressOf

local config = { abilitySystem = function() return nil end }

-- options: { abilitySystem = function() -> the player's AbilitySystemComponent or nil }
function Gas.Configure(options)
    for key, value in pairs(options) do config[key] = value end
end

-- ---------------------------------------------------------------------------
-- Attributes (FGameplayAttributeData: BaseValue is saved, CurrentValue = base + modifiers)
-- ---------------------------------------------------------------------------

local function readCurrentValue(set, attributeName) return set[attributeName].CurrentValue end
local function readBaseValue(set, attributeName) return set[attributeName].BaseValue end
local function writeCurrentValue(set, attributeName, value) set[attributeName].CurrentValue = value end

function Gas.GetAttribute(set, attributeName) return Unreal.TryNumber(readCurrentValue, set, attributeName) end
function Gas.GetBaseValue(set, attributeName) return Unreal.TryNumber(readBaseValue, set, attributeName) end

-- Both values (a direct set, e.g. health).
function Gas.SetAttribute(set, attributeName, value)
    try(function()
        local attribute = set[attributeName]
        if attribute.BaseValue ~= value then attribute.BaseValue = value end
        if attribute.CurrentValue ~= value then attribute.CurrentValue = value end
    end)
end

-- CurrentValue only: the game rebuilds it from BaseValue, so this is never saved.
function Gas.SetCurrentValue(set, attributeName, value) pcall(writeCurrentValue, set, attributeName, value) end

-- Sets BaseValue and moves CurrentValue by the same amount, so active buffs are kept.
function Gas.SetBaseValueKeepModifiers(set, attributeName, value)
    try(function()
        local attribute = set[attributeName]
        local oldBase, current = attribute.BaseValue, attribute.CurrentValue
        attribute.BaseValue = value
        attribute.CurrentValue = current + (value - oldBase)
    end)
end

-- Raises attributeName to the current value of maxAttributeName. Returns true when it changed.
function Gas.FillAttribute(set, attributeName, maxAttributeName)
    local maximum = Gas.GetAttribute(set, maxAttributeName)
    local current = Gas.GetAttribute(set, attributeName)
    if maximum and current and maximum > 0 and current < maximum then
        Gas.SetAttribute(set, attributeName, maximum)
        return true
    end
    return false
end

-- Accessors for core/override.lua.
Gas.BASE_VALUE = { read = Gas.GetBaseValue, write = Gas.SetBaseValueKeepModifiers, saved = true }
Gas.CURRENT_VALUE = { read = Gas.GetAttribute, write = Gas.SetCurrentValue, saved = false }

-- ---------------------------------------------------------------------------
-- Gameplay tags
-- ---------------------------------------------------------------------------

-- Tag structs ({ TagName = FName }), built once per tag name.
local tagStructs = {}
function Gas.Tag(tagName)
    local tag = tagStructs[tagName]
    if not tag then
        tag = { TagName = FName(tagName) }
        tagStructs[tagName] = tag
    end
    return tag
end

-- The tag name in a gameplay-tag parameter or array element, or nil ("None" counts as nil).
function Gas.TagNameOf(tagParam)
    local name = try(function() return tagParam:get().TagName:ToString() end)
    if name and name ~= "None" then return name end
    return nil
end

-- The tag names in a gameplay-tag container.
function Gas.TagNamesIn(tagContainer)
    local names = {}
    try(function()
        tagContainer.GameplayTags:ForEach(function(_, element)
            names[#names + 1] = Gas.TagNameOf(element)
        end)
    end)
    return names
end

-- ---------------------------------------------------------------------------
-- Gameplay effects
-- ---------------------------------------------------------------------------

-- Applies a GameplayEffect class (by path) to the player (loads it if it is not in memory yet).
function Gas.ApplyEffect(effectPath)
    local abilitySystem = config.abilitySystem()
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
    local abilitySystem = config.abilitySystem()
    return abilitySystem and try(function() return abilitySystem.ActiveGameplayEffects.GameplayEffects_Internal end)
end

function Gas.ActiveEffectCount()
    local effects = activeEffectArray()
    return effects and Unreal.TryNumber(function() return effects:GetArrayNum() end) or 0
end

-- The player's active GameplayEffects as { effect, className, definition, startTime }, read once per
-- tick and shared by every feature that looks at them. Gas.BeginTick starts a new tick (the game
-- registers it with Runner.OnTickStart).
local tickNumber = 0
local effectSnapshot = { tick = -1, entries = {} }
local classNameByDefinition = {}   -- definition address -> class name (resolving it is 3 calls)

function Gas.BeginTick() tickNumber = tickNumber + 1 end

-- After removing an effect: the shared list no longer matches the array, read it again.
function Gas.InvalidateActiveEffects() effectSnapshot.tick = -1 end

function Gas.ActiveEffects()
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

Unreal.OnWorldReset(function() classNameByDefinition = {} end)

return Gas
