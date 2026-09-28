local _, PS = ...

if not PS or type(PS.RegisterModule) ~= "function" then return end

local REFRESH_INTERVAL = 0.05
-- Out of combat with nothing to re-read, the tick only expires engagements and probes deaths.
local IDLE_INTERVAL = 0.25
local REFRESH_BUDGET = 2
local IMMEDIATE_REFRESH_BUDGET = 4
local DEAD_PROBE_BUDGET = 2
local MAX_ENEMIES = 40
local MAX_ROSTER_UNITS = 82
local MAX_ATTACKER_TARGETS = 40
local MAX_ATTACKERS_PER_TARGET = 40
local ENGAGEMENT_WINDOW = 5
-- The group read covers the whole roster, so it runs at most this often (the windows redraw at 0.25 s).
local GROUP_THREAT_INTERVAL = 0.2
-- The differential needs every roster member's threat on the mob. The player's target and focus,
-- and enemies a tank window shows, are read on every refresh; other plates at most this often.
local GROUP_SCAN_INTERVAL = 0.5

local SERVICE_EVENTS = {
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_TARGET",
    "UNIT_PET",
    "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "UNIT_COMBAT",
    -- What the player is doing can make them the tank (Adaptive): stance, form, auras, talents.
    -- UNIT_AURA is registered for the player alone, below.
    "UPDATE_SHAPESHIFT_FORM",
    "CHARACTER_POINTS_CHANGED",
    "PLAYER_TALENT_UPDATE",
}

local ThreatService = {
    cursor = 0,
    enemyCount = 0,
    rosterCount = 0,
    rosterRevision = 0,
    rosterMissingGUID = 0,
    snapshotCount = 0,
    totalVisible = 0,
    totalLoose = 0,
    totalEngaged = 0,
    snapshotDirty = true,
    isSolo = true,
    nextRecordSerial = 0,
    deadCursor = 0,
    immediateRefreshes = 0,
    targetersDirty = false,
    allTargetersDirty = false,
    playerRole = "NONE",
    playerRoleSource = "none",
    -- Bumped whenever the snapshot is rebuilt or the group threat is re-read, so a window
    -- redraws only when something changed.
    snapshotRevision = 0,
    groupThreatRevision = 0,
    groupThreatCount = 0,
    groupThreatWanted = false,
    threatPass = 0,
    groupScans = 0,
    tickInterval = REFRESH_INTERVAL,
}

local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable, IsSecret, ReadBoolean = Secret.IsReadable, Secret.IsSecret, Secret.ReadBoolean
local UnitExistsSafely, SameUnit, ReadName, ReadGUID = Secret.UnitExists, Secret.SameUnit, Secret.ReadName, Secret.ReadGUID
local L = PS.L

-- "<unit>target" for each token seen, built once instead of on every read.
local targetTokens = {}
local function TargetToken(unit)
    local token = targetTokens[unit]
    if not token then
        token = unit .. "target"
        targetTokens[unit] = token
    end
    return token
end

-- Roster tokens, built once rather than on every roster rebuild.
local RAID_TOKENS, RAID_PET_TOKENS, PARTY_TOKENS, PARTY_PET_TOKENS = {}, {}, {}, {}
for index = 1, 40 do RAID_TOKENS[index], RAID_PET_TOKENS[index] = "raid" .. index, "raidpet" .. index end
for index = 1, 4 do PARTY_TOKENS[index], PARTY_PET_TOKENS[index] = "party" .. index, "partypet" .. index end

-- Fields a threat window shows or sorts by. A refresh that changes none of them (and holds no
-- protected value, which cannot be compared) leaves the snapshot as it is.
local SHOWN_FIELDS = {
    "unit", "guid", "enemyName", "serial", "root", "threatMobSource", "holdState", "engaged", "loose",
    "targetName", "activeAttackerCount", "percent", "lead", "leadKind", "leadPercent", "rawThreat",
    "selfHolds", "tankHolds", "tanking", "status",
}

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

-- The nameplate token for a unit token such as "target" or "boss1": true and the token (nil when
-- the unit has no plate), or false when the client will not say.
local function PlateToken(unit)
    local getPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(getPlate) ~= "function" then return false end
    local ok, plate = pcall(getPlate, unit)
    if not ok or not IsReadable(plate) then return false end
    if plate == nil then return true, nil end
    if type(plate) ~= "table" then return false end
    local token = plate.namePlateUnitToken
    if not IsReadable(token) or type(token) ~= "string" then return false end
    return true, token
end

-- The character's tank choice: "adaptive", "always" or "never".
local function TankMode()
    local character = type(PS.GetCharacterSettings) == "function" and PS.GetCharacterSettings() or nil
    return type(character) == "table" and character.tankRole or "adaptive"
end

-- A threat tuple is "no entry on this mob's table" only when every value is readable and nil.
-- An unreadable value is never compared with nil: it counts as an entry.
local function IsNoEntry(tanking, status, scaled, rawPercent, raw)
    return IsReadable(tanking) and tanking == nil and IsReadable(status) and status == nil
        and IsReadable(scaled) and scaled == nil and IsReadable(rawPercent) and rawPercent == nil
        and IsReadable(raw) and raw == nil
end

local function ReadThreatValue(callback, unit, mob)
    if type(callback) ~= "function" then return nil, nil, "api-missing" end
    local ok, value = pcall(callback, unit, mob)
    if not ok then return nil, nil, "error" end
    if IsSecret(value) then return nil, value, "protected/displayable" end
    if not IsReadable(value) or type(value) ~= "number" then
        return nil, nil, value == nil and "none" or "unavailable"
    end
    return value, nil, "readable"
end

-- A group member's role: the one assigned in the group, else a raid's Main Tank marking.
local function ReadRole(unit)
    if type(UnitGroupRolesAssigned) == "function" then
        local ok, role = pcall(UnitGroupRolesAssigned, unit)
        if ok and IsReadable(role) and type(role) == "string" and role ~= "NONE" then return role end
    end
    if type(GetPartyAssignment) == "function" then
        local ok, mainTank = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and IsReadable(mainTank) and mainTank == true then return "TANK" end
    end
    return "NONE"
end

