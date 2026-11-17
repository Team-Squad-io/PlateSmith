-- Threat breakdown (a built-in module, "platesmith.threat-breakdown"): the player's own threat per pull, estimated
-- from what the client lets an addon read, beside the game's own figure where it is readable. A pull runs from
-- PLAYER_REGEN_DISABLED to PLAYER_REGEN_ENABLED; during it the player's casts (UNIT_SPELLCAST_SUCCEEDED) are counted
-- and the threat service's records give the game's threat on each mob (the highest readable, every TICK seconds).
-- After it, Blizzard's damage meter gives the player's damage per spell and damage taken (secret in combat; read at
-- READ_AFTER seconds until readable). ThreatModel turns those into the estimate. Nothing reads the combat log.
-- The last MAX_PULLS are kept for the session. The window (a threat window's title menu, or Settings) lists them,
-- each named by its main mob; the one picked shows a bar per ability (threat, share, per second; the working in its
-- tooltip), then the rage and the stat sheet (armor, attack power).
local _, PS = ...
if not PS or type(PS.RegisterModule) ~= "function" then return end
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Model = assert(PS.ThreatModel, "PlateSmith ThreatModel missing")
local Format = assert(PS.Format, "PlateSmith Format missing")
local Number, Text = Secret.Number, Secret.String

-- MAX_PULLS pulls are kept besides the ones you keep (at most MAX_KEPT), REPLAYS of them with their group replay; all
-- of it this character's, across sessions (PlateSmithThreatDB).
local Breakdown = { version = 1, apiMin = 1, apiMax = 1, pulls = {}, pull = nil, MAX_PULLS = 30, MAX_KEPT = 20, REPLAYS = 15,
    READ_AFTER = { 1, 3, 6, 10 }, TICK = 0.5, TICKER = "threat.breakdown", MAX_SAMPLES = 1200, REPLAY_LINES = 8,
    MAX_CASTS = 400, RECENT_CASTS = 4, MAX_SOURCES = 40, MERGE_GAP = 5,
    REPLAY_TICKER = "threat.breakdown.replay" }
PS.ThreatBreakdown = Breakdown

local function Now() return type(GetTime) == "function" and GetTime() or 0 end

-- fn's results, or nothing when it is missing or fails.
local function Results(ok, ...)
    if not ok then return nil end
    return ...
end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Results(pcall(fn, ...))
end

-- A spell's name (readable), else nil.
local function SpellName(spellID)
    spellID = Number(spellID)
    if not spellID then return nil end
    local spell = rawget(_G, "C_Spell")
    local name = spell and Read(spell.GetSpellName, spellID)
    if not Text(name) and type(GetSpellInfo) == "function" then name = Read(GetSpellInfo, spellID) end
    return Text(name)
end

-- The player's form as ThreatModel knows it (bear, cat), from the threat service's reading: its form ("bear") or,
-- for a form that is not a tank's, its word ("cat").
local function PlayerForm()
    local service = PS.ThreatService
    if not (service and type(service.ReadPlayerForm) == "function") then return nil end
    local ok, form, _, word = pcall(service.ReadPlayerForm, service, service:PlayerClass())
    if not ok then return nil end
    if form == "bear" then return "bear" end
    return word == "cat" and "cat" or nil
end

-- Your target's name when it is something you can attack (a corpse too) and the client lets the name be read, else
-- nil. Forever withholds creature names in combat, so the pull's name comes from the target just before it (the
-- last one picked out of combat, Breakdown.lastFoe) or after it (the corpse you are still targeting).
local function FoeName()
    if Read(UnitCanAttack, "player", "target") ~= true then return nil end
    return Secret.ReadName("target")
end

-- ------------------------------------------------------------------ the damage meter, after the pull

-- The player's source in the current session for the meter type named kind ("DamageDone", "DamageTaken"), or nil.
local function MeterSource(kind)
    local meter, enum = rawget(_G, "C_DamageMeter"), rawget(_G, "Enum")
    local sessions, types = enum and enum.DamageMeterSessionType, enum and enum.DamageMeterType
    if not (meter and sessions and types and type(meter.GetCombatSessionSourceFromType) == "function") then return nil end
    local guid = Text(Read(UnitGUID, "player"))
    if not (guid and sessions.Current ~= nil and types[kind] ~= nil) then return nil end
    return Read(meter.GetCombatSessionSourceFromType, sessions.Current, types[kind], guid)
end

-- The player's damage per spell name and in all, from the meter: nil while any of it is secret (so a partial
-- answer never passes for a whole one).
function Breakdown.ReadDamage(source)
    if type(source) ~= "table" or not Secret.IsReadable(source) then return nil end
    local spells = source.combatSpells
    if not (Secret.IsReadable(spells) and type(spells) == "table") then return nil end
    local damage = {}
    for _, spell in ipairs(spells) do
        local amount = Secret.IsReadable(spell) and type(spell) == "table" and Number(spell.totalAmount)
        if not amount then return nil end
        local id = Number(spell.spellID)
        local name = SpellName(id) or (id and string.format(L["Spell %d"], id)) or L["Unknown"]
        damage[name] = (damage[name] or 0) + amount
    end
    return damage, Number(source.totalAmount)
end

-- The meter's current session for kind (every source in it), or nil.
local function MeterSession(kind)
    local meter, enum = rawget(_G, "C_DamageMeter"), rawget(_G, "Enum")
    local sessions, types = enum and enum.DamageMeterSessionType, enum and enum.DamageMeterType
    if not (meter and sessions and types and type(meter.GetCombatSessionFromType) == "function") then return nil end
    if sessions.Current == nil or types[kind] == nil then return nil end
    return Read(meter.GetCombatSessionFromType, sessions.Current, types[kind])
end

