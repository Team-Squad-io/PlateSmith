local _, PS = ...

local Options = assert(PS.Options, "PlateSmith EditorComponents missing")
local catalog = assert(Options.editorCatalog)
local editorDefaults = catalog.editorDefaults
local editorOrder = catalog.editorOrder
local editorLabels = catalog.editorLabels
local editorDefinitions = catalog.editorDefinitions
local VALUE_SLOT_COUNT = catalog.VALUE_SLOT_COUNT
local valueSourceChoices = catalog.valueSourceChoices
local valueSourceByKey = catalog.valueSourceByKey
local valueAnchorChoices = catalog.valueAnchorChoices
local editorProfiles = {
    { key = "enemy", label = "Enemies", sampleName = "Training Raider", colour = { 1, 0.25, 0.2 } },
    { key = "friendlyPlayer", label = "Players", sampleName = "Your Character", colour = { 0.25, 1, 0.45 } },
    { key = "friendlyNPC", label = "Friendly NPCs", sampleName = "Innkeeper Allison", colour = { 0.35, 0.9, 1 } },
}
local editorGroups = {
    { key = "text", label = "Text", components = { name = true, level = true, guild = true, threat = true, tagged = true } },
    { key = "bars", label = "Bars", components = { health = true, power = true, cast = true } },
    { key = "markers", label = "Markers", components = { quest = true, raidIcon = true, relationshipIcon = true, pvpIcon = true, classification = true } },
    { key = "auras", label = "Auras", components = { buffs = true, debuffs = true } },
    { key = "other", label = "Other", components = {} },
}
for index = 1, VALUE_SLOT_COUNT do editorGroups[1].components["value" .. index] = true end
local function EditorGroupForKey(key)
    for _, group in ipairs(editorGroups) do
        if group.components[key] then return group.key end
    end
    return "other"
end
local editorContextForKey = {
    name = "name", level = "level", guild = "guild",
    health = "health", power = "power", cast = "cast",
    threat = "threat", tagged = "tagged", quest = "quest",
    raidIcon = "raidIcon", relationshipIcon = "relationshipIcon", pvpIcon = "pvpIcon", classification = "classification",
    buffs = "buffs", debuffs = "debuffs",
}
for index = 1, VALUE_SLOT_COUNT do editorContextForKey["value" .. index] = "value" end
local editorDescriptions = {
    name = "The readable name displayed above this unit.",
    level = "The unit level, positioned independently.",
    guild = "A readable guild name above friendly players outdoors.",
    health = "The main health display for this unit.",
    power = "A movable power bar; mana is shown for units that use mana.",
    cast = "Tracks the unit's current cast.",
    threat = "Percentage and signed lead when the client permits it.",
    tagged = "Appears when another player or group has tagged this mob.",
    quest = "Marks an active quest objective or possible item drop.",
    raidIcon = "Shows the assigned Blizzard raid target icon.",
    relationshipIcon = "Marks current group or guild members outdoors.",
    pvpIcon = "Marks a PvP-flagged friendly player outdoors.",
    classification = "Shows elite, rare, rare elite, or world-boss status.",
    buffs = "Helpful auras near the nameplate.",
    debuffs = "Harmful auras near the nameplate.",
}
for index = 1, VALUE_SLOT_COUNT do
    editorDescriptions["value" .. index] = "Choose a live value, attach it to a bar or the plate, then position it."
end
local editorProfileSet = { enemy = true, enemyDungeon = true, friendlyPlayer = true, friendlyNPC = true }
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
Options.editorProfile = "enemy"
Options.editorContext = "world"
Options.editorPreviewZoom = 2
Options.editorSnap = true
Options.editorGroupOpen = { text = true, bars = true, markers = true, auras = true, other = true }

function Options:CurrentEditorVariant()
    if self.editorProfile == "enemy" or self.editorProfile == "enemyDungeon" then return "full" end
    if self.editorContext == "dungeon" then return "dungeon" end
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return settings and settings.friendly == "names" and "names" or "full"
end

local modeChoices = {
    { value = "auto", label = "Automatic" },
    { value = "own", label = "PlateSmith skin" },
    { value = "overlay", label = "Overlay only" },
}

local friendlyChoices = {
    { value = "names", label = "Names only" },
    { value = "full", label = "Full plates" },
    { value = "off", label = "Blizzard plates" },
}

local friendlyPvpChoices = {
    { value = "off", label = "Off" },
    { value = "colour", label = "Name colour" },
    { value = "icon", label = "Faction icon" },
    { value = "both", label = "Colour and icon" },
}

local editorThemeChoices = {
    { value = "auto", label = "Automatic" },
    { value = "classic", label = "Classic" },
    { value = "modern", label = "Modern" },
}

local spotlightStyleChoices = {
    { value = "box", label = "Outline box" },
    { value = "sides", label = "Side chevrons" },
    { value = "both", label = "Box and chevrons" },
}

local targetHighlightChoices = {
    { value = "off", label = "Off", help = "No extra glow. The health bar keeps its normal target edge." },
    { value = "border", label = "Steady glow", help = "Gold light follows the selected plate's text and visible bars, without a box around the whole plate." },
    { value = "halo", label = "Pulsing glow", help = "The same text-and-bar glow gently pulses around the selected plate." },
}

local auraSourceChoices = {
    { value = "mine", label = "Only mine (pet included)" },
    { value = "all", label = "Everyone's" },
}

local function IsReadableValue(value)
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        return ok and readable == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return not ok or secret ~= true
    end
    return true
end

local function CurrentCharacterName()
    local readers = {
        function()
            return type(GetUnitName) == "function" and GetUnitName("player", true) or nil
        end,
        function()
            return type(UnitPVPName) == "function" and UnitPVPName("player") or nil
        end,
        function()
            return type(UnitName) == "function" and UnitName("player") or nil
        end,
    }
    for _, reader in ipairs(readers) do
        local ok, name = pcall(reader)
        if ok and IsReadableValue(name) and type(name) == "string" and name ~= "" and name ~= "player" then
            return name
        end
    end
    return "Your Character"
end

