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

-- Copy to all plate types, for a look each design has its own that would otherwise be set tab by tab (Settings'
-- CopyDesignLook: what is "heals"): the open design's into the same design of the other plate types, asked
-- first (question names the design). Returns the row and its button.
local function CopyLookRow(section, what, question, help)
    local row, copy = K.ButtonRow(section, L["Copy to all plate types"], 170)
    copy:SetScript("OnClick", function()
        local design = Options:EditorDesignLabel(Options.editorProfile, Options.editorDesign or "world")
        Options:ConfirmStudioAction(string.format(question, design), L["Copy"], function()
            PS.CopyDesignLook(Options:EditorTarget(), what)
            Options:Refresh(true)
        end)
    end)
    K.Add(section, row)
    K.AttachHelp(row, help)
    return row, copy
end

-- Settings › Optional parts: shortcuts over the tree's eyes (Schema's partSwitches), each ticked while its part shows
-- on every plate type that has it, by the part's own name. part and plateType: where its Add goes (+ Add's route,
-- Options:AddEditorComponent) while it is off the plate everywhere (deleted, or Range and Behind you, which start so).
local SHOW_ON_PLATES = {
    { key = "quest", label = L["Quest marker"], part = "quest", plateType = "enemy" },
    { key = "showTagged", label = L["Tagged indicator"], part = "tagged", plateType = "enemy" },
    { key = "threat", label = L["Threat"], part = "threat", plateType = "enemy" },
    { key = "showClassification", label = L["Elite / rare mark"], part = "classification", plateType = "enemy" },
    { key = "title", label = L["Title"], part = "guild", plateType = "friendlyNPC", where = L["Friendly NPCs"] },
    { key = "range", label = L["Range"], part = "range", plateType = "enemy" },
    { key = "behindYou", label = L["Behind you"], part = "behindYou", plateType = "enemy" },
    { key = "targetedBy", label = L["Targeted by"], part = "targetedBy", plateType = "enemy", where = L["Enemies"] },
    { key = "looseMark", label = L["Loose mark"], part = "looseMark", plateType = "enemy", where = L["Enemies"] },
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
-- tag, when given: { field, value } set on each control it registered (studioPage, studioContext: see
-- Options:IsEditorControlAway).
local function BuildLater(what, build, tag, ...)
    local controls = Options.controls
    local first, marks = #controls + 1, Options.EditorThemeMarks and Options:EditorThemeMarks()
    local ok, failure = pcall(build, ...)
    if not ok then PS.Chat.ReportError(what, failure) end
    local settings = PS.GetSettings()
    local refreshing = Options.refreshing
    Options.refreshing = true
    for index = first, #controls do
        if tag then controls[index][tag[1]] = tag[2] end
        pcall(controls[index].Refresh, controls[index], settings)
    end
    Options.refreshing = refreshing
    if marks then Options:PaintEditorThemeSince(marks) end
    return ok
end
Options._BuildEditorLater = function(what, build, ...) return BuildLater(what, build, nil, ...) end

-- A Settings page's controls (studioPage) and a part context's own rows (studioContext) are refreshed while they
-- can be seen: Options:Refresh passes over them otherwise and marks them stale, and they are refreshed when
-- their page is laid out to show (Chrome's LayoutEditorSettingsPanels) or their context is selected
-- (RefreshEditorInspectorContext). Settings search lends any page's rows, so while it is busy every page counts as
-- seen. Most of a refresh's controls are on pages and contexts out of sight (live: the Stacking page's diagram
-- was drawn again on every value changed anywhere in Studio).
function Options:IsEditorControlAway(control)
    -- A page of Blizzard's Settings (Panel.lua's BuildPage) refreshes everything when it shows.
    local panel = control.settingsPage
    if panel then return not (panel.IsVisible and panel:IsVisible()) end
    local page, context, away = control.studioPage, control.studioContext, false
    if page then
        local search = self.settingsSearch
        if self.editorWorkspacePage ~= "settings" then
            away = true
        elseif not (search and search.IsBusy()) then
            away = page ~= (self.editorSettingsCategory or "plate")
        end
    elseif context then
        local selection = self.editorInspectorSelection
        away = not (selection and selection.context == context)
    end
    -- Never one that can be seen (a row shown somewhere else than its page or context).
    if away and control.IsVisible and control:IsVisible() then return false end
    return away
end

-- The stale controls that can now be seen, refreshed (cheap when there are none).
function Options:RefreshEditorStaleControls()
    if not self.editorStaleControls then return end
    local settings, refreshing, stale = PS.GetSettings(), self.refreshing, false
    if not settings then return end
    self.refreshing = true
    for _, control in ipairs(self.controls) do
        if control.studioStale then
            if self:IsEditorControlAway(control) then
                stale = true
            else
                control.studioStale = nil
                pcall(control.Refresh, control, settings)
            end
        end
    end
    self.refreshing = refreshing
    self.editorStaleControls = stale or nil
end

-- Fills a context's frame the first time it is wanted; true when it is built (or has nothing to build).
-- With nothing selected the inspector shows the Plate row's Quick layout, built with the plate's rows.
function Options:BuildEditorContext(key)
    key = key or "plate"
    local build = contextBuilders[key]
    if not build then return true end
    contextBuilders[key] = nil
    return BuildLater("studio inspector " .. key, build, { "studioContext", key }, self.editorContextFrames[key])
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

-- Controls that cannot apply (a Stacking setting the game ignores) are dimmed this much.
local DIMMED_ALPHA = 0.55

