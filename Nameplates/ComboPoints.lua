-- Your combo points on your target's plate (the Combo points part and {combo}): a rogue's, or a
-- druid's in cat form. Read from GetComboPoints("player", "target"), else UnitPower("player",
-- ComboPoints); redrawn only on the player's combo-point power events, a shapeshift and the target
-- plate changing (Lifecycle's UpdateTarget). A protected count is never compared: each pip's fill
-- takes its opacity from a client step curve, else the count shows as text (SetFormattedText).
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local IsReadable, IsSecret = Secret.IsReadable, Secret.IsSecret

local Combo = {}
PS.ComboPoints = Combo
Combo.MAX = 5
-- Who has combo points: a rogue always, a druid in cat form.
Combo.CLASSES = { ROGUE = "always", DRUID = "cat" }
-- GetShapeshiftFormID's cat form, Cat Form's spell (the form bar slot's and the player's cast); the
-- fallbacks when Enum does not name the power types.
local CAT_FORM, CAT_FORM_SPELL, ENERGY, COMBO_POWER = 1, 768, 3, 4
-- A Cat Form cast stands for the form until a form change this much later (one that is not its own).
local CAT_CAST_WINDOW = 1
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" }
-- What can change whether a druid is in cat form (Combo.Forget): the form events, the power type
-- following the form (it can arrive after the form event while the form ID is withheld) and the
-- player's own form casts.
local FORM_EVENTS = { "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS" }
local PLAYER_FORM_EVENTS = { "UNIT_DISPLAYPOWER", "UNIT_SPELLCAST_SUCCEEDED" }
-- Entering and leaving combat change whether an empty row shows (pipShowRow "combat").
local COMBAT_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local EMPTY = {}

-- class: the player's class token once readable. has: whether they have combo points now (nil:
-- ask again, after a shapeshift). curves: each pip's step curve, false where the client has none.
-- catCast: when the player last cast Cat Form (GetTime), until a later form change.
local state = { curves = {} }

local function PowerType(name, fallback)
    local types = Enum and Enum.PowerType
    local value = types and types[name]
    if IsReadable(value) and type(value) == "number" then return value end
    return fallback
end

local function PlayerClass()
    if state.class then return state.class end
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, class = pcall(UnitClass, "player")
    state.class = ok and Secret.String(class) or nil
    return state.class
end

-- The form bar's active slot: true or false when its spell reads (Cat Form or not; slot 0 is no form),
-- nil when the client withholds it or is an older one whose slot info has no spell.
local function CatFromFormSlot()
    if type(GetShapeshiftForm) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then return nil end
    local ok, index = pcall(GetShapeshiftForm)
    if not (ok and IsReadable(index) and type(index) == "number") then return nil end
    if index == 0 then return false end
    local infoOK, _, second, _, fourth = pcall(GetShapeshiftFormInfo, index)
    -- Older clients: icon, name, active, castable (no spell).
    if not infoOK or (IsReadable(second) and type(second) == "string") then return nil end
    if not (IsReadable(fourth) and type(fourth) == "number") then return nil end
    return fourth == CAT_FORM_SPELL
end

-- In cat form, from the first signal that answers: the form ID, the form bar's active slot, power
-- type energy (only a cat's), else the player's own Cat Form cast since the last form change. In
-- combat the client can withhold the form ID and slot. Unknown is not cat form (fails closed).
local function InCatForm()
    if type(GetShapeshiftFormID) == "function" then
        local ok, form = pcall(GetShapeshiftFormID)
        if ok and IsReadable(form) then return form == CAT_FORM end
    end
    local slot = CatFromFormSlot()
    if slot ~= nil then return slot end
    if type(UnitPowerType) == "function" then
        local ok, power = pcall(UnitPowerType, "player")
        if ok and IsReadable(power) and type(power) == "number" then return power == PowerType("Energy", ENERGY) end
    end
    return state.catCast ~= nil
end

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, now = pcall(GetTime)
    return ok and IsReadable(now) and type(now) == "number" and now or 0
end

-- A form event: Cat Form cast moments ago is the change it reports, an older one no longer stands.
local function NoteFormChange()
    if state.catCast and Now() - state.catCast > CAT_CAST_WINDOW then state.catCast = nil end
end

-- The player's own cast (UNIT_SPELLCAST_SUCCEEDED's spell): Cat Form, or another form (it ends Cat Form).
local FORM_SPELLS = { [5487] = true, [9634] = true, [783] = true, [1066] = true, [24858] = true, [33891] = true,
    [33943] = true, [40120] = true }
