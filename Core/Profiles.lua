local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Designs = assert(PS.Designs, "PlateSmith Designs missing")

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

-- Each action a player runs (a new profile, a switch, Save, Revert, Delete...) is measured as one
-- (Performance.RunAction: /ps diagnose's performance.memory). The public functions are the measured
-- ones; inside this file the actions call each other's unmeasured bodies, so one click is one action.
local function Measured(kind, fn, ...)
    local Performance = PS.Performance
    if Performance and Performance.RunAction then return Performance.RunAction(Performance.ACTIONS[kind], fn, ...) end
    return fn(...)
end

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

-- IsDirty compares the whole working copy with the saved profile, so its answer is kept until
-- something can change it (an edit, a load or a save) and each Notify asks at most once.
-- lastDifference: the keys to where the last comparison found the copies differ. Edits come in runs
-- on one setting (a slider drag), so that place is compared first: a difference there is a
-- difference in the whole, and only when it is gone is the whole walked again.
local dirtyKnown, dirty = false, false
local lastDifference, scratchPath = { length = 0 }, { length = 0 }
local function Invalidate() dirtyKnown = false end

-- For the tests: IsDirty's comparisons, and the values they compared.
Profiles.comparisons, Profiles.comparedNodes = 0, 0

-- Whether two plain tables differ; if they do, path holds the keys to the first difference.
local function FindDifference(left, right, path, depth)
    Profiles.comparedNodes = Profiles.comparedNodes + 1
    if type(left) ~= "table" or type(right) ~= "table" then
        if left == right then return false end
        path.length = depth - 1
        return true
    end
    for key, child in pairs(left) do
        path[depth] = key
        if FindDifference(child, right[key], path, depth + 1) then return true end
    end
    for key in pairs(right) do
        if left[key] == nil then
            path[depth], path.length = key, depth
            return true
        end
    end
    return false
end

-- Whether the values at path differ (where the shapes part, the values there are compared).
local function DiffersAt(left, right, path)
    for index = 1, path.length do
        if type(left) ~= "table" or type(right) ~= "table" then break end
        local key = path[index]
        left, right = left[key], right[key]
    end
    return FindDifference(left, right, scratchPath, 1)
end

local function OwnerShown(owner)
    if owner.IsVisible then return owner:IsVisible() end
    return not owner.IsShown or owner:IsShown()
end

function Profiles.Notify()
    changed = false
    PS.Ticker.SetEnabled("profiles.changes", false)
    Invalidate()
    for _, entry in ipairs(listeners) do
        if entry.owner and not OwnerShown(entry.owner) then
            entry.stale = true
        else
            entry.stale = false
            pcall(entry.listener)
        end
    end
end

-- Listeners run after any profile change; setting edits are batched by the ticker. With an owner
-- frame, the listener is skipped while the frame is hidden and runs when it is shown again.
function Profiles.Subscribe(listener, owner)
    local entry = { listener = listener, owner = owner }
    listeners[#listeners + 1] = entry
    if owner and owner.HookScript then
        owner:HookScript("OnShow", function()
            if entry.stale then
                entry.stale = false
                pcall(listener)
            end
        end)
    end
end

-- The changes tick runs only between an edit and the Notify that reports it.
function Profiles.MarkChanged()
    Invalidate()
    if not changed then
        changed = true
        PS.Ticker.SetEnabled("profiles.changes", true)
    end
end

-- Tells the player once what a migration (or an old Blueprint) changed in profile name.
function Profiles.NoteMigration(name, note)
    if type(note) == "table" and (note.threatRulesDisabled or 0) > 0 then
        PS.Chat.Print(string.format(PS.L["Threat rules in %s were turned off because Show threat details was off in "
            .. "1.0.3. Turn them on in Studio › Rules."], tostring(name)))
    end
    if type(note) == "table" and note.dungeonOverlayOff then
        PS.Chat.Print(string.format(PS.L["The dungeon friendly overlay test was turned off in %s; it is now under "
            .. "Settings › Experimental if you want to try it again."], tostring(name)))
    end
end

function Profiles.Load()
    store = type(PlateSmithDB) == "table" and PlateSmithDB or {}
    PlateSmithDB = store
    for key in pairs(store) do
        if key ~= "profiles" and key ~= "profileKeys" and key ~= "state" then store[key] = nil end
    end
    if type(store.profiles) ~= "table" then store.profiles = {} end
    if type(store.profileKeys) ~= "table" then store.profileKeys = {} end
    store.state = S.NormalizeState(store.state)
    -- Threat colours arriving off is said once, however many profiles had it turned off; so is where
    -- 1.1.x's Studio Layout switch went (a profile saved before 1.2.0: schema 27 or older), naming the
    -- Dungeon layout's new place when one had it.
    local threatColoursOff, designsNote = false, nil
    for name, settings in pairs(store.profiles) do
        if Profiles.CleanName(name) ~= name or type(settings) ~= "table" then
            store.profiles[name] = nil
        else
            if (tonumber(settings.schemaVersion) or 1) < 28 then
                local plates = settings.plateProfiles
                local dungeon = type(plates) == "table" and type(plates.enemyDungeon) == "table"
                designsNote = (designsNote == "dungeon" or dungeon) and "dungeon" or "designs"
            end
            S.NormalizeSettings(settings)
            local note = S.TakeMigrationNote(settings)
            threatColoursOff = threatColoursOff or (type(note) == "table" and note.threatColoursOff == true)
            Profiles.NoteMigration(name, note)
        end
    end
    if threatColoursOff then
        PS.Chat.Print(PS.L["New: Threat colours, in Studio › Settings › Modules › Threat "
            .. "(off for your existing profiles)."])
    end
    -- 1.3.0 moved the threat settings (Game Options' Threat page, Behaviour & display's Threat colours) into Studio;
    -- said once to an install that had them where they were.
    if store.state.threatMovedSaid ~= true then
        if next(store.profiles) ~= nil and not threatColoursOff then
            PS.Chat.Print(PS.L["1.3.0: Threat settings (your role, Threat colours, the threat windows) are now in Studio › "
                .. "Settings › Modules › Threat."])
        end
        store.state.threatMovedSaid = true
    end
    if designsNote == "dungeon" then
        PS.Chat.Print(PS.L["1.2.0: Studio's Layout switch is now a Design menu on each tab; your Dungeon layout is now "
            .. "the Enemies › Dungeons & raids design."])
    elseif designsNote then
        PS.Chat.Print(PS.L["1.2.0: Studio's Layout switch is now a Design menu on each tab."])
    end
    if next(store.profiles) == nil then
        store.profiles[Profiles.DEFAULT] = Defaults()
        -- A fresh install: Studio's first open offers the first-run picker until a choice is made
        -- (Studio/FirstRun.lua). An existing install never has firstRunDone false.
        if store.state.firstRunDone == nil then store.state.firstRunDone = false end
    end

    characterKey = CharacterKey()
    local active = store.profileKeys[characterKey]
    if type(active) ~= "string" or not store.profiles[active] then
        active = store.profiles[Profiles.DEFAULT] and Profiles.DEFAULT or Profiles.List()[1]
        store.profileKeys[characterKey] = active
    end
    working = Table.DeepCopy(store.profiles[active])
    Invalidate()
    Designs.Invalidate()
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
    if not dirtyKnown then
        local saved = store.profiles[Profiles.Active()]
        Profiles.comparisons = Profiles.comparisons + 1
        dirty = (dirty and DiffersAt(working, saved, lastDifference))
            or FindDifference(working, saved, lastDifference, 1)
        dirtyKnown = true
    end
    return dirty
end

-- The active profile as last saved (read only: Save replaces it whole), for a view that compares one area.
function Profiles.Saved() return store and store.profiles[Profiles.Active()] end

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
    Invalidate()
    Designs.Invalidate()
    PS.NamePolicy.Apply()
    PS.Refresh()
    Profiles.Notify()
end

-- Bumped each time other settings are loaded into the working copy (a switch, revert, reset or copy),
-- so a view can tell a new design from an edit.
function Profiles.Loads() return loads end

local function Save()
    store.profiles[Profiles.Active()] = Table.DeepCopy(working)
    Invalidate()
    Profiles.Notify()
    return true
end
function Profiles.Save() return Measured("save", Save) end

local function Revert() Load(store.profiles[Profiles.Active()]) end
function Profiles.Revert() Measured("revert", Revert) end

-- Another profile's settings into the working copy; Save keeps them.
local function CopyFrom(name)
    if not store.profiles[name] then return false, "profile does not exist" end
    Load(store.profiles[name])
    return true
end
function Profiles.CopyFrom(name) return Measured("copy", CopyFrom, name) end

-- Defaults into the working copy; like any edit it needs Save to keep.
local function Reset() Load(Defaults()) end
function Profiles.Reset() Measured("reset", Reset) end

local function Switch(name)
    if Profiles.IsDirty() then return false, "save or revert changes first" end
    if not store.profiles[name] then return false, "profile does not exist" end
    store.profileKeys[characterKey] = name
    Load(store.profiles[name])
    return true
end
function Profiles.Switch(name) return Measured("switch", Switch, name) end

-- A new profile starts from defaults, or from a copy of an existing profile, and becomes active.
local function Create(name, copyFrom)
    local clean, reason = Profiles.CleanName(name)
    if not clean then return false, reason end
    if Find(clean) then return false, "a profile with that name exists" end
    if Profiles.IsDirty() then return false, "save or revert changes first" end
    if copyFrom ~= nil and not store.profiles[copyFrom] then return false, "profile does not exist" end
    store.profiles[clean] = copyFrom and Table.DeepCopy(store.profiles[copyFrom]) or Defaults()
    return Switch(clean)
end
function Profiles.Create(name, copyFrom) return Measured("new", Create, name, copyFrom) end

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
-- defaults, the preset's Blueprint is imported into it (all sections, checked as any import), the look
-- is recorded in it (look, lookVersion) and it is saved. No other profile is touched; if the import fails
-- the new profile is removed and the previous one is active again. Returns true and the new name.
-- The defaults go into the working copy quietly (no refresh of the plates, no Notify): the import
-- refreshes the plates and Save tells the listeners once, with the load counted, so Studio and the
-- plates draw the new look once instead of the defaults first. Until Save the saved copy is an empty
-- table (normalized, it is the defaults).
local function CreateFromPreset(id)
    local Presets = PS.ProfilePresets
    local preset = Presets and Presets.Get(id)
    if not preset then return false, "preset does not exist" end
    if Profiles.IsDirty() then return false, "save or revert changes first" end
    local text, reason = Presets.Document(id)
    if not text then return false, reason end
    local name = Profiles.UniqueName(preset.name)
    if not name then return false, "a profile with that name exists" end
    local previous = Profiles.Active()
    store.profiles[name] = {}
    store.profileKeys[characterKey] = name
    loads = loads + 1
    -- A copy, as Load makes: fresh defaults can share tables with the schema's own.
    Table.Replace(working, Table.DeepCopy(Defaults()))
    Invalidate()
    Designs.Invalidate()
    local ok
    -- A failed import is undone below (the previous profile loaded), so the import keeps no copy to restore.
    ok, reason = PS.ImportBlueprint(text, nil, true)
    if not ok then
        store.profiles[name] = nil
        store.profileKeys[characterKey] = previous
        Load(store.profiles[previous])
        return false, reason
    end
    -- The look it was made from, kept with the profile (never in a Blueprint: Schema's NormalizeSettings checks it).
    working.look, working.lookVersion = id, Presets.LOOK_VERSION
    Save()
    return true, name
end
function Profiles.CreateFromPreset(id) return Measured("new", CreateFromPreset, id) end

-- Renames the active profile for every character that uses it.
local function Rename(name)
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
    if PS.AutoProfile then PS.AutoProfile.ProfileRenamed(old, clean) end
    Profiles.Notify()
    return true
end
function Profiles.Rename(name) return Measured("rename", Rename, name) end

-- Characters that used a deleted profile fall back to Default at their next login.
local function Delete(name)
    if not store.profiles[name] then return false, "profile does not exist" end
    if name == Profiles.Active() then return false, "the active profile cannot be deleted" end
    store.profiles[name] = nil
    for key, value in pairs(store.profileKeys) do
        if value == name then store.profileKeys[key] = nil end
    end
    if PS.AutoProfile then PS.AutoProfile.ProfileDeleted(name) end
    Profiles.Notify()
    return true
end
function Profiles.Delete(name) return Measured("delete", Delete, name) end

PS.Ticker.Register("profiles.changes", 0.2, function()
    if changed then Profiles.Notify() end
end)
PS.Ticker.SetEnabled("profiles.changes", false)
