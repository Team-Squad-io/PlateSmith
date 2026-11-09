-- Threat breakdown (a built-in module, "platesmith.threat-breakdown"): the player's own threat per pull, estimated
-- from what the client lets an addon read, beside the game's own figure where it is readable. A pull runs from
-- PLAYER_REGEN_DISABLED to PLAYER_REGEN_ENABLED; during it the player's casts (UNIT_SPELLCAST_SUCCEEDED) are counted
-- and the threat service's records give the game's threat on each mob (the highest readable, every TICK seconds).
-- After it, Blizzard's damage meter gives the player's damage per spell and damage taken (secret in combat; read at
-- READ_AFTER seconds until readable). ThreatModel turns those into the estimate. Nothing reads the combat log.
-- The last MAX_PULLS are kept for the session; the window (from the Tank window's menu) shows the newest, the stat
-- sheet (armor, attack power) and the earlier ones.
local _, PS = ...
if not PS or type(PS.RegisterModule) ~= "function" then return end
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Model = assert(PS.ThreatModel, "PlateSmith ThreatModel missing")
local Format = assert(PS.Format, "PlateSmith Format missing")
local Number, Text = Secret.Number, Secret.String

local Breakdown = { version = 1, apiMin = 1, apiMax = 1, pulls = {}, pull = nil, MAX_PULLS = 10,
    READ_AFTER = { 1, 3, 6, 10 }, TICK = 0.5, TICKER = "threat.breakdown" }
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

-- The player's form as ThreatModel knows it (bear), from the threat service's reading.
local function PlayerForm()
    local service = PS.ThreatService
    if not (service and type(service.ReadPlayerForm) == "function") then return nil end
    local ok, form = pcall(service.ReadPlayerForm, service, service:PlayerClass())
    return ok and form == "bear" and "bear" or nil
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
    self.pull = { started = Now(), form = PlayerForm(), level = level, enemyLevel = (enemy and enemy > 0) and enemy or nil,
        casts = {}, threat = {}, state = "fighting" }
    PS.Ticker.SetEnabled(Breakdown.TICKER, true)
end

function Breakdown:EndPull()
    local pull = self.pull
    if not pull then return end
    self.pull = nil
    PS.Ticker.SetEnabled(Breakdown.TICKER, false)
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

-- The game's threat on each mob the threat service reads (its readable rawThreat), the highest per mob.
function Breakdown:SampleThreat()
    local pull, service = self.pull, PS.ThreatService
    if not (pull and service and type(service.GetSnapshot) == "function") then return end
    local ok, list, count = pcall(service.GetSnapshot, service)
    if not ok or type(list) ~= "table" then return end
    for index = 1, count or 0 do
        local record = list[index]
        local raw, guid = record and Number(record.rawThreat), record and Text(record.guid)
        if raw and guid and raw > (pull.threat[guid] or 0) then pull.threat[guid] = raw end
    end
end

-- ------------------------------------------------------------------ the text

local function Amount(value) return value and Format.Abbreviate(value) or "?" end
local function Clock(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
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

-- The lines for pull (nil: none yet) and the stat sheet.
function Breakdown.Lines(pull, stats, earlier)
    local lines = {}
    local function Add(text, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(text, ...) or text end
    if not pull then
        Add(L["No pull yet. Fight something; the breakdown fills in a few seconds after combat ends."])
    else
        local form = pull.form and Model.FORMS[pull.form]
        Add(L["Last pull: %s, %s, level %s against %s"], Clock(pull.seconds),
            form and string.format(L["%s (x%.2f)"], form.label, form.mod) or L["no threat form"],
            tostring(pull.level or "?"), tostring(pull.enemyLevel or "?"))
        if pull.state == "reading" then
            Add(L["Reading the damage meter..."])
        elseif not pull.damage then
            Add(L["The damage meter gave nothing readable after this pull, so there is no estimate."])
        end
        local estimate = Model.Estimate(pull)
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
        Add("")
        for _, row in ipairs(estimate.rows) do
            local share = row.share and Format.Percent(row.share * 100) or "-"
            if row.flat then
                Add(L["%s: %d casts, %s threat (%s)%s"], row.name, row.casts, Amount(row.threat), share,
                    row.known and "" or L[" - formula not known yet"])
            else
                Add(L["%s: %s damage x%.2f = %s threat (%s)%s"], row.name, Amount(row.damage), row.mod, Amount(row.threat),
                    share, row.known and "" or L[" - modifier not known yet, counted as 1"])
            end
        end
        if estimate.rage then
            Add("")
            Add(L["Rage from damage taken: about %s (%s taken)"], Amount(estimate.rage), Amount(pull.taken))
        end
    end
    if stats then
        Add("")
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
    if earlier and #earlier > 1 then
        Add("")
        Add(L["Earlier pulls"])
        for index = 2, #earlier do
            local old = earlier[index]
            local estimate = Model.Estimate(old)
            Add(L["%s: %s threat, %s per second"], Clock(old.seconds), Amount(estimate.total), Amount(estimate.perSecond))
        end
    end
    return lines
end

-- ------------------------------------------------------------------ the window

function Breakdown:Window()
    if self.frame then return self.frame end
    local Window = PS.UI and PS.UI.Window
    if not Window then return nil end
    local frame = Window.Create("PlateSmithThreatBreakdown", { title = L["Threat breakdown"], width = 520, height = 460,
        resizable = { 380, 260, 1000, 1000 } })
    local scroll = Window.ScrollText(frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    frame.scroll = scroll
    frame:SetScript("OnSizeChanged", function() Window.RefreshScroll(scroll) end)
    self.frame = frame
    return frame
end

function Breakdown:Paint()
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end
    local pull = self.pulls[1]
    local lines = Breakdown.Lines(pull, Breakdown.Stats(pull and pull.enemyLevel), self.pulls)
    PS.UI.Window.SetScrollText(frame.scroll, table.concat(lines, "\n"))
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
    self.pull = nil
    if self.frame then self.frame:Hide() end
end

local registered = PS:RegisterModule("platesmith.threat-breakdown", Breakdown)
if registered then PS.ThreatBreakdown = registered end
