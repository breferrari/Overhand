-- ValorianSheet / features/hud.lua
-- The player's HUD: telling the health bar about values written directly, and keeping the bar at
-- its normal length while Max Health is raised.
--
-- The HUD widget (WBP_PlayerVitals) is found once and kept. After loading a save the old HUD can
-- stay valid for a while next to the new one, so it is checked by its owner, not only by being
-- valid; while missing it is searched again at most every 2 s.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")

local Hud = {}

local try, isValid = Unreal.Try, Unreal.IsValid
local clock = State.clock

local DEFAULT_PIXELS_PER_HEALTH = 2.5   -- 250 px for 100 max health in 1.0

local vitals = { widget = nil, nextOwnerCheckAt = 0, nextSearchAt = 0 }
local healthBar = {
    widgetAddress = nil,      -- the HUD the values below belong to
    pixelsPerHealth = nil,    -- learned from the game's own layout
    widthWeSet = nil,
    lastSeenWidth = nil,
    wasResized = false,
    nextCheckAt = 0,
    layoutDumps = 0,
    resizeLogs = 0,
}

local function readNumber(fn)
    local ok, value = pcall(fn)
    if ok and type(value) == "number" then return value end
    return nil
end

-- true / false, or nil when the widget's owner is unknown.
local function isOwnedBy(widget, playerAddress)
    local pawn = try(function() return widget:GetOwningPlayerPawn() end)
    if not isValid(pawn) then return nil end
    return Unreal.AddressOf(pawn) == playerAddress
end

-- The HUD widget that belongs to the current William.
function Hud.VitalsWidget()
    local player = Game.Player()
    local playerAddress = player and Unreal.AddressOf(player)
    if isValid(vitals.widget) then
        if clock() < vitals.nextOwnerCheckAt then return vitals.widget end
        vitals.nextOwnerCheckAt = clock() + 1
        if isOwnedBy(vitals.widget, playerAddress) ~= false then return vitals.widget end
        Log.Debug("health bar: HUD belongs to an old William, looking for the new one")
    end
    vitals.widget = nil
    if clock() < vitals.nextSearchAt then return nil end
    vitals.nextSearchAt = clock() + 2
    local ownerUnknown = nil
    for _, widget in ipairs(FindAllOf("WBP_PlayerVitals_C") or {}) do
        if Unreal.IsLiveObject(widget) then
            local owned = isOwnedBy(widget, playerAddress)
            if owned == true then
                vitals.widget = widget
                return widget
            end
            if owned == nil then ownerUnknown = widget end
        end
    end
    vitals.widget = ownerUnknown
    return ownerUnknown
end

local function healthBarWidget()
    local widget = Hud.VitalsWidget()
    local bar = widget and try(function() return widget.PlayerHealthVitalsBar end)
    if isValid(bar) then return bar end
    return nil
end

-- Tell the health bar about a value we wrote directly. The bar is a child of the kept HUD widget,
-- so this never searches (it runs up to 4 times a second during regeneration).
function Hud.UpdateHealthBar(health, maxHealth)
    local bar = healthBarWidget()
    if bar then try(function() bar:Update(health / maxHealth) end) end
end

-- ---------------------------------------------------------------------------
-- Health bar length: the HUD makes the bar longer the more max health William has (bar width =
-- pixels per point of max health x MaxHealth). With Max Health at 3x or 5x it runs off the screen.
-- While Max Health is raised the bar keeps the width it would have with the vanilla max health; the
-- fill still shows the real share of the raised max health.
-- ---------------------------------------------------------------------------

-- Logs the bar's layout (the first few times, or always with Debug Logging), for bug reports.
local function logLayout(reason)
    if healthBar.layoutDumps >= 12 and not Log.debugEnabled then return end
    healthBar.layoutDumps = healthBar.layoutDumps + 1
    local healthSet = Game.AttributeSet("Health")
    local bar = healthBarWidget()
    local slot = bar and try(function() return bar.Slot end)
    Log.Info(string.format("health bar (%s): MaxHealth=%s base=%s factor=%s width=%s", reason,
        tostring(healthSet and Game.GetAttribute(healthSet, "MaxHealth")),
        tostring(healthSet and Game.GetBaseValue(healthSet, "MaxHealth")),
        tostring(State.settings.maxHealthFactor),
        tostring(slot and readNumber(function() return slot:GetSize().X end))))
