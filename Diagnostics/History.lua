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
        error = errorText, report = report }
    store.entries[#store.entries + 1] = entry
    while #store.entries > HISTORY_LIMIT do table.remove(store.entries, 1) end
    Changed()
    return entry
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
        if not capturing and History.IsEnabled() and IsPlateSmithError(message) then
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
