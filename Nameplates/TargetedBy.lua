-- "Targeted by" badges on enemy plates: one class-coloured badge per group member (party1..party4;
-- in a raid its tanks, up to four), shown while that member targets the plate's unit. Whether they
-- do is UnitIsUnit("<member>target", plate unit), which Forever may protect: the answer goes
-- straight to each badge region's SetAlphaFromBoolean and Lua never compares or tests it. A
-- readable answer is used as it is; with no such sink a protected answer keeps the badge hidden.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local IsReadable, IsSecret, ReadBoolean = Secret.IsReadable, Secret.IsSecret, Secret.ReadBoolean

local TargetedBy = {}
PS.TargetedBy = TargetedBy
TargetedBy.MAX = 4
TargetedBy.TICKER = "plates.targetedBy"
-- The backstop re-reads at most this many plates' badges each pass, from a rolling cursor.
TargetedBy.INTERVAL, TargetedBy.BUDGET = 0.5, 8
local MAX, EMPTY = TargetedBy.MAX, {}
local FALLBACK_COLOUR = { 0.6, 0.6, 0.6 }
local ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD" }
local GROUP_EVENTS = { "UNIT_TARGET", "PLAYER_TARGET_CHANGED" }

local PARTY_TOKENS, RAID_TOKENS, TARGET_TOKENS = {}, {}, {}
for index = 1, 4 do PARTY_TOKENS[index] = "party" .. index end
for index = 1, 40 do RAID_TOKENS[index] = "raid" .. index end

-- The style's size, spacing, whether the row runs down, and whether badges show initials.
function TargetedBy.StyleOf(style)
    local defaults = S.STYLE_DEFAULTS
    style = style or EMPTY
    return style.badgeSize or defaults.badgeSize, style.badgeSpacing or defaults.badgeSpacing,
        (style.badgeOrientation or defaults.badgeOrientation) == "vertical", style.badgeInitial ~= false
end

-- The row's size for count badges (at least one, so a pinned part keeps a place to meet).
function TargetedBy.RowSize(count, size, spacing, vertical)
    count = math.max(1, count)
    local long = count * size + (count - 1) * spacing
    if vertical then return size, long end
    return long, size
end

-- Badge index's top-left corner in the row (x right, y down).
function TargetedBy.BadgeOffset(index, size, spacing, vertical)
    local along = (index - 1) * (size + spacing)
    if vertical then return 0, along end
    return along, 0
end

function TargetedBy.InitialFontSize(size) return math.max(6, math.floor(size - 2)) end

-- Shows or hides one badge's regions by a UnitIsUnit answer: a readable boolean directly, a
-- protected one only through SetAlphaFromBoolean (every region must have it, else all stay
-- hidden). Returns how: "readable", "sink" or "hidden".
function TargetedBy.ApplyVisibility(regions, value)
    if IsReadable(value) then
        local alpha = (value == true) and 1 or 0
        for index = 1, #regions do regions[index]:SetAlpha(alpha) end
        return "readable"
    end
    for index = 1, #regions do
        local sink = regions[index].SetAlphaFromBoolean
        if type(sink) ~= "function" or not pcall(sink, regions[index], value, 1, 0) then
            for other = 1, #regions do regions[other]:SetAlpha(0) end
            return "hidden"
        end
    end
    return "sink"
end

-- A readable name's first character (a whole UTF-8 sequence), upper-cased; nil otherwise.
local function Initial(unit)
    if type(UnitName) ~= "function" then return nil end
    local ok, name = pcall(UnitName, unit)
    if not ok or not IsReadable(name) or type(name) ~= "string" then return nil end
    local first = name:match("^[\1-\127\194-\244][\128-\191]*")
    return first and first:upper() or nil
end


local function IsTank(unit)
    if type(UnitGroupRolesAssigned) == "function" then
        local ok, role = pcall(UnitGroupRolesAssigned, unit)
        if ok and IsReadable(role) and role == "TANK" then return true end
    end
    return type(GetPartyAssignment) == "function" and ReadBoolean(GetPartyAssignment, "MAINTANK", unit) == true
end

