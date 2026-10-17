-- game/app.lua
-- ValorianSheet for Valor Mortis: the mod's identity and every setting with its vanilla value.

local App = require("core.app")

App.Define({
    name = "ValorianSheet",
    version = "1.3.0",
    menuTitle = "VALORIAN SHEET",
    status = "Waiting for a loaded save...",
    settings = {
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
    },
    -- Not restored on start: you would load into a save flying through walls.
    sessionOnly = { noClip = true },
})

return App
