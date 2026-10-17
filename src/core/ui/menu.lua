-- core/ui/menu.lua
-- A menu drawn with plain UMG widgets, styled by the game's theme:
--
--   header       the mod's mark, title, a rule and the game's name; the tabs, each with how many of
--                its rows differ from vanilla
--   rows         toggles (OFF | ON), choices (‹ value ›), actions, section titles, sub-rows; a mark
--                on every row changed from vanilla, the selected row lit with an edge bar
--   description  what the selected row does
--   footer       the status line, how many settings differ from vanilla, and the buttons that do
--                something on the selected row
--
--   Keyboard: F5 / Esc open / close, Up / Down select, Left / Right change, Enter use, Q / E tabs
--   Controller (core/ui/input.lua): L3 + R3 open / close, D-pad, A use, B close, LB / RB tabs
--
-- Knows no game: the game passes in what it needs with Menu.Configure and defines the content with
-- Menu.AddTab (see game/sheet.lua). Everything runs on the game thread from Menu.Tick; while
-- the menu is closed a tick only looks at the key queue and one controller button. A refresh only
-- touches widgets whose text or colour changed.

local Unreal = require("core.unreal")
local Log = require("core.log")
local App = require("core.app")
local Paths = require("core.paths")
local Settings = require("core.settings")
local Widgets = require("core.ui.widgets")
local Input = require("core.ui.input")
local GameMenus = require("core.ui.game_menus")

local Menu = {}

local COLORS = Widgets.COLORS
local TRANSPARENT = Widgets.TRANSPARENT
local FILL, START, CENTER, END = Widgets.FILL, Widgets.START, Widgets.CENTER, Widgets.END
local try, isValid = Unreal.Try, Unreal.IsValid

-- Sizes are the design's pixels at 1080p; font sizes are points (3/4 of the design's pixels).
-- MENU_SCALE enlarges the whole menu evenly.
local MENU_SCALE = 1.1
local WIDTH = 480
local SIDE_PADDING = 22
local ROW_PADDING = 8
local SELECTION_BAR_WIDTH = 3
local CONTROL_WIDTH = 124      -- toggles and choices line up on the right
local VALUE_WIDTH = 88         -- a choice's value between its arrows
local SLIDER_WIDTH = 120
local MARK_SIZE = 24
local CORNER_LENGTH, CORNER_THICKNESS = 12, 2
local POSITION = { X = 40, Y = 40 }
local REFERENCE_HEIGHT = 1080
local REFRESH_INTERVAL = 0.25
local GAME_MENU_CHECK_INTERVAL = 0.5
local DESCRIPTION_MIN_HEIGHT = 40

local FONT_SIZE = {
    title = 16.5, subtitle = 9, tab = 10, tabCount = 7, section = 10, row = 12, subRow = 11.5,
    toggle = 8.5, arrow = 9, info = 9, descriptionTitle = 8.5, description = 10.5, footer = 9, hint = 9,
}

-- The footer's buttons for each input device. A hint with a verb is only shown when the selected
-- row has something for it: "press" (toggle a toggle, use an action), "change" (step a choice).
local HINTS = {
    keyboard = {
        { keys = { "Enter" }, verb = "press" },
        { keys = { "Left", "Right" }, verb = "change" },
        { keys = { "Up", "Down" }, label = "select" },
        { keys = { "Q", "E" }, label = "tab" },
        { keys = { "F5" }, label = "close" },
    },
    controller = {
        { keys = { "A" }, verb = "press" },
        { keys = { "D-pad" }, verb = "change" },
        { keys = { "B" }, label = "close" },
        { keys = { "LB", "RB" }, label = "tab" },
    },
}

local config = {
    controller = function() return nil end,   -- the player controller
    player = function() return nil end,       -- the player character
    isReady = function() return false end,    -- is a save loaded? (actions need one by default)
    buttonIcons = {},                         -- chip label ("A", "LB", ...) -> texture path
    theme = {},                               -- see Menu.Configure
}

-- options: { controller, player, isReady, gameMenuClasses = { "WBP_PauseMenu_C", ... },
--            buttonIcons = { A = "/Game/.../T_A.T_A", ... },
--            theme = { subtitle = "GAME NAME", mark = "assets/mark.png" (in the mod folder),
--                      palette = { role = "#RRGGBB" } (core/ui/widgets.lua), panelOpacity,
--                      fonts = { display = font, body = font } (a font is an object path or a
--                      list of name fragments, see Widgets.ResolveFonts; display: title, sections) } }
function Menu.Configure(options)
    for key, value in pairs(options) do config[key] = value end
    Input.Configure({ controller = config.controller, player = config.player })
    GameMenus.Configure(options.gameMenuClasses or {})
    if options.theme then Widgets.ApplyTheme(options.theme.palette, options.theme.panelOpacity) end
end

