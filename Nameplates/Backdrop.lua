-- The Backdrop part (Objects; Schema's BACKDROP): a box drawn behind other parts, like a game tooltip. Fit to parts
-- wraps the parts it is given (the name, the Status text, the Action icon...) while they show, Padding round them;
-- Fixed size is its own Width by Height on its own place. Its edges are anchored to the wrapped parts' own regions,
-- as the soft glow's are (TargetGlow.Place), so it follows a text live; which part reaches furthest on each side is
-- worked out from the layout's places and the parts' readable sizes, never from a protected value (an unreadable
-- width counts as none: that part's centre). The plates and Studio's preview draw it with the same Frame, Paint and
-- Fit.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local BACKDROP, DEFAULTS = S.BACKDROP, S.STYLE_DEFAULTS
local EMPTY = {}

local Backdrop = {}
PS.Backdrop = Backdrop

-- Its fill and edges are plain textures (PS.EdgeFrame), not Blizzard's Backdrop, which works out texture coordinates
-- from a size the client may keep secret (a wrapped text's width in an instance).
function Backdrop.Frame(parent)
    local box = PS.EdgeFrame(parent, DEFAULTS.backdropEdge)
    box.fill = box:CreateTexture(nil, "BACKGROUND")
    box.fill:SetAllPoints(box)
    box:Hide()
    return box
end

-- style's look: Blizzard's rounded level box (StyleBox.Rounded, in its own colours) or the fill and an edge of its
-- border px (0: none).
function Backdrop.Paint(box, style)
    style = style or EMPTY
    local rounded = PS.StyleBox.Rounded(box, style.boxShape == "rounded")
    local size = style.border or DEFAULTS.backdropEdge
    box.fill:SetShown(not rounded)
    for _, edge in ipairs(box.plateSmithEdges) do edge:SetShown(not rounded and size > 0) end
    if rounded then return end
    if size > 0 and box.plateSmithEdgeSize ~= size then box:SetEdgeSize(size) end
    local fill = style.boxColour or DEFAULTS.boxColour
    box.fill:SetColorTexture(fill.r, fill.g, fill.b, fill.a or 1)
    local edge = style.boxBorder or DEFAULTS.boxBorder
    box:SetBackdropBorderColor(edge.r, edge.g, edge.b, edge.a or 1)
end

function Backdrop.Fixed(style)
    return style ~= nil and style.backdropWrap == "fixed"
end

-- Fixed size's width and height, in the part's own units.
function Backdrop.Size(style)
    style = style or EMPTY
    return style.backdropWidth or DEFAULTS.backdropWidth, style.backdropHeight or DEFAULTS.backdropHeight
end

-- The parts Fit to parts wraps: a set (shared, never written).
function Backdrop.Parts(style)
    return BACKDROP.Ticked(style and style.backdropParts)
end

function Backdrop.Padding(style)
    return style and style.padding or DEFAULTS.padding
end

-- One wrapped part for Fit: region, its centre (x, y) and its drawn width and height (readable numbers or nil: none)
-- at scale, in one unit for every part.
function Backdrop.Entry(entry, region, x, y, scale, width, height)
    entry.region, entry.x, entry.y = region, x, y
    entry.halfWidth = (type(width) == "number" and width or 0) * scale / 2
    entry.halfHeight = (type(height) == "number" and height or 0) * scale / 2
    return entry
end

-- The regions of count entries reaching furthest left, right, up and down (the first part wins a tie).
function Backdrop.Extremes(entries, count)
    local left, right, top, bottom = entries[1], entries[1], entries[1], entries[1]
    for index = 2, count do
        local entry = entries[index]
        if entry.x - entry.halfWidth < left.x - left.halfWidth then left = entry end
        if entry.x + entry.halfWidth > right.x + right.halfWidth then right = entry end
        if entry.y + entry.halfHeight > top.y + top.halfHeight then top = entry end
        if entry.y - entry.halfHeight < bottom.y - bottom.halfHeight then bottom = entry end
    end
    return left.region, right.region, top.region, bottom.region
end

-- Fits box round count entries with padding (in box's units) and shows it; hides it with none. A layout that pins a
-- wrapped part to the backdrop itself makes the client refuse the anchor: the box then hides. True when shown.
function Backdrop.Fit(box, entries, count, padding)
    if count == 0 then
        box:Hide()
        return false
    end
    local wrap = box.plateSmithWrap or { frame = box }
    box.plateSmithWrap = wrap
    wrap.spread, wrap.spreadY = padding, padding
    if not pcall(PS.TargetGlow.Place, wrap, Backdrop.Extremes(entries, count)) then
        wrap.placed = nil
        box:ClearAllPoints()
        box:Hide()
        return false
    end
    box:Show()
    return true
end

-- Fixed size: Fit's anchors are let go (placed again from scratch when it fits again).
function Backdrop.Unfit(box)
    if box.plateSmithWrap then box.plateSmithWrap.placed = nil end
end

-- Whether a plate's Backdrop (made: its layout shows it) fits round its name (ObjectHover covers it then).
function Backdrop.WrapsName(data)
    local position = data.backdrop and data.layout and data.layout.backdrop
    if not position or S.TurnedOff(position) then return false end
    local style = data.profile and data.profile.styles and data.profile.styles.backdrop
    return not Backdrop.Fixed(style) and Backdrop.Parts(style).name == true
end

-- The plate side. context: Transforms, SafeSize, AnchorPart, RegionAlpha (Placement's). The box is made the first time
-- a plate's layout shows the part, on the plate's overlay just under every part, and placed again in the plate's
-- visibility pass (Lifecycle's RunFlush), which follows the parts showing, hiding and changing text.
PS._CreatePlateBackdrop = function(context)
    local Transforms, SafeSize, AnchorPart, RegionAlpha = context.Transforms, context.SafeSize, context.AnchorPart,
        context.RegionAlpha
    local Pass = {}
    local entries = {}
    for index = 1, #BACKDROP.PARTS do entries[index] = {} end

    local function Style(data)
        local styles = data.profile and data.profile.styles
        return styles and styles.backdrop
    end

    -- Objects only: Studio's copy of another plate type's layout may hold the entry, never drawn there.
    local function Wanted(data)
        local position = data.own and data.object == true and data.overlay and data.layout and data.layout.backdrop
        return type(position) == "table" and not S.TurnedOff(position)
    end

    -- A wrapped part counts while it draws: on in the layout, shown, not hidden or faded out by a rule or its parent.
    -- The quest marker is its loot bag while that shows in its place.
    local function Drawn(data, key)
        local position = data.layout[key]
        if not position or S.TurnedOff(position) then return nil end
        local region = data[key]
        if key == "quest" and data.questLoot and data.questLoot:IsShown() and not (region and region:IsShown()) then
            region = data.questLoot
        end
        if type(region) ~= "table" or not region.IsShown or not region:IsShown() or RegionAlpha(region) <= 0 then return nil end
        return region
    end

    local function Ensure(data)
        local box = data.backdrop
        if box then return box end
        box = Backdrop.Frame(data.overlay)
        data.backdrop = box
        Backdrop.Paint(box, Style(data))
        return box
    end

    function Pass.Sync(data)
        if not Wanted(data) then
            if data.backdrop then data.backdrop:Hide() end
            return
        end
        local box = Ensure(data)
        local level = math.max(0, data.overlay:GetFrameLevel() - 1)
        if box.plateSmithLevel ~= level then
            box.plateSmithLevel = level
            box:SetFrameLevel(level)
        end
        local style = Style(data)
        if Backdrop.Fixed(style) then
            Backdrop.Unfit(box)
            AnchorPart(data, box, "backdrop")
            box:SetSize(Backdrop.Size(style))
            box:Show()
            return
        end
        box:SetScale(1)
        local parts, count = Backdrop.Parts(style), 0
        local transforms = Transforms(data.layout, data)
        for _, key in ipairs(BACKDROP.PARTS) do
            local region = parts[key] and Drawn(data, key)
            local at = region and transforms[key]
            if at then
                count = count + 1
                local width, height = SafeSize(region, data)
                Backdrop.Entry(entries[count], region, at.x, at.y, at.scale > 0 and at.scale or 1, width, height)
            end
        end
        Backdrop.Fit(box, entries, count, Backdrop.Padding(style))
        for index = 1, count do entries[index].region = nil end
    end

    -- A plate was laid out: its box made (placed by the visibility pass) or hidden.
    function Pass.Update(data)
        if Wanted(data) then
            Ensure(data)
        elseif data.backdrop then
            data.backdrop:Hide()
        end
    end

    -- A settings change: its look again (the visibility pass places it).
    function Pass.ApplyAppearance(data)
        if data.backdrop then Backdrop.Paint(data.backdrop, Style(data)) end
    end

    function Pass.Release(data)
        if data.backdrop then data.backdrop:Hide() end
    end

    return Pass
end
