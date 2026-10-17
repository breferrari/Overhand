# Architecture

Overhand is a UE4SS Lua mod framework with one folder per supported game. The repo holds:

```
src/main.lua        entry point
src/core/           Unreal + UE4SS + the menu framework (any UE4SS game)
src/gas/            Gameplay Ability System helpers (any GAS game)
games/<game>/       one game: app definition, game access, features, menu content, manifest.json
tools/              install.ps1 (build + install one game), smoke_test.py, ue4ss_mock.lua
```

## How a game's mod is assembled

`tools/install.ps1 -Game <game>` builds `build/<game>/Overhand/` from only what that game needs, and installs it into the game's `ue4ss/Mods/`:

```
Scripts/main.lua    src/main.lua
Scripts/core/       src/core/
Scripts/gas/        src/gas/          (only when manifest.json says usesGas)
Scripts/game/       games/<game>/     (without manifest.json)
assets/             assets/           (the menu's mark, arrows, button disc, fonts; shared by every game)
```

UE4SS loads `Scripts/main.lua`; everything else is a module loaded with `require`, resolved from `Scripts/` (`require("core.ui.menu")` is `Scripts/core/ui/menu.lua`). A game's own modules are always required as `game.*` (`require("game.features.health")`), so game code never knows its folder name in the repo. The smoke test assembles every game the same way.

Each game also has its page in `docs/games/<game>.md`: its cheats (what players see, linked from the README), then a reference of its internals.

`manifest.json` holds what the installer and the smoke test need: the game's folder names (`installFolders`, as Steam, the Xbox app, Epic or GOG name its folder; the installer finds the install) and Unreal project folder (`projectFolder`, which holds `Binaries\Win64` or `WinGDK`), its process name, whether it uses GAS, and the smoke test's expectations.

## Layers

Dependencies only point down:

```
games/<game>/   (installed as game/)
        │
        ▼
src/gas/
        │
        ▼
src/core/
```