local function NoteFormCast(spellID)
    if not (IsReadable(spellID) and type(spellID) == "number") then return false end
    if spellID == CAT_FORM_SPELL then
        state.catCast = Now()
        return true
    end
    if FORM_SPELLS[spellID] then
        state.catCast = nil
        return true
    end
    return false
end

-- Whether the player's class can have combo points at all.
function Combo.Possible()
    local class = PlayerClass()
    return class ~= nil and Combo.CLASSES[class] ~= nil
end

-- Whether the player has combo points now (kept until a shapeshift or a settings refresh).
function Combo.Has()
    if state.has == nil then
        local class = PlayerClass()
        if not class then return false end
        local rule = Combo.CLASSES[class]
        state.has = rule == "always" or (rule == "cat" and InCatForm())
    end
    return state.has
end

function Combo.Forget() state.has = nil end

-- value, secret from one API call: a readable count (whole, 0..MAX) with false, a protected one
-- with true, or nothing.
local function Counted(ok, value)
    if not ok then return nil, nil end
    if IsSecret(value) then return value, true end
    if IsReadable(value) and type(value) == "number" then
        return math.max(0, math.min(Combo.MAX, math.floor(value))), false
    end
    return nil, nil
end

-- The count on your target: value, secret (nil, nil when the client says nothing).
function Combo.Count()
    if type(GetComboPoints) == "function" then
        local value, secret = Counted(pcall(GetComboPoints, "player", "target"))
        if secret ~= nil then return value, secret end
    end
    if type(UnitPower) == "function" then
        local value, secret = Counted(pcall(UnitPower, "player", PowerType("ComboPoints", COMBO_POWER)))
        if secret ~= nil then return value, secret end
    end
    return nil, nil
end

-- How many pips to draw: the readable maximum, at most MAX (MAX when unknown).
function Combo.Maximum()
    if type(UnitPowerMax) ~= "function" then return Combo.MAX end
    local ok, value = pcall(UnitPowerMax, "player", PowerType("ComboPoints", COMBO_POWER))
    if ok and IsReadable(value) and type(value) == "number" and value >= 1 then
        return math.min(Combo.MAX, math.floor(value))
    end
    return Combo.MAX
end

-- Whether a readable count of 0 hides the row, for the style's Show row (pipShowRow): "points" (Only
-- with points) always, "combat" (In combat or with points) out of combat, nil (Always, every style
-- before it) never. The caller never asks for a protected count: it cannot be compared with 0.
function Combo.EmptyHidden(mode, inCombat)
    return mode == "points" or (mode == "combat" and not inCombat)
end

-- {combo}: the count (possibly protected) on the plate of your target while you have combo points.
-- Points stay on the target whatever your form: out of cat form a readable count reads only while it
-- is above 0, and a protected one (it cannot be compared) always.
function Combo.Read(data)
    if data.targeted ~= true or data.friendly ~= false or not Combo.Possible() then return nil end
    local count, secret = Combo.Count()
    if secret or Combo.Has() or (count ~= nil and count > 0) then return count end
    return nil
end

-- Pip index's step curve (0 below index, 1 from it), made once; false when the client has none.
local function PipCurve(index)
    local curve = state.curves[index]
    if curve ~= nil then return curve end
    curve = false
    local util, kinds = C_CurveUtil, Enum and Enum.LuaCurveType
    local step = kinds and kinds.Step
    if util and type(util.CreateCurve) == "function" and step ~= nil then
        local ok, made = pcall(util.CreateCurve)
        if ok and made ~= nil and pcall(made.SetType, made, step) and pcall(made.AddPoint, made, 0, 0)
            and pcall(made.AddPoint, made, index, 1) then
            curve = made
        end
    end
    state.curves[index] = curve
    return curve
end

-- For tests: forget the class, the form, the curves and whether Blizzard's art exists.
function Combo._Reset()
    state.class, state.has, state.blizzardArt, state.catCast = nil, nil, nil, nil
    for index in pairs(state.curves) do state.curves[index] = nil end
end

-- Your class colour { r, g, b } (combo points are always yours), or nil while the class is unknown.
function Combo.ClassColour()
    local r, g, b = Secret.ClassColour(PlayerClass())
    if not r then return nil end
    local colour = state.classColour or {}
    colour[1], colour[2], colour[3] = r, g, b
    state.classColour = colour
    return colour
