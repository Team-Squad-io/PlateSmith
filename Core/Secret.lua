local _, PS = ...

-- Protected ("secret") values may be displayed through Blizzard's own sinks
-- but never compared, calculated with, or used as table keys. Every read of a
-- client value that might be protected goes through these helpers, and each
-- one fails closed: an error or an unreadable result is treated as "unknown".
local Secret = {}
PS.Secret = Secret

local rawIsSecret = type(issecretvalue) == "function" and issecretvalue or nil
local rawCanAccess = type(canaccessvalue) == "function" and canaccessvalue or nil

-- The hot helpers call the client's checks directly only when a load-time self-test shows they
-- answer every plain kind of value with a boolean and never raise; otherwise each call is wrapped.
local function Answers(check, expected)
    local samples = { n = 5, nil, {}, function() end, 1, "" }
    for index = 1, samples.n do
        local ok, result = pcall(check, samples[index])
        if not ok or result ~= expected then return false end
    end
    return true
end
local direct = (not rawIsSecret or Answers(rawIsSecret, false)) and (not rawCanAccess or Answers(rawCanAccess, true))

if not rawIsSecret then
    function Secret.IsSecret() return false end
elseif direct then
    function Secret.IsSecret(value) return rawIsSecret(value) == true end
else
    function Secret.IsSecret(value)
        local ok, secret = pcall(rawIsSecret, value)
        return ok and secret == true
    end
end

if rawCanAccess and direct then
    function Secret.IsReadable(value) return rawCanAccess(value) == true end
elseif rawCanAccess then
    function Secret.IsReadable(value)
        local ok, readable = pcall(rawCanAccess, value)
        return ok and readable == true
    end
else
    local IsSecret = Secret.IsSecret
    function Secret.IsReadable(value) return not IsSecret(value) end
end

local IsSecret, IsReadable = Secret.IsSecret, Secret.IsReadable
-- Whether the client's checks are called directly (for tests and diagnostics).
Secret._direct = direct and (rawIsSecret ~= nil or rawCanAccess ~= nil)

-- True for a present value, including a protected one that can still be displayed.
function Secret.HasValue(value)
    return IsSecret(value) or value ~= nil
end

-- A number usable in Lua arithmetic, or nil.
function Secret.Number(value)
    return IsReadable(value) and type(value) == "number" and value or nil
end

-- A non-empty readable string, or nil.
function Secret.String(value)
    return IsReadable(value) and type(value) == "string" and value ~= "" and value or nil
end

-- Calls an API that may be missing, error, or return a protected value.
-- Returns true/false for a readable result and nil when the answer is unknown.
function Secret.ReadBoolean(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if not ok or not IsReadable(value) then return nil end
    if value == nil then return false end
    return value and true or false
end

-- A readable number from a frame or region getter (object:method()), or nil when the getter is
-- missing, errors, or returns a protected or non-number value.
function Secret.ReadNumber(object, method)
    local getter = object[method]
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, object)
    if ok and IsReadable(value) and type(value) == "number" then return value end
end

-- "<unit>target" for a unit token, built once per token instead of on every read.
local targetTokens = {}
function Secret.TargetToken(unit)
    local token = targetTokens[unit]
    if not token then
        token = unit .. "target"
        targetTokens[unit] = token
    end
    return token
end

function Secret.SameUnit(left, right)
    return Secret.ReadBoolean(UnitIsUnit, left, right) == true
end

function Secret.UnitExists(unit)
    return Secret.ReadBoolean(UnitExists, unit) == true
end

-- Whether unit is a game object the client gave a nameplate (a book, a chest): only a readable true. Read before
-- UnitExists, which an object may fail; a missing API or a protected answer is not an object (the old behaviour).
-- The one reader for plates and the threat service.
function Secret.IsGameObject(unit)
    return Secret.ReadBoolean(UnitIsGameObject, unit) == true
end

