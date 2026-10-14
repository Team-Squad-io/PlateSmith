-- The Objects plate's Status text and what it reads: the object's requirement from the game's own tooltip (a line
-- such as "Requires Mining (65)"), read when the player hovers the object in the world and kept by the object's ID
-- for the account (state.objectTooltips, the oldest going past 300), so once one Tin Vein is hovered every Tin Vein's
-- plate can show it; and the player's skill from the client's skill lines. The skill in a line is found by the
-- player's own skill names as the client gives them, never by a list of names here. An object no kept line names a
-- skill for is looked up in the original game's herbs and ore veins (Data/GatherSkills.lua), as Herbalism and Mining
-- by PlateSmith's own names for them. Herbs also show Cultivation (Nameplates/Cultivation.lua) to a player who knows
-- it. Unknown shows nothing.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Cultivation = assert(PS.Cultivation, "PlateSmith Cultivation missing")
local Gather = PS.GatherSkills or {}
local L = PS.L
local IsReadable, String = Secret.IsReadable, Secret.String

local ObjectStatus = {}
PS.ObjectStatus = ObjectStatus
ObjectStatus.EVENTS = { "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "PLAYER_LEVEL_UP" }
-- The text's colour: you can (green), you can't yet (red), unknown (white).
-- Colour keys: can/cannot/plain, and the game's gathering skill-up colours (orange: a skill point every time, yellow:
-- often, green ("can"): rarely, grey: never; red ("cannot"): above your skill).
ObjectStatus.COLOURS = { can = { 0.4, 0.95, 0.4 }, cannot = { 1, 0.32, 0.26 }, plain = { 0.92, 0.92, 0.92 },
    orange = { 1, 0.5, 0.25 }, yellow = { 1, 0.9, 0.2 }, grey = { 0.62, 0.62, 0.62 } }

-- The game's gathering colours for your rank against the level an object needs: red below it, orange up to 25 over,
-- yellow up to 50, green up to 100, grey beyond.
function ObjectStatus.SkillColour(rank, level)
    if rank < level then return "cannot" end
    local over = rank - level
    if over < 25 then return "orange" end
    if over < 50 then return "yellow" end
    if over < 100 then return "can" end
    return "grey"
