local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local model = assert(Options.studioModel)
local ThreatColours = assert(PS.ThreatColours, "PlateSmith ThreatColours missing")
local L = PS.L
local WidgetName = model.WidgetName

-- Studio's Threat colours controls (Nameplates/ThreatColours.lua). Settings › Modules › Threat (Settings/ThreatPage.lua)
-- holds them: Your role's fixed-role line and legend, then Threat colours' switch (the one for every design), the
-- shared colours and Apply to, where each part can have its own colours (their swatches show only while it does).
-- Which parts take them is each design's own: the Health bar's (the bar and its edge) and Name's inspector boxes
-- (ThreatColourPartCheck); Apply to says where each is on.
local STATE_LABELS, STATE_HELP = ThreatColours.STATE_LABELS, ThreatColours.STATE_HELP
local PART_LABELS = { health = L["Health bar"], name = L["Name text"], border = L["Health bar edge"] }
-- The role a profile can fix (threatColourRole; "auto" follows This character tanks and is never named).
local ROLE_LABELS = { tank = L["Tank"], dps = L["DPS & healer"] }
-- Own colours' rows sit in from the label column's edge.
local OWN_INSET = 16

local function Settings() return PS.GetSettings() end
local function On() return Settings().colourByThreat == true end

local function LabelOf(value) return ROLE_LABELS[value] or "" end

-- A state's swatch: the shared colour, or (part) that part's own.
local function Swatch(SK, section, Bind, state, part, shown)
    local id = "threatColour_" .. (part or "shared") .. "_" .. state
    local row, swatch = SK.SwatchRow(section, STATE_LABELS[state], {
        inset = part and OWN_INSET or nil, name = WidgetName("editor_" .. id, "Colour"),
        get = function()
            local settings = Settings()
            local own = part and settings.threatPartColours[part]
            return (own or settings.threatColours)[state]
        end,
        set = function(r, g, b)
            local ok = PS.SetThreatColour(state, r, g, b, part)
            Options:Refresh(true)
            return ok
        end,
    })
    if SK.AttachHelp then SK.AttachHelp(row, STATE_HELP[state]) end
    SK.Add(section, row, shown)
    Bind("plate." .. id, swatch)
end

local function Check(SK, section, Bind, id, text, get, set, shown, inset)
    local row, checkbox = SK.CheckRow(section, nil, { text = text, get = get, set = set, inset = inset,
        name = WidgetName("editor_" .. id, "Checkbox") })
    SK.Add(section, row, shown)
    Bind("plate." .. id, checkbox)
    return row, checkbox
end

-- The section's summary: Off, On (following this character's role), or the role the profile fixes.
function Options.ThreatColourSummary()
    if not On() then return L["Off"] end
    local role = Settings().threatColourRole
    return role == "auto" and L["On"] or LabelOf(role)
end

-- Modules › Threat › Your role, after This character tanks (Settings/ThreatPage.lua): what a profile fixes, and whom
-- the plates colour as now.
function Options.BuildThreatRoleSettings(SK, section)
    -- A profile can still fix the role (threatColourRole: older profiles, Blueprints). Then a line says
    -- so, with a button back to following this character's role. Its text is set as it is laid out.
    local fixed = SK.Note(section, "")
    local function Fixed()
        local role = Settings().threatColourRole
        if not On() or role == "auto" then return false end
        fixed.text:SetText(string.format(L["This profile always colours as: %s"], LabelOf(role)))
        return true
    end
    SK.Add(section, fixed, Fixed)
    local followRow, follow = SK.ButtonRow(section, L["Follow my role"], 140, nil, SK.CONTROL_X)
    follow:SetScript("OnClick", function()
        PS.SetOption("threatColourRole", "auto")
        Options:Refresh(true)
    end)
    PS.UI.Controls.AttachTooltip(follow, L["Follow my role"], { L["Threat colours follow This character tanks again, "
        .. "in this profile."] })
    SK.Add(section, followRow, Fixed)
    Options.editorThreatRoleNote, Options.editorThreatFollowRole = fixed, follow
    -- Whom the plates (and the threat windows) treat you as now, and why, with what each of that role's colours means.
    -- Its text is set as it is laid out (each refresh), from the same answer the plates use.
    local legend = SK.Note(section, "")
    SK.Add(section, legend, function()
        legend.text:SetText(ThreatColours.RoleLegendText(Settings()))
        return true
    end)
    Options.editorThreatLegend, Options.threatRoleLegend = legend, legend
