# Changelog

## 1.0.0 (2026-10-17)

First version.

- **Menu:** a keyboard menu with tabs (Survival, Movement, Combat, Items, Give, Misc), built from plain UMG widgets. Blocks game input while open, won't open over game menus, two-step confirmation for one-way actions, mouse slider for long lists. Replaces the ModMenu library.
- **Performance:** no object searches on any per-tick path (game-menu watch, health bar, combat check, Toggle Sprint, controller and subsystem lookups). See [docs/PERFORMANCE.md](docs/PERFORMANCE.md).
- **Structure:** split into `lib/`, `game.lua`, `state.lua`, `features/` (one module per feature group), `cheats.lua`, `settings.lua` and `ui/`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Settings:** plain-text `settings.cfg`; imports the Valor Mortis Cheat Menu's `config.json` and `teleports.txt` (including its attribute ledger) on first start.
- **Tooling:** `tools/install.ps1` (install / uninstall, switches the Cheat Menu off), `tools/smoke_test.py` (compile + mocked load test).
- **Removed:** the unfinished "Invisible To Enemies" code; teleport slot renaming (no text input in the keyboard menu; names imported from the Cheat Menu are kept).
