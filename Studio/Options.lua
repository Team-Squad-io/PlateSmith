local _, PS = ...

local Options = assert(PS.Options, "PlateSmith EditorComponents missing")
local catalog = assert(Options.editorCatalog)
local editorDefaults = catalog.editorDefaults
local editorOrder = catalog.editorOrder
local editorLabels = catalog.editorLabels
local editorDefinitions = catalog.editorDefinitions
local VALUE_SLOT_COUNT = catalog.VALUE_SLOT_COUNT
local valueSourceChoices = catalog.valueSourceChoices
local valueSourceByKey = catalog.valueSourceByKey
local valueAnchorChoices = catalog.valueAnchorChoices
local editorProfiles = {
    { key = "enemy", label = "Enemies", sampleName = "Training Raider", colour = { 1, 0.25, 0.2 } },
    { key = "friendlyPlayer", label = "Players", sampleName = "Your Character", colour = { 0.25, 1, 0.45 } },
    { key = "friendlyNPC", label = "Friendly NPCs", sampleName = "Innkeeper Allison", colour = { 0.35, 0.9, 1 } },
}
local editorGroups = {
    { key = "text", label = "Text", components = { name = true, level = true, guild = true, threat = true, tagged = true } },
    { key = "bars", label = "Bars", components = { health = true, power = true, cast = true } },
    { key = "markers", label = "Markers", components = { quest = true, raidIcon = true, relationshipIcon = true, pvpIcon = true, classification = true } },
    { key = "auras", label = "Auras", components = { buffs = true, debuffs = true } },
    { key = "other", label = "Other", components = {} },
}
for index = 1, VALUE_SLOT_COUNT do editorGroups[1].components["value" .. index] = true end
local function EditorGroupForKey(key)
    for _, group in ipairs(editorGroups) do
        if group.components[key] then return group.key end
    end
    return "other"
end
local editorContextForKey = {
    name = "name", level = "level", guild = "guild",
    health = "health", power = "power", cast = "cast",
    threat = "threat", tagged = "tagged", quest = "quest",
    raidIcon = "raidIcon", relationshipIcon = "relationshipIcon", pvpIcon = "pvpIcon", classification = "classification",
    buffs = "buffs", debuffs = "debuffs",
}
for index = 1, VALUE_SLOT_COUNT do editorContextForKey["value" .. index] = "value" end
local editorDescriptions = {
    name = "The readable name displayed above this unit.",
    level = "The unit level, positioned independently.",
    guild = "A readable guild name above friendly players outdoors.",
    health = "The main health display for this unit.",
    power = "A movable power bar; mana is shown for units that use mana.",
    cast = "Tracks the unit's current cast.",
    threat = "Percentage and signed lead when the client permits it.",
    tagged = "Appears when another player or group has tagged this mob.",
    quest = "Marks an active quest objective or possible item drop.",
    raidIcon = "Shows the assigned Blizzard raid target icon.",
    relationshipIcon = "Marks current group or guild members outdoors.",
    pvpIcon = "Marks a PvP-flagged friendly player outdoors.",
    classification = "Shows elite, rare, rare elite, or world-boss status.",
    buffs = "Helpful auras near the nameplate.",
    debuffs = "Harmful auras near the nameplate.",
}
for index = 1, VALUE_SLOT_COUNT do
    editorDescriptions["value" .. index] = "Choose a live value, attach it to a bar or the plate, then position it."
end
local editorBlueprint = assert(Options.editorBlueprint, "PlateSmith EditorBlueprint missing")
local CopyEditorLayout = editorBlueprint.CopyLayout
Options.editorProfile = "enemy"
Options.editorContext = "world"
Options.editorPreviewZoom = 2
Options.editorSnap = true
Options.editorGroupOpen = { text = true, bars = true, markers = true, auras = true, other = true }

function Options:CurrentEditorVariant()
    if self.editorProfile == "enemy" or self.editorProfile == "enemyDungeon" then return "full" end
    if self.editorContext == "dungeon" then return "dungeon" end
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return settings and settings.friendly == "names" and "names" or "full"
end

local modeChoices = {
    { value = "auto", label = "Automatic" },
    { value = "own", label = "PlateSmith skin" },
    { value = "overlay", label = "Overlay only" },
}

