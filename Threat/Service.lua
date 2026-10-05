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
-- An engaged mob is re-read at least this often, event or not.
local STALE_REFRESH = 1
-- Members whose target is re-read on each GROUP_SCAN_INTERVAL pass whatever UNIT_TARGET said: all
-- of a party's, a rolling few of a raid's (ReconcileTargets).
local RECONCILE_BUDGET = 5
-- UNIT_COMBAT damage per record, in one-second slots, for /ps diagnose (the last 10 s).
local DAMAGE_SLOTS = 10

local SERVICE_EVENTS = {
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_TARGET",
    "UNIT_PET",
    "PLAYER_TARGET_CHANGED",
    -- The mouseover and focus tokens can read threat a plate's own token cannot (ReadThreat).
    "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_FOCUS_CHANGED",
    -- The boss tokens (boss1..boss5) appear, change and become targetable during an encounter.
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "UNIT_TARGETABLE_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "UNIT_COMBAT",
    -- What the player is doing can make them the tank (Adaptive): stance, form, auras, form casts,
    -- talents. UNIT_AURA and UNIT_SPELLCAST_SUCCEEDED are registered for the player alone, below.
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_FORMS",
    "CHARACTER_POINTS_CHANGED",
    "PLAYER_TALENT_UPDATE",
}

local ThreatService = {
    version = 1,
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
    reconcileCursor = 0,
    targetReconciles = 0,
    immediateRefreshes = 0,
    targetersDirty = false,
    allTargetersDirty = false,
    playerRole = "NONE",
    playerRoleSource = "none",
    -- What each tank-evidence signal said at the last role resolve, for /ps diagnose.
    roleReads = { formID = "not read", formIndex = "not read", power = "not read", aura = "not read", tankAura = "not read" },
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
local UnitExistsSafely, SameUnit, ReadGUID = Secret.UnitExists, Secret.SameUnit, Secret.ReadGUID
local TargetToken = Secret.TargetToken
local L = PS.L

-- Roster tokens, built once rather than on every roster rebuild.
local RAID_TOKENS, RAID_PET_TOKENS, PARTY_TOKENS, PARTY_PET_TOKENS = {}, {}, {}, {}
for index = 1, 40 do RAID_TOKENS[index], RAID_PET_TOKENS[index] = "raid" .. index, "raidpet" .. index end
for index = 1, 4 do PARTY_TOKENS[index], PARTY_PET_TOKENS[index] = "party" .. index, "partypet" .. index end

-- Fields a threat window (its rows and open tooltip) shows or sorts by. A refresh that changes none
-- of them (and holds no protected value, which cannot be compared) leaves the snapshot as it is.
-- targeterRevision covers a new targeter list of the same length.
local SHOWN_FIELDS = {
    "unit", "guid", "enemyName", "serial", "root", "threatMobSource", "holdState", "engaged", "loose",
    "targetName", "activeAttackerCount", "attackerState", "targeterCount", "targeterState", "targeterRevision",
    "percent", "lead", "leadKind", "leadKept", "leadPercent", "rawThreat",
    "selfHolds", "tankHolds", "tanking", "status", "hasOpaqueName", "hasOpaqueTargetName",
    "hasOpaqueTanking", "holdFlagCount", "holdFallback",
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

local function IsGroupToken(unit)
    return unit == "player" or unit == "pet" or unit:match("^party") ~= nil or unit:match("^raid") ~= nil
end

-- Tokens borrowed for a plate's threat reads besides "target" (ReadThreat), in this order; a group
-- member's target (MemberBorrowedToken) comes after them. Boss tokens name the same mob for every
-- player, so they come before the hover.
local BORROWED_TOKENS = { "focus", "boss1", "boss2", "boss3", "boss4", "boss5", "mouseover" }
local BOSS_TOKENS = { boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true }
-- The boss tokens that may name a unit now (SyncBossTokens, on encounter events): the others are not
-- looked up, so outside an encounter a read costs what it did without them. An unreadable answer counts.
local bossActive = {}

local function SyncBossTokens()
    for token in pairs(BOSS_TOKENS) do bossActive[token] = ReadBoolean(UnitExists, token) ~= false end
end
-- Who a borrowed token found targeting a mob is kept this long after it moves on (ReadTokenTargeters).
local TARGETERS_HOLD = 5

local function Settings()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return type(settings) == "table" and settings or nil
end

-- A gap read through one of them (or the target) is kept after the token moves on for the
-- profile's threatKeptHold: seconds, or false ("until") while the same mob lives (its record serial).
local KEPT_HOLDS = { ["5"] = 5, ["10"] = 10, ["15"] = 15, ["30"] = 30, ["until"] = false }
local DEFAULT_KEPT_HOLD = 5

-- The hold in seconds, or nil while a kept gap stays as long as its mob.
local function KeptHold()
    local settings = Settings()
    local hold = settings and KEPT_HOLDS[settings.threatKeptHold]
    if hold == nil then return DEFAULT_KEPT_HOLD end
    return hold or nil
end
ThreatService.KeptHold = KeptHold

-- Settings › Experimental: more borrowed tokens, after the mouseover and before a member's target:
-- the soft targets, then the target's and focus's targets. They may not exist on this client, so
-- each is looked up only while its test is on, and one the client refuses is skipped.
local SOFT_TOKENS = { "softenemy", "softinteract" }
local CHAIN_TOKENS = { "targettarget", "focustarget" }
-- Per token, for /ps diagnose: whether it exists (readable, none, protected, error, api-missing), and
-- how many reads went through it, with the last one's differential state.
local experimentalTokens = {}
for _, token in ipairs({ SOFT_TOKENS[1], SOFT_TOKENS[2], CHAIN_TOKENS[1], CHAIN_TOKENS[2] }) do
    experimentalTokens[token] = { exists = "not tried", reads = 0, last = "none" }
end

local function ExperimentalTokenExists(token)
    local stat = experimentalTokens[token]
    if type(UnitExists) ~= "function" then
        stat.exists = "api-missing"
        return false
    end
    local ok, exists = pcall(UnitExists, token)
    if not ok then
        stat.exists = "error"
        return false
    end
    -- A protected answer may still name a unit: the plate lookup decides.
    if not IsReadable(exists) then
        stat.exists = "protected"
        return true
    end
    stat.exists = exists and "readable" or "none"
    return exists and true or false
end

-- Whether a unit token (such as "mouseover") names the plate root or plate unit: the plate frame the
-- client gives for it is compared with ours (a frame, not a protected GUID), else its readable
-- plate token. A withheld answer is no.
local function TokenPlateFrame(token)
    local getPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(getPlate) ~= "function" then return nil end
    local ok, plate = pcall(getPlate, token)
    if ok and IsReadable(plate) and type(plate) == "table" then return plate end
    return nil
end

local function TokenNamesPlate(token, root, unit)
    local plate = TokenPlateFrame(token)
    if not plate then return false end
    if root ~= nil and plate == root then return true end
    local plateUnit = plate.namePlateUnitToken
    return IsReadable(plateUnit) and type(plateUnit) == "string" and plateUnit == unit
end

-- Whether a member's target token is this record's mob, by readable GUIDs (outdoors; in instances
-- the GUIDs are protected and this is false).
local function MemberTargetsRecord(token, record)
    local guid = record.guid
    if not guid then return false end
    return ReadGUID(token) == guid
end

-- The plate frame the client gives for a member's target, and what it said: "found", "none" (no
-- plate: no target, or one without a plate), "protected", "error", "unavailable" or "api-missing".
-- The frame is our own plate root (a readable table, compared by identity); a protected answer is
-- never looked at.
local function ReadTargetPlate(token)
    local getPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(getPlate) ~= "function" then return nil, "api-missing" end
    local ok, plate = pcall(getPlate, token)
    if not ok then return nil, "error" end
    if not IsReadable(plate) then return nil, "protected" end
    if plate == nil then return nil, "none" end
    if type(plate) ~= "table" then return nil, "unavailable" end
    return plate, "found"
end

local function ExperimentalToken(tokens, record)
    for index = 1, #tokens do
        local token = tokens[index]
        if ExperimentalTokenExists(token) and TokenNamesPlate(token, record.root, record.unit) then return token end
    end
    return nil
end

-- The first borrowed token that names this record's plate, or nil.
local function BorrowedToken(record)
    for index = 1, #BORROWED_TOKENS do
        local token = BORROWED_TOKENS[index]
        if (not BOSS_TOKENS[token] or bossActive[token]) and TokenNamesPlate(token, record.root, record.unit) then
            return token
        end
    end
    local settings = Settings()
    if not settings then return nil end
    local token
    if settings.experimentalSoftTargetThreat == true then token = ExperimentalToken(SOFT_TOKENS, record) end
    if not token and settings.experimentalTargetOfTargetThreat == true then token = ExperimentalToken(CHAIN_TOKENS, record) end
    return token
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

-- Evidence that the player is tanking right now, for Adaptive: a tanking stance or presence,
-- Righteous Fury, or Bear / Dire Bear Form (unless the talents are clearly Balance or Restoration:
-- bear form is then an escape). In combat the client may withhold the form ID and auras, so the
-- form comes from the first signal that answers (ReadPlayerForm).
local TANK_FORMS = { [18] = true } -- Defensive Stance
local BEAR_FORMS = { [5] = true, [8] = true } -- Bear, Dire Bear
-- The spells behind forms and stances (the form bar, auras, the player's own casts): "tank",
-- "bear", or "none" for a form that is neither.
local FORM_SPELLS = {
    [71] = "tank", [5487] = "bear", [9634] = "bear", [2457] = "none", [2458] = "none", -- the stances, Bear, Dire Bear
    -- Cat, Travel, Aquatic, Moonkin, Tree of Life, Flight and Swift Flight Form
    [768] = "none", [783] = "none", [1066] = "none", [24858] = "none", [33891] = "none", [33943] = "none", [40120] = "none",
}
-- Who can tank by form ("form") or by aura ("aura": Righteous Fury, the death knight's tanking presence).
local TANK_CLASSES = { DRUID = "form", WARRIOR = "form", PALADIN = "aura", DEATHKNIGHT = "aura" }
local TANK_AURAS = { 25780, 48263 }
-- A form cast stands for the form until a form change that is not its own (one this much later).
local FORM_CAST_WINDOW = 1
-- Bear form is an escape only with this many more points in Balance or Restoration than in Feral.
local BEAR_ESCAPE_MARGIN = 5

local function PlayerClass()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, class = pcall(UnitClass, "player")
    return ok and Secret.String(class) or nil
end

-- Each Form* read returns the form ("tank", "bear", "none") or nil, and what the client said
-- ("readable", "protected", "unavailable", "error", "api-missing") for /ps diagnose.
local function FormFromID()
    if type(GetShapeshiftFormID) ~= "function" then return nil, "api-missing" end
    local ok, formID = pcall(GetShapeshiftFormID)
    if not ok then return nil, "error" end
    if not IsReadable(formID) then return nil, "protected" end
    if formID ~= nil and TANK_FORMS[formID] then return "tank", "readable" end
    if formID ~= nil and BEAR_FORMS[formID] then return "bear", "readable" end
    return "none", "readable"
end

-- A form bar slot (GetShapeshiftFormInfo: icon, active, castable, spellID; older clients icon,
-- name, active, castable): whether it is active (nil when unknown), its form (a spell not named
-- here, such as a paladin aura, is "none"; nil when the spell is withheld) and the state word.
local function FormSlot(index)
    local ok, _, second, third, fourth = pcall(GetShapeshiftFormInfo, index)
    if not ok then return nil, nil, "error" end
    local active, spellID = second, fourth
    if IsReadable(second) and type(second) == "string" then active, spellID = third, nil end
    if not IsReadable(active) or type(active) ~= "boolean" then active = nil end
    if not IsReadable(spellID) then return active, nil, "protected" end
    if type(spellID) ~= "number" then return active, nil, "unavailable" end
    return active, FORM_SPELLS[spellID] or "none", "readable"
end

local MAX_FORM_SLOTS = 10
-- GetShapeshiftForm's slot (0: no form), else the slot GetShapeshiftFormInfo says is active.
local function FormFromIndex()
    if type(GetShapeshiftForm) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then
        return nil, "api-missing"
    end
    local ok, index = pcall(GetShapeshiftForm)
    if ok and IsReadable(index) and type(index) == "number" then
        if index == 0 then return "none", "readable" end
        local _, form, state = FormSlot(index)
        return form, state
    end
    local slots
    if type(GetNumShapeshiftForms) == "function" then
        local countOK, count = pcall(GetNumShapeshiftForms)
        if countOK and IsReadable(count) and type(count) == "number" then slots = count end
    end
    if not slots then return nil, ok and "protected" or "error" end
    local known = true
    for slot = 1, math.min(slots, MAX_FORM_SLOTS) do
        local active, form, state = FormSlot(slot)
        if active == true then return form, state end
        if active == nil then known = false end
    end
    if known then return "none", "readable" end
    return nil, "protected"
end

-- A druid has rage only in Bear or Dire Bear Form.
local RAGE = 1
local function FormFromPower(class)
    if class ~= "DRUID" then return nil, "not used" end
    if type(UnitPowerType) ~= "function" then return nil, "api-missing" end
    local ok, power = pcall(UnitPowerType, "player")
    if not ok then return nil, "error" end
    if not IsReadable(power) then return nil, "protected" end
    if type(power) ~= "number" then return nil, "unavailable" end
    local rage = Enum and Enum.PowerType and Secret.Number(Enum.PowerType.Rage) or RAGE
    return power == rage and "bear" or "none", "readable"
end

-- C_UnitAuras.GetPlayerAuraBySpellID on each spell: the first one on, false when every answer is
-- readably off, nil when one is withheld; and the state word.
local function PlayerAura(spellIDs)
    local get = type(C_UnitAuras) == "table" and C_UnitAuras.GetPlayerAuraBySpellID
    if type(get) ~= "function" then return nil, "api-missing" end
    local state = "readable"
    for index = 1, #spellIDs do
        local ok, aura = pcall(get, spellIDs[index])
        if not ok then
            state = "error"
        elseif not IsReadable(aura) then
            state = "protected"
        elseif aura ~= nil then
            return spellIDs[index], "readable"
        end
    end
    if state == "readable" then return false, state end
    return nil, state
end

-- Bear Form shows as a buff, so its absence says "none"; a stance may not, so Defensive Stance's
-- aura can only say "tank".
local FORM_AURAS = { DRUID = { 5487, 9634 }, WARRIOR = { 71 } }
local ANY_FORM_AURAS = { 71, 5487, 9634 }
local function FormFromAuras(class)
    local spellID, state = PlayerAura(FORM_AURAS[class] or ANY_FORM_AURAS)
    if spellID then return FORM_SPELLS[spellID], state end
    if spellID == false and class == "DRUID" then return "none", state end
    return nil, state
end

-- Points spent in a talent tree, and the state word.
local function TalentPoints(tab)
    if type(GetTalentTabInfo) ~= "function" then return nil, "api-missing" end
    local ok, first, _, third, _, fifth = pcall(GetTalentTabInfo, tab)
    if not ok then return nil, "error" end
    if not IsReadable(first) then return nil, "protected" end
    -- Older clients return name, icon, points; later ones id, name, description, icon, points. Any
    -- other shape gives nothing rather than some other return read as points.
    local points
    if type(first) == "string" then
        points = third
    elseif type(first) == "number" then
        points = fifth
    end
    if not IsReadable(points) then return nil, "protected" end
    if type(points) ~= "number" or points < 0 then return nil, "unavailable" end
    return points, "readable"
end

-- Balance, Feral and Restoration points, else nil and the first refusal's state word.
local function DruidTalents()
    local balance, balanceState = TalentPoints(1)
    local feral, feralState = TalentPoints(2)
    local restoration, restorationState = TalentPoints(3)
    if balance and feral and restoration then return balance, feral, restoration, "readable" end
    return nil, nil, nil, (not balance and balanceState) or (not feral and feralState) or restorationState
end

-- The role the player's specialization gives (GetSpecializationRole), or nil.
local function SpecializationRole()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationRole) ~= "function" then return nil end
    local ok, specialization = pcall(GetSpecialization)
    if not ok or not IsReadable(specialization) or type(specialization) ~= "number" then return nil end
    local roleOK, specRole = pcall(GetSpecializationRole, specialization)
    if roleOK and IsReadable(specRole) and type(specRole) == "string" then return specRole end
    return nil
end

-- Bear form tanks unless Balance or Restoration has a clear majority over Feral. A low-level druid
-- has few points anywhere, and a near split or unreadable talents is no sign of a healer's escape.
-- Without talent trees (later clients), a healing specialization's bear form is the escape.
local function BearTanks()
    local balance, feral, restoration = DruidTalents()
    if not balance then return SpecializationRole() ~= "HEALER" end
    return balance - feral < BEAR_ESCAPE_MARGIN and restoration - feral < BEAR_ESCAPE_MARGIN
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

-- A member's target: its GUID, and whether the answer is known (a readable GUID, or readably no
-- target at all). A protected GUID or existence leaves it unknown.
local function ReadMemberTarget(token)
    local guid = ReadGUID(token)
    if guid then return guid, true end
    return nil, ReadBoolean(UnitExists, token) == false
end

-- A unit token usable as a table key: readable and a string.
local function ReadableToken(unit)
    return IsReadable(unit) and type(unit) == "string" and unit or nil
end

-- A unit's name as readable, opaque, hasOpaque. In instances Forever protects enemy (and sometimes
-- group) names: the opaque value is kept only for a text sink and readable is then nil, so logic
-- never sees it. fallback is used only when the client returns no name at all.
local function ReadDisplayName(unit, fallback)
    if type(UnitName) ~= "function" then return fallback, nil, false end
    local ok, name = pcall(UnitName, unit)
    if not ok then return fallback, nil, false end
    if not IsReadable(name) then return nil, name, true end
    if type(name) == "string" and name ~= "" then return name, nil, false end
    return fallback, nil, false
