local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local L = PS.L

-- The release What's new window: on the first login after PlateSmith's release changes (the release part of
-- PS.RUNTIME_BUILD, so a build's "+stamp" never counts), a release's highlights (Data/ReleaseNotes.lua) over a dimmed
-- screen: a large title over one card in Studio's panel look (the subtitle, then each section's heading and its
-- gold-dotted items, the reminder at its foot), then Don't show on startup, Open Studio and Close. The last release seen is
-- account state (releaseSeen), recorded at every login whether or not the window shows; a fresh install only records
-- it. Off (releaseNewsOff: the window's box and Settings › Studio › Notices alike), it never shows on login; Settings ›
-- Help › What's new... shows it any time. Never in combat (it waits for combat to end) and never before the loading
-- screen is gone; a failure stays quiet.
local WhatsNew = {}
Options.WhatsNew = WhatsNew

local DELAY = 3
-- The card: width, inner padding, the dot's column, the space between items and between sections.
local CARD = { width = 600, pad = 28, dot = 16, itemGap = 7, sectionGap = 14 }

-- The release part of build (PS.RUNTIME_BUILD by default): "1.4.0" from "1.4.0+20261110.3"; nil when it has none.
function WhatsNew.Release(build)
    local text = build
    if text == nil then text = PS.RUNTIME_BUILD end
    if type(text) ~= "string" then return nil end
    return text:match("^(%d+%.%d+[%.%d]*%d)") or text:match("^(%d+%.%d+)")
end

-- Releases in order: -1, 0 or 1 by their numbers ("1.10.0" after "1.9.2").
function WhatsNew.Compare(a, b)
    local left, right = {}, {}
    for number in tostring(a):gmatch("%d+") do left[#left + 1] = tonumber(number) end
    for number in tostring(b):gmatch("%d+") do right[#right + 1] = tonumber(number) end
    for index = 1, math.max(#left, #right) do
        local x, y = left[index] or 0, right[index] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

-- Release's notes (Data/ReleaseNotes.lua: subtitle and sections), or nil when it has none.
function WhatsNew.Notes(release)
    local notes = PS.ReleaseNotes
    local entry = type(release) == "string" and type(notes) == "table" and notes[release] or nil
    return type(entry) == "table" and type(entry.sections) == "table" and #entry.sections > 0 and entry or nil
end

-- Release's items, every section's in order, or nil when it has none.
function WhatsNew.Lines(release)
    local entry = WhatsNew.Notes(release)
    if not entry then return nil end
    local lines = {}
    for _, section in ipairs(entry.sections) do
        for _, item in ipairs(type(section.items) == "table" and section.items or {}) do lines[#lines + 1] = item end
    end
    return #lines > 0 and lines or nil
end

-- The newest release with notes, not after this one (a release without notes shows the one before it's): nil if none.
function WhatsNew.Latest(release)
    release = release or WhatsNew.Release()
    if not release then return nil end
    if WhatsNew.Lines(release) then return release end
    local best
    for key in pairs(type(PS.ReleaseNotes) == "table" and PS.ReleaseNotes or {}) do
        if WhatsNew.Lines(key) and WhatsNew.Compare(key, release) < 0 and (not best or WhatsNew.Compare(key, best) > 0) then
            best = key
        end
    end
    return best
end

-- Whether the window shows on login: account state (releaseNewsOff), one setting for every profile and character.
function WhatsNew.Enabled()
    local state = PS.GetState and PS.GetState()
    return not (state and state.releaseNewsOff == true)
end
function WhatsNew.SetEnabled(on)
    local state = PS.GetState and PS.GetState()
    if not state then return false end
    state.releaseNewsOff = not on or nil
    local row, dialog = Options.editorReleaseNewsCheckbox, WhatsNew.dialog
    if row and row.Refresh then row:Refresh() end
    if dialog then dialog.hide:SetChecked(not WhatsNew.Enabled()) end
    return true
end

local function Text(parent, size, colour, justify)
    local chrome = Options.studioChrome
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetFont(chrome.FONT, size)
    text:SetTextColor(colour[1], colour[2], colour[3])
    text:SetJustifyH(justify or "CENTER")
    return text
end

local LIGHT, DIM = { 0.93, 0.90, 0.84 }, { 0.70, 0.67, 0.61 }

-- The card's text from a pool: kind "heading" (a section's title) or "item" (a gold dot and its line), reused across
-- shows; every one not used this time is hidden.
local function Pooled(card, kind, index)
    local chrome = Options.studioChrome
    local pool = card.pools[kind]
    local entry = pool[index]
    if entry then return entry end
    if kind == "heading" then
        entry = { text = Text(card, 15, LIGHT, "LEFT") }
    else
        entry = { dot = Text(card, 14, chrome.GOLD, "LEFT"), text = Text(card, 13, chrome.LABEL, "LEFT") }
        entry.dot:SetText("•")
        entry.text:SetWidth(CARD.width - 2 * CARD.pad - CARD.dot)
        if entry.text.SetSpacing then entry.text:SetSpacing(2) end
    end
    pool[index] = entry
    return entry
end

-- Fills the card with entry's sections (a heading each, then its items); returns the card's height.
local function FillCard(card, entry)
    local TextHeight = Options.LookUpdate.TextHeight
    card.subtitle:SetText(entry.subtitle or "")
    local y = CARD.pad + TextHeight(card.subtitle) + 24
    local used = { heading = 0, item = 0 }
    for index, section in ipairs(entry.sections) do
        if index > 1 then y = y + CARD.sectionGap end
        used.heading = used.heading + 1
        local heading = Pooled(card, "heading", used.heading)
        heading.text:SetText(section.title or "")
        heading.text:ClearAllPoints()
        heading.text:SetPoint("TOPLEFT", card, "TOPLEFT", CARD.pad, -y)
        heading.text:Show()
        y = y + TextHeight(heading.text) + 8
        for _, item in ipairs(type(section.items) == "table" and section.items or {}) do
            used.item = used.item + 1
            local line = Pooled(card, "item", used.item)
            line.text:SetText(item)
            line.text:ClearAllPoints()
            line.text:SetPoint("TOPLEFT", card, "TOPLEFT", CARD.pad + CARD.dot, -y)
            line.dot:ClearAllPoints()
            line.dot:SetPoint("TOPLEFT", card, "TOPLEFT", CARD.pad, -y + 1)
            line.text:Show()
            line.dot:Show()
            y = y + TextHeight(line.text) + CARD.itemGap
        end
    end
    for kind, pool in pairs(card.pools) do
        for index = used[kind] + 1, #pool do
            pool[index].text:Hide()
            if pool[index].dot then pool[index].dot:Hide() end
        end
    end
    y = y - CARD.itemGap + 22
    card.again:ClearAllPoints()
    card.again:SetPoint("TOP", card, "TOP", 0, -y)
    return y + TextHeight(card.again) + CARD.pad
end

local function Dialog()
    if WhatsNew.dialog then return WhatsNew.dialog end
    local chrome = Options.studioChrome
    -- The whole screen, dimmed; Escape closes it.
    local dialog = CreateFrame("Frame", "PlateSmithWhatsNewDialog", UIParent)
    dialog:SetAllPoints(UIParent)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:EnableMouse(true)
    local dim = dialog:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(dialog)
    dim:SetColorTexture(0, 0, 0, 0.6)
    dialog.dim = dim
    PS.UI.Window.CloseOnEscape("PlateSmithWhatsNewDialog", dialog)
    local content = CreateFrame("Frame", nil, dialog)
    content:SetPoint("CENTER", dialog, "CENTER", 0, 20)
    content:SetWidth(CARD.width)
    dialog.content = content
    local title = Text(content, 30, chrome.GOLD)
    title:SetPoint("TOP", content, "TOP", 0, 0)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(2, -2)
    dialog.title = title
    local closeX = chrome.CreateCloseButton(content)
    closeX:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 4)
    closeX:SetScript("OnClick", function() dialog:Hide() end)
    PS.UI.Controls.AttachTooltip(closeX, L["Close"], {})
    dialog.closeX = closeX
    -- The one card: Studio's dark panel, the subtitle centred at its top, the sections, the reminder at its foot.
    local card = CreateFrame("Frame", nil, content)
    chrome.DressStudioDialog(card)
    card:SetWidth(CARD.width)
    card.pools = { heading = {}, item = {} }
    card.subtitle = Text(card, 14, LIGHT)
    card.subtitle:SetPoint("TOP", card, "TOP", 0, -CARD.pad)
    card.subtitle:SetWidth(CARD.width - 2 * CARD.pad)
    card.again = Text(card, 13, DIM)
    card.again:SetText(L["Studio › Settings › Help › What's new... shows this again."])
    dialog.card, dialog.subtitle, dialog.again = card, card.subtitle, card.again
    local hide = chrome.KitCheckbox(content, L["Don't show on startup"], function(box)
        WhatsNew.SetEnabled(not box:GetChecked())
    end)
    PS.UI.Controls.AttachTooltip(hide, L["Don't show on startup"], { L["Tick it and this window no longer opens when you "
        .. "log in after PlateSmith updates. Settings › Studio › Notices turns it back on."] })
    dialog.hide = hide
    local open = chrome.CreateStudioButton(content, L["Open Studio"], 170, 32, "primary")
    open:SetScript("OnClick", function()
        dialog:Hide()
        if PS.OpenVisualEditor then PS.OpenVisualEditor() end
    end)
    dialog.open = open
    local close = chrome.CreateStudioButton(content, L["Close"], 170, 32)
    close:SetScript("OnClick", function() dialog:Hide() end)
    dialog.close = close
    dialog:Hide()
    WhatsNew.dialog = dialog
    return dialog
end

-- Lays the window out for release's notes: the title, the card, then the box and the buttons under it.
local function Layout(dialog, entry, studioShown)
    local TextHeight = Options.LookUpdate.TextHeight
    local top = TextHeight(dialog.title) + 18
    local card = dialog.card
    card:SetHeight(math.floor(FillCard(card, entry) + 0.5))
    card:ClearAllPoints()
    card:SetPoint("TOP", dialog.content, "TOP", 0, -top)
    local y = top + card:GetHeight() + 16
    dialog.hide:ClearAllPoints()
    dialog.hide:SetPoint("TOP", dialog.content, "TOP", -78, -y)
    y = y + 36
    dialog.open:SetShown(not studioShown)
    dialog.open:ClearAllPoints()
    dialog.open:SetPoint("TOP", dialog.content, "TOP", -94, -y)
    dialog.close:ClearAllPoints()
    dialog.close:SetPoint("TOP", dialog.content, "TOP", studioShown and 0 or 94, -y)
    dialog.content:SetHeight(y + 32)
end

-- The window for release (by default the newest with notes, WhatsNew.Latest); nil when there are none. Records
-- nothing. Open Studio shows while Studio is closed.
function WhatsNew.Show(release)
    release = release or WhatsNew.Latest()
    local entry = WhatsNew.Notes(release)
    if not entry then return nil end
    local dialog = Dialog()
    dialog.release = release
    dialog.title:SetText(string.format(L["What's new in PlateSmith %s"], release))
    dialog.hide:SetChecked(not WhatsNew.Enabled())
    local editor = Options.editor
    Layout(dialog, entry, editor ~= nil and editor:IsShown() and true or false)
    dialog:Show()
    if dialog.Raise then dialog:Raise() end
    return dialog
end

local events = CreateFrame("Frame")
WhatsNew.events = events
local function Unregister(event)
    if events.UnregisterEvent then pcall(events.UnregisterEvent, events, event) end
end

-- At login (after the loading screen): the window once for a release the player has not seen, newer than the one
-- recorded. Nothing recorded yet: an install that had profiles before (from before 1.4.0) is shown it, a fresh one
-- (Profiles.Load's firstRunDone false) only records. In combat it waits for combat to end, recording nothing.
function WhatsNew.Check()
    local state = PS.GetState and PS.GetState()
    local release = WhatsNew.Release()
    if type(state) ~= "table" or not release or state.releaseSeen == release then return nil end
    local seen = state.releaseSeen
    local notes = WhatsNew.Latest(release)
    local fresh = seen == nil and state.firstRunDone == false
    if fresh or not WhatsNew.Enabled() or not notes or (seen and WhatsNew.Compare(notes, seen) <= 0) then
        state.releaseSeen = release
        return nil
    end
    if PS.Secret.InCombat() then
        WhatsNew.waiting = true
        PS._RegisterEvent(events, "PLAYER_REGEN_ENABLED", "platesmith.whats-new")
        return nil
    end
    local dialog = WhatsNew.Show(notes)
    if dialog then state.releaseSeen = release end
    return dialog
end

-- Check, quietly: an error records nothing and says nothing (the next login tries again).
function WhatsNew.Login()
    local ok, result = pcall(WhatsNew.Check)
    if not ok then
        WhatsNew.failure = result
        return nil
    end
    return result
end

PS._RegisterEvent(events, "PLAYER_ENTERING_WORLD", "platesmith.whats-new")
-- The window covers the screen and takes its clicks: combat starting puts it away, and it comes back when combat ends
-- (WhatsNew.reshow: the release it showed).
PS._RegisterEvent(events, "PLAYER_REGEN_DISABLED", "platesmith.whats-new")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        local dialog = WhatsNew.dialog
        if dialog and dialog:IsShown() then
            WhatsNew.reshow = dialog.release or true
            dialog:Hide()
            PS._RegisterEvent(events, "PLAYER_REGEN_ENABLED", "platesmith.whats-new")
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and WhatsNew.reshow then
        local release = WhatsNew.reshow
        WhatsNew.reshow = nil
        if not WhatsNew.waiting then Unregister("PLAYER_REGEN_ENABLED") end
        WhatsNew.Show(release ~= true and release or nil)
        if not WhatsNew.waiting then return end
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Once a session: the first is the login (or a reload).
        Unregister("PLAYER_ENTERING_WORLD")
        if WhatsNew.started then return end
        WhatsNew.started = true
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(DELAY, WhatsNew.Login)
        else
            WhatsNew.Login()
        end
    elseif event == "PLAYER_REGEN_ENABLED" and WhatsNew.waiting then
        WhatsNew.waiting = nil
        Unregister("PLAYER_REGEN_ENABLED")
        WhatsNew.Login()
    end
end)