local friendlyChoices = {
    { value = "names", label = "Names only" },
    { value = "full", label = "Full plates" },
    { value = "off", label = "Blizzard plates" },
}

local friendlyPvpChoices = {
    { value = "off", label = "Off" },
    { value = "colour", label = "Name colour" },
    { value = "icon", label = "Faction icon" },
    { value = "both", label = "Colour and icon" },
}

local editorThemeChoices = {
    { value = "auto", label = "Automatic" },
    { value = "classic", label = "Classic" },
    { value = "modern", label = "Modern" },
}

local targetHighlightChoices = {
    { value = "off", label = "Off", help = "No extra glow. The health bar keeps its normal target edge." },
    { value = "border", label = "Steady glow", help = "Gold light follows the selected plate's text and visible bars, without a box around the whole plate." },
    { value = "halo", label = "Pulsing glow", help = "The same text-and-bar glow gently pulses around the selected plate." },
}

local auraSourceChoices = {
    { value = "mine", label = "Only mine (pet included)" },
    { value = "all", label = "Everyone's" },
}

local function AddLabel(parent, text, x, y, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function WidgetName(key, suffix)
    local safeKey = key:gsub("[^%w_]", "_")
    return "PlateSmith" .. safeKey:sub(1, 1):upper() .. safeKey:sub(2) .. suffix
end

editorBlueprint.RegisterFields(editorProfiles)

local function Notify(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441PlateSmith:|r " .. tostring(message))
    end
end

Options.Notify = Notify

local function SetEditBoxText(editBox, text)
    if not editBox then return end
    editBox:SetText(text or "")
    if editBox.HighlightText then editBox:HighlightText() end
    if editBox.SetFocus then editBox:SetFocus() end
end

local importSections = {
    { key = "settings", label = "General settings" },
    { key = "layouts", label = "World layouts" },
    { key = "dungeonFriendly", label = "Dungeon friendly names" },
    { key = "styles", label = "Bar styles" },
    { key = "values", label = "Custom values & power" },
    { key = "dungeon", label = "Dungeon enemy profile" },
    { key = "other", label = "Companion-addon data" },
}

local function EnsureBlueprintWindow()
    if Options.blueprintWindow then return Options.blueprintWindow end
    local window = CreateFrame("Frame", "PlateSmithBlueprintWindow", UIParent, "BackdropTemplate")
    window:SetSize(730, 540)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    window:SetScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    window:SetBackdropColor(0.025, 0.03, 0.035, 0.98)
    window:SetBackdropBorderColor(0.58, 0.42, 0.19, 0.95)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -15)
    local instruction = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instruction:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -45)
    instruction:SetWidth(680)
    instruction:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() window:Hide() end)
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -78)
    scroll:SetSize(680, 252)
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetWidth(650)
    editBox:SetHeight(250)
    if editBox.SetMaxLetters then editBox:SetMaxLetters(16384) end
    editBox:SetScript("OnEscapePressed", function() window:Hide() end)
    scroll:SetScrollChild(editBox)
    local selectionLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectionLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -345)
    selectionLabel:SetText("Import only these sections")
    local checkboxes = {}
    for index, section in ipairs(importSections) do
        local checkbox = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        checkbox:SetPoint("TOPLEFT", window, "TOPLEFT", 18 + column * 345, -370 - row * 28)
        local label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetText(section.label)
        checkboxes[section.key] = checkbox
    end
    local selectAll = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    selectAll:SetSize(110, 24)
    selectAll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 15)
    selectAll:SetText("Select all")
    selectAll:SetScript("OnClick", function() editBox:SetFocus(); editBox:HighlightText() end)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
    local action = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    action:SetSize(120, 24)
    action:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 15)
    action:SetText("Import selected")
    action:SetScript("OnClick", function()
        local selection = {}
        for _, section in ipairs(importSections) do
            selection[section.key] = checkboxes[section.key]:GetChecked() and true or false
        end
        local ok, reason = PS.ImportBlueprint(editBox:GetText(), selection)
        if ok then
            Options:Refresh()
            window:Hide()
            Notify("Selected Blueprint sections imported.")
        else
            Notify("Blueprint import failed: " .. tostring(reason or "invalid data"))
        end
    end)
    window.title = title
    window.instruction = instruction
    window.editBox = editBox
    window.scroll = scroll
    window.selectAll = selectAll
    window.selectionLabel = selectionLabel
    window.checkboxes = checkboxes
    window.hint = hint
    window.action = action
    Options.blueprintWindow = window
    window:Hide()
    return window
