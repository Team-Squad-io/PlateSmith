local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local L = PS.L

-- Built-in profile presets and the rule presets they (and Studio's Rules > Presets) use. A preset
-- is built from the current defaults with overrides, then shared as a Blueprint document, so it is
-- checked by the normal import and keeps working as the defaults change. Each has its own look
-- (fonts, bar textures, borders, text boxes, rules) from media that ships with the game.
local ProfilePresets = {}
PS.ProfilePresets = ProfilePresets

-- Rule presets: each appends its rules to a part, in order. Rules are read top to bottom and the
-- last one that holds wins, so the more specific rules come later. kind "colour" offers a preset
-- only on parts rules can colour (bars and text). Fact names and colours are set here and nowhere else.
-- retired: no longer offered in Rules › Presets, because a built-in option does the job (STANDARDS 2a:
-- one route per job, rules on top). Kept by id: rules made from them are ordinary saved rules and keep
-- working, and Settings › Fading writes the fades through them.
ProfilePresets.RULES = {
    { id = "healthBlend", name = L["Health colours (blend)"], kind = "colour", rules = {
        { when = "", set = "blend", stops = { { at = 0, colour = { r = 0.9, g = 0.15, b = 0.1 } },
            { at = 50, colour = { r = 0.95, g = 0.8, b = 0.1 } }, { at = 100, colour = { r = 0.2, g = 0.85, b = 0.25 } } } },
    } },
    { id = "lowHealth", name = L["Low health red"], kind = "colour", rules = {
        { when = "health.percent < 35", set = "colour", colour = { r = 0.9, g = 0.15, b = 0.1 } },
    } },
    { id = "execute", name = L["Execute range"], kind = "colour", rules = {
        { when = "health.percent < 20", set = "colour", colour = { r = 1, g = 0.4, b = 0 } },
    } },
    -- Retired for the health bar's Grey when tagged by others (greyWhenTagged), on for new profiles.
    { id = "tagged", name = L["Grey when tagged"], kind = "colour", retired = true, rules = {
        { when = "tagged", set = "colour", colour = { r = 0.5, g = 0.5, b = 0.5 } },
    } },
    -- Retired for Settings › Modules › Threat › Threat colours (Colour by threat).
    { id = "threatTank", name = L["Threat colours (tank)"], kind = "colour", retired = true, rules = {
        { when = "role.tank and threat.holding", set = "colour", colour = { r = 0.5, g = 0.5, b = 1 } },
        { when = "role.tank and threat.losing", set = "colour", colour = { r = 1, g = 1, b = 0 } },
        { when = "role.tank and threat.offtank", set = "colour", colour = { r = 0.73, g = 0.92, b = 1 } },
        { when = "role.tank and threat.other and not threat.offtank", set = "colour", colour = { r = 1, g = 0, b = 0 } },
    } },
    { id = "threatDps", name = L["Threat colours (DPS/healer)"], kind = "colour", retired = true, rules = {
        { when = "not role.tank and threat.pulling", set = "colour", colour = { r = 1, g = 0.8, b = 0 } },
        { when = "not role.tank and threat.holding", set = "colour", colour = { r = 1, g = 0.11, b = 0 } },
    } },
    -- Retired for the cast bar's Colour by interrupt, which also shows it through the client's colour
    -- sink where the game withholds the interrupt's readiness (then neither of the first two rules holds).
    { id = "castInterrupt", name = L["Cast colours by interrupt"], kind = "colour", retired = true, rules = {
        { when = "casting and interruptible and interruptReady", set = "colour", colour = { r = 0.25, g = 0.85, b = 0.35 } },
        { when = "casting and interruptible and not interruptReady", set = "colour", colour = { r = 0.9, g = 0.3, b = 0.2 } },
        { when = "casting and not interruptible", set = "colour", colour = { r = 0.55, g = 0.55, b = 0.55 } },
    } },
    -- Fades, retired for Settings › Behaviour & display › Fading, which adds these to every shown part of
    -- the enemy plates (Settings' SetFadeEverywhere finds them by their condition).
    { id = "fadeNonTarget", name = L["Fade non-targets"], kind = "alpha", retired = true, rules = {
        { when = "hastarget and not targeted", set = "alpha", alpha = 0.5 },
    } },
    { id = "fadeOutOfRange", name = L["Fade out of range"], kind = "alpha", retired = true, rules = {
        { when = "not inrange", set = "alpha", alpha = 0.5 },
    } },
}

function ProfilePresets.Rule(id)
    for _, preset in ipairs(ProfilePresets.RULES) do
        if preset.id == id then return preset end
    end
end

-- Style presets: built-in looks for one part of a kind (Studio's Style > Presets lists them before
-- the player's saved ones). Applying one replaces the part's style.
ProfilePresets.STYLES = {
    { id = "levelBox", name = L["Level box"], kind = "text", style = { box = true,
        boxColour = { r = 0, g = 0, b = 0, a = 0.7 }, boxBorder = { r = 0.78, g = 0.62, b = 0.3, a = 1 }, padding = 3 } },
    { id = "boldOutline", name = L["Bold outline"], kind = "text", style = { outline = "thick", shadow = true } },
    { id = "framedBar", name = L["Framed bar"], kind = "bar", style = { border = 2, borderColour = { r = 0, g = 0, b = 0, a = 1 },
        background = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 } } },
}

-- Colours the presets' own styles and rules use.
local BLACK, DARK = { r = 0, g = 0, b = 0, a = 1 }, { r = 0.06, g = 0.06, b = 0.07, a = 0.92 }
local WHITE = { r = 1, g = 1, b = 1 }
-- The looks' Enemies plates (1.3.0): each is its first-run card's sketch (Studio/FirstRun.lua), made real
-- (docs/reviews/LOOKS_V2.md). The name in a warm white and the level in gold, each as a rule set first (a
-- player's later rules still win); the bars' background where a look has none of its own.
local NAME_COLOUR, LEVEL_COLOUR = { r = 1, g = 0.92, b = 0.88 }, { r = 1, g = 0.82, b = 0 }
local BAR_BACKGROUND = { r = 0.05, g = 0.05, b = 0.05, a = 0.75 }
-- Each look's combo points (the Enemies' combo style, replacing the default's gold coins). A row
-- narrower than the bar stays where the defaults put it, in the Bars stack under the cast bar (it moves
-- up under the health bar while nothing is cast); bar segments as wide as the bar sit straight under
-- the health bar, over the cast bar (SegmentsUnderBar). In the stack the row has room at any shape and
-- size, where above the bar or on its edge a larger shape met the name or the cast bar. Blizzard's
-- gems fall back to round coins where the client lacks their art. Small, without a glow: they show
-- only on your target, under the plate's resting outline.
local COMBO = {
    -- The defaults' gold coins, smaller and without their glow.
    platesmith = { pipShape = "round", pipWidth = 7, pipSpacing = 3, pipFill = { r = 1, g = 0.78, b = 0.15, a = 1 } },
    classic = { pipShape = "blizzard", pipWidth = 10, pipSpacing = 2 },
    -- Thin segments fitted to the bar's width (24.4 px each at 130; Width 24 if Fit is turned off), so a
    -- wider or narrower bar keeps them spanning it.
    sleek = { pipShape = "segments", pipWidth = 24, pipHeight = 3, pipSpacing = 2, pipFit = true,
        pipFill = { r = 1, g = 0.82, b = 0.25, a = 1 } },
    bold = { pipShape = "round", pipWidth = 9, pipSpacing = 4, pipFill = { r = 1, g = 0.72, b = 0.1, a = 1 } },
    tank = { pipShape = "square", pipWidth = 7, pipSpacing = 3, pipFill = { r = 1, g = 0.85, b = 0.3, a = 1 } },
    healer = { pipShape = "diamond", pipWidth = 7, pipSpacing = 2 },
    minimal = { pipShape = "square", pipWidth = 5, pipSpacing = 2 },
    -- Segments fitted to the bar's width (18.4 px each at 100).
    dungeon = { pipShape = "segments", pipWidth = 16, pipHeight = 3, pipSpacing = 2, pipFit = true },
    blizzard = { pipShape = "blizzard", pipWidth = 13, pipSpacing = 3 },
}
ProfilePresets.COMBO = COMBO

-- Compact's cast bar: the cast colour while it can be interrupted, grey while it cannot.
local CAST_RULES = {
    { when = "casting and interruptible", set = "colour", colour = S.CAST_COLOUR },
    { when = "casting and not interruptible", set = "colour", colour = { r = 0.55, g = 0.55, b = 0.55 } },
}

-- Appends the named rule presets to profile.rules[part], in order.
local function AddRules(profile, part, ...)
    profile.rules = profile.rules or {}
    local list = profile.rules[part] or {}
    for index = 1, select("#", ...) do
        local id = select(index, ...)
        for _, preset in ipairs(ProfilePresets.RULES) do
            if preset.id == id then
                for _, rule in ipairs(preset.rules) do list[#list + 1] = Table.DeepCopy(rule) end
            end
        end
    end
    profile.rules[part] = list
end

-- Appends rules of the preset's own to profile.rules[part].
local function AddOwnRules(profile, part, rules)
    profile.rules = profile.rules or {}
    local list = profile.rules[part] or {}
    for _, rule in ipairs(rules) do list[#list + 1] = Table.DeepCopy(rule) end
    profile.rules[part] = list
end

-- Sets fields of one part's style (Schema NormalizeStyles).
local function Style(profile, key, fields)
    profile.styles = profile.styles or {}
    local style = profile.styles[key] or {}
    for field, value in pairs(fields) do style[field] = Table.DeepCopy(value) end
    profile.styles[key] = style
end

local function Show(layout, shown, ...)
    for index = 1, select("#", ...) do
        local position = layout[select(index, ...)]
        if position then position.visible = shown end
    end
end

-- Pins key to parent's edge with gap px between them (Dynamic placement).
local function Pin(layout, key, parent, edge, gap)
    local position, offset = layout[key], S.ATTACH_EDGES[edge]
    position.parent, position.attach, position.free, position.order = parent, edge, nil, nil
    position.x, position.y = offset[1] * gap, offset[2] * gap
end

-- Combo points as bar segments, as wide as the bar: straight under the health bar, over the cast bar.
local function SegmentsUnderBar(layout) S.ComboInStack(layout, "health") end

-- Places key on parent at (x, y) from its centre (Free placement), e.g. text inside a bar.
local function Place(layout, key, parent, x, y)
    local position = layout[key]
    position.parent, position.attach, position.free, position.order = parent, nil, true, nil
    position.x, position.y = x, y
end

-- A text custom part on the health bar, at x px from its centre.
local function AddValue(profile, index, source, x, fontSize)
    local key = "value" .. index
    local slot = profile.valueSlots[key]
    slot.source, slot.anchor, slot.fontSize = source, "health", fontSize or slot.fontSize
    profile.layout[key].x, profile.layout[key].y, profile.layout[key].visible = x, 0, true
    return key, slot
end

-- Deletes a part the preset never uses, as Studio's delete does: off the tree and the plate
-- until + Add puts it back. A part pinned to it stays pinned, now to its parent; the loot bag
-- goes with the quest mark. A part with other parts placed on it (a bar and its custom parts)
-- is only hidden, since custom parts cannot be deleted.
local function Remove(layout, key)
    local position = layout[key]
    if not position or position.removed or S.IsGroupKey(key) then return end
    for childKey, child in pairs(layout) do
        if child.parent == key and not child.attach and childKey ~= "questLoot" then
            position.visible = false
            return
        end
    end
    for childKey, child in pairs(layout) do
        if child.parent == key then
            if childKey == "questLoot" then child.removed, child.visible = true, false
            else child.parent = position.parent end
        end
    end
    position.removed, position.visible = true, false
end

-- Deletes any group with nothing in it.
local function DropEmptyGroups(layout)
    for key in pairs(layout) do
        if S.IsGroupKey(key) then
            local used = false
            for _, position in pairs(layout) do used = used or (position.parent == key and not position.removed) end
            if not used then
                layout[key] = nil
                for _, position in pairs(layout) do if position.parent == key then position.parent = nil end end
            end
        end
    end
end

-- Deletes every part the layout leaves hidden, except keep (parts players turn on with the eye),
-- then any group left with nothing in it.
local function Prune(layout, keep)
    local kept = {}
    for _, key in ipairs(keep or {}) do kept[key] = true end
    local hidden = {}
    for key, position in pairs(layout) do
        if position.visible == false and not position.removed and not kept[key] and key ~= "questLoot"
            and not S.IsGroupKey(key) and not key:match("^value%d+$") then
            hidden[#hidden + 1] = key
        end
    end
    table.sort(hidden)
    for _, key in ipairs(hidden) do Remove(layout, key) end
    DropEmptyGroups(layout)
end

local function Profiles(settings) return settings.plateProfiles end
local function FullLayouts(settings)
    local profiles = Profiles(settings)
    return { profiles.enemy.layout, profiles.friendlyPlayer.layout, profiles.friendlyNPC.layout }
end
local function AllLayouts(settings)
    local layouts = FullLayouts(settings)
    for _, key in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
        layouts[#layouts + 1] = Profiles(settings)[key].namesLayout
        layouts[#layouts + 1] = Profiles(settings)[key].dungeonNamesLayout
    end
    return layouts
end
-- The plate types a look's builder shapes; Objects take the look's own name box instead (OBJECTS).
local LOOK_TYPES = { "enemy", "friendlyPlayer", "friendlyNPC" }
local function EachProfile(settings, callback)
    for _, key in ipairs(LOOK_TYPES) do callback(Profiles(settings)[key], key) end
end
-- The Enemies' TAGGED is always kept, off (every look greys a tagged mob's bar instead: greyWhenTagged), so its
-- eye can bring the word back.
local function PruneAll(settings, keep)
    -- TAGGED and the Loose mark stay on the tree, hidden, for their eyes to bring back.
    local enemy, kept = Profiles(settings).enemy.layout, { "tagged", "looseMark" }
    for _, key in ipairs(keep or {}) do kept[#kept + 1] = key end
    for _, layout in ipairs(AllLayouts(settings)) do Prune(layout, layout == enemy and kept or keep) end
end

-- A flat bar: a solid fill over a dark background, with a border of size px (0: none).
local function FlatBar(profile, key, size)
    Style(profile, key, { texture = "flat", background = DARK, border = size > 0 and size or nil,
        borderColour = size > 0 and BLACK or nil })
end

-- part always in colour: a rule set first, in place of the look's own unconditional colour rule, so a
-- player's later rules still win.
local function ColourFirst(profile, part, colour)
    profile.rules = profile.rules or {}
    local list = { { when = "", set = "colour", colour = Table.DeepCopy(colour) } }
    for _, rule in ipairs(profile.rules[part] or {}) do
        if not (rule.when == "" and rule.set == "colour") then list[#list + 1] = rule end
    end
    profile.rules[part] = list
end

-- The level in gold Friz Quadrata at size pt (nil: Auto), in the name's outline, without a shadow; the gold as a
-- rule set first.
local function GoldLevel(profile, size)
    local styles = profile.styles or {}
    local outline = styles.name and styles.name.outline or "outline"
    Style(profile, "level", { font = "friz", fontSize = size, outline = outline })
    profile.styles.level.shadow = nil
    ColourFirst(profile, "level", LEVEL_COLOUR)
end

-- The Enemies' resting plate as its first-run card draws it: the name at nameSize pt in the warm white
-- (under the name's 9 pt floor, its style's Font size takes it), in its own face and outline; the level
-- (levelSize, nil while the look shows none) in gold Friz Quadrata in the name's outline; the bars on the
-- look's background (BAR_BACKGROUND where it has none); a slim cast bar in the health bar's texture
-- unless it has its own, with no border, the spell icon inside its left end (a look without one keeps
-- none), gap px (3 when nil) under the health bar: more where a mark beside a slim bar (taller than it)
-- must clear combo points of any size passing under it (layout_smoke). Where the name and level sit is each look's.
local function Sketch(enemy, nameSize, levelSize, gap)
    enemy.nameFontSize = math.max(9, nameSize)
    if nameSize < 9 then Style(enemy, "name", { fontSize = nameSize }) end
    ColourFirst(enemy, "name", NAME_COLOUR)
    local styles = enemy.styles
    if levelSize then GoldLevel(enemy, levelSize) end
    local background = styles.health and styles.health.background or BAR_BACKGROUND
    Style(enemy, "health", { background = background })
    Style(enemy, "cast", { texture = styles.cast and styles.cast.texture or enemy.healthTexture, background = background })
    styles.cast.border, styles.cast.borderColour = nil, nil
    if enemy.castIcon ~= "off" then enemy.castIcon = "inside" end
    enemy.layout[enemy.layout.health.parent].gap = gap or 3
end

-- The extras the sketch leaves out, quieter (each shows only on a unit that has it): the elite mark at 80%
-- and the quest mark at 85% (the raid mark keeps its size: it is called on), the aura rows at debuffs and
-- buffs px, TAGGED at 8 pt while its eye shows it.
local function Quiet(enemy, debuffs, buffs)
    local layout, rows = enemy.layout, enemy.auraLayouts
    layout.classification.scale, layout.quest.scale = 0.8, 0.85
    rows.debuffs.size, rows.buffs.size = debuffs, buffs
    Style(enemy, "tagged", { fontSize = 8 })
end

-- The Loose mark (LooseMark.lua) keeps its place right of the enemy name in every look: a part the look pins there
-- (TAGGED, say) goes after it, and takes its place while the mark is off or the mob is not loose (Schema's PinTarget).
local function LooseAfterName(layout)
    local mark = layout and layout.looseMark
    if not (mark and mark.parent and mark.attach) then return end
    for key, position in pairs(layout) do
        if key ~= "looseMark" and type(position) == "table" and position.parent == mark.parent
            and position.attach == mark.attach then
            position.parent = "looseMark"
        end
    end
end

-- Aura countdowns that never meet their neighbours' (a 12 px row's Auto 8 pt "2m15m" ran together): the widest
-- label the client writes ("59m", minutes from 60 s) is COUNTDOWN.em px a point in Friz Quadrata (the plate
-- font's), plus its outline, so one icon's step (its size and gap) must be that wide. A row's gap widens to fit,
-- up to Schema's most; past that its countdown's Font size comes down to fit (the countdown scales with the icon).
-- Only the looks: a player's own rows keep their sizes.
local COUNTDOWN = { em = 2.25, outline = 2 }
local function FitCountdowns(settings)
    local most, smallest = S.auraLayoutRanges.spacing[2], S.STYLE_FONT_SIZE[1]
    EachProfile(settings, function(profile)
        for _, row in pairs(profile.auraLayouts) do
            local wide = math.ceil(COUNTDOWN.em * S.AuraCountdownSize(row) + COUNTDOWN.outline)
            if row.showDuration ~= false and wide > row.size + row.spacing then
                row.spacing = math.max(row.spacing, math.min(most, wide - row.size))
                if wide > row.size + row.spacing then
                    row.timeFontSize = math.max(smallest, math.floor((row.size + row.spacing - COUNTDOWN.outline) / COUNTDOWN.em))
                end
            end
        end
    end)
end
ProfilePresets.COUNTDOWN = COUNTDOWN

-- Whether any of the profile's layouts shows key.
local function Shown(profile, key)
    for _, field in ipairs({ "layout", "namesLayout", "dungeonNamesLayout" }) do
        local position = profile[field] and profile[field][key]
        if position and position.visible ~= false and not position.removed then return true end
    end
    return false
end

-- The friendly plates after the Enemies' (1.3.0): the name at the Enemies' size (nameSize) on a plate type the
-- look shows as full plates, 1 pt larger where it shows names only (the name is the whole plate there; one size
-- serves both, as a plate type has one name size); the level as the Enemies' (GoldLevel at levelSize, nil: the
-- look shows no level); the guild line at least GUILD_MIN pt (its Auto size is the name's less 2).
local GUILD_MIN = 9
local function Friendly(settings, nameSize, levelSize)
    for _, key in ipairs(S.FRIENDLY.TYPES) do
        local profile = Profiles(settings)[key]
        profile.nameFontSize = math.max(9, nameSize + (S.FRIENDLY.Mode(settings, key) == "names" and 1 or 0))
        if levelSize and Shown(profile, "level") then GoldLevel(profile, levelSize) end
        if Shown(profile, "guild") and S.PartTextSize("guild", profile.nameFontSize) < GUILD_MIN then
            Style(profile, "guild", { fontSize = GUILD_MIN })
        end
    end
end

-- Each builder changes a complete default settings table in place.
local BUILDERS = {}

-- PlateSmith: the defaults' plate, calmer. The name centred over the bar with the gold level before it,
-- the cast bar slim under the bar with its icon inside, the threat text small under the bars.
function BUILDERS.platesmith(settings)
    local enemy = Profiles(settings).enemy
    local layout = enemy.layout
    Pin(layout, "name", "health", "top", 5)
    Pin(layout, "level", "name", "left", 3)
    -- 4 px: the raid mark beside the 10 px bar (18 px) clears combo points of any size.
    Sketch(enemy, 12, 10, 4)
    Quiet(enemy, 16, 12)
    Style(enemy, "threat", { fontSize = 10 })
    Friendly(settings, 12, 10)
    -- Only the Text group the name left: the PlateSmith look deletes no parts.
    DropEmptyGroups(layout)
end

-- Classic: the game's own plates of old. Friz Quadrata, the game's bar texture framed by a thin
-- dark border, a name centred above, level and the elite dragon right of the bar, the
-- cast bar with icon and spell name, the player's debuffs above the name.
function BUILDERS.classic(settings)
    for _, layout in ipairs(FullLayouts(settings)) do
        Pin(layout, "level", "health", "right", 3)
        Pin(layout, "classification", "level", "right", 2)
        Pin(layout, "quest", "name", "left", 3)
        Pin(layout, "pvpIcon", "name", "left", 3)
        Pin(layout, "tagged", "name", "right", 4)
        Show(layout, false, "buffs", "threat")
    end
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = 120, 10, 10, 14
        profile.castIcon, profile.castTime, profile.castName = "left", false, true
        for _, key in ipairs({ "name", "level", "guild", "tagged", "classification" }) do
            Style(profile, key, { font = "friz", outline = "none", shadow = true })
        end
        for _, key in ipairs({ "health", "cast" }) do
            Style(profile, key, { texture = "blizzard", border = 1, borderColour = { r = 0.08, g = 0.08, b = 0.08, a = 1 } })
        end
    end)
    local enemy = Profiles(settings).enemy
    -- 9 px: a long name running past the bar's end clears the classic dragon's wing (MARKS: 13 px over the bar's line
    -- round the 10 pt level).
    Pin(enemy.layout, "name", "health", "top", 9)
    Pin(enemy.layout, "level", "health", "right", 4)
    -- 4 px: the raid mark beside the 10 px bar (18 px) clears combo points of any size.
    Sketch(enemy, 12, 10, 4)
    Quiet(enemy, 16, 12)
    Friendly(settings, 12, 10)
    PruneAll(settings, { "buffs" })
end

-- Sleek: flat and modern. A wide flat bar with a 1 px black border, a small Arial Narrow name
-- after the level above the bar's left end, health % inside its right end, the raid mark right
-- of the bar, a flat cast bar with icon and timer, square debuffs with small buffs over them.
function BUILDERS.sleek(settings)
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = 130, 12, 10, 10
        profile.castIcon, profile.castTime, profile.castName = "left", true, true
        profile.auraLayouts.debuffs.size, profile.auraLayouts.debuffs.spacing = 20, 1
        profile.auraLayouts.buffs.size, profile.auraLayouts.buffs.count = 14, 3
        local layout = profile.layout
        -- 15 px up: a mark after a long name (relationship icon, TAGGED) clears the raid mark.
        Place(layout, "level", "health", -profile.width / 2 + 4, 15)
        Pin(layout, "name", "level", "right", 3)
        Pin(layout, "classification", "level", "left", 3)
        Pin(layout, "quest", "classification", "left", 2)
        Pin(layout, "tagged", "name", "right", 4)
        Pin(layout, "raidIcon", "health", "right", 4)
        SegmentsUnderBar(layout)
        local key = AddValue(profile, 1, "healthPercent", profile.width / 2 - 14, 10)
        for _, text in ipairs({ "name", "level", "guild", "threat", "tagged", "classification", key }) do
            Style(profile, text, { font = "arialn", outline = "none", shadow = true })
        end
        Style(profile, key, { outline = "outline", shadow = false })
        FlatBar(profile, "health", 1)
        FlatBar(profile, "cast", 1)
    end)
    -- The Enemies: the level on the bar's top left end, the name 2 px after it; the health % in Friz
    -- Quadrata inside the bar's right end, 3 px in (pinned left of the bar, a bar's width over).
    local enemy = Profiles(settings).enemy
    local layout = enemy.layout
    -- 3 px up: a long name running past the bar's end clears the raid mark right of it.
    Pin(layout, "level", "health", "top", 3)
    layout.level.x = -58
    Pin(layout, "name", "level", "right", 2)
    Pin(layout, "value1", "health", "left", -(enemy.width - 3))
    enemy.valueSlots.value1.fontSize = 9
    Style(enemy, "value1", { font = "friz" })
    enemy.styles.value1.shadow = nil
    Sketch(enemy, 10, 9)
    Quiet(enemy, 16, 12)
    Friendly(settings, 10, 9)
    -- The guild line 10 pt: Arial Narrow reads smaller than its size.
    Style(Profiles(settings).friendlyPlayer, "guild", { fontSize = 10 })
    PruneAll(settings)
end

-- Bold: chunky and threat first. A tall bar with a heavy border that takes the threat colours for
-- your role, Morpheus names with a thick outline, the threat % under the bars (on friendly plates
-- boxed right of the bar, with a large elite mark left of it and a large raid mark over the name);
-- debuffs only.
function BUILDERS.bold(settings)
    local enemy = Profiles(settings).enemy
    for _, layout in ipairs(FullLayouts(settings)) do
        if layout ~= enemy.layout then
            layout.name.y = 22
            Pin(layout, "threat", "health", "right", 5)
            Pin(layout, "classification", "health", "left", 4)
            layout.classification.scale = 1.3
            Pin(layout, "raidIcon", "name", "top", 2)
            layout.raidIcon.scale = 1.5
            layout.debuffs.y = 70
        end
        Pin(layout, "tagged", "name", "right", 4)
        Show(layout, false, "buffs")
    end
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.nameFontSize = 120, 14, 14
        profile.auraLayouts.debuffs.size = 16
        Style(profile, "name", { font = "morpheus", outline = "thick" })
        for _, key in ipairs({ "level", "guild", "tagged", "classification" }) do
            Style(profile, key, { font = "friz", outline = "thick" })
        end
        if profile == enemy then
            Style(profile, "threat", { font = "friz", outline = "thick", fontSize = 10 })
        else
            Style(profile, "threat", { font = "friz", outline = "thick", box = true, padding = 2,
                boxColour = { r = 0, g = 0, b = 0, a = 0.75 }, boxBorder = { r = 0.9, g = 0.7, b = 0.2, a = 1 } })
        end
        for _, key in ipairs({ "health", "cast" }) do Style(profile, key, { texture = "blizzard", border = 2, borderColour = BLACK }) end
    end)
    -- Threat colours (the setting, not rules, so its swatches are what the bar shows): the tank's are the
    -- defaults; a DPS or healer's are this look's own, and Safe keeps the bar's colour.
    settings.colourByThreat, settings.threatColourSafeKeep = true, true
    settings.threatColours.pulling = { r = 1, g = 0.8, b = 0 }
    settings.threatColours.aggro = { r = 1, g = 0.11, b = 0 }
    -- The name 6 px over the bar, the cast bar 5 px under it and the raid mark 6 px left of it: each (and the quest
    -- mark on the name's line) clears the Bar frame mark's rings round the bar's 2 px border (a boss's 3 px; MARKS).
    Pin(enemy.layout, "name", "health", "top", 6)
    Pin(enemy.layout, "level", "name", "left", 3)
    Pin(enemy.layout, "raidIcon", "health", "left", 6)
    Sketch(enemy, 12, 10, 5)
    Quiet(enemy, 16, 12)
    Friendly(settings, 12, 10)
    PruneAll(settings)
end

-- Tank: the tank threat colours on the bar, the threat lead in gold right of it, who the mob is
-- targeting under the bars, the elite and raid marks left of the bar, compact auras.
function BUILDERS.tank(settings)
    local enemy = Profiles(settings).enemy
    local layout = enemy.layout
    Pin(layout, "classification", "health", "left", 4)
    Pin(layout, "raidIcon", "classification", "left", 3)
    Pin(layout, "tagged", "name", "right", 4)
    Show(layout, false, "threat")
    Show(layout, true, "targetName", "looseMark")
    -- Threat colours: the setting's tank colours are this look's (no rules, so its swatches apply).
    settings.colourByThreat = true
    local key, slot = AddValue(enemy, 1, "leadPercent", 0, 9)
    slot.colour = { r = 1, g = 0.85, b = 0.3 }
    Pin(layout, key, "health", "right", 4)
    Style(enemy, key, { font = "friz", outline = "outline" })
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight = 120, 12
        for _, row in pairs(profile.auraLayouts) do row.size, row.spacing, row.count, row.columns = 14, 1, 5, 5 end
        for _, bar in ipairs({ "health", "cast" }) do
            Style(profile, bar, { texture = "blizzard", border = 1, borderColour = { r = 0.25, g = 0.05, b = 0.05, a = 1 } })
        end
        Style(profile, "targetName", { font = "friz", outline = "outline" })
    end)
    Pin(layout, "name", "health", "top", 5)
    Pin(layout, "level", "name", "left", 3)
    Style(enemy, "targetName", { fontSize = 9 })
    Sketch(enemy, 12, 10)
    Quiet(enemy, 14, 12)
    Friendly(settings, 12, 10)
    PruneAll(settings)
end

-- Healer: friendly plates are full plates with thick bars that blend from green through yellow
-- to red, health % inside; enemy plates are slim, the name and bar only, dimmed beside your target.
function BUILDERS.healer(settings)
    settings.friendly = "full"
    for _, profileKey in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
        local profile = Profiles(settings)[profileKey]
        profile.width, profile.healthHeight = profileKey == "friendlyPlayer" and 130 or 110, 14
        AddRules(profile, "health", "healthBlend")
        local key, slot = AddValue(profile, 1, "template", 0, 11)
        slot.template = "{health.percent}%"
        Style(profile, key, { font = "friz", outline = "outline" })
        Style(profile, "health", { texture = "blizzard", border = 1, borderColour = BLACK })
    end
    local enemy = Profiles(settings).enemy
    enemy.width, enemy.healthHeight = 100, 6
    Show(enemy.layout, false, "level", "threat", "buffs", "debuffs")
    -- 5 px: a long name clears the elite mark beside the slim bar (taller than it).
    Pin(enemy.layout, "name", "health", "top", 5)
    -- The name sits low over the slim bar, so the quest mark goes on the bar's line (left of the bar, the raid
    -- mark left of it), where beside a long name it met the raid mark.
    Pin(enemy.layout, "quest", "health", "left", 3)
    Pin(enemy.layout, "raidIcon", "quest", "left", 3)
    FlatBar(enemy, "health", 0)
    FlatBar(enemy, "cast", 0)
    -- Drawn in full with no target (the plate as its card draws it); dimmed beside your target.
    AddOwnRules(enemy, "name", { { when = "hastarget and not targeted", set = "alpha", alpha = 0.5 } })
    AddOwnRules(enemy, "health", { { when = "hastarget and not targeted", set = "alpha", alpha = 0.5 } })
    -- 5 px under the slim bar: the marks beside it (taller than it) clear combo points of any size.
    Sketch(enemy, 10, nil, 5)
    Quiet(enemy, 16, 12)
    -- The Enemies show no level: the friendly one is gold Friz Quadrata at 9 pt (the guild line's floor).
    Friendly(settings, 10, 9)
    PruneAll(settings)
end

-- Minimal: friendly plates show names only; enemies a thin flat bar under a plain name, with the
-- raid mark after it and the elite mark before it, nothing else (no level, other marks, borders or auras).
function BUILDERS.minimal(settings)
    settings.friendly = "names"
    for _, layout in ipairs(AllLayouts(settings)) do
        Show(layout, false, "level", "quest", "questLoot", "pvpIcon", "relationshipIcon", "classification", "tagged",
            "threat", "guild", "power", "buffs", "debuffs", "targetName")
    end
    local enemy = Profiles(settings).enemy
    for _, layout in ipairs(FullLayouts(settings)) do
        -- 3 px (the Enemies' 2 px): the raid mark beside the name (taller than it) clears the bar.
        Pin(layout, "name", "health", "top", layout == enemy.layout and 2 or 3)
        -- The Enemies' after the name: their elite mark sits before it (MARKS).
        Pin(layout, "raidIcon", "name", layout == enemy.layout and "right" or "left", 3)
    end
    Show(enemy.layout, true, "classification")
    for _, profileKey in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
        Pin(Profiles(settings)[profileKey].namesLayout, "raidIcon", "name", "right", 3)
    end
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = 100, 8, 6, 12
        profile.castIcon, profile.castTime, profile.castName = "off", false, false
        Style(profile, "name", { font = "arialn", outline = "none", shadow = true })
        for _, bar in ipairs({ "health", "cast" }) do
            Style(profile, bar, { texture = "flat", background = { r = 0, g = 0, b = 0, a = 0.45 } })
        end
    end)
    -- The Enemies' raid mark at 80% (14 px): beside the 11 pt name 2 px over the bar, it clears the bar.
    Profiles(settings).enemy.layout.raidIcon.scale = 0.8
    Sketch(Profiles(settings).enemy, 11)
    Friendly(settings, 11)
    PruneAll(settings)
end

-- Compact (id dungeon, its name until 1.2): flat bars with the name inside, a tall cast bar with its spell name and time,
-- in the cast colour while you can interrupt it and grey while you cannot; marks sit above the bar; no level.
function BUILDERS.dungeon(settings)
    for _, layout in ipairs(AllLayouts(settings)) do Show(layout, false, "level") end
    for _, layout in ipairs(FullLayouts(settings)) do
        Place(layout, "name", "health", 0, 0)
        Pin(layout, "raidIcon", "health", "top", 3)
        -- Each plate type shows at most one mark on either side of the raid mark.
        Place(layout, "classification", "health", 36, 16)
        Place(layout, "relationshipIcon", "health", 36, 15)
        Place(layout, "quest", "health", -36, 15)
        Place(layout, "pvpIcon", "health", -36, 15)
        SegmentsUnderBar(layout)
    end
    -- A friendly player's PvP and relationship icons beside the name inside the bar, on its line, as on the
    -- names-only plates: a long name runs past the bar's ends, so an icon beside the bar would meet it.
    local players = Profiles(settings).friendlyPlayer.layout
    Pin(players, "pvpIcon", "name", "left", 2)
    Pin(players, "relationshipIcon", "name", "right", 2)
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = 100, 12, 14, 11
        profile.castIcon, profile.castTime, profile.castName = "left", true, true
        for _, row in pairs(profile.auraLayouts) do row.size = 16 end
        Style(profile, "name", { font = "arialn", outline = "outline", shadow = false })
        for _, key in ipairs({ "threat", "guild", "tagged", "classification" }) do Style(profile, key, { font = "arialn" }) end
        FlatBar(profile, "health", 1)
        FlatBar(profile, "cast", 1)
    end)
    -- The Enemies' spell and time 11 pt in the tall cast bar, the threat text under the bars 10 pt.
    local enemy = Profiles(settings).enemy
    AddOwnRules(enemy, "cast", CAST_RULES)
    Style(enemy, "cast", { fontSize = 11 })
    Style(enemy, "threat", { fontSize = 10 })
    Sketch(enemy, 11)
    Quiet(enemy, 16, 12)
    Friendly(settings, 11)
    PruneAll(settings)
end

-- Blizzard: the game's own modern plates (Blizzard_NamePlates' Modern style), drawn by PlateSmith. Its
-- health bar texture (the "modern" atlas) with an outlined name inside its left end, the level in
-- Blizzard's own rounded level box right of the bar, a thin cast bar under it; friendly plates are full
-- plates too (Blizzard's names sit in their bars), players in their class colour with the guild under, NPCs
-- in its friendly green. Its friendly names keep Blizzard's 12 pt (the other looks' friendly names follow
-- their Enemies' size: Friendly).
-- The Blizzard nameplate font throughout, but the Enemies' level (its card's Friz Quadrata).
local BLIZZARD = { width = 166, height = 20, castHeight = 10, nameSize = 12, gap = 5,
    friendlyGreen = { r = 0.25, g = 0.85, b = 0.25 },
    levelColour = { r = 1, g = 0.82, b = 0 },
    uninterruptible = { r = 0.62, g = 0.62, b = 0.62 } }
function BUILDERS.blizzard(settings)
    settings.font, settings.friendly = "default", "full"
    local B = BLIZZARD
    EachProfile(settings, function(profile, profileKey)
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = B.width, B.height, B.castHeight, B.nameSize
        profile.castIcon, profile.castTime, profile.castName = "left", false, true
        profile.healthTexture = "modern"
        local layout = profile.layout
        -- The name's left end 4 px inside the bar (its own left edge meets the bar's right edge, less
        -- the bar's width), as Blizzard draws it; the level box after the bar.
        Pin(layout, "name", "health", "right", 4 - B.width)
        Pin(layout, "level", "health", "right", B.gap)
        Pin(layout, "classification", "level", "right", 2)
        Pin(layout, "relationshipIcon", "level", "right", 3)
        Pin(layout, "quest", "health", "left", 3)
        Pin(layout, "pvpIcon", "health", "left", 3)
        Pin(layout, "raidIcon", profileKey == "friendlyPlayer" and "pvpIcon" or "quest", "left", 3)
        layout.debuffs.y = math.floor(B.height / 2 + 17)
        Show(layout, false, "buffs", "threat")
        if profile.namesLayout then
            -- Names only (Settings › Friendly plates): the level box after the name, the guild under it.
            -- What sat after the name (relationship, raid and elite marks) moves after the level box.
            local names = profile.namesLayout
            for _, key in ipairs({ "relationshipIcon", "raidIcon", "classification", "tagged" }) do
                if names[key].parent == "name" then names[key].parent = "level" end
            end
            Pin(names, "level", "name", "right", B.gap)
            Pin(names, "quest", "name", "left", 3)
            Pin(names, "pvpIcon", "name", "left", 3)
        end
        Style(profile, "name", { outline = "outline", shadow = false })
        -- The box as tall as the bar beside it, as Blizzard's (Height: Match its parent; Padding its sides).
        Style(profile, "level", { box = true, boxShape = "rounded", boxHeight = "parent", padding = 3, outline = "outline" })
        for _, bar in ipairs({ "health", "cast" }) do
            Style(profile, bar, { texture = "modern", border = 1, borderColour = { r = 0, g = 0, b = 0, a = 0.85 },
                background = { r = 0.04, g = 0.04, b = 0.05, a = 0.85 } })
        end
        AddOwnRules(profile, "name", { { when = "", set = "colour", colour = WHITE } })
        AddOwnRules(profile, "level", { { when = "", set = "colour", colour = B.levelColour } })
        AddOwnRules(profile, "cast", { { when = "casting and not interruptible", set = "colour", colour = B.uninterruptible } })
    end)
    -- Friendly players' bars in their class colour, as Blizzard's (the automatic colour without the social colours,
    -- which Blizzard's plates do not draw); their names white (the rule above), but a PvP-flagged ally's in Blizzard's
    -- green beside the faction icon, the selection colour Blizzard's plates give it where they colour names
    -- (CompactUnitFrame_UpdateName's UnitSelectionColor; on Forever its Legacy style, as Modern's names are white).
    -- The green is Display's Colour and icon: with social colours off the class-coloured bar keeps its colour and the
    -- name takes it (PvPMark.ColourOnBar), so the white rule steps aside for a flagged ally (not pvp).
    settings.friendlyRelationshipColours, settings.friendlyPvpStyle = false, "both"
    Profiles(settings).friendlyPlayer.rules.name[1].when = "not pvp"
    local npcs = Profiles(settings).friendlyNPC
    npcs.healthColourMode, npcs.healthColour = "custom", Table.DeepCopy(B.friendlyGreen)
    -- The Enemies: a 10 pt name 3 px inside the bar, the level box 6 px after the bar, 2 px each side of its digits,
    -- which are 10 pt as on the friendly plates (the box is the bar's height).
    local enemy = Profiles(settings).enemy
    Pin(enemy.layout, "name", "health", "right", 3 - B.width)
    Pin(enemy.layout, "level", "health", "right", B.gap + 1)
    Sketch(enemy, 10, 10)
    Style(enemy, "level", { padding = 2 })
    Quiet(enemy, 18, 14)
    PruneAll(settings, { "buffs" })
end

-- Each look's Objects plate (1.3.0): the object's gold name in the look's own font in a box (the Backdrop part, its
-- OBJECT_BOX_FIELDS; the rest of style is the name's), round the Status text and the Action icon too; size: the name's
-- points. The quest mark stays just outside the box.
local OBJECT_BOX_FIELDS = { boxColour = true, boxBorder = true, padding = true, boxShape = true }
local OBJECTS = {
    platesmith = { size = 13, style = { box = true, boxColour = { r = 0.03, g = 0.03, b = 0.05, a = 0.85 },
        boxBorder = { r = 0.6, g = 0.53, b = 0.36, a = 1 }, padding = 5 } },
    classic = { size = 14, style = { font = "friz", outline = "none", shadow = true, box = true,
        boxColour = { r = 0, g = 0, b = 0, a = 0.75 }, boxBorder = { r = 0.3, g = 0.3, b = 0.3, a = 1 }, padding = 4 } },
    sleek = { size = 11, style = { font = "arialn", outline = "none", shadow = true, box = true, boxColour = DARK,
        boxBorder = BLACK, padding = 4 } },
    bold = { size = 14, style = { font = "morpheus", outline = "thick", box = true,
        boxColour = { r = 0, g = 0, b = 0, a = 0.75 }, boxBorder = { r = 0.9, g = 0.7, b = 0.2, a = 1 }, padding = 4 } },
    tank = { size = 13, style = { font = "friz", outline = "outline", box = true,
        boxColour = { r = 0.04, g = 0.03, b = 0.03, a = 0.85 }, boxBorder = { r = 0.35, g = 0.1, b = 0.1, a = 1 }, padding = 4 } },
    healer = { size = 12, style = { font = "friz", outline = "outline", box = true,
        boxColour = { r = 0.03, g = 0.05, b = 0.04, a = 0.8 }, boxBorder = { r = 0.35, g = 0.55, b = 0.35, a = 1 }, padding = 4 } },
    -- Subtle: a faint fill without an edge.
    minimal = { size = 12, style = { font = "arialn", outline = "none", shadow = true, box = true,
        boxColour = { r = 0, g = 0, b = 0, a = 0.45 }, boxBorder = { r = 0, g = 0, b = 0, a = 0 }, padding = 3 } },
    dungeon = { size = 11, style = { font = "arialn", outline = "outline", shadow = false, box = true,
        boxColour = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }, boxBorder = BLACK, padding = 3 } },
    -- Blizzard's tooltip: its dark blue-black fill and light grey edge, the plates' own font unoutlined.
    blizzard = { size = 12, style = { outline = "none", shadow = true, box = true,
        boxColour = { r = 0.09, g = 0.09, b = 0.19, a = 0.9 }, boxBorder = { r = 0.75, g = 0.75, b = 0.75, a = 1 }, padding = 5 } },
}
ProfilePresets.OBJECTS = OBJECTS

-- Each look's object types (Studio's Objects › Type; Core/Designs.lua): herbs, ore, chests and quest objects in a name
-- colour of their own (a colour rule on the name, in the type's layer), and the Status text on for herbs and ore
-- ("Mining 65"). fade: Fade objects you can't use. Classic and Blizzard keep the game's gold names and no
-- fade, as the game draws them. Profiles from before 1.3.0 have no types: every type looks like All objects.
local OBJECT_TYPE_COLOURS = { herb = { r = 0.35, g = 0.9, b = 0.35 }, ore = { r = 0.72, g = 0.7, b = 0.64 },
    loot = { r = 1, g = 0.7, b = 0.15 }, quest = { r = 1, g = 1, b = 0.25 } }
local OBJECT_TYPE_LOOKS = { classic = { plain = true }, blizzard = { plain = true } }
local function ObjectTypes(id)
    local look = OBJECT_TYPE_LOOKS[id] or {}
    local types = {}
    for objectType, colour in pairs(look.plain and {} or OBJECT_TYPE_COLOURS) do
        types[objectType] = { rules = { name = { { when = "", set = "colour", colour = Table.DeepCopy(colour) } } } }
    end
    for _, objectType in ipairs({ "herb", "ore" }) do
        types[objectType] = types[objectType] or {}
        types[objectType].layouts = { layout = { statusText = { visible = true } } }
    end
    return types, not look.plain
end
ProfilePresets.ObjectTypes = ObjectTypes

-- Each look's Elite / rare mark (1.3.0; docs/reviews/ELITE_MARKS.md, renders: elite-marks-shots.ps1 -Looks): its
-- Style and Icon size (the general classificationStyle, classificationIconSize). scale: the Enemies' mark at full
-- size, over Quiet's 80%, where 80% made it smaller than the name it sits before (or Tank's 18 px beside the bar).
-- Blizzard keeps Blizzard's icons; Classic the classic dragon round the level; Sleek the level's suffix (60+); Bold
-- and Healer a frame round the bar (chunky; slim, where an icon at the name's 10 pt is too small to read); Tank the
-- full-size icon left of the bar; the rest a small icon before the name.
local MARKS = {
    platesmith = { style = "beforeName", size = "auto", scale = 1 },
    classic = { style = "dragon", size = "auto" },
    sleek = { style = "suffix", size = "auto" },
    bold = { style = "frame", size = "auto" },
    tank = { style = "icon", size = "standard", scale = 1 },
    healer = { style = "frame", size = "auto" },
    minimal = { style = "beforeName", size = "auto", scale = 1 },
    dungeon = { style = "beforeName", size = "auto", scale = 1 },
    blizzard = { style = "icon", size = "auto" },
}
ProfilePresets.MARKS = MARKS

-- In menu order. name and description are shown to the player.
ProfilePresets.LIST = {
    { id = "platesmith", name = L["PlateSmith"],
        description = L["PlateSmith's own look: a calm name over the bar, a gold level, a slim cast bar with its icon inside."] },
    { id = "classic", name = L["Classic"],
        description = L["The game's classic look: Friz Quadrata, a thin dark border, level and elite dragon right of the bar."] },
    { id = "sleek", name = L["Sleek"],
        description = L["Flat, modern bars with a small name above the left end and health % inside."] },
    { id = "bold", name = L["Bold"],
        description = L["Tall bars in threat colours for your role, thick outlined text, the threat % under the bars."] },
    { id = "tank", name = L["Tank"],
        description = L["Tank threat colours, the threat lead beside the bar, the mob's target under it."] },
    { id = "healer", name = L["Healer"],
        description = L["Thick friendly bars with health % that turn yellow then red; slim enemy plates, dim beside your target."] },
    { id = "minimal", name = L["Minimal"],
        description = L["A thin flat bar under a plain name, only raid and elite marks; friendly plates show names."] },
    { id = "dungeon", name = L["Compact"],
        description = L["Flat bars with the name inside and a tall cast bar, orange when you can interrupt."] },
    { id = "blizzard", name = L["Blizzard"],
        description = L["Blizzard's own look, drawn by PlateSmith so you can change anything."] },
}
for _, preset in ipairs(ProfilePresets.LIST) do preset.build = BUILDERS[preset.id] end

function ProfilePresets.Get(id)
    for _, preset in ipairs(ProfilePresets.LIST) do
        if preset.id == id then return preset end
    end
    return nil
end

-- The preset's settings: the current defaults with its overrides (not yet checked).
function ProfilePresets.Build(id)
    local preset = ProfilePresets.Get(id)
    if not preset then return nil, "preset does not exist" end
    local settings = Table.DeepCopy(S.NormalizeSettings({}))
    preset.build(settings)
    LooseAfterName(Profiles(settings).enemy.layout)
    FitCountdowns(settings)
    local mark = MARKS[id]
    if mark then
        settings.classificationStyle, settings.classificationIconSize = mark.style, mark.size
        local position = Profiles(settings).enemy.layout.classification
        if mark.scale and position and not position.removed then position.scale = mark.scale end
    end
    if COMBO[id] then
        local style = Table.DeepCopy(COMBO[id])
        -- Only with points: an empty row never shows (a new profile's default shows one in combat).
        style.pipShowRow = "points"
        Profiles(settings).enemy.styles.combo = style
    end
    local look, object = OBJECTS[id], Profiles(settings).object
    if look and object then
        object.nameFontSize = look.size
        object.styles = object.styles or {}
        -- The box goes to the Backdrop (round the name, the Status text and the Action icon), the font to the name.
        local name, backdrop = {}, {}
        for field, value in pairs(look.style) do
            if OBJECT_BOX_FIELDS[field] then
                backdrop[field] = Table.DeepCopy(value)
            elseif field ~= "box" then
                name[field] = Table.DeepCopy(value)
            end
        end
        object.styles.name = next(name) and name or nil
        object.styles.backdrop = backdrop
        object.layout.quest.x = -(look.style.padding + 2)
        object.types, settings.objectFadeUnable = ObjectTypes(id)
    end
    return settings
end

-- The looks' version, recorded with the look in a profile made from one (Profiles' CreateFromPreset: settings.look and
-- settings.lookVersion): bumped when a look gains something a profile made from an older one lacks, so a later
-- version can offer it.
ProfilePresets.LOOK_VERSION = 1

-- The Objects style of settings (a profile, or a look's settings): the Objects' World design (its layout, styles, sizes
-- and rules) without its context designs, its type layers, and Fade objects you can't use. A copy.
function ProfilePresets.ObjectStyleOf(settings)
    local world = Table.DeepCopy(Profiles(settings).object)
    local types = world.types
    world.contexts, world.types = nil, nil
    return { world = world, types = types, fade = settings.objectFadeUnable == true }
end

-- A look's Objects style (Objects › Copy style from a look), as a profile made from it has it; nil for no such look.
function ProfilePresets.ObjectStyle(id)
    local settings = ProfilePresets.Build(id)
    if not settings then return nil end
    return ProfilePresets.ObjectStyleOf(S.NormalizeSettings(settings))
end

-- The preset as Blueprint text, for the normal import.
function ProfilePresets.Document(id)
    local settings, reason = ProfilePresets.Build(id)
    if not settings then return nil, reason end
    local document
    document, reason = PS.BlueprintDocument(settings)
    if not document then return nil, reason end
    return PS.Json.Encode(document)
end
