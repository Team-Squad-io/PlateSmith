local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")

-- Blizzard nameplate CVars PlateSmith changes, and how they are restored.
-- Each original value is captured once into the account state's cvarRestore before the
-- first change, so logout, reset, or turning an option off puts it back.
local NamePolicy = {}
PS.NamePolicy = NamePolicy

local friendlyNameCVars = {
    "UnitNameFriendlyPlayerName",
    "UnitNameFriendlyPetName",
    "UnitNameFriendlyGuardianName",
    "UnitNameFriendlyMinionName",
    "UnitNameFriendlyTotemName",
}
local restrictedFriendlyNameCVars = {
    "nameplateShowOnlyNameForFriendlyPlayerUnits",
    "nameplateShowOnlyNames",
}
local CLASS_COLOUR_CVAR = "nameplateShowFriendlyClassColor"
local pendingNames, pendingValues = {}, {}

local function Settings()
    return type(PS.GetSettings) == "function" and PS.GetSettings() or nil
end

-- Captures live in account state, not the profile, so switching or reverting
-- a profile never forgets what to restore.
local function State() return PS.Profiles.State() end

-- nil (never false) when nothing was captured, so a missing capture is never written back.
local function Captured(key)
    local state = State()
    if not state or type(state.cvarRestore) ~= "table" then return nil end
    return state.cvarRestore[key]
end

local function RestoreTable()
    local state = State()
    state.cvarRestore = type(state.cvarRestore) == "table" and state.cvarRestore or {}
    return state.cvarRestore
end

local function ClearRestore(key)
    local state = State()
    if not state or type(state.cvarRestore) ~= "table" then return end
    state.cvarRestore[key] = nil
    if next(state.cvarRestore) == nil then state.cvarRestore = nil end
end

-- In a dungeon or raid, where Blizzard owns friendly plates and enemies use the dungeon profile.
-- Every plate asks as it arrives, so the answer is read once per zone (NamePolicy.ZoneChanged on
-- PLAYER_ENTERING_WORLD and ZONE_CHANGED_NEW_AREA).
local groupInstance
function NamePolicy.InGroupInstance()
    if groupInstance == nil then
        local inInstance, instanceType = IsInInstance()
        groupInstance = inInstance and (instanceType == "party" or instanceType == "raid") or false
    end
    return groupInstance
end

function NamePolicy.ZoneChanged()
    groupInstance = nil
end
local InRestrictedInstance = NamePolicy.InGroupInstance

function NamePolicy.Read(name)
    local callback = C_CVar and C_CVar.GetCVar or GetCVar
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