-- Placement: what the part is anchored to (its parent in the tree; dragging it there does the
-- same) and how. Free keeps an offset from the parent's centre; pinned to an edge, it follows the
-- parent's size. Either way it moves with the parent and hides with a hidden one.
-- Combo points that Style › Position puts on the health bar, and the parts the Elite / rare mark's style places:
-- Placement has no say (Editor's IsEditorPlacedByStyle), so Anchor to and Stick to are unavailable and say why
-- (EditorPlacedByStyleTip).
local function ByStyleTip() return Options:EditorPlacedByStyleTip(Options.selectedComponent) end
local function BuildPlacement(page)
    local section = K.Section(page, L["PLACEMENT"])
    Options.editorInspectorBasics = section
    -- Where it is, its anchor, pin and scale are one area, so the section carries the mark.
    Mark(section, Area.Entry("placement"))
    -- Whether other (its layout entry position) can be the selected part's anchor.
    local function Anchorable(other, position, key)
        return type(position) == "table" and other ~= key and not position.removed
            and not (key and Options:IsEditorUnder(other, key))
            and (other:match("^group%.%d+$") or Options:IsEditorComponentRelevant(other)) and true or false
    end
    local function AnchorChoices()
        local key, layout = Options.selectedComponent, Options.editorLayout or {}
        local choices = { { value = "", label = L["Plate"] } }
        local entries = {}
        for other, position in pairs(layout) do
            if Anchorable(other, position, key) then
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
        -- What AnchorChoices names the anchor (the plate, or an entry it lists), without listing them.
        labelFor = function(parentKey)
            if parentKey == "" then return L["Plate"] end
            local layout = Options.editorLayout or {}
            if Anchorable(parentKey, layout[parentKey], Options.selectedComponent) then
                return Options:EditorNodeLabel(parentKey)
            end
            return nil
        end,
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
            if Options:IsEditorPlacedByStyle(Options.selectedComponent) then return ByStyleTip() end
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
    -- A custom part pinned to a part's top, bottom or right edge may ride that part's fill when it is a bar (Schema's
    -- FILL): its top or bottom at the fill's moving end, or the end's middle; and say what it does while that bar is
    -- not shown (no power, no cast).
    local function FillPinned()
        local key, position = Options.selectedComponent, SelectedPosition()
        return key ~= nil and key:match("^value%d+$") ~= nil and position ~= nil and Schema.FILL.EDGES[position.attach] == true
            and Pinnable()
    end
    local fillRow, fill = K.CheckRow(section, L["Fill"], { text = L["Ride the bar's fill"],
        name = WidgetName("editor_fill", "Checkbox"),
        tooltip = { title = L["Ride the bar's fill"], lines = { L["On a bar, it sits at the end of the bar's fill instead "
            .. "of the bar's edge, and the game moves it as the value changes (Stick to Top: above the fill's end; "
            .. "Bottom: below it; Right: on it)."] } },
        get = function()
            local position = SelectedPosition()
            return position ~= nil and position.fill ~= nil
        end,
        set = function(on)
            local key = Options.selectedComponent
            if key then Options:SetEditorFill(key, on and "hide" or nil) end
        end,
    })
    K.Add(section, fillRow, FillPinned)
    local whenRow = K.Row(section, L["If not shown"])
    local when = K.Segmented(whenRow, {
        name = WidgetName("editor_fill_fallback", "Choice"),
        choices = {
            { value = "hide", label = L["Hide it"], tooltip = L["While its bar is not shown, it hides with it."] },
            { value = "next", label = L["Next bar"], tooltip = L["While its bar is not shown, it rides the next bar's fill "
                .. "(the power bar's goes to the health bar; the cast bar's to the power bar, else the health bar)."] },
        },
        get = function()
            local position = SelectedPosition()
            return position and position.fill or "hide"
        end,
        set = function(mode)
            local key = Options.selectedComponent
            if key then Options:SetEditorFill(key, mode) end
        end,
    })
    K.Add(section, whenRow, function()
        local position = SelectedPosition()
        return FillPinned() and position.fill ~= nil
    end)
    local byStyleNote = K.Note(section, ByStyleTip())
    K.Add(section, byStyleNote, function()
        local placed = Options:IsEditorPlacedByStyle(Options.selectedComponent)
        if placed and byStyleNote.text then byStyleNote.text:SetText(ByStyleTip()) end
        return placed
    end)
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
        GameTooltip:AddLine(ByStyleTip(), 1, 0.82, 0.45, true)
        GameTooltip:Show()
    end)
    anchor:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Options.editorFillCheck, Options.editorFillFallback = fill, when
    Options.editorPlacementRefresh = function()
        anchor:Refresh()
        SetAvailable(anchor, not Options:IsEditorPlacedByStyle(Options.selectedComponent))
        behaviour:Refresh()
        fill:Refresh()
        when:Refresh()
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
-- Read only (a part without a style shares one empty table: every style row asks on each refresh).
local SelectedStyle
do
    local NONE = {}
    SelectedStyle = function()
        local key = Options.selectedComponent
        local profile = Profile()
        return key and profile and profile.styles and profile.styles[key] or NONE
    end
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
-- text's). spec.context: whose rows they are, which Settings search finds (EditorDisplayRows); spec.widgets, a
-- second set of them on the same part (Objects' Range), names its widgets apart.
local FONT_STYLE_CHOICES = { { value = "", label = L["Plate outline"] }, { value = "none", label = L["None"] },
    { value = "outline", label = L["Outline"] }, { value = "thick", label = L["Thick outline"] } }
-- Kept while Media's list is the same (it is kept too): each refresh of a Font row asks. Read only.
local fontChoices, fontChoicesFrom
local function FontChoices()
    local media = PS.Media.FontChoices()
    if fontChoices and fontChoicesFrom == media then return fontChoices end
    local choices = { { value = "", label = L["Plate font"] } }
    for _, choice in ipairs(media) do
        if choice.value ~= "default" then choices[#choices + 1] = choice end
    end
    fontChoices, fontChoicesFrom = choices, media
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
    local widgets = spec.widgets or context
    -- Each row's mark: spec.area(field) when it binds elsewhere, else the part's style field.
    local function Add(label, row, field)
        K.Add(section, row)
        rows[#rows + 1] = { label = label, frame = row, section = section }
        if field then Mark(row, spec.area and spec.area(field) or Area.Style(field)) end
    end
    local getFont, setFont = bind("font")
    local fontRow, font = K.DropdownRow(section, L["Font"], { choices = FontChoices,
        name = WidgetName("selected_" .. widgets .. "_font", "Dropdown"),
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
            name = WidgetName("selected_" .. widgets .. "_fontSize", "Slider"),
            get = function() return getSize() or Auto() end,
            drag = function(value) return setSize(value, true) end,
            set = function(value) return setSize(value) end,
        })
        KeepStyleControl(slider)
        local auto
        autoRow, auto = K.CheckRow(section, nil, { text = spec.autoText or L["Auto: follows the name size"],
            name = WidgetName("selected_" .. widgets .. "_fontSizeAuto", "Checkbox"),
            get = function() return getSize() == nil end,
            set = function(on) setSize(not on and (getSize() or Auto()) or nil) end })
        KeepStyleControl(auto)
        autoRow.control = auto
    end
    Add(L["Font size"], sizeRow, not spec.size and "fontSize" or nil)
    if autoRow then K.Add(section, autoRow) end
    local getOutline, setOutline = bind("outline")
    local outlineRow, outline = K.DropdownRow(section, L["Font style"], { choices = FONT_STYLE_CHOICES,
        name = WidgetName("selected_" .. widgets .. "_outline", "Dropdown"),
        get = function() return getOutline() or "" end,
        set = function(value) setOutline(value ~= "" and value or nil) end })
    KeepStyleControl(outline)
    Add(L["Font style"], outlineRow, "outline")
    local getShadow, setShadow = bind("shadow")
    local shadowRow, shadow = K.CheckRow(section, L["Shadow"], { text = L["Drop shadow"],
        name = WidgetName("selected_" .. widgets .. "_shadow", "Checkbox"),
        get = function() return getShadow() == true end,
        set = function(on) setShadow(on) end })
    KeepStyleControl(shadow)
    Add(L["Shadow"], shadowRow, "shadow")
    -- (A second set of the same part, spec.widgets: its widgets named apart; search lists the first.)
    if not spec.widgets then displayRows[context] = rows end
end

-- The contexts whose Display has the text rows, and those rows' labels (an aura row adds its
-- Timed only before them and its countdown's position after), so Settings search lists them before
-- the part's rows are built.
local TEXT_ROW_LABELS = { L["Font"], L["Font size"], L["Font style"], L["Shadow"] }
local DISPLAY_ROW_LABELS = { buffs = { L["Permanent"], L["Font"], L["Font size"], L["Font style"], L["Shadow"],
    L["Text position"] } }
DISPLAY_ROW_LABELS.debuffs = DISPLAY_ROW_LABELS.buffs
for _, context in ipairs({ "name", "level", "guild", "tagged", "targetName", "quest", "classification", "threat",
    "combo", "targetedBy", "cast", "value", "statusText", "range", "behindYou" }) do
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
    return { { label = L["Show row"], help = Options.COMBO_SHOW_ROW_HELP, keywords = L["combo points empty"] } }
end

-- Every built context's Display text rows, by context (tests check them against the labels above).
function Options:EditorBuiltDisplayRows() return displayRows end

-- Class colour on the Health bar and the Name (Schema's CLASS_COLOUR, a design's own option): on Players and Enemy
-- players only (NPCs have no class), not on Blizzard's dungeon names. Unset, it shows the plate type's default.
-- Each part's help: one short line, then the detail.
local CLASS_COLOUR_HELP = {
    health = { L["The bar takes the player's class colour (set in Studio › Settings › Player colours)."],
        L["These still win: on Players, group, guild and friends colours (while Player colours' Group, guild & "
            .. "friends come before class colours is on); a PvP-flagged ally's PvP colour, Custom colour, threat colours "
            .. "and colour rules. Unticked: Players take their group, guild or friend colour, else blue; enemy players red "
            .. "or yellow. Where the game keeps the class private, the game's own class colour shows."] },
    name = { L["The name takes the player's class colour (set in Studio › Settings › Player colours)."],
        L["These still win: on Players, group, guild and friends colours (while Player colours' Group, guild & "
            .. "friends come before class colours is on); a PvP-flagged ally's PvP colour, threat colours and colour "
            .. "rules. Unticked: Players take their group, guild or friend colour, else blue; enemy players red or "
            .. "yellow. Where the game keeps the class private, the game's own class colour shows."] },
}
-- Settings › Player colours › Class colours: a colour row per class this client has (PlateColours.Classes), each
-- Blizzard's until changed (PS.SetClassColour keeps only changed ones), and Reset to Blizzard's.
function Options.BuildClassColourSettings(SK, section, Bind)
    local classes = PS.PlateColours.Classes()
    for _, class in ipairs(classes) do
        local file = class.file
        local row = SK.Row(section, class.name)
        local swatch = Controls.ColourSwatch(row, { size = SK.SWATCH, name = WidgetName("editor_class_" .. file, "Colour"),
            get = function()
                local own = PS.GetSettings().classColours
                if type(own) == "table" and own[file] then return own[file] end
                local r, g, b = PS.Secret.ClassColour(file)
                return { r = r or 1, g = g or 1, b = b or 1 }
            end,
            set = function(r, g, b)
                PS.SetClassColour(file, r, g, b)
                Options:Refresh()
            end,
        })
        swatch:ClearAllPoints()
        swatch:SetPoint("LEFT", row, "LEFT", SK.CONTROL_X, 0)
        SK.Add(section, row)
        Bind("relations.class." .. file, swatch)
    end
    if #classes == 0 then
        SK.Add(section, SK.Help(section, L["This game client gives no list of classes, so there is nothing to set here."]))
        return
    end
    local resetRow, reset = SK.ButtonRow(section, L["Reset to Blizzard's"], 200)
    reset:SetScript("OnClick", function()
        PS.ResetClassColours()
        Options:Refresh()
    end)
    Controls.AttachTooltip(reset, L["Reset to Blizzard's"], { L["Puts every class back to Blizzard's own colour."] })
    -- Unavailable while every class is Blizzard's.
    function reset:Refresh(settings)
        SetAvailable(self, type(settings.classColours) == "table" and next(settings.classColours) ~= nil)
    end
    Bind("relations.classColoursReset", reset)
    SK.Add(section, resetRow)
    SK.Add(section, SK.ControlHelp(section, L["Each class's colour wherever PlateSmith draws one: the Health bar and "
        .. "Name where Class colour is ticked, the soft target glow's Class, Targeted by badges, the target's name and "
        .. "combo points. Change any you find hard to tell apart (colour blindness, a dark texture); only those you "
        .. "change are kept, the rest stay Blizzard's. Where the game keeps a class private, the game's own colour shows."]))
end

-- Where a colour rule overrides a part's own colour, the row says so (STANDARDS 2a.2): the first enabled colour or blend
-- rule on part that always holds (the worst: the own colour never shows), else the first with a condition. Its index,
-- whether it always holds, and its condition; nil without one. Read from the stored rules when the inspector lays out.
function Options.EditorRuleCover(part)
    local profile = Profile()
    local list = profile and profile.rules and profile.rules[part]
    local first
    for index, rule in ipairs(type(list) == "table" and list or {}) do
        if rule.enabled ~= false and (rule.set == "colour" or rule.set == "blend") then
            local when = type(rule.when) == "string" and rule.when or ""
            if not when:find("%S") then return index, true, "" end
            first = first or index
        end
    end
    if first then return first, false, list[first].when end
    return nil
end
local COVER_PARTS = { name = L["Name"], health = L["Health bar"], level = L["Level"] }
local COVER_TEXT = {
    class = { always = L["A rule always sets this %s's colour, so its class colour never shows."],
        when = L["A rule sets this %s's colour (while %s), so its class colour shows only where that rule doesn't apply."] },
    custom = { always = L["A rule always sets this %s's colour, so its custom colour never shows."],
        when = L["A rule sets this %s's colour (while %s), so its custom colour shows only where that rule doesn't "
            .. "apply."] },
    difficulty = { always = L["A rule always sets this %s's colour, so its difficulty colour never shows."],
        when = L["A rule sets this %s's colour (while %s), so its difficulty colour shows only where that rule doesn't "
            .. "apply."] },
}
-- The line for a covered own colour (which: "class" or "custom") of part, or nil while no rule covers it.
function Options.EditorRuleCoverText(part, which)
    local index, always, when = Options.EditorRuleCover(part)
    if not index then return nil end
    local texts = COVER_TEXT[which]
    if always then return string.format(texts.always, COVER_PARTS[part]), index end
    return string.format(texts.when, COVER_PARTS[part], when), index
end
-- Under the row of part's own colour: the line while a rule covers it (inUse: whether that colour is the part's now),
-- and Show rule, which opens the part's Rules at that rule (Search.RevealPartRule).
local function RuleCoverNote(section, part, which, inUse)
    local note = K.Note(section, "")
    local function Shown()
        return Options.selectedComponent == part and inUse() and Options.EditorRuleCoverText(part, which) ~= nil
    end
    K.Add(section, note, function()
        if not Shown() then return false end
        note.text:SetText((Options.EditorRuleCoverText(part, which)))
        return true
    end)
    local linkRow, link = K.ButtonRow(section, L["Show rule"], 100, nil, K.CONTROL_X)
    link:SetScript("OnClick", function()
        local _, index = Options.EditorRuleCoverText(part, which)
        if index and Options.settingsSearch then Options.settingsSearch.RevealPartRule(index) end
    end)
    Controls.AttachTooltip(link, L["Show rule"], { L["Opens this part's Rules at the rule that sets its colour."] })
    K.Add(section, linkRow, Shown)
    Options.editorRuleCoverNotes = Options.editorRuleCoverNotes or {}
    Options.editorRuleCoverNotes[part .. "." .. which] = { note = note, link = link, row = linkRow }
end

local function ClassColourCheck(section, part)
    local CLASS = Schema.CLASS_COLOUR
    local key = CLASS.PARTS[part]
    local function Players()
        local plate = Options.editorProfile
        return (plate == "friendlyPlayer" or plate == "enemyPlayer") and not PS.Designs.IsBlizzard(plate, Options.editorDesign)
    end
    local row, checkbox = K.CheckRow(section, L["Class"], { text = L["Class colour"],
        name = WidgetName("selected_" .. key, "Checkbox"),
        get = function() return CLASS.On(Profile(), Options.editorProfile, part) == true end,
        set = SetProfileValue(key) })
    Register(checkbox)
    Mark(row, Area.Option(key))
    K.Add(section, row, Players)
    for _, line in ipairs(CLASS_COLOUR_HELP[part]) do
        if not K.AttachHelp(row, line) then K.Add(section, K.Help(section, line), Players) end
    end
    -- Where the social switch applies (friendly players), it comes first.
    K.Add(section, K.Note(section, L["Group, guild & friends first"]), function()
        return Players() and Options.editorProfile == "friendlyPlayer" and PS.GetSettings().friendlyRelationshipColours ~= false
    end)
    RuleCoverNote(section, part, "class", function() return Players() and CLASS.On(Profile(), Options.editorProfile, part) == true end)
    Options.editorClassColourChecks = Options.editorClassColourChecks or {}
    Options.editorClassColourChecks[part] = checkbox
    return checkbox
end

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
        -- The name's own colour (Schema's NAME_COLOUR): Custom, the colour picked; unticked, its automatic colour.
        -- Picking a colour or ticking Custom unticks Class colour (which wins while ticked); Cancel restores both.
        local namePicked
        local function NameClassOn()
            return Schema.CLASS_COLOUR.On(Profile(), Options.editorProfile, "name") == true
        end
        local function NameCustom() return ProfileValue("nameColour")() ~= nil and not NameClassOn() end
        local function SetNameColour(colour)
            if colour and Schema.CLASS_COLOUR.On(Profile(), Options.editorProfile, "name") ~= nil then
                PS.SetPlateProfileOption(Options:EditorTarget(), { nameColour = colour, nameClassColour = false })
            else
                PS.SetPlateProfileOption(Options:EditorTarget(), "nameColour", colour)
            end
            Options:Refresh(true)
        end
        local nameColourRow, nameSwatch = K.SwatchRow(nameSection, L["Colour"], {
            name = WidgetName("selected_nameColour", "Colour"),
            beforeOpen = function()
                namePicked = { colour = PS.Table.DeepCopy(ProfileValue("nameColour")()), class = Profile().nameClassColour }
            end,
            get = function() return ProfileValue("nameColour")() or { r = 1, g = 1, b = 1 } end,
            set = function(r, g, b) SetNameColour({ r = r, g = g, b = b }) end,
            cancel = function()
                local before = namePicked or {}
                PS.SetPlateProfileOption(Options:EditorTarget(), "nameColour", before.colour)
                if Schema.CLASS_COLOUR.On(Profile(), Options.editorProfile, "name") ~= nil then
                    PS.SetPlateProfileOption(Options:EditorTarget(), "nameClassColour", before.class)
                end
                Options:Refresh(true)
            end,
        })
        Register(nameSwatch)
        local nameCustom = Register(K.RowCheck(nameColourRow, {
            text = L["Custom"],
            get = NameCustom,
            set = function(custom)
                SetNameColour(custom and PS.Table.DeepCopy(ProfileValue("nameColour")() or { r = 1, g = 1, b = 1 }) or nil)
            end,
        }))
        Mark(nameColourRow, Area.Option({ "nameColour" }))
        K.Add(nameSection, nameColourRow)
        K.AttachHelp(nameColourRow, L["Custom: the name takes the colour picked here instead of its own (an object's "
            .. "gold, a group, guild, class or reaction colour). Picking a colour turns it on and Class colour off; Class "
            .. "colour, while ticked, wins over it. A PvP-flagged ally's PvP colour, threat colours and colour rules still "
            .. "win."])
        RuleCoverNote(nameSection, "name", "custom", NameCustom)
        Options.editorNameColour, Options.editorNameCustom = nameSwatch, nameCustom
        ClassColourCheck(nameSection, "name")
        Options.ThreatColourPartCheck(K, nameSection, "name")
        -- The name's Font size is this plate type's name size in points, which the other texts follow.
        TextRows(nameSection, { context = "name", size = function(section)
            return ProfileSliderRow(section, L["Font size"], "nameFontSize", profileRanges.nameFontSize, 1, PointText):GetParent()
        end })
    end)

    -- Level, guild and the tagged mark draw only text: Display holds the text rows. The Level has its Colour first:
    -- its own (Normal) or the game's for its level against yours (style levelColour "difficulty"), under colour rules.
    for _, key in ipairs({ "level", "guild", "tagged" }) do
        CreateContext(page, key, function(context)
            local section = K.Section(context, L["DISPLAY"])
            K.Add(context, section)
            if key == "level" then
                local colourRow, colour = K.DropdownRow(section, L["Colour"], {
                    choices = { { value = "normal", label = L["Normal"] }, { value = "difficulty", label = L["Difficulty"],
                        help = L["The game's colour for the unit's level against yours: red, orange, yellow, green or "
                            .. "grey, and red for ??."] } },
                    name = WidgetName("selected_level_colour", "Dropdown"),
                    get = function() return SelectedStyle().levelColour or "normal" end,
                    set = function(value) WriteSelectedStyle("levelColour", value == "difficulty" and value or nil) end,
                })
                KeepStyleControl(colour)
                colourRow.kitSearchKeywords = L["con colour difficulty"]
                Mark(colourRow, Area.Style("levelColour"))
                K.AttachHelp(colourRow, L["Difficulty: the level in the game's colour for it against yours (red, orange, "
                    .. "yellow, green or grey; red for ??)."])
                K.AttachHelp(colourRow, L["Where the game hides the level, it keeps its normal colour. A colour rule on "
                    .. "the Level wins: the looks colour the level gold with one, so to see this set that rule's Then to "
                    .. "Set difficulty colour, or turn the rule off."])
                K.Add(section, colourRow)
                RuleCoverNote(section, "level", "difficulty", function() return SelectedStyle().levelColour == "difficulty" end)
            end
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
        -- The flagged ally's colour (relationshipColours.pvp), while Display colours it; where it goes is
        -- PvPMark.ColourOnBar's.
        local function NameColoured() return PS.PvPMark.Colours(PS.GetSettings()) end
        local function SetPvpColour(r, g, b)
            PS.SetRelationshipColour("pvp", r, g, b)
            Options:Refresh(true)
        end
        K.Add(pvpSection, K.Help(pvpSection, L["Goes on picks where the colour shows: the health bar, the name or both. "
            .. "Automatic: the health bar on a full plate, and the name on names-only plates or where the bar has a "
            .. "colour of its own (Custom colour, a colour rule that always applies, or its class colour)."]), NameColoured)
        local getPlace, setPlace = SettingControl("friendlyPvpColourOn")
        local placeRow, place = K.DropdownRow(pvpSection, L["Goes on"], { choices = model.friendlyPvpPlaceChoices,
            name = WidgetName("selected_friendlyPvpColourOn", "Dropdown"), get = getPlace, set = setPlace })
        Register(place)
        K.Add(pvpSection, placeRow, NameColoured)
        local colourRow, colour = K.SwatchRow(pvpSection, L["PvP colour"], {
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
        -- Icon size, for the styles that draw Blizzard's winged icon.
        local getSize, setSize = SettingControl("classificationIconSize")
        local sizeRow, size = K.DropdownRow(markSection, L["Icon size"], { choices = model.classificationIconSizeChoices,
            name = WidgetName("selected_classificationIconSize", "Dropdown"), get = getSize, set = setSize })
        Register(size)
        K.Add(markSection, sizeRow, function()
            local style = PS.GetSettings().classificationStyle
            return style == "icon" or style == "beforeName"
        end)
        Options.SharedSettingNote(K, markSection)
        K.Add(markSection, K.Help(markSection, L["Gold for elite, silver for rare, both for rare elite, a skull or red "
            .. "for a world boss. Classic dragon and Before the name place the mark and the level themselves; another "
            .. "style puts back your own placement. Where the game keeps the classification private, no mark shows."]))
        TextRows(markSection, { context = "classification" })
    end)

    -- The threat text's form, shared by every plate type (and the Tank window's threat column).
    CreateContext(page, "threat", function(context)
        local threatSection = K.Section(context, L["DISPLAY"])
        K.Add(context, threatSection)
        local getThreat, setThreat = SettingControl("threatTextFormat")
        local threatRow, threatFormat = K.DropdownRow(threatSection, L["Threat text"], {
            choices = { { value = "gap", label = L["% and gap"] }, { value = "gapOnly", label = L["Gap only"] },
                { value = "percent", label = L["% only"] }, { value = "detailed", label = L["Detailed (lead % and raw threat)"] } },
            name = WidgetName("selected_threatTextFormat", "Dropdown"), get = getThreat, set = setThreat })
        Options.editorThreatTextFormat = Register(threatFormat)
        K.Add(threatSection, threatRow)
        K.Add(threatSection, K.Help(threatSection, L["% and gap: your threat and the margin the threat windows show "
            .. "(+ your margin while you hold it, - how far you are from pulling it). Where the game keeps the "
            .. "numbers private, only the % shows. Gap only: just the margin (+1.2k, -300); where the game keeps it private, "
            .. "the % shows instead. Custom text can show more: {threat.percent} {threat.lead} "
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
        -- Display (style badgeShow): a badge per member (nil, the default) or Count only.
        local showRow, show = K.DropdownRow(targetedSection, L["Display"], {
            choices = { { value = "badges", label = L["Badges"] }, { value = "count", label = L["Count only"] } },
            name = WidgetName("selected_targetedBy_show", "Dropdown"),
            get = function() return SelectedStyle().badgeShow or "badges" end,
            set = function(value) WriteSelectedStyle("badgeShow", value == "count" and "count" or nil) end,
        })
        KeepStyleControl(show)
        Mark(showRow, Area.Style("badgeShow"))
        K.AttachHelp(showRow, L["Badges: one per party member, or a raid's tanks. Count only: one small number, how many "
            .. "of your whole group or raid (not you) target this enemy, counting only the answers the game gives; "
            .. "nothing shows while no one does. Style's Size sets the number's size. Rules and custom text can read it "
            .. "as targeted.count."])
        K.Add(targetedSection, showRow)
        local function BadgesShown() return SelectedStyle().badgeShow ~= "count" end
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
        K.Add(targetedSection, initialsRow, BadgesShown)
        TextRows(targetedSection, { context = "targetedBy", autoText = L["Auto: follows the badge size"], auto = function()
            local geometry = PS.TargetedBy
            return geometry and geometry.InitialFontSize(geometry.StyleOf(SelectedStyle())) or 8
        end })
    end)

    -- The Action icon (Nameplates/ActionIcon.lua): what it is, and how an icon saying you can't shows.
    CreateContext(page, "actionIcon", function(context)
        local actionSection = K.Section(context, L["DISPLAY"])
        K.Add(context, actionSection)
        K.Add(actionSection, K.Help(actionSection, L["The game's own cursor icon for this object or NPC: a herb, ore, a "
            .. "chest, a book, a quest, someone to talk to or a trainer. Where the game gives no icon, none shows. Rules "
            .. "and custom text can read what it says: object.kind, object.unable, and interact.inrange for reach."]))
        local unableRow, unable = K.DropdownRow(actionSection, L["Can't use"], {
            choices = { { value = "game", label = L["As the game shows it"] }, { value = "grey", label = L["Greyed"] },
                { value = "hide", label = L["Hidden"] } },
            name = WidgetName("selected_actionIcon_unable", "Dropdown"),
            get = function() return SelectedStyle().iconUnable or "game" end,
            set = function(value) WriteSelectedStyle("iconUnable", value ~= "game" and value or nil) end,
        })
        KeepStyleControl(unable)
        Mark(unableRow, Area.Style("iconUnable"))
        K.AttachHelp(unableRow, L["The game shows its own icon for something you cannot use yet, such as a herb your "
            .. "skill is too low for. Greyed dims it further; Hidden shows nothing."])
        K.Add(actionSection, unableRow)
    end)

    -- The Status text (Nameplates/ObjectStatus.lua): where it comes from, then the text rows.
    CreateContext(page, "statusText", function(context)
        local section = K.Section(context, L["DISPLAY"])
        K.Add(context, section)
        K.Add(section, K.Help(section, L["What the object needs, such as Mining 65, in the game's gathering colours for "
            .. "your skill: orange, yellow, green, grey, or red when you can't yet. It comes from the game's tooltip: "
            .. "hover one Tin Vein and every Tin Vein shows it from then on; herbs and ore veins show the original "
            .. "game's level without hovering. Until then, or for an object that needs no skill, nothing shows. With "
            .. "Cultivation (Tauren), herbs add Cultivate ready, Cultivate in 23m, Cultivated or the level it needs. "
            .. "Rules and custom text can read object.skill, object.cangather and object.cancultivate."]))
        TextRows(section, { context = "statusText" })
    end)

    -- The Backdrop (Nameplates/Backdrop.lua): what it is; its look and size are under Style.
    CreateContext(page, "backdrop", function(context)
        local section = K.Section(context, L["DISPLAY"])
        K.Add(context, section)
        K.Add(section, K.Help(section, L["A box behind other parts, like the game's tooltip. Style › Size: Fit to parts "
            .. "wraps the parts you tick (the name, the Status text, the Action icon, the quest marker) as they show and "
            .. "hide, so a herb's box grows to hold its Status text; Fixed size is a box of your own size to place "
            .. "anywhere. Rules can hide or fade it."]))
    end)

    -- The Loose mark (Nameplates/LooseMark.lua): when it shows, its icon and its pulse.
    CreateContext(page, "looseMark", function(context)
        local looseSection = K.Section(context, L["DISPLAY"])
        K.Add(context, looseSection)
        K.Add(looseSection, K.Help(looseSection, L["A small mark while the mob is loose: attacking someone who is not a "
            .. "tank, as the Tank window's LOOSE says. Where the game will not say who holds it, no mark shows. Rules "
            .. "and custom text can read the same as threat.loose. Test values: Loose and You tank."]))
        local forRow, forControl = K.DropdownRow(looseSection, L["For"], {
            choices = { { value = "tank", label = L["Tanks"] }, { value = "all", label = L["Everyone"] } },
            name = WidgetName("selected_looseMark_for", "Dropdown"),
            get = function() return SelectedStyle().looseFor or "tank" end,
            set = function(value) WriteSelectedStyle("looseFor", value == "all" and "all" or nil) end,
        })
        KeepStyleControl(forControl)
        Mark(forRow, Area.Style("looseFor"))
        K.AttachHelp(forRow, L["Tanks: only while you tank (your role, or Threat colours' Role). Everyone: whatever your "
            .. "role, so a healer sees which mobs got loose."])
        K.Add(looseSection, forRow)
        local iconRow, iconControl = K.DropdownRow(looseSection, L["Icon"], {
            choices = { { value = "alert", label = L["The game's alert"] }, { value = "window", label = L["Tank window's"] } },
            name = WidgetName("selected_looseMark_icon", "Dropdown"),
            get = function() return SelectedStyle().looseIcon or "alert" end,
            set = function(value) WriteSelectedStyle("looseIcon", value == "window" and "window" or nil) end,
        })
        KeepStyleControl(iconControl)
        Mark(iconRow, Area.Style("looseIcon"))
        K.Add(looseSection, iconRow)
        local pulseRow, pulse = K.CheckRow(looseSection, L["Pulse"], { text = L["Pulse as it gets loose"],
            name = WidgetName("selected_looseMark_pulse", "Checkbox"),
            get = function() return SelectedStyle().loosePulse ~= false end,
            -- On clears the field (nil: it pulses); off stores false.
            set = function(on)
                if on then return WriteSelectedStyle("loosePulse", nil) end
                return WriteSelectedStyle("loosePulse", false)
            end,
        })
        KeepStyleControl(pulse)
        Mark(pulseRow, Area.Style("loosePulse"))
        K.AttachHelp(pulseRow, L["Two quick blinks when the mob becomes loose; then it stays still."])
        K.Add(looseSection, pulseRow)
    end)

    -- A style colour row of the selected part (written whole, never changed in place) with its changed-here mark.
    local function ColourRow(section, label, field, fallback)
        local row, swatch = K.SwatchRow(section, label, {
            get = function() return SelectedStyle()[field] or fallback end,
            drag = function(r, g, b) return WriteSelectedStyle(field, { r = r, g = g, b = b, a = 1 }, true) end,
            set = function(r, g, b) return WriteSelectedStyle(field, { r = r, g = g, b = b, a = 1 }) end,
        })
        KeepStyleControl(swatch)
        Mark(row, Area.Style(field))
        K.Add(section, row)
        return row
    end
    -- A style choice of the selected part: the first choice is stored as nil.
    local function ChoiceRow(section, label, field, choices, name)
        local row, control = K.DropdownRow(section, label, {
            choices = choices, name = WidgetName(name, "Dropdown"),
            get = function() return SelectedStyle()[field] or choices[1].value end,
            set = function(value) WriteSelectedStyle(field, value ~= choices[1].value and value or nil) end,
        })
        KeepStyleControl(control)
        Mark(row, Area.Style(field))
        K.Add(section, row)
        return row
    end

    -- The Range part (Nameplates/Range.lua): what it draws, when, its two colours, then the text rows. On Objects, the
    -- game's in-reach answer: its own section, with the words it writes.
    CreateContext(page, "range", function(context)
        local Range = PS.Range
        local function Object() return Options:IsEditorObject() end
        local reach = K.Section(context, L["DISPLAY"])
        K.Add(context, reach, Object)
        K.Add(reach, K.Help(reach, L["Whether you can reach the object, corpse or NPC to use it, as the game says while "
            .. "it gives the plate an icon (interact.inrange). While the game doesn't say, nothing shows. Test values: "
            .. "Within reach."]))
        ChoiceRow(reach, L["Display"], "rangeDisplay", Range.PART.OBJECT_DISPLAY_CHOICES, "selected_range_objectDisplay")
        ChoiceRow(reach, L["Show"], "rangeShow", Range.PART.OBJECT_SHOW_CHOICES, "selected_range_objectShow")
        -- Its words, out of reach and in reach: blank is the default (Range.OBJECT_WORDS).
        for _, words in ipairs({ { "rangeOutText", L["Out of reach"], Range.OBJECT_WORDS.out },
            { "rangeInText", L["In reach"], Range.OBJECT_WORDS["in"] } }) do
            local field, label, default = words[1], words[2], words[3]
            local row = K.Row(reach, label)
            local edit = Controls.EditBox(row, { width = K.WIDTH - K.CONTROL_X, height = K.CONTROL_H,
                fontSize = K.FIELD_FONT, insets = { K.CARD_PAD, K.CARD_PAD }, maxLetters = Schema.VALUE_NAME_LENGTH,
                fill = { 0.06, 0.05, 0.04, 0.92 } })
            edit:SetPoint("LEFT", row, "LEFT", K.CONTROL_X, 0)
            local function Commit(box)
                local text = box:GetText()
                WriteSelectedStyle(field, (text ~= "" and text ~= default) and text or nil)
                box:ClearFocus()
            end
            edit:SetScript("OnEnterPressed", Commit)
            edit:SetScript("OnEditFocusLost", function(box) if box.studioEditing then Commit(box) end end)
            edit:SetScript("OnEditFocusGained", function(box) box.studioEditing = true end)
            edit:SetScript("OnEscapePressed", function(box)
                box.studioEditing = false
                box:ClearFocus()
                box:Refresh()
            end)
            function edit:Refresh()
                if self.HasFocus and self:HasFocus() then return end
                self.studioEditing = false
                self:SetText(SelectedStyle()[field] or default)
            end
            Controls.AttachTooltip(edit, label, { L["The words it shows. Leave it blank for the default."] })
            KeepStyleControl(edit)
            Mark(row, Area.Style(field))
            K.Add(reach, row)
        end
        ColourRow(reach, L["In reach"], "rangeInColour", Range.PART.IN)
        ColourRow(reach, L["Out of reach"], "rangeOutColour", Range.PART.OUT)
        TextRows(reach, { context = "range", widgets = "rangeReach" })
        local section = K.Section(context, L["DISPLAY"])
        K.Add(context, section, function() return not Object() end)
        K.Add(section, K.Help(section, L["Whether your spells reach the unit, from your spellbook: harmful spells on "
            .. "enemies, helpful ones (heals, buffs) on friends, and out of combat the game's follow distance. While "
            .. "PlateSmith has no answer (not checked yet, or the game keeps it in combat) nothing shows, so it never "
            .. "guesses. Rules and custom text can read unit.inrange, range.band and {range}. Test values: In range."]))
        local displayRow = ChoiceRow(section, L["Display"], "rangeDisplay", Range.PART.DISPLAY_CHOICES,
            "selected_range_display")
        K.AttachHelp(displayRow, L["Dot: a small dot. Distance: how far, from your spells' own ranges, such as <30 (within "
            .. "30 yards) or 30+ (past your longest); not exact yards. Dot and distance: both."])
        local showRow = ChoiceRow(section, L["Show"], "rangeShow", Range.PART.SHOW_CHOICES, "selected_range_show")
        K.AttachHelp(showRow, L["Out of range: only while your spells don't reach the unit. In range: only while they do. "
            .. "Always: either, in its colour."])
        ColourRow(section, L["In range"], "rangeInColour", Range.PART.IN)
        ColourRow(section, L["Out of range"], "rangeOutColour", Range.PART.OUT)
        TextRows(section, { context = "range" })
    end)

    -- The Behind you part (Nameplates/Behind.lua): an arrow or the words, for whom, its colour, then the text rows.
    CreateContext(page, "behindYou", function(context)
        local Behind = PS.Behind
        local section = K.Section(context, L["DISPLAY"])
        K.Add(context, section)
        K.Add(section, K.Help(section, L["Shows while the game says your target's plate is behind the camera (the game "
            .. "then keeps it at the screen's edge: Settings › Stacking & distance › Target behind you: range). Only the game's "
            .. "own yes shows it: never a guess. Rules and custom text can read unit.behind. Test values: Behind you and "
            .. "Your target."]))
        ChoiceRow(section, L["Display"], "behindDisplay", Behind.PART.DISPLAY_CHOICES, "selected_behindYou_display")
        local forRow = ChoiceRow(section, L["For"], "behindFor", Behind.PART.FOR_CHOICES, "selected_behindYou_for")
        K.AttachHelp(forRow, L["Target only: your target's plate. Target and focus: your focus's plate too."])
        ColourRow(section, L["Colour"], "behindColour", Behind.PART.COLOUR)
        TextRows(section, { context = "behindYou", autoText = L["Auto: follows the name size (the arrow too)"] })
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
        RuleCoverNote(health, "health", "custom", function() return ProfileValue("healthColourMode")() == "custom" end)
        ClassColourCheck(health, "health")
        Options.ThreatColourPartCheck(K, health, "health")
        Options.ThreatColourPartCheck(K, health, "border")
        -- Grey when tagged by others (the design's greyWhenTagged; ThreatColours.GreyWhenTagged): enemy plates only. A
        -- profile saved before 1.2.1 has it off and keeps its TAGGED word; a line offers the switch, which turns TAGGED
        -- off too (Settings › Show on plates' box, every design).
        local function EnemyPlate() return Options:IsEditorEnemy() end
        local greyRow, grey = K.CheckRow(health, L["Tagged"], { text = L["Grey when tagged by others"],
            get = function() return ProfileValue("greyWhenTagged")() == true end,
            set = function(on) SetProfileValue("greyWhenTagged")(on == true) end,
            name = WidgetName("selected_greyWhenTagged", "Checkbox") })
        Register(grey)
        Mark(greyRow, Area.Option("greyWhenTagged"))
        K.Add(health, greyRow, EnemyPlate)
        local greyHelp = L["While another player or group has tagged the mob (you get no credit for it), its health bar "
            .. "is grey, as Blizzard's plates draw it; with threat colours on the bar, it keeps its threat colour, "
            .. "darkened, so you still see who holds it. A colour rule on the health bar wins over it."]
        if not K.AttachHelp(greyRow, greyHelp) then K.Add(health, K.Help(health, greyHelp), EnemyPlate) end
        local function OfferGrey()
            return EnemyPlate() and ProfileValue("greyWhenTagged")() ~= true and PS.GetPartShownState("showTagged") ~= "none"
        end
        K.Add(health, K.Help(health, L["This profile shows the TAGGED word. Blizzard's plates grey the bar instead."]),
            OfferGrey)
        local insteadRow, instead = K.ButtonRow(health, L["Grey bar instead"], 150)
        instead:SetScript("OnClick", function()
            PS.SetPlateProfileOption(Options:EditorTarget(), "greyWhenTagged", true)
            PS.SetPartShownEverywhere("showTagged", false)
            Options:Refresh(true)
        end)
        PS.UI.Controls.AttachTooltip(instead, L["Grey bar instead"], { L["Turns on Grey when tagged by others in this "
            .. "design and turns the TAGGED word off in every design. Its eye in the parts tree brings it back."] })
        K.Add(health, insteadRow, OfferGrey)
        Options.editorGreyWhenTagged, Options.editorGreyInstead = grey, instead

        -- Incoming heals and absorbs (the design's own, absent while off: Schema's HEALS; Nameplates/HealPrediction.lua).
        local heals = K.Section(context, L["INCOMING HEALS"])
        K.Add(context, heals)
        local healsRow, healsChoice = K.DropdownRow(heals, L["Incoming heals"], {
            choices = { { value = "off", label = L["Off"] }, { value = "all", label = L["All heals"] },
                { value = "others", label = L["Others' heals only"] } },
            name = WidgetName("selected_healPrediction", "Dropdown"),
            get = function() return ProfileValue("healPrediction")() or "off" end,
            set = function(value) SetProfileValue("healPrediction")(value ~= "off" and value or nil) end,
        })
        Register(healsChoice)
        healsRow.kitSearchKeywords = L["heal prediction shield absorb"]
        Mark(healsRow, Area.Option("healPrediction"))
        K.Add(heals, healsRow)
        local function Help(row, text)
            if not K.AttachHelp(row, text) then K.Add(heals, K.Help(heals, text)) end
        end
        Help(healsRow, L["Heals on the way to the unit, as a bar after its health, the way the game's unit frames show "
            .. "them. Others' heals only leaves out your own (where the game cannot tell them apart, it shows nothing). "
            .. "The game keeps the amounts hidden from addons, so it draws them; nothing is worked out here."])
        local function HealsOn() return ProfileValue("healPrediction")() ~= nil end
        local function HealSwatch(parent, key, shown)
            local row, swatch = K.SwatchRow(parent, L["Colour"], {
                get = function() return Schema.HEALS.Colour(Profile(), key) end,
                set = function(r, g, b) SetProfileValue(key)({ r = r, g = g, b = b }) end,
            })
            Register(swatch)
            Mark(row, Area.Option(key))
            K.Add(parent, row, shown)
            return swatch
        end
        Options.editorHealPrediction = healsChoice
        Options.editorHealColour = HealSwatch(heals, "healPredictionColour", HealsOn)
        local absorbRow, absorbs = K.CheckRow(heals, L["Absorbs"], { text = L["Show shields and heal absorbs"],
            name = WidgetName("selected_absorbs", "Checkbox"),
            get = function() return ProfileValue("absorbs")() == true end,
            set = function(on) SetProfileValue("absorbs")(on == true or nil) end })
        Register(absorbs)
        Mark(absorbRow, Area.Option("absorbs"))
        K.Add(heals, absorbRow)
        Help(absorbRow, L["Shields (damage the unit will absorb) after its health and heals, in this colour; heal "
            .. "absorbs (healing it will soak up) in dark red over the end of its health."])
        Options.editorAbsorbs = absorbs
        Options.editorAbsorbColour = HealSwatch(heals, "absorbColour", function() return ProfileValue("absorbs")() == true end)
        local _, copyHeals = CopyLookRow(heals, "heals", L["Give the other plate types' %s design these Incoming heals "
            .. "and Absorbs?"], L["Gives Enemies, Players and Friendly NPCs (and Enemy players, from World) this Incoming "
            .. "heals choice, Absorbs and their colours, in the same design as the one open here. A design they do not "
            .. "have is left out. Like any change it needs Save."])
        Options.editorHealsCopy = copyHeals
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
                { value = "inside", label = L["Inside"],
                    tooltip = L["The spell's icon inside the bar's left end, as tall as the bar; the spell's name starts after it."] },
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
            return checkbox
        end
        Options.editorCastInterruptCheck = CastCheck("castInterruptColours", L["Colour"], L["Colour by interrupt"])
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
        -- A choice's fields in one write (a module's source is the source and the text: catalog.ChoiceFields).
        local function WriteChoice(value, field)
            local slot, key = SelectedSlot()
            local fields = catalog.ChoiceFields(value, field, slot and slot.kind, slot)
            if not slot or not PS.SetPlateValueSlotFields(Options:EditorTarget(), key, fields) then return false end
            Options:RefreshEditorAppearance(PS.GetSettings())
            Options:SelectEditorComponent(key)
            return true
        end
        local controls = {}
        -- A bar's fill comes from a percentage; a text value from any source; both may be a module's.
        local sourceRow, source = K.DropdownRow(section, L["Source"], {
            placeholder = L["Choose value"], name = WidgetName("selected_value_source", "Dropdown"),
            choices = function() return Kind() == "bar" and catalog.BarSourceChoices() or catalog.ValueSourceChoices() end,
            get = function() return catalog.SlotChoice((SelectedSlot())) end,
            set = function(value) WriteChoice(value, "source") end,
        })
        controls[#controls + 1] = source
        -- Refreshed with every setting-bound control (Options:Refresh) as well as with the part.
        Register(source)
        -- A custom part is one area (its whole slot): its title, what it shows and its picture carry it.
        Mark(section, Area.Part("slot"))
        Mark(sourceRow, Area.Part("slot"))
        K.Add(section, sourceRow, function() return Kind() == nil or Kind() == "bar" end)
        -- An image's picture, in the source's place: where it comes from (From: kit, atlas, shared media, My media), then
        -- the picture, from a list or (an atlas) typed by name. A picture this install lacks is named under it: the
        -- plates draw nothing there. From is the inspector's own until a picture is chosen.
        local function Image() return Kind() == "icon" end
        local function PictureFrom()
            local slot, key = SelectedSlot()
            -- The choice is this part's in this design and type only (another's value3 is another part).
            local chosen = Options.editorPictureFrom
            if chosen and chosen.key == key and chosen.target == Options:EditorTarget() then return chosen.source end
            return catalog.PictureSourceOf(slot)
        end
        local fromRow = K.Row(section, L["From"])
        local from = K.Segmented(fromRow, {
            name = WidgetName("selected_value_from", "Choice"), choices = catalog.PICTURE_SOURCES,
            enabled = function(value)
                if value == "unit" then return #catalog.UnitPictureChoices() > 0 end
                return value ~= "lsm" or PS.Media.HasSharedMedia()
            end,
            disabledTip = function(value)
                if value == "unit" then return L["Only under Type › Totems, on the Enemies and Friendly NPCs."] end
                return L["Shared media comes with many addons (LibSharedMedia); none is installed."]
            end,
            get = PictureFrom,
            set = function(value)
                Options.editorPictureFrom = { key = Options.selectedComponent, source = value, target = Options:EditorTarget() }
                Options:RefreshEditorInspectorContext()
            end,
        })
        controls[#controls + 1] = from
        Mark(fromRow, Area.Part("slot"))
        K.Add(section, fromRow, Image)
        local iconRow, icon = K.DropdownRow(section, L["Picture"], {
            placeholder = L["Choose a picture"], name = WidgetName("selected_value_icon", "Dropdown"),
            choices = function() return catalog.PictureChoices(PictureFrom()) end,
            -- The picture's name without building the list (a module's icon: from the list).
            labelFor = function(value)
                local origin, name = PS.Media.PictureSource(value)
                local piece = origin == "kit" and PS.Media.KitPiece(name)
                if piece then return piece.label end
                if origin == "unit" then return PS.Media.UNIT_PICTURES[name] and PS.Media.UNIT_PICTURES[name].label end
                if origin == "media" or origin == "lsm" or origin == "atlas" then return name end
                return nil
            end,
            get = function() return catalog.SlotChoice((SelectedSlot())) end,
            set = function(value) WriteChoice(value, "icon") end,
        })
        controls[#controls + 1] = icon
        Register(icon)
        Mark(iconRow, Area.Part("slot"))
        K.Add(section, iconRow, function() return Image() and PictureFrom() ~= "atlas" end)
        local atlasRow = K.Row(section, L["Atlas"])
        local atlasBox = K.ValueBox(atlasRow, K.CONTROL_X, K.WIDTH - K.CONTROL_X, function(edit)
            local name = (edit:GetText() or ""):match("^%s*(.-)%s*$")
            if name ~= "" and PS.Media.IsPicture("atlas:" .. name) then WriteChoice("atlas:" .. name, "icon") end
            Options:RefreshEditorInspectorContext()
        end, 64)
        atlasRow.kitSearchExtra = L["Type the atlas's name and press Enter."]
        Mark(atlasRow, Area.Part("slot"))
        K.Add(section, atlasRow, function() return Image() and PictureFrom() == "atlas" end)
        K.Add(section, K.Help(section, L["Add your own pictures in Settings › My media."]),
            function() return Image() and PictureFrom() == "media" and next(PS.Media.MyMedia()) == nil end)
        local missingNote = K.Note(section, "")
        K.Add(section, missingNote, function()
            local slot = SelectedSlot()
            local picture = Image() and slot and not PS.ModuleSources.SlotSource(slot) and PS.Media.SlotPicture(slot)
            local missing = picture and PS.Media.PictureMissing(picture)
            if missing then
                missingNote.text:SetText(string.format(L["Missing picture: %s. The plates draw nothing here until this "
                    .. "install has it."], picture))
                K.Ink(missingNote.text, "error")
            end
            return missing and true or false
        end)
        Options.editorPictureFrom = nil
        Options.editorValueFrom, Options.editorValueAtlasBox, Options.editorValueMissingNote = from, atlasBox, missingNote
        -- A shape's size (bar, box, image): its own Width and Height, unless it is fitted to its part.
        local function Fitted()
            local slot = SelectedSlot()
            return slot ~= nil and slot.fit ~= nil and (slot.kind == "icon" or slot.kind == "box")
        end
        local shape = K.Group(section)
        local function ShapeSize(field, index)
            return function()
                local slot = SelectedSlot()
                local size = slot and PS.ValueImage.SIZE[slot.kind]
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
        K.Add(section, shape, function() return Kind() ~= nil and not Fitted() end)
        Options.editorValueShapeBox, Options.editorValueIconDropdown = shape, icon
        Options.editorValueSourceDropdown = source
        -- An image's or box's look (Schema's IMAGE): its size by its own Width and Height or its part's, then for an
        -- image its flip, quarter turn and tint, and for both its opacity.
        local IMAGE = Schema.IMAGE
        local function Framed() return Kind() == "icon" or Kind() == "box" end
        local function WriteLook(field, value, light)
            if not WriteSlot(field, value, false, light) then return false end
            if not light then Options:RefreshEditorInspectorContext() end
            return true
        end
        local function OnPart()
            local position = SelectedPosition()
            local parent = position and position.parent
            return parent ~= nil and not Schema.IsGroupKey(parent) and Options.editorLayout[parent] ~= nil
        end
        local fitRow = K.Row(section, L["Size by"])
        local fit = K.Segmented(fitRow, {
            name = WidgetName("selected_value_fit", "Choice"),
            choices = { { value = "fixed", label = L["Fixed"], tooltip = L["Its own Width and Height."] },
                { value = "part", label = L["Fit to part"],
                    tooltip = L["As big as the part it is anchored to (a bar, a text), Outset more on each side."] } },
            enabled = function(value) return value == "fixed" or OnPart() end,
            disabledTip = L["Anchor it to a part (not a group or the plate) to fit it to that part."],
            get = function()
                local slot = SelectedSlot()
                return slot and slot.fit or "fixed"
            end,
            set = function(value) WriteLook("fit", value) end,
        })
        controls[#controls + 1] = fit
        Mark(fitRow, Area.Part("slot"))
        fitRow.kitSearchKeywords = L["fit fixed size"]
        K.Add(section, fitRow, Framed)
        local outsetRow, outset = K.SliderRow(section, L["Outset"], {
            min = IMAGE.OUTSET[1], max = IMAGE.OUTSET[2], step = 1, name = WidgetName("selected_value_outset", "Slider"),
            get = function()
                local slot = SelectedSlot()
                return slot and slot.outset or 0
            end,
            drag = function(value) return WriteLook("outset", value, true) end,
            set = function(value) return WriteLook("outset", value) end,
        })
        controls[#controls + 1] = outset
        Mark(outsetRow, Area.Part("slot"))
        K.Add(section, outsetRow, Fitted)
        local FLIPS = { none = { false, false }, x = { true, false }, y = { false, true }, both = { true, true } }
        local flipRow = K.Row(section, L["Flip"])
        local flip = K.Segmented(flipRow, {
            name = WidgetName("selected_value_flip", "Choice"),
            choices = { { value = "none", label = L["None"] },
                { value = "x", label = L["Across"], tooltip = L["Mirrored left to right."] },
                { value = "y", label = L["Up-down"], tooltip = L["Mirrored top to bottom."] },
                { value = "both", label = L["Both"] } },
            get = function()
                local slot = SelectedSlot()
                if not slot then return "none" end
                if slot.flipX and slot.flipY then return "both" end
                return slot.flipX and "x" or slot.flipY and "y" or "none"
            end,
            set = function(value)
                local slot, key = SelectedSlot()
                if not slot then return end
                if PS.SetPlateValueSlotFields(Options:EditorTarget(), key, { flipX = FLIPS[value][1], flipY = FLIPS[value][2] }) then
                    Options:RefreshEditorAppearance(PS.GetSettings())
                    Options:RefreshEditorInspectorContext()
                end
            end,
        })
        controls[#controls + 1] = flip
        Mark(flipRow, Area.Part("slot"))
        K.Add(section, flipRow, Image)
        local turnRow = K.Row(section, L["Turn"])
        local turn = K.Segmented(turnRow, {
            name = WidgetName("selected_value_turn", "Choice"),
            choices = { { value = 0, label = "0" }, { value = 90, label = "90" }, { value = 180, label = "180" },
                { value = 270, label = "270" } },
            get = function()
                local slot = SelectedSlot()
                return slot and slot.rotation or 0
            end,
            set = function(value) WriteLook("rotation", value) end,
        })
        controls[#controls + 1] = turn
        Mark(turnRow, Area.Part("slot"))
        K.Add(section, turnRow, Image)
        local tintRow, tint = K.DropdownRow(section, L["Tint"], {
            name = WidgetName("selected_value_tint", "Dropdown"),
            choices = { { value = "own", label = L["Its colour"], help = L["The Colour below."] },
                { value = "bar", label = L["Its bar's colour"], help = L["The colour of the bar it is anchored to, as it changes."] },
                { value = "class", label = L["Class"], help = L["A player's class colour; another unit's reaction."] },
                { value = "reaction", label = L["Reaction"], help = L["Hostile, neutral or friendly."] },
                { value = "threat", label = L["Threat"],
                    help = L["The threat colour while the unit is in combat with you or your group; else its colour."] } },
            get = function()
                local slot = SelectedSlot()
                return slot and slot.tint or "own"
            end,
            set = function(value) WriteLook("tint", value) end,
        })
        controls[#controls + 1] = tint
        Mark(tintRow, Area.Part("slot"))
        K.Add(section, tintRow, Image)
        local alphaRow, alpha = K.SliderRow(section, L["Opacity"], {
            min = IMAGE.ALPHA[1], max = IMAGE.ALPHA[2], step = 0.05, format = PercentText,
            name = WidgetName("selected_value_alpha", "Slider"),
            get = function()
                local slot = SelectedSlot()
                return slot and slot.alpha or 1
            end,
            drag = function(value) return WriteLook("alpha", value, true) end,
            set = function(value) return WriteLook("alpha", value) end,
        })
        controls[#controls + 1] = alpha
        Mark(alphaRow, Area.Part("slot"))
        K.Add(section, alphaRow, Framed)
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
        -- The tokens, flags and words with values come from the rule reference (Core/RuleWords.lua), so the list
        -- cannot miss one.
        local templateHelp = HelpButton(templateLabel, L["Custom text"], {
            string.format(L["Tokens: %s."], PS.RuleWords.ValueNames()),
            L["Modifiers: {health:short} 1.2k, {health.percent:1} one decimal, {name:upper} {name:lower}, "
                .. "{name:max:10}, {target:else:none} when missing."],
            L["Conditions: [if health.percent < 35]LOW[elseif unit.elite]ELITE[else]{health}[end]. Use and, or, not, "
                .. "brackets and < <= > >= = !=; a flag = true or = false."],
            string.format(L["Flags for conditions: %s. Words with values (= or !=): %s."], PS.RuleWords.FlagNames()),
            L["What each word means, and on which plates: Rules › What can I use?"],
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
            -- The atlas a part draws, unless the box is being typed in.
            if not (atlasBox.HasFocus and atlasBox:HasFocus()) then
                local origin, name = PS.Media.PictureSource(PS.Media.SlotPicture(slot))
                atlasBox:SetText(origin == "atlas" and name or "")
            end
            local custom = Custom()
            if custom and not (templateEdit.HasFocus and templateEdit:HasFocus()) then templateEdit:SetText(slot.template or "") end
            if custom then ShowTemplateStatus(slot.template) end
        end
    end)
end

-- What the designs that draw aura rows use as key's Source (Settings › Auras' line): the one choice's name, or
-- differs by design.
function Options.AuraSourceSummary(key)
    local value, mixed, seen = nil, false, false
    PS.Designs.EachDesign(PS.GetSettings(), { enemy = true, enemyPlayer = true, friendlyPlayer = true, friendlyNPC = true },
        function(profile)
            if not seen then value, seen = profile[key], true elseif profile[key] ~= value then mixed = true end
        end)
    if mixed then return L["differs by design"] end
    for _, choice in ipairs(model.auraSourceChoices) do
        if choice.value == value then return choice.label end
    end
    return ""
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
            -- Whose auras: the design's own (Enemy players' layer included), so mobs can show only yours and enemy
            -- players everyone's.
            local sourceRow, source = K.DropdownRow(which, L["Source"], { choices = model.auraSourceChoices,
                name = WidgetName("selected_" .. definition.source, "Dropdown"), get = ProfileValue(definition.source),
                set = SetProfileValue(definition.source) })
            Register(source)
            Mark(sourceRow, Area.Option(definition.source))
            K.Add(which, sourceRow)
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
            -- Hidden auras' one home is its Settings page: a button opens it.
            local hiddenRow, hiddenLink = K.ButtonRow(which, L["Hidden auras..."], 200)
            hiddenLink:SetScript("OnClick", function() Options:OpenSettingsCategory("hiddenAuras") end)
            K.Add(which, hiddenRow)
            K.AttachHelp(hiddenRow, L["Opens Studio › Settings › Hidden auras, where particular auras are hidden by spell "
                .. "ID or name, for you on every profile."])
            Options.editorHiddenAurasLinks = Options.editorHiddenAurasLinks or {}
            Options.editorHiddenAurasLinks[kind] = hiddenLink
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
    classification = true, statusText = true }
local STYLE_BAR = { health = true, power = true, cast = true }
local function StyleKind(key)
    if STYLE_BAR[key] then return "bar" end
    if key == "backdrop" then return "backdrop" end
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
    threat = true, tagged = true, targetName = true, classification = true, statusText = true }
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
    -- The Backdrop (Nameplates/Backdrop.lua) shares the box's rows (its border has a width too), then how it is sized:
    -- Fit to parts (the parts it wraps, ticked as the soft glow's Glow parts are, and Padding round them) or Fixed size
    -- (Width and Height, placed as any part).
    local BACKDROP = Schema.BACKDROP
    local function Backdrop() return StyleKind(Options.selectedComponent) == "backdrop" end
    local function Fitted() return Backdrop() and Style().backdropWrap ~= "fixed" end
    local function FixedSize() return Backdrop() and Style().backdropWrap == "fixed" end
    local function Boxed() return Text() or Backdrop() end
    local function SquareBox() return Boxed() and Style().boxShape ~= "rounded" end
    K.Add(section, K.SubHeader(section, L["Box behind"]), Boxed)
    K.Add(section, CheckRow(L["Box"], "box", true, L["Show a box"]), Text)
    K.Add(section, DropdownRow(L["Shape"], "boxShape", {
        { value = "", label = L["Square"] }, { value = "rounded", label = L["Rounded (Blizzard's)"] },
    }, "selected_style_box_shape"), Boxed)
    K.Add(section, K.Help(section, L["Rounded is Blizzard's own nameplate level box, in its own colours."]),
        function() return Boxed() and Style().boxShape == "rounded" end)
    -- Height (boxHeight): the text and Padding, or at least the part the text is pinned to (Blizzard's box by its bar).
    K.Add(section, DropdownRow(L["Height"], "boxHeight", {
        { value = "", label = L["Fit the text"] }, { value = "parent", label = L["Match its parent"] },
    }, "selected_style_box_height"), Text)
    K.Add(section, K.Help(section, L["As tall as the part this text is pinned to (the bar beside it), centred on the "
        .. "text; Padding sets its sides."]), function() return Text() and Style().boxHeight == "parent" end)
    K.Add(section, SwatchRow(L["Fill"], "boxColour", STYLE_DEFAULTS.boxColour, true), SquareBox)
    local boxBorder = SwatchRow(L["Border"], "boxBorder", STYLE_DEFAULTS.boxBorder, true)
    K.Add(section, boxBorder, function() return Text() and Style().boxShape ~= "rounded" end)
    local backdropBorder = SwatchRow(L["Border"], "boxBorder", STYLE_DEFAULTS.boxBorder, true)
    SizeAfterSwatch(backdropBorder, "border", Schema.STYLE_BORDER, STYLE_DEFAULTS.backdropEdge)
    backdropBorder.changedMark.area = Area.Style({ "boxBorder", "border" })
    K.Add(section, backdropBorder, function() return Backdrop() and Style().boxShape ~= "rounded" end)
    local wrapRow = DropdownRow(L["Size"], "backdropWrap", {
        { value = "", label = L["Fit to parts"] }, { value = "fixed", label = L["Fixed size"] },
    }, "selected_style_backdrop_wrap")
    K.AttachHelp(wrapRow, L["Fit to parts: it wraps the parts ticked under Wraps while they show, Padding round them, and "
        .. "hides when none shows; move those parts to move it. Fixed size: Width by Height, placed like any part."])
    K.Add(section, wrapRow, Backdrop)
    local ticked = {}
    local function TickedParts()
        local set = BACKDROP.Ticked(Style().backdropParts)
        for _, part in ipairs(BACKDROP.PARTS) do ticked[part] = set[part] == true end
        return ticked
    end
    local partChoices = {}
    for _, part in ipairs(BACKDROP.PARTS) do
        partChoices[#partChoices + 1] = { value = part, label = Options:EditorComponentLabel(part) }
    end
    local partsRow, partsControl = K.DropdownRow(section, L["Wraps"], { multi = true, choices = partChoices,
        name = WidgetName("selected_style_backdrop_parts", "Dropdown"), get = TickedParts,
        set = function(part, on)
            local parts = TickedParts()
            parts[part] = on == true
            local value = BACKDROP.Value(parts)
            return WriteStyle("backdropParts", value ~= BACKDROP.DEFAULT and value or nil)
        end })
    Keep(partsControl)
    Mark(partsRow, Area.Style("backdropParts"))
    K.AttachHelp(partsRow, L["The parts the box wraps while they show. A hidden part (its eye off, nothing to show, "
        .. "or hidden by a rule) is left out; with none showing the box hides. A part pinned to the box itself (the "
        .. "Action icon beside it) is never wrapped: pin it to the name to put it inside."])
    K.Add(section, partsRow, Fitted)
    local paddingRow, padding = K.SliderRow(section, L["Padding"], {
        min = Schema.STYLE_PADDING[1], max = Schema.STYLE_PADDING[2], step = 1,
        get = function() return Style().padding or STYLE_DEFAULTS.padding end,
        drag = function(value) return WriteStyle("padding", value, true) end,
        set = function(value) return WriteStyle("padding", value) end,
    })
    Keep(padding)
    Mark(paddingRow, Area.Style("padding"))
    K.Add(section, paddingRow, function() return Text() or Fitted() end)
    for _, size in ipairs({ { L["Width"], "backdropWidth" }, { L["Height"], "backdropHeight" } }) do
        local field = size[2]
        local row, slider = K.SliderRow(section, size[1], {
            min = BACKDROP.SIZE[1], max = BACKDROP.SIZE[2], step = 1,
            get = function() return Style()[field] or STYLE_DEFAULTS[field] end,
            drag = function(value) return WriteStyle(field, value, true) end,
            set = function(value) return WriteStyle(field, value) end,
        })
        Keep(slider)
        Mark(row, Area.Style(field))
        K.Add(section, row, FixedSize)
    end
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
    -- One placement at a time (audit #15): on the bar, Placement's rows are unavailable (IsEditorPlacedByStyle).
    K.Add(section, K.Help(section, L["On the bar's bottom edge, above or below it, the row sits on the health bar and "
        .. "Placement is off. Where placed: Placement places it."]), Pips)
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
        -- Count only (style badgeShow) uses Size alone, for its number.
        K.Add(section, row, field == "badgeSize" and Badges or function() return Badges() and Style().badgeShow ~= "count" end)
    end
    local orientationRow, orientation = K.DropdownRow(section, L["Direction"], {
        choices = { { value = "horizontal", label = L["Row"] }, { value = "vertical", label = L["Column"] } },
        name = WidgetName("selected_style_badge_direction", "Dropdown"),
        get = function() return Style().badgeOrientation or STYLE_DEFAULTS.badgeOrientation end,
        set = function(value) WriteStyle("badgeOrientation", value) end,
    })
    Keep(orientation)
    Mark(orientationRow, Area.Style("badgeOrientation"))
    K.Add(section, orientationRow, function() return Badges() and Style().badgeShow ~= "count" end)

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
-- ReadRules: the stored list, read only (every rule row's getter and the section's refresh ask on each refresh);
-- CurrentRules: a copy to change and write whole.
local ReadRules
do
    local NONE = {}
    ReadRules = function()
        local key = Options.selectedComponent
        local profile = Profile()
        return key and profile and profile.rules and profile.rules[key] or NONE, key
    end
end
local function CurrentRules()
    local list, key = ReadRules()
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
    -- Rule(): this card's rule in a copy of the list, to change and write; Shown(): the stored one, read only.
    local function Rule()
        local list = CurrentRules()
        return list[index], list
    end
    local function Shown() return (ReadRules())[index] end
    local pad = K.CARD_PAD
    -- When: an on/off box, then the condition, the whole control column (less the remove at the
    -- card's right). A rule turned off stays in the list, unchanged, and never applies.
    local whenRow = K.Add(card, K.Row(card, nil, pad))
    local enabled = Controls.Checkbox(whenRow, {
        name = WidgetName("selected_rule_enabled_" .. index, "Checkbox"), label = "",
        get = function()
            local rule = Shown()
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
    -- The box, then + Word, then the remove.
    local RULE_WORD_W = 64
    local besides = K.SWATCH + K.CONTROL_GAP + RULE_WORD_W + K.CONTROL_GAP
    local when = FieldBox(whenRow, K.CONTROL_X, whenRow.right - besides - K.CONTROL_X, Schema.TEMPLATE_LENGTH)
    K.OnWidth(whenRow, function(width) when:SetWidth(width - pad - besides - K.CONTROL_X) end)
    local word = CreateStudioButton(whenRow, L["+ Word"], RULE_WORD_W, K.CONTROL_H)
    word:SetPoint("LEFT", when, "RIGHT", K.CONTROL_GAP, 0)
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

    -- Then: what it sets; a colour's swatch at the card's right. Set class colour is a colour rule whose colour is the
    -- unit's class colour (colourSource "class"; its picked colour is kept for Set colour), Set difficulty colour the
    -- game's colour for the unit's level against yours (colourSource "difficulty").
    local thenRow = K.Add(card, K.Row(card, L["Then"], pad))
    local CLASS_CHOICE, DIFFICULTY_CHOICE = "classColour", "difficultyColour"
    local function SetChoices()
        local choices = {}
        if Colourable(Options.selectedComponent) then
            choices[#choices + 1] = { value = "colour", label = L["Set colour"] }
            choices[#choices + 1] = { value = CLASS_CHOICE, label = L["Set class colour"],
                help = L["The unit's class colour: yours from Settings › Player colours › Class colours, else Blizzard's. "
                    .. "Where the game keeps the class private, the game's own class colour; a unit with no class keeps "
                    .. "the part's own colour."] }
            choices[#choices + 1] = { value = DIFFICULTY_CHOICE, label = L["Set difficulty colour"],
                help = L["The game's colour for the unit's level against yours: red, orange, yellow, green or grey, and red "
                    .. "for ??. Where the game hides the level, the part keeps its own colour."] }
            choices[#choices + 1] = { value = "blend", label = L["Blend by health"] }
        end
        choices[#choices + 1] = { value = "alpha", label = L["Set opacity"] }
        choices[#choices + 1] = { value = "hide", label = L["Hide it"] }
        return choices
    end
    local setDropdown = K.Dropdown(thenRow, {
        choices = SetChoices, name = WidgetName("selected_rule_set_" .. index, "Dropdown"),
        get = function()
            local rule = Shown()
            if rule and rule.set == "colour" and rule.colourSource == "class" then return CLASS_CHOICE end
            if rule and rule.set == "colour" and rule.colourSource == "difficulty" then return DIFFICULTY_CHOICE end
            return rule and rule.set
        end,
        set = function(value)
            local rule, list = Rule()
            if not rule then return end
            rule.colourSource = nil
            if value == CLASS_CHOICE then value, rule.colourSource = "colour", "class" end
            if value == DIFFICULTY_CHOICE then value, rule.colourSource = "colour", "difficulty" end
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
            local rule = Shown()
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
            local rule = Shown()
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
                local rule = Shown()
                local stops = rule and rule.stops
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
    -- Where the cursor was, for + Word, while the text stays as it was left.
    when:SetScript("OnEditFocusLost", function(edit)
        placeholder:SetShown((edit:GetText() or "") == "")
        edit.wordText, edit.wordCursor = edit:GetText(), edit.GetCursorPosition and edit:GetCursorPosition() or nil
    end)
    when:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
    when:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    -- + Word: the words a condition can use on this plate type, by topic as Help's rule words list them (Core/RuleWords.lua,
    -- the one source), each's meaning on hover; choosing one adds a condition on it that compiles (RuleWords.Starter) at
    -- the cursor where a condition can start there, else after " and " (RuleWords.InsertCondition).
    local function AddWord(starter, cursor)
        local rule, list = Rule()
        if not rule then return false end
        local text, stop = PS.RuleWords.InsertCondition(rule.when, starter, cursor, Schema.TEMPLATE_LENGTH)
        if not text then return false end
        rule.when = text
        when.wordText, when.wordCursor = text, stop
        when:SetText(text)
        if when.SetCursorPosition then when:SetCursorPosition(stop) end
        return WriteRules(list)
    end
    local function WordEntries()
        local shown, cursor = Shown()
        if when.HasFocus and when:HasFocus() and when.GetCursorPosition then
            cursor = when:GetCursorPosition()
        elseif shown and when.wordText == (shown.when or "") then
            cursor = when.wordCursor
        end
        local entries = {}
        for _, topic in ipairs(PS.RuleWords.Conditions(Options.editorProfile)) do
            local children = {}
            for _, entry in ipairs(topic.words) do
                children[#children + 1] = { text = entry.word, func = function() AddWord(entry.starter, cursor) end,
                    tooltip = { title = entry.word, text = string.format(L["%s\nAdds: %s"], entry.text, entry.starter) } }
            end
            entries[#entries + 1] = { text = topic.label, children = children }
        end
        return entries
    end
    word:SetScript("OnClick", function(instance) Options:ShowEditorMenu(WordEntries(), instance) end)
    Controls.AttachTooltip(word, L["+ Word"], { L["Adds a word rules can use, by topic as Settings › Help's rule words "
        .. "list them, as a condition to edit: at the cursor where a condition can start, else after \"and\". Hover a word "
        .. "for what it means."] })
    remove:SetScript("OnClick", function()
        local _, list = Rule()
        table.remove(list, index)
        WriteRules(list)
    end)
    card.when, card.status, card.placeholder, card.setDropdown, card.swatch, card.alpha, card.remove =
        when, status, placeholder, setDropdown, swatch, alpha, remove
    card.stopRows, card.addStop, card.enabled, card.word, card.WordEntries = stopRows, addStop, enabled, word, WordEntries
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
        local picked = rule.set == "colour" and rule.colourSource == nil
        swatch:SetShown(picked)
        if picked then swatch:Refresh() end
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
        local count = #(ReadRules())
        if count == 0 then return L["No rules"] end
        return count == 1 and L["1 rule"] or string.format(L["%d rules"], count)
    end })
    Options.editorRulesBlock = section
    local help = HelpButton(section.band, L["Rules"], {
        L["When its condition holds, a rule sets this part's colour, blends it by health, sets its opacity or "
            .. "hides it. An empty condition always holds."],
        L["Rules are read top to bottom: the last colour or opacity rule that holds wins, and any hide rule "
            .. "hides. With none, the part keeps its own style. Presets add ready-made sets."],
        L["Conditions are the same as in Custom text: health.percent < 35, unit.elite and unit.tagged = false, "
            .. "pvp.flagged = false, role.tank and threat.losing. What can I use? (under the rules) lists every word "
            .. "by topic, with its old name, what it means and an example."],
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
    -- What can I use?: the rule reference (Settings › Help's Rule words, Core/RuleWords.lua).
    local wordsRow, words = K.ButtonRow(section, L["What can I use?"], 140)
    words:SetScript("OnClick", function() Options:OpenRuleReference() end)
    Controls.AttachTooltip(words, L["What can I use?"], { L["Opens Studio › Settings › Help at the rule words: every "
        .. "word rules and custom text can use, by topic, with its old name, what it means, an example and the plates "
        .. "that have it, and how and, or, not and unknown values work."] })
    K.Add(section, wordsRow)
    Options.editorRuleWordsLink = words
    -- The cards, one per rule, in order (each CARD_GAP below the one before).
    local list = K.Group(section)
    local cards = {}
    K.Add(section, list)
    local buttons, addRule = K.ButtonRow(section, L["+ Add rule"], 120)
    addRule:SetScript("OnClick", function()
        local rules = CurrentRules()
        if RuleRoom(rules) < 1 then return end
        local key = Options.selectedComponent
        -- A starter to edit: low health turns the part red (or half see-through). Not "tagged", which
        -- the plates already grey on their own.
        rules[#rules + 1] = { when = "health.percent < 35", set = Colourable(key) and "colour" or "alpha",
            colour = { r = 0.9, g = 0.15, b = 0.1 }, alpha = 0.5 }
        WriteRules(rules)
    end)
    Controls.AttachTooltip(addRule, L["+ Add rule"], { string.format(L["A part keeps up to %d rules, a plate type %d "
        .. "in all; when the button is off, remove one first."], Schema.MAX_RULES_PER_PART, MAX_RULES) })
    K.Add(section, buttons)
    -- Presets: built-in sets of rules that fit this part, appended after its own (the title's action).
    -- Retired ones (a built-in option does the job: Threat colours, Colour by interrupt, Fading) are not
    -- offered; rules made from them stay ordinary rules.
    -- A preset for some plate types only (plates: Colour objects by type, the Objects tab's) is offered there.
    local function PresetFits(preset, key)
        return not preset.retired and (preset.kind ~= "colour" or Colourable(key))
            and (preset.plates == nil or preset.plates[Options.editorProfile] == true)
    end
    local function RulePresetEntries()
        local key, entries = Options.selectedComponent, {}
        local room = RuleRoom((ReadRules()))
        for _, preset in ipairs(RULE_PRESETS) do
            if PresetFits(preset, key) then
                entries[#entries + 1] = { text = preset.name, disabled = room < #preset.rules, func = function()
                    local rules = CurrentRules()
                    if RuleRoom(rules) < #preset.rules then return end
                    for _, rule in ipairs(preset.rules) do rules[#rules + 1] = PS.Table.DeepCopy(rule) end
                    WriteRules(rules)
                end }
            end
        end
        -- Built in: the options that do the retired presets' jobs (ProfilePresets.BUILT_IN), after the presets of a part
        -- that has some. Each opens its setting and adds no rule, so there is still one route per job.
        if #entries == 0 then return entries end
        local builtIn = {}
        for _, option in ipairs(Presets.BUILT_IN) do
            local open = Options.OpenBuiltInOption
            builtIn[#builtIn + 1] = { text = option.name, func = function() open(option.id) end,
                tooltip = { title = option.name, text = string.format(L["Opens it in %s. It adds no rule; your rules still "
                    .. "win over it."], option.home) } }
        end
        entries[#entries + 1] = { text = L["Built in"], children = builtIn,
            tooltip = { title = L["Built in"], text = L["Jobs PlateSmith does without rules: each opens its setting."] } }
        return entries
    end
    local presets = CreateStudioButton(section.band, L["Presets"], 86, K.BUTTON_H)
    K.Accessory(section, presets)
    presets:SetScript("OnClick", function(instance) Options:ShowEditorMenu(RulePresetEntries(), instance) end)
    Controls.AttachTooltip(presets, L["Presets"], { L["Adds a ready-made set of rules after this part's own."] })
    Options.editorRulesAdd, Options.editorRulePresetsButton = addRule, presets
    Options.editorRuleRows = cards
    Options.EditorRulePresetEntries = RulePresetEntries
    -- Whether any preset fits this part (RulePresetEntries offers one), without listing them.
    local function AnyPresetFits()
        local key = Options.selectedComponent
        for _, preset in ipairs(RULE_PRESETS) do
            if PresetFits(preset, key) then return true end
        end
        return false
    end
    -- The cards show the stored rules (read only: each change writes a copy, CurrentRules).
    Options.editorRulesRefresh = function()
        local rules, key = ReadRules()
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
        local fits = AnyPresetFits()
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
-- RefreshTargetHighlightPreview). Highlight: Off, Edge (stored "border", or "halo" while it pulses) or
-- Soft glow behind. One Pulse slowly box serves both lit styles: Edge's switches border and halo, the
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
-- The edge's colour: on the bars' edges and the text (Edge) and the health bar's edge (Edge and Soft glow behind).
local function CustomEdge()
    local mode = TargetLit() and EditorHighlight().targetEdgeColourMode
    return mode == "custom" or mode == "threat"
end
-- The glow's wrap: Fit to parts (its Width and Height are targetGlowSpread and targetGlowSpreadY, room past the
-- parts) or Fixed size (targetGlowWidth and targetGlowHeight, its whole size). Height shows only with Same width
-- and height (targetGlowEven) off.
local function Fixed() return EditorHighlight().targetGlowWrap == "fixed" end
local function FitsParts() return Glowing() and not Fixed() end
local function FixedGlow() return Glowing() and Fixed() end
local function Uneven() return EditorHighlight().targetGlowEven == false end
local function FitsPartsUneven() return FitsParts() and Uneven() end
local function FixedUneven() return FixedGlow() and Uneven() end
-- Its rows in order (Settings search lists them before they are built): id is the option.
local TARGET_ROWS = {
    { id = "targetHighlightStyle", label = L["Highlight"], shown = Lit, keywords = L["glow edge target selected"],
        help = L["Edge lights the selected plate's "
        .. "text and bar edges, gold or in its Edge colour, steady or pulsing; Soft glow behind is a soft light behind "
        .. "the whole plate. Either appears only on PlateSmith's own artwork, not on the 3D character model or "
        .. "Blizzard-owned plates."] },
    { id = "targetEdgeColourMode", label = L["Edge colour"], shown = TargetLit,
        help = L["The edge's colour on the bars and text, and on the health bar's outline (with Soft glow behind too): "
            .. "its own gold, one you pick, the target's class (players), its reaction, or your threat on it. Threat: your "
            .. "threat colour on this target while you're in combat with it; your custom colour otherwise."] },
    { id = "targetEdgeColour", label = L["Custom edge colour"], shown = CustomEdge },
    { id = "targetGlowColourMode", label = L["Glow colour"], shown = Glowing,
        help = L["The glow's colour: one you pick, the target's class (players), its reaction, or your threat on it. "
            .. "Threat: your threat colour on this target while you're in combat with it; your custom colour otherwise."] },
    { id = "targetGlowColour", label = L["Custom glow colour"], shown = CustomGlow },
    { id = "targetGlowOpacity", label = L["Glow opacity"], shown = Glowing, step = 0.05, format = PercentText },
    { id = "targetGlowWrap", label = L["Glow wrap"], shown = Glowing, help = L["Fit to parts: the glow follows the parts "
        .. "you pick as they show and hide (a names-only plate's name line), and Width and Height add room around them. "
        .. "Fixed size: Width and Height are the glow's whole size, centred on the health bar."] },
    { id = "targetGlowParts", label = L["Glow parts"], shown = FitsParts, help = L["The parts the glow wraps while they "
        .. "show and sit next to each other. With none showing, it wraps the health bar."] },
    { id = "targetGlowOffsetX", label = L["Glow offset X"], shown = Glowing, step = 1 },
    { id = "targetGlowOffsetY", label = L["Glow offset Y"], shown = Glowing, step = 1,
        help = L["Moves the glow's centre right (X) or up (Y), in pixels."] },
    { id = "targetGlowSpread", label = L["Glow width"], shown = FitsParts, step = 1,
        help = L["How far the glow reaches past the parts left and right (and up and down with Same width and height), "
            .. "in pixels, the same on both sides."] },
    { id = "targetGlowSpreadY", label = L["Glow height"], shown = FitsPartsUneven, step = 1,
        help = L["How far the glow reaches past the parts up and down, in pixels, the same on both sides."] },
    { id = "targetGlowWidth", label = L["Glow width"], shown = FixedGlow, step = 1,
        help = L["The glow's whole width (and height with Same width and height), in pixels."] },
    { id = "targetGlowHeight", label = L["Glow height"], shown = FixedUneven, step = 1,
        help = L["The glow's whole height, in pixels."] },
    -- (Its line is the note under it, made with the row: what Width and Height are in this wrap.)
    { id = "targetGlowEven", label = L["Same width and height"], shown = Glowing },
    { id = "targetGlowPulse", label = L["Pulse slowly"], shown = TargetLit,
        help = L["The edge or the soft glow slowly fades in and out."] },
}

-- The section's rows for Settings search: { id, label, help, shown, frame (once built), section }.
function Options:EditorTargetHighlightRows()
    local rows, built = {}, self.editorTargetHighlightRowFrames or {}
    for index, spec in ipairs(TARGET_ROWS) do
        rows[index] = { id = spec.id, label = spec.label, help = spec.help, keywords = spec.keywords, shown = spec.shown,
            frame = built[spec.id], section = self.editorTargetHighlightSection }
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
    -- Objects show no target highlight (Lifecycle's UpdateTarget).
    K.Add(context, section, function() return not Options:IsEditorObject() end)
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
    local _, setEven = Bind("targetGlowEven")
    local _, setParts = Bind("targetGlowParts")
    local HIGHLIGHT, ticked = Schema.HIGHLIGHT, {}
    local function TickedParts()
        local set = HIGHLIGHT.PartsSet(EditorHighlight().targetGlowParts)
        for _, part in ipairs(HIGHLIGHT.GLOW_PARTS) do ticked[part] = set == nil or set[part] == true end
        return ticked
    end
    -- A colour row (the glow's or the edge's custom colour): while a colour is picked only the swatch and the preview
    -- follow.
    local function Swatch(spec)
        local row, colour
        row, colour = K.SwatchRow(section, spec.label, {
            name = WidgetName("editor_" .. spec.id, "Colour"),
            get = function() return EditorHighlight()[spec.id] end,
            set = function(r, g, b)
                Write(spec.id, { r = r, g = g, b = b })
                colour:Refresh()
                GlowPreview()
            end,
        })
        return row, colour
    end
    local build = {
        targetHighlightStyle = function(spec)
            return K.DropdownRow(section, spec.label, { choices = model.targetHighlightChoices, get = ShownStyle,
                set = function(value)
                    -- Edge keeps a pulsing edge pulsing.
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
        targetEdgeColourMode = function(spec)
            local get, set = Bind(spec.id)
            return K.DropdownRow(section, spec.label, { choices = model.targetEdgeColourChoices, get = get, set = set,
                name = WidgetName("editor_targetEdgeColourMode", "Dropdown") })
        end,
        -- Fixed size unticks Same width and height in the same edit (one change), so it starts as its own
        -- Width by Height box, not a square; Fit to parts leaves the tick as it is.
        targetGlowWrap = function(spec)
            local get, set = Bind(spec.id)
            return K.DropdownRow(section, spec.label, { choices = model.targetGlowWrapChoices, get = get,
                set = function(value)
                    if value ~= "fixed" or EditorHighlight().targetGlowEven == false then return set(value) end
                    local ok = PS.SetPlateProfileOption(Options:EditorTarget(), { targetGlowWrap = value, targetGlowEven = false })
                    Options:Refresh(true)
                    return ok
                end,
                name = WidgetName("editor_targetGlowWrap", "Dropdown") })
        end,
        -- One item per part: it writes the whole set (Schema's targetGlowParts names it).
        targetGlowParts = function(spec)
            return K.DropdownRow(section, spec.label, { multi = true, choices = model.targetGlowPartChoices,
                name = WidgetName("editor_targetGlowParts", "Dropdown"), get = TickedParts,
                set = function(part, on)
                    local parts = TickedParts()
                    parts[part] = on == true
                    return setParts(HIGHLIGHT.PartsValue(parts))
                end })
        end,
        -- Unticked, Height starts at Width, so nothing moves until it is dragged.
        targetGlowEven = function(spec)
            return K.CheckRow(section, nil, { text = spec.label, name = WidgetName("editor_targetGlowEven", "Checkbox"),
                get = function() return EditorHighlight().targetGlowEven ~= false end,
                set = function(on)
                    if on then return setEven(true) end
                    local highlight = EditorHighlight()
                    if highlight.targetGlowWrap == "fixed" then
                        Write("targetGlowHeight", highlight.targetGlowWidth)
                    else
                        Write("targetGlowSpreadY", highlight.targetGlowSpread)
                    end
                    return setEven(false)
                end })
        end,
        targetGlowColour = Swatch,
        targetEdgeColour = Swatch,
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
        -- Changed here: a design other than World with its own value (Studio/Marks.lua). Edge's pulse is
        -- its style ("halo").
        Mark(row, Area.Option(spec.id == "targetGlowPulse" and { "targetGlowPulse", "targetHighlightStyle" } or spec.id))
        controls[spec.id], frames[spec.id] = Register(control), row
        if spec.id == "targetGlowEven" then
            -- One line under the size rows: what Width and Height are in this wrap.
            local note = K.Help(section, "")
            K.Add(section, note, Glowing)
            Options.editorTargetGlowSizeNote = note
            Register({ Refresh = function()
                note.text:SetText(Fixed() and L["Width and Height are the glow's whole size, centred on the health bar."]
                    or L["The glow follows the plate's parts; Width and Height add room around them."])
            end })
        end
    end
    -- A profile saved before 1.2.1 keeps the health bar's gold target edge with Highlight Off
    -- (targetOffKeepsEdge, every design); a line says so, with a button that drops the edge.
    local function KeepsEdge()
        return Lit() and EditorHighlight().targetHighlightStyle == "off" and PS.GetSettings().targetOffKeepsEdge == true
    end
    K.Add(section, K.Help(section, L["This profile keeps the health bar's gold target edge with Highlight Off, as "
        .. "before 1.2.1."]), KeepsEdge)
    local dropRow, drop = K.ButtonRow(section, L["No gold edge"], 140)
    drop:SetScript("OnClick", function()
        PS.SetOption("targetOffKeepsEdge", false)
        Options:Refresh(true)
    end)
    K.Add(section, dropRow, KeepsEdge)
    Options.editorTargetOffKeepsEdge = drop
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

-- Hide unstyled names (hideUnstyledFriendlyNames): it changes the game's own friendly name settings (NamePolicy's
-- players', pets', guardians', minions' and totems' name CVars, kept off by its watch), so its home is Settings ›
-- Behaviour & display › Names; Players › Plate settings › Friendly plates has a line that reads it and opens it there.
-- Its help: one short line, then the detail.
local HIDE_UNSTYLED_HELP = L["Outside dungeons & raids, keeps the game's large floating names off friendly players and "
    .. "their pets, guardians, minions and totems."]
local HIDE_UNSTYLED_DETAIL = L["The game draws those names over players PlateSmith gives no name: past its 40 nameplates "
    .. "in a crowd, or past nameplate range. On: those players show no name, and if another addon or the game's Names "
    .. "options turn the names back on, PlateSmith turns them off again. Off: the game's Names options decide. Friendly "
    .. "NPCs' names are not affected."]

-- Clicking (Nameplates/ClickThrough.lua): its home is Settings › Behaviour & display › Clicking; the Clicks rows in
-- Players' and Friendly NPCs' Friendly plates read and write the same settings (STANDARDS section 2a rule 3). Each
-- row's choices and help, and the one dropdown both places build. Friendly players' row shows "Click through (shared
-- with NPCs)" and is locked while Friendly NPCs' Click through covers them (the game has one Friendly setting).
local CLICKS = {
    players = {
        { value = "clickable", label = L["Clickable"], help = L["Clicking the plate selects the player."] },
        { value = "through", label = L["Click through"], help = L["Clicks pass through the plate to whatever is behind it."] },
    },
    others = {
        { value = "game", label = L["Clickable"], help = L["PlateSmith leaves the game's click area as it is."] },
        { value = "through", label = L["Click through"], help = L["Clicks pass through the plate to whatever is behind it."] },
    },
    shared = L["Click through (shared with NPCs)"],
    help = {
        clickFriendlyPlayer = L["While PlateSmith draws friendly players outside dungeons & raids. Click through turns on "
            .. "the game's names-only option for them, which leaves their plates nothing to click; PlateSmith still draws "
            .. "its own look. With Blizzard's plates, and in dungeons & raids, the game's option is yours."],
        clickFriendlyNPC = L["The game has one click setting for every friendly plate, so Click through here makes "
            .. "friendly players click through too. Outside dungeons & raids."],
        clickEnemy = L["Every enemy plate, everywhere."],
    },
    home = L["The same setting as Settings › Behaviour & display › Clicking."],
}
local function ClickDropdownRow(kit, parent, key, label, name)
    local ClickThrough = PS.ClickThrough
    local players = key == "clickFriendlyPlayer"
    local get, set = Options.BindSetting(key)
    local spec = { choices = players and CLICKS.players or CLICKS.others, set = set, name = name }
    if players then
        spec.get = function() return ClickThrough.PlayersValue(PS.GetSettings()) end
        spec.labelFor = function(value) return value == "shared" and CLICKS.shared or nil end
    else
        spec.get = function() return get() == "through" and "through" or "game" end
    end
    local row, dropdown = kit.DropdownRow(parent, label, spec)
    if players then
        local refresh = dropdown.Refresh
        function dropdown:Refresh()
            refresh(self)
            local shared = ClickThrough.SharedThrough(PS.GetSettings())
            SetAvailable(self, not shared)
            row:SetAlpha(shared and DIMMED_ALPHA or 1)
        end
    end
    return row, dropdown
end

-- Plate settings' Friendly plates, first on the Players and Friendly NPCs tabs: the one home for how the open
-- friendly plate type shows outdoors. Show as (Schema's FRIENDLY, each type its own, through PS.SetFriendlyMode);
-- on Players, a line saying whether Hide unstyled names is on, which opens it in Settings › Behaviour & display ›
-- Names (its home);
-- Show in, this type's row of Where plates show (Studio/Visibility.lua, the same settings as Settings' grid and
-- the design row's eye); and the way to the Dungeons & raids design, where Blizzard draws them. Its rows in
-- order, for Settings search before they are built: id, label, help, plateType (the tab it is on, when only one).
local FRIENDLY_ROWS = {
    { id = "section", label = L["Friendly plates"] },
    { id = "showAs", label = L["Show as"], help = L["How this plate type's friendly units show outside dungeons & raids: "
        .. "PlateSmith's names only or full plates, or Blizzard's own plates. Players and Friendly NPCs each have their "
        .. "own. Blizzard's plates still show: to hide this type's plates in a place, use Show in below (Where plates "
        .. "show)."] },
    { id = "clicksPlayer", key = "clickFriendlyPlayer", label = L["Clicks"], plateType = "friendlyPlayer",
        help = CLICKS.help.clickFriendlyPlayer .. " " .. CLICKS.home },
    { id = "clicksNPC", key = "clickFriendlyNPC", label = L["Clicks"], plateType = "friendlyNPC",
        help = CLICKS.help.clickFriendlyNPC .. " " .. CLICKS.home },
    { id = "hideUnstyled", label = L["Hide unstyled names"], plateType = "friendlyPlayer", help = HIDE_UNSTYLED_HELP },
    { id = "showIn", label = L["Show in"], help = L["Where this plate type's plates show. The same switches as Settings › "
        .. "Where plates show."] },
    { id = "who", key = "shownFriendlyPlayerWho", label = L["Friendly players"], plateType = "friendlyPlayer",
        help = L["Which friendly players get a plate where PlateSmith draws them: everyone, your group only, or your group "
            .. "and guild; whoever you target always gets one. Blizzard's own plates are never hidden by it. Its home is "
            .. "Settings › Where plates show › "
            .. "Friendly players: the same setting, for every design."] },
    { id = "dungeon", label = L["Dungeons & raids design"], help = L["In dungeons & raids Blizzard draws friendly "
        .. "plates: its names, names only, class colours and font are set in this plate type's Dungeons & raids design."] },
}
local function FriendlyTab()
    return Options.editorProfile == "friendlyPlayer" or Options.editorProfile == "friendlyNPC"
end

-- The section's rows for Settings search: { id, label, help, plateType, frame (once built), section }.
function Options:EditorFriendlyRows()
    local rows, built = {}, self.editorFriendlyRowFrames or {}
    for index, spec in ipairs(FRIENDLY_ROWS) do
        rows[index] = { id = spec.id, label = spec.label, help = spec.help, plateType = spec.plateType, frame = built[spec.id],
            section = self.editorFriendlySection }
    end
    return rows
end

local function BuildFriendlySection(context)
    local frames = {}
    Options.editorFriendlyRowFrames = frames
    local section = K.Section(context, L["FRIENDLY PLATES"], { summary = function()
        local mode = Options:EditorShowAs()
        for _, choice in ipairs(model.friendlyChoices) do
            if choice.value == mode then return choice.label end
        end
        return ""
    end })
    K.Add(context, section, FriendlyTab)
    Options.editorFriendlySection, frames.section = section, section
    local spec = {}
    for _, row in ipairs(FRIENDLY_ROWS) do spec[row.id] = row end
    local scope = K.Help(section, "")
    K.Add(section, scope)
    Register({ Refresh = function()
        scope.text:SetText(string.format(L["For %s, outside dungeons & raids."], Options:EditorPlateLabel(Options.editorProfile)))
    end })

    local showRow, showAs = K.DropdownRow(section, spec.showAs.label, { choices = model.friendlyChoices,
        name = WidgetName("editor_friendlyShowAs", "Dropdown"),
        get = function() return Options:EditorShowAs() end,
        set = function(value) return Options:SetEditorShowAs(value) end })
    K.Add(section, showRow)
    K.AttachHelp(showRow, spec.showAs.help)
    Options.editorFriendlyShowAs, frames.showAs = Register(showAs), showRow
    K.Add(section, K.Help(section, L["Blizzard draws these plates everywhere."]),
        function() return Options:EditorShowAs() == "off" end)
    -- Clicks, independent of Show as: a shortcut to Settings › Behaviour & display › Clicking's row for this plate type
    -- (the same setting).
    Options.editorFriendlyClicks = {}
    for _, id in ipairs({ "clicksPlayer", "clicksNPC" }) do
        local entry = spec[id]
        local function Shown()
            return Options.editorProfile == entry.plateType and PS.ClickThrough.Supported(entry.key)
        end
        local row, control = ClickDropdownRow(K, section, entry.key, entry.label,
            WidgetName("editor_friendlyClicks_" .. entry.plateType, "Dropdown"))
        K.Add(section, row, Shown)
        K.AttachHelp(row, entry.help)
        Options.editorFriendlyClicks[entry.key] = Register(control)
        frames[id] = row
    end
    -- One line each, so the shared Friendly setting is never a surprise.
    K.Add(section, K.Help(section, L["The game has one click setting for all friendly plates: Click through here makes "
        .. "friendly players click through too."]), function()
        return Options.editorProfile == "friendlyNPC" and PS.ClickThrough.Supported("clickFriendlyNPC")
    end)
    K.Add(section, K.Help(section, L["Friendly NPCs' Click through covers players too: the game has one click setting for "
        .. "all friendly plates."]), function()
        return Options.editorProfile == "friendlyPlayer" and PS.ClickThrough.SharedThrough(PS.GetSettings())
    end)
    -- Friendly NPCs with the game's own switch for their plates off: the green names over them are the game's
    -- floating names, which cannot be clicked. The way is Where plates show (Studio/Visibility.lua), its one home.
    local function NPCPlatesOff()
        return Options.editorProfile == "friendlyNPC" and PS.PlateVisibility.GameHides("friendlyNPC")
    end
    K.Add(section, K.Help(section, L["The game's friendly NPC plates are off, so NPCs show only floating names (not "
        .. "clickable)."]), NPCPlatesOff)
    local npcOffRow, npcOff = K.ButtonRow(section, L["Where plates show"], 170)
    npcOff:SetScript("OnClick", function() Options:OpenPlateVisibilitySettings() end)
    K.Add(section, npcOffRow, NPCPlatesOff)
    Options.editorFriendlyNPCPlatesOff = npcOff

    -- Hide unstyled names (Players): one line across the row, reading the setting and opening its home, Settings ›
    -- Behaviour & display › Names (STANDARDS §2a rule 3). The whole path would not fit the line, so its tooltip names it.
    local getHide = Options.BindSetting("hideUnstyledFriendlyNames")
    local hideRow = K.Row(section, nil)
    local hide = CreateFrame("Button", WidgetName("editor_friendlyHideUnstyled", "Button"), hideRow)
    hide:SetAllPoints(hideRow)
    hide.hover = hide:CreateTexture(nil, "BACKGROUND")
    hide.hover:SetAllPoints(hide)
    hide.hover:Hide()
    hide.text = K.Text(hide, "", "label")
    hide.text:SetPoint("LEFT", hide, "LEFT", 0, 0)
    hide.text:SetPoint("RIGHT", hide, "RIGHT", 0, 0)
    if hide.text.SetWordWrap then hide.text:SetWordWrap(false) end
    hide:SetScript("OnEnter", function(instance)
        local colour = K.Palette().hover or { 1, 1, 1, 0.06 }
        instance.hover:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1)
        instance.hover:Show()
        K.Ink(instance.text, "value")
    end)
    hide:SetScript("OnLeave", function(instance)
        instance.hover:Hide()
        K.Ink(instance.text, "label")
    end)
    PS.UI.Controls.AttachTooltip(hide, spec.hideUnstyled.label, { spec.hideUnstyled.help, HIDE_UNSTYLED_DETAIL,
        { L["It changes the game's own name settings, so it is set in Settings › Behaviour & display › Names. "
            .. "Click to open it there."], 0.86, 0.86, 0.86 } })
    hide:SetScript("OnClick", function() Options:OpenSettingsControl("plate.hideUnstyledFriendlyNames") end)
    function hide:Refresh()
        self.text:SetText(getHide() and L["Hide unstyled names: On, in Settings"]
            or L["Hide unstyled names: Off, in Settings"])
    end
    K.Add(section, hideRow, function() return Options.editorProfile == spec.hideUnstyled.plateType end)
    Options.editorFriendlyHideUnstyled, frames.hideUnstyled = Register(hide), hideRow

    frames.showIn = Options.BuildPlateShowIn(K, section, spec.showIn.label, spec.showIn.help)
    -- Friendly players (Players): a shortcut to Where plates show's row (its home), writing the same setting.
    local getWho, setWho = Options.BindSetting(spec.who.key)
    local whoRow, who = K.DropdownRow(section, spec.who.label, { choices = Options.FRIENDLY_PLAYER_WHO, get = getWho,
        set = setWho, name = WidgetName("editor_friendlyWho", "Dropdown") })
    K.Add(section, whoRow, function() return Options.editorProfile == spec.who.plateType end)
    K.AttachHelp(whoRow, spec.who.help)
    Options.editorFriendlyWho, frames.who = Register(who), whoRow

    K.Add(section, K.Help(section, L["Blizzard draws them in dungeons & raids:"]))
    local dungeonRow, dungeon = K.ButtonRow(section, spec.dungeon.label, 200)
    dungeon:SetScript("OnClick", function() Options:SetEditorDesign("dungeon") end)
    K.Add(section, dungeonRow)
    K.AttachHelp(dungeonRow, spec.dungeon.help)
    Options.editorFriendlyDungeonLink, frames.dungeon = dungeon, dungeonRow
    -- Show as, Hide unstyled names, Show in and Friendly players are the whole profile's, whichever design is open.
    Options.SharedSettingNote(K, section, nil, true)
end

-- Plate settings' Objects, first on the Objects tab: design things only (Copy style from a look) and the way to the
-- home of the object settings, Studio › Settings › Objects & interacting (who draws them, fading, pointing at a
-- plate, the game's interact key), so each setting has one place.

-- Copy style from a look's menu: the looks in their order; picking one copies its Objects style, asking first when the
-- Objects tab has changes of its own (they would go).
function Options:ObjectLookMenuItems()
    local items = {}
    for _, preset in ipairs(PS.ProfilePresets.LIST) do
        local id, name = preset.id, preset.name
        items[#items + 1] = { text = name, tooltip = { title = name, text = preset.description }, func = function()
            local function Copy()
                if PS.CopyObjectLook(id) then Options:Refresh(true) end
            end
            if not PS.ObjectLookChanged() then return Copy() end
            Options:ConfirmStudioAction(string.format(L["Give this profile %s's Objects style? Your changes on the Objects "
                .. "tab (All objects, its types and Fade objects you can't use yet) go; Revert undoes it until you Save."], name),
                L["Copy"], Copy)
        end }
    end
    return items
end

function Options:OpenObjectLookMenu(anchor)
    return PS.UI.Menu.Toggle(anchor, function() return Options:ObjectLookMenuItems() end, { width = 200 })
end

local function BuildObjectsSection(context)
    local section = K.Section(context, L["OBJECTS"])
    K.Add(context, section, function() return Options.editorProfile == "object" end)
    Options.editorObjectsSection = section
    K.Add(section, K.Help(section, L["Books, chests, ore and quest objects the game gives a plate. Where they show is "
        .. "the game's: it has no switch for object plates."]))
    -- A look's Objects style into this profile (Settings' CopyObjectLook), confirmed first when the Objects tab has
    -- changes of its own (ObjectLookChanged).
    local copyRow, copy = K.ButtonRow(section, L["Copy style from a look..."], 200)
    copy:SetScript("OnClick", function(instance) Options:OpenObjectLookMenu(instance) end)
    K.Add(section, copyRow)
    K.AttachHelp(copyRow, L["Gives this profile the Objects style of a look (PlateSmith, Classic... Blizzard): All "
        .. "objects' design, its types (herbs green, the Status text...) and Fade objects you can't use yet. The Objects' "
        .. "Dungeons & raids, Battlegrounds & arenas and Cities & inns designs stay. Like any change it needs Save; "
        .. "Revert undoes it."])
    Options.editorObjectCopyLook = copy
    local settingsRow, settingsLink = K.ButtonRow(section, L["Object settings..."], 200)
    settingsLink:SetScript("OnClick", function() Options:OpenSettingsCategory("objects") end)
    K.Add(section, settingsRow)
    K.AttachHelp(settingsRow, L["Opens Studio › Settings › Objects & interacting: who draws object plates, corpse "
        .. "plates, what pointing at an object's plate shows, and the game's interact key."])
    Options.editorObjectSettingsLink = settingsLink
end

-- Plate settings' Object looks, on the Objects tab: Fade objects you can't use yet (objectFadeUnable) and When out of
-- reach (interactRangeCue, ActionIcon.Cue), the home of these two looks. They are general settings (one value for every
-- design), so the section says so; Settings › Objects & interacting links here. Its rows, for search and the links.
local OBJECT_LOOKS = {
    ROWS = {
        { id = "objectFadeUnable", label = L["Fade objects you can't use yet"], help = L["Fades an object's plate while "
            .. "the game's icon says you can't use it yet, such as a herb or vein your skill is too low for (object.unable). "
            .. "Off: they look like the rest."] },
        { id = "interactRangeCue", label = L["When out of reach"], help = L["How an object, corpse or Friendly NPC with an "
            .. "Action icon shows that the game says it is out of reach (interact.inrange). When the game can't say, nothing "
            .. "changes. For words such as \"Too far\" you can move and style, add the Range part (+ Add › Text › Range). "
            .. "Rules can do more with interact.inrange."] },
    },
    CUE_CHOICES = {
        { value = "off", label = L["Game's icon only"], help = L["Only the game's greyed icon shows it."] },
        { value = "dim", label = L["Dim the plate"], help = L["The plate fades, as Fade objects you can't use yet "
            .. "fades it."] },
        { value = "grey", label = L["Grey the name"], help = L["The name turns grey. A colour rule on the name wins."] },
    },
}
function OBJECT_LOOKS.CueLabel(value)
    for _, choice in ipairs(OBJECT_LOOKS.CUE_CHOICES) do
        if choice.value == value then return choice.label end
    end
    return ""
end
Options.editorObjectLookChoices = OBJECT_LOOKS

function Options:EditorObjectLookRows()
    local rows, built = {}, self.editorObjectLookRowFrames or {}
    for index, spec in ipairs(OBJECT_LOOKS.ROWS) do
        rows[index] = { id = spec.id, label = spec.label, help = spec.help, frame = built[spec.id],
            section = self.editorObjectLookSection }
    end
    return rows
end

function OBJECT_LOOKS.Build(context)
    local fade, cue = OBJECT_LOOKS.ROWS[1], OBJECT_LOOKS.ROWS[2]
    local section = K.Section(context, L["OBJECT LOOKS"], { summary = function()
        return OBJECT_LOOKS.CueLabel(PS.GetSettings().interactRangeCue)
    end })
    K.Add(context, section, function() return Options.editorProfile == "object" end)
    Options.editorObjectLookSection = section
    local getFade, setFade = Options.BindSetting(fade.id)
    local fadeRow, fadeBox = K.CheckRow(section, nil, { text = fade.label, get = getFade, set = setFade,
        name = WidgetName("editor_objectFadeUnable", "Checkbox") })
    K.Add(section, fadeRow)
    if not K.AttachHelp(fadeRow, fade.help) then K.Add(section, K.Help(section, fade.help)) end
    local getCue, setCue = Options.BindSetting(cue.id)
    local cueRow, cueChoice = K.DropdownRow(section, cue.label, { choices = OBJECT_LOOKS.CUE_CHOICES, get = getCue,
        set = setCue, name = WidgetName("editor_interactRangeCue", "Dropdown") })
    K.Add(section, cueRow)
    if not K.AttachHelp(cueRow, cue.help) then K.Add(section, K.Help(section, cue.help)) end
    Options.editorObjectFade, Options.editorObjectReachCue = Register(fadeBox), Register(cueChoice)
    Options.editorObjectLookRowFrames = { objectFadeUnable = fadeRow, interactRangeCue = cueRow }
    Options.SharedSettingNote(K, section, nil, true)
end

-- Plate settings' Totems, shown while Type › Totems is open on the Enemies or Friendly NPCs: how a totem's plate draws
-- (Schema's TOTEMS, the Totems layer's own option, absent while Plate; Nameplates/Totems.lua draws it). Its row, for
-- Settings search before it is built (Options:EditorTotemRows), and its choices.
local TOTEM_SECTION = {
    ROWS = { { id = "totemDisplay", label = L["Display"], keywords = L["totem totems shaman icon mana spring grounding windfury"],
        help = L["How a shaman totem's plate draws. Plate: this Totems design's plate (everything you change while Totems "
            .. "is open). Icon: only its Totem icon, a part you move and size like any other (added if there is none). "
            .. "Icon and name: the icon and its name. Name only: its name, no bars or level. Hidden: no plate. A totem with "
            .. "no known icon (another language, a creature's own totem) shows a plain totem icon. In dungeons & raids "
            .. "Blizzard draws friendly plates, so there only PlateSmith's own text changes, as its name."] } },
    CHOICES = { { value = "plate", label = L["Plate"] }, { value = "icon", label = L["Icon"] },
        { value = "iconName", label = L["Icon and name"] }, { value = "name", label = L["Name only"] },
        { value = "hidden", label = L["Hidden"] } },
}

function Options:EditorTotemRows()
    local rows, built = {}, self.editorTotemRowFrames or {}
    for index, spec in ipairs(TOTEM_SECTION.ROWS) do
        rows[index] = { id = spec.id, label = spec.label, help = spec.help, keywords = spec.keywords, frame = built[spec.id],
            section = self.editorTotemSection }
    end
    return rows
end

function TOTEM_SECTION.Build(context)
    local function Shown() return Options:IsEditorTotem() end
    local function Chosen() return ProfileValue("totemDisplay")() or "plate" end
    local section = K.Section(context, L["TOTEMS"], { summary = function()
        for _, choice in ipairs(TOTEM_SECTION.CHOICES) do
            if choice.value == Chosen() then return choice.label end
        end
        return ""
    end })
    K.Add(context, section, Shown)
    Options.editorTotemSection = section
    local spec = TOTEM_SECTION.ROWS[1]
    local row, choice = K.DropdownRow(section, spec.label, { choices = TOTEM_SECTION.CHOICES,
        name = WidgetName("editor_totemDisplay", "Dropdown"), get = Chosen,
        set = function(value)
            -- Icon choices draw the layer's totem icon parts: one is added where there is none.
            if value == "icon" or value == "iconName" then Options:EnsureEditorTotemIcon() end
            SetProfileValue("totemDisplay")(value ~= "plate" and value or nil)
        end })
    Register(choice)
    Mark(row, Area.Option("totemDisplay"))
    K.Add(section, row)
    if not K.AttachHelp(row, spec.help) then K.Add(section, K.Help(section, spec.help)) end
    Options.editorTotemDisplay, Options.editorTotemRowFrames = choice, { totemDisplay = row }
end

-- The plate's own scale, per plate type: Studio's Plate settings row (the tree's top). Sizes belong to
-- their parts (the health bar's width and height, each text's size), so they are set there, once.
-- Under it, the selected target's highlight for this plate type and design. On the friendly tabs,
-- Friendly plates comes first.
local function BuildPlateContext(page)
    CreateContext(page, "plate", function(context)
        BuildFriendlySection(context)
        TOTEM_SECTION.Build(context)
        BuildObjectsSection(context)
        OBJECT_LOOKS.Build(context)
        -- An object type open (Objects › Type): it may hide its plates altogether (plateHidden, the type's own; Totems
        -- hide with their Display).
        local typeSection = K.Section(context, L["THIS TYPE"])
        K.Add(context, typeSection, function() return Options:IsEditorObject() and Options:EditorObjectType() ~= nil end)
        local hideRow, hide = K.CheckRow(typeSection, L["Plates"], { text = L["Hide these plates"],
            name = WidgetName("editor_plateHidden", "Checkbox"),
            get = function() return ProfileValue("plateHidden")() == true end,
            set = function(on) SetProfileValue("plateHidden")(on == true) end })
        Register(hide)
        Mark(hideRow, Area.Option("plateHidden"))
        K.AttachHelp(hideRow, L["Draws no plate for objects of this type (in every place), and keeps the game's own hidden "
            .. "while PlateSmith draws objects. The others stay."])
        K.Add(typeSection, hideRow)
        Options.editorObjectTypeSection = typeSection
        -- Corpses while Corpse plates (corpsePlates, a general setting: its home is Settings › Objects & interacting)
        -- are off: they show nowhere, so a note and a button writing that same setting.
        local function CorpsesOff()
            return Options:EditorObjectType() == "corpse" and PS.GetSettings().corpsePlates ~= true
        end
        K.Add(typeSection, K.Help(typeSection, L["Corpse plates are off, so these show nowhere."]), CorpsesOff)
        local corpseRow, corpseOn = K.ButtonRow(typeSection, L["Turn on"], 120)
        local _, setCorpses = Options.BindSetting("corpsePlates")
        corpseOn:SetScript("OnClick", function() setCorpses(true) end)
        K.Add(typeSection, corpseRow, CorpsesOff)
        K.AttachHelp(corpseRow, L["Turns on Corpse plates, the same setting as Settings › Objects & interacting › "
            .. "Corpses › Corpse plates, for every design. Dead creatures then get a plate in this style."])
        Options.editorCorpsePlatesOn = corpseOn
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
-- hidden. Every row is live: changing one makes it PlateSmith's (a changed mark, whose arrow gives it
-- back to the game); one the game ignores (View distance) is dimmed and takes no clicks, with the
-- reason under it. A dragged slider only redraws the preview; letting go writes.
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

-- The Settings kit's changed marks (UI/Layout's ChangedMark): a Stacking & distance row PlateSmith sets
-- ({ kind = "stacking", key }, or keys: a bitfield's bits, changed while PlateSmith sets any), and its
-- arrow, which gives the setting (every bit) back to the game.
local function StackingOwnedKeys(area)
    local owned = {}
    if type(area) ~= "table" or area.kind ~= "stacking" or not PS.Stacking then return owned end
    for _, key in ipairs(area.keys or { area.key }) do
        local _, source = PS.Stacking.Get(key)
        if source == "setting" then owned[#owned + 1] = key end
    end
    return owned
end
local settingsMarks = {
    State = function(area)
        local owned = #StackingOwnedKeys(area) > 0
        return owned, false, owned
    end,
    Tip = function(area)
        if type(area) ~= "table" or area.kind ~= "stacking" then return nil end
        return { L["PlateSmith sets this in this profile. The arrow gives it back to the game."] }
    end,
    Reset = function(area)
        local given = false
        for _, key in ipairs(StackingOwnedKeys(area)) do
            if PS.Stacking.Set(key, nil) then given = true end
        end
        if not given then return false end
        Options:Refresh(true)
        return true
    end,
    resetLabel = L["Give it back to the game"],
}

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
    [L["Blizzard: names only in dungeons"]] = function(profile)
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
        -- The way back from Friendly plates' Dungeons & raids link: World, with Plate settings open.
        local backRow, back = K.ButtonRow(context, L["‹ Back to World design"], 200)
        back:SetScript("OnClick", function()
            if Options:SetEditorDesign("world") then Options:SelectEditorPlate() end
        end)
        K.Add(context, backRow)
        K.AttachHelp(backRow, L["How these plates look outdoors, and Plate settings › Friendly plates: how and where they show."])
        Options.editorBlizzardNameBack = back
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
        -- Not Show as' Names only (PlateSmith's own names outdoors): Blizzard's choice for its own plates here.
        Check("restrictedFriendlyNamesOnly", L["Blizzard: names only in dungeons"], "namesOnly", L["Blizzard shows only "
            .. "the name on these plates, without their health bars. Outdoors, Plate settings › Friendly plates › Show as "
            .. "decides."])
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
DISPLAY_ROW_LABELS.blizzardName = { L["Change Blizzard's names"], L["Where"], L["Blizzard: names only in dungeons"],
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
    local state = { rows = {}, groups = {}, drag = {} }
    Options.editorStacking = state
    local function Changed() Options:Refresh(true) end
    local function StackSection(id, title, summary, visible)
        local section = SK.Section(page.columns, title, { key = "studio.settings." .. id, summary = summary })
        section.title:SetFont(SK.FONT_PATH, SK.TITLE_FONT)
        SK.Add(page.columns, section, visible)
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

    -- Blizzard's settings: what changing a row does, how many PlateSmith sets, and the reset.
    local function OwnedText()
        local count = Stacking.OwnedCount()
        if count == 0 then return L["All the game's own"] end
        return count == 1 and L["PlateSmith sets 1"] or string.format(L["PlateSmith sets %d"], count)
    end
    local blizzard = StackSection("stackingBlizzard", L["Blizzard's settings"], OwnedText)
    state.intro = SK.Add(blizzard, SK.Help(blizzard, L["Change any setting on this page and PlateSmith keeps it set "
        .. "for this profile. Settings you leave alone stay the game's own. A changed setting is marked; its arrow "
        .. "gives it back to the game."]))
    state.ownedText = OwnedText
    -- The saved record of the player's own values was lost (Stacking.OriginalsMissing).
    state.lostNote = SK.Add(blizzard, SK.Note(blizzard, L["PlateSmith has no record of your earlier settings; a "
        .. "setting given back to the game goes to Blizzard's default."]), function() return Stacking.OriginalsMissing() end)
    SK.Ink(state.lostNote.text, "sub")
    local resetRow, reset = SK.ButtonRow(blizzard, L["Reset Blizzard's stacking to game defaults"], nil, "action")
    SK.Add(blizzard, resetRow)
    state.reset = reset
    reset:SetScript("OnClick", function()
        Options:ConfirmStudioAction(L["Set every Blizzard stacking, distance, scale and fade setting to the game's "
            .. "default and give each back to the game? This clears this profile's stacking values; Revert undoes "
            .. "that until you save."], L["Reset"],
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
    local preset = StackSection("stackingPreset", L["Preset"], function()
        for _, choice in ipairs(presetChoices) do
            if choice.value == Stacking.Preset() then return choice.label end
        end
        return ""
    end, function() return HasEntries() end)
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
        local section = StackSection("stacking." .. group.id, group.label, nil, function() return HasEntries(group.id) end)
        local rows = SK.Add(section, SK.Group(section))
        state.groups[group.id] = { section = section, rows = rows }
        if group.id == "stacking" then
            -- Only where one setting stacks both (Plate arrangement); Stack plates names its units itself.
            state.sharedNote = SK.Add(section, SK.Help(section, L["Blizzard uses one stacking setting for friendly "
                .. "and enemy plates."]), function() return Stacking.MotionShared() end)
        end
    end
    local SOURCES = { setting = L["Set by PlateSmith in this profile"], client = L["The game's own setting"],
        default = L["Blizzard default"] }
    -- Why a row the game ignores is shown but cannot be changed.
    local IGNORED = { nameplateMaxDistance = L["The game keeps nameplates to a fixed range (about 60 yards) and "
        .. "ignores this setting, so PlateSmith leaves it alone."] }
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
            if entry.ignored then
                table.insert(lines, 1, { IGNORED[key] or L["The game ignores this setting."], 1, 1, 1 })
            elseif SPACING[key] and Stacking.Arrangement() == "overlapping" then
                table.insert(lines, 2, { SPACING_OFF, 1, 1, 1 })
            end
            return lines
        end)
        local record = { row = row, control = control, entry = entry }
        if entry.ignored then
            record.note = SK.Note(parent, IGNORED[key] or L["The game ignores this setting."])
            SK.Ink(record.note.text, "sub")
        else
            -- Set by PlateSmith: marked, and its arrow gives it back to the game (settingsMarks). The diamond sits
            -- in the gap before the control: left of the row it would be cut off by the page's edge.
            record.mark = SK.ChangedMark(row, { kind = "stacking", key = key }, { anchor = control })
        end
        return record
    end
    -- A bitfield's bits (Stack Nameplates' Enemy and Friendly) are one row, as Blizzard's options show
    -- them: a multi-select whose field reads the ticked bits. Each item writes only its own bit; the mark
    -- shows while PlateSmith sets either, and its arrow gives both back.
    local function MakeBitsRow(parent, bitfield, entries)
        local record = { entries = entries, bitfield = bitfield }
        local function Choices()
            local choices = {}
            for index, entry in ipairs(record.entries) do choices[index] = { value = entry.key, label = entry.bitLabel } end
            return choices
        end
        local label = entries[1].bitfieldLabel or bitfield
        local row, control = SK.DropdownRow(parent, label, { multi = true, choices = Choices,
            name = WidgetName("stacking_" .. bitfield, "Dropdown"),
            get = function()
                local ticked = {}
                for _, entry in ipairs(record.entries) do ticked[entry.key] = Value(entry.key) == 1 end
                return ticked
            end,
            set = function(key, ticked)
                local ok = Stacking.Set(key, ticked and 1 or 0)
                Changed()
                return ok
            end })
        Wrap(row)
        local words = {}
        for _, entry in ipairs(entries) do words[#words + 1] = entry.bitLabel end
        row.kitSearchExtra = table.concat(words, ", ")
        LiveTip(control, label, function()
            local lines = {}
            for _, entry in ipairs(record.entries) do
                local _, source = Stacking.Get(entry.key)
                lines[#lines + 1] = { string.format(L["%s: %s"], entry.bitLabel, SOURCES[source] or ""), 1, 0.82, 0.45 }
            end
            lines[#lines + 1] = { bitfield, 0.6, 0.6, 0.6 }
            return lines
        end)
        record.row, record.control = row, control
        record.mark = SK.ChangedMark(row, function()
            local keys = {}
            for index, entry in ipairs(record.entries) do keys[index] = entry.key end
            return { kind = "stacking", keys = keys }
        end, { anchor = control })
        return record
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
            if record.note then record.note:Hide() end
            bound["stacking." .. key] = nil
        end
        local bits = {}
        for _, entry in ipairs(catalogue) do
            if entry.bitfield then
                bits[entry.bitfield] = bits[entry.bitfield] or {}
                table.insert(bits[entry.bitfield], entry)
            end
        end
        for _, entry in ipairs(catalogue) do
            local holder = state.groups[entry.group]
            local key = entry.bitfield or entry.key
            if holder and not (state.rows[key] and state.rows[key].live) then
                local record = state.rows[key]
                if record and entry.bitfield then record.entries = bits[key] end
                record = record or (entry.bitfield and MakeBitsRow(holder.rows, key, bits[key]) or MakeRow(holder.rows, entry))
                state.rows[key], record.live = record, true
                SK.Add(holder.rows, record.row)
                if record.note then SK.Add(holder.rows, record.note) end
                bound["stacking." .. key] = record.control
            end
        end
    end
    state.SyncRows = SyncRows

    -- PlateSmith's own options. Target and focus on top move only PlateSmith's frames; frame size and
    -- combat stacking change Blizzard's plates, and are off until ticked.
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
    local preview = StackSection("stackingPreview", L["Preview"])
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
    -- A setting changed outside PlateSmith (Blizzard's Options, another addon) is checked when the page opens,
    -- as a client may not say (Stacking.LiveChanged); the page then shows the live values.
    page:HookScript("OnShow", function() Stacking.LiveChanged() end)
    -- The CVar rows are not Options.controls (a new catalogue replaces them): refreshed here, and on their own
    -- when a CVar changes outside PlateSmith (Options:RefreshEditorStacking).
    function state.Refresh()
        SyncRows()
        for _, record in pairs(state.rows) do
            if record.live then
                record.control:Refresh()
                local value = record.entry and record.control.valueText
                if value then
                    local _, source = Stacking.Get(record.entry.key)
                    SK.Ink(value, source == "setting" and "value" or "muted")
                end
                if record.mark then
                    record.mark:Refresh()
                    -- Over a check row's label click area, so the arrow takes its own clicks.
                    if record.mark.reset then record.mark.reset:SetFrameLevel(record.row:GetFrameLevel() + 2) end
                end
                -- The row carries its own dimming, so it stays dimmed when the settings search lends it out.
                if record.entry and record.entry.ignored then
                    SetAvailable(record.control, false)
                    record.row:SetAlpha(DIMMED_ALPHA)
                end
            end
        end
        local sizable = Stacking.SizeSupport()
        SetAvailable(state.matchFrame, sizable)
        state.matchFrame.label:SetAlpha(sizable and 1 or 0.45)
        state.sizeText.text:SetText(FrameSizeText())
        local combatState = CombatState()
        SetAvailable(combat, combatState ~= "refused")
        combat.label:SetAlpha(combatState ~= "refused" and 1 or 0.45)
        state.combatNote.text:SetText(COMBAT_TIPS[combatState] or "")
    end
    Register({ Refresh = state.Refresh })
    -- Its own control, so a row that fails to refresh cannot leave the diagram as it was.
    Register({ Refresh = function() state.DrawPreview() end })
end

-- Blizzard's stacking settings may have changed outside PlateSmith (Stacking.LiveChanged, once its pass ran):
-- Settings › Stacking & distance, while it shows, reads them again. Nothing else in Studio depends on them.
function Options:RefreshEditorStacking()
    local state = self.editorStacking
    local page = self.editorInspectorPages and self.editorInspectorPages.stacking
    if not (state and state.Refresh and page and page:IsVisible()) then return end
    self.refreshing = true
    local ok, failure = pcall(state.Refresh)
    if ok then ok, failure = pcall(state.DrawPreview) end
    self.refreshing = false
    if not ok then PS.Chat.ReportError("stacking refresh", failure) end
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
        marks = settingsMarks,
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
    -- foldKey: the section's fold state key (default "studio.settings.<id>").
    local function Section(panel, id, title, summary, foldKey)
        local section = SK.Section(panel.columns, title, { key = foldKey or ("studio.settings." .. id), summary = summary })
        section.title:SetFont(SK.FONT_PATH, SK.TITLE_FONT)
        SK.Add(panel.columns, section)
        return section
    end
    -- Modules' pages (Studio/Modules.lua) are built with the same pieces.
    Options.settingsPageKit = { Page = Page, Section = Section, Bind = Bind }
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
    -- A list (Hidden auras, My media) as a row per entry: its line, and its own Remove button at the row's end, so an
    -- entry goes without typing it again. The rows sit where the list was made in section's flow and are made as the list
    -- grows. entries(): the list now; describe(entry): its line; remove(entry): what Remove does. Returns the list:
    -- Refresh() fills the rows, rows[i].text and rows[i].remove.
    local function ListRows(section, entries, describe, remove)
        local group = SK.Add(section, SK.Group(section))
        local list = { group = group, rows = {}, count = 0 }
        function list.Refresh()
            local items = entries()
            for index, item in ipairs(items) do
                local row = list.rows[index]
                if not row then
                    row = SK.Row(group, nil)
                    local button = CreateStudioButton(row, L["Remove"], 90, SK.BUTTON_H)
                    button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                    button:SetScript("OnClick", function(instance) remove(instance.entry) end)
                    local text = SK.Text(row, "", "label")
                    text:SetPoint("LEFT", row, "LEFT", 0, 0)
                    text:SetPoint("RIGHT", button, "LEFT", -SK.CONTROL_GAP, 0)
                    text:SetJustifyH("LEFT")
                    if text.SetWordWrap then text:SetWordWrap(true) end
                    function row:Measure()
                        local width = math.max(1, (self:GetWidth() or SK.WIDTH) - 90 - SK.CONTROL_GAP)
                        local height = math.max(SK.ROW_H, SK.TextHeight(text, width))
                        self:SetHeight(height)
                        return height
                    end
                    row.text, row.remove = text, button
                    local position = index
                    SK.Add(group, row, function() return position <= list.count end)
                    list.rows[index] = row
                end
                row.text:SetText(describe(item))
                row.remove.entry = item
            end
            list.count = #items
        end
        return list
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
        Choice(plates, "plate.mode", "mode", L["Who draws the plates"], model.modeChoices):GetParent().kitSearchKeywords =
            L["enable disable turn off blizzard"]
        -- How friendly plates show (Show as, Show in) is set per plate type in Studio.
        local friendlyRow, friendlyLink = SK.ButtonRow(plates, L["Friendly plates in Studio › Plate settings"])
        SK.Add(plates, friendlyRow)
        friendlyLink:SetScript("OnClick", function() Options.settingsSearch.RevealFriendlyPlates() end)
        SK.Add(plates, SK.ControlHelp(plates, L["Players and Friendly NPCs each choose names only, full plates or "
            .. "Blizzard's plates there, and where they show."]))
        Options.editorFriendlyPlatesLink = friendlyLink
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
        -- What Blizzard, with PlateSmith extras adds to Blizzard's plates (Studio/Extras.lua), its one home.
        Options.BuildExtrasSettings(SK, Section(plate, "extras", L["Extras on Blizzard's plates"], Options.ExtrasSummary),
            Bind)
        -- Clicking (Nameplates/ClickThrough.lua), the home: a row per kind of plate, where this client can set it
        -- (friendly players through the game's names-only switch; NPCs and enemies through the client's click-through
        -- switch or the hit-test insets; your own plate through the switch only). Players' and Friendly NPCs' Friendly
        -- plates have a Clicks row for the same setting.
        do
            local ClickThrough = PS.ClickThrough
            local clickRows = { { key = "clickFriendlyPlayer", label = L["Friendly players"] },
                { key = "clickFriendlyNPC", label = L["Friendly NPCs"] }, { key = "clickEnemy", label = L["Enemies"] },
                { key = "clickSelf", label = L["Your own plate"] } }
            local clicking = Section(plate, "clicking", L["Clicking"], function()
                if not ClickThrough.AnySupported() then return L["Not on this game client"] end
                local settings, through = PS.GetSettings(), 0
                for _, entry in ipairs(clickRows) do
                    local value = entry.key == "clickFriendlyPlayer" and ClickThrough.PlayersValue(settings)
                        or settings[entry.key]
                    if ClickThrough.Supported(entry.key) and value ~= "clickable" and value ~= "game" then
                        through = through + 1
                    end
                end
                if through == 0 then return L["Clickable"] end
                return string.format(L["Click through: %d"], through)
            end)
            clicking.kitSearchKeywords = L["clickthrough click through mouse"]
            for _, entry in ipairs(clickRows) do
                local function Shown() return ClickThrough.Supported(entry.key) end
                local row, dropdown = ClickDropdownRow(SK, clicking, entry.key, entry.label,
                    WidgetName("editor_" .. entry.key, "Dropdown"))
                SK.Add(clicking, row, Shown)
                Bind("plate." .. entry.key, dropdown)
                if CLICKS.help[entry.key] then SK.Add(clicking, SK.ControlHelp(clicking, CLICKS.help[entry.key]), Shown) end
            end
            SK.Add(clicking, SK.Help(clicking, L["Each covers every plate of its kind, not one plate. Click through is put "
                .. "back to the game's own when you choose Clickable, turn PlateSmith off or log out; in combat the change "
                .. "waits for combat to end."]), ClickThrough.AnySupported)
            SK.Add(clicking, SK.Help(clicking, L["This game client has no way to make nameplates click through, "
                .. "so there is nothing to set here."]), function() return not ClickThrough.AnySupported() end)
        end
        local names = Section(plate, "names", L["Names"])
        Check(names, "plate.showPlayerSurnames", "showPlayerSurnames", L["Show player surnames"])
        -- Its home (the game's own name settings); Players › Plate settings › Friendly plates reads it and links here.
        Check(names, "plate.hideUnstyledFriendlyNames", "hideUnstyledFriendlyNames", L["Hide unstyled names"])
        SK.Add(names, SK.ControlHelp(names, HIDE_UNSTYLED_HELP))
        SK.Add(names, SK.ControlHelp(names, HIDE_UNSTYLED_DETAIL))
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
        -- The target highlight (Plate settings, per plate type) and Threat colours (Modules › Threat) have their homes
        -- elsewhere; Settings search finds both there.
        local fading = Section(plate, "fading", L["Fading"])
        fading.kitSearchKeywords = L["alpha opacity transparent"]
        FadeRows(SK, fading, Bind, "fadeNonTarget", L["Fade non-targets"], L["While you have a target, the other enemy plates "
            .. "fade to this opacity. It adds a rule to each part they show; Studio's Rules edit it per part."])
        FadeRows(SK, fading, Bind, "fadeOutOfRange", L["Fade out of range"], L["Enemy plates beyond your spells' reach (from your "
            .. "spellbook) fade. Where the game withholds the range the plate stays as it is."])
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
        -- The companion's own options (audit #12) are its page under Modules.
        SK.Add(quests, SK.ControlHelp(quests, L["With the PlateSmith_QuestieDB companion installed, its own options "
            .. "(which mobs it marks for your quests) are in Studio › Settings › Modules › QuestieDB."]))
        -- Optional parts: shortcuts over the tree's eyes (STANDARDS 2a rule 3: they write the eyes, nothing of their own);
        -- the summary counts those shown on at least one plate type. A part off the plate on every plate type (deleted,
        -- or never added) has no eye to set: its row is an Add that goes + Add's way, on its plate type in Studio.
        local shows = Section(plate, "showOnPlates", L["Optional parts"], function()
            local on = 0
            for _, entry in ipairs(SHOW_ON_PLATES) do
                local state = PS.GetPartShownState(entry.key)
                if state == "all" or state == "some" then on = on + 1 end
            end
            return string.format(L["%d of %d shown"], on, #SHOW_ON_PLATES)
        end)
        shows.kitSearchKeywords = L["show on plates hide part eye"]
        Options.editorOptionalPartAdds = {}
        for _, entry in ipairs(SHOW_ON_PLATES) do
            -- Off the plate everywhere it could show: no live layout has it, and the plate type's World holds it removed.
            local function Addable()
                if PS.GetPartShownState(entry.key) ~= nil then return false end
                local world = PS.GetPlateProfileSettings(entry.plateType)
                for _, field in ipairs({ "layout", "namesLayout" }) do
                    local position = world and type(world[field]) == "table" and world[field][entry.part]
                    if type(position) == "table" and position.removed then return true end
                end
                return false
            end
            local get, set, mixed = Options.BindPartSwitch(entry.key)
            local row, checkbox = SK.CheckRow(shows, nil, { text = entry.label, get = get, set = set, mixed = mixed,
                mixedTip = L["Shown on some plate types"], name = WidgetName("editor_" .. entry.key, "Checkbox") })
            SK.Add(shows, row, function() return not Addable() end)
            SK.AttachHelp(row, entry.where and string.format(L["Shows or hides it on every plate type that has it (%s). "
                .. "Studio's eye sets it per plate type."], entry.where)
                or L["Shows or hides it on every plate type. Studio's eye sets it per plate type."])
            -- No plate type draws it now (their Show as is Blizzard's): nothing to show or hide.
            local refresh = checkbox.Refresh
            function checkbox:Refresh(...)
                refresh(self, ...)
                SetAvailable(self, PS.GetPartShownState(entry.key) ~= nil)
            end
            Bind("plate." .. entry.key, checkbox)
            local addRow = SK.ButtonsRow(shows, entry.label, { { L["+ Add"], 90, function()
                Options:RestoreOptionalPart(entry.part, entry.plateType)
            end } })
            SK.Add(shows, addRow, Addable)
            SK.AttachHelp(addRow, string.format(L["Not on any plate. Opens Studio on %s and adds it there, as + Add does; "
                .. "then its eye shows or hides it."], Options:EditorPlateLabel(entry.plateType)))
            Options.editorOptionalPartAdds[entry.key] = addRow.buttons[1]
        end
    end)

    -- Where plates show (Studio/Visibility.lua builds the section).
    Define("visibility", function()
        local visibility = Page("visibility")
        Options.BuildPlateVisibilitySettings(SK, Section(visibility, "visibility", L["Where plates show"],
            Options.PlateVisibilitySummary), Bind)
    end)

    -- Objects & interacting: the home of the object settings (the Objects tab's Plate settings links here) and of the
    -- game's interact key settings (Nameplates/Interaction.lua: a row only where the client has its CVar).
    Define("objects", function()
        local Interaction = PS.Interaction
        local objects = Page("objects")
        local drawChoices = {
            { value = "platesmith", label = L["PlateSmith"], help = L["Drawn in the Objects tab's design."] },
            { value = "blizzard", label = L["Blizzard's"], help = L["The game's own object plate, untouched."] },
        }
        local plates = Section(objects, "objectPlates", L["Object plates"], function()
            return LabelOf(drawChoices, PS.GetSettings().objectPlates)
        end)
        Choice(plates, "objects.objectPlates", "objectPlates", L["Drawn by"], drawChoices, L["Who draws the plates the game "
            .. "gives objects (books, chests, ore, quest objects). PlateSmith draws them in Studio's Objects tab; "
            .. "Blizzard's leaves the game's own plate untouched. Which objects get a plate is the game's choice."])
        -- Object looks (Fade objects you can't use yet, When out of reach) are appearance: their home is Studio ›
        -- Objects › Plate settings › Object looks, so here each is a line reading the setting that opens it there.
        local looks = Options.editorObjectLookChoices
        -- name: the row's name for search; text(): the button's words, with the setting's value.
        local function LookLink(section, id, name, text)
            local row, link = SK.ButtonRow(section, text(), 340)
            row.kitSearchLabel = name
            SK.Add(section, row)
            link:SetScript("OnClick", function() Options.settingsSearch.RevealObjectLooks(id) end)
            Register({ Refresh = function() link.label:SetText(text()) end })
            Options.editorObjectLookLinks = Options.editorObjectLookLinks or {}
            Options.editorObjectLookLinks[id] = link
            return row, link
        end
        LookLink(plates, "objectFadeUnable", L["Fade objects you can't use yet"], function()
            return string.format(L["Fade objects you can't use yet: %s, in Studio › Objects"],
                PS.GetSettings().objectFadeUnable == true and L["On"] or L["Off"])
        end)
        SK.Add(plates, SK.ControlHelp(plates, L["Opens Studio › Objects › Plate settings › Object looks, its home. "
            .. "Fades an object's plate while the game's icon says you can't use it yet."]))
        -- Pointing at the plate's name (Nameplates/ObjectHover.lua): the player's own, not shared in Blueprints.
        local hover = Section(objects, "objectHover", L["When you point at an object's plate"])
        Check(hover, "objects.objectHoverCursor", "objectHoverCursor", L["Show the game's cursor"])
        SK.Add(hover, SK.ControlHelp(hover, L["Pointing at an object's name on its plate shows the game's own cursor for "
            .. "it, as over the object: gather, mine, read, loot, or greyed when it is out of reach or you can't use it "
            .. "yet. Clicking and turning the camera work as before. Not in combat. Not shared in Blueprints."]))
        Check(hover, "objects.objectHoverTooltip", "objectHoverTooltip", L["Show a tooltip"])
        SK.Add(hover, SK.ControlHelp(hover, L["Pointing at an object's name on its plate shows a small tooltip: its "
            .. "name, its type and, once one like it has been hovered in the world, what it needs (the Status text's "
            .. "line). Not in combat. Not shared in Blueprints."]))
        -- Corpse plates (Nameplates/ActionIcon.lua's IsCorpse): the player's own, not shared in Blueprints.
        local function CorpseSummary()
            local settings = PS.GetSettings()
            return settings.corpsePlates == true and L["On"] or L["Off"]
        end
        local corpses = Section(objects, "corpsePlates", L["Corpses"], CorpseSummary)
        Check(corpses, "objects.corpsePlates", "corpsePlates", L["Corpse plates"]):GetParent().kitSearchKeywords =
            L["loot skin dead body corpse"]
        SK.Add(corpses, SK.ControlHelp(corpses, L["Dead creatures get a simple plate: their name in a box, with the "
            .. "loot or skinning icon when there is something to take. Off: no plate."]))
        SK.Add(corpses, SK.ControlHelp(corpses, L["Style it in Studio › Objects › Type › Corpses. Clicking still loots. "
            .. "It turns on two game settings it needs, Interact key target and Plate on it (below); when it is off, they "
            .. "go back to yours."]))
        local function CorpsesOn() return PS.GetSettings().corpsePlates == true end
        -- Corpse plates hold Interact key target and Plate on it On (Interaction.Forced); one turned off elsewhere since
        -- (another addon, the game's options) is followed, so a note and a button take them back.
        local function NeedsShown() return CorpsesOn() and Interaction.CorpseNeeds() ~= nil end
        local note = SK.Add(corpses, SK.Note(corpses, L["Another addon turned off a setting corpses need."]), NeedsShown)
        SK.Ink(note.text, "sub")
        local needsRow, needsButton = SK.ButtonRow(corpses, L["Turn them back on"], 180)
        needsButton:SetScript("OnClick", function()
            for _, key in ipairs(Interaction.CORPSE_NEEDS) do Interaction.TakeBack(key) end
            Interaction.Apply()
            Options:Refresh(true)
        end)
        SK.Add(corpses, needsRow, NeedsShown)
        -- Out of reach (ActionIcon.Cue): a look, shared in Blueprints, set in Studio › Objects › Plate settings.
        local reach = Section(objects, "interactRangeCue", L["When out of reach"], function()
            return looks.CueLabel(PS.GetSettings().interactRangeCue)
        end)
        LookLink(reach, "interactRangeCue", L["Show it"], function()
            return string.format(L["Show it: %s, in Studio › Objects"], looks.CueLabel(PS.GetSettings().interactRangeCue))
        end)
        SK.Add(reach, SK.ControlHelp(reach, L["Opens Studio › Objects › Plate settings › Object looks, its home: how an "
            .. "object, corpse or Friendly NPC with an Action icon shows that the game says it is out of reach (Game's icon "
            .. "only, Dim the plate or Grey the name)."]))
        -- The interact key's rows in Interaction.SWITCHES' order, each with Game's setting (writes nothing) first.
        local game = { value = "game", label = L["Game's setting"], help = L["PlateSmith leaves it as the game has it."] }
        local onOff = { game, { value = "on", label = L["On"] }, { value = "off", label = L["Off"] } }
        local range = { game }
        for _, yards in ipairs({ "10", "15", "20", "30", "45", "60" }) do
            range[#range + 1] = { value = yards, label = string.format(L["%s yards"], yards) }
        end
        local rows = {
            { key = "interactTargeting", label = L["Interact key target"], choices = onOff, help = L["Objects, corpses "
                .. "and NPCs near you become your interact key's target, so the key loots, gathers or talks without "
                .. "clicking. On is always (the game's 3), Off is off (0)."], keywords = L["softinteract soft interact loot"] },
            { key = "interactRange", label = L["Range"], choices = range, help = L["How far the interact key looks for "
                .. "a target. Forever appears to drop the target past about 15 yards whatever this says."] },
            { key = "interactArc", label = L["Direction"], help = L["Where it looks: only straight ahead, anywhere in "
                .. "front of you, or all around you."], choices = { game, { value = "ahead", label = L["Straight ahead"] },
                { value = "front", label = L["In front"] }, { value = "around", label = L["All around"] } } },
            { key = "interactReach", label = L["Out of reach"], help = L["Whether it picks only what you can reach "
                .. "from where you stand, or also what is out of reach (you then walk up to use it)."], choices = { game,
                { value = "within", label = L["Only within reach"] }, { value = "beyond", label = L["Out of reach too"] } } },
            { key = "interactNameplate", label = L["Plate on it"], choices = onOff, help = L["Shows a plate for the "
                .. "object, corpse or NPC your interact key would use."] },
            { key = "interactIcons", label = L["Icon over it"], choices = onOff, help = L["The game's icon over your "
                .. "interact key's target (loot, talk, gather...)."] },
            { key = "interactObjectIcons", label = L["Icons on objects too"], choices = onOff, help = L["Lets the game "
                .. "show its interact icon on objects too, not just creatures."] },
            { key = "interactMinorIcons", label = L["Icons on minor targets"], choices = onOff, help = L["Lets the game "
                .. "show its interact icon on targets it ranks as minor too, not just the one your key would use."] },
        }
        Options.editorInteractRows = rows
        local interact = Section(objects, "interactKey", L["Interact key"], function()
            if not Interaction.AnySupported() then return L["Not on this game client"] end
            local settings, set = PS.GetSettings(), 0
            for _, entry in ipairs(rows) do
                if Interaction.Supported(entry.key) and (settings[entry.key] or "game") ~= "game" then set = set + 1 end
            end
            if set == 0 then return L["Game's settings"] end
            return string.format(L["Set by PlateSmith: %d"], set)
        end)
        SK.Add(interact, SK.Help(interact, L["The game's own settings: they pick the nearest object, corpse or NPC for "
            .. "your interact key. They are shared with other addons such as Loot Sparkles, kept by this profile and not "
            .. "shared in Blueprints. Game's setting leaves one alone; if another addon changes it after PlateSmith, "
            .. "PlateSmith follows that instead of setting it back."]), Interaction.AnySupported)
        for _, entry in ipairs(rows) do
            local function Shown() return Interaction.Supported(entry.key) end
            local get, set = Options.BindSetting(entry.key)
            -- A pick (the same one too) takes the CVar back from an outside change (Interaction.TakeBack).
            local function Pick(value)
                Interaction.TakeBack(entry.key)
                local result = set(value)
                Interaction.Apply()
                Options:Refresh(true)
                return result
            end
            -- Held On by Corpse plates: reads On, greyed, with the reason under it (the player's choice is kept).
            local function Forced() return Interaction.Forced(entry.key) end
            local function Current()
                if Forced() then return "on" end
                return get()
            end
            local row, dropdown = SK.DropdownRow(interact, entry.label, { choices = entry.choices, get = Current,
                set = Pick, name = WidgetName("editor_" .. entry.key, "Dropdown") })
            row.kitSearchKeywords = entry.keywords
            local refresh = dropdown.Refresh
            function dropdown:Refresh()
                refresh(self)
                local locked = Forced()
                if self.SetEnabled then self:SetEnabled(not locked) end
                self:SetAlpha(locked and 0.5 or 1)
            end
            SK.Add(interact, row, Shown)
            -- (The help first: it becomes the row's "?" only while it follows the row.)
            SK.Add(interact, SK.ControlHelp(interact, entry.help), Shown)
            local held = SK.Add(interact, SK.Note(interact, L["Kept On by Corpse plates."]),
                function() return Shown() and Forced() end)
            SK.Ink(held.text, "sub")
            -- While PlateSmith follows someone else's change, the row's choice is not what the game holds: said here.
            local following = SK.Add(interact, SK.Note(interact, L["Changed by another addon. Pick a choice to set it "
                .. "again."]), function() return Shown() and not Forced() and Interaction.Following(entry.key) ~= nil end)
            SK.Ink(following.text, "sub")
            Bind("objects." .. entry.key, dropdown)
        end
        SK.Add(interact, SK.Help(interact, L["This game client has none of the game's interact key settings, so there is "
            .. "nothing to set here."]), function() return not Interaction.AnySupported() end)
    end)

    Define("stacking", function()
        BuildStackingPage(SK, Page, Bind)
    end)

    -- Aura defaults.
    Define("auras", function()
        local auras = Page("auras",
            L["Select Buffs or Debuffs in the Studio tree to set how many icons show, their size and which way they grow."])
        -- Whose auras show is each design's own (the Buffs' and Debuffs' Source in the inspector): a line says what the
        -- designs use, not a second control.
        local function SourceLine(section, key, label)
            local row = SK.Row(section, label)
            row.value = SK.Text(row, "", "label")
            row.value:SetPoint("LEFT", row, "LEFT", SK.CONTROL_X, 0)
            SK.Add(section, row, function()
                row.value:SetText(Options.AuraSourceSummary(key))
                return true
            end)
            SK.AttachHelp(row, L["Each design picks its own: select Buffs or Debuffs in the Studio tree (Display › Source)."])
            Options.editorAuraSourceLines = Options.editorAuraSourceLines or {}
            Options.editorAuraSourceLines[key] = row
        end
        local buffs = Section(auras, "buffs", L["Buffs"])
        PartCheck(buffs, "auras.showBuffs", "showBuffs", L["Show buffs"])
        SourceLine(buffs, "buffSource", L["Buff source"])
        local debuffs = Section(auras, "debuffs", L["Debuffs"])
        PartCheck(debuffs, "auras.showDebuffs", "showDebuffs", L["Show debuffs"])
        SourceLine(debuffs, "debuffSource", L["Debuff source"])
    end)

    -- Hidden auras (Schema's HIDDEN_AURAS): account state saved at once, never in a profile or a Blueprint, so it needs
    -- no Save and sits under Yours. Its one home: the aura rows' Display links here.
    Define("hiddenAuras", function()
        local page = Page("hiddenAuras")
        local H = PS.ProfileSchema.HIDDEN_AURAS
        local WHO_LABELS = { enemy = L["Enemies"], enemyPlayer = L["Enemy players"], friendlyPlayer = L["Players"],
            friendlyNPC = L["Friendly NPCs"] }
        local function List() return PS.GetState().hiddenAuras or {} end
        local hidden = Section(page, "hiddenAuras", L["Hidden auras"], function()
            return string.format(L["%d of %d"], #List(), H.MAX)
        end)
        -- Other names a player may search for it by.
        hidden.kitSearchKeywords = L["blacklist hide filter ignore buff debuff spell"]
        SK.Add(hidden, SK.Help(hidden, L["Buffs and debuffs no plate shows, by spell ID or name, for the kinds of plate "
            .. "you tick. For you on every profile, kept at once; never in a Blueprint. In dungeons & raids, and "
            .. "wherever the game keeps an aura's ID and name from addons, the game's own aura icons show every aura."]))
        local who = { enemy = true, enemyPlayer = true, friendlyPlayer = true, friendlyNPC = true }
        local whoBoxes, status, Refresh = {}, nil, nil
        local function Describe(entry)
            local names = {}
            for _, key in ipairs(H.WHO) do
                if not entry.who or entry.who[key] then names[#names + 1] = WHO_LABELS[key] end
            end
            local what = entry.id and string.format(L["Spell %d"], entry.id) or entry.name
            return string.format(L["%s: %s"], what, entry.who and table.concat(names, ", ") or L["every plate"])
        end
        -- The list, a row per aura with its own Remove; "None yet." while it is empty.
        local rows = ListRows(hidden, List, Describe, function(entry)
            local text = entry.id and tostring(entry.id) or entry.name
            local ok = PS.RemoveHiddenAura(text)
            Refresh(ok and string.format(L["Showing %s again."], text) or nil, not ok)
        end)
        local listText = SK.Add(hidden, SK.Help(hidden, L["None yet."]), function() return #List() == 0 end)
        local function ShowList() rows.Refresh() end
        local textRow = SK.Add(hidden, SK.Row(hidden, L["Spell ID or name"]))
        local textBox = SK.ValueBox(textRow, SK.CONTROL_X, SK.WIDTH - SK.CONTROL_X, function(box)
            -- One already in the list ticks its plates, to change them.
            local kind, value = H.Parse(box:GetText())
            local key = kind and H.Key(kind == "id" and { id = value } or { name = value })
            for _, entry in ipairs(List()) do
                if key and H.Key(entry) == key then
                    for _, plate in ipairs(H.WHO) do who[plate] = not entry.who or entry.who[plate] == true end
                    for _, box2 in pairs(whoBoxes) do if box2.Refresh then box2:Refresh() end end
                end
            end
        end, H.NAME_LENGTH)
        -- The kinds of plate the typed aura is hidden on, under their heading.
        SK.Add(hidden, SK.SubHeader(hidden, L["Hide on:"]))
        for _, plate in ipairs(H.WHO) do
            local row, box = SK.CheckRow(hidden, nil, { text = WHO_LABELS[plate],
                name = WidgetName("hiddenAuras_" .. plate, "Checkbox"),
                get = function() return who[plate] end, set = function(on) who[plate] = on and true or false end })
            SK.Add(hidden, row)
            whoBoxes[plate] = Register(box)
        end
        Refresh = function(message, error)
            ShowList()
            status.text:SetText(message or "")
            SK.Ink(status.text, error and "error" or "muted")
            Options:LayoutEditorSettingsPanels()
        end
        local buttonsRow = SK.ButtonsRow(hidden, nil, {
            { L["Add or update"], 130, function()
                local text = (textBox:GetText() or ""):match("^%s*(.-)%s*$")
                local ok, result = PS.SetHiddenAura(text, who)
                if ok then
                    Refresh(string.format(result and L["Updated %s."] or L["Hiding %s."], text))
                else
                    Refresh(result, true)
                end
            end },
        })
        SK.Add(hidden, buttonsRow)
        status = SK.Add(hidden, SK.Help(hidden, ""))
        Options.editorHiddenAuraControls = { text = textBox, list = listText, rows = rows.rows, status = status,
            who = whoBoxes, add = buttonsRow.buttons[1] }
        Register({ Refresh = ShowList })
    end)

    -- Player colours (key "relations").
    Define("relations", function()
        local relations = Page("relations", L["A PvP-flagged ally's colour goes on a full plate's health bar, or on "
            .. "the name of a names-only plate in place of its social colour. Icons use Blizzard's faction art. These "
            .. "apply outdoors; Blizzard protects friendly plates in dungeons and raids. Class colours show where "
            .. "Studio's Health bar or Name has Class colour ticked (Players and Enemy players)."])
        local icons = Section(relations, "relationIcons", L["Icons"])
        Check(icons, "relations.showGroupIcon", "showGroupIcon", L["Show icon above group members"])
        Check(icons, "relations.showGuildIcon", "showGuildIcon", L["Show icon above guild members"])
        local colours = Section(relations, "relationColours", L["Social colours"])
        -- The social switch's one home.
        Check(colours, "relations.friendlyRelationshipColours", "friendlyRelationshipColours",
            L["Group, guild & friends come before class colours"])
        SK.Add(colours, SK.ControlHelp(colours, L["On: a friendly player in your group or guild, a friend or a recent "
            .. "ally takes its colour below on its name and health bar, over its class colour. Off: friendly players "
            .. "take their class colour where Studio's Players › Health bar or Name has Class colour ticked (as "
            .. "Blizzard's plates draw them), else blue."]))
        Colour(colours, "relations.group", "group", L["Group members"])
        Colour(colours, "relations.guild", "guild", L["Guild members"])
        Colour(colours, "relations.friend", "friend", L["Friends"])
        Colour(colours, "relations.recent", "recent", L["Recent allies"])
        local pvp = Section(relations, "relationPvp", L["PvP"], function()
            return LabelOf(model.friendlyPvpChoices, PS.GetSettings().friendlyPvpStyle)
        end)
        Choice(pvp, "relations.friendlyPvpStyle", "friendlyPvpStyle", L["PvP-flagged players"], model.friendlyPvpChoices)
        Choice(pvp, "relations.friendlyPvpColourOn", "friendlyPvpColourOn", L["PvP colour goes on"],
            model.friendlyPvpPlaceChoices)
        Colour(pvp, "relations.pvp", "pvp", L["PvP colour"])
        Options.BuildClassColourSettings(SK, Section(relations, "classColours", L["Class colours"], function()
            local own = PS.GetSettings().classColours
            local changed = 0
            for _ in pairs(type(own) == "table" and own or {}) do changed = changed + 1 end
            if changed == 0 then return L["Blizzard's"] end
            return string.format(L["%d changed"], changed)
        end), Bind)
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
        SK.Add(dungeon, SK.ControlHelp(dungeon, L["Tries to draw PlateSmith's own plate over Blizzard's friendly plates "
            .. "in dungeons & raids. The game usually blocks it."]))
        SK.Add(dungeon, SK.ControlHelp(dungeon, L["In a dungeon, /ps diagnose (dungeonFriendlyOverlay) shows how many "
            .. "friendly plates it tracked and how many it showed on. While it is on, the Players and Friendly NPCs "
            .. "Dungeons & raids designs show the overlay's parts instead of Blizzard's name; turn it off to set "
            .. "Blizzard's names there."]))
    end)

    -- Profiles (Settings/ProfilesPage.lua builds the page; Game Options' Profiles page opens it).
    Define("profiles", function() Options:BuildProfileSettings(SK, Page, Section) end)

    -- My media: the player's own picture files for Image parts (Core/Media.lua's My media), account state saved at once,
    -- never in a profile or a Blueprint: a design names them, and whoever imports it adds the same name to see them.
    Define("media", function()
        local Media = PS.Media
        local media = Page("media", L["Put your own .tga, .blp or .png files in a folder of your own inside "
            .. "Interface\\AddOns\\ (for example Interface\\AddOns\\MyPictures\\), name each here, then pick it in an "
            .. "Image part's Picture (From: Mine). A Blueprint carries only the name: whoever imports it adds the same "
            .. "name for the picture to show. The game cannot tell PlateSmith whether a file exists, so check it in "
            .. "the preview here."])
        local function Names()
            local names = {}
            for name in pairs(Media.MyMedia()) do names[#names + 1] = name end
            table.sort(names)
            return names
        end
        local list = Section(media, "mediaList", L["Your pictures"], function()
            return string.format(L["%d of %d"], #Names(), Media.MEDIA_MAX)
        end)
        -- A row per picture with its own Remove; "None yet." while there are none.
        local status, Refresh
        local rows = ListRows(list, Names, function(name)
            return string.format(L["%s: %s"], name, Media.MyMedia()[name] or "")
        end, function(name)
            local ok = PS.RemoveMyMedia(name)
            Refresh(ok and string.format(L["Removed %s. Parts naming it draw nothing."], name) or nil, not ok)
        end)
        local listText = SK.Add(list, SK.Help(list, L["None yet."]), function() return #Names() == 0 end)
        local edit = Section(media, "mediaEdit", L["Add or change a picture"])
        local nameRow = SK.Add(edit, SK.Row(edit, L["Name"]))
        local pathRow = SK.Add(edit, SK.Row(edit, L["File"]))
        local previewRow = SK.Add(edit, SK.Row(edit, L["Preview"]))
        local thumb = previewRow:CreateTexture(nil, "ARTWORK")
        thumb:SetSize(SK.CONTROL_H, SK.CONTROL_H)
        thumb:SetPoint("LEFT", previewRow, "LEFT", SK.CONTROL_X, 0)
        local pathBox
        -- The typed file, drawn as an image would draw it (a file that does not exist draws nothing).
        local function ShowThumb()
            local path = Media.MediaPath(pathBox:GetText())
            thumb:SetShown(path ~= nil and pcall(thumb.SetTexture, thumb, path))
        end
        local nameBox = SK.ValueBox(nameRow, SK.CONTROL_X, SK.WIDTH - SK.CONTROL_X, function(box)
            -- A name already in the list brings its file back to change it.
            local path = Media.MyMedia()[(box:GetText() or ""):match("^%s*(.-)%s*$")]
            if path then
                pathBox:SetText(path)
                ShowThumb()
            end
        end, Media.MEDIA_NAME_LENGTH)
        pathBox = SK.ValueBox(pathRow, SK.CONTROL_X, SK.WIDTH - SK.CONTROL_X, ShowThumb, Media.MEDIA_PATH_LENGTH)
        local function ShowList() rows.Refresh() end
        Refresh = function(message, error)
            ShowList()
            status.text:SetText(message or "")
            SK.Ink(status.text, error and "error" or "muted")
            Options:RefreshEditorAppearance(PS.GetSettings())
            Options:RefreshEditorInspectorContext()
            Options:LayoutEditorSettingsPanels()
        end
        local buttonsRow = SK.ButtonsRow(edit, nil, {
            { L["Add or update"], 130, function()
                local name = nameBox:GetText()
                local ok, reason = PS.SetMyMedia(name, pathBox:GetText())
                Refresh(ok and string.format(L["Saved %s. Parts naming it draw it now."], name:match("^%s*(.-)%s*$"))
                    or reason, not ok)
            end },
        })
        SK.Add(edit, buttonsRow)
        status = SK.Add(edit, SK.Help(edit, ""))
        Options.editorMediaControls = { name = nameBox, path = pathBox, list = listText, rows = rows.rows, status = status,
            thumb = thumb, add = buttonsRow.buttons[1] }
        -- The list follows every refresh (the page refreshes what it holds whenever it shows).
        Register({ Refresh = ShowList })
    end)

    -- Studio's own look and size: this player's preferences, applied at once, never saved in a profile.
    Define("studio", function()
        local studio = Page("studio")
        Options.editorStudioPage = studio
        local size = Section(studio, "studioSize", L["Studio size"], function()
            return Controls.PercentText(Options:GetStudioScale())
        end)
        size.kitSearchKeywords = L["scale"]
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
        -- Colour-blind friendly: by default the plates' threat palette decides (Modules › Threat).
        local colourBlindRow, colourBlind = SK.DropdownRow(access, L["Colour-blind friendly"], {
            name = WidgetName("studio_colourBlind", "Dropdown"), choices = Options.StudioColourBlindChoices,
            get = function() return Options:StudioColourBlindChoice() end,
            set = function(value) Options:SetStudioAccess("colourBlind", value) end })
        colourBlindRow.kitSearchKeywords = L["colorblind colourblind"]
        SK.Add(access, colourBlindRow)
        SK.Add(access, SK.ControlHelp(access, L["Studio's lines are thicker and the preview's threat text uses blue and "
            .. "orange; nothing changes on the plates. It follows the plates' threat palette (Settings › Modules › Threat › "
            .. "Threat text & window colours) unless you choose On or Off."]))
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
        -- The What's new window's opt-out (Studio/LookUpdate.lua): the same setting as the window's own box.
        local news = Section(studio, "lookNews", L["Notices"])
        local newsRow, newsBox = SK.CheckRow(news, nil, { text = L["Tell me when a look has a new version"],
            name = WidgetName("studio_lookNews", "Checkbox"), get = function() return Options.LookUpdate.Enabled() end,
            set = function(enabled) Options.LookUpdate.SetEnabled(enabled) end })
        SK.Add(news, newsRow)
        SK.Add(news, SK.ControlHelp(news, L["When you open Studio and your profile's look has a new version, a window says "
            .. "what's new, once per profile and version. Off, it never shows; Profile › Update to the latest look still "
            .. "offers the update."]))
        Options.editorLookNewsCheckbox = Register(newsBox)
        -- The release What's new window's opt-out (Studio/WhatsNew.lua): the window's Don't show on startup, unticked.
        local releaseRow, releaseBox = SK.CheckRow(news, nil, { text = L["Show what's new when PlateSmith updates"],
            name = WidgetName("studio_releaseNews", "Checkbox"), get = function() return Options.WhatsNew.Enabled() end,
            set = function(enabled) Options.WhatsNew.SetEnabled(enabled) end })
        releaseRow.kitSearchKeywords = L["what's new release notes changelog startup login"]
        SK.Add(news, releaseRow)
        SK.Add(news, SK.ControlHelp(news, L["On your first login after PlateSmith updates to a new release, a window lists "
            .. "what's new, once. Off, it never shows on login (its Don't show on startup box is the same setting); "
            .. "Settings › Help › What's new... still shows it."]))
        Options.editorReleaseNewsCheckbox = Register(releaseBox)
        -- PlateSmith's minimap button (Core/MinimapButton.lua): this player's, for every character, never in a profile.
        local minimap = Section(studio, "minimapButton", L["Minimap button"])
        local minimapRow, minimapBox = SK.CheckRow(minimap, nil, { text = L["Show minimap button"],
            name = WidgetName("studio_minimapButton", "Checkbox"), get = function() return PS.MinimapButton.Shown() end,
            set = function(enabled) PS.MinimapButton.SetShown(enabled) end })
        minimapRow.kitSearchKeywords = L["icon broker minimap"]
        SK.Add(minimap, minimapRow)
        SK.Add(minimap, SK.ControlHelp(minimap, L["PlateSmith's button on the minimap's edge: left-click opens Studio, "
            .. "right-click its Settings; drag it round the edge to move it. For every character on this account; not "
            .. "saved in profiles or Blueprints."]))
        Options.editorMinimapCheckbox = Register(minimapBox)
        Options:RefreshStudioScaleControls()
    end)

    -- Help: how Studio works, in short sections.
    Define("help", function()
        local help = Page("help")
        for _, entry in ipairs({
            { "helpColumns", L["The three columns"], L["The tree lists this plate type's parts and groups. The preview shows "
                .. "the plate; drag parts there. The inspector on the right edits what is selected: a part, a group or "
                .. "Plate settings (the plate's scale, the target highlight and Quick layout; also Friendly plates on "
                .. "Players and Friendly NPCs, Totems while Type › Totems is open, and the object settings on Objects)."] },
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
                .. "while a condition holds, such as \"when unit.elite, set colour gold\". Test values try them in the preview."] },
            { "helpSharing", L["Sharing"], L["Export gives a share code (or readable JSON) for the current profile. Import "
                .. "takes one and lets you choose which sections to replace; press Save to keep them."] },
            { "helpCommands", L["Commands"], L["/ps opens Studio. /ps console shows or hides the threat windows. "
                .. "/ps diagnose opens a report to share when something looks wrong."] },
            { "helpThreat", L["Threat windows"], L["/ps console shows them: up to five, each a Threat meter (your group's "
                .. "threat on your target), Tank (every enemy in view and who holds it) or Rescue (your group, coloured when "
                .. "someone pulls or has aggro; click a member to taunt their target). Drag a title to move a window and "
                .. "those snapped to it (Shift: alone); drop it on a side of Blizzard's damage meter to follow it. Right-click "
                .. "a title for its menu; click a row to spotlight its plate. Threat breakdown (in that menu, or Settings "
                .. "› Modules › Threat › Threat windows) estimates your own threat on each of your recent pulls."] },
        }) do
            local section = Section(help, entry[1], entry[2])
            local body = SK.Add(section, SK.Help(section, entry[3]))
            SK.Ink(body.text, "label")
            if body.text.SetSpacing then body.text:SetSpacing(3) end
        end
        -- This release's highlights any time (Studio/WhatsNew.lua): the window that shows once on login.
        local news = Section(help, "helpWhatsNew", L["What's new"])
        news.kitSearchKeywords = L["release notes changelog"]
        local newsRow, newsButton = SK.ButtonRow(news, L["What's new..."], 200)
        newsRow.kitSearchKeywords = L["release notes changelog"]
        newsButton:SetScript("OnClick", function() Options.WhatsNew.Show() end)
        SK.Add(news, newsRow)
        SK.AttachHelp(newsRow, L["This release's highlights: the window that opens once on your first login after "
            .. "PlateSmith updates (Settings › Studio › Notices turns that on or off)."])
        Options.editorWhatsNewButton = newsButton
        Options.BuildRuleReference(help, Section, SK)
    end)

    -- A value change can change a folded section's summary.
    Register({ Refresh = function()
        if Options.editorSettingsWorkspace and Options.editorSettingsWorkspace:IsShown() then
            Options:LayoutEditorSettingsPanels()
        end
    end })
end

-- The rule reference (Rules › What can I use?): on Settings › Help, a section per topic of Core/RuleWords.lua (each
-- word in gold with its kind and old name, what it means, an example and the plates that have it), then the operators
-- and unknown values, then the presets that are built-in options now. Made from RuleWords only, so it cannot drift.
local WORD_COLOUR = "|cffffd100%s|r"
local function WordLines(entry)
    local head = string.format(WORD_COLOUR, entry.word) .. "   " .. entry.kind
    if #entry.former > 0 then head = string.format(L["%s · was %s"], head, table.concat(entry.former, ", ")) end
    if #entry.aliases > 0 then head = string.format(L["%s · also %s"], head, table.concat(entry.aliases, ", ")) end
    return string.format("%s\n%s\n%s", head, entry.text, string.format(L["Example: %s · Plates: %s"], entry.example,
        entry.plates))
end
function Options.BuildRuleReference(page, Section, SK)
    local Words, sections = PS.RuleWords, {}
    local function Body(section, text)
        local body = SK.Add(section, SK.Help(section, text))
        SK.Ink(body.text, "label")
        if body.text.SetSpacing then body.text:SetSpacing(3) end
        return body
    end
    local byTopic = {}
    for _, entry in ipairs(Words.Entries()) do
        byTopic[entry.topic] = byTopic[entry.topic] or {}
        table.insert(byTopic[entry.topic], entry)
    end
    for _, topic in ipairs(Words.TOPICS) do
        local section = Section(page, "helpRules_" .. topic.id, string.format(L["Rule words: %s"], topic.label))
        for _, entry in ipairs(byTopic[topic.id] or {}) do Body(section, WordLines(entry)).ruleWord = entry.word end
        sections[#sections + 1] = section
    end
    local operators = Section(page, "helpRules_operators", L["Rule words: and, or, not and unknown values"])
    for _, operator in ipairs(Words.OPERATORS) do
        Body(operators, string.format("%s\n%s\n%s", string.format(WORD_COLOUR, operator[1]), operator[2],
            string.format(L["Example: %s"], operator[3])))
    end
    Body(operators, Words.UNKNOWN)
    sections[#sections + 1] = operators
    local presets = Section(page, "helpRules_builtIn", L["Presets that are built-in options now"])
    for _, option in ipairs(Presets.BUILT_IN) do
        local names = {}
        for _, preset in ipairs(RULE_PRESETS) do
            if preset.builtIn == option.id then names[#names + 1] = preset.name end
        end
        Body(presets, string.format(L["%s: %s (%s)."], table.concat(names, ", "), option.name, option.home))
    end
    Body(presets, L["Rules made from them stay ordinary rules. Rules › Presets › Built in opens each."])
    sections[#sections + 1] = presets
    Options.editorRuleReferenceSections = sections
end

-- Rules › What can I use?: Settings › Help opened at the rule words (its first section unfolded, scrolled to and
-- flashed, as a search result opens).
function Options:OpenRuleReference()
    if not self:OpenSettingsCategory("help") then return false end
    local first = self.editorRuleReferenceSections and self.editorRuleReferenceSections[1]
    if not (first and self.settingsSearch) then return false end
    return self.settingsSearch.Pick({ place = "studio", category = "help", frame = first, section = first })
end

-- Rules › Presets › Built in (ProfilePresets.BUILT_IN): opens the option that does a retired preset's job. Colour by
-- threat and Fading are Settings rows; Colour by interrupt the Cast bar's row; Grey when tagged the Health bar's (an
-- enemy plate's: another plate type opens the Enemies).
function Options.OpenBuiltInOption(id)
    local Search = Options.settingsSearch
    if id == "threat" then return Options:OpenSettingsControl("plate.colourByThreat") end
    if id == "fading" then return Options:OpenSettingsControl("plate.fadeNonTarget") end
    if not Search then return false end
    if id == "tagged" then
        if not Options:IsEditorEnemy() then Options:OpenEditorDesign("enemy", "world") end
        return Search.RevealPartControl("health", function() return Options.editorGreyWhenTagged end)
    end
    if id == "interrupt" then
        return Search.RevealPartControl("cast", function() return Options.editorCastInterruptCheck end)
    end
    return false
end

-- A Settings page by key, built the first time it is wanted (shown, or indexed by Settings
-- search); nil for a page this client has none of (Stacking without PS.Stacking).
function Options:EditorSettingsPage(key)
    local pages = self.editorInspectorPages
    if not pages or key == nil then return nil end
    local build = settingsPageBuilders[key]
    if build then
        settingsPageBuilders[key] = nil
        BuildLater("studio settings " .. key, build, { "studioPage", key })
    elseif not pages[key] and self.ModuleSettingsBuilder then
        -- A module's page (Studio/Modules.lua), "module:<id>".
        build = self:ModuleSettingsBuilder(key)
        if build then BuildLater("studio settings " .. key, build, { "studioPage", key }) end
    end
    return pages[key]
end

-- Opens Studio's Settings at the category key (a link to a page, such as the Objects tab's Object settings...), opening
-- Studio first when it is closed (in combat too: its frames are not protected). section(): one of the page's sections,
-- read once the page is built, to unfold, scroll to and flash as a search result opens.
function Options:OpenSettingsCategory(key, section)
    if not (self.editor and self.editor:IsShown()) and not (PS.OpenVisualEditor and PS.OpenVisualEditor()) then
        return false
    end
    if not self:EditorSettingsPage(key) then return false end
    self:SetEditorInspectorPage(key)
    self:SetSettingsCategory(key)
    if self.editorSettingsCategory ~= key then return false end
    local frame = section and section()
    if frame and self.settingsSearch then
        self.settingsSearch.Pick({ place = "studio", category = key, frame = frame, section = frame })
    end
    return true
end

-- Where a bound control lives when it is not on the page its id names: id -> Settings page key. A page that moved
-- keeps its controls' ids (Settings/ThreatPage.lua: "plate.colourByThreat" is on Modules › Threat).
Options.settingsControlHomes = Options.settingsControlHomes or {}

-- Opens Studio's Settings at the row of the control bound as id ("<page>.<setting>", editorSettingsControls):
-- its section unfolded, scrolled to and flashed, as a search result opens it.
function Options:OpenSettingsControl(id)
    local key = type(id) == "string" and (self.settingsControlHomes[id] or id:match("^([^.]+)%.")) or nil
    if not (key and self:EditorSettingsPage(key) and self.settingsSearch) then return false end
    local control = self.editorSettingsControls and self.editorSettingsControls[id]
    local row = control and control:GetParent()
    if not row then return false end
    return self.settingsSearch.Pick({ place = "studio", category = key, frame = row, section = row:GetParent() })
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
