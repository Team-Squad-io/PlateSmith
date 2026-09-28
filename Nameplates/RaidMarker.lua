local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

-- Raid target icons on plates. Forever can protect the marker index on a
-- nameplate token, so this tries Blizzard's texture sink first, then another
-- token that refers to the same unit (target, focus, a group member's target).
local RaidMarker = {}
PS.RaidMarker = RaidMarker

local candidates

function RaidMarker.ReadIndex(unit)
    if type(GetRaidTargetIndex) ~= "function" then return nil, "api-missing" end
    local ok, index = pcall(GetRaidTargetIndex, unit)
    if not ok then return nil, "error" end
    if not IsReadable(index) then return nil, "secret" end
    if index == nil or index == 0 then return nil, "none" end
    if type(index) ~= "number" or index < 1 or index > 8 then return nil, "invalid-" .. type(index) end
    return index, "readable"
end

function RaidMarker.PlateRoot(unit)
    local callback = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(callback) ~= "function" then return nil, "api-missing" end
    local ok, root = pcall(callback, unit)
    if not ok then return nil, "error" end
    if not IsReadable(root) then return nil, "secret" end
    return root, root and "readable" or "none"
end

-- The candidate list depends only on group size, so it is rebuilt on roster changes.
function RaidMarker.InvalidateCandidates()
    candidates = nil
end

-- Whether a UNIT_TARGET for unit changes a candidate token (a group member's target).
function RaidMarker.IsCandidateSource(unit)
    return type(unit) == "string" and (unit:find("^party%d") ~= nil or unit:find("^raid%d") ~= nil)
end

local function Candidates()
    if candidates then return candidates end
    local list = { "target", "focus", "mouseover" }
    for number = 1, 5 do list[#list + 1] = "boss" .. number end
    local groupCount = 0
    if type(GetNumGroupMembers) == "function" then
        local ok, count = pcall(GetNumGroupMembers)
        groupCount = ok and Secret.Number(count) and math.min(40, count) or 0
    end
    local prefix = Secret.ReadBoolean(IsInRaid) == true and "raid" or "party"
    local maximum = prefix == "raid" and groupCount or math.min(4, groupCount)
    for number = 1, maximum do list[#list + 1] = prefix .. number .. "target" end
    candidates = list
    return list
end

-- Returns index, sourceUnit, route ("direct", "root", "identity", or the failure state).
function RaidMarker.Resolve(data)
    local index, state = RaidMarker.ReadIndex(data.unit)
    if index then return index, data.unit, "direct" end
    -- A readable "no marker" is authoritative; only a withheld read needs
    -- another token that refers to the same unit.
    if state ~= "secret" and state ~= "error" then return nil, data.unit, state end
    local list = Candidates()
    for position = 1, #list do
        local candidate = list[position]
        local candidateRoot = RaidMarker.PlateRoot(candidate)
        local matched = (candidateRoot and candidateRoot == data.root) or Secret.SameUnit(data.unit, candidate)
        if matched then
            index = RaidMarker.ReadIndex(candidate)
            if index then return index, candidate, candidateRoot == data.root and "root" or "identity" end
        end
    end
    return nil, data.unit, state
end

-- Midnight/Forever can protect the numeric marker while still permitting it to
-- flow directly into Blizzard's texture sink. Do not compare it, calculate with
-- it, or use it as a table key on this path.
local function RenderProtected(data)
    if type(GetRaidTargetIndex) ~= "function" or type(SetRaidTargetIconTexture) ~= "function" then
        return false, "sink-unavailable"
    end
    local ok, index = pcall(GetRaidTargetIndex, data.unit)
    if not ok then return false, "sink-error" end
    if not Secret.HasValue(index) then return false, "none" end
    -- A readable index is checked; a protected one goes straight to the sink.
    if IsReadable(index) and (type(index) ~= "number" or index < 1 or index > 8) then return false, "none" end
    if not pcall(SetRaidTargetIconTexture, data.raidIcon, index) then return false, "sink-error" end
    return true, "direct-sink"
end

-- Shows the plate's marker. Plates that needed another token keep raidIconNeedsFallback set,
-- so a change to one of those tokens checks them again.
-- Whether a plate that needs a stand-in must resolve again now that token (a group member's
-- target) changed: its marker came from that token, or the token now names the plate's unit. Any
-- other token is as it was, so the result would be too.
function RaidMarker.TokenChanged(data, token)
    if data.raidIconUnit == token then return true end
    local root = RaidMarker.PlateRoot(token)
    return (root and root == data.root) or Secret.SameUnit(data.unit, token)
end

function RaidMarker.Update(data)
    data.raidIconNeedsFallback, data.raidIconUnit = false, nil
    if not data.own or data.layout.raidIcon.visible == false then
        data.raidIconSource = "disabled"
        data.raidIcon:Hide()
        return
    end
    local protectedShown, protectedSource = RenderProtected(data)
    if protectedShown then
        data.raidIconSource = protectedSource
        data.raidIcon:Show()
        return
    end
    local index, source, route = RaidMarker.Resolve(data)
    -- Plates resolved through another token must re-check when that token changes.
    data.raidIconNeedsFallback = route == "root" or route == "identity" or route == "secret" or route == "error"
    if route == "root" or route == "identity" then data.raidIconUnit = source else data.raidIconUnit = nil end
    if not index then
        data.raidIconSource = protectedSource
        data.raidIcon:Hide()
        return
    end
    if type(SetRaidTargetIconTexture) == "function" then
        SetRaidTargetIconTexture(data.raidIcon, index)
    else
        local column = (index - 1) % 4
        local row = math.floor((index - 1) / 4)
        data.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        data.raidIcon:SetTexCoord(column / 4, (column + 1) / 4, row / 2, (row + 1) / 2)
    end
    data.raidIconSource = "readable-fallback"
    data.raidIcon:Show()
end
