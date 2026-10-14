local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local model = assert(Options.studioModel)
local L = PS.L
local WidgetName = model.WidgetName

-- Studio's Extras on Blizzard's plates (Nameplates/Extras.lua): Settings › Behaviour & display › Extras on Blizzard's
-- plates, the one home for what PlateSmith adds while Who draws the plates is Blizzard, with PlateSmith extras. A
-- sample of Blizzard's own plate shows them, placed and painted by the plates' own routes (Extras.Place, the threat
-- text's, Threat colours', the soft glow's and the Loose mark's), for a loose mob as a tank sees it.
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local EXTRAS = S.EXTRAS
local THREAT_CHOICES = {
    { value = "both", label = L["Text and edge"],
        help = L["Your threat over Blizzard's name and a thin edge round its health bar in the threat colours."] },
    { value = "text", label = L["Text"], help = L["Your threat % and lead over Blizzard's name."] },
    { value = "edge", label = L["Edge"], help = L["A thin edge round Blizzard's health bar in the threat colours."] },
    { value = "off", label = L["Off"] },
}
-- The sample's mob: loose, as the Tank window's sample Gravelmaw Brute (Threat/Sample.lua), pulled off you by a
-- damage dealer. The sample is a tank's view of it.
local SAMPLE = { engaged = true, loose = true, holdState = "LOOSE", tanking = false, percent = 91, lead = -310,
    leadKind = "pull" }
local SAMPLE_HEIGHT = 88

local function Settings() return PS.GetSettings() end

-- How many extras are on, or that Blizzard does not draw the plates now.
function Options.ExtrasSummary()
    local settings = Settings()
    local on = 0
    for _, key in ipairs({ "extrasQuest", "extrasTarget", "extrasLoose" }) do
        if settings[key] == true then on = on + 1 end
    end
    if settings.extrasThreat ~= "off" then on = on + 1 end
    if settings.mode ~= "overlay" then return string.format(L["%d of %d on, not in use"], on, 4) end
    return string.format(L["%d of %d on"], on, 4)
end

-- The sample: a stand-in for Blizzard's unit frame (its bar texture in the hostile red, the name over it), and
-- PlateSmith's own regions over it, as on a plate.
local function BuildSample(SK, section)
    local holder = CreateFrame("Frame", nil, section)
    holder:SetSize(SK.WIDTH, SAMPLE_HEIGHT)
    local plate = CreateFrame("Frame", nil, holder)
    plate:SetSize(170, SAMPLE_HEIGHT)
    plate:SetPoint("CENTER", holder, "CENTER", 0, 0)
    local unit = CreateFrame("Frame", nil, plate)
    unit:SetAllPoints(plate)
    unit:SetFrameLevel(plate:GetFrameLevel() + 2)
    local bar = CreateFrame("StatusBar", nil, unit)
    bar:SetSize(110, 9)
    bar:SetPoint("CENTER", unit, "CENTER", 0, -10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.9, 0.1, 0.1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.72)
    local ground = bar:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints()
    ground:SetColorTexture(0.08, 0.08, 0.08, 0.85)
    local name = unit:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("BOTTOM", bar, "TOP", 0, 4)
    name:SetText(L["Gravelmaw Brute"])
    name:SetTextColor(1, 0.3, 0.25)
    local overlay = CreateFrame("Frame", nil, plate)
    overlay:SetAllPoints(plate)
    overlay:SetFrameLevel(plate:GetFrameLevel() + 6)
    local parts = { overlay = overlay }
    parts.threat = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if PS.ApplyNameplateFont then PS.ApplyNameplateFont(parts.threat, 10) end
    parts.quest = overlay:CreateTexture(nil, "OVERLAY")
    parts.quest:SetSize(16, 16)
    parts.quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    parts.looseMark = overlay:CreateTexture(nil, "OVERLAY")
    parts.extrasEdge = PS.Extras.CreateEdge(overlay)
    parts.glow = PS.TargetGlow.Create(overlay)
    holder.parts, holder.bar, holder.name, holder.plate = parts, bar, name, plate
    return holder
end

