local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local defaults = S.defaults
local DefaultValueSlots = S.DefaultValueSlots
local profileOrder = S.profileOrder
local profileDefaults = S.profileDefaults
local defaultRelationshipColours = S.defaultRelationshipColours
local validModes = S.validModes
local validFriendlyModes = S.validFriendlyModes
local validFriendlyPvpStyles = S.validFriendlyPvpStyles
local validAuraSources = S.validAuraSources
local NormalizeLayout = S.NormalizeLayout
local NormalizeColour = S.NormalizeColour
local NormalizeSettings = S.NormalizeSettings

local blueprintPrefix = "!PS1!"
local blueprintFields = {
    "mode",
    "friendly",
    "friendlyRelationshipColours",
    "friendlyPvpStyle",
    "restrictedFriendlyNamesOnly",
    "restrictedFriendlyClassColour",
    "experimentalDungeonFriendlyText",
    "showPlayerSurnames",
    "showGroupIcon",
    "showGuildIcon",
    "showClassification",
    "groupColour",
    "guildColour",
    "friendColour",
    "recentColour",
    "pvpColour",
    "quest",
    "threat",
    "showTagged",
    "showBuffs",
    "showDebuffs",
    "buffSource",
    "debuffSource",
    "targetHighlightStyle",
    "scale",
    "width",
    "healthHeight",
    "nameFontSize",
}
local blueprintFieldSet = {}
for _, key in ipairs(blueprintFields) do
    blueprintFieldSet[key] = true
end
local blueprintExtensions = {}

local function EncodeScale(value)
    local hundredths = math.floor(value * 100 + 0.5)
    local whole = math.floor(hundredths / 100)
    local fraction = hundredths % 100
    if fraction == 0 then return tostring(whole) end
    if fraction % 10 == 0 then return whole .. "." .. math.floor(fraction / 10) end
    return string.format("%d.%02d", whole, fraction)
end

local function ColourToHex(colour)
    local function channel(value)
        return math.floor(math.max(0, math.min(1, tonumber(value) or 0)) * 255 + 0.5)
    end
    return string.format("%02x%02x%02x", channel(colour.r), channel(colour.g), channel(colour.b))
end

local function HexToColour(value)
    if type(value) ~= "string" or not value:match("^[%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F]$") then
        return nil
    end
    return {
        r = tonumber(value:sub(1, 2), 16) / 255,
        g = tonumber(value:sub(3, 4), 16) / 255,
        b = tonumber(value:sub(5, 6), 16) / 255,
    }
end

local function RegisterBlueprintField(key, descriptor)
    if type(key) ~= "string" or #key > 64 or not key:match("^[a-z][a-z0-9_]*%.[a-z][a-z0-9_]*$") then
        return false, "extension fields must use module.field names"
    end
    if blueprintFieldSet[key] or blueprintExtensions[key] then
        return false, "blueprint field is already registered"
    end
    if type(descriptor) ~= "table"
        or type(descriptor.export) ~= "function"
        or type(descriptor.parse) ~= "function"
        or type(descriptor.apply) ~= "function" then
        return false, "extension field requires export, parse, and apply functions"
    end
    blueprintExtensions[key] = descriptor
    return true
end

