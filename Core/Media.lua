local _, PS = ...
local L = PS.L

-- Bar textures, fonts and alert sounds. Built-in choices always exist; when the optional
-- LibSharedMedia-3.0 is loaded its registered media are offered as well.
-- Stored LSM choices are "lsm:<name>", so a missing library or a removed
-- media entry falls back to the built-in default instead of failing.
local Media = {}
PS.Media = Media

local LSM_PREFIX = "lsm:"
-- atlas: drawn with Blizzard's atlas where the client has it (modern: its own nameplates' health bar),
-- else with path.
local statusBars = {
    { value = "blizzard", label = L["Blizzard"], path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { value = "flat", label = L["Flat"], path = "Interface\\Buttons\\WHITE8X8" },
    { value = "modern", label = L["Blizzard modern"], path = "Interface\\TargetingFrame\\UI-StatusBar",
        atlas = "UI-HUD-CoolDownManager-Bar" },
}
local statusBarByKey = {}
for _, entry in ipairs(statusBars) do statusBarByKey[entry.value] = entry end
local fonts = {
    { value = "default", label = L["Blizzard nameplate font"] },
    { value = "friz", label = L["Friz Quadrata"], path = "Fonts\\FRIZQT__.TTF" },
    { value = "arialn", label = L["Arial Narrow"], path = "Fonts\\ARIALN.TTF" },
    { value = "morpheus", label = L["Morpheus"], path = "Fonts\\MORPHEUS.TTF" },
    { value = "skurri", label = L["Skurri"], path = "Fonts\\SKURRI.TTF" },
}
local fontByKey = {}
for _, entry in ipairs(fonts) do fontByKey[entry.value] = entry end
-- Names in other alphabets, to check a font draws them: Studio's Sample name and /ps testname
-- (its short word).
Media.sampleNames = {
    { value = "chinese", short = "cn", name = "测试玩家", guild = "<测试公会>" },
    { value = "korean", short = "kr", name = "테스트", guild = "<테스트 길드>" },
    { value = "russian", short = "ru", name = "Тестовый", guild = "<Тестовая гильдия>" },
}

local function SharedMedia()
    if type(LibStub) ~= "table" and type(LibStub) ~= "function" then return nil end
    local ok, library = pcall(LibStub, "LibSharedMedia-3.0", true)
    return ok and library or nil
end

-- A well-formed LSM reference, even if LSM is absent here.
local function IsSharedReference(value)
    return type(value) == "string" and #value <= 80 and value:sub(1, #LSM_PREFIX) == LSM_PREFIX and #value > #LSM_PREFIX
end

function Media.IsStatusBar(value) return statusBarByKey[value] ~= nil or IsSharedReference(value) end
function Media.IsFont(value) return fontByKey[value] ~= nil or IsSharedReference(value) end

-- The built-in choices, then LibSharedMedia's of kind. Kept per kind while LSM's list is the same table at the
-- same length (it only grows as addons register media), so a refresh of every font and texture field (Studio
-- asks on each) makes no list; read only.
local sharedChoices = {}
local function SharedChoices(builtIn, kind)
    local library = SharedMedia()
    local names
    if library and type(library.List) == "function" then
        local ok, list = pcall(library.List, library, kind)
        if ok and type(list) == "table" then names = list end
    end
    local kept = sharedChoices[kind]
    if kept and kept.names == names and kept.count == (names and #names or 0) then return kept.choices end
    local choices = {}
    for _, entry in ipairs(builtIn) do choices[#choices + 1] = { value = entry.value, label = entry.label } end
    for _, name in ipairs(names or {}) do
        if type(name) == "string" then choices[#choices + 1] = { value = LSM_PREFIX .. name, label = name } end
    end
    sharedChoices[kind] = { names = names, count = names and #names or 0, choices = choices }
    return choices
end

-- Both lists are kept (SharedChoices) and shared: read only.
function Media.StatusBarChoices() return SharedChoices(statusBars, "statusbar") end
function Media.FontChoices() return SharedChoices(fonts, "font") end
-- Sounds: the caller's own built-in list ({ value, label }; one caller, Rescue's alerts), then LibSharedMedia's.
function Media.SoundChoices(builtIn) return SharedChoices(builtIn, "sound") end
Media.IsSharedReference = IsSharedReference

local function Fetch(kind, value)
    if type(value) ~= "string" or value:sub(1, #LSM_PREFIX) ~= LSM_PREFIX then return nil end
    local library = SharedMedia()
    if not library or type(library.Fetch) ~= "function" then return nil end
    local ok, path = pcall(library.Fetch, library, kind, value:sub(#LSM_PREFIX + 1), true)
    return ok and type(path) == "string" and path or nil
end

function Media.StatusBarPath(value)
    local entry = statusBarByKey[value]
    if entry then return entry.path end
    return Fetch("statusbar", value) or statusBars[1].path
end

-- An "lsm:<name>" sound's file while LibSharedMedia has it, else nil (the caller plays its own default).
function Media.SoundPath(value) return Fetch("sound", value) end

function Media.StatusBarAtlas(value)
    local entry = statusBarByKey[value]
    return entry and entry.atlas or nil
end

-- Draws value on a status bar's fill, or on a plain texture: its file, then its atlas where it has one.
-- An atlas the client refuses (or lacks) leaves the file.
function Media.SetStatusBar(target, value)
    local path, atlas = Media.StatusBarPath(value), Media.StatusBarAtlas(value)
    -- By its type where it says one (a texture may answer to every widget method in some builds).
    local bar
    if type(target.GetObjectType) == "function" then bar = target:GetObjectType() == "StatusBar"
    else bar = type(target.SetStatusBarTexture) == "function" end
    if bar then target:SetStatusBarTexture(path) else target:SetTexture(path) end
    if not atlas then return end
    local texture = target
    if bar then texture = type(target.GetStatusBarTexture) == "function" and target:GetStatusBarTexture() or nil end
    local ok, result = false, nil
    if type(texture) == "table" and type(texture.SetAtlas) == "function" then ok, result = pcall(texture.SetAtlas, texture, atlas) end
    if ok and result ~= false then return end
    if bar then target:SetStatusBarTexture(path) else target:SetTexture(path) end
end

-- Pictures: what a custom part of kind icon (Studio's Image) draws. A picture is a reference, never a file path in a
-- profile or a Blueprint (STANDARDS 13):
--   kit:<id>           PlateSmith's own pieces (KIT; a module adds its own with PS.RegisterPicture, as "<module>.<name>")
--   atlas:<name>       a game atlas, looked up when drawn (C_Texture.GetAtlasInfo)
--   lsm:<type>:<name>  LibSharedMedia's background or statusbar media, while it is installed
--   media:<name>       the player's own files ("My media": account state, PS.GetState().media, name -> path)
--   unit:<name>        a picture the plate's unit gives (UNIT_PICTURES: unit:totem, the totem's spell icon), found
--                      when the plate is laid out; Studio's preview, which has no unit, draws the entry's sample
-- A part without a picture of its own (slot.image) draws its icon, one of the twelve kit pieces it had before 1.4.0, so
-- a saved part looks as it did. Media.Picture answers nil for one this install does not have: the plates draw nothing.
local PICTURE_LENGTH = 100
Media.PICTURE_SOURCES = { "kit", "atlas", "lsm", "media", "unit" }
-- Unit pictures by name: { label, read = function(unit) -> texture or nil, sample = function() -> texture or nil,
-- size = { width, height } (a new part's), coords (as a kit piece's), only = the Type it is offered under ("totem") }.
-- Drawn as a kit piece is, its entry in the piece's place. PlateSmith's own (Media.
-- RegisterUnitPicture: Nameplates/Totems.lua), not a module extension point.
Media.UNIT_PICTURES = {}
function Media.RegisterUnitPicture(name, definition)
    assert(type(name) == "string" and name:match("^%l+$") and type(definition.read) == "function", "unit picture")
    Media.UNIT_PICTURES[name] = definition
end
Media.LSM_PICTURE_TYPES = { background = true, statusbar = true }
-- My media: at most MEDIA_MAX names of at most MEDIA_NAME_LENGTH characters, each a path of at most MEDIA_PATH_LENGTH.
Media.MEDIA_MAX, Media.MEDIA_NAME_LENGTH, Media.MEDIA_PATH_LENGTH = 64, 32, 200
-- Kit pieces: id, label, file, coords ({ left, right, top, bottom }; the whole file without), turn (clockwise quarter
-- turns the file is drawn at: an arrow file pointing down drawn pointing right), blend (ADD for light), size (a new
-- part's width and height), slice ({ left, top, right, bottom } px: nine-slice margins, kept for Fit to part where the
-- client has SetTextureSliceMargins) and hidden (kept for saved parts, not offered). The first twelve are the icons
-- custom parts had before 1.4.0 (their ids are the slot's icon values).
local KIT = {
    { id = "raid8", label = L["Skull"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
    { id = "raid7", label = L["Cross"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
    { id = "raid6", label = L["Square"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
    { id = "raid5", label = L["Moon"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
    { id = "raid4", label = L["Triangle"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
    { id = "raid3", label = L["Diamond"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
    { id = "raid2", label = L["Circle"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
    { id = "raid1", label = L["Star"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
    { id = "skull", label = L["Skull"], file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", hidden = true },
    { id = "quest", label = L["Quest mark"], file = "Interface\\GossipFrame\\AvailableQuestIcon" },
    { id = "sword", label = L["Sword"], file = "Interface\\Icons\\INV_Sword_04" },
    { id = "shield", label = L["Shield"], file = "Interface\\Icons\\INV_Shield_06" },
    -- 1.4.0's decoration pieces, game art every client has: the tutorial's gold arrow (a down arrow, drawn pointing
    -- right), the cast bar's spark and a soft round glow.
    { id = "arrow", label = L["Arrow"], file = "Interface\\Buttons\\UI-MicroStream-Yellow", turn = 3, size = { 18, 18 } },
    { id = "spark", label = L["Spark"], file = "Interface\\CastingBar\\UI-CastingBar-Spark", blend = "ADD",
        size = { 12, 26 } },
    { id = "glow", label = L["Soft glow"], file = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64", blend = "ADD",
        size = { 32, 32 } },
    -- A plain white disc to tint (the combo points' round mask): the Range part's dot.
    { id = "dot", label = L["Dot"], file = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", size = { 10, 10 } },
}
local kitById = {}
for _, entry in ipairs(KIT) do kitById[entry.id] = entry end
Media.KIT = KIT
-- "kit:<icon>" for each icon a slot may hold, made once.
local ICON_PICTURES = {}
for _, entry in ipairs(KIT) do ICON_PICTURES[entry.id] = "kit:" .. entry.id end

-- My media's name: letters, digits, spaces and _ - . (trimmed), at most MEDIA_NAME_LENGTH characters.
function Media.IsMediaName(name)
    return type(name) == "string" and #name >= 1 and #name <= Media.MEDIA_NAME_LENGTH and name:match("^[%w_%-%.][%w _%-%.]*$")
        ~= nil and name:sub(-1) ~= " "
end

-- A My media path made valid: inside Interface\AddOns\ (any case, / or \), a .tga, .blp or .png file, no "..", at
-- most MEDIA_PATH_LENGTH characters, with \ separators; nil for anything else. The client cannot tell Lua whether the
-- file exists: a path to nothing draws nothing, and Studio's preview is the player's check.
function Media.MediaPath(path)
    if type(path) ~= "string" then return nil end
    path = path:gsub("/", "\\"):match("^%s*(.-)%s*$")
    if #path > Media.MEDIA_PATH_LENGTH or path:find("[%c|]") or path:find("..", 1, true) then return nil end
    local lower = path:lower()
    local prefix = "interface\\addons\\"
    if lower:sub(1, #prefix) ~= prefix or not lower:sub(#prefix + 1):match("^[^\\]+\\.") then return nil end
    local extension = lower:match("%.(%a+)$")
    if extension ~= "tga" and extension ~= "blp" and extension ~= "png" then return nil end
    return path
end

-- A My media list made valid (name -> path), at most MEDIA_MAX of them in name order; a new table.
function Media.NormalizeMediaList(list)
    local result, names = {}, {}
    for name in pairs(type(list) == "table" and list or {}) do
        if Media.IsMediaName(name) and Media.MediaPath(list[name]) then names[#names + 1] = name end
    end
    table.sort(names)
    for index = 1, math.min(#names, Media.MEDIA_MAX) do result[names[index]] = Media.MediaPath(list[names[index]]) end
    return result
end

local NO_MEDIA = {}
-- The account's My media list (read only).
function Media.MyMedia()
    local state = type(PS.GetState) == "function" and PS.GetState() or nil
    return state and type(state.media) == "table" and state.media or NO_MEDIA
end

-- What ref names: its source ("kit", "atlas", "lsm", "media", "unit"), the name, and for lsm its media type; nil for
-- anything that is not a well-formed reference (a known source with a bad name, or an unknown source).
function Media.PictureSource(ref)
    if type(ref) ~= "string" or #ref > PICTURE_LENGTH or ref:find("[%c|]") then return nil end
    local source, name = ref:match("^(%l+):(.+)$")
    if source == "kit" then
        if #name <= 64 and name:match("^%a[%w_%.%-]*$") then return "kit", name end
    elseif source == "atlas" then
        if #name <= 64 and name:match("^[%w_%-%.]+$") then return "atlas", name end
    elseif source == "lsm" then
        local kind, media = name:match("^(%l+):(.+)$")
        if kind and Media.LSM_PICTURE_TYPES[kind] and #media <= 64 then return "lsm", media, kind end
    elseif source == "media" then
        if Media.IsMediaName(name) then return "media", name end
    elseif source == "unit" then
        if #name <= 32 and name:match("^%l+$") then return "unit", name end
    end
    return nil
end
-- The unit picture's name ref names ("totem" for unit:totem), or nil.
function Media.UnitPicture(ref)
    local source, name = Media.PictureSource(ref)
    return source == "unit" and name or nil
end
-- The prefix ref starts with ("kit" from "kit:arrow"), well formed or not: a Blueprint skips a picture from a source
-- this version does not know and refuses a bad one from a source it does.
function Media.PicturePrefix(ref)
    return type(ref) == "string" and ref:match("^(%l+):") or nil
end
function Media.IsPicture(ref) return Media.PictureSource(ref) ~= nil end

local function AtlasExists(name)
    local api = type(C_Texture) == "table" and C_Texture.GetAtlasInfo
    if type(api) ~= "function" then return false end
    local ok, info = pcall(api, name)
    return ok and type(info) == "table"
end

-- How to draw ref on this install: "file" and its path (and a kit piece's entry), or "atlas" and its name; nil while
-- the picture is missing (an unknown kit piece or atlas, LibSharedMedia or its media absent, a My media name not in
-- the list). A unit picture is unit's (nil: the entry's sample), missing while it has none (read under pcall).
function Media.Picture(ref, unit)
    local source, name, kind = Media.PictureSource(ref)
    if source == "kit" then
        local entry = kitById[name]
        if entry then return "file", entry.file, entry end
    elseif source == "atlas" then
        if AtlasExists(name) then return "atlas", name end
    elseif source == "lsm" then
        local path = Fetch(kind, LSM_PREFIX .. name)
        if path then return "file", path end
    elseif source == "media" then
        local path = Media.MyMedia()[name]
        if path then return "file", path end
    elseif source == "unit" then
        local entry = Media.UNIT_PICTURES[name]
        local read = entry and (unit and entry.read or entry.sample)
        local ok, texture = false, nil
        if read then ok, texture = pcall(read, unit) end
        if ok and (type(texture) == "number" or (type(texture) == "string" and texture ~= "")) then
            return "file", texture, entry
        end
    end
    return nil
end
-- Whether this install lacks ref's picture (a unit picture: only one it does not know; each unit may have its own).
function Media.PictureMissing(ref)
    local name = Media.UnitPicture(ref)
    if name then return Media.UNIT_PICTURES[name] == nil end
    return Media.Picture(ref) == nil
end

-- The picture a custom part draws: its own (slot.image), else its icon's kit piece (raid8, the skull, without one).
function Media.SlotPicture(slot)
    if type(slot) ~= "table" then return ICON_PICTURES.raid8 end
    return slot.image or ICON_PICTURES[slot.icon] or ICON_PICTURES.raid8
end

-- A kit piece's entry by id (read only), or nil.
function Media.KitPiece(id) return kitById[id] end

-- The eight texture coordinates (upper left, lower left, upper right, lower right, as SetTexCoord takes them) of
-- coords ({ left, right, top, bottom }; the whole file without) turned clockwise by turns quarter turns, then the
-- picture as drawn mirrored across (flipX) and up and down (flipY). Studio's preview and the plates draw through it.
function Media.PictureCoords(coords, flipX, flipY, turns)
    local left, right, top, bottom = 0, 1, 0, 1
    if coords then left, right, top, bottom = coords[1], coords[2], coords[3], coords[4] end
    local ulx, uly, llx, lly, urx, ury, lrx, lry = left, top, left, bottom, right, top, right, bottom
    for _ = 1, (tonumber(turns) or 0) % 4 do
        ulx, uly, llx, lly, urx, ury, lrx, lry = llx, lly, lrx, lry, ulx, uly, urx, ury
    end
    if flipX then ulx, uly, llx, lly, urx, ury, lrx, lry = urx, ury, lrx, lry, ulx, uly, llx, lly end
    if flipY then ulx, uly, llx, lly, urx, ury, lrx, lry = llx, lly, ulx, uly, lrx, lry, urx, ury end
    return ulx, uly, llx, lly, urx, ury, lrx, lry
end

-- The pictures a source offers in Studio's picker ({ value, label, icon }), in order: kit (PlateSmith's pieces and the
-- modules'), lsm (LibSharedMedia's backgrounds and status bars, while installed) or media (My media). Read only.
local kitChoices
function Media.PictureChoices(source)
    -- The kit's list is kept while no piece is added (PS.RegisterPicture).
    if source == "kit" and kitChoices and kitChoices.count == #KIT then return kitChoices end
    local choices = {}
    if source == "kit" then
        choices.count = #KIT
        kitChoices = choices
        for _, entry in ipairs(KIT) do
            if not entry.hidden then
                choices[#choices + 1] = { value = ICON_PICTURES[entry.id] or ("kit:" .. entry.id), label = entry.label,
                    icon = entry.file, iconCoords = { Media.PictureCoords(entry.coords, false, false, entry.turn) } }
            end
        end
    elseif source == "lsm" then
        local library = SharedMedia()
        for _, kind in ipairs({ "background", "statusbar" }) do
            local ok, list = false, nil
            if library and type(library.List) == "function" then ok, list = pcall(library.List, library, kind) end
            for _, name in ipairs(ok and type(list) == "table" and list or {}) do
                local value = "lsm:" .. kind .. ":" .. tostring(name)
                if Media.IsPicture(value) then
                    choices[#choices + 1] = { value = value, label = string.format(L["%s (%s)"], name, kind) }
                end
            end
        end
    elseif source == "media" then
        local names = {}
        for name in pairs(Media.MyMedia()) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            choices[#choices + 1] = { value = "media:" .. name, label = name, icon = Media.MyMedia()[name] }
        end
    elseif source == "unit" then
        local names = {}
        for name in pairs(Media.UNIT_PICTURES) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local _, sample = Media.Picture("unit:" .. name)
            choices[#choices + 1] = { value = "unit:" .. name, label = Media.UNIT_PICTURES[name].label, icon = sample }
        end
    end
    return choices
end
function Media.HasSharedMedia() return SharedMedia() ~= nil end

-- A module's own picture (docs/MODULES.md), offered with the kit as "kit:<id>": id in the module ID grammar
-- ("<module>.<name>"), definition { label, file (inside Interface\AddOns\), coords, turn, blend, size, slice }.
-- A Blueprint names it; where the module is not installed the part's picture is missing.
local function Coords(value, count)
    if value == nil then return true end
    if type(value) ~= "table" or #value ~= count then return false end
    for index = 1, count do if type(value[index]) ~= "number" then return false end end
    return true
end
function PS.RegisterPicture(...)
    local id, definition = PS._Args(...)
    if not PS.IsModuleId(id, 2) then return false, PS._IdReason("picture", 2) end
    if kitById[id] then return false, "picture is already registered" end
    if type(definition) ~= "table" or type(definition.label) ~= "string" or not Media.MediaPath(definition.file) then
        return false, "picture definition requires a label and a file inside Interface\\AddOns"
    end
    if not Coords(definition.coords, 4) or not Coords(definition.slice, 4) or not Coords(definition.size, 2) then
        return false, "picture coords, slice and size must be lists of numbers"
    end
    local entry = { id = id, label = definition.label, file = Media.MediaPath(definition.file), coords = definition.coords,
        turn = tonumber(definition.turn) and math.floor(definition.turn) % 4 or nil,
        blend = definition.blend == "ADD" and "ADD" or nil, size = definition.size, slice = definition.slice }
    KIT[#KIT + 1] = entry
    kitById[id] = entry
    ICON_PICTURES[id] = "kit:" .. id
    return true
end

-- nil means "use Blizzard's multilingual nameplate font object".
function Media.FontPath(value)
    local entry = fontByKey[value]
    if entry then return entry.path end
    return Fetch("font", value)
end

-- A chosen face drawn through a font family: the face for Latin text and Blizzard's own nameplate faces
-- for the alphabets it lacks (Korean, Chinese, Cyrillic), as Blizzard's family objects do. A face set
-- with SetFont has no such fallback, so a name in another alphabet showed as boxes or blanks.
-- CreateFontFamily makes a permanent global object: one is made per face and outline at FAMILY_HEIGHT
-- (sized with SetTextScale), at most FAMILY_LIMIT.base, and per face, outline and height for text
-- that cannot be scaled (aura countdowns), at most FAMILY_LIMIT.sized, so countdown sizes never use
-- up the names' share. Past a limit, or without the API, callers keep SetFont.
Media.FAMILY_ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }
Media.FAMILY_HEIGHT = 12
local FAMILY_LIMIT = { base = 32, sized = 16 }
local FAMILY_SOURCES = { "SystemFont_Outline", "SystemFont_NamePlate" }
local families = {} -- key -> { object, name }, or false where none could be made
local familyCount, kindCount = 0, { base = 0, sized = 0 }
local blizzardFaces -- alphabet -> { file, height }, from the first family object that answers

-- path, height and flags of a font object or text, readable values only.
function Media.ReadFont(object)
    if type(object) ~= "table" or type(object.GetFont) ~= "function" then return nil end
    local ok, path, height, flags = pcall(object.GetFont, object)
    local IsReadable = PS.Secret.IsReadable
    if not ok or not IsReadable(path) or not IsReadable(height) or not IsReadable(flags) then return nil end
    if type(path) ~= "string" or type(height) ~= "number" then return nil end
    return path, height, type(flags) == "string" and flags or ""
end

-- The alphabet's member of a family object (nil when the object is no family or lacks it).
function Media.FamilyMember(object, alphabet)
    if type(object) ~= "table" or type(object.GetFontObjectForAlphabet) ~= "function" then return nil end
    local ok, member = pcall(object.GetFontObjectForAlphabet, object, alphabet)
    return ok and type(member) == "table" and member or nil
end

local function BlizzardFaces()
    if blizzardFaces then return blizzardFaces end
    for _, name in ipairs(FAMILY_SOURCES) do
        local source, faces, count = rawget(_G, name), {}, 0
        for _, alphabet in ipairs(Media.FAMILY_ALPHABETS) do
            local file, height = Media.ReadFont(Media.FamilyMember(source, alphabet))
            if file then
                faces[alphabet] = { file, height }
                count = count + 1
            end
        end
        if count > 0 then
            blizzardFaces = faces
            return faces
        end
    end
end

-- The family for path and flags at height (default FAMILY_HEIGHT) and its global name, or nil.
function Media.FontFamily(path, flags, height)
    local create = rawget(_G, "CreateFontFamily")
    if type(path) ~= "string" or type(create) ~= "function" then return nil end
    flags = type(flags) == "string" and flags or ""
    height = tonumber(height) or Media.FAMILY_HEIGHT
    local key = path .. "|" .. flags .. "|" .. height
    local family = families[key]
    if family ~= nil then
        if not family then return nil end
        return family[1], family[2]
    end
    local faces = BlizzardFaces()
    local kind = height == Media.FAMILY_HEIGHT and "base" or "sized"
    if not faces or kindCount[kind] >= FAMILY_LIMIT[kind] then return nil end
    local roman = faces.roman
    local members = { { alphabet = "roman", file = path, height = height, flags = flags } }
    for _, alphabet in ipairs(Media.FAMILY_ALPHABETS) do
        local face = faces[alphabet]
        if alphabet ~= "roman" and face then
            -- Blizzard's own size for that alphabet, relative to its Latin one.
            local scale = roman and roman[2] > 0 and face[2] / roman[2] or 1
            members[#members + 1] = { alphabet = alphabet, file = face[1], height = height * scale, flags = flags }
        end
    end
    familyCount, kindCount[kind] = familyCount + 1, kindCount[kind] + 1
    local name = "PlateSmithFontFamily" .. familyCount
    local ok, object = pcall(create, name, members)
    if not ok or type(object) ~= "table" then object = ok and rawget(_G, name) or nil end
    if type(object) ~= "table" then
        families[key] = false
        return nil
    end
    families[key] = { object, name }
    return object, name
end

function Media.FamilyCount() return familyCount end

-- Whether this client can draw through a family at all (the API and Blizzard's alphabet faces).
function Media.FamilyAvailable()
    return type(rawget(_G, "CreateFontFamily")) == "function" and BlizzardFaces() ~= nil
end

-- Sets a text's font object and keeps its colour: the client's SetFontObject gives the text the object's colour
-- too (a family's white), and a font or style sets only face, size and outline, so a colour set before it (the
-- name's friendly green, the guild line's) must stay. The colour is handed straight back, never compared, so a
-- protected one (a class colour from the client's sink) stays as well. A text that already has object from here,
-- with no face of its own set since (plateSmithOwnFace), is left alone: a restyle sets the same object again and
-- again, and plates restyle in bursts. False when the object does not take.
function Media.SetFontObject(fontString, object)
    if fontString.plateSmithFontObject == object and not fontString.plateSmithOwnFace then return true end
    local read, r, g, b, a = false, nil, nil, nil, nil
    if fontString.GetTextColor then read, r, g, b, a = pcall(fontString.GetTextColor, fontString) end
    if not pcall(fontString.SetFontObject, fontString, object) then
        fontString.plateSmithFontObject = nil
        return false
    end
    fontString.plateSmithFontObject = object
    if read and fontString.SetTextColor then pcall(fontString.SetTextColor, fontString, r, g, b, a) end
    return true
end

-- Draws text in path at size through its family (FontFamily), sized with SetTextScale; with exact,
-- through the family made at size itself. False when that cannot be done (no API, no family, or a
-- text whose earlier SetFont face the client keeps over a font object: plateSmithOwnFace), so the
-- caller sets the face with SetFont as before.
function Media.SetFamilyFont(fontString, path, size, flags, exact)
    if type(fontString) ~= "table" or not fontString.SetFontObject or not (exact or fontString.SetTextScale) then
        return false
    end
    local family = Media.FontFamily(path, flags, exact and size or nil)
    if not family or not Media.SetFontObject(fontString, family) then return false end
    if fontString.plateSmithOwnFace then
        local wantPath, wantHeight, wantFlags = Media.ReadFont(family)
        local nowPath, nowHeight, nowFlags = Media.ReadFont(fontString)
        if not wantPath or nowPath ~= wantPath or nowHeight ~= wantHeight or nowFlags ~= wantFlags then return false end
        fontString.plateSmithOwnFace = nil
    end
    if fontString.SetTextScale then fontString:SetTextScale(exact and 1 or size / Media.FAMILY_HEIGHT) end
    return true
end

-- For /ps diagnose: what a text is drawn with. mode "family" (a font object with alphabet members,
-- listed in alphabets), "object" (a font object without them) or "file" (a face set with SetFont).
function Media.FontReport(fontString)
    local report = { file = "unavailable", height = "unavailable", flags = "unavailable" }
    local file, height, flags = Media.ReadFont(fontString)
    if file then report.file, report.height, report.flags = file, height, flags end
    local object
    if type(fontString) == "table" and type(fontString.GetFontObject) == "function" then
        local ok, value = pcall(fontString.GetFontObject, fontString)
        object = ok and type(value) == "table" and value or nil
    end
    local alphabets = PS.Json.Array()
    for _, alphabet in ipairs(Media.FAMILY_ALPHABETS) do
        if Media.FamilyMember(object, alphabet) then alphabets[#alphabets + 1] = alphabet end
    end
    local name
    if object and type(object.GetName) == "function" then
        local ok, value = pcall(object.GetName, object)
        name = ok and PS.Secret.IsReadable(value) and type(value) == "string" and value or nil
    end
    report.object = name or (object and "unnamed") or "none"
    if type(fontString) == "table" and fontString.plateSmithOwnFace or not object then
        report.mode = "file"
    else
        report.mode = #alphabets > 0 and "family" or "object"
    end
    report.alphabets = alphabets
    report.textScale = type(fontString) == "table" and PS.Secret.ReadNumber(fontString, "GetTextScale") or "unavailable"
    return report
end
