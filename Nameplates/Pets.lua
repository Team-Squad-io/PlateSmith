-- Pets (Type › Pets on the Enemies and Friendly NPCs: each tab's Pets layer, Core/Designs.lua's types; 1.4.2, from
-- PR #3 by ndzwdz): a player's pet draws with its tab's Pets layer, whose Display (petDisplay, Schema's PETS) may draw
-- it as its icon, its icon over its name, its name alone, or not at all, as a totem's (Nameplates/Totems.lua draws
-- the choice for both). A pet is your own (UnitIsUnit "pet") or another player's (UnitIsOtherPlayersPet): a hunter's
-- beast, a warlock's demon, an engineer's dragonling; a totem, a non-combat pet or a wild pet is none, and an
-- unreadable answer is none, so its plate draws as any other. Its icon is its family's (UnitCreatureFamily, matched
-- against the client's family list in its own language), else PlateSmith's plain pet icon. Read when a plate is laid
-- out (Lifecycle's ApplyLayout), never per frame.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local PETS = S.PETS

local Pets = {}
PS.Pets = Pets
Pets.TYPE = PETS.TYPE

-- What is summoned but no pet here: a totem (Type › Totems has it), a companion, a battle pet.
local NOT_PETS = { totem = true, noncombatpet = true, wildpet = true }
function Pets.IsPet(unit)
    if Secret.ReadBoolean(rawget(_G, "UnitIsOtherPlayersPet"), unit) ~= true
        and Secret.ReadBoolean(rawget(_G, "UnitIsUnit"), unit, "pet") ~= true then
        return false
    end
    local creature, _, answered = Secret.CreatureType(unit)
    return answered and not NOT_PETS[creature or ""]
end

-- The type a plate about to be laid out draws with (Lifecycle's ApplyLayout, after Totems.TypeFor): "pet" (Designs'
-- Pets layer) for a pet on a plate type with Pets while its layer changes anything, else nil (nothing is read).
function Pets.TypeFor(db, data)
    if not PETS.PLATES[data.profileKey] or not PS.Designs.Record(db, data.profileKey, Pets.TYPE) then return nil end
    return Pets.IsPet(data.unit) and Pets.TYPE or nil
end

-- The client's creature families: their icons by name (in the client's language) and by family ID, read once, when
-- an icon is first wanted (C_CreatureInfo; none without it). A name or an icon that is not readable is left out.
local families
Pets.MAX_FAMILY_ID = 512
local function Families()
    if families then return families end
    families = { byName = {}, byID = {} }
    local api = rawget(_G, "C_CreatureInfo")
    local info = type(api) == "table" and api.GetCreatureFamilyInfo
    if type(info) ~= "function" then return families end
    local ids
    if type(api.GetCreatureFamilyIDs) == "function" then
        local ok, list = pcall(api.GetCreatureFamilyIDs)
        ids = ok and Secret.IsReadable(list) and type(list) == "table" and list or nil
    end
    if not ids then
        ids = {}
        for id = 1, Pets.MAX_FAMILY_ID do ids[id] = id end
    end
    for _, id in ipairs(ids) do
        local ok, family = pcall(info, id)
        if ok and Secret.IsReadable(family) and type(family) == "table" then
            local icon = Secret.IsReadable(family.iconFile) and family.iconFile or nil
            if (type(icon) == "number" and icon > 0) or (type(icon) == "string" and icon ~= "") then
                families.byID[id] = icon
                local name = Secret.String(family.name)
                if name then families.byName[name] = icon end
            end
        end
    end
    return families
end
-- Forget the families read (tests; a client that had not loaded them yet answers again).
function Pets.Reset() families = nil end

-- A pet whose family has no known icon (a missing API, a name the client keeps from Lua): PlateSmith's plain pet icon,
-- a paw that is no one family's (Media/PetIcon.png, drawn by tools/render/pet-icon.py).
Pets.GENERIC_FILE = "Interface\\AddOns\\PlateSmith\\Media\\PetIcon.png"
function Pets.GenericIcon() return Pets.GENERIC_FILE end
-- A family's icon by its name (the client's own) or its ID, or nil.
function Pets.IconFor(family)
    if type(family) == "string" then return Families().byName[family] end
    if type(family) == "number" then return Families().byID[family] end
    return nil
end
function Pets.Icon(unit)
    local read = rawget(_G, "UnitCreatureFamily")
    local family
    if type(read) == "function" then
        local ok, name = pcall(read, unit)
        family = ok and Secret.String(name) or nil
    end
    return Pets.IconFor(family) or Pets.GenericIcon()
end
PS.Totems.DISPLAY_ICONS[Pets.TYPE] = Pets.Icon

-- Studio's preview has no unit: the open tab's sample pet ({ family = ID }: Pets.SampleSource, which Studio sets;
-- without it a wolf), its family's icon, else the plain one.
Pets.sample = { family = 1 }
function Pets.SampleIcon()
    local sample = Pets.SampleSource and Pets.SampleSource() or Pets.sample
    return Pets.IconFor(sample.family) or Pets.GenericIcon()
end

-- The pet's icon as a picture (Media's unit:pet, PETS.PICTURE): an image part showing it is a pet icon part, offered
-- under Type › Pets (+ Add › Shape › Pet icon, an image's From › Unit). A unit that is no pet has none: the part hides.
local function UnitPetIcon(unit)
    if not Pets.IsPet(unit) then return nil end
    return Pets.Icon(unit)
end
PS.Media.RegisterUnitPicture("pet", { label = PS.L["This pet's icon"], read = UnitPetIcon, sample = Pets.SampleIcon,
    size = { PETS.ICON_SIZE, PETS.ICON_SIZE }, coords = { 0.08, 0.92, 0.08, 0.92 }, only = Pets.TYPE })
