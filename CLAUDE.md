# ValorianSheet

UE4SS Lua cheat menu for Valor Mortis (UE 5.7). The mod is `mod/ValorianSheet/`; UE4SS loads `Scripts/main.lua`.
Three layers: `core/` (game-free framework), `gas/` (GAS helpers), `game/` (the game). `core/` must never require `gas/` or `game/`, and `gas/` never `game/`; the smoke test enforces it. Porting to another game: `docs/PORTING.md`.

- Read `docs/ARCHITECTURE.md` before changing code: layers, module responsibilities, and the rules (game thread only, no `FindAllOf` on per-tick paths, off means vanilla, everything guarded, full descriptive names).
- Performance background and the per-path budget: `docs/PERFORMANCE.md`.
- After any change: `python -I tools/smoke_test.py` (needs `pip install lupa`). It compiles with Lua 5.4, checks the first-start settings file and runs the mod against mocked UE4SS with strict globals. It cannot test game behaviour; say so when reporting.
- Install into the game: `tools/install.ps1` (Game Pass path by default, `-GameDir` for Steam, `-Uninstall`). The game must be closed.
- Version lives in `game/app.lua`; record changes in `CHANGELOG.md`.
- The owner's install is the Game Pass build: `C:\XboxGames\Valor Mortis\Content\ValorMortis\Binaries\Win64\ue4ss\Mods`.
