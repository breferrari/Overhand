# Changelog

## 1.5.0 (2026-10-17): its own look

- **New menu design**, Overhand's own (no longer modelled on AeonGreyh's menus):
  - header with the blood-handprint mark, the title and the game's name; the tabs are centred, each with a count of its rows changed from vanilla
  - toggles as OFF | ON (ON lit in the accent), choices as ‹ value ›; vanilla values read quieter than changed ones; every row changed from vanilla has a red mark
  - sub-rows ("only out of combat", the regeneration options) drawn under their parent with a connector
  - a description of the selected row; every Valor Mortis row has one
  - footer: what just changed ("Damage Taken: 50%"), how many settings differ from vanilla, and only the buttons that do something on the selected row ("A turn off", "D-pad change"); face buttons drawn as coloured discs
  - the frame has brass corner ticks; only what changed is redrawn, as before
- **Themes per game:** `games/<game>/theme.lua` (palette by role in sRGB hex, subtitle, mark, optional display font), passed with `Menu.Configure({ theme = ... })`. Valor Mortis: soot, parchment, crimson, brass.
- **Mark:** `assets/mark.png` is installed with the mod and loaded with the engine's `ImportFileAsTexture2D`; if that fails the menu draws a small diamond. The log says which (`menu mark:`).
- README: banner and a picture of the menu design.

## 1.4.0 (2026-10-17): Overhand

