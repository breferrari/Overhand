-- ValorianSheet / state.lua
-- State shared by the menu and every feature module. The menu only writes State.settings[...];
-- the features read it on the game thread and apply it.

local State = {}

-- What the player chose. Booleans for toggles, numbers for multipliers and amounts.
State.settings = {
    godMode = false,
    infiniteStamina = false,
    staminaOnlyOutOfCombat = false,
    infiniteNephtoglobin = false,
    fallDamage = 1,
    damageTaken = 1,            -- share of every hit that gets through (features/defense.lua)
    maxHealthFactor = 1,
    regenPerSecond = 0,         -- health points per second (0 = off)
    regenDelay = 2,             -- seconds without a hit before it starts
    regenMaxPercent = 100,      -- heals up to this share of max health
    regenOnlyOutOfCombat = false,

    noClip = false,
    movementSpeed = 1,
    jumpHeight = 1,
    gameSpeed = 1,
    toggleSprint = false,
    instantSprint = false,

    oneHitKills = false,
    damageMultiplier = 1,
    perfectParry = false,
    parryWindow = 1,
    dodgeWindow = 1,

    infiniteAmmo = false,
    infiniteFlasks = false,
    infiniteConsumables = false,
    infiniteBuffs = false,
    noItemCooldowns = false,
    keepCatalysts = false,
    noAbilityCosts = false,

    debugLogging = false,
}

-- The vanilla values, for Turn Everything Off.
State.defaults = {}
for key, value in pairs(State.settings) do State.defaults[key] = value end

-- Not restored on start: you would load into a save flying through walls.
State.SESSION_ONLY = { noClip = true }

-- Not a cheat: Turn Everything Off leaves it alone.
State.NOT_A_CHEAT = { debugLogging = true }

function State.SortedSettingKeys()
    local keys = {}
    for key in pairs(State.settings) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- One line of feedback for the menu's status row.
State.status = "Waiting for a loaded save..."

-- Values written into attributes the game saves (see lib/override.lua). Persisted by settings.lua.
State.attributeLedger = {}

-- Saved teleport positions: slot number (string) -> { map, x, y, z, yaw, name }.
State.teleports = {}

-- Runtime flags read by more than one feature.
State.noClipActive = false
State.safeLandingUntil = 0          -- no fall damage until then (after NoClip / teleport)

return State
