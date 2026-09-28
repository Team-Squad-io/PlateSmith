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
-- "problem", "limited" or nil for a report value (the Details view marks rows with it).
Summary.Severity = Severity

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
Summary.SortedKeys = SortedKeys

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

local function SortIssues(issues)
    table.sort(issues, function(left, right)
        if left.severity ~= right.severity then return left.severity == "problem" end
        return left.path < right.path
    end)
    return issues
end

-- entry (optional) adds the capture time, reason, and error message.
function Summary.Build(report, entry)
    local lines, issues = {}, {}
    Flatten(report or {}, "", lines, issues, 0)
    SortIssues(issues)
    local out = {}
    if entry then
        out[#out + 1] = Colour("heading", L["Captured"]) .. "  " .. Format.Clock(entry.time)
            .. "  ·  " .. tostring(entry.reason or "manual")
            .. (type(entry.build) == "string" and "  ·  " .. string.format(L["build %s"], entry.build) or "")
        if entry.error then out[#out + 1] = Colour("problem", L["Error"]) .. "  " .. tostring(entry.error) end
        out[#out + 1] = ""
    end
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

-- The short summary players paste into a bug report: plain text (no colour codes), one line per
-- topic, and a bounded list of problems found by real checks on the report.
local TICK_BUDGET_MS, FRAME_BUDGET_MS, MAX_PROBLEMS = 1, 2, 6
Summary.tickBudgetMs, Summary.frameBudgetMs, Summary.maxProblems = TICK_BUDGET_MS, FRAME_BUDGET_MS, MAX_PROBLEMS
-- Report paths a named check below already explains; the generic walk skips them.
local EXPLAINED = { "^questProviders", "^protectedAction", "^dungeonFriendlyOverlay", "^target%.debuffs%.nativeContainerError" }

local function Field(value, ...)
    for index = 1, select("#", ...) do
        if type(value) ~= "table" then return nil end
        value = value[(select(index, ...))]
    end
    return value
end

local function Text(value, fallback)
    return Scalar(value) or fallback or L["unknown"]
end

local function Ms(value)
    return type(value) == "number" and string.format(L["%.2f ms"], value) or nil
end

local function OneLine(text, count)
    return Format.Truncate(tostring(text):match("^[^\n]*") or "", count, count * 2)
end

-- An error's first line without the addon's path prefix (file:line and the message), cut at a
-- word boundary with an ellipsis. The full text stays in the report.
function Summary.ShortError(message, limit)
    limit = limit or 140
    local text = (tostring(message or ""):match("^[^\n]*") or ""):gsub("Interface[\\/]AddOns[\\/]PlateSmith[\\/]", "")
    if Format.Length(text) <= limit then return text end
    local cut = Format.Truncate(text, limit - 1)
    local head = cut:match("^(.*%S)%s+%S*$")
    if head and Format.Length(head) >= limit / 2 then cut = head end
    return (cut:gsub("%s+$", "")) .. "…"
end

-- "3 h ago" from two time() stamps, or nil when either is unknown.
function Summary.Age(stamp, now)
    if type(stamp) ~= "number" or type(now) ~= "number" or stamp <= 0 then return nil end
    local seconds = math.max(0, now - stamp)
    if seconds < 60 then return string.format(L["%d s ago"], seconds) end
    if seconds < 3600 then return string.format(L["%d min ago"], math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format(L["%d h ago"], math.floor(seconds / 3600)) end
    return string.format(L["%d d ago"], math.floor(seconds / 86400))
end

-- Plain names for the events the plate runtime times; others show as the event itself.
Summary.eventNames = {
    NAME_PLATE_UNIT_ADDED = L["plate added"], NAME_PLATE_UNIT_REMOVED = L["plate removed"],
    UNIT_AURA = L["auras"], UNIT_HEALTH = L["health"], UNIT_MAXHEALTH = L["max health"],
    UNIT_NAME_UPDATE = L["name update"], UNIT_FACTION = L["faction"], UNIT_FLAGS = L["unit flags"],
    PLAYER_TARGET_CHANGED = L["target changed"], UNIT_THREAT_LIST_UPDATE = L["threat list"],
    UNIT_THREAT_SITUATION_UPDATE = L["threat situation"], UNIT_SPELLCAST_START = L["cast start"],
    UNIT_SPELLCAST_STOP = L["cast stop"], UNIT_CLASSIFICATION_CHANGED = L["classification"],
    GROUP_ROSTER_UPDATE = L["group roster"], QUEST_LOG_UPDATE = L["quest log"],
}

local function GroupText(group)
    local kind = Field(group, "type")
    local members = Field(group, "members")
    if type(kind) == "string" and kind ~= "solo" and type(members) == "number" then
        return string.format(L["%s of %d"], kind, members)
    end
    return Text(kind, "solo")
end

local function RestrictionText(restrictions)
    if type(restrictions) ~= "table" then return L["unknown"] end
    if restrictions.state then return Text(restrictions.state) end
    local active = {}
    for _, key in ipairs(SortedKeys(restrictions)) do
        local value = restrictions[key]
        if value == "restricted" then
            active[#active + 1] = tostring(key)
        elseif value ~= "clear" then
            active[#active + 1] = string.format(L["%s %s"], tostring(key), Text(value))
        end
    end
    return #active > 0 and table.concat(active, ", ") or L["none"]
end

local function QuestText(report)
    local providers = report.questProviders
    local parts = {}
    if type(providers) == "table" then
        for _, provider in ipairs(providers) do
            if type(provider) == "table" then
                parts[#parts + 1] = string.format(L["%s %s"], Text(provider.id), Text(provider.status))
            end
        end
    end
    if #parts > 0 then return table.concat(parts, ", ") end
    return Field(report, "api", "quest") == true and L["native only"] or L["no quest API"]
end

local function PerformanceText(performance)
    if type(performance) ~= "table" then return L["Performance: not in this report"] end
    local profiler = type(performance.profiler) == "table" and performance.profiler or {}
    local average = type(profiler.recentAverageMs) == "number"
        and string.format(L["%.2f ms/frame"], profiler.recentAverageMs)
        or Text(profiler.state or profiler.recentAverageMs, L["profiler unavailable"])
    -- The recent window's own peak (ticker runs and timed events), else the profiler's.
    local peak
    for _, entry in pairs(type(performance.ticker) == "table" and performance.ticker or {}) do
        local value = Field(entry, "recentPeakMs")
        if type(value) == "number" and (not peak or value > peak) then peak = value end
    end
    local events = type(performance.recentEvents) == "table" and performance.recentEvents or {}
    for _, entry in ipairs(events) do
        local value = Field(entry, "peakMs")
        if type(value) == "number" and (not peak or value > peak) then peak = value end
    end
    if not peak and type(profiler.peakMs) == "number" then peak = profiler.peakMs end
    -- The top event's total over the window, with its call count and single worst run, so the
    -- total does not read as one cost.
    local top = events[1]
    local topText = L["none"]
    if type(top) == "table" and type(top.totalMs) == "number" then
        local name = Summary.eventNames[top.event] or Text(top.event)
        topText = string.format(L["%s ×%s, %.1f ms total (peak %s)"], name, Text(top.calls, "?"), top.totalMs,
            type(top.peakMs) == "number" and string.format(L["%.1f ms"], top.peakMs) or L["n/a"])
    end
    return string.format(L["Performance (%s s): %s, peak %s · top event: %s"], Text(performance.recentWindowSeconds),
        average, Ms(peak) or L["n/a"], topText)
end

local function TargetText(target)
    local identity = Field(target, "identity")
    if type(identity) ~= "table" then return L["Target: none"] end
    local reaction = identity.reaction
    local side
    if type(reaction) == "number" then
        side = reaction >= 5 and L["friendly"] or reaction == 4 and L["neutral"] or L["hostile"]
    elseif identity.friendly == true then
        side = L["friendly"]
    elseif identity.attackable == true or identity.friendly == false then
        side = L["hostile"]
    else
        side = L["unknown"]
    end
    local who = identity.player == true and L["player"] or identity.player == false and L["NPC"] or L["unit"]
    local plate = Field(target, "plate")
    local layout = type(plate) ~= "table" and L["no plate"] or plate.namesOnly == true and L["names only"] or L["full plate"]
    local highlight = Field(target, "highlight")
    local highlightText = L["no highlight data"]
    if type(highlight) == "table" then
        local applied, configured = Text(highlight.applied, "none"), Text(highlight.configured, "none")
        highlightText = applied == configured and string.format(L["highlight %s"], applied)
            or string.format(L["highlight %s (set: %s)"], applied, configured)
    end
    return string.format(L["Target: %s %s · %s · %s"], side, who, layout, highlightText)
end

-- Plain-language problems, most specific first. extras: historyErrors, lastError, entry.
function Summary.Problems(report, extras)
    report, extras = type(report) == "table" and report or {}, extras or {}
    local problems = {}
    local function Add(text) problems[#problems + 1] = text end

    local entryError = Field(extras, "entry", "error")
    if entryError then Add(string.format(L["This capture was taken for an error: %s"], Summary.ShortError(entryError))) end
    local studio, active = Field(report, "profile", "studio"), Field(report, "profile", "active")
    if type(studio) == "string" and type(active) == "string" and studio ~= "" and studio ~= "none"
        and studio ~= "nil" and studio ~= active then
        Add(string.format(L["Studio is editing profile \"%s\", but the plates use \"%s\"."], studio, active))
    end
    local blocked = Field(report, "protectedAction", "last")
    if blocked then Add(string.format(L["The client blocked a PlateSmith action (taint): %s"], OneLine(blocked, 120))) end
    local restricted = {}
    for key, value in pairs(type(report.restrictions) == "table" and report.restrictions or {}) do
        if value == "restricted" then restricted[#restricted + 1] = tostring(key) end
    end
    table.sort(restricted)
    if #restricted > 0 then
        Add(string.format(L["Addon restrictions are active (%s), so some plate details are limited."],
            table.concat(restricted, ", ")))
    end
    local overlay = report.dungeonFriendlyOverlay
    if type(overlay) == "table" and type(overlay.errors) == "number" and overlay.errors > 0 then
        Add(string.format(L["The friendly dungeon overlay failed on %d plates: %s"], overlay.errors,
            OneLine(Text(overlay.firstError), 100)))
    end
    local containerError = Field(report, "target", "debuffs", "nativeContainerError")
    if containerError then Add(string.format(L["The debuff container failed: %s"], OneLine(containerError, 100))) end
    for _, provider in ipairs(type(report.questProviders) == "table" and report.questProviders or {}) do
        if Field(provider, "status") == "failed" then
            Add(string.format(L["Quest provider %s failed and was switched off."], Text(provider.id)))
        end
    end
    -- Only this session's errors: older ones (often from a build that fixed them) stay in History.
    local sessionErrors = tonumber(extras.sessionErrors) or 0
    if sessionErrors > 0 then
        local latest = Summary.ShortError(Text(extras.lastError))
        local age = Summary.Age(extras.lastErrorTime, extras.now)
        if age then latest = string.format(L["%s (%s)"], latest, age) end
        Add(string.format(sessionErrors == 1 and L["%d PlateSmith error this session: %s"]
            or L["%d PlateSmith errors this session; latest: %s"], sessionErrors, latest))
    end
    local average = Field(report, "performance", "profiler", "recentAverageMs")
    if type(average) == "number" and average > FRAME_BUDGET_MS then
        Add(string.format(L["PlateSmith averages %.2f ms per frame (budget %.1f ms)."], average, FRAME_BUDGET_MS))
    end
    local ticker = Field(report, "performance", "ticker")
    if type(ticker) == "table" then
        for _, id in ipairs(SortedKeys(ticker)) do
            local entry = ticker[id]
            local cost = Field(entry, "recentAverageMs") or Field(entry, "averageMs")
            if type(cost) == "number" and cost > TICK_BUDGET_MS then
                Add(string.format(L["Ticker %s averages %.2f ms per run (budget %.1f ms)."], tostring(id), cost,
                    TICK_BUDGET_MS))
            end
        end
    end
    -- Any other problem state word in the report, so a new probe is covered without a new check.
    local issues, others = {}, {}
    Flatten(report, "", {}, issues, 0)
    for _, issue in ipairs(SortIssues(issues)) do
        local explained = issue.severity ~= "problem"
        for _, pattern in ipairs(EXPLAINED) do
            if explained then break end
            explained = issue.path:find(pattern) ~= nil
        end
        if not explained then others[#others + 1] = issue end
    end
    if #others > 0 then
        Add(string.format(others[2] and L["%d report values show a problem, first %s = %s."]
            or L["%d report value shows a problem: %s = %s."], #others, others[1].path, OneLine(others[1].value, 60)))
    end
    return problems
end

-- report: the full report; extras: see Summary.Problems. Returns the text and the problem count.
function Summary.Short(report, extras)
    report = type(report) == "table" and report or {}
    local context = type(report.context) == "table" and report.context or {}
    local build = context.build
    local client = type(build) == "number" and build >= 100000 and "Retail" or "Forever"
    local profile = type(report.profile) == "table" and report.profile or {}
    local activeProfile = Text(profile.active)
    if profile.unsaved == true then activeProfile = string.format(L["%s (unsaved)"], activeProfile) end
    local lines = {}
    local entry = extras and extras.entry
    if entry then
        local captured = string.format(L["Captured %s · %s"], Format.Clock(entry.time), Text(entry.reason, "manual"))
        if type(entry.build) == "string" then captured = string.format(L["%s · build %s"], captured, entry.build) end
        lines[#lines + 1] = captured
    end
    lines[#lines + 1] = string.format(L["PlateSmith %s · %s %s · %s, %s · %s plates"], Text(report.version), client,
        Text(build), Text(context.instance), GroupText(context.group), Text(context.plates))
    -- Studio is named only while it is open on a different profile (Problems explains that too).
    local studio = profile.studio
    if type(studio) == "string" and studio ~= "" and studio ~= "none" and studio ~= "nil" and studio ~= profile.active then
        activeProfile = string.format(L["%s (Studio: %s)"], activeProfile, studio)
    end
    lines[#lines + 1] = string.format(L["Profile: %s · friendly: %s · mode: %s"], activeProfile,
        Text(Field(report, "settings", "friendly")), Text(Field(report, "settings", "mode")))
    lines[#lines + 1] = string.format(L["Restrictions: %s · Quest: %s"], RestrictionText(report.restrictions),
        QuestText(report))
    lines[#lines + 1] = PerformanceText(report.performance)
    lines[#lines + 1] = TargetText(report.target)
    local problems = Summary.Problems(report, extras)
    if #problems == 0 then
        lines[#lines + 1] = L["Problems: none found"]
    else
        lines[#lines + 1] = string.format(L["Problems (%d):"], #problems)
        for index = 1, math.min(#problems, MAX_PROBLEMS) do lines[#lines + 1] = "- " .. problems[index] end
        if #problems > MAX_PROBLEMS then
            lines[#lines + 1] = string.format(L["- and %d more (see the full report)"], #problems - MAX_PROBLEMS)
        end
    end
    return table.concat(lines, "\n"), #problems
end
