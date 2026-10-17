# Changelog

## 1.1.0 (2026-10-17)

- **Health Regeneration** now follows AeonGreyh's Passive Health Regen: health points per second (1–50), a delay after hits, a heal-up-to limit, out-of-combat option; healing goes through the game's attribute system (GASCompanion), so the HUD follows on its own. Its settings are imported on first start, and the install script switches that mod off, so one mod covers everything.
- **Combat check** uses the world's EnemyInfoSubsystem (the check Passive Health Regen uses), for regeneration and Infinite Stamina's out-of-combat option.
- **Cleanup** (`/simplify`):
  - one world reset (`Unreal.ResetWorld`, `Unreal.OnWorldReset`) instead of hand-wired resets
  - all object searches in `lib/unreal.lua` (`FindAllCached`, `FindAllLive`)
  - one save path (`Settings.MarkDirty`, saved by the main loop at most once a second); Debug logging is an ordinary setting
  - the menu checks for a loaded save before the confirm prompt (`Menu.Action` options); `Menu.Value` for menu-only values
  - shared helpers for the item database, tag names, HUD refreshes, rate-limited log lines, file I/O, `Game.IsPlayer`, `Game.PlayerHealth`, combat-utils hooks
- **Efficiency:** one shared read of the active effects per tick, Dodge Window reads it only when it changes, the menu only redraws what changed, memoized dynamic lists, early returns for cheats that are off, no closures in the hottest helpers.
- **Fixes along the way:** teleport slots beyond 5 imported from the Cheat Menu are kept on save; settings write whole numbers without ".0".

## 1.0.0 (2026-10-17)

First version.

- **Menu:** a keyboard menu with tabs (Survival, Movement, Combat, Items, Give, Misc), built from plain UMG widgets. Blocks game input while open, won't open over game menus, two-step confirmation for one-way actions, mouse slider for long lists. Replaces the ModMenu library.
- **Performance:** no object searches on any per-tick path (game-menu watch, health bar, combat check, Toggle Sprint, controller and subsystem lookups). See [docs/PERFORMANCE.md](docs/PERFORMANCE.md).
- **Structure:** split into `lib/`, `game.lua`, `state.lua`, `features/` (one module per feature group), `cheats.lua`, `settings.lua` and `ui/`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Settings:** plain-text `settings.cfg`; imports the Valor Mortis Cheat Menu's `config.json` and `teleports.txt` (including its attribute ledger) on first start.
- **Tooling:** `tools/install.ps1` (install / uninstall, switches the Cheat Menu off), `tools/smoke_test.py` (compile + mocked load test).
- **Removed:** the unfinished "Invisible To Enemies" code; teleport slot renaming (no text input in the keyboard menu; names imported from the Cheat Menu are kept).
