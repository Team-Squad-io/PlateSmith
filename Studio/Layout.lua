local _, PS = ...

local Options = assert(PS.Options, "PlateSmith EditorComponents missing")
local catalog = assert(Options.editorCatalog)
local editorDefaults = catalog.editorDefaults
local editorOrder = catalog.editorOrder

-- The editor works on a complete copy of one layout so unsaved drags never
-- touch the live settings table.
local function CopyEditorLayout(source)
    local result = {}
    source = type(source) == "table" and source or editorDefaults
    for _, key in ipairs(editorOrder) do
        local fallback = editorDefaults[key]
        local position = type(source[key]) == "table" and source[key] or fallback
        local visible = fallback.visible
        if type(position.visible) == "boolean" then visible = position.visible end
        result[key] = {
            x = tonumber(position.x) or fallback.x,
            y = tonumber(position.y) or fallback.y,
            visible = visible ~= false,
            scale = tonumber(position.scale) or 1,
            attach = type(position.attach) == "string" and position.attach or nil,
            parent = type(position.parent) == "string" and position.parent or nil,
            order = tonumber(position.order),
            removed = position.removed == true or nil,
            free = position.free == true or nil,
            layer = tonumber(position.layer),
            name = type(position.name) == "string" and position.name or nil,
        }
    end
    -- Custom groups ride along: their offset, scale, name and order.
    for key, position in pairs(source) do
        if type(key) == "string" and key:match("^group%.%d+$") and type(position) == "table" then
            result[key] = { x = tonumber(position.x) or 0, y = tonumber(position.y) or 0, visible = true,
                scale = tonumber(position.scale) or 1, parent = type(position.parent) == "string" and position.parent or nil,
                name = position.name, order = position.order, stack = position.stack, gap = position.gap,
                layer = tonumber(position.layer) }
        end
    end
    return result
end

Options.editorBlueprint = { CopyLayout = CopyEditorLayout }
Options.editorLayout = CopyEditorLayout(editorDefaults)