-- Evidence that the player is tanking right now, for Adaptive when no role is assigned: a
-- tanking stance or presence, Righteous Fury, or Bear / Dire Bear Form on a druid whose talents
-- are mostly Feral (bear form alone is also a healer's escape). Returns true, false, or nil when
-- the client will not say (the caller keeps what it last knew).
local TANK_FORMS = { [18] = "stance" } -- Defensive Stance
local BEAR_FORMS = { [5] = true, [8] = true } -- Bear, Dire Bear
local TANK_AURAS = { [25780] = true, [48263] = true } -- Righteous Fury; the death knight's tanking presence
local BEAR_AURAS = { [5487] = true, [9634] = true } -- Bear Form, Dire Bear Form (when the form ID is withheld)

local function PlayerAuraActive(spellID)
    if type(C_UnitAuras) == "table" and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if not ok or IsSecret(aura) then return nil end
        return aura ~= nil
    end
    return nil
end

-- Points spent in each talent tree (nil where the client does not say).
local function TalentPoints(tab)
    if type(GetTalentTabInfo) ~= "function" then return nil end
    local ok, first, _, third, _, fifth = pcall(GetTalentTabInfo, tab)
    if not ok then return nil end
    -- Older clients return name, icon, points; later ones id, name, description, icon, points.
    local points = type(first) == "string" and third or fifth
    return IsReadable(points) and type(points) == "number" and points or nil
end

local function PlayerTankEvidence()
    local formID
    if type(GetShapeshiftFormID) == "function" then
        local ok, value = pcall(GetShapeshiftFormID)
        if ok and IsReadable(value) then formID = value end
    end
    if formID and TANK_FORMS[formID] then return true end
    local unknown = false
    for spellID in pairs(TANK_AURAS) do
        local active = PlayerAuraActive(spellID)
        if active then return true end
        if active == nil then unknown = true end
    end
    local bear = formID and BEAR_FORMS[formID]
    if not bear and not formID then
        for spellID in pairs(BEAR_AURAS) do
            if PlayerAuraActive(spellID) then bear = true break end
        end
    end
    if bear then
        -- Mostly Balance or Restoration points: bear form as an escape, not tanking. Talents the
        -- client will not report leave bear form as the evidence it usually is.
        local feral, balance, restoration = TalentPoints(2), TalentPoints(1), TalentPoints(3)
        if not feral then return true end
        return feral >= (balance or 0) and feral >= (restoration or 0)
    end
    if unknown and not formID then return nil end
    return false
end

local function IsVisibleHostile(root, unit)
    if not root or type(unit) ~= "string" then return false end
    if root.IsShown and not root:IsShown() then return false end
    if not UnitExistsSafely(unit) then return false end
    if ReadBoolean(UnitIsDeadOrGhost, unit) == true or ReadBoolean(UnitIsDead, unit) == true then return false end

    local hostile = ReadBoolean(UnitCanAttack, "player", unit)
    if hostile ~= nil then return hostile end
    local friendly = ReadBoolean(UnitIsFriend, "player", unit)
    if friendly ~= nil then return not friendly end
    return false
end

-- A unit token usable as a table key: readable and a string.
local function ReadableToken(unit)
    return IsReadable(unit) and type(unit) == "string" and unit or nil
end

local function SnapshotSort(left, right)
    if left.loose ~= right.loose then return left.loose end
    if left.engaged ~= right.engaged then return left.engaged end
    if left.targetName ~= right.targetName then return left.targetName < right.targetName end
    if left.enemyName ~= right.enemyName then return left.enemyName < right.enemyName end
    return left.unit < right.unit
end

function ThreatService:AddRosterUnit(unit, owner, isMember)
    if self.rosterCount >= MAX_ROSTER_UNITS or not UnitExistsSafely(unit) then return end
    self.rosterCount = self.rosterCount + 1
    local entry = self.rosterPool[self.rosterCount]
    entry.unit = unit
    entry.targetToken = TargetToken(unit)
    entry.owner = owner or unit
    entry.assignedRole = ReadRole(entry.owner)
    entry.role = entry.assignedRole
    entry.name = ReadName(unit, unit)
    entry.guid = ReadGUID(unit)
    entry.isMember = isMember and true or false
    entry.isPlayer = unit == "player" or SameUnit(unit, "player")
    entry.ownerIsPlayer = entry.owner ~= unit and (entry.owner == "player" or SameUnit(entry.owner, "player"))
    entry.targetGUID, entry.targetDirty = nil, true
    entry.classToken = nil
    if entry.isMember and type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, unit)
        if ok and IsReadable(token) and type(token) == "string" then entry.classToken = token end
    end
    if entry.isPlayer and not self.playerRosterIndex then self.playerRosterIndex = self.rosterCount end
    self.threatTuples[self.rosterCount].pass = nil
    self.rosterByUnit[unit] = entry
    if entry.guid then
        self.rosterByGUID[entry.guid] = entry
    else
        self.rosterMissingGUID = self.rosterMissingGUID + 1
    end
end

-- The player's role. Always and Never (per character) win; Adaptive takes the assigned group
-- role, then what the player is doing (PlayerTankEvidence), then the specialization's.
function ThreatService:ResolvePlayerRole()
    self.roleDirty = false
    self.roleResolves = (self.roleResolves or 0) + 1
    local role, source = "NONE", "none"
    local mode = TankMode()
    for index = 1, mode == "always" and 0 or self.rosterCount do
        local entry = self.rosterPool[index]
        if entry.isPlayer then
            role = entry.assignedRole
            if role ~= "NONE" then source = "assigned" end
            break
        end
    end
    -- Adaptive: what the player is doing now (a tanking stance, presence or bear form) outranks
    -- the role a talent spec implies (Feral reads as damage); only a group-assigned role, or the
    -- Always / Never choice, comes before it.
    if role == "NONE" and mode == "adaptive" then
        local evidence = PlayerTankEvidence()
        if evidence == nil then evidence = self.playerTankEvidence end
        self.playerTankEvidence = evidence
        if evidence then role, source = "TANK", "adaptive" end
    end
    if role == "NONE" and mode ~= "always" and type(GetSpecialization) == "function"
        and type(GetSpecializationRole) == "function" then
        local ok, specialization = pcall(GetSpecialization)
        if ok and IsReadable(specialization) and type(specialization) == "number" then
            local roleOK, specRole = pcall(GetSpecializationRole, specialization)
            if roleOK and IsReadable(specRole) and type(specRole) == "string" then
                role, source = specRole, "specialization"
            end
        end
    end
    if mode == "always" then
        role, source = "TANK", "forced"
    elseif mode == "never" then
        if role == "TANK" then role, source = "DAMAGER", "never" end
    end

    self.playerRole, self.playerRoleSource = role, source
    -- Hold state reads roster roles, so the player's entries must carry the resolved role.
    for index = 1, self.rosterCount do
        local entry = self.rosterPool[index]
        if entry.isPlayer or entry.ownerIsPlayer then entry.role = role end
    end
end

function ThreatService:RebuildRoster()
    self.rosterDirty = false
    self.rosterRebuilds = (self.rosterRebuilds or 0) + 1
    local oldCount = self.rosterCount
    self.rosterCount, self.playerRosterIndex, self.rosterMissingGUID = 0, nil, 0
    -- Cached group scans were read against the old roster.
    self.rosterRevision = self.rosterRevision + 1
    for guid in pairs(self.rosterByGUID) do self.rosterByGUID[guid] = nil end
    for unit in pairs(self.rosterByUnit) do self.rosterByUnit[unit] = nil end

    local raid = ReadBoolean(IsInRaid) == true
    local groupCount = 0
    if raid and type(GetNumGroupMembers) == "function" then
        local ok, value = pcall(GetNumGroupMembers)
        if ok and IsReadable(value) and type(value) == "number" then
            groupCount = math.min(value, 40)
        end
        for index = 1, groupCount do
            self:AddRosterUnit(RAID_TOKENS[index], nil, true)
            self:AddRosterUnit(RAID_PET_TOKENS[index], RAID_TOKENS[index], false)
        end
    else
        self:AddRosterUnit("player", nil, true)
        self:AddRosterUnit("pet", "player", false)
        if type(GetNumSubgroupMembers) == "function" then
            local ok, value = pcall(GetNumSubgroupMembers)
            if ok and IsReadable(value) and type(value) == "number" then
                groupCount = math.min(value, 4)
            end
        end
        for index = 1, groupCount do
            self:AddRosterUnit(PARTY_TOKENS[index], nil, true)
            self:AddRosterUnit(PARTY_PET_TOKENS[index], PARTY_TOKENS[index], false)
        end
    end

    self.isSolo = not raid and groupCount == 0

    for index = self.rosterCount + 1, oldCount do
        local entry = self.rosterPool[index]
        entry.unit, entry.owner, entry.role, entry.assignedRole, entry.name, entry.guid = nil, nil, nil, nil, nil, nil
        entry.isMember, entry.isPlayer, entry.ownerIsPlayer, entry.classToken = nil, nil, nil, nil
        entry.targetToken, entry.targetGUID, entry.targetDirty = nil, nil, nil
        local tuple = self.threatTuples[index]
        tuple.pass, tuple.tanking, tuple.status, tuple.scaled, tuple.rawPercent, tuple.raw = nil, nil, nil, nil, nil, nil
    end

    self:ResolvePlayerRole()
end

