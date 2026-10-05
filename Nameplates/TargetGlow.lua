-- The target's soft glow (targetHighlightStyle "glow"): one soft cloud of light in one colour behind the
-- target's whole plate, under every part: one continuous field, full across the plate (it shows round the
-- name's letters and between the parts) and fading steadily outward from its outline, with no edge.
-- Nine textures cut from one soft round texture (its quarters as the corners, its middle row and column
-- stretched along the sides, its centre across the middle) are anchored to the plate's own regions with
-- the spread as offsets. Nothing is measured, as a restricted plate's sizes can be secret. The slow pulse
-- is one AnimationGroup, made the first time it is asked for; without it nothing runs per frame. Studio's
-- preview draws the same glow (Glow.Create, Style, Place, Paint).
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

local Glow = {}
PS.TargetGlow = Glow
-- Blizzard's soft white disc (the combo points' glow).
Glow.TEXTURE = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
-- The cloud's disc (128 px, white). Its centre is the plate's edge (the middle piece stretches its centre
-- texel over the plate). Its alpha is full from the centre to 0.15 of the radius, so the pieces meet on
-- equal texels however the client filters them, then falls like a Gaussian to nothing at the rim, the
-- spread away. It never rises outward: a centre below the ring showed the plate's bounds as a darker
-- rectangle. Drawn with normal blending: an additive light washed out to white on bright ground.
Glow.HALO_TEXTURE = "Interface\\AddOns\\PlateSmith\\Media\\TargetGlow.png"
Glow.REACTION = { hostile = { 0.9, 0.16, 0.16 }, neutral = { 1, 0.82, 0 }, friendly = { 0.25, 0.9, 0.35 } }
-- The pulse: from full to PULSE_LOW of the glow's opacity and back, PULSE_SECONDS each way.
Glow.PULSE_LOW, Glow.PULSE_SECONDS = 0.35, 1.6
-- How far under the plate's overlay the glow sits: below every part, a Behind custom part (overlay - 1)
-- and its text box (overlay - 2).
Glow.LEVELS_UNDER = 3
-- Besides the health bar, the parts whose showing moves the glow's top or bottom (Glow.Bounds): the name,
-- power bar and cast bar, while they show and sit next to the bar. Nothing else (threat text, auras,
-- marks) ever stretches it.
Glow.EDGE_PARTS = { "name", "power", "cast" }
-- How far (layout units) an edge part's box may be from the body (the health bar's box, or a part already
-- taken in) and still be taken in: the default name, 7 px over the bar, and the Bars stack's 5 px gaps fit.
Glow.BODY_REACH = 12
-- A plate without a bar (names-only) is lit round its name line: the name and, across, the level and icons
-- pinned to it (NAME_LINE, directly or along a chain of pins), and down to the guild line under it while it
-- is within BODY_REACH of the name (UNDER_NAME). Marks and auras placed further off stay out.
Glow.NAME_LINE = { "level", "pvpIcon", "relationshipIcon" }
Glow.UNDER_NAME = { "guild" }

