-- core/app.lua
-- The mod's identity and its settings, shared by core and the game. The game fills it in once with
-- App.Define (see game/app.lua); core only reads it, and adds its own settings with App.AddSetting.

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

-- A setting with its default. options.notACheat: Turn Everything Off leaves it alone.
function App.AddSetting(key, default, options)
    if App.settings[key] == nil then App.settings[key] = default end
    App.defaults[key] = default
    if options and options.notACheat then App.notACheat[key] = true end
end

-- definition: { name, version, menuTitle, settings = { key = default, ... },
--               sessionOnly = { key = true }, notACheat = { key = true }, status }
-- Every app gets a debugLogging setting (core/log.lua reads it).
function App.Define(definition)
    App.name = definition.name
    App.version = definition.version
    App.menuTitle = definition.menuTitle or definition.name:upper()
    App.settings = definition.settings
    App.sessionOnly = definition.sessionOnly or {}
    App.notACheat = definition.notACheat or {}
    App.status = definition.status or ""
    App.defaults = {}
    for key, value in pairs(App.settings) do App.defaults[key] = value end
    App.AddSetting("debugLogging", false, { notACheat = true })
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
