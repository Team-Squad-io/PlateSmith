local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local model = assert(Options.settingsPanelModel, "PlateSmith Options missing")
local AddLabel = model.AddLabel
local WidgetName = model.WidgetName
local CopyEditorLayout = model.CopyEditorLayout
local modeChoices = model.modeChoices
local friendlyChoices = model.friendlyChoices
local spotlightStyleChoices = {
    { value = "box", label = "Outline box" },
    { value = "sides", label = "Side chevrons" },
    { value = "both", label = "Box and chevrons" },
}

local function ChoiceLabel(choices, value)
    for _, choice in ipairs(choices) do
        if choice.value == value then return choice.label end
    end
    return choices[1].label
end

function Options:AddDropdown(parent, label, key, choices, x, y, controlID, helpText)
    AddLabel(parent, label, x + 16, y)
    local dropdownName = WidgetName((controlID or "options") .. "_" .. key, "Dropdown")
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y - 18)
    UIDropDownMenu_SetWidth(dropdown, 180)
    UIDropDownMenu_Initialize(dropdown, function()
        local settings = PS.GetSettings()
        for _, choice in ipairs(choices) do
            local selected = choice
            local info = UIDropDownMenu_CreateInfo()
            info.text = selected.label
            info.checked = settings[key] == selected.value
            if selected.help then
                info.tooltipTitle = selected.label
                info.tooltipText = selected.help
                info.tooltipOnButton = true
            end
            info.func = function()
                PS.SetOption(key, selected.value)
                Options:Refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    if helpText then
        local function ShowHelp(instance)
            if not GameTooltip then return end
            GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(helpText, 1, 0.82, 0.45, true)
            for _, choice in ipairs(choices) do
                if choice.help then
                    GameTooltip:AddLine(choice.label .. ": " .. choice.help, 0.86, 0.86, 0.86, true)
                end
            end
            GameTooltip:Show()
        end
        local function HideHelp() if GameTooltip then GameTooltip:Hide() end end
        dropdown:SetScript("OnEnter", ShowHelp)
        dropdown:SetScript("OnLeave", HideHelp)
        local arrow = _G[dropdownName .. "Button"]
        if arrow and arrow.HookScript then
            arrow:HookScript("OnEnter", ShowHelp)
            arrow:HookScript("OnLeave", HideHelp)
        end
        local helpButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        helpButton:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 220, y - 16)
        helpButton:SetSize(18, 18)
        helpButton:SetText("?")
        helpButton:SetScript("OnEnter", ShowHelp)
        helpButton:SetScript("OnLeave", HideHelp)
    end
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings)
            UIDropDownMenu_SetText(dropdown, ChoiceLabel(choices, settings[key]))
        end,
    }
    return dropdown
end

function Options:AddCheckbox(parent, label, key, x, y, controlID)
    local checkbox = CreateFrame("CheckButton", WidgetName((controlID or "options") .. "_" .. key, "Checkbox"), parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", x, y)
    local text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    text:SetText(label)
    checkbox:SetScript("OnClick", function(instance)
        PS.SetOption(key, instance:GetChecked() and true or false)
        Options:Refresh()
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings) checkbox:SetChecked(settings[key]) end,
    }
    return checkbox
end

function Options:AddSlider(parent, label, key, minimum, maximum, step, x, y, formatter, controlID, sliderWidth)
    sliderWidth = sliderWidth or 230
    AddLabel(parent, label, x, y)
    local valueText = AddLabel(parent, "", x + sliderWidth - 30, y, "GameFontHighlightSmall")
    valueText:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", WidgetName((controlID or "options") .. "_" .. key, "Slider"), parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetSize(sliderWidth, 17)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(_, value)
        if Options.refreshing then return end
        value = math.floor(value / step + 0.5) * step
        PS.SetOption(key, value)
        valueText:SetText(formatter(value))
        Options:Refresh()
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings)
            slider:SetValue(settings[key])
            valueText:SetText(formatter(settings[key]))
        end,
    }
    return slider
end

