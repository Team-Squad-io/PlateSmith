local addonName, PS = ...

-- PlateSmith's CPU cost: the client's addon profiler (always on, no
-- scriptProfile CVar needed) plus each shared-ticker entry's own timing.
local Performance = {}
PS.Performance = Performance

-- Report key and Enum.AddOnProfilerMetric field; all are milliseconds.
local METRICS = {
    { "recentAverageMs", "RecentAverageTime" }, { "sessionAverageMs", "SessionAverageTime" },
    { "encounterAverageMs", "EncounterAverageTime" }, { "peakMs", "PeakTime" },
}
local SLOW_TICKS = { { "ticksOver5Ms", "CountTimeOver5Ms" }, { "ticksOver50Ms", "CountTimeOver50Ms" } }

local function Round(value) return math.floor(value * 1000 + 0.5) / 1000 end

local function Profiler(addon)
    local api = C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric
    local enum = Enum and Enum.AddOnProfilerMetric
    if type(api) ~= "function" or type(enum) ~= "table" then return { state = "api-missing" } end
    local report = {}
    local function Add(key, field, round)
        if enum[field] == nil then return end
        local ok, value = pcall(api, addon, enum[field])
        if not ok then
            report[key] = "error"
        elseif PS.Secret.IsReadable(value) and type(value) == "number" then
            report[key] = round and Round(value) or value
        else
            report[key] = "unavailable"
        end
    end
    for _, metric in ipairs(METRICS) do Add(metric[1], metric[2], true) end
    for _, metric in ipairs(SLOW_TICKS) do Add(metric[1], metric[2], false) end
    return report
end

-- Costs by name, for ticker entries (Ticker.Run passes each timed run) and event handlers (the plate
-- runtime passes each handler it timed). Both are recorded only where the profiler clock already
-- measured them. A record keeps session totals and the recent window: SLICES slices of
-- SLICE_SECONDS, the oldest cleared as the window moves, so "recent" covers the last 20-30 s.
-- Bounded: at most MAX_NAMES names per table (the registered sets are smaller).
local SLICES, SLICE_SECONDS, MAX_NAMES, TOP_EVENTS = 3, 10, 64, 5
local slice = 1
local tickCosts, eventCosts = { records = {}, count = 0 }, { records = {}, count = 0 }

local function Record(store, name, ms)
    local record = store.records[name]
    if not record then
        if store.count >= MAX_NAMES or type(name) ~= "string" or type(ms) ~= "number" then return end
        record = { calls = 0, totalMs = 0, peakMs = 0, recent = {} }
        for index = 1, SLICES do record.recent[index] = { 0, 0, 0 } end
        store.records[name], store.count = record, store.count + 1
    end
    record.calls, record.totalMs = record.calls + 1, record.totalMs + ms
    if ms > record.peakMs then record.peakMs = ms end
    local part = record.recent[slice]
    part[1], part[2] = part[1] + 1, part[2] + ms
    if ms > part[3] then part[3] = ms end
end

function Performance.RecordTick(id, ms) Record(tickCosts, id, ms) end
function Performance.RecordEvent(event, ms) Record(eventCosts, event, ms) end

-- The recent window's calls, total and peak for a record.
local function Recent(record)
    local calls, total, peak = 0, 0, 0
    for index = 1, SLICES do
        local part = record.recent[index]
        calls, total = calls + part[1], total + part[2]
        if part[3] > peak then peak = part[3] end
    end
    return calls, total, peak
end

-- The window moves on: the oldest slice is cleared for the next SLICE_SECONDS.
PS.Ticker.Register("diagnostics.window", SLICE_SECONDS, function()
    slice = slice % SLICES + 1
    for _, store in ipairs({ tickCosts, eventCosts }) do
        for _, record in pairs(store.records) do
            local part = record.recent[slice]
            part[1], part[2], part[3] = 0, 0, 0
        end
    end
end)

-- The TOP_EVENTS events by total time (recent: in the recent window), most first.
local function TopEvents(recent)
    local list = {}
    for event, record in pairs(eventCosts.records) do
        local calls, total, peak = record.calls, record.totalMs, record.peakMs
        if recent then calls, total, peak = Recent(record) end
        if calls > 0 then list[#list + 1] = { event = event, calls = calls, total = total, peak = peak } end
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    local top = PS.Json and PS.Json.Array() or {}
    for index = 1, math.min(TOP_EVENTS, #list) do
        local entry = list[index]
        top[index] = { event = entry.event, calls = entry.calls, totalMs = Round(entry.total),
            averageMs = Round(entry.total / entry.calls), peakMs = Round(entry.peak) }
    end
    return top
end

-- Each ticker entry's session figures (Ticker.Report) with its recent window's beside them.
local function TickerReport()
    local report = PS.Ticker.Report()
    for id, entry in pairs(report) do
        local record = tickCosts.records[id]
        if record then
            local calls, total, peak = Recent(record)
            entry.recentCalls = calls
            if calls > 0 then entry.recentAverageMs, entry.recentPeakMs = Round(total / calls), Round(peak) end
        end
    end
    return report
end

function Performance.Report()
    return { profiler = Profiler(addonName), ticker = TickerReport(), events = TopEvents(false),
        recentEvents = TopEvents(true), recentWindowSeconds = SLICES * SLICE_SECONDS }
end