-- The tick returns to the refresh rate as soon as there is something to re-read.
function ThreatService:Hurry()
    if self.tickInterval ~= REFRESH_INTERVAL then
        self.tickInterval = REFRESH_INTERVAL
        if PS.Ticker then PS.Ticker.SetInterval("threat.service", REFRESH_INTERVAL) end
    end
end

-- Roster events come in bursts (a raid forming, pets resummoned): each only flags the roster,
-- which is rebuilt once, on the next tick or before anything reads it.
function ThreatService:MarkRosterDirty()
    self.rosterDirty = true
    self:Hurry()
end

-- Stance, form, aura and talent events likewise only flag the player's role.
function ThreatService:MarkRoleDirty()
    self.roleDirty = true
    self:Hurry()
end

-- Whether what the player is doing can decide the role: Adaptive with no group-assigned role.
function ThreatService:TankEvidenceMatters()
    if self.rosterDirty then return true end
    if TankMode() ~= "adaptive" then return false end
    local entry = self.playerRosterIndex and self.rosterPool[self.playerRosterIndex]
    return not entry or entry.assignedRole == "NONE"
end

-- Applies a flagged roster or role change. Returns nothing; safe to call on any read.
function ThreatService:FlushPending()
    if self.rosterDirty then
        self:RebuildRoster()
        self:RebuildTargeterCounts()
        self:MarkDirty()
    end
    if self.roleDirty then
        local previous = self.playerRole
        self:ResolvePlayerRole()
        if self.playerRole ~= previous then self:MarkDirty() end
    end
end

-- A group member retargeted: only that member's target is read again at the next flush. A mob's
-- retarget changes no group targeter; an unreadable or unknown group token re-reads everyone.
function ThreatService:MarkTargeterDirty(unit)
    local token = ReadableToken(unit)
    local entry = token and self.rosterByUnit[token]
    if not entry and token == "player" and self.playerRosterIndex then entry = self.rosterPool[self.playerRosterIndex] end
    if entry then
        if entry.isMember then
            entry.targetDirty = true
            self.targetersDirty = true
            self:Hurry()
        end
        return
    end
    if token and not (token == "pet" or token:match("^party") or token:match("^raid")) then return end
    self.allTargetersDirty = true
    self.targetersDirty = true
    self:Hurry()
end

-- Rebuilds who targets which enemy from each member's target GUID. With onlyDirty, only members
-- marked by MarkTargeterDirty are read from the client; the rest reuse their last read.
function ThreatService:RebuildTargeterCounts(onlyDirty)
    local readAll = not onlyDirty or self.allTargetersDirty
    self.allTargetersDirty = false
    for guid in pairs(self.attackerCounts) do self.attackerCounts[guid] = nil end
    for index = 1, self.attackerTargetCount do
        local bucket = self.attackerTargetOrder[index]
        self.attackerTargets[bucket.guid] = nil
        bucket.guid = nil
        bucket.count = 0
    end
    self.attackerTargetCount = 0

    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if member.isMember then
            if readAll or member.targetDirty then
                member.targetGUID = ReadGUID(member.targetToken)
                member.targetDirty = false
            end
            local targetGUID = member.targetGUID
            if targetGUID then
                local bucket = self.attackerTargets[targetGUID]
                if not bucket and self.attackerTargetCount < MAX_ATTACKER_TARGETS then
                    self.attackerTargetCount = self.attackerTargetCount + 1
                    bucket = self.attackerTargetPool[self.attackerTargetCount]
                    bucket.guid = targetGUID
                    bucket.count = 0
                    self.attackerTargetOrder[self.attackerTargetCount] = bucket
                    self.attackerTargets[targetGUID] = bucket
                end
                if bucket and bucket.count < MAX_ATTACKERS_PER_TARGET then
                    bucket.count = bucket.count + 1
                    bucket.names[bucket.count] = member.name
                    bucket.units[bucket.count] = member.unit
                    self.attackerCounts[targetGUID] = bucket.count
                end
            end
        end
    end
end

function ThreatService:ExpireEngagements(now)
    now = tonumber(now) or Now()
    local nextExpiry
    -- An expired record is re-read; the snapshot changes only if what it shows does.
    for enemyIndex = 1, self.enemyCount do
        local record = self.enemyOrder[enemyIndex]
        if record.unitDamageAt then
            if now - record.unitDamageAt < ENGAGEMENT_WINDOW then
                local expiry = record.unitDamageAt + ENGAGEMENT_WINDOW
                if not nextExpiry or expiry < nextExpiry then nextExpiry = expiry end
            else
                record.unitDamageAt = nil
                record.dirty = true
            end
        end
    end
    self.nextEngagementExpiry = nextExpiry
end

function ThreatService:RecordUnitDamage(unit)
    local token = ReadableToken(unit)
    local record = token and self.enemyByUnit[token] or nil
    if not record then return false end
    local now = Now()
    record.unitDamageAt = now
    record.dirty = true
    self:Hurry()
    local expiry = now + ENGAGEMENT_WINDOW
    if not self.nextEngagementExpiry or expiry < self.nextEngagementExpiry then
        self.nextEngagementExpiry = expiry
    end
    return true
end

function ThreatService:UpdateRecordGUID(record)
    local guid = ReadGUID(record.unit)
    if record.guid and record.guid ~= guid and self.enemyByGUID[record.guid] == record then
        self.enemyByGUID[record.guid] = nil
    end
    -- knownGUID survives unreadable reads, so a GUID that is only briefly
    -- withheld keeps its history while a genuinely different mob starts clean.
    if guid and record.knownGUID and guid ~= record.knownGUID then
        record.unitDamageAt = nil
        self.nextRecordSerial = self.nextRecordSerial + 1
        record.serial = self.nextRecordSerial
    end
    if guid then record.knownGUID = guid end
    record.guid = guid
    if guid then self.enemyByGUID[guid] = record end
end

function ThreatService:UpdateEngaged(record)
    local engaged = type(record.unitDamageAt) == "number" and Now() - record.unitDamageAt < ENGAGEMENT_WINDOW
    if not engaged then engaged = ReadBoolean(UnitAffectingCombat, record.unit) == true end
    if not engaged and (record.tanking == true or (type(record.status) == "number" and record.status > 0)) then
        engaged = true
    end
    record.engaged = engaged
end

-- Who is attacking: the mob took damage recently, so the members targeting it are inferred to be
-- the ones hitting it (the client names no damage source).
function ThreatService:UpdateActiveAttackers(record)
    local count = 0
    if record.unitDamageAt and Now() - record.unitDamageAt < ENGAGEMENT_WINDOW then
        local bucket = record.guid and self.attackerTargets[record.guid] or nil
        for index = 1, bucket and bucket.count or 0 do
            count = count + 1
            record.activeAttackerNames[count] = bucket.names[index]
            record.activeAttackerUnits[count] = bucket.units[index]
        end
    end
    for index = count + 1, record.activeAttackerCount or 0 do
        record.activeAttackerNames[index] = nil
        record.activeAttackerUnits[index] = nil
    end
    record.activeAttackerCount = count
end

