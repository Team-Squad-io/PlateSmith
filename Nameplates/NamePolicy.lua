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

-- The client's default for a CVar as text (GetCVarInfo's default, else GetCVarDefault), or nil
-- when the client reports none.
function NamePolicy.Default(name)
    local info = C_CVar and C_CVar.GetCVarInfo
    if type(info) == "function" then
        local ok, _, default = pcall(info, name)
        if ok and default ~= nil then return tostring(default) end
    end
    local getDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if type(getDefault) == "function" then
        local ok, default = pcall(getDefault, name)
        if ok and default ~= nil then return tostring(default) end
    end
    return nil
end

-- A lost original: the record of what a CVar was before PlateSmith changed it is gone (the saved
-- file was deleted or reset while the change stood). Two ways to know: PlateSmith changed it this
-- session (changed), or at login the CVar held PlateSmith's value with no record (marked in
-- state.cvarOriginalsMissing[key][name] until it is restored). Such a CVar goes back to the client's
-- default instead of staying as PlateSmith left it.
local changed, reported = {}, {}

local function Missing(create)
    local state = State()
    if not state then return nil end
    if type(state.cvarOriginalsMissing) ~= "table" then
        if not create then return nil end
        state.cvarOriginalsMissing = {}
    end
    return state.cvarOriginalsMissing
end

local function Mark(key, name)
    local missing = Missing(true)
    if not missing then return end
    missing[key] = type(missing[key]) == "table" and missing[key] or {}
    missing[key][name] = true
end

local function Changed(key, name)
    changed[key] = changed[key] or {}
    changed[key][name] = true
end

local function Lost(key, name)
    local missing = Missing(false)
    return (changed[key] and changed[key][name]) or (missing and type(missing[key]) == "table" and missing[key][name])
        or false
end

-- Forgets that name (nil: every CVar) under key was changed or lost: it has been put back.
local function Forget(key, name)
    if changed[key] then
        if name == nil then changed[key] = nil else changed[key][name] = nil end
    end
    local missing = Missing(false)
    if not missing or type(missing[key]) ~= "table" then return end
    if name == nil then missing[key] = {} else missing[key][name] = nil end
    if next(missing[key]) == nil then missing[key] = nil end
    if next(missing) == nil then State().cvarOriginalsMissing = nil end
end

-- The value to put name back to when key's record has none: the client's default for a lost
-- original, else nil (PlateSmith never changed it). No default: it is left and reported once.
local function Fallback(key, name)
    if not Lost(key, name) then return nil end
    local default = NamePolicy.Default(name)
    if default == nil and not reported[name] then
        reported[name] = true
        if PS.Chat then
            PS.Chat.Print(string.format(PS.L["%s was left as it is: PlateSmith has no record of its earlier value and "
                .. "the game reports no default."], name))
        end
    end
    return default
end

-- What to record as name's original before PlateSmith changes it: its value now, or the client's
-- default when the value now may be PlateSmith's own (a lost original).
local function OriginalFor(key, name)
    if Lost(key, name) then return NamePolicy.Default(name) end
    return NamePolicy.Read(name)
end

-- The original of name under key was lost (found at login): it is marked, and the client's default
-- stands in for it. Returns that default, or nil when the client reports none.
local function MarkLost(key, name)
    Mark(key, name)
    return NamePolicy.Default(name)
end

-- Whether any original under key (nil: any key) is known to be lost.
function NamePolicy.OriginalsMissing(key)
    local missing = Missing(false)
    if not missing then return false end
    if key == nil then return next(missing) ~= nil end
    return type(missing[key]) == "table" and next(missing[key]) ~= nil
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

-- Whether Dungeon friendly names only (restrictedFriendlyNamesOnly) reaches players alone: the
-- client has the players' CVar. Older clients have only nameplateShowOnlyNames, for every friendly.
function NamePolicy.NamesOnlyIsPlayersOnly()
    return NamePolicy.Read(restrictedFriendlyNameCVars[1]) ~= nil
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
local function GroupRecord(group)
    local restores = RestoreTable()
    local record = type(restores[group]) == "table" and restores[group] or {}
    restores[group] = record
    return record
end

