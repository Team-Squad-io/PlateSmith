local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Format = assert(PS.Format, "PlateSmith Format missing")

-- Text templates for custom values: literal text with {tokens}, and [if] conditions.
--
--   {health} / {health.max} ({health.percent}%)
--   [if health.percent < 35]LOW {health.percent}%[else]{health:short}[end]
--   [if elite and not tagged]{name}[end]
--
-- A token is {name} or {name:format}; format is short (1.2k) or 0, 1 or 2 decimals. Conditions
-- are [if ...], [elseif ...], [else] and [end], nesting up to four deep, with and, or, not,
-- brackets and comparisons (< <= > >= = !=) between tokens and numbers. {{ and [[ write a
-- literal { or [. Protected values are only ever shown: they pass straight into the client's
-- SetFormattedText, never compared or calculated. Conditions use three values: a protected or
-- missing value is unknown, unknown carries through not, and, or (Kleene logic), and only a
-- condition that is true holds, so an unknown one fails closed.
-- Other addons add tokens, flags and formatters (RegisterToken, RegisterFormatter; see the end).
local Template = {}
PS.Template = Template
local unpack = unpack or table.unpack -- luacheck: ignore 143
-- Locale.lua loads after this file; reasons are translated when they are made.
local L = setmetatable({}, { __index = function(_, key) return PS.L and PS.L[key] or key end })

Template.MAX_LENGTH = 160
local MAX_DEPTH, MAX_ARGUMENTS = 4, 8
-- Compiled templates and conditions, failures included, by source text. Studio compiles every
-- prefix typed, so each cache is emptied when it passes CACHE_LIMIT entries.
local CACHE_LIMIT = 256

-- Tokens: numbers, text and flags (true or false). kind decides how each is shown.
Template.tokens = {
    ["health"] = "number", ["health.max"] = "number", ["health.percent"] = "percent", ["health.missing"] = "number",
    ["power"] = "number", ["power.max"] = "number", ["power.percent"] = "percent",
    ["threat.percent"] = "percent", ["threat.lead"] = "signed", ["threat.raw"] = "number",
    ["level"] = "number", ["name"] = "text", ["target"] = "text",
    ["tagged"] = "flag", ["elite"] = "flag", ["rare"] = "flag", ["boss"] = "flag", ["casting"] = "flag",
    ["combat"] = "flag", ["tanking"] = "flag", ["targeted"] = "flag", ["player"] = "flag",
    ["focus"] = "flag", ["quest"] = "flag", ["friendly"] = "flag",
    ["level.smart"] = "text", ["level.diff"] = "signed", ["classification"] = "text", ["guild"] = "text",
    ["cast.name"] = "text", ["threat.hold"] = "text",
    ["hostile"] = "flag", ["neutral"] = "flag", ["interruptible"] = "flag", ["questdrop"] = "flag",
    ["pvp"] = "flag", ["instance"] = "flag", ["ingroup"] = "flag", ["inguild"] = "flag",
    ["role.tank"] = "flag", ["threat.holding"] = "flag", ["threat.losing"] = "flag", ["threat.pulling"] = "flag",
    ["threat.other"] = "flag", ["threat.offtank"] = "flag",
}
-- Short names people know from other addons.
Template.aliases = {
    hp = "health", maxhp = "health.max", hpp = "health.percent", missinghp = "health.missing",
    ["health.current"] = "health", ["health.deficit"] = "health.missing",
    pp = "power", maxpp = "power.max", ppp = "power.percent", ["power.current"] = "power",
    tp = "threat.percent", ["threat.diff"] = "threat.lead",
}
local function Resolve(name) return Template.aliases[name] or name end
local FORMATS = { short = true, ["0"] = true, ["1"] = true, ["2"] = true }
-- Tokens and formatters other addons registered (RegisterToken, RegisterFormatter). A registered
-- token's kind is also written into Template.tokens, so templates and conditions compile with it.
local extensions, formatters = {}, {}

-- ------------------------------------------------------------------ parsing

local function Tokenize(condition)
    local list, position = {}, 1
    while position <= #condition do
        local rest = condition:sub(position)
        local space = rest:match("^%s+")
        if space then
            position = position + #space
        else
            local word = rest:match("^[%a][%w%.]*")
            local number = not word and rest:match("^%-?%d+%.?%d*")
            local operator = not word and not number and (rest:match("^[<>!]=") or rest:match("^[<>=()]"))
            local piece = word or number or operator
            if not piece then return nil, string.format(L["cannot read \"%s\""], Format.Truncate(rest, 8)) end
            list[#list + 1] = { text = piece, word = word ~= nil, number = number and tonumber(number) or nil }
            position = position + #piece
        end
    end
    return list
end

local COMPARISONS = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true, ["="] = true, ["!="] = true }

-- or := and ("or" and)*;  and := not ("and" not)*;  not := "not" not | atom;
-- atom := "(" or ")" | operand [comparison operand];  operand := token | number.
local function ParseCondition(text)
    local list, reason = Tokenize(text)
    if not list then return nil, reason end
    if #list == 0 then return nil, L["[if] needs a condition"] end
    local index = 1
    local function Peek() return list[index] end
    local function Take() index = index + 1 return list[index - 1] end
    local ParseOr
    local function Operand()
        local piece = Take()
        if not piece then return nil, L["a condition ends too soon"] end
        if piece.number then return { number = piece.number } end
        if piece.word and Template.tokens[Resolve(piece.text)] then return { token = Resolve(piece.text) } end
        return nil, string.format(L["unknown name \"%s\""], piece.text)
    end
    local function Atom()
        local piece = Peek()
        if piece and piece.text == "(" then
            Take()
            local inner, failure = ParseOr()
            if not inner then return nil, failure end
            if not Peek() or Peek().text ~= ")" then return nil, L["a ( has no )"] end
            Take()
            return inner
        end
        local left, failure = Operand()
        if not left then return nil, failure end
        local operator = Peek()
        if operator and COMPARISONS[operator.text] then
            Take()
            local right, rightFailure = Operand()
            if not right then return nil, rightFailure end
            return { compare = operator.text, left = left, right = right }
        end
        return { truth = left }
    end
    local function ParseNot()
        local piece = Peek()
        if piece and piece.word and piece.text == "not" then
            Take()
            local inner, failure = ParseNot()
            if not inner then return nil, failure end
            return { negate = inner }
        end
        return Atom()
    end
    local function ParseAnd()
        local left, failure = ParseNot()
        if not left then return nil, failure end
        while Peek() and Peek().word and Peek().text == "and" do
            Take()
            local right, rightFailure = ParseNot()
            if not right then return nil, rightFailure end
            left = { both = { left, right } }
        end
        return left
    end
    ParseOr = function()
        local left, failure = ParseAnd()
        if not left then return nil, failure end
        while Peek() and Peek().word and Peek().text == "or" do
            Take()
            local right, rightFailure = ParseAnd()
            if not right then return nil, rightFailure end
            left = { either = { left, right } }
        end
        return left
    end
    local tree, failure = ParseOr()
    if not tree then return nil, failure end
    if index <= #list then return nil, string.format(L["unexpected \"%s\""], list[index].text) end
    return tree
end

-- A bounded cache of compile results: { value } or { failure = reason }.
local function Cache() return { entries = {}, count = 0 } end
local function Cached(cache, key)
    local entry = cache.entries[key]
    if entry then return entry.value, entry.failure end
end
local function Store(cache, key, value, failure)
    if cache.count >= CACHE_LIMIT then cache.entries, cache.count = {}, 0 end
    cache.entries[key] = { value = value, failure = failure }
    cache.count = cache.count + 1
    return value, failure
end
local templateCache, conditionCache = Cache(), Cache()
-- A new token or formatter can make a cached failure compile.
local function ForgetCompiled() templateCache, conditionCache = Cache(), Cache() end

-- Compiles a template into nodes: { text }, { token, format }, { branches = { { condition, nodes } },
-- otherwise }. Returns nodes, or nil and a reason a player can act on.
local function CompileTemplate(source)
    local root = {}
    local stack = { { nodes = root } }
    local position, literal = 1, {}
    local function Current() return stack[#stack] end
    local function Flush()
        if #literal > 0 then
            local nodes = Current().nodes
            nodes[#nodes + 1] = { text = table.concat(literal) }
            literal = {}
        end
    end
    while position <= #source do
        local char = source:sub(position, position)
        local nextChar = source:sub(position + 1, position + 1)
        if (char == "{" and nextChar == "{") or (char == "[" and nextChar == "[") then
            literal[#literal + 1] = char
            position = position + 2
        elseif char == "{" then
            local close = source:find("}", position, true)
            if not close then return nil, L["a { has no }"] end
            local inner = source:sub(position + 1, close - 1)
            -- {token} then modifiers, each after a colon: short, full, 0-2 or d0-d2 (numbers), upper,
            -- lower, max:N (text), else:text (shown when the value is missing; the rest of the braces),
            -- or a registered formatter's id.
            local name, rest = inner:match("^%s*([%a][%w%.]*)%s*(.-)%s*$")
            name = name and Resolve(name)
            if not name or not Template.tokens[name] then return nil, string.format(L["unknown token {%s}"], inner) end
            if Template.tokens[name] == "flag" then
                return nil, string.format(L["{%s} is a condition: use it in [if]"], name)
            end
            local node = { token = name }
            while rest ~= "" do
                local modifier, remainder = rest:match("^:%s*([%w%.]+)%s*(.-)$")
                if not modifier then return nil, string.format(L["{%s}: modifiers follow a colon"], inner) end
                modifier = modifier:lower()
                if modifier == "else" then
                    local fallback = remainder:match("^:(.*)$") or ""
                    node.fallback = fallback:match('^%s*"(.*)"%s*$') or fallback
                    rest = ""
                elseif modifier == "max" then
                    local count, after = remainder:match("^:%s*(%d+)%s*(.-)$")
                    if not count then return nil, string.format(L["{%s}: max needs a length, as max:10"], inner) end
                    node.max = math.min(60, tonumber(count))
                    rest = after
                elseif FORMATS[modifier] or modifier:match("^d[0-2]$") or modifier == "full" then
                    node.format = modifier == "full" and "0" or modifier:gsub("^d", "")
                    rest = remainder
                elseif modifier == "upper" or modifier == "lower" then
                    node.case = modifier
                    rest = remainder
                elseif formatters[modifier] then
                    node.formatter = modifier
                    rest = remainder
                else
                    return nil, string.format(L["{%s}: unknown modifier %s"], inner, modifier)
                end
            end
            Flush()
            local nodes = Current().nodes
            nodes[#nodes + 1] = node
            position = close + 1
        elseif char == "[" then
            local close = source:find("]", position, true)
            if not close then return nil, L["a [ has no ]"] end
            local inner = source:sub(position + 1, close - 1)
            local keyword, rest = inner:match("^%s*(%a+)%s*(.-)%s*$")
            keyword = keyword and keyword:lower()
            Flush()
            if keyword == "if" then
                if #stack > MAX_DEPTH then return nil, string.format(L["conditions nest more than %d deep"], MAX_DEPTH) end
                local condition, failure = ParseCondition(rest)
                if not condition then return nil, string.format(L["[if %s]: %s"], rest, failure) end
                local block = { branches = { { condition = condition, nodes = {} } } }
                local nodes = Current().nodes
                nodes[#nodes + 1] = block
                stack[#stack + 1] = { block = block, nodes = block.branches[1].nodes }
            elseif keyword == "elseif" then
                local frame = Current()
                if not frame.block or frame.block.otherwise then return nil, L["[elseif] without its [if]"] end
                local condition, failure = ParseCondition(rest)
                if not condition then return nil, string.format(L["[elseif %s]: %s"], rest, failure) end
                local branch = { condition = condition, nodes = {} }
                frame.block.branches[#frame.block.branches + 1] = branch
                frame.nodes = branch.nodes
            elseif keyword == "else" and rest == "" then
                local frame = Current()
                if not frame.block or frame.block.otherwise then return nil, L["[else] without its [if]"] end
                frame.block.otherwise = {}
                frame.nodes = frame.block.otherwise
            elseif keyword == "end" and rest == "" then
                if not Current().block then return nil, L["[end] without its [if]"] end
                stack[#stack] = nil
            else
                return nil, string.format(L["[%s] is not if, elseif, else or end"], inner)
            end
            position = close + 1
        else
            literal[#literal + 1] = char
            position = position + 1
        end
    end
    Flush()
    if #stack > 1 then return nil, L["an [if] has no [end]"] end
    return root
end

local function CheckSource(source)
    if type(source) ~= "string" then return L["not text"] end
    if #source > Template.MAX_LENGTH then return string.format(L["longer than %d characters"], Template.MAX_LENGTH) end
end

function Template.Compile(source)
    local invalid = CheckSource(source)
    if invalid then return nil, invalid end
    local nodes, failure = Cached(templateCache, source)
    if nodes or failure then return nodes, failure end
    return Store(templateCache, source, CompileTemplate(source))
end

-- ------------------------------------------------------------------ rendering

-- Readability first: a protected value is never compared, even with nil.
local function Readable(value) return Secret.IsReadable(value) and value ~= nil end

-- Conditions evaluate to true, false or nil (unknown: a protected or missing value).
local function Truth(value)
    if not Readable(value) then return nil end
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) == "string" then return value ~= "" end
    return false
end

local function Value(operand, read)
    if operand.number then return operand.number end
    return read(operand.token)
end

local function Evaluate(node, read)
    if node.both then
        local left = Evaluate(node.both[1], read)
        if left == false then return false end
        local right = Evaluate(node.both[2], read)
        if right == false then return false end
        if left == nil or right == nil then return nil end
        return true
    end
    if node.either then
        local left = Evaluate(node.either[1], read)
        if left == true then return true end
        local right = Evaluate(node.either[2], read)
        if right == true then return true end
        if left == nil or right == nil then return nil end
        return false
    end
    if node.negate then
        local inner = Evaluate(node.negate, read)
        if inner == nil then return nil end
        return not inner
    end
    if node.truth then return Truth(Value(node.truth, read)) end
    local left, right = Value(node.left, read), Value(node.right, read)
    if not Readable(left) or not Readable(right) then return nil end
    if type(left) ~= "number" or type(right) ~= "number" then return false end
    local operator = node.compare
    if operator == "<" then return left < right end
    if operator == "<=" then return left <= right end
    if operator == ">" then return left > right end
    if operator == ">=" then return left >= right end
    if operator == "=" then return left == right end
    return left ~= right
end

-- Text written into the format string: % doubled for SetFormattedText, and | doubled so text
-- from a Blueprint or a unit cannot open a texture, link or colour escape.
local function Escape(text) return (tostring(text):gsub("%%", "%%%%"):gsub("|", "||")) end

-- A readable value as text, by its token's kind, the format asked for and its modifiers.
local function Show(kind, value, formatName, node)
    if type(value) == "string" then
        if node and node.case == "upper" then value = value:upper() elseif node and node.case == "lower" then value = value:lower() end
        if node and node.max then value = Format.Truncate(value, node.max) end
        return value
    end
    if type(value) ~= "number" then return "" end
    if formatName == "short" then return kind == "signed" and Format.SignedLead(value) or Format.Abbreviate(value) end
    local decimals = tonumber(formatName) or 0
    local text = string.format("%." .. decimals .. "f", value)
    if kind == "signed" and value > 0 then text = "+" .. text end
    return text
end

-- A registered reader or formatter that errors is reported once, reads nil from then on for that
-- call, and is switched off for the session after FAILURE_LIMIT errors.
local FAILURE_LIMIT = 5
local function Fail(entry, what, message)
    entry.errors = entry.errors + 1
    if entry.errors >= FAILURE_LIMIT then entry.disabled = true end
    if entry.errors == 1 and PS.Chat then
        PS.Chat.ReportError(what .. " " .. entry.id, tostring(message) .. " (off for this session after "
            .. FAILURE_LIMIT .. " errors)")
    end
end

-- A readable value through a registered formatter, at most 64 characters (escaped when written
-- in, like any text). nil when the formatter fails.
local function Formatted(id, value)
    local entry = formatters[id]
    if not entry or entry.disabled then return nil end
    local ok, text = pcall(entry.format, value)
    if not ok then Fail(entry, "formatter", text) return nil end
    if type(text) == "number" then text = tostring(text) end
    if type(text) ~= "string" or not Secret.IsReadable(text) then return nil end
    return Format.Truncate(text, 64)
end

local function Walk(list, read, parts, arguments)
    for _, node in ipairs(list) do
        if node.text then
            parts[#parts + 1] = Escape(node.text)
        elseif node.token then
            local kind, value = Template.tokens[node.token], read(node.token)
            if not Secret.HasValue(value) or (Readable(value) and value == "") then
                if node.fallback then parts[#parts + 1] = Escape(node.fallback) end
            elseif Readable(value) then
                local shown = node.formatter and Formatted(node.formatter, value)
                parts[#parts + 1] = Escape(shown or Show(kind, value, node.format, node))
            elseif #arguments < MAX_ARGUMENTS then
                -- Protected: the client formats it (a formatter is skipped). Short numbers go
                -- through its abbreviator.
                local shown, pattern = value, kind == "text" and "%s" or "%.0f"
                if node.format == "short" and kind ~= "text" then
                    local abbreviate = type(AbbreviateNumbers) == "function" and AbbreviateNumbers or nil
                    local ok, abbreviated = false, nil
                    if abbreviate then ok, abbreviated = pcall(abbreviate, value) end
                    if ok and Secret.HasValue(abbreviated) then shown, pattern = abbreviated, "%s" end
                elseif tonumber(node.format) and kind ~= "text" then
                    pattern = "%." .. node.format .. "f"
                end
                parts[#parts + 1] = pattern
                arguments[#arguments + 1] = shown
            end
        elseif node.branches then
            -- The first branch whose condition is true; [else] when none is (unknown included).
            local taken = node.otherwise
            for _, branch in ipairs(node.branches) do
                if Evaluate(branch.condition, read) == true then taken = branch.nodes break end
            end
            if taken then Walk(taken, read, parts, arguments) end
        end
    end
end

-- Plates render every refresh, so Render reuses its scratch tables. A render started while
-- another runs (a reader that renders) gets its own.
local scratchParts, scratchArguments, rendering = {}, {}, false

-- Renders compiled nodes with read(token) -> value (readable, protected, or nil). Returns the
-- format string and the protected arguments it takes (readable parts are written in). The
-- argument list is reused by the next Render, so use it before rendering again.
function Template.Render(nodes, read)
    local parts, arguments = scratchParts, scratchArguments
    local nested = rendering
    if nested then parts, arguments = {}, {} end
    for index = #parts, 1, -1 do parts[index] = nil end
    for index = #arguments, 1, -1 do arguments[index] = nil end
    rendering = true
    local ok, failure = pcall(Walk, nodes, read, parts, arguments)
    rendering = nested
    if not ok then error(failure, 0) end
    return table.concat(parts), arguments
end

-- A condition on its own (a rule's "when"): compiled once, evaluated with read(token).
function Template.CompileCondition(text)
    local invalid = CheckSource(text)
    if invalid then return nil, invalid end
    local tree, failure = Cached(conditionCache, text)
    if tree or failure then return tree, failure end
    return Store(conditionCache, text, ParseCondition(text))
end

-- True only when the condition is true; false and unknown both fail.
function Template.Test(tree, read) return tree ~= nil and Evaluate(tree, read) == true end

-- Writes a template into a font string. Returns true when something shows.
function Template.Apply(fontString, source, read)
    local nodes = Template.Compile(source)
    if not nodes then
        fontString:SetText("")
        return false
    end
    local pattern, arguments = Template.Render(nodes, read)
    local ok
    if #arguments == 0 then
        -- Unescape: with no arguments the text is written as it is.
        local text = pattern:gsub("%%%%", "%%")
        ok = pcall(fontString.SetText, fontString, text)
        if ok and text:match("^%s*$") then return false end
    else
        ok = pcall(fontString.SetFormattedText, fontString, pattern, unpack(arguments))
    end
    if not ok then fontString:SetText("") end
    return ok
end

-- ------------------------------------------------------------------ extensions

-- Installed addons are trusted code and may register functions; templates and rules (from
-- profiles and Blueprints) are data and can only name what is registered (STYLING_RULES 12.1).
local MAX_ID_LENGTH, MAX_LABEL_LENGTH, MAX_SAMPLE_LENGTH = 64, 80, 60
local KINDS = { number = "number", percent = "number", signed = "number", text = "string", flag = "boolean" }
local BUILT_IN_MODIFIERS = {
    short = true, full = true, ["0"] = true, ["1"] = true, ["2"] = true, d0 = true, d1 = true, d2 = true,
    upper = true, lower = true, max = true, ["else"] = true,
}
-- Built-in names' first words ("health", "threat", ...) stay PlateSmith's, so a later built-in
-- token cannot collide with a module's.
local reserved = {}
for name in pairs(Template.tokens) do reserved[name:match("^[^.]+")] = true end
for name in pairs(Template.aliases) do reserved[name:match("^[^.]+")] = true end

local function CheckId(id, what)
    if type(id) ~= "string" or #id > MAX_ID_LENGTH or not id:match("^[a-z][a-z0-9]*%.[a-z0-9][a-z0-9.]*$")
        or id:find("..", 1, true) or id:sub(-1) == "." then
        return false, what .. " id must be \"<module>.<name>\" in lowercase letters, digits and dots, at most "
            .. MAX_ID_LENGTH .. " characters"
    end
    if reserved[id:match("^[^.]+")] then return false, what .. " id " .. id .. " uses a PlateSmith namespace" end
    return true
end

local function CheckLabel(label)
    return label == nil or (type(label) == "string" and #label <= MAX_LABEL_LENGTH)
end

-- spec = { kind = number|percent|signed|text|flag, read = function(unit, read) end, sample, label }.
-- read may return a protected value: it is only shown, like a built-in token's. A flag is used in
-- conditions only. Returns true, or false and a reason; nothing is stored unless all of it is valid.
function Template.RegisterToken(id, spec)
    local ok, reason = CheckId(id, "token")
    if not ok then return false, reason end
    if Template.tokens[id] or Template.aliases[id] then return false, "token is already registered: " .. id end
    if type(spec) ~= "table" then return false, "token spec must be a table" end
    local valueType = KINDS[spec.kind]
    if not valueType then return false, "token kind must be number, percent, signed, text or flag" end
    if type(spec.read) ~= "function" then return false, "token needs read(unit, read)" end
    if not CheckLabel(spec.label) then
        return false, "token label must be text of at most " .. MAX_LABEL_LENGTH .. " characters"
    end
    local sample = spec.sample
    if sample ~= nil and (type(sample) ~= valueType or (valueType == "string" and #sample > MAX_SAMPLE_LENGTH)) then
        return false, "token sample must be a " .. valueType
            .. (valueType == "string" and " of at most " .. MAX_SAMPLE_LENGTH .. " characters" or "")
    end
    extensions[id] = { id = id, kind = spec.kind, read = spec.read, label = spec.label, sample = sample, errors = 0 }
    Template.tokens[id] = spec.kind
    ForgetCompiled()
    return true
end

-- formatter = function(value) -> text, or { format = function, label = text }. Used as a modifier,
-- {level:<id>}, on readable values only: a protected value keeps the token's default format.
function Template.RegisterFormatter(id, formatter)
    local ok, reason = CheckId(id, "formatter")
    if not ok then return false, reason end
    if BUILT_IN_MODIFIERS[id] then return false, "formatter id is a built-in modifier: " .. id end
    if formatters[id] then return false, "formatter is already registered: " .. id end
    local format, label = formatter, nil
    if type(formatter) == "table" then format, label = formatter.format, formatter.label end
    if type(format) ~= "function" then return false, "formatter must be a function(value) returning text" end
    if not CheckLabel(label) then
        return false, "formatter label must be text of at most " .. MAX_LABEL_LENGTH .. " characters"
    end
    formatters[id] = { id = id, format = format, label = label, errors = 0 }
    ForgetCompiled()
    return true
end

-- The reader only ever sees the unit token and this read function, which reads other tokens
-- for the same plate while the reader runs and nothing after it returns.
local currentRead
local function GuardedRead(token)
    if type(token) == "string" and currentRead then return currentRead(token) end
end

-- A registered token's live value for a unit (Nameplates/TemplateReaders falls back to this).
-- Errors are contained: the token reads nil and the plate renders the rest.
function Template.ReadExtension(token, unit, read)
    local entry = extensions[token]
    if not entry or entry.disabled or entry.busy then return nil end
    local previous = currentRead
    entry.busy, currentRead = true, read
    local ok, value = pcall(entry.read, unit, GuardedRead)
    entry.busy, currentRead = false, previous
    if not ok then Fail(entry, "token", value) return nil end
    -- A readable value of the wrong type reads as missing; a protected one is passed on to be shown.
    if Readable(value) and type(value) ~= KINDS[entry.kind] then return nil end
    return value
end

-- Studio's preview value for a registered token.
function Template.Sample(token)
    local entry = extensions[token]
    return entry and entry.sample
end

local function State(entry)
    if entry.disabled then return "disabled" end
    if entry.errors > 0 then return "error" end
end

-- Every token, built-in and registered, for help and tools, sorted by id:
-- { id, kind, builtin, label, sample, aliases, state }. label and sample come from the
-- registering addon (built-ins have none); state is nil, "error" or "disabled".
function Template.ListTokens()
    local aliasesOf = {}
    for alias, target in pairs(Template.aliases) do
        aliasesOf[target] = aliasesOf[target] or {}
        table.insert(aliasesOf[target], alias)
    end
    local list = {}
    for id, kind in pairs(Template.tokens) do
        local entry = extensions[id]
        if aliasesOf[id] then table.sort(aliasesOf[id]) end
        list[#list + 1] = {
            id = id, kind = kind, builtin = entry == nil, label = entry and entry.label,
            sample = entry and entry.sample, aliases = aliasesOf[id], state = entry and State(entry) or nil,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Registered formatters, sorted by id: { id, label, state }.
function Template.ListFormatters()
    local list = {}
    for id, entry in pairs(formatters) do list[#list + 1] = { id = id, label = entry.label, state = State(entry) } end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end