-- The roster entry the mob is targeting: matched by GUID, and by UnitIsUnit only against members
-- whose GUID the client withheld (or when the target's own GUID is withheld).
function ThreatService:FindHolder(targetUnit)
    local guid = ReadGUID(targetUnit)
    if guid then
        local entry = self.rosterByGUID[guid]
        if entry or self.rosterMissingGUID == 0 then return entry end
    end
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if (not guid or not member.guid) and SameUnit(targetUnit, member.unit) then return member end
    end
    return nil
end

function ThreatService:FindTarget(record)
    if not record.engaged then
        record.targetName, record.targetUnit = L["No target"], nil
        record.tankHolds, record.selfHolds, record.loose = false, false, false
        record.holdState = "IDLE"
        return
    end
    local targetUnit = record.targetToken
    if not UnitExistsSafely(targetUnit) then
        record.targetName, record.targetUnit = L["No target"], nil
        record.tankHolds, record.selfHolds, record.loose = false, false, true
        record.holdState = "LOOSE"
        return
    end

    local member = self:FindHolder(targetUnit)
    if member then
        record.targetName = member.name
        record.targetUnit = member.unit
        record.tankHolds = member.role == "TANK"
        record.selfHolds = self.isSolo and (member.isPlayer or member.owner == "player")
        record.loose = not record.tankHolds and not record.selfHolds
        record.holdState = record.tankHolds and "TANK" or record.selfHolds and "YOU" or "LOOSE"
        return
    end

    record.targetName = ReadName(targetUnit, L["Unknown target"])
    record.targetUnit = nil
    record.tankHolds, record.selfHolds, record.loose = false, false, true
    record.holdState = "LOOSE"
end

-- One roster member's UnitDetailedThreatSituation on mob. Reads on the player's target are kept
-- for the rest of this refresh pass (threatPass), so the group read reuses ReadThreat's sweep
-- instead of asking the client again. The cached values may be protected; they are only returned.
function ThreatService:ReadMemberThreat(index, unit, mob)
    local tuple = self.threatTuples[index]
    if mob ~= "target" then return pcall(UnitDetailedThreatSituation, unit, mob) end
    if tuple.pass == self.threatPass then
        return tuple.ok, tuple.tanking, tuple.status, tuple.scaled, tuple.rawPercent, tuple.raw
    end
    local ok, tanking, status, scaled, rawPercent, raw = pcall(UnitDetailedThreatSituation, unit, mob)
    tuple.pass, tuple.ok = self.threatPass, ok
    tuple.tanking, tuple.status, tuple.scaled, tuple.rawPercent, tuple.raw = tanking, status, scaled, rawPercent, raw
    return ok, tanking, status, scaled, rawPercent, raw
end

-- The highest raw threat any other roster member holds on mob, or nil plus the state and the
-- unit that blocked it. A complete nil tuple means that actor has no entry on this mob's threat
-- table (members and pets alike; nobody has to attack or be in combat). A partial, protected, or
-- errored tuple is not evidence of zero.
function ThreatService:ScanGroupThreat(mob)
    local highestOther = 0
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if not member.isPlayer then
            local ok, tanking, status, scaled, percent, raw = self:ReadMemberThreat(index, member.unit, mob)
            if not ok or not IsReadable(raw) then
                return nil, IsSecret(raw) and "protected-group-threat" or "group-threat-unavailable", member.unit
            end
            if raw == nil then
                if not IsNoEntry(tanking, status, scaled, percent, raw) then
                    return nil, "group-threat-unavailable", member.unit
                end
            elseif type(raw) ~= "number" then
                return nil, "group-threat-unavailable", member.unit
            elseif raw > highestOther then
                highestOther = raw
            end
        end
    end
    return highestOther
end

-- The group scan for this record: read now when it is a priority or the last one is too old,
-- else the cached result (kept per record and invalidated by a new mob or a roster change).
function ThreatService:GroupHighest(record, mob, priority)
    local now = Now()
    if priority or record.groupScanSerial ~= record.serial or record.groupScanRoster ~= self.rosterRevision
        or not record.groupScanAt or now - record.groupScanAt >= GROUP_SCAN_INTERVAL then
        record.groupHighest, record.groupBlockedState, record.groupBlocker = self:ScanGroupThreat(mob)
        record.groupScanAt, record.groupScanSerial, record.groupScanRoster = now, record.serial, self.rosterRevision
        self.groupScans = self.groupScans + 1
    end
    return record.groupHighest, record.groupBlockedState, record.groupBlocker
end

-- Read on every refresh: the player's target and focus, and enemies a shown tank window lists.
function ThreatService:IsPriority(record, targetMatched)
    if targetMatched then return true end
    local console = PS.ThreatConsole
    if console and console.watchedRecords and console.watchedRecords[record] then return true end
    return SameUnit(record.unit, "focus")
end

function ThreatService:ReadThreat(record)
    self.threatPass = self.threatPass + 1
    record.playerPercent, record.playerDifferential = nil, nil
    record.percent, record.lead = nil, nil
    record.leadKind = nil
    record.percentOpaque, record.hasOpaquePercent = nil, false
    record.rawThreat, record.rawThreatOpaque, record.hasOpaqueRawThreat = nil, nil, false
    record.leadPercent, record.leadPercentOpaque, record.hasOpaqueLeadPercent = nil, nil, false
    record.leadSituation, record.leadSituationOpaque, record.hasOpaqueLeadSituation = nil, nil, false
    record.rawThreatState, record.leadPercentState, record.leadSituationState = "unavailable", "unavailable", "unavailable"
    record.differentialState = "unavailable"
    record.differentialBlocker = nil
    record.tanking, record.status = nil, nil
    record.playerThreatNoEntry = false

    -- Forever can expose readable threat through the player's target while the
    -- equivalent nameplate token remains protected. Only borrow that token for
    -- the exact current mob; never match by name or infer an arbitrary GUID.
    local targetMatched = SameUnit(record.unit, "target")
    local mob = targetMatched and "target" or record.unit
    record.threatMobSource = targetMatched and "target" or "nameplate"
    record.leadPercent, record.leadPercentOpaque, record.leadPercentState =
        ReadThreatValue(UnitThreatPercentageOfLead, "player", mob)
    record.hasOpaqueLeadPercent = record.leadPercentState == "protected/displayable"
    record.leadSituation, record.leadSituationOpaque, record.leadSituationState =
        ReadThreatValue(UnitThreatLeadSituation, "player", mob)
    record.hasOpaqueLeadSituation = record.leadSituationState == "protected/displayable"

    if type(UnitDetailedThreatSituation) ~= "function" then return end

    local ok, tanking, status, scaledPercent, rawPercent, raw
    if self.playerRosterIndex then
        ok, tanking, status, scaledPercent, rawPercent, raw = self:ReadMemberThreat(self.playerRosterIndex, "player", mob)
    else
        ok, tanking, status, scaledPercent, rawPercent, raw = pcall(UnitDetailedThreatSituation, "player", mob)
    end
    if not ok then return end
    -- A complete nil tuple is no player entry on this mob, even if Forever's
    -- lead API separately reports a readable zero. Do not suppress partial or
    -- protected tuples: they may still contain displayable threat.
    if IsNoEntry(tanking, status, scaledPercent, rawPercent, raw) then
        record.playerThreatNoEntry = true
        record.leadPercent, record.leadPercentOpaque, record.hasOpaqueLeadPercent = nil, nil, false
        record.leadSituation, record.leadSituationOpaque, record.hasOpaqueLeadSituation = nil, nil, false
        record.leadPercentState, record.leadSituationState = "no-entry", "no-entry"
        record.differentialState = "player-threat-no-entry"
        record.differentialBlocker = "player"
        return
    end
    if IsReadable(tanking) and type(tanking) == "boolean" then record.tanking = tanking end
    if IsReadable(status) and type(status) == "number" then record.status = status end
    if IsReadable(scaledPercent) and type(scaledPercent) == "number" then
        record.playerPercent = scaledPercent
        record.percent = scaledPercent
    elseif IsSecret(scaledPercent) then
        record.percentOpaque = scaledPercent
        record.hasOpaquePercent = true
    end
    if IsReadable(raw) and type(raw) == "number" then
        record.rawThreat = raw
        record.rawThreatState = "readable"
    elseif IsSecret(raw) then
        record.rawThreatOpaque = raw
        record.hasOpaqueRawThreat = true
        record.rawThreatState = "protected/displayable"
    else
        record.rawThreatState = "unavailable"
    end
    if not IsReadable(raw) or type(raw) ~= "number" then
        record.differentialState = IsSecret(raw) and "protected-player-threat" or "player-threat-unavailable"
        record.differentialBlocker = "player"
        return
    end

    local highestOther, blockedState, blocker = self:GroupHighest(record, mob, self:IsPriority(record, targetMatched))
    if not highestOther then
        record.differentialState, record.differentialBlocker = blockedState, blocker
        return
    end
    -- The roster scan cannot see threat held outside the group. While another
    -- unit holds the mob, rawPercent is the player's threat as a share of the
    -- holder's, which recovers the holder's total whoever it is.
    if record.tanking == false then
        local holder = IsReadable(rawPercent) and type(rawPercent) == "number" and rawPercent > 0
            and raw * 100 / rawPercent or nil
        if holder and holder > highestOther then
            highestOther = holder
        elseif not holder and highestOther <= raw then
            record.differentialState = "external-holder"
            record.differentialBlocker = "holder"
            return
        end
    elseif record.tanking == true and record.status == 2 and highestOther <= raw then
        -- Status 2 means another unit has more threat; none of the group does.
        record.differentialState = "external-higher"
        record.differentialBlocker = "outside-group"
        return
    end
    if targetMatched and not SameUnit(record.unit, "target") then
        record.differentialState = "target-changed"
        return
    end
    record.playerDifferential = raw - highestOther
    -- The signed lead shown (plates, windows, PS.Threat.GetGap), both by the melee rule (130% at
    -- range; the melee margin is the safe one). Holding the mob ("tank"): the margin before the
    -- next highest reaches 110% of your threat, so positive is safe even while someone has more
    -- raw threat; alone on its table, the margin against 0. Not holding it ("pull"): how far you
    -- are from pulling it, 110% of the holder's threat.
    if record.tanking == true then
        record.lead = math.floor(raw * 1.1 - highestOther + 0.5)
        record.leadKind = "tank"
    else
        record.lead = math.floor(raw - highestOther * 1.1 + 0.5)
        record.leadKind = "pull"
    end
    record.differentialState = "readable"
end

local function GroupThreatSort(left, right)
    if left.percent ~= right.percent then return left.percent > right.percent end
    return left.order < right.order
end

-- Every roster member's threat on the player's current target, for the threat meter windows.
-- Only the confirmed current target is read (the token Forever makes readable most often).
-- Protected values are kept opaque for display sinks; the gap to pulling (the holder's raw
-- threat x 1.1, the melee rule) and the order are only calculated from readable numbers.
function ThreatService:ReadGroupThreat(record)
    local count, holderRaw, allReadable = 0, nil, true
    self.groupThreatRecord = record
    if type(UnitDetailedThreatSituation) == "function" then
        for index = 1, self.rosterCount do
            local member = self.rosterPool[index]
            local ok, tanking, status, scaled, rawPercent, raw = self:ReadMemberThreat(index, member.unit, "target")
            -- A complete, readable nil tuple is no entry on this mob's table: no row.
            if ok and not IsNoEntry(tanking, status, scaled, rawPercent, raw) then
                count = count + 1
                local entry = self.groupThreat[count]
                entry.unit, entry.name, entry.role = member.unit, member.name, member.role
                entry.isPlayer, entry.isPet, entry.order = member.isPlayer, not member.isMember, index
                entry.classToken = member.classToken
                entry.tanking = nil
                if IsReadable(tanking) and type(tanking) == "boolean" then entry.tanking = tanking end
                entry.percent, entry.percentOpaque, entry.hasOpaquePercent = nil, nil, false
                if IsReadable(scaled) and type(scaled) == "number" then
                    entry.percent = scaled
                elseif IsSecret(scaled) then
                    entry.percentOpaque, entry.hasOpaquePercent = scaled, true
                end
                if entry.percent == nil then allReadable = false end
                entry.raw, entry.rawOpaque, entry.hasOpaqueRaw, entry.gap = nil, nil, false, nil
                if IsReadable(raw) and type(raw) == "number" then
                    entry.raw = raw
                    if entry.tanking == true then holderRaw = raw end
                elseif IsSecret(raw) then
                    entry.rawOpaque, entry.hasOpaqueRaw = raw, true
                end
            end
        end
    end
    for index = count + 1, self.groupThreatCount do
        local entry = self.groupThreat[index]
        entry.unit, entry.name, entry.percentOpaque, entry.rawOpaque = nil, nil, nil, nil
    end
    self.groupThreatCount = count
    -- Gaps follow the lead's rules (see ReadThreat): the holder's margin over the highest other
    -- (known only when every other total is readable), everyone else's distance to pulling. Your
    -- own row takes your lead, which also counts a holder outside the group.
    local highestOther = 0
    for index = 1, count do
        local entry = self.groupThreat[index]
        if entry.tanking ~= true then
            if entry.raw == nil then
                highestOther = nil
                break
            elseif entry.raw > highestOther then
                highestOther = entry.raw
            end
        end
    end
    for index = 1, count do
        local entry = self.groupThreat[index]
        if entry.isPlayer and type(record.lead) == "number" then
            entry.gap = record.lead
        elseif entry.raw and entry.tanking == true and highestOther then
            entry.gap = math.floor(entry.raw * 1.1 - highestOther + 0.5)
        elseif entry.raw and entry.tanking == false and holderRaw then
            entry.gap = math.floor(entry.raw - holderRaw * 1.1 + 0.5)
        end
    end
    if allReadable and count > 1 then
        -- Sorting a slice of the pool in place: copy into the scratch list, sort, copy back.
        local scratch = self.groupThreatScratch
        for index = 1, count do scratch[index] = self.groupThreat[index] end
        for index = count + 1, #scratch do scratch[index] = nil end
        table.sort(scratch, GroupThreatSort)
        for index = 1, count do self.groupThreat[index] = scratch[index] end
    end
    self.groupThreatRevision = self.groupThreatRevision + 1
end

-- A failed group read shows no rows rather than half-updated ones.
function ThreatService:ReadGroupThreatSafely(record)
    if pcall(self.ReadGroupThreat, self, record) then return true end
    self.groupThreatCount = 0
    self.groupThreatRevision = self.groupThreatRevision + 1
    return false
end

-- Reads now, or marks the read pending until the interval has passed (the service tick does it).
function ThreatService:RequestGroupThreat(record)
    local now = Now()
    if self.groupThreatRecord ~= record or not self.groupThreatReadAt or now - self.groupThreatReadAt >= GROUP_THREAT_INTERVAL then
        self.groupThreatReadAt, self.groupThreatPending = now, nil
        self:ReadGroupThreatSafely(record)
    else
        self.groupThreatPending = record
    end
end

function ThreatService:FlushGroupThreat(now)
    local record = self.groupThreatPending
    if not record or not self.groupThreatReadAt or (now or 0) - self.groupThreatReadAt < GROUP_THREAT_INTERVAL then return end
    self.groupThreatPending = nil
    if self.groupThreatWanted and record.unit and SameUnit(record.unit, "target") then
        self.groupThreatReadAt = now
        -- A later tick: nothing read in the last refresh pass may be reused.
        self.threatPass = self.threatPass + 1
        self:ReadGroupThreatSafely(record)
    end
end

-- The measured record, the row count and the pooled rows; nil and 0 when the player's target
-- has no tracked plate.
function ThreatService:GetGroupThreat()
    local record = self.groupThreatRecord
    if not record or not record.unit or not SameUnit(record.unit, "target") then return nil, 0, self.groupThreat end
    return record, self.groupThreatCount, self.groupThreat
end

-- Windows in threat meter mode ask for the group read; nobody else pays for it.
function ThreatService:SetGroupThreatWanted(wanted)
    wanted = wanted and true or false
    if wanted == self.groupThreatWanted then return end
    self.groupThreatWanted = wanted
    if wanted then
        for index = 1, self.enemyCount do
            local record = self.enemyOrder[index]
            if SameUnit(record.unit, "target") then record.dirty = true end
        end
        self:Hurry()
    else
        self.groupThreatRecord, self.groupThreatCount, self.groupThreatPending = nil, 0, nil
    end
end

local function ShownChanged(record)
    if record.hasOpaquePercent or record.hasOpaqueLeadPercent or record.hasOpaqueRawThreat
        or record.hasOpaqueLeadSituation then return true end
    local shown = record.shown
    for index = 1, #SHOWN_FIELDS do
        local field = SHOWN_FIELDS[index]
        if shown[field] ~= record[field] then return true end
    end
    return false
end

function ThreatService:RefreshRecord(record)
    if not record or not record.unit then return false end
    if self.rosterDirty or self.roleDirty then self:FlushPending() end
    if not IsVisibleHostile(record.root, record.unit) then
        self:UntrackEnemy(record.unit)
        return false
    end
    local shown = record.shown
    for index = 1, #SHOWN_FIELDS do
        local field = SHOWN_FIELDS[index]
        shown[field] = record[field]
    end

    record.enemyName = ReadName(record.unit, record.unit)
    self:UpdateRecordGUID(record)
    record.targeterCount = record.guid and (self.attackerCounts[record.guid] or 0) or nil
    -- A failed read must not leave the record dirty or skip the engagement and hold state below.
    if not pcall(self.ReadThreat, self, record) then
        record.differentialState, record.differentialBlocker = "error", nil
    end
    if self.groupThreatWanted and record.threatMobSource == "target" then self:RequestGroupThreat(record) end
    self:UpdateEngaged(record)
    self:UpdateActiveAttackers(record)
    self:FindTarget(record)
    record.dirty = false
    record.revision = record.revision + 1
    if ShownChanged(record) then self.snapshotDirty = true end
    return true
end

function ThreatService:TrackEnemy(unit, root)
    unit = ReadableToken(unit)
    if not unit then return nil end
    self:WakeTicker()
    root = root or (C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit))
    if not IsVisibleHostile(root, unit) then return nil end

    local record = self.enemyByUnit[unit]
    self:Hurry()
    if record then
        if record.root ~= root then self.snapshotDirty = true end
        record.root = root
        record.dirty = true
        return record
    end
    if self.enemyCount >= MAX_ENEMIES then return nil end

    if self.freeCount == 0 then return nil end
    record = self.freeRecords[self.freeCount]
    self.freeRecords[self.freeCount] = nil
    self.freeCount = self.freeCount - 1
    self.enemyCount = self.enemyCount + 1
    self.enemyOrder[self.enemyCount] = record
    self.enemyByUnit[unit] = record
    record.unit, record.root, record.targetToken = unit, root, TargetToken(unit)
    self.nextRecordSerial = self.nextRecordSerial + 1
    record.serial = self.nextRecordSerial
    record.dirty, record.revision = true, 0
    record.enemyName, record.targetName, record.targetUnit = unit, L["No target"], nil
    record.tankHolds, record.selfHolds, record.loose, record.engaged = false, false, false, false
    record.holdState = "IDLE"
    record.guid = ReadGUID(unit)
    record.knownGUID = record.guid
    record.targeterCount = nil
    record.activeAttackerCount = 0
    record.unitDamageAt = nil
    record.groupScanAt, record.groupHighest, record.groupBlockedState, record.groupBlocker = nil, nil, nil, nil
    if record.guid then self.enemyByGUID[record.guid] = record end
    record.playerPercent, record.playerDifferential = nil, nil
    record.playerThreatNoEntry = false
    record.percent, record.lead, record.tanking, record.status = nil, nil, nil, nil
    record.leadKind = nil
    record.percentOpaque, record.hasOpaquePercent = nil, false
    record.rawThreat, record.rawThreatOpaque, record.hasOpaqueRawThreat = nil, nil, false
    record.leadPercent, record.leadPercentOpaque, record.hasOpaqueLeadPercent = nil, nil, false
    record.leadSituation, record.leadSituationOpaque, record.hasOpaqueLeadSituation = nil, nil, false
    record.rawThreatState, record.leadPercentState, record.leadSituationState = "unavailable", "unavailable", "unavailable"
    record.differentialState = "unavailable"
    record.differentialBlocker = nil
    record.threatMobSource = "nameplate"
    self.snapshotDirty = true
    return record
