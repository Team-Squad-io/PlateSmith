local _, PS = ...
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Format = assert(PS.Format, "PlateSmith Format missing")

-- Threat text, its state colours and threat facts for plates and the threat windows. Readable
-- values are formatted in Lua; protected ones pass straight into Blizzard's
-- SetFormattedText / SetValue sinks without being compared or calculated.
local ThreatText = {}
PS.ThreatText = ThreatText

local function IsReadableNumber(value)
    return Secret.IsReadable(value) and type(value) == "number"
end

-- The gap is a kept target, hover, focus or group member's target read (the threat service's leadKept,
-- kept for the profile's threatKeptHold), not a live one: its text starts with "~" so it is never
-- shown as live, and it looks stale as threatKeptStyle says (dimmed, fading with age, or grey).
local KEPT_PREFIX = "~"
local function Kept(info)
    return type(info) == "table" and info.leadKept == true
end
ThreatText.Kept = Kept
ThreatText.KEPT_PREFIX = KEPT_PREFIX

local function Settings()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return type(settings) == "table" and settings or nil
end
local KEPT_STYLES = { dim = true, fade = true, grey = true }
-- "Fade with age": from FADE_FROM to FADE_TO over the hold (FADE_UNTIL seconds while it is kept as
-- long as the mob lives). "Grey": this colour instead of the state's.
local FADE_FROM, FADE_TO, FADE_UNTIL = 0.85, 0.35, 30
local KEPT_GREY = { 0.62, 0.62, 0.62 }

function ThreatText.KeptStyle()
    local settings = Settings()
    local style = settings and settings.threatKeptStyle
    return KEPT_STYLES[style] and style or "dim"
end

function ThreatText.ShowKeptAge()
    local settings = Settings()
    return settings ~= nil and settings.threatKeptAge == true
end

-- Seconds since the kept gap was read (keptAt, a readable GetTime stamp), or nil.
local function KeptSeconds(info)
    if not Kept(info) or type(GetTime) ~= "function" then return nil end
    local at, now = info.keptAt, GetTime()
    if not IsReadableNumber(at) or not IsReadableNumber(now) then return nil end
    return math.max(0, now - at)
end

-- The kept gap's age in whole seconds, or nil when it is live or has no stamp.
function ThreatText.KeptAge(info)
    local seconds = KeptSeconds(info)
    return seconds and math.floor(seconds) or nil
end

-- The alpha a kept gap's text shows with: fading with age, dim (the threat windows pass theirs;
-- plates are not dimmed), else 1.
function ThreatText.KeptAlpha(info, dim)
    if not Kept(info) then return 1 end
    local style = ThreatText.KeptStyle()
    if style == "fade" then
        local service, span = PS.ThreatService, FADE_UNTIL
        if type(service) == "table" and type(service.KeptHold) == "function" then span = service.KeptHold() or FADE_UNTIL end
        local share = math.min(1, (KeptSeconds(info) or 0) / math.max(1, span))
        return FADE_FROM + (FADE_TO - FADE_FROM) * share
    end
    if style == "dim" and dim then return dim end
    return 1
end

-- Grey instead of the state colour: the kept gap's colour, or nil.
local function KeptGrey(info)
    if Kept(info) and ThreatText.KeptStyle() == "grey" then return KEPT_GREY end
    return nil
end

-- The text marked kept ("~"), with its age after it when the profile shows it ("~100%  +145  3s").
local function MarkKept(info, text)
    if text ~= "" and Kept(info) then
        local age = ThreatText.ShowKeptAge() and ThreatText.KeptAge(info)
        if age then return string.format("%s%s  %s", KEPT_PREFIX, text, string.format(L["%ds"], age)) end
        return KEPT_PREFIX .. text
    end
    return text
end

ThreatText.MarkKept = MarkKept

-- A sink format for a kept gap: "~" before it and, when shown, a trailing age slot (KeptAge).
local function KeptFormat(info, format)
    local age = ThreatText.ShowKeptAge() and ThreatText.KeptAge(info)
    if age then return KEPT_PREFIX .. format .. "  " .. L["%ds"], age end
    return KEPT_PREFIX .. format, nil
end

-- Readable percent and signed lead, or "" when neither is readable.
function ThreatText.Readable(percent, lead)
    return Format.Threat(percent, lead) or ""
