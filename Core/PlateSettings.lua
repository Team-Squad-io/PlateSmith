-- Saved profile and layout mutation; rendering refreshes stay with the nameplate owner.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

PS._CreatePlateSettings = function(context)
    local GetSettings = context.GetSettings
    local SetSettings = context.SetSettings
    local RefreshAll = context.RefreshAll
    local ApplyFriendlyNamePolicy = context.ApplyFriendlyNamePolicy
    local RestoreFriendlyNameCVars = context.RestoreFriendlyNameCVars
    local RestoreRestrictedFriendlyNameCVar = context.RestoreRestrictedFriendlyNameCVar
    local ApplyRestrictedFriendlyClassColour = context.ApplyRestrictedFriendlyClassColour
    local defaults = S.defaults
    local profileDefaults = S.profileDefaults
    local defaultRelationshipColours = S.defaultRelationshipColours
    local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT
    local valueSources = S.valueSources
    local valueAnchors = S.valueAnchors
    local valueLayers = S.valueLayers
    local missingAnchorModes = S.missingAnchorModes
    local NormalizeSettings = S.NormalizeSettings
    local NormalizeProfile = S.NormalizeProfile
    local NormalizeLayout = S.NormalizeLayout
    local NormalizeColour = S.NormalizeColour
    local CopyEnemyProfile = S.CopyEnemyProfile

    local function SetOption(key, value)
        local db = GetSettings()
        if defaults[key] == nil or key == "schemaVersion" then return false end
        db[key] = value
        if key == "scale" or key == "width" or key == "healthHeight" or key == "nameFontSize" then
            db.plateProfiles.enemy[key] = value
        end
        NormalizeSettings(db)
        if key == "hideUnstyledFriendlyNames" or key == "restrictedFriendlyNamesOnly"
            or key == "restrictedFriendlyClassColour" then ApplyFriendlyNamePolicy() end
        RefreshAll()
        return true
    end

    local function GetProfileSettings(profileKey)
        local db = GetSettings()
        if not db or not db.plateProfiles then return nil end
        if profileKey == "enemyDungeon" then
            return db.plateProfiles.enemyDungeon or db.plateProfiles.enemy
        end
        profileKey = profileDefaults[profileKey] and profileKey or "enemy"
        return db.plateProfiles[profileKey]
    end

    local function EnsureProfileSettings(profileKey)
        local db = GetSettings()
        if profileKey == "enemyDungeon" then
            if not db.plateProfiles.enemyDungeon then
                db.plateProfiles.enemyDungeon = CopyEnemyProfile(db.plateProfiles.enemy)
            end
            return db.plateProfiles.enemyDungeon
        end
        return GetProfileSettings(profileKey)
    end

    local function SetDungeonEnemyProfile(profile)
        local db = GetSettings()
        if not db then return false end
        if profile == nil then
            db.plateProfiles.enemyDungeon = nil
        elseif type(profile) == "table" then
            db.plateProfiles.enemyDungeon = CopyEnemyProfile(NormalizeProfile(profile, db.plateProfiles.enemy))
        else
            return false
        end
        RefreshAll()
        return true
    end


    local function LayoutField(profileKey, variant)
        if variant == "dungeon" and (profileKey == "friendlyPlayer" or profileKey == "friendlyNPC") then
            return "dungeonNamesLayout"
        end
        return variant == "names" and profileKey ~= "enemy" and profileKey ~= "enemyDungeon"
            and "namesLayout" or "layout"
    end

    local function GetDefaultLayout(profileKey, variant)
        local db = GetSettings()
        if profileKey == "enemyDungeon" then
            return NormalizeLayout(db and db.plateProfiles.enemy.layout, profileDefaults.enemy.layout)
        end
        profileKey = profileDefaults[profileKey] and profileKey or "enemy"
        local field = LayoutField(profileKey, variant)
        return NormalizeLayout(nil, profileDefaults[profileKey][field])
    end

    local function GetLayout(profileKey, variant)
        local db = GetSettings()
        profileKey = profileKey == "enemyDungeon" and profileKey
            or (profileDefaults[profileKey] and profileKey or "enemy")
        local profile = GetProfileSettings(profileKey)
        local field = LayoutField(profileKey, variant)
        local fallback = profileKey == "enemyDungeon" and db.plateProfiles.enemy
            or profileDefaults[profileKey]
        return NormalizeLayout(profile and profile[field], fallback[field])
    end

    local function SetLayout(layout, profileKey, variant)
        local db = GetSettings()
        if not db then return false end
        profileKey = profileKey == "enemyDungeon" and profileKey
            or (profileDefaults[profileKey] and profileKey or "enemy")
        local field = LayoutField(profileKey, variant)
        local profile = EnsureProfileSettings(profileKey)
        local fallback = profileKey == "enemyDungeon" and db.plateProfiles.enemy
            or profileDefaults[profileKey]
        profile[field] = NormalizeLayout(layout, fallback[field])
        if profileKey == "enemy" then db.layout = db.plateProfiles.enemy.layout end
        RefreshAll()
        return true
    end

    local function SetComponentPosition(key, x, y, profileKey, variant)
        local db = GetSettings()
        if not db or type(key) ~= "string" or not key:match("^[%a][%w_%.]*$") then return false end
        x, y = tonumber(x), tonumber(y)
        if not x or not y then return false end
        local layout = GetLayout(profileKey, variant)
        local current = layout[key]
        layout[key] = { x = x, y = y, visible = not current or current.visible ~= false,
            scale = current and current.scale or 1, followName = current and current.followName }
        return SetLayout(layout, profileKey, variant)
    end

    local function SetComponentScale(key, scale, profileKey, variant)
        local db = GetSettings()
        if not db or type(key) ~= "string" or not key:match("^[%a][%w_%.]*$") then return false end
        scale = tonumber(scale)
        if not scale or scale ~= scale or scale < 0.5 or scale > 2 then return false end
        local layout = GetLayout(profileKey, variant)
        if not layout[key] then return false end
        layout[key].scale = scale
        return SetLayout(layout, profileKey, variant)
    end

    local function SetLevelFollowName(enabled, profileKey, variant)
        local db = GetSettings()
        if not db or type(enabled) ~= "boolean" then return false end
        local layout = GetLayout(profileKey, variant)
        if not layout.level then return false end
        layout.level.followName = enabled
        return SetLayout(layout, profileKey, variant)
    end

    local function SetComponentVisibility(key, visible, profileKey, variant)
        local db = GetSettings()
        if not db or type(key) ~= "string" or not key:match("^[%a][%w_%.]*$") or type(visible) ~= "boolean" then
            return false
        end
        local layout = GetLayout(profileKey, variant)
        if not layout[key] then return false end
        layout[key].visible = visible
        return SetLayout(layout, profileKey, variant)
    end

    local function SetProfileOption(profileKey, key, value)
        local db = GetSettings()
        if (key ~= "scale" and key ~= "width" and key ~= "healthHeight" and key ~= "powerHeight" and key ~= "nameFontSize"
            and key ~= "healthTexture" and key ~= "healthColourMode") then
            return false
        end
        local profile = EnsureProfileSettings(profileKey)
        if not profile then return false end
        profile[key] = value
        NormalizeProfile(profile, profileKey == "enemyDungeon" and db.plateProfiles.enemy or profileDefaults[profileKey])
        if profileKey == "enemy" and (key == "scale" or key == "width" or key == "healthHeight" or key == "nameFontSize") then
            db[key] = profile[key]
            db.layout = profile.layout
        end
        RefreshAll()
        return true
    end

    local function SetProfileValueSlot(profileKey, key, field, value)
        local db = GetSettings()
        local profile = GetProfileSettings(profileKey)
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if not slot then return false end
        if field == "source" then
            if not valueSources[value] then return false end
        elseif field == "anchor" then
            if not valueAnchors[value] then return false end
        elseif field == "layer" then
            if not valueLayers[value] then return false end
        elseif field == "whenMissing" then
            if not missingAnchorModes[value] then return false end
        elseif field == "fontSize" then
            value = tonumber(value)
            if not value or value < 7 or value > 18 then return false end
        elseif field == "colour" then
            if type(value) ~= "table" then return false end
            value = NormalizeColour(value, { r = 1, g = 1, b = 1 })
        else
            return false
        end
        profile = EnsureProfileSettings(profileKey)
        slot = profile.valueSlots[key]
        slot[field] = value
        NormalizeProfile(profile, profileKey == "enemyDungeon" and db.plateProfiles.enemy or profileDefaults[profileKey])
        RefreshAll()
        return true
    end

    local function SetProfileValueSlots(profileKey, slots)
        if not GetProfileSettings(profileKey) or type(slots) ~= "table" then return false end
        local candidate = {}
        for index = 1, VALUE_SLOT_COUNT do
            local key = "value" .. index
            local slot = slots[key]
            if type(slot) ~= "table" or not valueSources[slot.source]
                or not valueAnchors[slot.anchor] or (slot.layer ~= nil and not valueLayers[slot.layer])
                or (slot.whenMissing ~= nil and not missingAnchorModes[slot.whenMissing])
                or type(slot.fontSize) ~= "number"
                or slot.fontSize < 7 or slot.fontSize > 18 or type(slot.colour) ~= "table" then return false end
            candidate[key] = { source = slot.source, anchor = slot.anchor,
                layer = slot.layer or "front", whenMissing = slot.whenMissing or "fallback", fontSize = slot.fontSize,
                colour = NormalizeColour(slot.colour, { r = 1, g = 1, b = 1 }) }
        end
        EnsureProfileSettings(profileKey).valueSlots = candidate
        RefreshAll()
        return true
    end

    local function SetProfileHealthColour(profileKey, r, g, b)
        local db = GetSettings()
        if not GetProfileSettings(profileKey) then return false end
        local profile = EnsureProfileSettings(profileKey)
        if not profile then return false end
        profile.healthColour = NormalizeColour({ r = r, g = g, b = b },
            profileKey == "enemyDungeon" and db.plateProfiles.enemy.healthColour
                or profileDefaults[profileKey].healthColour)
        profile.healthColourMode = "custom"
        RefreshAll()
        return true
    end

    local function SetRelationshipColour(relationship, r, g, b)
        local db = GetSettings()
        local fallback = defaultRelationshipColours[relationship]
        if not db or not fallback then return false end
        db.relationshipColours[relationship] = NormalizeColour({ r = r, g = g, b = b }, fallback)
        RefreshAll()
        return true
    end

    local function ResetSettings()
        RestoreFriendlyNameCVars(true)
        RestoreRestrictedFriendlyNameCVar(true)
        ApplyRestrictedFriendlyClassColour(false)
        local settings = type(PlateSmithDB) == "table" and PlateSmithDB or {}
        for key in pairs(settings) do settings[key] = nil end
        PlateSmithDB = NormalizeSettings(settings)
        local db = PlateSmithDB
        SetSettings(db)
        ApplyFriendlyNamePolicy()
        RefreshAll()
        return db
    end

    return {
        SetOption = SetOption,
        GetLayout = GetLayout,
        SetLayout = SetLayout,
        SetComponentPosition = SetComponentPosition,
        SetComponentScale = SetComponentScale,
        SetLevelFollowName = SetLevelFollowName,
        SetComponentVisibility = SetComponentVisibility,
        GetPlateProfileSettings = GetProfileSettings,
        GetDungeonEnemyOverride = function()
            local db = GetSettings()
            return db and db.plateProfiles and db.plateProfiles.enemyDungeon or nil
        end,
        SetDungeonEnemyProfile = SetDungeonEnemyProfile,
        GetDefaultLayout = GetDefaultLayout,
        SetPlateProfileOption = SetProfileOption,
        SetPlateValueSlot = SetProfileValueSlot,
        SetPlateValueSlots = SetProfileValueSlots,
        SetPlateProfileHealthColour = SetProfileHealthColour,
        SetRelationshipColour = SetRelationshipColour,
        ResetSettings = ResetSettings,
    }
end
