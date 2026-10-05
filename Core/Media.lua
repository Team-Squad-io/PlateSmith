local _, PS = ...
local L = PS.L

-- Bar textures and fonts. Built-in choices always exist; when the optional
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

local function SharedChoices(builtIn, kind)
    local choices = {}
    for _, entry in ipairs(builtIn) do choices[#choices + 1] = { value = entry.value, label = entry.label } end
    local library = SharedMedia()
    if library and type(library.List) == "function" then
        local ok, names = pcall(library.List, library, kind)
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                if type(name) == "string" then choices[#choices + 1] = { value = LSM_PREFIX .. name, label = name } end
            end
        end
    end
    return choices
end

function Media.StatusBarChoices() return SharedChoices(statusBars, "statusbar") end
function Media.FontChoices() return SharedChoices(fonts, "font") end

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

-- Draws text in path at size through its family (FontFamily), sized with SetTextScale; with exact,
-- through the family made at size itself. False when that cannot be done (no API, no family, or a
-- text whose earlier SetFont face the client keeps over a font object: plateSmithOwnFace), so the
-- caller sets the face with SetFont as before.
function Media.SetFamilyFont(fontString, path, size, flags, exact)
    if type(fontString) ~= "table" or not fontString.SetFontObject or not (exact or fontString.SetTextScale) then
        return false
    end
    local family = Media.FontFamily(path, flags, exact and size or nil)
    if not family or not pcall(fontString.SetFontObject, fontString, family) then return false end
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
