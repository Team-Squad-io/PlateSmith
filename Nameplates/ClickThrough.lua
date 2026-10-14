-- Clicking: whether a click on a plate selects its unit or passes through, per kind of plate. Its home is Settings ›
-- Behaviour & display › Clicking; Players' and Friendly NPCs' Plate settings › Friendly plates show the same setting
-- as a Clicks row (STANDARDS section 2a rule 3). Each row is backed by what this client has:
-- - Friendly players (clickFriendlyPlayer): Blizzard's names-only switch for friendly players, whose one owner is
--   NamePolicy (ApplyNamesOnly): on, Blizzard clears their plates' hit-test points. Clickable (the default) keeps it
--   off while PlateSmith draws them outdoors, Click through on; Blizzard's plates and dungeons are as before.
-- - Friendly NPCs (clickFriendlyNPC) and Enemies (clickEnemy): the client's click-through switch for the category
--   (C_NamePlate.SetNamePlate<Friendly|Enemy>ClickThrough) where it has one, else the category's hit-test insets
--   (C_NamePlateManager.SetNamePlateHitTestInsets) grown far past the plate, which leaves it no click area. The
--   client's Friendly category is every friendly plate, players and NPCs together, so Friendly NPCs' Click through
--   makes friendly players click through too (SharedThrough: the Players rows say so and are locked). The Friendly
--   category is set outside dungeons & raids only, where PlateSmith draws friendly plates; in them the game's stands.
-- - Your own plate (clickSelf): the client's switch only.
-- Clickable (game) writes nothing; Click through sets the switch or insets while PlateSmith runs, through
-- NamePolicy's capture and restore (each registered as an accessor): the original captured once before the first
-- write, writes queued in combat, put back on Clickable, PlateSmith off, Revert or a profile change, and logout.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local NamePolicy = assert(PS.NamePolicy, "PlateSmith NamePolicy missing")

local ClickThrough = {}
PS.ClickThrough = ClickThrough

local GROUP = "clickThrough"
-- Each side's inset for Click through: far past any plate (a Large plate is about 240 x 85), so the area is gone
-- however the client measures it (the plate's bounds or its hit-test points). The client's own are 0.
local THROUGH_INSET = 1000
local GAME_INSETS = "0,0,0,0"

-- setting key -> the client's category: its click-through switch (C_NamePlate.SetNamePlate<api>ClickThrough and its
-- getter), else its Enum.NamePlateType for the hit-test insets. friendly: set outside dungeons & raids only.
ClickThrough.CATEGORIES = {
    { key = "clickFriendlyNPC", api = "Friendly", insets = "Friendly", friendly = true },
    { key = "clickEnemy", api = "Enemy", insets = "Enemy" },
    { key = "clickSelf", api = "Self" },
}
for _, category in ipairs(ClickThrough.CATEGORIES) do
    category.switchName = "nameplateClickThrough." .. category.api
    if category.insets then category.insetName = "nameplateHitTestInsets." .. category.insets end
end
local PLAYERS = "clickFriendlyPlayer"

-- applied[name]: the value PlateSmith last wrote; nil while the game's own stands.
local applied = {}

local function Settings() return type(PS.GetSettings) == "function" and PS.GetSettings() or nil end

-- Insets as text, "left,right,top,bottom", each to a tenth (the client may hand back 1000 as 999.99997).
local function InsetText(...)
    local parts = {}
    for index = 1, 4 do
        local value = select(index, ...)
        if not Secret.IsReadable(value) or type(value) ~= "number" then return nil end
        parts[index] = (string.format("%.1f", value):gsub("%.0$", ""))
    end
    return table.concat(parts, ",")
end
local THROUGH_INSETS = InsetText(THROUGH_INSET, THROUGH_INSET, THROUGH_INSET, THROUGH_INSET)

local function ParseInsets(text)
    local left, right, top, bottom = tostring(text):match("^(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)$")
    left, right, top, bottom = tonumber(left), tonumber(right), tonumber(top), tonumber(bottom)
    if not (left and right and top and bottom) then return nil end
    return left, right, top, bottom
