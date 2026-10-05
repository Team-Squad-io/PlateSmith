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

-- A Blueprint is a JSON document. Missing fields take their defaults. An unknown field (a newer
-- PlateSmith's) is skipped and named in the import's result, so the rest still imports; a known
-- field with a bad value is refused, and nothing changes.
local FORMAT = "platesmith-blueprint"
-- Version 3 carries custom parts (kinds), templates, rules, styles and Dynamic placement
-- (layoutVersion 3). Version 2 documents still import: their layouts are upgraded on the way in.
-- Version 4 adds context designs (contexts), the Enemy players layer (enemyPlayers) and everything new
-- since 1.1.1 (NEW_SETTINGS, NEW_SETTING_VALUES, NEW_STYLE_FIELDS, a design's own target highlight), and
-- says readableFrom = 3:
-- everything else in it is version 3, so a reader that skips what it does not know still reads it.
-- An export that uses nothing new is version 3, byte for byte what 1.1.1 wrote, so 1.1.1 (strict:
-- it refuses any field it does not know) imports it; 1.1.1 refuses every version 4 document. A later
-- version imports only when it says this one can still read it (readableFrom, one of
-- READABLE_VERSIONS); otherwise it is refused.
local VERSION = 4
local LEGACY_VERSION = 3
local READABLE_VERSIONS = { [2] = true, [3] = true, [4] = true }
local MAX_JSON_BYTES = 65536
local MAX_COMPONENTS = 64
local DESIGN = S.DESIGN
local CLEAR = DESIGN.CLEAR
local L = PS.L

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
-- PlateSmith runs is the player's own, not part of a design) and Where plates show, which, like
-- stacking, drives account-wide CVars. A document that has them (a 1.2.0 test build wrote them) is
-- read, and they are ignored.
local IGNORED_SETTINGS = Set("enabled")
for _, key in ipairs(S.VISIBILITY.KEYS) do IGNORED_SETTINGS[key] = true end
local booleanSettings, enumSettings = {}, {}
for _, key in ipairs(S.booleanSettings) do
    if not IGNORED_SETTINGS[key] then booleanSettings[#booleanSettings + 1] = key end
end
for key, allowed in pairs(S.enumSettings) do
    if not IGNORED_SETTINGS[key] then enumSettings[key] = allowed end
end
local settingRanges = S.settingRanges
local profileNumbers = S.profileRanges
local healthColourModes = Set("automatic", "custom")
local styleFields = { "scale", "width", "healthHeight", "nameFontSize", "healthTexture", "healthColourMode", "healthColour",
    "powerWidth", "castWidth", "castHeight", "castIcon", "castTime", "castName", "castInterruptColours", "castOnTop",
    "castColours", "questProgress", "questProgressFormat", "rules", "styles" }
-- A design's own target highlight (Schema's HIGHLIGHT): part of its look, imported with Styles. New since
-- 1.1.1, so a document with any is version 4; absent, the design follows the general settings.
local HIGHLIGHT = S.HIGHLIGHT
for _, key in ipairs(HIGHLIGHT.KEYS) do styleFields[#styleFields + 1] = key end
-- contexts: the context designs the Blueprint carries (CarriedDesigns), each replacing yours for
-- that plate type and context; your others stay. enemyPlayers: the Enemy players layer, replaced
-- whole. The old keys dungeon (the Enemies' Dungeons & raids design) and dungeonFriendly (the friendly
-- plates' Dungeons & raids names), which API callers may still pass, select just those designs.
local sections = { "settings", "layouts", "styles", "values", "contexts", "enemyPlayers", "other" }
local LEGACY_SECTIONS = { dungeon = "contexts", dungeonFriendly = "contexts" }
-- General settings new since 1.1.1, which its strict reader refuses: each is exported only away
-- from the value its absence imports as (its default; colourByThreat's is false, as a code from
-- before Threat colours brings them off), and then the export is version 4. The shared threat colours
-- (threatColours) likewise, and parts' own threat colours (threatPartColours) whenever there are any.
local NEW_SETTINGS = {}
for _, key in ipairs({ "namesOnlyCastText", "colourByThreat", "threatColourRole", "threatColourSafeKeep",
    "threatColourHealth", "threatColourName", "threatColourBorder", "targetGlowColourMode", "targetGlowColour",
    "targetGlowSpread", "targetGlowOpacity", "targetGlowPulse", "targetGlowOffsetX", "targetGlowOffsetY" }) do
    NEW_SETTINGS[key] = S.defaults[key]
end
NEW_SETTINGS.colourByThreat = false
-- Choices of older settings and part style fields new since 1.1.1, which its strict reader refuses: an
-- export using one (in a design or a saved style) is version 4. NEW_TEXTURES: bar textures new since
-- 1.1.1, as a design's texture (healthTexture) or a part's (style texture).
local NEW_SETTING_VALUES = { targetHighlightStyle = Set("glow"), targetGlowColourMode = Set("threat") }
local NEW_STYLE_FIELDS = Set("pipShape", "pipAnchor", "pipClassColour", "pipGlow", "pipFit", "pipShowRow", "boxShape")
-- The largest pip sizes 1.1.1 accepts (it refuses a larger one): a style past them is version 4.
local PIP_LIMITS_111 = { pipWidth = 24, pipHeight = 12, pipSpacing = 8 }
local NEW_TEXTURES = Set("modern")

local moduleFields = {}

local ColourToHex, HexToColour = PS.Format.ColourToHex, PS.Format.HexToColour

-- Validation raises { blueprintError = "path: reason" } so every check can stay one line.
local function Reject(path, reason) error({ blueprintError = path .. " " .. reason }, 0) end

-- The fields an import skipped: { count, paths } (at most MAX_SKIPPED_PATHS paths kept), set only
-- while an import checks its document; outside one an unknown field is refused.
local skipped
local MAX_SKIPPED_PATHS = 200

-- Records a field the import leaves out (outside an import: refused for reason).
local function Skip(fieldPath, reason)
    if not skipped then Reject(fieldPath, reason) end
    skipped.count = skipped.count + 1
    if #skipped.paths < MAX_SKIPPED_PATHS then skipped.paths[#skipped.paths + 1] = fieldPath end
end

-- An unknown key is dropped from the decoded document (the import's own copy), so nothing below
-- reads it.
local function CheckObject(value, path, allowed)
    if type(value) ~= "table" or Json.IsArray(value) then Reject(path, "must be an object") end
    if allowed then
        for key in pairs(value) do
            if not allowed[key] then
                Skip(path == "blueprint" and tostring(key) or path .. "." .. tostring(key), "is not a known field")
                value[key] = nil
            end
        end
    end
    return value
end

-- A sparse design's parts past the most it holds (DESIGN.MAX_ENTRIES, kept in sorted order as
-- NormalizeDesign keeps them) are skipped, and named.
local function SkipExtraParts(map, path)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    if #keys <= DESIGN.MAX_ENTRIES then return end
    table.sort(keys)
    for index = DESIGN.MAX_ENTRIES + 1, #keys do
        Skip(path .. "." .. keys[index], "has too many parts")
        map[keys[index]] = nil
    end
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

-- A layout entry's placement (x and y needed; scale, order, stack and gap, free, layer, attach and
-- parent when given), checked into entry. A whole layout's entries and a context design's
-- placement overrides share it; a parent is checked against the layout by the caller.
local function CheckPlacement(position, componentPath, key, entry)
    entry.x = CheckRange(position.x, componentPath .. ".x", S.layoutRanges.x)
    entry.y = CheckRange(position.y, componentPath .. ".y", S.layoutRanges.y)
    if position.scale ~= nil then entry.scale = CheckRange(position.scale, componentPath .. ".scale", S.layoutRanges.scale) end
    if position.order ~= nil then entry.order = CheckRange(position.order, componentPath .. ".order", { 0, 99, true }) end
    if position.stack ~= nil then
        if not S.STACK_DIRECTIONS[position.stack] then Reject(componentPath .. ".stack", "is not down, up, right or left") end
        entry.stack = position.stack
        entry.gap = position.gap == nil and 0 or CheckRange(position.gap, componentPath .. ".gap", S.STACK_GAP)
    end
    if position.free ~= nil then entry.free = CheckBoolean(position.free, componentPath .. ".free") or nil end
    if position.layer ~= nil then entry.layer = CheckRange(position.layer, componentPath .. ".layer", S.LAYER_RANGE) end
    if position.attach ~= nil then
        if not S.ATTACH_EDGES[position.attach] then
            Reject(componentPath .. ".attach", "must be left, right, top or bottom")
        end
        entry.attach = position.attach
    end
    if position.parent ~= nil then
        if type(position.parent) ~= "string" or position.parent == key then
            Reject(componentPath .. ".parent", "is not another component")
        end
        entry.parent = position.parent
    end
    return entry
end

local function CheckLayout(value, path)
    CheckObject(value, path)
    local layout, count = {}, 0
    for key, position in pairs(value) do
        local componentPath = path .. "." .. tostring(key)
        if not S.PartKey(key) then Reject(componentPath, "is not a component name") end
        count = count + 1
        if count > MAX_COMPONENTS then Reject(path, "has too many components") end
        CheckObject(position, componentPath, componentFields)
        layout[key] = CheckPlacement(position, componentPath, key, {
            visible = position.visible == nil or CheckBoolean(position.visible, componentPath .. ".visible"),
        })
        layout[key].scale = layout[key].scale or 1
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
            layout[key].order = layout[key].order or 0
        elseif position.name ~= nil then
            layout[key].name = S.NormalizeGroupName(CheckText(position.name, componentPath .. ".name", S.GROUP_NAME_LENGTH))
        end
        if position.group ~= nil then
            if not S.IsGroupKey(position.group) or S.IsGroupKey(key) then
                Reject(componentPath .. ".group", "is not a group")
            end
            layout[key].group = position.group
        end
        if position.removed ~= nil then
            if S.IsGroupKey(key) or key:match("^value%d+$") then Reject(componentPath .. ".removed", "only applies to parts") end
            layout[key].removed = CheckBoolean(position.removed, componentPath .. ".removed") or nil
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
for _, key in ipairs(HIGHLIGHT.KEYS) do profileFields[key] = true end
local castColourFields = Set("ready", "cooldown", "locked")

-- One target highlight value of a design (a profile or a sparse design's options), checked as the
-- general setting of that name is.
local function CheckHighlight(key, raw, keyPath)
    if key == "targetGlowPulse" then return CheckBoolean(raw, keyPath) end
    if S.enumSettings[key] then return CheckEnum(raw, keyPath, S.enumSettings[key]) end
    if settingRanges[key] then return CheckRange(raw, keyPath, settingRanges[key]) end
    return CheckColour(raw, keyPath)
end
local auraLayoutFields = Set("count", "columns", "size", "spacing", "growX", "growY", "showDuration", "timeSize", "timeFont",
    "timeOutline", "timeShadow", "timePosition", "timeFontSize", "timedOnly")

-- A context design's "-" list (the fields it clears): each one known and true.
local function CheckClear(value, path, allowed)
    CheckObject(value, path, allowed)
    local clear = {}
    for key, flag in pairs(value) do
        if flag ~= true then Reject(path .. "." .. key, "must be true") end
        clear[key] = true
    end
    return clear
end

local sparseAuraFields = Set(CLEAR)
for key in pairs(auraLayoutFields) do sparseAuraFields[key] = true end

-- Each aura row's layout: every field optional, each checked against its range or choices. A
-- context design's (sparse) rows may also list the fields they clear ("-").
local function CheckAuraLayouts(value, path, target, sparse)
    CheckObject(value, path, Set("buffs", "debuffs"))
    for kind, layout in pairs(value) do
        local rowPath = path .. "." .. kind
        CheckObject(layout, rowPath, sparse and sparseAuraFields or auraLayoutFields)
        if layout[CLEAR] ~= nil then target[kind][CLEAR] = CheckClear(layout[CLEAR], rowPath .. "." .. CLEAR, auraLayoutFields) end
        for key, range in pairs(S.auraLayoutRanges) do
            if layout[key] ~= nil then target[kind][key] = CheckRange(layout[key], rowPath .. "." .. key, range) end
        end
        if layout.growX ~= nil then target[kind].growX = CheckEnum(layout.growX, rowPath .. ".growX", S.auraGrowX) end
        if layout.growY ~= nil then target[kind].growY = CheckEnum(layout.growY, rowPath .. ".growY", S.auraGrowY) end
        if layout.showDuration ~= nil then
            target[kind].showDuration = CheckBoolean(layout.showDuration, rowPath .. ".showDuration")
        end
        -- The countdown's text: absent keeps the plate font, outline and the client's shadow.
        if layout.timeFont ~= nil then
            if not PS.Media.IsFont(layout.timeFont) then Reject(rowPath .. ".timeFont", "has an unsupported value") end
            target[kind].timeFont = layout.timeFont
        end
        if layout.timeOutline ~= nil then
            target[kind].timeOutline = CheckEnum(layout.timeOutline, rowPath .. ".timeOutline", S.STYLE_OUTLINES)
        end
        if layout.timeShadow ~= nil then target[kind].timeShadow = CheckBoolean(layout.timeShadow, rowPath .. ".timeShadow") end
        if layout.timeFontSize ~= nil then
            target[kind].timeFontSize = CheckRange(layout.timeFontSize, rowPath .. ".timeFontSize", S.STYLE_FONT_SIZE)
        end
        if layout.timePosition ~= nil then
            target[kind].timePosition = CheckEnum(layout.timePosition, rowPath .. ".timePosition", S.auraTimePositions)
        end
        -- Timed only; absent or false is off.
        if layout.timedOnly ~= nil then
            target[kind].timedOnly = CheckBoolean(layout.timedOnly, rowPath .. ".timedOnly") or nil
        end
    end
end

local ruleFields, stopFields = Set("when", "set", "colour", "alpha", "stops", "enabled"), Set("at", "colour")

-- Rules: part -> ordered list of { when, set, colour (hex) | alpha | stops[, enabled] }. A blend's
-- condition may be empty (always); its stops are { at (0-100), colour (hex) }. Returns them checked
-- (colours as tables), not yet normalised; an empty list stays an empty list.
local function CheckRules(value, path)
    CheckObject(value, path)
    local rules = {}
    for key, list in pairs(value) do
        local listPath = path .. "." .. tostring(key)
        if not S.PartKey(key) then Reject(listPath, "is not a part name") end
        if type(list) ~= "table" or not Json.IsArray(list) then Reject(listPath, "must be a list") end
        if #list > S.MAX_RULES_PER_PART then Reject(listPath, "has more than " .. S.MAX_RULES_PER_PART .. " rules") end
        rules[key] = {}
        for index, rule in ipairs(list) do
            local rulePath = listPath .. "[" .. index .. "]"
            CheckObject(rule, rulePath, ruleFields)
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
                    CheckObject(stop, stopPath, stopFields)
                    entry.stops[stopIndex] = { at = CheckRange(stop.at, stopPath .. ".at", { 0, 100, true }),
                        colour = CheckColour(stop.colour, stopPath .. ".colour") }
                end
            end
            rules[key][index] = entry
        end
    end
    return rules
end

-- Styles: part -> { font, fontSize, outline, shadow, box, boxShape, boxColour, boxBorder, padding, texture,
-- background, border, borderColour, pipFill, pipEmpty, pipWidth, pipHeight, pipSpacing, pipShape,
-- pipAnchor, pipClassColour, pipGlow, pipFit, pipShowRow, badgeSize, badgeSpacing, badgeOrientation, badgeInitial };
-- colours are { r, g, b, a } from 0 to 1. An older Blueprint's gradient (low, mid, high) becomes the
-- part's leading blend rule (profiles only). A context design's (sparse) style may list the fields it
-- clears ("-") and has no gradient.
local styleFieldList = { "font", "fontSize", "outline", "shadow", "box", "boxShape", "boxColour", "boxBorder", "padding",
    "texture",
    "background", "border", "borderColour", "pipFill", "pipEmpty", "pipWidth", "pipHeight", "pipSpacing",
    "pipShape", "pipAnchor", "pipClassColour", "pipGlow", "pipFit", "pipShowRow",
    "badgeSize", "badgeSpacing", "badgeOrientation", "badgeInitial" }
local profileStyleFields, sparseStyleFields = SetOf(styleFieldList), SetOf(styleFieldList)
profileStyleFields.gradient, sparseStyleFields[CLEAR] = true, true
local sparseStyleClear = SetOf(styleFieldList)

local function CheckUnitColour(colour, colourPath)
    CheckObject(colour, colourPath, Set("r", "g", "b", "a"))
    for _, channel in ipairs({ "r", "g", "b", "a" }) do
        if colour[channel] ~= nil then CheckRange(colour[channel], colourPath .. "." .. channel, { 0, 1 }) end
    end
end

local function CheckStyles(value, path, sparse)
    CheckObject(value, path)
    for key, style in pairs(value) do
        local stylePath = path .. "." .. tostring(key)
        if not S.PartKey(key) then Reject(stylePath, "is not a part name") end
        CheckObject(style, stylePath, sparse and sparseStyleFields or profileStyleFields)
        if style[CLEAR] ~= nil then style[CLEAR] = CheckClear(style[CLEAR], stylePath .. "." .. CLEAR, sparseStyleClear) end
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
        if style.pipShape ~= nil then CheckEnum(style.pipShape, stylePath .. ".pipShape", S.STYLE_PIP_SHAPES) end
        if style.pipAnchor ~= nil then CheckEnum(style.pipAnchor, stylePath .. ".pipAnchor", S.STYLE_PIP_ANCHORS) end
        if style.pipClassColour ~= nil then CheckBoolean(style.pipClassColour, stylePath .. ".pipClassColour") end
        if style.pipGlow ~= nil then CheckBoolean(style.pipGlow, stylePath .. ".pipGlow") end
        if style.pipFit ~= nil then CheckBoolean(style.pipFit, stylePath .. ".pipFit") end
        if style.pipShowRow ~= nil then CheckEnum(style.pipShowRow, stylePath .. ".pipShowRow", S.STYLE_PIP_SHOW_ROWS) end
        if style.font ~= nil and not PS.Media.IsFont(style.font) then Reject(stylePath .. ".font", "has an unsupported value") end
        if style.texture ~= nil and not PS.Media.IsStatusBar(style.texture) then
            Reject(stylePath .. ".texture", "has an unsupported value")
        end
        if style.shadow ~= nil then CheckBoolean(style.shadow, stylePath .. ".shadow") end
        if style.box ~= nil then CheckBoolean(style.box, stylePath .. ".box") end
        if style.boxShape ~= nil then CheckEnum(style.boxShape, stylePath .. ".boxShape", S.STYLE_BOX_SHAPES) end
        if style.outline ~= nil then CheckEnum(style.outline, stylePath .. ".outline", S.STYLE_OUTLINES) end
        if style.padding ~= nil then CheckRange(style.padding, stylePath .. ".padding", S.STYLE_PADDING) end
        if style.fontSize ~= nil then CheckRange(style.fontSize, stylePath .. ".fontSize", S.STYLE_FONT_SIZE) end
        if style.border ~= nil then CheckRange(style.border, stylePath .. ".border", S.STYLE_BORDER) end
        if style.gradient ~= nil then
            CheckObject(style.gradient, stylePath .. ".gradient", Set("low", "mid", "high"))
            for _, stop in ipairs({ "low", "mid", "high" }) do
                if style.gradient[stop] ~= nil then CheckUnitColour(style.gradient[stop], stylePath .. ".gradient." .. stop) end
            end
        end
    end
    return value
end

-- A context design's own profile options (Designs: options), each checked as a profile's is;
-- castOnNames (false: no cast bar on names-only plates there) and "-" (optional sizes cleared, so
-- they follow the health bar there) are a design's own.
local optionFields = Set("healthTexture", "healthColourMode", "healthColour", "castColours", "castOnNames", CLEAR)
for key in pairs(profileNumbers) do optionFields[key] = true end
for key in pairs(S.optionalProfileRanges) do optionFields[key] = true end
for key in pairs(S.castOptions) do optionFields[key] = true end
local clearableOptions = {}
for key in pairs(S.optionalProfileRanges) do clearableOptions[key] = true end
for _, key in ipairs(HIGHLIGHT.KEYS) do optionFields[key], clearableOptions[key] = true, true end

local function CheckOptions(value, path)
    CheckObject(value, path, optionFields)
    local options = {}
    for key, raw in pairs(value) do
        local keyPath = path .. "." .. key
        local choices = S.castOptions[key]
        if key == CLEAR then
            options[CLEAR] = CheckClear(raw, keyPath, clearableOptions)
        elseif profileNumbers[key] or S.optionalProfileRanges[key] then
            options[key] = CheckRange(raw, keyPath, profileNumbers[key] or S.optionalProfileRanges[key])
        elseif choices == "boolean" then
            -- (Not an and/or: false must survive.)
            options[key] = CheckBoolean(raw, keyPath)
        elseif choices then
            options[key] = CheckEnum(raw, keyPath, choices)
        elseif key == "healthTexture" then
            if not PS.Media.IsStatusBar(raw) then Reject(keyPath, "has an unsupported value") end
            options[key] = raw
        elseif key == "healthColourMode" then
            options[key] = CheckEnum(raw, keyPath, healthColourModes)
        elseif key == "healthColour" then
            options[key] = CheckColour(raw, keyPath)
        elseif key == "castColours" then
            CheckObject(raw, keyPath, castColourFields)
            options[key] = {}
            for name, colour in pairs(raw) do options[key][name] = CheckColour(colour, keyPath .. "." .. name) end
        elseif key == "castOnNames" then
            options[key] = CheckBoolean(raw, keyPath)
        elseif HIGHLIGHT.SET[key] then
            options[key] = CheckHighlight(key, raw, keyPath)
        end
    end
    return options
end

local entryFields = Set("placement", "visible", "removed", "name", "added", "deleted")
local placementFields = SetOf(DESIGN.PLACEMENT)

-- One layout entry's override: placement (one unit), the eye, presence, the label (false: the
-- standard name), added (an entry only this design has, with its placement) or deleted (a World
-- group missing here).
local function CheckEntryOverride(key, value, path)
    CheckObject(value, path, entryFields)
    local entry = {}
    if value.placement ~= nil then
        CheckObject(value.placement, path .. ".placement", placementFields)
        entry.placement = CheckPlacement(value.placement, path .. ".placement", key, {})
    end
    if value.visible ~= nil then entry.visible = CheckBoolean(value.visible, path .. ".visible") end
    if value.removed ~= nil then
        if S.IsGroupKey(key) or key:match("^value%d+$") then Reject(path .. ".removed", "only applies to parts") end
        entry.removed = CheckBoolean(value.removed, path .. ".removed")
    end
    if value.name ~= nil then
        entry.name = value.name ~= false and CheckText(value.name, path .. ".name", S.GROUP_NAME_LENGTH) or false
    end
    if value.added ~= nil and CheckBoolean(value.added, path .. ".added") then
        if not entry.placement then Reject(path .. ".placement", "is needed for a part only this design has") end
        entry.added = true
    end
    if value.deleted ~= nil and CheckBoolean(value.deleted, path .. ".deleted") then
        if not S.IsGroupKey(key) then Reject(path .. ".deleted", "only applies to groups") end
        entry.deleted = true
    end
    return entry
end

local designFields = Set("full", "options", "layouts", "styles", "rules", "valueSlots", "auraLayouts")

-- A sparse context design (Designs' storage, colours as hex as elsewhere in the document): each
-- area checked as a profile's is, every error naming its path; then made valid as a saved one is.
local function CheckDesign(value, path, plateType)
    CheckObject(value, path, designFields)
    local design = {}
    if value.options ~= nil then design.options = CheckOptions(value.options, path .. ".options") end
    if value.layouts ~= nil then
        local layoutsPath = path .. ".layouts"
        CheckObject(value.layouts, layoutsPath, SetOf(DESIGN.LAYOUT_FIELDS))
        design.layouts = {}
        for field, map in pairs(value.layouts) do
            local fieldPath = layoutsPath .. "." .. field
            if not profileDefaults[plateType][field] then Reject(fieldPath, "is not used by this profile") end
            CheckObject(map, fieldPath)
            local entries, count = {}, 0
            for key, entry in pairs(map) do
                local entryPath = fieldPath .. "." .. tostring(key)
                if not S.PartKey(key) then Reject(entryPath, "is not a component name") end
                count = count + 1
                if count > MAX_COMPONENTS then Reject(fieldPath, "has too many components") end
                entries[key] = CheckEntryOverride(key, entry, entryPath)
            end
            design.layouts[field] = entries
        end
    end
    if value.styles ~= nil then
        design.styles = CheckStyles(value.styles, path .. ".styles", true)
        SkipExtraParts(design.styles, path .. ".styles")
    end
    if value.rules ~= nil then
        design.rules = CheckRules(value.rules, path .. ".rules")
        SkipExtraParts(design.rules, path .. ".rules")
    end
    if value.valueSlots ~= nil then design.valueSlots = CheckValueSlots(value.valueSlots, path .. ".valueSlots") end
    if value.auraLayouts ~= nil then
        local rows = { buffs = {}, debuffs = {} }
        CheckAuraLayouts(value.auraLayouts, path .. ".auraLayouts", rows, true)
        design.auraLayouts = rows
    end
    return S.NormalizeDesign(design, plateType)
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
    -- Its own target highlight; absent follows the general settings.
    for _, key in ipairs(HIGHLIGHT.KEYS) do
        if value[key] ~= nil then target[key] = CheckHighlight(key, value[key], path .. "." .. key) else target[key] = nil end
    end
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
    if value.rules ~= nil then target.rules = S.NormalizeRules(CheckRules(value.rules, path .. ".rules")) end
    if value.styles ~= nil then
        CheckStyles(value.styles, path .. ".styles")
        target.rules = S.NormalizeRules(S.GradientRules(target.rules, value.styles))
        target.styles = S.NormalizeStyles(value.styles)
    end
end

local flavors = Set("forever", "retail")
local documentFields = Set("format", "version", "readableFrom", "addon", "client", "flavor", "settings", "profiles",
    "dungeonEnemy", "contexts", "enemyPlayers", "modules")
-- Font choices: a built-in key or an "lsm:" reference (PS.Media.IsFont).
local fontSettings = { "font", "blizzardNameFontFace" }
local settingFields = Set("relationshipColours", "stylePresets", "threatColours", "threatPartColours")
local THREAT_COLOURS = S.THREAT_COLOURS
local threatStates, threatParts = SetOf(THREAT_COLOURS.STATES), SetOf(THREAT_COLOURS.PARTS)
for _, key in ipairs(fontSettings) do settingFields[key] = true end
for _, key in ipairs(booleanSettings) do settingFields[key] = true end
for key in pairs(enumSettings) do settingFields[key] = true end
for _, key in ipairs(S.VISIBILITY.KEYS) do settingFields[key] = true end
for key in pairs(settingRanges) do settingFields[key] = true end
for key in pairs(S.colourSettings) do settingFields[key] = true end
-- Codes from before Show on plates followed the eyes carry its switches; one that is off turns
-- its parts' eyes off in the code's layouts (Schema's ApplyLegacySwitches).
for _, switch in ipairs(S.PART_SWITCHES) do settingFields[switch.key] = true end

-- Whether a Blueprint was exported before addon version major.minor.patch (its addon field); one
-- that does not say is taken as older.
local function ExportedBefore(addon, major, minor, patch)
    local a, b, c = tostring(addon or ""):match("^(%d+)%.(%d+)%.(%d+)")
    if not a then return true end
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if a ~= major then return a < major end
    if b ~= minor then return b < minor end
    return c < patch
end

-- Returns a complete, normalized settings table built from defaults plus the document, the number
-- of threat rules a 1.0.3 code turns off, and whether the dungeon overlay test was turned off.
local function BuildCandidate(document)
    CheckObject(document, "blueprint", documentFields)
    if document.format ~= FORMAT then Reject("format", "is not a PlateSmith Blueprint") end
    local version = document.version
    if not READABLE_VERSIONS[version] then
        local newer = type(version) == "number" and version > VERSION and version == math.floor(version)
        if not (newer and READABLE_VERSIONS[document.readableFrom]) then
            Reject("version", "is not supported by this PlateSmith version")
        end
    elseif document.readableFrom ~= nil and not (READABLE_VERSIONS[document.readableFrom] and document.readableFrom <= version) then
        Reject("readableFrom", "is not a version from 2 to the document's own")
    end
    if document.flavor ~= nil then CheckEnum(document.flavor, "flavor", flavors) end

    local candidate = NormalizeSettings({})
    local settings = document.settings == nil and {} or CheckObject(document.settings, "settings", settingFields)
    for _, key in ipairs(booleanSettings) do
        if settings[key] ~= nil then candidate[key] = CheckBoolean(settings[key], "settings." .. key) end
    end
    -- As a saved profile's migration does: before 1.1.1 the dungeon overlay test arrives off.
    local overlayOff = candidate.experimentalDungeonFriendlyText == true and ExportedBefore(document.addon, 1, 1, 1)
    if overlayOff then candidate.experimentalDungeonFriendlyText = false end
    for key, allowed in pairs(enumSettings) do
        if settings[key] ~= nil then candidate[key] = CheckEnum(settings[key], "settings." .. key, allowed) end
    end
    for key, range in pairs(settingRanges) do
        if settings[key] ~= nil then candidate[key] = CheckRange(settings[key], "settings." .. key, range) end
    end
    for key in pairs(S.colourSettings) do
        if settings[key] ~= nil then candidate[key] = CheckColour(settings[key], "settings." .. key) end
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
    if settings.threatColours ~= nil then
        CheckObject(settings.threatColours, "settings.threatColours", threatStates)
        for key, value in pairs(settings.threatColours) do
            candidate.threatColours[key] = CheckColour(value, "settings.threatColours." .. key)
        end
    end
    if settings.threatPartColours ~= nil then
        -- A part listed has Own colours on; a state it leaves out takes the shared colour.
        CheckObject(settings.threatPartColours, "settings.threatPartColours", threatParts)
        local parts = {}
        for part, colours in pairs(settings.threatPartColours) do
            local path = "settings.threatPartColours." .. part
            CheckObject(colours, path, threatStates)
            parts[part] = {}
            for key, value in pairs(colours) do parts[part][key] = CheckColour(value, path .. "." .. key) end
        end
        candidate.threatPartColours = parts
    end
    -- A code from before Threat colours arrives with them off, as a saved profile's migration turns them.
    if settings.colourByThreat == nil then candidate.colourByThreat = false end

    local profiles = document.profiles == nil and {}
        or CheckObject(document.profiles, "profiles", SetOf(profileOrder))
    for _, key in ipairs(profileOrder) do
        if profiles[key] ~= nil then
            -- An export leaves out a design's empty styles: it has none (not a new profile's, nor World's).
            candidate.plateProfiles[key].styles = {}
            ApplyProfile(candidate.plateProfiles[key], profiles[key], "profiles." .. key,
                profileDefaults[key].namesLayout ~= nil)
        end
    end
    -- Context designs (version 4). contexts.enemy.dungeon wins over dungeonEnemy: a full one takes
    -- its body from dungeonEnemy, a sparse one ignores it. Without it, dungeonEnemy (versions 2 and 3,
    -- or a version 4 read for its fallback) is the Enemies' full Dungeons & raids design, as the
    -- migration makes the old override.
    local contexts = document.contexts ~= nil and CheckObject(document.contexts, "contexts", SetOf(profileOrder)) or {}
    local dungeonRecord
    for _, plateType in ipairs(profileOrder) do
        local designs = contexts[plateType]
        if designs ~= nil then
            local typePath = "contexts." .. plateType
            CheckObject(designs, typePath, DESIGN.STORED[plateType])
            for _, context in ipairs(DESIGN.ORDER) do
                local record, path = designs[context], typePath .. "." .. context
                if record ~= nil then
                    CheckObject(record, path)
                    if record.full ~= nil and CheckBoolean(record.full, path .. ".full") then
                        CheckObject(record, path, Set("full"))
                        if path ~= "contexts.enemy.dungeon" then Reject(path .. ".full", "only applies to contexts.enemy.dungeon") end
                        if document.dungeonEnemy == nil then Reject(path .. ".full", "needs dungeonEnemy") end
                        dungeonRecord = "full"
                    else
                        PS.Designs.SetSparse(candidate.plateProfiles[plateType], context, CheckDesign(record, path, plateType))
                        if path == "contexts.enemy.dungeon" then dungeonRecord = "sparse" end
                    end
                end
            end
        end
    end
    if document.dungeonEnemy ~= nil and dungeonRecord ~= "sparse" then
        local dungeon = CopyEnemyProfile(candidate.plateProfiles.enemy)
        dungeon.styles = {}
        ApplyProfile(dungeon, document.dungeonEnemy, "dungeonEnemy", false)
        PS.Designs.SetFull(candidate.plateProfiles.enemy, "dungeon", dungeon)
    end
    -- The Enemy players layer (version 4): a sparse design over the Enemies', never a full one.
    if document.enemyPlayers ~= nil then
        CheckObject(document.enemyPlayers, "enemyPlayers")
        if document.enemyPlayers.full ~= nil then Reject("enemyPlayers.full", "is not allowed here") end
        PS.Designs.SetPlayers(candidate.plateProfiles.enemy, CheckDesign(document.enemyPlayers, "enemyPlayers", "enemy"))
    end
    local legacy = {}
    for _, switch in ipairs(S.PART_SWITCHES) do
        if settings[switch.key] ~= nil then legacy[switch.key] = CheckBoolean(settings[switch.key], "settings." .. switch.key) end
    end
    -- The tank's warning border ran under the old threat switch.
    if legacy.threat == false and settings.tankWarning == nil then candidate.tankWarning = false end
    -- A code whose threat switch was off also turns off its threat rules (the count is returned).
    local disabled = S.ApplyLegacySwitches(candidate, legacy)
    return NormalizeSettings(candidate), disabled, overlayOff
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

-- A part's rules as the document holds them (colours as hex). A rule still being typed (its
-- condition does not compile yet) stays in Studio but is not shared: an import rejects such
-- conditions. An empty condition (always) is shared.
local function ExportRuleList(list)
    local result = {}
    for _, rule in ipairs(list) do
        if rule.when == "" or (PS.Template and PS.Template.CompileCondition(rule.when)) then
            local stops
            for stopIndex, stop in ipairs(rule.stops or {}) do
                stops = stops or {}
                stops[stopIndex] = { at = stop.at, colour = ColourToHex(stop.colour) }
            end
            local shared = { when = rule.when, set = rule.set, alpha = rule.alpha,
                colour = rule.colour and ColourToHex(rule.colour) or nil, stops = stops }
            -- Only a rule turned off says so (false must survive, so not an and/or).
            if rule.enabled == false then shared.enabled = false end
            result[#result + 1] = shared
        end
    end
    return result
end

local function ExportSlot(slot)
    return { source = slot.source, anchor = slot.anchor, layer = slot.layer,
        whenMissing = slot.whenMissing, fontSize = slot.fontSize, colour = ColourToHex(slot.colour),
        name = slot.name, template = slot.template, kind = slot.kind, width = slot.width, height = slot.height,
        icon = slot.icon }
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
    -- (Absent where the design follows the general settings, so an export without any is as before.)
    for _, key in ipairs(HIGHLIGHT.KEYS) do
        local own = profile[key]
        if own ~= nil and S.colourSettings[key] then own = ColourToHex(own) end
        result[key] = own
    end
    result.rules = {}
    for key, list in pairs(profile.rules or {}) do
        local shared = ExportRuleList(list)
        result.rules[key] = #shared > 0 and shared or nil
    end
    for kind, layout in pairs(profile.auraLayouts or {}) do
        result.auraLayouts[kind] = { count = layout.count, columns = layout.columns, size = layout.size,
            spacing = layout.spacing, growX = layout.growX, growY = layout.growY, showDuration = layout.showDuration,
            timeSize = layout.timeSize, timeFont = layout.timeFont, timeOutline = layout.timeOutline,
            timeShadow = layout.timeShadow, timePosition = layout.timePosition,
            timeFontSize = layout.timeFontSize, timedOnly = layout.timedOnly == true or nil }
    end
    if includeNames then
        result.namesLayout = ExportLayout(profile.namesLayout, profile.valueSlots)
        result.dungeonNamesLayout = ExportLayout(profile.dungeonNamesLayout, profile.valueSlots)
    end
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = profile.valueSlots[key]
        if not DefaultSlot(slot) then result.valueSlots[key] = ExportSlot(slot) end
    end
    return result
end

-- Whether a part's style uses a field (NEW_STYLE_FIELDS), a pip size past PIP_LIMITS_111 or a texture
-- (NEW_TEXTURES) 1.1.1 does not know.
local function UsesNewStyleField(style)
    if type(style) ~= "table" then return false end
    for field in pairs(NEW_STYLE_FIELDS) do
        if style[field] ~= nil then return true end
    end
    for field, limit in pairs(PIP_LIMITS_111) do
        if type(style[field]) == "number" and style[field] > limit then return true end
    end
    return NEW_TEXTURES[style.texture] == true
end

-- Whether an exported profile's texture or styles, or saved styles (presets), use one.
local function UsesNewStyleFields(profile, presets)
    if profile and NEW_TEXTURES[profile.healthTexture] then return true end
    for _, style in pairs(profile and profile.styles or {}) do
        if UsesNewStyleField(style) then return true end
    end
    for _, preset in pairs(presets or {}) do
        if type(preset) == "table" and UsesNewStyleField(preset.style) then return true end
    end
    return false
end

-- A sparse context design as the document holds it: Designs' storage, with colours as hex as
-- elsewhere (styles keep { r, g, b, a } as profiles' do). An empty one (it follows World) is {}.
local function ExportDesign(record)
    local result = {}
    if type(record.options) == "table" then
        local options = Table.DeepCopy(record.options)
        if options.healthColour then options.healthColour = ColourToHex(options.healthColour) end
        if options.targetGlowColour then options.targetGlowColour = ColourToHex(options.targetGlowColour) end
        if options.castColours then
            for key, colour in pairs(options.castColours) do options.castColours[key] = ColourToHex(colour) end
        end
        result.options = options
    end
    if type(record.layouts) == "table" then result.layouts = Table.DeepCopy(record.layouts) end
    if type(record.styles) == "table" then result.styles = Table.DeepCopy(record.styles) end
    if type(record.rules) == "table" then
        -- An empty list (no rules on that part here) stays a list.
        result.rules = {}
        for key, list in pairs(record.rules) do result.rules[key] = Json.Array(ExportRuleList(list)) end
    end
    if type(record.valueSlots) == "table" then
        result.valueSlots = {}
        for key, slot in pairs(record.valueSlots) do result.valueSlots[key] = ExportSlot(slot) end
    end
    if type(record.auraLayouts) == "table" then result.auraLayouts = Table.DeepCopy(record.auraLayouts) end
    return result
end

-- The document's contexts: plate type -> context -> design. The Enemies' full Dungeons & raids
-- design (the migrated override) is { full = true }, its body the document's dungeonEnemy, unless
-- withoutBody (the size fallback, which leaves dungeonEnemy out): then, as any other full design,
-- it is written as what it differs from World in. Also whether anything here is new in version 4:
-- any design but that full one.
local function ExportContexts(db, withoutBody)
    local Designs = PS.Designs
    local contexts, newer
    for _, plateType in ipairs(profileOrder) do
        for _, context in ipairs(DESIGN.ORDER) do
            local record = Designs.Record(db, plateType, context)
            if record then
                local legacy = record.full == true and plateType == "enemy" and context == "dungeon"
                newer = newer or not legacy
                contexts = contexts or {}
                contexts[plateType] = contexts[plateType] or {}
                if legacy and not withoutBody then
                    contexts[plateType][context] = { full = true }
                else
                    local sparse = record.full == true and Designs.CopyFrom(db.plateProfiles[plateType], record) or record
                    contexts[plateType][context] = ExportDesign(sparse)
                end
            end
        end
    end
    return contexts, newer
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
-- Version 3 unless something is new since 1.1.1 (ExportContexts, the Enemy players layer,
-- NEW_SETTINGS, NEW_SETTING_VALUES, NEW_STYLE_FIELDS); then version 4, readable from 3. withoutBody:
-- the size fallback (version 4 only), without dungeonEnemy.
local function BuildDocument(db, live, withoutBody)
    if not db then return nil, "settings are not loaded" end
    local settings = { relationshipColours = {} }
    for _, key in ipairs(booleanSettings) do settings[key] = db[key] end
    for key in pairs(enumSettings) do settings[key] = db[key] end
    for key in pairs(settingRanges) do settings[key] = db[key] end
    for _, key in ipairs(fontSettings) do settings[key] = db[key] end
    for key in pairs(S.colourSettings) do settings[key] = ColourToHex(db[key]) end
    local presets = live and PS.GetState and PS.GetState().stylePresets
    settings.stylePresets = presets and next(presets) and Table.DeepCopy(presets) or nil
    for key in pairs(defaultRelationshipColours) do
        settings.relationshipColours[key] = ColourToHex(db.relationshipColours[key])
    end
    local contexts, newer = ExportContexts(db, withoutBody)
    -- The shared threat colours, unless every one is its default (as hex: what an import keeps).
    local threatColours, ownThreatColours = {}, false
    for _, state in ipairs(THREAT_COLOURS.STATES) do
        threatColours[state] = ColourToHex(db.threatColours[state])
        ownThreatColours = ownThreatColours or threatColours[state] ~= ColourToHex(THREAT_COLOURS.defaults[state])
    end
    if ownThreatColours then settings.threatColours, newer = threatColours, true end
    -- Only parts with Own colours on, and none at all when no part has them.
    for _, part in ipairs(THREAT_COLOURS.PARTS) do
        local own = db.threatPartColours and db.threatPartColours[part]
        if own then
            newer = true
            settings.threatPartColours = settings.threatPartColours or {}
            settings.threatPartColours[part] = {}
            for _, state in ipairs(THREAT_COLOURS.STATES) do settings.threatPartColours[part][state] = ColourToHex(own[state]) end
        end
    end
    -- The Enemy players layer, while it holds anything (version 4 only).
    local players = PS.Designs.Record(db, "enemyPlayer")
    local enemyPlayers = players and next(players) ~= nil and ExportDesign(players) or nil
    if enemyPlayers then newer = true end
    for key, absent in pairs(NEW_SETTINGS) do
        if Table.DeepEqual(settings[key], S.colourSettings[key] and ColourToHex(absent) or absent) then
            settings[key] = nil
        else
            newer = true
        end
    end
    for key, values in pairs(NEW_SETTING_VALUES) do newer = newer or values[db[key]] == true end
    newer = newer or UsesNewStyleFields(nil, settings.stylePresets)
    -- World designs as in version 3.
    local profiles = {}
    for _, key in ipairs(profileOrder) do
        profiles[key] = ExportProfile(db.plateProfiles[key], profileDefaults[key].namesLayout ~= nil)
        newer = newer or UsesNewStyleFields(profiles[key]) or HIGHLIGHT.Has(profiles[key])
    end
    -- The Enemies' Dungeons & raids design resolved whole, whatever its kind: version 3's place for
    -- it, and in version 4 the body of a full one (contexts.enemy.dungeon = { full = true }).
    local dungeonEnemy = not withoutBody and PS.Designs.HasDesign(db, "enemy", "dungeon")
        and ExportProfile(PS.Designs.For(db, "enemy", "dungeon"), false) or nil
    newer = newer or UsesNewStyleFields(dungeonEnemy) or HIGHLIGHT.Has(dungeonEnemy)
    local build = type(GetBuildInfo) == "function" and select(4, GetBuildInfo()) or nil
    local document = {
        format = FORMAT, version = newer and VERSION or LEGACY_VERSION, readableFrom = newer and LEGACY_VERSION or nil,
        addon = tostring(PS.RUNTIME_BUILD or "unknown"),
        client = type(build) == "number" and build or nil,
        flavor = PS.ClientFlavor(),
        settings = settings, profiles = profiles,
        dungeonEnemy = dungeonEnemy,
        contexts = newer and contexts or nil,
        enemyPlayers = enemyPlayers,
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

-- The Blueprint's text (or nil, reason). details, a table when given, receives its version. A
-- version 4 document too large with dungeonEnemy is shared without that copy: its contexts still
-- carry the Enemies' Dungeons & raids design, and 1.1.1 refuses any version 4 document anyway.
local function ExportBlueprint(pretty, details)
    local db = PS.GetSettings and PS.GetSettings()
    local document, reason = BuildDocument(db, true)
    if not document then return nil, reason end
    local text = Json.Encode(document, pretty)
    if #text > MAX_JSON_BYTES and document.version > LEGACY_VERSION and document.dungeonEnemy then
        document = assert(BuildDocument(db, true, true))
        text = Json.Encode(document, pretty)
    end
    if #text > MAX_JSON_BYTES then return nil, "blueprint is too large" end
    if type(details) == "table" then details.version = document.version end
    return text
end

-- Text from a Blueprint (a path, a reason) made safe to print: at most limit bytes, never cut inside
-- a UTF-8 character, with chat escapes ("|") made literal.
local function ChatText(text, limit)
    text = tostring(text)
    if #text > limit then text = text:sub(1, limit):gsub("[\192-\255][\128-\191]*$", "") end
    return (text:gsub("|", "||"))
end

-- The context designs a document carries: plate type -> context -> true. A design under contexts (in
-- a context this version stores), the Enemies' dungeonEnemy, and a friendly type's Dungeons & raids
-- names layout unless it is the default one, which every export carries. Read from the document as
-- it is, so the import window (Describe) and the import agree.
local defaultDungeonNames
local function CarriedDesigns(document)
    if not defaultDungeonNames then
        defaultDungeonNames = {}
        local fresh = NormalizeSettings({})
        for _, plateType in ipairs(profileOrder) do
            local profile = fresh.plateProfiles[plateType]
            if profile.dungeonNamesLayout then
                defaultDungeonNames[plateType] = Json.Encode(ExportLayout(profile.dungeonNamesLayout, profile.valueSlots))
            end
        end
    end
    local contexts = type(document.contexts) == "table" and document.contexts or {}
    local profiles = type(document.profiles) == "table" and document.profiles or {}
    local carried = {}
    for _, plateType in ipairs(profileOrder) do
        local designs = type(contexts[plateType]) == "table" and contexts[plateType] or {}
        local names = type(profiles[plateType]) == "table" and profiles[plateType].dungeonNamesLayout
        carried[plateType] = {}
        for _, context in ipairs(DESIGN.ORDER) do
            local has
            if PS.Designs.IsBlizzard(plateType, context) then
                local ok, encoded = pcall(Json.Encode, names)
                has = type(names) == "table" and not (ok and encoded == defaultDungeonNames[plateType])
            else
                has = DESIGN.STORED[plateType][context] and type(designs[context]) == "table"
                    or plateType == "enemy" and context == "dungeon" and type(document.dungeonEnemy) == "table"
            end
            carried[plateType][context] = has or nil
        end
    end
    return carried
end

-- A design's overrides that no longer mean what they did, dropped: record (sparse) was made over
-- base's World (its layouts and custom parts) and now sits over final's. An override of a group or
-- custom part whose key now names something else (a group of another name, parent or members; a
-- custom part with another record), or that World gained or lost, would land on the wrong thing, so it
-- goes, as does a placement under such a parent. Built-in parts keep their meaning. Returns record
-- itself when nothing goes, else a new record.
local function Rebase(record, base, final)
    local members = {}
    local function Members(layout)
        if members[layout] then return members[layout] end
        local result = {}
        for key, entry in pairs(layout) do
            if type(entry) == "table" and entry.parent then
                result[entry.parent] = result[entry.parent] or {}
                table.insert(result[entry.parent], key)
            end
        end
        for _, list in pairs(result) do table.sort(list) end
        members[layout] = result
        return result
    end
    local function SlotMoved(key)
        return key:match("^value%d+$") ~= nil and base.valueSlots ~= final.valueSlots
            and not Table.DeepEqual(base.valueSlots[key], final.valueSlots[key])
    end
    local function Moved(field, key)
        if SlotMoved(key) then return true end
        local before, after = base[field], final[field]
        if before == after or type(before) ~= "table" or type(after) ~= "table" then return false end
        local was, now = before[key], after[key]
        if (was == nil) ~= (now == nil) then return true end
        if was == nil or not S.IsGroupKey(key) then return false end
        return was.name ~= now.name or was.parent ~= now.parent
            or not Table.DeepEqual(Members(before)[key] or {}, Members(after)[key] or {})
    end
    local result
    local function Changed()
        result = result or Table.DeepCopy(record)
        return result
    end
    for field, map in pairs(type(record.layouts) == "table" and record.layouts or {}) do
        local dropped = {}
        for key in pairs(map) do dropped[key] = Moved(field, key) or nil end
        -- Until nothing more goes: a dropped entry may be another's parent.
        local again = true
        while again do
            again = false
            for key, entry in pairs(result and result.layouts[field] or map) do
                local parent = not dropped[key] and type(entry.placement) == "table" and entry.placement.parent
                if parent and (dropped[parent] or Moved(field, parent) and not (map[parent] and map[parent].added)) then
                    -- An entry only this design has needs its placement.
                    local kept = Changed().layouts[field][key]
                    kept.placement, again = nil, true
                    if kept.added or next(kept) == nil then dropped[key] = true end
                end
            end
        end
        for key in pairs(dropped) do Changed().layouts[field][key] = nil end
    end
    for _, area in ipairs({ "styles", "rules", "valueSlots" }) do
        for key in pairs(type(record[area]) == "table" and record[area] or {}) do
            if SlotMoved(key) then Changed()[area][key] = nil end
        end
    end
    return result or record
end

-- An import's selection: Selected(section), and the selection itself (nil: every section). Only a
-- table opts into selective import; callers may pass through a gsub count.
local function Selector(selection)
    if type(selection) ~= "table" then selection = nil end
    local function Selected(section)
        if not selection or selection[section] == true then return true end
        for legacy, current in pairs(LEGACY_SECTIONS) do
            if current == section and selection[legacy] == true then return true end
        end
        return false
    end
    for _, section in ipairs(sections) do
        if Selected(section) then return Selected, selection end
    end
    return nil, "select at least one section"
end

-- The Blueprint JSON checked and built (BuildCandidate), nothing applied: { document, candidate,
-- modules (companion data parsed), disabledRules, overlayOff, skipped = { count, paths } }, or nil and
-- the reason.
local function Parse(text)
    local document, parseError = Json.Decode(text, MAX_JSON_BYTES)
    if document == nil then return nil, "invalid JSON: " .. tostring(parseError) end
    local parsed = { document = document, modules = {}, disabledRules = 0, overlayOff = false,
        skipped = { count = 0, paths = {} } }
    skipped = parsed.skipped
    local built, failure = pcall(function()
        parsed.candidate, parsed.disabledRules, parsed.overlayOff = BuildCandidate(document)
        if document.modules ~= nil then
            CheckObject(document.modules, "modules")
            -- Data for companion addons that are not installed here is skipped.
            for key, value in pairs(document.modules) do
                local descriptor = moduleFields[key]
                if descriptor then
                    local ok, data, reason = pcall(descriptor.parse, value)
                    if not ok or data == nil then Reject("modules." .. key, tostring(reason or "is invalid")) end
                    parsed.modules[key] = data
                end
            end
        end
    end)
    skipped = nil
    if not built then
        if type(failure) == "table" and failure.blueprintError then return nil, failure.blueprintError end
        return nil, "invalid blueprint: " .. tostring(failure)
    end
    return parsed
end

-- The selected sections of parsed written into db (the working settings, or the import preview's
-- copy of them). live: companion-addon data applies (it writes the modules' own state) and the
-- designs' cache is invalidated; the preview does neither. true, or false and the reason.
local function ApplySections(db, parsed, selection, Selected, live)
    local candidate, document, modules = parsed.candidate, parsed.document, parsed.modules
    -- Which carried designs replace yours: every one with contexts (or no selection), the Enemies'
    -- Dungeons & raids design with the old dungeon key, the friendly ones' with dungeonFriendly.
    local carried = CarriedDesigns(document)
    local function ContextSelected(plateType, context)
        if not carried[plateType][context] then return false end
        if not selection or selection.contexts == true then return true end
        if PS.Designs.IsBlizzard(plateType, context) then return selection.dungeonFriendly == true end
        return selection.dungeon == true and plateType == "enemy" and context == "dungeon"
    end

    do
        local profiles = db.plateProfiles
        -- World as the profile's designs were made over it, before this import.
        local before = {}
        for _, key in ipairs(profileOrder) do
            local world = profiles[key]
            before[key] = { layout = world.layout, namesLayout = world.namesLayout, valueSlots = world.valueSlots }
        end
        if Selected("settings") then
            for _, key in ipairs(booleanSettings) do db[key] = candidate[key] end
            for key in pairs(enumSettings) do db[key] = candidate[key] end
            for key in pairs(settingRanges) do db[key] = candidate[key] end
            for _, key in ipairs(fontSettings) do db[key] = candidate[key] end
            for key in pairs(S.colourSettings) do db[key] = candidate[key] end
            db.relationshipColours = candidate.relationshipColours
            db.threatColours, db.threatPartColours = candidate.threatColours, candidate.threatPartColours
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
            if Selected("values") then
                target.valueSlots = source.valueSlots
                target.powerHeight = source.powerHeight
            end
        end
        -- Each design the Blueprint carries replaces yours there; your others stay. Every sparse design
        -- then drops what no longer means the same over World (Rebase): one imported now was made over
        -- the Blueprint's World, one kept over yours as it was.
        local imported = {}
        for _, key in ipairs(profileOrder) do
            local source, target = candidate.plateProfiles[key], profiles[key]
            local contexts = {}
            for name, record in pairs(type(target.contexts) == "table" and target.contexts or {}) do contexts[name] = record end
            imported[key] = {}
            for _, context in ipairs(DESIGN.ORDER) do
                if ContextSelected(key, context) then
                    if PS.Designs.IsBlizzard(key, context) then
                        target.dungeonNamesLayout = source.dungeonNamesLayout
                    else
                        contexts[context], imported[key][context] = source.contexts and source.contexts[context], true
                    end
                end
            end
            for _, context in ipairs(DESIGN.ORDER) do
                local record = contexts[context]
                if type(record) == "table" and record.full ~= true then
                    contexts[context] = Rebase(record, imported[key][context] and source or before[key], target)
                end
            end
            target.contexts = next(contexts) ~= nil and contexts or nil
        end
        -- The Enemy players layer is replaced whole: a Blueprint without one removes yours.
        local enemy = profiles.enemy
        if Selected("enemyPlayers") then
            enemy.players = candidate.plateProfiles.enemy.players
            if enemy.players then enemy.players = Rebase(enemy.players, candidate.plateProfiles.enemy, enemy) end
        elseif enemy.players then
            enemy.players = Rebase(enemy.players, before.enemy, enemy)
        end
        if live and Selected("other") then
            for _, key in ipairs(SortedModuleKeys()) do
                if modules[key] ~= nil then
                    local ok, applied = pcall(moduleFields[key].apply, modules[key])
                    if not ok or applied == false then return false, "module apply failed: " .. key end
                end
            end
        end
    end
    NormalizeSettings(db)
    if live then PS.Designs.Invalidate() end
    return true
end

local function ImportBlueprint(text, selection)
    local db = PS.GetSettings and PS.GetSettings()
    if not db then return false, "settings are not loaded" end
    if type(text) ~= "string" then return false, "blueprint must be text" end
    local Selected, chosen = Selector(selection)
    if not Selected then return false, chosen end
    selection = chosen
    local parsed, reason = Parse(text)
    if not parsed then return false, reason end
    local candidate, document = parsed.candidate, parsed.document
    local disabledRules, overlayOff, skippedFields = parsed.disabledRules, parsed.overlayOff, parsed.skipped

    -- Module apply callbacks write live state, so any failure restores the
    -- whole pre-import settings rather than leaving a partial Blueprint.
    local snapshot = Table.DeepCopy(db)
    local completed, applied, failure = pcall(ApplySections, db, parsed, selection, Selected, true)
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
    if PS.Profiles then
        local rules = disabledRules > 0 and (Selected("styles") or Selected("contexts"))
        PS.Profiles.NoteMigration(PS.Profiles.Active(), { threatRulesDisabled = rules and disabledRules or 0,
            dungeonOverlayOff = overlayOff and Selected("settings") })
    end
    -- Imports across clients succeed; the third result names the other client
    -- so the caller can say some options may behave differently here. The fourth lists the fields
    -- skipped, unknown or not kept ({ count, paths }, paths sorted; nil when none), for BlueprintSkippedMessage.
    local otherFlavor
    if document.flavor ~= nil and document.flavor ~= PS.ClientFlavor() then otherFlavor = document.flavor end
    if skippedFields.count == 0 then return true, nil, otherFlavor end
    table.sort(skippedFields.paths)
    return true, nil, otherFlavor, skippedFields
end

-- What ImportBlueprint(text, selection) would leave the working settings as, without importing: a
-- copy of them with the same sections applied by the same route (ApplySections), for the import
-- window's preview. Companion-addon data and saved styles are left out (they are not the profile's,
-- and draw nothing on a plate). Returns the copy, or nil and the reason the import would fail.
local function ImportResult(text, selection)
    local db = PS.GetSettings and PS.GetSettings()
    if not db then return nil, "settings are not loaded" end
    if type(text) ~= "string" then return nil, "blueprint must be text" end
    local Selected, chosen = Selector(selection)
    if not Selected then return nil, chosen end
    local parsed, reason = Parse(text)
    if not parsed then return nil, reason end
    local result = Table.DeepCopy(db)
    local completed, applied, failure = pcall(ApplySections, result, parsed, chosen, Selected, false)
    if not completed or not applied then
        return nil, completed and failure or ("blueprint apply failed: " .. tostring(applied))
    end
    return result
end

-- The one chat line for an import that skipped fields (nil when none): at most SKIPPED_SHOWN paths,
-- each cut to SKIPPED_PATH_LENGTH bytes (ChatText), then how many more. A skipped field is one this
-- version does not know (a newer PlateSmith's) or cannot keep (a context design a plate type cannot
-- have here, parts past a design's limit).
local SKIPPED_SHOWN, SKIPPED_PATH_LENGTH = 5, 80
local function SkippedMessage(fields)
    if type(fields) ~= "table" or type(fields.count) ~= "number" or fields.count < 1 then return nil end
    local shown = {}
    for index = 1, math.min(SKIPPED_SHOWN, #fields.paths) do
        shown[index] = ChatText(fields.paths[index], SKIPPED_PATH_LENGTH)
    end
    local list = table.concat(shown, ", ")
    local more = fields.count - #shown
    if more > 0 then list = string.format(L["%s and %d more"], list, more) end
    if fields.count == 1 then
        return string.format(L["Imported, except 1 setting this PlateSmith cannot use (it may be from a newer version): %s."], list)
    end
    return string.format(L["Imported, except %d settings this PlateSmith cannot use (some may be from a newer version): %s."],
        fields.count, list)
end

-- The chat line for an import that failed: its reason, at most FAILURE_LENGTH bytes (ChatText).
local FAILURE_LENGTH = 200
local function FailureMessage(reason)
    return string.format(L["Blueprint import failed: %s"], ChatText(reason or L["invalid data"], FAILURE_LENGTH))
end

-- The import window's summary of pasted text: which context designs it carries (CarriedDesigns:
-- "Includes: Enemies › Dungeons & raids, Players › Cities & inns"), and { contexts = { label },
-- enemyPlayers = true | nil }. nil for text that is not a Blueprint. Read only to describe it: nothing
-- is checked.
local PLATE_LABELS = { enemy = L["Enemies"], friendlyPlayer = L["Players"], friendlyNPC = L["Friendly NPCs"] }
local function Describe(text)
    if type(text) ~= "string" then return nil end
    if text:match("^%s*!PSB") then
        text = PS.DecodeShareCode and PS.DecodeShareCode(text)
        if not text then return nil end
    end
    local document = Json.Decode(text, MAX_JSON_BYTES)
    if type(document) ~= "table" or document.format ~= FORMAT then return nil end
    local carried = CarriedDesigns(document)
    local labels = {}
    for _, plateType in ipairs(profileOrder) do
        for _, context in ipairs(DESIGN.ORDER) do
            if carried[plateType][context] then
                labels[#labels + 1] = string.format(L["%s › %s"], PLATE_LABELS[plateType], PS.Designs.LABELS[context])
            end
        end
    end
    local info = { contexts = labels, enemyPlayers = document.enemyPlayers ~= nil or nil }
    local named = {}
    for index, label in ipairs(labels) do named[index] = label end
    if type(document.enemyPlayers) == "table" then named[#named + 1] = L["Enemy players"] end
    if #named == 0 then return L["Includes: World designs only"], info end
    return string.format(L["Includes: %s"], table.concat(named, ", ")), info
end

PS.BlueprintDescribe = Describe
PS.MAX_BLUEPRINT_BYTES = MAX_JSON_BYTES
PS.RegisterBlueprintField = RegisterBlueprintField
PS.ExportBlueprint = ExportBlueprint
PS.BlueprintDocument = function(settings) return BuildDocument(settings, false) end
PS.ImportBlueprint = ImportBlueprint
PS.BlueprintImportResult = ImportResult
PS.BlueprintSkippedMessage = SkippedMessage
PS.BlueprintFailureMessage = FailureMessage
