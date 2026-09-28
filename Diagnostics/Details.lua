local _, PS = ...
local L = PS.L
local Summary = assert(PS.DiagnosticSummary, "PlateSmith DiagnosticSummary missing")

-- The Details tab's model: a report sorted into named sections of label | value rows, sub-headed
-- by the table they came from, with each flagged value lifted to the top of its section and the
-- performance lists as small tables. Plain data only; Diagnostics/Window.lua draws it.
local Details = {}
PS.DiagnosticDetails = Details

Details.SECTIONS = {
    { "context", L["Context"] }, { "profile", L["Profile"] }, { "performance", L["Performance"] },
    { "target", L["Target"] }, { "auras", L["Auras"] }, { "threat", L["Threat"] },
    { "threatWindows", L["Threat windows"] }, { "quest", L["Quest"] }, { "restrictions", L["Restrictions"] },
    { "other", L["Other"] },
}

-- Report paths to sections; the longest matching path wins. sub names the table's own rows
-- (nil: straight under the section title); skip leaves a path to a table built below.
local ROUTES = {
    { "format", "context" }, { "version", "context" }, { "context", "context" },
    { "api", "context", L["APIs"] },
    { "profile", "profile" }, { "settings", "profile", L["Settings"] },
    { "performance", "performance" }, { "performance.profiler", "performance", L["Profiler"] },
    { "performance.ticker", "performance", skip = true }, { "performance.events", "performance", skip = true },
    { "performance.recentEvents", "performance", skip = true },
    { "target", "target" }, { "raid", "target", L["Raid marker"] },
    { "target.buffs", "auras", L["Buffs"] }, { "target.debuffs", "auras", L["Debuffs"] },
    { "target.blizzardAuras", "auras", L["Blizzard aura frames"] },
    { "target.threat", "threat" }, { "target.threatProbe", "threat", L["Probe"] },
    { "threatConsole", "threatWindows" }, { "blizzardMeter", "threatWindows", L["Blizzard damage meter"] },
    { "questProviders", "quest", L["Providers"] }, { "target.quest", "quest", L["Target"] },
    { "restrictions", "restrictions" }, { "protectedAction", "restrictions", L["Blocked action"] },
}

-- Friendly names for the report's keys; any other key is split at its capitals.
local NAMES = {
    api = L["API"], format = L["Format"], version = L["Version"], build = L["Client build"], provider = L["Quest data"],
    plates = L["Plates"], instance = L["Instance"], group = L["Group"], members = L["Members"], type = L["Type"],
    quest = L["Quest"], secret = L["Secret values"], mode = L["Mode"], friendly = L["Friendly"],
    active = L["Active"], unsaved = L["Unsaved changes"], studio = L["Studio"], changes = L["Recent changes"],
    recentAverageMs = L["Recent average"], sessionAverageMs = L["Session average"],
    encounterAverageMs = L["Encounter average"], peakMs = L["Peak"], ticksOver5Ms = L["Frames over 5 ms"],
    ticksOver50Ms = L["Frames over 50 ms"], recentWindowSeconds = L["Recent window"], state = L["State"],
    display = L["Display"], pvp = L["PvP name"], legacy = L["Legacy name"], names = L["Names"],
    identity = L["Identity"], plate = L["Plate"], highlight = L["Highlight"], shownValues = L["Shown values"],
}

-- The field that names an entry of a list (a list of actors reads "party1", not "#2").
local ENTRY_NAMES = { "unit", "id", "name", "slot", "event" }
Details.MAX_LINES = 200

local function Words(key)
    if type(key) == "number" then return string.format(L["#%d"], key) end
    key = tostring(key)
    if NAMES[key] then return NAMES[key] end
    local words = key:gsub("Ms$", ""):gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):lower()
    return (words:gsub("^%l", string.upper))
end
Details.Words = Words

local function Trim(number)
    if number == math.floor(number) and math.abs(number) < 1e15 then return string.format("%d", number) end
    return (string.format("%.3f", number):gsub("0+$", ""):gsub("%.$", ""))
end

-- A value as it reads in a row: yes/no, milliseconds for *Ms keys, the first line of long text.
function Details.FormatValue(key, value)
    local kind = type(value)
    if kind == "boolean" then return value and L["yes"] or L["no"] end
    if kind == "number" then
        if type(key) == "string" and key:find("Ms$") and not key:find("^ticks") then
            return string.format(L["%.2f ms"], value)
        end
        if key == "recentWindowSeconds" then return string.format(L["%d s"], value) end
        return Trim(value)
    end
    if kind == "string" then
        local line = value:match("^[^\n]*") or ""
        return PS.Format.Truncate(line, 240, 480)
    end
    if kind == "table" then return L["empty"] end
    return tostring(value)
end

local function IsList(value)
    return type(value) == "table" and (value[1] ~= nil or getmetatable(value) ~= nil) and next(value) ~= nil
end

