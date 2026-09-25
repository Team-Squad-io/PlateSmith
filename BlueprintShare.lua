local _, PS = ...

-- Transport only: keep the validated PS1 schema and its selective import semantics.
local PREFIX = "!PSB1!"
local MAX_LEGACY_BYTES = 8192
local MAX_SHARE_BYTES = 16384
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for index = 1, #ALPHABET do DECODE[ALPHABET:sub(index, index)] = index - 1 end

local function Base64Encode(input)
    local output = {}
    for index = 1, #input, 3 do
        local first, second, third = input:byte(index, index + 2)
        local value = first * 65536 + (second or 0) * 256 + (third or 0)
        output[#output + 1] = ALPHABET:sub(math.floor(value / 262144) % 64 + 1,
            math.floor(value / 262144) % 64 + 1)
        output[#output + 1] = ALPHABET:sub(math.floor(value / 4096) % 64 + 1,
            math.floor(value / 4096) % 64 + 1)
        output[#output + 1] = second and ALPHABET:sub(math.floor(value / 64) % 64 + 1,
            math.floor(value / 64) % 64 + 1) or "="
        output[#output + 1] = third and ALPHABET:sub(value % 64 + 1, value % 64 + 1) or "="
    end
    return table.concat(output)
end

local function Base64Decode(input)
    if #input == 0 or #input % 4 ~= 0 or input:find("[^%w%+/%=]") then return nil end
    local output = {}
    for index = 1, #input, 4 do
        local a, b, c, d = input:sub(index, index), input:sub(index + 1, index + 1),
            input:sub(index + 2, index + 2), input:sub(index + 3, index + 3)
        local first, second = DECODE[a], DECODE[b]
        local third, fourth = c == "=" and nil or DECODE[c], d == "=" and nil or DECODE[d]
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

local function Checksum(input)
    local first, second = 1, 0
    for index = 1, #input do
        first = (first + input:byte(index)) % 65521
        second = (second + first) % 65521
    end
    return string.format("%04X%04X", second, first)
end

local function CompressionMethod()
    return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
end

function PS.ExportShareCode()
    local legacy, reason = PS.ExportBlueprint()
    if not legacy then return nil, reason end
    if #legacy > MAX_LEGACY_BYTES then return nil, "blueprint is too large to share" end
    local mode, payload = "R", legacy
    local codec, method = C_EncodingUtil, CompressionMethod()
    if codec and type(codec.CompressString) == "function" and method then
        local ok, compressed = pcall(codec.CompressString, legacy, method)
        if ok and type(compressed) == "string" and #compressed < #legacy then
            mode, payload = "D", compressed
        end
    end
    local result = PREFIX .. mode .. ":" .. Checksum(legacy) .. ":" .. Base64Encode(payload)
    if #result > MAX_SHARE_BYTES then return nil, "share code is too large" end
    return result
end

function PS.DecodeShareCode(text)
    if type(text) ~= "string" or #text > MAX_SHARE_BYTES then return nil, "share code is too large" end
    text = text:match("^%s*(.-)%s*$")
    local mode, expected, encoded = text:match("^!PSB1!([RD]):([%x][%x][%x][%x][%x][%x][%x][%x]):([%w%+/%=]+)$")
    if not mode then return nil, "invalid share code" end
    local payload = Base64Decode(encoded)
    if not payload then return nil, "invalid Base64 data" end
    local legacy = payload
    if mode == "D" then
        local codec, method = C_EncodingUtil, CompressionMethod()
        if not codec or type(codec.DecompressString) ~= "function" or not method then
            return nil, "this game client cannot decompress the share code"
        end
        local ok, decompressed = pcall(codec.DecompressString, payload, method)
        if not ok or type(decompressed) ~= "string" then return nil, "invalid compressed data" end
        legacy = decompressed
    end
    if #legacy > MAX_LEGACY_BYTES or legacy:sub(1, 5) ~= "!PS1!" then
        return nil, "invalid blueprint payload"
    end
    if Checksum(legacy) ~= expected:upper() then return nil, "share code checksum mismatch" end
    return legacy
end

local ImportLegacyBlueprint = PS.ImportBlueprint
function PS.ImportBlueprint(text, selection)
    if type(text) == "string" and text:match("^%s*!PSB1!") then
        local decoded, reason = PS.DecodeShareCode(text)
        if not decoded then return false, reason end
        text = decoded
    end
    return ImportLegacyBlueprint(text, selection)
end
