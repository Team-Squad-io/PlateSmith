local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local catalog = assert(Options.editorCatalog)
local model = assert(Options.studioModel)
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")
local Controls = assert(PS.UI and PS.UI.Controls, "PlateSmith Controls missing")
local Schema = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local L = PS.L
local WidgetName = model.WidgetName
local CreateStudioButton = chrome.CreateStudioButton
local profileRanges, optionalRanges = Schema.profileRanges, Schema.optionalProfileRanges
local PixelText, PointText, PercentText = Controls.PixelText, Controls.PointText, Controls.PercentText
local MAX_RULES = Schema.MAX_RULES

-- Rule and style presets (Rules > Presets, Style > Presets): Core/ProfilePresets.lua, shared with
-- the profile presets. Style > Presets lists the built-in looks, then the player's saved ones.
local Presets = assert(PS.ProfilePresets, "PlateSmith ProfilePresets missing")
local RULE_PRESETS, STYLE_PRESETS = Presets.RULES, Presets.STYLES
local STYLE_DEFAULTS = Schema.STYLE_DEFAULTS
local SetAvailable = assert(PS.SaveBar, "PlateSmith SaveBar missing").SetAvailable

-- The inspector's layout kit: the shared panel layout (UI/Layout.lua: its spacing tokens, flow
-- and builders) for the inspector's column, in parchment ink (high contrast: the dark palette),
-- with Studio's buttons, value-box art and arrow icons. The column is the parchment inside its
-- rail, PAD_X in from it and from the scroll bar's lane.
local PanelLayout = assert(PS.UI.Layout, "PlateSmith Layout missing")
local Theme = PS.StudioTheme
local FRAME = chrome.INSPECTOR
local function HighContrast()
    local access = Options.StudioAccess and Options:StudioAccess() or {}
    return access.highContrast and true or false
end
-- The kit's tree arrows point right (expand) and down (collapse); mirrored, left and up.
local SEGMENT_ICONS = { right = { "expand-arrow-normal" }, left = { "expand-arrow-normal", "x" },
    bottom = { "collapse-arrow-normal" }, top = { "collapse-arrow-normal", "y" } }
local function SegmentIcon(segment, which, size)
    local art = SEGMENT_ICONS[which]
    if not art then return nil end
    local icon = segment:CreateTexture(nil, "OVERLAY")
    Theme.Place(icon, art[1], segment, 0, 0, size, size)
    if Theme.Size(art[1]) then
        local left, right, top, bottom = Theme.TexCoord(art[1])
        if art[2] == "x" then icon:SetTexCoord(right, left, top, bottom) end
        if art[2] == "y" then icon:SetTexCoord(left, right, bottom, top) end
    end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", segment, "CENTER", 0, 0)
    return icon
end
Options.editorSectionFolds = Options.editorSectionFolds or {}
local K = PanelLayout.New({
    width = FRAME.width - FRAME.rail - FRAME.lane - PanelLayout.TOKENS.PAD_X * 2,
    palette = function() return HighContrast() and PanelLayout.PALETTES.contrast or PanelLayout.PALETTES.parchment end,
    -- The header (the part's name and what it is), custom text's box and a group's member lines.
    tokens = { HEADER_H = 30, HEADER_GAP = 4, HEADER_FONT = 22, TEMPLATE_H = 54, MEMBER_H = 20 },
    button = CreateStudioButton,
    segmentIcon = SegmentIcon,
    fieldArt = function(edit)
        local art = Theme.ThreeSlice(edit, "value-box", nil)
        art.fit = true
        Options.editorKitFields = Options.editorKitFields or {}
        Options.editorKitFields[#Options.editorKitFields + 1] = art
        return art
    end,
    -- Chrome's ApplyEditorTheme repaints these for the current look.
    register = function(kind, object)
        local key = kind == "segment" and "editorSegments" or kind == "card" and "editorCards"
            or kind == "section" and "editorSections"
        if not key then return end
        Options[key] = Options[key] or {}
        Options[key][#Options[key] + 1] = object
    end,
    revert = function() Options:RefreshEditorInspectorContext() end,
    -- Every section folds. Folds are kept per section title and shared by every part, in the
    -- player's saved state (sectionFolds).
    collapsible = true,
    sectionState = function()
            local state = PS.GetState and PS.GetState()
            return state and state.sectionFolds or Options.editorSectionFolds
        end,
    relayout = function() Options:LayoutEditorInspector() end,
    chevron = function(texture, open)
        local parent = texture:GetParent()
        Theme.Place(texture, open and "collapse-arrow-normal" or "expand-arrow-normal", parent, 0, 0, 14, 14)
        texture:ClearAllPoints()
        texture:SetPoint("LEFT", parent, "LEFT", 0, 0)
        -- The kit's arrows are light (for dark panels): inked like the section's title.
        local ink = (HighContrast() and PanelLayout.PALETTES.contrast or PanelLayout.PALETTES.parchment).ink.title
        texture:SetVertexColor(ink[1], ink[2], ink[3], 1)
    end,
})
Options.inspectorKit = K
local TextHeight, ValueBox = K.TextHeight, K.ValueBox

-- A ? tooltip's last lines: tokens (and, for templates, formatters) other addons registered,
-- read when it opens so late registrations show.
local function AddExtensionHelp(button, withFormatters)
    if not button.HookScript then return end
    button:HookScript("OnEnter", function()
        if not GameTooltip then return end
        local tokens, formatters = {}, {}
        for _, token in ipairs(PS.Template.ListTokens()) do
            if not token.builtin then
                tokens[#tokens + 1] = token.label and string.format(L["%s (%s)"], token.id, token.label) or token.id
            end
        end
        for _, formatter in ipairs(withFormatters and PS.Template.ListFormatters() or {}) do
            formatters[#formatters + 1] = formatter.id
        end
        if #tokens > 0 then
            GameTooltip:AddLine(string.format(L["From other addons: %s"], table.concat(tokens, ", ")), 0.6, 0.85, 1, true)
        end
        if #formatters > 0 then
            GameTooltip:AddLine(string.format(L["Formatters from other addons: %s"], table.concat(formatters, ", ")),
                0.6, 0.85, 1, true)
        end
        if #tokens + #formatters > 0 then GameTooltip:Show() end
    end)
end

local function HelpButton(parent, title, lines, withFormatters)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(18, 18)
    button:SetText("?")
    Controls.AttachTooltip(button, title, lines)
    AddExtensionHelp(button, withFormatters)
    return button
end

-- What the inspector shows (Editor's RefreshEditorInspectorContext sets it): key (a part),
-- group, plate, context (which part controls) and movable.
local function Selection() return Options.editorInspectorSelection or {} end
local function Profile() return PS.GetPlateProfileSettings(Options.editorProfile) end
local Register = assert(Options.RegisterControl, "PlateSmith RegisterControl missing")
local function SelectedPosition()
    local key = Options.selectedComponent
    return key and Options.editorLayout and Options.editorLayout[key]
end
local function SelectedSlot()
    local key = Options.selectedComponent
    local profile = Profile()
    return key and key:match("^value%d+$") and profile and profile.valueSlots and profile.valueSlots[key], key
end

-- A setting the whole profile shares (PS.SetOption); the plates and the controls follow.
local function SettingControl(key)
    return function() return PS.GetSettings()[key] end, function(value)
        PS.SetOption(key, value)
        Options:Refresh(true)
    end
end

-- This plate type's own option (PS.SetPlateProfileOption). A slider's steps only move the preview.
local function ProfileSliderRow(parent, label, key, range, step, format)
    local _, slider = K.SliderRow(parent, label, {
        min = range[1], max = range[2], step = step, format = format,
        name = WidgetName("selected_profile_" .. key, "Slider"),
        get = function()
            local profile = Profile()
            return profile and profile[key]
        end,
        drag = function(value)
            local ok = PS.SetPlateProfileOption(Options.editorProfile, key, value)
            Options:QueueRefresh()
            return ok
        end,
        set = function(value)
            local ok = PS.SetPlateProfileOption(Options.editorProfile, key, value)
            Options:Refresh(true)
            return ok
        end,
    })
    return Register(slider)
end

local function SetProfileValue(key)
    return function(value)
        PS.SetPlateProfileOption(Options.editorProfile, key, value)
        Options:Refresh(true)
    end
end
local function ProfileValue(key)
    return function()
        local profile = Profile()
        return profile and profile[key]
    end
end

-- Settings › Show on plates: shortcuts over the tree's eyes (Schema's PART_SWITCHES), each ticked
-- while its part shows on every plate type.
local SHOW_ON_PLATES = {
    { key = "quest", label = L["Show quest markers"] }, { key = "showTagged", label = L["Show tagged indicator"] },
    { key = "threat", label = L["Show threat details"] }, { key = "showClassification", label = L["Show elite and rare marks"] },
}

-- The inspector's column: everything a selected part offers, in one scrolling column on the
-- parchment: its header, then Placement, its own sections, Style and Rules. Its padding inside
-- the scroll is the kit's: PAD_X at both sides, PAD_TOP above the name, PAD_BOTTOM below the end.
local INSPECTOR_PAD = { left = K.PAD_X, right = K.PAD_X, top = K.PAD_TOP, bottom = K.PAD_BOTTOM }
Options.editorInspectorPad = INSPECTOR_PAD

function Options:SetEditorInspectorContentHeight(height)
    if not self.editorComponentContent then return end
    self.editorComponentContent:SetHeight(height)
    if self.editorComponentHolder then
        self.editorComponentHolder:SetHeight(height + INSPECTOR_PAD.top + INSPECTOR_PAD.bottom)
    end
end

-- The part's controls for each context (Editor's editorContextForKey): a flow of sections,
-- shown while its part is selected.
local function CreateContext(page, key)
    local frame = K.Group(page)
    Options.editorContextFrames[key] = frame
    K.Add(page, frame, function() return Selection().context == key end)
    return frame
end

-- Header: the part's name (a custom value's is editable) with its eye at the right on the same
-- line, then what it is, wrapped across the column.
local function BuildHeader(page)
    local header = CreateFrame("Frame", nil, page)
    header:SetSize(K.WIDTH, K.HEADER_H)
    local band = CreateFrame("Frame", nil, header)
    band:SetSize(K.WIDTH, K.HEADER_H)
    band:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    local eyeSlot = K.CHECK_W + K.CONTROL_GAP
    local title = K.Text(band, L["Select a component"], "label")
    title:SetFont(K.FONT_PATH, K.HEADER_FONT)
    title:SetWidth(K.WIDTH - eyeSlot)
    title:SetPoint("LEFT", band, "LEFT", 0, 0)
    if title.SetWordWrap then title:SetWordWrap(false) end
    Options.editorComponentTitle = title
    -- A custom value's title is its name: click it to rename (Enter keeps, Escape cancels,
    -- blank goes back to "Value 1").
    local nameEdit = Controls.EditBox(band, { width = K.WIDTH - eyeSlot, height = K.HEADER_H, fontSize = K.HEADER_FONT,
        colour = PanelLayout.PALETTES.parchment.ink.label, maxLetters = Schema.VALUE_NAME_LENGTH, rule = { 0.42, 0.33, 0.21, 0.5 } })
    nameEdit:SetPoint("LEFT", band, "LEFT", 0, 0)
    nameEdit:Hide()
    local function CommitName(edit)
        local key = Options.selectedComponent
        if key and key:match("^value%d+$") then
            PS.SetPlateValueSlot(Options.editorProfile, key, "name", edit:GetText())
            Options:RefreshEditorComponentList(PS.GetSettings())
        end
        edit:ClearFocus()
        Options:RefreshEditorInspectorContext()
    end
    nameEdit:SetScript("OnEnterPressed", CommitName)
    nameEdit:SetScript("OnEditFocusLost", function(edit) if edit.studioEditing then CommitName(edit) end end)
    nameEdit:SetScript("OnEditFocusGained", function(edit) edit.studioEditing = true end)
    nameEdit:SetScript("OnEscapePressed", function(edit)
        edit.studioEditing = false
        edit:ClearFocus()
        Options:RefreshEditorInspectorContext()
    end)
    Controls.AttachTooltip(nameEdit, L["Rename"], { L["Click to name this value. Leave it blank for the default name."] })
    Options.editorComponentNameEdit = nameEdit
    -- A pencil after the name says it can be edited.
    local namePencil = CreateFrame("Button", nil, nameEdit)
    namePencil:SetSize(K.SWATCH, K.SWATCH)
    namePencil:SetPoint("RIGHT", nameEdit, "RIGHT", 0, 0)
    namePencil:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    namePencil:SetHighlightTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "ADD")
    namePencil:SetScript("OnClick", function() Options:BeginEditorRename(Options.selectedComponent) end)
    Controls.AttachTooltip(namePencil, L["Rename"], { L["Give this value its own name."] })
    if nameEdit.SetTextInsets then nameEdit:SetTextInsets(0, K.SWATCH + K.CHECK_INSET, 0, 0) end
    Options.editorComponentNamePencil = namePencil
    -- The eye, as in the tree: shows or hides the part (or every part in the group).
    local eye = chrome.CreateVisibilityEye(band, function(instance)
        local selection = Selection()
        if selection.key then
            Options:SetEditorComponentVisibility(selection.key, instance:GetChecked() and true or false)
        elseif selection.group then
            Options:SetEditorGroupVisibility(selection.group, instance.mixed or instance:GetChecked() and true or false)
        end
    end, L["Show"], { L["Show or hide it on the plate."] })
    eye:SetPoint("RIGHT", band, "RIGHT", 0, 0)
    Options.editorInspectorEye = eye
    local description = K.Text(header, "", "muted")
    description:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -(K.HEADER_H + K.HEADER_GAP))
    description:SetWidth(K.WIDTH)
    if description.SetWordWrap then description:SetWordWrap(true) end
    Options.editorComponentDescription = description
    function header:Measure()
        local text = description:GetText() or ""
        local height = K.HEADER_H + (text == "" and 0 or K.HEADER_GAP + TextHeight(description, K.WIDTH))
        self:SetHeight(height)
        return height
    end
    Options.editorHeaderRefresh = function()
        local selection = Selection()
        if selection.key and Options.editorLayout and Options.editorLayout[selection.key] then
            eye.mixed = false
            eye:SetChecked(Options:IsEditorPartShown(selection.key))
            eye:Show()
        elseif selection.group then
            local row = Options.editorCustomGroupHeaders and Options.editorCustomGroupHeaders[selection.group]
            local tick = row and row.visibility
            eye.mixed = tick and tick.mixed or false
            eye:SetChecked(tick and tick:GetChecked() and true or false)
            eye:Show()
        else
            eye:Hide()
        end
    end
    K.Add(page, header)
end

-- Controls that cannot apply right now (Stacking while unmanaged) are dimmed this much.
local DIMMED_ALPHA = 0.55

