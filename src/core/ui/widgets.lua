-- core/ui/widgets.lua
-- Building plain UMG widgets from Lua (StaticConstructObject), and the menu's theme: colours by
-- role, written as sRGB hex and turned into the linear colours UMG draws with.

local Unreal = require("core.unreal")
local App = require("core.app")
local Log = require("core.log")
local Paths = require("core.paths")
local Fonts = require("core.ui.fonts")

local Widgets = {}

local try = Unreal.Try

-- ESlateVisibility
local SHOWN = 4        -- SelfHitTestInvisible: drawn, not hit by the mouse itself
local COLLAPSED = 1

-- EHorizontalAlignment / EVerticalAlignment
Widgets.FILL, Widgets.START, Widgets.CENTER, Widgets.END = 0, 1, 2, 3

-- "#RRGGBB" (sRGB, as a designer writes it) -> the linear FLinearColor UMG expects; nil when it is
-- not a colour written that way.
function Widgets.Hex(hex, alpha)
    if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x$") then return nil end
    local function channel(offset)
        local value = tonumber(hex:sub(offset, offset + 1), 16) / 255
        if value <= 0.04045 then return value / 12.92 end
        return ((value + 0.055) / 1.055) ^ 2.4
    end
    return { R = channel(2), G = channel(4), B = channel(6), A = alpha or 1.0 }
end

-- The default theme (neutral greys). A game passes its own with Menu.Configure({ theme = ... }):
-- any role it leaves out keeps the default.
local DEFAULT_PALETTE = {
    panel = "#141414",           -- the menu's background
    edge = "#3A3A3A",            -- frame, header and footer lines
    corner = "#B0B0B0",          -- the frame's corner ticks
    footer = "#101010",          -- the status / hints bar
    rowSelected = "#202020",     -- the selected row
    selectionBar = "#B0B0B0",    -- the selected row's left edge
    hairline = "#4A4A4A",        -- the header rule, idle toggle frames, sub-row connectors
    title = "#E6E6E6",           -- the title and values that differ from vanilla
    bright = "#F2F2F2",          -- the selected row's label, text on the accent
    label = "#B0B0B0",           -- row labels
    muted = "#8C8C8C",           -- sub-rows, vanilla values, the subtitle, hint labels
    dim = "#6E6E6E",             -- inactive tabs
    faint = "#5A5A5A",           -- arrows, the unlit half of a toggle
    accent = "#C03030",          -- the active tab, section titles, ON, changed-from-vanilla marks
    highlight = "#C8C8C8",       -- tab counts, the status line, the description title
    toggleOff = "#2A2A2A",       -- the lit OFF half of a toggle
    descriptionPanel = "#0F0F0F",
    descriptionEdge = "#2A2A2A",
    chipEdge = "#5A5A5A",        -- key / shoulder button outlines
    chipText = "#D8D8D8",
    buttonA = "#3E7A34",         -- controller face buttons
    buttonB = "#9B2B2B",
    buttonX = "#2F5E9E",
    buttonY = "#B08A2E",
}

Widgets.COLORS = {}
Widgets.TRANSPARENT = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }

-- palette: { role = "#RRGGBB", ... }; panelOpacity: the panel's alpha (the game shows through). A
-- colour that is not "#RRGGBB" keeps the default (and is logged).
function Widgets.ApplyTheme(palette, panelOpacity)
    for role, hex in pairs(DEFAULT_PALETTE) do
        local themed = palette and palette[role]
        local color = themed and Widgets.Hex(themed)
        if themed and not color then Log.Info("theme: " .. role .. " = " .. tostring(themed) .. " is not #RRGGBB; using the default") end
        Widgets.COLORS[role] = color or Widgets.Hex(hex)
    end
    Widgets.COLORS.panel.A = panelOpacity or 0.96
end

Widgets.ApplyTheme(nil)

-- Every widget gets a name of its own: the build number and a running count make it unique, so no
-- two widgets can ever share one (constructing over an existing name of another class is a fatal
-- engine error). The name passed in only makes the widget recognisable in Live View.
local buildNumber, constructed = 0, 0
function Widgets.StartBuild()
    buildNumber = buildNumber + 1
    constructed = 0
end

function Widgets.Construct(classPath, outer, name)
    local widgetClass = Unreal.Static(classPath)
    if not Unreal.IsValid(widgetClass) then error("missing class " .. classPath) end
    constructed = constructed + 1
    local widget = StaticConstructObject(widgetClass, outer, FName(App.name .. buildNumber .. "_" .. constructed .. "_" .. name))
    if not Unreal.IsValid(widget) then error("could not construct " .. classPath) end
    return widget
end

