# Performance

## The one expensive call

UE4SS's `FindAllOf(className)` walks the game's entire object array (hundreds of thousands of objects in Valor Mortis) and compares each object's class. With the community "Crash Fix" (`bForceGUObjectArrayForIteration = true`), UE4SS takes the slower, safer walk. One call is affordable on a button press; several per second show up as stutter.

Everything else (reading and writing properties, calling functions on objects the mod already holds) crosses from Lua into C++ once per call. That is cheap, but not free at 30 ticks a second, so per-tick paths also avoid repeating calls they don't need.

## What the Valor Mortis Cheat Menu 1.3.2 did

Per-tick or timer paths in the original that ran full object searches, found by reading its code. The stutters from the first two were confirmed in play; the rest follow from the same pattern.

| Where | When | Searches |
|---|---|---|
| Game-menu watch (`activeGameMenu`) | every 0.1 s **while its menu was open** | 13 classes → **~130 searches/s** |
| Health bar update (`updateHealthBar`) | every 0.25 s **while Health Regeneration healed** (and on every direct heal) | 4/s |
| Combat check (`inCombat`) | every 0.25 s when an "only out of combat" option was on | 4–8/s |
| Toggle Sprint ability lookup | every 1 s **while Toggle Sprint was on** | 1/s |
| Player controller lookup | **every tick (30/s)** whenever no player controller existed: main menu, loading screens | 30/s |
| Attribute set / inventory / save subsystem lookups | every tick while not found yet | up to 30/s each |

## How Overhand finds objects

All searches go through `core/unreal.lua`, the one place allowed to call `FindAllOf`:

- `Unreal.FindCached(key, class, retry, accept)`: the first matching object, kept while valid. After a miss, no new search for `retry` seconds.
- `Unreal.FindAllCached(key, class, retry)`: every live object of a class, kept; searched again only when none of them is alive, then at most every `retry` seconds.
- `Unreal.FindAllLive(class)`: an uncached search, for button presses only (Kill All Enemies Nearby).

Everything kept is per world and dropped by the single world reset when a new William appears.

| Path | Now |
|---|---|
| Game menus | Searched only when you press F5, at most once a minute per class that has no widget yet. While our menu is open only the kept widgets are checked, twice a second. The game gets no input while it's open, so its menus can't open by accident. |
| Health bar | The HUD widget is a ranked cached lookup (`Unreal.FindRanked`: William's own HUD first, unknown owner as fallback); the bar is its child. **0 searches** once his HUD is found. |
| Combat check | The enemy-info subsystem of William's world is kept. **0 searches** after the first. |
| Toggle Sprint | `FindAllCached`, retry 5 s. |
| Controller, components, attribute sets, inventory, save subsystem | `FindCached` / kept: 1–5 s between searches after a miss; in the main menu that's **1 search/s** instead of 30. |
| Kill All Enemies Nearby, Give, unlocks | One search on the button press. |

## Per-tick work

- **Cheats that are off** return before any lookup: fall damage at 100 %, regeneration off, Max Health 1x, Damage Taken 100 %, the health bar, damage hooks once registered.
- **Active effects** (Dodge Window, Infinite Buffs, the debug effect log) share one read of William's effect list per tick (`Game.ActiveEffects`). Effect class names are cached per definition. Dodge Window only reads the list when its length changes (a dodge adds effects) or while an early removal is pending.
- **Consumables:** one poll of 34 item counts, every 0.25 s while Infinite Consumables is on, every 1 s otherwise (for Refill Everything). Item tag structs are built once.
- **The hottest helpers** (`IsValid`, `AddressOf`, attribute reads) call module-level functions, so they allocate no closure per call.

| Cheat | Rate |
|---|---|
| Infinite Buffs | 0.1 s while on, 0.5 s while off |
| No Item Cooldowns | 0.25 s |
| Health Regeneration | a step every 0.25 s while healing |
| Damage Taken | resistances re-applied when the active effects change, at most every 0.25 s otherwise |
| Health bar length | 0.2 s while Max Health is raised |

## The menu

- **Closed:** each tick reads the key queue and one controller button (L3; R3 only while L3 is held) and returns.
- **Open:** the visible tab is redrawn 4 times a second and after every key press, but only widgets whose text or colour changed are touched (usually none, or the two rows the selection moved between). Long lists (Give Item, teleport slots) are rebuilt only when their source changes. No searches. The controller's A is also read every frame (two key reads), for releases visible for one frame only.
- **First open:** builds all widgets once (a few hundred `StaticConstructObject` calls). Expect one short hitch the first time you press F5 in a session.

## Checking it yourself

Compare frame times in the same spot with the mod on and off (rename `Mods\Overhand\enabled.txt`). Turn on **Debug logging** (Misc tab) to see what each cheat does in `Overhand.log`.
