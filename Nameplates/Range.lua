-- Whether a plate's unit is within reach (unit.inrange) and how far, in bands (range.band, {range}), and the Range part
-- that shows it (+ Add › Text › Range). The answers come from the player's own spellbook: every known spell with a
-- readable reach, harmful ones on enemies and helpful ones on friends, one per distinct reach; and out of combat the
-- interact distances. A few plates are checked per tick, only while a layout shows the part or reads the range; an
-- answer the client withholds is unknown (nil). Bands are as close as those spells can tell, not exact yards.
local _, PS = ...
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

local Range = {}
PS.Range = Range

-- Bands by the nearest reach the unit is known to be within, in yards: melee up to MELEE, near up to NEAR, then far;
-- out when nothing reaches it. A melee spell's range (the client says 0 or 5) counts as MELEE.
Range.MELEE, Range.NEAR = 5, 20
-- CheckInteractDistance's follow distance (about 28 yards), and the distances the bands ask: duel (about 10) and follow.
local INTERACT_DISTANCE = 4
Range.INTERACT_DISTANCES = { { 3, 10 }, { INTERACT_DISTANCE, 28 } }
Range.PLATES_PER_TICK = 4
Range.INTERVAL = 0.2
Range.TICKER = "plates.range"
-- The spellbook scan: at most CAP spells asked per unit (one per distinct reach, the shortest and the longest always
-- among them), none reaching past MAX_REACH yards (Hunter's Mark's 100 would put every unit in range), and at most
-- MAX_ITEMS spellbook entries looked at.
Range.CAP, Range.MAX_REACH, Range.MAX_ITEMS = 6, 45, 600
-- The events after which the spells are worked out again (registered only where the client knows them; SPELLS_CHANGED
-- everywhere): learned or replaced spells, a new level, talents and specs (which can change a spell's reach).
Range.EVENTS = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP",
    "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED" }

-- true or false from a readable answer (a boolean, or 1 and 0 from older APIs); nil otherwise.
local function Answer(ok, value)
    if not ok or not IsReadable(value) then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
    return nil
end
local function Ask(api, ...)
    if type(api) ~= "function" then return nil end
    return Answer(pcall(api, ...))
end

-- A spell's readable reach (C_Spell.GetSpellInfo's, else GetSpellInfo's), read when the spells are worked out (again
-- after a talent or spec change): { min, max }, min 0 when unread; nil when the reach is not readable.
local function SpellRange(spell)
    local minimum, maximum
    local info = C_Spell and C_Spell.GetSpellInfo
    if type(info) == "function" then
        local ok, result = pcall(info, spell)
        if ok and IsReadable(result) and type(result) == "table" then
            minimum, maximum = Secret.Number(result.minRange), Secret.Number(result.maxRange)
        end
    end
    if not maximum and type(GetSpellInfo) == "function" then
        local ok, _, _, _, _, low, high = pcall(GetSpellInfo, spell)
        if ok then minimum, maximum = Secret.Number(low), Secret.Number(high) end
    end
    if not maximum or maximum ~= maximum or maximum < 0 or maximum > 1000 then return nil end
    if not minimum or minimum ~= minimum or minimum < 0 then minimum = 0 end
    return { min = minimum, max = math.max(maximum, Range.MELEE), melee = maximum <= Range.MELEE }
end

-- Whether a spellbook entry is harmful and whether it is helpful (each true, false or nil), by its spell ID (C_Spell),
-- else by its place in the book (C_SpellBook, else the older globals with book "spell").
local function SpellKind(spell, index, bank, older)
    local api = C_Spell
    local harm = Ask(api and api.IsSpellHarmful, spell)
    local help = Ask(api and api.IsSpellHelpful, spell)
    if harm == nil and help == nil and not older then
        local book = C_SpellBook
        harm = Ask(book and book.IsSpellBookItemHarmful, index, bank)
        help = Ask(book and book.IsSpellBookItemHelpful, index, bank)
    end
    if harm == nil and help == nil and older then
        harm, help = Ask(IsHarmfulSpell, index, "spell"), Ask(IsHelpfulSpell, index, "spell")
    end
    return harm, help
