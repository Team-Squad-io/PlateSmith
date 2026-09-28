local _, PS = ...

-- Transport only. A share code is the minified Blueprint JSON in Base64, so it
-- survives chat and forum pasting and every client can decode it. There is no
-- compression, so the decoded size is bounded by the code's length.
-- Share codes are "!PSB3!" and base64 JSON; "!PSB2!" codes (Blueprint version 2) still import.
local PREFIX = "!PSB3!"
local READABLE_PREFIXES = { "!PSB3!", "!PSB2!" }
local Base64 = assert(PS.Base64, "PlateSmith Base64 missing")
local MAX_CODE_BYTES = #PREFIX + math.ceil(PS.MAX_BLUEPRINT_BYTES / 3) * 4

function PS.ExportShareCode()
    local json, reason = PS.ExportBlueprint(false)
    if not json then return nil, reason end
    return PREFIX .. Base64.Encode(json)
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
    local json = Base64.Decode(body)
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
