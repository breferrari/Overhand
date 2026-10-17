# Overhand

![Overhand](docs/images/banner.png)

**In-game cheat menus for Unreal Engine games, built on UE4SS.** One menu, every cheat, nothing running that you didn't switch on.

Press **F5** (or **L3 + R3** on a controller), pick a tab, change a value. Every cheat can be switched off at any time and puts the game back to vanilla when you do. Your choices are saved for the next session.

<p align="center"><img src="docs/images/menu.png" width="480" alt="The Overhand menu in Valor Mortis"></p>

Every row says what it does while it's selected, rows changed from vanilla carry a red mark (and each tab counts them), and the footer shows only the buttons that do something on the selected row. Each game brings its own theme; this is Valor Mortis', set in Cinzel and Barlow Semi Condensed, which ship with the mod.

One repo holds the shared framework and every supported game. Installing builds a mod for **one** game from only what that game needs.

## Games

| Game | Folder | Status |
|---|---|---|
| **Valor Mortis** | `games/valormortis/` | Survival, movement, teleport, combat, items, give: [details below](#valor-mortis) |

Adding a game: [docs/PORTING.md](docs/PORTING.md) (worked example: Atomic Heart).

## Controls

| Keyboard | Controller | |
|---|---|---|
| **F5** | **L3 + R3** (click both sticks) | open / close |
| **Up / Down** | **D-pad up / down** | select a row (hold to repeat) |
| **Left / Right** | **D-pad left / right** | change the value (hold to repeat) |
| **Enter** | **A** | toggle, run an action, or open a list (then Left / Right a page, pick with Enter / A, back with Esc / B) |
| **Q / E** | **LB / RB** | previous / next tab |
| **Esc** | **B** | close |

The footer shows the buttons of the device you opened the menu with (or the game's own button icons, once mapped), and only those that do something on the selected row. While the menu is open your character doesn't move, look around or act. The menu won't open over a game menu, and closes itself when one appears. Risky one-way actions need **Enter (or A) twice**.

## Install

**Requirements**
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for the game's engine version (UE 5.6+ needs the **experimental-latest** build).
- Recommended: `bForceGUObjectArrayForIteration = true` in `ue4ss\UE4SS-settings.ini` (the community "Crash Fix").

**Install a game's mod** (the game must be closed):

```powershell
.\tools\install.ps1 -Game valormortis
.\tools\install.ps1 -Game valormortis -GameDir "D:\SteamLibrary\steamapps\common\Valor Mortis"
.\tools\install.ps1 -Game valormortis -Uninstall
.\tools\install.ps1 -Game valormortis -BuildOnly      # only assemble build\valormortis\Overhand\
```

The script assembles `build\<game>\Overhand\` and copies it into the game's `ue4ss\Mods\Overhand\`:

```
Scripts\main.lua    src\main.lua
Scripts\core\       src\core\
Scripts\gas\        src\gas\           (only for games that use GAS)
Scripts\game\       games\<game>\      (only that game)
assets\             assets\            (the menu's mark, arrows, button disc, fonts)
```

A game update or a Game Pass / Steam "repair" can remove UE4SS and the mod; install again afterwards. Your `settings.cfg` and teleports are kept across installs. The game's `manifest.json` lists other mods Overhand replaces (they are switched off, not deleted) and earlier folder names to take settings from.

## Files it writes

All inside `Mods\Overhand\`:

| File | |
|---|---|
| `settings.cfg` | your settings, plain `key=value` text |
| `teleports.txt` | saved positions (if the game has teleports) |
| `Overhand.log`, `.log.old` | this session and the previous one |
| `Overhand-BugReport.txt` | only when you press *Write bug report* |
| `Overhand-ButtonIcons.txt` | only when you press *Find controller button icons* |
| `Overhand-Quests.txt` | only when you press *Write quest report* (Valor Mortis) |

## Valor Mortis

| Tab | Cheats |
|---|---|
| **Survival** | God Mode · Infinite Stamina (optionally only out of combat) · Stamina Cost 100–25 % (attacks, dodges, blocks) · Infinite Nephtoglobin · Fall Damage 100–0 % · Damage Taken 100–10 % (through the game's own resistances) · Max Health up to 5x (the health bar keeps its length) · Health Regeneration 1–50 HP/s with a delay after hits, a heal-up-to limit and an out-of-combat option |
| **Movement** | NoClip (Space or A up, Ctrl, C or B down) · Movement Speed up to 5x · Jump Height up to 10x · Game Speed 0.25–2x · Toggle Sprint for keyboard · Instant Sprint · **Teleport**: 5 saved positions per area |
| **Combat** | One-Hit Kills · Damage Multiplier up to 10x · Every Block Is A Perfect Parry (two-handed weapons too) · Claymore Can Parry · Parry Window 0.5–6x · Dodge Window 0.5–4x · Kill All Enemies Nearby (60 m) |
| **Items** | Infinite Ammo (optionally still reloading) · Infinite Healing Flasks · Infinite Consumables · Infinite Buffs (potions, coatings, pistol boosts) · No Item Cooldowns · Keep Catalysts On Death (also deaths without a deathmark) · No Ability Costs · Free Respec · Refill Everything |
| **Give** | +1,000 / +10,000 Catalysts · +99 of every upgrade material · +5 of every consumable · Unlock all weapons / abilities / gems · **Give Item**: any consumable, material, instant or quest item from a list, 1–999 at a time (the count is checked afterwards) |
| **Quests** | Your active quests and what each one's current step asks for (read only) · Refresh the list · Write quest report |
| **Misc** | Turn everything off · Debug logging · Write bug report · Find controller button icons |

Overhand replaces the Valor Mortis Cheat Menu and AeonGreyh's Passive Health Regen; the install switches them off. Damage multipliers left in a save by Cheat Menu 1.1.0 and older are repaired automatically.

## Performance

The menu does no work while it's closed beyond reading a key queue and one controller button, and cheats that are off cost nothing. No object search runs on a per-tick path: every game object is found once and kept. Details in [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## How it works

```
games/<game>/     one folder per game: wiring, game access, features, menu content, manifest
src/gas/          Gameplay Ability System helpers (any GAS game)
src/core/         the menu, input, settings, logging, safe Unreal access, the per-tick loop
src/main.lua      entry point: loads game/init.lua
```

`src/core/` knows no game and no GAS; `src/gas/` knows no game. A game passes core what it needs (player, controller, its menu widgets) and registers its features. Each cheat is a small feature module with a tick that applies your settings; the menu only writes settings. Layout and rules: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

```powershell
pip install lupa
python tools\smoke_test.py               # every game
python tools\smoke_test.py valormortis   # one game
```

For every game the smoke test assembles the mod the way the installer does, compiles it with Lua 5.4 (what UE4SS embeds), checks the layers, and loads it against mock UE4SS objects: main menu, a loaded save with the features ticking, every row of every tab with keyboard and controller, a map change, and the first-start settings file. It catches syntax, wiring and load errors; game behaviour still needs the game.

## Docs

| | |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layers, how a game's mod is assembled, every module, the rules |
| [docs/PORTING.md](docs/PORTING.md) | Adding a game (worked example: Atomic Heart) |
| [docs/DISCOVERY.md](docs/DISCOVERY.md) | Finding a game's internals with UE4SS: dumps, Live View, hooks, testing, pitfalls, reviewing other mods |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | What costs what, and the per-path budget |
| [docs/games/valormortis.md](docs/games/valormortis.md) | Valor Mortis' internals: classes, attributes, damage functions, effects, items, menus |
| [CHANGELOG.md](CHANGELOG.md) | Every version |

## Credits

- Parts of the Valor Mortis cheat logic come from **Valor Mortis Cheat Menu** 1.3.2 by BryanHudson (MIT), and several 1.6.0 features follow its 1.4.0 findings, reimplemented.
- Valor Mortis Health Regeneration (healing through the game's attribute system, the combat check) and Damage Taken (raising resistances) follow **AeonGreyh**'s Passive Health Regen and Defense Multiplier, reimplemented here.
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) by the UE4SS-RE team (MIT).
- Fonts: [Cinzel](https://github.com/NDISCOVER/Cinzel) by Natanael Gama and [Barlow](https://github.com/jpt/barlow) by Jeremy Tribby, both under the SIL Open Font License 1.1 (`assets/fonts/`).

## License

MIT. See [LICENSE](LICENSE).
