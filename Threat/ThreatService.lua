local _, PS = ...

if not PS or type(PS.RegisterModule) ~= "function" then return end

local REFRESH_INTERVAL = 0.05
local REFRESH_BUDGET = 2
local MAX_ENEMIES = 40
local MAX_ROSTER_UNITS = 82
local MAX_ATTACKER_TARGETS = 40
local MAX_ATTACKERS_PER_TARGET = 40
local ENGAGEMENT_WINDOW = 5
local DAMAGE_EVENT_SUFFIX = "_DAMAGE"

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
    "UNIT_COMBAT",
}

local ThreatService = {
    elapsed = 0,
    cursor = 0,
    enemyCount = 0,
    rosterCount = 0,
    snapshotCount = 0,
    totalVisible = 0,
    totalLoose = 0,
    totalEngaged = 0,
    snapshotDirty = true,
    isSolo = true,
    nextRecordSerial = 0,
}

local function IsReadable(value)
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        return ok and readable == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret ~= true
    end
    return true
end

local function IsSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
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

local function ReadBoolean(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if not ok or not IsReadable(value) then return nil end
    if value == nil then return false end
    return value and true or false
end

local function UnitExistsSafely(unit)
    return ReadBoolean(UnitExists, unit) == true
end

local function SameUnit(left, right)
    if type(UnitIsUnit) ~= "function" then return false end
    local ok, same = pcall(UnitIsUnit, left, right)
    return ok and IsReadable(same) and same and true or false
end

local function ReadName(unit, fallback)
    if type(UnitName) ~= "function" then return fallback end
    local ok, name = pcall(UnitName, unit)
    if ok and IsReadable(name) and type(name) == "string" and name ~= "" then
        return name
    end
    return fallback
end

local function ReadGUID(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if ok and IsReadable(guid) and type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

local function ReadRole(unit)
    if type(UnitGroupRolesAssigned) ~= "function" then return "NONE" end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if ok and IsReadable(role) and type(role) == "string" then return role end
    return "NONE"
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
    entry.owner = owner or unit
    entry.role = ReadRole(entry.owner)
    entry.name = ReadName(unit, unit)
    entry.guid = ReadGUID(unit)
    entry.isMember = isMember and true or false
    entry.isPlayer = unit == "player" or SameUnit(unit, "player")
    if entry.guid then self.rosterByGUID[entry.guid] = entry end
end

function ThreatService:RebuildRoster()
    local oldCount = self.rosterCount
    self.rosterCount = 0
    for guid in pairs(self.rosterByGUID) do self.rosterByGUID[guid] = nil end

    local raid = ReadBoolean(IsInRaid) == true
    local groupCount = 0
    if raid and type(GetNumGroupMembers) == "function" then
        local ok, value = pcall(GetNumGroupMembers)
        if ok and IsReadable(value) and type(value) == "number" then
            groupCount = math.min(value, 40)
        end
        for index = 1, groupCount do
            self:AddRosterUnit("raid" .. index, nil, true)
            self:AddRosterUnit("raidpet" .. index, "raid" .. index, false)
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
            self:AddRosterUnit("party" .. index, nil, true)
            self:AddRosterUnit("partypet" .. index, "party" .. index, false)
        end
    end

    self.isSolo = not raid and groupCount == 0

    for index = self.rosterCount + 1, oldCount do
        local entry = self.rosterPool[index]
        entry.unit, entry.owner, entry.role, entry.name, entry.guid = nil, nil, nil, nil, nil
        entry.isMember, entry.isPlayer = nil, nil
    end

    self.playerRole = "NONE"
    for index = 1, self.rosterCount do
        local entry = self.rosterPool[index]
        if entry.isPlayer then
            self.playerRole = entry.role
            break
        end
    end
    if self.playerRole == "NONE" and type(GetSpecialization) == "function"
        and type(GetSpecializationRole) == "function" then
        local ok, specialization = pcall(GetSpecialization)
        if ok and IsReadable(specialization) and type(specialization) == "number" then
            local roleOK, role = pcall(GetSpecializationRole, specialization)
            if roleOK and IsReadable(role) and type(role) == "string" then self.playerRole = role end
        end
    end
end

function ThreatService:RebuildTargeterCounts()
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
            local targetGUID = ReadGUID(member.unit .. "target")
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

-- Backward-compatible alias for early modules built against the alpha API.
function ThreatService:RebuildAttackerCounts()
    return self:RebuildTargeterCounts()
end

local function ClearEngagers(record)
    for index = 1, record.engagerCount or 0 do
        record.engagerKeys[index] = nil
        record.engagerNames[index] = nil
        record.engagerUnits[index] = nil
        record.engagerLastHit[index] = nil
    end
    record.engagerCount = 0
end

function ThreatService:ExpireEngagements(now)
    now = tonumber(now) or (type(GetTime) == "function" and GetTime()) or 0
    local nextExpiry
    local anyChanged = false
    for enemyIndex = 1, self.enemyCount do
        local record = self.enemyOrder[enemyIndex]
        local write = 1
        local changed = false
        if record.unitDamageAt then
            if now - record.unitDamageAt < ENGAGEMENT_WINDOW then
                local expiry = record.unitDamageAt + ENGAGEMENT_WINDOW
                if not nextExpiry or expiry < nextExpiry then nextExpiry = expiry end
            else
                record.unitDamageAt = nil
                changed = true
            end
        end
        for read = 1, record.engagerCount or 0 do
            local lastHit = record.engagerLastHit[read]
            if type(lastHit) == "number" and now - lastHit < ENGAGEMENT_WINDOW then
                if write ~= read then
                    record.engagerKeys[write] = record.engagerKeys[read]
                    record.engagerNames[write] = record.engagerNames[read]
                    record.engagerUnits[write] = record.engagerUnits[read]
                    record.engagerLastHit[write] = lastHit
                end
                local expiry = lastHit + ENGAGEMENT_WINDOW
                if not nextExpiry or expiry < nextExpiry then nextExpiry = expiry end
                write = write + 1
            else
                changed = true
            end
        end
        for clear = write, record.engagerCount or 0 do
            record.engagerKeys[clear] = nil
            record.engagerNames[clear] = nil
            record.engagerUnits[clear] = nil
            record.engagerLastHit[clear] = nil
        end
        local count = write - 1
        if count ~= (record.engagerCount or 0) then changed = true end
        record.engagerCount = count
        if changed then
            record.dirty = true
            anyChanged = true
        end
    end
    self.nextEngagementExpiry = nextExpiry
    if anyChanged then self.snapshotDirty = true end
end

function ThreatService:RecordUnitDamage(unit)
    local record = type(unit) == "string" and self.enemyByUnit[unit] or nil
    if not record then return false end
    local now = type(GetTime) == "function" and GetTime() or 0
    record.unitDamageAt = now
    record.dirty = true
    self.snapshotDirty = true
    local expiry = now + ENGAGEMENT_WINDOW
    if not self.nextEngagementExpiry or expiry < self.nextEngagementExpiry then
        self.nextEngagementExpiry = expiry
    end
    return true
end

function ThreatService:RecordDamage(sourceGUID, destGUID)
    if type(sourceGUID) ~= "string" or type(destGUID) ~= "string" then return false end
    local source = self.rosterByGUID[sourceGUID]
    local record = self.enemyByGUID[destGUID]
    if not source or not record then return false end

    local ownerUnit = source.owner or source.unit
    local ownerGUID = ReadGUID(ownerUnit) or sourceGUID
    local ownerName = ReadName(ownerUnit, source.name or ownerUnit)
    local now = type(GetTime) == "function" and GetTime() or 0
    local found
    for index = 1, record.engagerCount do
        if record.engagerKeys[index] == ownerGUID then
            found = index
            break
        end
    end
    if not found and record.engagerCount < MAX_ATTACKERS_PER_TARGET then
        record.engagerCount = record.engagerCount + 1
        found = record.engagerCount
    end
    if not found then return false end

    record.engagerKeys[found] = ownerGUID
    record.engagerNames[found] = ownerName
    record.engagerUnits[found] = ownerUnit
    record.engagerLastHit[found] = now
    record.dirty = true
    self.snapshotDirty = true
    local expiry = now + ENGAGEMENT_WINDOW
    if not self.nextEngagementExpiry or expiry < self.nextEngagementExpiry then
        self.nextEngagementExpiry = expiry
    end
    return true
end

function ThreatService:HandleCombatLog()
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
    local ok, _, subevent, _, sourceGUID, _, _, _, destGUID = pcall(CombatLogGetCurrentEventInfo)
    if not ok or not IsReadable(subevent) or type(subevent) ~= "string"
        or subevent:sub(-#DAMAGE_EVENT_SUFFIX) ~= DAMAGE_EVENT_SUFFIX then
        return
    end
    if not IsReadable(sourceGUID) or not IsReadable(destGUID) then return end
    self:RecordDamage(sourceGUID, destGUID)
end

function ThreatService:UpdateRecordGUID(record)
    local guid = ReadGUID(record.unit)
    if record.guid and record.guid ~= guid and self.enemyByGUID[record.guid] == record then
        self.enemyByGUID[record.guid] = nil
        ClearEngagers(record)
    end
    record.guid = guid
    if guid then self.enemyByGUID[guid] = record end
end

function ThreatService:UpdateEngaged(record)
    local now = type(GetTime) == "function" and GetTime() or 0
    local engaged = (record.engagerCount or 0) > 0
        or (type(record.unitDamageAt) == "number" and now - record.unitDamageAt < ENGAGEMENT_WINDOW)
    if not engaged then engaged = ReadBoolean(UnitAffectingCombat, record.unit) == true end
    if not engaged and (record.tanking == true or (type(record.status) == "number" and record.status > 0)) then
        engaged = true
    end
    record.engaged = engaged
end

function ThreatService:UpdateActiveAttackers(record)
    record.activeAttackerCount = 0
    for index = 1, record.engagerCount or 0 do
        local unit = record.engagerUnits[index]
        if unit and ReadGUID(unit .. "target") == record.guid then
            record.activeAttackerCount = record.activeAttackerCount + 1
            local activeIndex = record.activeAttackerCount
            record.activeAttackerNames[activeIndex] = record.engagerNames[index]
            record.activeAttackerUnits[activeIndex] = unit
            record.activeAttackerInferred[activeIndex] = false
        end
    end
    local now = type(GetTime) == "function" and GetTime() or 0
    if record.unitDamageAt and now - record.unitDamageAt < ENGAGEMENT_WINDOW then
        local bucket = record.guid and self.attackerTargets[record.guid] or nil
        for index = 1, bucket and bucket.count or 0 do
            local unit = bucket.units[index]
            local duplicate = false
            for activeIndex = 1, record.activeAttackerCount do
                if record.activeAttackerUnits[activeIndex] == unit then duplicate = true break end
            end
            if not duplicate and record.activeAttackerCount < MAX_ATTACKERS_PER_TARGET then
                record.activeAttackerCount = record.activeAttackerCount + 1
                local activeIndex = record.activeAttackerCount
                record.activeAttackerNames[activeIndex] = bucket.names[index]
                record.activeAttackerUnits[activeIndex] = unit
                record.activeAttackerInferred[activeIndex] = true
            end
        end
    end
    for index = record.activeAttackerCount + 1, MAX_ATTACKERS_PER_TARGET do
        if not record.activeAttackerNames[index] and not record.activeAttackerUnits[index]
            and record.activeAttackerInferred[index] == nil then break end
        record.activeAttackerNames[index] = nil
        record.activeAttackerUnits[index] = nil
        record.activeAttackerInferred[index] = nil
    end
end

function ThreatService:FindTarget(record)
    if not record.engaged then
        record.targetName, record.targetUnit = "No target", nil
        record.tankHolds, record.selfHolds, record.loose = false, false, false
        record.holdState = "IDLE"
        return
    end
    local targetUnit = record.unit .. "target"
    if not UnitExistsSafely(targetUnit) then
        record.targetName, record.targetUnit = "No target", nil
        record.tankHolds, record.selfHolds, record.loose = false, false, true
        record.holdState = "LOOSE"
        return
    end

    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if SameUnit(targetUnit, member.unit) then
            record.targetName = member.name
            record.targetUnit = member.unit
            record.tankHolds = member.role == "TANK"
            record.selfHolds = self.isSolo and (member.isPlayer or member.owner == "player")
            record.loose = not record.tankHolds and not record.selfHolds
            record.holdState = record.tankHolds and "TANK" or record.selfHolds and "YOU" or "LOOSE"
            return
        end
    end

    record.targetName = ReadName(targetUnit, "Unknown target")
    record.targetUnit = nil
    record.tankHolds, record.selfHolds, record.loose = false, false, true
    record.holdState = "LOOSE"
end

function ThreatService:ReadThreat(record)
    record.playerPercent, record.playerDifferential = nil, nil
    record.percent, record.lead = nil, nil
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

    local ok, tanking, status, scaledPercent, rawPercent, raw = pcall(UnitDetailedThreatSituation, "player", mob)
    if not ok then return end
    -- A complete nil tuple is no player entry on this mob, even if Forever's
    -- lead API separately reports a readable zero. Do not suppress partial or
    -- protected tuples: they may still contain displayable threat.
    if tanking == nil and status == nil and scaledPercent == nil
        and rawPercent == nil and raw == nil then
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

    local highestOther = 0
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if not member.isPlayer then
            local threatOK, memberTanking, memberStatus, memberScaled, memberPercent, memberRaw =
                pcall(UnitDetailedThreatSituation, member.unit, mob)
            if not threatOK or not IsReadable(memberRaw) then
                record.differentialState = IsSecret(memberRaw) and "protected-group-threat" or "group-threat-unavailable"
                record.differentialBlocker = member.unit
                return
            end
            -- A complete nil tuple means this actor has no entry on this mob's
            -- threat table. This applies to group members as well as pets; it
            -- is not a requirement for everyone to attack or enter combat.
            -- A partial, protected, or errored tuple is not evidence of zero.
            if memberRaw == nil then
                if not IsReadable(memberTanking) or not IsReadable(memberStatus)
                    or not IsReadable(memberScaled) or not IsReadable(memberPercent)
                    or memberTanking ~= nil or memberStatus ~= nil
                    or memberScaled ~= nil or memberPercent ~= nil then
                    record.differentialState = "group-threat-unavailable"
                    record.differentialBlocker = member.unit
                    return
                end
            elseif type(memberRaw) ~= "number" then
                record.differentialState = "group-threat-unavailable"
                record.differentialBlocker = member.unit
                return
            elseif memberRaw ~= nil and memberRaw > highestOther then
                highestOther = memberRaw
            end
        end
    end
    if targetMatched and not SameUnit(record.unit, "target") then
        record.differentialState = "target-changed"
        return
    end
    record.playerDifferential = raw - highestOther
    record.lead = record.playerDifferential
    record.differentialState = "readable"
end

function ThreatService:RefreshRecord(record)
    if not record or not record.unit then return false end
    if not IsVisibleHostile(record.root, record.unit) then
        self:UntrackEnemy(record.unit)
        return false
    end

    record.enemyName = ReadName(record.unit, record.unit)
    self:UpdateRecordGUID(record)
    record.targeterCount = record.guid and (self.attackerCounts[record.guid] or 0) or nil
    record.attackerCount = record.targeterCount
    self:ReadThreat(record)
    self:UpdateEngaged(record)
    self:UpdateActiveAttackers(record)
    self:FindTarget(record)
    record.dirty = false
    record.revision = record.revision + 1
    self.snapshotDirty = true
    return true
end

function ThreatService:TrackEnemy(unit, root)
    if type(unit) ~= "string" then return nil end
    root = root or (C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit))
    if not IsVisibleHostile(root, unit) then return nil end

    local record = self.enemyByUnit[unit]
    if record then
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
    record.unit, record.root = unit, root
    self.nextRecordSerial = self.nextRecordSerial + 1
    record.serial = self.nextRecordSerial
    record.dirty, record.revision = true, 0
    record.enemyName, record.targetName, record.targetUnit = unit, "No target", nil
    record.tankHolds, record.selfHolds, record.loose, record.engaged = false, false, false, false
    record.holdState = "IDLE"
    record.guid = ReadGUID(unit)
    record.targeterCount, record.attackerCount = nil, nil
    record.activeAttackerCount = 0
    record.unitDamageAt = nil
    ClearEngagers(record)
    record.unitDamageAt = nil
    if record.guid then self.enemyByGUID[record.guid] = record end
    record.playerPercent, record.playerDifferential = nil, nil
    record.playerThreatNoEntry = false
    record.percent, record.lead, record.tanking, record.status = nil, nil, nil, nil
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
    local record = self.enemyByUnit[unit]
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
    ClearEngagers(record)
    record.unit, record.root, record.guid, record.dirty = nil, nil, nil, false
    self.freeCount = self.freeCount + 1
    self.freeRecords[self.freeCount] = record
    if self.cursor > self.enemyCount then self.cursor = 0 end
    self.snapshotDirty = true
end

function ThreatService:MarkDirty(unit)
    local record = unit and self.enemyByUnit[unit]
    if record then
        record.dirty = true
        return
    end
    for index = 1, self.enemyCount do self.enemyOrder[index].dirty = true end
end

function ThreatService:RefreshUnit(unit)
    local record = self.enemyByUnit[unit]
    if not record then
        record = self:TrackEnemy(unit)
    end
    if record then self:RefreshRecord(record) end
    return record
end

function ThreatService:RefreshBatch(budget)
    local count = self.enemyCount
    if count == 0 then self.cursor = 0 return 0 end
    local checked, refreshed = 0, 0
    local limit = math.min(tonumber(budget) or REFRESH_BUDGET, count)
    while checked < limit and self.enemyCount > 0 do
        self.cursor = (self.cursor % self.enemyCount) + 1
        local record = self.enemyOrder[self.cursor]
        if record and (record.dirty or ReadBoolean(UnitIsDeadOrGhost, record.unit) == true
            or ReadBoolean(UnitIsDead, record.unit) == true)
            and self:RefreshRecord(record) then refreshed = refreshed + 1 end
        checked = checked + 1
    end
    return refreshed
end

function ThreatService:RefreshAllForTest()
    local index = 1
    while index <= self.enemyCount do
        local record = self.enemyOrder[index]
        if record and record.dirty then self:RefreshRecord(record) end
        if self.enemyOrder[index] == record then index = index + 1 end
    end
end

function ThreatService:GetEnemy(unit)
    return self.enemyByUnit[unit]
end

function ThreatService:GetPlayerRole()
    return self.playerRole
end

local function GetTargeterBucket(service, unit)
    if type(unit) ~= "string" then return nil end
    local record = service.enemyByUnit[unit]
    local guid = record and record.guid
    return guid and service.attackerTargets[guid] or nil
end

function ThreatService:GetAttackerCount(unit)
    local bucket = GetTargeterBucket(self, unit)
    return bucket and bucket.count or 0
end

function ThreatService:GetAttacker(unit, index)
    if not IsReadable(index) or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
        return nil, nil
    end
    local bucket = GetTargeterBucket(self, unit)
    if not bucket or index > bucket.count then return nil, nil end
    return bucket.names[index], bucket.units[index]
end

function ThreatService:GetTargeterCount(unit)
    return self:GetAttackerCount(unit)
end

function ThreatService:GetTargeter(unit, index)
    return self:GetAttacker(unit, index)
end

function ThreatService:GetEngagerCount(unit)
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    return record and record.engagerCount or 0
end

function ThreatService:GetEngager(unit, index)
    if not IsReadable(index) or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
        return nil, nil
    end
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    if not record or index > record.engagerCount then return nil, nil end
    return record.engagerNames[index], record.engagerUnits[index]
end

function ThreatService:GetActiveAttackerCount(unit)
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    return record and record.activeAttackerCount or 0
end

function ThreatService:GetActiveAttacker(unit, index)
    if not IsReadable(index) or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
        return nil, nil
    end
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    if not record or index > record.activeAttackerCount then return nil, nil end
    return record.activeAttackerNames[index], record.activeAttackerUnits[index], record.activeAttackerInferred[index]
end

function ThreatService:IsCurrentUnit(unit, guid)
    if type(unit) ~= "string" or type(guid) ~= "string" then return false end
    local record = self.enemyByUnit[unit]
    return record ~= nil and record.guid == guid and ReadGUID(unit) == guid
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

function ThreatService:HandleEvent(event, unit, action)
    if not self.eventsEnabled then return end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:HandleCombatLog()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        self:TrackEnemy(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        self:UntrackEnemy(unit)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED"
        or event == "PLAYER_ENTERING_WORLD" or event == "UNIT_PET" then
        self:RebuildRoster()
        self:RebuildTargeterCounts()
        self:MarkDirty()
    elseif event == "UNIT_TARGET" or event == "PLAYER_TARGET_CHANGED" then
        self:RebuildTargeterCounts()
        self:MarkDirty(unit)
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
    return console and console.window and console.window:IsShown() or false
end

function ThreatService:OnUpdate(elapsed)
    if not self:HasActiveConsumer() then return end
    local now = type(GetTime) == "function" and GetTime() or nil
    if now and self.nextEngagementExpiry and now >= self.nextEngagementExpiry then
        self:ExpireEngagements(now)
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < REFRESH_INTERVAL then return end
    self.elapsed = self.elapsed - REFRESH_INTERVAL
    self:RefreshBatch(REFRESH_BUDGET)
end

function ThreatService:OnInitialize()
    self.enemyByUnit = {}
    self.enemyByGUID = {}
    self.enemyOrder = {}
    self.enemyPool = {}
    self.freeRecords = {}
    for index = 1, MAX_ENEMIES do
        local record = {
            revision = 0,
            engagerCount = 0,
            engagerKeys = {},
            engagerNames = {},
            engagerUnits = {},
            engagerLastHit = {},
            activeAttackerCount = 0,
            activeAttackerNames = {},
            activeAttackerUnits = {},
            activeAttackerInferred = {},
        }
        self.enemyPool[index] = record
        self.freeRecords[index] = record
    end
    self.freeCount = MAX_ENEMIES
    self.rosterPool = {}
    self.rosterByGUID = {}
    for index = 1, MAX_ROSTER_UNITS do self.rosterPool[index] = {} end
    self.attackerCounts = {}
    self.attackerTargets = {}
    self.attackerTargetOrder = {}
    self.attackerTargetPool = {}
    self.attackerTargetCount = 0
    for index = 1, MAX_ATTACKER_TARGETS do
        self.attackerTargetPool[index] = { names = {}, units = {}, count = 0 }
    end
    self.snapshot = {}
    self:RebuildRoster()
    self:RebuildTargeterCounts()
end

function ThreatService:OnEnable()
    self.eventsEnabled = true
    self:ScanVisibleEnemies()
    self:MarkDirty()
end

function ThreatService:OnDisable()
    self.eventsEnabled = false
end

ThreatService._Test = {
    IsReadable = IsReadable,
    IsSecret = IsSecret,
    RefreshInterval = REFRESH_INTERVAL,
    RefreshBudget = REFRESH_BUDGET,
    MaxEnemies = MAX_ENEMIES,
    MaxAttackerTargets = MAX_ATTACKER_TARGETS,
    MaxAttackersPerTarget = MAX_ATTACKERS_PER_TARGET,
    EngagementWindow = ENGAGEMENT_WINDOW,
}

-- Register once while the addon file is loading, then gate delivery with
-- eventsEnabled so module enable/disable never mutates event subscriptions.
ThreatService.frame = CreateFrame("Frame")
ThreatService.frame:SetScript("OnEvent", function(_, event, ...)
    ThreatService:HandleEvent(event, ...)
end)
ThreatService.frame:SetScript("OnUpdate", function(_, elapsed)
    if ThreatService.eventsEnabled then ThreatService:OnUpdate(elapsed) end
end)
for index = 1, #SERVICE_EVENTS do
    PS._RegisterEvent(ThreatService.frame, SERVICE_EVENTS[index], "platesmith.threat-service")
end

local registered = PS:RegisterModule("platesmith.threat-service", ThreatService)
if registered then PS.ThreatService = registered end
