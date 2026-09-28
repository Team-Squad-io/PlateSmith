local _, PS = ...
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Format = assert(PS.Format, "PlateSmith Format missing")

-- Threat text, its state colours and threat facts for plates and the threat windows. Readable
-- values are formatted in Lua; protected ones pass straight into Blizzard's
-- SetFormattedText / SetValue sinks without being compared or calculated.
local ThreatText = {}
PS.ThreatText = ThreatText

-- Readable percent and signed lead, or "" when neither is readable.
function ThreatText.Readable(percent, lead)
    return Format.Threat(percent, lead) or ""
end

-- Everything readable in a threat record, falling back to "YOU" while solo.
function ThreatText.Record(info)
    if type(info) ~= "table" then return "" end
    local value = ThreatText.Readable(info.percent, info.lead)
    if value ~= "" then return value end
    local parts = {}
    if type(info.percent) == "number" then parts[#parts + 1] = Format.Percent(info.percent) end
    -- L: the lead percentage, T: raw threat.
    if type(info.leadPercent) == "number" then
        parts[#parts + 1] = string.format(L["L%s"], Format.Percent(info.leadPercent))
    end
    if type(info.rawThreat) == "number" then parts[#parts + 1] = string.format(L["T%s"], Format.Abbreviate(info.rawThreat)) end
    if #parts > 0 then return table.concat(parts, "  ") end
    if info.selfHolds then return L["YOU"] end
    return ""
end

-- Raw threat abbreviated for display (1.2k): Blizzard's abbreviation takes a protected value.
-- Returns the text or protected text, and whether there is one.
local function SinkRawThreat(info)
    local value
    if info.hasOpaqueRawThreat then
        value = info.rawThreatOpaque
    else
        value = info.rawThreat
        if value == nil then return nil, false end
    end
    local formatter = type(AbbreviateNumbers) == "function" and AbbreviateNumbers
        or type(AbbreviateLargeNumbers) == "function" and AbbreviateLargeNumbers or nil
    if formatter then
        local ok, abbreviated = pcall(formatter, value)
        if ok and Secret.IsSecret(abbreviated) then return abbreviated, true end
        if ok and Secret.IsReadable(abbreviated) and abbreviated ~= nil then return abbreviated, true end
    end
    if not info.hasOpaqueRawThreat and type(value) == "number" then return Format.Abbreviate(value), true end
    return nil, false
end

ThreatText.SinkRawThreat = SinkRawThreat

-- The signed gap the threat windows show (PS.Threat.GetGap) for unit (+125, -800): a plain
-- readable number, or nil when there is none.
function ThreatText.Gap(unit)
    local threat = PS.Threat
    if type(threat) ~= "table" or type(threat.GetGap) ~= "function" or type(unit) ~= "string" then return nil end
    local ok, gap = pcall(threat.GetGap, unit)
    if ok and Secret.IsReadable(gap) and type(gap) == "number" then return gap end
end

-- Formats by [percent][lead][raw]: lead 1 is the lead percentage (L), 2 the signed gap; T is raw
-- threat. Translated as whole format strings, so a locale can change the prefixes.
local SINK_FORMATS = {
    [true] = {
        [0] = { [true] = L["%.0f%%  T%s"], [false] = "%.0f%%" },
        [1] = { [true] = L["%.0f%%  L%.0f%%  T%s"], [false] = L["%.0f%%  L%.0f%%"] },
        [2] = { [true] = L["%.0f%%  %+.0f  T%s"], [false] = "%.0f%%  %+.0f" },
    },
    [false] = {
        [0] = { [true] = L["T%s"] },
        [1] = { [true] = L["L%.0f%%  T%s"], [false] = L["L%.0f%%"] },
        [2] = { [true] = L["%+.0f  T%s"], [false] = "%+.0f" },
    },
}

local function ApplySinkText(fontString, info, gap)
    local hasPercent = type(info.percent) == "number" or info.hasOpaquePercent == true
    -- Assign opaque values without and/or: that would test a protected value's truthiness.
    local percent, lead = info.percent, info.leadPercent
    if info.hasOpaquePercent then percent = info.percentOpaque end
    local leadKind = 0
    if gap ~= nil then
        lead, leadKind = gap, 2
    elseif type(info.leadPercent) == "number" or info.hasOpaqueLeadPercent then
        if info.hasOpaqueLeadPercent then lead = info.leadPercentOpaque end
        leadKind = 1
    end
    local raw, hasRaw = SinkRawThreat(info)
    local format = SINK_FORMATS[hasPercent][leadKind][hasRaw]
    if not format then return false end
    local set = fontString.SetFormattedText
    local ok
    if hasPercent and leadKind > 0 and hasRaw then
        ok = pcall(set, fontString, format, percent, lead, raw)
    elseif hasPercent and leadKind > 0 then
        ok = pcall(set, fontString, format, percent, lead)
    elseif hasPercent and hasRaw then
        ok = pcall(set, fontString, format, percent, raw)
    elseif leadKind > 0 and hasRaw then
        ok = pcall(set, fontString, format, lead, raw)
    elseif hasPercent then
        ok = pcall(set, fontString, format, percent)
    elseif leadKind > 0 then
        ok = pcall(set, fontString, format, lead)
    else
        ok = pcall(set, fontString, format, raw)
    end
    return ok == true
end

-- Returns how the text was produced: readable, direct-sink, fallback, hold, or empty. gap
-- (optional, from ThreatText.Gap) stands in for the lead percentage in the sink text.
function ThreatText.Apply(fontString, info, gap)
    if not fontString or type(info) ~= "table" then return "empty" end
    local readable = ThreatText.Readable(info.percent, info.lead)
    if readable ~= "" then
        fontString:SetText(readable)
        return "readable"
    end
    if type(fontString.SetFormattedText) == "function" and ApplySinkText(fontString, info, gap) then
        return (info.hasOpaquePercent or info.hasOpaqueLeadPercent or info.hasOpaqueRawThreat)
            and "direct-sink" or "fallback"
    end
    fontString:SetText(ThreatText.Record(info))
    return info.selfHolds and "hold" or "empty"
end

-- Threat facts, three-valued: true, false, or nil (unknown), from an engaged threat record (only
-- readable values are stored on it). Thresholds follow the threat windows' melee rule (a mob
-- changes target at 110% of its holder's threat): losing while someone else has 90% of your
-- threat or more (or more raw threat than you, status 2), pulling from 90% of the pull threshold
-- (or status 1). Rules read them (TemplateReaders) and the threat text is coloured by them.
local LOSING_SHARE, PULLING_PERCENT = 0.9, 90
local function Holding(info)
    if info.playerThreatNoEntry == true then return false end
    local tanking = info.tanking
    if tanking == true or tanking == false then return tanking end
end
local THREAT_FACTS = {
    holding = Holding,
    -- The gap is your margin before the next highest reaches 110% of your threat; someone at
    -- LOSING_SHARE of it leaves a gap of (1.1 - LOSING_SHARE) of your threat or less.
    losing = function(info)
        local holding = Holding(info)
        if holding ~= true then return holding end
        if info.status == 2 then return true end
        local raw, gap = info.rawThreat, info.lead
        if type(raw) == "number" and type(gap) == "number" and info.leadKind == "tank" then
            return gap <= raw * (1.1 - LOSING_SHARE)
        end
        if info.status == 3 then return false end
    end,
    pulling = function(info)
        local holding = Holding(info)
        if holding == true or info.playerThreatNoEntry == true then return false end
        if info.status == 1 then return true end
        if holding == nil then return nil end
        if type(info.percent) == "number" then return info.percent >= PULLING_PERCENT end
        if info.status == 0 then return false end
    end,
    other = function(info)
        local holding = Holding(info)
        if holding == true then return false end
        if holding == false and info.playerThreatNoEntry ~= true then return true end
        -- No threat of your own on it: held by someone else only if a group member holds it.
        if type(info.targetUnit) == "string" and info.targetUnit ~= "player" then return true end
        if holding == false then return false end
    end,
    -- Held by another tank in your group (the mob's target has the tank role).
    offtank = function(info)
        if Holding(info) == true then return false end
        local holder = info.targetUnit
        if info.holdState == "TANK" and type(holder) == "string" then return holder ~= "player" end
        if info.holdState == "YOU" or info.holdState == "LOOSE" or info.holdState == "IDLE" then return false end
    end,
}
ThreatText.Facts = THREAT_FACTS

-- Standard and colour-blind palettes; the lead sign and "YOU" carry the same meaning as the colour.
local palettes = {
    standard = { hold = { 0.25, 1, 0.3 }, losing = { 1, 0.2, 0.15 }, warning = { 1, 0.62, 0.1 }, neutral = { 1, 0.9, 0.35 } },
    colourblind = { hold = { 0.35, 0.7, 1 }, losing = { 1, 0.5, 0.05 }, warning = { 1, 0.85, 0.2 }, neutral = { 0.9, 0.9, 0.9 } },
}

-- The colorblindMode CVar, read at most once per frame: every plate and window asks each tick.
local colourBlindCVar, colourBlindReadAt
local function CVarColourBlind()
    local now = type(GetTime) == "function" and GetTime() or nil
    if now == nil or now ~= colourBlindReadAt then
        local ok, mode = false, nil
        if type(GetCVar) == "function" then ok, mode = pcall(GetCVar, "colorblindMode") end
        colourBlindCVar = ok and Secret.IsReadable(mode) and tostring(mode) == "1"
        colourBlindReadAt = now
    end
    return colourBlindCVar
end

-- colourBlind forces the colour-blind palette (Studio's own option).
function ThreatText.Palette(colourBlind)
    if colourBlind then return palettes.colourblind end
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    local choice = settings and settings.threatPalette or "auto"
    if choice == "auto" then choice = CVarColourBlind() and "colourblind" or "standard" end
    return palettes[choice] or palettes.standard
end

-- The threat text's colour by state, in the threat windows' palette (the colour-blind one with
-- that setting): you hold it (hold), you are losing it or close to pulling it (warning), someone
-- else holds it (losing). A state the client withholds changes nothing: neutral, never a guess.
function ThreatText.StateColour(info, colourBlind)
    local palette = ThreatText.Palette(colourBlind)
    local colour = palette.neutral
    if type(info) == "table" then
        if THREAT_FACTS.losing(info) == true or THREAT_FACTS.pulling(info) == true then
            colour = palette.warning
        elseif Holding(info) == true or info.selfHolds == true then
            colour = palette.hold
        elseif THREAT_FACTS.other(info) == true then
            colour = palette.losing
        end
    end
    return colour[1], colour[2], colour[3]
end
-- A threat window row's colour (Threat/Meter.lua).
function ThreatText.Colour(info)
    local palette = ThreatText.Palette()
    local colour = palette.neutral
    if info.tanking or info.selfHolds then
        colour = palette.hold
    elseif info.lead and info.lead < 0 then
        colour = palette.losing
    elseif info.percent and info.percent >= 80 then
        colour = palette.warning
    end
    return colour[1], colour[2], colour[3]
end
