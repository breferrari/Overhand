-- core/ui/menu.lua
-- A menu drawn with plain UMG widgets, styled by the game's theme:
--
--   header       the mod's mark, title, a rule and the game's name; the tabs, each with how many of
--                its rows differ from vanilla
--   rows         toggles (OFF | ON), choices (◂ value ▸), lists (a choice that opens a dropdown),
--                actions, section titles, sub-rows; a mark on every row changed from vanilla, the
--                selected row lit with an edge bar
--   description  what the selected row does
--   footer       the status line, how many cheats are active, and the buttons that do something on
--                the selected row
--
--   Keyboard: F5 / Esc open / close, Up / Down select, Left / Right change, Enter use, Q / E tabs
--   Controller (core/ui/input.lua): L3 + R3 open / close, D-pad, A use, B close, LB / RB tabs
--   In an open dropdown: Up / Down move, Left / Right a page, Enter / A pick, Esc / B back
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
local addCentered = Widgets.AddCentered

-- Sizes are the design's pixels at 1080p; font sizes are points (3/4 of the design's pixels).
-- MENU_SCALE enlarges the whole menu evenly.
local MENU_SCALE = 1.1
local WIDTH = 480
local SIDE_PADDING = 22
local ROW_PADDING = 8
local SELECTION_BAR_WIDTH = 3
local CONTROL_WIDTH = 124      -- toggles and choices line up on the right
local VALUE_WIDTH = 88         -- a choice's value between its arrows
local LIST_VALUE_WIDTH = 200   -- a list's value (item names are long); fixed, so nothing moves
local LIST_ROWS = 7            -- options shown at once in an open dropdown
local MARK_SIZE = 26
local ARROW_WIDTH, ARROW_HEIGHT = 5, 7
local CORNER_LENGTH, CORNER_THICKNESS = 12, 2
local POSITION = { X = 40, Y = 40 }
local REFERENCE_HEIGHT = 1080
local REFRESH_INTERVAL = 0.25
local GAME_MENU_CHECK_INTERVAL = 0.5
local DESCRIPTION_MIN_HEIGHT = 40
local STATUS_MAX_WIDTH = 150   -- the footer's status line is cut off past this, the buttons keep their room

local FONT_SIZE = {
    title = 16.5, subtitle = 9, tab = 10, tabCount = 7, section = 10, row = 12, subRow = 11.5,
    toggle = 8.5, arrow = 9, info = 9, descriptionTitle = 8.5, description = 10.5, footer = 9, hint = 9,
}

-- The footer's buttons for each input device. A hint with a verb is only shown when the selected
-- row (or the open dropdown) has something for it, and says what: "press" (toggle, use, open a
-- list, pick), "change" (step a choice), "back" (close the menu, or the dropdown).
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
        { keys = { "B" }, verb = "back" },
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
--                      fonts = { display = font, body = font } (see Widgets.ResolveFonts;
--                      display: title and section headings) } }
-- Adds the themeFonts setting (the theme's fonts on or off; a row for it: Menu.Toggle with
-- { onChange = Menu.Rebuild }).
function Menu.Configure(options)
    for key, value in pairs(options) do config[key] = value end
    Input.Configure({ controller = config.controller, player = config.player })
    GameMenus.Configure(options.gameMenuClasses or {})
    if options.theme then Widgets.ApplyTheme(options.theme.palette, options.theme.panelOpacity) end
    App.AddSetting("themeFonts", true, { notACheat = true })
end

