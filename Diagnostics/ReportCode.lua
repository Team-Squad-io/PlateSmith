local _, PS = ...
local Json = assert(PS.Json, "PlateSmith Json missing")
local Base64 = assert(PS.Base64, "PlateSmith Base64 missing")

-- The full diagnostic report as one pasteable line. "PS1:z:" is Base64 of the compact JSON compressed
-- by the client (C_EncodingUtil, zlib or raw deflate); "PS1:p:" is Base64 of the plain JSON, used when
-- the client cannot compress. tools/decode-report.py turns either back into readable JSON.
local ReportCode = {}
PS.DiagnosticCode = ReportCode

ReportCode.PREFIX = "PS1:"

local function Util(name)
    local util = C_EncodingUtil
    return type(util) == "table" and type(util[name]) == "function" and util[name] or nil
end

local function Compress(text)
    local compress = Util("CompressString")
    local methods = Enum and Enum.CompressionMethod
    if not compress or type(methods) ~= "table" then return nil end
    local method = methods.Zlib or methods.Deflate
    if method == nil then return nil end
    local levels = Enum.CompressionLevel
    local level = type(levels) == "table" and levels.OptimizeForSize or nil
    local ok, data = pcall(compress, text, method, level)
    if ok and type(data) == "string" and data ~= "" then return data end
    return nil
end

-- The client's encoder when it gives standard padded Base64, else PlateSmith's own.
local function EncodeBase64(data)
    local encode = Util("EncodeBase64")
    if encode then
        local ok, text = pcall(encode, data)
        if ok and type(text) == "string" and text ~= "" and #text % 4 == 0 and not text:find("[^%w%+/=]") then
            return text
        end
    end
    return Base64.Encode(data)
end

-- Returns the code and its flag: "z" (compressed) or "p" (plain).
function ReportCode.Encode(report)
    local json = Json.Encode(report or {})
    local compressed = Compress(json)
    local flag = compressed and "z" or "p"
    return ReportCode.PREFIX .. flag .. ":" .. EncodeBase64(compressed or json), flag
end
