local _, PS = ...
local unpack = unpack or table.unpack -- luacheck: ignore 143
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local catalog = assert(Options.editorCatalog)
local model = assert(Options.studioModel)
local editorLabels = catalog.editorLabels
local editorDefinitions = catalog.editorDefinitions
local editorProfiles = model.editorProfiles
local WidgetName = model.WidgetName
local editorProfileSet = { enemy = true, friendlyPlayer = true, friendlyNPC = true, enemyPlayer = true }
local Designs = assert(PS.Designs, "PlateSmith Designs missing")

local IsReadableValue = PS.Secret.IsReadable
local STYLE_DEFAULTS = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing").STYLE_DEFAULTS

-- A component that fails (another addon's, say) is reported once, not on every refresh or
-- slider step.
local reportedFailures = {}
local function ReportComponentFailure(stage, key, reason)
    local id = stage .. " " .. key
    if reportedFailures[id] then return end
    reportedFailures[id] = true
    PS.Chat.ReportError("Studio component " .. id, reason)
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
    return L["Your Character"]
end

local function MakeEditorComponent(parent, key, width, height)
    local component = CreateFrame("Button", WidgetName(key, "EditorComponent"), parent, "BackdropTemplate")
    component:SetSize(width, height)
    component:SetMovable(editorDefinitions[key].movable ~= false)
    component:EnableMouse(true)
    component:RegisterForDrag("LeftButton")
    component:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    component:SetBackdropBorderColor(0, 0, 0, 0)
    component:SetScript("OnEnter", function(instance)
        if Options.selectedComponent ~= key then instance:SetBackdropBorderColor(0.85, 0.75, 0.5, 0.6) end
    end)
    component:SetScript("OnLeave", function(instance)
        if Options.selectedComponent ~= key then instance:SetBackdropBorderColor(0, 0, 0, 0) end
    end)
    component:SetScript("OnMouseDown", function() Options:PressEditorComponent(key) end)
    component:SetScript("OnDragStart", function(instance) Options:StartEditorDrag(key, instance) end)
    component:SetScript("OnDragStop", function(instance) Options:StopEditorDrag(key, instance) end)
    return component
end

-- In dungeons and raids Blizzard draws friendly plates itself, and addons cannot draw on or size
-- them. Unless the test overlay is on, Players and Friendly NPCs › Dungeons & raids show only what
-- can change there: the name's font, which is Blizzard's shared one (Nameplates/NativeFonts.lua).
function Options:IsEditorBlizzardNames(settings)
    if self.editorDesign ~= "dungeon" then return false end
    if self.editorProfile ~= "friendlyPlayer" and self.editorProfile ~= "friendlyNPC" then return false end
    settings = settings or (type(PS.GetSettings) == "function" and PS.GetSettings())
    return not (settings and settings.experimentalDungeonFriendlyText == true)
end

-- Whether this plate type uses key (and it is on the plate: not deleted, unless includeRemoved).
function Options:IsEditorComponentRelevant(key, settings, includeRemoved)
    if not editorDefinitions[key] then return false end
    if self:IsEditorBlizzardNames(settings) then return key == "name" end
    -- The quest loot bag is the quest marker's other look (it swaps in, in the same place), so
    -- Studio shows the one Quest marker.
    if key == "questLoot" then return false end
    local position = self.editorLayout and self.editorLayout[key]
    if position and position.removed and not includeRemoved then return false end
    settings = settings or (type(PS.GetSettings) == "function" and PS.GetSettings())
    local friendlyMode = self.editorDesign == "dungeon" and "full"
        or (self.editorFriendlyView or (settings and settings.friendly))
    if key:match("^value%d+$") then
        local profile = self:EditorProfileSettings()
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if not slot or slot.source == "off" then return false end
        if not self:IsEditorEnemy() and friendlyMode ~= "full" then return false end
        return true
    end
    if self:IsEditorEnemy() then
        return key ~= "guild" and key ~= "relationshipIcon" and key ~= "pvpIcon"
    end
    if friendlyMode == "off" or not friendlyMode then return false end
    if key == "health" or key == "power" or key == "cast" then return friendlyMode == "full" end
    if key == "threat" or key == "tagged" or key == "combo" or key == "targetedBy" then return false end
    if self.editorProfile == "friendlyPlayer" then
        return key ~= "quest" and key ~= "questLoot" and key ~= "classification"
    end
    return key ~= "relationshipIcon" and key ~= "pvpIcon" and key ~= "classification" and key ~= "guild"
end

-- Styles in the preview, over what each component's refresh has just drawn: font, Font size,
-- outline, shadow and box on text; texture, background and border on bars. A part whose text is not
-- its previewText (the cast bar's spell and time, the quest mark's progress, the badges' initials)
-- lists it as previewStyleTexts.
local PREVIEW_WHITE = "Interface\\Buttons\\WHITE8X8"
local function PreviewTextStyle(text, style, settings)
    if style.font or style.outline or style.fontSize then
        PS.ApplyNameplateFont(text, text.plateSmithFontSize or settings.nameFontSize or 12, style)
    end
    if style.shadow ~= nil and text.SetShadowColor then
        text:SetShadowColor(0, 0, 0, style.shadow and 1 or 0)
        text:SetShadowOffset(1, -1)
    end
end
function Options:ApplyEditorPreviewStyles(profile)
    local styles = profile and profile.styles or {}
    -- The health bar shows the test health % (Test values).
    local health = self.editorComponents and self.editorComponents.health
    local testPercent = self.templateSamples and tonumber(self.templateSamples["health.percent"])
    if health and health.previewBar and testPercent then health.previewBar:SetValue(testPercent) end
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or {}
    for key, component in pairs(self.editorComponents or {}) do
        -- Blizzard's own name takes none of PlateSmith's styles.
        local style = not component.previewNative and styles[key] or nil
        local text, bar = component.previewText, component.previewBar
        local styled = component.previewStyleTexts
        -- The plates' own font route (Nameplates/Factory), at the size the part's refresh gave it.
        if style and type(PS.ApplyNameplateFont) == "function" then
            if styled then
                for _, region in ipairs(styled) do PreviewTextStyle(region, style, settings) end
            elseif text then
                PreviewTextStyle(text, style, settings)
            end
        end
        -- The box behind the text.
        local box = component.styleBox
        if text and not styled and style and style.box then
            if not box then
                box = CreateFrame("Frame", nil, component, "BackdropTemplate")
                box:SetFrameLevel(math.max(0, component:GetFrameLevel() - 1))
                component.styleBox = box
            end
            local padding = style.padding or STYLE_DEFAULTS.padding
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", text, "TOPLEFT", -padding, padding)
            box:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", padding, -padding)
            -- Rounded: Blizzard's level box art, as on the plates (the square box where the client lacks it).
            if PS.StyleBox.Rounded(box, style.boxShape == "rounded") then
                box:SetBackdrop(nil)
            else
                box:SetBackdrop({ bgFile = PREVIEW_WHITE, edgeFile = PREVIEW_WHITE, edgeSize = 1 })
                local fill = style.boxColour or STYLE_DEFAULTS.boxColour
                box:SetBackdropColor(fill.r, fill.g, fill.b, fill.a or 1)
                local edge = style.boxBorder or STYLE_DEFAULTS.boxBorder
                box:SetBackdropBorderColor(edge.r, edge.g, edge.b, edge.a or 1)
            end
            box:Show()
        elseif box then
            box:Hide()
        end
        -- Bars.
        if bar then
            if style and style.texture then PS.Media.SetStatusBar(bar, style.texture) end
            if not component.styleBackground then
                component.styleBackground = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
                component.styleBackground:SetAllPoints(bar)
            end
            -- As the plates (Factory, Styles.StyledBar): every bar has its dark background, the style's
            -- colour or the default one, so a target glow behind the plate never shows through a bar.
            local background = style and style.background or STYLE_DEFAULTS.background
            component.styleBackground:SetColorTexture(background.r, background.g, background.b, background.a or 1)
            component.styleBackground:Show()
            local border = component.styleBorder
            local size = style and style.border or 0
            if size > 0 then
                if not border then
                    border = CreateFrame("Frame", nil, component, "BackdropTemplate")
                    border:SetFrameLevel(bar:GetFrameLevel() + 3)
                    component.styleBorder = border
                end
                border:ClearAllPoints()
                border:SetPoint("TOPLEFT", bar, "TOPLEFT", -size, size)
                border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", size, -size)
                border:SetBackdrop({ edgeFile = PREVIEW_WHITE, edgeSize = size })
                local colour = style.borderColour or { r = 0, g = 0, b = 0, a = 1 }
                border:SetBackdropBorderColor(colour.r, colour.g, colour.b, colour.a or 1)
                border:Show()
            elseif border then
                border:Hide()
            end
        end
    end
end

-- A blend's colour at percent: the plates' own blend (PS.StyleBlend), so the preview matches.
local function BlendColour(stops, percent)
    local r, g, b = PS.StyleBlend.Colour(stops, percent)
    return r and { r = r, g = g, b = b } or nil
end

-- Rules in the preview: with the sample values (Options.templateSamples), or every condition
-- holding while "Preview as if true" is ticked. The components' own refresh has just set their
-- normal look, so a rule only needs to put its colour or opacity over it. As on the plates, the
-- last colour or blend rule that holds sets the colour, the last opacity rule the opacity, and
-- any hide rule hides; an empty condition always holds.
function Options:ApplyEditorPreviewRules(profile)
    for _, component in pairs(self.editorComponents or {}) do component.previewRuleHidden = nil end
    self:ApplyEditorPreviewPartRules(profile)
    -- As on the plates: what sits under a part a rule hides (or fades to 0) hides with it; a
    -- turned-off part passes the question up to its own parent.
    local layout, components = self.editorLayout or {}, self.editorComponents or {}
    local function HiddenUnder(key, depth)
        local component = components[key]
        if component and component.targetPreviewVisible and component.previewRuleHidden then return true end
        local parent = layout[key] and layout[key].parent
        if not parent or parent:match("^group%.%d+$") or not layout[parent] or depth > PS.ProfileSchema.MAX_DEPTH then
            return false
        end
        return HiddenUnder(parent, depth + 1)
    end
    for key, component in pairs(components) do
        local parent = layout[key] and layout[key].parent
        if component.targetPreviewVisible and not component.previewNative and parent and HiddenUnder(parent, 0) then
            component:SetAlpha((component.GetAlpha and component:GetAlpha() or 1) * 0.12)
            component.previewRuleHidden = true
        end
    end
end

-- Threat colours in the preview, from the test values (ThreatColours.ForSample): the health bar and
-- the name where no rule colours them (ruled[key]), and the health bar's edge.
function Options:ApplyEditorPreviewThreat(ruled)
    local Threat, settings = PS.ThreatColours, PS.GetSettings and PS.GetSettings()
    if not Threat or not settings then return end
    local components, samples = self.editorComponents or {}, self.templateSamples or {}
    for _, key in ipairs(Threat.RULE_PARTS) do
        local component = components[key]
        local colour = not ruled[key] and Threat.ForSample(settings, key, samples)
        if colour and component and component:IsShown() and not component.previewNative then
            if component.previewBar then
                component.previewBar:SetStatusBarColor(colour.r, colour.g, colour.b)
            elseif component.previewText then
                component.previewText:SetTextColor(colour.r, colour.g, colour.b)
            end
        end
    end
    local health = components.health
    if not health then return end
    local colour = health:IsShown() and Threat.ForSample(settings, "border", samples)
    local edge = health.previewThreatEdge
    if colour and not edge then
        edge = CreateFrame("Frame", nil, health, "BackdropTemplate")
        edge:SetPoint("TOPLEFT", health, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 1, -1)
        edge:SetBackdrop({ edgeFile = PREVIEW_WHITE, edgeSize = 1 })
        if health.previewBar then edge:SetFrameLevel(health.previewBar:GetFrameLevel() + 2) end
        health.previewThreatEdge = edge
    end
    if not edge then return end
    if colour then edge:SetBackdropBorderColor(colour.r, colour.g, colour.b, 1) end
    edge:SetShown(colour and true or false)
end

function Options:ApplyEditorPreviewPartRules(profile)
    local rules = profile and profile.rules
    local ruled = {}
    if not rules or not PS.Template then
        self:ApplyEditorPreviewThreat(ruled)
        return
    end
    local samples, forced = self.templateSamples or {}, self.editorRulesPreviewTrue
    local function Read(token) return samples[token] end
    local percent = tonumber(samples["health.percent"]) or 72
    for key, list in pairs(rules) do
        local component = self.editorComponents and self.editorComponents[key]
        if component and component:IsShown() and not component.previewNative then
            local colour, alpha, hide
            for _, rule in ipairs(list) do
                -- A rule turned off never applies, not even as if its condition held.
                local always = rule.when == ""
                local tree = not always and PS.Template.CompileCondition(rule.when)
                if rule.enabled ~= false and (always or (tree and (forced or PS.Template.Test(tree, Read)))) then
                    if rule.set == "colour" then colour = rule.colour
                    elseif rule.set == "blend" and rule.stops then colour = BlendColour(rule.stops, percent)
                    elseif rule.set == "alpha" then alpha = rule.alpha
                    elseif rule.set == "hide" then hide = true end
                end
            end
            if colour then
                ruled[key] = true
                if component.previewBar then component.previewBar:SetStatusBarColor(colour.r, colour.g, colour.b)
                elseif component.previewTexture then component.previewTexture:SetVertexColor(colour.r, colour.g, colour.b)
                elseif component.previewText then component.previewText:SetTextColor(colour.r, colour.g, colour.b) end
            end
            if hide or alpha then
                local current = component.GetAlpha and component:GetAlpha() or 1
                component:SetAlpha(current * (hide and 0.12 or alpha))
            end
            component.previewRuleHidden = (hide or alpha == 0) or nil
        end
    end
    self:ApplyEditorPreviewThreat(ruled)
end

local function SetTargetPreviewStrength(options, strength)
    -- Blizzard's own name keeps its look (PlateSmith's target glow is not on its plates).
    for _, component in ipairs(options.targetPreviewTexts or {}) do
        local text = not component.previewNative and component.previewText
        if text and strength and component.targetPreviewVisible then
            text:SetShadowColor(1, 0.7, 0.14, strength)
            text:SetShadowOffset(1, -1)
        elseif text then
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

-- The pulsing glow's preview: a ticker entry, on only while the preview shows it.
local PULSE_TICKER = "studio.target-pulse"
PS.Ticker.Register(PULSE_TICKER, 0.05, function(_, now)
    SetTargetPreviewStrength(Options, 0.4 + 0.3 * (0.5 + 0.5 * math.sin((now or 0) * 3)))
end)
PS.Ticker.SetEnabled(PULSE_TICKER, false)

function Options:UpdateEditorPulse()
    local pulsing = self.targetPreviewStyle == "halo" and self.editor and self.editor:IsShown()
        and self.editorCanvas and self.editorCanvas:IsShown()
    PS.Ticker.SetEnabled(PULSE_TICKER, pulsing and true or false)
end

-- The soft glow style's preview: the plates' own glow (Nameplates/TargetGlow.lua), placed and coloured
-- as they do it, round the sample's bars and texts under every part, in the sample's colour (Test values' reaction; a
-- player sample in your class colour; Threat: the threat colour Test values' role and threat flags give, as the bars'
-- Threat colours take it, out of combat the custom colour). highlight: the design's (Schema's HIGHLIGHT).
local function SoftGlowColour(options, highlight)
    local samples, reactions = options.templateSamples or {}, PS.TargetGlow.REACTION
    local classFile -- never truth-tested: it may be protected (Glow.Colour reads it through Secret)
    if samples.player then classFile = PS.Secret.ClassFile("player") end
    local reaction = samples.hostile and reactions.hostile or samples.friendly and reactions.friendly or reactions.neutral
    local threat = highlight.targetGlowColourMode == "threat" and PS.ThreatColours
        and PS.ThreatColours.ForSample(PS.GetSettings(), PS.ThreatColours.GLOW, samples) or nil
    return PS.TargetGlow.Colour(highlight, classFile, reaction, threat)
