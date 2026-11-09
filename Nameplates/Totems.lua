-- Totems (Type › Totems on the Enemies and Friendly NPCs: each tab's Totems layer, Core/Designs.lua's types): a totem's
-- plate draws with its tab's Totems layer, whose Display (totemDisplay, Schema's TOTEMS) may draw it as its icon, its
-- icon over its name, its name alone, or not at all. A totem is a unit whose creature type (Secret.CreatureType, the one
-- reader) is readably "totem"; unknown is no totem, so its plate draws as any other. Its icon is its spell's: the game
-- gives addons none for the unit, so its name (only when readable) finds the spell, the player's own by name in any
-- language, else Data/Totems.lua's rank 1 spell ID by its English name. Read when a plate is laid out (Lifecycle's
-- ApplyLayout, also after a change of kind), never per frame.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local TOTEMS = S.TOTEMS

local Totems = {}
PS.Totems = Totems

-- A texture the client's spell texture API gives for spell (a spell ID or a name the player knows): readable, or nil.
local function Usable(texture)
    if not Secret.IsReadable(texture) then return nil end
    if type(texture) == "number" or (type(texture) == "string" and texture ~= "") then return texture end
    return nil
end
function Totems.SpellTexture(spell)
    local api = rawget(_G, "C_Spell")
    local get = type(api) == "table" and api.GetSpellTexture or rawget(_G, "GetSpellTexture")
    if type(get) == "function" then
        local ok, texture = pcall(get, spell)
        texture = ok and Usable(texture) or nil
        if texture then return texture end
    end
    -- The spell's info: C_Spell's table (iconID), else the older GetSpellInfo's third result.
    local info = type(api) == "table" and api.GetSpellInfo
    if type(info) == "function" then
        local ok, result = pcall(info, spell)
        if ok and Secret.IsReadable(result) and type(result) == "table" then return Usable(result.iconID) end
        return nil
    end
    info = rawget(_G, "GetSpellInfo")
    if type(info) ~= "function" then return nil end
    local ok, _, _, icon = pcall(info, spell)
    return ok and Usable(icon) or nil
end

-- A totem's spell name, without a trailing rank ("Searing Totem III" -> "Searing Totem"), and its Data/Totems.lua key,
-- without " Totem" too ("Searing"). Only ever given a readable name.
function Totems.BaseNames(name)
    local spell = name:match("^(.-) [IVX]+$") or name
    return spell, spell:match("^(.-) Totem$") or spell
end

-- Icons found, by the unit's readable name (bounded: a city's worth of totems, then it starts over). What is not found
-- is not kept, so a spell the client had not loaded yet is asked again at the next layout. IconFor takes a readable
-- name (Studio's preview: its sample totem's).
local found, foundCount, MAX_FOUND = {}, 0, 64
-- A totem whose own icon is not found (a creature's own totem such as Lava Spout Totem, a name the client keeps from
-- Lua, or one in a language the table does not have): PlateSmith's plain totem icon, a carved pole that is no one
-- spell's (Media/TotemIcon.png, drawn by tools/render/totem-icon.py). Live report 2026-11-11: a Razorfen totem drew
-- no icon at all; then: not a specific totem's icon either.
Totems.GENERIC_FILE = "Interface\\AddOns\\PlateSmith\\Media\\TotemIcon.png"
function Totems.GenericIcon() return Totems.GENERIC_FILE end
function Totems.Icon(unit)
    local name = Secret.ReadName(unit)
    return name and Totems.IconFor(name) or Totems.GenericIcon()
end
function Totems.IconFor(name)
    if type(name) ~= "string" then return nil end
    local texture = found[name]
    if texture then return texture end
    local spell, key = Totems.BaseNames(name)
    texture = Totems.SpellTexture(spell)
    local id = not texture and PS.TotemSpells and PS.TotemSpells[key]
    if id then texture = Totems.SpellTexture(id) end
    if not texture then return nil end
    if foundCount >= MAX_FOUND then found, foundCount = {}, 0 end
    found[name], foundCount = texture, foundCount + 1
    return texture
