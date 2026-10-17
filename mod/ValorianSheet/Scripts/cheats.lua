-- ValorCheatMenu / cheats.lua
-- All cheat logic. The menu only writes C.want[...]; everything is applied here on the game thread.
-- Author: BryanHudson
--
-- Note on the game's dev cheat manager (BP_MTCheatManager): its C++ cheat functions (GodMode,
-- NoClip, ...) are empty in the release build and its Cheat.* CVars do not exist (tested in 0.3).
-- Every cheat here therefore has its own implementation. We only use the cheat manager for its
-- data (weapon and material lists), its working cheat actions (gems, ability unlocks) and the
-- engine's IgnoreCosts toggle.

local G = require("game")

local C = {}

-- Desired state, written by the menu. Booleans for toggles, numbers for multipliers.
C.want = {
    godMode = false,
    infStamina = false,
    infBlood = false,
    noFall = false,
    invisible = false,
    noClip = false,
    speedMult = 1,
    jumpMult = 1,
    gameSpeed = 1,
    oneHit = false,
    alwaysParry = false,
    dmgMult = 1,
    dmgTaken = 1,
    maxHealthMult = 1,
    infAmmo = false,
    infFlasks = false,
    infConsumables = false,
    noCooldown = false,
    keepCatalysts = false,
    ignoreCosts = false,
    parryMult = 1,
    toggleSprint = false,
    instantSprint = false,
    infBuffs = false,
    dodgeMult = 1,
    fallDamage = 1,
    staminaOutOfCombat = false,
    regenRate = 0,          -- Health Regeneration: share of max health per second (0 = off)
    regenDelay = 2,         -- seconds without a hit before it starts
    regenOutOfCombat = false,
}

C.status = "Waiting for a loaded save..."

local now = os.clock
local savedChecked = false
local weaponsChecked = false
local readyAt = 0
local lastPlayer = nil

-- ---------------------------------------------------------------------------
-- Overrides with vanilla restore
-- The game changes speeds/multipliers on its own (sprint, buffs, ...). We remember the value the
-- game wants ("base") and write fn(base); when the game writes a new value we take that as the
-- new base. restore() puts the base back.
-- ---------------------------------------------------------------------------

local Override = {}
Override.__index = Override

local function newOverride() return setmetatable({ t = {} }, Override) end

local function asFn(f)
    if type(f) == "function" then return f end
    return function(base) return base * f end
end

-- Plain number property (CharacterMovement.MaxWalkSpeed, ...). f = factor or function(base).
function Override:prop(obj, prop, f)
    local cur = G.Try(function() return obj[prop] end)
    if type(cur) ~= "number" then return end
    local key = tostring(G.Addr(obj)) .. ":" .. prop
    local st = self.t[key]
    if not st then
        st = { obj = obj, prop = prop, base = cur }
        self.t[key] = st
        G.Debug(prop .. ": vanilla " .. tostring(cur))
    elseif st.written and math.abs(cur - st.written) > 0.001 then
        G.Debug(prop .. ": game set " .. tostring(cur) .. ", new base")
        st.base = cur
    end
    local want = asFn(f)(st.base)
    if math.abs(cur - want) > 0.001 then
        G.Try(function() obj[prop] = want end)
    end
    st.written = want
end

-- Gameplay attribute (FGameplayAttributeData). f = factor or function(base).
-- The game saves attributes into the save file, so a changed value survives save/load. To never
-- mistake our own value for vanilla, every value we write is kept in a ledger (config.json):
-- { vanilla = x, written = y }. When the attribute later reads y again (after a load, or after the
-- cheat was switched off while the game was closed), we know its real value is x.
-- Only BaseValue is compared: buffs change CurrentValue and must not be taken as a new vanilla.
C.ledger = {}
local ledgerDirty = false
local function ledgerPut(name, entry)
    C.ledger[name] = entry
    ledgerDirty = true
end

local nextLedgerSave = 0
local function flushLedger()
    if not ledgerDirty or now() < nextLedgerSave then return end
    ledgerDirty = false
    nextLedgerSave = now() + 1
    if C.onLedgerChange then pcall(C.onLedgerChange, C.ledger) end
end

local function getBase(set, name)
    return G.Try(function() return set[name].BaseValue end)
end

-- Sets BaseValue to v and moves CurrentValue by the same amount (keeps active buffs).
local function setBaseKeepMods(set, name, v)
    G.Try(function()
        local a = set[name]
        local base, cur = a.BaseValue, a.CurrentValue
        a.BaseValue = v
        a.CurrentValue = cur + (v - base)
    end)
end

local function near(a, b) return math.abs(a - b) <= math.max(0.0001, math.abs(b) * 0.0001) end

function Override:attr(set, name, f)
    local base = getBase(set, name)
    if type(base) ~= "number" then return end
    local key = tostring(G.Addr(set)) .. ":" .. name
    local st = self.t[key]
    if not st then
        local led = C.ledger[name]
        if led and near(base, led.written) then
            G.Log(name .. ": " .. base .. " is our own value from last time, vanilla is " .. led.vanilla)
            base = led.vanilla
        end
        st = { set = set, attr = name, base = base }
        self.t[key] = st
        G.Debug(name .. ": vanilla " .. tostring(base))
    elseif st.written and not near(base, st.written) then
        G.Debug(name .. ": game set base " .. tostring(base) .. ", new vanilla")
        st.base = base
    end
    local want = asFn(f)(st.base)
    local now_ = getBase(set, name)
    if not near(now_, want) then setBaseKeepMods(set, name, want) end
    if st.written ~= want or not C.ledger[name] then
        ledgerPut(name, { vanilla = st.base, written = want })
    end
    st.written = want
end

function Override:restore()
    for _, st in pairs(self.t) do
        if st.obj and G.Valid(st.obj) then
            local cur = G.Try(function() return st.obj[st.prop] end)
            if type(cur) == "number" and st.written and math.abs(cur - st.written) < 0.001 then
                G.Try(function() st.obj[st.prop] = st.base end)
            end
        elseif st.set then
            if G.Valid(st.set) then
                setBaseKeepMods(st.set, st.attr, st.base)
                G.Debug(st.attr .. ": back to vanilla " .. tostring(st.base))
            end
            ledgerPut(st.attr, nil)
        end
    end
    self.t = {}
end

function Override:forget() self.t = {} end
function Override:active() return next(self.t) ~= nil end

local speedOv = newOverride()
local jumpOv = newOverride()
local dmgOv = newOverride()
local parryOv = newOverride()
local takenOv = newOverride()
local maxHpOv = newOverride()
local flyOv = newOverride()
local accelOv = newOverride()

-- ---------------------------------------------------------------------------
-- No ability costs: the engine's GAS cheat (its toggle works in release builds and its CVar
-- AbilitySystem.IgnoreCosts tells us the real state).
-- ---------------------------------------------------------------------------

local ignore = { state = nil, last = -99 }

local function syncIgnoreCosts()
    -- Our own record decides (never re-toggle because of a CVar read); the CVar only goes to the log.
    local want = C.want.ignoreCosts == true
    local on = ignore.state == true
    if on ~= want and now() - ignore.last > 1.5 then
        ignore.last = now()
        if G.DevCheat("IgnoreCostsToggle") then
            ignore.state = want
            G.Debug("AbilitySystem.IgnoreCosts now reads " .. tostring(G.CVarBool("AbilitySystem.IgnoreCosts")))
        end
    end
end

function C.DevStates()
    return { "AbilitySystem.IgnoreCosts reads " .. tostring(G.CVarBool("AbilitySystem.IgnoreCosts")) }
end

-- ---------------------------------------------------------------------------
-- Dev cheat actions by name (Blueprint actions keep their logic in the release build)
-- ---------------------------------------------------------------------------

local function findAction(name)
    local cm = G.CheatManager()
    local actions = cm and G.Try(function() return cm.CheatActions end)
    if not actions then return nil end
    local found = nil
    G.Try(function()
        actions:ForEach(function(_, el)
            if found then return end
            local a = el:get()
            if G.Valid(a) and G.Try(function() return a.ActionName:ToString() end) == name then found = a end
        end)
    end)
    return found
end

function C.RunAction(name)
    local a = findAction(name)
    if not a then
        G.Log("dev action '" .. name .. "' not found")
        return false
    end
    local cls = G.Try(function() return a:GetClass():GetFName():ToString() end) or "?"
    local ok, err = pcall(function() a:PerformAction() end)
    G.Log("dev action '" .. name .. "' (" .. cls .. ") " .. (ok and "performed" or ("failed: " .. tostring(err))))
    return ok
end

