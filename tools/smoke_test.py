"""Smoke test for ValorianSheet, outside the game.

1. Compiles every Lua file with Lua 5.4 (the version UE4SS embeds).
2. First start next to the Valor Mortis Cheat Menu and Passive Health Regen: their settings,
   teleports and attribute ledger must be imported.
3. Loads the mod against tools/ue4ss_mock.lua in a temporary copy of the mod folder, runs the
   game-thread loop in the main menu and with a loaded save, walks every row of every tab with key
   presses, and fails on any error the mod logs ("ERROR in ...") or any undefined global it reads.

This catches syntax, wiring and load errors. It does not test game behaviour; that needs the game.

Usage:  python -I tools/smoke_test.py      (needs: pip install lupa)
"""
import pathlib
import shutil
import sys
import tempfile

from lupa import lua54

REPO = pathlib.Path(__file__).resolve().parent.parent
MOD = REPO / "mod" / "ValorianSheet"
MOCK = REPO / "tools" / "ue4ss_mock.lua"
TAB_COUNT = 6
ROWS_PER_TAB = 14   # more than any tab has, so every row is visited

# The Valor Mortis Cheat Menu's config.json format (ModMenu ConfigManager), with a ledger entry.
CHEAT_MENU_CONFIG = """{
  "alwaysParry": true,
  "attrLedger": {
    "MaxHealth": {
      "vanilla": 100,
      "written": 300
    }
  },
  "debugLog": false,
  "dmgTaken": 0.5,
  "dock": "right",
  "fallDamage": 0.75,
  "godMode": false,
  "maxHealthMult": 3,
  "noClip": true,
  "speedMult": 1.5
}"""
PASSIVE_REGEN_CONFIG = """-- PassiveHealthRegen settings. Press the menu key in game to change them.
Enabled=1
MenuX=40
MenuY=40
HealthPerSecond=7.5
DelayAfterDamage=3.0
MaxPercent=80.0
OutOfCombatOnly=1
"""
IMPORT_EXPECTED = [
    "perfectParry=true",
    "damageTaken=0.5",
    "fallDamage=0.75",
    "maxHealthFactor=3",
    "movementSpeed=1.5",
    "regenPerSecond=7.5",
    "regenDelay=3",
    "regenMaxPercent=80",
    "regenOnlyOutOfCombat=true",
    "ledger.MaxHealth=100,300",
]


def compile_all() -> list[str]:
    errors = []
    lua = lua54.LuaRuntime()
    loader = lua.eval("function(source, name) local fn, err = load(source, '@' .. name) return err end")
    for path in sorted(MOD.rglob("*.lua")):
        err = loader(path.read_text(encoding="utf-8"), str(path.relative_to(REPO)))
        if err:
            errors.append(err)
    return errors


def run_mod(mod_folder: pathlib.Path, walk_menu: bool = True) -> list[str]:
    lua = lua54.LuaRuntime()
    scripts = (mod_folder / "Scripts").as_posix()
    lua.execute(f'package.path = "{scripts}/?.lua;" .. package.path')
    mock = lua.execute(f'return dofile("{MOCK.as_posix()}")')
    lua.execute(f'dofile("{scripts}/main.lua")')
    advance_clock = lua.eval("function(seconds) local clock = os.clock; os.clock = function() return clock() + seconds end end")

    def tick(times=1):
        for _ in range(times):
            mock.loop()

    def press(key):
        mock.keyBinds[key]()
        tick()

    # Main menu: no player controller yet.
    tick(5)
    press("F6")
    # A save is loaded; the clock jumps past the world's settle time.
    mock.worldReady = True
    tick(1)
    advance_clock(100)
    tick(5)
    # Open the menu and walk every row of every tab: change values, run actions (twice for confirms).
    press("F6")
    for _ in range(TAB_COUNT if walk_menu else 0):
        for _ in range(ROWS_PER_TAB):
            for key in ("RIGHT_ARROW", "LEFT_ARROW", "RETURN", "RETURN", "DOWN_ARROW"):
                press(key)
        press("E")
    press("Q")
    press("ESCAPE")
    # Let the settings save, then a map change.
    advance_clock(200)
    tick(5)
    mock.loadMap()
    tick(5)

    log = (mod_folder / "ValorianSheet.log").read_text(encoding="utf-8")
    problems = [line for line in log.splitlines() if "ERROR" in line]
    undefined = sorted({str(mock.undefinedGlobals[i]) for i in range(1, len(mock.undefinedGlobals) + 1)})
    if undefined:
        problems.append("undefined globals read: " + ", ".join(undefined))
    if "loaded, press F6" not in log:
        printed = "\n".join(str(mock.printed[i]) for i in range(1, len(mock.printed) + 1))
        problems.append("mod did not finish loading:\n" + printed)
    return problems


def fresh_mod_copy(temp: str) -> pathlib.Path:
    mod_copy = pathlib.Path(temp) / "ValorianSheet"
    shutil.copytree(MOD, mod_copy)
    return mod_copy


def test_import() -> list[str]:
    with tempfile.TemporaryDirectory() as temp:
        mod_copy = fresh_mod_copy(temp)
        cheat_menu = pathlib.Path(temp) / "ValorCheatMenu"
        cheat_menu.mkdir()
        (cheat_menu / "config.json").write_text(CHEAT_MENU_CONFIG, encoding="utf-8")
        (cheat_menu / "teleports.txt").write_text("2|Map_Hub|1.5|2.5|3.5|90|Bridge\n7|Map_Old|1|2|3|0|\n", encoding="utf-8")
        passive_regen = pathlib.Path(temp) / "PassiveHealthRegen"
        passive_regen.mkdir()
        (passive_regen / "PassiveHealthRegen.cfg").write_text(PASSIVE_REGEN_CONFIG, encoding="utf-8")

        problems = run_mod(mod_copy, walk_menu=False)
        settings = (mod_copy / "settings.cfg").read_text(encoding="utf-8").splitlines()
        teleports = (mod_copy / "teleports.txt").read_text(encoding="utf-8")
    problems += [f"import: expected '{line}' in settings.cfg" for line in IMPORT_EXPECTED if line not in settings]
    if any(line.startswith("noClip=") for line in settings):
        problems.append("import: noClip is session-only and must not be saved")
    for line in ("2|Map_Hub|1.5|2.5|3.5|90|Bridge", "7|Map_Old|1|2|3|0|"):
        if line not in teleports:
            problems.append(f"import: teleport '{line}' missing")
    return problems


def test_menu_walk() -> list[str]:
    with tempfile.TemporaryDirectory() as temp:
        return run_mod(fresh_mod_copy(temp))


def main() -> int:
    errors = compile_all()
    if errors:
        print("Compile errors:\n" + "\n".join(errors))
        return 1
    print("compile: ok")
    for name, test in (("import from other mods", test_import), ("load + ticks + menu", test_menu_walk)):
        problems = test()
        if problems:
            print(f"{name}: FAILED\n" + "\n".join(problems))
            return 1
        print(f"{name}: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
