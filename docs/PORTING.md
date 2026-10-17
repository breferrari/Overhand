# Adding a game

Overhand keeps every game in one repo: `src/core/` (menu, input, settings, logging, lookups, overrides, the per-tick loop) and `src/gas/` know no game, and each game is a folder under `games/`. Adding a game is **a new `games/<name>/` folder with a `manifest.json`**; the installer builds that game's mod from `src/` plus that folder only, so no other game's code is installed with it. This guide uses **Atomic Heart** as the example.

## What a new game reuses

| Part | New game |
|---|---|
| `src/core/` | As is. |
| `src/gas/` | As is, **if** the game uses Unreal's Gameplay Ability System (`"usesGas": true` in the manifest). Many UE games do; Atomic Heart is not known to (its stats are likely on its own components). Without GAS it is not installed. |
| `tools/` | As is: `install.ps1 -Game <name>`, `smoke_test.py` (tests every game), the UE4SS mock. |
| `games/valormortis/` | The pattern to follow; none of it is installed for another game. |

The real work for a new game is **finding its internals**: which class is the player and his controller, where health and stamina live, which functions deal damage, which widgets are its menus. The framework covers everything else.

## Requirements

- **UE4SS** that supports the game's engine version. Atomic Heart is Unreal Engine 4; UE4SS's stable release covers UE 4.12 through 5.5 (UE 5.6+ games like Valor Mortis need the experimental build). Some games need a custom config from UE4SS's `zCustomGameConfigs`.
- The game must allow mods to load (UE4SS's DLL proxy). Single-player games usually do; online games with anti-cheat usually don't.

## Steps

### 1. Find the internals

Turn on UE4SS's console and tools (`UE4SS-settings.ini`: `ConsoleEnabled = 1`, `GuiConsoleEnabled = 1`) and use the Live View or the object dumper. Look for:

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
  manifest.json   where the game is, GAS or not, test expectations (not installed)
  init.lua        wiring (start from valormortis/init.lua and trim)
  app.lua         App.Define: version, menu title, settings with vanilla values
  game.lua        Controller(), Player(), and whatever access the cheats need
  sheet.lua       the menu tabs
  features/       one module per feature group
```

Inside the game folder, require its own modules as `game.*` (it is installed as `Scripts/game/`), and the shared ones as `core.*` / `gas.*`.

**`manifest.json`**

```json
{
    "gameName": "Atomic Heart",
    "modName": "Overhand",
    "defaultGameDir": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Atomic Heart",
    "modsPath": "AtomicHeart\\Binaries\\Win64\\ue4ss\\Mods",
    "processName": "AtomicHeart*",
    "usesGas": false,
    "replacesMods": [],
    "previousModFolders": [],
    "smokeTest": {
        "controllerClass": "<PlayerControllerClass>",
        "playerClass": "<PlayerCharacterClass>",
        "tabCount": 3,
        "expectLog": [],
        "expectDefaults": ["godMode=false"],
        "expectAbsentDefaults": []
    }
}
```

**`app.lua`**

```lua
local App = require("core.app")
App.Define({
    name = "Overhand",
    version = "0.1.0",
    menuTitle = "OVERHAND",
    status = "Waiting for a loaded save...",
    settings = { godMode = false, infiniteAmmo = false, movementSpeed = 1 },
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

**`init.lua`**: connects the game to core.

```lua
require("game.app")
local Runner = require("core.runner")
local Menu = require("core.ui.menu")
local Game = require("game.game")

Runner.Configure({ identity = Game.Player })
Runner.AddFeature("survival", require("game.features.survival").Tick)

Menu.Configure({
    controller = Game.Controller,
    player = Game.Player,
    isReady = function() return Game.Player() ~= nil end,
    gameMenuClasses = { "<PauseMenuWidgetClass>" },
    buttonIcons = {},
})

require("game.sheet").Build()
```

For a GAS game also add `Gas.Configure({ abilitySystem = Game.AbilitySystem })` and `Runner.OnTickStart(Gas.BeginTick)`.

**Features**: the same shape as Valor Mortis'. A tick function that reads `App.settings` and applies it, `Override` for values the game also writes (`Override:property(movement, "MaxWalkSpeed", factor)`), `Unreal.OnWorldReset` for per-world state.

### 3. Test and install

```powershell
python tools\smoke_test.py atomicheart
.\tools\install.ps1 -Game atomicheart
```

In the game: F5 or L3 + R3; check `Overhand.log` for "player found" and the features' lines. For controller prompts, Misc → **Find controller button icons** writes the game's loaded button images to `Overhand-ButtonIcons.txt`; put the paths into `buttonIcons` (`A`, `B`, `LB`, `RB`, `D-pad`).

## Things that may differ per game

- **Input mode with a controller.** In Valor Mortis the UI-only input mode stops controller buttons from reaching the game, so a controller-opened menu uses game-and-UI mode (`core/ui/input.lua`). Check the log's `controller:` lines in the new game.
- **World detection.** The runner starts a new world when the identity object (the player character) changes. If a game reuses the pawn across loads, give `Runner.Configure` a different identity (e.g. the world or game state).
- **Menu scaling** assumes a 1080p layout scaled to the viewport, which suits most games.
