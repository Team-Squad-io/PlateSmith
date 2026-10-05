-- Where plates show: Blizzard's show CVars per plate type, switched off where the profile hides that
-- type (the place from PS.PlateContext, and in or out of combat). Where a type shows, its CVar is put
-- back to what it was before PlateSmith hid it, so with every cell on nothing is ever written.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local NamePolicy = assert(PS.NamePolicy, "PlateSmith NamePolicy missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

local Visibility = {}
PS.PlateVisibility = Visibility

local GROUP = "plateVisibility"
local V = S.VISIBILITY
Visibility.TYPES, Visibility.PLACES, Visibility.COMBAT = V.TYPES, V.PLACES, V.COMBAT
Visibility.CVARS = { enemy = "nameplateShowEnemies", friendlyPlayer = "nameplateShowFriends",
    friendlyNPC = "nameplateShowFriendlyNPCs" }
-- The combat columns write at PLAYER_REGEN_DISABLED, which is not yet proven in game; until it is,
-- they are hidden in Studio and their settings are not applied.
Visibility.combatColumns = false

-- applied[cvar]: "hide" once PlateSmith hid it, "show" once it put the original back in combat
-- (the record is kept until combat ends, so a second hide in the same fight keeps the true original).
local applied = {}
-- inCombat: between PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED (nil: not known yet).
local state = { inCombat = nil }
Visibility.state = state

local function Settings() return type(PS.GetSettings) == "function" and PS.GetSettings() or nil end

-- Whether this client has a CVar for friendly NPCs' plates. Without it one switch shows every
-- friendly plate, so Players' cells stand for all of them (Studio shows one Friendly row).
function Visibility.FriendlyShared()
    return NamePolicy.Read(Visibility.CVARS.friendlyNPC) == nil
end

-- Whether settings show plateType's plates in place (world, dungeon, pvp, city) and combat state.
function Visibility.Shown(settings, plateType, place, inCombat)
    local keys = V.keys[plateType]
    if not (settings and keys) then return true end
    if settings[keys[place] or keys.world] == false then return false end
    if not Visibility.combatColumns then return true end
    local combat = settings[keys.combat]
    if combat == "never" then return false end
    if inCombat then return combat ~= "noCombat" end
    return combat ~= "combat"
end

-- Whether settings keep every cell at its default (nothing hidden anywhere).
function Visibility.AllDefault(settings)
    if not settings then return true end
    for _, key in ipairs(V.KEYS) do
        if settings[key] ~= nil and settings[key] ~= S.defaults[key] then return false end
    end
    return true
end

local function InCombat()
    if state.inCombat == nil then return Secret.InCombat() end
    return state.inCombat
end

local function Hide(cvar)
    if applied[cvar] == "hide" then return end
    if NamePolicy.WriteCaptured(GROUP, cvar, "0") then
        applied[cvar] = "hide"
    end
end

-- Puts cvar back: out of combat its record is restored and forgotten (the next hide records the
-- player's value then); in combat the original is written (queued) and the record kept.
local function Show(cvar)
    local record = NamePolicy.CapturedGroup(GROUP)
    if applied[cvar] == nil and not (record and record[cvar] ~= nil) then return end
    if Secret.InCombat() then
        if applied[cvar] ~= "show" and record and record[cvar] ~= nil then
            NamePolicy.Write(cvar, record[cvar])
        end
        applied[cvar] = "show"
        return
    end
    NamePolicy.RestoreGroup(GROUP, cvar)
    applied[cvar] = nil
end

-- Whether settings hide plateType anywhere (a place, or the combat column while it is used).
local function HidesSomewhere(settings, plateType)
    local keys = V.keys[plateType]
    for _, place in ipairs(V.PLACES) do
        if settings[keys[place]] == false then return true end
    end
    return Visibility.combatColumns and settings[keys.combat] ~= nil and settings[keys.combat] ~= "always"
end

-- Once a session, before the first write: a type the profile hides somewhere whose show CVar holds
-- PlateSmith's "0" with no record most likely stayed hidden when the game closed without a logout
-- (a crash: the saved record is the last clean logout's, cleared then). Its original is marked lost,
-- so the client's default stands in and showing the type puts that back. A player who turned such a
-- type off by hand gets it back once. (Stacking.CheckOriginals and NamePolicy's CheckLost do the same.)
local checked = false
local function CheckLost(settings)
    if checked then return end
    checked = true
    if Visibility.AllDefault(settings) then return end
    local record = NamePolicy.CapturedGroup(GROUP) or {}
    local shared = Visibility.FriendlyShared()
    for _, plateType in ipairs(V.TYPES) do
        local cvar = Visibility.CVARS[plateType]
        if not (shared and plateType == "friendlyNPC") and record[cvar] == nil and HidesSomewhere(settings, plateType)
            and NamePolicy.Read(cvar) == "0" then
            local default = NamePolicy.Default(cvar)
            if default ~= nil and default ~= "0" then NamePolicy.MarkLost(GROUP, cvar) end
        end
    end
end

-- Brings Blizzard's show CVars in line with the profile and where the player is. Cheap and safe at any
-- time (every refresh calls it); nothing is written that already holds.
function Visibility.Apply()
    local settings = Settings()
    if not (settings and PS.Profiles and PS.Profiles.State()) then return false end
    CheckLost(settings)
    local active = settings.enabled ~= false and not Visibility.AllDefault(settings)
    local place = PS.PlateContext and PS.PlateContext.Current() or "world"
    local inCombat = InCombat()
    local shared = Visibility.FriendlyShared()
    for _, plateType in ipairs(V.TYPES) do
        local cvar = Visibility.CVARS[plateType]
        if not (shared and plateType == "friendlyNPC") then
            if active and not Visibility.Shown(settings, plateType, place, inCombat) then Hide(cvar) else Show(cvar) end
        end
    end
    return true
end

-- Puts every hidden plate type back now (logout). keep (a logout or /reload in combat, when the client
-- may block the write unseen): the originals stay recorded, and the next login's Apply puts them back.
function Visibility.RestoreAll(immediate, keep)
    NamePolicy.RestoreGroup(GROUP, nil, immediate, keep)
    for cvar in pairs(applied) do applied[cvar] = nil end
end

-- For diagnostics: the friendly NPC switch ("own" or "shared"), whether the profile hides anything,
-- and each CVar's state ("hidden", "restoring" in combat, else "untouched").
function Visibility.Report()
    local cvars = {}
    for _, plateType in ipairs(V.TYPES) do
        local cvar = Visibility.CVARS[plateType]
        cvars[cvar] = applied[cvar] == "hide" and "hidden" or applied[cvar] == "show" and "restoring" or "untouched"
    end
    return { friendlyNPCs = Visibility.FriendlyShared() and "shared" or "own", hides = not Visibility.AllDefault(Settings()),
        combatColumns = Visibility.combatColumns, cvars = cvars }
end

-- For the suites: a new session.
function Visibility._Reset()
    for cvar in pairs(applied) do applied[cvar] = nil end
    state.inCombat, checked = nil, false
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
    PS._RegisterEvent(eventFrame, event, "platesmith.visibility")
end
eventFrame:SetScript("OnEvent", function(_, event)
    if not Settings() then return end
    if event == "PLAYER_REGEN_DISABLED" then
        -- Just before the lockdown, so a combat column's write still lands at once.
        state.inCombat = true
        if Visibility.combatColumns then Visibility.Apply() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
        -- Queued writes first, so none lands over what applies now.
        NamePolicy.FlushPending()
        Visibility.Apply()
    else
        NamePolicy.FlushPending()
        Visibility.RestoreAll(true, state.inCombat == true or Secret.InCombat())
    end
end)
