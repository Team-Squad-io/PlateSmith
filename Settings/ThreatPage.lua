local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local Schema = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local L = PS.L
local WidgetName = assert(Options.settingsPanelModel, "PlateSmith Options missing").WidgetName

-- Settings > PlateSmith > Threat: four folding sections. Your role (per character, saved at
-- once), Threat colours and Spotlight (profile settings, kept with Save), and Threat windows:
-- pick a window, then its mode, theme, rows, opacity, meter following and lock. Windows are
-- account state, so their changes apply at once and need no Save.
local function Console() return PS.ThreatConsole end

local Register = Options.RegisterControl

local function LabelOf(choices, value)
    for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
        if choice.value == value then return choice.label end
    end
    return ""
end

local tankChoices = {
    { value = "adaptive", label = L["Adaptive"],
        help = L["Your group role; without one, a tanking stance, presence, Righteous Fury or bear form "
            .. "(not on a mostly Balance or Restoration druid); else your specialization."] },
    { value = "always", label = L["Always"], help = L["Always treat this character as a tank."] },
    { value = "never", label = L["Never"], help = L["Never treat this character as a tank."] },
}
local paletteChoices = {
    { value = "auto", label = L["Follow colour-blind mode"] },
    { value = "standard", label = L["Standard"] },
    { value = "colourblind", label = L["Colour-blind"] },
}
local spotlightStyleChoices = {
    { value = "glow", label = L["Glow"] },
    { value = "arrow", label = L["Arrow"] },
    { value = "sides", label = L["Chevrons"] },
    { value = "box", label = L["Box"] },
    { value = "both", label = L["Box and chevrons"] },
}
local modeChoices = {
    { value = "threat", label = L["Threat meter"],
        help = L["Everyone's threat on your target, like a damage meter; your own row stays in view."] },
    { value = "tank", label = L["Tank"],
        help = L["Every enemy in view: who holds it, loose enemies first, and your threat on each."] },
}
local DOCK_SIDES = { { "right", L["Right"] }, { "left", L["Left"] }, { "above", L["Above"] }, { "below", L["Below"] } }
local METER_WINDOWS = 3

local function Seconds(value)
    return value == 1 and L["1 second"] or string.format(L["%d seconds"], value)
end
local function Visible(value) return string.format(L["%d%% visible"], math.floor(value * 100 + 0.5)) end

local function Selected()
    local console = Console()
    if not console then return nil end
    local record = Options.threatWindowSelected and console:GetWindow(Options.threatWindowSelected)
    if not record then
        record = console:GetWindows()[1]
        Options.threatWindowSelected = record and record.id or nil
    end
    return record
end

