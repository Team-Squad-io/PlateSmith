local _, PS = ...

local defaults = {
    schemaVersion = 19,
    enabled = true,
    mode = "auto",       -- auto, own, overlay
    friendly = "names",  -- names, full, off
    hideUnstyledFriendlyNames = true,
    friendlyRelationshipColours = true,
    friendlyPvpStyle = "icon", -- off, colour, icon, both
    restrictedFriendlyNamesOnly = true,
    restrictedFriendlyClassColour = false,
    experimentalDungeonFriendlyText = false,
    showPlayerSurnames = true,
    showGroupIcon = true,
    showGuildIcon = true,
    showClassification = true,
    quest = true,
    threat = true,
    showTagged = true,
    showBuffs = true,
    showDebuffs = true,
    buffSource = "all",       -- all, mine
    debuffSource = "mine",   -- all, mine
    nativeNameFont = true,
    editorTheme = "auto", -- auto, classic, modern
    scale = 1,
    width = 112,
    healthHeight = 10,
    nameFontSize = 12,
    threatConsoleShown = false,
    threatConsoleX = 260,
    threatConsoleY = 0,
    threatSpotlightStyle = "both", -- box, sides, both
    targetHighlightStyle = "border", -- off, border, halo
    threatSpotlightOthersAlpha = 0.55,
    threatSpotlightDuration = 3,
}

local defaultLayout = {
    name = { x = 0, y = 16, visible = true },
    health = { x = 0, y = 0, visible = true },
    cast = { x = 0, y = -13, visible = true },
    threat = { x = 0, y = -25, visible = true },
    tagged = { x = 62, y = -25, visible = true },
    quest = { x = -70, y = 16, visible = true },
    raidIcon = { x = 70, y = 16, visible = true },
    relationshipIcon = { x = 0, y = 38, visible = false },
    pvpIcon = { x = 94, y = 8, visible = false },
    classification = { x = -94, y = 0, visible = true },
    level = { x = -70, y = 0, visible = true },
    guild = { x = 0, y = -40, visible = false },
    buffs = { x = 0, y = 38, visible = true },
    debuffs = { x = 0, y = -43, visible = true },
    power = { x = 0, y = -14, visible = false },
}

local VALUE_SLOT_COUNT = 8
local valueSources = {
    off = true, healthPercent = true, healthCurrent = true, healthValue = true,
    powerPercent = true, powerCurrent = true, powerValue = true,
    threatPercent = true, leadPercent = true, rawThreat = true, differential = true,
}
local valueAnchors = { canvas = true, health = true, power = true, cast = true }
local valueLayers = { back = true, front = true }
local missingAnchorModes = { fallback = true, hide = true }
for index = 1, VALUE_SLOT_COUNT do
    defaultLayout["value" .. index] = { x = 0, y = 0, visible = true }
end

local function DefaultValueSlots()
    local slots = {}
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        slots[key] = { source = "off", anchor = "health", layer = "front", whenMissing = "fallback", fontSize = 9,
            colour = { r = 1, g = 1, b = 1 } }
    end
    return slots
end

