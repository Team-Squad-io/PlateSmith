local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local model = assert(Options.studioModel)
local ThreatColours = assert(PS.ThreatColours, "PlateSmith ThreatColours missing")
local L = PS.L
local WidgetName = model.WidgetName

-- Studio's Threat colours controls (Nameplates/ThreatColours.lua). Settings › Behaviour & display ›
-- Threat colours holds the switch, this character's tank role, the shared colours and Apply to, where each part can
-- have its own colours (their swatches show only while it does). The Health bar's and Name's
-- inspectors have the same Apply to box, so it is found from the part too.
local STATE_LABELS = {
    holding = L["Holding"], losing = L["Losing it"], offtank = L["Other tank has it"], other = L["Someone else has it"],
    safe = L["Safe"], pulling = L["Pulling"], aggro = L["Aggro"],
}
local STATE_HELP = {
    holding = L["You hold its threat."],
    losing = L["You hold it, but someone is close to taking it."],
    offtank = L["Another tank in your group holds it."],
    other = L["Someone who is not a tank holds it."],
    safe = L["A tank or someone else holds it, and you are not close."],
    pulling = L["You are close to taking it from whoever holds it."],
    aggro = L["You hold its threat."],
}
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

-- Settings › Behaviour & display › Threat colours (Inspector's plate page builds the section).
function Options.BuildThreatColourSettings(SK, section, Bind)
    local get, set = Options.BindSetting("colourByThreat")
    Check(SK, section, Bind, "colourByThreat", L["Colour by threat"], get, set)
    SK.Add(section, SK.ControlHelp(section, L["Colours an enemy's health bar and name by who holds its threat, while it "
        .. "is in combat with you or your group. Where the game withholds that, a part keeps its own colour; a part's "
        .. "colour rule always wins."]))
    -- Who counts as a tank: this character's choice, as on Settings › Threat › Your role (saved at once).
    local tankRow, tank = SK.DropdownRow(section, L["This character tanks"], {
        choices = Options.tankRoleChoices or {}, name = WidgetName("editor_tankRole", "Dropdown"),
        get = function() return PS.GetCharacterSettings().tankRole end,
        set = function(value)
            local ok = PS.SetCharacterOption("tankRole", value)
            Options:Refresh(true)
            return ok
        end })
    SK.Add(section, tankRow, On)
    SK.Add(section, SK.ControlHelp(section, L["When threat colours, rules and the threat windows treat you "
        .. "as a tank. Saved for this character only."]))
    Bind("plate.tankRole", tank)
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
    for _, part in ipairs(ThreatColours.PARTS) do
        local key = ThreatColours.PART_SETTINGS[part]
        local partGet, partSet = Options.BindSetting(key)
        Check(SK, section, Bind, key, PART_LABELS[part], partGet, partSet, On)
        local function Applied() return On() and Settings()[key] == true end
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
end

-- A part's inspector box for its Apply to (the Health bar's and the Name's), on the enemy plate types
-- only: friendly units hold no threat on you. While Colour by threat is off the box reads unticked and
-- is unavailable (it would do nothing), and its tooltip says where to turn the colours on.
local function EnemyPlate() return Options:IsEditorEnemy() end
local OFF_TIP = L["Threat colours are off. Turn on Colour by threat in Settings › Behaviour & display › Threat colours."]
function Options.ThreatColourPartCheck(K, section, part)
    local key = ThreatColours.PART_SETTINGS[part]
    local get, set = Options.BindSetting(key)
    local row, checkbox = K.CheckRow(section, L["Threat"], { text = L["Colour by threat"], set = set,
        get = function() return On() and get() end, name = WidgetName("selected_" .. key, "Checkbox") })
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
    K.Add(section, row, EnemyPlate)
    Options.editorThreatPartChecks = Options.editorThreatPartChecks or {}
    Options.editorThreatPartChecks[part] = checkbox
    if K.AttachHelp then
        K.AttachHelp(row, L["Takes the threat colours while Colour by threat is on (Settings › Behaviour & display › "
            .. "Threat colours, with the role and colours). A colour rule on this part wins."])
    end
    checkbox.sharedNote = Options.SharedSettingNote(K, section, EnemyPlate)
    return checkbox
end