end

-- false only on the client's readable no: a spell with no reach of its own (self or area), which never answers.
local function HasRange(spell, index, older)
    local api = C_Spell
    local has = Ask(api and api.SpellHasRange, spell)
    if has == nil and older then has = Ask(SpellHasRange, index, "spell") end
    return has ~= false
end

-- Every learned spell in the player's spellbook: visit(spell, index, bank, older), at most MAX_ITEMS entries. The
-- client's C_SpellBook skill lines (passive, off-spec and not-yet-learned entries skipped), else the older spell tabs.
-- unread(): an entry the client did not answer readably (the spells are worked out again after combat).
local function EachBookSpell(visit, unread)
    local book, seen = C_SpellBook, 0
    if type(book) == "table" and type(book.GetNumSpellBookSkillLines) == "function"
        and type(book.GetSpellBookSkillLineInfo) == "function" and type(book.GetSpellBookItemInfo) == "function" then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
        local ok, lines = pcall(book.GetNumSpellBookSkillLines)
        lines = ok and Secret.Number(lines)
        if not lines then unread() end
        for line = 1, math.min(lines or 0, 32) do
            local okLine, info = pcall(book.GetSpellBookSkillLineInfo, line)
            local offset = okLine and IsReadable(info) and type(info) == "table" and Secret.Number(info.itemIndexOffset)
            local count = offset and Secret.Number(info.numSpellBookItems)
            if not count then unread() end
            for index = (offset or 0) + 1, (offset or 0) + (count or 0) do
                seen = seen + 1
                if seen > Range.MAX_ITEMS then return end
                local okItem, item = pcall(book.GetSpellBookItemInfo, index, bank)
                if not (okItem and IsReadable(item) and type(item) == "table") then
                    unread()
                elseif Secret.Number(item.itemType) == spellType and not (IsReadable(item.isPassive) and item.isPassive == true)
                    and not (IsReadable(item.isOffSpec) and item.isOffSpec == true) then
                    local spell = Secret.Number(item.spellID) or Secret.Number(item.actionID)
                    if spell then visit(spell, index, bank, false) else unread() end
                end
            end
        end
        return
    end
    if type(GetNumSpellTabs) ~= "function" or type(GetSpellTabInfo) ~= "function"
        or type(GetSpellBookItemInfo) ~= "function" then
        return
    end
    local ok, tabs = pcall(GetNumSpellTabs)
    for tab = 1, math.min(ok and Secret.Number(tabs) or 0, 16) do
        local okTab, _, _, offset, count = pcall(GetSpellTabInfo, tab)
        offset, count = okTab and Secret.Number(offset), okTab and Secret.Number(count) or 0
        for index = (offset or 0) + 1, (offset or 0) + count do
            seen = seen + 1
            if seen > Range.MAX_ITEMS then return end
            local okItem, kind, spell = pcall(GetSpellBookItemInfo, index, "spell")
            if not (okItem and IsReadable(kind)) then unread() end
            spell = okItem and IsReadable(kind) and kind == "SPELL" and Secret.Number(spell)
            if spell and not (IsPassiveSpell and Ask(IsPassiveSpell, index, "spell")) then visit(spell, index, "spell", true) end
        end
    end
end

