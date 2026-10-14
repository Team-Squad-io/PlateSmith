-- Modules' settings pages in Studio (PlateSmith:RegisterStudioSettings, docs/MODULES.md): the registry, the settings
-- a module declares up front, and where their values live. Studio/Modules.lua builds the pages, Settings/Panel.lua
-- the Game Options pages that open them, Core/Blueprint.lua shares the profile ones.
local _, PS = ...
local Args = assert(PS._Args, "PlateSmith Modules missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")

-- An independent contract (docs/MODULES.md): the page definition and the kit a page is built with.
PS.STUDIO_API_VERSION = 1

local ModuleSettings = {}
PS.ModuleSettings = ModuleSettings

local entries, order = {}, {}
-- What PlateSmith's own pages pass to register as built-ins (their Profile and Character bindings are the profile's and
-- the character's own keys, PS.SetOption and PS.SetCharacterOption, so nothing of theirs moves).
local BUILTIN = {}
ModuleSettings.BUILTIN = BUILTIN

local MAX_TITLE, MAX_SUMMARY, MAX_KEY, MAX_SETTINGS, MAX_TEXT, MAX_CHOICES = 40, 120, 32, 64, 200, 32
local BLUEPRINT_PREFIX = "settings:"
ModuleSettings.BLUEPRINT_PREFIX = BLUEPRINT_PREFIX

-- A declared setting: { type = "boolean" | "range" | "enum" | "colour" | "text", default, scope = "profile" (Save,
-- Revert, Blueprints) | "character" (saved at once) }; range has min, max and optional step; enum its values; text an
-- optional maxLength. Valid(spec, value) returns the value made valid (a range clamped to its step), or nil.
local function Unit(value) return type(value) == "number" and value >= 0 and value <= 1 end
local TYPES = {
    boolean = function(_, value) if type(value) == "boolean" then return value end end,
    range = function(spec, value)
        if type(value) ~= "number" or value ~= value then return nil end
        value = math.max(spec.min, math.min(spec.max, value))
        if spec.step then value = spec.min + math.floor((value - spec.min) / spec.step + 0.5) * spec.step end
        return math.max(spec.min, math.min(spec.max, value))
    end,
    enum = function(spec, value) if spec.valueSet[value] then return value end end,
    colour = function(_, value)
        if type(value) ~= "table" or not (Unit(value.r) and Unit(value.g) and Unit(value.b)) then return nil end
        return { r = value.r, g = value.g, b = value.b }
    end,
    text = function(spec, value)
        if type(value) ~= "string" or #value > (spec.maxLength or MAX_TEXT) or value:find("[%c|]") then return nil end
        return value
    end,
}

local function Valid(spec, value)
    if value == nil then return nil end
    return TYPES[spec.type](spec, value)
end
ModuleSettings.Valid = Valid

-- A copy of one declaration, checked; or nil and the reason.
local function Declaration(key, spec)
    if type(key) ~= "string" or #key > MAX_KEY or not key:match("^[%a][%w_]*$") then
        return nil, "setting keys are letters, digits and _, at most " .. MAX_KEY .. " characters: " .. tostring(key)
    end
    if type(spec) ~= "table" or not TYPES[spec.type] then
        return nil, "setting " .. key .. " needs a type: boolean, range, enum, colour or text"
    end
    local copy = { type = spec.type, scope = spec.scope or "profile", min = spec.min, max = spec.max, step = spec.step,
        maxLength = spec.maxLength }
    if copy.scope ~= "profile" and copy.scope ~= "character" then
        return nil, "setting " .. key .. " scope must be profile or character"
    end
    if copy.type == "range" then
        if type(copy.min) ~= "number" or type(copy.max) ~= "number" or copy.min >= copy.max
            or (copy.step ~= nil and (type(copy.step) ~= "number" or copy.step <= 0)) then
            return nil, "setting " .. key .. " needs min < max (and a positive step)"
        end
    elseif copy.type == "enum" then
        if type(spec.values) ~= "table" or #spec.values == 0 or #spec.values > MAX_CHOICES then
            return nil, "setting " .. key .. " needs its values (1 to " .. MAX_CHOICES .. ")"
        end
        copy.values, copy.valueSet = {}, {}
        for index, value in ipairs(spec.values) do
            if (type(value) ~= "string" and type(value) ~= "number") or copy.valueSet[value] then
                return nil, "setting " .. key .. " values must be distinct text or numbers"
            end
            copy.values[index], copy.valueSet[value] = value, true
        end
    elseif copy.type == "text" and copy.maxLength ~= nil
        and (type(copy.maxLength) ~= "number" or copy.maxLength < 1 or copy.maxLength > MAX_TEXT) then
        return nil, "setting " .. key .. " maxLength must be 1 to " .. MAX_TEXT
    end
    local default = Valid(copy, spec.default)
    if default == nil or (copy.type == "range" and default ~= spec.default) then
        return nil, "setting " .. key .. " needs a valid default"
    end
    copy.default = default
    return copy
end

local function Text(value, limit)
    return type(value) == "string" and value ~= "" and #value <= limit and not value:find("[%c|]")