end
local function EditorTransforms(_, options) return options:EditorTransforms() end
-- As on the plates, a part counts only while it draws something: not a faint sample (the cast bar while
-- Test values' Casting is off, which the plates hide, or a part turned off in Settings).
-- The design's part sizes as the stage draws them (its parts are sized at the profile's scale), for
-- Glow.Bounds' boxes.
local stageSizes = {}
local SIZE_FIELDS = { "width", "healthHeight", "powerWidth", "powerHeight", "castWidth", "castHeight", "nameFontSize" }
local function StageSizes(profile)
    local scale = tonumber(profile.scale) or 1
    for _, field in ipairs(SIZE_FIELDS) do
        local value = tonumber(profile[field])
        stageSizes[field] = value and value * scale or nil
    end
    if not stageSizes.castHeight and stageSizes.healthHeight then
        stageSizes.castHeight = math.max(5, (tonumber(profile.healthHeight) or 10) - 3) * scale
    end
    return stageSizes
end
-- The sample name's drawn width (Studio's own text, always readable), so a long one widens the glow.
local function EditorNameWidth(options)
    local component = options.editorComponents and options.editorComponents.name
    local text = component and component.previewText
    return text and PS.Secret.ReadNumber(text, "GetStringWidth") or nil
end
local function EditorEdgeDrawn(_, _, component)
    if component.previewIdle or not component.targetPreviewVisible then return false end
    local text = not component.previewBar and component.previewText
    if not text then return true end
    return (not text.GetText or (text:GetText() or "") ~= "") and (not text.GetAlpha or (text:GetAlpha() or 1) >= 0.99)
