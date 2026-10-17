-- core/unreal.lua
-- Safe access to Unreal objects through UE4SS, cached object lookups, and the world reset.
--
-- Performance rule: FindAllOf walks every object in the game (hundreds of thousands), and with the
-- Crash Fix setting (bForceGUObjectArrayForIteration) it takes the slower walk. This file is the only
-- place that calls it on a schedule. FindCached / FindAllCached keep what they found, and a lookup
-- that found nothing waits before it searches again, so code that asks every tick (main menu,
-- loading screens) never searches every tick. See docs/PERFORMANCE.md.
--
-- World reset: everything cached here belongs to one world. Unreal.ResetWorld() forgets it and runs
-- the callbacks modules registered with Unreal.OnWorldReset (for their own per-world state).

local Unreal = {}

-- Calls fn(...) and returns its first result, or nil when it raised an error.
function Unreal.Try(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- Number results only (nil for errors and anything that is not a number).
function Unreal.TryNumber(fn, ...)
    local result = Unreal.Try(fn, ...)
    if type(result) == "number" then return result end
    return nil
end

-- Module-level callees, so the hot helpers below allocate no closure per call.
local function callIsValid(object) return object:IsValid() end
local function callGetAddress(object) return object:GetAddress() end
local function callClassName(object) return object:GetClass():GetFName():ToString() end
local function callFullName(object) return object:GetFullName() end

function Unreal.IsValid(object)
    if object == nil then return false end
    local ok, valid = pcall(callIsValid, object)
    return ok and valid == true
end

function Unreal.AddressOf(object) return Unreal.Try(callGetAddress, object) end
function Unreal.ClassNameOf(object) return Unreal.Try(callClassName, object) end

-- A live instance: valid, and not a class default object ("Default__...", a template).
function Unreal.IsLiveObject(object)
    if not Unreal.IsValid(object) then return false end
    local fullName = Unreal.Try(callFullName, object)
    return fullName ~= nil and not fullName:find("Default__", 1, true)
end

-- Every live object of className that passes accept (optional). A full search: button presses only.
function Unreal.FindAllLive(className, accept)
    local found = {}
    for _, object in ipairs(FindAllOf(className) or {}) do
        if Unreal.IsLiveObject(object) and (not accept or accept(object)) then found[#found + 1] = object end
    end
    return found
end

-- ---------------------------------------------------------------------------
-- Cached lookups (per world)
-- ---------------------------------------------------------------------------

local cachedObjects = {}   -- key -> object, or list of objects (FindAllCached)
local nextSearchAt = {}    -- key -> clock time before which a missed lookup does not search again
local worldResetCallbacks = {}

local function searchAllowed(key, retrySeconds)
    if os.clock() < (nextSearchAt[key] or 0) then return false end
    nextSearchAt[key] = os.clock() + (retrySeconds or 2)
    return true
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

-- Drop one entry (it turned out to be the wrong object); the next lookup may search right away.
function Unreal.Forget(key)
    cachedObjects[key] = nil
    nextSearchAt[key] = nil
end

-- The first live object of className that passes accept (optional), kept under key.
-- A miss is remembered for retrySeconds: no new FindAllOf before then.
function Unreal.FindCached(key, className, retrySeconds, accept)
    local cached = Unreal.GetCached(key)
    if cached then return cached end
    cachedObjects[key] = nil
    if not searchAllowed(key, retrySeconds) then return nil end
    cachedObjects[key] = Unreal.FindAllLive(className, accept)[1]
    return cachedObjects[key]
end

-- The still-valid objects kept under key by FindAllCached (never searches).
function Unreal.GetCachedList(key)
    local alive = {}
    for _, object in ipairs(cachedObjects[key] or {}) do
        if Unreal.IsValid(object) then alive[#alive + 1] = object end
    end
    cachedObjects[key] = alive
    return alive
end

-- Every live object of className, kept under key. Searched again only when none of the kept objects
-- is still valid, and then at most every retrySeconds.
function Unreal.FindAllCached(key, className, retrySeconds)
    local alive = Unreal.GetCachedList(key)
    if #alive == 0 and searchAllowed(key, retrySeconds) then
        alive = Unreal.FindAllLive(className)
        cachedObjects[key] = alive
    end
    return alive
end

-- The best live object of className by rank(object) (a number, higher is better; nil rejects it),
-- kept under key. The kept object is ranked again on every call (rank should be cheap). With nothing
-- usable kept, a search runs at most every retrySeconds; with a usable object below bestRank, only
-- every UPGRADE_SEARCH_SECONDS (a better one may never exist).
local UPGRADE_SEARCH_SECONDS = 30
function Unreal.FindRanked(key, className, retrySeconds, rank, bestRank)
    local kept = cachedObjects[key]
    local keptRank = kept and Unreal.IsValid(kept.object) and rank(kept.object)
    if keptRank and keptRank >= bestRank then return kept.object end
    if searchAllowed(key, keptRank and UPGRADE_SEARCH_SECONDS or retrySeconds) then
        local bestObject, bestFound = nil, nil
        for _, object in ipairs(Unreal.FindAllLive(className)) do
            local objectRank = rank(object)
            if objectRank and (not bestFound or objectRank > bestFound) then bestObject, bestFound = object, objectRank end
        end
        if bestObject and (not keptRank or bestFound > keptRank) then
            cachedObjects[key] = { object = bestObject }
            return bestObject
        end
    end
    if keptRank then return kept.object end
    cachedObjects[key] = nil
    return nil
end

-- Static objects (class default objects, function libraries) never change: one lookup each.
local staticObjects = {}
function Unreal.Static(path)
    if Unreal.IsValid(staticObjects[path]) then return staticObjects[path] end
    staticObjects[path] = StaticFindObject(path)
    return staticObjects[path]
end

-- Is a key or controller button held on this player controller? keyName is an Unreal FKey name
-- ("SpaceBar", "Gamepad_FaceButton_Bottom", ...); the key struct is built once per name.
local keyStructs = {}
local function isInputKeyDown(controller, key) return controller:IsInputKeyDown(key) end

function Unreal.IsKeyDown(controller, keyName)
    if not controller then return false end
    local key = keyStructs[keyName]
    if not key then
        key = { KeyName = FName(keyName) }
        keyStructs[keyName] = key
    end
    return Unreal.Try(isInputKeyDown, controller, key) == true
end

-- Engine function libraries every Unreal game has.
function Unreal.GameplayStatics() return Unreal.Static("/Script/Engine.Default__GameplayStatics") end
function Unreal.WidgetLibrary() return Unreal.Static("/Script/UMG.Default__WidgetBlueprintLibrary") end
function Unreal.WidgetLayoutLibrary() return Unreal.Static("/Script/UMG.Default__WidgetLayoutLibrary") end

-- ---------------------------------------------------------------------------
-- World reset
-- ---------------------------------------------------------------------------

-- callback() runs on every world reset: forget per-world state that is not an Unreal cache entry.
function Unreal.OnWorldReset(callback)
    worldResetCallbacks[#worldResetCallbacks + 1] = callback
end

-- Callbacks run first, so they can still reach cached objects that survive the reset.
function Unreal.ResetWorld()
    for _, callback in ipairs(worldResetCallbacks) do pcall(callback) end
    cachedObjects = {}
    nextSearchAt = {}
end

return Unreal
