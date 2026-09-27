local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local L = PS.L

-- The Blueprint Export / Share and Import window opened from Blueprint Studio.
local importSections = {
    { key = "settings", label = L["General settings"] },
    { key = "layouts", label = L["World layouts"] },
    { key = "dungeonFriendly", label = L["Dungeon friendly names"] },
    { key = "styles", label = L["Plate sizes & bar styles"] },
    { key = "values", label = L["Custom values & power"] },
    { key = "dungeon", label = L["Dungeon enemy profile"] },
    { key = "other", label = L["Companion-addon data"] },
}

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
    local selection = {}
    for _, section in ipairs(importSections) do
        selection[section.key] = window.checkboxes[section.key]:GetChecked() and true or false
    end
    local ok, reason, otherFlavor = PS.ImportBlueprint(window.editBox:GetText(), selection)
    if ok then
        Options:Refresh(true)
        window:Hide()
        Chat.Print(L["Selected Blueprint sections imported. Press Save to keep them."])
        if otherFlavor then
            Chat.Print(string.format(L["This Blueprint was made on the %s client; some options may look different here."], otherFlavor))
        end
    else
        Chat.Print(string.format(L["Blueprint import failed: %s"], tostring(reason or L["invalid data"])))
    end
end

local function EnsureWindow()
    if Options.blueprintWindow then return Options.blueprintWindow end
    local window = Window.Create("PlateSmithBlueprintWindow", {
        width = 730, height = 540, title = "", titleFont = "GameFontNormalLarge",
        border = Window.colours.studio, background = { 0.025, 0.03, 0.035, 0.98 },
    })
    local chrome = Options.studioChrome
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
        scrollBar:Sync()
    end)
    editBox:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        local offset, view = scroll:GetVerticalScroll() or 0, scroll:GetHeight()
        local top, line = -(y or 0), lineHeight or 16
        if top < offset then scroll:SetVerticalScroll(top)
        elseif top + line > offset + view then scroll:SetVerticalScroll(top + line - view) end
        scrollBar:Sync()
    end)
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 26, -86)
    editBox:SetWidth(640)
    inset:SetPoint("TOPLEFT", scroll, "TOPLEFT", -10, 10)
    inset:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 30, -10)
    window.inset = inset

    local selectionLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectionLabel:SetFont(chrome.FONT, 15)
    selectionLabel:SetTextColor(chrome.GOLD[1], chrome.GOLD[2], chrome.GOLD[3])
    selectionLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -348)
    selectionLabel:SetText(L["Import only these sections"])
    local checkboxes = {}
    for index, section in ipairs(importSections) do
        local checkbox = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        chrome.SkinCheckbox(checkbox)
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        checkbox:SetPoint("TOPLEFT", window, "TOPLEFT", 18 + column * 345, -370 - row * 28)
        local label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetText(section.label)
        checkboxes[section.key] = checkbox
    end

    local selectAll = chrome.CreateStudioButton(window, L["Select all"], 118, 28)
    selectAll:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectAll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 22, 20)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
    local formatToggle = chrome.CreateStudioButton(window, "", 170, 28)
    formatToggle:SetScript("OnClick", function() Options:ShowExportBlueprint(not window.showingJson) end)
    formatToggle:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 20)
    local action = chrome.CreateStudioButton(window, L["Import selected"], 150, 28, "primary")
    action:SetScript("OnClick", function() Import(window) end)
    action:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 20)

    window.instruction, window.editBox, window.scroll = instruction, editBox, scroll
    window.selectAll, window.selectionLabel, window.checkboxes = selectAll, selectionLabel, checkboxes
    window.hint, window.action, window.formatToggle = hint, action, formatToggle
    Options.blueprintWindow = window
    return window
end

-- The share code is what people paste; the JSON view is for reading and diagnosing.
function Options:ShowExportBlueprint(showJson)
    local blueprint, reason
    if showJson then blueprint, reason = PS.ExportBlueprint(true) else blueprint, reason = PS.ExportShareCode() end
    if not blueprint then return Chat.Print(string.format(L["Blueprint export failed: %s"], tostring(reason))) end
    local window = EnsureWindow()
    window.importing = false
    window.placeholder:Hide()
    window.showingJson = showJson and true or false
    window.title:SetText(L["PlateSmith · Export / Share"])
    window.instruction:SetText(showJson
        and L["Readable Blueprint JSON. It imports as-is, but the share code is easier to paste in chat."]
        or L["Copy this share code with Ctrl+C and paste it into Import on another character or client."])
    window.selectionLabel:Hide()
    for _, checkbox in pairs(window.checkboxes) do checkbox:Hide() end
    window.action:Hide()
    window.formatToggle.label:SetText(showJson and L["Show share code"] or L["Show readable JSON"])
    window.scroll:SetSize(660, 540 - 86 - 70)
    window.formatToggle:Show()
    window.hint:SetText(L["Press Ctrl+C to copy"])
    ShowText(window, blueprint)
end

function Options:ShowImportBlueprint()
    local window = EnsureWindow()
    window.importing = true
    window.placeholder:Show()
    window.title:SetText(L["PlateSmith · Import Blueprint"])
    window.instruction:SetText(L["Paste a PlateSmith share code or Blueprint JSON, then choose exactly which sections to overwrite."])
    window.selectionLabel:Show()
    for _, checkbox in pairs(window.checkboxes) do checkbox:SetChecked(true); checkbox:Show() end
    window.formatToggle:Hide()
    window.action:Show()
    window.hint:SetText(L["Press Ctrl+V to paste"])
    window.scroll:SetSize(660, 240)
    window.editBox:SetText("")
    window.editBox:SetHeight(240)
    window.scroll:SetVerticalScroll(0)
    window:Show()
    window.scrollBar:Sync()
    window.editBox:SetFocus()
end
