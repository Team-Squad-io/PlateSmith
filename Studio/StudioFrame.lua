local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local catalog = assert(Options.editorCatalog)
local model = assert(Options.studioModel)
local editorOrder = catalog.editorOrder
local editorDefinitions = catalog.editorDefinitions
local editorProfiles = model.editorProfiles
local editorGroups = model.editorGroups
local AddLabel = model.AddLabel
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")
local SetStudioButtonState = chrome.SetStudioButtonState
local CreateStudioButton = chrome.CreateStudioButton
local studioButtonBackdrop = chrome.buttonBackdrop
local studioArtSourceX = chrome.artSourceX
local studioArtSourceY = chrome.artSourceY

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

    Options:BuildStudioInspector(editor, workbench, surfaceBackdrop)

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