end

-- Readable names sort by name, a protected (nil) one after them; nil when they are equal.
local function NameBefore(left, right)
    if left == right then return nil end
    if left == nil then return false end
    if right == nil then return true end
    return left < right
end

local function SnapshotSort(left, right)
    if left.loose ~= right.loose then return left.loose end
    if left.engaged ~= right.engaged then return left.engaged end
    local before = NameBefore(left.targetName, right.targetName)
    if before ~= nil then return before end
    before = NameBefore(left.enemyName, right.enemyName)
    if before ~= nil then return before end
    -- Protected names: the order the plates were tracked in, so rows do not shuffle.
    if left.enemyName == nil and type(left.serial) == "number" and type(right.serial) == "number"
        and left.serial ~= right.serial then
        return left.serial < right.serial
    end
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
    entry.name, entry.nameOpaque, entry.hasOpaqueName = ReadDisplayName(unit, unit)
    -- A pet the client has not named yet ("Unknown", or no name at all): named by its owner.
    if entry.owner ~= unit and not entry.hasOpaqueName
        and (entry.name == unit or entry.name == rawget(_G, "UNKNOWNOBJECT")) then
        local ownerName = ReadDisplayName(entry.owner, nil)
        if ownerName then entry.name = string.format(L["%s's pet"], ownerName) end
    end
    entry.guid = ReadGUID(unit)
    entry.isMember = isMember and true or false
    entry.isPlayer = unit == "player" or SameUnit(unit, "player")
    entry.ownerIsPlayer = entry.owner ~= unit and (entry.owner == "player" or SameUnit(entry.owner, "player"))
    entry.targetGUID, entry.targetKnown, entry.targetDirty = nil, false, true
    entry.plateFrame, entry.plateState = nil, nil
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

-- The player's class token: the roster's read, else the client's (nil when withheld).
function ThreatService:PlayerClass()
    local entry = self.playerRosterIndex and self.rosterPool[self.playerRosterIndex]
    return entry and entry.classToken or PlayerClass()
end

-- The player's form as "tank", "bear" or "none", and the signal that said so: the form ID, the
-- form bar, a druid's power, the form auras, then the player's own last form cast (a readable
-- "no Bear Form buff" comes after the cast). nil when none of them can say.
function ThreatService:ReadPlayerForm(class)
    local reads = self.roleReads
    reads.formIndex, reads.power, reads.aura = "not needed", "not needed", "not needed"
    local form
    form, reads.formID = FormFromID()
    if form then return form, "formID" end
    form, reads.formIndex = FormFromIndex()
    if form then return form, "formIndex" end
    form, reads.power = FormFromPower(class)
    if form then return form, "power" end
    local auraForm
    auraForm, reads.aura = FormFromAuras(class)
    if auraForm ~= nil and auraForm ~= "none" then return auraForm, "aura" end
    if self.formCast ~= nil then return self.formCast, "cast" end
    if auraForm ~= nil then return auraForm, "aura" end
    return nil, nil
end

-- true, false, or nil when the client will not say (the caller keeps what it last knew), and the
-- signal that decided: formID, formIndex, power, aura, cast, event (a form change since the
-- last known tank form, with nothing readable: the player left it), or class (cannot tank).
function ThreatService:PlayerTankEvidence()
    local class = self:PlayerClass()
    local kind = class and TANK_CLASSES[class]
    local reads = self.roleReads
    reads.formID, reads.formIndex, reads.power, reads.aura, reads.tankAura =
        "not needed", "not needed", "not needed", "not needed", "not needed"
    if class and not kind then return false, "class" end
    local form, signal
    if kind ~= "aura" then
        form, signal = self:ReadPlayerForm(class)
        -- Read now, so a remembered cast no longer stands for the form.
        if signal ~= nil and signal ~= "cast" then self.formCast = nil end
        if form == nil and self.formLeft and self.playerInTankForm then form, signal = "none", "event" end
        if form ~= nil then self.formLeft, self.playerInTankForm = false, form ~= "none" end
        if form == "tank" then return true, signal end
        if form == "bear" then return BearTanks(), signal end
        if kind == "form" then
            if form == "none" then return false, signal end
            return nil, nil
        end
    end
    local spellID, state = PlayerAura(TANK_AURAS)
    reads.tankAura = state
    if spellID then return true, "aura" end
    -- A client without the aura API can never say: that counts as no aura.
    if (spellID == false or state == "api-missing") and (kind == "aura" or form == "none") then
        return false, kind == "aura" and "aura" or signal
    end
    return nil, nil
end

