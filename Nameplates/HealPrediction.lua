-- Incoming heals and absorbs on PlateSmith's health bars (Schema's HEALS: the Health bar's Incoming heals and Absorbs, a
-- design's own, off by default), drawn as Blizzard's 12.x frames draw them, without Lua reading a number: status bars
-- starting at the health bar's fill edge (its fill texture's right), as wide as the bar, ranged 0 to the bar's own
-- maximum, their values the client's (secret or not) passed straight to SetMinMaxValues and SetValue, and cut at the
-- bar's ends by a clipping frame. The client's calculator (CreateUnitHealPredictionCalculator with
-- UnitGetDetailedHealPrediction) gives the heals, every healer's or other healers' only, and the absorbs; without it,
-- UnitGetIncomingHeals and UnitGetTotal(Heal)Absorbs (every healer's only). A value that is missing or refused, or an
-- API the client lacks, shows nothing. Studio's preview draws with the same Ensure, Paint and Draw.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local HasValue = Secret.HasValue
local HEALS = S.HEALS

local HealPrediction = {}
PS.HealPrediction = HealPrediction
-- Opacity: the heals over the empty bar, the shields lighter, heal absorbs (healing the unit will soak up) dark over
-- the end of its health.
HealPrediction.ALPHA = { heal = 0.7, absorb = 0.55, healAbsorb = 0.75 }
HealPrediction.HEAL_ABSORB_COLOUR = { r = 0.45, g = 0.05, b = 0.12 }
-- Studio's preview: an incoming heal and a shield after Test values' health, in hundredths of the bar.
HealPrediction.SAMPLE = { heal = 15, absorb = 10 }

-- How heals are read: "calculator", "incoming" (the plain APIs) or false (neither); worked out on the first read.
local reads = { route = nil, calculator = nil, heals = nil, absorbs = nil, healAbsorbs = nil }

local function Method(object, name)
    local ok, method = pcall(function() return object[name] end)
    return ok and type(method) == "function" and method or nil
end

function HealPrediction.Route()
    if reads.route ~= nil then return reads.route end
    reads.route = false
    if type(CreateUnitHealPredictionCalculator) == "function" and type(UnitGetDetailedHealPrediction) == "function" then
        local ok, calculator = pcall(CreateUnitHealPredictionCalculator)
        local heals = ok and Secret.IsReadable(calculator) and calculator ~= nil and Method(calculator, "GetIncomingHeals")
        if heals then
            reads.calculator, reads.heals = calculator, heals
            reads.absorbs = Method(calculator, "GetDamageAbsorbs")
            reads.healAbsorbs = Method(calculator, "GetHealAbsorbs")
            reads.route = "calculator"
            return reads.route
        end
    end
    if type(UnitGetIncomingHeals) == "function" or type(UnitGetTotalAbsorbs) == "function" then reads.route = "incoming" end
    return reads.route
end

-- Forgets the route, so the next read works it out again (tests; a client that gained the APIs).
function HealPrediction.Forget()
    reads.route, reads.calculator, reads.heals, reads.absorbs, reads.healAbsorbs = nil, nil, nil, nil, nil
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

-- The unit's heals on the way (mode all or others; nil: not wanted), shields and heal absorbs (absorbs: wanted), each
-- the client's value or nil. Never compared or calculated with.
function HealPrediction.Read(unit, mode, absorbs)
    local route = HealPrediction.Route()
    if not route then return nil, nil, nil end
    if route == "calculator" then
        local calculator = reads.calculator
        if pcall(UnitGetDetailedHealPrediction, unit, "player", calculator) then
            local heal, absorb, healAbsorb
            if mode then
                -- Every healer's, yours, then other healers'.
                local ok, all, _, others = pcall(reads.heals, calculator)
                if ok then
                    if mode == "others" then heal = others else heal = all end
                end
            end
            if absorbs then
                absorb = Call(reads.absorbs, calculator)
                healAbsorb = Call(reads.healAbsorbs, calculator)
            end
            return heal, absorb, healAbsorb
        end
    end
    -- The plain APIs give every healer's heals only: other healers' need a subtraction Lua may not do on them.
    local heal
    if mode == "all" then heal = Call(UnitGetIncomingHeals, unit) end
    if not absorbs then return heal, nil, nil end
    return heal, Call(UnitGetTotalAbsorbs, unit), Call(UnitGetTotalHealAbsorbs, unit)
end

local function NewBar(parent, reverse)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    if reverse and bar.SetReverseFill then bar:SetReverseFill(true) end
    bar:Hide()
    return bar
end

-- The bars from the fill edge: heals and shields grow right from it, heal absorbs left (over the health).
local function Anchor(record, fill)
    record.fill = fill
    local heal, absorb, healAbsorb = record.heal, record.absorb, record.healAbsorb
    heal:ClearAllPoints()
    heal:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    heal:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    absorb:ClearAllPoints()
    absorb:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    absorb:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    record.absorbAfterHeal = false
    healAbsorb:ClearAllPoints()
    healAbsorb:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    healAbsorb:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
end

local function FillOf(bar)
    if type(bar.GetStatusBarTexture) ~= "function" then return nil end
    local ok, fill = pcall(bar.GetStatusBarTexture, bar)
    if ok and type(fill) == "table" then return fill end
    return nil
end

-- The bars for a health bar (bar.plateSmithHeals), made the first time a design wants them: a clipping frame over the
-- bar and three status bars in it. nil where the client gives no fill texture to start from.
function HealPrediction.Ensure(bar)
    local record = bar.plateSmithHeals
    if record then return record end
    local fill = FillOf(bar)
    if not fill then return nil end
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetAllPoints(bar)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    record = { clip = clip, heal = NewBar(clip), absorb = NewBar(clip), healAbsorb = NewBar(clip, true) }
    HealPrediction.Level(record, bar:GetFrameLevel())
    Anchor(record, fill)
    bar.plateSmithHeals = record
    return record
end

-- The bars draw over the health bar's fill, under any part in front of it: one level up, the level the draw order keeps
-- free for them (Styles.LayerLevel). At the bar's own level, plain or by SetUsingParentLevel, the bar's fill and
-- background drew over them (seen in game, and in Studio). Styles.ApplyDrawOrder keeps it so.
function HealPrediction.Level(record, level)
    if record.level == level then return end
    record.level = level
    for _, frame in ipairs({ record.clip, record.heal, record.absorb, record.healAbsorb }) do frame:SetFrameLevel(level + 1) end
end

local function Hide(record)
    record.heal:Hide()
    record.absorb:Hide()
    record.healAbsorb:Hide()
end
HealPrediction.Hide = Hide

local function Colour(bar, colour, alpha) bar:SetStatusBarColor(colour.r, colour.g, colour.b, alpha) end

-- What profile draws on record's bar: its mode and absorbs, their colours, the bar texture (textureKey: PS.Media's) and
-- the health bar's width. Off, the bars hide.
function HealPrediction.Paint(record, bar, profile, textureKey, width)
    record.mode, record.absorbs = HEALS.Mode(profile), HEALS.Absorbs(profile)
    local fill = FillOf(bar)
    if fill and fill ~= record.fill then Anchor(record, fill) end
    for _, part in ipairs({ record.heal, record.absorb, record.healAbsorb }) do
        PS.Media.SetStatusBar(part, textureKey)
        part:SetWidth(width)
    end
    Colour(record.heal, HEALS.Colour(profile, "healPredictionColour"), HealPrediction.ALPHA.heal)
    Colour(record.absorb, HEALS.Colour(profile, "absorbColour"), HealPrediction.ALPHA.absorb)
    Colour(record.healAbsorb, HealPrediction.HEAL_ABSORB_COLOUR, HealPrediction.ALPHA.healAbsorb)
    if not record.mode then record.heal:Hide() end
    if not record.absorbs then
        record.absorb:Hide()
        record.healAbsorb:Hide()
    end
