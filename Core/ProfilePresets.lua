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
    { id = "tagged", name = L["Grey when tagged"], kind = "colour", rules = {
        { when = "tagged", set = "colour", colour = { r = 0.5, g = 0.5, b = 0.5 } },
    } },
    { id = "threatTank", name = L["Threat colours (tank)"], kind = "colour", rules = {
        { when = "role.tank and threat.holding", set = "colour", colour = { r = 0.5, g = 0.5, b = 1 } },
        { when = "role.tank and threat.losing", set = "colour", colour = { r = 1, g = 1, b = 0 } },
        { when = "role.tank and threat.offtank", set = "colour", colour = { r = 0.73, g = 0.92, b = 1 } },
        { when = "role.tank and threat.other and not threat.offtank", set = "colour", colour = { r = 1, g = 0, b = 0 } },
    } },
    { id = "threatDps", name = L["Threat colours (DPS/healer)"], kind = "colour", rules = {
        { when = "not role.tank and threat.pulling", set = "colour", colour = { r = 1, g = 0.8, b = 0 } },
        { when = "not role.tank and threat.holding", set = "colour", colour = { r = 1, g = 0.11, b = 0 } },
    } },
}

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
-- Dungeon's cast bar: orange while it can be interrupted, grey while it cannot.
local CAST_RULES = {
    { when = "casting and interruptible", set = "colour", colour = { r = 1, g = 0.55, b = 0.1 } },
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
    slot.source, slot.anchor, slot.fontSize = source, "health", fontSize or 9
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
local function EachProfile(settings, callback)
    for _, key in ipairs(S.profileOrder) do callback(Profiles(settings)[key], key) end
end
local function PruneAll(settings, keep)
    for _, layout in ipairs(AllLayouts(settings)) do Prune(layout, keep) end
end

-- A flat bar: a solid fill over a dark background, with a border of size px (0: none).
local function FlatBar(profile, key, size)
    Style(profile, key, { texture = "flat", background = DARK, border = size > 0 and size or nil,
        borderColour = size > 0 and BLACK or nil })
end

-- Each builder changes a complete default settings table in place.
local BUILDERS = {}

function BUILDERS.platesmith() end

-- Classic: the game's own plates of old. Friz Quadrata, the game's bar texture framed by a thin
-- dark border, a white name centred above, level and the elite dragon right of the bar, the
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
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = 120, 10, 10, 12
        profile.castIcon, profile.castTime, profile.castName = "left", false, true
        for _, key in ipairs({ "name", "level", "guild", "tagged", "classification" }) do
            Style(profile, key, { font = "friz", outline = "none", shadow = true })
        end
        for _, key in ipairs({ "health", "cast" }) do
            Style(profile, key, { texture = "blizzard", border = 1, borderColour = { r = 0.08, g = 0.08, b = 0.08, a = 1 } })
        end
    end)
    local enemy = Profiles(settings).enemy
    AddRules(enemy, "health", "tagged")
    AddOwnRules(enemy, "name", { { when = "", set = "colour", colour = WHITE } })
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
        local key = AddValue(profile, 1, "healthPercent", profile.width / 2 - 14, 10)
        for _, text in ipairs({ "name", "level", "guild", "threat", "tagged", "classification", key }) do
            Style(profile, text, { font = "arialn", outline = "none", shadow = true })
        end
        Style(profile, key, { outline = "outline", shadow = false })
        FlatBar(profile, "health", 1)
        FlatBar(profile, "cast", 1)
    end)
    PruneAll(settings)
end

-- Bold: chunky and threat first. A tall bar with a heavy border that takes the threat colours for
-- your role, Morpheus names with a thick outline, the threat % boxed right of the bar, a large
-- elite mark left of it and a large raid mark over the name; debuffs only.
function BUILDERS.bold(settings)
    for _, layout in ipairs(FullLayouts(settings)) do
        layout.name.y = 22
        Pin(layout, "threat", "health", "right", 5)
        Pin(layout, "classification", "health", "left", 4)
        layout.classification.scale = 1.35
        Pin(layout, "raidIcon", "name", "top", 2)
        layout.raidIcon.scale = 1.5
        Pin(layout, "tagged", "name", "right", 4)
        layout.debuffs.y = 70
        Show(layout, false, "buffs")
    end
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.nameFontSize = 120, 14, 13
        profile.auraLayouts.debuffs.size = 16
        Style(profile, "name", { font = "morpheus", outline = "thick" })
        for _, key in ipairs({ "level", "guild", "tagged", "classification" }) do
            Style(profile, key, { font = "friz", outline = "thick" })
        end
        Style(profile, "threat", { font = "friz", outline = "thick", box = true, padding = 2,
            boxColour = { r = 0, g = 0, b = 0, a = 0.75 }, boxBorder = { r = 0.9, g = 0.7, b = 0.2, a = 1 } })
        for _, key in ipairs({ "health", "cast" }) do Style(profile, key, { texture = "blizzard", border = 2, borderColour = BLACK }) end
    end)
    AddRules(Profiles(settings).enemy, "health", "threatTank", "threatDps")
    PruneAll(settings)
end

