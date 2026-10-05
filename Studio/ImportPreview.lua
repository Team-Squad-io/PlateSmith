local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Designs = assert(PS.Designs, "PlateSmith Designs missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local catalog = assert(Options.editorCatalog)
local editorOrder, editorDefinitions = catalog.editorOrder, catalog.editorDefinitions
local CopyLayout = assert(Options.editorBlueprint).CopyLayout

-- The Blueprint import window's preview (BlueprintWindow.lua): one small plate for each design the
-- pasted Blueprint, imported with the ticked sections, would change. The settings come from
-- PS.BlueprintImportResult (the import's own route, on a copy); each plate is drawn by Studio's preview
-- (RefreshEditorAppearance) on a view of its own, so nothing of Studio's, the profile's or the DB's is
-- touched. Plates are made the first time they are needed and kept for the next paste.
local ImportPreview = {}
Options.ImportPreview = ImportPreview

local PLATE_LABELS = { enemy = L["Enemies"], friendlyPlayer = L["Players"], friendlyNPC = L["Friendly NPCs"] }
-- Every design a plate can be drawn with, in the order the preview lists them.
local DESIGNS = {}
for _, plateType in ipairs({ "enemy", "friendlyPlayer", "friendlyNPC" }) do
    DESIGNS[#DESIGNS + 1] = { plateType = plateType, context = "world" }
    for _, context in ipairs(Designs.CONTEXTS) do DESIGNS[#DESIGNS + 1] = { plateType = plateType, context = context } end
end
DESIGNS[#DESIGNS + 1] = { plateType = "enemyPlayer", context = "world" }

-- What a caption names, in this order. The layout is the one the plate draws (LayoutField); every
-- profile option no area lists is Other options.
local AREAS = {
    { label = L["Sizes"], fields = { "scale", "width", "healthHeight", "powerWidth", "powerHeight", "castWidth", "castHeight",
        "nameFontSize" } },
    { label = L["Styles"], fields = { "styles", "healthTexture", "healthColourMode", "healthColour" } },
    { label = L["Cast bar"], fields = { "castIcon", "castTime", "castName", "castInterruptColours", "castOnTop", "castColours" } },
    { label = L["Rules"], fields = { "rules" } },
    { label = L["Custom parts"], fields = { "valueSlots" } },
    { label = L["Auras"], fields = { "auraLayouts" } },
}
local NOT_OPTIONS = { contexts = true, players = true, layout = true, namesLayout = true, dungeonNamesLayout = true }
for _, area in ipairs(AREAS) do
    for _, field in ipairs(area.fields) do NOT_OPTIONS[field] = true end
end
-- The target highlight is named when what the design draws changes: its own values, or the general ones
-- it follows (Schema's HIGHLIGHT).
local HIGHLIGHT = S.HIGHLIGHT
for _, key in ipairs(HIGHLIGHT.KEYS) do NOT_OPTIONS[key] = true end
local highlightNow, highlightImported = {}, {}

-- Equal as a Blueprint carries them: a colour by its hex, so the 1/255 a round trip moves one (0.85 comes
-- back as 217/255) is no change.
local ColourToHex = PS.Format.ColourToHex
local COLOUR_CHANNELS = { r = true, g = true, b = true }
local function IsColour(value)
    return type(value) == "table" and type(value.r) == "number" and type(value.g) == "number" and type(value.b) == "number"
end
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local colour = IsColour(a) and IsColour(b)
    if colour and ColourToHex(a) ~= ColourToHex(b) then return false end
    for key, value in pairs(a) do
        if not (colour and COLOUR_CHANNELS[key]) and not Same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- Settings outside plateProfiles that are not general ones: the Enemies' World sizes and layout, mirrored.
local NOT_GENERAL = { plateProfiles = true, layout = true }
for key in pairs(S.ENEMY_ALIASES) do NOT_GENERAL[key] = true end

-- The layout a design's plate draws: the Enemies' full one; friendly plates' names-only or full one, as
-- Where plates show has them outdoors (Blizzard's plates: the full one), and in dungeons & raids
-- their names layout.
local function LayoutField(plateType, context, live)
    if plateType == "enemy" or plateType == "enemyPlayer" then return "layout" end
    if context == "dungeon" then return "dungeonNamesLayout" end
    return live.friendly == "names" and "namesLayout" or "layout"
end

-- As Settings' GetLayout: normalized against a full design's World, else the plate type's defaults.
local function DrawnLayout(db, plateType, context, field, profile)
    local base = plateType == "enemyPlayer" and "enemy" or plateType
    local fallback = S.profileDefaults[base][field]
    if context ~= "world" and field ~= "dungeonNamesLayout" and Designs.IsFull(db, base, context) then
        fallback = db.plateProfiles[base][field]
    end
    return S.NormalizeLayout(profile and profile[field], fallback)
end

local function HasOwn(db, entry)
    if entry.plateType == "enemyPlayer" then return Designs.Record(db, "enemyPlayer") ~= nil end
    return Designs.Record(db, entry.plateType, entry.context) ~= nil
end

-- The changed areas' names, between two effective profiles (of the settings live and result).
local function ChangedAreas(now, imported, nowLayout, importedLayout, layoutOnly, live, result)
    local names = {}
    if not Same(nowLayout, importedLayout) then names[1] = L["Layout"] end
    if layoutOnly then return names end
    for _, area in ipairs(AREAS) do
        for _, field in ipairs(area.fields) do
            if not Same(now[field], imported[field]) then
                names[#names + 1] = area.label
                break
            end
        end
    end
    local before, after = HIGHLIGHT.Resolve(live, now, highlightNow), HIGHLIGHT.Resolve(result, imported, highlightImported)
    for _, key in ipairs(HIGHLIGHT.KEYS) do
        if not Same(before[key], after[key]) then
            names[#names + 1] = L["Target highlight"]
            break
        end
    end
    local other = false
    for _, pair in ipairs({ { now, imported }, { imported, now } }) do
        for key, value in pairs(pair[1]) do
            if not NOT_OPTIONS[key] and not Same(value, pair[2][key]) then other = true end
        end
    end
    if other then names[#names + 1] = L["Other options"] end
    return names
end

-- The designs that differ between live (the working settings) and result (what the import would
-- leave): { { plateType, context, label, areas = { name }, state = "new" | "removed" | nil, now,
-- imported (effective profiles), nowLayout, importedLayout } }, and whether any general setting differs.
-- A context design is listed only where either has one of its own (without, it is World, listed
-- already); friendly plates' Dungeons & raids names only while the test overlay draws them.
function ImportPreview.Changes(live, result)
    local changes = {}
    for _, entry in ipairs(DESIGNS) do
        local plateType, context = entry.plateType, entry.context
        local blizzard = plateType ~= "enemyPlayer" and Designs.IsBlizzard(plateType, context)
        local had, has = true, true
        if blizzard then
            had = live.experimentalDungeonFriendlyText == true
            has = had
        elseif context ~= "world" or plateType == "enemyPlayer" then
            had, has = HasOwn(live, entry), HasOwn(result, entry)
        end
        if had or has then
            local field = LayoutField(plateType, context, live)
            local now, imported = Designs.Peek(live, plateType, context), Designs.Peek(result, plateType, context)
            local nowLayout = DrawnLayout(live, plateType, context, field, now)
            local importedLayout = DrawnLayout(result, plateType, context, field, imported)
            local areas = ChangedAreas(now, imported, nowLayout, importedLayout, blizzard, live, result)
            if #areas > 0 then
                local label = plateType == "enemyPlayer" and L["Enemy players"]
                    or string.format(L["%s › %s"], PLATE_LABELS[plateType], Designs.LABELS[context])
                changes[#changes + 1] = { plateType = plateType, context = context, label = label, areas = areas,
                    state = not had and "new" or not has and "removed" or nil, now = now, imported = imported,
                    nowLayout = nowLayout, importedLayout = importedLayout }
            end
        end
    end
    local general = false
    for _, pair in ipairs({ { live, result }, { result, live } }) do
        for key, value in pairs(pair[1]) do
            if not NOT_GENERAL[key] and not Same(value, pair[2][key]) then general = true end
        end
    end
    return changes, general
end

-- A plate's caption under it: what changed, and whether the design is new or goes.
function ImportPreview.Caption(change)
    local areas = table.concat(change.areas, ", ")
    if change.state == "new" then return string.format(L["New design: %s"], areas) end
    if change.state == "removed" then return string.format(L["Removed: %s"], areas) end
    return areas
end

-- A view: Studio's preview methods with this plate's own state. Only methods and the shared sample
-- choices come from Studio (Options); none of its frames or state, so nothing drawn here moves,
-- selects or repaints Studio's.
local VIEW_SHARED = { editorSampleScripts = true, editorSampleScript = true, studioChrome = true }
local viewMeta = { __index = function(_, key)
    local value = Options[key]
    if type(value) == "function" or VIEW_SHARED[key] then return value end
    return nil
end }
local function Nothing() end
local function ViewProfile(view) return view.previewProfile end
-- Parts are plain frames: no select, hover or drag.
local function MakePart(parent, _, width, height)
    local component = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    component:SetSize(width, height)
    if component.EnableMouse then component:EnableMouse(false) end
    return component
end

local function NewView(clip)
    local stage = CreateFrame("Frame", nil, clip)
    stage:SetSize(1, 1)
    stage:SetPoint("CENTER", clip, "CENTER", 0, 0)
    stage:SetFrameLevel(clip:GetFrameLevel() + 2)
    return setmetatable({
        editorCanvas = clip, editorPreviewStage = stage, editorComponents = {}, editorRulesPreviewTrue = false,
        templateSamples = setmetatable({}, { __index = Options.templateSamples }),
        MakeEditorComponentFrame = MakePart, EditorProfileSettings = ViewProfile, PlaceEditorModel = false,
        UpdateEditorPulse = Nothing, UpdateEditorSelectionHandles = Nothing, RefreshEditorComponentList = Nothing,
        SelectEditorComponent = Nothing, RefreshEditorInspectorContext = Nothing,
    }, viewMeta)
end

-- What a plate draws: the box round its shown parts (side icons and texts included), in stage units at
-- 100%, as Studio's Fit measures them: { left, right, bottom, top }, or nil when nothing shows.
local function ContentBox(view)
    local box
    for key, component in pairs(view.editorComponents) do
        if component:IsShown() then
            local x, y, hw, hh = Options.EditorComponentBounds(view, key)
            if x then
                box = box or { math.huge, -math.huge, math.huge, -math.huge }
                box[1], box[2] = math.min(box[1], x - hw), math.max(box[2], x + hw)
                box[3], box[4] = math.min(box[3], y - hh), math.max(box[4], y + hh)
            end
        end
    end
    return box
end
-- The preview is a small Studio stage: Studio's preview panel art (its world picture, dimmer and frame), its
-- plate-type tabs, a Design dropdown and a View-style menu over the picture, the grid, and the plate at one
-- zoom for every design: the largest (up to MAX_SCALE) at which the widest and tallest plate of any design,
-- imported or as it is now, fits the picture less MARGIN on each side, so a narrower design looks narrower.
-- Everything is its own instance: nothing here reads or writes Studio's tabs, design, view or zoom.
local MIN_SCALE, MAX_SCALE, MARGIN = 0.35, 1.5, 14
ImportPreview.MARGIN, ImportPreview.MAX_SCALE = MARGIN, MAX_SCALE
-- The caption strip along the picture's foot, and the gap between the design row and the plate's room.
local CAPTION_HEIGHT, ROW_GAP = 28, 6

-- Draws a design (change, imported or now) on the view's plate, Studio's way: its parts, sizes, styles,
-- rules, the target highlight and Test values. Returns what it draws (ContentBox).
local function Draw(view, change, showNow)
    local live = PS.GetSettings()
    local plateType, context = change.plateType, change.context
    view.editorProfile, view.editorDesign = plateType, context
    view.editorFriendlyView = LayoutField(plateType, context, live) == "namesLayout" and "names" or "full"
    view.previewProfile = showNow and change.now or change.imported
    view.editorLayout = CopyLayout(showNow and change.nowLayout or change.importedLayout)
    view.editorTransforms = nil
    for flag, value in pairs(Options.EditorSampleReactions(plateType, context) or {}) do view.templateSamples[flag] = value end
    for _, key in ipairs(editorOrder) do
        local component = Options.CreateEditorComponent(view, key, editorDefinitions[key])
        if component then component.previewOwner = view end
    end
    Options.RefreshEditorAppearance(view, live, true)
    -- Studio keeps a part that is turned off or that a rule hides as a faint ghost, to place it; on the
    -- plates it is not drawn.
    for _, component in pairs(view.editorComponents) do
        if not component.targetPreviewVisible or component.previewRuleHidden then component:Hide() end
    end
    return ContentBox(view)
end

-- The plate's room on the stage, in the stage frame's units: its picture under the design row and above the
-- caption strip. Returns width, height and the room's centre's offset from the stage's centre (y).
function ImportPreview.PlateRoom(area)
    local layout = Options.editorPreviewLayout
    local inset = layout.pictureInset
    local top, bottom = layout.rowTop + layout.rowHeight + ROW_GAP, inset + CAPTION_HEIGHT
    local width, height = area.canvas:GetWidth(), area.canvas:GetHeight()
    return width - 2 * inset, height - top - bottom, (bottom - top) / 2
end

local function DesignKey(change) return change.plateType .. "@" .. change.context end

-- The designs of plateType the preview lists, in order, with their index in area.changes.
local function DesignsOf(area, plateType)
    local list = {}
    for index, change in ipairs(area.changes or {}) do
        if change.plateType == plateType then list[#list + 1] = index end
    end
    return list
end

-- A design's name in the Design dropdown: its place, and whether the import makes or removes it.
local function DesignLabel(change)
    local label = Designs.LABELS[change.context] or L["World"]
    if change.state == "new" then return string.format(L["%s (new)"], label) end
    if change.state == "removed" then return string.format(L["%s (removed)"], label) end
    return label
end

-- Shows design index of area.changes (clamped).
function ImportPreview.Select(window, index)
    local area = window.preview
    local count = area and area.changes and #area.changes or 0
    if count == 0 then return false end
    area.page = math.max(1, math.min(count, index))
    ImportPreview.Redraw(window)
    return true
end

-- Places the tabs, the design row and the caption strip for the stage's size (Studio's own measures).
local function LayoutStage(area)
    local layout, canvas = Options.editorPreviewLayout, area.canvas
    local width = canvas:GetWidth()
    local tabs = area.tabs
    local tabWidth = math.floor((width - 16 - 2 * (#tabs - 1)) / math.max(1, #tabs))
    for index, tab in ipairs(tabs) do
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8 + (index - 1) * (tabWidth + 2), -7)
        tab:SetWidth(index == #tabs and (width - 16 - (index - 1) * (tabWidth + 2)) or tabWidth)
    end
    area.row:ClearAllPoints()
    area.row:SetPoint("TOPLEFT", canvas, "TOPLEFT", layout.side, -layout.rowTop)
    area.row:SetSize(math.max(1, width - 2 * layout.side), layout.rowHeight)
    area.art.previewTop = layout.pictureTop
    area.art:Layout()
end

-- The stage in the import window (parent: the Review page; x, top: its place from the window's top left;
-- width, height), and the note on general settings under noteAnchor (noteWidth wide). Hidden until the
-- window is in Import. One plate (one view, its frames made once) draws every design.
function ImportPreview.Attach(window, parent, x, top, width, height, noteAnchor, noteWidth)
    local chrome, layout = Options.studioChrome, Options.editorPreviewLayout
    local canvas = CreateFrame("Frame", nil, parent or window)
    canvas:SetPoint("TOPLEFT", window, "TOPLEFT", x, top)
    canvas:SetSize(width, height)
    canvas:SetFrameLevel((parent or window):GetFrameLevel() + 2)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    canvas:Hide()
    -- The stage frame is the area: its parts and state are its fields.
    local area = canvas
    area.canvas, area.tabs, area.tabFor = canvas, {}, {}
    area.art = chrome.CreatePanelArt(canvas, "preview")
    canvas:SetScript("OnSizeChanged", function() LayoutStage(area) end)
    -- Studio's plate-type tabs; a type the import leaves alone is unavailable.
    for _, definition in ipairs(Options.studioModel.editorProfiles) do
        local tab = chrome.CreateStudioButton(canvas, definition.label, 100, 40, "tab")
        tab.label:SetFont(chrome.FONT, 14)
        tab:SetFrameLevel(canvas:GetFrameLevel() + 6)
        tab.plateType = definition.key
        tab:SetScript("OnClick", function(instance)
            local first = DesignsOf(area, instance.plateType)[1]
            if first then ImportPreview.Select(window, first) end
        end)
        area.tabs[#area.tabs + 1] = tab
        area.tabFor[definition.key] = tab
    end
    -- The design row: Design and its dropdown (the open type's designs the import changes), and at its
    -- right a View-style menu for which plates show, imported or yours as they are now.
    local row = CreateFrame("Frame", nil, canvas)
    row:SetFrameLevel(canvas:GetFrameLevel() + 6)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetFont(chrome.FONT, 15)
    label:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    label:SetText(L["Design:"])
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    local dropdown = PS.UI.Controls.MenuField(row, { width = 226, height = 30, minMenuWidth = 250,
        items = function() return ImportPreview.DesignItems(window) end })
    chrome.SkinDropdown(dropdown)
    dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
    PS.UI.Controls.AttachTooltip(dropdown, L["Design"], { L["The designs of this plate type the import would change."] })
    local show = PS.UI.Controls.MenuField(row, { width = 138, height = 30, minMenuWidth = 160,
        items = function() return ImportPreview.ShowItems(window) end })
    chrome.SkinDropdown(show)
    show:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    PS.UI.Controls.AttachTooltip(show, L["Show"], { L["The plates as the import would leave them, or yours as they "
        .. "are now, to compare. Nothing changes until you press Import selected."] })
    -- The grid (Studio's, placed by its own UpdateEditorGrid on this stage's view), under the plate.
    local gridFrame = CreateFrame("Frame", nil, canvas)
    gridFrame:SetAllPoints(canvas)
    gridFrame:SetFrameLevel(canvas:GetFrameLevel() + 1)
    -- The caption strip along the picture's foot: what the import changes in the shown design.
    local strip = CreateFrame("Frame", nil, canvas)
    strip:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", layout.pictureInset, layout.pictureInset)
    strip:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -layout.pictureInset, layout.pictureInset)
    strip:SetHeight(CAPTION_HEIGHT)
    strip:SetFrameLevel(canvas:GetFrameLevel() + 6)
    local band = strip:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints(strip)
    band:SetColorTexture(0, 0, 0, 0.55)
    local caption = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    caption:SetFont(chrome.FONT, 13)
    caption:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    caption:SetPoint("LEFT", strip, "LEFT", 10, 0)
    caption:SetPoint("RIGHT", strip, "RIGHT", -10, 0)
    caption:SetJustifyH("LEFT")
    if caption.SetWordWrap then caption:SetWordWrap(false) end
    -- Said on the empty stage while there is nothing to draw.
    local message = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    message:SetFont(chrome.FONT, 13)
    message:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    message:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    message:SetWidth(width - 80)
    message:SetJustifyH("CENTER")
    -- Under the section boxes: that general settings change too.
    local note = (parent or window):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetFont(chrome.FONT, 12)
    note:SetTextColor(0.72, 0.70, 0.66)
    note:SetPoint("TOPLEFT", noteAnchor or canvas, "BOTTOMLEFT", 0, -12)
    note:SetWidth(noteWidth or width)
    note:SetJustifyH("LEFT")
    area.row, area.label, area.dropdown, area.show, area.strip, area.caption = row, label, dropdown, show, strip, caption
    area.message, area.note, area.page = message, note, 1
    area.view = NewView(canvas)
    area.view.editorGrid = { frame = gridFrame, textures = {}, area = {} }
    LayoutStage(area)
    window.preview = area
    -- Closed, a waiting rebuild is dropped.
    if window.HookScript then
        window:HookScript("OnHide", function() window.previewRequest = (window.previewRequest or 0) + 1 end)
    end
    ImportPreview.Clear(window)
    return area
end

-- The plate, the tabs, the design row and the caption, shown or not together.
local function ShowPlate(area, shown)
    for _, tab in ipairs(area.tabs) do tab:SetShown(shown) end
    area.row:SetShown(shown)
    area.strip:SetShown(shown)
    area.view.editorPreviewStage:SetShown(shown)
    area.view.editorGrid.frame:SetShown(shown)
    area.message:SetShown(not shown)
end

-- No plates: text (a hint or why there is nothing to show) on the empty stage.
function ImportPreview.Clear(window, text)
    window.previewRequest = (window.previewRequest or 0) + 1
    local area = window.preview
    if not area then return end
    area.changes = nil
    ShowPlate(area, false)
    area.note:SetText("")
    area.message:SetText(text or L["Paste a Blueprint to see the designs it would change."])
    if Options.BlueprintPreviewBuilt then Options.BlueprintPreviewBuilt(window) end
end

-- A new paste starts on the first design (a ticked box keeps the one shown, where it can).
function ImportPreview.ResetPage(window)
    local area = window.preview
    if area then area.page, area.pageKey = 1, nil end
end

-- The Design dropdown's items: the shown type's designs the import changes, the shown one checked.
function ImportPreview.DesignItems(window)
    local area, items = window.preview, {}
    local shown = area.changes and area.changes[area.page]
    if not shown then return items end
    for _, index in ipairs(DesignsOf(area, shown.plateType)) do
        local change = area.changes[index]
        items[#items + 1] = { text = DesignLabel(change), checked = index == area.page,
            tooltip = { title = change.label, text = ImportPreview.Caption(change) },
            func = function() ImportPreview.Select(window, index) end }
    end
    return items
end

-- The View-style menu's items: the plates after the import, or yours now.
function ImportPreview.ShowItems(window)
    local now = window.previewShowsNow == true
    local function Show(on)
        return function()
            window.previewShowsNow = on
            ImportPreview.Redraw(window)
        end
    end
    return { { text = L["After import"], checked = not now, func = Show(false) },
        { text = L["Yours now"], checked = now, func = Show(true) } }
end

-- Draws area.changes' shown design, as imported or (the menu) as they are now, at the shared scale: its
-- tab chosen (the types the import leaves alone unavailable), its design in the dropdown, its changes in
-- the caption strip.
function ImportPreview.Redraw(window)
    local area = window.preview
    local changes = area and area.changes
    if not changes then return end
    local showNow = window.previewShowsNow == true
    local page = math.max(1, math.min(#changes, area.page or 1))
    local change = changes[page]
    area.page, area.pageKey = page, DesignKey(change)
    ShowPlate(area, true)
    local setState = Options.studioChrome.SetStudioButtonState
    for _, tab in ipairs(area.tabs) do
        PS.SaveBar.SetAvailable(tab, DesignsOf(area, tab.plateType)[1] ~= nil)
        setState(tab, tab.plateType == change.plateType)
    end
    area.dropdown:SetText(Designs.LABELS[change.context] or L["World"])
    area.show:SetText(showNow and L["Yours now"] or L["After import"])
    area.caption:SetText(ImportPreview.Caption(change))
    local view = area.view
    local ok, box = pcall(Draw, view, change, showNow)
    if not ok then
        PS.Chat.ReportError("Blueprint import preview", box)
        box = nil
    end
    -- Centred in the plate's room on what it draws, as Studio pans (offsets in the scaled stage's units); the
    -- grid follows, its centre lines through the plate's own centre as in Studio.
    local scale = area.scale or 1
    local _, _, roomY = ImportPreview.PlateRoom(area)
    local panX = box and -(box[1] + box[2]) / 2 or 0
    local panY = (box and -(box[3] + box[4]) / 2 or 0) + roomY / scale
    local stage = view.editorPreviewStage
    stage:SetScale(scale)
    stage:ClearAllPoints()
    stage:SetPoint("CENTER", area.canvas, "CENTER", panX, panY)
    view.editorPreviewZoom, view.editorPreviewPanX, view.editorPreviewPanY = scale, panX, panY
    Options.UpdateEditorGrid(view)
end

-- Steps through the designs (-1, 1), across the tabs; false at an end or with nothing to show.
function ImportPreview.Page(window, step)
    local area = window.preview
    local count = area and area.changes and #area.changes or 0
    local page = (area and area.page or 1) + step
    if page < 1 or page > count then return false end
    return ImportPreview.Select(window, page)
end

-- The window's arrow keys: true when one stepped (the window keeps the key), false to pass it on.
function ImportPreview.Key(window, key)
    if key ~= "LEFT" and key ~= "RIGHT" then return false end
    local area = window.preview
    if not (area and area.canvas:IsVisible() and area.changes and #area.changes > 1) then return false end
    local focus = type(GetCurrentKeyBoardFocus) == "function" and GetCurrentKeyBoardFocus() or nil
    if focus ~= nil then return false end
    ImportPreview.Page(window, key == "LEFT" and -1 or 1)
    return true
end

-- The shared scale: every design drawn once, imported and as now, on the one plate, to measure what it
-- draws (its frames are reused; only the shown design stays drawn); the largest box decides.
local function SharedScale(area)
    local wide, tall = 1, 1
    for _, change in ipairs(area.changes) do
        for _, showNow in ipairs({ false, true }) do
            local ok, box = pcall(Draw, area.view, change, showNow)
            if ok and box then wide, tall = math.max(wide, box[2] - box[1]), math.max(tall, box[4] - box[3]) end
        end
    end
    local width, height = ImportPreview.PlateRoom(area)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, (width - 2 * MARGIN) / wide, (height - 2 * MARGIN) / tall))
end

-- The preview for the window's text and ticked sections (selection: BlueprintWindow's Selection). The design
-- shown stays while it is still listed, else the nearest one.
function ImportPreview.Build(window)
    local area = window.preview
    if not area then return end
    local result, reason = PS.BlueprintImportResult(window.editBox:GetText() or "", window.previewSelection(window))
    if not result then
        if reason == "select at least one section" then
            return ImportPreview.Clear(window, L["Tick a section to see what importing it would change."])
        end
        return ImportPreview.Clear(window, L["This Blueprint cannot be imported as it is: Import selected says why."])
    end
    local changes, general = ImportPreview.Changes(PS.GetSettings(), result)
    if #changes == 0 then
        ImportPreview.Clear(window, general and L["No design changes: only general settings (fonts, colours and more) would change."]
            or L["Nothing on your plates would look different."])
        return
    end
    local key, page = area.pageKey, math.min(area.page or 1, #changes)
    for index, change in ipairs(changes) do
        if key and DesignKey(change) == key then page = index end
    end
    area.changes, area.page = changes, page
    area.scale = SharedScale(area)
    area.note:SetText(general and L["General settings change too (fonts, colours and more); the preview shows yours."] or "")
    ImportPreview.Redraw(window)
    -- The window's Review tab counts the designs.
    if Options.BlueprintPreviewBuilt then Options.BlueprintPreviewBuilt(window) end
end

-- A paste or a ticked box: the preview follows a moment later, once (a burst of keystrokes builds it
-- once). Without a timer it follows at once.
local DEBOUNCE = 0.2
function ImportPreview.Schedule(window)
    window.previewRequest = (window.previewRequest or 0) + 1
    local request = window.previewRequest
    if not (C_Timer and C_Timer.After) then return ImportPreview.Build(window) end
    C_Timer.After(DEBOUNCE, function()
        if window.previewRequest == request and window:IsShown() and window.importing then ImportPreview.Build(window) end
    end)
end