function Options:AddProfileSlider(parent, label, key, minimum, maximum, step, x, y, formatter, controlID, sliderWidth)
    sliderWidth = sliderWidth or 230
    AddLabel(parent, label, x, y)
    local valueText = AddLabel(parent, "", x + sliderWidth - 30, y, "GameFontHighlightSmall")
    valueText:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", WidgetName((controlID or "profile") .. "_profile_" .. key, "Slider"), parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetSize(sliderWidth, 17)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(_, value)
        if Options.refreshing then return end
        value = math.floor(value / step + 0.5) * step
        PS.SetPlateProfileOption(Options.editorProfile, key, value)
        valueText:SetText(formatter(value))
        Options:Refresh()
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function()
            local profile = PS.GetPlateProfileSettings(Options.editorProfile)
            if not profile then return end
            slider:SetValue(profile[key])
            valueText:SetText(formatter(profile[key]))
        end,
    }
    return slider
end

function Options:AddColour(parent, label, relationship, x, y, controlID)
    AddLabel(parent, label, x + 34, y - 5)
    local swatch = CreateFrame("Button", WidgetName((controlID or "options") .. "_" .. relationship, "Colour"), parent, "BackdropTemplate")
    swatch:SetPoint("TOPLEFT", x, y)
    swatch:SetSize(24, 24)
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    swatch:SetScript("OnClick", function()
        local settings = PS.GetSettings()
        local colour = settings and settings.relationshipColours and settings.relationshipColours[relationship]
        if not colour or not ColorPickerFrame then return end
        local previous = { r = colour.r, g = colour.g, b = colour.b }
        local function ApplyPicker()
            if not ColorPickerFrame.GetColorRGB then return end
            local r, g, b = ColorPickerFrame:GetColorRGB()
            PS.SetRelationshipColour(relationship, r, g, b)
            Options:Refresh()
        end
        local function CancelPicker()
            PS.SetRelationshipColour(relationship, previous.r, previous.g, previous.b)
            Options:Refresh()
        end
        if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = previous.r, g = previous.g, b = previous.b,
                swatchFunc = ApplyPicker,
                cancelFunc = CancelPicker,
            })
        else
            ColorPickerFrame.func = ApplyPicker
            ColorPickerFrame.cancelFunc = CancelPicker
            if ColorPickerFrame.SetColorRGB then ColorPickerFrame:SetColorRGB(previous.r, previous.g, previous.b) end
            ColorPickerFrame:Show()
        end
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings)
            local colour = settings.relationshipColours and settings.relationshipColours[relationship]
            if colour then swatch:SetBackdropColor(colour.r, colour.g, colour.b, 1) end
        end,
    }
    return swatch
end

