-- ValorianSheet / ui/menu.lua
-- A keyboard menu drawn with plain UMG widgets: tabs of rows (toggles, choices, actions), an
-- optional slider on long choices for the mouse, and a status line.
--
--   F5 / Esc       open / close          Up / Down      select a row
--   Left / Right   change the value      Enter          toggle / run (twice for risky actions)
--   Q / E          previous / next tab
--
-- The menu content is defined in ui/sheet.lua; this file only knows the item kinds.
-- Everything runs on the game thread from Menu.Tick; while the menu is closed a tick only looks at
-- the key queue. A refresh only touches widgets whose text or colour changed.

local Unreal = require("lib.unreal")
local Log = require("lib.log")
local Game = require("game")
local State = require("state")
local Settings = require("settings")
local Widgets = require("ui.widgets")
local Input = require("ui.input")
local GameMenus = require("ui.game_menus")

local Menu = {}

local COLORS = Widgets.COLORS
local try, isValid = Unreal.Try, Unreal.IsValid

local TITLE = "VALORIAN SHEET"
local HINT = "Up/Down select   Left/Right change   Enter use   Q/E tab   F5 close"
local MIN_WIDTH = 460
local SLIDER_WIDTH = 150
local VALUE_WIDTH = 120
local POSITION = { X = 40, Y = 40 }
local REFERENCE_HEIGHT = 1080
local REFRESH_INTERVAL = 0.25
local GAME_MENU_CHECK_INTERVAL = 0.5

local tabs = {}   -- { title, items }
local view = {
    open = false,
    tabIndex = 1,
    shownTabIndex = nil,      -- the tab the widgets currently show
    selectedByTab = {},       -- tab index -> item index
    widgets = nil,            -- built on the first open
    pendingConfirm = nil,     -- the action waiting for its second Enter
    shownStatus = nil,
    nextRefreshAt = 0,
    nextGameMenuCheckAt = 0,
}

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

local function isSelectable(item)
    return item.kind == "toggle" or item.kind == "choice" or item.kind == "action"
end

