# Performance

## The one expensive call

UE4SS's `FindAllOf(className)` walks the game's entire object array (hundreds of thousands of objects in Valor Mortis) and compares each object's class. With the community "Crash Fix" (`bForceGUObjectArrayForIteration = true`), UE4SS takes the slower, safer walk. One call is affordable on a button press; several per second show up as stutter.

Everything else the mod does (reading and writing properties, calling functions on objects it already holds) is cheap.

## What the Valor Mortis Cheat Menu 1.3.2 did

These are the per-tick or timer paths in the original that ran full object searches. Found by reading its code. The stutters from the first two were confirmed in play; the rest follow from the same pattern.

| Where | When | Searches |
|---|---|---|
| Game-menu watch (`activeGameMenu`) | every 0.1 s **while its menu was open** | 13 classes → **~130 searches/s** |
| Health bar update (`updateHealthBar`) | every 0.25 s **while Health Regeneration healed** (and on every direct heal) | 4/s |
| Combat check (`inCombat`) | every 0.25 s when an "only out of combat" option was on | 4–8/s |
| Toggle Sprint ability lookup | every 1 s **while Toggle Sprint was on** | 1/s |
| Player controller lookup | **every tick (30/s)** whenever no player controller existed: main menu, loading screens | 30/s |
| Attribute set / inventory / save subsystem lookups | every tick while not found yet | up to 30/s each |

## What ValorianSheet does

| Path | Now |
|---|---|
| Game menus | Checked only when you press F6 (classes not seen yet: at most once a minute each). Widgets found are kept and checked directly; while the menu is open only the kept widgets are checked, twice a second. While open, the game gets no input, so its menus can't open by accident. |
| Health bar | The HUD widget is kept (found once, re-checked by owner once a second); the bar is its child. **0 searches.** |
| Combat check | The combat / enemy-info subsystems are kept (`Game.Subsystem`). **0 searches** after the first. |
| Toggle Sprint | Ability instances are kept; searched again only when none is alive, at most every 5 s. |
| Controller, attribute sets, inventory, save subsystem | `Unreal.FindCached`: kept while valid; after a miss, no new search for 1–5 s. In the main menu that's **1 search/s** instead of 30. |
| Kill All Enemies Nearby, Give, unlocks | One search on the button press (unchanged; not a per-tick path). |

## The menu

- **Closed:** each tick reads the key queue and returns. Nothing else.
- **Open:** text and colours of the visible tab are refreshed 4 times a second (about a dozen `SetText` calls), sliders are read every tick. No searches.
- **First open:** builds all widgets once (a few hundred `StaticConstructObject` calls). Expect one short hitch the first time you press F6 in a session.

## Cheats that are on

Most cheats are a few property reads and writes per tick. The heavier ones are throttled:

| Cheat | Rate |
|---|---|
| Infinite Consumables | item counts polled every 0.25 s (34 items, one call each) |
| Refill peak tracking | every 1 s |
| Infinite Buffs | active effects scanned every 0.1 s while on, 0.5 s while off (a short list on the player) |
| No Item Cooldowns | every 0.25 s |
| Health bar length (Max Health) | every 0.2 s while Max Health is raised |

## Checking it yourself

Compare frame times in the same spot with the mod on and off (rename `Mods\ValorianSheet\enabled.txt`). Turn on **Debug logging** (Misc tab) to see what each cheat does in `ValorianSheet.log`.