-- Placement: what the part is anchored to (its parent in the tree; dragging it there does the
-- same) and how. Free keeps an offset from the parent's centre; pinned to an edge, it follows the
-- parent's size. Either way it moves with the parent and hides with a hidden one.
local function BuildPlacement(page)
    local section = K.Section(page, L["PLACEMENT"])
    Options.editorInspectorBasics = section
    local function AnchorChoices()
        local key, layout = Options.selectedComponent, Options.editorLayout or {}
        local choices = { { value = "", label = L["Plate"] } }
        local entries = {}
        for other, position in pairs(layout) do
            if type(position) == "table" and other ~= key and not position.removed
                and not (key and Options:IsEditorUnder(other, key))
                and (other:match("^group%.%d+$") or Options:IsEditorComponentRelevant(other)) then
                entries[#entries + 1] = { value = other, label = Options:EditorNodeLabel(other),
                    group = other:match("^group%.%d+$") ~= nil }
            end
        end
        table.sort(entries, function(left, right)
            if left.group ~= right.group then return left.group end
            return left.label < right.label
        end)
        for _, entry in ipairs(entries) do choices[#choices + 1] = entry end
        return choices
    end
    local anchorRow, anchor = K.DropdownRow(section, L["Anchor to"], {
        choices = AnchorChoices, name = WidgetName("editor_anchor", "Dropdown"),
        get = function()
            local position = SelectedPosition()
            return position and position.parent or ""
        end,
        set = function(parentKey)
            if Options.selectedComponent then Options:SetEditorAnchor(Options.selectedComponent, parentKey) end
        end,
    })
    K.Add(section, anchorRow)
    -- Pinning needs a part as the anchor, not a group or the plate.
    local function Pinnable()
        local position = SelectedPosition()
        local parent = position and position.parent
        return parent ~= nil and not parent:match("^group%.%d+$") and Options.editorLayout[parent] ~= nil
    end
    local behaviourRow = K.Row(section, L["Behaviour"])
    local behaviour = K.Segmented(behaviourRow, {
        name = WidgetName("editor_behaviour", "Choice"),
        choices = {
            { value = "static", label = L["Free"], tooltip = L["Free: an offset from its parent's centre."] },
            { value = "left", label = L["Left"], icon = "left",
                tooltip = L["Pinned left of it: its right edge follows the parent's left edge."] },
            { value = "right", label = L["Right"], icon = "right",
                tooltip = L["Pinned right of it: its left edge follows the parent's right edge."] },
            { value = "top", label = L["Top"], icon = "top",
                tooltip = L["Pinned above it: its bottom edge follows the parent's top edge."] },
            { value = "bottom", label = L["Bottom"], icon = "bottom",
                tooltip = L["Pinned below it: its top edge follows the parent's bottom edge."] },
        },
        disabledTip = L["To pin it to an edge, anchor it to a part (not a group or the plate)."],
        enabled = function(value) return value == "static" or Pinnable() end,
        get = function()
            local position = SelectedPosition()
            return position and position.attach or "static"
        end,
        set = function(edge)
            local key = Options.selectedComponent
            if key then Options:SetEditorAttach(key, edge ~= "static" and edge or nil) end
        end,
    })
    K.Add(section, behaviourRow)
    -- X and Y (for a pinned part, an offset from its pinned spot).
    local offset
    offset = K.OffsetRow(section, L["Offset"], function()
        local key = Options.selectedComponent
        if not key then return end
        if not Options:SetEditorComponentPosition(key, tonumber(offset.x:GetText()), tonumber(offset.y:GetText()), false) then
            Options:RefreshEditorInspectorContext()
        end
    end)
    K.Add(section, offset, function() return Selection().movable end)
    Options.editorCoordinateControls = offset
    Options.editorCoordinateX, Options.editorCoordinateY = offset.x, offset.y
    local scaleRange = Schema.layoutRanges.scale
    local scaleRow, scale = K.SliderRow(section, L["Scale"], {
        min = scaleRange[1], max = scaleRange[2], step = 0.05, format = PercentText,
        name = WidgetName("editor_component_scale", "Slider"),
        get = function()
            local position = SelectedPosition()
            return position and position.scale or 1
        end,
        -- While dragged only the preview follows; letting go refreshes the inspector.
        drag = function(value)
            if not Options.selectedComponent then return false end
            return Options:SetEditorComponentScale(Options.selectedComponent, value, true)
        end,
        set = function(value)
            if not Options.selectedComponent then return false end
            return Options:SetEditorComponentScale(Options.selectedComponent, value)
        end,
    })
    K.Add(section, scaleRow, function() return SelectedPosition() ~= nil end)
    Options.editorComponentScaleSlider, Options.editorComponentScaleText = scale, scale.valueText
    Options.editorAnchorDropdown, Options.editorBehaviourControl = anchor, behaviour
    Register(anchor)
    Options.editorPlacementRefresh = function()
        anchor:Refresh()
        behaviour:Refresh()
    end
    K.Add(page, section, function() return Selection().key ~= nil end)
end

-- A bar's own width or height, or the health bar's (the tick); moving the slider unticks it.
local function BarSize(section, label, key, followLabel)
    local function Effective()
        local profile = Profile()
        return profile and (profile[key] or profile.width)
    end
    local range = optionalRanges[key]
    local row, slider = K.SliderRow(section, label, {
        min = range[1], max = range[2], step = key:find("Width") and 2 or 1,
        name = WidgetName("selected_bar_" .. key, "Slider"), get = Effective,
        drag = function(value)
            if not PS.SetPlateProfileOption(Options.editorProfile, key, value) then return false end
            Options:QueueRefresh()
            return true
        end,
        set = function(value)
            if not PS.SetPlateProfileOption(Options.editorProfile, key, value) then return false end
            Options:Refresh(true)
            return true
        end,
    })
    Register(slider)
    K.Add(section, row)
    local followRow, follow = K.CheckRow(section, nil, {
        text = followLabel,
        get = function()
            local profile = Profile()
            return profile and profile[key] == nil
        end,
        set = function(following)
            PS.SetPlateProfileOption(Options.editorProfile, key, not following and Effective() or nil)
            Options:Refresh(true)
        end,
    })
    Register(follow)
    K.Add(section, followRow)
end

-- Text parts: the name, target's name and the relationship marks.
local function BuildTextContexts(page)
    local nameSection = K.Section(CreateContext(page, "name"), L["TEXT"])
    K.Add(Options.editorContextFrames.name, nameSection)
    K.Add(nameSection, ProfileSliderRow(nameSection, L["Size"], "nameFontSize", profileRanges.nameFontSize, 1,
        PointText):GetParent())
    local getSurnames, setSurnames = SettingControl("showPlayerSurnames")
    local surnameRow, surnames = K.CheckRow(nameSection, L["Surnames"], { text = L["Show player surnames"],
        name = WidgetName("selected_showPlayerSurnames", "Checkbox"), get = getSurnames, set = setSurnames })
    Register(surnames)
    K.Add(nameSection, surnameRow, function() return Options.editorProfile == "friendlyPlayer" end)
    Options.editorSurnameControl = surnames

    local targetSection = K.Section(CreateContext(page, "targetName"), L["TEXT"])
    K.Add(Options.editorContextFrames.targetName, targetSection)
    local getHide, setHide = SettingControl("targetNameHideSelf")
    local hideRow, hide = K.CheckRow(targetSection, nil, { text = L["Hide when it targets you"],
        name = WidgetName("selected_targetNameHideSelf", "Checkbox"), get = getHide, set = setHide })
    Register(hide)
    K.Add(targetSection, hideRow)
    K.Add(targetSection, K.Help(targetSection, L["The client can withhold it in some places; then nothing shows."]))

    -- The quest mark's progress text: this plate type's option, off by default.
    local questSection = K.Section(CreateContext(page, "quest"), L["QUEST MARKER"])
    K.Add(Options.editorContextFrames.quest, questSection)
    local progressRow, progress = K.DropdownRow(questSection, L["Progress"], {
        choices = { { value = "off", label = L["Off"] }, { value = "beside", label = L["Beside the mark"] },
            { value = "instead", label = L["Instead of the mark"] } },
        name = WidgetName("selected_questProgress", "Dropdown"),
        get = function() return ProfileValue("questProgress")() or "off" end,
        set = SetProfileValue("questProgress"),
    })
    Register(progress)
    K.Add(questSection, progressRow)
    local formatRow = K.Row(questSection, L["Show as"])
    local format = K.Segmented(formatRow, {
        name = WidgetName("selected_questProgressFormat", "Choice"),
        choices = { { value = "count", label = L["Count"], tooltip = L["Done and needed, as 3/8."] },
            { value = "percent", label = L["Percent"], tooltip = L["How far along, as 38%."] } },
        get = function() return ProfileValue("questProgressFormat")() or "count" end,
        set = SetProfileValue("questProgressFormat"),
    })
    Register(format)
    K.Add(questSection, formatRow, function() return (ProfileValue("questProgress")() or "off") ~= "off" end)
    K.Add(questSection, K.Help(questSection, L["The objective's progress from your quest log, when the game shares "
        .. "it; otherwise nothing shows. Custom text can show it too: {quest.progress} or {quest.percent}."]))

    local lootSection = K.Section(CreateContext(page, "questLoot"), L["QUEST LOOT MARKER"])
    K.Add(Options.editorContextFrames.questLoot, lootSection)
    -- The loot bag follows the quest mark unless freed; freeing or re-anchoring keeps it in place.
    local lootRow, loot = K.CheckRow(lootSection, nil, {
        text = L["Anchor to the quest marker"],
        get = function()
            local position = Options.editorLayout and Options.editorLayout.questLoot
            return position and position.parent == "quest"
        end,
        set = function(anchored)
            if PS.SetComponentAnchor("questLoot", anchored and "quest" or nil, Options.editorProfile,
                Options:CurrentEditorVariant()) then
                Options:ReloadEditorLayoutCopy()
                Options:RefreshEditorLayout()
                Options:RefreshEditorInspectorContext()
            end
        end,
    })
    Register(loot)
    K.Add(lootSection, lootRow)

    local badgeSection = K.Section(CreateContext(page, "relationshipIcon"), L["FRIENDLY PLAYER BADGES"])
    K.Add(Options.editorContextFrames.relationshipIcon, badgeSection)
    for _, badge in ipairs({ { "showGroupIcon", L["Above group members"] }, { "showGuildIcon", L["Above guild members"] } }) do
        local get, set = SettingControl(badge[1])
        local row, checkbox = K.CheckRow(badgeSection, nil, { text = badge[2],
            name = WidgetName("selected_" .. badge[1], "Checkbox"), get = get, set = set })
        Register(checkbox)
        K.Add(badgeSection, row)
    end

    local pvpSection = K.Section(CreateContext(page, "pvpIcon"), L["FRIENDLY PLAYER PVP"])
    K.Add(Options.editorContextFrames.pvpIcon, pvpSection)
    local getPvp, setPvp = SettingControl("friendlyPvpStyle")
    local pvpRow, pvp = K.DropdownRow(pvpSection, L["Display"], { choices = model.friendlyPvpChoices,
        name = WidgetName("selected_friendlyPvpStyle", "Dropdown"), get = getPvp, set = setPvp })
    Register(pvp)
    K.Add(pvpSection, pvpRow)

    local markSection = K.Section(CreateContext(page, "classification"), L["ENEMY CLASSIFICATION"])
    K.Add(Options.editorContextFrames.classification, markSection)
    local getMark, setMark = SettingControl("classificationStyle")
    local markRow, mark = K.DropdownRow(markSection, L["Style"], { choices = model.classificationStyleChoices,
        name = WidgetName("selected_classificationStyle", "Dropdown"), get = getMark, set = setMark })
    Register(mark)
    K.Add(markSection, markRow)
    K.Add(markSection, K.Help(markSection, L["Icons: gold dragon elite, silver dragon rare or rare elite, skull world boss."]))

    -- The threat text's form, shared by every plate type (and the Tank window's threat column).
    local threatSection = K.Section(CreateContext(page, "threat"), L["THREAT TEXT"])
    K.Add(Options.editorContextFrames.threat, threatSection)
    local getThreat, setThreat = SettingControl("threatTextFormat")
    local threatRow, threatFormat = K.DropdownRow(threatSection, L["Threat text"], {
        choices = { { value = "gap", label = L["% and gap"] }, { value = "percent", label = L["% only"] },
            { value = "detailed", label = L["Detailed (lead % and raw threat)"] } },
        name = WidgetName("selected_threatTextFormat", "Dropdown"), get = getThreat, set = setThreat })
    Register(threatFormat)
    K.Add(threatSection, threatRow)
    K.Add(threatSection, K.Help(threatSection, L["% and gap: your threat and the margin the threat windows show "
        .. "(+ your margin while you hold it, - how far you are from pulling it). Where the game keeps the "
        .. "numbers private, only the % shows. Custom text can show more: {threat.percent} {threat.lead} "
        .. "{threat.leadpercent} {threat.raw}."]))
    -- The kept gap (the threat service's KeepBorrowedLead): how long, how it looks, and its age.
    local keptRows = {
        { "threatKeptHold", L["Keep last gap for"], {
            { value = "5", label = L["5 s"] }, { value = "10", label = L["10 s"] }, { value = "15", label = L["15 s"] },
            { value = "30", label = L["30 s"] }, { value = "until", label = L["Until it dies or leaves"] } },
            L["Where the game keeps your threat private, a gap read through your target, mouseover, focus, a boss or "
            .. "a group member's target stays on the plate (marked ~) after that unit moves on, for this long. "
            .. "Until it dies or leaves: while that enemy's plate is shown."] },
        { "threatKeptStyle", L["Stale gap"], {
            { value = "dim", label = L["Dim"] }, { value = "fade", label = L["Fade with age"] },
            { value = "grey", label = L["Grey"] } },
            L["How a kept gap shows it is not live. Dim: the threat windows dim it. Fade with age: it fades as it "
            .. "gets older, on plates and windows. Grey: grey instead of the threat colour."] },
    }
    for _, spec in ipairs(keptRows) do
        local get, set = SettingControl(spec[1])
        local row, dropdown = K.DropdownRow(threatSection, spec[2], { choices = spec[3],
            name = WidgetName("selected_" .. spec[1], "Dropdown"), get = get, set = set })
        Register(dropdown)
        K.AttachHelp(row, spec[4])
        K.Add(threatSection, row)
    end
    local getAge, setAge = SettingControl("threatKeptAge")
    local ageRow, age = K.CheckRow(threatSection, L["Gap age"], { text = L["Show gap age"],
        name = WidgetName("selected_threatKeptAge", "Checkbox"), get = getAge, set = setAge })
    Register(age)
    K.AttachHelp(ageRow, L["Adds how many seconds ago a kept gap was read, as ~100%  +145  3s."])
    K.Add(threatSection, ageRow)

    local comboSection = K.Section(CreateContext(page, "combo"), L["COMBO POINTS"])
    K.Add(Options.editorContextFrames.combo, comboSection)
    K.Add(comboSection, K.Help(comboSection, L["Shows on your target's plate only, while you have combo points: a rogue, "
        .. "or a druid in cat form. Style sets the pips' colours, size and spacing. Custom text can show the count: {combo}."]))

    local targetedSection = K.Section(CreateContext(page, "targetedBy"), L["TARGETED BY"])
    K.Add(Options.editorContextFrames.targetedBy, targetedSection)
    K.Add(targetedSection, K.Help(targetedSection, L["A small badge for each group member targeting this enemy, in their "
        .. "class colour: your party, or a raid's tanks (up to four). Shown only where the game says who is targeting; "
        .. "otherwise the badge stays hidden. Style sets the size, spacing, direction and initials."]))

    -- Parts with nothing of their own beyond Placement, Style and Rules.
    for _, key in ipairs({ "level", "guild", "raidIcon", "other" }) do CreateContext(page, key) end
end

-- Bars: health (its size, the plate's bar texture and colour), power and cast.
local function BuildBarContexts(page)
    local health = K.Section(CreateContext(page, "health"), L["BAR"])
    K.Add(Options.editorContextFrames.health, health)
    for _, bar in ipairs({ { L["Width"], "width", 2 }, { L["Height"], "healthHeight", 1 } }) do
        local slider = ProfileSliderRow(health, bar[1], bar[2], profileRanges[bar[2]], bar[3])
        K.Add(health, slider:GetParent())
    end
    -- The plate's texture (healthTexture) draws every bar on the plate; Style > Bar's texture
    -- (a part's style) overrides it for one bar.
    local textureRow, texture = K.DropdownRow(health, L["Plate texture"], {
        choices = function() return PS.Media.StatusBarChoices() end,
        name = WidgetName("selected_healthTexture", "Dropdown"),
        get = ProfileValue("healthTexture"), set = SetProfileValue("healthTexture"),
    })
    Register(texture)
    K.Add(health, textureRow)
    K.Add(health, K.ControlHelp(health, L["Every bar on this plate, unless its Style picks its own."]))
    -- Choosing a colour switches the bar to it; cancelling restores both colour and mode.
    local modeBeforePicker
    local colourRow, colourSwatch = K.SwatchRow(health, L["Colour"], {
        beforeOpen = function() modeBeforePicker = ProfileValue("healthColourMode")() end,
        get = ProfileValue("healthColour"),
        set = function(r, g, b)
            PS.SetPlateProfileHealthColour(Options.editorProfile, r, g, b)
            Options:Refresh(true)
        end,
        cancel = function(previous)
            PS.SetPlateProfileHealthColour(Options.editorProfile, previous.r, previous.g, previous.b)
            PS.SetPlateProfileOption(Options.editorProfile, "healthColourMode", modeBeforePicker)
            Options:Refresh(true)
        end,
    })
    Register(colourSwatch)
    Register(K.RowCheck(colourRow, {
        text = L["Custom"],
        get = function() return ProfileValue("healthColourMode")() == "custom" end,
        set = function(custom) SetProfileValue("healthColourMode")(custom and "custom" or "automatic") end,
    }))
    K.Add(health, colourRow)

    local power = K.Section(CreateContext(page, "power"), L["POWER BAR"])
    K.Add(Options.editorContextFrames.power, power)
    K.Add(power, ProfileSliderRow(power, L["Height"], "powerHeight", profileRanges.powerHeight, 1):GetParent())
    BarSize(power, L["Width"], "powerWidth", L["Same width as the health bar"])
    K.Add(power, K.Help(power, L["Hidden when the client reports no power."]))

    local cast = K.Section(CreateContext(page, "cast"), L["CAST BAR"])
    K.Add(Options.editorContextFrames.cast, cast)
    BarSize(cast, L["Width"], "castWidth", L["Same width as the health bar"])
    -- The cast bar's height is its own (the health bar's height never changes it).
    K.Add(cast, ProfileSliderRow(cast, L["Height"], "castHeight", optionalRanges.castHeight, 1):GetParent())
    -- Its spell icon, time left and spell name (the profile's cast options).
    local iconRow = K.Row(cast, L["Icon"])
    local icon = K.Segmented(iconRow, {
        name = WidgetName("selected_castIcon", "Choice"),
        choices = { { value = "left", label = L["Left"], tooltip = L["The spell's icon left of the bar."] },
            { value = "right", label = L["Right"], tooltip = L["The spell's icon right of the bar."] },
            { value = "off", label = L["Off"], tooltip = L["No icon."] } },
        get = function() return ProfileValue("castIcon")() or "left" end,
        set = SetProfileValue("castIcon"),
    })
    Register(icon)
    K.Add(cast, iconRow)
    for _, option in ipairs({ { "castTime", L["Time left"], L["Show time left"] },
        { "castName", L["Spell"], L["Show the spell's name"] } }) do
        local key = option[1]
        local row, checkbox = K.CheckRow(cast, option[2], {
            text = option[3], name = WidgetName("selected_" .. key, "Checkbox"),
            get = function() return ProfileValue(key)() ~= false end,
            set = SetProfileValue(key),
        })
        Register(checkbox)
        K.Add(cast, row)
    end
    -- Colour by interrupt (Nameplates/Interrupt.lua): three colours, shown while it is on. Colours
    -- are written whole (a new castColours), never changed in place.
    local function CastCheck(key, label, text)
        local row, checkbox = K.CheckRow(cast, label, {
            text = text, name = WidgetName("selected_" .. key, "Checkbox"),
            get = function() return ProfileValue(key)() == true end,
            set = SetProfileValue(key),
        })
        Register(checkbox)
        K.Add(cast, row)
    end
    CastCheck("castInterruptColours", L["Colour"], L["Colour by interrupt"])
    local function ByInterrupt() return ProfileValue("castInterruptColours")() == true end
    for _, swatch in ipairs({ { "ready", L["Ready"] }, { "cooldown", L["On cooldown"] }, { "locked", L["Can't interrupt"] } }) do
        local which = swatch[1]
        local row, control = K.SwatchRow(cast, swatch[2], {
            get = function() return Schema.NormalizeCastColours(ProfileValue("castColours")())[which] end,
            set = function(r, g, b)
                local colours = Schema.NormalizeCastColours(ProfileValue("castColours")())
                colours[which] = { r = r, g = g, b = b }
                SetProfileValue("castColours")(colours)
            end,
        })
        Register(control)
        K.Add(cast, row, ByInterrupt)
    end
    K.Add(cast, K.Help(cast, L["Ready: the cast can be interrupted and your interrupt is ready. On cooldown: it can, but "
        .. "yours is not ready or you have none. Where the game withholds either, the bar keeps its own colour."]), ByInterrupt)
    CastCheck("castOnTop", L["Layer"], L["Draw casts above other plates"])
    K.Add(cast, K.Help(cast, L["A casting plate draws over its neighbours where plates overlap; your target stays on top."]))
end

-- Custom values: a live value, custom text, or a shape (bar, box, icon).
local function BuildValueContext(page)
    local context = CreateContext(page, "value")
    local section = K.Section(context, L["LIVE VALUE"])
    K.Add(context, section)
    -- light: while dragged or typed, only the preview follows (once a frame). The full refresh
    -- redraws the inspector too; reselect when the part's controls change with it (its source).
    local function WriteSlot(field, value, reselect, light)
        local slot, key = SelectedSlot()
        if not slot or not PS.SetPlateValueSlot(Options.editorProfile, key, field, value) then return false end
        if light then
            Options:QueueRefresh()
            return true
        end
        Options:RefreshEditorAppearance(PS.GetSettings())
        if reselect then Options:SelectEditorComponent(key) end
        return true
    end
    local function SlotField(field)
        return function()
            local slot = SelectedSlot()
            return slot and slot[field]
        end
    end
    local function Kind()
        local slot = SelectedSlot()
        return slot and slot.kind
    end
    local function Custom()
        local slot = SelectedSlot()
        return slot and slot.source == "template" and not slot.kind
    end
    local controls = {}
    -- A bar's fill comes from a percentage; a text value from any source.
    local sourceRow, source = K.DropdownRow(section, L["Source"], {
        placeholder = L["Choose value"], name = WidgetName("selected_value_source", "Dropdown"),
        choices = function() return Kind() == "bar" and catalog.barSourceChoices or catalog.valueSourceChoices end,
        get = SlotField("source"),
        set = function(value) WriteSlot("source", value, true) end,
    })
    controls[#controls + 1] = source
    -- Refreshed with every setting-bound control (Options:Refresh) as well as with the part.
    Register(source)
    K.Add(section, sourceRow, function() return Kind() == nil or Kind() == "bar" end)
    -- An icon's picture, in the source's place.
    local iconRow, icon = K.DropdownRow(section, L["Picture"], {
        choices = catalog.iconChoices, name = WidgetName("selected_value_icon", "Dropdown"),
        get = function() return SlotField("icon")() or "raid8" end,
        set = function(value) WriteSlot("icon", value) end,
    })
    controls[#controls + 1] = icon
    Register(icon)
    K.Add(section, iconRow, function() return Kind() == "icon" end)
    -- A shape's size (bar, box, icon).
    local shape = K.Group(section)
    local function ShapeSize(field, index)
        return function()
            local slot = SelectedSlot()
            local size = slot and PS.ValueGraphicSize and PS.ValueGraphicSize[slot.kind]
            return slot and (slot[field] or (size and size[index])) or 10
        end
    end
    for index, entry in ipairs({ { "width", L["Width"], Schema.VALUE_WIDTH }, { "height", L["Height"], Schema.VALUE_HEIGHT } }) do
        local field, range = entry[1], entry[3]
        local row, slider = K.SliderRow(shape, entry[2], {
            min = range[1], max = range[2], step = 1, get = ShapeSize(field, index),
            drag = function(value) return WriteSlot(field, value, false, true) end,
            set = function(value) return WriteSlot(field, value) end,
        })
        controls[#controls + 1] = slider
        K.Add(shape, row)
    end
    K.Add(section, shape, function() return Kind() ~= nil end)
    Options.editorValueShapeBox, Options.editorValueIconDropdown = shape, icon
    -- Custom text: the template, written live (the preview shows it with sample values), and
    -- what is wrong with it while it does not compile.
    local template = K.Group(section)
    local templateLabel = K.Add(template, K.Row(template, L["Text"]))
    local templateBlock = K.Add(template, CreateFrame("Frame", nil, template))
    templateBlock:SetSize(K.WIDTH, K.TEMPLATE_H)
    templateBlock.flowBefore = K.SUB_GAP
    local templateEdit = Controls.EditBox(templateBlock, { width = K.WIDTH, height = K.TEMPLATE_H, fontSize = K.FIELD_FONT,
        multiLine = true, maxLetters = Schema.TEMPLATE_LENGTH, insets = { K.CARD_PAD, K.CARD_PAD, K.SUB_GAP, K.SUB_GAP },
        fill = { 0.06, 0.05, 0.04, 0.92 } })
    templateEdit:SetPoint("TOPLEFT", templateBlock, "TOPLEFT", 0, 0)
    local statusLine = K.Add(template, K.Help(template, ""))
    statusLine.flowBefore = K.SUB_GAP
    local templateStatus = statusLine.text
    local function ShowTemplateStatus(text)
        local _, reason = PS.Template.Compile(text or "")
        if text == nil or text == "" then
            templateStatus:SetText(L["Type text with {tokens}; hover ? for the list."])
            K.Ink(templateStatus, "muted")
        elseif reason then
            templateStatus:SetText(reason)
            K.Ink(templateStatus, "error")
        else
            templateStatus:SetText(L["OK"])
            K.Ink(templateStatus, "ok")
        end
    end
    templateEdit:SetScript("OnTextChanged", function(edit, userInput)
        if not userInput then return end
        local text = edit:GetText():gsub("[%c]", "")
        -- The limit is in bytes (SetMaxLetters counts characters): past it, the edit is undone.
        if #text > Schema.TEMPLATE_LENGTH then
            local slot = SelectedSlot()
            edit:SetText(slot and slot.template or "")
            return
        end
        WriteSlot("template", text, false, true)
        ShowTemplateStatus(text)
    end)
    templateEdit:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    templateEdit:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
    local templateHelp = HelpButton(templateLabel, L["Custom text"], {
        L["Tokens: {health} {health.max} {health.percent} {health.missing} {power} {power.max} {power.percent} "
            .. "{threat.percent} {threat.lead} {threat.leadpercent} {threat.raw} {threat.hold} {level} {level.smart} {level.diff} {name} "
            .. "{target} {guild} {classification} {cast.name} {quest.progress} {quest.percent} {combo}. Short names: hp maxhp "
            .. "hpp pp ppp tp."],
        L["Modifiers: {health:short} 1.2k, {health.percent:1} one decimal, {name:upper} {name:lower}, "
            .. "{name:max:10}, {target:else:none} when missing."],
        L["Conditions: [if health.percent < 35]LOW[elseif elite]ELITE[else]{health}[end]. Use and, or, not, "
            .. "brackets and < <= > >= = !=."],
        L["Flags for conditions: tagged elite rare boss casting interruptible interruptReady combat tanking targeted focus quest "
            .. "questdrop friendly hostile neutral player pvp instance ingroup inguild role.tank threat.holding "
            .. "threat.losing threat.pulling threat.other threat.offtank hastarget inrange; level.diff is a number."],
        { L["A protected or missing value still shows, but a condition on it is unknown and counts as not true "
            .. "(not included), so [else] shows."], 0.86, 0.86, 0.86 },
    }, true)
    templateHelp:SetPoint("RIGHT", templateLabel, "RIGHT", 0, 0)
    K.Add(section, template, Custom)
    Options.editorTemplateEdit, Options.editorTemplateStatus, Options.editorTemplateBox = templateEdit, templateStatus, template
    K.Add(section, K.Help(section, L["Anchor it to a bar to show it on the bar; it hides while that bar is hidden."]),
        function() return not Custom() and Kind() == nil end)
    local sizeRange = Schema.valueFontRange
    local sizeRow, size = K.SliderRow(section, L["Size"], {
        min = sizeRange[1], max = sizeRange[2], step = 1, format = PointText, get = SlotField("fontSize"),
        drag = function(value) return WriteSlot("fontSize", value, false, true) end,
        set = function(value) return WriteSlot("fontSize", value) end,
    })
    controls[#controls + 1] = size
    K.Add(section, sizeRow, function() return Kind() == nil end)
    local colourRow, colour = K.SwatchRow(section, L["Colour"], {
        get = SlotField("colour"),
        set = function(r, g, b) WriteSlot("colour", { r = r, g = g, b = b }) end,
    })
    controls[#controls + 1] = colour
    K.Add(section, colourRow)
    local layerRow = K.Row(section, L["Layer"])
    local layer = K.Segmented(layerRow, {
        choices = { { value = "back", label = L["Behind"], tooltip = L["Behind the plate's own parts."] },
            { value = "front", label = L["In front"], tooltip = L["In front of the plate's own parts."] } },
        get = function()
            local slot = SelectedSlot()
            return slot and slot.layer == "back" and "back" or "front"
        end,
        set = function(value)
            local key = Options.selectedComponent
            if key and key:match("^value%d+$") and PS.SetPlateValueSlot(Options.editorProfile, key, "layer", value) then
                Options:RefreshEditorAppearance(PS.GetSettings())
            end
        end,
    })
    controls[#controls + 1] = layer
    K.Add(section, layerRow)
    Options.valueControlsRefresh = function()
        local slot = SelectedSlot()
        if not slot then return end
        for _, control in ipairs(controls) do control:Refresh() end
        section.title:SetText(slot.kind == "icon" and L["PICTURE"] or slot.kind == "bar" and L["FILLS WITH"]
            or slot.kind == "box" and L["BOX"] or L["LIVE VALUE"])
        local custom = Custom()
        if custom and not (templateEdit.HasFocus and templateEdit:HasFocus()) then templateEdit:SetText(slot.template or "") end
        if custom then ShowTemplateStatus(slot.template) end
    end
end

-- Aura rows: which auras show, and their grid.
local function BuildAuraContexts(page)
    local ranges = Schema.auraLayoutRanges
    for _, definition in ipairs({ { key = "buffs", source = "buffSource" }, { key = "debuffs", source = "debuffSource" } }) do
        local kind = definition.key
        local context = CreateContext(page, kind)
        local function Layout(field) return function()
            local profile = Profile()
            return profile and profile.auraLayouts and profile.auraLayouts[kind][field]
        end end
        -- light: a slider's step, which only the preview follows (once a frame).
        local function Write(field, light) return function(value)
            if not PS.SetPlateAuraLayout(Options.editorProfile, kind, field, value) then return false end
            if light then Options:QueueRefresh() else Options:RefreshEditorAppearance(PS.GetSettings()) end
            return true
        end end
        local which = K.Section(context, L["WHICH AURAS"])
        K.Add(context, which)
        local getSource, setSource = SettingControl(definition.source)
        local sourceRow, source = K.DropdownRow(which, L["Source"], { choices = model.auraSourceChoices,
            name = WidgetName("selected_" .. definition.source, "Dropdown"), get = getSource, set = setSource })
        Register(source)
        K.Add(which, sourceRow)
        local timeRow, time = K.CheckRow(which, L["Time left"], { text = L["Show time left"],
            get = Layout("showDuration"), set = Write("showDuration") })
        Register(time)
        K.Add(which, timeRow)
        local grid = K.Section(context, L["GRID"])
        K.Add(context, grid)
        for _, spec in ipairs({ { "count", L["Icons"], tostring }, { "columns", L["Per line"], tostring },
            { "size", L["Size"], PixelText }, { "spacing", L["Spacing"], PixelText } }) do
            local field = spec[1]
            local row, slider = K.SliderRow(grid, spec[2], {
                min = ranges[field][1], max = ranges[field][2], step = 1, format = spec[3],
                name = WidgetName("editor_" .. kind .. "_" .. field, "Slider"),
                get = Layout(field), drag = Write(field, true), set = Write(field),
            })
            Register(slider)
            K.Add(grid, row)
        end
        local growRow = K.Row(grid, L["Grow"])
        Register(K.Segmented(growRow, {
            choices = { { value = "right", label = L["L to R"], tooltip = L["Left to right"] },
                { value = "left", label = L["R to L"], tooltip = L["Right to left"] },
                { value = "centre", label = L["Centre"], tooltip = L["From the centre"] } },
            get = Layout("growX"), set = Write("growX"),
        }))
        K.Add(grid, growRow)
        local linesRow = K.Row(grid, L["More lines"])
        Register(K.Segmented(linesRow, {
            choices = { { value = "up", label = L["Up"], tooltip = L["Stack upwards"] },
                { value = "down", label = L["Down"], tooltip = L["Stack downwards"] } },
            get = Layout("growY"), set = Write("growY"),
        }))
        K.Add(grid, linesRow)
    end
end

-- Style: how a text, bar, pip or badge part is drawn. Text: font, outline, shadow and a box behind it.
-- Bars: texture, background and border. Pips (combo points): colours, size and spacing. Badges
-- ("Targeted by"): size, spacing, direction and initials.
local STYLE_TEXT = { name = true, level = true, guild = true, targetName = true, threat = true, tagged = true,
    classification = true }
local STYLE_BAR = { health = true, power = true, cast = true }
local function StyleKind(key)
    if STYLE_BAR[key] then return "bar" end
    if key == "combo" then return "pips" end
    if key == "targetedBy" then return "badges" end
    if type(key) == "string" and key:match("^value%d+$") then
        -- A custom part styles as what it is: a bar as a bar, text as text; boxes and icons have none.
        local profile = Profile()
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        local kind = slot and slot.kind
        if kind == "bar" then return "bar" end
        if kind then return nil end
        return "text"
    end
    if STYLE_TEXT[key] then return "text" end
end
-- Parts a rule can colour (a text's colour, a bar's fill).
local COLOURABLE = { health = true, power = true, cast = true, name = true, level = true, guild = true,
    threat = true, tagged = true, targetName = true, classification = true }
local function Colourable(key)
    return COLOURABLE[key] or (type(key) == "string" and key:match("^value%d+$") ~= nil)
end

local function BuildStyle(page)
    local section = K.Section(page, L["STYLE"])
    Options.editorStyleBlock = section
    local function Style()
        local key = Options.selectedComponent
        local profile = Profile()
        return key and profile and profile.styles and profile.styles[key] or {}
    end
    local controls = {}
    local function Keep(control)
        controls[#controls + 1] = control
        return Register(control)
    end
    -- light: while a slider drags, only the preview follows (once a frame); letting go refreshes all.
    local function WriteStyle(field, value, light)
        local key = Options.selectedComponent
        if not key or not PS.SetPartStyle(Options.editorProfile, key, field, value) then return false end
        if light then
            Options:QueueRefresh()
            return true
        end
        Options:RefreshEditorAppearance(PS.GetSettings())
        for _, control in ipairs(controls) do control:Refresh() end
        return true
    end
    local function Text() return StyleKind(Options.selectedComponent) == "text" end
    local function Bar() return StyleKind(Options.selectedComponent) == "bar" end
    -- Colours are written whole, never changed in place.
    local function SwatchRow(label, field, fallback, alpha)
        local row, swatch = K.SwatchRow(section, label, {
            alpha = alpha,
            get = function() return Style()[field] or fallback end,
            drag = function(r, g, b, a) return WriteStyle(field, { r = r, g = g, b = b, a = a }, true) end,
            set = function(r, g, b, a) return WriteStyle(field, { r = r, g = g, b = b, a = alpha and a or 1 }) end,
        })
        Keep(swatch)
        return row
    end
    -- A size in pixels on a swatch's row (border width): a slider like every other.
    local function SizeAfterSwatch(row, field, range, fallback)
        Keep(K.Slider(row, {
            min = range[1], max = range[2], step = 1,
            get = function() return Style()[field] or fallback end,
            drag = function(value) return WriteStyle(field, value, true) end,
            set = function(value) return WriteStyle(field, value) end,
        }))
    end
    local function DropdownRow(label, field, choices, name)
        local row, dropdown = K.DropdownRow(section, label, {
            choices = choices, name = WidgetName(name, "Dropdown"),
            get = function() return Style()[field] or "" end,
            set = function(value) WriteStyle(field, value ~= "" and value or nil) end,
        })
        Keep(dropdown)
        return row
    end
    -- clear: unticked removes the field (nil), rather than storing false.
    local function CheckRow(label, field, clear, text)
        local row, checkbox = K.CheckRow(section, label, { text = text,
            get = function() return Style()[field] == true end,
            set = function(on)
                if clear and not on then WriteStyle(field, nil) else WriteStyle(field, on) end
            end,
        })
        Keep(checkbox)
        return row
    end

    -- Text: font, outline and shadow; then the box behind it (its fill and border with their opacity).
    K.Add(section, K.SubHeader(section, L["Text"]), Text)
    K.Add(section, DropdownRow(L["Font"], "font", function()
        local choices = { { value = "", label = L["Plate font"] } }
        for _, choice in ipairs(PS.Media.FontChoices()) do
            if choice.value ~= "default" then choices[#choices + 1] = choice end
        end
        return choices
    end, "selected_style_font"), Text)
    K.Add(section, DropdownRow(L["Outline"], "outline", { { value = "", label = L["Plate outline"] },
        { value = "none", label = L["None"] }, { value = "outline", label = L["Outline"] },
        { value = "thick", label = L["Thick outline"] } }, "selected_style_outline"), Text)
    K.Add(section, CheckRow(L["Shadow"], "shadow", nil, L["Drop shadow"]), Text)
    K.Add(section, K.SubHeader(section, L["Box behind"]), Text)
    K.Add(section, CheckRow(L["Box"], "box", true, L["Show a box"]), Text)
    K.Add(section, SwatchRow(L["Fill"], "boxColour", STYLE_DEFAULTS.boxColour, true), Text)
    local boxBorder = SwatchRow(L["Border"], "boxBorder", STYLE_DEFAULTS.boxBorder, true)
    K.Add(section, boxBorder, Text)
    local paddingRow, padding = K.SliderRow(section, L["Padding"], {
        min = Schema.STYLE_PADDING[1], max = Schema.STYLE_PADDING[2], step = 1,
        get = function() return Style().padding or STYLE_DEFAULTS.padding end,
        drag = function(value) return WriteStyle("padding", value, true) end,
        set = function(value) return WriteStyle("padding", value) end,
    })
    Keep(padding)
    K.Add(section, paddingRow, Text)

    -- Pips (combo points): the filled and empty colours with their opacity, each pip's size and the gap.
    local function Pips() return StyleKind(Options.selectedComponent) == "pips" end
    K.Add(section, K.SubHeader(section, L["Pips"]), Pips)
    K.Add(section, SwatchRow(L["Filled"], "pipFill", STYLE_DEFAULTS.pipFill, true), Pips)
    K.Add(section, SwatchRow(L["Empty"], "pipEmpty", STYLE_DEFAULTS.pipEmpty, true), Pips)
    for _, size in ipairs({ { L["Width"], "pipWidth" }, { L["Height"], "pipHeight" }, { L["Spacing"], "pipSpacing" } }) do
        local field, range = size[2], Schema.STYLE_PIPS[size[2]]
        local row, slider = K.SliderRow(section, size[1], {
            min = range[1], max = range[2], step = 1,
            get = function() return Style()[field] or STYLE_DEFAULTS[field] end,
            drag = function(value) return WriteStyle(field, value, true) end,
            set = function(value) return WriteStyle(field, value) end,
        })
        Keep(slider)
        K.Add(section, row, Pips)
    end

    -- Badges ("Targeted by"): each badge's size and the gap, the row's direction, and initials.
    local function Badges() return StyleKind(Options.selectedComponent) == "badges" end
    K.Add(section, K.SubHeader(section, L["Badges"]), Badges)
    for _, size in ipairs({ { L["Size"], "badgeSize" }, { L["Spacing"], "badgeSpacing" } }) do
        local field, range = size[2], Schema.STYLE_BADGES[size[2]]
        local row, slider = K.SliderRow(section, size[1], {
            min = range[1], max = range[2], step = 1,
            get = function() return Style()[field] or STYLE_DEFAULTS[field] end,
            drag = function(value) return WriteStyle(field, value, true) end,
            set = function(value) return WriteStyle(field, value) end,
        })
        Keep(slider)
        K.Add(section, row, Badges)
    end
    local orientationRow, orientation = K.DropdownRow(section, L["Direction"], {
        choices = { { value = "horizontal", label = L["Row"] }, { value = "vertical", label = L["Column"] } },
        name = WidgetName("selected_style_badge_direction", "Dropdown"),
        get = function() return Style().badgeOrientation or STYLE_DEFAULTS.badgeOrientation end,
        set = function(value) WriteStyle("badgeOrientation", value) end,
    })
    Keep(orientation)
    K.Add(section, orientationRow, Badges)
    -- Initials are on unless the style says false.
    local initialsRow, initials = K.CheckRow(section, L["Initials"], { text = L["Show each member's initial"],
        get = function() return Style().badgeInitial ~= false end,
        set = function(on) WriteStyle("badgeInitial", on and nil or false) end,
    })
    Keep(initials)
    K.Add(section, initialsRow, Badges)

    -- Bars: texture, then the background with its opacity and the border with its width.
    K.Add(section, K.SubHeader(section, L["Bar"]), Bar)
    K.Add(section, DropdownRow(L["Own texture"], "texture", function()
        local choices = { { value = "", label = L["Same as plate"] } }
        for _, choice in ipairs(PS.Media.StatusBarChoices()) do choices[#choices + 1] = choice end
        return choices
    end, "selected_style_texture"), Bar)
    K.Add(section, SwatchRow(L["Background"], "background", STYLE_DEFAULTS.background, true), Bar)
    local barBorder = SwatchRow(L["Border"], "borderColour", { r = 0, g = 0, b = 0, a = 1 })
    SizeAfterSwatch(barBorder, "border", Schema.STYLE_BORDER, 0)
    K.Add(section, barBorder, Bar)

    -- Presets: built-in looks and your saved ones, for this kind of part. Applying one replaces
    -- the part's style (and its rules, when it has some).
    local function PresetEntries()
        local key = Options.selectedComponent
        local kind = key and StyleKind(key)
        local entries = {}
        local function Apply(preset)
            if PS.ApplyStylePreset(Options.editorProfile, key, preset) then Options:RefreshEditorAppearance(PS.GetSettings()) end
        end
        for _, preset in ipairs(STYLE_PRESETS) do
            if preset.kind == kind then
                entries[#entries + 1] = { text = preset.name, func = function() Apply(preset) end }
            end
        end
        local saved, names = PS.GetState().stylePresets or {}, {}
        for name, preset in pairs(saved) do if preset.kind == kind then names[#names + 1] = name end end
        table.sort(names)
        for _, name in ipairs(names) do
            entries[#entries + 1] = { text = name, func = function() Apply(name) end }
        end
        entries[#entries + 1] = { text = L["Save this style as a preset..."], func = function()
            Options:PromptStudioName(L["Name for this preset:"], "", function(text)
                local profile = Profile()
                local style = profile.styles and profile.styles[key]
                local rules = profile.rules and profile.rules[key]
                if not (style or rules) then return false, L["This part has no style or rules to save yet."] end
                return PS.SaveStylePreset(text, kind, style, rules)
            end)
        end }
        if #names > 0 then
            local deletes = {}
            for _, name in ipairs(names) do
                deletes[#deletes + 1] = { text = name, func = function()
                    Options:ConfirmStudioAction(string.format(L["Delete the preset \"%s\"?"], name), L["Delete"],
                        function() PS.DeleteStylePreset(name) end)
                end }
            end
            entries[#entries + 1] = { text = L["Delete a preset"], children = deletes }
        end
        return entries
    end
    local presets = CreateStudioButton(section.band, L["Presets"], 86, K.BUTTON_H)
    K.Accessory(section, presets)
    presets:SetScript("OnClick", function(instance) Options:ShowEditorMenu(PresetEntries(), instance) end)
    Options.EditorPresetEntries = PresetEntries
    Options.editorStyleRefresh = function()
        if StyleKind(Options.selectedComponent) then
            for _, control in ipairs(controls) do control:Refresh() end
        end
    end
    K.Add(page, section, function() return Selection().key ~= nil and StyleKind(Selection().key) ~= nil end)
end

-- Rules: an ordered list of "when <condition>, then <colour | blend | opacity | hide>" cards.
-- Written whole on each change (PS.SetPartRules); the preview shows them with sample values, or
-- as if every condition held while Preview "as if every condition is true" is ticked.
local function CurrentRules()
    local key = Options.selectedComponent
    local profile = Profile()
    local list = key and profile and profile.rules and profile.rules[key] or {}
    return PS.Table.DeepCopy(list), key
end
-- The full write refreshes the preview, and with it the inspector (these cards too).
local function WriteRules(list, light)
    local key = Options.selectedComponent
    if not key or not PS.SetPartRules(Options.editorProfile, key, #list > 0 and list or nil) then return false end
    if light then Options:QueueRefresh() else Options:RefreshEditorAppearance(PS.GetSettings()) end
    return true
end
-- How many more rules fit: a part keeps MAX_RULES_PER_PART, a plate type MAX_RULES in all.
local function RuleRoom(list)
    local profile, total = Profile(), 0
    for _, rules in pairs(profile and profile.rules or {}) do total = total + #rules end
    return math.max(0, math.min(Schema.MAX_RULES_PER_PART - #list, MAX_RULES - total))
end
local function PresetStops(id)
    for _, preset in ipairs(RULE_PRESETS) do
        if preset.id == id then return PS.Table.DeepCopy(preset.rules[1].stops) end
    end
end

-- A small remove (x) button, at the right end of its row.
local function RemoveButton(row, tip)
    local button = CreateFrame("Button", nil, row)
    button:SetSize(K.SWATCH, K.SWATCH)
    button:SetPoint("RIGHT", row, "RIGHT", -row.inset, 0)
    button:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    button:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    Controls.AttachTooltip(button, L["Remove"], { tip })
    return button
end

-- A plain edit box on a dark fill, CONTROL_H tall, from x in row.
local function FieldBox(row, x, width, maxLetters)
    local edit = Controls.EditBox(row, { width = width, height = K.CONTROL_H, fontSize = K.FIELD_FONT,
        insets = { K.CARD_PAD, K.CARD_PAD }, maxLetters = maxLetters, fill = { 0.06, 0.05, 0.04, 0.92 } })
    edit:SetPoint("LEFT", row, "LEFT", x, 0)
    return edit
end

-- One rule's card (K.Card); cards are made as needed and reused.
local function RuleCard(parent, index)
    local card = K.Card(parent)
    local function Rule()
        local list = CurrentRules()
        return list[index], list
    end
    local pad = K.CARD_PAD
    -- When: an on/off box, then the condition, the whole control column (less the remove at the
    -- card's right). A rule turned off stays in the list, unchanged, and never applies.
    local whenRow = K.Add(card, K.Row(card, nil, pad))
    local enabled = Controls.Checkbox(whenRow, {
        name = WidgetName("selected_rule_enabled_" .. index, "Checkbox"), label = "",
        get = function()
            local rule = Rule()
            return rule ~= nil and rule.enabled ~= false
        end,
        set = function(on)
            local rule, list = Rule()
            if not rule then return end
            -- On is the default, so only a rule turned off stores it.
            if on then rule.enabled = nil else rule.enabled = false end
            WriteRules(list)
        end,
        tooltip = { title = L["Rule on"], lines = { L["Untick to turn this rule off without removing it; tick to turn "
            .. "it back on as it was."] } },
    })
    enabled:ClearAllPoints()
    enabled:SetPoint("LEFT", whenRow, "LEFT", pad, 0)
    whenRow.label = K.Text(whenRow, L["When"], "label")
    whenRow.label:SetPoint("LEFT", whenRow, "LEFT", pad + K.SWATCH + K.SWATCH_GAP, 0)
    whenRow.kitSearchLabel = L["When"]
    local when = FieldBox(whenRow, K.CONTROL_X, whenRow.right - K.SWATCH - K.CONTROL_GAP - K.CONTROL_X, Schema.TEMPLATE_LENGTH)
    K.OnWidth(whenRow, function(width) when:SetWidth(width - pad - K.SWATCH - K.CONTROL_GAP - K.CONTROL_X) end)
    -- Empty holds always: the box says so, dimmed, until something is typed.
    local placeholder = K.Text(when, L["always"], "hint")
    placeholder:SetPoint("LEFT", when, "LEFT", K.CARD_PAD, 0)
    -- A condition longer than the box: the whole of it on hover.
    if when.HookScript then
        when:HookScript("OnEnter", function(self)
            local text = self:GetText() or ""
            if text == "" or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["When"], 1, 0.82, 0)
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        when:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    local remove = RemoveButton(whenRow, L["Remove this rule."])
    -- One line, so a long error never runs into the Then row; the whole of it on hover.
    local statusRow = K.Add(card, K.Row(card, nil, pad), function() return card.statusText ~= nil end)
    statusRow:SetHeight(K.LINE_H)
    statusRow.flowBefore = K.SUB_GAP
    local status = K.Text(statusRow, "", "error")
    status:SetPoint("LEFT", statusRow, "LEFT", K.CONTROL_X, 0)
    K.OnWidth(statusRow, function(width) status:SetWidth(width - pad - K.CONTROL_X) end)
    if status.SetMaxLines then status:SetMaxLines(1) end
    if status.SetWordWrap then status:SetWordWrap(false) end
    statusRow:EnableMouse(true)
    statusRow:SetScript("OnEnter", function(instance)
        if not (GameTooltip and card.statusText) then return end
        GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Rule"])
        GameTooltip:AddLine(card.statusText, 1, 0.82, 0.45, true)
        GameTooltip:Show()
    end)
    statusRow:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Then: what it sets; a colour's swatch at the card's right.
    local thenRow = K.Add(card, K.Row(card, L["Then"], pad))
    local function SetChoices()
        local choices = {}
        if Colourable(Options.selectedComponent) then
            choices[#choices + 1] = { value = "colour", label = L["Set colour"] }
            choices[#choices + 1] = { value = "blend", label = L["Blend by health"] }
        end
        choices[#choices + 1] = { value = "alpha", label = L["Set opacity"] }
        choices[#choices + 1] = { value = "hide", label = L["Hide it"] }
        return choices
    end
    local setDropdown = K.Dropdown(thenRow, {
        choices = SetChoices, name = WidgetName("selected_rule_set_" .. index, "Dropdown"),
        get = function()
            local rule = Rule()
            return rule and rule.set
        end,
        set = function(value)
            local rule, list = Rule()
            if not rule then return end
            rule.set = value
            if value == "colour" and not rule.colour then rule.colour = { r = 0.5, g = 0.5, b = 0.5 } end
            if value == "alpha" and not rule.alpha then rule.alpha = 0.5 end
            if value == "blend" and not rule.stops then rule.stops = PresetStops("healthBlend") end
            WriteRules(list)
        end,
    }, K.CONTROL_X, thenRow.right - K.SWATCH - K.CONTROL_GAP)
    Register(setDropdown)
    local swatch = Controls.ColourSwatch(thenRow, {
        size = K.SWATCH,
        get = function()
            local rule = Rule()
            return rule and rule.colour
        end,
        set = function(r, g, b)
            local rule, list = Rule()
            if not rule then return end
            rule.colour = { r = r, g = g, b = b }
            WriteRules(list)
        end,
    })
    swatch:ClearAllPoints()
    swatch:SetPoint("RIGHT", thenRow, "RIGHT", -pad, 0)
    -- Opacity: its own row under Then, a slider like every other.
    local alphaRow = K.Add(card, K.Row(card, nil, pad), function() return card.rule and card.rule.set == "alpha" end)
    local function WriteAlpha(value, light)
        local rule, list = Rule()
        if not rule then return false end
        rule.alpha = value
        return WriteRules(list, light)
    end
    local alpha = K.Slider(alphaRow, {
        min = 0, max = 1, step = 0.05, format = PercentText,
        get = function()
            local rule = Rule()
            return rule and rule.alpha or 0.5
        end,
        drag = function(value) return WriteAlpha(value, true) end, set = WriteAlpha,
    })
    -- Blend: each stop as [swatch] [at] % (x), then + stop.
    local stopRows = {}
    local function Stops()
        local rule, list = Rule()
        return rule and rule.stops, list
    end
    for stopIndex = 1, Schema.MAX_BLEND_STOPS do
        local row = K.Add(card, K.Row(card, stopIndex == 1 and L["Stops"] or nil, pad), function()
            local rule = card.rule
            return rule and rule.set == "blend" and rule.stops and rule.stops[stopIndex] ~= nil or false
        end)
        row.swatch = Controls.ColourSwatch(row, {
            size = K.SWATCH,
            get = function()
                local stops = Stops()
                return stops and stops[stopIndex] and stops[stopIndex].colour
            end,
            set = function(r, g, b)
                local stops, list = Stops()
                if not (stops and stops[stopIndex]) then return end
                stops[stopIndex].colour = { r = r, g = g, b = b }
                WriteRules(list)
            end,
        })
        row.swatch:ClearAllPoints()
        row.swatch:SetPoint("LEFT", row, "LEFT", K.CONTROL_X, 0)
        local function CommitAt(edit)
            local stops, list = Stops()
            local at = tonumber(edit:GetText())
            if not (stops and stops[stopIndex]) or not at then
                Options:RefreshEditorInspectorContext()
                return
            end
            stops[stopIndex].at = math.floor(math.max(0, math.min(100, at)) + 0.5)
            WriteRules(list)
        end
        local atX = K.CONTROL_X + K.SWATCH + K.CONTROL_GAP
        row.at = FieldBox(row, atX, K.VALUE_W, 3)
        row.at:SetScript("OnEnterPressed", function(edit)
            edit.committed = true
            CommitAt(edit)
            edit:ClearFocus()
        end)
        row.at:SetScript("OnEditFocusGained", function(edit) edit.committed = nil end)
        row.at:SetScript("OnEditFocusLost", function(edit)
            if edit.committed then edit.committed = nil return end
            CommitAt(edit)
        end)
        row.at:SetScript("OnEscapePressed", function(edit)
            edit.committed = true
            edit:ClearFocus()
            Options:RefreshEditorInspectorContext()
        end)
        K.Text(row, L["%"], "value"):SetPoint("LEFT", row, "LEFT", atX + K.VALUE_W + K.CHECK_TEXT_GAP, 0)
        row.remove = RemoveButton(row, string.format(L["Remove this stop (a blend keeps at least %d)."],
            Schema.MIN_BLEND_STOPS))
        row.remove:SetScript("OnClick", function()
            local stops, list = Stops()
            if not stops or #stops <= Schema.MIN_BLEND_STOPS then return end
            table.remove(stops, stopIndex)
            WriteRules(list)
        end)
        stopRows[stopIndex] = row
    end
    local addStopRow, addStop = K.ButtonRow(card, L["+ stop"], 76, nil, K.CONTROL_X)
    K.Add(card, addStopRow, function() return card.rule and card.rule.set == "blend" or false end)
    Controls.AttachTooltip(addStop, L["+ stop"], { string.format(L["A blend has %d to %d stops."], Schema.MIN_BLEND_STOPS,
        Schema.MAX_BLEND_STOPS) })
    addStop:SetScript("OnClick", function()
        local stops, list = Stops()
        if not stops or #stops >= Schema.MAX_BLEND_STOPS then return end
        -- Halfway along the widest gap, in the colour of the stop after it.
        local after = 2
        for stopIndex = 2, #stops do
            if stops[stopIndex].at - stops[stopIndex - 1].at > stops[after].at - stops[after - 1].at then after = stopIndex end
        end
        local low, high = stops[after - 1], stops[after]
        table.insert(stops, after, { at = math.floor((low.at + high.at) / 2 + 0.5), colour = PS.Table.DeepCopy(high.colour) })
        WriteRules(list)
    end)

    local function ShowStatus(rule)
        local text = rule.when or ""
        local tree, reason = PS.Template.CompileCondition(text)
        card.statusText = text ~= "" and not tree and reason or nil
        status:SetText(card.statusText or "")
        placeholder:SetShown(text == "" and not (when.HasFocus and when:HasFocus()))
    end
    when:SetScript("OnTextChanged", function(edit, userInput)
        placeholder:SetShown((edit:GetText() or "") == "" and not (edit.HasFocus and edit:HasFocus()))
        if not userInput then return end
        local rule, list = Rule()
        if not rule then return end
        local text = edit:GetText():gsub("[%c]", "")
        -- The limit is in bytes (SetMaxLetters counts characters): past it, the edit is undone.
        if #text > Schema.TEMPLATE_LENGTH then
            edit:SetText(rule.when or "")
            return
        end
        rule.when = text
        WriteRules(list, true)
        local had = card.statusText ~= nil
        ShowStatus(rule)
        -- The error line comes or goes: the cards under it move.
        if had ~= (card.statusText ~= nil) then Options:LayoutEditorInspector() end
    end)
    when:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    when:SetScript("OnEditFocusLost", function(edit) placeholder:SetShown((edit:GetText() or "") == "") end)
    when:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
    when:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    remove:SetScript("OnClick", function()
        local _, list = Rule()
        table.remove(list, index)
        WriteRules(list)
    end)
    card.when, card.status, card.placeholder, card.setDropdown, card.swatch, card.alpha, card.remove =
        when, status, placeholder, setDropdown, swatch, alpha, remove
    card.stopRows, card.addStop, card.enabled = stopRows, addStop, enabled
    -- Shows the rule; the card's flow (Measure, in the inspector's layout) places its rows.
    function card.Display(instance, rule)
        instance.rule, instance.active = rule, true
        instance:Show()
        if not (when.HasFocus and when:HasFocus()) then
            when:SetText(rule.when or "")
            -- Show a long condition from its start ("role.tank and ..."), not its end.
            if when.SetCursorPosition then when:SetCursorPosition(0) end
        end
        ShowStatus(rule)
        enabled:Refresh()
        setDropdown:Refresh()
        swatch:SetShown(rule.set == "colour")
        if rule.set == "colour" then swatch:Refresh() end
        alpha:SetShown(rule.set == "alpha")
        if rule.set == "alpha" then alpha:Refresh() end
        local stops = rule.set == "blend" and rule.stops or {}
        for stopIndex, row in ipairs(stopRows) do
            local stop = stops[stopIndex]
            if stop then
                row.swatch:Refresh()
                if not (row.at.HasFocus and row.at:HasFocus()) then row.at:SetText(tostring(stop.at)) end
                local removable = #stops > Schema.MIN_BLEND_STOPS
                SetAvailable(row.remove, removable)
            end
        end
        local room = #stops < Schema.MAX_BLEND_STOPS
        SetAvailable(addStop, room)
        instance:Measure()
    end
    return card
end

local function BuildRules(page)
    local section = K.Section(page, L["RULES"], { summary = function()
        local count = #(CurrentRules() or {})
        if count == 0 then return L["No rules"] end
        return count == 1 and L["1 rule"] or string.format(L["%d rules"], count)
    end })
    Options.editorRulesBlock = section
    local help = HelpButton(section.band, L["Rules"], {
        L["When its condition holds, a rule sets this part's colour, blends it by health, sets its opacity or "
            .. "hides it. An empty condition always holds."],
        L["Rules are read top to bottom: the last colour or opacity rule that holds wins, and any hide rule "
            .. "hides. With none, the part keeps its own style. Presets add ready-made sets."],
        L["Conditions are the same as in Custom text: tagged, elite, casting, health.percent < 35, and, or, not. "
            .. "Role and threat: role.tank, threat.holding, threat.losing, threat.pulling, threat.other, "
            .. "threat.offtank. Fades: hastarget (you have a target), inrange (within your spells' reach)."],
        { L["A condition on a protected or missing value is unknown and counts as not true, even after not."],
            0.86, 0.86, 0.86 },
    }, false)
    help:SetPoint("LEFT", section.title, "RIGHT", K.CONTROL_GAP, 0)
    -- Preview as if true: the section's first row.
    local previewRow, previewTrue = K.CheckRow(section, L["Preview"], {
        text = L["as if every condition is true"],
        get = function() return Options.editorRulesPreviewTrue == true end,
        set = function(on)
            Options.editorRulesPreviewTrue = on or nil
            Options:RefreshEditorAppearance(PS.GetSettings())
        end,
    })
    K.Add(section, previewRow)
    Options.editorRulesPreviewCheckbox = Register(previewTrue)
    -- The cards, one per rule, in order (each CARD_GAP below the one before).
    local list = K.Group(section)
    local cards = {}
    K.Add(section, list)
    local buttons, addRule = K.ButtonRow(section, L["+ Add rule"], 120)
    addRule:SetScript("OnClick", function()
        local rules = CurrentRules()
        if RuleRoom(rules) < 1 then return end
        local key = Options.selectedComponent
        rules[#rules + 1] = { when = "tagged", set = Colourable(key) and "colour" or "alpha",
            colour = { r = 0.5, g = 0.5, b = 0.5 }, alpha = 0.5 }
        WriteRules(rules)
    end)
    Controls.AttachTooltip(addRule, L["+ Add rule"], { string.format(L["A part keeps up to %d rules, a plate type %d "
        .. "in all; when the button is off, remove one first."], Schema.MAX_RULES_PER_PART, MAX_RULES) })
    K.Add(section, buttons)
    -- Presets: built-in sets of rules that fit this part, appended after its own (the title's action).
    local function RulePresetEntries()
        local key, entries = Options.selectedComponent, {}
        local room = RuleRoom(CurrentRules())
        for _, preset in ipairs(RULE_PRESETS) do
            if preset.kind ~= "colour" or Colourable(key) then
                entries[#entries + 1] = { text = preset.name, disabled = room < #preset.rules, func = function()
                    local rules = CurrentRules()
                    if RuleRoom(rules) < #preset.rules then return end
                    for _, rule in ipairs(preset.rules) do rules[#rules + 1] = PS.Table.DeepCopy(rule) end
                    WriteRules(rules)
                end }
            end
        end
        return entries
    end
    local presets = CreateStudioButton(section.band, L["Presets"], 86, K.BUTTON_H)
    K.Accessory(section, presets)
    presets:SetScript("OnClick", function(instance) Options:ShowEditorMenu(RulePresetEntries(), instance) end)
    Controls.AttachTooltip(presets, L["Presets"], { L["Adds a ready-made set of rules after this part's own."] })
    Options.editorRulesAdd, Options.editorRulePresetsButton = addRule, presets
    Options.editorRuleRows = cards
    Options.EditorRulePresetEntries = RulePresetEntries
    Options.editorRulesRefresh = function()
        local rules, key = CurrentRules()
        if not key then return end
        previewTrue:Refresh()
        for index, rule in ipairs(rules) do
            if not cards[index] then
                local card = RuleCard(list, index)
                cards[index] = card
                K.Add(list, card, function() return card.active end)
            end
            cards[index]:Display(rule)
        end
        for index = #rules + 1, #cards do
            cards[index].active = false
            cards[index]:Hide()
        end
        -- At either limit (or with nothing that fits) a button is off and dimmed, not refused on click.
        local room = RuleRoom(rules) > 0
        SetAvailable(addRule, room)
        -- With no preset for this part, the title has no action at all (not a blank, dimmed one).
        local fits = #RulePresetEntries() > 0
        presets:SetEnabled(fits)
        presets:SetShown(fits)
    end
    K.Add(page, section, function() return Selection().key ~= nil end)
end

-- A custom group: its name, the offset that moves every member, its scale and arrangement, its
-- members, its place in the tree and Delete. The header's eye shows or hides it.
local function BuildGroupContext(page)
    local context = CreateContext(page, "group")
    local function SelectedGroup()
        local key = Options.editorSelectedGroup
        return key, key and Options.editorLayout and Options.editorLayout[key]
    end
    local section = K.Section(context, L["GROUP"])
    K.Add(context, section)
    local nameRow = K.Row(section, L["Name"])
    local groupName = ValueBox(nameRow, K.CONTROL_X, K.WIDE, function(edit)
        local key = SelectedGroup()
        if key then Options:RenameEditorGroup(key, edit:GetText()) end
    end, Schema.GROUP_NAME_LENGTH)
    K.Add(section, nameRow)
    local offset
    offset = K.OffsetRow(section, L["Offset"], function()
        local key, group = SelectedGroup()
        if not group then return end
        Options:SetEditorGroupOffset(key, tonumber(offset.x:GetText()) or group.x, tonumber(offset.y:GetText()) or group.y)
    end)
    Options.editorGroupOffsetX, Options.editorGroupOffsetY = offset.x, offset.y
    K.Add(section, offset)
    -- Scale: every member grows or shrinks together around the group's centre.
    local scaleRange = Schema.layoutRanges.scale
    local scaleRow, scale = K.SliderRow(section, L["Scale"], {
        min = scaleRange[1], max = scaleRange[2], step = 0.05, format = PercentText,
        name = WidgetName("editor_group_scale", "Slider"),
        get = function()
            local _, group = SelectedGroup()
            return group and (group.scale or 1)
        end,
        drag = function(value)
            local key = SelectedGroup()
            return key and Options:SetEditorGroupScale(key, value, nil, nil, nil, true) or false
        end,
        set = function(value)
            local key = SelectedGroup()
            return key and Options:SetEditorGroupScale(key, value) or false
        end,
    })
    Options.editorGroupScaleSlider = scale
    K.Add(section, scaleRow)
    -- Arrange: stack what is inside (a shown power bar then pushes the cast bar down), or not.
    local arrangeRow, arrange = K.DropdownRow(section, L["Arrange"], {
        choices = { { value = "free", label = L["Where each is put"] }, { value = "down", label = L["Stack downwards"] },
            { value = "up", label = L["Stack upwards"] }, { value = "right", label = L["Stack to the right"] },
            { value = "left", label = L["Stack to the left"] } },
        name = WidgetName("editor_group_stack", "Dropdown"),
        get = function()
            local _, group = SelectedGroup()
            return group and group.stack or "free"
        end,
        set = function(value)
            local key, group = SelectedGroup()
            if key then Options:SetEditorStack(key, value ~= "free" and value or nil, group and group.gap) end
        end,
    })
    Register(arrange)
    Options.editorGroupArrange = arrange
    K.Add(section, arrangeRow)
    local gapRow, gap = K.SliderRow(section, L["Gap"], {
        min = Schema.STACK_GAP[1], max = Schema.STACK_GAP[2], step = 1, name = WidgetName("editor_group_gap", "Slider"),
        get = function()
            local _, group = SelectedGroup()
            return group and (group.gap or 4)
        end,
        set = function(value)
            local key, group = SelectedGroup()
            return key and group and group.stack and Options:SetEditorStack(key, group.stack, value) or false
        end,
    })
    K.Add(section, gapRow, function()
        local _, group = SelectedGroup()
        return group and group.stack ~= nil
    end)
    K.Add(section, K.Help(section, L["Drag a member in the preview to move them all, or a corner to scale them."]))

    local members = K.Section(context, L["MEMBERS"])
    K.Add(context, members)
    local memberCount = K.Text(members.band, "", "muted")
    memberCount:SetWidth(K.WIDTH / 2)
    memberCount:SetJustifyH("RIGHT")
    K.Accessory(members, memberCount)
    -- The members, one line each inside an inset, CARD_PAD above and below them.
    local inset = CreateFrame("Frame", nil, members)
    local function InsetHeight(count) return K.CARD_PAD * 2 + math.max(1, count) * K.MEMBER_H end
    inset:SetSize(K.WIDTH, InsetHeight(0))
    local insetArt = Theme.NineSlice(inset, "inspector-inset", "ARTWORK", 0)
    inset:SetScript("OnSizeChanged", function(frame) insetArt:Layout(0, 0, frame:GetWidth(), frame:GetHeight()) end)
    insetArt:Layout(0, 0, K.WIDTH, inset:GetHeight())
    local textX = K.CARD_PAD + K.CHECK_INSET
    local memberRows = {}
    for index = 1, 12 do
        local row = K.Text(inset, "", "label")
        row:SetPoint("LEFT", inset, "TOPLEFT", textX, -(K.CARD_PAD + (index - 0.5) * K.MEMBER_H))
        memberRows[index] = row
    end
    local emptyMembers = K.Text(inset, L["Drag parts onto this group in the tree to add them."], "muted")
    emptyMembers:SetPoint("LEFT", inset, "TOPLEFT", textX, -(K.CARD_PAD + K.MEMBER_H / 2))
    emptyMembers:SetWidth(K.WIDTH - textX * 2)
    K.Add(members, inset)
    local moves = K.Add(members, K.Row(members, nil))
    local half = math.floor((K.WIDTH - K.CONTROL_GAP) / 2)
    local moveUp = CreateStudioButton(moves, L["Move up"], half, K.BUTTON_H)
    moveUp:SetPoint("LEFT", moves, "LEFT", 0, 0)
    local moveDown = CreateStudioButton(moves, L["Move down"], K.WIDTH - K.CONTROL_GAP - half, K.BUTTON_H)
    moveDown:SetPoint("LEFT", moves, "LEFT", half + K.CONTROL_GAP, 0)
    local function MoveSelected(direction)
        local key = SelectedGroup()
        if key and PS.MoveComponentGroup(key, direction, Options.editorProfile, Options:CurrentEditorVariant()) then
            Options:ReloadEditorLayout()
        end
    end
    moveUp:SetScript("OnClick", function() MoveSelected(-1) end)
    moveDown:SetScript("OnClick", function() MoveSelected(1) end)
    local deleteRow, deleteGroup = K.ButtonRow(members, L["Delete group"], nil, "action")
    deleteGroup:SetScript("OnClick", function()
        local key = SelectedGroup()
        if key then Options:ConfirmDeleteEditorGroup(key) end
    end)
    K.Add(members, deleteRow)
    Options.editorGroupMembers = memberRows
    Options.groupControlsRefresh = function()
        local key, group = SelectedGroup()
        if not group then return end
        groupName:SetText(group.name or "")
        offset.x:SetText(tostring(group.x or 0))
        offset.y:SetText(tostring(group.y or 0))
        scale:Refresh()
        arrange:Refresh()
        gap:Refresh()
        local list = {}
        for _, entry in ipairs(Options:EditorCustomGroups()) do
            if entry.key == key then list = entry.members end
        end
        for index, row in ipairs(memberRows) do
            row:SetText(list[index] and Options:EditorComponentLabel(list[index]) or "")
        end
        memberCount:SetText(#list == 1 and L["1 part"] or string.format(L["%d parts"], #list))
        emptyMembers:SetShown(#list == 0)
        inset:SetHeight(InsetHeight(math.min(#list, #memberRows)))
        insetArt:Layout(0, 0, K.WIDTH, inset:GetHeight())
    end
end

-- The plate's own scale, per plate type: Studio's "Plate" row (the tree's top). Sizes belong to
-- their parts (the health bar's width and height, each text's size), so they are set there, once.
local function BuildPlateContext(page)
    local context = CreateContext(page, "plate")
    local section = K.Section(context, L["PLATE"])
    K.Add(context, section)
    local range = profileRanges.scale
    local row, slider = K.SliderRow(section, L["Scale"], {
        min = range[1], max = range[2], step = 0.05, format = PercentText,
        name = WidgetName("editor_profile_scale", "Slider"),
        get = ProfileValue("scale"),
        drag = function(value)
            local ok = PS.SetPlateProfileOption(Options.editorProfile, "scale", value)
            Options:QueueRefresh()
            return ok
        end,
        set = function(value)
            local ok = PS.SetPlateProfileOption(Options.editorProfile, "scale", value)
            Options:Refresh(true)
            return ok
        end,
    })
    Register(slider)
    K.Add(section, row)
    K.Add(section, K.Help(section, L["Scales the whole plate. Bar sizes are set on each bar, text sizes on each text."]))
end

-- Settings › Stacking & distance: Blizzard's own stacking, spacing, edge, distance, scale and fade
-- CVars (PS.Stacking, docs/STACKING.md) and PlateSmith's stacking options. The CVar rows come from
-- the client's catalogue, so a CVar this client lacks never shows and a group without any is
-- hidden. While PlateSmith does not manage stacking, every section under Management is dimmed and
-- takes no clicks (still readable). A dragged slider only redraws the preview; letting go writes.
-- The preview: a fixed scale (plate: the unscaled plate's width in pixels), units standing on a
-- ground line `ground` px above the canvas's bottom (their distances under it), each plate headGap
-- over its unit's head. Plates glide on the ticker (interval) only while one moves and it shows.
local STACKING_PREVIEW = { width = 280, height = 170, font = 10, labelInset = 4, plate = 84, ground = 18,
    body = { 6, 16 }, headGap = 4, interval = 0.03, ticker = "studio.stackingPreview" }
local STACKING_TARGET_INK = { 1, 0.82, 0 }
local STACKING_UNIT_INK = { 0.62, 0.6, 0.56 }
-- The page's glide step (BuildStackingPage sets it); the entry runs only while plates move.
local stackingGlide
PS.Ticker.Register(STACKING_PREVIEW.ticker, STACKING_PREVIEW.interval, function(elapsed)
    if stackingGlide then stackingGlide(elapsed) else PS.Ticker.SetEnabled(STACKING_PREVIEW.ticker, false) end
end)
PS.Ticker.SetEnabled(STACKING_PREVIEW.ticker, false)

local function TrimNumber(value)
    local text = string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
    return text
end

-- A CVar's reading: distances in yards, opacity and screen insets as percentages, scales and
-- spacing as multiples, anything else as the plain number.
local function StackingValueText(key)
    if key:find("Distance$") then
        return function(value) return string.format(L["%d yd"], math.floor(value + 0.5)) end
    end
    if key:find("Alpha") or key:find("Inset$") then return PercentText end
    if key:find("Scale$") or key:find("^nameplateOverlap") then
        return function(value) return string.format(L["%s×"], TrimNumber(value)) end
    end
    return TrimNumber
end

-- Blizzard's own names (Nameplates/NativeFonts.lua): the opt-in size for its shared nameplate fonts,
-- and the readable outdoor treatment it replaces where it applies.
local function BuildBlizzardNameFontSection(SK, Section, Check, Choice, Bind, page)
    local scopeChoices = {
        { value = "instances", label = L["Dungeons and raids"],
            help = L["Only where Blizzard keeps friendly plates; outdoors its fonts are left as they were."] },
        { value = "everywhere", label = L["Everywhere"], help = L["The same size on every Blizzard plate, in the world too."] },
    }
    local outlineChoices = {
        { value = "none", label = L["None"] }, { value = "outline", label = L["Outline"] },
        { value = "thick", label = L["Thick outline"] },
    }
    local section = Section(page, "blizzardNameFont", L["Blizzard name size"], function()
        local settings = PS.GetSettings()
        if not settings.blizzardNameFont then return L["Off"] end
        return PointText(settings.blizzardNameFontSize)
    end)
    Check(section, "dungeonFriendly.blizzardNameFont", "blizzardNameFont", L["Change Blizzard's nameplate fonts"], "dungeon")
    SK.Add(section, SK.ControlHelp(section, L["Off by default. Sets one size for the names Blizzard draws on its own "
        .. "plates, such as friendly players in dungeons. It changes Blizzard's shared nameplate fonts, so any other "
        .. "addon or Blizzard window that uses them changes too. Turning it off puts them back as they were."]))
    Choice(section, "dungeonFriendly.blizzardNameFontScope", "blizzardNameFontScope", L["Where"], scopeChoices)
    local range = Schema.settingRanges.blizzardNameFontSize
    local get, set, drag = Options.BindSetting("blizzardNameFontSize")
    local row, slider = SK.SliderRow(section, L["Size"], {
        min = range[1], max = range[2], step = 1, format = PointText,
        name = WidgetName("dungeon_blizzardNameFontSize", "Slider"), get = get, set = set, drag = drag,
    })
    SK.Add(section, row)
    Bind("dungeonFriendly.blizzardNameFontSize", slider)
    Choice(section, "dungeonFriendly.blizzardNameFontOutline", "blizzardNameFontOutline", L["Outline"], outlineChoices)
    Choice(section, "dungeonFriendly.blizzardNameFontFace", "blizzardNameFontFace", L["Font"], PS.Media.FontChoices,
        L["Blizzard nameplate font keeps each font's own face."])
    Check(section, "dungeonFriendly.nativeNameFont", "nativeNameFont", L["Readable Blizzard names outdoors"], "dungeon")
    SK.Add(section, SK.ControlHelp(section, L["Outside dungeons and raids, Blizzard's names are drawn at least 13 pt with "
        .. "an outline. Where the size above applies, it is used instead."]))
end

local function BuildStackingPage(SK, Page, Bind)
    local Stacking = PS.Stacking
    if not Stacking then return end
    local bound = Options.editorSettingsControls
    local page = Page("stacking")
    local state = { rows = {}, groups = {}, dimmed = {}, drag = {} }
    Options.editorStacking = state
    local function Changed() Options:Refresh(true) end
    local function StackSection(id, title, summary, visible)
        local section = SK.Section(page.columns, title, { key = "studio.settings." .. id, summary = summary })
        section.title:SetFont(SK.FONT_PATH, SK.TITLE_FONT)
        SK.Add(page.columns, section, visible)
        return section
    end
    -- Dimmed and blocked while unmanaged; its title band still folds it.
    local function Dimmable(section)
        local blocker = CreateFrame("Frame", nil, section)
        blocker:EnableMouse(true)
        blocker:SetPoint("TOPLEFT", section.band, "BOTTOMLEFT", 0, 0)
        blocker:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 0, 0)
        blocker:Hide()
        section.stackingBlocker = blocker
        state.dimmed[#state.dimmed + 1] = section
        return section
    end
    local function CheckRow(section, id, text, get, set)
        local row, box = SK.CheckRow(section, nil, { text = text, get = get, set = set,
            name = WidgetName("stacking_" .. id, "Checkbox") })
        SK.Add(section, row)
        return Bind("stacking." .. id, box)
    end
    -- A tooltip built when it opens (its lines depend on the current state).
    local function LiveTip(owner, title, lines)
        if owner.SetMotionScriptsWhileDisabled then owner:SetMotionScriptsWhileDisabled(true) end
        owner:HookScript("OnEnter", function(instance)
            if not GameTooltip then return end
            GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
            GameTooltip:SetText(type(title) == "function" and title() or title)
            for _, line in ipairs(lines()) do GameTooltip:AddLine(line[1], line[2], line[3], line[4], true) end
            GameTooltip:Show()
        end)
        owner:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    local function HasEntries(group)
        for _, entry in ipairs(Stacking.Catalogue()) do
            if group == nil or entry.group == group then return true end
        end
        return false
    end

    -- Management.
    local management = StackSection("stackingManagement", L["Management"], function()
        return Stacking.IsManaged() and L["On"] or L["Off"]
    end)
    CheckRow(management, "managed", L["Manage Blizzard's plate stacking"], Stacking.IsManaged, function(value)
        Stacking.SetManaged(value)
        Changed()
    end)
    SK.Add(management, SK.ControlHelp(management, L["When off, PlateSmith leaves Blizzard's stacking settings alone. "
        .. "Turning it off puts every setting back as it was."]))
    state.offNote = SK.Add(management, SK.Note(management, L["Turn it on to change the settings below."]),
        function() return not Stacking.IsManaged() end)
    SK.Ink(state.offNote.text, "sub")
    -- The saved record of the player's own values was lost (Stacking.OriginalsMissing).
    state.lostNote = SK.Add(management, SK.Note(management, L["PlateSmith has no record of your earlier "
        .. "settings; turning this off restores Blizzard's defaults."]), function() return Stacking.OriginalsMissing() end)
    SK.Ink(state.lostNote.text, "sub")
    local resetRow, reset = SK.ButtonRow(management, L["Reset Blizzard's stacking to game defaults"], nil, "action")
    SK.Add(management, resetRow)
    state.reset = reset
    reset:SetScript("OnClick", function()
        Options:ConfirmStudioAction(L["Set every Blizzard stacking, distance, scale and fade setting to the game's "
            .. "default? This clears this profile's stacking values; Revert undoes that until you save."], L["Reset"],
            function()
                local _, left = Stacking.ResetToDefaults()
                if left and #left > 0 then
                    PS.Chat.Print(string.format(L["The game reports no default for %s, so it was left as it is."],
                        table.concat(left, ", ")))
                end
                Changed()
            end)
    end)

    -- Preset.
    local presetChoices = {
        { value = "tight", label = L["Tight"], tooltip = L["Plates close together, near the screen edges."] },
        { value = "normal", label = L["Normal"], tooltip = L["Blizzard's usual spacing."] },
        { value = "loose", label = L["Loose"], tooltip = L["More room between plates and from the screen edges."] },
        { value = "custom", label = L["Custom"], tooltip = L["Your own values, set below."] },
    }
    local preset = Dimmable(StackSection("stackingPreset", L["Preset"], function()
        for _, choice in ipairs(presetChoices) do
            if choice.value == Stacking.Preset() then return choice.label end
        end
        return ""
    end, function() return HasEntries() end))
    local presetRow = SK.Add(preset, SK.Row(preset, L["Spacing"]))
    state.preset = Bind("stacking.preset", SK.Segmented(presetRow, { choices = presetChoices,
        name = WidgetName("stacking_preset", "Segmented"), get = Stacking.Preset,
        set = function(value)
            Stacking.ApplyPreset(value)
            Changed()
        end }))
    SK.Add(preset, SK.ControlHelp(preset, L["Sets the spacing and screen edge insets in one step. Changing one of "
        .. "them afterwards makes it Custom."]))

    -- One section per group, a row per CVar this client has (SyncRows fills them).
    for _, group in ipairs(Stacking.GROUPS) do
        local section = Dimmable(StackSection("stacking." .. group.id, group.label, nil,
            function() return HasEntries(group.id) end))
        local rows = SK.Add(section, SK.Group(section))
        state.groups[group.id] = { section = section, rows = rows }
        if group.id == "stacking" then
            state.sharedNote = SK.Add(section, SK.Help(section, L["Blizzard uses one stacking setting for friendly "
                .. "and enemy plates."]), function() return Stacking.MotionShared() end)
        end
    end
    local SOURCES = { setting = L["Set in this profile"], client = L["Game setting"], default = L["Blizzard default"] }
    local function Value(key) return (Stacking.Get(key)) end
    -- Blizzard spaces plates only while they stack; Overlapping leaves them on their units.
    local SPACING = { nameplateOverlapV = true, nameplateOverlapH = true }
    local SPACING_OFF = L["Applies only while plates are Stacking; they are Overlapping now."]
    -- A label that does not fit wraps and the row grows, instead of being cut short.
    local function Wrap(row)
        local label = row.label
        if label.SetWordWrap then label:SetWordWrap(true) end
        local measure = row.Measure
        function row:Measure()
            local height = math.max(measure and measure(self) or SK.ROW_H, SK.TextHeight(label, SK.LABEL_W))
            self:SetHeight(height)
            return height
        end
    end
    local function MakeRow(parent, entry)
        local key = entry.key
        local row, control
        if entry.kind == "choice" then
            row, control = SK.DropdownRow(parent, entry.label, { choices = entry.choices,
                name = WidgetName("stacking_" .. key, "Dropdown"), get = function() return Value(key) end,
                set = function(value)
                    Stacking.Set(key, value)
                    Changed()
                end })
        elseif entry.kind == "toggle" then
            row, control = SK.CheckRow(parent, entry.label, { text = "", name = WidgetName("stacking_" .. key, "Checkbox"),
                get = function() return Value(key) == 1 end,
                set = function(value)
                    Stacking.Set(key, value and 1 or 0)
                    Changed()
                end })
        else
            row, control = SK.SliderRow(parent, entry.label, {
                min = entry.min, max = entry.max, step = entry.step, format = StackingValueText(key),
                name = WidgetName("stacking_" .. key, "Slider"), get = function() return Value(key) end,
                -- Dragging only moves the preview; the value is written once, on release.
                drag = function(value)
                    state.drag[key] = value
                    if Stacking.Previewed(key) and state.DrawPreview then state.DrawPreview() end
                    return true
                end,
                set = function(value)
                    state.drag[key] = nil
                    local ok = Stacking.Set(key, value)
                    Changed()
                    return ok
                end,
            })
        end
        Wrap(row)
        LiveTip(control, entry.label, function()
            local _, source = Stacking.Get(key)
            local lines = { { SOURCES[source] or "", 1, 0.82, 0.45 }, { key, 0.6, 0.6, 0.6 } }
            if SPACING[key] and Value("nameplateMotion") ~= 1 then
                table.insert(lines, 2, { SPACING_OFF, 1, 1, 1 })
            end
            return lines
        end)
        return { row = row, control = control, entry = entry }
    end
    -- The rows follow the client's catalogue (built once per client; again only for a new one).
    local function SyncRows()
        local catalogue = Stacking.Catalogue()
        if state.catalogue == catalogue then return end
        state.catalogue = catalogue
        for _, holder in pairs(state.groups) do holder.rows.flowItems = {} end
        for key, record in pairs(state.rows) do
            record.live = false
            record.row:Hide()
            bound["stacking." .. key] = nil
        end
        for _, entry in ipairs(catalogue) do
            local holder = state.groups[entry.group]
            if holder then
                local record = state.rows[entry.key] or MakeRow(holder.rows, entry)
                state.rows[entry.key], record.live = record, true
                SK.Add(holder.rows, record.row)
                bound["stacking." .. entry.key] = record.control
            end
        end
    end
    state.SyncRows = SyncRows

    -- PlateSmith's own options.
    -- Target and focus on top are PlateSmith's own and work without managing Blizzard's stacking;
    -- only the two options that change Blizzard's settings wait for management.
    local options = StackSection("stackingOptions", L["PlateSmith options"])
    local function Option(name, text, help)
        local box = CheckRow(options, name, text, function() return Stacking.GetOption(name) end, function(value)
            Stacking.SetOption(name, value)
            Changed()
        end)
        SK.Add(options, SK.ControlHelp(options, help))
        return box
    end
    Option("targetOnTop", L["Target on top"], L["Your target's plate draws over its neighbours where plates overlap."])
    Option("focusOnTop", L["Focus on top"], L["Your focus's plate too, under your target's."])
    state.matchFrame = Option("matchFrameSize", L["Match frame size to layout"], L["Sizes Blizzard's "
        .. "plate to what your layout draws, so stacking spaces plates evenly."])
    local NO_SIZING = L["This client can't size Blizzard's plates, so this has no effect here."]
    LiveTip(state.matchFrame, L["Match frame size to layout"], function()
        return Stacking.SizeSupport() and {} or { { NO_SIZING, 1, 0.82, 0.45 } }
    end)
    -- Wraps to its column: the reason sizing cannot work here is a full sentence.
    state.sizeText = SK.Add(options, SK.Note(options, ""))
    SK.Ink(state.sizeText.text, "value")
    local COMBAT_TIPS = { refused = L["The game doesn't allow switching this in combat"],
        untested = L["Not tested yet on this client - it will be tried at your next fight"] }
    local function CombatState()
        local _, combatState = Stacking.CanCombatSwitch()
        return combatState
    end
    local combat = Option("combatStacking", L["Stack only in combat"], L["Plates stack during fights and "
        .. "go back to your usual arrangement after."])
    state.combat = combat
    LiveTip(combat, L["Stack only in combat"], function()
        local tip = COMBAT_TIPS[CombatState()]
        return tip and { { tip, 1, 0.82, 0.45 } } or {}
    end)
    state.combatNote = SK.Add(options, SK.Note(options, ""), function() return COMBAT_TIPS[CombatState()] ~= nil end)

    -- Preview: three units at near, mid (your target) and far range and where Blizzard draws their
    -- plates (Stacking.PreviewModel), at a fixed scale so every change moves or restyles a plate.
    local SP = STACKING_PREVIEW
    local preview = Dimmable(StackSection("stackingPreview", L["Preview"]))
    local holder = CreateFrame("Frame", nil, preview)
    holder:SetSize(SK.WIDTH, SP.height)
    local canvas = CreateFrame("Frame", nil, holder)
    canvas:SetSize(SP.width, SP.height)
    -- A plate stacked above the canvas is cut at its edge instead of drawing over the page.
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    local backdrop = canvas:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(canvas)
    backdrop:SetColorTexture(0, 0, 0, 0.35)
    local edge = PanelLayout.PALETTES.studio.divider
    local groundLine = canvas:CreateTexture(nil, "BORDER")
    groundLine:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 0, SP.ground)
    groundLine:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0, SP.ground)
    groundLine:SetHeight(1)
    groundLine:SetColorTexture(edge[1], edge[2], edge[3], 1)
    local plates, units = {}, {}
    for index, name in ipairs({ L["Murloc"], L["Kobold"], L["Gnoll"] }) do
        local plate = CreateFrame("Frame", nil, canvas)
        plate.fill = plate:CreateTexture(nil, "BACKGROUND")
        plate.fill:SetAllPoints(plate)
        plate.fill:SetColorTexture(0.09, 0.08, 0.07, 1)
        -- Four 1 px sides over the fill, not a rectangle under it: dimmed, a rectangle shows through.
        plate.edges = {}
        for side, points in pairs({ top = { "TOPLEFT", "TOPRIGHT" }, bottom = { "BOTTOMLEFT", "BOTTOMRIGHT" },
            left = { "TOPLEFT", "BOTTOMLEFT" }, right = { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local line = plate:CreateTexture(nil, "BORDER")
            line:SetPoint(points[1], plate, points[1], 0, 0)
            line:SetPoint(points[2], plate, points[2], 0, 0)
            if side == "top" or side == "bottom" then line:SetHeight(1) else line:SetWidth(1) end
            plate.edges[side] = line
        end
        plate.label = SK.Text(plate, name, "label")
        plate.label:SetFont(SK.FONT_PATH, SP.font)
        -- At the plate's left end: the part a later, overlapping plate leaves uncovered.
        plate.label:SetPoint("LEFT", plate, "LEFT", SP.labelInset, 0)
        plates[index] = plate
        -- The unit: a figure on the ground, its distance under it, and a faint line up to its plate.
        local unit = { body = canvas:CreateTexture(nil, "ARTWORK"), line = canvas:CreateTexture(nil, "BORDER") }
        unit.body:SetSize(SP.body[1], SP.body[2])
        unit.line:SetWidth(1)
        unit.line:SetColorTexture(1, 1, 1, 0.25)
        unit.label = SK.Text(canvas, "", "muted")
        unit.label:SetFont(SK.FONT_PATH, SP.font)
        units[index] = unit
    end
    SK.OnWidth(holder, function(width)
        canvas:ClearAllPoints()
        canvas:SetPoint("TOPLEFT", holder, "TOPLEFT", math.max(0, math.floor((width - SP.width) / 2)), 0)
    end)
    SK.Add(preview, holder)
    local captionRow = SK.Add(preview, SK.Help(preview, ""))
    -- The CVars this client has that the diagram cannot show, so none of them seems to do nothing.
    local function NotShownText()
        local names, seen = {}, {}
        for _, entry in ipairs(Stacking.Catalogue()) do
            if not Stacking.Previewed(entry.key) then
                local name = entry.group == "edges" and entry.groupLabel or entry.label
                if not seen[name] then
                    seen[name], names[#names + 1] = true, name
                end
            end
        end
        return #names > 0 and string.format(L["Not shown here: %s."], table.concat(names, ", ")) or ""
    end
    state.notShown = SK.Add(preview, SK.Help(preview, ""), function() return NotShownText() ~= "" end)
    SK.Ink(state.notShown.text, "sub")
    state.canvas, state.plates, state.units, state.caption = canvas, plates, units, captionRow.text
    state.NotShownText = NotShownText
    local MODE_TEXT = {
        overlapping = L["Overlapping: plates stay on their units; the spacing settings apply only while Stacking. "
            .. "Plate size %d × %d; your target is gold."],
        stacking = L["Stacking: plates move apart. Plate size %d × %d; your target is gold."],
    }
    local OUT_OF_VIEW = L["A unit beyond the view distance has no plate."]

    -- Each plate's drawn height (model units) while it glides to the model's (nameplateMotionSpeed).
    local glide, drawnShown = {}, {}
    local function Settle() return 0.5 / state.px end
    local function SetGliding(on)
        on = (on and canvas:IsVisible()) and true or false
        if PS.Ticker.IsEnabled(SP.ticker) ~= on then PS.Ticker.SetEnabled(SP.ticker, on) end
    end
    local function Place(index, shape, y)
        local plate, unit, px = plates[index], units[index], state.px
        local x = state.originX + shape.x * px
        local head = SP.ground + SP.body[2]
        local w, h = math.max(1, shape.width * px), math.max(1, shape.height * px)
        local bottom = head + SP.headGap + (y - shape.height / 2) * px
        plate:ClearAllPoints()
        plate:SetPoint("TOPLEFT", canvas, "TOPLEFT", x - w / 2, -(SP.height - bottom - h))
        plate:SetSize(w, h)
        unit.line:ClearAllPoints()
        unit.line:SetPoint("BOTTOM", canvas, "BOTTOMLEFT", x, head)
        unit.line:SetHeight(math.max(1, bottom - head))
        unit.line:SetShown(shape.shown)
    end
    -- The ticker's step: each plate moves on toward its place; hidden, they jump there and it stops.
    function state.StepPreview(elapsed)
        local drawn = state.model
        if not drawn then return SetGliding(false) end
        if not canvas:IsVisible() then elapsed = math.huge end
        local moving = false
        for index, shape in ipairs(drawn.plates) do
            local arrived
            glide[index], arrived = Stacking.PreviewGlide(glide[index] or shape.y, shape.y, drawn.speed, elapsed, Settle())
            moving = moving or not arrived
            Place(index, shape, glide[index])
        end
        SetGliding(moving)
    end
    stackingGlide = state.StepPreview
    -- Reuses the frames: only places, sizes, alphas, inks and levels change (cheap enough per drag step).
    function state.DrawPreview()
        local drawn = Stacking.PreviewModel(state.drag)
        state.model, state.px = drawn, SP.plate / math.max(1, drawn.width)
        state.originX = (SP.width - drawn.plates[#drawn.plates].unitX * state.px) / 2
        local visible, base, moving, hidden = canvas:IsVisible(), canvas:GetFrameLevel(), false, false
        for index, shape in ipairs(drawn.plates) do
            local plate, unit = plates[index], units[index]
            -- A plate glides only from where it was drawn; one just shown (or hidden) jumps.
            if not (visible and shape.shown and drawnShown[index] and glide[index]) or drawn.speed <= 0 then
                glide[index] = shape.y
            end
            drawnShown[index] = shape.shown
            moving = moving or math.abs(glide[index] - shape.y) > Settle()
            hidden = hidden or not shape.shown
            plate:SetShown(shape.shown)
            plate:SetAlpha(shape.alpha)
            -- Later units draw over earlier ones; the target over all while it is kept on top.
            plate:SetFrameLevel(base + index + ((shape.target and drawn.targetOnTop) and #plates or 0))
            local ink = shape.target and STACKING_TARGET_INK or edge
            for _, line in pairs(plate.edges) do line:SetColorTexture(ink[1], ink[2], ink[3], 1) end
            plate.label:SetShown(shape.height * state.px >= SP.font + 2)
            local x = state.originX + shape.x * state.px
            ink = shape.target and STACKING_TARGET_INK or STACKING_UNIT_INK
            unit.body:ClearAllPoints()
            unit.body:SetPoint("BOTTOM", canvas, "BOTTOMLEFT", x, SP.ground + 1)
            unit.body:SetColorTexture(ink[1], ink[2], ink[3], 1)
            unit.body:SetAlpha(shape.shown and 1 or 0.4)
            unit.label:ClearAllPoints()
            unit.label:SetPoint("TOP", canvas, "BOTTOMLEFT", x, SP.ground - 3)
            unit.label:SetText(string.format(L["%d yd"], shape.distance))
            Place(index, shape, glide[index])
        end
        SetGliding(moving)
        local text = string.format(MODE_TEXT[drawn.motion], math.floor(drawn.width + 0.5), math.floor(drawn.height + 0.5))
        if hidden then text = string.format("%s\n%s", text, OUT_OF_VIEW) end
        local relayout = state.captionText ~= nil and state.captionText ~= text and preview:IsVisible()
        state.caption:SetText(text)
        state.captionText = text
        -- A caption that gains or loses a line changes the section's height.
        if relayout then Options:LayoutEditorSettingsPanels() end
        return drawn
    end

    local function FrameSizeText()
        if not Stacking.SizeSupport() then return NO_SIZING end
        local sizes = Stacking.FrameSizes()
        local enemy, friendly = sizes.enemy, sizes.friendly
        if enemy and friendly then
            return string.format(L["Enemy %d × %d, Friendly %d × %d"], enemy[1], enemy[2], friendly[1], friendly[2])
        end
        if enemy and sizes.friendlyLocked then
            return string.format(L["Enemy %d × %d (Blizzard sizes friendly plates here)"], enemy[1], enemy[2])
        end
        if enemy then return string.format(L["Enemy %d × %d"], enemy[1], enemy[2]) end
        if friendly then return string.format(L["Friendly %d × %d"], friendly[1], friendly[2]) end
        return ""
    end

    local relayout = page.Relayout
    function page:Relayout(width)
        SyncRows()
        state.notShown.text:SetText(NotShownText())
        return relayout(self, width)
    end
    -- The CVar rows are not Options.controls (a new catalogue replaces them): refreshed here.
    Register({ Refresh = function()
        SyncRows()
        for _, record in pairs(state.rows) do
            if record.live then
                record.control:Refresh()
                local value = record.control.valueText
                if value then
                    local _, source = Stacking.Get(record.entry.key)
                    SK.Ink(value, source == "setting" and "value" or "muted")
                end
            end
        end
        local managed = Stacking.IsManaged()
        local sizable = managed and Stacking.SizeSupport()
        SetAvailable(state.matchFrame, sizable)
        state.matchFrame.label:SetAlpha(sizable and 1 or 0.45)
        for _, section in ipairs(state.dimmed) do
            -- The title and the rows dim; the divider above stays as on every other section.
            local alpha = managed and 1 or DIMMED_ALPHA
            section.band:SetAlpha(alpha)
            -- Each row carries its own dimming (a CVar row too, not only its group), so it stays
            -- dimmed when the settings search lends it to its results page.
            for _, item in ipairs(section.flowItems) do
                local frame = item.frame
                frame:SetAlpha(frame.flowTransparent and 1 or alpha)
                for _, inner in ipairs(frame.flowTransparent and frame.flowItems or {}) do inner.frame:SetAlpha(alpha) end
            end
            section.stackingDimmed = not managed
            section.stackingBlocker:SetFrameLevel(section:GetFrameLevel() + 60)
            section.stackingBlocker:SetShown(not managed)
        end
        state.sizeText.text:SetText(FrameSizeText())
        local combatState = CombatState()
        SetAvailable(combat, managed and combatState ~= "refused")
        combat.label:SetAlpha((managed and combatState ~= "refused") and 1 or 0.45)
        state.combatNote.text:SetText(COMBAT_TIPS[combatState] or "")
    end })
    -- Its own control, so a row that fails to refresh cannot leave the diagram as it was.
    Register({ Refresh = function() state.DrawPreview() end })
end

-- Settings › Fading: a shortcut over a fade rule preset on every part the enemy plates show
-- (PS.SetFadeEverywhere), ticked while each has it and mixed while some do, with its opacity. The
-- rules stay ordinary rules, so Studio shows and edits them part by part.
local function FadeRows(SK, section, Bind, id, text, help)
    local function State() return PS.GetFadeState(id) end
    local row, checkbox = SK.CheckRow(section, nil, { text = text, name = WidgetName("editor_" .. id, "Checkbox"),
        get = function() return State() == "all" end,
        set = function(on)
            local ok = PS.SetFadeEverywhere(id, on)
            Options:Refresh(true)
            return ok
        end,
        mixed = function() return State() == "some" end, mixedTip = L["On some parts only"] })
    SK.Add(section, row)
    SK.Add(section, SK.ControlHelp(section, help))
    Bind("plate." .. id, checkbox)
    local alphaRow, alpha = SK.SliderRow(section, L["Opacity"], {
        min = 0, max = 1, step = 0.05, format = PercentText, name = WidgetName("editor_" .. id .. "_alpha", "Slider"),
        get = function()
            local _, value = State()
            return value or 0.5
        end,
        drag = function(value)
            local ok = PS.SetFadeAlpha(id, value)
            Options:QueueRefresh()
            return ok
        end,
        set = function(value)
            local ok = PS.SetFadeAlpha(id, value)
            Options:Refresh(true)
            return ok
        end,
    })
    SK.Add(section, alphaRow, function()
        local state = State()
        return state == "all" or state == "some"
    end)
    Bind("plate." .. id .. "Alpha", alpha)
end

-- Settings' pages (plate, auras, relations, dungeon friendlies, Studio, help): one shown at a time.
-- Each is the shared panel kit in Studio's dark palette: foldable sections (folds kept in the
-- player's state as "studio.settings.<section>") dealt into two columns when the page is wide
-- enough and one otherwise, laid out again at the page's width whenever it changes (Chrome's
-- LayoutEditorSettingsPanels). A row is label | control; its help is a tooltip on the label and a "?" after it,
-- and only its state (SK.Note) shows under the control.
local function BuildSettingsPages(settingsContent)
    local SK = PanelLayout.New({
        width = 420, palette = PanelLayout.PALETTES.studio,
        tokens = { LABEL_W = 200, VALUE_W = 48, CONTROL_GAP = 12, ROW_H = 32, CONTROL_H = 28, ROW_GAP = 8,
            FONT = 14, FIELD_FONT = 14, LINE_H = 18, SECTION_TOP = 24, SECTION_TITLE_H = 28, SWATCH = 22,
            SECTION_RULE_GAP = 4, COLUMN_GAP = 48,
            TITLE_FONT = 16, INTRO_GAP = 10, SIZE_BUTTON = 34, SIZE_TEXT_W = 56,
            -- A skinned field's text runs from 12 px in to 30 px before its end (Chrome's SkinDropdown).
            DROPDOWN_TEXT_INSETS = 42 },
        button = CreateStudioButton,
        collapsible = true,
        -- Blizzard's Settings rows: a check's text is its label, the box in the control column.
        checkLabels = true,
        ruleUnder = true,
        -- Explanations are tooltips, so a page shows its settings rather than paragraphs.
        helpAsTooltip = true,
        sectionState = function()
            local state = PS.GetState and PS.GetState()
            return state and state.sectionFolds or Options.editorSectionFolds
        end,
        relayout = function() Options:LayoutEditorSettingsPanels() end,
        -- The kit's light arrows, gold like the titles.
        chevron = function(texture, open)
            local parent = texture:GetParent()
            Theme.Place(texture, open and "collapse-arrow-normal" or "expand-arrow-normal", parent, 0, 0, 14, 14)
            texture:ClearAllPoints()
            texture:SetPoint("LEFT", parent, "LEFT", 0, 0)
            texture:SetVertexColor(chrome.GOLD[1], chrome.GOLD[2], chrome.GOLD[3], 1)
        end,
    })
    Options.settingsKit = SK
    -- Every setting-bound control on these pages, by "<page>.<setting>".
    local bound = {}
    Options.editorSettingsControls = bound
    local function Bind(id, control)
        bound[id] = Register(control)
        return control
    end

    -- A page: its intro (if any) over its sections' columns.
    local function Page(key, intro)
        local panel = SK.Flow(CreateFrame("Frame", nil, settingsContent))
        panel:SetSize(SK.WIDTH, 1)
        panel.settingsKey = key
        if intro then
            local help = SK.Add(panel, SK.Help(panel, intro))
            help.flowAfter = SK.INTRO_GAP
        end
        panel.columns = SK.Add(panel, SK.Columns(panel, { minColumnWidth = 360, divider = true }))
        function panel:Relayout(width)
            if width and width > 0 then self:SetWidth(width) end
            local height = SK.LayoutFlow(self, 0)
            self:SetHeight(math.max(1, height))
            return height
        end
        Options.editorInspectorPages[key] = panel
        Options.editorSettingsPanels[#Options.editorSettingsPanels + 1] = panel
        return panel
    end
    local function Section(panel, id, title, summary)
        local section = SK.Section(panel.columns, title, { key = "studio.settings." .. id, summary = summary })
        section.title:SetFont(SK.FONT_PATH, SK.TITLE_FONT)
        SK.Add(panel.columns, section)
        return section
    end
    local function Check(section, id, key, text, controlID)
        local get, set = Options.BindSetting(key)
        local row, checkbox = SK.CheckRow(section, nil, { text = text, get = get, set = set,
            name = WidgetName((controlID or "editor") .. "_" .. key, "Checkbox") })
        SK.Add(section, row)
        return Bind(id, checkbox)
    end
    -- A Show on plates or aura box: a shortcut over the parts' eyes on every plate type.
    local function PartCheck(section, id, key, text)
        local get, set, mixed = Options.BindPartSwitch(key)
        local row, checkbox = SK.CheckRow(section, nil, { text = text, get = get, set = set, mixed = mixed,
            mixedTip = L["Shown on some plate types"], name = WidgetName("editor_" .. key, "Checkbox") })
        SK.Add(section, row)
        SK.Add(section, SK.ControlHelp(section, L["Shows or hides it on every plate type. Studio's eye sets it per plate type."]))
        return Bind(id, checkbox)
    end
    local function Choice(section, id, key, label, choices, help)
        local get, set = Options.BindSetting(key)
        local row, dropdown = SK.DropdownRow(section, label, { choices = choices, get = get, set = set,
            name = WidgetName("editor_" .. key, "Dropdown") })
        SK.Add(section, row)
        if help then SK.Add(section, SK.ControlHelp(section, help)) end
        return Bind(id, dropdown)
    end
    local function Colour(section, id, relationship, label)
        local row = SK.Row(section, label)
        local swatch = Controls.ColourSwatch(row, { size = SK.SWATCH, name = WidgetName("editor_" .. relationship, "Colour"),
            get = function()
                local settings = PS.GetSettings()
                return settings and settings.relationshipColours and settings.relationshipColours[relationship]
            end,
            set = function(r, g, b)
                PS.SetRelationshipColour(relationship, r, g, b)
                Options:Refresh()
            end,
        })
        swatch:ClearAllPoints()
        swatch:SetPoint("LEFT", row, "LEFT", SK.CONTROL_X, 0)
        SK.Add(section, row)
        return Bind(id, swatch)
    end
    local function LabelOf(choices, value)
        for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
            if choice.value == value then return choice.label end
        end
        return ""
    end
    -- A long font name may not fit its field: pointing at the field then shows it whole.
    local function FullNameTip(dropdown)
        dropdown:HookScript("OnEnter", function(instance)
            local text = instance.kitText or instance.Text
            if not text or not GameTooltip then return end
            local truncated
            if text.IsTruncated then truncated = text:IsTruncated() end
            if truncated == nil then truncated = text:GetStringWidth() > instance:GetWidth() - SK.DROPDOWN_TEXT_INSETS end
            if not truncated then return end
            GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
            GameTooltip:SetText(text:GetText() or "")
            GameTooltip:Show()
            instance.fullNameTip = true
        end)
        dropdown:HookScript("OnLeave", function(instance)
            if instance.fullNameTip and GameTooltip then GameTooltip:Hide() end
            instance.fullNameTip = nil
        end)
    end

    -- Behaviour & display.
    local plate = Page("plate")
    local plates = Section(plate, "plates", L["Plates"])
    Choice(plates, "plate.mode", "mode", L["Appearance ownership"], model.modeChoices)
    Choice(plates, "plate.friendly", "friendly", L["Friendly units"], model.friendlyChoices)
    Check(plates, "plate.restrictedFriendlyNamesOnly", "restrictedFriendlyNamesOnly", L["Dungeon friendly names only"])
    -- The friendly-name CVars PlateSmith changes (NamePolicy), back to the game's defaults.
    local restoreRow, restoreNames = SK.ButtonRow(plates, L["Restore Blizzard nameplate settings"], nil, "action")
    SK.Add(plates, restoreRow)
    Options.editorRestoreNamePolicy = restoreNames
    restoreNames:SetScript("OnClick", function()
        Options:ConfirmStudioAction(L["Put Blizzard's friendly name settings that PlateSmith changes back to the game's "
            .. "defaults? Options that are on apply again over them."], L["Restore"], function()
            local left = PS.NamePolicy.RestoreDefaults()
            if #left > 0 then
                PS.Chat.Print(string.format(L["The game reports no default for %s, so it was left as it is."],
                    table.concat(left, ", ")))
            end
            Options:Refresh(true)
        end)
    end)
    SK.Add(plates, SK.ControlHelp(plates, L["For when names show wrongly after PlateSmith's saved settings were lost."]))
    local names = Section(plate, "names", L["Names"])
    Check(names, "plate.showPlayerSurnames", "showPlayerSurnames", L["Show player surnames"])
    Check(names, "plate.hideUnstyledFriendlyNames", "hideUnstyledFriendlyNames", L["Hide unstyled names outdoors"])
    Check(names, "plate.friendlyRelationshipColours", "friendlyRelationshipColours", L["Colour social relationships"])
    -- Casts on names-only plates: a slim bar under the name (Nameplates/Placement.lua's NameCast).
    Check(names, "plate.namesOnlyCastFriendly", "namesOnlyCastFriendly", L["Show casts on friendly names"])
    SK.Add(names, SK.ControlHelp(names, L["A slim cast bar under the name of a names-only friendly plate, with the "
        .. "spell's name: Opening, Mounting, Hearthstone. Not on Blizzard's protected dungeon plates."]))
    Check(names, "plate.namesOnlyCastEnemy", "namesOnlyCastEnemy", L["Show casts on enemy names"])
    SK.Add(names, SK.ControlHelp(names, L["The same slim cast bar on enemy plates whose layout hides both the health "
        .. "and cast bars, so only the name shows."]))
    do
        local range = Schema.settingRanges.namesOnlyCastWidth
        local get, set, drag = Options.BindSetting("namesOnlyCastWidth")
        local row, slider = SK.SliderRow(names, L["Name cast bar width"], {
            min = range[1], max = range[2], step = 1,
            name = WidgetName("editor_namesOnlyCastWidth", "Slider"), get = get, set = set, drag = drag,
        })
        SK.Add(names, row)
        SK.Add(names, SK.ControlHelp(names, L["How wide the cast bar under a name is, for both options above."]))
        Bind("plate.namesOnlyCastWidth", slider)
    end
    local target = Section(plate, "target", L["Target"], function()
        return LabelOf(model.targetHighlightChoices, PS.GetSettings().targetHighlightStyle)
    end)
    Choice(target, "plate.targetHighlightStyle", "targetHighlightStyle", L["Selected target"], model.targetHighlightChoices,
        L["Choose a glow around the selected plate's text and visible bars. It appears only on PlateSmith's own artwork, "
        .. "not on the 3D character model or Blizzard-owned plates."])
    local fading = Section(plate, "fading", L["Fading"])
    FadeRows(SK, fading, Bind, "fadeNonTarget", L["Fade non-targets"], L["While you have a target, the other enemy plates "
        .. "fade to this opacity. It adds a rule to each part they show; Studio's Rules edit it per part."])
    FadeRows(SK, fading, Bind, "fadeOutOfRange", L["Fade out of range"], L["Enemy plates beyond your class spells' reach "
        .. "fade. Where the game withholds the range the plate stays as it is."])
    local text = Section(plate, "text", L["Text"], function()
        local settings = PS.GetSettings()
        return string.format(L["%s, %s"], LabelOf(PS.Media.FontChoices, settings.font), PercentText(settings.textScale or 1))
    end)
    FullNameTip(Choice(text, "plate.font", "font", L["Font"], PS.Media.FontChoices,
        L["Used by every PlateSmith plate. More fonts appear when LibSharedMedia-3.0 is installed."]))
    local textScaleRange = Schema.settingRanges.textScale
    local getTextScale, setTextScale, dragTextScale = Options.BindSetting("textScale")
    local textScaleRow, textScale = SK.SliderRow(text, L["Text size"], {
        min = textScaleRange[1], max = textScaleRange[2], step = 0.05, format = PercentText,
        name = WidgetName("editor_textScale", "Slider"), get = getTextScale, set = setTextScale, drag = dragTextScale,
    })
    SK.Add(text, textScaleRow)
    SK.Add(text, SK.ControlHelp(text, L["Scales every PlateSmith text on every plate type; each part's own size still applies."]))
    Bind("plate.textScale", textScale)
    -- Questie draws its own nameplate quest icons; one set shows, never both.
    local questIconChoices = {
        { value = "auto", label = L["Automatic"],
            help = L["Questie's when Questie shows nameplate icons, otherwise PlateSmith's."] },
        { value = "platesmith", label = L["PlateSmith's"], help = L["Always PlateSmith's quest marker."] },
        { value = "questie", label = L["Questie's"], help = L["PlateSmith's marker steps aside while Questie is loaded."] },
    }
    local quests = Section(plate, "quests", L["Quests"], function()
        return LabelOf(questIconChoices, PS.GetSettings().questIcons)
    end)
    Choice(quests, "plate.questIcons", "questIcons", L["Quest icons"], questIconChoices,
        L["Questie can draw its own quest icons on nameplates. Choose whose show, so a plate never has two."])
    -- Shortcuts over the tree's eyes; the summary counts those shown on at least one plate type.
    local shows = Section(plate, "showOnPlates", L["Show on plates"], function()
        local on = 0
        for _, entry in ipairs(SHOW_ON_PLATES) do
            local state = PS.GetPartShownState(entry.key)
            if state == "all" or state == "some" then on = on + 1 end
        end
        return string.format(L["%d of %d shown"], on, #SHOW_ON_PLATES)
    end)
    for _, entry in ipairs(SHOW_ON_PLATES) do PartCheck(shows, "plate." .. entry.key, entry.key, entry.label) end
    -- Not a part: the health bar's edge on enemy plates, so it has a setting of its own.
    Check(shows, "plate.tankWarning", "tankWarning", L["Warn when you lose a mob you tank"])
    SK.Add(shows, SK.ControlHelp(shows, L["While you tank, an enemy's health bar edge turns red when you stop "
        .. "holding its threat."]))

    BuildStackingPage(SK, Page, Bind)

    -- Aura defaults.
    local auras = Page("auras",
        L["Select Buffs or Debuffs in the Studio tree to set how many icons show, their size and which way they grow."])
    local buffs = Section(auras, "buffs", L["Buffs"])
    PartCheck(buffs, "auras.showBuffs", "showBuffs", L["Show buffs"])
    Choice(buffs, "auras.buffSource", "buffSource", L["Buff source"], model.auraSourceChoices)
    local debuffs = Section(auras, "debuffs", L["Debuffs"])
    PartCheck(debuffs, "auras.showDebuffs", "showDebuffs", L["Show debuffs"])
    Choice(debuffs, "auras.debuffSource", "debuffSource", L["Debuff source"], model.auraSourceChoices)

    -- Relationships.
    local relations = Page("relations", L["PvP colour takes priority over social colour when selected. "
        .. "Icons use Blizzard's faction art. These apply outdoors; Blizzard protects friendly plates in dungeons and raids."])
    local icons = Section(relations, "relationIcons", L["Icons"])
    Check(icons, "relations.showGroupIcon", "showGroupIcon", L["Show icon above group members"])
    Check(icons, "relations.showGuildIcon", "showGuildIcon", L["Show icon above guild members"])
    local colours = Section(relations, "relationColours", L["Social colours"])
    Colour(colours, "relations.group", "group", L["Group members"])
    Colour(colours, "relations.guild", "guild", L["Guild members"])
    Colour(colours, "relations.friend", "friend", L["Friends"])
    Colour(colours, "relations.recent", "recent", L["Recent allies"])
    local pvp = Section(relations, "relationPvp", L["PvP"], function()
        return LabelOf(model.friendlyPvpChoices, PS.GetSettings().friendlyPvpStyle)
    end)
    Choice(pvp, "relations.friendlyPvpStyle", "friendlyPvpStyle", L["PvP-flagged players"], model.friendlyPvpChoices)
    Colour(pvp, "relations.pvp", "pvp", L["PvP name colour"])

    -- Experimental: tests of what the game allows, each off by default (the page header's "?" says so,
    -- and /ps diagnose's experimental section reports what each saw).
    do
        local experimental = Page("experimental")
        local tokens = Section(experimental, "experimentalTokens", L["More threat sources"])
        Check(tokens, "experimental.experimentalSoftTargetThreat", "experimentalSoftTargetThreat", L["Soft target tokens"])
        SK.Add(tokens, SK.ControlHelp(tokens, L["Also reads threat through your soft targets (softenemy, softinteract), "
            .. "after the mouseover, for the plate they name. This client may not have them; then nothing changes."]))
        Check(tokens, "experimental.experimentalTargetOfTargetThreat", "experimentalTargetOfTargetThreat",
            L["Target of target / focus target"])
        SK.Add(tokens, SK.ControlHelp(tokens, L["Also reads threat through your target's target and your focus's target, "
            .. "for the plate they name. A gap read this way is kept (~) like one read on hover."]))
        local shown = Section(experimental, "experimentalDisplay", L["More threat shown"])
        Check(shown, "experimental.experimentalSoloCurveGap", "experimentalSoloCurveGap", L["Solo hover gap (curve)"])
        SK.Add(shown, SK.ControlHelp(shown, L["Solo, when the game keeps your raw threat private but says the enemy "
            .. "targets you, tries to show the gap through one of the game's curves without reading the number. "
            .. "If the game refuses, only the % shows, as now."]))
        Check(shown, "experimental.experimentalOutsideHolderRow", "experimentalOutsideHolderRow", L["Outside-group holder row"])
        SK.Add(shown, SK.ControlHelp(shown, L["In a Threat meter window, a row for whoever holds your target from outside "
            .. "your group, with its threat worked out from yours. Shown only when nobody in your group holds it."]))
    end

    -- Dungeon friendlies (listed in the Dungeon layout only).
    local dungeon = Page("dungeonFriendly", L["Use the same component preview and positions as outdoors, saved separately "
        .. "for Dungeon. Blizzard keeps its own friendly plate; the optional overlay may be blocked by this client."])
    local friendlies = Section(dungeon, "dungeonFriendly", L["Dungeon friendlies"])
    Check(friendlies, "dungeonFriendly.restrictedFriendlyNamesOnly", "restrictedFriendlyNamesOnly", L["Names only"], "dungeon")
    Check(friendlies, "dungeonFriendly.restrictedFriendlyClassColour", "restrictedFriendlyClassColour",
        L["Blizzard class colours, when available"], "dungeon")
    Check(friendlies, "dungeonFriendly.experimentalDungeonFriendlyText", "experimentalDungeonFriendlyText",
        L["Test editable overlay over native plate"], "dungeon")
    SK.Add(friendlies, SK.ControlHelp(friendlies, L["Off by default. The native plate stays visible, so duplicates are "
        .. "possible. Positions are separate; shared style and value-source controls still affect World. "
        .. "If nothing appears, the client may protect that plate."]))
    BuildBlizzardNameFontSection(SK, Section, Check, Choice, Bind, dungeon)

    -- Studio's own look and size: this player's preferences, applied at once, never saved in a profile.
    local studio = Page("studio")
    Options.editorStudioPage = studio
    local size = Section(studio, "studioSize", L["Studio size"], function()
        return Controls.PercentText(Options:GetStudioScale())
    end)
    local sizeRow = SK.Add(size, SK.Row(size, L["Size"]))
    local smaller = CreateStudioButton(sizeRow, "-", SK.SIZE_BUTTON, SK.CONTROL_H)
    smaller:SetPoint("LEFT", sizeRow, "LEFT", SK.CONTROL_X, 0)
    smaller:SetScript("OnClick", function() Options:SetStudioScale(Options:GetStudioScale() - 0.05) end)
    local sizeText = SK.Text(sizeRow, "", "value")
    sizeText:SetWidth(SK.SIZE_TEXT_W)
    sizeText:SetJustifyH("CENTER")
    sizeText:SetPoint("LEFT", smaller, "RIGHT", SK.CONTROL_GAP, 0)
    local larger = CreateStudioButton(sizeRow, "+", SK.SIZE_BUTTON, SK.CONTROL_H)
    larger:SetPoint("LEFT", sizeText, "RIGHT", SK.CONTROL_GAP, 0)
    larger:SetScript("OnClick", function() Options:SetStudioScale(Options:GetStudioScale() + 0.05) end)
    Options.editorStudioSmaller, Options.editorStudioLarger, Options.editorStudioScaleText = smaller, larger, sizeText
    Controls.AttachTooltip(smaller, L["Studio size"], { L["Make Blueprint Studio smaller."] })
    Controls.AttachTooltip(larger, L["Studio size"], { L["Make Blueprint Studio larger."] })
    local access = Section(studio, "accessibility", L["Accessibility"])
    Options.editorAccessCheckboxes = {}
    for _, spec in ipairs({
        { "colourBlind", L["Colour-blind friendly"],
            L["Threat colours in the preview use blue and orange; Studio's lines are thicker."] },
        { "highContrast", L["High contrast"],
            L["A dark inspector with white text, brighter lines and larger handles, and the plain dark preview."] },
    }) do
        local row, box = SK.CheckRow(access, nil, { text = spec[2], name = WidgetName("studio_" .. spec[1], "Checkbox"),
            get = function() return Options:StudioAccess()[spec[1]] end,
            set = function(enabled) Options:SetStudioAccess(spec[1], enabled) end })
        SK.Add(access, row)
        SK.Add(access, SK.ControlHelp(access, spec[3]))
        Options.editorAccessCheckboxes[spec[1]] = Register(box)
    end

    -- Help: how Studio works, in short sections.
    local help = Page("help")
    for _, entry in ipairs({
        { "helpColumns", L["The three columns"], L["The tree lists this plate type's parts and groups. The preview shows "
            .. "the plate; drag parts there. The inspector on the right edits what is selected: a part, a group or the "
            .. "Plate row."] },
        { "helpPlacement", L["Placement"], L["A part's parent in the tree is what it is anchored to: it moves with it and "
            .. "hides while it is hidden. In the inspector, Anchor to picks the parent and Behaviour pins the part to one "
            .. "of its edges (Level is pinned left of the name, so it follows the name's width) or leaves it Free."] },
        { "helpQuickLayout", L["Quick layout"], L["Select the tree's Plate row for Quick layout: pick a part for the top, "
            .. "bottom, left, right or centre of the health bar (the name on a names-only layout). Each pick is ordinary "
            .. "placement, so you can still drag or fine-tune the part; a part moved by hand shows as Custom."] },
        { "helpGroups", L["Groups"], L["Every plate starts with Text, Bars and Auras groups; change them freely. Drag a "
            .. "part onto a row to put it inside, or between rows to reorder. A group can stack its parts (Arrange): "
            .. "hidden parts take no space. Deleting a group leaves its parts where they are."] },
        { "helpParts", L["Parts"], L["Click a part to select it; its eye shows or hides it. Drag it in the preview "
            .. "(Shift: no snap), nudge it with the arrows (Shift for 10 px), or drag its handles to resize it. "
            .. "Right-click a row to rename, duplicate, layer, reset or delete it; + Add brings a deleted part back."] },
        { "helpPlateTypes", L["Plate types and layouts"], L["Enemies, Players and Friendly NPCs each have their own "
            .. "layout. Layout (top left) switches between World and Dungeon, which keep separate positions. Players and "
            .. "Friendly NPCs have a Names only and a Full plate layout; the switch under the preview picks one."] },
        { "helpSave", L["Save and Revert"], L["Changes show on your plates straight away. Save keeps them in the current "
            .. "profile; Revert goes back to the last save. Closing Studio with unsaved changes asks first. Profile (top "
            .. "right) switches, creates and renames profiles."] },
        { "helpCustom", L["Custom text, Style and Rules"], L["+ Add > Value > Custom text writes your own text, such as "
            .. "{health} / {health.max} ({health.percent}%). Style sets fonts, boxes and bar borders. Rules change a part "
            .. "while a condition holds, such as \"when tagged, set colour grey\". Test values try them in the preview."] },
        { "helpSharing", L["Sharing"], L["Export gives a share code (or readable JSON) for the current profile. Import "
            .. "takes one and lets you choose which sections to replace; press Save to keep them."] },
        { "helpCommands", L["Commands"], L["/ps opens Studio and /ps config opens Settings. /ps save and /ps revert act on "
            .. "unsaved changes; /ps profile <name> switches profile. /ps console shows or hides the threat windows. "
            .. "/ps diagnose opens a report to share when something looks wrong."] },
        { "helpThreat", L["Threat windows"], L["/ps console shows them: up to five, each a Threat meter (your group's "
            .. "threat on your target) or Tank (every enemy in view and who holds it). Drag a title to move a window and "
            .. "those snapped to it (Shift: alone); drop it on a side of Blizzard's damage meter to follow it. Right-click "
            .. "a title for its menu; click a row to spotlight its plate."] },
    }) do
        local section = Section(help, entry[1], entry[2])
        local body = SK.Add(section, SK.Help(section, entry[3]))
        SK.Ink(body.text, "label")
        if body.text.SetSpacing then body.text:SetSpacing(3) end
    end

    -- A value change can change a folded section's summary.
    Register({ Refresh = function()
        if Options.editorSettingsWorkspace and Options.editorSettingsWorkspace:IsShown() then
            Options:LayoutEditorSettingsPanels()
        end
    end })
end

function Options:BuildStudioInspector(workbench)
    local editor = self.editor
    local inspector = CreateFrame("Frame", nil, editor)
    inspector:SetFrameLevel(workbench:GetFrameLevel() + 2)
    Options.editorInspector = inspector
    -- Parchment: its labels are inked (Chrome's ApplyEditorTheme), at the inspector's compact sizes.
    inspector.studioLabelSize = { K.FONT, K.FONT }
    inspector.studioInkLabels = {}
    inspector.studioPaper = true
    Options.editorInspectorArt = chrome.TrackPanelArt(inspector, "parchment")

    -- Settings' page: the category's title and summary over its controls.
    local settingsWorkspace = CreateFrame("Frame", nil, editor)
    settingsWorkspace:SetFrameLevel(workbench:GetFrameLevel() + 2)
    Options.editorSettingsWorkspace = settingsWorkspace
    -- The same label sizes as Studio's other dark panels.
    settingsWorkspace.studioLabelSize = { 16, 14 }
    chrome.TrackPanelArt(settingsWorkspace, "dark")
    local settingsTitle = settingsWorkspace:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    settingsTitle:SetFont(K.FONT_PATH, 26)
    settingsTitle:SetTextColor(chrome.GOLD[1], chrome.GOLD[2], chrome.GOLD[3])
    Options.editorSettingsTitle = settingsTitle
    local settingsSummary = settingsWorkspace:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    settingsSummary:SetFont(K.FONT_PATH, 15)
    settingsSummary:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    Options.editorSettingsSummary = settingsSummary
    -- The page header's "?", for a category with a tooltip (Chrome's SetSettingsCategory shows it).
    local settingsHelp = CreateFrame("Button", nil, settingsWorkspace)
    settingsHelp:SetSize(18, 18)
    settingsHelp.art = settingsHelp:CreateTexture(nil, "ARTWORK")
    settingsHelp.art:SetAllPoints(settingsHelp)
    settingsHelp.art:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
    settingsHelp:SetScript("OnEnter", function(instance)
        if not GameTooltip or not instance.helpText then return end
        GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
        GameTooltip:SetText(instance.helpTitle or "", 1, 1, 1)
        GameTooltip:AddLine(instance.helpText, 1, 0.82, 0.45, true)
        GameTooltip:Show()
    end)
    settingsHelp:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    settingsHelp:Hide()
    Options.editorSettingsHelp = settingsHelp
    local settingsRule = settingsWorkspace:CreateTexture(nil, "ARTWORK")
    Theme.Place(settingsRule, "divider", settingsWorkspace, 0, 0, 600, 2)
    Options.editorSettingsRule = settingsRule
    local settingsViewport = CreateFrame("ScrollFrame", "PlateSmithEditorSettingsScroll", settingsWorkspace)
    local settingsContent = CreateFrame("Frame", nil, settingsViewport)
    settingsContent:SetSize(930, 815)
    settingsViewport:SetScrollChild(settingsContent)
    Options.editorSettingsViewport = settingsViewport
    Options.editorSettingsContent = settingsContent
    Options.editorSettingsScrollBar = chrome.CreateStudioScrollBar(settingsViewport, settingsWorkspace)
    Options.editorSettingsPanels = {}
    settingsWorkspace:Hide()

    Options.editorInspectorPages = {}
    local componentScroll = CreateFrame("ScrollFrame", "PlateSmithEditorInspectorScroll", inspector)
    local componentHolder = CreateFrame("Frame", nil, componentScroll)
    componentHolder:SetSize(K.WIDTH + INSPECTOR_PAD.left + INSPECTOR_PAD.right, 626 + INSPECTOR_PAD.top + INSPECTOR_PAD.bottom)
    local page = K.Flow(CreateFrame("Frame", nil, componentHolder))
    page:SetPoint("TOPLEFT", componentHolder, "TOPLEFT", INSPECTOR_PAD.left, -INSPECTOR_PAD.top)
    page:SetSize(K.WIDTH, 626)
    componentScroll:SetScrollChild(componentHolder)
    Options.editorComponentHolder = componentHolder
    Options.editorComponentScroll = componentScroll
    Options.editorComponentScrollBar = chrome.CreateStudioScrollBar(componentScroll, inspector)
    Options.editorComponentContent = page
    Options.editorInspectorPages.components = componentScroll
    Options.editorContextFrames = {}
    BuildSettingsPages(settingsContent)

    -- The column, top to bottom: header, Placement, the part's own sections, Style, Rules.
    BuildHeader(page)
    BuildPlacement(page)
    BuildTextContexts(page)
    BuildBarContexts(page)
    BuildValueContext(page)
    BuildAuraContexts(page)
    BuildGroupContext(page)
    BuildPlateContext(page)
    if self.BuildQuickLayoutSection then self:BuildQuickLayoutSection(page) end
    BuildStyle(page)
    BuildRules(page)
end

-- The column's width: PAD_X from the parchment on both sides, and the scroll bar's lane too
-- while the bar shows. The kit is built for the narrower column; its rows follow the width.
local function SetColumnWidth(options, withLane)
    local inspector, scroll = options.editorInspector, options.editorComponentScroll
    local width = inspector and inspector:GetWidth() or 0
    if width <= 0 then width = FRAME.width end
    local outer = width - FRAME.rail - (withLane and FRAME.lane or 0)
    local column = outer - INSPECTOR_PAD.left - INSPECTOR_PAD.right
    options.editorComponentContent:SetWidth(column)
    if options.editorComponentHolder then options.editorComponentHolder:SetWidth(outer) end
    if scroll then scroll:SetWidth(outer) end
    options.editorInspectorLane = withLane
end

-- Lays the column out for what is selected: each part's controls refreshed, then every shown
-- section stacked under the header. Laid out without the scroll bar's lane first; when the
-- column then overflows (the bar shows) it is laid out again inside the lane.
function Options:LayoutEditorInspector()
    local page = self.editorComponentContent
    if not page then return end
    if self.editorHeaderRefresh then self.editorHeaderRefresh() end
    local key = Selection().key
    if key and self.editorStyleRefresh then self.editorStyleRefresh() end
    if key and self.editorRulesRefresh then self.editorRulesRefresh() end
    local bar = self.editorComponentScrollBar
    SetColumnWidth(self, false)
    self:SetEditorInspectorContentHeight(math.max(1, K.LayoutFlow(page, 0)))
    if bar then bar:Sync() end
    if bar and bar:IsShown() then
        SetColumnWidth(self, true)
        self:SetEditorInspectorContentHeight(math.max(1, K.LayoutFlow(page, 0)))
        bar:Sync()
    end
end
