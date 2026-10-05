local _, PS = ...

-- Transport only. A share code is the minified Blueprint JSON in Base64, so it
-- survives chat and forum pasting and every client can decode it. There is no
-- compression, so the decoded size is bounded by the code's length.
-- Share codes are "!PSB<version>!" and base64 JSON: the prefix follows the Blueprint's version
-- ("!PSB3!", or "!PSB4!" for one that uses something new since 1.1.1). "!PSB2!" codes still import,
-- and any later prefix is decoded: the Blueprint's own version decides whether it imports.
local MIN_PREFIX_VERSION = 2
local Base64 = assert(PS.Base64, "PlateSmith Base64 missing")
-- Room for a prefix with a version of up to three digits.
local MAX_CODE_BYTES = #"!PSB!" + 3 + math.ceil(PS.MAX_BLUEPRINT_BYTES / 3) * 4

-- The code (or nil, reason); details as PS.ExportBlueprint's.
function PS.ExportShareCode(details)
    details = type(details) == "table" and details or {}
    local json, reason = PS.ExportBlueprint(false, details)
    if not json then return nil, reason end
    return "!PSB" .. details.version .. "!" .. Base64.Encode(json)
end

function PS.DecodeShareCode(text)
    if type(text) ~= "string" then return nil, "share code must be text" end
    text = text:gsub("%s+", "")
    if #text > MAX_CODE_BYTES then return nil, "share code is too large" end
    local version, body = text:match("^!PSB(%d%d?%d?)!(.*)$")
    if not version or tonumber(version) < MIN_PREFIX_VERSION then return nil, "not a PlateSmith share code" end
    local json = Base64.Decode(body)
    if not json then return nil, "share code is damaged or incomplete" end
    return json
end

-- Import accepts a share code or the Blueprint JSON itself, pretty or minified: the JSON, or nil and
-- the reason.
local function DocumentText(text)
    if type(text) ~= "string" then return nil, "blueprint must be text" end
    if text:match("^%s*!PSB") then return PS.DecodeShareCode(text) end
    if not text:match("^%s*{") then return nil, "paste a PlateSmith share code or Blueprint JSON" end
    return text
end

local ImportDocument = PS.ImportBlueprint
function PS.ImportBlueprint(text, selection)
    local json, reason = DocumentText(text)
    if not json then return false, reason end
    return ImportDocument(json, selection)
end

-- The import preview's settings (Blueprint.lua's ImportResult), from a share code or JSON.
local DocumentResult = PS.BlueprintImportResult
function PS.BlueprintImportResult(text, selection)
    local json, reason = DocumentText(text)
    if not json then return nil, reason end
    return DocumentResult(json, selection)
end