local function AddLabel(parent, text, x, y, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function ChoiceLabel(choices, value)
    for _, choice in ipairs(choices) do
        if choice.value == value then return choice.label end
    end
    return choices[1].label
end

local function WidgetName(key, suffix)
    local safeKey = key:gsub("[^%w_]", "_")
    return "PlateSmith" .. safeKey:sub(1, 1):upper() .. safeKey:sub(2) .. suffix
end

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

local function Notify(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441PlateSmith:|r " .. tostring(message))
    end
end

local function SetEditBoxText(editBox, text)
    if not editBox then return end
    editBox:SetText(text or "")
    if editBox.HighlightText then editBox:HighlightText() end
    if editBox.SetFocus then editBox:SetFocus() end
end

local importSections = {
    { key = "settings", label = "General settings" },
    { key = "layouts", label = "World layouts" },
    { key = "dungeonFriendly", label = "Dungeon friendly names" },
    { key = "styles", label = "Bar styles" },
    { key = "values", label = "Custom values & power" },
    { key = "dungeon", label = "Dungeon enemy profile" },
    { key = "other", label = "Companion-addon data" },
}

local function EnsureBlueprintWindow()
    if Options.blueprintWindow then return Options.blueprintWindow end
    local window = CreateFrame("Frame", "PlateSmithBlueprintWindow", UIParent, "BackdropTemplate")
    window:SetSize(730, 540)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    window:SetScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    window:SetBackdropColor(0.025, 0.03, 0.035, 0.98)
    window:SetBackdropBorderColor(0.58, 0.42, 0.19, 0.95)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -15)
    local instruction = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instruction:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -45)
    instruction:SetWidth(680)
    instruction:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() window:Hide() end)
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -78)
    scroll:SetSize(680, 252)
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetWidth(650)
    editBox:SetHeight(250)
    if editBox.SetMaxLetters then editBox:SetMaxLetters(16384) end
    editBox:SetScript("OnEscapePressed", function() window:Hide() end)
    scroll:SetScrollChild(editBox)
    local selectionLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectionLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -345)
    selectionLabel:SetText("Import only these sections")
    local checkboxes = {}
    for index, section in ipairs(importSections) do
        local checkbox = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        checkbox:SetPoint("TOPLEFT", window, "TOPLEFT", 18 + column * 345, -370 - row * 28)
        local label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetText(section.label)
        checkboxes[section.key] = checkbox
    end
    local selectAll = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    selectAll:SetSize(110, 24)
    selectAll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 15)
    selectAll:SetText("Select all")
    selectAll:SetScript("OnClick", function() editBox:SetFocus(); editBox:HighlightText() end)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
    local action = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    action:SetSize(120, 24)
    action:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 15)
    action:SetText("Import selected")
    action:SetScript("OnClick", function()
        local selection = {}
        for _, section in ipairs(importSections) do
            selection[section.key] = checkboxes[section.key]:GetChecked() and true or false
        end
        local ok, reason = PS.ImportBlueprint(editBox:GetText(), selection)
        if ok then
            Options:Refresh()
            window:Hide()
            Notify("Selected Blueprint sections imported.")
        else
            Notify("Blueprint import failed: " .. tostring(reason or "invalid data"))
        end
    end)
    window.title = title
    window.instruction = instruction
    window.editBox = editBox
    window.scroll = scroll
    window.selectAll = selectAll
    window.selectionLabel = selectionLabel
    window.checkboxes = checkboxes
    window.hint = hint
    window.action = action
    Options.blueprintWindow = window
    window:Hide()
    return window
end

function Options:ShowExportBlueprint()
    if type(PS.ExportShareCode) ~= "function" then
        Notify("Blueprint exporting is not available in this build.")
        return
    end
    local blueprint, reason = PS.ExportShareCode()
    if not blueprint then Notify("Blueprint export failed: " .. tostring(reason)) return end
    local window = EnsureBlueprintWindow()
    window.title:SetText("PlateSmith · Export / Share")
    window.instruction:SetText("Copy this compressed share code with Ctrl+C. Existing PS1 codes still import.")
    window.selectionLabel:Hide()
    for _, checkbox in pairs(window.checkboxes) do checkbox:Hide() end
    window.action:Hide()
    window.hint:SetText("Press Ctrl+C to copy")
    SetEditBoxText(window.editBox, blueprint)
    window.editBox:SetHeight(math.max(250, math.ceil(#blueprint / 78) * 16))
    window:Show()
    SetEditBoxText(window.editBox, blueprint)
end

function Options:ShowImportBlueprint()
    local window = EnsureBlueprintWindow()
    window.title:SetText("PlateSmith · Import Blueprint")
    window.instruction:SetText("Paste a PlateSmith share string, then choose exactly which sections to overwrite.")
    window.selectionLabel:Show()
    for _, checkbox in pairs(window.checkboxes) do checkbox:SetChecked(true); checkbox:Show() end
    window.action:Show()
    window.hint:SetText("Press Ctrl+V to paste")
    window.editBox:SetText("")
    window.editBox:SetHeight(250)
    window:Show()
    window.editBox:SetFocus()
end

function Options:GetEditorLayout()
    return CopyEditorLayout(self.editorLayout)
end

function Options:ApplyEditorLayout(layout)
    local variant = self:CurrentEditorVariant()
    if type(PS.SetLayout) == "function" then PS.SetLayout(layout, self.editorProfile, variant) end
    self.editorLayout = CopyEditorLayout(type(PS.GetLayout) == "function"
        and PS.GetLayout(self.editorProfile, variant) or layout)
    self:RefreshEditorLayout()
end

function Options:RefreshEditorComponentList(settings)
    local content = self.editorListContent
    if not content then return end
    local y = -8
    for _, group in ipairs(editorGroups) do
        local count = 0
        for _, key in ipairs(editorOrder) do
            if EditorGroupForKey(key) == group.key and self:IsEditorComponentRelevant(key, settings) then
                count = count + 1
            end
        end
        local header = self.editorGroupButtons[group.key]
        header:SetShown(count > 0)
        if count > 0 then
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 5, y)
            header.label:SetText(group.label)
            header.expander:SetText(self.editorGroupOpen[group.key] and "-" or "+")
            y = y - 27
        end
        for _, key in ipairs(editorOrder) do
            if EditorGroupForKey(key) == group.key then
                local button = self.editorComponentButtons[key]
                if button then
                    local shown = count > 0 and self.editorGroupOpen[group.key]
                        and self:IsEditorComponentRelevant(key, settings)
                    button:SetShown(shown)
                    if button.visibility and self.editorLayout and self.editorLayout[key] then
                        button.visibility:SetChecked(self.editorLayout[key].visible ~= false)
                    end
                    if shown then
                        button:ClearAllPoints()
                        button:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y)
                        y = y - 23
                    end
                end
            end
        end
        if group.key == "text" and self.editorAddValueButton then
            local canAdd = self.editorProfile == "enemy" or self.editorProfile == "enemyDungeon"
                or self.editorContext == "dungeon" or (settings and settings.friendly == "full")
            local profile = PS.GetPlateProfileSettings(self.editorProfile)
            if canAdd and profile and profile.valueSlots then
                canAdd = false
                for index = 1, VALUE_SLOT_COUNT do
                    if profile.valueSlots["value" .. index].source == "off" then canAdd = true break end
                end
            else
                canAdd = false
            end
            self.editorAddValueButton:SetShown(canAdd and self.editorGroupOpen.text)
            if canAdd and self.editorGroupOpen.text then
                self.editorAddValueButton:ClearAllPoints()
                self.editorAddValueButton:SetPoint("TOPLEFT", content, "TOPLEFT", 21, y - 2)
                y = y - 27
            end
        end
    end
    local contentHeight = math.max(10, -y + 8)
    content:SetHeight(contentHeight)
    local scrollBar = self.editorListScroll and (self.editorListScroll.ScrollBar
        or _G.PlateSmithEditorComponentScrollScrollBar)
    if scrollBar and self.editorListScroll then
        scrollBar:SetShown(contentHeight > self.editorListScroll:GetHeight() + 2)
    end
end

function Options:AddValueSlot()
    local settings = PS.GetSettings()
    if self.editorProfile ~= "enemy" and self.editorProfile ~= "enemyDungeon"
        and self.editorContext ~= "dungeon"
        and (not settings or settings.friendly ~= "full") then return false end
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    if not profile or not profile.valueSlots then return false end
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        if profile.valueSlots[key].source == "off" then
            PS.SetPlateValueSlot(self.editorProfile, key, "source", "healthPercent")
            self:RefreshEditorAppearance(PS.GetSettings())
            self:SelectEditorComponent(key)
            return true
        end
    end
    return false
end

function Options:SetEditorGroupOpen(groupKey, open)
    if self.editorGroupOpen[groupKey] == nil then return false end
    self.editorGroupOpen[groupKey] = open and true or false
    self:RefreshEditorComponentList(PS.GetSettings())
    return true
end

function Options:RefreshEditorInspectorContext()
    local key = self.selectedComponent
    if self.editorComponentTitle then
        self.editorComponentTitle:SetText(key and (editorLabels[key] or key) or "Select a component")
    end
    if self.editorComponentDescription then
        self.editorComponentDescription:SetText(key and (editorDescriptions[key] or "Edit this nameplate component.") or "")
    end
    local selectedContext = key and (editorContextForKey[key] or "other")
    for contextKey, frame in pairs(self.editorContextFrames or {}) do
        frame:SetShown(contextKey == selectedContext)
    end
    if self.editorSurnameControl then
        self.editorSurnameControl:SetShown(key == "name" and self.editorProfile == "friendlyPlayer")
    end
    if self.editorCoordinateX and self.editorCoordinateY then
        local position = key and self.editorLayout and self.editorLayout[key]
        self.editorCoordinateX:SetText(position and tostring(position.x) or "")
        self.editorCoordinateY:SetText(position and tostring(position.y) or "")
    end
    if self.editorComponentScaleSlider then
        local position = key and self.editorLayout and self.editorLayout[key]
        local scale = position and position.scale or 1
        self.refreshingComponentScale = true
        self.editorComponentScaleSlider:SetValue(scale)
        self.refreshingComponentScale = false
        self.editorComponentScaleText:SetText(string.format("%d%%", math.floor(scale * 100 + 0.5)))
        self.editorComponentScaleControls:SetShown(position ~= nil)
    end
    if self.editorLevelFollowName then
        local level = self.editorLayout and self.editorLayout.level
        self.editorLevelFollowName:SetChecked(not level or level.followName ~= false)
    end
    local movable = key and self:IsEditorComponentRelevant(key)
        and editorDefinitions[key] and editorDefinitions[key].movable ~= false
    if self.editorMoveControls then
        self.editorMoveControls:SetShown(movable and self.editorInspectorPage == "components" and true or false)
    end
    if self.editorCoordinateControls then self.editorCoordinateControls:SetShown(movable and true or false) end
    if self.valueControlsRefresh then self.valueControlsRefresh(key) end
end

function Options:RefreshEditorComponentLayers()
    if not self.editorPreviewStage or not self.editorComponents then return end
    local profile = type(PS.GetPlateProfileSettings) == "function"
        and PS.GetPlateProfileSettings(self.editorProfile) or nil
    local base = self.editorPreviewStage:GetFrameLevel()
    for key, component in pairs(self.editorComponents) do
        local slot = key:match("^value%d+$") and profile and profile.valueSlots[key] or nil
        local level = key == self.selectedComponent and 30
            or (slot and (slot.layer == "front" and 20 or 1) or 5)
        component:SetFrameLevel(base + level)
    end
end

function Options:SelectEditorComponent(key)
    if key and not self:IsEditorComponentRelevant(key) then
        key = self:IsEditorComponentRelevant("name") and "name" or nil
    end
    if key and not editorDefinitions[key] then return end
    self.selectedComponent = key
    if self.componentVisibleCheckbox then
        local position = self.editorLayout and self.editorLayout[key]
        self.refreshingVisibility = true
        self.componentVisibleCheckbox:SetChecked(not position or position.visible ~= false)
        self.componentVisibleCheckbox:SetShown(key ~= nil)
        self.refreshingVisibility = false
    end
    for componentKey, component in pairs(self.editorComponents or {}) do
        if component.SetBackdropBorderColor then
            if componentKey == "quest" then
                component:SetBackdropBorderColor(0, 0, 0, 0)
            elseif componentKey == key then
                component:SetBackdropBorderColor(1, 0.72, 0.12, 1)
            else
                component:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.55)
            end
        end
    end
    for componentKey, button in pairs(self.editorComponentButtons or {}) do
        if button.selection then button.selection:SetShown(componentKey == key) end
        if button.visibility and self.editorLayout and self.editorLayout[componentKey] then
            button.visibility:SetChecked(self.editorLayout[componentKey].visible ~= false)
        end
        if button.label then
            if componentKey == key then button.label:SetTextColor(1, 0.82, 0.12)
            else button.label:SetTextColor(0.93, 0.87, 0.73) end
        end
    end
    self:RefreshEditorComponentLayers()
    self:RefreshEditorInspectorContext()
    if key and self.editorWorkspacePage ~= "settings" then self:SetEditorInspectorPage("components") end
