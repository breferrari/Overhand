-- core/ui/font_finder.lua
-- Lists the fonts the game has loaded, so a theme can use the game's own (theme.fonts, see
-- Widgets.ResolveFonts). Writes <App.name>-Fonts.txt in the mod folder. Run it in game after the
-- game's menus have been shown at least once (only loaded fonts are found).

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")
local Paths = require("core.paths")

local FontFinder = {}

local FONT_CLASSES = { "Font", "FontFace" }

local function fullName(object) return object:GetFullName() end

function FontFinder.WriteReport()
    local found, seen = {}, {}
    for _, className in ipairs(FONT_CLASSES) do
        for _, object in ipairs(FindAllOf(className) or {}) do
            local name = Unreal.Try(fullName, object)
            if name and not seen[name] then
                seen[name] = true
                found[#found + 1] = name
            end
        end
    end
    table.sort(found)
    local fileName = App.name .. "-Fonts.txt"
    local header = {
        "# Loaded fonts (" .. #found .. "). A theme takes a Font's path (after the class name) or name fragments.",
        "",
    }
    local ok = Paths.WriteFile(Paths.InModFolder(fileName), table.concat(header, "\n") .. table.concat(found, "\n") .. "\n")
    Log.Info(string.format("fonts: %d written to %s", #found, fileName))
    App.status = ok and (#found .. " fonts saved to " .. fileName) or ("Could not write " .. fileName)
end

return FontFinder
