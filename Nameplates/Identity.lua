-- Readable unit identity, social relationships, classification marks, and plate colour/profile
-- choice.
local _, PS = ...
local L = PS.L
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

-- Elite, rare, rare elite and world boss: Blizzard's nameplate icon (gold dragon, silver dragon,
-- skull), a word, letters for the mark, the suffix {level.smart} adds, the classic dragon (dragon), the Level
-- suffix style's coloured letters (levelSuffix, after the number in levelColour) and the Bar frame style's rings
-- (frame: { colour, px } from the bar out). The icons are client atlases; a client without one shows the word
-- instead. One table for plates, templates and Studio.
local GOLD, SILVER, RED = { 1, 0.78, 0.25 }, { 0.78, 0.86, 1 }, { 1, 0.35, 0.25 }
local CLASSIFICATION_MARKS = {
    elite = { letters = "+", suffix = "+", word = L["Elite"], atlas = "nameplates-icon-elite-gold", colour = GOLD,
        dragon = "gold", levelColour = GOLD, levelSuffix = { { "+", GOLD } }, frame = { { GOLD, 1 } } },
    rare = { letters = "R", suffix = "R", word = L["Rare"], atlas = "nameplates-icon-elite-silver", colour = SILVER,
        dragon = "silver", levelColour = SILVER, levelSuffix = { { "R", SILVER } }, frame = { { SILVER, 1 } } },
    rareelite = { letters = "R+", suffix = "R+", word = L["Rare elite"], atlas = "nameplates-icon-elite-silver",
        colour = GOLD, dragon = "silver", levelColour = SILVER, levelSuffix = { { "R", SILVER }, { "+", GOLD } },
        frame = { { GOLD, 1 }, { SILVER, 1 } } },
    -- A boss's level is "??": Level suffix shows it alone, in red (its letter B is {level.smart}'s only).
    worldboss = { letters = "BOSS", suffix = "B", word = L["Boss"],
        texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", colour = RED, dragon = "gold",
        levelColour = RED, levelSuffix = {}, frame = { { { 0, 0, 0 }, 1 }, { { 0.62, 0.05, 0.04 }, 2 } } },
}
PS.ClassificationMarks = CLASSIFICATION_MARKS

-- The Elite / rare mark's shared route (plates, templates, Studio's preview and the import preview): its one
-- classification reader, the level text each style draws, the icon size, the classic dragon's geometry and the
-- Bar frame's rings.
local Mark = {}
PS.ClassificationMark = Mark

