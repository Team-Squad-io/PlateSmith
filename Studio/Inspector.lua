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
    -- "Changed here" marks against World (Studio/Marks.lua).
    marks = Options.editorMarkConfig,
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
-- A row's "changed here" mark (UI/Layout's ChangedMark) and the areas it can name (Studio/Marks.lua).
local Mark, Area = K.ChangedMark, Options.editorMarkAreas

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

-- The same gold "?" as a settings row's help (UI/Layout's AttachHelp), lit while pointed at.
local function HelpButton(parent, title, lines, withFormatters)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(K.HELP_ICON, K.HELP_ICON)
    button.art = button:CreateTexture(nil, "ARTWORK")
    button.art:SetAllPoints(button)
    button.art:SetTexture(K.HELP_ICON_FILE)
    button.art:SetAlpha(K.HELP_ALPHA)
    Controls.AttachTooltip(button, title, lines)
    if button.HookScript then
        button:HookScript("OnEnter", function(self) self.art:SetAlpha(K.HELP_ALPHA_LIT) end)
        button:HookScript("OnLeave", function(self) self.art:SetAlpha(K.HELP_ALPHA) end)
    end
    AddExtensionHelp(button, withFormatters)
    return button
end

-- What the inspector shows (Editor's RefreshEditorInspectorContext sets it): key (a part),
-- group, plate, context (which part controls) and movable.
local function Selection() return Options.editorInspectorSelection or {} end
-- A part with PlateSmith's own sections (Placement, Style, Rules): not Blizzard's own name.
local function PartSelected()
    local selection = Selection()
    return selection.key ~= nil and selection.context ~= "blizzardName"
end
local function Profile() return PS.GetPlateProfileSettings(Options:EditorTarget()) end
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
            local ok = PS.SetPlateProfileOption(Options:EditorTarget(), key, value)
            Options:QueueRefresh()
            return ok
        end,
        set = function(value)
            local ok = PS.SetPlateProfileOption(Options:EditorTarget(), key, value)
            Options:Refresh(true)
            return ok
        end,
    })
    Mark(slider:GetParent(), Area.Option(key))
    return Register(slider)
end

local function SetProfileValue(key)
    return function(value)
        PS.SetPlateProfileOption(Options:EditorTarget(), key, value)
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
-- shown while its part is selected. The frame takes its place in the column at once; build(frame)
-- fills it the first time the context is shown (Options:BuildEditorContext), so opening Studio
-- does not build every part's rows in one go (the client stops a script that runs too long).
local contextBuilders = {}
local function CreateContext(page, key, build)
    local frame = K.Group(page)
    Options.editorContextFrames[key] = frame
    K.Add(page, frame, function() return Selection().context == key end)
    contextBuilders[key] = build
    return frame
end

-- Runs build(...) for Studio's on-demand pages and contexts: what it registered is refreshed and
-- given Studio's current look, as Options:Refresh and ApplyEditorTheme did for what was built with
-- the frame. A failure is reported once; what was built stays.
local function BuildLater(what, build, ...)
    local controls = Options.controls
    local first, marks = #controls + 1, Options.EditorThemeMarks and Options:EditorThemeMarks()
    local ok, failure = pcall(build, ...)
    if not ok then PS.Chat.ReportError(what, failure) end
    local settings = PS.GetSettings()
    local refreshing = Options.refreshing
    Options.refreshing = true
    for index = first, #controls do pcall(controls[index].Refresh, controls[index], settings) end
    Options.refreshing = refreshing
    if marks then Options:PaintEditorThemeSince(marks) end
    return ok
end
Options._BuildEditorLater = BuildLater

-- Fills a context's frame the first time it is wanted; true when it is built (or has nothing to build).
-- With nothing selected the inspector shows the Plate row's Quick layout, built with the plate's rows.
function Options:BuildEditorContext(key)
    key = key or "plate"
    local build = contextBuilders[key]
    if not build then return true end
    contextBuilders[key] = nil
    return BuildLater("studio inspector " .. key, build, self.editorContextFrames[key])
end

-- Whether a context's rows are still to be built (tests, Settings search).
function Options:IsEditorContextPending(key) return contextBuilders[key] ~= nil end

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
            PS.SetPlateValueSlot(Options:EditorTarget(), key, "name", edit:GetText())
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
    Controls.AttachTooltip(nameEdit, L["Rename"], { L["Click to name this part. Leave it blank for the default name."] })
    Options.editorComponentNameEdit = nameEdit
    -- A pencil after the name says it can be edited.
    local namePencil = CreateFrame("Button", nil, nameEdit)
    namePencil:SetSize(K.SWATCH, K.SWATCH)
    namePencil:SetPoint("RIGHT", nameEdit, "RIGHT", 0, 0)
    namePencil:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    namePencil:SetHighlightTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "ADD")
    namePencil:SetScript("OnClick", function() Options:BeginEditorRename(Options.selectedComponent) end)
    Controls.AttachTooltip(namePencil, L["Rename"], { L["Give this part its own name."] })
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
    Mark(band, Area.Entry("eye"), { anchor = eye, tipFrame = eye, resetLeft = true })
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
        if PartSelected() and Options.editorLayout and Options.editorLayout[selection.key] then
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
        -- Without the eye the name has the whole line.
        title:SetWidth(eye:IsShown() and K.WIDTH - eyeSlot or K.WIDTH)
    end
    K.Add(page, header)
end

-- Controls that cannot apply right now (Stacking while unmanaged) are dimmed this much.
local DIMMED_ALPHA = 0.55

-- Placement: what the part is anchored to (its parent in the tree; dragging it there does the
-- same) and how. Free keeps an offset from the parent's centre; pinned to an edge, it follows the
-- parent's size. Either way it moves with the parent and hides with a hidden one.
-- Combo points that Style › Position puts on the health bar: Placement has no say (Editor's
-- IsEditorPlacedByStyle), so Anchor to and Stick to are unavailable and say why.
local BY_STYLE_TIP = L["Style › Position puts the combo points on the health bar. Choose Where placed there to place "
    .. "them here."]
local function BuildPlacement(page)
    local section = K.Section(page, L["PLACEMENT"])
    Options.editorInspectorBasics = section
    -- Where it is, its anchor, pin and scale are one area, so the section carries the mark.
    Mark(section, Area.Entry("placement"))
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
    local behaviourRow = K.Row(section, L["Stick to"])
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
        disabledTip = function()
            if Options:IsEditorPlacedByStyle(Options.selectedComponent) then return BY_STYLE_TIP end
            return L["To pin it to an edge, anchor it to a part (not a group or the plate)."]
        end,
        enabled = function(value)
            return not Options:IsEditorPlacedByStyle(Options.selectedComponent) and (value == "static" or Pinnable())
        end,
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
    K.Add(section, K.Note(section, BY_STYLE_TIP), function() return Options:IsEditorPlacedByStyle(Options.selectedComponent) end)
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
    if anchor.SetMotionScriptsWhileDisabled then anchor:SetMotionScriptsWhileDisabled(true) end
    anchor:HookScript("OnEnter", function(instance)
        if instance:IsEnabled() or not GameTooltip then return end
        GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Anchor to"], 1, 1, 1)
        GameTooltip:AddLine(BY_STYLE_TIP, 1, 0.82, 0.45, true)
        GameTooltip:Show()
    end)
    anchor:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Options.editorPlacementRefresh = function()
        anchor:Refresh()
        SetAvailable(anchor, not Options:IsEditorPlacedByStyle(Options.selectedComponent))
        behaviour:Refresh()
    end
    K.Add(page, section, PartSelected)
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
            if not PS.SetPlateProfileOption(Options:EditorTarget(), key, value) then return false end
            Options:QueueRefresh()
            return true
        end,
        set = function(value)
            if not PS.SetPlateProfileOption(Options:EditorTarget(), key, value) then return false end
            Options:Refresh(true)
            return true
        end,
    })
    Register(slider)
    Mark(row, Area.Option(key))
    K.Add(section, row)
    local followRow, follow = K.CheckRow(section, nil, {
        text = followLabel,
        get = function()
            local profile = Profile()
            return profile and profile[key] == nil
        end,
        set = function(following)
            PS.SetPlateProfileOption(Options:EditorTarget(), key, not following and Effective() or nil)
            Options:Refresh(true)
        end,
    })
    Register(follow)
    K.Add(section, followRow)
end

-- The selected part's style, and one field of it written (PS.SetPartStyle; nil clears it). light: a
-- slider's step, which only the preview follows (once a frame); otherwise the preview and every
-- style-bound control (styleControls: Display's text rows and Style's) follow.
local styleControls = {}
local function SelectedStyle()
    local key = Options.selectedComponent
    local profile = Profile()
    return key and profile and profile.styles and profile.styles[key] or {}
end
local function WriteSelectedStyle(field, value, light)
    local key = Options.selectedComponent
    if not key or not PS.SetPartStyle(Options:EditorTarget(), key, field, value) then return false end
    if light then
        Options:QueueRefresh()
        return true
    end
    Options:RefreshEditorAppearance(PS.GetSettings())
    for _, control in ipairs(styleControls) do control:Refresh() end
    -- Combo points' Position decides whether Placement, drag and the nudges apply; Fit to bar width
    -- and Shape which size rows show.
    if field == "pipAnchor" or field == "pipFit" or field == "pipShape" then Options:RefreshEditorInspectorContext() end
    return true