end

function Options:ShowExportBlueprint()
    if type(PS.ExportShareCode) ~= "function" then
        Notify("Blueprint exporting is not available in this build.")
        return
    end
    local blueprint, reason = PS.ExportShareCode()
    if not blueprint then Notify("Blueprint export failed: " .. tostring(reason)) return end
    local window = EnsureBlueprintWindow()
    window.title:SetText("PlateSmith · Export / Share")
    window.instruction:SetText("Copy this compressed share code with Ctrl+C. Existing PS1 codes still import.")
    window.selectionLabel:Hide()
    for _, checkbox in pairs(window.checkboxes) do checkbox:Hide() end
    window.action:Hide()
    window.hint:SetText("Press Ctrl+C to copy")
    SetEditBoxText(window.editBox, blueprint)
    window.editBox:SetHeight(math.max(250, math.ceil(#blueprint / 78) * 16))
    window:Show()
    SetEditBoxText(window.editBox, blueprint)
end

function Options:ShowImportBlueprint()
    local window = EnsureBlueprintWindow()
    window.title:SetText("PlateSmith · Import Blueprint")
    window.instruction:SetText("Paste a PlateSmith share string, then choose exactly which sections to overwrite.")
    window.selectionLabel:Show()
    for _, checkbox in pairs(window.checkboxes) do checkbox:SetChecked(true); checkbox:Show() end
    window.action:Show()
    window.hint:SetText("Press Ctrl+V to paste")
    window.editBox:SetText("")
    window.editBox:SetHeight(250)
    window:Show()
    window.editBox:SetFocus()
end

function Options:GetEditorLayout()
    return CopyEditorLayout(self.editorLayout)
end

function Options:ApplyEditorLayout(layout)
    local variant = self:CurrentEditorVariant()
    if type(PS.SetLayout) == "function" then PS.SetLayout(layout, self.editorProfile, variant) end
    self.editorLayout = CopyEditorLayout(type(PS.GetLayout) == "function"
        and PS.GetLayout(self.editorProfile, variant) or layout)
    self:RefreshEditorLayout()
end

function Options:RefreshEditorComponentList(settings)
    local content = self.editorListContent
    if not content then return end
    local y = -8
    for _, group in ipairs(editorGroups) do
        local count = 0
        for _, key in ipairs(editorOrder) do
            if EditorGroupForKey(key) == group.key and self:IsEditorComponentRelevant(key, settings) then
                count = count + 1
            end
        end
        local header = self.editorGroupButtons[group.key]
        header:SetShown(count > 0)
        if count > 0 then
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 5, y)
            header.label:SetText(group.label)
            header.expander:SetText(self.editorGroupOpen[group.key] and "-" or "+")
            y = y - 27
        end
        for _, key in ipairs(editorOrder) do
            if EditorGroupForKey(key) == group.key then
                local button = self.editorComponentButtons[key]
                if button then
                    local shown = count > 0 and self.editorGroupOpen[group.key]
                        and self:IsEditorComponentRelevant(key, settings)
                    button:SetShown(shown)
                    if button.visibility and self.editorLayout and self.editorLayout[key] then
                        button.visibility:SetChecked(self.editorLayout[key].visible ~= false)
                    end
                    if shown then
                        button:ClearAllPoints()
                        button:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y)
                        y = y - 23
                    end
                end
            end
        end
        if group.key == "text" and self.editorAddValueButton then
            local canAdd = self.editorProfile == "enemy" or self.editorProfile == "enemyDungeon"
                or self.editorContext == "dungeon" or (settings and settings.friendly == "full")
            local profile = PS.GetPlateProfileSettings(self.editorProfile)
            if canAdd and profile and profile.valueSlots then
                canAdd = false
                for index = 1, VALUE_SLOT_COUNT do
                    if profile.valueSlots["value" .. index].source == "off" then canAdd = true break end
                end
            else
                canAdd = false
            end
            self.editorAddValueButton:SetShown(canAdd and self.editorGroupOpen.text)
            if canAdd and self.editorGroupOpen.text then
                self.editorAddValueButton:ClearAllPoints()
                self.editorAddValueButton:SetPoint("TOPLEFT", content, "TOPLEFT", 21, y - 2)
                y = y - 27
            end
        end
    end
    local contentHeight = math.max(10, -y + 8)
    content:SetHeight(contentHeight)
    local scrollBar = self.editorListScroll and (self.editorListScroll.ScrollBar
        or _G.PlateSmithEditorComponentScrollScrollBar)
    if scrollBar and self.editorListScroll then
        scrollBar:SetShown(contentHeight > self.editorListScroll:GetHeight() + 2)
    end
end

function Options:AddValueSlot()
    local settings = PS.GetSettings()
    if self.editorProfile ~= "enemy" and self.editorProfile ~= "enemyDungeon"
        and self.editorContext ~= "dungeon"
        and (not settings or settings.friendly ~= "full") then return false end
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    if not profile or not profile.valueSlots then return false end
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        if profile.valueSlots[key].source == "off" then
            PS.SetPlateValueSlot(self.editorProfile, key, "source", "healthPercent")
            self:RefreshEditorAppearance(PS.GetSettings())
            self:SelectEditorComponent(key)
            return true
        end
    end
    return false
end

function Options:SetEditorGroupOpen(groupKey, open)
    if self.editorGroupOpen[groupKey] == nil then return false end
    self.editorGroupOpen[groupKey] = open and true or false
    self:RefreshEditorComponentList(PS.GetSettings())
    return true
end

function Options:RefreshEditorInspectorContext()
    local key = self.selectedComponent
    if self.editorComponentTitle then
        self.editorComponentTitle:SetText(key and (editorLabels[key] or key) or "Select a component")
    end
    if self.editorComponentDescription then
        self.editorComponentDescription:SetText(key and (editorDescriptions[key] or "Edit this nameplate component.") or "")
    end
    local selectedContext = key and (editorContextForKey[key] or "other")
    for contextKey, frame in pairs(self.editorContextFrames or {}) do
        frame:SetShown(contextKey == selectedContext)
    end
    if self.editorSurnameControl then
        self.editorSurnameControl:SetShown(key == "name" and self.editorProfile == "friendlyPlayer")
    end
    if self.editorCoordinateX and self.editorCoordinateY then
        local position = key and self.editorLayout and self.editorLayout[key]
        self.editorCoordinateX:SetText(position and tostring(position.x) or "")
        self.editorCoordinateY:SetText(position and tostring(position.y) or "")
    end
    if self.editorComponentScaleSlider then
        local position = key and self.editorLayout and self.editorLayout[key]
        local scale = position and position.scale or 1
        self.refreshingComponentScale = true
        self.editorComponentScaleSlider:SetValue(scale)
        self.refreshingComponentScale = false
        self.editorComponentScaleText:SetText(string.format("%d%%", math.floor(scale * 100 + 0.5)))
        self.editorComponentScaleControls:SetShown(position ~= nil)
    end
    if self.editorLevelFollowName then
        local level = self.editorLayout and self.editorLayout.level
        self.editorLevelFollowName:SetChecked(not level or level.followName ~= false)
    end
    local movable = key and self:IsEditorComponentRelevant(key)
        and editorDefinitions[key] and editorDefinitions[key].movable ~= false
    if self.editorMoveControls then
        self.editorMoveControls:SetShown(movable and self.editorInspectorPage == "components" and true or false)
    end
    if self.editorCoordinateControls then self.editorCoordinateControls:SetShown(movable and true or false) end
    if self.valueControlsRefresh then self.valueControlsRefresh(key) end
end

function Options:RefreshEditorComponentLayers()
    if not self.editorPreviewStage or not self.editorComponents then return end
    local profile = type(PS.GetPlateProfileSettings) == "function"
        and PS.GetPlateProfileSettings(self.editorProfile) or nil
    local base = self.editorPreviewStage:GetFrameLevel()
    for key, component in pairs(self.editorComponents) do
        local slot = key:match("^value%d+$") and profile and profile.valueSlots[key] or nil
        local level = key == self.selectedComponent and 30
            or (slot and (slot.layer == "front" and 20 or 1) or 5)
        component:SetFrameLevel(base + level)
    end
end

function Options:SelectEditorComponent(key)
    if key and not self:IsEditorComponentRelevant(key) then
        key = self:IsEditorComponentRelevant("name") and "name" or nil
    end
    if key and not editorDefinitions[key] then return end
    self.selectedComponent = key
    if self.componentVisibleCheckbox then
        local position = self.editorLayout and self.editorLayout[key]
        self.refreshingVisibility = true
        self.componentVisibleCheckbox:SetChecked(not position or position.visible ~= false)
        self.componentVisibleCheckbox:SetShown(key ~= nil)
        self.refreshingVisibility = false
    end
    for componentKey, component in pairs(self.editorComponents or {}) do
        if component.SetBackdropBorderColor then
            if componentKey == "quest" then
                component:SetBackdropBorderColor(0, 0, 0, 0)
            elseif componentKey == key then
                component:SetBackdropBorderColor(1, 0.72, 0.12, 1)
            else
                component:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.55)
            end
        end
    end
    for componentKey, button in pairs(self.editorComponentButtons or {}) do
        if button.selection then button.selection:SetShown(componentKey == key) end
        if button.visibility and self.editorLayout and self.editorLayout[componentKey] then
            button.visibility:SetChecked(self.editorLayout[componentKey].visible ~= false)
        end
        if button.label then
            if componentKey == key then button.label:SetTextColor(1, 0.82, 0.12)
            else button.label:SetTextColor(0.93, 0.87, 0.73) end
        end
    end
    self:RefreshEditorComponentLayers()
    self:RefreshEditorInspectorContext()
    if key and self.editorWorkspacePage ~= "settings" then self:SetEditorInspectorPage("components") end
