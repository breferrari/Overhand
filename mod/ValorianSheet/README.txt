Valor Mortis Cheat Menu v1.3.2 by BryanHudson
==============================================

One in-game menu for all cheats. Press F6 in game (or type "cheatmenu" in the UE4SS console).
Every cheat can be switched on and off at any time and goes back to vanilla when switched off.
Your settings are saved and come back the next time you play (NoClip always starts off).

Features
- Player:  God Mode, Infinite Stamina (optional: only out of combat), Infinite Nephtoglobin,
           Fall Damage (100% down to 0%), NoClip (Space up, Ctrl down),
           Damage Taken (100% down to 10%), Max Health (up to 5x, the health bar keeps its normal length),
           Health Regeneration (1% - 10% of max health per second, after a hit or only out of combat)
           Movement Speed (up to 5x), Jump Height (up to 10x), Game Speed (0.25x - 2x),
           Toggle Sprint (keyboard), Instant Sprint
- Teleport: save up to 5 named positions and teleport back to them (kept per area)
- Combat:  One-Hit Kills, Every Block Is A Perfect Parry, Parry Window (0.5x - 6x),
           Dodge Window (0.5x - 4x),
           Damage Multiplier (up to 10x),
           Kill All Enemies Nearby
- Items:   Infinite Ammo (no reload), Infinite Healing Flasks, Infinite Consumables,
           Infinite Buffs (potions, coatings, pistol boosts), No Item Cooldowns,
           Keep Catalysts On Death, No Ability Costs, Refill Everything
- Give:    +1,000 / +10,000 Catalysts, +99 Upgrade Materials, +5 Of Every Consumable,
           Unlock All Weapons, Unlock All Abilities, Unlock All Gems
- Give Item: pick any consumable, material or instant item from a searchable list and
           choose the amount (1 - 999). Story items are left out so quests can't break.
- Misc:    Turn Everything Off, Write Bug Report, Debug Logging

Requirements
- UE4SS for Valor Mortis

Install
Copy the ValorCheatMenu folder into
  ...\Valor Mortis\ValorMortis\Binaries\Win64\ue4ss\Mods\
Start the game, load a save, press F6.
The cheat menu closes when you open a game menu (pause, inventory, lantern, ...) and can only
be opened while no game menu is open.

Uninstall
Delete ue4ss\Mods\ValorCheatMenu.

Settings are saved to ValorCheatMenu\config.json.

Reporting bugs
1. Open the menu (F6) -> Misc tab -> turn on "Debug Logging".
2. Do what caused the bug again.
3. Press "Write Bug Report".
4. Attach these files from the ValorCheatMenu folder to your bug report:
   ValorCheatMenu-BugReport.txt and ValorCheatMenu.log
   (if the game crashed: ValorCheatMenu.log.old is the log of the crashed session,
    plus ue4ss\UE4SS.log)

Credits
- Menu UI: ModMenu by Matthew Arvidson (MIT License), github.com/mattdavida/ue4ss-ModMenu
  The full license text is in LICENSE-ModMenu.txt.
- UE4SS team (UE4SS, MIT License)