-- A CVar write blocked in combat raises ADDON_ACTION_BLOCKED instead of an
-- error, so it cannot be detected afterwards. Defer it until combat ends.
function NamePolicy.Write(name, value, immediate)
    local callback = C_CVar and C_CVar.SetCVar or SetCVar
    if type(callback) ~= "function" then return false end
    if not immediate and Secret.InCombat() then
        if pendingValues[name] == nil then pendingNames[#pendingNames + 1] = name end
        pendingValues[name] = value
        return true
    end
    return pcall(callback, name, value)
end

function NamePolicy.FlushPending()
    for index = 1, #pendingNames do
        local name = pendingNames[index]
        NamePolicy.Write(name, pendingValues[name], true)
        pendingNames[index], pendingValues[name] = nil, nil
    end
end

-- A set of CVars another owner manages (Stacking), under one cvarRestore key: each CVar's
-- original is captured once, before its first write, and put back by RestoreGroup. A CVar the
-- client does not have is never written.
function NamePolicy.WriteCaptured(group, name, value, immediate)
    local current = NamePolicy.Read(name)
    if current == nil then return false end
    local restores = RestoreTable()
    local record = type(restores[group]) == "table" and restores[group] or {}
    restores[group] = record
    if record[name] == nil then record[name] = current end
    return NamePolicy.Write(name, value, immediate)
end

-- The originals captured under group (name -> value), or nil when there are none.
function NamePolicy.CapturedGroup(group)
    local record = Captured(group)
    if type(record) ~= "table" or next(record) == nil then return nil end
    return record
end

-- Puts back one captured CVar of group (name), or all of them (name nil), and forgets them.
function NamePolicy.RestoreGroup(group, name, immediate)
    local record = Captured(group)
    if type(record) ~= "table" then return end
    for key, value in pairs(record) do
        if name == nil or key == name then
            NamePolicy.Write(key, value, immediate)
            record[key] = nil
        end
    end
    if next(record) == nil then ClearRestore(group) end
end

local function RestoreRestrictedNames(clear)
    local restore = Captured("restrictedFriendlyNames")
    if type(restore) == "table" and restore.name and restore.value ~= nil then
        NamePolicy.Write(restore.name, restore.value)
    end
    if clear then ClearRestore("restrictedFriendlyNames") end
end

local function ApplyRestrictedNames(settings, restricted)
    if not restricted or not settings.restrictedFriendlyNamesOnly then
        RestoreRestrictedNames(false)
        return
    end
    local restores = RestoreTable()
    local restore = restores.restrictedFriendlyNames
    if type(restore) ~= "table" then
        -- Clients expose one of two names for the same setting.
        for _, name in ipairs(restrictedFriendlyNameCVars) do
            local value = NamePolicy.Read(name)
            if value ~= nil then
                restore = { name = name, value = value }
                restores.restrictedFriendlyNames = restore
                break
            end
        end
    end
    if restore and restore.name then NamePolicy.Write(restore.name, "1") end
end

local function ApplyClassColour(settings, restricted)
    local restore = Captured("restrictedFriendlyClassColour")
    if not restricted or not settings.restrictedFriendlyClassColour then
        if restore ~= nil then NamePolicy.Write(CLASS_COLOUR_CVAR, restore) end
        ClearRestore("restrictedFriendlyClassColour")
        return
    end
    local current = NamePolicy.Read(CLASS_COLOUR_CVAR)
    if current == nil then return end
    local restores = RestoreTable()
    if restores.restrictedFriendlyClassColour == nil then restores.restrictedFriendlyClassColour = current end
    NamePolicy.Write(CLASS_COLOUR_CVAR, "1")
end

local function RestoreFriendlyNames(clear)
    local restore = Captured("friendlyNames")
    if type(restore) == "table" then
        for _, name in ipairs(friendlyNameCVars) do
            if restore[name] ~= nil then NamePolicy.Write(name, restore[name]) end
        end
    end
    if clear then ClearRestore("friendlyNames") end
end

-- Outdoors: optionally hide Blizzard's unstyled friendly names. In dungeons
-- and raids, Blizzard owns friendly plates, so apply its names-only option.
function NamePolicy.Apply()
    local settings = Settings()
    if not settings then return end
    local restricted = InRestrictedInstance()
    if not settings.hideUnstyledFriendlyNames or restricted then
        RestoreFriendlyNames(false)
        ApplyRestrictedNames(settings, restricted)
        ApplyClassColour(settings, restricted)
        return
    end
    RestoreRestrictedNames(false)
    ApplyClassColour(settings, false)
    local restores = RestoreTable()
    local restore = type(restores.friendlyNames) == "table" and restores.friendlyNames or {}
    restores.friendlyNames = restore
    for _, name in ipairs(friendlyNameCVars) do
        if restore[name] == nil then restore[name] = NamePolicy.Read(name) end
        NamePolicy.Write(name, "0")
    end
end

-- Puts every captured CVar back and forgets the captures (logout, reset).
function NamePolicy.RestoreAll()
    local settings = Settings()
    RestoreFriendlyNames(true)
    RestoreRestrictedNames(true)
    ApplyClassColour(settings, false)
end