end

function Options:SetEditorComponentVisibility(key, visible)
    if not self:IsEditorComponentRelevant(key) then return false end
    local position = self.editorLayout and self.editorLayout[key]
    if not position then return false end
    position.visible = visible and true or false
    if type(PS.SetComponentVisibility) == "function" then
        PS.SetComponentVisibility(key, position.visible, self.editorProfile, self:CurrentEditorVariant())
        self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    else
        self:ApplyEditorLayout(self.editorLayout)
    end
    self:RefreshEditorLayout()
    self:RefreshEditorAppearance(PS.GetSettings())
    self:SelectEditorComponent(key)
    return true
end

function Options:PositionEditorComponent(key)
    local component = self.editorComponents and self.editorComponents[key]
    local position = self.editorLayout and self.editorLayout[key]
    if not component or not position then return end
    component:ClearAllPoints()
    component:SetScale(position.scale or 1)
    if key == "level" and position.followName ~= false
        and self.editorLayout.name and self.editorLayout.name.visible ~= false then
        local name = self.editorComponents.name
        local namePosition = self.editorLayout.name
        component:SetPoint("RIGHT", name.previewText or name, "LEFT", -10 + position.x - self:EditorLevelBaseline(),
            position.y - namePosition.y)
        return
    end
    local anchor = self:EditorValueAnchor(key)
    component:SetPoint("CENTER", anchor or self.editorPreviewStage or self.editorCanvas,
        "CENTER", position.x, position.y)
end

function Options:EditorLevelBaseline()
    return (self.editorProfile == "friendlyPlayer" or self.editorProfile == "friendlyNPC")
        and (self:CurrentEditorVariant() == "names" or self:CurrentEditorVariant() == "dungeon")
        and -85 or -70
end

function Options:EditorLevelCanvasX()
    local position = self.editorLayout and self.editorLayout.level
    local namePosition = self.editorLayout and self.editorLayout.name
    local name = self.editorComponents and self.editorComponents.name
    local level = self.editorComponents and self.editorComponents.level
    if not position or not namePosition or not name or not level then return position and position.x or 0 end
    local text = name.previewText
    local width = text and text.GetStringWidth and text:GetStringWidth() or name:GetWidth()
    return namePosition.x - width * (namePosition.scale or 1) / 2
        - 10 + position.x - self:EditorLevelBaseline() - level:GetWidth() * (position.scale or 1) / 2
end

function Options:EditorLevelLayoutX(canvasX)
    local position = self.editorLayout and self.editorLayout.level
    return (position and position.x or self:EditorLevelBaseline()) + canvasX - self:EditorLevelCanvasX()
end

