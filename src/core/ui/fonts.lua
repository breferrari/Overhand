-- core/ui/fonts.lua
-- The theme's own fonts, built at runtime from the font files in the mod folder (assets/fonts/).
--
-- How: the Font is a copy of the engine's Roboto (its composite font comes along). Each of its
-- typeface entries is renamed to one of our weights ("Regular", "Medium", "SemiBold", "Bold") and
-- pointed straight at our file: an entry without a FontFace asset streams the file named in its
-- FontFilename (FFontData falls back to its own fields without one), so no asset, package or
-- install into the game's Content folder is needed. (A FontFace made at runtime does not work: its
-- SourceFilename is only filled in when the engine loads one from disk, so it streams nothing and
-- the text lays out empty, silently.) The Font lives inside the Roboto font object (an outer
-- that always exists; a package cannot be looked up from Lua), is kept (root set) and remembered
-- here, so it is built once per session. Only a font that was built completely is remembered.
--
-- When a file is missing, or the copy has no typeface entries to fill, Build returns nil and the
-- menu keeps the engine's font. Whether the engine could read the files shows only when text is
-- laid out: the menu checks that (see build in core/ui/menu.lua).

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")
local Paths = require("core.paths")

local Fonts = {}

local ROBOTO = "/Engine/EngineFonts/Roboto.Roboto"
local KEEP = 0x83          -- RF_Public | RF_Standalone | RF_MarkAsRootSet
local STREAM = 1           -- EFontLoadingPolicy::Stream
local FONT_FOLDER = "assets/fonts/"

local built = {}      -- name -> the font, built completely this session
local attempts = 0    -- every attempt gets a name of its own (a failed one stays in memory)

-- Weights in the order they fill the copied entries: Regular first (the default typeface).
local function weightOrder(faces)
    local weights = {}
    for weight in pairs(faces) do
        if weight ~= "Regular" then weights[#weights + 1] = weight end
    end
    table.sort(weights)
    table.insert(weights, 1, "Regular")
    return weights
end

-- Points a typeface entry at a font file (and away from any FontFace asset, which would win).
local function pointAtFile(entry, file)
    local fontData = entry.Font
    if not pcall(function() fontData.FontFaceAsset = nil end) then fontData.FontFaceAsset = CreateInvalidObject() end
    fontData.FontFilename = file
    fontData.LoadingPolicy = STREAM
end

local function build(name, files)
    local roboto = Unreal.FindObject(ROBOTO)
    if not roboto then return nil, "no engine font to copy" end
    attempts = attempts + 1
    local font = StaticConstructObject(Unreal.Static("/Script/Engine.Font"), roboto,
        FName(App.name .. name .. "Font" .. attempts), KEEP, 0, false, false, roboto)
    if not Unreal.IsValid(font) then return nil, "could not create the font" end

    local weights, filled = weightOrder(files), 0
    font.CompositeFont.DefaultTypeface.Fonts:ForEach(function(_, element)
        filled = filled + 1
        local entry = element:get()
        local weight = weights[filled]
        -- entries beyond our weights show Regular, so nothing falls back to Roboto
        if weight then entry.Name = FName(weight) end
        pointAtFile(entry, files[weight or "Regular"])
    end)
    if filled == 0 then return nil, "the copied font has no typefaces" end
    if filled < #weights then
        Log.Info("menu fonts: " .. name .. " has room for " .. filled .. " of " .. #weights .. " weights")
    end
    return font
end

-- faces: { Regular = "Cinzel-SemiBold", Bold = "Cinzel-Bold", ... } (files in assets/fonts/, without
-- .ttf; Regular is required). Returns the font, or nil and why not.
function Fonts.Build(name, faces)
    if Unreal.IsValid(built[name]) then return built[name] end
    if not faces.Regular then return nil, "no Regular face" end
    local files = {}
    for weight, faceName in pairs(faces) do
        files[weight] = Paths.InModFolder(FONT_FOLDER .. faceName .. ".ttf")
        if not Paths.Exists(files[weight]) then return nil, faceName .. ".ttf missing from " .. FONT_FOLDER end
    end
    local ok, font, reason = pcall(build, name, files)
    if not ok then return nil, tostring(font) end
    built[name] = font
    return font, reason
end

return Fonts