end

-- One bar at value (the client's, or nil: hidden) out of maximum, through the client's sinks only.
local function Fill(bar, maximum, value)
    if HasValue(value) and pcall(bar.SetMinMaxValues, bar, 0, maximum) and pcall(bar.SetValue, bar, value) then
        bar:Show()
        return true
    end
    bar:Hide()
    return false
end

-- Draws record's wanted bars: heal, absorb and healAbsorb out of maximum (the health bar's own). Shields follow the
-- heals' end while the heals show, else the health's.
function HealPrediction.Draw(record, maximum, heal, absorb, healAbsorb)
    if not HasValue(maximum) then return Hide(record) end
    local healShown = record.mode ~= nil and Fill(record.heal, maximum, heal)
    if not record.mode then record.heal:Hide() end
    if not record.absorbs then
        record.absorb:Hide()
        record.healAbsorb:Hide()
        return
    end
    if healShown ~= record.absorbAfterHeal then
        local from = healShown and FillOf(record.heal) or nil
        if not from then from = record.fill end
        local absorbBar = record.absorb
        absorbBar:ClearAllPoints()
        absorbBar:SetPoint("TOPLEFT", from, "TOPRIGHT", 0, 0)
        absorbBar:SetPoint("BOTTOMLEFT", from, "BOTTOMRIGHT", 0, 0)
        record.absorbAfterHeal = from ~= record.fill
    end
    Fill(record.absorb, maximum, absorb)
    Fill(record.healAbsorb, maximum, healAbsorb)
