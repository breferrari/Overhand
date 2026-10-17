-- ValorianSheet / lib/paths.lua
-- Where the mod lives on disk, and small file helpers. Everything the mod writes stays inside its
-- own folder.

local Paths = {}

-- This file is <mod>/Scripts/lib/paths.lua; the mod folder is two levels up.
local scriptFolder = (debug.getinfo(1, "S").source:match("^@(.*[\\/])")) or ""
Paths.MOD_FOLDER = scriptFolder:gsub("[Ss]cripts[\\/]lib[\\/]$", "")

function Paths.InModFolder(fileName) return Paths.MOD_FOLDER .. fileName end

function Paths.Exists(path)
    local file = io.open(path, "r")
    if not file then return false end
    file:close()
    return true
end

-- The whole file, or nil when it does not exist.
function Paths.ReadFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("a")
    file:close()
    return content
end

-- Returns true, or false and the error.
function Paths.WriteFile(path, content)
    local file, err = io.open(path, "w")
    if not file then return false, err end
    file:write(content)
    file:close()
    return true
end

return Paths