-- Debug only: write the game's whole dev cheat list to the log.
local function dumpCheatActions(cm)
    local actions = G.Try(function() return cm.CheatActions end)
    if not actions then return end
    G.Try(function()
        actions:ForEach(function(_, el)
            local a = el:get()
            if G.Valid(a) then
                local name = G.Try(function() return a.ActionName:ToString() end) or "?"
                local cvar = G.Try(function() return a.CheatCVarName:ToString() end) or ""
                local cls = G.Try(function() return a:GetClass():GetFName():ToString() end) or "?"
                G.Debug("dev action: " .. name .. " <" .. cls .. ">" .. (cvar ~= "" and (" [" .. cvar .. "]") or ""))
            end
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- Own cheats
-- ---------------------------------------------------------------------------

-- Heal William to "target" health in a way the HUD sees right away: through the game's own heal
-- (MTCombatUtils:Overheal, a GameplayEffect, so the health bar animates as usual). If that does
-- not raise his health, the value is written directly and the health bar widget is told.
local healPath = nil -- "game" / "direct", logged once
local function updateHealthBar(hp, max)
    for _, bar in ipairs(FindAllOf("WBP_PlayerHealthVitalsBar_C") or {}) do
        if G.Valid(bar) and not (G.Try(function() return bar:GetFullName() end) or ""):find("Default__", 1, true) then
            G.Try(function() bar:Update(hp / max) end)
        end
    end
end

local function healTo(hs, target)
    local hp, max = G.GetAttr(hs, "Health"), G.GetAttr(hs, "MaxHealth")
    if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return end
    target = math.min(target, max)
    if target <= hp + 0.01 then return end
    local cu, p = G.CombatUtils(), G.Player()
    if healPath ~= "direct" and G.Valid(cu) and p then
        G.Try(function() cu:Overheal(target - hp, p) end)
        local after = G.GetAttr(hs, "Health")
        if type(after) == "number" and after >= target - 0.5 then
            if after > max then G.SetAttr(hs, "Health", max) end -- no overheal above max from us
            if healPath ~= "game" then healPath = "game"; G.Log("healing through the game's heal effect") end
            return
        end
        if healPath == nil then G.Log("game heal did not apply, writing health directly") end
        healPath = "direct"
    end
    G.SetAttr(hs, "Health", target)
    updateHealthBar(target, max)
end

local function godMode()
    local s = G.Set("Health")
    local max = s and G.GetAttr(s, "MaxHealth")
    if type(max) == "number" then healTo(s, max) end
end

local function infStamina()
    local s = G.Set("Stamina")
    if s then G.FillAttr(s, "Stamina", "MaxStamina") end
end

local function infBlood()
    local s = G.Set("Blood")
    if s then G.FillAttr(s, "BloodPoints", "MaxBloodPoints") end
end

local function infFlasks()
    local s = G.Set("Flasks")
    if s then G.FillAttr(s, "HealingFlasks", "HealingFlasksMax") end
end

local ammoTypes = { "Pistol", "Blunderbuss", "Rifle" }
local function infAmmo()
    local s = G.Set("Ranged")
    if not s then return end
    local changed = false
    for _, t in ipairs(ammoTypes) do
        if G.FillAttr(s, t .. "Ammo", "Max" .. t .. "Ammo") then changed = true end
        if G.FillAttr(s, t .. "AmmoInClip", "Max" .. t .. "AmmoInClip") then changed = true end
    end
    -- values written directly do not reach the HUD by themselves: tell the ammo display
    if changed then
        local n = G.Notifier()
        if n then
            local ok = G.Try(function() n:RequestWeaponRefresh() return true end)
            G.Try(function() n:RequestTokenRefresh() end)
            G.Debug("ammo filled, HUD refresh " .. (ok and "requested" or "failed"))
        end
    end
end

-- No fall damage: while William is falling we keep moving his "highest point" down with him,
-- so the game measures a fall of almost zero when he lands.
local MOVE_FALLING, MOVE_FLYING = 3, 5
local safeLandingUntil = 0
local function noFall()
    local p, m = G.Player(), G.Movement()
    if not p or not m then return end
    local mode = G.Try(function() return m.MovementMode end)
    if mode == MOVE_FALLING then
        G.Try(function() p:SetLastApexHeightToCurrentPosition() end)
    end
end

-- Fall Damage (partial): William's fall damage comes from his FallDamageCurve (fall height ->
-- damage). We scale the curve's values; 0 % uses the apex reset above instead. The curve is a game
-- asset that is not saved, the original values come back when the setting goes back to 100 %.
local fallCurve = { addr = nil, curve = nil, orig = nil, applied = 1 }

local function curveKeys(curve, fn)
    G.Try(function()
        curve.FloatCurve.Keys:ForEach(function(i, el) fn(i, el:get()) end)
    end)
end

local function applyFallCurve()
    local f = C.want.fallDamage or 1
    if f <= 0 or C.want.godMode then f = 1 end
    local p = G.Player()
    local c = p and G.Try(function() return p.FallDamageCurve end)
    if not G.Valid(c) then return end
    local addr = G.Addr(c)
    if addr ~= fallCurve.addr then
        fallCurve.addr, fallCurve.curve, fallCurve.orig, fallCurve.applied = addr, c, {}, 1
        local desc = {}
        curveKeys(c, function(i, k)
            fallCurve.orig[i] = k.Value
            desc[#desc + 1] = string.format("%.0f:%.2f", k.Time or 0, k.Value or 0)
        end)
        G.Debug("fall damage curve (height:value): " .. table.concat(desc, " "))
    end
    if f == fallCurve.applied then return end
    curveKeys(c, function(i, k)
        local o = fallCurve.orig[i]
        if type(o) == "number" then k.Value = o * f end
    end)
    fallCurve.applied = f
    G.Log(string.format("fall damage: %d%%", math.floor(f * 100 + 0.5)))
end

-- In a fight? (the game's CombatSubsystem knows; checked 4 times a second)
local combat = { at = -1, value = false }
local function inCombat()
    if now() - combat.at < 0.25 then return combat.value end
    combat.at = now()
    local v = nil
    for _, cs in ipairs(FindAllOf("CombatSubsystem") or {}) do
        local name = G.Try(function() return cs:GetFullName() end) or ""
        if G.Valid(cs) and not name:find("Default__", 1, true) then
            v = G.Try(function() return cs:IsInCombat() end)
            if v ~= nil then break end
        end
    end
    if v == nil then
        for _, es in ipairs(FindAllOf("EnemyInfoSubsystem") or {}) do
            local n = G.Try(function() return es.EnemiesInCombatState:GetArrayNum() end)
            if type(n) == "number" then v = n > 0 break end
        end
    end
    v = v == true
    if v ~= combat.value then G.Debug("combat: " .. (v and "started" or "ended")) end
    combat.value = v
    return v
end

-- Invisible: the game's enemies have their own senses (MTAISenseComponent: sight, hearing, touch).
-- Each sense is an invisible overlap shape around the enemy that notices the player entering it.
-- While the cheat is on we switch the overlap off on every sense, empty what it already perceived,
-- switch off the controller perception and calm down enemies that are already chasing.
-- Everything we touched is switched back on when the cheat goes off. New enemies are picked up
-- every half second.
local invisibleOn = false
local blinded = {}        -- address -> { kind, obj }
local nextBlindScan = 0
local AGGRO_IDLE = 3

local function blindEnemies()
    if now() < nextBlindScan then return end
    nextBlindScan = now() + 0.5
    local senses, ctrls = 0, 0
    local playerAddr = G.Addr(G.Player())

    for _, sense in ipairs(FindAllOf("MTAISenseComponent") or {}) do
        local addr = G.Valid(sense) and G.Addr(sense)
        local owner = addr and G.Try(function() return sense:GetOwner() end)
        if addr and not blinded[addr] and G.Valid(owner) and G.Addr(owner) ~= playerAddr then
            local shape = G.Try(function() return sense.SenseOverlapComponent end)
            if G.Valid(shape) and G.Try(function() shape:SetGenerateOverlapEvents(false) return true end) then
                G.Try(function() sense:ResetSense() end)
                blinded[addr] = { kind = "sense", obj = shape }
                senses = senses + 1
            end
        end
    end

    for _, ctrl in ipairs(FindAllOf("EnemyController") or {}) do
        local addr = G.Valid(ctrl) and G.Addr(ctrl)
        if addr and not blinded[addr] and G.Try(function() ctrl:DisablePerception() return true end) then
            G.Try(function()
                ctrl.bIsPlayerVisible = false
                ctrl.bWasPlayerVisible = false
                ctrl.bNoiseHeared = false
                ctrl.bTouched = false
            end)
            -- calm the enemy down if it is already after us
            local enemy = G.Try(function() return ctrl.OwnerCharacter end)
            local aggro = G.Valid(enemy) and G.Try(function() return enemy.AggroComponent end)
            if G.Valid(aggro) then
                G.Try(function() aggro:SetAggroValue(0.0) end)
                G.Try(function() aggro:SetNewAggroState(AGGRO_IDLE) end)
            end
            blinded[addr] = { kind = "ctrl", obj = ctrl }
            ctrls = ctrls + 1
        end
    end

    if senses + ctrls > 0 then G.Debug("invisible: blinded " .. senses .. " senses, " .. ctrls .. " enemy controllers") end
end

local function setInvisible(on)
    if on then
        nextBlindScan = 0
        blindEnemies()
    else
        local senses, ctrls = 0, 0
        for addr, e in pairs(blinded) do
            if G.Valid(e.obj) then
                if e.kind == "sense" then
                    if G.Try(function() e.obj:SetGenerateOverlapEvents(true) return true end) then senses = senses + 1 end
                else
                    if G.Try(function() e.obj:EnablePerception() return true end) then ctrls = ctrls + 1 end
                end
            end
            blinded[addr] = nil
        end
        G.Debug("invisible: restored " .. senses .. " senses, " .. ctrls .. " enemy controllers")
    end
    G.Log("invisible to enemies " .. (on and "ON" or "OFF"))
    invisibleOn = on
end

-- NoClip: fly mode without collision. Space / A = up, Ctrl / B = down.
local noClipOn = false
local keyCache = {}
local function keyDown(names)
    local pc = G.Controller()
    if not pc then return false end
    for _, n in ipairs(names) do
        keyCache[n] = keyCache[n] or { KeyName = FName(n) }
        if G.Try(function() return pc:IsInputKeyDown(keyCache[n]) end) == true then return true end
    end
    return false
end
local UP_KEYS = { "SpaceBar", "Gamepad_FaceButton_Bottom" }
local DOWN_KEYS = { "LeftControl", "C", "Gamepad_FaceButton_Right" }
local FLY_SPEED = 1200

local function setNoClip(on)
    local p, m = G.Player(), G.Movement()
    if not p or not m then return end
    if on then
        G.Try(function() p:SetActorEnableCollision(false) end)
        G.Try(function() m:SetMovementMode(MOVE_FLYING, 0) end)
    else
        flyOv:restore()
        G.Try(function() p:SetActorEnableCollision(true) end)
        G.Try(function() m:SetMovementMode(MOVE_FALLING, 0) end)
        safeLandingUntil = now() + 4 -- no fall damage when dropping out of noclip
    end
    noClipOn = on
    G.Log("noclip " .. (on and "ON" or "OFF"))
end

local function noClipTick()
    local p, m = G.Player(), G.Movement()
    if not p or not m then return end
    if G.Try(function() return m.MovementMode end) ~= MOVE_FLYING then
        G.Try(function() m:SetMovementMode(MOVE_FLYING, 0) end)
    end
    flyOv:prop(m, "MaxFlySpeed", function() return FLY_SPEED end)
    flyOv:prop(m, "BrakingDecelerationFlying", function() return 6000 end)
    local z = 0
    if keyDown(UP_KEYS) then z = FLY_SPEED elseif keyDown(DOWN_KEYS) then z = -FLY_SPEED end
    G.Try(function()
        local v = m.Velocity
        m.Velocity = { X = v.X, Y = v.Y, Z = z }
    end)
end

local nextCooldown = 0
local function noCooldown()
    if now() < nextCooldown then return end
    nextCooldown = now() + 0.25
    local inv, p = G.Inventory(), G.Player()
    if inv and p then
        G.Try(function() inv:TrySetAllConsumableInventoryItemsCooldown(p, 0.0) end)
    end
end

-- Keep catalysts: once William is back on his feet, pick his deathmark up for him right away.
local markHandled = {}
local function keepCatalysts()
    local p = G.Player()
    if not p or not G.IsAlive() then return end
    if G.Try(function() return p.bRespawning end) == true then return end
    local mark = G.Try(function() return p.DeathmarkRef end)
    if not G.Valid(mark) then return end
    local addr = G.Addr(mark)
    local t = markHandled[addr]
    if t and now() < t then return end
    markHandled[addr] = now() + 3
    if G.Try(function() mark:ForcePickup() return true end) then
        G.Log("deathmark picked up (catalysts kept)")
    end
end

-- Infinite consumables: the game's item database lists every consumable (grenades, syringes,
-- potions, ...). We watch how many William carries and give back whatever was used up.
-- (Hooks on the "use item" functions do not work: the game calls them from C++.)
local cons = { tags = nil, last = {}, nextPoll = 0, stuck = {}, check = {}, peak = {}, nextPeak = 0 }

-- The database maps a category (Items.Consumable.Grenade) to its real items
-- (Items.Consumable.Grenade.Regular, ...Oil). We want the real items.
local function consumableTags()
    if cons.tags then return cons.tags end
    local inv = G.Inventory()
    local db = inv and G.Try(function() return inv.InventoryDatabaseAsset end)
    if not G.Valid(db) then return nil end
    local tags, cats = {}, 0
    G.Try(function()
        db.ConsumableItemsMap:ForEach(function(catKey, item)
            cats = cats + 1
            local before = #tags
            G.Try(function()
                item:get().ItemMap:ForEach(function(key)
                    local name = G.Try(function() return key:get().TagName:ToString() end)
                    if name and name ~= "None" then tags[#tags + 1] = name end
                end)
            end)
            if #tags == before then
                -- category without sub items: use the category tag itself
                local name = G.Try(function() return catKey:get().TagName:ToString() end)
                if name and name ~= "None" then tags[#tags + 1] = name end
            end
        end)
    end)
    if #tags == 0 then return nil end
    table.sort(tags)
    cons.tags = tags
    G.Log("consumables: " .. #tags .. " items in " .. cats .. " categories")
    G.Debug("consumables: " .. table.concat(tags, ", "))
    return tags
end

local function itemCount(save, name)
    local n = G.Try(function() return save:TryGetInventoryItemCount({ TagName = FName(name) }) end)
    if type(n) == "number" then return n end
end

local function infConsumables()
    if now() < cons.nextPoll then return end
    cons.nextPoll = now() + 0.25
    local tags, save, inv = consumableTags(), G.Save(), G.Inventory()
    if not tags or not save or not inv then return end
    for _, name in ipairs(tags) do
        local n = itemCount(save, name)
        if n then
            local last = cons.last[name]
            if cons.check[name] then
                -- we gave this one back on the last poll: did it arrive?
                cons.check[name] = nil
                if last and n < last then
                    cons.stuck[name] = true
                    G.Log("consumable " .. name .. ": give back did not stick (" .. n .. "/" .. last .. "), skipping it")
                end
                cons.last[name] = n
            elseif last and n < last and not cons.stuck[name] then
                local missing = last - n
                if G.Try(function() inv:AddInventoryItem({ TagName = FName(name) }, missing) return true end) then
                    G.Debug("consumable " .. name .. " +" .. missing .. " (given back)")
                    cons.check[name] = true
                else
                    cons.stuck[name] = true
                    G.Log("consumable " .. name .. ": AddInventoryItem failed, skipping it")
                end
            elseif not last or n > last then
                cons.last[name] = n
            end
        end
    end
end

local function resetConsumables()
    cons.last = {}
    cons.stuck = {}
    cons.check = {}
end

-- Remember the most William carried of every consumable this session, so Refill Everything
-- can put back what was used (grenades, syringes, potions, ...).
local function trackPeaks()
    if now() < cons.nextPeak then return end
    cons.nextPeak = now() + 1
    local tags, save = consumableTags(), G.Save()
    if not tags or not save then return end
    for _, name in ipairs(tags) do
        local n = itemCount(save, name)
        if n and n > (cons.peak[name] or 0) then cons.peak[name] = n end
    end
end

local function refillConsumables()
    local tags, save, inv = consumableTags(), G.Save(), G.Inventory()
    if not tags or not save or not inv then return 0 end
    local refilled = 0
    for _, name in ipairs(tags) do
        if not name:find("Catalyst", 1, true) then
            local n, peak = itemCount(save, name), cons.peak[name]
            if n and peak and n < peak then
                if G.Try(function() inv:AddInventoryItem({ TagName = FName(name) }, peak - n) return true end) then
                    G.Debug("refill " .. name .. " " .. n .. " -> " .. peak)
                    refilled = refilled + 1
                end
            end
        end
    end
    cons.last = {} -- new baseline for Infinite Consumables
    return refilled
end

-- Perfect parry on every block: a huge parry window on William's side (the attribute the
-- "Forgiving Parry" gem raises) and no parry cooldown / spam penalty on his weapon.
local PARRY_EXTRA = 5.0
local function applyParry(on)
    if not on then
        if parryOv:active() then parryOv:restore() end
        return
    end
    local melee = G.Set("Melee")
    if melee then parryOv:attr(melee, "ParryWindowAdjustment", function(base) return base + PARRY_EXTRA end) end
    local p = G.Player()
    local weapon = p and G.Try(function() return p.CurrentMeleeWeapon end)
    if G.Valid(weapon) then
        parryOv:prop(weapon, "PerfectParryCooldown", 0)
        parryOv:prop(weapon, "PerfectParrySpamReduction", 0)
    end
end

-- Parry Window: when an enemy hit reaches William's block, the game checks the attack's
-- PerfectParryOpeningTime (MTCombatUtils:CheckBlockMelee / ...ForProperties / CheckBlockProjectile).
-- We scale that value for this one check (the attack data is a copy, nothing is saved).
local parryHooks = { done = false, n = 0 }
local PARRY_FUNCS = { "CheckBlockMelee", "CheckBlockMeleeForProperties", "CheckBlockProjectile" }

local function onBlockCheck(fn, dataPrm, blockerPrm)
    local f = C.want.parryMult or 1
    if f == 1 then return end
    local p = G.Player()
    local b = blockerPrm and G.Try(function() return blockerPrm:get() end)
    if not p or not G.Valid(b) or G.Addr(b) ~= G.Addr(p) then return end
    local data = G.Try(function() return dataPrm:get() end)
    local v = data and G.Try(function() return data.PerfectParryOpeningTime end)
    if type(v) ~= "number" then return end
    G.Try(function() data.PerfectParryOpeningTime = v * f end)
    local after = G.Try(function() return dataPrm:get().PerfectParryOpeningTime end)
    if type(after) == "number" and math.abs(after - v * f) > 0.0001 then
        -- the struct came back as a copy: write it back as a whole
        G.Try(function() dataPrm:set(data) end)
        after = G.Try(function() return dataPrm:get().PerfectParryOpeningTime end)
    end
    parryHooks.n = parryHooks.n + 1
    if parryHooks.n <= 3 or G.debugOn then
        G.Log(string.format("parry window x%s (%s): %.3f -> %s", tostring(f), fn, v, tostring(after)))
    end
end

local function hookParry()
    if parryHooks.done then return end
    parryHooks.done = true
    local ok_n = 0
    for _, fn in ipairs(PARRY_FUNCS) do
        local ok = pcall(RegisterHook, "/Script/MinotaurCore.MTCombatUtils:" .. fn, function(_, data, blocker)
            pcall(onBlockCheck, fn, data, blocker)
        end)
        if ok then ok_n = ok_n + 1 end
    end
    G.Log("parry window: hooked " .. ok_n .. " block checks")
end

-- Toggle Sprint: on a gamepad the game's sprint ability (GA_Sprint) already works as a toggle; it
-- keeps a flag for that. With Toggle Sprint on we set that flag for the keyboard too.
local sprint = { abilities = {}, nextFind = 0, set = false }

local function applyToggleSprint()
    local on = C.want.toggleSprint == true
    if not on and not sprint.set then return end
    if now() >= sprint.nextFind then
        sprint.nextFind = now() + 1
        sprint.abilities = {}
        for _, a in ipairs(FindAllOf("GA_Sprint_C") or {}) do
            local name = G.Try(function() return a:GetFullName() end) or ""
            if G.Valid(a) and not name:find("Default__", 1, true) then sprint.abilities[#sprint.abilities + 1] = a end
        end
    end
    for _, a in ipairs(sprint.abilities) do
        if G.Valid(a) then
            local cur = G.Try(function() return a.bGamepadInput end)
            if on and cur == false then
                G.Try(function() a.bGamepadInput = true end)
                if not sprint.set then G.Log("toggle sprint: sprint ability set to toggle") end
                sprint.set = true
            elseif not on and sprint.set and cur == true then
                G.Try(function() a.bGamepadInput = false end)
            end
        end
    end
    if not on then sprint.set = false end
end

-- Damage Taken: we watch William's health and give back (1 - factor) of every loss right away,
-- so at 10% he keeps 90% of every hit. (The health set's DamageMultiplier does not change the
-- damage he takes, tested in 1.0.2.) A hit bigger than his current health still kills, so for
-- big hits Max Health is the better choice.
-- Max Health: MaxHealth times the factor; current health is scaled with it so the bar keeps its fill.
local appliedHpMult = 1
local lastHp = nil

-- Damage Taken / God Mode, part 1 (before the hit lands): the game deals damage through MTCombatUtils
-- functions. We hook them and scale the damage values when the target is William, so the bar only
-- drops by the reduced amount and the reduction works down to 0 health.
-- Part 2 (fallback, below in applyDefense): for damage that does not go through these functions we
-- give back the share right after the hit.
local dmgHooks = { done = false, lastAt = -99, hits = 0 }

-- function -> positions (1-based, after the context object) of the damage values and of the target
-- function -> positions (1-based, after the context object) of the damage values, the target and
-- the attacker
local DAMAGE_FUNCS = {
    DealMeleeDamage = { dmg = { 1 }, target = 2, attacker = 4 },
    DealRangedDamage = { dmg = { 1 }, target = 2, attacker = 4 },
    DealExplosiveDamage = { dmg = { 1 }, target = 2, attacker = 4 },
    DealEnvironmentalDamage = { dmg = { 1 }, target = 2, attacker = 4 },
    DealCriticalDamage = { dmg = { 1 }, target = 2, attacker = 4 },
    DealIgniteDamage = { dmg = { 1 }, target = 2, attacker = 3 },
    DealInfectionDamage = { dmg = { 1 }, target = 2, attacker = 3 },
    DealCrystallizationDamage = { dmg = { 1 }, target = 2, attacker = 3 },
    DealDamage = { dmg = { 2 }, target = 3, attacker = 4 },
    DealDamageWithEffect = { dmg = { 3 }, target = 4, attacker = 5 },
    DealCombinedDamage = { dmg = { 2, 3, 4, 5, 7, 8, 10 }, target = 12, attacker = 13 },
}

local ONE_HIT_FACTOR = 100000

-- Is this actor William, or something he fired (projectile, grenade: its Instigator is William)?
local function isPlayerActor(a, pAddr)
    if not G.Valid(a) then return false end
    if G.Addr(a) == pAddr then return true end
    local inst = G.Try(function() return a.Instigator end)
    return G.Valid(inst) and G.Addr(inst) == pAddr
end

local function scaleParams(spec, params, f)
    for _, i in ipairs(spec.dmg) do
        local prm = params[i]
        local v = prm and G.Try(function() return prm:get() end)
        if type(v) == "number" and v > 0 then
            G.Try(function() prm:set(v * f) end)
        end
    end
end

local function onDamage(fn, spec, params)
    local p = G.Player()
    if not p then return end
    local pAddr = G.Addr(p)
    local tp, ap = params[spec.target], params[spec.attacker]
    local target = tp and G.Try(function() return tp:get() end)
    local attacker = ap and G.Try(function() return ap:get() end)

    if G.Valid(target) and G.Addr(target) == pAddr then
        -- incoming: God Mode = no damage at all; otherwise the Damage Taken share
        local f = C.want.godMode and 0 or (C.want.dmgTaken or 1)
        if f >= 1 then return end
        scaleParams(spec, params, f)
        dmgHooks.lastAt = now()
        dmgHooks.hits = dmgHooks.hits + 1
        if dmgHooks.hits <= 3 or G.debugOn then G.Log("damage reduced before the hit (" .. fn .. ")") end
        return
    end

    if isPlayerActor(attacker, pAddr) then
        -- outgoing: One-Hit Kills / Damage Multiplier. Only the hit is changed, nothing is saved.
        local f = C.want.oneHit and ONE_HIT_FACTOR or (C.want.dmgMult or 1)
        if f == 1 then return end
        scaleParams(spec, params, f)
        dmgHooks.outHits = (dmgHooks.outHits or 0) + 1
        if dmgHooks.outHits <= 3 or G.debugOn then G.Log("your damage x" .. f .. " (" .. fn .. ")") end
    end
end

local function hookDamage()
    if dmgHooks.done then return end
    dmgHooks.done = true
    local ok_n = 0
    for fn, spec in pairs(DAMAGE_FUNCS) do
        -- depth: when one damage function calls another through script, only the outer one is scaled
        local ok = pcall(RegisterHook, "/Script/MinotaurCore.MTCombatUtils:" .. fn, function(_, ...)
            dmgHooks.depth = (dmgHooks.depth or 0) + 1
            if dmgHooks.depth == 1 then
                local params = { ... }
                pcall(onDamage, fn, spec, params)
            end
        end, function()
            dmgHooks.depth = math.max((dmgHooks.depth or 1) - 1, 0)
        end)
        if ok then ok_n = ok_n + 1 end
    end
    G.Log("damage: hooked " .. ok_n .. " damage functions")
end

local function applyDefense()
    local hs = G.Set("Health")
    if not hs then
        lastHp = nil
        return
    end
    if takenOv:active() then takenOv:restore() end -- older builds touched DamageMultiplier

    local mult = C.want.maxHealthMult or 1
    if mult ~= 1 then
        maxHpOv:attr(hs, "MaxHealth", mult)
    elseif maxHpOv:active() then
        maxHpOv:restore()
    end
    if mult ~= appliedHpMult then
        local hp, max = G.GetAttr(hs, "Health"), G.GetAttr(hs, "MaxHealth")
        if type(hp) == "number" and type(max) == "number" and hp > 0 then
            local newHp = math.min(hp * mult / appliedHpMult, max)
            G.SetAttr(hs, "Health", newHp)
            G.Debug("max health x" .. mult .. ": MaxHealth=" .. max .. ", Health " .. hp .. " -> " .. newHp)
        end
        appliedHpMult = mult
        lastHp = nil -- our own change, not damage
    end

    local hp, max = G.GetAttr(hs, "Health"), G.GetAttr(hs, "MaxHealth")
    if type(hp) ~= "number" or type(max) ~= "number" then return end
    local taken = C.want.dmgTaken or 1
    if taken < 1 or C.want.godMode or C.want.oneHit or (C.want.dmgMult or 1) ~= 1 then hookDamage() end
    local hookedRecently = now() - dmgHooks.lastAt < 0.5
    if taken < 1 and not hookedRecently and lastHp and hp < lastHp - 0.5 and hp > 0 then
        local loss = lastHp - hp
        healTo(hs, hp + loss * (1 - taken))
        local after = G.GetAttr(hs, "Health")
        G.Debug(string.format("damage taken %.0f%% (fallback): lost %.1f, gave back %.1f", taken * 100, loss, (after or hp) - hp))
        hp = after or hp
    end
    lastHp = hp
end

-- Health Regeneration: William slowly heals by a share of his max health per second, starting a
-- few seconds after the last hit (optionally only out of combat). Healing is applied in small steps
-- four times a second, written directly so the game's heal effect and sound do not fire every step.
local regen = { lastHp = nil, lastHitAt = -99, lastStep = nil, logged = false }
local function healthRegen()
    local rate = C.want.regenRate or 0
    local hs = G.Set("Health")
    local hp = hs and G.GetAttr(hs, "Health")
    local max = hs and G.GetAttr(hs, "MaxHealth")
    if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then
        regen.lastHp, regen.lastStep = nil, nil
        return
    end
    local t = now()
    if regen.lastHp and hp < regen.lastHp - 0.01 then regen.lastHitAt = t end
    regen.lastHp = hp
    if rate <= 0 or hp <= 0 or hp >= max then regen.lastStep = nil return end
    if t - regen.lastHitAt < (C.want.regenDelay or 2) then regen.lastStep = nil return end
    if C.want.regenOutOfCombat and inCombat() then regen.lastStep = nil return end
    if not regen.lastStep then regen.lastStep = t return end
    local dt = t - regen.lastStep
    if dt < 0.25 then return end
    regen.lastStep = t
    local new = math.min(max, hp + max * rate * math.min(dt, 1))
    G.SetAttr(hs, "Health", new)
    updateHealthBar(new, max)
    regen.lastHp = G.GetAttr(hs, "Health") or new
    if not regen.logged then
        regen.logged = true
        G.Log(string.format("health regeneration: %.0f%% of max health per second", rate * 100))
    end
end

-- Health bar length: the HUD (WBP_PlayerVitals) makes the health bar longer the more max health
-- William has: the bar's width is (width per point of max health) x MaxHealth. With Max Health at 3x
-- or 5x it runs off the screen. While Max Health is raised we keep the bar at the width it would have
-- with the vanilla max health; the fill still shows the real share of the raised max health.
-- The width per point is learned from the game's own layout (250 px for 100 max health in 1.0).
local hpBar = { obj = nil, addr = nil, k = nil, setX = nil, wasOn = false, dumps = 0, logs = 0 }
local DEFAULT_PX_PER_HP = 2.5

local function hudNum(fn)
    local ok, v = pcall(fn)
    if ok and type(v) == "number" then return v end
    return nil
end

-- The HUD widget that belongs to the current William. After loading a save the old HUD can stay
-- valid for a while next to the new one, so it is checked by its owner, not only by being valid.
-- FindAllOf walks every object, so the widget is kept and only searched again every 2 s while missing.
local function ownedByPlayer(w, pAddr)
    local pawn = G.Try(function() return w:GetOwningPlayerPawn() end)
    if not (pawn and G.Valid(pawn)) then return nil end -- owner unknown
    return G.Addr(pawn) == pAddr
end

local function playerVitals()
    local p = G.Player()
    local pAddr = p and G.Addr(p)
    if hpBar.obj and G.Valid(hpBar.obj) then
        if now() < (hpBar.nextOwnerCheck or 0) then return hpBar.obj end
        hpBar.nextOwnerCheck = now() + 1
        if ownedByPlayer(hpBar.obj, pAddr) ~= false then return hpBar.obj end
        G.Debug("health bar: HUD belongs to an old William, looking for the new one")
    end
    hpBar.obj = nil
    if now() < (hpBar.nextFind or 0) then return nil end
    hpBar.nextFind = now() + 2
    local fallback = nil
    for _, w in ipairs(FindAllOf("WBP_PlayerVitals_C") or {}) do
        if G.Valid(w) and not (G.Try(function() return w:GetFullName() end) or ""):find("Default__", 1, true) then
            local mine = ownedByPlayer(w, pAddr)
            if mine == true then hpBar.obj = w return w end
            if mine == nil then fallback = w end
        end
    end
    hpBar.obj = fallback
    return fallback
end

-- Forget the HUD after a load or a new William, so the new HUD is found.
function hpBar.forget()
    hpBar.obj, hpBar.addr, hpBar.setX, hpBar.seenX, hpBar.nextFind = nil, nil, nil, nil, 0
end

local function className(obj)
    return G.Try(function() return obj:GetClass():GetFName():ToString() end) or "?"
end

-- Layout values of one widget that the HUD could use to size the bar (all read right away, no
-- waiting for the next frame).
local function widgetLayout(w)
    local t = {}
    local slot = G.Try(function() return w.Slot end)
    if slot and G.Valid(slot) then
        t.slot = className(slot)
        t.sx = hudNum(function() return slot:GetSize().X end)
        t.sy = hudNum(function() return slot:GetSize().Y end)
        t.ox = hudNum(function() return slot.LayoutData.Offsets.Right end)
        t.px = hudNum(function() return slot.LayoutData.Offsets.Left end)
        t.fill = hudNum(function() return slot.Size.Value end)
    end
    t.scale = hudNum(function() return w.RenderTransform.Scale.X end)
    t.wo = hudNum(function() return w.WidthOverride end)
    t.minw = hudNum(function() return w.MinDesiredWidth end)
    t.pct = hudNum(function() return w.Percent end)
    return t
end

local function layoutText(name, w)
    local t = widgetLayout(w)
    local parts = { name .. " <" .. className(w) .. ">" }
    for _, k in ipairs({ "slot", "sx", "sy", "px", "ox", "fill", "scale", "wo", "minw", "pct" }) do
        if t[k] ~= nil then parts[#parts + 1] = k .. "=" .. (type(t[k]) == "number" and string.format("%.2f", t[k]) or t[k]) end
    end
    return table.concat(parts, " ")
end

-- The widgets whose layout we watch: the health bar, its parents, the bonus health bar and frame image.
local function watchedWidgets(v)
    local list = {}
    local bar = G.Try(function() return v.PlayerHealthVitalsBar end)
    if bar and G.Valid(bar) then
        list[#list + 1] = { "PlayerHealthVitalsBar", bar }
        local p = bar
        for i = 1, 3 do
            p = G.Try(function() return p:GetParent() end)
            if not (p and G.Valid(p)) then break end
            list[#list + 1] = { "parent" .. i, p }
        end
    end
    for _, n in ipairs({ "BonusHealth", "Image_112" }) do
        local w = G.Try(function() return v[n] end)
        if w and G.Valid(w) then list[#list + 1] = { n, w } end
    end
    return list
end

local function dumpHud(v, why)
    if hpBar.dumps >= 12 and not G.debugOn then return end
    hpBar.dumps = hpBar.dumps + 1
    local hs = G.Set("Health")
    G.Log(string.format("health bar (%s): MaxHealth=%s base=%s mult=%s InitialHealthBarXSize=%s", why,
        tostring(hs and G.GetAttr(hs, "MaxHealth")), tostring(hs and getBase(hs, "MaxHealth")),
        tostring(C.want.maxHealthMult or 1), tostring(hudNum(function() return v.InitialHealthBarXSize end))))
    for _, e in ipairs(watchedWidgets(v)) do G.Log("  " .. layoutText(e[1], e[2])) end
end

local function healthBarSlot(v)
    local bar = G.Try(function() return v.PlayerHealthVitalsBar end)
    local slot = bar and G.Valid(bar) and G.Try(function() return bar.Slot end)
    if slot and G.Valid(slot) then return slot end
    return nil
end

local function fixHealthBar()
    local mult = C.want.maxHealthMult or 1
    if mult == 1 and not hpBar.wasOn and hpBar.addr and not G.debugOn then return end -- nothing to do
    if now() < (hpBar.nextCheck or 0) then return end
    hpBar.nextCheck = now() + 0.2
    local v = playerVitals()
    if not v then hpBar.addr = nil return end
    local addr = G.Addr(v)
    local fresh = addr ~= hpBar.addr
    if fresh then
        hpBar.addr, hpBar.setX = addr, nil
        dumpHud(v, "HUD found")
    end
    local hs = G.Set("Health")
    local max = hs and G.GetAttr(hs, "MaxHealth")
    local base = hs and getBase(hs, "MaxHealth")
    if type(max) ~= "number" or max <= 0 or type(base) ~= "number" or base <= 0 then return end
    local slot = healthBarSlot(v)
    if not slot then return end
    local sx = hudNum(function() return slot:GetSize().X end)
    local sy = hudNum(function() return slot:GetSize().Y end)
    if not sx or not sy then return end

    -- a new width we did not set comes from the game: learn its width per point of max health
    local changed = fresh or not hpBar.seenX or math.abs(sx - hpBar.seenX) > 0.5
    hpBar.seenX = sx
    if changed and not (hpBar.setX and math.abs(sx - hpBar.setX) <= 0.5) then
        if not fresh then dumpHud(v, "game changed the bar") end
        hpBar.setX = nil
        local k = sx / max
        if k > 0.05 and k < 50 and (mult == 1 or appliedHpMult == mult) then
            if not hpBar.k or math.abs(k - hpBar.k) > 0.001 then G.Debug(string.format("health bar: %.3f px per max health", k)) end
            hpBar.k = k
        end
    end

    local function setWidth(x, why)
        if math.abs(sx - x) <= 0.5 then hpBar.setX = sx return end
        local ok = pcall(function() slot:SetSize({ X = x, Y = sy }) end)
        hpBar.setX = hudNum(function() return slot:GetSize().X end) or x
        hpBar.seenX = hpBar.setX
        if hpBar.logs < 20 or G.debugOn then
            hpBar.logs = hpBar.logs + 1
            G.Log(string.format("health bar: width %.0f -> %.0f (%s)%s", sx, hpBar.setX, why, ok and "" or ", SetSize failed"))
        end
    end

    if mult == 1 then
        if hpBar.wasOn then
            hpBar.wasOn = false
            setWidth((hpBar.k or DEFAULT_PX_PER_HP) * max, "Max Health off, game width")
            hpBar.setX = nil
        end
        return
    end
    hpBar.wasOn = true
    if appliedHpMult ~= mult then return end -- Max Health not applied yet this tick
    local vanilla = max - base + base / mult -- vanilla max health, buffs kept
    setWidth((hpBar.k or DEFAULT_PX_PER_HP) * vanilla, string.format("Max Health x%s, vanilla max health %.0f", tostring(mult), vanilla))
end

-- ---------------------------------------------------------------------------
-- Values the game saved while a cheat was on (checked once after every load)
-- ---------------------------------------------------------------------------

-- attribute -> which set it lives in and whether its cheat is on right now
local LEDGER_ATTRS = {
    MaxHealth = { set = "Health", on = function() return (C.want.maxHealthMult or 1) ~= 1 end },
    ParryWindowAdjustment = { set = "Melee", on = function() return C.want.alwaysParry == true end },
}

local function cdoBase(cls, name)
    local cdo = G.Static("/Script/MinotaurCore.Default__" .. cls)
    local v = cdo and G.Try(function() return cdo[name].BaseValue end)
    if type(v) == "number" and v >= 0.05 and v <= 20 then return v end
    return 1
end

-- 1.1.0 and older put One-Hit Kills (x1000) and the Damage Multiplier (up to x10) into the damage
-- multipliers, which the game saves. The game itself never changes their base value (weapon and gem
-- bonuses are effects on top of it), so a base value of 1.4x the game's default or more can only come
-- from that and is put back to the default. Active bonuses are kept.
local function repairDamage()
    local fixed = 0
    for _, d in ipairs({ { "Melee", "MeleeAttributeSet", "MeleeDamageMultiplier" }, { "Ranged", "RangedAttributeSet", "RangedDamageMultiplier" } }) do
        local set = G.Set(d[1])
        local base = set and getBase(set, d[3])
        local cur = set and G.GetAttr(set, d[3])
        local def = cdoBase(d[2], d[3])
        G.Debug(d[3] .. ": base " .. tostring(base) .. ", current " .. tostring(cur) .. ", game default " .. tostring(def))
        if type(base) == "number" and base >= def * 1.4 then
            setBaseKeepMods(set, d[3], def)
            G.Log("repaired " .. d[3] .. ": " .. base .. " -> " .. def .. " (left over from an older version)")
            fixed = fixed + 1
        end
    end
    local hs = G.Set("Health")
    if hs then
        G.Debug("MaxHealth: base " .. tostring(getBase(hs, "MaxHealth")) .. ", current " .. tostring(G.GetAttr(hs, "MaxHealth")))
    end
    if fixed > 0 then C.status = "Repaired your damage values (left over from an older version)" end
end

local function checkSavedValues()
    repairDamage()
    for name, info in pairs(C.ledger) do
        local la = LEDGER_ATTRS[name]
        local set = la and G.Set(la.set)
        local base = set and getBase(set, name)
        if type(info) ~= "table" or type(info.vanilla) ~= "number" or type(info.written) ~= "number" then
            ledgerPut(name, nil)
        elseif set and type(base) == "number" then
            if not near(base, info.written) then
                G.Debug(name .. ": saved value " .. base .. " is not ours, ledger entry dropped")
                ledgerPut(name, nil)
            elseif la.on() then
                -- cheat still on: the override picks the real vanilla from the ledger
                if name == "MaxHealth" and info.vanilla > 0 then appliedHpMult = info.written / info.vanilla end
            else
                setBaseKeepMods(set, name, info.vanilla)
                if name == "MaxHealth" and info.written > 0 then
                    local hp = G.GetAttr(set, "Health")
                    if type(hp) == "number" then
                        G.SetAttr(set, "Health", math.min(hp * info.vanilla / info.written, info.vanilla))
                    end
                end
                G.Log(name .. ": put back to vanilla " .. info.vanilla .. " (was saved while the cheat was on)")
                ledgerPut(name, nil)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Infinite Buffs: potions, weapon coatings and pistol boosts never run out.
-- Every active buff gets a very long duration; the old one comes back when the cheat is switched off.
-- Buffs are saved with their remaining time, so after a load with the cheat off, buffs that still
-- have our long time get 2 more minutes.
-- ---------------------------------------------------------------------------

local BUFF_EFFECTS = {
    GE_Bubble_C = true, GE_ProtectionPotion_C = true, GE_StaminaPotion_C = true, GE_Rage_C = true,
    GE_FlamingCoating_C = true, GE_SharpCoating_C = true, GE_StasisCoating_C = true,
    GE_FlamingBoost_C = true, GE_PreciseBoost_C = true, GE_StasisBoost_C = true, GE_ConcussingBoost_C = true,
}
local BUFF_LONG = 36000      -- 10 hours
local BUFF_LEFTOVER = 120    -- what a leftover long buff gets when the cheat is off
local buffs = { nextScan = 0, orig = {}, peak = {}, handles = {}, logged = false, hooked = false }

-- The ability system keeps every active effect in ActiveGameplayEffects.GameplayEffects_Internal
-- (Spec.Def = effect, Spec.Duration, StartWorldTime). When an effect's timer runs out the game
-- checks Spec.Duration again and keeps the effect if the duration was made longer, so a longer
-- Spec.Duration is all it takes.
local function worldTime()
    local gs, p = G.GameplayStatics(), G.Player()
    return p and G.Try(function() return gs:GetTimeSeconds(p) end)
end

-- calls fn(effect, name) for every active buff on William
local function forEachBuff(fn)
    local p = G.Player()
    local asc = p and G.Try(function() return p.AbilitySystemComponent end)
    if not G.Valid(asc) then return 0 end
    local arr = G.Try(function() return asc.ActiveGameplayEffects.GameplayEffects_Internal end)
    if not arr then
        if not buffs.logged then buffs.logged = true; G.Log("infinite buffs: effect list not readable") end
        return 0
    end
    local names, n = {}, 0
    local ok, err = pcall(function()
        arr:ForEach(function(_, el)
            local e = el:get()
            local def = G.Try(function() return e.Spec.Def end)
            local name = def and G.Try(function() return def:GetClass():GetFName():ToString() end)
            if name then names[#names + 1] = name end
            if name and BUFF_EFFECTS[name] then
                n = n + 1
                fn(e, name)
            end
        end)
    end)
    if not ok then G.Debug("infinite buffs: " .. tostring(err)) end
    if G.debugOn and not buffs.logged and #names > 0 then
        buffs.logged = true
        G.Debug("active effects: " .. table.concat(names, ", "))
    end
    return n
end

local function infBuffs()
    if now() < buffs.nextScan then return end
    local on = C.want.infBuffs == true
    buffs.nextScan = now() + (on and 0.1 or 0.5)
    local t = worldTime()
    if type(t) ~= "number" then return end
    local seen = {}
    local refreshHud = false
    forEachBuff(function(e, name)
        local start = G.Try(function() return e.StartWorldTime end)
        if type(start) ~= "number" then return end
        local key = name .. "@" .. string.format("%.2f", start)
        seen[key] = true

        -- Coatings and pistol boosts count hits/shots as stacks: keep the highest count.
        local stacks = G.Try(function() return e.Spec.StackCount end)
        if on and type(stacks) == "number" and stacks > 0 then
            local peak = buffs.peak[key]
            if not peak or stacks > peak then
                buffs.peak[key] = stacks
            elseif stacks < peak then
                G.Try(function() e.Spec.StackCount = peak end)
                refreshHud = true
                G.Debug(string.format("infinite buff %s: stacks %d -> %d", name, stacks, peak))
            end
        end

        local dur = G.Try(function() return e.Spec.Duration end)
        if type(dur) ~= "number" or dur <= 0 then return end
        local elapsed = t - start
        if on and dur - elapsed < BUFF_LONG / 2 then
            if not buffs.orig[key] then buffs.orig[key] = dur end
            local want = elapsed + BUFF_LONG
            G.Try(function() e.Spec.Duration = want end)
            local after = G.Try(function() return e.Spec.Duration end)
            G.Log(string.format("infinite buff %s: %.0fs left -> %s", name, dur - elapsed, tostring(after and math.floor(after - elapsed))))
        elseif not on and dur - elapsed > BUFF_LONG / 4 then
            local want = buffs.orig[key] or (elapsed + BUFF_LEFTOVER)
            if want <= elapsed then want = elapsed + 1 end
            G.Try(function() e.Spec.Duration = want end)
            G.Log(string.format("buff %s back to normal: %.0fs left", name, want - elapsed))
            buffs.orig[key] = nil
        end
    end)
    for key in pairs(buffs.peak) do
        if not seen[key] or not on then buffs.peak[key] = nil end
    end
    if not on then buffs.handles = {} end
    if refreshHud then
        -- the HUD only redraws buff counters when asked: ask it, and tell it about the stack change
        local n = G.Notifier()
        if n then G.Try(function() n:RequestTokenRefresh() end) end
        for _, h in pairs(buffs.handles) do
            if n then G.Try(function() n:OnGameplayEffectStackChanged(h.handle, h.peak, h.peak - 1) end) end
        end
    end
end

-- When the game changes a buff's stacks it tells the attribute notifier (with the effect handle).
-- We keep those handles so we can tell the HUD about our refill.
local function hookBuffStacks()
    if buffs.hooked then return end
    buffs.hooked = true
    local ok = pcall(RegisterHook, "/Script/MinotaurCore.PlayerAttributesNotifier:OnGameplayEffectStackChanged", function(_, handle, newStack, oldStack)
        if C.want.infBuffs ~= true then return end
        local h = G.Try(function() return handle:get() end)
        local id = h and G.Try(function() return h.Handle end)
        local nNew, nOld = G.Try(function() return newStack:get() end), G.Try(function() return oldStack:get() end)
        if type(id) == "number" and type(nNew) == "number" and type(nOld) == "number" and nNew < nOld then
            local prev = buffs.handles[id]
            buffs.handles[id] = { handle = { Handle = id, bPassedFiltersAndWasExecuted = true }, peak = math.max(nOld, prev and prev.peak or 0) }
            G.Debug("buff stack change seen: handle " .. id .. " " .. nOld .. " -> " .. nNew)
        end
    end)
    G.Log("infinite buffs: stack hook " .. (ok and "on" or "not available"))
end

-- Dodge Window: every dodge gives William GE_Invincibility for a short time (0.25 s in 1.0);
-- hits in that time are dodged perfectly. We make that effect last longer (the game checks the
-- duration again when it runs out) or remove it earlier for the harder settings.
local DODGE_COMPANIONS = { GE_DodgeAttackEnabled_C = true, GE_Dodge_WaitingForInput_C = true, GE_DodgeCooldown_C = true }
local dodge = { done = {}, logged = 0 }

local function applyDodgeWindow()
    local f = C.want.dodgeMult or 1
    if f == 1 then
        if next(dodge.done) then dodge.done = {} end
        return
    end
    local p = G.Player()
    local asc = p and G.Try(function() return p.AbilitySystemComponent end)
    local arr = asc and G.Try(function() return asc.ActiveGameplayEffects.GameplayEffects_Internal end)
    if not arr then return end
    local t = worldTime()
    if type(t) ~= "number" then return end
    local inv, dodgeStarts, alive = {}, {}, {}
    pcall(function()
        arr:ForEach(function(_, el)
            local e = el:get()
            local def = G.Try(function() return e.Spec.Def end)
            local name = def and G.Try(function() return def:GetClass():GetFName():ToString() end)
            local start = G.Try(function() return e.StartWorldTime end)
            if name and type(start) == "number" then
                if name == "GE_Invincibility_C" then inv[#inv + 1] = { e = e, start = start, cls = G.Try(function() return def:GetClass() end) }
                elseif DODGE_COMPANIONS[name] then dodgeStarts[#dodgeStarts + 1] = start end
            end
        end)
    end)
    for _, it in ipairs(inv) do
        local key = string.format("%.3f", it.start)
        alive[key] = true
        local fromDodge = false
        for _, ds in ipairs(dodgeStarts) do
            if math.abs(ds - it.start) < 0.1 then fromDodge = true break end
        end
        local d = dodge.done[key]
        if fromDodge and not d then
            local dur = G.Try(function() return it.e.Spec.Duration end)
            if type(dur) == "number" and dur > 0 and dur < 5 then
                d = { orig = dur, want = dur * f }
                dodge.done[key] = d
                if f > 1 then G.Try(function() it.e.Spec.Duration = d.want end) end
                dodge.logged = dodge.logged + 1
                if dodge.logged <= 3 or G.debugOn then
                    G.Log(string.format("dodge window x%s: %.2f s -> %.2f s", tostring(f), dur, d.want))
                end
            end
        end
        -- harder settings: end the invincibility early
        if d and f < 1 and t - it.start >= d.want and not d.removed then
            d.removed = true
            G.Try(function() asc:RemoveActiveGameplayEffectBySourceEffect(it.cls, nil, -1) end)
        end
    end
    for key in pairs(dodge.done) do
        if not alive[key] then dodge.done[key] = nil end
    end
end

-- Debug Logging only: log when an enemy attack checks for / grants a perfect dodge
-- (GA_MeleeAttack_Enemy:CheckInvincibilityDuringDodge / ActivatePerfectDodge).
local dodgeDebug = { done = false, nextTry = 0 }
local function hookDodgeDebug() -- unused since 1.3.1, kept for reference
    if dodgeDebug.done or now() < dodgeDebug.nextTry then return end
    dodgeDebug.nextTry = now() + 5
    local inst = FindFirstOf and FindFirstOf("GA_MeleeAttack_Enemy_C")
    local path = G.Valid(inst) and G.Try(function() return inst:GetClass():GetFullName() end)
    if not path then return end
    path = path:gsub("^%S+%s+", "")
    dodgeDebug.done = true
    for _, fn in ipairs({ "CheckInvincibilityDuringDodge", "ActivatePerfectDodge" }) do
        local ok = pcall(RegisterHook, path .. ":" .. fn, function() G.Debug("enemy attack: " .. fn) end)
        G.Debug("dodge debug hook " .. fn .. (ok and " on" or " failed"))
    end
end

-- Debug Logging only: logs every effect that appears on William (name, duration), to find out
-- which effects the game uses for things like the dodge window.
local effectWatch = { seen = {}, nextClean = 0 }
local function watchEffects()
    local p = G.Player()
    local asc = p and G.Try(function() return p.AbilitySystemComponent end)
    local arr = asc and G.Try(function() return asc.ActiveGameplayEffects.GameplayEffects_Internal end)
    if not arr then return end
    local t = worldTime() or 0
    local now_seen = {}
    pcall(function()
        arr:ForEach(function(_, el)
            local e = el:get()
            local def = G.Try(function() return e.Spec.Def end)
            local name = def and G.Try(function() return def:GetClass():GetFName():ToString() end) or "?"
            local start = G.Try(function() return e.StartWorldTime end) or 0
            local key = name .. "@" .. string.format("%.3f", start)
            now_seen[key] = true
            if not effectWatch.seen[key] then
                effectWatch.seen[key] = true
                local dur = G.Try(function() return e.Spec.Duration end)
                G.Debug(string.format("effect on: %s (duration %s, at %.2f)", name, tostring(dur), t))
            end
        end)
    end)
    for key in pairs(effectWatch.seen) do
        if not now_seen[key] then
            effectWatch.seen[key] = nil
            G.Debug(string.format("effect off: %s (at %.2f)", key:match("^[^@]+"), t))
        end
    end
end
C.WatchEffects = watchEffects

local INSTANT_ACCEL = 40

local function applyOverrides()
    local m, p = G.Movement(), G.Player()

    if C.want.speedMult ~= 1 and m and not noClipOn then
        speedOv:prop(m, "MaxWalkSpeed", C.want.speedMult)
        speedOv:prop(m, "MaxWalkSpeedCrouched", C.want.speedMult)
    elseif speedOv:active() and (C.want.speedMult == 1 or noClipOn) then
        speedOv:restore()
    end

    if C.want.jumpMult ~= 1 and m then
        -- Jump height grows with the square of the launch speed.
        jumpOv:prop(m, "JumpZVelocity", math.sqrt(C.want.jumpMult))
    elseif C.want.jumpMult == 1 and jumpOv:active() then
        jumpOv:restore()
    end

    -- One-Hit Kills and Damage Multiplier work on each hit (damage hooks in applyDefense's hookDamage),
    -- they no longer touch the saved damage multipliers (1.1.0 and older did, see repairDamage).

    -- Instant Sprint: full speed the moment you start running (no speed-up phase)
    if C.want.instantSprint and m and not noClipOn then
        accelOv:prop(m, "MaxAcceleration", INSTANT_ACCEL)
    elseif accelOv:active() and (not C.want.instantSprint or noClipOn) then
        accelOv:restore()
    end

    if (C.want.parryMult or 1) ~= 1 then hookParry() end
    applyToggleSprint()
    applyParry(C.want.alwaysParry == true)
    applyDefense()
end

local appliedGameSpeed = 1
local function applyGameSpeed()
    local v = C.want.gameSpeed or 1
    if v == appliedGameSpeed then return end
    local gs, p = G.GameplayStatics(), G.Player()
    if G.Valid(gs) and p and G.Try(function() gs:SetGlobalTimeDilation(p, v) return true end) then
        appliedGameSpeed = v
    end
end

-- ---------------------------------------------------------------------------
-- One-shot actions (menu callbacks run on the game thread, ModMenu polls there)
-- ---------------------------------------------------------------------------

local function needPlayer()
    if G.Player() then return true end
    C.status = "Load a save first"
    return false
end

-- ---------------------------------------------------------------------------
-- Teleport: save up to 5 positions and jump back to them (kept in teleports.txt, per map)
-- ---------------------------------------------------------------------------

C.teleports = {}

local function mapName()
    local p = G.Player()
    return p and G.Try(function() return p:GetOuter():GetOuter():GetFName():ToString() end) or "?"
end

local function slotName(slot)
    local t = C.teleports[tostring(slot)]
    local n = type(t) == "table" and t.name
    if type(n) == "string" and n:match("%S") then return n end
    return "Position " .. slot
end
C.PositionName = slotName

-- Rename a slot (also before anything is saved in it).
function C.RenamePosition(slot, name)
    name = (type(name) == "string") and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local key = tostring(slot)
    local t = C.teleports[key]
    if type(t) ~= "table" then t = {} C.teleports[key] = t end
    if t.name == name or (t.name == nil and name == "") then return end
    t.name = name ~= "" and name or nil
    G.Log("position " .. slot .. " renamed to '" .. name .. "'")
    if C.onTeleportsChange then pcall(C.onTeleportsChange, C.teleports) end
end

function C.SavePosition(slot)
    if not needPlayer() then return end
    local p, pc = G.Player(), G.Controller()
    local loc = G.Try(function() return p:K2_GetActorLocation() end)
    if not loc then
        C.status = "Could not read your position"
        return
    end
    local yaw = pc and G.Try(function() return pc:GetControlRotation().Yaw end) or 0
    local old = C.teleports[tostring(slot)]
    local name = type(old) == "table" and old.name or nil
    C.teleports[tostring(slot)] = { map = mapName(), x = loc.X, y = loc.Y, z = loc.Z, yaw = yaw, name = name }
    if C.onTeleportsChange then pcall(C.onTeleportsChange, C.teleports) end
    G.Log(string.format("position %d (%s) saved: %s %.0f %.0f %.0f", slot, slotName(slot), mapName(), loc.X, loc.Y, loc.Z))
    C.status = slotName(slot) .. " saved"
end

function C.TeleportTo(slot)
    if not needPlayer() then return end
    local t = C.teleports[tostring(slot)]
    if type(t) ~= "table" or type(t.x) ~= "number" then
        C.status = slotName(slot) .. " is empty, save it first"
        return
    end
    if t.map ~= mapName() then
        C.status = slotName(slot) .. " was saved in another area"
        return
    end
    local p, pc, m = G.Player(), G.Controller(), G.Movement()
    if m then G.Try(function() m.Velocity = { X = 0, Y = 0, Z = 0 } end) end
    local ok = G.Try(function() p:K2_SetActorLocation({ X = t.x, Y = t.y, Z = t.z }, false, {}, true) return true end)
    if pc and type(t.yaw) == "number" then
        G.Try(function() pc:SetControlRotation({ Pitch = 0, Yaw = t.yaw, Roll = 0 }) end)
    end
    safeLandingUntil = now() + 3
    G.Log("teleport to position " .. slot .. " (" .. slotName(slot) .. ")" .. (ok and "" or " FAILED"))
    C.status = ok and ("Teleported to " .. slotName(slot)) or "Teleport failed"
end


function C.AddCatalysts(amount)
    local cu = G.CombatUtils()
    if not needPlayer() or not G.Valid(cu) then return end
    if G.Try(function() cu:AddExperiencePointsToPlayer(amount) return true end) then
        G.Log("added " .. amount .. " catalysts")
        C.status = "Added " .. amount .. " catalysts"
    else
        G.Log("AddExperiencePointsToPlayer failed")
        C.status = "Could not add catalysts"
    end
end

-- Refill the way resting at a lantern does: the game's own restore effects, so the HUD and
-- everything else follows. Ammo has no lantern effect, it is filled directly.
local GE = "/Game/Minotaur/Gameplay/GAS/GameplayEffects/"
local REFILL_EFFECTS = {
    GE .. "GE_FullHeal.GE_FullHeal_C",
    GE .. "GE_FullStamina.GE_FullStamina_C",
    GE .. "GE_HealingFlasksRestore.GE_HealingFlasksRestore_C",
    GE .. "GE_RestoreNephtoglobinAtLantern.GE_RestoreNephtoglobinAtLantern_C",
}

-- What refill is about, for the log: attributes and the flask/syringe items.
local function refillSnapshot()
    local parts = {}
    local function a(set, name)
        local st = G.Set(set)
        local v = st and G.GetAttr(st, name)
        parts[#parts + 1] = name .. "=" .. (type(v) == "number" and string.format("%.0f", v) or "?")
    end
    a("Health", "Health"); a("Health", "MaxHealth")
    a("Stamina", "Stamina"); a("Stamina", "MaxStamina")
    a("Blood", "BloodPoints"); a("Blood", "MaxBloodPoints")
    a("Flasks", "HealingFlasks"); a("Flasks", "HealingFlasksMax")
    a("Ranged", "PistolAmmo"); a("Ranged", "PistolAmmoInClip")
    local save = G.Save()
    for _, item in ipairs({ "Items.Consumable.HealingFlask.Regular", "Items.Consumable.NephtoglobinFlask.Small", "Items.Consumable.Grenade.Regular" }) do
        local n = save and itemCount(save, item)
        parts[#parts + 1] = item:match("[^.]+%.[^.]+$") .. "=" .. tostring(n)
    end
    return table.concat(parts, ", ")
end

local refillCheckAt = nil

function C.RefillAll()
    if not needPlayer() then return end
    G.Log("refill before: " .. refillSnapshot())
    local applied = 0
    for _, path in ipairs(REFILL_EFFECTS) do
        if G.ApplyEffect(path) then applied = applied + 1 end
    end
    -- and fill the attributes directly as well, in case an effect does not apply in this state
    godMode(); infStamina(); infBlood(); infFlasks(); infAmmo()
    local items = refillConsumables()
    G.Log("refill: " .. applied .. "/" .. #REFILL_EFFECTS .. " restore effects applied, values filled, " .. items .. " consumables refilled")
    refillCheckAt = now() + 0.5
    C.status = "Health, stamina, nephtoglobin, flasks, ammo and items refilled"
end

local function refillCheck()
    if refillCheckAt and now() >= refillCheckAt then
        refillCheckAt = nil
        G.Log("refill after:  " .. refillSnapshot())
    end
end

-- +amount of every consumable (grenades, syringes, potions, coatings, ...), catalysts excluded
-- (they have their own buttons).
function C.AddConsumables(amount)
    if not needPlayer() then return end
    local tags, inv = consumableTags(), G.Inventory()
    if not tags or not inv then
        C.status = "Item database not found"
        return
    end
    local count = 0
    for _, name in ipairs(tags) do
        if not name:find("Catalyst", 1, true) then
            local ok = G.Try(function() inv:AddInventoryItem({ TagName = FName(name) }, amount) return true end)
            G.Debug("consumable " .. name .. (ok and (" +" .. amount) or " failed"))
            if ok then count = count + 1 end
        end
    end
    cons.last = {} -- new baseline for Infinite Consumables
    G.Log("added " .. amount .. " of " .. count .. " consumables")
    C.status = "Added " .. amount .. " of " .. count .. " consumables"
end

-- ---------------------------------------------------------------------------
-- Give Item: pick one item from the game's item database and choose how many.
-- Story items (NarrativeItemsMap) are left out on purpose: they can break quests.
-- ---------------------------------------------------------------------------

local ITEM_CATEGORIES = {
    { key = "Consumables", map = "ConsumableItemsMap" },
    { key = "Materials", map = "MaterialItemsMap" },
    { key = "Instant", map = "InstantItemsMap" },
}
C.ITEM_CATEGORIES = ITEM_CATEGORIES

local catalog = nil
local loggedTextKeys = false

-- "Items.Consumable.Grenade.Oil" -> "Grenade Oil"
local GENERIC_TAG_PARTS = { Items = true, Item = true, Inventory = true, Consumable = true, Consumables = true,
    Material = true, Materials = true, Instant = true, Upgrade = true, Upgrades = true }
local function prettyTag(tag)
    local parts = {}
    for part in tag:gmatch("[^%.]+") do
        if not GENERIC_TAG_PARTS[part] then parts[#parts + 1] = part end
    end
    local name = #parts >= 2 and (parts[#parts - 1] .. " " .. parts[#parts]) or (parts[1] or tag)
    name = name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    return name
end

local function itemLabel(tag)
    for _, list in pairs(catalog or {}) do
        for _, e in ipairs(list) do
            if e.value == tag then return e.label end
        end
    end
    return prettyTag(tag)
end

-- The item's in-game name from its UI data, if the game has one.
local function itemName(props, tag)
    local name, firstKeys = nil, {}
    G.Try(function()
        props.UIData.TextStats:ForEach(function(k, v)
            local key = G.Try(function() return k:get().TagName:ToString() end) or "?"
            local text = G.Try(function() return v:get():ToString() end)
            firstKeys[#firstKeys + 1] = key .. "=" .. tostring(text)
            if not name and text and text ~= "" and (key:find("Name") or key:find("Title")) then name = text end
        end)
    end)
    if not loggedTextKeys and #firstKeys > 0 then
        loggedTextKeys = true
        G.Debug("item text stats for " .. tag .. ": " .. table.concat(firstKeys, ", "))
    end
    return name
end

local function addEntry(list, seen, tag, props)
    if not tag or tag == "None" or seen[tag] then return end
    seen[tag] = true
    local name = props and itemName(props, tag)
    list[#list + 1] = { label = name or prettyTag(tag), value = tag }
end

-- { Consumables = { {label, value}, ... }, Materials = {...}, Instant = {...} } or nil before a save is loaded
function C.ItemCatalog()
    if catalog then return catalog end
    local inv = G.Inventory()
    local db = inv and G.Try(function() return inv.InventoryDatabaseAsset end)
    if not G.Valid(db) then return nil end
    local result, total = {}, 0
    for _, cat in ipairs(ITEM_CATEGORIES) do
        local list, seen = {}, {}
        G.Try(function()
            db[cat.map]:ForEach(function(catKey, item)
                local before = #list
                G.Try(function()
                    item:get().ItemMap:ForEach(function(key, props)
                        addEntry(list, seen, G.Try(function() return key:get().TagName:ToString() end), G.Try(function() return props:get() end))
                    end)
                end)
                if #list == before then
                    addEntry(list, seen, G.Try(function() return catKey:get().TagName:ToString() end), nil)
                end
            end)
        end)
        if cat.key == "Materials" then
            -- the upgrade materials the developers' cheat manager lists, in case the database misses some
            local cm = G.CheatManager()
            G.Try(function()
                cm.UpgradeMaterials.GameplayTags:ForEach(function(_, el)
                    addEntry(list, seen, G.Try(function() return el:get().TagName:ToString() end), nil)
                end)
            end)
        end
        table.sort(list, function(x, y) return x.label:lower() < y.label:lower() end)
        result[cat.key] = list
        total = total + #list
        G.Log("give item: " .. #list .. " " .. cat.key:lower())
    end
    if total == 0 then return nil end
    catalog = result
    return catalog
end

function C.GiveItem(tag, amount)
    if not needPlayer() then return end
    amount = math.floor(tonumber(amount) or 0)
    if not tag or tag == "" then
        C.status = "Pick an item first"
        return
    end
    if amount < 1 then
        C.status = "Amount must be at least 1"
        return
    end
    local inv, save = G.Inventory(), G.Save()
    if not inv then
        C.status = "Inventory not found"
        return
    end
    local before = save and itemCount(save, tag)
    local ok = G.Try(function() inv:AddInventoryItem({ TagName = FName(tag) }, amount) return true end)
    local after = save and itemCount(save, tag)
    cons.last = {} -- new baseline for Infinite Consumables
    cons.peak[tag] = nil
    G.Log(string.format("give item %s x%d: %s (count %s -> %s)", tag, amount, ok and "ok" or "failed", tostring(before), tostring(after)))
    C.status = ok and ("Added " .. amount .. "x " .. itemLabel(tag)) or ("Could not add " .. itemLabel(tag))
end

-- The weapons from the developers' cheat manager that are really in the game. "WeaponGrenade"
-- (Crystal Grenade) is an unfinished leftover: it does nothing and takes the Claymore's place on the
-- weapon wheel, so it is left out (1.3.1) and removed from saves that got it from older versions.
local WEAPON_FIELDS = { "PlayerSaber", "WeaponPistol", "WeaponFlamethrower", "WeaponRifle",
    "WeaponClaymore", "WeaponBlunderbuss", "WeaponShield", "WeaponRapier", "WeaponStasis" }
local BROKEN_WEAPON_FIELDS = { "WeaponGrenade" }

-- Removes the broken leftover weapons from the player's weapon lists. Only rebuilds a list after a
-- test append proved that this UE4SS version can grow arrays, so a list is never left emptied.
local function removeBrokenWeapons()
    local p, cm = G.Player(), G.CheatManager()
    if not G.Valid(p) or not cm then return false end
    local bad = {}
    for _, field in ipairs(BROKEN_WEAPON_FIELDS) do
        local w = G.Try(function() return cm[field] end)
        if G.Valid(w) then bad[G.Addr(w)] = field end
    end
    if next(bad) == nil then return true end
    local removed = 0
    for _, listName in ipairs({ "RangedWeapons", "MeleeWeapons", "TwoHandedWeapons" }) do
        G.Safe("clean " .. listName, function()
            local arr = p[listName]
            local keep, hit = {}, false
            arr:ForEach(function(_, el)
                local w = el:get()
                if G.Valid(w) and bad[G.Addr(w)] then hit = true else keep[#keep + 1] = w end
            end)
            if not hit then return end
            local n = arr:GetArrayNum()
            local grew = G.Try(function() arr[n + 1] = keep[1] or arr[1] return arr:GetArrayNum() == n + 1 end)
            if not grew then
                G.Log("could not remove the Crystal Grenade from " .. listName .. " (array cannot grow)")
                return
            end
            arr:Empty()
            for i, w in ipairs(keep) do arr[i] = w end
            G.Log(listName .. ": removed the Crystal Grenade, " .. #keep .. " weapons kept (now " .. arr:GetArrayNum() .. ")")
            removed = removed + 1
        end)
    end
    -- never leave the broken weapon in the hand
    local cur = G.Try(function() return p.CurrentRangedWeapon end)
    if G.Valid(cur) and bad[G.Addr(cur)] then
        local pistol = G.Try(function() return cm.WeaponPistol end)
        if G.Valid(pistol) then
            G.Try(function() p:EquipRangedWeapon(pistol, false, true, true) return true end)
            G.Log("switched from the Crystal Grenade to the pistol")
        end
    end
    if removed > 0 then
        local n = G.Notifier()
        if n then G.Try(function() n:RequestWeaponRefresh() return true end) end
        C.status = "Removed the broken Crystal Grenade from your weapon wheel"
    end
    return true
end
C.RemoveBrokenWeapons = removeBrokenWeapons

function C.UnlockWeapons()
    if not needPlayer() then return end
    local p, cm = G.Player(), G.CheatManager()
    if not cm then
        C.status = "Cheat manager not found"
        return
    end
    local count = 0
    for _, field in ipairs(WEAPON_FIELDS) do
        local w = G.Try(function() return cm[field] end)
        if G.Valid(w) then
            local ok = G.Try(function() p:AcquireWeapon(w, true) return true end)
            G.Log("weapon " .. field .. (ok and " acquired" or " failed"))
            if ok then count = count + 1 end
        else
            G.Log("weapon " .. field .. ": not set")
        end
    end
    C.status = "Unlocked " .. count .. " weapons"
end

-- The upgrade materials the developers' cheat manager lists, 99 of each.
function C.AddMaterials(amount)
    if not needPlayer() then return end
    local cm, inv = G.CheatManager(), G.Inventory()
    if not cm or not inv then
        C.status = "Cheat manager / inventory not found"
        return
    end
    local tags = {}
    G.Try(function()
        cm.UpgradeMaterials.GameplayTags:ForEach(function(_, el)
            local name = G.Try(function() return el:get().TagName:ToString() end)
            if name and name ~= "None" then tags[#tags + 1] = name end
        end)
    end)
    local count = 0
    for _, name in ipairs(tags) do
        local ok = G.Try(function() inv:AddInventoryItem({ TagName = FName(name) }, amount) return true end)
        G.Log("material " .. name .. (ok and (" +" .. amount) or " failed"))
        if ok then count = count + 1 end
    end
    C.status = count > 0 and ("Added " .. amount .. " of " .. count .. " materials") or "No materials found"
end

function C.Actions(names, label)
    if not needPlayer() then return end
    local done = 0
    for _, n in ipairs(names) do
        if C.RunAction(n) then done = done + 1 end
    end
    C.status = label .. ": " .. done .. "/" .. #names .. " done"
end

-- Kill every enemy within 60 m.
function C.KillNearby()
    if not needPlayer() then return end
    local p = G.Player()
    local here = G.Try(function() return p:K2_GetActorLocation() end)
    if not here then return end
    local killed = 0
    for _, e in ipairs(FindAllOf("EnemyCharacter") or {}) do
        if G.Valid(e) then
            local pos = G.Try(function() return e:K2_GetActorLocation() end)
            local hp = G.Try(function() return e.HealthAttributes.Health.CurrentValue end)
            if pos and type(hp) == "number" and hp > 0 then
                local dx, dy, dz = pos.X - here.X, pos.Y - here.Y, pos.Z - here.Z
                if dx * dx + dy * dy + dz * dz < 6000 * 6000 then
                    if G.Try(function() e:KillCharacter(p, { GameplayTags = {}, ParentTags = {} }) return true end) then
                        killed = killed + 1
                    end
                end
            end
        end
    end
    G.Log("killed " .. killed .. " enemies nearby")
    C.status = "Killed " .. killed .. " enemies nearby"
end

-- ---------------------------------------------------------------------------
-- Main tick
-- ---------------------------------------------------------------------------

local function forgetPlayerState()
    G.ResetCache()
    speedOv:forget(); jumpOv:forget(); accelOv:forget(); sprint.abilities = {}; sprint.nextFind = 0; buffs.orig = {}; buffs.peak = {}; buffs.handles = {}; buffs.logged = false; dmgOv:forget(); parryOv:forget(); flyOv:forget(); takenOv:forget(); maxHpOv:forget()
    appliedHpMult = 1
    lastHp = nil
    savedChecked = false
    weaponsChecked = false
    hpBar.forget()
    appliedGameSpeed = 1
    markHandled = {}
    resetConsumables()
    invisibleOn = false
    blinded = {}
    noClipOn = false
end

function C.OnMapChange(reason)
    G.Debug("map change / restart: " .. tostring(reason))
    forgetPlayerState()
    readyAt = now() + 3
end

local cmAddr = nil

function C.Tick()
    if now() < readyAt then return end
    local p = G.Player()
    if not p then
        C.status = "Waiting for a loaded save..."
        lastPlayer = nil
        return
    end
    local addr = G.Addr(p)
    if addr ~= lastPlayer then
        lastPlayer = addr
        G.Log("player found")
        forgetPlayerState()
        readyAt = now() + 2
        C.status = "Ready"
        return
    end

    local cm = G.CheatManager()
    if cm and G.Addr(cm) ~= cmAddr then
        cmAddr = G.Addr(cm)
        G.Log("cheat manager found")
        if G.debugOn then dumpCheatActions(cm) end
    end

    if not savedChecked then
        savedChecked = true
        G.Safe("check saved values", checkSavedValues)
    end
    if not weaponsChecked and cm then
        weaponsChecked = G.Try(removeBrokenWeapons) == true
    end

    syncIgnoreCosts()

    local w = C.want
    if w.godMode then godMode() end
    if w.infStamina and not (w.staminaOutOfCombat and inCombat()) then infStamina() end
    if w.infBlood then infBlood() end
    if w.infFlasks then infFlasks() end
    if w.infAmmo then infAmmo() end
    -- God Mode covers falls too: fall damage does not go through the damage functions we hook.
    if w.noFall or (w.fallDamage or 1) <= 0 or w.godMode or now() < safeLandingUntil then noFall() end
    G.Safe("fall damage", applyFallCurve)
    G.Safe("health regeneration", healthRegen)
    if w.noCooldown then noCooldown() end
    if w.keepCatalysts then keepCatalysts() end
    if w.infConsumables then infConsumables() else cons.last = {} end
    trackPeaks()

    if w.invisible ~= invisibleOn then setInvisible(w.invisible) end
    if invisibleOn then blindEnemies() end
    if w.noClip ~= noClipOn then setNoClip(w.noClip) end
    if noClipOn then noClipTick() end

    applyOverrides()
    G.Safe("health bar length", fixHealthBar) -- after Max Health was applied this tick
    applyGameSpeed()
    -- (the dodge debug hooks are off since 1.3.1: hooking Blueprint functions that are not loaded yet
    -- failed and could leave the Lua state broken)
    if G.debugOn then G.Safe("watch effects", watchEffects) end
    G.Safe("dodge window", applyDodgeWindow)
    if w.infBuffs then hookBuffStacks() end
    G.Safe("infinite buffs", infBuffs)
    refillCheck()
    flushLedger()
end

-- ---------------------------------------------------------------------------
-- Bug report: one text file with everything we need to help a user.
-- ---------------------------------------------------------------------------

local function attrLine(setName, names)
    local s = G.Set(setName)
    if not s then return setName .. ": not found" end
    local parts = {}
    for _, n in ipairs(names) do
        parts[#parts + 1] = n .. "=" .. tostring(G.GetAttr(s, n))
    end
    return setName .. ": " .. table.concat(parts, ", ")
end

function C.WriteBugReport()
    local L = {}
    local function add(s) L[#L + 1] = s end
    add("Valor Mortis Cheat Menu v" .. G.VERSION .. " - bug report")
    add("Written: " .. os.date("%Y-%m-%d %H:%M:%S"))
    add("Please attach this file and ValorCheatMenu.log to your bug report on Nexus.")
    add("")
    add("== Settings ==")
    local keys = {}
    for k in pairs(C.want) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do add(k .. " = " .. tostring(C.want[k])) end
    add("")
    add("== Game state ==")
    local p = G.Player()
    add("status: " .. tostring(C.status))
    add("player: " .. (p and "found" or "NOT found"))
    add("cheat manager: " .. (G.CheatManager() and "found" or "NOT found"))
    add("inventory subsystem: " .. (G.Inventory() and "found" or "NOT found"))
    add("noclip active: " .. tostring(noClipOn) .. ", invisible active: " .. tostring(invisibleOn))
    if p then
        add(attrLine("Health", { "Health", "MaxHealth", "DamageMultiplier", "MeleeResistance", "RangedResistance" }))
        add(attrLine("Stamina", { "Stamina", "MaxStamina" }))
        add(attrLine("Blood", { "BloodPoints", "MaxBloodPoints" }))
        add(attrLine("Flasks", { "HealingFlasks", "HealingFlasksMax" }))
        add(attrLine("Ranged", { "PistolAmmo", "PistolAmmoInClip", "RangedDamageMultiplier" }))
        add(attrLine("Melee", { "MeleeDamageMultiplier", "ParryWindowAdjustment" }))
        add(attrLine("Exp", { "ExpPoints" }))
        local m = G.Movement()
        if m then
            add("movement: mode=" .. tostring(G.Try(function() return m.MovementMode end))
                .. ", MaxWalkSpeed=" .. tostring(G.Try(function() return m.MaxWalkSpeed end))
                .. ", JumpZVelocity=" .. tostring(G.Try(function() return m.JumpZVelocity end)))
        end
        local weapon = G.Try(function() return p.CurrentMeleeWeapon end)
        if G.Valid(weapon) then
            add("melee weapon: " .. tostring(G.Try(function() return weapon:GetFName():ToString() end))
                .. ", PerfectParryCooldown=" .. tostring(G.Try(function() return weapon.PerfectParryCooldown end))
                .. ", PerfectParrySpamReduction=" .. tostring(G.Try(function() return weapon.PerfectParrySpamReduction end)))
        end
    end
    add("")
    add("== Engine cheats ==")
    for _, line in ipairs(C.DevStates()) do add(line) end
    add("")
    add("== Last log lines ==")
    for _, line in ipairs(G.RecentLines()) do add(line) end

    local ok = pcall(function()
        local f = assert(io.open(G.REPORT_FILE, "w"))
        f:write(table.concat(L, "\n"), "\n")
        f:close()
    end)
    if ok then
        G.Log("bug report written: " .. G.REPORT_FILE)
        C.status = "Saved ValorCheatMenu-BugReport.txt in the mod folder"
    else
        G.Log("could not write bug report to " .. G.REPORT_FILE)
        C.status = "Could not write the bug report"
    end
end

-- Everything back to vanilla.
function C.ResetAll()
    for k, v in pairs(C.want) do
        if type(v) == "boolean" then C.want[k] = false end
        if type(v) == "number" then C.want[k] = 1 end
    end
    C.want.regenRate = 0
    C.want.regenDelay = 2
end

return C
