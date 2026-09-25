local _, PS = ...

local Options = { controls = {} }
PS.Options = Options
local editorDefaults, editorOrder, editorLabels, editorDefinitions = {}, {}, {}, {}
Options.editorDefinitions = editorDefinitions
local VALUE_SLOT_COUNT = 8
local valueSourceChoices = {
    { value = "healthPercent", label = "Health %", preview = "72%" },
    { value = "healthCurrent", label = "Current HP", preview = "842" },
    { value = "healthValue", label = "Current / max HP", preview = "842 / 1170" },
    { value = "powerPercent", label = "Power %", preview = "64%" },
    { value = "powerCurrent", label = "Current power", preview = "320" },
    { value = "powerValue", label = "Current / max power", preview = "320 / 500" },
    { value = "threatPercent", label = "Threat %", preview = "82%" },
    { value = "leadPercent", label = "Lead %", preview = "L34%" },
    { value = "rawThreat", label = "Raw threat", preview = "T60k" },
    { value = "differential", label = "Signed difference", preview = "+1.4k" },
}
local valueSourceByKey = {}
for _, choice in ipairs(valueSourceChoices) do valueSourceByKey[choice.value] = choice end
local valueAnchorChoices = {
    { value = "health", label = "Health bar" },
    { value = "power", label = "Power bar" },
    { value = "cast", label = "Cast bar" },
    { value = "canvas", label = "Plate canvas" },
}

function PS.RegisterEditorComponent(key, definition)
    if type(key) ~= "string" or not key:match("^[%a][%w_%.]*$") then
        return false, "component key must be a stable namespaced identifier"
    end
    if type(definition) ~= "table" or type(definition.label) ~= "string" then
        return false, "component definition requires a label"
    end
    if editorDefinitions[key] then return false, "component is already registered" end

    local x, y = tonumber(definition.x), tonumber(definition.y)
    local width, height = tonumber(definition.width), tonumber(definition.height)
    if not x or not y or not width or not height or width <= 0 or height <= 0 then
        return false, "component definition requires numeric x, y, width, and height"
    end

    editorDefinitions[key] = definition
    editorOrder[#editorOrder + 1] = key
    editorLabels[key] = definition.label
    editorDefaults[key] = { x = x, y = y, visible = definition.visible ~= false }

    if Options.editorCanvas and Options.CreateEditorComponent then
        local saved = type(PS.GetLayout) == "function"
            and PS.GetLayout(Options.editorProfile, Options:CurrentEditorVariant()) or nil
        Options.editorLayout[key] = saved and saved[key] or { x = x, y = y, visible = definition.visible ~= false }
        Options:CreateEditorComponent(key, definition)
        Options:CreateEditorComponentButton(key)
        Options:PositionEditorComponent(key)
        if type(PS.GetSettings) == "function" then Options:RefreshEditorAppearance(PS.GetSettings()) end
    end
    return true
end

PS.RegisterEditorComponent("name", {
    label = "Name", x = 0, y = 16, width = 176, height = 22,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText("Training Raider")
        component.previewText:SetTextColor(1, 0.25, 0.2)
    end,
    refresh = function(component, settings)
        if component.previewText then
            local scale = settings.scale or 1
            local size = math.floor((settings.nameFontSize or 12) * scale + 0.5)
            if type(PS.ApplyNameplateFont) == "function" then
                PS.ApplyNameplateFont(component.previewText, size)
            elseif component.previewText.SetFont then
                component.previewText:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
            end
        end
    end,
})

PS.RegisterEditorComponent("level", {
    label = "Level", x = -70, y = 0, width = 30, height = 20,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText("15")
    end,
    refresh = function(component, settings)
        if component.previewText and type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(component.previewText, math.max(8, (settings.nameFontSize or 12) - 2))
        end
    end,
})

PS.RegisterEditorComponent("guild", {
    label = "Guild name", x = 0, y = -13, width = 176, height = 19,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText("<Guild Name>")
        component.previewText:SetTextColor(0.68, 0.85, 0.76)
    end,
    refresh = function(component, settings)
        if component.previewText and type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(component.previewText, math.max(8, (settings.nameFontSize or 12) - 2))
        end
    end,
})

PS.RegisterEditorComponent("health", {
    label = "Health bar", x = 0, y = 0, width = 112, height = 10,
    create = function(component)
        local bar = CreateFrame("StatusBar", nil, component)
        bar:SetAllPoints()
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.85, 0.12, 0.1)
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(72)
        component.previewBar = bar
    end,
    refresh = function(component, settings)
        local scale = settings.scale or 1
        component:SetSize(math.floor((settings.width or 112) * scale + 0.5), math.floor((settings.healthHeight or 10) * scale + 0.5))
        if component.previewBar then
            component.previewBar:SetStatusBarTexture(settings.healthTexture == "flat"
                and "Interface\\Buttons\\WHITE8X8" or "Interface\\TargetingFrame\\UI-StatusBar")
            local colour = settings.healthColour
            if settings.healthColourMode == "custom" and colour then
                component.previewBar:SetStatusBarColor(colour.r, colour.g, colour.b)
            else
                if Options.editorProfile == "friendlyPlayer" then
                    component.previewBar:SetStatusBarColor(0.25, 1, 0.45)
                elseif Options.editorProfile == "friendlyNPC" then
                    component.previewBar:SetStatusBarColor(0.35, 0.9, 1)
                else
                    component.previewBar:SetStatusBarColor(0.85, 0.12, 0.1)
                end
            end
        end
    end,
})