-- Creature types: a locale-safe word for what UnitCreatureType says (unit.creature), the one reader for plates and the
-- threat service's critters. The client names the type in its own language, so the word comes from the client's
-- creature type ID: UnitCreatureType's second result where the client gives a readable one, else the name matched
-- against the client's own name for each ID (C_CreatureInfo.GetCreatureTypeInfo, read once the client has it), else
-- against the English names (an English client without that API). CREATURE_TYPES[id] is the word.
Secret.CREATURE_TYPES = { "beast", "dragonkin", "demon", "elemental", "giant", "undead", "humanoid", "critter", "mechanical",
    "notspecified", "totem", "noncombatpet", "gascloud", "wildpet", "aberration" }
local creatureIDs = { Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5, Undead = 6, Humanoid = 7, Critter = 8,
    Mechanical = 9, ["Not specified"] = 10, Totem = 11, ["Non-combat Pet"] = 12, ["Gas Cloud"] = 13, ["Wild Pet"] = 14,
    Aberration = 15 }
local creatureNamesRead = false
local function CreatureID(name)
    if not creatureNamesRead then
        local api = rawget(_G, "C_CreatureInfo")
        local getInfo = type(api) == "table" and api.GetCreatureTypeInfo
        if type(getInfo) == "function" then
            creatureNamesRead = true
            for id = 1, #Secret.CREATURE_TYPES do
                local ok, info = pcall(getInfo, id)
                local own = ok and IsReadable(info) and type(info) == "table" and Secret.String(info.name)
                if own then creatureIDs[own] = id end
            end
        end
    end
    return creatureIDs[name]
end

-- unit's creature type: its word (nil when unknown or not one of CREATURE_TYPES), the client's own readable name (nil
-- unless readable), and whether the client answered readably at all (a unit with no type, such as an object, is a
-- readable nil: answered with no word). A missing API, an error or a protected answer is not answered.
function Secret.CreatureType(unit)
    if type(UnitCreatureType) ~= "function" then return nil, nil, false end
    local ok, name, id = pcall(UnitCreatureType, unit)
    if not ok then return nil, nil, false end
    if IsReadable(id) and type(id) == "number" and Secret.CREATURE_TYPES[id] then
        return Secret.CREATURE_TYPES[id], Secret.String(name), true
    end
    if not IsReadable(name) then return nil, nil, false end
    if type(name) ~= "string" or name == "" then return nil, nil, true end
    local found = CreatureID(name)
    return found and Secret.CREATURE_TYPES[found] or nil, name, true
end

function Secret.ReadGUID(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    return ok and Secret.String(guid) or nil
end

-- A readable GUID's kind and entry ID (its sixth field: an NPC's or an object's ID from the game), as
-- "GameObject", 175734 or "Creature", 299; nil for anything else. Only ever given ReadGUID's readable string.
function Secret.GUIDEntry(guid)
    if type(guid) ~= "string" then return nil end
    local kind, entry = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
    entry = tonumber(entry)
    if not kind or not entry or entry <= 0 then return nil end
    return kind, entry
end

function Secret.ReadName(unit, fallback)
    if type(UnitName) ~= "function" then return fallback end
    local ok, name = pcall(UnitName, unit)
    return ok and Secret.String(name) or fallback
end

-- A display value chosen inside the client by a boolean that may be protected
-- (C_CurveUtil.EvaluateColorValueFromBoolean), so Lua never branches on it: true and the value
-- (possibly protected: for sinks such as SetAlpha or SetTextColor only), or false when the client
-- has no such sink or refuses the call.
function Secret.Pick(flag, whenTrue, whenFalse)
    local sink = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if type(sink) ~= "function" then return false end
    local ok, value = pcall(sink, flag, whenTrue, whenFalse)
    if ok then return true, value end
    return false
end

-- Pick for a colour, channel by channel: true and r, g, b when flag is true, else elseR, elseG,
-- elseB (any of them possibly protected; the result for a setter only), or false.
function Secret.PickColour(flag, r, g, b, elseR, elseG, elseB)
    local okR, pr = Secret.Pick(flag, r, elseR)
    local okG, pg = Secret.Pick(flag, g, elseG)
    local okB, pb = Secret.Pick(flag, b, elseB)
    if okR and okG and okB then return true, pr, pg, pb end
    return false
end

-- A unit's class file as the client gives it (possibly protected), and whether there is one.
function Secret.ClassFile(unit)
    if type(UnitClass) ~= "function" then return nil, false end
    local ok, _, classFile = pcall(UnitClass, unit)
    if not ok or not Secret.HasValue(classFile) then return nil, false end
    return classFile, true
end

-- Colours a region by a class file that may be protected: C_ClassColor.GetClassColor turns it into
-- a colour inside the client and its channels go straight to the region's setter (SetTextColor by
-- default, or SetVertexColor for a texture). False when the client has no such sink, the colour is
-- unavailable, or the call is refused.
function Secret.SetClassColour(region, classFile, setter)
    local set = region[setter or "SetTextColor"]
    if type(set) ~= "function" then return false end
    local ok, r, g, b = Secret.ClassColourChannels(classFile)
    if not ok then return false end
    return (pcall(set, region, r, g, b))