end

function Options:SetEditorComponentVisibility(key, visible)
    if not self:IsEditorComponentRelevant(key) then return false end
    local position = self.editorLayout and self.editorLayout[key]
    if not position then return false end
    position.visible = visible and true or false
    if type(PS.SetComponentVisibility) == "function" then
        PS.SetComponentVisibility(key, position.visible, self.editorProfile, self:CurrentEditorVariant())
        self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    else
        self:ApplyEditorLayout(self.editorLayout)
    end
    self:RefreshEditorLayout()
    self:RefreshEditorAppearance(PS.GetSettings())
    self:SelectEditorComponent(key)
    return true
end

function Options:PositionEditorComponent(key)
    local component = self.editorComponents and self.editorComponents[key]
    local position = self.editorLayout and self.editorLayout[key]
    if not component or not position then return end
    component:ClearAllPoints()
    component:SetScale(position.scale or 1)
    if key == "level" and position.followName ~= false
        and self.editorLayout.name and self.editorLayout.name.visible ~= false then
        local name = self.editorComponents.name
        local namePosition = self.editorLayout.name
        component:SetPoint("RIGHT", name.previewText or name, "LEFT", -10 + position.x - self:EditorLevelBaseline(),
            position.y - namePosition.y)
        return
    end
    local anchor = self:EditorValueAnchor(key)
    component:SetPoint("CENTER", anchor or self.editorPreviewStage or self.editorCanvas,
        "CENTER", position.x, position.y)
