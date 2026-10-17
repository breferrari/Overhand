-- Stand-ins for the UE4SS Lua API, for tools/smoke_test.py.
-- Every object is a "mock": always valid, any property or method returns another mock, so the mod's
-- code paths run without the game. Values that must be real (class names, the player's pawn, his
-- location) are set explicitly. This catches wiring and load errors, not game behaviour.

local Mock = {}
local nextAddress = 1000

local function newMock(className)
    nextAddress = nextAddress + 1
    local fields = { __className = className or "Mock", __address = nextAddress }
    local mock = {}
    local methods = {
        IsValid = function() return true end,
        GetAddress = function() return fields.__address end,
        GetFullName = function() return fields.__className .. " /Game/Mock." .. fields.__className end,
        GetClass = function()
            local class = newMock("Class")
            rawset(class, "GetFName", function() return { ToString = function() return fields.__className end } end)
            return class
        end,
        ForEach = function() end,
        GetArrayNum = function() return 0 end,
        ToString = function() return fields.__className end,
        K2_GetActorLocation = function() return { X = 100.0, Y = 200.0, Z = 300.0 } end,
        GetControlRotation = function() return { Pitch = 0.0, Yaw = 90.0, Roll = 0.0 } end,
    }
    setmetatable(mock, {
        __index = function(_, key)
            if methods[key] then return function(_, ...) return methods[key](...) end end
            if fields[key] == nil then fields[key] = newMock(tostring(key)) end
            return fields[key]
        end,
        __newindex = function(_, key, value) fields[key] = value end,
        __call = function() return newMock("Result") end,
    })
    return mock
end

-- The world the mod sees: a controller whose pawn is William.
Mock.controller = newMock("BP_PlayerController_C")
Mock.controller.Pawn = newMock("BP_PlayerCharacter_C")
Mock.worldReady = false   -- false: main menu (no player controller found)

Mock.keyBinds = {}
Mock.loop = nil
Mock.printed = {}

function FindAllOf(className)
    if className == "BP_PlayerController_C" then
        return Mock.worldReady and { Mock.controller } or nil
    end
    return nil
end
function StaticFindObject(path) return newMock(path:match("([%w_]+)$") or "Static") end
function StaticConstructObject() return newMock("Constructed") end
function LoadAsset() end
function FName(text) return { ToString = function() return text end } end
function FText(text) return text end
function RegisterKeyBind(key, callback) Mock.keyBinds[key] = callback end
function RegisterHook() end
function RegisterLoadMapPreHook(callback) Mock.loadMap = callback end
function LoopInGameThreadWithDelay(_, fn) Mock.loop = fn return 1 end
function print(text) Mock.printed[#Mock.printed + 1] = text end

Key = setmetatable({}, { __index = function(_, name) return name end })

-- Strict globals: reading an undefined global (a typo) or creating an unexpected one is an error.
-- Reads are also recorded, because the mod wraps most calls in pcall (Unreal.Try), which would
-- swallow the error.
local ALLOWED_NEW_GLOBALS = { ValorianSheetTick = true, ValorianSheetTickHandle = true }
Mock.undefinedGlobals = {}
setmetatable(_G, {
    __index = function(_, name)
        Mock.undefinedGlobals[#Mock.undefinedGlobals + 1] = tostring(name)
        error("undefined global '" .. tostring(name) .. "'", 2)
    end,
    __newindex = function(t, name, value)
        if not ALLOWED_NEW_GLOBALS[name] then error("unexpected global '" .. tostring(name) .. "'", 2) end
        rawset(t, name, value)
    end,
})

return Mock
