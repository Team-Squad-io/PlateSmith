local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local L = PS.L

-- The Blueprint Export / Share and Import window opened from Blueprint Studio. Export shows the share
-- code (and Link in chat). Import has two tabs: Paste (the instruction, the box and what the pasted text
-- includes) and Review, open once the text is a Blueprint: the section boxes in a column at the left, the
-- preview of what importing them would change at the right (a small Studio stage, ImportPreview.lua), and
-- Import selected. Context designs and Enemy players show only for a Blueprint that has such designs (has:
-- from PS.BlueprintDescribe's info); the shown boxes fill the column in order, so a hidden one leaves no gap.
local importSections = {
    { key = "settings", label = L["General settings"] },
    { key = "layouts", label = L["World layouts"] },
    { key = "styles", label = L["Plate sizes & bar styles"] },
    { key = "values", label = L["Custom parts & power"] },
    { key = "other", label = L["Companion-addon data"] },
    { key = "contexts", label = L["Context designs (dungeons, PvP, cities)"],
        has = function(info) return #info.contexts > 0 end },
    { key = "enemyPlayers", label = L["Enemy players"], has = function(info) return info.enemyPlayers == true end },
}

-- Import: the tab strip under the title; Paste's instruction, box and summary under it; Review's section
-- boxes in a column (SECTIONS_WIDTH, Select all under them) and the stage from PREVIEW_X to the window's
-- right, down to the Import selected row. Export keeps its own size: the share code fills it.
local IMPORT_WIDTH, IMPORT_HEIGHT, EXPORT_WIDTH, EXPORT_HEIGHT = 800, 540, 730, 540
local TABS_TOP, PAGE_TOP = -44, -84
local IMPORT_TEXT_TOP, IMPORT_TEXT_HEIGHT, SUMMARY_TOP = -166, 220, -410
local SECTIONS_TOP, SECTION_ROW, SECTIONS_WIDTH = -110, 28, 272
local PREVIEW_X, PREVIEW_BOTTOM = 22 + SECTIONS_WIDTH + 12, 58
local EXPORT_TEXT_TOP = -86

-- The shown section boxes in one column, in order, and Select all under them.
local function PlaceSections(window)
    local index = 0
    for _, section in ipairs(importSections) do
        local checkbox = window.checkboxes[section.key]
        if checkbox:IsShown() then
            checkbox:ClearAllPoints()
            checkbox:SetPoint("TOPLEFT", window, "TOPLEFT", 18, SECTIONS_TOP - index * SECTION_ROW)
            index = index + 1
        end
    end
    window.selectSections:ClearAllPoints()
    window.selectSections:SetPoint("TOPLEFT", window, "TOPLEFT", 22, SECTIONS_TOP - index * SECTION_ROW - 8)
end

-- The sections Import selected imports: a hidden one never does.
local function Selection(window)
    local selection = {}
    for _, section in ipairs(importSections) do
        local checkbox = window.checkboxes[section.key]
        selection[section.key] = checkbox:IsShown() and checkbox:GetChecked() and true or false
    end
    return selection
end

-- The text and its box: Export's, and Import's on its Paste tab.
local function ShowTextBox(window, shown)
    for _, part in ipairs({ window.instruction, window.inset, window.scroll }) do part:SetShown(shown) end
    window.placeholder:SetShown(shown and window.importing and (window.editBox:GetText() or "") == "")
    -- Withheld, the bar and its arrows stay hidden whatever the text's length (Sync runs on every change).
    window.scrollBar.withheld = not shown or nil
    window.scrollBar:Sync()
end

-- Import's tabs: Paste always; Review only while the text is a Blueprint, its label counting the designs
-- the preview shows ("Review (3)").
local function SelectTab(window, key)
    if key == "review" and not window.importInfo then key = "paste" end
    window.importTab = key
    window.tabs:Select(key)
    window.pastePage:SetShown(window.importing and key == "paste")
    window.reviewPage:SetShown(window.importing and key == "review")
    ShowTextBox(window, not window.importing or key == "paste")
    -- Review pages with the arrow keys (ImportPreview.Key); every other key, and every key elsewhere, passes on.
    local keys = window.importing and key == "review" or false
    if window.EnableKeyboard and not PS.Secret.InCombat() then pcall(window.EnableKeyboard, window, keys) end
end

local function RefreshReview(window)
    local valid = window.importInfo ~= nil
    local changes = window.preview and window.preview.changes
    local tab = window.tabs.buttons.review
    tab:SetText(valid and changes and #changes > 0 and string.format(L["Review (%d)"], #changes) or L["Review"])
    PS.SaveBar.SetAvailable(tab, valid)
    PS.SaveBar.SetAvailable(window.reviewButton, valid)
    if not valid and window.importTab == "review" then SelectTab(window, "paste") end
end

-- What the pasted text includes (PS.BlueprintDescribe), and the sections that need data only when
-- it has some: hidden, a section is unticked, so it imports nothing. The preview follows: cleared at
-- once for text that is not a Blueprint, else rebuilt a moment later.
local function Describe(window)
    local summary, info = PS.BlueprintDescribe(window.editBox:GetText() or "")
    window.summary:SetText(summary or "")
    for _, section in ipairs(importSections) do
        if section.has then
            local checkbox = window.checkboxes[section.key]
            local shown = window.importing and info ~= nil and section.has(info) == true
            -- Ticked when it appears, as every section starts.
            if shown ~= checkbox:IsShown() then checkbox:SetChecked(shown) end
            checkbox:SetShown(shown)
        end
    end
    PlaceSections(window)
    if not window.importing then return end
    window.importInfo = info
    -- New text starts the preview on its first design.
    Options.ImportPreview.ResetPage(window)
    if info then Options.ImportPreview.Schedule(window) else Options.ImportPreview.Clear(window) end
    RefreshReview(window)
end

-- Import and Export share the window: Import is larger, with its tabs. Its text spans the window.
local function SetImporting(window, importing)
    window.importing = importing
    local width = importing and IMPORT_WIDTH or EXPORT_WIDTH
    window:SetSize(width, importing and IMPORT_HEIGHT or EXPORT_HEIGHT)
    window.instruction:SetWidth(width - 50)
    window.summary:SetWidth(width - 50)
    window.editBox:SetWidth(width - 90)
    -- The panel art follows at once (its size hook may wait for the next layout pass).
    if window.studioArt then window.studioArt:Layout() end
    window.tabs:SetShown(importing)
    window.preview:SetShown(importing)
    window.instruction:ClearAllPoints()
    window.instruction:SetPoint("TOPLEFT", window, "TOPLEFT", 22, importing and PAGE_TOP or -50)
    -- Export's text and its buttons sit on the window itself; Import's on its pages.
    window.exportButtons:SetShown(not importing)
    if not importing then
        window.pastePage:Hide()
        window.reviewPage:Hide()
        ShowTextBox(window, true)
    end
end

-- The text's height as the box draws it: a hidden font string of the same font and width
-- measures it (an edit box reports no text height). Without one, lines wrap at ~160 characters.
local function TextHeight(window, text)
    text = tostring(text or "")
    local measure = window.textMeasure
    local height = measure and measure.GetStringHeight and (function()
        measure:SetWidth(window.editBox:GetWidth())
        measure:SetText(text)
        return measure:GetStringHeight()
    end)()
    if not height or height <= 0 then
        height = 0
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            height = height + math.max(1, math.ceil(#line / 160)) * 12
        end
    end
    return math.max(window.scroll:GetHeight(), height + 12)
end

local function ShowText(window, text)
    window.editBox:SetHeight(TextHeight(window, text))
    window:Show()
    window.editBox:SetText(text)
    window.scroll:SetVerticalScroll(0)
    window.scrollBar:Sync()
    window.editBox:HighlightText()
    window.editBox:SetFocus()
end

local function Import(window)
    local ok, reason, otherFlavor, skipped = PS.ImportBlueprint(window.editBox:GetText(), Selection(window))
    if ok then
        Options:Refresh(true)
        window:Hide()
        Chat.Print(L["Selected Blueprint sections imported. Press Save to keep them."])
        -- Fields from a newer PlateSmith were skipped: one line names them.
        local skippedLine = PS.BlueprintSkippedMessage(skipped)
        if skippedLine then Chat.Print(skippedLine) end
        if otherFlavor then
            Chat.Print(string.format(L["This Blueprint was made on the %s client; some options may look different here."], otherFlavor))
        end
    else
        -- The reason may quote the pasted text: printed with its chat escapes made literal.
        Chat.Print(PS.BlueprintFailureMessage(reason))
    end
end

-- A frame over the whole window that shows or hides a group of its parts at once.
local function Page(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetAllPoints(window)
    page:SetFrameLevel(window:GetFrameLevel() + 1)
    page:Hide()
    return page
end

local function EnsureWindow()
    if Options.blueprintWindow then return Options.blueprintWindow end
    local window = Window.Create("PlateSmithBlueprintWindow", {
        width = EXPORT_WIDTH, height = EXPORT_HEIGHT, title = "", titleFont = "GameFontNormalLarge",
        border = Window.colours.studio, background = { 0.025, 0.03, 0.035, 0.98 },
    })
    local chrome = Options.studioChrome
    local pastePage, reviewPage, exportButtons = Page(window), Page(window), Page(window)
    window.pastePage, window.reviewPage, window.exportButtons = pastePage, reviewPage, exportButtons
    local tabs = Window.Tabs(window, { tabs = { { "paste", L["Paste"] }, { "review", L["Review"] } },
        onSelect = function(key) SelectTab(window, key) end })
    tabs:SetPoint("TOPLEFT", window, "TOPLEFT", 22, TABS_TOP)
    tabs:SetPoint("TOPRIGHT", window, "TOPRIGHT", -22, TABS_TOP)
    tabs:Hide()
    window.tabs = tabs
    local instruction = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instruction:SetFont(chrome.FONT, 13)
    instruction:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    instruction:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -50)
    instruction:SetWidth(680)
    instruction:SetJustifyH("LEFT")

    chrome.DressStudioDialog(window)
    -- The text sits in one of Studio's dark panels; export uses the window's full height.
    local inset = CreateFrame("Frame", nil, window)
    inset:SetFrameLevel(window:GetFrameLevel() + 1)
    local insetArt = chrome.CreatePanelArt(inset, "dark")
    inset:SetScript("OnSizeChanged", function() insetArt:Layout() end)
    local scroll, editBox = Window.ScrollEditBox(window, { plain = true })
    scroll:SetFrameLevel(inset:GetFrameLevel() + 2)
    -- Studio's scroll bar, shown only when the text is longer than the box.
    local scrollBar = chrome.CreateStudioScrollBar(scroll, window)
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, -18)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 18)
    window.scrollBar = scrollBar
    local measure = window:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
    measure:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    if measure.SetJustifyH then measure:SetJustifyH("LEFT") end
    if measure.SetAlpha then measure:SetAlpha(0) end
    measure:Hide()
    window.textMeasure = measure
    -- A click anywhere in the box puts the cursor in the text (the edit box itself is only as
    -- tall as its lines).
    if scroll.EnableMouse then scroll:EnableMouse(true) end
    scroll:SetScript("OnMouseDown", function()
        editBox:SetFocus()
        if editBox.SetCursorPosition then editBox:SetCursorPosition(#(editBox:GetText() or "")) end
    end)
    -- Import's hint sits in the empty box until something is pasted or typed.
    local placeholder = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -4)
    placeholder:SetText(L["Paste a share code or Blueprint JSON here (Ctrl+V)"])
    placeholder:Hide()
    window.placeholder = placeholder
    -- Pasted or typed text grows the box's content, and the cursor stays in view.
    editBox:SetScript("OnTextChanged", function(instance)
        instance:SetHeight(TextHeight(window, instance:GetText()))
        placeholder:SetShown(window.importing and (instance:GetText() or "") == "")
        if window.importing then Describe(window) end
        scrollBar:Sync()
    end)
    editBox:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        local offset, view = scroll:GetVerticalScroll() or 0, scroll:GetHeight()
        local top, line = -(y or 0), lineHeight or 16
        if top < offset then scroll:SetVerticalScroll(top)
        elseif top + line > offset + view then scroll:SetVerticalScroll(top + line - view) end
        scrollBar:Sync()
    end)
    editBox:SetWidth(640)
    inset:SetPoint("TOPLEFT", scroll, "TOPLEFT", -10, 10)
    inset:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 30, -10)
    window.inset = inset

    -- Paste: what the pasted Blueprint includes, under the text, and Review to go on.
    local summary = pastePage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetFont(chrome.FONT, 12)
    summary:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    summary:SetPoint("TOPLEFT", window, "TOPLEFT", 22, SUMMARY_TOP)
    summary:SetWidth(680)
    summary:SetJustifyH("LEFT")
    window.summary = summary
    local pasteHint = pastePage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pasteHint:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 24, 28)
    pasteHint:SetText(L["Press Ctrl+V to paste"])
    local reviewButton = chrome.CreateStudioButton(pastePage, L["Review"], 150, 28, "primary")
    reviewButton:SetScript("OnClick", function() SelectTab(window, "review") end)
    reviewButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 20)
    window.reviewButton = reviewButton

    -- Review: the section boxes in a column, beside the plates they change.
    local selectionLabel = reviewPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectionLabel:SetFont(chrome.FONT, 15)
    selectionLabel:SetTextColor(chrome.GOLD[1], chrome.GOLD[2], chrome.GOLD[3])
    selectionLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 22, PAGE_TOP)
    selectionLabel:SetWidth(SECTIONS_WIDTH)
    selectionLabel:SetJustifyH("LEFT")
    selectionLabel:SetText(L["Import only these sections"])
    local checkboxes = {}
    for _, section in ipairs(importSections) do
        local checkbox = CreateFrame("CheckButton", nil, reviewPage, "UICheckButtonTemplate")
        chrome.SkinCheckbox(checkbox)
        local label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetWidth(SECTIONS_WIDTH - 36)
        label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(true) end
        label:SetText(section.label)
        checkbox.label = label
        -- The preview follows what is ticked.
        checkbox:SetScript("OnClick", function() Options.ImportPreview.Schedule(window) end)
        checkboxes[section.key] = checkbox
    end
    window.previewSelection = Selection
    -- Ticks every section the Blueprint has.
    local selectSections = chrome.CreateStudioButton(reviewPage, L["Select all"], 118, 26)
    selectSections:SetScript("OnClick", function()
        for _, checkbox in pairs(checkboxes) do
            if checkbox:IsShown() then checkbox:SetChecked(true) end
        end
        Options.ImportPreview.Schedule(window)
    end)
    window.selectSections = selectSections
    -- The stage: from PREVIEW_X to the window's right, from the column's heading down to the button row;
    -- its note on general settings under Select all.
    Options.ImportPreview.Attach(window, reviewPage, PREVIEW_X, PAGE_TOP + 4, IMPORT_WIDTH - PREVIEW_X - 22,
        IMPORT_HEIGHT + PAGE_TOP + 4 - PREVIEW_BOTTOM, selectSections, SECTIONS_WIDTH)
    -- The arrow keys step through the preview's designs while Review shows and no edit box has the keyboard;
    -- the window keeps only those (in combat the client keeps the choice it had; Escape always passes on).
    window:SetScript("OnKeyDown", function(frame, key)
        local kept = window.importing and window.importTab == "review" and Options.ImportPreview.Key(window, key) or false
        if frame.SetPropagateKeyboardInput then pcall(frame.SetPropagateKeyboardInput, frame, not kept) end
    end)
    local action = chrome.CreateStudioButton(reviewPage, L["Import selected"], 150, 28, "primary")
    action:SetScript("OnClick", function() Import(window) end)
    action:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 20)

    -- Export: Select all for the code, then Link in chat (PS.BlueprintLink).
    local selectAll = chrome.CreateStudioButton(exportButtons, L["Select all"], 118, 28)
    selectAll:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectAll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 22, 20)
    local hint = exportButtons:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
    hint:SetText(L["Press Ctrl+C to copy"])
    local linkButton = chrome.CreateStudioButton(exportButtons, L["Link in chat"], 130, 28)
    linkButton:SetScript("OnClick", function() PS.BlueprintLink.InsertInChat() end)
    linkButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 20)
    window.linkButton = linkButton

    window.instruction, window.editBox, window.scroll = instruction, editBox, scroll
    window.selectAll, window.selectSections, window.selectionLabel = selectAll, selectSections, selectionLabel
    window.checkboxes, window.hint, window.pasteHint, window.action = checkboxes, hint, pasteHint, action
    Options.blueprintWindow = window
    return window
