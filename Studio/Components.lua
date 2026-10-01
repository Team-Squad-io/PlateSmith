local _, PS = ...
local L = PS.L

local Options = { controls = {} }
PS.Options = Options
local editorDefaults, editorOrder, editorLabels, editorDefinitions = {}, {}, {}, {}
Options.editorDefinitions = editorDefinitions
local VALUE_SLOT_COUNT = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing").VALUE_SLOT_COUNT
local valueSourceChoices = {
    { value = "healthPercent", label = L["Health %"], preview = "72%" },
    { value = "healthCurrent", label = L["Current HP"], preview = "842" },
    { value = "healthValue", label = L["Current / max HP"], preview = "842 / 1170" },
    { value = "powerPercent", label = L["Power %"], preview = "64%" },
    { value = "powerCurrent", label = L["Current power"], preview = "320" },
    { value = "powerValue", label = L["Current / max power"], preview = "320 / 500" },
    { value = "threatPercent", label = L["Threat %"], preview = "82%" },
    { value = "leadPercent", label = L["Threat gap"], preview = "+125" },
    { value = "rawThreat", label = L["Raw threat"], preview = "60k" },
    { value = "differential", label = L["Signed difference"], preview = "+1.4k" },
    { value = "template", label = L["Custom text"], preview = "{health}" },
}
-- A bar's sources (its fill), for its inspector.
local barSourceChoices = {
    { value = "healthPercent", label = L["Health %"] },
    { value = "powerPercent", label = L["Power %"] },
    { value = "threatPercent", label = L["Threat %"] },
}
local iconChoices = {
    { value = "raid8", label = L["Skull"] }, { value = "raid7", label = L["Cross"] },
    { value = "raid6", label = L["Square"] }, { value = "raid5", label = L["Moon"] },
    { value = "raid4", label = L["Triangle"] }, { value = "raid3", label = L["Diamond"] },
    { value = "raid2", label = L["Circle"] }, { value = "raid1", label = L["Star"] },
    { value = "quest", label = L["Quest mark"] }, { value = "sword", label = L["Sword"] },
    { value = "shield", label = L["Shield"] },
}

-- Sample values for a template in Studio's preview (the plates read the real ones).
local TEMPLATE_SAMPLES = {
    ["health"] = 842, ["health.max"] = 1170, ["health.percent"] = 72, ["health.missing"] = 328,
    ["power"] = 320, ["power.max"] = 500, ["power.percent"] = 64,
    ["threat.percent"] = 82, ["threat.lead"] = 1400, ["threat.raw"] = 60000, ["threat.leadpercent"] = 82,
    ["level"] = 14, ["name"] = L["Training Raider"], ["target"] = L["Target Name"],
    ["tagged"] = false, ["elite"] = true, ["rare"] = false, ["boss"] = false, ["casting"] = true,
    ["combat"] = true, ["tanking"] = false, ["targeted"] = true, ["player"] = false,
    ["focus"] = false, ["quest"] = true, ["friendly"] = false, ["level.smart"] = "14+", ["level.diff"] = -3,
    ["classification"] = L["Elite"], ["guild"] = L["Guild Name"], ["cast.name"] = L["Fireball"], ["threat.hold"] = L["TANK"],
    ["hostile"] = true, ["neutral"] = false, ["interruptible"] = true, ["interruptReady"] = true, ["questdrop"] = false, ["pvp"] = false,
    ["instance"] = false, ["ingroup"] = false, ["inguild"] = false,
    ["role.tank"] = false, ["threat.holding"] = false, ["threat.losing"] = false, ["threat.pulling"] = false,
    ["threat.other"] = false, ["threat.offtank"] = false,
    ["hastarget"] = true, ["inrange"] = true, ["quest.progress"] = "3/8", ["quest.percent"] = 38,
    ["combo"] = 3,
}
-- Tokens other addons registered preview with their own sample (Template.RegisterToken).
setmetatable(TEMPLATE_SAMPLES, { __index = function(_, token) return PS.Template.Sample(token) end })
Options.templateSamples = TEMPLATE_SAMPLES