end

function Totems.IsTotem(unit)
    return (Secret.CreatureType(unit)) == "totem"
end

-- The type a plate about to be laid out draws with (Lifecycle's ApplyLayout): "totem" (Designs' Totems layer) for a
-- totem on a plate type with Totems while its layer changes anything, else nil (the creature type is then not read).
Totems.TYPE = "totem"
function Totems.TypeFor(db, data)
    if not TOTEMS.PLATES[data.profileKey] or not PS.Designs.Record(db, data.profileKey, Totems.TYPE) then return nil end
    return Totems.IsTotem(data.unit) and Totems.TYPE or nil
end

-- Studio's preview has no unit: the open tab's sample totem ({ name, key }: Totems.SampleSource, which Studio sets;
-- without it the Enemies'), its icon found as a plate's is, else by its Data/Totems.lua key's spell.
Totems.sample = { name = "Searing Totem", key = "Searing" }
function Totems.SampleIcon()
    local sample = Totems.SampleSource and Totems.SampleSource() or Totems.sample
    local id = PS.TotemSpells and PS.TotemSpells[sample.key]
    return Totems.IconFor(sample.name) or (id and Totems.SpellTexture(id)) or nil
end

-- The totem's icon as a picture (Media's unit:totem, TOTEMS.PICTURE): an image part showing it is a totem icon part,
-- offered under Type › Totems (+ Add › Shape › Totem icon, an image's From › Totem). A unit that is no totem has none:
-- the part hides; a totem without a known icon has the plain one (Totems.GenericIcon).
local function UnitTotemIcon(unit)
    if not Totems.IsTotem(unit) then return nil end
    return Totems.Icon(unit)
end
PS.Media.RegisterUnitPicture("totem", { label = PS.L["This totem's icon"], read = UnitTotemIcon, sample = Totems.SampleIcon,
    size = { TOTEMS.ICON_SIZE, TOTEMS.ICON_SIZE }, coords = { 0.08, 0.92, 0.08, 0.92 }, only = Totems.TYPE })

-- What a plate laid out now draws for a totem: nil (not drawn with the Totems layer, or its Display is Plate),
-- "hidden", "name", "icon" or "iconName", and for the last two its icon parts (TOTEMS.IconKeys of layout). With no
-- icon found, or no icon part, Icon and Icon and name show the name rather than nothing. drawn: PlateSmith draws this
-- plate (its own, shown).
function Totems.Choice(data, drawn, layout)
    if not drawn or data.objectType ~= Totems.TYPE then return nil end
    local choice = TOTEMS.Choice(data.profile)
    if choice ~= "icon" and choice ~= "iconName" then return choice end
    local icons = TOTEMS.IconKeys(data.profile, layout)
    if not icons or not Totems.Icon(data.unit) then return "name" end
    return choice, icons
end

-- The plate side: a laid-out plate's unit pictures drawn for its unit. ApplyValueKind draws them when the plate's
-- appearance is applied; a plate kept prepared for a new unit (the same layout) is not applied again, so each layout
-- draws them again here (each part's picture missing, so hidden, while its unit has none).
PS._CreatePlateTotems = function(context)
    local Pass = {}
    local Media, VALUE_KEYS = PS.Media, context.VALUE_KEYS

    function Pass.Update(data)
        local slots, graphics = data.own and data.profile and data.profile.valueSlots, data.valueGraphics
        if not slots or not graphics then return end
        for index = 1, S.VALUE_SLOT_COUNT do
            local key = VALUE_KEYS[index]
            local slot = slots[key]
            local graphic = graphics[key] and graphics[key].icon
            if graphic and slot and slot.kind == "icon" and Media.UnitPicture(slot.image) then
                graphic.plateSmithMissing = not PS.ValueImage.Draw(graphic, slot, data.unit) or nil
            end
        end
    end

    function Pass.Release() end

    return Pass
end