end

function Options:EditorLevelBaseline()
    return (self.editorProfile == "friendlyPlayer" or self.editorProfile == "friendlyNPC")
        and (self:CurrentEditorVariant() == "names" or self:CurrentEditorVariant() == "dungeon")
        and -85 or -70
end

function Options:EditorLevelCanvasX()
    local position = self.editorLayout and self.editorLayout.level
    local namePosition = self.editorLayout and self.editorLayout.name
    local name = self.editorComponents and self.editorComponents.name
    local level = self.editorComponents and self.editorComponents.level
    if not position or not namePosition or not name or not level then return position and position.x or 0 end
    local text = name.previewText
    local width = text and text.GetStringWidth and text:GetStringWidth() or name:GetWidth()
    return namePosition.x - width * (namePosition.scale or 1) / 2
        - 10 + position.x - self:EditorLevelBaseline() - level:GetWidth() * (position.scale or 1) / 2
end

function Options:EditorLevelLayoutX(canvasX)
    local position = self.editorLayout and self.editorLayout.level
    return (position and position.x or self:EditorLevelBaseline()) + canvasX - self:EditorLevelCanvasX()
end

function Options:EditorValueAnchorKey(key)
    if type(key) ~= "string" or not key:match("^value%d+$") then return nil end
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    local slot = profile and profile.valueSlots and profile.valueSlots[key]
    if not slot or slot.anchor == "canvas" then return nil end
    if slot.whenMissing == "hide" or self.editorLayout[slot.anchor].visible ~= false then
        return slot.anchor
    end
    local fallbacks = slot.anchor == "cast" and { "power", "health" }
        or slot.anchor == "power" and { "health", "cast" } or { "power", "cast" }
    for _, fallback in ipairs(fallbacks) do
        if self.editorLayout[fallback].visible ~= false then return fallback end
    end
    return nil