local function ExtensionFieldKeys()
    local keys = {}
    for key in pairs(blueprintExtensions) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function ExportBlueprint()
    local db = PS.GetSettings and PS.GetSettings()
    if not db then return nil, "settings are not loaded" end

    local values = {
        mode = db.mode,
        friendly = db.friendly,
        friendlyRelationshipColours = db.friendlyRelationshipColours and "1" or "0",
        friendlyPvpStyle = db.friendlyPvpStyle,
        restrictedFriendlyNamesOnly = db.restrictedFriendlyNamesOnly and "1" or "0",
        restrictedFriendlyClassColour = db.restrictedFriendlyClassColour and "1" or "0",
        experimentalDungeonFriendlyText = db.experimentalDungeonFriendlyText and "1" or "0",
        showPlayerSurnames = db.showPlayerSurnames and "1" or "0",
        showGroupIcon = db.showGroupIcon and "1" or "0",
        showGuildIcon = db.showGuildIcon and "1" or "0",
        showClassification = db.showClassification and "1" or "0",
        groupColour = ColourToHex(db.relationshipColours.group),
        guildColour = ColourToHex(db.relationshipColours.guild),
        friendColour = ColourToHex(db.relationshipColours.friend),
        recentColour = ColourToHex(db.relationshipColours.recent),
        pvpColour = ColourToHex(db.relationshipColours.pvp),
        quest = db.quest and "1" or "0",
        threat = db.threat and "1" or "0",
        showTagged = db.showTagged and "1" or "0",
        showBuffs = db.showBuffs and "1" or "0",
        showDebuffs = db.showDebuffs and "1" or "0",
        buffSource = db.buffSource,
        debuffSource = db.debuffSource,
        targetHighlightStyle = db.targetHighlightStyle,
        scale = EncodeScale(db.scale),
        width = tostring(db.width),
        healthHeight = tostring(db.healthHeight),
        nameFontSize = tostring(db.nameFontSize),
    }
    local fields = {}
    for index, key in ipairs(blueprintFields) do
        fields[index] = key .. "=" .. values[key]
    end
    for _, key in ipairs(ExtensionFieldKeys()) do
        local succeeded, value = pcall(blueprintExtensions[key].export)
        if not succeeded then return nil, "extension export failed: " .. key end
        if value ~= nil then
            value = tostring(value)
            if #value == 0 or #value > 2048 or not value:match("^[%w%._:%+%-%/|~]+$") then
                return nil, "extension exported an unsafe value: " .. key
            end
            fields[#fields + 1] = key .. "=" .. value
        end
    end
    return blueprintPrefix .. table.concat(fields, ";")
end

local function ParseBlueprintValue(key, value)
    if key == "mode" then
        return validModes[value] and value or nil
    elseif key == "friendly" then
        return validFriendlyModes[value] and value or nil
    elseif key == "friendlyPvpStyle" then
        return validFriendlyPvpStyles[value] and value or nil
    elseif key == "buffSource" or key == "debuffSource" then
        return validAuraSources[value] and value or nil
    elseif key == "targetHighlightStyle" then
        return (value == "off" or value == "border" or value == "halo") and value or nil
    elseif key == "friendlyRelationshipColours" or key == "restrictedFriendlyNamesOnly"
        or key == "restrictedFriendlyClassColour"
        or key == "experimentalDungeonFriendlyText"
        or key == "showPlayerSurnames" or key == "showGroupIcon" or key == "showGuildIcon"
        or key == "showClassification"
        or key == "quest" or key == "threat" or key == "showTagged"
        or key == "showBuffs" or key == "showDebuffs" then
        if value == "1" then return true end
        if value == "0" then return false end
        return nil
    elseif key == "groupColour" or key == "guildColour" or key == "friendColour"
        or key == "recentColour" or key == "pvpColour" then
        return HexToColour(value)
    end

    local isDecimal = value:match("^%d+$") or value:match("^%d+%.%d+$")
    if not isDecimal then return nil end
    local number = tonumber(value)
    if key == "scale" then
        return number >= 0.7 and number <= 1.5 and number or nil
    end
    if not value:match("^%d+$") then return nil end
    if key == "width" then
        return number >= 80 and number <= 200 and number or nil
    elseif key == "healthHeight" then
        return number >= 6 and number <= 20 and number or nil
    elseif key == "nameFontSize" then
        return number >= 9 and number <= 20 and number or nil
    end
end

local function ImportBlueprint(text, selection)
    local db = PS.GetSettings and PS.GetSettings()
    if not db then return false, "settings are not loaded" end
    if type(text) ~= "string" then return false, "blueprint must be text" end
    if #text > 8192 then return false, "blueprint is too large" end
    -- Lua substitutions return the replacement count as a second value; legacy callers
    -- may pass that through unintentionally, so only a table opts into selective import.
    if type(selection) ~= "table" then selection = nil end
    local function Selected(section) return not selection or selection[section] == true end
    if selection then
        local any = false
        for _, section in ipairs({ "settings", "layouts", "dungeonFriendly", "styles", "values", "dungeon", "other" }) do
            if Selected(section) then any = true break end
        end
        if not any then return false, "select at least one section" end
    end

    text = text:match("^%s*(.-)%s*$")
    if text:sub(1, #blueprintPrefix) ~= blueprintPrefix then
        return false, "unsupported blueprint version"
    end

    local payload = text:sub(#blueprintPrefix + 1)
    if payload == "" or payload:sub(1, 1) == ";" or payload:sub(-1) == ";" or payload:find(";;", 1, true) then
        return false, "malformed blueprint"
    end

    local parsed = {}
    local parsedExtensions = {}
    local seen = {}
    local coreCount = 0
    for field in payload:gmatch("[^;]+") do
        local key, value = field:match("^([%a][%w_%.]*)=(.+)$")
        if not key or (not blueprintFieldSet[key] and not blueprintExtensions[key]) then
            return false, "unknown or malformed field"
        end
        if seen[key] then return false, "duplicate field: " .. key end
        seen[key] = true
        if blueprintFieldSet[key] then
            local parsedValue = ParseBlueprintValue(key, value)
            if parsedValue == nil then return false, "invalid value for " .. key end
            parsed[key] = parsedValue
            coreCount = coreCount + 1
        else
            if #value > 2048 or not value:match("^[%w%._:%+%-%/|~]+$") then
                return false, "unsafe value for " .. key
            end
            local succeeded, parsedValue, parseError = pcall(blueprintExtensions[key].parse, value)
            if not succeeded or parsedValue == nil then
                return false, parseError or ("invalid value for " .. key)
            end
            parsedExtensions[key] = parsedValue
        end
    end

    -- PS1 predates these display preferences. Keep older Blueprints importable
    -- and treat missing opt-out fields as their default-on values.
    for _, key in ipairs({ "friendlyRelationshipColours", "friendlyPvpStyle", "restrictedFriendlyNamesOnly", "restrictedFriendlyClassColour", "experimentalDungeonFriendlyText", "showPlayerSurnames", "showGroupIcon", "showGuildIcon", "showClassification", "showTagged", "showBuffs", "showDebuffs", "buffSource", "debuffSource", "targetHighlightStyle" }) do
        if parsed[key] == nil and not seen[key] then
            parsed[key] = defaults[key]
            coreCount = coreCount + 1
        end
    end
    local colourFields = {
        groupColour = "group",
        guildColour = "guild",
        friendColour = "friend",
        recentColour = "recent",
        pvpColour = "pvp",
    }
    for field, relationship in pairs(colourFields) do
        if parsed[field] == nil and not seen[field] then
            parsed[field] = NormalizeColour(nil, defaultRelationshipColours[relationship])
            coreCount = coreCount + 1
        end
    end
    if coreCount ~= #blueprintFields then return false, "blueprint is incomplete" end
    for _, key in ipairs(blueprintFields) do
        if parsed[key] == nil then return false, "missing field: " .. key end
    end

    local candidate = {}
    for key, value in pairs(db) do candidate[key] = value end
    candidate.plateProfiles = {}
    for _, profileKey in ipairs(profileOrder) do
        local source = db.plateProfiles[profileKey]
        candidate.plateProfiles[profileKey] = {
            scale = source.scale,
            width = source.width,
            healthHeight = source.healthHeight,
            nameFontSize = source.nameFontSize,
            layout = NormalizeLayout(source.layout, profileDefaults[profileKey].layout),
            namesLayout = profileDefaults[profileKey].namesLayout
                and NormalizeLayout(source.namesLayout, profileDefaults[profileKey].namesLayout) or nil,
        }
    end
    candidate.relationshipColours = {}
    for relationship, colour in pairs(db.relationshipColours) do
        candidate.relationshipColours[relationship] = NormalizeColour(colour, defaultRelationshipColours[relationship])
    end
    if Selected("settings") then
        for _, key in ipairs(blueprintFields) do candidate[key] = parsed[key] end
        for _, key in ipairs({ "scale", "width", "healthHeight", "nameFontSize" }) do
            candidate.plateProfiles.enemy[key] = parsed[key]
        end
    end
    NormalizeSettings(candidate)
    local extensionSections = {
        ["editor.layout"] = "layouts",
        ["editor.dungeonfriendly"] = "dungeonFriendly",
        ["editor.healthstyle"] = "styles",
        ["editor.values"] = "values",
        ["editor.dungeon"] = "dungeon",
    }
    for _, key in ipairs(ExtensionFieldKeys()) do
        if parsedExtensions[key] ~= nil and Selected(extensionSections[key] or "other") then
            local succeeded, applied = pcall(blueprintExtensions[key].apply, parsedExtensions[key])
            if not succeeded or applied == false then return false, "extension apply failed: " .. key end
        end
    end
    if Selected("dungeon") and parsedExtensions["editor.dungeon"] == nil then db.plateProfiles.enemyDungeon = nil end
    if Selected("dungeonFriendly") and parsedExtensions["editor.dungeonfriendly"] == nil then
        for _, key in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
            local world = db.plateProfiles[key].namesLayout
            local dungeon = NormalizeLayout(nil, profileDefaults[key].dungeonNamesLayout)
            for _, component in ipairs({ "name", "level", "guild" }) do
                local position = world[component]
                if position then
                    dungeon[component] = { x = position.x, y = position.y,
                        visible = position.visible ~= false, scale = position.scale or 1 }
                end
            end
            db.plateProfiles[key].dungeonNamesLayout = dungeon
        end
    end
    if Selected("values") and parsedExtensions["editor.values"] == nil then
        for _, key in ipairs(profileOrder) do
            db.plateProfiles[key].valueSlots = DefaultValueSlots()
            db.plateProfiles[key].powerHeight = profileDefaults[key].powerHeight
        end
    end
    if Selected("settings") then
        for _, key in ipairs(blueprintFields) do db[key] = candidate[key] end
        for _, key in ipairs({ "scale", "width", "healthHeight", "nameFontSize" }) do
            db.plateProfiles.enemy[key] = candidate.plateProfiles.enemy[key]
        end
        db.relationshipColours.group = db.groupColour
        db.relationshipColours.guild = db.guildColour
        db.relationshipColours.friend = db.friendColour
        db.relationshipColours.recent = db.recentColour
        db.relationshipColours.pvp = db.pvpColour
    end
    db.groupColour, db.guildColour, db.friendColour, db.recentColour, db.pvpColour = nil, nil, nil, nil, nil
    NormalizeSettings(db)
    PS.Refresh()
    return true
end

PS.RegisterBlueprintField = RegisterBlueprintField
PS.ExportBlueprint = ExportBlueprint
PS.ImportBlueprint = ImportBlueprint
