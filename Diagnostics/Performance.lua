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

local function Metric(api, addon, field, round)
    local ok, value = pcall(api, addon, field)
    if not ok then return "error" end
    if PS.Secret.IsReadable(value) and type(value) == "number" then return round and Round(value) or value end
    return "unavailable"
end

-- into: a table to fill again (the live view's), else a new one.
local function Profiler(addon, into)
    local report = into or {}
    local api = C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric
    local enum = Enum and Enum.AddOnProfilerMetric
    if type(api) ~= "function" or type(enum) ~= "table" then
        report.state = "api-missing"
        return report
    end
    for _, metric in ipairs(METRICS) do
        if enum[metric[2]] ~= nil then report[metric[1]] = Metric(api, addon, enum[metric[2]], true) end
    end
    for _, metric in ipairs(SLOW_TICKS) do
        if enum[metric[2]] ~= nil then report[metric[1]] = Metric(api, addon, enum[metric[2]], false) end
    end
    return report
end

-- Costs by name, for ticker entries (Ticker.Run passes each timed run), event handlers (the plate
-- runtime passes each handler it timed) and the phases of a plate add. All are recorded only where
-- the profiler clock already measured them. A record keeps session totals and the recent window:
-- SLICES slices of SLICE_SECONDS, the oldest cleared as the window moves, so "recent" covers the
-- last 20-30 s. Bounded: at most MAX_NAMES names per table (the registered sets are smaller).
local SLICES, SLICE_SECONDS, MAX_NAMES, TOP_EVENTS = 3, 10, 64, 5
local slice = 1
local tickCosts, eventCosts = { records = {}, count = 0 }, { records = {}, count = 0 }
local phaseCosts, auraCosts = { records = {}, count = 0 }, { records = {}, count = 0 }
local STORES = { tickCosts, eventCosts, phaseCosts, auraCosts }

-- NAME_PLATE_UNIT_ADDED is timed under one of these: a plate frame built for the first time, a
-- frame reused, or an add queued for a later frame (its work then counts in plates.frame).
Performance.PLATE_ADDED = { new = "NAME_PLATE_UNIT_ADDED (new)", reused = "NAME_PLATE_UNIT_ADDED (reused)",
    queued = "NAME_PLATE_UNIT_ADDED (queued)" }
local PLATE_ADDED_ORDER = { "new", "reused", "queued" }
-- The phases of a plate add, each timed without what the phases inside it took (Lifecycle.lua).
-- aurasLater: the add's aura pass, read after the add in the frame's aura round (auras is then only its queueing).
Performance.ADD_PHASES = { "build", "layout", "styles", "text", "quest", "bars", "auras", "aurasLater", "threat",
    "placement", "values", "rules", "flush", "other" }
-- The parts of one aura pass (Auras.lua's UpdateAuras, any route to it), each a pass's sum: the reads,
-- textures set, icons made, swipes and countdowns, hiding/laying out/showing rows, the client's aura
-- container; reflow is the stack layout a row shown or hidden asked for, in the aura round; earlier is
-- the plate's work other events marked before the pass (flushed with it, not caused by it).
Performance.AURA_PHASES = { "read", "textures", "build", "times", "place", "native", "reflow", "earlier" }
-- The live view's own ticker entry, reported on its own line so it is not read as plate cost.
Performance.LIVE_TICKER = "diagnostics.live"

-- PlateSmith's own timed work per frame: each ticker pass with the timed events since the one before
-- (performance.frames). The client profiler (performance.profiler) measures more: every PlateSmith
-- script and hook, timed or not, Studio and this report included, over its own window and session.
-- frames.recent: per slice { frames, ms, peak, over 5 ms, over 50 ms, untimed hook calls }.
-- untimed.hooks: calls of hooks on Blizzard's plate frames, which run outside any timed handler.
local SLOW_FRAME_MS, VERY_SLOW_FRAME_MS = 5, 50
local frames = { count = 0, totalMs = 0, peakMs = 0, over5 = 0, over50 = 0, eventMs = 0, hooksSeen = 0, recent = {} }
for index = 1, SLICES do frames.recent[index] = { 0, 0, 0, 0, 0, 0 } end
Performance.untimed = { hooks = 0 }
local untimed = Performance.untimed
-- Plate adds left for a later frame (Lifecycle's adds): how many queued, how many of those hid
-- Blizzard's plate while they waited, the most frames one waited (since login or a peak reset), how
-- many ran past the budget because they had waited too long (overdue), and the waits in frames by
-- bucket (ADD_WAIT_BUCKETS: at most 1, 3, 10, more), and the longest wait in ms (profiler time from
-- queueing to drawn). recent: the same per slice of the recent window, { queued, held, max wait,
-- overdue, then one count per bucket, then the longest wait in ms }.
local ADD_WAIT_BUCKETS = { 1, 3, 10 }
local ADD_WAIT_NAMES = { "upTo1", "upTo3", "upTo10", "over10" }
local ADD_WAIT_MS = 9
Performance.addQueue = { queued = 0, held = 0, maxWaitFrames = 0, maxWaitMs = 0, overdue = 0, waits = { 0, 0, 0, 0 },
    recent = {} }
for index = 1, SLICES do Performance.addQueue.recent[index] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 } end
local ADD_RECENT_FIELD = { queued = 1, held = 2, overdue = 4 }

-- kind: "queued", "held", "overdue", or "waited" with waited (frames, a whole number) and ms (nil
-- without a profiler clock).
function Performance.RecordAddQueue(kind, waited, ms)
    local queue = Performance.addQueue
    local part = queue.recent[slice]
    if kind == "waited" then
        if type(waited) ~= "number" then return end
        if waited > queue.maxWaitFrames then queue.maxWaitFrames = waited end
        if waited > part[3] then part[3] = waited end
        if type(ms) == "number" then
            if ms > queue.maxWaitMs then queue.maxWaitMs = ms end
            if ms > part[ADD_WAIT_MS] then part[ADD_WAIT_MS] = ms end
        end
        local bucket = #ADD_WAIT_NAMES
        for index, limit in ipairs(ADD_WAIT_BUCKETS) do
            if waited <= limit then
                bucket = index
                break
            end
        end
        queue.waits[bucket], part[4 + bucket] = queue.waits[bucket] + 1, part[4 + bucket] + 1
        return
    end
    local field = ADD_RECENT_FIELD[kind]
    if not field then return end
    queue[kind], part[field] = queue[kind] + 1, part[field] + 1
end

local function Waits(counts)
    local report = {}
    for index, name in ipairs(ADD_WAIT_NAMES) do report[name] = counts[index] end
    return report
end

-- The addQueue section: session figures, then the recent window's.
local function AddQueueFigures()
    local queue = Performance.addQueue
    local report = { queued = queue.queued, held = queue.held, maxWaitFrames = queue.maxWaitFrames,
        maxWaitMs = Round(queue.maxWaitMs), overdue = queue.overdue, waits = Waits(queue.waits) }
    local totals, maxWait, maxWaitMs = { 0, 0, 0, 0 }, 0, 0
    local queued, held, overdue = 0, 0, 0
    for index = 1, SLICES do
        local part = queue.recent[index]
        queued, held, overdue = queued + part[1], held + part[2], overdue + part[4]
        if part[3] > maxWait then maxWait = part[3] end
        if part[ADD_WAIT_MS] > maxWaitMs then maxWaitMs = part[ADD_WAIT_MS] end
        for bucket = 1, #totals do totals[bucket] = totals[bucket] + part[4 + bucket] end
    end
    report.recentQueued, report.recentHeld, report.recentOverdue = queued, held, overdue
    report.recentMaxWaitFrames, report.recentMaxWaitMs, report.recentWaits = maxWait, Round(maxWaitMs), Waits(totals)
    return report
end

-- record.version moves with every change to a record (a run, the window moving on, a peak reset),
-- so the live view refigures only records that changed since its last refresh.
local function Record(store, name, ms)
    local record = store.records[name]
    if not record then
        if store.count >= MAX_NAMES or type(name) ~= "string" or type(ms) ~= "number" then return end
        record = { calls = 0, totalMs = 0, peakMs = 0, recent = {}, version = 0 }
        for index = 1, SLICES do record.recent[index] = { 0, 0, 0 } end
        store.records[name], store.count = record, store.count + 1
    end
    record.calls, record.totalMs, record.version = record.calls + 1, record.totalMs + ms, record.version + 1
    if ms > record.peakMs then record.peakMs = ms end
    local part = record.recent[slice]
    part[1], part[2] = part[1] + 1, part[2] + ms
    if ms > part[3] then part[3] = ms end
end

function Performance.RecordTick(id, ms) Record(tickCosts, id, ms) end
function Performance.RecordEvent(event, ms)
    Record(eventCosts, event, ms)
    if type(ms) == "number" then frames.eventMs = frames.eventMs + ms end
end
function Performance.RecordPhase(phase, ms) Record(phaseCosts, phase, ms) end
function Performance.RecordAuraPhase(phase, ms) Record(auraCosts, phase, ms) end

-- The ticker's pass ended (passMs: its timed entries): the frame's timed work is that pass and the
-- events timed since the last pass.
function Performance.RecordFrame(passMs)
    local ms = passMs + frames.eventMs
    frames.eventMs = 0
    local hooks = untimed.hooks - frames.hooksSeen
    frames.hooksSeen = untimed.hooks
    frames.count, frames.totalMs = frames.count + 1, frames.totalMs + ms
    if ms > frames.peakMs then frames.peakMs = ms end
    local part = frames.recent[slice]
    part[1], part[2], part[6] = part[1] + 1, part[2] + ms, part[6] + hooks
    if ms > part[3] then part[3] = ms end
    if ms > SLOW_FRAME_MS then
        frames.over5, part[4] = frames.over5 + 1, part[4] + 1
        if ms > VERY_SLOW_FRAME_MS then frames.over50, part[5] = frames.over50 + 1, part[5] + 1 end
    end
end

-- The frames section: recent window (the same 20-30 s as the rest) and session.
local function FrameFigures(into)
    local report = into or {}
    local count, total, peak, over5, over50, hooks = 0, 0, 0, 0, 0, 0
    for index = 1, SLICES do
        local part = frames.recent[index]
        count, total, over5, over50, hooks = count + part[1], total + part[2], over5 + part[4], over50 + part[5],
            hooks + part[6]
        if part[3] > peak then peak = part[3] end
    end
    report.recentFrames, report.recentOver5Ms, report.recentOver50Ms = count, over5, over50
    report.recentAverageMs = count > 0 and Round(total / count) or nil
    report.recentPeakMs = count > 0 and Round(peak) or nil
    report.recentUntimedHooksPerFrame = count > 0 and Round(hooks / count) or nil
    report.sessionFrames, report.sessionOver5Ms, report.sessionOver50Ms = frames.count, frames.over5, frames.over50
    report.sessionAverageMs = frames.count > 0 and Round(frames.totalMs / frames.count) or nil
    report.sessionPeakMs = frames.count > 0 and Round(frames.peakMs) or nil
    return report
end

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
    for _, store in ipairs(STORES) do
        for _, record in pairs(store.records) do
            local part = record.recent[slice]
            part[1], part[2], part[3] = 0, 0, 0
            record.version = record.version + 1
        end
    end
    local part = frames.recent[slice]
    for index = 1, #part do part[index] = 0 end
    part = Performance.addQueue.recent[slice]
    for index = 1, #part do part[index] = 0 end
end)

-- Starts every peak PlateSmith keeps (events, phases, ticker entries) again from now; calls and
-- totals stay. The client profiler's own session peak cannot be reset.
function Performance.ResetPeaks()
    for _, store in ipairs(STORES) do
        for _, record in pairs(store.records) do
            record.peakMs, record.version = 0, record.version + 1
            for index = 1, SLICES do record.recent[index][3] = 0 end
        end
    end
    frames.peakMs = 0
    for index = 1, SLICES do frames.recent[index][3] = 0 end
    Performance.addQueue.maxWaitFrames, Performance.addQueue.maxWaitMs = 0, 0
    for index = 1, SLICES do
        local part = Performance.addQueue.recent[index]
        part[3], part[ADD_WAIT_MS] = 0, 0
    end
    PS.Ticker.ResetPeaks()
end

-- A record's figures as the report lists them: session calls, total, average and peak, and the
-- recent window's calls, average and peak. into may be last refresh's table: every field is set.
local function Figures(record, into)
    local recentCalls, recentTotal, recentPeak = Recent(record)
    into.calls, into.totalMs, into.peakMs = record.calls, Round(record.totalMs), Round(record.peakMs)
    into.averageMs = record.calls > 0 and Round(record.totalMs / record.calls) or nil
    into.recentCalls, into.recentTotalMs = recentCalls, Round(recentTotal)
    into.recentAverageMs, into.recentPeakMs = nil, nil
    if recentCalls > 0 then into.recentAverageMs, into.recentPeakMs = Round(recentTotal / recentCalls), Round(recentPeak) end
    return into
end

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

-- The live view's figures refigure only a record whose version moved since they were made from it.
-- into keeps which record and version it shows (liveRecord, liveVersion); only the live view's
-- tables carry them, never a report's.
local function LiveFigures(record, into)
    if into.liveRecord == record and into.liveVersion == record.version then return into end
    into.liveRecord, into.liveVersion = record, record.version
    return Figures(record, into)
end

-- Each ticker entry's session figures (Ticker.Report) with its recent window's beside them.
-- into: last refresh's report, filled again; its recent figures are refigured only for an entry
-- whose record changed (seenVersions, by row: the version they were made from).
local seenVersions = setmetatable({}, { __mode = "k" })
local function TickerReport(into)
    local report = PS.Ticker.Report(into)
    for id, entry in pairs(report) do
        local record = tickCosts.records[id]
        local version = record and record.version
        if into and version ~= nil and seenVersions[entry] == version then
            record = nil
        else
            if into then seenVersions[entry] = version end
            entry.recentCalls, entry.recentAverageMs, entry.recentPeakMs = nil, nil, nil
        end
        if record then
            local calls, total, peak = Recent(record)
            entry.recentCalls = calls
            if calls > 0 then entry.recentAverageMs, entry.recentPeakMs = Round(total / calls), Round(peak) end
        end
    end
    return report
end

-- NAME_PLATE_UNIT_ADDED by kind (new, reused, queued), whichever were timed.
local function PlateAdds()
    local report = {}
    for _, kind in ipairs(PLATE_ADDED_ORDER) do
        local record = eventCosts.records[Performance.PLATE_ADDED[kind]]
        if record then report[kind] = Figures(record, {}) end
    end
    return report
end

-- Each phase that was timed, in the list's order (ADD_PHASES from phaseCosts, AURA_PHASES from auraCosts).
local function Phases(names, store)
    local report = PS.Json and PS.Json.Array() or {}
    for _, phase in ipairs(names) do
        local record = store.records[phase]
        if record then report[#report + 1] = Figures(record, { phase = phase }) end
    end
    return report
end

-- PlateSmith's recent average CPU time per frame (the client profiler's, in ms) and that as a
-- percentage of one frame at the current frame rate; nil for what the client does not report.
function Performance.RecentCost()
    local api = C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric
    local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
    if type(api) ~= "function" or metric == nil then return nil end
    local ok, ms = pcall(api, addonName, metric)
    if not ok or not PS.Secret.IsReadable(ms) or type(ms) ~= "number" or ms < 0 then return nil end
    if type(GetFramerate) ~= "function" then return ms end
    local fpsOk, fps = pcall(GetFramerate)
    if not fpsOk or not PS.Secret.IsReadable(fps) or type(fps) ~= "number" or fps <= 0 then return ms end
    return ms, ms * fps / 10
end

-- Client debug settings that slow every frame while on: taint logging and the old script profiler.
Performance.DEBUG_CVARS = { "taintLog", "scriptProfile" }

local function ReadCVar(name)
    local read = C_CVar and C_CVar.GetCVar or GetCVar
    if type(read) ~= "function" then return nil end
    local ok, value = pcall(read, name)
    if not ok or not PS.Secret.IsReadable(value) then return nil end
    if type(value) == "number" then return tostring(value) end
    return type(value) == "string" and value or nil
end

local function IsOn(value)
    local number = tonumber(value)
    if number then return number ~= 0 end
    return value ~= ""
end

-- Each debug CVar as the client has it (nil: unreadable here); the report's debugSettings.
function Performance.DebugSettings()
    local report = {}
    for _, name in ipairs(Performance.DEBUG_CVARS) do report[name] = ReadCVar(name) end
    return report
end

-- The debug CVars that are on now, in DEBUG_CVARS order.
function Performance.DebugSettingsOn(settings)
    settings = settings or Performance.DebugSettings()
    local on = {}
    for _, name in ipairs(Performance.DEBUG_CVARS) do
        local value = settings[name]
        if type(value) == "string" and IsOn(value) then on[#on + 1] = name end
    end
    return on
end

function Performance.Report()
    local debugSettings = Performance.DebugSettings()
    return { profiler = Profiler(addonName), frames = FrameFigures(), ticker = TickerReport(), events = TopEvents(false),
        recentEvents = TopEvents(true), recentWindowSeconds = SLICES * SLICE_SECONDS,
        plateAdds = PlateAdds(), addPhases = Phases(Performance.ADD_PHASES, phaseCosts),
        auraPhases = Phases(Performance.AURA_PHASES, auraCosts), debugSettings = next(debugSettings) and debugSettings or nil,
        addQueue = AddQueueFigures(), spares = Performance.SpareFigures and Performance.SpareFigures() or nil }
end

-- The live Performance tab's figures: the profiler, every ticker entry, the plate adds and their
-- phases, and the eventLimit events with the most time in the recent window (then the session).
-- Refreshed once a second while the tab shows, into the same tables every time (valid until the
-- next call): once every name has been seen, a refresh makes no tables. Nothing here runs otherwise.
local live = { byEvent = {}, ranked = {}, plateAdds = {}, phaseRows = {} }
live.result = { profiler = {}, frames = {}, ticker = {}, events = {}, plateAdds = live.plateAdds, addPhases = {},
    recentWindowSeconds = SLICES * SLICE_SECONDS, debugSettingsOn = {} }

-- Most recent-window time first, then session time, then name.
local function Ahead(a, b)
    if a.rankRecent ~= b.rankRecent then return a.rankRecent > b.rankRecent end
    if a.rankTotal ~= b.rankTotal then return a.rankTotal > b.rankTotal end
    return a.event < b.event
end

function Performance.Live(eventLimit)
    local result, ranked = live.result, live.ranked
    -- Every timed event keeps its row in ranked, which stays in last refresh's order: the insertion
    -- sort below is then one pass unless the ranking moved, and skipped when no event's rank did
    -- (a pass over rows already in order moves none). Only the rows shown get their figures.
    local moved = false
    for event, record in pairs(eventCosts.records) do
        local entry = live.byEvent[event]
        if not entry and record.calls > 0 then
            entry = { event = event, record = record }
            live.byEvent[event] = entry
            ranked[#ranked + 1] = entry
            moved = true
        end
        if entry and entry.rankVersion ~= record.version then
            local recent, total = record.recent, 0
            for index = 1, SLICES do total = total + recent[index][2] end
            if entry.rankRecent ~= total or entry.rankTotal ~= record.totalMs then moved = true end
            entry.rankRecent, entry.rankTotal, entry.rankVersion = total, record.totalMs, record.version
        end
    end
    for index = 2, moved and #ranked or 1 do
        local entry, at = ranked[index], index - 1
        while at > 0 and Ahead(entry, ranked[at]) do
            ranked[at + 1] = ranked[at]
            at = at - 1
        end
        ranked[at + 1] = entry
    end
    local events, shown = result.events, math.min(eventLimit or TOP_EVENTS, #ranked)
    for index = 1, shown do events[index] = LiveFigures(ranked[index].record, ranked[index]) end
    for index = shown + 1, #events do events[index] = nil end

    Profiler(addonName, result.profiler)
    FrameFigures(result.frames)
    TickerReport(result.ticker)
    for _, kind in ipairs(PLATE_ADDED_ORDER) do
        local record = eventCosts.records[Performance.PLATE_ADDED[kind]]
        if record then live.plateAdds[kind] = LiveFigures(record, live.plateAdds[kind] or {}) end
    end
    local phases, count = result.addPhases, 0
    for _, phase in ipairs(Performance.ADD_PHASES) do
        local record = phaseCosts.records[phase]
        if record then
            count = count + 1
            local row = live.phaseRows[phase] or { phase = phase }
            live.phaseRows[phase] = row
            phases[count] = LiveFigures(record, row)
        end
    end
    for index = count + 1, #phases do phases[index] = nil end
    local on = result.debugSettingsOn
    for index = #on, 1, -1 do on[index] = nil end
    for _, name in ipairs(Performance.DEBUG_CVARS) do
        local value = ReadCVar(name)
        if type(value) == "string" and IsOn(value) then on[#on + 1] = name end
    end
    return result
end

-- Once a session, on entering an instance with a debug setting on, one chat line says so.
local debugWarning = { shown = false }
Performance._debugWarning = debugWarning

function Performance.WarnDebugSettings()
    if debugWarning.shown or type(IsInInstance) ~= "function" then return false end
    local ok, inInstance = pcall(IsInInstance)
    if not ok or not PS.Secret.IsReadable(inInstance) or inInstance ~= true then return false end
    local on = Performance.DebugSettingsOn()
    if #on == 0 then return false end
    debugWarning.shown = true
    local frame = debugWarning.frame
    if frame and frame.UnregisterEvent then frame:UnregisterEvent("PLAYER_ENTERING_WORLD") end
    PS.Chat.Print(string.format(PS.L["%s is on, which costs frame time here. /console %s 0 turns it off; /ps perf shows "
        .. "PlateSmith's own cost."], table.concat(on, ", "), on[1]))
    return true
end

debugWarning.frame = CreateFrame("Frame")
debugWarning.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
debugWarning.frame:SetScript("OnEvent", function() Performance.WarnDebugSettings() end)
