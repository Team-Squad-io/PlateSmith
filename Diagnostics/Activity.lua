local addonName, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Format = assert(PS.Format, "PlateSmith Format missing")
local L = PS.L

-- The activity log, PlateSmithDiagnosticsDB.activity: what changed, when, and who did it (PlateSmith's CVar
-- writes, outside changes to nameplate CVars, profile actions, account-state setters, logins and places). Always
-- on: at most LIMIT small entries of plain text and numbers, written only when something changes, never per frame.
local Activity = {}
PS.ActivityLog = Activity

local LIMIT, REPORT_LINES, SAVED_PATHS, PATH_LIMIT, TEXT_LIMIT, PATHS_LIMIT = 200, 30, 3, 20, 64, 160
-- A CVAR_UPDATE within this many seconds of PlateSmith's write of that CVar, with its value, is that write's.
local OWN_WINDOW = 2
Activity.LIMIT, Activity.REPORT_LINES, Activity.PATH_LIMIT, Activity.SAVED_PATHS = LIMIT, REPORT_LINES, PATH_LIMIT, SAVED_PATHS
-- The game's show switches, read at login and at each change of place: an outside change then shows its old value,
-- and one the client raised no CVAR_UPDATE for is still found (late).
local SEEDED = { "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends", "nameplateShowFriendlyPlayers",
    "nameplateShowFriendlyNPCs", "nameplateShowOnlyNames", "SoftTargetInteract" }

-- Set by the diagnostics window so a new entry repaints its Activity tab.
Activity.onChange = nil

-- known: the last value seen of each watched CVar (lower-case name). own: PlateSmith's writes whose CVAR_UPDATE is
-- still to come ({ value, at }; value nil: any, for a bit of a field).
local known, own = {}, {}
local session = { started = false, kind = nil }
-- lastOutside: the newest outside entry of each watched CVar and when ({ entry, at }), so the setter hook and
-- CVAR_UPDATE, which may come in either order, make one line. writers: this session's outside changes by each named
-- addon and CVar ("<addon> <cvar>" -> { by, cvar, count, old, new, t }), at most WRITER_LIMIT of them.
local lastOutside, writers, writerCount = {}, {}, 0
local WRITER_LIMIT, WRITERS_REPORTED = 20, 5
-- Who a write came from when no addon of its own is on the stack.
local BLIZZARD, UNKNOWN = "Blizzard UI", "unknown"

local function Entries()
    local db = type(PlateSmithDiagnosticsDB) == "table" and PlateSmithDiagnosticsDB or {}
    PlateSmithDiagnosticsDB = db
    if type(db.activity) ~= "table" then db.activity = {} end
    return db.activity
end

local function Now() return type(time) == "function" and time() or 0 end
local function Clock() return type(GetTime) == "function" and GetTime() or 0 end

-- Plain, readable, short text, or nil: never a secret value, a table, or a chat escape.
local function Text(value, limit)
    if value == nil or not Secret.IsReadable(value) then return nil end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return nil end
    local text = (tostring(value):gsub("[%c|]", "?"))
    limit = limit or TEXT_LIMIT
    if #text > limit then text = text:sub(1, limit) .. "..." end
    return text
end

