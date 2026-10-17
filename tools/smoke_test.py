"""Smoke test for ValorianSheet, outside the game.

1. Compiles every Lua file with Lua 5.4 (the version UE4SS embeds).
2. Loads the mod against tools/ue4ss_mock.lua in a temporary copy of the mod folder, runs the
   game-thread loop in the main menu and with a loaded save, drives the menu with key presses,
   and fails on any error the mod logs ("ERROR in ...").

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


def compile_all() -> list[str]:
    errors = []
    lua = lua54.LuaRuntime()
    loader = lua.eval("function(source, name) local fn, err = load(source, '@' .. name) return err end")
    for path in sorted(MOD.rglob("*.lua")):
        err = loader(path.read_text(encoding="utf-8"), str(path.relative_to(REPO)))
        if err:
            errors.append(err)
    return errors


def run_mod(mod_folder: pathlib.Path, drive_menu: bool = True) -> tuple[list[str], str]:
    lua = lua54.LuaRuntime()
    scripts = (mod_folder / "Scripts").as_posix()
    lua.execute(f'package.path = "{scripts}/?.lua;" .. package.path')
    mock = lua.execute(f'return dofile("{MOCK.as_posix()}")')
    lua.execute(f'dofile("{scripts}/main.lua")')

    def tick(times=1):
        for _ in range(times):
            mock.loop()

    def press(key):
        mock.keyBinds[key]()
        tick()

    # Main menu: no player controller yet.
    tick(5)
    press("F6")
    # A save is loaded.
    mock.worldReady = True
    lua.execute("local clock = os.clock; os.clock = function() return clock() + 100 end")
    tick(5)
    # Drive the menu: open, walk every tab and row, change values, run actions (twice for confirms).
    press("F6")
    for _ in range(6 if drive_menu else 0):
        for _ in range(14):
            press("RIGHT_ARROW")
            press("LEFT_ARROW")
            press("RETURN")
            press("RETURN")
            press("DOWN_ARROW")
        press("E")
    press("Q")
    press("ESCAPE")
    tick(5)
    mock.loadMap()
    tick(5)

    log = (mod_folder / "ValorianSheet.log").read_text(encoding="utf-8")
    printed = "\n".join(str(mock.printed[i]) for i in range(1, len(mock.printed) + 1))
    problems = [line for line in log.splitlines() if "ERROR" in line]
    undefined = sorted({str(mock.undefinedGlobals[i]) for i in range(1, len(mock.undefinedGlobals) + 1)})
    if undefined:
        problems.append("undefined globals read: " + ", ".join(undefined))
    if "loaded, press F6" not in log:
        problems.append("mod did not finish loading:\n" + printed)
    return problems, log


def main() -> int:
    errors = compile_all()
    if errors:
        print("Compile errors:\n" + "\n".join(errors))
        return 1
    print("compile: ok")

    with tempfile.TemporaryDirectory() as temp:
        mod_copy = pathlib.Path(temp) / "ValorianSheet"
        shutil.copytree(MOD, mod_copy)
        cheat_menu = pathlib.Path(temp) / "ValorCheatMenu"
        cheat_menu.mkdir()
        (cheat_menu / "config.json").write_text(CHEAT_MENU_CONFIG, encoding="utf-8")
        (cheat_menu / "teleports.txt").write_text("2|Map_Hub|1.5|2.5|3.5|90|Bridge\n", encoding="utf-8")
        problems, log = run_mod(mod_copy, drive_menu=False)
        settings = (mod_copy / "settings.cfg").read_text(encoding="utf-8")
        teleports = (mod_copy / "teleports.txt").read_text(encoding="utf-8")
        problems += [f"import: expected '{line}' in settings.cfg" for line in IMPORT_EXPECTED if line not in settings.splitlines()]
        if "2|Map_Hub|1.5|2.5|3.5|90|Bridge" not in teleports:
            problems.append("import: teleports.txt not imported")
    if problems:
        print("Import errors:\n" + "\n".join(problems))
        return 1
    print("import from Valor Mortis Cheat Menu: ok")

    with tempfile.TemporaryDirectory() as temp:
        mod_copy = pathlib.Path(temp) / "ValorianSheet"
        shutil.copytree(MOD, mod_copy)
        problems, log = run_mod(mod_copy)
    if problems:
        print("Runtime errors:\n" + "\n".join(problems))
        return 1
    print("load + ticks + menu: ok")
    return 0


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
IMPORT_EXPECTED = [
    "perfectParry=true",
    "damageTaken=0.5",
    "fallDamage=0.75",
    "maxHealthFactor=3",
    "movementSpeed=1.5",
    "ledger.MaxHealth=100,300",
]


if __name__ == "__main__":
    sys.exit(main())