end

-- The preview built (ImportPreview.Build): Review's tab counts its designs.
function Options.BlueprintPreviewBuilt(window)
    if window and window.tabs then RefreshReview(window) end
end

-- Export shows the share code, which is what people paste (Import still reads Blueprint JSON).
function Options:ShowExportBlueprint()
    local info = {}
    local blueprint, reason = PS.ExportShareCode(info)
    if not blueprint then return Chat.Print(string.format(L["Blueprint export failed: %s"], tostring(reason))) end
    local window = EnsureWindow()
    SetImporting(window, false)
    window.placeholder:Hide()
    window.title:SetText(L["PlateSmith · Export / Share"])
    window.instruction:SetText(L["Copy this share code with Ctrl+C and paste it into Import on another character or client."])
    window.scroll:ClearAllPoints()
    window.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 26, EXPORT_TEXT_TOP)
    window.scroll:SetSize(660, EXPORT_HEIGHT + EXPORT_TEXT_TOP - 70)
    ShowText(window, blueprint)
end

function Options:ShowImportBlueprint()
    local window = EnsureWindow()
    SetImporting(window, true)
    window.previewShowsNow = false
    window.placeholder:Show()
    window.title:SetText(L["PlateSmith · Import Blueprint"])
    -- What Context designs replaces, and what a context design keeps once World's layouts or custom
    -- parts change (Blueprint.lua's Rebase), said exactly.
    window.instruction:SetText(L["Paste a PlateSmith share code or Blueprint JSON, then choose which sections to overwrite. "
        .. "Context designs replaces only the designs listed under the text; your others stay. When World layouts or "
        .. "custom parts change, each context design drops its changes to any group or custom part that is new, gone or "
        .. "different in the World it now sits on; changes to built-in parts stay."])
    for _, checkbox in pairs(window.checkboxes) do checkbox:SetChecked(true); checkbox:Show() end
    window.scroll:ClearAllPoints()
    window.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 26, IMPORT_TEXT_TOP)
    window.scroll:SetSize(IMPORT_WIDTH - 70, IMPORT_TEXT_HEIGHT)
    window.importTab = "paste"
    window.editBox:SetText("")
    Describe(window)
    SelectTab(window, "paste")
    window.editBox:SetHeight(IMPORT_TEXT_HEIGHT)
    window.scroll:SetVerticalScroll(0)
    window:Show()
    window.scrollBar:Sync()
    window.editBox:SetFocus()
end

-- Import with text already in the box (a Blueprint received from a chat link): it opens on Review.
-- Nothing imports until the player presses Import selected.
function Options:ShowImportBlueprintText(text)
    self:ShowImportBlueprint()
    local window = self.blueprintWindow
    window.editBox:SetText(text)
    window.editBox:SetHeight(TextHeight(window, text))
    window.placeholder:Hide()
    Describe(window)
    window.scroll:SetVerticalScroll(0)
    window.scrollBar:Sync()
    SelectTab(window, "review")
    return window
end
