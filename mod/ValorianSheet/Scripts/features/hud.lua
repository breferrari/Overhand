-- ValorianSheet / features/hud.lua
-- The player's HUD: telling it about values written directly (health, ammo, buff counters), and
-- keeping the health bar at its normal length while Max Health is raised.
--
-- The HUD widget (WBP_PlayerVitals) is a ranked lookup (Unreal.FindRanked): after loading a save the
-- old HUD can stay valid for a while next to the new one, so the kept widget is re-ranked by its
-- owner on every use and William's own HUD wins.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")

local Hud = {}

local try, isValid = Unreal.Try, Unreal.IsValid

local DEFAULT_PIXELS_PER_HEALTH = 2.5   -- 250 px for 100 max health in 1.0

local healthBar = {}

local function resetHealthBar()
    healthBar = {
        widgetAddress = nil,      -- the HUD the values below belong to
        pixelsPerHealth = nil,    -- learned from the game's own layout
        widthWeSet = nil,
        lastSeenWidth = nil,
        wasResized = false,
        nextCheckAt = 0,
    }
end
resetHealthBar()
Unreal.OnWorldReset(resetHealthBar)

local function owningPawn(widget) return widget:GetOwningPlayerPawn() end

-- William's own HUD ranks highest; one whose owner is unknown is a fallback (the old HUD after a
-- load also loses its owner); one owned by an old William is rejected.
local OWNED, OWNER_UNKNOWN = 2, 1
local function rankVitals(widget)
    local pawn = try(owningPawn, widget)
    if not isValid(pawn) then return OWNER_UNKNOWN end
    return Game.IsPlayer(pawn) and OWNED or nil
end

local function vitalsWidget()
    return Unreal.FindRanked("vitals", "WBP_PlayerVitals_C", 2, rankVitals, OWNED)
end

local function healthBarWidget()
    local widget = vitalsWidget()
    local bar = widget and try(function() return widget.PlayerHealthVitalsBar end)
    if isValid(bar) then return bar end
    return nil
end

-- Tell the health bar about a value we wrote directly (never searches once the HUD is kept).
function Hud.UpdateHealthBar(health, maxHealth)
    local bar = healthBarWidget()
    if bar then try(function() bar:Update(health / maxHealth) end) end
end

local function notifier(method)
    local attributesNotifier = Game.AttributesNotifier()
    if attributesNotifier then try(function() attributesNotifier[method](attributesNotifier) end) end
end

-- The ammo display, after ammo was written directly.
function Hud.RefreshWeapons() notifier("RequestWeaponRefresh") end

-- Buff and consumable counters.
function Hud.RefreshTokens() notifier("RequestTokenRefresh") end

-- ---------------------------------------------------------------------------
-- Health bar length: the HUD makes the bar longer the more max health William has (bar width =
-- pixels per point of max health x MaxHealth). With Max Health at 3x or 5x it runs off the screen.
-- While Max Health is raised the bar keeps the width it would have with the vanilla max health; the
-- fill still shows the real share of the raised max health.
-- ---------------------------------------------------------------------------

local function logLayout(reason, width)
    local healthSet = Game.AttributeSet("Health")
    Log.Limited("health bar layout", 12, string.format("health bar (%s): MaxHealth=%s base=%s factor=%s width=%s", reason,
        tostring(healthSet and Game.GetAttribute(healthSet, "MaxHealth")),
        tostring(healthSet and Game.GetBaseValue(healthSet, "MaxHealth")),
        tostring(State.settings.maxHealthFactor), tostring(width)))
end

function Hud.KeepHealthBarLength()
    local factor = State.settings.maxHealthFactor or 1
    if factor == 1 and not healthBar.wasResized then return end
    if os.clock() < healthBar.nextCheckAt then return end
    healthBar.nextCheckAt = os.clock() + 0.2

    local widget = vitalsWidget()
    local healthSet, _, maxHealth = Game.PlayerHealth()
    local baseMaxHealth = healthSet and Game.GetBaseValue(healthSet, "MaxHealth")
    local bar = widget and healthBarWidget()
    local slot = bar and try(function() return bar.Slot end)
    if not baseMaxHealth or baseMaxHealth <= 0 or not isValid(slot) then return end
    local width = Unreal.TryNumber(function() return slot:GetSize().X end)
    local height = Unreal.TryNumber(function() return slot:GetSize().Y end)
    if not width or not height then return end

    local address = Unreal.AddressOf(widget)
    local freshWidget = address ~= healthBar.widgetAddress
    if freshWidget then
        healthBar.widgetAddress, healthBar.widthWeSet = address, nil
        logLayout("HUD found", width)
    end

    -- A width we did not set comes from the game: learn its pixels per point of max health.
    local widthChanged = freshWidget or not healthBar.lastSeenWidth or math.abs(width - healthBar.lastSeenWidth) > 0.5
    healthBar.lastSeenWidth = width
    local isOurs = healthBar.widthWeSet and math.abs(width - healthBar.widthWeSet) <= 0.5
    if widthChanged and not isOurs then
        if not freshWidget then logLayout("game changed the bar", width) end
        healthBar.widthWeSet = nil
        -- only while max health is settled (vanilla, or our value in place), not mid-change
        local recorded = State.attributeLedger.MaxHealth
        local settled = factor == 1 or (recorded and math.abs(baseMaxHealth - recorded.written) <= 0.01)
        local pixelsPerHealth = width / maxHealth
        if settled and pixelsPerHealth > 0.05 and pixelsPerHealth < 50 then healthBar.pixelsPerHealth = pixelsPerHealth end
    end

    local function setWidth(newWidth, reason)
        if math.abs(width - newWidth) <= 0.5 then
            healthBar.widthWeSet = width
            return
        end
        local ok = pcall(function() slot:SetSize({ X = newWidth, Y = height }) end)
        healthBar.widthWeSet = Unreal.TryNumber(function() return slot:GetSize().X end) or newWidth
        healthBar.lastSeenWidth = healthBar.widthWeSet
        Log.Limited("health bar resize", 20, string.format("health bar: width %.0f -> %.0f (%s)%s",
            width, healthBar.widthWeSet, reason, ok and "" or ", SetSize failed"))
    end

    local pixelsPerHealth = healthBar.pixelsPerHealth or DEFAULT_PIXELS_PER_HEALTH
    if factor == 1 then
        healthBar.wasResized = false
        setWidth(pixelsPerHealth * maxHealth, "Max Health off, game width")
        healthBar.widthWeSet = nil
        return
    end
    healthBar.wasResized = true
    -- the vanilla base from the ledger, once our value is in place (buffs on top are kept)
    local recorded = State.attributeLedger.MaxHealth
    if not recorded or math.abs(baseMaxHealth - recorded.written) > 0.01 then return end
    local vanillaMaxHealth = maxHealth - baseMaxHealth + recorded.vanilla
    setWidth(pixelsPerHealth * vanillaMaxHealth,
        string.format("Max Health x%s, vanilla max health %.0f", tostring(factor), vanillaMaxHealth))
end

return Hud