-- The members badges are drawn for: a party's party1..party4, or a raid's tanks (up to MAX, never
-- the player). members[i] = { unit, targetToken, r, g, b (readable) or classFile (opaque), initial }.
local members, memberIndex = {}, {}
-- Bumped by every rebuild: a plate's row drawn for an older roster is styled again.
TargetedBy.revision = 0
local function RebuildMembers()
    TargetedBy.revision = TargetedBy.revision + 1
    for unit in pairs(memberIndex) do memberIndex[unit] = nil end
    local count = 0
    local function Add(unit)
        count = count + 1
        local member = members[count] or {}
        members[count] = member
        TARGET_TOKENS[unit] = TARGET_TOKENS[unit] or Secret.TargetToken(unit)
        member.unit, member.targetToken, member.initial = unit, TARGET_TOKENS[unit], Initial(unit)
        -- classOpaque: the class is protected; classFile is then only ever passed to the colour sink.
        member.r, member.g, member.b, member.classFile, member.classOpaque = nil, nil, nil, nil, false
        local classFile, has = Secret.ClassFile(unit)
        if has and IsReadable(classFile) and type(classFile) == "string" then
            member.r, member.g, member.b = Secret.ClassColour(classFile)
        elseif has then
            member.classFile, member.classOpaque = classFile, true
        end
        memberIndex[unit] = count
    end
    local inRaid = type(IsInRaid) == "function" and ReadBoolean(IsInRaid) == true
    if inRaid then
        local ok, total = false, nil
        if type(GetNumGroupMembers) == "function" then ok, total = pcall(GetNumGroupMembers) end
        total = ok and IsReadable(total) and type(total) == "number" and math.min(40, total) or 0
        for index = 1, total do
            local unit = RAID_TOKENS[index]
            if count >= MAX then break end
            if not Secret.SameUnit(unit, "player") and IsTank(unit) then Add(unit) end
        end
    else
        local ok, total = false, nil
        if type(GetNumSubgroupMembers) == "function" then ok, total = pcall(GetNumSubgroupMembers) end
        total = ok and IsReadable(total) and type(total) == "number" and math.min(MAX, total) or 0
        for index = 1, total do Add(PARTY_TOKENS[index]) end
    end
    for index = count + 1, #members do members[index] = nil end
    TargetedBy.raid = inRaid
    return count
end

-- For tests: forget the roster.
function TargetedBy._Reset()
    for index = #members, 1, -1 do members[index] = nil end
    for unit in pairs(memberIndex) do memberIndex[unit] = nil end
end