local profileOrder = { "enemy", "friendlyPlayer", "friendlyNPC" }
local profileDefaults = {
    enemy = {
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 12,
        healthTexture = "blizzard", healthColourMode = "automatic",
        healthColour = { r = 0.85, g = 0.12, b = 0.1 },
        layout = defaultLayout,
    },
    friendlyPlayer = {
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 12,
        healthTexture = "blizzard", healthColourMode = "automatic",
        healthColour = { r = 0.25, g = 1, b = 0.45 },
        layout = {
            name = { x = 0, y = 8, visible = true },
            health = { x = 0, y = -8, visible = true },
            cast = { x = 0, y = -21, visible = true },
            threat = { x = 0, y = -33, visible = false },
            tagged = { x = 62, y = -33, visible = false },
            quest = { x = -70, y = 8, visible = false },
            raidIcon = { x = 70, y = 8, visible = true },
            relationshipIcon = { x = 0, y = 34, visible = true },
            pvpIcon = { x = 94, y = 8, visible = true },
            classification = { x = -94, y = -8, visible = false },
            level = { x = -70, y = -8, visible = true },
            guild = { x = 0, y = -36, visible = true },
            buffs = { x = 0, y = 54, visible = true },
            debuffs = { x = 0, y = -52, visible = true },
        },
        namesLayout = {
            name = { x = 0, y = 8, visible = true },
            health = { x = 0, y = -8, visible = false },
            cast = { x = 0, y = -21, visible = false },
            threat = { x = 0, y = -33, visible = false },
            tagged = { x = 62, y = -33, visible = false },
            quest = { x = -70, y = 8, visible = false },
            raidIcon = { x = 85, y = 8, visible = true },
            relationshipIcon = { x = 0, y = 34, visible = true },
            pvpIcon = { x = 106, y = 8, visible = true },
            classification = { x = -106, y = 8, visible = false },
            level = { x = -85, y = 8, visible = true },
            guild = { x = 0, y = -13, visible = true },
            buffs = { x = 0, y = 52, visible = true },
            debuffs = { x = 0, y = -30, visible = true },
        },
    },
    friendlyNPC = {
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 12,
        healthTexture = "blizzard", healthColourMode = "automatic",
        healthColour = { r = 0.35, g = 0.9, b = 1 },
        layout = {
            name = { x = 0, y = 8, visible = true },
            health = { x = 0, y = -8, visible = true },
            cast = { x = 0, y = -21, visible = true },
            threat = { x = 0, y = -33, visible = false },
            tagged = { x = 62, y = -33, visible = false },
            quest = { x = -70, y = 8, visible = true },
            raidIcon = { x = 70, y = 8, visible = true },
            relationshipIcon = { x = 0, y = 34, visible = false },
            pvpIcon = { x = 94, y = 8, visible = false },
            classification = { x = -94, y = -8, visible = false },
            level = { x = -70, y = -8, visible = true },
            guild = { x = 0, y = -36, visible = false },
            buffs = { x = 0, y = 54, visible = true },
            debuffs = { x = 0, y = -52, visible = true },
        },
        namesLayout = {
            name = { x = 0, y = 8, visible = true },
            health = { x = 0, y = -8, visible = false },
            cast = { x = 0, y = -21, visible = false },
            threat = { x = 0, y = -33, visible = false },
            tagged = { x = 62, y = -33, visible = false },
            quest = { x = -70, y = 8, visible = true },
            raidIcon = { x = 85, y = 8, visible = true },
            relationshipIcon = { x = 0, y = 34, visible = false },
            pvpIcon = { x = 106, y = 8, visible = false },
            classification = { x = -106, y = 8, visible = false },
            level = { x = -85, y = 8, visible = true },
            guild = { x = 0, y = -13, visible = false },
            buffs = { x = 0, y = 52, visible = true },
            debuffs = { x = 0, y = -30, visible = true },
        },
    },
}

for profileKey, profile in pairs(profileDefaults) do
    profile.layout.power = { x = 0, y = -14, visible = false }
    for index = 1, VALUE_SLOT_COUNT do
        profile.layout["value" .. index] = { x = 0, y = 0, visible = true }
    end
    if profile.namesLayout then
        profile.namesLayout.power = { x = 0, y = -14, visible = false }
        for index = 1, VALUE_SLOT_COUNT do
            profile.namesLayout["value" .. index] = { x = 0, y = 0, visible = true }
        end
        profile.dungeonNamesLayout = {}
        for key, position in pairs(profile.namesLayout) do
            local text = key == "name" or key == "level"
                or (profileKey == "friendlyPlayer" and key == "guild")
            profile.dungeonNamesLayout[key] = { x = position.x, y = position.y,
                visible = text and position.visible ~= false or false }
        end
    end
    profile.valueSlots = DefaultValueSlots()
end

local defaultRelationshipColours = {
    group = { r = 0.25, g = 1, b = 0.45 },
    guild = { r = 0.35, g = 0.9, b = 0.75 },
    friend = { r = 0.25, g = 0.75, b = 1 },
    recent = { r = 0.82, g = 0.55, b = 1 },
    pvp = { r = 1, g = 0.56, b = 0.2 },
}

local validModes = { auto = true, own = true, overlay = true }
local validFriendlyModes = { names = true, full = true, off = true }
local validFriendlyPvpStyles = { off = true, colour = true, icon = true, both = true }
local validEditorThemes = { auto = true, classic = true, modern = true }
local validAuraSources = { all = true, mine = true }
local healthTexturePaths = {
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8X8",
}

local function CopyDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = value
        end
    end
end