function Options:EditorValueAnchorKey(key)
    if type(key) ~= "string" or not key:match("^value%d+$") then return nil end
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    local slot = profile and profile.valueSlots and profile.valueSlots[key]
    if not slot or slot.anchor == "canvas" then return nil end
    if slot.whenMissing == "hide" or self.editorLayout[slot.anchor].visible ~= false then
        return slot.anchor
    end
    local fallbacks = slot.anchor == "cast" and { "power", "health" }
        or slot.anchor == "power" and { "health", "cast" } or { "power", "cast" }
    for _, fallback in ipairs(fallbacks) do
        if self.editorLayout[fallback].visible ~= false then return fallback end
    end
    return nil
end

function Options:EditorValueAnchor(key)
    local anchorKey = self:EditorValueAnchorKey(key)
    return anchorKey and self.editorComponents and self.editorComponents[anchorKey] or nil
end

function Options:EditorValueAnchorOffset(key)
    local anchorKey = self:EditorValueAnchorKey(key)
    local position = anchorKey and self.editorLayout and self.editorLayout[anchorKey]
    return position and position.x or 0, position and position.y or 0
end

function Options:SetValueAnchor(key, anchor)
    local position = self.editorLayout and self.editorLayout[key]
    if not position then return false end
    local oldX, oldY = self:EditorValueAnchorOffset(key)
    local absoluteX, absoluteY = position.x + oldX, position.y + oldY
    if not PS.SetPlateValueSlot(self.editorProfile, key, "anchor", anchor) then return false end
    local newX, newY = self:EditorValueAnchorOffset(key)
    PS.SetComponentPosition(key, absoluteX - newX, absoluteY - newY,
        self.editorProfile, self:CurrentEditorVariant())
    self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    self:RefreshEditorLayout()
    self:RefreshEditorInspectorContext()
    return true
end

function Options:UpdateEditorGrid()
    local grid, canvas, stage = self.editorGrid, self.editorCanvas, self.editorPreviewStage
    if not grid or not canvas or not stage then return end
    local zoom = self.editorPreviewZoom or 1
    for _, entry in ipairs(grid.vertical) do
        local line = entry.texture
        line:ClearAllPoints()
        line:SetPoint("CENTER", stage, "CENTER", entry.offset, 0)
        line:SetSize((entry.offset == 0 and 2 or 1) / zoom, (canvas:GetHeight() - 92) / zoom)
    end
    for _, entry in ipairs(grid.horizontal) do
        local line = entry.texture
        line:ClearAllPoints()
        line:SetPoint("CENTER", stage, "CENTER", 0, entry.offset)
        line:SetSize((canvas:GetWidth() - 22) / zoom, (entry.offset == 0 and 2 or 1) / zoom)
    end
end

function Options:SetEditorPreviewZoom(zoom)
    zoom = tonumber(zoom)
    if not zoom then return false end
    self.editorPreviewZoom = math.max(1, math.min(3, math.floor(zoom * 4 + 0.5) / 4))
    if self.editorPreviewStage then self.editorPreviewStage:SetScale(self.editorPreviewZoom) end
    self:UpdateEditorGrid()
    if self.editorZoomText then
        self.editorZoomText:SetText(string.format("%d%%", math.floor(self.editorPreviewZoom * 100 + 0.5)))
    end
    return true
end

function Options:SnapEditorPosition(key, x, y)
    if not self.editorSnap then return x, y end
    local component = self.editorComponents and self.editorComponents[key]
    local profile = type(PS.GetPlateProfileSettings) == "function"
        and PS.GetPlateProfileSettings(self.editorProfile) or PS.GetSettings()
    local halfWidth = ((profile and profile.width or 112) * (profile and profile.scale or 1)) / 2
    local componentHalf = component and component.GetWidth and component:GetWidth() / 2 or 0
    local edge = math.max(0, halfWidth - componentHalf)
    for _, candidate in ipairs({ 0, -edge, edge }) do
        if math.abs(x - candidate) <= 6 then x = candidate break end
    end
    for _, candidate in ipairs({ 0, 16, -13 }) do
        if math.abs(y - candidate) <= 6 then y = candidate break end
    end
    return x, y
end

function Options:SetEditorComponentPosition(key, x, y, snap)
    if not self:IsEditorComponentRelevant(key) or editorDefinitions[key].movable == false then return false end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x ~= x or y ~= y then return false end
    local anchorX, anchorY = self:EditorValueAnchorOffset(key)
    if snap then
        x, y = self:SnapEditorPosition(key, x + anchorX, y + anchorY)
        x, y = x - anchorX, y - anchorY
    end
    x = math.floor(math.max(-280, math.min(280, x)) + 0.5)
    y = math.floor(math.max(-105, math.min(105, y)) + 0.5)
    local position = self.editorLayout[key]
    self.editorLayout[key] = { x = x, y = y, visible = position.visible ~= false,
        scale = position.scale or 1 }
    if type(PS.SetComponentPosition) == "function" then
        PS.SetComponentPosition(key, x, y, self.editorProfile, self:CurrentEditorVariant())
        self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    end
    self:PositionEditorComponent(key)
    self:RefreshEditorInspectorContext()
    return true
end