end

-- The client's switch for category, or its insets: the name NamePolicy knows it by (registered on first ask, again
-- when the client's functions change), the value for Click through, and the kind ("switch" or "insets"). nil when
-- the client has neither.
local function Mechanism(category)
    local plate = C_NamePlate
    local get, set
    if type(plate) == "table" then
        get, set = plate["GetNamePlate" .. category.api .. "ClickThrough"], plate["SetNamePlate" .. category.api .. "ClickThrough"]
    end
    if type(get) == "function" and type(set) == "function" then
        if category.registered ~= get then
            NamePolicy.RegisterAccessor(category.switchName, get, set)
            category.registered = get
        end
        return category.switchName, "1", "switch"
    end
    local manager, types = C_NamePlateManager, Enum and Enum.NamePlateType
    local kind = category.insets and type(types) == "table" and types[category.insets] or nil
    if kind == nil or type(manager) ~= "table" or type(manager.GetNamePlateHitTestInsets) ~= "function"
        or type(manager.SetNamePlateHitTestInsets) ~= "function" then
        return nil
    end
    local getInsets, setInsets = manager.GetNamePlateHitTestInsets, manager.SetNamePlateHitTestInsets
    if category.registered ~= getInsets or category.registeredSet ~= setInsets then
        NamePolicy.RegisterAccessor(category.insetName, function() return InsetText(getInsets(kind)) end,
            function(text)
                local left, right, top, bottom = ParseInsets(text)
                if not left then error("PlateSmith: unreadable insets " .. tostring(text)) end
                setInsets(kind, left, right, top, bottom)
            end, true, GAME_INSETS)
        category.registered, category.registeredSet = getInsets, setInsets
    end
    return category.insetName, THROUGH_INSETS, "insets"
end

local function Category(key)
    for _, category in ipairs(ClickThrough.CATEGORIES) do
        if category.key == key then return category end
    end
end

-- Whether this client can set key's row: friendly players through their names-only switch (the players' own CVar),
-- the others through their switch or insets.
function ClickThrough.Supported(key)
    if key == PLAYERS then return NamePolicy.NamesOnlyIsPlayersOnly() end
    local category = Category(key)
    return category ~= nil and Mechanism(category) ~= nil
end

function ClickThrough.AnySupported()
    if ClickThrough.Supported(PLAYERS) then return true end
    for _, category in ipairs(ClickThrough.CATEGORIES) do
        if Mechanism(category) then return true end
    end
    return false
end

-- How key's row is set on this client: "namesOnly", "switch", "insets", or nil.
function ClickThrough.Kind(key)
    if key == PLAYERS then return ClickThrough.Supported(PLAYERS) and "namesOnly" or nil end
    local category = Category(key)
    return category and select(3, Mechanism(category)) or nil
end

-- Whether Friendly NPCs' Click through also covers friendly players (the client's Friendly category is both).
function ClickThrough.SharedThrough(settings)
    settings = settings or Settings()
    return type(settings) == "table" and settings.clickFriendlyNPC == "through" and ClickThrough.Supported("clickFriendlyNPC")
end

-- What friendly players' rows show: "shared" (Friendly NPCs' Click through covers them), "through" or "clickable".
function ClickThrough.PlayersValue(settings)
    settings = settings or Settings()
    if ClickThrough.SharedThrough(settings) then return "shared" end
    return type(settings) == "table" and settings.clickFriendlyPlayer == "through" and "through" or "clickable"
end

-- Whether name now differs from what PlateSmith wrote, by someone else (no write of ours is queued).
local function ChangedElsewhere(name)
    if applied[name] == nil or NamePolicy.Pending(name) ~= nil then return false, nil end
    local now = NamePolicy.Read(name)
    return now ~= nil and now ~= applied[name], now
end

