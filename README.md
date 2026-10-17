# ValorianSheet

**An in-game cheat sheet for Valor Mortis.** One keyboard menu, every cheat, nothing running that you didn't switch on.

Press **F6**, pick a tab, change a value. Every cheat can be switched off at any time and puts the game back to vanilla when you do. Your choices are saved for the next session.

```
VALORIAN SHEET
SURVIVAL   MOVEMENT   COMBAT   ITEMS   GIVE   MISC
──────────────────────────────────────────────────
  God Mode                                     OFF
  Infinite Stamina                     <  ON  >
    ...only out of combat                      OFF
  Infinite Nephtoglobin                        OFF
  Fall Damage                     100% (vanilla)
  Damage Taken                               50%
  Max Health                        1x (vanilla)
HEALTH REGENERATION
  Regeneration                     Off (vanilla)

Ready
Up/Down select   Left/Right change   Enter use   Q/E tab   F6 close
```

## What's in it

| Tab | Cheats |
|---|---|
| **Survival** | God Mode · Infinite Stamina (optionally only out of combat) · Infinite Nephtoglobin · Fall Damage 100–0 % · Damage Taken 100–10 % · Max Health up to 5x (the health bar keeps its length) · Health Regeneration 1–50 HP/s with a delay after hits, a heal-up-to limit and an out-of-combat option |
| **Movement** | NoClip (Space up, Ctrl down) · Movement Speed up to 5x · Jump Height up to 10x · Game Speed 0.25–2x · Toggle Sprint for keyboard · Instant Sprint · **Teleport**: 5 saved positions per area |
| **Combat** | One-Hit Kills · Damage Multiplier up to 10x · Every Block Is A Perfect Parry · Parry Window 0.5–6x · Dodge Window 0.5–4x · Kill All Enemies Nearby (60 m) |
| **Items** | Infinite Ammo · Infinite Healing Flasks · Infinite Consumables · Infinite Buffs (potions, coatings, pistol boosts) · No Item Cooldowns · Keep Catalysts On Death · No Ability Costs · Refill Everything |
| **Give** | +1,000 / +10,000 Catalysts · +99 of every upgrade material · +5 of every consumable · Unlock all weapons / abilities / gems · **Give Item**: any consumable, material or instant item, 1–999 at a time (story items are left out so quests can't break) |
| **Misc** | Turn everything off · Debug logging · Write bug report |

Risky one-way actions (unlocks, Kill All, Turn Everything Off) need **Enter twice**.

## Controls

| Key | |
|---|---|
| **F6** | open / close |
| **Up / Down** | select a row |
| **Left / Right** | change the value |
| **Enter** | toggle, or run an action |
| **Q / E** | previous / next tab |
| **Esc** | close |
| **Mouse** | drag the slider on long lists (Give Item) |

While the menu is open the game gets no input, so you don't walk around or open the pause menu by accident. The menu won't open over a game menu, and closes itself when one appears (death screen, message box).

## Install

**Requirements**
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest), the **experimental-latest** build (Valor Mortis is Unreal Engine 5.7; the stable 3.0.1 doesn't support it).
- Recommended: UE4SS's `bForceGUObjectArrayForIteration = true` in `ue4ss\UE4SS-settings.ini` (the community "Crash Fix").

**With the script** (Game Pass path by default):

```powershell
.\tools\install.ps1
.\tools\install.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Valor Mortis"   # Steam
.\tools\install.ps1 -Uninstall
```

**By hand:** copy `mod\ValorianSheet` to `<game>\ValorMortis\Binaries\Win64\ue4ss\Mods\` so that `Mods\ValorianSheet\Scripts\main.lua` exists.

### Coming from the Valor Mortis Cheat Menu or Passive Health Regen

ValorianSheet replaces both; don't run them side by side. The install script switches them off (renames their `enabled.txt`) and leaves their folders alone. On the first start ValorianSheet **imports their settings**: the Cheat Menu's settings and teleports, including the record of values it wrote into your save (so nothing is left behind in your save file), and Passive Health Regen's regeneration settings.

## Files it writes

All inside `Mods\ValorianSheet\`:

| File | |
|---|---|
| `settings.cfg` | your settings, plain `key=value` text |
| `teleports.txt` | saved positions |
| `ValorianSheet.log`, `.log.old` | this session and the previous one |
| `ValorianSheet-BugReport.txt` | only when you press *Write bug report* |

## Performance

The menu does no work while it's closed beyond reading a key queue, and cheats that are off cost nothing. The things that made the Cheat Menu stutter (searching every object in the game several times a second while its menu was open, during health regeneration, and with Toggle Sprint on) are gone: every game object is found once and kept. Details in [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## How it works

Each cheat is a small module in `Scripts/features/` with a `Tick` that applies your settings; per-world state is dropped through one world reset. The menu only writes settings; everything is applied on the game thread from one loop. Layout and conventions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

```powershell
pip install lupa
python -I tools\smoke_test.py
```

The smoke test compiles every file with Lua 5.4 (what UE4SS embeds), checks the settings import, and loads the mod against mock UE4SS objects: main menu, a loaded save, every row of every tab, and a map change. It catches syntax, wiring and load errors; game behaviour still needs the game.

## Credits

- Parts of the cheat logic come from **Valor Mortis Cheat Menu** 1.3.2 by BryanHudson (MIT).
- Health Regeneration (healing through the game's attribute system, the combat check) and the menu style follow **AeonGreyh**'s Passive Health Regen, reimplemented here.
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) by the UE4SS-RE team (MIT).

## License

MIT. See [LICENSE](LICENSE).
