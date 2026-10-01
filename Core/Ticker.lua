local _, PS = ...

-- All periodic work runs from this one OnUpdate, so every per-frame cost is
-- registered, measurable, and visible in diagnostics in one place. An entry
-- runs at most once per frame; after a hitch it does not replay missed ticks.
local Ticker = {}
PS.Ticker = Ticker

local ERROR_REPORT_INTERVAL = 30
local entries = {}
local byId = {}

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

-- interval 0 runs every frame. callback(elapsedSinceLastRun, now)
function Ticker.Register(id, interval, callback)
    assert(type(id) == "string" and not byId[id], "ticker id must be unique")
    assert(type(callback) == "function", "ticker callback required")
    local entry = { id = id, interval = tonumber(interval) or 0, callback = callback, enabled = true,
        waited = 0, calls = 0, totalMs = 0, peakMs = 0 }
    entries[#entries + 1] = entry
    byId[id] = entry
    return entry
end

function Ticker.SetEnabled(id, enabled)
    local entry = byId[id]
    if entry then
        entry.enabled = enabled and true or false
        entry.waited = 0
    end
end

-- Changes how often an entry runs. Time already waited counts toward the new interval, so a
-- shorter one takes effect on the next frame that reaches it.
function Ticker.SetInterval(id, interval)
    local entry = byId[id]
    if entry then entry.interval = tonumber(interval) or 0 end
end

function Ticker.IsEnabled(id)
    local entry = byId[id]
    return entry ~= nil and entry.enabled
end

local function Run(entry, elapsed, now)
    local started = Clock()
    local ok, failure = pcall(entry.callback, elapsed, now)
    local finished = Clock()
    if started and finished then
        local cost = finished - started
        entry.calls = entry.calls + 1
        entry.totalMs = entry.totalMs + cost
        if cost > entry.peakMs then entry.peakMs = cost end
        if PS.Performance then PS.Performance.RecordTick(entry.id, cost) end
    end
    if not ok and PS.Chat and (not entry.reportedAt or now - entry.reportedAt >= ERROR_REPORT_INTERVAL) then
        entry.reportedAt = now
        PS.Chat.ReportError("ticker " .. entry.id, failure)
    end
end

function Ticker.Step(elapsed)
    local now = type(GetTime) == "function" and GetTime() or 0
    for index = 1, #entries do
        local entry = entries[index]
        if entry.enabled then
            entry.waited = entry.waited + elapsed
            if entry.waited >= entry.interval then
                local waited = entry.waited
                entry.waited = entry.interval > 0 and math.min(entry.waited - entry.interval, entry.interval) or 0
                Run(entry, waited, now)
            end
        end
    end
end

-- Each entry's peak starts again from its next run (the diagnostics' Reset peaks).
function Ticker.ResetPeaks()
    for _, entry in ipairs(entries) do entry.peakMs = 0 end
end

-- Per-entry cost for diagnostics; milliseconds are nil when the client has no profiler clock.
-- into: a report to fill again (the live view's, refreshed every second), else a new one.
function Ticker.Report(into)
    local report = into or {}
    for _, entry in ipairs(entries) do
        local row = report[entry.id] or {}
        report[entry.id] = row
        row.interval, row.enabled, row.calls = entry.interval, entry.enabled, entry.calls
        row.averageMs = entry.calls > 0 and math.floor(entry.totalMs / entry.calls * 1000 + 0.5) / 1000 or nil
        row.peakMs = entry.calls > 0 and math.floor(entry.peakMs * 1000 + 0.5) / 1000 or nil
    end
    return report
end

Ticker.frame = CreateFrame("Frame")
Ticker.frame:SetScript("OnUpdate", function(_, elapsed) Ticker.Step(elapsed) end)
