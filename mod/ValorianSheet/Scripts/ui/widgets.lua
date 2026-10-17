-- ValorianSheet / ui/widgets.lua
-- Building plain UMG widgets from Lua (StaticConstructObject), and the menu's colours.

local Unreal = require("lib.unreal")

local Widgets = {}

local try = Unreal.Try

-- ESlateVisibility
Widgets.SHOWN = 4        -- SelfHitTestInvisible: drawn, children (sliders) still take the mouse
Widgets.COLLAPSED = 1

Widgets.COLORS = {
    frame = { R = 0.42, G = 0.40, B = 0.37, A = 0.95 },
    background = { R = 0.012, G = 0.012, B = 0.014, A = 0.93 },
    title = { R = 0.92, G = 0.90, B = 0.86, A = 1.0 },
    accent = { R = 0.78, G = 0.04, B = 0.05, A = 1.0 },
    label = { R = 0.66, G = 0.66, B = 0.64, A = 1.0 },
    value = { R = 0.90, G = 0.90, B = 0.88, A = 1.0 },
    muted = { R = 0.45, G = 0.45, B = 0.43, A = 1.0 },
    status = { R = 0.80, G = 0.78, B = 0.70, A = 1.0 },
    rowSelected = { R = 0.16, G = 0.0, B = 0.0016, A = 0.85 },
    rowIdle = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 },
    sliderTrack = { R = 0.18, G = 0.18, B = 0.18, A = 1.0 },
}

-- Widget names must be unique per outer; every build gets its own prefix.
local buildNumber = 0
function Widgets.StartBuild() buildNumber = buildNumber + 1 end
local function uniqueName(name) return "ValorianSheet" .. buildNumber .. "_" .. name end

function Widgets.Construct(classPath, outer, name)
    local widgetClass = StaticFindObject(classPath)
    if not Unreal.IsValid(widgetClass) then error("missing class " .. classPath) end
    local widget = StaticConstructObject(widgetClass, outer, FName(uniqueName(name)))
    if not Unreal.IsValid(widget) then error("could not construct " .. classPath) end
    return widget
end

function Widgets.SetTextColor(textBlock, color)
    try(function() textBlock:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
end

function Widgets.SetText(textBlock, text)
    try(function() textBlock:SetText(FText(text or "")) end)
end

function Widgets.Text(tree, name, text, fontSize, color)
    local textBlock = Widgets.Construct("/Script/UMG.TextBlock", tree, name)
    Widgets.SetText(textBlock, text)
    try(function()
        textBlock.Font.Size = fontSize
        textBlock:SetFont(textBlock.Font)
    end)
    Widgets.SetTextColor(textBlock, color)
    try(function() textBlock:SetShadowColorAndOpacity({ SpecifiedColor = { R = 0, G = 0, B = 0, A = 0.85 }, ColorUseRule = 0 }) end)
    try(function() textBlock:SetShadowOffset({ X = 1.0, Y = 1.0 }) end)
    return textBlock
end

function Widgets.Border(tree, name, color, padding)
    local border = Widgets.Construct("/Script/UMG.Border", tree, name)
    try(function() border:SetBrushColor(color) end)
    if padding then Widgets.Pad(border, padding[1], padding[2], padding[3], padding[4]) end
    return border
end

function Widgets.SizeBox(tree, name, width, height)
    local sizeBox = Widgets.Construct("/Script/UMG.SizeBox", tree, name)
    if width then try(function() sizeBox:SetWidthOverride(width) end) end
    if height then try(function() sizeBox:SetHeightOverride(height) end) end
    return sizeBox
end

function Widgets.VerticalBox(tree, name) return Widgets.Construct("/Script/UMG.VerticalBox", tree, name) end
function Widgets.HorizontalBox(tree, name) return Widgets.Construct("/Script/UMG.HorizontalBox", tree, name) end

-- Padding on a slot or a border (both have SetPadding).
function Widgets.Pad(target, left, top, right, bottom)
    try(function() target:SetPadding({ Left = left, Top = top, Right = right, Bottom = bottom }) end)
end

function Widgets.Slider(tree, name, minimum, maximum, step, value, width)
    local box = Widgets.SizeBox(tree, name .. "Box", width, 18.0)
    local slider = Widgets.Construct("/Script/UMG.Slider", tree, name)
    try(function() slider:SetMinValue(minimum) end)
    try(function() slider:SetMaxValue(maximum) end)
    try(function() slider:SetStepSize(step) end)
    try(function() slider.MouseUsesStep = true end)
    try(function() slider.IsFocusable = false end)
    try(function() slider:SetSliderBarColor(Widgets.COLORS.sliderTrack) end)
    try(function() slider:SetSliderHandleColor(Widgets.COLORS.accent) end)
    try(function() slider:SetValue(value) end)
    box:SetContent(slider)
    return box, slider
end

function Widgets.SliderValue(slider)
    local value = try(function() return slider.Value end)
    if type(value) == "number" then return value end
    value = try(function() return slider:GetValue() end)
    if type(value) == "number" then return value end
    return nil
end

function Widgets.SetVisible(widget, visible)
    try(function() widget:SetVisibility(visible and Widgets.SHOWN or Widgets.COLLAPSED) end)
end

return Widgets
