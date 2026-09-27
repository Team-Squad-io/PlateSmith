local _, PS = ...

-- Display formatting shared by plates, the threat windows, Blueprints, and
-- diagnostics. Inputs must already be readable; protected values go straight
-- to Blizzard's text sinks instead.
local Format = {}
PS.Format = Format

function Format.Abbreviate(value)
    if type(value) ~= "number" then return nil end
    local absolute = math.abs(value)
    if absolute >= 1000000 then return string.format("%.1fm", value / 1000000) end
    if absolute >= 1000 then return string.format("%.1fk", value / 1000) end
    return tostring(value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5))
end

function Format.Percent(value)
    return type(value) == "number" and string.format("%d%%", math.floor(value + 0.5)) or nil
end

function Format.SignedLead(value)
    if type(value) ~= "number" then return nil end
    return (value > 0 and "+" or "") .. Format.Abbreviate(value)
end

-- "88%  +1.2k", either half alone, or nil when neither is readable.
function Format.Threat(percent, lead)
    local percentText, leadText = Format.Percent(percent), Format.SignedLead(lead)
    if percentText and leadText then return percentText .. "  " .. leadText end
    return percentText or leadText
end

-- A colour channel or opacity: value as a number clamped to 0-1, else fallback.
function Format.Unit(value, fallback)
    return math.max(0, math.min(1, tonumber(value) or fallback))
end

function Format.ColourToHex(colour)
    local function Channel(value) return math.floor(Format.Unit(value, 0) * 255 + 0.5) end
    return string.format("%02x%02x%02x", Channel(colour.r), Channel(colour.g), Channel(colour.b))
end

local CHARACTER = "[%z\1-\127\194-\244][\128-\191]*"

-- UTF-8 aware: the number of characters in text.
function Format.Length(text)
    local count = 0
    for _ in text:gmatch(CHARACTER) do count = count + 1 end
    return count
end

-- UTF-8 aware: text cut to at most count characters and, when maxBytes is given, that many
-- bytes, never inside a character.
function Format.Truncate(text, count, maxBytes)
    -- A character is at least one byte, so text this short needs no cut.
    if #text <= count and (not maxBytes or #text <= maxBytes) then return text end
    local result, characters, bytes = {}, 0, 0
    for character in text:gmatch(CHARACTER) do
        characters, bytes = characters + 1, bytes + #character
        if characters > count or (maxBytes and bytes > maxBytes) then break end
        result[#result + 1] = character
    end
    return table.concat(result)
end

function Format.HexToColour(value)
    if type(value) ~= "string" or not value:match("^%x%x%x%x%x%x$") then return nil end
    return { r = tonumber(value:sub(1, 2), 16) / 255, g = tonumber(value:sub(3, 4), 16) / 255,
        b = tonumber(value:sub(5, 6), 16) / 255 }
end

function Format.Clock(stamp)
    if type(date) == "function" and type(stamp) == "number" and stamp > 0 then
        return date("%Y-%m-%d %H:%M:%S", stamp)
    end
    return "unknown time"
end