end

function Options:RefreshSoftGlowPreview(settings, shown)
    local Glow, glow = PS.TargetGlow, self.targetPreviewSoftGlow
    local components = self.editorComponents or {}
    local health, name = components.health, components.name
    if not (shown and name) then
        if glow then Glow.Hide(glow) end
        return
    end
    local stage = self.editorPreviewStage or self.editorCanvas
    if not glow then
        glow = Glow.Create(stage)
        self.targetPreviewSoftGlow = glow
    end
    Glow.SetLevel(glow, stage:GetFrameLevel())
    -- Its spread at the sample's drawn size (the preview's zoom and the profile's scale).
    local scale = health and health.GetScale and health:GetScale() or 1
    local spread = settings.targetGlowSpread
    Glow.Style(glow, { targetGlowSpread = spread and spread * scale, targetGlowOpacity = settings.targetGlowOpacity,
        targetGlowPulse = settings.targetGlowPulse, targetGlowOffsetX = (settings.targetGlowOffsetX or 0) * scale,
        targetGlowOffsetY = (settings.targetGlowOffsetY or 0) * scale })
    local layout = self.editorLayout or {}
    local barless = not (health and health:IsShown() and layout.health)
    Glow.Place(glow, Glow.Bounds(layout, components, barless, EditorTransforms, self,
        StageSizes(self:EditorProfileSettings() or settings), EditorEdgeDrawn, EditorNameWidth))
    Glow.Paint(glow, SoftGlowColour(self, settings))
    Glow.Show(glow)