local function NormalizeLayout(layout, fallbackLayout)
    fallbackLayout = fallbackLayout or defaultLayout
    local normalized = {}
    if type(layout) == "table" then
        for key, position in pairs(layout) do
            if type(key) == "string" and key:match("^[%a][%w_%.]*$") and type(position) == "table" then
                local x, y = tonumber(position.x), tonumber(position.y)
                if x and y then
                    local followName
                    if key == "level" then followName = position.followName ~= false end
                    normalized[key] = {
                        x = math.floor(math.max(-280, math.min(280, x)) + 0.5),
                        y = math.floor(math.max(-105, math.min(105, y)) + 0.5),
                        visible = position.visible ~= false,
                        scale = math.floor(math.max(0.5, math.min(2, tonumber(position.scale) or 1)) * 20 + 0.5) / 20,
                        followName = followName,
                    }
                end
            end
        end
    end
    for key, position in pairs(fallbackLayout) do
        if not normalized[key] then
            local followName
            if key == "level" then followName = position.followName ~= false end
            normalized[key] = { x = position.x, y = position.y, visible = position.visible ~= false,
                scale = math.floor(math.max(0.5, math.min(2, tonumber(position.scale) or 1)) * 20 + 0.5) / 20,
                followName = followName }
        end
    end
    return normalized
end

local function NormalizeColour(colour, fallback)
    colour = type(colour) == "table" and colour or fallback
    local normalized = {}
    for _, channel in ipairs({ "r", "g", "b" }) do
        normalized[channel] = math.max(0, math.min(1, tonumber(colour[channel]) or fallback[channel]))
    end
    return normalized
end

local function NormalizeProfile(profile, fallback, legacy)
    profile = type(profile) == "table" and profile or {}
    legacy = type(legacy) == "table" and legacy or {}
    local previousLayout = profile.layout or legacy.layout
    profile.scale = math.max(0.7, math.min(1.5, tonumber(profile.scale) or tonumber(legacy.scale) or fallback.scale))
    profile.width = math.floor(math.max(80, math.min(200, tonumber(profile.width) or tonumber(legacy.width) or fallback.width)) + 0.5)
    profile.healthHeight = math.floor(math.max(6, math.min(20, tonumber(profile.healthHeight) or tonumber(legacy.healthHeight) or fallback.healthHeight)) + 0.5)
    profile.powerHeight = math.floor(math.max(3, math.min(14, tonumber(profile.powerHeight) or fallback.powerHeight)) + 0.5)
    profile.nameFontSize = math.floor(math.max(9, math.min(20, tonumber(profile.nameFontSize) or tonumber(legacy.nameFontSize) or fallback.nameFontSize)) + 0.5)
    profile.healthTexture = healthTexturePaths[profile.healthTexture] and profile.healthTexture or fallback.healthTexture
    profile.healthColourMode = profile.healthColourMode == "custom" and "custom" or "automatic"
    profile.healthColour = NormalizeColour(profile.healthColour, fallback.healthColour)
    profile.valueSlots = type(profile.valueSlots) == "table" and profile.valueSlots or {}
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = type(profile.valueSlots[key]) == "table" and profile.valueSlots[key] or {}
        profile.valueSlots[key] = {
            source = valueSources[slot.source] and slot.source or "off",
            anchor = valueAnchors[slot.anchor] and slot.anchor or "health",
            layer = valueLayers[slot.layer] and slot.layer or "front",
            whenMissing = missingAnchorModes[slot.whenMissing] and slot.whenMissing or "fallback",
            fontSize = math.floor(math.max(7, math.min(18, tonumber(slot.fontSize) or 9)) + 0.5),
            colour = NormalizeColour(slot.colour, { r = 1, g = 1, b = 1 }),
        }
    end
    profile.layout = NormalizeLayout(profile.layout or legacy.layout, fallback.layout)
    if fallback.namesLayout then
        if type(profile.namesLayout) ~= "table" then
            profile.namesLayout = NormalizeLayout(nil, fallback.namesLayout)
            if type(previousLayout) == "table" then
                for _, key in ipairs({ "name", "quest", "raidIcon", "relationshipIcon", "pvpIcon", "classification" }) do
                    local position = previousLayout[key]
                    if type(position) == "table" then
                        local migrated = NormalizeLayout({ [key] = position }, fallback.namesLayout)[key]
                        migrated.visible = fallback.namesLayout[key].visible
                        profile.namesLayout[key] = migrated
                    end
                end
            end
        else
            profile.namesLayout = NormalizeLayout(profile.namesLayout, fallback.namesLayout)
        end
        profile.dungeonNamesLayout = NormalizeLayout(profile.dungeonNamesLayout, fallback.dungeonNamesLayout)
    end
    return profile
end

