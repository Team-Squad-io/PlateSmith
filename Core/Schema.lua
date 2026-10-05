local _, PS = ...
local Format = assert(PS.Format, "PlateSmith Format missing")
local Template = assert(PS.Template, "PlateSmith Template missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local Media = assert(PS.Media, "PlateSmith Media missing")

local defaults = {
    schemaVersion = 29,
    enabled = true,
    mode = "auto",       -- auto, own, overlay
    friendly = "names",  -- names, full, off
    hideUnstyledFriendlyNames = true,
    friendlyRelationshipColours = true,
    -- off, colour, icon, both. New profiles colour the name too (Blizzard's green, relationshipColours.pvp):
    -- the icon alone is hard to see. Saved profiles keep their own (1.1.x's default was icon).
    friendlyPvpStyle = "both",
    restrictedFriendlyNamesOnly = true,
    restrictedFriendlyClassColour = false,
    experimentalDungeonFriendlyText = false,
    showPlayerSurnames = true,
    -- A cast on a names-only plate: a small bar under the name, namesOnlyCastWidth wide. Friendly:
    -- names-only friendly plates; enemy: enemy plates whose layout hides the health and cast bars.
    -- namesOnlyCastText: the spell's name and time under the bar, or inside it.
    namesOnlyCastFriendly = false, namesOnlyCastEnemy = false, namesOnlyCastWidth = 90, namesOnlyCastText = "under",
    showGroupIcon = true,
    showGuildIcon = true,
    classificationStyle = "icon", -- icon (Blizzard's nameplate icons), words, letters
    -- Whose quest icons show: auto (Questie's when Questie shows nameplate icons, else
    -- PlateSmith's), platesmith, or questie (PlateSmith's step aside while Questie is loaded).
    questIcons = "auto",
    -- An enemy plate's health bar edge turns red while you tank and lose that mob.
    tankWarning = true,
    -- Threat colours (Nameplates/ThreatColours.lua): an enemy's parts in the colour for its threat
    -- state while it is in combat with you or your group. Role auto follows role.tank; the parts
    -- ticked here take the shared colours (threatColours) or their own (threatPartColours); Safe
    -- keeps the part's own colour while threatColourSafeKeep is on. Saved profiles from before it
    -- start with it off (migration 27).
    colourByThreat = true, threatColourRole = "auto", threatColourSafeKeep = false,
    threatColourHealth = true, threatColourName = true, threatColourBorder = false,
    -- The target-of-target name hides while that unit targets you (it would say your name).
    targetNameHideSelf = true,
    buffSource = "all",       -- all, mine
    debuffSource = "mine",   -- all, mine
    -- Blizzard's own plate names, drawn with its shared nameplate font objects (Nameplates/NativeFonts.lua):
    -- readable outdoors (nativeNameFont), and the opt-in chosen font where blizzardNameFontScope says.
    nativeNameFont = true,
    blizzardNameFont = false,
    blizzardNameFontScope = "instances", -- instances (dungeons and raids), everywhere
    blizzardNameFontSize = 12,
    blizzardNameFontOutline = "outline", -- none, outline, thick
    blizzardNameFontFace = "default", -- default (each object's own Blizzard face) or a PS.Media font
    scale = 1,
    width = 112,
    healthHeight = 10,
    nameFontSize = 14,
    -- Every PlateSmith text on every plate type drawn at this times its own size.
    textScale = 1,
    threatSpotlightStyle = "glow", -- glow, arrow, sides, box, both
    targetHighlightStyle = "border", -- off, border, halo, glow
    -- The glow style (Nameplates/TargetGlow.lua): a soft cloud of light behind the target's whole plate
    -- in the unit's class or reaction colour, or targetGlowColour; how far it reaches past the plate (px),
    -- its opacity, and an optional slow pulse. A changed glow default needs no migration: every profile
    -- that could show the glow holds its glow values (profiles are stored whole once loaded), so only new
    -- profiles take it.
    targetGlowColourMode = "custom", targetGlowColour = { r = 0.1, g = 0.8, b = 0.9 },
    targetGlowSpread = 56, targetGlowOpacity = 0.6, targetGlowPulse = false,
    -- How far the whole glow is moved from the plate (px, right and up); 0 keeps it centred.
    targetGlowOffsetX = 0, targetGlowOffsetY = 0,
    threatSpotlightOthersAlpha = 0.55,
    threatSpotlightDuration = 3,
    threatPalette = "auto", -- auto (follows the colorblindMode CVar), standard, colourblind
    threatTextFormat = "gap", -- the plates' threat text: gap (% and signed gap), percent, detailed (lead % and raw)
    -- A gap read through a borrowed token (target, hover, focus...) is kept once it moves on: for
    -- threatKeptHold seconds ("until": while the same mob lives), dimmed, fading with age or grey
    -- (threatKeptStyle), with its age after it while threatKeptAge is on.
    threatKeptHold = "5", threatKeptStyle = "dim", threatKeptAge = false,
    -- Settings › Experimental: tests of what the game allows, each off by default.
    experimentalSoftTargetThreat = false, experimentalTargetOfTargetThreat = false,
    experimentalSoloCurveGap = false, experimentalOutsideHolderRow = false,
    font = "default", -- default (Blizzard's multilingual nameplate font) or lsm:<name>
}

-- Where plates show (Nameplates/Visibility.lua): per plate type, a switch for each kind of place
-- (shown<Type><Place>, on by default) and when in combat (shown<Type>Combat: always, combat,
-- noCombat, never). Every cell at its default writes nothing.
local VISIBILITY = { TYPES = { "enemy", "friendlyPlayer", "friendlyNPC" }, PLACES = { "world", "dungeon", "pvp", "city" },
    COMBAT = { "always", "combat", "noCombat", "never" }, KEYS = {}, keys = {} }
do
    local function Cap(text) return text:sub(1, 1):upper() .. text:sub(2) end
    for _, plateType in ipairs(VISIBILITY.TYPES) do
        VISIBILITY.keys[plateType] = {}
        for _, place in ipairs(VISIBILITY.PLACES) do
            local key = "shown" .. Cap(plateType) .. Cap(place)
            VISIBILITY.keys[plateType][place], defaults[key] = key, true
            VISIBILITY.KEYS[#VISIBILITY.KEYS + 1] = key
        end
        local key = "shown" .. Cap(plateType) .. "Combat"
        VISIBILITY.keys[plateType].combat, defaults[key] = key, "always"
        VISIBILITY.KEYS[#VISIBILITY.KEYS + 1] = key
    end
end

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
-- An unused custom part: off, white 11 pt text on the health bar. Blueprints leave slots like
-- this out.
local DEFAULT_VALUE_SLOT = { source = "off", anchor = "health", layer = "front", whenMissing = "fallback", fontSize = 11,
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

-- Rules: per part, an ordered list of { when = condition, set = what, colour | alpha | stops[, enabled] },
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
                -- enabled: on unless false. A rule turned off stays in the list and never applies.
                if rule.enabled == false then entry.enabled = false end
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
    spacing = { 0, 6, true }, timeSize = { 30, 90, true } }
local auraGrowX = { right = true, left = true, centre = true }
local auraGrowY = { up = true, down = true }
-- A text's outline (a part's style, and an aura row's countdown): none, outline or thick.
local STYLE_OUTLINES = { none = true, outline = true, thick = true }
-- A text part's Font size in points (before the profile's text size); nil is Auto, the size the plate
-- gives it (PartTextSize), as before. An aura row's countdown (timeFontSize) takes the same range.
local STYLE_FONT_SIZE = { 6, 32, true }
-- The countdown text's font (timeFont, a media key), outline (timeOutline) and shadow (timeShadow):
-- each optional. Absent: the plate font (Friz Quadrata while that is Blizzard's), outlined, and the
-- client's own shadow. Where it sits (timePosition): centred on the icon's bottom edge (absent),
-- its middle or its top edge, or the bottom right corner it used to take.
local auraTimeFields = { timeFont = true, timeOutline = true, timeShadow = true, timePosition = true, timeFontSize = true }
local auraTimePositions = { bottom = true, centre = true, top = true, bottomright = true }
local defaultAuraLayouts = {
    -- Both rows sit above the name, centred on it, and further lines grow away from it.
    buffs = { count = 4, columns = 4, size = 18, spacing = 2, growX = "centre", growY = "up", showDuration = true, timeSize = 45 },
    debuffs = { count = 4, columns = 4, size = 18, spacing = 2, growX = "centre", growY = "up", showDuration = true,
        timeSize = 45 },
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
        row.timeFont = Media.IsFont(layout.timeFont) and layout.timeFont or nil
        row.timeOutline = STYLE_OUTLINES[layout.timeOutline] and layout.timeOutline or nil
        if type(layout.timeShadow) == "boolean" then row.timeShadow = layout.timeShadow end
        row.timePosition = auraTimePositions[layout.timePosition] and layout.timePosition or nil
        -- Timed only: the row skips auras with no time limit; absent (off) shows them all.
        if layout.timedOnly == true then row.timedOnly = true end
        local points = tonumber(layout.timeFontSize)
        if points and points == points then
            row.timeFontSize = math.floor(math.max(STYLE_FONT_SIZE[1], math.min(STYLE_FONT_SIZE[2], points)) + 0.5)
        end
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
    -- The name 19 px up: the quest mark (18 px at the 14 pt name) beside it stays clear of the raid
    -- mark (20 px) beside the bar under any name length.
    name = { 0, 19 }, health = { 0, 0 }, cast = { 0, -13 },
    -- Under the bars in the Bars stack (AddTemplateStacks), closing up while a bar is idle. Their own
    -- offsets (where Studio draws a turned-off one) are their stacked places under the cast bar and the
    -- combo points.
    guild = { 0, -42 }, threat = { 0, -42 }, targetName = { 0, -58 },
    level = { -3, 0, "name", "left" }, quest = { -2, 0, "level", "left" }, pvpIcon = { -2, 0, "level", "left" },
    relationshipIcon = { 3, 0, "name", "right" },
    raidIcon = { -4, 0, "health", "left" }, classification = { 4, 0, "health", "right" },
    -- TAGGED after the classification mark, so a long word ("Rare elite") never runs under it;
    -- on a mob without one it takes the mark's place beside the bar.
    tagged = { 4, 0, "classification", "right" },
    -- Above the name in the Auras stack: debuffs nearest, buffs above them.
    debuffs = { 0, 37 }, buffs = { 0, 57 },
    -- Combo points (your target's plate only): placed here, then moved into the Bars stack under the
    -- cast bar (ComboInStack). This spot is LEGACY_ENTRIES' (where layouts saved before 1.2.0 have them).
    combo = { 0, 2, "health", "top" },
    -- "Targeted by" badges (off by default): beside the bar, left of the raid mark (meeting the bar
    -- when there is none), on the bar's line, clear of the name line above it.
    targetedBy = { -2, 0, "raidIcon", "left" },
}
local NAMES_POSITIONS = {
    -- 3 px: clear of a 20 px raid mark beside a short name, over the guild line's wider text.
    name = { 0, 0 }, guild = { 0, -3, "name", "bottom" },
    level = { -3, 0, "name", "left" }, quest = { -2, 0, "level", "left" }, pvpIcon = { -2, 0, "level", "left" },
    relationshipIcon = { 3, 0, "name", "right" }, raidIcon = { 22, 0, "name", "right" },
    classification = { 43, 0, "name", "right" }, tagged = { 64, 0, "name", "right" },
    health = { 0, -29 }, cast = { 0, -42 }, threat = { 0, -55 }, targetName = { 0, -30 },
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
    raidIcon = true, classification = true, level = true, buffs = true, debuffs = true, combo = true })

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
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 14,
        healthTexture = "blizzard", healthColourMode = "automatic",
        healthColour = { r = 0.85, g = 0.12, b = 0.1 },
        layout = defaultLayout,
        -- A new profile's own part styles (NormalizeProfiles' fresh): gold round coins with a soft glow,
        -- shown in combat or with points (an empty row at rest stays hidden). Saved profiles never take
        -- these (their styles are their own).
        styles = { combo = { pipShape = "round", pipWidth = 9, pipSpacing = 3, pipGlow = true,
            pipFill = { r = 1, g = 0.78, b = 0.15, a = 1 }, pipShowRow = "combat" } },
    },
    friendlyPlayer = {
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 14,
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
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 14,
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
-- castInterruptColours colours the bar by your interrupt (castColours); castOnTop draws a casting
-- plate over its neighbours (under the target and focus). The quest mark's progress text ("3/8" or
-- "50%") rides here too: off, beside the mark, or in its place, as a count or a percentage.
local castOptions = { castIcon = { left = true, right = true, off = true }, castTime = "boolean", castName = "boolean",
    castInterruptColours = "boolean", castOnTop = "boolean",
    questProgress = { off = true, beside = true, instead = true }, questProgressFormat = { count = true, percent = true } }
local castDefaults = { castIcon = "left", castTime = true, castName = true, castInterruptColours = false, castOnTop = false,
    questProgress = "off", questProgressFormat = "count" }
-- The cast bar's own colour, and Colour by interrupt's: ready (it can be interrupted and your
-- interrupt is ready), cooldown (it can, but yours is on cooldown or you have none), locked (it cannot).
local CAST_COLOUR = { r = 0.95, g = 0.68, b = 0.16 }
local CAST_COLOUR_KEYS = { "ready", "cooldown", "locked" }
local castColourDefaults = { ready = { r = 0.25, g = 0.85, b = 0.35 }, cooldown = { r = 0.9, g = 0.3, b = 0.2 },
    locked = { r = 0.55, g = 0.55, b = 0.55 } }

for profileKey, profile in pairs(profileDefaults) do
    for key, value in pairs(castDefaults) do profile[key] = value end
    profile.castColours = Table.DeepCopy(castColourDefaults)
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
    -- Blizzard's own (BLIZZARD_PVP_GREEN, below). Saved profiles keep theirs (1.1.x's default: 1, 0.56, 0.2).
    pvp = { r = 0, g = 1, b = 0 },
}

-- Threat colours' states (a tank's four, then a DPS or healer's three), their default colours, and
-- the parts they can colour. A part's own colours (threatPartColours[part]) are kept only while
-- its Own colours is on; a state it lacks takes the shared colour.
local THREAT_COLOURS = {
    STATES = { "holding", "losing", "offtank", "other", "safe", "pulling", "aggro" },
    PARTS = { "health", "name", "border" },
    defaults = {
        holding = { r = 0.5, g = 0.5, b = 1 }, losing = { r = 1, g = 1, b = 0 },
        offtank = { r = 0.73, g = 0.92, b = 1 }, other = { r = 1, g = 0, b = 0 },
        safe = { r = 0.3, g = 0.8, b = 0.3 }, pulling = { r = 1, g = 0.6, b = 0 }, aggro = { r = 1, g = 0.1, b = 0.45 },
    },
}
THREAT_COLOURS.isPart = {}
for _, part in ipairs(THREAT_COLOURS.PARTS) do THREAT_COLOURS.isPart[part] = true end

local validModes = { auto = true, own = true, overlay = true }
local validFriendlyModes = { names = true, full = true, off = true }
local validFriendlyPvpStyles = { off = true, colour = true, icon = true, both = true }
local validAuraSources = { all = true, mine = true }
local validClassificationStyles = { icon = true, words = true, letters = true }
local validQuestIcons = { auto = true, platesmith = true, questie = true }
local validThreatPalettes = { auto = true, standard = true, colourblind = true }
local validThreatTextFormats = { gap = true, percent = true, detailed = true }
local validThreatKeptHolds = { ["5"] = true, ["10"] = true, ["15"] = true, ["30"] = true, ["until"] = true }
local validThreatKeptStyles = { dim = true, fade = true, grey = true }
local validThreatSpotlightStyles = { glow = true, arrow = true, sides = true, box = true, both = true }
local validTargetHighlightStyles = { off = true, border = true, halo = true, glow = true }
local validTargetGlowColourModes = { class = true, reaction = true, custom = true, threat = true }
local validBlizzardNameFontScopes = { instances = true, everywhere = true }
THREAT_COLOURS.roles = { auto = true, tank = true, dps = true }

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
local settingRanges = { threatSpotlightOthersAlpha = { 0.3, 1 }, threatSpotlightDuration = { 1, 8, true },
    textScale = { 0.8, 1.5 }, blizzardNameFontSize = { 8, 20, true }, namesOnlyCastWidth = { 50, 160, true },
    targetGlowSpread = { 8, 80, true }, targetGlowOpacity = { 0.1, 1 }, targetGlowOffsetX = { -40, 40, true },
    targetGlowOffsetY = { -40, 40, true } }
-- General settings that are one colour ({ r, g, b }): exported as hex, imported through CheckColour.
local colourSettings = { targetGlowColour = true }
-- The soft target glow's own look: a change restyles only the glow on the plate showing it
-- (TargetGlow.RestyleShown), with no plate laid out again (Settings.SetOption).
local glowSettings = { targetGlowColourMode = true, targetGlowColour = true, targetGlowSpread = true,
    targetGlowOpacity = true, targetGlowPulse = true, targetGlowOffsetX = true, targetGlowOffsetY = true }
local ENEMY_ALIASES = { scale = true, width = true, healthHeight = true, nameFontSize = true }
-- Component positions on the preview canvas, and per-component scale.
local layoutRanges = { x = { -280, 280, true }, y = { -105, 105, true }, scale = { 0.5, 2 } }

-- Every general setting has one of these validators (or colourSettings, or is font,
-- relationshipColours, the threat colour tables or an enemy alias). Blueprints share all of them
-- except enabled.
local booleanSettings = {
    "enabled", "hideUnstyledFriendlyNames", "friendlyRelationshipColours", "restrictedFriendlyNamesOnly",
    "restrictedFriendlyClassColour", "experimentalDungeonFriendlyText", "showPlayerSurnames", "showGroupIcon",
    "showGuildIcon", "nativeNameFont", "targetNameHideSelf", "tankWarning", "blizzardNameFont",
    "threatKeptAge", "experimentalSoftTargetThreat", "experimentalTargetOfTargetThreat", "experimentalSoloCurveGap",
    "experimentalOutsideHolderRow", "namesOnlyCastFriendly", "namesOnlyCastEnemy",
    "colourByThreat", "threatColourSafeKeep", "threatColourHealth", "threatColourName", "threatColourBorder",
    "targetGlowPulse",
}
local enumSettings = {
    mode = validModes, friendly = validFriendlyModes, friendlyPvpStyle = validFriendlyPvpStyles,
    buffSource = validAuraSources, debuffSource = validAuraSources, classificationStyle = validClassificationStyles,
    questIcons = validQuestIcons, targetHighlightStyle = validTargetHighlightStyles,
    namesOnlyCastText = { under = true, inside = true },
    threatSpotlightStyle = validThreatSpotlightStyles, threatPalette = validThreatPalettes,
    threatTextFormat = validThreatTextFormats, threatKeptHold = validThreatKeptHolds, threatKeptStyle = validThreatKeptStyles,
    blizzardNameFontScope = validBlizzardNameFontScopes,
    blizzardNameFontOutline = { none = true, outline = true, thick = true },
    threatColourRole = THREAT_COLOURS.roles, targetGlowColourMode = validTargetGlowColourModes,
}
do
    local combatChoices = {}
    for _, choice in ipairs(VISIBILITY.COMBAT) do combatChoices[choice] = true end
    for _, plateType in ipairs(VISIBILITY.TYPES) do
        local keys = VISIBILITY.keys[plateType]
        for _, place in ipairs(VISIBILITY.PLACES) do booleanSettings[#booleanSettings + 1] = keys[place] end
        enumSettings[keys.combat] = combatChoices
    end
end
local isBooleanSetting = {}
for _, key in ipairs(booleanSettings) do isBooleanSetting[key] = true end

-- The first candidate that converts to a number (not NaN), clamped to range (and
-- rounded for whole-number ranges). The last candidate is always a default.
local function Bounded(range, ...)
    local value
    for index = 1, select("#", ...) do
        value = tonumber((select(index, ...)))
        if value and value == value then break end
        value = nil
    end
    value = math.max(range[1], math.min(range[2], value or range[1]))
    return range[3] and math.floor(value + 0.5) or value
end

-- True only for a real number inside range (and whole, for whole-number ranges).
local function InRange(range, value)
    return type(value) == "number" and value == value and value >= range[1] and value <= range[2]
        and (not range[3] or value == math.floor(value))
end

-- A plate text's drawn size: its own size times the profile's text size (textScale), in whole
-- points within DRAWN_FONT_RANGE.
local DRAWN_FONT_RANGE = { 6, 32, true }
local function ScaledFontSize(size, textScale)
    return Bounded(DRAWN_FONT_RANGE, (tonumber(size) or 12) * Bounded(settingRanges.textScale, textScale, 1))
end

-- A text part's size: its style's Font size in points, or (Auto) the size the plate gives it.
local function StyledFontSize(size, style)
    local points = type(style) == "table" and tonumber(style.fontSize)
    return points or size
end

-- Auto Font size: the size the plate gives a part's text, from this plate type's name size (the
-- name's own; the level, guild, target, threat, elite mark, quest progress and combo count 2 pt less,
-- at least 8; the tagged mark 3 less; the cast bar's text 4 less, at least 7). Nil for a part whose
-- size follows something else (a badge, an aura icon). Lifecycle, Studio and the tests agree on it.
local PART_TEXT_SIZES = { level = { 8, -2 }, guild = { 8, -2 }, targetName = { 8, -2 }, threat = { 8, -2 },
    classification = { 8, -2 }, quest = { 8, -2 }, combo = { 8, -2 }, tagged = { 8, -3 }, cast = { 7, -4 } }
local function PartTextSize(key, nameFontSize)
    local size = tonumber(nameFontSize) or 14
    if key == "name" then return size end
    local rule = PART_TEXT_SIZES[key]
    return rule and math.max(rule[1], size + rule[2]) or nil
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

-- Sorts keys (entries of layout) in place into tree order: by each entry's order (unset:
-- fallback, 99 by default), then by key. Returns keys.
local function SortByTreeOrder(layout, keys, fallback)
    fallback = fallback or 99
    table.sort(keys, function(left, right)
        local a, b = layout[left].order or fallback, layout[right].order or fallback
        if a ~= b then return a < b end
        return left < right
    end)
    return keys
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
        local keys, children = {}, {}
        for key, position in pairs(layout) do
            if type(position) == "table" and position.parent == parentKey and not position.free
                and position.visible ~= false and not position.removed then
                keys[#keys + 1] = key
            end
        end
        for _, key in ipairs(SortByTreeOrder(layout, keys)) do
            -- measure(key) -> width, height[, hidden[, boxX, boxY]]: box* is the drawn box's
            -- centre from the part's own centre (an aura grid's further lines), own units.
            local width, height, hidden, boxX, boxY = measure(key)
            if width and height then
                children[#children + 1] = { key = key, width = width, height = height, hidden = hidden,
                    boxX = tonumber(boxX) or 0, boxY = tonumber(boxY) or 0 }
            end
        end
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
    for _, list in pairs(children) do SortByTreeOrder(layout, list) end
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
    { name = "Bars", members = { "health", "power", "cast" }, stack = "down", gap = 5 },
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

-- Combo points next in the health bar's stack after the part after (the cast bar in the template): the
-- stack makes room for the row at any shape and size and moves what is under it down, on your target's
-- plate only and only while the row shows; while nothing is cast the idle cast bar takes no room and
-- the row closes up under the health bar. Above the bar a larger shape met the name; on its edge, the
-- cast bar. The siblings are numbered in turn, so every place is its own.
local function ComboInStack(layout, after)
    local combo, anchor = layout.combo, layout[after]
    local group = anchor and anchor.parent and layout[anchor.parent]
    if not (combo and group and group.stack == "down") then return end
    local keys = {}
    for key, position in pairs(layout) do
        if position.parent == anchor.parent and key ~= "combo" then keys[#keys + 1] = key end
    end
    local order = 0
    for _, key in ipairs(SortByTreeOrder(layout, keys)) do
        order = order + 1
        layout[key].order = order
        if key == after then
            order = order + 1
            combo.order = order
        end
    end
    combo.parent, combo.attach, combo.free, combo.x, combo.y = anchor.parent, nil, nil, 0, 0
end

for _, profile in pairs(profileDefaults) do
    for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
        local layout = profile[field]
        if layout then
            AddDefaultGroups(layout, true)
            AddTemplateStacks(layout)
            ComboInStack(layout, "cast")
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

-- One layout entry made valid (position: any table); nil without a usable x and y.
local function NormalizeLayoutEntry(key, position)
    local x, y = tonumber(position.x), tonumber(position.y)
    if not (x and y) then return nil end
    -- Only layouts from before Dynamic placement carry followName (their upgrade
    -- reads it); it is never added.
    local followName
    if key == "level" and position.followName ~= nil then followName = position.followName ~= false end
    local entry = {
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
    if entry.removed then entry.visible = false end
    if IsGroupKey(key) then
        entry.name = NormalizeGroupName(position.name) or "Group"
        entry.order = math.floor(tonumber(position.order) or 0)
    elseif type(position.name) == "string" then
        -- A built-in part's own name in Studio's tree (nil: its standard name).
        entry.name = NormalizeGroupName(position.name)
    end
    return entry
end

-- Where an existing layout without the entry gets it: the spot the template had for it before it
-- moved (combo points above the health bar until 1.2.0). Every layout since has the entry, so one
-- without it was saved (or shared) before, and keeps drawing it where it did.
local LEGACY_ENTRIES = { combo = { x = 0, y = 2, parent = "health", attach = "top" } }

-- key's scale as drawn: its own times every parent's (layout entries only, never a frame's size).
local function DrawnScale(layout, key)
    local scale, depth = 1, 0
    while type(layout) == "table" and type(layout[key]) == "table" and depth <= MAX_DEPTH do
        scale = scale * (tonumber(layout[key].scale) or 1)
        key, depth = layout[key].parent, depth + 1
    end
    return scale
end

-- The width a fitted combo row spans, in the row's own units: the health bar's (the profile's width,
-- never a measured frame) at its drawn scale over the row's, so the part's Scale and its parents'
-- leave the span exact.
local function PipFitWidth(profile, layout)
    local width = tonumber(type(profile) == "table" and profile.width) or 112
    local row = DrawnScale(layout, "combo")
    if row <= 0 then return width end
    return width * DrawnScale(layout, "health") / row
end

local function NormalizeLayout(layout, fallbackLayout)
    fallbackLayout = fallbackLayout or defaultLayout
    local normalized = {}
    if type(layout) == "table" then
        for key, position in pairs(layout) do
            if PartKey(key) and type(position) == "table" then
                normalized[key] = NormalizeLayoutEntry(key, position)
            end
        end
    end
    -- Missing parts come from the fallback with their place in its tree; a new layout takes all
    -- its groups (the default template), an existing one only a group a copied part sits in.
    local fresh = next(normalized) == nil
    local function Copy(key, position, shown)
        normalized[key] = { x = position.x, y = position.y, visible = (shown or position).visible ~= false,
            scale = ComponentScale(position.scale),
            parent = position.parent, order = position.order, stack = position.stack, gap = position.gap,
            layer = position.layer, attach = position.attach }
        normalized[key].name = position.name
    end
    for key, position in pairs(fallbackLayout) do
        if not normalized[key] and (fresh or not IsGroupKey(key)) then
            local legacy = not fresh and LEGACY_ENTRIES[key]
            if legacy then Copy(key, legacy, position) else Copy(key, position) end
        end
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

-- The shared threat colours with every state.
function THREAT_COLOURS.Normalize(colours)
    colours = type(colours) == "table" and colours or {}
    local result = {}
    for _, state in ipairs(THREAT_COLOURS.STATES) do
        result[state] = NormalizeColour(colours[state], THREAT_COLOURS.defaults[state])
    end
    return result
end

-- Parts' own threat colours: known parts only, each with every state (one it lacks from shared).
function THREAT_COLOURS.NormalizeParts(parts, shared)
    local result = {}
    if type(parts) ~= "table" then return result end
    for _, part in ipairs(THREAT_COLOURS.PARTS) do
        local own = parts[part]
        if type(own) == "table" then
            local colours = {}
            for _, state in ipairs(THREAT_COLOURS.STATES) do colours[state] = NormalizeColour(own[state], shared[state]) end
            result[part] = colours
        end
    end
    return result
end

-- Colour by interrupt's three colours, each made valid (a new table; fallback: the profile's defaults).
local function NormalizeCastColours(colours, fallback)
    colours = type(colours) == "table" and colours or {}
    fallback = type(fallback) == "table" and fallback or castColourDefaults
    local normalized = {}
    for _, key in ipairs(CAST_COLOUR_KEYS) do
        normalized[key] = NormalizeColour(colours[key], fallback[key] or castColourDefaults[key])
    end
    return normalized
end

-- Styles: per part, how it is drawn beyond position and size. Text parts: font (a media key;
-- nil is the plates' font), font size (a percentage), outline, shadow, and an optional box behind the text (fill,
-- border, padding). Bars: texture, background, border. Pips (combo points): the filled and empty
-- colours, each pip's size and the gap between them. Everything is optional; nil keeps the
-- part as it draws today. Colour by health is a blend rule: an older style's gradient becomes
-- one (GradientRules) and is not kept.
local STYLE_PADDING, STYLE_BORDER = { 0, 12, true }, { 0, 4, true }
-- The box's shape: square (nil, the fill and 1 px border every profile has had) or rounded (Blizzard's
-- own nameplate level box, drawn in its own colours).
local STYLE_BOX_SHAPES = { square = true, rounded = true }

-- Pips (combo points): each pip's width and height and the gap between them, in pixels. Five pips
-- up to 40 px wide span the widest health bar (200 px) with no gap, so Width, not the part's Scale,
-- sizes a row to any bar. (1.1.1 knew 24, 12 and 8: Blueprint exports a larger one as version 4.)
local STYLE_PIPS = { pipWidth = { 4, 40, true }, pipHeight = { 2, 16, true }, pipSpacing = { 0, 12, true } }
-- A pip's shape (nil: the bordered blocks every profile has had) and where the row sits: nil where
-- the layout places it, or on the health bar (edge: centred on its bottom edge; above; below).
-- pipClassColour fills with your class colour and pipGlow lights the filled ones (true or nil).
-- pipFit (true or nil) makes the row exactly as wide as the health bar (PipRow).
local STYLE_PIP_SHAPES = { round = true, square = true, diamond = true, segments = true, blizzard = true }
local STYLE_PIP_ANCHORS = { edge = true, above = true, below = true }
-- When the row shows on your target (ComboPoints.EmptyHidden): nil Always (empty pips at 0, every style
-- before it), combat (in combat or with points), points (only with points).
local STYLE_PIP_SHOW_ROWS = { combat = true, points = true }
-- Badges ("Targeted by"): each badge's size and the gap, in pixels; the row's direction; and whether
-- a badge shows its member's initial (nil: yes).
local STYLE_BADGES = { badgeSize = { 6, 20, true }, badgeSpacing = { 0, 8, true } }
local STYLE_BADGE_ORIENTATIONS = { horizontal = true, vertical = true }
-- What an unset field draws as, on the plates, in Studio's preview and in the inspector. Read only.
local STYLE_DEFAULTS = {
    boxColour = { r = 0, g = 0, b = 0, a = 0.65 },
    boxBorder = { r = 0.78, g = 0.62, b = 0.3, a = 1 },
    padding = 3,
    background = { r = 0.025, g = 0.025, b = 0.025, a = 0.92 },
    pipFill = { r = 1, g = 0.8, b = 0.1, a = 1 },
    pipEmpty = { r = 0.12, g = 0.12, b = 0.12, a = 0.8 },
    pipWidth = 10, pipHeight = 4, pipSpacing = 2,
    badgeSize = 10, badgeSpacing = 2, badgeOrientation = "horizontal", badgeInitial = true,
}

-- A row of count pips in style, as ComboPoints.StylePips draws it (tests measure it the same way):
-- each pip's width and height, the gap, and the row's width. A shape other than blocks or segments is
-- as tall as it is wide. With pipFit, fitWidth (PipFitWidth) is the row's width: blocks and segments
-- widen to fill it (their gap kept); other shapes keep their size and spread out (the gap grows,
-- never below 0, so pips too large to fit make a row wider than the bar).
local function PipRow(style, count, fitWidth)
    style = type(style) == "table" and style or STYLE_DEFAULTS
    count = math.max(1, math.floor(tonumber(count) or 5))
    local width = style.pipWidth or STYLE_DEFAULTS.pipWidth
    local height = style.pipHeight or STYLE_DEFAULTS.pipHeight
    local spacing = style.pipSpacing or STYLE_DEFAULTS.pipSpacing
    local even = style.pipShape ~= nil and style.pipShape ~= "segments"
    if even then height = width end
    if style.pipFit and type(fitWidth) == "number" and fitWidth > 0 then
        if not even then
            width = math.max(1, (fitWidth - (count - 1) * spacing) / count)
        elseif count > 1 then
            spacing = math.max(0, (fitWidth - count * width) / (count - 1))
        end
    end
    return width, height, spacing, count * width + (count - 1) * spacing
end
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
                pipFill = StyleColour(style.pipFill),
                pipEmpty = StyleColour(style.pipEmpty),
            }
            entry.fontSize = tonumber(style.fontSize) and Bounded(STYLE_FONT_SIZE, style.fontSize) or nil
            for field, range in pairs(STYLE_PIPS) do
                entry[field] = tonumber(style[field]) and Bounded(range, style[field]) or nil
            end
            for field, range in pairs(STYLE_BADGES) do
                entry[field] = tonumber(style[field]) and Bounded(range, style[field]) or nil
            end
            entry.badgeOrientation = STYLE_BADGE_ORIENTATIONS[style.badgeOrientation] and style.badgeOrientation or nil
            entry.pipShape = STYLE_PIP_SHAPES[style.pipShape] and style.pipShape or nil
            entry.boxShape = style.boxShape == "rounded" and "rounded" or nil
            entry.pipAnchor = STYLE_PIP_ANCHORS[style.pipAnchor] and style.pipAnchor or nil
            entry.pipClassColour = style.pipClassColour == true or nil
            entry.pipGlow = style.pipGlow == true or nil
            entry.pipFit = style.pipFit == true or nil
            entry.pipShowRow = STYLE_PIP_SHOW_ROWS[style.pipShowRow] and style.pipShowRow or nil
            -- On, off, or nil for the plates' own shadow (false must survive, so not an and/or).
            if type(style.shadow) == "boolean" then entry.shadow = style.shadow end
            if type(style.badgeInitial) == "boolean" then entry.badgeInitial = style.badgeInitial end
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

-- Saved styles: at most 40, named (at most 24 characters), for text, bar or pip parts. A preset
-- holds a style (NormalizeStyles) and optionally rules (NormalizeRules).
local PRESET_KINDS, MAX_PRESETS, PRESET_NAME_LENGTH = { text = true, bar = true, pips = true, badges = true }, 40, 24
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

-- The target highlight (how your target's plate is lit) per design: each of these general settings may
-- also be a design's own profile option, which wins over it; absent (nil), the design draws with the
-- general setting, so a profile saved before they were per design looks as it did on every plate type.
-- Value: the design's own value made valid by the general setting's validator, or nil (none, or not
-- valid). Resolve fills out with what a design draws.
local HIGHLIGHT = { KEYS = { "targetHighlightStyle", "targetGlowColourMode", "targetGlowColour", "targetGlowSpread",
    "targetGlowOpacity", "targetGlowOffsetX", "targetGlowOffsetY", "targetGlowPulse" }, SET = {} }
for _, key in ipairs(HIGHLIGHT.KEYS) do HIGHLIGHT.SET[key] = true end
function HIGHLIGHT.Value(key, value)
    if value == nil or not HIGHLIGHT.SET[key] then return nil end
    if key == "targetGlowPulse" then
        if type(value) == "boolean" then return value end
        return nil
    end
    local allowed = enumSettings[key]
    if allowed then return allowed[value] and value or nil end
    local range = settingRanges[key]
    if range then
        local number = tonumber(value)
        if number and number == number then return Bounded(range, number) end
        return nil
    end
    if colourSettings[key] and type(value) == "table" then return NormalizeColour(value, defaults[key]) end
    return nil
end
function HIGHLIGHT.Resolve(db, profile, out)
    out = out or {}
    for _, key in ipairs(HIGHLIGHT.KEYS) do
        -- (Not and/or: Pulse's false must survive.)
        local own
        if type(profile) == "table" then own = profile[key] end
        if own == nil and type(db) == "table" then own = db[key] end
        if own == nil then own = defaults[key] end
        out[key] = own
    end
    return out
end
-- Whether profile holds a highlight of its own (any key).
function HIGHLIGHT.Has(profile)
    if type(profile) ~= "table" then return false end
    for _, key in ipairs(HIGHLIGHT.KEYS) do
        if profile[key] ~= nil then return true end
    end
    return false
end

local function IsProfileOption(key)
    return profileRanges[key] ~= nil or optionalProfileRanges[key] ~= nil or key == "healthTexture"
        or key == "healthColourMode" or key == "castColours" or castOptions[key] ~= nil or HIGHLIGHT.SET[key] == true
end

-- One profile option made valid for profile (fallback: its defaults). NormalizeProfile checks
-- every option this way; Settings writes a single one.
local function ProfileOptionValue(profile, key, value, fallback)
    if HIGHLIGHT.SET[key] then return HIGHLIGHT.Value(key, value) end
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
    if key == "castColours" then return NormalizeCastColours(value, fallback.castColours) end
    local choices = castOptions[key]
    if choices then
        if choices == "boolean" and type(value) == "boolean" then return value end
        if choices ~= "boolean" and choices[value] then return value end
        if fallback[key] ~= nil then return fallback[key] end
        return castDefaults[key]
    end
    return nil
end

-- One custom part's record made valid (slot: anything; a missing one is an unused slot).
local function NormalizeValueSlot(slot)
    slot = type(slot) == "table" and slot or {}
    local base = DEFAULT_VALUE_SLOT
    return {
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

-- fresh: a new profile (NormalizeSettings' new table), which starts with the template's own part
-- styles (fallback.styles) unless it brings its own.
local function NormalizeProfile(profile, fallback, legacy, fresh)
    profile = type(profile) == "table" and profile or {}
    legacy = type(legacy) == "table" and legacy or {}
    if fresh and profile.styles == nil and fallback.styles then profile.styles = Table.DeepCopy(fallback.styles) end
    local previousLayout = profile.layout or legacy.layout
    for key, range in pairs(profileRanges) do
        profile[key] = Bounded(range, profile[key], legacy[key], fallback[key])
    end
    for key in pairs(optionalProfileRanges) do profile[key] = ProfileOptionValue(profile, key, profile[key], fallback) end
    for _, key in ipairs({ "healthTexture", "healthColourMode" }) do
        profile[key] = ProfileOptionValue(profile, key, profile[key], fallback)
    end
    for key in pairs(castOptions) do profile[key] = ProfileOptionValue(profile, key, profile[key], fallback) end
    for _, key in ipairs(HIGHLIGHT.KEYS) do profile[key] = HIGHLIGHT.Value(key, profile[key]) end
    profile.healthColour = NormalizeColour(profile.healthColour, fallback.healthColour)
    profile.castColours = NormalizeCastColours(profile.castColours, fallback.castColours)
    profile.valueSlots = type(profile.valueSlots) == "table" and profile.valueSlots or {}
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        profile.valueSlots[key] = NormalizeValueSlot(profile.valueSlots[key])
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
        castInterruptColours = source.castInterruptColours, castOnTop = source.castOnTop,
        castColours = NormalizeCastColours(source.castColours),
        questProgress = source.questProgress, questProgressFormat = source.questProgressFormat,
        healthColour = NormalizeColour(source.healthColour, profileDefaults.enemy.healthColour),
        layout = NormalizeLayout(source.layout, profileDefaults.enemy.layout),
        auraLayouts = NormalizeAuraLayouts(source.auraLayouts),
        rules = NormalizeRules(source.rules),
        styles = NormalizeStyles(source.styles),
        valueSlots = Table.DeepCopy(source.valueSlots),
    }
    for _, key in ipairs(HIGHLIGHT.KEYS) do copy[key] = Table.DeepCopy(source[key]) end
    return NormalizeProfile(copy, profileDefaults.enemy)
end

-- Context designs (Core/Designs.lua merges them): plateProfiles.<type>.contexts.<context> is a full
-- design ({ full = true, design = <whole profile> }, never inheriting) or a sparse one holding only
-- what differs from the plate type's World design (docs in Designs.lua). STORED: the contexts a
-- plate type may store one for. Friendly plates' Dungeons & raids design is their World
-- dungeonNamesLayout (Blizzard draws those plates), never a stored one.
local DESIGN = {
    ORDER = { "dungeon", "pvp", "city" },
    STORED = { enemy = { dungeon = true, pvp = true, city = true }, friendlyPlayer = { pvp = true, city = true },
        friendlyNPC = { pvp = true, city = true } },
    KNOWN = { world = true, dungeon = true, pvp = true, city = true },
    LAYOUT_FIELDS = { "layout", "namesLayout" },
    -- A layout entry's placement is one unit: offsets only make sense with their parent and pin.
    PLACEMENT = { "x", "y", "scale", "parent", "attach", "free", "stack", "gap", "layer", "order" },
    STYLE_FIELDS = { font = true, fontSize = true, outline = true, shadow = true, box = true, boxColour = true,
        boxBorder = true, padding = true, texture = true, background = true, border = true, borderColour = true,
        pipFill = true, pipEmpty = true, pipWidth = true, pipHeight = true, pipSpacing = true,
        pipShape = true, pipAnchor = true, pipClassColour = true, pipGlow = true, pipFit = true, pipShowRow = true,
        boxShape = true,
        badgeSize = true, badgeSpacing = true, badgeOrientation = true, badgeInitial = true },
    -- Entries per layout and style parts a sparse design may hold.
    MAX_ENTRIES = 64,
    -- "-" lists keys cleared (nil) here; PartKey's leading letter keeps it apart from every name.
    CLEAR = "-",
}

-- The keys of map that keep(key) accepts, sorted, at most limit of them: a bound that cuts the
-- same keys every time.
function DESIGN.Keys(map, keep, limit)
    local keys = {}
    for key in pairs(type(map) == "table" and map or {}) do
        if type(key) == "string" and keep(key) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for index = #keys, (limit or #keys) + 1, -1 do keys[index] = nil end
    return keys
end

-- A design's own value for a profile option, made valid; nil drops it (World's then applies).
function DESIGN.OptionValue(key, value, fallback)
    if HIGHLIGHT.SET[key] then return HIGHLIGHT.Value(key, value) end
    local range = profileRanges[key] or optionalProfileRanges[key]
    if range then
        local number = tonumber(value)
        return number and number == number and Bounded(range, number) or nil
    end
    if key == "healthTexture" then return Media.IsStatusBar(value) and value or nil end
    if key == "healthColourMode" then return (value == "custom" or value == "automatic") and value or nil end
    if key == "castColours" then return type(value) == "table" and NormalizeCastColours(value, fallback.castColours) or nil end
    local choices = castOptions[key]
    if choices == "boolean" then
        if type(value) == "boolean" then return value end
        return nil
    end
    if choices and choices[value] then return value end
    return nil
end

-- One layout entry's overrides in four sub-areas (placement, the eye, presence, the label), or a
-- group's tombstone (deleted) or an entry only this design has (added, with its placement).
function DESIGN.Entry(key, entry)
    if type(entry) ~= "table" then return nil end
    if entry.deleted == true then return IsGroupKey(key) and { deleted = true } or nil end
    local result = {}
    local placed = type(entry.placement) == "table" and NormalizeLayoutEntry(key, entry.placement)
    if placed then
        result.placement = {}
        for _, field in ipairs(DESIGN.PLACEMENT) do result.placement[field] = placed[field] end
    end
    if type(entry.visible) == "boolean" then result.visible = entry.visible end
    if type(entry.removed) == "boolean" then result.removed = entry.removed end
    -- false: the standard name.
    if entry.name == false or type(entry.name) == "string" then result.name = NormalizeGroupName(entry.name) or false end
    if entry.added == true then
        if not result.placement then return nil end
        result.added = true
    end
    return next(result) and result or nil
end

-- One aura row's overrides: valid fields only, and "-" for optional fields cleared here.
function DESIGN.AuraRow(row)
    if type(row) ~= "table" then return nil end
    local result = {}
    for key, range in pairs(auraLayoutRanges) do
        local number = tonumber(row[key])
        if number and number == number then result[key] = math.floor(math.max(range[1], math.min(range[2], number)) + 0.5) end
    end
    if auraGrowX[row.growX] then result.growX = row.growX end
    if auraGrowY[row.growY] then result.growY = row.growY end
    if type(row.showDuration) == "boolean" then result.showDuration = row.showDuration end
    if Media.IsFont(row.timeFont) then result.timeFont = row.timeFont end
    if STYLE_OUTLINES[row.timeOutline] then result.timeOutline = row.timeOutline end
    if type(row.timeShadow) == "boolean" then result.timeShadow = row.timeShadow end
    if auraTimePositions[row.timePosition] then result.timePosition = row.timePosition end
    if row.timedOnly == true then result.timedOnly = true end
    local points = tonumber(row.timeFontSize)
    if points and points == points then
        result.timeFontSize = math.floor(math.max(STYLE_FONT_SIZE[1], math.min(STYLE_FONT_SIZE[2], points)) + 0.5)
    end
    local clear = {}
    for field, flag in pairs(type(row[DESIGN.CLEAR]) == "table" and row[DESIGN.CLEAR] or {}) do
        if flag == true and (auraTimeFields[field] or field == "timedOnly") and result[field] == nil then clear[field] = true end
    end
    if next(clear) then result[DESIGN.CLEAR] = clear end
    return next(result) and result or nil
end

-- A sparse design made valid, as a new table: every area checked with the profile's own
-- validators, what is invalid dropped, counts bounded. nil when design is not a table.
local function NormalizeDesign(design, plateType)
    if type(design) ~= "table" then return nil end
    local fallback = profileDefaults[plateType] or profileDefaults.enemy
    local CLEAR = DESIGN.CLEAR
    local result = {}
    local options, cleared = {}, {}
    local saved = type(design.options) == "table" and design.options or {}
    for key, value in pairs(saved) do
        if key == "castOnNames" then
            -- Only false means anything: names-only plates here draw no cast bar.
            if value == false then options.castOnNames = false end
        elseif key == "healthColour" then
            if type(value) == "table" then options.healthColour = NormalizeColour(value, fallback.healthColour) end
        elseif type(key) == "string" and key ~= CLEAR and IsProfileOption(key) then
            options[key] = DESIGN.OptionValue(key, value, fallback)
        end
    end
    for key, flag in pairs(type(saved[CLEAR]) == "table" and saved[CLEAR] or {}) do
        -- Only an option that may be absent (a bar width that follows the health bar's) clears.
        if flag == true and (optionalProfileRanges[key] or HIGHLIGHT.SET[key]) and options[key] == nil
            and ProfileOptionValue({}, key, nil, fallback) == nil then
            cleared[key] = true
        end
    end
    if next(cleared) then options[CLEAR] = cleared end
    if next(options) then result.options = options end

    local layouts = {}
    for _, field in ipairs(DESIGN.LAYOUT_FIELDS) do
        local map = type(design.layouts) == "table" and design.layouts[field]
        if fallback[field] and type(map) == "table" then
            local entries = {}
            for _, key in ipairs(DESIGN.Keys(map, PartKey, DESIGN.MAX_ENTRIES)) do entries[key] = DESIGN.Entry(key, map[key]) end
            if next(entries) then layouts[field] = entries end
        end
    end
    if next(layouts) then result.layouts = layouts end

    local styles = {}
    for _, key in ipairs(DESIGN.Keys(design.styles, PartKey, DESIGN.MAX_ENTRIES)) do
        local savedStyle = design.styles[key]
        if type(savedStyle) == "table" then
            local style = NormalizeStyles({ [key] = savedStyle })[key] or {}
            local clear = {}
            for field, flag in pairs(type(savedStyle[CLEAR]) == "table" and savedStyle[CLEAR] or {}) do
                if flag == true and DESIGN.STYLE_FIELDS[field] and style[field] == nil then clear[field] = true end
            end
            if next(clear) then style[CLEAR] = clear end
            if next(style) then styles[key] = style end
        end
    end
    if next(styles) then result.styles = styles end

    -- A part's list replaces World's; {} means no rules on that part here.
    local rules = {}
    local partRules = {}
    for _, key in ipairs(DESIGN.Keys(design.rules, PartKey, DESIGN.MAX_ENTRIES)) do
        if type(design.rules[key]) == "table" then partRules[key] = design.rules[key] end
    end
    local normalized = NormalizeRules(partRules)
    for key in pairs(partRules) do rules[key] = normalized[key] or {} end
    if next(rules) then result.rules = rules end

    local slots = {}
    for key, slot in pairs(type(design.valueSlots) == "table" and design.valueSlots or {}) do
        local index = type(key) == "string" and tonumber(key:match("^value(%d+)$"))
        if index and index >= 1 and index <= VALUE_SLOT_COUNT and key == "value" .. index and type(slot) == "table" then
            slots[key] = NormalizeValueSlot(slot)
        end
    end
    if next(slots) then result.valueSlots = slots end

    local auras = {}
    for kind in pairs(defaultAuraLayouts) do
        auras[kind] = type(design.auraLayouts) == "table" and DESIGN.AuraRow(design.auraLayouts[kind]) or nil
    end
    if next(auras) then result.auraLayouts = auras end
    return result
end

-- A plate type's context designs made valid in place: a full design normalised against World (as
-- the dungeon override always was), a sparse one by NormalizeDesign. A known context this type may
-- not store, or anything that is not a table, goes; a table under an unknown key (a newer
-- version's context) is kept as it is. No designs: no contexts.
local function NormalizeContexts(profile, plateType)
    local contexts = profile.contexts
    if type(contexts) ~= "table" then profile.contexts = nil return end
    local stored = DESIGN.STORED[plateType] or {}
    for key, record in pairs(contexts) do
        if stored[key] then
            if type(record) ~= "table" then
                contexts[key] = nil
            elseif record.full == true then
                if type(record.design) == "table" then
                    for field in pairs(record) do if field ~= "full" and field ~= "design" then record[field] = nil end end
                    record.design = NormalizeProfile(record.design, profile)
                else
                    contexts[key] = nil
                end
            else
                contexts[key] = NormalizeDesign(record, plateType)
            end
        elseif DESIGN.KNOWN[key] or type(key) ~= "string" or type(record) ~= "table" then
            contexts[key] = nil
        end
    end
    if next(contexts) == nil then profile.contexts = nil end
end

local function NormalizeProfiles(profiles, legacy, fresh)
    profiles = type(profiles) == "table" and profiles or {}
    for _, key in ipairs(profileOrder) do
        profiles[key] = NormalizeProfile(profiles[key], profileDefaults[key], legacy, fresh)
        NormalizeContexts(profiles[key], key)
    end
    -- The Enemy players layer (Designs.lua): a sparse design over the Enemies'; an empty one stays
    -- (made in Studio, it changes nothing yet).
    profiles.enemy.players = NormalizeDesign(profiles.enemy.players, "enemy")
    -- Saved data from before schema 29 still holds the dungeon override here until migration 28
    -- moves it into the Enemies' contexts; older migrations normalise it where it is.
    if type(profiles.enemyDungeon) == "table" then
        profiles.enemyDungeon = NormalizeProfile(profiles.enemyDungeon, profiles.enemy)
    else
        profiles.enemyDungeon = nil
    end
    return profiles
end

-- Schema 28 kept the dungeon enemy override beside the plate types; it becomes the Enemies' full
-- Dungeons & raids design, unchanged, so it draws exactly as before. (Also run on a schema-29
-- profile a 1.1.x install edited after a downgrade: that newer edit wins.)
local function MoveDungeonOverride(settings)
    local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles
    if not profiles then return end
    if type(profiles.enemyDungeon) == "table" then
        profiles.enemy = type(profiles.enemy) == "table" and profiles.enemy or {}
        profiles.enemy.contexts = type(profiles.enemy.contexts) == "table" and profiles.enemy.contexts or {}
        profiles.enemy.contexts.dungeon = { full = true, design = profiles.enemyDungeon }
    end
    profiles.enemyDungeon = nil
end

-- Settings' Show on plates and Aura defaults boxes are shortcuts over the tree's eyes, not settings
-- of their own: each names its parts (the first is the one Studio's tree shows) and the plate
-- types that use them. The box reads those parts' eyes in the layouts those plate types use now
-- (EachLiveLayout, PartShownState) and sets them there (Settings' SetPartShownEverywhere); the
-- other layouts keep their own eyes. The aura rows are full-plate parts (names-only plates show
-- none by default, as Blizzard's do), so their boxes leave the names-only layouts alone.
-- A plate type's layout fields; dungeonNamesLayout is World's only (the friendly dungeon design).
local PLATE_LAYOUT_FIELDS = {
    enemy = { "layout" },
    enemyPlayer = { "layout" },
    friendlyPlayer = { "layout", "namesLayout", "dungeonNamesLayout" },
    friendlyNPC = { "layout", "namesLayout", "dungeonNamesLayout" },
}
-- Enemy players draw with the Enemies' designs plus their own layer (Designs.EachDesign visits it).
local ENEMY_PLATES = { enemy = true, enemyPlayer = true }
local THREAT_SOURCES = { threatPercent = true, leadPercent = true, rawThreat = true, differential = true }
-- sources: custom parts showing one of these values were kept off by the switch too.
local PART_SWITCHES = {
    { key = "quest", parts = { "quest", "questLoot" }, plates = { enemy = true, enemyPlayer = true, friendlyNPC = true } },
    { key = "showTagged", parts = { "tagged" }, plates = ENEMY_PLATES },
    { key = "threat", parts = { "threat" }, plates = ENEMY_PLATES, sources = THREAT_SOURCES },
    { key = "showClassification", parts = { "classification" }, plates = ENEMY_PLATES },
    { key = "showBuffs", parts = { "buffs" }, fullOnly = true,
        plates = { enemy = true, enemyPlayer = true, friendlyPlayer = true, friendlyNPC = true } },
    { key = "showDebuffs", parts = { "debuffs" }, fullOnly = true,
        plates = { enemy = true, enemyPlayer = true, friendlyPlayer = true, friendlyNPC = true } },
}
local partSwitches = {}
for _, switch in ipairs(PART_SWITCHES) do partSwitches[switch.key] = switch end

-- visit(layout, profile, field, plateType, context) for each layout of every design of plates (nil:
-- every plate type), World first (Designs.EachDesign). A sparse design's layouts are its effective,
-- read-only ones.
local function EachPlateLayout(settings, plates, visit)
    PS.Designs.EachDesign(settings, plates, function(profile, plateType, context)
        for _, field in ipairs(PLATE_LAYOUT_FIELDS[plateType]) do
            if (field ~= "dungeonNamesLayout" or context == "world") and type(profile[field]) == "table" then
                visit(profile[field], profile, field, plateType, context)
            end
        end
    end)
end

-- The layouts a switch's plate types draw with now, as Lifecycle's ApplyLayout picks them: every
-- enemy design's; a friendly design's full or names-only layout by the friendly setting (none
-- while friendly plates are off), and World's dungeon layout while the dungeon overlay is on.
-- visit(layout, profile, field, plateType, context, record) (record: a context design's, as EachDesign).
local function EachLiveLayout(settings, switch, visit)
    PS.Designs.EachDesign(settings, switch.plates, function(profile, plateType, context, record)
        local fields
        if ENEMY_PLATES[plateType] then
            fields = { "layout" }
        else
            fields = {}
            if settings.friendly == "full" then fields[1] = "layout"
            elseif settings.friendly == "names" and not switch.fullOnly then fields[1] = "namesLayout" end
            if settings.experimentalDungeonFriendlyText == true and not switch.fullOnly and context == "world" then
                fields[#fields + 1] = "dungeonNamesLayout"
            end
        end
        for _, field in ipairs(fields) do
            if type(profile[field]) == "table" then visit(profile[field], profile, field, plateType, context, record) end
        end
    end)
end
-- "all" when a switch's part is shown in every live layout that has it, "none" when in none,
-- "some" when they differ; nil for an unknown switch or when none has it (deleted, or no plate
-- type uses it now).
local function PartShownState(settings, key)
    local switch = partSwitches[key]
    if not switch then return nil end
    local shown, hidden = 0, 0
    EachLiveLayout(settings, switch, function(layout)
        local position = layout[switch.parts[1]]
        if type(position) == "table" and not position.removed then
            if position.visible == false then hidden = hidden + 1 else shown = shown + 1 end
        end
    end)
    if shown + hidden == 0 then return nil end
    if hidden == 0 then return "all" end
    return shown == 0 and "none" or "some"
end

-- Whether a rule reads threat: its condition names a token of TemplateReaders' threat kind
-- (threat.* and tanking). role.tank alone does not; it reads the player's role, not the threat
-- service. A condition that does not compile is read as text.
local function ConditionReadsThreat(node, depth)
    if type(node) ~= "table" or depth > 64 then return false end
    local token = node.token
    if type(token) == "string" and (token == "tanking" or token:sub(1, 7) == "threat.") then return true end
    local pair = node.both or node.either
    if type(pair) == "table" and (ConditionReadsThreat(pair[1], depth + 1) or ConditionReadsThreat(pair[2], depth + 1)) then
        return true
    end
    return ConditionReadsThreat(node.negate, depth + 1) or ConditionReadsThreat(node.truth, depth + 1)
        or ConditionReadsThreat(node.left, depth + 1) or ConditionReadsThreat(node.right, depth + 1)
end
local function RuleReadsThreat(rule)
    local when = type(rule) == "table" and rule.when
    if type(when) ~= "string" or not when:find("%S") then return false end
    local tree = Template.CompileCondition(when)
    if tree then return ConditionReadsThreat(tree, 0) end
    return when:find("threat.", 1, true) ~= nil or when:find("tanking", 1, true) ~= nil
end

-- With 1.0.3's threat switch off, rules reading threat had no threat to read and never held.
-- They are turned off (enabled = false), not removed, in every plate type and design. Returns how many.
local function DisableThreatRules(settings)
    local count = 0
    local profiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
    local function Disable(rules)
        for _, list in pairs(type(rules) == "table" and rules or {}) do
            for _, rule in ipairs(type(list) == "table" and list or {}) do
                if rule.enabled ~= false and RuleReadsThreat(rule) then
                    rule.enabled = false
                    count = count + 1
                end
            end
        end
    end
    for _, profile in pairs(profiles) do
        if type(profile) == "table" then
            Disable(profile.rules)
            for _, record in pairs(type(profile.contexts) == "table" and profile.contexts or {}) do
                if type(record) == "table" then
                    Disable(record.full == true and type(record.design) == "table" and record.design.rules or record.rules)
                end
            end
            if type(profile.players) == "table" then Disable(profile.players.rules) end
        end
    end
    return count
end

-- Schema 25 and older kept each box as a setting of its own, which kept its parts off whatever
-- their eyes said. One that was off (source[key] == false) turns its parts' eyes off in every
-- layout of settings (and those of custom parts showing its values); the keys then go. Returns
-- how many threat rules it turned off (DisableThreatRules). World's and full designs' layouts are
-- set in place; a sparse design's merged layouts are shared and read-only, so one that has its own
-- eye for a part is set through its override (Designs.StoreEntry, after World's eyes, so one that
-- now matches World's goes). The Enemy players layer is one record for every place: set from World.
local function ApplyLegacySwitches(settings, source)
    local disabled = 0
    if type(source) == "table" and source.threat == false then disabled = DisableThreatRules(settings) end
    local Designs = PS.Designs
    for _, switch in ipairs(PART_SWITCHES) do
        if type(source) == "table" and source[switch.key] == false then
            local own = {}
            local function Hide(layout, key, field, plateType, record)
                if type(layout[key]) ~= "table" then return end
                if not (record and record.full ~= true) then
                    layout[key].visible = false
                    return
                end
                local entries = type(record.layouts) == "table" and record.layouts[field]
                if type(entries) == "table" and type(entries[key]) == "table" then
                    local entry = Table.DeepCopy(layout[key])
                    entry.visible = false
                    own[#own + 1] = { world = settings.plateProfiles[plateType == "enemyPlayer" and "enemy" or plateType],
                        record = record, field = field, key = key, entry = entry }
                end
            end
            Designs.EachDesign(settings, nil, function(profile, plateType, context, record)
                if plateType == "enemyPlayer" and context ~= "world" then return end
                for _, field in ipairs(PLATE_LAYOUT_FIELDS[plateType]) do
                    local layout = profile[field]
                    if (field ~= "dungeonNamesLayout" or context == "world") and type(layout) == "table" then
                        for _, part in ipairs(switch.parts) do Hide(layout, part, field, plateType, record) end
                        for key, slot in pairs(switch.sources and type(profile.valueSlots) == "table" and profile.valueSlots or {}) do
                            if type(slot) == "table" and switch.sources[slot.source] then Hide(layout, key, field, plateType, record) end
                        end
                    end
                end
            end)
            for _, edit in ipairs(own) do
                Designs.StoreEntry(edit.world, edit.record, edit.field, edit.key, edit.entry)
                if edit.world.players == edit.record then Designs.SetPlayers(edit.world, edit.record) end
            end
            Designs.Invalidate()
        end
        settings[switch.key] = nil
    end
    return disabled
end

-- Whether a shown custom part, or any rule, of these plate types reads a word (a template token
-- or condition naming it; plain text naming it counts too, so this errs towards true). sources:
-- value sources that read it.
local function PlatesRead(settings, plates, words, sources)
    local function Names(text)
        if type(text) ~= "string" then return false end
        for _, word in ipairs(words) do if text:find(word, 1, true) then return true end end
        return false
    end
    local found = false
    EachPlateLayout(settings, plates, function(layout, profile)
        if found then return end
        for key, slot in pairs(type(profile.valueSlots) == "table" and profile.valueSlots or {}) do
            local position = layout[key]
            if type(slot) == "table" and type(position) == "table" and not TurnedOff(position)
                and ((sources and sources[slot.source]) or (slot.source == "template" and Names(slot.template))) then
                found = true
                return
            end
        end
        for _, list in pairs(type(profile.rules) == "table" and profile.rules or {}) do
            for _, rule in ipairs(type(list) == "table" and list or {}) do
                if type(rule) == "table" and rule.enabled ~= false and Names(rule.when) then
                    found = true
                    return
                end
            end
        end
    end)
    return found
end

-- What the plates need at all, from what their layouts show: the threat service runs while an
-- enemy layout shows threat or reads it (a custom part or rule; the tank's role too), Threat
-- colours colour a part, or a layout shows the health bar the tank's warning border is drawn on
-- while that warning is on; quest lookups
-- run while a layout shows the quest marker or reads it.
local HEALTH_BAR = { plates = ENEMY_PLATES }
local function ThreatNeeded(settings)
    local state = PartShownState(settings, "threat")
    if state == "all" or state == "some" then return true end
    if type(settings) == "table" and settings.colourByThreat == true and (settings.threatColourHealth == true
        or settings.threatColourName == true or settings.threatColourBorder == true) then
        return true
    end
    if type(settings) == "table" and settings.tankWarning ~= false then
        local bar = false
        EachLiveLayout(settings, HEALTH_BAR, function(layout)
            bar = bar or (type(layout.health) == "table" and not TurnedOff(layout.health))
        end)
        if bar then return true end
    end
    return PlatesRead(settings, ENEMY_PLATES, { "threat", "tank" }, THREAT_SOURCES)
end
local function QuestNeeded(settings)
    local state = PartShownState(settings, "quest")
    if state == "all" or state == "some" then return true end
    return PlatesRead(settings, nil, { "quest" })
end
-- Quest progress is read while a plate type shows it by its quest mark or reads its tokens.
local function QuestProgressNeeded(settings)
    local shown = false
    EachPlateLayout(settings, nil, function(layout, profile)
        shown = shown or (profile.questProgress ~= nil and profile.questProgress ~= "off"
            and type(layout.quest) == "table" and not TurnedOff(layout.quest))
    end)
    return shown or PlatesRead(settings, nil, { "quest.progress", "quest.percent" })
end
-- The range checks run only while an enemy plate's rule or text reads inrange.
local function RangeNeeded(settings)
    return PlatesRead(settings, ENEMY_PLATES, { "inrange", "inRange" })
end
-- Combo points are read while a layout shows the part or a custom part or rule reads {combo}.
local function ComboNeeded(settings)
    local shown = false
    EachPlateLayout(settings, nil, function(layout)
        shown = shown or (type(layout.combo) == "table" and not TurnedOff(layout.combo))
    end)
    return shown or PlatesRead(settings, nil, { "combo" })
end
-- The "Targeted by" badges are read while an enemy layout shows them.
local function TargetedByNeeded(settings)
    local shown = false
    EachPlateLayout(settings, ENEMY_PLATES, function(layout)
        shown = shown or (type(layout.targetedBy) == "table" and not TurnedOff(layout.targetedBy))
    end)
    return shown
end

-- What a migration did that the player should hear about, by settings table, until the loader
-- takes it (TakeMigrationNote): Profiles.Load names the profile in chat once.
local migrationNotes = setmetatable({}, { __mode = "k" })
local function TakeMigrationNote(settings)
    local note = migrationNotes[settings]
    migrationNotes[settings] = nil
    return note
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
    [25] = function(settings)
        -- The Show on plates and aura switches became shortcuts over the eyes: a switch that was
        -- off leaves its parts' eyes off in every layout.
        -- The tank's warning border ran under the threat switch: it keeps that switch's state.
        settings.plateProfiles = NormalizeProfiles(settings.plateProfiles, settings)
        if settings.tankWarning == nil then settings.tankWarning = settings.threat ~= false end
        local disabled = ApplyLegacySwitches(settings, settings)
        if disabled > 0 then migrationNotes[settings] = { threatRulesDisabled = disabled } end
        settings.schemaVersion = 26
    end,
    [26] = function(settings)
        -- The dungeon friendly overlay test never drew on Forever (the game blocks it): it starts off,
        -- so Studio's Players and Friendly NPCs › Dungeons & raids show Blizzard's name. It is on Experimental.
        if settings.experimentalDungeonFriendlyText == true then
            settings.experimentalDungeonFriendlyText = false
            local note = migrationNotes[settings] or {}
            note.dungeonOverlayOff = true
            migrationNotes[settings] = note
        end
        settings.schemaVersion = 27
    end,
    [27] = function(settings)
        -- Threat colours are new and on for new profiles; a saved profile keeps its colours (off).
        if settings.colourByThreat == nil then
            settings.colourByThreat = false
            local note = migrationNotes[settings] or {}
            note.threatColoursOff = true
            migrationNotes[settings] = note
        end
        settings.schemaVersion = 28
    end,
    [28] = function(settings)
        -- Context designs: the dungeon enemy override becomes the Enemies' full Dungeons & raids design.
        MoveDungeonOverride(settings)
        settings.schemaVersion = 29
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

-- A general setting's value, made valid: the default when it is not (a colour setting a new
-- table). nil for a key without a validator of its own (relationshipColours, plateProfiles, the
-- enemy aliases).
local function SettingValue(key, value)
    if isBooleanSetting[key] then
        if type(value) == "boolean" then return value end
        return defaults[key]
    end
    local allowed = enumSettings[key]
    if allowed then return allowed[value] and value or defaults[key] end
    if key == "font" or key == "blizzardNameFontFace" then return Media.IsFont(value) and value or defaults[key] end
    local range = settingRanges[key]
    if range then return Bounded(range, value, defaults[key]) end
    if colourSettings[key] then return NormalizeColour(value, defaults[key]) end
    return nil
end

-- Blizzard's nameplate stacking, distance, scale and fade CVars PlateSmith can manage
-- (Nameplates/Stacking.lua), in the order the UI lists them: { key, group, kind, min, max, step,
-- default }. A choice lists its values; a number is clamped to [min, max]. default is used only
-- when the client reports none. The client reports no bounds, so these are PlateSmith's.
local STACKING_CVARS = {
    { "nameplateMotion", "stacking", "choice", choices = { 0, 1 }, default = 0 },
    { "nameplateMotionSpeed", "stacking", "number", 0, 0.5, 0.005, default = 0.025 },
    { "nameplateOverlapV", "stacking", "number", 0.2, 2.5, 0.05, default = 1.1 },
    { "nameplateOverlapH", "stacking", "number", 0.2, 2.5, 0.05, default = 0.8 },
    { "nameplateOtherTopInset", "edges", "number", -1, 0.5, 0.01, default = 0.08 },
    { "nameplateOtherBottomInset", "edges", "number", -1, 0.5, 0.01, default = 0.1 },
    { "nameplateLargeTopInset", "edges", "number", -1, 0.5, 0.01, default = 0.1 },
    { "nameplateLargeBottomInset", "edges", "number", -1, 0.5, 0.01, default = 0.15 },
    { "nameplateTargetRadialPosition", "edges", "choice", choices = { 0, 1, 2 }, default = 0 },
    { "nameplateTargetBehindMaxDistance", "distance", "number", 0, 100, 1, default = 15 },
    { "nameplateMaxDistance", "distance", "number", 5, 100, 1, default = 41 },
    { "nameplateMinScale", "scale", "number", 0.3, 1.5, 0.05, default = 0.8 },
    { "nameplateMaxScale", "scale", "number", 0.3, 2, 0.05, default = 1 },
    { "nameplateMinScaleDistance", "scale", "number", 0, 100, 1, default = 10 },
    { "nameplateMaxScaleDistance", "scale", "number", 0, 100, 1, default = 10 },
    { "nameplateSelectedScale", "scale", "number", 0.5, 2, 0.05, default = 1.2 },
    { "nameplateLargerScale", "scale", "number", 0.5, 2, 0.05, default = 1.2 },
    { "nameplateMinAlpha", "fade", "number", 0, 1, 0.05, default = 0.6 },
    { "nameplateMaxAlpha", "fade", "number", 0, 1, 0.05, default = 1 },
    { "nameplateMinAlphaDistance", "fade", "number", 0, 100, 1, default = 10 },
    { "nameplateMaxAlphaDistance", "fade", "number", 0, 100, 1, default = 40 },
    { "nameplateSelectedAlpha", "fade", "number", 0, 1, 0.05, default = 1 },
    { "nameplateNotSelectedAlpha", "fade", "number", 0, 1, 0.05, default = 0.5 },
    { "nameplateOccludedAlphaMult", "fade", "number", 0, 1, 0.05, default = 0.4 },
}
local stackingCVar = {}
for _, entry in ipairs(STACKING_CVARS) do stackingCVar[entry[1]] = entry end

-- Fixed spacing presets (docs/STACKING.md): stacking on, then how fast plates move apart, how far
-- apart they stack (overlap: 1 = one plate's size) and how close to the screen edges they may go.
local STACKING_PRESETS = {
    tight = { nameplateMotion = 1, nameplateMotionSpeed = 0.1, nameplateOverlapV = 0.7, nameplateOverlapH = 0.6,
        nameplateOtherTopInset = 0.05, nameplateOtherBottomInset = 0.05, nameplateLargeTopInset = 0.05,
        nameplateLargeBottomInset = 0.05 },
    normal = { nameplateMotion = 1, nameplateMotionSpeed = 0.05, nameplateOverlapV = 1.1, nameplateOverlapH = 0.8,
        nameplateOtherTopInset = 0.08, nameplateOtherBottomInset = 0.1, nameplateLargeTopInset = 0.1,
        nameplateLargeBottomInset = 0.15 },
    loose = { nameplateMotion = 1, nameplateMotionSpeed = 0.025, nameplateOverlapV = 1.6, nameplateOverlapH = 1.1,
        nameplateOtherTopInset = 0.1, nameplateOtherBottomInset = 0.15, nameplateLargeTopInset = 0.12,
        nameplateLargeBottomInset = 0.2 },
}
local stackingPresetNames = { custom = true, tight = true, normal = true, loose = true }
-- managed = false: PlateSmith never writes these CVars (the default, and every existing profile's).
-- values holds only what the player set; anything else keeps the client's own value.
local stackingDefaults = { managed = false, preset = "custom", targetOnTop = true, focusOnTop = false,
    matchFrameSize = true, combatStacking = false }
local STACKING_OPTIONS = { "targetOnTop", "focusOnTop", "matchFrameSize", "combatStacking" }

-- A stacking CVar's value made valid, or nil (unknown CVar, or not a usable value).
local function StackingValue(key, value)
    local entry = stackingCVar[key]
    value = tonumber(value)
    if not entry or not value or value ~= value then return nil end
    if entry.choices then
        for _, choice in ipairs(entry.choices) do if choice == value then return value end end
        return nil
    end
    return math.max(entry[4], math.min(entry[5], value))
end

local function NormalizeStacking(stacking)
    stacking = type(stacking) == "table" and stacking or {}
    local result = { managed = stacking.managed == true, values = {} }
    result.preset = stackingPresetNames[stacking.preset] and stacking.preset or stackingDefaults.preset
    for _, key in ipairs(STACKING_OPTIONS) do
        if type(stacking[key]) == "boolean" then result[key] = stacking[key] else result[key] = stackingDefaults[key] end
    end
    for key, value in pairs(type(stacking.values) == "table" and stacking.values or {}) do
        result.values[key] = StackingValue(key, value)
    end
    return result
end

local function NormalizeSettings(settings)
    settings = type(settings) == "table" and settings or {}
    -- Every saved profile carries schemaVersion (stamped below), so a table without one is new
    -- (a fresh install, a reset, a Blueprint candidate): it starts at the current schema, and
    -- migrations run only on saved data from an older one.
    local fresh = settings.schemaVersion == nil
    if fresh then settings.schemaVersion = defaults.schemaVersion end
    local schemaVersion = MigrateSettings(settings)
    if schemaVersion >= 29 then MoveDungeonOverride(settings) end
    -- The old switches are never read; one left over (a table stamped by another build) goes.
    for _, switch in ipairs(PART_SWITCHES) do settings[switch.key] = nil end
    CopyDefaults(settings, defaults)
    for key in pairs(defaults) do
        local value = SettingValue(key, settings[key])
        if value ~= nil then settings[key] = value end
    end
    settings.relationshipColours = type(settings.relationshipColours) == "table" and settings.relationshipColours or {}
    for key, fallback in pairs(defaultRelationshipColours) do
        settings.relationshipColours[key] = NormalizeColour(settings.relationshipColours[key], fallback)
    end
    settings.threatColours = THREAT_COLOURS.Normalize(settings.threatColours)
    settings.threatPartColours = THREAT_COLOURS.NormalizeParts(settings.threatPartColours, settings.threatColours)
    settings.plateProfiles = NormalizeProfiles(settings.plateProfiles, settings, fresh)
    -- Stacking drives account-wide CVars, so Blueprints leave it out (Core/Blueprint.lua lists
    -- what they carry).
    settings.stacking = NormalizeStacking(settings.stacking)
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
    -- studioColourBlind has no default: nil follows the plates' threat palette, true is on, "off" off.
    studioHighContrast = false,
    -- The model behind Studio's preview (View › Model): off, player, target or creature.
    studioPreviewModel = "off",
    threatConsoleShown = false,
    threatWindows = {},
    -- Saved styles ("Level box", "Framed bar"): name -> { kind, style, rules }, applied to any
    -- part of that kind. The player's own, kept across profiles, Revert and profile switches.
    stylePresets = {},
    -- Studio's and Settings' folded sections for this player: section key -> true.
    sectionFolds = {},
    -- The other-nameplate-addon notice: dismissed[set of addon folder names, "A+B"] = true.
    conflictNotice = { dismissed = {} },
    -- The most nameplates this client has had plates at once (Lifecycle's spares follow it).
    platePeak = 0,
    -- firstRunDone has no default: Profiles.Load sets it false on a fresh install (Studio's first-run
    -- picker is to show) and the picker true; an existing install leaves it nil and never sees it.
}
local studioScaleRange = { 0.6, 1.3 }

local function NormalizeState(state)
    state = type(state) == "table" and state or {}
    if type(state.threatConsoleShown) ~= "boolean" then state.threatConsoleShown = stateDefaults.threatConsoleShown end
    if type(state.studioHighContrast) ~= "boolean" then state.studioHighContrast = stateDefaults.studioHighContrast end
    -- A saved false (the old tick box's default) follows the plates' palette from now on.
    if state.studioColourBlind ~= true and state.studioColourBlind ~= "off" then state.studioColourBlind = nil end
    if type(state.threatWindows) ~= "table" then state.threatWindows = {} end
    if state.cvarRestore ~= nil and type(state.cvarRestore) ~= "table" then state.cvarRestore = nil end
    if type(state.firstRunDone) ~= "boolean" then state.firstRunDone = nil end
    -- CVars whose original was lost (NamePolicy): restore key -> { CVar name -> true }.
    local lost, lostCount = {}, 0
    for key, names in pairs(type(state.cvarOriginalsMissing) == "table" and state.cvarOriginalsMissing or {}) do
        if type(key) == "string" and #key <= 64 and type(names) == "table" then
            local kept = {}
            for name, value in pairs(names) do
                if type(name) == "string" and #name <= 64 and value == true and lostCount < 64 then
                    kept[name], lostCount = true, lostCount + 1
                end
            end
            if next(kept) then lost[key] = kept end
        end
    end
    state.cvarOriginalsMissing = next(lost) and lost or nil
    -- Studio no longer has themes: an older saved choice is dropped.
    state.editorTheme = nil
    state.studioScale = Bounded(studioScaleRange, state.studioScale, stateDefaults.studioScale)
    local model = state.studioPreviewModel
    if model ~= "off" and model ~= "player" and model ~= "target" and model ~= "creature" then
        state.studioPreviewModel = stateDefaults.studioPreviewModel
    end
    local peak = state.platePeak
    if type(peak) ~= "number" or peak < 0 or peak > 1000 or peak ~= math.floor(peak) then
        state.platePeak = stateDefaults.platePeak
    end
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
    local dismissed, sets = {}, 0
    local notice = type(state.conflictNotice) == "table" and state.conflictNotice.dismissed
    if type(notice) == "table" then
        for key, value in pairs(notice) do
            if type(key) == "string" and #key <= 200 and value == true and sets < 32 then
                dismissed[key], sets = true, sets + 1
            end
        end
    end
    state.conflictNotice = { dismissed = dismissed }
    return state
end

-- Per-character preferences live outside PlateSmithDB so alts keep their own role.
-- tankRole: adaptive (the group role, else what the character is doing: a tanking stance,
-- aura or feral bear), always (this character tanks) or never.
local characterDefaults = {
    tankRole = "adaptive",
}
local validTankRoles = { adaptive = true, always = true, never = true }

-- autoProfile (Core/AutoProfile.lua): a profile name per content type and specialization index; a
-- missing key is "Don't switch". precedence says which wins when both apply. Kept in place, so the
-- table's identity survives normalising.
local autoProfileRuleKeys = { world = true, dungeon = true, raid = true, pvp = true,
    spec1 = true, spec2 = true, spec3 = true, spec4 = true }
local autoProfilePrecedence = { content = true, spec = true }

local function NormalizeAutoProfile(rules)
    rules = type(rules) == "table" and rules or {}
    for key, value in pairs(rules) do
        if key == "precedence" then
            if not autoProfilePrecedence[value] then rules[key] = nil end
        elseif not autoProfileRuleKeys[key] or type(value) ~= "string" or value == "" or #value > 32
            or value:find("[%c|]") then
            rules[key] = nil
        end
    end
    if rules.precedence == nil then rules.precedence = "content" end
    return rules
end

local function NormalizeCharacterSettings(settings)
    settings = type(settings) == "table" and settings or {}
    settings.autoProfile = NormalizeAutoProfile(settings.autoProfile)
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
    CAST_COLOUR = CAST_COLOUR,
    CAST_COLOUR_KEYS = CAST_COLOUR_KEYS,
    NormalizeCastColours = NormalizeCastColours,
    layoutRanges = layoutRanges,
    valueFontRange = valueFontRange,
    auraLayoutRanges = auraLayoutRanges,
    auraGrowX = auraGrowX,
    auraGrowY = auraGrowY,
    auraTimeFields = auraTimeFields,
    auraTimePositions = auraTimePositions,
    Bounded = Bounded,
    InRange = InRange,
    ComponentScale = ComponentScale,
    ScaledFontSize = ScaledFontSize,
    StyledFontSize = StyledFontSize,
    PartTextSize = PartTextSize,
    STYLE_FONT_SIZE = STYLE_FONT_SIZE,
    DRAWN_FONT_RANGE = DRAWN_FONT_RANGE,
    characterDefaults = characterDefaults,
    validTankRoles = validTankRoles,
    stateDefaults = stateDefaults,
    studioScaleRange = studioScaleRange,
    NormalizeState = NormalizeState,
    NormalizeCharacterSettings = NormalizeCharacterSettings,
    NormalizeAutoProfile = NormalizeAutoProfile,
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
    SortByTreeOrder = SortByTreeOrder,
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
    STYLE_PIPS = STYLE_PIPS,
    PipRow = PipRow,
    PipFitWidth = PipFitWidth,
    DrawnScale = DrawnScale,
    STYLE_BADGES = STYLE_BADGES,
    STYLE_BADGE_ORIENTATIONS = STYLE_BADGE_ORIENTATIONS,
    STYLE_PIP_SHAPES = STYLE_PIP_SHAPES,
    STYLE_BOX_SHAPES = STYLE_BOX_SHAPES,
    STYLE_PIP_ANCHORS = STYLE_PIP_ANCHORS,
    STYLE_PIP_SHOW_ROWS = STYLE_PIP_SHOW_ROWS,
    STYLE_DEFAULTS = STYLE_DEFAULTS,
    RULE_SETS = RULE_SETS,
    MAX_RULES_PER_PART = MAX_RULES_PER_PART,
    MAX_RULES = MAX_RULES,
    NormalizePartRules = NormalizePartRules,
    NormalizeValueTemplate = NormalizeValueTemplate,
    profileOrder = profileOrder,
    profileDefaults = profileDefaults,
    defaultRelationshipColours = defaultRelationshipColours,
    -- Blizzard's name colour for a PvP-flagged ally: its nameplates colour names by UnitSelectionColor
    -- (CompactUnitFrame_UpdateName), which is Friendly, pure green, for such a player.
    BLIZZARD_PVP_GREEN = { r = 0, g = 1, b = 0 },
    THREAT_COLOURS = THREAT_COLOURS,
    booleanSettings = booleanSettings,
    enumSettings = enumSettings,
    settingRanges = settingRanges,
    colourSettings = colourSettings,
    glowSettings = glowSettings,
    VISIBILITY = VISIBILITY,
    ENEMY_ALIASES = ENEMY_ALIASES,
    SettingValue = SettingValue,
    NormalizeLayout = NormalizeLayout,
    LEGACY_ENTRIES = LEGACY_ENTRIES,
    ComboInStack = ComboInStack,
    -- Whether a design's combo points sit on its health bar's bottom edge (their style's pipAnchor "edge",
    -- with the bar not turned off). The plates and Studio's preview then draw the row in front of the bars.
    -- Defined here, not as a local: the main chunk is at Lua 5.1's 200-local limit.
    ComboOnBarEdge = function(profile, layout)
        local styles = type(profile) == "table" and profile.styles
        local style = type(styles) == "table" and styles.combo
        if not (type(style) == "table" and style.pipAnchor == "edge") then return false end
        return type(layout) == "table" and type(layout.health) == "table" and not TurnedOff(layout.health)
    end,
    NormalizeColour = NormalizeColour,
    NormalizeProfile = NormalizeProfile,
    IsProfileOption = IsProfileOption,
    HIGHLIGHT = HIGHLIGHT,
    ProfileOptionValue = ProfileOptionValue,
    CopyEnemyProfile = CopyEnemyProfile,
    NormalizeLayoutEntry = NormalizeLayoutEntry,
    NormalizeValueSlot = NormalizeValueSlot,
    DESIGN = DESIGN,
    NormalizeDesign = NormalizeDesign,
    NormalizeSettings = NormalizeSettings,
    STACKING_CVARS = STACKING_CVARS,
    STACKING_PRESETS = STACKING_PRESETS,
    STACKING_OPTIONS = STACKING_OPTIONS,
    stackingDefaults = stackingDefaults,
    stackingPresetNames = stackingPresetNames,
    StackingValue = StackingValue,
    NormalizeStacking = NormalizeStacking,
    PART_SWITCHES = PART_SWITCHES,
    partSwitches = partSwitches,
    EachPlateLayout = EachPlateLayout,
    EachLiveLayout = EachLiveLayout,
    PartShownState = PartShownState,
    ApplyLegacySwitches = ApplyLegacySwitches,
    RuleReadsThreat = RuleReadsThreat,
    TakeMigrationNote = TakeMigrationNote,
    ThreatNeeded = ThreatNeeded,
    QuestNeeded = QuestNeeded,
    QuestProgressNeeded = QuestProgressNeeded,
    RangeNeeded = RangeNeeded,
    ComboNeeded = ComboNeeded,
    TargetedByNeeded = TargetedByNeeded,
    ENEMY_PLATES = ENEMY_PLATES,
}
