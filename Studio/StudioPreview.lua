local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local catalog = assert(Options.editorCatalog)
local model = assert(Options.studioModel)
local editorDefaults = catalog.editorDefaults
local editorLabels = catalog.editorLabels
local editorDefinitions = catalog.editorDefinitions
local editorProfiles = model.editorProfiles
local WidgetName = model.WidgetName
local CopyEditorLayout = assert(Options.editorBlueprint).CopyLayout
local Notify = assert(Options.Notify)
local editorProfileSet = { enemy = true, enemyDungeon = true, friendlyPlayer = true, friendlyNPC = true }

local function IsReadableValue(value)
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        return ok and readable == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return not ok or secret ~= true
    end
    return true
end

local function CurrentCharacterName()
    local readers = {
        function()
            return type(GetUnitName) == "function" and GetUnitName("player", true) or nil
        end,
        function()
            return type(UnitPVPName) == "function" and UnitPVPName("player") or nil
        end,
        function()
            return type(UnitName) == "function" and UnitName("player") or nil
        end,
    }
    for _, reader in ipairs(readers) do
        local ok, name = pcall(reader)
        if ok and IsReadableValue(name) and type(name) == "string" and name ~= "" and name ~= "player" then
            return name
        end
    end
    return "Your Character"
end

local function MakeEditorComponent(parent, key, width, height)
    local component = CreateFrame("Button", WidgetName(key, "EditorComponent"), parent, "BackdropTemplate")
    component:SetSize(width, height)
    component:SetMovable(editorDefinitions[key].movable ~= false)
    component:EnableMouse(true)
    component:RegisterForDrag("LeftButton")
    component:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    component:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.55)
    component:SetScript("OnMouseDown", function() Options:SelectEditorComponent(key) end)
    component:SetScript("OnDragStart", function(instance) Options:StartEditorDrag(key, instance) end)
    component:SetScript("OnDragStop", function(instance) Options:StopEditorDrag(key, instance) end)
    return component
end

function Options:IsEditorComponentRelevant(key, settings)
    if not editorDefinitions[key] then return false end
    settings = settings or (type(PS.GetSettings) == "function" and PS.GetSettings())
    local friendlyMode = self.editorContext == "dungeon" and self.editorProfile ~= "enemyDungeon"
        and "full" or (settings and settings.friendly)
    if key:match("^value%d+$") then
        local profile = PS.GetPlateProfileSettings(self.editorProfile)
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if not slot or slot.source == "off" then return false end
        if self.editorProfile ~= "enemy" and self.editorProfile ~= "enemyDungeon"
            and friendlyMode ~= "full" then return false end
        return true
    end
    if self.editorProfile == "enemy" or self.editorProfile == "enemyDungeon" then
        return key ~= "guild" and key ~= "relationshipIcon" and key ~= "pvpIcon"
    end
    if friendlyMode == "off" or not friendlyMode then return false end
    if key == "health" or key == "power" or key == "cast" then return friendlyMode == "full" end
    if key == "threat" or key == "tagged" then return false end
    if self.editorProfile == "friendlyPlayer" then return key ~= "quest" and key ~= "classification" end
    return key ~= "relationshipIcon" and key ~= "pvpIcon" and key ~= "classification" and key ~= "guild"
end

local function SetTargetPreviewStrength(options, strength)
    for _, component in ipairs(options.targetPreviewTexts or {}) do
        local text = component.previewText
        if strength and component.targetPreviewVisible then
            text:SetShadowColor(1, 0.7, 0.14, strength)
            text:SetShadowOffset(1, -1)
        else
            local original = component.targetPreviewShadow
            text:SetShadowColor(original[1], original[2], original[3], original[4])
            text:SetShadowOffset(original[5], original[6])
        end
    end
    for _, component in ipairs(options.targetPreviewBars or {}) do
        local glow = component.targetPreviewGlow
        glow:SetShown(strength ~= nil and component.targetPreviewVisible)
        if strength then glow:SetAlpha(strength) end
    end
end

local function UpdateTargetPreviewPulse(_, elapsed)
    local options = PS.Options
    if not options.editor or not options.editor:IsShown() or not options.editorCanvas:IsShown() then return end
    options.targetPreviewPulseElapsed = (options.targetPreviewPulseElapsed or 0) + elapsed
    if options.targetPreviewPulseElapsed < 0.05 then return end
    options.targetPreviewPulseElapsed = 0
    SetTargetPreviewStrength(options, 0.4 + 0.3 * (0.5 + 0.5 * math.sin(GetTime() * 3)))
end

