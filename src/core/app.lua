-- core/app.lua
-- The mod's identity and its settings, shared by core and the game. The game fills it in once with
-- App.Define (see game/app.lua); core only reads it.

local App = {
    name = "Mod",
    version = "0.0.0",
    menuTitle = "MOD",
    settings = {},        -- what the player chose (the menu writes, the features read)
    defaults = {},        -- vanilla values, for Turn Everything Off
    sessionOnly = {},     -- keys not restored on start
    notACheat = {},       -- keys Turn Everything Off leaves alone
    status = "",          -- one line of feedback for the menu's status row
}

-- definition: { name, version, menuTitle, settings = { key = default, ... },
--               sessionOnly = { key = true }, notACheat = { key = true }, status }
-- Every app gets a debugLogging setting (core/log.lua reads it) and a themeFonts setting (the
-- menu's own fonts, core/ui/menu.lua); neither is a cheat.
function App.Define(definition)
    App.name = definition.name
    App.version = definition.version
    App.menuTitle = definition.menuTitle or definition.name:upper()
    App.settings = definition.settings
    App.settings.debugLogging = App.settings.debugLogging or false
    if App.settings.themeFonts == nil then App.settings.themeFonts = true end
    App.sessionOnly = definition.sessionOnly or {}
    App.notACheat = definition.notACheat or {}
    App.notACheat.debugLogging = true
    App.notACheat.themeFonts = true
    App.status = definition.status or ""
    App.defaults = {}
    for key, value in pairs(App.settings) do App.defaults[key] = value end
end

function App.SortedSettingKeys()
    local keys = {}
    for key in pairs(App.settings) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- Every cheat back to its vanilla value (settings that are not cheats stay).
function App.ResetCheats()
    for key, value in pairs(App.defaults) do
        if not App.notACheat[key] then App.settings[key] = value end
    end
end

return App
