# Overhand

UE4SS Lua cheat-menu framework with one folder per game. `src/main.lua` + `src/core/` (game-free framework) + `src/gas/` (GAS helpers) are shared; `games/<game>/` is one game (installed as `Scripts/game/`, required as `game.*`). Supported: `games/valormortis/` (Valor Mortis, UE 5.7; tested on the Game Pass build).

- Read `docs/ARCHITECTURE.md` before changing code: layers, assembly, module responsibilities, and the rules (game thread only, no `FindAllOf` on per-tick paths, off means vanilla, everything guarded, layers point down, full descriptive names). `src/core/` must never require `gas.*` or `game.*`, and `src/gas/` never `game.*`; the smoke test enforces it.
- Adding a game: `docs/PORTING.md`. Finding a game's internals (UE4SS dumps, Live View, hooks, pitfalls): `docs/DISCOVERY.md`. Performance rules: `docs/PERFORMANCE.md`.
- What we know about each game's internals: `docs/games/<game>.md` (update it when you learn or confirm something; mark what was confirmed in game).
- After any change: `python tools/smoke_test.py [game]` (needs `pip install lupa`). It assembles each game like the installer, compiles with Lua 5.4, checks the layers and runs the mod against mocked UE4SS with strict globals. It cannot test game behaviour; say so when reporting.
- Install: `tools/install.ps1 -Game <game>` (`-GameDir`, `-Uninstall`, `-BuildOnly`). The game must be closed. It finds the game in Steam, Xbox app / Game Pass, Epic and GOG installs; `games/<game>/manifest.json` names the game's folders (never a PC's path), GAS use, replaced mods and test expectations.
- Versions live in `games/<game>/app.lua`; record changes in `CHANGELOG.md`.
