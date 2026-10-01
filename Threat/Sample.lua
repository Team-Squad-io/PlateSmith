local _, PS = ...
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")

-- Sample data for the threat windows (screenshots out of combat): a fixed group and enemy list
-- in the threat service's own record shapes, read through the same render path. Session only;
-- the console switches it on and off (and off on entering combat).
local Sample = { enabled = false }
PS.ThreatSample = Sample

local TARGET = "Stonehide Basilisk"
local PET = "Grimclaw"
-- Your raw threat as the holder; everyone's percent is of the pull threshold (110% of it).
local HOLDER_RAW = 9394
local MEMBERS = {
    { name = "Kaelyra", classToken = "MAGE", role = "DAMAGER", percent = 88 },
    { name = "Dunmore", classToken = "ROGUE", role = "DAMAGER", percent = 72 },
    { name = "Sethrin", classToken = "HUNTER", role = "DAMAGER", percent = 64 },
    { name = "Aldwyn", classToken = "PRIEST", role = "HEALER", percent = 41 },
    { name = "Morvaine", classToken = "WARLOCK", role = "DAMAGER", percent = 18 },
}

-- Unit tokens here are sample keys, never real units: rows built from them cannot spotlight.
local function Enemy(unit, name, fields)
    fields.sample, fields.unit, fields.enemyName = true, unit, name
    fields.serial, fields.revision = 0, 0
    fields.activeAttackerNames = fields.activeAttackerNames or {}
    fields.activeAttackerCount = #fields.activeAttackerNames
    fields.targeterNames = fields.targeterNames or fields.activeAttackerNames
    return fields
end

local function PlayerFacts()
    local name = Secret.ReadName("player", L["You"])
    local classToken = "WARRIOR"
    if type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, "player")
        if ok and Secret.IsReadable(token) and type(token) == "string" and token ~= "" then classToken = token end
    end
    return name, classToken
end

-- Rebuilt each time sample data is switched on, so your own name and class are current.
function Sample.Build()
    local you, classToken = PlayerFacts()
    local pull = HOLDER_RAW * 1.1
    local members = { { unit = "sample-player", name = you, role = "TANK", classToken = classToken, isPlayer = true,
        isPet = false, tanking = true, percent = 100, raw = HOLDER_RAW, order = 1, sample = true } }
    local highestOther = 0
    for index, member in ipairs(MEMBERS) do
        local raw = math.floor(member.percent / 100 * pull + 0.5)
        if raw > highestOther then highestOther = raw end
        members[#members + 1] = { unit = "sample-party" .. index, name = member.name, role = member.role,
            classToken = member.classToken, isPlayer = false, isPet = false, tanking = false, percent = member.percent,
            raw = raw, gap = math.floor(raw - pull + 0.5), order = index + 1, sample = true }
    end
    local lead = math.floor(pull - highestOther + 0.5)
    members[1].gap = lead
    Sample.members = members
    Sample.memberRecord = { sample = true, unit = "sample-enemy1", enemyName = TARGET, serial = 0 }

    local caster, stabber, hunter = MEMBERS[1].name, MEMBERS[2].name, MEMBERS[3].name
    local enemies = {
        -- Pulled off you by a damage dealer: loose, and listed first.
        Enemy("sample-enemy4", "Gravelmaw Brute", { engaged = true, loose = true, holdState = "LOOSE",
            targetName = caster, tanking = false, percent = 91, lead = -310, leadKind = "pull",
            activeAttackerNames = { caster } }),
        Enemy("sample-enemy1", TARGET, { engaged = true, loose = false, holdState = "TANK", tankHolds = true,
            targetName = you, tanking = true, percent = 100, lead = lead, leadKind = "tank", threatMobSource = "target",
            activeAttackerNames = { you, caster, stabber } }),
        Enemy("sample-enemy2", "Cragjaw Hatchling", { engaged = true, loose = false, holdState = "TANK", tankHolds = true,
            targetName = you, tanking = true, percent = 100, lead = 2860, leadKind = "tank",
            activeAttackerNames = { you, hunter } }),
        -- Still on you by a thin margin: its threat shows in the warning colour.
        Enemy("sample-enemy3", "Duskscale Lurker", { engaged = true, loose = false, holdState = "TANK", tankHolds = true,
            targetName = you, percent = 100, lead = 45, leadKind = "tank", activeAttackerNames = { stabber } }),
        Enemy("sample-enemy5", "Siltfang Skulker", { engaged = true, loose = false, holdState = "YOU", selfHolds = true,
            targetName = PET, tanking = false, percent = 58, lead = -2140, leadKind = "pull",
            activeAttackerNames = { PET, hunter } }),
        Enemy("sample-enemy6", "Shalebound Sentry", { engaged = false, loose = false, holdState = "IDLE",
            targetName = L["No target"] }),
    }
    local byUnit, loose, engaged = {}, 0, 0
    for _, entry in ipairs(enemies) do
        byUnit[entry.unit] = entry
        if entry.loose then loose = loose + 1 end
        if entry.engaged then engaged = engaged + 1 end
    end
    Sample.enemies, Sample.enemyByUnit, Sample.loose, Sample.engaged = enemies, byUnit, loose, engaged
end

-- What the windows read instead of the threat service while sample data is on: the same calls,
-- returning the same shapes.
local Source = {}
Sample.Source = Source

function Source:GetGroupThreat()
    return Sample.memberRecord, #Sample.members, Sample.members
end

function Source:GetSnapshot()
    local count = #Sample.enemies
    return Sample.enemies, count, count, Sample.loose, Sample.engaged
end

local function Named(unit, key, index)
    local entry = Sample.enemyByUnit and Sample.enemyByUnit[unit]
    local names = entry and entry[key]
    if not names then return nil, nil end
    return names[index], nil
end

function Source:GetActiveAttackerCount(unit)
    local entry = Sample.enemyByUnit and Sample.enemyByUnit[unit]
    local count = entry and entry.activeAttackerCount or 0
    return count, count > 0 and "confirmed" or "none"
end

function Source:GetActiveAttacker(unit, index) return Named(unit, "activeAttackerNames", index) end

function Source:GetTargeterCount(unit)
    local entry = Sample.enemyByUnit and Sample.enemyByUnit[unit]
    local count = entry and #entry.targeterNames or 0
    return count, count > 0 and "confirmed" or "none"
end

function Source:GetTargeter(unit, index) return Named(unit, "targeterNames", index) end

Sample.Build()
