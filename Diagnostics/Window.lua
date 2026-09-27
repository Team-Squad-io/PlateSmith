local _, PS = ...
local Json = assert(PS.Json, "PlateSmith Json missing")
local Format = assert(PS.Format, "PlateSmith Format missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local History = assert(PS.DiagnosticHistory, "PlateSmith DiagnosticHistory missing")
local Summary = assert(PS.DiagnosticSummary, "PlateSmith DiagnosticSummary missing")
local L = PS.L

-- The /platesmith diagnose window: Summary, Report (full JSON), and History tabs.
local UI = {}
PS.DiagnosticUI = UI

local TABS = { "summary", "report", "history" }
local TAB_LABELS = { summary = L["Summary"], report = L["Report"], history = L["History"] }

local window
local viewing

local function LayoutContent()
    if not window then return end
    local width = math.max(200, (window:GetWidth() or 760) - 56)
    window.editBox:SetWidth(width)
    window.summary:SetWidth(width)
    window.summary.text:SetWidth(width)
    window.historyList:SetWidth(width)
    for _, row in ipairs(window.historyRows) do row:SetWidth(width) end
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
    window.selectAll:SetShown(tab == "report")
    window.copyHint:SetShown(tab == "report")
    window.deleteEntry:SetShown(tab ~= "history" and viewing ~= nil)
    window.clearHistory:SetShown(tab == "history")
    if tab == "report" then
        window.editBox:SetFocus()
        window.editBox:HighlightText()
    end
end

local function HistoryLabel(entry)
    local report = type(entry.report) == "table" and entry.report or {}
    local target = type(report.target) == "table" and type(report.target.names) == "table"
        and report.target.names.display or nil
    local _, issueCount = Summary.Build(report)
    local parts = { Format.Clock(entry.time), tostring(entry.reason or "manual") }
    if target then parts[#parts + 1] = tostring(target) end
    parts[#parts + 1] = string.format(issueCount == 1 and L["%d issue"] or L["%d issues"], issueCount)
    if entry.error then parts[#parts + 1] = Format.Truncate(tostring(entry.error):match("^[^\n]*"), 90, 90) end
    return table.concat(parts, "  ·  ")
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
    window.historyList:SetHeight(math.max(40, #entries * 22))
    if window.tab then SelectTab(window.tab) end
end

-- savedEntry is set when showing a report reopened from History.
local function ShowView(report, savedEntry, tab)
    local current = UI.EnsureWindow()
    local content = Json.Encode(report, true)
    current.editBox:SetText(content)
    Window.SetScrollText(current.editBox, content, 14)
    local text, issueCount = Summary.Build(report, savedEntry)
    current.summary.text:SetText(text)
    Window.SetScrollText(current.summary, text, 16)
    viewing = savedEntry
    current.title:SetText(savedEntry and string.format(L["PlateSmith Diagnostics  ·  saved %s"], Format.Clock(savedEntry.time))
        or L["PlateSmith Diagnostics"])
    current.tabButtons.summary:SetText(issueCount > 0 and string.format(L["Summary (%d)"], issueCount) or TAB_LABELS.summary)
    current:Show()
    UI.Refresh()
    SelectTab(tab or "summary")
end

local function BuildWindow()
    local frame = Window.Create("PlateSmithDiagnosticsWindow", {
        width = 760, height = 520, title = L["PlateSmith Diagnostics"],
        resizable = { 560, 360, 1400, 1000 }, onSizeChanged = LayoutContent,
    })

    local historyToggle = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    historyToggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -150, -8)
    local historyLabel = historyToggle:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    historyLabel:SetPoint("LEFT", historyToggle, "RIGHT", 2, 0)
    historyLabel:SetText(L["Keep history"])
    historyToggle:SetScript("OnClick", function(instance) History.SetEnabled(instance:GetChecked() and true or false) end)

    local tabButtons, panes = {}, {}
    for index, key in ipairs(TABS) do
        local button = Window.Button(frame, TAB_LABELS[key], 110, 22, function() SelectTab(key) end)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + (index - 1) * 116, -38)
        tabButtons[key] = button
    end
    local capture = Window.Button(frame, L["Capture again"], 120, 22, function() PS.Diagnose() end)
    capture:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + #TABS * 116 + 16, -38)
    frame.captureButton = capture

    local summaryScroll, summary = Window.ScrollText(frame)
    local reportScroll, editBox = Window.ScrollEditBox(frame)
    local historyScroll, historyList = Window.ScrollText(frame)
    for _, pane in ipairs({ summaryScroll, reportScroll, historyScroll }) do
        pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -68)
        pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 45)
    end
    panes.summary, panes.report, panes.history = summaryScroll, reportScroll, historyScroll

    local historyRows = {}
    for index = 1, History.LIMIT do
        local row = CreateFrame("Button", nil, historyList)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", historyList, "TOPLEFT", 0, -(index - 1) * 22)
        if row.SetHighlightTexture then row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight") end
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetJustifyH("LEFT")
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

    local clearHistory = Window.Button(frame, L["Clear history"], 110, 24, function() History.Clear() end)
    clearHistory:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)

    local deleteEntry = Window.Button(frame, L["Delete this capture"], 130, 24, function()
        if viewing then History.Delete(viewing) end
        viewing = nil
        SelectTab("history")
    end)
    deleteEntry:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 12)

    frame.historyToggle, frame.tabButtons, frame.panes = historyToggle, tabButtons, panes
    frame.editBox, frame.scroll, frame.summary = editBox, reportScroll, summary
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
