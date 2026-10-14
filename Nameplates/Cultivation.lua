-- Cultivation, the Tauren racial on Forever (spell 20552): it grows a duplicate of a nearby herb that you can harvest
-- without Herbalism, once per herb, on a cooldown of about an hour. What Objects plates read from it: whether you know
-- it, whether it is ready (the spell's own cooldown), and the herbs you cultivated, by their GUID (a node that respawns
-- has a new GUID, so it is ready again). Readable answers only; anything else is unknown. The plate side (events and a
-- slow ticker entry while herb plates are up) is ObjectStatus' (Nameplates/ObjectStatus.lua).
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local L = PS.L
local IsReadable = Secret.IsReadable

local Cultivation = {}
PS.Cultivation = Cultivation
Cultivation.SPELL = 20552
Cultivation.TICKER, Cultivation.INTERVAL = "plates.cultivation", 30
-- A cooldown this short or shorter is the global cooldown, not Cultivation's own.
Cultivation.GCD = 1.5
-- The herbs you cultivated this session, newest last: at most this many GUIDs.
Cultivation.LIMIT = 32
-- The events the plate side listens to: SPELLS_CHANGED always, the rest only while you know the spell (and
-- SPELL_UPDATE_COOLDOWN, which comes with every global cooldown, only while a herb plate is up too).
Cultivation.KNOWN_EVENT = "SPELLS_CHANGED"
Cultivation.EVENTS = { "SPELL_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }
-- A herb needs this much Herbalism per level of yours: a herb of skill 150 needs level 30, one of 300 level 60.
Cultivation.SKILL_PER_LEVEL = 5
-- The units whose game object a cast is aimed at, in order: the interaction target, then the hovered object.
local AIMS = { "softinteract", "mouseover" }

-- Whether you know it: true, false, or nil (the client cannot say). Read once until Forget (SPELLS_CHANGED).
local known, read = nil, false
local function ReadKnown()
    for _, name in ipairs({ "IsPlayerSpell", "IsSpellKnown" }) do
        local ask = rawget(_G, name)
        if type(ask) == "function" then
            local ok, value = pcall(ask, Cultivation.SPELL)
            if ok and IsReadable(value) and type(value) == "boolean" then return value end
        end
    end
    return nil
end

function Cultivation.Known()
    if not read then known, read = ReadKnown(), true end
    return known
end

function Cultivation.Forget() known, read = nil, false end

local function Number(value)
    if IsReadable(value) and type(value) == "number" then return value end
    return nil
end

-- Seconds until it is ready (0: ready now), or nil while unknown (no API, a protected answer, or a cooldown that has
-- not started: isEnabled false).
function Cultivation.Remaining()
    local start, duration, enabled = Secret.SpellCooldown(Cultivation.SPELL)
    if not (start and duration) or enabled == false or enabled == 0 then return nil end
    if duration <= Cultivation.GCD then return 0 end
    local now = type(GetTime) == "function" and Number(GetTime()) or nil
    if not now then return nil end
    return math.max(0, start + duration - now)
end

-- What the plates show for its state, as one value that changes only when their text would: 0 ready, the minutes
-- left (rounded up), or -1 unknown or not known.
function Cultivation.Stamp()
    if Cultivation.Known() ~= true then return -1 end
    local remaining = Cultivation.Remaining()
    if remaining == nil then return -1 end
    return remaining <= 0 and 0 or math.ceil(remaining / 60)
end

-- The herbs you cultivated: GUID -> true, and their order (oldest first).
local marks, order = {}, {}
Cultivation._marks = marks

function Cultivation.Cultivated(guid)
    return guid ~= nil and marks[guid] == true
end

-- The game object a cast of yours is aimed at: its readable GUID, or nil.
local function AimedGUID()
    for _, unit in ipairs(AIMS) do
        if Secret.IsGameObject(unit) then
            local guid = Secret.ReadGUID(unit)
            if Secret.GUIDEntry(guid) == "GameObject" then return guid end
        end
    end
    return nil
end

-- Whether an event's unit and spell are your own cast of Cultivation (readable only).
function Cultivation.Mine(unit, spell)
    return IsReadable(unit) and unit == "player" and IsReadable(spell) and spell == Cultivation.SPELL
end

-- A cast of it started (UNIT_SPELLCAST_SENT): the herb it is aimed at, kept for its success.
local pending
function Cultivation.Aim() pending = AimedGUID() end

-- Cultivation is channelled on Forever: UNIT_SPELLCAST_SUCCEEDED comes as the channel starts, so the herb is marked
-- only when the channel runs to its end (CHANNEL_STOP at or after its end time); stopping it early marks nothing.
-- channel: { guid, ends } (ends: GetTime seconds) while your Cultivation channels, else nil.
local channel
local CHANNEL_SLACK = 0.25

-- The player's Cultivation channel end time (GetTime seconds), or nil when not channelling it or unreadable.
local function ChannelEnds()
    if type(UnitChannelInfo) ~= "function" then return nil end
    local ok, _, _, _, _, endMS, _, _, spellID = pcall(UnitChannelInfo, "player")
    if not ok or not (IsReadable(spellID) and spellID == Cultivation.SPELL) then return nil end
    endMS = Number(endMS)
    return endMS and endMS / 1000 or nil
end

-- It succeeded (UNIT_SPELLCAST_SUCCEEDED): a channel starts waiting for its end; a plain cast marks at once.
-- True when the herb was marked now.
function Cultivation.Succeeded()
    local ends = ChannelEnds()
    if ends then
        channel = { guid = pending or AimedGUID(), ends = ends }
        pending = nil
        return false
    end
    return Cultivation.Mark() ~= nil
end

-- The channel was pushed back (UNIT_SPELLCAST_CHANNEL_UPDATE): its new end.
function Cultivation.ChannelUpdated()
    if channel then channel.ends = ChannelEnds() or channel.ends end
end

-- The channel stopped (UNIT_SPELLCAST_CHANNEL_STOP): marked only if it ran to its end. True when marked.
function Cultivation.ChannelStopped(now)
    local current = channel
    channel = nil
    if not current then return false end
    now = now or (type(GetTime) == "function" and GetTime()) or 0
    if now + CHANNEL_SLACK < current.ends then return false end
    return Cultivation.Mark(current.guid) ~= nil
end

-- Marks that herb as cultivated. The GUID marked, or nil when none was readable.
function Cultivation.Mark(guid)
    guid = guid or pending or AimedGUID()
    pending = nil
    if type(guid) ~= "string" then return nil end
    if not marks[guid] then
        marks[guid] = true
        order[#order + 1] = guid
        while #order > Cultivation.LIMIT do marks[table.remove(order, 1)] = nil end
    end
    return guid
end

-- The level a herb of Herbalism skill needs (nil: skill unknown).
function Cultivation.LevelFor(skill)
    if type(skill) ~= "number" then return nil end
    return math.max(1, math.ceil(skill / Cultivation.SKILL_PER_LEVEL))
end

-- Your level: PLAYER_LEVEL_UP's (LevelUp) until the game's own catches up, or nil when unreadable.
local levelledTo
function Cultivation.LevelUp(level)
    if IsReadable(level) and type(level) == "number" then levelledTo = level end
end
function Cultivation.Level()
    local ok, level = pcall(UnitLevel, "player")
    if not (ok and IsReadable(level) and type(level) == "number" and level > 0) then level = nil end
    if levelledTo and (level == nil or levelledTo > level) then return levelledTo end
    return level
end

-- Whether you are too low for a herb of Herbalism skill: true, false, or nil (unknown).
local function TooLow(skill)
    local need, level = Cultivation.LevelFor(skill), Cultivation.Level()
    if not (need and level) then return nil end
    return level < need
end

-- object.cancultivate: herb (true, false, or nil when unknown) with guid (its readable GUID, or nil) and skill (its
-- Herbalism skill, or nil). true while you know Cultivation, it is ready, your level reaches the herb (LevelFor) and
-- you have not cultivated it; false when you don't know it, it is not a herb, your level is too low, you cultivated it
-- or the spell is cooling down; nil while any of that is unknown (an unknown skill does not stop it).
function Cultivation.Can(herb, guid, skill)
    local knows = Cultivation.Known()
    if knows == false or herb == false then return false end
    if knows == nil or herb == nil then return nil end
    if TooLow(skill) == true then return false end
    if Cultivation.Cultivated(guid) then return false end
    local remaining = Cultivation.Remaining()
    if remaining == nil then return nil end
    return remaining <= 0
end

-- The Status text's part for a herb (herb true, skill: its Herbalism skill or nil) you can cultivate: its text and
-- colour key (ObjectStatus.COLOURS: "can" ready, "cannot" your level is too low, "plain" otherwise), or nil (not a
-- herb, you don't know it, or unknown).
function Cultivation.Status(herb, guid, skill)
    if herb ~= true or Cultivation.Known() ~= true then return nil end
    if TooLow(skill) == true then
        return string.format(L["Cultivate at level %d"], Cultivation.LevelFor(skill)), "cannot"
    end
    if Cultivation.Cultivated(guid) then return L["Cultivated"], "plain" end
    local remaining = Cultivation.Remaining()
    if remaining == nil then return nil end
    if remaining <= 0 then return L["Cultivate ready"], "can" end
    return string.format(L["Cultivate in %dm"], math.ceil(remaining / 60)), "plain"
end

-- Studio's sample (Test values' Cultivation ready).
function Cultivation.Sample() return L["Cultivate ready"], "can" end

-- For /ps diagnose (ObjectStatus' report): whether you know it, its state, and how many herbs are marked (never
-- their GUIDs).
function Cultivation.Report()
    local knows = Cultivation.Known()
    local stamp = Cultivation.Stamp()
    return { known = knows == nil and "unavailable" or knows, marked = #order,
        state = knows ~= true and "none" or stamp < 0 and "unavailable" or stamp == 0 and "ready" or "cooldown" }
end
