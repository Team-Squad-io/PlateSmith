local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local catalog = assert(Options.editorCatalog)
local model = assert(Options.studioModel)
local editorOrder = catalog.editorOrder
local editorDefinitions = catalog.editorDefinitions
local valueSourceChoices = catalog.valueSourceChoices
local valueSourceByKey = catalog.valueSourceByKey
local valueAnchorChoices = catalog.valueAnchorChoices
local editorProfiles = model.editorProfiles
local editorGroups = model.editorGroups
local modeChoices = model.modeChoices
local friendlyChoices = model.friendlyChoices
local friendlyPvpChoices = model.friendlyPvpChoices
local editorThemeChoices = model.editorThemeChoices
local targetHighlightChoices = model.targetHighlightChoices
local auraSourceChoices = model.auraSourceChoices
local AddLabel = model.AddLabel
local WidgetName = model.WidgetName
local SetStudioButtonState

local classicUIAddons = { "ClassicUIForever" }

local studioButtonBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

SetStudioButtonState = function(button, selected)
    button.studioSelected = selected and true or false
    local active = button.studioSelected or button.studioHover
    local primary = button.studioVariant == "primary"
    button:SetBackdropColor(primary and 0.075 or 0.095, primary and 0.125 or 0.075,
        primary and 0.16 or 0.050, active and 0.98 or 0.92)
    button:SetBackdropBorderColor(active and 0.91 or 0.48, active and 0.68 or 0.36,
        active and 0.29 or 0.17, 1)
    button.studioRule:SetColorTexture(active and 0.96 or 0.55, active and 0.75 or 0.45,
        active and 0.37 or 0.23, active and 0.95 or 0.65)
    button.label:SetTextColor(active and 1 or 0.85, active and 0.85 or 0.73,
        active and 0.50 or 0.56)
    if button.studioLip then button.studioLip:SetShown(button.studioSelected) end
end

