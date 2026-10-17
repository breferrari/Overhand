"""Smoke test for ValorianSheet, outside the game.

1. Compiles every Lua file with Lua 5.4 (the version UE4SS embeds).
2. Loads the mod against tools/ue4ss_mock.lua in a temporary copy of the mod folder, runs the
   game-thread loop in the main menu and with a loaded save, walks every row of every tab with key
   presses, and fails on any error the mod logs ("ERROR in ...") or any undefined global it reads.
3. A first start writes settings.cfg with the defaults.

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

def check_layers() -> list[str]:
    """core/ knows no game and no GAS; gas/ knows no game (so both carry over to another game)."""
    errors = []
    scripts = MOD / "Scripts"
    forbidden = {"core": ("games.", "gas."), "gas": ("games.",)}
    for layer, prefixes in forbidden.items():
        for path in sorted((scripts / layer).rglob("*.lua")):
            text = path.read_text(encoding="utf-8")
            for prefix in prefixes:
                if 'require("' + prefix in text:
                    errors.append(f"{path.relative_to(REPO)} requires {prefix}* ({layer}/ must not)")
    return errors


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
    press("F5")
    # A save is loaded; the clock jumps past the world's settle time.
    mock.worldReady = True
    tick(1)
    advance_clock(100)
    tick(5)
    # Open the menu and walk every row of every tab: change values, run actions (twice for confirms).
    press("F5")
    for _ in range(TAB_COUNT if walk_menu else 0):
        for _ in range(ROWS_PER_TAB):
            for key in ("RIGHT_ARROW", "LEFT_ARROW", "RETURN", "RETURN", "DOWN_ARROW"):
                press(key)
        press("E")
    press("Q")
    press("ESCAPE")
    # Controller: L3 + R3 opens, D-pad / A / LB / RB navigate (D-pad held repeats), B closes.
    def hold(*buttons, ticks=2):
        for button in buttons:
            mock.keysDown[button] = True
        tick(ticks)
        for button in buttons:
            mock.keysDown[button] = None
        tick()

    hold("Gamepad_LeftThumbstick", "Gamepad_RightThumbstick")
    for button in ("Gamepad_DPad_Down", "Gamepad_DPad_Right", "Gamepad_FaceButton_Bottom",
                   "Gamepad_RightShoulder", "Gamepad_LeftShoulder"):
        hold(button)
    advance_clock(1)
    hold("Gamepad_DPad_Down", ticks=20)
    hold("Gamepad_FaceButton_Right")
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
    if walk_menu and "controller: toggleWithController" not in log:
        problems.append("controller: L3 + R3 did not open the menu")
    if walk_menu and "button icons:" not in log:
        problems.append("Misc > Find controller button icons did not run")
    if walk_menu and "controller: close" not in log:
        problems.append("controller: B did not close the menu")
    if "loaded, press F5" not in log:
        printed = "\n".join(str(mock.printed[i]) for i in range(1, len(mock.printed) + 1))
        problems.append("mod did not finish loading:\n" + printed)
    return problems


def fresh_mod_copy(temp: str) -> pathlib.Path:
    mod_copy = pathlib.Path(temp) / "ValorianSheet"
    shutil.copytree(MOD, mod_copy)
    return mod_copy


def test_first_start() -> list[str]:
    with tempfile.TemporaryDirectory() as temp:
        mod_copy = fresh_mod_copy(temp)
        problems = run_mod(mod_copy, walk_menu=False)
        settings = (mod_copy / "settings.cfg").read_text(encoding="utf-8").splitlines()
    problems += [f"defaults: expected '{line}'" for line in ("godMode=false", "regenPerSecond=0", "debugLogging=false") if line not in settings]
    if any(line.startswith("noClip=") for line in settings):
        problems.append("noClip is session-only and must not be saved")
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
    layer_errors = check_layers()
    if layer_errors:
        print("Layer errors:\n" + "\n".join(layer_errors))
        return 1
    print("layers: ok")
    tests = (("load + ticks + menu", test_menu_walk), ("first start writes settings.cfg", test_first_start))
    for name, test in tests:
        problems = test()
        if problems:
            print(f"{name}: FAILED\n" + "\n".join(problems))
            return 1
        print(f"{name}: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