end

-- settings: the general settings; the sample shows the open design's own highlight over them (Schema's
-- HIGHLIGHT), as its plates do.
function Options:RefreshTargetHighlightPreview(settings)
    if not self.editorCanvas then return end
    local highlight = PS.ProfileSchema.HIGHLIGHT.Resolve(settings, self:EditorProfileSettings(), self.editorHighlight)
    self.editorHighlight = highlight
    local style = highlight.targetHighlightStyle
    if self.targetPreviewStyle ~= style then
        self.targetPreviewStyle = style
        self:UpdateEditorPulse()
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
    -- Test values: only a targeted sample shows the glow, except while the Plate row (its Target
    -- highlight) is selected: then it always shows, and Test values stay as they are.
    local targeted = self.editorInspectingPlate == true and not self.selectedComponent
        or not (self.templateSamples and self.templateSamples.targeted == false)
    SetTargetPreviewStrength(self, targeted and (style == "border" and 0.7 or style == "halo" and 0.55) or nil)
    self:RefreshSoftGlowPreview(highlight, targeted and style == "glow" and not self:IsEditorBlizzardNames(settings))
end

-- Test values' reaction flags colour the sample's name: hostile red, friendly green for a
-- player or blue for an NPC, otherwise neutral yellow. Each plate type starts from its own; the
-- Enemies' Battlegrounds & arenas design from an enemy player.
local SAMPLE_REACTIONS = {
    enemy = { hostile = true, friendly = false, player = false },
    enemyPlayer = { hostile = true, friendly = false, player = true },
    friendlyPlayer = { hostile = false, friendly = true, player = true },
    friendlyNPC = { hostile = false, friendly = true, player = false },
}
local function SampleKind(plateType, design)
    if plateType == "enemy" and design == "pvp" then return "enemyPlayer" end
    return plateType