local tabs = {}   -- { title, items }
local view = {
    open = false,
    tabIndex = 1,
    shownTabIndex = nil,      -- the tab the widgets currently show
    selectedByTab = {},       -- tab index -> item index
    widgets = nil,            -- built on the first open
    pendingConfirm = nil,     -- the action waiting for its second Enter
    list = nil,               -- the open dropdown: { item, highlighted, first } (option indexes)
    withController = false,   -- opened with L3 + R3: controller hints and input mode
    shown = {},               -- what the description and footer show (redrawn on change)
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

-- A settings key (string) becomes a get/set pair on App.settings that logs and saves changes (then
-- calls onChange), and knows whether the value differs from vanilla; an accessor table ({ get, set },
-- e.g. from Menu.Value) is used as it is.
local function accessorFor(keyOrAccessor, onChange)
    if type(keyOrAccessor) == "table" then return keyOrAccessor end
    local key = keyOrAccessor
    return {
        get = function() return App.settings[key] end,
        set = function(value)
            App.settings[key] = value
            Log.Info("menu: " .. key .. " -> " .. tostring(value))
            Settings.MarkDirty()
            if onChange then onChange(value) end
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

-- Every row takes, in its options: description (shown while it is selected), sub = true (drawn as a
-- refinement of the row above) and, for a settings key, onChange (called after a change).
local function row(kind, label, options, fields)
    fields.kind, fields.label = kind, label
    fields.description, fields.sub = options.description, options.sub == true
    fields.upperLabel = label:upper()
    return fields
end

-- options.confirm: a prompt; the action then needs a second Enter (and the prompt is its
-- description unless it has one). options.anytime: runs without a loaded save (by default an action
-- needs one, and says so).
function Menu.Action(label, run, options)
    options = options or {}
    local action = row("action", label, options, { run = run, confirmPrompt = options.confirm, needsSave = not options.anytime })
    action.description = action.description or options.confirm
    return action
end

function Menu.Toggle(label, keyOrAccessor, options)
    options = options or {}
    local accessor = accessorFor(keyOrAccessor, options.onChange)
    return row("toggle", label, options, { get = accessor.get, set = accessor.set, isChanged = accessor.isChanged })
end

-- options: a list of { label, value }, or a function returning one (read on every refresh, so it
-- should cache). display.list = true: Enter / A opens a dropdown (long lists); display.wrap = false
-- stops at the ends.
function Menu.Choice(label, options, keyOrAccessor, display)
    display = display or {}
    local accessor = accessorFor(keyOrAccessor, display.onChange)
    return row("choice", label, display, {
        options = options, get = accessor.get, set = accessor.set, isChanged = accessor.isChanged,
        list = display.list == true, wrap = display.wrap ~= false,
    })
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

-- How many cheats are active: settings that differ from vanilla (debug logging and the like do not
-- count).
local function activeCheatCount()
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

local function pickOption(item, option)
    item.set(option.value)
    App.status = item.label .. ": " .. option.label
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
        pickOption(item, options[index])
    end
end

-- The dropdown opens on the current option, with it in view.
local function openList(item)
    local highlighted = currentIndex(item, optionsOf(item)) or 1
    view.list = { item = item, highlighted = highlighted, first = highlighted - math.floor(LIST_ROWS / 2) }
end

-- Moves the highlight by step (clamped to the list) and scrolls it into view.
local function moveInList(step)
    local list, count = view.list, #optionsOf(view.list.item)
    if count == 0 then return end
    list.highlighted = math.max(1, math.min(count, list.highlighted + step))
    if list.highlighted < list.first then list.first = list.highlighted end
    if list.highlighted >= list.first + LIST_ROWS then list.first = list.highlighted - LIST_ROWS + 1 end
    list.first = math.max(1, math.min(list.first, count - LIST_ROWS + 1))
end

local function activate()
    local item = selected()
    if not item then return end
    if item.kind == "toggle" then
        changeValue(1)
        return
    end
    if item.kind == "choice" and item.list then
        openList(item)
        moveInList(0)   -- clamps the first visible option to the list
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
    Widgets.Fill(addCentered(line, (Widgets.Bar(tree, name, color, nil, 1)), left, right))
end

-- OFF | ON in an outline; the lit half is filled.
local function buildToggle(tree, name)
    local halves = Widgets.HorizontalBox(tree, name .. "Halves")
    local toggle = {}
    for _, half in ipairs({ "Off", "On" }) do
        local cell = Widgets.Border(tree, name .. half, TRANSPARENT, { 0, 2, 0, 2 })
        Widgets.Align(cell, CENTER, nil)
        local text = Widgets.Text(tree, name .. half .. "Text", half:upper(), FONT_SIZE.toggle, COLORS.faint, { weight = "SemiBold", spacing = 80 })
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

-- A small triangle (the menu's arrow image, tinted), or a text arrow without the image.
local function buildArrow(tree, name, image, fallback)
    return Widgets.Icon(tree, name, Widgets.images[image], ARROW_WIDTH, ARROW_HEIGHT, COLORS.faint)
        or Widgets.Text(tree, name, fallback, FONT_SIZE.arrow, COLORS.faint)
end

-- ◂ value ▸ (a list's value has a fixed width: long names are cut off, nothing moves).
local function buildChoice(tree, name, item)
    local line = Widgets.HorizontalBox(tree, name .. "Choice")
    local valueBox = item.list and Widgets.SizeBox(tree, name .. "ValueBox", LIST_VALUE_WIDTH)
        or Widgets.SizeBox(tree, name .. "ValueBox", nil, nil, VALUE_WIDTH)
    local value = Widgets.Text(tree, name .. "Value", "", FONT_SIZE.row, COLORS.title, { center = true, ellipsis = item.list })
    valueBox:SetContent(value)
    addCentered(line, buildArrow(tree, name .. "Left", "arrowLeft", "‹"))
    addCentered(line, valueBox, 8, 8)
    addCentered(line, buildArrow(tree, name .. "Right", "arrowRight", "›"))
    local box = Widgets.SizeBox(tree, name .. "ChoiceBox", nil, nil, CONTROL_WIDTH)
    box:SetContent(line)
    return box, { value = value }
end

-- The bend of a sub-row: a short corner drawn with two bars, reaching up to the row above.
local function buildConnector(tree, name)
    local box = Widgets.SizeBox(tree, name .. "Box", 10, 10)
    local overlay = Widgets.Overlay(tree, name)
    Widgets.Align(overlay:AddChild((Widgets.Bar(tree, name .. "Down", COLORS.hairline, 1, nil))), START, FILL)
    Widgets.Align(overlay:AddChild((Widgets.Bar(tree, name .. "Across", COLORS.hairline, nil, 1))), FILL, END)
    box:SetContent(overlay)
    try(function() box:SetRenderTranslation({ X = 0.0, Y = -4.0 }) end)
    return box
end

-- A line of a dropdown or a row: an edge bar (lit when selected) and content. Returns the border,
-- the bar and the content box.
local function buildSelectableLine(tree, name, leftPadding, verticalPadding)
    local border = Widgets.Border(tree, name .. "Row", TRANSPARENT)
    local line = Widgets.HorizontalBox(tree, name .. "Line")
    border:SetContent(line)
    local barBox, bar = Widgets.Bar(tree, name .. "Bar", TRANSPARENT, SELECTION_BAR_WIDTH, nil)
    line:AddChild(barBox)
    local content = Widgets.HorizontalBox(tree, name .. "Content")
    local contentSlot = line:AddChild(content)
    Widgets.Fill(contentSlot)
    Widgets.Pad(contentSlot, leftPadding - SELECTION_BAR_WIDTH, verticalPadding, SIDE_PADDING, verticalPadding)
    return border, bar, content
end

-- The dropdown under a list row: LIST_ROWS lines in an inset panel, hidden until opened. Each line:
-- a mark on the current option and the option's name.
local function buildList(tree, page, name)
    local panel = Widgets.Border(tree, name .. "ListPanel", COLORS.descriptionPanel, { 0, 4, 0, 4 })
    local stack = Widgets.VerticalBox(tree, name .. "ListStack")
    panel:SetContent(stack)
    local lines = {}
    for index = 1, LIST_ROWS do
        local lineName = name .. "List" .. index
        local border, bar, content = buildSelectableLine(tree, lineName, 14, 3)
        local markBox, marker = Widgets.Diamond(tree, lineName .. "Current", 5, TRANSPARENT)
        addCentered(content, markBox, 0, 9)
        local text = Widgets.Text(tree, lineName .. "Text", "", FONT_SIZE.subRow, COLORS.label, { ellipsis = true })
        Widgets.Fill(addCentered(content, text))
        stack:AddChild(border)
        lines[index] = { border = border, bar = bar, marker = marker, text = text, shown = {} }
    end
    local outline = Widgets.Outlined(tree, name .. "ListOutline", panel, COLORS.descriptionEdge)
    Widgets.Pad(page:AddChild(outline), SIDE_PADDING + 14, 2, SIDE_PADDING, 6)
    Widgets.SetVisible(outline, false)
    return { box = outline, lines = lines, shown = {} }
end

local function buildRow(tree, page, name, item)
    local rowWidgets = { shown = {} }
    local border, bar, content = buildSelectableLine(tree, name, SIDE_PADDING, ROW_PADDING)
    rowWidgets.border, rowWidgets.bar = border, bar

    local markBox
    markBox, rowWidgets.marker = Widgets.Diamond(tree, name .. "Changed", 5, TRANSPARENT)
    addCentered(content, markBox, 0, item.sub and 8 or 9)
    if item.sub then addCentered(content, buildConnector(tree, name .. "Connector"), 0, 8) end

    rowWidgets.label = Widgets.Text(tree, name .. "Label", item.label, item.sub and FONT_SIZE.subRow or FONT_SIZE.row, COLORS.label)
    Widgets.Fill(addCentered(content, rowWidgets.label, 0, 12))

    if item.kind == "toggle" then
        local box
        box, rowWidgets.toggle = buildToggle(tree, name .. "Toggle")
        addCentered(content, box)
    elseif item.kind == "choice" then
        local box
        box, rowWidgets.choice = buildChoice(tree, name, item)
        addCentered(content, box)
    else
        rowWidgets.value = Widgets.Text(tree, name .. "Value", "", FONT_SIZE.row, COLORS.faint)
        addCentered(content, rowWidgets.value)
    end

    page:AddChild(border)
    if item.list then rowWidgets.list = buildList(tree, page, name) end
    return rowWidgets
end

local function buildSection(tree, page, name, title, isFirst)
    local line = Widgets.HorizontalBox(tree, name)
    addCentered(line, Widgets.Text(tree, name .. "Title", title, FONT_SIZE.section, COLORS.accent,
        { weight = "SemiBold", spacing = 120, display = true }))
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
    local icon = Widgets.Icon(tree, "Mark", texture, MARK_SIZE)
    Log.Limited("menu mark", 1, "menu mark: " .. (icon and markFile or "diamond (no image loaded)"))
    return icon or (Widgets.Diamond(tree, "MarkDiamond", 8, COLORS.accent))
end

-- Mark, title, rule, game name.
local function buildTitleLine(tree, controller)
    local line = Widgets.HorizontalBox(tree, "TitleLine")
    addCentered(line, buildMark(tree, controller), 0, 10)
    addCentered(line, Widgets.Text(tree, "Title", App.menuTitle, FONT_SIZE.title, COLORS.title,
        { weight = "Bold", spacing = 80, display = true }))
    addRule(tree, line, "TitleRule", COLORS.hairline, 12, config.theme.subtitle and 12 or 0)
    if config.theme.subtitle then
        addCentered(line, Widgets.Text(tree, "Subtitle", config.theme.subtitle, FONT_SIZE.subtitle, COLORS.muted, { spacing = 140 }))
    end
    return line
end

-- The tabs with dots between them, each with its count of changed rows; shrunk if they do not fit.
local function buildTabStrip(tree)
    local strip = Widgets.HorizontalBox(tree, "Tabs")
    local tabWidgets = {}
    for index, tab in ipairs(tabs) do
        if index > 1 then
            addCentered(strip, Widgets.Text(tree, "TabDot" .. index, "·", FONT_SIZE.tab, COLORS.edge, { weight = "SemiBold" }), 10, 10)
        end
        local label = Widgets.Text(tree, "Tab" .. index, tab.title:upper(), FONT_SIZE.tab, COLORS.dim, { weight = "SemiBold", spacing = 120 })
        addCentered(strip, label)
        local count = Widgets.Text(tree, "TabCount" .. index, "", FONT_SIZE.tabCount, COLORS.highlight, { weight = "SemiBold" })
        local countSlot = strip:AddChild(count)
        Widgets.Align(countSlot, nil, START)
        Widgets.Pad(countSlot, 2, 0, 0, 0)
        tabWidgets[index] = { label = label, count = count }
    end
    return Widgets.ShrinkToFit(tree, "TabsFit", strip), tabWidgets
end

local function buildHeader(tree, column, controller)
    local header = Widgets.VerticalBox(tree, "Header")
    header:AddChild(buildTitleLine(tree, controller))
    local strip, tabWidgets = buildTabStrip(tree)
    local stripSlot = header:AddChild(strip)
    Widgets.Align(stripSlot, CENTER, nil)
    Widgets.Pad(stripSlot, 0, 14, 0, 0)
    Widgets.Pad(column:AddChild(header), SIDE_PADDING, 18, SIDE_PADDING, 14)
    column:AddChild((Widgets.Bar(tree, "HeaderLine", COLORS.edge, nil, 1)))
    return tabWidgets
end

local function buildDescription(tree, column)
    local panel = Widgets.Border(tree, "Description", COLORS.descriptionPanel, { 14, 12, 14, 12 })
    local stack = Widgets.VerticalBox(tree, "DescriptionStack")
    panel:SetContent(stack)
    local titleLine = Widgets.HorizontalBox(tree, "DescriptionTitleLine")
    addCentered(titleLine, (Widgets.Diamond(tree, "DescriptionDiamond", 5, COLORS.highlight)), 0, 8)
    local title = Widgets.Text(tree, "DescriptionTitle", "", FONT_SIZE.descriptionTitle, COLORS.highlight, { weight = "SemiBold", spacing = 160 })
    addCentered(titleLine, title)
    stack:AddChild(titleLine)
    local bodyBox = Widgets.SizeBox(tree, "DescriptionBodyBox")
    try(function() bodyBox:SetMinDesiredHeight(DESCRIPTION_MIN_HEIGHT) end)
    local body = Widgets.Text(tree, "DescriptionBody", "", FONT_SIZE.description, COLORS.label, { wrap = true, lineHeight = 1.15 })
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
        local keyWidget = Widgets.Icon(tree, name .. "Icon" .. index, iconPath and Unreal.FindObject(iconPath), 16)
            or Widgets.ButtonChip(tree, name .. "Key" .. index, key)
        addCentered(group, keyWidget, 0, 4)
    end
    local label = Widgets.Text(tree, name .. "Label", hint.label or "", FONT_SIZE.hint, COLORS.muted)
    addCentered(group, label)
    addCentered(row, group, 10, 0)
    return { group = group, label = label, verb = hint.verb, shown = {} }
end

local function buildHintRow(tree, line, device)
    local row = Widgets.HorizontalBox(tree, "Hints_" .. device)
    local hints = {}
    for index, hint in ipairs(HINTS[device]) do hints[index] = buildHint(tree, row, "Hint_" .. device .. index, hint) end
    addCentered(line, row)
    Widgets.SetVisible(row, false)
    return { box = row, hints = hints }
end

-- Status · N active on the left (the status is cut off when long), the buttons on the right.
local function buildFooter(tree, column)
    column:AddChild((Widgets.Bar(tree, "FooterLine", COLORS.edge, nil, 1)))
    local footer = Widgets.Border(tree, "Footer", COLORS.footer, { SIDE_PADDING, 10, SIDE_PADDING, 10 })
    local line = Widgets.HorizontalBox(tree, "FooterRow")
    footer:SetContent(line)
    local statusLine = Widgets.HorizontalBox(tree, "StatusLine")
    local status = Widgets.Text(tree, "Status", "", FONT_SIZE.footer, COLORS.highlight, { ellipsis = true })
    local separator = Widgets.Text(tree, "StatusSeparator", "·", FONT_SIZE.footer, COLORS.edge)
    local count = Widgets.Text(tree, "ActiveCount", "", FONT_SIZE.footer, COLORS.muted)
    local statusBox = Widgets.SizeBox(tree, "StatusBox")
    try(function() statusBox:SetMaxDesiredWidth(STATUS_MAX_WIDTH) end)
    statusBox:SetContent(status)
    addCentered(statusLine, statusBox)
    addCentered(statusLine, separator, 8, 8)
    addCentered(statusLine, count)
    Widgets.Fill(addCentered(line, statusLine))
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
    Widgets.ResolveFonts(App.settings.themeFonts and config.theme.fonts or nil)
    Widgets.LoadImages(controller)

    local panel = Widgets.Border(tree, "Panel", COLORS.panel)
    local widthBox = Widgets.SizeBox(tree, "Width", nil, nil, WIDTH)
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

-- Records value under key; true when it differs from what was drawn last (so it needs drawing).
local function changed(state, key, value)
    if state[key] == value then return false end
    state[key] = value
    return true
end

local function setText(state, key, widget, text)
    if changed(state, key, text) then Widgets.SetText(widget, text) end
end

local function setTextColor(state, key, widget, color)
    if changed(state, key, color) then Widgets.SetTextColor(widget, color) end
end

local function setVisible(state, key, widget, visible)
    if changed(state, key, visible) then Widgets.SetVisible(widget, visible) end
end

-- A selectable line lit (selected) or not: its background and edge bar.
local function drawLit(state, border, bar, lit)
    if not changed(state, "lit", lit) then return false end
    Widgets.SetColor(border, lit and COLORS.rowSelected or TRANSPARENT)
    Widgets.SetColor(bar, lit and COLORS.selectionBar or TRANSPARENT)
    return true
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

local function drawToggle(rowWidgets, item)
    local on, toggle = item.get() == true, rowWidgets.toggle
    if not changed(rowWidgets.shown, "on", on) then return end
    Widgets.SetColors(toggle.bars, on and COLORS.accent or COLORS.hairline)
    Widgets.SetColor(toggle.On.cell, on and COLORS.accent or TRANSPARENT)
    Widgets.SetTextColor(toggle.On.text, on and COLORS.bright or COLORS.faint)
    Widgets.SetColor(toggle.Off.cell, on and TRANSPARENT or COLORS.toggleOff)
    Widgets.SetTextColor(toggle.Off.text, on and COLORS.faint or COLORS.title)
end

-- The open dropdown's lines: the highlighted option lit, the current one marked.
local function drawList(list, item, options, current)
    local open = view.list ~= nil and view.list.item == item
    setVisible(list.shown, "visible", list.box, open)
    if not open then return end
    for index, line in ipairs(list.lines) do
        local optionIndex = view.list.first + index - 1
        local option = options[optionIndex]
        setVisible(line.shown, "visible", line.border, option ~= nil)
        if option then
            local highlighted = optionIndex == view.list.highlighted
            setText(line.shown, "text", line.text, option.label)
            setTextColor(line.shown, "color", line.text, highlighted and COLORS.bright or COLORS.label)
            drawLit(line.shown, line.border, line.bar, highlighted)
            if changed(line.shown, "current", optionIndex == current) then
                Widgets.SetColor(line.marker, optionIndex == current and COLORS.accent or TRANSPARENT)
            end
        end
    end
end

local function drawChoice(rowWidgets, item, isChangedNow)
    local options = optionsOf(item)
    local current = currentIndex(item, options)
    local value = rowWidgets.choice.value
    setText(rowWidgets.shown, "value", value, current and options[current].label or "-")
    -- a setting at its vanilla value reads quieter than a changed one
    local quiet = item.isChanged ~= nil and not isChangedNow
    setTextColor(rowWidgets.shown, "valueColor", value, quiet and COLORS.muted or COLORS.title)
    if rowWidgets.list then drawList(rowWidgets.list, item, options, current) end
end

local function drawAction(rowWidgets, item, isSelected)
    local pending = view.pendingConfirm == item
    setText(rowWidgets.shown, "value", rowWidgets.value, pending and (view.withController and "A again" or "Enter again") or "›")
    local color = pending and COLORS.accent or (isSelected and COLORS.highlight or COLORS.faint)
    setTextColor(rowWidgets.shown, "valueColor", rowWidgets.value, color)
end

local function drawRow(rowWidgets, item, isSelected)
    if drawLit(rowWidgets.shown, rowWidgets.border, rowWidgets.bar, isSelected) then
        Widgets.SetTextColor(rowWidgets.label, isSelected and COLORS.bright or (item.sub and COLORS.muted or COLORS.label))
        Widgets.SetWeight(rowWidgets.label, isSelected and "Medium" or "Regular")
    end
    local isChangedNow = isChanged(item)
    if changed(rowWidgets.shown, "changed", isChangedNow) then
        Widgets.SetColor(rowWidgets.marker, isChangedNow and COLORS.accent or TRANSPARENT)
    end
    if rowWidgets.toggle then
        drawToggle(rowWidgets, item)
    elseif rowWidgets.choice then
        drawChoice(rowWidgets, item, isChangedNow)
    else
        drawAction(rowWidgets, item, isSelected)
    end
end

local function drawTabCounts()
    for tabIndex, tab in ipairs(tabs) do
        local count = 0
        for _, item in ipairs(tab.items) do
            if isChanged(item) then count = count + 1 end
        end
        local tabWidgets = view.widgets.tabs[tabIndex]
        if changed(tabWidgets, "shownCount", count) then Widgets.SetText(tabWidgets.count, count > 0 and tostring(count) or "") end
    end
end

local function drawDescription(item)
    local description, shown = view.widgets.description, view.shown
    setVisible(shown, "descriptionVisible", description.box, item ~= nil)
    if not item then return end
    setText(shown, "descriptionTitle", description.title, item.upperLabel)
    setText(shown, "descriptionBody", description.body, item.description or "")
end

-- What each verb hint says for this row (or the open dropdown); nil hides it.
local function hintText(verb, item)
    if view.list then
        return (verb == "press" and "pick") or (verb == "change" and "page") or (verb == "back" and "back") or nil
    end
    if verb == "back" then return "close" end
    if not item then return nil end
    if verb == "press" then
        if item.kind == "toggle" then return "toggle" end
        if item.kind == "choice" and item.list then return "list" end
        if item.kind == "action" then return view.pendingConfirm == item and "confirm" or "use" end
    elseif verb == "change" and item.kind == "choice" then
        return "change"
    end
    return nil
end

local function drawFooter(item)
    local footer, shown = view.widgets.footer, view.shown
    setText(shown, "status", footer.status, App.status)
    setVisible(shown, "separator", footer.separator, App.status ~= "")
    local activeCount = activeCheatCount()
    setText(shown, "activeCount", footer.count, activeCount == 0 and "none active" or (activeCount .. " active"))
    for _, hint in ipairs(footer.hintRows[view.withController and "controller" or "keyboard"].hints) do
        if hint.verb then
            local text = hintText(hint.verb, item)
            setVisible(hint.shown, "visible", hint.group, text ~= nil)
            if text then setText(hint.shown, "text", hint.label, text) end
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
        local rowWidgets = page.rows[index]
        if rowWidgets and rowWidgets.info then
            setText(rowWidgets, "shownText", rowWidgets.info, item.text())
        elseif rowWidgets then
            drawRow(rowWidgets, item, index == selectedIndex)
        end
    end
    drawTabCounts()
    drawDescription(selectedItem)
    drawFooter(selectedItem)
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
    view.list = nil
    if view.widgets and isValid(view.widgets.root) then Widgets.SetVisible(view.widgets.root, false) end
    Input.UnblockGame(handOverTo)
end

-- Builds the widgets again (after a change to how they are built, e.g. the theme fonts switch).
function Menu.Rebuild()
    local wasOpen, withController = view.open, view.withController
    close()
    if view.widgets and isValid(view.widgets.root) then try(function() view.widgets.root:RemoveFromParent() end) end
    view.widgets = nil
    if wasOpen then open(withController) end
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

-- While a dropdown is open it takes the commands; anything else closes it first.
local LIST_COMMANDS = {
    up = function() moveInList(-1) end,
    down = function() moveInList(1) end,
    left = function() moveInList(-LIST_ROWS) end,
    right = function() moveInList(LIST_ROWS) end,
    enter = function()
        local option = optionsOf(view.list.item)[view.list.highlighted]
        if option then pickOption(view.list.item, option) end
        view.list = nil
    end,
    close = function() view.list = nil end,
}

local function handleCommand(command)
    if command == "toggle" or command == "toggleWithController" then
        if view.open then close() else open(command == "toggleWithController") end
        return
    end
    if not view.open then return end
    if command ~= "enter" then view.pendingConfirm = nil end
    if view.list and LIST_COMMANDS[command] then
        LIST_COMMANDS[command]()
    else
        view.list = nil
        COMMANDS[command]()
    end
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
        view.open, view.widgets, view.list = false, nil, nil
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
    if App.status ~= view.shown.status or os.clock() >= view.nextRefreshAt then
        view.nextRefreshAt = os.clock() + REFRESH_INTERVAL
        refresh()
    end
end

return Menu
