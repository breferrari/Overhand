"""Smoke test for Overhand, outside the game. For every game in games/:

1. Assembles the mod the way tools/install.ps1 does (src/main.lua, src/core, src/gas when the
   manifest uses GAS, games/<game> as Scripts/game) into a temporary folder.
2. Compiles every Lua file with Lua 5.4 (the version UE4SS embeds), and checks the layers:
   core/ never requires gas/ or game/, gas/ never requires game/.
3. Loads the mod against tools/ue4ss_mock.lua, runs the game-thread loop in the main menu and with
   a loaded save, walks every row of every tab with key presses and with the controller, and fails
   on any error the mod logs ("ERROR in ...") or any undefined global it reads.
4. A first start writes settings.cfg with the defaults.

Per-game expectations live in games/<game>/manifest.json under "smokeTest".
This catches syntax, wiring and load errors. It does not test game behaviour; that needs the game.

Usage:  python tools/smoke_test.py [game]      (needs: pip install lupa)
"""
import json
import pathlib
import shutil
import sys
import tempfile

from lupa import lua54

REPO = pathlib.Path(__file__).resolve().parent.parent
SOURCE = REPO / "src"
GAMES = REPO / "games"
MOCK = REPO / "tools" / "ue4ss_mock.lua"
ROWS_PER_TAB = 20   # more than any tab has, so every row is visited


def load_manifest(game: str) -> dict:
    return json.loads((GAMES / game / "manifest.json").read_text(encoding="utf-8"))


def assemble(game: str, manifest: dict, into: pathlib.Path) -> pathlib.Path:
    """The installed mod folder, as tools/install.ps1 builds it."""
    mod = into / manifest["modName"]
    scripts = mod / "Scripts"
    scripts.mkdir(parents=True)
    shutil.copy(SOURCE / "main.lua", scripts)
    shutil.copytree(SOURCE / "core", scripts / "core")
    if manifest.get("usesGas"):
        shutil.copytree(SOURCE / "gas", scripts / "gas")
    shutil.copytree(GAMES / game, scripts / "game", ignore=shutil.ignore_patterns("manifest.json"))
    shutil.copytree(REPO / "assets", mod / "assets")
    return mod


def check_layers() -> list[str]:
    """core/ knows no game and no GAS; gas/ knows no game (so both serve every game)."""
    errors = []
    forbidden = {"core": ("game.", "gas."), "gas": ("game.",)}
    for layer, prefixes in forbidden.items():
        for path in sorted((SOURCE / layer).rglob("*.lua")):
            text = path.read_text(encoding="utf-8")
            for prefix in prefixes:
                if 'require("' + prefix in text:
                    errors.append(f"{path.relative_to(REPO)} requires {prefix}* ({layer}/ must not)")
    return errors


def compile_all(mod: pathlib.Path) -> list[str]:
    errors = []
    lua = lua54.LuaRuntime()
    loader = lua.eval("function(source, name) local fn, err = load(source, '@' .. name) return err end")
    for path in sorted(mod.rglob("*.lua")):
        err = loader(path.read_text(encoding="utf-8"), str(path.relative_to(mod)))
        if err:
            errors.append(err)
    return errors


