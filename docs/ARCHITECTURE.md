# Architecture

ValorianSheet is a UE4SS Lua mod. UE4SS loads `Scripts/main.lua`; everything else is a module loaded with `require`, resolved from `Scripts/` (`require("features.health")` is `Scripts/features/health.lua`).

## Layers

```
main.lua ──► settings.lua ─────────────┐
   │                                   ▼
   ├──► ui/sheet.lua ──► ui/menu.lua ──► state.lua ◄── features/*.lua ◄── cheats.lua
   │                        │                              │
   │                        ├─► ui/input.lua               ├─► game.lua ──► lib/unreal.lua
   │                        ├─► ui/game_menus.lua          └─► lib/override.lua
   │                        └─► ui/widgets.lua
   └──► one game-thread loop (every 33 ms): Menu.Tick, Cheats.Tick, Settings.SaveIfDirty
```

| Module | Responsibility |
|---|---|
| `lib/unreal.lua` | Safe calls into Unreal objects (`Try`, `IsValid`, ...) and **cached lookups** (`FindCached`). The only place that is allowed to search the object list on a schedule. |
| `lib/log.lua` | Session log (console + `ValorianSheet.log`), `Debug` lines, `Guarded` (run and log errors with a traceback). |
| `lib/paths.lua` | The mod folder; everything the mod writes stays in it. |
| `lib/override.lua` | Change a game value and put the vanilla value back later, even when the game changes it in between; keeps the **attribute ledger** for values that end up in the save file. |
| `game.lua` | Access to Valor Mortis: controller, player, components, attribute sets, subsystems, items, effects, the developers' cheat manager. |
| `state.lua` | `State.settings` (what the player chose), status line, teleports, ledger, and the few runtime flags that more than one feature reads. |
| `features/*.lua` | One module per feature group. Each exposes `Tick()` plus the actions the menu calls, and registers its per-world state with `Unreal.OnWorldReset`. |
| `cheats.lua` | Calls every feature's `Tick` in order, detects a new William (new save, map, respawn) and runs `Unreal.ResetWorld()`, runs the once-per-load checks. |
| `settings.lua` | `settings.cfg` and `teleports.txt`, saved through `Settings.MarkDirty()` (at most once a second). |
| `ui/menu.lua` | The menu framework: item kinds (toggle, choice, action, section, info), navigation, drawing, open/close. |
| `ui/sheet.lua` | The menu's content: which rows each tab has and what they are bound to. |
| `ui/widgets.lua` | Building UMG widgets from Lua; colours. |
| `ui/input.lua` | Key queue; blocking the game's input while the menu is open. |
| `ui/game_menus.lua` | Is one of the game's own menus open? (cached widgets, see Performance) |

## Features

| Module | Cheats |
|---|---|
| `health.lua` | God Mode, Infinite Stamina / Nephtoglobin, Fall Damage, Max Health, Damage Taken (fallback), Health Regeneration |
| `damage.lua` | Hooks on the game's damage functions: incoming (God Mode, Damage Taken) and outgoing (One-Hit Kills, Damage Multiplier) |
| `hud.lua` | The player's HUD widget, health bar updates, health bar length under Max Health |
| `combat.lua` | Combat state, Perfect Parry, Parry Window, Dodge Window, Kill All Enemies Nearby |
| `movement.lua` | Movement Speed, Jump Height, Instant Sprint, Toggle Sprint, NoClip, Game Speed |
| `teleport.lua` | Saved positions |
| `resources.lua` | Infinite Ammo / Flasks / Consumables, No Item Cooldowns, Keep Catalysts, Refill Everything |
| `buffs.lua` | Infinite Buffs |
| `give.lua` | Catalysts, materials, consumables, Give Item catalog, weapons, abilities, gems; removes the broken Crystal Grenade |
| `dev_actions.lua` | The developers' Blueprint cheat actions; No Ability Costs |
| `saved_values.lua` | After every load: repairs damage multipliers left by old cheat menu versions, restores ledger values |
| `bug_report.lua` | `ValorianSheet-BugReport.txt` |

## Rules

1. **Game thread only.** One loop (`LoopInGameThreadWithDelay`) runs the menu and the cheats. Key callbacks only queue a command; hooks only touch their parameters. No `LoopAsync`.
2. **No per-tick searches.** `FindAllOf` walks every object in the game. Look objects up through `Unreal.FindCached` / `Unreal.FindAllCached` / `Game.*`, which keep what they found and wait before searching again after a miss. Searching on a button press is fine. See [PERFORMANCE.md](PERFORMANCE.md).
3. **Off means vanilla.** A cheat that is switched off must leave the game as it found it. Use `Override` for any value the game also writes; record attributes that are saved in the ledger.
4. **Everything is guarded.** Unreal calls go through `Unreal.Try`; feature work that can fail runs under `Log.Guarded`, so one broken cheat never stops the loop.
5. **The menu only writes settings.** Features read `State.settings` and apply it in their `Tick`. Actions (buttons) are plain functions on the feature modules; the menu checks that a save is loaded before running one (unless it is marked `anytime`) and asks twice when it has a `confirm` prompt.
6. **One world reset.** Objects found through `lib/unreal.lua` are per world and dropped automatically; other per-world state is dropped in a callback registered with `Unreal.OnWorldReset`. Nothing else resets by hand.
7. **One way to save.** Whatever changes persisted state calls `Settings.MarkDirty()`; the main loop writes the files.
8. **Names say what things are.** Full names for modules (`Game`, `State`, `Health`) and locals (`player`, `healthSet`, `factor`).

## Adding a cheat

1. Add the setting with its vanilla value to `State.settings` in `state.lua`.
2. Implement it in the matching `features/` module: apply it in `Tick`; register anything per-world that is not a cached lookup with `Unreal.OnWorldReset`.
3. Add a row in `ui/sheet.lua` (`Menu.Toggle`, `Menu.Choice` or `Menu.Action`).
4. Run `python -I tools/smoke_test.py`, then try it in the game.