-- Gives name back: its original, unless someone else changed it after PlateSmith did (their value is the newer
-- choice, so it stays and the record is dropped). In combat (not immediate) the original is queued and its record
-- kept until combat ends (PLAYER_REGEN_ENABLED applies again), as NamePolicy.ApplyNamesOnly does, so a choice made
-- again meanwhile never records PlateSmith's own value as the original. keep: written, but the record stays
-- (logout in combat).
local function Release(name, immediate, keep)
    local record = NamePolicy.CapturedGroup(GROUP)
    local original = record and record[name]
    if applied[name] == nil and original == nil then return end
    if ChangedElsewhere(name) then
        NamePolicy.ForgetCaptured(GROUP, name)
    elseif not immediate and original ~= nil and Secret.InCombat() then
        if NamePolicy.Pending(name) ~= original then NamePolicy.Write(name, original) end
    else
        NamePolicy.RestoreGroup(GROUP, name, immediate, keep)
    end
    applied[name] = nil
end

-- Brings each switch and inset in line with the profile and the place. Cheap and safe at any time (every refresh
-- calls it): one that already holds is not written. Someone else changing one PlateSmith sets makes theirs the
-- original to put back, and PlateSmith's choice is set again (as Hide unstyled names does: STANDARDS section 14).
-- Friendly players' row is NamePolicy.ApplyNamesOnly's.
function ClickThrough.Apply()
    local settings = Settings()
    if not (settings and PS.Profiles and PS.Profiles.State()) then return false end
    local active = settings.enabled ~= false
    local outdoors = not NamePolicy.InGroupInstance()
    for _, category in ipairs(ClickThrough.CATEGORIES) do
        local name, through = Mechanism(category)
        if name then
            if active and settings[category.key] == "through" and (outdoors or not category.friendly) then
                local elsewhere, now = ChangedElsewhere(name)
                if elsewhere then NamePolicy.SetOriginal(GROUP, name, now) end
                local current = NamePolicy.Pending(name) or NamePolicy.Read(name)
                if current ~= through then NamePolicy.WriteCaptured(GROUP, name, through) end
                applied[name] = through
            else
                Release(name)
            end
        end
    end
    return true
end

-- Puts every switch and inset back now (logout). keep: the originals stay recorded, so the next login's Apply puts
-- them back if a blocked write left PlateSmith's value standing.
function ClickThrough.RestoreAll(immediate, keep)
    for _, category in ipairs(ClickThrough.CATEGORIES) do
        local name = Mechanism(category)
        if name then Release(name, immediate, keep) end
    end
end

-- For diagnostics: each row's mechanism ("none" where the client has none), its value now (a switch "1" click
-- through, "0" clickable; insets "left,right,top,bottom"), the setting, and whether PlateSmith sets it.
function ClickThrough.Report()
    local settings = Settings() or {}
    local out = {}
    if ClickThrough.Supported(PLAYERS) then
        out.FriendlyPlayers = { kind = "namesOnly", setting = settings[PLAYERS] or "clickable",
            shared = ClickThrough.SharedThrough(settings) == true }
    else
        out.FriendlyPlayers = "none"
    end
    for _, category in ipairs(ClickThrough.CATEGORIES) do
        local name, _, kind = Mechanism(category)
        if name then
            out[category.api] = { kind = kind, value = NamePolicy.Read(name) or "unreadable",
                setting = settings[category.key] or "game", owned = applied[name] ~= nil }
        else
            -- Not a problem: a client may have neither (Summary flags api-missing).
            out[category.api] = "none"
        end
    end
    return out
end

-- For the suites: a new session.
function ClickThrough._Reset()
    for name in pairs(applied) do applied[name] = nil end
    for _, category in ipairs(ClickThrough.CATEGORIES) do category.registered, category.registeredSet = nil, nil end
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
    PS._RegisterEvent(eventFrame, event, "platesmith.clickthrough")
end
eventFrame:SetScript("OnEvent", function(_, event)
    if not Settings() then return end
    -- Queued writes first, so none lands over what applies now.
    NamePolicy.FlushPending()
    if event == "PLAYER_REGEN_ENABLED" then
        ClickThrough.Apply()
    else
        ClickThrough.RestoreAll(true, Secret.InCombat())
    end
end)