-- Everyone's damage in the session (the group's, from the meter after the pull), highest first: name (realm cut),
-- class, amount, isPlayer (the meter's isLocalPlayer). nil while any name or amount is secret, so a part of the
-- group never passes for all of it; at most MAX_SOURCES.
function Breakdown.ReadGroupDamage(session)
    if type(session) ~= "table" or not Secret.IsReadable(session) then return nil end
    local sources = session.combatSources
    if not (Secret.IsReadable(sources) and type(sources) == "table") then return nil end
    local rows = {}
    for index, source in ipairs(sources) do
        if index > Breakdown.MAX_SOURCES then break end
        if not (Secret.IsReadable(source) and type(source) == "table") then return nil end
        local name, amount = Text(source.name), Number(source.totalAmount)
        if not (name and amount) then return nil end
        rows[#rows + 1] = { name = name:match("^[^-]+") or name, class = Text(source.classFilename),
            amount = amount, isPlayer = source.isLocalPlayer == true or nil }
    end
    if #rows == 0 then return nil end
    table.sort(rows, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.name < b.name
    end)
    return rows
end

-- The damage meter's name for its newest session (the game names a fight after an enemy in it), when readable. In
-- instances the game withholds every creature's name and GUID from addons, so this may be the only name a pull gets.
function Breakdown.SessionName()
    local meter = rawget(_G, "C_DamageMeter")
    if not (meter and type(meter.GetAvailableCombatSessions) == "function") then return nil end
    local sessions = Read(meter.GetAvailableCombatSessions)
    if not (Secret.IsReadable(sessions) and type(sessions) == "table") then return nil end
    local newestID, newestName
    for _, session in ipairs(sessions) do
        local id = Secret.IsReadable(session) and type(session) == "table" and Number(session.sessionID)
        if id and (not newestID or id > newestID) then newestID, newestName = id, Text(session.name) end
    end
    return newestName ~= "" and newestName or nil
end

function Breakdown:ReadMeter(pull)
    local damage, done = Breakdown.ReadDamage(MeterSource("DamageDone"))
    if not damage then return false end
    pull.damage, pull.done = damage, done
    pull.session = pull.session or Breakdown.SessionName()
    local taken = MeterSource("DamageTaken")
    pull.taken = type(taken) == "table" and Secret.IsReadable(taken) and Number(taken.totalAmount) or nil
    pull.groupDamage = Breakdown.ReadGroupDamage(MeterSession("DamageDone"))
    return true
end

-- A finished pull the meter read with nothing in it (no estimate, no damage of yours and no threat read: a mob
-- someone else killed, say), unless you keep it. An unread pull stays: its damage is not known to be none.
function Breakdown.Empty(pull)
    if pull.kept or not pull.damage then return false end
    if (Number(pull.done) or 0) > 0 or (Number(pull.gameThreat) or 0) > 0 then return false end
    return Model.Estimate(pull).total == 0
end

-- Whether later (just settled) carries on earlier: combat dropped for under MERGE_GAP seconds between them (a chain
-- of packs), in the same zone and form. Both started in this game session (their GetTime starts compare).
function Breakdown.Continues(earlier, later)
    if type(earlier) ~= "table" or type(later) ~= "table" or earlier == later then return false end
    if earlier.sample or later.sample or earlier.state == "reading" or later.state == "reading" then return false end
    if earlier.zone ~= later.zone or earlier.form ~= later.form then return false end
    local started, start, seconds = Number(later.started), Number(earlier.started), Number(earlier.seconds)
    if not (started and start and seconds) then return false end
    local gap = started - (start + seconds)
    return gap >= 0 and gap <= Breakdown.MERGE_GAP
end

local function AddCounts(into, from)
    for key, value in pairs(from or {}) do
        if type(value) == "number" then into[key] = (into[key] or 0) + value end
    end
end

-- A part with no meter read (its damage unknown): 1, else 0; a joined pull counts its own.
local function UnreadParts(pull)
    return pull.unreadParts or (pull.damage and 0 or 1)
end

-- Folds later into earlier (Continues): one pull from earlier's start to later's end, its counts and damage added,
-- the game's threat the higher, the casts and the group replay carried on at their time from earlier's start.
function Breakdown.Merge(into, from)
    local offset = from.started - into.started
    into.unreadParts = UnreadParts(into) + UnreadParts(from)
    into.parts = (into.parts or 1) + (from.parts or 1)
    into.seconds = offset + from.seconds
    into.casts = into.casts or {}
    AddCounts(into.casts, from.casts)
    if into.castLog and from.castLog then
        for _, cast in ipairs(from.castLog) do
            if #into.castLog >= Breakdown.MAX_CASTS then break end
            into.castLog[#into.castLog + 1] = { cast[1] + offset, cast[2] }
        end
    end
    if from.damage then
        into.damage = into.damage or {}
        AddCounts(into.damage, from.damage)
        into.done = (Number(into.done) or 0) + (Number(from.done) or 0)
    end
    if from.taken then into.taken = (Number(into.taken) or 0) + from.taken end
    into.threat, into.names = into.threat or {}, into.names or {}
    for guid, value in pairs(from.threat or {}) do into.threat[guid] = math.max(into.threat[guid] or 0, value) end
    for guid, name in pairs(from.names or {}) do if not into.names[guid] then into.names[guid] = name end end
    if from.gameThreat then into.gameThreat = math.max(into.gameThreat or 0, from.gameThreat) end
    into.drops = (into.drops or 0) + (from.drops or 0)
    if from.level then into.level = math.max(into.level or 0, from.level) end
    if from.enemyLevel then into.enemyLevel = math.max(into.enemyLevel or 0, from.enemyLevel) end
    into.target, into.session = into.target or from.target, into.session or from.session
    into.stats = into.stats or from.stats
    into.kept = (into.kept or from.kept) and true or nil
    if from.groupDamage then
        local byName, rows = {}, into.groupDamage or {}
        for _, row in ipairs(rows) do byName[row.name] = row end
        for _, row in ipairs(from.groupDamage) do
            local mine = byName[row.name]
            if mine then
                mine.amount, mine.isPlayer = mine.amount + row.amount, (mine.isPlayer or row.isPlayer) and true or nil
            elseif #rows < Breakdown.MAX_SOURCES then
                mine = { name = row.name, class = row.class, amount = row.amount, isPlayer = row.isPlayer }
                rows[#rows + 1], byName[row.name] = mine, mine
            end
        end
        table.sort(rows, function(a, b)
            if a.amount ~= b.amount then return a.amount > b.amount end
            return a.name < b.name
        end)
        into.groupDamage = rows
    end
    local group, more = into.group, from.group
    if group and more then
        local base = #group.times
        local count = math.min(#more.times, Breakdown.MAX_SAMPLES - base)
        if count < #more.times then group.cut = true end
        for index = 1, count do
            group.times[base + index] = more.times[index] + offset
            group.mobs[base + index] = more.mobs[index]
        end
        for _, key in ipairs(more.order) do
            local member, theirs = group.members[key], more.members[key]
            if not member then
                member = { name = theirs.name, class = theirs.class, isPlayer = theirs.isPlayer, raw = {}, tank = {} }
                group.members[key] = member
                group.order[#group.order + 1] = key
            end
            for index = 1, count do
                member.raw[base + index], member.tank[base + index] = theirs.raw[index], theirs.tank[index]
            end
        end
        group.hidden = ((group.hidden or 0) + (more.hidden or 0)) > 0 and (group.hidden or 0) + (more.hidden or 0) or nil
        group.cut = (group.cut or more.cut) and true or nil
    end
    into.state = into.damage and "read" or "unread"
    return into
end

-- pull is final: read when the meter read it, else unread. One carrying on the pull before it (Continues) joins it;
-- an empty one leaves the list.
function Breakdown:Settle(pull)
    pull.state = pull.damage and "read" or "unread"
    for index, each in ipairs(self.pulls) do
        if each == pull then
            local earlier = self.pulls[index + 1]
            if Breakdown.Continues(earlier, pull) then
                Breakdown.Merge(earlier, pull)
                table.remove(self.pulls, index)
                if self.selected == pull then self.selected = earlier ~= self.pulls[1] and earlier or nil end
                return self:Changed()
            end
            break
        end
    end
    if Breakdown.Empty(pull) then
        for index, each in ipairs(self.pulls) do
            if each == pull then
                table.remove(self.pulls, index)
                break
            end
        end
        if self.selected == pull then self.selected = nil end
    end
    return self:Changed()
end

-- Reads the meter at the next READ_AFTER step; the pull is final once it reads or the steps run out.
function Breakdown:ScheduleRead(pull, step)
    local delay = Breakdown.READ_AFTER[step]
    local timer = rawget(_G, "C_Timer")
    if not delay or not (timer and type(timer.After) == "function") then
        return self:Settle(pull)
    end
    local previous = step > 1 and Breakdown.READ_AFTER[step - 1] or 0
    timer.After(delay - previous, function()
        if pull.state ~= "reading" then return end
        if self:ReadMeter(pull) then
            self:Settle(pull)
        else
            self:ScheduleRead(pull, step + 1)
        end
    end)
end

-- ------------------------------------------------------------------ the pull

function Breakdown:StartPull()
    -- The meter's current session is the new pull's from now: an earlier pull still waiting to read it stops, unread,
    -- so it is never given this pull's damage.
    local waiting = {}
    for _, earlier in ipairs(self.pulls) do
        if earlier.state == "reading" then waiting[#waiting + 1] = earlier end
    end
    for _, earlier in ipairs(waiting) do self:Settle(earlier) end
    local level = Number(Read(UnitLevel, "player"))
    local enemy = Number(Read(UnitLevel, "target"))
    -- The target's name names the pull when no threat record gives the main mob's (an attackable target only); in
    -- combat it may be withheld already, so the one you picked just before stands in.
    local target = FoeName() or self.lastFoe
    self.pull = { started = Now(), form = PlayerForm(), level = level, enemyLevel = (enemy and enemy > 0) and enemy or nil,
        target = target, casts = {}, castLog = {}, threat = {}, names = {}, state = "fighting",
        when = Number(Read(rawget(_G, "time"))), zone = Text(Read(rawget(_G, "GetRealZoneText"))),
        group = { times = {}, mobs = {}, members = {}, order = {} } }
    self.lastThreat = {}
    PS.Ticker.SetEnabled(Breakdown.TICKER, true)
    Breakdown.WantGroup(true)
end

-- The threat service's group read (each member's threat on your target) runs while a pull is being recorded.
function Breakdown.WantGroup(wanted)
    local service = PS.ThreatService
    if service and type(service.SetGroupThreatWanted) == "function" then
        pcall(service.SetGroupThreatWanted, service, wanted, "breakdown")
    end
end

function Breakdown:EndPull()
    local pull = self.pull
    if not pull then return end
    self.pull = nil
    PS.Ticker.SetEnabled(Breakdown.TICKER, false)
    Breakdown.WantGroup(false)
    pull.seconds = math.max(0, Now() - pull.started)
    pull.form = pull.form or PlayerForm()
    -- Out of combat the name reads again: the corpse you are still targeting names a pull that had none.
    pull.target = pull.target or FoeName()
    local highest = 0
    for _, value in pairs(pull.threat) do highest = math.max(highest, value) end
    pull.gameThreat = highest > 0 and highest or nil
    pull.drops = pull.drops or 0
    self.lastThreat = nil
    -- Your stats as they were for this pull (out of combat, so they read), not as they are when you look later.
    pull.stats = Breakdown.Stats(pull.enemyLevel)
    table.insert(self.pulls, 1, pull)
    Breakdown.Trim(self.pulls)
    pull.state = "reading"
    self:ScheduleRead(pull, 1)
end

-- pulls (newest first) to what is kept: MAX_PULLS besides the ones you keep (the oldest go), and the group replay of
-- the newest REPLAYS of those (an older one's is dropped: replayDropped). A kept pull keeps everything.
function Breakdown.Trim(pulls)
    local unkept, index = 0, 1
    while pulls[index] do
        local pull = pulls[index]
        if pull.kept then
            index = index + 1
        else
            unkept = unkept + 1
            if unkept > Breakdown.MAX_PULLS then
                table.remove(pulls, index)
            else
                if unkept > Breakdown.REPLAYS and pull.group then
                    pull.group, pull.castLog, pull.replayDropped = nil, nil, true
                end
                index = index + 1
            end
        end
    end
end

-- This character's pulls from earlier sessions (PlateSmithThreatDB, saved per character; only readable numbers and
-- text are ever stored in a pull). A pull still waiting on the meter when the game closed can no longer read it.
function Breakdown:Load()
    local saved = rawget(_G, "PlateSmithThreatDB")
    if type(saved) ~= "table" or saved.version ~= 1 or type(saved.pulls) ~= "table" then
        saved = { version = 1, pulls = {} }
    end
    local pulls = {}
    for _, pull in ipairs(saved.pulls) do
        -- A sample (the developer tester's made-up pulls) is never loaded again.
        if type(pull) == "table" and type(pull.seconds) == "number" and not pull.sample then
            if pull.state ~= "read" and pull.state ~= "unread" then pull.state = pull.damage and "read" or "unread" end
            for _, key in ipairs({ "casts", "threat", "names" }) do
                if type(pull[key]) ~= "table" then pull[key] = {} end
            end
            for _, key in ipairs({ "group", "castLog", "groupDamage", "stats" }) do
                if pull[key] ~= nil and type(pull[key]) ~= "table" then pull[key] = nil end
            end
            if not Breakdown.Empty(pull) then pulls[#pulls + 1] = pull end
        end
    end
    Breakdown.Trim(pulls)
    saved.pulls = pulls
    PlateSmithThreatDB = saved
    self.saved, self.pulls = saved, pulls
    self.frameStyle = Breakdown.FRAME_STYLES[saved.frameStyle] and saved.frameStyle or nil
end

-- Keeps pull (keep true) past the newest MAX_PULLS, or lets it go again; false when MAX_KEPT are kept already.
function Breakdown:KeepPull(pull, keep)
    if not pull then return false end
    if keep and not pull.kept and Breakdown.KeptCount(self.pulls) >= Breakdown.MAX_KEPT then return false end
    pull.kept = keep and true or nil
    Breakdown.Trim(self.pulls)
    self:Paint()
    return true
end

function Breakdown.KeptCount(pulls)
    local count = 0
    for _, pull in ipairs(pulls) do if pull.kept then count = count + 1 end end
    return count
end

function Breakdown:DeletePull(pull)
    for index, each in ipairs(self.pulls) do
        if each == pull then
            table.remove(self.pulls, index)
            break
        end
    end
    if self.selected == pull then self.selected = nil end
    if self.replay and self.replay.pull == pull then self.replay.pull = nil end
    self:Paint()
end

-- Where and when the pull was ("Deadmines, 13 Nov 21:14"), or nil when neither was read.
function Breakdown.When(pull)
    local when, date = Number(pull and pull.when), rawget(_G, "date")
    local stamp = when and type(date) == "function" and date("%d %b %H:%M", when) or nil
    local zone = pull and Text(pull.zone)
    if zone and stamp then return string.format(L["%s, %s"], zone, stamp) end
    return zone or stamp
end

-- A cast while fighting: counted by name; the form is read at the pull's first cast (false: none then), once, so a
-- pull's casts do not each read it; the pull's end reads it again when none was found.
function Breakdown:NoteCast(spellID)
    local pull = self.pull
    if not pull then return end
    local name = SpellName(spellID)
    if not name then return end
    pull.casts[name] = (pull.casts[name] or 0) + 1
    -- When, for the group replay (seconds into the pull, name); the first MAX_CASTS.
    local log = pull.castLog
    if log and #log < Breakdown.MAX_CASTS then log[#log + 1] = { math.max(0, Now() - pull.started), name } end
    if pull.form == nil then pull.form = PlayerForm() or false end
end

-- A reading under DROP_SHARE of the last one on the same mob, from at least DROP_FLOOR: the mob cut your threat (a
-- knock-back, a threat drop), so the game's highest figure is the most you held at once, not the pull's total.
Breakdown.DROP_SHARE, Breakdown.DROP_FLOOR = 0.5, 200
local function Dropped(last, raw)
    return last ~= nil and raw ~= nil and last >= Breakdown.DROP_FLOOR and raw < last * Breakdown.DROP_SHARE
end

-- How many times the game cut your threat this pull (pull.drops, counted as it is recorded). A pull saved before that
-- was counted: from its group replay (your readings on your target, the same mob running), else 0.
function Breakdown.Drops(pull)
    if type(pull) ~= "table" then return 0 end
    if Number(pull.drops) then return pull.drops end
    local group = pull.group
    if type(group) ~= "table" or type(group.members) ~= "table" or type(group.times) ~= "table" then return 0 end
    local series
    for _, member in pairs(group.members) do
        if type(member) == "table" and member.isPlayer and type(member.raw) == "table" then series = member.raw end
    end
    if not series then return 0 end
    local drops, last, lastMob = 0, nil, nil
    for index = 1, #group.times do
        local raw, mob = Number(series[index]), group.mobs and group.mobs[index]
        if raw then
            if mob ~= lastMob then last = nil end
            if Dropped(last, raw) then drops = drops + 1 end
            last, lastMob = raw, mob
        end
    end
    return drops
end

-- The game's threat on each mob the threat service reads (its readable rawThreat), the highest per mob, each fall
-- (Dropped) counted, and each mob's name, read once (false: not readable).
function Breakdown:SampleThreat()
    local pull, service = self.pull, PS.ThreatService
    if not (pull and service and type(service.GetSnapshot) == "function") then return end
    local ok, list, count = pcall(service.GetSnapshot, service)
    if not ok or type(list) ~= "table" then return end
    for index = 1, count or 0 do
        local record = list[index]
        local raw, guid = record and Number(record.rawThreat), record and Text(record.guid)
        if raw and guid and raw > (pull.threat[guid] or 0) then pull.threat[guid] = raw end
        if raw and guid and self.lastThreat then
            if Dropped(self.lastThreat[guid], raw) then pull.drops = (pull.drops or 0) + 1 end
            self.lastThreat[guid] = raw
        end
        if raw and guid and pull.names[guid] == nil and record.unit then
            pull.names[guid] = Secret.ReadName(record.unit) or false
        end
    end
    self:SampleGroup(pull, Now() - pull.started)
end

-- The group's threat on your target this tick (ThreatService:GetGroupThreat, read through "target"): each member's
-- readable raw threat and whether they hold aggro, keyed by name (else unit token), and the mob. A tick with no
-- readable value adds no sample; a protected one is counted (hidden), never read. At most MAX_SAMPLES (then cut).
function Breakdown:SampleGroup(pull, seconds)
    local service, group = PS.ThreatService, pull.group
    if not (group and service and type(service.GetGroupThreat) == "function") then return end
    local ok, record, count, rows = pcall(service.GetGroupThreat, service)
    if not ok or not record or type(rows) ~= "table" or (count or 0) == 0 then return end
    if #group.times >= Breakdown.MAX_SAMPLES then
        group.cut = true
        return
    end
    local index, any = #group.times + 1, false
    for row = 1, count do
        local entry = rows[row]
        local raw = entry and Number(entry.raw)
        local key = entry and (Text(entry.name) or Text(entry.unit))
        if raw and key then
            local member = group.members[key]
            if not member then
                member = { name = Text(entry.name) or L["Group member"], class = Text(entry.classToken),
                    isPlayer = entry.isPlayer == true, raw = {}, tank = {} }
                group.members[key] = member
                group.order[#group.order + 1] = key
            end
            member.raw[index], member.tank[index] = raw, entry.tanking == true or nil
            any = true
        elseif entry and entry.hasOpaqueRaw then
            group.hidden = (group.hidden or 0) + 1
        end
    end
    if not any then return end
    group.times[index] = seconds
    local guid = Text(record.guid)
    group.mobs[index] = guid or false
    if guid and pull.names[guid] == nil then pull.names[guid] = Text(record.enemyName) or Secret.ReadName("target") or false end
end

-- ------------------------------------------------------------------ the text

local function Amount(value) return value and Format.Abbreviate(value) or "?" end
local function Clock(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function PerSecond(amount, pull)
    local seconds = Number(pull.seconds)
    return (amount and seconds and seconds > 0) and amount / seconds or nil
end

-- The stat sheet: armor against an enemy of level, attack power and spell power.
function Breakdown.Stats(level)
    level = Number(level) or ((Number(Read(UnitLevel, "player")) or 60) + 3)
    local baseArmor, effectiveArmor = Read(UnitArmor, "player")
    local armor = Number(effectiveArmor) or Number(baseArmor)
    local base, plus, minus = Read(UnitAttackPower, "player")
    local ap = Number(base) and (base + (Number(plus) or 0) + (Number(minus) or 0)) or nil
    local sp = Number(Read(GetSpellBonusDamage, 4))
    return { level = level, armor = armor, reduction = Model.ArmorReduction(armor, level), cap = Model.ArmorCap(level),
        attackPower = ap, spellPower = sp, scaling = Model.Scaling(ap, sp), swing = Model.RageFromSwing(),
        swingCrit = Model.RageFromSwing(nil, true, true) }
end

-- The pull's name in the list: its main mob (the highest threat read whose name was readable), "+N" for the other
-- mobs read, else the attackable target at its start, else the damage meter's name for the fight (SessionName), else
-- "Pull in <zone>", else "Pull".
function Breakdown.Title(pull)
    local main, best, mobs = nil, -1, 0
    local names = pull.names or {}
    for guid, value in pairs(pull.threat or {}) do
        mobs = mobs + 1
        if names[guid] and value > best then main, best = names[guid], value end
    end
    local zone = Text(pull.zone)
    local name = main or pull.target or Text(pull.session)
        or (zone and zone ~= "" and string.format(L["Pull in %s"], zone)) or L["Pull"]
    return mobs > 1 and string.format(L["%s +%d"], name, mobs - 1) or name
end

-- The list's second line: the pull's length, then its estimate, or what it is waiting for.
function Breakdown.Detail(pull)
    if pull.state == "reading" then return string.format(L["%s, reading the meter..."], Clock(pull.seconds)) end
    local estimate = Model.Estimate(pull)
    if not pull.damage and estimate.total == 0 then return string.format(L["%s, no estimate"], Clock(pull.seconds)) end
    return string.format(L["%s, %s, %s/s"], Clock(pull.seconds), Amount(estimate.total), Amount(estimate.perSecond))
end

-- The lines above the bars for pull (nil: none yet), with its estimate.
function Breakdown.Summary(pull, estimate)
    local lines = {}
    local function Add(text, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(text, ...) or text end
    if not pull then
        Add(L["No pull yet. Fight something; the breakdown fills in a few seconds after combat ends."])
        return lines
    end
    local form = pull.form and Model.FORMS[pull.form]
    Add(L["%s, %s, level %s against %s"], Clock(pull.seconds),
        form and string.format(L["%s (x%.2f)"], form.label, form.mod) or L["no threat form"],
        tostring(pull.level or "?"), tostring(pull.enemyLevel or "?"))
    if (pull.parts or 1) > 1 then
        Add(L["Joined from %d fights: combat dropped for under %d seconds between them."], pull.parts,
            Breakdown.MERGE_GAP)
        if (pull.unreadParts or 0) > 0 and pull.damage then
            Add(L["The damage meter could not be read for %d of them, so their damage is missing."], pull.unreadParts)
        end
    end
    if pull.state == "reading" then
        Add(L["Reading the damage meter..."])
    elseif not pull.damage then
        Add(L["The damage meter gave nothing readable after this pull, so there is no estimate."])
    end
    if pull.damage or next(pull.casts or {}) then
        Add(L["Estimated threat: %s (%s per second)"], Amount(estimate.total), Amount(estimate.perSecond))
    end
    -- The mobs whose threat on you read this pull: with several, the estimate (every mob together) is not
    -- comparable with the game's figure for one.
    local mobs, drops = 0, Breakdown.Drops(pull)
    for _ in pairs(pull.threat or {}) do mobs = mobs + 1 end
    -- The mob cut your threat (a knock-back, a threat drop): the game's figure is the most you held at once, so the
    -- whole pull's estimate is not set against it.
    if pull.gameThreat and drops > 0 then
        Add(drops == 1 and L["Game's threat, highest on one mob: %s. Your threat was cut once in this pull (a knock-back "
            .. "or a threat drop), so that is the most you held at once, not the pull's total: no comparison."]
            or L["Game's threat, highest on one mob: %s. Your threat was cut %d times in this pull (knock-backs or "
            .. "threat drops), so that is the most you held at once, not the pull's total: no comparison."],
            Amount(pull.gameThreat), drops)
    elseif pull.gameThreat and mobs > 1 then
        Add(L["Game's threat, highest on one mob: %s. You fought %d mobs: the estimate is your threat on them all, "
            .. "so it runs above that."], Amount(pull.gameThreat), mobs)
    elseif pull.gameThreat then
        local ratio = estimate.total > 0 and Format.Percent(estimate.total / pull.gameThreat * 100) or "?"
        Add(L["Game's threat, highest on one mob: %s (the estimate is %s of it)"], Amount(pull.gameThreat), ratio)
    else
        Add(L["Game's threat: not readable this pull."])
    end
    return lines
end

-- One bar per ability, as wide as its threat against the top one's: name, the value text (threat, share, per
-- second; "?" for a flat ability whose formula is not known) and whether its numbers are all known.
function Breakdown.Bars(pull, estimate)
    local top = 0
    for _, row in ipairs(estimate.rows) do top = math.max(top, row.threat or 0) end
    local bars = {}
    for index, row in ipairs(estimate.rows) do
        local value = row.threat and string.format(L["%s  %s  %s/s"], Amount(row.threat),
            row.share and Format.Percent(row.share * 100) or "-", Amount(PerSecond(row.threat, pull))) or "?"
        bars[index] = { row = row, name = row.name, value = value, known = row.known,
            fill = (row.threat and top > 0) and row.threat / top or 0 }
    end
    return bars
end

-- A bar's tooltip lines: how its threat was worked out, its casts, and per second.
function Breakdown.BarLines(pull, row)
    local lines = {}
    local function Add(text, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(text, ...) or text end
    if row.flat and row.known then
        Add(L["%d casts, %s threat"], row.casts, Amount(row.threat))
    elseif row.flat then
        Add(L["%d casts; this ability's threat formula is not known yet."], row.casts)
    else
        Add(L["%s damage x%.2f = %s threat"], Amount(row.damage), row.mod, Amount(row.threat))
        if not row.known then Add(L["Its modifier is not known yet, so it counts as 1."]) end
        local casts = pull.casts and pull.casts[row.name]
        if casts and casts > 0 then Add(L["%d casts, %s threat each"], casts, Amount(row.threat / casts)) end
    end
    local form = pull.form and Model.FORMS[pull.form]
    if form and row.threat then Add(L["Includes %s (x%.2f)."], form.label, form.mod) end
    if row.threat then Add(L["%s threat per second"], Amount(PerSecond(row.threat, pull))) end
    return lines
end

-- The lines below the bars: rage from damage taken, then the stat sheet. A Cat Form pull runs on energy, so it shows
-- no rage, and its attack power line leaves out Bear Form's abilities.
function Breakdown.Footer(pull, estimate, stats)
    local lines = {}
    local function Add(text, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(text, ...) or text end
    local cat = pull and pull.form == "cat"
    if pull and estimate and estimate.rage and not cat then
        Add(L["Rage from damage taken: about %s (%s taken)"], Amount(estimate.rage), Amount(pull.taken))
        Add("")
    end
    if stats then
        Add(L["Stats against level %d"], stats.level)
        if stats.armor then
            Add(L["Armor %s: %s damage reduction (75%% cap at %s)"], Amount(stats.armor),
                Format.Percent((stats.reduction or 0) * 100) or "?", Amount(stats.cap))
        end
        if stats.attackPower and cat then
            Add(L["Attack power %s"], Amount(stats.attackPower))
        elseif stats.attackPower then
            Add(L["Attack power %s: Paw +%.1f DPS, Swipe +%.1f per hit"], Amount(stats.attackPower),
                stats.scaling.pawDPS or 0, stats.scaling.swipe or 0)
        end
        if stats.spellPower and stats.spellPower > 0 then
            Add(L["Spell power %s: Thorns +%.1f"], Amount(stats.spellPower), stats.scaling.thorns or 0)
        end
        if not cat then Add(L["Rage per auto attack: %.1f (%.1f on a crit)"], stats.swing, stats.swingCrit) end
    end
    return lines
end

-- ------------------------------------------------------------------ the group replay

-- The pull's recorded group (nil: none, or no readable sample).
function Breakdown.Group(pull)
    local group = pull and pull.group
    return (group and #group.times > 0) and group or nil
end

-- The last sample at or before seconds into the pull (the first when seconds is before it).
function Breakdown.ReplayIndex(group, seconds)
    local times = group.times
    local low, high, found = 1, #times, 1
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if times[middle] <= seconds then
            found, low = middle, middle + 1
        else
            high = middle - 1
        end
    end
    return found
end

-- The group at sample index, highest first: name, class, raw, tanking, isPlayer, and ofHolder (the share of the
-- aggro holder's threat; nil when nobody held it), then the mob's GUID (false: not readable).
function Breakdown.ReplayAt(group, index)
    local rows, holder = {}, nil
    for _, key in ipairs(group.order) do
        local member = group.members[key]
        local raw = member.raw[index]
        if raw then
            rows[#rows + 1] = { key = key, name = member.name, class = member.class, raw = raw,
                tanking = member.tank[index] == true, isPlayer = member.isPlayer }
            if member.tank[index] then holder = raw end
        end
    end
    table.sort(rows, function(a, b)
        if a.raw ~= b.raw then return a.raw > b.raw end
        return a.name < b.name
    end)
    for _, row in ipairs(rows) do row.ofHolder = (holder and holder > 0) and row.raw / holder or nil end
    return rows, group.mobs[index]
end

-- Each time aggro changed hands (or the mob read changed): seconds, index, key, name, mob.
function Breakdown.AggroChanges(group)
    local changes, last, lastMob = {}, nil, nil
    for index = 1, #group.times do
        local holder
        for _, key in ipairs(group.order) do
            if group.members[key].tank[index] then
                holder = key
                break
            end
        end
        local mob = group.mobs[index]
        if holder and (holder ~= last or mob ~= lastMob) then
            changes[#changes + 1] = { seconds = group.times[index], index = index, key = holder,
                name = group.members[holder].name, mob = mob }
            last, lastMob = holder, mob
        end
    end
    return changes
end

-- The graph's lines: the REPLAY_LINES members with the highest peaks, each with its points ({ seconds, raw }, at
-- most about points of them; false where the member had no reading, which breaks the line), and the highest value.
-- A name without its realm ("Name-Realm" to "Name"), for matching the meter's names with the group's.
local function ShortName(name)
    return type(name) == "string" and (name:match("^[^-]+") or name) or nil
end

-- The group member focus names (a member's key, or a name with or without its realm), or nil.
function Breakdown.FocusKey(group, focus)
    if not (group and focus) then return nil end
    if group.members[focus] then return focus end
    local short = ShortName(focus)
    for _, key in ipairs(group.order) do
        if ShortName(group.members[key].name) == short then return key end
    end
    return nil
end

-- focus (a member's key, Breakdown.FocusKey) is always among the lines, in place of the lowest when it is not.
function Breakdown.Series(group, points, focus)
    local peaks = {}
    for _, key in ipairs(group.order) do
        local peak = 0
        for index = 1, #group.times do peak = math.max(peak, group.members[key].raw[index] or 0) end
        peaks[#peaks + 1] = { key = key, peak = peak }
    end
    table.sort(peaks, function(a, b)
        if a.peak ~= b.peak then return a.peak > b.peak end
        return a.key < b.key
    end)
    local shown = math.min(#peaks, Breakdown.REPLAY_LINES)
    if focus and group.members[focus] then
        local rankOf
        for rank, peak in ipairs(peaks) do if peak.key == focus then rankOf = rank end end
        if rankOf and rankOf > shown then peaks[shown] = peaks[rankOf] end
    end
    local step = math.max(1, math.ceil(#group.times / math.max(1, points or 120)))
    local lines, top = {}, 0
    for rank = 1, shown do
        local member = group.members[peaks[rank].key]
        local line = { key = peaks[rank].key, name = member.name, class = member.class, points = {} }
        for index = 1, #group.times, step do
            local raw = member.raw[index]
            line.points[#line.points + 1] = raw and { group.times[index], raw } or false
        end
        top = math.max(top, peaks[rank].peak)
        lines[rank] = line
    end
    return lines, top
end

-- The mob's name for a sample's GUID.
function Breakdown.MobName(pull, guid)
    return guid and pull.names and pull.names[guid] or L["your target"]
end

-- Your last count casts at or before seconds into the pull (oldest first), each { seconds, name }.
function Breakdown.CastsBefore(pull, seconds, count)
    local log, found = pull and pull.castLog or {}, {}
    for index = #log, 1, -1 do
        local cast = log[index]
        if cast[1] <= seconds then
            table.insert(found, 1, cast)
            if #found >= count then break end
        end
    end
    return found
end

-- The group's damage (the meter's, after the pull) beside each one's highest threat on your target (the replay's;
-- matched by name, you by isPlayer), highest damage first: name, class, damage, share of all the damage, threat (nil:
-- none read) and fill (against the top damage). nil when the meter gave none.
function Breakdown.DamageRows(pull)
    local sources = pull and pull.groupDamage
    if type(sources) ~= "table" or #sources == 0 then return nil end
    local peaks, mine, total = {}, nil, 0
    for _, member in pairs(pull.group and pull.group.members or {}) do
        local peak
        for _, raw in pairs(member.raw) do peak = math.max(peak or 0, raw) end
        if peak then peaks[member.name] = peak end
        if peak and member.isPlayer then mine = peak end
    end
    for _, source in ipairs(sources) do total = total + source.amount end
    local top, rows = sources[1].amount, {}
    for index, source in ipairs(sources) do
        rows[index] = { name = source.name, class = source.class, damage = source.amount, isPlayer = source.isPlayer,
            share = total > 0 and source.amount / total or 0, threat = source.isPlayer and mine or peaks[source.name],
            fill = top > 0 and source.amount / top or 0 }
    end
    return rows
end

-- ------------------------------------------------------------------ the window

-- In Studio's dialog look (Options.studioChrome, like the What's new and Blueprint windows): its dark panel, gold
-- title and close button. Left, in a dark panel, the pulls (newest first) as Settings' category rows: a wash on
-- hover, the chosen one lit with a gold bar at its left. Right, in another, one scroll with Studio's scroll
-- bar; its two views are toggles in the title band. Your threat: the pull's name, the summary, a bar per
-- ability, then the rage and stat sheet. Group replay: the group's threat on your target over the pull as a
-- graph (click or drag it to move through the pull, or play it), the group at that moment as bars, and each time
-- aggro changed hands. selected: the pull viewed, nil for the newest (so a new pull shows when it ends).
local LIST = { width = 200, height = 38, gap = 2, pad = 8, scroll = 26, actions = 34 }
-- The window: its first size on screen (ApplyScale divides it by Studio's scale) and its largest, in its own units.
local WINDOW = { width = 760, height = 540, maxWidth = 1200, maxHeight = 1000 }
local BAR = { height = 20, gap = 3, space = 10 }
local PANEL = { gap = 10, pad = 14, scroll = 28, tabWidth = 130, tabsUp = 8 }
-- The window's two looks (developer tester's switch, saved in PlateSmithThreatDB.frameStyle while it is tried):
-- dialog, Studio's dialog panel; studio, Studio's own painted frame (studioChrome.CreateFrameShell). Each: the panels'
-- insets from the window's edges, the title's place, and the tabs' right end from the right panel's (clear of the
-- close button, or of the close corner) and their height above it. Studio's panels sit between the header rail the
-- close corner lands on (105 to 113 down in the window's units, CreateFrameShell) and the footer rail (70 to 78 up
-- from the bottom: the bottom corners' inner curves reach up to it, so panels lower than that run under them), as
-- Studio's own do; the title (titleSize, Studio's large gold) and the tabs centred in the header band above.
Breakdown.FRAME_STYLES = {
    dialog = { top = 54, side = 18, bottom = 18, titleX = 22, titleY = 18, tabsRight = 34, tabsUp = PANEL.tabsUp },
    studio = { top = 116, side = 34, bottom = 84, titleX = 44, titleY = 67, titleSize = 22, tabsRight = 84,
        tabsUp = 22 },
}
local GRAPH = { height = 150, controls = 28, change = 18, changes = 30, speeds = { 1, 2, 4, 8 }, tick = 7 }
local SIZE = { heading = 16, text = 12, title = 13, detail = 11 }
local INK = { label = { 0.87, 0.85, 0.81 }, gold = { 0.89, 0.75, 0.13 }, lit = { 1, 0.93, 0.80 },
    dim = { 0.62, 0.60, 0.56 }, wash = { 1, 0.86, 0.5 }, track = { 0, 0, 0, 0.4 },
    known = { 0.72, 0.53, 0.20, 0.9 }, unknown = { 0.60, 0.25, 0.19, 0.9 }, member = { 0.55, 0.55, 0.55 } }

local function Chrome() return PS.Options and PS.Options.studioChrome end

-- A left-aligned font string in Studio's font at size, in ink.
local function Label(parent, size, ink)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local chrome = Chrome()
    if chrome then text:SetFont(chrome.FONT, size) end
    text:SetTextColor(ink[1], ink[2], ink[3])
    -- A drop shadow keeps light text readable where it sits over a bar's gold fill.
    if text.SetShadowColor then
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
    end
    text:SetJustifyH("LEFT")
    if text.SetJustifyV then text:SetJustifyV("TOP") end
    return text
end

-- A Studio button (variant as CreateStudioButton's), else the plain kit's.
local function Button(parent, text, width, variant, onClick, height)
    local chrome = Chrome()
    local button = chrome and chrome.CreateStudioButton(parent, text, width, height or 26, variant)
        or PS.UI.Window.Button(parent, text, width, height or 26)
    button:SetScript("OnClick", onClick)
    return button
end
local function SetButtonText(button, text)
    if button.label then button.label:SetText(text) else button:SetText(text) end
end

local function ClassInk(class)
    local r, g, b = Secret.ClassColour(class)
    if r then return r, g, b end
    return INK.member[1], INK.member[2], INK.member[3]
end

function Breakdown:SelectedPull()
    local selected = self.selected
    if selected then
        for _, pull in ipairs(self.pulls) do if pull == selected then return pull end end
    end
    return self.pulls[1]
end

function Breakdown:Select(pull)
    self.selected = (pull ~= self.pulls[1]) and pull or nil
    if self.frame then self.frame.scroll:SetVerticalScroll(0) end
    self:Paint()
end

-- "yours" (Your threat) or "replay" (Group replay).
function Breakdown:SelectTab(tab)
    self.tab = tab
    if self.frame then self.frame.scroll:SetVerticalScroll(0) end
    if tab ~= "replay" then self:Play(false) end
    self:Paint()
end

local function PaintPullButton(button)
    local alpha = button.selected and 0.10 or button.hover and 0.05 or 0
    button.fill:SetColorTexture(INK.wash[1], INK.wash[2], INK.wash[3], alpha)
    button.bar:SetShown(button.selected == true)
    local ink = (button.selected or button.hover) and INK.lit or INK.label
    button.title:SetTextColor(ink[1], ink[2], ink[3])
end

function Breakdown:PullButton(index)
    local list = self.frame.list
    local button = list.buttons[index]
    if button then return button end
    button = CreateFrame("Button", nil, list)
    button:SetHeight(LIST.height)
    local y = -(index - 1) * (LIST.height + LIST.gap)
    button:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
    button:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, y)
    button.fill = button:CreateTexture(nil, "BACKGROUND")
    button.fill:SetAllPoints(button)
    button.bar = button:CreateTexture(nil, "ARTWORK")
    button.bar:SetColorTexture(INK.gold[1], INK.gold[2], INK.gold[3], 1)
    button.bar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.bar:SetWidth(3)
    -- "Kept" in gold at the title line's right for a pull you keep; the title stops short of it.
    button.kept = Label(button, SIZE.detail, INK.gold)
    button.kept:SetPoint("TOPRIGHT", button, "TOPRIGHT", -6, -6)
    button.kept:SetJustifyH("RIGHT")
    button.title = Label(button, SIZE.title, INK.label)
    button.title:SetPoint("TOPLEFT", button, "TOPLEFT", 12, -5)
    button.title:SetPoint("TOPRIGHT", button.kept, "TOPLEFT", -4, 1)
    if button.title.SetWordWrap then button.title:SetWordWrap(false) end
    button.detail = Label(button, SIZE.detail, INK.dim)
    button.detail:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 12, 5)
    button.detail:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 5)
    if button.detail.SetWordWrap then button.detail:SetWordWrap(false) end
    button:SetScript("OnEnter", function(owner) owner.hover = true PaintPullButton(owner) end)
    button:SetScript("OnLeave", function(owner) owner.hover = false PaintPullButton(owner) end)
    button:SetScript("OnClick", function(owner) self:Select(owner.pull) end)
    list.buttons[index] = button
    return button
end

-- Keep's and Delete's tooltips: what they do, and Keep's limit.
function Breakdown:ShowActionTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if button.tip == "keep" then
        GameTooltip:SetText(L["Keep"])
        GameTooltip:AddLine(string.format(L["Your newest %d pulls are saved, and older ones drop off. A kept pull stays, "
            .. "replay and all, until you press Keep again. Up to %d (%d kept now)."], Breakdown.MAX_PULLS,
            Breakdown.MAX_KEPT, Breakdown.KeptCount(self.pulls)), 1, 1, 1, true)
    else
        GameTooltip:SetText(L["Delete"])
        GameTooltip:AddLine(L["Removes the chosen pull."], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- An ability's bar (bar.row) shows how its threat was worked out; a member's (bar.member) their threat then.
function Breakdown:ShowBarTooltip(bar)
    if not GameTooltip then return end
    if bar.row and bar.pull then
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:SetText(bar.row.name)
        for _, line in ipairs(Breakdown.BarLines(bar.pull, bar.row)) do GameTooltip:AddLine(line, 0.86, 0.86, 0.86, true) end
        GameTooltip:Show()
    elseif bar.damage then
        local row = bar.damage
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.name)
        GameTooltip:AddLine(string.format(L["%s damage, %s of the group's"], Amount(row.damage),
            Format.Percent(row.share * 100)), 0.86, 0.86, 0.86)
        if row.threat then
            GameTooltip:AddLine(string.format(L["%s threat at most on your target (%.2f per damage)"], Amount(row.threat),
                row.damage > 0 and row.threat / row.damage or 0), 0.86, 0.86, 0.86, true)
        else
            GameTooltip:AddLine(L["No threat of theirs was read on your target."], 0.86, 0.86, 0.86, true)
        end
        GameTooltip:Show()
    elseif bar.member then
        local member = bar.member
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:SetText(member.name)
        GameTooltip:AddLine(string.format(L["%s threat"], Amount(member.raw)), 0.86, 0.86, 0.86)
        if member.tanking then
            GameTooltip:AddLine(L["Has aggro"], 0.86, 0.86, 0.86)
        elseif member.ofHolder then
            GameTooltip:AddLine(string.format(L["%s of the aggro holder's threat (melee pull aggro at 110%%, ranged at "
                .. "130%%)"], Format.Percent(member.ofHolder * 100)), 0.86, 0.86, 0.86, true)
        end
        GameTooltip:Show()
    end
end

-- A bar in pool (content.bars: abilities; content.groupBars: the group at the replay's moment).
function Breakdown:Bar(index, pool)
    local content = self.frame.content
    pool = pool or content.bars
    local bar = pool[index]
    if bar then return bar end
    bar = CreateFrame("Button", nil, content)
    bar:SetHeight(BAR.height)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    bar.track:SetColorTexture(INK.track[1], INK.track[2], INK.track[3], INK.track[4])
    bar.fill = bar:CreateTexture(nil, "BORDER")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.value = Label(bar, SIZE.text, INK.lit)
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    bar.value:SetJustifyH("RIGHT")
    if bar.value.SetJustifyV then bar.value:SetJustifyV("MIDDLE") end
    bar.label = Label(bar, SIZE.text, INK.lit)
    bar.label:SetPoint("LEFT", bar, "LEFT", 6, 0)
    bar.label:SetPoint("RIGHT", bar.value, "LEFT", -8, 0)
    if bar.label.SetJustifyV then bar.label:SetJustifyV("MIDDLE") end
    if bar.label.SetWordWrap then bar.label:SetWordWrap(false) end
    -- The followed member's mark (the replay's focus): a gold bar at the left, as the chosen pull has.
    bar.edge = bar:CreateTexture(nil, "OVERLAY")
    bar.edge:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.edge:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.edge:SetWidth(3)
    bar.edge:SetColorTexture(INK.gold[1], INK.gold[2], INK.gold[3], 1)
    bar.edge:Hide()
    bar.share = 0
    -- A group member's bar (the replay's, or damage and threat's): follows them, or stops following.
    bar:SetScript("OnClick", function(owner)
        local name = owner.member and owner.member.key or owner.damage and owner.damage.name
        if name then self:Follow(self:Following(owner.member and owner.member.key, name) and nil or name) end
    end)
    bar:SetScript("OnEnter", function(owner) self:ShowBarTooltip(owner) end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pool[index] = bar
    return bar
end

-- Whether the replay follows the member with key (or name, the realm aside): its focus.
function Breakdown:Following(key, name)
    local focus = self.replay and self.replay.focus
    if not focus then return false end
    return (key ~= nil and key == focus) or ShortName(name) == ShortName(focus)
end

-- Follows a group member in the replay (name: their key or name; nil stops): their bars marked, their graph line
-- drawn bold over the others.
function Breakdown:Follow(name)
    self.replay = self.replay or { seconds = 0, playing = false, speed = 1 }
    self.replay.focus = Text(name)
    self:Paint()
end

-- An aggro change's row: its text; a click moves the replay there.
function Breakdown:ChangeRow(index)
    local content = self.frame.content
    local row = content.changeRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(GRAPH.change)
    row.text = Label(row, SIZE.text, INK.label)
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    if row.text.SetJustifyV then row.text:SetJustifyV("MIDDLE") end
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetAllPoints(row)
    row.fill:SetColorTexture(INK.wash[1], INK.wash[2], INK.wash[3], 0.06)
    row.fill:Hide()
    row:SetScript("OnEnter", function(owner) owner.fill:Show() end)
    row:SetScript("OnLeave", function(owner) owner.fill:Hide() end)
    row:SetScript("OnClick", function(owner) if owner.seconds then self:Seek(owner.seconds) end end)
    content.changeRows[index] = row
    return row
end

-- ------------------------------------------------------------------ playing the replay

-- The viewed pull's recorded group and its last sample's time, or nil.
function Breakdown:ReplayGroup()
    local group = Breakdown.Group(self:SelectedPull())
    if not group then return nil end
    return group, group.times[#group.times]
end

function Breakdown:Seek(seconds)
    local group, duration = self:ReplayGroup()
    if not group then return end
    self.replay.seconds = math.max(0, math.min(duration, seconds or 0))
    self:PaintMoment()
end

-- Plays from where the replay is (from the start when it is at the end), at replay.speed; false pauses.
function Breakdown:Play(on)
    local replay = self.replay
    local group, duration = self:ReplayGroup()
    on = on and group ~= nil
    if on and replay.seconds >= duration then replay.seconds = 0 end
    replay.playing = on and true or false
    PS.Ticker.SetEnabled(Breakdown.REPLAY_TICKER, replay.playing)
    local controls = self.frame and self.frame.content.controls
    if controls then SetButtonText(controls.play, replay.playing and L["Pause"] or L["Play"]) end
    if on then self:PaintMoment() end
end

function Breakdown:StepReplay(elapsed)
    local replay = self.replay
    local group, duration = self:ReplayGroup()
    if not (replay.playing and group) then return self:Play(false) end
    replay.seconds = replay.seconds + (elapsed or 0) * replay.speed
    if replay.seconds >= duration then
        replay.seconds = duration
        self:Play(false)
    end
    self:PaintMoment()
end

function Breakdown:CycleSpeed()
    local replay, speeds = self.replay, GRAPH.speeds
    local chosen = speeds[1]
    for index, speed in ipairs(speeds) do
        if speed == replay.speed then chosen = speeds[index + 1] or speeds[1] end
    end
    replay.speed = chosen
    SetButtonText(self.frame.content.controls.speed, string.format(L["Speed %dx"], chosen))
end

-- The moment the replay is at: the status line, the group's bars (laid out again when their number changes) and the
-- graph's cursor.
function Breakdown:PaintMoment()
    local frame = self.frame
    local pull = self:SelectedPull()
    local group, duration = self:ReplayGroup()
    if not (frame and group and self.tab == "replay") then return end
    local content, replay = frame.content, self.replay
    local rows, mob = Breakdown.ReplayAt(group, Breakdown.ReplayIndex(group, replay.seconds))
    content.status:SetText(string.format(L["%s of %s, on %s"], Clock(replay.seconds), Clock(duration),
        Breakdown.MobName(pull, mob)))
    if content.casts:IsShown() then
        local parts = {}
        for _, cast in ipairs(Breakdown.CastsBefore(pull, replay.seconds, Breakdown.RECENT_CASTS)) do
            parts[#parts + 1] = string.format(L["%s %s"], Clock(cast[1]), cast[2])
        end
        content.casts:SetText(string.format(L["Your casts: %s"], #parts > 0 and table.concat(parts, "  ·  ")
            or L["none yet"]))
    end
    local top = rows[1] and rows[1].raw or 0
    for index, row in ipairs(rows) do
        local bar = self:Bar(index, content.groupBars)
        bar.member, bar.row = row, nil
        bar.share = top > 0 and row.raw / top or 0
        bar.label:SetText(row.tanking and string.format(L["%s (aggro)"], row.name) or row.name)
        bar.value:SetText(row.ofHolder and not row.tanking
            and string.format(L["%s  %s"], Amount(row.raw), Format.Percent(row.ofHolder * 100)) or Amount(row.raw))
        local r, g, b = ClassInk(row.class)
        local followed = self:Following(row.key, row.name)
        bar.fill:SetColorTexture(r, g, b, (row.tanking or followed) and 0.95 or 0.7)
        bar.edge:SetShown(followed)
        local ink = followed and INK.gold or INK.lit
        bar.label:SetTextColor(ink[1], ink[2], ink[3])
        bar:Show()
        if content.width then bar.fill:SetWidth(math.max(1, content.width * bar.share)) end
    end
    for index = #rows + 1, #content.groupBars do content.groupBars[index]:Hide() end
    local graph = content.graph
    if content.width and duration > 0 then
        graph.cursor:ClearAllPoints()
        graph.cursor:SetPoint("TOP", graph, "TOPLEFT", content.width * replay.seconds / duration, 0)
        graph.cursor:SetPoint("BOTTOM", graph, "BOTTOMLEFT", content.width * replay.seconds / duration, 0)
    end
    if #rows ~= content.groupShown then
        content.groupShown = #rows
        self:Refit()
    end
end

-- The graph's lines for the viewed pull at width (drawn again only when either changes). A client without lines
-- (CreateLine) shows the cursor and the bars alone.
function Breakdown:DrawGraph(width)
    local graph, pull = self.frame.content.graph, self:SelectedPull()
    local group, duration = self:ReplayGroup()
    local focus = Breakdown.FocusKey(group, self.replay and self.replay.focus)
    if graph.drawnPull == pull and graph.drawnWidth == width and graph.drawnFocus == focus then return end
    graph.drawnPull, graph.drawnWidth, graph.drawnFocus = pull, width, focus
    local used = 0
    if group and duration > 0 and type(graph.CreateLine) == "function" then
        local lines, top = Breakdown.Series(group, math.floor(width / 4), focus)
        local height = GRAPH.height - 4
        graph.peak:SetText(top > 0 and Amount(top) or "")
        -- The followed member's line is bold and drawn last (on top); the others fade back while one is followed.
        if focus then
            table.sort(lines, function(a, b) return (a.key == focus and 1 or 0) < (b.key == focus and 1 or 0) end)
        end
        for _, series in ipairs(lines) do
            local r, g, b = ClassInk(series.class)
            local alpha, thickness = 0.9, 1.5
            if focus then
                alpha, thickness = series.key == focus and 1 or 0.35, series.key == focus and 3 or 1.5
            end
            local previous
            for _, point in ipairs(series.points) do
                if point and previous and top > 0 then
                    used = used + 1
                    local line = graph.lines[used]
                    if not line then
                        line = graph:CreateLine(nil, "ARTWORK")
                        graph.lines[used] = line
                    end
                    if line.SetThickness then line:SetThickness(thickness) end
                    line:SetColorTexture(r, g, b, alpha)
                    line:SetStartPoint("BOTTOMLEFT", graph, width * previous[1] / duration, height * previous[2] / top)
                    line:SetEndPoint("BOTTOMLEFT", graph, width * point[1] / duration, height * point[2] / top)
                    line:Show()
                end
                previous = point or nil
            end
        end
    end
    for index = used + 1, #graph.lines do graph.lines[index]:Hide() end
    -- A short gold mark along the bottom for each of your casts.
    local marks = 0
    if group and duration > 0 then
        for _, cast in ipairs(pull.castLog or {}) do
            if cast[1] <= duration then
                marks = marks + 1
                local tick = graph.ticks[marks]
                if not tick then
                    tick = graph:CreateTexture(nil, "OVERLAY")
                    tick:SetColorTexture(INK.gold[1], INK.gold[2], INK.gold[3], 0.75)
                    tick:SetSize(1, GRAPH.tick)
                    graph.ticks[marks] = tick
                end
                tick:ClearAllPoints()
                tick:SetPoint("BOTTOM", graph, "BOTTOMLEFT", width * cast[1] / duration, 0)
                tick:Show()
            end
        end
    end
    for index = marks + 1, #graph.ticks do graph.ticks[index]:Hide() end
end

-- The cursor's place along the graph as seconds into the pull.
function Breakdown:SeekFromCursor()
    local graph = self.frame.content.graph
    local _, duration = self:ReplayGroup()
    if not duration or type(GetCursorPosition) ~= "function" then return end
    local x = GetCursorPosition() / (graph:GetEffectiveScale() or 1)
    local left, width = graph:GetLeft(), graph:GetWidth()
    if type(left) ~= "number" or not width or width <= 0 then return end
    self:Seek(duration * (x - left) / width)
end

-- ------------------------------------------------------------------ the layout

local function Place(region, content, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
end

-- The ability bars, or the group's at the moment, down the content from y at width; returns the new y.
local function PlaceBars(content, pool, count, y, width)
    for index = 1, count do
        local bar = pool[index]
        y = y + (index == 1 and BAR.space or BAR.gap)
        Place(bar, content, y)
        bar:SetWidth(width)
        bar.fill:SetWidth(math.max(1, width * (bar.share or 0)))
        y = y + BAR.height
    end
    return y
end

-- Places the shown tab's parts down the content at width; returns their height.
function Breakdown:LayOut(width)
    local content, Window = self.frame.content, PS.UI.Window
    content.width = width
    local y = 0
    if content.heading:IsShown() then
        Place(content.heading, content, 0)
        y = Window.MeasureText(content.heading, width) + 6
    end
    if content.when:IsShown() then
        Place(content.when, content, y - 2)
        y = y - 2 + Window.MeasureText(content.when, width) + 8
    end
    if self.tab ~= "replay" then
        Place(content.text, content, y)
        y = PlaceBars(content, content.bars, content.shown or 0, y + Window.MeasureText(content.text, width), width)
        Place(content.footer, content, y + BAR.space)
        return y + BAR.space + Window.MeasureText(content.footer, width)
    end
    Place(content.status, content, y)
    y = y + Window.MeasureText(content.status, width)
    if content.graph:IsShown() then
        y = y + BAR.space
        Place(content.graph, content, y)
        content.graph:SetWidth(width)
        self:DrawGraph(width)
        y = y + GRAPH.height + BAR.gap * 2
        Place(content.controls, content, y)
        content.controls:SetWidth(width)
        y = y + GRAPH.controls
        if content.casts:IsShown() then
            Place(content.casts, content, y + 2)
            content.casts:SetWidth(width)
            y = y + 2 + Window.MeasureText(content.casts, width)
        end
        y = PlaceBars(content, content.groupBars, content.groupShown or 0, y, width)
        Place(content.changesHeading, content, y + BAR.space * 2)
        y = y + BAR.space * 2 + Window.MeasureText(content.changesHeading, width) + 4
        for index = 1, content.changesShown or 0 do
            local row = content.changeRows[index]
            Place(row, content, y)
            row:SetWidth(width)
            y = y + GRAPH.change
        end
        if content.changesMore:IsShown() then
            Place(content.changesMore, content, y + 2)
            y = y + 2 + Window.MeasureText(content.changesMore, width)
        end
    end
    if content.damageHeading:IsShown() then
        Place(content.damageHeading, content, y + BAR.space * 2)
        y = y + BAR.space * 2 + Window.MeasureText(content.damageHeading, width)
        y = PlaceBars(content, content.damageBars, content.damageShown or 0, y, width)
        Place(content.damageNote, content, y + 6)
        y = y + 6 + Window.MeasureText(content.damageNote, width)
    end
    return y
end

-- Sizes the content to the scroll's width and its laid-out height, then syncs the scroll bar.
function Breakdown:Refit()
    local frame = self.frame
    local width = frame and frame.scroll:GetWidth() or 0
    if width <= 0 then return end
    frame.content:SetWidth(width)
    frame.content:SetHeight(self:LayOut(width) + BAR.space)
    if frame.scrollBar then frame.scrollBar:Sync() end
end

-- ------------------------------------------------------------------ building and painting

-- A dark Studio panel over frame (its art follows its size).
local function Panel(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetFrameLevel(frame:GetFrameLevel() + 1)
    local chrome = Chrome()
    if chrome then
        local art = chrome.CreatePanelArt(panel, "dark")
        panel:SetScript("OnSizeChanged", function() art:Layout() end)
        panel.art = art
    end
    return panel
end

-- The replay's parts in content: the status line, the graph (a scrubber: press or drag), the controls, the group's
-- bars and the aggro changes.
function Breakdown:BuildReplay(content)
    content.status = Label(content, SIZE.text, INK.label)
    local graph = CreateFrame("Frame", nil, content)
    graph:SetHeight(GRAPH.height)
    graph.track = graph:CreateTexture(nil, "BACKGROUND")
    graph.track:SetAllPoints(graph)
    graph.track:SetColorTexture(INK.track[1], INK.track[2], INK.track[3], INK.track[4])
    graph.cursor = graph:CreateTexture(nil, "OVERLAY")
    graph.cursor:SetColorTexture(INK.gold[1], INK.gold[2], INK.gold[3], 0.9)
    graph.cursor:SetWidth(2)
    graph.peak = Label(graph, SIZE.detail, INK.dim)
    graph.peak:SetPoint("TOPLEFT", graph, "TOPLEFT", 4, -3)
    graph.lines, graph.ticks = {}, {}
    graph:EnableMouse(true)
    local function Follow()
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return graph:SetScript("OnUpdate", nil) end
        self:SeekFromCursor()
    end
    graph:SetScript("OnMouseDown", function()
        self:Play(false)
        self:SeekFromCursor()
        graph:SetScript("OnUpdate", Follow)
    end)
    graph:SetScript("OnMouseUp", function() graph:SetScript("OnUpdate", nil) end)
    graph:SetScript("OnHide", function() graph:SetScript("OnUpdate", nil) end)
    content.graph = graph

    local controls = CreateFrame("Frame", nil, content)
    controls:SetHeight(GRAPH.controls)
    controls.play = Button(controls, L["Play"], 90, nil, function() self:Play(not self.replay.playing) end)
    controls.play:SetPoint("LEFT", controls, "LEFT", 0, 0)
    controls.speed = Button(controls, string.format(L["Speed %dx"], self.replay.speed), 90, nil,
        function() self:CycleSpeed() end)
    controls.speed:SetPoint("LEFT", controls.play, "RIGHT", 6, 0)
    controls.hint = Label(controls, SIZE.detail, INK.dim)
    controls.hint:SetPoint("LEFT", controls.speed, "RIGHT", 10, 0)
    controls.hint:SetPoint("RIGHT", controls, "RIGHT", 0, 0)
    controls.hint:SetText(L["Click or drag the graph to move through the pull."])
    content.controls = controls

    content.groupBars, content.groupShown = {}, 0
    content.changesHeading = Label(content, SIZE.title, INK.gold)
    content.changesHeading:SetText(L["Aggro"])
    content.changeRows, content.changesShown = {}, 0
    content.changesMore = Label(content, SIZE.detail, INK.dim)
    -- Your casts up to the moment (gold marks on the graph), and the group's damage beside their threat.
    content.casts = Label(content, SIZE.text, INK.label)
    content.damageHeading = Label(content, SIZE.title, INK.gold)
    content.damageHeading:SetText(L["Damage and threat"])
    content.damageBars, content.damageShown = {}, 0
    content.damageNote = Label(content, SIZE.detail, INK.dim)
    content.damageNote:SetText(L["Damage is the whole pull on every mob, from the game's damage meter once combat ended "
        .. "(the game hides it during a fight, so it cannot follow the graph). Threat is the most each reached on your "
        .. "target."])
end

function Breakdown:Window()
    if self.frame then return self.frame end
    local Window = PS.UI and PS.UI.Window
    if not Window then return nil end
    self.replay = self.replay or { seconds = 0, playing = false, speed = 1 }
    self.tab = self.tab or "yours"
    local frame = Window.Create("PlateSmithThreatBreakdown", { title = L["Threat breakdown"],
        width = WINDOW.width, height = WINDOW.height, resizable = { 640, 480, WINDOW.maxWidth, WINDOW.maxHeight },
        border = Window.colours.studio, background = { 0.025, 0.03, 0.035, 0.98 },
    })
    local chrome = Chrome()
    if chrome then chrome.DressStudioDialog(frame) end
    frame.dialogClose = frame.closeButton
    -- Studio's painted frame, for the studio look (FRAME_STYLES); hidden until chosen.
    if chrome and chrome.CreateFrameShell then
        local shell = chrome.CreateFrameShell(frame)
        shell.close:SetScript("OnClick", function() frame:Hide() end)
        shell:SetShown(false)
        frame.shell = shell
        -- The art follows the window: each resize (at the size the client gives) and each Show (a size set while it
        -- was hidden, ApplyScale's first, may not have laid it out, and the panels then grew past the art's edges).
        if frame.HookScript then
            frame:HookScript("OnSizeChanged", function(_, width, height)
                if shell.shown then shell:Layout(width, height) end
            end)
            frame:HookScript("OnShow", function() if shell.shown then shell:Layout(nil, nil, true) end end)
        end
    end
    if frame.HookScript then frame:HookScript("OnHide", function() self:Play(false) end) end

    local listPanel = Panel(frame)
    listPanel:SetWidth(LIST.width + LIST.scroll + 2 * LIST.pad)
    frame.listPanel = listPanel
    -- The pulls scroll (Studio's bar, shown only when they overflow); Keep and Delete for the chosen one under them.
    local listScroll = CreateFrame("ScrollFrame", nil, listPanel)
    listScroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", LIST.pad, -LIST.pad)
    listScroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -(LIST.pad + LIST.scroll), LIST.pad + LIST.actions)
    listScroll:SetFrameLevel(listPanel:GetFrameLevel() + 2)
    local list = CreateFrame("Frame", nil, listScroll)
    list:SetWidth(LIST.width)
    list:SetHeight(1)
    listScroll:SetScrollChild(list)
    list.buttons = {}
    local actionWidth = math.floor((LIST.width + LIST.scroll - 6) / 2)
    local keep = Button(listPanel, L["Keep"], actionWidth, "toggle", function()
        local pull = self:SelectedPull()
        self:KeepPull(pull, not (pull and pull.kept))
    end)
    keep:SetPoint("BOTTOMLEFT", listPanel, "BOTTOMLEFT", LIST.pad, LIST.pad)
    -- As tall as the toggle beside it (Studio draws toggles 32 high), so both labels match.
    local delete = Button(listPanel, L["Delete"], actionWidth, nil,
        function() self:DeletePull(self:SelectedPull()) end, 32)
    delete:SetPoint("LEFT", keep, "RIGHT", 6, 0)
    for _, action in ipairs({ keep, delete }) do
        action:SetFrameLevel(listPanel:GetFrameLevel() + 3)
        action:HookScript("OnEnter", function(owner) self:ShowActionTooltip(owner) end)
        action:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    keep.tip, delete.tip = "keep", "delete"
    frame.keep, frame.delete, frame.listScroll = keep, delete, listScroll

    local contentPanel = Panel(frame)
    contentPanel:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", PANEL.gap, 0)
    frame.contentPanel = contentPanel
    -- The two views sit in the title band, right of the title and clear of the close button, as Studio's header holds
    -- its Studio / Settings toggle; the panel below starts with the pull itself.
    local tabs = {
        yours = Button(frame, L["Your threat"], PANEL.tabWidth, "toggle", function() self:SelectTab("yours") end),
        replay = Button(frame, L["Group replay"], PANEL.tabWidth, "toggle", function() self:SelectTab("replay") end),
    }
    tabs.yours:SetPoint("RIGHT", tabs.replay, "LEFT", -6, 0)
    for _, tab in pairs(tabs) do tab:SetFrameLevel(frame:GetFrameLevel() + 3) end
    local scroll = CreateFrame("ScrollFrame", nil, contentPanel)
    scroll:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", PANEL.pad, -PANEL.pad)
    scroll:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -(PANEL.pad + PANEL.scroll), PANEL.pad)
    scroll:SetFrameLevel(contentPanel:GetFrameLevel() + 2)
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    content.heading = Label(content, SIZE.heading, INK.gold)
    content.when = Label(content, SIZE.detail, INK.dim)
    content.text = Label(content, SIZE.text, chrome and chrome.LABEL or INK.label)
    content.footer = Label(content, SIZE.text, INK.dim)
    content.bars, content.shown = {}, 0
    frame.list, frame.scroll, frame.content, frame.tabs = list, scroll, content, tabs
    self.frame = frame
    self:BuildReplay(content)
    if chrome then
        local listBar = chrome.CreateStudioScrollBar(listScroll, listPanel)
        listBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 4, -18)
        listBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 4, 18)
        listBar:SetFrameLevel(listScroll:GetFrameLevel() + 1)
        frame.listBar = listBar
        local bar = chrome.CreateStudioScrollBar(scroll, contentPanel)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -18)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 18)
        bar:SetFrameLevel(scroll:GetFrameLevel() + 1)
        frame.scrollBar = bar
    end
    -- The scroll's width is known only once the client lays it out (after the first Show): fit then, and on resizes.
    scroll:SetScript("OnSizeChanged", function() self:Refit() end)
    listScroll:SetScript("OnSizeChanged", function(owner)
        local width = owner:GetWidth() or 0
        if width > 0 then list:SetWidth(width) end
        if frame.listBar then frame.listBar:Sync() end
    end)
    self:ApplyFrameStyle()
    return frame
end

-- The window's look (FRAME_STYLES; self.frameStyle, dialog by default): the dialog's panel and close button or
-- Studio's frame, and the panels, title and tabs placed for it.
function Breakdown:ApplyFrameStyle()
    local frame = self.frame
    if not frame then return end
    local studio = self.frameStyle == "studio" and frame.shell ~= nil
    local style = Breakdown.FRAME_STYLES[studio and "studio" or "dialog"]
    if frame.studioArt and frame.studioArt.SetShown then frame.studioArt:SetShown(not studio) end
    if frame.dialogClose then frame.dialogClose:SetShown(not studio) end
    if frame.shell then
        frame.shell:SetShown(studio)
        if studio then frame.shell:Layout() end
        frame.closeButton = studio and frame.shell.close or frame.dialogClose
    end
    if frame.title then
        local title = frame.title
        if title.GetFont and not frame.dialogTitleFont then frame.dialogTitleFont = { title:GetFont() } end
        local font = frame.dialogTitleFont
        local chrome = Chrome()
        if style.titleSize and chrome then
            title:SetFont(chrome.FONT, style.titleSize)
        elseif font and font[1] then
            title:SetFont(font[1], font[2], font[3])
        end
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", style.titleX, -style.titleY)
    end
    local list, content = frame.listPanel, frame.contentPanel
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", style.side, -style.top)
    list:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", style.side, style.bottom)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -style.side, style.bottom)
    frame.tabs.replay:ClearAllPoints()
    frame.tabs.replay:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -style.tabsRight, style.tabsUp)
end

-- Switches the window's look ("dialog" or "studio"; anything else is dialog) and keeps the choice for this character.
function Breakdown:SetFrameStyle(style)
    self.frameStyle = Breakdown.FRAME_STYLES[style] and style or nil
    if self.saved then self.saved.frameStyle = self.frameStyle end
    self:ApplyFrameStyle()
    self:Paint()
end

-- Your threat: the summary, a bar per ability, the rage and stat sheet.
function Breakdown:PaintYours(pull)
    local content = self.frame.content
    local estimate = pull and Model.Estimate(pull)
    content.text:SetText(table.concat(Breakdown.Summary(pull, estimate), "\n"))
    local bars = (pull and pull.damage or pull and next(pull.casts or {})) and Breakdown.Bars(pull, estimate) or {}
    for index, entry in ipairs(bars) do
        local bar = self:Bar(index)
        bar.pull, bar.row, bar.member, bar.share = pull, entry.row, nil, entry.fill
        bar.label:SetText(entry.name)
        bar.value:SetText(entry.value)
        local ink = entry.known and INK.known or INK.unknown
        bar.fill:SetColorTexture(ink[1], ink[2], ink[3], ink[4])
        bar:Show()
    end
    for index = #bars + 1, #content.bars do content.bars[index]:Hide() end
    content.shown = #bars
    -- A pull shows the stats recorded with it (none for one from before they were); no pull yet, your stats now.
    local stats = pull and pull.stats or (not pull and Breakdown.Stats()) or nil
    content.footer:SetText(table.concat(Breakdown.Footer(pull, estimate, stats), "\n"))
end

-- The group's damage beside their threat (DamageRows), or nothing when the meter gave none.
function Breakdown:PaintDamage(pull)
    local content = self.frame.content
    local rows = Breakdown.DamageRows(pull) or {}
    for index, row in ipairs(rows) do
        local bar = self:Bar(index, content.damageBars)
        bar.damage, bar.share = row, row.fill
        bar.label:SetText(row.name)
        bar.value:SetText(row.threat
            and string.format(L["%s  %s  ·  %s threat"], Amount(row.damage), Format.Percent(row.share * 100),
                Amount(row.threat))
            or string.format(L["%s  %s"], Amount(row.damage), Format.Percent(row.share * 100)))
        local r, g, b = ClassInk(row.class)
        local followed = self:Following(nil, row.name)
        bar.fill:SetColorTexture(r, g, b, followed and 0.95 or 0.7)
        bar.edge:SetShown(followed)
        local ink = followed and INK.gold or INK.lit
        bar.label:SetTextColor(ink[1], ink[2], ink[3])
        bar:Show()
    end
    for index = #rows + 1, #content.damageBars do content.damageBars[index]:Hide() end
    content.damageShown = #rows
    content.damageHeading:SetShown(#rows > 0)
    content.damageNote:SetShown(#rows > 0)
end

-- Group replay: the graph, controls and aggro changes (the moment's bars from PaintMoment), or why there is none.
function Breakdown:PaintReplay(pull)
    local content, replay = self.frame.content, self.replay
    local group = Breakdown.Group(pull)
    if replay.pull ~= pull then
        replay.pull, replay.seconds = pull, 0
        self:Play(false)
    end
    content.graph:SetShown(group ~= nil)
    content.controls:SetShown(group ~= nil)
    content.changesHeading:SetShown(group ~= nil)
    content.casts:SetShown(group ~= nil and pull.castLog ~= nil and #pull.castLog > 0)
    content.changesMore:Hide()
    for _, bar in ipairs(content.groupBars) do bar:Hide() end
    for _, row in ipairs(content.changeRows) do row:Hide() end
    content.groupShown, content.changesShown = 0, 0
    self:PaintDamage(pull)
    if not group then
        local hidden = pull and pull.group and (pull.group.hidden or 0) > 0
        content.status:SetText(not pull and L["No pull yet."]
            or pull.replayDropped and string.format(L["Replays are kept for your newest %d pulls and the ones you keep, "
                .. "so this one's has gone. Press Keep on a pull to hold on to its replay."], Breakdown.REPLAYS)
            or hidden
            and L["The game kept the group's threat hidden this pull (it does in some places, such as instances), so "
                .. "there is nothing to replay."]
            or L["No group threat was recorded this pull. It is read on your target while you fight, so target the "
                .. "mob you want to follow."])
        return
    end
    local changes = Breakdown.AggroChanges(group)
    for index = 1, math.min(#changes, GRAPH.changes) do
        local change, row = changes[index], self:ChangeRow(index)
        row.seconds = change.seconds
        row.text:SetText(string.format(L["%s  %s has aggro on %s"], Clock(change.seconds), change.name,
            Breakdown.MobName(pull, change.mob)))
        row:Show()
    end
    content.changesShown = math.min(#changes, GRAPH.changes)
    if #changes == 0 then
        content.changesMore:SetText(L["Nobody's aggro was read this pull."])
        content.changesMore:Show()
    elseif #changes > GRAPH.changes then
        content.changesMore:SetText(string.format(L["and %d more"], #changes - GRAPH.changes))
        content.changesMore:Show()
    end
    self:PaintMoment()
end

function Breakdown:Paint()
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end
    local pull = self:SelectedPull()
    for index, each in ipairs(self.pulls) do
        local button = self:PullButton(index)
        button.pull, button.selected = each, each == pull
        button.title:SetText(Breakdown.Title(each))
        button.kept:SetText(each.kept and L["Kept"] or "")
        button.detail:SetText(Breakdown.Detail(each))
        PaintPullButton(button)
        button:Show()
    end
    for index = #self.pulls + 1, #frame.list.buttons do frame.list.buttons[index]:Hide() end
    frame.list:SetHeight(math.max(1, #self.pulls * (LIST.height + LIST.gap)))
    if frame.listBar then frame.listBar:Sync() end

    local chrome, content, replaying = Chrome(), frame.content, self.tab == "replay"
    for key, tab in pairs(frame.tabs) do
        if chrome then chrome.SetStudioButtonState(tab, key == self.tab) end
    end
    -- Keep: lit for a kept pull; off while nothing is chosen or MAX_KEPT others are kept. Delete: any pull.
    if chrome then chrome.SetStudioButtonState(frame.keep, pull ~= nil and pull.kept == true) end
    frame.keep:SetEnabled(pull ~= nil and (pull.kept or Breakdown.KeptCount(self.pulls) < Breakdown.MAX_KEPT))
    frame.delete:SetEnabled(pull ~= nil)
    content.heading:SetText(pull and Breakdown.Title(pull) or "")
    content.heading:SetShown(pull ~= nil)
    local when = pull and Breakdown.When(pull)
    content.when:SetText(when or "")
    content.when:SetShown(when ~= nil)
    for _, region in ipairs({ content.text, content.footer }) do region:SetShown(not replaying) end
    content.status:SetShown(replaying)
    if replaying then
        for _, bar in ipairs(content.bars) do bar:Hide() end
        self:PaintReplay(pull)
    else
        for _, region in ipairs({ content.graph, content.controls, content.changesHeading, content.changesMore,
            content.casts, content.damageHeading, content.damageNote }) do
            region:Hide()
        end
        for _, bar in ipairs(content.groupBars) do bar:Hide() end
        for _, bar in ipairs(content.damageBars) do bar:Hide() end
        for _, row in ipairs(content.changeRows) do row:Hide() end
        self:PaintYours(pull)
    end
    self:Refit()
end

function Breakdown:Changed() self:Paint() end

-- Studio's scale (studioChrome.WindowScale), so the kit's frame, art and text are the size Studio draws them. The
-- window keeps its size on screen: at first it is made 760 x 540 on screen, in the window's own (scaled) units.
function Breakdown:ApplyScale()
    local frame, chrome = self.frame, Chrome()
    if not frame or not frame.SetScale then return end
    local scale = chrome and chrome.WindowScale and chrome.WindowScale() or 1
    if self.scale == scale then return end
    local first = self.scale == nil
    self.scale = scale
    frame:SetScale(scale)
    if first then
        frame:SetSize(math.min(WINDOW.maxWidth, WINDOW.width / scale), math.min(WINDOW.maxHeight, WINDOW.height / scale))
    end
end

function Breakdown:Show()
    local frame = self:Window()
    if not frame then return false end
    self:ApplyScale()
    frame:Show()
    self:Paint()
    return true
end

-- A threat window row's right-click (ThreatConsole:OpenRowBreakdown): the window on tab ("yours" or "replay") and
-- the newest pull, as Details! opens the current fight's breakdown.
function Breakdown:Open(tab, name, unit)
    self.selected = nil
    self.tab = tab == "replay" and "replay" or "yours"
    if not self:Show() then return false end
    -- The member clicked (their name, else their unit token, as the replay keys them) is followed in the replay.
    self.replay.focus = self.tab == "replay" and (Text(name) or Text(unit)) or nil
    self:SelectTab(self.tab)
    return true
end

-- The threat meter's title button: shows the window, or hides it when it is open.
function Breakdown:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        return false
    end
    return self:Show()
end

-- ------------------------------------------------------------------ lifecycle

function Breakdown:OnInitialize()
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "PLAYER_REGEN_DISABLED" then self:StartPull()
        elseif event == "PLAYER_REGEN_ENABLED" then self:EndPull()
        -- Out of combat, the enemy you pick (none: forgotten) names the next pull if its name is withheld then.
        elseif event == "PLAYER_TARGET_CHANGED" then
            if not self.pull then self.lastFoe = FoeName() end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then self:NoteCast(spellID) end
    end)
    PS.Ticker.Register(Breakdown.TICKER, Breakdown.TICK, function() self:SampleThreat() end)
    PS.Ticker.SetEnabled(Breakdown.TICKER, false)
    -- The replay's playback: only while playing (Play).
    PS.Ticker.Register(Breakdown.REPLAY_TICKER, 0.05, function(elapsed) self:StepReplay(elapsed) end)
    PS.Ticker.SetEnabled(Breakdown.REPLAY_TICKER, false)
    self.replay = { seconds = 0, playing = false, speed = 1 }
end

function Breakdown:OnEnable()
    -- Modules enable at PLAYER_LOGIN, after the character's SavedVariables have loaded.
    self:Load()
    PS._RegisterEvent(self.events, "PLAYER_REGEN_DISABLED", "platesmith.threat-breakdown")
    PS._RegisterEvent(self.events, "PLAYER_REGEN_ENABLED", "platesmith.threat-breakdown")
    PS._RegisterEvent(self.events, "PLAYER_TARGET_CHANGED", "platesmith.threat-breakdown")
    if type(self.events.RegisterUnitEvent) == "function" then
        pcall(self.events.RegisterUnitEvent, self.events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        PS._RegisterEvent(self.events, "UNIT_SPELLCAST_SUCCEEDED", "platesmith.threat-breakdown")
    end
end

function Breakdown:OnDisable()
    self.events:UnregisterAllEvents()
    PS.Ticker.SetEnabled(Breakdown.TICKER, false)
    if self.pull then Breakdown.WantGroup(false) end
    self.pull = nil
    self:Play(false)
    if self.frame then self.frame:Hide() end
end

local registered = PS:RegisterModule("platesmith.threat-breakdown", Breakdown)
if registered then PS.ThreatBreakdown = registered end
