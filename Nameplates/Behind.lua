-- Whether your target's or focus's plate is behind the camera (unit.behind), and the Behind you part that shows it
-- (+ Add › Icons › Behind you): the game's own answer (C_NamePlateManager.IsNamePlateUnitBehindCamera), kept per plate
-- as true only on a readable yes, read again on NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED for the plate's own token and when
-- the target or focus changes, and cleared when the plate is reused. It is the camera's relation only: not a direction,
-- a distance or line of sight; nothing is projected. Off while no layout shows the part and nothing reads unit.behind
-- (Schema's BehindNeeded), which is the default.
local _, PS = ...
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

local Behind = { EVENT = "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED", TICKER = "plates.behind", INTERVAL = 0.5 }
PS.Behind = Behind

local function Api()
    local manager = C_NamePlateManager
    local api = type(manager) == "table" and manager.IsNamePlateUnitBehindCamera
    return type(api) == "function" and api or nil
end

function Behind.Supported() return Api() ~= nil end

-- true on the client's readable yes for a nameplate unit; nil otherwise (no API, an error, a protected answer, no).
function Behind.Read(unit)
    local api = Api()
    if not api then return nil end
    local ok, value = pcall(api, unit)
    if ok and IsReadable(value) and value == true then return true end
    return nil
end

-- The Behind you part (style fields behindDisplay, behindFor, behindColour, and the text rows): an arrow pointing down
-- at the name (PlateSmith's kit arrow) or the words "Behind you", in its colour, on your target's plate (Who: Target
-- only, the default) or your target's and focus's (Target and focus) while the game says it is behind the camera. The
-- plates and Studio's preview draw it here.
Behind.PART = { COLOUR = { r = 1, g = 0.6, b = 0.2 }, PICTURE = { image = "kit:arrow", rotation = 90 } }
Behind.PART.DISPLAY_CHOICES = { { value = "icon", label = L["Icon"] }, { value = "text", label = L["Text"] } }
Behind.PART.FOR_CHOICES = { { value = "target", label = L["Target only"] },
    { value = "focus", label = L["Target and focus"] } }
local EMPTY = {}

-- The style's Display ("icon" or "text") and For ("target" or "focus": target and focus).
function Behind.PartDisplay(style)
    style = type(style) == "table" and style or EMPTY
    return style.behindDisplay == "text" and "text" or "icon", style.behindFor == "focus" and "focus" or "target"
end

-- Whether the part shows: behind (the game's yes) on your target's plate, or your focus's with Target and focus.
function Behind.PartShows(style, behind, target, focus)
    if behind ~= true then return false end
    local _, who = Behind.PartDisplay(style)
    return target == true or (who == "focus" and focus == true)
end

-- The icon's size for the text's drawn size in points.
function Behind.IconSize(points)
    return math.max(12, math.floor((tonumber(points) or 12) + 4.5))
end

-- The part's pieces on frame (a plate's holder, or Studio's component): the icon and the text.
function Behind.BuildPart(frame)
    frame.behindIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.behindIcon:SetAllPoints(frame)
    frame.behindIcon:Hide()
    frame.behindLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.behindLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.behindLabel:SetText(L["Behind you"])
    frame.behindLabel:Hide()
    if PS.ValueImage then PS.ValueImage.Draw(frame.behindIcon, Behind.PART.PICTURE) end
    return frame
end

-- Draws the part on frame, its text already in its font at points (drawn size), and sizes frame to it.
function Behind.PaintPart(frame, style, points)
    style = type(style) == "table" and style or EMPTY
    local display = Behind.PartDisplay(style)
    local colour = style.behindColour or Behind.PART.COLOUR
    local icon, label = frame.behindIcon, frame.behindLabel
    icon:SetVertexColor(colour.r, colour.g, colour.b)
    label:SetTextColor(colour.r, colour.g, colour.b)
    icon:SetShown(display == "icon")
    label:SetShown(display == "text")
    points = tonumber(points) or 12
    if display == "icon" then
        local size = Behind.IconSize(points)
        frame:SetSize(size, size)
    else
        local width = Secret.ReadNumber(label, "GetStringWidth")
        if not (width and width > 0) then width = #L["Behind you"] * points * 0.55 end
        frame:SetSize(width, points)
    end
end

-- The plate pass. context: active (unit -> plate), MarkValues, RunBatch, Styles, AnchorPart, MarkStacks. Only the
-- target's and focus's plates are asked (at most two), on the event, on a change of target (Lifecycle's UpdateTarget)
-- or focus (FocusChanged), and by a slow backstop while one is watched, in case the client withholds the event. The
-- part's frame is made the first time a plate's layout shows it.
PS._CreatePlateBehind = function(context)
    local active, MarkValues, RunBatch = context.active, context.MarkValues, context.RunBatch
    local Styles, AnchorPart, MarkStacks = context.Styles, context.AnchorPart, context.MarkStacks
    local S = PS.ProfileSchema
    local Pass = { wanted = false }
    -- The plates of your target and focus as last updated.
    local watched = {}

    local function Style(data)
        local styles = data.profile and data.profile.styles
        return styles and styles.behindYou or nil
    end

    local function PartShown(data)
        local position = data.own and not data.object and data.layout and data.layout.behindYou
        return position ~= nil and position ~= false and not S.TurnedOff(position)
    end

    local function FontSize(data)
        return S.PartTextSize("behindYou", data.profile and data.profile.nameFontSize)
    end

    function Pass.Ensure(data)
        if data.behindYou then return data.behindYou end
        local layer = CreateFrame("Frame", nil, data.overlay)
        layer:SetAllPoints(data.overlay)
        data.layerFrames.behindYou = layer
        local holder = Behind.BuildPart(CreateFrame("Frame", nil, layer))
        holder:Hide()
        data.behindYou = holder
        Styles.StyledFont(data, "behindYou", holder.behindLabel, FontSize(data))
        if data.layout and data.layout.behindYou then AnchorPart(data, holder, "behindYou") end
        layer:SetFrameLevel(Styles.LayerLevel(data, "behindYou"))
        data.stackStatesFor = nil
        MarkStacks(data)
        return holder
    end

    -- The part shown for the plate's answer; only a change marks its stacks.
    function Pass.Paint(data)
        local holder = data.behindYou
        if not holder then return end
        local shown = PartShown(data) and Behind.PartShows(Style(data), data.behind, data.targeted == true,
            data.behindFocus == true)
        if (holder:IsShown() and true or false) ~= shown then
            holder:SetShown(shown)
            MarkStacks(data)
        end
    end

    -- After a settings change (ApplyAppearance): made where the layout shows it, in its font and look.
    function Pass.ApplyAppearance(data)
        if not data.behindYou and not PartShown(data) then return end
        local holder = Pass.Ensure(data)
        Styles.StyledFont(data, "behindYou", holder.behindLabel, FontSize(data))
        local points = S.ScaledFontSize(S.StyledFontSize(FontSize(data), Style(data)),
            PS.GetSettings and PS.GetSettings().textScale)
        Behind.PaintPart(holder, Style(data), points)
        Pass.Paint(data)
    end

    local function Set(data, behind)
        if data.behind ~= behind then
            data.behind = behind
            MarkValues(data, "behind")
        end
        Pass.Paint(data)
    end

    -- PlateSmith's own plate (never an object's) of your target or focus: whether it is each.
    local function Watches(data)
        if not (Pass.wanted and data.own and not data.object and data.unit and active[data.unit] == data) then
            return false, false
        end
        return data.targeted == true, Secret.SameUnit(data.unit, "focus")
    end

    function Pass.Update(data)
        local target, focus = Watches(data)
        local watch = target or focus
        watched[data] = watch or nil
        data.behindFocus = focus or nil
        Set(data, watch and Behind.Read(data.unit) or nil)
        if watch then PS.Ticker.SetEnabled(Behind.TICKER, true) end
    end

    -- The watched plates read again; the backstop sleeps once there are none.
    local function UpdateWatched()
        local any = false
        for data in pairs(watched) do
            Pass.Update(data)
            any = any or watched[data] ~= nil
        end
        if not any then PS.Ticker.SetEnabled(Behind.TICKER, false) end
    end

    -- Every plate looked at again: your focus may be any of them (an event, not a tick).
    local function UpdateAll()
        for unit, data in pairs(active) do
            if data.unit == unit then Pass.Update(data) end
        end
    end

    function Pass.FocusChanged()
        if Pass.wanted then RunBatch(false, UpdateAll) end
    end

    -- The plate leaves its unit: its answer goes with it.
    function Pass.Release(data)
        watched[data] = nil
        data.behind, data.behindFocus = nil, nil
        if data.behindYou and data.behindYou:IsShown() then data.behindYou:Hide() end
    end

    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, _, unit)
        if not Pass.wanted then return end
        -- The event's unit is used only once readable and a plate's own token ("target" and "softenemy" come too);
        -- otherwise the watched plates are read again.
        local token = IsReadable(unit) and type(unit) == "string" and unit or nil
        local data = token and active[token] or nil
        if data and data.unit == token then
            RunBatch(false, Pass.Update, data)
        elseif not token or token:sub(1, 9) == "nameplate" then
            RunBatch(false, UpdateWatched)
        end
    end)
    Pass.events = events

    -- Registered only where the client has the API and knows the event, so other clients print nothing.
    local function Listen(on)
        if not on then
            if type(events.UnregisterEvent) == "function" then events:UnregisterEvent(Behind.EVENT) end
            return
        end
        local utils = C_EventUtils
        if type(utils) == "table" and type(utils.IsEventValid) == "function" then
            local ok, valid = pcall(utils.IsEventValid, Behind.EVENT)
            if not (ok and IsReadable(valid) and valid == true) then return end
        end
        PS._RegisterEvent(events, Behind.EVENT, "platesmith.behind")
    end

    -- On while a layout shows the part or a rule or text reads unit.behind, and the client can answer; off, every
    -- plate's answer goes.
    function Pass.SetWanted(wanted)
        wanted = (wanted and Behind.Supported()) and true or false
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        Listen(wanted)
        if wanted then
            RunBatch(false, UpdateAll)
        else
            PS.Ticker.SetEnabled(Behind.TICKER, false)
            for data in pairs(watched) do
                watched[data] = nil
                data.behindFocus = nil
                Set(data, nil)
            end
        end
    end

    PS.Ticker.Register(Behind.TICKER, Behind.INTERVAL, function() RunBatch(false, UpdateWatched) end)
    PS.Ticker.SetEnabled(Behind.TICKER, false)
    return Pass
end
