local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")

-- Which Midnight addon restrictions (combat, encounter, keystone, PvP match,
-- restricted map, chat) apply right now. Clients without the API report
-- "api-missing" rather than guessing.
local Restrictions = {}
PS.Restrictions = Restrictions

-- Report key and Enum.AddOnRestrictionType field; Chat was added in 12.0.5.
local TYPES = {
    { "combat", "Combat" }, { "encounter", "Encounter" }, { "challengeMode", "ChallengeMode" },
    { "pvpMatch", "PvPMatch" }, { "map", "Map" }, { "chat", "Chat" },
}

-- { combat = "clear", encounter = "restricted", ... }; types this client lacks are left out.
function Restrictions.Report()
    local api = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
    local enum = Enum and Enum.AddOnRestrictionType
    if type(api) ~= "function" or type(enum) ~= "table" then return { state = "api-missing" } end
    local report = {}
    for _, entry in ipairs(TYPES) do
        local value = enum[entry[2]]
        if value ~= nil then
            local ok, active = pcall(api, value)
            if not ok then
                report[entry[1]] = "error"
            elseif not Secret.IsReadable(active) then
                report[entry[1]] = "protected"
            else
                report[entry[1]] = active and "restricted" or "clear"
            end
        end
    end
    return report
end

-- For /ps status: "none", the active restriction keys joined by "+", or the probe state.
function Restrictions.Summary()
    local report = Restrictions.Report()
    if report.state then return report.state end
    local active = {}
    for _, entry in ipairs(TYPES) do
        if report[entry[1]] == "restricted" then active[#active + 1] = entry[1] end
    end
    return #active > 0 and table.concat(active, "+") or "none"
end
