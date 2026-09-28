local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")

-- Named settings profiles; each character picks one. The runtime edits a
-- working copy, and a profile in SavedVariables only changes on Save, so
-- trying things out never overwrites it.
--
-- PlateSmithDB = {
--     profiles = { [name] = settings },      -- ProfileSchema.defaults
--     profileKeys = { ["Name - Realm"] = name },
--     state = { ... },                       -- ProfileSchema.stateDefaults
-- }
local Profiles = {}
PS.Profiles = Profiles

Profiles.DEFAULT = "Default"
Profiles.MAX_NAME_LENGTH = 32

local store, working, characterKey
local loads = 0
local listeners = {}
local changed = false

local function Defaults() return S.NormalizeSettings({}) end

local function CharacterKey()
    local realm
    if type(GetRealmName) == "function" then
        local ok, value = pcall(GetRealmName)
        realm = ok and Secret.String(value) or nil
    end
    return Secret.ReadName("player", "Unknown") .. " - " .. (realm or "Unknown")
end

-- Case-insensitive, so "raid" and "Raid" cannot both exist.
local function Find(name)
    if type(name) ~= "string" then return nil end
    local wanted = name:lower()
    for existing in pairs(store.profiles) do
        if existing:lower() == wanted then return existing end
    end
    return nil
end

Profiles.Find = Find

-- Returns the trimmed name, or nil and the reason it cannot be used.
function Profiles.CleanName(name)
    if type(name) ~= "string" then return nil, "name must be text" end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil, "name is empty" end
    if #name > Profiles.MAX_NAME_LENGTH then return nil, "name is too long" end
    -- "|" starts a chat escape sequence; control characters do not display.
    if name:find("[%c|]") then return nil, "name has unsupported characters" end
    return name
end

function Profiles.Notify()
    changed = false
    for _, listener in ipairs(listeners) do pcall(listener) end
end