end

function ThreatService:UntrackEnemy(unit)
    unit = ReadableToken(unit)
    local record = unit and self.enemyByUnit[unit]
    if not record then return end

    local removeIndex
    for index = 1, self.enemyCount do
        if self.enemyOrder[index] == record then
            removeIndex = index
            break
        end
    end
    if not removeIndex then return end

    local last = self.enemyOrder[self.enemyCount]
    self.enemyOrder[removeIndex] = last
    self.enemyOrder[self.enemyCount] = nil
    self.enemyCount = self.enemyCount - 1
    self.enemyByUnit[unit] = nil
    if record.guid and self.enemyByGUID[record.guid] == record then self.enemyByGUID[record.guid] = nil end
    if self.groupThreatRecord == record then self.groupThreatRecord, self.groupThreatCount = nil, 0 end
    if self.groupThreatPending == record then self.groupThreatPending = nil end
    for index = 1, record.activeAttackerCount or 0 do
        record.activeAttackerNames[index], record.activeAttackerUnits[index] = nil, nil
    end
    record.activeAttackerCount = 0
    record.unit, record.root, record.guid, record.dirty = nil, nil, nil, false
    self.freeCount = self.freeCount + 1
    self.freeRecords[self.freeCount] = record
    if self.cursor > self.enemyCount then self.cursor = 0 end
    self.snapshotDirty = true