def run_mod(mod: pathlib.Path, manifest: dict, walk_menu: bool = True) -> list[str]:
    expectations = manifest.get("smokeTest", {})
    lua = lua54.LuaRuntime()
    scripts = (mod / "Scripts").as_posix()
    lua.execute(f'package.path = "{scripts}/?.lua;" .. package.path')
    lua.globals().MockConfig = lua.table_from({
        "controllerClass": expectations.get("controllerClass", "PlayerController"),
        "playerClass": expectations.get("playerClass", "Character"),
    })
    mock = lua.execute(f'return dofile("{MOCK.as_posix()}")')
    lua.execute(f'dofile("{scripts}/main.lua")')
    advance_clock = lua.eval("function(seconds) local clock = os.clock; os.clock = function() return clock() + seconds end end")

    def frame():
        if mock.frameLoop:
            mock.frameLoop()

    def tick(times=1):
        for _ in range(times):
            frame()
            mock.loop()

    def press(key):
        mock.keyBinds[key]()
        tick()

    def hold(*buttons, ticks=2):
        for button in buttons:
            mock.keysDown[button] = True
        tick(ticks)
        for button in buttons:
            mock.keysDown[button] = None
            mock.keysJustReleased[button] = True
        tick()
        for button in buttons:
            mock.keysJustReleased[button] = None
        tick()

    # A button whose press never reached the controller, only its release (the game's CommonUI
    # takes the first A after the menu opens): the engine flags it as released for one frame.
    def release_only(button):
        mock.keysJustReleased[button] = True
        frame()
        mock.keysJustReleased[button] = None
        tick()

    def log_text():
        return (mod / (manifest["modName"] + ".log")).read_text(encoding="utf-8")

    problems = []

    # Main menu: no player controller yet.
    tick(5)
    press("F5")
    # A save is loaded. The clock moves past the controller lookup's retry (it missed in the main
    # menu), so the player is found and the runner starts a world; then past the world's settle
    # time, so the features run while the menu is walked.
    mock.worldReady = True
    advance_clock(5)
    tick(5)
    advance_clock(10)
    tick(5)
    if walk_menu:
        # Keyboard: every row of every tab; change values, run actions (twice for confirms).
        press("F5")
        for _ in range(expectations.get("tabCount", 1)):
            for _ in range(ROWS_PER_TAB):
                for key in ("RIGHT_ARROW", "LEFT_ARROW", "RETURN", "RETURN", "DOWN_ARROW"):
                    press(key)
            press("E")
        press("Q")
        press("ESCAPE")
        # Controller: L3 + R3 opens, D-pad / A / LB / RB navigate (D-pad held repeats), B closes.
        hold("Gamepad_LeftThumbstick", "Gamepad_RightThumbstick")
        # The first A after opening arrives only as a release; it must still act, once. A normal
        # press then acts once too (its release flag must not count a second time).
        release_only("Gamepad_FaceButton_Bottom")
        enters = log_text().count("controller: enter")
        if enters != 1:
            problems.append(f"an A seen only as a release: expected 1 'controller: enter', got {enters}")
        hold("Gamepad_FaceButton_Bottom")
        enters = log_text().count("controller: enter")
        if enters != 2:
            problems.append(f"an A press after it: expected 2 'controller: enter' in total, got {enters}")
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

    log = log_text()
    problems += [line for line in log.splitlines() if "ERROR" in line]
    undefined = sorted({str(mock.undefinedGlobals[i]) for i in range(1, len(mock.undefinedGlobals) + 1)})
    if undefined:
        problems.append("undefined globals read: " + ", ".join(undefined))
    if "loaded, press F5" not in log:
        printed = "\n".join(str(mock.printed[i]) for i in range(1, len(mock.printed) + 1))
        problems.append("mod did not finish loading:\n" + printed)
    if walk_menu:
        expected = ["controller: toggleWithController", "controller: close"] + expectations.get("expectLog", [])
        problems += [f"expected '{line}' in the log" for line in expected if line not in log]
    return problems


def test_game(game: str) -> list[str]:
    manifest = load_manifest(game)
    with tempfile.TemporaryDirectory() as temp:
        mod = assemble(game, manifest, pathlib.Path(temp))
        errors = compile_all(mod)
        if errors:
            return ["compile: " + error for error in errors]
        problems = run_mod(mod, manifest)
    with tempfile.TemporaryDirectory() as temp:
        mod = assemble(game, manifest, pathlib.Path(temp))
        problems += run_mod(mod, manifest, walk_menu=False)
        settings = (mod / "settings.cfg").read_text(encoding="utf-8").splitlines()
    expectations = manifest.get("smokeTest", {})
    problems += [f"first start: expected '{line}' in settings.cfg"
                 for line in expectations.get("expectDefaults", []) if line not in settings]
    problems += [f"first start: '{prefix}' must not be saved (session only)"
                 for prefix in expectations.get("expectAbsentDefaults", []) if any(line.startswith(prefix) for line in settings)]
    return problems


def main() -> int:
    layer_errors = check_layers()
    if layer_errors:
        print("layers: FAILED\n" + "\n".join(layer_errors))
        return 1
    print("layers: ok")
    games = sys.argv[1:] or sorted(path.name for path in GAMES.iterdir() if (path / "manifest.json").exists())
    failed = False
    for game in games:
        problems = test_game(game)
        if problems:
            print(f"{game}: FAILED\n" + "\n".join(problems))
            failed = True
        else:
            print(f"{game}: compile + load + menu (keyboard, controller) + first start: ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
