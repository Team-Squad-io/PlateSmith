-- Module sources for the existing custom parts (docs/MODULES.md, "Sources for custom parts"): a custom bar's fill from a
-- module's number token, a custom icon's picture from a module's reader. A part using one stores it as its text
-- ("{<id>}", source "template"), so profiles, designs, rules and Blueprints carry it as they carry any custom part;
-- Nameplates/Values.lua draws it on plates and Studio/Components.lua in the preview, both through BarPercent and
-- IconTexture below.
local _, PS = ...
local Args = assert(PS._Args, "PlateSmith Modules missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local IsReadable, HasValue = Secret.IsReadable, Secret.HasValue

local ModuleSources = {}
PS.ModuleSources = ModuleSources

local bars, icons = {}, {}
local MAX_LABEL, MAX_ERRORS = 80, 5

local function Label(label) return type(label) == "string" and label ~= "" and #label <= MAX_LABEL end
local function Sample(value) return value == nil or type(value) == "number" or type(value) == "string" end

local function Check(id, definition, what)
    local ok, reason = PS._StyleRange(definition)
    if not ok then return false, reason end
    ok, reason = PS.Template.CheckId(id, what)
    if not ok then return false, reason end
    if bars[id] or icons[id] then return false, "source is already registered: " .. id end
    if not Label(definition.label) then return false, what .. " needs a label of at most " .. MAX_LABEL .. " characters" end
    return true
end

-- A custom bar's fill: { label, token (default: the id), min = 0, max = 100 } over a number token, or with read (and
-- sample) to register that token here too. The bar shows (value - min) / (max - min); a protected value fills it only
-- for a 0 to 100 source, passed straight to the bar. true, or false and the reason.
function PS.RegisterBarSource(...)
    local id, definition = Args(...)
    local ok, reason = Check(id, definition, "bar source")
    if not ok then return false, reason end
    local low, high = definition.min or 0, definition.max or 100
    if type(low) ~= "number" or type(high) ~= "number" or low ~= low or high ~= high or low >= high then
        return false, "bar source needs min < max"
    end
    local token = definition.token or id
    if type(token) ~= "string" then return false, "bar source token must be a token's id" end
    if definition.read ~= nil then
        if token ~= id then return false, "a bar source with read is its own token" end
        ok, reason = PS.Template.RegisterToken(id, { kind = "number", read = definition.read, label = definition.label,
            sample = definition.sample })
        if not ok then return false, reason end
    end
    bars[id] = { id = id, kind = "bar", label = definition.label, token = token, min = low, max = high }
    return true
end

-- A custom icon's picture: { label, read = function(unit) -> texture (file ID or path) or nil, sample = texture }.
-- read runs under pcall when the plate renders (it may return a protected texture: it is only shown); five errors
-- turn the source off for the session. true, or false and the reason.
function PS.RegisterIconSource(...)
    local id, definition = Args(...)
    local ok, reason = Check(id, definition, "icon source")
    if not ok then return false, reason end
    if type(definition.read) ~= "function" then return false, "icon source needs read(unit)" end
    if not Sample(definition.sample) then return false, "icon source sample must be a texture path or file ID" end
    icons[id] = { id = id, kind = "icon", label = definition.label, read = definition.read, sample = definition.sample,
        errors = 0 }
    return true
end

function ModuleSources.Get(id) return bars[id] or icons[id] end
function ModuleSources.Bar(id) return bars[id] end
function ModuleSources.Icon(id) return icons[id] end

-- The sources of a kind ("bar" or "icon"), by label: { id, label }, for Studio's choices.
function ModuleSources.List(kind)
    local list = {}
    for id, source in pairs(kind == "icon" and icons or bars) do list[#list + 1] = { id = id, label = source.label } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- What a custom part stores for a source: its text.
function ModuleSources.Template(id) return "{" .. id .. "}" end

-- The source a bar or icon part uses, or nil: its kind's source named by its text. Each text is parsed once.
local parsed, parsedCount = {}, 0
function ModuleSources.SlotSource(slot)
    if type(slot) ~= "table" or slot.source ~= "template" or (slot.kind ~= "bar" and slot.kind ~= "icon") then return nil end
    local text = slot.template
    if type(text) ~= "string" then return nil end
    local id = parsed[text]
    if id == nil then
        if parsedCount >= 256 then parsed, parsedCount = {}, 0 end
        id = text:match("^{([%a%d%.]+)}$") or false
        parsed[text], parsedCount = id, parsedCount + 1
    end
    if not id then return nil end
    local source = slot.kind == "bar" and bars[id] or slot.kind == "icon" and icons[id] or nil
    return source and id or nil
end

-- The token a part's source reads (a bar's number token, an icon's own id), for what marks the plate (TemplateReaders).
function ModuleSources.SlotToken(slot)
    local id = ModuleSources.SlotSource(slot)
    if not id then return nil end
    return slot.kind == "bar" and bars[id].token or id
end

-- A bar's fill (0 to 100) from its token's value: readable numbers scaled by the source's range and clamped; a protected
-- value only for a 0 to 100 source (passed on to be shown); nil when there is nothing to show.
function ModuleSources.BarPercent(id, value)
    local source = bars[id]
    if not source or not HasValue(value) then return nil end
    if IsReadable(value) then
        if type(value) ~= "number" or value ~= value then return nil end
        local percent = (value - source.min) / (source.max - source.min) * 100
        if percent < 0 then return 0 end
        if percent > 100 then return 100 end
        return percent
    end
    if source.min == 0 and source.max == 100 then return value end
    return nil
end

-- An icon's texture for unit (nil: the part hides). Contained like a token's reader.
function ModuleSources.IconTexture(id, unit)
    local source = icons[id]
    if not source or source.disabled then return nil end
    local ok, texture = pcall(source.read, unit)
    if not ok then
        source.errors = source.errors + 1
        if source.errors == 1 then Chat.ReportError("icon source " .. id, texture) end
        if source.errors >= MAX_ERRORS then source.disabled = true end
        return nil
    end
    if IsReadable(texture) and type(texture) ~= "number" and type(texture) ~= "string" then return nil end
    return texture
end

-- Studio's preview: the icon's sample texture.
function ModuleSources.Sample(id)
    local source = icons[id]
    return source and source.sample
end
