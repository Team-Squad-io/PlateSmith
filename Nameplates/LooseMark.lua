-- The Loose mark: a small icon on an enemy's plate while the threat service reports the mob LOOSE (ThreatText.Facts'
-- loose, the Tank window's LOOSE and rules' threat.loose: held by someone who is not a tank). On Enemies plates it is
-- the part looseMark (off by default; the Tank look turns it on), and on Blizzard's own plates one of the extras
-- (Extras.lua places it there). It shows for tanks, or for everyone (the part's Show for), and pulses briefly as the
-- mob becomes loose: one AnimationGroup on its layer, made the first time, played once, no Lua per frame. Fails
-- closed: a hold the service cannot read (UNKNOWN), a mob out of combat or a role it cannot read shows nothing.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local ThreatText = assert(PS.ThreatText, "PlateSmith ThreatText missing")

local LooseMark = {}
PS.LooseMark = LooseMark
-- The icons: the game's own alert (the default), or the Tank window's LOOSE icon (PlateSmith's threat kit).
LooseMark.ALERT = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
LooseMark.WINDOW = "icon-loose"
-- The pulse: PULSE_TIMES dips to PULSE_LOW of its opacity and back, PULSE_SECONDS each way.
LooseMark.PULSE_LOW, LooseMark.PULSE_SECONDS, LooseMark.PULSE_TIMES = 0.2, 0.15, 2

-- The icon's size, square, before the part's Scale: the quest mark's (from the plate type's name size).
function LooseMark.Size(nameFontSize)
    return math.max(14, (tonumber(nameFontSize) or 14) + 4)
end

-- Whether the mark is for this player: tanks (style.looseFor nil), or everyone ("all"). tank: true, false or nil
-- (unknown: not a tank).
function LooseMark.ForRole(style, tank)
    if type(style) == "table" and style.looseFor == "all" then return true end
    return tank == true
end

-- Whether a threat record says the mob is loose now: engaged and the fact readably true.
function LooseMark.IsLoose(info)
    if type(info) ~= "table" or info.engaged ~= true then return false end
    return ThreatText.Facts.loose(info) == true
end

-- Whether the mark shows: for this player and loose. Plates and Studio's preview (Test values' Loose and You tank)
-- both decide here.
function LooseMark.Shows(style, tank, loose)
    return loose == true and LooseMark.ForRole(style, tank)
end

-- Draws the style's icon on texture (set only when the choice changes). The Tank window's icon falls back to the
-- game's alert where the kit cannot be drawn.
function LooseMark.Paint(texture, style)
    local choice = type(style) == "table" and style.looseIcon == "window" and "window" or "alert"
    if texture.plateSmithLooseIcon == choice then return end
    texture.plateSmithLooseIcon = choice
    local themes = PS.ThreatThemes
    if choice == "window" and themes and themes.SetKit(texture, LooseMark.WINDOW) then
        texture:SetTexCoord(themes.TexCoord(LooseMark.WINDOW))
        return
    end
    -- The kit keeps the file it set (threatKitKey): forgotten, so choosing it again sets it again.
    texture.threatKitKey = nil
    texture:SetTexture(LooseMark.ALERT)
    texture:SetTexCoord(0, 1, 0, 1)
end

