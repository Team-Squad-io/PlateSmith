local _, PS = ...
local Format = assert(PS.Format, "PlateSmith Format missing")
local Template = assert(PS.Template, "PlateSmith Template missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local Media = assert(PS.Media, "PlateSmith Media missing")

local defaults = {
    schemaVersion = 35,
    enabled = true,
    mode = "auto",       -- auto, own, overlay
    -- Extras on Blizzard's plates (Schema's EXTRAS, Nameplates/Extras.lua), drawn while mode is overlay: quest markers,
    -- threat (text, edge, both, off), the target's glow, the Loose mark. A saved profile keeps what that choice drew
    -- before 1.3.0, quest markers and threat text (migration 33).
    extrasQuest = true, extrasThreat = "both", extrasTarget = true, extrasLoose = true,
    -- Who draws a game object's plate (a book, a chest: the Objects plate type): platesmith (the Objects design) or
    -- blizzard (the client's own plate, untouched).
    objectPlates = "platesmith",
    -- Objects plates fade while the game's icon says you can't use the object yet (object.unable: a skill too low).
    objectFadeUnable = false,
    -- Hovering an Objects plate's name (Nameplates/ObjectHover.lua): the game's interaction cursor, and a small tooltip.
    -- The player's own, changing no look: kept by the profile, not shared in Blueprints (HOVER).
    objectHoverCursor = true,
    objectHoverTooltip = true,
    -- names, full, off (Blizzard's plates): Show as for both friendly plate types, unless one has its own
    -- (friendlyPlayers, friendlyNPCs: no default, absent while it follows this; read through FRIENDLY.Mode).
    friendly = "names",
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
    -- The Elite / rare mark (Nameplates/Identity.lua's ClassificationMark): icon (Blizzard's nameplate icons), dragon
    -- (the classic dragon round the level at the bar's right end), beforeName (the icon before the name), suffix (on
    -- the level: 60+, 60R), frame (a ring round the health bar), words, letters. The two that place parts do it
    -- through MARK.Layout, never in the saved layout. classificationIconSize: auto, standard (18 px), text (the
    -- name's text height); auto is standard beside the bar and text before the name.
    classificationStyle = "icon", classificationIconSize = "auto",
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
    -- Grey when tagged by others (ThreatColours.GreyWhenTagged): an enemy's health bar turns grey while another
    -- player or group has tagged the mob, as Blizzard's plates draw it. New profiles have it on, with the TAGGED
    -- word off (defaultLayout); saved profiles keep their TAGGED word and colours (migration 30: off).
    greyWhenTagged = true,
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
    -- Highlight Off once kept the health bar's gold target edge; profiles saved before 1.2.1 still do.
    targetOffKeepsEdge = false,
    -- The glow style (Nameplates/TargetGlow.lua): a soft cloud of light behind the target's whole plate
    -- in the unit's class or reaction colour, or targetGlowColour; how far it reaches past the plate (px),
    -- its opacity, and an optional slow pulse. A changed glow default needs no migration: every profile
    -- that could show the glow holds its glow values (profiles are stored whole once loaded), so only new
    -- profiles take it.
    targetGlowColourMode = "custom", targetGlowColour = { r = 0.1, g = 0.8, b = 0.9 },
    targetGlowSpread = 56, targetGlowOpacity = 0.6, targetGlowPulse = false,
    -- How far the whole glow is moved from the plate (px, right and up); 0 keeps it centred.
    targetGlowOffsetX = 0, targetGlowOffsetY = 0,
    -- Its wrap (targetGlowWrap): "parts" wraps the shown parts of targetGlowParts (Glow.Bounds) and reaches
    -- targetGlowSpread past them across, and up and down too while targetGlowEven, else targetGlowSpreadY; "fixed"
    -- is a box targetGlowWidth by targetGlowHeight (targetGlowEven: by its width) centred on the health bar.
    targetGlowWrap = "parts", targetGlowParts = "name,health,power,cast", targetGlowEven = true, targetGlowSpreadY = 56,
    targetGlowWidth = 140, targetGlowHeight = 40,
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

-- Clicking (Nameplates/ClickThrough.lua): per kind of plate, whether a click selects its unit or passes through.
-- clickFriendlyPlayer: clickable (the default) or through, friendly players' plates while PlateSmith draws them
-- (NamePolicy's names-only switch). clickFriendlyNPC, clickEnemy and clickSelf: game (Clickable: the game's own
-- left as it is, the default) or through, set while PlateSmith runs. Like Where plates show, it drives account-wide
-- client state, so Blueprints leave it out. Kept on VISIBILITY's table (the main chunk is at Lua 5.1's 200-local
-- limit) and exported as CLICK.
VISIBILITY.CLICK = { CHOICES = { "game", "clickable", "through" },
    KEYS = { "clickFriendlyPlayer", "clickFriendlyNPC", "clickEnemy", "clickSelf" } }
for _, key in ipairs(VISIBILITY.CLICK.KEYS) do defaults[key] = "game" end
defaults.clickFriendlyPlayer = "clickable"
-- The game's interact key settings (Nameplates/Interaction.lua; Settings › Objects & interacting): game leaves each
-- as the game has it; any other choice sets it while PlateSmith runs. CHOICES are a switch's (on, off) unless OWN
-- gives the key its own: Range in yards, Direction (ahead, front, around), Out of reach (within, beyond). Like
-- Clicking: account-wide client state, kept out of Blueprints, exported as INTERACT.
VISIBILITY.INTERACT = { CHOICES = { "game", "on", "off" },
    KEYS = { "interactTargeting", "interactRange", "interactArc", "interactReach", "interactNameplate", "interactIcons",
        "interactObjectIcons", "interactMinorIcons" },
    OWN = { interactRange = { "game", "10", "15", "20", "30", "45", "60" },
        interactArc = { "game", "ahead", "front", "around" }, interactReach = { "game", "within", "beyond" } } }
for _, key in ipairs(VISIBILITY.INTERACT.KEYS) do defaults[key] = "game" end
-- The Objects' hover cursor and tooltip (on or off): the player's own behaviour, no look, so Blueprints leave them
-- out too. Exported as HOVER.
VISIBILITY.HOVER = { KEYS = { "objectHoverCursor", "objectHoverTooltip" } }

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

-- object: a game object's plate (a book, a chest), drawn names only (Lifecycle's rounds.Kind); new in 1.3.0.
local profileOrder = { "enemy", "friendlyPlayer", "friendlyNPC", "object" }
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

-- The enemy template, and the fallback for any layout entry that is missing. TAGGED is off: the health bar greys
-- instead (greyWhenTagged); its eye brings the word back.
local defaultLayout = FullLayout({ name = true, health = true, cast = true, threat = true, quest = true,
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
    -- Objects: one names-only layout (no names/full switch, no Blizzard dungeon design) showing the name and the
    -- quest mark, in a tooltip-like box (the Backdrop part: dark fill, a thin grey-gold edge) with the quest mark just
    -- outside it. The name's gold is the plate's own (Identity's ObjectPlate.COLOUR), as a creature's reaction
    -- colour is; rules change it. The Action icon, the Status text and the Backdrop follow below.
    object = {
        scale = 1, width = 112, healthHeight = 10, powerHeight = 5, nameFontSize = 14,
        healthTexture = "blizzard", healthColourMode = "automatic",
        healthColour = { r = 1, g = 0.82, b = 0 },
        layout = NamesLayout({ name = true, quest = true }),
        styles = { backdrop = { boxColour = { r = 0.03, g = 0.03, b = 0.05, a = 0.85 },
            boxBorder = { r = 0.6, g = 0.53, b = 0.36, a = 1 }, padding = 5 } },
    },
}
-- The quest mark pinned to the name, clear of the Backdrop (Padding 5 and 2 px).
profileDefaults.object.layout.quest.parent, profileDefaults.object.layout.quest.x = "name", -7
-- The Action icon (Nameplates/ActionIcon.lua): the game's own cursor icon for what you can do with the unit. Objects
-- show it right of the name, inside the Backdrop; Friendly NPCs have it off, right of the name (of the raid mark on
-- names-only plates, taking its place while there is none). Other plate types have no entry.
profileDefaults.object.layout.actionIcon = { x = 4, y = 0, visible = true, parent = "name", attach = "right" }
-- The Status text (Nameplates/ObjectStatus.lua): what the object needs and your skill ("Mining 65" in its skill-up colour), centred
-- under the name, inside the Backdrop. Off on All objects; an object type (Designs.TYPES) or a look may turn it on.
profileDefaults.object.layout.statusText = { x = 0, y = -3, visible = false, parent = "name", attach = "bottom" }
-- The Backdrop (Nameplates/Backdrop.lua): Objects only, round the name, the Status text and the Action icon.
profileDefaults.object.layout.backdrop = { x = 0, y = 0, visible = true, parent = "name" }
profileDefaults.friendlyNPC.layout.actionIcon = { x = 3, y = 0, visible = false, parent = "name", attach = "right" }
profileDefaults.friendlyNPC.namesLayout.actionIcon = { x = 3, y = 0, visible = false, parent = "raidIcon", attach = "right" }
-- The Loose mark (Nameplates/LooseMark.lua): a small icon right of the name while the mob is loose (the threat
-- service's LOOSE). Enemies only, off; a look may turn it on (Tank). Other plate types have no entry.
profileDefaults.enemy.layout.looseMark = { x = 3, y = 0, visible = false, parent = "name", attach = "right" }

-- The cast bar's own parts, on every plate type: the spell's icon (left or right of the bar, inside its
-- left end, or off), the time left inside the bar's right end, and the spell's name.
-- castInterruptColours colours the bar by your interrupt (castColours); castOnTop draws a casting
-- plate over its neighbours (under the target and focus). The quest mark's progress text ("3/8" or
-- "50%") rides here too: off, beside the mark, or in its place, as a count or a percentage.
local castOptions = { castIcon = { left = true, right = true, inside = true, off = true }, castTime = "boolean", castName = "boolean",
    castInterruptColours = "boolean", castOnTop = "boolean",
    questProgress = { off = true, beside = true, instead = true }, questProgressFormat = { count = true, percent = true } }
local castDefaults = { castIcon = "left", castTime = true, castName = true, castInterruptColours = false, castOnTop = false,
    questProgress = "off", questProgressFormat = "count" }
-- Colour by interrupt's colours: ready (it can be interrupted and your interrupt is ready), cooldown (it can, but yours
-- is on cooldown or you have none), locked (it cannot). (The cast bar's own colour is the export's CAST_COLOUR.)
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
-- Blizzard draws friendly names in dungeons: no Action icon there.
profileDefaults.friendlyNPC.dungeonNamesLayout.actionIcon = nil

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
-- its Own colours is on; a state it lacks takes the shared colour. Other tank has it is teal (1.3.0), apart from
-- Holding's periwinkle; it was a pale blue (OFFTANK_BEFORE_130) close to it, which saved profiles keep: a saved
-- profile stores its whole palette, so only new installs and profiles take the teal.
local THREAT_COLOURS = {
    STATES = { "holding", "losing", "offtank", "other", "safe", "pulling", "aggro" },
    PARTS = { "health", "name", "border" },
    OFFTANK_BEFORE_130 = { r = 0.73, g = 0.92, b = 1 },
    defaults = {
        holding = { r = 0.5, g = 0.5, b = 1 }, losing = { r = 1, g = 1, b = 0 },
        offtank = { r = 0.2, g = 0.8, b = 0.7 }, other = { r = 1, g = 0, b = 0 },
        safe = { r = 0.3, g = 0.8, b = 0.3 }, pulling = { r = 1, g = 0.6, b = 0 }, aggro = { r = 1, g = 0.1, b = 0.45 },
    },
}
THREAT_COLOURS.isPart = {}
for _, part in ipairs(THREAT_COLOURS.PARTS) do THREAT_COLOURS.isPart[part] = true end

local validModes = { auto = true, own = true, overlay = true }
-- Show as (Studio's Friendly plates): names only, full plates or Blizzard's plates, per friendly plate type.
-- friendly is both types' choice (every profile and Blueprint from before 1.2.1, /ps friendly with no type);
-- KEYS name a type's own, absent while it follows friendly. Mode is the one reader.
local FRIENDLY = { MODES = { names = true, full = true, off = true },
    KEYS = { friendlyPlayer = "friendlyPlayers", friendlyNPC = "friendlyNPCs" }, TYPES = { "friendlyPlayer", "friendlyNPC" } }
-- plateType's Show as in settings (a friendly plate type; another reads the shared one).
function FRIENDLY.Mode(settings, plateType)
    if type(settings) ~= "table" then return defaults.friendly end
    local key = FRIENDLY.KEYS[plateType]
    local own = key and settings[key]
    if own ~= nil and FRIENDLY.MODES[own] then return own end
    local shared = settings.friendly
    return FRIENDLY.MODES[shared] and shared or defaults.friendly
end
-- Whether either friendly plate type shows as mode.
function FRIENDLY.Any(settings, mode)
    return FRIENDLY.Mode(settings, "friendlyPlayer") == mode or FRIENDLY.Mode(settings, "friendlyNPC") == mode
end
-- Keeps the stored form minimal, so a profile whose types agree stores (and exports) only friendly, as
-- before 1.2.1: an own value that is invalid or the same as friendly goes, and two that agree become friendly.
function FRIENDLY.Normalize(settings)
    if not FRIENDLY.MODES[settings.friendly] then settings.friendly = defaults.friendly end
    local players, npcs = settings.friendlyPlayers, settings.friendlyNPCs
    if players ~= nil and not FRIENDLY.MODES[players] then players = nil end
    if npcs ~= nil and not FRIENDLY.MODES[npcs] then npcs = nil end
    if players ~= nil and players == npcs then
        settings.friendly, players, npcs = players, nil, nil
    end
    if players == settings.friendly then players = nil end
    if npcs == settings.friendly then npcs = nil end
    settings.friendlyPlayers, settings.friendlyNPCs = players, npcs
    return settings
end
-- The report's and /ps status's word: the one Show as, or each type's when they differ.
function FRIENDLY.Text(settings)
    local players, npcs = FRIENDLY.Mode(settings, "friendlyPlayer"), FRIENDLY.Mode(settings, "friendlyNPC")
    if players == npcs then return players end
    return string.format("players %s, npcs %s", players, npcs)
end
local validFriendlyPvpStyles = { off = true, colour = true, icon = true, both = true }
local validAuraSources = { all = true, mine = true }
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
    targetGlowOffsetY = { -40, 40, true }, targetGlowSpreadY = { 8, 80, true }, targetGlowWidth = { 16, 320, true },
    targetGlowHeight = { 8, 160, true } }
-- General settings that are one colour ({ r, g, b }): exported as hex, imported through CheckColour.
local colourSettings = { targetGlowColour = true }
-- The soft target glow's own look: a change restyles only the glow on the plate showing it
-- (TargetGlow.RestyleShown), with no plate laid out again (Settings.SetOption).
local glowSettings = { targetGlowColourMode = true, targetGlowColour = true, targetGlowSpread = true,
    targetGlowOpacity = true, targetGlowPulse = true, targetGlowOffsetX = true, targetGlowOffsetY = true,
    targetGlowWrap = true, targetGlowParts = true, targetGlowEven = true, targetGlowSpreadY = true, targetGlowWidth = true,
    targetGlowHeight = true }
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
    "targetGlowPulse", "targetOffKeepsEdge", "greyWhenTagged", "targetGlowEven", "objectFadeUnable",
    "objectHoverCursor", "objectHoverTooltip",
    "extrasQuest", "extrasTarget", "extrasLoose",
}
local enumSettings = {
    mode = validModes, friendly = FRIENDLY.MODES, friendlyPlayers = FRIENDLY.MODES, friendlyNPCs = FRIENDLY.MODES,
    friendlyPvpStyle = validFriendlyPvpStyles,
    buffSource = validAuraSources, debuffSource = validAuraSources,
    classificationStyle = { icon = true, dragon = true, beforeName = true, suffix = true, frame = true, words = true,
        letters = true },
    classificationIconSize = { auto = true, standard = true, text = true },
    questIcons = validQuestIcons, targetHighlightStyle = validTargetHighlightStyles,
    namesOnlyCastText = { under = true, inside = true },
    threatSpotlightStyle = validThreatSpotlightStyles, threatPalette = validThreatPalettes,
    threatTextFormat = validThreatTextFormats, threatKeptHold = validThreatKeptHolds, threatKeptStyle = validThreatKeptStyles,
    blizzardNameFontScope = validBlizzardNameFontScopes,
    blizzardNameFontOutline = { none = true, outline = true, thick = true },
    threatColourRole = THREAT_COLOURS.roles, targetGlowColourMode = validTargetGlowColourModes,
    -- (targetGlowParts' values: HIGHLIGHT.GLOW_PARTS.)
    targetGlowWrap = { parts = true, fixed = true }, targetGlowParts = { none = true },
    extrasThreat = { text = true, edge = true, both = true, off = true },
}
do
    local combatChoices = {}
    for _, choice in ipairs(VISIBILITY.COMBAT) do combatChoices[choice] = true end
    for _, plateType in ipairs(VISIBILITY.TYPES) do
        local keys = VISIBILITY.keys[plateType]
        for _, place in ipairs(VISIBILITY.PLACES) do booleanSettings[#booleanSettings + 1] = keys[place] end
        enumSettings[keys.combat] = combatChoices
    end
    local clickChoices = {}
    for _, choice in ipairs(VISIBILITY.CLICK.CHOICES) do clickChoices[choice] = true end
    for _, key in ipairs(VISIBILITY.CLICK.KEYS) do enumSettings[key] = clickChoices end
    local INTERACT = VISIBILITY.INTERACT
    for _, key in ipairs(INTERACT.KEYS) do
        local choices = {}
        for _, choice in ipairs(INTERACT.OWN[key] or INTERACT.CHOICES) do choices[choice] = true end
        enumSettings[key] = choices
    end
    enumSettings.objectPlates = { platesmith = true, blizzard = true }
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
    classification = { 8, -2 }, quest = { 8, -2 }, combo = { 8, -2 }, tagged = { 8, -3 }, cast = { 7, -4 },
    statusText = { 8, -2 } }
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

-- The Elite / rare mark's styles that place parts (classificationStyle). An enemy plate (Lifecycle's ApplyLayout)
-- and Studio's preview (Options:EditorDrawnLayout) draw an enemy layout through MARK.Layout: the style's placement
-- over the player's, which is never written, so another style shows the player's own placement again.
--   dragon (Classic dragon): the level pinned right of the health bar (Placement and the preview then centre it a
--     dragon's curl past the bar's end), the mark on the level (its dragon is placed round it) and drawn under it;
--     what was pinned to the level takes its place, as when the level is turned off (PinTarget).
--   beforeName (Before the name): the mark pinned left of the name, GAP away; a level pinned left of the name moves
--     left of the mark (on a mob without one it takes the mark's place, beside the name), and a name pinned right
--     of the level moves right of the mark; what was pinned to the mark takes its place.
-- Nothing is placed for a mark turned off or deleted, a Classic dragon whose health bar is turned off, or a
-- placement that would pin a part round a loop. MARK.Placed(layout): the entries a placement changed.
local MARK = { GAP = 2 }
do
    local placedBy = setmetatable({}, { __mode = "k" })
    local NONE = {}
    -- Per style, layout -> its placement (false: none), for the plates, whose layouts are replaced, never changed.
    local cache = { dragon = setmetatable({}, { __mode = "k" }), beforeName = setmetatable({}, { __mode = "k" }) }
    MARK.PLACING = { dragon = true, beforeName = true }

    local function Copy(position)
        local copy = {}
        for field, value in pairs(position) do copy[field] = value end
        return copy
    end

    -- What sat on key takes its place in result: pinned to a part key was pinned to, it meets that part on its own
    -- edge with its own gap (PinTarget's way); otherwise it takes key's own placement.
    local function Vacate(result, layout, key, changed)
        local from = layout[key]
        for other, position in pairs(layout) do
            if type(position) == "table" and position.parent == key and not changed[other] then
                local entry = Copy(position)
                if entry.attach and from.attach and IsPartKey(layout, from.parent) then
                    entry.parent = from.parent
                else
                    entry.parent, entry.attach, entry.free, entry.x, entry.y = from.parent, from.attach, from.free, from.x, from.y
                end
                result[other], changed[other] = entry, true
            end
        end
    end

    local function Loops(layout)
        for key, position in pairs(layout) do
            local node = type(position) == "table" and position.parent
            for _ = 0, MAX_DEPTH do
                if node == key then return true end
                local entry = type(node) == "string" and layout[node]
                if type(entry) ~= "table" then break end
                node = entry.parent
            end
        end
        return false
    end

    -- layout with style's placement, a new table (entries it does not change are layout's own), or layout itself.
    function MARK.Build(layout, style)
        if not MARK.PLACING[style] or type(layout) ~= "table" then return layout end
        local mark, level, name, health = layout.classification, layout.level, layout.name, layout.health
        if type(mark) ~= "table" or TurnedOff(mark) then return layout end
        local result, changed = {}, { classification = true }
        for key, position in pairs(layout) do result[key] = position end
        local placed = Copy(mark)
        placed.free, placed.y = nil, 0
        if style == "dragon" then
            if type(level) ~= "table" or level.removed or type(health) ~= "table" or TurnedOff(health) then return layout end
            local entry = Copy(level)
            entry.parent, entry.attach, entry.free, entry.x, entry.y = "health", "right", nil, MARK.GAP, 0
            placed.parent, placed.attach, placed.x, placed.scale = "level", "right", 0, nil
            -- Under the level (a child draws over its parent at the same layer), so the dragon never covers it.
            -- (-10: the lowest layer, LAYER_RANGE.)
            local layer = tonumber(level.layer) or 0
            entry.layer, placed.layer = layer, math.max(-10, layer - 1)
            result.level, changed.level = entry, true
            Vacate(result, layout, "level", changed)
        else
            local nameAfterLevel = type(name) == "table" and name.parent == "level" and name.attach == "right"
            if nameAfterLevel then
                placed.parent, placed.attach, placed.x = "level", "right", MARK.GAP
                local entry = Copy(name)
                entry.parent = "classification"
                result.name, changed.name = entry, true
            else
                placed.parent, placed.attach, placed.x = "name", "left", -MARK.GAP
                if type(level) == "table" and level.parent == "name" and level.attach == "left" then
                    local entry = Copy(level)
                    entry.parent = "classification"
                    result.level, changed.level = entry, true
                end
            end
            Vacate(result, layout, "classification", changed)
        end
        result.classification = placed
        if Loops(result) then return layout end
        placedBy[result] = changed
        return result
    end

    -- MARK.Build, kept per layout table and style (a plate's layout is replaced when it changes, never edited).
    function MARK.Layout(layout, style)
        local byStyle = cache[style]
        if not byStyle or type(layout) ~= "table" then return layout end
        local result = byStyle[layout]
        if result == nil then
            result = MARK.Build(layout, style)
            -- false for none: a value naming its weak key would keep the key alive.
            byStyle[layout] = result ~= layout and result or false
        end
        return result or layout
    end

    -- key -> true for each entry layout's placement changed (none for a layout MARK.Build did not make).
    function MARK.Placed(layout)
        return placedBy[layout] or NONE
    end
end

local SortByTreeOrder, LayoutTransforms
do
    -- One comparator for every sort (no closure per call): the layout and fallback being sorted.
    local sortLayout, sortFallback
    local function TreeOrder(left, right)
        local a, b = sortLayout[left].order or sortFallback, sortLayout[right].order or sortFallback
        if a ~= b then return a < b end
        return left < right
    end

    -- Sorts keys (entries of layout) in place into tree order: by each entry's order (unset:
    -- fallback, 99 by default), then by key. Returns keys.
    SortByTreeOrder = function(layout, keys, fallback)
        sortLayout, sortFallback = layout, fallback or 99
        table.sort(keys, TreeOrder)
        sortLayout = nil
        return keys
    end

    -- Where a part with no place of its own (or past MAX_DEPTH, or in a cycle) is drawn. Read only.
    local ORIGIN = { x = 0, y = 0, scale = 1 }

    local function Clear(map) for key in pairs(map) do map[key] = nil end end

    -- One parent's stacked children's offsets (st: the call's working tables, LayoutTransforms).
    local function StackOffsets(st, parentKey)
        local stacks, layout = st.stacks, st.layout
        if stacks[parentKey] then return stacks[parentKey] end
        local offsets = st.offsetTables[parentKey]
        if offsets then Clear(offsets) else
            offsets = {}
            st.offsetTables[parentKey] = offsets
        end
        stacks[parentKey] = offsets
        local parent, keys, children = layout[parentKey], st.keys, st.children
        for index = #keys, 1, -1 do keys[index] = nil end
        for key, position in pairs(layout) do
            if type(position) == "table" and position.parent == parentKey and not position.free
                and position.visible ~= false and not position.removed then
                keys[#keys + 1] = key
            end
        end
        local count = 0
        for _, key in ipairs(SortByTreeOrder(layout, keys)) do
            -- measure(key) -> width, height[, hidden[, boxX, boxY]]: box* is the drawn box's
            -- centre from the part's own centre (an aura grid's further lines), own units.
            local width, height, hidden, boxX, boxY = st.measure(key)
            if width and height then
                count = count + 1
                local child = children[count] or {}
                children[count] = child
                child.key, child.width, child.height, child.hidden = key, width, height, hidden
                child.boxX, child.boxY = tonumber(boxX) or 0, tonumber(boxY) or 0
            end
        end
        local direction, gap = parent.stack, tonumber(parent.gap) or 0
        local vertical = direction == "down" or direction == "up"
        local sign = (direction == "down" or direction == "left") and -1 or 1
        -- The stack starts at the first child's leading edge (it keeps its own offset). Each
        -- shown child follows the last; a hidden one (measure's third result) is placed where
        -- it would go but takes no space, so what follows closes up until it shows.
        local edge
        for index = 1, count do
            local child = children[index]
            local position = layout[child.key]
            local own = tonumber(position.scale) or 1
            local half = (vertical and child.height or child.width) * own / 2
            local x, y = tonumber(position.x) or 0, tonumber(position.y) or 0
            local box = (vertical and child.boxY or child.boxX) * own
            if not edge then edge = (vertical and y or x) + box - sign * half end
            local along = edge + sign * half - box
            if vertical then y = along else x = along end
            if not child.hidden then edge = edge + sign * (2 * half + gap) end
            -- A part has one parent, so its offset table is its own.
            local point = st.points[child.key] or {}
            st.points[child.key] = point
            point.x, point.y = x, y
            offsets[child.key] = point
        end
        return offsets
    end

    local function Resolve(st, key, depth)
        local result, layout, measure, visiting = st.result, st.layout, st.measure, st.visiting
        local done = result[key]
        if done then return done end
        local position = layout[key]
        if type(position) ~= "table" or visiting[key] or depth > MAX_DEPTH then return ORIGIN end
        visiting[key] = true
        local parentEntry = position.parent and layout[position.parent]
        local parent = parentEntry and Resolve(st, position.parent, depth + 1) or ORIGIN
        visiting[key] = nil
        local x, y = tonumber(position.x) or 0, tonumber(position.y) or 0
        if measure and parentEntry and STACK_DIRECTIONS[parentEntry.stack] then
            local stacked = StackOffsets(st, position.parent)[key]
            if stacked then x, y = stacked.x, stacked.y end
        end
        local scale = parent.scale * (tonumber(position.scale) or 1)
        local transform = st.transforms[key] or {}
        st.transforms[key] = transform
        transform.x, transform.y, transform.scale = parent.x + x * parent.scale, parent.y + y * parent.scale, scale
        -- Dynamic: pinned to an edge of its parent part. (x, y) is then the gap from the parent's
        -- edge to the part's facing edge, so it follows the parent's size (a longer name moves a
        -- level pinned to its left). Needs sizes; a group parent has none, so it stays static.
        -- A turned-off parent passes its place on (PinTarget); the gap stays in the parent's units.
        local edge = ATTACH_EDGES[position.attach]
        local target = edge and measure and PinTarget(layout, key, st.absent)
        if target then
            local base = parent
            if target ~= position.parent then
                visiting[key] = true
                base = Resolve(st, target, depth + 1)
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

    -- key -> { x, y, scale } drawn from the plate's centre, for every entry of layout. measure(key),
    -- when given, returns a part's width and height in its own units (nil: not stacked); without
    -- it stacks are not applied. absent(key), when given, says a part has nothing to show on this
    -- plate right now (see PinTarget). into: a table the caller keeps (a plate's), whose tables
    -- are reused: the result is then the same table each call, filled again (a plate's relayout,
    -- as a cast bar or aura row shows or hides in combat, makes no tables).
    LayoutTransforms = function(layout, measure, absent, into)
        local st = into or {}
        st.result, st.visiting, st.stacks = st.result or {}, st.visiting or {}, st.stacks or {}
        st.transforms, st.points, st.offsetTables = st.transforms or {}, st.points or {}, st.offsetTables or {}
        st.keys, st.children = st.keys or {}, st.children or {}
        Clear(st.result)
        Clear(st.visiting)
        Clear(st.stacks)
        st.layout, st.measure, st.absent = layout, measure, absent
        for key in pairs(layout) do Resolve(st, key, 0) end
        st.layout, st.measure, st.absent = nil, nil, nil
        return st.result
    end
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

-- into: a table the caller keeps (Studio's preview, which works the order out several times a refresh), whose
-- tables are reused: rank is then the same table each call, filled again. Without it every table is new (the
-- plates keep each layout's result: Styles' drawOrderCache).
local DrawOrder
do
    local function Clear(map) for key in pairs(map) do map[key] = nil end end
    -- Front to back: a part's children before the part itself (they draw on it, as a value on
    -- its bar), and higher siblings, with everything under them, before lower ones.
    local function Walk(st, parentKey, inherited, depth)
        local list = st.children[parentKey]
        if not list then return end
        local layout, sequence, effective = st.layout, st.sequence, st.effective
        for index = 1, #list do
            local key = list[index]
            local layer = tonumber(layout[key].layer) or inherited
            if depth < MAX_DEPTH then Walk(st, key, layer, depth + 1) end
            if not IsGroupKey(key) then
                sequence[#sequence + 1] = key
                effective[key] = layer
            end
        end
    end
    -- One comparator (no closure per call): the call's effective layers and tree places.
    local sortEffective, sortTreeIndex
    local function Front(left, right)
        if sortEffective[left] ~= sortEffective[right] then return sortEffective[left] > sortEffective[right] end
        return sortTreeIndex[left] < sortTreeIndex[right]
    end
    DrawOrder = function(layout, into)
        local st = into or {}
        st.children, st.lists = st.children or {}, st.lists or {}
        st.sequence, st.effective = st.sequence or {}, st.effective or {}
        st.treeIndex, st.rank = st.treeIndex or {}, st.rank or {}
        local children, lists = st.children, st.lists
        -- Each parent's list of children; the lists are kept for the next call (cleared, not dropped).
        for parent, list in pairs(children) do
            for index = #list, 1, -1 do list[index] = nil end
            lists[#lists + 1] = list
            children[parent] = nil
        end
        for key, position in pairs(layout) do
            if type(position) == "table" then
                local parent = position.parent and layout[position.parent] and position.parent or false
                local list = children[parent]
                if not list then
                    list = lists[#lists] or {}
                    lists[#lists] = nil
                    children[parent] = list
                end
                list[#list + 1] = key
            end
        end
        for _, list in pairs(children) do SortByTreeOrder(layout, list) end
        local sequence, effective, treeIndex, rank = st.sequence, st.effective, st.treeIndex, st.rank
        for index = #sequence, 1, -1 do sequence[index] = nil end
        Clear(effective)
        Clear(treeIndex)
        Clear(rank)
        st.layout = layout
        Walk(st, false, 0, 0)
        st.layout = nil
        for index, key in ipairs(sequence) do treeIndex[key] = index end
        sortEffective, sortTreeIndex = effective, treeIndex
        table.sort(sequence, Front)
        sortEffective, sortTreeIndex = nil, nil
        for index, key in ipairs(sequence) do rank[key] = index end
        return rank, #sequence
    end
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
-- claimed (NormalizeSettings' own pass over a profile's layouts): position itself is returned when it
-- is already exactly the valid entry and no other layout of this pass took it (claimed[position]), so
-- normalising a saved profile again makes no garbage; anything else gets a new table, as always.
local function NormalizeLayoutEntry(key, position, claimed)
    local x, y = tonumber(position.x), tonumber(position.y)
    if not (x and y) then return nil end
    -- Only layouts from before Dynamic placement carry followName (their upgrade
    -- reads it); it is never added.
    local followName
    if key == "level" and position.followName ~= nil then followName = position.followName ~= false end
    x, y = Bounded(layoutRanges.x, x), Bounded(layoutRanges.y, y)
    local scale = ComponentScale(position.scale)
    local parent = type(position.parent) == "string" and position.parent ~= key and position.parent or nil
    local order = tonumber(position.order) and math.floor(math.max(0, math.min(99, position.order))) or nil
    -- A built-in part the player deleted: off the tree and the plate until added back.
    local removed = position.removed == true or nil
    local stack = STACK_DIRECTIONS[position.stack] and position.stack or nil
    local gap = STACK_DIRECTIONS[position.stack] and Bounded(STACK_GAP, position.gap, 0) or nil
    local free = position.free == true or nil
    local layer = tonumber(position.layer) and Bounded(LAYER_RANGE, position.layer) or nil
    local attach = ATTACH_EDGES[position.attach] and position.attach or nil
    local visible = position.visible ~= false and not removed
    local group, name = IsGroupKey(key), nil
    if group then
        name = NormalizeGroupName(position.name) or "Group"
    elseif type(position.name) == "string" then
        -- A built-in part's own name in Studio's tree (nil: its standard name).
        name = NormalizeGroupName(position.name)
    end
    local finalOrder = group and math.floor(tonumber(position.order) or 0) or order
    if claimed and not claimed[position] and position.x == x and position.y == y and position.visible == visible
        and position.scale == scale and position.followName == followName and position.parent == parent
        and position.order == finalOrder and position.removed == removed and position.stack == stack
        and position.gap == gap and position.free == free and position.layer == layer and position.attach == attach
        and position.name == name then
        -- Every field matches; no other key: as many keys as the entry would have (x, y, visible, scale and
        -- each optional field that is set).
        local fields, count = 4 + (followName ~= nil and 1 or 0) + (parent and 1 or 0) + (finalOrder and 1 or 0)
            + (removed and 1 or 0) + (stack and 1 or 0) + (gap and 1 or 0) + (free and 1 or 0) + (layer and 1 or 0)
            + (attach and 1 or 0) + (name and 1 or 0), 0
        for _ in pairs(position) do count = count + 1 end
        if count == fields then
            claimed[position] = true
            return position
        end
    end
    -- Sized for the eight fields most entries have; the rarer ones are added.
    local entry = { x = x, y = y, visible = visible, scale = scale, parent = parent, order = order, layer = layer,
        attach = attach }
    if followName ~= nil then entry.followName = followName end
    if removed then entry.removed = removed end
    if stack then entry.stack, entry.gap = stack, gap end
    if free then entry.free = free end
    if group then
        entry.name = name
        entry.order = finalOrder
    elseif type(position.name) == "string" then
        entry.name = name
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

-- A new layout table. claimed: see NormalizeLayoutEntry (only NormalizeSettings passes it, for a
-- profile's own layouts, which the result replaces).
local function NormalizeLayout(layout, fallbackLayout, claimed)
    fallbackLayout = fallbackLayout or defaultLayout
    local normalized = {}
    if type(layout) == "table" then
        for key, position in pairs(layout) do
            if PartKey(key) and type(position) == "table" then
                normalized[key] = NormalizeLayoutEntry(key, position, claimed)
            end
        end
    end
    -- Missing parts come from the fallback with their place in its tree; a new layout takes all
    -- its groups (the default template), an existing one only a group a copied part sits in.
    local fresh = next(normalized) == nil
    -- The fields most entries have in the table made (sized for eight); a group's stack, gap and name added.
    local function Copy(key, position, shown)
        local entry = { x = position.x, y = position.y, visible = (shown or position).visible ~= false,
            scale = ComponentScale(position.scale), parent = position.parent, order = position.order,
            layer = position.layer, attach = position.attach }
        if position.stack ~= nil then entry.stack = position.stack end
        if position.gap ~= nil then entry.gap = position.gap end
        if position.name ~= nil then entry.name = position.name end
        normalized[key] = entry
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
    -- A parent must exist, and the chain must end: a cycle or a chain past MAX_DEPTH is cut. (A chain
    -- that comes back to a part it passed never ends, so it passes MAX_DEPTH too: no table of parts seen.)
    for _, position in pairs(normalized) do
        if position.parent and not normalized[position.parent] then position.parent = nil end
    end
    for _, position in pairs(normalized) do
        local current, depth = position.parent, 0
        while current do
            depth = depth + 1
            if depth > MAX_DEPTH then position.parent = nil break end
            current = normalized[current] and normalized[current].parent
        end
    end
    return normalized
end

local function NormalizeColour(colour, fallback)
    colour = type(colour) == "table" and colour or fallback
    return { r = Format.Unit(colour.r, fallback.r), g = Format.Unit(colour.g, fallback.g), b = Format.Unit(colour.b, fallback.b) }
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
    backdropWidth = 120, backdropHeight = 40, backdropEdge = 1,
}

-- A multi-part choice (the soft glow's Glow parts, a Backdrop's Parts): the ticked parts of PARTS stored as one value,
-- their names joined by commas in PARTS' order ("name,health"), or "none". VALUES holds every such value. Set reads a
-- value as a set (shared, never written; nil for DEFAULT or a value not in VALUES), Ticked as a set always (DEFAULT's
-- for those), and Value names a set again (nil: every part). PartChoices.New makes one; the Backdrop's is kept here.
local PartChoices = {}
function PartChoices.New(parts, default)
    local choice = { PARTS = parts, DEFAULT = default, VALUES = { none = true }, sets = {} }
    for mask = 1, 2 ^ #parts - 1 do
        local names = {}
        for index, part in ipairs(parts) do
            if math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then names[#names + 1] = part end
        end
        choice.VALUES[table.concat(names, ",")] = true
    end
    local function Read(value)
        local set = choice.sets[value]
        if not set then
            set = {}
            if value ~= "none" then
                for part in string.gmatch(value, "[^,]+") do set[part] = true end
            end
            choice.sets[value] = set
        end
        return set
    end
    function choice.Set(value)
        if value == choice.DEFAULT or not choice.VALUES[value] then return nil end
        return Read(value)
    end
    function choice.Ticked(value)
        return choice.Set(value) or Read(choice.DEFAULT)
    end
    function choice.Value(set)
        local names = {}
        for _, part in ipairs(parts) do
            if set == nil or set[part] then names[#names + 1] = part end
        end
        return #names > 0 and table.concat(names, ",") or "none"
    end
    return choice
end

-- The Backdrop part (Objects; Nameplates/Backdrop.lua): a box drawn behind other parts, styled like a text's box
-- (boxShape, boxColour, boxBorder, padding) with an edge of style border px (nil: backdropEdge). backdropWrap: nil fits
-- round the shown parts of backdropParts (PartChoice over PARTS; nil: DEFAULT), "fixed" is backdropWidth by
-- backdropHeight (SIZE) centred on its own place.
PartChoices.backdrop = PartChoices.New({ "name", "statusText", "actionIcon", "quest" }, "name,statusText,actionIcon")
PartChoices.backdrop.SIZE, PartChoices.backdrop.WRAPS = { 8, 400, true }, { parts = true, fixed = true }

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
            entry.boxHeight = style.boxHeight == "parent" and "parent" or nil
            entry.pipAnchor = STYLE_PIP_ANCHORS[style.pipAnchor] and style.pipAnchor or nil
            entry.pipClassColour = style.pipClassColour == true or nil
            entry.pipGlow = style.pipGlow == true or nil
            entry.pipFit = style.pipFit == true or nil
            entry.pipShowRow = STYLE_PIP_SHOW_ROWS[style.pipShowRow] and style.pipShowRow or nil
            -- The Action icon's "can't" icons (Unable*): nil as the game gives them, greyed, or hidden.
            entry.iconUnable = (style.iconUnable == "grey" or style.iconUnable == "hide") and style.iconUnable or nil
            -- The Loose mark's (Nameplates/LooseMark.lua): who it shows for (nil tanks, all everyone), its icon (nil
            -- the game's alert, window the Tank window's LOOSE icon), and its pulse (nil on, false off).
            entry.looseFor = style.looseFor == "all" and "all" or nil
            entry.looseIcon = style.looseIcon == "window" and "window" or nil
            if style.loosePulse == false then entry.loosePulse = false end
            -- The Backdrop's wrap, the parts it fits round (the default stored as nil) and its fixed size.
            entry.backdropWrap = style.backdropWrap == "fixed" and "fixed" or nil
            local backdrop = PartChoices.backdrop
            entry.backdropParts = backdrop.Set(style.backdropParts) and style.backdropParts or nil
            entry.backdropWidth = tonumber(style.backdropWidth) and Bounded(backdrop.SIZE, style.backdropWidth) or nil
            entry.backdropHeight = tonumber(style.backdropHeight) and Bounded(backdrop.SIZE, style.backdropHeight) or nil
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
local PRESET_KINDS, MAX_PRESETS, PRESET_NAME_LENGTH = { text = true, bar = true, pips = true, badges = true, backdrop = true },
    40, 24
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
    "targetGlowOpacity", "targetGlowOffsetX", "targetGlowOffsetY", "targetGlowPulse", "targetGlowWrap", "targetGlowParts",
    "targetGlowEven", "targetGlowSpreadY", "targetGlowWidth", "targetGlowHeight" }, SET = {},
    BOOLEAN = { targetGlowPulse = true, targetGlowEven = true }, GLOW_PARTS = { "name", "health", "power", "cast" } }
for _, key in ipairs(HIGHLIGHT.KEYS) do HIGHLIGHT.SET[key] = true end
-- The parts a "parts" glow may wrap (GLOW_PARTS; PartChoice): targetGlowParts is the ticked ones ("name,health"), or
-- "none". PartsSet reads a value as a set, or nil for every part (the default, or not a valid value); PartsValue names
-- a set again.
HIGHLIGHT.GLOW = PartChoices.New(HIGHLIGHT.GLOW_PARTS, defaults.targetGlowParts)
for value in pairs(HIGHLIGHT.GLOW.VALUES) do enumSettings.targetGlowParts[value] = true end
HIGHLIGHT.PartsSet, HIGHLIGHT.PartsValue = HIGHLIGHT.GLOW.Set, HIGHLIGHT.GLOW.Value
function HIGHLIGHT.Value(key, value)
    if value == nil or not HIGHLIGHT.SET[key] then return nil end
    if HIGHLIGHT.BOOLEAN[key] then
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

-- plateHidden: an object type's own (Designs.TYPES; Settings refuses it elsewhere): true draws none of those plates,
-- absent draws them.
local function IsProfileOption(key)
    return profileRanges[key] ~= nil or optionalProfileRanges[key] ~= nil or key == "healthTexture"
        or key == "healthColourMode" or key == "castColours" or castOptions[key] ~= nil or HIGHLIGHT.SET[key] == true
        or key == "plateHidden"
end

-- One profile option made valid for profile (fallback: its defaults). NormalizeProfile checks
-- every option this way; Settings writes a single one.
local function ProfileOptionValue(profile, key, value, fallback)
    if HIGHLIGHT.SET[key] then return HIGHLIGHT.Value(key, value) end
    if key == "plateHidden" then return value == true or nil end
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

-- One custom part's record made valid (slot: anything; a missing one is an unused slot). claimed: as
-- NormalizeLayoutEntry's, the slot itself when it is already exactly valid (its colour too).
local function NormalizeValueSlot(slot, claimed)
    slot = type(slot) == "table" and slot or {}
    local base = DEFAULT_VALUE_SLOT
    local colour = slot.colour
    if claimed and not claimed[slot] and slot ~= base and type(colour) == "table" and colour ~= base.colour
        and not claimed[colour] and slot.source == (valueSources[slot.source] and slot.source or base.source)
        and slot.anchor == (valueAnchors[slot.anchor] and slot.anchor or base.anchor)
        and slot.layer == (valueLayers[slot.layer] and slot.layer or base.layer)
        and slot.whenMissing == (missingAnchorModes[slot.whenMissing] and slot.whenMissing or base.whenMissing)
        and slot.fontSize == Bounded(valueFontRange, slot.fontSize, base.fontSize)
        and slot.kind == (valueKinds[slot.kind] and slot.kind ~= "text" and slot.kind or nil)
        and slot.width == (tonumber(slot.width) and Bounded(VALUE_WIDTH, slot.width) or nil)
        and slot.height == (tonumber(slot.height) and Bounded(VALUE_HEIGHT, slot.height) or nil)
        and slot.icon == (valueIcons[slot.icon] and slot.icon or nil)
        and colour.r == Format.Unit(colour.r, base.colour.r) and colour.g == Format.Unit(colour.g, base.colour.g)
        and colour.b == Format.Unit(colour.b, base.colour.b)
        and slot.name == NormalizeValueName(slot.name) and slot.template == NormalizeValueTemplate(slot.template) then
        -- No other key: source, anchor, layer, whenMissing, fontSize, colour and each optional one set.
        local fields, count, channels = 6 + (slot.kind and 1 or 0) + (slot.width and 1 or 0) + (slot.height and 1 or 0)
            + (slot.icon and 1 or 0) + (slot.name and 1 or 0) + (slot.template and 1 or 0), 0, 0
        for _ in pairs(slot) do count = count + 1 end
        for _ in pairs(colour) do channels = channels + 1 end
        if count == fields and channels == 3 then
            claimed[slot], claimed[colour] = true, true
            return slot
        end
    end
    -- Sized for the six fields every slot has and two more; a slot with more grows.
    local result = {
        source = valueSources[slot.source] and slot.source or base.source,
        anchor = valueAnchors[slot.anchor] and slot.anchor or base.anchor,
        layer = valueLayers[slot.layer] and slot.layer or base.layer,
        whenMissing = missingAnchorModes[slot.whenMissing] and slot.whenMissing or base.whenMissing,
        fontSize = Bounded(valueFontRange, slot.fontSize, base.fontSize),
        colour = NormalizeColour(slot.colour, base.colour),
        name = NormalizeValueName(slot.name),
        template = NormalizeValueTemplate(slot.template),
    }
    result.kind = valueKinds[slot.kind] and slot.kind ~= "text" and slot.kind or nil
    if tonumber(slot.width) then result.width = Bounded(VALUE_WIDTH, slot.width) end
    if tonumber(slot.height) then result.height = Bounded(VALUE_HEIGHT, slot.height) end
    result.icon = valueIcons[slot.icon] and slot.icon or nil
    return result
end

-- fresh: a new profile (NormalizeSettings' new table), which starts with the template's own part
-- styles (fallback.styles) unless it brings its own. claimed: NormalizeSettings' (see
-- NormalizeLayoutEntry): the profile's own layout entries and custom parts that are already valid are
-- kept, never one taken from legacy or the fallback.
local function NormalizeProfile(profile, fallback, legacy, fresh, claimed)
    profile = type(profile) == "table" and profile or {}
    legacy = type(legacy) == "table" and legacy or {}
    if fresh and profile.styles == nil and fallback.styles then profile.styles = Table.DeepCopy(fallback.styles) end
    local previousLayout = profile.layout or legacy.layout
    for key, range in pairs(profileRanges) do
        profile[key] = Bounded(range, profile[key], legacy[key], fallback[key])
    end
    for key in pairs(optionalProfileRanges) do profile[key] = ProfileOptionValue(profile, key, profile[key], fallback) end
    profile.healthTexture = ProfileOptionValue(profile, "healthTexture", profile.healthTexture, fallback)
    profile.healthColourMode = ProfileOptionValue(profile, "healthColourMode", profile.healthColourMode, fallback)
    for key in pairs(castOptions) do profile[key] = ProfileOptionValue(profile, key, profile[key], fallback) end
    for _, key in ipairs(HIGHLIGHT.KEYS) do profile[key] = HIGHLIGHT.Value(key, profile[key]) end
    profile.plateHidden = profile.plateHidden == true or nil
    profile.healthColour = NormalizeColour(profile.healthColour, fallback.healthColour)
    profile.castColours = NormalizeCastColours(profile.castColours, fallback.castColours)
    profile.valueSlots = type(profile.valueSlots) == "table" and profile.valueSlots or {}
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        profile.valueSlots[key] = NormalizeValueSlot(profile.valueSlots[key], claimed)
    end
    profile.layout = NormalizeLayout(profile.layout or legacy.layout, fallback.layout, profile.layout and claimed or nil)
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
            profile.namesLayout = NormalizeLayout(profile.namesLayout, fallback.namesLayout, claimed)
        end
        profile.dungeonNamesLayout = NormalizeLayout(profile.dungeonNamesLayout, fallback.dungeonNamesLayout, claimed)
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
        friendlyNPC = { pvp = true, city = true }, object = { dungeon = true, pvp = true, city = true } },
    KNOWN = { world = true, dungeon = true, pvp = true, city = true },
    LAYOUT_FIELDS = { "layout", "namesLayout" },
    -- A layout entry's placement is one unit: offsets only make sense with their parent and pin.
    PLACEMENT = { "x", "y", "scale", "parent", "attach", "free", "stack", "gap", "layer", "order" },
    STYLE_FIELDS = { font = true, fontSize = true, outline = true, shadow = true, box = true, boxColour = true,
        boxBorder = true, padding = true, texture = true, background = true, border = true, borderColour = true,
        pipFill = true, pipEmpty = true, pipWidth = true, pipHeight = true, pipSpacing = true,
        pipShape = true, pipAnchor = true, pipClassColour = true, pipGlow = true, pipFit = true, pipShowRow = true,
        boxShape = true, boxHeight = true,
        badgeSize = true, badgeSpacing = true, badgeOrientation = true, badgeInitial = true, iconUnable = true,
        looseFor = true, looseIcon = true, loosePulse = true, backdropWrap = true, backdropParts = true,
        backdropWidth = true, backdropHeight = true },
    -- Entries per layout and style parts a sparse design may hold.
    MAX_ENTRIES = 64,
    -- "-" lists keys cleared (nil) here; PartKey's leading letter keeps it apart from every name.
    CLEAR = "-",
    -- Object types (plateProfiles.object.types.<type>, Core/Designs.lua): a sparse layer each over whichever design
    -- objects draw with, picked per plate from the game's cursor icon (ActionIcon.TYPE_OF). In Studio's Type order.
    TYPES = { "herb", "ore", "loot", "quest", "book", "service", "other" },
}
DESIGN.TYPE_SET = {}
for _, key in ipairs(DESIGN.TYPES) do DESIGN.TYPE_SET[key] = true end

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
    if key == "plateHidden" then return value == true or nil end
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
local function NormalizeContexts(profile, plateType, claimed)
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
                    record.design = NormalizeProfile(record.design, profile, nil, nil, claimed)
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

local function NormalizeProfiles(profiles, legacy, fresh, claimed)
    profiles = type(profiles) == "table" and profiles or {}
    for _, key in ipairs(profileOrder) do
        -- Objects never had the old top-level settings (legacy: the Enemies' sizes and layout), and a profile
        -- without them starts with their whole default, its box included (as migration 32 gives them).
        local object = key == "object"
        profiles[key] = NormalizeProfile(profiles[key], profileDefaults[key], not object and legacy or nil,
            fresh or (object and type(profiles[key]) ~= "table"), claimed)
        NormalizeContexts(profiles[key], key, claimed)
    end
    -- The Enemy players layer (Designs.lua): a sparse design over the Enemies'; an empty one stays
    -- (made in Studio, it changes nothing yet).
    profiles.enemy.players = NormalizeDesign(profiles.enemy.players, "enemy")
    -- Object types (Designs.TYPES): sparse layers over the Objects' designs; an empty one goes (no type has a
    -- record until it changes something). A table under an unknown key (a newer version's type) is kept as it is.
    local types = profiles.object.types
    if type(types) == "table" then
        for key, record in pairs(types) do
            if DESIGN.TYPE_SET[key] then
                local design = NormalizeDesign(record, "object")
                types[key] = design and next(design) ~= nil and design or nil
            elseif type(key) ~= "string" or type(record) ~= "table" then
                types[key] = nil
            end
        end
        if next(types) == nil then profiles.object.types = nil end
    else
        profiles.object.types = nil
    end
    -- Saved data from before schema 29 still holds the dungeon override here until migration 28
    -- moves it into the Enemies' contexts; older migrations normalise it where it is.
    if type(profiles.enemyDungeon) == "table" then
        profiles.enemyDungeon = NormalizeProfile(profiles.enemyDungeon, profiles.enemy, nil, nil, claimed)
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
    object = { "layout" },
}
-- Enemy players draw with the Enemies' designs plus their own layer (Designs.EachDesign visits it).
local ENEMY_PLATES = { enemy = true, enemyPlayer = true }
local THREAT_SOURCES = { threatPercent = true, leadPercent = true, rawThreat = true, differential = true }
-- sources: custom parts showing one of these values were kept off by the switch too.
local PART_SWITCHES = {
    { key = "quest", parts = { "quest", "questLoot" },
        plates = { enemy = true, enemyPlayer = true, friendlyNPC = true, object = true } },
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
-- enemy design's; a friendly design's full or names-only layout by its type's Show as (FRIENDLY.Mode;
-- none while that type shows Blizzard's plates), and World's dungeon layout while the dungeon overlay is on.
-- visit(layout, profile, field, plateType, context, record) (record: a context design's, as EachDesign).
local function EachLiveLayout(settings, switch, visit)
    PS.Designs.EachDesign(settings, switch.plates, function(profile, plateType, context, record)
        local fields
        -- Objects have one layout, drawn while PlateSmith draws them (objectPlates).
        if plateType == "object" then
            fields = { settings.objectPlates ~= "blizzard" and "layout" or nil }
        elseif ENEMY_PLATES[plateType] then
            fields = { "layout" }
        else
            fields = {}
            local mode = FRIENDLY.Mode(settings, plateType)
            if mode == "full" then fields[1] = "layout"
            elseif mode == "names" and not switch.fullOnly then fields[1] = "namesLayout" end
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
    -- The Loose mark on an enemy layout, or the extras on Blizzard's plates that show threat (Nameplates/Extras.lua).
    local loose = false
    EachPlateLayout(settings, ENEMY_PLATES, function(layout)
        loose = loose or (type(layout.looseMark) == "table" and not TurnedOff(layout.looseMark))
    end)
    if loose or PS.ProfileSchema.EXTRAS.ReadsThreat(settings) then return true end
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
    [29] = function(settings)
        -- Target highlight Off now draws no gold edge either; a saved profile keeps the edge it had.
        if settings.targetOffKeepsEdge == nil then settings.targetOffKeepsEdge = true end
        settings.schemaVersion = 30
    end,
    [30] = function(settings)
        -- Grey when tagged by others is new and on for new profiles; a saved profile keeps its TAGGED word and its
        -- health bar's colours (off). A rule of its own (the old Grey when tagged preset) stays as it is.
        if settings.greyWhenTagged == nil then settings.greyWhenTagged = false end
        settings.schemaVersion = 31
    end,
    [31] = function(settings)
        -- Stacking & distance lost its Manage switch: every value a profile keeps is now applied. A profile
        -- with the switch off applied nothing, so it keeps nothing that would start changing the game: its
        -- values go (the game's own stand, as they did), the preset is Custom, and the two options that
        -- changed Blizzard's plates (frame size, combat stacking) are off. A profile with it on keeps all.
        local stacking = settings.stacking
        if type(stacking) == "table" then
            if stacking.managed ~= true then
                stacking.values, stacking.preset = {}, "custom"
                stacking.matchFrameSize, stacking.combatStacking = false, false
            end
            stacking.managed = nil
        end
        settings.schemaVersion = 32
    end,
    [32] = function(settings)
        -- Objects (books, chests) became a plate type of their own. They had no look to keep (they drew with a
        -- fixed names-only Friendly NPCs plate), so a saved profile gets the new default, its tooltip-like box
        -- included; one an earlier migration of this pass made here (NormalizeProfiles) is replaced the same way.
        settings.plateProfiles = type(settings.plateProfiles) == "table" and settings.plateProfiles or {}
        settings.plateProfiles.object = Table.DeepCopy(profileDefaults.object)
        settings.schemaVersion = 33
    end,
    [33] = function(settings)
        -- Extras on Blizzard's plates are new: a saved profile keeps what Blizzard, with PlateSmith extras drew before,
        -- quest markers and threat text, with no threat edge, target glow or Loose mark. New profiles have them all.
        if settings.extrasThreat == nil then settings.extrasThreat = "text" end
        if settings.extrasTarget == nil then settings.extrasTarget = false end
        if settings.extrasLoose == nil then settings.extrasLoose = false end
        settings.schemaVersion = 34
    end,
    [34] = function(settings)
        -- Objects' tooltip-like box became the Backdrop part (1.3.0 test builds): the name's box moves to it, so the
        -- box now wraps the Status text and the Action icon too, in the same colours, edge, shape and padding. A
        -- name without its box gets the Backdrop turned off. Context designs and object types keep what they set.
        local object = type(settings.plateProfiles) == "table" and settings.plateProfiles.object
        local layout = type(object) == "table" and object.layout
        if type(layout) == "table" and layout.backdrop == nil then
            object.styles = type(object.styles) == "table" and object.styles or {}
            local name = type(object.styles.name) == "table" and object.styles.name or nil
            local boxed = name ~= nil and name.box == true
            layout.backdrop = Table.DeepCopy(profileDefaults.object.layout.backdrop)
            layout.backdrop.visible = boxed
            if boxed then
                object.styles.backdrop = { boxColour = name.boxColour, boxBorder = name.boxBorder, padding = name.padding,
                    boxShape = name.boxShape }
                name.box, name.boxColour, name.boxBorder, name.padding, name.boxShape, name.boxHeight = nil, nil, nil, nil, nil, nil
                if next(name) == nil then object.styles.name = nil end
            end
        end
        settings.schemaVersion = 35
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

-- Blizzard's nameplate stacking, distance, scale and fade CVars PlateSmith can set
-- (Nameplates/Stacking.lua), in the order the UI lists them: { key, group, kind, min, max, step,
-- default }. A choice or toggle lists its values; a number is clamped to [min, max]. default is used
-- only when the client reports none. The client reports no bounds, so these are PlateSmith's.
-- bitfield: one bit of that bitfield CVar, the bit `enum`'s `bit` (key "<cvar>.<bit>"; the 12.x clients'
-- Stack Nameplates choice, read and written with C_CVar's Get/SetCVarBitfield).
-- ignored: the game no longer reads it (nameplateMaxDistance: plates show to a fixed range since
-- about 10.2.6), so PlateSmith shows it but never writes it; a value a profile kept stays unused.
local STACKING_CVARS = {
    { "nameplateMotion", "stacking", "choice", choices = { 0, 1 }, default = 0 },
    { "nameplateStackingTypes.Enemy", "stacking", "toggle", choices = { 0, 1 }, default = 1,
        bitfield = "nameplateStackingTypes", enum = "NamePlateStackType", bit = "Enemy" },
    { "nameplateStackingTypes.Friendly", "stacking", "toggle", choices = { 0, 1 }, default = 0,
        bitfield = "nameplateStackingTypes", enum = "NamePlateStackType", bit = "Friendly" },
    { "nameplateMotionSpeed", "stacking", "number", 0, 0.5, 0.005, default = 0.025 },
    { "nameplateOverlapV", "stacking", "number", 0.2, 2.5, 0.05, default = 1.1 },
    { "nameplateOverlapH", "stacking", "number", 0.2, 2.5, 0.05, default = 0.8 },
    { "nameplateOtherTopInset", "edges", "number", -1, 0.5, 0.01, default = 0.08 },
    { "nameplateOtherBottomInset", "edges", "number", -1, 0.5, 0.01, default = 0.1 },
    { "nameplateLargeTopInset", "edges", "number", -1, 0.5, 0.01, default = 0.1 },
    { "nameplateLargeBottomInset", "edges", "number", -1, 0.5, 0.01, default = 0.15 },
    { "nameplateTargetRadialPosition", "edges", "choice", choices = { 0, 1, 2 }, default = 0 },
    { "nameplateShowOffscreen", "edges", "toggle", choices = { 0, 1 }, default = 0 },
    { "nameplateTargetBehindMaxDistance", "distance", "number", 0, 100, 1, default = 15 },
    { "nameplateMaxDistance", "distance", "number", 5, 100, 1, default = 41, ignored = true },
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

-- Fixed spacing presets (docs/STACKING.md): stacking on (nameplateMotion, or enemy plates on a client
-- with Stack Nameplates' bits), then how fast plates move apart, how far apart they stack (overlap:
-- 1 = one plate's size) and how close to the screen edges they may go.
local STACKING_PRESETS = {
    tight = { nameplateMotion = 1, ["nameplateStackingTypes.Enemy"] = 1, nameplateMotionSpeed = 0.1,
        nameplateOverlapV = 0.7, nameplateOverlapH = 0.6, nameplateOtherTopInset = 0.05,
        nameplateOtherBottomInset = 0.05, nameplateLargeTopInset = 0.05, nameplateLargeBottomInset = 0.05 },
    normal = { nameplateMotion = 1, ["nameplateStackingTypes.Enemy"] = 1, nameplateMotionSpeed = 0.05,
        nameplateOverlapV = 1.1, nameplateOverlapH = 0.8, nameplateOtherTopInset = 0.08,
        nameplateOtherBottomInset = 0.1, nameplateLargeTopInset = 0.1, nameplateLargeBottomInset = 0.15 },
    loose = { nameplateMotion = 1, ["nameplateStackingTypes.Enemy"] = 1, nameplateMotionSpeed = 0.025,
        nameplateOverlapV = 1.6, nameplateOverlapH = 1.1, nameplateOtherTopInset = 0.1,
        nameplateOtherBottomInset = 0.15, nameplateLargeTopInset = 0.12, nameplateLargeBottomInset = 0.2 },
}
local stackingPresetNames = { custom = true, tight = true, normal = true, loose = true }
-- values holds only what the player set, and PlateSmith writes each of them; anything else keeps the
-- client's own value. The two options that change Blizzard's plates start off.
local stackingDefaults = { preset = "custom", targetOnTop = true, focusOnTop = false, matchFrameSize = false,
    combatStacking = false }
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
    local result = { values = {} }
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
    -- Clicking's first test builds had one friendly row (clickFriendly, the client's whole Friendly category): its
    -- Click through is now Friendly NPCs', which drives that same category.
    if settings.clickFriendly ~= nil then
        if settings.clickFriendly == "through" and settings.clickFriendlyNPC == nil then settings.clickFriendlyNPC = "through" end
        settings.clickFriendly = nil
    end
    CopyDefaults(settings, defaults)
    for key in pairs(defaults) do
        local value = SettingValue(key, settings[key])
        if value ~= nil then settings[key] = value end
    end
    FRIENDLY.Normalize(settings)
    -- The look a profile was made from (Profiles' CreateFromPreset: a look's ID and ProfilePresets.LOOK_VERSION), or
    -- none. Not a setting: no default, never in a Blueprint (which carries Schema's lists only) nor taken from one.
    local look = settings.look
    if type(look) ~= "string" or #look > 32 or not look:match("^%w+$") then settings.look = nil end
    local lookVersion = settings.lookVersion
    if settings.look == nil or type(lookVersion) ~= "number" or lookVersion < 1 or lookVersion > 9999
        or lookVersion ~= math.floor(lookVersion) then
        settings.lookVersion = nil
    end
    settings.relationshipColours = type(settings.relationshipColours) == "table" and settings.relationshipColours or {}
    for key, fallback in pairs(defaultRelationshipColours) do
        settings.relationshipColours[key] = NormalizeColour(settings.relationshipColours[key], fallback)
    end
    settings.threatColours = THREAT_COLOURS.Normalize(settings.threatColours)
    settings.threatPartColours = THREAT_COLOURS.NormalizeParts(settings.threatPartColours, settings.threatColours)
    -- Each layout entry and custom part of the profiles that is already valid is kept, once (see
    -- NormalizeLayoutEntry): normalising a saved profile again (every load) makes little garbage.
    settings.plateProfiles = NormalizeProfiles(settings.plateProfiles, settings, fresh, {})
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
    -- meterSkin has no default: true skins Blizzard's damage meter in the threat windows' theme (Threat/MeterSkin.lua).
    -- objectTooltips has no default (Nameplates/ObjectStatus.lua): the game's tooltip lines under an object's name,
    -- by its ID from the game, read when you hover one in the world: { order = { id, ... } (oldest first), byID =
    -- { [id] = { line, ... } } }, at most objectTooltipLimits.entries of them. Never in a profile or a Blueprint.
}
-- The objectTooltips cache's bounds: entries, lines per entry, bytes per line. (A field, not a main chunk local:
-- this chunk is at Lua 5.1's 200.)
stateDefaults.objectTooltipLimits = { entries = 300, lines = 4, bytes = 120 }
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
    -- Whether 1.3.0's "threat settings moved" line was said (Profiles.Load): true or nothing.
    if state.threatMovedSaid ~= true then state.threatMovedSaid = nil end
    -- Skin Blizzard's damage meter (Threat/MeterSkin.lua): true or nothing, off by default.
    if state.meterSkin ~= true then state.meterSkin = nil end
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
    -- What PlateSmith left in each CVar it captured (NamePolicy): restore key -> { CVar name -> text }.
    local written, writtenCount = {}, 0
    for key, names in pairs(type(state.cvarWritten) == "table" and state.cvarWritten or {}) do
        if type(key) == "string" and #key <= 64 and type(names) == "table" then
            local kept = {}
            for name, value in pairs(names) do
                if type(name) == "string" and #name <= 64 and type(value) == "string" and #value <= 64 and writtenCount < 128 then
                    kept[name], writtenCount = value, writtenCount + 1
                end
            end
            if next(kept) then written[key] = kept end
        end
    end
    state.cvarWritten = next(written) and written or nil
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
    -- Kept in place when valid (ObjectStatus holds the table); each ID once, lines readable text only.
    local tooltips, limits = state.objectTooltips, stateDefaults.objectTooltipLimits
    if type(tooltips) == "table" and type(tooltips.order) == "table" and type(tooltips.byID) == "table" then
        local order, byID, seen = {}, {}, {}
        for _, id in ipairs(tooltips.order) do
            local lines = tooltips.byID[id]
            if type(id) == "number" and id > 0 and id == math.floor(id) and not seen[id] and type(lines) == "table" then
                local kept = {}
                for _, line in ipairs(lines) do
                    if type(line) == "string" and line ~= "" and #line <= limits.bytes and #kept < limits.lines then
                        kept[#kept + 1] = line
                    end
                end
                seen[id], order[#order + 1], byID[id] = true, id, kept
            end
        end
        while #order > limits.entries do
            byID[table.remove(order, 1)] = nil
        end
        tooltips.order, tooltips.byID = order, byID
        for key in pairs(tooltips) do if key ~= "order" and key ~= "byID" then tooltips[key] = nil end end
    else
        state.objectTooltips = nil
    end
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
    -- NamePolicy's names-only mark (no default): { cvar, wrote, original }, each short text, else dropped.
    local mark = settings.namesOnlyMark
    if mark ~= nil and (type(mark) ~= "table" or type(mark.cvar) ~= "string" or type(mark.wrote) ~= "string"
        or type(mark.original) ~= "string" or #mark.cvar > 64 or #mark.wrote > 64 or #mark.original > 64) then
        settings.namesOnlyMark = nil
    end
    for key, value in pairs(characterDefaults) do
        if type(settings[key]) ~= type(value) then settings[key] = value end
    end
    if not validTankRoles[settings.tankRole] then settings.tankRole = characterDefaults.tankRole end
    return settings
end

PS.ProfileSchema = {
    defaults = defaults,
    MARK = MARK,
    profileRanges = profileRanges,
    optionalProfileRanges = optionalProfileRanges,
    castOptions = castOptions,
    -- The cast bar's own colour.
    CAST_COLOUR = { r = 0.95, g = 0.68, b = 0.16 },
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
    -- The box's height (style boxHeight): text (nil, the text's line and Padding above and below, every profile
    -- before it) or parent: at least as tall as the part the text is pinned to, drawn border included (Blizzard's
    -- level box beside its bar), centred on the text; Padding then sets only its sides (StyleBox.Place).
    STYLE_BOX_HEIGHTS = { text = true, parent = true },
    STYLE_PIP_ANCHORS = STYLE_PIP_ANCHORS,
    STYLE_PIP_SHOW_ROWS = STYLE_PIP_SHOW_ROWS,
    STYLE_DEFAULTS = STYLE_DEFAULTS,
    BACKDROP = PartChoices.backdrop,
    PartChoice = PartChoices.New,
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
    CLICK = VISIBILITY.CLICK,
    INTERACT = VISIBILITY.INTERACT,
    HOVER = VISIBILITY.HOVER,
    FRIENDLY = FRIENDLY,
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
    PlatesRead = PlatesRead,
    ENEMY_PLATES = ENEMY_PLATES,
}

-- The plate types with an Action icon (Nameplates/ActionIcon.lua), and whether its pass runs: while one of their
-- layouts shows the part, or a custom part or rule there reads what it reads (object.kind, object.unable,
-- interact.inrange). (Fields, not main chunk locals: this chunk is at Lua 5.1's 200.)
PS.ProfileSchema.ACTION_PLATES = { object = true, friendlyNPC = true }
function PS.ProfileSchema.ActionIconNeeded(settings)
    local Schema = PS.ProfileSchema
    local shown = false
    Schema.EachPlateLayout(settings, Schema.ACTION_PLATES, function(layout, _, _, plateType)
        if plateType == "object" and settings.objectPlates == "blizzard" then return end
        shown = shown or (type(layout.actionIcon) == "table" and not Schema.TurnedOff(layout.actionIcon))
    end)
    return shown or Schema.PlatesRead(settings, Schema.ACTION_PLATES, { "object.kind", "object.unable", "interact." })
        or Schema.ObjectKindsNeeded(settings)
end

-- Extras on Blizzard's plates (Nameplates/Extras.lua): what PlateSmith adds while Who draws the plates is Blizzard, with
-- PlateSmith extras (mode overlay). extrasQuest: quest markers (and their progress); extrasThreat: text, edge (a thin
-- edge round Blizzard's health bar in the threat colours), both or off; extrasTarget: the soft glow behind your
-- target; extrasLoose: the Loose mark. ReadsThreat: whether they need the threat service's records.
PS.ProfileSchema.EXTRAS = { THREAT = { text = true, edge = true, both = true, off = true },
    THREAT_CHOICES = { "both", "text", "edge", "off" } }
function PS.ProfileSchema.EXTRAS.ReadsThreat(settings)
    if type(settings) ~= "table" or settings.mode ~= "overlay" then return false end
    return (settings.extrasThreat ~= nil and settings.extrasThreat ~= "off") or settings.extrasLoose == true
end
-- Whether the threat edge (edge or both) or the threat text (text or both) is on.
function PS.ProfileSchema.EXTRAS.Edge(settings)
    return type(settings) == "table" and (settings.extrasThreat == "edge" or settings.extrasThreat == "both")
end
function PS.ProfileSchema.EXTRAS.Text(settings)
    return type(settings) == "table" and (settings.extrasThreat == "text" or settings.extrasThreat == "both")
end

-- Whether every Objects plate's kind is read (its Action icon pass), whatever its layout shows: while objects are
-- PlateSmith's and an object type has a layer (Designs.TYPES), Fade objects you can't use is on, or the Status text
-- is wanted (StatusNeeded).
function PS.ProfileSchema.ObjectKindsNeeded(settings)
    if type(settings) ~= "table" or settings.objectPlates == "blizzard" then return false end
    local profile = type(settings.plateProfiles) == "table" and settings.plateProfiles.object
    if type(profile) == "table" and type(profile.types) == "table" and next(profile.types) ~= nil then return true end
    return settings.objectFadeUnable == true or PS.ProfileSchema.StatusNeeded(settings)
end

-- Whether Objects plates get hover frames (Nameplates/ObjectHover.lua): while PlateSmith draws objects and the hover
-- cursor or tooltip is on.
function PS.ProfileSchema.HoverNeeded(settings)
    if type(settings) ~= "table" or settings.objectPlates == "blizzard" then return false end
    return settings.objectHoverCursor == true or settings.objectHoverTooltip == true
end

-- Whether the Status text's reads run (Nameplates/ObjectStatus.lua: the tooltip capture, your skills and Cultivation):
-- while an Objects layout (a type's too) shows the part, a custom part or rule there reads object.skill,
-- object.cangather or object.cancultivate, or Fade objects you can't use is on (which asks the last two).
function PS.ProfileSchema.StatusNeeded(settings)
    local Schema = PS.ProfileSchema
    if type(settings) ~= "table" or settings.objectPlates == "blizzard" then return false end
    if settings.objectFadeUnable == true then return true end
    local shown, objects = false, { object = true }
    Schema.EachPlateLayout(settings, objects, function(layout)
        shown = shown or (type(layout.statusText) == "table" and not Schema.TurnedOff(layout.statusText))
    end)
    return shown or Schema.PlatesRead(settings, objects, { "object.skill", "object.cangather", "object.cancultivate" })
end

-- An aura row's countdown Font size in points, before the profile's text size: its own (timeFontSize), or Auto,
-- the row's share of the icon (timeSize, 45% unless an early 1.1.1 build set it), at least 8. (A field, not a main
-- chunk local: this chunk is at Lua 5.1's 200.)
function PS.ProfileSchema.AuraCountdownSize(aura)
    local points = tonumber(aura.timeFontSize)
    if points then return points end
    return math.max(8, math.floor((tonumber(aura.size) or 18) * ((tonumber(aura.timeSize) or 45) / 100)))
end