end

-- How a row of pips is drawn from the part's style (Studio's preview draws its sample row the same
-- way). Shapes: nil, the bordered blocks every profile has had (width x height, a 1 px dark edge
-- round a pip 6 px or more each way); square, a block as tall as it is wide; round and diamond, a
-- disc or diamond pipWidth across with a dark rim; segments, touching bar segments on one dark
-- backing; blizzard, Blizzard's own combo point art, or round where the client lacks it. pipGlow
-- lights each filled pip from behind; pipClassColour fills with your class colour. The row's flags
-- (row.pipShaped: its textures carry art, coordinates or tints; row.pipNoEdge; row.pipGlow) say what
-- the last styling drew.
-- Blizzard's white disc and diamond masks, drawn as tintable shapes.
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local DIAMOND = "Interface\\Common\\common-mask-diamond"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local BLIZZARD_FILLED, BLIZZARD_EMPTY = "ClassOverlay-ComboPoint", "ClassOverlay-ComboPoint-Off"
Combo.BLIZZARD_ART = BLIZZARD_FILLED

-- Whether the client has Blizzard's combo point atlases (asked once).
function Combo.BlizzardArt()
    if state.blizzardArt == nil then
        local info = C_Texture and C_Texture.GetAtlasInfo
        local ok, found = false, nil
        if type(info) == "function" then ok, found = pcall(info, BLIZZARD_FILLED) end
        state.blizzardArt = ok and found ~= nil and IsReadable(found) or false
    end
    return state.blizzardArt
end

local function Inset(texture, edge, inset)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", edge, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -inset, inset)
end

-- One texture of a shaped pip in its art and colour.
local function Paint(texture, shape, art, r, g, b, a)
    if shape == "round" then
        texture:SetTexture(ROUND)
        texture:SetTexCoord(0, 1, 0, 1)
    elseif shape == "diamond" then
        texture:SetTexture(DIAMOND)
        texture:SetTexCoord(0, 1, 0, 1)
    elseif shape == "segments" then
        texture:SetTexture(BAR)
        texture:SetTexCoord(0, 1, 0, 1)
    elseif shape == "blizzard" then
        texture:SetTexCoord(0, 1, 0, 1)
        if not pcall(texture.SetAtlas, texture, art) then texture:SetTexture(ROUND) end
        r, g, b, a = 1, 1, 1, 1
    else
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetColorTexture(r, g, b, a)
        return
    end
    texture:SetVertexColor(r, g, b, a)
end