-- The sample unit's classification mark (Test values' elite, rare and boss).
local function SampleClassification()
    if TEMPLATE_SAMPLES.boss then return "worldboss" end
    if TEMPLATE_SAMPLES.rare then return TEMPLATE_SAMPLES.elite and "rareelite" or "rare" end
    return TEMPLATE_SAMPLES.elite and "elite" or nil
end
local valueSourceByKey = {}
for _, choice in ipairs(valueSourceChoices) do valueSourceByKey[choice.value] = choice end

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
        -- A fresh copy of the edited layout, now with this part (its saved place or its default).
        Options:ReloadEditorLayoutCopy()
        Options:CreateEditorComponent(key, definition)
        Options:CreateEditorComponentButton(key)
        -- The refresh draws it, lays it out and lists it in the tree.
        if type(PS.GetSettings) == "function" then Options:RefreshEditorAppearance(PS.GetSettings()) end
    end
    return true
end

PS.RegisterEditorComponent("name", {
    label = L["Name"], x = 0, y = 16, width = 176, height = 22,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText(L["Training Raider"])
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
    label = L["Level"], x = -70, y = 0, width = 30, height = 20,
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
    label = L["Guild name"], x = 0, y = -13, width = 176, height = 19,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText(L["<Guild Name>"])
        component.previewText:SetTextColor(0.68, 0.85, 0.76)
    end,
    refresh = function(component, settings)
        if component.previewText and type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(component.previewText, math.max(8, (settings.nameFontSize or 12) - 2))
        end
    end,
})

PS.RegisterEditorComponent("health", {
    label = L["Health bar"], x = 0, y = 0, width = 112, height = 10,
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
            component.previewBar:SetStatusBarTexture(PS.Media.StatusBarPath(settings.healthTexture))
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
    label = L["Power bar"], x = 0, y = -14, width = 112, height = 6, visible = false,
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
        local scale = settings.scale or 1
        component:SetSize(math.floor((settings.powerWidth or settings.width or 112) * scale + 0.5),
            math.floor((settings.powerHeight or 5) * scale + 0.5))
        component.previewBar:SetStatusBarTexture(PS.Media.StatusBarPath(settings.healthTexture))
    end,
})