local function Keys(value)
    if IsList(value) then
        local keys = {}
        for index = 1, #value do keys[index] = index end
        return keys
    end
    return Summary.SortedKeys(value)
end

-- A list entry's name: its naming field, else its position.
local function EntryName(key, value)
    if type(key) == "number" and type(value) == "table" then
        for _, field in ipairs(ENTRY_NAMES) do
            if type(value[field]) == "string" then return value[field] end
        end
    end
    return Words(key)
end

local function Route(path)
    local best, length = nil, -1
    for _, route in ipairs(ROUTES) do
        local prefix = route[1]
        if (path == prefix or path:sub(1, #prefix + 1) == prefix .. ".") and #prefix > length then
            best, length = route, #prefix
        end
    end
    return best
end

local function NewSection(key, title)
    return { key = key, title = title, flagged = {}, lines = {}, groups = {}, groupOf = {}, tables = {}, problems = 0, limited = 0 }
end

-- The rows under one heading (nil: the section's own rows, drawn first).
local function Group(section, heading)
    local group = section.groupOf[heading or false]
    if not group then
        group = { heading = heading, rows = {} }
        section.groupOf[heading or false] = group
        section.groups[#section.groups + 1] = group
    end
    return group.rows
end

-- A group's heading: its route's name, then the path below the route's own table.
local function Heading(route, names, depth)
    local parts = {}
    if route and route[3] then parts[1] = route[3] end
    for index = depth + 1, #names do parts[#parts + 1] = names[index] end
    if #parts == 0 then return nil end
    return table.concat(parts, " › ")
end

-- Problems first, then limited values, each in the order met.
local function Flag(section, severity, label, value)
    local row = { kind = "row", label = label, value = value, severity = severity }
    if severity == "problem" then
        table.insert(section.flagged, section.problems + 1, row)
        section.problems = section.problems + 1
    else
        section.flagged[#section.flagged + 1] = row
        section.limited = section.limited + 1
    end
end

-- One group (sub-heading and rows) per table that holds values; nested tables follow it.
local function Walk(model, value, path, names, depth)
    if depth > 10 then return end
    local keys = Keys(value)
    local rows = {}
    for _, key in ipairs(keys) do
        local child = value[key]
        local childPath = path == "" and tostring(key) or (path .. "." .. tostring(key))
        if type(child) ~= "table" or next(child) == nil then
            local childRoute = Route(childPath)
            if not (childRoute and childRoute.skip) then
                rows[#rows + 1] = { key = key, value = child, route = childRoute }
            end
        end
    end
    -- Rows of the root table go to their own routes (format, version) one by one.
    for _, row in ipairs(rows) do
        local rowRoute = row.route
        local section = model.byKey[rowRoute and rowRoute[2] or "other"]
        local depthBase = rowRoute and select(2, rowRoute[1]:gsub("%.", "")) + 1 or 0
        local heading = Heading(rowRoute, names, path == "" and 0 or depthBase)
        if path ~= "" and not rowRoute then heading = table.concat(names, " › ") end
        local label, text = Words(row.key), Details.FormatValue(row.key, row.value)
        local severity = Summary.Severity(row.value)
        if severity then
            Flag(section, severity, heading and (heading .. " › " .. label) or label, text)
        else
            local group = Group(section, heading)
            group[#group + 1] = { kind = "row", label = label, value = text }
        end
    end
    for _, key in ipairs(keys) do
        local child = value[key]
        if type(child) == "table" and next(child) ~= nil then
            local childPath = path == "" and tostring(key) or (path .. "." .. tostring(key))
            local childRoute = Route(childPath)
            if not (childRoute and childRoute.skip) then
                names[depth + 1] = EntryName(key, child)
                Walk(model, child, childPath, names, depth + 1)
                names[depth + 1] = nil
            end
        end
    end
end

local function Number(value) return type(value) == "number" and value or nil end
local function Ms(value) return Number(value) and string.format(L["%.2f"], value) or L["–"] end
local function Count(value) return Number(value) and Trim(value) or L["–"] end

-- rows: { name, sortValue, cells = { three texts }, severity }; most first, then by name.
local function Table(section, title, columns, rows)
    if #rows == 0 then return end
    table.sort(rows, function(left, right)
        local a, b = left.sort or -1, right.sort or -1
        if a ~= b then return a > b end
        return left.name < right.name
    end)
    local lines = { { kind = "sub", text = title },
        { kind = "head", label = columns[1], cells = { columns[2], columns[3], columns[4] } } }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = { kind = "trow", label = row.name, cells = row.cells, severity = row.severity, sort = row.sort }
    end
    section.tables[#section.tables + 1] = lines
end

local function PerformanceTables(section, performance)
    if type(performance) ~= "table" then return end
    local average = Number(type(performance.profiler) == "table" and performance.profiler.recentAverageMs)
    if average and average > Summary.frameBudgetMs then
        Flag(section, "problem", L["Frame cost"], string.format(L["PlateSmith averages %.2f ms per frame (budget %.1f ms)."],
            average, Summary.frameBudgetMs))
    end
    local ticker = {}
    for id, entry in pairs(type(performance.ticker) == "table" and performance.ticker or {}) do
        if type(entry) == "table" then
            local recent = Number(entry.recentAverageMs)
            local cost = recent or Number(entry.averageMs)
            local over = cost and cost > Summary.tickBudgetMs
            local name = tostring(id)
            if over then
                Flag(section, "problem", name, string.format(L["Ticker %s averages %.2f ms per run (budget %.1f ms)."],
                    name, cost, Summary.tickBudgetMs))
            end
            ticker[#ticker + 1] = { name = name, sort = recent, severity = over and "problem" or nil,
                cells = { Ms(recent), Ms(entry.peakMs), Count(entry.calls) } }
        end
    end
    Table(section, L["Ticker entries"], { L["Name"], L["Recent ms"], L["Peak ms"], L["Calls"] }, ticker)
    for _, list in ipairs({ { "recentEvents", L["Recent events"], L["Recent ms"] },
        { "events", L["Top events (session)"], L["Total ms"] } }) do
        local rows = {}
        for _, entry in ipairs(type(performance[list[1]]) == "table" and performance[list[1]] or {}) do
            if type(entry) == "table" then
                local name = Summary.eventNames[entry.event] or tostring(entry.event or "?")
                rows[#rows + 1] = { name = name, sort = Number(entry.totalMs),
                    cells = { Ms(entry.totalMs), Ms(entry.peakMs), Count(entry.calls) } }
            end
        end
        Table(section, list[2], { L["Event"], list[3], L["Peak ms"], L["Calls"] }, rows)
    end
end

-- report: a diagnostic report; entry (optional): the History capture it came from.
-- Returns { sections = { ... in SECTIONS order, empty ones left out }, byKey, problems, limited }.
function Details.Build(report, entry)
    report = type(report) == "table" and report or {}
    local model = { sections = {}, byKey = {}, problems = 0, limited = 0 }
    for _, spec in ipairs(Details.SECTIONS) do model.byKey[spec[1]] = NewSection(spec[1], spec[2]) end
    local context = model.byKey.context
    if type(entry) == "table" then
        local rows = Group(context, nil)
        rows[#rows + 1] = { kind = "row", label = L["Captured"], value = PS.Format.Clock(entry.time) }
        rows[#rows + 1] = { kind = "row", label = L["Reason"], value = tostring(entry.reason or "manual") }
        if entry.error then Flag(context, "problem", L["Error"], Details.FormatValue(nil, tostring(entry.error))) end
    end
    Walk(model, report, "", {}, 0)
    PerformanceTables(model.byKey.performance, report.performance)
    for _, spec in ipairs(Details.SECTIONS) do
        local section = model.byKey[spec[1]]
        -- The section's own rows first, then each heading's in the order met, then the tables.
        local own = section.groupOf[false]
        if own then
            for _, line in ipairs(own.rows) do section.lines[#section.lines + 1] = line end
        end
        for _, group in ipairs(section.groups) do
            if group.heading then
                section.lines[#section.lines + 1] = { kind = "sub", text = group.heading }
                for _, line in ipairs(group.rows) do section.lines[#section.lines + 1] = line end
            end
        end
        for _, lines in ipairs(section.tables) do
            for _, line in ipairs(lines) do section.lines[#section.lines + 1] = line end
        end
        section.groups, section.groupOf, section.tables = nil, nil, nil
        if #section.lines + #section.flagged > 0 then
            model.sections[#model.sections + 1] = section
            model.problems, model.limited = model.problems + section.problems, model.limited + section.limited
        end
    end
    return model
end

-- A section's lines as drawn: flagged rows first, then its own, at most MAX_LINES, then one line
-- saying how many more there are.
function Details.Lines(section, limit)
    limit = limit or Details.MAX_LINES
    local out = {}
    for _, list in ipairs({ section.flagged, section.lines }) do
        for _, line in ipairs(list) do out[#out + 1] = line end
    end
    if #out <= limit then return out, 0 end
    local shown = {}
    for index = 1, limit do shown[index] = out[index] end
    local more = #out - limit
    shown[#shown + 1] = { kind = "more", label = string.format(more == 1 and L["and %d more row: see the Report tab"]
        or L["and %d more rows: see the Report tab"], more) }
    return shown, more
end

-- What a folded section's header says: its problem and limited counts.
function Details.HeaderText(section)
    local parts = {}
    if section.problems > 0 then
        parts[#parts + 1] = string.format(section.problems == 1 and L["%d problem"] or L["%d problems"], section.problems)
    end
    if section.limited > 0 then parts[#parts + 1] = string.format(L["%d limited"], section.limited) end
    return table.concat(parts, "  ·  ")
end