-- A settings key (string) becomes a get/set pair on State.settings that logs and saves changes;
-- an accessor table ({ get, set }, e.g. from Menu.Value) is used as it is.
local function accessorFor(keyOrAccessor)
    if type(keyOrAccessor) == "table" then return keyOrAccessor end
    local key = keyOrAccessor
    return {
        get = function() return State.settings[key] end,
        set = function(value)
            State.settings[key] = value
            Log.Info("menu: " .. key .. " -> " .. tostring(value))
            Settings.MarkDirty()
        end,
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

-- options.confirm: a prompt; the action then needs a second Enter.
-- options.anytime: runs without a loaded save (by default an action needs one, and says so).
function Menu.Action(label, run, options)
    options = options or {}
    return { kind = "action", label = label, run = run, confirmPrompt = options.confirm, needsSave = not options.anytime }
end

function Menu.Toggle(label, keyOrAccessor)
    local accessor = accessorFor(keyOrAccessor)
    return { kind = "toggle", label = label, get = accessor.get, set = accessor.set }
end

-- options: a list of { label, value }, or a function returning one (read on every refresh, so it
-- should cache). display.slider adds a slider for the mouse (long lists); display.wrap = false stops
-- at the ends.
function Menu.Choice(label, options, keyOrAccessor, display)
    local accessor = accessorFor(keyOrAccessor)
    display = display or {}
    return {
        kind = "choice", label = label, options = options, get = accessor.get, set = accessor.set,
        slider = display.slider == true, wrap = display.wrap ~= false,
    }
end

local function optionsOf(item)
    local options = item.options
    if type(options) == "function" then options = options() end
    return options or {}
end

local function sameValue(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
    return a == b
end

local function currentIndex(item, options)
    local value = item.get()
    for index, option in ipairs(options) do
        if sameValue(option.value, value) then return index end
    end
    return nil
end

local function valueText(item, selected)
    if item.kind == "action" then
        return view.pendingConfirm == item and "Enter again" or ""
    end
    local text
    if item.kind == "toggle" then
        text = item.get() and "ON" or "OFF"
    else
        local options = optionsOf(item)
        local index = currentIndex(item, options)
        text = index and options[index].label or "-"
    end
    if selected then text = "<  " .. text .. "  >" end
    return text
end

function Menu.AddTab(title, items)
    tabs[#tabs + 1] = { title = title, items = items }
    for index, item in ipairs(items) do
        if isSelectable(item) then
            view.selectedByTab[#tabs] = index
            break
        end
    end
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
    if item.needsSave and not Game.Player() then
        State.status = "Load a save first"
        return
    end
    if item.confirmPrompt and view.pendingConfirm ~= item then
        view.pendingConfirm = item
        State.status = item.confirmPrompt .. " Press Enter again to confirm."
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
-- Widgets
-- ---------------------------------------------------------------------------

local function buildRow(tree, page, name, item)
    local border = Widgets.Border(tree, name .. "Row", COLORS.rowIdle, { 8, 3, 8, 3 })
    local line = Widgets.HorizontalBox(tree, name .. "Line")
    border:SetContent(line)

    local label = Widgets.Text(tree, name .. "Label", item.label, 13, COLORS.label)
    local labelSlot = line:AddChild(label)
    try(function() labelSlot:SetSize({ Value = 1.0, SizeRule = 1 }) end)   -- fill
    try(function() labelSlot:SetVerticalAlignment(2) end)                   -- center
    Widgets.Pad(labelSlot, 0, 0, 16, 0)
    local row = { border = border, label = label }

    if item.kind == "choice" and item.slider then
        local options = optionsOf(item)
        local maximum = math.max(#options, 2)
        local box, slider = Widgets.Slider(tree, name .. "Slider", 1, maximum, currentIndex(item, options) or 1, SLIDER_WIDTH)
        local sliderSlot = line:AddChild(box)
        try(function() sliderSlot:SetVerticalAlignment(2) end)
        Widgets.Pad(sliderSlot, 0, 0, 12, 0)
        row.slider, row.sliderMaximum = slider, maximum
    end

    local value = Widgets.Text(tree, name .. "Value", "", 13, COLORS.value)
    local valueWidget = value
    if item.kind ~= "action" then
        valueWidget = Widgets.SizeBox(tree, name .. "ValueBox")
        try(function() valueWidget:SetMinDesiredWidth(VALUE_WIDTH) end)
        valueWidget:SetContent(value)
    end
    local valueSlot = line:AddChild(valueWidget)
    try(function() valueSlot:SetVerticalAlignment(2) end)
    row.value = value

    Widgets.Pad(page:AddChild(border), 0, 1, 0, 1)
    return row
end

local function buildPage(tree, column, tabIndex, tab)
    local page = Widgets.VerticalBox(tree, "Page" .. tabIndex)
    local rows = {}
    for index, item in ipairs(tab.items) do
        local name = "Tab" .. tabIndex .. "Item" .. index
        if item.kind == "section" then
            local heading = Widgets.Text(tree, name, item.label:upper(), 11, COLORS.accent)
            Widgets.Pad(page:AddChild(heading), 0, index == 1 and 0 or 10, 0, 3)
        elseif item.kind == "info" then
            local text = Widgets.Text(tree, name, "", 11, COLORS.label)
            Widgets.Pad(page:AddChild(text), 8, 2, 8, 2)
            rows[index] = { info = text }
        else
            rows[index] = buildRow(tree, page, name, item)
        end
    end
    column:AddChild(page)
    Widgets.SetVisible(page, false)
    return { box = page, rows = rows }
end

local function build(controller)
    Widgets.StartBuild()
    local widgetLibrary = Game.WidgetLibrary()
    local root = try(function()
        return widgetLibrary:Create(controller, Unreal.Static("/Script/UMG.UserWidget"), controller)
    end)
    if not isValid(root) then root = Widgets.Construct("/Script/UMG.UserWidget", controller, "Root") end
    local tree = Widgets.Construct("/Script/UMG.WidgetTree", root, "Tree")
    root.WidgetTree = tree
    local canvas = Widgets.Construct("/Script/UMG.CanvasPanel", tree, "Canvas")
    tree.RootWidget = canvas

    local frame = Widgets.Border(tree, "Frame", COLORS.frame, { 1, 1, 1, 1 })
    local frameSlot = canvas:AddChild(frame)
    try(function() frameSlot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } }) end)
    try(function() frameSlot:SetAutoSize(true) end)
    local panel = Widgets.Border(tree, "Panel", COLORS.background, { 18, 14, 18, 12 })
    frame:SetContent(panel)
    local widthBox = Widgets.SizeBox(tree, "Width")
    try(function() widthBox:SetMinDesiredWidth(MIN_WIDTH) end)
    panel:SetContent(widthBox)
    local column = Widgets.VerticalBox(tree, "Column")
    widthBox:SetContent(column)

    Widgets.Pad(column:AddChild(Widgets.Text(tree, "Title", TITLE, 20, COLORS.title)), 0, 0, 0, 4)
    local tabRow = Widgets.HorizontalBox(tree, "Tabs")
    local tabLabels = {}
    for index, tab in ipairs(tabs) do
        tabLabels[index] = Widgets.Text(tree, "Tab" .. index, tab.title:upper(), 12, COLORS.muted)
        Widgets.Pad(tabRow:AddChild(tabLabels[index]), 0, 0, 14, 0)
    end
    Widgets.Pad(column:AddChild(tabRow), 0, 0, 0, 4)
    local accentLine = Widgets.SizeBox(tree, "AccentLine", nil, 1.0)
    accentLine:SetContent(Widgets.Border(tree, "AccentLineFill", COLORS.accent))
    Widgets.Pad(column:AddChild(accentLine), 0, 0, 0, 8)

    local pages = {}
    for index, tab in ipairs(tabs) do pages[index] = buildPage(tree, column, index, tab) end

    local status = Widgets.Text(tree, "Status", "", 11, COLORS.status)
    Widgets.Pad(column:AddChild(status), 0, 10, 0, 0)
    Widgets.Pad(column:AddChild(Widgets.Text(tree, "Hint", HINT, 10, COLORS.muted)), 0, 4, 0, 0)

    try(function() root:AddToViewport(1000) end)
    view.widgets = { root = root, frame = frame, frameSlot = frameSlot, tabLabels = tabLabels, pages = pages, status = status }
    view.shownTabIndex = nil
end

-- The menu is laid out for 1080p and scaled to the viewport (UMG's own DPI scale divided out).
local function applyScale(controller)
    local layout = Unreal.Static("/Script/UMG.Default__WidgetLayoutLibrary")
    local height = Unreal.TryNumber(function() return layout:GetViewportSize(controller).Y end)
    local dpiScale = Unreal.TryNumber(function() return layout:GetViewportScale(controller) end)
    local scale = 1
    if height and height > 0 and dpiScale and dpiScale > 0 then scale = (height / REFERENCE_HEIGHT) / dpiScale end
    local widgets = view.widgets
    try(function() widgets.frame:SetRenderTransformPivot({ X = 0.0, Y = 0.0 }) end)
    try(function() widgets.frame:SetRenderScale({ X = scale, Y = scale }) end)
    try(function() widgets.frameSlot:SetPosition({ X = POSITION.X * scale, Y = POSITION.Y * scale }) end)
end

local function showTab()
    local widgets = view.widgets
    if view.shownTabIndex == view.tabIndex then return end
    if view.shownTabIndex then
        Widgets.SetVisible(widgets.pages[view.shownTabIndex].box, false)
        Widgets.SetTextColor(widgets.tabLabels[view.shownTabIndex], COLORS.muted)
    end
    Widgets.SetVisible(widgets.pages[view.tabIndex].box, true)
    Widgets.SetTextColor(widgets.tabLabels[view.tabIndex], COLORS.title)
    view.shownTabIndex = view.tabIndex
end

-- Writes only what changed since the row was last drawn.
local function drawRow(row, item, isSelected)
    local text = valueText(item, isSelected)
    if text ~= row.shownText then
        Widgets.SetText(row.value, text)
        row.shownText = text
    end
    if isSelected ~= row.shownSelected then
        try(function() row.border:SetBrushColor(isSelected and COLORS.rowSelected or COLORS.rowIdle) end)
        Widgets.SetTextColor(row.label, isSelected and COLORS.title or COLORS.label)
        Widgets.SetTextColor(row.value, isSelected and COLORS.title or COLORS.value)
        row.shownSelected = isSelected
    end
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

local function refresh()
    local widgets = view.widgets
    if not widgets then return end
    showTab()
    local tab, page = tabs[view.tabIndex], widgets.pages[view.tabIndex]
    local _, selectedIndex = selected()
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
    if State.status ~= view.shownStatus then
        Widgets.SetText(widgets.status, State.status)
        view.shownStatus = State.status
    end
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

local function open()
    local controller = Game.Controller()
    if not controller then
        Log.Info("menu: no player controller yet")
        return
    end
    local gameMenu, className = GameMenus.FindOpen()
    if gameMenu or GameMenus.IsGamePaused() then
        Log.Info("menu not opened: a game menu is open (" .. tostring(className or "game paused") .. ")")
        return
    end
    if not (view.widgets and isValid(view.widgets.root)) then
        view.widgets = nil
        Log.Guarded("build menu", build, controller)
        if not view.widgets then return end
    end
    Widgets.SetVisible(view.widgets.root, true)
    applyScale(controller)
    Input.BlockGame(controller)
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
    if command == "toggle" then
        if view.open then close() else open() end
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
        if gameMenu or GameMenus.IsGamePaused() then
            close(gameMenu)
            return
        end
    end
    if readSliders() or State.status ~= view.shownStatus or os.clock() >= view.nextRefreshAt then
        view.nextRefreshAt = os.clock() + REFRESH_INTERVAL
        refresh()
    end
end

return Menu
