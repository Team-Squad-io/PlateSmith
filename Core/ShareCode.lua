local _, PS = ...

-- Transport only. A share code is the minified Blueprint JSON in Base64, so it
-- survives chat and forum pasting and every client can decode it. There is no
-- compression, so the decoded size is bounded by the code's length.
-- Share codes are "!PSB3!" and base64 JSON; "!PSB2!" codes (Blueprint version 2) still import.
local PREFIX = "!PSB3!"
local READABLE_PREFIXES = { "!PSB3!", "!PSB2!" }
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for index = 1, #ALPHABET do DECODE[ALPHABET:sub(index, index)] = index - 1 end
local MAX_CODE_BYTES = #PREFIX + math.ceil(PS.MAX_BLUEPRINT_BYTES / 3) * 4

local function Base64Encode(input)
    local output = {}
    for index = 1, #input, 3 do
        local first, second, third = input:byte(index, index + 2)
        local value = first * 65536 + (second or 0) * 256 + (third or 0)
        local a, b = math.floor(value / 262144) % 64 + 1, math.floor(value / 4096) % 64 + 1
        local c, d = math.floor(value / 64) % 64 + 1, value % 64 + 1
        output[#output + 1] = ALPHABET:sub(a, a) .. ALPHABET:sub(b, b)
            .. (second and ALPHABET:sub(c, c) or "=") .. (third and ALPHABET:sub(d, d) or "=")
    end
    return table.concat(output)
end

local function Base64Decode(input)
    if #input == 0 or #input % 4 ~= 0 or input:find("[^%w%+/%=]") then return nil end
    local output = {}
    for index = 1, #input, 4 do
        local a, b = input:sub(index, index), input:sub(index + 1, index + 1)
        local c, d = input:sub(index + 2, index + 2), input:sub(index + 3, index + 3)
        local first, second = DECODE[a], DECODE[b]
        local third, fourth = c ~= "=" and DECODE[c] or nil, d ~= "=" and DECODE[d] or nil
        if first == nil or second == nil or (c ~= "=" and third == nil)
            or (d ~= "=" and fourth == nil) or (c == "=" and d ~= "=")
            or ((c == "=" or d == "=") and index + 3 ~= #input) then return nil end
        local value = first * 262144 + second * 4096 + (third or 0) * 64 + (fourth or 0)
        output[#output + 1] = string.char(math.floor(value / 65536) % 256)
        if c ~= "=" then output[#output + 1] = string.char(math.floor(value / 256) % 256) end
        if d ~= "=" then output[#output + 1] = string.char(value % 256) end
    end
    return table.concat(output)
end

function PS.ExportShareCode()
    local json, reason = PS.ExportBlueprint(false)
    if not json then return nil, reason end
    return PREFIX .. Base64Encode(json)
end

function PS.DecodeShareCode(text)
    if type(text) ~= "string" then return nil, "share code must be text" end
    text = text:gsub("%s+", "")
    if #text > MAX_CODE_BYTES then return nil, "share code is too large" end
    local body
    for _, prefix in ipairs(READABLE_PREFIXES) do
        if text:sub(1, #prefix) == prefix then body = text:sub(#prefix + 1) break end
    end
    if not body then return nil, "not a PlateSmith share code" end
    local json = Base64Decode(body)
    if not json then return nil, "share code is damaged or incomplete" end
    return json
end

-- Import accepts a share code or the Blueprint JSON itself, pretty or minified.
local ImportDocument = PS.ImportBlueprint
function PS.ImportBlueprint(text, selection)
    if type(text) ~= "string" then return false, "blueprint must be text" end
    if text:match("^%s*!PSB") then
        local json, reason = PS.DecodeShareCode(text)
        if not json then return false, reason end
        text = json
    elseif not text:match("^%s*{") then
        return false, "paste a PlateSmith share code or Blueprint JSON"
    end
    return ImportDocument(text, selection)
end