-- The spells to ask, harmful (harm) and helpful (help): for each distinct reach one spell, preferring one with no
-- minimum range (its no then means too far, never too close); at most CAP, ordered longest first. ranges: spell ->
-- { min, max, melee }. A helpful spell needs a reach (a self buff's is 0).
local known
local function Pick(byReach)
    local reaches = {}
    for _, entry in pairs(byReach) do reaches[#reaches + 1] = entry end
    table.sort(reaches, function(left, right)
        if left.range.max ~= right.range.max then return left.range.max > right.range.max end
        return left.spell < right.spell
    end)
    local spells, count = {}, #reaches
    if count <= Range.CAP then
        for index = 1, count do spells[index] = reaches[index].spell end
    else
        -- Spread over the reaches, the longest and the shortest included.
        for pick = 1, Range.CAP do
            spells[pick] = reaches[1 + math.floor((pick - 1) * (count - 1) / (Range.CAP - 1) + 0.5)].spell
        end
    end
    return spells
end
local function Better(entry, spell, range)
    if not entry then return true end
    if (entry.range.min > 0) ~= (range.min > 0) then return range.min == 0 end
    return spell < entry.spell
end
local function Build()
    local harm, help, ranges, partial = {}, {}, {}, false
    local function Unread() partial = true end
    EachBookSpell(function(spell, index, bank, older)
        local isHarm, isHelp = SpellKind(spell, index, bank, older)
        if isHarm == nil and isHelp == nil then partial = true end
        if not (isHarm or isHelp) or not HasRange(spell, index, older) then return end
        local range = SpellRange(spell)
        if not range then partial = true end
        if not range or range.max > Range.MAX_REACH then return end
        -- Melee reaches all count as one (the client says 0 or 5).
        local reach = range.melee and 0 or math.floor(range.max + 0.5)
        if isHarm and Better(harm[reach], spell, range) then harm[reach] = { spell = spell, range = range } end
        if isHelp and not range.melee and Better(help[reach], spell, range) then help[reach] = { spell = spell, range = range } end
        ranges[spell] = range
    end, Unread)
    return { harm = Pick(harm), help = Pick(help), ranges = ranges, partial = partial }
end
local function KnownSpells(friendly)
    known = known or Build()
    return friendly and known.help or known.harm, known.ranges
end
-- The spells asked now (worked out if needed), for the probe and tests: harmful, helpful, and their ranges.
function Range.Spells()
    KnownSpells(false)
    return known.harm, known.help, known.ranges
end

function Range.Invalidate() known = nil end

-- Whether one spell reaches unit (Rescue's range fade): true, false, or nil when the client has no answer, a
-- protected one, or no such API.
function Range.SpellInRange(spell, unit)
    local api = C_Spell and C_Spell.IsSpellInRange
    if type(api) ~= "function" then return nil end
    return Answer(pcall(api, spell, unit))
end

-- The band and its text for inRange's answer, from the nearest reach the unit is within (upper) and the farthest it is
-- known to be past (lower): nil, nil while unknown. Each text is made once (yards are whole and at most 1000). Studio's
-- preview asks it too.
local WITHIN, PAST = {}, {}
local function Text(cache, format, yards)
    yards = math.floor(yards + 0.5)
    local text = cache[yards]
    if not text then
        text = string.format(format, yards)
        cache[yards] = text
    end
    return text
end
function Range.Band(inRange, upper, lower)
    if inRange == false then return "out", lower and Text(PAST, "%d+", lower) or nil end
    if inRange ~= true or not upper then return nil, nil end
    local text = Text(WITHIN, "<%d", upper)
    if upper <= Range.MELEE then return "melee", text end
    if upper <= Range.NEAR then return "near", text end
    return "far", text
end

-- The answers of one plate's unit: every chosen spell asked (Check stops at the first that reaches), then out of combat
-- the interact distances. A spell with a minimum range that says no may mean too close: it tells how far past its reach
-- the unit is only once a nearer no rules that out (a no without a minimum range, or an interact distance, at least as
-- far as its minimum), and while one cannot be ruled out the unit is not said to be out of range (unknown instead).
-- Returns inRange (true, false or nil), upper, lower.
local pending = {}
local function Gather(unit, friendly, measure)
    local api = C_Spell and C_Spell.IsSpellInRange
    local reached, answered, upper, lower = false, false, nil, nil
    local waiting = 0
    if type(api) == "function" then
        local spells, ranges = KnownSpells(friendly)
        for index = 1, #spells do
            local spell = spells[index]
            local answer, range = Answer(pcall(api, spell, unit)), ranges[spell]
            if answer then
                if not measure then return true end
                reached = true
                if not upper or range.max < upper then upper = range.max end
            elseif answer == false then
                answered = true
                if range.min == 0 then
                    if not lower or range.max > lower then lower = range.max end
                else
                    waiting = waiting + 1
                    pending[waiting] = range
                end
            end
        end
    end
    local inCombat = Secret.InCombat()
    if type(CheckInteractDistance) == "function" and not inCombat and (measure or not reached) then
        for _, distance in ipairs(Range.INTERACT_DISTANCES) do
            if measure or distance[1] == INTERACT_DISTANCE then
                local answer = Answer(pcall(CheckInteractDistance, unit, distance[1]))
                if answer and (not upper or distance[2] < upper) then upper = distance[2] end
                if answer == false and (not lower or distance[2] > lower) then lower = distance[2] end
                -- With no spell's answer the follow distance decides.
                if distance[1] == INTERACT_DISTANCE and not (reached or answered) and answer ~= nil then
                    reached, answered = answer, not answer
                end
            end
        end
    end
    -- A no from a spell with a minimum range counts once the unit is known to be past that minimum.
    local resolved = true
    repeat
        local changed = false
        for index = 1, waiting do
            local range = pending[index]
            if range and lower and range.min <= lower then
                if range.max > lower then lower = range.max end
                pending[index], changed = false, true
            end
        end
    until not changed
    for index = 1, waiting do
        if pending[index] then resolved = false end
        pending[index] = nil
    end
    if reached then return true, upper, lower end
    if answered and resolved then return false, upper, lower end
    return nil, nil, nil
end

-- true, false, or nil when nothing readable answered. friendly: a friendly plate's unit (helpful spells).
function Range.Check(unit, friendly)
    return (Gather(unit, friendly, false))
end

-- unit.inrange as Check answers it, then its band ("melee", "near", "far" or "out") and text ("<5", "<30", "30+"):
-- every chosen spell is asked, and out of combat the interact distances too.
-- The farthest the player can reach a unit of that kind with a chosen spell (nil with none): an out-of-range unit reads
-- as past it ("30+"), whichever answer said no, so every out-of-range plate reads alike.
local function Longest(friendly)
    local spells, ranges = KnownSpells(friendly)
    local longest
    for index = 1, #spells do
        local range = ranges[spells[index]]
        if range and (not longest or range.max > longest) then longest = range.max end
    end
    return longest
end
Range.Longest = Longest

function Range.Measure(unit, friendly)
    local inRange, upper, lower = Gather(unit, friendly, true)
    if inRange == false then lower = Longest(friendly) or lower end
    return inRange, Range.Band(inRange, upper, lower)
end

-- The Range part (+ Add › Text › Range; style fields rangeDisplay, rangeShow, rangeInColour, rangeOutColour, and the
-- text rows): a dot, the band's text ("<30", "30+") or both, in its in-range or out-of-range colour, shown out of range
-- (the default), in range or always, and hidden while the range is unknown. The plates and Studio's preview draw it here.
-- On Objects it shows the game's in-reach answer instead (interact.inrange, read by the Action icon's pass, only while
-- the game gives the plate an icon): its words (rangeOutText, rangeInText; nil OBJECT_WORDS) by default, or a dot.
Range.PART = { DISPLAYS = { dot = true, text = true, both = true }, SHOWS = { out = true, ["in"] = true, always = true },
    IN = { r = 0.2, g = 0.8, b = 0.2 }, OUT = { r = 1, g = 0.2, b = 0.2 }, DOT = { image = "kit:dot" }, GAP = 2 }
Range.PART.DISPLAY_CHOICES = { { value = "dot", label = L["Dot"] }, { value = "text", label = L["Distance"] },
    { value = "both", label = L["Dot and distance"] } }
Range.PART.SHOW_CHOICES = { { value = "out", label = L["Out of range"] }, { value = "in", label = L["In range"] },
    { value = "always", label = L["Always"] } }
-- Objects' choices (the first is the default) and words.
Range.PART.OBJECT_DISPLAY_CHOICES = { { value = "text", label = L["Words"] }, { value = "dot", label = L["Dot"] },
    { value = "both", label = L["Dot and words"] } }
Range.PART.OBJECT_SHOW_CHOICES = { { value = "out", label = L["Out of reach"] }, { value = "in", label = L["In reach"] },
    { value = "always", label = L["Always"] } }
Range.OBJECT_WORDS = { out = L["Too far"], ["in"] = L["In reach"] }
local EMPTY = {}

-- What the style shows: its Display (object: an Objects plate's, words by default), its Show, and whether it reads the
-- band (its text).
function Range.PartDisplay(style, object)
    style = type(style) == "table" and style or EMPTY
    return Range.PART.DISPLAYS[style.rangeDisplay] and style.rangeDisplay or (object and "text" or "dot"),
        Range.PART.SHOWS[style.rangeShow] and style.rangeShow or "out"
end

-- An Objects plate's answer: the game's in-reach answer while it gives the plate an Action icon (kind), as Out of
-- reach's cue reads it; else unknown (nil). Its words for that answer (nil while unknown).
function Range.ObjectAnswer(kind, inRange)
    if kind == nil then return nil end
    return inRange
end
function Range.ObjectWords(style, inRange)
    if inRange == nil then return nil end
    style = type(style) == "table" and style or EMPTY
    if inRange then return style.rangeInText or Range.OBJECT_WORDS["in"] end
    return style.rangeOutText or Range.OBJECT_WORDS.out
end
function Range.PartReadsBand(style) return Range.PartDisplay(style) ~= "dot" end

-- Whether the part shows for inRange (true, false, or nil: unknown, never shown).
function Range.PartShows(style, inRange)
    if inRange == nil then return false end
    local _, show = Range.PartDisplay(style)
    return show == "always" or (show == "in") == (inRange == true)
end

-- The dot's size for the text's drawn size in points.
function Range.DotSize(points)
    return math.max(6, math.floor((tonumber(points) or 10) * 0.8 + 0.5))
end

-- The part's pieces on frame (a plate's holder, or Studio's component): the dot and the text.
function Range.BuildPart(frame)
    frame.rangeDot = frame:CreateTexture(nil, "OVERLAY")
    frame.rangeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.rangeDot:Hide()
    frame.rangeLabel:Hide()
    if PS.ValueImage then PS.ValueImage.Draw(frame.rangeDot, Range.PART.DOT) end
    return frame
end

-- A text's width: the client's, else as wide as its letters at size points.
local function TextWidth(label, text, points)
    local width = Secret.ReadNumber(label, "GetStringWidth")
    if width and width > 0 then return width end
    return #text * points * 0.55
end

-- Draws the part on frame for inRange and text (the band's, or an object's words; nil while it has none), its text
-- already in its font at points (drawn size). preview: draws what it would show even while it does not (Studio's faint
-- part). object: an Objects plate's part (Range.PartDisplay). Sizes frame to what it draws; returns whether the part
-- shows and whether anything is drawn.
function Range.PaintPart(frame, style, inRange, text, points, preview, object)
    style = type(style) == "table" and style or EMPTY
    local display = Range.PartDisplay(style, object)
    local shows = Range.PartShows(style, inRange)
    local drawn = shows or preview == true
    local colour = inRange == true and (style.rangeInColour or Range.PART.IN) or (style.rangeOutColour or Range.PART.OUT)
    local dot, label = frame.rangeDot, frame.rangeLabel
    local dotShown = drawn and display ~= "text"
    local textShown = drawn and display ~= "dot" and type(text) == "string"
    local size = Range.DotSize(points)
    dot:SetSize(size, size)
    dot:SetVertexColor(colour.r, colour.g, colour.b)
    dot:SetShown(dotShown)
    if frame.plateSmithRangeText ~= (textShown and text or "") then
        frame.plateSmithRangeText = textShown and text or ""
        label:SetText(frame.plateSmithRangeText)
    end
    label:SetTextColor(colour.r, colour.g, colour.b)
    label:SetShown(textShown)
    label:ClearAllPoints()
    if dotShown then
        label:SetPoint("LEFT", dot, "RIGHT", Range.PART.GAP, 0)
    else
        label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    end
    dot:ClearAllPoints()
    dot:SetPoint("LEFT", frame, "LEFT", 0, 0)
    local width = dotShown and size or 0
    if textShown then width = width + (dotShown and Range.PART.GAP or 0) + TextWidth(label, text, points) end
    frame:SetSize(math.max(1, width), math.max(size, tonumber(points) or size))
    return shows, dotShown or textShown
end

-- The plate pass. context: active (unit -> plate), MarkValues, RunBatch, Styles, AnchorPart, MarkStacks,
-- ApplyNameplateFont. Each tick checks up to PLATES_PER_TICK plates that show the part or whose rules or text read the
-- range, in turn over a list of the active plates taken again once a round, so no tick's work grows with the plate count.
-- The entry is off while nothing reads the range (SetWanted). The part's frame is made the first time a plate's layout
-- shows it.
PS._CreatePlateRange = function(context)
    local active, MarkValues, RunBatch = context.active, context.MarkValues, context.RunBatch
    local Styles, AnchorPart, MarkStacks = context.Styles, context.AnchorPart, context.MarkStacks
    local S = PS.ProfileSchema
    local Pass = { wanted = false }
    local round, cursor = {}, 0

    local function Style(data)
        local styles = data.profile and data.profile.styles
        return styles and styles.range or nil
    end

    -- The part on this plate: PlateSmith's own, its layout showing it.
    local function PartShown(data)
        local position = data.own and data.layout and data.layout.range
        return position ~= nil and position ~= false and not S.TurnedOff(position)
    end

    -- Whether the plate's part, rules or text read the range (any plate but an object's whose friendliness is known),
    -- and whether they read its band (range.band, {range}, the part's text), which asks every spell.
    local function Reads(data)
        if not (data.own and not data.object and data.friendly ~= nil) then return false, false end
        local reads, part = data.reads, PartShown(data)
        local band = part and Range.PartReadsBand(Style(data))
        if reads == nil then return part, band end
        local rules, values = reads.rules, reads.values
        return part or rules.range == true or values.range == true,
            band or rules.rangeBand == true or values.rangeBand == true
    end

    local function FontSize(data)
        return S.PartTextSize("range", data.profile and data.profile.nameFontSize)
    end

    function Pass.Ensure(data)
        if data.range then return data.range end
        local layer = CreateFrame("Frame", nil, data.overlay)
        layer:SetAllPoints(data.overlay)
        data.layerFrames.range = layer
        local holder = Range.BuildPart(CreateFrame("Frame", nil, layer))
        holder:Hide()
        data.range = holder
        Styles.StyledFont(data, "range", holder.rangeLabel, FontSize(data))
        if data.layout and data.layout.range then AnchorPart(data, holder, "range") end
        layer:SetFrameLevel(Styles.LayerLevel(data, "range"))
        data.stackStatesFor = nil
        MarkStacks(data)
        return holder
    end

    -- The part drawn for the plate's answer (an object's: the Action icon's pass, which calls this when it changes);
    -- only a change of what shows marks its stacks.
    function Pass.Paint(data)
        local holder = data.range
        if not holder then return end
        local shown = false
        if PartShown(data) then
            local points = S.ScaledFontSize(S.StyledFontSize(FontSize(data), Style(data)),
                PS.GetSettings and PS.GetSettings().textScale)
            local inRange, text = data.inRange, data.rangeText
            if data.object then
                inRange = Range.ObjectAnswer(data.objectKind, data.interactInRange)
                text = Range.ObjectWords(Style(data), inRange)
            end
            local shows, drawn = Range.PaintPart(holder, Style(data), inRange, text, points, nil, data.object)
            shown = shows and drawn
        end
        if (holder:IsShown() and true or false) ~= shown then
            holder:SetShown(shown)
            MarkStacks(data)
        end
    end

    -- After a settings change (ApplyAppearance): made where the layout shows it, in its font, and drawn again.
    function Pass.ApplyAppearance(data)
        if not data.range and not PartShown(data) then return end
        local holder = Pass.Ensure(data)
        Styles.StyledFont(data, "range", holder.rangeLabel, FontSize(data))
        holder.plateSmithRangeText = nil
        Pass.Paint(data)
    end

    -- What reads the answer follows only a change.
    local function Set(data, inRange, band, text)
        if data.inRange ~= inRange or data.rangeBand ~= band or data.rangeText ~= text then
            data.inRange, data.rangeBand, data.rangeText = inRange, band, text
            MarkValues(data, "range")
            Pass.Paint(data)
        end
    end

    function Pass.Release(data)
        if data.range and data.range:IsShown() then data.range:Hide() end
    end

    local function Refill()
        for index = #round, 1, -1 do round[index] = nil end
        for unit, data in pairs(active) do
            if data.unit == unit then round[#round + 1] = data end
        end
        cursor = 0
    end

    function Pass.Tick()
        local checked, refilled = 0, false
        while checked < Range.PLATES_PER_TICK do
            if cursor >= #round then
                if refilled then break end
                Refill()
                refilled = true
                if #round == 0 then break end
            end
            cursor = cursor + 1
            local data = round[cursor]
            if data.unit and active[data.unit] == data then
                local reads, band = Reads(data)
                if reads then
                    if band then
                        Set(data, Range.Measure(data.unit, data.friendly))
                    else
                        Set(data, Range.Check(data.unit, data.friendly), nil, nil)
                    end
                    checked = checked + 1
                elseif data.inRange ~= nil then
                    Set(data, nil, nil, nil)
                end
            end
        end
    end

    -- On while a layout shows the part or reads the range; off, every plate's answer is forgotten.
    function Pass.SetWanted(wanted)
        wanted = wanted and true or false
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        PS.Ticker.SetEnabled(Range.TICKER, wanted)
        if not wanted then
            for unit, data in pairs(active) do
                if data.unit == unit then
                    data.inRange, data.rangeBand, data.rangeText = nil, nil, nil
                    Pass.Paint(data)
                end
            end
            for index = #round, 1, -1 do round[index] = nil end
            cursor = 0
        end
    end

    PS.Ticker.Register(Range.TICKER, Range.INTERVAL, function() RunBatch(false, Pass.Tick) end)
    PS.Ticker.SetEnabled(Range.TICKER, false)
    return Pass
end

-- The spells are worked out again after the spellbook, the level, talents or the spec change (on the next check), and
-- after combat when the client kept an answer when they were last worked out.
do
    local frame = CreateFrame("Frame")
    local utils = C_EventUtils
    for _, event in ipairs(Range.EVENTS) do
        local valid = event == "SPELLS_CHANGED"
        if not valid and type(utils) == "table" and type(utils.IsEventValid) == "function" then
            local ok, answer = pcall(utils.IsEventValid, event)
            valid = ok and IsReadable(answer) and answer == true
        end
        if valid then PS._RegisterEvent(frame, event, "platesmith.range") end
    end
    PS._RegisterEvent(frame, "PLAYER_REGEN_ENABLED", "platesmith.range")
    frame:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_REGEN_ENABLED" or (known and known.partial) then Range.Invalidate() end
    end)
    Range.events = frame
end
