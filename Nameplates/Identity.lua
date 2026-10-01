-- Readable unit identity, social relationships, classification marks, and plate colour/profile
-- choice.
local _, PS = ...
local L = PS.L
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

-- Elite, rare, rare elite and world boss: Blizzard's nameplate icon (gold dragon, silver dragon,
-- skull), a word, letters for the mark, and the suffix {level.smart} adds. The dragons are client
-- atlases; a client without one shows the word instead. One table for plates, templates and Studio.
local CLASSIFICATION_MARKS = {
    elite = { letters = "+", suffix = "+", word = L["Elite"], atlas = "nameplates-icon-elite-gold",
        colour = { 1, 0.78, 0.25 } },
    rare = { letters = "R", suffix = "R", word = L["Rare"], atlas = "nameplates-icon-elite-silver",
        colour = { 0.78, 0.86, 1 } },
    rareelite = { letters = "R+", suffix = "R+", word = L["Rare elite"], atlas = "nameplates-icon-elite-silver",
        colour = { 1, 0.78, 0.25 } },
    worldboss = { letters = "BOSS", suffix = "B", word = L["Boss"],
        texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", colour = { 1, 0.35, 0.25 } },
}
PS.ClassificationMarks = CLASSIFICATION_MARKS

local function HasAtlas(name)
    if not C_Texture or type(C_Texture.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- Shows kind's mark on text or icon in style; false (both hidden) when kind has none. Studio's
-- preview draws its sample through this too.
function PS.ApplyClassificationMark(text, icon, kind, style)
    local mark = CLASSIFICATION_MARKS[kind]
    if not mark then
        text:Hide()
        icon:Hide()
        return false
    end
    if style == "icon" and (mark.texture or HasAtlas(mark.atlas)) then
        if mark.texture then
            icon:SetTexture(mark.texture)
            icon:SetTexCoord(0, 1, 0, 1)
        else
            icon:SetAtlas(mark.atlas)
        end
        icon:Show()
        text:Hide()
        return true
    end
    text:SetText(style == "letters" and mark.letters or mark.word)
    text:SetTextColor(mark.colour[1], mark.colour[2], mark.colour[3])
    text:Show()
    icon:Hide()
    return true
end

PS._CreatePlateIdentity = function(context)
    local IsReadable = PS.Secret.IsReadable
    local HasValue = PS.Secret.HasValue
    local ReadBoolean = PS.Secret.ReadBoolean
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

    -- True or false, or nil while the client withholds it.
    local function IsPlayerUnit(unit)
        if type(UnitIsPlayer) ~= "function" then return false end
        return ReadBoolean(UnitIsPlayer, unit)
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

    -- The client build cannot change during a session, so it is read once.
    local foreverClient = false
    if type(GetBuildInfo) == "function" then
        local ok, interface = pcall(function() return select(4, GetBuildInfo()) end)
        foreverClient = ok and type(interface) == "number" and interface >= 16000 and interface < 17000
    end
    local function IsForeverClient() return foreverClient end
    -- Most complete display identity first; built once instead of per plate update.
    local displayNameRequests = {
        { GetUnitName, true },
        { UnitPVPName },
        { UnitNameUnmodified },
        { UnitFullName },
        { UnitName },
    }

    -- The most complete name the client gives, possibly protected (only a display sink shows it).
    -- Forever may protect UnitIsPlayer on transient nameplate tokens while the name stays
    -- readable, so only a readable name of a confirmed player is shortened; NPC names stay whole.
    local function UnitDisplayNameValue(unit)
        local db = GetSettings()
        local ordinary = ReadUnitNameValue(UnitName, unit)
        if not IsForeverClient() then return ordinary end
        for _, request in ipairs(displayNameRequests) do
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

    local function FriendlyRelationship(unit)
        if type(UnitIsPlayer) == "function" and ReadBoolean(UnitIsPlayer, unit) ~= true then return nil end

        if ReadBoolean(UnitInParty, unit) == true or ReadBoolean(UnitInRaid, unit) == true then
            return "group"
        end

        if ReadBoolean(UnitIsInMyGuild, unit) == true then return "guild" end

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

    -- relationshipKnown: relationship is FriendlyRelationship(unit), already read by the caller.
    local function SafeColourForUnit(unit, friendly, relationship, relationshipKnown)
        local db = GetSettings()
        if friendly then
            if db and (db.friendlyPvpStyle == "colour" or db.friendlyPvpStyle == "both")
                and IsPlayerUnit(unit) ~= false and FriendlyPvPState(unit) then
                local colour = db.relationshipColours.pvp
                return colour.r, colour.g, colour.b
            end
            if not db or db.friendlyRelationshipColours ~= false then
                if not relationshipKnown then relationship = FriendlyRelationship(unit) end
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
            if PS.NamePolicy.InGroupInstance() and db and db.plateProfiles and db.plateProfiles.enemyDungeon then
                return "enemyDungeon"
            end
            return "enemy"
        end
        local player = IsPlayerUnit(unit)
        if player == false then return "friendlyNPC" end
        return "friendlyPlayer"
    end

    -- Writes a plate text (name, level) unless the region already shows that readable value, as a
    -- reused frame for the same unit, a level or a social update often does. region.plateSmithText
    -- is the readable value last written; the caller is the region's only writer. A protected value
    -- goes to the sink every time and clears the record. Returns whether the region shows value.
    local function SetPlateText(region, value)
        if not IsReadable(value) then
            region.plateSmithText = nil
            return pcall(region.SetText, region, value)
        end
        if value == nil then value = "" end
        if region.plateSmithText == value then return true end
        local ok = pcall(region.SetText, region, value)
        region.plateSmithText = ok and value or nil
        return ok
    end

    return {
        SetPlateText = SetPlateText,
        ReadUnitName = ReadUnitName,
        UnitDisplayNameValue = UnitDisplayNameValue,
        FriendlyRelationship = FriendlyRelationship,
        FriendlyPvPState = FriendlyPvPState,
        SafeColourForUnit = SafeColourForUnit,
        ProfileKeyForUnit = ProfileKeyForUnit,
    }
end