end

-- The texture a design's health bar draws with: its Style's, else the plate's (healthTexture).
function HealPrediction.TextureKey(profile)
    local styles = type(profile) == "table" and profile.styles
    local style = type(styles) == "table" and styles.health
    return type(style) == "table" and style.texture or (type(profile) == "table" and profile.healthTexture or nil)
end

-- Studio's preview (Components' health bar): the sample heal and shield after its Test values' health, out of 100,
-- while the design draws them; drawn by the plates' own Ensure, Paint and Draw.
function HealPrediction.Preview(bar, profile, width)
    local on = HEALS.Mode(profile) ~= nil or HEALS.Absorbs(profile)
    local record = bar.plateSmithHeals
    if not on then
        if record then Hide(record) end
        return
    end
    record = HealPrediction.Ensure(bar)
    if not record then return end
    HealPrediction.Level(record, bar:GetFrameLevel())
    HealPrediction.Paint(record, bar, profile, HealPrediction.TextureKey(profile), width)
    local sample = HealPrediction.SAMPLE
    HealPrediction.Draw(record, 100, sample.heal, sample.absorb, nil)
end

-- The plates' side (Lifecycle's rounds.heals): bars on an owned plate's health bar, made the first time its design wants
-- them, painted with its appearance (ApplyAppearance), drawn on the health and heal events (Update), hidden when its unit
-- goes (Release). No per-frame work.
PS._CreatePlateHealPrediction = function()
    local Pass = {}

    -- PlateSmith's own full plate: never names-only, never a restricted friendly plate drawn over Blizzard's.
    local function Wanted(data)
        return data.own == true and not data.namesOnly and not data.restrictedFriendly
    end

    function Pass.ApplyAppearance(data)
        local profile = data.profile
        local on = Wanted(data) and (HEALS.Mode(profile) ~= nil or HEALS.Absorbs(profile))
        if not on then
            if data.heals then Hide(data.heals) end
            data.heals = nil
            return
        end
        local record = HealPrediction.Ensure(data.health)
        data.heals = record
        if record then HealPrediction.Paint(record, data.health, profile, HealPrediction.TextureKey(profile), profile.width) end
    end

    -- After the health bar's own update (Lifecycle's UpdateHealth) and on the heal events.
    function Pass.Update(data)
        local record = data.heals
        if not record then return end
        if not Wanted(data) then return Hide(record) end
        local maximum = data.healthMaxValue
        if not HasValue(maximum) then return Hide(record) end
        HealPrediction.Draw(record, maximum, HealPrediction.Read(data.unit, record.mode, record.absorbs))
    end

    function Pass.Release(data)
        if data.heals then Hide(data.heals) end
    end

    return Pass
end