local function CreateStudioButton(parent, text, width, height, variant)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    button:SetBackdrop(studioButtonBackdrop)
    button.studioVariant = variant
    local rule = button:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -3)
    rule:SetPoint("TOPRIGHT", button, "TOPRIGHT", -5, -3)
    rule:SetHeight(1)
    button.studioRule = rule
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText(text)
    button.label = label
    if variant == "tab" then
        local lip = button:CreateTexture(nil, "OVERLAY")
        lip:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, -2)
        lip:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, -2)
        lip:SetHeight(3)
        lip:SetColorTexture(0.12, 0.084, 0.058, 1)
        button.studioLip = lip
    end
    button:SetScript("OnEnter", function(instance)
        instance.studioHover = true
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    button:SetScript("OnLeave", function(instance)
        instance.studioHover = false
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    SetStudioButtonState(button, false)
    return button
end

-- Keep corner scrollwork and the four central emblems intact while stretching only quiet material.
-- The source art occupies 1586x992 inside a 2048x1024 power-of-two texture.
local studioArtSourceX = { 0, 200, 745, 841, 1386, 1586 }
local studioArtSourceY = { 0, 210, 445, 547, 782, 992 }

function Options:LayoutEditorArt()
    local editor, tiles = self.editor, self.editorStudioArtTiles
    if not editor or not tiles then return end
    local width, height = editor:GetWidth(), editor:GetHeight()
    local centerX, centerY = 70, 72
    local middleLeft = math.floor((width - centerX) / 2)
    local middleTop = math.floor((height - centerY) / 2)
    local x = { 0, 140, middleLeft, middleLeft + centerX, width - 140, width }
    local y = { 0, 147, middleTop, middleTop + centerY, height - 147, height }
    for row = 1, 5 do
        for column = 1, 5 do
            local tile = tiles[(row - 1) * 5 + column]
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", editor, "TOPLEFT", x[column], -y[row])
            tile:SetSize(x[column + 1] - x[column], y[row + 1] - y[row])
        end
    end
end

local function IsAddonLoaded(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(name) == true
    end
    return type(IsAddOnLoaded) == "function" and IsAddOnLoaded(name) == true
end

function Options:GetResolvedEditorTheme()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    local requested = settings and settings.editorTheme or "auto"
    if requested == "classic" or requested == "modern" then return requested, requested end
    for _, addon in ipairs(classicUIAddons) do
        if IsAddonLoaded(addon) then return "classic", addon end
    end
    return "classic", nil
end

function Options:ApplyEditorTheme()
    local editor = self.editor
    if not editor then return end
    local resolved, detected = self:GetResolvedEditorTheme()
    local classic = resolved == "classic"
    local editorBackdrop = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true,
        tileSize = 32,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    }
    if not classic then editorBackdrop.edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border" end
    editor:SetBackdrop(editorBackdrop)
    editor:SetBackdropColor(classic and 0.025 or 0.018, classic and 0.021 or 0.024, classic and 0.018 or 0.035, 1)
    editor:SetBackdropBorderColor(classic and 0.72 or 0.20, classic and 0.48 or 0.38, classic and 0.14 or 0.55, 1)
    for _, tile in ipairs(self.editorStudioArtTiles or {}) do tile:SetShown(classic) end

    if self.editorWorkbench then
        self.editorWorkbench:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        self.editorWorkbench:SetBackdropColor(classic and 0.065 or 0.025,
            classic and 0.053 or 0.03, classic and 0.042 or 0.04, 0.98)
        self.editorWorkbench:SetBackdropBorderColor(0.54, 0.39, 0.22, 0.95)
    end
    for _, surface in ipairs(self.editorSurfaces or {}) do
        surface:SetBackdropColor(0, 0, 0, 0)
        surface:SetBackdropBorderColor(0, 0, 0, 0)
    end
    for _, surface in ipairs({ self.editorList, self.editorCanvas, self.editorInspector }) do
        if surface then
            surface:SetBackdropColor(classic and 0.075 or 0.025, classic and 0.066 or 0.03,
                classic and 0.055 or 0.04, 0.98)
            surface:SetBackdropBorderColor(0.48, 0.36, 0.22, 0.9)
        end
    end
    if self.editorCanvas then self.editorCanvas:SetBackdropColor(0.045, 0.043, 0.040, 0.99) end
    if self.editorSettingsWorkspace then
        self.editorSettingsWorkspace:SetBackdropColor(classic and 0.075 or 0.025,
            classic and 0.066 or 0.03, classic and 0.055 or 0.04, 0.98)
        self.editorSettingsWorkspace:SetBackdropBorderColor(0.48, 0.36, 0.22, 0.9)
    end
    for _, panel in ipairs(self.editorSettingsPanels or {}) do
        panel:SetBackdropColor(classic and 0.065 or 0.035,
            classic and 0.053 or 0.037, classic and 0.042 or 0.05, 0.98)
        panel:SetBackdropBorderColor(0.48, 0.36, 0.22, 0.75)
    end
    for _, texture in ipairs(self.editorPanelTextures or {}) do
        texture:SetShown(classic)
    end
    if self.editorFooter then
        self.editorFooter:SetBackdropColor(0.035, 0.039, 0.044, 0.93)
        self.editorFooter:SetBackdropBorderColor(0.49, 0.36, 0.20, 0.45)
    end
    if self.editorTitle then
        self.editorTitle:SetTextColor(classic and 1 or 0.45, classic and 0.82 or 0.82, classic and 0 or 1)
    end
    if self.editorThemeStatus then
        if detected then
            self.editorThemeStatus:SetText("Automatic · ClassicUI Forever detected")
        else
            self.editorThemeStatus:SetText(classic and "Classic editor chrome" or "Modern editor chrome")
        end
    end
end

function Options:SetEditorInspectorPage(page)
    if not self.editorInspectorPages or not self.editorInspectorPages[page] then return end
    local nativeOnly = self.editorContext == "dungeon" and self.editorProfile ~= "enemyDungeon"
    if nativeOnly and page ~= "components" then page = "dungeonFriendly"
    elseif not nativeOnly and page == "dungeonFriendly" then page = "components" end
    self.editorInspectorPage = page
    local settingsOpen = page ~= "components"
    self.editorWorkspacePage = settingsOpen and "settings" or "preview"
    if self.editorSettingsContent then
        self.editorSettingsContent:SetHeight(nativeOnly and 335
            or self.editorProfile == "friendlyPlayer" and 980 or 735)
    end
    if settingsOpen and self.editorSettingsViewport and self.editorSettingsViewport.SetVerticalScroll then
        self.editorSettingsViewport:SetVerticalScroll(0)
    end
    if self.editorList then self.editorList:SetShown(not settingsOpen) end
    if self.editorCanvas then self.editorCanvas:SetShown(not settingsOpen) end
    if self.editorInspector then self.editorInspector:SetShown(not settingsOpen) end
    if self.editorSettingsWorkspace then self.editorSettingsWorkspace:SetShown(settingsOpen) end
    for key, frame in pairs(self.editorInspectorPages) do
        frame:SetShown((key == "components" and not settingsOpen)
            or (nativeOnly and settingsOpen and key == "dungeonFriendly")
            or (not nativeOnly and key ~= "components" and key ~= "dungeonFriendly"
                and settingsOpen and (key ~= "relations" or self.editorProfile == "friendlyPlayer")))
    end
    if self.editorSettingsButton and self.editorSettingsButton.label then
        self.editorSettingsButton.label:SetText(settingsOpen and "Back to preview" or "Plate settings")
        SetStudioButtonState(self.editorSettingsButton, settingsOpen)
        self.editorSettingsButton:Show()
    end
    if self.editorResetButton and self.editorResetButton.label then
        self.editorResetButton.label:SetText(self.editorProfile == "enemyDungeon" and "Use World" or "Reset profile")
        self.editorResetButton:Show()
    end
    if self.resetLayoutButton then self.resetLayoutButton:Show() end
    if self.editorSettingsProfileLabel then
        local labels = { enemy = "World enemies", enemyDungeon = "Dungeon enemies",
            friendlyPlayer = "Players", friendlyNPC = "Friendly NPCs" }
        self.editorSettingsProfileLabel:SetText((labels[self.editorProfile] or "Enemies")
            .. (nativeOnly and " · Blizzard-owned nameplates" or " · Changes apply immediately"))
    end
    if self.editorInspectorHeading then
        self.editorInspectorHeading:SetText("SELECTED COMPONENT")
    end
    self:RefreshEditorInspectorContext()
end

function Options:ReflowVisualEditor()
    local editor, canvas, inspector = self.editor, self.editorCanvas, self.editorInspector
    if not editor or not canvas or not inspector then return end
    local width = editor.GetWidth and editor:GetWidth() or 960
    local height = editor.GetHeight and editor:GetHeight() or 640
    -- Reserve a quiet band above the lower scrollwork for the action rail.
    canvas:SetSize(math.max(400, width - 645), math.max(340, height - 260))
    inspector:ClearAllPoints()
    inspector:SetPoint("TOPLEFT", canvas, "TOPRIGHT", 12, 0)
    inspector:SetSize(294, canvas:GetHeight())
    if self.editorList then self.editorList:SetSize(204, canvas:GetHeight()) end
    if self.editorListScroll then self.editorListScroll:SetSize(176, canvas:GetHeight() - 43) end
    if self.editorComponentScroll then self.editorComponentScroll:SetSize(262, canvas:GetHeight() - 44) end
    if self.editorHeader then self.editorHeader:SetSize(width - 40, 53) end
    if self.editorWorkbench then self.editorWorkbench:SetSize(width - 100, canvas:GetHeight() + 8) end
    if self.editorSettingsWorkspace then self.editorSettingsWorkspace:SetSize(width - 110, canvas:GetHeight()) end
    if self.editorSettingsViewport then
        self.editorSettingsViewport:SetSize(math.min(1000, width - 110), canvas:GetHeight() - 58)
    end
    if self.editorFooter then self.editorFooter:SetSize(width - 140, 42) end
    self:LayoutEditorArt()
    self:UpdateEditorGrid()
end

function Options:FitVisualEditorToScreen()
    local editor = self.editor
    if not editor then return end
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if screenWidth and screenHeight and screenWidth > 0 and screenHeight > 0 then
        local scale = math.min(1, (screenWidth - 40) / editor:GetWidth(),
            (screenHeight - 40) / editor:GetHeight())
        editor:SetScale(math.max(0.65, scale))
    end
    self:ReflowVisualEditor()
end

function PS.CreateVisualEditor()
    if Options.editor then return Options.editor end

    local editor = CreateFrame("Frame", "PlateSmithBlueprintEditor", UIParent, "BackdropTemplate")
    editor:SetSize(1120, 720)
    editor:SetPoint("CENTER")
    editor:SetFrameStrata("DIALOG")
    editor:SetMovable(true)
    if editor.SetResizable then editor:SetResizable(true) end
    if editor.SetResizeBounds then
        editor:SetResizeBounds(1120, 720, 1600, 1000)
    else
        if editor.SetMinResize then editor:SetMinResize(1120, 720) end
        if editor.SetMaxResize then editor:SetMaxResize(1600, 1000) end
    end
    editor:EnableMouse(true)
    editor:RegisterForDrag("LeftButton")
    editor:SetClampedToScreen(true)
    editor:SetScript("OnDragStart", function(instance) instance:StartMoving() end)
    editor:SetScript("OnDragStop", function(instance) instance:StopMovingOrSizing() end)
    editor:SetScript("OnSizeChanged", function() Options:ReflowVisualEditor() end)
    editor:SetScript("OnShow", function()
        Options:FitVisualEditorToScreen()
        Options:Refresh()
        Options:SelectEditorComponent(Options.selectedComponent or "health")
    end)
    Options.editor = editor

    Options.editorStudioArtTiles = {}
    for row = 1, 5 do
        for column = 1, 5 do
            local tile = editor:CreateTexture(nil, "ARTWORK")
            tile:SetTexture("Interface\\AddOns\\PlateSmith\\Media\\PlateSmithStudioFrame.png")
            tile:SetTexCoord(studioArtSourceX[column] / 2048,
                studioArtSourceX[column + 1] / 2048,
                studioArtSourceY[row] / 1024, studioArtSourceY[row + 1] / 1024)
            Options.editorStudioArtTiles[#Options.editorStudioArtTiles + 1] = tile
        end
    end

    local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() editor:Hide() end)

    local resize = CreateFrame("Button", nil, editor)
    resize:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -13, 13)
    resize:SetSize(22, 22)
    local resizeArt = resize:CreateTexture(nil, "OVERLAY")
    resizeArt:SetAllPoints()
    resizeArt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeArt:SetVertexColor(0.87, 0.68, 0.38, 0.95)
    resize:SetScript("OnMouseDown", function()
        if editor.StartSizing then editor:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnMouseUp", function()
        editor:StopMovingOrSizing()
        Options:FitVisualEditorToScreen()
    end)
    resize:SetScript("OnEnter", function(instance)
        if not GameTooltip then return end
        GameTooltip:SetOwner(instance, "ANCHOR_TOP")
        GameTooltip:SetText("Resize Blueprint Studio")
        GameTooltip:Show()
    end)
    resize:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if not editor.SetResizable or not editor.StartSizing then resize:Hide() end
    Options.editorResizeGrip = resize

    local surfaceBackdrop = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    }
    Options.editorSurfaces = {}

    local workbench = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    workbench:SetPoint("TOPLEFT", 50, -116)
    workbench:SetSize(1020, 504)
    workbench:SetFrameLevel(editor:GetFrameLevel() + 1)
    Options.editorWorkbench = workbench

    local header = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 20, -30)
    header:SetSize(920, 50)
    header:SetBackdrop(surfaceBackdrop)
    header:SetFrameLevel(workbench:GetFrameLevel() + 1)
    Options.editorHeader = header
    Options.editorSurfaces[#Options.editorSurfaces + 1] = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", header, "TOP", 0, -7)
    title:SetText("PlateSmith  ·  Blueprint Studio")
    Options.editorTitle = title

    local portraitFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    portraitFrame:SetPoint("TOPLEFT", header, "TOPLEFT", 3, -1)
    portraitFrame:SetSize(50, 50)
    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
    portrait:SetSize(48, 48)
    portrait:SetTexture("Interface\\AddOns\\PlateSmith\\Media\\PlateSmithStudioCrest.tga")
    Options.editorStudioCrest = portrait

    local help = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOP", title, "BOTTOM", 0, -3)
    help:SetText("Build a plate · Select a component to edit it · Drag to position")
    local headerRule = header:CreateTexture(nil, "ARTWORK")
    headerRule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 58, 0)
    headerRule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -6, 0)
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(0.67, 0.45, 0.16, 0.5)

    Options.editorProfileButtons = {}
    local previousTab
    for index, definition in ipairs(editorProfiles) do
        local button = CreateStudioButton(editor, definition.label, 120, 28, "tab")
        if previousTab then
            button:SetPoint("BOTTOMLEFT", previousTab, "BOTTOMRIGHT", 2, 0)
        else
            button:SetPoint("BOTTOMLEFT", workbench, "TOPLEFT", 12, -2)
        end
        button:SetFrameLevel(workbench:GetFrameLevel() + 2)
        button:SetScript("OnClick", function() Options:SetEditorProfile(definition.key) end)
        Options.editorProfileButtons[definition.key] = button
        previousTab = button
    end

    local contextLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contextLabel:SetPoint("LEFT", previousTab, "RIGHT", 18, 0)
    contextLabel:SetText("CONTEXT")
    Options.editorContextLabel = contextLabel
    local contextDropdown = CreateFrame("Frame", "PlateSmithEditorContextDropdown",
        editor, "UIDropDownMenuTemplate")
    contextDropdown:SetPoint("LEFT", contextLabel, "RIGHT", 1, 0)
    contextDropdown:SetFrameLevel(workbench:GetFrameLevel() + 2)
    UIDropDownMenu_SetWidth(contextDropdown, 116)
    UIDropDownMenu_SetText(contextDropdown, "World")
    UIDropDownMenu_Initialize(contextDropdown, function()
        for _, choice in ipairs({ { key = "world", label = "World" },
            { key = "dungeon", label = "Dungeon" } }) do
            local selected = choice
            local info = UIDropDownMenu_CreateInfo()
            info.text = selected.label
            info.checked = Options.editorContext == selected.key
            info.func = function() Options:SetEditorContext(selected.key) end
            UIDropDownMenu_AddButton(info)
        end
    end)
    Options.editorContextDropdown = contextDropdown

    local settingsButton = CreateStudioButton(editor, "Plate settings", 132, 27)
    settingsButton:SetPoint("BOTTOMRIGHT", workbench, "TOPRIGHT", -14, -2)
    Options.editorSettingsButton = settingsButton
    settingsButton:SetScript("OnClick", function()
        Options:SetEditorInspectorPage(Options.editorWorkspacePage == "settings" and "components" or "plate")
    end)

    local list = CreateFrame("Frame", nil, workbench, "BackdropTemplate")
    list:SetPoint("TOPLEFT", editor, "TOPLEFT", 55, -120)
    list:SetSize(204, 470)
    list:SetBackdrop(surfaceBackdrop)
    list:SetFrameLevel(workbench:GetFrameLevel() + 1)
    Options.editorList = list
    Options.editorSurfaces[#Options.editorSurfaces + 1] = list
    Options.editorPanelTextures = {}
    local listTexture = list:CreateTexture(nil, "BACKGROUND")
    listTexture:SetAllPoints()
    listTexture:SetAtlas("Professions-background-summarylist", false)
    listTexture:SetAlpha(0.35)
    Options.editorPanelTextures[#Options.editorPanelTextures + 1] = listTexture
    AddLabel(list, "COMPONENTS", 11, -10, "GameFontNormalSmall")
    local listRule = list:CreateTexture(nil, "ARTWORK")
    listRule:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -29)
    listRule:SetPoint("TOPRIGHT", list, "TOPRIGHT", -11, -29)
    listRule:SetHeight(1)
    listRule:SetColorTexture(0.60, 0.44, 0.24, 0.65)

    local listScroll = CreateFrame("ScrollFrame", "PlateSmithEditorComponentScroll", list, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", list, "TOPLEFT", 5, -31)
    listScroll:SetSize(176, 427)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(172, 500)
    listScroll:SetScrollChild(listContent)
    Options.editorListScroll, Options.editorListContent = listScroll, listContent

    Options.editorGroupButtons = {}
    for _, group in ipairs(editorGroups) do
        local groupKey = group.key
        local button = CreateFrame("Button", nil, listContent)
        button:SetSize(170, 23)
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.11, 0.105, 0.095, 0.85)
        local bottomRule = button:CreateTexture(nil, "BORDER")
        bottomRule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        bottomRule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        bottomRule:SetHeight(1)
        bottomRule:SetColorTexture(0.57, 0.42, 0.23, 0.72)
        local expander = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        expander:SetPoint("LEFT", 6, 0)
        button.expander = expander
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 23, 0)
        button.label = label
        button:SetScript("OnClick", function()
            Options:SetEditorGroupOpen(groupKey, not Options.editorGroupOpen[groupKey])
        end)
        Options.editorGroupButtons[groupKey] = button
    end
    Options.editorComponentButtons = {}
    local canvas = CreateFrame("Frame", nil, workbench, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", editor, "TOPLEFT", 267, -120)
    canvas:SetSize(475, 470)
    canvas:SetBackdrop(surfaceBackdrop)
    canvas:SetFrameLevel(workbench:GetFrameLevel() + 1)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    Options.editorCanvas = canvas
    Options.editorSurfaces[#Options.editorSurfaces + 1] = canvas

    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetPoint("CENTER", canvas, "CENTER", 0, -10)
    stage:SetSize(1, 1)
    stage:SetScale(Options.editorPreviewZoom)
    Options.editorPreviewStage = stage

    local grid = { vertical = {}, horizontal = {} }
    for offset = -270, 270, 30 do
        local line = stage:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(0.73, 0.60, 0.37, offset == 0 and 0.50 or 0.23)
        grid.vertical[#grid.vertical + 1] = { texture = line, offset = offset }
    end
    for offset = -180, 180, 30 do
        local line = stage:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(0.73, 0.60, 0.37, offset == 0 and 0.50 or 0.23)
        grid.horizontal[#grid.horizontal + 1] = { texture = line, offset = offset }
    end
    Options.editorGrid = grid
    Options:UpdateEditorGrid()

    local workspaceTitle = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    workspaceTitle:SetPoint("TOPLEFT", 14, -12)
    workspaceTitle:SetText("PLATE PREVIEW")
    local workspaceHint = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    workspaceHint:SetPoint("TOPRIGHT", -14, -14)
    workspaceHint:SetText("Drag the selected part")
    local previewStatus = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewStatus:SetPoint("TOPLEFT", canvas, "TOPLEFT", 14, -34)
    previewStatus:SetText("Enemy nameplate")
    Options.editorPreviewStatus = previewStatus

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

    Options.editorComponents = {}
    for _, key in ipairs(editorOrder) do Options:CreateEditorComponent(key, editorDefinitions[key]) end
    for _, key in ipairs(editorOrder) do Options:CreateEditorComponentButton(key) end
    local addValue = CreateStudioButton(listContent, "+ Add value", 132, 21)
    addValue:SetScript("OnClick", function() Options:AddValueSlot() end)
    Options.editorAddValueButton = addValue
    Options:RefreshEditorComponentList(PS.GetSettings())

    local zoomOut = CreateStudioButton(canvas, "-", 25, 23)
    zoomOut:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 12, 12)
    zoomOut:SetScript("OnClick", function() Options:SetEditorPreviewZoom(Options.editorPreviewZoom - 0.25) end)
    local zoomText = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoomText:SetPoint("LEFT", zoomOut, "RIGHT", 9, 0)
    Options.editorZoomText = zoomText
    local zoomIn = CreateStudioButton(canvas, "+", 25, 23)
    zoomIn:SetPoint("LEFT", zoomText, "RIGHT", 9, 0)
    zoomIn:SetScript("OnClick", function() Options:SetEditorPreviewZoom(Options.editorPreviewZoom + 0.25) end)
    Options.editorZoomInButton, Options.editorZoomOutButton = zoomIn, zoomOut
    Options:SetEditorPreviewZoom(Options.editorPreviewZoom)

    local snap = CreateFrame("CheckButton", nil, canvas, "UICheckButtonTemplate")
    snap:SetPoint("BOTTOM", canvas, "BOTTOM", -4, 10)
    snap:SetChecked(Options.editorSnap)
    local snapLabel = snap:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    snapLabel:SetPoint("LEFT", snap, "RIGHT", 2, 0)
    snapLabel:SetText("Snap")
    snap:SetScript("OnClick", function(instance) Options.editorSnap = instance:GetChecked() and true or false end)
    Options.editorSnapCheckbox = snap

    local movement = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    movement:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -10, 8)
    movement:SetSize(87, 87)
    movement:SetBackdrop(studioButtonBackdrop)
    movement:SetBackdropColor(0.034, 0.037, 0.039, 0.88)
    movement:SetBackdropBorderColor(0.48, 0.36, 0.20, 0.85)
    local nudgeTexture = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
    local directions = {
        { label = "Left", x = 3, y = 30, rotation = math.pi, dx = -1, dy = 0 },
        { label = "Up", x = 30, y = 57, rotation = math.pi / 2, dx = 0, dy = 1 },
        { label = "Down", x = 30, y = 3, rotation = math.pi * 1.5, dx = 0, dy = -1 },
        { label = "Right", x = 57, y = 30, rotation = 0, dx = 1, dy = 0 },
    }
    local center = movement:CreateTexture(nil, "ARTWORK")
    center:SetPoint("CENTER", movement, "CENTER", 0, 0)
    center:SetSize(7, 7)
    center:SetColorTexture(0.68, 0.46, 0.19, 0.9)
    Options.editorNudgeButtons = {}
    for index, direction in ipairs(directions) do
        local button = CreateFrame("Button", nil, movement)
        button:SetPoint("BOTTOMLEFT", movement, "BOTTOMLEFT", direction.x, direction.y)
        button:SetSize(27, 27)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(nudgeTexture)
        icon:SetRotation(direction.rotation)
        button.icon = icon
        button:SetScript("OnClick", function() Options:NudgeEditorComponent(direction.dx, direction.dy) end)
        button:SetScript("OnEnter", function(instance)
            if not GameTooltip then return end
            GameTooltip:SetOwner(instance, "ANCHOR_TOP")
            GameTooltip:SetText("Move " .. direction.label)
            GameTooltip:AddLine("1 px · Shift-click for 10 px", 1, 0.82, 0.45)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        Options.editorNudgeButtons[index] = button
    end
    Options.editorMoveControls = movement

    local inspector = CreateFrame("Frame", nil, workbench, "BackdropTemplate")
    inspector:SetBackdrop(surfaceBackdrop)
    inspector:SetFrameLevel(workbench:GetFrameLevel() + 1)
    Options.editorInspector = inspector
    Options.editorSurfaces[#Options.editorSurfaces + 1] = inspector
    local inspectorTexture = inspector:CreateTexture(nil, "BACKGROUND")
    inspectorTexture:SetAllPoints()
    inspectorTexture:SetAtlas("Professions-background-summarylist", false)
    inspectorTexture:SetAlpha(0.35)
    Options.editorPanelTextures[#Options.editorPanelTextures + 1] = inspectorTexture

    local settingsWorkspace = CreateFrame("Frame", nil, workbench, "BackdropTemplate")
    settingsWorkspace:SetPoint("TOPLEFT", editor, "TOPLEFT", 55, -120)
    settingsWorkspace:SetSize(1010, 460)
    settingsWorkspace:SetBackdrop(surfaceBackdrop)
    settingsWorkspace:SetFrameLevel(workbench:GetFrameLevel() + 2)
    Options.editorSettingsWorkspace = settingsWorkspace
    AddLabel(settingsWorkspace, "PLATE SETTINGS", 16, -12, "GameFontNormal")
    local settingsProfile = AddLabel(settingsWorkspace, "", 165, -12, "GameFontHighlightSmall")
    Options.editorSettingsProfileLabel = settingsProfile
    local settingsRule = settingsWorkspace:CreateTexture(nil, "ARTWORK")
    settingsRule:SetPoint("TOPLEFT", settingsWorkspace, "TOPLEFT", 14, -34)
    settingsRule:SetPoint("TOPRIGHT", settingsWorkspace, "TOPRIGHT", -14, -34)
    settingsRule:SetHeight(1)
    settingsRule:SetColorTexture(0.60, 0.44, 0.24, 0.65)
    local settingsViewport = CreateFrame("ScrollFrame", "PlateSmithEditorSettingsScroll",
        settingsWorkspace, "UIPanelScrollFrameTemplate")
    settingsViewport:SetPoint("TOP", settingsWorkspace, "TOP", 0, -46)
    settingsViewport:SetSize(1000, 402)
    local settingsContent = CreateFrame("Frame", nil, settingsViewport)
    settingsContent:SetSize(1000, 735)
    settingsViewport:SetScrollChild(settingsContent)
    Options.editorSettingsViewport = settingsViewport
    Options.editorSettingsContent = settingsContent
    Options.editorSettingsPanels = {}

    Options.editorInspectorPages = {}
    local inspectorHeading = AddLabel(inspector, "SELECTED COMPONENT", 15, -11, "GameFontNormal")
    Options.editorInspectorHeading = inspectorHeading
    local inspectorRule = inspector:CreateTexture(nil, "ARTWORK")
    inspectorRule:SetPoint("TOPLEFT", inspector, "TOPLEFT", 13, -31)
    inspectorRule:SetPoint("TOPRIGHT", inspector, "TOPRIGHT", -13, -31)
    inspectorRule:SetHeight(1)
    inspectorRule:SetColorTexture(0.60, 0.44, 0.24, 0.65)
    local componentScroll = CreateFrame("ScrollFrame", "PlateSmithEditorInspectorScroll",
        inspector, "UIPanelScrollFrameTemplate")
    componentScroll:SetPoint("TOPLEFT", inspector, "TOPLEFT", 8, -36)
    componentScroll:SetSize(262, 416)
    local componentsPage = CreateFrame("Frame", nil, componentScroll)
    componentsPage:SetSize(262, 660)
    componentScroll:SetScrollChild(componentsPage)
    Options.editorComponentScroll = componentScroll
    Options.editorInspectorPages.components = componentScroll
    local function AddSettingsPanel(key, x, y, height, width)
        local panel = CreateFrame("Frame", nil, settingsContent, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", x, y)
        panel:SetSize(width or 475, height)
        panel:SetBackdrop(surfaceBackdrop)
        panel:SetBackdropColor(0.065, 0.053, 0.042, 0.98)
        panel:SetBackdropBorderColor(0.48, 0.36, 0.22, 0.75)
        Options.editorInspectorPages[key] = panel
        Options.editorSettingsPanels[#Options.editorSettingsPanels + 1] = panel
        return panel
    end
    AddSettingsPanel("plate", 12, -10, 445)
    AddSettingsPanel("style", 510, -10, 385)
    AddSettingsPanel("auras", 510, -410, 310)
    AddSettingsPanel("relations", 12, -475, 490)
    AddSettingsPanel("dungeonFriendly", 12, -10, 295, 973)
    local function AddSettingsHint(panel, text)
        local hint = AddLabel(panel, text, 286, -55, "GameFontDisableSmall")
        hint:SetWidth(176)
        hint:SetJustifyH("LEFT")
    end
    AddSettingsHint(Options.editorInspectorPages.plate,
        "Choose which plates PlateSmith owns and which details appear. Changes apply to live plates.")
    AddSettingsHint(Options.editorInspectorPages.style,
        "Geometry is saved for the selected profile. Use the tabs above to switch profiles.")
    AddSettingsHint(Options.editorInspectorPages.auras,
        "Buff and debuff rows can be positioned individually in the plate preview.")
    AddSettingsHint(Options.editorInspectorPages.relations,
        "Player colours, PvP marks, and badges apply outdoors. Blizzard owns friendly plates in dungeons.")

    local dungeonFriendly = Options.editorInspectorPages.dungeonFriendly
    AddLabel(dungeonFriendly, "DUNGEON FRIENDLY TEXT TEST", 14, -12, "GameFontNormal")
    local dungeonNotice = AddLabel(dungeonFriendly,
        "Use the same component preview and positions as outdoors, saved separately for Dungeon. "
        .. "Blizzard keeps its own friendly plate; the optional overlay may be blocked by this client.",
        16, -43, "GameFontHighlightSmall")
    dungeonNotice:SetWidth(880)
    dungeonNotice:SetJustifyH("LEFT")
    Options:AddCheckbox(dungeonFriendly, "Names only", "restrictedFriendlyNamesOnly", 14, -95, "editor")
    Options:AddCheckbox(dungeonFriendly, "Blizzard class colours, when available",
        "restrictedFriendlyClassColour", 14, -131, "editor")
    Options:AddCheckbox(dungeonFriendly, "Test editable overlay over native plate",
        "experimentalDungeonFriendlyText", 14, -167, "editor")
    local nativeHint = AddLabel(dungeonFriendly,
        "Off by default. The native plate stays visible, so duplicates are possible. "
        .. "Positions are separate; shared style and value-source controls still affect World. "
        .. "If nothing appears, the client may protect that plate.",
        16, -218, "GameFontDisableSmall")
    nativeHint:SetWidth(880)
    nativeHint:SetJustifyH("LEFT")

    local componentTitle = AddLabel(componentsPage, "Select a component", 12, -8, "GameFontHighlight")
    Options.editorComponentTitle = componentTitle
    local componentDescription = AddLabel(componentsPage, "", 12, -30, "GameFontHighlightSmall")
    componentDescription:SetWidth(255)
    componentDescription:SetJustifyH("LEFT")
    Options.editorComponentDescription = componentDescription
    local visible = CreateFrame("CheckButton", nil, componentsPage, "UICheckButtonTemplate")
    visible:SetPoint("TOPLEFT", 12, -66)
    local visibleText = visible:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    visibleText:SetPoint("LEFT", visible, "RIGHT", 4, 0)
    visibleText:SetText("Show component")
    visible:SetScript("OnClick", function(instance)
        if not Options.refreshingVisibility then
            Options:SetEditorComponentVisibility(Options.selectedComponent, instance:GetChecked() and true or false)
        end
    end)
    Options.componentVisibleCheckbox = visible

    local coordinates = CreateFrame("Frame", nil, componentsPage)
    coordinates:SetPoint("TOPLEFT", componentsPage, "TOPLEFT", 12, -110)
    coordinates:SetSize(250, 80)
    Options.editorCoordinateControls = coordinates
    AddLabel(coordinates, "POSITION", 0, 0, "GameFontNormalSmall")
    local function CreateCoordinateField(label, x)
        AddLabel(coordinates, label, x, -23, "GameFontHighlightSmall")
        local edit = CreateFrame("EditBox", nil, coordinates, "InputBoxTemplate")
        edit:SetPoint("TOPLEFT", coordinates, "TOPLEFT", x, -40)
        edit:SetSize(85, 20)
        edit:SetAutoFocus(false)
        if edit.SetMaxLetters then edit:SetMaxLetters(5) end
        return edit
    end
    local xField = CreateCoordinateField("X", 0)
    local yField = CreateCoordinateField("Y", 116)
    Options.editorCoordinateX, Options.editorCoordinateY = xField, yField
    local function CommitCoordinates()
        local key = Options.selectedComponent
        if not key then return end
        local x = tonumber(xField:GetText())
        local y = tonumber(yField:GetText())
        if not Options:SetEditorComponentPosition(key, x, y, false) then
            Options:RefreshEditorInspectorContext()
        end
    end
    xField:SetScript("OnEnterPressed", CommitCoordinates)
    yField:SetScript("OnEnterPressed", CommitCoordinates)
    xField:SetScript("OnEditFocusLost", CommitCoordinates)
    yField:SetScript("OnEditFocusLost", CommitCoordinates)

    local scaleControls = CreateFrame("Frame", nil, componentsPage)
    scaleControls:SetPoint("TOPLEFT", componentsPage, "TOPLEFT", 12, -200)
    scaleControls:SetSize(250, 62)
    AddLabel(scaleControls, "COMPONENT SCALE", 0, 0, "GameFontNormalSmall")
    local scaleText = AddLabel(scaleControls, "100%", 192, 0, "GameFontHighlightSmall")
    local scaleSlider = CreateFrame("Slider", WidgetName("editor_component_scale", "Slider"),
        scaleControls, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleControls, "TOPLEFT", 0, -24)
    scaleSlider:SetSize(225, 17)
    scaleSlider:SetOrientation("HORIZONTAL")
    scaleSlider:SetMinMaxValues(0.5, 2)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetScript("OnValueChanged", function(_, value)
        if not Options.refreshingComponentScale and Options.selectedComponent then
            Options:SetEditorComponentScale(Options.selectedComponent, value)
        end
    end)
    Options.editorComponentScaleControls = scaleControls
    Options.editorComponentScaleSlider = scaleSlider
    Options.editorComponentScaleText = scaleText

    Options.editorContextFrames = {}
    local function CreateContext(key)
        local frame = CreateFrame("Frame", nil, componentsPage)
        frame:SetPoint("TOPLEFT", componentsPage, "TOPLEFT", 12, -270)
        frame:SetSize(250, 350)
        Options.editorContextFrames[key] = frame
        return frame
    end
    local nameContext = CreateContext("name")
    AddLabel(nameContext, "TEXT", 0, 0, "GameFontNormalSmall")
    Options:AddProfileSlider(nameContext, "Name size", "nameFontSize", 9, 20, 1, 0, -25,
        function(value) return string.format("%d pt", value) end, "selected", 225)
    local surnames = Options:AddCheckbox(nameContext, "Show player surnames", "showPlayerSurnames", -10, -102, "selected")
    Options.editorSurnameControl = surnames

    local levelContext = CreateContext("level")
    local levelHelp = AddLabel(levelContext, "The level can follow the rendered name width, or stay at a fixed canvas position.",
        0, 0, "GameFontHighlightSmall")
    levelHelp:SetWidth(236)
    levelHelp:SetJustifyH("LEFT")
    local levelFollow = CreateFrame("CheckButton", nil, levelContext, "UICheckButtonTemplate")
    levelFollow:SetPoint("TOPLEFT", levelContext, "TOPLEFT", 0, -64)
    local levelFollowText = levelFollow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    levelFollowText:SetPoint("LEFT", levelFollow, "RIGHT", 4, 0)
    levelFollowText:SetText("Follow name width")
    levelFollow:SetScript("OnClick", function(instance)
        Options:SetEditorLevelFollowName(instance:GetChecked() and true or false)
    end)
    local function ShowLevelHelp(instance)
        if not GameTooltip then return end
        GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
        GameTooltip:SetText("Follow name width")
        GameTooltip:AddLine("On: the level keeps its Blueprint gap from the rendered name as names shrink, grow, or change.", 1, 0.82, 0.45, true)
        GameTooltip:AddLine("Off: the level stays at its fixed X/Y position on the plate.", 0.86, 0.86, 0.86, true)
        GameTooltip:Show()
    end
    levelFollow:SetScript("OnEnter", ShowLevelHelp)
    levelFollow:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Options.editorLevelFollowName = levelFollow

    local guildContext = CreateContext("guild")
    local guildHelp = AddLabel(guildContext, "Shows a readable guild name above friendly players outdoors.",
        0, 0, "GameFontHighlightSmall")
    guildHelp:SetWidth(236)
    guildHelp:SetJustifyH("LEFT")

    local healthContext = CreateContext("health")
    AddLabel(healthContext, "BAR GEOMETRY", 0, 0, "GameFontNormalSmall")
    Options:AddProfileSlider(healthContext, "Plate width", "width", 80, 200, 2, 0, -25,
        function(value) return string.format("%d px", value) end, "selected", 225)
    Options:AddProfileSlider(healthContext, "Health-bar height", "healthHeight", 6, 20, 1, 0, -99,
        function(value) return string.format("%d px", value) end, "selected", 225)
    AddLabel(healthContext, "BAR TEXTURE", 0, -149, "GameFontNormalSmall")
    local healthTexture = CreateFrame("Frame", nil, healthContext, "UIDropDownMenuTemplate")
    healthTexture:SetPoint("TOPLEFT", healthContext, "TOPLEFT", -14, -163)
    UIDropDownMenu_SetWidth(healthTexture, 192)
    UIDropDownMenu_Initialize(healthTexture, function()
        local profile = PS.GetPlateProfileSettings(Options.editorProfile)
        for _, choice in ipairs({ { value = "blizzard", label = "Blizzard" },
            { value = "flat", label = "Flat" } }) do
            local option = choice
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.checked = profile.healthTexture == option.value
            info.func = function()
                PS.SetPlateProfileOption(Options.editorProfile, "healthTexture", option.value)
                Options:Refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    Options.controls[#Options.controls + 1] = {
        Refresh = function()
            local profile = PS.GetPlateProfileSettings(Options.editorProfile)
            UIDropDownMenu_SetText(healthTexture, profile.healthTexture == "flat" and "Flat" or "Blizzard")
        end,
    }

    local powerContext = CreateContext("power")
    AddLabel(powerContext, "POWER BAR", 0, 0, "GameFontNormalSmall")
    local powerHelp = AddLabel(powerContext,
        "Displays this unit's active resource, such as mana. Hidden when the client reports no power.",
        0, -26, "GameFontHighlightSmall")
    powerHelp:SetWidth(235)
    powerHelp:SetJustifyH("LEFT")
    Options:AddProfileSlider(powerContext, "Bar height", "powerHeight", 3, 14, 1, 0, -96,
        function(value) return string.format("%d px", value) end, "selected", 225)
    AddLabel(healthContext, "BAR COLOUR", 0, -209, "GameFontNormalSmall")
    local colourMode = CreateFrame("CheckButton", nil, healthContext, "UICheckButtonTemplate")
    colourMode:SetPoint("TOPLEFT", healthContext, "TOPLEFT", -9, -225)
    local colourModeLabel = colourMode:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    colourModeLabel:SetPoint("LEFT", colourMode, "RIGHT", 3, 0)
    colourModeLabel:SetText("Custom colour")
    local colourSwatch = CreateFrame("Button", nil, healthContext, "BackdropTemplate")
    colourSwatch:SetPoint("LEFT", colourModeLabel, "RIGHT", 10, 0)
    colourSwatch:SetSize(23, 22)
    colourSwatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    colourSwatch:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    colourMode:SetScript("OnClick", function(instance)
        PS.SetPlateProfileOption(Options.editorProfile, "healthColourMode",
            instance:GetChecked() and "custom" or "automatic")
        Options:Refresh()
    end)
    colourSwatch:SetScript("OnClick", function()
        local profile = PS.GetPlateProfileSettings(Options.editorProfile)
        local colour = profile and profile.healthColour
        if not colour or not ColorPickerFrame then return end
        local previous = { r = colour.r, g = colour.g, b = colour.b, mode = profile.healthColourMode }
        local function ApplyPicker()
            if not ColorPickerFrame.GetColorRGB then return end
            local r, g, b = ColorPickerFrame:GetColorRGB()
            PS.SetPlateProfileHealthColour(Options.editorProfile, r, g, b)
            Options:Refresh()
        end
        local function CancelPicker()
            PS.SetPlateProfileHealthColour(Options.editorProfile, previous.r, previous.g, previous.b)
            PS.SetPlateProfileOption(Options.editorProfile, "healthColourMode", previous.mode)
            Options:Refresh()
        end
        if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
            ColorPickerFrame:SetupColorPickerAndShow({ r = previous.r, g = previous.g, b = previous.b,
                swatchFunc = ApplyPicker, cancelFunc = CancelPicker })
        else
            ColorPickerFrame.func = ApplyPicker
            ColorPickerFrame.cancelFunc = CancelPicker
            if ColorPickerFrame.SetColorRGB then
                ColorPickerFrame:SetColorRGB(previous.r, previous.g, previous.b)
            end
            ColorPickerFrame:Show()
        end
    end)
    Options.controls[#Options.controls + 1] = {
        Refresh = function()
            local profile = PS.GetPlateProfileSettings(Options.editorProfile)
            colourMode:SetChecked(profile.healthColourMode == "custom")
            colourSwatch:SetBackdropColor(profile.healthColour.r, profile.healthColour.g,
                profile.healthColour.b, 1)
        end,
    }

    local castContext = CreateContext("cast")
    AddLabel(castContext, "CAST BAR", 0, 0, "GameFontNormalSmall")
    Options:AddProfileSlider(castContext, "Plate width", "width", 80, 200, 2, 0, -25,
        function(value) return string.format("%d px", value) end, "cast", 225)

    local questContext = CreateContext("quest")
    AddLabel(questContext, "QUEST MARKER", 0, 0, "GameFontNormalSmall")
    Options:AddCheckbox(questContext, "Show quest markers", "quest", -10, -30, "selected")
    local threatContext = CreateContext("threat")
    AddLabel(threatContext, "THREAT", 0, 0, "GameFontNormalSmall")
    Options:AddCheckbox(threatContext, "Show threat details", "threat", -10, -30, "selected")
    local valueContext = CreateContext("value")
    valueContext:SetHeight(390)
    AddLabel(valueContext, "LIVE VALUE", 0, 0, "GameFontNormalSmall")
    local valueSource = CreateFrame("Frame", nil, valueContext, "UIDropDownMenuTemplate")
    valueSource:SetPoint("TOPLEFT", valueContext, "TOPLEFT", -16, -16)
    UIDropDownMenu_SetWidth(valueSource, 204)
    UIDropDownMenu_Initialize(valueSource, function()
        local key = Options.selectedComponent
        local profile = PS.GetPlateProfileSettings(Options.editorProfile)
        local slot = key and profile and profile.valueSlots and profile.valueSlots[key]
        for _, choice in ipairs(valueSourceChoices) do
            local selected = choice
            local info = UIDropDownMenu_CreateInfo()
            info.text = selected.label
            info.checked = slot and slot.source == selected.value
            info.func = function()
                if PS.SetPlateValueSlot(Options.editorProfile, key, "source", selected.value) then
                    Options:RefreshEditorAppearance(PS.GetSettings())
                    Options:SelectEditorComponent(key)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    AddLabel(valueContext, "ATTACH TO", 0, -79, "GameFontNormalSmall")
    local valueAnchor = CreateFrame("Frame", nil, valueContext, "UIDropDownMenuTemplate")
    valueAnchor:SetPoint("TOPLEFT", valueContext, "TOPLEFT", -16, -95)
    UIDropDownMenu_SetWidth(valueAnchor, 204)
    UIDropDownMenu_Initialize(valueAnchor, function()
        local key = Options.selectedComponent
        local profile = PS.GetPlateProfileSettings(Options.editorProfile)
        local slot = key and profile and profile.valueSlots and profile.valueSlots[key]
        for _, choice in ipairs(valueAnchorChoices) do
            local selected = choice
            local info = UIDropDownMenu_CreateInfo()
            info.text = selected.label
            info.checked = slot and slot.anchor == selected.value
            info.func = function()
                Options:SetValueAnchor(key, selected.value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    local valueMissing = CreateFrame("CheckButton", nil, valueContext, "UICheckButtonTemplate")
    valueMissing:SetPoint("TOPLEFT", valueContext, "TOPLEFT", 0, -137)
    local valueMissingText = valueMissing:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueMissingText:SetPoint("LEFT", valueMissing, "RIGHT", 3, 0)
    valueMissingText:SetText("Hide if attached bar is absent")
    valueMissing:SetScript("OnClick", function(instance)
        local key = Options.selectedComponent
        if key and key:match("^value%d+$")
            and PS.SetPlateValueSlot(Options.editorProfile, key, "whenMissing",
                instance:GetChecked() and "hide" or "fallback") then
            Options:RefreshEditorLayout()
            Options:RefreshEditorAppearance(PS.GetSettings())
        end
    end)
    AddLabel(valueContext, "TEXT SIZE", 0, -181, "GameFontNormalSmall")
    local valueSize = CreateFrame("Slider", nil, valueContext, "OptionsSliderTemplate")
    valueSize:SetPoint("TOPLEFT", valueContext, "TOPLEFT", 0, -207)
    valueSize:SetSize(210, 17)
    valueSize:SetOrientation("HORIZONTAL")
    valueSize:SetMinMaxValues(7, 18)
    valueSize:SetValueStep(1)
    valueSize:SetObeyStepOnDrag(true)
    local valueSizeText = AddLabel(valueContext, "", 205, -181, "GameFontHighlightSmall")
    valueSizeText:SetJustifyH("RIGHT")
    valueSize:SetScript("OnValueChanged", function(_, size)
        if Options.refreshingValue then return end
        local key = Options.selectedComponent
        if not key or not key:match("^value%d+$") then return end
        size = math.floor(size + 0.5)
        if PS.SetPlateValueSlot(Options.editorProfile, key, "fontSize", size) then
            valueSizeText:SetText(size .. " pt")
            Options:RefreshEditorAppearance(PS.GetSettings())
        end
    end)
    AddLabel(valueContext, "TEXT COLOUR", 0, -239, "GameFontNormalSmall")
    local valueColour = CreateFrame("Button", nil, valueContext, "BackdropTemplate")
    valueColour:SetPoint("TOPLEFT", valueContext, "TOPLEFT", 105, -235)
    valueColour:SetSize(25, 22)
    valueColour:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    valueColour:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    valueColour:SetScript("OnClick", function()
        local key = Options.selectedComponent
        local profile = PS.GetPlateProfileSettings(Options.editorProfile)
        local slot = key and profile and profile.valueSlots and profile.valueSlots[key]
        if not slot or not ColorPickerFrame then return end
        local previous = { r = slot.colour.r, g = slot.colour.g, b = slot.colour.b }
        local function ApplyPicker()
            if not ColorPickerFrame.GetColorRGB then return end
            local r, g, b = ColorPickerFrame:GetColorRGB()
            PS.SetPlateValueSlot(Options.editorProfile, key, "colour", { r = r, g = g, b = b })
            Options:RefreshEditorAppearance(PS.GetSettings())
            Options:RefreshEditorInspectorContext()
        end
        local function CancelPicker()
            PS.SetPlateValueSlot(Options.editorProfile, key, "colour", previous)
            Options:RefreshEditorAppearance(PS.GetSettings())
            Options:RefreshEditorInspectorContext()
        end
        if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
            ColorPickerFrame:SetupColorPickerAndShow({ r = previous.r, g = previous.g, b = previous.b,
                swatchFunc = ApplyPicker, cancelFunc = CancelPicker })
        else
            ColorPickerFrame.func = ApplyPicker
            ColorPickerFrame.cancelFunc = CancelPicker
            if ColorPickerFrame.SetColorRGB then
                ColorPickerFrame:SetColorRGB(previous.r, previous.g, previous.b)
            end
            ColorPickerFrame:Show()
        end
    end)
    AddLabel(valueContext, "LAYER", 0, -274, "GameFontNormalSmall")
    local sendBack = CreateStudioButton(valueContext, "Behind", 98, 23)
    sendBack:SetPoint("TOPLEFT", valueContext, "TOPLEFT", 0, -294)
    local bringFront = CreateStudioButton(valueContext, "In front", 98, 23)
    bringFront:SetPoint("LEFT", sendBack, "RIGHT", 8, 0)
    local function SetValueLayer(layer)
        local key = Options.selectedComponent
        if key and key:match("^value%d+$")
            and PS.SetPlateValueSlot(Options.editorProfile, key, "layer", layer) then
            Options:RefreshEditorAppearance(PS.GetSettings())
            Options:RefreshEditorInspectorContext()
        end
    end
    sendBack:SetScript("OnClick", function() SetValueLayer("back") end)
    bringFront:SetScript("OnClick", function() SetValueLayer("front") end)
    Options.editorValueLayerButtons = { back = sendBack, front = bringFront }
    local removeValue = CreateStudioButton(valueContext, "Remove value", 128, 24)
    removeValue:SetPoint("TOPLEFT", valueContext, "TOPLEFT", 0, -336)
    removeValue:SetScript("OnClick", function()
        local key = Options.selectedComponent
        if key and key:match("^value%d+$")
            and PS.SetPlateValueSlot(Options.editorProfile, key, "source", "off") then
            Options:RefreshEditorAppearance(PS.GetSettings())
        end
    end)
    Options.valueControlsRefresh = function(key)
        if not key or not key:match("^value%d+$") then return end
        local profile = PS.GetPlateProfileSettings(Options.editorProfile)
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if not slot then return end
        UIDropDownMenu_SetText(valueSource, valueSourceByKey[slot.source]
            and valueSourceByKey[slot.source].label or "Choose value")
        for _, choice in ipairs(valueAnchorChoices) do
            if choice.value == slot.anchor then UIDropDownMenu_SetText(valueAnchor, choice.label) break end
        end
        valueMissing:SetChecked(slot.whenMissing == "hide")
        if valueMissing.SetEnabled then valueMissing:SetEnabled(slot.anchor ~= "canvas") end
        Options.refreshingValue = true
        valueSize:SetValue(slot.fontSize)
        Options.refreshingValue = false
        valueSizeText:SetText(slot.fontSize .. " pt")
        valueColour:SetBackdropColor(slot.colour.r, slot.colour.g, slot.colour.b, 1)
        SetStudioButtonState(sendBack, slot.layer == "back")
        SetStudioButtonState(bringFront, slot.layer ~= "back")
    end
    local taggedContext = CreateContext("tagged")
    AddLabel(taggedContext, "TAGGED INDICATOR", 0, 0, "GameFontNormalSmall")
    Options:AddCheckbox(taggedContext, "Show tagged indicator", "showTagged", -10, -30, "selected")
    local raidContext = CreateContext("raidIcon")
    local raidHelp = AddLabel(raidContext, "Uses Blizzard's raid target icon when one is assigned.",
        0, 0, "GameFontHighlightSmall")
    raidHelp:SetWidth(236)
    raidHelp:SetJustifyH("LEFT")

    local relationContext = CreateContext("relationshipIcon")
    AddLabel(relationContext, "FRIENDLY PLAYER BADGES", 0, 0, "GameFontNormalSmall")
    Options:AddCheckbox(relationContext, "Above group members", "showGroupIcon", -10, -29, "selected")
    Options:AddCheckbox(relationContext, "Above guild members", "showGuildIcon", -10, -62, "selected")
    local pvpContext = CreateContext("pvpIcon")
    AddLabel(pvpContext, "FRIENDLY PLAYER PVP", 0, 0, "GameFontNormalSmall")
    Options:AddDropdown(pvpContext, "Flagged-player display", "friendlyPvpStyle", friendlyPvpChoices, -14, -25, "selected")
    local classificationContext = CreateContext("classification")
    AddLabel(classificationContext, "ENEMY CLASSIFICATION", 0, 0, "GameFontNormalSmall")
    Options:AddCheckbox(classificationContext, "Show elite and rare marks", "showClassification", -10, -29, "selected")
    local classificationHelp = AddLabel(classificationContext,
        "+ Elite  ·  R Rare  ·  R+ Rare elite  ·  BOSS World boss",
        0, -72, "GameFontHighlightSmall")
    classificationHelp:SetWidth(236)
    classificationHelp:SetJustifyH("LEFT")
    for _, definition in ipairs({
        { key = "buffs", title = "BUFF ROW", show = "showBuffs", source = "buffSource" },
        { key = "debuffs", title = "DEBUFF ROW", show = "showDebuffs", source = "debuffSource" },
    }) do
        local context = CreateContext(definition.key)
        AddLabel(context, definition.title, 0, 0, "GameFontNormalSmall")
        Options:AddCheckbox(context, "Show row", definition.show, -10, -28, "selected")
        Options:AddDropdown(context, "Source", definition.source, auraSourceChoices, -14, -71, "selected")
    end
    local otherContext = CreateContext("other")
    local otherHelp = AddLabel(otherContext, "This component can be shown, moved, and positioned.",
        0, 0, "GameFontHighlightSmall")
    otherHelp:SetWidth(236)
    otherHelp:SetJustifyH("LEFT")

    local platePage = Options.editorInspectorPages.plate
    AddLabel(platePage, "BEHAVIOUR & DISPLAY", 12, -8, "GameFontNormalSmall")
    Options:AddDropdown(platePage, "Theme", "editorTheme", editorThemeChoices, -2, -28, "editor")
    Options:AddDropdown(platePage, "Appearance ownership", "mode", modeChoices, -2, -86, "editor")
    Options:AddDropdown(platePage, "Friendly units", "friendly", friendlyChoices, -2, -144, "editor")
    Options:AddCheckbox(platePage, "Show quest markers", "quest", 4, -184, "editor")
    Options:AddCheckbox(platePage, "Show threat details", "threat", 4, -210, "editor")
    Options:AddCheckbox(platePage, "Show tagged indicator", "showTagged", 4, -236, "editor")
    Options:AddCheckbox(platePage, "Hide unstyled names outdoors", "hideUnstyledFriendlyNames", 4, -262, "editor")
    Options:AddCheckbox(platePage, "Colour social relationships", "friendlyRelationshipColours", 4, -288, "editor")
    Options:AddCheckbox(platePage, "Show player surnames", "showPlayerSurnames", 4, -314, "editor")
    Options:AddCheckbox(platePage, "Dungeon friendly names only", "restrictedFriendlyNamesOnly", 4, -340, "editor")
    Options:AddCheckbox(platePage, "Show elite and rare marks", "showClassification", 4, -366, "editor")
    local themeStatus = AddLabel(platePage, "", 12, -398, "GameFontDisableSmall")
    themeStatus:SetWidth(246)
    themeStatus:SetJustifyH("LEFT")
    Options.editorThemeStatus = themeStatus

    local auraPage = Options.editorInspectorPages.auras
    AddLabel(auraPage, "AURA ROWS", 12, -8, "GameFontNormalSmall")
    Options:AddCheckbox(auraPage, "Show buffs", "showBuffs", 4, -38, "editor")
    Options:AddDropdown(auraPage, "Buff source", "buffSource", auraSourceChoices, -2, -78, "editor")
    Options:AddCheckbox(auraPage, "Show debuffs", "showDebuffs", 4, -154, "editor")
    Options:AddDropdown(auraPage, "Debuff source", "debuffSource", auraSourceChoices, -2, -194, "editor")
    local auraHelp = AddLabel(auraPage,
        "Up to four icons per row. Drag Buffs or Debuffs in Components to position them.",
        12, -280, "GameFontDisableSmall")
    auraHelp:SetWidth(246)
    auraHelp:SetJustifyH("LEFT")

    local stylePage = Options.editorInspectorPages.style
    AddLabel(stylePage, "PLATE GEOMETRY", 12, -8, "GameFontNormalSmall")
    Options:AddProfileSlider(stylePage, "Overall scale", "scale", 0.7, 1.5, 0.05, 14, -42,
        function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end, "editor", 238)
    Options:AddProfileSlider(stylePage, "Plate width", "width", 80, 200, 2, 14, -112,
        function(value) return string.format("%d px", value) end, "editor", 238)
    Options:AddProfileSlider(stylePage, "Health-bar height", "healthHeight", 6, 20, 1, 14, -182,
        function(value) return string.format("%d px", value) end, "editor", 238)
    Options:AddProfileSlider(stylePage, "Name size", "nameFontSize", 9, 20, 1, 14, -252,
        function(value) return string.format("%d pt", value) end, "editor", 238)
    Options:AddDropdown(stylePage, "Selected target", "targetHighlightStyle", targetHighlightChoices,
        -2, -325, "editor", "Choose a glow around the selected plate's text and visible bars. It appears only on PlateSmith's own artwork, not on the 3D character model or Blizzard-owned plates.")

    local relationsPage = Options.editorInspectorPages.relations
    AddLabel(relationsPage, "FRIENDLY PLAYER RELATIONSHIPS", 12, -8, "GameFontNormalSmall")
    Options:AddCheckbox(relationsPage, "Show icon above group members", "showGroupIcon", 4, -38, "editor")
    Options:AddCheckbox(relationsPage, "Show icon above guild members", "showGuildIcon", 4, -68, "editor")
    Options:AddColour(relationsPage, "Group members", "group", 14, -112, "editor")
    Options:AddColour(relationsPage, "Guild members", "guild", 14, -162, "editor")
    Options:AddColour(relationsPage, "Friends", "friend", 14, -212, "editor")
    Options:AddColour(relationsPage, "Recent allies", "recent", 14, -262, "editor")
    Options:AddDropdown(relationsPage, "PvP-flagged players", "friendlyPvpStyle", friendlyPvpChoices, -2, -302, "editor")
    Options:AddColour(relationsPage, "PvP name colour", "pvp", 14, -372, "editor")
    local relationHelp = AddLabel(relationsPage, "PvP colour takes priority over social colour when selected. Icons use Blizzard's faction art. These apply outdoors; Blizzard protects friendly plates in dungeons and raids.", 14, -420, "GameFontDisableSmall")
    relationHelp:SetWidth(244)
    relationHelp:SetJustifyH("LEFT")

    local footer = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 70, 75)
    footer:SetSize(980, 42)
    footer:SetBackdrop(studioButtonBackdrop)
    footer:SetFrameLevel(workbench:GetFrameLevel() + 1)
    Options.editorFooter = footer

    local resetAll = CreateStudioButton(footer, "Reset profile", 120, 26)
    resetAll:SetPoint("LEFT", footer, "LEFT", 12, 0)
    resetAll:SetScript("OnClick", function()
        if Options.editorProfile == "enemyDungeon" then
            PS.SetDungeonEnemyProfile(nil)
            Options:SetEditorProfile("enemy")
        else
            PS.ResetSettings()
        end
        Options:Refresh()
    end)

    local resetLayout = CreateStudioButton(footer, "Reset layout", 120, 26)
    resetLayout:SetPoint("LEFT", resetAll, "RIGHT", 9, 0)
    resetLayout:SetScript("OnClick", function() Options:ResetEditorLayout() end)

    local done = CreateStudioButton(footer, "Done", 92, 26, "primary")
    done:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
    done:SetScript("OnClick", function() editor:Hide() end)
    Options.editorDoneButton = done

    local import = CreateStudioButton(footer, "Import Blueprint", 140, 26)
    import:SetPoint("RIGHT", done, "LEFT", -9, 0)
    import:SetScript("OnClick", function() Options:ShowImportBlueprint() end)

    local export = CreateStudioButton(footer, "Export / Share", 140, 26)
    export:SetPoint("RIGHT", import, "LEFT", -9, 0)
    export:SetScript("OnClick", function() Options:ShowExportBlueprint() end)

    Options.editorResetButton = resetAll
    Options.resetLayoutButton = resetLayout
    Options.exportBlueprintButton = export
    Options.importBlueprintButton = import
    Options:ReflowVisualEditor()
    Options:RefreshEditorLayout()
    Options:RefreshEditorAppearance(PS.GetSettings())
    Options:SetEditorInspectorPage("components")
    Options:SelectEditorComponent("health")
    Options:ApplyEditorTheme()
    Options:SetEditorProfile("enemy")
    editor:Hide()
    return editor
end

function PS.OpenVisualEditor()
    local editor = PS.CreateVisualEditor()
    editor:Show()
end

Options.SetStudioButtonState = SetStudioButtonState
