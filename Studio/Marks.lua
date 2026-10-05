-- Studio's "changed here" marks: what the open design changes from World (Designs.ChangedAreas, read
-- once per settings revision), what the inspector's marks (the kit's ChangedMark) ask about an area,
-- their tooltips and Reset to World, and the dots on the tree's rows.
-- An area is Designs.Reset's: { kind = "option" | "entry" | "style" | "rules" | "slot" | "aura", key,
-- sub, field }; an option area's key may be a list of keys (a row that writes several options).
local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Designs = assert(PS.Designs, "PlateSmith Designs missing")

-- How many times the marks' state was worked out (tests: once per revision, not once per row).
Options.editorMarkBuilds = 0
local state = {}

local function Settings() return type(PS.GetSettings) == "function" and PS.GetSettings() or nil end

-- The design the marks are about: the open one, or for Enemy players their layer (the Enemies'
-- "players" design, marked against the Enemies' World).
local function MarkDesign(self)
    if self.editorProfile == "enemyPlayer" then return "enemy", Designs.PLAYERS end
    return self.editorProfile, self.editorDesign or "world"
end

-- The open design's changed areas (here; nil on World), and on World every stored design's (others:
-- { context, areas }), for the settings' revision now.
function Options:EditorChangedAreas()
    local db = Settings()
    local plateType, design = MarkDesign(self)
    if state.revision == Designs.revision and state.db == db and state.plateType == plateType and state.design == design then
        return state
    end
    state = { revision = Designs.revision, db = db, plateType = plateType, design = design, others = {} }
    if db and design ~= "world" then
        state.here = Designs.ChangedAreas(db, plateType, design)
    elseif db then
        for _, entry in ipairs(Designs.List(db, plateType)) do
            if entry.context ~= "world" and not entry.blizzard then
                state.others[#state.others + 1] = { context = entry.context,
                    areas = Designs.ChangedAreas(db, plateType, entry.context) }
            end
        end
    end
    self.editorMarkBuilds = self.editorMarkBuilds + 1
    -- Enemy players reset to what the Enemies have.
    if self.editorMarkConfig then
        self.editorMarkConfig.resetLabel = design == Designs.PLAYERS and L["Reset to Enemies"] or L["Reset to World"]
    end
    return state
end

-- The layout field the open view edits (an entry area's field).
function Options:EditorMarkField()
    return self:CurrentEditorVariant() == "names" and "namesLayout" or "layout"
end

-- A setting the whole profile shares (Inspector's SettingControl rows, the threat part boxes) has no
-- changed-here mark. While a design other than World is open (or Enemy players), a note under its row
-- (rows: under a block of them) says it changes every design. shown: the row's own visibility.
function Options:EditorSharedNoteShown()
    return self.editorProfile == "enemyPlayer" or (self.editorDesign or "world") ~= "world"
end

function Options.SharedSettingNote(K, section, shown, rows)
    local text = rows and L["The rows above are shared by all designs"] or L["Shared by all designs"]
    local note = K.Note(section, text)
    note:EnableMouse(true)
    PS.UI.Controls.AttachTooltip(note, text, { L["A setting of the whole profile: changing it here changes World and "
        .. "every other design and plate type too."] })
    K.Add(section, note, function() return Options:EditorSharedNoteShown() and (not shown or shown()) end)
    return note
end

-- An entry area of key in the open view's layout (sub: placement, eye, presence or label).
function Options:EditorEntryArea(key, sub)
    if not key then return nil end
    return { kind = "entry", key = key, sub = sub, field = self:EditorMarkField() }
end

local function EntryMarks(areas, area)
    local entries = areas.entries[area.field or "layout"]
    return entries and entries[area.key]
end

-- Whether areas (Designs.ChangedAreas) change area.
local function Has(areas, area)
    if not areas or type(area) ~= "table" then return false end
    local kind, key, sub = area.kind, area.key, area.sub
    if kind == "option" then
        if type(key) == "table" then
            for _, each in ipairs(key) do if areas.options[each] then return true end end
            return false
        end
        return areas.options[key] == true
    elseif kind == "entry" then
        local marks = EntryMarks(areas, area)
        if not marks then return false end
        return sub == nil or marks[sub] == true
    elseif kind == "style" or kind == "aura" then
        local fields = (kind == "style" and areas.styles or areas.auras)[key]
        if not fields then return false end
        if type(sub) == "table" then
            for _, each in ipairs(sub) do if fields[each] then return true end end
            return false
        end
        return sub == nil or fields[sub] == true
    elseif kind == "rules" then
        return areas.rules[key] == true
    elseif kind == "slot" then
        return areas.slots[key] == true
    end
    return false
end

-- A part only this design has has no World to go back to.
local function OnlyHere(areas, area)
    if area.kind ~= "entry" then return false end
    local marks = EntryMarks(areas, area)
    return marks ~= nil and marks.added == true
end

-- For the kit's ChangedMark: changed here, changed in another design (on World), and whether Reset
-- to World can put it back.
function Options:EditorMarkState(area)
    local marks = self:EditorChangedAreas()
    if marks.here then
        local changed = Has(marks.here, area)
        return changed, false, changed and not OnlyHere(marks.here, area)
    end
    for _, other in ipairs(marks.others) do
        if Has(other.areas, area) then return false, true, false end
    end
    return false, false, false
end

local function Number(value)
    local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
    return text
end

-- A value as the tooltip's "World: ..." names it.
local function Describe(value)
    if value == nil then return L["default"] end
    if value == true then return L["on"] end
    if value == false then return L["off"] end
    if type(value) == "number" then return Number(value) end
    if type(value) == "string" then return value end
    if type(value) == "table" and value.r then return "#" .. PS.Format.ColourToHex(value) end
    return L["its own"]
end

-- What World has for area (for Enemy players, the Enemies' World).
local function WorldText(self, area)
    local world = PS.GetPlateProfileSettings((MarkDesign(self)))
    if type(world) ~= "table" then return L["default"] end
    local kind, key, sub = area.kind, area.key, area.sub
    if kind == "option" then
        return Describe(world[type(key) == "table" and key[1] or key])
    elseif kind == "entry" then
        local layout = world[area.field or "layout"]
        local entry = type(layout) == "table" and layout[key]
        if type(entry) ~= "table" then return L["not on its plate"] end
        if sub == "eye" then return entry.visible == false and L["hidden"] or L["shown"] end
        if sub == "presence" then return entry.removed and L["not on its plate"] or L["on its plate"] end
        if sub == "label" then return entry.name or L["its standard name"] end
        return string.format(L["x %s, y %s"], Number(entry.x or 0), Number(entry.y or 0))
    elseif kind == "style" or kind == "aura" then
        local map = world[kind == "style" and "styles" or "auraLayouts"]
        local own = type(map) == "table" and map[key]
        local field = type(sub) == "table" and sub[1] or sub
        return Describe(type(own) == "table" and field and own[field] or nil)
    elseif kind == "rules" then
        local count = #(type(world.rules) == "table" and world.rules[key] or {})
        if count == 0 then return L["No rules"] end
        return count == 1 and L["1 rule"] or string.format(L["%d rules"], count)
    elseif kind == "slot" then
        local slot = type(world.valueSlots) == "table" and world.valueSlots[key]
        if type(slot) ~= "table" or slot.source == "off" then return L["not on its plate"] end
        return Describe(slot.kind or slot.source)
    end
    return L["default"]
end

-- The mark's tooltip lines: here, "Changed here (World: ...)"; on World, the designs that change it.
function Options:EditorMarkTip(area)
    local marks = self:EditorChangedAreas()
    if marks.here then
        if not Has(marks.here, area) then return nil end
        if OnlyHere(marks.here, area) then return { L["Changed here: only this design has it."] } end
        if self.editorProfile == "enemyPlayer" then
            return { string.format(L["Changed here (Enemies: %s)"], WorldText(self, area)) }
        end
        return { string.format(L["Changed here (World: %s)"], WorldText(self, area)) }
    end
    local labels = {}
    for _, other in ipairs(marks.others) do
        if Has(other.areas, area) then labels[#labels + 1] = Designs.LABELS[other.context] end
    end
    if #labels == 0 then return nil end
    return { string.format(L["Also changed in: %s"], table.concat(labels, ", ")) }
end

-- Reset to World for one area of the open design (each changed key of a list): a sparse design
-- drops it, a full one takes World's value and stays full. Studio follows.
function Options:ResetEditorMark(area)
    local plateType, design = MarkDesign(self)
    local marks = self:EditorChangedAreas()
    if design == "world" or not marks.here or type(area) ~= "table" then return false end
    local keys = type(area.key) == "table" and area.key or { area.key }
    local subs = type(area.sub) == "table" and area.sub or { area.sub or false }
    local done = false
    for _, key in ipairs(keys) do
        for _, sub in ipairs(subs) do
            local one = { kind = area.kind, key = key, sub = sub or nil, field = area.field }
            if Has(marks.here, one) and not OnlyHere(marks.here, one) and PS.ResetDesignArea(plateType, design, one) then
                done = true
            end
        end
    end
    if not done then return false end
    self:Refresh(true)
    self:RefreshEditorInspectorContext()
    if self.editorStyleRefresh then self.editorStyleRefresh() end
    return true
end

-- The inspector's areas: Option and Aura name one area; the rest are functions of the part (or
-- group) selected now, nil while there is none.
local function Selected() return Options.editorSelectedGroup or Options.selectedComponent end
Options.editorMarkAreas = {
    Option = function(key) return { kind = "option", key = key } end,
    Aura = function(kind, field) return { kind = "aura", key = kind, sub = field } end,
    Style = function(field) return function()
        local key = Options.selectedComponent
        return key and { kind = "style", key = key, sub = field } or nil
    end end,
    Entry = function(sub) return function() return Options:EditorEntryArea(Selected(), sub) end end,
    Part = function(kind) return function()
        local key = Options.selectedComponent
        return key and { kind = kind, key = key } or nil
    end end,
}

-- The kit's config.marks (Inspector's kit).
Options.editorMarkConfig = {
    State = function(area) return Options:EditorMarkState(area) end,
    Tip = function(area) return Options:EditorMarkTip(area) end,
    Reset = function(area) return Options:ResetEditorMark(area) end,
    resetLabel = L["Reset to World"],
}

-- A small gold diamond after a tree row's label: something of that part is changed here.
local DOT_SIZE = 7
local function Dot(row)
    if row.changedDot then return row.changedDot end
    local dot = row:CreateTexture(nil, "OVERLAY")
    dot:SetSize(DOT_SIZE, DOT_SIZE)
    if dot.SetRotation then dot:SetRotation(math.pi / 4) end
    local gold = Options.studioChrome.GOLD
    dot:SetColorTexture(gold[1], gold[2], gold[3], 1)
    dot:Hide()
    row.changedDot = dot
    return dot
end

local function PlaceDot(row, on)
    if not (on or row.changedDot) then return end
    local dot, label = Dot(row), row.label
    dot:ClearAllPoints()
    local width = label and label.GetStringWidth and label:GetStringWidth() or 0
    -- A label spanning the row (anchored at both ends) may cut its text short: the dot stays inside.
    local room = label and label:GetNumPoints() > 1 and label:GetWidth() or 0
    if room > 0 then width = math.min(width, room - DOT_SIZE - 6) end
    dot:SetPoint("LEFT", label or row, "LEFT", width + 6, 0)
    dot:SetShown(on and true or false)
end

-- The tree's dots: a part or group with any area changed here (an aura row's fields are its part's),
-- the Plate row with any option.
function Options:RefreshEditorTreeMarks()
    local here = self:EditorChangedAreas().here
    local parts, auras = here and here.parts or {}, here and here.auras or {}
    for key, button in pairs(self.editorComponentButtons or {}) do PlaceDot(button, parts[key] or auras[key]) end
    for key, header in pairs(self.editorCustomGroupHeaders or {}) do PlaceDot(header, parts[key]) end
    if self.editorPlateRow then PlaceDot(self.editorPlateRow, here and next(here.options) ~= nil) end
end

-- Every mark: the inspector's rows and the tree's dots.
function Options:RefreshEditorMarks()
    if self.inspectorKit and self.inspectorKit.RefreshMarks then self.inspectorKit.RefreshMarks() end
    self:RefreshEditorTreeMarks()
end
