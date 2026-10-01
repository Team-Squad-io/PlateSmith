local _, PS = ...
local Profiles = assert(PS.Profiles, "PlateSmith Profiles missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local L = PS.L

-- Automatic profile switching: this character's rules (PlateSmithCharacterDB.autoProfile, normalised
-- by Schema) name a profile per content type and per specialization. A switch happens only when the
-- content or specialization changes (or a rule does), only out of combat, never over unsaved changes,
-- and only when the resolved profile is not already active, so a profile chosen by hand stays until
-- the next change.
local AutoProfile = {}
PS.AutoProfile = AutoProfile

AutoProfile.CONTENT = { "world", "dungeon", "raid", "pvp" }
AutoProfile.MAX_SPECS = 4
AutoProfile.PRECEDENCE = { "content", "spec" }

local CONTENT_LABELS = {
    world = L["open world"], dungeon = L["dungeon"], raid = L["raid"], pvp = L["battleground or arena"],
}
AutoProfile.CONTENT_LABELS = CONTENT_LABELS

-- IsInInstance's type: "none" outdoors, "party" (and "scenario") for dungeons, "pvp" and "arena".
local CONTENT_BY_INSTANCE = { none = "world", party = "dungeon", scenario = "dungeon", raid = "raid", pvp = "pvp",
    arena = "pvp" }

local SPEC_KEYS = {}
for index = 1, AutoProfile.MAX_SPECS do SPEC_KEYS[index] = "spec" .. index end
AutoProfile.SPEC_KEYS = SPEC_KEYS

local state = { context = nil, pending = nil, warned = nil, last = nil, busy = false }
AutoProfile._state = state

local function Rules()
    local character = type(PS.GetCharacterSettings) == "function" and PS.GetCharacterSettings() or nil
    return character and character.autoProfile or nil
end
AutoProfile.Rules = Rules

-- The content type here, or nil when the client cannot say (missing API, error, protected value).
function AutoProfile.Content()
    if type(IsInInstance) ~= "function" then return nil end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or not Secret.IsReadable(inInstance) or not Secret.IsReadable(instanceType) then return nil end
    if not inInstance then return "world" end
    return type(instanceType) == "string" and CONTENT_BY_INSTANCE[instanceType] or nil
end