PS.RegisterEditorComponent("cast", {
    label = L["Cast bar"], x = 0, y = -13, width = 112, height = 7,
    create = function(component)
        local bar = CreateFrame("StatusBar", nil, component)
        bar:SetAllPoints()
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.95, 0.65, 0.12)
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(58)
        component.previewBar = bar
        component.previewSpell = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewSpell:SetPoint("CENTER")
        -- As the plate draws them: the time left inside the bar's right end, the spell's icon
        -- beside the bar.
        component.previewTime = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewTime:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
        component.previewIcon = bar:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
        component.previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        component.previewStyleTexts = { component.previewSpell, component.previewTime }
    end,
    -- Test values: casting fills it with the spell's name; one that cannot be interrupted is grey,
    -- or with Colour by interrupt, the colour interruptible and interruptReady choose.
    -- The profile's cast options place the icon (left, right or off) and show the time and name.
    refresh = function(component, settings)
        local scale = settings.scale or 1
        -- As on the plates: its own size, or the health bar's width and 3 px less height.
        local height = settings.castHeight or math.max(5, (settings.healthHeight or 10) - 3)
        local drawn = math.floor(height * scale + 0.5)
        component:SetSize(math.floor((settings.castWidth or settings.width or 112) * scale + 0.5), drawn)
        local casting = TEMPLATE_SAMPLES.casting == true
        local bar, spell, time, icon = component.previewBar, component.previewSpell, component.previewTime, component.previewIcon
        bar:SetValue(casting and 58 or 0)
        if settings.castInterruptColours == true then
            local colours = PS.ProfileSchema.NormalizeCastColours(settings.castColours)
            local colour = colours.cooldown
            if TEMPLATE_SAMPLES.interruptible == false then
                colour = colours.locked
            elseif TEMPLATE_SAMPLES.interruptReady == true then
                colour = colours.ready
            end
            bar:SetStatusBarColor(colour.r, colour.g, colour.b)
        elseif TEMPLATE_SAMPLES.interruptible == false then
            bar:SetStatusBarColor(0.6, 0.6, 0.65)
        else
            bar:SetStatusBarColor(0.95, 0.65, 0.12)
        end
        local showTime, side = settings.castTime ~= false, settings.castIcon or "left"
        spell:SetText(casting and tostring(TEMPLATE_SAMPLES["cast.name"] or "") or "")
        spell:SetShown(settings.castName ~= false)
        spell:ClearAllPoints()
        if showTime then
            spell:SetPoint("LEFT", bar, "LEFT", 3, 0)
            spell:SetPoint("RIGHT", time, "LEFT", -2, 0)
            spell:SetJustifyH("LEFT")
        else
            spell:SetPoint("CENTER")
            spell:SetJustifyH("CENTER")
        end
        time:SetText(casting and "1.2" or "")
        time:SetShown(showTime)
        icon:SetSize(drawn, drawn)
        icon:ClearAllPoints()
        if side == "right" then icon:SetPoint("LEFT", bar, "RIGHT", 2, 0) else icon:SetPoint("RIGHT", bar, "LEFT", -2, 0) end
        icon:SetShown(casting and side ~= "off")
        local size = math.max(7, math.floor(height * scale))
        if PS.ApplyNameplateFont then
            PS.ApplyNameplateFont(spell, size)
            PS.ApplyNameplateFont(time, size)
        end
    end,
})