end

-- The client's own colour for a class file that may be protected (C_ClassColor.GetClassColor): true and its channels,
-- possibly protected (for a colour setter only), or false when the client has no such sink or refuses.
function Secret.ClassColourChannels(classFile)
    local classColour = rawget(_G, "C_ClassColor")
    local getColour = type(classColour) == "table" and classColour.GetClassColor
    if type(getColour) ~= "function" then return false end
    local ok, colour = pcall(getColour, classFile)
    if not ok or not IsReadable(colour) or type(colour) ~= "table" then return false end
    return true, colour.r, colour.g, colour.b
end

function Secret.SetClassTextColour(region, classFile) return Secret.SetClassColour(region, classFile) end

-- The class colour (r, g, b) for a readable class file, else nil.
function Secret.ClassColour(classFile)
    if not IsReadable(classFile) or type(classFile) ~= "string" then return nil end
    local classColour = rawget(_G, "C_ClassColor")
    if type(classColour) == "table" and type(classColour.GetClassColor) == "function" then
        local ok, colour = pcall(classColour.GetClassColor, classFile)
        if ok and IsReadable(colour) and type(colour) == "table" and IsReadable(colour.r) and type(colour.r) == "number" then
            return colour.r, colour.g, colour.b
        end
    end
    local colours = rawget(_G, "RAID_CLASS_COLORS")
    local colour = type(colours) == "table" and colours[classFile]
    if type(colour) == "table" and type(colour.r) == "number" then return colour.r, colour.g, colour.b end
    return nil
end

-- A readable value as it is (a cooldown's isEnabled: a boolean, or 1 and 0 on older clients), else nil.
local function Flag(value)
    if IsReadable(value) then return value end
    return nil
end

-- A spell's cooldown: its start, its duration and whether it runs, each readable or nil, then what the client
-- said: "readable", "protected" (an answer withheld) or "api-missing". The one reader for Cultivation and Rescue.
function Secret.SpellCooldown(spell)
    local api = rawget(_G, "C_Spell")
    if type(api) == "table" and type(api.GetSpellCooldown) == "function" then
        local ok, info = pcall(api.GetSpellCooldown, spell)
        if not (ok and IsReadable(info) and type(info) == "table") then return nil, nil, nil, "protected" end
        local start, duration = Secret.Number(info.startTime), Secret.Number(info.duration)
        return start, duration, Flag(info.isEnabled), (start and duration) and "readable" or "protected"
    end
    local legacy = rawget(_G, "GetSpellCooldown")
    if type(legacy) == "function" then
        local ok, start, duration, enabled = pcall(legacy, spell)
        if not ok then return nil, nil, nil, "protected" end
        start, duration = Secret.Number(start), Secret.Number(duration)
        return start, duration, Flag(enabled), (start and duration) and "readable" or "protected"
    end
    return nil, nil, nil, "api-missing"
end

function Secret.InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end