end

function Hud.KeepHealthBarLength()
    local factor = State.settings.maxHealthFactor or 1
    if factor == 1 and not healthBar.wasResized and healthBar.widgetAddress and not Log.debugEnabled then return end
    if clock() < healthBar.nextCheckAt then return end
    healthBar.nextCheckAt = clock() + 0.2

    local widget = Hud.VitalsWidget()
    if not widget then
        healthBar.widgetAddress = nil
        return
    end
    local address = Unreal.AddressOf(widget)
    local freshWidget = address ~= healthBar.widgetAddress
    if freshWidget then
        healthBar.widgetAddress, healthBar.widthWeSet = address, nil
        logLayout("HUD found")
    end

    local healthSet = Game.AttributeSet("Health")
    local maxHealth = healthSet and Game.GetAttribute(healthSet, "MaxHealth")
    local baseMaxHealth = healthSet and Game.GetBaseValue(healthSet, "MaxHealth")
    if type(maxHealth) ~= "number" or maxHealth <= 0 or type(baseMaxHealth) ~= "number" or baseMaxHealth <= 0 then return end
    local bar = healthBarWidget()
    local slot = bar and try(function() return bar.Slot end)
    if not isValid(slot) then return end
    local width = readNumber(function() return slot:GetSize().X end)
    local height = readNumber(function() return slot:GetSize().Y end)
    if not width or not height then return end

    -- A width we did not set comes from the game: learn its pixels per point of max health.
    local widthChanged = freshWidget or not healthBar.lastSeenWidth or math.abs(width - healthBar.lastSeenWidth) > 0.5
    healthBar.lastSeenWidth = width
    local isOurs = healthBar.widthWeSet and math.abs(width - healthBar.widthWeSet) <= 0.5
    if widthChanged and not isOurs then
        if not freshWidget then logLayout("game changed the bar") end
        healthBar.widthWeSet = nil
        local pixelsPerHealth = width / maxHealth
        local plausible = pixelsPerHealth > 0.05 and pixelsPerHealth < 50
        if plausible and (factor == 1 or State.appliedMaxHealthFactor == factor) then
            healthBar.pixelsPerHealth = pixelsPerHealth
        end
    end

    local function setWidth(newWidth, reason)
        if math.abs(width - newWidth) <= 0.5 then
            healthBar.widthWeSet = width
            return
        end
        local ok = pcall(function() slot:SetSize({ X = newWidth, Y = height }) end)
        healthBar.widthWeSet = readNumber(function() return slot:GetSize().X end) or newWidth
        healthBar.lastSeenWidth = healthBar.widthWeSet
        if healthBar.resizeLogs < 20 or Log.debugEnabled then
            healthBar.resizeLogs = healthBar.resizeLogs + 1
            Log.Info(string.format("health bar: width %.0f -> %.0f (%s)%s", width, healthBar.widthWeSet, reason,
                ok and "" or ", SetSize failed"))
        end
    end

    local pixelsPerHealth = healthBar.pixelsPerHealth or DEFAULT_PIXELS_PER_HEALTH
    if factor == 1 then
        if healthBar.wasResized then
            healthBar.wasResized = false
            setWidth(pixelsPerHealth * maxHealth, "Max Health off, game width")
            healthBar.widthWeSet = nil
        end
        return
    end
    healthBar.wasResized = true
    if State.appliedMaxHealthFactor ~= factor then return end -- Max Health not applied yet this tick
    local vanillaMaxHealth = maxHealth - baseMaxHealth + baseMaxHealth / factor -- buffs kept
    setWidth(pixelsPerHealth * vanillaMaxHealth,
        string.format("Max Health x%s, vanilla max health %.0f", tostring(factor), vanillaMaxHealth))
end

-- After a load or a new William: find the new HUD.
function Hud.Reset()
    vitals.widget, vitals.nextSearchAt = nil, 0
    healthBar.widgetAddress, healthBar.widthWeSet, healthBar.lastSeenWidth = nil, nil, nil
end

return Hud
