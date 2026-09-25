-- Readable unit identity, social relationships, and plate colour/profile choice.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

PS._CreatePlateIdentity = function(context)
    local IsReadable = context.IsReadable
    local HasValue = context.HasValue
    local GetSettings = context.GetSettings
    local defaultRelationshipColours = S.defaultRelationshipColours

    local function ReadUnitPlayerName(unit)
        local callback = type(UnitNameUnmodified) == "function" and UnitNameUnmodified
            or (type(UnitFullName) == "function" and UnitFullName or UnitName)
        if type(callback) ~= "function" then return nil, nil end
        local ok, name, realm = pcall(callback, unit)
        if not ok or not IsReadable(name) or type(name) ~= "string" or name == "" then return nil, nil end
        if IsReadable(realm) and type(realm) == "string" and realm ~= "" then
            return name, name .. "-" .. realm
        end
        return name, name
    end

    local function IsPlayerUnit(unit)
        if type(UnitIsPlayer) ~= "function" then return false end
        local ok, player = pcall(UnitIsPlayer, unit)
        if not ok or not IsReadable(player) then return nil end
        return player and true or false
    end

    local function ReadUnitName(callback, unit, ...)
        if type(callback) ~= "function" then return nil end
        local ok, name = pcall(callback, unit, ...)
        if not ok or not IsReadable(name) or type(name) ~= "string" or name == "" then return nil end
        return name
    end

    local function ReadUnitNameValue(callback, unit, ...)
        if type(callback) ~= "function" then return nil end
        local ok, name = pcall(callback, unit, ...)
        if not ok or not HasValue(name) then return nil end
        if IsReadable(name) and (type(name) ~= "string" or name == "") then return nil end
        return name
    end

    local function IsForeverClient()
        if type(GetBuildInfo) ~= "function" then return false end
        local ok, interface = pcall(function() return select(4, GetBuildInfo()) end)
        return ok and type(interface) == "number" and interface >= 16000 and interface < 17000
    end

    local function PlayerDisplayName(unit)
        local db = GetSettings()
        local ordinary = ReadUnitName(UnitName, unit) or ""
        if not IsForeverClient() then return ordinary end

        local identity = ReadUnitName(GetUnitName, unit, true)
            or ReadUnitName(UnitPVPName, unit)
            or ReadUnitName(UnitNameUnmodified, unit)
            or ReadUnitName(UnitFullName, unit)
            or ordinary
        if identity == "" then return ordinary end

        -- Forever may protect UnitIsPlayer on transient nameplate tokens even when
        -- the complete display identity remains readable. Showing the unmodified
        -- name does not require classifying the unit first, and also preserves
        -- multi-word NPC names. Only shorten identities we can confirm are players.
        if db and db.showPlayerSurnames == false and IsPlayerUnit(unit) then
            return identity:match("^(%S+)") or identity
        end
        return identity
    end

    local function UnitDisplayNameValue(unit)
        local db = GetSettings()
        local ordinary = ReadUnitNameValue(UnitName, unit)
        if not IsForeverClient() then return ordinary end
        for _, request in ipairs({
            { GetUnitName, true },
            { UnitPVPName },
            { UnitNameUnmodified },
            { UnitFullName },
            { UnitName },
        }) do
            local value = ReadUnitNameValue(request[1], unit, request[2])
            if HasValue(value) then
                if db and db.showPlayerSurnames == false and IsReadable(value)
                    and type(value) == "string" and IsPlayerUnit(unit) == true then
                    return value:match("^(%S+)") or value
                end
                return value
            end
        end
        return ordinary
    end

    local function IsRecognizedPlayerName(name, fullName, includeFlags)
        local callback = C_AutoComplete and C_AutoComplete.IsRecognizedName
        if type(callback) ~= "function" or type(includeFlags) ~= "number" then return false end
        local ok, recognized = pcall(callback, fullName or name, includeFlags, 0)
        if ok and IsReadable(recognized) and recognized then return true end
        if fullName ~= name then
            ok, recognized = pcall(callback, name, includeFlags, 0)
            if ok and IsReadable(recognized) and recognized then return true end
        end
        return false
    end

    local function ReadAutoCompleteFlag(key, fallback)
        local flags = Enum and Enum.AutoCompleteEntryFlag
        local value = flags and flags[key]
        return type(value) == "number" and value or fallback
    end

    local function UnitMatchesRelationship(callback, unit)
        if type(callback) ~= "function" then return false end
        local ok, matched = pcall(callback, unit)
        return ok and IsReadable(matched) and matched and true or false
    end

    local function FriendlyRelationship(unit)
        if type(UnitIsPlayer) == "function" then
            local ok, isPlayer = pcall(UnitIsPlayer, unit)
            if not ok or not IsReadable(isPlayer) or not isPlayer then return nil end
        end

        if UnitMatchesRelationship(UnitInParty, unit) or UnitMatchesRelationship(UnitInRaid, unit) then
            return "group"
        end

        if UnitMatchesRelationship(UnitIsInMyGuild, unit) then return "guild" end

        local name, fullName = ReadUnitPlayerName(unit)
        if not name then return nil end
        local groupFlag = ReadAutoCompleteFlag("InGroup", 1)
        if IsRecognizedPlayerName(name, fullName, groupFlag) then return "group" end

        if type(UnitGUID) == "function" and C_FriendList and type(C_FriendList.IsFriend) == "function" then
            local guidOK, guid = pcall(UnitGUID, unit)
            if guidOK and IsReadable(guid) and type(guid) == "string" then
                local friendOK, isFriend = pcall(C_FriendList.IsFriend, guid)
                if friendOK and IsReadable(isFriend) and isFriend then return "friend" end
            end
        end

        local friendFlags = ReadAutoCompleteFlag("Friend", 4) + ReadAutoCompleteFlag("Bnet", 8)
        if IsRecognizedPlayerName(name, fullName, friendFlags) then return "friend" end
        if IsRecognizedPlayerName(name, fullName, ReadAutoCompleteFlag("RecentPlayer", 256)) then return "recent" end
        return nil
    end

    local function FriendlyPvPState(unit)
        if type(UnitIsPVPFreeForAll) == "function" then
            local ok, freeForAll = pcall(UnitIsPVPFreeForAll, unit)
            if not ok or not IsReadable(freeForAll) then return nil end
            if freeForAll then return "FFA" end
        end
        if type(UnitIsPVP) ~= "function" then return nil end
        local ok, flagged = pcall(UnitIsPVP, unit)
        if not ok or not IsReadable(flagged) then return nil end
        if not flagged then return false end
        if type(UnitFactionGroup) == "function" then
            local factionOK, faction = pcall(UnitFactionGroup, unit)
            if factionOK and IsReadable(faction) and (faction == "Alliance" or faction == "Horde") then
                return faction
            end
        end
        return "flagged"
    end

    local function SafeColourForUnit(unit, friendly)
        local db = GetSettings()
        if friendly then
            if db and (db.friendlyPvpStyle == "colour" or db.friendlyPvpStyle == "both")
                and IsPlayerUnit(unit) ~= false and FriendlyPvPState(unit) then
                local colour = db.relationshipColours.pvp
                return colour.r, colour.g, colour.b
            end
            if not db or db.friendlyRelationshipColours ~= false then
                local relationship = FriendlyRelationship(unit)
                local colour = db and db.relationshipColours and db.relationshipColours[relationship]
                    or defaultRelationshipColours[relationship]
                if colour then return colour.r, colour.g, colour.b end
            end
            local _, class = UnitClass(unit)
            if IsReadable(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
                local colour = RAID_CLASS_COLORS[class]
                return colour.r, colour.g, colour.b
            end
            return 0.35, 0.75, 1
        end

        local reaction = UnitReaction(unit, "player")
        if IsReadable(reaction) and type(reaction) == "number" and reaction == 4 then
            return 1, 0.82, 0
        end
        return 0.9, 0.16, 0.16
    end

    local function ProfileKeyForUnit(unit, friendly)
        local db = GetSettings()
        if not friendly then
            local inInstance, instanceType = IsInInstance()
            if inInstance and (instanceType == "party" or instanceType == "raid")
                and db and db.plateProfiles and db.plateProfiles.enemyDungeon then
                return "enemyDungeon"
            end
            return "enemy"
        end
        local player = IsPlayerUnit(unit)
        if player == false then return "friendlyNPC" end
        return "friendlyPlayer"
    end

    return {
        ReadUnitName = ReadUnitName,
        PlayerDisplayName = PlayerDisplayName,
        UnitDisplayNameValue = UnitDisplayNameValue,
        FriendlyRelationship = FriendlyRelationship,
        FriendlyPvPState = FriendlyPvPState,
        SafeColourForUnit = SafeColourForUnit,
        ProfileKeyForUnit = ProfileKeyForUnit,
    }
end