end
-- The import preview's plates take the same reactions.
function Options.EditorSampleReactions(plateType, design) return SAMPLE_REACTIONS[SampleKind(plateType, design)] end
local ENEMY_PLAYER_SAMPLE = L["Arena Challenger"]
-- View's sample name: the plates' own, or a name and guild in another alphabet, so the preview
-- shows whether the chosen font draws it (through the plates' font route, as a real name would be).
Options.editorSampleScripts = { { value = "latin", label = L["Latin"] } }
do
    local labels = { chinese = L["Chinese"], korean = L["Korean"], russian = L["Russian"] }
    for _, sample in ipairs(PS.Media.sampleNames) do
        Options.editorSampleScripts[#Options.editorSampleScripts + 1] = { value = sample.value,
            label = labels[sample.value], name = sample.name, guild = sample.guild }
    end
end
function Options:EditorSampleScript()
    for _, script in ipairs(self.editorSampleScripts) do
        if script.value == self.editorSampleScript then return script end
    end
    return self.editorSampleScripts[1]
end

-- Test values' Reset: the samples as made, with this plate type's reaction.
function Options:ResetEditorSamples(defaults)
    self.editorSampleScript = nil
    local samples = self.templateSamples
    for token in pairs(samples) do samples[token] = nil end
    for token, value in pairs(defaults) do samples[token] = value end
    for flag, value in pairs(SAMPLE_REACTIONS[SampleKind(self.editorProfile, self.editorDesign)] or {}) do
        samples[flag] = value
    end
end

local function SampleNameColour(samples)
    if samples.hostile then return 1, 0.25, 0.2 end
    if samples.friendly then
        if samples.player then return 0.25, 1, 0.45 end
        return 0.35, 0.9, 1
    end
    return 1, 0.9, 0.35
end

-- Blizzard's friendly names in a dungeon, as its plates draw them: a class-coloured player, a green
-- NPC. Its font: the chosen Blizzard name font while that is on (it applies in every instance
-- whatever its Where), else Blizzard's own (NativeFonts' original, else the client's standard face).
local BLIZZARD_NAME_SAMPLES = {
    friendlyPlayer = { text = L["Judgement Misclicked"], class = "PALADIN", colour = { 0.96, 0.55, 0.73 } },
    friendlyNPC = { text = L["Innkeeper Allison"], colour = { 0, 1, 0 } },
}
local BLIZZARD_NAME_OBJECT = "SystemFont_NamePlate_Outlined"
local BLIZZARD_NAME_FALLBACK = { size = 9, flags = "OUTLINE" }
function Options:EditorBlizzardNameFont(settings)
    local NativeFonts = PS.NativeFonts
    local path, size, flags
    if NativeFonts and NativeFonts.Original then
        path, size, flags = NativeFonts.Original(BLIZZARD_NAME_OBJECT)
        if not path then path, size, flags = NativeFonts.Original("SystemFont_NamePlate") end
    end
    path = path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    size, flags = size or BLIZZARD_NAME_FALLBACK.size, flags or BLIZZARD_NAME_FALLBACK.flags
    if not (settings and settings.blizzardNameFont == true) then return path, size, flags end
    local Schema = PS.ProfileSchema
    local outlines = NativeFonts and NativeFonts.OUTLINES or {}
    return PS.Media.FontPath(settings.blizzardNameFontFace) or path,
        Schema.Bounded(Schema.settingRanges.blizzardNameFontSize, settings.blizzardNameFontSize, 12),
        outlines[settings.blizzardNameFontOutline] or "OUTLINE"
end

function Options:ApplyEditorBlizzardName(settings)
    local component = self.editorComponents and self.editorComponents.name
    local text = component and component.previewText
    local sample = BLIZZARD_NAME_SAMPLES[self.editorProfile]
    if not (text and sample) then return end
    text:SetText(self:EditorSampleScript().name or sample.text)
    local class = sample.class and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[sample.class]
    local colour = sample.colour
    if type(class) == "table" and type(class.r) == "number" then colour = { class.r, class.g, class.b } end
    text:SetTextColor(colour[1], colour[2], colour[3])
    local path, size, flags = self:EditorBlizzardNameFont(settings)
    -- The plates' font route (Factory) keeps its own size mark and gives the face back on the next
    -- refresh after this layout is left. Blizzard's names are a font family (its faces for every
    -- alphabet), so the sample is drawn through one too where the client can.
    if not PS.Media.SetFamilyFont(text, path, size, flags) then
        if text.SetTextScale then text:SetTextScale(1) end
        if text.SetFont then text:SetFont(path, size, flags) end
        text.plateSmithOwnFace = true
    end
    -- One line, as on Blizzard's plates (a long name measured as wrapped makes a tall outline).
    if text.SetWordWrap then
        text:SetWordWrap(false)
        text.previewNoWrap = true
    end
    if text.SetShadowColor then
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(flags == "" and 1 or 0, flags == "" and -1 or 0)
    end
end

-- The client keeps a face set with SetFont over any font object set later, so a preview text that
-- had one (plateSmithOwnFace: a fallback where no family could be made) never draws through a font
-- family again, and a name in another alphabet shows boxes. Where a family can be made such a text
-- is swapped for a fresh one, at most RENEW_LIMIT times per part.
local RENEWED_TEXTS = { name = true, guild = true }
local RENEW_LIMIT = 2
local function RenewPreviewText(component)
    local old = component.previewText
    if not (old and old.plateSmithOwnFace) or (component.previewTextRenewals or 0) >= RENEW_LIMIT
        or not PS.Media.FamilyAvailable() then
        return old
    end
    local ok, text = pcall(component.CreateFontString, component, nil, "OVERLAY", "GameFontNormal")
    if not ok or type(text) ~= "table" then return old end
    component.previewTextRenewals = (component.previewTextRenewals or 0) + 1
    for index = 1, old.GetNumPoints and old:GetNumPoints() or 0 do text:SetPoint(old:GetPoint(index)) end
    if (old.GetNumPoints and old:GetNumPoints() or 0) == 0 then text:SetPoint("CENTER") end
    -- Studio's own sample text and colours, never a unit's.
    text:SetText(old:GetText() or "")
    text:SetTextColor(old:GetTextColor())
    text:SetShadowColor(old:GetShadowColor())
    text:SetShadowOffset(old:GetShadowOffset())
    text.plateSmithFontSize = old.plateSmithFontSize
    old:SetText("")
    old:Hide()
    component.previewText = text
    return text
end