function Options:RefreshTargetHighlightPreview(settings)
    if not self.editorCanvas then return end
    local style = settings.targetHighlightStyle
    if self.targetPreviewStyle ~= style then
        self.targetPreviewStyle = style
        self.targetPreviewPulseElapsed = 0
        self.editorCanvas:SetScript("OnUpdate", style == "halo" and UpdateTargetPreviewPulse or nil)
        for _, component in ipairs(self.targetPreviewBars or {}) do
            local glow = component.targetPreviewGlow
            local inset = style == "halo" and 3 or 1
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", component, "TOPLEFT", -inset, inset)
            glow:SetPoint("BOTTOMRIGHT", component, "BOTTOMRIGHT", inset, -inset)
            glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = style == "halo" and 2 or 1 })
            glow:SetBackdropBorderColor(1, 0.7, 0.14, 1)
        end
    end
    SetTargetPreviewStrength(self, style == "border" and 0.7 or style == "halo" and 0.55 or nil)
end

function Options:RefreshEditorAppearance(settings)
    if not self.editorComponents or not settings then return end
    local profile = type(PS.GetPlateProfileSettings) == "function" and PS.GetPlateProfileSettings(self.editorProfile) or settings
    for key, component in pairs(self.editorComponents) do
        local definition = editorDefinitions[key]
        if definition and type(definition.refresh) == "function" then
            local succeeded, reason = pcall(definition.refresh, component, profile)
            if not succeeded then Notify("Editor component refresh failed for " .. key .. ": " .. tostring(reason)) end
        end
        local position = self.editorLayout and self.editorLayout[key]
        local relevant = self:IsEditorComponentRelevant(key, settings)
        local globallyEnabled = relevant and (key ~= "quest" or settings.quest)
            and (key ~= "threat" or settings.threat)
            and (key ~= "buffs" or settings.showBuffs)
            and (key ~= "debuffs" or settings.showDebuffs)
            and (key ~= "pvpIcon" or settings.friendlyPvpStyle == "icon" or settings.friendlyPvpStyle == "both")
            and (key ~= "classification" or settings.showClassification)
        component.targetPreviewVisible = globallyEnabled and position and position.visible ~= false
        component:SetShown(relevant)
        if relevant then
            local slot = key:match("^value%d+$") and profile.valueSlots[key] or nil
            local missingBar = slot and slot.whenMissing == "hide" and slot.anchor ~= "canvas"
                and self.editorLayout[slot.anchor].visible == false
            component:SetAlpha((position and position.visible == false or missingBar) and 0.18
                or (globallyEnabled and 1 or 0.35))
        end
    end
    self:RefreshEditorComponentLayers()
    self:RefreshEditorComponentList(settings)
    if self.editorPreviewStatus then
        local label = self.editorProfile == "enemyDungeon"
            and (PS.GetDungeonEnemyOverride() and "Dungeon enemy · custom layout" or "Dungeon enemy · inherits World")
            or self.editorContext == "dungeon" and "Dungeon friendly · experimental overlay · separate positions"
            or self.editorProfile == "enemy" and "World enemy nameplate"
            or settings.friendly == "names" and "Names only · selected in Friendly units"
            or settings.friendly == "full" and "Full plate · selected in Friendly units"
            or "Blizzard plates · choose Names only or Full plates to edit"
        self.editorPreviewStatus:SetText(label)
    end
    local sample
    for _, definition in ipairs(editorProfiles) do
        if definition.key == self.editorProfile
            or (definition.key == "enemy" and self.editorProfile == "enemyDungeon") then
            sample = definition break
        end
    end
    local name = self.editorComponents.name
    if name and name.previewText and sample then
        name.previewText:SetText(self.editorProfile == "friendlyPlayer" and CurrentCharacterName() or sample.sampleName)
        local colour = self.editorProfile == "friendlyPlayer"
            and (settings.friendlyPvpStyle == "colour" or settings.friendlyPvpStyle == "both")
            and settings.relationshipColours and settings.relationshipColours.pvp
        if colour then
            name.previewText:SetTextColor(colour.r, colour.g, colour.b)
        else
            name.previewText:SetTextColor(sample.colour[1], sample.colour[2], sample.colour[3])
        end
    end
    local level = self.editorComponents.level
    if level and level.previewText then
        level.previewText:SetText((self.editorProfile == "enemy"
            or self.editorProfile == "enemyDungeon") and "14" or "15")
    end
    local guild = self.editorComponents.guild
    if guild and guild.previewText and self.editorProfile == "friendlyPlayer" then
        local ok, guildName = false, nil
        if type(GetGuildInfo) == "function" then ok, guildName = pcall(GetGuildInfo, "player") end
        if ok and IsReadableValue(guildName) and type(guildName) == "string" and guildName ~= "" then
            guild.previewText:SetText("<" .. guildName .. ">")
        else
            guild.previewText:SetText("<Guild Name>")
        end
    end
    if not self:IsEditorComponentRelevant(self.selectedComponent, settings) then
        self:SelectEditorComponent(self:IsEditorComponentRelevant("name", settings) and "name" or nil)
    else
        self:RefreshEditorInspectorContext()
    end
    self:RefreshTargetHighlightPreview(settings)
