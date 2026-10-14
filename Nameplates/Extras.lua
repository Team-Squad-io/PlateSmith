-- Extras on Blizzard's plates: what PlateSmith adds while Who draws the plates is Blizzard, with PlateSmith extras
-- (mode overlay) and no other nameplate addon draws them. Blizzard draws its plate; PlateSmith never moves, resizes,
-- hides or restyles its frames. Its own regions (on the plate's overlay, as on any plate) are anchored to Blizzard's
-- unit frame's health bar and name, read as fields only: the quest marker left of the name, the threat text above it,
-- the Loose mark right of it, a thin threat edge round the bar and the target's soft glow behind it. Nothing is
-- measured (Forever keeps plate positions and sizes secret). Blizzard already draws raid marks and elite icons, so
-- PlateSmith adds neither; objects keep PlateSmith's own Objects plates (Lifecycle's rounds.Owns). Friendly plates in
-- dungeons & raids are Blizzard's protected frames and get nothing. Beside another addon's plates (Automatic, or this
-- choice with one running) the overlay keeps its old place over the plate, with the quest marker and threat text only.
-- Studio's sample (Studio/Extras.lua) places and paints its extras through the same functions.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

local Extras = {}
PS.Extras = Extras
local EXTRAS = S.EXTRAS
-- The threat edge: its width, and how far outside the bar it sits.
Extras.EDGE, Extras.EDGE_OUTSET = 2, 1
-- Gaps (px, the overlay's units) between Blizzard's name or bar and what sits beside it.
Extras.GAP = 3

-- Whether PlateSmith's extras go on Blizzard's own plates now: Blizzard, with PlateSmith extras, and no other nameplate
-- addon drawing them.
function Extras.OnBlizzard(settings)
    return type(settings) == "table" and settings.mode == "overlay" and PS.Conflicts.CachedProvider() == nil
end

-- A field of a frame Blizzard owns, read only (a key its own code set on it): nil unless it is a region or frame.
local function Field(owner, key)
    if type(owner) ~= "table" then return nil end
    local value = owner[key]
    if type(value) == "table" and type(value.SetPoint) == "function" then return value end
    return nil
end

-- Blizzard's health bar and name on a nameplate root (its unit frame's; the 12.x clients keep the bar in
-- HealthBarsContainer), or nil each.
function Extras.NativeRegions(root)
    local frame = Field(root, "UnitFrame")
    if not frame then return nil, nil end
    local bar = Field(Field(frame, "HealthBarsContainer"), "healthBar") or Field(frame, "healthBar")
    return bar, Field(frame, "name")
end

local function Anchor(region, point, relative, relativePoint, x, y)
    region:ClearAllPoints()
    if relative and pcall(region.SetPoint, region, point, relative, relativePoint, x, y) then return true end
    region:ClearAllPoints()
    return false
end

