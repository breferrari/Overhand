-- games/valormortis/app.lua
-- Overhand for Valor Mortis: the mod's identity and every setting with its vanilla value.

local App = require("core.app")

App.Define({
    name = "Overhand",
    version = "1.6.0",
    menuTitle = "OVERHAND",
    status = "Waiting for a loaded save...",
    settings = {
        godMode = false,
        infiniteStamina = false,
        staminaOnlyOutOfCombat = false,
        staminaCost = 1,            -- share of the normal stamina cost of attacks, dodges and blocks
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
        claymoreParry = false,      -- two-handed (block-only) weapons can parry
        parryWindow = 1,
        dodgeWindow = 1,

        infiniteAmmo = false,
        ammoReload = false,         -- Infinite Ammo keeps the reserve full, you still reload
        infiniteFlasks = false,
        infiniteConsumables = false,
        infiniteBuffs = false,
        noItemCooldowns = false,
        keepCatalysts = false,
        noAbilityCosts = false,
        freeRespec = false,
    },
    -- Not restored on start: you would load into a save flying through walls.
    sessionOnly = { noClip = true },
})

return App
