# Valor Mortis

Overhand for **Valor Mortis** (Unreal Engine 5.7): the cheats in the menu, then what we know about the game's internals.

Install: `.\tools\install.ps1 -Game valormortis` (see the [README](../../README.md#quick-start)).

## Cheats

| Tab | Cheats |
|---|---|
| **Survival** | God Mode · Infinite Stamina (optionally only out of combat) · Stamina Cost 100–25 % (attacks, dodges, blocks) · Infinite Nephtoglobin · Fall Damage 100–0 % · Damage Taken 100–10 % (through the game's own resistances) · Max Health up to 5x (the health bar keeps its length) · Health Regeneration 1–50 HP/s with a delay after hits, a heal-up-to limit and an out-of-combat option |
| **Movement** | NoClip (Space or A up, Ctrl, C or B down) · Movement Speed up to 5x · Jump Height up to 10x · Game Speed 0.25–2x · Toggle Sprint for keyboard · Instant Sprint · **Teleport**: 5 saved positions per area |
| **Combat** | One-Hit Kills · Damage Multiplier up to 10x · Every Block Is A Perfect Parry (two-handed weapons too) · Claymore Can Parry · Parry Window 0.5–6x · Dodge Window 0.5–4x · Kill All Enemies Nearby (60 m) |
| **Items** | Infinite Ammo (optionally still reloading) · Infinite Healing Flasks · Infinite Consumables · Infinite Buffs (potions, coatings, pistol boosts) · No Item Cooldowns · Keep Catalysts On Death (also deaths without a deathmark) · No Ability Costs · Free Respec · Refill Everything |
| **Give** | +1,000 / +10,000 Catalysts · +99 of every upgrade material · +5 of every consumable · Unlock all weapons / abilities / gems · **Give Item**: any consumable, material, instant or quest item from a list, 1–999 at a time (the count is checked afterwards) |
| **Quests** | Your active quests and what each one's current step asks for (read only) · Refresh the list · Write quest report (`Overhand-Quests.txt`) |
| **Misc** | Turn everything off · Debug logging · Write bug report · Find controller button icons |

The menu's theme (Cinzel and Barlow Semi Condensed, which ship with the mod) is this game's.

---

# Internals

What we know about Valor Mortis' internals, and how Overhand uses each part. Marked **confirmed in game** where an in-game test or log showed it working (as of 2026-10-17); the rest comes from reading the game through code that runs (it may still need a check after a game update).

The game's code module is **MinotaurCore** (`/Script/MinotaurCore.*`); its assets live under `/Game/Minotaur/`.

## Setup

| | |
|---|---|
| Engine | Unreal Engine 5.7 |
| UE4SS | experimental-latest required (stable 3.0.1 predates UE 5.6/5.7). Tested: `UE4SS_v3.0.1-1176-g1ba38db4` |
| Crash Fix | `bForceGUObjectArrayForIteration = true` (community recommendation) |
| Game Pass path (the tested build) | `C:\XboxGames\Valor Mortis\Content\ValorMortis\Binaries\Win64\` (`Win64`, not `WinGDK`); exe `ValorMortisMSG-Win64-Shipping.exe` |
| UE4SS proxy | `dwmapi.dll` works on the Game Pass build (**confirmed in game**) |

## Player

| What | Where |
|---|---|
| Controller | `BP_PlayerController_C` (its `Pawn`, `CheatManager`) |
| Character | `BP_PlayerCharacter_C`. A loading-screen character exists before it; check the class. |
| Components | `CharacterMovement`, `AttributesNotifierComponent`, `AbilitySystemComponent` (properties on the character) |
| World | `player:GetOuter():GetOuter()`; map name from the world's FName |
| Movement modes | `CharacterMovement.MovementMode`: 3 falling, 5 flying |

## Attributes (GAS)

Valor Mortis uses the Gameplay Ability System. `BaseValue` is saved with the game; `CurrentValue` is base plus modifiers.

| Set (property on `AttributesNotifierComponent`) | Attributes we use |
|---|---|
| `HealthAttributes` | `Health`, `MaxHealth`, `MeleeResistance`, `RangedResistance`, `ExplosiveResistance`, `MagicResistance` (all four readable, **confirmed in game**), `DamageMultiplier` (does not change damage taken, per the Cheat Menu's tests) |
| `StaminaAttributes` | `Stamina`, `MaxStamina`, `StaminaMeleeCostMultiplier` / `StaminaDodgeCostMultiplier` / `StaminaBlockCostMultiplier` (base values, saved; what the game's upgrades change; used by Stamina Cost) |
| `BloodAttributes` | `BloodPoints`, `MaxBloodPoints` (Nephtoglobin) |
| `FlasksAttributes` | `HealingFlasks`, `HealingFlasksMax` |
| `RangedAttributes` | `PistolAmmo` / `BlunderbussAmmo` / `RifleAmmo`, `...AmmoInClip`, `Max...`, `RangedDamageMultiplier` |
| `ExpAttributes` | `ExpPoints` (catalysts) |

| Set found by class (owned by the character) | |
|---|---|
| `MeleeAttributeSet` | `MeleeDamageMultiplier`, `ParryWindowAdjustment` (what the "Forgiving Parry" gem raises; the game drops it to -10 while a two-handed weapon is equipped) |
| `MovementAttributeSet` | (not used) |

- **Resistances:** a resistance `r` lets `1 - r` of the damage through. Raising `CurrentValue` reduces damage (Damage Taken, **confirmed in game**: 50 % halves hits).
- **GASCompanion:** `/Script/GASCompanion.Default__GSCBlueprintFunctionLibrary:GetCompanionCoreComponent(player)` returns a core whose `SetAttributeValue(attribute, value)` changes an attribute the normal way, and the HUD follows. The Health `FGameplayAttribute` comes from `GE_AddHealth`'s modifiers (`/Game/Minotaur/Gameplay/GAS/GameplayEffects/GE_AddHealth.Default__GE_AddHealth_C`). Used by Health Regeneration (**confirmed in game**: "healing through the game").

## Damage and combat (`/Script/MinotaurCore.MTCombatUtils`)

| Function | Parameters after the context object | Used for |
|---|---|---|
| `DealMeleeDamage`, `DealRangedDamage`, `DealExplosiveDamage`, `DealEnvironmentalDamage`, `DealCriticalDamage` | 1 damage, 2 target, 4 attacker | God Mode (incoming × 0), One-Hit Kills / Damage Multiplier (outgoing) |
| `DealIgniteDamage`, `DealInfectionDamage`, `DealCrystallizationDamage` | 1 damage, 2 target, 3 attacker | same |
| `DealDamage` | 2 damage, 3 target, 4 attacker | same |
| `DealDamageWithEffect` | 3 damage, 4 target, 5 attacker | same |
| `DealCombinedDamage` | damage 2, 3, 4, 5, 7, 8, 10; 12 target, 13 attacker | same |
| `CheckBlockMelee`, `CheckBlockMeleeForProperties`, `CheckBlockProjectile` | attack data (`PerfectParryOpeningTime`), blocker | Parry Window |
| `Overheal(amount, player)` | | God Mode, Refill (heals through a GameplayEffect) |
| `AddExperiencePointsToPlayer(amount)` | | +Catalysts |

- Projectiles and grenades carry the player as their `Instigator`.
- Fall damage is not dealt through these functions: it comes from the character's `FallDamageCurve` (height → damage, a float curve asset). `SetLastApexHeightToCurrentPosition()` while falling cancels it.
- Enemies: `EnemyCharacter` with `HealthAttributes`; `KillCharacter(killer, tagContainer)`.
- In combat: the world's `EnemyInfoSubsystem.EnemiesInCombatState` (match the subsystem's outer to the player's world). `CombatSubsystem:IsInCombat()` also exists.
- Dodge: each dodge applies `GE_Invincibility_C` (0.25 s), alongside `GE_DodgeAttackEnabled_C` / `GE_Dodge_WaitingForInput_C` / `GE_DodgeCooldown_C`. The game re-checks `Spec.Duration` when an effect expires, so a longer duration keeps it.
- Weapon parry fields: `CurrentMeleeWeapon.PerfectParryCooldown`, `PerfectParrySpamReduction`.

## Effects

- Active effects: `AbilitySystemComponent.ActiveGameplayEffects.GameplayEffects_Internal` (`Spec.Def`, `Spec.Duration`, `Spec.StackCount`, `StartWorldTime`).
- Buffs: `GE_Bubble_C`, `GE_ProtectionPotion_C`, `GE_StaminaPotion_C`, `GE_Rage_C`, coatings `GE_FlamingCoating_C` / `GE_SharpCoating_C` / `GE_StasisCoating_C`, pistol boosts `GE_FlamingBoost_C` / `GE_PreciseBoost_C` / `GE_StasisBoost_C` / `GE_ConcussingBoost_C`. Coatings and boosts count hits as stacks.
- Restore (like resting at a lantern): `GE_FullHeal_C`, `GE_FullStamina_C`, `GE_HealingFlasksRestore_C`, `GE_RestoreNephtoglobinAtLantern_C` under `/Game/Minotaur/Gameplay/GAS/GameplayEffects/`.
- `PlayerAttributesNotifier:OnGameplayEffectStackChanged(handle, new, old)`: hooked to learn effect handles; also tells the HUD about stack changes.

## Items and inventory

- `InventorySubsystem.InventoryDatabaseAsset`: maps `ConsumableItemsMap`, `MaterialItemsMap`, `InstantItemsMap`, `NarrativeItemsMap` (quest items; Give Item's Quest Items category, with the tags in `QuestAction_GrantItems` / `QuestAction_RemoveItems` `ItemTags`). Each maps a category tag to an `ItemMap` of real items. 34 consumables, 14 materials, 7 instant items (**confirmed in game**). In-game names in `UIData.TextStats`.
- `SaveSubsystem:TryGetInventoryItemCount(tag)`, `InventorySubsystem:AddInventoryItem(tag, amount)`, `InventorySubsystem:TrySetAllConsumableInventoryItemsCooldown(player, 0)`.
- "Use item" functions are called from C++, so hooking them does not work; Infinite Consumables polls counts and gives back what was used.
- Give Item: items past what William can carry go to his storage (**confirmed in game**: a coating at 3 stayed at 3, the rest could be picked up from storage). `TryGetInventoryItemCount` counts what he carries; Overhand reads it again a second after giving and says where the items went.
- Death: the character's `DeathmarkRef:ForcePickup()` returns the dropped catalysts; `bRespawning` while respawning. Some deaths (poison, some bosses) leave no deathmark and still take the catalysts; `MTCombatUtils:AddExperiencePointsToPlayer(n)` gives catalysts.

## Weapons, progression and quests

From Valor Mortis Cheat Menu 1.4.0's findings (BryanHudson), reimplemented; **not yet confirmed in game** by us.

- `MeleeWeaponPrimaryDataAsset.BlockAllowedType`: 0 = block and parry, 1 = block only (the Claymore and other two-handed weapons). A game asset, not saved. Overhand looks the assets up when William's melee weapon changes, not on a timer.
- The equipped melee weapon (`CurrentMeleeWeapon`) has `PerfectParryCooldown` and `PerfectParrySpamReduction`.
- `CharacterProgressionDatabase.RespecCosts`: a map level -> catalyst cost for resetting upgrades at a lantern. A game asset, not saved (Free Respec writes 0, restores the costs when off).
- `CharacterMovement.MovementMode`: 1 walking, 2 nav walking, 3 falling, 5 flying. Instant Sprint applies only on the ground (in the air the huge acceleration steered away jump and swing momentum).
- `QuestSubsystem`: `GameQuests` (tag -> quest), `ActiveQuests`; a quest's `QuestTitle`, `PersistentState` (`bQuestActive`, `bQuestCompleted`, `CurrentQuestStepIndex`), `CurrentQuestStep.StepDescription`. `EndQuest` / `ResetQuest` from outside crash the quest system, so the Quests tab only reads.

## Developer cheat manager (`BP_MTCheatManager`)

- Its C++ cheat functions (`GodMode`, `NoClip`, ...) are empty in the release build, and its `Cheat.*` console variables don't exist.
- Its Blueprint cheat actions (`CheatActions`, by `ActionName`) work: "Unlock Grappling", "Unlock Stasis", "Unlock Neptho Interactions", "Unlock Leveling Up", "Unlock all gems".
- `IgnoreCostsToggle` works (state in the `AbilitySystem.IgnoreCosts` CVar).
- Weapon fields: `PlayerSaber`, `WeaponPistol`, `WeaponFlamethrower`, `WeaponRifle`, `WeaponClaymore`, `WeaponBlunderbuss`, `WeaponShield`, `WeaponRapier`, `WeaponStasis` (`player:AcquireWeapon(weapon, true)`). **`WeaponGrenade` (Crystal Grenade) is an unfinished leftover**: it does nothing and takes the Claymore's wheel slot, so Unlock All Weapons leaves it out.
- `UpgradeMaterials`: a tag container of the upgrade materials.

## HUD and menus

- HUD: `WBP_PlayerVitals_C` (owner via `GetOwningPlayerPawn`; the previous one stays valid for a while after a load). `PlayerHealthVitalsBar:Update(fraction)` redraws the bar; its slot width is 2.5 px per point of max health (250 px for 100), so raised max health runs it off screen.
- `AttributesNotifierComponent:RequestWeaponRefresh()` / `RequestTokenRefresh()` redraw ammo and counters after direct writes.
- Game menus: `WBP_PauseMenu_C` (**confirmed in game**: blocks our menu), `WBP_PanelSettings_C`, `WBP_PlayerInventory_C`, `WBP_LanternMenu_C`, `WBP_ProgressionMenu_C`, `WBP_PlayerJournal_C`, `WBP_PlayerQuests_C`, `WBP_FastTravel_C`, `WBP_SaveManager_C`, `WBP_DeathScreen_C`, `WBP_PlayerArsenal_C`, `WBP_PlayerStorage_C`, `WBP_MessageBox_C`.

## Input

- Toggle sprint: `GA_Sprint_C.bGamepadInput` makes sprint a toggle (the gamepad behaviour) for the keyboard too.
- Controller buttons via `PlayerController:IsInputKeyDown` with FKey names (`Gamepad_LeftThumbstick` for L3 **confirmed in game**).
- **UI-only input mode stops controller buttons from reaching the game** (and so `IsInputKeyDown`), **confirmed in game**. A controller-opened menu uses game-and-UI mode.
- The game uses **CommonUI**: the viewport client is `CommonGameViewportClient` and its action router is `MTUIActionRouterBase`, **confirmed in game**. `WBP_PayOff_C` and `WBP_Dialogue_C` stay activated (hidden) during normal play.
- **The first A after our menu opens reaches the player controller only as a release**, **confirmed in game** (2026-10-17): `IsInputKeyDown` never turns true for that press, but `WasInputKeyJustReleased` is true for one frame. Later A presses arrive normally, and other buttons (RB, D-pad) are never affected. Nothing hookable runs on that press (no `UserWidget` key or focus event, no CommonUI button, no input-mode change), so the press is taken natively, most likely by CommonUI as Accept. The menu acts on A's release and counts a release whose press it never saw, checked every frame (`Input.WatchReleases`); **fix confirmed in game**.
