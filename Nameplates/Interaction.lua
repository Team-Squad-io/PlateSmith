-- The game's own interact key settings (Studio › Settings › Objects & interacting › Interact key): what the interact
-- key picks (the nearest object, corpse or NPC), how far and in which direction it looks, the plate it shows for it,
-- and its icons. Game's setting writes nothing; any other choice sets the CVar while PlateSmith runs, through
-- NamePolicy's capture and restore (group "interaction"), as Clicking does (Nameplates/ClickThrough.lua). A CVar this
-- client lacks is never offered or written.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local NamePolicy = assert(PS.NamePolicy, "PlateSmith NamePolicy missing")

local Interaction = {}
PS.Interaction = Interaction

local GROUP = "interaction"
Interaction.GROUP = GROUP
local ON_OFF = { on = "1", off = "0" }
-- setting key -> its CVar and what each choice but Game's setting writes (Schema's INTERACT lists the choices), in
-- the order Settings shows them. SoftTargetInteract is a mode: 0 off, 3 always (the value Forever Loot Sparkles
-- writes; 1 and 2 limit it to a gamepad), so On is 3. Range is in yards, though Forever appears to drop the
-- interaction target past about 15 yards whatever it says (Loot Sparkles' own note). Arc: 0 straight ahead, 1 in
-- front, 2 all around. OnlyInRange: 1 picks only what is within reach, 0 also what is out of reach.
Interaction.SWITCHES = {
    { key = "interactTargeting", cvar = "SoftTargetInteract", values = { on = "3", off = "0" } },
    { key = "interactRange", cvar = "SoftTargetInteractRange",
        values = { ["10"] = "10", ["15"] = "15", ["20"] = "20", ["30"] = "30", ["45"] = "45", ["60"] = "60" } },
    { key = "interactArc", cvar = "SoftTargetInteractArc", values = { ahead = "0", front = "1", around = "2" } },
    { key = "interactReach", cvar = "SoftTargetInteractOnlyInRange", values = { within = "1", beyond = "0" } },
    { key = "interactNameplate", cvar = "SoftTargetNameplateInteract", values = ON_OFF },
    { key = "interactIcons", cvar = "SoftTargetIconInteract", values = ON_OFF },
    { key = "interactObjectIcons", cvar = "SoftTargetIconGameObject", values = ON_OFF },
    { key = "interactMinorIcons", cvar = "SoftTargetLowPriorityIcons", values = ON_OFF },
}

-- yielded[cvar]: the setting (any choice but "game") PlateSmith stopped writing because someone else (another addon,
-- the game's options) changed the CVar after PlateSmith did; it follows their value until the setting changes.
local yielded = {}

local function Settings() return type(PS.GetSettings) == "function" and PS.GetSettings() or nil end

local function SwitchFor(key)
    for _, switch in ipairs(Interaction.SWITCHES) do
        if switch.key == key then return switch end
    end
    return nil
end

-- Whether this client has key's CVar: C_CVar.GetCVarInfo knows it (else it reads).
function Interaction.Supported(key)
    local switch = SwitchFor(key)
    if not switch then return false end
    local info = C_CVar and C_CVar.GetCVarInfo
    if type(info) == "function" then
        local ok, value = pcall(info, switch.cvar)
        return ok and value ~= nil
    end
    return NamePolicy.Read(switch.cvar) ~= nil
end

function Interaction.AnySupported()
    for _, switch in ipairs(Interaction.SWITCHES) do
        if Interaction.Supported(switch.key) then return true end
    end
    return false
end

-- Gives cvar back: its original, unless someone else changed it after PlateSmith did (NamePolicy.RestoreGroup
-- leaves their newer value standing). In combat (not immediate) the original is queued and its record kept until
-- PLAYER_REGEN_ENABLED applies again (NamePolicy.Release). keep: written, but the record stays (logout in combat).
local function Release(cvar, immediate, keep)
    yielded[cvar] = nil
    if not NamePolicy.GroupNames(GROUP)[cvar] then return end
    NamePolicy.Release(GROUP, cvar, immediate, keep)
end

-- Brings each switch in line with the profile; cheap and safe at any time (every refresh calls it). A switch that
-- already holds is not written, and one changed elsewhere since PlateSmith wrote it is followed, not fought: that
-- value becomes the original to give back and PlateSmith writes no more until its setting changes.
function Interaction.Apply()
    local settings = Settings()
    if not (settings and PS.Profiles and PS.Profiles.State()) then return false end
    local active = settings.enabled ~= false
    for _, switch in ipairs(Interaction.SWITCHES) do
        if Interaction.Supported(switch.key) then
            local cvar, want = switch.cvar, settings[switch.key]
            local value = active and want ~= nil and switch.values[want] or nil
            if value then
                if NamePolicy.Drifted(GROUP, cvar) ~= nil then
                    -- Theirs is the original now and what stands (Held), so only a later change counts again.
                    NamePolicy.Adopt(GROUP, cvar)
                    NamePolicy.Held(GROUP, cvar)
                    yielded[cvar] = want
                end
                if yielded[cvar] ~= want then
                    yielded[cvar] = nil
                    -- The client may read a number back in another form ("15.000000").
                    local current = NamePolicy.Pending(cvar) or NamePolicy.Read(cvar)
                    if not NamePolicy.SameText(current, value) then NamePolicy.WriteCaptured(GROUP, cvar, value) end
                end
            else
                Release(cvar)
            end
        end
    end
    return true
end

-- Puts every switch back now (logout, PlateSmith turned off). keep: the originals stay recorded, so the next login's
-- Apply puts them back if a blocked write left PlateSmith's value standing.
function Interaction.RestoreAll(immediate, keep)
    for _, switch in ipairs(Interaction.SWITCHES) do
        if Interaction.Supported(switch.key) then Release(switch.cvar, immediate, keep) end
    end
end

-- For diagnostics: each switch's value now ("none" where the client lacks the CVar), the setting, whether
-- PlateSmith holds an original for it, and whether it follows someone else's change.
function Interaction.Report()
    local settings = Settings() or {}
    local out, names = {}, NamePolicy.GroupNames(GROUP)
    for _, switch in ipairs(Interaction.SWITCHES) do
        if Interaction.Supported(switch.key) then
            out[switch.cvar] = { value = NamePolicy.Read(switch.cvar) or "unreadable", setting = settings[switch.key] or "game",
                owned = names[switch.cvar] == true, yielded = yielded[switch.cvar] ~= nil }
        else
            out[switch.cvar] = "none"
        end
    end
    return out
end

-- For the suites: a new session.
function Interaction._Reset()
    for cvar in pairs(yielded) do yielded[cvar] = nil end
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
    PS._RegisterEvent(eventFrame, event, "platesmith.interaction")
end
eventFrame:SetScript("OnEvent", function(_, event)
    if not Settings() then return end
    -- Queued writes first, so none lands over what applies now.
    NamePolicy.FlushPending()
    if event == "PLAYER_REGEN_ENABLED" then
        Interaction.Apply()
    else
        Interaction.RestoreAll(true, Secret.InCombat())
    end
end)
