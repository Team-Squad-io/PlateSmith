local _, PS = ...

local unpack = unpack or table.unpack -- luacheck: ignore 143 (Lua 5.1 global; tests also run on 5.4)

PS.API_VERSION = 1
PS.QUEST_PROVIDER_API_VERSION = 1
-- Style extension contract (docs/MODULES.md, STYLING_RULES 12): text tokens, facts, formatters.
PS.STYLE_API_VERSION = 1

local modules = {}
local moduleOrder = {}
local questProviders = {}
local questProviderOrder = {}
local questProviderIndex, questProviderIds = {}, {}
local initialized = false
local enabled = false
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

-- Every public call takes PlateSmith:Call(...) and PlateSmith.Call(...) alike: a colon call passes PlateSmith
-- itself first, which no argument of the API can be.
local function Args(first, ...)
    if first == PS then return ... end
    return first, ...
end
PS._Args = Args

-- The one ID grammar (docs/MODULES.md): lowercase words of letters and digits joined by dots, at most 64
-- characters. A module's own ID may be one word ("kickwatch"); what a module registers (tokens, facts, formatters,
-- Blueprint fields, parts, sources) is "<module>.<name>", two words or more.
local MAX_ID_LENGTH = 64
local function IsModuleId(id, words)
    if type(id) ~= "string" or #id > MAX_ID_LENGTH or not id:match("^[a-z][a-z0-9.]*$")
        or id:find("..", 1, true) or id:sub(-1) == "." then
        return false
    end
    local count = 1
    for _ in id:gmatch("%.") do count = count + 1 end
    for word in id:gmatch("[^.]+") do
        if not word:match("^[a-z0-9]+$") then return false end
    end
    return count >= (words or 1)
end
PS.IsModuleId = function(...) return IsModuleId(Args(...)) end
PS.MAX_ID_LENGTH = MAX_ID_LENGTH

-- The reason every registration gives for an ID outside the grammar.
function PS._IdReason(what, words)
    if (words or 1) >= 2 then
        return string.format("%s id must be \"<module>.<name>\": lowercase letters and digits joined by dots, at most %d "
            .. "characters", what, MAX_ID_LENGTH)
    end
    return string.format("%s id must be lowercase letters and digits, words joined by dots, at most %d characters",
        what, MAX_ID_LENGTH)
end

-- Module IDs registered before 1.3.0 may also use capitals, "_" and "-" (still accepted, so no installed module
-- breaks); new modules use the grammar above.
local function IsLegacyModuleId(id)
    return type(id) == "string" and #id <= MAX_ID_LENGTH and id:match("^[%a_][%w_.%-]*$") ~= nil
end

-- The calls in progress, one reused record per depth (a module's callback may call ForEachModule
-- again): the module, its callback, and the arguments at 1..count. So a call makes no table or
-- closure (each quest log change reaches the modules).
local calls, depth = {}, 0

local function InvokeCurrent()
    local call = calls[depth]
    return call.callback(call.module, unpack(call, 1, call.count))
end

local function Traceback(message)
    if type(debugstack) == "function" then
        return debugstack(tostring(message), 2, 20)
    end
    return tostring(message)
end
PS._Traceback = Traceback

local function SafeInvoke(module, method, ...)
    local callback = module[method]
    if type(callback) ~= "function" then return true end

    depth = depth + 1
    local call = calls[depth] or {}
    calls[depth] = call
    local count = select("#", ...)
    call.module, call.callback, call.count = module, callback, count
    for index = 1, count do call[index] = (select(index, ...)) end
    local ok, result = xpcall(InvokeCurrent, Traceback)
    for index = 1, count do call[index] = nil end
    call.module, call.callback = nil, nil
    depth = depth - 1
    if not ok then
        module._plateSmithError = tostring(result)
        Chat.ReportError(module.id .. "." .. method, result)
    end
    return ok, result
end

local function InitializeModule(module)
    if module._plateSmithState == "initialized" or module._plateSmithState == "enabled" then return true end
    if module._plateSmithState == "failed" or module._plateSmithState == "initializing" then return false end
    module._plateSmithState = "initializing"
    local ok = SafeInvoke(module, "OnInitialize")
    if not ok then
        module._plateSmithState = "failed"
        module._plateSmithInitialized = false
        return false
    end
    module._plateSmithState = "initialized"
    module._plateSmithInitialized = true
    return true
end

local function EnableModule(module)
    if module._plateSmithState == "enabled" then return true end
    if not InitializeModule(module) then return false end
    module._plateSmithState = "enabling"
    local ok = SafeInvoke(module, "OnEnable")
    if not ok then
        module._plateSmithState = "failed"
        module._plateSmithEnabled = false
        return false
    end
    module._plateSmithState = "enabled"
    module._plateSmithEnabled = true
    return true