function PS.CreateOptions()
    if Options.panel then return Options.panel end

    if type(PS.GetLayout) == "function" then
        Options.editorLayout = CopyEditorLayout(PS.GetLayout())
    end

    local panel = CreateFrame("Frame")
    panel.name = "PlateSmith"
    panel:SetSize(640, 610)
    Options.panel = panel

    AddLabel(panel, "PlateSmith", 20, -16, "GameFontNormalLarge")
    local description = AddLabel(panel, "Readable native nameplates with quest and threat context.", 20, -40, "GameFontHighlightSmall")
    description:SetWidth(600)
    description:SetJustifyH("LEFT")

    AddLabel(panel, "Behaviour", 20, -72, "GameFontNormalLarge")
    Options:AddDropdown(panel, "Appearance ownership", "mode", modeChoices, 20, -98)
    Options:AddDropdown(panel, "Friendly units", "friendly", friendlyChoices, 290, -98)
    Options:AddCheckbox(panel, "Show quest markers", "quest", 24, -154)
    Options:AddCheckbox(panel, "Show threat details", "threat", 290, -154)
    Options:AddCheckbox(panel, "Hide Blizzard fallback names outdoors", "hideUnstyledFriendlyNames", 24, -182)
    Options:AddCheckbox(panel, "Colour groups, friends & recent allies", "friendlyRelationshipColours", 290, -182)
    Options:AddCheckbox(panel, "Show player surnames", "showPlayerSurnames", 24, -210)
    Options:AddCheckbox(panel, "Show tagged indicator", "showTagged", 290, -210)
    Options:AddCheckbox(panel, "Dungeon friendly names only", "restrictedFriendlyNamesOnly", 24, -238)
    Options:AddCheckbox(panel, "Show elite and rare marks", "showClassification", 290, -238)

    AddLabel(panel, "Enemy appearance", 20, -272, "GameFontNormalLarge")
    Options:AddSlider(panel, "Overall scale", "scale", 0.7, 1.5, 0.05, 24, -303,
        function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end)
    Options:AddSlider(panel, "Plate width", "width", 80, 200, 2, 300, -303,
        function(value) return string.format("%d px", value) end)
    Options:AddSlider(panel, "Health-bar height", "healthHeight", 6, 20, 1, 24, -352,
        function(value) return string.format("%d px", value) end)
    Options:AddSlider(panel, "Name size", "nameFontSize", 9, 20, 1, 300, -352,
        function(value) return string.format("%d pt", value) end)

    AddLabel(panel, "Threat-window spotlight", 20, -405, "GameFontNormalLarge")
    Options:AddDropdown(panel, "Selected plate", "threatSpotlightStyle", spotlightStyleChoices, 20, -434)
    Options:AddSlider(panel, "Other enemy plates", "threatSpotlightOthersAlpha", 0.3, 1, 0.05, 300, -434,
        function(value) return string.format("%d%% visible", math.floor(value * 100 + 0.5)) end)
    Options:AddSlider(panel, "Spotlight time", "threatSpotlightDuration", 1, 8, 1, 24, -490,
        function(value) return string.format("%d seconds", value) end)
    local spotlightHelp = AddLabel(panel,
        "Click a threat row to spotlight its plate. Dimming affects PlateSmith enemy artwork, not Blizzard's protected plate.",
        300, -490, "GameFontHighlightSmall")
    spotlightHelp:SetWidth(280)
    spotlightHelp:SetJustifyH("LEFT")

    local reset = CreateFrame("Button", "PlateSmithResetButton", panel, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", 24, -558)
    reset:SetSize(140, 24)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function()
        PS.ResetSettings()
        Options:Refresh()
    end)
    Options.resetButton = reset

    local editor = CreateFrame("Button", "PlateSmithVisualEditorButton", panel, "UIPanelButtonTemplate")
    editor:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    editor:SetSize(180, 24)
    editor:SetText("Open Blueprint Editor")
    editor:SetScript("OnClick", function() PS.OpenVisualEditor() end)
    Options.editorButton = editor

    local threatConsole = CreateFrame("Button", "PlateSmithThreatConsoleButton", panel, "UIPanelButtonTemplate")
    threatConsole:SetPoint("LEFT", editor, "RIGHT", 12, 0)
    threatConsole:SetSize(160, 24)
    threatConsole:SetText("Toggle Threat Console")
    threatConsole:SetScript("OnClick", function()
        if PS.ThreatConsole then PS.ThreatConsole:Toggle() end
    end)
    Options.threatConsoleButton = threatConsole

    panel:SetScript("OnShow", function() Options:Refresh() end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        Options.category = category
        Options.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    Options:Refresh()
    return panel
end

function PS.RegisterModuleSettings(id, title, panel)
    if type(id) ~= "string" or type(title) ~= "string" or not panel then
        return nil, "module settings require an id, title, and panel"
    end
    PS.CreateOptions()
    Options.moduleSettings = Options.moduleSettings or {}
    if Options.moduleSettings[id] then return nil, "module settings are already registered" end

    panel.name = title
    if Settings and Settings.RegisterCanvasLayoutSubcategory and Options.category then
        local category = Settings.RegisterCanvasLayoutSubcategory(Options.category, panel, title)
        Settings.RegisterAddOnCategory(category)
        Options.moduleSettings[id] = category
        return category
    elseif InterfaceOptions_AddCategory then
        panel.parent = "PlateSmith"
        InterfaceOptions_AddCategory(panel)
        Options.moduleSettings[id] = panel
        return panel
    end
    return nil, "module settings are unavailable on this client"
end

function PS.OpenOptions()
    PS.CreateOptions()
    if Settings and Settings.OpenToCategory and Options.categoryID then
        Settings.OpenToCategory(Options.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
    end
end