-- A readable whole number from 1 to MAX_SPECS returned by callback, or nil.
local function ReadIndex(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if not ok or not Secret.IsReadable(value) or type(value) ~= "number" then return nil end
    if value < 1 or value > AutoProfile.MAX_SPECS or value % 1 ~= 0 then return nil end
    return value
end

-- "specialization" (GetSpecialization), "talent-groups" (dual spec through GetActiveTalentGroup) or
-- "not-supported". A client with GetSpecialization but no specializations to count uses talent groups.
function AutoProfile.SpecSupport()
    if type(GetSpecialization) == "function" and ReadIndex(GetNumSpecializations) then return "specialization" end
    if type(GetActiveTalentGroup) == "function" then return "talent-groups" end
    return "not-supported"
end

-- How many specializations (or talent groups) a rule can name; 0 without the API. Dual spec always
-- offers two, so a rule for the second can be set before it is learned.
function AutoProfile.SpecCount()
    local support = AutoProfile.SpecSupport()
    if support == "specialization" then return ReadIndex(GetNumSpecializations) or 0 end
    if support == "talent-groups" then return 2 end
    return 0
end

-- The active specialization or talent group index, or nil while the client has not said.
function AutoProfile.Spec()
    local support = AutoProfile.SpecSupport()
    if support == "specialization" then return ReadIndex(GetSpecialization) end
    if support == "talent-groups" then return ReadIndex(GetActiveTalentGroup) end
    return nil
end

function AutoProfile.SpecLabel(index)
    if AutoProfile.SpecSupport() == "specialization" and type(GetSpecializationInfo) == "function" then
        local ok, _, name = pcall(GetSpecializationInfo, index)
        name = ok and Secret.String(name) or nil
        if name then return name end
    end
    if index == 1 then return L["Primary talents"] end
    if index == 2 then return L["Secondary talents"] end
    return string.format(L["Specialization %d"], index)
end

-- An existing profile's name for a rule's stored name (compared as profile names are), or nil.
local function Existing(name)
    if type(name) ~= "string" or not Profiles.Active() then return nil end
    return Profiles.Find(name)
end

-- The profile the rules choose for content and spec, the rule key that chose it and its label; nil
-- when no rule applies. Precedence says which wins when both have a rule ("content" by default).
function AutoProfile.Resolve(content, spec)
    local rules = Rules()
    if not rules then return nil end
    local contentKey = content and CONTENT_LABELS[content] and content or nil
    local specKey = spec and SPEC_KEYS[spec] or nil
    local contentProfile = contentKey and Existing(rules[contentKey]) or nil
    local specProfile = specKey and Existing(rules[specKey]) or nil
    local specFirst = rules.precedence == "spec"
    if specProfile and (specFirst or not contentProfile) then return specProfile, specKey, AutoProfile.SpecLabel(spec) end
    if contentProfile then return contentProfile, contentKey, CONTENT_LABELS[contentKey] end
    return nil
end

local function ClearPending()
    state.pending, state.warned = nil, nil
end

-- Works out the profile for where the character is and switches to it when allowed. force evaluates
-- even though the content and spec are unchanged (a rule changed). Returns a state word: switched,
-- same, none, unchanged, manual, waiting-combat, waiting-unsaved or failed.
function AutoProfile.Evaluate(force)
    if state.busy or not Profiles.Active() then return "unchanged" end
    local content, spec = AutoProfile.Content(), AutoProfile.Spec()
    local context = tostring(content) .. "/" .. tostring(spec)
    local contextChanged = context ~= state.context
    state.context = context
    if not force and not contextChanged then
        if not state.pending then return "unchanged" end
        -- The player chose another profile themselves while this switch waited.
        if Profiles.Active() ~= state.pending.from then
            ClearPending()
            return "manual"
        end
    end
    local target, reason, label = AutoProfile.Resolve(content, spec)
    if not target then
        ClearPending()
        return "none"
    end
    if target == Profiles.Active() then
        ClearPending()
        return "same"
    end
    if not state.pending or state.pending.profile ~= target then state.warned = nil end
    state.pending = { profile = target, reason = reason, label = label, from = Profiles.Active() }
    if Secret.InCombat() then
        state.pending.waiting = "waiting-combat"
        return "waiting-combat"
    end
    if Profiles.IsDirty() then
        state.pending.waiting = "waiting-unsaved"
        if not state.warned then
            state.warned = true
            Chat.Print(string.format(L["%s is set for %s, but this profile has unsaved changes. Save or revert them "
                .. "to switch."], target, label))
        end
        return "waiting-unsaved"
    end
    state.busy = true
    local ok, why = Profiles.Switch(target)
    state.busy = false
    ClearPending()
    if not ok then
        state.last = { profile = target, reason = reason, result = "failed: " .. tostring(why) }
        return "failed"
    end
    state.last = { profile = target, reason = reason, result = "switched" }
    Chat.Print(string.format(L["switched to %s (%s)"], target, label))
    return "switched"
end

-- Sets this character's rule for key (a CONTENT entry or spec1..spec4) to a profile name, or clears it
-- with nil or "" ("Don't switch"), then applies it where the character is now.
function AutoProfile.SetRule(key, name)
    local rules = Rules()
    if not rules or type(key) ~= "string" or not (CONTENT_LABELS[key] or key:match("^spec[1-4]$")) then
        return false, "unknown rule"
    end
    if name == "" then name = nil end
    if name ~= nil and not Existing(name) then return false, "profile does not exist" end
    rules[key] = name and Existing(name) or nil
    AutoProfile.Evaluate(true)
    return true
end

function AutoProfile.SetPrecedence(value)
    local rules = Rules()
    if not rules or (value ~= "content" and value ~= "spec") then return false, "unknown precedence" end
    rules.precedence = value
    AutoProfile.Evaluate(true)
    return true
end

-- Profiles calls these so this character's rules follow a rename or delete. Other characters' rules
-- live in their own saved variables; a rule naming a profile that no longer exists is ignored.
function AutoProfile.ProfileRenamed(old, new)
    local rules = Rules()
    if not rules then return end
    for key, value in pairs(rules) do
        if key ~= "precedence" and value == old then rules[key] = new end
    end
    if state.last and state.last.profile == old then state.last.profile = new end
end

function AutoProfile.ProfileDeleted(name)
    local rules = Rules()
    if not rules then return end
    for key, value in pairs(rules) do
        if key ~= "precedence" and value == name then rules[key] = nil end
    end
    if state.pending and state.pending.profile == name then ClearPending() end
end

-- The diagnostics report's section: the rules, where the character is, and the last switch.
function AutoProfile.Report()
    local rules = Rules() or {}
    local section = { precedence = tostring(rules.precedence or "content"), rules = {} }
    for _, key in ipairs(AutoProfile.CONTENT) do
        section.rules[key] = rules[key] and (Existing(rules[key]) and rules[key] or "missing: " .. rules[key]) or "none"
    end
    for index, key in ipairs(SPEC_KEYS) do
        if rules[key] then section.rules[key] = Existing(rules[key]) and rules[key] or "missing: " .. rules[key]
        elseif index <= AutoProfile.SpecCount() then section.rules[key] = "none" end
    end
    section.specSupport = AutoProfile.SpecSupport()
    section.content = tostring(AutoProfile.Content() or "unknown")
    section.spec = tostring(AutoProfile.Spec() or "unknown")
    section.pending = state.pending and (state.pending.profile .. " (" .. state.pending.reason .. ", "
        .. tostring(state.pending.waiting) .. ")") or "none"
    section.last = state.last and (state.last.profile .. " (" .. state.last.reason .. ", " .. state.last.result .. ")")
        or "none"
    return section
end

-- Save or revert (any profile Notify) may let a waiting switch go ahead.
Profiles.Subscribe(function()
    if state.pending and not state.busy then AutoProfile.Evaluate(false) end
end)

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }) do
    PS._RegisterEvent(frame, event, "platesmith.autoprofile")
end
-- Specialization events differ between clients; one the client does not know is skipped quietly
-- (PS._RegisterEvent would report it as a rejected registration).
local SPEC_EVENTS = { "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }
for _, event in ipairs(SPEC_EVENTS) do
    local known = true
    if C_EventUtils and type(C_EventUtils.IsEventValid) == "function" then
        local ok, valid = pcall(C_EventUtils.IsEventValid, event)
        known = ok and valid == true
    end
    if known and type(frame.RegisterEvent) == "function" then pcall(frame.RegisterEvent, frame, event) end
end
-- Every event only re-reads the content and spec; nothing happens unless one of them changed.
frame:SetScript("OnEvent", function() AutoProfile.Evaluate(false) end)