-- Styles row (its pips: { edge, empty, fill[, glow] }) for count pips; scale multiplies the sizes
-- (the preview's). fitWidth: the health bar's width in the row's units (Schema.PipFitWidth), which a
-- style with pipFit spans exactly (Schema.PipRow). Returns the filled colour (for the count's text).
function Combo.StylePips(row, pips, count, style, scale, classColour, fitWidth)
    local defaults = S.STYLE_DEFAULTS
    scale = scale or 1
    local shape = style.pipShape
    if shape == "blizzard" and not Combo.BlizzardArt() then shape = "round" end
    local width, height, spacing = S.PipRow(style, count, fitWidth)
    width, height, spacing = width * scale, height * scale, spacing * scale
    local fill, empty = style.pipFill or defaults.pipFill, style.pipEmpty or defaults.pipEmpty
    local r, g, b, a = fill.r, fill.g, fill.b, fill.a or 1
    if style.pipClassColour and classColour then r, g, b = classColour[1], classColour[2], classColour[3] end
    row:SetSize(count * width + (count - 1) * spacing, height)
    -- Today's blocks make exactly the calls they always made; a row styled otherwise before is reset.
    local square = shape == nil or shape == "square"
    local textured = not square
    local inset = 0
    if square then
        inset = (width >= 6 and height >= 6) and 1 or 0
    elseif shape == "round" or shape == "diamond" then
        inset = width >= 6 and (shape == "diamond" and 1.5 or 1) or 0
    end
    local reset = row.pipShaped and square
    local noEdge = shape == "segments" or shape == "blizzard"
    for index, pip in ipairs(pips) do
        local edge = pip.edge
        edge:ClearAllPoints()
        edge:SetPoint("LEFT", row, "LEFT", (index - 1) * (width + spacing), 0)
        edge:SetSize(width, height)
        if reset then Paint(edge, nil, nil, 0, 0, 0, 0.9) elseif square then edge:SetColorTexture(0, 0, 0, 0.9) end
        if textured and not noEdge then Paint(edge, shape, nil, 0, 0, 0, 0.9) end
        Inset(pip.empty, edge, inset)
        Inset(pip.fill, edge, inset)
        if square and not reset then
            pip.empty:SetColorTexture(empty.r, empty.g, empty.b, empty.a or 1)
            pip.fill:SetColorTexture(r, g, b, a)
        else
            Paint(pip.empty, textured and shape or nil, BLIZZARD_EMPTY, empty.r, empty.g, empty.b, empty.a or 1)
            Paint(pip.fill, textured and shape or nil, BLIZZARD_FILLED, r, g, b, a)
        end
        if style.pipGlow and not pip.glow then
            pip.glow = row:CreateTexture(nil, "BACKGROUND", nil, -8)
            pip.glow:SetTexture(PS.TargetGlow.TEXTURE)
            pip.glow:SetBlendMode("ADD")
            pip.glow:Hide()
        end
        if pip.glow then
            if style.pipGlow then
                pip.glow:ClearAllPoints()
                pip.glow:SetPoint("CENTER", edge, "CENTER", 0, 0)
                pip.glow:SetSize(width + 12 * scale, height + 12 * scale)
                pip.glow:SetVertexColor(r, g, b, 0.9)
            else
                pip.glow:Hide()
            end
        end
    end
    -- Segments: one dark backing behind the whole row, 1 px past it.
    if shape == "segments" and not row.pipBacking then
        row.pipBacking = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        row.pipBacking:SetPoint("TOPLEFT", row, "TOPLEFT", -1, 1)
        row.pipBacking:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 1, -1)
        row.pipBacking:SetColorTexture(0, 0, 0, 0.9)
    end
    if row.pipBacking then row.pipBacking:SetShown(shape == "segments") end
    row.pipShaped, row.pipNoEdge, row.pipGlow = textured or nil, noEdge or nil, style.pipGlow or nil
    row.pipSegments = shape == "segments" or nil
    return r, g, b
end

-- Which pips show (the first maximum), and which of them are filled: filled true (all, a protected
-- count fades them through curves), false (none) or a readable count.
-- fillsOnly: no edges, empty pips or segments' backing, only the fills (a protected count out of cat
-- form, whose curve may give every fill 0: then nothing shows).
function Combo.ShowPips(row, pips, maximum, filled, fillsOnly)
    for index, pip in ipairs(pips) do
        local used = index <= maximum
        local lit = used and (filled == true or (filled ~= false and index <= filled))
        pip.edge:SetShown(used and not row.pipNoEdge and not fillsOnly)
        pip.empty:SetShown(used and not fillsOnly)
        pip.fill:SetShown(lit)
        if pip.glow then pip.glow:SetShown(lit and row.pipGlow == true) end
    end
    if row.pipBacking then row.pipBacking:SetShown(row.pipSegments == true and not fillsOnly) end
end

-- Where a row sits on the health bar instead of its placed spot (style.pipAnchor): its point, the
-- bar's point, and the gap (px, upward).
Combo.BAR_ANCHORS = { edge = { "CENTER", "BOTTOM", 0 }, above = { "BOTTOM", "TOP", 2 }, below = { "TOP", "BOTTOM", -2 } }

