local _, PS = ...

-- Shared JSON for Blueprints and diagnostics. Encoding is deterministic
-- (sorted object keys) so an unchanged profile always exports the same text.
-- Decoding is a strict parser with size and depth limits; it never evaluates Lua.
local Json = {}
PS.Json = Json

local arrayMarker = {}

function Json.Array(values)
    return setmetatable(values or {}, arrayMarker)
end

-- SavedVariables drop metatables, so a stored array is recognised by its keys;
-- the marker is only needed to keep an empty array from encoding as {}.
function Json.IsArray(value)
    if getmetatable(value) == arrayMarker then return true end
    local count = #value
    if count == 0 then return false end
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then return false end
    end
    return true
end

local function EncodeString(value)
    local escaped = tostring(value):gsub('[%z\1-\31\\"]', function(char)
        if char == '\\' then return '\\\\' end
        if char == '"' then return '\\"' end
        if char == '\n' then return '\\n' end
        if char == '\r' then return '\\r' end
        if char == '\t' then return '\\t' end
        return string.format('\\u%04x', string.byte(char))
    end)
    return '"' .. escaped .. '"'
end

local function EncodeNumber(value)
    if value ~= value or value == math.huge or value == -math.huge then return "null" end
    if value == math.floor(value) and math.abs(value) < 1e15 then return string.format("%d", value) end
    return string.format("%.14g", value)
end

local function EncodeValue(value, pretty, depth, out)
    local kind = type(value)
    if kind == "string" then out[#out + 1] = EncodeString(value) return end
    if kind == "boolean" then out[#out + 1] = value and "true" or "false" return end
    if kind == "number" then out[#out + 1] = EncodeNumber(value) return end
    if kind ~= "table" then out[#out + 1] = "null" return end

    local array = Json.IsArray(value)
    local count = array and #value or 0
    local keys
    if not array then
        keys = {}
        for key in pairs(value) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        count = #keys
    end
    if count == 0 then out[#out + 1] = array and "[]" or "{}" return end

    local newline = pretty and ("\n" .. string.rep("  ", depth + 1)) or ""
    out[#out + 1] = array and "[" or "{"
    for index = 1, count do
        if index > 1 then out[#out + 1] = "," end
        out[#out + 1] = newline
        if array then
            EncodeValue(value[index], pretty, depth + 1, out)
        else
            local key = keys[index]
            out[#out + 1] = EncodeString(key)
            out[#out + 1] = pretty and ": " or ":"
            local child = value[key]
            if child == nil then child = value[tonumber(key)] end
            EncodeValue(child, pretty, depth + 1, out)
        end
    end
    if pretty then out[#out + 1] = "\n" .. string.rep("  ", depth) end
    out[#out + 1] = array and "]" or "}"
end

function Json.Encode(value, pretty)
    local out = {}
    EncodeValue(value, pretty and true or false, 0, out)
    return table.concat(out)
end

local escapes = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function Utf8(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

-- Returns value or nil, reason. Objects reject duplicate keys; arrays are
-- marked so they re-encode as arrays.
function Json.Decode(text, maxBytes, maxDepth)
    if type(text) ~= "string" then return nil, "JSON must be text" end
    if #text > (maxBytes or 65536) then return nil, "JSON is too large" end
    maxDepth = maxDepth or 16
    local position = 1
    local length = #text

    local function Fail(message) error({ jsonError = message .. " at character " .. position }, 0) end
    local function SkipSpace()
        position = text:find("[^ \t\r\n]", position) or length + 1
    end

    local ParseValue

    local function ParseString()
        position = position + 1
        local parts = {}
        while true do
            local stop = text:find('["\\%z\1-\31]', position)
            if not stop then Fail("unterminated string") end
            parts[#parts + 1] = text:sub(position, stop - 1)
            local char = text:sub(stop, stop)
            if char == '"' then
                position = stop + 1
                return table.concat(parts)
            elseif char == "\\" then
                local escape = text:sub(stop + 1, stop + 1)
                if escape == "u" then
                    local hex = text:sub(stop + 2, stop + 5)
                    if not hex:match("^%x%x%x%x$") then Fail("invalid unicode escape") end
                    local code = tonumber(hex, 16)
                    if code >= 0xD800 and code <= 0xDFFF then Fail("unsupported surrogate escape") end
                    parts[#parts + 1] = Utf8(code)
                    position = stop + 6
                elseif escapes[escape] then
                    parts[#parts + 1] = escapes[escape]
                    position = stop + 2
                else
                    Fail("invalid escape")
                end
            else
                Fail("control character in string")
            end
        end
    end

    local function Digits()
        local digits = text:match("^%d+", position)
        if not digits then Fail("invalid number") end
        position = position + #digits
        return digits
    end

    local function ParseNumber()
        local start = position
        if text:sub(position, position) == "-" then position = position + 1 end
        local whole = Digits()
        if #whole > 1 and whole:sub(1, 1) == "0" then Fail("invalid number") end
        if text:sub(position, position) == "." then
            position = position + 1
            Digits()
        end
        if text:sub(position, position):match("[eE]") then
            position = position + 1
            if text:sub(position, position):match("[%+%-]") then position = position + 1 end
            Digits()
        end
        return tonumber(text:sub(start, position - 1))
    end

    local function ParseContainer(depth, closing)
        if depth >= maxDepth then Fail("JSON is nested too deeply") end
        position = position + 1
        local isArray = closing == "]"
        local result = isArray and Json.Array() or {}
        SkipSpace()
        if text:sub(position, position) == closing then
            position = position + 1
            return result
        end
        while true do
            SkipSpace()
            if isArray then
                result[#result + 1] = ParseValue(depth + 1)
            else
                if text:sub(position, position) ~= '"' then Fail("expected a key") end
                local key = ParseString()
                if result[key] ~= nil then Fail("duplicate key " .. key) end
                SkipSpace()
                if text:sub(position, position) ~= ":" then Fail("expected ':'") end
                position = position + 1
                SkipSpace()
                result[key] = ParseValue(depth + 1)
            end
            SkipSpace()
            local separator = text:sub(position, position)
            position = position + 1
            if separator == closing then return result end
            if separator ~= "," then Fail("expected ',' or '" .. closing .. "'") end
        end
    end

    ParseValue = function(depth)
        SkipSpace()
        local char = text:sub(position, position)
        if char == "{" then return ParseContainer(depth, "}") end
        if char == "[" then return ParseContainer(depth, "]") end
        if char == '"' then return ParseString() end
        if char == "-" or char:match("%d") then return ParseNumber() end
        if text:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        end
        if text:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        end
        -- Lua tables cannot hold nil, so null would silently drop keys and shift arrays.
        if text:sub(position, position + 3) == "null" then Fail("null is not supported") end
        Fail("unexpected input")
    end

    local ok, result = pcall(function()
        local value = ParseValue(0)
        SkipSpace()
        if position <= length then Fail("unexpected trailing input") end
        return value
    end)
    if ok then return result end
    if type(result) == "table" and result.jsonError then return nil, result.jsonError end
    return nil, tostring(result)
end