-- Tank: the tank threat colours on the bar, the threat lead large and boxed right of it, who the
-- mob is targeting under the bars, the elite and raid marks left of the bar, compact auras.
function BUILDERS.tank(settings)
    local enemy = Profiles(settings).enemy
    local layout = enemy.layout
    Pin(layout, "classification", "health", "left", 4)
    Pin(layout, "raidIcon", "classification", "left", 3)
    Pin(layout, "tagged", "name", "right", 4)
    Show(layout, false, "threat")
    Show(layout, true, "targetName")
    AddRules(enemy, "health", "threatTank")
    local key, slot = AddValue(enemy, 1, "leadPercent", 0, 14)
    slot.colour = { r = 1, g = 0.85, b = 0.3 }
    Pin(layout, key, "health", "right", 5)
    Style(enemy, key, { font = "friz", outline = "thick", box = true, padding = 3,
        boxColour = { r = 0.12, g = 0, b = 0, a = 0.85 }, boxBorder = { r = 0.85, g = 0.15, b = 0.1, a = 1 } })
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight = 120, 12
        for _, row in pairs(profile.auraLayouts) do row.size, row.spacing, row.count, row.columns = 14, 1, 5, 5 end
        for _, bar in ipairs({ "health", "cast" }) do
            Style(profile, bar, { texture = "blizzard", border = 1, borderColour = { r = 0.25, g = 0.05, b = 0.05, a = 1 } })
        end
        Style(profile, "targetName", { font = "friz", outline = "outline" })
    end)
    PruneAll(settings)
end

-- Healer: friendly plates are full plates with thick bars that blend from green through yellow
-- to red, health % inside; enemy plates are slim, dim until targeted, the name and bar only.
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
    enemy.width, enemy.healthHeight, enemy.nameFontSize = 100, 6, 10
    Show(enemy.layout, false, "level", "threat", "buffs", "debuffs")
    FlatBar(enemy, "health", 0)
    FlatBar(enemy, "cast", 0)
    AddOwnRules(enemy, "name", { { when = "not targeted", set = "alpha", alpha = 0.5 } })
    AddOwnRules(enemy, "health", { { when = "not targeted", set = "alpha", alpha = 0.5 } })
    PruneAll(settings)
end

-- Minimal: friendly plates show names only; enemies a tiny flat bar under a small name, with the
-- raid mark and nothing else (no level, marks, borders or auras).
function BUILDERS.minimal(settings)
    settings.friendly = "names"
    for _, layout in ipairs(AllLayouts(settings)) do
        Show(layout, false, "level", "quest", "questLoot", "pvpIcon", "relationshipIcon", "classification", "tagged",
            "threat", "guild", "power", "buffs", "debuffs", "targetName")
    end
    for _, layout in ipairs(FullLayouts(settings)) do
        -- 3 px: the raid mark beside the name (16 px, taller than it) clears the bar.
        Pin(layout, "name", "health", "top", 3)
        Pin(layout, "raidIcon", "name", "left", 3)
    end
    for _, profileKey in ipairs({ "friendlyPlayer", "friendlyNPC" }) do
        Pin(Profiles(settings)[profileKey].namesLayout, "raidIcon", "name", "right", 3)
    end
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = 80, 6, 5, 10
        profile.castIcon, profile.castTime, profile.castName = "off", false, false
        Style(profile, "name", { font = "arialn", outline = "none", shadow = true })
        for _, bar in ipairs({ "health", "cast" }) do
            Style(profile, bar, { texture = "flat", background = { r = 0, g = 0, b = 0, a = 0.45 } })
        end
    end)
    PruneAll(settings)
end

-- Dungeon: small flat bars with the name inside, a tall cast bar with its spell name and time,
-- orange while you can interrupt it and grey while you cannot; marks sit above the bar; no level.
function BUILDERS.dungeon(settings)
    for _, layout in ipairs(FullLayouts(settings)) do
        Show(layout, false, "level")
        Place(layout, "name", "health", 0, 0)
        Pin(layout, "raidIcon", "health", "top", 3)
        -- Each plate type shows at most one mark on either side of the raid mark.
        Place(layout, "classification", "health", 36, 16)
        Place(layout, "relationshipIcon", "health", 36, 15)
        Place(layout, "quest", "health", -36, 15)
        Place(layout, "pvpIcon", "health", -36, 15)
    end
    EachProfile(settings, function(profile)
        profile.width, profile.healthHeight, profile.castHeight, profile.nameFontSize = 90, 8, 14, 9
        profile.castIcon, profile.castTime, profile.castName = "left", true, true
        for _, row in pairs(profile.auraLayouts) do row.size = 16 end
        Style(profile, "name", { font = "arialn", outline = "outline", shadow = false })
        for _, key in ipairs({ "threat", "guild", "tagged", "classification" }) do Style(profile, key, { font = "arialn" }) end
        FlatBar(profile, "health", 1)
        FlatBar(profile, "cast", 1)
    end)
    AddOwnRules(Profiles(settings).enemy, "cast", CAST_RULES)
    PruneAll(settings)
end

-- In menu order. name and description are shown to the player.
ProfilePresets.LIST = {
    { id = "platesmith", name = L["PlateSmith"], description = L["PlateSmith's own defaults."] },
    { id = "classic", name = L["Classic"],
        description = L["The game's classic look: Friz Quadrata, a thin dark border, level and elite dragon right of the bar."] },
    { id = "sleek", name = L["Sleek"],
        description = L["Flat, modern bars with a small name above the left end and health % inside."] },
    { id = "bold", name = L["Bold"],
        description = L["Tall bars in threat colours for your role, thick outlined text, boxed threat % and big marks."] },
    { id = "tank", name = L["Tank"],
        description = L["Tank threat colours, the threat lead large and boxed beside the bar, the mob's target under it."] },
    { id = "healer", name = L["Healer"],
        description = L["Thick friendly bars with health % that turn yellow then red; slim, dim enemy plates."] },
    { id = "minimal", name = L["Minimal"],
        description = L["A tiny flat bar under a small name, raid marks only; friendly plates show names."] },
    { id = "dungeon", name = L["Dungeon"],
        description = L["Small flat bars with the name inside and a tall cast bar, orange when you can interrupt."] },
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
    return settings
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
