-- Part styles and layering on owned plates: fonts, text boxes, bar borders, rule and blend
-- colours, the cast bar's own colour, and each part's frame level from the layout's drawing order.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

-- Blend by health (a rule's set = "blend"; Schema turns an older style gradient into one): a colour between
-- stops { at = 0..100, colour = { r, g, b } }, sorted by at, by a readable health %. Below the
-- first stop is its colour, above the last the last's. Returns r, g, b, or nothing for a
-- protected or missing percentage or no stops (the part keeps its own colour). Studio's preview
-- uses the same blend.
local Blend = {}
PS.StyleBlend = Blend
local IsReadable = PS.Secret.IsReadable

local function IsStop(stop)
    if type(stop) ~= "table" then return false end
    local colour = stop.colour
    return type(stop.at) == "number" and type(colour) == "table" and type(colour.r) == "number"
        and type(colour.g) == "number" and type(colour.b) == "number"
end

function Blend.Colour(stops, percent)
    if type(stops) ~= "table" or not IsReadable(percent) or type(percent) ~= "number" then return nil end
    local count = #stops
    if count == 0 then return nil end
    for index = 1, count do
        if not IsStop(stops[index]) then return nil end
    end
    local first = stops[1]
    if percent <= first.at then return first.colour.r, first.colour.g, first.colour.b end
    for index = 2, count do
        local low, high = stops[index - 1], stops[index]
        if percent <= high.at then
            local span = high.at - low.at
            local along = span > 0 and (percent - low.at) / span or 1
            local from, to = low.colour, high.colour
            return from.r + (to.r - from.r) * along, from.g + (to.g - from.g) * along, from.b + (to.b - from.b) * along
        end
    end
    local last = stops[count].colour
    return last.r, last.g, last.b
end

PS._CreatePlateStyles = function(context)
    local ApplyNameplateFont = context.ApplyNameplateFont
    local Styles = {}

    local EMPTY = {}
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local BAR_BACKGROUND = S.STYLE_DEFAULTS.background
    local DEFAULT_BOX_FILL = S.STYLE_DEFAULTS.boxColour
    local DEFAULT_BOX_EDGE = S.STYLE_DEFAULTS.boxBorder
    local DEFAULT_BAR_EDGE = { r = 0, g = 0, b = 0, a = 1 }
    -- Backdrops are shared, never changed after creation: SetBackdrop keeps a reference.
    local borderBackdrops = {}
    local function BorderBackdrop(size)
        local backdrop = borderBackdrops[size]
        if not backdrop then
            backdrop = { edgeFile = WHITE, edgeSize = size }
            borderBackdrops[size] = backdrop
        end
        return backdrop
    end

    -- Custom part keys (value1..valueN), in order and as a set, so hot paths never match patterns.
    local VALUE_KEYS, IS_VALUE_KEY = {}, {}
    for index = 1, S.VALUE_SLOT_COUNT do
        VALUE_KEYS[index] = "value" .. index
        IS_VALUE_KEY[VALUE_KEYS[index]] = true
    end
    Styles.VALUE_KEYS, Styles.IS_VALUE_KEY, Styles.EMPTY = VALUE_KEYS, IS_VALUE_KEY, EMPTY

    local function PartStyle(data, key)
        local styles = data.profile and data.profile.styles
        return styles and styles[key]
    end

    -- The layout's drawing order (Schema's DrawOrder), once per layout table.
    local drawOrderCache = setmetatable({}, { __mode = "k" })
    local function DrawOrder(layout)
        local order = drawOrderCache[layout]
        if not order then
            local rank, count = S.DrawOrder(layout)
            order = { rank = rank, count = count }
            drawOrderCache[layout] = order
        end
        return order
    end

    -- A part's frame level over the plate: the front of the drawing order is highest. A value set
    -- to Behind sits under the plate's bars.
    local function LayerLevel(data, key)
        local order = DrawOrder(data.layout)
        local base = data.overlay:GetFrameLevel()
        local slot = IS_VALUE_KEY[key] and data.profile.valueSlots[key]
        if slot and slot.layer ~= "front" then return math.max(0, base - 1) end
        return base + 1 + order.count - (order.rank[key] or order.count)
    end
    Styles.LayerLevel = LayerLevel

    function Styles.ApplyDrawOrder(data)
        for key, frame in pairs(data.layerFrames or EMPTY) do
            frame:SetFrameLevel(LayerLevel(data, key == "questLoot" and "quest" or key))
        end
        for key, holder in pairs(data.valueHolders or EMPTY) do holder:SetFrameLevel(LayerLevel(data, key)) end
        -- The threat windows' spotlight (border and arrows) stays above every part.
        if data.beacon then
            data.beacon:SetFrameLevel(data.overlay:GetFrameLevel() + 2 + DrawOrder(data.layout).count)
        end
    end

    -- The target glow puts a text's own shadow back when it ends (targetShadowDefaults), so a
    -- styled shadow becomes that text's own; clearing the style returns the shadow it was made with.
    local function StyledShadow(data, style, region)
        if not region.SetShadowColor or not region.SetShadowOffset then return end
        local defaults = data.targetShadowDefaults or {}
        data.targetShadowDefaults = defaults
        data.plainShadows = data.plainShadows or {}
        local plain = data.plainShadows[region]
        if style and style.shadow ~= nil then
            if not plain then
                plain = defaults[region]
                if not plain and region.GetShadowColor and region.GetShadowOffset then
                    local red, green, blue, alpha = region:GetShadowColor()
                    local x, y = region:GetShadowOffset()
                    plain = { red, green, blue, alpha, x, y }
                end
                data.plainShadows[region] = plain
            end
            local shadow = { 0, 0, 0, style.shadow and 1 or 0, 1, -1 }
            region:SetShadowColor(shadow[1], shadow[2], shadow[3], shadow[4])
            region:SetShadowOffset(shadow[5], shadow[6])
            defaults[region] = shadow
        elseif plain then
            region:SetShadowColor(plain[1], plain[2], plain[3], plain[4])
            region:SetShadowOffset(plain[5], plain[6])
            defaults[region] = plain
            data.plainShadows[region] = nil
        end
    end

    -- A text part's font: the plates' font and size, then the style's font, outline and shadow.
    function Styles.StyledFont(data, key, region, size)
        if not region then return end
        local style = PartStyle(data, key)
        ApplyNameplateFont(region, size, style)
        StyledShadow(data, style, region)
    end

    -- The box's fill and 1 px edges as plain textures, not a backdrop: it is anchored to its text,
    -- whose width the client keeps secret in instances, and a backdrop works out its texture
    -- coordinates from its size (Blizzard's Backdrop errors on a secret width).
    local function BoxFrame(parent)
        local box = CreateFrame("Frame", nil, parent)
        box.fill = box:CreateTexture(nil, "BACKGROUND")
        box.fill:SetAllPoints(box)
        local top, bottom = box:CreateTexture(nil, "BORDER"), box:CreateTexture(nil, "BORDER")
        local left, right = box:CreateTexture(nil, "BORDER"), box:CreateTexture(nil, "BORDER")
        top:SetPoint("TOPLEFT", box, "TOPLEFT") top:SetPoint("TOPRIGHT", box, "TOPRIGHT") top:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT") bottom:SetHeight(1)
        left:SetPoint("TOPLEFT", box, "TOPLEFT") left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT") left:SetWidth(1)
        right:SetPoint("TOPRIGHT", box, "TOPRIGHT") right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT") right:SetWidth(1)
        box.edges = { top, bottom, left, right }
        return box
    end

    -- A box behind a text part (the "level box"): fill, border and padding around the text. It
    -- follows the text's size and, through SyncStyleBoxes, its shown state and opacity.
    function Styles.StyledBox(data, key, region)
        local style = PartStyle(data, key)
        data.styleBoxes = data.styleBoxes or {}
        local box = data.styleBoxes[key]
        if not (style and style.box and region) then
            if box then box:Hide() end
            return
        end
        if not box then
            box = BoxFrame(data.overlay)
            data.styleBoxes[key] = box
        end
        local padding = style.padding or S.STYLE_DEFAULTS.padding
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", region, "TOPLEFT", -padding, padding)
        box:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", padding, -padding)
        local fill = style.boxColour or DEFAULT_BOX_FILL
        box.fill:SetColorTexture(fill.r, fill.g, fill.b, fill.a or 1)
        local edge = style.boxBorder or DEFAULT_BOX_EDGE
        for _, line in ipairs(box.edges) do line:SetColorTexture(edge.r, edge.g, edge.b, edge.a or 1) end
        box.plateSmithStyled = true
    end

    -- A bar's texture, background and border (an outer frame, so the target edge stays its own).
    function Styles.StyledBar(data, key, bar, baseTexture)
        local style = PartStyle(data, key) or EMPTY
        bar:SetStatusBarTexture(PS.Media.StatusBarPath(style.texture or baseTexture))
        local background = bar.plateSmithBackground
        if background then
            local colour = style.background
            if colour then
                background:SetColorTexture(colour.r, colour.g, colour.b, colour.a or 1)
            else
                background:SetColorTexture(BAR_BACKGROUND.r, BAR_BACKGROUND.g, BAR_BACKGROUND.b, BAR_BACKGROUND.a)
            end
        end
        data.styleBorders = data.styleBorders or {}
        local frame = data.styleBorders[key]
        local size = style.border or 0
        if size <= 0 then
            if frame then frame:Hide() end
            return
        end
        if not frame then
            frame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
            frame:SetFrameLevel(bar:GetFrameLevel() + 3)
            data.styleBorders[key] = frame
        end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", bar, "TOPLEFT", -size, size)
        frame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", size, -size)
        local backdrop = BorderBackdrop(size)
        if frame.plateSmithBackdrop ~= backdrop then
            frame:SetBackdrop(backdrop)
            frame.plateSmithBackdrop = backdrop
        end
        local colour = style.borderColour or DEFAULT_BAR_EDGE
        frame:SetBackdropBorderColor(colour.r, colour.g, colour.b, colour.a or 1)
        frame:Show()
    end

    -- Text boxes follow their text: shown with it, at its opacity, just under its layer. A custom
    -- part that is now a bar, box or icon has no text, so no box.
    function Styles.SyncStyleBoxes(data)
        local boxes = data.styleBoxes
        if not boxes then return end
        local slots = data.profile and data.profile.valueSlots
        local overlayShown = data.overlay:IsShown()
        for key, box in pairs(boxes) do
            local slot = IS_VALUE_KEY[key] and slots and slots[key]
            local style = PartStyle(data, key)
            if box.plateSmithStyled and not (slot and slot.kind) and style and style.box then
                local region = data[key]
                if slot then region = data.valueTexts and data.valueTexts[key] or data.values[key] end
                local shown = region and region.IsShown and region:IsShown() and overlayShown
                box:SetShown(shown and true or false)
                if shown and region.GetAlpha then box:SetAlpha(region:GetAlpha() or 1) end
                if data.layout and data.layout[key] then box:SetFrameLevel(math.max(0, LayerLevel(data, key) - 1)) end
            else
                box:Hide()
            end
        end
    end

    Styles.BlendColour = Blend.Colour

    local function Near(r, g, b, colour)
        return colour ~= nil and math.abs(r - colour[1]) < 0.003 and math.abs(g - colour[2]) < 0.003
            and math.abs(b - colour[3]) < 0.003
    end

    -- A rule's colour over a part (r nil: no rule colour). The part's own colour is kept to go
    -- back to: taken before the first override, and again whenever the part set its own colour
    -- since (it is not the one the rule applied). region.plateSmithRuleColour is the applied
    -- colour while a rule holds and nil otherwise; its tables are reused.
    function Styles.RuleColour(region, r, g, b)
        local bar = region.SetStatusBarColor ~= nil
        local text = not bar and region.SetTextColor ~= nil
        local get = bar and region.GetStatusBarColor or text and region.GetTextColor or region.GetVertexColor
        local set = bar and region.SetStatusBarColor or text and region.SetTextColor or region.SetVertexColor
        if not get or not set then return end
        local ok, cr, cg, cb = pcall(get, region)
        local readable = ok and IsReadable(cr) and IsReadable(cg) and IsReadable(cb) and type(cr) == "number"
            and type(cg) == "number" and type(cb) == "number"
        local applied = region.plateSmithRuleColour
        local own = region.plateSmithOwnColour
        if r then
            if readable and not Near(cr, cg, cb, applied) then
                local base = region.plateSmithBaseColour or region.plateSmithBaseSpare or {}
                base[1], base[2], base[3] = cr, cg, cb
                region.plateSmithBaseColour = base
            elseif own and not applied then
                -- A protected own colour cannot be read back: the one OwnColour wrote is kept.
                local base = region.plateSmithBaseColour or region.plateSmithBaseSpare or {}
                base[1], base[2], base[3] = own[1], own[2], own[3]
                region.plateSmithBaseColour = base
            end
            if not (readable and math.abs(cr - r) < 0.003 and math.abs(cg - g) < 0.003 and math.abs(cb - b) < 0.003) then
                set(region, r, g, b)
            end
            if not applied then
                applied = region.plateSmithRuleSpare or {}
                region.plateSmithRuleColour = applied
            end
            applied[1], applied[2], applied[3] = r, g, b
        elseif applied then
            local base = region.plateSmithBaseColour
            -- With an own colour (OwnColour), only the rule has written the region since, so it
            -- goes back even when the colour cannot be read.
            if base and (own or (readable and Near(cr, cg, cb, applied))) then
                pcall(set, region, base[1], base[2], base[3])
            end
            region.plateSmithRuleColour, region.plateSmithRuleSpare = nil, applied
            region.plateSmithBaseColour, region.plateSmithBaseSpare = nil, base or region.plateSmithBaseSpare
        end
    end

    -- A part's own colour that may be protected (the cast bar's Colour by interrupt): written at
    -- once, or, while a rule's colour holds, kept as the colour to go back to. RuleColour never
    -- reads it back, so a protected colour is only ever passed to the setter.
    function Styles.OwnColour(region, r, g, b)
        local own = region.plateSmithOwnColour or {}
        own[1], own[2], own[3] = r, g, b
        region.plateSmithOwnColour = own
        if region.plateSmithRuleColour then
            local base = region.plateSmithBaseColour or region.plateSmithBaseSpare or {}
            base[1], base[2], base[3] = r, g, b
            region.plateSmithBaseColour = base
        else
            pcall(region.SetStatusBarColor, region, r, g, b)
        end
    end

    -- A casting bar's colour: Colour by interrupt (Interrupt.CastColour), or the bar's own colour
    -- again once that no longer applies.
    function Styles.CastColour(data)
        local profile, interrupt = data.profile or EMPTY, PS.Interrupt
        local ok, r, g, b
        if data.casting and profile.castInterruptColours == true and interrupt then
            ok, r, g, b = interrupt.CastColour(profile.castColours, data.castNotInterruptible)
        end
        if not ok then
            if not data.castColoured then return end
            local own = S.CAST_COLOUR
            r, g, b = own.r, own.g, own.b
        end
        data.castColoured = ok or nil
        Styles.OwnColour(data.cast, r, g, b)
    end

    return Styles
end
