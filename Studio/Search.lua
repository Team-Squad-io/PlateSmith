local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")
local Theme = assert(PS.StudioTheme, "PlateSmith StudioTheme missing")
local Layout = assert(PS.UI and PS.UI.Layout, "PlateSmith Layout missing")

-- The search box over Settings' categories: it finds a setting on any of Studio's Settings pages,
-- on PlateSmith's pages in Blizzard's Settings panel, or a part in the Studio tree and its inspector's rows. The
-- settings index (and every part's inspector rows) is built the first time the box takes focus, a page at a time within
-- a small time budget (the rest on the ticker); parts are listed for the tab Studio shows, kept while it holds.
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
-- label's first word), of a checkbox's own text or the row's search words, of the section's title (for the
-- section itself), or of the help. Only the start of a word matches ("surn" finds surnames, "urnames" does not).
-- Help counts only when nothing is named with every query word (Search.Query's second pass), so "friendly" lists
-- the settings called friendly, not every row whose help mentions friendly plates.
local SCORE = { label = 10, whole = 2, first = 3, extra = 8, path = 5, help = 2, labelPrefix = 15 }
Search.SCORE, Search.MAX_RESULTS = SCORE, MAX_RESULTS

local index = { entries = {}, queue = nil, done = false }
Search._index = index
-- The Studio part entries (PartEntries), kept for a search's keystrokes while what they come from holds.
local partCache = { stamp = {}, entries = nil }
Search._parts = partCache

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

-- Plain text: no colour codes or inline textures.
local function Plain(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- US spellings as the UI's UK ones, the query's and the index's alike: a word that starts with one has its start
-- changed ("colors" Colours, "grayed" Greyed, "colorblind" colourblind), so a start both share ("colo") still matches.
local SPELLINGS = { { "color", "colour" }, { "gray", "grey" }, { "behavior", "behaviour" }, { "favor", "favour" } }
local function UK(word)
    for _, pair in ipairs(SPELLINGS) do
        local us = pair[1]
        if word:sub(1, #us) == us then return pair[2] .. word:sub(#us + 1) end
    end
    -- center(s): centre(s); centered, centering: centred, centring.
    if word:sub(1, 6) == "center" then
        local rest = word:sub(7)
        return (rest == "" or rest:sub(1, 1) == "s") and "centre" .. rest or "centr" .. rest
    end
    return word
end
Search.UK = UK

-- Lowercase words (UK spellings): runs of anything but spaces and punctuation, so accented letters stay in a word.
-- Kept per text (the Studio part entries are prepared again for each search): read only. Bounded.
local wordsCache, wordsCount = {}, 0
local function Words(text)
    if type(text) ~= "string" or text == "" then return {} end
    local cached = wordsCache[text]
    if cached then return cached end
    local words = {}
    for word in Plain(text):lower():gmatch("[^%s%p]+") do words[#words + 1] = UK(word) end
    if wordsCount >= 4000 then wordsCache, wordsCount = {}, 0 end
    wordsCache[text], wordsCount = words, wordsCount + 1
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

-- An entry's score for the query's words: every word must start a word of its name (label, checkbox text, search
-- words; a section's title for the section itself), else nil. Where it sits (its page, section or part) may stand for
-- a word only once its name holds another ("level font size": Level's Font size; "level" alone: not every Level row).
-- withHelp: its help counts too.
function Search.Score(entry, queryWords, queryText, withHelp)
    if #queryWords == 0 then return nil end
    local total, named = 0, false
    for _, query in ipairs(queryWords) do
        local own = math.max(Best(entry.labelWords, query, SCORE.label, SCORE.first),
            Best(entry.extraWords, query, SCORE.extra, 0), Best(entry.keywordWords, query, SCORE.extra, 0),
            entry.pathCounts and Best(entry.pathWords, query, SCORE.path, 0) or 0)
        local score = math.max(own, Best(entry.pathWords, query, SCORE.path, 0),
            withHelp and Best(entry.helpWords, query, SCORE.help, 0) or 0)
        if score == 0 then return nil end
        named = named or own > 0 or (withHelp and score > 0)
        total = total + score
    end
    if not named then return nil end
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
    entry.pathWords, entry.helpWords, entry.keywordWords = Words(entry.path), Words(entry.help), Words(entry.keywords)
    -- The page and section a row sits in name the section, not each of its rows: only a section's own entry matches
    -- on them, and brings its rows with it.
    if entry.pathCounts == nil then entry.pathCounts = entry.section ~= nil and entry.frame == entry.section end
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
            extra = found.extra, help = found.help, keywords = found.keywords, sectionTitle = sectionTitle,
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
    -- The Modules group's pages (Studio/Modules.lua), built the same way: "Modules › Threat › Your role".
    for _, category in ipairs(Options.ModuleSettingsCategories and Options:ModuleSettingsCategories() or {}) do
        local key = category.key
        sources[#sources + 1] = function()
            local panel = Options:EditorSettingsPage(key)
            if not panel then return end
            IndexPage(panel, "studio", { category = key, panel = panel, pagePath = L["Modules"], pageLabel = category.label,
                module = category.module })
        end
    end
    -- Game Options' main page (its Profiles page and a module's there only open Studio, whose pages are indexed above).
    local blizzard = {
        { Options.panel, Options.category, "PlateSmith" },
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
    -- A module's own Game Options page (RegisterModuleSettings) is hand-built, so it is found by its title.
    for _, legacy in ipairs(Options.legacyModulePages or {}) do
        sources[#sources + 1] = function()
            index.entries[#index.entries + 1] = Prepare({ place = "blizzard", page = legacy.page, frame = legacy.page,
                categoryObject = legacy.category, label = legacy.title, pageLabel = legacy.title,
                path = Path(L["Settings"], legacy.title) })
        end
    end
    -- The parts' own inspector rows, built the first time a part is selected: built here too, one a step, so the
    -- part entries (PartEntries) list each part's rows as its inspector shows them.
    local contexts, seen = {}, {}
    for _, context in pairs(Options.editorContextForKey or {}) do
        if not seen[context] then contexts[#contexts + 1], seen[context] = context, true end
    end
    contexts[#contexts + 1] = "blizzardName"
    table.sort(contexts)
    for _, context in ipairs(contexts) do
        sources[#sources + 1] = function()
            if Options.IsEditorContextPending and Options:IsEditorContextPending(context) then
                Options:BuildEditorContext(context)
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
    partCache.entries = nil
    PS.Ticker.SetEnabled(INDEX_TICKER, false)
end

-- A section's title as a step of a path: DISPLAY reads Display.
local function SectionName(title)
    if type(title) ~= "string" or title == "" then return nil end
    return title:sub(1, 1) .. title:sub(2):lower()
end

-- Whether a layout would show item now (its test, if any, says yes).
local function Shown(item)
    if item.visible == nil then return true end
    local ok, shown = pcall(item.visible)
    return ok and shown and true or false
end

-- The rows part key's inspector shows (its context's own sections, then Style), as Layout.SearchEntries finds them
-- in the built rows, without those its layout would hide with key selected: the rows' tests read
-- Options.selectedComponent and the inspector's selection, so both stand for key while they are asked, then are put
-- back. Placement and Rules are every part's alike, so they are left out. Each row: SearchEntries' entry and its place
-- ("partRow" or "partStyleRow"). Second result: whether the context's rows are built.
local function InspectorRows(key, context)
    local page, frames, rows = Options.editorComponentContent, Options.editorContextFrames or {}, {}
    local built = frames[context] ~= nil and not Options:IsEditorContextPending(context)
    if not page then return rows, false end
    local roots = {}
    for _, item in ipairs(page.flowItems or {}) do
        if item.frame == frames[context] and built then
            roots[#roots + 1] = { item = item, place = "partRow" }
        elseif item.frame == Options.editorStyleBlock then
            roots[#roots + 1] = { item = item, place = "partStyleRow" }
        end
    end
    local selectedKey, selection = Options.selectedComponent, rawget(Options, "editorInspectorSelection")
    Options.selectedComponent, Options.editorInspectorSelection = key, { key = key, context = context }
    local ok, failure = pcall(function()
        for _, root in ipairs(roots) do
            for _, found in ipairs(Layout.SearchEntries({ flowItems = { root.item } }, Shown)) do
                -- A row in a section (not the section itself, nor a sub-heading).
                if found.section and found.frame ~= found.section and not found.heading then
                    found.place = root.place
                    rows[#rows + 1] = found
                end
            end
        end
    end)
    Options.selectedComponent, Options.editorInspectorSelection = selectedKey, selection
    if not ok then PS.Chat.ReportError("studio search " .. tostring(key), failure) end
    return rows, built
end

-- Part key's inspector rows as entries ("Part › Section", the row's label), through add. A context not built yet gives
-- its Display text rows' labels (EditorDisplayRows); the row is found once selecting the part has built it.
-- EditorStyleSearchRows' words and help join the Style row of the same label (else they are a row of their own).
local function AddPartRows(key, partLabel, add)
    local context = Options:EditorPartContext(key) or "other"
    local found, built = InspectorRows(key, context)
    local rows = {}
    if not built then
        for _, row in ipairs(Options.EditorDisplayRows and Options:EditorDisplayRows(key) or {}) do
            rows[#rows + 1] = { place = "partRow", label = row.label, frame = row.frame, section = row.section,
                path = Path(partLabel, L["Display"]) }
        end
    end
    for _, row in ipairs(found) do rows[#rows + 1] = row end
    for _, extra in ipairs(Options.EditorStyleSearchRows and Options:EditorStyleSearchRows(key) or {}) do
        local same
        for _, row in ipairs(rows) do
            if row.place == "partStyleRow" and row.label == extra.label then same = row end
        end
        if same then
            same.keywords = same.keywords and extra.keywords and (same.keywords .. " " .. extra.keywords) or extra.keywords
                or same.keywords
            same.help = same.help or extra.help
        else
            rows[#rows + 1] = { place = "partStyleRow", label = extra.label, help = extra.help, keywords = extra.keywords }
        end
    end
    for _, row in ipairs(rows) do
        local where = row.place == "partStyleRow" and L["Style"] or SectionName(row.section and row.section.kitSearchTitle)
        add({ place = row.place, key = key, label = row.label, extra = row.extra, help = row.help, keywords = row.keywords,
            frame = row.frame, section = row.section, partLabel = partLabel, path = row.path or Path(partLabel, where) })
    end
end

-- The + Add menu's category of a part (Editor's ADD_MENU), else Other (parts other addons registered).
local function AddCategory(key)
    for _, category in ipairs(Options.editorAddMenu or {}) do
        for _, listed in ipairs(category.keys) do
            if listed == key then return category.label end
        end
    end
    return L["Other"]
end

-- Whether the part entries kept (partCache) still hold: nothing they come from changed (the settings, by Designs'
-- revision; the design and layout Studio edits; the friendly view; how many contexts are built).
local function PartsFresh()
    local built = 0
    for context in pairs(Options.editorContextFrames or {}) do
        if not Options:IsEditorContextPending(context) then built = built + 1 end
    end
    local stamp, fresh = partCache.stamp, partCache.entries ~= nil
    local now = { PS.Designs and PS.Designs.revision, Options:EditorTarget(), Options.editorLayout, Options.editorFriendlyView,
        built }
    for position = 1, 5 do
        if stamp[position] ~= now[position] then fresh, stamp[position] = false, now[position] end
    end
    return fresh
end

-- The parts this plate type's tree lists, as entries, each with its inspector's rows as "Part › Section" rows
-- (AddPartRows); a part deleted from the plate as "Add part: Range" under "+ Add › Text"; Blizzard's name rows on
-- Players › Dungeons & raids; and the Plate row's Target highlight, Friendly plates and Totems rows.
local function PartEntries()
    if PartsFresh() then return partCache.entries end
    local entries, settings = {}, PS.GetSettings and PS.GetSettings()
    local order = #index.entries
    local function Add(entry)
        order = order + 1
        entry.order = order
        entries[#entries + 1] = Prepare(entry)
    end
    local keys = {}
    for key in pairs(Options.editorLayout or {}) do
        if not key:match("^group%.%d+$") then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local label = Options:EditorComponentLabel(key)
        if Options:IsEditorComponentRelevant(key, settings) then
            Add({ place = "part", key = key, label = label, path = L["Part in the Studio tree"] })
            AddPartRows(key, label, Add)
        elseif Options:IsEditorComponentRelevant(key, settings, true) then
            Add({ place = "addPart", key = key, partLabel = label, label = string.format(L["Add part: %s"], label),
                path = Path(L["+ Add"], AddCategory(key)) })
        end
    end
    for _, row in ipairs(Options.EditorTargetHighlightRows and Options:EditorTargetHighlightRows() or {}) do
        Add({ place = "plateRow", label = row.label, help = row.help, keywords = row.keywords, shown = row.shown,
            path = Path(L["Plate settings"], L["Target highlight"]) })
    end
    -- Friendly plates (Players and Friendly NPCs › Plate settings), from any tab.
    for _, row in ipairs(Options.EditorFriendlyRows and Options:EditorFriendlyRows() or {}) do
        local where = row.plateType and Options:EditorPlateLabel(row.plateType) or nil
        Add({ place = "friendlyRow", id = row.id, label = row.label, help = row.help, plateType = row.plateType,
            path = Path(where, L["Plate settings"], row.id ~= "section" and L["Friendly plates"] or nil) })
    end
    -- Totems' Display (Enemies and Friendly NPCs › Type › Totems › Plate settings), from any tab.
    for _, row in ipairs(Options.EditorTotemRows and Options:EditorTotemRows() or {}) do
        Add({ place = "totemRow", id = row.id, label = row.label, help = row.help, keywords = row.keywords,
            path = Path(L["Type"], L["Totems"]) })
    end
    -- Blizzard's name rows on Players › Dungeons & raids (names only, class colours, its font) while another
    -- view is open. With the overlay test on, that tab shows the overlay's parts instead.
    if not Options:IsEditorBlizzardNames(settings) and not (settings and settings.experimentalDungeonFriendlyText == true)
        and Options.EditorDungeonNameRows then
        local partLabel = L["Name (drawn by Blizzard)"]
        for _, row in ipairs(Options:EditorDungeonNameRows()) do
            Add({ place = "dungeonNameRow", key = "name", label = row.label, partLabel = partLabel,
                path = Path(L["Players"], L["Dungeons & raids"], partLabel, L["Display"]) })
        end
    end
    partCache.entries = entries
    return entries
end

-- Whether an entry can be shown now: its category is listed, and its row was not hidden by its
-- page (a folded section's rows still count).
local function Available(entry, categories)
    if entry.place == "part" or entry.place == "partRow" or entry.place == "partStyleRow" or entry.place == "dungeonNameRow"
        or entry.place == "addPart" then
        return true
    end
    -- A Target highlight row its style hides (the glow's rows under Edge) is not offered.
    if entry.place == "plateRow" then return not entry.shown or entry.shown() and true or false end
    if entry.place == "friendlyRow" or entry.place == "totemRow" then return true end
    if entry.place == "studio" and not categories[entry.category] then return false end
    -- A module's page that was turned off (its fifth error) offers nothing.
    if entry.module and entry.module.state == "disabled" then return false end
    local frame, kit = entry.frame, entry.place == "studio" and Options.settingsKit or entry.page and entry.page.settingsKit
    if frame.IsShown and not frame:IsShown() then
        local section = entry.section
        local folded = section and section ~= frame and kit and kit.IsFolded(section.foldKey)
        if not folded then return false end
        -- Folded, a row its page would hide anyway (an interact key row this client has no CVar for) stays out.
        local item = entry.item
        if item and item.visible and not item.visible() then return false end
    end
    return true
end

-- Help's own pages (Help, its rule words) come after the settings that match.
local function Tier(entry) return entry.category == "help" and 1 or 0 end

-- The best matches for text, at most limit (default MAX_RESULTS), best first; and whether they were found only
-- through their help (nothing is named with every query word: then whatever mentions them).
function Search.Query(text, limit)
    local queryWords = Words(text)
    if #queryWords == 0 then return {}, false end
    local queryText = table.concat(queryWords, " ")
    local categories = {}
    for _, category in ipairs(Options:SettingsCategoryList()) do categories[category.key] = true end
    local candidates = {}
    for _, entry in ipairs(index.entries) do
        if Available(entry, categories) then candidates[#candidates + 1] = entry end
    end
    for _, entry in ipairs(PartEntries()) do
        if Available(entry, categories) then candidates[#candidates + 1] = entry end
    end
    local found, viaHelp = {}, false
    for pass = 1, 2 do
        for _, entry in ipairs(candidates) do
            local score = Search.Score(entry, queryWords, queryText, pass == 2)
            if score then found[#found + 1] = { entry = entry, score = score } end
        end
        if #found > 0 then break end
        viaHelp = true
    end
    if #found == 0 then viaHelp = false end
    table.sort(found, function(a, b)
        if Tier(a.entry) ~= Tier(b.entry) then return Tier(a.entry) < Tier(b.entry) end
        if a.score ~= b.score then return a.score > b.score end
        if #a.entry.label ~= #b.entry.label then return #a.entry.label < #b.entry.label end
        if a.entry.label ~= b.entry.label then return a.entry.label < b.entry.label end
        return a.entry.order < b.entry.order
    end)
    local results = {}
    for position = 1, math.min(limit or MAX_RESULTS, #found) do results[position] = found[position].entry end
    return results, viaHelp
end

-- A frame's distance below stop, following its TOPLEFT anchors (the kit places every flow item by
-- its TOPLEFT), else from the two frames' tops; nil when neither says.
local function OffsetIn(frame, stop)
    if not stop then return nil end
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

-- Blizzard's Settings panel sits under Studio and is protected in combat: Studio steps aside while the
-- page opens at the setting, and comes back as it was when the panel closes; its unsaved changes stay in
-- play meanwhile, so it does not ask about them. Where the panel cannot be followed, Studio closes as its
-- close button does (asking about unsaved changes).
local function RevealBlizzardSetting(entry)
    if PS.Secret.InCombat() then
        PS.Chat.Print(L["Blizzard's Settings panel opens only out of combat."])
        return false
    end
    local Window, editor = PS.UI.Window, Options.editor
    local stepAside = editor ~= nil and editor:IsShown() and Window.WatchSettingsPanel()
    if editor then
        Options.editorSteppingAside = stepAside or nil
        editor:Hide()
        Options.editorSteppingAside = nil
    end
    if PS.OpenOptions then PS.OpenOptions() end
    if stepAside and not Window.WhenSettingsPanelCloses(function()
        if not editor:IsShown() then PS.OpenVisualEditor() end
    end) then
        PS.OpenVisualEditor() -- the panel did not open: nothing to step aside for
    end
    local category = entry.categoryObject
    if category and category ~= Options.category and Settings and Settings.OpenToCategory and category.GetID then
        pcall(Settings.OpenToCategory, category:GetID())
    end
    local page = entry.page
    if page.settingsKit then Unfold(page.settingsKit, entry.section) end
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

local function IsHidden(frame) return frame.IsShown ~= nil and not frame:IsShown() end

-- A part's own row: the part selected, its section unfolded, the inspector scrolled to the row (its section while the
-- row is hidden). A row listed before its part's rows were built is found once selecting the part has built them.
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
    if IsHidden(frame) and section then frame = section end
    local offset = OffsetIn(frame, Options.editorComponentContent)
    local bar = Options.editorComponentScrollBar
    if offset and bar and bar.ScrollToOffset then bar:ScrollToOffset(math.max(0, offset - REVEAL_MARGIN)) end
    Flash(frame)
end

-- A part's Style row: the part selected, the Style section unfolded and scrolled to the row (else the shown row with
-- that label, else the section).
local function RevealPartStyleRow(entry)
    RevealPart(entry)
    local section = Options.editorStyleBlock
    if not section then return end
    local function Find(flow)
        for _, item in ipairs(flow.flowItems or {}) do
            if item.frame.kitSearchLabel == entry.label and not IsHidden(item.frame) then return item.frame end
            local found = Find(item.frame)
            if found then return found end
        end
    end
    Unfold(Options.inspectorKit, section)
    Options:LayoutEditorInspector()
    local frame = entry.frame
    if not frame or IsHidden(frame) then frame = Find(section) or section end
    local offset = OffsetIn(frame, Options.editorComponentContent)
    local bar = Options.editorComponentScrollBar
    if offset and bar and bar.ScrollToOffset then bar:ScrollToOffset(math.max(0, offset - REVEAL_MARGIN)) end
    Flash(frame)
end

-- A part's control (control(): the control, read once the part is selected and its rows built; Rules › Presets ›
-- Built in): the part selected, the control's section unfolded, scrolled to its row and flashed.
function Search.RevealPartControl(key, control)
    RevealPart({ key = key })
    local found = control()
    local row = found and found:GetParent()
    if not row then return false end
    Unfold(Options.inspectorKit, row:GetParent())
    Options:LayoutEditorInspector()
    local offset = OffsetIn(row, Options.editorComponentContent)
    local bar = Options.editorComponentScrollBar
    if offset and bar and bar.ScrollToOffset then bar:ScrollToOffset(math.max(0, offset - REVEAL_MARGIN)) end
    Flash(row)
    return true
end

-- The selected part's rule index (Show rule, under a colour a rule covers): its Rules section unfolded, scrolled to the
-- rule's card and flashed. False when the part has no such rule.
function Search.RevealPartRule(position)
    local section, cards = Options.editorRulesBlock, Options.editorRuleRows
    if not section or type(position) ~= "number" then return false end
    Unfold(Options.inspectorKit, section)
    Options:LayoutEditorInspector()
    local card = cards and cards[position]
    local frame = card and card.active and card or section
    local offset = OffsetIn(frame, Options.editorComponentContent)
    local bar = Options.editorComponentScrollBar
    if offset and bar and bar.ScrollToOffset then bar:ScrollToOffset(math.max(0, offset - REVEAL_MARGIN)) end
    Flash(frame)
    return frame == card
end

-- A row of Blizzard's name on Players › Dungeons & raids: Studio opens that design, then the row as a part's.
local function RevealDungeonNameRow(entry)
    Options:OpenEditorDesign("friendlyPlayer", "dungeon")
    RevealPartRow({ key = entry.key, label = entry.label })
end

-- The Plate row's Target highlight (Settings' link, a search result): Studio's editor with the Plate row
-- selected, the section open, scrolled to the row labelled label (else the section) and flashed.
function Search.RevealTargetHighlight(label)
    if not (Options.editor and Options.editor:IsShown()) and not (PS.OpenVisualEditor and PS.OpenVisualEditor()) then
        return false
    end
    -- Blizzard's own dungeon plate and the Enemy players gate have no Plate row: World's has. Objects have no
    -- target highlight: the Enemies' instead.
    if Options.editorPlayersGated or Options:IsEditorObject() then
        Options:OpenEditorDesign("enemy", "world")
    elseif Options:IsEditorBlizzardNames() then
        Options:OpenEditorDesign(Options.editorProfile, "world")
    end
    return Search.RevealPlateRow("target", "label", label)
end

-- Plate settings' sections (built with the Plate row): the section and its rows.
local PLATE_SECTIONS = {
    target = function() return Options.editorTargetHighlightSection, Options:EditorTargetHighlightRows() end,
    friendly = function() return Options.editorFriendlySection, Options:EditorFriendlyRows() end,
    totems = function() return Options.editorTotemSection, Options:EditorTotemRows() end,
    objectLooks = function() return Options.editorObjectLookSection, Options:EditorObjectLookRows() end,
}

-- With Studio open on the right tab and design: the Plate row selected, the section (PLATE_SECTIONS' which)
-- unfolded, scrolled to its row whose field is value (else the section) and flashed.
function Search.RevealPlateRow(which, field, value)
    Options:SetEditorInspectorPage("components")
    Options:SelectEditorPlate()
    local section, rows = PLATE_SECTIONS[which]()
    if not section then return false end
    Unfold(Options.inspectorKit, section)
    Options:LayoutEditorInspector()
    local target = section
    for _, row in ipairs(rows) do
        if value and row[field] == value and row.frame and row.frame:IsShown() then target = row.frame end
    end
    local offset = OffsetIn(target, Options.editorComponentContent)
    local bar = Options.editorComponentScrollBar
    if offset and bar and bar.ScrollToOffset then bar:ScrollToOffset(math.max(0, offset - REVEAL_MARGIN)) end
    Flash(target)
    return true
end

-- Plate settings › Friendly plates (Settings' link, a search result): on the open friendly tab, else plateType's
-- (default Players), at its World design (Dungeons & raids is Blizzard's, with no Plate row), at the row id.
function Search.RevealFriendlyPlates(id, plateType)
    if not (Options.editor and Options.editor:IsShown()) and not (PS.OpenVisualEditor and PS.OpenVisualEditor()) then
        return false
    end
    local open = Options.editorProfile
    plateType = plateType or ((open == "friendlyPlayer" or open == "friendlyNPC") and open or "friendlyPlayer")
    if plateType ~= open or Options.editorDesign == "dungeon" then Options:OpenEditorDesign(plateType, "world") end
    return Search.RevealPlateRow("friendly", "id", id)
end

-- Type › Totems' Plate settings: on the open Enemies or Friendly NPCs tab (at World where Blizzard draws its friendly
-- plates), else the Enemies' World design; Type › Totems opened there.
function Search.RevealTotems(id)
    if not (Options.editor and Options.editor:IsShown()) and not (PS.OpenVisualEditor and PS.OpenVisualEditor()) then
        return false
    end
    local open = Options.editorProfile
    if Options.editorPlayersGated or not PS.ProfileSchema.TOTEMS.PLATES[open] then
        Options:OpenEditorDesign("enemy", "world")
    elseif Options:IsEditorBlizzardNames() then
        Options:OpenEditorDesign(open, "world")
    end
    if not Options:IsEditorTotem() and not Options:SetEditorObjectType("totem") then return false end
    return Search.RevealPlateRow("totems", "id", id)
end

-- A part deleted from the plate: put back as + Add does (Options:AddEditorComponent), then shown in the tree.
local function AddPart(entry)
    Options:SetEditorInspectorPage("components")
    if not Options:AddEditorComponent(entry.key) then return false end
    RevealPart(entry)
    return true
end

-- Plate settings › Object looks (Settings › Objects & interacting's links): the Objects tab (its open design and type
-- kept when already open), at the row id.
function Search.RevealObjectLooks(id)
    if not (Options.editor and Options.editor:IsShown()) and not (PS.OpenVisualEditor and PS.OpenVisualEditor()) then
        return false
    end
    if not Options:IsEditorObject() and not Options:OpenEditorDesign("object", "world") then return false end
    return Search.RevealPlateRow("objectLooks", "id", id)
end

-- Goes to a result: its category, section unfolded, scrolled to and flashed.
function Search.Pick(entry)
    if not entry then return false end
    Search.Clear()
    if entry.place == "part" then
        RevealPart(entry)
    elseif entry.place == "addPart" then
        return AddPart(entry)
    elseif entry.place == "partRow" then
        RevealPartRow(entry)
    elseif entry.place == "partStyleRow" then
        RevealPartStyleRow(entry)
    elseif entry.place == "dungeonNameRow" then
        RevealDungeonNameRow(entry)
    elseif entry.place == "plateRow" then
        return Search.RevealTargetHighlight(entry.label)
    elseif entry.place == "friendlyRow" then
        return Search.RevealFriendlyPlates(entry.id, entry.plateType)
    elseif entry.place == "totemRow" then
        return Search.RevealTotems(entry.id)
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

-- A pooled group: a heading over one section's matches (or all its rows, when the section matched).
-- A row that cannot be changed carries its own dimming and disabled control, lent or not.
local function Group(position)
    local group = results.groups[position]
    if group then return group end
    local kit, page = Options.settingsKit, results.page
    group = kit.Group(page.columns)
    group.heading = Heading(kit, group)
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
    if entry.place == "partRow" or entry.place == "partStyleRow" or entry.place == "dungeonNameRow" then
        return string.format(L["Select part in Studio › %s"], Path(entry.path, entry.label))
    end
    if entry.place == "addPart" then return string.format(L["Add in Studio › %s"], Path(entry.path, entry.partLabel)) end
    if entry.place == "plateRow" or entry.place == "friendlyRow" or entry.place == "totemRow" then
        return string.format(L["Open in Studio › %s"], Path(entry.path, entry.label))
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
        group.flowItems = {}
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
        group.flowItems = items
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
function Search.LayoutResults(width, shown)
    local page = results.page
    if not page then return 0 end
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", Options.editorSettingsContent, "TOPLEFT", 0, 0)
    page:SetShown(shown and results.active)
    if not results.active then return 0 end
    return page:Relayout(width)
end

local function SetHeading()
    local title, summary = Options.editorSettingsTitle, Options.editorSettingsSummary
    if title then title:SetText(L["Search results"]) end
    if summary then
        summary:SetText(string.format(results.viaHelp and L["No setting is called \"%s\": these mention it in their help."]
            or L["Settings that match \"%s\"."], results.text or ""))
    end
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
    results.found, results.viaHelp = Search.Query(text, MAX_RESULTS)
    results.active, results.text = true, text
    Place(results.found)
    if viewport and viewport.SetVerticalScroll then viewport:SetVerticalScroll(0) end
    SetHeading()
    Options:LayoutEditorSettingsPanels()
end

-- The rows go back to their pages, and the category shows again where it was scrolled to.
function Search.Close()
    PS.Ticker.SetEnabled(DEBOUNCE_TICKER, false)
    partCache.entries = nil
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