-- The player's role. Always and Never (per character) win. Adaptive takes an assigned TANK role,
-- then what the player is doing (PlayerTankEvidence), then any other assigned role (a group finder
-- gives every member one, often DAMAGER), then the specialization's.
function ThreatService:ResolvePlayerRole()
    self.roleDirty = false
    self.roleResolves = (self.roleResolves or 0) + 1
    self.roleResolvedAt, self.roleResolvedInCombat = Now(), Secret.InCombat()
    local previous = self.playerRole
    local role, source = "NONE", "none"
    local mode = TankMode()
    local entry = self.playerRosterIndex and self.rosterPool[self.playerRosterIndex]
    local assigned = mode ~= "always" and entry and entry.assignedRole or "NONE"
    if assigned == "TANK" then role, source = "TANK", "assigned" end
    -- Adaptive: what the player is doing now (a tanking stance, presence or bear form) outranks
    -- an assigned DAMAGER or HEALER and the role a talent spec implies (Feral reads as damage). A
    -- healer's bear form escape is ruled out by the talents (BearTanks).
    self.tankEvidenceRead = role == "NONE" and mode == "adaptive"
    if self.tankEvidenceRead then
        local evidence, signal = self:PlayerTankEvidence()
        self.lastTankEvidence = evidence
        if evidence == nil then
            evidence = self.playerTankEvidence
        else
            self.playerTankSignal = signal
        end
        self.playerTankEvidence = evidence
        if evidence then role, source = "TANK", "adaptive" end
    end
    if role == "NONE" and assigned ~= "NONE" then role, source = assigned, "assigned" end
    if role == "NONE" and mode ~= "always" then
        local specRole = SpecializationRole()
        if specRole then role, source = specRole, "specialization" end
    end
    if mode == "always" then
        role, source = "TANK", "forced"
    elseif mode == "never" then
        if role == "TANK" then role, source = "DAMAGER", "never" end
    end

    if role ~= previous then
        self.roleChangedFrom, self.roleChangedAt, self.roleChangedInCombat = previous, self.roleResolvedAt,
            self.roleResolvedInCombat
    end
    self.playerRole, self.playerRoleSource = role, source
    -- Hold state reads roster roles, so the player's entries must carry the resolved role.
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if member.isPlayer or member.ownerIsPlayer then member.role = role end
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
    self.isRaid = raid

    for index = self.rosterCount + 1, oldCount do
        local entry = self.rosterPool[index]
        entry.unit, entry.owner, entry.role, entry.assignedRole, entry.name, entry.guid = nil, nil, nil, nil, nil, nil
        entry.nameOpaque, entry.hasOpaqueName = nil, nil
        entry.isMember, entry.isPlayer, entry.ownerIsPlayer, entry.classToken = nil, nil, nil, nil
        entry.targetToken, entry.targetGUID, entry.targetKnown, entry.targetDirty = nil, nil, nil, nil
        entry.plateFrame, entry.plateState = nil, nil
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

-- Whether what the player is doing can decide the role: Adaptive without an assigned TANK role.
function ThreatService:TankEvidenceMatters()
    if self.rosterDirty then return true end
    if TankMode() ~= "adaptive" then return false end
    local entry = self.playerRosterIndex and self.rosterPool[self.playerRosterIndex]
    return not entry or entry.assignedRole ~= "TANK"
end

-- The player's own form casts and form changes, kept for when the client withholds the form
-- (ReadPlayerForm). False for an event that says nothing about the player's form.
function ThreatService:NoteFormEvent(event, unit, spellID)
    local now = Now()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not (IsReadable(unit) and unit == "player") or not Secret.Number(spellID) then return false end
        local form = FORM_SPELLS[spellID]
        if not form then return false end
        self.formCast, self.formCastAt, self.formLeft = form, now, false
        return true
    end
    -- A change that is not the last cast's own: that cast no longer stands for the form.
    if self.formCast == nil or now - self.formCastAt > FORM_CAST_WINDOW then
        self.formCast, self.formLeft = nil, true
    end
    return true
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
                local known, frame = member.targetKnown, member.plateFrame
                member.targetGUID, member.targetKnown = ReadMemberTarget(member.targetToken)
                member.plateFrame, member.plateState = ReadTargetPlate(member.targetToken)
                member.targetDirty = false
                -- Readable where it was not, or the other way: any record's targeting state can change.
                if known ~= member.targetKnown or (frame == nil) ~= (member.plateFrame == nil) then
                    self.targetKnownChanged = true
                elseif frame ~= member.plateFrame then
                    -- From one plate to another: only those two records' lists change.
                    self.touchedPlates[frame], self.touchedPlates[member.plateFrame] = true, true
                end
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

-- A member's target GUID is read on its UNIT_TARGET; one the client withheld at that moment would
-- stay missing until the next retarget. On the tick (every GROUP_SCAN_INTERVAL) a missing one is
-- read again, and the targeters rebuilt only when it has become readable.
function ThreatService:RetryMissingTargets()
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if member.isMember and member.targetGUID == nil and not member.targetDirty
            and ReadGUID(member.targetToken) ~= nil then
            member.targetDirty = true
            self.targetersDirty = true
        end
    end
end

-- UNIT_TARGET can be missed (withheld, or sent while the GUID was protected), which would leave an
-- old count. Each pass re-reads up to RECONCILE_BUDGET members' targets, from a rolling cursor, and
-- flags only the ones whose GUID (or whether it is known) or target plate frame changed. The
-- borrowed-token route needs none of this: it is re-read on every refresh of the record
-- (ReadTokenTargeters).
function ThreatService:ReconcileTargets()
    local count = self.rosterCount
    local checked, visited = 0, 0
    while checked < RECONCILE_BUDGET and visited < count do
        visited = visited + 1
        self.reconcileCursor = (self.reconcileCursor % count) + 1
        local member = self.rosterPool[self.reconcileCursor]
        if member.isMember and not member.targetDirty then
            checked = checked + 1
            local guid, known = ReadMemberTarget(member.targetToken)
            local frame, plateState = ReadTargetPlate(member.targetToken)
            if guid ~= member.targetGUID or known ~= member.targetKnown or frame ~= member.plateFrame
                or plateState ~= member.plateState then
                member.targetDirty = true
                self.targetersDirty = true
                self.targetReconciles = self.targetReconciles + 1
            end
        end
    end
    return checked
end

-- Members targeting the record by its borrowed token (target, mouseover or focus), for when the
-- GUID route gives nothing (a protected plate or member-target GUID): UnitIsUnit against that
-- token, which the client often answers where the plate's own token is protected. Read at most
-- every GROUP_THREAT_INTERVAL per record; a plate read through its own token has none.
function ThreatService:ReadTokenTargeters(record)
    local bucket = record.tokenTargeters
    local source = record.threatMobSource
    local borrowed = source ~= nil and source ~= "nameplate"
    local now = Now()
    if borrowed and bucket.source == source and bucket.serial == record.serial and bucket.readAt
        and now - bucket.readAt < GROUP_THREAT_INTERVAL then
        return
    end
    -- Read through the mouseover or focus a moment ago: kept for TARGETERS_HOLD.
    if not borrowed and bucket.readAt and bucket.serial == record.serial and now - bucket.readAt < TARGETERS_HOLD then
        return
    end
    local count = 0
    -- Each member's answer (true, false, or nil when protected), for MergeTargeters.
    local answers = bucket.answers
    for unit in pairs(answers) do answers[unit] = nil end
    if borrowed then
        for index = 1, self.rosterCount do
            local member = self.rosterPool[index]
            if member.isMember then
                local same = ReadBoolean(UnitIsUnit, member.targetToken, source)
                answers[member.unit] = same
                if same == true and count < MAX_ATTACKERS_PER_TARGET then
                    count = count + 1
                    bucket.names[count], bucket.units[count] = member.name, member.unit
                end
            end
        end
    end
    for index = count + 1, bucket.count do bucket.names[index], bucket.units[index] = nil, nil end
    bucket.count, bucket.source, bucket.serial, bucket.readAt = count, source, record.serial, borrowed and now or nil
end

-- Whether a member readably targets something other than the record: another plate (by the frame
-- the client gives for its target), nothing at all, or a GUID that is not the record's (known when
-- the record's GUID is, or when it is a group member's or another tracked mob's).
function ThreatService:TargetsElsewhere(member, record)
    local frame = member.plateFrame
    if frame ~= nil and frame ~= record.root then return true end
    if not member.targetKnown then return false end
    local target = member.targetGUID
    if target == nil or record.guid ~= nil then return true end
    local other = self.enemyByGUID[target]
    return self.rosterByGUID[target] ~= nil or (other ~= nil and other ~= record)
end

-- Who targets the record, member by member: the GUID route (RebuildTargeterCounts), the plate-frame
-- route (the frame the client gives for the member's target is this record's plate, which works
-- where GUIDs and UnitIsUnit are protected) and the borrowed token route (ReadTokenTargeters) each
-- identify members on their own, and a member any one names is listed. targeterState says how sure
-- the list is: "confirmed" or "none" when every member was answered, "partial" (a lower bound) or
-- "unknown" (nobody found) when some member's target could not be matched. targeterRevision moves
-- when the list or the state changes.
function ThreatService:MergeTargeters(record)
    local merged, answers = record.targeters, record.tokenTargeters.answers
    local guid, root = record.guid, record.root
    local count, partial, changed = 0, false, false
    -- A read kept after the hover or focus moved on (TARGETERS_HOLD) still lists who it found, but its
    -- "not targeting" answers are old: they confirm nothing.
    local live = record.threatMobSource == record.tokenTargeters.source
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if member.isMember then
            local token = answers[member.unit]
            local frame = member.plateFrame
            local onPlate = frame ~= nil and frame == root
            if token == true or onPlate or (guid ~= nil and member.targetGUID == guid) then
                if count < MAX_ATTACKERS_PER_TARGET then
                    count = count + 1
                    if merged.units[count] ~= member.unit or merged.names[count] ~= member.name then changed = true end
                    merged.names[count], merged.units[count] = member.name, member.unit
                end
            elseif (token ~= false or not live) and not self:TargetsElsewhere(member, record) then
                partial = true
            end
        end
    end
    for index = count + 1, merged.count do merged.names[index], merged.units[index] = nil, nil end
    local state = partial and (count > 0 and "partial" or "unknown") or (count > 0 and "confirmed" or "none")
    if changed or count ~= merged.count or state ~= record.targeterState then
        record.targeterRevision = (record.targeterRevision or 0) + 1
    end
    merged.count, record.targeterState, record.targeterCount = count, state, count
    local bucket = guid and self.attackerTargets[guid]
    record.guidTargeterCount = bucket and bucket.count or 0
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

-- Forgets the damage slots (a new mob in the record).
local function ClearDamage(record)
    for slot = 1, DAMAGE_SLOTS do record.damageStamps[slot], record.damageCounts[slot] = nil, 0 end
end

function ThreatService:RecordUnitDamage(unit)
    local token = ReadableToken(unit)
    local record = token and self.enemyByUnit[token] or nil
    if not record and token and not IsGroupToken(token) then
        -- "target", "focus", "mouseover"...: the plate the client names for it.
        local known, plateUnit = PlateToken(token)
        record = known and plateUnit and self.enemyByUnit[plateUnit] or nil
        local frame = not known and TokenPlateFrame(token) or nil
        for index = 1, frame and self.enemyCount or 0 do
            local candidate = self.enemyOrder[index]
            if candidate.root == frame then
                record = candidate
                break
            end
        end
    end
    if not record then return false end
    local now = Now()
    local second = math.floor(now)
    local slot = second % DAMAGE_SLOTS + 1
    if record.damageStamps[slot] ~= second then record.damageStamps[slot], record.damageCounts[slot] = second, 0 end
    record.damageCounts[slot] = record.damageCounts[slot] + 1
    record.unitDamageAt = now
    -- The client reports damage for this mob, so a quiet spell later means nobody is hitting it.
    record.damageSeenSerial = record.serial
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
        ClearDamage(record)
        self.nextRecordSerial = self.nextRecordSerial + 1
        record.serial = self.nextRecordSerial
    end
    if guid then record.knownGUID = guid end
    record.guid = guid
    if guid then self.enemyByGUID[guid] = record end
end

-- Creature types (as the client names them) that are never part of a fight.
local CRITTER_TYPES = { Critter = true, ["Non-combat Pet"] = true }
local TRIVIAL_CLASSES = { trivial = true, minus = true }