end

-- Everything readable in a threat record, falling back to "YOU" while solo.
function ThreatText.Record(info)
    if type(info) ~= "table" then return "" end
    local value = ThreatText.Readable(info.percent, info.lead)
    if value ~= "" then return MarkKept(info, value) end
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

-- SetFormattedText with count values (possibly protected), then the age when there is one.
local function SinkCall(fontString, format, age, count, a, b, c)
    local set = fontString.SetFormattedText
    if count == 1 then
        if age then return pcall(set, fontString, format, a, age) end
        return pcall(set, fontString, format, a)
    elseif count == 2 then
        if age then return pcall(set, fontString, format, a, b, age) end
        return pcall(set, fontString, format, a, b)
    end
    if age then return pcall(set, fontString, format, a, b, c, age) end
    return pcall(set, fontString, format, a, b, c)
end

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
    local age
    if leadKind == 2 and Kept(info) then format, age = KeptFormat(info, format) end
    local ok
    if hasPercent and leadKind > 0 and hasRaw then
        ok = SinkCall(fontString, format, age, 3, percent, lead, raw)
    elseif hasPercent and leadKind > 0 then
        ok = SinkCall(fontString, format, age, 2, percent, lead)
    elseif hasPercent and hasRaw then
        ok = SinkCall(fontString, format, age, 2, percent, raw)
    elseif leadKind > 0 and hasRaw then
        ok = SinkCall(fontString, format, age, 2, lead, raw)
    elseif hasPercent then
        ok = SinkCall(fontString, format, age, 1, percent)
    elseif leadKind > 0 then
        ok = SinkCall(fontString, format, age, 1, lead)
    else
        ok = SinkCall(fontString, format, age, 1, raw)
    end
    return ok == true
end

-- The lead percentage and raw threat forms (L…%, T…), for the "detailed" threat text.
local function ApplyDetailed(fontString, info, gap)
    local readable = ThreatText.Readable(info.percent, info.lead)
    if readable ~= "" then
        fontString:SetText(MarkKept(info, readable))
        return "readable"
    end
    if type(fontString.SetFormattedText) == "function" and ApplySinkText(fontString, info, gap) then
        return (info.hasOpaquePercent or info.hasOpaqueLeadPercent or info.hasOpaqueRawThreat)
            and "direct-sink" or "fallback"
    end
    fontString:SetText(ThreatText.Record(info))
    return info.selfHolds and "hold" or "empty"
end

-- "% and gap" (and "% only" without the gap): your threat % and the signed gap the threat windows
-- show (+145, -230). The gap is only ever a readable number; a protected percent goes into the
-- format sink, and with no readable gap only the percent shows.
-- Settings › Experimental (Solo hover gap): the threat service's curve gap (raw x 1.1 evaluated by a
-- client curve, possibly protected) beside the percent, straight into the sink. False when there is
-- none or the client refuses it, and the caller shows what it would have.
local function ApplyCurveGap(fontString, info)
    if info.hasCurveLead ~= true or type(fontString.SetFormattedText) ~= "function" then return false end
    local percent
    if info.hasOpaquePercent then
        percent = info.percentOpaque
    elseif IsReadableNumber(info.percent) then
        percent = info.percent
    else
        return false
    end
    local shown = pcall(fontString.SetFormattedText, fontString, "%.0f%%  %+.0f", percent, info.curveLeadOpaque)
    -- For /ps diagnose's experimental section (readable words and counts only).
    info.curveState = shown and "shown" or "display-refused"
    local stats = type(PS.ThreatService) == "table" and PS.ThreatService.curveStats
    if shown and type(stats) == "table" then stats.shown, stats.state = stats.shown + 1, "shown" end
    return shown
end