-- The preview's look from the settings, then its layout (sizes and text widths move stacked and
-- pinned parts). light: a value is being dragged, so the tree and the inspector are left alone.
function Options:RefreshEditorAppearance(settings, light)
    if not self.editorComponents or not settings then return end
    local profile = self:EditorProfileSettings() or settings
    local blizzardNames = self:IsEditorBlizzardNames(settings)
    for key, component in pairs(self.editorComponents) do
        component.previewNative = blizzardNames and key == "name" or nil
        local wrapped = component.previewText
        if not component.previewNative and wrapped and wrapped.previewNoWrap then
            wrapped:SetWordWrap(true)
            wrapped.previewNoWrap = nil
        end
        local definition = editorDefinitions[key]
        if RENEWED_TEXTS[key] then RenewPreviewText(component) end
        local baseText, baseBar = component.previewBaseText, component.previewBaseBar
        if baseText and component.previewText then component.previewText:SetTextColor(unpack(baseText)) end
        -- No face is put back here: each text's font is set again by its refresh or style, and a face
        -- set with SetFont would stay over the plates' font family on the client (boxes for CJK).
        if baseBar and component.previewBar and component.previewBar == component.previewBaseBarFrame then
            component.previewBar:SetStatusBarColor(unpack(baseBar))
        end
        if definition and type(definition.refresh) == "function" then
            local succeeded, reason = pcall(definition.refresh, component, profile)
            if not succeeded then ReportComponentFailure("refresh", key, reason) end
        end
        local position = self.editorLayout and self.editorLayout[key]
        local relevant = self:IsEditorComponentRelevant(key, settings)
        local globallyEnabled = relevant
            and (key ~= "pvpIcon" or settings.friendlyPvpStyle == "icon" or settings.friendlyPvpStyle == "both")
        -- Blizzard's own name always shows: its eye and rules are PlateSmith's, not on its plates.
        component.targetPreviewVisible = component.previewNative
            or globallyEnabled and position and position.visible ~= false
        component.previewFitVisible = component.targetPreviewVisible
        component:SetShown(relevant)
        if component.previewNative then
            component:SetAlpha(1)
        elseif relevant then
            component:SetAlpha((position and position.visible == false) and 0.18 or (globallyEnabled and 1 or 0.35))
        end
        -- Its alpha is set anew: RefreshEditorComponentLayers decides again whether it is a stack ghost.
        component.ghostApplied, component.ghostAlpha = nil, nil
    end
    -- A part turned off leaves what sits under it shown (a pinned part takes its place, as on the
    -- plates); what a rule hides takes its children with it (ApplyEditorPreviewRules, below).
    self:RefreshEditorComponentLayers()
    if not light then self:RefreshEditorComponentList(settings) end
    local sample
    for _, definition in ipairs(editorProfiles) do
        if definition.key == self.editorProfile then sample = definition break end
    end
    local name = self.editorComponents.name
    if name and name.previewText and sample then
        local text = SampleKind(self.editorProfile, self.editorDesign) == "enemyPlayer" and ENEMY_PLAYER_SAMPLE
            or sample.sampleName
        if self.editorProfile == "friendlyPlayer" then
            -- As on the plates (Nameplates/Identity): without surnames only the first word shows.
            text = CurrentCharacterName()
            if settings.showPlayerSurnames == false then text = text:match("^(%S+)") or text end
        end
        name.previewText:SetText(self:EditorSampleScript().name or text)
        local colour = self.editorProfile == "friendlyPlayer"
            and (settings.friendlyPvpStyle == "colour" or settings.friendlyPvpStyle == "both")
            and settings.relationshipColours and settings.relationshipColours.pvp
        if colour then
            name.previewText:SetTextColor(colour.r, colour.g, colour.b)
        else
            name.previewText:SetTextColor(SampleNameColour(self.templateSamples or {}))
        end
    end
    local level = self.editorComponents.level
    if level and level.previewText then
        level.previewText:SetText(self:IsEditorEnemy() and "14" or "15")
    end
    local guild = self.editorComponents.guild
    if guild and guild.previewText and self.editorProfile == "friendlyPlayer" then
        local ok, guildName = false, nil
        if type(GetGuildInfo) == "function" then ok, guildName = pcall(GetGuildInfo, "player") end
        local script = self:EditorSampleScript()
        if script.guild then
            guild.previewText:SetText(script.guild)
        elseif ok and IsReadableValue(guildName) and type(guildName) == "string" and guildName ~= "" then
            guild.previewText:SetText("<" .. guildName .. ">")
        else
            guild.previewText:SetText(L["<Guild Name>"])
        end
    end
    -- A selected group or the Plate row has no component; it stays selected.
    local inspectingOther = self.selectedComponent == nil and (self.editorSelectedGroup or self.editorInspectingPlate)
    if not light and not inspectingOther and not self:IsEditorComponentRelevant(self.selectedComponent, settings) then
        self:SelectEditorComponent(self:IsEditorComponentRelevant("name", settings) and "name" or nil)
    elseif not light then
        self:RefreshEditorInspectorContext()
    end
    self:RefreshTargetHighlightPreview(settings)
    -- Styles and rules last, over every colour and text set above (the sample name's colour too).
    self:ApplyEditorPreviewStyles(profile)
    self:ApplyEditorPreviewRules(profile)
    if blizzardNames then self:ApplyEditorBlizzardName(settings) end
    -- Again, now what the rules hide is known: a hidden part's ghost goes under the drawn ones.
    self:RefreshEditorComponentLayers()
    -- Sizes and text are final: lay the parts out again from them.
    self:InvalidateEditorTransforms()
    self:RefreshEditorLayout()
    -- And with every part in its place, which ghosts lie over a drawn part (IsEditorStackGhost).
    self:RefreshEditorComponentLayers()
    -- Blizzard's name was given its font after the selection outline was placed: hug it again.
    if blizzardNames then self:UpdateEditorSelectionHandles() end
    if self.editorPreviewFit and not self.editorDrag then self:FitEditorPreview(self.editorPreviewFitZoom) end
    -- The model behind the plate follows its lowest part (PreviewModel.lua; nothing while Off).
    if self.PlaceEditorModel then self:PlaceEditorModel() end
end

-- The preview's Names only / Full plate switch: friendly plates, on every design but Dungeons &
-- raids (Blizzard's). The one the plates use now (Settings > Friendly units) is gold.
local LIVE_VIEW = { 1, 0.82, 0.2 }
function Options:RefreshEditorFriendlyViewButtons()
    local buttons = self.editorFriendlyViewButtons
    if not buttons then return end
    local friendly = (self.editorProfile == "friendlyPlayer" or self.editorProfile == "friendlyNPC")
        and self.editorDesign ~= "dungeon"
    local view, live = self:EditorFriendlyView(), self:EditorLiveFriendlyView()
    local chrome = self.studioChrome
    for key, button in pairs(buttons) do
        button:SetShown(friendly and true or false)
        chrome.SetStudioButtonState(button, key == view)
        if button.label then
            local colour = key == live and LIVE_VIEW or chrome.LABEL
            button.label:SetTextColor(colour[1], colour[2], colour[3])
        end
    end
end

-- The design Studio opens on a plate type: the one last edited there while it still exists, else World.
function Options:EditorDesignFor(plateType)
    if plateType == "enemyPlayer" then return "world" end
    local design = self.editorDesignByType[plateType] or "world"
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    if design ~= "world" and not (settings and Designs.HasDesign(settings, plateType, design)) then design = "world" end
    return design
end

-- Keeps the open view (zoom and pan) under its key and opens the one for the plate type, design and
-- layout now edited: each keeps its own, so a zoom on one leaves the others fitted.
local function SwitchEditorView(self)
    self.editorViews = self.editorViews or {}
    if self.editorViewKey then
        self.editorViews[self.editorViewKey] = {
            fit = self.editorPreviewFit ~= false, fitZoom = self.editorPreviewFitZoom,
            zoom = self.editorPreviewZoom, x = self.editorPreviewPanX, y = self.editorPreviewPanY }
    end
    self.editorViewKey = self.editorProfile .. "." .. self.editorDesign .. "." .. self:CurrentEditorVariant()
    local view = self.editorViews[self.editorViewKey]
    if view and not view.fit and view.zoom then
        self.editorPreviewPanX, self.editorPreviewPanY = view.x or 0, view.y or 0
        self:SetEditorPreviewZoom(view.zoom)
    else
        self.editorPreviewFit, self.editorPreviewFitZoom = true, view and view.fitZoom
    end
end

function Options:SetEditorProfile(profileKey)
    if not editorProfileSet[profileKey] then return false end
    local design = self:EditorDesignFor(profileKey)
    local changed = profileKey ~= self.editorProfile or design ~= self.editorDesign
    if changed and self.templateSamples then
        for flag, value in pairs(SAMPLE_REACTIONS[SampleKind(profileKey, design)]) do self.templateSamples[flag] = value end
    end
    -- A design's "added" banner belongs to the moment it was added (Options:AddEditorDesign).
    if changed then self.editorDesignAdded = nil end
    self.editorProfile, self.editorDesign = profileKey, design
    self.editorDesignByType[profileKey] = design
    SwitchEditorView(self)
    self:ReloadEditorLayoutCopy()
    for key, button in pairs(self.editorProfileButtons or {}) do
        self.studioChrome.SetStudioButtonState(button, key == profileKey)
    end
    self:RefreshEditorFriendlyViewButtons()
    -- This switch selects for the new view itself (below); Refresh only rebuilds a view a setting changes.
    self.editorBlizzardNamesShown = self:IsEditorBlizzardNames()
    self:Refresh(true)
    -- Changing the plate type goes back to Studio.
    if self.editorWorkspacePage == "settings" or self.editorInspectorPage ~= "components" then
        self:SetEditorInspectorPage("components")
    elseif self.LayoutEditorSettingsPanels then
        self:LayoutEditorSettingsPanels()
    end
    -- The Plate row (and its Quick layout) stays selected across plate types.
    if self.editorInspectingPlate and not self.selectedComponent then
        self:SelectEditorPlate()
    else
        self:SelectEditorComponent(self.selectedComponent or "name")
    end
    return true
end

-- Which design of the open plate type Studio edits: "world", or a context it has a design for
-- (Designs.HasDesign; friendly plates always have Dungeons & raids, Blizzard's).
function Options:SetEditorDesign(design)
    if not Designs.LABELS[design] then return false end
    -- Enemy players have one layer, over the Enemies' design wherever they are.
    if self.editorProfile == "enemyPlayer" and design ~= "world" then return false end
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    if design ~= "world" and not (settings and Designs.HasDesign(settings, self.editorProfile, design)) then return false end
    self.editorDesignByType[self.editorProfile] = design
    return self:SetEditorProfile(self.editorProfile)
end

-- Opens Studio on a plate type's design (nil: World) with a part selected: Settings' links, Search.
function Options:OpenEditorDesign(plateType, design, part)
    design = design or "world"
    if not editorProfileSet[plateType] or not Designs.LABELS[design] then return false end
    if plateType == "enemyPlayer" and design ~= "world" then return false end
    if not (self.editor and self.editor:IsShown()) and not (PS.OpenVisualEditor and PS.OpenVisualEditor()) then
        return false
    end
    self.editorDesignByType[plateType] = design
    if not self:SetEditorProfile(plateType) or self.editorDesign ~= design then return false end
    if part then self:SelectEditorComponent(part) end
    return true
end

-- Settings came back without the open design (Revert, a profile switch, an import): World instead.
function Options:CheckEditorDesign(settings)
    local design = self.editorDesign
    if design == "world" or Designs.HasDesign(settings, self.editorProfile, design) then return false end
    self.editorDesignByType[self.editorProfile] = nil
    self.editorDesign, self.editorDesignAdded = "world", nil
    SwitchEditorView(self)
    self:RefreshEditorFriendlyViewButtons()
    return true
end

function Options:CreateEditorComponent(key, definition)
    if not self.editorCanvas or self.editorComponents[key] then return self.editorComponents[key] end
    -- The import preview's plates make plain frames (MakeEditorComponentFrame): no selecting or dragging.
    local component = (self.MakeEditorComponentFrame or MakeEditorComponent)(self.editorPreviewStage or self.editorCanvas,
        key, definition.width, definition.height)
    component.editorDefinition = definition
    self.editorComponents[key] = component
    if type(definition.create) == "function" then
        local succeeded, reason = pcall(definition.create, component, self.editorCanvas)
        -- Its look as made: each refresh starts from it, so a style or rule the preview painted
        -- on goes away when it no longer applies.
        local text, bar = component.previewText, component.previewBar
        if text and text.GetTextColor then component.previewBaseText = { text:GetTextColor() } end
        if bar and bar.GetStatusBarColor then
            component.previewBaseBar, component.previewBaseBarFrame = { bar:GetStatusBarColor() }, bar
        end
        if not succeeded then ReportComponentFailure("creation", key, reason) end
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

local PENCIL = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up"
-- A tree row's name ends this far from the row's right: near the edge, or clear of the drag grip (at
-- -6, about 19 wide) while it shows.
local TREE_LABEL_RIGHT, TREE_LABEL_RIGHT_GRIP = -6, -26

-- A part's row in the component tree: its connector to the group, its eye (show or hide),
-- its name, and the kit's row art when selected or hovered.
function Options:CreateEditorComponentButton(key)
    if not self.editorListContent or not editorDefinitions[key] then return nil end
    local made = rawget(self.editorComponentButtons, key)
    if made then return made end
    local Theme = PS.StudioTheme
    local button = CreateFrame("Button", nil, self.editorListContent)
    button:SetSize(248, 29)
    local selection = button:CreateTexture(nil, "BACKGROUND")
    selection:Hide()
    button.selection = selection
    local hover = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    hover:Hide()
    button.hoverArt = hover
    button:SetScript("OnSizeChanged", function(instance)
        Theme.Place(instance.selection, "tree-part-row-selected", instance, 14, 0, instance:GetWidth() - 14, 28)
        Theme.Place(instance.hoverArt, "tree-part-row-hover", instance, 14, 0, instance:GetWidth() - 14, 28)
    end)
    -- The drag grip shows under the pointer: every row can be dragged to another place or group.
    local grip = button:CreateTexture(nil, "OVERLAY")
    Theme.Place(grip, "drag-handle-normal", button, 0, 0)
    grip:ClearAllPoints()
    grip:SetPoint("RIGHT", button, "RIGHT", key:match("^value%d+$") and -46 or -6, 0)
    grip:Hide()
    button.grip = grip
    button:HookScript("OnEnter", function(instance)
        instance.hoverArt:SetShown(not instance.selection:IsShown())
        instance.grip:Show()
        instance.label:SetPoint("RIGHT", instance, "RIGHT", instance.labelRight[2], 0)
    end)
    button:HookScript("OnLeave", function(instance)
        instance.hoverArt:Hide()
        instance.grip:Hide()
        instance.label:SetPoint("RIGHT", instance, "RIGHT", instance.labelRight[1], 0)
    end)
    -- The connector: a 2 px line down from the parent's eye and a short dash to this part's.
    local vertical = button:CreateTexture(nil, "ARTWORK")
    vertical:SetColorTexture(0.72, 0.58, 0.36, 0.9)
    vertical:SetPoint("TOPLEFT", button, "TOPLEFT", 21, 0)
    vertical:SetSize(2, 29)
    local horizontal = button:CreateTexture(nil, "ARTWORK")
    horizontal:SetColorTexture(0.72, 0.58, 0.36, 0.9)
    horizontal:SetPoint("TOPLEFT", button, "TOPLEFT", 23, -14)
    horizontal:SetSize(11, 2)
    button.connectors = { vertical, horizontal }
    -- A part with parts under it folds them away, as a group does (the arrow at its left).
    local fold = CreateFrame("Button", nil, button)
    fold:SetSize(18, 18)
    fold:SetPoint("LEFT", button, "LEFT", 1, 0)
    fold.art = fold:CreateTexture(nil, "ARTWORK")
    fold.art:SetAllPoints(fold)
    fold:SetScript("OnClick", function() self:ToggleEditorGroup(key) end)
    fold:Hide()
    function fold.SetFolded(instance, folded)
        Theme.Place(instance.art, folded and "expand-arrow-normal" or "collapse-arrow-normal", instance, 0, 0, 18, 18)
    end
    fold:SetFolded(false)
    button.fold = fold
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", button, "LEFT", 70, 0)
    -- Values keep room for their pencil and X at the row's right. Other rows use the drag grip's room
    -- too while it is hidden, so a nested part's name shows in full; under the pointer the name gives
    -- the grip its room (the client ends a name that no longer fits with "...", and the row's tooltip
    -- names it whole).
    local value = key:match("^value%d+$") ~= nil
    button.labelRight = value and { -66, -66 } or { TREE_LABEL_RIGHT, TREE_LABEL_RIGHT_GRIP }
    label:SetPoint("RIGHT", button, "RIGHT", button.labelRight[1], 0)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(false) end
    label:SetText(editorLabels[key])
    label:SetFont(self.studioChrome.FONT, 15)
    button.label = label
    local visibility = self.studioChrome.CreateVisibilityEye(button, function(instance)
        self:SetEditorComponentVisibility(key, instance:GetChecked() and true or false)
    end)
    visibility:SetPoint("LEFT", button, "LEFT", 35, 0)
    visibility:SetChecked(true)
    button.visibility = visibility
    -- Custom values carry an X to remove them (it asks first).
    if key:match("^value%d+$") then
        local remove = CreateFrame("Button", nil, button)
        remove:SetSize(16, 16)
        remove:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        remove:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
        remove:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        remove:SetScript("OnClick", function() self:ConfirmRemoveValueSlot(key) end)
        PS.UI.Controls.AttachTooltip(remove, PS.L["Remove"], { PS.L["Remove this custom part from the plate."] })
        button.remove = remove
        -- ...and a pencil to name it: it selects the value and puts the cursor in its name.
        local rename = CreateFrame("Button", nil, button)
        rename:SetSize(16, 16)
        rename:SetPoint("RIGHT", remove, "LEFT", -4, 0)
        rename:SetNormalTexture(PENCIL)
        rename:SetHighlightTexture(PENCIL, "ADD")
        rename:SetScript("OnClick", function() self:BeginEditorTreeRename(key) end)
        PS.UI.Controls.AttachTooltip(rename, PS.L["Rename"], { PS.L["Give this custom part its own name."] })
        button.rename = rename
    end
    -- Titled with the name the tree shows now (a renamed custom part's own), whole.
    PS.UI.Controls.AttachTooltip(button, function() return self:EditorComponentLabel(key) end,
        { PS.L["Click to select; the eye shows or hides it. "
        .. "Right-click for more; drag to move it in the tree."] })
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(instance, mouseButton)
        if mouseButton == "RightButton" then self:OpenEditorContextMenu(key, instance) return end
        self:SelectEditorComponent(key)
    end)
    button:SetScript("OnDoubleClick", function() self:BeginEditorTreeRename(key) end)
    -- Drag a part onto a group's heading to move it into that group.
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() self:StartEditorTreeDrag("part", key) end)
    button:SetScript("OnDragStop", function() self:StopEditorTreeDrag() end)
    -- The tree places it (RefreshEditorComponentList, which asks for the rows it shows).
    self.editorComponentButtons[key] = button
    return button
end