-- Places the extras of parts (a plate's data, or Studio's sample: threat, quest, looseMark, extrasEdge, overlay) on
-- bar and name (Blizzard's regions; either may be nil). With neither, the old overlay places: the threat text over
-- the overlay, the quest marker left of it. Returns whether they were anchored to Blizzard's regions.
function Extras.Place(parts, bar, name)
    local over = name or bar
    local threat, quest = parts.threat, parts.quest
    local native = over ~= nil and Anchor(threat, "BOTTOM", over, "TOP", 0, 2)
    if not native then
        Anchor(threat, "BOTTOM", parts.overlay, "TOP", 0, 2)
        Anchor(quest, "RIGHT", threat, "LEFT", -4, 0)
        if parts.looseMark then Anchor(parts.looseMark, "LEFT", threat, "RIGHT", 4, 0) end
        return false
    end
    if not Anchor(quest, "RIGHT", over, "LEFT", -Extras.GAP, 0) then Anchor(quest, "RIGHT", threat, "LEFT", -4, 0) end
    if parts.looseMark and not Anchor(parts.looseMark, "LEFT", over, "RIGHT", Extras.GAP, 0) then
        Anchor(parts.looseMark, "LEFT", threat, "RIGHT", 4, 0)
    end
    local edge = parts.extrasEdge
    if edge then
        local outset = Extras.EDGE + Extras.EDGE_OUTSET
        edge:ClearAllPoints()
        if not (bar and pcall(edge.SetPoint, edge, "TOPLEFT", bar, "TOPLEFT", -outset, outset)
            and pcall(edge.SetPoint, edge, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", outset, -outset)) then
            edge:ClearAllPoints()
            edge:Hide()
        end
    end
    return true
end

-- The thin threat edge: made on first need, under parent (the overlay), hidden.
function Extras.CreateEdge(parent)
    local edge = PS.EdgeFrame(parent, Extras.EDGE)
    if edge.EnableMouse then edge:EnableMouse(false) end
    edge:Hide()
    return edge
end

-- The edge's colour: the shared Threat colours for your role and the mob's state (ThreatColours' part "extras"),
-- readable or picked inside the client from protected answers. True when painted; false hides it (no state, Safe
-- while it keeps the part's colour, not in combat with you or your group).
function Extras.PaintEdge(edge, data)
    local Threat = PS.ThreatColours
    local colour = Threat.ForPlate(data, Threat.EXTRAS)
    if colour then
        -- Its table is the state's colour: written only when that changes.
        if edge.plateSmithColour ~= colour then
            edge:SetBackdropBorderColor(colour.r, colour.g, colour.b, 1)
            edge.plateSmithColour = colour
        end
        return true
    end
    -- Picked inside the client from protected answers: written each time, never compared.
    edge.plateSmithColour = nil
    local folded, r, g, b = Threat.FoldForPlate(data, Threat.EXTRAS)
    if folded and pcall(edge.SetBackdropBorderColor, edge, r, g, b, 1) then return true end
    return false
end

-- Studio's sample (Studio/Extras.lua): the edge's colour for a threat record and role (tank: true or false), as
-- ForPlate picks it on a plate; nil for none.
function Extras.SampleEdgeColour(settings, info, tank)
    local Threat = PS.ThreatColours
    return Threat.Colour(settings, Threat.EXTRAS, Threat.PlateState(tank, info))
end

-- The level the glow takes: under Blizzard's unit frame (the root's own level; the unit frame is its child, above
-- it), so the glow lights the plate from behind instead of covering its bar.
local function UnderNative(root)
    if type(root) ~= "table" or type(root.GetFrameLevel) ~= "function" then return 0 end
    local ok, level = pcall(root.GetFrameLevel, root)
    if ok and IsReadable(level) and type(level) == "number" then return math.max(0, level) end
    return 0
end
Extras.UnderNative = UnderNative

-- The plate side. context: GetSettings, PlaceLoose (LooseMark's Ensure asks it for a mark made on an extras plate).
PS._CreatePlateExtras = function(context)
    local GetSettings = context.GetSettings
    local Glow = PS.TargetGlow
    local Pass = { plates = setmetatable({}, { __mode = "k" }) }

    local function HideEdge(data)
        if data.extrasEdge then data.extrasEdge:Hide() end
    end
    local function HideGlow(data)
        if data.extrasGlow and data.extrasGlow.shown then Glow.Hide(data.extrasGlow) end
        data.extrasGlowStyled = nil
    end

    -- Not on Blizzard's plate (now owned, undrawn or released): the flag goes, and what only the extras draw.
    function Pass.Clear(data)
        data.extras, data.extrasBar, data.extrasName, data.extrasNative = false, nil, nil, nil
        Pass.plates[data] = nil
        HideEdge(data)
        HideGlow(data)
    end

    -- A plate PlateSmith does not draw, laid out (Lifecycle's ApplyLayout): the extras placed on Blizzard's regions
    -- while Blizzard draws it, else in the overlay's old places. settings: the working copy.
    function Pass.Apply(data, settings)
        settings = settings or GetSettings()
        local onBlizzard = Extras.OnBlizzard(settings) and not data.object
        local bar, name
        if onBlizzard then bar, name = Extras.NativeRegions(data.root) end
        data.extras, data.extrasBar, data.extrasName = onBlizzard, bar, name
        data.extrasGlowStyled = nil
        Pass.plates[data] = onBlizzard or nil
        if onBlizzard and bar and EXTRAS.Edge(settings) and data.friendly == false and not data.extrasEdge then
            data.extrasEdge = Extras.CreateEdge(data.overlay)
        end
        data.extrasNative = Extras.Place(data, bar, name)
        -- The mark's layer follows its layout entry on an owned plate (ShowUsedFrames); here it is the extras'.
        if data.looseMarkLayer then data.looseMarkLayer:SetShown(onBlizzard) end
        if not (onBlizzard and bar) then
            HideEdge(data)
            HideGlow(data)
        end
    end

    -- A Loose mark made on this plate after it was laid out: placed with the others.
    function Pass.PlaceLoose(data)
        if not data.extras then return end
        Extras.Place(data, data.extrasBar, data.extrasName)
        if data.looseMarkLayer then data.looseMarkLayer:Show() end
    end

    -- The threat edge after the plate's threat record changed (Lifecycle's UpdateThreat), and the glow's colour in
    -- its Threat mode.
    function Pass.Threat(data, settings)
        if not data.extras then return end
        settings = settings or GetSettings()
        local edge = data.extrasEdge
        if edge then
            local wanted = data.extrasBar ~= nil and EXTRAS.Edge(settings) and data.friendly == false
            edge:SetShown(wanted and Extras.PaintEdge(edge, data) or false)
        end
        local glow, highlight = data.extrasGlow, data.extrasHighlight
        if glow and glow.shown and highlight and highlight.targetGlowColourMode == "threat" then
            Glow.ColourFor(glow, highlight, data.unit, data.friendly, data)
        end
    end

    -- The target's soft glow behind Blizzard's plate (Lifecycle's UpdateTarget): in the design's glow look (its
    -- Target highlight's colour, size, opacity and pulse; Schema's HIGHLIGHT), round Blizzard's health bar.
    function Pass.Target(data, targeted, settings)
        settings = settings or GetSettings()
        if not (targeted and data.extras and data.extrasBar and settings.extrasTarget == true) then
            HideGlow(data)
            return
        end
        local glow = data.extrasGlow
        -- Shown and styled since the plate was laid out (a settings change lays it out again): nothing to do on the
        -- state pass's visits to the target.
        if glow and glow.shown and data.extrasGlowStyled then return end
        if not glow then
            glow = Glow.Create(data.overlay)
            data.extrasGlow = glow
        end
        local highlight = S.HIGHLIGHT.Resolve(settings, data.profile, data.extrasHighlight)
        data.extrasHighlight = highlight
        local bar = data.extrasBar
        local ok = pcall(function()
            Glow.SetLevel(glow, UnderNative(data.root))
            Glow.Style(glow, highlight)
            Glow.Place(glow, bar, bar, bar, bar)
            Glow.ColourFor(glow, highlight, data.unit, data.friendly, data)
        end)
        if ok then
            Glow.Show(glow)
            data.extrasGlowStyled = true
        else
            HideGlow(data)
        end
    end

    -- A glow setting changed (TargetGlow's RestyleShown): the glows shown on Blizzard's plates restyle too.
    function Pass.RestyleShown(settings)
        for data in pairs(Pass.plates) do
            if data.extrasGlow and data.extrasGlow.shown then
                data.extrasGlowStyled = nil
                Pass.Target(data, true, settings)
            end
        end
    end

    function Pass.Release(data) Pass.Clear(data) end

    Extras._pass = Pass
    return Pass
end

-- For /ps diagnose (extras): the choice, whether the extras are on Blizzard's plates now, which are on, and for the
-- plates that have them how many found Blizzard's regions and show an edge, a glow or the Loose mark. Readable
-- values only.
function Extras.Report(settings)
    settings = settings or (type(PS.GetSettings) == "function" and PS.GetSettings()) or {}
    local pass = Extras._pass
    local report = { mode = settings.mode, onBlizzard = Extras.OnBlizzard(settings), quest = settings.extrasQuest == true,
        threat = settings.extrasThreat, target = settings.extrasTarget == true, loose = settings.extrasLoose == true,
        plates = 0, anchored = 0, edges = 0, glows = 0, looseShown = PS.LooseMark and PS.LooseMark.ShownCount() or 0 }
    for data in pairs(pass and pass.plates or {}) do
        if data.extras then
            report.plates = report.plates + 1
            if data.extrasNative then report.anchored = report.anchored + 1 end
            if data.extrasEdge and data.extrasEdge:IsShown() then report.edges = report.edges + 1 end
            if data.extrasGlow and data.extrasGlow.shown then report.glows = report.glows + 1 end
        end
    end
    -- Plates with the extras but none of Blizzard's regions to anchor to: the client's plate is not as expected.
    report.regions = report.plates == 0 and "none" or report.anchored == report.plates and "readable"
        or report.anchored == 0 and "missing" or "partial"
    return report
end