end
local function KeepStyleControl(control)
    styleControls[#styleControls + 1] = control
    return Register(control)
end

-- Display's text rows, the same on every part that draws text, after the part's own rows: Font,
-- Font size, Font style (the outline) and Shadow. They write the selected part's style (font,
-- fontSize, outline, shadow) unless spec.bind(field) returns other accessors (an aura row keeps its
-- countdown's on its layout). Font size is in points: unset, it is Auto, the size the plate gives
-- the text (spec.auto(), by default Schema's PartTextSize), which the slider then shows with Auto ticked; moving it
-- sets a size and ticking Auto clears it (as a bar's own width and "Same width" do). spec.size
-- (section) builds the Font size row instead, for a size the part keeps itself (the name's, custom
-- text's). spec.context: whose rows they are, which Settings search finds (EditorDisplayRows).
local FONT_STYLE_CHOICES = { { value = "", label = L["Plate outline"] }, { value = "none", label = L["None"] },
    { value = "outline", label = L["Outline"] }, { value = "thick", label = L["Thick outline"] } }
local function FontChoices()
    local choices = { { value = "", label = L["Plate font"] } }
    for _, choice in ipairs(PS.Media.FontChoices()) do
        if choice.value ~= "default" then choices[#choices + 1] = choice end
    end
    return choices
end
local function StyleBinding(field)
    return function() return SelectedStyle()[field] end,
        function(value, light) return WriteSelectedStyle(field, value, light) end
end
local function NameDerivedSize()
    local profile = Profile()
    return Schema.PartTextSize(Options.selectedComponent, profile and profile.nameFontSize) or 12
end
local displayRows = {}
local function TextRows(section, spec)
    local bind, context, rows = spec.bind or StyleBinding, spec.context, {}
    -- Each row's mark: spec.area(field) when it binds elsewhere, else the part's style field.
    local function Add(label, row, field)
        K.Add(section, row)
        rows[#rows + 1] = { label = label, frame = row, section = section }
        if field then Mark(row, spec.area and spec.area(field) or Area.Style(field)) end
    end
    local getFont, setFont = bind("font")
    local fontRow, font = K.DropdownRow(section, L["Font"], { choices = FontChoices,
        name = WidgetName("selected_" .. context .. "_font", "Dropdown"),
        get = function() return getFont() or "" end,
        set = function(value) setFont(value ~= "" and value or nil) end })
    KeepStyleControl(font)
    Add(L["Font"], fontRow, "font")
    local sizeRow, autoRow
    if spec.size then
        sizeRow = spec.size(section)
    else
        local getSize, setSize = bind("fontSize")
        local Auto, range = spec.auto or NameDerivedSize, Schema.STYLE_FONT_SIZE
        local slider
        sizeRow, slider = K.SliderRow(section, L["Font size"], {
            -- The value box has room for "12 pt" only; the ticked Auto under it says it is Auto.
            min = range[1], max = range[2], step = 1, format = PointText,
            name = WidgetName("selected_" .. context .. "_fontSize", "Slider"),
            get = function() return getSize() or Auto() end,
            drag = function(value) return setSize(value, true) end,
            set = function(value) return setSize(value) end,
        })
        KeepStyleControl(slider)
        local auto
        autoRow, auto = K.CheckRow(section, nil, { text = spec.autoText or L["Auto: follows the name size"],
            name = WidgetName("selected_" .. context .. "_fontSizeAuto", "Checkbox"),
            get = function() return getSize() == nil end,
            set = function(on) setSize(not on and (getSize() or Auto()) or nil) end })
        KeepStyleControl(auto)
        autoRow.control = auto
    end
    Add(L["Font size"], sizeRow, not spec.size and "fontSize" or nil)
    if autoRow then K.Add(section, autoRow) end
    local getOutline, setOutline = bind("outline")
    local outlineRow, outline = K.DropdownRow(section, L["Font style"], { choices = FONT_STYLE_CHOICES,
        name = WidgetName("selected_" .. context .. "_outline", "Dropdown"),
        get = function() return getOutline() or "" end,
        set = function(value) setOutline(value ~= "" and value or nil) end })
    KeepStyleControl(outline)
    Add(L["Font style"], outlineRow, "outline")
    local getShadow, setShadow = bind("shadow")
    local shadowRow, shadow = K.CheckRow(section, L["Shadow"], { text = L["Drop shadow"],
        name = WidgetName("selected_" .. context .. "_shadow", "Checkbox"),
        get = function() return getShadow() == true end,
        set = function(on) setShadow(on) end })
    KeepStyleControl(shadow)
    Add(L["Shadow"], shadowRow, "shadow")
    displayRows[context] = rows
end

-- The contexts whose Display has the text rows, and those rows' labels (an aura row adds its
-- Timed only before them and its countdown's position after), so Settings search lists them before
-- the part's rows are built.
local TEXT_ROW_LABELS = { L["Font"], L["Font size"], L["Font style"], L["Shadow"] }
local DISPLAY_ROW_LABELS = { buffs = { L["Permanent"], L["Font"], L["Font size"], L["Font style"], L["Shadow"],
    L["Text position"] } }
DISPLAY_ROW_LABELS.debuffs = DISPLAY_ROW_LABELS.buffs
for _, context in ipairs({ "name", "level", "guild", "tagged", "targetName", "quest", "classification", "threat",
    "combo", "targetedBy", "cast", "value" }) do
    DISPLAY_ROW_LABELS[context] = TEXT_ROW_LABELS
end
Options._editorDisplayRowLabels = DISPLAY_ROW_LABELS

-- A part's Display text rows (label, and once its rows are built frame and section), for Settings
-- search; nil while it has none (a custom part that is a bar, box or icon).
function Options:EditorDisplayRows(key)
    local context = self.EditorPartContext and self:EditorPartContext(key)
    if context == "value" then
        local profile = Profile()
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if not slot or slot.kind then return nil end
    end
    if not context then return nil end
    -- Blizzard's name shows on this tab only the rows that apply to it.
    if context == "blizzardName" then
        local rows = {}
        for _, row in ipairs(displayRows.blizzardName or {}) do
            if Options.BlizzardNameRowShown(row.label) then rows[#rows + 1] = row end
        end
        if displayRows.blizzardName then return rows end
    elseif displayRows[context] then
        return displayRows[context]
    end
    local labels = DISPLAY_ROW_LABELS[context]
    if not labels then return nil end
    local rows = {}
    for _, label in ipairs(labels) do
        if context ~= "blizzardName" or Options.BlizzardNameRowShown(label) then rows[#rows + 1] = { label = label } end
    end
    return rows
end

-- Style rows Settings search finds for a part (beyond its Display rows): { label, help }. The combo
-- points' Show row, so "combo", "empty" and "points" lead to it.
Options.COMBO_SHOW_ROW_HELP = L["When the combo row appears on your target. With no points, Always shows empty pips."]
function Options:EditorStyleSearchRows(key)
    if key ~= "combo" then return nil end
    return { { label = L["Show row"], help = Options.COMBO_SHOW_ROW_HELP } }
end

-- Every built context's Display text rows, by context (tests check them against the labels above).
function Options:EditorBuiltDisplayRows() return displayRows end

-- Text parts: the name, target's name and the relationship marks. Each part that draws text has a
-- Display section: what it shows, then the same text rows (TextRows).
local function BuildTextContexts(page)
    CreateContext(page, "name", function(context)
        local nameSection = K.Section(context, L["DISPLAY"])
        K.Add(context, nameSection)
        local getSurnames, setSurnames = SettingControl("showPlayerSurnames")
        local surnameRow, surnames = K.CheckRow(nameSection, L["Surnames"], { text = L["Show player surnames"],
            name = WidgetName("selected_showPlayerSurnames", "Checkbox"), get = getSurnames, set = setSurnames })
        Register(surnames)
        local function FriendlyPlayers() return Options.editorProfile == "friendlyPlayer" end
        K.Add(nameSection, surnameRow, FriendlyPlayers)
        Options.SharedSettingNote(K, nameSection, FriendlyPlayers)
        Options.editorSurnameControl = surnames
        Options.ThreatColourPartCheck(K, nameSection, "name")
        -- The name's Font size is this plate type's name size in points, which the other texts follow.
        TextRows(nameSection, { context = "name", size = function(section)
            return ProfileSliderRow(section, L["Font size"], "nameFontSize", profileRanges.nameFontSize, 1, PointText):GetParent()
        end })
    end)

    -- Level, guild and the tagged mark draw only text: Display holds the text rows.
    for _, key in ipairs({ "level", "guild", "tagged" }) do
        CreateContext(page, key, function(context)
            local section = K.Section(context, L["DISPLAY"])
            K.Add(context, section)
            TextRows(section, { context = key })
        end)
    end

    CreateContext(page, "targetName", function(context)
        local targetSection = K.Section(context, L["DISPLAY"])
        K.Add(context, targetSection)
        local getHide, setHide = SettingControl("targetNameHideSelf")
        local hideRow, hide = K.CheckRow(targetSection, nil, { text = L["Hide when it targets you"],
            name = WidgetName("selected_targetNameHideSelf", "Checkbox"), get = getHide, set = setHide })
        Register(hide)
        K.Add(targetSection, hideRow)
        Options.SharedSettingNote(K, targetSection)
        K.Add(targetSection, K.Help(targetSection, L["The client can withhold it in some places; then nothing shows."]))
        TextRows(targetSection, { context = "targetName" })
    end)

    -- The quest mark's progress text: this plate type's option, off by default.
    CreateContext(page, "quest", function(context)
        local questSection = K.Section(context, L["DISPLAY"])
        K.Add(context, questSection)
        local progressRow, progress = K.DropdownRow(questSection, L["Progress"], {
            choices = { { value = "off", label = L["Off"] }, { value = "beside", label = L["Beside the mark"] },
                { value = "instead", label = L["Instead of the mark"] } },
            name = WidgetName("selected_questProgress", "Dropdown"),
            get = function() return ProfileValue("questProgress")() or "off" end,
            set = SetProfileValue("questProgress"),
        })
        Register(progress)
        Mark(progressRow, Area.Option("questProgress"))
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
        Mark(formatRow, Area.Option("questProgressFormat"))
        K.Add(questSection, formatRow, function() return (ProfileValue("questProgress")() or "off") ~= "off" end)
        K.Add(questSection, K.Help(questSection, L["The objective's progress from your quest log, when the game shares "
            .. "it; otherwise nothing shows. Custom text can show it too: {quest.progress} or {quest.percent}."]))
        TextRows(questSection, { context = "quest" })
    end)

    CreateContext(page, "questLoot", function(context)
        local lootSection = K.Section(context, L["QUEST LOOT MARKER"])
        K.Add(context, lootSection)
        -- The loot bag follows the quest mark unless freed; freeing or re-anchoring keeps it in place.
        local lootRow, loot = K.CheckRow(lootSection, nil, {
            text = L["Anchor to the quest marker"],
            get = function()
                local position = Options.editorLayout and Options.editorLayout.questLoot
                return position and position.parent == "quest"
            end,
            set = function(anchored)
                if PS.SetComponentAnchor("questLoot", anchored and "quest" or nil, Options:EditorTarget(),
                    Options:CurrentEditorVariant()) then
                    Options:ReloadEditorLayoutCopy()
                    Options:RefreshEditorLayout()
                    Options:RefreshEditorInspectorContext()
                end
            end,
        })
        Register(loot)
        K.Add(lootSection, lootRow)
    end)

    CreateContext(page, "relationshipIcon", function(context)
        local badgeSection = K.Section(context, L["FRIENDLY PLAYER BADGES"])
        K.Add(context, badgeSection)
        for _, badge in ipairs({ { "showGroupIcon", L["Above group members"] }, { "showGuildIcon", L["Above guild members"] } }) do
            local get, set = SettingControl(badge[1])
            local row, checkbox = K.CheckRow(badgeSection, nil, { text = badge[2],
                name = WidgetName("selected_" .. badge[1], "Checkbox"), get = get, set = set })
            Register(checkbox)
            K.Add(badgeSection, row)
        end
        Options.SharedSettingNote(K, badgeSection, nil, true)
    end)

    CreateContext(page, "pvpIcon", function(context)
        local pvpSection = K.Section(context, L["FRIENDLY PLAYER PVP"])
        K.Add(context, pvpSection)
        local getPvp, setPvp = SettingControl("friendlyPvpStyle")
        local pvpRow, pvp = K.DropdownRow(pvpSection, L["Display"], { choices = model.friendlyPvpChoices,
            name = WidgetName("selected_friendlyPvpStyle", "Dropdown"), get = getPvp, set = setPvp })
        Register(pvp)
        K.Add(pvpSection, pvpRow)
        -- The flagged name's colour (relationshipColours.pvp), while Display colours it.
        local function NameColoured()
            local style = PS.GetSettings().friendlyPvpStyle
            return style == "colour" or style == "both"
        end
        local function SetPvpColour(r, g, b)
            PS.SetRelationshipColour("pvp", r, g, b)
            Options:Refresh(true)
        end
        local colourRow, colour = K.SwatchRow(pvpSection, L["Name colour"], {
            name = WidgetName("selected_pvpColour", "Colour"),
            get = function() return PS.GetSettings().relationshipColours.pvp end,
            set = SetPvpColour,
        })
        Register(colour)
        K.Add(pvpSection, colourRow, NameColoured)
        local green = Schema.BLIZZARD_PVP_GREEN
        local greenRow, greenButton = K.ButtonRow(pvpSection, L["Blizzard green"], 130, nil, K.CONTROL_X)
        greenButton:SetScript("OnClick", function() SetPvpColour(green.r, green.g, green.b) end)
        Controls.AttachTooltip(greenButton, L["Blizzard green"],
            { L["The colour Blizzard's own nameplates give a PvP-flagged ally's name."] })
        -- Unavailable while the colour already is Blizzard's.
        function greenButton:Refresh(settings)
            local current = settings.relationshipColours.pvp
            SetAvailable(self, not (current.r == green.r and current.g == green.g and current.b == green.b))
        end
        Register(greenButton)
        K.Add(pvpSection, greenRow, NameColoured)
        Options.SharedSettingNote(K, pvpSection)
    end)

    CreateContext(page, "classification", function(context)
        local markSection = K.Section(context, L["DISPLAY"])
        K.Add(context, markSection)
        local getMark, setMark = SettingControl("classificationStyle")
        local markRow, mark = K.DropdownRow(markSection, L["Style"], { choices = model.classificationStyleChoices,
            name = WidgetName("selected_classificationStyle", "Dropdown"), get = getMark, set = setMark })
        Register(mark)
        K.Add(markSection, markRow)
        Options.SharedSettingNote(K, markSection)
        K.Add(markSection, K.Help(markSection, L["Icons: gold dragon elite, silver dragon rare or rare elite, skull world boss."]))
        TextRows(markSection, { context = "classification" })
    end)

    -- The threat text's form, shared by every plate type (and the Tank window's threat column).
    CreateContext(page, "threat", function(context)
        local threatSection = K.Section(context, L["DISPLAY"])
        K.Add(context, threatSection)
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
        Options.SharedSettingNote(K, threatSection, nil, true)
        TextRows(threatSection, { context = "threat" })
    end)

    CreateContext(page, "combo", function(context)
        local comboSection = K.Section(context, L["DISPLAY"])
        K.Add(context, comboSection)
        K.Add(comboSection, K.Help(comboSection, L["Shows on your target's plate only: your combo points in any form, and an empty row "
            .. "while you can build them (a rogue, or a druid in cat form). Style sets the pips' shape, position, colours, glow, "
            .. "size, spacing and when the row shows. Custom text can show the count: {combo}."]))
        TextRows(comboSection, { context = "combo" })
    end)

    CreateContext(page, "targetedBy", function(context)
        local targetedSection = K.Section(context, L["DISPLAY"])
        K.Add(context, targetedSection)
        K.Add(targetedSection, K.Help(targetedSection, L["A small badge for each group member targeting this enemy, in their "
            .. "class colour: your party, or a raid's tanks (up to four). Shown only where the game says who is targeting; "
            .. "otherwise the badge stays hidden. Style sets the size, spacing and direction."]))
        -- Initials are on unless the style says false.
        local initialsRow, initials = K.CheckRow(targetedSection, L["Initials"], { text = L["Show each member's initial"],
            name = WidgetName("selected_targetedBy_initials", "Checkbox"),
            get = function() return SelectedStyle().badgeInitial ~= false end,
            -- On clears the field (nil: initials show); off stores false. (on and nil or false is always false.)
            set = function(on)
                if on then return WriteSelectedStyle("badgeInitial", nil) end
                return WriteSelectedStyle("badgeInitial", false)
            end,
        })
        KeepStyleControl(initials)
        Mark(initialsRow, Area.Style("badgeInitial"))
        K.Add(targetedSection, initialsRow)
        TextRows(targetedSection, { context = "targetedBy", autoText = L["Auto: follows the badge size"], auto = function()
            local geometry = PS.TargetedBy
            return geometry and geometry.InitialFontSize(geometry.StyleOf(SelectedStyle())) or 8
        end })
    end)

    -- Parts with nothing of their own beyond Placement, Style and Rules.
    for _, key in ipairs({ "raidIcon", "other" }) do CreateContext(page, key) end
end

-- Bars: health (its size, the plate's bar texture and colour), power and cast.
local function BuildBarContexts(page)
    CreateContext(page, "health", function(context)
        local health = K.Section(context, L["BAR"])
        K.Add(context, health)
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
        Mark(textureRow, Area.Option("healthTexture"))
        K.Add(health, textureRow)
        K.Add(health, K.ControlHelp(health, L["Every bar on this plate, unless its Style picks its own."]))
        -- Choosing a colour switches the bar to it; cancelling restores both colour and mode.
        local modeBeforePicker
        local colourRow, colourSwatch = K.SwatchRow(health, L["Colour"], {
            beforeOpen = function() modeBeforePicker = ProfileValue("healthColourMode")() end,
            get = ProfileValue("healthColour"),
            set = function(r, g, b)
                PS.SetPlateProfileHealthColour(Options:EditorTarget(), r, g, b)
                Options:Refresh(true)
            end,
            cancel = function(previous)
                PS.SetPlateProfileHealthColour(Options:EditorTarget(), previous.r, previous.g, previous.b)
                PS.SetPlateProfileOption(Options:EditorTarget(), "healthColourMode", modeBeforePicker)
                Options:Refresh(true)
            end,
        })
        Register(colourSwatch)
        Register(K.RowCheck(colourRow, {
            text = L["Custom"],
            get = function() return ProfileValue("healthColourMode")() == "custom" end,
            set = function(custom) SetProfileValue("healthColourMode")(custom and "custom" or "automatic") end,
        }))
        Mark(colourRow, Area.Option({ "healthColour", "healthColourMode" }))
        K.Add(health, colourRow)
        Options.ThreatColourPartCheck(K, health, "health")
    end)

    CreateContext(page, "power", function(context)
        local power = K.Section(context, L["POWER BAR"])
        K.Add(context, power)
        K.Add(power, ProfileSliderRow(power, L["Height"], "powerHeight", profileRanges.powerHeight, 1):GetParent())
        BarSize(power, L["Width"], "powerWidth", L["Same width as the health bar"])
        K.Add(power, K.Help(power, L["Hidden when the client reports no power."]))
    end)

    CreateContext(page, "cast", function(context)
        local cast = K.Section(context, L["CAST BAR"])
        K.Add(context, cast)
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
        Mark(iconRow, Area.Option("castIcon"))
        K.Add(cast, iconRow)
        -- Colour by interrupt (Nameplates/Interrupt.lua): three colours, shown while it is on. Colours
        -- are written whole (a new castColours), never changed in place.
        local function CastCheck(key, label, text)
            local row, checkbox = K.CheckRow(cast, label, {
                text = text, name = WidgetName("selected_" .. key, "Checkbox"),
                get = function() return ProfileValue(key)() == true end,
                set = SetProfileValue(key),
            })
            Register(checkbox)
            Mark(row, Area.Option(key))
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
            Mark(row, Area.Option("castColours"))
            K.Add(cast, row, ByInterrupt)
        end
        K.Add(cast, K.Help(cast, L["Ready: the cast can be interrupted and your interrupt is ready. On cooldown: it can, but "
            .. "yours is not ready or you have none. Where the game withholds either, the bar keeps its own colour."]), ByInterrupt)
        CastCheck("castOnTop", L["Layer"], L["Draw casts above other plates"])
        K.Add(cast, K.Help(cast, L["A casting plate draws over its neighbours where plates overlap; your target stays on top."]))

        -- Display: whether the time left and the spell's name show (the profile's cast options), then
        -- their text rows (the cast part's style; names-only casts use them too).
        local castDisplay = K.Section(context, L["DISPLAY"])
        K.Add(context, castDisplay)
        for _, option in ipairs({ { "castTime", L["Time left"], L["Show time left"] },
            { "castName", L["Spell"], L["Show the spell's name"] } }) do
            local key = option[1]
            local row, checkbox = K.CheckRow(castDisplay, option[2], {
                text = option[3], name = WidgetName("selected_" .. key, "Checkbox"),
                get = function() return ProfileValue(key)() ~= false end,
                set = SetProfileValue(key),
            })
            Register(checkbox)
            Mark(row, Area.Option(key))
            K.Add(castDisplay, row)
        end
        TextRows(castDisplay, { context = "cast" })
    end)
end

-- Custom values: a live value, custom text, or a shape (bar, box, icon).
local function BuildValueContext(page)
    CreateContext(page, "value", function(context)
        local section = K.Section(context, L["LIVE VALUE"])
        K.Add(context, section)
        -- light: while dragged or typed, only the preview follows (once a frame). The full refresh
        -- redraws the inspector too; reselect when the part's controls change with it (its source).
        local function WriteSlot(field, value, reselect, light)
            local slot, key = SelectedSlot()
            if not slot or not PS.SetPlateValueSlot(Options:EditorTarget(), key, field, value) then return false end
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
        -- A custom part is one area (its whole slot): its title, what it shows and its picture carry it.
        Mark(section, Area.Part("slot"))
        Mark(sourceRow, Area.Part("slot"))
        K.Add(section, sourceRow, function() return Kind() == nil or Kind() == "bar" end)
        -- An icon's picture, in the source's place.
        local iconRow, icon = K.DropdownRow(section, L["Picture"], {
            choices = catalog.iconChoices, name = WidgetName("selected_value_icon", "Dropdown"),
            get = function() return SlotField("icon")() or "raid8" end,
            set = function(value) WriteSlot("icon", value) end,
        })
        controls[#controls + 1] = icon
        Register(icon)
        Mark(iconRow, Area.Part("slot"))
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
                .. "{threat.percent} {threat.lead} {threat.leadpercent} {threat.raw} {threat.hold} {level} {level.smart} "
                .. "{level.diff} {name} "
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
                if key and key:match("^value%d+$") and PS.SetPlateValueSlot(Options:EditorTarget(), key, "layer", value) then
                    Options:RefreshEditorAppearance(PS.GetSettings())
                end
            end,
        })
        controls[#controls + 1] = layer
        K.Add(section, layerRow)
        -- Text (a live value or custom text): its text rows; its Font size is the part's own, in points.
        local display = K.Section(context, L["DISPLAY"])
        K.Add(context, display, function() return Kind() == nil end)
        TextRows(display, { context = "value", size = function(parent)
            local sizeRange = Schema.valueFontRange
            local sizeRow, size = K.SliderRow(parent, L["Font size"], {
                min = sizeRange[1], max = sizeRange[2], step = 1, format = PointText, get = SlotField("fontSize"),
                name = WidgetName("selected_value_fontSize", "Slider"),
                drag = function(value) return WriteSlot("fontSize", value, false, true) end,
                set = function(value) return WriteSlot("fontSize", value) end,
            })
            controls[#controls + 1] = size
            return sizeRow
        end })
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
    end)
end

-- Aura rows: which auras show, and their grid.
local function BuildAuraContexts(page)
    local ranges = Schema.auraLayoutRanges
    for _, definition in ipairs({ { key = "buffs", source = "buffSource" }, { key = "debuffs", source = "debuffSource" } }) do
        local kind = definition.key
        CreateContext(page, kind, function(context)
            local function Layout(field) return function()
                local profile = Profile()
                return profile and profile.auraLayouts and profile.auraLayouts[kind][field]
            end end
            -- light: a slider's step, which only the preview follows (once a frame).
            local function Write(field, light) return function(value)
                if not PS.SetPlateAuraLayout(Options:EditorTarget(), kind, field, value) then return false end
                if light then Options:QueueRefresh() else Options:RefreshEditorAppearance(PS.GetSettings()) end
                return true
            end end
            -- Which auras show and how their countdown text looks.
            local which = K.Section(context, L["DISPLAY"])
            K.Add(context, which)
            local getSource, setSource = SettingControl(definition.source)
            local sourceRow, source = K.DropdownRow(which, L["Source"], { choices = model.auraSourceChoices,
                name = WidgetName("selected_" .. definition.source, "Dropdown"), get = getSource, set = setSource })
            Register(source)
            K.Add(which, sourceRow)
            Options.SharedSettingNote(K, which)
            -- Timed only (the row's timedOnly; off is stored as absent). The game's own aura container,
            -- used where it keeps aura times private, cannot be filtered, so there every aura shows.
            local timedRow, timed = K.CheckRow(which, L["Permanent"], { text = L["Hide permanent auras"],
                name = WidgetName("selected_" .. kind .. "_timedOnly", "Checkbox"),
                get = function() return Layout("timedOnly")() == true end,
                set = function(on) Write("timedOnly")(on and true or nil) end })
            Register(timed)
            K.AttachHelp(timedRow, L["Hides passives and auras like Devotion Aura. In dungeons, where the game keeps "
                .. "aura times private, all auras still show."])
            Mark(timedRow, Area.Aura(kind, "timedOnly"))
            K.Add(which, timedRow)
            -- The countdown on each icon: whether it shows, then its text rows, kept on the row's layout
            -- (timeFont, timeSize as a share of the icon, timeOutline, timeShadow).
            local timeRow, time = K.CheckRow(which, L["Time left"], { text = L["Show time left"],
                get = Layout("showDuration"), set = Write("showDuration") })
            Register(time)
            Mark(timeRow, Area.Aura(kind, "showDuration"))
            K.Add(which, timeRow)
            local TIME_FIELDS = { font = "timeFont", fontSize = "timeFontSize", outline = "timeOutline", shadow = "timeShadow" }
            TextRows(which, { context = kind, autoText = L["Auto: follows the icon size"],
                bind = function(field)
                    local get = Layout(TIME_FIELDS[field])
                    return get, function(value, light) return Write(TIME_FIELDS[field], light)(value) end
                end,
                area = function(field) return Area.Aura(kind, TIME_FIELDS[field]) end,
                -- Auto: the countdown's share of its icon, as the plates draw it (PS.AuraCountdownFont).
                auto = function()
                    local profile = Profile()
                    local layout = profile and profile.auraLayouts and profile.auraLayouts[kind]
                    if not (layout and PS.AuraCountdownFont) then return 8 end
                    local auto = PS.Table.DeepCopy(layout)
                    auto.timeFontSize = nil
                    local _, size = PS.AuraCountdownFont(auto, { textScale = 1 })
                    return size
                end })
            -- Where the countdown sits on each icon, after the standard text rows.
            local positionRow, position = K.DropdownRow(which, L["Text position"], {
                choices = { { value = "bottom", label = L["Bottom centre"] }, { value = "centre", label = L["Centre"] },
                    { value = "top", label = L["Top centre"] }, { value = "bottomright", label = L["Bottom right"] } },
                name = WidgetName("selected_" .. kind .. "_timePosition", "Dropdown"),
                get = function() return Layout("timePosition")() or "bottom" end,
                set = function(value) Write("timePosition")(value ~= "bottom" and value or nil) end,
            })
            KeepStyleControl(position)
            Mark(positionRow, Area.Aura(kind, "timePosition"))
            K.Add(which, positionRow)
            local rows = displayRows[kind]
            table.insert(rows, 1, { label = L["Permanent"], frame = timedRow, section = which })
            rows[#rows + 1] = { label = L["Text position"], frame = positionRow, section = which }
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
                Mark(row, Area.Aura(kind, field))
                K.Add(grid, row)
            end
            local growRow = K.Row(grid, L["Grow"])
            Register(K.Segmented(growRow, {
                choices = { { value = "right", label = L["L to R"], tooltip = L["Left to right"] },
                    { value = "left", label = L["R to L"], tooltip = L["Right to left"] },
                    { value = "centre", label = L["Centre"], tooltip = L["From the centre"] } },
                get = Layout("growX"), set = Write("growX"),
            }))
            Mark(growRow, Area.Aura(kind, "growX"))
            K.Add(grid, growRow)
            local linesRow = K.Row(grid, L["More lines"])
            Register(K.Segmented(linesRow, {
                choices = { { value = "up", label = L["Up"], tooltip = L["Stack upwards"] },
                    { value = "down", label = L["Down"], tooltip = L["Stack downwards"] } },
                get = Layout("growY"), set = Write("growY"),
            }))
            Mark(linesRow, Area.Aura(kind, "growY"))
            K.Add(grid, linesRow)
        end)
    end
end

-- Style: how a text, bar, pip or badge part looks. Text: a box behind it (its font, size, outline and
-- shadow are in Display). Bars: texture, background and border. Pips (combo points): colours, size
-- and spacing. Badges ("Targeted by"): size, spacing and direction.
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
    local Style, Keep, WriteStyle = SelectedStyle, KeepStyleControl, WriteSelectedStyle
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
        Mark(row, Area.Style(field))
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
        Mark(row, Area.Style(field))
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
        Mark(row, Area.Style(field))
        return row
    end

    -- Text: the box behind it (its shape, its fill and border with their opacity, and padding). A rounded
    -- box is Blizzard's own level box in its own colours, so Fill and Border are for the square one.
    local function SquareBox() return Text() and Style().boxShape ~= "rounded" end
    K.Add(section, K.SubHeader(section, L["Box behind"]), Text)
    K.Add(section, CheckRow(L["Box"], "box", true, L["Show a box"]), Text)
    K.Add(section, DropdownRow(L["Shape"], "boxShape", {
        { value = "", label = L["Square"] }, { value = "rounded", label = L["Rounded (Blizzard's)"] },
    }, "selected_style_box_shape"), Text)
    K.Add(section, K.Help(section, L["Rounded is Blizzard's own nameplate level box, in its own colours."]),
        function() return Text() and Style().boxShape == "rounded" end)
    K.Add(section, SwatchRow(L["Fill"], "boxColour", STYLE_DEFAULTS.boxColour, true), SquareBox)
    local boxBorder = SwatchRow(L["Border"], "boxBorder", STYLE_DEFAULTS.boxBorder, true)
    K.Add(section, boxBorder, SquareBox)
    local paddingRow, padding = K.SliderRow(section, L["Padding"], {
        min = Schema.STYLE_PADDING[1], max = Schema.STYLE_PADDING[2], step = 1,
        get = function() return Style().padding or STYLE_DEFAULTS.padding end,
        drag = function(value) return WriteStyle("padding", value, true) end,
        set = function(value) return WriteStyle("padding", value) end,
    })
    Keep(padding)
    Mark(paddingRow, Area.Style("padding"))
    K.Add(section, paddingRow, Text)

    -- Pips (combo points): the shape and where the row sits, the filled and empty colours with their
    -- opacity (or your class colour), a glow on filled pips, each pip's size and the gap, and Fit to bar
    -- width (the row spans the health bar: Schema.PipRow works out the width, or the gap, it replaces).
    local function Pips() return StyleKind(Options.selectedComponent) == "pips" end
    -- Round, square, diamond and Blizzard's pips are as tall as wide: one Size instead of Width and Height.
    local function Even() return Pips() and Style().pipShape ~= nil and Style().pipShape ~= "segments" end
    local function Sized() return Pips() and not Even() end
    local function Fit() return Pips() and Style().pipFit == true end
    K.Add(section, K.SubHeader(section, L["Pips"]), Pips)
    K.Add(section, DropdownRow(L["Shape"], "pipShape", {
        { value = "", label = L["Blocks"] }, { value = "round", label = L["Round coins"] },
        { value = "square", label = L["Squares"] }, { value = "diamond", label = L["Diamonds"] },
        { value = "segments", label = L["Bar segments"] }, { value = "blizzard", label = L["Blizzard's"] },
    }, "selected_style_pip_shape"), Pips)
    K.Add(section, DropdownRow(L["Position"], "pipAnchor", {
        { value = "", label = L["Where placed"] }, { value = "edge", label = L["On the bar's bottom edge"] },
        { value = "above", label = L["Above the bar"] }, { value = "below", label = L["Below the bar"] },
    }, "selected_style_pip_anchor"), Pips)
    -- Show row (pipShowRow): when the row appears on your target; "" is Always (empty pips at 0).
    K.Add(section, DropdownRow(L["Show row"], "pipShowRow", {
        { value = "", label = L["Always"] }, { value = "combat", label = L["In combat or with points"] },
        { value = "points", label = L["Only with points"] },
    }, "selected_style_pip_show_row"), Pips)
    K.Add(section, K.Help(section, Options.COMBO_SHOW_ROW_HELP), Pips)
    K.Add(section, SwatchRow(L["Filled"], "pipFill", STYLE_DEFAULTS.pipFill, true), Pips)
    K.Add(section, SwatchRow(L["Empty"], "pipEmpty", STYLE_DEFAULTS.pipEmpty, true), Pips)
    K.Add(section, CheckRow(L["Class colour"], "pipClassColour", true, L["Fill with your class colour"]), Pips)
    K.Add(section, CheckRow(L["Glow"], "pipGlow", true, L["Glow behind filled pips"]), Pips)
    K.Add(section, CheckRow(L["Fit to bar width"], "pipFit", true, L["Make the row as wide as the health bar"]), Pips)
    K.Add(section, K.Help(section, L["The row spans the health bar: blocks and segments widen (Spacing sets the gaps), "
        .. "other shapes keep their Size and spread out."]), Fit)
    -- With Fit to bar width, the row's width sets the segments' Width, or the other shapes' Spacing.
    local function FreeWidth() return Sized() and not Fit() end
    local function FreeSpacing() return Pips() and not (Fit() and Even()) end
    for _, size in ipairs({ { L["Size"], "pipWidth", Even }, { L["Width"], "pipWidth", FreeWidth }, { L["Height"], "pipHeight", Sized },
        { L["Spacing"], "pipSpacing", FreeSpacing } }) do
        local field, range = size[2], Schema.STYLE_PIPS[size[2]]
        local row, slider = K.SliderRow(section, size[1], {
            min = range[1], max = range[2], step = 1,
            get = function() return Style()[field] or STYLE_DEFAULTS[field] end,
            drag = function(value) return WriteStyle(field, value, true) end,
            set = function(value) return WriteStyle(field, value) end,
        })
        Keep(slider)
        Mark(row, Area.Style(field))
        K.Add(section, row, size[3])
    end
    K.Add(section, K.Help(section, L["Width, Height and Size set each point; Placement › Scale enlarges the whole part."]), Pips)

    -- Badges ("Targeted by"): each badge's size and the gap, and the row's direction (initials are in Display).
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
        Mark(row, Area.Style(field))
        K.Add(section, row, Badges)
    end
    local orientationRow, orientation = K.DropdownRow(section, L["Direction"], {
        choices = { { value = "horizontal", label = L["Row"] }, { value = "vertical", label = L["Column"] } },
        name = WidgetName("selected_style_badge_direction", "Dropdown"),
        get = function() return Style().badgeOrientation or STYLE_DEFAULTS.badgeOrientation end,
        set = function(value) WriteStyle("badgeOrientation", value) end,
    })
    Keep(orientation)
    Mark(orientationRow, Area.Style("badgeOrientation"))
    K.Add(section, orientationRow, Badges)

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
    barBorder.changedMark.area = Area.Style({ "borderColour", "border" })
    K.Add(section, barBorder, Bar)

    -- Presets: built-in looks and your saved ones, for this kind of part. Applying one replaces
    -- the part's style (and its rules, when it has some).
    local function PresetEntries()
        local key = Options.selectedComponent
        local kind = key and StyleKind(key)
        local entries = {}
        local function Apply(preset)
            if PS.ApplyStylePreset(Options:EditorTarget(), key, preset) then Options:RefreshEditorAppearance(PS.GetSettings()) end
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
    -- Display's text rows and Style's, for the part now selected.
    Options.editorStyleRefresh = function()
        for _, control in ipairs(styleControls) do control:Refresh() end
    end
    K.Add(page, section, function() return PartSelected() and StyleKind(Selection().key) ~= nil end)
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
    if not key or not PS.SetPartRules(Options:EditorTarget(), key, #list > 0 and list or nil) then return false end
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
    -- After the box itself (its own width), so the label never runs under it.
    whenRow.label:SetPoint("LEFT", enabled, "RIGHT", K.SWATCH_GAP, 0)
    whenRow.labelX = pad + (enabled:GetWidth() or K.CHECK_W) + K.SWATCH_GAP
    whenRow.labelRoom = K.CONTROL_X - K.CONTROL_GAP - whenRow.labelX
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
    -- A design's rules for a part are one list that replaces World's: the title carries the mark
    -- (its reset after the "?") and a line says so.
    local replaced = Mark(section, Area.Part("rules"), { after = help })
    K.Add(section, K.Help(section, L["These rules replace World's for this part."]), function() return replaced.changed end)
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
    -- Presets with a hint (the threat colours, which a setting does without rules) sit under Advanced,
    -- the hint its tooltip.
    local function RulePresetEntries()
        local key, entries, advanced, hint = Options.selectedComponent, {}, {}, nil
        local room = RuleRoom(CurrentRules())
        for _, preset in ipairs(RULE_PRESETS) do
            if preset.kind ~= "colour" or Colourable(key) then
                local into = preset.hint and advanced or entries
                hint = hint or preset.hint
                into[#into + 1] = { text = preset.name, disabled = room < #preset.rules,
                    tooltip = preset.hint and { title = preset.name, text = preset.hint } or nil, func = function()
                    local rules = CurrentRules()
                    if RuleRoom(rules) < #preset.rules then return end
                    for _, rule in ipairs(preset.rules) do rules[#rules + 1] = PS.Table.DeepCopy(rule) end
                    WriteRules(rules)
                end }
            end
        end
        if #advanced > 0 then
            entries[#entries + 1] = { text = L["Advanced"], children = advanced,
                tooltip = { title = L["Advanced"], text = hint } }
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
    K.Add(page, section, PartSelected)
end

-- A custom group: its name, the offset that moves every member, its scale and arrangement, its
-- members, its place in the tree and Delete. The header's eye shows or hides it.
local function BuildGroupContext(page)
    CreateContext(page, "group", function(context)
        local function SelectedGroup()
            local key = Options.editorSelectedGroup
            return key, key and Options.editorLayout and Options.editorLayout[key]
        end
        local section = K.Section(context, L["GROUP"])
        K.Add(context, section)
        -- Its offset, scale and arrangement are its placement (one area); its name is its label.
        Mark(section, Area.Entry("placement"))
        local nameRow = K.Row(section, L["Name"])
        local groupName = ValueBox(nameRow, K.CONTROL_X, K.WIDE, function(edit)
            local key = SelectedGroup()
            if key then Options:RenameEditorGroup(key, edit:GetText()) end
        end, Schema.GROUP_NAME_LENGTH)
        Mark(nameRow, Area.Entry("label"))
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
            if key and PS.MoveComponentGroup(key, direction, Options:EditorTarget(), Options:CurrentEditorVariant()) then
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
    end)
end

-- Plate settings' Target highlight: how the selected target is lit (Nameplates/TargetGlow.lua), for the open
-- plate type and design: its own values (profile options, Schema's HIGHLIGHT), or, where it has none, the
-- general settings every design shares (what every plate drew before they were per design). While Plate
-- settings is selected the preview shows the look whatever Test values' Targeted says (Preview's
-- RefreshTargetHighlightPreview). Highlight: Off, Gold edge (stored "border", or "halo" while it pulses) or
-- Soft glow behind. One Pulse slowly box serves both lit styles: Gold edge's switches border and halo, the
-- soft glow's is targetGlowPulse. Friendly plates' Dungeons & raids design is Blizzard's: no highlight there.
local highlightScratch = {}
local function EditorHighlight()
    return Schema.HIGHLIGHT.Resolve(PS.GetSettings(), Profile(), highlightScratch)
end
local function BlizzardDesign()
    return PS.Designs.IsBlizzard(Options.editorProfile, Options.editorDesign) and Options.editorProfile ~= "enemyPlayer"
end
local function Lit() return not BlizzardDesign() end
local function Glowing() return Lit() and EditorHighlight().targetHighlightStyle == "glow" end
-- The custom colour is also Threat's out of combat.
local function CustomGlow()
    local mode = Glowing() and EditorHighlight().targetGlowColourMode
    return mode == "custom" or mode == "threat"
end
local function TargetLit() return Lit() and EditorHighlight().targetHighlightStyle ~= "off" end
-- Its rows in order (Settings search lists them before they are built): id is the option.
local TARGET_ROWS = {
    { id = "targetHighlightStyle", label = L["Highlight"], shown = Lit, help = L["Gold edge lights the selected plate's "
        .. "text and bar edges, steady or pulsing; Soft glow behind is a soft light behind the whole plate. Either appears "
        .. "only on PlateSmith's own artwork, not on the 3D character model or Blizzard-owned plates."] },
    { id = "targetGlowColourMode", label = L["Glow colour"], shown = Glowing,
        help = L["The glow's colour: one you pick, the target's class (players), its reaction, or your threat on it. "
            .. "Threat: your threat colour on this target while you're in combat with it; your custom colour otherwise."] },
    { id = "targetGlowColour", label = L["Custom glow colour"], shown = CustomGlow },
    { id = "targetGlowSpread", label = L["Glow size"], shown = Glowing, step = 1, help = L["Wraps the health bar and the "
        .. "name, power bar and cast bar next to it (a names-only plate's name alone). Glow size is how far it reaches "
        .. "past them, in pixels."] },
    { id = "targetGlowOpacity", label = L["Glow opacity"], shown = Glowing, step = 0.05, format = PercentText },
    { id = "targetGlowOffsetX", label = L["Glow offset X"], shown = Glowing, step = 1 },
    { id = "targetGlowOffsetY", label = L["Glow offset Y"], shown = Glowing, step = 1,
        help = L["Moves the whole glow right (X) or up (Y) from the parts it wraps, in pixels."] },
    { id = "targetGlowPulse", label = L["Pulse slowly"], shown = TargetLit,
        help = L["The gold edge or the soft glow slowly fades in and out."] },
}

-- The section's rows for Settings search: { id, label, help, shown, frame (once built), section }.
function Options:EditorTargetHighlightRows()
    local rows, built = {}, self.editorTargetHighlightRowFrames or {}
    for index, spec in ipairs(TARGET_ROWS) do
        rows[index] = { id = spec.id, label = spec.label, help = spec.help, shown = spec.shown, frame = built[spec.id],
            section = self.editorTargetHighlightSection }
    end
    return rows
end

-- Whom the section edits: "For Enemies", "For Enemies › Dungeons & raids", "For Enemy players".
function Options:EditorTargetHighlightScope()
    local plate = self:EditorPlateLabel(self.editorProfile)
    local design = self.editorDesign
    if not design or design == "world" or self.editorProfile == "enemyPlayer" then return string.format(L["For %s"], plate) end
    return string.format(L["For %s › %s"], plate, self:EditorDesignLabel(self.editorProfile, design))
end

local function BuildTargetHighlightSection(context)
    local controls, frames = {}, {}
    Options.editorTargetHighlightControls, Options.editorTargetHighlightRowFrames = controls, frames
    local function ShownStyle()
        local style = EditorHighlight().targetHighlightStyle
        return style == "halo" and "border" or style
    end
    local section = K.Section(context, L["TARGET HIGHLIGHT"], { summary = function()
        if BlizzardDesign() then return L["Off"] end
        local highlight = EditorHighlight()
        local label = ""
        for _, choice in ipairs(model.targetHighlightChoices) do
            if choice.value == ShownStyle() then label = choice.label end
        end
        local pulsing = highlight.targetHighlightStyle == "halo"
            or (highlight.targetHighlightStyle == "glow" and highlight.targetGlowPulse == true)
        return pulsing and string.format(L["%s, pulsing"], label) or label
    end })
    K.Add(context, section)
    Options.editorTargetHighlightSection = section
    -- Whom it edits, kept in step with the open tab and design.
    local scope = K.Help(section, "")
    K.Add(section, scope)
    Options.editorTargetHighlightScope = scope
    Register({ Refresh = function() scope.text:SetText(Options:EditorTargetHighlightScope()) end })
    local blizzard = K.Help(section, L["Blizzard draws these plates in dungeons & raids, so they show no target highlight."])
    K.Add(section, blizzard, BlizzardDesign)
    -- A design's own option (PS.SetPlateProfileOption on the open design). A glow option restyles only the glow
    -- (Settings' glowSettings): while a slider is dragged or a colour picked, only the swatch and the
    -- preview's glow follow, not all of Studio.
    local function GlowPreview() Options:RefreshTargetHighlightPreview(PS.GetSettings()) end
    local function Write(key, value) return PS.SetPlateProfileOption(Options:EditorTarget(), key, value) end
    local function Bind(key)
        return function() return EditorHighlight()[key] end,
            function(value)
                local ok = Write(key, value)
                Options:Refresh(true)
                return ok
            end,
            function(value)
                local ok = Write(key, value)
                GlowPreview()
                return ok
            end
    end
    local _, setStyle = Bind("targetHighlightStyle")
    local _, setGlowPulse = Bind("targetGlowPulse")
    local build = {
        targetHighlightStyle = function(spec)
            return K.DropdownRow(section, spec.label, { choices = model.targetHighlightChoices, get = ShownStyle,
                set = function(value)
                    -- Gold edge keeps a pulsing edge pulsing.
                    if value == "border" and EditorHighlight().targetHighlightStyle == "halo" then value = "halo" end
                    return setStyle(value)
                end,
                name = WidgetName("editor_targetHighlightStyle", "Dropdown") })
        end,
        targetGlowColourMode = function(spec)
            local get, set = Bind(spec.id)
            return K.DropdownRow(section, spec.label, { choices = model.targetGlowColourChoices, get = get, set = set,
                name = WidgetName("editor_targetGlowColourMode", "Dropdown") })
        end,
        targetGlowColour = function(spec)
            local row, colour
            row, colour = K.SwatchRow(section, spec.label, {
                name = WidgetName("editor_targetGlowColour", "Colour"),
                get = function() return EditorHighlight().targetGlowColour end,
                set = function(r, g, b)
                    Write("targetGlowColour", { r = r, g = g, b = b })
                    colour:Refresh()
                    GlowPreview()
                end,
            })
            return row, colour
        end,
        targetGlowPulse = function(spec)
            return K.CheckRow(section, nil, { text = spec.label, name = WidgetName("editor_targetGlowPulse", "Checkbox"),
                get = function()
                    local highlight = EditorHighlight()
                    if highlight.targetHighlightStyle == "glow" then return highlight.targetGlowPulse == true end
                    return highlight.targetHighlightStyle == "halo"
                end,
                set = function(on)
                    if EditorHighlight().targetHighlightStyle == "glow" then return setGlowPulse(on == true) end
                    return setStyle(on and "halo" or "border")
                end })
        end,
    }
    local function Slider(spec)
        local key, range = spec.id, Schema.settingRanges[spec.id]
        local get, set, drag = Bind(key)
        return K.SliderRow(section, spec.label, { min = range[1], max = range[2], step = spec.step, format = spec.format,
            name = WidgetName("editor_" .. key, "Slider"), get = get, set = set, drag = drag })
    end
    for _, spec in ipairs(TARGET_ROWS) do
        local row, control = (build[spec.id] or Slider)(spec)
        K.Add(section, row, spec.shown)
        if spec.help and not K.AttachHelp(row, spec.help) then K.Add(section, K.Help(section, spec.help), spec.shown) end
        -- Changed here: a design other than World with its own value (Studio/Marks.lua). Gold edge's pulse is
        -- its style ("halo").
        Mark(row, Area.Option(spec.id == "targetGlowPulse" and { "targetGlowPulse", "targetHighlightStyle" } or spec.id))
        controls[spec.id], frames[spec.id] = Register(control), row
    end
    -- Every plate type's World design takes this look (their other designs keep their own).
    local copyRow, copy = K.ButtonRow(section, L["Copy to all plate types"], 170)
    copy:SetScript("OnClick", function()
        Options:ConfirmStudioAction(L["Give every plate type's World design this target highlight?"], L["Copy"], function()
            PS.CopyTargetHighlight(Options:EditorTarget())
            Options:Refresh(true)
        end)
    end)
    K.Add(section, copyRow, Lit)
    Options.editorTargetHighlightCopy = copy
end

-- The plate's own scale, per plate type: Studio's Plate settings row (the tree's top). Sizes belong to
-- their parts (the health bar's width and height, each text's size), so they are set there, once.
-- Under it, the selected target's highlight for this plate type and design.
local function BuildPlateContext(page)
    CreateContext(page, "plate", function(context)
        local section = K.Section(context, L["SCALE"])
        K.Add(context, section)
        local range = profileRanges.scale
        local row, slider = K.SliderRow(section, L["Scale"], {
            min = range[1], max = range[2], step = 0.05, format = PercentText,
            name = WidgetName("editor_profile_scale", "Slider"),
            get = ProfileValue("scale"),
            drag = function(value)
                local ok = PS.SetPlateProfileOption(Options:EditorTarget(), "scale", value)
                Options:QueueRefresh()
                return ok
            end,
            set = function(value)
                local ok = PS.SetPlateProfileOption(Options:EditorTarget(), "scale", value)
                Options:Refresh(true)
                return ok
            end,
        })
        Register(slider)
        Mark(row, Area.Option("scale"))
        K.Add(section, row)
        K.Add(section, K.Help(section, L["Scales the whole plate. Bar sizes are set on each bar, text sizes on each text."]))
        BuildTargetHighlightSection(context)
    end)
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
local BLIZZARD_NAME_CHOICES = {
    scope = {
        { value = "instances", label = L["Dungeons & raids"],
            help = L["Only where Blizzard keeps friendly plates; outdoors its fonts are left as they were."] },
        { value = "everywhere", label = L["Everywhere"], help = L["The same size on every Blizzard plate, in the world too."] },
    },
    outline = {
        { value = "none", label = L["None"] }, { value = "outline", label = L["Outline"] },
        { value = "thick", label = L["Thick outline"] },
    },
}
-- Blizzard's own friendly plates in dungeons: what each of its choices there applies to. Class
-- colours are players' only; names only is players' only where the client has the players' CVar
-- (NamePolicy), else Blizzard's one CVar covers friendly NPCs too.
local BLIZZARD_NAME_ROW_SHOWN = {
    [L["Names only"]] = function(profile)
        return profile == "friendlyPlayer" or not (PS.NamePolicy and PS.NamePolicy.NamesOnlyIsPlayersOnly())
    end,
    [L["Blizzard class colours, when available"]] = function(profile) return profile == "friendlyPlayer" end,
}
local function BlizzardNameRowShown(label, profile)
    local shown = BLIZZARD_NAME_ROW_SHOWN[label]
    return not shown or shown(profile or Options.editorProfile) and true or false
end
Options.BlizzardNameRowShown = BlizzardNameRowShown

-- Players and Friendly NPCs › Dungeons & raids (Options:IsEditorBlizzardNames): Blizzard's own name.
-- Its Display holds every choice Blizzard allows on those plates: names only, class colours and
-- the opt-in size for its shared nameplate fonts (Nameplates/NativeFonts.lua).
local function BuildBlizzardNameContext(page)
    CreateContext(page, "blizzardName", function(context)
        local section = K.Section(context, L["DISPLAY"])
        K.Add(context, section)
        local rows, controls = {}, {}
        Options.editorBlizzardNameControls = controls
        local function Add(label, row, control, help)
            Register(control)
            K.Add(section, row, function() return BlizzardNameRowShown(label) end)
            if help then K.AttachHelp(row, help) end
            rows[#rows + 1] = { label = label, frame = row, section = section }
        end
        -- A check's text sits beside its box here, so its help is the box's tooltip.
        local function Check(key, label, id, help)
            local get, set = Options.BindSetting(key)
            local row, box = K.CheckRow(section, nil, { text = label, name = WidgetName("selected_" .. key, "Checkbox"),
                get = get, set = set, tooltip = { title = label, lines = { help } } })
            Add(label, row, box)
            controls[id] = box
        end
        local function Choice(key, label, choices, id, help)
            local get, set = Options.BindSetting(key)
            local row, dropdown = K.DropdownRow(section, label, { choices = choices,
                name = WidgetName("selected_" .. key, "Dropdown"), get = get, set = set })
            Add(label, row, dropdown, help)
            controls[id] = dropdown
        end
        Check("blizzardNameFont", L["Change Blizzard's names"], "on", L["Off by default. Sets one font for the names "
            .. "Blizzard draws on its own plates. It changes Blizzard's shared nameplate fonts, so any other addon or "
            .. "Blizzard window that uses them changes too. Turning it off puts them back as they were."])
        Choice("blizzardNameFontScope", L["Where"], BLIZZARD_NAME_CHOICES.scope, "scope")
        Check("restrictedFriendlyNamesOnly", L["Names only"], "namesOnly", L["Blizzard shows only the name on these "
            .. "plates, without their health bars."])
        Check("restrictedFriendlyClassColour", L["Blizzard class colours, when available"], "classColour",
            L["Blizzard colours friendly players' names by class, where the game allows it."])
        Choice("blizzardNameFontFace", L["Font"], PS.Media.FontChoices, "face",
            L["Blizzard nameplate font keeps each font's own face."])
        local range = Schema.settingRanges.blizzardNameFontSize
        local getSize, setSize, dragSize = Options.BindSetting("blizzardNameFontSize")
        local sizeRow, size = K.SliderRow(section, L["Font size"], {
            min = range[1], max = range[2], step = 1, format = PointText,
            name = WidgetName("selected_blizzardNameFontSize", "Slider"), get = getSize, set = setSize, drag = dragSize,
        })
        Add(L["Font size"], sizeRow, size)
        controls.size = size
        Choice("blizzardNameFontOutline", L["Font style"], BLIZZARD_NAME_CHOICES.outline, "outline")
        displayRows.blizzardName = rows
    end)
end
DISPLAY_ROW_LABELS.blizzardName = { L["Change Blizzard's names"], L["Where"], L["Names only"],
    L["Blizzard class colours, when available"], L["Font"], L["Font size"], L["Font style"] }

-- Players › Dungeons & raids' Blizzard name rows (labels; frames once built), for Settings search
-- while another plate type or layout is open: picking one opens that tab.
function Options:EditorDungeonNameRows()
    local rows = {}
    for _, row in ipairs(displayRows.blizzardName or {}) do
        if BlizzardNameRowShown(row.label, "friendlyPlayer") then rows[#rows + 1] = row end
    end
    if displayRows.blizzardName then return rows end
    for _, label in ipairs(DISPLAY_ROW_LABELS.blizzardName) do
        if BlizzardNameRowShown(label, "friendlyPlayer") then rows[#rows + 1] = { label = label } end
    end
    return rows
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

-- Settings' pages (plate, stacking, auras, relations, experimental, Studio, help): one shown at a time.
-- Each is the shared panel kit in Studio's dark palette: foldable sections (folds kept in the
-- player's state as "studio.settings.<section>") dealt into two columns when the page is wide
-- enough and one otherwise, laid out again at the page's width whenever it changes (Chrome's
-- LayoutEditorSettingsPanels). A row is label | control; its help is a tooltip on the label and a "?" after it,
-- and only its state (SK.Note) shows under the control.
local settingsPageBuilders = {}
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
        -- Chrome's LayoutEditorSettingsPanels shows the current page (a page built for Settings
        -- search stays hidden).
        panel:Hide()
        return panel
    end
    -- Each page is built the first time it is wanted (Options:EditorSettingsPage), in this order.
    local order = {}
    local function Define(key, build)
        settingsPageBuilders[key] = build
        order[#order + 1] = key
    end
    Options.editorSettingsPageOrder = order
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
    Define("plate", function()
        local plate = Page("plate")
        local plates = Section(plate, "plates", L["Plates"])
        Choice(plates, "plate.mode", "mode", L["Who draws the plates"], model.modeChoices)
        Choice(plates, "plate.friendly", "friendly", L["Friendly units"], model.friendlyChoices)
        -- Blizzard's names in dungeons & raids are set in Studio's Players › Dungeons & raids design.
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
        Options.BuildPlateVisibilitySettings(SK, Section(plate, "visibility", L["Where plates show"],
            Options.PlateVisibilitySummary), Bind)
        local names = Section(plate, "names", L["Names"])
        Check(names, "plate.showPlayerSurnames", "showPlayerSurnames", L["Show player surnames"])
        Check(names, "plate.hideUnstyledFriendlyNames", "hideUnstyledFriendlyNames", L["Hide unstyled names outdoors"])
        Check(names, "plate.friendlyRelationshipColours", "friendlyRelationshipColours", L["Colour social relationships"])
        Check(names, "plate.nativeNameFont", "nativeNameFont", L["Readable Blizzard names outdoors"])
        SK.Add(names, SK.ControlHelp(names, L["Outside dungeons and raids, Blizzard's names are drawn at least 13 pt with "
            .. "an outline. Where Blizzard name size applies, it is used instead."]))
        -- Blizzard's names in dungeons & raids: their own rows on Players › Dungeons & raids › Name.
        local blizzardNamesRow, blizzardNames = SK.ButtonRow(names, L["Blizzard's names in dungeons & raids..."], 300)
        SK.Add(names, blizzardNamesRow)
        blizzardNames:SetScript("OnClick", function()
            Options:SetEditorInspectorPage("components")
            Options:OpenEditorDesign("friendlyPlayer", "dungeon", "name")
        end)
        Controls.AttachTooltip(blizzardNames, L["Blizzard's names in dungeons & raids..."], { L["Opens Players › Dungeons "
            .. "& raids › Name, where Blizzard name size, font and class colours are set."] })
        Options.editorBlizzardNamesLink = blizzardNames
        -- Casts on names-only plates: a small bar under the name (Nameplates/Placement.lua's NameCast).
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
        Choice(names, "plate.namesOnlyCastText", "namesOnlyCastText", L["Name cast text"], model.namesOnlyCastTextChoices,
            L["Where the spell's name and time go on the cast bar of a name: small under a slim bar, or inside a "
            .. "small bar like the full plate's. Time left follows the cast bar's own Time left choice."])
        -- The selected target's highlight is edited in Studio's Plate settings, per plate type, where the preview
        -- shows it; the summary is the open plate type's.
        local target = Section(plate, "target", L["Target"], function()
            local settings = EditorHighlight()
            local style = settings.targetHighlightStyle
            local label = LabelOf(model.targetHighlightChoices, style == "halo" and "border" or style)
            local pulsing = style == "halo" or (style == "glow" and settings.targetGlowPulse == true)
            return pulsing and string.format(L["%s, pulsing"], label) or label
        end)
        local targetRow, targetLink = SK.ButtonRow(target, L["Edit the target highlight in Studio › Plate settings"], 340)
        SK.Add(target, targetRow)
        targetLink:SetScript("OnClick", function() Options.settingsSearch.RevealTargetHighlight() end)
        SK.Add(target, SK.ControlHelp(target, L["Opens Studio with Plate settings selected, at Target highlight: Off, "
            .. "Gold edge or Soft glow behind, the glow's colour, size and offset, and Pulse slowly, for each plate type. "
            .. "The preview shows the look as you change it."]))
        Options.editorTargetHighlightLink = targetLink
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
        Options.BuildThreatColourSettings(SK, Section(plate, "threatColours", L["Threat colours"], Options.ThreatColourSummary),
            Bind)
    end)

    Define("stacking", function()
        BuildStackingPage(SK, Page, Bind)
    end)

    -- Aura defaults.
    Define("auras", function()
        local auras = Page("auras",
            L["Select Buffs or Debuffs in the Studio tree to set how many icons show, their size and which way they grow."])
        local buffs = Section(auras, "buffs", L["Buffs"])
        PartCheck(buffs, "auras.showBuffs", "showBuffs", L["Show buffs"])
        Choice(buffs, "auras.buffSource", "buffSource", L["Buff source"], model.auraSourceChoices)
        local debuffs = Section(auras, "debuffs", L["Debuffs"])
        PartCheck(debuffs, "auras.showDebuffs", "showDebuffs", L["Show debuffs"])
        Choice(debuffs, "auras.debuffSource", "debuffSource", L["Debuff source"], model.auraSourceChoices)
    end)

    -- Relationships.
    Define("relations", function()
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
    end)

    -- Experimental: tests of what the game allows, each off by default (the page header's "?" says so,
    -- and /ps diagnose's experimental section reports what each saw).
    Define("experimental", function()
        local experimental = Page("experimental")
        local tokens = Section(experimental, "experimentalTokens", L["More threat sources"])
        Check(tokens, "experimental.experimentalSoftTargetThreat", "experimentalSoftTargetThreat", L["Soft targets"])
        SK.Add(tokens, SK.ControlHelp(tokens, L["Also reads threat through your soft targets (softenemy, softinteract), "
            .. "after the mouseover, for the plate they name. This client may not have them; then nothing changes."]))
        Check(tokens, "experimental.experimentalTargetOfTargetThreat", "experimentalTargetOfTargetThreat",
            L["Target of target / focus target"])
        SK.Add(tokens, SK.ControlHelp(tokens, L["Also reads threat through your target's target and your focus's target, "
            .. "for the plate they name. A gap read this way is kept (~) like one read on hover."]))
        local shown = Section(experimental, "experimentalDisplay", L["More threat shown"])
        Check(shown, "experimental.experimentalSoloCurveGap", "experimentalSoloCurveGap", L["Solo gap while it targets you"])
        SK.Add(shown, SK.ControlHelp(shown, L["Solo, when the game keeps your raw threat private but says the enemy "
            .. "targets you, tries to show the gap through one of the game's curves without reading the number. "
            .. "If the game refuses, only the % shows, as now."]))
        Check(shown, "experimental.experimentalOutsideHolderRow", "experimentalOutsideHolderRow", L["Holder from outside your group"])
        SK.Add(shown, SK.ControlHelp(shown, L["In a Threat meter window, a row for whoever holds your target from outside "
            .. "your group, with its threat worked out from yours. Shown only when nobody in your group holds it."]))
        local dungeon = Section(experimental, "experimentalDungeon", L["Friendly plates in dungeons & raids"])
        Check(dungeon, "experimental.experimentalDungeonFriendlyText", "experimentalDungeonFriendlyText",
            L["Try drawing over Blizzard's dungeon names"])
        SK.Add(dungeon, SK.ControlHelp(dungeon, L["PlateSmith tries to draw its own plate over Blizzard's friendly plates "
            .. "in dungeons and raids. The game usually blocks it: in a dungeon, /ps diagnose (dungeonFriendlyOverlay) shows "
            .. "how many friendly plates it tracked and how many it showed on. While it is on, the Players and Friendly NPCs "
            .. "Dungeons & raids designs show the overlay's full parts instead of Blizzard's name; turn it off to set "
            .. "Blizzard's names there."]))
    end)


    -- Studio's own look and size: this player's preferences, applied at once, never saved in a profile.
    Define("studio", function()
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
        -- Colour-blind friendly: by default the plates' threat palette decides (Settings › Threat).
        local colourBlindRow, colourBlind = SK.DropdownRow(access, L["Colour-blind friendly"], {
            name = WidgetName("studio_colourBlind", "Dropdown"), choices = Options.StudioColourBlindChoices,
            get = function() return Options:StudioColourBlindChoice() end,
            set = function(value) Options:SetStudioAccess("colourBlind", value) end })
        SK.Add(access, colourBlindRow)
        SK.Add(access, SK.ControlHelp(access, L["Threat colours in the preview use blue and orange; Studio's lines are "
            .. "thicker. It follows the plates' threat palette unless you choose On or Off."]))
        Options.editorAccessColourBlind = Register(colourBlind)
        for _, spec in ipairs({
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
        Options:RefreshStudioScaleControls()
    end)

    -- Help: how Studio works, in short sections.
    Define("help", function()
        local help = Page("help")
        for _, entry in ipairs({
            { "helpColumns", L["The three columns"], L["The tree lists this plate type's parts and groups. The preview shows "
                .. "the plate; drag parts there. The inspector on the right edits what is selected: a part, a group or "
                .. "Plate settings (the plate's scale and the target highlight)."] },
            { "helpPlacement", L["Placement"], L["A part's parent in the tree is what it is anchored to: it moves with it and "
                .. "hides while it is hidden. In the inspector, Anchor to picks the parent and Stick to pins the part to one "
                .. "of its edges (Level is pinned left of the name, so it follows the name's width) or leaves it Free."] },
            { "helpQuickLayout", L["Quick layout"], L["Select the tree's Plate settings for Quick layout: pick a part for the top, "
                .. "bottom, left, right or centre of the health bar (the name on a names-only layout). Each pick is ordinary "
                .. "placement, so you can still drag or fine-tune the part; a part moved by hand shows as Custom."] },
            { "helpGroups", L["Groups"], L["Every plate starts with Text, Bars and Auras groups; change them freely. Drag a "
                .. "part onto a row to put it inside, or between rows to reorder. A group can stack its parts (Arrange): "
                .. "hidden parts take no space. Deleting a group leaves its parts where they are."] },
            { "helpParts", L["Parts"], L["Click a part to select it; its eye shows or hides it. Drag it in the preview "
                .. "(Shift: no snap), nudge it with the arrows (Shift for 10 px), or drag its handles to resize it. "
                .. "Right-click a row to rename, duplicate, layer, reset or delete it; + Add brings a deleted part back."] },
            { "helpPlateTypes", L["Plate types and designs"], L["Enemies, Players and Friendly NPCs each have their own "
                .. "design. The Design menu (under the tabs) picks World or a separate design for dungeons & raids, "
                .. "battlegrounds & arenas or cities & inns, which follows World except what you change in it; its chip "
                .. "says which. Players and Friendly NPCs have a Names only and a Full plate layout; the switch under the "
                .. "preview picks one. The Enemy players tab has no designs of its own: enemy players look like Enemies "
                .. "in every place, except what you change on that tab."] },
            { "helpSave", L["Save and Revert"], L["Changes show on your plates straight away. Save keeps them in the current "
                .. "profile; Revert goes back to the last save. Closing Studio with unsaved changes asks first. Profile (top "
                .. "right) switches, creates and renames profiles."] },
            { "helpCustom", L["Custom text, Style and Rules"], L["+ Add > Custom part > Custom text writes your own text, such as "
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
    end)

    -- A value change can change a folded section's summary.
    Register({ Refresh = function()
        if Options.editorSettingsWorkspace and Options.editorSettingsWorkspace:IsShown() then
            Options:LayoutEditorSettingsPanels()
        end
    end })
end

-- A Settings page by key, built the first time it is wanted (shown, or indexed by Settings
-- search); nil for a page this client has none of (Stacking without PS.Stacking).
function Options:EditorSettingsPage(key)
    local pages = self.editorInspectorPages
    if not pages or key == nil then return nil end
    local build = settingsPageBuilders[key]
    if build then
        settingsPageBuilders[key] = nil
        BuildLater("studio settings " .. key, build)
    end
    return pages[key]
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
    BuildBlizzardNameContext(page)
    BuildBarContexts(page)
    BuildValueContext(page)
    BuildAuraContexts(page)
    BuildGroupContext(page)
    BuildPlateContext(page)
    -- Quick layout shows with the Plate row (or nothing selected), so it is built with the plate's
    -- own rows, into its place in the column.
    if self.BuildQuickLayoutSection then
        local holder, buildPlate = K.Add(page, K.Group(page)), contextBuilders.plate
        contextBuilders.plate = function(context)
            buildPlate(context)
            self:BuildQuickLayoutSection(holder)
        end
    end
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
    if not page or self.editorPlayersGated then return end
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