function NamePolicy.WriteCaptured(group, name, value, immediate)
    if NamePolicy.Read(name) == nil then return false end
    local record = GroupRecord(group)
    if record[name] == nil then
        -- Changed this session and the record is gone: the value now is PlateSmith's own.
        if changed[group] and changed[group][name] then Mark(group, name) end
        record[name] = OriginalFor(group, name)
    end
    Changed(group, name)
    return NamePolicy.Write(name, value, immediate)
end

-- The originals captured under group (name -> value), or nil when there are none.
function NamePolicy.CapturedGroup(group)
    local record = Captured(group)
    if type(record) ~= "table" or next(record) == nil then return nil end
    return record
end

-- Every CVar of group PlateSmith has to put back: captured, changed this session or lost (name -> true).
function NamePolicy.GroupNames(group)
    local names = {}
    local record = Captured(group)
    if type(record) == "table" then for name in pairs(record) do names[name] = true end end
    for name in pairs(changed[group] or {}) do names[name] = true end
    local missing = Missing(false)
    if missing and type(missing[group]) == "table" then
        for name in pairs(missing[group]) do names[name] = true end
    end
    return names
end

-- Records value as name's original under group, replacing any capture (a reset to the client's
-- defaults), and forgets that it was lost.
function NamePolicy.SetOriginal(group, name, value)
    GroupRecord(group)[name] = value
    Forget(group, name)
end

-- At login: name held PlateSmith's value under group with no record of its original, so the client's
-- default stands in for it. False when the client reports no default (restoring it then reports it).
function NamePolicy.MarkLost(group, name)
    local default = MarkLost(group, name)
    if default == nil then return false end
    GroupRecord(group)[name] = default
    return true
end

-- Puts back one CVar of group (name), or all of them (name nil), and forgets them: its captured
-- original, else the client's default when the original was lost.
function NamePolicy.RestoreGroup(group, name, immediate)
    local record = Captured(group)
    record = type(record) == "table" and record or nil
    for key in pairs(NamePolicy.GroupNames(group)) do
        if name == nil or key == name then
            local value = record and record[key]
            if value == nil then value = Fallback(group, key) end
            if value ~= nil then NamePolicy.Write(key, value, immediate) end
            if record then record[key] = nil end
            Forget(group, key)
        end
    end
    if record and next(record) == nil then ClearRestore(group) end
end

local RESTRICTED_NAMES, CLASS_COLOUR, FRIENDLY_NAMES = "restrictedFriendlyNames", "restrictedFriendlyClassColour",
    "friendlyNames"

local function RestoreRestrictedNames(clear)
    local restore = Captured(RESTRICTED_NAMES)
    if type(restore) == "table" and restore.name and restore.value ~= nil then
        NamePolicy.Write(restore.name, restore.value)
    else
        for _, name in ipairs(restrictedFriendlyNameCVars) do
            local value = Fallback(RESTRICTED_NAMES, name)
            if value ~= nil then NamePolicy.Write(name, value) end
        end
    end
    if clear then
        ClearRestore(RESTRICTED_NAMES)
        Forget(RESTRICTED_NAMES)
    end
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
            if NamePolicy.Read(name) ~= nil then
                restore = { name = name, value = OriginalFor(RESTRICTED_NAMES, name) }
                restores.restrictedFriendlyNames = restore
                break
            end
        end
    end
    if restore and restore.name then
        Changed(RESTRICTED_NAMES, restore.name)
        NamePolicy.Write(restore.name, "1")
    end
end

local function ApplyClassColour(settings, restricted)
    local restore = Captured(CLASS_COLOUR)
    if not restricted or not settings.restrictedFriendlyClassColour then
        if restore == nil then restore = Fallback(CLASS_COLOUR, CLASS_COLOUR_CVAR) end
        if restore ~= nil then NamePolicy.Write(CLASS_COLOUR_CVAR, restore) end
        ClearRestore(CLASS_COLOUR)
        Forget(CLASS_COLOUR)
        return
    end
    if NamePolicy.Read(CLASS_COLOUR_CVAR) == nil then return end
    local restores = RestoreTable()
    if restores.restrictedFriendlyClassColour == nil then
        restores.restrictedFriendlyClassColour = OriginalFor(CLASS_COLOUR, CLASS_COLOUR_CVAR)
    end
    Changed(CLASS_COLOUR, CLASS_COLOUR_CVAR)
    NamePolicy.Write(CLASS_COLOUR_CVAR, "1")