end

-- Modules › Threat › Threat colours (Settings/ThreatPage.lua builds the section): the switch, the colours, Apply to
-- and the tank warning.
function Options.BuildThreatColourSettings(SK, section, Bind)
    local get, set = Options.BindSetting("colourByThreat")
    Check(SK, section, Bind, "colourByThreat", L["Colour by threat"], get, set)
    SK.Add(section, SK.ControlHelp(section, L["Colours an enemy's health bar and name by who holds its threat, while it "
        .. "is in combat with you or your group. Where the game withholds that, a part keeps its own colour; a part's "
        .. "colour rule always wins. Who counts as a tank: Your role, above."]))
    SK.Add(section, SK.SubHeader(section, L["Tank"]), On)
    for _, state in ipairs(ThreatColours.TANK_STATES) do Swatch(SK, section, Bind, state, nil, On) end
    SK.Add(section, SK.SubHeader(section, L["DPS & healer"]), On)
    for _, state in ipairs(ThreatColours.DPS_STATES) do
        Swatch(SK, section, Bind, state, nil, On)
        if state == "safe" then
            local keepGet, keepSet = Options.BindSetting("threatColourSafeKeep")
            local row = Check(SK, section, Bind, "threatColourSafeKeep", L["Safe keeps the part's colour"], keepGet, keepSet, On,
                OWN_INSET)
            if SK.AttachHelp then SK.AttachHelp(row, L["While someone else safely holds it, the part keeps its own colour."]) end
        end
    end
    SK.Add(section, SK.SubHeader(section, L["Apply to"]), On)
    SK.Add(section, SK.ControlHelp(section, L["Each design picks its parts: Colour by threat on the Health bar (the bar and "
        .. "its edge) and the Name, in Studio's inspector on the Enemies and Enemy players tabs."]), On)
    for _, part in ipairs(ThreatColours.PARTS) do
        -- Where the part takes the colours: a line, not a second box (the designs' own is the one source).
        local where = SK.Note(section, "")
        SK.Add(section, where, function()
            if not On() then return false end
            where.text:SetText(string.format(L["%s: %s"], PART_LABELS[part], Options.ThreatPartWhere(part)))
            return true
        end)
        Options.editorThreatApplied = Options.editorThreatApplied or {}
        Options.editorThreatApplied[part] = where
        local function Applied() return On() and Options.ThreatPartDesigns(part) > 0 end
        local function Own() return Applied() and Settings().threatPartColours[part] ~= nil end
        local row = Check(SK, section, Bind, "threatOwnColours_" .. part, L["Own colours"],
            function() return Settings().threatPartColours[part] ~= nil end,
            function(on)
                local ok = PS.SetThreatPartOwnColours(part, on)
                Options:Refresh(true)
                return ok
            end, Applied, OWN_INSET)
        if SK.AttachHelp then
            SK.AttachHelp(row, L["Colours for this part only, starting from the shared ones. Off: the shared colours again."])
        end
        for _, state in ipairs(ThreatColours.STATES) do Swatch(SK, section, Bind, state, part, Own) end
    end
    -- The tank warning's red edge, the health bar edge's other writer (audit #5). Not a threat colour: it shows with
    -- Colour by threat off too. Where a design's edge takes the threat colours, they show there instead: in every
    -- design, the box is unavailable and a line says why; in some, a line says so.
    local warnGet, warnSet = Options.BindSetting("tankWarning")
    local _, warn = Check(SK, section, Bind, "tankWarning", L["Warn when you lose a mob you tank"], warnGet, warnSet)
    local function EdgeTakesThreat()
        local on, total = Options.ThreatPartDesigns("border")
        return On() and total > 0 and on == total
    end
    local function EdgeSometimes()
        local on, total = Options.ThreatPartDesigns("border")
        return On() and on > 0 and on < total
    end
    local refresh = warn.Refresh
    function warn:Refresh()
        refresh(self)
        local available = not EdgeTakesThreat()
        PS.SaveBar.SetAvailable(self, available)
        if self.label then self.label:SetAlpha(available and 1 or 0.45) end
    end
    SK.Add(section, SK.ControlHelp(section, L["While you tank, an enemy's health bar edge turns red when you stop "
        .. "holding its threat."]))
    SK.Add(section, SK.Note(section, L["The edge takes the threat colours in every design (the Health bar's Threat "
        .. "edge)."]), EdgeTakesThreat)
    SK.Add(section, SK.Note(section, L["Where a design's edge takes the threat colours (the Health bar's Threat edge), "
        .. "they show there instead."]), EdgeSometimes)
    Options.editorTankWarning = warn
end

-- The enemy designs (Designs.EachDesign: the Enemies' and, while it changes anything, the Enemy players layer over
-- each) whose part takes the threat colours, and how many there are.
local ENEMY_PLATES = { enemy = true, enemyPlayer = true }
function Options.ThreatPartDesigns(part)
    local key, on, total = ThreatColours.PART_SETTINGS[part], 0, 0
    PS.Designs.EachDesign(Settings(), ENEMY_PLATES, function(profile)
        total = total + 1
        if profile[key] == true then on = on + 1 end
    end)
    return on, total
end
-- Apply to's line for part: every design, none, or how many.
function Options.ThreatPartWhere(part)
    local on, total = Options.ThreatPartDesigns(part)
    if on == total then return L["every design"] end
    if on == 0 then return L["no design"] end
    return string.format(L["%d of %d designs"], on, total)
end

-- A part's inspector box for its design's Colour by threat (the Health bar's, its edge's and the Name's), on the
-- enemy plate types only: friendly units hold no threat on you. A design option, so a design follows World (Enemy
-- players: the Enemies) until it changes it, with the changed-here mark. While Colour by threat is off the box reads
-- unticked and is unavailable (it would do nothing), and its tooltip says where to turn the colours on.
local function EnemyPlate() return Options:IsEditorEnemy() end
local OFF_TIP = L["Threat colours are off. Turn on Colour by threat in Settings › Modules › Threat › Threat colours."]
local PART_ROWS = {
    health = { L["Threat"], L["Colour by threat"], L["Takes the threat colours while Colour by threat is on (Settings "
        .. "› Modules › Threat › Threat colours, with the role and colours). A colour rule on this part wins."] },
    border = { L["Threat edge"], L["Colour edge by threat"], L["The health bar's edge takes the threat colours while "
        .. "Colour by threat is on, in place of the tank warning's red and the target's gold."] },
}
PART_ROWS.name = PART_ROWS.health
function Options.ThreatColourPartCheck(K, section, part)
    local key, labels = ThreatColours.PART_SETTINGS[part], PART_ROWS[part]
    local function Own()
        local profile = Options:EditorProfileSettings()
        return profile ~= nil and profile[key] == true
    end
    local row, checkbox = K.CheckRow(section, labels[1], { text = labels[2],
        set = function(on)
            local ok = PS.SetPlateProfileOption(Options:EditorTarget(), key, on == true)
            Options:Refresh(true)
            return ok
        end,
        get = function() return On() and Own() end, name = WidgetName("selected_" .. key, "Checkbox") })
    local refresh = checkbox.Refresh
    function checkbox:Refresh()
        refresh(self)
        local on = On()
        PS.SaveBar.SetAvailable(self, on)
        if self.label then self.label:SetAlpha(on and 1 or 0.45) end
    end
    checkbox:HookScript("OnEnter", function(instance)
        if On() or not GameTooltip then return end
        GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Colour by threat"], 1, 1, 1)
        GameTooltip:AddLine(OFF_TIP, 1, 0.82, 0.45, true)
        GameTooltip:Show()
    end)
    checkbox:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Options.RegisterControl(checkbox)
    K.ChangedMark(row, Options.editorMarkAreas.Option(key))
    K.Add(section, row, EnemyPlate)
    Options.editorThreatPartChecks = Options.editorThreatPartChecks or {}
    Options.editorThreatPartChecks[part] = checkbox
    if K.AttachHelp then K.AttachHelp(row, labels[3]) end
    return checkbox
end