`core/` never requires `gas/` or `game/`, and `gas/` never requires `game/`. The smoke test enforces this. Whatever core needs from a game (the player, the controller, the game's menu widgets, button icons) is passed in by the game at startup. A new game is a new folder under `games/` (see [PORTING.md](PORTING.md)).

## Startup

`main.lua` requires `game.init` (the installed game's `init.lua`), which:

1. defines the app (`App.Define`: name, version, menu title, every setting with its vanilla value),
2. passes core what it needs (`Gas.Configure`, `Menu.Configure`, `Runner.Configure`),
3. registers its features and once-per-world checks with the runner, and its bug report section,
4. builds the menu content (`Sheet.Build` → `Menu.AddTab`).

Then `main.lua` starts the log, loads the settings, binds the keys and starts one game-thread loop (every 33 ms): `Menu.Tick`, `Runner.Tick`, `Settings.SaveIfDirty`. When UE4SS has its EngineTick hook, a second game-thread loop runs every frame and only calls `Input.WatchReleases` (two key reads while the menu is open, nothing otherwise): a controller release can be visible for one frame only.

## src/core/

| Module | Responsibility |
|---|---|
| `app.lua` | The mod's identity and settings: `App.settings` (what the player chose), defaults, status line. Filled in by the game with `App.Define`. |
| `unreal.lua` | Safe calls into Unreal objects, **cached lookups** (`FindCached`, `FindAllCached`, `FindRanked`), key state, engine function libraries, and the **world reset** (`ResetWorld`, `OnWorldReset`). The only place that searches the object list on a schedule. |
| `log.lua` | Session log (`<name>.log`), debug lines, rate-limited lines, `Guarded` (run and log errors with a traceback, at most one error per context every 5 s). |
| `paths.lua` | The mod folder and file helpers; everything the mod writes stays in it. |
| `settings.lua` | `settings.cfg` (`App.settings`) plus lines and files other modules register (`RegisterLines`, `RegisterFile`). Saved through `MarkDirty`, at most once a second. |
| `ledger.lua` | Values we wrote into state the game saves, so our own value is never mistaken for vanilla after a load. |
| `override.lua` | Change a game value and put the vanilla value back later, even when the game changes it in between. What is changed is an accessor (read/write, saved or not): `Override.PROPERTY` here, GAS attributes in `gas/`. |
| `runner.lua` | The per-tick loop for the game's features: detects a new player character (new world), runs once-per-world checks, ticks every feature guarded on its own. |
| `bug_report.lua` | `<name>-BugReport.txt`: settings, the game's sections, recent log lines. |
| `ui/menu.lua` | The menu framework: item kinds (toggle, choice, list (a choice picked from a list that opens in the description panel), action, section, info; sub-rows, descriptions), navigation, drawing only what changed, open/close. The layout: header (mark, title, game name, tabs with changed-row counts), rows (OFF \| ON toggles, ‹ value › choices, a mark on rows changed from vanilla; a tab taller than the screen scrolls, with an indicator), the selected row's description, a footer with the status, the changed count and the buttons that act on the selected row. |
| `ui/widgets.lua` | Building UMG widgets from Lua: text, borders, outlines, bars, diamonds, shrink-to-fit boxes, key and face-button chips, tinted icons, textures from PNG files, the theme's fonts; the theme (colour roles written as sRGB hex, converted to the linear colours UMG draws with). |
| `ui/input.lua` | Keyboard queue, controller polling (L3 + R3, D-pad, A, B, LB, RB), blocking the game's input while the menu is open. A acts on its release, watched every frame (`WatchReleases`), because a game can take its press (Valor Mortis' CommonUI does, for the first A). |
| `ui/game_menus.lua` | Is one of the game's own menus open? (classes from the game, cached widgets) |
| `ui/icon_finder.lua` | Writes the loaded images that look like controller button prompts to a file, to map the game's own icons. |
| `ui/fonts.lua` | The theme's fonts at runtime: a Font copied from the engine's Roboto whose typeface entries stream our `.ttf` files from `assets/fonts/` by file name (no FontFace assets: one made at runtime has no file name, so it renders nothing). The menu falls back to the engine font when a file is missing or its text lays out empty. |

## src/gas/

`gas.lua`: attribute reads and writes (`GetAttribute`, `SetBaseValueKeepModifiers`, `FillAttribute`, ...), the override accessors `BASE_VALUE` (saved, ledgered) and `CURRENT_VALUE` (live only), gameplay tags, applying effects, and a per-tick snapshot of the player's active effects. Needs only the player's AbilitySystemComponent, passed in with `Gas.Configure`.

## games/valormortis/

| Module | Responsibility |
|---|---|
| `manifest.json` | Install and test settings (see How a game's mod is assembled). Not installed. |
| `init.lua` | Wires everything above (see Startup). |
| `app.lua` | Name, version, menu title, every setting with its vanilla value. |
| `game.lua` | Valor Mortis access: controller and player classes, components, attribute sets, subsystems, items, the developers' cheat manager. |
| `shared.lua` | Runtime flags more than one feature reads (NoClip active, safe landing). |
| `sheet.lua` | The menu content: seven tabs, what each row is bound to and what it does (its description). |
| `theme.lua` | The menu's look for this game: palette, subtitle, mark (`assets/mark.png`), optional display font. |
| `features/health.lua` | God Mode, Infinite Stamina / Nephtoglobin, Fall Damage, Max Health, Health Regeneration |
| `features/defense.lua` | Damage Taken (raises the resistance attributes) |
| `features/damage.lua` | Hooks on the game's damage functions: God Mode blocking, One-Hit Kills, Damage Multiplier |
| `features/hud.lua` | The player's HUD widget, health bar updates, health bar length under Max Health |
| `features/combat.lua` | Combat state, Perfect Parry, Claymore Can Parry, Parry Window, Dodge Window, Kill All Enemies Nearby |
| `features/movement.lua` | Movement Speed, Jump Height, Instant Sprint, Toggle Sprint, NoClip, Game Speed |
| `features/teleport.lua` | Saved positions (`teleports.txt`) |
| `features/resources.lua` | Infinite Ammo / Flasks / Consumables, No Item Cooldowns, Keep Catalysts, Refill Everything |
| `features/buffs.lua` | Infinite Buffs |
| `features/give.lua` | Catalysts, materials, consumables, Give Item catalog (with quest items) and its count check, weapons, abilities, gems |
| `features/progression.lua` | Free Respec (the lantern's respec costs) |
| `features/quests.lua` | The Quests tab: active quests and what their current step asks for (read only); the quest report (`Overhand-Quests.txt`) |
| `features/dev_actions.lua` | The developers' Blueprint cheat actions; No Ability Costs |
| `features/saved_values.lua` | Once per world: puts back values the game saved while a cheat was on (from the ledger) |

## Rules

1. **Game thread only.** One loop (`LoopInGameThreadWithDelay`) runs the menu and the features; the only other loop is the per-frame release watch (`LoopInGameThreadAfterFrames`, also the game thread). Key callbacks only queue a command; hooks only touch their parameters. No `LoopAsync`.
2. **No per-tick searches.** `FindAllOf` walks every object in the game. Look objects up through `Unreal.FindCached` / `FindAllCached` / `FindRanked` (or the game's helpers built on them), which keep what they found and wait before searching again. Searching on a button press is fine. See [PERFORMANCE.md](PERFORMANCE.md).
3. **Off means vanilla.** A cheat that is switched off must leave the game as it found it. Use `Override` for any value the game also writes; saved values go through a saved accessor (ledger).
4. **Everything is guarded.** Unreal calls go through `Unreal.Try`; features and checks run under `Log.Guarded`, so one broken cheat never stops the loop.
5. **The menu only writes settings.** Features read `App.settings` and apply it in their tick. Actions (buttons) are plain functions; the menu checks that a save is loaded before running one (unless it is marked `anytime`) and asks twice when it has a `confirm` prompt.
6. **One world reset.** Objects found through `core/unreal.lua` are per world and dropped automatically; other per-world state is dropped in a callback registered with `Unreal.OnWorldReset`.
7. **One way to save.** Whatever changes persisted state calls `Settings.MarkDirty()`; the main loop writes the files.
8. **Layers point down.** `core/` knows no game and no GAS; `gas/` knows no game. A game passes core what it needs, and requires its own modules as `game.*`.
9. **Names say what things are.** Full names for modules (`Game`, `App`, `Health`) and locals (`player`, `healthSet`, `factor`).

## Adding a cheat

1. Add the setting with its vanilla value in `games/<game>/app.lua`.
2. Implement it in the matching `features/` module: apply it in a tick function; register anything per-world that is not a cached lookup with `Unreal.OnWorldReset`. A new module is registered in `init.lua` with `Runner.AddFeature`.
3. Add a row in `sheet.lua` (`Menu.Toggle`, `Menu.Choice` or `Menu.Action`).
4. Run `python tools/smoke_test.py <game>`, install with `tools/install.ps1 -Game <game>` and try it in the game.
