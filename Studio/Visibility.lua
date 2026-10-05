local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Controls = assert(PS.UI and PS.UI.Controls, "PlateSmith Controls missing")
local Visibility = assert(PS.PlateVisibility, "PlateSmith PlateVisibility missing")
local Schema = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local model = assert(Options.studioModel)
local Theme = assert(PS.StudioTheme, "PlateSmith StudioTheme missing")
local L = PS.L
local WidgetName = model.WidgetName

-- Studio's Where plates show (Nameplates/Visibility.lua): Settings › Behaviour & display › Where plates
-- show, a grid of switches (a row per plate type, a column per kind of place), and the design row's
-- eye that opens it.
local V = Schema.VISIBILITY
local PLACE_HEADERS = { world = L["World"], dungeon = L["Dungeons & raids"], pvp = L["Battlegrounds & arenas"],
    city = L["Cities & inns"], inCombat = L["In combat"], noCombat = L["Out of combat"] }
-- Said under the grid and in the eye's tooltip on the Enemy players tab.
local ENEMY_PLAYERS_NOTE = L["Enemy players show and hide with the Enemies row: Blizzard has one switch for every enemy plate."]
-- The grid's label column and the header's height.
local GRID_LABEL_W, HEADER_H = 128, 40
-- The eye's icon (the tree's, 26 wide) and its count's colours.
local EYE_ICON, EYE_TEXT, EYE_HOVER = 26, { 0.86, 0.84, 0.79 }, { 1, 0.86, 0.45 }

local function Settings() return PS.GetSettings() end

-- Whose cells a plate type's row edits: Friendly NPCs share Players' when the client has one
-- switch for every friendly plate.
-- Enemy players always share the Enemies' (one switch for every enemy plate).
local function RowType(plateType)
    if plateType == "enemyPlayer" then return "enemy" end
    if plateType == "friendlyNPC" and Visibility.FriendlyShared() then return "friendlyPlayer" end
    return plateType
end