local function CopyEnemyProfile(source)
    local copy = {
        scale = source.scale, width = source.width, healthHeight = source.healthHeight,
        powerHeight = source.powerHeight, nameFontSize = source.nameFontSize,
        healthTexture = source.healthTexture, healthColourMode = source.healthColourMode,
        healthColour = NormalizeColour(source.healthColour, profileDefaults.enemy.healthColour),
        layout = NormalizeLayout(source.layout, profileDefaults.enemy.layout),
        valueSlots = {},
    }
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = source.valueSlots[key]
        copy.valueSlots[key] = { source = slot.source, anchor = slot.anchor,
            layer = slot.layer, whenMissing = slot.whenMissing, fontSize = slot.fontSize,
            colour = NormalizeColour(slot.colour, { r = 1, g = 1, b = 1 }) }
    end
    return NormalizeProfile(copy, profileDefaults.enemy)
end

local function NormalizeProfiles(profiles, legacy)
    profiles = type(profiles) == "table" and profiles or {}
    for _, key in ipairs(profileOrder) do
        profiles[key] = NormalizeProfile(profiles[key], profileDefaults[key], legacy)
    end
    if type(profiles.enemyDungeon) == "table" then
        profiles.enemyDungeon = NormalizeProfile(profiles.enemyDungeon, profiles.enemy)
    else
        profiles.enemyDungeon = nil
    end
    return profiles
end

local settingsMigrations = {
    [1] = function(settings)
        settings.schemaVersion = 2
    end,
    [2] = function(settings)
        settings.layout = NormalizeLayout(settings.layout)
        settings.schemaVersion = 3
    end,
    [3] = function(settings)
        settings.layout = NormalizeLayout(settings.layout)
        settings.schemaVersion = 4
    end,
    [4] = function(settings)
        settings.schemaVersion = 5
    end,
    [5] = function(settings)
        settings.schemaVersion = 6
    end,
    [6] = function(settings)
        settings.schemaVersion = 7
    end,
    [7] = function(settings)
        settings.schemaVersion = 8
    end,
    [8] = function(settings)
        settings.schemaVersion = 9
    end,
    [9] = function(settings)
        settings.plateProfiles = NormalizeProfiles(settings.plateProfiles, settings)
        settings.plateProfiles.friendlyPlayer.layout.relationshipIcon.visible = true
        settings.plateProfiles.enemy.layout.relationshipIcon.visible = false
        settings.plateProfiles.friendlyNPC.layout.relationshipIcon.visible = false
        settings.schemaVersion = 10
    end,
    [10] = function(settings)
        settings.plateProfiles = NormalizeProfiles(settings.plateProfiles, settings)
        -- Guild text is new in schema 11; the old shared layout would otherwise hide it.
        settings.plateProfiles.friendlyPlayer.layout.guild.visible = true
        settings.schemaVersion = 11
    end,
    [11] = function(settings)
        settings.schemaVersion = 12
    end,
    [12] = function(settings)
        settings.schemaVersion = 13
    end,
    [13] = function(settings)
        settings.schemaVersion = 14
    end,
    [14] = function(settings)
        settings.schemaVersion = 15
    end,
    [15] = function(settings)
        settings.schemaVersion = 16
    end,
    [16] = function(settings)
        local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        for _, profileKey in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
            local profile = profiles[profileKey]
            local layout = profile and profile.dungeonNamesLayout
            if type(layout) == "table" then
                for key, position in pairs(layout) do
                    if key ~= "name" and key ~= "level" and key ~= "guild"
                        and type(position) == "table" then position.visible = false end
                end
            end
        end
        settings.schemaVersion = 17
    end,
    [17] = function(settings)
        settings.schemaVersion = 18
    end,
    [18] = function(settings)
        settings.schemaVersion = 19
    end,
}

local function MigrateSettings(settings)
    local version = math.floor(tonumber(settings.schemaVersion) or 1)
    while version < defaults.schemaVersion do
        local migrate = settingsMigrations[version]
        if not migrate then break end
        migrate(settings)
        version = math.floor(tonumber(settings.schemaVersion) or (version + 1))
    end
    return version
end