function Options:SetEditorComponentScale(key, scale)
    if not self:IsEditorComponentRelevant(key) then return false end
    scale = tonumber(scale)
    if not scale or scale ~= scale then return false end
    scale = math.floor(math.max(0.5, math.min(2, scale)) * 20 + 0.5) / 20
    if not PS.SetComponentScale(key, scale, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    self:PositionEditorComponent(key)
    self:RefreshEditorInspectorContext()
    return true
end

function Options:SetEditorLevelFollowName(enabled)
    if not PS.SetLevelFollowName(enabled and true or false, self.editorProfile,
        self:CurrentEditorVariant()) then return false end
    self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
    self:PositionEditorComponent("level")
    self:RefreshEditorInspectorContext()
    return true
end

function Options:NudgeEditorComponent(dx, dy)
    local key = self.selectedComponent
    local position = key and self.editorLayout and self.editorLayout[key]
    if not position then return false end
    local step = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and 10 or 1
    return self:SetEditorComponentPosition(key, position.x + dx * step, position.y + dy * step, false)
end

function Options:CaptureEditorComponent(key)
    local component = self.editorComponents and self.editorComponents[key]
    local canvas = self.editorPreviewStage or self.editorCanvas
    if not component or not canvas or not component.GetCenter or not canvas.GetCenter then return end
    local componentX, componentY = component:GetCenter()
    local canvasX, canvasY = canvas:GetCenter()
    if not componentX or not componentY or not canvasX or not canvasY then return end
    local zoom = self.editorPreviewZoom or 1
    local anchorX, anchorY = self:EditorValueAnchorOffset(key)
    self:SetEditorComponentPosition(key, (componentX - canvasX) / zoom - anchorX,
        (componentY - canvasY) / zoom - anchorY, true)
end

function Options:UpdateEditorDrag()
    local drag = self.editorDrag
    if not drag or type(GetCursorPosition) ~= "function" then return end
    local cursorX, cursorY = GetCursorPosition()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then return end
    local stage = self.editorPreviewStage or self.editorCanvas
    local scale = stage and stage.GetEffectiveScale and stage:GetEffectiveScale()
        or self.editorPreviewZoom or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local rawX = drag.startX + (cursorX - drag.cursorX) / scale
    local rawY = drag.startY + (cursorY - drag.cursorY) / scale
    local x, y = rawX, rawY
    if self.editorSnap then x, y = self:SnapEditorPosition(drag.key, x, y) end
    x, y = math.max(-280, math.min(280, x)), math.max(-105, math.min(105, y))
    drag.x, drag.y = x, y
    drag.component:ClearAllPoints()
    drag.component:SetPoint("CENTER", stage, "CENTER", x, y)
    if self.editorCoordinateX and self.editorCoordinateY then
        local anchorX, anchorY = self:EditorValueAnchorOffset(drag.key)
        self.editorCoordinateX:SetText(tostring(math.floor(x - anchorX + 0.5)))
        self.editorCoordinateY:SetText(tostring(math.floor(y - anchorY + 0.5)))
    end
    if self.editorSnapGuideX then
        self.editorSnapGuideX:SetShown(self.editorSnap and math.abs(x - rawX) > 0.01)
        self.editorSnapGuideX:ClearAllPoints()
        self.editorSnapGuideX:SetPoint("CENTER", stage, "CENTER", x, 0)
    end
    if self.editorSnapGuideY then
        self.editorSnapGuideY:SetShown(self.editorSnap and math.abs(y - rawY) > 0.01)
        self.editorSnapGuideY:ClearAllPoints()
        self.editorSnapGuideY:SetPoint("CENTER", stage, "CENTER", 0, y)
    end
end

function Options:StartEditorDrag(key, component)
    if editorDefinitions[key].movable == false then return end
    self:SelectEditorComponent(key)
    if type(GetCursorPosition) ~= "function" then component:StartMoving() return end
    local cursorX, cursorY = GetCursorPosition()
    local position = self.editorLayout and self.editorLayout[key]
    if not position or type(cursorX) ~= "number" or type(cursorY) ~= "number" then return end
    local anchorX, anchorY = self:EditorValueAnchorOffset(key)
    local levelRelative = key == "level" and position.followName ~= false
        and self.editorLayout.name and self.editorLayout.name.visible ~= false
    local startX = levelRelative and self:EditorLevelCanvasX() or position.x + anchorX
    self.editorDrag = { key = key, component = component, cursorX = cursorX, cursorY = cursorY,
        startX = startX, startY = position.y + anchorY,
        x = startX, y = position.y + anchorY, levelRelative = levelRelative }
    component:SetScript("OnUpdate", function() self:UpdateEditorDrag() end)
end

function Options:StopEditorDrag(key, component)
    if editorDefinitions[key].movable == false then return end
    if self.editorDrag and self.editorDrag.key == key then self:UpdateEditorDrag() end
    component:SetScript("OnUpdate", nil)
    if self.editorSnapGuideX then self.editorSnapGuideX:Hide() end
    if self.editorSnapGuideY then self.editorSnapGuideY:Hide() end
    local drag = self.editorDrag
    self.editorDrag = nil
    if drag and drag.key == key then
        local anchorX, anchorY = self:EditorValueAnchorOffset(key)
        self:SetEditorComponentPosition(key,
            drag.levelRelative and self:EditorLevelLayoutX(drag.x) or drag.x - anchorX,
            drag.y - anchorY, false)
    else
        component:StopMovingOrSizing()
        self:CaptureEditorComponent(key)
    end
end

function Options:RefreshEditorLayout()
    if not self.editorCanvas then return end
    for _, key in ipairs(editorOrder) do self:PositionEditorComponent(key) end
end

function Options:ResetEditorLayout()
    local defaults = type(PS.GetDefaultLayout) == "function"
        and PS.GetDefaultLayout(self.editorProfile, self:CurrentEditorVariant()) or editorDefaults
    self:ApplyEditorLayout(defaults)
    self:SelectEditorComponent((self:CurrentEditorVariant() == "names"
        or self:CurrentEditorVariant() == "dungeon") and "name" or "health")
end

local function MakeEditorComponent(parent, key, width, height)
    local component = CreateFrame("Button", WidgetName(key, "EditorComponent"), parent, "BackdropTemplate")
    component:SetSize(width, height)
    component:SetMovable(editorDefinitions[key].movable ~= false)
    component:EnableMouse(true)
    component:RegisterForDrag("LeftButton")
    component:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    component:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.55)
    component:SetScript("OnMouseDown", function() Options:SelectEditorComponent(key) end)
    component:SetScript("OnDragStart", function(instance) Options:StartEditorDrag(key, instance) end)
    component:SetScript("OnDragStop", function(instance) Options:StopEditorDrag(key, instance) end)
    return component
end

function Options:IsEditorComponentRelevant(key, settings)
    if not editorDefinitions[key] then return false end
    settings = settings or (type(PS.GetSettings) == "function" and PS.GetSettings())
    local friendlyMode = self.editorContext == "dungeon" and self.editorProfile ~= "enemyDungeon"
        and "full" or (settings and settings.friendly)
    if key:match("^value%d+$") then
        local profile = PS.GetPlateProfileSettings(self.editorProfile)
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if not slot or slot.source == "off" then return false end
        if self.editorProfile ~= "enemy" and self.editorProfile ~= "enemyDungeon"
            and friendlyMode ~= "full" then return false end
        return true
    end
    if self.editorProfile == "enemy" or self.editorProfile == "enemyDungeon" then
        return key ~= "guild" and key ~= "relationshipIcon" and key ~= "pvpIcon"
    end
    if friendlyMode == "off" or not friendlyMode then return false end
    if key == "health" or key == "power" or key == "cast" then return friendlyMode == "full" end
    if key == "threat" or key == "tagged" then return false end
    if self.editorProfile == "friendlyPlayer" then return key ~= "quest" and key ~= "classification" end
    return key ~= "relationshipIcon" and key ~= "pvpIcon" and key ~= "classification" and key ~= "guild"
end

local function SetTargetPreviewStrength(options, strength)
    for _, component in ipairs(options.targetPreviewTexts or {}) do
        local text = component.previewText
        if strength and component.targetPreviewVisible then
            text:SetShadowColor(1, 0.7, 0.14, strength)
            text:SetShadowOffset(1, -1)
        else
            local original = component.targetPreviewShadow
            text:SetShadowColor(original[1], original[2], original[3], original[4])
            text:SetShadowOffset(original[5], original[6])
        end
    end
    for _, component in ipairs(options.targetPreviewBars or {}) do
        local glow = component.targetPreviewGlow
        glow:SetShown(strength ~= nil and component.targetPreviewVisible)
        if strength then glow:SetAlpha(strength) end
    end
end

local function UpdateTargetPreviewPulse(_, elapsed)
    local options = PS.Options
    if not options.editor or not options.editor:IsShown() or not options.editorCanvas:IsShown() then return end
    options.targetPreviewPulseElapsed = (options.targetPreviewPulseElapsed or 0) + elapsed
    if options.targetPreviewPulseElapsed < 0.05 then return end
    options.targetPreviewPulseElapsed = 0
    SetTargetPreviewStrength(options, 0.4 + 0.3 * (0.5 + 0.5 * math.sin(GetTime() * 3)))
end

