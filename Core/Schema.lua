local _, PS = ...
local Format = assert(PS.Format, "PlateSmith Format missing")
local Template = assert(PS.Template, "PlateSmith Template missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local Media = assert(PS.Media, "PlateSmith Media missing")

local defaults = {
    schemaVersion = 25,
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
    classificationStyle = "icon", -- icon (Blizzard's nameplate icons), words, letters
    quest = true,
    -- Whose quest icons show: auto (Questie's when Questie shows nameplate icons, else
    -- PlateSmith's), platesmith, or questie (PlateSmith's step aside while Questie is loaded).
    questIcons = "auto",
    threat = true,
    showTagged = true,
    -- The target-of-target name hides while that unit targets you (it would say your name).
    targetNameHideSelf = true,
    showBuffs = true,
    showDebuffs = true,
    buffSource = "all",       -- all, mine
    debuffSource = "mine",   -- all, mine
    nativeNameFont = true,
    scale = 1,
    width = 112,
    healthHeight = 10,
    nameFontSize = 12,
    threatSpotlightStyle = "glow", -- glow, arrow, sides, box, both
    targetHighlightStyle = "border", -- off, border, halo
    threatSpotlightOthersAlpha = 0.55,
    threatSpotlightDuration = 3,
    threatPalette = "auto", -- auto (follows the colorblindMode CVar), standard, colourblind
    font = "default", -- default (Blizzard's multilingual nameplate font) or lsm:<name>
}

-- Custom parts: up to 24 per plate type. Each is a text value (a live value or a template), a
-- bar filled by a percentage, a box (a coloured rectangle) or an icon.
local VALUE_SLOT_COUNT = 24
local valueKinds = { text = true, bar = true, box = true, icon = true }
local valueIcons = {
    raid1 = true, raid2 = true, raid3 = true, raid4 = true, raid5 = true, raid6 = true, raid7 = true, raid8 = true,
    quest = true, sword = true, shield = true, skull = true,
}
local VALUE_WIDTH, VALUE_HEIGHT = { 2, 240, true }, { 2, 80, true }
local valueSources = {
    off = true, healthPercent = true, healthCurrent = true, healthValue = true,
    powerPercent = true, powerCurrent = true, powerValue = true,
    threatPercent = true, leadPercent = true, rawThreat = true, differential = true,
    template = true, -- the slot's own text template (Core/Template.lua)
    static = true, -- a box or icon: always shown (rules can change it)
}
local valueAnchors = { canvas = true, health = true, power = true, cast = true }
local valueLayers = { back = true, front = true }
local missingAnchorModes = { fallback = true, hide = true }
local valueFontRange = { 7, 18, true }
local WHITE = { r = 1, g = 1, b = 1 }
-- An unused custom part: off, white 9 pt text on the health bar. Blueprints leave slots like
-- this out.
local DEFAULT_VALUE_SLOT = { source = "off", anchor = "health", layer = "front", whenMissing = "fallback", fontSize = 9,
    colour = WHITE }
local function DefaultValueSlot() return Table.DeepCopy(DEFAULT_VALUE_SLOT) end

-- A player-typed name: control characters removed, trimmed, at most length characters (UTF-8
-- aware). nil when nothing is left.
local function CleanName(name, length)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[%c]", ""):match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return Format.Truncate(name, length)
end

-- A custom value's own name (shown in Studio's list), trimmed and at most 24 characters;
-- none (nil) shows its default "Value 1" and so on.
local VALUE_NAME_LENGTH = 24
-- A value's template or a rule's condition: text, control characters removed, at most
-- Template.MAX_LENGTH bytes (the bound on compile work), never cut inside a character.
local TEMPLATE_LENGTH = Template.MAX_LENGTH
local function TemplateText(text)
    return Format.Truncate((text:gsub("[%c]", "")), TEMPLATE_LENGTH, TEMPLATE_LENGTH)
end
local function NormalizeValueTemplate(text)
    if type(text) ~= "string" then return nil end
    text = TemplateText(text)
    if text == "" then return nil end
    return text
end

-- Rules: per part, an ordered list of { when = condition, set = what, colour | alpha | stops },
-- read top to bottom: the last rule that holds sets each property (Core/Template.lua compiles
-- the conditions). "blend" colours the part by health %, between its stops ({ at = 0-100,
-- colour }, 2-5 of them, sorted); an empty condition always holds.
local RULE_SETS = { colour = true, alpha = true, hide = true, blend = true }
local MAX_RULES_PER_PART, MAX_RULES = 8, 64
local MIN_BLEND_STOPS, MAX_BLEND_STOPS = 2, 5
local function PartKey(key) return type(key) == "string" and key:match("^[%a][%w_%.]*$") ~= nil end
local function RuleColour(colour)
    colour = type(colour) == "table" and colour or {}
    return { r = Format.Unit(colour.r, 0.5), g = Format.Unit(colour.g, 0.5), b = Format.Unit(colour.b, 0.5) }
end
-- A blend's stops as whole percentages in order; nil when fewer than two are usable.
local function NormalizeBlendStops(stops)
    if type(stops) ~= "table" then return nil end
    local result = {}
    for _, stop in ipairs(stops) do
        local at = type(stop) == "table" and tonumber(stop.at)
        if at and at == at and #result < MAX_BLEND_STOPS then
            result[#result + 1] = { at = math.floor(math.max(0, math.min(100, at)) + 0.5), colour = RuleColour(stop.colour) }
        end
    end
    if #result < MIN_BLEND_STOPS then return nil end
    -- An insertion sort keeps stops at the same percentage in the order given.
    for index = 2, #result do
        local stop, place = result[index], index
        while place > 1 and result[place - 1].at > stop.at do
            result[place] = result[place - 1]
            place = place - 1
        end
        result[place] = stop
    end
    return result
end
-- limit: how many rules may be kept in all (default MAX_RULES).
local function NormalizeRules(rules, limit)
    local result, total = {}, 0
    limit = limit or MAX_RULES
    if type(rules) ~= "table" then return result end
    local keys = {}
    for key in pairs(rules) do if PartKey(key) then keys[#keys + 1] = key end end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local list = {}
        for _, rule in ipairs(type(rules[key]) == "table" and rules[key] or {}) do
            if type(rule) == "table" and RULE_SETS[rule.set] and #list < MAX_RULES_PER_PART and total < limit then
                local when = type(rule.when) == "string" and TemplateText(rule.when) or ""
                local entry = { when = when, set = rule.set }
                if rule.set == "colour" then
                    entry.colour = RuleColour(rule.colour)
                elseif rule.set == "alpha" then
                    entry.alpha = Format.Unit(rule.alpha, 0.5)
                elseif rule.set == "blend" then
                    entry.stops = NormalizeBlendStops(rule.stops)
                end
                if rule.set ~= "blend" or entry.stops then
                    list[#list + 1] = entry
                    total = total + 1
                end
            end
        end
        if #list > 0 then result[key] = list end
    end
    return result
end

-- One part's rules, in a profile that already holds others: kept within the total limit.
local function NormalizePartRules(rules, key, list)
    local others = 0
    for otherKey, other in pairs(type(rules) == "table" and rules or {}) do
        if otherKey ~= key and type(other) == "table" then others = others + #other end
    end
    return NormalizeRules({ [key] = list }, math.max(0, MAX_RULES - others))[key]
end

local function NormalizeValueName(name) return CleanName(name, VALUE_NAME_LENGTH) end

local function DefaultValueSlots()
    local slots = {}
    for index = 1, VALUE_SLOT_COUNT do slots["value" .. index] = DefaultValueSlot() end
    return slots
end

-- How each aura row lays out its icons: how many, how many per line, their size and gap,
-- which way a line grows from the component's position, and which way extra lines stack.
local auraLayoutRanges = { count = { 1, 8, true }, columns = { 1, 8, true }, size = { 12, 32, true },
    spacing = { 0, 6, true } }
local auraGrowX = { right = true, left = true, centre = true }
local auraGrowY = { up = true, down = true }
local defaultAuraLayouts = {
    -- Both rows sit above the name, centred on it, and further lines grow away from it.
    buffs = { count = 4, columns = 4, size = 18, spacing = 2, growX = "centre", growY = "up", showDuration = true },
    debuffs = { count = 4, columns = 4, size = 18, spacing = 2, growX = "centre", growY = "up", showDuration = true },
}

local function NormalizeAuraLayouts(layouts, fallback)
    layouts = type(layouts) == "table" and layouts or {}
    local normalized = {}
    for kind, rowDefaults in pairs(fallback or defaultAuraLayouts) do
        local layout = type(layouts[kind]) == "table" and layouts[kind] or {}
        local row = {}
        for key, range in pairs(auraLayoutRanges) do
            local value = tonumber(layout[key]) or rowDefaults[key]
            value = math.max(range[1], math.min(range[2], value))
            row[key] = math.floor(value + 0.5)
        end
        row.growX = auraGrowX[layout.growX] and layout.growX or rowDefaults.growX
        row.growY = auraGrowY[layout.growY] and layout.growY or rowDefaults.growY
        if layout.showDuration == nil then row.showDuration = rowDefaults.showDuration ~= false
        else row.showDuration = layout.showDuration ~= false end
        normalized[kind] = row
    end
    return normalized
end

local profileOrder = { "enemy", "friendlyPlayer", "friendlyNPC" }
-- The default template (docs/DEFAULT_LAYOUTS.md). Every plate type starts from the same grid, so
-- Studio shows each one in the same place: a full plate's health bar sits on the centre line, a
-- names-only plate's name does. Types differ only in what is shown (shown: the keys visible by
-- default). An entry is { x, y[, parent, attach] }: a part that must follow another's size is
-- pinned to its edge (the level left of the name, the quest mark left of the level), so a long
-- name pushes it out instead of running under it. A pinned part takes the place of a parent
-- that is turned off or has nothing to show (PinTarget), and hides only with a bar, an aura row
-- or a rule; a wider pinned gap (raidIcon 22 px right of a names-only name) keeps room for the
-- icon that may show before it.
local FULL_POSITIONS = {
    -- The name 18 px up: the quest mark (16 px) beside it stays clear of the raid mark (18 px)
    -- beside the bar under any name length.
    name = { 0, 18 }, health = { 0, 0 }, cast = { 0, -13 },
    -- Under the bars in the Bars stack (AddTemplateStacks), closing up while a bar is idle.
    guild = { 0, -26 }, threat = { 0, -26 }, targetName = { 0, -40 },
    level = { -3, 0, "name", "left" }, quest = { -2, 0, "level", "left" }, pvpIcon = { -2, 0, "level", "left" },
    relationshipIcon = { 3, 0, "name", "right" },
    raidIcon = { -4, 0, "health", "left" }, classification = { 4, 0, "health", "right" },
    -- TAGGED after the classification mark, so a long word ("Rare elite") never runs under it;
    -- on a mob without one it takes the mark's place beside the bar.
    tagged = { 4, 0, "classification", "right" },
    -- Above the name in the Auras stack: debuffs nearest, buffs above them.
    debuffs = { 0, 36 }, buffs = { 0, 56 },
}
local NAMES_POSITIONS = {
    -- 3 px: clear of an 18 px raid mark beside a short name, over the guild line's wider text.
    name = { 0, 0 }, guild = { 0, -3, "name", "bottom" },
    level = { -3, 0, "name", "left" }, quest = { -2, 0, "level", "left" }, pvpIcon = { -2, 0, "level", "left" },
    relationshipIcon = { 3, 0, "name", "right" }, raidIcon = { 22, 0, "name", "right" },
    classification = { 43, 0, "name", "right" }, tagged = { 64, 0, "name", "right" },
    health = { 0, -29 }, cast = { 0, -42 }, threat = { 0, -55 }, targetName = { 0, -27 },
    debuffs = { 0, 19 }, buffs = { 0, 39 },
}

-- overrides: key -> { x, y } for one plate type (the same parent and edge).
local function BuildLayout(positions, shown, overrides)
    local layout = {}
    for key, position in pairs(positions) do
        local own = overrides and overrides[key] or position
        layout[key] = { x = own[1], y = own[2], visible = shown[key] == true, parent = position[3], attach = position[4] }
    end
    -- The quest-loot bag shows where the quest mark would, anchored to it.
    layout.questLoot = { x = 0, y = 0, visible = shown.quest == true, parent = "quest" }
    layout.level.order, layout.quest.order, layout.pvpIcon.order = 1, 1, 2
    return layout
end

local function FullLayout(shown) return BuildLayout(FULL_POSITIONS, shown) end
local function NamesLayout(shown, overrides) return BuildLayout(NAMES_POSITIONS, shown, overrides) end

-- The enemy template, and the fallback for any layout entry that is missing.
local defaultLayout = FullLayout({ name = true, health = true, cast = true, threat = true, tagged = true, quest = true,
    raidIcon = true, classification = true, level = true, buffs = true, debuffs = true })

-- The entries every layout has beyond the grid: the power bar (hidden) and the custom parts,
-- which sit on the health bar.
local function AddBarEntries(layout)
    layout.power = { x = 0, y = -14, visible = false }
    for index = 1, VALUE_SLOT_COUNT do
        layout["value" .. index] = { x = 0, y = 0, visible = true, parent = "health", order = index }
    end
end

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
        layout = FullLayout({ name = true, health = true, cast = true, raidIcon = true,
            relationshipIcon = true, pvpIcon = true, level = true, guild = true, buffs = true, debuffs = true }),
        -- Names-only plates show no aura rows by default, as Blizzard's and Plater's do: a city
        -- full of players would otherwise read every player's auras.
        namesLayout = NamesLayout({ name = true, raidIcon = true, relationshipIcon = true, pvpIcon = true,
            level = true, guild = true }),
    },
    friendlyNPC = {
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 12,
        healthTexture = "blizzard", healthColourMode = "automatic",
        healthColour = { r = 0.35, g = 0.9, b = 1 },
        layout = FullLayout({ name = true, health = true, cast = true, quest = true, raidIcon = true,
            level = true, buffs = true, debuffs = true }),
        -- NPCs have no relationship icon, so the raid mark sits straight after the name.
        namesLayout = NamesLayout({ name = true, quest = true, raidIcon = true, level = true },
            { raidIcon = { 3, 0 } }),
    },
}

-- The cast bar's own parts, on every plate type: the spell's icon (left or right of the bar, or
-- off), the time left inside the bar's right end, and the spell's name.
local castOptions = { castIcon = { left = true, right = true, off = true }, castTime = "boolean", castName = "boolean" }
local castDefaults = { castIcon = "left", castTime = true, castName = true }

for profileKey, profile in pairs(profileDefaults) do
    for key, value in pairs(castDefaults) do profile[key] = value end
    AddBarEntries(profile.layout)
    if profile.namesLayout then
        AddBarEntries(profile.namesLayout)
        -- Friendly names in dungeons: the names-only layout showing only its text.
        profile.dungeonNamesLayout = Table.DeepCopy(profile.namesLayout)
        for key, position in pairs(profile.dungeonNamesLayout) do
            local text = key == "name" or key == "level"
                or (profileKey == "friendlyPlayer" and key == "guild")
            position.visible = text and position.visible ~= false or false
        end
    end
    profile.valueSlots = DefaultValueSlots()
    profile.auraLayouts = NormalizeAuraLayouts(nil)
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
local validAuraSources = { all = true, mine = true }
local validClassificationStyles = { icon = true, words = true, letters = true }
local validQuestIcons = { auto = true, platesmith = true, questie = true }
local validThreatPalettes = { auto = true, standard = true, colourblind = true }
local validThreatSpotlightStyles = { glow = true, arrow = true, sides = true, box = true, both = true }
local validTargetHighlightStyles = { off = true, border = true, halo = true }

-- Numeric bounds shared by normalization and Blueprint validation; true = whole number.
local profileRanges = {
    scale = { 0.7, 1.5 }, width = { 80, 200, true }, healthHeight = { 6, 20, true },
    powerHeight = { 3, 14, true }, nameFontSize = { 9, 20, true },
}
-- A bar's own size: nil widths follow the health bar; the cast bar's height starts 3 px under
-- the health bar's and is then its own.
local optionalProfileRanges = {
    powerWidth = { 80, 200, true }, castWidth = { 80, 200, true }, castHeight = { 3, 20, true },
}
-- The general settings' own numbers. (scale, width, healthHeight and nameFontSize at the top
-- level are copies of the enemy profile's.)
local settingRanges = { threatSpotlightOthersAlpha = { 0.3, 1 }, threatSpotlightDuration = { 1, 8, true } }
local ENEMY_ALIASES = { scale = true, width = true, healthHeight = true, nameFontSize = true }
-- Component positions on the preview canvas, and per-component scale.
local layoutRanges = { x = { -280, 280, true }, y = { -105, 105, true }, scale = { 0.5, 2 } }

-- Every general setting has one of these validators (or is font, relationshipColours or an
-- enemy alias). Blueprints share all of them except enabled.
local booleanSettings = {
    "enabled", "hideUnstyledFriendlyNames", "friendlyRelationshipColours", "restrictedFriendlyNamesOnly",
    "restrictedFriendlyClassColour", "experimentalDungeonFriendlyText", "showPlayerSurnames", "showGroupIcon",
    "showGuildIcon", "showClassification", "quest", "threat", "showTagged", "showBuffs", "showDebuffs",
    "nativeNameFont", "targetNameHideSelf",
}
local enumSettings = {
    mode = validModes, friendly = validFriendlyModes, friendlyPvpStyle = validFriendlyPvpStyles,
    buffSource = validAuraSources, debuffSource = validAuraSources, classificationStyle = validClassificationStyles,
    questIcons = validQuestIcons, targetHighlightStyle = validTargetHighlightStyles,
    threatSpotlightStyle = validThreatSpotlightStyles, threatPalette = validThreatPalettes,
}
local isBooleanSetting = {}
for _, key in ipairs(booleanSettings) do isBooleanSetting[key] = true end

-- The first candidate that converts to a number, clamped to range (and
-- rounded for whole-number ranges). The last candidate is always a default.
local function Bounded(range, ...)
    local value
    for index = 1, select("#", ...) do
        value = tonumber((select(index, ...)))
        if value then break end
    end
    value = math.max(range[1], math.min(range[2], value or range[1]))
    return range[3] and math.floor(value + 0.5) or value
end

-- True only for a real number inside range (and whole, for whole-number ranges).
local function InRange(range, value)
    return type(value) == "number" and value == value and value >= range[1] and value <= range[2]
        and (not range[3] or value == math.floor(value))
end

-- Component scale snaps to 5% steps.
local function ComponentScale(value)
    return math.floor(Bounded(layoutRanges.scale, value, 1) * 20 + 0.5) / 20
end

local function CopyDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = value
        end
    end
end

-- The anchors a layout without parents (schema 20 and older, Blueprints without layoutVersion)
-- may name; they are read as parents.
local componentAnchors = { questLoot = { quest = true } }

-- The layout is a hierarchy: an entry may name a parent (any other entry, a part or a group). A
-- part is drawn at its parent's centre plus its own offset times the parent's drawn scale, and
-- its drawn scale is its own times its parent's (like a scene hierarchy). Roots hang from the
-- plate's centre at scale 1. MAX_DEPTH bounds the chain; cycles are cut when normalizing.
local MAX_DEPTH = 8

-- A parent can stack its children (stack = down, up, right or left, with gap): in tree order,
-- the first keeps its own offset and each next sits gap beyond the one before along that axis;
-- across it each keeps its own offset. Hidden, deleted and free children take no space.
local STACK_DIRECTIONS = { down = true, up = true, right = true, left = true }
local STACK_GAP = { 0, 40, true }

-- Dynamic placement's edges: which way from the parent's centre, and the points that meet
-- (the part's facing point on the parent's edge point).
local ATTACH_EDGES = {
    left = { -1, 0, "RIGHT", "LEFT" }, right = { 1, 0, "LEFT", "RIGHT" },
    top = { 0, 1, "BOTTOM", "TOP" }, bottom = { 0, -1, "TOP", "BOTTOM" },
}

local function IsPartKey(layout, key)
    return type(key) == "string" and type(layout[key]) == "table" and not key:match("^group%.%d+$")
end

-- Turned off by the player: the eye off, or deleted.
local function TurnedOff(position)
    return type(position) == "table" and (position.visible == false or position.removed == true)
end

-- The part a pinned entry meets. While its parent is turned off (or absent(key): the plate has
-- nothing to show in it, such as a normal mob's classification), the pinned part takes that
-- part's place: it meets what the hidden part sits on, on its own edge with its own gap, walking
-- up to a shown part. A hidden part under a group or the plate is kept (it still has a place).
-- nil when key is not pinned to a part.
local function PinTarget(layout, key, absent)
    local position = layout[key]
    if type(position) ~= "table" or not ATTACH_EDGES[position.attach] or not IsPartKey(layout, position.parent) then
        return nil
    end
    local target = position.parent
    for _ = 1, MAX_DEPTH do
        local entry = layout[target]
        if not (TurnedOff(entry) or (absent and absent(target))) then break end
        local up = entry.parent
        if not IsPartKey(layout, up) or up == key then break end
        target = up
    end
    return target
end

-- key -> { x, y, scale } drawn from the plate's centre, for every entry of layout. measure(key),
-- when given, returns a part's width and height in its own units (nil: not stacked); without
-- it stacks are not applied. absent(key), when given, says a part has nothing to show on this
-- plate right now (see PinTarget).
local function LayoutTransforms(layout, measure, absent)
    local result, visiting, stacks = {}, {}, {}
    local function StackOffsets(parentKey)
        if stacks[parentKey] then return stacks[parentKey] end
        local offsets, parent = {}, layout[parentKey]
        stacks[parentKey] = offsets
        local children = {}
        for key, position in pairs(layout) do
            if type(position) == "table" and position.parent == parentKey and not position.free
                and position.visible ~= false and not position.removed then
                -- measure(key) -> width, height[, hidden[, boxX, boxY]]: box* is the drawn box's
                -- centre from the part's own centre (an aura grid's further lines), own units.
                local width, height, hidden, boxX, boxY = measure(key)
                if width and height then
                    children[#children + 1] = { key = key, width = width, height = height, hidden = hidden,
                        boxX = tonumber(boxX) or 0, boxY = tonumber(boxY) or 0 }
                end
            end
        end
        table.sort(children, function(left, right)
            local a, b = layout[left.key].order or 99, layout[right.key].order or 99
            if a ~= b then return a < b end
            return left.key < right.key
        end)
        local direction, gap = parent.stack, tonumber(parent.gap) or 0
        local vertical = direction == "down" or direction == "up"
        local sign = (direction == "down" or direction == "left") and -1 or 1
        -- The stack starts at the first child's leading edge (it keeps its own offset). Each
        -- shown child follows the last; a hidden one (measure's third result) is placed where
        -- it would go but takes no space, so what follows closes up until it shows.
        local edge
        for _, child in ipairs(children) do
            local position = layout[child.key]
            local own = tonumber(position.scale) or 1
            local half = (vertical and child.height or child.width) * own / 2
            local x, y = tonumber(position.x) or 0, tonumber(position.y) or 0
            local box = (vertical and child.boxY or child.boxX) * own
            if not edge then edge = (vertical and y or x) + box - sign * half end
            local along = edge + sign * half - box
            if vertical then y = along else x = along end
            if not child.hidden then edge = edge + sign * (2 * half + gap) end
            offsets[child.key] = { x = x, y = y }
        end
        return offsets
    end
    local function Resolve(key, depth)
        local done = result[key]
        if done then return done end
        local position = layout[key]
        if type(position) ~= "table" or visiting[key] or depth > MAX_DEPTH then return { x = 0, y = 0, scale = 1 } end
        visiting[key] = true
        local parentEntry = position.parent and layout[position.parent]
        local parent = parentEntry and Resolve(position.parent, depth + 1) or { x = 0, y = 0, scale = 1 }
        visiting[key] = nil
        local x, y = tonumber(position.x) or 0, tonumber(position.y) or 0
        if measure and parentEntry and STACK_DIRECTIONS[parentEntry.stack] then
            local stacked = StackOffsets(position.parent)[key]
            if stacked then x, y = stacked.x, stacked.y end
        end
        local scale = parent.scale * (tonumber(position.scale) or 1)
        local transform = {
            x = parent.x + x * parent.scale,
            y = parent.y + y * parent.scale,
            scale = scale,
        }
        -- Dynamic: pinned to an edge of its parent part. (x, y) is then the gap from the parent's
        -- edge to the part's facing edge, so it follows the parent's size (a longer name moves a
        -- level pinned to its left). Needs sizes; a group parent has none, so it stays static.
        -- A turned-off parent passes its place on (PinTarget); the gap stays in the parent's units.
        local edge = ATTACH_EDGES[position.attach]
        local target = edge and measure and PinTarget(layout, key, absent)
        if target then
            local base = parent
            if target ~= position.parent then
                visiting[key] = true
                base = Resolve(target, depth + 1)
                visiting[key] = nil
            end
            local targetWidth, targetHeight = measure(target)
            local width, height = measure(key)
            if targetWidth and targetHeight and width and height then
                transform.x = base.x + x * parent.scale + edge[1] * (targetWidth * base.scale + width * scale) / 2
                transform.y = base.y + y * parent.scale + edge[2] * (targetHeight * base.scale + height * scale) / 2
            end
        end
        result[key] = transform
        return transform
    end
    for key in pairs(layout) do Resolve(key, 0) end
    return result
end

-- An aura row's whole grid: the row frame is its first line; further lines go up or down.
-- Returns the grid's width and height and its centre's offset from the first line's centre.
local function AuraGridBox(aura, count)
    if type(aura) ~= "table" then return nil end
    local size, spacing, columns = tonumber(aura.size) or 18, tonumber(aura.spacing) or 0, math.max(1, tonumber(aura.columns) or 1)
    local lines = math.max(1, math.ceil((count or tonumber(aura.count) or columns) / columns))
    local width = columns * size + (columns - 1) * spacing
    local height = lines * size + (lines - 1) * spacing
    local offset = (lines - 1) * (size + spacing) / 2 * (aura.growY == "down" and -1 or 1)
    return width, height, offset
end

-- Custom component groups live in a layout as "group.<n>" entries: the group's offset (x, y,
-- which moves every member placed from the plate's centre), its name and its order in Studio's
-- tree. A member names its group in its own entry (group = "group.<n>").
local GROUP_NAME_LENGTH, MAX_GROUPS = 24, 16
local function IsGroupKey(key) return type(key) == "string" and key:match("^group%.%d+$") ~= nil end

local function NormalizeGroupName(name) return CleanName(name, GROUP_NAME_LENGTH) end

-- Drawing order: higher in the tree draws on top, and a part's children draw on the part. An
-- entry's layer (-10 to 10; unset: its parent's, 0 at the top) comes first, so a part brought
-- to the front draws over everything. Returns key -> rank (1 = front) for the
-- parts, and their count. Groups draw nothing; their layer carries their contents.
local LAYER_RANGE = { -10, 10, true }

local function DrawOrder(layout)
    local children = {}
    for key, position in pairs(layout) do
        if type(position) == "table" then
            local parent = position.parent and layout[position.parent] and position.parent or false
            children[parent] = children[parent] or {}
            children[parent][#children[parent] + 1] = key
        end
    end
    for _, list in pairs(children) do
        table.sort(list, function(left, right)
            local a, b = layout[left].order or 99, layout[right].order or 99
            if a ~= b then return a < b end
            return left < right
        end)
    end
    local sequence, effective = {}, {}
    -- Front to back: a part's children before the part itself (they draw on it, as a value on
    -- its bar), and higher siblings, with everything under them, before lower ones.
    local function Walk(parentKey, inherited, depth)
        for _, key in ipairs(children[parentKey] or {}) do
            local layer = tonumber(layout[key].layer) or inherited
            if depth < MAX_DEPTH then Walk(key, layer, depth + 1) end
            if not IsGroupKey(key) then
                sequence[#sequence + 1] = key
                effective[key] = layer
            end
        end
    end
    Walk(false, 0, 0)
    local treeIndex = {}
    for index, key in ipairs(sequence) do treeIndex[key] = index end
    table.sort(sequence, function(left, right)
        if effective[left] ~= effective[right] then return effective[left] > effective[right] end
        return treeIndex[left] < treeIndex[right]
    end)
    local rank = {}
    for index, key in ipairs(sequence) do rank[key] = index end
    return rank, #sequence
end

-- The default template's groups: Studio's tree starts with these. They are ordinary groups, so
-- they can be renamed, reordered, moved, scaled or deleted like any other; parts keep an order
-- inside their group.
local DEFAULT_GROUPS = {
    { name = "Text", members = { "name", "level", "guild", "threat", "tagged", "targetName" } },
    { name = "Bars", members = { "health", "power", "cast" }, stack = "down", gap = 4 },
    { name = "Markers", members = { "quest", "raidIcon", "relationshipIcon", "pvpIcon", "classification" } },
    { name = "Auras", members = { "buffs", "debuffs" } },
}
for index = 1, VALUE_SLOT_COUNT do table.insert(DEFAULT_GROUPS[1].members, "value" .. index) end

-- Puts a layout's ungrouped parts into the default groups, added after any groups it has.
local function AddDefaultGroups(layout, withStacks)
    local nextIndex, nextOrder, count = 1, 0, 0
    for key, position in pairs(layout) do
        if IsGroupKey(key) then
            count = count + 1
            nextIndex = math.max(nextIndex, tonumber(key:match("%d+")) + 1)
            nextOrder = math.max(nextOrder, type(position) == "table" and tonumber(position.order) or 0)
        end
    end
    for _, group in ipairs(DEFAULT_GROUPS) do
        local members = {}
        for _, member in ipairs(group.members) do
            local position = layout[member]
            if type(position) == "table" and not position.group and not position.parent then members[#members + 1] = member end
        end
        if #members > 0 and count < MAX_GROUPS then
            local key = "group." .. nextIndex
            nextIndex, nextOrder, count = nextIndex + 1, nextOrder + 1, count + 1
            layout[key] = { x = 0, y = 0, visible = true, scale = 1, name = group.name, order = nextOrder,
                stack = withStacks and group.stack or nil, gap = withStacks and group.gap or nil }
            for order, member in ipairs(members) do layout[member].parent, layout[member].order = key, order end
        end
    end
    return layout
end

-- Reads a layout without Dynamic placement (schema 22 and older, Blueprint layoutVersion below
-- 3): Level with followName becomes Level pinned to the name's left edge (the same gap, so
-- nothing moves), and a value on a bar becomes that bar's child (hiding with it). followName
-- applied only to a shown name, so with the name hidden or removed Level keeps its place.
local function UpgradeLayoutPlacement(layout, field, valueSlots)
    if type(layout) ~= "table" then return layout end
    local level, name = layout.level, layout.name
    if type(level) == "table" then
        if level.followName ~= false and type(name) == "table" and name.visible ~= false and not name.removed
            and not level.attach then
            -- The old rule: level's right edge 10 px left of the name's left edge, less the
            -- plate type's baseline (-70 full plates, -85 names-only), in Level's own units at
            -- its own scale (not its group's). Pinned, a gap is in the name's drawn units and
            -- Level's size is the name's times its own, so both convert and nothing moves.
            local baseline = field == "layout" and -70 or -85
            local ownScale = tonumber(level.scale) or 1
            local nameTransform = LayoutTransforms(layout).name
            local nameScale = nameTransform and nameTransform.scale > 0 and nameTransform.scale or 1
            local ratio = ownScale / nameScale
            level.x = (-10 + (tonumber(level.x) or 0) - baseline) * ratio
            level.y = ((tonumber(level.y) or 0) - (tonumber(name.y) or 0)) * ratio
            if ratio ~= 1 then level.scale = ratio end
            level.parent, level.attach, level.free, level.order = "name", "left", nil, 1
        end
        level.followName = nil
    end
    if type(valueSlots) == "table" then
        for key, slot in pairs(valueSlots) do
            local position = layout[key]
            if type(position) == "table" and type(slot) == "table" and type(slot.anchor) == "string"
                and slot.anchor ~= "canvas" and type(layout[slot.anchor]) == "table" then
                position.parent, position.free, position.attach = slot.anchor, nil, nil
            end
        end
    end
    return layout
end

-- The template's own stacks: the text under the bars joins the Bars stack (guild, threat, then
-- the target's name, each closing up while what is above it is hidden), and the aura rows stack
-- up from above the name, debuffs first. Parts pinned to another part stay where they are.
local function AddTemplateStacks(layout)
    for key, position in pairs(layout) do
        if IsGroupKey(key) and position.name == "Bars" then
            for order, part in ipairs({ "guild", "threat", "targetName" }) do
                local entry = layout[part]
                if entry and (entry.parent == nil or IsGroupKey(entry.parent)) then
                    entry.parent, entry.order = key, 3 + order
                end
            end
        elseif IsGroupKey(key) and position.name == "Auras" then
            position.stack, position.gap = "up", 2
            layout.debuffs.order, layout.buffs.order = 1, 2
        end
    end
end

for _, profile in pairs(profileDefaults) do
    for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
        local layout = profile[field]
        if layout then
            AddDefaultGroups(layout, true)
            AddTemplateStacks(layout)
        end
    end
end

-- Layouts from before the hierarchy (schema 20 and older, and Blueprints without layoutVersion)
-- used groups (group = "group.<n>", offsets in each part's own scale) and anchors. This rewrites
-- one in place as parents, keeping where and how large everything is drawn. valueSlots, when
-- given, says which values sit on a bar (those keep their bar-relative offsets). A level that
-- follows the name keeps its own rule.
local function UpgradeLayoutToHierarchy(layout, valueSlots)
    if type(layout) ~= "table" then return layout end
    -- A layout already in the hierarchy (parents, and no groups or anchors) is left alone.
    local legacy, hasParents = false, false
    for _, position in pairs(layout) do
        if type(position) == "table" then
            if position.group ~= nil or position.anchor ~= nil then legacy = true end
            if position.parent ~= nil then hasParents = true end
        end
    end
    if hasParents and not legacy then return layout end
    local drawn = {}
    local function OnBar(key)
        local slot = type(valueSlots) == "table" and valueSlots[key]
        return type(slot) == "table" and slot.anchor ~= nil and slot.anchor ~= "canvas"
    end
    local function Old(key, depth)
        if drawn[key] then return drawn[key] end
        local position = layout[key]
        if type(position) ~= "table" or depth > 4 then return { x = 0, y = 0, scale = 1 } end
        local x, y, own = tonumber(position.x) or 0, tonumber(position.y) or 0, tonumber(position.scale) or 1
        local result
        if IsGroupKey(key) then
            result = { x = x, y = y, scale = own }
        elseif type(position.anchor) == "string" and layout[position.anchor] then
            local anchor = Old(position.anchor, depth + 1)
            result = { x = anchor.x + x * own, y = anchor.y + y * own, scale = own }
        else
            local group = type(position.group) == "string" and layout[position.group]
            local g = group and Old(position.group, depth + 1) or { x = 0, y = 0, scale = 1 }
            result = { x = g.x + x * own * g.scale, y = g.y + y * own * g.scale, scale = own * g.scale }
        end
        drawn[key] = result
        return result
    end
    local keep = {}
    for key, position in pairs(layout) do
        if type(position) == "table" then
            Old(key, 0)
            -- A pinned entry is already in the hierarchy's form: a part the template added to an
            -- old layout (its pin, not a place to convert).
            keep[key] = OnBar(key) or (key == "level" and position.followName ~= false) or position.attach ~= nil
        end
    end
    for _, position in pairs(layout) do
        if type(position) == "table" then
            position.parent = type(position.anchor) == "string" and position.anchor or position.group or position.parent
            position.anchor, position.group = nil, nil
        end
    end
    -- Parents first, so each child is placed against its parent's upgraded transform.
    local placed = {}
    local function Place(key, depth)
        if placed[key] or depth > 4 then return end
        local position = layout[key]
        local parentKey = position.parent
        -- A parent this layout does not hold (a partial Blueprint) stays named, offsets as they are.
        local present = parentKey and type(layout[parentKey]) == "table"
        if present then Place(parentKey, depth + 1) end
        placed[key] = true
        if keep[key] or (parentKey and not present) then return end
        local parent = position.parent and LayoutTransforms(layout)[position.parent] or { x = 0, y = 0, scale = 1 }
        local target = drawn[key]
        position.scale = target.scale / parent.scale
        position.x = (target.x - parent.x) / parent.scale
        position.y = (target.y - parent.y) / parent.scale
    end
    for key, position in pairs(layout) do
        if type(position) == "table" then Place(key, 0) end
    end
    return layout
end

local function NormalizeLayout(layout, fallbackLayout)
    fallbackLayout = fallbackLayout or defaultLayout
    local normalized = {}
    if type(layout) == "table" then
        for key, position in pairs(layout) do
            if PartKey(key) and type(position) == "table" then
                local x, y = tonumber(position.x), tonumber(position.y)
                if x and y then
                    -- Only layouts from before Dynamic placement carry followName (their upgrade
                    -- reads it); it is never added.
                    local followName
                    if key == "level" and position.followName ~= nil then followName = position.followName ~= false end
                    normalized[key] = {
                        x = Bounded(layoutRanges.x, x),
                        y = Bounded(layoutRanges.y, y),
                        visible = position.visible ~= false,
                        scale = ComponentScale(position.scale),
                        followName = followName,
                        parent = type(position.parent) == "string" and position.parent ~= key and position.parent or nil,
                        order = tonumber(position.order) and math.floor(math.max(0, math.min(99, position.order))) or nil,
                        -- A built-in part the player deleted: off the tree and the plate until added back.
                        removed = position.removed == true or nil,
                        stack = STACK_DIRECTIONS[position.stack] and position.stack or nil,
                        gap = STACK_DIRECTIONS[position.stack] and Bounded(STACK_GAP, position.gap, 0) or nil,
                        free = position.free == true or nil,
                        layer = tonumber(position.layer) and Bounded(LAYER_RANGE, position.layer) or nil,
                        attach = ATTACH_EDGES[position.attach] and position.attach or nil,
                    }
                    if normalized[key].removed then normalized[key].visible = false end
                    if IsGroupKey(key) then
                        normalized[key].name = NormalizeGroupName(position.name) or "Group"
                        normalized[key].order = math.floor(tonumber(position.order) or 0)
                    elseif type(position.name) == "string" then
                        -- A built-in part's own name in Studio's tree (nil: its standard name).
                        normalized[key].name = NormalizeGroupName(position.name)
                    end
                end
            end
        end
    end
    -- Missing parts come from the fallback with their place in its tree; a new layout takes all
    -- its groups (the default template), an existing one only a group a copied part sits in.
    local fresh = next(normalized) == nil
    local function Copy(key, position)
        normalized[key] = { x = position.x, y = position.y, visible = position.visible ~= false,
            scale = ComponentScale(position.scale),
            parent = position.parent, order = position.order, stack = position.stack, gap = position.gap,
            layer = position.layer, attach = position.attach }
        normalized[key].name = position.name
    end
    for key, position in pairs(fallbackLayout) do
        if not normalized[key] and (fresh or not IsGroupKey(key)) then Copy(key, position) end
    end
    if not fresh then
        repeat
            local needed = {}
            for _, position in pairs(normalized) do
                local parent = position.parent
                if parent and not normalized[parent] and IsGroupKey(parent) and type(fallbackLayout[parent]) == "table" then
                    needed[parent] = true
                end
            end
            for parent in pairs(needed) do Copy(parent, fallbackLayout[parent]) end
        until next(needed) == nil
    end
    -- A parent must exist, and the chain must end: a cycle or a chain past MAX_DEPTH is cut.
    for _, position in pairs(normalized) do
        if position.parent and not normalized[position.parent] then position.parent = nil end
    end
    for key, position in pairs(normalized) do
        local seen, current, depth = { [key] = true }, position.parent, 0
        while current do
            depth = depth + 1
            if seen[current] or depth > MAX_DEPTH then position.parent = nil break end
            seen[current] = true
            current = normalized[current] and normalized[current].parent
        end
    end
    return normalized
end

local function NormalizeColour(colour, fallback)
    colour = type(colour) == "table" and colour or fallback
    local normalized = {}
    for _, channel in ipairs({ "r", "g", "b" }) do
        normalized[channel] = Format.Unit(colour[channel], fallback[channel])
    end
    return normalized
end

-- Styles: per part, how it is drawn beyond position and size. Text parts: font (a media key;
-- nil is the plates' font), outline, shadow, and an optional box behind the text (fill,
-- border, padding). Bars: texture, background, border. Everything is optional; nil keeps the
-- part as it draws today. Colour by health is a blend rule: an older style's gradient becomes
-- one (GradientRules) and is not kept.
local STYLE_OUTLINES = { none = true, outline = true, thick = true }
local STYLE_PADDING, STYLE_BORDER = { 0, 12, true }, { 0, 4, true }
-- What an unset field draws as, on the plates, in Studio's preview and in the inspector. Read only.
local STYLE_DEFAULTS = {
    boxColour = { r = 0, g = 0, b = 0, a = 0.65 },
    boxBorder = { r = 0.78, g = 0.62, b = 0.3, a = 1 },
    padding = 3,
    background = { r = 0.025, g = 0.025, b = 0.025, a = 0.92 },
}
local function StyleColour(value, alpha)
    if type(value) ~= "table" then return nil end
    return { r = Format.Unit(value.r, 1), g = Format.Unit(value.g, 1), b = Format.Unit(value.b, 1),
        a = alpha ~= false and Format.Unit(value.a, 1) or nil }
end
local function NormalizeStyles(styles)
    local result = {}
    if type(styles) ~= "table" then return result end
    for key, style in pairs(styles) do
        if PartKey(key) and type(style) == "table" then
            local entry = {
                font = Media.IsFont(style.font) and style.font or nil,
                outline = STYLE_OUTLINES[style.outline] and style.outline or nil,
                shadow = nil,
                box = style.box == true or nil,
                boxColour = StyleColour(style.boxColour),
                boxBorder = StyleColour(style.boxBorder),
                padding = tonumber(style.padding) and Bounded(STYLE_PADDING, style.padding) or nil,
                texture = Media.IsStatusBar(style.texture) and style.texture or nil,
                background = StyleColour(style.background),
                border = tonumber(style.border) and Bounded(STYLE_BORDER, style.border) or nil,
                borderColour = StyleColour(style.borderColour),
            }
            -- On, off, or nil for the plates' own shadow (false must survive, so not an and/or).
            if type(style.shadow) == "boolean" then entry.shadow = style.shadow end
            if next(entry) then result[key] = entry end
        end
    end
    return result
end

-- rules (part -> list) with each styled part's old gradient (low, mid, high) put first as a
-- blend at 0, 50 and 100%, unless the part already has a blend rule. The list may then exceed
-- a part's limit; NormalizeRules keeps the first ones. (Core loads before the plates' own
-- StyleBlend, and the core suites load Schema alone, so the conversion is made here.)
local GRADIENT_STOPS = { { "low", 0, { r = 0.9, g = 0.15, b = 0.1 } }, { "mid", 50, { r = 0.95, g = 0.8, b = 0.1 } },
    { "high", 100, { r = 0.2, g = 0.85, b = 0.25 } } }
local function GradientRules(rules, styles)
    rules = type(rules) == "table" and rules or {}
    for key, style in pairs(type(styles) == "table" and styles or {}) do
        local gradient = type(style) == "table" and style.gradient
        if PartKey(key) and type(gradient) == "table" then
            local list, blended = type(rules[key]) == "table" and rules[key] or {}, false
            for _, rule in ipairs(list) do blended = blended or (type(rule) == "table" and rule.set == "blend") end
            if not blended then
                local stops = {}
                for index, stop in ipairs(GRADIENT_STOPS) do
                    stops[index] = { at = stop[2], colour = StyleColour(gradient[stop[1]], false) or stop[3] }
                end
                local converted = { { when = "", set = "blend", stops = stops } }
                for _, rule in ipairs(list) do converted[#converted + 1] = rule end
                rules[key] = converted
            end
        end
    end
    return rules
end

-- Saved styles: at most 40, named (at most 24 characters), for text or bar parts. A preset holds
-- a style (NormalizeStyles) and optionally rules (NormalizeRules).
local PRESET_KINDS, MAX_PRESETS, PRESET_NAME_LENGTH = { text = true, bar = true }, 40, 24
local function PresetName(name) return CleanName(name, PRESET_NAME_LENGTH) end
local function NormalizeStylePresets(presets)
    local result, count = {}, 0
    if type(presets) ~= "table" then return result end
    local names = {}
    for name in pairs(presets) do if type(name) == "string" then names[#names + 1] = name end end
    table.sort(names)
    for _, name in ipairs(names) do
        local preset = presets[name]
        local clean = PresetName(name)
        if clean and type(preset) == "table" and PRESET_KINDS[preset.kind] and count < MAX_PRESETS then
            local style = NormalizeStyles({ part = preset.style }).part
            local rules = NormalizeRules(GradientRules({ part = preset.rules }, { part = preset.style })).part
            if style or rules then
                result[clean] = { kind = preset.kind, style = style, rules = rules }
                count = count + 1
            end
        end
    end
    return result
end

local function IsProfileOption(key)
    return profileRanges[key] ~= nil or optionalProfileRanges[key] ~= nil or key == "healthTexture"
        or key == "healthColourMode" or castOptions[key] ~= nil
end

-- One profile option made valid for profile (fallback: its defaults). NormalizeProfile checks
-- every option this way; Settings writes a single one.
local function ProfileOptionValue(profile, key, value, fallback)
    local range = profileRanges[key]
    if range then return Bounded(range, value, fallback[key]) end
    range = optionalProfileRanges[key]
    if range then
        if tonumber(value) then return Bounded(range, value) end
        -- The cast bar's height starts 3 px under the health bar's (at least 5); changing the
        -- health bar does not move it.
        if key == "castHeight" then return Bounded(range, math.max(5, (tonumber(profile.healthHeight) or 10) - 3)) end
        return nil
    end
    if key == "healthTexture" then return Media.IsStatusBar(value) and value or fallback.healthTexture end
    if key == "healthColourMode" then return value == "custom" and "custom" or "automatic" end
    local choices = castOptions[key]
    if choices then
        if choices == "boolean" and type(value) == "boolean" then return value end
        if choices ~= "boolean" and choices[value] then return value end
        if fallback[key] ~= nil then return fallback[key] end
        return castDefaults[key]
    end
    return nil
end

local function NormalizeProfile(profile, fallback, legacy)
    profile = type(profile) == "table" and profile or {}
    legacy = type(legacy) == "table" and legacy or {}
    local previousLayout = profile.layout or legacy.layout
    for key, range in pairs(profileRanges) do
        profile[key] = Bounded(range, profile[key], legacy[key], fallback[key])
    end
    for key in pairs(optionalProfileRanges) do profile[key] = ProfileOptionValue(profile, key, profile[key], fallback) end
    for _, key in ipairs({ "healthTexture", "healthColourMode" }) do
        profile[key] = ProfileOptionValue(profile, key, profile[key], fallback)
    end
    for key in pairs(castOptions) do profile[key] = ProfileOptionValue(profile, key, profile[key], fallback) end
    profile.healthColour = NormalizeColour(profile.healthColour, fallback.healthColour)
    profile.valueSlots = type(profile.valueSlots) == "table" and profile.valueSlots or {}
    local base = DEFAULT_VALUE_SLOT
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = type(profile.valueSlots[key]) == "table" and profile.valueSlots[key] or {}
        profile.valueSlots[key] = {
            source = valueSources[slot.source] and slot.source or base.source,
            anchor = valueAnchors[slot.anchor] and slot.anchor or base.anchor,
            layer = valueLayers[slot.layer] and slot.layer or base.layer,
            whenMissing = missingAnchorModes[slot.whenMissing] and slot.whenMissing or base.whenMissing,
            fontSize = Bounded(valueFontRange, slot.fontSize, base.fontSize),
            kind = valueKinds[slot.kind] and slot.kind ~= "text" and slot.kind or nil,
            width = tonumber(slot.width) and Bounded(VALUE_WIDTH, slot.width) or nil,
            height = tonumber(slot.height) and Bounded(VALUE_HEIGHT, slot.height) or nil,
            icon = valueIcons[slot.icon] and slot.icon or nil,
            colour = NormalizeColour(slot.colour, base.colour),
            name = NormalizeValueName(slot.name),
            template = NormalizeValueTemplate(slot.template),
        }
    end
    profile.layout = NormalizeLayout(profile.layout or legacy.layout, fallback.layout)
    profile.auraLayouts = NormalizeAuraLayouts(profile.auraLayouts, fallback.auraLayouts)
    profile.rules = NormalizeRules(GradientRules(profile.rules, profile.styles))
    profile.styles = NormalizeStyles(profile.styles)
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
        powerWidth = source.powerWidth, castWidth = source.castWidth, castHeight = source.castHeight,
        healthTexture = source.healthTexture, healthColourMode = source.healthColourMode,
        castIcon = source.castIcon, castTime = source.castTime, castName = source.castName,
        healthColour = NormalizeColour(source.healthColour, profileDefaults.enemy.healthColour),
        layout = NormalizeLayout(source.layout, profileDefaults.enemy.layout),
        auraLayouts = NormalizeAuraLayouts(source.auraLayouts),
        rules = NormalizeRules(source.rules),
        styles = NormalizeStyles(source.styles),
        valueSlots = Table.DeepCopy(source.valueSlots),
    }
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
    [19] = function(settings)
        -- The tree's built-in groups became real groups (the default template); layouts get them.
        local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        for _, profile in pairs(profiles) do
            for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
                if type(profile) == "table" and type(profile[field]) == "table" then AddDefaultGroups(profile[field]) end
            end
        end
        if type(settings.layout) == "table" then AddDefaultGroups(settings.layout) end
        settings.schemaVersion = 20
    end,
    [20] = function(settings)
        -- Groups and anchors became one hierarchy of parents; nothing moves.
        local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        for _, profile in pairs(profiles) do
            if type(profile) == "table" then
                for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
                    if type(profile[field]) == "table" then UpgradeLayoutToHierarchy(profile[field], profile.valueSlots) end
                end
            end
        end
        if type(settings.layout) == "table" then UpgradeLayoutToHierarchy(settings.layout) end
        settings.schemaVersion = 21
    end,
    [21] = function(settings)
        -- Bars stack (so a shown power bar pushes the cast bar down) where the template's Bars
        -- group still holds the three bars at their default places; moved bars stay as they are.
        local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        for _, profile in pairs(profiles) do
            for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
                local layout = type(profile) == "table" and profile[field]
                if type(layout) == "table" then
                    for key, position in pairs(layout) do
                        if IsGroupKey(key) and type(position) == "table" and position.name == "Bars" and not position.stack then
                            local function At(part, x, y)
                                local entry = layout[part]
                                return type(entry) == "table" and entry.parent == key and entry.x == x and entry.y == y
                                    and (entry.scale or 1) == 1
                            end
                            if At("health", 0, 0) and At("power", 0, -14) and At("cast", 0, -13) then
                                position.stack, position.gap = "down", 4
                            end
                        end
                    end
                end
            end
        end
        settings.schemaVersion = 22
    end,
    [22] = function(settings)
        -- Dynamic placement: Level follows the name as its pinned child; values on a bar are its
        -- children. Nothing moves on the plate.
        local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        for _, profile in pairs(profiles) do
            if type(profile) == "table" then
                for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
                    UpgradeLayoutPlacement(profile[field], field, profile.valueSlots)
                end
            end
        end
        if type(settings.layout) == "table" then UpgradeLayoutPlacement(settings.layout, "layout") end
        settings.schemaVersion = 23
    end,
    [23] = function(settings)
        -- Level pinned to the name sits on the name's line: a full plate's converted template
        -- level (16 px below, on the bar's line) overlapped the bar under a short name.
        local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        for _, profile in pairs(profiles) do
            local level = type(profile) == "table" and type(profile.layout) == "table" and profile.layout.level
            if type(level) == "table" and level.parent == "name" and level.attach == "left" and level.y == -16 then
                level.y = 0
            end
        end
        settings.schemaVersion = 24
    end,
    [24] = function(settings)
        -- TAGGED at its old default (26 px right of the health bar, past an 18 px mark) follows the
        -- classification instead, so a classification word no longer runs under it.
        local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        for _, profile in pairs(profiles) do
            local layout = type(profile) == "table" and type(profile.layout) == "table" and profile.layout
            local tagged, mark = layout and layout.tagged, layout and layout.classification
            if type(tagged) == "table" and type(mark) == "table" and tagged.parent == "health" and tagged.attach == "right"
                and tagged.x == 26 and tagged.y == 0 and (tagged.scale or 1) == 1
                and mark.parent == "health" and mark.attach == "right" then
                tagged.parent, tagged.x = "classification", 4
            end
        end
        settings.schemaVersion = 25
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

-- A general setting's value, made valid: the default when it is not. nil for a key without a
-- validator of its own (relationshipColours, plateProfiles, the enemy aliases).
local function SettingValue(key, value)
    if isBooleanSetting[key] then
        if type(value) == "boolean" then return value end
        return defaults[key]
    end
    local allowed = enumSettings[key]
    if allowed then return allowed[value] and value or defaults[key] end
    if key == "font" then return Media.IsFont(value) and value or defaults.font end
    local range = settingRanges[key]
    if range then return Bounded(range, value, defaults[key]) end
    return nil
end

local function NormalizeSettings(settings)
    settings = type(settings) == "table" and settings or {}
    -- Every saved profile carries schemaVersion (stamped below), so a table without one is new
    -- (a fresh install, a reset, a Blueprint candidate): it starts at the current schema, and
    -- migrations run only on saved data from an older one.
    if settings.schemaVersion == nil then settings.schemaVersion = defaults.schemaVersion end
    local schemaVersion = MigrateSettings(settings)
    CopyDefaults(settings, defaults)
    for key in pairs(defaults) do
        local value = SettingValue(key, settings[key])
        if value ~= nil then settings[key] = value end
    end
    settings.relationshipColours = type(settings.relationshipColours) == "table" and settings.relationshipColours or {}
    for key, fallback in pairs(defaultRelationshipColours) do
        settings.relationshipColours[key] = NormalizeColour(settings.relationshipColours[key], fallback)
    end
    settings.plateProfiles = NormalizeProfiles(settings.plateProfiles, settings)
    -- The top-level scale, width, healthHeight, nameFontSize and layout mirror the enemy profile.
    local enemy = settings.plateProfiles.enemy
    for key in pairs(ENEMY_ALIASES) do settings[key] = enemy[key] end
    settings.layout = enemy.layout
    settings.schemaVersion = math.max(schemaVersion, defaults.schemaVersion)
    return settings
end

-- Account-wide state, kept outside profiles so it never waits for Save: captured CVars to
-- restore, the threat windows (Threat/Console.lua checks each entry), saved styles and how
-- Studio looks to this player.
local stateDefaults = {
    studioScale = 0.85, -- Blueprint Studio's size for this player, before fitting the screen
    -- Studio's accessibility options for this player: colour-blind friendly cues, high contrast.
    studioColourBlind = false,
    studioHighContrast = false,
    threatConsoleShown = false,
    threatWindows = {},
    -- Saved styles ("Level box", "Framed bar"): name -> { kind, style, rules }, applied to any
    -- part of that kind. The player's own, kept across profiles, Revert and profile switches.
    stylePresets = {},
    -- Studio's and Settings' folded sections for this player: section key -> true.
    sectionFolds = {},
}
local studioScaleRange = { 0.6, 1.3 }

local function NormalizeState(state)
    state = type(state) == "table" and state or {}
    if type(state.threatConsoleShown) ~= "boolean" then state.threatConsoleShown = stateDefaults.threatConsoleShown end
    for _, key in ipairs({ "studioColourBlind", "studioHighContrast" }) do
        if type(state[key]) ~= "boolean" then state[key] = stateDefaults[key] end
    end
    if type(state.threatWindows) ~= "table" then state.threatWindows = {} end
    if state.cvarRestore ~= nil and type(state.cvarRestore) ~= "table" then state.cvarRestore = nil end
    -- Studio no longer has themes: an older saved choice is dropped.
    state.editorTheme = nil
    state.studioScale = Bounded(studioScaleRange, state.studioScale, stateDefaults.studioScale)
    state.stylePresets = NormalizeStylePresets(state.stylePresets)
    local folds, count = {}, 0
    if type(state.sectionFolds) == "table" then
        for key, folded in pairs(state.sectionFolds) do
            if type(key) == "string" and #key <= 64 and folded == true and count < 64 then
                folds[key], count = true, count + 1
            end
        end
    end
    state.sectionFolds = folds
    return state
end

-- Per-character preferences live outside PlateSmithDB so alts keep their own role.
-- tankRole: adaptive (the group role, else what the character is doing: a tanking stance,
-- aura or feral bear), always (this character tanks) or never.
local characterDefaults = {
    tankRole = "adaptive",
}
local validTankRoles = { adaptive = true, always = true, never = true }

local function NormalizeCharacterSettings(settings)
    settings = type(settings) == "table" and settings or {}
    -- alwaysTank (saved by a tick box before tankRole) = true reads as always.
    if settings.tankRole == nil and settings.alwaysTank == true then settings.tankRole = "always" end
    settings.alwaysTank = nil
    for key, value in pairs(characterDefaults) do
        if type(settings[key]) ~= type(value) then settings[key] = value end
    end
    if not validTankRoles[settings.tankRole] then settings.tankRole = characterDefaults.tankRole end
    return settings
end

PS.ProfileSchema = {
    defaults = defaults,
    profileRanges = profileRanges,
    optionalProfileRanges = optionalProfileRanges,
    castOptions = castOptions,
    layoutRanges = layoutRanges,
    valueFontRange = valueFontRange,
    auraLayoutRanges = auraLayoutRanges,
    auraGrowX = auraGrowX,
    auraGrowY = auraGrowY,
    Bounded = Bounded,
    InRange = InRange,
    ComponentScale = ComponentScale,
    characterDefaults = characterDefaults,
    validTankRoles = validTankRoles,
    stateDefaults = stateDefaults,
    studioScaleRange = studioScaleRange,
    NormalizeState = NormalizeState,
    NormalizeCharacterSettings = NormalizeCharacterSettings,
    defaultLayout = defaultLayout,
    VALUE_SLOT_COUNT = VALUE_SLOT_COUNT,
    valueKinds = valueKinds,
    valueIcons = valueIcons,
    VALUE_WIDTH = VALUE_WIDTH,
    VALUE_HEIGHT = VALUE_HEIGHT,
    valueSources = valueSources,
    valueAnchors = valueAnchors,
    valueLayers = valueLayers,
    missingAnchorModes = missingAnchorModes,
    DEFAULT_VALUE_SLOT = DEFAULT_VALUE_SLOT,
    DefaultValueSlot = DefaultValueSlot,
    CleanName = CleanName,
    PartKey = PartKey,
    NormalizeValueName = NormalizeValueName,
    IsGroupKey = IsGroupKey,
    AddDefaultGroups = AddDefaultGroups,
    LayoutTransforms = LayoutTransforms,
    PinTarget = PinTarget,
    TurnedOff = TurnedOff,
    STACK_DIRECTIONS = STACK_DIRECTIONS,
    DrawOrder = DrawOrder,
    AuraGridBox = AuraGridBox,
    LAYER_RANGE = LAYER_RANGE,
    STACK_GAP = STACK_GAP,
    UpgradeLayoutToHierarchy = UpgradeLayoutToHierarchy,
    MAX_DEPTH = MAX_DEPTH,
    LAYOUT_VERSION = 3,
    UpgradeLayoutPlacement = UpgradeLayoutPlacement,
    ATTACH_EDGES = ATTACH_EDGES,
    NormalizeGroupName = NormalizeGroupName,
    GROUP_NAME_LENGTH = GROUP_NAME_LENGTH,
    MAX_GROUPS = MAX_GROUPS,
    componentAnchors = componentAnchors,
    VALUE_NAME_LENGTH = VALUE_NAME_LENGTH,
    TEMPLATE_LENGTH = TEMPLATE_LENGTH,
    NormalizeRules = NormalizeRules,
    NormalizeStyles = NormalizeStyles,
    GradientRules = GradientRules,
    MIN_BLEND_STOPS = MIN_BLEND_STOPS,
    MAX_BLEND_STOPS = MAX_BLEND_STOPS,
    NormalizeStylePresets = NormalizeStylePresets,
    PRESET_KINDS = PRESET_KINDS,
    MAX_PRESETS = MAX_PRESETS,
    PresetName = PresetName,
    STYLE_OUTLINES = STYLE_OUTLINES,
    STYLE_PADDING = STYLE_PADDING,
    STYLE_BORDER = STYLE_BORDER,
    STYLE_DEFAULTS = STYLE_DEFAULTS,
    RULE_SETS = RULE_SETS,
    MAX_RULES_PER_PART = MAX_RULES_PER_PART,
    MAX_RULES = MAX_RULES,
    NormalizePartRules = NormalizePartRules,
    NormalizeValueTemplate = NormalizeValueTemplate,
    profileOrder = profileOrder,
    profileDefaults = profileDefaults,
    defaultRelationshipColours = defaultRelationshipColours,
    booleanSettings = booleanSettings,
    enumSettings = enumSettings,
    settingRanges = settingRanges,
    ENEMY_ALIASES = ENEMY_ALIASES,
    SettingValue = SettingValue,
    NormalizeLayout = NormalizeLayout,
    NormalizeColour = NormalizeColour,
    NormalizeProfile = NormalizeProfile,
    IsProfileOption = IsProfileOption,
    ProfileOptionValue = ProfileOptionValue,
    CopyEnemyProfile = CopyEnemyProfile,
    NormalizeSettings = NormalizeSettings,
}
