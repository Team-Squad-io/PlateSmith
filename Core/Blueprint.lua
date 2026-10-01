local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Json = assert(PS.Json, "PlateSmith Json missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local profileOrder = S.profileOrder
local profileDefaults = S.profileDefaults
local defaultRelationshipColours = S.defaultRelationshipColours
local NormalizeLayout = S.NormalizeLayout
local NormalizeSettings = S.NormalizeSettings
local CopyEnemyProfile = S.CopyEnemyProfile
local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT

-- A Blueprint is a JSON document. Missing fields take their defaults; unknown
-- fields are rejected so typos and newer-version data fail loudly.
local FORMAT = "platesmith-blueprint"
-- Version 3 carries custom parts (kinds), templates, rules, styles and Dynamic placement
-- (layoutVersion 3). Version 2 documents still import: their layouts are upgraded on the way in.
local VERSION = 3
local READABLE_VERSIONS = { [2] = true, [3] = true }
local MAX_JSON_BYTES = 65536
local MAX_COMPONENTS = 64

local function Set(...)
    local result = {}
    for index = 1, select("#", ...) do result[select(index, ...)] = true end
    return result
end

local function SetOf(list)
    local result = {}
    for _, value in ipairs(list) do result[value] = true end
    return result
end

-- The general settings a Blueprint carries: Schema's validators, except enabled (whether
-- PlateSmith runs is the player's own, not part of a design).
local booleanSettings = {}
for _, key in ipairs(S.booleanSettings) do
    if key ~= "enabled" then booleanSettings[#booleanSettings + 1] = key end
end
local enumSettings = S.enumSettings
local settingRanges = S.settingRanges
local profileNumbers = S.profileRanges
local healthColourModes = Set("automatic", "custom")
local styleFields = { "scale", "width", "healthHeight", "nameFontSize", "healthTexture", "healthColourMode", "healthColour",
    "powerWidth", "castWidth", "castHeight", "castIcon", "castTime", "castName", "castInterruptColours", "castOnTop",
    "castColours", "questProgress", "questProgressFormat", "rules", "styles" }
local sections = { "settings", "layouts", "dungeonFriendly", "styles", "values", "dungeon", "other" }

local moduleFields = {}

local ColourToHex, HexToColour = PS.Format.ColourToHex, PS.Format.HexToColour

-- Validation raises { blueprintError = "path: reason" } so every check can stay one line.
local function Reject(path, reason) error({ blueprintError = path .. " " .. reason }, 0) end

local function CheckObject(value, path, allowed)
    if type(value) ~= "table" or Json.IsArray(value) then Reject(path, "must be an object") end
    if allowed then
        for key in pairs(value) do
            if not allowed[key] then Reject(path .. "." .. tostring(key), "is not a known field") end
        end
    end
    return value
end

local function CheckRange(value, path, range)
    if not S.InRange(range, value) then
        Reject(path, string.format("must be %s %s-%s", range[3] and "a whole number" or "a number", range[1], range[2]))
    end
    return value
end

local function CheckEnum(value, path, allowed)
    if type(value) ~= "string" or not allowed[value] then Reject(path, "has an unsupported value") end
    return value
end

local function CheckBoolean(value, path)
    if type(value) ~= "boolean" then Reject(path, "must be true or false") end
    return value
end

local function CheckColour(value, path)
    return HexToColour(value) or Reject(path, "must be a six-digit hex colour")
end

-- Text of at most limit characters (names; UTF-8 aware, as Schema cuts them) or, with bytes,
-- limit bytes (templates and conditions).
local function CheckText(value, path, limit, bytes)
    if type(value) ~= "string" or (bytes and #value or PS.Format.Length(value)) > limit then
        Reject(path, string.format("must be text of at most %d %s", limit, bytes and "bytes" or "characters"))
    end
    return value
end

-- parent: the hierarchy (layoutVersion 2); attach: pinned to a parent's edge (3). anchor, group
-- and Level's followName: older Blueprints, converted on import.
local componentFields = Set("x", "y", "visible", "scale", "followName", "parent", "anchor", "group", "name", "order",
    "removed", "stack", "gap", "free", "layer", "attach")

local function CheckLayout(value, path)
    CheckObject(value, path)
    local layout, count = {}, 0
    for key, position in pairs(value) do
        local componentPath = path .. "." .. tostring(key)
        if not S.PartKey(key) then Reject(componentPath, "is not a component name") end
        count = count + 1
        if count > MAX_COMPONENTS then Reject(path, "has too many components") end
        CheckObject(position, componentPath, componentFields)
        layout[key] = {
            x = CheckRange(position.x, componentPath .. ".x", S.layoutRanges.x),
            y = CheckRange(position.y, componentPath .. ".y", S.layoutRanges.y),
            visible = position.visible == nil or CheckBoolean(position.visible, componentPath .. ".visible"),
            scale = position.scale == nil and 1 or CheckRange(position.scale, componentPath .. ".scale", S.layoutRanges.scale),
        }
        if position.followName ~= nil then
            if key ~= "level" then Reject(componentPath .. ".followName", "only applies to level") end
            layout[key].followName = CheckBoolean(position.followName, componentPath .. ".followName")
        end
        if position.anchor ~= nil then
            if not (S.componentAnchors[key] and S.componentAnchors[key][position.anchor]) then
                Reject(componentPath .. ".anchor", "is not a component this one can anchor to")
            end
            layout[key].anchor = position.anchor
        end
        -- Groups: a group's name and order; a member's group and its order in it.
        if S.IsGroupKey(key) then
            CheckText(position.name, componentPath .. ".name", S.GROUP_NAME_LENGTH)
            layout[key].name = S.NormalizeGroupName(position.name) or "Group"
            layout[key].order = CheckRange(position.order or 0, componentPath .. ".order", { 0, 99, true })
        else
            if position.name ~= nil then
                layout[key].name = S.NormalizeGroupName(CheckText(position.name, componentPath .. ".name", S.GROUP_NAME_LENGTH))
            end
            if position.order ~= nil then
                layout[key].order = CheckRange(position.order, componentPath .. ".order", { 0, 99, true })
            end
        end
        if position.group ~= nil then
            if not S.IsGroupKey(position.group) or S.IsGroupKey(key) then
                Reject(componentPath .. ".group", "is not a group")
            end
            layout[key].group = position.group
        end
        if position.stack ~= nil then
            if not S.STACK_DIRECTIONS[position.stack] then Reject(componentPath .. ".stack", "is not down, up, right or left") end
            layout[key].stack = position.stack
            layout[key].gap = position.gap == nil and 0 or CheckRange(position.gap, componentPath .. ".gap", S.STACK_GAP)
        end
        if position.free ~= nil then layout[key].free = CheckBoolean(position.free, componentPath .. ".free") or nil end
        if position.layer ~= nil then layout[key].layer = CheckRange(position.layer, componentPath .. ".layer", S.LAYER_RANGE) end
        if position.attach ~= nil then
            if not S.ATTACH_EDGES[position.attach] then
                Reject(componentPath .. ".attach", "must be left, right, top or bottom")
            end
            layout[key].attach = position.attach
        end
        if position.removed ~= nil then
            if S.IsGroupKey(key) or key:match("^value%d+$") then Reject(componentPath .. ".removed", "only applies to parts") end
            layout[key].removed = CheckBoolean(position.removed, componentPath .. ".removed") or nil
        end
        if position.parent ~= nil then
            if type(position.parent) ~= "string" or position.parent == key then
                Reject(componentPath .. ".parent", "is not another component")
            end
            layout[key].parent = position.parent
        end
    end
    for key, position in pairs(layout) do
        if position.group and not layout[position.group] then Reject(path .. "." .. key .. ".group", "names a missing group") end
        if position.parent and not layout[position.parent] then
            Reject(path .. "." .. key .. ".parent", "names a missing component")
        end
    end
    return layout
end

local slotFields = Set("source", "anchor", "layer", "whenMissing", "fontSize", "colour", "name", "template", "kind",
    "width", "height", "icon")

local function CheckValueName(value, path)
    if value == nil then return nil end
    return S.NormalizeValueName(CheckText(value, path, S.VALUE_NAME_LENGTH))
end

local function CheckTemplate(value, path)
    if value == nil then return nil end
    return S.NormalizeValueTemplate(CheckText(value, path, S.TEMPLATE_LENGTH, true))
end

local function CheckValueSlots(value, path)
    local allowed = {}
    for index = 1, VALUE_SLOT_COUNT do allowed["value" .. index] = true end
    CheckObject(value, path, allowed)
    local slots = {}
    for key, slot in pairs(value) do
        local slotPath = path .. "." .. key
        CheckObject(slot, slotPath, slotFields)
        slots[key] = {
            source = CheckEnum(slot.source, slotPath .. ".source", S.valueSources),
            anchor = CheckEnum(slot.anchor, slotPath .. ".anchor", S.valueAnchors),
            layer = slot.layer == nil and "front" or CheckEnum(slot.layer, slotPath .. ".layer", S.valueLayers),
            whenMissing = slot.whenMissing == nil and "fallback"
                or CheckEnum(slot.whenMissing, slotPath .. ".whenMissing", S.missingAnchorModes),
            fontSize = CheckRange(slot.fontSize, slotPath .. ".fontSize", S.valueFontRange),
            colour = CheckColour(slot.colour, slotPath .. ".colour"),
            name = CheckValueName(slot.name, slotPath .. ".name"),
            kind = slot.kind ~= nil and CheckEnum(slot.kind, slotPath .. ".kind", S.valueKinds) or nil,
            width = slot.width ~= nil and CheckRange(slot.width, slotPath .. ".width", S.VALUE_WIDTH) or nil,
            height = slot.height ~= nil and CheckRange(slot.height, slotPath .. ".height", S.VALUE_HEIGHT) or nil,
            icon = slot.icon ~= nil and CheckEnum(slot.icon, slotPath .. ".icon", S.valueIcons) or nil,
            template = CheckTemplate(slot.template, slotPath .. ".template"),
        }
    end
    return slots
end

local profileFields = Set("scale", "width", "healthHeight", "powerHeight", "powerWidth", "castWidth", "castHeight",
    "castIcon", "castTime", "castName", "castInterruptColours", "castOnTop", "castColours", "layoutVersion",
    "questProgress", "questProgressFormat",
    "nameFontSize", "healthTexture",
    "healthColourMode", "healthColour", "layout", "namesLayout", "dungeonNamesLayout", "valueSlots", "auraLayouts",
    "rules", "styles")
local castColourFields = Set("ready", "cooldown", "locked")
local auraLayoutFields = Set("count", "columns", "size", "spacing", "growX", "growY", "showDuration")

-- Each aura row's layout: every field optional, each checked against its range or choices.
local function CheckAuraLayouts(value, path, target)
    CheckObject(value, path, Set("buffs", "debuffs"))
    for kind, layout in pairs(value) do
        local rowPath = path .. "." .. kind
        CheckObject(layout, rowPath, auraLayoutFields)
        for key, range in pairs(S.auraLayoutRanges) do
            if layout[key] ~= nil then target[kind][key] = CheckRange(layout[key], rowPath .. "." .. key, range) end
        end
        if layout.growX ~= nil then target[kind].growX = CheckEnum(layout.growX, rowPath .. ".growX", S.auraGrowX) end
        if layout.growY ~= nil then target[kind].growY = CheckEnum(layout.growY, rowPath .. ".growY", S.auraGrowY) end
        if layout.showDuration ~= nil then
            target[kind].showDuration = CheckBoolean(layout.showDuration, rowPath .. ".showDuration")
        end
    end
end

-- Overlays a validated document profile onto target, a fully normalized profile.
local function ApplyProfile(target, value, path, allowNames)
    CheckObject(value, path, profileFields)
    for key, range in pairs(profileNumbers) do
        if value[key] ~= nil then target[key] = CheckRange(value[key], path .. "." .. key, range) end
    end
    -- A bar's own sizes; absent follows the health bar.
    for key, range in pairs(S.optionalProfileRanges) do
        target[key] = value[key] ~= nil and CheckRange(value[key], path .. "." .. key, range) or nil
    end
    -- The cast bar's icon side and its time and name switches, and the quest mark's progress;
    -- absent keeps the default.
    for key, choices in pairs(S.castOptions) do
        if value[key] ~= nil then
            if choices == "boolean" then target[key] = CheckBoolean(value[key], path .. "." .. key)
            else target[key] = CheckEnum(value[key], path .. "." .. key, choices) end
        end
    end
    if value.healthTexture ~= nil then
        if not PS.Media.IsStatusBar(value.healthTexture) then Reject(path .. ".healthTexture", "has an unsupported value") end
        target.healthTexture = value.healthTexture
    end
    if value.healthColourMode ~= nil then
        target.healthColourMode = CheckEnum(value.healthColourMode, path .. ".healthColourMode", healthColourModes)
    end
    if value.healthColour ~= nil then target.healthColour = CheckColour(value.healthColour, path .. ".healthColour") end
    -- Colour by interrupt's colours: any of ready, cooldown and locked; absent keeps the default.
    if value.castColours ~= nil then
        CheckObject(value.castColours, path .. ".castColours", castColourFields)
        local colours = Table.DeepCopy(target.castColours)
        for key, colour in pairs(value.castColours) do
            colours[key] = CheckColour(colour, path .. ".castColours." .. key)
        end
        target.castColours = colours
    end
    for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
        if value[field] ~= nil then
            if field ~= "layout" and not allowNames then Reject(path .. "." .. field, "is not used by this profile") end
            local checked = CheckLayout(value[field], path .. "." .. field)
            if value.layoutVersion == nil then
                -- From before the hierarchy: groups and anchors become parents (nothing moves),
                -- and one from before groups (none at all) takes the default template's.
                S.UpgradeLayoutToHierarchy(checked, value.valueSlots)
                local grouped = false
                for key in pairs(checked) do grouped = grouped or S.IsGroupKey(key) end
                if not grouped then S.AddDefaultGroups(checked) end
            end
            if (value.layoutVersion or 1) < 3 then
                -- From before Dynamic placement: Level pinned to the name, values under their bar.
                if checked.level and checked.level.followName == nil then checked.level.followName = true end
                S.UpgradeLayoutPlacement(checked, field, value.valueSlots)
            end
            target[field] = NormalizeLayout(checked, target[field])
        end
    end
    if value.valueSlots ~= nil then
        local slots = CheckValueSlots(value.valueSlots, path .. ".valueSlots")
        for key, slot in pairs(slots) do target.valueSlots[key] = slot end
    end
    if value.auraLayouts ~= nil then CheckAuraLayouts(value.auraLayouts, path .. ".auraLayouts", target.auraLayouts) end
    if value.rules ~= nil then
        -- Rules: part -> ordered list of { when, set, colour (hex) | alpha | stops[, enabled] }. A blend's
        -- condition may be empty (always); its stops are { at (0-100), colour (hex) }.
        CheckObject(value.rules, path .. ".rules")
        local rules = {}
        for key, list in pairs(value.rules) do
            local listPath = path .. ".rules." .. tostring(key)
            if not S.PartKey(key) then Reject(listPath, "is not a part name") end
            if type(list) ~= "table" or not Json.IsArray(list) then Reject(listPath, "must be a list") end
            if #list > S.MAX_RULES_PER_PART then Reject(listPath, "has more than " .. S.MAX_RULES_PER_PART .. " rules") end
            rules[key] = {}
            for index, rule in ipairs(list) do
                local rulePath = listPath .. "[" .. index .. "]"
                CheckObject(rule, rulePath, Set("when", "set", "colour", "alpha", "stops", "enabled"))
                CheckText(rule.when, rulePath .. ".when", S.TEMPLATE_LENGTH, true)
                local entry = { when = rule.when, set = CheckEnum(rule.set, rulePath .. ".set", S.RULE_SETS) }
                if rule.enabled ~= nil and not CheckBoolean(rule.enabled, rulePath .. ".enabled") then entry.enabled = false end
                if rule.when ~= "" then
                    local compiled, reason = PS.Template.CompileCondition(rule.when)
                    if not compiled then Reject(rulePath .. ".when", "is not a condition: " .. tostring(reason)) end
                end
                if entry.set == "colour" and rule.colour == nil then Reject(rulePath .. ".colour", "is needed to set colour") end
                if rule.colour ~= nil then entry.colour = CheckColour(rule.colour, rulePath .. ".colour") end
                if rule.alpha ~= nil then entry.alpha = CheckRange(rule.alpha, rulePath .. ".alpha", { 0, 1 }) end
                if entry.set == "blend" or rule.stops ~= nil then
                    local stops = rule.stops
                    if type(stops) ~= "table" or not Json.IsArray(stops) or #stops < S.MIN_BLEND_STOPS
                        or #stops > S.MAX_BLEND_STOPS then
                        Reject(rulePath .. ".stops", string.format("must be a list of %d to %d stops",
                            S.MIN_BLEND_STOPS, S.MAX_BLEND_STOPS))
                    end
                    entry.stops = {}
                    for stopIndex, stop in ipairs(stops) do
                        local stopPath = rulePath .. ".stops[" .. stopIndex .. "]"
                        CheckObject(stop, stopPath, Set("at", "colour"))
                        entry.stops[stopIndex] = { at = CheckRange(stop.at, stopPath .. ".at", { 0, 100, true }),
                            colour = CheckColour(stop.colour, stopPath .. ".colour") }
                    end
                end
                rules[key][index] = entry
            end
        end
        target.rules = S.NormalizeRules(rules)
    end
    if value.styles ~= nil then
        -- Styles: part -> { font, outline, shadow, box, boxColour, boxBorder, padding, texture,
        -- background, border, borderColour, pipFill, pipEmpty, pipWidth, pipHeight, pipSpacing,
        -- badgeSize, badgeSpacing, badgeOrientation, badgeInitial }; colours are { r, g, b, a } from 0 to 1. An older
        -- Blueprint's gradient (low, mid, high) becomes the part's leading blend rule.
        CheckObject(value.styles, path .. ".styles")
        local fields = Set("font", "outline", "shadow", "box", "boxColour", "boxBorder", "padding", "texture",
            "background", "border", "borderColour", "gradient", "pipFill", "pipEmpty", "pipWidth", "pipHeight", "pipSpacing",
            "badgeSize", "badgeSpacing", "badgeOrientation", "badgeInitial")
        local function CheckUnitColour(colour, colourPath)
            CheckObject(colour, colourPath, Set("r", "g", "b", "a"))
            for _, channel in ipairs({ "r", "g", "b", "a" }) do
                if colour[channel] ~= nil then CheckRange(colour[channel], colourPath .. "." .. channel, { 0, 1 }) end
            end
        end
        for key, style in pairs(value.styles) do
            local stylePath = path .. ".styles." .. tostring(key)
            if not S.PartKey(key) then Reject(stylePath, "is not a part name") end
            CheckObject(style, stylePath, fields)
            for _, field in ipairs({ "boxColour", "boxBorder", "background", "borderColour", "pipFill", "pipEmpty" }) do
                if style[field] ~= nil then CheckUnitColour(style[field], stylePath .. "." .. field) end
            end
            for field, range in pairs(S.STYLE_PIPS) do
                if style[field] ~= nil then CheckRange(style[field], stylePath .. "." .. field, range) end
            end
            for field, range in pairs(S.STYLE_BADGES) do
                if style[field] ~= nil then CheckRange(style[field], stylePath .. "." .. field, range) end
            end
            if style.badgeOrientation ~= nil then
                CheckEnum(style.badgeOrientation, stylePath .. ".badgeOrientation", S.STYLE_BADGE_ORIENTATIONS)
            end
            if style.badgeInitial ~= nil then CheckBoolean(style.badgeInitial, stylePath .. ".badgeInitial") end
            if style.font ~= nil and not PS.Media.IsFont(style.font) then Reject(stylePath .. ".font", "has an unsupported value") end
            if style.texture ~= nil and not PS.Media.IsStatusBar(style.texture) then
                Reject(stylePath .. ".texture", "has an unsupported value")
            end
            if style.shadow ~= nil then CheckBoolean(style.shadow, stylePath .. ".shadow") end
            if style.box ~= nil then CheckBoolean(style.box, stylePath .. ".box") end
            if style.outline ~= nil then CheckEnum(style.outline, stylePath .. ".outline", S.STYLE_OUTLINES) end
            if style.padding ~= nil then CheckRange(style.padding, stylePath .. ".padding", S.STYLE_PADDING) end
            if style.border ~= nil then CheckRange(style.border, stylePath .. ".border", S.STYLE_BORDER) end
            if style.gradient ~= nil then
                CheckObject(style.gradient, stylePath .. ".gradient", Set("low", "mid", "high"))
                for _, stop in ipairs({ "low", "mid", "high" }) do
                    if style.gradient[stop] ~= nil then CheckUnitColour(style.gradient[stop], stylePath .. ".gradient." .. stop) end
                end
            end
        end
        target.rules = S.NormalizeRules(S.GradientRules(target.rules, value.styles))
        target.styles = S.NormalizeStyles(value.styles)
    end
end

local flavors = Set("forever", "retail")
local documentFields = Set("format", "version", "addon", "client", "flavor", "settings", "profiles", "dungeonEnemy", "modules")
-- Font choices: a built-in key or an "lsm:" reference (PS.Media.IsFont).
local fontSettings = { "font", "blizzardNameFontFace" }
local settingFields = Set("relationshipColours", "stylePresets")
for _, key in ipairs(fontSettings) do settingFields[key] = true end
for _, key in ipairs(booleanSettings) do settingFields[key] = true end
for key in pairs(enumSettings) do settingFields[key] = true end
for key in pairs(settingRanges) do settingFields[key] = true end
-- Codes from before Show on plates followed the eyes carry its switches; one that is off turns
-- its parts' eyes off in the code's layouts (Schema's ApplyLegacySwitches).
for _, switch in ipairs(S.PART_SWITCHES) do settingFields[switch.key] = true end

-- Returns a complete, normalized settings table built from defaults plus the document.
local function BuildCandidate(document)
    CheckObject(document, "blueprint", documentFields)
    if document.format ~= FORMAT then Reject("format", "is not a PlateSmith Blueprint") end
    if not READABLE_VERSIONS[document.version] then Reject("version", "is not supported by this PlateSmith version") end
    if document.flavor ~= nil then CheckEnum(document.flavor, "flavor", flavors) end

    local candidate = NormalizeSettings({})
    local settings = document.settings == nil and {} or CheckObject(document.settings, "settings", settingFields)
    for _, key in ipairs(booleanSettings) do
        if settings[key] ~= nil then candidate[key] = CheckBoolean(settings[key], "settings." .. key) end
    end
    for key, allowed in pairs(enumSettings) do
        if settings[key] ~= nil then candidate[key] = CheckEnum(settings[key], "settings." .. key, allowed) end
    end
    for key, range in pairs(settingRanges) do
        if settings[key] ~= nil then candidate[key] = CheckRange(settings[key], "settings." .. key, range) end
    end
    for _, key in ipairs(fontSettings) do
        if settings[key] ~= nil then
            if not PS.Media.IsFont(settings[key]) then Reject("settings." .. key, "has an unsupported value") end
            candidate[key] = settings[key]
        end
    end
    if settings.stylePresets ~= nil then
        -- Saved styles: name -> { kind, style, rules }; the style and rules are checked as a part's.
        CheckObject(settings.stylePresets, "settings.stylePresets")
        for name, preset in pairs(settings.stylePresets) do
            local presetPath = "settings.stylePresets." .. tostring(name)
            CheckObject(preset, presetPath, Set("kind", "style", "rules"))
            CheckEnum(preset.kind, presetPath .. ".kind", S.PRESET_KINDS)
            if preset.style ~= nil then CheckObject(preset.style, presetPath .. ".style") end
            if preset.rules ~= nil and (type(preset.rules) ~= "table" or not Json.IsArray(preset.rules)) then
                Reject(presetPath .. ".rules", "must be a list")
            end
        end
        candidate.stylePresets = S.NormalizeStylePresets(settings.stylePresets)
    end
    if settings.relationshipColours ~= nil then
        CheckObject(settings.relationshipColours, "settings.relationshipColours", defaultRelationshipColours)
        for key, value in pairs(settings.relationshipColours) do
            candidate.relationshipColours[key] = CheckColour(value, "settings.relationshipColours." .. key)
        end
    end

    local profiles = document.profiles == nil and {}
        or CheckObject(document.profiles, "profiles", SetOf(profileOrder))
    for _, key in ipairs(profileOrder) do
        if profiles[key] ~= nil then
            ApplyProfile(candidate.plateProfiles[key], profiles[key], "profiles." .. key,
                profileDefaults[key].namesLayout ~= nil)
        end
    end
    if document.dungeonEnemy ~= nil then
        local dungeon = CopyEnemyProfile(candidate.plateProfiles.enemy)
        ApplyProfile(dungeon, document.dungeonEnemy, "dungeonEnemy", false)
        candidate.plateProfiles.enemyDungeon = dungeon
    end
    local legacy = {}
    for _, switch in ipairs(S.PART_SWITCHES) do
        if settings[switch.key] ~= nil then legacy[switch.key] = CheckBoolean(settings[switch.key], "settings." .. switch.key) end
    end
    -- The tank's warning border ran under the old threat switch.
    if legacy.threat == false and settings.tankWarning == nil then candidate.tankWarning = false end
    -- A code whose threat switch was off also turns off its threat rules (the count is returned).
    local disabled = S.ApplyLegacySwitches(candidate, legacy)
    return NormalizeSettings(candidate), disabled
end

-- Unused custom parts (off, and everything else at its default) are left out: an import fills
-- them from the defaults.
local function DefaultSlot(slot)
    local base, colour = S.DEFAULT_VALUE_SLOT, slot.colour or {}
    return slot.source == base.source and slot.layer == base.layer and slot.fontSize == base.fontSize and not slot.name
        and not slot.template and not slot.kind and not slot.width and not slot.height and not slot.icon
        and colour.r == base.colour.r and colour.g == base.colour.g and colour.b == base.colour.b
        and (slot.anchor == base.anchor or slot.anchor == nil)
        and (slot.whenMissing == base.whenMissing or slot.whenMissing == nil)
end

local function ExportLayout(layout, slots)
    local result = {}
    -- An unused part another entry sits under stays in: an import checks every parent exists.
    local parents = {}
    for _, position in pairs(layout or {}) do
        if type(position) == "table" and position.parent then parents[position.parent] = true end
    end
    for key, position in pairs(layout or {}) do
        local slot = slots and key:match("^value%d+$") and slots[key]
        if not (slot and DefaultSlot(slot) and not parents[key]) then
            result[key] = { x = position.x, y = position.y, visible = position.visible ~= false, scale = position.scale or 1 }
            if position.parent then result[key].parent = position.parent end
            if position.attach then result[key].attach = position.attach end
            if position.removed then result[key].removed = true end
            if position.stack then result[key].stack, result[key].gap = position.stack, position.gap end
            if position.free then result[key].free = true end
            if position.layer then result[key].layer = position.layer end
            if position.name then result[key].name = position.name end
            if position.order then result[key].order = position.order end
        end
    end
    return result
end

local function ExportProfile(profile, includeNames)
    local result = {
        scale = profile.scale, width = profile.width, healthHeight = profile.healthHeight,
        powerHeight = profile.powerHeight, nameFontSize = profile.nameFontSize,
        powerWidth = profile.powerWidth, castWidth = profile.castWidth, castHeight = profile.castHeight,
        castIcon = profile.castIcon, castTime = profile.castTime, castName = profile.castName,
        castInterruptColours = profile.castInterruptColours, castOnTop = profile.castOnTop,
        questProgress = profile.questProgress, questProgressFormat = profile.questProgressFormat,
        healthTexture = profile.healthTexture, healthColourMode = profile.healthColourMode,
        healthColour = ColourToHex(profile.healthColour),
        layoutVersion = S.LAYOUT_VERSION,
        layout = ExportLayout(profile.layout, profile.valueSlots),
        valueSlots = {},
        auraLayouts = {},
    }
    if profile.castColours then
        result.castColours = {}
        for _, key in ipairs(S.CAST_COLOUR_KEYS) do
            if profile.castColours[key] then result.castColours[key] = ColourToHex(profile.castColours[key]) end
        end
    end
    result.styles = profile.styles and next(profile.styles) and Table.DeepCopy(profile.styles) or nil
    result.rules = {}
    -- A rule still being typed (its condition does not compile yet) stays in Studio but is not
    -- shared: an import rejects such conditions. An empty condition (always) is shared.
    for key, list in pairs(profile.rules or {}) do
        local shared = {}
        for _, rule in ipairs(list) do
            if rule.when == "" or (PS.Template and PS.Template.CompileCondition(rule.when)) then shared[#shared + 1] = rule end
        end
        result.rules[key] = #shared > 0 and {} or nil
        for index, rule in ipairs(shared) do
            local stops
            for stopIndex, stop in ipairs(rule.stops or {}) do
                stops = stops or {}
                stops[stopIndex] = { at = stop.at, colour = ColourToHex(stop.colour) }
            end
            result.rules[key][index] = { when = rule.when, set = rule.set, alpha = rule.alpha,
                colour = rule.colour and ColourToHex(rule.colour) or nil, stops = stops }
            -- Only a rule turned off says so (false must survive, so not an and/or).
            if rule.enabled == false then result.rules[key][index].enabled = false end
        end
    end
    for kind, layout in pairs(profile.auraLayouts or {}) do
        result.auraLayouts[kind] = { count = layout.count, columns = layout.columns, size = layout.size,
            spacing = layout.spacing, growX = layout.growX, growY = layout.growY, showDuration = layout.showDuration }
    end
    if includeNames then
        result.namesLayout = ExportLayout(profile.namesLayout, profile.valueSlots)
        result.dungeonNamesLayout = ExportLayout(profile.dungeonNamesLayout, profile.valueSlots)
    end
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = profile.valueSlots[key]
        if not DefaultSlot(slot) then
            result.valueSlots[key] = { source = slot.source, anchor = slot.anchor, layer = slot.layer,
                whenMissing = slot.whenMissing, fontSize = slot.fontSize, colour = ColourToHex(slot.colour),
                name = slot.name, template = slot.template, kind = slot.kind, width = slot.width, height = slot.height,
                icon = slot.icon }
        end
    end
    return result
end

local function IsJsonValue(value, depth)
    local kind = type(value)
    if kind == "string" or kind == "boolean" then return true end
    if kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
    if kind ~= "table" or depth > 8 then return false end
    for key, child in pairs(value) do
        if type(key) ~= "string" and not Json.IsArray(value) then return false end
        if not IsJsonValue(child, depth + 1) then return false end
    end
    return true
end

local function RegisterBlueprintField(key, descriptor)
    if type(key) ~= "string" or #key > 64 or not key:match("^[a-z][a-z0-9_]*%.[a-z][a-z0-9_]*$") then
        return false, "extension fields must use module.field names"
    end
    if moduleFields[key] then return false, "blueprint field is already registered" end
    if type(descriptor) ~= "table" or type(descriptor.export) ~= "function"
        or type(descriptor.parse) ~= "function" or type(descriptor.apply) ~= "function" then
        return false, "extension field requires export, parse, and apply functions"
    end
    moduleFields[key] = descriptor
    return true
end

local function SortedModuleKeys()
    local keys = {}
    for key in pairs(moduleFields) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- db: a complete settings table. live: also carry the account's saved styles and module data,
-- as an export does; a built-in profile preset (Core/ProfilePresets.lua) carries neither.
local function BuildDocument(db, live)
    if not db then return nil, "settings are not loaded" end
    local settings = { relationshipColours = {} }
    for _, key in ipairs(booleanSettings) do settings[key] = db[key] end
    for key in pairs(enumSettings) do settings[key] = db[key] end
    for key in pairs(settingRanges) do settings[key] = db[key] end
    for _, key in ipairs(fontSettings) do settings[key] = db[key] end
    local presets = live and PS.GetState and PS.GetState().stylePresets
    settings.stylePresets = presets and next(presets) and Table.DeepCopy(presets) or nil
    for key in pairs(defaultRelationshipColours) do
        settings.relationshipColours[key] = ColourToHex(db.relationshipColours[key])
    end
    local profiles = {}
    for _, key in ipairs(profileOrder) do
        profiles[key] = ExportProfile(db.plateProfiles[key], profileDefaults[key].namesLayout ~= nil)
    end
    local build = type(GetBuildInfo) == "function" and select(4, GetBuildInfo()) or nil
    local document = {
        format = FORMAT, version = VERSION,
        addon = tostring(PS.RUNTIME_BUILD or "unknown"),
        client = type(build) == "number" and build or nil,
        flavor = PS.ClientFlavor(),
        settings = settings, profiles = profiles,
        dungeonEnemy = db.plateProfiles.enemyDungeon and ExportProfile(db.plateProfiles.enemyDungeon, false) or nil,
    }
    for _, key in ipairs(live and SortedModuleKeys() or {}) do
        local ok, value = pcall(moduleFields[key].export)
        if not ok then return nil, "module export failed: " .. key end
        if value ~= nil then
            if not IsJsonValue(value, 0) then return nil, "module exported a value JSON cannot hold: " .. key end
            document.modules = document.modules or {}
            document.modules[key] = value
        end
    end
    return document
end

local function ExportBlueprint(pretty)
    local document, reason = BuildDocument(PS.GetSettings and PS.GetSettings(), true)
    if not document then return nil, reason end
    local text = Json.Encode(document, pretty)
    if #text > MAX_JSON_BYTES then return nil, "blueprint is too large" end
    return text
end

local function ImportBlueprint(text, selection)
    local db = PS.GetSettings and PS.GetSettings()
    if not db then return false, "settings are not loaded" end
    if type(text) ~= "string" then return false, "blueprint must be text" end
    -- Only a table opts into selective import; callers may pass through a gsub count.
    if type(selection) ~= "table" then selection = nil end
    local function Selected(section) return not selection or selection[section] == true end
    local any = false
    for _, section in ipairs(sections) do
        if Selected(section) then any = true break end
    end
    if not any then return false, "select at least one section" end

    local document, parseError = Json.Decode(text, MAX_JSON_BYTES)
    if document == nil then return false, "invalid JSON: " .. tostring(parseError) end

    local modules, disabledRules = {}, 0
    local built, candidate = pcall(function()
        local result
        result, disabledRules = BuildCandidate(document)
        if document.modules ~= nil then
            CheckObject(document.modules, "modules")
            -- Data for companion addons that are not installed here is skipped.
            for key, value in pairs(document.modules) do
                local descriptor = moduleFields[key]
                if descriptor then
                    local ok, parsed, reason = pcall(descriptor.parse, value)
                    if not ok or parsed == nil then Reject("modules." .. key, tostring(reason or "is invalid")) end
                    modules[key] = parsed
                end
            end
        end
        return result
    end)
    if not built then
        if type(candidate) == "table" and candidate.blueprintError then return false, candidate.blueprintError end
        return false, "invalid blueprint: " .. tostring(candidate)
    end

    local function ApplySelected()
        local profiles = db.plateProfiles
        if Selected("settings") then
            for _, key in ipairs(booleanSettings) do db[key] = candidate[key] end
            for key in pairs(enumSettings) do db[key] = candidate[key] end
            for key in pairs(settingRanges) do db[key] = candidate[key] end
            for _, key in ipairs(fontSettings) do db[key] = candidate[key] end
            db.relationshipColours = candidate.relationshipColours
        end
        for _, key in ipairs(profileOrder) do
            local source, target = candidate.plateProfiles[key], profiles[key]
            if Selected("styles") then
                for _, field in ipairs(styleFields) do target[field] = source[field] end
            end
            if Selected("layouts") then
                target.layout = source.layout
                target.namesLayout = source.namesLayout
                target.auraLayouts = source.auraLayouts
            end
            if Selected("dungeonFriendly") then target.dungeonNamesLayout = source.dungeonNamesLayout end
            if Selected("values") then
                target.valueSlots = source.valueSlots
                target.powerHeight = source.powerHeight
            end
        end
        if Selected("dungeon") then profiles.enemyDungeon = candidate.plateProfiles.enemyDungeon end
        if Selected("other") then
            for _, key in ipairs(SortedModuleKeys()) do
                if modules[key] ~= nil then
                    local ok, applied = pcall(moduleFields[key].apply, modules[key])
                    if not ok or applied == false then return false, "module apply failed: " .. key end
                end
            end
        end
        NormalizeSettings(db)
        return true
    end

    -- Module apply callbacks write live state, so any failure restores the
    -- whole pre-import settings rather than leaving a partial Blueprint.
    local snapshot = Table.DeepCopy(db)
    local completed, applied, failure = pcall(ApplySelected)
    if not completed or not applied then
        -- Other modules hold the live settings table, so it is restored in place.
        Table.Replace(db, snapshot)
        PS.Refresh()
        return false, completed and failure or ("blueprint apply failed: " .. tostring(applied))
    end
    -- Presets are account state (saved at once, outside the snapshot), so they join only after
    -- everything else applied. Same names are replaced, up to the limit: yours are never pushed out.
    local state = Selected("settings") and PS.GetState and PS.GetState()
    if state then
        state.stylePresets = state.stylePresets or {}
        local count = 0
        for _ in pairs(state.stylePresets) do count = count + 1 end
        for name, preset in pairs(candidate.stylePresets or {}) do
            if state.stylePresets[name] or count < S.MAX_PRESETS then
                if not state.stylePresets[name] then count = count + 1 end
                state.stylePresets[name] = preset
            end
        end
        -- The friendly-name settings are applied through CVars.
        if PS.NamePolicy and PS.NamePolicy.Apply then PS.NamePolicy.Apply() end
    end
    PS.Refresh()
    if disabledRules > 0 and (Selected("styles") or Selected("dungeon")) and PS.Profiles then
        PS.Profiles.NoteMigration(PS.Profiles.Active(), { threatRulesDisabled = disabledRules })
    end
    -- Imports across clients succeed; the third result names the other client
    -- so the caller can say some options may behave differently here.
    if document.flavor ~= nil and document.flavor ~= PS.ClientFlavor() then return true, nil, document.flavor end
    return true
end

PS.BlueprintSections = sections
PS.MAX_BLUEPRINT_BYTES = MAX_JSON_BYTES
PS.RegisterBlueprintField = RegisterBlueprintField
PS.ExportBlueprint = ExportBlueprint
PS.BlueprintDocument = function(settings) return BuildDocument(settings, false) end
PS.ImportBlueprint = ImportBlueprint
