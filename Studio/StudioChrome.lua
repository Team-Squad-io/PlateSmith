local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")

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

Options.studioChrome = {
    SetStudioButtonState = SetStudioButtonState,
    CreateStudioButton = CreateStudioButton,
    buttonBackdrop = studioButtonBackdrop,
    artSourceX = studioArtSourceX,
    artSourceY = studioArtSourceY,
}