end

local function IsGroupToken(unit)
    return unit == "player" or unit == "pet" or unit:match("^party") ~= nil or unit:match("^raid") ~= nil
end

function ThreatService:MarkDirty(unit)
    if unit ~= nil then
        local record = IsReadable(unit) and self.enemyByUnit[unit]
        if record then
            record.dirty = true
            self:Hurry()
            return
        end
        if IsReadable(unit) and type(unit) == "string" then
            -- Group tokens are never mobs; their target changes reach records
            -- through the targeter rebuild instead.
            if IsGroupToken(unit) then return end
            -- "target", "focus", "boss1"...: the plate the client names for it, else (when it will
            -- not say) every record the token matches.
            local known, token = PlateToken(unit)
            if known then
                record = token and self.enemyByUnit[token]
                if record then
                    record.dirty = true
                    self:Hurry()
                end
                return
            end
            self:Hurry()
            for index = 1, self.enemyCount do
                local candidate = self.enemyOrder[index]
                if SameUnit(candidate.unit, unit) then candidate.dirty = true end
            end
            return
        end
    end
    for index = 1, self.enemyCount do self.enemyOrder[index].dirty = true end
    self:Hurry()
end

-- The player's target changed: only the old target (the records last read through "target") and
-- the new one can read differently now.
function ThreatService:MarkTargetChanged()
    local known, token = PlateToken("target")
    if not known then return self:MarkDirty() end
    for index = 1, self.enemyCount do
        local record = self.enemyOrder[index]
        if record.threatMobSource == "target" or record.unit == token then record.dirty = true end
    end
    self:Hurry()
end

function ThreatService:RefreshUnit(unit)
    self:WakeTicker()
    local record = self.enemyByUnit[unit]
    if not record then
        record = self:TrackEnemy(unit)
    end
    if record then self:RefreshRecord(record) end
    return record
end

-- Refreshes immediately while this tick's budget lasts, so a burst of new
-- plates (a large pull or a loading screen) is spread over the batch refresh.
function ThreatService:RequestRefresh(unit)
    if self.immediateRefreshes < IMMEDIATE_REFRESH_BUDGET then
        self.immediateRefreshes = self.immediateRefreshes + 1
        return self:RefreshUnit(unit)
    end
    local record = self.enemyByUnit[unit] or self:TrackEnemy(unit)
    if record then
        record.dirty = true
        self:Hurry()
    end
    return record
