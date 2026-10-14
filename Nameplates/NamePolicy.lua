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
-- Hide unstyled names is kept, not set once: another addon or the game's own Names options can turn a
-- friendly name CVar back on at any time (live: Hyperframe's city preset turns players' names on as the
-- player starts resting, after PlateSmith's login and zone writes), and the game then writes its large
-- names over every friendly player without a nameplate. While it hides, the five are watched (CVAR_UPDATE,
-- and a WATCH_INTERVAL backstop for a client that names the CVar differently or sends nothing for an
-- addon's write): one turned on elsewhere takes that value as its original to put back and is hidden
-- again. At most once per WATCH_INTERVAL, so an addon that insists is not fought every frame.
local WATCH_ID, WATCH_INTERVAL = "names.watch", 2
local watch = { hiding = false, reasserts = 0, last = nil, wroteAt = nil }

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

-- Bits of a bitfield CVar, each read and written as a CVar of its own ("1" or "0"), so a bit is
-- captured and put back alone and its neighbours are never touched (Stacking registers
-- nameplateStackingTypes' Enemy and Friendly bits). name -> { cvar, index (the client's enum value) }.
local bits = {}

function NamePolicy.RegisterBit(name, cvar, index)
    if type(name) ~= "string" then return end
    bits[name] = (type(cvar) == "string" and type(index) == "number") and { cvar, index } or nil
end

-- Client settings set through a getter and setter rather than a CVar (ClickThrough's per-category nameplate
-- click switches and hit-test insets), read and written as if each were a CVar: captured, queued in combat and put
-- back by the same route. A switch reads "1" or "0"; with text, get returns the value's text and set takes it
-- (the insets, "left,right,top,bottom"), and default is the client's own (a lost original goes back to it).
-- name -> { get, set, text, default }; a client without the functions registers nothing.
local accessors = {}

function NamePolicy.RegisterAccessor(name, get, set, text, default)
    if type(name) ~= "string" then return end
    accessors[name] = (type(get) == "function" and type(set) == "function")
        and { get, set, text = text == true, default = default } or nil
end

local function ReadAccessor(field)
    local ok, value = pcall(field[1])
    if not ok or not Secret.IsReadable(value) or value == nil then return nil end
    if field.text then return type(value) == "string" and value or nil end
    return (value == true or value == 1 or value == "1") and "1" or "0"
end

local function ReadBit(field)
    local get = C_CVar and C_CVar.GetCVarBitfield
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, field[1], field[2])
    if not ok or value == nil then return nil end
    return (value == true or value == 1 or value == "1") and "1" or "0"
end

local function WriteBit(field, value)
    local set = C_CVar and C_CVar.SetCVarBitfield
    if type(set) ~= "function" then return false end
    return pcall(set, field[1], field[2], value == "1" or value == 1 or value == true)
end