local function NormalizeSettings(settings)
    settings = type(settings) == "table" and settings or {}
    local schemaVersion = MigrateSettings(settings)
    CopyDefaults(settings, defaults)
    if not validModes[settings.mode] then settings.mode = defaults.mode end
    if not validFriendlyModes[settings.friendly] then settings.friendly = defaults.friendly end
    if not validFriendlyPvpStyles[settings.friendlyPvpStyle] then settings.friendlyPvpStyle = defaults.friendlyPvpStyle end
    if not validEditorThemes[settings.editorTheme] then settings.editorTheme = defaults.editorTheme end
    if not validAuraSources[settings.buffSource] then settings.buffSource = defaults.buffSource end
    if not validAuraSources[settings.debuffSource] then settings.debuffSource = defaults.debuffSource end
    if settings.threatSpotlightStyle ~= "box" and settings.threatSpotlightStyle ~= "sides"
        and settings.threatSpotlightStyle ~= "both" then
        settings.threatSpotlightStyle = defaults.threatSpotlightStyle
    end
    if settings.targetHighlightStyle ~= "off" and settings.targetHighlightStyle ~= "border"
        and settings.targetHighlightStyle ~= "halo" then
        settings.targetHighlightStyle = defaults.targetHighlightStyle
    end
    for _, key in ipairs({ "enabled", "hideUnstyledFriendlyNames", "friendlyRelationshipColours", "restrictedFriendlyNamesOnly", "restrictedFriendlyClassColour", "experimentalDungeonFriendlyText", "showPlayerSurnames", "showGroupIcon", "showGuildIcon", "showClassification", "quest", "threat", "showTagged", "showBuffs", "showDebuffs", "nativeNameFont", "threatConsoleShown" }) do
        if type(settings[key]) ~= "boolean" then settings[key] = defaults[key] end
    end
    settings.scale = math.max(0.7, math.min(1.5, tonumber(settings.scale) or defaults.scale))
    settings.width = math.floor(math.max(80, math.min(200, tonumber(settings.width) or defaults.width)) + 0.5)
    settings.healthHeight = math.floor(math.max(6, math.min(20, tonumber(settings.healthHeight) or defaults.healthHeight)) + 0.5)
    settings.nameFontSize = math.floor(math.max(9, math.min(20, tonumber(settings.nameFontSize) or defaults.nameFontSize)) + 0.5)
    settings.threatConsoleX = math.floor(math.max(-5000, math.min(5000, tonumber(settings.threatConsoleX) or defaults.threatConsoleX)) + 0.5)
    settings.threatConsoleY = math.floor(math.max(-5000, math.min(5000, tonumber(settings.threatConsoleY) or defaults.threatConsoleY)) + 0.5)
    settings.threatSpotlightOthersAlpha = math.max(0.3, math.min(1,
        tonumber(settings.threatSpotlightOthersAlpha) or defaults.threatSpotlightOthersAlpha))
    settings.threatSpotlightDuration = math.floor(math.max(1, math.min(8,
        tonumber(settings.threatSpotlightDuration) or defaults.threatSpotlightDuration)) + 0.5)
    settings.relationshipColours = type(settings.relationshipColours) == "table" and settings.relationshipColours or {}
    for key, fallback in pairs(defaultRelationshipColours) do
        settings.relationshipColours[key] = NormalizeColour(settings.relationshipColours[key], fallback)
    end
    settings.plateProfiles = NormalizeProfiles(settings.plateProfiles, settings)
    -- Preserve the original public fields as aliases for the enemy profile.
    local enemy = settings.plateProfiles.enemy
    settings.scale, settings.width = enemy.scale, enemy.width
    settings.healthHeight, settings.nameFontSize = enemy.healthHeight, enemy.nameFontSize
    settings.layout = enemy.layout
    settings.schemaVersion = math.max(schemaVersion, defaults.schemaVersion)
    return settings
end

PS.ProfileSchema = {
    defaults = defaults,
    defaultLayout = defaultLayout,
    VALUE_SLOT_COUNT = VALUE_SLOT_COUNT,
    valueSources = valueSources,
    valueAnchors = valueAnchors,
    valueLayers = valueLayers,
    missingAnchorModes = missingAnchorModes,
    DefaultValueSlots = DefaultValueSlots,
    profileOrder = profileOrder,
    profileDefaults = profileDefaults,
    defaultRelationshipColours = defaultRelationshipColours,
    validModes = validModes,
    validFriendlyModes = validFriendlyModes,
    validFriendlyPvpStyles = validFriendlyPvpStyles,
    validAuraSources = validAuraSources,
    healthTexturePaths = healthTexturePaths,
    CopyDefaults = CopyDefaults,
    NormalizeLayout = NormalizeLayout,
    NormalizeColour = NormalizeColour,
    NormalizeProfile = NormalizeProfile,
    CopyEnemyProfile = CopyEnemyProfile,
    MigrateSettings = MigrateSettings,
    NormalizeSettings = NormalizeSettings,
}
