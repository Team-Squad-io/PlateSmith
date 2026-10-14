local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Schema = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local ModuleSettings = assert(PS.ModuleSettings, "PlateSmith ModuleSettings missing")
local ThreatColours = assert(PS.ThreatColours, "PlateSmith ThreatColours missing")
local L = PS.L
local WidgetName = assert(Options.settingsPanelModel, "PlateSmith Options missing").WidgetName

-- Studio › Settings › Modules › Threat, PlateSmith's own module page and the first user of the Studio settings API
-- (Core/ModuleSettings.lua, Studio/Modules.lua): five folding sections. Your role (per character, saved at once),
-- Threat colours, Threat text & window colours and Spotlight (profile settings, kept with Save), and Threat windows:
-- pick a window, then its mode, theme, rows, opacity, meter following and lock. Windows are account state, so their
-- changes apply at once and need no Save. Game Options' Threat page only opens it (Settings/Panel.lua). Every control
-- keeps the id and widget name it had on Game Options' page or Studio's Behaviour & display.
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
        help = L["A group Tank role; else a tanking stance, presence, Righteous Fury or Bear Form (not on a mostly "
            .. "Balance or Restoration druid; Cat and other forms are not tanking); else your other group role, then "
            .. "your specialization."] },
    { value = "always", label = L["Always"], help = L["Always treat this character as a tank."] },
    { value = "never", label = L["Never"], help = L["Never treat this character as a tank."] },
}
-- Studio's Threat colours has the same control (Studio/ThreatColours.lua).
Options.tankRoleChoices = tankChoices
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
    { value = "rescue", label = L["Rescue"],
        help = L["Your group in a fixed order, coloured when someone pulls or has aggro; click a member to taunt "
            .. "their target."] },
}
local rescueLayoutChoices = {
    { value = "auto", label = L["List in a party, grid in a raid"] },
    { value = "list", label = L["Always a list"] },
    { value = "grid", label = L["Always a grid"] },
}
local rescueFilterChoices = {
    { value = "everyone", label = L["Everyone"] },
    { value = "healers", label = L["Healers only"] },
    { value = "healersRanged", label = L["Healers and ranged"] },
    { value = "group", label = L["My group only"] },
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
    locked = false, shown = false, targetFirst = true, rescueLayout = "auto", rescueFilter = "everyone",
    rescueInRaids = true, rescueSound = false, rescueSoundKey = "raidWarning", rescueSoundGap = 3, rescueFlash = false,
    rescueCooldown = false }

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

