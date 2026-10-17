# Bringing the menu to another game

`core/` (menu, input, settings, logging, lookups, overrides, the per-tick loop) and `gas/` know no game. A new game is a new folder next to `games/valormortis/` plus a one-word change in `main.lua`. This guide uses **Atomic Heart** as the example.

## What carries over, what doesn't

| Part | New game |
|---|---|
| `core/` | As is. |
| `gas/` | As is, **if** the game uses Unreal's Gameplay Ability System. Many UE games do; Atomic Heart is not known to (its stats are likely on its own components). Without GAS, leave `gas/` unused. |
| `tools/smoke_test.py`, `tools/ue4ss_mock.lua` | As is; the mock's player class names change (see Test). |
| `tools/install.ps1` | New game path and folder name. |
| `games/valormortis/` | Not reused: it is Valor Mortis' class names, attributes and cheats. Use it as the pattern. |

The real work for a new game is **finding its internals**: which class is the player and his controller, where health and stamina live, which functions deal damage, which widgets are its menus. The framework saves everything else.

## Requirements

- **UE4SS** that supports the game's engine version. Atomic Heart is Unreal Engine 4; UE4SS's stable release covers UE4 (UE 5.6+ games like Valor Mortis need the experimental build).
- The game must allow mods to load (`dwmapi.dll` / `xinput1_3.dll` proxy). Some games with anti-cheat block this; single-player games usually don't.

## Steps

### 1. Find the internals

Turn on UE4SS's console and object dumper (`UE4SS-settings.ini`: `ConsoleEnabled = 1`, then the "Dump objects" key, or the Live View in the GUI console). Look for:

| What | Valor Mortis | Atomic Heart (to find) |
|---|---|---|
| Player controller class | `BP_PlayerController_C` | the controller the pawn is possessed by |
| Player character class | `BP_PlayerCharacter_C` | the pawn class while playing |
| Health / stamina | GAS attribute sets (`HealthAttributes`, ...) | component properties or attribute sets |
| Damage | `MTCombatUtils:Deal*Damage` functions | a damage function to hook, or `TakeDamage` |
| Game menus | `WBP_PauseMenu_C`, ... | the pause / inventory widget classes |
| Developer cheats | `BP_MTCheatManager` | `CheatManager` subclass, if any |

### 2. Create `games/atomicheart/`

```
games/atomicheart/
  init.lua      wiring (copy valormortis/init.lua and trim)
  app.lua       App.Define: name, version, menu title, settings with vanilla values
  game.lua      Controller(), Player(), and whatever access the cheats need
  sheet.lua     the menu tabs
  features/     one module per feature group
```

**`app.lua`**: the mod's name decides its file names (`<name>.log`, `<name>-BugReport.txt`); `settings.cfg` and the menu keys are shared.

```lua
local App = require("core.app")
App.Define({
    name = "HeartSheet",
    version = "0.1.0",
    menuTitle = "HEART SHEET",
    status = "Waiting for a loaded save...",
    settings = { godMode = false, infiniteAmmo = false, movementSpeed = 1 },
    sessionOnly = {},
})
return App
```

**`game.lua`**: build on `core/unreal.lua`; never search per tick.

```lua
local Unreal = require("core.unreal")
local Game = {}
function Game.Controller() return Unreal.FindCached("controller", "<PlayerControllerClass>", 1) end
function Game.Player()
    local controller = Game.Controller()
    local pawn = controller and Unreal.Try(function() return controller.Pawn end)
    if Unreal.IsValid(pawn) then return pawn end
end
return Game
```

**`init.lua`**: the part that connects the game to core.

```lua
require("games.atomicheart.app")
local Runner = require("core.runner")
local Menu = require("core.ui.menu")
local Game = require("games.atomicheart.game")

Runner.Configure({ identity = Game.Player })
Runner.AddFeature("survival", require("games.atomicheart.features.survival").Tick)

Menu.Configure({
    controller = Game.Controller,
    player = Game.Player,
    isReady = function() return Game.Player() ~= nil end,
    gameMenuClasses = { "<PauseMenuWidgetClass>" },
    buttonIcons = {},
})

require("games.atomicheart.sheet").Build()
```

For a GAS game also add `Gas.Configure({ abilitySystem = Game.AbilitySystem })` and `Runner.OnTickStart(Gas.BeginTick)`.

**Features**: the same shape as Valor Mortis'. A tick function that reads `App.settings` and applies it, `Override` for values the game also writes (`Override:property(movement, "MaxWalkSpeed", factor)`), `Unreal.OnWorldReset` for per-world state.

### 3. Point `main.lua` at it

```lua
local GAME = "atomicheart"
```

and install the mod folder into the game's `ue4ss\Mods\` (adapt `tools/install.ps1`).

### 4. Test

- `python tools/smoke_test.py`: set the mock's controller and pawn class names in `tools/ue4ss_mock.lua` to the new game's. The layer check keeps `core/` and `gas/` game-free.
- In the game: F5 or L3 + R3; check the log (`<name>.log`) for "player found" and the features' lines.
- Controller prompts: Misc → **Find controller button icons** writes the game's loaded button images to `<name>-ButtonIcons.txt`; put the paths into `buttonIcons` (`A`, `B`, `LB`, `RB`, `D-pad`).

## Things that may differ per game

- **Input mode with a controller.** In Valor Mortis the UI-only input mode stops controller buttons from reaching the game, so a controller-opened menu uses game-and-UI mode (`core/ui/input.lua`). Check the log's `controller:` lines in the new game.
- **World detection.** The runner starts a new world when the identity object (the player character) changes. If a game reuses the pawn across loads, give `Runner.Configure` a different identity (e.g. the world or game state).
- **Menu scaling** assumes a 1080p layout scaled to the viewport, which suits most games.