-- The one CVar reader and comparison (NamePolicy's), so "1.5" and "1.500000" are one value.
local function Read(name)
    local policy = PS.NamePolicy
    return policy and policy.Read(name) or nil
end
local function Same(left, right)
    local policy = PS.NamePolicy
    if policy then return policy.SameText(left, right) end
    return left == right
end

-- The CVars whose outside changes are logged.
local function Watched(lower) return lower:find("^nameplate") ~= nil or lower:find("^softtarget") ~= nil end

local function Add(entry)
    entry.t = Now()
    local entries = Entries()
    entries[#entries + 1] = entry
    while #entries > LIMIT do table.remove(entries, 1) end
    if Activity.onChange then pcall(Activity.onChange) end
    return entry
end

function Activity.Entries() return Entries() end

function Activity.Clear()
    Entries()
    PlateSmithDiagnosticsDB.activity = {}
    if Activity.onChange then pcall(Activity.onChange) end
end

-- NamePolicy, just before a write that changes name (cvar: the console variable it lands in, nil for a client setting
-- with a getter and setter; value nil: any value, for a bit of a field). A change made outside since the last reading
-- is logged first, late (the client raised no CVAR_UPDATE for it), and this write's CVAR_UPDATE is marked as ours.
function Activity.Expect(cvar, value)
    if type(cvar) ~= "string" then return end
    local lower = cvar:lower()
    if not Watched(lower) then return end
    local live, last = Text(Read(cvar)), known[lower]
    if last ~= nil and live ~= nil and not Same(last, live) then
        Add({ kind = "outside", name = Text(cvar), old = last, new = live, late = true })
    end
    own[lower] = { value = value ~= nil and tostring(value) or nil, at = Clock() }
end

-- NamePolicy, after a write landed: name's value before and now, and the owner's record it wrote for (group).
function Activity.Wrote(name, cvar, old, new, group)
    if type(cvar) == "string" and Watched(cvar:lower()) then known[cvar:lower()] = Text(Read(cvar)) end
    if old ~= nil and new ~= nil and Same(old, new) then return end
    Add({ kind = "cvar", name = Text(name), old = Text(old), new = Text(new), group = Text(group) })
end

-- CVAR_UPDATE (NamePolicy's frame): a watched CVar now holding a value PlateSmith did not just write was changed by
-- the game or another addon. The name may be withheld; the value is read again rather than taken from the event.
function Activity.CVarUpdated(name)
    if not Secret.IsReadable(name) or type(name) ~= "string" then return end
    local lower = name:lower()
    if not Watched(lower) then return end
    local live = Text(Read(name))
    if live == nil then return end
    local mine = own[lower]
    own[lower] = nil
    if mine and Clock() - mine.at <= OWN_WINDOW and (mine.value == nil or Same(mine.value, live)) then
        known[lower] = live
        return
    end
    local last = known[lower]
    known[lower] = live
    if last ~= nil and Same(last, live) then return end
    lastOutside[lower] = { entry = Add({ kind = "outside", name = Text(name), old = last, new = live }), at = Clock() }
end

-- A named addon's outside change, counted for the report's problems.
local function Count(by, cvar, old, new)
    if by == BLIZZARD or by == UNKNOWN or by == addonName then return end
    local key = by .. " " .. cvar
    local record = writers[key]
    if not record then
        if writerCount >= WRITER_LIMIT then return end
        writerCount = writerCount + 1
        record = { by = by, cvar = cvar, count = 0 }
        writers[key] = record
    end
    record.count, record.old, record.new, record.t = record.count + 1, old, new, Now()
end

-- Who called the setter: the nearest addon folder on the stack other than Blizzard's own (Blizzard's SetCVar wraps
-- C_CVar's) and PlateSmith's (another addon's hook can run inside a PlateSmith call); PlateSmith when it is the only
-- one (its writes are NamePolicy's to log), else BLIZZARD when the stack shows the game's own code, else UNKNOWN.
local function Writer()
    if type(debugstack) ~= "function" then return UNKNOWN end
    local ok, stack = pcall(debugstack, 3, 12, 0)
    if not ok or type(stack) ~= "string" then return UNKNOWN end
    local blizzard, ours = stack:find("FrameXML", 1, true) ~= nil, false
    for name in stack:gmatch("AddOns[/\\]([^/\\]+)[/\\]") do
        if name:find("^Blizzard_") then
            blizzard = true
        elseif name == addonName then
            ours = true
        else
            return Text(name) or UNKNOWN
        end
    end
    if ours then return addonName end
    return blizzard and BLIZZARD or UNKNOWN
end

-- Posted after SetCVar and C_CVar.SetCVar (hooksecurefunc: they run unchanged, untainted). Only a watched CVar is
-- looked at; PlateSmith's own write (NamePolicy's mark) is NamePolicy's to log, and a write that changed nothing is
-- not logged. An outside line CVAR_UPDATE already made for this value is given its writer instead of a second line.
local function OnSet(name)
    if not Secret.IsReadable(name) or type(name) ~= "string" then return end
    local lower = name:lower()
    if not Watched(lower) then return end
    local mine = own[lower]
    if mine and Clock() - mine.at <= OWN_WINDOW then return end
    local live = Text(Read(name))
    if live == nil then return end
    local by = Writer()
    if by == addonName then
        known[lower] = live
        return
    end
    local recent = lastOutside[lower]
    if recent and recent.entry.by == nil and Clock() - recent.at <= 1 and Same(recent.entry.new, live) then
        recent.entry.by = by
        Count(by, recent.entry.name or name, recent.entry.old, live)
        if Activity.onChange then pcall(Activity.onChange) end
        return
    end
    local old = known[lower]
    if old ~= nil and Same(old, live) then return end
    known[lower] = live
    lastOutside[lower] = { entry = Add({ kind = "outside", name = Text(name), old = old, new = live, by = by }),
        at = Clock() }
    Count(by, Text(name) or name, old, live)
end
Activity._OnSet = OnSet

-- Hooks the setters once; false when the client lacks hooksecurefunc.
function Activity.InstallHooks()
    if Activity.hooked then return true end
    if type(hooksecurefunc) ~= "function" then return false end
    local hooked = false
    if type(SetCVar) == "function" then hooked = pcall(hooksecurefunc, "SetCVar", OnSet) or hooked end
    if type(C_CVar) == "table" and type(C_CVar.SetCVar) == "function" then
        hooked = pcall(hooksecurefunc, C_CVar, "SetCVar", OnSet) or hooked
    end
    Activity.hooked = hooked
    return hooked
end

-- This session's outside changes by named addons, most first (then by addon and CVar), at most WRITERS_REPORTED.
function Activity.Writers()
    local list = {}
    for _, record in pairs(writers) do list[#list + 1] = record end
    table.sort(list, function(left, right)
        if left.count ~= right.count then return left.count > right.count end
        if left.by ~= right.by then return left.by < right.by end
        return left.cvar < right.cvar
    end)
    local out, now = {}, Now()
    for index = 1, math.min(#list, WRITERS_REPORTED) do
        local record = list[index]
        out[index] = { by = record.by, cvar = record.cvar, count = record.count, old = record.old or "?",
            new = record.new or "?", at = Format.TimeOfDay(record.t, now) }
    end
    return out
end

local function Seed(late)
    for _, name in ipairs(SEEDED) do
        local lower, live = name:lower(), Text(Read(name))
        local last = known[lower]
        if live ~= nil then
            if late and last ~= nil and not Same(last, live) then
                Add({ kind = "outside", name = name, old = last, new = live, late = true })
            end
            known[lower] = live
        end
    end
end

local function ZoneText()
    if type(GetRealZoneText) ~= "function" then return nil end
    local ok, zone = pcall(GetRealZoneText)
    return ok and Text(zone) or nil
end

-- Lifecycle, after NamePolicy forgot the place: PLAYER_ENTERING_WORLD (login: its isInitialLogin) and
-- ZONE_CHANGED_NEW_AREA. The session's first is the login or reload; later ones are logged when the kind of
-- place changes (NamePolicy.InstanceType).
function Activity.Entered(login)
    local policy = PS.NamePolicy
    local kind = Text(policy and policy.InstanceType() or "unknown")
    if not session.started then
        session.started, session.kind = true, kind
        Seed(false)
        Add({ kind = "context", what = login == true and "login" or "reload", place = kind, zone = ZoneText() })
        return
    end
    Seed(true)
    if kind == session.kind then return end
    session.kind = kind
    Add({ kind = "context", what = "entered", place = kind, zone = ZoneText() })
end

-- Profiles' actions once they succeeded: save, revert, reset, copy, switch, create, preset, rename, delete; a and b
-- name the profiles (switch, copy and rename: from, to).
function Activity.Profile(action, a, b)
    Add({ kind = "profile", action = Text(action), profile = Text(a), other = Text(b) })
end

-- Profiles.Save, with Profiles.CountChanges(SAVED_PATHS, PATH_LIMIT) taken just before it: the first paths and how many
-- settings changed (past PATH_LIMIT, "more").
function Activity.Saved(profile, paths, count)
    paths = type(paths) == "table" and paths or {}
    count = type(count) == "number" and count or #paths
    local first = {}
    for index = 1, math.min(#paths, SAVED_PATHS) do first[index] = tostring(paths[index]) end
    Add({ kind = "profile", action = "save", profile = Text(profile), count = math.min(count, PATH_LIMIT),
        more = count > PATH_LIMIT or nil, paths = #first > 0 and Text(table.concat(first, ", "), PATHS_LIMIT) or nil })
end

-- Account state changed through its setter: hiddenAura, hiddenAuraRemoved, media, mediaRemoved, minimap.
function Activity.Account(what, detail)
    Add({ kind = "account", what = Text(what), detail = Text(detail) })
end

local PLACES = { none = L["the world"], party = L["a dungeon"], raid = L["a raid"], pvp = L["a battleground"],
    arena = L["an arena"], scenario = L["a scenario"] }
local PROFILE = {
    revert = L["Reverted profile %s to its saved settings"], reset = L["Reset profile %s to the defaults (not saved yet)"],
    copy = L["Copied profile %s into %s (not saved yet)"], switch = L["Switched from profile %s to %s"],
    create = L["Created profile %s"], preset = L["Created profile %s from a look"], rename = L["Renamed profile %s to %s"],
    delete = L["Deleted profile %s"],
}
local ACCOUNT = { hiddenAura = L["Hidden auras: added or changed %s"], hiddenAuraRemoved = L["Hidden auras: removed %s"],
    media = L["My media: set %s"], mediaRemoved = L["My media: removed %s"] }

local function Q(value) return value ~= nil and tostring(value) or "?" end

local function SavedText(entry)
    local count = type(entry.count) == "number" and entry.count or 0
    if count == 0 then return string.format(L["Saved profile %s: no settings changed"], Q(entry.profile)) end
    local settings = count == 1 and L["1 setting"]
        or string.format(entry.more and L["%d+ settings"] or L["%d settings"], count)
    return string.format(L["Saved profile %s: %s changed (%s)"], Q(entry.profile), settings, Q(entry.paths))
end

-- One entry as a line a person reads, without its time.
function Activity.Line(entry)
    if type(entry) ~= "table" then return "?" end
    local kind = entry.kind
    if kind == "cvar" then
        local name, old, new = Q(entry.name), Q(entry.old), Q(entry.new)
        if entry.group == nil then return string.format(L["%s: %s -> %s, by PlateSmith"], name, old, new) end
        return string.format(L["%s: %s -> %s, by PlateSmith (%s)"], name, old, new, Q(entry.group))
    elseif kind == "outside" and entry.by ~= nil then
        -- Who: an addon's folder name as it is; the two stored words in the player's language when shown.
        local by = entry.by == BLIZZARD and L["Blizzard UI"] or entry.by == UNKNOWN and L["unknown"] or Q(entry.by)
        if entry.old == nil then return string.format(L["%s = %s, by %s"], Q(entry.name), Q(entry.new), by) end
        return string.format(L["%s: %s -> %s, by %s"], Q(entry.name), Q(entry.old), Q(entry.new), by)
    elseif kind == "outside" then
        return string.format(entry.late and L["%s: %s -> %s, by the game or another addon (found later)"]
            or L["%s: %s -> %s, by the game or another addon"], Q(entry.name), Q(entry.old), Q(entry.new))
    elseif kind == "profile" then
        if entry.action == "save" then return SavedText(entry) end
        return string.format(PROFILE[entry.action] or "%s %s", Q(entry.profile), Q(entry.other))
    elseif kind == "account" then
        if entry.what == "minimap" then
            return entry.detail == "shown" and L["Minimap button shown"] or L["Minimap button hidden"]
        end
        return string.format(ACCOUNT[entry.what] or (Q(entry.what) .. " %s"), Q(entry.detail))
    elseif kind == "context" then
        local place = PLACES[entry.place] or Q(entry.place)
        local format = entry.what == "login" and L["Logged in, in %s (%s)"]
            or entry.what == "reload" and L["Reloaded the UI, in %s (%s)"] or L["Entered %s (%s)"]
        return string.format(format, place, Q(entry.zone))
    end
    return Q(kind)
end

-- The newest limit entries (all by default), newest first, each with its time.
function Activity.Lines(limit)
    local entries, lines, now = Entries(), {}, Now()
    limit = limit or LIMIT
    for index = #entries, math.max(1, #entries - limit + 1), -1 do
        local entry = entries[index]
        if type(entry) == "table" then
            lines[#lines + 1] = Format.TimeOfDay(entry.t, now) .. "  " .. Activity.Line(entry)
        end
    end
    return lines
end

-- For the diagnostic report: how many entries there are and the newest REPORT_LINES as lines.
function Activity.Report()
    return { count = #Entries(), lines = PS.Json.Array(Activity.Lines(REPORT_LINES)),
        outside = PS.Json.Array(Activity.Writers()) }
end

-- For the suites: a new session (no value seen, no write of ours awaited, the next entry the login).
function Activity._Reset()
    known, own, lastOutside, writers, writerCount = {}, {}, {}, {}, 0
    session.started, session.kind = false, nil
end

Activity.InstallHooks()