-- Your role: This character tanks (the one control for it: Studio's Threat colours had a copy), the line a profile's
-- fixed role adds and whom the plates treat you as (Studio/ThreatColours.lua).
local function BuildRole(kit)
    local section = kit.Section(nil, L["Your role"], { key = "role", anchor = "role",
        summary = function() return LabelOf(tankChoices, PS.GetCharacterSettings().tankRole) end })
    kit.Choice(section, { label = L["This character tanks"], bind = kit.Character("tankRole"), choices = tankChoices,
        id = "plate.tankRole", name = "editor_tankRole",
        help = L["When threat colours, rules and the threat windows treat you as a tank. Saved for this character only."] })
    Options.BuildThreatRoleSettings(kit.internal.SK, section)
end

-- Threat colours: on bars and names (Studio/ThreatColours.lua builds the rows; their ids stay "plate.*").
local function BuildThreatColours(kit)
    local section = kit.Section(nil, L["Threat colours"], { key = "colours", anchor = "colours",
        summary = Options.ThreatColourSummary })
    Options.BuildThreatColourSettings(kit.internal.SK, section, kit.internal.Bind)
end

local function BuildColours(kit)
    local bind = kit.Profile("threatPalette")
    -- Audit #4: the palette colours the threat text and the threat windows only; the colours on bars and names are
    -- Threat colours, so this section is named for what it covers.
    local section = kit.Section(nil, L["Threat text & window colours"], { key = "palette", anchor = "palette",
        summary = function() return LabelOf(paletteChoices, bind.get()) end })
    kit.Choice(section, { label = L["Palette"], bind = bind, choices = paletteChoices, name = "options_threatPalette",
        id = "threat.threatPalette",
        help = L["The threat text on plates and the threat windows. Colour-blind mode swaps green and red for blue and "
            .. "orange. Threat colours on health bars and names are set in Threat colours, above."] })
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

-- Rescue's rows, shown only while the selected window is a Rescue window (RESCUE_MODE.md section 6). Clicks and
-- bindings are account state shared by every Rescue window; the rest is the window's own.
local function IsRescue()
    local record = Selected()
    return record ~= nil and record.mode == "rescue"
end

local function PlayerClass()
    local service = PS.ThreatService
    return service and service.PlayerClass and service:PlayerClass() or nil
end

local function BuildRescue(kit, section)
    local Secure = assert(PS.ThreatRescueSecure, "PlateSmith ThreatRescueSecure missing")
    local Rescue = assert(PS.ThreatRescue, "PlateSmith ThreatRescue missing")
    local function Row(row, control, visible)
        if control then Register(control) end
        kit.Add(section, row, visible or IsRescue)
    end
    local layoutRow, layout = kit.DropdownRow(section, L["Layout"], {
        name = WidgetName("threatWindows_rescueLayout", "Dropdown"), choices = rescueLayoutChoices,
        get = Get("rescueLayout"), set = Set("rescueLayout"),
    })
    Row(layoutRow, layout)
    local filterRow, filter = kit.DropdownRow(section, L["Show"], {
        name = WidgetName("threatWindows_rescueFilter", "Dropdown"), choices = rescueFilterChoices,
        get = Get("rescueFilter"), set = Set("rescueFilter"),
    })
    Row(filterRow, filter)
    Row(kit.ControlHelp(section, L["Healers and ranged counts hunters, mages, warlocks and priests besides healers. Roles "
        .. "are the group's: someone without one is listed with the damage dealers."]))
    local raidsRow, raids = kit.CheckRow(section, L["In raids"], {
        text = L["Show this window in raids"], name = WidgetName("threatWindows_rescueInRaids", "Checkbox"),
        get = Get("rescueInRaids"), set = Set("rescueInRaids"),
    })
    Row(raidsRow, raids)
    local clicksRow, clicks = kit.CheckRow(section, L["Clicks"], {
        text = L["Click a member to cast"], name = WidgetName("threatWindows_rescueClicks", "Checkbox"),
        get = function() local console = Console() return console ~= nil and console:RescueClicksOn() end,
        set = function(value)
            local console = Console()
            local ok = console ~= nil and console:SetRescueClicks(value)
            Options:Refresh()
            return ok
        end,
    })
    Row(clicksRow, clicks)
    Row(kit.ControlHelp(section, L["Each member has an invisible click area over their row that casts your spell on "
        .. "their target, like a macro button. Turn it off if clicks are blocked on this client: the window still shows "
        .. "who needs help. Shared by every Rescue window."]))
    local function HasList()
        return IsRescue() and Secure.SPELLS[PlayerClass() or ""] ~= nil
    end
    for _, modifier in ipairs(Secure.MODIFIERS) do
        local row, dropdown = kit.DropdownRow(section, Secure.MODIFIER_LABELS[modifier], {
            name = WidgetName("threatWindows_rescue_" .. modifier, "Dropdown"),
            choices = function() return Secure.Choices(PlayerClass()) end,
            get = function()
                local console, class = Console(), PlayerClass()
                return console and Secure.Binding(console:RescueBindings(), class, modifier) or "none"
            end,
            set = function(value)
                local console, class = Console(), PlayerClass()
                local ok = console ~= nil and class ~= nil and console:SetRescueBinding(class, modifier, value)
                Options:Refresh()
                return ok
            end,
        })
        Row(row, dropdown, HasList)
    end
    Row(kit.ControlHelp(section, L["What each click on a member casts, for every character of your class. Spells you "
        .. "do not know are left unbound. A healer targeting a friend has no enemy to taunt: use your area taunt or "
        .. "Taunt my target."]), nil, HasList)
    -- A state, so a line in view (on Studio's page, help is a row's tooltip).
    Row(kit.Note(section, L["Your class has no taunt to bind: the window shows who needs help."]), nil,
        function() return IsRescue() and not HasList() end)
    local soundRow, sound = kit.CheckRow(section, L["Alerts"], {
        text = L["Sound when someone other than a tank gets aggro"],
        name = WidgetName("threatWindows_rescueSound", "Checkbox"), get = Get("rescueSound"), set = Set("rescueSound"),
    })
    Row(soundRow, sound)
    -- The built-in sounds, then LibSharedMedia's when it is installed.
    local pickRow, pick = kit.DropdownRow(section, L["Sound"], {
        name = WidgetName("threatWindows_rescueSoundKey", "Dropdown"), choices = Rescue.SoundChoices,
        get = Get("rescueSoundKey"), set = Set("rescueSoundKey"),
    })
    Row(pickRow, pick)
    local testRow = kit.ButtonsRow(section, "", {
        { L["Test"], 90, function()
            local record = Selected()
            Rescue.PlaySound(record and record.rescueSoundKey)
        end },
    })
    Row(testRow)
    local gapRow, gap = kit.SliderRow(section, L["At most every"], {
        min = Rescue.SOUND_GAP[1], max = Rescue.SOUND_GAP[2], step = 1, format = Seconds,
        name = WidgetName("threatWindows_rescueSoundGap", "Slider"),
        get = Get("rescueSoundGap"), set = Set("rescueSoundGap"), drag = Set("rescueSoundGap"),
    })
    Row(gapRow, gap)
    local flashRow, flash = kit.CheckRow(section, L["Border"], {
        text = L["Flash the window's border when someone other than a tank gets aggro"],
        name = WidgetName("threatWindows_rescueFlash", "Checkbox"), get = Get("rescueFlash"), set = Set("rescueFlash"),
    })
    Row(flashRow, flash)
    local cooldownRow, cooldown = kit.CheckRow(section, L["Header"], {
        text = L["Show my taunt's cooldown"],
        name = WidgetName("threatWindows_rescueCooldown", "Checkbox"), get = Get("rescueCooldown"),
        set = Set("rescueCooldown"),
    })
    Row(cooldownRow, cooldown)
    Row(kit.ControlHelp(section, L["Your left-click spell's cooldown, at the right of the window's header. Hidden when "
        .. "the game keeps it private."]))
end

-- Threat windows: rows from Studio's kit (internal: a picker, actions that look unavailable, the theme's preview).
local function BuildWindows(module)
    local internal = module.internal
    local kit = internal.SK
    local section = module.Section(nil, L["Threat windows"], { key = "windows", anchor = "windows",
        summary = WindowsSummary })
    -- One switch for every window, at the section's right.
    local all = internal.Button(section.band, L["Show all"], 90, 26)
    all:SetScript("OnClick", function()
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
        .. "your target), Tank (every enemy in view and who holds it) or Rescue (your group, coloured when someone pulls "
        .. "or has aggro; click a member to taunt their target). Drag a title to move a window and those snapped "
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
    -- Account-wide like the windows (not in Blueprints): Threat/MeterSkin.lua owns it.
    local skinRow, skinCheck = kit.CheckRow(section, L["Damage meter"], {
        text = L["Skin Blizzard's damage meter"], name = WidgetName("threatWindows_meterSkin", "Checkbox"),
        get = function() return PS.ThreatMeterSkin ~= nil and PS.ThreatMeterSkin.IsOn() end,
        set = function(value)
            local ok = PS.ThreatMeterSkin ~= nil and PS.ThreatMeterSkin.SetOn(value)
            Options:Refresh()
            return ok
        end,
    })
    Options.threatMeterSkinCheck = Register(skinCheck)
    kit.Add(section, skinRow)
    kit.Add(section, kit.ControlHelp(section, L["Draws Blizzard's damage meter in the threat windows' theme (Forge, Ledger "
        .. "or Glass: the theme of the window following that meter window, else of the first shown window; Forge for "
        .. "the other themes): its frame, header, buttons, bars, scroll bar and breakdown. Only its look changes; Edit "
        .. "Mode still places and sizes it. Off puts Blizzard's look back at once. For every character."]))

    kit.Add(section, kit.SubHeader(section, L["This window"]))
    local modeRow, mode = kit.DropdownRow(section, L["Mode"], {
        name = WidgetName("threatWindows_mode", "Dropdown"), choices = modeChoices, get = Get("mode"), set = Set("mode"),
    })
    Register(mode)
    kit.Add(section, modeRow)
    BuildRescue(kit, section)
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
    kit.Add(section, kit.ControlHelp(section, L["In combat a Rescue window cannot move, resize, follow the meter or "
        .. "hide: its click areas are fixed until combat ends, when everything waiting is applied."]), IsRescue)
end

local function BuildSpotlight(kit)
    local style, others = kit.Profile("threatSpotlightStyle"), kit.Profile("threatSpotlightOthersAlpha")
    local time = kit.Profile("threatSpotlightDuration")
    local section = kit.Section(nil, L["Spotlight"], { key = "spotlight", anchor = "spotlight",
        summary = function()
            return string.format(L["%s, %s, %s"], LabelOf(spotlightStyleChoices, style.get()), Visible(others.get() or 1),
                Seconds(time.get() or 1))
        end })
    kit.Help(section, L["Click a threat window row to spotlight its plate. Only PlateSmith's own enemy plates dim; "
        .. "Blizzard's protected plates do not."])
    kit.Choice(section, { label = L["Selected plate"], bind = style, choices = spotlightStyleChoices,
        name = "options_threatSpotlightStyle", id = "threat.threatSpotlightStyle" })
    local ranges = Schema.settingRanges
    kit.Slider(section, { label = L["Other enemy plates"], bind = others, min = ranges.threatSpotlightOthersAlpha[1],
        max = ranges.threatSpotlightOthersAlpha[2], step = 0.05, format = Visible,
        name = "options_threatSpotlightOthersAlpha", id = "threat.threatSpotlightOthersAlpha" })
    kit.Slider(section, { label = L["Spotlight time"], bind = time, min = ranges.threatSpotlightDuration[1],
        max = ranges.threatSpotlightDuration[2], step = 1, format = Seconds, name = "options_threatSpotlightDuration",
        id = "threat.threatSpotlightDuration" })
end

-- The threat settings in the profile (the Modules row's unsaved dot compares them with the saved profile).
local PROFILE_KEYS = { "colourByThreat", "threatColours", "threatPartColours", "threatColourRole", "threatColourSafeKeep",
    "tankWarning", "threatPalette", "threatSpotlightStyle", "threatSpotlightOthersAlpha", "threatSpotlightDuration" }
for _, part in ipairs(ThreatColours.PARTS) do PROFILE_KEYS[#PROFILE_KEYS + 1] = ThreatColours.PART_SETTINGS[part] end

-- The ids the page's controls kept from Behaviour & display ("plate.*"), so Options:OpenSettingsControl finds them here.
do
    local homes = Options.settingsControlHomes or {}
    Options.settingsControlHomes = homes
    local here = "module:threat"
    for _, id in ipairs({ "plate.tankRole", "plate.colourByThreat", "plate.threatColourSafeKeep", "plate.tankWarning" }) do
        homes[id] = here
    end
    for _, part in ipairs(ThreatColours.PARTS) do
        homes["plate." .. ThreatColours.PART_SETTINGS[part]] = here
        homes["plate.threatOwnColours_" .. part] = here
        for _, state in ipairs(ThreatColours.STATES) do homes["plate.threatColour_" .. part .. "_" .. state] = here end
    end
    for _, state in ipairs(ThreatColours.STATES) do homes["plate.threatColour_shared_" .. state] = here end
end

assert(ModuleSettings.Register("threat", {
    title = L["Threat"], icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    summary = L["Your role, Threat colours, the threat text and windows' colours, the spotlight and the threat windows."],
    launcher = L["Your role, Threat colours, the threat text and windows' colours, the spotlight and the threat windows "
        .. "are set in Blueprint Studio › Settings › Modules › Threat."],
    profileKeys = PROFILE_KEYS,
    build = function(_, kit)
        BuildRole(kit)
        BuildThreatColours(kit)
        BuildColours(kit)
        BuildSpotlight(kit)
        BuildWindows(kit)
    end,
}, ModuleSettings.BUILTIN))