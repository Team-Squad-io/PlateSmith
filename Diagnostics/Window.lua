local _, PS = ...
local Json = assert(PS.Json, "PlateSmith Json missing")
local Format = assert(PS.Format, "PlateSmith Format missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local History = assert(PS.DiagnosticHistory, "PlateSmith DiagnosticHistory missing")
local Summary = assert(PS.DiagnosticSummary, "PlateSmith DiagnosticSummary missing")
local ReportCode = assert(PS.DiagnosticCode, "PlateSmith DiagnosticCode missing")
local L = PS.L

-- The /platesmith diagnose window: the short Summary (what players paste, plus the one-line PS1
-- report code), Details (every flagged value), Report (full JSON), and History tabs.
local UI = {}
PS.DiagnosticUI = UI

local TABS = { "summary", "details", "report", "history" }
local TAB_LABELS = { summary = L["Summary"], details = L["Details"], report = L["Report"], history = L["History"] }
local SUMMARY_TAB_CONTROLS = { "copySummary", "copyReport", "showReport", "codeBox", "codeLabel", "summaryHint" }

local window
local viewing

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

local function SelectTab(tab)
    window.tab = tab
    for _, key in ipairs(TABS) do
        window.panes[key]:SetShown(key == tab)
        local button = window.tabButtons[key]
        if button.LockHighlight then
            if key == tab then button:LockHighlight() else button:UnlockHighlight() end
        end
    end
    for _, key in ipairs(SUMMARY_TAB_CONTROLS) do window[key]:SetShown(tab == "summary") end
    window.selectAll:SetShown(tab == "report")
    window.copyHint:SetShown(tab == "report")
    window.deleteEntry:SetShown(tab ~= "history" and viewing ~= nil)
    Window.RefreshScroll(window.panes[tab])
    if tab == "summary" then
        SelectText(window.summaryBox, window.summaryText)
    elseif tab == "report" then
        window.editBox:SetFocus()
        window.editBox:HighlightText()
    end
end

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

-- savedEntry is set when showing a report reopened from History.
local function ShowView(report, savedEntry, tab)
    local current = UI.EnsureWindow()
    current.report, viewing = report, savedEntry
    Window.SetScrollText(current.panes.report, Json.Encode(report, true))
    local text, issueCount = Summary.Build(report, savedEntry)
    Window.SetScrollText(current.panes.details, text)
    local code, flag = ReportCode.Encode(report)
    current.codeText, current.codeFlag = code, flag
    current.codeBox:SetText(code)
    if current.codeBox.SetCursorPosition then current.codeBox:SetCursorPosition(0) end
    current.codeLabel:SetText(string.format(flag == "z" and L["Full report code: %d characters, compressed"]
        or L["Full report code: %d characters, not compressed"], #code))
    current.title:SetText(savedEntry and string.format(L["PlateSmith Diagnostics  ·  saved %s"], Format.Clock(savedEntry.time))
        or L["PlateSmith Diagnostics"])
    current.tabButtons.details:SetText(issueCount > 0 and string.format(L["Details (%d)"], issueCount) or TAB_LABELS.details)
    current:Show()
    UI.Refresh()
    SelectTab(tab or "summary")
end

local function BuildWindow()
    local frame = Window.Create("PlateSmithDiagnosticsWindow", {
        width = 760, height = 520, title = L["PlateSmith Diagnostics"],
        resizable = { 680, 380, 1400, 1000 }, onSizeChanged = LayoutContent,
    })

    local historyToggle = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    historyToggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -250, -8)
    local historyLabel = historyToggle:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    historyLabel:SetPoint("LEFT", historyToggle, "RIGHT", 2, 0)
    historyLabel:SetText(L["Keep history"])
    historyToggle:SetScript("OnClick", function(instance) History.SetEnabled(instance:GetChecked() and true or false) end)
    -- Everything at once; each History row also has its own dismiss button.
    local clearHistory = Window.Button(frame, L["Clear history"], 110, 22, function() History.Clear() end)
    clearHistory:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -10)

    local tabButtons, panes = {}, {}
    for index, key in ipairs(TABS) do
        local button = Window.Button(frame, TAB_LABELS[key], 96, 22, function() SelectTab(key) end)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + (index - 1) * 100, -38)
        tabButtons[key] = button
    end
    local capture = Window.Button(frame, L["Capture again"], 120, 22, function() PS.Diagnose() end)
    capture:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + #TABS * 100 + 16, -38)
    frame.captureButton = capture

    local summaryScroll, summaryBox = Window.ScrollEditBox(frame, { font = "GameFontHighlight" })
    local detailsScroll, details = Window.ScrollText(frame)
    local reportScroll, editBox = Window.ScrollEditBox(frame)
    local historyScroll, historyList = Window.ScrollText(frame)
    -- The panes' scroll bars sit inside their right edge.
    for _, pane in ipairs({ summaryScroll, detailsScroll, reportScroll, historyScroll }) do
        pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -68)
        pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 45)
    end
    -- The summary pane leaves room for the report code line under it.
    summaryScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 100)
    historyScroll.measure = function() return math.max(1, #History.Entries()) * 22 end
    panes.summary, panes.details, panes.report, panes.history = summaryScroll, detailsScroll, reportScroll, historyScroll

    local codeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    codeLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 80)
    local summaryHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summaryHint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 80)
    summaryHint:SetText(L["Ctrl+C copies. Bug reports: paste the summary and the code line."])
    local codeBox = CreateFrame("EditBox", nil, frame)
    codeBox:SetAutoFocus(false)
    codeBox:SetFontObject("GameFontHighlightSmall")
    if codeBox.SetMaxLetters then codeBox:SetMaxLetters(0) end
    codeBox:SetHeight(20)
    codeBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 50)
    codeBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 50)
    codeBox:SetScript("OnEscapePressed", function() frame:Hide() end)

    local copySummary = Window.Button(frame, L["Copy summary"], 120, 24, function() SelectText(summaryBox, frame.summaryText) end)
    copySummary:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
    local copyReport = Window.Button(frame, L["Copy full report"], 130, 24, function() SelectText(codeBox, frame.codeText) end)
    copyReport:SetPoint("LEFT", copySummary, "RIGHT", 6, 0)
    local showReport = Window.Button(frame, L["Show full report"], 130, 24, function() SelectTab("report") end)
    showReport:SetPoint("LEFT", copyReport, "RIGHT", 6, 0)

    local historyRows = {}
    for index = 1, History.LIMIT do
        local row = CreateFrame("Button", nil, historyList)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", historyList, "TOPLEFT", 0, -(index - 1) * 22)
        row:SetPoint("TOPRIGHT", historyList, "TOPRIGHT", 0, -(index - 1) * 22)
        if row.SetHighlightTexture then row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight") end
        -- Removes just this capture (an old error, say) from the saved history and every count.
        local dismiss = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        dismiss:SetSize(20, 20)
        dismiss:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        dismiss:SetScript("OnClick", function()
            if row.entry then History.Delete(row.entry) end
        end)
        row.dismiss = dismiss
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", dismiss, "LEFT", -4, 0)
        label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(false) end
        row.label = label
        row:SetScript("OnClick", function(instance)
            if instance.entry then ShowView(instance.entry.report, instance.entry, "summary") end
        end)
        row:Hide()
        historyRows[index] = row
    end
    local historyEmpty = historyList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    historyEmpty:SetPoint("TOPLEFT", historyList, "TOPLEFT", 4, -4)

    local selectAll = Window.Button(frame, L["Select all"], 110, 24, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
    local copyHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    copyHint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
    copyHint:SetText(L["Press Ctrl+C to copy"])

    local deleteEntry = Window.Button(frame, L["Delete this capture"], 130, 24, function()
        if viewing then History.Delete(viewing) end
        viewing = nil
        SelectTab("history")
    end)
    deleteEntry:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 12)

    frame.historyToggle, frame.tabButtons, frame.panes = historyToggle, tabButtons, panes
    frame.editBox, frame.scroll, frame.details = editBox, reportScroll, details
    frame.summaryBox, frame.codeBox, frame.codeLabel, frame.summaryHint = summaryBox, codeBox, codeLabel, summaryHint
    frame.copySummary, frame.copyReport, frame.showReport = copySummary, copyReport, showReport
    frame.historyList, frame.historyRows, frame.historyEmpty = historyList, historyRows, historyEmpty
    frame.selectAll, frame.copyHint = selectAll, copyHint
    frame.clearHistory, frame.deleteEntry = clearHistory, deleteEntry
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

-- New reports are recorded in History when it is on, then shown.
function UI.ShowReport(report, reason)
    History.Record(report, reason or "manual")
    ShowView(report, nil, "summary")
end

function UI.ShowHistory()
    UI.EnsureWindow():Show()
    UI.Refresh()
    SelectTab("history")
end