-- The plate side. context: active (unit -> plate), RunBatch, MarkStacks, MarkValues, Styles,
-- AnchorPart (Placement). The part's frames are made the first time a plate
-- shows it, so a class without combo points never makes any, and its events are registered only
-- while a layout shows the part or reads {combo} (SetWanted) and the class can have them.
PS._CreatePlateCombo = function(context)
    local active, RunBatch, MarkStacks, MarkValues = context.active, context.RunBatch, context.MarkStacks, context.MarkValues
    local Styles, AnchorPart = context.Styles, context.AnchorPart
    local Pass = { wanted = false }
    -- target: the plate of your target, as UpdateTarget last said.
    local watch = {}

    local function PartStyle(data)
        local styles = data.profile and data.profile.styles
        return styles and styles.combo or EMPTY
    end

    -- Pip shapes, sizes and colours from the part's style (Combo.StylePips); the row is as wide as
    -- the pips it draws.
    local function ApplyStyle(data)
        local style = PartStyle(data)
        local count = data.comboMax or Combo.MAX
        local r, g, b = Combo.StylePips(data.combo, data.comboPips, count, style, 1,
            style.pipClassColour and Combo.ClassColour() or nil, style.pipFit and S.PipFitWidth(data.profile, data.layout) or nil)
        local profile = data.profile or EMPTY
        Styles.StyledFont(data, "combo", data.comboText, math.max(8, (profile.nameFontSize or 14) - 2))
        data.comboText:SetTextColor(r, g, b)
        data.comboDrawn = nil
    end

    local function Ensure(data)
        if data.combo then return data.combo end
        local layer = CreateFrame("Frame", nil, data.overlay)
        layer:SetAllPoints(data.overlay)
        data.layerFrames.combo = layer
        local frame = CreateFrame("Frame", nil, layer)
        frame:Hide()
        local pips = {}
        for index = 1, Combo.MAX do
            pips[index] = { edge = frame:CreateTexture(nil, "BACKGROUND"), empty = frame:CreateTexture(nil, "BORDER"),
                fill = frame:CreateTexture(nil, "ARTWORK") }
        end
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        text:Hide()
        data.combo, data.comboPips, data.comboText = frame, pips, text
        data.comboMax = Combo.Maximum()
        ApplyStyle(data)
        AnchorPart(data, frame, "combo")
        layer:SetFrameLevel(Styles.LayerLevel(data, "combo"))
        -- The layout is placed again with the part in it (a stack or a pin may follow it).
        data.stackStatesFor = nil
        MarkStacks(data)
        return frame
    end

    local function ShowPips(data, maximum, filled, fillsOnly)
        Combo.ShowPips(data.combo, data.comboPips, maximum, filled, fillsOnly)
    end

    -- A protected count: each fill's opacity is its step curve evaluated by the client ("curve"),
    -- else the count as text in the row's place ("text"), else nothing ("hidden"). fillsOnly (out of cat
    -- form, where a 0 must not show an empty row): the fills alone, and no text (it would show a 0).
    local function DrawSecret(data, count, maximum, fillsOnly)
        local curved = true
        for index = 1, maximum do
            local curve = PipCurve(index)
            local pip = data.comboPips[index]
            local fill = pip.fill
            local ok, alpha = false, nil
            if curve then ok, alpha = pcall(curve.Evaluate, curve, count) end
            if not (ok and pcall(fill.SetAlpha, fill, alpha)) then
                curved = false
                break
            end
            -- A filled pip's glow fades with it (the same opaque alpha, straight to the sink).
            if pip.glow then pcall(pip.glow.SetAlpha, pip.glow, alpha) end
        end
        if curved then
            ShowPips(data, maximum, true, fillsOnly)
            data.comboText:Hide()
            return fillsOnly and "curveFills" or "curve"
        end
        ShowPips(data, 0, false)
        if fillsOnly then
            data.comboText:Hide()
            return "hidden"
        end
        local shown = pcall(data.comboText.SetFormattedText, data.comboText, "%.0f", count)
        data.comboText:SetShown(shown)
        return shown and "text" or "hidden"
    end

    -- A readable 0 on this plate's row: hidden as its style's Show row says, in your combat state now.
    local function EmptyHidden(data) return Combo.EmptyHidden(PartStyle(data).pipShowRow, Secret.InCombat()) end

    -- Draws the count; false when there is nothing to show: the client says nothing, or a readable 0
    -- the style's Show row hides, or a readable 0 while you cannot build points (a druid out of cat form;
    -- points on the target stay whatever the form, so a count above 0 shows in any form).
    local function Draw(data)
        local maximum = Combo.Maximum()
        if maximum ~= data.comboMax then
            data.comboMax = maximum
            ApplyStyle(data)
        end
        local building = Combo.Has()
        local count, secret = Combo.Count()
        if secret then
            data.comboDrawn = nil
            data.comboPath = DrawSecret(data, count, maximum, not building)
            return data.comboPath ~= "hidden"
        end
        if secret == nil then
            data.comboDrawn, data.comboPath = nil, "unknown"
            return false
        end
        if count == 0 and (not building or EmptyHidden(data)) then
            data.comboDrawn, data.comboPath = nil, "empty"
            return false
        end
        if data.comboDrawn ~= count or data.comboPath ~= "pips" then
            -- A pip a protected count faded through its curve is opaque again.
            for _, pip in ipairs(data.comboPips) do
                pip.fill:SetAlpha(1)
                if pip.glow then pip.glow:SetAlpha(1) end
            end
            ShowPips(data, maximum, count)
            data.comboText:Hide()
            data.comboDrawn, data.comboPath = count, "pips"
        end
        return true
    end

    -- Only on your target's owned enemy plate, with the part on, for a class with combo points (in any
    -- form: Draw decides what an empty row shows).
    local function Wanted(data)
        local position = data.layout and data.layout.combo
        return Pass.wanted and data.own == true and not data.namesOnly and data.friendly == false
            and data.targeted == true and position ~= nil and not S.TurnedOff(position) and Combo.Possible()
    end

    -- A plate's targeted state or your combo points changed.
    function Pass.Update(data)
        -- comboTargeted: the plate was your target at its last update (another plate may be the
        -- watched one by now).
        local was, now = data.comboTargeted == true, data.targeted == true
        data.comboTargeted = now or nil
        if now then
            watch.target = data
        elseif watch.target == data then
            watch.target = nil
        end
        local shown = false
        if Wanted(data) then
            Ensure(data)
            shown = Draw(data)
        end
        local frame = data.combo
        if frame and (frame:IsShown() and true or false) ~= shown then
            frame:SetShown(shown)
            MarkStacks(data)
        end
        -- {combo} reads a count only on the target's plate: it changes there, and where it left.
        if was or now then MarkValues(data, "combo") end
    end

    -- Sizes and colours again after a settings change (ApplyAppearance); nothing for a plate without the part.
    function Pass.ApplyAppearance(data)
        if data.combo then ApplyStyle(data) end
    end

    -- The plate leaves its unit (or is not drawn): its row is hidden and forgotten.
    function Pass.Release(data)
        if data.combo then data.combo:Hide() end
        data.comboDrawn, data.comboPath, data.comboTargeted = nil, nil, nil
        if watch.target == data then watch.target = nil end
    end

    local function Refresh()
        local data = watch.target
        if data and data.unit and active[data.unit] == data then
            RunBatch(false, Pass.Update, data)
        else
            watch.target = nil
        end
    end

    local events = CreateFrame("Frame")
    local function Unregister(event)
        if type(events.UnregisterEvent) == "function" then events:UnregisterEvent(event) end
    end
    local function Listen(on)
        for _, list in ipairs({ POWER_EVENTS, PLAYER_FORM_EVENTS }) do
            for _, event in ipairs(list) do
                if not on then
                    Unregister(event)
                elseif not (type(events.RegisterUnitEvent) == "function" and pcall(events.RegisterUnitEvent, events, event, "player")) then
                    PS._RegisterEvent(events, event, "platesmith.combo")
                end
            end
        end
        for _, list in ipairs({ FORM_EVENTS, COMBAT_EVENTS }) do
            for _, event in ipairs(list) do
                if on then PS._RegisterEvent(events, event, "platesmith.combo") else Unregister(event) end
            end
        end
    end
    local FORM_EVENT, COMBAT_EVENT = {}, {}
    for _, event in ipairs(FORM_EVENTS) do FORM_EVENT[event] = true end
    for _, event in ipairs(COMBAT_EVENTS) do COMBAT_EVENT[event] = true end
    events:SetScript("OnEvent", function(_, event, unit, second, third)
        if not Pass.wanted then return end
        if FORM_EVENT[event] then
            NoteFormChange()
            Combo.Forget()
            return Refresh()
        end
        if COMBAT_EVENT[event] then return Refresh() end
        -- The rest are the player's own (other units' arrive where unit filtering is missing).
        if not (IsReadable(unit) and unit == "player") then return end
        if event == "UNIT_DISPLAYPOWER" then
            Combo.Forget()
            return Refresh()
        end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if NoteFormCast(third) then
                Combo.Forget()
                Refresh()
            end
            return
        end
        -- Combo points only: other power types (energy) are dropped.
        if not (IsReadable(second) and second == "COMBO_POINTS") then return end
        Refresh()
    end)
    Pass.events = events

    -- On while a layout shows the part or reads {combo} and your class can have combo points.
    function Pass.SetWanted(wanted)
        Combo.Forget()
        wanted = (wanted and Combo.Possible()) and true or false
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        Listen(wanted)
    end

    Pass.Watched = function() return watch.target end
    return Pass
end
