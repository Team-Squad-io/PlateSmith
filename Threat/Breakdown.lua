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

local Breakdown = { version = 1, apiMin = 1, apiMax = 1, pulls = {}, pull = nil, MAX_PULLS = 10,
    READ_AFTER = { 1, 3, 6, 10 }, TICK = 0.5, TICKER = "threat.breakdown", MAX_SAMPLES = 1200, REPLAY_LINES = 8,
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

function Breakdown:ReadMeter(pull)
    local damage, done = Breakdown.ReadDamage(MeterSource("DamageDone"))
    if not damage then return false end
    pull.damage, pull.done = damage, done
    local taken = MeterSource("DamageTaken")
    pull.taken = type(taken) == "table" and Secret.IsReadable(taken) and Number(taken.totalAmount) or nil
    return true
end

-- Reads the meter at the next READ_AFTER step; the pull is final once it reads or the steps run out.
function Breakdown:ScheduleRead(pull, step)
    local delay = Breakdown.READ_AFTER[step]
    local timer = rawget(_G, "C_Timer")
    if not delay or not (timer and type(timer.After) == "function") then
        pull.state = pull.damage and "read" or "unread"
        return self:Changed()
    end
    local previous = step > 1 and Breakdown.READ_AFTER[step - 1] or 0
    timer.After(delay - previous, function()
        if pull.state ~= "reading" then return end
        if self:ReadMeter(pull) then
            pull.state = "read"
            self:Changed()
        else
            self:ScheduleRead(pull, step + 1)
        end
    end)
end

-- ------------------------------------------------------------------ the pull

function Breakdown:StartPull()
    -- The meter's current session is the new pull's from now: an earlier pull still waiting to read it stops, unread,
    -- so it is never given this pull's damage.
    for _, earlier in ipairs(self.pulls) do
        if earlier.state == "reading" then
            earlier.state = "unread"
            self:Changed()
        end
    end
    local level = Number(Read(UnitLevel, "player"))
    local enemy = Number(Read(UnitLevel, "target"))
    -- The target's name names the pull when no threat record gives the main mob's (an attackable target only).
    local target = Read(UnitCanAttack, "player", "target") == true and Secret.ReadName("target") or nil
    self.pull = { started = Now(), form = PlayerForm(), level = level, enemyLevel = (enemy and enemy > 0) and enemy or nil,
        target = target, casts = {}, threat = {}, names = {}, state = "fighting",
        group = { times = {}, mobs = {}, members = {}, order = {} } }
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
    local highest = 0
    for _, value in pairs(pull.threat) do highest = math.max(highest, value) end
    pull.gameThreat = highest > 0 and highest or nil
    table.insert(self.pulls, 1, pull)
    for index = #self.pulls, Breakdown.MAX_PULLS + 1, -1 do self.pulls[index] = nil end
    pull.state = "reading"
    self:ScheduleRead(pull, 1)
end

-- A cast while fighting: counted by name; the form is read at the pull's first cast (false: none then), once, so a
-- pull's casts do not each read it; the pull's end reads it again when none was found.
function Breakdown:NoteCast(spellID)
    local pull = self.pull
    if not pull then return end
    local name = SpellName(spellID)
    if not name then return end
    pull.casts[name] = (pull.casts[name] or 0) + 1
    if pull.form == nil then pull.form = PlayerForm() or false end
end

-- The game's threat on each mob the threat service reads (its readable rawThreat), the highest per mob, and each
-- mob's name, read once (false: not readable).
function Breakdown:SampleThreat()
    local pull, service = self.pull, PS.ThreatService
    if not (pull and service and type(service.GetSnapshot) == "function") then return end
    local ok, list, count = pcall(service.GetSnapshot, service)
    if not ok or type(list) ~= "table" then return end
    for index = 1, count or 0 do
        local record = list[index]
        local raw, guid = record and Number(record.rawThreat), record and Text(record.guid)
        if raw and guid and raw > (pull.threat[guid] or 0) then pull.threat[guid] = raw end
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
-- mobs read, else the attackable target at its start, else "Pull".
function Breakdown.Title(pull)
    local main, best, mobs = nil, -1, 0
    local names = pull.names or {}
    for guid, value in pairs(pull.threat or {}) do
        mobs = mobs + 1
        if names[guid] and value > best then main, best = names[guid], value end
    end
    local name = main or pull.target or L["Pull"]
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
    local mobs = 0
    for _ in pairs(pull.threat or {}) do mobs = mobs + 1 end
    if pull.gameThreat and mobs > 1 then
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

-- The lines below the bars: rage from damage taken, then the stat sheet.
function Breakdown.Footer(pull, estimate, stats)
    local lines = {}
    local function Add(text, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(text, ...) or text end
    if pull and estimate and estimate.rage then
        Add(L["Rage from damage taken: about %s (%s taken)"], Amount(estimate.rage), Amount(pull.taken))
        Add("")
    end
    if stats then
        Add(L["Stats against level %d"], stats.level)
        if stats.armor then
            Add(L["Armor %s: %s damage reduction (75%% cap at %s)"], Amount(stats.armor),
                Format.Percent((stats.reduction or 0) * 100) or "?", Amount(stats.cap))
        end
        if stats.attackPower then
            Add(L["Attack power %s: Paw +%.1f DPS, Swipe +%.1f per hit"], Amount(stats.attackPower),
                stats.scaling.pawDPS or 0, stats.scaling.swipe or 0)
        end
        if stats.spellPower then Add(L["Spell power %s: Thorns +%.1f"], Amount(stats.spellPower), stats.scaling.thorns or 0) end
        Add(L["Rage per auto attack: %.1f (%.1f on a crit)"], stats.swing, stats.swingCrit)
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
function Breakdown.Series(group, points)
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
    local step = math.max(1, math.ceil(#group.times / math.max(1, points or 120)))
    local lines, top = {}, 0
    for rank = 1, math.min(#peaks, Breakdown.REPLAY_LINES) do
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

-- ------------------------------------------------------------------ the window

-- In Studio's dialog look (Options.studioChrome, like the What's new and Blueprint windows): its dark panel, gold
-- title and close button. Left, in a dark panel, the pulls (newest first) as Settings' category rows: a wash on
-- hover, the chosen one lit with a gold bar at its left. Right, in another, two tabs over one scroll with Studio's
-- scroll bar. Your threat: the pull's name, the summary, a bar per ability, then the rage and stat sheet. Group
-- replay: the group's threat on your target over the pull as a graph (click or drag it to move through the pull, or
-- play it), the group at that moment as bars, and each time aggro changed hands. selected: the pull viewed, nil for
-- the newest (so a new pull shows when it ends).
local LIST = { width = 200, height = 38, gap = 2, pad = 8 }
local BAR = { height = 20, gap = 3, space = 10 }
local PANEL = { top = 54, side = 18, bottom = 18, gap = 10, pad = 14, scroll = 28, tabs = 40 }
local GRAPH = { height = 150, controls = 28, change = 18, changes = 30, speeds = { 1, 2, 4, 8 } }
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
    text:SetJustifyH("LEFT")
    if text.SetJustifyV then text:SetJustifyV("TOP") end
    return text
end

-- A Studio button (variant as CreateStudioButton's), else the plain kit's.
local function Button(parent, text, width, variant, onClick)
    local chrome = Chrome()
    local button = chrome and chrome.CreateStudioButton(parent, text, width, 26, variant)
        or PS.UI.Window.Button(parent, text, width, 26)
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
    button.title = Label(button, SIZE.title, INK.label)
    button.title:SetPoint("TOPLEFT", button, "TOPLEFT", 12, -5)
    button.title:SetPoint("TOPRIGHT", button, "TOPRIGHT", -6, -5)
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

-- An ability's bar (bar.row) shows how its threat was worked out; a member's (bar.member) their threat then.
function Breakdown:ShowBarTooltip(bar)
    if not GameTooltip then return end
    if bar.row and bar.pull then
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:SetText(bar.row.name)
        for _, line in ipairs(Breakdown.BarLines(bar.pull, bar.row)) do GameTooltip:AddLine(line, 0.86, 0.86, 0.86, true) end
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
    bar.share = 0
    bar:SetScript("OnEnter", function(owner) self:ShowBarTooltip(owner) end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pool[index] = bar
    return bar
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
    local top = rows[1] and rows[1].raw or 0
    for index, row in ipairs(rows) do
        local bar = self:Bar(index, content.groupBars)
        bar.member, bar.row = row, nil
        bar.share = top > 0 and row.raw / top or 0
        bar.label:SetText(row.tanking and string.format(L["%s (aggro)"], row.name) or row.name)
        bar.value:SetText(row.ofHolder and not row.tanking
            and string.format(L["%s  %s"], Amount(row.raw), Format.Percent(row.ofHolder * 100)) or Amount(row.raw))
        local r, g, b = ClassInk(row.class)
        bar.fill:SetColorTexture(r, g, b, row.tanking and 0.95 or 0.7)
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
    if graph.drawnPull == pull and graph.drawnWidth == width then return end
    graph.drawnPull, graph.drawnWidth = pull, width
    local used = 0
    if group and duration > 0 and type(graph.CreateLine) == "function" then
        local lines, top = Breakdown.Series(group, math.floor(width / 4))
        local height = GRAPH.height - 4
        graph.peak:SetText(top > 0 and Amount(top) or "")
        for _, series in ipairs(lines) do
            local r, g, b = ClassInk(series.class)
            local previous
            for _, point in ipairs(series.points) do
                if point and previous and top > 0 then
                    used = used + 1
                    local line = graph.lines[used]
                    if not line then
                        line = graph:CreateLine(nil, "ARTWORK")
                        if line.SetThickness then line:SetThickness(1.5) end
                        graph.lines[used] = line
                    end
                    line:SetColorTexture(r, g, b, 0.9)
                    line:SetStartPoint("BOTTOMLEFT", graph, width * previous[1] / duration, height * previous[2] / top)
                    line:SetEndPoint("BOTTOMLEFT", graph, width * point[1] / duration, height * point[2] / top)
                    line:Show()
                end
                previous = point or nil
            end
        end
    end
    for index = used + 1, #graph.lines do graph.lines[index]:Hide() end
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
    if self.tab ~= "replay" then
        Place(content.text, content, y)
        y = PlaceBars(content, content.bars, content.shown or 0, y + Window.MeasureText(content.text, width), width)
        Place(content.footer, content, y + BAR.space)
        return y + BAR.space + Window.MeasureText(content.footer, width)
    end
    Place(content.status, content, y)
    y = y + Window.MeasureText(content.status, width)
    if not content.graph:IsShown() then return y end
    y = y + BAR.space
    Place(content.graph, content, y)
    content.graph:SetWidth(width)
    self:DrawGraph(width)
    y = y + GRAPH.height + BAR.gap * 2
    Place(content.controls, content, y)
    content.controls:SetWidth(width)
    y = PlaceBars(content, content.groupBars, content.groupShown or 0, y + GRAPH.controls, width)
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
    graph.lines = {}
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
end

function Breakdown:Window()
    if self.frame then return self.frame end
    local Window = PS.UI and PS.UI.Window
    if not Window then return nil end
    self.replay = self.replay or { seconds = 0, playing = false, speed = 1 }
    self.tab = self.tab or "yours"
    local frame = Window.Create("PlateSmithThreatBreakdown", { title = L["Threat breakdown"], width = 760, height = 540,
        resizable = { 640, 480, 1200, 1000 }, border = Window.colours.studio, background = { 0.025, 0.03, 0.035, 0.98 },
    })
    local chrome = Chrome()
    if chrome then chrome.DressStudioDialog(frame) end
    if frame.HookScript then frame:HookScript("OnHide", function() self:Play(false) end) end

    local listPanel = Panel(frame)
    listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL.side, -PANEL.top)
    listPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PANEL.side, PANEL.bottom)
    listPanel:SetWidth(LIST.width + 2 * LIST.pad)
    local list = CreateFrame("Frame", nil, listPanel)
    list:SetPoint("TOPLEFT", listPanel, "TOPLEFT", LIST.pad, -LIST.pad)
    list:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -LIST.pad, LIST.pad)
    list:SetFrameLevel(listPanel:GetFrameLevel() + 2)
    list.buttons = {}

    local contentPanel = Panel(frame)
    contentPanel:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", PANEL.gap, 0)
    contentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PANEL.side, PANEL.bottom)
    local tabs = {
        yours = Button(contentPanel, L["Your threat"], 150, "toggle", function() self:SelectTab("yours") end),
        replay = Button(contentPanel, L["Group replay"], 150, "toggle", function() self:SelectTab("replay") end),
    }
    tabs.yours:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", PANEL.pad, -PANEL.pad + 4)
    tabs.replay:SetPoint("LEFT", tabs.yours, "RIGHT", 6, 0)
    for _, tab in pairs(tabs) do tab:SetFrameLevel(contentPanel:GetFrameLevel() + 3) end
    local scroll = CreateFrame("ScrollFrame", nil, contentPanel)
    scroll:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", PANEL.pad, -(PANEL.pad + PANEL.tabs))
    scroll:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -(PANEL.pad + PANEL.scroll), PANEL.pad)
    scroll:SetFrameLevel(contentPanel:GetFrameLevel() + 2)
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    content.heading = Label(content, SIZE.heading, INK.gold)
    content.text = Label(content, SIZE.text, chrome and chrome.LABEL or INK.label)
    content.footer = Label(content, SIZE.text, INK.dim)
    content.bars, content.shown = {}, 0
    frame.list, frame.scroll, frame.content, frame.tabs = list, scroll, content, tabs
    self.frame = frame
    self:BuildReplay(content)
    if chrome then
        local bar = chrome.CreateStudioScrollBar(scroll, contentPanel)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -18)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 18)
        bar:SetFrameLevel(scroll:GetFrameLevel() + 1)
        frame.scrollBar = bar
    end
    -- The scroll's width is known only once the client lays it out (after the first Show): fit then, and on resizes.
    scroll:SetScript("OnSizeChanged", function() self:Refit() end)
    return frame
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
    content.footer:SetText(table.concat(Breakdown.Footer(pull, estimate, Breakdown.Stats(pull and pull.enemyLevel)), "\n"))
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
    content.changesMore:Hide()
    for _, bar in ipairs(content.groupBars) do bar:Hide() end
    for _, row in ipairs(content.changeRows) do row:Hide() end
    content.groupShown, content.changesShown = 0, 0
    if not group then
        local hidden = pull and pull.group and (pull.group.hidden or 0) > 0
        content.status:SetText(not pull and L["No pull yet."] or hidden
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
        button.detail:SetText(Breakdown.Detail(each))
        PaintPullButton(button)
        button:Show()
    end
    for index = #self.pulls + 1, #frame.list.buttons do frame.list.buttons[index]:Hide() end

    local chrome, content, replaying = Chrome(), frame.content, self.tab == "replay"
    for key, tab in pairs(frame.tabs) do
        if chrome then chrome.SetStudioButtonState(tab, key == self.tab) end
    end
    content.heading:SetText(pull and Breakdown.Title(pull) or "")
    content.heading:SetShown(pull ~= nil)
    for _, region in ipairs({ content.text, content.footer }) do region:SetShown(not replaying) end
    content.status:SetShown(replaying)
    if replaying then
        for _, bar in ipairs(content.bars) do bar:Hide() end
        self:PaintReplay(pull)
    else
        for _, region in ipairs({ content.graph, content.controls, content.changesHeading, content.changesMore }) do
            region:Hide()
        end
        for _, bar in ipairs(content.groupBars) do bar:Hide() end
        for _, row in ipairs(content.changeRows) do row:Hide() end
        self:PaintYours(pull)
    end
    self:Refit()
end

function Breakdown:Changed() self:Paint() end

function Breakdown:Show()
    local frame = self:Window()
    if not frame then return false end
    frame:Show()
    self:Paint()
    return true
end

-- ------------------------------------------------------------------ lifecycle

function Breakdown:OnInitialize()
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "PLAYER_REGEN_DISABLED" then self:StartPull()
        elseif event == "PLAYER_REGEN_ENABLED" then self:EndPull()
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
    PS._RegisterEvent(self.events, "PLAYER_REGEN_DISABLED", "platesmith.threat-breakdown")
    PS._RegisterEvent(self.events, "PLAYER_REGEN_ENABLED", "platesmith.threat-breakdown")
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