-- The client's default for a CVar as text (GetCVarInfo's default, else GetCVarDefault), or nil
-- when the client reports none. A bit has none of its own (the client reports the whole field's); an accessor's is
-- the one it registered.
function NamePolicy.Default(name)
    if accessors[name] then return accessors[name].default end
    if bits[name] then return nil end
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

-- In a dungeon or raid, where Blizzard owns friendly plates (each plate type's design for the place
-- comes from PlateContext, which reads ReadInstance).
-- Every plate asks as it arrives, so the answer is read once per zone (NamePolicy.ZoneChanged on
-- PLAYER_ENTERING_WORLD and ZONE_CHANGED_NEW_AREA).
-- instanceKind: IsInInstance's type ("none" outside an instance), or "unknown" when the read failed
-- or was protected; then the player counts as in the world.
local groupInstance, instanceKind
local function ReadKind()
    local ok, inInstance, kind = false, nil, nil
    if type(IsInInstance) == "function" then ok, inInstance, kind = pcall(IsInInstance) end
    if not ok or not Secret.IsReadable(inInstance) or not Secret.IsReadable(kind) then return "unknown" end
    if not inInstance then return "none" end
    return type(kind) == "string" and kind or "unknown"
end
local function ReadInstance()
    instanceKind = ReadKind()
    groupInstance = instanceKind == "party" or instanceKind == "raid"
end

function NamePolicy.InGroupInstance()
    if groupInstance == nil then ReadInstance() end
    return groupInstance
end

-- The instance type read with InGroupInstance (same read, once per zone). fresh reads the client now and keeps
-- nothing: for a zone event's other listeners (AutoProfile), which may run before Lifecycle's ZoneChanged.
function NamePolicy.InstanceType(fresh)
    if fresh then return ReadKind() end
    if groupInstance == nil then ReadInstance() end
    return instanceKind
end

function NamePolicy.ZoneChanged()
    groupInstance, instanceKind = nil, nil
end
local InRestrictedInstance = NamePolicy.InGroupInstance

function NamePolicy.Read(name)
    if bits[name] then return ReadBit(bits[name]) end
    if accessors[name] then return ReadAccessor(accessors[name]) end
    local callback = C_CVar and C_CVar.GetCVar or GetCVar
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

-- What PlateSmith left in each CVar it captured (WriteCaptured), as the client reads it back:
-- state.cvarWritten[group][name], kept with the record. A CVar holding something else since was changed
-- outside PlateSmith (Blizzard's Options, another addon, or another character's own value where the client
-- keeps the CVar per character), and that value is the player's newest: Drifted reports it, Adopt makes
-- it the original to give back, and RestoreGroup leaves it standing instead of a stale original.
local function WrittenGroup(group, create)
    local state = State()
    if not state then return nil end
    if type(state.cvarWritten) ~= "table" then
        if not create then return nil end
        state.cvarWritten = {}
    end
    local names = state.cvarWritten[group]
    if type(names) ~= "table" then
        if not create then return nil end
        names = {}
        state.cvarWritten[group] = names
    end
    return names
end

local function SetWritten(group, name, value)
    local names = WrittenGroup(group, value ~= nil)
    if not names then return end
    names[name] = value
    if value ~= nil then return end
    local state = State()
    if next(names) == nil then state.cvarWritten[group] = nil end
    if next(state.cvarWritten) == nil then state.cvarWritten = nil end
end

-- Two CVar texts mean the same value ("1.5" and "1.500000").
local function SameText(left, right)
    local a, b = tonumber(left), tonumber(right)
    if a and b then return math.abs(a - b) < 0.0001 end
    return left == right
end
-- Whether two CVar readings are the same value (numbers compared as numbers).
NamePolicy.SameText = SameText

-- After a write lands: each group that left name records what the client now holds (it may round or clamp).
local function NoteLanded(name)
    local state = State()
    if not state or type(state.cvarWritten) ~= "table" then return end
    for _, names in pairs(state.cvarWritten) do
        if type(names) == "table" and names[name] ~= nil then names[name] = NamePolicy.Read(name) or names[name] end
    end
end

-- Whether Dungeon friendly names only (restrictedFriendlyNamesOnly) reaches players alone: the
-- client has the players' CVar. Older clients have only nameplateShowOnlyNames, for every friendly.
function NamePolicy.NamesOnlyIsPlayersOnly()
    return NamePolicy.Read(restrictedFriendlyNameCVars[1]) ~= nil
end

-- A CVar write blocked in combat raises ADDON_ACTION_BLOCKED instead of an
-- error, so it cannot be detected afterwards. Defer it until combat ends.
function NamePolicy.Write(name, value, immediate)
    local field, accessor = bits[name], accessors[name]
    local callback = C_CVar and C_CVar.SetCVar or SetCVar
    if not field and not accessor and type(callback) ~= "function" then return false end
    if not immediate and Secret.InCombat() then
        if pendingValues[name] == nil then pendingNames[#pendingNames + 1] = name end
        pendingValues[name] = value
        return true
    end
    local ok
    if field then
        ok = WriteBit(field, value)
    elseif accessor and accessor.text then
        ok = pcall(accessor[2], tostring(value))
    elseif accessor then
        ok = pcall(accessor[2], value == "1" or value == 1 or value == true)
    else
        ok = pcall(callback, name, value)
    end
    if ok then NoteLanded(name) end
    return ok
end

-- The value queued for name until combat ends, or nil.
function NamePolicy.Pending(name)
    return pendingValues[name]
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
    SetWritten(group, name, tostring(value))
    return NamePolicy.Write(name, value, immediate)
end

-- The value name holds when it was changed outside PlateSmith since PlateSmith last wrote it under group
-- (nil: PlateSmith's value stands, a write of its own still waits for combat to end, or it never wrote it).
function NamePolicy.Drifted(group, name)
    local names = WrittenGroup(group, false)
    local wrote = names and names[name]
    if wrote == nil or pendingValues[name] ~= nil then return nil end
    local live = NamePolicy.Read(name)
    if live == nil or SameText(live, wrote) then return nil end
    return live
end

-- A CVar of group changed outside PlateSmith (Drifted): that value becomes its original, the one to give
-- back, and it is no longer counted lost. Returns the value (nil when nothing changed outside) and whether
-- it differs from the original recorded before (false: the CVar went back to the player's own value).
function NamePolicy.Adopt(group, name)
    local live = NamePolicy.Drifted(group, name)
    if live == nil then return nil, false end
    local record = GroupRecord(group)
    local before = record[name]
    record[name] = live
    Forget(group, name)
    return live, before == nil or not SameText(before, live)
end

-- PlateSmith's value already stands in name (nothing to write): with an original recorded, it is what an
-- outside change is told from (PlateSmith took the CVar over without writing, as after the login check).
function NamePolicy.Held(group, name)
    local record = Captured(group)
    if type(record) ~= "table" or record[name] == nil or pendingValues[name] ~= nil then return end
    local live = NamePolicy.Read(name)
    if live ~= nil then SetWritten(group, name, live) end
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
-- defaults), and forgets that it was lost. What stands now is no longer kept: giving it back writes value.
function NamePolicy.SetOriginal(group, name, value)
    GroupRecord(group)[name] = value
    Forget(group, name)
    SetWritten(group, name, nil)
end

-- Drops name's record under group without writing anything: what holds now is someone else's later choice,
-- so the older original must not be put back over it.
function NamePolicy.ForgetCaptured(group, name)
    local record = Captured(group)
    if type(record) == "table" then
        record[name] = nil
        if next(record) == nil then ClearRestore(group) end
    end
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
-- original, else the client's default when the original was lost. One changed outside PlateSmith since
-- its last write (Drifted) holds the player's newest value: that stands, never the older original.
-- keep (a logout or /reload in combat, where the client may block the write unseen): written, but the
-- record stays (a lost original's default recorded too), so the next session puts it back.
function NamePolicy.RestoreGroup(group, name, immediate, keep)
    local record = Captured(group)
    record = type(record) == "table" and record or nil
    for key in pairs(NamePolicy.GroupNames(group)) do
        if name == nil or key == name then
            local value = NamePolicy.Drifted(group, key)
            if value == nil then
                value = record and record[key]
                if value == nil then value = Fallback(group, key) end
                -- Already back (a write queued in combat has landed: Release): not written again.
                local back = value ~= nil and pendingValues[key] == nil and SameText(NamePolicy.Read(key), value)
                if value ~= nil and not back then NamePolicy.Write(key, value, immediate) end
            end
            SetWritten(group, key, nil)
            if not keep then
                if record then record[key] = nil end
                Forget(group, key)
            elseif value ~= nil then
                GroupRecord(group)[key] = value
            end
        end
    end
    if not keep and record and next(record) == nil then ClearRestore(group) end
end

-- Gives back what an owner no longer sets while playing (a setting turned off, a profile switch, PlateSmith off):
-- RestoreGroup, except in combat (not immediate), where the write only queues. Then an original to put back is queued
-- and its record kept (a lost one's default recorded), so a setting turned back on before combat ends finds the true
-- original rather than recording PlateSmith's own value, still standing, as it. The owner applies again after
-- FlushPending on PLAYER_REGEN_ENABLED, which gives it back for good. One changed outside PlateSmith since its last
-- write is RestoreGroup's at once (nothing is written).
function NamePolicy.Release(group, name, immediate, keep)
    if immediate or not Secret.InCombat() then return NamePolicy.RestoreGroup(group, name, immediate, keep) end
    for key in pairs(NamePolicy.GroupNames(group)) do
        if name == nil or key == name then
            local record = Captured(group)
            local original = type(record) == "table" and record[key] or nil
            if original == nil then
                original = Fallback(group, key)
                if original ~= nil then GroupRecord(group)[key] = original end
            end
            if original == nil or NamePolicy.Drifted(group, key) ~= nil then
                NamePolicy.RestoreGroup(group, key, immediate, keep)
            else
                local now = pendingValues[key]
                if now == nil then now = NamePolicy.Read(key) end
                if now == nil or not SameText(now, original) then NamePolicy.Write(key, original) end
            end
        end
    end
end

local RESTRICTED_NAMES, CLASS_COLOUR, FRIENDLY_NAMES = "restrictedFriendlyNames", "restrictedFriendlyClassColour",
    "friendlyNames"

-- Blizzard's names-only switch for friendly players has one owner, here, and one decision per place
-- (NamesOnlyWanted). Its record is the group RESTRICTED_NAMES (the name it had while only the dungeon option set
-- it), written through WriteCaptured and put back through RestoreGroup.
-- - Outdoors, while PlateSmith draws friendly players (names only or full plates, over Blizzard's frame hidden by
--   alpha), it follows Clicking's Friendly players row (clickFriendlyPlayer; Nameplates/ClickThrough.lua): on,
--   Blizzard's UpdateShowOnlyName clears the plate's hit-test points (UpdateHitTestArea), so clicks pass through the
--   PlateSmith plate. Clickable (the default) keeps it off, Click through keeps it on. The plate itself keeps its size
--   (C_NamePlate.SetNamePlateSize is one size for every plate), so PlateSmith's overlay, centred on it, stays put.
--   Only the players' CVar: the older clients' nameplateShowOnlyNames covers friendly NPCs too, whose Blizzard
--   plates it would change.
-- - In dungeons and raids, where friendly plates are Blizzard's, Dungeon friendly names only turns it on.
-- - Anywhere else (Blizzard's plates, PlateSmith off, the option off) the player's own value stands.
-- A change someone else makes while PlateSmith sets it becomes the original to give back, and PlateSmith's value
-- is set again on its next apply (as Hide unstyled names and Clicking do: docs/STANDARDS.md section 14).

-- The CVar this client has: the players' one, else the older one for every friendly.
local function NamesOnlyCVar()
    for _, name in ipairs(restrictedFriendlyNameCVars) do
        if NamePolicy.Read(name) ~= nil then return name end
    end
    return nil
end

-- Before 1.3.0 the record was { name = cvar, value = original }; it becomes the group's { [cvar] = original }.
local function UpgradeNamesOnlyRecord()
    local record = Captured(RESTRICTED_NAMES)
    if type(record) ~= "table" or type(record.name) ~= "string" then return end
    local name, value = record.name, record.value
    record.name, record.value = nil, nil
    if value ~= nil and record[name] == nil then record[name] = value end
    if next(record) == nil then ClearRestore(RESTRICTED_NAMES) end
end

-- Whether PlateSmith draws friendly players' plates outdoors: on, drawing plates itself (Lifecycle's
-- OwnsAppearance) and Players' Show as not Blizzard's plates.
function NamePolicy.DrawsFriendlyPlayers(settings)
    settings = settings or Settings()
    if type(settings) ~= "table" or not settings.enabled then return false end
    local owns = PS.OwnsAppearance
    if type(owns) ~= "function" or not owns(settings) then return false end
    local schema = PS.ProfileSchema
    return schema ~= nil and schema.FRIENDLY.Mode(settings, "friendlyPlayer") ~= "off"
end

-- The value PlateSmith wants in name here ("0" or "1"), or nil when the player's own value stands.
local function NamesOnlyWanted(settings, restricted, name)
    if restricted then return settings.restrictedFriendlyNamesOnly and "1" or nil end
    if name == restrictedFriendlyNameCVars[1] and NamePolicy.DrawsFriendlyPlayers(settings) then
        return settings.clickFriendlyPlayer == "through" and "1" or "0"
    end
    return nil
end

-- The names-only mark, this character's (PlateSmithCharacterDB.namesOnlyMark = { cvar, wrote, original }): what
-- PlateSmith last set the switch to and the player's value it gives back. ApplyNamesOnly sets the switch outdoors for
-- every player, and a session that ends without a logout (a crash) saves neither its record nor anything else, while
-- the switch may keep PlateSmith's value. So the mark outlives a logout (the record does not), and at the next login a
-- switch with no record that holds the mark's value, where a logout would have left the original, gets the original
-- back (NamesOnlyReport's recovered). Giving the switch back while playing drops the mark: the player's value stands.
-- Only a session saved after a write leaves a mark; a crash in the first one cannot be told (TRACKING).
local mark = { checked = false, recovered = nil, cvar = nil, wrote = nil, original = nil }

local function CharacterRecord()
    local get = PS.GetCharacterSettings
    if type(get) ~= "function" then return nil end
    local ok, character = pcall(get)
    return ok and type(character) == "table" and character or nil
end

-- Once a session, before the first write.
local function CheckNamesOnlyMark(name)
    if mark.checked then return end
    local character = CharacterRecord()
    if not character then return end
    mark.checked = true
    local saved = character.namesOnlyMark
    if type(saved) ~= "table" or saved.cvar ~= name then return end
    mark.cvar, mark.wrote, mark.original = saved.cvar, saved.wrote, saved.original
    local record = Captured(RESTRICTED_NAMES)
    if type(record) == "table" and record[name] ~= nil then return end
    local live = NamePolicy.Read(name)
    if live == nil or not SameText(live, saved.wrote) or SameText(live, saved.original) then return end
    NamePolicy.SetOriginal(RESTRICTED_NAMES, name, saved.original)
    mark.recovered = saved.original
end

-- original nil: the mark is dropped. Only a change touches the saved table.
local function SetNamesOnlyMark(name, wrote, original)
    if original == nil then name, wrote = nil, nil end
    if mark.cvar == name and mark.wrote == wrote and mark.original == original then return end
    local character = CharacterRecord()
    if not character then return end
    mark.cvar, mark.wrote, mark.original = name, wrote, original
    character.namesOnlyMark = name and { cvar = name, wrote = wrote, original = original } or nil
end

-- Brings the names-only switch in line with the settings and the place. Cheap and safe at any time (every refresh
-- calls it): a value that already holds is not written, and a write in combat waits for it to end (Write).
function NamePolicy.ApplyNamesOnly(settings, restricted)
    settings = settings or Settings()
    if type(settings) ~= "table" or not State() then return end
    if restricted == nil then restricted = InRestrictedInstance() end
    UpgradeNamesOnlyRecord()
    local name = NamesOnlyCVar()
    if not name then return end
    CheckNamesOnlyMark(name)
    local want = NamesOnlyWanted(settings, restricted, name)
    if want == nil then
        if NamePolicy.GroupNames(RESTRICTED_NAMES)[name] then NamePolicy.Release(RESTRICTED_NAMES, name) end
        if not Secret.InCombat() then SetNamesOnlyMark(nil) end
        return
    end
    NamePolicy.Adopt(RESTRICTED_NAMES, name)
    local current = pendingValues[name] or NamePolicy.Read(name)
    if current ~= want then
        NamePolicy.WriteCaptured(RESTRICTED_NAMES, name, want)
    else
        NamePolicy.Held(RESTRICTED_NAMES, name)
    end
    local record = Captured(RESTRICTED_NAMES)
    SetNamesOnlyMark(name, want, type(record) == "table" and record[name] or nil)
end

-- For diagnostics (context.ownership.namesOnly): the CVar, its value, what PlateSmith wants of it here ("0", "1"
-- or "player": the player's own stands), whether PlateSmith holds an original for it, and the original given back
-- this session after one that ended without a logout (recovered; nil when none was).
function NamePolicy.NamesOnlyReport()
    local name = NamesOnlyCVar()
    if not name then return "none" end
    local settings = Settings()
    local want = type(settings) == "table" and NamesOnlyWanted(settings, InRestrictedInstance(), name) or nil
    return { cvar = name, value = NamePolicy.Read(name) or "unreadable", wanted = want or "player",
        owned = NamePolicy.GroupNames(RESTRICTED_NAMES)[name] == true, pending = pendingValues[name],
        recovered = mark.recovered }
end

-- keep: put back but still recorded (NamePolicy.RestoreAll).
local function ApplyClassColour(settings, restricted, keep)
    local restore = Captured(CLASS_COLOUR)
    if not restricted or not settings.restrictedFriendlyClassColour then
        if restore == nil then restore = Fallback(CLASS_COLOUR, CLASS_COLOUR_CVAR) end
        if restore ~= nil then NamePolicy.Write(CLASS_COLOUR_CVAR, restore) end
        if keep then return end
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
local function SetWatching(hiding)
    watch.hiding = hiding
    if PS.Ticker then PS.Ticker.SetEnabled(WATCH_ID, hiding) end
end

-- Outdoors: optionally hide Blizzard's unstyled friendly names. In dungeons
-- and raids, Blizzard owns friendly plates, so apply its names-only option.
function NamePolicy.Apply()
    local settings = Settings()
    if not settings then return end
    CheckLost(settings)
    local restricted = InRestrictedInstance()
    NamePolicy.ApplyNamesOnly(settings, restricted)
    if not settings.hideUnstyledFriendlyNames or restricted then
        SetWatching(false)
        RestoreFriendlyNames(false)
        ApplyClassColour(settings, restricted)
        return
    end
    ApplyClassColour(settings, false)
    local restores = RestoreTable()
    local restore = type(restores.friendlyNames) == "table" and restores.friendlyNames or {}
    restores.friendlyNames = restore
    for _, name in ipairs(friendlyNameCVars) do
        if restore[name] == nil then restore[name] = OriginalFor(FRIENDLY_NAMES, name) end
        Changed(FRIENDLY_NAMES, name)
        NamePolicy.Write(name, "0")
    end
    SetWatching(true)
end

-- The watch (names.watch): a friendly name CVar shown while Hide unstyled names hides them was turned on
-- by someone else. Their value is what to put back when PlateSmith stops hiding (the option off, a
-- dungeon, logout), and it is hidden again (queued in combat; a write already queued is not counted again).
function NamePolicy.Watch()
    if not watch.hiding then return end
    for _, name in ipairs(friendlyNameCVars) do
        local value = NamePolicy.Read(name)
        if value ~= nil and value ~= "0" and pendingValues[name] ~= "0" then
            local restores = RestoreTable()
            local restore = type(restores.friendlyNames) == "table" and restores.friendlyNames or {}
            restores.friendlyNames = restore
            restore[name] = value
            Forget(FRIENDLY_NAMES, name)
            Changed(FRIENDLY_NAMES, name)
            NamePolicy.Write(name, "0")
            watch.reasserts, watch.last = watch.reasserts + 1, name
            watch.wroteAt = type(GetTime) == "function" and GetTime() or nil
        end
    end
end

-- A CVar changed: the watch runs on the next frame, unless it hid one within WATCH_INTERVAL (its own
-- writes, or an addon writing back at once, wait for the backstop).
function NamePolicy.CVarChanged()
    if not watch.hiding or not PS.Ticker then return end
    local now = type(GetTime) == "function" and GetTime() or nil
    if now and watch.wroteAt and now - watch.wroteAt < WATCH_INTERVAL then return end
    PS.Ticker.Due(WATCH_ID)
end

-- For diagnostics (context.ownership.worldNames.watch): whether the friendly names are kept hidden, how
-- often one was turned on elsewhere and hidden again this session, and the last one.
function NamePolicy.WatchReport()
    return { hiding = watch.hiding, reasserts = watch.reasserts, last = watch.last or "none" }
end

-- Puts every captured CVar back and forgets the captures (logout, reset). keep (a logout or /reload
-- in combat, where a write may be blocked unseen): put back but still recorded, so the next login's
-- Apply puts them back again.
function NamePolicy.RestoreAll(keep)
    SetWatching(false)
    local settings = Settings()
    RestoreFriendlyNames(not keep)
    UpgradeNamesOnlyRecord()
    NamePolicy.RestoreGroup(RESTRICTED_NAMES, nil, nil, keep)
    ApplyClassColour(settings, false, keep)
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
    local namesOnly = {}
    for _, name in ipairs(restrictedFriendlyNameCVars) do
        namesOnly[name] = Reset(name)
        SetWritten(RESTRICTED_NAMES, name, nil)
    end
    local classColour = Reset(CLASS_COLOUR_CVAR)
    for _, key in ipairs({ FRIENDLY_NAMES, RESTRICTED_NAMES, CLASS_COLOUR }) do
        ClearRestore(key)
        Forget(key)
    end
    local restores = RestoreTable()
    if settings.hideUnstyledFriendlyNames and next(friendly) then restores.friendlyNames = friendly end
    local owned = NamesOnlyCVar()
    if owned and namesOnly[owned] ~= nil and (settings.restrictedFriendlyNamesOnly or NamePolicy.DrawsFriendlyPlayers(settings)) then
        restores.restrictedFriendlyNames = { [owned] = namesOnly[owned] }
    end
    if settings.restrictedFriendlyClassColour then restores.restrictedFriendlyClassColour = classColour end
    if next(restores) == nil then State().cvarRestore = nil end
    NamePolicy.Apply()
    return left
end

-- For the suites: a new session (nothing changed yet, the login check to run again).
function NamePolicy._Reset()
    changed, reported, checked = {}, {}, false
    mark.checked, mark.recovered, mark.cvar, mark.wrote, mark.original = false, nil, nil, nil, nil
    watch.reasserts, watch.last, watch.wroteAt = 0, nil, nil
end

if PS.Ticker then
    PS.Ticker.Register(WATCH_ID, WATCH_INTERVAL, NamePolicy.Watch)
    PS.Ticker.SetEnabled(WATCH_ID, false)
end
local eventFrame = CreateFrame("Frame")
PS._RegisterEvent(eventFrame, "CVAR_UPDATE", "platesmith.names")
eventFrame:SetScript("OnEvent", NamePolicy.CVarChanged)