end

local function RestoreFriendlyNames(clear)
    local restore = Captured(FRIENDLY_NAMES)
    restore = type(restore) == "table" and restore or {}
    for _, name in ipairs(friendlyNameCVars) do
        local value = restore[name]
        if value == nil then value = Fallback(FRIENDLY_NAMES, name) end
        if value ~= nil then NamePolicy.Write(name, value) end
    end
    if clear then
        ClearRestore(FRIENDLY_NAMES)
        Forget(FRIENDLY_NAMES)
    end
end

-- Once a session, before the first change: with hiding unstyled names on, every friendly-name CVar
-- at PlateSmith's "0" and no original recorded means the record was lost (docs/STACKING.md, "Lost
-- originals"); one the player shows is theirs, so nothing is marked. The dungeon names-only and
-- class colour CVars are single switches a player sets too, so they are not guessed at; the restore
-- button (RestoreDefaults) covers them.
local checked = false
local function CheckLost(settings)
    if checked or not State() then return end
    checked = true
    if not settings.hideUnstyledFriendlyNames or Captured(FRIENDLY_NAMES) ~= nil then return end
    local hidden = {}
    for _, name in ipairs(friendlyNameCVars) do
        local value = NamePolicy.Read(name)
        if value ~= nil and value ~= "0" then return end
        if value ~= nil and NamePolicy.Default(name) ~= "0" then hidden[#hidden + 1] = name end
    end
    if #hidden == 0 then return end
    local record = {}
    for _, name in ipairs(hidden) do record[name] = MarkLost(FRIENDLY_NAMES, name) end
    RestoreTable().friendlyNames = record
end
-- Outdoors: optionally hide Blizzard's unstyled friendly names. In dungeons
-- and raids, Blizzard owns friendly plates, so apply its names-only option.
function NamePolicy.Apply()
    local settings = Settings()
    if not settings then return end
    CheckLost(settings)
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
        if restore[name] == nil then restore[name] = OriginalFor(FRIENDLY_NAMES, name) end
        Changed(FRIENDLY_NAMES, name)
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

-- Behaviour & display › Plates' "Restore Blizzard nameplate settings": every CVar NamePolicy changes
-- goes back to the client's default (queued in combat), and those defaults become the originals, so
-- an option still on applies over them and turning it off leaves the default. Returns the CVars the
-- client reports no default for, left as they are.
function NamePolicy.RestoreDefaults()
    local settings = Settings() or {}
    local left = {}
    local function Reset(name)
        if NamePolicy.Read(name) == nil then return nil end
        local default = NamePolicy.Default(name)
        if default == nil then
            left[#left + 1] = name
        else
            NamePolicy.Write(name, default)
        end
        return default
    end
    local friendly = {}
    for _, name in ipairs(friendlyNameCVars) do friendly[name] = Reset(name) end
    local restricted
    for _, name in ipairs(restrictedFriendlyNameCVars) do
        local default = Reset(name)
        if default ~= nil and not restricted then restricted = { name = name, value = default } end
    end
    local classColour = Reset(CLASS_COLOUR_CVAR)
    for _, key in ipairs({ FRIENDLY_NAMES, RESTRICTED_NAMES, CLASS_COLOUR }) do
        ClearRestore(key)
        Forget(key)
    end
    local restores = RestoreTable()
    if settings.hideUnstyledFriendlyNames and next(friendly) then restores.friendlyNames = friendly end
    if settings.restrictedFriendlyNamesOnly then restores.restrictedFriendlyNames = restricted end
    if settings.restrictedFriendlyClassColour then restores.restrictedFriendlyClassColour = classColour end
    if next(restores) == nil then State().cvarRestore = nil end
    NamePolicy.Apply()
    return left
end

-- For the suites: a new session (nothing changed yet, the login check to run again).
function NamePolicy._Reset()
    changed, reported, checked = {}, {}, false
end