local tabs = {}   -- { title, items }
local view = {
    open = false,
    tabIndex = 1,
    shownTabIndex = nil,      -- the tab the widgets currently show
    selectedByTab = {},       -- tab index -> item index
    widgets = nil,            -- built on the first open
    pendingConfirm = nil,     -- the action waiting for its second Enter
    withController = false,   -- opened with L3 + R3: controller hints and input mode
    shown = {},               -- what the header, description and footer show (redrawn on change)
    nextRefreshAt = 0,
    nextGameMenuCheckAt = 0,
}

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

local function isSelectable(item)
    return item.kind == "toggle" or item.kind == "choice" or item.kind == "action"
end

local function sameValue(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
    return a == b
end

-- A settings key (string) becomes a get/set pair on App.settings that logs and saves changes, and
-- knows whether the value differs from vanilla; an accessor table ({ get, set }, e.g. from
-- Menu.Value) is used as it is.
local function accessorFor(keyOrAccessor)
    if type(keyOrAccessor) == "table" then return keyOrAccessor end
    local key = keyOrAccessor
    return {
        get = function() return App.settings[key] end,
        set = function(value)
            App.settings[key] = value
            Log.Info("menu: " .. key .. " -> " .. tostring(value))
            Settings.MarkDirty()
        end,
        isChanged = function() return not sameValue(App.settings[key], App.defaults[key]) end,
    }
end

-- A value that only lives in the menu (not saved), e.g. the selected teleport slot.
function Menu.Value(initial)
    local value = initial
    return { get = function() return value end, set = function(newValue) value = newValue end }
end

function Menu.Section(title) return { kind = "section", label = title } end

-- A line of text; textOf() is read on every refresh.
function Menu.Info(textOf) return { kind = "info", text = textOf } end

-- Every row takes, in its options: description (shown while it is selected) and sub = true (drawn
-- as a refinement of the row above).

-- options.confirm: a prompt; the action then needs a second Enter.
-- options.anytime: runs without a loaded save (by default an action needs one, and says so).
function Menu.Action(label, run, options)
    options = options or {}
    return {
        kind = "action", label = label, run = run, confirmPrompt = options.confirm, needsSave = not options.anytime,
        description = options.description, sub = options.sub == true,
    }
end

function Menu.Toggle(label, keyOrAccessor, options)
    options = options or {}
    local accessor = accessorFor(keyOrAccessor)
    return {
        kind = "toggle", label = label, get = accessor.get, set = accessor.set, isChanged = accessor.isChanged,
        description = options.description, sub = options.sub == true,
    }
end

-- options: a list of { label, value }, or a function returning one (read on every refresh, so it
-- should cache). display.slider adds a slider for the mouse (long lists); display.wrap = false stops
-- at the ends.
function Menu.Choice(label, options, keyOrAccessor, display)
    display = display or {}
    local accessor = accessorFor(keyOrAccessor)
    return {
        kind = "choice", label = label, options = options, get = accessor.get, set = accessor.set,
        isChanged = accessor.isChanged, slider = display.slider == true, wrap = display.wrap ~= false,
        description = display.description, sub = display.sub == true,
    }
end

local function optionsOf(item)
    local options = item.options
    if type(options) == "function" then options = options() end
    return options or {}
end

local function currentIndex(item, options)
    local value = item.get()
    for index, option in ipairs(options) do
        if sameValue(option.value, value) then return index end
    end
    return nil
end

local function choiceText(item)
    local options = optionsOf(item)
    local index = currentIndex(item, options)
    return index and options[index].label or "-"
end

local function isChanged(item) return item.isChanged ~= nil and item.isChanged() end

function Menu.AddTab(title, items)
    tabs[#tabs + 1] = { title = title, items = items }
    for index, item in ipairs(items) do
        if isSelectable(item) then
            view.selectedByTab[#tabs] = index
            break
        end
    end
end

-- How many settings differ from vanilla (cheats only: debug logging and the like do not count).
local function changedSettingCount()
    local count = 0
    for key, default in pairs(App.defaults) do
        if not App.notACheat[key] and not sameValue(App.settings[key], default) then count = count + 1 end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

local function selected()
    local tab = tabs[view.tabIndex]
    local index = view.selectedByTab[view.tabIndex]
    return tab and index and tab.items[index], index
end

local function moveSelection(direction)
    local tab = tabs[view.tabIndex]
    local selectable, position = {}, 1
    for index, item in ipairs(tab.items) do
        if isSelectable(item) then
            selectable[#selectable + 1] = index
            if index == view.selectedByTab[view.tabIndex] then position = #selectable end
        end
    end
    if #selectable == 0 then return end
    view.selectedByTab[view.tabIndex] = selectable[(position - 1 + direction) % #selectable + 1]
end

local function changeValue(direction)
    local item = selected()
    if not item then return end
    if item.kind == "toggle" then
        item.set(not item.get())
        App.status = item.label .. ": " .. (item.get() and "on" or "off")
    elseif item.kind == "choice" then
        local options = optionsOf(item)
        if #options == 0 then return end
        local index = (currentIndex(item, options) or 0) + direction
        if item.wrap then
            index = (index - 1) % #options + 1
        else
            index = math.max(1, math.min(#options, index))
        end
        item.set(options[index].value)
        App.status = item.label .. ": " .. options[index].label
    end
end

local function activate()
    local item = selected()
    if not item then return end
    if item.kind == "toggle" then
        changeValue(1)
        return
    end
    if item.kind ~= "action" then return end
    if item.needsSave and not config.isReady() then
        App.status = "Load a save first"
        return
    end
    if item.confirmPrompt and view.pendingConfirm ~= item then
        view.pendingConfirm = item
        App.status = item.confirmPrompt .. (view.withController and " Press A again to confirm." or " Press Enter again to confirm.")
        return
    end
    view.pendingConfirm = nil
    Log.Info("menu: " .. item.label)
    Log.Guarded("action " .. item.label, item.run)
end

local function switchTab(direction)
    if #tabs > 0 then view.tabIndex = (view.tabIndex - 1 + direction) % #tabs + 1 end
end

-- ---------------------------------------------------------------------------
-- Building the widgets
-- ---------------------------------------------------------------------------

-- A rule that takes the rest of a horizontal box, centred on the line.
local function addRule(tree, line, name, color, left, right)
    local rule = Widgets.Bar(tree, name, color, nil, 1)
    local slot = line:AddChild(rule)
    Widgets.Fill(slot)
    Widgets.CenterVertically(slot)
    Widgets.Pad(slot, left, 0, right, 0)
end

-- OFF | ON in an outline; the lit half is filled.
local function buildToggle(tree, name)
    local halves = Widgets.HorizontalBox(tree, name .. "Halves")
    local toggle = {}
    for _, half in ipairs({ "Off", "On" }) do
        local cell = Widgets.Border(tree, name .. half, TRANSPARENT, { 0, 2, 0, 2 })
        try(function() cell:SetHorizontalAlignment(CENTER) end)
        local text = Widgets.Text(tree, name .. half .. "Text", half:upper(), FONT_SIZE.toggle, COLORS.faint, { bold = true, spacing = 80 })
        cell:SetContent(text)
        Widgets.Fill(halves:AddChild(cell))
        toggle[half] = { cell = cell, text = text }
    end
    local outline, bars = Widgets.Outlined(tree, name .. "Outline", halves, COLORS.hairline)
    toggle.bars = bars
    local box = Widgets.SizeBox(tree, name .. "Box", CONTROL_WIDTH)
    box:SetContent(outline)
    return box, toggle
end

-- ‹ value ›
local function buildChoice(tree, name)
    local line = Widgets.HorizontalBox(tree, name .. "Choice")
    local left = Widgets.Text(tree, name .. "Left", "‹", FONT_SIZE.arrow, COLORS.faint)
    local valueBox = Widgets.SizeBox(tree, name .. "ValueBox")
    try(function() valueBox:SetMinDesiredWidth(VALUE_WIDTH) end)
    local value = Widgets.Text(tree, name .. "Value", "", FONT_SIZE.row, COLORS.title, { center = true })
    valueBox:SetContent(value)
    local right = Widgets.Text(tree, name .. "Right", "›", FONT_SIZE.arrow, COLORS.faint)
    for _, part in ipairs({ left, valueBox, right }) do
        local slot = line:AddChild(part)
        Widgets.CenterVertically(slot)
        Widgets.Pad(slot, part == valueBox and 8 or 0, 0, part == valueBox and 8 or 0, 0)
    end
    local box = Widgets.SizeBox(tree, name .. "ChoiceBox")
    try(function() box:SetMinDesiredWidth(CONTROL_WIDTH) end)
    box:SetContent(line)
    return box, { left = left, value = value, right = right }
end

-- The bend of a sub-row: a short corner drawn with two bars, reaching up to the row above.
local function buildConnector(tree, name)
    local box = Widgets.SizeBox(tree, name .. "Box", 10, 10)
    local overlay = Widgets.Overlay(tree, name)
    local down = Widgets.Bar(tree, name .. "Down", COLORS.hairline, 1, nil)
    Widgets.Align(overlay:AddChild(down), START, FILL)
    local across = Widgets.Bar(tree, name .. "Across", COLORS.hairline, nil, 1)
    Widgets.Align(overlay:AddChild(across), FILL, END)
    box:SetContent(overlay)
    try(function() box:SetRenderTranslation({ X = 0.0, Y = -4.0 }) end)
    return box
end

local function buildRow(tree, page, name, item)
    local row = { shown = {} }
    row.border = Widgets.Border(tree, name .. "Row", TRANSPARENT)
    local line = Widgets.HorizontalBox(tree, name .. "Line")
    row.border:SetContent(line)

    local barBox
    barBox, row.bar = Widgets.Bar(tree, name .. "Bar", TRANSPARENT, SELECTION_BAR_WIDTH, nil)
    line:AddChild(barBox)

    local content = Widgets.HorizontalBox(tree, name .. "Content")
    local contentSlot = line:AddChild(content)
    Widgets.Fill(contentSlot)
    Widgets.Pad(contentSlot, SIDE_PADDING - SELECTION_BAR_WIDTH, ROW_PADDING, SIDE_PADDING, ROW_PADDING)

    local function add(widget, left, right)
        local slot = content:AddChild(widget)
        Widgets.CenterVertically(slot)
        Widgets.Pad(slot, left or 0, 0, right or 0, 0)
        return slot
    end

    local markBox
    markBox, row.marker = Widgets.Diamond(tree, name .. "Changed", 5, TRANSPARENT)
    add(markBox, 0, item.sub and 8 or 9)
    if item.sub then add(buildConnector(tree, name .. "Connector"), 0, 8) end

    row.label = Widgets.Text(tree, name .. "Label", item.label, item.sub and FONT_SIZE.subRow or FONT_SIZE.row, COLORS.label)
    Widgets.Fill(add(row.label, 0, 12))

    if item.kind == "choice" and item.slider then
        local options = optionsOf(item)
        local maximum = math.max(#options, 2)
        local box, slider = Widgets.Slider(tree, name .. "Slider", 1, maximum, currentIndex(item, options) or 1, SLIDER_WIDTH)
        add(box, 0, 12)
        row.slider, row.sliderMaximum = slider, maximum
    end

    if item.kind == "toggle" then
        local box
        box, row.toggle = buildToggle(tree, name .. "Toggle")
        add(box)
    elseif item.kind == "choice" then
        local box
        box, row.choice = buildChoice(tree, name)
        add(box)
    else
        row.value = Widgets.Text(tree, name .. "Value", "", FONT_SIZE.row, COLORS.faint, { bold = true })
        add(row.value)
    end

    page:AddChild(row.border)
    return row
end

local function buildSection(tree, page, name, title, isFirst)
    local line = Widgets.HorizontalBox(tree, name)
    local text = Widgets.Text(tree, name .. "Title", title, FONT_SIZE.section, COLORS.accent,
        { bold = true, spacing = 120, display = true })
    Widgets.CenterVertically(line:AddChild(text))
    addRule(tree, line, name .. "Rule", COLORS.edge, 12, 0)
    Widgets.Pad(page:AddChild(line), SIDE_PADDING, isFirst and 4 or 16, SIDE_PADDING, 6)
end

local function buildPage(tree, column, tabIndex, tab)
    local page = Widgets.VerticalBox(tree, "Page" .. tabIndex)
    local rows = {}
    for index, item in ipairs(tab.items) do
        local name = "Tab" .. tabIndex .. "Item" .. index
        if item.kind == "section" then
            buildSection(tree, page, name, item.label, index == 1)
        elseif item.kind == "info" then
            local text = Widgets.Text(tree, name, "", FONT_SIZE.info, COLORS.muted)
            Widgets.Pad(page:AddChild(text), SIDE_PADDING, 6, SIDE_PADDING, 2)
            rows[index] = { info = text }
        else
            rows[index] = buildRow(tree, page, name, item)
        end
    end
    Widgets.Pad(column:AddChild(page), 0, 12, 0, 12)
    Widgets.SetVisible(page, false)
    return { box = page, rows = rows }
end

-- The theme's mark (a PNG in the mod folder), or a small diamond in the accent colour.
local function buildMark(tree, controller)
    local markFile = config.theme.mark
    local texture = markFile and Widgets.TextureFromFile(Paths.InModFolder(markFile), controller)
    local icon = texture and Widgets.Icon(tree, "Mark", texture, MARK_SIZE)
    Log.Limited("menu mark", 1, "menu mark: " .. (icon and markFile or "diamond (no image loaded)"))
    if icon then return icon end
    return (Widgets.Diamond(tree, "MarkDiamond", 8, COLORS.accent))
end

-- Mark, title, rule, game name; below it the tabs, centred, with dots between them.
local function buildHeader(tree, column, controller)
    local header = Widgets.VerticalBox(tree, "Header")
    local titleLine = Widgets.HorizontalBox(tree, "TitleLine")
    local markSlot = titleLine:AddChild(buildMark(tree, controller))
    Widgets.CenterVertically(markSlot)
    Widgets.Pad(markSlot, 0, 0, 10, 0)
    local title = Widgets.Text(tree, "Title", App.menuTitle, FONT_SIZE.title, COLORS.title,
        { bold = true, spacing = 80, display = true })
    Widgets.CenterVertically(titleLine:AddChild(title))
    addRule(tree, titleLine, "TitleRule", COLORS.hairline, 12, config.theme.subtitle and 12 or 0)
    if config.theme.subtitle then
        local subtitle = Widgets.Text(tree, "Subtitle", config.theme.subtitle, FONT_SIZE.subtitle, COLORS.muted, { spacing = 140 })
        Widgets.CenterVertically(titleLine:AddChild(subtitle))
    end
    header:AddChild(titleLine)

    local tabLine = Widgets.HorizontalBox(tree, "Tabs")
    local tabWidgets = {}
    for index, tab in ipairs(tabs) do
        if index > 1 then
            local dot = Widgets.Text(tree, "TabDot" .. index, "·", FONT_SIZE.tab, COLORS.edge, { bold = true })
            local dotSlot = tabLine:AddChild(dot)
            Widgets.CenterVertically(dotSlot)
            Widgets.Pad(dotSlot, 10, 0, 10, 0)
        end
        local label = Widgets.Text(tree, "Tab" .. index, tab.title:upper(), FONT_SIZE.tab, COLORS.dim, { bold = true, spacing = 120 })
        Widgets.CenterVertically(tabLine:AddChild(label))
        local count = Widgets.Text(tree, "TabCount" .. index, "", FONT_SIZE.tabCount, COLORS.highlight, { bold = true })
        local countSlot = tabLine:AddChild(count)
        Widgets.Align(countSlot, nil, START)
        Widgets.Pad(countSlot, 2, 0, 0, 0)
        tabWidgets[index] = { label = label, count = count }
    end
    local tabSlot = header:AddChild(tabLine)
    Widgets.Align(tabSlot, CENTER, nil)
    Widgets.Pad(tabSlot, 0, 14, 0, 0)

    Widgets.Pad(column:AddChild(header), SIDE_PADDING, 18, SIDE_PADDING, 14)
    column:AddChild((Widgets.Bar(tree, "HeaderLine", COLORS.edge, nil, 1)))
    return tabWidgets
end

local function buildDescription(tree, column)
    local panel = Widgets.Border(tree, "Description", COLORS.descriptionPanel, { 14, 12, 14, 12 })
    local stack = Widgets.VerticalBox(tree, "DescriptionStack")
    panel:SetContent(stack)
    local titleLine = Widgets.HorizontalBox(tree, "DescriptionTitleLine")
    local diamondSlot = titleLine:AddChild((Widgets.Diamond(tree, "DescriptionDiamond", 5, COLORS.highlight)))
    Widgets.CenterVertically(diamondSlot)
    Widgets.Pad(diamondSlot, 0, 0, 8, 0)
    local title = Widgets.Text(tree, "DescriptionTitle", "", FONT_SIZE.descriptionTitle, COLORS.highlight, { bold = true, spacing = 160 })
    Widgets.CenterVertically(titleLine:AddChild(title))
    stack:AddChild(titleLine)
    local bodyBox = Widgets.SizeBox(tree, "DescriptionBodyBox")
    try(function() bodyBox:SetMinDesiredHeight(DESCRIPTION_MIN_HEIGHT) end)
    local body = Widgets.Text(tree, "DescriptionBody", "", FONT_SIZE.description, COLORS.label, { wrap = true })
    bodyBox:SetContent(body)
    Widgets.Pad(stack:AddChild(bodyBox), 0, 6, 0, 0)

    local outline = Widgets.Outlined(tree, "DescriptionOutline", panel, COLORS.descriptionEdge)
    Widgets.Pad(column:AddChild(outline), SIDE_PADDING, 0, SIDE_PADDING, 14)
    return { box = outline, title = title, body = body }
end

-- Chips (or the game's own button images) and a label; the group hides as one.
local function buildHint(tree, row, name, hint)
    local group = Widgets.HorizontalBox(tree, name)
    for index, key in ipairs(hint.keys) do
        local iconPath = config.buttonIcons[key]
        local texture = iconPath and Unreal.Static(iconPath)
        local keyWidget = Unreal.IsValid(texture) and Widgets.Icon(tree, name .. "Icon" .. index, texture, 16)
            or Widgets.ButtonChip(tree, name .. "Key" .. index, key)
        local slot = group:AddChild(keyWidget)
        Widgets.CenterVertically(slot)
        Widgets.Pad(slot, 0, 0, 4, 0)
    end
    local label = Widgets.Text(tree, name .. "Label", hint.label or "", FONT_SIZE.hint, COLORS.muted)
    Widgets.CenterVertically(group:AddChild(label))
    local groupSlot = row:AddChild(group)
    Widgets.CenterVertically(groupSlot)
    Widgets.Pad(groupSlot, 10, 0, 0, 0)
    return { group = group, label = label, verb = hint.verb }
end

local function buildHintRow(tree, line, device)
    local row = Widgets.HorizontalBox(tree, "Hints_" .. device)
    local hints = {}
    for index, hint in ipairs(HINTS[device]) do hints[index] = buildHint(tree, row, "Hint_" .. device .. index, hint) end
    Widgets.CenterVertically(line:AddChild(row))
    Widgets.SetVisible(row, false)
    return { box = row, hints = hints }
end

-- Status · N changed on the left, the buttons on the right.
local function buildFooter(tree, column)
    column:AddChild((Widgets.Bar(tree, "FooterLine", COLORS.edge, nil, 1)))
    local footer = Widgets.Border(tree, "Footer", COLORS.footer, { SIDE_PADDING, 10, SIDE_PADDING, 10 })
    local line = Widgets.HorizontalBox(tree, "FooterRow")
    footer:SetContent(line)
    local statusLine = Widgets.HorizontalBox(tree, "StatusLine")
    local status = Widgets.Text(tree, "Status", "", FONT_SIZE.footer, COLORS.highlight)
    local separator = Widgets.Text(tree, "StatusSeparator", "·", FONT_SIZE.footer, COLORS.edge, { bold = true })
    local count = Widgets.Text(tree, "ChangedCount", "", FONT_SIZE.footer, COLORS.muted)
    Widgets.CenterVertically(statusLine:AddChild(status))
    local separatorSlot = statusLine:AddChild(separator)
    Widgets.CenterVertically(separatorSlot)
    Widgets.Pad(separatorSlot, 8, 0, 8, 0)
    Widgets.CenterVertically(statusLine:AddChild(count))
    local statusSlot = line:AddChild(statusLine)
    Widgets.Fill(statusSlot)
    Widgets.CenterVertically(statusSlot)
    local hintRows = { keyboard = buildHintRow(tree, line, "keyboard"), controller = buildHintRow(tree, line, "controller") }
    column:AddChild(footer)
    return { status = status, separator = separator, count = count, hintRows = hintRows }
end

-- Short brass ticks over the frame's corners.
local function buildCorners(tree, frame)
    local corners = { { START, START }, { END, START }, { START, END }, { END, END } }
    for index, corner in ipairs(corners) do
        local across = Widgets.Bar(tree, "CornerAcross" .. index, COLORS.corner, CORNER_LENGTH, CORNER_THICKNESS)
        Widgets.Align(frame:AddChild(across), corner[1], corner[2])
        local down = Widgets.Bar(tree, "CornerDown" .. index, COLORS.corner, CORNER_THICKNESS, CORNER_LENGTH)
        Widgets.Align(frame:AddChild(down), corner[1], corner[2])
    end
end

local function build(controller)
    Widgets.StartBuild()
    local widgetLibrary = Unreal.WidgetLibrary()
    local root = try(function()
        return widgetLibrary:Create(controller, Unreal.Static("/Script/UMG.UserWidget"), controller)
    end)
    if not isValid(root) then root = Widgets.Construct("/Script/UMG.UserWidget", controller, "Root") end
    local tree = Widgets.Construct("/Script/UMG.WidgetTree", root, "Tree")
    root.WidgetTree = tree
    local canvas = Widgets.Construct("/Script/UMG.CanvasPanel", tree, "Canvas")
    tree.RootWidget = canvas
    Widgets.ResolveFonts(config.theme.fonts)

    local panel = Widgets.Border(tree, "Panel", COLORS.panel)
    local widthBox = Widgets.SizeBox(tree, "Width")
    try(function() widthBox:SetMinDesiredWidth(WIDTH) end)
    try(function() widthBox:SetMaxDesiredWidth(WIDTH) end)
    panel:SetContent(widthBox)
    local column = Widgets.VerticalBox(tree, "Column")
    widthBox:SetContent(column)

    local frame = Widgets.Outlined(tree, "Frame", panel, COLORS.edge)
    buildCorners(tree, frame)
    local frameSlot = canvas:AddChild(frame)
    try(function() frameSlot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } }) end)
    try(function() frameSlot:SetAutoSize(true) end)

    local tabWidgets = buildHeader(tree, column, controller)
    local pages = {}
    for index, tab in ipairs(tabs) do pages[index] = buildPage(tree, column, index, tab) end
    local description = buildDescription(tree, column)
    local footer = buildFooter(tree, column)

    try(function() root:AddToViewport(1000) end)
    view.widgets = {
        root = root, frame = frame, frameSlot = frameSlot, tabs = tabWidgets, pages = pages,
        description = description, footer = footer,
    }
    view.shownTabIndex = nil
    view.shown = {}
end

-- The menu is laid out for 1080p and scaled to the viewport (UMG's own DPI scale divided out).
local function applyScale(controller)
    local layout = Unreal.WidgetLayoutLibrary()
    local height = Unreal.TryNumber(function() return layout:GetViewportSize(controller).Y end)
    local dpiScale = Unreal.TryNumber(function() return layout:GetViewportScale(controller) end)
    local scale = MENU_SCALE
    if height and height > 0 and dpiScale and dpiScale > 0 then scale = MENU_SCALE * (height / REFERENCE_HEIGHT) / dpiScale end
    local widgets = view.widgets
    try(function() widgets.frame:SetRenderTransformPivot({ X = 0.0, Y = 0.0 }) end)
    try(function() widgets.frame:SetRenderScale({ X = scale, Y = scale }) end)
    try(function() widgets.frameSlot:SetPosition({ X = POSITION.X * scale, Y = POSITION.Y * scale }) end)
end

-- ---------------------------------------------------------------------------
-- Drawing (only what changed)
-- ---------------------------------------------------------------------------

-- Calls apply(value) when value differs from what state[key] last had.
local function update(state, key, value, apply)
    if state[key] == value then return end
    state[key] = value
    apply(value)
end

local function setText(state, key, widget, text)
    update(state, key, text, function() Widgets.SetText(widget, text) end)
end

local function setTextColor(state, key, widget, color)
    update(state, key, color, function() Widgets.SetTextColor(widget, color) end)
end

local function showTab()
    local widgets = view.widgets
    if view.shownTabIndex == view.tabIndex then return end
    if view.shownTabIndex then
        Widgets.SetVisible(widgets.pages[view.shownTabIndex].box, false)
        Widgets.SetTextColor(widgets.tabs[view.shownTabIndex].label, COLORS.dim)
    end
    Widgets.SetVisible(widgets.pages[view.tabIndex].box, true)
    Widgets.SetTextColor(widgets.tabs[view.tabIndex].label, COLORS.accent)
    view.shownTabIndex = view.tabIndex
end

local function drawToggle(row, item)
    local on, toggle, shown = item.get() == true, row.toggle, row.shown
    update(shown, "on", on, function()
        Widgets.SetColors(toggle.bars, on and COLORS.accent or COLORS.hairline)
        Widgets.SetColor(toggle.On.cell, on and COLORS.accent or TRANSPARENT)
        Widgets.SetTextColor(toggle.On.text, on and COLORS.bright or COLORS.faint)
        Widgets.SetColor(toggle.Off.cell, on and TRANSPARENT or COLORS.toggleOff)
        Widgets.SetTextColor(toggle.Off.text, on and COLORS.faint or COLORS.title)
    end)
end

local function drawChoice(row, item)
    local choice, shown = row.choice, row.shown
    setText(shown, "value", choice.value, choiceText(item))
    -- a setting at its vanilla value reads quieter than a changed one
    local quiet = item.isChanged ~= nil and not item.isChanged()
    setTextColor(shown, "valueColor", choice.value, quiet and COLORS.muted or COLORS.title)
    if row.slider then
        local options = optionsOf(item)
        local maximum = math.max(#options, 2)
        if maximum ~= row.sliderMaximum then
            try(function() row.slider:SetMaxValue(maximum) end)
            row.sliderMaximum = maximum
        end
        local index = currentIndex(item, options) or 1
        if index ~= row.sliderIndex then
            try(function() row.slider:SetValue(index) end)
            row.sliderIndex = index
        end
    end
end

local function drawAction(row, item, isSelected)
    local pending = view.pendingConfirm == item
    local text = pending and (view.withController and "A again" or "Enter again") or "›"
    setText(row.shown, "value", row.value, text)
    local color = pending and COLORS.accent or (isSelected and COLORS.highlight or COLORS.faint)
    setTextColor(row.shown, "valueColor", row.value, color)
end

local function drawRow(row, item, isSelected)
    local shown = row.shown
    update(shown, "selected", isSelected, function()
        Widgets.SetColor(row.border, isSelected and COLORS.rowSelected or TRANSPARENT)
        Widgets.SetColor(row.bar, isSelected and COLORS.selectionBar or TRANSPARENT)
        Widgets.SetTextColor(row.label, isSelected and COLORS.bright or (item.sub and COLORS.muted or COLORS.label))
    end)
    local changed = isChanged(item)
    update(shown, "changed", changed, function() Widgets.SetColor(row.marker, changed and COLORS.accent or TRANSPARENT) end)
    if row.toggle then
        drawToggle(row, item)
    elseif row.choice then
        drawChoice(row, item)
    else
        drawAction(row, item, isSelected)
    end
end

local function drawTabCounts()
    local shown = view.shown
    for tabIndex, tab in ipairs(tabs) do
        local count = 0
        for _, item in ipairs(tab.items) do
            if isChanged(item) then count = count + 1 end
        end
        setText(shown, "tabCount" .. tabIndex, view.widgets.tabs[tabIndex].count, count > 0 and tostring(count) or "")
    end
end

local function drawDescription(item)
    local description, shown = view.widgets.description, view.shown
    update(shown, "descriptionVisible", item ~= nil, function(visible) Widgets.SetVisible(description.box, visible) end)
    if not item then return end
    setText(shown, "descriptionTitle", description.title, item.label:upper())
    setText(shown, "descriptionBody", description.body, item.description or "")
end

-- What the press button does on this row ("turn on", "use", ...); nil when nothing.
local function pressVerb(item)
    if not item then return nil end
    if item.kind == "toggle" then return item.get() and "turn off" or "turn on" end
    if item.kind == "action" then return view.pendingConfirm == item and "confirm" or "use" end
    return nil
end

local function drawFooter(item)
    local footer, shown = view.widgets.footer, view.shown
    setText(shown, "status", footer.status, App.status)
    update(shown, "separator", App.status ~= "", function(visible) Widgets.SetVisible(footer.separator, visible) end)
    local changedCount = changedSettingCount()
    setText(shown, "changedCount", footer.count, changedCount == 0 and "all vanilla" or (changedCount .. " changed"))

    local device = view.withController and "controller" or "keyboard"
    local verbs = { press = pressVerb(item), change = item and item.kind == "choice" and "change" or nil }
    for index, hint in ipairs(footer.hintRows[device].hints) do
        if hint.verb then
            local text = verbs[hint.verb]
            local key = device .. "Hint" .. index
            update(shown, key .. "Visible", text ~= nil, function(visible) Widgets.SetVisible(hint.group, visible) end)
            if text then setText(shown, key .. "Text", hint.label, text) end
        end
    end
end

local function refresh()
    local widgets = view.widgets
    if not widgets then return end
    showTab()
    local tab, page = tabs[view.tabIndex], widgets.pages[view.tabIndex]
    local selectedItem, selectedIndex = selected()
    for index, item in ipairs(tab.items) do
        local row = page.rows[index]
        if row and row.info then
            local text = item.text()
            if text ~= row.shownText then
                Widgets.SetText(row.info, text)
                row.shownText = text
            end
        elseif row then
            drawRow(row, item, index == selectedIndex)
        end
    end
    drawTabCounts()
    drawDescription(selectedItem)
    drawFooter(selectedItem)
end

-- A slider moved with the mouse picks that option. Returns true when something changed.
local function readSliders()
    local tab, page = tabs[view.tabIndex], view.widgets.pages[view.tabIndex]
    local changed = false
    for index, item in ipairs(tab.items) do
        local row = page.rows[index]
        local raw = row and row.slider and Widgets.SliderValue(row.slider)
        local optionIndex = raw and math.floor(raw + 0.5)
        if optionIndex and optionIndex ~= row.sliderIndex then
            local option = optionsOf(item)[optionIndex]
            if option then
                item.set(option.value)
                row.sliderIndex = optionIndex
                view.selectedByTab[view.tabIndex] = index
                changed = true
            end
        end
    end
    return changed
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

-- withController: opened with L3 + R3 (see Input.BlockGame for why that changes the input mode).
local function open(withController)
    local controller = config.controller()
    if not controller then
        Log.Info("menu: no player controller yet")
        return
    end
    local gameMenu, className = GameMenus.FindOpen()
    if gameMenu or GameMenus.IsGamePaused(controller) then
        Log.Info("menu not opened: a game menu is open (" .. tostring(className or "game paused") .. ")")
        return
    end
    if not (view.widgets and isValid(view.widgets.root)) then
        view.widgets = nil
        Log.Guarded("build menu", build, controller)
        if not view.widgets then return end
    end
    view.withController = withController == true
    local hintRows = view.widgets.footer.hintRows
    Widgets.SetVisible(view.widgets.root, true)
    Widgets.SetVisible(hintRows.keyboard.box, not view.withController)
    Widgets.SetVisible(hintRows.controller.box, view.withController)
    applyScale(controller)
    Input.BlockGame(view.withController)
    view.open = true
    view.pendingConfirm = nil
    view.nextGameMenuCheckAt = os.clock() + GAME_MENU_CHECK_INTERVAL
    refresh()
end

-- handOverTo: a game menu that opened on top of ours (it gets the cursor).
local function close(handOverTo)
    if not view.open then return end
    view.open = false
    view.pendingConfirm = nil
    if view.widgets and isValid(view.widgets.root) then Widgets.SetVisible(view.widgets.root, false) end
    Input.UnblockGame(handOverTo)
end

local COMMANDS = {
    up = function() moveSelection(-1) end,
    down = function() moveSelection(1) end,
    left = function() changeValue(-1) end,
    right = function() changeValue(1) end,
    enter = activate,
    previousTab = function() switchTab(-1) end,
    nextTab = function() switchTab(1) end,
    close = function() close() end,
}

local function handleCommand(command)
    if command == "toggle" or command == "toggleWithController" then
        if view.open then close() else open(command == "toggleWithController") end
        return
    end
    if not view.open then return end
    if command ~= "enter" then view.pendingConfirm = nil end
    COMMANDS[command]()
    if view.open then refresh() end
end

function Menu.BindKeys()
    Input.Bind(Key.F5, "toggle")
    Input.Bind(Key.ESCAPE, "close")
    Input.Bind(Key.UP_ARROW, "up")
    Input.Bind(Key.DOWN_ARROW, "down")
    Input.Bind(Key.LEFT_ARROW, "left")
    Input.Bind(Key.RIGHT_ARROW, "right")
    Input.Bind(Key.RETURN, "enter")
    Input.Bind(Key.Q, "previousTab")
    Input.Bind(Key.E, "nextTab")
end

function Menu.Tick()
    Input.PollController(view.open)
    for _, command in ipairs(Input.TakePending()) do
        Log.Guarded("menu command " .. command, handleCommand, command)
    end
    if not view.open then return end
    -- the widgets die with the world (map change): the next open builds new ones
    if not (view.widgets and isValid(view.widgets.root)) then
        view.open, view.widgets = false, nil
        Input.Forget()
        return
    end
    if os.clock() >= view.nextGameMenuCheckAt then
        view.nextGameMenuCheckAt = os.clock() + GAME_MENU_CHECK_INTERVAL
        local gameMenu = GameMenus.FindOpenKnown()
        if gameMenu or GameMenus.IsGamePaused(config.controller()) then
            close(gameMenu)
            return
        end
    end
    if readSliders() or App.status ~= view.shown.status or os.clock() >= view.nextRefreshAt then
        view.nextRefreshAt = os.clock() + REFRESH_INTERVAL
        refresh()
    end
end

return Menu
