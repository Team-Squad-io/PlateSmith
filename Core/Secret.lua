local _, PS = ...

-- Protected ("secret") values may be displayed through Blizzard's own sinks
-- but never compared, calculated with, or used as table keys. Every read of a
-- client value that might be protected goes through these helpers, and each
-- one fails closed: an error or an unreadable result is treated as "unknown".
local Secret = {}
PS.Secret = Secret

function Secret.IsSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

function Secret.IsReadable(value)
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        return ok and readable == true
    end
    return not Secret.IsSecret(value)
end

-- True for a present value, including a protected one that can still be displayed.
function Secret.HasValue(value)
    return Secret.IsSecret(value) or value ~= nil
end

-- A number usable in Lua arithmetic, or nil.
function Secret.Number(value)
    return Secret.IsReadable(value) and type(value) == "number" and value or nil
end

-- A non-empty readable string, or nil.
function Secret.String(value)
    return Secret.IsReadable(value) and type(value) == "string" and value ~= "" and value or nil
end

-- Calls an API that may be missing, error, or return a protected value.
-- Returns true/false for a readable result and nil when the answer is unknown.
function Secret.ReadBoolean(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if not ok or not Secret.IsReadable(value) then return nil end
    if value == nil then return false end
    return value and true or false
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

function Secret.InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end