-- frame: anchored round the plate; body: its pieces and the pulse, so the pulse's alpha never replaces
-- the alpha the frame is given.
function Glow.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    if frame.EnableMouse then frame:EnableMouse(false) end
    frame:Hide()
    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints(frame)
    if body.EnableMouse then body:EnableMouse(false) end
    local pieces = {}
    local function Piece(left, right, top, bottom)
        local texture = body:CreateTexture(nil, "BACKGROUND", nil, -8)
        texture:SetTexture(Glow.HALO_TEXTURE)
        texture:SetTexCoord(left, right, top, bottom)
        texture:SetBlendMode("BLEND")
        pieces[#pieces + 1] = texture
        return texture
    end
    local topLeft, topRight = Piece(0, 0.5, 0, 0.5), Piece(0.5, 1, 0, 0.5)
    local bottomLeft, bottomRight = Piece(0, 0.5, 0.5, 1), Piece(0.5, 1, 0.5, 1)
    topLeft:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    topRight:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    bottomLeft:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
    bottomRight:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    -- The sides stretch between the corners (the disc's middle column or row, from rim to centre), and
    -- the middle across the plate (its centre texel).
    local function Between(piece, fromCorner, fromPoint, toCorner, toPoint)
        piece:SetPoint("TOPLEFT", fromCorner, fromPoint, 0, 0)
        piece:SetPoint("BOTTOMRIGHT", toCorner, toPoint, 0, 0)
    end
    Between(Piece(0.5, 0.5, 0, 0.5), topLeft, "TOPRIGHT", topRight, "BOTTOMLEFT")
    Between(Piece(0.5, 0.5, 0.5, 1), bottomLeft, "TOPRIGHT", bottomRight, "BOTTOMLEFT")
    Between(Piece(0, 0.5, 0.5, 0.5), topLeft, "BOTTOMLEFT", bottomLeft, "TOPRIGHT")
    Between(Piece(0.5, 1, 0.5, 0.5), topRight, "BOTTOMLEFT", bottomRight, "TOPRIGHT")
    Between(Piece(0.5, 0.5, 0.5, 0.5), topLeft, "BOTTOMRIGHT", bottomRight, "TOPLEFT")
    return { frame = frame, body = body, pieces = pieces, corners = { topLeft, topRight, bottomLeft, bottomRight } }
end

-- The glow's frames at level (a child is not kept above its parent's level by the client).
function Glow.SetLevel(glow, level)
    glow.frame:SetFrameLevel(level)
    glow.body:SetFrameLevel(level)
end

-- Under every part of a plate: LEVELS_UNDER below its overlay (the glow's parent).
function Glow.Under(glow, overlay)
    Glow.SetLevel(glow, math.max(0, overlay:GetFrameLevel() - Glow.LEVELS_UNDER))
end

-- Spread (how far past the plate: the corners' size), offset (the whole glow moved right and up),
-- opacity and pulse.
function Glow.Style(glow, settings)
    local spread = settings.targetGlowSpread or S.defaults.targetGlowSpread
    local opacity = settings.targetGlowOpacity or S.defaults.targetGlowOpacity
    glow.spread = spread
    glow.offsetX, glow.offsetY = settings.targetGlowOffsetX or 0, settings.targetGlowOffsetY or 0
    for _, piece in ipairs(glow.corners) do piece:SetSize(spread, spread) end
    for _, piece in ipairs(glow.pieces) do piece:SetAlpha(opacity) end
    Glow.SetPulse(glow, settings.targetGlowPulse == true)
end

-- left, right, top, bottom: the regions whose edges the glow reaches past by its spread, all moved by
-- its offset. leftReach, rightReach (readable numbers, the glow's units; Bounds' long name): that side
-- reaches this far from its region's centre instead of from its edge. Placed again only when one of
-- them, the spread or the offset changes.
function Glow.Place(glow, left, right, top, bottom, leftReach, rightReach)
    local frame, spread = glow.frame, glow.spread or S.defaults.targetGlowSpread
    local x, y = glow.offsetX or 0, glow.offsetY or 0
    local placed = glow.placed
    if placed and placed[1] == left and placed[2] == right and placed[3] == top and placed[4] == bottom
        and placed[5] == spread and placed[6] == x and placed[7] == y and placed[8] == leftReach
        and placed[9] == rightReach then return end
    placed = placed or {}
    placed[1], placed[2], placed[3], placed[4], placed[5], placed[6], placed[7] = left, right, top, bottom, spread, x, y
    placed[8], placed[9] = leftReach, rightReach
    glow.placed = placed
    frame:ClearAllPoints()
    if left == top and right == bottom and not leftReach and not rightReach then
        frame:SetPoint("TOPLEFT", left, "TOPLEFT", x - spread, y + spread)
        frame:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", x + spread, y - spread)
        return
    end
    -- Edges from different regions: each edge point sets only its own side's position.
    if leftReach then
        frame:SetPoint("LEFT", left, "CENTER", x - spread - leftReach, 0)
    else
        frame:SetPoint("LEFT", left, "LEFT", x - spread, 0)
    end
    if rightReach then
        frame:SetPoint("RIGHT", right, "CENTER", x + spread + rightReach, 0)
    else
        frame:SetPoint("RIGHT", right, "RIGHT", x + spread, 0)
    end
    frame:SetPoint("TOP", top, "TOP", 0, y + spread)
    frame:SetPoint("BOTTOM", bottom, "BOTTOM", 0, y - spread)
end

function Glow.Paint(glow, r, g, b)
    for _, piece in ipairs(glow.pieces) do piece:SetVertexColor(r, g, b) end
end

-- The colour a reaction draws (hostile, neutral, friendly): unit's when readable, else the plate's
-- friendly flag; nil when neither is known.
function Glow.Reaction(unit, friendly)
    if unit and type(UnitReaction) == "function" then
        local ok, reaction = pcall(UnitReaction, unit, "player")
        if ok and IsReadable(reaction) and type(reaction) == "number" then
            if reaction <= 3 then return Glow.REACTION.hostile end
            if reaction == 4 then return Glow.REACTION.neutral end
            return Glow.REACTION.friendly
        end
    end
    if friendly == true then return Glow.REACTION.friendly end
    if friendly == false then return Glow.REACTION.hostile end
    return nil
end

-- The settings' colour (r, g, b) from readable facts: classFile (a player's, or nil), then reaction
-- (a REACTION colour, or nil), or for the Threat mode threat (a threat colour { r, g, b }, or nil), then
-- the custom colour, which is also what any unknown falls back to. ColourFor and Studio's preview (a
-- sample, not a unit) both choose through it.
function Glow.Colour(settings, classFile, reaction, threat)
    local mode = settings.targetGlowColourMode
    if mode == "class" then
        local r, g, b = Secret.ClassColour(classFile) -- nil for none, or one it cannot read
        if r then return r, g, b end
    end
    if mode == "threat" then
        if threat then return threat.r, threat.g, threat.b end
    elseif mode ~= "custom" and reaction then
        return reaction[1], reaction[2], reaction[3]
    end
    local colour = settings.targetGlowColour or S.defaults.targetGlowColour
    return colour.r, colour.g, colour.b
end

-- Threat mode on plate data: its threat colour (ThreatColours' part "glow", the shared colours for your
-- role and its state, as the bars and edge take them) while it is in combat with you: readable, or picked
-- inside the client from protected answers (FoldForPlate, straight to the pieces' colour setter, as the
-- health bar's edge takes it). True when painted.
local function PaintThreat(glow, data)
    local Threat = PS.ThreatColours
    if not (Threat and data) then return false end
    local colour = Threat.ForPlate(data, Threat.GLOW)
    if colour then
        Glow.Paint(glow, colour.r, colour.g, colour.b)
        return true
    end
    local folded, r, g, b = Threat.FoldForPlate(data, Threat.GLOW)
    if not folded then return false end
    local painted = true
    for _, piece in ipairs(glow.pieces) do painted = pcall(piece.SetVertexColor, piece, r, g, b) and painted end
    return painted
end

-- Paints the glow in the settings' colour for unit: a player's class (a protected class file goes
-- straight to the client's colour sink), the reaction, the plate's threat colour (data: the plate, for
-- Threat), or the custom colour, which is also what any unknown falls back to. Returns which was used.
function Glow.ColourFor(glow, settings, unit, friendly, data)
    local mode = settings.targetGlowColourMode
    if mode == "threat" then
        if PaintThreat(glow, data) then return "threat" end
        Glow.Paint(glow, Glow.Colour(settings))
        return "custom"
    end
    if mode == "class" and unit and Secret.ReadBoolean(UnitIsPlayer, unit) == true then
        local classFile, has = Secret.ClassFile(unit)
        if has then
            local r, g, b = Secret.ClassColour(classFile)
            if r then
                Glow.Paint(glow, r, g, b)
                return "class"
            end
            local painted = true
            for _, piece in ipairs(glow.pieces) do
                painted = Secret.SetClassColour(piece, classFile, "SetVertexColor") and painted
            end
            if painted then return "class" end
        end
    end
    local reaction = mode ~= "custom" and Glow.Reaction(unit, friendly) or nil
    Glow.Paint(glow, Glow.Colour(settings, nil, reaction))
    return reaction and "reaction" or "custom"
end

-- A part's box in its own units, from the profile that sizes it (never measured: a restricted plate's
-- sizes can be secret): the bars' sizes, and the name's line (its font size; its width is its text's,
-- so it counts as its centre across). Nil for a part it does not know.
local NO_PROFILE = {}
function Glow.PartSize(profile, key)
    profile = profile or NO_PROFILE
    local width = tonumber(profile.width) or 0
    local healthHeight = tonumber(profile.healthHeight) or 0
    if key == "health" then return width, healthHeight end
    if key == "power" then return tonumber(profile.powerWidth) or width, tonumber(profile.powerHeight) or 0 end
    if key == "cast" then
        return tonumber(profile.castWidth) or width, tonumber(profile.castHeight) or math.max(5, healthHeight - 3)
    end
    local nameSize = tonumber(profile.nameFontSize) or 0
    if key == "name" then return 0, nameSize end
    if key == "guild" then return 0, S.PartTextSize("guild", nameSize) or 0 end
end

-- Box key's centre and half sizes in the layout's units, at its drawn place and scale.
local function Box(box, profile, key, at)
    local width, height = Glow.PartSize(profile, key)
    box.x, box.y = at.x, at.y
    box.halfWidth, box.halfHeight = (width or 0) * at.scale / 2, (height or 0) * at.scale / 2
    return box
end

-- Whether two boxes are within BODY_REACH of each other on both axes (overlapping counts).
local function Near(a, b)
    local reach = Glow.BODY_REACH
    return math.abs(a.x - b.x) - a.halfWidth - b.halfWidth <= reach
        and math.abs(a.y - b.y) - a.halfHeight - b.halfHeight <= reach
end

-- Scratch boxes for Bounds (at most the bar and EDGE_PARTS), reused between calls.
local boxes, waiting = { {}, {}, {}, {} }, {}

-- The regions the glow reaches past (Place's left, right, top, bottom). parts: the regions by layout
-- key (a plate's data, Studio's components); profile sizes them (PartSize). A barless plate (names-only,
-- or a layout that turns its health bar off): the name alone. Else the health bar across, and up and
-- down to the highest and lowest EDGE_PARTS of the plate's body: shown, on in the layout, drawing
-- something (Drawn(owner, key, region), when given: Studio's faint samples do not), and within
-- BODY_REACH of the bar or of a part already taken in, link by link (bar, power bar, cast bar). A part
-- placed away from them is left out and draws outside the glow. The layout's worked-out offsets
-- (TransformsOf(layout, owner), asked only when needed) place the boxes. A name taken in that is wider
-- than the bar widens it to the name's sides: NameWidth(owner, region) gives its drawn text's width in
-- its own units, a readable number, or nil (unknown or protected: the bar's width, as without it); that
-- side's reach from the name's centre is returned too (Place's leftReach, rightReach). Last, the part
-- whose alpha the glow takes (the bar, or a lone name). The plates and Studio's preview both place it
-- through this.
local NameLine -- (below)
function Glow.Bounds(layout, parts, barless, TransformsOf, owner, profile, Drawn, NameWidth)
    local name, health = parts.name, parts.health
    if barless or not layout or S.TurnedOff(layout.health) then
        return NameLine(layout, parts, TransformsOf, owner, profile, Drawn)
    end
    local top, bottom, transforms, topY, bottomY = health, health, nil, nil, nil
    local count = 0
    for _, key in ipairs(Glow.EDGE_PARTS) do
        local region, position = parts[key], layout[key]
        if region and position and not S.TurnedOff(position) and region:IsShown()
            and (not Drawn or Drawn(owner, key, region)) then
            transforms = transforms or TransformsOf(layout, owner)
            if transforms[key] and transforms.health then
                count = count + 1
                waiting[count] = key
            end
        end
    end
    if count == 0 then return health, health, top, bottom, nil, nil, health end
    local taken, healthAt, nameAt = 1, transforms.health, nil
    Box(boxes[1], profile, "health", healthAt)
    local found = true
    while found do
        found = false
        for index = 1, count do
            local key = waiting[index]
            if key then
                local at = transforms[key]
                local box = Box(boxes[taken + 1], profile, key, at)
                for other = 1, taken do
                    if Near(box, boxes[other]) then
                        taken, found, waiting[index] = taken + 1, true, false
                        if key == "name" then nameAt = at end
                        if at.y > (topY or healthAt.y) then
                            top, topY = parts[key], at.y
                        elseif at.y < (bottomY or healthAt.y) then
                            bottom, bottomY = parts[key], at.y
                        end
                        break
                    end
                end
            end
        end
    end
    for index = 1, count do waiting[index] = nil end
    local left, right, leftReach, rightReach = health, health, nil, nil
    local width = nameAt and NameWidth and NameWidth(owner, name)
    if type(width) == "number" and width > 0 then
        local reach, bar = width * nameAt.scale / 2, boxes[1]
        if nameAt.x - reach < bar.x - bar.halfWidth then left, leftReach = name, reach end
        if nameAt.x + reach > bar.x + bar.halfWidth then right, rightReach = name, reach end
    end
    return left, right, top, bottom, leftReach, rightReach, health
end

-- Whether key is pinned to the name, directly or along a chain of pins.
local function PinnedToName(layout, key)
    for _ = 1, S.MAX_DEPTH do
        local position = layout[key]
        if type(position) ~= "table" or not S.ATTACH_EDGES[position.attach] then return false end
        if position.parent == "name" then return true end
        key = position.parent
    end
    return false
end

local function Counts(layout, parts, key, owner, Drawn)
    local region, position = parts[key], layout[key]
    return region and position and not S.TurnedOff(position) and region:IsShown() and (not Drawn or Drawn(owner, key, region))
        and region or nil
end

-- Bounds without a bar: the name, the parts pinned to it on its line across, and the guild line under it.
NameLine = function(layout, parts, TransformsOf, owner, profile, Drawn)
    local name = parts.name
    local left, right, bottom = name, name, name
    if type(layout) ~= "table" or type(layout.name) ~= "table" then return name, name, name, name, nil, nil, name end
    local transforms, leftX, rightX
    for _, key in ipairs(Glow.NAME_LINE) do
        local region = Counts(layout, parts, key, owner, Drawn)
        if region and PinnedToName(layout, key) then
            transforms = transforms or TransformsOf(layout, owner)
            local at, nameAt = transforms[key], transforms.name
            if at and nameAt then
                if at.x < (leftX or nameAt.x) then
                    left, leftX = region, at.x
                elseif at.x > (rightX or nameAt.x) then
                    right, rightX = region, at.x
                end
            end
        end
    end
    for _, key in ipairs(Glow.UNDER_NAME) do
        local region, position = Counts(layout, parts, key, owner, Drawn), layout[key]
        if region and position.attach == "bottom" and position.parent == "name" then
            -- Pinned under the name: its gap (the pin's offset) says how far off it is.
            if math.abs(tonumber(position.x) or 0) <= Glow.BODY_REACH and math.abs(tonumber(position.y) or 0) <= Glow.BODY_REACH then
                bottom = region
            end
        elseif region then
            transforms = transforms or TransformsOf(layout, owner)
            local at, nameAt = transforms[key], transforms.name
            if at and nameAt and at.y < nameAt.y and Near(Box(boxes[1], profile, "name", nameAt), Box(boxes[2], profile, key, at)) then
                bottom = region
            end
        end
    end
    return left, right, name, bottom, nil, nil, name
end

-- The pulse: made once, then played only while the glow shows with it on.
function Glow.SetPulse(glow, on)
    local body = glow.body
    if on and not glow.pulse and type(body.CreateAnimationGroup) == "function" then
        local group = body:CreateAnimationGroup()
        local fade = group and group:CreateAnimation("Alpha")
        if fade then
            fade:SetFromAlpha(1)
            fade:SetToAlpha(Glow.PULSE_LOW)
            fade:SetDuration(Glow.PULSE_SECONDS)
            if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
            group:SetLooping("BOUNCE")
            glow.pulse = group
        end
    end
    glow.pulsing = on and glow.pulse ~= nil
    local group = glow.pulse
    if not group then return end
    if glow.pulsing and glow.frame:IsShown() then
        if not group:IsPlaying() then group:Play() end
    elseif group:IsPlaying() then
        group:Stop()
    end
end

-- glow.shown: Show's and Hide's own record, so a part's hook can skip a hidden glow without asking.
function Glow.Show(glow)
    glow.frame:Show()
    glow.shown = true
    if glow.pulsing and not glow.pulse:IsPlaying() then glow.pulse:Play() end
end

function Glow.Hide(glow)
    if glow.pulse and glow.pulse:IsPlaying() then glow.pulse:Stop() end
    glow.frame:Hide()
    glow.shown = false
end

-- The plate side. context: Transforms (Placement's). The glow is made the first time a plate shows
-- it (data.targetSoftGlow), as the target's highlight is: a child of the plate's overlay, so it takes
-- the plate's scale, visibility and fades (Blizzard's distance fade on the nameplate, the threat
-- spotlight's on the overlay) as every part does, LEVELS_UNDER below it (Styles.ApplyDrawOrder keeps it
-- there as the overlay's level moves).
PS._CreatePlateTargetGlow = function(context)
    local Transforms = context.Transforms
    -- The plates showing the glow now (at most the target's), for RestyleShown.
    local Pass, shown = {}, {}

    -- The name's width, measured on a text of PlateSmith's own (scratch) in the name's font, never on the
    -- plate's name, whose width a restricted plate keeps secret. Only a readable name is measured: the
    -- text SetPlateText last wrote (plateSmithText; nil while the name shows a protected value, which
    -- leaves the glow at the bar's width). Kept per plate (data.targetGlowName) until the text changes
    -- or the glow is shown again (a new font or size comes with that: ApplyAppearance shows it again).
    local scratch
    local function NameWidth(data, region)
        local text = region.plateSmithText
        if type(text) ~= "string" or text == "" then return nil end
        local known = data.targetGlowName
        if known and known.text == text then return known.width end
        if not scratch then
            local holder = CreateFrame("Frame", nil, UIParent)
            holder:Hide()
            scratch = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            if scratch.SetWordWrap then scratch:SetWordWrap(false) end
        end
        if type(PS.StyledPartFont) ~= "function" then return nil end
        PS.StyledPartFont(data, "name", scratch, region.plateSmithFontSize)
        scratch:SetText(text)
        local width = Secret.ReadNumber(scratch, "GetStringWidth")
        known = known or {}
        known.text, known.width = text, type(width) == "number" and width or nil
        data.targetGlowName = known
        return known.width
    end
    Pass.NameWidth = NameWidth

    -- The regions the glow reaches past on a plate (Glow.Bounds, with Placement's transforms and the
    -- plate's design sizing the parts), and a long name's reach.
    function Pass.Bounds(data)
        return Glow.Bounds(data.layout, data, data.namesOnly, Transforms, data, data.profile, nil, NameWidth)
    end

    -- Placed round the plate; the frame takes the alpha of the part it follows (the bar, or a lone name),
    -- so a rule's fade (Fade out of range, Fade non-targets) dims the glow with it.
    local function Place(data, glow)
        local left, right, top, bottom, leftReach, rightReach, follow = Pass.Bounds(data)
        if glow.follow ~= follow then
            glow.follow = follow
            if follow.GetAlpha and glow.frame.SetAlpha then glow.frame:SetAlpha(follow:GetAlpha()) end
        end
        Glow.Place(glow, left, right, top, bottom, leftReach, rightReach)
    end

    -- Once per plate: a part showing or hiding places a shown glow again (a cast starting takes in the
    -- cast bar too), and the followed part's alpha passes straight to the glow (a sink: never read here).
    local function Follow(data, glow)
        local function Moved()
            if glow.shown then Place(data, glow) end
        end
        for _, key in ipairs(Glow.EDGE_PARTS) do
            local region = data[key]
            if region then
                for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
                    if region[method] then hooksecurefunc(region, method, Moved) end
                end
            end
        end
        -- Names-only: the parts on the name line and the guild line under it.
        for _, list in ipairs({ Glow.NAME_LINE, Glow.UNDER_NAME }) do
            for _, key in ipairs(list) do
                local region = data[key]
                if region then
                    for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
                        if region[method] then hooksecurefunc(region, method, Moved) end
                    end
                end
            end
        end
        -- A new name (SetPlateText writes only a change) may be wider or narrower.
        if data.name.SetText then hooksecurefunc(data.name, "SetText", Moved) end
        local function Faded(region, alpha)
            if glow.follow == region then glow.frame:SetAlpha(alpha) end
        end
        for _, region in ipairs({ data.health, data.name }) do
            if region.SetAlpha then hooksecurefunc(region, "SetAlpha", Faded) end
        end
    end

    -- The target highlight the plate's design draws: its own values over the general settings db (Schema's
    -- HIGHLIGHT), resolved into the plate's own table from the profile it draws with (a glow edit that
    -- restyles without a layout edits that profile in place: Settings' Mutate).
    function Pass.Highlight(data, db)
        data.targetHighlight = S.HIGHLIGHT.Resolve(db, data.profile, data.targetHighlight)
        return data.targetHighlight
    end

    -- restyle: only a glow setting changed (RestyleShown), so the name's measure still holds.
    local function Show(data, settings, restyle)
        local glow = data.targetSoftGlow
        if not glow then
            glow = Glow.Create(data.overlay)
            data.targetSoftGlow = glow
            Follow(data, glow)
        end
        if not restyle and data.targetGlowName then data.targetGlowName.text = nil end
        settings = Pass.Highlight(data, settings)
        Glow.Under(glow, data.overlay)
        Glow.Style(glow, settings)
        Place(data, glow)
        data.targetGlowColour = Glow.ColourFor(glow, settings, data.unit, data.friendly, data)
        Glow.Show(glow)
        shown[data] = true
    end
    function Pass.Show(data, settings) Show(data, settings, false) end

    -- Nothing to do for a plate that never showed it.
    function Pass.Hide(data)
        if data.targetSoftGlow then Glow.Hide(data.targetSoftGlow) end
        data.targetGlowColour = nil
        shown[data] = nil
    end

    -- The plate's threat changed (Lifecycle's UpdateThreatValues, on a new record, revision or idle): a shown
    -- glow in the Threat colour mode takes the new colour; nothing is placed again.
    function Pass.Recolour(data)
        local glow, highlight = data.targetSoftGlow, data.targetHighlight
        if not (glow and glow.shown and highlight and highlight.targetGlowColourMode == "threat") then return end
        data.targetGlowColour = Glow.ColourFor(glow, highlight, data.unit, data.friendly, data)
    end

    -- A glow setting changed (Settings' SetOption, or a design's own glow option): only the plates showing
    -- the glow restyle it, each with its own design's values.
    function Glow.RestyleShown(settings)
        for data in pairs(shown) do Show(data, settings, true) end
    end

    return Pass
end