end

-- Where a module's values live: the active profile's working copy (modules["<id>"]), or the character's.
local function Store(scope, id, create)
    local root
    if scope == "character" then
        root = PS.GetCharacterSettings and PS.GetCharacterSettings()
    else
        root = PS.GetSettings and PS.GetSettings()
    end
    if type(root) ~= "table" then return nil end
    local modules = root.modules
    if type(modules) ~= "table" then
        if not create then return nil end
        modules = {}
        root.modules = modules
    end
    local own = modules[id]
    if type(own) ~= "table" then
        if not create then return nil end
        own = {}
        modules[id] = own
    end
    return own, modules, root
end

-- Registers a module's Studio settings page (docs/MODULES.md, "Studio settings"). true, or false and the reason.
-- A definition outside the Studio API range is still listed (greyed, saying why) but gets no page.
function ModuleSettings.Register(id, definition, builtin)
    if type(id) ~= "string" then return false, "studio settings need the module's id" end
    if entries[id] then return false, "studio settings are already registered: " .. id end
    if builtin ~= BUILTIN and not (PS.GetModule and PS.GetModule(id)) then
        return false, "register the module first (PlateSmith:RegisterModule): " .. id
    end
    if type(definition) ~= "table" then return false, "studio settings definition must be a table" end
    if not Text(definition.title, MAX_TITLE) then
        return false, "studio settings need a title of at most " .. MAX_TITLE .. " characters"
    end
    if definition.summary ~= nil and not Text(definition.summary, MAX_SUMMARY) then
        return false, "summary must be text of at most " .. MAX_SUMMARY .. " characters"
    end
    if definition.icon ~= nil and type(definition.icon) ~= "number" and type(definition.icon) ~= "string" then
        return false, "icon must be a texture path or file ID"
    end
    for _, name in ipairs({ "build", "OnSettingsChanged", "OnShow" }) do
        if definition[name] ~= nil and type(definition[name]) ~= "function" then
            return false, name .. " must be a function"
        end
    end
    if type(definition.build) ~= "function" then return false, "studio settings need build(page, kit)" end
    local settings, count = {}, 0
    if definition.settings ~= nil and type(definition.settings) ~= "table" then return false, "settings must be a table" end
    for key, spec in pairs(definition.settings or {}) do
        count = count + 1
        if count > MAX_SETTINGS then return false, "at most " .. MAX_SETTINGS .. " declared settings" end
        local declared, reason = Declaration(key, spec)
        if not declared then return false, reason end
        settings[key] = declared
    end
    local entry = { id = id, title = definition.title, summary = definition.summary, icon = definition.icon,
        build = definition.build, OnSettingsChanged = definition.OnSettingsChanged, OnShow = definition.OnShow,
        gameOptions = definition.gameOptions ~= false, builtin = builtin == BUILTIN, settings = settings,
        launcher = definition.launcher, profileKeys = builtin == BUILTIN and definition.profileKeys or nil,
        state = "ok", errors = 0 }
    local api = PS.STUDIO_API_VERSION
    local low, high = definition.studioApiMin, definition.studioApiMax
    local reason
    if (low ~= nil and type(low) ~= "number") or (high ~= nil and type(high) ~= "number") then
        reason = "studioApiMin and studioApiMax must be numbers"
    elseif low and low > api then
        entry.state, entry.note = "api-missing", "needs a newer PlateSmith"
        reason = "studio API range starts above this PlateSmith version"
    elseif high and high < api then
        entry.state, entry.note = "api-missing", "needs an update"
        reason = "studio API range ends below this PlateSmith version"
    end
    if reason and entry.state ~= "api-missing" then return false, reason end
    entries[id], order[#order + 1] = entry, entry
    entry.order = #order
    local options = PS.Options
    if options and type(options.OnModuleSettingsRegistered) == "function" then
        local ok, failure = pcall(options.OnModuleSettingsRegistered, options, entry)
        if not ok then Chat.ReportError("module settings " .. id, failure) end
    end
    if reason then return false, reason end
    return true
end

function PS.RegisterStudioSettings(...)
    local id, definition = Args(...)
    return ModuleSettings.Register(id, definition)
end

function ModuleSettings.Get(id) return entries[id] end

-- Every registration in order, built-ins first (they register while PlateSmith loads).
function ModuleSettings.List() return order end

-- The value of a declared setting: the stored one while it is valid, else its default.
function ModuleSettings.Value(id, key)
    local entry = entries[id]
    local spec = entry and entry.settings[key]
    if not spec then return nil end
    local own = Store(spec.scope, id, false)
    local value = own and Valid(spec, own[key])
    if value == nil then value = spec.default end
    if type(value) == "table" then return Table.DeepCopy(value) end
    return value
end

function PS.GetModuleOption(...)
    local id, key = Args(...)
    return ModuleSettings.Value(id, key)
end

local function SameValue(left, right)
    if type(left) == "table" and type(right) == "table" then return Table.DeepEqual(left, right) end
    return left == right
end

-- Calls the module's OnSettingsChanged(key, value), contained.
function ModuleSettings.Changed(entry, key, value)
    if not entry.OnSettingsChanged then return end
    local ok, failure = pcall(entry.OnSettingsChanged, key, value)
    if not ok then Chat.ReportError("module settings " .. entry.id .. ".OnSettingsChanged", failure) end
end

-- Writes a declared setting: made valid by its declaration, a profile one in the working copy (Save keeps it, Revert
-- undoes it; its default is stored as nothing, so going back to it is no change) and a character one at once. Then
-- OnSettingsChanged. true, or false and the reason; nothing is written for an invalid value.
function ModuleSettings.Set(id, key, value)
    local entry = entries[id]
    if not entry then return false, "no studio settings for " .. tostring(id) end
    local spec = entry.settings[key]
    if not spec then return false, "undeclared setting: " .. tostring(key) end
    local valid = Valid(spec, value)
    if valid == nil then return false, "invalid value for " .. key end
    local own, modules, root = Store(spec.scope, id, true)
    if not own then return false, "settings are not loaded" end
    if SameValue(valid, spec.default) then own[key] = nil else own[key] = valid end
    if next(own) == nil then modules[id] = nil end
    if next(modules) == nil then root.modules = nil end
    if spec.scope == "profile" and PS.Profiles then PS.Profiles.MarkChanged() end
    ModuleSettings.Changed(entry, key, valid)
    return true
end

function PS.SetModuleOption(...)
    local id, key, value = Args(...)
    return ModuleSettings.Set(id, key, value)
end

-- What a page's state reports (diagnostics: modules.<id>.studio): ok, error: ..., disabled or api-missing.
function ModuleSettings.State(entry)
    if entry.state == "error" then return "error: " .. tostring(entry.lastError or "unknown") end
    return entry.state
end

-- One contained failure of a page's callbacks: reported once; the fifth turns the page off for the session.
ModuleSettings.MAX_ERRORS = 5
function ModuleSettings.Fail(entry, failure)
    entry.errors = entry.errors + 1
    entry.lastError = tostring(failure):gsub("\n.*", ""):sub(1, 160)
    if entry.errors == 1 then Chat.ReportError("module settings " .. entry.id, failure) end
    if entry.state == "ok" then entry.state = "error" end
    if entry.errors >= ModuleSettings.MAX_ERRORS and entry.state ~= "disabled" then
        entry.state = "disabled"
        local options = PS.Options
        if options and type(options.OnModuleSettingsFailed) == "function" then
            pcall(options.OnModuleSettingsFailed, options, entry)
        end
        return true
    end
    return entry.state == "disabled"
end

-- Blueprints (Core/Blueprint.lua): a module's profile settings travel under modules["settings:<id>"], only those away
-- from their default and only for modules installed here (validated by their declaration). Older readers skip them.
function ModuleSettings.Export(db)
    local exported
    for _, entry in ipairs(order) do
        local stored = type(db) == "table" and type(db.modules) == "table" and db.modules[entry.id]
        if type(stored) == "table" then
            local values
            for key, spec in pairs(entry.settings) do
                local value = spec.scope == "profile" and Valid(spec, stored[key]) or nil
                if value ~= nil and not SameValue(value, spec.default) then
                    values = values or {}
                    values[key] = value
                end
            end
            if values then
                exported = exported or {}
                exported[BLUEPRINT_PREFIX .. entry.id] = values
            end
        end
    end
    return exported
end

-- A Blueprint's modules entry: nil when it is not module settings PlateSmith knows here (another module's field, or a
-- module not installed: skipped); else the values to store (known keys valid by declaration; unknown keys skipped, as a
-- newer version's), or false and the reason for a known key with a bad value.
function ModuleSettings.Parse(key, value)
    if type(key) ~= "string" or key:sub(1, #BLUEPRINT_PREFIX) ~= BLUEPRINT_PREFIX then return nil end
    local entry = entries[key:sub(#BLUEPRINT_PREFIX + 1)]
    if not entry then return nil end
    if type(value) ~= "table" then return false, "must be an object" end
    local values = {}
    for name, raw in pairs(value) do
        local spec = entry.settings[name]
        if spec and spec.scope == "profile" then
            local valid = Valid(spec, raw)
            if valid == nil then return false, name .. " has an unsupported value" end
            if not SameValue(valid, spec.default) then values[name] = valid end
        end
    end
    return values, entry.id
end

-- An import's settings section: every installed module with profile settings takes the Blueprint's values (none: its
-- defaults); data of modules not installed here stays as it was.
function ModuleSettings.Apply(db, parsed)
    for _, entry in ipairs(order) do
        local profiled = false
        for _, spec in pairs(entry.settings) do profiled = profiled or spec.scope == "profile" end
        if profiled then
            local values = parsed and parsed[entry.id]
            if type(db.modules) ~= "table" then db.modules = nil end
            if values and next(values) then
                db.modules = db.modules or {}
                db.modules[entry.id] = Table.DeepCopy(values)
            elseif db.modules then
                db.modules[entry.id] = nil
                if next(db.modules) == nil then db.modules = nil end
            end
        end
    end
end