end

function Options:SetEditorProfile(profileKey)
    if profileKey == "enemy" and self.editorContext == "dungeon" then profileKey = "enemyDungeon" end
    if not editorProfileSet[profileKey] then return false end
    self.editorProfile = profileKey
    self.editorLayout = CopyEditorLayout(type(PS.GetLayout) == "function"
        and PS.GetLayout(profileKey, self:CurrentEditorVariant()) or editorDefaults)
    for key, button in pairs(self.editorProfileButtons or {}) do
        Options.SetStudioButtonState(button, key == profileKey
            or (key == "enemy" and profileKey == "enemyDungeon"))
    end
    self:RefreshEditorLayout()
    self:RefreshEditorAppearance(PS.GetSettings())
    self:SelectEditorComponent(self.selectedComponent or "name")
    self:Refresh()
    self:SetEditorInspectorPage("components")
    return true
end

function Options:SetEditorContext(context)
    if context ~= "world" and context ~= "dungeon" then return false end
    self.editorContext = context
    if self.editorContextDropdown then
        UIDropDownMenu_SetText(self.editorContextDropdown,
            context == "dungeon" and "Dungeon" or "World")
    end
    local category = self.editorProfile == "enemyDungeon" and "enemy" or self.editorProfile
    return self:SetEditorProfile(category)
end

function Options:CreateEditorComponent(key, definition)
    if not self.editorCanvas or self.editorComponents[key] then return self.editorComponents[key] end
    local component = MakeEditorComponent(self.editorPreviewStage or self.editorCanvas,
        key, definition.width, definition.height)
    component.editorDefinition = definition
    self.editorComponents[key] = component
    if type(definition.create) == "function" then
        local succeeded, reason = pcall(definition.create, component, self.editorCanvas)
        if not succeeded then Notify("Editor component creation failed for " .. key .. ": " .. tostring(reason)) end
    end
    if component.previewText and (key == "name" or key == "level" or key == "guild"
        or key == "threat" or key == "tagged" or key == "classification" or key:match("^value%d+$")) then
        local red, green, blue, alpha = component.previewText:GetShadowColor()
        local x, y = component.previewText:GetShadowOffset()
        component.targetPreviewShadow = { red or 0, green or 0, blue or 0, alpha or 0, x or 0, y or 0 }
        self.targetPreviewTexts = self.targetPreviewTexts or {}
        self.targetPreviewTexts[#self.targetPreviewTexts + 1] = component
    elseif key == "health" or key == "power" or key == "cast" then
        local glow = CreateFrame("Frame", nil, component, "BackdropTemplate")
        glow:SetPoint("TOPLEFT", component, "TOPLEFT", -1, 1)
        glow:SetPoint("BOTTOMRIGHT", component, "BOTTOMRIGHT", 1, -1)
        glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        glow:SetBackdropBorderColor(1, 0.7, 0.14, 1)
        glow:EnableMouse(false)
        glow:Hide()
        component.targetPreviewGlow = glow
        self.targetPreviewBars = self.targetPreviewBars or {}
        self.targetPreviewBars[#self.targetPreviewBars + 1] = component
    end
    return component
end

function Options:CreateEditorComponentButton(key)
    if not self.editorListContent or self.editorComponentButtons[key] then return end
    local button = CreateFrame("Button", nil, self.editorListContent)
    button:SetSize(154, 23)
    local selection = button:CreateTexture(nil, "BACKGROUND")
    selection:SetAllPoints()
    selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    selection:SetBlendMode("ADD")
    selection:SetAlpha(0.65)
    selection:Hide()
    button.selection = selection
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", button, "LEFT", 12, 0)
    label:SetText(editorLabels[key])
    button.label = label
    local visibility = CreateFrame("CheckButton", nil, button, "UICheckButtonTemplate")
    visibility:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    visibility:SetSize(21, 21)
    visibility:SetChecked(true)
    visibility:SetScript("OnClick", function(instance)
        self:SetEditorComponentVisibility(key, instance:GetChecked() and true or false)
    end)
    button.visibility = visibility
    button:SetScript("OnClick", function() self:SelectEditorComponent(key) end)
    self.editorComponentButtons[key] = button
    self:RefreshEditorComponentList(PS.GetSettings())
    return button
end

