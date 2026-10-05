local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local catalog = assert(Options.editorCatalog)
local model = assert(Options.studioModel)
local editorOrder = catalog.editorOrder
local editorDefinitions = catalog.editorDefinitions
local editorProfiles = model.editorProfiles
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")
local Theme = assert(PS.StudioTheme)
local SetStudioButtonState = chrome.SetStudioButtonState
local CreateStudioButton = chrome.CreateStudioButton

local LABEL_FONT, LABEL, GOLD = chrome.FONT, chrome.LABEL, chrome.GOLD

-- Asked when Studio closes with unsaved changes. PlateSmith's own window, not a Blizzard
-- StaticPopup: Studio closes from Escape inside Blizzard's secure game-menu handling, and
-- writing its popup state from there tainted it (Escape's SpellStopCasting was blocked).
local function UnsavedChangesDialog()
    if Options.editorUnsavedDialog then return Options.editorUnsavedDialog end
    local Window = PS.UI.Window
    local dialog = Window.Create("PlateSmithUnsavedChangesDialog", {
        width = 500, height = 150, closeButton = false, closeOnEscape = false, movable = false,
        border = Window.colours.studio,
    })
    chrome.DressStudioDialog(dialog)
    chrome.DialogText(dialog, 26):SetText(L["Blueprint Studio has unsaved changes. They show on your plates until you save "
        .. "or discard them."])
    -- From the close button Studio is still open: Save and Discard close it, Keep editing only
    -- dismisses this. After Escape (Studio already hidden) Keep editing reopens it.
    local function Close()
        if Options.editor and Options.editor:IsShown() then Options.editor:Hide() end
    end
    -- Save (gold), Discard (red: it throws the changes away), Keep editing (dark).
    local actions = {
        { L["Save"], function() PS.Profiles.Save() Close() end, "primary" },
        { L["Discard"], function() PS.Profiles.Revert() Close() end, "action" },
        { L["Keep editing"], function()
            if not (Options.editor and Options.editor:IsShown()) then PS.OpenVisualEditor() end
        end },
    }
    dialog.buttons = {}
    for index, action in ipairs(actions) do
        local button = CreateStudioButton(dialog, action[1], 138, 32, action[3])
        button:SetScript("OnClick", function()
            dialog:Hide()
            action[2]()
        end)
        button:SetPoint("BOTTOM", dialog, "BOTTOM", (index - 2) * 150, 22)
        dialog.buttons[index] = button
    end
    Options.editorUnsavedDialog = dialog
    return dialog
end

-- A panel frame with the kit's panel art, laid out with the rest.
local function Panel(parent, kind, level)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetFrameLevel(level)
    return frame, chrome.TrackPanelArt(frame, kind)
end

local function HeaderLabel(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetFont(LABEL_FONT, 15)
    label:SetText(text)
    label:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
    return label
end

-- A Studio checkbox with the kit's art and a light label (the preview's Snap).
local function KitCheckbox(parent, text, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    PS.UI.Controls.StyleCheckbox(checkbox, 18)
    chrome.SkinCheckbox(checkbox)
    local label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetFont(LABEL_FONT, 15)
    label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
    label:SetText(text)
    checkbox.label = label
    checkbox:SetScript("OnClick", onClick)
    return checkbox
end

-- A group's header row in the tree: the kit's group row, its expand / collapse arrow, its eye
-- (shows or hides the group), its name and a drag handle.
function Options:CreateEditorGroupHeader(content, groupKey)
    local header = CreateFrame("Button", nil, content)
    header.customGroup = groupKey
    header:SetSize(254, 32)
    header.bar = header:CreateTexture(nil, "BACKGROUND")
    header.arrow = header:CreateTexture(nil, "ARTWORK")
    header.handle = header:CreateTexture(nil, "ARTWORK")
    local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("LEFT", header, "LEFT", 70, 0)
    text:SetFont(LABEL_FONT, 16)
    header.label = text
    -- Shown while something is dragged over it.
    header.dropTarget = header:CreateTexture(nil, "OVERLAY")
    header.dropTarget:Hide()
    -- The arrow folds the group; the rest of the row selects it.
    local fold = CreateFrame("Button", nil, header)
    fold:SetSize(28, 32)
    fold:SetPoint("LEFT", header, "LEFT", 0, 0)
    fold:SetScript("OnClick", function() Options:ToggleEditorGroup(groupKey) end)
    header.foldButton = fold
    function header.SetFolded(row, folded)
        row.folded = folded
        Theme.Place(row.arrow, folded and "expand-arrow-normal" or "collapse-arrow-normal", row, 6, 5)
    end
    local function Paint(instance, state)
        if instance.selected then state = "selected" end
        Theme.Place(instance.bar, "tree-group-row-" .. state, instance, 0, 0, instance:GetWidth(), 32)
        -- At rest the row draws nothing: its normal art is an opaque copy of the panel's fill,
        -- which would hide the panel's edge shading behind it.
        instance.bar:SetShown(state ~= "normal")
        Theme.Place(instance.dropTarget, "drop-target", instance, 0, 0, instance:GetWidth(), 32)
        -- The drag grip shows under the pointer, as on part rows.
        instance.handle:SetShown(state == "hover")
        Theme.Place(instance.handle, "drag-handle-normal", instance, instance:GetWidth() - 25, 4)
    end
    function header.SetSelected(row, selected)
        row.selected = selected and true or false
        Paint(row, "normal")
    end
    header:SetScript("OnSizeChanged", function(instance) Paint(instance, "normal") end)
    header:SetScript("OnEnter", function(instance) Paint(instance, "hover") end)
    header:SetScript("OnLeave", function(instance) Paint(instance, "normal") end)
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:SetScript("OnClick", function(instance, mouseButton)
        if mouseButton == "RightButton" then Options:OpenEditorContextMenu(groupKey, instance) return end
        Options:SelectEditorGroup(groupKey)
    end)
    header:SetScript("OnDoubleClick", function() Options:BeginEditorTreeRename(groupKey) end)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() Options:StartEditorTreeDrag("group", groupKey) end)
    header:SetScript("OnDragStop", function() Options:StopEditorTreeDrag() end)
    header:SetFolded(false)
    Paint(header, "normal")
    -- A mixed group shows every component on the first click, then hides them all.
    local visibility = chrome.CreateVisibilityEye(header, function(instance)
        Options:SetEditorGroupVisibility(groupKey, instance.mixed or instance:GetChecked() and true or false)
    end, L["Group"], { L["Show or hide every part in this group."] })
    visibility:SetPoint("LEFT", header, "LEFT", 35, 0)
    header.visibility = visibility
    return header
end

-- The tree's top row, Plate settings: the plate itself (its scale for this plate type, the target highlight).
local function CreatePlateRow(content)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(254, 30)
    row.bar = row:CreateTexture(nil, "BACKGROUND")
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("LEFT", row, "LEFT", 12, 0)
    text:SetFont(LABEL_FONT, 16)
    text:SetText(L["Plate settings"])
    text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    row.label = text
    local function Paint(instance, state)
        if instance.selected then state = "selected" end
        Theme.Place(instance.bar, "tree-part-row-" .. state, instance, 0, 0, instance:GetWidth(), 28)
        instance.bar:SetShown(state ~= "normal") -- (see the group rows)
    end
    function row:SetSelected(selected)
        self.selected = selected and true or false
        Paint(self, "normal")
    end
    row:SetScript("OnSizeChanged", function(instance) Paint(instance, "normal") end)
    row:SetScript("OnEnter", function(instance) Paint(instance, "hover") end)
    row:SetScript("OnLeave", function(instance) Paint(instance, "normal") end)
    row:SetScript("OnClick", function() Options:SelectEditorPlate() end)
    PS.UI.Controls.AttachTooltip(row, L["Plate settings"], { L["The whole plate's scale, for this plate type."],
        L["Target highlight: how your target's plate of this type is lit (Gold edge or Soft glow)."],
        L["Quick layout: place parts by position (top, bottom, left, right, centre)."] })
    Paint(row, "normal")
    return row
end

-- Test values' panel, made the first time it is opened (Options:EditorTestPanel): health % and the
-- flags the preview's templates and rules read (the samples). It opens upwards from its button on the
-- preview's foot (Chrome's LayoutEditorPreviewPanel); the sample name and the model are in View.
local function BuildTestPanel(canvas)
    -- It takes the pointer only over its own rectangle; drags elsewhere reach the preview.
    local testPanel = CreateFrame("Frame", nil, canvas)
    testPanel:SetSize(300, 378)
    testPanel:SetFrameLevel(canvas:GetFrameLevel() + 30)
    testPanel:EnableMouse(true)
    local testArt = chrome.CreatePanelArt(testPanel, "dark")
    testPanel:SetScript("OnSizeChanged", function() testArt:Layout() end)
    testArt:Layout()
    testPanel:Hide()
    Options.editorTestPanel = testPanel
    local samples = Options.templateSamples or {}
    local defaults = Options.editorTestDefaults or {}
    local testControls = {}
    local function Changed()
        Options:RefreshEditorAppearance(PS.GetSettings())
    end
    -- Health % and the combo points, side by side.
    local healthText = testPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthText:SetPoint("TOPRIGHT", testPanel, "TOPLEFT", 140, -14)
    local healthLabel = testPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthLabel:SetPoint("TOPLEFT", testPanel, "TOPLEFT", 16, -14)
    healthLabel:SetText(L["Health %"])
    local function SetSampleHealth(value)
        samples["health.percent"] = value
        samples["health"] = math.floor((samples["health.max"] or 1170) * value / 100 + 0.5)
    end
    -- While dragged only the preview follows, once a frame; letting go refreshes the rest.
    local healthSlider = PS.UI.Controls.Slider(testPanel, {
        min = 0, max = 100, step = 1, x = 14, y = -32, width = 126, valueText = healthText,
        format = PS.Format.Percent,
        get = function() return samples["health.percent"] or 72 end,
        drag = function(value)
            SetSampleHealth(value)
            Options:QueueRefresh()
        end,
        set = function(value)
            SetSampleHealth(value)
            Changed()
        end,
    })
    testControls[#testControls + 1] = healthSlider
    local comboText = testPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    comboText:SetPoint("TOPRIGHT", testPanel, "TOPRIGHT", -16, -14)
    local comboLabel = testPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    comboLabel:SetPoint("TOPLEFT", testPanel, "TOPLEFT", 160, -14)
    comboLabel:SetText(L["Combo points"])
    local comboSlider = PS.UI.Controls.Slider(testPanel, {
        min = 0, max = 5, step = 1, x = 158, y = -32, width = 126, valueText = comboText,
        get = function() return tonumber(samples.combo) or 3 end,
        drag = function(value)
            samples.combo = value
            Options:QueueRefresh()
        end,
        set = function(value)
            samples.combo = value
            Changed()
        end,
    })
    Options.editorTestComboSlider = comboSlider
    testControls[#testControls + 1] = comboSlider
    -- Each flag shows in the preview (and in rules and custom text): tagged the indicator, elite,
    -- rare and boss the mark, casting and interruptible the cast bar, combat and tanking the
    -- threat text, targeted the glow, quest the marker, friendly, hostile and player the name.
    -- interruptReady colours the cast bar with Colour by interrupt. The role and threat-state flags
    -- show Threat colours (with combat) and are for rules, hastarget and inrange for the fades.
    -- Each box says what it is in plain words; its tooltip names the flag rules and custom text read.
    local flags = {
        { "tagged", L["Tagged"] }, { "elite", L["Elite"] }, { "rare", L["Rare"] }, { "boss", L["Boss"] },
        { "casting", L["Casting"] }, { "interruptible", L["Interruptible"] }, { "interruptReady", L["Interrupt ready"] },
        { "combat", L["In combat"] }, { "tanking", L["Tanking"] }, { "targeted", L["Your target"] },
        { "quest", L["Quest unit"] }, { "friendly", L["Friendly"] }, { "hostile", L["Hostile"] }, { "player", L["Player"] },
        { "role.tank", L["You tank"] }, { "threat.holding", L["Holding threat"] }, { "threat.losing", L["Losing threat"] },
        { "threat.pulling", L["Pulling threat"] }, { "threat.other", L["Someone else has it"] },
        { "threat.offtank", L["Other tank has it"] }, { "hastarget", L["Has a target"] }, { "inrange", L["In range"] },
    }
    for index, entry in ipairs(flags) do
        local flag = entry[1]
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        local checkbox = PS.UI.Controls.Checkbox(testPanel, {
            label = entry[2], x = 12 + column * 144, y = -70 - row * 24, labelTemplate = "GameFontHighlightSmall",
            tooltip = { title = entry[2], lines = { string.format(L["Rules and custom text read this as %s."], flag) } },
            get = function() return samples[flag] == true end,
            set = function(on)
                samples[flag] = on and true or false
                Changed()
            end,
        })
        checkbox.sampleFlag = flag
        testControls[#testControls + 1] = checkbox
    end
    -- Reset also puts back View's sample name (Preview's ResetEditorSamples); it leaves the model.
    local reset = CreateStudioButton(testPanel, L["Reset"], 90, 24)
    reset:SetPoint("BOTTOMLEFT", testPanel, "BOTTOMLEFT", 14, 12)
    reset:SetScript("OnClick", function()
        Options:ResetEditorSamples(defaults)
        for _, control in ipairs(testControls) do control:Refresh() end
        Changed()
    end)
    Options.editorTestControls = testControls
    return testPanel
end

function Options:EditorTestPanel()
    if self.editorTestPanel or not self.editorCanvas then return self.editorTestPanel end
    self._BuildEditorLater("studio test values", BuildTestPanel, self.editorCanvas)
    if self.LayoutEditorPreviewPanel then self:LayoutEditorPreviewPanel() end
    if self.RefreshEditorModelNote then self:RefreshEditorModelNote() end
    return self.editorTestPanel
end

-- Settings' categories panel (its search box over a row per category), made when Settings first opens.
function Options:EditorSettingsCategories()
    if self.editorSettingsCategoriesPanel or not self.editor then return self.editorSettingsCategoriesPanel end
    self._BuildEditorLater("studio settings categories", function()
        local categories = Panel(self.editor, "dark", self.editor:GetFrameLevel() + 3)
        categories:Hide()
        self.editorSettingsCategoriesPanel = categories
        self.editorSettingsCategoryRows = {}
        for index = 1, 8 do
            local row = CreateStudioButton(categories, "", 282, 44, "category")
            row:SetScript("OnClick", function(instance)
                if instance.categoryKey then self:SetSettingsCategory(instance.categoryKey) end
            end)
            self.editorSettingsCategoryRows[index] = row
        end
        self:BuildSettingsSearch(categories)
    end)
    self:ReflowVisualEditor()
    return self.editorSettingsCategoriesPanel
end

function PS.CreateVisualEditor()
    if Options.editor then return Options.editor end

    local editor = CreateFrame("Frame", "PlateSmithBlueprintEditor", UIParent)
    editor:SetSize(1440, 900)
    editor:SetPoint("CENTER")
    editor:SetFrameStrata("DIALOG")
    editor:SetMovable(true)
    if editor.SetResizable then editor:SetResizable(true) end
    if editor.SetResizeBounds then
        editor:SetResizeBounds(1440, 900, 1600, 1000)
    else
        if editor.SetMinResize then editor:SetMinResize(1440, 900) end
        if editor.SetMaxResize then editor:SetMaxResize(1600, 1000) end
    end
    editor:EnableMouse(true)
    editor:RegisterForDrag("LeftButton")
    editor:SetClampedToScreen(true)
    editor:SetScript("OnDragStart", function(instance) instance:StartMoving() end)
    editor:SetScript("OnDragStop", function(instance) instance:StopMovingOrSizing() end)
    editor:SetScript("OnSizeChanged", function() Options:ReflowVisualEditor() end)
    -- Changes show on the plates live, so leaving with some unsaved asks what to do with them
    -- rather than keeping them in play unsaved.
    editor:SetScript("OnHide", function()
        if PS.SetLayoutMeasure then PS.SetLayoutMeasure(nil) end
        Options:UpdateEditorPulse()
        if PS.Profiles.IsDirty() then UnsavedChangesDialog():Show() end
    end)
    local function Opened()
        -- Tree moves keep a stacked part where its stack draws it (the preview's sizes).
        Options:SupplyEditorMeasure()
        Options:FitVisualEditorToScreen()
        -- Just built, it is already refreshed and its part selected; reopened, settings may have
        -- changed meanwhile.
        if Options.editorJustBuilt then
            Options.editorJustBuilt = nil
        else
            Options:Refresh()
            Options:SelectEditorComponent(Options.selectedComponent or "health")
        end
        Options:UpdateEditorPulse()
        Options:FitEditorPreview() -- opens fitted: as large as fits, up to 200%, centred
        -- Off (the default) makes nothing; a model chosen before is shown again (you, or the new target).
        Options:ApplyEditorModel()
    end
    -- The client reports an error in a script handler itself, so OnShow catches its own and closes.
    editor:SetScript("OnShow", function()
        local ok, failure = pcall(Opened)
        if not ok then Options:FailEditorOpen(failure) end
    end)
    -- The kit's controls take Studio's look as they are made inside it.
    editor.skinControl = chrome.SkinControl
    Options.editor = editor
    -- While it is built, layouts leave the tree and the inspector's column to the one full refresh
    -- at the end (Chrome's ReflowVisualEditor).
    Options.editorBuilding = true
    PS.UI.Window.CloseOnEscape("PlateSmithBlueprintEditor")

    -- The painted frame (Chrome's LayoutEditorShell places it).
    Options.editorShell = chrome.CreateEditorShell(editor)
    local base = editor:GetFrameLevel()

    -- The close button, seated in the close corner's recess over its solid backing.
    local close = chrome.CreateCloseButton(editor)
    close:SetFrameLevel(base + 12)
    close.backing = close:CreateTexture(nil, "BACKGROUND")
    Theme.Place(close.backing, "close-backing", close, 0, 0)
    -- With unsaved changes the close button asks first; Studio stays open behind the question.
    close:SetScript("OnClick", function()
        if PS.Profiles.IsDirty() then UnsavedChangesDialog():Show() else editor:Hide() end
    end)
    PS.UI.Controls.AttachTooltip(close, L["Close"], { L["Close Blueprint Studio."] })
    Options.editorCloseButton = close

    -- The resize grip: faint in the corner until the pointer finds it, like a meter's grips.
    local resize = CreateFrame("Button", nil, editor)
    resize:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -3, 3)
    resize:SetSize(26, 26)
    resize:SetFrameLevel(base + 12)
    for _, spec in ipairs({ { "SetNormalTexture", "GetNormalTexture", "Up" },
        { "SetHighlightTexture", "GetHighlightTexture", "Highlight" }, { "SetPushedTexture", "GetPushedTexture", "Down" } }) do
        resize[spec[1]](resize, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-" .. spec[3])
        local texture = resize[spec[2]] and resize[spec[2]](resize)
        if texture and texture.SetVertexColor then texture:SetVertexColor(1, 0.80, 0.45, 1) end
    end
    resize:SetAlpha(0.4)
    resize:SetScript("OnEnter", function(instance) instance:SetAlpha(1) end)
    resize:SetScript("OnLeave", function(instance) instance:SetAlpha(0.4) end)
    resize:SetScript("OnMouseDown", function()
        if editor.StartSizing then editor:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnMouseUp", function()
        editor:StopMovingOrSizing()
        Options:FitVisualEditorToScreen()
    end)
    PS.UI.Controls.AttachTooltip(resize, L["Resize Blueprint Studio"], {})
    if not editor.SetResizable or not editor.StartSizing then resize:Hide() end
    Options.editorResizeGrip = resize

    -- The body behind the panels (ReflowVisualEditor sizes it).
    local workbench = CreateFrame("Frame", nil, editor)
    workbench:SetFrameLevel(base + 1)
    Options.editorWorkbench = workbench

    -- Header band: the Studio / Settings toggle and Profile; the subtitle under the logo.
    local header = CreateFrame("Frame", nil, editor)
    header:SetPoint("TOPLEFT", editor, "TOPLEFT", 36, -84)
    header:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -36, -84)
    header:SetHeight(68)
    header:SetFrameLevel(base + 4)
    local subtitle = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetFont(LABEL_FONT, 13)
    subtitle:SetText(L["Blueprint Studio"])
    subtitle:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
    subtitle:SetShadowColor(0, 0, 0, 1)
    subtitle:SetShadowOffset(1, -1)
    Options.editorSubtitle = subtitle

    local studioToggle = CreateStudioButton(header, L["Studio"], 92, 32, "toggle")
    studioToggle:SetScript("OnClick", function() Options:SetEditorInspectorPage("components") end)
    Options.editorStudioToggle = studioToggle
    local settingsToggle = CreateStudioButton(header, L["Settings"], 94, 32, "toggle")
    settingsToggle:SetScript("OnClick", function() Options:SetEditorInspectorPage(Options.editorSettingsCategory or "plate") end)
    Options.editorSettingsButton = settingsToggle

    Options.editorProfileLabel = HeaderLabel(header, L["Profile:"])
    local profileNotice = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileNotice:SetFont(LABEL_FONT, 12)
    profileNotice:SetJustifyH("CENTER")
    Options.editorProfileNotice = profileNotice
    local profileDropdown
    local function RefreshProfile()
        profileDropdown:SetText(PS.Profiles.Active())
        local active = tostring(PS.Profiles.Active() or PS.Profiles.DEFAULT)
        profileNotice:SetText(PS.Profiles.IsDirty()
            and string.format(L["Profile: %s · |cffffc94aUnsaved changes|r · Save or revert before switching profile"], active)
            or "")
    end
    -- Profiles: switch between them, and below a divider New, Duplicate, Rename and Delete.
    local function ProfileAction(ok, reason)
        if ok then
            RefreshProfile()
            Options:Refresh(true)
        end
        return ok, reason
    end
    local function ProfileItems()
        local Profiles = PS.Profiles
        local items, dirty, active = {}, Profiles.IsDirty(), Profiles.Active()
        for _, name in ipairs(Profiles.List()) do
            local profileName = name
            items[#items + 1] = { text = name, checked = name == active, disabled = dirty, func = function()
                -- A menu can outlive the clean state it was opened in; Switch checks again.
                local switched = Profiles.Switch(profileName)
                RefreshProfile()
                if switched then Options:Refresh(true) end
            end }
        end
        items[#items + 1] = { separator = true }
        -- New and Duplicate switch to the new profile, which would drop unsaved edits: while
        -- there are some they are off, and say why (a disabled entry keeps its tooltip).
        local switchTip = L["Save or revert your changes first: this switches to the new profile."]
        items[#items + 1] = { text = L["New profile..."], disabled = dirty, tooltip = dirty and switchTip or nil, func = function()
            Options:PromptStudioName(L["Name for the new profile:"], "",
                function(text) return ProfileAction(Profiles.Create(text)) end)
        end }
        local presets = {}
        for _, preset in ipairs(PS.ProfilePresets.LIST) do
            local id = preset.id
            presets[#presets + 1] = { text = preset.name, disabled = dirty,
                tooltip = { title = preset.name, text = preset.description }, func = function()
                    local ok, reason = ProfileAction(Profiles.CreateFromPreset(id))
                    if not ok then PS.Chat.Print(string.format(L["Profile change failed: %s"], L[reason or "unknown error"])) end
                end }
        end
        items[#items + 1] = { text = L["New from preset..."], children = presets, disabled = dirty,
            tooltip = dirty and switchTip or L["A new profile from a built-in design, named after it. Your profiles are not changed."] }
        items[#items + 1] = { text = L["Duplicate this profile..."], disabled = dirty, tooltip = dirty and switchTip or nil,
            func = function()
                Options:PromptStudioName(L["Name for the copy:"], string.format(L["%s copy"], active),
                    function(text) return ProfileAction(Profiles.Create(text, active)) end)
            end }
        items[#items + 1] = { text = L["Rename this profile..."], func = function()
            Options:PromptStudioName(L["New name for this profile:"], active,
                function(text) return ProfileAction(Profiles.Rename(text)) end)
        end }
        local deletable = {}
        for _, name in ipairs(Profiles.List()) do
            if name ~= active then
                local profileName = name
                deletable[#deletable + 1] = { text = name, func = function()
                    Options:ConfirmStudioAction(string.format(L["Delete the profile \"%s\"? This cannot be undone."],
                        profileName), L["Delete"], function() ProfileAction(Profiles.Delete(profileName)) end)
                end }
            end
        end
        -- The active profile cannot be deleted, so with only one there is nothing to delete.
        items[#items + 1] = { text = L["Delete a profile"], children = deletable, disabled = #deletable == 0,
            tooltip = #deletable == 0 and L["There is no other profile to delete. The one in use cannot be deleted."] or nil }
        -- Settings › Profiles › Automatic switching (Blizzard's Settings panel, closed to addons in combat).
        local inCombat = PS.Secret.InCombat()
        items[#items + 1] = { separator = true }
        items[#items + 1] = { text = L["Switch automatically..."], disabled = inCombat,
            tooltip = inCombat and L["Blizzard's Settings panel opens only out of combat."]
                or L["Choose a profile this character switches to by itself, by content or specialization."],
            func = function() Options:OpenAutoProfileSettings() end }
        return items
    end
    profileDropdown = PS.UI.Controls.MenuField(header, { name = "PlateSmithEditorNamedProfileDropdown", width = 126,
        height = 34, minMenuWidth = 200, items = function()
            local items = ProfileItems()
            RefreshProfile()
            return items
        end })
    chrome.SkinDropdown(profileDropdown)
    PS.UI.Controls.AttachTooltip(profileDropdown, L["Profile"], { L["The saved profile being edited."] })
    profileDropdown.studioLabel = Options.editorProfileLabel
    Options.editorNamedProfileDropdown = profileDropdown
    -- Studio always shows and edits the active profile: a switch from anywhere (Settings, a slash
    -- command, New from preset) redraws it, not only one made from this menu.
    -- While Studio is hidden the listener is skipped and runs once when it is shown again.
    local seenLoads = PS.Profiles.Loads()
    PS.Profiles.Subscribe(function()
        RefreshProfile()
        if PS.Profiles.Loads() ~= seenLoads then
            seenLoads = PS.Profiles.Loads()
            Options:Refresh(true)
        end
    end, editor)
    RefreshProfile()

    -- Studio: the component tree.
    local list = Panel(editor, "dark", base + 3)
    Options.editorList = list
    local listTitle = list:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    listTitle:SetFont(LABEL_FONT, 19)
    listTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    listTitle:SetText(L["Parts"])
    Options.editorListTitle = listTitle
    -- One + Add menu: a group, a part put back (after it was deleted), or a value.
    local add = CreateStudioButton(list, L["+ Add"], 265, 32)
    add:SetScript("OnClick", function(instance) Options:OpenEditorAddMenu(instance) end)
    PS.UI.Controls.AttachTooltip(add, L["Add"], { L["A group, a value or shape, or a part you deleted (back in its default place)."],
        L["With a group selected, it goes inside that group."] })
    Options.editorAddButton = add

    local search = CreateFrame("EditBox", nil, list)
    search:SetAutoFocus(false)
    search:SetFont(LABEL_FONT, 14, "")
    search:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
    search:SetTextInsets(38, 10, 0, 0)
    search.field = Theme.ThreeSlice(search, "search-field", nil)
    Options.editorKitFields = Options.editorKitFields or {}
    Options.editorKitFields[#Options.editorKitFields + 1] = search.field
    search.icon = search:CreateTexture(nil, "ARTWORK")
    search:SetScript("OnSizeChanged", function(instance)
        instance.field:Layout()
        Theme.Place(instance.icon, "search-icon-normal", instance, 8, 5)
    end)
    local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetFont(LABEL_FONT, 14)
    hint:SetPoint("LEFT", search, "LEFT", 38, 0)
    hint:SetText(L["Search parts..."])
    search.hint = hint
    search:SetScript("OnTextChanged", function(instance)
        Options.editorSearchText = instance:GetText()
        instance.hint:SetShown(instance:GetText() == "")
        Options:RefreshEditorComponentList(PS.GetSettings())
    end)
    search:SetScript("OnEscapePressed", function(instance) instance:SetText("") instance:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(instance) instance:ClearFocus() end)
    Options.editorSearchField = search

    local listScroll = CreateFrame("ScrollFrame", "PlateSmithEditorComponentScroll", list)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(254, 500)
    listScroll:SetScrollChild(listContent)
    Options.editorListScroll, Options.editorListContent = listScroll, listContent
    Options.editorListScrollBar = chrome.CreateStudioScrollBar(listScroll, list)
    Options.editorPlateRow = CreatePlateRow(listContent)
    -- A part's tree row is made the first time anything asks for it (the tree, when it shows the
    -- part): most parts are not on the plate type Studio opens on, or wait in a folded group.
    Options.editorComponentButtons = setmetatable({}, { __index = function(_, key)
        return Options:CreateEditorComponentButton(key)
    end })

    -- Studio: the preview, its plate-type tabs above the stage.
    local canvas, stageArt = Panel(editor, "preview", base + 3)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function() Options:StartEditorPan() end)
    canvas:SetScript("OnMouseUp", function() Options:StopEditorPan() end)
    canvas:SetScript("OnHide", function() Options:StopEditorPan() end)
    if canvas.EnableMouseWheel then canvas:EnableMouseWheel(true) end
    canvas:SetScript("OnMouseWheel", function(_, delta)
        Options:SetEditorPreviewZoom(Options.editorPreviewZoom + delta * 0.25)
    end)
    Options.editorCanvas = canvas
    Options.editorStageArt = stageArt

    Options.editorProfileButtons = {}
    Options.editorPlateTabs = {}
    for _, definition in ipairs(editorProfiles) do
        local tab = CreateStudioButton(canvas, definition.label, 230, 40, "tab")
        tab:SetFrameLevel(canvas:GetFrameLevel() + 6)
        tab:SetScript("OnClick", function() Options:SetEditorProfile(definition.key) end)
        Options.editorProfileButtons[definition.key] = tab
        Options.editorPlateTabs[#Options.editorPlateTabs + 1] = tab
    end
    -- Under the tabs: which design of the plate type is edited, what it follows, Where plates show and
    -- View (DesignRow.lua). Nothing else sits over the preview.
    Options:BuildEditorDesignRow(canvas)
    -- The model's note (PreviewModel.lua), under View: empty unless it shows you instead or cannot show.
    local modelNote = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    modelNote:SetJustifyH("RIGHT")
    if modelNote.SetWordWrap then modelNote:SetWordWrap(false) end
    Options.editorModelNote = modelNote
    -- Test values (on the preview's foot, after Snap): what the preview's templates and rules read (the
    -- samples). Set health % and the flags to see a rule or template as it would be on such a unit.
    local testButton = CreateStudioButton(canvas, L["Test values"], 110, 26)
    testButton:SetFrameLevel(canvas:GetFrameLevel() + 9)
    PS.UI.Controls.AttachTooltip(testButton, L["Test values"], {
        L["Set the preview's health % and conditions (tagged, elite, casting, threat...) to see your rules and "
            .. "custom text as they would be on such a unit. Your real plates always read the real unit."],
    })
    Options.editorTestButton = testButton
    -- Test values' Reset goes back to the samples as Studio made them; its panel is made when first opened.
    local defaults = {}
    for token, value in pairs(Options.templateSamples or {}) do defaults[token] = value end
    Options.editorTestDefaults = defaults
    testButton:SetScript("OnClick", function()
        local testPanel = Options:EditorTestPanel()
        if not testPanel then return end
        testPanel:SetShown(not testPanel:IsShown())
        SetStudioButtonState(testButton, testPanel:IsShown())
        -- The model keeps clear of the open panel.
        Options:PlaceEditorModel(true)
        if testPanel:IsShown() then
            for _, control in ipairs(Options.editorTestControls or {}) do control:Refresh() end
        end
    end)

    -- Friendly plates: which outdoor layout the preview edits (names only or full plate).
    Options.editorFriendlyViewButtons = {}
    for _, view in ipairs({ { "names", L["Names only"] }, { "full", L["Full plate"] } }) do
        local key = view[1]
        local button = CreateStudioButton(canvas, view[2], 104, 26, "toggle")
        button:SetFrameLevel(canvas:GetFrameLevel() + 6)
        button:SetScript("OnClick", function() Options:SetEditorFriendlyView(key) end)
        PS.UI.Controls.AttachTooltip(button, view[2], {
            L["Friendly plates keep two outdoor layouts; this switch picks which one you are editing. Styles "
                .. "and rules are shared by both."],
            { L["Gold: the one your plates use now (Settings > Behaviour & display > Friendly units)."], 0.86, 0.86, 0.86 },
        })
        button:Hide()
        Options.editorFriendlyViewButtons[key] = button
    end

    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    stage:SetSize(1, 1)
    stage:SetScale(Options.editorPreviewZoom)
    stage:SetFrameLevel(canvas:GetFrameLevel() + 2)
    Options.editorPreviewStage = stage

    -- The grid is not on the stage: its lines are placed in canvas units over the visible preview from the
    -- zoom and pan (UpdateEditorGrid), under the stage and the model.
    local gridFrame = CreateFrame("Frame", nil, canvas)
    gridFrame:SetAllPoints(canvas)
    gridFrame:SetFrameLevel(canvas:GetFrameLevel() + 1)
    Options.editorGrid = { frame = gridFrame, textures = {}, area = {} }
    Options:UpdateEditorGrid()

    local guideX = stage:CreateTexture(nil, "ARTWORK")
    guideX:SetSize(1, 200)
    guideX:SetColorTexture(1, 0.77, 0.23, 0.74)
    guideX:Hide()
    Options.editorSnapGuideX = guideX
    local guideY = stage:CreateTexture(nil, "ARTWORK")
    guideY:SetSize(285, 1)
    guideY:SetColorTexture(1, 0.77, 0.23, 0.74)
    guideY:Hide()
    Options.editorSnapGuideY = guideY
    -- Placed in whole physical pixels as they show (Options:EditorPixelLine), not by the client.
    PS.UI.Controls.KeepOffPixelGrid(guideX)
    PS.UI.Controls.KeepOffPixelGrid(guideY)

    Options.editorComponents = {}
    for _, key in ipairs(editorOrder) do Options:CreateEditorComponent(key, editorDefinitions[key]) end

    local previewControls = CreateFrame("Frame", nil, canvas)
    previewControls:SetAllPoints()
    previewControls:SetFrameLevel(canvas:GetFrameLevel() + 8)
    Options.editorPreviewControls = previewControls
    local zoomOut = CreateStudioButton(previewControls, "-", 34, 32)
    zoomOut:SetScript("OnClick", function() Options:SetEditorPreviewZoom(Options.editorPreviewZoom - 0.25) end)
    local zoomText = previewControls:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    zoomText:SetFont(LABEL_FONT, 15)
    Options.editorZoomText = zoomText
    local zoomIn = CreateStudioButton(previewControls, "+", 34, 32)
    zoomIn:SetScript("OnClick", function() Options:SetEditorPreviewZoom(Options.editorPreviewZoom + 0.25) end)
    Options.editorZoomInButton, Options.editorZoomOutButton = zoomIn, zoomOut
    local fit = CreateStudioButton(previewControls, L["Fit"], 62, 32)
    fit:SetScript("OnClick", function() Options:FitEditorPreview() end)
    Options.editorFitButton = fit
    local snap = KitCheckbox(previewControls, L["Snap"], function(instance)
        Options.editorSnap = instance:GetChecked() and true or false
    end)
    snap:SetChecked(Options.editorSnap)
    -- (Test values follows it on the foot, so Shift's hint is in the tooltip only.)
    PS.UI.Controls.AttachTooltip(snap, L["Snap"],
        { L["Lines parts up with the plate and each other. Hold Shift while dragging to place freely."] })
    Options.editorSnapCheckbox = snap

    -- Nudge buttons in a row: up, down, left, right (Shift for 10 px).
    local movement = CreateFrame("Frame", nil, previewControls)
    movement:SetSize(192, 32)
    local directions = {
        { label = L["Left"], column = 2, icon = "move-left", dx = -1, dy = 0 },
        { label = L["Up"], column = 0, icon = "move-up", dx = 0, dy = 1 },
        { label = L["Down"], column = 1, icon = "move-down", dx = 0, dy = -1 },
        { label = L["Right"], column = 3, icon = "move-right", dx = 1, dy = 0 },
    }
    Options.editorNudgeButtons = {}
    for index, direction in ipairs(directions) do
        local button = CreateStudioButton(movement, "", 36, 32)
        button:SetPoint("TOPLEFT", movement, "TOPLEFT", direction.column * 52, 0)
        local icon = button:CreateTexture(nil, "OVERLAY")
        Theme.Place(icon, direction.icon .. "-normal", button, 0, 0)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.icon = icon
        button:SetScript("OnClick", function() Options:NudgeEditorComponent(direction.dx, direction.dy) end)
        PS.UI.Controls.AttachTooltip(button, string.format(L["Move %s"], direction.label),
            { L["1 px · Shift-click for 10 px"] })
        Options.editorNudgeButtons[index] = button
    end
    Options.editorMoveControls = movement

    -- Studio: the inspector; Settings: the categories and the page (Inspector.lua builds them).
    -- (The categories are made when Settings first opens: Options:EditorSettingsCategories.)
    Options:BuildStudioInspector(workbench)

    -- Footer: Studio's Reset layout, Import and Export, or Settings' Reset settings; Revert and Save.
    local footerLayout = {}
    local function FooterButton(text, width, x, variant, right)
        local button = CreateStudioButton(editor, text, width, 32, variant or "action")
        button:SetFrameLevel(base + 6)
        footerLayout[#footerLayout + 1] = { button = button, x = x, right = right }
        return button
    end
    local resetLayout = FooterButton(L["Reset layout"], 130, 96)
    -- World's parts go back to their default places; a context's design takes World's places again, and
    -- the Enemy players layer the Enemies'.
    resetLayout:SetScript("OnClick", function()
        local text = L["Put this design's parts back where World has them? Revert undoes it until you save."]
        if Options.editorProfile == "enemyPlayer" then
            text = L["Put Enemy players' parts back where the Enemies have them? Revert undoes it until you save."]
        elseif Options.editorDesign == "world" then
            text = L["Put this plate type's parts back in their default positions? Revert undoes it until you save."]
        end
        Options:ConfirmStudioAction(text, L["Reset layout"], function() Options:ResetEditorLayout() end)
    end)
    PS.UI.Controls.AttachTooltip(resetLayout, L["Reset layout"], { L["Only the positions of the plate type you are editing."] })
    local import = FooterButton(L["Import"], 116, 247)
    import:SetScript("OnClick", function() Options:ShowImportBlueprint() end)
    local export = FooterButton(L["Export"], 116, 382)
    export:SetScript("OnClick", function() Options:ShowExportBlueprint() end)

    local resetAll = FooterButton(L["Reset settings"], 150, 96)
    -- Both resets ask first; either can still be undone with Revert until you save.
    resetAll:SetScript("OnClick", function()
        Options:ConfirmStudioAction(L["Reset every setting and position in this profile to the defaults? Revert undoes it "
            .. "until you save."], L["Reset settings"], function()
            PS.ResetSettings()
            Options:Refresh(true)
        end)
    end)
    PS.UI.Controls.AttachTooltip(resetAll, L["Reset settings"], { L["Every setting and position in this profile, for all plate types."] })

    local saveBar = PS.SaveBar.Create(editor, function(parent, text, _, _, primary)
        return CreateStudioButton(parent, text, 118, 32, primary and "primary" or "action")
    end)
    saveBar:SetSize(254, 32)
    saveBar:SetFrameLevel(base + 6)
    saveBar.revertButton:ClearAllPoints()
    saveBar.revertButton:SetPoint("RIGHT", saveBar.saveButton, "LEFT", -18, 0)
    saveBar.status:Hide() -- The dirty notice sits in the footer's middle.
    footerLayout[#footerLayout + 1] = { button = saveBar, x = 365, right = true }
    Options.editorSaveBar = saveBar
    Options:BuildEditorCpuReadout(editor, base + 6)
    Options.editorFooterLayout = footerLayout
    Options.editorStudioFooterButtons = { resetLayout, import, export }
    Options.editorSettingsFooterButtons = { resetAll }

    Options.editorResetButton = resetAll
    Options.resetLayoutButton = resetLayout
    Options.exportBlueprintButton = export
    Options.importBlueprintButton = import
    Options.editorPreloadedArt = chrome.PreloadStudioArt(editor)
    Options:ReflowVisualEditor()
    -- One full refresh (the plate type's layout, the tree, controls and preview), then the kit's look.
    Options.editorBuilding = nil
    Options.selectedComponent = Options.selectedComponent or "health"
    Options:SetEditorProfile("enemy")
    Options:ApplyEditorTheme()
    editor:Hide()
    return editor
end

-- Studio (DIALOG) opens above Blizzard's Settings window (HIGH) rather than closing it: closing it from addon
-- code (HideUIPanel) tainted the panel manager, which later blocked the spellbook, action
-- bar layout and Escape's SpellStopCasting.
--
-- A build or open that fails (the client stops a script that runs too long, which it did to Studio's
-- first open in a dungeon) must not leave the window shown but undrawn: it is hidden, the error is
-- reported, and one chat line says what to do. A half-built Studio is not shown again until /reload.
function Options:FailEditorOpen(failure, broken)
    if broken then self.editorBroken = true end
    self.editorJustBuilt, self.editorBuilding = nil, nil
    if self.editor and self.editor:IsShown() then self.editor:Hide() end
    PS.Chat.ReportError("studio open", failure)
    PS.Chat.Print(L["Blueprint Studio could not open. Type /reload, then /ps to try again."])
end

function PS.OpenVisualEditor()
    if Options.editorBroken then
        PS.Chat.Print(L["Blueprint Studio could not open. Type /reload, then /ps to try again."])
        return false
    end
    local built = Options.editor == nil
    local ok, editor = pcall(PS.CreateVisualEditor)
    if not ok then
        Options:FailEditorOpen(editor, true)
        return false
    end
    Options.editorJustBuilt = built or nil
    editor:Show()
    -- A fresh install's first open: the first-run picker over Studio (Studio/FirstRun.lua).
    if Options.ShowFirstRunIfPending then Options:ShowFirstRunIfPending() end
    return editor:IsShown() and true or false
end
