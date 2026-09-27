local _, PS = ...
local L = PS.L
local Format = assert(PS.Format, "PlateSmith Format missing")

-- A readable summary of any diagnostic report. It walks the report
-- generically, so a new probe needs no change here: any leaf string that
-- matches these state words is flagged and listed first.
local Summary = {}
PS.DiagnosticSummary = Summary

Summary.problemStates = { "error", "failed", "blocked", "api%-missing", "missing", "^invalid", "rejected" }
Summary.limitedStates = { "^secret$", "^protected$", "unavailable", "withheld", "no%-entry", "^restricted$" }
Summary.sectionOrder = { "context", "restrictions", "settings", "target", "raid", "questProviders", "api", "performance" }

local colours = { problem = "|cffff5a4a", limited = "|cffffc94a", heading = "|cff60d4ff", muted = "|cff9a9a9a" }
local function Colour(kind, text) return colours[kind] .. text .. "|r" end

local function Severity(value)
    if type(value) ~= "string" then return nil end
    local lowered = value:lower()
    for _, pattern in ipairs(Summary.problemStates) do
        if lowered:find(pattern) then return "problem" end
    end
    for _, pattern in ipairs(Summary.limitedStates) do
        if lowered:find(pattern) then return "limited" end
    end
    return nil
end

local function SortedKeys(value, preferred)
    local keys, seen = {}, {}
    for _, key in ipairs(preferred or {}) do
        if value[key] ~= nil then keys[#keys + 1] = key; seen[key] = true end
    end
    local rest = {}
    for key in pairs(value) do
        if not seen[key] then rest[#rest + 1] = key end
    end
    table.sort(rest, function(left, right) return tostring(left) < tostring(right) end)
    for _, key in ipairs(rest) do keys[#keys + 1] = key end
    return keys
end

local function Scalar(value)
    if type(value) == "string" then return value end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    return nil
end

-- One line per table that holds scalar values; nested tables get their own lines.
local function Flatten(value, path, lines, issues, depth)
    if depth > 8 then return end
    local parts = {}
    local keys = SortedKeys(value, depth == 0 and Summary.sectionOrder or nil)
    for _, key in ipairs(keys) do
        local child = value[key]
        local childPath = path == "" and tostring(key) or (path .. "." .. tostring(key))
        local text = Scalar(child)
        if text then
            local severity = Severity(child)
            if severity then issues[#issues + 1] = { severity = severity, path = childPath, value = text } end
            parts[#parts + 1] = tostring(key) .. " " .. (severity and Colour(severity, text) or text)
        elseif type(child) == "table" and next(child) == nil then
            parts[#parts + 1] = tostring(key) .. " " .. Colour("muted", L["empty"])
        end
    end
    if #parts > 0 then
        lines[#lines + 1] = Colour("heading", path == "" and L["report"] or path) .. "  " .. table.concat(parts, "  ·  ")
    end
    for _, key in ipairs(keys) do
        local child = value[key]
        if type(child) == "table" and next(child) ~= nil then
            Flatten(child, path == "" and tostring(key) or (path .. "." .. tostring(key)), lines, issues, depth + 1)
        end
    end
end

-- entry (optional) adds the capture time, reason, and error message.
function Summary.Build(report, entry)
    local lines, issues = {}, {}
    Flatten(report or {}, "", lines, issues, 0)
    local out = {}
    if entry then
        out[#out + 1] = Colour("heading", L["Captured"]) .. "  " .. Format.Clock(entry.time)
            .. "  ·  " .. tostring(entry.reason or "manual")
        if entry.error then out[#out + 1] = Colour("problem", L["Error"]) .. "  " .. tostring(entry.error) end
        out[#out + 1] = ""
    end
    table.sort(issues, function(left, right)
        if left.severity ~= right.severity then return left.severity == "problem" end
        return left.path < right.path
    end)
    if #issues > 0 then
        out[#out + 1] = Colour("heading", string.format(L["Needs attention (%d)"], #issues))
        for _, issue in ipairs(issues) do
            out[#out + 1] = "  " .. Colour(issue.severity, issue.severity == "problem" and "x" or "!")
                .. "  " .. issue.path .. ": " .. Colour(issue.severity, issue.value)
        end
    else
        out[#out + 1] = Colour("heading", L["Needs attention"]) .. "  " .. L["nothing flagged"]
    end
    out[#out + 1] = ""
    out[#out + 1] = Colour("heading", L["Overview"])
    for _, line in ipairs(lines) do out[#out + 1] = line end
    return table.concat(out, "\n"), #issues
end