-- Draws the sample for settings: each extra as the plates would, for the Enemies' World design.
local function DrawSample(holder, settings)
    local parts, bar = holder.parts, holder.bar
    local Extras, Glow, LooseMark, ThreatText = PS.Extras, PS.TargetGlow, PS.LooseMark, PS.ThreatText
    local enemy = settings.plateProfiles and settings.plateProfiles.enemy
    Extras.Place(parts, bar, holder.name)
    parts.quest:SetShown(settings.extrasQuest ~= false)
    local text = EXTRAS.Text(settings)
    if text then
        ThreatText.Apply(parts.threat, SAMPLE, nil)
        ThreatText.ApplyStateColour(parts.threat, SAMPLE)
    end
    parts.threat:SetShown(text)
    local edgeColour = EXTRAS.Edge(settings) and Extras.SampleEdgeColour(settings, SAMPLE, true) or nil
    if edgeColour then parts.extrasEdge:SetBackdropBorderColor(edgeColour.r, edgeColour.g, edgeColour.b, 1) end
    parts.extrasEdge:SetShown(edgeColour ~= nil)
    local glow = parts.glow
    if settings.extrasTarget == true then
        local highlight = S.HIGHLIGHT.Resolve(settings, enemy)
        Glow.SetLevel(glow, holder.plate:GetFrameLevel())
        Glow.Style(glow, highlight)
        Glow.Place(glow, bar, bar, bar, bar)
        Glow.Paint(glow, Glow.Colour(highlight, nil, Glow.REACTION.hostile,
            Extras.SampleEdgeColour(settings, SAMPLE, true)))
        Glow.Show(glow)
    else
        Glow.Hide(glow)
    end
    local style = enemy and enemy.styles and enemy.styles.looseMark
    local size = LooseMark.Size(enemy and enemy.nameFontSize)
    parts.looseMark:SetSize(size, size)
    LooseMark.Paint(parts.looseMark, style)
    parts.looseMark:SetShown(settings.extrasLoose == true and LooseMark.Shows(style, true, true))
end
Options.DrawExtrasSample = DrawSample

-- Settings › Behaviour & display › Extras on Blizzard's plates (Inspector's plate page builds the section).
function Options.BuildExtrasSettings(SK, section, Bind)
    Options.editorExtrasSection = section
    SK.Add(section, SK.Help(section, L["While Who draws the plates is Blizzard, with PlateSmith extras, Blizzard draws its "
        .. "own plates and PlateSmith adds these to them, without moving or restyling them. Objects keep PlateSmith's "
        .. "own plates. Beside another nameplate addon's plates only the quest markers and threat text show."]))
    local function Check(key, text, help)
        local get, set = Options.BindSetting(key)
        local row, checkbox = SK.CheckRow(section, nil, { text = text, get = get, set = set,
            name = WidgetName("editor_" .. key, "Checkbox") })
        SK.Add(section, row)
        if help then SK.Add(section, SK.ControlHelp(section, help)) end
        Bind("plate." .. key, checkbox)
        return checkbox
    end
    Check("extrasQuest", L["Quest markers"], L["Left of Blizzard's name, with their progress where the Enemies' quest "
        .. "marker shows it."])
    do
        local get, set = Options.BindSetting("extrasThreat")
        local row, dropdown = SK.DropdownRow(section, L["Threat"], { choices = THREAT_CHOICES, get = get, set = set,
            name = WidgetName("editor_extrasThreat", "Dropdown") })
        SK.Add(section, row)
        SK.Add(section, SK.ControlHelp(section, L["The edge takes Threat colours' shared colours for your role; Safe "
            .. "shows none while Safe keeps the part's colour. The text shows while the Enemies' Threat part is on, as "
            .. "the quest markers do while their Quest marker is."]))
        Bind("plate.extrasThreat", dropdown)
    end
    Check("extrasTarget", L["Target glow"], L["A soft glow behind your target's plate, in the Enemies' (or friendly "
        .. "type's) Target highlight glow colour, size and pulse."])
    Check("extrasLoose", L["Loose mark"], L["Right of Blizzard's name while a mob is loose, for tanks; its icon, pulse "
        .. "and Show for are the Enemies' Loose mark's."])
    local sample = BuildSample(SK, section)
    SK.Add(section, sample)
    Options.editorExtrasSample = sample
    SK.Add(section, SK.Help(section, L["The sample is a tank's view of a loose mob on Blizzard's plate. Blizzard draws its "
        .. "own raid marks and elite icons, so PlateSmith adds none. Friendly plates in dungeons & raids are Blizzard's "
        .. "protected plates: nothing is added there."]))
    Options.RegisterControl({ Refresh = function() DrawSample(sample, Settings()) end })
    DrawSample(sample, Settings())
    return section
end
