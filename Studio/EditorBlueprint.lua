local _, PS = ...

local Options = assert(PS.Options, "PlateSmith EditorComponents missing")
local catalog = assert(Options.editorCatalog)
local editorDefaults = catalog.editorDefaults
local editorOrder = catalog.editorOrder
local editorDefinitions = catalog.editorDefinitions
local VALUE_SLOT_COUNT = catalog.VALUE_SLOT_COUNT
local valueSourceByKey = catalog.valueSourceByKey

local editorBaseProfileSet = { enemy = true, friendlyPlayer = true, friendlyNPC = true }
local editorLayoutProfiles = {
    { key = "enemy", profile = "enemy", variant = "full" },
    { key = "friendlyPlayer", profile = "friendlyPlayer", variant = "full" },
    { key = "friendlyNPC", profile = "friendlyNPC", variant = "full" },
    { key = "friendlyPlayerNames", profile = "friendlyPlayer", variant = "names" },
    { key = "friendlyNPCNames", profile = "friendlyNPC", variant = "names" },
}
local editorLayoutProfileByKey = {}
for _, definition in ipairs(editorLayoutProfiles) do editorLayoutProfileByKey[definition.key] = definition end
local function CopyEditorLayout(source)
    local result = {}
    source = type(source) == "table" and source or editorDefaults
    for _, key in ipairs(editorOrder) do
        local fallback = editorDefaults[key]
        local position = type(source[key]) == "table" and source[key] or fallback
        local visible = fallback.visible
        if type(position.visible) == "boolean" then visible = position.visible end
        result[key] = {
            x = tonumber(position.x) or fallback.x,
            y = tonumber(position.y) or fallback.y,
            visible = visible ~= false,
            scale = tonumber(position.scale) or 1,
            followName = key == "level" and position.followName ~= false or nil,
        }
        if key == "level" and position.followName == false then result[key].followName = false end
    end
    return result
end

Options.editorBlueprint = { CopyLayout = CopyEditorLayout }

function Options.editorBlueprint.RegisterFields(editorProfiles)
Options.editorLayout = CopyEditorLayout(editorDefaults)