end

function Options:EditorValueAnchor(key)
    local anchorKey = self:EditorValueAnchorKey(key)
    return anchorKey and self.editorComponents and self.editorComponents[anchorKey] or nil
end

function Options:EditorValueAnchorOffset(key)
    local anchorKey = self:EditorValueAnchorKey(key)
    local position = anchorKey and self.editorLayout and self.editorLayout[anchorKey]
    return position and position.x or 0, position and position.y or 0
end

function Options:SetValueAnchor(key, anchor)
    local position = self.editorLayout and self.editorLayout[key]
    if not position then return false end
    local oldX, oldY = self:EditorValueAnchorOffset(key)
    local absoluteX, absoluteY = position.x + oldX, position.y + oldY
    if not PS.SetPlateValueSlot(self.editorProfile, key, "anchor", anchor) then return false end
    local newX, newY = self:EditorValueAnchorOffset(key)
    PS.SetComponentPosition(key, absoluteX - newX, absoluteY - newY,
        self.editorProfile, self:CurrentEditorVariant())
    self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    self:RefreshEditorLayout()
    self:RefreshEditorInspectorContext()
    return true
end

function Options:UpdateEditorGrid()
    local grid, canvas, stage = self.editorGrid, self.editorCanvas, self.editorPreviewStage
    if not grid or not canvas or not stage then return end
    local zoom = self.editorPreviewZoom or 1
    for _, entry in ipairs(grid.vertical) do
        local line = entry.texture
        line:ClearAllPoints()
        line:SetPoint("CENTER", stage, "CENTER", entry.offset, 0)
        line:SetSize((entry.offset == 0 and 2 or 1) / zoom, (canvas:GetHeight() - 92) / zoom)
    end
    for _, entry in ipairs(grid.horizontal) do
        local line = entry.texture
        line:ClearAllPoints()
        line:SetPoint("CENTER", stage, "CENTER", 0, entry.offset)
        line:SetSize((canvas:GetWidth() - 22) / zoom, (entry.offset == 0 and 2 or 1) / zoom)
    end
end

function Options:SetEditorPreviewZoom(zoom)
    zoom = tonumber(zoom)
    if not zoom then return false end
    self.editorPreviewZoom = math.max(1, math.min(3, math.floor(zoom * 4 + 0.5) / 4))
    if self.editorPreviewStage then self.editorPreviewStage:SetScale(self.editorPreviewZoom) end
    self:UpdateEditorGrid()
    if self.editorZoomText then
        self.editorZoomText:SetText(string.format("%d%%", math.floor(self.editorPreviewZoom * 100 + 0.5)))
    end
    return true
end

function Options:SnapEditorPosition(key, x, y)
    if not self.editorSnap then return x, y end
    local component = self.editorComponents and self.editorComponents[key]
    local profile = type(PS.GetPlateProfileSettings) == "function"
        and PS.GetPlateProfileSettings(self.editorProfile) or PS.GetSettings()
    local halfWidth = ((profile and profile.width or 112) * (profile and profile.scale or 1)) / 2
    local componentHalf = component and component.GetWidth and component:GetWidth() / 2 or 0
    local edge = math.max(0, halfWidth - componentHalf)
    for _, candidate in ipairs({ 0, -edge, edge }) do
        if math.abs(x - candidate) <= 6 then x = candidate break end
    end
    for _, candidate in ipairs({ 0, 16, -13 }) do
        if math.abs(y - candidate) <= 6 then y = candidate break end
    end
    return x, y
end

