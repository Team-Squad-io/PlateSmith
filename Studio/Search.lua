local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")
local Theme = assert(PS.StudioTheme, "PlateSmith StudioTheme missing")
local Layout = assert(PS.UI and PS.UI.Layout, "PlateSmith Layout missing")

-- The search box over Settings' categories: it finds a setting on any of Studio's Settings pages,
-- on PlateSmith's pages in Blizzard's Settings panel, or a part in the Studio tree. The settings
-- index is built the first time the box takes focus, a page at a time within a small time budget
-- (the rest on the ticker); parts are listed as each search runs, since plate types differ.
-- Typing (after a short pause) shows a results page in Settings' content area, as Blizzard's own
-- Settings search does: the matching rows themselves, lent from their pages and grouped under
-- "Page › Section" headings, so a setting changes right there. Clearing lends them back.
local Search = {}
Options.settingsSearch = Search

local MAX_RESULTS, MAX_ELSEWHERE, BUDGET_MS, REVEAL_MARGIN, DEBOUNCE = 30, 8, 4, 40, 0.15
local FLASH = { seconds = 1.2, alpha = 0.3 }
local INDEX_TICKER, FLASH_TICKER = "studio.search.index", "studio.search.flash"
local DEBOUNCE_TICKER = "studio.search.debounce"
-- Points for a query word that starts a word of the label (more for the whole word, and for the
-- label's first word), of a checkbox's own text, of the page or section, or of the help.
local SCORE = { label = 10, whole = 2, first = 3, extra = 8, path = 5, help = 2, labelPrefix = 15 }
Search.SCORE, Search.MAX_RESULTS = SCORE, MAX_RESULTS

local index = { entries = {}, queue = nil, done = false }
Search._index = index

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

-- Plain text: no colour codes or inline textures.
local function Plain(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- Lowercase words: runs of anything but spaces and punctuation, so accented letters stay in a word.
local function Words(text)
    local words = {}
    for word in Plain(text):lower():gmatch("[^%s%p]+") do words[#words + 1] = word end
    return words
end
Search.Words = Words

-- The best points any word in words earns for the query word, 0 when none starts with it.
local function Best(words, query, points, firstBonus)
    local best = 0
    for position, word in ipairs(words) do
        if word:sub(1, #query) == query then
            local score = points + (word == query and SCORE.whole or 0) + (position == 1 and firstBonus or 0)
            if score > best then best = score end
        end
    end
    return best
end

-- An entry's score for the query's words: every word must start a word somewhere, else nil.
function Search.Score(entry, queryWords, queryText)
    if #queryWords == 0 then return nil end
    local total = 0
    for _, query in ipairs(queryWords) do
        local score = math.max(Best(entry.labelWords, query, SCORE.label, SCORE.first),
            Best(entry.extraWords, query, SCORE.extra, 0), Best(entry.pathWords, query, SCORE.path, 0),
            Best(entry.helpWords, query, SCORE.help, 0))
        if score == 0 then return nil end
        total = total + score
    end
    if queryText and queryText ~= "" and entry.lowerLabel:sub(1, #queryText) == queryText then
        total = total + SCORE.labelPrefix
    end
    return total
end

-- entry: label, extra, help, and path (the category and section, shown under the label).
local function Prepare(entry)
    entry.label = Plain(entry.label)
    entry.lowerLabel = entry.label:lower()
    entry.labelWords, entry.extraWords = Words(entry.label), Words(entry.extra)
    entry.pathWords, entry.helpWords = Words(entry.path), Words(entry.help)
    entry.order = entry.order or #index.entries + 1
    return entry
end
Search.Prepare = Prepare

local function Path(...)
    local parts = {}
    for position = 1, select("#", ...) do
        local part = select(position, ...)
        if type(part) == "string" and part ~= "" then parts[#parts + 1] = Plain(part) end
    end
    return table.concat(parts, " › ")
end

-- One page's entries into the index. place: "studio" (a Settings category) or "blizzard".
local function IndexPage(root, place, fields)
    for _, found in ipairs(Layout.SearchEntries(root)) do
        local section = found.section
        local sectionTitle = section and section ~= found.frame and section.kitSearchTitle or nil
        local entry = { place = place, frame = found.frame, section = section, item = found.item, label = found.label,
            extra = found.extra, help = found.help, sectionTitle = sectionTitle,
            path = Path(fields.pagePath, fields.pageLabel, sectionTitle) }
        for key, value in pairs(fields) do if entry[key] == nil then entry[key] = value end end
        index.entries[#index.entries + 1] = Prepare(entry)
    end
end

-- The index's sources, one per page: Studio's Settings pages, then PlateSmith's Blizzard pages.
-- Studio builds a Settings page the first time it is wanted, so a source builds its page (one a
-- step, within the budget) before reading its rows.
local function Sources()
    local sources = {}
    for _, key in ipairs(Options.editorSettingsPageOrder or {}) do
        sources[#sources + 1] = function()
            local panel = Options:EditorSettingsPage(key)
            if not panel then return end
            local info = Options:SettingsCategoryInfo(key)
            IndexPage(panel, "studio", { category = key, panel = panel, pageLabel = info and info.label or key })
        end
    end
    local blizzard = {
        { Options.panel, Options.category, "PlateSmith" },
        { Options.threatPanel, Options.moduleSettings and Options.moduleSettings.threat, L["Threat"] },
        { Options.profilesPanel, Options.moduleSettings and Options.moduleSettings.profiles, L["Profiles"] },
    }
    for _, spec in ipairs(blizzard) do
        local page, category, title = spec[1], spec[2], spec[3]
        if page and page.settingsFlow then
            sources[#sources + 1] = function()
                IndexPage(page.settingsFlow, "blizzard", { page = page, categoryObject = category,
                    pagePath = L["Settings"], pageLabel = title })
            end
        end
    end
    return sources
end

-- Indexes pages until budgetMs has gone (all of them without a clock); true once all are done.
function Search.Step(budgetMs)
    if index.done then return true end
    if not index.queue then index.queue = Sources() end
    local started = Clock()
    while #index.queue > 0 do
        table.remove(index.queue, 1)()
        local now = Clock()
        if started and now and now - started >= (budgetMs or BUDGET_MS) then break end
    end
    index.done = #index.queue == 0
    return index.done
end

-- The first focus starts the index: what fits the budget now, the rest a page a frame.
function Search.Begin()
    if index.done then return true end
    if Search.Step(BUDGET_MS) then return true end
    PS.Ticker.SetEnabled(INDEX_TICKER, true)
    return false
end

PS.Ticker.Register(INDEX_TICKER, 0, function()
    if Search.Step(BUDGET_MS) then
        PS.Ticker.SetEnabled(INDEX_TICKER, false)
        -- Results shown from part of the index run again over all of it.
        if Search.IsActive() then Search.Update() end
    end
end)
PS.Ticker.SetEnabled(INDEX_TICKER, false)

-- Settings built again (a test, or a rebuild): the index starts over on the next focus.
function Search.Reset()
    Search.Close()
    index.entries, index.queue, index.done = {}, nil, false
    PS.Ticker.SetEnabled(INDEX_TICKER, false)
end

-- The parts this plate type's tree lists, as entries (built for each search: plate types differ),
-- each one's Display rows (Font, Font size, Font style, Shadow; an aura row's Timed only and Text
-- position too) as "Part › Display" rows, and
-- Blizzard's name rows on Dungeon › Players.
local function PartEntries()
    local entries, settings = {}, PS.GetSettings and PS.GetSettings()
    local order = #index.entries
    for key in pairs(Options.editorLayout or {}) do
        if not key:match("^group%.%d+$") and Options:IsEditorComponentRelevant(key, settings) then
            order = order + 1
            local label = Options:EditorComponentLabel(key)
            entries[#entries + 1] = Prepare({ place = "part", key = key, label = label,
                path = L["Part in the Studio tree"], order = order })
            for _, row in ipairs(Options.EditorDisplayRows and Options:EditorDisplayRows(key) or {}) do
                order = order + 1
                entries[#entries + 1] = Prepare({ place = "partRow", key = key, label = row.label, frame = row.frame,
                    section = row.section, partLabel = label, path = Path(label, L["Display"]), order = order })
            end
        end
    end
    -- Blizzard's name rows on Dungeon › Players (names only, class colours, its font) while another
    -- view is open. With the overlay test on, that tab shows the overlay's parts instead.
    if not Options:IsEditorBlizzardNames(settings) and not (settings and settings.experimentalDungeonFriendlyText == true)
        and Options.EditorDungeonNameRows then
        local partLabel = L["Name (drawn by Blizzard)"]
        for _, row in ipairs(Options:EditorDungeonNameRows()) do
            order = order + 1
            entries[#entries + 1] = Prepare({ place = "dungeonNameRow", key = "name", label = row.label, partLabel = partLabel,
                path = Path(L["Dungeon"], L["Players"], partLabel, L["Display"]), order = order })
        end
    end
    return entries
end

-- Whether an entry can be shown now: its category is listed, and its row was not hidden by its
-- page (a folded section's rows still count).
local function Available(entry, categories)
    if entry.place == "part" or entry.place == "partRow" or entry.place == "dungeonNameRow" then return true end
    if entry.place == "studio" and not categories[entry.category] then return false end
    local frame, kit = entry.frame, entry.place == "studio" and Options.settingsKit or entry.page and entry.page.settingsKit
    if frame.IsShown and not frame:IsShown() then
        local section = entry.section
        local folded = section and section ~= frame and kit and kit.IsFolded(section.foldKey)
        if not folded then return false end
    end
    return true
end

-- The best matches for text, at most limit (default MAX_RESULTS), best first.
function Search.Query(text, limit)
    local queryWords = Words(text)
    if #queryWords == 0 then return {} end
    local queryText = table.concat(queryWords, " ")
    local categories = {}
    for _, category in ipairs(Options:SettingsCategoryList()) do categories[category.key] = true end
    local found = {}
    local function Consider(entry)
        if not Available(entry, categories) then return end
        local score = Search.Score(entry, queryWords, queryText)
        if score then found[#found + 1] = { entry = entry, score = score } end
    end
    for _, entry in ipairs(index.entries) do Consider(entry) end
    for _, entry in ipairs(PartEntries()) do Consider(entry) end
    table.sort(found, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if #a.entry.label ~= #b.entry.label then return #a.entry.label < #b.entry.label end
        if a.entry.label ~= b.entry.label then return a.entry.label < b.entry.label end
        return a.entry.order < b.entry.order
    end)
    local results = {}
    for position = 1, math.min(limit or MAX_RESULTS, #found) do results[position] = found[position].entry end
    return results
end

-- A frame's distance below stop, following its TOPLEFT anchors (the kit places every flow item by
-- its TOPLEFT), else from the two frames' tops; nil when neither says.
local function OffsetIn(frame, stop)
    local y, node = 0, frame
    for _ = 1, 32 do
        if node == stop then return y end
        local nextNode
        for position = 1, node.GetNumPoints and node:GetNumPoints() or 0 do
            local point, relative, _, _, dy = node:GetPoint(position)
            if point == "TOPLEFT" and relative then
                y, nextNode = y - (tonumber(dy) or 0), relative
                break
            end
        end
        if not nextNode then break end
        node = nextNode
    end
    local top, stopTop = frame.GetTop and frame:GetTop(), stop.GetTop and stop:GetTop()
    if type(top) == "number" and type(stopTop) == "number" then return stopTop - top end
    return nil
end
Search.OffsetIn = OffsetIn

-- The found row's brief flash: a soft gold fill that fades, one ticker entry while it runs.
local flash = { started = nil }
Search._flash = flash
local function Flash(frame)
    if not frame or not frame.CreateTexture then return end
    if flash.texture and flash.texture ~= frame.kitSearchFlash then flash.texture:Hide() end
    local texture = frame.kitSearchFlash
    if not texture then
        texture = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        texture:SetAllPoints(frame)
        texture:SetColorTexture(chrome.GOLD[1], chrome.GOLD[2], chrome.GOLD[3], 1)
        frame.kitSearchFlash = texture
    end
    texture:SetAlpha(FLASH.alpha)
    texture:Show()
    flash.texture, flash.frame, flash.started = texture, frame, type(GetTime) == "function" and GetTime() or 0
    PS.Ticker.SetEnabled(FLASH_TICKER, true)
end
Search.Flash = Flash

PS.Ticker.Register(FLASH_TICKER, 0.03, function(_, now)
    local texture = flash.texture
    local age = (now or 0) - (flash.started or 0)
    if not texture or age >= FLASH.seconds or not flash.frame:IsVisible() then
        if texture then texture:Hide() end
        flash.texture, flash.frame = nil, nil
        PS.Ticker.SetEnabled(FLASH_TICKER, false)
        return
    end
    -- Two soft pulses, fading out.
    local fade = 1 - age / FLASH.seconds
    texture:SetAlpha(FLASH.alpha * fade * (0.6 + 0.4 * math.cos(age * 2 * math.pi * 2 / FLASH.seconds)))
end)
PS.Ticker.SetEnabled(FLASH_TICKER, false)

-- Opens a section that is folded (its kit relays the page out).
local function Unfold(kit, section)
    if kit and section and section.foldKey and kit.IsFolded(section.foldKey) then
        kit.SetFolded(section.foldKey, false)
        if section.RefreshHeader then section:RefreshHeader() end
    end
end

local function RevealStudioSetting(entry)
    Options:SetEditorInspectorPage(entry.category)
    Options:SetSettingsCategory(entry.category)
    Unfold(Options.settingsKit, entry.section)
    Options:LayoutEditorSettingsPanels()
    local target = entry.frame
    if target.IsShown and not target:IsShown() and entry.section then target = entry.section end
    local offset = OffsetIn(target, Options.editorSettingsContent)
    local bar = Options.editorSettingsScrollBar
    if offset and bar and bar.ScrollToOffset then bar:ScrollToOffset(math.max(0, offset - REVEAL_MARGIN)) end
    Flash(target)
end

-- Blizzard's Settings panel sits under Studio and is protected in combat: Studio closes (asking
-- about unsaved changes, as its close button does) and the page opens at the setting.
local function RevealBlizzardSetting(entry)
    if PS.Secret.InCombat() then
        PS.Chat.Print(L["Blizzard's Settings panel opens only out of combat."])
        return false
    end
    if Options.editor then Options.editor:Hide() end
    if PS.OpenOptions then PS.OpenOptions() end
    local category = entry.categoryObject
    if category and category ~= Options.category and Settings and Settings.OpenToCategory and category.GetID then
        pcall(Settings.OpenToCategory, category:GetID())
    end
    local page = entry.page
    Unfold(page.settingsKit, entry.section)
    if page.Relayout then page:Relayout() end
    local scroll = page.settingsScroll
    local offset = OffsetIn(entry.frame, page.settingsFlow)
    if offset then offset = offset + (Options.settingsPageMetrics and Options.settingsPageMetrics.top or 0) end
    if scroll and offset then
        local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(math.max(0, math.min(type(range) == "number" and range or 0, offset - REVEAL_MARGIN)))
    end
    Flash(entry.frame)
    return true
end

local function RevealPart(entry)
    Options:SetEditorInspectorPage("components")
    local tree = Options.editorSearchField
    if tree and tree:GetText() ~= "" then tree:SetText("") end
    Options:SelectEditorComponent(entry.key)
    Options:RefreshEditorComponentList(PS.GetSettings(), entry.key)
    Flash(Options.editorComponentButtons and Options.editorComponentButtons[entry.key])
end

-- A part's Display row: the part selected, its section unfolded, the inspector scrolled to the row.
-- A row listed before its part's rows were built is found once selecting the part has built them.
local function RevealPartRow(entry)
    RevealPart(entry)
    local frame, section = entry.frame, entry.section
    if not frame then
        for _, row in ipairs(Options:EditorDisplayRows(entry.key) or {}) do
            if row.label == entry.label and row.frame then frame, section = row.frame, row.section end
        end
    end
    if not frame then return end
    Unfold(Options.inspectorKit, section)
    Options:LayoutEditorInspector()
    local offset = OffsetIn(frame, Options.editorComponentContent)
    local bar = Options.editorComponentScrollBar
    if offset and bar and bar.ScrollToOffset then bar:ScrollToOffset(math.max(0, offset - REVEAL_MARGIN)) end
    Flash(frame)
end

-- A row of Blizzard's name on Dungeon › Players: Studio opens that tab, then the row as a part's.
local function RevealDungeonNameRow(entry)
    Options:SetEditorContext("dungeon")
    Options:SetEditorProfile("friendlyPlayer")
    RevealPartRow({ key = entry.key, label = entry.label })
end

-- Goes to a result: its category, section unfolded, scrolled to and flashed.
function Search.Pick(entry)
    if not entry then return false end
    Search.Clear()
    if entry.place == "part" then
        RevealPart(entry)
    elseif entry.place == "partRow" then
        RevealPartRow(entry)
    elseif entry.place == "dungeonNameRow" then
        RevealDungeonNameRow(entry)
    elseif entry.place == "blizzard" then
        return RevealBlizzardSetting(entry)
    else
        RevealStudioSetting(entry)
    end
    return true
end

-- The results page. Studio's matches are the rows themselves: each is reparented into a heading's
-- group on this page and put back (parent, then its page laid out again) when the results close.
-- Their pages keep them in their flows meanwhile and are not laid out while results show, so
-- nothing is copied and a change here is the same control's. Matches on Blizzard's pages and
-- parts cannot move in, so they are lines at the end that go to them.
local results = { active = false, moved = {}, pages = {}, groups = {}, lines = {}, found = {} }
Search._results = results

function Search.IsActive() return results.active end
-- Showing results, or about to (a pause in typing has not run the search yet).
function Search.IsBusy() return results.active or PS.Ticker.IsEnabled(DEBOUNCE_TICKER) end

-- A heading as a section's title band, without the fold: title, then the rule under it.
local function Heading(kit, parent)
    local frame = CreateFrame("Frame", nil, parent)
    local band = kit.SECTION_TITLE_H
    frame:SetSize(kit.WIDTH, band + kit.SECTION_RULE_GAP + kit.RULE_H)
    frame.flowBefore, frame.flowAfter = kit.SECTION_TOP, kit.SECTION_TITLE_GAP
    frame.text = kit.Text(frame, "", "title")
    frame.text:SetFont(kit.FONT_PATH, kit.TITLE_FONT or kit.FONT)
    frame.text:SetPoint("LEFT", frame, "TOPLEFT", 0, -math.floor(band / 2))
    frame.text:SetPoint("RIGHT", frame, "TOPRIGHT", 0, -math.floor(band / 2))
    if frame.text.SetWordWrap then frame.text:SetWordWrap(false) end
    frame.rule = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    frame.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(band + kit.SECTION_RULE_GAP))
    frame.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(band + kit.SECTION_RULE_GAP))
    function frame:Measure()
        Layout.Hairline(self.rule, kit.RULE_H)
        local colour = kit.Palette().divider
        self.rule:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1)
        kit.Ink(self.text, "title")
        return self:GetHeight()
    end
    return frame
end

-- A pooled group: a heading over one section's matches (or all its rows, when the section matched),
-- and a blocker over them while that section blocks its rows (Stacking while unmanaged).
local function Group(position)
    local group = results.groups[position]
    if group then return group end
    local kit, page = Options.settingsKit, results.page
    group = kit.Group(page.columns)
    group.heading = Heading(kit, group)
    group.blocker = CreateFrame("Frame", nil, group)
    group.blocker:EnableMouse(true)
    group.blocker:SetPoint("TOPLEFT", group.heading, "BOTTOMLEFT", 0, 0)
    group.blocker:SetPoint("BOTTOMRIGHT", group, "BOTTOMRIGHT", 0, 0)
    group.blocker:Hide()
    group:Hide()
    results.groups[position] = group
    return group
end

-- A line that goes to a match elsewhere (a Blizzard page's setting, a part in the tree).
local function Line(position)
    local line = results.lines[position]
    if line then return line end
    local kit, holder = Options.settingsKit, results.page.elsewhere
    line = CreateFrame("Button", nil, holder)
    line:SetSize(kit.WIDTH, kit.ROW_H)
    line.hover = line:CreateTexture(nil, "BACKGROUND")
    line.hover:SetAllPoints(line)
    line.hover:SetColorTexture(1, 0.9, 0.6, 0.08)
    line.hover:Hide()
    line.text = kit.Text(line, "", "sub")
    line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.text:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    if line.text.SetWordWrap then line.text:SetWordWrap(false) end
    line:SetScript("OnEnter", function(instance)
        instance.hover:Show()
        kit.Ink(instance.text, "value")
    end)
    line:SetScript("OnLeave", function(instance)
        instance.hover:Hide()
        kit.Ink(instance.text, "sub")
    end)
    line:SetScript("OnClick", function(instance) Search.Pick(instance.entry) end)
    line:Hide()
    results.lines[position] = line
    return line
end

local function LineText(entry)
    if entry.place == "part" then return string.format(L["Select part in Studio › %s"], entry.label) end
    if entry.place == "partRow" then
        return string.format(L["Select part in Studio › %s"], Path(entry.partLabel, L["Display"], entry.label))
    end
    if entry.place == "dungeonNameRow" then
        return string.format(L["Select part in Studio › %s"], Path(entry.path, entry.label))
    end
    return string.format(L["Open in Blizzard Settings › %s"], Path(entry.pageLabel, entry.sectionTitle, entry.label))
end

-- The page itself: the groups in Settings' columns, the lines for elsewhere, or the no-match text.
local function BuildResultsPage()
    local kit, content = Options.settingsKit, Options.editorSettingsContent
    if results.page or not kit or not content then return results.page end
    local page = kit.Flow(CreateFrame("Frame", nil, content))
    page:SetSize(kit.WIDTH, 1)
    results.page = page
    page.columns = kit.Add(page, kit.Columns(page, { minColumnWidth = 360, divider = true }))
    page.elsewhere = kit.Add(page, kit.Group(page))
    page.elsewhere.heading = Heading(kit, page.elsewhere)
    page.elsewhere.heading.text:SetText(L["Elsewhere"])
    page.empty = kit.Add(page, kit.Help(page, L["No settings match."]), function() return #results.found == 0 end)
    function page:Relayout(width)
        if width and width > 0 then self:SetWidth(width) end
        local height = kit.LayoutFlow(self, 0)
        self:SetHeight(math.max(1, height))
        return height
    end
    page:Hide()
    return page
end

-- Lends frame to group, remembering where it came from.
local function Lend(frame, group)
    results.moved[#results.moved + 1] = { frame = frame, parent = frame:GetParent() }
    frame:SetParent(group)
end

-- Every lent row back with its parent, and each page it came from laid out again as before.
local function Restore()
    for position = #results.moved, 1, -1 do
        local record = results.moved[position]
        record.frame:SetParent(record.parent)
    end
    results.moved = {}
    local viewport = Options.editorSettingsViewport
    local width = viewport and viewport:GetWidth()
    for panel in pairs(results.pages) do
        if panel.Relayout then panel:Relayout(width) end
    end
    results.pages = {}
    local page = results.page
    if not page then return end
    page.columns.flowItems = {}
    for _, group in ipairs(results.groups) do
        group.flowItems, group.source = {}, nil
        group:Hide()
    end
end

-- Lends the Studio matches to groups (one per section, in the order of its best match; a matched
-- section brings all its rows, its rows in their page's order) and lists the rest as lines.
local function Place(found)
    local page = results.page
    local groups, bySource, whole, elsewhere = {}, {}, {}, {}
    for _, entry in ipairs(found) do
        if entry.place == "studio" and entry.section and entry.frame == entry.section then whole[entry.section] = true end
    end
    for _, entry in ipairs(found) do
        if entry.place ~= "studio" then
            if #elsewhere < MAX_ELSEWHERE then elsewhere[#elsewhere + 1] = entry end
        else
            local source = entry.section or entry.panel
            local record = bySource[source]
            if not record then
                record = { source = source, section = entry.section, panel = entry.panel, entries = {},
                    heading = Path(entry.pageLabel, entry.section and entry.section.kitSearchTitle) }
                bySource[source] = record
                groups[#groups + 1] = record
            end
            if not whole[source] or entry.frame == source then record.entries[#record.entries + 1] = entry end
        end
    end
    for position, record in ipairs(groups) do
        local group = Group(position)
        group.heading.text:SetText(record.heading)
        local items = { { frame = group.heading } }
        if whole[record.source] then
            for _, item in ipairs(record.section.flowItems) do
                items[#items + 1] = item
                Lend(item.frame, group)
            end
        else
            table.sort(record.entries, function(a, b) return a.order < b.order end)
            for _, entry in ipairs(record.entries) do
                items[#items + 1] = entry.item
                Lend(entry.frame, group)
            end
        end
        group.flowItems, group.source = items, record.section
        page.columns.flowItems[position] = { frame = group }
        results.pages[record.panel] = true
    end
    local holder = page.elsewhere
    holder.flowItems = #elsewhere > 0 and { { frame = holder.heading } } or {}
    for position, line in ipairs(results.lines) do line:SetShown(elsewhere[position] ~= nil) end
    for position, entry in ipairs(elsewhere) do
        local line = Line(position)
        line.entry = entry
        line.text:SetText(LineText(entry))
        holder.flowItems[#holder.flowItems + 1] = { frame = line }
    end
end

-- Chrome's LayoutEditorSettingsPanels while results show: the page at width (shown with Settings).
-- A group follows its section's blocker and dimmed title (they change with the settings).
function Search.LayoutResults(width, shown)
    local page = results.page
    if not page then return 0 end
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", Options.editorSettingsContent, "TOPLEFT", 0, 0)
    page:SetShown(shown and results.active)
    if not results.active then return 0 end
    for _, group in ipairs(results.groups) do
        local source = group.source
        local blocked = source ~= nil and source.stackingDimmed == true
        group.blocker:SetFrameLevel(group:GetFrameLevel() + 60)
        group.blocker:SetShown(blocked)
        group.heading:SetAlpha(blocked and source.band and source.band:GetAlpha() or 1)
    end
    return page:Relayout(width)
end

local function SetHeading()
    local title, summary = Options.editorSettingsTitle, Options.editorSettingsSummary
    if title then title:SetText(L["Search results"]) end
    if summary then summary:SetText(string.format(L["Settings that match \"%s\"."], results.text or "")) end
    if Options.editorSettingsHelp then Options.editorSettingsHelp:Hide() end
end

-- Runs the search for the box's text and shows the results page (the page closes when it is empty).
function Search.Update()
    PS.Ticker.SetEnabled(DEBOUNCE_TICKER, false)
    local box = Options.editorSettingsSearch
    if not box then return end
    local text = box:GetText() or ""
    box.hint:SetShown(text == "")
    box.clear:SetShown(text ~= "")
    if not text:find("%S") or not BuildResultsPage() then
        Search.Close()
        return
    end
    Search.Begin()
    local viewport = Options.editorSettingsViewport
    if not results.active then
        results.scroll = viewport and viewport.GetVerticalScroll and viewport:GetVerticalScroll() or 0
    end
    Restore()
    results.found = Search.Query(text, MAX_RESULTS)
    results.active, results.text = true, text
    Place(results.found)
    if viewport and viewport.SetVerticalScroll then viewport:SetVerticalScroll(0) end
    SetHeading()
    Options:LayoutEditorSettingsPanels()
end

-- The rows go back to their pages, and the category shows again where it was scrolled to.
function Search.Close()
    PS.Ticker.SetEnabled(DEBOUNCE_TICKER, false)
    if not results.active then return end
    Restore()
    results.active, results.found = false, {}
    if results.page then results.page:Hide() end
    Options:SetSettingsCategory(Options.editorSettingsCategory or "plate")
    local viewport = Options.editorSettingsViewport
    if viewport and viewport.SetVerticalScroll then viewport:SetVerticalScroll(results.scroll or 0) end
    if Options.editorSettingsScrollBar then Options.editorSettingsScrollBar:Sync() end
end

-- Escape, the box's x, or a category: the box empties and lets go; the results close.
function Search.Clear()
    local box = Options.editorSettingsSearch
    if not box then return end
    if box:GetText() ~= "" then box:SetText("") end
    box.hint:Show()
    box.clear:Hide()
    box:ClearFocus()
    Search.Close()
end

-- A pause in typing runs the search (each key starts the wait again); an emptied box closes at once.
PS.Ticker.Register(DEBOUNCE_TICKER, DEBOUNCE, function() Search.Update() end)
PS.Ticker.SetEnabled(DEBOUNCE_TICKER, false)

function Search.TextChanged()
    local box = Options.editorSettingsSearch
    local text = box:GetText() or ""
    box.hint:SetShown(text == "")
    box.clear:SetShown(text ~= "")
    if text:find("%S") then
        PS.Ticker.SetEnabled(DEBOUNCE_TICKER, true)
    else
        Search.Close()
    end
end

-- The box in Settings' categories panel (Chrome's LayoutEditorSettingsPage places it); its results
-- page is built with Settings' pages, in their content area.
function Options:BuildSettingsSearch(panel)
    local box = CreateFrame("EditBox", "PlateSmithEditorSettingsSearch", panel)
    box:SetAutoFocus(false)
    box:SetFont(chrome.FONT, 14, "")
    box:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    box:SetTextInsets(38, 30, 0, 0)
    if box.SetMaxLetters then box:SetMaxLetters(60) end
    box.field = Theme.ThreeSlice(box, "search-field", nil)
    self.editorKitFields = self.editorKitFields or {}
    self.editorKitFields[#self.editorKitFields + 1] = box.field
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box:SetScript("OnSizeChanged", function(instance)
        instance.field:Layout()
        Theme.Place(instance.icon, "search-icon-normal", instance, 8, 5)
    end)
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetFont(chrome.FONT, 14)
    hint:SetPoint("LEFT", box, "LEFT", 38, 0)
    hint:SetText(L["Search settings..."])
    box.hint = hint
    -- Blizzard's search boxes' clear button.
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", box, "RIGHT", -9, 0)
    clear.icon = clear:CreateTexture(nil, "ARTWORK")
    clear.icon:SetAllPoints(clear)
    clear.icon:SetTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clear.icon:SetAlpha(0.6)
    clear:SetScript("OnEnter", function(instance) instance.icon:SetAlpha(1) end)
    clear:SetScript("OnLeave", function(instance) instance.icon:SetAlpha(0.6) end)
    clear:SetScript("OnClick", function() Search.Clear() end)
    clear:Hide()
    box.clear = clear
    PS.UI.Controls.AttachTooltip(box, L["Search settings"], { L["Shows the matching settings here, ready to change. "
        .. "Matches on PlateSmith's pages in Blizzard's Settings and parts in the Studio tree are listed at the end. "
        .. "Escape clears."] })
    box:SetScript("OnEditFocusGained", function() Search.Begin() end)
    box:SetScript("OnTextChanged", function() Search.TextChanged() end)
    box:SetScript("OnEscapePressed", function() Search.Clear() end)
    box:SetScript("OnEnterPressed", function(instance) instance:ClearFocus() end)
    self.editorSettingsSearch = box
    BuildResultsPage()
    return box
end