end

function ThreatService:RefreshBatch(budget)
    local count = self.enemyCount
    if count == 0 then self.cursor, self.deadCursor = 0, 0 return 0 end
    local refreshed, visited = 0, 0
    local limit = math.min(tonumber(budget) or REFRESH_BUDGET, count)
    -- Look past clean records so a dirty one is never queued behind them.
    while visited < count and refreshed < limit and self.enemyCount > 0 do
        self.cursor = (self.cursor % self.enemyCount) + 1
        local record = self.enemyOrder[self.cursor]
        if record and record.dirty and self:RefreshRecord(record) then refreshed = refreshed + 1 end
        visited = visited + 1
    end
    -- A mob can die without a threat event; probe a few records per tick. Out of combat only
    -- engaged ones: an idle mob that dies (or leaves) takes its plate with it.
    local anyRecord = Secret.InCombat()
    for _ = 1, math.min(DEAD_PROBE_BUDGET, self.enemyCount) do
        if self.enemyCount == 0 then break end
        self.deadCursor = (self.deadCursor % self.enemyCount) + 1
        local record = self.enemyOrder[self.deadCursor]
        if record and (anyRecord or record.engaged) then
            self.deathProbes = (self.deathProbes or 0) + 1
            if ReadBoolean(UnitIsDeadOrGhost, record.unit) == true or ReadBoolean(UnitIsDead, record.unit) == true then
                self:RefreshRecord(record)
            end
        end
    end
    return refreshed
end

-- UNIT_TARGET fires for every group member's retarget; rebuild once per tick, read only the
-- members that retargeted, and only re-read the records whose targeters could have changed.
function ThreatService:FlushTargeters()
    if not self.targetersDirty then return end
    self.targetersDirty = false
    self:RebuildTargeterCounts(true)
    for index = 1, self.enemyCount do
        local record = self.enemyOrder[index]
        local count = record.guid and (self.attackerCounts[record.guid] or 0) or nil
        if record.engaged or count ~= record.targeterCount then record.dirty = true end
    end
end

function ThreatService:RefreshAllForTest()
    self:FlushTargeters()
    local index = 1
    while index <= self.enemyCount do
        local record = self.enemyOrder[index]
        if record and record.dirty then self:RefreshRecord(record) end
        if self.enemyOrder[index] == record then index = index + 1 end
    end
end

function ThreatService:GetEnemy(unit)
    if not self.tickerEnabled then self:WakeTicker() end
    return self.enemyByUnit[unit]
end

function ThreatService:GetPlayerRole()
    if self.rosterDirty or self.roleDirty then self:FlushPending() end
    return self.playerRole, self.playerRoleSource
end

local function GetTargeterBucket(service, unit)
    if type(unit) ~= "string" then return nil end
    if service.rosterDirty then service:FlushPending() end
    local record = service.enemyByUnit[unit]
    local guid = record and record.guid
    return guid and service.attackerTargets[guid] or nil
end

-- Group members whose current target is this enemy (see RebuildTargeterCounts).
function ThreatService:GetTargeterCount(unit)
    local bucket = GetTargeterBucket(self, unit)
    return bucket and bucket.count or 0
end

function ThreatService:GetTargeter(unit, index)
    if not IsReadable(index) or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
        return nil, nil
    end
    local bucket = GetTargeterBucket(self, unit)
    if not bucket or index > bucket.count then return nil, nil end
    return bucket.names[index], bucket.units[index]
end

function ThreatService:GetActiveAttackerCount(unit)
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    return record and record.activeAttackerCount or 0
end

-- The name and unit of an inferred attacker (see UpdateActiveAttackers).
function ThreatService:GetActiveAttacker(unit, index)
    if not IsReadable(index) or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
        return nil, nil
    end
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    if not record or index > record.activeAttackerCount then return nil, nil end
    return record.activeAttackerNames[index], record.activeAttackerUnits[index]
end

function ThreatService:IsCurrentPlate(unit, serial, root, guid)
    if type(unit) ~= "string" or type(serial) ~= "number" or not root then return false, "missing-row" end
    local record = self.enemyByUnit[unit]
    if not record or record.serial ~= serial or record.root ~= root
        or not IsVisibleHostile(root, unit) then return false, "stale-record" end
    if type(guid) == "string" and (record.guid ~= guid or ReadGUID(unit) ~= guid) then
        return false, "changed-guid"
    end
    local getPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    local ok, currentRoot = false, nil
    if type(getPlate) == "function" then ok, currentRoot = pcall(getPlate, unit) end
    local token = root.namePlateUnitToken
    if ok and currentRoot and currentRoot ~= root then return false, "changed-root" end
    if IsReadable(token) and token ~= nil and token ~= unit then return false, "changed-token" end
    -- Forever may protect the root token or make the lookup temporarily
    -- unavailable. Either independently confirmed identity is sufficient,
    -- together with the record's serial/root (and GUID when readable).
    if ok and currentRoot == root then return true end
    if IsReadable(token) and token == unit then return true end
    return false, "identity-unavailable"
end

function ThreatService:GetSnapshot()
    if self.snapshotDirty then
        local oldCount = self.snapshotCount
        local count, loose, engaged = 0, 0, 0
        for index = 1, self.enemyCount do
            local record = self.enemyOrder[index]
            if record and record.unit then
                count = count + 1
                self.snapshot[count] = record
                if record.loose then loose = loose + 1 end
                if record.engaged then engaged = engaged + 1 end
            end
        end
        for index = count + 1, oldCount do self.snapshot[index] = nil end
        table.sort(self.snapshot, SnapshotSort)
        self.snapshotCount = count
        self.totalVisible = count
        self.totalLoose = loose
        self.totalEngaged = engaged
        self.snapshotDirty = false
        self.snapshotRevision = self.snapshotRevision + 1
    end
    return self.snapshot, self.snapshotCount, self.totalVisible, self.totalLoose, self.totalEngaged
end

function ThreatService:ScanVisibleEnemies()
    if not C_NamePlate or type(C_NamePlate.GetNamePlates) ~= "function" then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for index = 1, #plates do
        local root = plates[index]
        self:TrackEnemy(root and root.namePlateUnitToken, root)
    end
end

local ROSTER_EVENTS = { GROUP_ROSTER_UPDATE = true, PLAYER_ROLES_ASSIGNED = true, PLAYER_ENTERING_WORLD = true,
    UNIT_PET = true }
-- A form or aura only matters as tank evidence; talents (and a new pull) can also change the spec.
local EVIDENCE_EVENTS = { UPDATE_SHAPESHIFT_FORM = true, UNIT_AURA = true }
local ROLE_EVENTS = { CHARACTER_POINTS_CHANGED = true, PLAYER_TALENT_UPDATE = true, PLAYER_REGEN_DISABLED = true }