local function Columns()
    local columns = {}
    for _, place in ipairs(V.PLACES) do columns[#columns + 1] = place end
    if Visibility.combatColumns then
        columns[#columns + 1] = "inCombat"
        columns[#columns + 1] = "noCombat"
    end
    return columns
end

-- The combat setting as its two boxes, and back.
local function CombatHas(value, column)
    if value == "always" or value == nil then return true end
    return (column == "inCombat" and value == "combat") or (column == "noCombat" and value == "noCombat")
end
local function CombatValue(inCombat, noCombat)
    if inCombat and noCombat then return "always" end
    if inCombat then return "combat" end
    if noCombat then return "noCombat" end
    return "never"
end

local function Get(plateType, column)
    local keys, settings = V.keys[RowType(plateType)], Settings()
    if column == "inCombat" or column == "noCombat" then return CombatHas(settings[keys.combat], column) end
    return settings[keys[column]] ~= false
end

local function Set(plateType, column, on)
    local keys, settings = V.keys[RowType(plateType)], Settings()
    local ok
    if column == "inCombat" or column == "noCombat" then
        local inCombat, noCombat = Get(plateType, "inCombat"), Get(plateType, "noCombat")
        if column == "inCombat" then inCombat = on else noCombat = on end
        ok = PS.SetOption(keys.combat, CombatValue(inCombat, noCombat))
    else
        ok = PS.SetOption(keys[column], on and true or false)
    end
    Options:Refresh(true)
    return ok and settings ~= nil
end

local function PlateLabel(plateType)
    if plateType == "friendlyPlayer" and Visibility.FriendlyShared() then return L["Friendly"] end
    return Options:EditorPlateLabel(plateType)
end

-- The places plateType is hidden in (World, then the others in order), from settings.
local function HiddenPlaces(plateType, settings)
    local hidden, keys = {}, V.keys[RowType(plateType)]
    for _, place in ipairs(V.PLACES) do
        if settings and settings[keys[place]] == false then hidden[#hidden + 1] = place end
    end
    return hidden
end

-- How many kinds of place the plate type shows in, and how many there are (the design row's eye: "4/4").
function Options:PlateVisibilityCount(plateType, settings)
    local hidden = HiddenPlaces(plateType or self.editorProfile, settings or Settings())
    return #V.PLACES - #hidden, #V.PLACES
end

-- The eye's tooltip line: "Shown in: World, Dungeons & raids, ...", or "Shown nowhere."
function Options:PlateVisibilityShownText(plateType, settings)
    settings = settings or Settings()
    local keys, shown = V.keys[RowType(plateType or self.editorProfile)], {}
    for _, place in ipairs(V.PLACES) do
        if not (settings and settings[keys[place]] == false) then shown[#shown + 1] = PLACE_HEADERS[place] end
    end
    if #shown == 0 then return L["Shown nowhere."] end
    return string.format(L["Shown in: %s"], table.concat(shown, ", "))
end

-- The section's summary: everywhere, or how many plate types something hides.
function Options.PlateVisibilitySummary()
    local settings, limited = Settings(), 0
    for _, plateType in ipairs(V.TYPES) do
        if RowType(plateType) == plateType and #HiddenPlaces(plateType, settings) > 0 then limited = limited + 1 end
    end
    if limited == 0 then return L["Everywhere"] end
    return string.format(L["Limited for %d"], limited)
end

-- Opens Settings › Behaviour & display at Where plates show (unfolded, scrolled to, flashed).
function Options:OpenPlateVisibilitySettings()
    self:EditorSettingsPage("plate")
    local section = self.editorPlateVisibilitySection
    if not (section and self.settingsSearch) then return false end
    return self.settingsSearch.Pick({ place = "studio", category = "plate", frame = section, section = section })
end

-- Places the grid's header texts and boxes for the row's width; returns a header text's width.
local function PlaceCells(row, width, columns, texts)
    local columnWidth = math.max(1, (width - GRID_LABEL_W) / math.max(1, #columns))
    for index, column in ipairs(columns) do
        local centre = GRID_LABEL_W + columnWidth * (index - 0.5)
        local cell = row.cells[column]
        if cell then
            cell:ClearAllPoints()
            cell:SetPoint("CENTER", row, "LEFT", centre, 0)
            if texts then cell:SetWidth(columnWidth - 4) end
        end
    end
    return columnWidth - 4
end

-- The headers wrap between words only: at the labels' size, or smaller (down to HEADER_SHRINK points
-- less) until every word of every shown header fits its column ("Battlegrounds" in a narrow column, or a
-- longer word in another language). WORD_SLACK keeps a word clear of the column's edges.
local HEADER_SHRINK, WORD_SLACK = 3, 2
local function FitHeaders(SK, header, columns, width)
    local function Fits(size)
        local fits = true
        for _, column in ipairs(columns) do
            local text, words = header.cells[column], PLACE_HEADERS[column]
            text:SetFont(SK.FONT_PATH, size)
            for word in words:gmatch("%S+") do
                text:SetText(word)
                if fits and text:GetStringWidth() > width - WORD_SLACK then fits = false end
            end
            text:SetText(words)
        end
        return fits
    end
    local size = SK.FONT
    while size > SK.FONT - HEADER_SHRINK and not Fits(size) do size = size - 1 end
    header.fontSize = size
end

-- Settings › Behaviour & display › Where plates show (Inspector's plate page builds the section).
function Options.BuildPlateVisibilitySettings(SK, section, Bind)
    Options.editorPlateVisibilitySection = section
    local allColumns = { "world", "dungeon", "pvp", "city", "inCombat", "noCombat" }
    local function Shown(column)
        return function() return Visibility.combatColumns or (column ~= "inCombat" and column ~= "noCombat") end
    end
    -- Headers: one short place name over each column.
    local header = CreateFrame("Frame", nil, section)
    header:SetSize(SK.WIDTH, HEADER_H)
    header.cells = {}
    for _, column in ipairs(allColumns) do
        local text = SK.Text(header, PLACE_HEADERS[column], "sub")
        text:SetJustifyH("CENTER")
        if text.SetWordWrap then text:SetWordWrap(true) end
        if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
        header.cells[column] = text
    end
    SK.OnWidth(header, function(width)
        local columns = Columns()
        for _, column in ipairs(allColumns) do header.cells[column]:SetShown(Shown(column)()) end
        FitHeaders(SK, header, columns, PlaceCells(header, width, columns, true))
    end)
    SK.Add(section, header)
    Options.editorPlateVisibilityHeader = header
    local rows = {}
    for _, plateType in ipairs(V.TYPES) do
        local row = SK.Row(section, PlateLabel(plateType))
        if row.label then row.label:SetWidth(GRID_LABEL_W - 4) end
        row.cells, row.plateType = {}, plateType
        for _, column in ipairs(allColumns) do
            local label = PLACE_HEADERS[column]
            local checkbox = Controls.Checkbox(row, {
                label = "", name = WidgetName("editor_shown_" .. plateType .. "_" .. column, "Checkbox"),
                get = function() return Get(plateType, column) end,
                set = function(on) return Set(plateType, column, on) end,
            })
            Controls.AttachTooltip(checkbox, string.format(L["%s: %s"], PlateLabel(plateType), label),
                { L["Ticked: shown there. Unticked: Blizzard's switch for these plates is turned off there and put back "
                    .. "when you leave."] })
            row.cells[column] = checkbox
            Bind("plate.shown." .. plateType .. "." .. column, checkbox)
        end
        SK.OnWidth(row, function(width)
            for _, column in ipairs(allColumns) do row.cells[column]:SetShown(Shown(column)()) end
            PlaceCells(row, width, Columns())
        end)
        -- Friendly NPCs have no row of their own on a client with one switch for every friendly plate.
        SK.Add(section, row, function() return RowType(plateType) == plateType end)
        rows[#rows + 1] = row
    end
    Options.editorPlateVisibilityRows = rows
    SK.Add(section, SK.Help(section, L["Hides a plate type's plates in the places you untick, through Blizzard's own "
        .. "switches, and shows them again when you leave. Friendly plates in dungeons & raids are Blizzard's: they can be "
        .. "shown or hidden here, but PlateSmith does not draw them."]))
    SK.Add(section, SK.Help(section, ENEMY_PLAYERS_NOTE))
    local sharedNote = SK.Help(section, L["This game client has one switch for all friendly plates, so Players and "
        .. "Friendly NPCs show and hide together (the Friendly row)."])
    SK.Add(section, sharedNote, Visibility.FriendlyShared)
    -- The labels follow the client (Friendly when the switch is shared).
    Options.RegisterControl({ Refresh = function()
        for _, row in ipairs(rows) do
            if row.label then row.label:SetText(PlateLabel(row.plateType)) end
        end
    end })
    return section
end

-- The eye's look: open while every place shows the plates, half while some do, shut while none do.
local function PaintEye(eye, state)
    state = state or eye.eyeState or "normal"
    eye.eyeState = state
    local look = eye.look or "shown"
    -- The half-open eye has no hover art; its count still lights.
    Theme.Place(eye.icon, "visibility-" .. look .. "-" .. (look == "mixed" and "normal" or state), eye, 0, 0)
    local colour = state == "hover" and EYE_HOVER or EYE_TEXT
    eye.count:SetTextColor(colour[1], colour[2], colour[3])
end

-- The design row's right end, before View: the tree's eye and how many kinds of place the open plate type
-- shows in ("4/4"). Its tooltip names them; a click opens Settings' Where plates show.
function Options:BuildPlateVisibilityEye(row, view)
    local eye = CreateFrame("Button", nil, row)
    eye:SetSize(64, 28)
    eye:SetPoint("RIGHT", view, "LEFT", -12, 0)
    eye.icon = eye:CreateTexture(nil, "ARTWORK")
    local count = eye:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetFont(self.studioChrome.FONT, 14)
    count:SetPoint("LEFT", eye, "LEFT", EYE_ICON + 3, 0)
    eye.count = count
    eye:SetScript("OnEnter", function(instance) PaintEye(instance, "hover") end)
    eye:SetScript("OnLeave", function(instance) PaintEye(instance, "normal") end)
    eye.tip = { "", L["Choose where each plate type shows: the world, dungeons & raids, battlegrounds & arenas, cities "
        .. "& inns."] }
    Controls.AttachTooltip(eye, L["Where plates show"], eye.tip)
    eye:SetScript("OnClick", function() Options:OpenPlateVisibilitySettings() end)
    self.editorPlateVisibilityEye = eye
    self:RefreshPlateVisibilityEye()
    return eye
end

function Options:RefreshPlateVisibilityEye(settings)
    local eye = self.editorPlateVisibilityEye
    if not eye then return end
    settings = settings or Settings()
    local shown, total = self:PlateVisibilityCount(self.editorProfile, settings)
    eye.look = shown == total and "shown" or shown == 0 and "hidden" or "mixed"
    eye.count:SetText(string.format("%d/%d", shown, total))
    eye:SetWidth(EYE_ICON + 3 + math.ceil(eye.count:GetStringWidth()) + 2)
    eye.tip[1] = { self:PlateVisibilityShownText(self.editorProfile, settings), 1, 1, 1 }
    -- Enemy players have no switch of their own.
    eye.tip[3] = self.editorProfile == "enemyPlayer" and ENEMY_PLAYERS_NOTE or nil
    PaintEye(eye)
end