local function ReadString(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if ok and IsReadable(value) and type(value) == "string" then return value end
    return nil
end

local function ReadNumberValue(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if ok and IsReadable(value) and type(value) == "number" then return value end
    return nil
end

-- Whether the mob is on the group's readable threat table: your own entry, or another member's.
-- The group scan is kept per record (GroupHighest) and only counts while recent.
local function OnThreatTable(record)
    local group = type(record.groupHighest) == "number" and record.groupHighest > 0
        and type(record.groupScanAt) == "number" and Now() - record.groupScanAt < 2 * GROUP_SCAN_INTERVAL
    if record.playerThreatNoEntry == true then return group end
    return record.tanking == true or type(record.status) == "number"
        or (type(record.rawThreat) == "number" and record.rawThreat > 0) or group
end

-- Units that are not part of the fight leave the Tank list and its counts (record.excluded): a
-- neutral critter (creature type Critter, trivial or minus, or level 1) not on the group's threat
-- table, or another neutral mob neither in combat nor on it. (One you cannot attack is never
-- tracked: IsVisibleHostile.) Only readable answers exclude; a protected one never does. What
-- does not change for a mob (reaction, type, classification, level) is read once per serial.
function ThreatService:UpdateExcluded(record)
    local unit = record.unit
    if record.involvementSerial ~= record.serial then
        record.involvementSerial = record.serial
        -- One read for a hostile mob (the usual case); a neutral one is looked at more closely.
        -- A readable "cannot attack" never reaches here: IsVisibleHostile untracks it.
        local reaction = ReadNumberValue(UnitReaction, unit, "player")
        record.neutral = reaction == 4
        record.critter = false
        if record.neutral then
            local creature = ReadString(UnitCreatureType, unit)
            local class = ReadString(UnitClassification, unit)
            record.critter = (creature ~= nil and CRITTER_TYPES[creature] == true)
                or (class ~= nil and TRIVIAL_CLASSES[class] == true)
                or ReadNumberValue(UnitLevel, unit) == 1
        end
    end
    local excluded = false
    if record.critter or record.neutral then
        -- Joined the fight: on the group's threat table (or, for a neutral one, in combat).
        local fighting = OnThreatTable(record)
        if not fighting and record.neutral and not record.critter then
            fighting = ReadBoolean(UnitAffectingCombat, unit) == true
        end
        excluded = not fighting
    end
    record.excluded = excluded == true
end

function ThreatService:UpdateEngaged(record)
    local engaged = type(record.unitDamageAt) == "number" and Now() - record.unitDamageAt < ENGAGEMENT_WINDOW
    if not engaged then engaged = ReadBoolean(UnitAffectingCombat, record.unit) == true end
    if not engaged and (record.tanking == true or (type(record.status) == "number" and record.status > 0)) then
        engaged = true
    end
    record.engaged = engaged
end

-- Who is possibly attacking: the mob took damage recently, so the members targeting it are
-- inferred to be the ones hitting it (the client names no damage source). attackerState: the
-- targeting state (MergeTargeters) while it took damage; "none" when idle, or quiet although the
-- client has reported damage to it before; "no-signal" when engaged but no damage to it was ever
-- reported (UNIT_COMBAT withheld for it, or not hit yet), so nothing can be inferred.
function ThreatService:UpdateActiveAttackers(record)
    local count = 0
    local state = "none"
    if record.unitDamageAt and Now() - record.unitDamageAt < ENGAGEMENT_WINDOW then
        local bucket = record.targeters
        for index = 1, bucket.count do
            count = count + 1
            record.activeAttackerNames[count] = bucket.names[index]
            record.activeAttackerUnits[count] = bucket.units[index]
        end
        state = record.targeterState or "unknown"
    elseif record.engaged and record.damageSeenSerial ~= record.serial then
        state = "no-signal"
    end
    record.attackerState = state
    for index = count + 1, record.activeAttackerCount or 0 do
        record.activeAttackerNames[index] = nil
        record.activeAttackerUnits[index] = nil
    end
    record.activeAttackerCount = count
end

-- The roster entry the mob is targeting: matched by GUID, and by UnitIsUnit only against members
-- whose GUID the client withheld (or when the target's own GUID is withheld). The second result
-- is whether the answer is known: false when a protected UnitIsUnit left a member unchecked.
function ThreatService:FindHolder(targetUnit)
    local guid = ReadGUID(targetUnit)
    if guid then
        local entry = self.rosterByGUID[guid]
        if entry or self.rosterMissingGUID == 0 then return entry, true end
    end
    local known = true
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if not guid or not member.guid then
            local same = ReadBoolean(UnitIsUnit, targetUnit, member.unit)
            if same == true then return member, true end
            if same == nil then known = false end
        end
    end
    return nil, known
end

-- Drops the protected holding answers FoldHolders kept.
local function ClearHoldFlags(record)
    local flags, states = record.holdFlags, record.holdFlagStates
    for index = 1, record.holdFlagCount or 0 do flags[index], states[index] = nil, nil end
    record.holdFlagCount, record.holdFallback, record.holdFlagsHaveSelf = 0, nil, false
end

-- The mob's target by its token: its name (readable, else opaque for the text sink, else the
-- fallback) and class file (possibly protected, for the class-colour sink).
local function NameTarget(record, targetUnit)
    record.targetName, record.targetNameOpaque, record.hasOpaqueTargetName =
        ReadDisplayName(targetUnit, L["Unknown target"])
    record.targetClass, record.hasTargetClass = Secret.ClassFile(targetUnit)
end

local function SetHold(record, state, targetName)
    record.targetName, record.targetUnit = targetName, nil
    record.targetNameOpaque, record.hasOpaqueTargetName = nil, false
    record.targetClass, record.hasTargetClass = nil, false
    record.tankHolds, record.selfHolds, record.loose = false, false, state == "LOOSE"
    record.holdState = state
    ClearHoldFlags(record)
end

-- kept: the holder is carried over (HoldWithoutTarget), so its time is not renewed.
function ThreatService:SetHolder(record, member, kept)
    if not kept then
        record.lastHolderUnit, record.lastHolderAt, record.lastHolderSerial = member.unit, Now(), record.serial
    end
    record.targetName, record.targetUnit = member.name, member.unit
    record.targetNameOpaque, record.hasOpaqueTargetName = member.nameOpaque, member.hasOpaqueName == true
    record.targetClass, record.hasTargetClass = nil, false
    record.tankHolds = member.role == "TANK"
    record.selfHolds = self.isSolo and (member.isPlayer or member.owner == "player")
    record.loose = not record.tankHolds and not record.selfHolds
    record.holdState = record.tankHolds and "TANK" or record.selfHolds and "YOU" or "LOOSE"
    ClearHoldFlags(record)
end

-- Whether a group member other than the player (or the player's pet) has the tank role.
function ThreatService:HasOtherTank()
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if member.role == "TANK" and not member.isPlayer and not member.ownerIsPlayer then return true end
    end
    return false
end

-- In instances Forever can protect the mob's target (existence, GUID and UnitIsUnit) while the
-- player's own threat stays readable, as the threat meter shows. That decides what it can: you
-- hold it, or, as the group's only tank, you do not. Anything else is UNKNOWN, never LOOSE.
-- Otherwise the group's own "holding it" answers decide (FoldHolders).
function ThreatService:HoldFromOwnThreat(record)
    local player = self.playerRosterIndex and self.rosterPool[self.playerRosterIndex]
    local onlyTank = player and player.role == "TANK" and not self.isSolo and not self:HasOtherTank()
    if player and record.tanking == true then
        self:SetHolder(record, player)
    elseif record.tanking == false and onlyTank then
        SetHold(record, "LOOSE", L["Unknown target"])
    else
        SetHold(record, "UNKNOWN", L["Unknown target"])
        self:FoldHolders(record, player, onlyTank)
    end
end

-- Group members whose "holding it" answer FoldHolders reads, besides you: a party's members, or a
-- raid's tanks, at most this many.
local MAX_FOLDED_MEMBERS = 5

-- Who holds a mob when neither its target nor your own threat can say: each member's isTanking
-- from UnitDetailedThreatSituation on it (only one unit can hold it). A readable true names the
-- holder. Protected answers are kept with the state each would mean (holdFlags, holdFlagStates:
-- TANK for a tank, else LOOSE; yours first, as SetHolder would give it, with holdFlagsHaveSelf),
-- and holdFallback for none of them: the tank window and plates pass them to the client's boolean
-- sinks, and the record stays
-- UNKNOWN (not loose, for counts and order). Lua never branches on a protected answer.
function ThreatService:FoldHolders(record, player, onlyTank)
    local flags, states = record.holdFlags, record.holdFlagStates
    local count = 0
    if player and record.tanking == nil and record.hasOpaqueTanking then
        count = 1
        flags[1] = record.tankingOpaque
        states[1] = player.role == "TANK" and "TANK" or (self.isSolo and "YOU") or "LOOSE"
        record.holdFlagCount, record.holdFlagsHaveSelf = count, true
    end
    local source = record.threatMobSource
    local mob = (source ~= nil and source ~= "nameplate") and source or record.unit
    -- Whether every answer read was readable (a raid's non-tanks are not read, so never there).
    local complete = (record.tanking ~= nil or record.playerThreatNoEntry == true) and not self.isRaid
    local folded = 0
    for index = 1, self.rosterCount do
        if folded >= MAX_FOLDED_MEMBERS then break end
        local member = self.rosterPool[index]
        if member.isMember and not member.isPlayer and (not self.isRaid or member.role == "TANK") then
            folded = folded + 1
            local ok, tanking = self:ReadMemberThreat(index, member.unit, mob)
            if not (ok and IsReadable(tanking) and type(tanking) == "boolean") then
                -- Withheld: the member's threat status on it (readable where the values are not;
                -- ReadThreatSituation), 2 or 3 holding it.
                local status = ReadThreatValue(UnitThreatSituation, member.unit, mob)
                if status ~= nil then ok, tanking = true, status >= 2 end
            end
            if ok and IsReadable(tanking) and tanking == true then
                self:SetHolder(record, member)
                return true
            elseif ok and IsSecret(tanking) then
                count = count + 1
                flags[count], states[count] = tanking, member.role == "TANK" and "TANK" or "LOOSE"
                record.holdFlagCount = count
                complete = false
            elseif not ok or not IsReadable(tanking) then
                complete = false
            end
        end
    end
    if folded >= MAX_FOLDED_MEMBERS then complete = false end
    record.holdFallback = count > 0 and (onlyTank and "LOOSE" or "UNKNOWN") or nil
    return complete
end

-- How long the last holder is kept once a mob has no target (fear, stun, fleeing at low health).
local HOLDER_KEPT = 3

-- A mob with (readably) no target: running away, feared or stunned, it is still held by whoever
-- held it. The last holder is kept for HOLDER_KEPT seconds; you hold it when your readable threat
-- says so (tanking, status 2 or 3, or the top of the group's readable threat); protected answers
-- are folded as for a "?" row (FoldHolders, LOOSE for none of them). LOOSE only when every answer
-- is readable and nobody in the group holds it.
function ThreatService:HoldWithoutTarget(record)
    local last = record.lastHolderUnit and self.rosterByUnit[record.lastHolderUnit]
    if last and record.lastHolderSerial == record.serial and record.lastHolderAt
        and Now() - record.lastHolderAt < HOLDER_KEPT then
        self:SetHolder(record, last, true)
        return
    end
    local player = self.playerRosterIndex and self.rosterPool[self.playerRosterIndex]
    local status, differential = record.status, record.playerDifferential
    if player and (record.tanking == true or (type(status) == "number" and status >= 2)
        or (type(differential) == "number" and differential >= 0 and record.playerThreatNoEntry ~= true
            and type(record.rawThreat) == "number" and record.rawThreat > 0)) then
        self:SetHolder(record, player)
        return
    end
    SetHold(record, "UNKNOWN", L["No target"])
    local complete = self:FoldHolders(record, player, true)
    if record.targetUnit ~= nil then return end
    if record.holdFlagCount == 0 and complete then SetHold(record, "LOOSE", L["No target"]) end
end

function ThreatService:FindTarget(record)
    -- Whether the holder was named by the mob's own (readable) target, not inferred.
    record.holdFromTarget = false
    if not record.engaged then
        SetHold(record, "IDLE", L["No target"])
        return
    end
    -- The confirmed target's own "targettarget" is often readable where the plate's is not (and
    -- likewise "mouseovertarget" and "focustarget" for a borrowed token).
    local source = record.threatMobSource
    local targetUnit = (source ~= nil and source ~= "nameplate") and TargetToken(source) or record.targetToken
    local exists = ReadBoolean(UnitExists, targetUnit)
    if exists == false then
        self:HoldWithoutTarget(record)
        return
    end
    if exists == true then
        local member, known = self:FindHolder(targetUnit)
        if member then
            self:SetHolder(record, member)
            record.holdFromTarget = true
            return
        end
        if known then
            -- Held by someone outside the group.
            SetHold(record, "LOOSE", L["Unknown target"])
            NameTarget(record, targetUnit)
            return
        end
    end
    -- The mob's target cannot be matched to the group (or even said to exist): unless a group
    -- member was found holding it, the ON column still names it and colours it by class, through
    -- the text and class-colour sinks when protected (nothing when the client gives no name).
    self:HoldFromOwnThreat(record)
    if record.targetUnit == nil then NameTarget(record, targetUnit) end
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
    -- A scan through another token (the plate's, or a member's target) may be blocked where this one
    -- is not.
    if priority or record.groupScanSerial ~= record.serial or record.groupScanRoster ~= self.rosterRevision
        or record.groupScanMob ~= mob or not record.groupScanAt or now - record.groupScanAt >= GROUP_SCAN_INTERVAL then
        record.groupHighest, record.groupBlockedState, record.groupBlocker = self:ScanGroupThreat(mob)
        record.groupScanAt, record.groupScanSerial, record.groupScanRoster = now, record.serial, self.rosterRevision
        record.groupScanMob = mob
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

-- A group member's target token ("party2target") that names this record's plate, for a plate whose
-- own threat read was not readable: like the mouseover, a member's target can read threat the
-- plate's token cannot, and it is matched the same way, by the plate frame the client gives for
-- it. Only members whose target was last read as this plate are asked (one lookup each); one that
-- has moved on is read again at the next flush.
function ThreatService:MemberBorrowedToken(record)
    local root = record.root
    if record.plateThreat ~= "blocked" or root == nil then return nil end
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        -- The player's own target is "target", borrowed first.
        if member.isMember and not member.isPlayer then
            if member.plateFrame == root then
                if TokenPlateFrame(member.targetToken) == root then return member.targetToken end
                member.targetDirty, self.targetersDirty = true, true
            elseif member.targetGUID ~= nil and member.targetGUID == record.guid
                and MemberTargetsRecord(member.targetToken, record) then
                -- Forever refuses the plate lookup for "party1target": matched by readable GUID instead.
                return member.targetToken
            end
        end
    end
    return nil
end

-- The player's threat status on mob from UnitThreatSituation, when the detailed read withholds it.
-- Blizzard's secret predicates keep the threat STATE between you and a nameplate readable where its
-- VALUES (UnitDetailedThreatSituation, the lead percentage) are not, and Blizzard's own plates and
-- other nameplate addons colour by it. 3 is tanking, 2 tanking but losing it, 1 not tanking but
-- above the holder, 0 not tanking; isTanking follows it when the detailed read withheld that too.
-- A protected or missing status changes nothing (situationState says which, for /ps diagnose).
function ThreatService:ReadThreatSituation(record, mob)
    local status, _, state = ReadThreatValue(UnitThreatSituation, "player", mob)
    record.situationState = state
    if status == nil then return end
    record.status, record.statusSource = status, "situation"
    if record.tanking == nil then record.tanking = status >= 2 end
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
    record.statusSource, record.situationState = nil, "not read"
    record.tankingOpaque, record.hasOpaqueTanking = nil, false
    record.playerThreatNoEntry = false
    record.outsideHolderThreat = nil

    -- Forever can expose readable threat through the player's target while the
    -- equivalent nameplate token remains protected. Only borrow that token for
    -- the exact current mob; never match by name or infer an arbitrary GUID.
    -- The focus and mouseover tokens are borrowed the same way, for the mob focused or under the
    -- mouse (matched by the plate the client names for them), then a group member's target.
    local targetMatched = SameUnit(record.unit, "target")
    local borrowed = targetMatched and "target" or BorrowedToken(record)
    local memberBorrowed = false
    if not borrowed then
        borrowed = self:MemberBorrowedToken(record)
        memberBorrowed = borrowed ~= nil
    end
    record.memberBorrowed = memberBorrowed
    local mob = borrowed or record.unit
    record.threatMobSource = borrowed or "nameplate"
    record.leadPercent, record.leadPercentOpaque, record.leadPercentState =
        ReadThreatValue(UnitThreatPercentageOfLead, "player", mob)
    record.hasOpaqueLeadPercent = record.leadPercentState == "protected/displayable"
    record.leadSituation, record.leadSituationOpaque, record.leadSituationState =
        ReadThreatValue(UnitThreatLeadSituation, "player", mob)
    record.hasOpaqueLeadSituation = record.leadSituationState == "protected/displayable"

    if type(UnitDetailedThreatSituation) ~= "function" then return self:ReadThreatSituation(record, mob) end

    local ok, tanking, status, scaledPercent, rawPercent, raw
    if self.playerRosterIndex then
        ok, tanking, status, scaledPercent, rawPercent, raw = self:ReadMemberThreat(self.playerRosterIndex, "player", mob)
    else
        ok, tanking, status, scaledPercent, rawPercent, raw = pcall(UnitDetailedThreatSituation, "player", mob)
    end
    if not ok then return self:ReadThreatSituation(record, mob) end
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
    if IsReadable(tanking) and type(tanking) == "boolean" then
        record.tanking = tanking
    elseif IsSecret(tanking) then
        -- Kept only for the client's boolean sinks (Secret.Pick): the windows and plates show
        -- what it would mean either way without Lua branching on it.
        record.tankingOpaque, record.hasOpaqueTanking = tanking, true
    end
    if IsReadable(status) and type(status) == "number" then
        record.status, record.statusSource = status, "detailed"
    else
        self:ReadThreatSituation(record, mob)
    end
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

    -- A member's target is read like any other plate (GROUP_SCAN_INTERVAL), not on every refresh.
    local highestOther, blockedState, blocker =
        self:GroupHighest(record, mob, self:IsPriority(record, borrowed ~= nil and not memberBorrowed))
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
            -- Clearly above every group member (not the holder's own total come back with rounding):
            -- held outside the group, for the threat meter's outside-group row (readable only).
            if holder - highestOther > math.max(1, highestOther * 0.001) then
                record.outsideHolderThreat = math.floor(holder + 0.5)
            end
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
    if memberBorrowed then
        if TokenPlateFrame(borrowed) ~= record.root and not MemberTargetsRecord(borrowed, record) then
            record.differentialState = "member-target-changed"
            return
        end
    elseif borrowed and not targetMatched and BorrowedToken(record) ~= borrowed then
        record.differentialState = "hover-changed"
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

-- Settings › Experimental (Outside-group holder row): the unit holding the measured enemy from outside
-- the group, as one more row after the count members, when ReadThreat recovered its threat total
-- (outsideHolderThreat, readable) and no member holds it. Its name is the mob's target's, readable
-- only; else "Outside group". The entry, or nil.
function ThreatService:AddOutsideHolder(record, count)
    local settings = Settings()
    local total = record.outsideHolderThreat
    if not (settings and settings.experimentalOutsideHolderRow == true) or type(total) ~= "number"
        or count >= MAX_ROSTER_UNITS then
        return nil
    end
    for index = 1, count do
        if self.groupThreat[index].tanking == true then return nil end
    end
    local source = record.threatMobSource
    local name = (source ~= nil and source ~= "nameplate") and Secret.ReadName(TargetToken(source)) or nil
    if not name and record.targetToken then name = Secret.ReadName(record.targetToken) end
    local entry = self.groupThreat[count + 1]
    entry.unit, entry.role, entry.classToken = nil, nil, nil
    entry.name = name and string.format(L["%s (outside group)"], name) or L["Outside group"]
    entry.nameOpaque, entry.hasOpaqueName = nil, false
    entry.isPlayer, entry.isPet, entry.isOutside, entry.order = false, false, true, 0
    -- It holds the mob, so its threat is the 100% everyone else's is measured against.
    entry.tanking, entry.percent, entry.percentOpaque, entry.hasOpaquePercent = true, 100, nil, false
    entry.raw, entry.rawOpaque, entry.hasOpaqueRaw, entry.gap = total, nil, false, nil
    self.outsideRowsShown = (self.outsideRowsShown or 0) + 1
    self.outsideLastThreat = total
    return entry
end

-- Every roster member's threat on the player's current target, for the threat meter windows.
-- Only the confirmed current target is read (the token Forever makes readable most often).
-- Protected values are kept opaque for display sinks; the gap to pulling (the holder's raw
-- threat x 1.1, the melee rule) and the order are only calculated from readable numbers.
function ThreatService:ReadGroupThreat(record)
    local count, holderRaw, allReadable = 0, nil, true
    -- True only when every member was read and none is on the mob's threat table.
    local noThreat = type(UnitDetailedThreatSituation) == "function" and self.rosterCount > 0
    self.groupThreatRecord = record
    if type(UnitDetailedThreatSituation) == "function" then
        for index = 1, self.rosterCount do
            local member = self.rosterPool[index]
            local ok, tanking, status, scaled, rawPercent, raw = self:ReadMemberThreat(index, member.unit, "target")
            if not ok then noThreat = false end
            -- A complete, readable nil tuple is no entry on this mob's table: no row.
            if ok and not IsNoEntry(tanking, status, scaled, rawPercent, raw) then
                noThreat = false
                count = count + 1
                local entry = self.groupThreat[count]
                entry.unit, entry.name, entry.role = member.unit, member.name, member.role
                entry.nameOpaque, entry.hasOpaqueName = member.nameOpaque, member.hasOpaqueName == true
                entry.isPlayer, entry.isPet, entry.order = member.isPlayer, not member.isMember, index
                entry.classToken, entry.isOutside = member.classToken, false
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
    local outside = self:AddOutsideHolder(record, count)
    if outside then
        count, holderRaw, noThreat = count + 1, outside.raw, false
    end
    for index = count + 1, self.groupThreatCount do
        local entry = self.groupThreat[index]
        entry.unit, entry.name, entry.percentOpaque, entry.rawOpaque = nil, nil, nil, nil
        entry.nameOpaque, entry.hasOpaqueName = nil, false
    end
    self.groupThreatCount, self.groupThreatNone = count, noThreat
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
    self.groupThreatCount, self.groupThreatNone = 0, false
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

-- The threat meter's enemy when no tracked plate is read through "target" (the target has no plate,
-- or the client will not match its plate to "target"): the group is read through "target" itself,
-- which needs no plate, when it is a living enemy you can attack. At most every
-- GROUP_THREAT_INTERVAL, from the tick; a matched plate (RequestGroupThreat) takes precedence.
function ThreatService:ReadTargetScope(now)
    if self.targetScopeAt and now - self.targetScopeAt < GROUP_THREAT_INTERVAL then return end
    self.targetScopeAt = now
    local scope, current = self.targetScope, self.groupThreatRecord
    if current and current ~= scope and current.unit and current.threatMobSource == "target"
        and SameUnit(current.unit, "target") then
        return
    end
    local attackable = UnitExistsSafely("target") and ReadBoolean(UnitCanAttack, "player", "target") == true
        and ReadBoolean(UnitIsDeadOrGhost, "target") ~= true and ReadBoolean(UnitIsDead, "target") ~= true
    if not attackable then
        if current == scope then self:ClearTargetScope() end
        return
    end
    scope.guid = ReadGUID("target")
    scope.enemyName, scope.enemyNameOpaque, scope.hasOpaqueName = ReadDisplayName("target", nil)
    self.groupThreatReadAt, self.groupThreatPending = now, nil
    -- A later tick: nothing read in the last refresh pass may be reused.
    self.threatPass = self.threatPass + 1
    self.targetScopeReads = (self.targetScopeReads or 0) + 1
    self:ReadGroupThreatSafely(scope)
end

-- The target changed or went away: the meter's "target" read is no longer about it.
function ThreatService:ClearTargetScope()
    self.targetScopeAt = nil
    if self.groupThreatRecord ~= self.targetScope then return end
    self.groupThreatRecord, self.groupThreatCount, self.groupThreatNone = nil, 0, false
    self.groupThreatRevision = self.groupThreatRevision + 1
end

-- The measured record, the row count, the pooled rows, and whether the client showed that nobody
-- in the group has threat on it yet; nil and 0 when "target" is not the enemy last read. The record
-- is a tracked plate's, or targetScope (targetScoped, no plate) from ReadTargetScope.
function ThreatService:GetGroupThreat()
    local record = self.groupThreatRecord
    if not record or not record.unit or not SameUnit(record.unit, "target") then return nil, 0, self.groupThreat, false end
    return record, self.groupThreatCount, self.groupThreat, self.groupThreatCount == 0 and self.groupThreatNone == true
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
        self.targetScopeAt = nil
    end
end

local function ShownChanged(record)
    if record.hasOpaquePercent or record.hasOpaqueLeadPercent or record.hasOpaqueRawThreat
        or record.hasOpaqueLeadSituation or record.hasOpaqueTanking or (record.holdFlagCount or 0) > 0
        or record.hasOpaqueTargetName or record.hasTargetClass then
        return true
    end
    local shown = record.shown
    for index = 1, #SHOWN_FIELDS do
        local field = SHOWN_FIELDS[index]
        if shown[field] ~= record[field] then return true end
    end
    return false
end

-- Differential states that mean the token read gave no usable threat (ReadThreat).
local BLOCKED_READS = {
    ["unavailable"] = true, ["error"] = true, ["protected-player-threat"] = true, ["player-threat-unavailable"] = true,
    ["protected-group-threat"] = true, ["group-threat-unavailable"] = true,
}

-- The enemy's name: readable, else opaque for a text sink (the plate token only when the client
-- gives no name at all). A plate's name can be protected while "target" names the same mob, so
-- the borrowed token (target, mouseover or focus) is asked too.
function ThreatService:ReadEnemyName(record)
    local name, opaque, hasOpaque = ReadDisplayName(record.unit, nil)
    local source = record.threatMobSource
    if name == nil and source ~= nil and source ~= "nameplate" then
        local targetName, targetOpaque, targetHasOpaque = ReadDisplayName(source, nil)
        if targetName ~= nil or targetHasOpaque then name, opaque, hasOpaque = targetName, targetOpaque, targetHasOpaque end
    end
    if name == nil and not hasOpaque then name = record.unit end
    record.enemyName, record.enemyNameOpaque, record.hasOpaqueName = name, opaque, hasOpaque
end

-- A gap read through the mouseover, focus, a boss or a member's target token is kept on the record; once
-- the plate's own reads (or a protected member-target read) give none, it is shown again for
-- the profile's hold (KeptHold; the same mob only: its serial). A later borrowed read of the mob replaces it.
function ThreatService:KeepBorrowedLead(record)
    local source = record.threatMobSource
    -- Any live gap is kept, the target's too: outdoors the target is often the only token that
    -- reads one, so a gap seen while targeting stays (marked "~") after the target moves on.
    if source ~= "nameplate" and type(record.lead) == "number" then
        record.keptLead, record.keptLeadKind, record.keptPercent = record.lead, record.leadKind, record.percent
        record.keptTanking, record.keptStatus = record.tanking, record.status
        record.keptAt, record.keptSerial = Now(), record.serial
        record.leadKept = false
        return
    end
    -- A token that read no gap (a protected hover, the plate's own) falls back to the kept one.
    local hold = KeptHold()
    local fresh = record.keptAt ~= nil and record.keptSerial == record.serial
        and (hold == nil or Now() - record.keptAt < hold)
    -- One that read no gap but a readable "are you holding it" answer keeps that answer alone (not
    -- the percent, which would show as live) for the same hold, so the hold state and threat colours
    -- stay with it; a kept gap still held is not replaced.
    if source ~= "nameplate" and type(record.tanking) == "boolean" and not (fresh and record.keptLead ~= nil) then
        record.keptLead, record.keptLeadKind, record.keptPercent = nil, nil, nil
        record.keptTanking, record.keptStatus = record.tanking, record.status
        record.keptAt, record.keptSerial = Now(), record.serial
        record.leadKept = false
        return
    end
    local kept = source ~= "target" and record.lead == nil and BLOCKED_READS[record.differentialState] == true and fresh
    record.leadKept = kept and record.keptLead ~= nil
    if kept then
        -- The hold state and LOSING follow the kept read too (FindTarget runs after this).
        record.lead, record.leadKind = record.keptLead, record.keptLeadKind
        if record.percent == nil and not record.hasOpaquePercent then record.percent = record.keptPercent end
        if record.tanking == nil then record.tanking = record.keptTanking end
        if record.status == nil then record.status = record.keptStatus end
    elseif record.keptAt ~= nil and not fresh then
        record.keptLead, record.keptLeadKind, record.keptPercent, record.keptAt, record.keptSerial = nil, nil, nil, nil, nil
        record.keptTanking, record.keptStatus = nil, nil
    end
end

-- The last read through the mouseover, for /ps diagnose (threatMouseover): readable facts only.
function ThreatService:NoteMouseoverRead(record)
    local probe = self.mouseoverProbe
    probe.readAt, probe.readUnit = Now(), record.unit
    -- The token every call of this read went through (ReadThreat's mob), and what the player's own
    -- tuple gave through it.
    probe.token = record.threatMobSource
    probe.playerRaw = record.rawThreatState or "unavailable"
    probe.playerTanking = record.tanking ~= nil and "readable" or (record.hasOpaqueTanking and "protected" or "none")
    probe.playerPercent = type(record.percent) == "number" and "readable"
        or (record.hasOpaquePercent and "protected" or "none")
    probe.differential, probe.blocker = record.differentialState or "unavailable", record.differentialBlocker or "none"
    probe.groupRead = record.differentialState == "readable" and "readable"
        or (record.differentialState == "protected-group-threat" and "protected") or "not reached"
    probe.lead = type(record.lead) == "number" and record.lead or "none"
    probe.leadKind = record.leadKind or "none"
    local text = PS.ThreatText and PS.ThreatText.Record
    probe.display = type(text) == "function" and text(record) or ""
end

-- Settings › Experimental (Solo hover gap): solo, the gap while you hold a mob is your raw threat x 1.1
-- (nobody else is on its table). With only a protected raw threat, a linear client curve
-- (0 -> 0, CURVE_TOP -> CURVE_TOP x 1.1) evaluates that inside the client; Lua never compares or
-- computes with the value, which goes to the plate's format sink as it is (ThreatText).
local CURVE_TOP = 1e9
local curveGap -- the curve, made once; false when the client has none
ThreatService.curveStats = { state = "not tried", evaluated = 0, failed = 0, shown = 0 }

local function CurveGap()
    if curveGap ~= nil then return curveGap end
    curveGap = false
    local util, kinds = C_CurveUtil, Enum and Enum.LuaCurveType
    local linear = kinds and kinds.Linear
    if util and type(util.CreateCurve) == "function" and linear ~= nil then
        local ok, made = pcall(util.CreateCurve)
        if ok and made ~= nil and pcall(made.SetType, made, linear) and pcall(made.AddPoint, made, 0, 0)
            and pcall(made.AddPoint, made, CURVE_TOP, CURVE_TOP * 1.1) then
            curveGap = made
        end
    end
    return curveGap
end

function ThreatService:ReadCurveGap(record)
    record.curveLeadOpaque, record.hasCurveLead, record.curveState = nil, false, nil
    local settings = Settings()
    if not (settings and settings.experimentalSoloCurveGap == true) then return end
    -- The mob's own target names you (YOU, or TANK for a solo tank): only then is the gap raw x 1.1.
    -- A kept gap (an older readable read) does not stop it: a live curve read is newer.
    if not self.isSolo or not record.hasOpaqueRawThreat or (record.lead ~= nil and not record.leadKept)
        or record.targetUnit ~= "player"
        or not record.holdFromTarget then
        return
    end
    local stats = self.curveStats
    local curve = CurveGap()
    if not curve then
        record.curveState, stats.state = "curve-missing", "curve-missing"
        return
    end
    local ok, value = pcall(curve.Evaluate, curve, record.rawThreatOpaque)
    if not ok or not (IsSecret(value) or (IsReadable(value) and type(value) == "number")) then
        record.curveState, stats.state, stats.failed = "evaluate-failed", "evaluate-failed", stats.failed + 1
        -- What the client said, for /ps diagnose: its error text, or the kind of value it gave back.
        if not ok then
            stats.lastError = IsReadable(value) and type(value) == "string" and value:sub(1, 160) or "unreadable error"
        else
            stats.lastError = IsReadable(value) and ("returned " .. type(value)) or "returned unreadable"
        end
        return
    end
    record.curveLeadOpaque, record.hasCurveLead = value, true
    record.curveState, stats.state, stats.evaluated = "evaluated", "evaluated", stats.evaluated + 1
end

-- For /ps diagnose (experimental): each test's switch and what it saw. Readable words and counts only;
-- a token is looked up here only while its test is on.
function ThreatService:ExperimentalReport()
    local settings = Settings() or {}
    local function Tokens(tokens, on)
        local report = {}
        for _, token in ipairs(tokens) do
            local stat = experimentalTokens[token]
            if on then ExperimentalTokenExists(token) end
            report[token] = { exists = on and stat.exists or "off", reads = stat.reads, last = stat.last }
        end
        return report
    end
    local soft, chain = settings.experimentalSoftTargetThreat == true, settings.experimentalTargetOfTargetThreat == true
    local curveOn, outsideOn = settings.experimentalSoloCurveGap == true, settings.experimentalOutsideHolderRow == true
    local stats = self.curveStats
    local curve = "off"
    if curveOn then curve = CurveGap() and "available" or "curve-missing" end
    return {
        softTargets = { enabled = soft, tokens = Tokens(SOFT_TOKENS, soft) },
        targetOfTarget = { enabled = chain, tokens = Tokens(CHAIN_TOKENS, chain) },
        soloCurveGap = { enabled = curveOn, solo = self.isSolo == true, curve = curve,
            state = curveOn and stats.state or "off", evaluated = stats.evaluated, failed = stats.failed, shown = stats.shown,
            lastError = stats.lastError or "none" },
        outsideHolderRow = { enabled = outsideOn, rowsShown = self.outsideRowsShown or 0,
            lastThreat = self.outsideLastThreat or "none" },
    }
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

    self:UpdateRecordGUID(record)
    -- A failed read must not leave the record dirty or skip the engagement and hold state below.
    if not pcall(self.ReadThreat, self, record) then
        record.differentialState, record.differentialBlocker = "error", nil
    end
    -- Whether the plate's own token read threat: a member's target is borrowed only for one that did
    -- not (MemberBorrowedToken). Protected through the member's target too, the plate is tried again.
    local readable = not BLOCKED_READS[record.differentialState]
    if record.threatMobSource == "nameplate" then
        record.plateThreat = readable and "readable" or "blocked"
    elseif record.memberBorrowed and not readable then
        record.plateThreat = nil
    end
    self:ReadTokenTargeters(record)
    self:MergeTargeters(record)
    -- A read through an experimental token (only tried while its test is on), for /ps diagnose.
    local tokenStat = experimentalTokens[record.threatMobSource]
    if tokenStat then tokenStat.reads, tokenStat.last = tokenStat.reads + 1, record.differentialState or "unavailable" end
    self:KeepBorrowedLead(record)
    if record.threatMobSource == "mouseover" then self:NoteMouseoverRead(record) end
    self:ReadEnemyName(record)
    if self.groupThreatWanted and record.threatMobSource == "target" then self:RequestGroupThreat(record) end
    self:UpdateEngaged(record)
    self:UpdateActiveAttackers(record)
    self:FindTarget(record)
    self:ReadCurveGap(record)
    record.dirty = false
    record.refreshedAt = Now()
    record.revision = record.revision + 1
    if ShownChanged(record) then self.snapshotDirty = true end
    return true
end

-- A plate frame is reused for another mob: members whose target was read as that frame are read
-- again at the next flush, so no member is listed on the new mob from an old answer.
function ThreatService:RecheckPlateTargets(root)
    if root == nil then return end
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if member.plateFrame == root then
            member.targetDirty = true
            self.targetersDirty = true
        end
    end
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
        if record.root ~= root then
            self.snapshotDirty = true
            self:RecheckPlateTargets(record.root)
            self:RecheckPlateTargets(root)
        end
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
    self:RecheckPlateTargets(root)
    record.plateThreat, record.memberBorrowed = nil, false
    self.nextRecordSerial = self.nextRecordSerial + 1
    record.serial = self.nextRecordSerial
    record.dirty, record.revision = true, 0
    record.enemyName, record.targetName, record.targetUnit = unit, L["No target"], nil
    record.enemyNameOpaque, record.hasOpaqueName, record.targetNameOpaque, record.hasOpaqueTargetName = nil, false, nil, false
    record.tankHolds, record.selfHolds, record.loose, record.engaged = false, false, false, false
    record.holdState = "IDLE"
    record.guid = ReadGUID(unit)
    record.knownGUID = record.guid
    record.targeterCount, record.targeterState, record.guidTargeterCount = 0, "unknown", 0
    record.activeAttackerCount, record.attackerState, record.damageSeenSerial = 0, "none", nil
    record.unitDamageAt = nil
    ClearDamage(record)
    record.groupScanAt, record.groupHighest, record.groupBlockedState, record.groupBlocker = nil, nil, nil, nil
    if record.guid then self.enemyByGUID[record.guid] = record end
    record.playerPercent, record.playerDifferential = nil, nil
    record.playerThreatNoEntry = false
    record.percent, record.lead, record.tanking, record.status = nil, nil, nil, nil
    record.tankingOpaque, record.hasOpaqueTanking = nil, false
    ClearHoldFlags(record)
    record.keptLead, record.keptLeadKind, record.keptPercent, record.keptAt, record.keptSerial = nil, nil, nil, nil, nil
    record.keptTanking, record.keptStatus = nil, nil
    record.leadKept = false
    record.leadKind = nil
    record.outsideHolderThreat, record.holdFromTarget = nil, false
    record.curveLeadOpaque, record.hasCurveLead, record.curveState = nil, false, nil
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
    local tokens, merged = record.tokenTargeters, record.targeters
    for index = 1, tokens.count do tokens.names[index], tokens.units[index] = nil, nil end
    for member in pairs(tokens.answers) do tokens.answers[member] = nil end
    tokens.count, tokens.source, tokens.serial, tokens.readAt = 0, nil, nil, nil
    for index = 1, merged.count do merged.names[index], merged.units[index] = nil, nil end
    merged.count = 0
    self:RecheckPlateTargets(record.root)
    record.unit, record.root, record.guid, record.dirty = nil, nil, nil, false
    record.enemyNameOpaque, record.targetNameOpaque, record.curveLeadOpaque, record.hasCurveLead = nil, nil, nil, false
    self.freeCount = self.freeCount + 1
    self.freeRecords[self.freeCount] = record
    if self.cursor > self.enemyCount then self.cursor = 0 end
    self.snapshotDirty = true
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
-- The same for the mouseover and focus tokens; when the client will not name their plate, only the
-- record last read through them (a hover must not re-read every plate).
function ThreatService:MarkTokenChanged(unit)
    local known, token = PlateToken(unit)
    if not known and unit == "target" then return self:MarkDirty() end
    local frame = not known and TokenPlateFrame(unit) or nil
    local matched
    for index = 1, self.enemyCount do
        local record = self.enemyOrder[index]
        local names = (token ~= nil and record.unit == token) or (frame ~= nil and record.root == frame)
        if names then matched = record.unit end
        if record.threatMobSource == unit or names then record.dirty = true end
    end
    if unit == "mouseover" then
        -- For /ps diagnose (threatMouseover): which plate the hover named, and how.
        local probe = self.mouseoverProbe
        probe.matched = matched or false
        probe.route = (known and token and "plate-token") or (frame and "plate-frame")
            or (known and "no-plate") or "unknown"
    end
    self:Hurry()
end

function ThreatService:MarkTargetChanged()
    self:ClearTargetScope()
    return self:MarkTokenChanged("target")
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
-- members that retargeted, and only re-read (and re-merge) the records whose targeters could have
-- changed: engaged ones, ones whose GUID count moved or whose list is uncertain, and every record
-- when a member's target became readable or protected.
function ThreatService:FlushTargeters()
    if not self.targetersDirty then return end
    self.targetersDirty, self.targetKnownChanged = false, false
    self:RebuildTargeterCounts(true)
    local all, touched = self.targetKnownChanged, self.touchedPlates
    for index = 1, self.enemyCount do
        local record = self.enemyOrder[index]
        local bucket = record.guid and self.attackerTargets[record.guid]
        if all or record.engaged or record.targeterState == "partial" or record.targeterState == "unknown"
            or (bucket and bucket.count or 0) ~= record.guidTargeterCount or touched[record.root] then
            record.dirty = true
            -- Merged now, so the re-read below sees no change: the snapshot is marked here.
            local revision = record.targeterRevision
            self:MergeTargeters(record)
            if record.targeterRevision ~= revision then self.snapshotDirty = true end
        end
    end
    for frame in pairs(touched) do touched[frame] = nil end
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
    return record and record.targeters or nil
end

-- How many group members target this enemy (MergeTargeters), and how sure that is: "confirmed",
-- "none", "partial" (at least that many) or "unknown" (also for an enemy that is not tracked).
function ThreatService:GetTargeterCount(unit)
    local bucket = GetTargeterBucket(self, unit)
    if not bucket then return 0, "unknown" end
    return bucket.count, self.enemyByUnit[unit].targeterState or "unknown"
end

function ThreatService:GetTargeter(unit, index)
    if not IsReadable(index) or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
        return nil, nil
    end
    local bucket = GetTargeterBucket(self, unit)
    if not bucket or index > bucket.count then return nil, nil end
    return bucket.names[index], bucket.units[index], self:MemberNameOpaque(bucket.units[index])
end

-- A roster member's protected name for a text sink, and whether there is one.
function ThreatService:MemberNameOpaque(unit)
    local member = type(unit) == "string" and self.rosterByUnit[unit]
    if member and member.hasOpaqueName then return member.nameOpaque, true end
    return nil, false
end

-- The number of possible attackers (UpdateActiveAttackers) and its state: "confirmed", "none",
-- "partial" (at least that many), "unknown" (targeting hidden) or "no-signal" (no damage reported).
function ThreatService:GetActiveAttackerCount(unit)
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    if not record then return 0, "unknown" end
    return record.activeAttackerCount or 0, record.attackerState or "unknown"
end

-- The name and unit of an inferred attacker (see UpdateActiveAttackers), then a protected name for
-- a text sink and whether there is one (the readable name is then nil). GetTargeter is the same.
function ThreatService:GetActiveAttacker(unit, index)
    if not IsReadable(index) or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
        return nil, nil
    end
    local record = type(unit) == "string" and self.enemyByUnit[unit]
    if not record or index > record.activeAttackerCount then return nil, nil end
    local attacker = record.activeAttackerUnits[index]
    return record.activeAttackerNames[index], attacker, self:MemberNameOpaque(attacker)
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
            -- Critters and mobs not in the fight are left out of the list and its counts. Decided here,
            -- so only a shown Tank window pays for it (its inputs are shown fields, which rebuild this).
            if record and record.unit then self:UpdateExcluded(record) end
            if record and record.unit and not record.excluded then
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
-- A form, form cast or aura only matters as tank evidence; talents (and a new pull) can also change the spec.
local EVIDENCE_EVENTS = { UPDATE_SHAPESHIFT_FORM = true, UPDATE_SHAPESHIFT_FORMS = true, UNIT_AURA = true,
    UNIT_SPELLCAST_SUCCEEDED = true }
local FORM_EVENTS = { UPDATE_SHAPESHIFT_FORM = true, UNIT_SPELLCAST_SUCCEEDED = true }
local ROLE_EVENTS = { CHARACTER_POINTS_CHANGED = true, PLAYER_TALENT_UPDATE = true, PLAYER_REGEN_DISABLED = true }
-- The borrowed token each event changes (MarkTokenChanged).
local BORROW_EVENTS = { UPDATE_MOUSEOVER_UNIT = "mouseover", PLAYER_FOCUS_CHANGED = "focus" }

-- With nothing reading threat, events only note what must be redone on waking: a plate
-- removal is applied (it is cheap and leaves no stale record), additions are rescanned, and
-- the roster and role are rebuilt.
function ThreatService:NoteWhileAsleep(event, unit)
    -- A hover, focus or boss change while nothing reads threat: the wake re-reads every record anyway.
    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" or event == "UNIT_TARGETABLE_CHANGED" then
        SyncBossTokens()
        return
    end
    if BORROW_EVENTS[event] then
        if event == "UPDATE_MOUSEOVER_UNIT" then self.mouseoverProbe.asleep = (self.mouseoverProbe.asleep or 0) + 1 end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        self:UntrackEnemy(unit)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        self.platesDirty = true
    elseif ROSTER_EVENTS[event] then
        self.rosterDirty = true
        if event == "PLAYER_ENTERING_WORLD" then
            self.platesDirty = true
            SyncBossTokens()
        end
    elseif ROLE_EVENTS[event] or (EVIDENCE_EVENTS[event]
        and (event ~= "UNIT_AURA" or (IsReadable(unit) and unit == "player"))) then
        self.roleDirty = true
    end
    self.missedEvents = true
end

function ThreatService:HandleEvent(event, unit, action, spellID)
    if not self.eventsEnabled then return end
    -- Before anything wakes: on a client without unit-filtered events every unit's casts arrive.
    if FORM_EVENTS[event] and not self:NoteFormEvent(event, unit, spellID) then return end
    if not self.tickerEnabled then
        self:WakeTicker()
        if not self.tickerEnabled then return self:NoteWhileAsleep(event, unit) end
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        self:TrackEnemy(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        self:UntrackEnemy(unit)
    elseif ROSTER_EVENTS[event] then
        if event == "PLAYER_ENTERING_WORLD" then SyncBossTokens() end
        self:MarkRosterDirty()
    elseif EVIDENCE_EVENTS[event] then
        -- A stance, form, form cast or aura can make the player the tank (or stop it), but only as
        -- evidence. Each one resolves the role on the next tick, in combat too.
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
    elseif BORROW_EVENTS[event] then
        local token = BORROW_EVENTS[event]
        if token == "mouseover" then
            local probe = self.mouseoverProbe
            probe.events, probe.eventAt = probe.events + 1, Now()
        end
        self:MarkTokenChanged(token)
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        self.bossEvents = (self.bossEvents or 0) + 1
        SyncBossTokens()
        for token in pairs(BOSS_TOKENS) do self:MarkTokenChanged(token) end
    elseif event == "UNIT_TARGETABLE_CHANGED" then
        if IsReadable(unit) and BOSS_TOKENS[unit] then
            self.bossEvents = (self.bossEvents or 0) + 1
            SyncBossTokens()
            self:MarkTokenChanged(unit)
        end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" and IsReadable(unit) and type(unit) == "string" and IsGroupToken(unit) then
        -- Your (or a member's) threat situation changed on some mob the event does not name: each
        -- engaged record is read again at the next flush, however many events come first.
        for index = 1, self.enemyCount do
            local record = self.enemyOrder[index]
            if record.engaged then record.dirty = true end
        end
        self:Hurry()
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        self:MarkDirty(unit)
    elseif event == "UNIT_COMBAT" and IsReadable(action) and action == "WOUND" then
        -- Counted for /ps diagnose: damage the client reported for a tracked mob, or for none.
        if self:RecordUnitDamage(unit) then
            self.combatMatched = (self.combatMatched or 0) + 1
        else
            self.combatUnmatched = (self.combatUnmatched or 0) + 1
        end
    end
end

-- Plates need threat while a layout shows it or reads it (Lifecycle's PlateNeeds, cached per
-- settings revision, so this stays cheap on every tick). Without the plates it is assumed.
function ThreatService:HasActiveConsumer()
    local needs = type(PS.PlateNeeds) == "function" and PS.PlateNeeds() or nil
    if not needs or needs.threat ~= false then return true end
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
    if not self.targetRetryAt or now - self.targetRetryAt >= GROUP_SCAN_INTERVAL then
        self.targetRetryAt = now
        self:RetryMissingTargets()
        self:ReconcileTargets()
        -- An engaged mob whose threat event the client did not send (or sent for another token)
        -- is still re-read at least every STALE_REFRESH.
        for index = 1, self.enemyCount do
            local record = self.enemyOrder[index]
            if record.engaged and not record.dirty and (not record.refreshedAt or now - record.refreshedAt >= STALE_REFRESH) then
                record.dirty = true
            end
        end
    end
    self:FlushTargeters()
    if self.groupThreatPending then self:FlushGroupThreat(now) end
    self:RefreshBatch(REFRESH_BUDGET)
    if self.groupThreatWanted then self:ReadTargetScope(now) end
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
            -- Members targeting it by the borrowed token (ReadTokenTargeters).
            tokenTargeters = { count = 0, names = {}, units = {}, answers = {} },
            -- Both routes merged, member by member (MergeTargeters).
            targeters = { count = 0, names = {}, units = {} },
            damageStamps = {}, damageCounts = {},
            -- Protected "holding it" answers and what each means (FoldHolders).
            holdFlags = {}, holdFlagStates = {}, holdFlagCount = 0,
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
    self.mouseoverProbe = { events = 0 }
    -- Plate frames a member's target moved to or from since the last FlushTargeters.
    self.touchedPlates = {}
    self.attackerTargetOrder = {}
    self.attackerTargetPool = {}
    self.attackerTargetCount = 0
    for index = 1, MAX_ATTACKER_TARGETS do
        self.attackerTargetPool[index] = { names = {}, units = {}, count = 0 }
    end
    self.snapshot = {}
    self.groupThreat, self.groupThreatScratch = {}, {}
    -- The meter's enemy read through "target" alone (ReadTargetScope): never tracked, no plate.
    self.targetScope = { unit = "target", serial = 0, targetScoped = true, threatMobSource = "target" }
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

-- What the client lets the service read about a unit, in /ps diagnose's words.
local function Readability(callback, ...)
    if type(callback) ~= "function" then return "api-missing" end
    local ok, value = pcall(callback, ...)
    if not ok then return "error" end
    if not IsReadable(value) then return "protected" end
    if value == nil or value == false then return "none" end
    return "readable"
end

-- Whether a unit's threat on mob reads: its raw threat readable, protected, no entry, or worse.
local function ThreatReadability(unit, mob)
    if type(UnitDetailedThreatSituation) ~= "function" then return "api-missing" end
    local ok, tanking, status, scaled, rawPercent, raw = pcall(UnitDetailedThreatSituation, unit, mob)
    if not ok then return "error" end
    if IsNoEntry(tanking, status, scaled, rawPercent, raw) then return "no-entry" end
    if not IsReadable(raw) then return "protected" end
    return type(raw) == "number" and "readable" or "unavailable"
end

-- For /ps diagnose (threatTargeting): each group member's target as the client shows it (at most 8),
-- the targeting and damage state of each engaged mob (at most 8), and the event counters. Readable
-- facts and state words only; built on demand, never on the tick.
function ThreatService:TargetingReport()
    local Array = PS.Json and PS.Json.Array or function() return {} end
    local now = Now()
    local members = Array()
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if #members >= 8 then break end
        if member.isMember then
            local token = member.targetToken
            -- The plate the client gives for the member's target, the record it is, and whether threat
            -- reads through "<member>target" (the player's own tuple, and the rest of the group).
            local frame, plateState = ReadTargetPlate(token)
            -- Forever raises an error for a compound token ("party1target"): a known refusal, not a
            -- fault (the summary flags "error"), and the record is matched by GUID below.
            if plateState == "error" then plateState = "refused" end
            local plateRecord = "none"
            for enemyIndex = 1, frame and self.enemyCount or 0 do
                if self.enemyOrder[enemyIndex].root == frame then plateRecord = self.enemyOrder[enemyIndex].unit break end
            end
            if frame and plateRecord == "none" then plateRecord = "untracked" end
            -- Without a plate frame (Forever refuses "party1target"), the record matched by GUID.
            local guidMatch = false
            if not frame and member.targetGUID then
                local record = self.enemyByGUID[member.targetGUID]
                if record then plateRecord, guidMatch = record.unit, true end
            end
            local threatGroup = "not read"
            if frame or guidMatch then
                local highest, blocked = self:ScanGroupThreat(token)
                threatGroup = highest ~= nil and "readable"
                    or (blocked == "protected-group-threat" and "protected") or blocked or "unavailable"
            end
            members[#members + 1] = {
                unit = member.unit, exists = Readability(UnitExists, token), guid = Readability(UnitGUID, token),
                isTarget = Readability(UnitIsUnit, token, "target"),
                known = member.targetKnown == true and (member.targetGUID and "target" or "no target") or "unknown",
                plateFrame = plateState, plateRecord = plateRecord,
                threatPlayer = (frame or guidMatch) and ThreatReadability("player", token) or "not read",
                threatGroup = threatGroup, matchedBy = frame and "plate" or (guidMatch and "guid") or "none",
            }
        end
    end
    local mobs = Array()
    local second = math.floor(now)
    for index = 1, self.enemyCount do
        local record = self.enemyOrder[index]
        if #mobs >= 8 then break end
        if record.unit and record.engaged then
            local damage = 0
            for slot = 1, DAMAGE_SLOTS do
                local stamp = record.damageStamps[slot]
                if stamp and second - stamp < DAMAGE_SLOTS then damage = damage + record.damageCounts[slot] end
            end
            mobs[#mobs + 1] = {
                unit = record.unit, source = record.threatMobSource or "nameplate",
                targeting = record.targeterState or "unknown", targeters = record.targeters.count,
                attackers = record.attackerState or "unknown", attackerCount = record.activeAttackerCount or 0,
                damageEvents10s = damage,
                lastDamageAgo = record.unitDamageAt and string.format("%.1fs", now - record.unitDamageAt) or "none",
                gapKept = record.leadKept == true,
            }
        end
    end
    -- The boss tokens as a threat source: whether each exists, the plate the client names for it, the
    -- record that plate is, and whether that record's last read went through the token.
    local bosses = Array()
    for index = 1, 5 do
        local token = "boss" .. index
        local exists = Readability(UnitExists, token)
        if exists ~= "none" then
            local frame, plateState = ReadTargetPlate(token)
            local plateRecord, source = frame and "untracked" or "none", "none"
            for enemyIndex = 1, frame and self.enemyCount or 0 do
                local record = self.enemyOrder[enemyIndex]
                if record.root == frame then
                    plateRecord, source = record.unit, record.threatMobSource or "nameplate"
                    break
                end
            end
            bosses[#bosses + 1] = {
                unit = token, exists = exists, plateFrame = plateState, plateRecord = plateRecord,
                readThrough = source == token, source = source,
            }
        end
    end
    local scope = self.groupThreatRecord
    return {
        members = members, mobs = mobs, bosses = bosses, bossEvents = self.bossEvents or 0,
        combatEvents = { matched = self.combatMatched or 0, unmatched = self.combatUnmatched or 0 },
        reconciledTargets = self.targetReconciles,
        meterScope = (scope == nil and "none") or (scope == self.targetScope and "target") or "plate",
    }
end

local function EvidenceWord(value)
    if value == nil then return "nil" end
    return value and "true" or "false"
end

-- For /ps diagnose (role): the tank choice, the resolved role and its source, the assigned role
-- and how it read, the tank evidence and the signal behind it, what each signal read at the last
-- resolve and reads now, a druid's talents, the last role change, and whom the Tank window counts
-- as tanks. Readable facts and state words only; built on demand.
function ThreatService:RoleReport()
    if self.rosterDirty or self.roleDirty then self:FlushPending() end
    local Array = PS.Json and PS.Json.Array or function() return {} end
    local now = Now()
    local class = self:PlayerClass()
    local _, formID = FormFromID()
    local _, formIndex = FormFromIndex()
    local _, power = FormFromPower(class)
    local _, aura = FormFromAuras(class)
    local assignedRead = "api-missing"
    if type(UnitGroupRolesAssigned) == "function" then
        local ok, value = pcall(UnitGroupRolesAssigned, "player")
        if not ok then
            assignedRead = "error"
        elseif not IsReadable(value) then
            assignedRead = "protected"
        elseif type(value) == "string" then
            assignedRead = "readable " .. value
        else
            assignedRead = value == nil and "none" or "unavailable"
        end
    end
    local talents, bearTanks = "not used", "not used"
    if class == "DRUID" then
        local balance, feral, restoration, state = DruidTalents()
        talents = balance and string.format("%s/%s/%s (Balance/Feral/Restoration)", balance, feral, restoration) or state
        bearTanks = BearTanks()
    end
    local tanks, members = Array(), Array()
    local player
    for index = 1, self.rosterCount do
        local member = self.rosterPool[index]
        if member.isPlayer then player = member end
        if member.isMember then
            if member.role == "TANK" then tanks[#tanks + 1] = member.unit end
            if #members < 8 then
                members[#members + 1] = { unit = member.unit, assigned = member.assignedRole or "NONE", role = member.role or "NONE" }
            end
        end
    end
    local reads = self.roleReads
    local resolvedAt = self.roleResolvedAt
    return {
        tankMode = TankMode(), role = self.playerRole, source = self.playerRoleSource,
        assigned = player and player.assignedRole or "NONE", assignedRead = assignedRead, class = class or "protected",
        evidence = EvidenceWord(self.playerTankEvidence), signal = self.playerTankSignal or "none",
        -- What the last resolve read (nil: nothing answered, so the evidence above was kept).
        lastRead = self.tankEvidenceRead and EvidenceWord(self.lastTankEvidence) or "not read",
        lastResolve = {
            formID = reads.formID, formIndex = reads.formIndex, power = reads.power, aura = reads.aura,
            tankAura = reads.tankAura, resolves = self.roleResolves or 0,
            ago = resolvedAt and string.format("%.1fs", now - resolvedAt) or "never",
            inCombat = self.roleResolvedInCombat == true,
        },
        readsNow = { formID = formID, formIndex = formIndex, power = power, aura = aura, inCombat = Secret.InCombat() },
        formCast = self.formCast and string.format("%s %.1fs ago", self.formCast, now - self.formCastAt) or "none",
        formChangedSince = self.formLeft == true,
        talents = talents, bearTanks = bearTanks,
        lastChange = self.roleChangedAt and {
            from = self.roleChangedFrom, to = self.playerRole, ago = string.format("%.1fs", now - self.roleChangedAt),
            inCombat = self.roleChangedInCombat == true,
        } or "none",
        solo = self.isSolo == true, tanks = tanks, members = members,
    }
end

ThreatService._Test = {
    IsSecret = IsSecret,
    RefreshInterval = REFRESH_INTERVAL,
    IdleInterval = IDLE_INTERVAL,
    RefreshBudget = REFRESH_BUDGET,
    EngagementWindow = ENGAGEMENT_WINDOW,
    GroupScanInterval = GROUP_SCAN_INTERVAL,
    ReconcileBudget = RECONCILE_BUDGET,
    ExperimentalTokens = experimentalTokens,
    -- Forgets the curve (made again on the next solo curve read).
    ResetCurve = function() curveGap = nil end,
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
-- Only the player's auras and casts matter (tank evidence); the unit filter keeps a raid's churn out.
for _, event in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED" }) do
    local frame = ThreatService.frame
    local ok, accepted = false, false
    if type(frame.RegisterUnitEvent) == "function" then
        ok, accepted = pcall(frame.RegisterUnitEvent, frame, event, "player")
    end
    if not ok or accepted == false then PS._RegisterEvent(frame, event, "platesmith.threat-service") end
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