-- Listeners run after any profile change; setting edits are batched by the ticker.
function Profiles.Subscribe(listener) listeners[#listeners + 1] = listener end

function Profiles.MarkChanged() changed = true end

function Profiles.Load()
    store = type(PlateSmithDB) == "table" and PlateSmithDB or {}
    PlateSmithDB = store
    for key in pairs(store) do
        if key ~= "profiles" and key ~= "profileKeys" and key ~= "state" then store[key] = nil end
    end
    if type(store.profiles) ~= "table" then store.profiles = {} end
    if type(store.profileKeys) ~= "table" then store.profileKeys = {} end
    store.state = S.NormalizeState(store.state)
    for name, settings in pairs(store.profiles) do
        if Profiles.CleanName(name) ~= name or type(settings) ~= "table" then
            store.profiles[name] = nil
        else
            S.NormalizeSettings(settings)
        end
    end
    if next(store.profiles) == nil then store.profiles[Profiles.DEFAULT] = Defaults() end

    characterKey = CharacterKey()
    local active = store.profileKeys[characterKey]
    if type(active) ~= "string" or not store.profiles[active] then
        active = store.profiles[Profiles.DEFAULT] and Profiles.DEFAULT or Profiles.List()[1]
        store.profileKeys[characterKey] = active
    end
    working = Table.DeepCopy(store.profiles[active])
    return working
end

function Profiles.State() return store and store.state end
PS.GetState = Profiles.State
function Profiles.Active() return store and store.profileKeys[characterKey] end

function Profiles.List()
    local names = {}
    for name in pairs(store.profiles) do names[#names + 1] = name end
    table.sort(names, function(left, right) return left:lower() < right:lower() end)
    return names
end

function Profiles.IsDirty()
    if not working then return false end
    return not Table.DeepEqual(working, store.profiles[Profiles.Active()])
end

-- Which settings differ from the saved profile, as dotted paths (for diagnostics and the Save bar).
function Profiles.Changes(limit)
    if not working then return {} end
    return Table.Differences(working, store.profiles[Profiles.Active()], limit)
end

-- Replaces the working copy in place (the runtime holds a reference to it) and reapplies it.
local function Load(settings)
    loads = loads + 1
    Table.Replace(working, Table.DeepCopy(settings))
    S.NormalizeSettings(working)
    PS.NamePolicy.Apply()
    PS.Refresh()
    Profiles.Notify()
end

-- Bumped each time other settings are loaded into the working copy (a switch, revert, reset or copy),
-- so a view can tell a new design from an edit.
function Profiles.Loads() return loads end

function Profiles.Save()
    store.profiles[Profiles.Active()] = Table.DeepCopy(working)
    Profiles.Notify()
    return true
end

function Profiles.Revert() Load(store.profiles[Profiles.Active()]) end

-- Another profile's settings into the working copy; Save keeps them.
function Profiles.CopyFrom(name)
    if not store.profiles[name] then return false, "profile does not exist" end
    Load(store.profiles[name])
    return true
end

-- Defaults into the working copy; like any edit it needs Save to keep.
function Profiles.Reset() Load(Defaults()) end

function Profiles.Switch(name)
    if Profiles.IsDirty() then return false, "save or revert changes first" end
    if not store.profiles[name] then return false, "profile does not exist" end
    store.profileKeys[characterKey] = name
    Load(store.profiles[name])
    return true
end

-- A new profile starts from defaults, or from a copy of an existing profile, and becomes active.
function Profiles.Create(name, copyFrom)
    local clean, reason = Profiles.CleanName(name)
    if not clean then return false, reason end
    if Find(clean) then return false, "a profile with that name exists" end
    if Profiles.IsDirty() then return false, "save or revert changes first" end
    if copyFrom ~= nil and not store.profiles[copyFrom] then return false, "profile does not exist" end
    store.profiles[clean] = copyFrom and Table.DeepCopy(store.profiles[copyFrom]) or Defaults()
    return Profiles.Switch(clean)
end

-- base, or base 2, base 3... : the first name no profile has (compared as Find does).
function Profiles.UniqueName(base)
    local clean = Profiles.CleanName(base) or Profiles.DEFAULT
    if not Find(clean) then return clean end
    for index = 2, 99 do
        local suffix = " " .. index
        local name = clean:sub(1, Profiles.MAX_NAME_LENGTH - #suffix) .. suffix
        if not Find(name) then return name end
    end
    return nil
end

-- A new profile from a built-in preset (Core/ProfilePresets.lua), named after it: it starts from
-- defaults, the preset's Blueprint is imported into it (all sections, checked as any import) and it
-- is saved. No other profile is touched; if the import fails the new profile is removed and the
-- previous one is active again. Returns true and the new name.
function Profiles.CreateFromPreset(id)
    local Presets = PS.ProfilePresets
    local preset = Presets and Presets.Get(id)
    if not preset then return false, "preset does not exist" end
    if Profiles.IsDirty() then return false, "save or revert changes first" end
    local text, reason = Presets.Document(id)
    if not text then return false, reason end
    local name = Profiles.UniqueName(preset.name)
    if not name then return false, "a profile with that name exists" end
    local previous = Profiles.Active()
    store.profiles[name] = Defaults()
    local ok
    ok, reason = Profiles.Switch(name)
    if ok then ok, reason = PS.ImportBlueprint(text) end
    if not ok then
        store.profiles[name] = nil
        store.profileKeys[characterKey] = previous
        Load(store.profiles[previous])
        return false, reason
    end
    Profiles.Save()
    return true, name
end

-- Renames the active profile for every character that uses it.
function Profiles.Rename(name)
    local clean, reason = Profiles.CleanName(name)
    if not clean then return false, reason end
    local old = Profiles.Active()
    local existing = Find(clean)
    if existing and existing ~= old then return false, "a profile with that name exists" end
    if clean == old then return true end
    store.profiles[clean], store.profiles[old] = store.profiles[old], nil
    for key, value in pairs(store.profileKeys) do
        if value == old then store.profileKeys[key] = clean end
    end
    Profiles.Notify()
    return true
end

-- Characters that used a deleted profile fall back to Default at their next login.
function Profiles.Delete(name)
    if not store.profiles[name] then return false, "profile does not exist" end
    if name == Profiles.Active() then return false, "the active profile cannot be deleted" end
    store.profiles[name] = nil
    for key, value in pairs(store.profileKeys) do
        if value == name then store.profileKeys[key] = nil end
    end
    Profiles.Notify()
    return true
end

PS.Ticker.Register("profiles.changes", 0.2, function()
    if changed then Profiles.Notify() end
end)
