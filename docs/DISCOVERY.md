# Finding a game's internals

How to learn what a game is made of (its player class, where health lives, which function deals damage, which widgets are its menus) using the tools that come with UE4SS, and how to turn that into Overhand features. Most of the work for a new game is this; the framework covers the rest ([PORTING.md](PORTING.md)).

Everything here was used on Valor Mortis; what we found there is in [games/valormortis.md](games/valormortis.md), as an example of what to look for and write down.

## 1. Set UE4SS up

1. **Pick the right build.** UE4SS's stable release covers Unreal Engine 4.12 to 5.5. Games on UE 5.6 or newer need the **experimental-latest** build from the [official releases](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest).
   - **Telling the engine version:** UE4 games ship `pakchunk*-WindowsNoEditor.pak` in `Content\Paks` (UE5 dropped "NoEditor"). The exact version is in the UE4SS log once it runs.
2. **Prefer the official download** over repacks on mod sites. If you use a repack, compare it with the official build: same-named Lua files should match byte for byte, and `dwmapi.dll` should differ only in its header (build timestamp and debug ID). A repack made between two official builds can't be matched exactly; check its date against the release history, and scan it.
3. **Install:** copy `dwmapi.dll` and the `ue4ss\` folder next to the game's `*-Win64-Shipping.exe`.
   - **Steam:** `<game>\<Project>\Binaries\Win64\`.
   - **Game Pass:** `C:\XboxGames\<Game>\Content\<Project>\Binaries\Win64\` (in Valor Mortis it is `Win64`, not `WinGDK`; the folder is writable).
4. **Crash Fix:** `bForceGUObjectArrayForIteration = true` in `ue4ss\UE4SS-settings.ini` avoids crashes in some games. The cost is that object searches (`FindAllOf`) take a slower path; one more reason to never search per tick (see [PERFORMANCE.md](PERFORMANCE.md)).
5. **Check it runs:** `ue4ss\UE4SS.log` appears after launching. If the game crashes at start or UE4SS can't find engine functions, look for the game in UE4SS's `zCustomGameConfigs` download.

## 2. The tools

### One-key dumps (UE4SS's Keybinds mod, on by default)

| Keys | Writes (next to the game's exe) | Use it for |
|---|---|---|
| **Ctrl+J** | `UE4SS_ObjectDump.txt`: every object in memory now, with properties and current values | Finding the live player, his components, current stat values, which widgets exist |
| **Ctrl+H** | `CXXHeaderDump\`: every class and struct, with properties and functions, as C++-style headers (one file per module) | The game's design: what a class has, which functions exist (damage, inventory, cheats), parameter order |
| Ctrl+Numpad 7 | every actor in the level | Enemies, pickups, interactables |
| Ctrl+Numpad 9 | Unreal-header-compatible headers | Rarely needed here |

Dump **in a loaded save, after playing a few seconds**, so the player, HUD, menus and effects exist. Open the pause menu or inventory once before dumping if you want their widgets.

Leave `LoadAllAssetsBeforeDumpingObjects` and `LoadAllAssetsBeforeGeneratingCXXHeaders` at 0: the ini warns that loading past the main menu after a dump with them on crashes the game.

### Live View (the GUI console)

An object browser in a separate window: search objects by name, open one, and watch its properties update live. Set in `UE4SS-settings.ini` under `[Debug]`:

```ini
GuiConsoleEnabled = 1
GuiConsoleVisible = 1
```

This is the tool for "which of these numbers is my health": open the player character, take a hit, see which value drops.

### The text console

`ConsoleEnabled = 1` opens UE4SS's console window with every log line, including Overhand's. Errors from any Lua mod show up here and in `UE4SS.log`.

## 3. The workflow

1. **Dump** (Ctrl+J and Ctrl+H) in a loaded save, then quit.
2. **Map** from the files (it's text, so search it):
   - In the object dump, find the player controller and the pawn it possesses: the pawn's class is the player class. Its properties list its components (movement, health, abilities, inventory).
   - In the headers, read those classes: stat properties, functions with names like `Damage`, `Heal`, `Kill`, `AddItem`, `Cheat`, and their parameters.
   - Search the headers for `AttributeSet` and `AbilitySystemComponent`: if they exist, the game uses GAS and `src/gas/` applies.
   - Search for `CheatManager`: a game that ships its developer cheat manager may have working cheat actions (Valor Mortis' Blueprint actions worked; its C++ cheat functions were empty).
   - Widgets: classes starting with `WBP_` / `W_` / `UI_`. Note the pause, inventory and death screens for `gameMenuClasses`.
3. **Confirm** the guesses in Live View: open the object, change something in the game, watch the value.
4. **Write it down** in `docs/games/<game>.md` (classes, paths, what works, what doesn't), like [games/valormortis.md](games/valormortis.md).
5. **Implement** in `games/<game>/` (start with `game.lua` lookups, then one feature), smoke test, install, test in the game.

## 4. From a dump to Lua

**Objects**: always find them once and keep them (`core/unreal.lua`):

```lua
Unreal.FindCached("controller", "BP_PlayerController_C", 1)   -- first live instance, retried at most every 1 s
Unreal.FindAllCached("sprintAbilities", "GA_Sprint_C", 5)     -- every live instance
Unreal.Static("/Script/MinotaurCore.Default__MTCombatUtils")  -- function libraries / class defaults
```

`Default__...` objects are class templates, never the live instance; the lookups skip them.

**Properties** are fields: `player.CharacterMovement`, `set.Health.CurrentValue`. Reads and writes go through `Unreal.Try` (a missing property raises an error; Try returns nil instead).

**Functions** are methods: `combatUtils:Overheal(amount, player)`. Parameter order is the header's.

**Hooks** run Lua when the game calls a function, and can change its parameters:

```lua
RegisterHook("/Script/MinotaurCore.MTCombatUtils:DealMeleeDamage", function(context, damage, target, ...)
    local value = damage:get()     -- parameters arrive as references
    damage:set(value * 0.5)        -- scaled before the function runs
end)
```

- **Path format:** `/Script/<Module>.<Class>:<Function>` for C++ functions; Blueprint classes use their asset path. The module is the header file's name.
- **Struct parameters may arrive as copies.** After changing a field, read it back; if it didn't change, write the whole struct back with `param:set(struct)` (the parry window code does both).
- **Only hook loaded Blueprint functions.** Per the Cheat Menu's notes, hooking a Blueprint function whose class wasn't loaded yet failed and could leave the Lua state broken. Our hooks on C++ (`/Script/`) functions registered fine at any time.
- A hooked function that calls another hooked one runs both hooks; count the depth if only the outer call should act (`features/damage.lua`).

**GAS attributes** (if the game uses GAS): `BaseValue` is saved in the save file, `CurrentValue` is base plus active modifiers and is rebuilt by the game. Change `CurrentValue` for live-only effects; change `BaseValue` only through `Gas.BASE_VALUE` so the ledger keeps the vanilla value.

## 5. Testing in the game

- **Logs:** `Mods\Overhand\Overhand.log` (this session; `.log.old` is the previous one) and `ue4ss\UE4SS.log` (everything, with timestamps). Overhand logs "player found", each setting change ("menu: key -> value"), the first few times each cheat acts (e.g. "damage taken: 50% (4 resistances raised)", "health regeneration: ... through the game") and any error with its stack trace.
- **Debug logging** (Misc tab) logs every action, e.g. each damage hook call and each effect appearing on the player. Turn it on to see what the game does, off afterwards.
- **Write bug report** (Misc tab) collects settings, game state and the last 150 log lines in one file.
- **Smoke test first:** `python tools/smoke_test.py <game>` catches load and wiring errors before you start the game.

## 6. Pitfalls we hit

| Pitfall | What happened | Do instead |
|---|---|---|
| `FindAllOf` on a timer | The Cheat Menu searched every object ~130 times a second while its menu was open: stutter. | Cached lookups; search on button presses only. |
| UI-only input mode with a controller | The game stopped processing controller buttons, so the mod could not read them. | Game-and-UI mode when opened with the controller (`core/ui/input.lua`). |
| `LoopAsync` | Async loops next to game-thread hooks corrupted the Lua state (random crashes, per the Cheat Menu's notes). | One `LoopInGameThreadWithDelay` loop. |
| Our value taken for vanilla | A saved attribute changed by a cheat came back after a load looking like the game's own value. | Saved values go through the ledger (`core/ledger.lua`). |
| Resetting state that outlives the world | Re-reading a game asset's "original" values after a map change would have read our scaled ones. | Track assets by address instead of resetting them (`features/health.lua`, fall curve). |
| An old object still valid after a load | The previous HUD stayed valid next to the new one for a while. | Check the owner, prefer the player's own (`Unreal.FindRanked`). |
| Trusting a call without checking | A heal call can succeed without healing. | Read the value back; fall back to a direct write (`features/health.lua`). |
| Loading-screen characters | A pawn exists before the real player does. | Check the player's class, not just "a pawn exists". |

## 7. Reviewing someone else's mod before installing it

What we did for the Cheat Menu, Passive Health Regen and Defense Multiplier:

- **Lua mods:** read the scripts. Search for `os.execute`, `io.popen`, `loadstring`, `load(`, `dofile`, `package.loadlib`, `require` of unknown modules, URLs, and long encoded strings. Check that `io.open` only writes inside the mod's own folder.
- **DLLs:** compare with the official release (hash, or byte-diff for repacks), check the signature status, and scan with Microsoft Defender (`MpCmdRun.exe -Scan -ScanType 3 -File <path>`).
- **Performance:** look for `FindAllOf` inside loops, timers or per-tick functions, and for `LoopAsync`.
