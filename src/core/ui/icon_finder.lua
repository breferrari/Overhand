-- core/ui/icon_finder.lua
-- Finds the game's controller button images, so the menu can show them instead of drawn chips.
-- Writes every loaded texture / sprite / brush whose path looks like a button prompt to
-- <App.name>-ButtonIcons.txt in the mod folder. Run it in game, after the game has shown controller
-- prompts at least once (only loaded images are found), then map the names in the game's menu
-- configuration (buttonIcons).

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")
local Paths = require("core.paths")

local IconFinder = {}

local ASSET_CLASSES = { "Texture2D", "PaperSprite", "SlateBrushAsset" }
local NAME_HINTS = {
    "gamepad", "controller", "xbox", "xsx", "xb1", "xinput", "ps4", "ps5", "dualsense", "dualshock",
    "button", "glyph", "prompt", "input", "keyicon", "key_", "face", "trigger", "bumper", "dpad", "thumbstick",
}

local function looksLikeButton(path)
    local lower = path:lower()
    for _, hint in ipairs(NAME_HINTS) do
        if lower:find(hint, 1, true) then return true end
    end
    return false
end

local function fullName(object) return object:GetFullName() end

function IconFinder.WriteReport()
    local found, seen = {}, {}
    for _, className in ipairs(ASSET_CLASSES) do
        for _, object in ipairs(FindAllOf(className) or {}) do
            local name = Unreal.Try(fullName, object)
            if name and not seen[name] and looksLikeButton(name) then
                seen[name] = true
                found[#found + 1] = name
            end
        end
    end
    table.sort(found)
    local fileName = App.name .. "-ButtonIcons.txt"
    local header = {
        "# Loaded images that look like controller button prompts (" .. #found .. ").",
        "# Found after the game showed prompts; the path after the class name is what buttonIcons needs.",
        "",
    }
    local ok = Paths.WriteFile(Paths.InModFolder(fileName), table.concat(header, "\n") .. table.concat(found, "\n") .. "\n")
    Log.Info(string.format("button icons: %d candidates written to %s", #found, fileName))
    App.status = ok and (#found .. " button image candidates saved to " .. fileName) or ("Could not write " .. fileName)
end

return IconFinder
