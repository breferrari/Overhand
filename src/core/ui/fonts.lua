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
-- The files are looked for where the engine will read them: its own Content folder
-- (KismetSystemLibrary.GetProjectContentDirectory). When a file is missing, or the copy has no
-- typeface entries to fill, Build returns nil and the menu keeps the engine's font.

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")
local Paths = require("core.paths")

local Fonts = {}

local isValid, find = Unreal.IsValid, Unreal.FindObject

local ROBOTO = "/Engine/EngineFonts/Roboto.Roboto"
local KEEP = 0x83          -- RF_Public | RF_Standalone | RF_MarkAsRootSet
local STREAM = 1           -- EFontLoadingPolicy::Stream

local function packageRoot() return "/Game/" .. App.name .. "/Fonts/" end

-- The game's Content folder as the engine sees it (where a /Game/ package name points), or nil.
local function contentFolder()
    local library = Unreal.Static("/Script/Engine.Default__KismetSystemLibrary")
    local folder = Unreal.Try(function() return library:GetProjectContentDirectory() end)
    if folder ~= nil and type(folder) ~= "string" then folder = Unreal.Try(function() return folder:ToString() end) end
    return type(folder) == "string" and folder ~= "" and folder or nil
end

-- Is the face's file where the engine will stream it from?
local function isInstalled(folder, faceName)
    return Paths.Exists(folder .. App.name .. "/Fonts/" .. faceName .. ".ufont")
end

-- A new package (packages have no outer). Only called for a face or font not created yet, so the
-- name is free; it is not looked up first (UE4SS cannot look a bare package name up).
local function package(path)
    return StaticConstructObject(Unreal.Static("/Script/CoreUObject.Package"), CreateInvalidObject(), FName(path), KEEP)
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
-- Regular is required). Returns the font, or nil and why not. A font built earlier this session is
-- found again by name.
function Fonts.Build(name, faces)
    local existing = find(packageRoot() .. name .. "." .. name)
    if existing then return existing end
    if not faces.Regular then return nil, "no Regular face" end
    local folder = contentFolder()
    if not folder then return nil, "the engine did not say where its Content folder is" end
    for _, faceName in pairs(faces) do
        if not isInstalled(folder, faceName) then return nil, faceName .. ".ufont not installed in " .. folder end
    end
    local ok, font, reason = pcall(build, name, faces)
    if not ok then return nil, tostring(font) end
    return font, reason
end

return Fonts