PS.RegisterEditorComponent("power", {
    label = "Power bar", x = 0, y = -14, width = 112, height = 6, visible = false,
    create = function(component)
        local bar = CreateFrame("StatusBar", nil, component)
        bar:SetAllPoints()
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.18, 0.48, 1)
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(64)
        component.previewBar = bar
    end,
    refresh = function(component, settings)
        component:SetSize(math.floor((settings.width or 112) * (settings.scale or 1) + 0.5),
            settings.powerHeight or 5)
        component.previewBar:SetStatusBarTexture(settings.healthTexture == "flat"
            and "Interface\\Buttons\\WHITE8X8" or "Interface\\TargetingFrame\\UI-StatusBar")
    end,
})

PS.RegisterEditorComponent("cast", {
    label = "Cast bar", x = 0, y = -13, width = 112, height = 7,
    create = function(component)
        local bar = CreateFrame("StatusBar", nil, component)
        bar:SetAllPoints()
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.95, 0.65, 0.12)
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(58)
    end,
    refresh = function(component, settings)
        local scale = settings.scale or 1
        component:SetSize(math.floor((settings.width or 112) * scale + 0.5), math.max(5, math.floor((settings.healthHeight or 10) * 0.65 * scale + 0.5)))
    end,
})

PS.RegisterEditorComponent("threat", {
    label = "Threat", x = 0, y = -25, width = 142, height = 24,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        component.previewText:SetPoint("TOP", 0, -2)
        component.previewText:SetText("82%  L34%  T60k")
        component.previewText:SetTextColor(1, 0.45, 0.1)
        component.previewRisk = CreateFrame("StatusBar", nil, component)
        component.previewRisk:SetSize(42, 2)
        component.previewRisk:SetPoint("BOTTOM", 0, 2)
        component.previewRisk:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        component.previewRisk:SetStatusBarColor(1, 0.18, 0.12, 0.9)
        component.previewRisk:SetMinMaxValues(0, 3)
        component.previewRisk:SetValue(2)
    end,
    refresh = function() end,
})

for index = 1, VALUE_SLOT_COUNT do
    local key = "value" .. index
    PS.RegisterEditorComponent(key, {
        label = "Value " .. index, x = 0, y = 0, width = 100, height = 17,
        create = function(component)
            local preview = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            preview:SetPoint("CENTER")
            preview:SetJustifyH("CENTER")
            component.previewText = preview
        end,
        refresh = function(component, profile)
            local slot = profile.valueSlots and profile.valueSlots[key]
            local choice = slot and valueSourceByKey[slot.source]
            component.previewText:SetText(choice and choice.preview or "Value")
            if slot and type(PS.ApplyNameplateFont) == "function" then
                PS.ApplyNameplateFont(component.previewText, slot.fontSize)
            end
            if slot and slot.colour then
                component.previewText:SetTextColor(slot.colour.r, slot.colour.g, slot.colour.b)
            end
        end,
    })
