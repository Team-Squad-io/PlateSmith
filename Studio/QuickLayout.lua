local _, PS = ...
local L = PS.L

-- Quick layout: named places around the plate's main part (the health bar; the name on a
-- names-only layout), for a player who would rather pick than drag. A pick writes ordinary layout
-- (a pin to an edge, or the centre of the bar), so the part stays editable in Studio afterwards.
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Schema = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local catalog = assert(Options.editorCatalog)
local editorOrder = catalog.editorOrder

local QuickLayout = {}
PS.QuickLayout = QuickLayout

-- Only places the placement model draws exactly: the four edges (a pin, which follows the main
-- part's size) and its centre. A corner or an inside end would need an offset worked out from
-- today's sizes, which would drift when a bar or text changes. An edge takes a line of parts, each
-- pinned beyond the last (a hidden one passes its place on, as pins do); the centre takes one.
-- Where the main part sits in a group that stacks towards an edge (the template's Bars stack
-- under the health bar), that edge is the rest of the stack instead, so a part there closes up
-- under an idle cast bar as the template's own text does.
local SLOTS = {
    { key = "top", edge = "top", label = L["Top"] },
    { key = "bottom", edge = "bottom", label = L["Bottom"] },
    { key = "left", edge = "left", label = L["Left"] },
    { key = "right", edge = "right", label = L["Right"] },
    { key = "centre", centre = true, label = L["Centre"] },
}
local SLOT_BY_KEY = {}
for _, slot in ipairs(SLOTS) do SLOT_BY_KEY[slot.key] = slot end
QuickLayout.SLOTS = SLOTS
QuickLayout.MAX_ROWS = 6
-- A new pin's gap out from the edge (Studio's Behaviour pins alike), and which offset runs along
-- the edge (moved off zero: placed by hand) or out from it (the gap, which may be anything).
local GAP = { top = { 0, 4 }, bottom = { 0, -4 }, left = { -4, 0 }, right = { 4, 0 } }
local ALONG = { top = "x", bottom = "x", left = "y", right = "y" }
local OUT = { top = "y", bottom = "y", left = "x", right = "x" }
QuickLayout.GAP = GAP

local function Number(value) return tonumber(value) or 0 end
local function Shown(position) return position.visible ~= false and not position.removed end
local function AlwaysUsable() return true end

local function IsUnder(layout, key, ancestor)
    local current, depth = layout[key] and layout[key].parent, 0
    while current and depth <= Schema.MAX_DEPTH do
        if current == ancestor then return true end
        current, depth = layout[current] and layout[current].parent, depth + 1
    end
    return false
end

local function Depth(layout, key)
    local depth, current = 0, layout[key] and layout[key].parent
    while current and depth <= Schema.MAX_DEPTH do
        depth, current = depth + 1, layout[current] and layout[current].parent
    end
    return depth
end

local function Height(layout, key, guard)
    if guard > Schema.MAX_DEPTH then return guard end
    local height = 0
    for child, position in pairs(layout) do
        if type(position) == "table" and position.parent == key then
            height = math.max(height, 1 + Height(layout, child, guard + 1))
        end
    end
    return height
end

local function ChildrenOf(layout)
    local children = {}
    for key, position in pairs(layout) do
        if type(position) == "table" and position.parent and not position.removed and not Schema.IsGroupKey(key) then
            children[position.parent] = children[position.parent] or {}
            table.insert(children[position.parent], key)
        end
    end
    return children
end