- **Renamed to Overhand** (was ValorianSheet). The installed folder is `Mods\Overhand\`; the install script takes `settings.cfg` and `teleports.txt` from `Mods\ValorianSheet\` and removes that folder. Logs and reports are `Overhand.log`, `Overhand-BugReport.txt`, `Overhand-ButtonIcons.txt`.
- **One repo, many games:** `src/` (main, core, gas) is shared and each game is a folder under `games/` with a `manifest.json`. `tools/install.ps1 -Game <game>` assembles `build/<game>/Overhand/` from `src/` and that game only (gas only for GAS games) and installs it; game code requires itself as `game.*`.
- **Smoke test** runs per game, assembled like the installer, with the game's expectations from its manifest; it now lets the features tick while the menu is walked (before, the walk happened inside the world's settle time, so features were never exercised).

## 1.3.0 (2026-10-17)

- **Layers for other games:** the code is split into `core/` (menu, input, settings, logging, lookups, overrides, the per-tick runner; knows no game), `gas/` (Gameplay Ability System helpers) and `game/` (Valor Mortis). Another game is a copy of the repo with its own `game/`. The game passes core what it needs (`Menu.Configure`, `Runner.Configure`, `Gas.Configure`) and register their features, settings stores and bug report sections. The smoke test enforces that core and gas stay game-free. Guide: [docs/PORTING.md](docs/PORTING.md).
- **Button chips:** the hint row draws every key and button as a keycap chip, and shows only the device the menu was opened with (keyboard or controller). Confirm prompts say "A again" when opened with the controller.
- **Button icons:** Misc → *Find controller button icons* writes the game's loaded button images to `ValorianSheet-ButtonIcons.txt`; configured icons (`buttonIcons`) replace the chips.
- `settings.cfg`, the ledger and teleports are separate stores (`Settings.RegisterLines` / `RegisterFile`); the file formats are unchanged.

## 1.2.0 (2026-10-17)

- **Controller support:** L3 + R3 opens and closes the menu; D-pad selects and changes (held: repeats), A uses, B closes, LB / RB switch tabs. The first 20 controller commands are logged. Key reading is shared (`Game.IsKeyDown`, also used by NoClip).
- **Controller fix (tested):** in UI-only input mode the game stops processing controller buttons, so the menu could open but not be navigated or closed. Opened with L3 + R3, the menu now uses game-and-UI input mode (William's own input stays disabled); opened with F5 it keeps UI-only mode.

## 1.1.0 (2026-10-17)

- **Health Regeneration** now follows AeonGreyh's Passive Health Regen: health points per second (1–50), a delay after hits, a heal-up-to limit, out-of-combat option; healing goes through the game's attribute system (GASCompanion), so the HUD follows on its own. The install script switches that mod off, so one mod covers everything.
- **Damage Taken** now follows AeonGreyh's Defense Multiplier: it raises William's resistance attributes (live value only, nothing saved) so the game's own damage math reduces every hit. The damage hooks no longer scale incoming damage except for God Mode, and the heal-back fallback is gone.
- **Combat check** uses the world's EnemyInfoSubsystem (the check Passive Health Regen uses), for regeneration and Infinite Stamina's out-of-combat option.
- **Cleanup** (`/simplify`):
  - one world reset (`Unreal.ResetWorld`, `Unreal.OnWorldReset`) instead of hand-wired resets
  - all object searches in `lib/unreal.lua` (`FindAllCached`, `FindAllLive`)
  - one save path (`Settings.MarkDirty`, saved by the main loop at most once a second); Debug logging is an ordinary setting
  - the menu checks for a loaded save before the confirm prompt (`Menu.Action` options); `Menu.Value` for menu-only values
  - shared helpers for the item database, tag names, HUD refreshes, rate-limited log lines, file I/O, `Game.IsPlayer`, `Game.PlayerHealth`, combat-utils hooks
- **Efficiency:** one shared read of the active effects per tick, Dodge Window reads it only when it changes, the menu only redraws what changed, memoized dynamic lists, early returns for cheats that are off, no closures in the hottest helpers.
- **Removed:** importing settings from the Valor Mortis Cheat Menu and Passive Health Regen (set them once in the menu).
- **Second cleanup** (`/simplify`):
  - Damage Taken is an `Override` (`Override:currentValue`, a read/write pair per entry) instead of its own tracking; re-applied when the active effects change or every 0.25 s.
  - Max Health scales current health by the actual change in max health, so the saved-values gate, its timeout and `appliedMaxHealthFactor` are gone; the check retries without holding other features back, and the damage repair runs once per world.
  - One heal helper (`addHealth` with a verified, sticky path) for God Mode and regeneration.
  - `Unreal.FindRanked` replaces the HUD's two lookups (one search, William's own HUD preferred).
  - The damage hooks are their own feature entry.
- **Menu key** is F5.
- **Second code review fixes:**
  - Max Health scales health from the max health we last wrote (or the one before switching on), so a level-up is no free heal.
  - Heals are verified every time and written directly only when that heal did not land; nothing is latched for good.
  - The saved-values check gives up after 10 s; `FindRanked` searches for a better candidate only every 30 s once it has a usable one.
  - Damage Taken logs when no resistance is readable; the health bar learns its scale only while max health is settled; the damage repair message survives a retry.
- **Fixes along the way:** every saved teleport slot is kept on save; settings write whole numbers without ".0".
- **Code review fixes:**
  - A world reset hands back vanilla values on objects that survive it (Override:release), so Movement Speed etc. can no longer compound after a restart.
  - Refill Everything forgets item peaks with the world (no topping a new save up to another save's counts).
  - The HUD lookup prefers the widget William owns over one with an unknown owner.
  - The shared effect list is re-read after Dodge Window removes an effect.
  - Regeneration checks that health actually rose and otherwise writes it directly.
  - The saved-values check retries until the attribute sets are readable (gives up after 10 s).
  - Every feature tick runs guarded on its own.
  - No Ability Costs retries quietly without a cheat manager.

## 1.0.0 (2026-10-17)

First version.

- **Menu:** a keyboard menu with tabs (Survival, Movement, Combat, Items, Give, Misc), built from plain UMG widgets. Blocks game input while open, won't open over game menus, two-step confirmation for one-way actions, mouse slider for long lists. Replaces the ModMenu library.
- **Performance:** no object searches on any per-tick path (game-menu watch, health bar, combat check, Toggle Sprint, controller and subsystem lookups). See [docs/PERFORMANCE.md](docs/PERFORMANCE.md).
- **Structure:** split into `lib/`, `game.lua`, `state.lua`, `features/` (one module per feature group), `cheats.lua`, `settings.lua` and `ui/`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Settings:** plain-text `settings.cfg`; imports the Valor Mortis Cheat Menu's `config.json` and `teleports.txt` (including its attribute ledger) on first start.
- **Tooling:** `tools/install.ps1` (install / uninstall, switches the Cheat Menu off), `tools/smoke_test.py` (compile + mocked load test).
- **Removed:** the unfinished "Invisible To Enemies" code; teleport slot renaming (no text input in the keyboard menu; names imported from the Cheat Menu are kept).
