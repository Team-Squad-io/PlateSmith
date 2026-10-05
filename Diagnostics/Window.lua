local _, PS = ...
local Json = assert(PS.Json, "PlateSmith Json missing")
local Format = assert(PS.Format, "PlateSmith Format missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local Layout = assert(PS.UI and PS.UI.Layout, "PlateSmith Layout missing")
local History = assert(PS.DiagnosticHistory, "PlateSmith DiagnosticHistory missing")
local Summary = assert(PS.DiagnosticSummary, "PlateSmith DiagnosticSummary missing")
local Details = assert(PS.DiagnosticDetails, "PlateSmith DiagnosticDetails missing")
local ReportCode = assert(PS.DiagnosticCode, "PlateSmith DiagnosticCode missing")
local Performance = assert(PS.Performance, "PlateSmith Performance missing")
local L = PS.L

-- The /platesmith diagnose window: the short Summary (what players paste, plus the one-line PS1
-- report code), Details (the report in folding sections), Report (full JSON), the live
-- Performance view, and History tabs. It uses the panel kit's Blizzard palette and spacing, as the
-- Settings pages do.
local UI = {}
PS.DiagnosticUI = UI

local TABS = { "summary", "details", "report", "performance", "history" }
local TAB_LABELS = { summary = L["Summary"], details = L["Details"], report = L["Report"], performance = L["Performance"],
    history = L["History"] }
-- The tabs that show a captured report; opened with none, they capture one first.
local REPORT_TABS = { summary = true, details = true, report = true }
local SUMMARY_TAB_CONTROLS = { "copySummary", "copyReport", "showReport", "codeCard", "codeBox", "codeLabel", "summaryHint" }
local PALETTE = Layout.PALETTES.blizzard
local T = Layout.TOKENS
-- The window's frame: the title line, the tab strip under it, the panes, and the button row.
local FRAME = { width = 760, height = 540, headerY = -12, tabsY = -40, footer = 12 }
FRAME.top = -(-FRAME.tabsY + Window.tabMetrics.height + T.CARD_GAP)
FRAME.bottom = FRAME.footer + T.BUTTON_H + T.CARD_GAP
-- The Details tables' number columns.
local COLUMN = { width = 84, gap = 8 }
local LIMITED_INK = { 1, 0.79, 0.29 }
UI.metrics = FRAME

local window
local viewing
local kit

-- Each pane sizes its content to the text and shows its scroll bar only when that overflows.
local function LayoutContent()
    if not window then return end
    for _, key in ipairs(TABS) do Window.RefreshScroll(window.panes[key]) end
end

-- Copying is the client's own Ctrl+C: a copy button restores the text and selects all of it.
local function SelectText(box, text)
    box:SetText(text or "")
    box:SetFocus()
    box:HighlightText()
end

local function Ink(text, role)
    local colour = PALETTE.ink[role] or PALETTE.ink.label
    text:SetTextColor(colour[1], colour[2], colour[3], 1)
    return text
end

-- Details: pooled line frames (a label | value row, a sub-heading, a table header or row, or the
-- "and N more" line). A new report puts every line back in the pool; a section takes lines only
-- while it is open, at most Details.MAX_LINES of them.
local function NewLine(frame)
    local line = CreateFrame("Button", nil, frame.detailsFlow)
    line:SetHeight(kit.ROW_H)
    line.label = kit.Text(line, "", "label")
    line.value = kit.Text(line, "", "value")
    line.cells = {}
    for index = 1, 3 do
        local cell = kit.Text(line, "", "value")
        cell:SetJustifyH("RIGHT")
        cell:SetWidth(COLUMN.width)
        cell:SetPoint("RIGHT", line, "RIGHT", -(3 - index) * (COLUMN.width + COLUMN.gap), 0)
        line.cells[index] = cell
    end
    for _, text in ipairs({ line.label, line.value }) do
        if text.SetWordWrap then text:SetWordWrap(false) end
    end
    line:SetScript("OnClick", function(instance)
        if instance.data and instance.data.kind == "more" then UI.SelectTab("report") end
    end)
    return line
end

local function ConfigureLine(line, data)
    local kind = data.kind
    local label, value = line.label, line.value
    line.data = data
    label:ClearAllPoints()
    label:SetPoint("LEFT", line, "LEFT", 0, 0)
    local tabular = kind == "head" or kind == "trow"
    if kind == "row" then
        label:SetWidth(kit.LABEL_W)
    else
        label:SetPoint("RIGHT", line, "RIGHT", tabular and -3 * (COLUMN.width + COLUMN.gap) or 0, 0)
    end
    label:SetText(kind == "sub" and data.text or data.label or "")
    value:ClearAllPoints()
    value:SetPoint("LEFT", line, "LEFT", kit.CONTROL_X, 0)
    value:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    value:SetText(data.value or "")
    value:SetShown(kind == "row")
    for index, cell in ipairs(line.cells) do
        cell:SetText(tabular and data.cells[index] or "")
        cell:SetShown(tabular)
    end
    local labelRole = kind == "sub" and "sub" or (kind == "head" or kind == "more") and "muted" or "label"
    local valueRole = kind == "head" and "muted" or "value"
    if data.severity == "problem" then labelRole, valueRole = "error", "error" end
    Ink(label, labelRole)
    Ink(value, valueRole)
    for _, cell in ipairs(line.cells) do Ink(cell, valueRole) end
    if data.severity == "limited" then
        for _, text in ipairs({ label, value }) do text:SetTextColor(LIMITED_INK[1], LIMITED_INK[2], LIMITED_INK[3], 1) end
    end
    line:SetHeight(kind == "sub" and kit.LINE_H + T.SUB_GAP or kit.ROW_H)
    line:EnableMouse(kind == "more")
end

local function AcquireLine(frame, body, data)
    local pool = frame.linePool
    local line = table.remove(pool.free)
    if not line then
        line = NewLine(frame)
        pool.created = pool.created + 1
    end
    line:SetParent(body)
    ConfigureLine(line, data)
    line:Show()
    pool.used[#pool.used + 1] = line
    return line
end

local function ReleaseLines(frame)
    local pool = frame.linePool
    for index = #pool.used, 1, -1 do
        local line = pool.used[index]
        line:Hide()
        line:ClearAllPoints()
        line.data = nil
        pool.free[#pool.free + 1] = line
        pool.used[index] = nil
    end
end

-- A section's body: its lines, taken from the pool the first time it is laid out open.
local function MeasureBody(body)
    local frame = window
    if body.revision ~= frame.detailsRevision then
        body.revision, body.lines = frame.detailsRevision, {}
        for _, data in ipairs((Details.Lines(body.section.model))) do
            body.lines[#body.lines + 1] = AcquireLine(frame, body, data)
        end
    end
    local y = 0
    for index, line in ipairs(body.lines) do
        if line.data.kind == "sub" and index > 1 then y = y + T.SUB_TOP end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        line:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
        y = y + line:GetHeight()
    end
    body:SetHeight(math.max(1, y))
    return y
end

-- The ten sections, made the first time the Details tab opens.
local function EnsureDetailSections(frame)
    if frame.detailSections then return end
    local flow = frame.detailsFlow
    local help = kit.Help(flow, L["Every value in this capture, by topic. Flagged values come first in red; a folded "
        .. "section shows how many it has. The Report tab has the full text to copy."])
    kit.Add(flow, help)
    frame.detailSections = {}
    for _, spec in ipairs(Details.SECTIONS) do
        local section
        section = kit.Section(flow, spec[2], { key = "diag." .. spec[1],
            summary = function() return section.model and Details.HeaderText(section.model) or "" end })
        section.title:SetFontObject("GameFontNormal")
        kit.Ink(section.title, "title")
        local body = CreateFrame("Frame", nil, section)
        body:SetSize(kit.WIDTH, 1)
        body.section, body.Measure = section, MeasureBody
        section.body = body
        kit.Add(section, body)
        kit.Add(flow, section, function() return section.model ~= nil end)
        frame.detailSections[spec[1]] = section
    end
end

local function RenderDetails(frame)
    EnsureDetailSections(frame)
    ReleaseLines(frame)
    frame.detailsRevision = (frame.detailsRevision or 0) + 1
    local model = frame.detailsModel or Details.Build({})
    local present = {}
    for _, section in ipairs(model.sections) do present[section.key] = section end
    for key, section in pairs(frame.detailSections) do
        section.model = present[key]
        section.body.lines = {}
        if section.model then kit.Ink(section.summary, section.model.problems > 0 and "error" or "muted") end
    end
    frame.detailsRendered = model
    frame.panes.details:SetVerticalScroll(0)
end

-- The live Performance tab: refreshed by its own ticker entry once a second, enabled only while
-- the tab shows. Every refresh (the entry's and the one on opening) is timed here too, so the view
-- reports its own cost on its own line instead of hiding it in what it shows.
local LIVE = { interval = 1, eventRows = 12, calls = 0, peakMs = 0,
    ownName = string.format(L["%s (this view)"], Performance.LIVE_TICKER), on = L["on"], off = L["off"] }
UI.live = LIVE
local PERF_COLUMN = { width = 76, gap = 8 }
local ADD_KINDS = { "new", "reused", "queued" }
local PERF_TABLE_KEYS = { "adds", "phases", "events", "ticker" }
local EMPTY_LIST = {}

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

local function SetLive(on)
    if PS.Ticker.IsEnabled(Performance.LIVE_TICKER) ~= on then PS.Ticker.SetEnabled(Performance.LIVE_TICKER, on) end
end

local function Ms(value) return type(value) == "number" and string.format(L["%.2f"], value) or L["–"] end
local function Count(value) return type(value) == "number" and string.format("%d", math.floor(value + 0.5)) or L["–"] end
local function Seconds(value) return string.format(L["%.2f s"], type(value) == "number" and value or 0) end
local function Plain(value) return value ~= nil and tostring(value) or "" end

-- A refresh writes only what moved: each text keeps the value and format it shows (perfValue,
-- perfFormat) and its ink (perfRole), so an unchanged cell is neither formatted nor set again.
local NONE = {}
local function SetCell(text, value, format)
    local key = value == nil and NONE or value
    if text.perfValue == key and text.perfFormat == format then return end
    text.perfValue, text.perfFormat = key, format
    text:SetText(format(value))
end

local function SetRole(text, role)
    if text.perfRole == role then return end
    text.perfRole = role
    Ink(text, role)
end

-- The number columns' formats: the five figures of an add, phase or event, and a ticker entry's.
local FIGURES = { Count, Ms, Ms, Ms, Ms }
local TICKER_COLUMNS = { Plain, Seconds, Ms, Ms, Count }

-- A table line: a label, then count right-aligned number cells at the line's right end.
local function PerfLine(parent, count)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(kit.ROW_H)
    line.label = kit.Text(line, "", "label")
    line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.label:SetPoint("RIGHT", line, "RIGHT", -count * (PERF_COLUMN.width + PERF_COLUMN.gap), 0)
    if line.label.SetWordWrap then line.label:SetWordWrap(false) end
    line.cells = {}
    for index = 1, count do
        local cell = kit.Text(line, "", "value")
        cell:SetJustifyH("RIGHT")
        cell:SetWidth(PERF_COLUMN.width)
        cell:SetPoint("RIGHT", line, "RIGHT", -(count - index) * (PERF_COLUMN.width + PERF_COLUMN.gap), 0)
        line.cells[index] = cell
    end
    return line
end

-- Sets a line's label and its five number cells (formats[i] for value i) in role's ink ("error"
-- red, as in the Details tables).
local function SetLine(line, role, label, formats, a, b, c, d, e)
    -- Most lines show what they showed last refresh; only this function writes a line's texts, so
    -- the same arguments as its last call leave every cell as it is.
    local last = line.perfLast
    if last and last[1] == label and last[2] == role and last[3] == formats and last[4] == a and last[5] == b
        and last[6] == c and last[7] == d and last[8] == e then
        return
    end
    last = last or {}
    line.perfLast = last
    last[1], last[2], last[3], last[4], last[5], last[6], last[7], last[8] = label, role, formats, a, b, c, d, e
    SetCell(line.label, label, Plain)
    SetRole(line.label, role)
    local cells = line.cells
    SetCell(cells[1], a, formats[1])
    SetCell(cells[2], b, formats[2])
    SetCell(cells[3], c, formats[3])
    SetCell(cells[4], d, formats[4])
    SetCell(cells[5], e, formats[5])
    if line.perfRole == role then return end
    line.perfRole = role
    local cellRole = role == "label" and "value" or role
    for index = 1, #cells do SetRole(cells[index], cellRole) end
end

-- A table: its column heads, then rows made as they are first needed and reused on every refresh.
-- A row is shown or hidden only when the number of rows changes.
local function PerfTable(parent, columns)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(kit.WIDTH, kit.ROW_H)
    frame.count, frame.rows, frame.shownRows = #columns - 1, {}, 0
    frame.head = PerfLine(frame, frame.count)
    frame.head.label:SetText(columns[1])
    Ink(frame.head.label, "muted")
    for index, cell in ipairs(frame.head.cells) do
        cell:SetText(columns[index + 1])
        Ink(cell, "muted")
    end
    function frame:Row(index)
        local line = self.rows[index]
        if not line then
            line = PerfLine(self, self.count)
            self.rows[index] = line
        end
        if index > self.shownRows then line:Show() end
        return line
    end
    function frame:Finish(shown)
        for index = shown + 1, math.min(self.shownRows, #self.rows) do self.rows[index]:Hide() end
        self.shownRows = shown
    end
    function frame:Measure()
        local y = 0
        for index = 0, self.shownRows do
            local line = index == 0 and self.head or self.rows[index]
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
            line:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -y)
            y = y + kit.ROW_H
        end
        self:SetHeight(y)
        return y
    end
    return frame
end

-- A profiler figure: a number in its format (nil: a count), else the state the profiler gave.
local PROFILER_ROWS = {
    { "recent", "recentAverageMs", L["%.2f ms/frame"] }, { "session", "sessionAverageMs", L["%.2f ms/frame"] },
    { "peak", "peakMs", L["%.2f ms"] }, { "over5", "ticksOver5Ms" }, { "over50", "ticksOver50Ms" },
}
local profilerText = {}
for _, spec in ipairs(PROFILER_ROWS) do
    local text = spec[3]
    spec.format = function(value)
        if type(value) ~= "number" then return profilerText.unavailable or tostring(value or L["–"]) end
        return text and string.format(text, value) or Count(value)
    end
end
local function PerFrame(value)
    if type(value) ~= "number" then return L["–"] end
    return string.format(L["%.2f ms/frame"], value)
end
local function ViewCost(value)
    if type(value) ~= "number" then return L["–"] end
    return string.format(L["%.2f ms (peak %.2f)"], value / 100, LIVE.peakMs)
end

local function PaintProfiler(frame, live)
    local profiler, rows = live.profiler or {}, frame.perfProfilerRows
    profilerText.unavailable = profiler.state and L["unavailable"] or nil
    for _, spec in ipairs(PROFILER_ROWS) do SetCell(rows[spec[1]].value, profiler[spec[2]], spec.format) end
    local frames = live.frames or {}
    SetCell(rows.timed.value, frames.recentAverageMs, PerFrame)
    SetCell(rows.timedOver5.value, frames.recentOver5Ms, Count)
    local timed = frames.recentAverageMs
    SetRole(rows.timed.value, type(timed) == "number" and timed > Summary.frameBudgetMs and "error" or "value")
    -- This view's cost, to the hundredth shown, with its peak: written when either moves.
    local shownPeak = math.floor(LIVE.peakMs * 100 + 0.5)
    local shownLast = LIVE.lastMs and math.floor(LIVE.lastMs * 100 + 0.5) or nil
    local view = rows.view.value
    if view.perfPeak ~= shownPeak then view.perfPeak, view.perfValue = shownPeak, nil end
    SetCell(view, shownLast, ViewCost)
end

-- The debug warning's text, rebuilt only when which settings are on changes.
local function PaintDebugWarning(frame, on)
    local warning = frame.perfDebugWarning
    local key = #on > 0 and (on[1] .. #on) or ""
    if warning.perfKey == key then return end
    warning.perfKey = key
    warning.text:SetText(#on > 0 and string.format(L["%s is on in the client's settings: it costs frame "
        .. "time on every frame. /console %s 0 turns it off."], table.concat(on, ", "), on[1]) or "")
    warning:SetShown(#on > 0)
end

-- The ticker entries sorted by name, again only when an entry is registered.
local function TickerIds(frame, ticker)
    local ids, count = frame.perfTickerIds or {}, 0
    frame.perfTickerIds = ids
    for _ in pairs(ticker) do count = count + 1 end
    if count ~= #ids then
        for index = #ids, 1, -1 do ids[index] = nil end
        for id in pairs(ticker) do ids[#ids + 1] = id end
        table.sort(ids)
    end
    return ids
end

local function PaintFigures(line, label, entry)
    SetLine(line, "label", label, FIGURES, entry.calls, entry.recentAverageMs, entry.averageMs, entry.peakMs, entry.totalMs)
end

local function PaintPerformance(frame, live)
    PaintProfiler(frame, live)
    PaintDebugWarning(frame, live.debugSettingsOn or EMPTY_LIST)
    local tables = frame.perfTables
    local shown = 0
    for _, kind in ipairs(ADD_KINDS) do
        local entry = live.plateAdds[kind]
        if entry then
            shown = shown + 1
            PaintFigures(tables.adds:Row(shown), Details.PLATE_ADD_NAMES[kind], entry)
        end
    end
    tables.adds:Finish(shown)
    for index, entry in ipairs(live.addPhases) do
        PaintFigures(tables.phases:Row(index), Details.PHASE_NAMES[entry.phase] or entry.phase, entry)
    end
    tables.phases:Finish(#live.addPhases)
    for index, entry in ipairs(live.events) do
        PaintFigures(tables.events:Row(index), Summary.eventNames[entry.event] or entry.event, entry)
    end
    tables.events:Finish(#live.events)
    local ids = TickerIds(frame, live.ticker)
    for index, id in ipairs(ids) do
        local entry = live.ticker[id]
        local over = type(entry.recentAverageMs) == "number" and entry.recentAverageMs > Summary.tickBudgetMs
        local own = id == Performance.LIVE_TICKER
        SetLine(tables.ticker:Row(index), over and "error" or (own and "muted" or "label"), own and LIVE.ownName or id,
            TICKER_COLUMNS, entry.enabled and LIVE.on or LIVE.off, entry.interval, entry.recentAverageMs, entry.peakMs,
            entry.calls)
    end
    tables.ticker:Finish(#ids)
end

-- Whether the rows the view shows changed since it was last laid out (only then is it laid out again).
local function PerformanceShapeChanged(frame)
    local shape, tables = frame.perfShape or {}, frame.perfTables
    frame.perfShape = shape
    local changed = false
    for index, key in ipairs(PERF_TABLE_KEYS) do
        local rows = tables[key].shownRows
        if shape[index] ~= rows then shape[index], changed = rows, true end
    end
    local warning = frame.perfDebugWarning.perfKey
    if shape.warning ~= warning then shape.warning, changed = warning, true end
    return changed
end

-- One refresh of the live view; stops the refresh when the tab is no longer shown.
function UI.RefreshPerformance()
    if not window or window.tab ~= "performance" or not window:IsVisible() then
        SetLive(false)
        return
    end
    local started = Clock()
    PaintPerformance(window, Performance.Live(LIVE.eventRows))
    if PerformanceShapeChanged(window) then Window.RefreshScroll(window.panes.performance) end
    LIVE.calls = LIVE.calls + 1
    if started then
        local cost = Clock() - started
        LIVE.lastMs = cost
        if cost > LIVE.peakMs then LIVE.peakMs = cost end
    end
end

PS.Ticker.Register(Performance.LIVE_TICKER, LIVE.interval, function() UI.RefreshPerformance() end)
PS.Ticker.SetEnabled(Performance.LIVE_TICKER, false)

function UI.SelectTab(tab)
    -- Opened on Performance (or History), the window has no report until a report tab is chosen.
    if REPORT_TABS[tab] and not window.report and UI._buildReport then
        return UI.ShowReport(UI._buildReport(), "manual", tab)
    end
    window.tab = tab
    window.tabs:Select(tab)
    for _, key in ipairs(TABS) do
        window.panes[key]:SetShown(key == tab)
        if window.cards[key] then window.cards[key]:SetShown(key == tab) end
    end
    for _, key in ipairs(SUMMARY_TAB_CONTROLS) do window[key]:SetShown(tab == "summary") end
    window.selectAll:SetShown(tab == "report")
    window.copyHint:SetShown(tab == "report")
    window.resetPeaks:SetShown(tab == "performance")
    window.liveHint:SetShown(tab == "performance")
    window.deleteEntry:SetShown(tab ~= "history" and tab ~= "performance" and viewing ~= nil)
    if tab == "details" and window.detailsRendered ~= window.detailsModel then RenderDetails(window) end
    SetLive(tab == "performance")
    if tab == "performance" then UI.RefreshPerformance() end
    Window.RefreshScroll(window.panes[tab])
    if tab == "summary" then
        SelectText(window.summaryBox, window.summaryText)
    elseif tab == "report" then
        window.editBox:SetFocus()
        window.editBox:HighlightText()
    end
end
local SelectTab = UI.SelectTab

-- This session's PlateSmith errors, for the summary's problems. Older errors are left out: they
-- stay in History, labelled with their build, and can be dismissed there.
local function HistoryExtras(savedEntry)
    local errors = History.SessionErrors()
    local latest = errors[#errors]
    return { sessionErrors = #errors, lastError = latest and latest.error, lastErrorTime = latest and latest.time,
        now = type(time) == "function" and time() or nil, entry = savedEntry }
end

local function HistoryLabel(entry)
    local report = type(entry.report) == "table" and entry.report or {}
    local target = type(report.target) == "table" and type(report.target.names) == "table"
        and report.target.names.display or nil
    local _, issueCount = Summary.Build(report)
    local parts = { Format.Clock(entry.time), tostring(entry.reason or "manual") }
    local build = History.Build(entry)
    if build then parts[#parts + 1] = string.format(L["build %s"], build) end
    if target then parts[#parts + 1] = tostring(target) end
    parts[#parts + 1] = string.format(issueCount == 1 and L["%d issue"] or L["%d issues"], issueCount)
    if entry.error then parts[#parts + 1] = Summary.ShortError(entry.error, 90) end
    return table.concat(parts, "  ·  ")
end

-- The short summary counts this session's errors in History, so it is redrawn when History changes.
local function PaintSummary(current)
    local short, problemCount = Summary.Short(current.report, HistoryExtras(viewing))
    current.summaryText = short
    Window.SetScrollText(current.panes.summary, short)
    current.tabButtons.summary:SetText(problemCount > 0 and string.format(L["Summary (%d)"], problemCount)
        or TAB_LABELS.summary)
end

function UI.Refresh()
    if not window then return end
    -- A saved capture that was deleted or cleared is no longer being viewed.
    if viewing then
        local present = false
        for _, entry in ipairs(History.Entries()) do if entry == viewing then present = true break end end
        if not present then viewing = nil end
    end
    window.historyToggle:SetChecked(History.IsEnabled())
    local entries = History.Entries()
    for index, row in ipairs(window.historyRows) do
        local entry = entries[#entries - index + 1]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then row.label:SetText(HistoryLabel(entry)) end
    end
    window.historyEmpty:SetShown(#entries == 0)
    window.historyEmpty:SetText(History.IsEnabled() and L["No captures yet. Run /platesmith diagnose."]
        or L["History is off. Tick \"Keep history\" to save each diagnose and PlateSmith error snapshots."])
    window.clearHistory:SetEnabled(#entries > 0)
    window.clearHistory:SetAlpha(#entries > 0 and 1 or 0.45)
    Window.RefreshScroll(window.panes.history)
    if window.report then PaintSummary(window) end
    if window.tab then SelectTab(window.tab) end
end

-- savedEntry is set when showing a report reopened from History. The Details view is only
-- modelled here; its frames are laid out when its tab opens.
local function ShowView(report, savedEntry, tab)
    local current = UI.EnsureWindow()
    current.report, viewing = report, savedEntry
    Window.SetScrollText(current.panes.report, Json.Encode(report, true))
    local model = Details.Build(report, savedEntry)
    current.detailsModel = model
    local code, flag = ReportCode.Encode(report)
    current.codeText, current.codeFlag = code, flag
    current.codeBox:SetText(code)
    if current.codeBox.SetCursorPosition then current.codeBox:SetCursorPosition(0) end
    current.codeLabel:SetText(string.format(flag == "z" and L["Full report code: %d characters, compressed"]
        or L["Full report code: %d characters, not compressed"], #code))
    current.title:SetText(savedEntry and string.format(L["PlateSmith Diagnostics  ·  saved %s"], Format.Clock(savedEntry.time))
        or L["PlateSmith Diagnostics"])
    local flagged = model.problems + model.limited
    current.tabButtons.details:SetText(flagged > 0 and string.format(L["Details (%d)"], flagged) or TAB_LABELS.details)
    current:Show()
    UI.Refresh()
    SelectTab(tab or "summary")
end

-- A card (the palette's fill and edge) between the tab strip and the button row.
local function Card(frame, bottom)
    local card = kit.Card(frame)
    card:SetPoint("TOPLEFT", frame, "TOPLEFT", T.PAD_X, FRAME.top)
    card:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.PAD_X, bottom or FRAME.bottom)
    return card
end

local function Inside(pane, card)
    pane:SetPoint("TOPLEFT", card, "TOPLEFT", T.CARD_PAD, -T.CARD_PAD)
    pane:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -T.CARD_PAD, T.CARD_PAD)
end

local function BuildHeader(frame)
    frame.title:SetFontObject("GameFontNormalLarge")
    Ink(frame.title, "title")
    local capture = Window.Button(frame, L["Capture again"], 120, 22, function() PS.Diagnose() end)
    capture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, FRAME.headerY + 2)
    -- Everything at once; each History row also has its own dismiss button.
    local clearHistory = Window.Button(frame, L["Clear history"], 110, 22, function() History.Clear() end)
    clearHistory:SetPoint("RIGHT", capture, "LEFT", -T.CONTROL_GAP, 0)
    local historyLabel = Ink(frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"), "label")
    historyLabel:SetPoint("RIGHT", clearHistory, "LEFT", -2 * T.CONTROL_GAP, 0)
    historyLabel:SetText(L["Keep history"])
    local historyToggle = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    historyToggle:SetSize(T.CHECK_W, T.CHECK_W)
    historyToggle:SetPoint("RIGHT", historyLabel, "LEFT", 0, 0)
    historyToggle:SetScript("OnClick", function(instance) History.SetEnabled(instance:GetChecked() and true or false) end)
    frame.captureButton, frame.clearHistory, frame.historyToggle = capture, clearHistory, historyToggle

    local tabSpecs = {}
    for index, key in ipairs(TABS) do tabSpecs[index] = { key, TAB_LABELS[key] } end
    local tabs = Window.Tabs(frame, { tabs = tabSpecs, onSelect = function(key) SelectTab(key) end })
    tabs:SetPoint("TOPLEFT", frame, "TOPLEFT", T.PAD_X, FRAME.tabsY)
    tabs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -T.PAD_X, FRAME.tabsY)
    frame.tabs, frame.tabButtons = tabs, tabs.buttons
end

local function BuildSummary(frame)
    local codeTop = FRAME.bottom + 2
    local summaryCard = Card(frame, codeTop + T.CONTROL_H + T.LINE_H + 2 * T.CARD_GAP)
    local summaryScroll, summaryBox = Window.ScrollEditBox(frame, { font = "GameFontHighlight" })
    summaryScroll:SetParent(summaryCard)
    Inside(summaryScroll, summaryCard)

    local codeCard = kit.Card(frame)
    codeCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", T.PAD_X, codeTop)
    codeCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.PAD_X, codeTop)
    codeCard:SetHeight(T.CONTROL_H)
    local codeBox = CreateFrame("EditBox", nil, codeCard)
    codeBox:SetAutoFocus(false)
    codeBox:SetFontObject("GameFontHighlightSmall")
    if codeBox.SetMaxLetters then codeBox:SetMaxLetters(0) end
    codeBox:SetPoint("TOPLEFT", codeCard, "TOPLEFT", T.CARD_PAD, 0)
    codeBox:SetPoint("BOTTOMRIGHT", codeCard, "BOTTOMRIGHT", -T.CARD_PAD, 0)
    codeBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    local codeLabel = Ink(frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), "sub")
    codeLabel:SetPoint("BOTTOMLEFT", codeCard, "TOPLEFT", 0, T.CARD_GAP / 2)
    local summaryHint = Ink(frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "muted")
    summaryHint:SetPoint("BOTTOMRIGHT", codeCard, "TOPRIGHT", 0, T.CARD_GAP / 2)
    summaryHint:SetText(L["Ctrl+C copies. Bug reports: paste the summary and the code line."])

    local copySummary = Window.Button(frame, L["Copy summary"], 120, T.BUTTON_H,
        function() SelectText(summaryBox, frame.summaryText) end)
    copySummary:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", T.PAD_X, FRAME.footer)
    local copyReport = Window.Button(frame, L["Copy full report"], 130, T.BUTTON_H,
        function() SelectText(codeBox, frame.codeText) end)
    copyReport:SetPoint("LEFT", copySummary, "RIGHT", T.CONTROL_GAP, 0)
    local showReport = Window.Button(frame, L["Show full report"], 130, T.BUTTON_H, function() SelectTab("report") end)
    showReport:SetPoint("LEFT", copyReport, "RIGHT", T.CONTROL_GAP, 0)

    frame.cards.summary, frame.panes.summary = summaryCard, summaryScroll
    frame.summaryBox, frame.codeCard, frame.codeBox, frame.codeLabel = summaryBox, codeCard, codeBox, codeLabel
    frame.summaryHint, frame.copySummary, frame.copyReport, frame.showReport = summaryHint, copySummary, copyReport, showReport
end

local function BuildDetails(frame)
    local detailsScroll, detailsChild = Window.ScrollText(frame)
    detailsScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", T.PAD_X, FRAME.top)
    detailsScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.PAD_X, FRAME.bottom)
    local flow = kit.Flow(CreateFrame("Frame", nil, detailsChild))
    flow:SetPoint("TOPLEFT", detailsChild, "TOPLEFT", 0, 0)
    flow:SetSize(kit.WIDTH, 1)
    -- The sections fill the pane's width (less the scroll bar when it shows).
    detailsScroll.measure = function(width)
        flow:SetWidth(width)
        local height = kit.LayoutFlow(flow, 0)
        flow:SetHeight(math.max(1, height))
        return height
    end
    frame.panes.details, frame.detailsFlow = detailsScroll, flow
    frame.linePool = { free = {}, used = {}, created = 0 }
end

local function BuildReport(frame)
    local card = Card(frame)
    local reportScroll, editBox = Window.ScrollEditBox(frame)
    reportScroll:SetParent(card)
    Inside(reportScroll, card)
    local selectAll = Window.Button(frame, L["Select all"], 110, T.BUTTON_H, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", T.PAD_X, FRAME.footer)
    local copyHint = Ink(frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "muted")
    copyHint:SetPoint("LEFT", selectAll, "RIGHT", T.CONTROL_GAP + 2, 0)
    copyHint:SetText(L["Press Ctrl+C to copy"])
    frame.cards.report, frame.panes.report = card, reportScroll
    frame.editBox, frame.scroll, frame.selectAll, frame.copyHint = editBox, reportScroll, selectAll, copyHint
end

local function BuildPerformance(frame)
    local scroll, child = Window.ScrollText(frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", T.PAD_X, FRAME.top)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.PAD_X, FRAME.bottom)
    local flow = kit.Flow(CreateFrame("Frame", nil, child))
    flow:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    flow:SetSize(kit.WIDTH, 1)
    scroll.measure = function(width)
        flow:SetWidth(width)
        local height = kit.LayoutFlow(flow, 0)
        flow:SetHeight(math.max(1, height))
        return height
    end
    kit.Add(flow, kit.Help(flow, L["Live figures, refreshed once a second while this tab is open; opening it captures no "
        .. "report. The client profiler's figures include this view's own refresh, which is also shown on its own."]))
    -- A client debug setting that slows every frame (taintLog, scriptProfile): shown only while one is on.
    local debugWarning = kit.Help(flow, "")
    Ink(debugWarning.text, "error")
    kit.Add(flow, debugWarning, function() return (debugWarning.text:GetText() or "") ~= "" end)
    frame.perfDebugWarning = debugWarning
    local function Section(key, title)
        local section = kit.Section(flow, title, { key = "perf." .. key })
        section.title:SetFontObject("GameFontNormal")
        kit.Ink(section.title, "title")
        kit.Add(flow, section)
        return section
    end
    local profiler = Section("profiler", L["Profiler"])
    local rows = {}
    -- PlateSmith's own timed work first (ticker passes and timed events, over the recent window), then
    -- the client profiler's figures: all PlateSmith code, Studio and untimed hooks included, the frame
    -- counts since login.
    for _, spec in ipairs({ { "timed", L["Timed work, recent"] }, { "timedOver5", L["Timed frames over 5 ms, recent"] },
        { "recent", L["Client: recent average"] }, { "session", L["Client: session average"] },
        { "peak", L["Peak (client profiler, this session)"] }, { "over5", L["Client: frames over 5 ms, session"] },
        { "over50", L["Client: frames over 50 ms, session"] }, { "view", L["This view's refresh"] } }) do
        local row = kit.Row(profiler, spec[2])
        row.value = kit.Value(row)
        row.value:SetWidth(160)
        kit.Add(profiler, row)
        rows[spec[1]] = row
    end
    -- The first column names the row; the rest are the same five figures.
    local function Columns(first) return { first, L["Calls"], L["Recent ms"], L["Average ms"], L["Peak ms"], L["Total ms"] } end
    local tables = {}
    local adds = Section("adds", L["Plate adds"])
    tables.adds = kit.Add(adds, PerfTable(adds, Columns(L["Kind"])))
    tables.phases = kit.Add(adds, PerfTable(adds, Columns(L["Phase of an add"])))
    local events = Section("events", L["Events"])
    tables.events = kit.Add(events, PerfTable(events, Columns(L["Event"])))
    local ticker = Section("ticker", L["Ticker entries"])
    tables.ticker = kit.Add(ticker, PerfTable(ticker, { L["Name"], L["On"], L["Interval"], L["Recent ms"], L["Peak ms"],
        L["Calls"] }))
    frame.panes.performance, frame.perfFlow, frame.perfProfilerRows, frame.perfTables = scroll, flow, rows, tables

    local resetPeaks = Window.Button(frame, L["Reset peaks"], 110, T.BUTTON_H, function()
        Performance.ResetPeaks()
        LIVE.peakMs = 0
        UI.RefreshPerformance()
    end)
    resetPeaks:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", T.PAD_X, FRAME.footer)
    local liveHint = Ink(frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "muted")
    liveHint:SetPoint("LEFT", resetPeaks, "RIGHT", T.CONTROL_GAP + 2, 0)
    liveHint:SetText(L["Peaks are PlateSmith's own since the last reset; the client profiler's peak cannot be reset."])
    frame.resetPeaks, frame.liveHint = resetPeaks, liveHint
end

local function BuildHistory(frame)
    local card = Card(frame)
    local historyScroll, historyList = Window.ScrollText(frame)
    historyScroll:SetParent(card)
    Inside(historyScroll, card)
    local rowHeight = kit.ROW_H + 2
    historyScroll.measure = function() return math.max(1, #History.Entries()) * rowHeight end
    local historyRows = {}
    for index = 1, History.LIMIT do
        local row = CreateFrame("Button", nil, historyList)
        row:SetHeight(kit.ROW_H)
        row:SetPoint("TOPLEFT", historyList, "TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", historyList, "TOPRIGHT", 0, -(index - 1) * rowHeight)
        if row.SetHighlightTexture then row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight") end
        -- Removes just this capture (an old error, say) from the saved history and every count.
        local dismiss = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        dismiss:SetSize(20, 20)
        dismiss:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        dismiss:SetScript("OnClick", function()
            if row.entry then History.Delete(row.entry) end
        end)
        row.dismiss = dismiss
        local label = kit.Text(row, "", "label")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", dismiss, "LEFT", -4, 0)
        if label.SetWordWrap then label:SetWordWrap(false) end
        row.label = label
        row:SetScript("OnClick", function(instance)
            if instance.entry then ShowView(instance.entry.report, instance.entry, "summary") end
        end)
        row:Hide()
        historyRows[index] = row
    end
    local historyEmpty = kit.Text(historyList, "", "muted")
    historyEmpty:SetPoint("TOPLEFT", historyList, "TOPLEFT", 4, -4)
    frame.cards.history, frame.panes.history = card, historyScroll
    frame.historyList, frame.historyRows, frame.historyEmpty = historyList, historyRows, historyEmpty
end

local function BuildWindow()
    local frame = Window.Create("PlateSmithDiagnosticsWindow", {
        width = FRAME.width, height = FRAME.height, title = L["PlateSmith Diagnostics"], border = PALETTE.divider,
        resizable = { 680, 400, 1400, 1000 }, onSizeChanged = LayoutContent,
    })
    kit = Layout.New({
        width = FRAME.width - 2 * T.PAD_X, palette = PALETTE, collapsible = true,
        tokens = { LABEL_W = 250, VALUE_W = 80, ROW_H = 20, SECTION_TOP = 10, SECTION_TITLE_GAP = 6 },
        sectionState = function()
            local state = PS.GetState and PS.GetState()
            return state and state.sectionFolds
        end,
        -- A section folded or opened: the pane it is in (Details, or the live Performance view,
        -- which is otherwise laid out only when its rows change).
        relayout = function()
            if window then Window.RefreshScroll(window.tab == "performance" and window.panes.performance or window.panes.details) end
        end,
    })
    frame.kit, frame.cards, frame.panes = kit, {}, {}
    BuildHeader(frame)
    BuildSummary(frame)
    BuildDetails(frame)
    BuildReport(frame)
    BuildPerformance(frame)
    BuildHistory(frame)
    -- Closed (Escape, the close button, the UI hidden), the live view stops refreshing.
    frame:HookScript("OnHide", function() SetLive(false) end)
    local deleteEntry = Window.Button(frame, L["Delete this capture"], 130, T.BUTTON_H, function()
        if viewing then History.Delete(viewing) end
        viewing = nil
        SelectTab("history")
    end)
    deleteEntry:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(T.PAD_X + 18), FRAME.footer)
    frame.deleteEntry = deleteEntry
    return frame
end

function UI.EnsureWindow()
    if window then return window end
    window = BuildWindow()
    PS._diagnosticWindow = window
    History.onChange = UI.Refresh
    LayoutContent()
    return window
end

-- New reports are recorded in History when it is on, then shown (on tab, default Summary).
function UI.ShowReport(report, reason, tab)
    History.Record(report, reason or "manual")
    ShowView(report, nil, tab or "summary")
end

-- The live Performance tab, without capturing a report.
function UI.ShowPerformance()
    UI.EnsureWindow():Show()
    SelectTab("performance")
end

function UI.ShowHistory()
    UI.EnsureWindow():Show()
    UI.Refresh()
    SelectTab("history")
end