function Options:RefreshTargetHighlightPreview(settings)
    if not self.editorCanvas then return end
    local style = settings.targetHighlightStyle
    if self.targetPreviewStyle ~= style then
        self.targetPreviewStyle = style
        self.targetPreviewPulseElapsed = 0
        self.editorCanvas:SetScript("OnUpdate", style == "halo" and UpdateTargetPreviewPulse or nil)
        for _, component in ipairs(self.targetPreviewBars or {}) do
            local glow = component.targetPreviewGlow
            local inset = style == "halo" and 3 or 1
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", component, "TOPLEFT", -inset, inset)
            glow:SetPoint("BOTTOMRIGHT", component, "BOTTOMRIGHT", inset, -inset)
            glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = style == "halo" and 2 or 1 })
            glow:SetBackdropBorderColor(1, 0.7, 0.14, 1)
        end
    end
    SetTargetPreviewStrength(self, style == "border" and 0.7 or style == "halo" and 0.55 or nil)
end

function Options:RefreshEditorAppearance(settings)
    if not self.editorComponents or not settings then return end
    local profile = type(PS.GetPlateProfileSettings) == "function" and PS.GetPlateProfileSettings(self.editorProfile) or settings
    for key, component in pairs(self.editorComponents) do
        local definition = editorDefinitions[key]
        if definition and type(definition.refresh) == "function" then
            local succeeded, reason = pcall(definition.refresh, component, profile)
            if not succeeded then Notify("Editor component refresh failed for " .. key .. ": " .. tostring(reason)) end
        end
        local position = self.editorLayout and self.editorLayout[key]
        local relevant = self:IsEditorComponentRelevant(key, settings)
        local globallyEnabled = relevant and (key ~= "quest" or settings.quest)
            and (key ~= "threat" or settings.threat)
            and (key ~= "buffs" or settings.showBuffs)
            and (key ~= "debuffs" or settings.showDebuffs)
            and (key ~= "pvpIcon" or settings.friendlyPvpStyle == "icon" or settings.friendlyPvpStyle == "both")
            and (key ~= "classification" or settings.showClassification)
        component.targetPreviewVisible = globallyEnabled and position and position.visible ~= false
        component:SetShown(relevant)
        if relevant then
            local slot = key:match("^value%d+$") and profile.valueSlots[key] or nil
            local missingBar = slot and slot.whenMissing == "hide" and slot.anchor ~= "canvas"
                and self.editorLayout[slot.anchor].visible == false
            component:SetAlpha((position and position.visible == false or missingBar) and 0.18
                or (globallyEnabled and 1 or 0.35))
        end
    end
    self:RefreshEditorComponentLayers()
    self:RefreshEditorComponentList(settings)
    if self.editorPreviewStatus then
        local label = self.editorProfile == "enemyDungeon"
            and (PS.GetDungeonEnemyOverride() and "Dungeon enemy · custom layout" or "Dungeon enemy · inherits World")
            or self.editorContext == "dungeon" and "Dungeon friendly · experimental overlay · separate positions"
            or self.editorProfile == "enemy" and "World enemy nameplate"
            or settings.friendly == "names" and "Names only · selected in Friendly units"
            or settings.friendly == "full" and "Full plate · selected in Friendly units"
            or "Blizzard plates · choose Names only or Full plates to edit"
        self.editorPreviewStatus:SetText(label)
    end
    local sample
    for _, definition in ipairs(editorProfiles) do
        if definition.key == self.editorProfile
            or (definition.key == "enemy" and self.editorProfile == "enemyDungeon") then
            sample = definition break
        end
    end
    local name = self.editorComponents.name
    if name and name.previewText and sample then
        name.previewText:SetText(self.editorProfile == "friendlyPlayer" and CurrentCharacterName() or sample.sampleName)
        local colour = self.editorProfile == "friendlyPlayer"
            and (settings.friendlyPvpStyle == "colour" or settings.friendlyPvpStyle == "both")
            and settings.relationshipColours and settings.relationshipColours.pvp
        if colour then
            name.previewText:SetTextColor(colour.r, colour.g, colour.b)
        else
            name.previewText:SetTextColor(sample.colour[1], sample.colour[2], sample.colour[3])
        end
    end
    local level = self.editorComponents.level
    if level and level.previewText then
        level.previewText:SetText((self.editorProfile == "enemy"
            or self.editorProfile == "enemyDungeon") and "14" or "15")
    end
    local guild = self.editorComponents.guild
    if guild and guild.previewText and self.editorProfile == "friendlyPlayer" then
        local ok, guildName = false, nil
        if type(GetGuildInfo) == "function" then ok, guildName = pcall(GetGuildInfo, "player") end
        if ok and IsReadableValue(guildName) and type(guildName) == "string" and guildName ~= "" then
            guild.previewText:SetText("<" .. guildName .. ">")
        else
            guild.previewText:SetText("<Guild Name>")
        end
    end
    if not self:IsEditorComponentRelevant(self.selectedComponent, settings) then
        self:SelectEditorComponent(self:IsEditorComponentRelevant("name", settings) and "name" or nil)
    else
        self:RefreshEditorInspectorContext()
    end
    self:RefreshTargetHighlightPreview(settings)
end

function Options:SetEditorProfile(profileKey)
    if profileKey == "enemy" and self.editorContext == "dungeon" then profileKey = "enemyDungeon" end
    if not editorProfileSet[profileKey] then return false end
    self.editorProfile = profileKey
    self.editorLayout = CopyEditorLayout(type(PS.GetLayout) == "function"
        and PS.GetLayout(profileKey, self:CurrentEditorVariant()) or editorDefaults)
    for key, button in pairs(self.editorProfileButtons or {}) do
        Options.SetStudioButtonState(button, key == profileKey
            or (key == "enemy" and profileKey == "enemyDungeon"))
    end
    self:RefreshEditorLayout()
    self:RefreshEditorAppearance(PS.GetSettings())
    self:SelectEditorComponent(self.selectedComponent or "name")
    self:Refresh()
    self:SetEditorInspectorPage("components")
    return true
end

function Options:SetEditorContext(context)
    if context ~= "world" and context ~= "dungeon" then return false end
    self.editorContext = context
    if self.editorContextDropdown then
        UIDropDownMenu_SetText(self.editorContextDropdown,
            context == "dungeon" and "Dungeon" or "World")
    end
    local category = self.editorProfile == "enemyDungeon" and "enemy" or self.editorProfile
    return self:SetEditorProfile(category)
end

