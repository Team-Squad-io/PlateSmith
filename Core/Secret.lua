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

function Secret.ReadGUID(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    return ok and Secret.String(guid) or nil
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
    local classColour = rawget(_G, "C_ClassColor")
    local getColour = type(classColour) == "table" and classColour.GetClassColor
    if type(getColour) ~= "function" then return false end
    local set = region[setter or "SetTextColor"]
    if type(set) ~= "function" then return false end
    local ok, colour = pcall(getColour, classFile)
    if not ok or not IsReadable(colour) or type(colour) ~= "table" then return false end
    return (pcall(set, region, colour.r, colour.g, colour.b))
end

function Secret.SetClassTextColour(region, classFile) return Secret.SetClassColour(region, classFile) end

function Secret.InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end