-- With nothing reading threat, events only note what must be redone on waking: a plate
-- removal is applied (it is cheap and leaves no stale record), additions are rescanned, and
-- the roster and role are rebuilt.
function ThreatService:NoteWhileAsleep(event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        self:UntrackEnemy(unit)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        self.platesDirty = true
    elseif ROSTER_EVENTS[event] then
        self.rosterDirty = true
        if event == "PLAYER_ENTERING_WORLD" then self.platesDirty = true end
    elseif ROLE_EVENTS[event] or event == "UPDATE_SHAPESHIFT_FORM"
        or (event == "UNIT_AURA" and IsReadable(unit) and unit == "player") then
        self.roleDirty = true
    end
    self.missedEvents = true
end

function ThreatService:HandleEvent(event, unit, action)
    if not self.eventsEnabled then return end
    if not self.tickerEnabled then
        self:WakeTicker()
        if not self.tickerEnabled then return self:NoteWhileAsleep(event, unit) end
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        self:TrackEnemy(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        self:UntrackEnemy(unit)
    elseif ROSTER_EVENTS[event] then
        self:MarkRosterDirty()
    elseif EVIDENCE_EVENTS[event] then
        -- A stance, form or aura can make the player the tank (or stop it), but only as evidence.
        if (event ~= "UNIT_AURA" or (IsReadable(unit) and unit == "player")) and self:TankEvidenceMatters() then
            self:MarkRoleDirty()
        end
    elseif ROLE_EVENTS[event] then
        -- Talents change the spec's role; the spec can also change between pulls without a roster event.
        self:MarkRoleDirty()
    elseif event == "UNIT_TARGET" then
        self:MarkTargeterDirty(unit)
        self:MarkDirty(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        self:MarkTargeterDirty("player")
        self:MarkTargetChanged()
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        self:MarkDirty(unit)
    elseif event == "UNIT_COMBAT" and IsReadable(action) and action == "WOUND" then
        self:RecordUnitDamage(unit)
    end
end

function ThreatService:HasActiveConsumer()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    if not settings or settings.threat ~= false then return true end
    local console = PS.ThreatConsole
    return console and type(console.IsShown) == "function" and console:IsShown() or false
end

-- The service tick runs only while enabled and something reads threat (plates showing it, or a
-- shown threat window). It stops itself when nothing does; plate lookups, events and the windows
-- start it again. Records may be stale after a pause, so waking marks them all for a re-read.
function ThreatService:SyncTicker()
    local wanted = self.eventsEnabled == true and self:HasActiveConsumer()
    if wanted ~= self.tickerEnabled then
        self.tickerEnabled = wanted
        if PS.Ticker then PS.Ticker.SetEnabled("threat.service", wanted) end
        if wanted then self:Wake() end
    end
    return wanted
end

-- Catches up with what was skipped while nothing read threat, then re-reads every record.
function ThreatService:Wake()
    if self.platesDirty then
        self.platesDirty = false
        self:ScanVisibleEnemies()
    end
    if self.missedEvents then
        -- Retargets were not followed while asleep.
        self.missedEvents = false
        self.allTargetersDirty, self.targetersDirty = true, true
    end
    self:FlushPending()
    self:MarkDirty()
end

function ThreatService:WakeTicker()
    if not self.tickerEnabled and self.eventsEnabled then self:SyncTicker() end
end

function ThreatService:OnUpdate()
    if not self:HasActiveConsumer() then
        self:SyncTicker()
        return
    end
    local now = Now()
    self:FlushPending()
    if self.nextEngagementExpiry and now >= self.nextEngagementExpiry then
        self:ExpireEngagements(now)
    end
    self:FlushTargeters()
    if self.groupThreatPending then self:FlushGroupThreat(now) end
    self:RefreshBatch(REFRESH_BUDGET)
    self:PaceTicker()
end

-- Something is still waiting to be re-read.
function ThreatService:HasPendingWork()
    if self.targetersDirty or self.groupThreatPending or self.rosterDirty or self.roleDirty then return true end
    for index = 1, self.enemyCount do
        if self.enemyOrder[index].dirty then return true end
    end
    return false
end

-- Idle out of combat, the tick slows to IDLE_INTERVAL; anything marked dirty hurries it back.
function ThreatService:PaceTicker()
    local interval = (Secret.InCombat() or self:HasPendingWork()) and REFRESH_INTERVAL or IDLE_INTERVAL
    if interval ~= self.tickInterval then
        self.tickInterval = interval
        if PS.Ticker then PS.Ticker.SetInterval("threat.service", interval) end
    end
end

function ThreatService:OnInitialize()
    self.enemyByUnit = {}
    self.enemyByGUID = {}
    self.enemyOrder = {}
    self.freeRecords = {}
    for index = 1, MAX_ENEMIES do
        self.freeRecords[index] = {
            revision = 0,
            activeAttackerCount = 0,
            activeAttackerNames = {},
            activeAttackerUnits = {},
            shown = {},
        }
    end
    self.freeCount = MAX_ENEMIES
    self.rosterPool = {}
    self.rosterByGUID = {}
    self.rosterByUnit = {}
    self.threatTuples = {}
    for index = 1, MAX_ROSTER_UNITS do
        self.rosterPool[index] = {}
        self.threatTuples[index] = {}
    end
    self.attackerCounts = {}
    self.attackerTargets = {}
    self.attackerTargetOrder = {}
    self.attackerTargetPool = {}
    self.attackerTargetCount = 0
    for index = 1, MAX_ATTACKER_TARGETS do
        self.attackerTargetPool[index] = { names = {}, units = {}, count = 0 }
    end
    self.snapshot = {}
    self.groupThreat, self.groupThreatScratch = {}, {}
    for index = 1, MAX_ROSTER_UNITS do self.groupThreat[index] = {} end
    self:RebuildRoster()
    self:RebuildTargeterCounts()
end

function ThreatService:OnEnable()
    self.eventsEnabled = true
    self:ScanVisibleEnemies()
    self:MarkDirty()
    self:SyncTicker()
end

function ThreatService:OnDisable()
    self.eventsEnabled = false
    -- Plate events are ignored while disabled, so kept records would go stale;
    -- OnEnable rescans the visible plates.
    while self.enemyCount > 0 do self:UntrackEnemy(self.enemyOrder[self.enemyCount].unit) end
    self:SyncTicker()
end

ThreatService._Test = {
    IsSecret = IsSecret,
    RefreshInterval = REFRESH_INTERVAL,
    IdleInterval = IDLE_INTERVAL,
    RefreshBudget = REFRESH_BUDGET,
    EngagementWindow = ENGAGEMENT_WINDOW,
    GroupScanInterval = GROUP_SCAN_INTERVAL,
}

-- Register once while the addon file is loading, then gate delivery with
-- eventsEnabled so module enable/disable never mutates event subscriptions.
ThreatService.frame = CreateFrame("Frame")
ThreatService.frame:SetScript("OnEvent", function(_, event, ...)
    ThreatService:HandleEvent(event, ...)
end)
PS.Ticker.Register("threat.service", REFRESH_INTERVAL, function()
    ThreatService.immediateRefreshes = 0
    if ThreatService.eventsEnabled then ThreatService:OnUpdate() end
end)
PS.Ticker.SetEnabled("threat.service", false)
for index = 1, #SERVICE_EVENTS do
    PS._RegisterEvent(ThreatService.frame, SERVICE_EVENTS[index], "platesmith.threat-service")
end
-- Only the player's auras matter (tank evidence); the unit filter keeps a raid's aura churn out.
do
    local frame = ThreatService.frame
    local ok, accepted = false, false
    if type(frame.RegisterUnitEvent) == "function" then
        ok, accepted = pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player")
    end
    if not ok or accepted == false then PS._RegisterEvent(frame, "UNIT_AURA", "platesmith.threat-service") end
end

local registered = PS:RegisterModule("platesmith.threat-service", ThreatService)
if registered then PS.ThreatService = registered end

-- For plates: the signed gap the threat windows show (see ReadThreat), as gap, kind. kind is
-- "tank" while you hold the mob (your margin before anyone pulls it) or "pull" (how far you are
-- from pulling it). nil when the mob is not tracked or the numbers are unknown or protected.
-- unit is a plate's unit token or the mob's GUID.
PS.Threat = PS.Threat or {}
function PS.Threat.GetGap(unit)
    local key = ReadableToken(unit)
    if not key then return nil end
    local record = ThreatService.enemyByUnit and (ThreatService.enemyByUnit[key] or ThreatService.enemyByGUID[key])
    if not record then
        local guid = ReadGUID(key)
        record = guid and ThreatService.enemyByGUID and ThreatService.enemyByGUID[guid]
    end
    if not record or not record.unit or type(record.lead) ~= "number" or not record.leadKind then return nil end
    return record.lead, record.leadKind
end