-- The pulse on frame (the mark's layer): made the first time, then played once from the start. A client without
-- animations just shows the mark.
function LooseMark.Pulse(frame)
    local group = frame.plateSmithLoosePulse
    if group == nil then
        group = false
        if type(frame.CreateAnimationGroup) == "function" then
            group = frame:CreateAnimationGroup()
            local low = LooseMark.PULSE_LOW
            for index = 1, LooseMark.PULSE_TIMES * 2 do
                local fade = group:CreateAnimation("Alpha")
                local out = index % 2 == 1
                fade:SetFromAlpha(out and 1 or low)
                fade:SetToAlpha(out and low or 1)
                fade:SetDuration(LooseMark.PULSE_SECONDS)
                fade:SetOrder(index)
            end
        end
        frame.plateSmithLoosePulse = group
    end
    if not group then return false end
    if group:IsPlaying() then group:Stop() end
    group:Play()
    return true
end

function LooseMark.StopPulse(frame)
    local group = frame and frame.plateSmithLoosePulse
    if group and group:IsPlaying() then group:Stop() end
end

-- The plate side. context: Styles, AnchorPart (Placement), MarkStacks, PlaceExtra (Extras' PlaceLoose: a mark made on
-- Blizzard's plate). A plate's mark is made the first time it is
-- wanted, in its own layer over the plate. Update follows the plate's threat record (Lifecycle's UpdateThreat, on a
-- new record or its refresh), so only a change shows, hides or pulses it.
PS._CreatePlateLooseMark = function(context)
    local Styles, AnchorPart, MarkStacks = context.Styles, context.AnchorPart, context.MarkStacks
    local Pass = { shown = setmetatable({}, { __mode = "k" }) }

    local function Style(data)
        local styles = data.profile and data.profile.styles
        return styles and styles.looseMark or nil
    end

    local function PartShown(data)
        local position = data.layout and data.layout.looseMark
        return position ~= nil and not S.TurnedOff(position)
    end

    -- An owned enemy plate whose layout shows the part, or Blizzard's plate with the extra on (data.extras).
    local function Wanted(data, settings)
        if data.friendly ~= false or data.object then return false end
        if data.own then return PartShown(data) end
        return data.extras == true and type(settings) == "table" and settings.extrasLoose == true
    end
    Pass.Wanted = Wanted

    local function ApplySize(data)
        local size = LooseMark.Size(data.profile and data.profile.nameFontSize)
        data.looseMark:SetSize(size, size)
    end

    function Pass.Ensure(data)
        if data.looseMark then return data.looseMark end
        local layer = CreateFrame("Frame", nil, data.overlay)
        layer:SetAllPoints(data.overlay)
        data.layerFrames.looseMark = layer
        local icon = layer:CreateTexture(nil, "OVERLAY")
        icon:Hide()
        data.looseMark, data.looseMarkLayer = icon, layer
        ApplySize(data)
        if data.own and data.layout and data.layout.looseMark then
            AnchorPart(data, icon, "looseMark")
            layer:SetFrameLevel(Styles.LayerLevel(data, "looseMark"))
            data.stackStatesFor = nil
            MarkStacks(data)
        elseif not data.own and context.PlaceExtra then
            -- On Blizzard's plate the extras place it (Extras.lua).
            context.PlaceExtra(data)
        end
        return icon
    end

    local function SetShown(data, shown)
        local icon = data.looseMark
        if not icon or (icon:IsShown() and true or false) == shown then return end
        icon:SetShown(shown)
        Pass.shown[data] = shown or nil
        if not shown then LooseMark.StopPulse(data.looseMarkLayer) end
        -- What is pinned to the mark takes its place while it is hidden (Placement's Absent).
        if data.own then MarkStacks(data) end
    end

    -- info: the plate's engaged threat record, or nil (none, out of combat, not an enemy). settings: the working copy.
    function Pass.Update(data, info, settings)
        if not Wanted(data, settings) then
            SetShown(data, false)
            data.looseState = nil
            return
        end
        -- Made while wanted, hidden or not, so what is pinned to it takes its place while it is hidden.
        local icon = Pass.Ensure(data)
        local style = Style(data)
        local loose = LooseMark.IsLoose(info)
        local tank = loose and PS.ThreatColours.IsTank(settings, PS.ThreatColours.PlayerTanks) or nil
        local shown = LooseMark.Shows(style, tank, loose)
        if shown then
            LooseMark.Paint(icon, style)
            -- A pulse as it becomes loose (not on every refresh of a mob that already is).
            if not data.looseState and not (type(style) == "table" and style.loosePulse == false) then
                LooseMark.Pulse(data.looseMarkLayer)
            end
        end
        data.looseState = shown or nil
        SetShown(data, shown)
    end

    -- Sized again after a settings change (ApplyAppearance); its icon follows the next Update.
    function Pass.ApplyAppearance(data)
        if not data.looseMark then return end
        ApplySize(data)
        data.looseMark.plateSmithLooseIcon = nil
        LooseMark.Paint(data.looseMark, Style(data))
    end

    function Pass.Release(data)
        SetShown(data, false)
        data.looseState = nil
    end

    LooseMark._pass = Pass
    return Pass
end

-- For /ps diagnose (extras.loose): how many plates show the mark now.
function LooseMark.ShownCount()
    local pass, count = LooseMark._pass, 0
    for data in pairs(pass and pass.shown or {}) do
        if data.looseMark and data.looseMark:IsShown() then count = count + 1 end
    end
    return count
end