end

PS.RegisterEditorComponent("tagged", {
    label = "Tagged indicator", x = 62, y = -25, width = 54, height = 18,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText("TAGGED")
        component.previewText:SetTextColor(0.72, 0.72, 0.72)
    end,
    refresh = function() end,
})

PS.RegisterEditorComponent("quest", {
    label = "Quest marker", x = -70, y = 16, width = 46, height = 28,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        component.previewText:SetPoint("LEFT", component, "LEFT", 3, 0)
        component.previewText:SetText("!")
        component.previewText:SetTextColor(1, 0.82, 0)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetSize(18, 18)
        component.previewIcon:SetPoint("RIGHT", component, "RIGHT", -2, 0)
        component.previewIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        component.previewIcon:SetMask("Interface\\AddOns\\PlateSmith\\Media\\QuestLootMask.png")
    end,
    refresh = function() end,
})

PS.RegisterEditorComponent("raidIcon", {
    label = "Raid target icon", x = 70, y = 16, width = 28, height = 28,
    create = function(component)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
        -- The live helper may require an opaque marker value on Forever. The
        -- editor is only a preview, so crop the built-in star directly.
        component.previewIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        component.previewIcon:SetTexCoord(0, 0.25, 0, 0.5)
    end,
    refresh = function() end,
})

PS.RegisterEditorComponent("relationshipIcon", {
    label = "Relationship icon", x = 0, y = 38, width = 26, height = 26, visible = false,
    create = function(component)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
        component.previewIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
    end,
    refresh = function() end,
})

PS.RegisterEditorComponent("pvpIcon", {
    label = "PvP icon", x = 106, y = 8, width = 22, height = 22,
    create = function(component)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
        component.previewIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance")
    end,
    refresh = function() end,
})

PS.RegisterEditorComponent("classification", {
    label = "Elite / rare mark", x = -94, y = 0, width = 28, height = 22,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText("+")
        component.previewText:SetTextColor(1, 0.78, 0.25)
    end,
    refresh = function() end,
})

local function CreateAuraPreview(component, textures)
    for index, texture in ipairs(textures) do
        local icon = component:CreateTexture(nil, "OVERLAY")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", component, "LEFT", (index - 1) * 20, 0)
        icon:SetTexture(texture)
    end
end

PS.RegisterEditorComponent("buffs", {
    label = "Buffs", x = 0, y = 38, width = 78, height = 20,
    create = function(component)
        CreateAuraPreview(component, {
            "Interface\\Icons\\Spell_Nature_Rejuvenation",
            "Interface\\Icons\\Spell_Holy_PowerWordShield",
            "Interface\\Icons\\Spell_Nature_Regeneration",
            "Interface\\Icons\\Spell_Holy_BlessingOfProtection",
        })
    end,
    refresh = function() end,
})

PS.RegisterEditorComponent("debuffs", {
    label = "Debuffs", x = 0, y = -43, width = 78, height = 20,
    create = function(component)
        CreateAuraPreview(component, {
            "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
            "Interface\\Icons\\Spell_Fire_FlameBolt",
            "Interface\\Icons\\Ability_Rogue_Rupture",
            "Interface\\Icons\\Spell_Nature_Slow",
        })
    end,
    refresh = function() end,
})

Options.editorCatalog = {
    editorDefaults = editorDefaults,
    editorOrder = editorOrder,
    editorLabels = editorLabels,
    editorDefinitions = editorDefinitions,
    VALUE_SLOT_COUNT = VALUE_SLOT_COUNT,
    valueSourceChoices = valueSourceChoices,
    valueSourceByKey = valueSourceByKey,
    valueAnchorChoices = valueAnchorChoices,
}
