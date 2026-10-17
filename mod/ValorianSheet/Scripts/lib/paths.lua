-- ValorianSheet / lib/paths.lua
-- Where the mod lives on disk. Everything the mod writes stays inside its own folder.

local Paths = {}

-- This file is <mod>/Scripts/lib/paths.lua; the mod folder is two levels up.
local scriptFolder = (debug.getinfo(1, "S").source:match("^@(.*[\\/])")) or ""
Paths.MOD_FOLDER = scriptFolder:gsub("[Ss]cripts[\\/]lib[\\/]$", "")

-- The Valor Mortis Cheat Menu's folder next to ours (its settings are imported once, see settings.lua).
Paths.CHEAT_MENU_FOLDER = Paths.MOD_FOLDER:gsub("[^\\/]+[\\/]$", "") .. "ValorCheatMenu\\"

function Paths.InModFolder(fileName) return Paths.MOD_FOLDER .. fileName end

function Paths.Exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

return Paths