end
local LIMITS = S.stateDefaults.objectTooltipLimits
-- Bumped when what a requirement reads changes (a line stored, the player's skills), so Requirement's memo follows.
ObjectStatus.revision = 0

-- The player's skills: name -> rank (with its modifier where the client gives one), readable values only. Read once
-- after each change of skill (SKILL_LINES_CHANGED, CHAT_MSG_SKILL: Forget). Classic's skill lines, else the
-- professions API; neither: none.
local skills
local function Rank(rank, modifier)
    if not (IsReadable(rank) and type(rank) == "number") then return nil end
    if IsReadable(modifier) and type(modifier) == "number" then return rank + modifier end
    return rank
end

local function ReadSkills()
    local found = {}
    if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local ok, count = pcall(GetNumSkillLines)
        if ok and IsReadable(count) and type(count) == "number" then
            for index = 1, math.min(count, 120) do
                local okLine, name, header, _, rank, _, modifier = pcall(GetSkillLineInfo, index)
                name = okLine and String(name) or nil
                if name and IsReadable(header) and not header then found[name] = Rank(rank, modifier) end
            end
        end
    elseif type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, a, b, c, d, e = pcall(GetProfessions)
        for _, index in ipairs(ok and { a, b, c, d, e } or {}) do
            if IsReadable(index) and type(index) == "number" then
                local okInfo, name, _, rank, _, _, _, _, modifier = pcall(GetProfessionInfo, index)
                name = okInfo and String(name) or nil
                if name then found[name] = Rank(rank, modifier) end
            end
        end
    end
    return found
end

function ObjectStatus.Skills()
    if not skills then skills = ReadSkills() end
    return skills
end

function ObjectStatus.Forget()
    skills = nil
    ObjectStatus.revision = ObjectStatus.revision + 1
end

-- The cached lines: the account's state, made the first time a line is kept.
local function Cache(create)
    local state = type(PS.GetState) == "function" and PS.GetState() or nil
    if not state then return nil end
    local cache = state.objectTooltips
    if not cache and create then
        cache = { order = {}, byID = {} }
        state.objectTooltips = cache
    end
    return cache
end

function ObjectStatus.Lines(id)
    local cache = id and Cache(false)
    return cache and cache.byID[id] or nil
end

-- id moved to the newest end of the order (most recently seen).
local function Touch(cache, id)
    local order = cache.order
    for index = #order, 1, -1 do
        if order[index] == id then
            if index == #order then return end
            table.remove(order, index)
            break
        end
    end
    order[#order + 1] = id
    while #order > LIMITS.entries do cache.byID[table.remove(order, 1)] = nil end
end

-- A plate shows an object whose lines are kept: it stays among the newest.
function ObjectStatus.Seen(id)
    local cache = id and Cache(false)
    if cache and cache.byID[id] then Touch(cache, id) end
end

-- A readable line cut to the cache's bytes, never inside a character; nil for anything else.
local function Line(text)
    text = String(text)
    if not text then return nil end
    if #text > LIMITS.bytes then text = text:sub(1, LIMITS.bytes):gsub("[\192-\255][\128-\191]*$", "") end
    return text ~= "" and text or nil
end
ObjectStatus.Line = Line

-- Keeps lines (readable text after the object's name, at most LIMITS.lines) for object id. True when they differ from
-- what was kept.
function ObjectStatus.Store(id, lines)
    if type(id) ~= "number" or id <= 0 or type(lines) ~= "table" then return false end
    local kept = {}
    for _, line in ipairs(lines) do
        line = Line(line)
        if line and #kept < LIMITS.lines then kept[#kept + 1] = line end
    end
    local cache = Cache(true)
    if not cache then return false end
    local old = cache.byID[id]
    Touch(cache, id)
    if old and PS.Table.DeepEqual(old, kept) then return false end
    cache.byID[id] = kept
    ObjectStatus.revision = ObjectStatus.revision + 1
    return true
end

-- The skill each of Data/GatherSkills.lua's tables needs, by the name the client's skill lines give it.
local DATA_SKILLS = { herb = L["Herbalism"], ore = L["Mining"] }

-- What the original game's data says object id needs: { skill, level, line, kind } or nil (not a herb or vein it
-- lists). A level of 0 there is the skill at any rank: 1.
local function DataRequirement(id)
    for kind, skill in pairs(DATA_SKILLS) do
        local level = type(Gather[kind]) == "table" and Gather[kind][id]
        if type(level) == "number" then
            level = math.max(1, level)
            return { skill = skill, level = level, line = string.format(L["%s %d"], skill, level), kind = kind }
        end
    end
    return nil
end

-- Whether object id (with the kind its Action icon read, if any) is a herb: true, false, or nil (unknown).
function ObjectStatus.IsHerb(id, kind)
    if kind == "herb" or (type(id) == "number" and type(Gather.herb) == "table" and Gather.herb[id]) then return true end
    if kind ~= nil or (type(id) == "number" and type(Gather.ore) == "table" and Gather.ore[id]) then return false end
    return nil
end

-- What object id needs, from its kept lines and the player's skill names (and Herbalism's and Mining's, which a
-- player without them still meets on herbs and veins): { skill, level (nil when the line has no number), line } or nil
-- (never hovered, or no line names one of those skills). The game's data (DataRequirement) gives it where no line
-- does, and its level where the line has none (WoW Forever's tooltip says "Requires Herbalism" without one). Worked
-- out once per revision.
local memo = {}
function ObjectStatus.Requirement(id)
    if type(id) ~= "number" then return nil end
    local known = memo[id]
    if known and known.revision == ObjectStatus.revision then return known.result or nil end
    local result = false
    local lines = ObjectStatus.Lines(id)
    if lines then
        local names, seen = {}, {}
        for name in pairs(ObjectStatus.Skills()) do names[#names + 1], seen[name] = name, true end
        for _, name in pairs(DATA_SKILLS) do
            if not seen[name] then names[#names + 1], seen[name] = name, true end
        end
        -- The longest name first, so a skill whose name holds another's is found as itself.
        table.sort(names, function(a, b) return #a > #b or (#a == #b and a < b) end)
        for _, line in ipairs(lines) do
            for _, name in ipairs(names) do
                if #name >= 3 and line:find(name, 1, true) then
                    result = { skill = name, level = tonumber(line:match("%d+")), line = line }
                    break
                end
            end
            if result then break end
        end
    end
    if not (result and result.level) then result = DataRequirement(id) or result end
    memo[id] = { revision = ObjectStatus.revision, result = result }
    return result or nil
end

-- object.skill and object.cangather: the level object id needs, and whether your skill reaches it (nil: unknown).
function ObjectStatus.Level(id)
    local need = ObjectStatus.Requirement(id)
    return need and need.level or nil
end

function ObjectStatus.CanGather(id)
    local need = ObjectStatus.Requirement(id)
    local rank = need and ObjectStatus.Skills()[need.skill]
    if not (need and need.level and rank) then return nil end
    return rank >= need.level
end

-- object.cancultivate (Cultivation.Can) for object id, with its kind and readable GUID (nil: unknown).
function ObjectStatus.CanCultivate(id, kind, guid)
    local need = ObjectStatus.Requirement(id)
    return Cultivation.Can(ObjectStatus.IsHerb(id, kind), guid, need and need.level)
end

-- Whether you can use object id after all although its icon says Unable (Fade objects you can't use): your skill
-- reaches it, or you can cultivate it.
function ObjectStatus.Usable(id, kind, guid)
    return ObjectStatus.CanGather(id) == true or ObjectStatus.CanCultivate(id, kind, guid) == true
end

-- The skill part's text and colour key.
local function SkillText(need, unable)
    local rank = ObjectStatus.Skills()[need.skill]
    if need.level and rank then
        return string.format(L["%s %d"], need.skill, need.level), ObjectStatus.SkillColour(rank, need.level)
    end
    return need.line, unable == true and "cannot" or "plain"
end

-- Joins the skill part (text, colour) with Cultivation's (cultivate, its colour key): each part keeps its own colour,
-- the skill's as the text's and Cultivation's inline, so "Herbalism 1" can be red beside a green "Cultivate ready".
local function Inline(text, key)
    local c = ObjectStatus.COLOURS[key] or ObjectStatus.COLOURS.plain
    return string.format("|cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), text)
end
local function WithCultivation(text, colour, cultivate, cultivateColour)
    if not cultivate then return text, colour end
    if not text then return cultivate, cultivateColour or "plain" end
    colour = colour or "plain"
    if cultivateColour ~= colour then cultivate = Inline(cultivate, cultivateColour) end
    return string.format(L["%s · %s"], text, cultivate), colour
end

-- The Status text for object id: its text and colour key (ObjectStatus.COLOURS), or nil (unknown: hidden). "Mining 65"
-- in the game's gathering colour for your skill (SkillColour) when both numbers are known; else the game's own line (or
-- the data's "Herbalism 150"), red while the game's icon says you can't (unable: object.unable). A herb (kind: its
-- Action icon's, guid: its readable GUID) adds Cultivation's state for a player who knows it ("Cultivate ready",
-- "Cultivate in 23m", "Cultivated", "Cultivate at level 30") in its own colour.
function ObjectStatus.Text(id, unable, kind, guid)
    local need = ObjectStatus.Requirement(id)
    local text, colour
    if need then text, colour = SkillText(need, unable) end
    return WithCultivation(text, colour, Cultivation.Status(ObjectStatus.IsHerb(id, kind), guid, need and need.level))
end

-- The hover tooltip's detail for object id: "Your Mining: 72" and what the colour means, or nil when either number is
-- unknown. Two strings (the second may be nil).
local SKILL_HINTS = { orange = L["A skill point every time"], yellow = L["A skill point most times"],
    can = L["A skill point now and then"], grey = L["No more skill points from this"],
    cannot = L["Your skill is too low"] }
function ObjectStatus.SkillDetail(id)
    local need = ObjectStatus.Requirement(id)
    local rank = need and need.level and ObjectStatus.Skills()[need.skill]
    if not rank then return nil end
    return string.format(L["Your %s: %d"], need.skill, rank), SKILL_HINTS[ObjectStatus.SkillColour(rank, need.level)]
end

-- Studio's sample for an object kind (Test values' Object, Can't use yet and Cultivation ready): what the plate would
-- show for a herb, ore or a locked chest; nil for a kind with no skill. Drawn by the same routes, with a sample skill.
local SAMPLE_SKILLS = { herb = L["Herbalism"], ore = L["Mining"], loot = L["Lockpicking"] }
function ObjectStatus.Sample(kind, unable, cultivate)
    local skill = SAMPLE_SKILLS[kind]
    if not skill then return nil end
    local level, rank = 65, unable and 40 or 72
    local text, colour = string.format(L["%s %d"], skill, level), ObjectStatus.SkillColour(rank, level)
    if kind == "herb" and cultivate then return WithCultivation(text, colour, Cultivation.Sample()) end
    return text, colour
end

-- The tooltip capture: the object the game's tooltip is about, by its GUID when the tooltip data gives one, else
-- the hovered or interaction target's game object whose name is the tooltip's first line. Its ID, or nil.
local CANDIDATES = { "mouseover", "softinteract" }
local function ObjectID(data, name)
    local guid = type(data) == "table" and String(data.guid) or nil
    if guid then
        local kind, id = Secret.GUIDEntry(guid)
        return kind == "GameObject" and id or nil
    end
    if not name then return nil end
    for _, unit in ipairs(CANDIDATES) do
        if Secret.IsGameObject(unit) and Secret.ReadName(unit) == name then
            local kind, id = Secret.GUIDEntry(Secret.ReadGUID(unit))
            if kind == "GameObject" then return id end
        end
    end
    return nil
end

-- The tooltip's lines as text: from its data (TooltipDataProcessor, C_TooltipInfo), else its own font strings. The
-- first is the object's name.
local function DataLines(data)
    local lines = {}
    for index, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
        if index > LIMITS.lines + 1 then break end
        lines[index] = type(line) == "table" and String(line.leftText) or false
    end
    return lines
end

local function FrameLines(tooltip)
    local lines = {}
    local name = type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    local count = Secret.ReadNumber(tooltip, "NumLines") or 0
    for index = 1, math.min(count, LIMITS.lines + 1) do
        local region = name and _G[name .. "TextLeft" .. index]
        local text
        if region and type(region.GetText) == "function" then
            local ok, value = pcall(region.GetText, region)
            if ok then text = String(value) end
        end
        lines[index] = text or false
    end
    return lines
end

-- Called with what the game's tooltip shows; keeps the lines when they are a game object's. Returns its ID when kept.
-- Not while PlateSmith fills the tooltip itself (ObjectHover's: paused), whose lines are not the game's.
function ObjectStatus.Capture(lines, data)
    if not ObjectStatus.capturing or ObjectStatus.paused or type(lines) ~= "table" then return nil end
    local name = lines[1] or nil
    local id = ObjectID(data, name)
    if not id then return nil end
    local rest = {}
    for index = 2, #lines do
        if lines[index] then rest[#rest + 1] = lines[index] end
    end
    if ObjectStatus.Store(id, rest) and ObjectStatus.Changed then ObjectStatus.Changed(id) end
    return id
end

-- Hooks the game's tooltip once, the first time the capture is wanted: an object tooltip's post call where the client
-- has TooltipDataProcessor, else GameTooltip's OnShow (with the world cursor's data where C_TooltipInfo has it). The
-- hooks stay; they do nothing while capturing is off.
local hooked = false
function ObjectStatus.Hook()
    if hooked then return true end
    local processor = rawget(_G, "TooltipDataProcessor")
    local kinds = rawget(_G, "Enum") and Enum.TooltipDataType
    local tooltip = rawget(_G, "GameTooltip")
    if type(processor) == "table" and type(processor.AddTooltipPostCall) == "function" and type(kinds) == "table"
        and kinds.Object ~= nil then
        hooked = pcall(processor.AddTooltipPostCall, kinds.Object, function(frame, data)
            if frame == rawget(_G, "GameTooltip") then pcall(ObjectStatus.Capture, DataLines(data), data) end
        end)
    elseif type(tooltip) == "table" and type(tooltip.HookScript) == "function" then
        hooked = pcall(tooltip.HookScript, tooltip, "OnShow", function(frame)
            if not ObjectStatus.capturing then return end
            local info = rawget(_G, "C_TooltipInfo")
            local data
            if type(info) == "table" and type(info.GetWorldCursor) == "function" then
                local ok, value = pcall(info.GetWorldCursor)
                if ok and IsReadable(value) and type(value) == "table" then data = value end
            end
            pcall(ObjectStatus.Capture, data and DataLines(data) or FrameLines(frame), data)
        end)
    end
    return hooked
end

-- A plate's own text colour under rules (Styles.RuleColour): written now, or kept as the colour a rule's goes back to.
local function OwnTextColour(region, colour)
    if region.plateSmithRuleColour then
        local base = region.plateSmithBaseColour or region.plateSmithBaseSpare or {}
        base[1], base[2], base[3] = colour[1], colour[2], colour[3]
        region.plateSmithBaseColour = base
    else
        region:SetTextColor(colour[1], colour[2], colour[3])
    end
end

-- The plate side. context: active, RunBatch, MarkStacks, MarkValues, Styles, AnchorPart, ApplyNameplateFont, EntryID
-- (the plate's readable object ID; after it, data.entryGUID is its GUID), ObjectFade (Fade objects you can't use
-- again). The part's text is made the first time a plate shows it; the capture, the skill and Cultivation events run
-- only while a layout of the Objects (or a type's) shows the part, a rule there reads its facts, or objects fade.
PS._CreatePlateObjectStatus = function(context)
    local active, RunBatch, MarkStacks, MarkValues = context.active, context.RunBatch, context.MarkStacks, context.MarkValues
    local Styles, AnchorPart, EntryID, ObjectFade = context.Styles, context.AnchorPart, context.EntryID, context.ObjectFade
    local Pass = { wanted = false, listening = false, cooldowns = false, ticking = false, stamp = nil }
    local events = CreateFrame("Frame")
    Pass.events = events

    local function PartShown(data)
        local position = data.layout and data.layout.statusText
        return position ~= nil and not S.TurnedOff(position)
    end

    local function FontSize(data)
        return S.PartTextSize("statusText", data.profile and data.profile.nameFontSize)
    end

    local function Ensure(data)
        if data.statusText then return data.statusText end
        local layer = CreateFrame("Frame", nil, data.overlay)
        layer:SetAllPoints(data.overlay)
        data.layerFrames.statusText = layer
        local text = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:Hide()
        data.statusText = text
        Styles.StyledFont(data, "statusText", text, FontSize(data))
        Styles.StyledBox(data, "statusText", text)
        if data.layout and data.layout.statusText then AnchorPart(data, text, "statusText") end
        layer:SetFrameLevel(Styles.LayerLevel(data, "statusText"))
        data.stackStatesFor = nil
        MarkStacks(data)
        return text
    end

    -- The plate's text from what is known now; only a change marks its stacks.
    local function Refresh(data)
        local region = data.statusText
        if not region then return end
        local text, colour
        if Pass.wanted and data.object and PartShown(data) then
            local id = EntryID(data)
            text, colour = ObjectStatus.Text(id, data.objectUnable, data.objectKind, id and data.entryGUID)
        end
        if text then
            if region.plateSmithStatus ~= text then
                region:SetText(text)
                region.plateSmithStatus = text
                MarkStacks(data)
            end
            if region.plateSmithStatusColour ~= colour then
                region.plateSmithStatusColour = colour
                OwnTextColour(region, ObjectStatus.COLOURS[colour])
            end
        end
        local shown = text ~= nil
        if (region:IsShown() and true or false) ~= shown then
            region:SetShown(shown)
            MarkStacks(data)
        end
    end
    Pass.Refresh = Refresh

    local function Herb(data)
        return data.object == true and ObjectStatus.IsHerb(EntryID(data), data.objectKind) == true
    end

    local function HerbsUp()
        for unit, data in pairs(active) do
            if data.unit == unit and Herb(data) then return true end
        end
        return false
    end

    -- SPELL_UPDATE_COOLDOWN comes with every global cooldown, so it is listened to only while you know Cultivation
    -- and a herb plate is up: a herb plate laid out turns it on, the first event or ticker pass with none off.
    local function Cooldowns(on)
        on = on and Pass.listening or false
        if on == Pass.cooldowns then return end
        Pass.cooldowns = on
        if on then
            PS._RegisterEvent(events, "SPELL_UPDATE_COOLDOWN", "platesmith.object-status")
        elseif type(events.UnregisterEvent) == "function" then
            pcall(events.UnregisterEvent, events, "SPELL_UPDATE_COOLDOWN")
        end
    end

    -- Cultivation's ticker entry: on while you know it and it is cooling down with a herb plate up; each pass a herb's
    -- text and facts follow when the minutes left change. It sleeps otherwise, woken by a herb plate laid out or the
    -- spell's cooldown changing while one is up (Pass.cooldowns).
    local function Wake()
        if Pass.wanted and Pass.cooldowns and not Pass.ticking and Cultivation.Stamp() > 0 then
            Pass.ticking = true
            PS.Ticker.SetEnabled(Cultivation.TICKER, true)
        end
    end
    local function Sleep()
        if Pass.ticking then
            Pass.ticking = false
            PS.Ticker.SetEnabled(Cultivation.TICKER, false)
        end
    end

    -- Every herb plate reads its text and facts again, and fades or not; true when there is one.
    local function FollowHerbs()
        local any = false
        for unit, data in pairs(active) do
            if data.unit == unit and Herb(data) then
                any = true
                Refresh(data)
                MarkValues(data, "object")
                if ObjectFade then ObjectFade(data) end
            end
        end
        return any
    end

    -- What Cultivation shows changed (stamp: Cultivation.Stamp), or force: herb plates follow.
    local function CultivationChanged(force)
        local stamp = Cultivation.Stamp()
        if not force and stamp == Pass.stamp then return end
        Pass.stamp = stamp
        RunBatch(false, FollowHerbs)
    end

    function Pass.CultivationTick()
        local herbs = false
        for unit, data in pairs(active) do
            if data.unit == unit and Herb(data) then
                herbs = true
                break
            end
        end
        if not herbs then Cooldowns(false) end
        local stamp = Cultivation.Stamp()
        if not herbs or stamp <= 0 then Sleep() end
        if herbs and stamp ~= Pass.stamp then
            Pass.stamp = stamp
            FollowHerbs()
        end
    end
    PS.Ticker.Register(Cultivation.TICKER, Cultivation.INTERVAL, function() RunBatch(false, Pass.CultivationTick) end)
    PS.Ticker.SetEnabled(Cultivation.TICKER, false)

    -- A plate was laid out (after its Action icon read Can't use): its text made, placed and shown, or hidden.
    function Pass.Update(data)
        if Pass.wanted and Herb(data) then
            Cooldowns(true)
            Wake()
        end
        if Pass.wanted and data.object and data.own and PartShown(data) then
            ObjectStatus.Seen(EntryID(data))
            Ensure(data)
            Refresh(data)
        elseif data.statusText and data.statusText:IsShown() then
            data.statusText:Hide()
            MarkStacks(data)
        end
    end

    function Pass.ApplyAppearance(data)
        if not data.statusText then return end
        Styles.StyledFont(data, "statusText", data.statusText, FontSize(data))
        Styles.StyledBox(data, "statusText", data.statusText)
        data.statusText.plateSmithStatusColour = nil
    end

    function Pass.Release(data)
        if data.statusText then data.statusText:Hide() end
    end

    -- Every object plate (with id: of that object) reads its text and facts again, and fades or not.
    local function Follow(id)
        for unit, data in pairs(active) do
            if data.unit == unit and data.object and (id == nil or EntryID(data) == id) then
                Refresh(data)
                MarkValues(data, "object")
                if ObjectFade then ObjectFade(data) end
            end
        end
    end
    ObjectStatus.Changed = function(id) RunBatch(false, Follow, id) end

    local function Unregister(event)
        if type(events.UnregisterEvent) == "function" then pcall(events.UnregisterEvent, events, event) end
    end
    -- Cultivation's cooldown and casts are listened to only while you know it (a player's own casts, by unit where
    -- the client can filter).
    local function Listen()
        local listening = Pass.wanted and Cultivation.Known() == true
        if listening == Pass.listening then return end
        Pass.listening = listening
        -- SPELL_UPDATE_COOLDOWN is Cooldowns'.
        for _, event in ipairs(Cultivation.EVENTS) do
            if event == "SPELL_UPDATE_COOLDOWN" then
                Cooldowns(listening and HerbsUp())
            elseif not listening then
                Unregister(event)
            elseif not (type(events.RegisterUnitEvent) == "function"
                and pcall(events.RegisterUnitEvent, events, event, "player")) then
                PS._RegisterEvent(events, event, "platesmith.object-status")
            end
        end
    end

    events:SetScript("OnEvent", function(_, event, unit, _, third, fourth)
        if event == Cultivation.KNOWN_EVENT then
            Cultivation.Forget()
            Listen()
            return CultivationChanged(true)
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            if not HerbsUp() then return Cooldowns(false) end
            CultivationChanged(false)
            return Wake()
        elseif event == "UNIT_SPELLCAST_SENT" then
            -- unit, target's name, cast GUID, spell
            if Cultivation.Mine(unit, fourth) then Cultivation.Aim() end
            return
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- unit, cast GUID, spell
            if Cultivation.Mine(unit, third) and Cultivation.Succeeded() then
                CultivationChanged(true)
                Wake()
            end
            return
        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            if Cultivation.Mine(unit, third) then Cultivation.ChannelUpdated() end
            return
        elseif event == "PLAYER_LEVEL_UP" then
            -- The new level comes first; UnitLevel may still say the old one.
            Cultivation.LevelUp(unit)
            return RunBatch(false, Follow, nil)
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if Cultivation.Mine(unit, third) and Cultivation.ChannelStopped() then
                CultivationChanged(true)
                Wake()
            end
            return
        end
        ObjectStatus.Forget()
        RunBatch(false, Follow, nil)
    end)

    -- On while a layout shows the part, a rule reads its facts or objects fade (Schema.StatusNeeded). Off: no capture,
    -- no events, no ticker.
    function Pass.SetWanted(wanted)
        wanted = wanted and true or false
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        ObjectStatus.capturing = wanted
        if wanted then ObjectStatus.Hook() end
        for _, event in ipairs(ObjectStatus.EVENTS) do
            if wanted then
                PS._RegisterEvent(events, event, "platesmith.object-status")
            else
                Unregister(event)
            end
        end
        if wanted then
            PS._RegisterEvent(events, Cultivation.KNOWN_EVENT, "platesmith.object-status")
            ObjectStatus.Forget()
            Cultivation.Forget()
            Pass.stamp = Cultivation.Stamp()
        else
            Unregister(Cultivation.KNOWN_EVENT)
            Sleep()
        end
        Listen()
    end

    ObjectStatus._pass = Pass
    return Pass
end

-- For /ps diagnose (context.objectStatus): whether it runs, the hook, how many objects are kept and your skills
-- counted (never their names or the lines), and Cultivation's state (Cultivation.Report).
function ObjectStatus.Report()
    local pass = ObjectStatus._pass
    local cache = Cache(false)
    local count = 0
    for _ in pairs(skills or {}) do count = count + 1 end
    return { wanted = pass ~= nil and pass.wanted or false, hooked = hooked, kept = cache and #cache.order or 0,
        skills = skills and count or "unread", cultivation = Cultivation.Report() }
end