local function WindowChoices()
    local choices = {}
    local console = Console()
    for _, record in ipairs(console and console:GetWindows() or {}) do
        choices[#choices + 1] = { value = record.id, label = string.format("%d  %s", record.id, record.name) }
    end
    return choices
end

-- What the controls show while there is no window (all deleted).
local EMPTY = { mode = "tank", theme = "forge", rowHeight = 18, alpha = 1, dockMeter = 0, dockSide = "right",
    locked = false, shown = false, targetFirst = true }

local function Get(key)
    return function()
        local record = Selected()
        if record then return record[key] end
        return EMPTY[key]
    end
end

local function Set(key)
    return function(value)
        local record, console = Selected(), Console()
        local ok = record and console and console:SetWindowOption(record.id, key, value) or false
        Options:Refresh()
        return ok
    end
end

local function ThemeChoices()
    local choices = {}
    for _, theme in ipairs(PS.ThreatThemes.list) do choices[#choices + 1] = { value = theme.id, label = theme.label } end
    return choices
end

-- Following Blizzard's damage meter, as one choice: "off", or "<side>:<meter window>". A side
-- follows the meter window already chosen (the first when none); pointing at it lists them.
local function DockValue()
    local record = Selected() or EMPTY
    if record.dockMeter == 0 then return "off" end
    return record.dockSide .. ":" .. record.dockMeter
end

local function DockChoices()
    local record = Selected() or EMPTY
    local meter = record.dockMeter > 0 and record.dockMeter or 1
    local choices = { { value = "off", label = L["Off"] } }
    for _, side in ipairs(DOCK_SIDES) do
        local children = {}
        for index = 1, METER_WINDOWS do
            children[index] = { value = side[1] .. ":" .. index, label = string.format(L["Meter window %d"], index) }
        end
        local label = meter == 1 and side[2] or string.format(L["%s (meter window %d)"], side[2], meter)
        choices[#choices + 1] = { value = side[1] .. ":" .. meter, label = label, children = children }
    end
    return choices
end

local function SetDock(value)
    local record, console = Selected(), Console()
    if not record or not console then return false end
    local ok
    if value == "off" then
        ok = console:SetWindowOption(record.id, "dockMeter", 0)
    else
        local side, meter = tostring(value):match("^(%a+):(%d)$")
        ok = side and console:SetWindowOption(record.id, "dockSide", side)
            and console:SetWindowOption(record.id, "dockMeter", tonumber(meter)) or false
    end
    Options:Refresh()
    return ok
end

-- An action button that looks unavailable when it cannot apply (no window, or the limit).
local function Availability(button, available)
    Register({ Refresh = function() PS.SaveBar.SetAvailable(button, available()) end })
end

local function BuildRole(kit, flow)
    local section = Options.SettingsSection(kit, flow, L["Your role"], { collapsible = true, key = "threat.role",
        summary = function() return LabelOf(tankChoices, PS.GetCharacterSettings().tankRole) end })
    local row, dropdown = kit.DropdownRow(section, L["This character tanks"], {
        name = WidgetName("options_tankRole", "Dropdown"), choices = tankChoices,
        get = function() return PS.GetCharacterSettings().tankRole end,
        set = function(value) return PS.SetCharacterOption("tankRole", value) end,
    })
    Register(dropdown)
    kit.Add(section, row)
    kit.Add(section, kit.ControlHelp(section, L["When threat colours, rules (role.tank) and the threat windows treat you "
        .. "as a tank. Saved for this character only."]))
end

local function BuildColours(kit, flow)
    local get, set = Options.BindSetting("threatPalette")
    local section = Options.SettingsSection(kit, flow, L["Threat colours"], { collapsible = true, key = "threat.colours",
        summary = function() return LabelOf(paletteChoices, get()) end })
    local row, dropdown = kit.DropdownRow(section, L["Palette"], {
        name = WidgetName("options_threatPalette", "Dropdown"), choices = paletteChoices, get = get, set = set,
    })
    Register(dropdown)
    kit.Add(section, row)
    kit.Add(section, kit.ControlHelp(section, L["Colour-blind mode swaps green and red for blue and orange."]))
end

local function WindowsSummary()
    local console = Console()
    local windows = console and console:GetWindows() or {}
    if #windows == 0 then return L["No windows"] end
    local shown = 0
    for _, record in ipairs(windows) do if record.shown then shown = shown + 1 end end
    local count = #windows == 1 and L["1 window"] or string.format(L["%d windows"], #windows)
    return string.format(L["%s, %d shown"], count, shown)
end

local function BuildWindows(kit, flow)
    local section = Options.SettingsSection(kit, flow, L["Threat windows"], { collapsible = true, key = "threat.windows",
        summary = WindowsSummary })
    -- One switch for every window, at the section's right.
    local all = Window.Button(section.band, L["Show all"], 90, 22, function()
        if Console() then Console():Toggle() end
        Options:Refresh()
    end)
    kit.Accessory(section, all)
    Register({ Refresh = function()
        local console = Console()
        all:SetText(console and console:IsShown() and L["Hide all"] or L["Show all"])
        section:RefreshHeader()
    end })
    Options.threatConsoleButton = all

    -- The windows' limits (Threat/Geometry.lua loads after this file, before the page is built).
    local Geometry = assert(PS.ThreatGeometry, "PlateSmith ThreatGeometry missing")
    kit.Add(section, kit.Help(section, string.format(L["Up to %d windows, each a Threat meter (your group's threat on "
        .. "your target) or Tank (every enemy in view and who holds it). Drag a title to move a window and those snapped "
        .. "to it; Shift-drag moves it alone without snapping, so you can drop it anywhere. Shift-resize changes it alone. "
        .. "Right-click a title for its menu (Detach from group moves it clear of the rest). Changes apply at once."],
        Geometry.MAX_WINDOWS)))
    local pickRow, picker = kit.DropdownRow(section, L["Window"], {
        name = WidgetName("threatWindows_window", "Dropdown"), choices = WindowChoices,
        get = function() local record = Selected() return record and record.id end,
        set = function(value)
            Options.threatWindowSelected = value
            Options:Refresh()
        end,
    })
    Options.threatWindowDropdown = Register(picker)
    kit.Add(section, pickRow)
    local actionsRow, actions = kit.ButtonsRow(section, "", {
        { L["New window"], 110, function()
            local console = Console()
            local record = console and console:CreateWindow()
            if record then
                Options.threatWindowSelected = record.id
                console:Show()
            end
            Options:Refresh()
        end },
        { L["Rename"], 90, function()
            local record = Selected()
            if record then Console():PromptRename(record.id) end
        end },
        { L["Delete"], 90, function()
            local record = Selected()
            if record then Console():ConfirmDelete(record.id) end
        end },
    })
    Availability(actions[1], function()
        local console = Console()
        return console ~= nil and #console:GetWindows() < Geometry.MAX_WINDOWS
    end)
    Availability(actions[2], function() return Selected() ~= nil end)
    Availability(actions[3], function() return Selected() ~= nil end)
    kit.Add(section, actionsRow)
    local sampleRow, sampleCheck = kit.CheckRow(section, L["Test"], {
        text = L["Show sample data"], name = WidgetName("threatWindows_sample", "Checkbox"),
        get = function() local console = Console() return console ~= nil and console:IsSampleData() end,
        set = function(value)
            local console = Console()
            local ok = console ~= nil and console:SetSampleData(value)
            Options:Refresh()
            return ok
        end,
    })
    Options.threatSampleCheck = Register(sampleCheck)
    kit.Add(section, sampleRow)
    kit.Add(section, kit.ControlHelp(section, L["Every shown window fills with a made-up group and enemies, for "
        .. "screenshots or trying a theme. Until you reload; it turns off when you enter combat."]))

    kit.Add(section, kit.SubHeader(section, L["This window"]))
    local modeRow, mode = kit.DropdownRow(section, L["Mode"], {
        name = WidgetName("threatWindows_mode", "Dropdown"), choices = modeChoices, get = Get("mode"), set = Set("mode"),
    })
    Register(mode)
    kit.Add(section, modeRow)
    local firstRow, firstCheck = kit.CheckRow(section, L["Row order"], {
        text = L["Target first"], name = WidgetName("threatWindows_targetFirst", "Checkbox"),
        get = Get("targetFirst"), set = Set("targetFirst"),
    })
    Register(firstCheck)
    kit.Add(section, firstRow)
    kit.Add(section, kit.ControlHelp(section, L["In Tank mode your current target is always the first row."]))
    local themeRow, theme = kit.DropdownRow(section, L["Theme"], {
        name = WidgetName("threatWindows_theme", "Dropdown"), choices = ThemeChoices, get = Get("theme"), set = Set("theme"),
    })
    Register(theme)
    kit.Add(section, themeRow)
    -- The theme's preview, under its field.
    local previewRow = kit.Row(section, nil)
    previewRow:SetHeight(48)
    local preview = previewRow:CreateTexture(nil, "ARTWORK")
    preview:SetPoint("LEFT", previewRow, "LEFT", kit.CONTROL_X, 0)
    preview:SetSize(96, 48)
    Register({ Refresh = function()
        local record = Selected()
        local look = record and PS.ThreatThemes.Get(record.theme)
        if look and look.preview and PS.ThreatThemes.SetKit(preview, look.preview) then
            preview:SetTexCoord(PS.ThreatThemes.TexCoord(look.preview))
            preview:Show()
        else
            preview:Hide()
        end
    end })
    kit.Add(section, previewRow)

    local ranges = Geometry.WINDOW_RANGES
    local heightRow, rowHeight = kit.SliderRow(section, L["Row height"], {
        min = ranges.rowHeight[1], max = ranges.rowHeight[2], step = 1, name = WidgetName("threatWindows_rowHeight", "Slider"),
        get = Get("rowHeight"), set = Set("rowHeight"), drag = Set("rowHeight"),
    })
    Register(rowHeight)
    kit.Add(section, heightRow)
    local alphaRow, alpha = kit.SliderRow(section, L["Background opacity"], {
        min = ranges.alpha[1], max = ranges.alpha[2], step = 0.05, name = WidgetName("threatWindows_alpha", "Slider"),
        format = PS.UI.Controls.PercentText, get = Get("alpha"), set = Set("alpha"), drag = Set("alpha"),
    })
    Register(alpha)
    kit.Add(section, alphaRow)
    local dockRow, dock = kit.DropdownRow(section, L["Follow damage meter"], {
        name = WidgetName("threatWindows_dock", "Dropdown"), choices = DockChoices, get = DockValue, set = SetDock,
    })
    Register(dock)
    Options.threatWindowDock = dock
    kit.Add(section, dockRow)
    kit.Add(section, kit.ControlHelp(section, L["The window sits on that side of Blizzard's damage meter window and "
        .. "moves with it; point at a side to pick meter window 2 or 3. You can also drag a window onto a side of "
        .. "the meter, and away to stop."]))
    local shownRow, shownCheck = kit.CheckRow(section, L["Visibility"], {
        text = L["Shown"], name = WidgetName("threatWindows_shown", "Checkbox"), get = Get("shown"), set = Set("shown"),
    })
    Register(shownCheck)
    kit.Add(section, shownRow)
    local lockedRow, lockedCheck = kit.CheckRow(section, nil, {
        text = L["Locked (no moving or resizing)"], name = WidgetName("threatWindows_locked", "Checkbox"),
        get = Get("locked"), set = Set("locked"),
    })
    Register(lockedCheck)
    kit.Add(section, lockedRow)
end

local function BuildSpotlight(kit, flow)
    local getStyle, setStyle = Options.BindSetting("threatSpotlightStyle")
    local getAlpha, setAlpha, dragAlpha = Options.BindSetting("threatSpotlightOthersAlpha")
    local getTime, setTime, dragTime = Options.BindSetting("threatSpotlightDuration")
    local section = Options.SettingsSection(kit, flow, L["Spotlight"], { collapsible = true, key = "threat.spotlight",
        summary = function()
            return string.format(L["%s, %s, %s"], LabelOf(spotlightStyleChoices, getStyle()), Visible(getAlpha() or 1),
                Seconds(getTime() or 1))
        end })
    kit.Add(section, kit.Help(section, L["Click a threat window row to spotlight its plate. Only PlateSmith's own enemy "
        .. "plates dim; Blizzard's protected plates do not."]))
    local styleRow, style = kit.DropdownRow(section, L["Selected plate"], {
        name = WidgetName("options_threatSpotlightStyle", "Dropdown"), choices = spotlightStyleChoices,
        get = getStyle, set = setStyle,
    })
    Register(style)
    kit.Add(section, styleRow)
    local ranges = Schema.settingRanges
    local othersRow, others = kit.SliderRow(section, L["Other enemy plates"], {
        min = ranges.threatSpotlightOthersAlpha[1], max = ranges.threatSpotlightOthersAlpha[2], step = 0.05,
        name = WidgetName("options_threatSpotlightOthersAlpha", "Slider"), format = Visible,
        get = getAlpha, set = setAlpha, drag = dragAlpha,
    })
    Register(others)
    kit.Add(section, othersRow)
    local timeRow, duration = kit.SliderRow(section, L["Spotlight time"], {
        min = ranges.threatSpotlightDuration[1], max = ranges.threatSpotlightDuration[2], step = 1,
        name = WidgetName("options_threatSpotlightDuration", "Slider"), format = Seconds,
        get = getTime, set = setTime, drag = dragTime,
    })
    Register(duration)
    kit.Add(section, timeRow)
end

function Options:BuildThreatPage(page)
    local kit, flow, bar = self:NewSettingsPage(page, L["Threat"],
        L["Threat colours and the spotlight are part of your profile and are kept with Save; your role and the "
            .. "threat windows are saved at once."], true)
    BuildRole(kit, flow)
    BuildColours(kit, flow)
    BuildWindows(kit, flow)
    BuildSpotlight(kit, flow)
    self.threatSaveBar = bar
    -- A value change can change a folded section's summary.
    Register({ Refresh = function() if page:IsShown() then page:Relayout() end end })
    page:Relayout()
end
