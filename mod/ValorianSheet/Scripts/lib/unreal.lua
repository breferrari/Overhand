-- ValorianSheet / lib/unreal.lua
-- Safe access to Unreal objects through UE4SS, and cached object lookups.
--
-- Performance rule: FindAllOf walks every object in the game (hundreds of thousands), and with the
-- Crash Fix setting (bForceGUObjectArrayForIteration) it takes the slower walk. Nothing may call it
-- on a per-tick path. FindCached keeps what it found, and a lookup that found nothing waits before
-- it searches again, so code that asks every tick (main menu, loading screens) never searches every
-- tick. See docs/PERFORMANCE.md.

local Unreal = {}

-- Calls fn and returns its results, or nil when it raised an error.
function Unreal.Try(fn, ...)
    local ok, first, second = pcall(fn, ...)
    if ok then return first, second end
    return nil
end

function Unreal.IsValid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

function Unreal.AddressOf(object)
    return Unreal.Try(function() return object:GetAddress() end)
end

function Unreal.ClassNameOf(object)
    return Unreal.Try(function() return object:GetClass():GetFName():ToString() end)
end

-- Class default objects ("Default__...") are templates, never the live instance we want.
function Unreal.IsDefaultObject(object)
    local fullName = Unreal.Try(function() return object:GetFullName() end)
    return fullName == nil or fullName:find("Default__", 1, true) ~= nil
end

function Unreal.IsLiveObject(object)
    return Unreal.IsValid(object) and not Unreal.IsDefaultObject(object)
end

-- ---------------------------------------------------------------------------
-- Cached lookups
-- ---------------------------------------------------------------------------

local cachedObjects = {}
local nextSearchAt = {}   -- cache key -> clock time before which a missed lookup does not search again

-- Forget everything (after a map change every cached object belonged to the old world).
function Unreal.ResetCache()
    cachedObjects = {}
    nextSearchAt = {}
end

function Unreal.GetCached(key)
    local object = cachedObjects[key]
    if Unreal.IsValid(object) then return object end
    return nil
end

function Unreal.Remember(key, object)
    cachedObjects[key] = object
    return object
end

-- The first live object of class className that passes accept (optional), kept under key.
-- A miss is remembered for retrySeconds: no new FindAllOf before then.
function Unreal.FindCached(key, className, retrySeconds, accept)
    local cached = Unreal.GetCached(key)
    if cached then return cached end
    cachedObjects[key] = nil
    local now = os.clock()
    if now < (nextSearchAt[key] or 0) then return nil end
    nextSearchAt[key] = now + (retrySeconds or 2)
    for _, object in ipairs(FindAllOf(className) or {}) do
        if Unreal.IsLiveObject(object) and (not accept or accept(object)) then
            cachedObjects[key] = object
            break
        end
    end
    return cachedObjects[key]
end

-- Static objects (class default objects, function libraries) never change: one lookup each.
local staticObjects = {}
function Unreal.Static(path)
    if Unreal.IsValid(staticObjects[path]) then return staticObjects[path] end
    staticObjects[path] = StaticFindObject(path)
    return staticObjects[path]
end

return Unreal