do
    local function Hex(colour)
        return string.format("|cff%02x%02x%02x", math.floor(colour[1] * 255 + 0.5), math.floor(colour[2] * 255 + 0.5),
            math.floor(colour[3] * 255 + 0.5))
    end
    -- The format strings Level suffix writes: the level (%s) and the mark's letters, each in its colour; and the
    -- level alone in the mark's colour (a protected level, which Lua cannot join to anything).
    for _, mark in pairs(CLASSIFICATION_MARKS) do
        local parts, colour = { Hex(mark.levelColour), "%s" }, mark.levelColour
        for _, part in ipairs(mark.levelSuffix) do
            if part[2] ~= colour then
                parts[#parts + 1] = "|r" .. Hex(part[2])
                colour = part[2]
            end
            parts[#parts + 1] = part[1]
        end
        parts[#parts + 1] = "|r"
        mark.levelFormat = table.concat(parts)
        mark.levelColourFormat = Hex(mark.levelColour) .. "%s|r"
    end
end

-- The unit's classification ("elite", "rare", ...), or nil while the client withholds it. One reader for the
-- plates' mark and level, and the templates' {elite}, {rare}, {boss}, {classification} and {level.smart}.
function Mark.Read(unit)
    if type(UnitClassification) ~= "function" then return nil end
    local ok, kind = pcall(UnitClassification, unit)
    if ok and PS.Secret.IsReadable(kind) and type(kind) == "string" then return kind end
    return nil
end

-- The classic client's dragon (Interface\Tooltips\EliteNameplateIcon, the silver RareEliteNameplateIcon: 64 x 32,
-- the dragon in the top-left 37 x 27), drawn at DragonScale(the level's text height) and placed round the level:
-- the level's centre GAP + CURL_X past the health bar's right end, the dragon's curl (CURL_X, CURL_Y from its
-- top-left) on it. LINE: the level's height the dragon is drawn at its own size round (it is 1.25 round 12 pt).
-- A boss shows its skull in the level's place (SKULL: its size to the level's height).
Mark.DRAGON = { gold = "Interface\\Tooltips\\EliteNameplateIcon", silver = "Interface\\Tooltips\\RareEliteNameplateIcon",
    WIDTH = 37, HEIGHT = 27, CURL_X = 11, CURL_Y = 12.5, TEXTURE_WIDTH = 64, TEXTURE_HEIGHT = 32, LINE = 9.6, GAP = 2,
    SKULL = 1.25 }
function Mark.DragonScale(levelHeight)
    return (tonumber(levelHeight) or 12) / Mark.DRAGON.LINE
end

local function HasAtlas(name)
    if not C_Texture or type(C_Texture.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- Shows kind's mark on text or icon in style; false (both hidden) when kind has none, or the style draws it
-- elsewhere (Level suffix on the level, Bar frame round the health bar). The callers size the icon (IconSize,
-- the dragon's). Studio's preview draws its sample through this too.
function Mark.Apply(text, icon, kind, style)
    local mark = CLASSIFICATION_MARKS[kind]
    if not mark or style == "suffix" or style == "frame" then
        text:Hide()
        icon:Hide()
        return false
    end
    if style == "dragon" then
        local D = Mark.DRAGON
        icon:SetTexture(D[mark.dragon])
        -- Half a texel in from the texture's left edge, so its neighbour never bleeds in.
        icon:SetTexCoord(0.5 / D.TEXTURE_WIDTH, D.WIDTH / D.TEXTURE_WIDTH, 0, D.HEIGHT / D.TEXTURE_HEIGHT)
        icon:Show()
        text:Hide()
        return true
    end
    if (style == "icon" or style == "beforeName") and (mark.texture or HasAtlas(mark.atlas)) then
        if mark.texture then
            icon:SetTexture(mark.texture)
            icon:SetTexCoord(0, 1, 0, 1)
        else
            icon:SetAtlas(mark.atlas)
        end
        icon:Show()
        text:Hide()
        return true
    end
    text:SetText(style == "letters" and mark.letters or mark.word)
    text:SetTextColor(mark.colour[1], mark.colour[2], mark.colour[3])
    text:Show()
    icon:Hide()
    return true
end
PS.ApplyClassificationMark = Mark.Apply

-- The style an enemy plate draws its mark in, for its layout (MARK.Layout's; Studio's preview asks the same): the
-- setting; nil while the part is turned off (no mark, no suffix, no frame); Blizzard icons for a Classic dragon the
-- layout could not place (its health bar turned off).
function Mark.StyleFor(settings, layout)
    local position = type(layout) == "table" and layout.classification
    if type(position) ~= "table" or S.TurnedOff(position) then return nil end
    local style = type(settings) == "table" and settings.classificationStyle or "icon"
    if style == "dragon" and not S.MARK.Placed(layout).level then return "icon" end
    return style
end

-- The mark's icon size in plate units (Icon size, classificationIconSize): Standard is 18; Text height the name's
-- drawn text height (its Font size and the text size); Auto is Standard beside the bar and Text height before the
-- name.
Mark.ICON_SIZE = 18
function Mark.IconSize(settings, profile, style)
    local size = type(settings) == "table" and settings.classificationIconSize or "auto"
    if size == "auto" then size = style == "beforeName" and "text" or "standard" end
    if size ~= "text" then return Mark.ICON_SIZE end
    local styles = type(profile) == "table" and profile.styles or nil
    return S.ScaledFontSize(S.StyledFontSize(type(profile) == "table" and tonumber(profile.nameFontSize) or 14,
        styles and styles.name), type(settings) == "table" and settings.textScale or 1)
end

-- A PvP-flagged friendly player's faction icon (FriendlyPvPState's Alliance, Horde or FFA): Blizzard's target frame
-- art, 64 x 64 files with the emblem in their top-left 42 x 42 and nothing else. Drawn whole, the emblem filled about
-- 40% of the icon's box, off its centre: a dot beside the bar. Cropped (COORDS), it fills the box (the plates' mark
-- size, about the name's height). One route for the plates and Studio's preview.
local PvPMark = {
    TEXTURES = {
        Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
        Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
        FFA = "Interface\\TargetingFrame\\UI-PVP-FFA",
    },
    COORDS = { 0, 42 / 64, 0, 42 / 64 },
}
PS.PvPMark = PvPMark

-- Draws state's emblem on icon; false (nothing set) for a state without one.
function PvPMark.Apply(icon, state)
    local texture = PvPMark.TEXTURES[state]
    if not texture then return false end
    local coords = PvPMark.COORDS
    icon:SetTexture(texture)
    icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    return true
end

-- Whether Display (friendlyPvpStyle) colours a PvP-flagged ally: Colour and icon, or Name colour.
function PvPMark.Colours(settings)
    local style = type(settings) == "table" and settings.friendlyPvpStyle
    return style == "colour" or style == "both"
end

-- A colour rule on the health bar that always holds (no condition): the bar's colour is the player's own.
local function BarRuleColoured(profile)
    local list = type(profile) == "table" and type(profile.rules) == "table" and profile.rules.health
    if type(list) ~= "table" then return false end
    for _, rule in ipairs(list) do
        if type(rule) == "table" and rule.enabled ~= false and (rule.set == "colour" or rule.set == "blend")
            and (rule.when == nil or (type(rule.when) == "string" and not rule.when:find("%S"))) then
            return true
        end
    end
    return false
end

-- Where a flagged ally's PvP colour goes (1.3.0): the health bar while the plate shows one (barShown) in the
-- automatic colour, and the name keeps its own; otherwise the name. A bar with a colour of its own keeps it and the
-- name takes the PvP colour instead: Custom colour, a colour rule that always holds (the Healer look's blend), or the
-- class colour the automatic bar is while Colour social relationships is off (the Blizzard look's, as Blizzard's own
-- plates). One answer for the plates (Lifecycle's UpdateIdentity) and Studio's preview.
function PvPMark.ColourOnBar(settings, profile, barShown)
    if not barShown or type(profile) ~= "table" or profile.healthColourMode == "custom" then return false end
    if type(settings) == "table" and settings.friendlyRelationshipColours == false then return false end
    return not BarRuleColoured(profile)
end

-- {level.smart}: the level and the mark's letters as one text ("60+", "60R+"; a hidden level is "??", a world
-- boss "??B"); a level that is not a readable number is passed on as it is.
local function LevelBase(level) return level < 0 and "??" or level end
function Mark.SmartLevel(level, kind)
    if not PS.Secret.IsReadable(level) or type(level) ~= "number" then return level end
    local text = tostring(LevelBase(level))
    local mark = CLASSIFICATION_MARKS[kind]
    return mark and text .. mark.suffix or text
end

-- What a plate's level shows in the mark's style (style: StyleFor's; kind: Read's, nil while withheld) for a
-- readable level: the number as the plates always wrote it, "??" for a level the client hides (-1); Level suffix
-- adds the mark's letters in its colours; the Classic dragon shows a boss's skull in its place (skullSize: px).
function Mark.LevelText(level, kind, style, skullSize)
    local text = LevelBase(level)
    local mark = CLASSIFICATION_MARKS[kind]
    if not mark then return text end
    if style == "suffix" then return string.format(mark.levelFormat, tostring(text)) end
    if style == "dragon" and mark.texture then
        local size = math.max(8, math.floor((tonumber(skullSize) or 15) + 0.5))
        return string.format("|T%s:%d:%d|t", mark.texture, size, size)
    end
    return text
end

-- For a protected level (a display sink shows it; Lua cannot join a suffix to it): the format SetFormattedText
-- draws it with, the level alone in the mark's colour (Level suffix, a readable classification), or nil (plain).
function Mark.ProtectedLevelFormat(kind, style)
    local mark = CLASSIFICATION_MARKS[kind]
    if style == "suffix" and mark then return mark.levelColourFormat end
    return nil
end

-- Whether style shows kind's skull in the level's place (the Classic dragon's boss, LevelText): then the level
-- itself, readable or not, is not shown.
function Mark.SkullForLevel(kind, style)
    local mark = CLASSIFICATION_MARKS[kind]
    return style == "dragon" and mark ~= nil and mark.texture ~= nil
end

-- Bar frame: kind's rings round bar, from its edge out past inset (the bar's own border, px). owner keeps them
-- (owner.markRings: PS.EdgeFrame, plain textures, so a secret bar width cannot break them). Returns how far they
-- reach past inset (0: none).
local function PlaceRing(frame, bar, outer)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", bar, "TOPLEFT", -outer, outer)
    frame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", outer, -outer)
end
Mark.PlaceRing = PlaceRing
function Mark.PaintFrame(owner, bar, kind, inset)
    local mark = CLASSIFICATION_MARKS[kind]
    local rings, frames = mark and mark.frame, owner.markRings
    if not rings and not frames then return 0 end
    if not frames then
        frames = {}
        owner.markRings = frames
    end
    inset = tonumber(inset) or 0
    local outer = inset
    for index = 1, 2 do
        local ring, frame = rings and rings[index], frames[index]
        if ring then
            local colour, width = ring[1], ring[2]
            if not frame then
                frame = PS.EdgeFrame(bar, width)
                frame:SetFrameLevel(bar:GetFrameLevel() + 3)
                if frame.EnableMouse then frame:EnableMouse(false) end
                frames[index] = frame
            end
            outer = outer + width
            PlaceRing(frame, bar, outer)
            if frame.plateSmithEdgeSize ~= width then frame:SetEdgeSize(width) end
            frame:SetBackdropBorderColor(colour[1], colour[2], colour[3], 1)
            frame:Show()
        elseif frame then
            frame:Hide()
        end
    end
    return outer - inset
end

-- A game object's plate (a book, a chest: Secret.IsGameObject) is the Objects plate type's, a names-only plate
-- whose layout (Schema's profileDefaults.object) shows the name and the quest mark. Its name is drawn in Blizzard's
-- game-object gold (NORMAL_FONT_COLOR, the colour of object names in its tooltips) as a creature's is in its reaction
-- colour; rules change it. Studio's preview reads the same colour. FADE: the plate's opacity while Fade objects you
-- can't use fades it (Lifecycle's ObjectFade; Studio's preview with Test values' Can't use yet).
local ObjectPlate = { COLOUR = { 1, 0.82, 0 }, FADE = 0.5 }
PS.ObjectPlate = ObjectPlate

-- A plate's colours from facts. One decision for the plates (the factory's SafeColourForUnit and FriendlyPvPColour,
-- from a unit) and Studio's preview (from Test values), so they agree. read holds the facts' readers, each called only
-- when the decision needs it, with unit (a unit token, or the preview's samples): IsPlayer (true, false or nil), PvP
-- (a truthy state while PvP-flagged), Relationship (group, guild, friend, recent or nil), ClassFile (may be protected:
-- only ClassColour reads it) and Neutral (true for a neutral reaction).
local PlateColours = {}
PS.PlateColours = PlateColours
PlateColours.HOSTILE, PlateColours.NEUTRAL, PlateColours.FRIENDLY = { 0.9, 0.16, 0.16 }, { 1, 0.82, 0 }, { 0.35, 0.75, 1 }

-- A friendly player's PvP colour (relationshipColours.pvp) while Display colours one (PvPMark.Colours) and the unit is
-- flagged, else nil. Whether it goes on the bar or the name is PvPMark.ColourOnBar's.
function PlateColours.PvP(db, read, unit)
    if db and PvPMark.Colours(db) and read.IsPlayer(unit) ~= false and read.PvP(unit) then
        return db.relationshipColours.pvp
    end
    return nil
end

-- The unit's own colour, without PvP (PlateColours.PvP): its name's, and its health bar's unless the design or the PvP
-- colour sets the bar's. An object's gold, a friendly player's social or class colour, a friendly NPC's blue, an
-- enemy's reaction. relationshipKnown: relationship was read already. Returns r, g, b.
function PlateColours.Base(db, read, unit, friendly, object, relationship, relationshipKnown)
    if object then return ObjectPlate.COLOUR[1], ObjectPlate.COLOUR[2], ObjectPlate.COLOUR[3] end
    if friendly then
        if not db or db.friendlyRelationshipColours ~= false then
            if not relationshipKnown then relationship = read.Relationship(unit) end
            local colour = db and db.relationshipColours and db.relationshipColours[relationship]
                or S.defaultRelationshipColours[relationship]
            if colour then return colour.r, colour.g, colour.b end
        end
        local r, g, b = PS.Secret.ClassColour((read.ClassFile(unit)))
        if r then return r, g, b end
        local fallback = PlateColours.FRIENDLY
        return fallback[1], fallback[2], fallback[3]
    end
    local colour = read.Neutral(unit) and PlateColours.NEUTRAL or PlateColours.HOSTILE
    return colour[1], colour[2], colour[3]
end

PS._CreatePlateIdentity = function(context)
    local IsReadable = PS.Secret.IsReadable
    local HasValue = PS.Secret.HasValue
    local ReadBoolean = PS.Secret.ReadBoolean
    local GetSettings = context.GetSettings

    local function ReadUnitPlayerName(unit)
        local callback = type(UnitNameUnmodified) == "function" and UnitNameUnmodified
            or (type(UnitFullName) == "function" and UnitFullName or UnitName)
        if type(callback) ~= "function" then return nil, nil end
        local ok, name, realm = pcall(callback, unit)
        if not ok or not IsReadable(name) or type(name) ~= "string" or name == "" then return nil, nil end
        if IsReadable(realm) and type(realm) == "string" and realm ~= "" then
            return name, name .. "-" .. realm
        end
        return name, name
    end

    -- True or false, or nil while the client withholds it.
    local function IsPlayerUnit(unit)
        if type(UnitIsPlayer) ~= "function" then return false end
        return ReadBoolean(UnitIsPlayer, unit)
    end

    local function ReadUnitName(callback, unit, ...)
        if type(callback) ~= "function" then return nil end
        local ok, name = pcall(callback, unit, ...)
        if not ok or not IsReadable(name) or type(name) ~= "string" or name == "" then return nil end
        return name
    end

    local function ReadUnitNameValue(callback, unit, ...)
        if type(callback) ~= "function" then return nil end
        local ok, name = pcall(callback, unit, ...)
        if not ok or not HasValue(name) then return nil end
        if IsReadable(name) and (type(name) ~= "string" or name == "") then return nil end
        return name
    end

    -- The client build cannot change during a session, so it is read once.
    local foreverClient = false
    if type(GetBuildInfo) == "function" then
        local ok, interface = pcall(function() return select(4, GetBuildInfo()) end)
        foreverClient = ok and type(interface) == "number" and interface >= 16000 and interface < 17000
    end
    local function IsForeverClient() return foreverClient end
    -- Most complete display identity first; built once instead of per plate update.
    local displayNameRequests = {
        { GetUnitName, true },
        { UnitPVPName },
        { UnitNameUnmodified },
        { UnitFullName },
        { UnitName },
    }

    -- The most complete name the client gives, possibly protected (only a display sink shows it).
    -- Forever may protect UnitIsPlayer on transient nameplate tokens while the name stays
    -- readable, so only a readable name of a confirmed player is shortened; NPC names stay whole.
    local function UnitDisplayNameValue(unit)
        local db = GetSettings()
        local ordinary = ReadUnitNameValue(UnitName, unit)
        if not IsForeverClient() then return ordinary end
        for _, request in ipairs(displayNameRequests) do
            local value = ReadUnitNameValue(request[1], unit, request[2])
            if HasValue(value) then
                if db and db.showPlayerSurnames == false and IsReadable(value)
                    and type(value) == "string" and IsPlayerUnit(unit) == true then
                    return value:match("^(%S+)") or value
                end
                return value
            end
        end
        return ordinary
    end

    local function IsRecognizedPlayerName(name, fullName, includeFlags)
        local callback = C_AutoComplete and C_AutoComplete.IsRecognizedName
        if type(callback) ~= "function" or type(includeFlags) ~= "number" then return false end
        local ok, recognized = pcall(callback, fullName or name, includeFlags, 0)
        if ok and IsReadable(recognized) and recognized then return true end
        if fullName ~= name then
            ok, recognized = pcall(callback, name, includeFlags, 0)
            if ok and IsReadable(recognized) and recognized then return true end
        end
        return false
    end

    local function ReadAutoCompleteFlag(key, fallback)
        local flags = Enum and Enum.AutoCompleteEntryFlag
        local value = flags and flags[key]
        return type(value) == "number" and value or fallback
    end

    local function FriendlyRelationship(unit)
        if type(UnitIsPlayer) == "function" and ReadBoolean(UnitIsPlayer, unit) ~= true then return nil end

        if ReadBoolean(UnitInParty, unit) == true or ReadBoolean(UnitInRaid, unit) == true then
            return "group"
        end

        if ReadBoolean(UnitIsInMyGuild, unit) == true then return "guild" end

        local name, fullName = ReadUnitPlayerName(unit)
        if not name then return nil end
        local groupFlag = ReadAutoCompleteFlag("InGroup", 1)
        if IsRecognizedPlayerName(name, fullName, groupFlag) then return "group" end

        if type(UnitGUID) == "function" and C_FriendList and type(C_FriendList.IsFriend) == "function" then
            local guidOK, guid = pcall(UnitGUID, unit)
            if guidOK and IsReadable(guid) and type(guid) == "string" then
                local friendOK, isFriend = pcall(C_FriendList.IsFriend, guid)
                if friendOK and IsReadable(isFriend) and isFriend then return "friend" end
            end
        end

        local friendFlags = ReadAutoCompleteFlag("Friend", 4) + ReadAutoCompleteFlag("Bnet", 8)
        if IsRecognizedPlayerName(name, fullName, friendFlags) then return "friend" end
        if IsRecognizedPlayerName(name, fullName, ReadAutoCompleteFlag("RecentPlayer", 256)) then return "recent" end
        return nil
    end

    local function FriendlyPvPState(unit)
        if type(UnitIsPVPFreeForAll) == "function" then
            local ok, freeForAll = pcall(UnitIsPVPFreeForAll, unit)
            if not ok or not IsReadable(freeForAll) then return nil end
            if freeForAll then return "FFA" end
        end
        if type(UnitIsPVP) ~= "function" then return nil end
        local ok, flagged = pcall(UnitIsPVP, unit)
        if not ok or not IsReadable(flagged) then return nil end
        if not flagged then return false end
        if type(UnitFactionGroup) == "function" then
            local factionOK, faction = pcall(UnitFactionGroup, unit)
            if factionOK and IsReadable(faction) and (faction == "Alliance" or faction == "Horde") then
                return faction
            end
        end
        return "flagged"
    end

    -- The unit's facts for PlateColours. A neutral reaction is UnitReaction 4, read only when it is readable.
    local LIVE_FACTS = {
        IsPlayer = IsPlayerUnit, PvP = FriendlyPvPState, Relationship = FriendlyRelationship,
        ClassFile = PS.Secret.ClassFile,
        Neutral = function(unit)
            local reaction = UnitReaction(unit, "player")
            return IsReadable(reaction) and type(reaction) == "number" and reaction == 4
        end,
    }

    -- A PvP-flagged friendly player's colour while Display colours one, else nil (PlateColours.PvP). Where it goes
    -- is PvPMark.ColourOnBar's.
    local function FriendlyPvPColour(unit)
        return PlateColours.PvP(GetSettings(), LIVE_FACTS, unit)
    end

    -- The unit's own colour, without the PvP colour (FriendlyPvPColour): PlateColours.Base. relationshipKnown:
    -- relationship is FriendlyRelationship(unit), already read by the caller. object: a game object's name.
    local function SafeColourForUnit(unit, friendly, relationship, relationshipKnown, object)
        return PlateColours.Base(GetSettings(), LIVE_FACTS, unit, friendly, object, relationship, relationshipKnown)
    end

    -- The plate type only; which of its designs draws here is PlateContext.DesignFor's answer. One
    -- UnitIsPlayer read: a hostile unit is an enemy player only while the client says so readably
    -- (withheld or secret: an NPC, the Enemies' own design). object: a game object (Secret.IsGameObject, read
    -- first), the Objects plate type.
    local function ProfileKeyForUnit(unit, friendly, object)
        if object then return "object" end
        if not friendly then return IsPlayerUnit(unit) == true and "enemyPlayer" or "enemy" end
        local player = IsPlayerUnit(unit)
        if player == false then return "friendlyNPC" end
        return "friendlyPlayer"
    end

    -- Writes a plate text (name, level) unless the region already shows that readable value, as a
    -- reused frame for the same unit, a level or a social update often does. region.plateSmithText
    -- is the readable value last written; the caller is the region's only writer. A protected value
    -- goes to the sink every time and clears the record. Returns whether the region shows value. The
    -- record is written before the text, so a SetText hook (the soft glow's long name) reads the new one.
    local function SetPlateText(region, value)
        if not IsReadable(value) then
            region.plateSmithText = nil
            return pcall(region.SetText, region, value)
        end
        if value == nil then value = "" end
        if region.plateSmithText == value then return true end
        region.plateSmithText = value
        local ok = pcall(region.SetText, region, value)
        if not ok then region.plateSmithText = nil end
        return ok
    end

    return {
        SetPlateText = SetPlateText,
        ReadUnitName = ReadUnitName,
        UnitDisplayNameValue = UnitDisplayNameValue,
        FriendlyRelationship = FriendlyRelationship,
        FriendlyPvPState = FriendlyPvPState,
        FriendlyPvPColour = FriendlyPvPColour,
        SafeColourForUnit = SafeColourForUnit,
        ProfileKeyForUnit = ProfileKeyForUnit,
    }
end