end

function PS.RegisterModule(...)
    local id, definition = Args(...)
    if not IsModuleId(id) and not IsLegacyModuleId(id) then return nil, PS._IdReason("module") end
    if type(definition) ~= "table" then return nil, "module definition must be a table" end
    if definition.requiredAPI ~= nil
        and (type(definition.requiredAPI) ~= "number" or definition.requiredAPI > PS.API_VERSION) then
        return nil, "module requires a newer PlateSmith API"
    end
    if definition.apiMin ~= nil and (type(definition.apiMin) ~= "number" or definition.apiMin > PS.API_VERSION) then
        return nil, "module API range starts above this PlateSmith version"
    end
    if definition.apiMax ~= nil and (type(definition.apiMax) ~= "number" or definition.apiMax < PS.API_VERSION) then
        return nil, "module API range ends below this PlateSmith version"
    end
    if modules[id] then return nil, "module is already registered: " .. id end

    definition.id = id
    modules[id] = definition
    moduleOrder[#moduleOrder + 1] = definition

    if initialized then InitializeModule(definition) end
    if enabled then EnableModule(definition) end
    return definition
end

function PS.GetModule(...)
    local id = Args(...)
    return modules[id]
end

function PS.IterateModules()
    local index = 0
    return function()
        index = index + 1
        local module = moduleOrder[index]
        if module then return module.id, module end
    end
end

-- A module's state in the standard words: enabled, initialized, failed (with the error), or nil when unknown.
function PS._ModuleState(id)
    local module = modules[id]
    if not module then return nil end
    return module._plateSmithState or "registered", module._plateSmithError
end

function PS.RegisterQuestProvider(...)
    local id, definition = Args(...)
    if not IsModuleId(id) and not IsLegacyModuleId(id) then return nil, PS._IdReason("quest provider") end
    if type(definition) ~= "table" or type(definition.GetUnitRelevance) ~= "function" then
        return nil, "quest provider requires GetUnitRelevance"
    end
    local api = PS.QUEST_PROVIDER_API_VERSION
    if definition.apiMin ~= nil and (type(definition.apiMin) ~= "number" or definition.apiMin > api) then
        return nil, "quest provider API range starts above this PlateSmith version"
    end
    if definition.apiMax ~= nil and (type(definition.apiMax) ~= "number" or definition.apiMax < api) then
        return nil, "quest provider API range ends below this PlateSmith version"
    end
    if questProviders[id] then return nil, "quest provider is already registered: " .. id end

    definition.id = id
    questProviders[id] = definition
    questProviderOrder[#questProviderOrder + 1] = definition
    questProviderIndex[id], questProviderIds[#questProviderOrder] = #questProviderOrder, id
    return definition
end

function PS.GetQuestProvider(...)
    local id = Args(...)
    return questProviders[id]
end

-- Stateless: the plates walk the providers for every quest check, so no closure is made per call.
local function NextQuestProvider(_, id)
    local index = 0
    if id ~= nil then
        index = questProviderIndex[id]
        if not index then return nil end
    end
    local provider = questProviderOrder[index + 1]
    if provider then return questProviderIds[index + 1], provider end
end

function PS.IterateQuestProviders()
    return NextQuestProvider, nil, nil
end

-- Style extensions. Each returns true, or false and a reason, and stores nothing on failure.
local function StyleRange(definition)
    if type(definition) ~= "table" then return false, "definition must be a table" end
    local api = PS.STYLE_API_VERSION
    if definition.styleApiMin ~= nil and (type(definition.styleApiMin) ~= "number" or definition.styleApiMin > api) then
        return false, "style API range starts above this PlateSmith version"
    end
    if definition.styleApiMax ~= nil and (type(definition.styleApiMax) ~= "number" or definition.styleApiMax < api) then
        return false, "style API range ends below this PlateSmith version"
    end
    return true
end
PS._StyleRange = StyleRange

-- { kind = "number"|"percent"|"signed"|"text"|"flag", read = function(unit, read), label, sample }.
-- "string" is accepted for "text" and preview for sample (the STYLING_RULES 12.3 names).
function PS.RegisterTextToken(...)
    local id, definition = Args(...)
    local ok, reason = StyleRange(definition)
    if not ok then return false, reason end
    return PS.Template.RegisterToken(id, {
        kind = definition.kind == "string" and "text" or definition.kind, read = definition.read,
        label = definition.label, sample = definition.sample == nil and definition.preview or definition.sample,
    })
end

-- A condition fact: { type = "boolean"|"number", read = function(unit, read), label, sample }.
-- Protected or missing values are unknown, so a condition on them is false.
function PS.RegisterFact(...)
    local id, definition = Args(...)
    local ok, reason = StyleRange(definition)
    if not ok then return false, reason end
    local kinds = { boolean = "flag", number = "number" }
    if not kinds[definition.type] then return false, "fact type must be boolean or number" end
    return PS.Template.RegisterToken(id, {
        kind = kinds[definition.type], read = definition.read, label = definition.label, sample = definition.sample,
    })
end

-- function(value) -> text, or { format = function(value), label }; readable values only.
function PS.RegisterFormatter(...)
    local id, definition = Args(...)
    if type(definition) == "table" then
        local ok, reason = StyleRange(definition)
        if not ok then return false, reason end
    end
    return PS.Template.RegisterFormatter(id, definition)
end

-- Facts PlateSmith re-reads on a module's word: quest relevance (a quest provider's answers changed) and object.quest.
local QUEST_FACTS = { quest = true, ["object.quest"] = true }

-- Asks PlateSmith to read a fact again on the next flush: a module's token or fact (its own event said it changed,
-- such as a cooldown ending with no plate event), for every visible plate or the plate of one unit; or "quest" when a
-- quest provider's answers changed. true, or false and a reason. Cheap: it marks plates; they render once a frame.
function PS.InvalidateFact(...)
    local id, unit = Args(...)
    if QUEST_FACTS[id] then
        if type(PS.RefreshQuestMarkers) == "function" then PS.RefreshQuestMarkers() end
        return true
    end
    local Template = PS.Template
    -- A module's bar or icon source (Core/ModuleSources.lua) is read the same way.
    local source = PS.ModuleSources and type(id) == "string" and PS.ModuleSources.Get(id)
    if not source then
        if type(id) ~= "string" or not Template.tokens[id] then return false, "unknown fact: " .. tostring(id) end
        if not Template.IsExtension(id) then return false, "built-in facts are read by PlateSmith itself: " .. id end
    end
    if unit ~= nil and type(unit) ~= "string" then return false, "unit must be a unit token" end
    if type(PS._InvalidatePlateValues) == "function" then PS._InvalidatePlateValues(unit) end
    return true
end

-- Error reports for modules: through the player's error handler (BugSack when installed), naming the build.
function PS.ReportError(...)
    local scope, message = Args(...)
    return Chat.ReportError(scope, message)
end

-- A module's own strings: L["English text"] is the text in the client's language when the module gave one, else the
-- English key. translations: { deDE = { ["English text"] = "..." }, ... }; calling again adds to them.
local locales = {}
local clientLocale = type(GetLocale) == "function" and GetLocale() or "enUS"
function PS.Locale(...)
    local id, translations = Args(...)
    if type(id) ~= "string" or id == "" then return nil, "locale needs the module's id" end
    local entry = locales[id]
    if not entry then
        local strings = {}
        entry = { strings = strings, table = setmetatable({}, {
            __index = function(_, key) return strings[key] or key end,
            __newindex = function() end,
        }) }
        locales[id] = entry
    end
    local own = type(translations) == "table" and translations[clientLocale]
    if type(own) == "table" then
        for key, text in pairs(own) do
            if type(key) == "string" and type(text) == "string" then entry.strings[key] = text end
        end
    end
    return entry.table
end

-- Values from the game that may be protected (docs/MODULES.md, Runtime rules). A colon call passes PlateSmith first;
-- a client value is never PlateSmith, and only a readable table is compared with it.
local function Value(first, ...)
    if type(first) == "table" and IsReadable(first) and first == PS then return (...) end
    return first
end
function PS.IsReadable(...) return IsReadable(Value(...)) end
function PS.ReadNumber(...) return Secret.Number(Value(...)) end
function PS.ReadText(...) return Secret.String(Value(...)) end

function PS:InitializeModules()
    if initialized then return end
    initialized = true
    for index = 1, #moduleOrder do InitializeModule(moduleOrder[index]) end
end

function PS:EnableModules()
    if enabled then return end
    self:InitializeModules()
    enabled = true
    for index = 1, #moduleOrder do EnableModule(moduleOrder[index]) end
end

function PS:DisableModules()
    if not enabled then return end
    enabled = false
    for index = #moduleOrder, 1, -1 do
        local module = moduleOrder[index]
        if module._plateSmithEnabled then
            module._plateSmithEnabled = false
            SafeInvoke(module, "OnDisable")
            module._plateSmithState = "initialized"
        end
    end
end

function PS:ForEachModule(method, ...)
    for index = 1, #moduleOrder do
        SafeInvoke(moduleOrder[index], method, ...)
    end
end

PS._CoreTest = {
    ModuleCount = function() return #moduleOrder end,
    QuestProviderCount = function() return #questProviderOrder end,
}