-- The parts along one edge, nearest first: pinned to the main part on that edge (several may fan
-- out at different gaps), each followed by what is pinned beyond it on the same edge.
local function EdgeOccupants(layout, children, anchor, edge, usable)
    local list, seen = {}, { [anchor] = true }
    local function Walk(node, depth)
        if depth > Schema.MAX_DEPTH then return end
        local line = {}
        for _, key in ipairs(children[node] or {}) do
            if layout[key].attach == edge and not seen[key] then line[#line + 1] = key end
        end
        table.sort(line, function(left, right)
            local a, b = math.abs(Number(layout[left][OUT[edge]])), math.abs(Number(layout[right][OUT[edge]]))
            if a ~= b then return a < b end
            return left < right
        end)
        for _, key in ipairs(line) do
            seen[key] = true
            if Shown(layout[key]) and usable(key) then
                list[#list + 1] = { key = key, custom = Number(layout[key][ALONG[edge]]) ~= 0 }
            end
            Walk(key, depth + 1)
        end
    end
    Walk(anchor, 0)
    return list
end

-- The centre's part: unpinned on the main part at no offset; else one placed there and moved by
-- hand (Custom). Returns it (or nil) and every shown part exactly on the centre.
local function CentreOccupant(layout, children, anchor, usable)
    local exact, moved = {}, {}
    for _, key in ipairs(children[anchor] or {}) do
        local position = layout[key]
        if not position.attach and Shown(position) and usable(key) then
            if Number(position.x) == 0 and Number(position.y) == 0 then exact[#exact + 1] = key else moved[#moved + 1] = key end
        end
    end
    Schema.SortByTreeOrder(layout, exact)
    Schema.SortByTreeOrder(layout, moved)
    if exact[1] then return { key = exact[1], custom = false }, exact end
    if moved[1] then return { key = moved[1], custom = true }, exact end
    return nil, exact
end

-- The group the main part stacks in towards edge, or nil.
local STACK_EDGE = { down = "bottom", up = "top", right = "right", left = "left" }
local function StackGroup(layout, anchor, edge)
    local parent = layout[anchor].parent
    local group = parent and Schema.IsGroupKey(parent) and layout[parent]
    if type(group) == "table" and STACK_EDGE[group.stack] == edge then return parent end
    return nil
end

-- Every child of group in tree order (hidden ones too), without except.
local function StackMembers(layout, group, except)
    local members = {}
    for key, position in pairs(layout) do
        if key ~= except and type(position) == "table" and position.parent == group then members[#members + 1] = key end
    end
    return Schema.SortByTreeOrder(layout, members)
end

-- The stack after the main part: its shown parts, a free one (moved by hand) or one off the
-- stack's line across it being Custom.
local function StackOccupants(layout, anchor, group, usable)
    local list, after = {}, false
    local across = ALONG[STACK_EDGE[layout[group].stack]]
    for _, key in ipairs(StackMembers(layout, group)) do
        local position = layout[key]
        if key == anchor then
            after = true
        elseif after and not Schema.IsGroupKey(key) and Shown(position) and usable(key) then
            list[#list + 1] = { key = key, custom = position.free == true or Number(position[across]) ~= 0 }
        end
    end
    return list
end

-- What each place holds in layout (usable(key): the part is used by this plate type): slots[key]
-- (a list of { key, custom }), where[part] = { slot, index }, and free (shown parts in no slot).
function QuickLayout.Read(layout, anchor, usable)
    usable = usable or AlwaysUsable
    local state = { anchor = anchor, slots = {}, where = {}, free = {} }
    if type(layout) ~= "table" or type(layout[anchor]) ~= "table" or layout[anchor].removed then
        state.unavailable = true
        for _, slot in ipairs(SLOTS) do state.slots[slot.key] = {} end
        return state
    end
    local children = ChildrenOf(layout)
    for _, slot in ipairs(SLOTS) do
        local list
        if slot.centre then
            local occupant = CentreOccupant(layout, children, anchor, usable)
            list = { occupant }
        else
            local group = StackGroup(layout, anchor, slot.edge)
            list = group and StackOccupants(layout, anchor, group, usable)
                or EdgeOccupants(layout, children, anchor, slot.edge, usable)
        end
        state.slots[slot.key] = list
        for index, occupant in ipairs(list) do state.where[occupant.key] = { slot = slot.key, index = index } end
    end
    for key, position in pairs(layout) do
        if type(position) == "table" and key ~= anchor and not Schema.IsGroupKey(key) and Shown(position)
            and usable(key) and not state.where[key] then
            state.free[#state.free + 1] = key
        end
    end
    Schema.SortByTreeOrder(layout, state.free)
    return state
end

local function LastOrder(layout, parentKey, except)
    local last = 0
    for key, position in pairs(layout) do
        if key ~= except and type(position) == "table" and position.parent == parentKey then
            last = math.max(last, Number(position.order))
        end
    end
    return math.min(99, last + 1)
end

-- Writes one place's parts (keys, in order) back into layout. A part that kept its spot (the same
-- part before it, stayed[key]) keeps its offsets, so a template's wider gap or a hand-placed part
-- stays as it is; one that moved, or is in reset, takes the place's own spot: the standard gap
-- beyond the part before it, 0 across a stack's line, or the bar's centre.
local function Rewrite(layout, slot, keys, anchor, old, stayed, reset)
    local group = not slot.centre and StackGroup(layout, anchor, slot.edge)
    local function Fresh(key) return reset[key] or not stayed[key] end
    if group then
        local inLine, before, after, seen = {}, {}, {}, false
        for _, key in ipairs(keys) do inLine[key] = true end
        for _, member in ipairs(StackMembers(layout, group)) do
            if not inLine[member] then
                if seen then after[#after + 1] = member else before[#before + 1] = member end
                if member == anchor then seen = true end
            end
        end
        local order = before
        for _, key in ipairs(keys) do order[#order + 1] = key end
        for _, member in ipairs(after) do order[#order + 1] = member end
        for place, member in ipairs(order) do layout[member].order = math.min(place, 99) end
        for _, key in ipairs(keys) do
            local position = layout[key]
            position.parent, position.attach = group, nil
            if Fresh(key) then position.x, position.y, position.free = 0, 0, nil end
        end
    elseif slot.centre then
        local key = keys[1]
        if key then
            local position = layout[key]
            if Fresh(key) or old[key].parent ~= anchor or old[key].attach then position.x, position.y = 0, 0 end
            position.parent, position.attach, position.free = anchor, nil, nil
            position.order = LastOrder(layout, anchor, key)
        end
    else
        -- Off their old parents first, so the new line cannot loop through them.
        for _, key in ipairs(keys) do layout[key].parent = anchor end
        for place, key in ipairs(keys) do
            local position, parent = layout[key], keys[place - 1] or anchor
            if Fresh(key) or old[key].parent ~= parent or old[key].attach ~= slot.edge then
                position.x, position.y = GAP[slot.edge][1], GAP[slot.edge][2]
            end
            position.parent, position.attach, position.free = parent, slot.edge, nil
            position.order = LastOrder(layout, parent, key)
        end
    end
end

-- Puts key in a place in layout (changed in place: pass a copy), shown. index is the row picked
-- (past the last: the end of the line). Within its own line key moves to that row and the rest
-- shift. From another place onto a taken row the two swap; from no place, the row's part is
-- hidden. The centre takes one part. Picking the row's own part again, when it was moved by hand,
-- puts it back on the place's own spot. What key leaves closes up; parts pinned to key on another
-- edge (a level beside a name) go with it. Returns true, or false when the place cannot take key
-- (the main part itself, a group, a part the main part sits under, or deeper than allowed).
function QuickLayout.Place(layout, key, slotKey, index, anchor, usable)
    usable = usable or AlwaysUsable
    local slot, position = SLOT_BY_KEY[slotKey], type(layout) == "table" and layout[key]
    if not slot or type(position) ~= "table" or key == anchor or Schema.IsGroupKey(key)
        or type(layout[anchor]) ~= "table" or layout[anchor].removed or IsUnder(layout, anchor, key) then
        return false
    end
    local state = QuickLayout.Read(layout, anchor, usable)
    local lists, old, stayed = {}, {}, {}
    for name, list in pairs(state.slots) do
        lists[name], stayed[name] = {}, {}
        for place, occupant in ipairs(list) do
            lists[name][place] = occupant.key
            stayed[name][occupant.key] = true
        end
    end
    for part in pairs(layout) do
        if type(layout[part]) == "table" then old[part] = { parent = layout[part].parent, attach = layout[part].attach } end
    end
    local list, from, reset = lists[slotKey], state.where[key], {}
    index = math.max(1, math.min(index or (#list + 1), #list + 1))
    local occupant = list[index]
    if occupant == key then
        if not state.slots[slotKey][index].custom then
            position.visible, position.removed = true, nil
            return true
        end
        reset[key] = true
    else
        if from then table.remove(lists[from.slot], from.index) end
        if from and from.slot == slotKey then
            table.insert(list, math.min(index, #list + 1), key)
        elseif occupant then
            if from then table.insert(lists[from.slot], from.index, occupant) else layout[occupant].visible = false end
            list[index] = key
        else
            list[#list + 1] = key
        end
        if slot.centre then
            -- One part: anything else exactly on the centre is hidden too.
            local _, exact = CentreOccupant(layout, ChildrenOf(layout), anchor, usable)
            for _, other in ipairs(exact) do if other ~= key and other ~= occupant then layout[other].visible = false end end
        end
    end
    position.visible, position.removed = true, nil
    local touched = { [slotKey] = true }
    if from then touched[from.slot] = true end
    for name in pairs(touched) do
        Rewrite(layout, SLOT_BY_KEY[name], lists[name], anchor, old, stayed[name], reset)
    end
    for name in pairs(touched) do
        for _, part in ipairs(lists[name]) do
            if IsUnder(layout, anchor, part) or Depth(layout, part) + Height(layout, part, 0) > Schema.MAX_DEPTH then
                return false
            end
        end
    end
    return true
end
-- Empties a row: its part is hidden (its eye off), so what is pinned beyond it closes up.
function QuickLayout.Clear(layout, slotKey, index, anchor, usable)
    local list = SLOT_BY_KEY[slotKey] and QuickLayout.Read(layout, anchor, usable).slots[slotKey]
    local occupant = list and list[index or 1]
    if not occupant then return false end
    layout[occupant.key].visible = false
    return true
end

-- Studio's side: the main part and the rules of the plate type and layout Studio edits.

function Options:QuickLayoutAnchor()
    local variant = self:CurrentEditorVariant()
    return (variant == "names" or variant == "dungeon") and "name" or "health"
end

function Options:QuickLayoutUsable()
    self.quickLayoutUsable = self.quickLayoutUsable or function(key) return self:IsEditorComponentRelevant(key) end
    return self.quickLayoutUsable
end

function Options:QuickLayoutState()
    return QuickLayout.Read(self.editorLayout, self:QuickLayoutAnchor(), self:QuickLayoutUsable())
end

-- A row's pick: a part's key, "none" (hide the row's part), or "new:<source>" (a new custom value
-- showing source). One layout write, then the preview, tree and inspector follow. Save keeps it.
function Options:SetQuickLayoutSlot(slotKey, index, choice)
    if not SLOT_BY_KEY[slotKey] or type(choice) ~= "string" or choice == "custom" then return false end
    local variant, profileKey = self:CurrentEditorVariant(), self:EditorTarget()
    local anchor, usable = self:QuickLayoutAnchor(), self:QuickLayoutUsable()
    if SLOT_BY_KEY[slotKey].centre and anchor == "name" then return false end
    local created
    local source = choice:match("^new:(.+)$")
    if source then
        created = self:EditorFreeValueSlot()
        if not created then return false end
        PS.SetPlateValueSlot(profileKey, created, "kind", nil)
        if not PS.SetPlateValueSlot(profileKey, created, "source", source) then return false end
        self:ReloadEditorLayoutCopy()
        choice = created
    end
    local layout = PS.GetLayout(profileKey, variant)
    local ok
    if choice == "none" then
        ok = QuickLayout.Clear(layout, slotKey, index, anchor, usable)
    else
        local relevant = self:IsEditorComponentRelevant(choice, nil, true)
        ok = relevant and QuickLayout.Place(layout, choice, slotKey, index, anchor, function(key)
            return key == choice or usable(key)
        end)
    end
    if ok then ok = PS.SetLayout(layout, profileKey, variant) end
    if not ok and created then PS.ResetValueSlot(profileKey, created) end
    self:Refresh(true)
    return ok and true or false
end

local function RowLabel(slot, index)
    if index == 1 then return slot.label end
    return string.format(L["%s %d"], slot.label, index)
end

-- The inspector's Quick layout section, under the Plate row's own: one dropdown per place (an
-- edge shows a row per part in its line and one more to add to it).
function Options:BuildQuickLayoutSection(page)
    local K = self.inspectorKit
    local options = self
    local section = K.Section(page, L["QUICK LAYOUT"])
    local view = { state = nil, candidates = {} }
    options.editorQuickLayout = { section = section, rows = {}, rowFrames = {}, view = view }
    local intro = K.Add(section, K.Help(section, ""))
    local unavailable = K.Add(section, K.Help(section, ""), function() return view.state and view.state.unavailable end)
    local function Occupant(slot, index)
        local list = view.state and view.state.slots[slot.key]
        return list and list[index]
    end
    local function RowShown(slot, index)
        local state = view.state
        if not state or state.unavailable then return false end
        if slot.centre then return index == 1 and state.anchor ~= "name" end
        return index <= math.min(#state.slots[slot.key] + 1, QuickLayout.MAX_ROWS)
    end
    local function Choices(slot, index)
        local list = { { value = "none", label = L["None"], help = L["Nothing here: the part in this place is hidden."] } }
        local occupant = Occupant(slot, index)
        if occupant and occupant.custom then
            list[#list + 1] = { value = "custom",
                label = string.format(L["Custom (%s)"], options:EditorComponentLabel(occupant.key)),
                help = L["Moved off this place by hand. Pick the part again to put it back."] }
        end
        for _, key in ipairs(view.candidates) do
            local label = options:EditorComponentLabel(key)
            local where = view.state and view.state.where[key]
            if where and not (where.slot == slot.key and where.index == index) then
                label = string.format(L["%s (%s)"], label, RowLabel(SLOT_BY_KEY[where.slot], where.index))
            end
            list[#list + 1] = { value = key, label = label }
        end
        if options:EditorFreeValueSlot() then
            local values = {}
            for _, choice in ipairs(catalog.valueSourceChoices or {}) do
                values[#values + 1] = { value = "new:" .. choice.value, label = choice.label }
            end
            list[#list + 1] = { label = L["New value"], children = values }
        end
        return list
    end
    for _, slot in ipairs(SLOTS) do
        for index = 1, slot.centre and 1 or QuickLayout.MAX_ROWS do
            local row, dropdown = K.DropdownRow(section, RowLabel(slot, index), {
                name = "PlateSmithQuickLayout" .. slot.key .. index .. "Dropdown",
                choices = function() return Choices(slot, index) end,
                get = function()
                    local occupant = Occupant(slot, index)
                    return occupant and (occupant.custom and "custom" or occupant.key) or "none"
                end,
                set = function(value) options:SetQuickLayoutSlot(slot.key, index, value) end,
            })
            options.editorQuickLayout.rows[slot.key .. index] = dropdown
            options.editorQuickLayout.rowFrames[slot.key .. index] = row
            K.Add(section, row, function() return RowShown(slot, index) end)
        end
    end
    K.Add(section, K.Help(section, L["Top, Bottom, Left and Right line up outwards (Top 2 sits above Top); under stacked "
        .. "bars, Bottom joins their stack. The centre takes one part. A pick moves the part there and shows it; None "
        .. "hides it. It is ordinary layout: select a part to drag or fine-tune it. Save keeps it, Revert undoes it."]),
        function() return view.state and not view.state.unavailable end)
    local free = K.Add(section, K.Help(section, ""), function() return view.state and #view.state.free > 0 end)
    local quick = options.editorQuickLayout
    quick.intro, quick.unavailable, quick.free = intro, unavailable, free
    -- Read again each time the inspector lays it out: after a pick, a drag, Revert or another plate type.
    local measure = section.Measure
    section.Measure = function(frame)
        options:RefreshQuickLayout()
        return measure(frame)
    end
    K.Add(page, section, function()
        local selection = options.editorInspectorSelection or {}
        return selection.context == "plate" or (selection.context == nil and selection.group == nil)
    end)
    return section
end

-- The section's state, its texts and its dropdowns, from Studio's layout copy.
function Options:RefreshQuickLayout()
    local quick = self.editorQuickLayout
    if not quick then return nil end
    local state = self:QuickLayoutState()
    quick.view.state = state
    -- Every part this plate type uses, deleted ones too (a pick puts one back).
    local candidates = {}
    for _, key in ipairs(editorOrder) do
        if key ~= state.anchor and self:IsEditorComponentRelevant(key, nil, true) then candidates[#candidates + 1] = key end
    end
    quick.view.candidates = candidates
    local design = PS.Designs.LABELS[self.editorDesign] or L["World"]
    local context = self.editorDesign ~= "dungeon" and self:CurrentEditorVariant() == "names"
        and string.format(L["%s, names only"], design) or design
    local plate = self:EditorPlateLabel(self.editorProfile)
    quick.intro.text:SetText(string.format(state.anchor == "name" and L["Places around the name, for %s (%s)."]
        or L["Places around the health bar, for %s (%s)."], plate, context))
    quick.unavailable.text:SetText(state.anchor == "name" and L["Add the name back (+ Add) to use Quick layout."]
        or L["Add the health bar back (+ Add) to use Quick layout."])
    local names = {}
    for _, key in ipairs(state.free) do names[#names + 1] = self:EditorComponentLabel(key) end
    quick.free.text:SetText(string.format(L["Placed freely: %s."], table.concat(names, ", ")))
    for _, dropdown in pairs(quick.rows) do dropdown:Refresh() end
    return state
end