PS.RegisterEditorComponent("threat", {
    label = L["Threat"], x = 0, y = -25, width = 142, height = 14,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText("82%  +125")
    end,
    -- The threat sample as the plates show it (percent and the signed gap), coloured by state in
    -- the plates' palette, or the colour-blind one with Studio's option. Test values: out of
    -- combat there is none (drawn faint, to place it); tanking, you hold it.
    refresh = function(component, settings)
        local access = Options.StudioAccess and Options:StudioAccess() or {}
        local combat, tanking = TEMPLATE_SAMPLES.combat ~= false, TEMPLATE_SAMPLES.tanking == true
        component.previewText:SetAlpha(combat and 1 or 0.3)
        local format = PS.ThreatText and PS.ThreatText.Format and PS.ThreatText.Format() or "gap"
        if format == "percent" then
            component.previewText:SetText(tanking and "100%" or "82%")
        elseif format == "detailed" then
            component.previewText:SetText(tanking and "100%  L253%  T60k" or "82%  L82%  T49k")
        else
            component.previewText:SetText(tanking and "100%  +575" or "82%  +125")
        end
        if type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(component.previewText, math.max(8, ((settings and settings.nameFontSize) or 12) - 2))
        end
        if PS.ThreatText and PS.ThreatText.StateColour then
            local info = tanking and { tanking = true, status = 3 } or { tanking = false, status = 1 }
            component.previewText:SetTextColor(PS.ThreatText.StateColour(info, access.colourBlind))
        end
    end,
})
for index = 1, VALUE_SLOT_COUNT do
    local key = "value" .. index
    PS.RegisterEditorComponent(key, {
        label = string.format(L["Value %d"], index), x = 0, y = 0, width = 100, height = 17,
        create = function(component)
            local preview = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            preview:SetPoint("CENTER")
            preview:SetJustifyH("CENTER")
            component.previewText = preview
        end,
        refresh = function(component, profile)
            local slot = profile.valueSlots and profile.valueSlots[key]
            local choice = slot and valueSourceByKey[slot.source]
            -- A shape (bar, box, icon) shows as itself; the text hides.
            local kind = slot and slot.kind
            if component.previewShape then component.previewShape:Hide() end
            if component.previewShapeBar then component.previewShapeBar:Hide() end
            component.previewBar, component.previewTexture = nil, nil
            if kind then
                local size = PS.ValueGraphicSize and PS.ValueGraphicSize[kind] or { 40, 10 }
                local width, height = slot.width or size[1], slot.height or size[2]
                component:SetSize(width, height)
                component.previewText:SetText("")
                local colour = slot.colour or { r = 1, g = 1, b = 1 }
                if kind == "bar" then
                    if not component.previewShapeBar then
                        local bar = CreateFrame("StatusBar", nil, component)
                        bar:SetAllPoints(component)
                        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        bar:SetMinMaxValues(0, 100)
                        component.previewShapeBar = bar
                    end
                    component.previewShapeBar:SetValue(slot.source == "powerPercent" and 64 or 72)
                    component.previewShapeBar:SetStatusBarColor(colour.r, colour.g, colour.b)
                    component.previewShapeBar:Show()
                    component.previewBar = component.previewShapeBar
                else
                    if not component.previewShape then
                        component.previewShape = component:CreateTexture(nil, "ARTWORK")
                        component.previewShape:SetAllPoints(component)
                    end
                    if kind == "box" then
                        component.previewShape:SetColorTexture(colour.r, colour.g, colour.b, 0.85)
                    else
                        component.previewShape:SetTexture(PS.ValueIconPaths and PS.ValueIconPaths[slot.icon or "raid8"])
                        component.previewShape:SetVertexColor(colour.r, colour.g, colour.b)
                    end
                    component.previewShape:Show()
                    component.previewTexture = component.previewShape
                end
                return
            end
            component:SetSize(100, 17)
            if slot and slot.source == "template" and PS.Template then
                -- The template with sample values; one that does not compile shows as it is typed.
                if not PS.Template.Apply(component.previewText, slot.template or "",
                    function(token) return TEMPLATE_SAMPLES[token] end) then
                    component.previewText:SetText(slot.template or L["Custom text"])
                end
            else
                component.previewText:SetText(choice and choice.preview or L["Value"])
            end
            if slot and type(PS.ApplyNameplateFont) == "function" then
                PS.ApplyNameplateFont(component.previewText, slot.fontSize)
            end
            if slot and slot.colour then
                component.previewText:SetTextColor(slot.colour.r, slot.colour.g, slot.colour.b)
            end
        end,
    })
end

PS.RegisterEditorComponent("targetName", {
    label = L["Target of target"], x = 0, y = 28, width = 120, height = 16,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText(L["Target Name"])
        component.previewText:SetTextColor(0.85, 0.85, 0.95)
    end,
    refresh = function(component, settings)
        if component.previewText and type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(component.previewText, math.max(8, (settings.nameFontSize or 12) - 2))
        end
    end,
})

PS.RegisterEditorComponent("tagged", {
    label = L["Tagged indicator"], x = 100, y = -8, width = 54, height = 18,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText(L["TAGGED"])
        component.previewText:SetTextColor(0.72, 0.72, 0.72)
    end,
    -- Test values: lit on a tagged unit, faint otherwise (so it can still be found and placed).
    refresh = function(component, settings)
        component.previewText:SetAlpha(TEMPLATE_SAMPLES.tagged == true and 1 or 0.3)
        if type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(component.previewText, math.max(8, (settings.nameFontSize or 14) - 3))
        end
    end,
})

