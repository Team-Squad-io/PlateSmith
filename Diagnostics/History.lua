local _, PS = ...

-- Opt-in diagnostic history in PlateSmithDiagnosticsDB, kept apart from
-- settings and Blueprints. Holds the last HISTORY_LIMIT reports: manual
-- /platesmith diagnose captures and rate-limited PlateSmith error snapshots.
local History = {}
PS.DiagnosticHistory = History

local HISTORY_LIMIT = 25
local ERROR_CAPTURE_INTERVAL = 5
local ERROR_REPEAT_INTERVAL = 60
History.LIMIT = HISTORY_LIMIT

local errorCapture = {}
-- Entries recorded since this login or reload (saved entries come back as new tables).
local sessionEntries = setmetatable({}, { __mode = "k" })
-- Set by the window so any change to history repaints it.
History.onChange = nil

local function Changed()
    if History.onChange then History.onChange() end
end

local function Store()
    local store = type(PlateSmithDiagnosticsDB) == "table" and PlateSmithDiagnosticsDB or {}
    if type(store.keepHistory) ~= "boolean" then store.keepHistory = false end
    if type(store.entries) ~= "table" then store.entries = {} end
    while #store.entries > HISTORY_LIMIT do table.remove(store.entries, 1) end
    PlateSmithDiagnosticsDB = store
    return store
end

function History.IsEnabled() return Store().keepHistory end

function History.SetEnabled(enabled)
    Store().keepHistory = enabled and true or false
    Changed()
end

function History.Entries() return Store().entries end

function History.Clear()
    Store().entries = {}
    Changed()
end

function History.Delete(entry)
    local entries = Store().entries
    for index, candidate in ipairs(entries) do
        if candidate == entry then
            table.remove(entries, index)
            Changed()
            return true
        end
    end
    return false
end

-- Returns the stored entry, or nil while history is off.
function History.Record(report, reason, errorText)
    local store = Store()
    if not store.keepHistory then return nil end
    local entry = { time = type(time) == "function" and time() or 0, reason = reason or "manual",
        error = errorText, report = report, build = tostring(PS.RUNTIME_BUILD or "unknown") }
    store.entries[#store.entries + 1] = entry
    sessionEntries[entry] = true
    while #store.entries > HISTORY_LIMIT do table.remove(store.entries, 1) end
    Changed()
    return entry
end

-- Whether entry was captured in this session (so on this build).
function History.InSession(entry) return sessionEntries[entry] == true end

-- The build an entry was captured on; entries saved before builds were stored use the report's.
function History.Build(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.build) == "string" then return entry.build end
    local version = type(entry.report) == "table" and entry.report.version
    return type(version) == "string" and version or nil
end

-- PlateSmith errors captured this session, oldest first.
function History.SessionErrors()
    local errors = {}
    for _, entry in ipairs(Store().entries) do
        if entry.reason == "error" and entry.error and sessionEntries[entry] then errors[#errors + 1] = entry end
    end
    return errors
end

local function IsPlateSmithError(message)
    return type(message) == "string"
        and (message:find("AddOns[\\/]PlateSmith") ~= nil or message:find("^PlateSmith ") ~= nil)
end

-- Wraps the active error handler (BugGrabber's, when installed) and always
-- forwards to it. Snapshots are rate-limited and never raise into the handler.
function History.InstallErrorCapture(buildReport)
    if History.errorCaptureInstalled or type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then
        return false
    end
    local ok, previous = pcall(geterrorhandler)
    if not ok or type(previous) ~= "function" then return false end
    local capturing = false
    local installed = pcall(seterrorhandler, function(message, ...)
        -- Ownership first: other addons' errors never touch the saved store.
        if not capturing and IsPlateSmithError(message) and History.IsEnabled() then
            local now = type(GetTime) == "function" and GetTime() or 0
            local repeated = errorCapture.lastMessage == message and errorCapture.lastMessageAt
                and now - errorCapture.lastMessageAt < ERROR_REPEAT_INTERVAL
            if not repeated and (not errorCapture.lastAt or now - errorCapture.lastAt >= ERROR_CAPTURE_INTERVAL) then
                capturing = true
                errorCapture.lastAt, errorCapture.lastMessage, errorCapture.lastMessageAt = now, message, now
                pcall(function() History.Record(buildReport(), "error", message) end)
                capturing = false
            end
        end
        return previous(message, ...)
    end)
    History.errorCaptureInstalled = installed
    return installed
end