function Options:SetEditorComponentPosition(key, x, y, snap)
    if not self:IsEditorComponentRelevant(key) or editorDefinitions[key].movable == false then return false end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x ~= x or y ~= y then return false end
    local anchorX, anchorY = self:EditorValueAnchorOffset(key)
    if snap then
        x, y = self:SnapEditorPosition(key, x + anchorX, y + anchorY)
        x, y = x - anchorX, y - anchorY
    end
    x = math.floor(math.max(-280, math.min(280, x)) + 0.5)
    y = math.floor(math.max(-105, math.min(105, y)) + 0.5)
    local position = self.editorLayout[key]
    self.editorLayout[key] = { x = x, y = y, visible = position.visible ~= false,
        scale = position.scale or 1 }
    if type(PS.SetComponentPosition) == "function" then
        PS.SetComponentPosition(key, x, y, self.editorProfile, self:CurrentEditorVariant())
        self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    end
    self:PositionEditorComponent(key)
    self:RefreshEditorInspectorContext()
    return true
end

function Options:SetEditorComponentScale(key, scale)
    if not self:IsEditorComponentRelevant(key) then return false end
    scale = tonumber(scale)
    if not scale or scale ~= scale then return false end
    scale = math.floor(math.max(0.5, math.min(2, scale)) * 20 + 0.5) / 20
    if not PS.SetComponentScale(key, scale, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    self:PositionEditorComponent(key)
    self:RefreshEditorInspectorContext()
    return true
end

function Options:SetEditorLevelFollowName(enabled)
    if not PS.SetLevelFollowName(enabled and true or false, self.editorProfile,
        self:CurrentEditorVariant()) then return false end
    self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    self:PositionEditorComponent("level")
    self:RefreshEditorInspectorContext()
    return true
end

function Options:NudgeEditorComponent(dx, dy)
    local key = self.selectedComponent
    local position = key and self.editorLayout and self.editorLayout[key]
    if not position then return false end
    local step = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and 10 or 1
    return self:SetEditorComponentPosition(key, position.x + dx * step, position.y + dy * step, false)
end

function Options:CaptureEditorComponent(key)
    local component = self.editorComponents and self.editorComponents[key]
    local canvas = self.editorPreviewStage or self.editorCanvas
    if not component or not canvas or not component.GetCenter or not canvas.GetCenter then return end
    local componentX, componentY = component:GetCenter()
    local canvasX, canvasY = canvas:GetCenter()
    if not componentX or not componentY or not canvasX or not canvasY then return end
    local zoom = self.editorPreviewZoom or 1
    local anchorX, anchorY = self:EditorValueAnchorOffset(key)
    self:SetEditorComponentPosition(key, (componentX - canvasX) / zoom - anchorX,
        (componentY - canvasY) / zoom - anchorY, true)
end

function Options:UpdateEditorDrag()
    local drag = self.editorDrag
    if not drag or type(GetCursorPosition) ~= "function" then return end
    local cursorX, cursorY = GetCursorPosition()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then return end
    local stage = self.editorPreviewStage or self.editorCanvas
    local scale = stage and stage.GetEffectiveScale and stage:GetEffectiveScale()
        or self.editorPreviewZoom or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local rawX = drag.startX + (cursorX - drag.cursorX) / scale
    local rawY = drag.startY + (cursorY - drag.cursorY) / scale
    local x, y = rawX, rawY
    if self.editorSnap then x, y = self:SnapEditorPosition(drag.key, x, y) end
    x, y = math.max(-280, math.min(280, x)), math.max(-105, math.min(105, y))
    drag.x, drag.y = x, y
    drag.component:ClearAllPoints()
    drag.component:SetPoint("CENTER", stage, "CENTER", x, y)
    if self.editorCoordinateX and self.editorCoordinateY then
        local anchorX, anchorY = self:EditorValueAnchorOffset(drag.key)
        self.editorCoordinateX:SetText(tostring(math.floor(x - anchorX + 0.5)))
        self.editorCoordinateY:SetText(tostring(math.floor(y - anchorY + 0.5)))
    end
    if self.editorSnapGuideX then
        self.editorSnapGuideX:SetShown(self.editorSnap and math.abs(x - rawX) > 0.01)
        self.editorSnapGuideX:ClearAllPoints()
        self.editorSnapGuideX:SetPoint("CENTER", stage, "CENTER", x, 0)
    end
    if self.editorSnapGuideY then
        self.editorSnapGuideY:SetShown(self.editorSnap and math.abs(y - rawY) > 0.01)
        self.editorSnapGuideY:ClearAllPoints()
        self.editorSnapGuideY:SetPoint("CENTER", stage, "CENTER", 0, y)
    end
end

function Options:StartEditorDrag(key, component)
    if editorDefinitions[key].movable == false then return end
    self:SelectEditorComponent(key)
    if type(GetCursorPosition) ~= "function" then component:StartMoving() return end
    local cursorX, cursorY = GetCursorPosition()
    local position = self.editorLayout and self.editorLayout[key]
    if not position or type(cursorX) ~= "number" or type(cursorY) ~= "number" then return end
    local anchorX, anchorY = self:EditorValueAnchorOffset(key)
    local levelRelative = key == "level" and position.followName ~= false
        and self.editorLayout.name and self.editorLayout.name.visible ~= false
    local startX = levelRelative and self:EditorLevelCanvasX() or position.x + anchorX
    self.editorDrag = { key = key, component = component, cursorX = cursorX, cursorY = cursorY,
        startX = startX, startY = position.y + anchorY,
        x = startX, y = position.y + anchorY, levelRelative = levelRelative }
    component:SetScript("OnUpdate", function() self:UpdateEditorDrag() end)
end

function Options:StopEditorDrag(key, component)
    if editorDefinitions[key].movable == false then return end
    if self.editorDrag and self.editorDrag.key == key then self:UpdateEditorDrag() end
    component:SetScript("OnUpdate", nil)
    if self.editorSnapGuideX then self.editorSnapGuideX:Hide() end
    if self.editorSnapGuideY then self.editorSnapGuideY:Hide() end
    local drag = self.editorDrag
    self.editorDrag = nil
    if drag and drag.key == key then
        local anchorX, anchorY = self:EditorValueAnchorOffset(key)
        self:SetEditorComponentPosition(key,
            drag.levelRelative and self:EditorLevelLayoutX(drag.x) or drag.x - anchorX,
            drag.y - anchorY, false)
    else
        component:StopMovingOrSizing()
        self:CaptureEditorComponent(key)
    end
end

function Options:RefreshEditorLayout()
    if not self.editorCanvas then return end
    for _, key in ipairs(editorOrder) do self:PositionEditorComponent(key) end
end

function Options:ResetEditorLayout()
    local defaults = type(PS.GetDefaultLayout) == "function"
        and PS.GetDefaultLayout(self.editorProfile, self:CurrentEditorVariant()) or editorDefaults
    self:ApplyEditorLayout(defaults)
    self:SelectEditorComponent((self:CurrentEditorVariant() == "names"
        or self:CurrentEditorVariant() == "dungeon") and "name" or "health")
end

Options.studioModel = {
    editorProfiles = editorProfiles,
    editorGroups = editorGroups,
    modeChoices = modeChoices,
    friendlyChoices = friendlyChoices,
    friendlyPvpChoices = friendlyPvpChoices,
    editorThemeChoices = editorThemeChoices,
    targetHighlightChoices = targetHighlightChoices,
    auraSourceChoices = auraSourceChoices,
    AddLabel = AddLabel,
    WidgetName = WidgetName,
}

Options.settingsPanelModel = {
    AddLabel = AddLabel,
    WidgetName = WidgetName,
    CopyEditorLayout = CopyEditorLayout,
    modeChoices = modeChoices,
    friendlyChoices = friendlyChoices,
}

function Options:Refresh()
    local settings = PS.GetSettings()
    if not settings then return end
    if type(PS.GetLayout) == "function" then
        self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
        self:RefreshEditorLayout()
    end
    self.refreshing = true
    for _, control in ipairs(self.controls) do control:Refresh(settings) end
    self.refreshing = false
    self:RefreshEditorAppearance(settings)
    self:ApplyEditorTheme()
end

-- Register display changes at addon load rather than when the editor is opened;
-- Forever may protect new event subscriptions after the UI has entered combat.
local editorDisplayEventFrame = CreateFrame("Frame")
PS._RegisterEvent(editorDisplayEventFrame, "DISPLAY_SIZE_CHANGED", "platesmith.blueprint-editor")
editorDisplayEventFrame:SetScript("OnEvent", function()
    Options:FitVisualEditorToScreen()
end)
