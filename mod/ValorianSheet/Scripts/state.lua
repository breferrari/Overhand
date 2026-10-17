-- ValorianSheet / state.lua
-- State shared by the menu and every feature module. The menu only writes State.settings[...];
-- the features read it on the game thread and apply it.

local State = {}

-- What the player chose. Booleans for toggles, numbers for multipliers and percentages.
State.settings = {
    godMode = false,
    infiniteStamina = false,
    staminaOnlyOutOfCombat = false,
    infiniteNephtoglobin = false,
    fallDamage = 1,
    damageTaken = 1,
    maxHealthFactor = 1,
    regenRate = 0,              -- share of max health per second (0 = off)
    regenDelay = 2,             -- seconds without a hit before it starts
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
}

-- The vanilla values, for Turn Everything Off.
State.defaults = {}
for key, value in pairs(State.settings) do State.defaults[key] = value end

-- Not restored on start: you would load into a save flying through walls.
State.SESSION_ONLY = { noClip = true }

-- One line of feedback for the menu's status row.
State.status = "Waiting for a loaded save..."

-- Values written into attributes the game saves (see lib/override.lua). Persisted by settings.lua.
State.attributeLedger = {}
State.onLedgerChanged = nil

-- Saved teleport positions: slot number (string) -> { map, x, y, z, yaw, name }.
State.teleports = {}
State.onTeleportsChanged = nil

-- Runtime flags read by more than one feature.
State.noClipActive = false
State.safeLandingUntil = 0          -- no fall damage until then (after NoClip / teleport)
State.appliedMaxHealthFactor = 1    -- the Max Health factor currently applied

State.clock = os.clock

return State