local function ApplyPercentGap(fontString, info, gap, withGap)
    local lead
    if withGap then
        if IsReadableNumber(gap) then lead = gap elseif IsReadableNumber(info.lead) then lead = info.lead end
    end
    if withGap and (lead == nil or Kept(info)) and ApplyCurveGap(fontString, info) then return "curve-sink" end
    if type(info.percent) == "number" or (lead ~= nil and not info.hasOpaquePercent) then
        local text = Format.Threat(info.percent, lead) or ""
        fontString:SetText(lead ~= nil and MarkKept(info, text) or text)
        return "readable"
    end
    if info.hasOpaquePercent and type(fontString.SetFormattedText) == "function" then
        local ok
        if lead ~= nil then
            local format, age = "%.0f%%  %s", nil
            if Kept(info) then format, age = KeptFormat(info, format) end
            ok = SinkCall(fontString, format, age, 2, info.percentOpaque, Format.SignedLead(lead))
        else
            ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%", info.percentOpaque)
        end
        if ok then return "direct-sink" end
    end
    fontString:SetText(info.selfHolds and L["YOU"] or "")
    return info.selfHolds and "hold" or "empty"
end

ThreatText.FORMATS = { gap = true, percent = true, detailed = true }

-- The threat text format the profile chose (Schema's threatTextFormat), "gap" by default.
function ThreatText.Format()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    local format = settings and settings.threatTextFormat
    return ThreatText.FORMATS[format] and format or "gap"
end

-- Returns how the text was produced: readable, direct-sink, fallback, hold, or empty. gap
-- (optional, from ThreatText.Gap) is the signed gap; format (optional) overrides the profile's.
-- Texts showing a kept gap whose look changes with its age (the age shown, or fading), refreshed
-- once a second by one ticker entry that sleeps while there are none. fontString.threatKeptRefresh
-- (a threat window's cell) redraws it; a plate's text is written again with its state colour.
local KEPT_TICKER = "threat.kept-age"
local keptWatch = setmetatable({}, { __mode = "k" })
local keptGaps = setmetatable({}, { __mode = "k" })
ThreatText._keptWatch = keptWatch

local function Watch(fontString, info, gap)
    if Kept(info) and (ThreatText.ShowKeptAge() or ThreatText.KeptStyle() == "fade") then
        if not keptWatch[fontString] and not PS.Ticker.IsEnabled(KEPT_TICKER) then PS.Ticker.SetEnabled(KEPT_TICKER, true) end
        keptWatch[fontString], keptGaps[fontString] = info, gap
    elseif keptWatch[fontString] then
        keptWatch[fontString], keptGaps[fontString] = nil, nil
    end
end

-- A text that no longer shows a threat record (cleared, or showing another unit's).
function ThreatText.Forget(fontString)
    if fontString and keptWatch[fontString] then keptWatch[fontString], keptGaps[fontString] = nil, nil end
end

function ThreatText.Apply(fontString, info, gap, format)
    if not fontString or type(info) ~= "table" then
        ThreatText.Forget(fontString)
        return "empty"
    end
    format = ThreatText.FORMATS[format] and format or ThreatText.Format()
    Watch(fontString, info, gap)
    if format == "detailed" then return ApplyDetailed(fontString, info, gap) end
    return ApplyPercentGap(fontString, info, gap, format == "gap")
end

local function RefreshPlateKept(fontString, info, gap)
    ThreatText.Apply(fontString, info, gap)
    ThreatText.ApplyStateColour(fontString, info)
end

PS.Ticker.Register(KEPT_TICKER, 1, function()
    for fontString, info in pairs(keptWatch) do
        local visible = not fontString.IsVisible or fontString:IsVisible()
        if visible and Kept(info) then
            (fontString.threatKeptRefresh or RefreshPlateKept)(fontString, info, keptGaps[fontString])
        else
            keptWatch[fontString], keptGaps[fontString] = nil, nil
        end
    end
    if next(keptWatch) == nil then PS.Ticker.SetEnabled(KEPT_TICKER, false) end
end)
PS.Ticker.SetEnabled(KEPT_TICKER, false)

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
local function StatePaletteColour(info, palette)
    if type(info) ~= "table" then return palette.neutral end
    local grey = KeptGrey(info)
    if grey then return grey end
    if THREAT_FACTS.losing(info) == true or THREAT_FACTS.pulling(info) == true then return palette.warning end
    if Holding(info) == true or info.selfHolds == true then return palette.hold end
    if THREAT_FACTS.other(info) == true then return palette.losing end
    return palette.neutral
end

function ThreatText.StateColour(info, colourBlind)
    local colour = StatePaletteColour(info, ThreatText.Palette(colourBlind))
    return colour[1], colour[2], colour[3]
end

-- One step of a colour fold inside the client (Secret.Pick): colour when the flag (possibly
-- protected) is true, else r, g, b (themselves possibly protected, from an earlier step). True and
-- the new r, g, b (for sinks only), or false when the client has no such sink.
local function FoldColour(flag, colour, r, g, b)
    local okR, nr = Secret.Pick(flag, colour[1], r)
    local okG, ng = Secret.Pick(flag, colour[2], g)
    local okB, nb = Secret.Pick(flag, colour[3], b)
    if okR and okG and okB then return true, nr, ng, nb end
    return false
end
ThreatText.FoldColour = FoldColour

-- Whether only a protected "are you holding it" answer is known: the record keeps the client's
-- flag (tankingOpaque) for sinks while its readable tanking is unknown.
local function OnlyOpaqueHolding(info)
    return type(info) == "table" and info.hasOpaqueTanking == true and info.tanking == nil
        and info.playerThreatNoEntry ~= true
end

-- The plate's threat text colour (StateColour) set on region. When nothing readable says who holds
-- it, the group's protected "holding it" answers (the threat service's holdFlags; yours first when
-- holdFlagsHaveSelf) are folded in the client: yours gives the hold colour, anyone else's the
-- colour for someone else holding it, none of them neutral. A kept gap fading with age takes its
-- alpha in the colour, so a rule's or the plate's own alpha on the text is left alone.
function ThreatText.ApplyStateColour(region, info, colourBlind)
    local palette = ThreatText.Palette(colourBlind)
    local colour = StatePaletteColour(info, palette)
    local alpha = ThreatText.KeptAlpha(info)
    if alpha == 1 then alpha = nil end
    local count = type(info) == "table" and info.holdFlagCount or 0
    if colour == palette.neutral and type(count) == "number" and count > 0 then
        local flags, own = info.holdFlags, info.holdFlagsHaveSelf == true
        local ok, r, g, b = true, colour[1], colour[2], colour[3]
        for index = own and 2 or 1, count do
            ok, r, g, b = FoldColour(flags[index], palette.losing, r, g, b)
            if not ok then break end
        end
        if ok and own then ok, r, g, b = FoldColour(flags[1], palette.hold, r, g, b) end
        if ok and alpha and pcall(region.SetTextColor, region, r, g, b, alpha) then return end
        if ok and not alpha and pcall(region.SetTextColor, region, r, g, b) then return end
    end
    if alpha then
        region:SetTextColor(colour[1], colour[2], colour[3], alpha)
    else
        region:SetTextColor(colour[1], colour[2], colour[3])
    end
end

-- A threat window row's colour from readable facts (Threat/Meter.lua): you hold it but someone is
-- about to pull it (warning, as on plates), you hold it (hold), someone else is ahead of you
-- (losing), close to pulling it (warning). holding overrides the record's own answer.
local function RowPaletteColour(info, palette, holding)
    local grey = KeptGrey(info)
    if grey then return grey end
    if holding == nil then holding = info.tanking == true end
    if holding and THREAT_FACTS.losing(info) == true then return palette.warning end
    if holding or info.selfHolds == true then return palette.hold end
    if type(info.lead) == "number" and info.lead < 0 then return palette.losing end
    if type(info.percent) == "number" and info.percent >= 80 then return palette.warning end
    return palette.neutral
end

function ThreatText.Colour(info)
    local colour = RowPaletteColour(info, ThreatText.Palette())
    return colour[1], colour[2], colour[3]
end

-- A row's threat text coloured (Colour); with only a protected "are you holding it" answer, the
-- client's sink picks between the holding colour and the one it would have otherwise.
function ThreatText.ApplyColour(region, info)
    local palette = ThreatText.Palette()
    if OnlyOpaqueHolding(info) and not KeptGrey(info) then
        local otherwise = RowPaletteColour(info, palette, false)
        local ok, r, g, b = FoldColour(info.tankingOpaque, palette.hold, otherwise[1], otherwise[2], otherwise[3])
        if ok and pcall(region.SetTextColor, region, r, g, b) then return end
    end
    local colour = RowPaletteColour(info, palette)
    region:SetTextColor(colour[1], colour[2], colour[3])
end