-- Combo points as the plates draw them (Nameplates/ComboPoints.lua): a row of pips in the part's
-- style, the sample's {combo} filled. Test values: faint unless the unit is your target, as on the
-- plates, where the row shows only on your target's plate.
PS.RegisterEditorComponent("combo", {
    label = L["Combo points"], x = 0, y = 9, width = 58, height = 4,
    create = function(component)
        component.previewPips = {}
        for index = 1, 5 do
            component.previewPips[index] = { edge = component:CreateTexture(nil, "BACKGROUND"),
                empty = component:CreateTexture(nil, "BORDER"), fill = component:CreateTexture(nil, "ARTWORK") }
        end
    end,
    refresh = function(component, profile)
        local defaults = PS.ProfileSchema.STYLE_DEFAULTS
        local style = profile and profile.styles and profile.styles.combo or {}
        local scale = profile and profile.scale or 1
        local width = (style.pipWidth or defaults.pipWidth) * scale
        local height = (style.pipHeight or defaults.pipHeight) * scale
        local spacing = (style.pipSpacing or defaults.pipSpacing) * scale
        local fill, empty = style.pipFill or defaults.pipFill, style.pipEmpty or defaults.pipEmpty
        local pips = component.previewPips
        component:SetSize(#pips * width + (#pips - 1) * spacing, height)
        local count = math.max(0, math.min(#pips, math.floor(tonumber(TEMPLATE_SAMPLES.combo) or 0)))
        local inset = (width >= 6 and height >= 6) and 1 or 0
        local alpha = TEMPLATE_SAMPLES.targeted == false and 0.3 or 1
        for index, pip in ipairs(pips) do
            pip.edge:ClearAllPoints()
            pip.edge:SetPoint("LEFT", component, "LEFT", (index - 1) * (width + spacing), 0)
            pip.edge:SetSize(width, height)
            pip.edge:SetColorTexture(0, 0, 0, 0.9)
            for _, texture in ipairs({ pip.empty, pip.fill }) do
                texture:ClearAllPoints()
                texture:SetPoint("TOPLEFT", pip.edge, "TOPLEFT", inset, -inset)
                texture:SetPoint("BOTTOMRIGHT", pip.edge, "BOTTOMRIGHT", -inset, inset)
            end
            pip.empty:SetColorTexture(empty.r, empty.g, empty.b, empty.a or 1)
            pip.fill:SetColorTexture(fill.r, fill.g, fill.b, fill.a or 1)
            pip.fill:SetShown(index <= count)
            for _, texture in pairs(pip) do texture:SetAlpha(alpha) end
        end
    end,
})

-- "Targeted by" badges as the plates draw them (Nameplates/TargetedBy.lua): four sample members in
-- their class colours, the first two targeting this unit and the others faint.
local TARGETED_BY_SAMPLES = { { "WARRIOR", "T" }, { "PRIEST", "H" }, { "MAGE", "M" }, { "ROGUE", "R" } }
local SAMPLE_CLASS_COLOURS = { WARRIOR = { 0.78, 0.61, 0.43 }, PRIEST = { 1, 1, 1 }, MAGE = { 0.25, 0.78, 0.92 },
    ROGUE = { 1, 0.96, 0.41 } }
PS.RegisterEditorComponent("targetedBy", {
    label = L["Targeted by"], x = -90, y = 0, width = 46, height = 10, visible = false,
    create = function(component)
        component.previewBadges, component.previewStyleTexts = {}, {}
        for index = 1, #TARGETED_BY_SAMPLES do
            local badge = { edge = component:CreateTexture(nil, "BORDER"), fill = component:CreateTexture(nil, "ARTWORK"),
                text = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
            badge.fill:SetPoint("TOPLEFT", badge.edge, "TOPLEFT", 1, -1)
            badge.fill:SetPoint("BOTTOMRIGHT", badge.edge, "BOTTOMRIGHT", -1, 1)
            badge.text:SetPoint("CENTER", badge.edge, "CENTER", 0, 0)
            component.previewBadges[index] = badge
            component.previewStyleTexts[index] = badge.text
        end
    end,
    refresh = function(component, profile)
        local geometry = PS.TargetedBy
        if not geometry then return end
        local style = profile and profile.styles and profile.styles.targetedBy or {}
        local scale = profile and profile.scale or 1
        local size, spacing, vertical, initials = geometry.StyleOf(style)
        local width, height = geometry.RowSize(#component.previewBadges, size, spacing, vertical)
        component:SetSize(width * scale, height * scale)
        local colours = rawget(_G, "RAID_CLASS_COLORS")
        for index, badge in ipairs(component.previewBadges) do
            local class, initial = TARGETED_BY_SAMPLES[index][1], TARGETED_BY_SAMPLES[index][2]
            local x, y = geometry.BadgeOffset(index, size, spacing, vertical)
            badge.edge:ClearAllPoints()
            badge.edge:SetPoint("TOPLEFT", component, "TOPLEFT", x * scale, -y * scale)
            badge.edge:SetSize(size * scale, size * scale)
            badge.edge:SetColorTexture(0, 0, 0, 0.9)
            local colour = type(colours) == "table" and colours[class]
            local r, g, b = SAMPLE_CLASS_COLOURS[class][1], SAMPLE_CLASS_COLOURS[class][2], SAMPLE_CLASS_COLOURS[class][3]
            if type(colour) == "table" and type(colour.r) == "number" then r, g, b = colour.r, colour.g, colour.b end
            badge.fill:SetColorTexture(r, g, b, 1)
            if type(PS.ApplyNameplateFont) == "function" then
                PS.ApplyNameplateFont(badge.text, geometry.InitialFontSize(size * scale))
            end
            badge.text:SetText(initial)
            badge.text:SetTextColor(0, 0, 0)
            badge.text:SetShown(initials)
            local alpha = index <= 2 and 1 or 0.3
            badge.edge:SetAlpha(alpha)
            badge.fill:SetAlpha(alpha)
            badge.text:SetAlpha(alpha)
        end
    end,
})

-- Markers are drawn at the plates' sizes (Nameplates/Lifecycle: from the name's text size, at
-- the plate's scale), so what is pinned to one, or stacked with it, meets it where it would on
-- the plate; its frame is its icon, not a padded box.
local function MarkerSize(component, settings, extra, minimum)
    local size = math.floor(math.max(minimum, (settings.nameFontSize or 12) + extra) * (settings.scale or 1) + 0.5)
    component:SetSize(size, size)
    return size
end

PS.RegisterEditorComponent("quest", {
    label = L["Quest marker"], x = -70, y = 16, width = 16, height = 16,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        component.previewText:SetPoint("CENTER")
        component.previewText:SetText("!")
        component.previewText:SetTextColor(1, 0.82, 0)
        component.previewProgress = component:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        component.previewProgress:SetTextColor(1, 0.82, 0)
        -- Its style is the progress text's: on the plates the mark is a picture.
        component.previewStyleTexts = { component.previewProgress }
    end,
    -- Test values: lit on a quest unit, faint otherwise (so it can still be found and placed). The
    -- progress text shows its sample beside the mark or in its place.
    refresh = function(component, settings)
        MarkerSize(component, settings, 4, 14)
        local alpha = TEMPLATE_SAMPLES.quest ~= false and 1 or 0.3
        local mode, progress = settings.questProgress or "off", component.previewProgress
        progress:ClearAllPoints()
        if mode == "instead" then
            progress:SetPoint("CENTER", component, "CENTER", 0, 0)
        else
            progress:SetPoint("RIGHT", component, "LEFT", -1, 0)
        end
        local percent = settings.questProgressFormat == "percent"
        progress:SetText(percent and string.format("%d%%", math.floor(tonumber(TEMPLATE_SAMPLES["quest.percent"]) or 38))
            or TEMPLATE_SAMPLES["quest.progress"] or "3/8")
        if type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(progress, math.max(8, (settings.nameFontSize or 14) - 2))
        end
        progress:SetShown(mode ~= "off")
        progress:SetAlpha(alpha)
        component.previewText:SetShown(mode ~= "instead")
        component.previewText:SetAlpha(alpha)
    end,
})

-- The bag for a mob that drops a quest item. On a plate it shows instead of the quest mark, so by
-- default it is anchored to it, in the same spot (select either from the list to move it).
PS.RegisterEditorComponent("questLoot", {
    label = L["Quest loot marker"], x = 0, y = 0, width = 16, height = 16,
    create = function(component)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
        component.previewIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        component.previewIcon:SetMask("Interface\\AddOns\\PlateSmith\\Media\\QuestLootMask.png")
    end,
    refresh = function(component, settings) MarkerSize(component, settings, 4, 14) end,
})

PS.RegisterEditorComponent("raidIcon", {
    label = L["Raid target icon"], x = 70, y = 16, width = 18, height = 18,
    create = function(component)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
        -- The live helper may require an opaque marker value on Forever. The
        -- editor is only a preview, so crop the built-in star directly (the sheet is 4 x 4).
        component.previewIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        component.previewIcon:SetTexCoord(0, 0.25, 0, 0.25)
    end,
    refresh = function(component, settings) MarkerSize(component, settings, 6, 16) end,
})

PS.RegisterEditorComponent("relationshipIcon", {
    label = L["Relationship icon"], x = 0, y = 38, width = 16, height = 16, visible = false,
    create = function(component)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
        component.previewIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
    end,
    refresh = function(component, settings) MarkerSize(component, settings, 4, 14) end,
})

PS.RegisterEditorComponent("pvpIcon", {
    label = L["PvP icon"], x = 106, y = 8, width = 16, height = 16,
    create = function(component)
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
        component.previewIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance")
    end,
    refresh = function(component, settings) MarkerSize(component, settings, 4, 14) end,
})

PS.RegisterEditorComponent("classification", {
    label = L["Elite / rare mark"], x = -94, y = 0, width = 18, height = 18,
    create = function(component)
        component.previewText = component:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        component.previewText:SetPoint("CENTER")
        component.previewIcon = component:CreateTexture(nil, "OVERLAY")
        component.previewIcon:SetAllPoints()
    end,
    -- The sample's mark (Test values' elite, rare, boss) in the chosen style: the plate's 18 px
    -- icon, or its word.
    refresh = function(component, profile)
        local settings = PS.GetSettings and PS.GetSettings()
        local style = settings and settings.classificationStyle or "icon"
        if type(PS.ApplyNameplateFont) == "function" then
            PS.ApplyNameplateFont(component.previewText, math.max(8, (profile.nameFontSize or 14) - 2))
        end
        PS.ApplyClassificationMark(component.previewText, component.previewIcon, SampleClassification(), style)
        local size = math.floor(18 * (profile.scale or 1) + 0.5)
        local text = component.previewText
        local wordWidth = text:IsShown() and text.GetStringWidth and text:GetStringWidth() or 0
        component:SetSize(math.max(size, math.ceil(wordWidth)), size)
    end,
})

-- Aura previews hold a full row of sample icons and are laid out by the plates' own aura
-- layout (PS.LayoutAuraRow), so count, size, spacing and growth read the same in Studio.
-- Each sample icon has a sample countdown, drawn by the plates' own countdown rules
-- (PS.AuraCountdownFont, PS.PlaceAuraCountdown): its Display font, size, outline, shadow and place.
local SAMPLE_COUNTDOWNS = { "12", "2m", "15m", "9", "45", "1h", "3m", "8" }
local function CreateAuraPreview(component, textures)
    component.auraIcons, component.auraCountdowns = {}, {}
    for index = 1, 8 do
        local icon = component:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(textures[(index - 1) % #textures + 1])
        component.auraIcons[index] = icon
        local countdown = component:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if countdown.SetDrawLayer then countdown:SetDrawLayer("OVERLAY", 7) end
        countdown:SetText(SAMPLE_COUNTDOWNS[index])
        -- Its own shadow, to go back to when the row's Shadow choice is cleared.
        local okColour, r, g, b, a = pcall(countdown.GetShadowColor, countdown)
        local okOffset, x, y = pcall(countdown.GetShadowOffset, countdown)
        countdown.plateSmithPlainShadow = okColour and { r, g, b, a } or nil
        countdown.plateSmithPlainOffset = okOffset and { x, y } or { 0, 0 }
        component.auraCountdowns[index] = countdown
    end
end

local function RefreshAuraPreview(kind)
    return function(component, profile)
        local layout = profile and profile.auraLayouts and profile.auraLayouts[kind]
        if not layout or not PS.LayoutAuraRow then return end
        PS.LayoutAuraRow(component, component.auraIcons, layout, layout.count)
        local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
        local path, size, flags, shadow, position
        if PS.AuraCountdownFont then path, size, flags, shadow, position = PS.AuraCountdownFont(layout, settings) end
        for index, icon in ipairs(component.auraIcons) do
            local shown = index <= layout.count
            icon:SetShown(shown)
            local countdown = component.auraCountdowns and component.auraCountdowns[index]
            if countdown then
                countdown:SetShown(shown and layout.showDuration ~= false and path ~= nil)
                if path then
                    countdown:SetFont(path, size, flags)
                    PS.PlaceAuraCountdown(countdown, icon, position)
                    local plain, offset = countdown.plateSmithPlainShadow, countdown.plateSmithPlainOffset
                    if shadow ~= nil then
                        countdown:SetShadowColor(0, 0, 0, shadow and 1 or 0)
                        countdown:SetShadowOffset(1, -1)
                    elseif plain and plain[1] then
                        countdown:SetShadowColor(plain[1], plain[2], plain[3], plain[4])
                        countdown:SetShadowOffset(offset[1] or 0, offset[2] or 0)
                    end
                end
            end
        end
    end
end

PS.RegisterEditorComponent("buffs", {
    label = L["Buffs"], x = 0, y = 38, width = 78, height = 20,
    create = function(component)
        CreateAuraPreview(component, {
            "Interface\\Icons\\Spell_Nature_Rejuvenation",
            "Interface\\Icons\\Spell_Holy_PowerWordShield",
            "Interface\\Icons\\Spell_Nature_Regeneration",
            "Interface\\Icons\\Spell_Holy_BlessingOfProtection",
            "Interface\\Icons\\Spell_Holy_Renew",
            "Interface\\Icons\\Spell_Nature_LightningShield",
            "Interface\\Icons\\Spell_Holy_MagicalSentry",
            "Interface\\Icons\\Spell_Nature_Thorns",
        })
    end,
    refresh = RefreshAuraPreview("buffs"),
})

PS.RegisterEditorComponent("debuffs", {
    label = L["Debuffs"], x = 0, y = -43, width = 78, height = 20,
    create = function(component)
        CreateAuraPreview(component, {
            "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
            "Interface\\Icons\\Spell_Fire_FlameBolt",
            "Interface\\Icons\\Ability_Rogue_Rupture",
            "Interface\\Icons\\Spell_Nature_Slow",
            "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
            "Interface\\Icons\\Spell_Frost_FrostBolt02",
            "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
            "Interface\\Icons\\Ability_Warrior_Sunder",
        })
    end,
    refresh = RefreshAuraPreview("debuffs"),
})

Options.editorCatalog = {
    editorDefaults = editorDefaults,
    editorOrder = editorOrder,
    editorLabels = editorLabels,
    editorDefinitions = editorDefinitions,
    VALUE_SLOT_COUNT = VALUE_SLOT_COUNT,
    barSourceChoices = barSourceChoices,
    iconChoices = iconChoices,
    valueSourceChoices = valueSourceChoices,
    valueSourceByKey = valueSourceByKey,
}
