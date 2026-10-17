-- core/ui/fonts.lua
-- The theme's own fonts, built at runtime from font files the installer puts in the game's Content
-- folder (<Project>/Content/<App.name>/Fonts/<face>.ufont: a cooked .ufont is the plain font file).
--
-- How: a FontFace whose loading policy is Stream reads its file from the path its package name maps
-- to, so each face gets its own package /Game/<App.name>/Fonts/<face>. The Font is a copy of the
-- engine's Roboto (its composite font comes along) with each typeface entry pointed at one of our
-- faces and renamed to its weight ("Regular", "Medium", "SemiBold", "Bold"). Everything is created
-- once per session and kept (root set), and found again by name after that.
--
-- When a file is missing, or the copy has no typeface entries to fill, Build returns nil and the
-- menu keeps the engine's font.

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")
local Paths = require("core.paths")

local Fonts = {}

local isValid = Unreal.IsValid

local ROBOTO = "/Engine/EngineFonts/Roboto.Roboto"
local KEEP = 0x83          -- RF_Public | RF_Standalone | RF_MarkAsRootSet
local STREAM = 1           -- EFontLoadingPolicy::Stream
-- the game's Content folder, from the mod folder: Mods inside Binaries/Win64/ue4ss, or Win64 itself
local CONTENT_FROM_MOD_FOLDER = { "../../../../../Content/", "../../../../Content/" }

local function packageRoot() return "/Game/" .. App.name .. "/Fonts/" end

local function find(path)
    local object = StaticFindObject(path)
    return isValid(object) and object or nil
end

-- The face's file on disk, or nil when the installer did not put it there.
function Fonts.FileFor(faceName)
    for _, contentFolder in ipairs(CONTENT_FROM_MOD_FOLDER) do
        local path = Paths.MOD_FOLDER .. contentFolder .. App.name .. "/Fonts/" .. faceName .. ".ufont"
        if Paths.Exists(path) then return path end
    end
    return nil
end

local function package(path)
    return find(path) or StaticConstructObject(Unreal.Static("/Script/CoreUObject.Package"), CreateInvalidObject(), FName(path), KEEP)
end

local function face(faceName)
    local packagePath = packageRoot() .. faceName
    local existing = find(packagePath .. "." .. faceName)
    if existing then return existing end
    local fontFace = StaticConstructObject(Unreal.Static("/Script/Engine.FontFace"), package(packagePath), FName(faceName), KEEP)
    fontFace.LoadingPolicy = STREAM
    return fontFace
end

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

local function build(name, faces)
    local fontPath = packageRoot() .. name
    local existing = find(fontPath .. "." .. name)
    if existing then return existing end
    local roboto = find(ROBOTO)
    if not roboto then return nil, "no engine font to copy" end
    local font = StaticConstructObject(Unreal.Static("/Script/Engine.Font"), package(fontPath), FName(name), KEEP, 0, false, false, roboto)
    if not isValid(font) then return nil, "could not create the font" end

    local weights, filled = weightOrder(faces), 0
    font.CompositeFont.DefaultTypeface.Fonts:ForEach(function(_, element)
        filled = filled + 1
        local entry = element:get()
        local weight = weights[filled]
        -- entries beyond our weights show Regular, so nothing falls back to Roboto
        if weight then entry.Name = FName(weight) end
        entry.Font.FontFaceAsset = face(faces[weight or "Regular"])
    end)
    if filled == 0 then return nil, "the copied font has no typefaces" end
    if filled < #weights then
        Log.Info("menu fonts: " .. name .. " has room for " .. filled .. " of " .. #weights .. " weights")
    end
    return font
end

-- faces: { Regular = "Cinzel-SemiBold", Bold = "Cinzel-Bold", ... } (file names without .ufont;
-- Regular is required). Returns the font, or nil and why not.
function Fonts.Build(name, faces)
    if not faces.Regular then return nil, "no Regular face" end
    for _, faceName in pairs(faces) do
        if not Fonts.FileFor(faceName) then return nil, faceName .. ".ufont not installed" end
    end
    local ok, font, reason = pcall(build, name, faces)
    if not ok then return nil, tostring(font) end
    return font, reason
end

return Fonts
