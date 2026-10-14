local _, PS = ...

local Options = assert(PS.Options, "PlateSmith EditorComponents missing")
local catalog = assert(Options.editorCatalog)
local editorDefaults = catalog.editorDefaults
local editorOrder = catalog.editorOrder

-- One entry of the editor's copy, written into entry: a part's (position, its default fallback) or, without a
-- fallback, a custom group's. Every field is written (nil included), so entry holds nothing else after.
local function FillPart(entry, position, fallback)
    local visible = fallback.visible
    if type(position.visible) == "boolean" then visible = position.visible end
    entry.x = tonumber(position.x) or fallback.x
    entry.y = tonumber(position.y) or fallback.y
    entry.visible = visible ~= false
    entry.scale = tonumber(position.scale) or 1
    entry.attach = type(position.attach) == "string" and position.attach or nil
    entry.parent = type(position.parent) == "string" and position.parent or nil
    entry.order = tonumber(position.order)
    entry.removed = position.removed == true or nil
    entry.free = position.free == true or nil
    entry.layer = tonumber(position.layer)
    entry.name = type(position.name) == "string" and position.name or nil
    entry.stack, entry.gap = nil, nil
    return entry
end
local function FillGroup(entry, position)
    entry.x, entry.y, entry.visible = tonumber(position.x) or 0, tonumber(position.y) or 0, true
    entry.scale = tonumber(position.scale) or 1
    entry.parent = type(position.parent) == "string" and position.parent or nil
    entry.name, entry.order, entry.stack, entry.gap = position.name, position.order, position.stack, position.gap
    entry.layer = tonumber(position.layer)
    entry.attach, entry.removed, entry.free = nil, nil, nil
    return entry
end
local FIELDS = { "x", "y", "visible", "scale", "attach", "parent", "order", "removed", "free", "layer", "name", "stack", "gap" }

local function IsGroupKey(key) return type(key) == "string" and key:match("^group%.%d+$") ~= nil end

-- The editor works on a complete copy of one layout so unsaved drags never
-- touch the live settings table.
-- A new entry, made at once at the size most need (x, y, visible, scale, parent, order; filling an empty table grows
-- it step by step, and room for every field doubles it).
local function NewEntry()
    return { x = 0, y = 0, visible = true, scale = 1, parent = false, order = false }
end

local function CopyEditorLayout(source)
    local result = {}
    source = type(source) == "table" and source or editorDefaults
    for _, key in ipairs(editorOrder) do
        local fallback = editorDefaults[key]
        local position = type(source[key]) == "table" and source[key] or fallback
        result[key] = FillPart(NewEntry(), position, fallback)
    end
    -- Custom groups ride along: their offset, scale, name and order.
    for key, position in pairs(source) do
        if IsGroupKey(key) and type(position) == "table" then result[key] = FillGroup(NewEntry(), position) end
    end
    return result
end

-- Whether copy is what CopyEditorLayout(source) makes, field for field, without making it (Studio's refresh keeps
-- its copy then: a drag that changed it in place and was not saved does not match).
local scratch = {}
local function Same(entry, expected)
    if type(entry) ~= "table" then return false end
    for _, field in ipairs(FIELDS) do
        if entry[field] ~= expected[field] then return false end
    end
    return true
end
local function EditorLayoutMatches(copy, source)
    if type(copy) ~= "table" then return false end
    source = type(source) == "table" and source or editorDefaults
    local count = 0
    for _, key in ipairs(editorOrder) do
        local fallback = editorDefaults[key]
        local position = type(source[key]) == "table" and source[key] or fallback
        if not Same(copy[key], FillPart(scratch, position, fallback)) then return false end
        count = count + 1
    end
    for key, position in pairs(source) do
        if IsGroupKey(key) and type(position) == "table" then
            if not Same(copy[key], FillGroup(scratch, position)) then return false end
            count = count + 1
        end
    end
    for _ in pairs(copy) do count = count - 1 end
    return count == 0
end

Options.editorBlueprint = { CopyLayout = CopyEditorLayout, LayoutMatches = EditorLayoutMatches }
Options.editorLayout = CopyEditorLayout(editorDefaults)