function Widgets.SetTextColor(textBlock, color)
    try(function() textBlock:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
end

function Widgets.SetText(textBlock, text)
    try(function() textBlock:SetText(FText(text or "")) end)
end

-- The theme's fonts, set when the menu is built: { display = UFont or nil, body = UFont or nil }.
-- Without one, text uses the engine's default font (Roboto).
Widgets.fonts = {}

-- A font spec is either { faces = { Regular = "Cinzel-SemiBold", Bold = "Cinzel-Bold" } } (.ttf
-- files in the mod's assets/fonts/; core/ui/fonts.lua builds the font) or the path of a font the
-- game has ("/Game/UI/Fonts/F_Title.F_Title").
local function findFont(role, spec)
    if type(spec) == "string" then
        local font = Unreal.FindObject(spec)
        if not font then Log.Info("menu fonts: " .. role .. " stays on the engine font (" .. spec .. " is not loaded)") end
        return font
    end
    local font, reason = Fonts.Build(role:sub(1, 1):upper() .. role:sub(2), spec.faces)
    if not font then Log.Info("menu fonts: " .. role .. " stays on the engine font (" .. tostring(reason) .. ")") end
    return font
end

-- specs: { display = spec, body = spec } (both optional), or nil for the engine font.
function Widgets.ResolveFonts(specs)
    Widgets.fonts = {}
    for role, spec in pairs(specs or {}) do Widgets.fonts[role] = findFont(role, spec) end
    Log.Info("menu fonts: display " .. (Widgets.fonts.display and "theme" or "engine")
        .. ", body " .. (Widgets.fonts.body and "theme" or "engine"))
end

-- The typeface for a weight ("Regular", "Medium", "SemiBold", "Bold"). The theme's fonts have them
-- all; the engine's Roboto only has Regular and Bold, so the others map to the nearest. (A game font
-- named by path gets the weight's name as it is; one without that typeface shows its first.)
local function typefaceFor(weight, display)
    if Widgets.fonts[display and "display" or "body"] then return weight end
    return (weight == "SemiBold" or weight == "Bold") and "Bold" or "Regular"
end

-- Changes a text's weight after it was built (the selected row's label).
function Widgets.SetWeight(textBlock, weight, display)
    try(function()
        local font = textBlock.Font
        font.TypefaceFontName = FName(typefaceFor(weight, display))
        textBlock:SetFont(font)
    end)
end

-- Roboto is much wider than the theme's condensed faces: its letter spacing is tightened so text
-- laid out for the theme still fits.
local ENGINE_FONT_SPACING = 0.4

-- style (optional): { weight = "Medium" | "SemiBold" | "Bold" (default Regular),
--                     display = true (the theme's display font instead of its body font),
--                     spacing = 120 (thousandths of an em), lineHeight = 1.15 (of the font's own),
--                     center = true, wrap = true, ellipsis = true (cut off with "..." when the
--                     space runs out) }
function Widgets.Text(tree, name, text, fontSize, color, style)
    style = style or {}
    local textBlock = Widgets.Construct("/Script/UMG.TextBlock", tree, name)
    Widgets.SetText(textBlock, text)
    try(function()
        local font = textBlock.Font
        local fontObject = style.display and Widgets.fonts.display or Widgets.fonts.body
        if fontObject then font.FontObject = fontObject end
        font.Size = fontSize
        font.TypefaceFontName = FName(typefaceFor(style.weight or "Regular", style.display))
        if style.spacing then font.LetterSpacing = math.floor(style.spacing * (fontObject and 1 or ENGINE_FONT_SPACING)) end
        textBlock:SetFont(font)
    end)
    Widgets.SetTextColor(textBlock, color)
    if style.center then try(function() textBlock:SetJustification(1) end) end   -- ETextJustify::Center
    if style.wrap then try(function() textBlock:SetAutoWrapText(true) end) end
    if style.lineHeight then try(function() textBlock.LineHeightPercentage = style.lineHeight end) end
    if style.ellipsis then
        try(function() textBlock:SetClipping(1) end)                -- EWidgetClipping::ClipToBounds
        try(function() textBlock:SetTextOverflowPolicy(1) end)      -- ETextOverflowPolicy::Ellipsis
    end
    return textBlock
end

function Widgets.Border(tree, name, color, padding)
    local border = Widgets.Construct("/Script/UMG.Border", tree, name)
    try(function() border:SetBrushColor(color) end)
    if padding then Widgets.Pad(border, padding[1], padding[2], padding[3], padding[4]) end
    return border
end

function Widgets.SetColor(border, color) try(function() border:SetBrushColor(color) end) end

function Widgets.SetColors(borders, color)
    for _, border in ipairs(borders) do Widgets.SetColor(border, color) end
end

-- Rounded corners on a border's brush (radius in slate units; nil: a pill / circle). Where the
-- engine does not take it the border stays square.
function Widgets.Round(border, radius)
    try(function()
        local brush = border.Background
        brush.DrawAs = 4                                   -- ESlateBrushDrawType::RoundedBox
        if radius then
            brush.OutlineSettings.RoundingType = 0         -- FixedRadius
            brush.OutlineSettings.CornerRadii = { X = radius, Y = radius, Z = radius, W = radius }
        else
            brush.OutlineSettings.RoundingType = 1         -- HalfHeightRadius
        end
        border:SetBrush(brush)
    end)
end

-- width / height: fixed sizes; minWidth: at least this wide.
function Widgets.SizeBox(tree, name, width, height, minWidth)
    local sizeBox = Widgets.Construct("/Script/UMG.SizeBox", tree, name)
    if width then try(function() sizeBox:SetWidthOverride(width) end) end
    if height then try(function() sizeBox:SetHeightOverride(height) end) end
    if minWidth then try(function() sizeBox:SetMinDesiredWidth(minWidth) end) end
    return sizeBox
end

function Widgets.VerticalBox(tree, name) return Widgets.Construct("/Script/UMG.VerticalBox", tree, name) end
function Widgets.HorizontalBox(tree, name) return Widgets.Construct("/Script/UMG.HorizontalBox", tree, name) end
function Widgets.Overlay(tree, name) return Widgets.Construct("/Script/UMG.Overlay", tree, name) end

-- A solid bar (a rule, an edge): a coloured border in a size box. Returns the box and the border.
function Widgets.Bar(tree, name, color, width, height)
    local box = Widgets.SizeBox(tree, name .. "Box", width, height)
    local fill = Widgets.Border(tree, name, color)
    box:SetContent(fill)
    return box, fill
end

-- Padding on a slot or a border (both have SetPadding).
function Widgets.Pad(target, left, top, right, bottom)
    try(function() target:SetPadding({ Left = left, Top = top, Right = right, Bottom = bottom }) end)
end

-- Alignment of a slot, or of a border's content (both have the setters).
function Widgets.Align(target, horizontal, vertical)
    if horizontal then try(function() target:SetHorizontalAlignment(horizontal) end) end
    if vertical then try(function() target:SetVerticalAlignment(vertical) end) end
end

function Widgets.CenterVertically(slot) Widgets.Align(slot, nil, Widgets.CENTER) end

-- A box slot that takes the space left over.
function Widgets.Fill(slot) try(function() slot:SetSize({ Value = 1.0, SizeRule = 1 }) end) end

-- Adds a child to a horizontal box, centred on the line, with space left and right of it.
function Widgets.AddCentered(box, child, left, right)
    local slot = box:AddChild(child)
    Widgets.CenterVertically(slot)
    if left or right then Widgets.Pad(slot, left or 0, 0, right or 0, 0) end
    return slot
end

-- content inside a 1-unit outline drawn as four bars (so whatever is behind shows through the
-- content, unlike a border filled with the outline colour). The content fills the outline. Returns
-- the outline and its bars.
function Widgets.Outlined(tree, name, content, color)
    local overlay = Widgets.Overlay(tree, name)
    local contentSlot = overlay:AddChild(content)
    Widgets.Align(contentSlot, Widgets.FILL, Widgets.FILL)
    Widgets.Pad(contentSlot, 1, 1, 1, 1)
    local sides = {
        { "Top", nil, 1, Widgets.FILL, Widgets.START },
        { "Bottom", nil, 1, Widgets.FILL, Widgets.END },
        { "Left", 1, nil, Widgets.START, Widgets.FILL },
        { "Right", 1, nil, Widgets.END, Widgets.FILL },
    }
    local bars = {}
    for _, side in ipairs(sides) do
        local box, fill = Widgets.Bar(tree, name .. side[1], color, side[2], side[3])
        Widgets.Align(overlay:AddChild(box), side[4], side[5])
        bars[#bars + 1] = fill
    end
    return overlay, bars
end

-- content shrunk evenly when it is wider than the space it gets (never enlarged).
function Widgets.ShrinkToFit(tree, name, content)
    local scaleBox = Widgets.Construct("/Script/UMG.ScaleBox", tree, name)
    try(function() scaleBox:SetStretch(3) end)              -- EStretch::ScaleToFitX
    try(function() scaleBox:SetStretchDirection(1) end)     -- EStretchDirection::DownOnly
    scaleBox:SetContent(content)
    return scaleBox
end

-- A small square turned 45 degrees. Returns the box and the square (to recolour).
function Widgets.Diamond(tree, name, size, color)
    local box, square = Widgets.Bar(tree, name, color, size, size)
    try(function() square:SetRenderTransformAngle(45.0) end)
    return box, square
end

-- Arrow keys are drawn as an arrow (the menu's arrow image, turned) instead of a word.
local ARROW_KEYS = { Left = { "arrowLeft", 0 }, Right = { "arrowRight", 0 }, Up = { "arrowRight", -90 }, Down = { "arrowRight", 90 } }

-- A key or shoulder button drawn as an outlined cap with its label (or arrow).
function Widgets.KeyChip(tree, name, label)
    local colors = Widgets.COLORS
    local edge = Widgets.Border(tree, name .. "Edge", colors.chipEdge, { 1, 1, 1, 1 })
    local face = Widgets.Border(tree, name .. "Face", colors.footer, { 5, 0, 5, 0 })
    Widgets.Round(edge, 3)
    Widgets.Round(face, 2)
    edge:SetContent(face)
    local arrow = ARROW_KEYS[label]
    local arrowIcon = arrow and Widgets.Icon(tree, name .. "Arrow", Widgets.images[arrow[1]], 5, 7, colors.chipText)
    if arrowIcon then
        try(function() arrowIcon:SetRenderTransformAngle(arrow[2]) end)
        Widgets.Pad(face, 6, 4, 6, 4)
        face:SetContent(arrowIcon)
    else
        face:SetContent(Widgets.Text(tree, name .. "Label", label, 9, colors.chipText))
    end
    return edge
end

-- A PNG / JPG from disk as a texture (the engine's own importer), or nil.
function Widgets.TextureFromFile(path, worldContext)
    local library = Unreal.Static("/Script/Engine.Default__KismetRenderingLibrary")
    local texture = Unreal.IsValid(library) and try(function() return library:ImportFileAsTexture2D(worldContext, path) end)
    return Unreal.IsValid(texture) and texture or nil
end

-- The menu's own images (the arrows and disc are white, tinted when drawn), PNGs in the mod folder,
-- plus any the caller adds (the theme's mark). Imported once and kept while the textures stay valid.
-- A missing image leaves its widget to a fallback.
local IMAGE_FILES = { arrowLeft = "assets/arrow-left.png", arrowRight = "assets/arrow-right.png", disc = "assets/disc.png" }
Widgets.images = {}

-- extraFiles: { key = "file in the mod folder" }, e.g. { mark = theme.mark }.
function Widgets.LoadImages(worldContext, extraFiles)
    for key, file in pairs(extraFiles or {}) do IMAGE_FILES[key] = file end
    for key, file in pairs(IMAGE_FILES) do
        if not Unreal.IsValid(Widgets.images[key]) then
            Widgets.images[key] = Widgets.TextureFromFile(Paths.InModFolder(file), worldContext)
        end
    end
end

-- A texture drawn at width x height (height defaults to width), tinted with color when given; nil
-- when there is no texture or it will not set (the caller falls back).
function Widgets.Icon(tree, name, texture, width, height, color)
    if not texture then return nil end
    local box = Widgets.SizeBox(tree, name .. "Box", width, height or width)
    local image = Widgets.Construct("/Script/UMG.Image", tree, name)
    local ok = try(function() image:SetBrushFromTexture(texture, false) return true end)
    if not ok then return nil end
    if color then try(function() image:SetColorAndOpacity(color) end) end
    box:SetContent(image)
    return box
end

local FACE_BUTTON_COLORS = { A = "buttonA", B = "buttonB", X = "buttonX", Y = "buttonY" }
local DISC_SIZE = 18

-- A controller face button (A / B / X / Y) as a coloured disc with its letter; any other label is
-- a key chip.
function Widgets.ButtonChip(tree, name, label)
    local role = FACE_BUTTON_COLORS[label]
    if not role then return Widgets.KeyChip(tree, name, label) end
    local letter = Widgets.Text(tree, name .. "Label", label, 9, Widgets.COLORS.bright, { weight = "SemiBold" })
    local disc = Widgets.Icon(tree, name .. "Disc", Widgets.images.disc, DISC_SIZE, DISC_SIZE, Widgets.COLORS[role])
    if disc then
        local overlay = Widgets.Overlay(tree, name)
        overlay:AddChild(disc)
        Widgets.Align(overlay:AddChild(letter), Widgets.CENTER, Widgets.CENTER)
        return overlay
    end
    local box = Widgets.SizeBox(tree, name .. "Box", DISC_SIZE, DISC_SIZE)
    local square = Widgets.Border(tree, name .. "Square", Widgets.COLORS[role])
    Widgets.Round(square, nil)
    Widgets.Align(square, Widgets.CENTER, Widgets.CENTER)
    square:SetContent(letter)
    box:SetContent(square)
    return box
end

function Widgets.SetVisible(widget, visible)
    try(function() widget:SetVisibility(visible and SHOWN or COLLAPSED) end)
end

return Widgets