local function EncodeOneEditorLayout(layout)
    local fields = {}
    for _, key in ipairs(editorOrder) do
        local position = layout[key] or editorDefaults[key]
        local x = math.floor((tonumber(position.x) or 0) + 0.5)
        local y = math.floor((tonumber(position.y) or 0) + 0.5)
        local scale = math.floor((tonumber(position.scale) or 1) * 100 + 0.5)
        local encoded = string.format("%s:%d:%d:%d", key, x, y, position.visible == false and 0 or 1)
        if key == "level" and position.followName == false then
            fields[#fields + 1] = encoded .. ":" .. scale .. ":0"
        else
            fields[#fields + 1] = scale == 100 and encoded or (encoded .. ":" .. scale)
        end
    end
    return table.concat(fields, "/")
end

local function ParseOneEditorLayout(value, fallback)
    if type(value) ~= "string" or value == "" then return nil, "editor layout is empty" end
    local layout, seen = CopyEditorLayout(fallback or editorDefaults), {}
    for field in value:gmatch("[^/]+") do
        local key, x, y, visible, scale, follow = field:match("^([%a][%w_%.]*):([%+%-]?%d+):([%+%-]?%d+):([01]):(%d+):([01])$")
        if not key then
            key, x, y, visible, scale = field:match("^([%a][%w_%.]*):([%+%-]?%d+):([%+%-]?%d+):([01]):(%d+)$")
        end
        if not key then
            key, x, y, visible = field:match("^([%a][%w_%.]*):([%+%-]?%d+):([%+%-]?%d+):([01])$")
        end
        if not key then
            key, x, y = field:match("^([%a][%w_%.]*):([%+%-]?%d+):([%+%-]?%d+)$")
            visible = "1"
        end
        x, y, scale = tonumber(x), tonumber(y), tonumber(scale) or 100
        if not key or seen[key] or not x or not y or scale < 50 or scale > 200 or scale % 5 ~= 0
            or (follow and key ~= "level") then
            return nil, "editor layout contains an invalid component"
        end
        if x < -280 or x > 280 or y < -105 or y > 105 then
            return nil, "editor component is outside the preview canvas"
        end
        seen[key] = true
        if editorDefinitions[key] then
            layout[key] = { x = x, y = y, visible = visible ~= "0", scale = scale / 100 }
            if key == "level" then layout[key].followName = follow ~= "0" end
        end
    end
    return layout
end


local function EncodeEditorLayout()
    local profiles = {}
    for _, definition in ipairs(editorLayoutProfiles) do
        local layout = type(PS.GetLayout) == "function"
            and PS.GetLayout(definition.profile, definition.variant) or nil
        profiles[#profiles + 1] = definition.key .. "~" .. EncodeOneEditorLayout(CopyEditorLayout(layout))
    end
    return table.concat(profiles, "|")
end

local function DerivedNamesLayout(profileKey, full)
    local fallback = type(PS.GetDefaultLayout) == "function" and PS.GetDefaultLayout(profileKey, "names") or editorDefaults
    local names = CopyEditorLayout(fallback)
    for _, key in ipairs({ "name", "quest", "raidIcon", "relationshipIcon", "pvpIcon", "classification" }) do
        if full[key] then names[key] = CopyEditorLayout({ [key] = full[key] })[key] end
    end
    return names
end

local function ParseEditorLayout(value)
    if type(value) ~= "string" or value == "" then return nil, "editor layout is empty" end
    if not value:find("|", 1, true) and not value:find("~", 1, true) then
        local legacy, reason = ParseOneEditorLayout(value)
        if not legacy then return nil, reason end
        local profiles = {
            enemy = CopyEditorLayout(legacy),
            friendlyPlayer = CopyEditorLayout(legacy),
            friendlyNPC = CopyEditorLayout(legacy),
        }
        profiles.friendlyPlayer.relationshipIcon.visible = true
        profiles.friendlyPlayer.pvpIcon.visible = true
        profiles.friendlyPlayer.classification.visible = false
        profiles.enemy.relationshipIcon.visible = false
        profiles.enemy.pvpIcon.visible = false
        profiles.friendlyNPC.relationshipIcon.visible = false
        profiles.friendlyNPC.pvpIcon.visible = false
        profiles.friendlyNPC.classification.visible = false
        profiles.friendlyPlayerNames = DerivedNamesLayout("friendlyPlayer", profiles.friendlyPlayer)
        profiles.friendlyNPCNames = DerivedNamesLayout("friendlyNPC", profiles.friendlyNPC)
        return profiles
    end
    local result, seen = {}, {}
    for field in value:gmatch("[^|]+") do
        local profileKey, encoded = field:match("^([%a][%w]*)~(.+)$")
        local definition = editorLayoutProfileByKey[profileKey]
        if not definition or seen[profileKey] then
            return nil, "editor layout contains an invalid profile"
        end
        local fallback = type(PS.GetDefaultLayout) == "function"
            and PS.GetDefaultLayout(definition.profile, definition.variant) or editorDefaults
        local layout, reason = ParseOneEditorLayout(encoded, fallback)
        if not layout then return nil, reason end
        seen[profileKey], result[profileKey] = true, layout
    end
    for _, profile in ipairs(editorProfiles) do
        if not result[profile.key] then return nil, "editor layout is missing a profile" end
    end
    result.friendlyPlayerNames = result.friendlyPlayerNames
        or DerivedNamesLayout("friendlyPlayer", result.friendlyPlayer)
    result.friendlyNPCNames = result.friendlyNPCNames
        or DerivedNamesLayout("friendlyNPC", result.friendlyNPC)
    return result
end

if type(PS.RegisterBlueprintField) == "function" then
    PS.RegisterBlueprintField("editor.layout", {
        export = EncodeEditorLayout,
        parse = ParseEditorLayout,
        apply = function(layouts)
            for _, definition in ipairs(editorLayoutProfiles) do
                if type(PS.SetLayout) == "function" then
                    PS.SetLayout(layouts[definition.key], definition.profile, definition.variant)
                end
            end
            Options.editorLayout = CopyEditorLayout(PS.GetLayout(Options.editorProfile, Options:CurrentEditorVariant()))
            Options:RefreshEditorLayout()
            return true
        end,
    })
    PS.RegisterBlueprintField("editor.dungeonfriendly", {
        export = function()
            local fields = {}
            for _, key in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
                fields[#fields + 1] = key .. "~"
                    .. EncodeOneEditorLayout(CopyEditorLayout(PS.GetLayout(key, "dungeon")))
            end
            return table.concat(fields, "|")
        end,
        parse = function(value)
            if type(value) ~= "string" or value == "" then
                return nil, "dungeon friendly layouts are empty"
            end
            local layouts, count = {}, 0
            for field in value:gmatch("[^|]+") do
                local key, encoded = field:match("^([%a]+)~(.+)$")
                if (key ~= "friendlyPlayer" and key ~= "friendlyNPC") or layouts[key] then
                    return nil, "dungeon friendly layout has an invalid profile"
                end
                local layout, reason = ParseOneEditorLayout(encoded, PS.GetDefaultLayout(key, "dungeon"))
                if not layout then return nil, reason end
                layouts[key], count = layout, count + 1
            end
            if count ~= 2 then return nil, "dungeon friendly layout is incomplete" end
            return layouts
        end,
        apply = function(layouts)
            for _, key in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
                if not PS.SetLayout(layouts[key], key, "dungeon") then return false end
            end
            return true
        end,
    })
    PS.RegisterBlueprintField("editor.healthstyle", {
        export = function()
            local values = {}
            for _, profile in ipairs(editorProfiles) do
                local settings = PS.GetPlateProfileSettings(profile.key)
                local colour = settings.healthColour
                local function Byte(value) return math.floor(value * 255 + 0.5) end
                values[#values + 1] = table.concat({ profile.key, settings.healthTexture,
                    settings.healthColourMode, Byte(colour.r), Byte(colour.g), Byte(colour.b) }, "~")
            end
            return table.concat(values, "|")
        end,
        parse = function(value)
            if type(value) ~= "string" or value == "" then return nil, "health style is empty" end
            local parsed, count = {}, 0
            for field in value:gmatch("[^|]+") do
                local key, texture, mode, red, green, blue =
                    field:match("^([%a]+)~([%a]+)~([%a]+)~(%d+)~(%d+)~(%d+)$")
                if not editorBaseProfileSet[key] or parsed[key] or (texture ~= "blizzard" and texture ~= "flat")
                    or (mode ~= "automatic" and mode ~= "custom") then
                    return nil, "health style has an invalid profile or setting"
                end
                red, green, blue = tonumber(red), tonumber(green), tonumber(blue)
                if red > 255 or green > 255 or blue > 255 then
                    return nil, "health style colour is outside its range"
                end
                parsed[key] = { texture = texture, mode = mode, r = red / 255, g = green / 255, b = blue / 255 }
                count = count + 1
            end
            if count ~= #editorProfiles then return nil, "health style is missing a profile" end
            return parsed
        end,
        apply = function(styles)
            for _, profile in ipairs(editorProfiles) do
                local style = styles[profile.key]
                PS.SetPlateProfileOption(profile.key, "healthTexture", style.texture)
                PS.SetPlateProfileHealthColour(profile.key, style.r, style.g, style.b)
                PS.SetPlateProfileOption(profile.key, "healthColourMode", style.mode)
            end
            return true
        end,
    })
    PS.RegisterBlueprintField("editor.values", {
        export = function()
            local fields = {}
            for _, profile in ipairs(editorProfiles) do
                local settings = PS.GetPlateProfileSettings(profile.key)
                local slots = settings.valueSlots
                fields[#fields + 1] = profile.key .. "~power~" .. settings.powerHeight
                for index = 1, VALUE_SLOT_COUNT do
                    local key = "value" .. index
                    local slot = slots[key]
                    local colour = slot.colour
                    fields[#fields + 1] = table.concat({ profile.key, key, slot.source,
                        slot.anchor, slot.fontSize, string.format("%02x%02x%02x",
                            math.floor(colour.r * 255 + 0.5), math.floor(colour.g * 255 + 0.5),
                            math.floor(colour.b * 255 + 0.5)), slot.layer or "front",
                        slot.whenMissing or "fallback" }, "~")
                end
            end
            return table.concat(fields, "|")
        end,
        parse = function(value)
            if type(value) ~= "string" or value == "" then return nil, "value settings are empty" end
            local result, count, powerCount = {}, 0, 0
            for field in value:gmatch("[^|]+") do
                local powerProfile, powerHeight = field:match("^([%a]+)~power~(%d+)$")
                if powerProfile then
                    powerHeight = tonumber(powerHeight)
                    if not editorBaseProfileSet[powerProfile] or powerHeight < 3 or powerHeight > 14
                        or (result[powerProfile] and result[powerProfile].powerHeight) then
                        return nil, "value settings contain an invalid power bar"
                    end
                    result[powerProfile] = result[powerProfile] or {}
                    result[powerProfile].powerHeight = powerHeight
                    powerCount = powerCount + 1
                else
                    local profile, key, source, anchor, size, hex, layer, whenMissing =
                        field:match("^([%a]+)~(value%d+)~([%a]+)~([%a]+)~(%d+)~([%da-fA-F]+)~([%a]+)~([%a]+)$")
                    if not profile then
                        profile, key, source, anchor, size, hex, layer =
                            field:match("^([%a]+)~(value%d+)~([%a]+)~([%a]+)~(%d+)~([%da-fA-F]+)~([%a]+)$")
                        whenMissing = "fallback"
                    end
                    if not profile then
                        profile, key, source, anchor, size, hex =
                            field:match("^([%a]+)~(value%d+)~([%a]+)~([%a]+)~(%d+)~([%da-fA-F]+)$")
                        layer = "front"
                        whenMissing = "fallback"
                    end
                    size = tonumber(size)
                    local index = key and tonumber(key:match("^value(%d+)$"))
                    if not editorBaseProfileSet[profile] or not index or index < 1 or index > VALUE_SLOT_COUNT
                        or not (source == "off" or valueSourceByKey[source])
                        or (anchor ~= "canvas" and anchor ~= "health" and anchor ~= "power" and anchor ~= "cast")
                        or not size or size < 7 or size > 18 or not hex or #hex ~= 6
                        or (layer ~= "front" and layer ~= "back")
                        or (whenMissing ~= "fallback" and whenMissing ~= "hide") then
                        return nil, "value settings contain an invalid slot"
                    end
                    result[profile] = result[profile] or {}
                    if result[profile][key] then return nil, "value settings contain a duplicate slot" end
                    result[profile][key] = { source = source, anchor = anchor, layer = layer,
                        whenMissing = whenMissing, fontSize = size,
                        colour = { r = tonumber(hex:sub(1, 2), 16) / 255,
                            g = tonumber(hex:sub(3, 4), 16) / 255,
                            b = tonumber(hex:sub(5, 6), 16) / 255 } }
                    count = count + 1
                end
            end
            if count ~= #editorProfiles * VALUE_SLOT_COUNT or powerCount ~= #editorProfiles then
                return nil, "value settings are incomplete"
            end
            return result
        end,
        apply = function(profiles)
            for _, profile in ipairs(editorProfiles) do
                if not PS.SetPlateProfileOption(profile.key, "powerHeight", profiles[profile.key].powerHeight) then
                    return false
                end
                if not PS.SetPlateValueSlots(profile.key, profiles[profile.key]) then return false end
            end
            Options:RefreshEditorAppearance(PS.GetSettings())
            Options:RefreshEditorLayout()
            return true
        end,
    })
    PS.RegisterBlueprintField("editor.dungeon", {
        export = function()
            local profile = PS.GetDungeonEnemyOverride and PS.GetDungeonEnemyOverride()
            if not profile then return nil end
            local function Hex(colour)
                return string.format("%02x%02x%02x", math.floor(colour.r * 255 + 0.5),
                    math.floor(colour.g * 255 + 0.5), math.floor(colour.b * 255 + 0.5))
            end
            local fields = { table.concat({ profile.scale, profile.width, profile.healthHeight,
                profile.powerHeight, profile.nameFontSize, profile.healthTexture,
                profile.healthColourMode, Hex(profile.healthColour),
                EncodeOneEditorLayout(profile.layout) }, "~") }
            for index = 1, VALUE_SLOT_COUNT do
                local key = "value" .. index
                local slot = profile.valueSlots[key]
                fields[#fields + 1] = table.concat({ key, slot.source, slot.anchor,
                    slot.layer or "front", slot.fontSize, Hex(slot.colour),
                    slot.whenMissing or "fallback" }, "~")
            end
            return table.concat(fields, "|")
        end,
        parse = function(value)
            if type(value) ~= "string" then return nil, "dungeon profile is invalid" end
            local header, fields = value:match("^([^|]+)|(.+)$")
            if not header then return nil, "dungeon profile is incomplete" end
            local scale, width, healthHeight, powerHeight, nameSize, texture, mode, hex, layoutText =
                header:match("^([%d%.]+)~(%d+)~(%d+)~(%d+)~(%d+)~([%a]+)~([%a]+)~([%da-fA-F]+)~(.+)$")
            scale, width, healthHeight = tonumber(scale), tonumber(width), tonumber(healthHeight)
            powerHeight, nameSize = tonumber(powerHeight), tonumber(nameSize)
            if not scale or scale < 0.7 or scale > 1.5 or not width or width < 80 or width > 200
                or not healthHeight or healthHeight < 6 or healthHeight > 20
                or not powerHeight or powerHeight < 3 or powerHeight > 14
                or not nameSize or nameSize < 9 or nameSize > 20
                or (texture ~= "blizzard" and texture ~= "flat")
                or (mode ~= "automatic" and mode ~= "custom") or not hex or #hex ~= 6 then
                return nil, "dungeon profile has invalid geometry or style"
            end
            local layout, reason = ParseOneEditorLayout(layoutText, PS.GetDefaultLayout("enemy", "full"))
            if not layout then return nil, reason end
            local profile = { scale = scale, width = width, healthHeight = healthHeight,
                powerHeight = powerHeight, nameFontSize = nameSize, healthTexture = texture,
                healthColourMode = mode, layout = layout, valueSlots = {},
                healthColour = { r = tonumber(hex:sub(1, 2), 16) / 255,
                    g = tonumber(hex:sub(3, 4), 16) / 255,
                    b = tonumber(hex:sub(5, 6), 16) / 255 } }
            local count = 0
            for field in fields:gmatch("[^|]+") do
                local key, source, anchor, layer, size, colour, whenMissing =
                    field:match("^(value%d+)~([%a]+)~([%a]+)~([%a]+)~(%d+)~([%da-fA-F]+)~([%a]+)$")
                if not key then
                    key, source, anchor, layer, size, colour =
                        field:match("^(value%d+)~([%a]+)~([%a]+)~([%a]+)~(%d+)~([%da-fA-F]+)$")
                    whenMissing = "fallback"
                end
                local index = key and tonumber(key:match("^value(%d+)$"))
                size = tonumber(size)
                if not index or index < 1 or index > VALUE_SLOT_COUNT or profile.valueSlots[key]
                    or not (source == "off" or valueSourceByKey[source])
                    or (anchor ~= "canvas" and anchor ~= "health" and anchor ~= "power" and anchor ~= "cast")
                    or (layer ~= "front" and layer ~= "back")
                    or (whenMissing ~= "fallback" and whenMissing ~= "hide")
                    or not size or size < 7 or size > 18 or not colour or #colour ~= 6 then
                    return nil, "dungeon profile has an invalid value slot"
                end
                profile.valueSlots[key] = { source = source, anchor = anchor, layer = layer,
                    whenMissing = whenMissing,
                    fontSize = size, colour = { r = tonumber(colour:sub(1, 2), 16) / 255,
                        g = tonumber(colour:sub(3, 4), 16) / 255,
                        b = tonumber(colour:sub(5, 6), 16) / 255 } }
                count = count + 1
            end
            if count ~= VALUE_SLOT_COUNT then return nil, "dungeon profile is missing value slots" end
            return profile
        end,
        apply = function(profile)
            return PS.SetDungeonEnemyProfile(profile)
        end,
    })
end

end
