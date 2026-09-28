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

local function SafeInvoke(module, method, ...)
    local callback = module[method]
    if type(callback) ~= "function" then return true end

    local arguments = { ... }
    local count = select("#", ...)
    local function Invoke()
        return callback(module, unpack(arguments, 1, count))
    end
    local ok, result = xpcall(Invoke, function(message)
        if type(debugstack) == "function" then
            return debugstack(tostring(message), 2, 20)
        end
        return tostring(message)
    end)
    if not ok then Chat.ReportError(module.id .. "." .. method, result) end
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

function PS:RegisterModule(id, definition)
    if type(id) ~= "string" or not id:match("^[%a_][%w_.%-]*$") then
        return nil, "module id must be a stable namespaced identifier"
    end
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

function PS:GetModule(id)
    return modules[id]
end

function PS:IterateModules()
    local index = 0
    return function()
        index = index + 1
        local module = moduleOrder[index]
        if module then return module.id, module end
    end
end

function PS:RegisterQuestProvider(id, definition)
    if type(id) ~= "string" or not id:match("^[%a_][%w_.%-]*$") then
        return nil, "quest provider id must be a stable namespaced identifier"
    end
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

function PS:GetQuestProvider(id)
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

function PS:IterateQuestProviders()
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

-- { kind = "number"|"percent"|"signed"|"text"|"flag", read = function(unit, read), label, sample }.
-- "string" is accepted for "text" and preview for sample (the STYLING_RULES 12.3 names).
function PS:RegisterTextToken(id, definition)
    local ok, reason = StyleRange(definition)
    if not ok then return false, reason end
    return PS.Template.RegisterToken(id, {
        kind = definition.kind == "string" and "text" or definition.kind, read = definition.read,
        label = definition.label, sample = definition.sample == nil and definition.preview or definition.sample,
    })
end

-- A condition fact: { type = "boolean"|"number", read = function(unit, read), label, sample }.
-- Protected or missing values are unknown, so a condition on them is false.
function PS:RegisterFact(id, definition)
    local ok, reason = StyleRange(definition)
    if not ok then return false, reason end
    local kinds = { boolean = "flag", number = "number" }
    if not kinds[definition.type] then return false, "fact type must be boolean or number" end
    return PS.Template.RegisterToken(id, {
        kind = kinds[definition.type], read = definition.read, label = definition.label, sample = definition.sample,
    })
end

-- function(value) -> text, or { format = function(value), label }; readable values only.
function PS:RegisterFormatter(id, definition)
    if type(definition) == "table" then
        local ok, reason = StyleRange(definition)
        if not ok then return false, reason end
    end
    return PS.Template.RegisterFormatter(id, definition)
end

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
