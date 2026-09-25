local _, PS = ...

local unpack = unpack or table.unpack

PS = PS or {}
_G.PlateSmith = PS

PS.API_VERSION = 1
PS.QUEST_PROVIDER_API_VERSION = 1

local modules = {}
local moduleOrder = {}
local questProviders = {}
local questProviderOrder = {}
local initialized = false
local enabled = false

local function ReportError(scope, message)
    local text = string.format("PlateSmith %s: %s", scope, tostring(message))
    if type(geterrorhandler) == "function" then
        geterrorhandler()(text)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555" .. text .. "|r")
    end
end

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
    if not ok then ReportError(module.id .. "." .. method, result) end
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
    return definition
end

function PS:GetQuestProvider(id)
    return questProviders[id]
end

function PS:IterateQuestProviders()
    local index = 0
    return function()
        index = index + 1
        local provider = questProviderOrder[index]
        if provider then return provider.id, provider end
    end
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
    SafeInvoke = SafeInvoke,
}