function Options:CreateEditorComponent(key, definition)
    if not self.editorCanvas or self.editorComponents[key] then return self.editorComponents[key] end
    local component = MakeEditorComponent(self.editorPreviewStage or self.editorCanvas,
        key, definition.width, definition.height)
    component.editorDefinition = definition
    self.editorComponents[key] = component
    if type(definition.create) == "function" then
        local succeeded, reason = pcall(definition.create, component, self.editorCanvas)
        if not succeeded then Notify("Editor component creation failed for " .. key .. ": " .. tostring(reason)) end
    end
    if component.previewText and (key == "name" or key == "level" or key == "guild"
        or key == "threat" or key == "tagged" or key == "classification" or key:match("^value%d+$")) then
        local red, green, blue, alpha = component.previewText:GetShadowColor()
        local x, y = component.previewText:GetShadowOffset()
        component.targetPreviewShadow = { red or 0, green or 0, blue or 0, alpha or 0, x or 0, y or 0 }
        self.targetPreviewTexts = self.targetPreviewTexts or {}
        self.targetPreviewTexts[#self.targetPreviewTexts + 1] = component
    elseif key == "health" or key == "power" or key == "cast" then
        local glow = CreateFrame("Frame", nil, component, "BackdropTemplate")
        glow:SetPoint("TOPLEFT", component, "TOPLEFT", -1, 1)
        glow:SetPoint("BOTTOMRIGHT", component, "BOTTOMRIGHT", 1, -1)
        glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        glow:SetBackdropBorderColor(1, 0.7, 0.14, 1)
        glow:EnableMouse(false)
        glow:Hide()
        component.targetPreviewGlow = glow
        self.targetPreviewBars = self.targetPreviewBars or {}
        self.targetPreviewBars[#self.targetPreviewBars + 1] = component
    end
    return component
end

function Options:CreateEditorComponentButton(key)
    if not self.editorListContent or self.editorComponentButtons[key] then return end
    local button = CreateFrame("Button", nil, self.editorListContent)
    button:SetSize(154, 23)
    local selection = button:CreateTexture(nil, "BACKGROUND")
    selection:SetAllPoints()
    selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    selection:SetBlendMode("ADD")
    selection:SetAlpha(0.65)
    selection:Hide()
    button.selection = selection
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", button, "LEFT", 12, 0)
    label:SetText(editorLabels[key])
    button.label = label
    local visibility = CreateFrame("CheckButton", nil, button, "UICheckButtonTemplate")
    visibility:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    visibility:SetSize(21, 21)
    visibility:SetChecked(true)
    visibility:SetScript("OnClick", function(instance)
        self:SetEditorComponentVisibility(key, instance:GetChecked() and true or false)
    end)
    button.visibility = visibility
    button:SetScript("OnClick", function() self:SelectEditorComponent(key) end)
    self.editorComponentButtons[key] = button
    self:RefreshEditorComponentList(PS.GetSettings())
    return button
end

Options.studioModel = {
    editorProfiles = editorProfiles,
    editorGroups = editorGroups,
    modeChoices = modeChoices,
    friendlyChoices = friendlyChoices,
    friendlyPvpChoices = friendlyPvpChoices,
    editorThemeChoices = editorThemeChoices,
    targetHighlightChoices = targetHighlightChoices,
    auraSourceChoices = auraSourceChoices,
    AddLabel = AddLabel,
    WidgetName = WidgetName,
}

function Options:AddDropdown(parent, label, key, choices, x, y, controlID, helpText)
    AddLabel(parent, label, x + 16, y)
    local dropdownName = WidgetName((controlID or "options") .. "_" .. key, "Dropdown")
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y - 18)
    UIDropDownMenu_SetWidth(dropdown, 180)
    UIDropDownMenu_Initialize(dropdown, function()
        local settings = PS.GetSettings()
        for _, choice in ipairs(choices) do
            local selected = choice
            local info = UIDropDownMenu_CreateInfo()
            info.text = selected.label
            info.checked = settings[key] == selected.value
            if selected.help then
                info.tooltipTitle = selected.label
                info.tooltipText = selected.help
                info.tooltipOnButton = true
            end
            info.func = function()
                PS.SetOption(key, selected.value)
                Options:Refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    if helpText then
        local function ShowHelp(instance)
            if not GameTooltip then return end
            GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(helpText, 1, 0.82, 0.45, true)
            for _, choice in ipairs(choices) do
                if choice.help then
                    GameTooltip:AddLine(choice.label .. ": " .. choice.help, 0.86, 0.86, 0.86, true)
                end
            end
            GameTooltip:Show()
        end
        local function HideHelp() if GameTooltip then GameTooltip:Hide() end end
        dropdown:SetScript("OnEnter", ShowHelp)
        dropdown:SetScript("OnLeave", HideHelp)
        local arrow = _G[dropdownName .. "Button"]
        if arrow and arrow.HookScript then
            arrow:HookScript("OnEnter", ShowHelp)
            arrow:HookScript("OnLeave", HideHelp)
        end
        local helpButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        helpButton:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 220, y - 16)
        helpButton:SetSize(18, 18)
        helpButton:SetText("?")
        helpButton:SetScript("OnEnter", ShowHelp)
        helpButton:SetScript("OnLeave", HideHelp)
    end
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings)
            UIDropDownMenu_SetText(dropdown, ChoiceLabel(choices, settings[key]))
        end,
    }
    return dropdown
end

function Options:AddCheckbox(parent, label, key, x, y, controlID)
    local checkbox = CreateFrame("CheckButton", WidgetName((controlID or "options") .. "_" .. key, "Checkbox"), parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", x, y)
    local text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    text:SetText(label)
    checkbox:SetScript("OnClick", function(instance)
        PS.SetOption(key, instance:GetChecked() and true or false)
        Options:Refresh()
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings) checkbox:SetChecked(settings[key]) end,
    }
    return checkbox
end

function Options:AddSlider(parent, label, key, minimum, maximum, step, x, y, formatter, controlID, sliderWidth)
    sliderWidth = sliderWidth or 230
    AddLabel(parent, label, x, y)
    local valueText = AddLabel(parent, "", x + sliderWidth - 30, y, "GameFontHighlightSmall")
    valueText:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", WidgetName((controlID or "options") .. "_" .. key, "Slider"), parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetSize(sliderWidth, 17)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(_, value)
        if Options.refreshing then return end
        value = math.floor(value / step + 0.5) * step
        PS.SetOption(key, value)
        valueText:SetText(formatter(value))
        Options:Refresh()
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings)
            slider:SetValue(settings[key])
            valueText:SetText(formatter(settings[key]))
        end,
    }
    return slider
end

function Options:AddProfileSlider(parent, label, key, minimum, maximum, step, x, y, formatter, controlID, sliderWidth)
    sliderWidth = sliderWidth or 230
    AddLabel(parent, label, x, y)
    local valueText = AddLabel(parent, "", x + sliderWidth - 30, y, "GameFontHighlightSmall")
    valueText:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", WidgetName((controlID or "profile") .. "_profile_" .. key, "Slider"), parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetSize(sliderWidth, 17)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(_, value)
        if Options.refreshing then return end
        value = math.floor(value / step + 0.5) * step
        PS.SetPlateProfileOption(Options.editorProfile, key, value)
        valueText:SetText(formatter(value))
        Options:Refresh()
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function()
            local profile = PS.GetPlateProfileSettings(Options.editorProfile)
            if not profile then return end
            slider:SetValue(profile[key])
            valueText:SetText(formatter(profile[key]))
        end,
    }
    return slider
end

function Options:AddColour(parent, label, relationship, x, y, controlID)
    AddLabel(parent, label, x + 34, y - 5)
    local swatch = CreateFrame("Button", WidgetName((controlID or "options") .. "_" .. relationship, "Colour"), parent, "BackdropTemplate")
    swatch:SetPoint("TOPLEFT", x, y)
    swatch:SetSize(24, 24)
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    swatch:SetScript("OnClick", function()
        local settings = PS.GetSettings()
        local colour = settings and settings.relationshipColours and settings.relationshipColours[relationship]
        if not colour or not ColorPickerFrame then return end
        local previous = { r = colour.r, g = colour.g, b = colour.b }
        local function ApplyPicker()
            if not ColorPickerFrame.GetColorRGB then return end
            local r, g, b = ColorPickerFrame:GetColorRGB()
            PS.SetRelationshipColour(relationship, r, g, b)
            Options:Refresh()
        end
        local function CancelPicker()
            PS.SetRelationshipColour(relationship, previous.r, previous.g, previous.b)
            Options:Refresh()
        end
        if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = previous.r, g = previous.g, b = previous.b,
                swatchFunc = ApplyPicker,
                cancelFunc = CancelPicker,
            })
        else
            ColorPickerFrame.func = ApplyPicker
            ColorPickerFrame.cancelFunc = CancelPicker
            if ColorPickerFrame.SetColorRGB then ColorPickerFrame:SetColorRGB(previous.r, previous.g, previous.b) end
            ColorPickerFrame:Show()
        end
    end)
    self.controls[#self.controls + 1] = {
        Refresh = function(_, settings)
            local colour = settings.relationshipColours and settings.relationshipColours[relationship]
            if colour then swatch:SetBackdropColor(colour.r, colour.g, colour.b, 1) end
        end,
    }
    return swatch
