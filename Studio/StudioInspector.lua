local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local catalog = assert(Options.editorCatalog)
local model = assert(Options.studioModel)
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")
local editorDefinitions = catalog.editorDefinitions
local valueSourceChoices = catalog.valueSourceChoices
local valueSourceByKey = catalog.valueSourceByKey
local valueAnchorChoices = catalog.valueAnchorChoices
local modeChoices = model.modeChoices
local friendlyChoices = model.friendlyChoices
local friendlyPvpChoices = model.friendlyPvpChoices
local editorThemeChoices = model.editorThemeChoices
local targetHighlightChoices = model.targetHighlightChoices
local auraSourceChoices = model.auraSourceChoices
local AddLabel = model.AddLabel
local WidgetName = model.WidgetName
local CreateStudioButton = chrome.CreateStudioButton
local SetStudioButtonState = chrome.SetStudioButtonState

function Options:BuildStudioInspector(editor, workbench, surfaceBackdrop)
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

end
