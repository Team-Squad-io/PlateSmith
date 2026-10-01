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
-- GetShapeshiftFormID's cat form; the fallbacks when Enum does not name them.
local CAT_FORM, ENERGY, COMBO_POWER = 1, 3, 4
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" }
local EMPTY = {}

-- class: the player's class token once readable. has: whether they have combo points now (nil:
-- ask again, after a shapeshift). curves: each pip's step curve, false where the client has none.
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

-- In cat form: the form ID, else (a client without it) a druid whose power is energy. Unknown is not.
local function InCatForm()
    if type(GetShapeshiftFormID) == "function" then
        local ok, form = pcall(GetShapeshiftFormID)
        if ok and IsReadable(form) then return form == CAT_FORM end
    end
    if type(UnitPowerType) == "function" then
        local ok, power = pcall(UnitPowerType, "player")
        if ok and IsReadable(power) and type(power) == "number" then return power == PowerType("Energy", ENERGY) end
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

-- {combo}: the count (possibly protected) on the plate of your target while you have combo points.
function Combo.Read(data)
    if data.targeted ~= true or data.friendly ~= false or not Combo.Has() then return nil end
    return (Combo.Count())
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

-- For tests: forget the class, the form and the curves.
function Combo._Reset()
    state.class, state.has = nil, nil
    for index in pairs(state.curves) do state.curves[index] = nil end
end

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

    local function Inset(texture, edge, inset)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", edge, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -inset, inset)
    end

    -- Pip sizes and colours from the part's style; the row is as wide as the pips it draws.
    local function ApplyStyle(data)
        local style, defaults = PartStyle(data), S.STYLE_DEFAULTS
        local width, height = style.pipWidth or defaults.pipWidth, style.pipHeight or defaults.pipHeight
        local spacing = style.pipSpacing or defaults.pipSpacing
        local fill, empty = style.pipFill or defaults.pipFill, style.pipEmpty or defaults.pipEmpty
        local count = data.comboMax or Combo.MAX
        data.combo:SetSize(count * width + (count - 1) * spacing, height)
        -- A 1 px dark edge round each pip 6 px or more each way; a smaller pip is all colour.
        local inset = (width >= 6 and height >= 6) and 1 or 0
        for index, pip in ipairs(data.comboPips) do
            pip.edge:ClearAllPoints()
            pip.edge:SetPoint("LEFT", data.combo, "LEFT", (index - 1) * (width + spacing), 0)
            pip.edge:SetSize(width, height)
            pip.edge:SetColorTexture(0, 0, 0, 0.9)
            Inset(pip.empty, pip.edge, inset)
            Inset(pip.fill, pip.edge, inset)
            pip.empty:SetColorTexture(empty.r, empty.g, empty.b, empty.a or 1)
            pip.fill:SetColorTexture(fill.r, fill.g, fill.b, fill.a or 1)
        end
        local profile = data.profile or EMPTY
        Styles.StyledFont(data, "combo", data.comboText, math.max(8, (profile.nameFontSize or 14) - 2))
        data.comboText:SetTextColor(fill.r, fill.g, fill.b)
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

    local function ShowPips(data, maximum, filled)
        for index, pip in ipairs(data.comboPips) do
            local used = index <= maximum
            pip.edge:SetShown(used)
            pip.empty:SetShown(used)
            pip.fill:SetShown(used and (filled == true or (filled ~= false and index <= filled)))
        end
    end

    -- A protected count: each fill's opacity is its step curve evaluated by the client ("curve"),
    -- else the count as text in the row's place ("text"), else nothing ("hidden").
    local function DrawSecret(data, count, maximum)
        local curved = true
        for index = 1, maximum do
            local curve = PipCurve(index)
            local fill = data.comboPips[index].fill
            local ok, alpha = false, nil
            if curve then ok, alpha = pcall(curve.Evaluate, curve, count) end
            if not (ok and pcall(fill.SetAlpha, fill, alpha)) then
                curved = false
                break
            end
        end
        if curved then
            ShowPips(data, maximum, true)
            data.comboText:Hide()
            return "curve"
        end
        ShowPips(data, 0, false)
        local shown = pcall(data.comboText.SetFormattedText, data.comboText, "%.0f", count)
        data.comboText:SetShown(shown)
        return shown and "text" or "hidden"
    end

    -- Draws the count; false when there is nothing to show (the client says nothing).
    local function Draw(data)
        local maximum = Combo.Maximum()
        if maximum ~= data.comboMax then
            data.comboMax = maximum
            ApplyStyle(data)
        end
        local count, secret = Combo.Count()
        if secret then
            data.comboDrawn = nil
            data.comboPath = DrawSecret(data, count, maximum)
            return data.comboPath ~= "hidden"
        end
        if secret == nil then
            data.comboDrawn, data.comboPath = nil, "unknown"
            return false
        end
        if data.comboDrawn ~= count or data.comboPath ~= "pips" then
            -- A pip a protected count faded through its curve is opaque again.
            for _, pip in ipairs(data.comboPips) do pip.fill:SetAlpha(1) end
            ShowPips(data, maximum, count)
            data.comboText:Hide()
            data.comboDrawn, data.comboPath = count, "pips"
        end
        return true
    end

    -- Only on your target's owned enemy plate, with the part on, while you have combo points.
    local function Wanted(data)
        local position = data.layout and data.layout.combo
        return Pass.wanted and data.own == true and not data.namesOnly and data.friendly == false
            and data.targeted == true and position ~= nil and not S.TurnedOff(position) and Combo.Has()
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
    local function Listen(on)
        for _, event in ipairs(POWER_EVENTS) do
            if not on then
                if type(events.UnregisterEvent) == "function" then events:UnregisterEvent(event) end
            elseif not (type(events.RegisterUnitEvent) == "function" and pcall(events.RegisterUnitEvent, events, event, "player")) then
                PS._RegisterEvent(events, event, "platesmith.combo")
            end
        end
        if on then
            PS._RegisterEvent(events, "UPDATE_SHAPESHIFT_FORM", "platesmith.combo")
        elseif type(events.UnregisterEvent) == "function" then
            events:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
        end
    end
    events:SetScript("OnEvent", function(_, event, unit, powerType)
        if not Pass.wanted then return end
        if event == "UPDATE_SHAPESHIFT_FORM" then
            Combo.Forget()
            return Refresh()
        end
        -- The player's combo points only: other units and other power types (energy) are dropped.
        if not (IsReadable(unit) and unit == "player" and IsReadable(powerType) and powerType == "COMBO_POINTS") then return end
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