end

function Options:Refresh()
    local settings = PS.GetSettings()
    if not settings then return end
    if type(PS.GetLayout) == "function" then
        self.editorLayout = CopyEditorLayout(PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()))
        self:RefreshEditorLayout()
    end
    self.refreshing = true
    for _, control in ipairs(self.controls) do control:Refresh(settings) end
    self.refreshing = false
    self:RefreshEditorAppearance(settings)
    self:ApplyEditorTheme()
end

function PS.CreateOptions()
    if Options.panel then return Options.panel end

    if type(PS.GetLayout) == "function" then
        Options.editorLayout = CopyEditorLayout(PS.GetLayout())
    end

    local panel = CreateFrame("Frame")
    panel.name = "PlateSmith"
    panel:SetSize(640, 610)
    Options.panel = panel

    AddLabel(panel, "PlateSmith", 20, -16, "GameFontNormalLarge")
    local description = AddLabel(panel, "Readable native nameplates with quest and threat context.", 20, -40, "GameFontHighlightSmall")
    description:SetWidth(600)
    description:SetJustifyH("LEFT")

    AddLabel(panel, "Behaviour", 20, -72, "GameFontNormalLarge")
    Options:AddDropdown(panel, "Appearance ownership", "mode", modeChoices, 20, -98)
    Options:AddDropdown(panel, "Friendly units", "friendly", friendlyChoices, 290, -98)
    Options:AddCheckbox(panel, "Show quest markers", "quest", 24, -154)
    Options:AddCheckbox(panel, "Show threat details", "threat", 290, -154)
    Options:AddCheckbox(panel, "Hide Blizzard fallback names outdoors", "hideUnstyledFriendlyNames", 24, -182)
    Options:AddCheckbox(panel, "Colour groups, friends & recent allies", "friendlyRelationshipColours", 290, -182)
    Options:AddCheckbox(panel, "Show player surnames", "showPlayerSurnames", 24, -210)
    Options:AddCheckbox(panel, "Show tagged indicator", "showTagged", 290, -210)
    Options:AddCheckbox(panel, "Dungeon friendly names only", "restrictedFriendlyNamesOnly", 24, -238)
    Options:AddCheckbox(panel, "Show elite and rare marks", "showClassification", 290, -238)

    AddLabel(panel, "Enemy appearance", 20, -272, "GameFontNormalLarge")
    Options:AddSlider(panel, "Overall scale", "scale", 0.7, 1.5, 0.05, 24, -303,
        function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end)
    Options:AddSlider(panel, "Plate width", "width", 80, 200, 2, 300, -303,
        function(value) return string.format("%d px", value) end)
    Options:AddSlider(panel, "Health-bar height", "healthHeight", 6, 20, 1, 24, -352,
        function(value) return string.format("%d px", value) end)
    Options:AddSlider(panel, "Name size", "nameFontSize", 9, 20, 1, 300, -352,
        function(value) return string.format("%d pt", value) end)

    AddLabel(panel, "Threat-window spotlight", 20, -405, "GameFontNormalLarge")
    Options:AddDropdown(panel, "Selected plate", "threatSpotlightStyle", spotlightStyleChoices, 20, -434)
    Options:AddSlider(panel, "Other enemy plates", "threatSpotlightOthersAlpha", 0.3, 1, 0.05, 300, -434,
        function(value) return string.format("%d%% visible", math.floor(value * 100 + 0.5)) end)
    Options:AddSlider(panel, "Spotlight time", "threatSpotlightDuration", 1, 8, 1, 24, -490,
        function(value) return string.format("%d seconds", value) end)
    local spotlightHelp = AddLabel(panel,
        "Click a threat row to spotlight its plate. Dimming affects PlateSmith enemy artwork, not Blizzard's protected plate.",
        300, -490, "GameFontHighlightSmall")
    spotlightHelp:SetWidth(280)
    spotlightHelp:SetJustifyH("LEFT")

    local reset = CreateFrame("Button", "PlateSmithResetButton", panel, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", 24, -558)
    reset:SetSize(140, 24)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function()
        PS.ResetSettings()
        Options:Refresh()
    end)
    Options.resetButton = reset

    local editor = CreateFrame("Button", "PlateSmithVisualEditorButton", panel, "UIPanelButtonTemplate")
    editor:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    editor:SetSize(180, 24)
    editor:SetText("Open Blueprint Editor")
    editor:SetScript("OnClick", function() PS.OpenVisualEditor() end)
    Options.editorButton = editor

    local threatConsole = CreateFrame("Button", "PlateSmithThreatConsoleButton", panel, "UIPanelButtonTemplate")
    threatConsole:SetPoint("LEFT", editor, "RIGHT", 12, 0)
    threatConsole:SetSize(160, 24)
    threatConsole:SetText("Toggle Threat Console")
    threatConsole:SetScript("OnClick", function()
        if PS.ThreatConsole then PS.ThreatConsole:Toggle() end
    end)
    Options.threatConsoleButton = threatConsole

    panel:SetScript("OnShow", function() Options:Refresh() end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        Options.category = category
        Options.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    Options:Refresh()
    return panel
end

function PS.RegisterModuleSettings(id, title, panel)
    if type(id) ~= "string" or type(title) ~= "string" or not panel then
        return nil, "module settings require an id, title, and panel"
    end
    PS.CreateOptions()
    Options.moduleSettings = Options.moduleSettings or {}
    if Options.moduleSettings[id] then return nil, "module settings are already registered" end

    panel.name = title
    if Settings and Settings.RegisterCanvasLayoutSubcategory and Options.category then
        local category = Settings.RegisterCanvasLayoutSubcategory(Options.category, panel, title)
        Settings.RegisterAddOnCategory(category)
        Options.moduleSettings[id] = category
        return category
    elseif InterfaceOptions_AddCategory then
        panel.parent = "PlateSmith"
        InterfaceOptions_AddCategory(panel)
        Options.moduleSettings[id] = panel
        return panel
    end
    return nil, "module settings are unavailable on this client"
end

function PS.OpenOptions()
    PS.CreateOptions()
    if Settings and Settings.OpenToCategory and Options.categoryID then
        Settings.OpenToCategory(Options.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
    end
end

-- Register display changes at addon load rather than when the editor is opened;
-- Forever may protect new event subscriptions after the UI has entered combat.
local editorDisplayEventFrame = CreateFrame("Frame")
PS._RegisterEvent(editorDisplayEventFrame, "DISPLAY_SIZE_CHANGED", "platesmith.blueprint-editor")
editorDisplayEventFrame:SetScript("OnEvent", function()
    Options:FitVisualEditorToScreen()
end)