-- The plate side. context: active (unit -> plate), RunBatch, MarkStacks, Styles, AnchorPart
-- (Placement). A plate's row is made the first time it shows, events are
-- registered only while an enemy layout shows the part (SetWanted), and the group events and the
-- backstop run only while grouped as well.
PS._CreatePlateTargetedBy = function(context)
    local active, RunBatch, MarkStacks = context.active, context.RunBatch, context.MarkStacks
    local Styles, AnchorPart = context.Styles, context.AnchorPart
    local Pass = { wanted = false, grouped = false, rosterDirty = false, ticking = false, cursor = 0 }
    -- Plates showing a row, in a round-robin list (each keeps its index as targetedByIndex).
    local rows = {}
    Pass.rows, Pass.active = rows, active

    local function ListSet(data, wanted)
        local index = data.targetedByIndex
        if wanted then
            if not index then
                rows[#rows + 1] = data
                data.targetedByIndex = #rows
            end
        elseif index then
            local last = rows[#rows]
            rows[index], last.targetedByIndex = last, index
            rows[#rows] = nil
            data.targetedByIndex = nil
        end
    end

    local function PartStyle(data)
        local styles = data.profile and data.profile.styles
        return styles and styles.targetedBy or EMPTY
    end

    -- Sizes, places and colours every badge for the roster; the row is as long as the members.
    local function ApplyStyle(data)
        local size, spacing, vertical, initials = TargetedBy.StyleOf(PartStyle(data))
        local count = #members
        data.targetedBy:SetSize(TargetedBy.RowSize(count, size, spacing, vertical))
        for index, badge in ipairs(data.targetedByBadges) do
            local member = members[index]
            local x, y = TargetedBy.BadgeOffset(index, size, spacing, vertical)
            badge.edge:ClearAllPoints()
            badge.edge:SetPoint("TOPLEFT", data.targetedBy, "TOPLEFT", x, -y)
            badge.edge:SetSize(size, size)
            badge.edge:SetColorTexture(0, 0, 0, 0.9)
            badge.fill:SetColorTexture(1, 1, 1, 1)
            local used = member ~= nil
            if used then
                -- A protected class goes through the client's colour sink; nothing readable is grey.
                local r, g, b = member.r, member.g, member.b
                if not r and not (member.classOpaque and Secret.SetClassColour(badge.fill, member.classFile, "SetVertexColor")) then
                    r, g, b = FALLBACK_COLOUR[1], FALLBACK_COLOUR[2], FALLBACK_COLOUR[3]
                end
                if r then badge.fill:SetVertexColor(r, g, b) end
                Styles.StyledFont(data, "targetedBy", badge.text, TargetedBy.InitialFontSize(size))
                badge.text:SetText(member.initial or "")
                badge.text:SetTextColor(0, 0, 0)
            end
            badge.edge:SetShown(used)
            badge.fill:SetShown(used)
            badge.text:SetShown(used and initials and member.initial ~= nil)
        end
        data.targetedByRevision = TargetedBy.revision
    end

    local function Ensure(data)
        if data.targetedBy then return data.targetedBy end
        local layer = CreateFrame("Frame", nil, data.overlay)
        layer:SetAllPoints(data.overlay)
        data.layerFrames.targetedBy = layer
        local frame = CreateFrame("Frame", nil, layer)
        frame:Hide()
        local badges = {}
        for index = 1, MAX do
            local badge = { edge = frame:CreateTexture(nil, "BORDER"), fill = frame:CreateTexture(nil, "ARTWORK"),
                text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
            badge.fill:SetPoint("TOPLEFT", badge.edge, "TOPLEFT", 1, -1)
            badge.fill:SetPoint("BOTTOMRIGHT", badge.edge, "BOTTOMRIGHT", -1, 1)
            badge.text:SetPoint("CENTER", badge.edge, "CENTER", 0, 0)
            -- The regions one answer shows or hides together.
            badge.regions = { badge.edge, badge.fill, badge.text }
            badges[index] = badge
        end
        data.targetedBy, data.targetedByBadges = frame, badges
        ApplyStyle(data)
        AnchorPart(data, frame, "targetedBy")
        layer:SetFrameLevel(Styles.LayerLevel(data, "targetedBy"))
        data.stackStatesFor = nil
        MarkStacks(data)
        return frame
    end

    -- One member's badge on one plate: the answer goes to the badges' sinks, never into Lua logic.
    local function RefreshBadge(data, index)
        local member, badge = members[index], data.targetedByBadges[index]
        if not member then return end
        if type(UnitIsUnit) ~= "function" then
            TargetedBy.ApplyVisibility(badge.regions, false)
            return
        end
        local ok, same = pcall(UnitIsUnit, member.targetToken, data.unit)
        if not ok then same = false end
        TargetedBy.ApplyVisibility(badge.regions, same)
    end

    local function RefreshPlate(data)
        for index = 1, #members do RefreshBadge(data, index) end
    end

    -- On your owned hostile plate, with the part on, while grouped.
    local function Wanted(data)
        local position = data.layout and data.layout.targetedBy
        return Pass.wanted and Pass.grouped and data.own == true and not data.namesOnly and data.friendly == false
            and position ~= nil and not S.TurnedOff(position)
    end

    -- A plate was laid out (or the roster changed): its row made, placed and re-read, or hidden.
    function Pass.Update(data)
        local shown = Wanted(data)
        if shown then
            Ensure(data)
            if data.targetedByRevision ~= TargetedBy.revision then
                ApplyStyle(data)
                data.stackStatesFor = nil
                MarkStacks(data)
            end
            RefreshPlate(data)
        end
        ListSet(data, shown)
        local frame = data.targetedBy
        if frame and (frame:IsShown() and true or false) ~= shown then
            frame:SetShown(shown)
            MarkStacks(data)
        end
    end

    -- Sizes and colours again after a settings change (ApplyAppearance).
    function Pass.ApplyAppearance(data)
        if data.targetedBy then ApplyStyle(data) end
    end

    function Pass.Release(data)
        if data.targetedBy then data.targetedBy:Hide() end
        ListSet(data, false)
    end

    local function EachActive(fn)
        for _, data in pairs(active) do fn(data) end
    end

    local function RefreshRows()
        for index = 1, #rows do RefreshPlate(rows[index]) end
    end

    local events = CreateFrame("Frame")
    Pass.events = events
    local function Listen(list, on)
        for _, event in ipairs(list) do
            if on then
                PS._RegisterEvent(events, event, "platesmith.targeted-by")
            elseif type(events.UnregisterEvent) == "function" then
                events:UnregisterEvent(event)
            end
        end
    end

    -- The group events and the backstop follow wanted and grouped; a roster change is read on the
    -- next frame (the ticker entry runs once at once), so a burst of roster events rebuilds once.
    local groupListening = false
    local function Sync()
        local grouped = Pass.wanted and Pass.grouped
        if grouped ~= groupListening then
            groupListening = grouped
            Listen(GROUP_EVENTS, grouped)
        end
        local ticking = Pass.wanted and (Pass.grouped or Pass.rosterDirty)
        PS.Ticker.SetInterval(TargetedBy.TICKER, Pass.rosterDirty and 0 or TargetedBy.INTERVAL)
        -- Enabling again would restart the entry's wait, so only a change is written.
        if ticking ~= Pass.ticking then
            Pass.ticking = ticking
            PS.Ticker.SetEnabled(TargetedBy.TICKER, ticking)
        end
    end

    function Pass.RebuildRoster()
        Pass.rosterDirty = false
        Pass.grouped = Pass.wanted and RebuildMembers() > 0
        Sync()
        EachActive(Pass.Update)
    end

    local function MarkRosterDirty()
        if Pass.rosterDirty then return end
        Pass.rosterDirty = true
        Sync()
    end

    -- The backstop: a missed UNIT_TARGET cannot leave a badge wrong for long.
    function Pass.Tick()
        if Pass.rosterDirty then return Pass.RebuildRoster() end
        local count = #rows
        for _ = 1, math.min(TargetedBy.BUDGET, count) do
            Pass.cursor = Pass.cursor % #rows + 1
            RefreshPlate(rows[Pass.cursor])
        end
    end
    PS.Ticker.Register(TargetedBy.TICKER, TargetedBy.INTERVAL, function() RunBatch(false, Pass.Tick) end)
    PS.Ticker.SetEnabled(TargetedBy.TICKER, false)

    local function OnUnitTarget(unit)
        if not (IsReadable(unit) and type(unit) == "string") then return end
        local index = memberIndex[unit]
        if index then
            for row = 1, #rows do RefreshBadge(rows[row], index) end
            return
        end
        local data = active[unit]
        if type(data) == "table" and data.targetedByIndex then RefreshPlate(data) end
    end

    events:SetScript("OnEvent", function(_, event, unit)
        if not Pass.wanted then return end
        if event == "UNIT_TARGET" then
            OnUnitTarget(unit)
        elseif event == "PLAYER_TARGET_CHANGED" then
            RefreshRows()
        else
            MarkRosterDirty()
        end
    end)

    -- On while an enemy layout shows the part. Off: no events, no ticker, every row hidden.
    function Pass.SetWanted(wanted)
        wanted = wanted and true or false
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        Listen(ROSTER_EVENTS, wanted)
        if wanted then
            Pass.RebuildRoster()
        else
            Pass.grouped, Pass.rosterDirty = false, false
            Sync()
            for index = #rows, 1, -1 do Pass.Release(rows[index]) end
        end
    end

    Pass.Members = function() return members end
    TargetedBy._pass = Pass
    return Pass
end

-- What each comparison gave, for /ps diagnose: readable, protected/displayable (a protected answer
-- the badge's sink takes), protected (no sink: hidden), error or api-missing. Never reads a value.
local function ComparisonState(member, unit, sink)
    if type(UnitIsUnit) ~= "function" then return "api-missing" end
    local ok, same = pcall(UnitIsUnit, member.targetToken, unit)
    if not ok then return "error" end
    if IsReadable(same) then return "readable" end
    if IsSecret(same) and sink then return "protected/displayable" end
    return "protected"
end

-- For /ps diagnose (targetedBy): the part's state, the members, and for your target's plate and up
-- to four engaged plates, each member's comparison. Built on demand, never on the tick.
function TargetedBy.Report()
    local Array = PS.Json and PS.Json.Array or function() return {} end
    local pass = TargetedBy._pass
    local report = {
        wanted = pass ~= nil and pass.wanted or false, grouped = pass ~= nil and pass.grouped or false,
        raid = TargetedBy.raid == true, rows = pass and #pass.rows or 0, members = Array(), plates = Array(),
    }
    for _, member in ipairs(members) do
        report.members[#report.members + 1] = {
            unit = member.unit, colour = member.r and "readable" or (member.classOpaque and "protected" or "none"),
            initial = member.initial ~= nil,
        }
    end
    if not pass or #members == 0 then return report end
    local service, active = PS.ThreatService, pass.active
    local picked = {}
    local function Pick(unit, data, role)
        if #report.plates >= 5 or picked[unit] then return end
        picked[unit] = true
        local badge = data and data.targetedByBadges and data.targetedByBadges[1]
        local sink = badge ~= nil and type(badge.edge.SetAlphaFromBoolean) == "function"
        local entry = { unit = unit, role = role, row = data ~= nil and data.targetedByIndex ~= nil, sink = sink,
            members = Array() }
        for _, member in ipairs(members) do
            entry.members[#entry.members + 1] = { unit = member.unit, comparison = ComparisonState(member, unit, sink) }
        end
        report.plates[#report.plates + 1] = entry
    end
    for unit, data in pairs(active) do
        if data.targeted == true and data.friendly == false then Pick(unit, data, "target") end
    end
    local order = service and service.enemyOrder or EMPTY
    for index = 1, service and service.enemyCount or 0 do
        local record = order[index]
        if record and record.unit and record.engaged then Pick(record.unit, active[record.unit], "engaged") end
    end
    return report
end
