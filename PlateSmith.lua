local addonName, PS = ...

PS = PS or {}
_G.PlateSmith = PS

local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local defaults = S.defaults
local defaultLayout = S.defaultLayout
local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT
local valueSources = S.valueSources
local valueAnchors = S.valueAnchors
local valueLayers = S.valueLayers
local missingAnchorModes = S.missingAnchorModes
local DefaultValueSlots = S.DefaultValueSlots
local profileOrder = S.profileOrder
local profileDefaults = S.profileDefaults
local defaultRelationshipColours = S.defaultRelationshipColours
local validModes = S.validModes
local validFriendlyModes = S.validFriendlyModes
local validFriendlyPvpStyles = S.validFriendlyPvpStyles
local validAuraSources = S.validAuraSources
local healthTexturePaths = S.healthTexturePaths
local CopyDefaults = S.CopyDefaults
local NormalizeLayout = S.NormalizeLayout
local NormalizeColour = S.NormalizeColour
local NormalizeProfile = S.NormalizeProfile
local CopyEnemyProfile = S.CopyEnemyProfile
local MigrateSettings = S.MigrateSettings
local NormalizeSettings = S.NormalizeSettings

local externalAddons = {
    "Kui_Nameplates",
    "Plater",
    "TidyPlates",
    "TidyPlates_ThreatPlates",
}

local active = {}
local activeCasts = {}
local spotlightUnit, spotlightUntil
local UpdateValueAnchors
local elapsedFast, elapsedSlow, elapsedAuras = 0, 0, 0
local db
local friendlyNameCVars = {
    "UnitNameFriendlyPlayerName",
    "UnitNameFriendlyPetName",
    "UnitNameFriendlyGuardianName",
    "UnitNameFriendlyMinionName",
    "UnitNameFriendlyTotemName",
}
local restrictedFriendlyNameCVars = {
    "nameplateShowOnlyNameForFriendlyPlayerUnits",
    "nameplateShowOnlyNames",
}

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function IsReadable(value)
    if type(canaccessvalue) == "function" then
        return canaccessvalue(value)
    end
    return not IsSecret(value)
end

local function RegionVisibleState(region)
    if not region or type(region.IsVisible) ~= "function" then return "unavailable" end
    local ok, visible = pcall(region.IsVisible, region)
    if not ok then return "error" end
    if not IsReadable(visible) then return "protected" end
    return visible == true
end

local function HasValue(value)
    if IsSecret(value) then
        return true
    end
    return value ~= nil
end

local function Abbreviate(value)
    if type(value) ~= "number" then return "" end
    local absolute = math.abs(value)
    if absolute >= 1000000 then
        return string.format("%.1fm", value / 1000000)
    elseif absolute >= 1000 then
        return string.format("%.1fk", value / 1000)
    end
    return tostring(value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5))
end

local function FormatThreat(percent, lead)
    local percentText = percent and string.format("%d%%", math.floor(percent + 0.5)) or nil
    local leadText
    if lead then
        leadText = (lead > 0 and "+" or "") .. Abbreviate(lead)
    end
    if percentText and leadText then return percentText .. "  " .. leadText end
    return percentText or leadText or ""
end

local function FormatThreatRecord(info)
    if type(info) ~= "table" then return "" end
    local value = FormatThreat(info.percent, info.lead)
    if value ~= "" then return value end
    local parts = {}
    if type(info.percent) == "number" then
        parts[#parts + 1] = string.format("%d%%", math.floor(info.percent + 0.5))
    end
    if type(info.leadPercent) == "number" then
        parts[#parts + 1] = string.format("L%d%%", math.floor(info.leadPercent + 0.5))
    end
    if type(info.rawThreat) == "number" then
        parts[#parts + 1] = "T" .. Abbreviate(info.rawThreat)
    end
    if #parts > 0 then return table.concat(parts, "  ") end
    if info.selfHolds then return "YOU" end
    return ""
end

local function AbbreviateThreatSinkValue(info)
    local value
    if info.hasOpaqueRawThreat then
        value = info.rawThreatOpaque
    else
        value = info.rawThreat
        if value == nil then return nil, false end
    end
    local formatter = type(AbbreviateNumbers) == "function" and AbbreviateNumbers
        or type(AbbreviateLargeNumbers) == "function" and AbbreviateLargeNumbers or nil
    if formatter then
        local ok, abbreviated = pcall(formatter, value)
        if ok and IsSecret(abbreviated) then return abbreviated, true end
        if ok and IsReadable(abbreviated) and abbreviated ~= nil then return abbreviated, true end
    end
    if not info.hasOpaqueRawThreat and type(value) == "number" then return Abbreviate(value), true end
    return nil, false
end

local function ApplyFallbackThreatText(fontString, info)
    local hasPercent = type(info.percent) == "number" or info.hasOpaquePercent
    local hasLead = type(info.leadPercent) == "number" or info.hasOpaqueLeadPercent
    local percent = info.percent
    local lead = info.leadPercent
    if info.hasOpaquePercent then percent = info.percentOpaque end
    if info.hasOpaqueLeadPercent then lead = info.leadPercentOpaque end
    local raw, hasRaw = AbbreviateThreatSinkValue(info)
    if not hasPercent and not hasLead and not hasRaw then return false end

    local ok
    if hasPercent and hasLead and hasRaw then
        ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%  L%.0f%%  T%s", percent, lead, raw)
    elseif hasPercent and hasLead then
        ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%  L%.0f%%", percent, lead)
    elseif hasPercent and hasRaw then
        ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%  T%s", percent, raw)
    elseif hasLead and hasRaw then
        ok = pcall(fontString.SetFormattedText, fontString, "L%.0f%%  T%s", lead, raw)
    elseif hasPercent then
        ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%", percent)
    elseif hasLead then
        ok = pcall(fontString.SetFormattedText, fontString, "L%.0f%%", lead)
    else
        ok = pcall(fontString.SetFormattedText, fontString, "T%s", raw)
    end
    return ok == true
end

local function ApplyThreatText(fontString, info)
    if not fontString or type(info) ~= "table" then return "empty" end
    local readable = FormatThreat(info.percent, info.lead)
    if readable ~= "" then
        fontString:SetText(readable)
        return "readable"
    end
    if type(fontString.SetFormattedText) == "function" and ApplyFallbackThreatText(fontString, info) then
        return (info.hasOpaquePercent or info.hasOpaqueLeadPercent or info.hasOpaqueRawThreat)
            and "direct-sink" or "fallback"
    end
    fontString:SetText(FormatThreatRecord(info))
    return info.selfHolds and "hold" or "empty"
end

local function ApplyLeadSituation(statusBar, info)
    if not statusBar or type(info) ~= "table" then return "empty" end
    local value = info.leadSituation
    if info.hasOpaqueLeadSituation then value = info.leadSituationOpaque end
    if not info.hasOpaqueLeadSituation and value == nil then
        statusBar:Hide()
        return "empty"
    end
    local ok = pcall(statusBar.SetValue, statusBar, value)
    if not ok then
        statusBar:Hide()
        return "error"
    end
    statusBar:Show()
    return info.hasOpaqueLeadSituation and "direct-sink" or "readable"
end

local function AddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return type(IsAddOnLoaded) == "function" and IsAddOnLoaded(name)
end

local function ExternalProvider()
    for _, name in ipairs(externalAddons) do
        if AddonLoaded(name) then return name end
    end
end

local function OwnsAppearance()
    if db.mode == "own" then return true end
    if db.mode == "overlay" then return false end
    return ExternalProvider() == nil
end

local function FriendlyUnit(unit)
    local friendly = UnitIsFriend("player", unit)
    if not IsReadable(friendly) then return nil end
    return friendly and true or false
end

local function RestrictedFriendly(unit)
    if FriendlyUnit(unit) ~= true then return false end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

local function ReadCVar(name)
    local callback = C_CVar and C_CVar.GetCVar or GetCVar
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function WriteCVar(name, value)
    local callback = C_CVar and C_CVar.SetCVar or SetCVar
    if type(callback) ~= "function" then return false end
    return pcall(callback, name, value)
end

local function RestoreRestrictedFriendlyNameCVar(clearSavedValue)
    local restore = db and type(db.cvarRestore) == "table" and db.cvarRestore.restrictedFriendlyNames
    if type(restore) == "table" and restore.name and restore.value ~= nil then
        WriteCVar(restore.name, restore.value)
    end
    if clearSavedValue and db and type(db.cvarRestore) == "table" then
        db.cvarRestore.restrictedFriendlyNames = nil
        if next(db.cvarRestore) == nil then db.cvarRestore = nil end
    end
end

local function ApplyRestrictedFriendlyNamesOnly(restricted)
    if not restricted or not db.restrictedFriendlyNamesOnly then
        RestoreRestrictedFriendlyNameCVar(false)
        return
    end
    db.cvarRestore = type(db.cvarRestore) == "table" and db.cvarRestore or {}
    local restore = db.cvarRestore.restrictedFriendlyNames
    if type(restore) ~= "table" then
        for _, name in ipairs(restrictedFriendlyNameCVars) do
            local value = ReadCVar(name)
            if value ~= nil then
                restore = { name = name, value = value }
                db.cvarRestore.restrictedFriendlyNames = restore
                break
            end
        end
    end
    if restore and restore.name then WriteCVar(restore.name, "1") end
end

local function ApplyRestrictedFriendlyClassColour(restricted)
    local key = "restrictedFriendlyClassColour"
    local cvar = "nameplateShowFriendlyClassColor"
    local restore = (db and type(db.cvarRestore) == "table" and db.cvarRestore[key]) or nil
    if not restricted or not db[key] then
        if restore ~= nil then WriteCVar(cvar, restore) end
        if db and type(db.cvarRestore) == "table" then db.cvarRestore[key] = nil end
        return
    end
    local current = ReadCVar(cvar)
    if current == nil then return end
    db.cvarRestore = type(db.cvarRestore) == "table" and db.cvarRestore or {}
    if db.cvarRestore[key] == nil then db.cvarRestore[key] = current end
    WriteCVar(cvar, "1")
end

local function RestoreFriendlyNameCVars(clearSavedValues)
    local restore = db and type(db.cvarRestore) == "table" and db.cvarRestore.friendlyNames
    if type(restore) == "table" then
        for _, name in ipairs(friendlyNameCVars) do
            if restore[name] ~= nil then WriteCVar(name, restore[name]) end
        end
    end
    if clearSavedValues and db and type(db.cvarRestore) == "table" then
        db.cvarRestore.friendlyNames = nil
        if next(db.cvarRestore) == nil then db.cvarRestore = nil end
    end
end

local function ApplyFriendlyNamePolicy()
    if not db then return end
    local inInstance, instanceType = IsInInstance()
    local restricted = inInstance and (instanceType == "party" or instanceType == "raid")
    if not db.hideUnstyledFriendlyNames or restricted then
        RestoreFriendlyNameCVars(false)
        ApplyRestrictedFriendlyNamesOnly(restricted)
        ApplyRestrictedFriendlyClassColour(restricted)
        return
    end

    RestoreRestrictedFriendlyNameCVar(false)
    ApplyRestrictedFriendlyClassColour(false)

    db.cvarRestore = type(db.cvarRestore) == "table" and db.cvarRestore or {}
    local restore = db.cvarRestore.friendlyNames
    if type(restore) ~= "table" then
        restore = {}
        db.cvarRestore.friendlyNames = restore
    end
    for _, name in ipairs(friendlyNameCVars) do
        if restore[name] == nil then restore[name] = ReadCVar(name) end
        WriteCVar(name, "0")
    end
end

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

local function IsPlayerUnit(unit)
    if type(UnitIsPlayer) ~= "function" then return false end
    local ok, player = pcall(UnitIsPlayer, unit)
    if not ok or not IsReadable(player) then return nil end
    return player and true or false
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

local function IsForeverClient()
    if type(GetBuildInfo) ~= "function" then return false end
    local ok, interface = pcall(function() return select(4, GetBuildInfo()) end)
    return ok and type(interface) == "number" and interface >= 16000 and interface < 17000
end

local function PlayerDisplayName(unit)
    local ordinary = ReadUnitName(UnitName, unit) or ""
    if not IsForeverClient() then return ordinary end

    local identity = ReadUnitName(GetUnitName, unit, true)
        or ReadUnitName(UnitPVPName, unit)
        or ReadUnitName(UnitNameUnmodified, unit)
        or ReadUnitName(UnitFullName, unit)
        or ordinary
    if identity == "" then return ordinary end

    -- Forever may protect UnitIsPlayer on transient nameplate tokens even when
    -- the complete display identity remains readable. Showing the unmodified
    -- name does not require classifying the unit first, and also preserves
    -- multi-word NPC names. Only shorten identities we can confirm are players.
    if db and db.showPlayerSurnames == false and IsPlayerUnit(unit) then
        return identity:match("^(%S+)") or identity
    end
    return identity
end

local function UnitDisplayNameValue(unit)
    local ordinary = ReadUnitNameValue(UnitName, unit)
    if not IsForeverClient() then return ordinary end
    for _, request in ipairs({
        { GetUnitName, true },
        { UnitPVPName },
        { UnitNameUnmodified },
        { UnitFullName },
        { UnitName },
    }) do
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

local function UnitMatchesRelationship(callback, unit)
    if type(callback) ~= "function" then return false end
    local ok, matched = pcall(callback, unit)
    return ok and IsReadable(matched) and matched and true or false
end

local function FriendlyRelationship(unit)
    if type(UnitIsPlayer) == "function" then
        local ok, isPlayer = pcall(UnitIsPlayer, unit)
        if not ok or not IsReadable(isPlayer) or not isPlayer then return nil end
    end

    if UnitMatchesRelationship(UnitInParty, unit) or UnitMatchesRelationship(UnitInRaid, unit) then
        return "group"
    end

    if UnitMatchesRelationship(UnitIsInMyGuild, unit) then return "guild" end

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

local function SafeColourForUnit(unit, friendly)
    if friendly then
        if db and (db.friendlyPvpStyle == "colour" or db.friendlyPvpStyle == "both")
            and IsPlayerUnit(unit) ~= false and FriendlyPvPState(unit) then
            local colour = db.relationshipColours.pvp
            return colour.r, colour.g, colour.b
        end
        if not db or db.friendlyRelationshipColours ~= false then
            local relationship = FriendlyRelationship(unit)
            local colour = db and db.relationshipColours and db.relationshipColours[relationship]
                or defaultRelationshipColours[relationship]
            if colour then return colour.r, colour.g, colour.b end
        end
        local _, class = UnitClass(unit)
        if IsReadable(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
            local colour = RAID_CLASS_COLORS[class]
            return colour.r, colour.g, colour.b
        end
        return 0.35, 0.75, 1
    end

    local reaction = UnitReaction(unit, "player")
    if IsReadable(reaction) and type(reaction) == "number" and reaction == 4 then
        return 1, 0.82, 0
    end
    return 0.9, 0.16, 0.16
end

local function ProfileKeyForUnit(unit, friendly)
    if not friendly then
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "party" or instanceType == "raid")
            and db and db.plateProfiles and db.plateProfiles.enemyDungeon then
            return "enemyDungeon"
        end
        return "enemy"
    end
    local player = IsPlayerUnit(unit)
    if player == false then return "friendlyNPC" end
    return "friendlyPlayer"
end

local function HideNative(data)
    local native = data.root and data.root.UnitFrame
    if not native or not native.SetAlpha then return end
    if data.nativeAlpha == nil and native.GetAlpha then
        data.nativeAlpha = native:GetAlpha()
    end
    if not data.nativeHideHooked and native.HookScript then
        native:HookScript("OnShow", function(frame)
            if data.hideNative and frame.SetAlpha then frame:SetAlpha(0) end
        end)
        data.nativeHideHooked = true
    end
    data.hideNative = true
    native:SetAlpha(0)
end

local function RestoreNative(data)
    local native = data.root and data.root.UnitFrame
    data.hideNative = false
    if native and native.SetAlpha and data.nativeAlpha ~= nil then
        native:SetAlpha(data.nativeAlpha)
    end
end

local function CreateBorder(parent)
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0.05, 0.05, 0.05, 1)
    return border
end

local function CreateTargetBarGlow(bar)
    -- Keep both layers attached to the bar itself, never to the whole plate canvas.
    local steady = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    steady:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    steady:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    steady:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    steady:SetBackdropBorderColor(1, 0.72, 0.16, 0.65)
    steady:EnableMouse(false)
    steady:Hide()

    local pulse = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    pulse:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 3)
    pulse:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 3, -3)
    pulse:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    pulse:SetBackdropBorderColor(1, 0.68, 0.1, 0.55)
    pulse:EnableMouse(false)
    pulse:Hide()
    return { steady = steady, pulse = pulse }
end

local function CaptureTextShadow(region)
    if not region.GetShadowColor or not region.GetShadowOffset then return nil end
    local red, green, blue, alpha = region:GetShadowColor()
    local x, y = region:GetShadowOffset()
    return { red, green, blue, alpha, x, y }
end

local function ApplyNameplateFont(fontString, size)
    if not fontString then return end
    size = tonumber(size) or 12
    local fontFamily = _G.SystemFont_Outline or _G.SystemFont_NamePlate
    if fontFamily and fontString.SetFontObject then
        fontString:SetFontObject(fontFamily)
        if fontString.SetTextScale then
            fontString:SetTextScale(size / 13)
        elseif fontString.SetFontHeight then
            fontString:SetFontHeight(size)
        end
        return
    end
    if fontString.SetFont then fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
end

local AURA_ICON_COUNT = 4
local AURA_ICON_SIZE = 18

local function CreateAuraRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize((AURA_ICON_COUNT * AURA_ICON_SIZE) + ((AURA_ICON_COUNT - 1) * 2), AURA_ICON_SIZE)
    local icons = {}
    for index = 1, AURA_ICON_COUNT do
        local icon = row:CreateTexture(nil, "OVERLAY")
        icon:SetSize(AURA_ICON_SIZE, AURA_ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", (index - 1) * (AURA_ICON_SIZE + 2), 0)
        icon:Hide()
        icons[index] = icon
    end
    row:Hide()
    return row, icons
end

local function CreatePlate(root)
    local overlay = CreateFrame("Frame", nil, root)
    overlay:SetSize(128, 52)
    overlay:SetPoint("CENTER", root, "CENTER", 0, 0)
    overlay:SetFrameLevel((root:GetFrameLevel() or 0) + 20)

    local health = CreateFrame("StatusBar", nil, overlay)
    health:SetSize(112, 10)
    health:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    health:SetMinMaxValues(0, 1)
    health:SetValue(1)
    local healthBackground = health:CreateTexture(nil, "BACKGROUND")
    healthBackground:SetAllPoints()
    healthBackground:SetColorTexture(0.025, 0.025, 0.025, 0.92)
    local healthBorder = CreateBorder(health)

    local power = CreateFrame("StatusBar", nil, overlay)
    power:SetSize(112, 5)
    power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    power:SetStatusBarColor(0.18, 0.48, 1)
    power:SetMinMaxValues(0, 1)
    power:SetValue(1)
    local powerBackground = power:CreateTexture(nil, "BACKGROUND")
    powerBackground:SetAllPoints()
    powerBackground:SetColorTexture(0.025, 0.025, 0.025, 0.92)
    CreateBorder(power)
    power:Hide()

    local values, valueHolders = {}, {}
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local holder = CreateFrame("Frame", nil, root)
        holder:SetAllPoints(overlay)
        local value = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("CENTER", health, "CENTER")
        value:SetJustifyH("CENTER")
        ApplyNameplateFont(value, 9)
        value:Hide()
        values[key] = value
        valueHolders[key] = holder
    end

    local name = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("BOTTOM", health, "TOP", 0, 3)
    ApplyNameplateFont(name, 12)
    name:SetJustifyH("CENTER")
    local level = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    level:SetPoint("RIGHT", health, "LEFT", -4, 0)
    ApplyNameplateFont(level, 10)

    local guild = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guild:SetPoint("TOP", name, "BOTTOM", 0, -3)
    ApplyNameplateFont(guild, 10)
    guild:SetTextColor(0.68, 0.85, 0.76)
    guild:Hide()

    local threat = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    threat:SetPoint("TOP", health, "BOTTOM", 0, -3)
    ApplyNameplateFont(threat, 10)

    local threatLead = CreateFrame("StatusBar", nil, overlay)
    threatLead:SetSize(42, 2)
    threatLead:SetPoint("TOP", threat, "BOTTOM", 0, -1)
    threatLead:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    threatLead:SetStatusBarColor(1, 0.18, 0.12, 0.9)
    threatLead:SetMinMaxValues(0, 3)
    threatLead:SetValue(0)
    local threatLeadBackground = threatLead:CreateTexture(nil, "BACKGROUND")
    threatLeadBackground:SetAllPoints()
    threatLeadBackground:SetColorTexture(0.16, 0.16, 0.16, 0.72)
    threatLead:Hide()

    local tagged = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tagged:SetPoint("TOP", health, "BOTTOM", 0, -3)
    tagged:SetText("TAGGED")
    tagged:SetTextColor(0.72, 0.72, 0.72)
    ApplyNameplateFont(tagged, 9)
    tagged:Hide()

    local quest = overlay:CreateTexture(nil, "OVERLAY")
    quest:SetSize(16, 16)
    quest:SetPoint("RIGHT", name, "LEFT", -3, 0)
    quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    quest:SetBlendMode("BLEND")
    quest:Hide()

    local questLoot = overlay:CreateTexture(nil, "OVERLAY")
    questLoot:SetAllPoints(quest)
    questLoot:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    questLoot:SetMask("Interface\\AddOns\\PlateSmith\\Media\\QuestLootMask.png")
    questLoot:Hide()

    local raidIcon = overlay:CreateTexture(nil, "OVERLAY")
    raidIcon:SetSize(18, 18)
    raidIcon:SetPoint("LEFT", name, "RIGHT", 3, 0)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:Hide()

    local relationshipIcon = overlay:CreateTexture(nil, "OVERLAY")
    relationshipIcon:SetSize(16, 16)
    relationshipIcon:SetPoint("BOTTOM", name, "TOP", 0, 3)
    relationshipIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
    relationshipIcon:Hide()

    local pvpIcon = overlay:CreateTexture(nil, "OVERLAY")
    pvpIcon:SetSize(18, 18)
    pvpIcon:SetPoint("LEFT", name, "RIGHT", 4, 0)
    pvpIcon:Hide()

    local classification = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classification:SetPoint("RIGHT", level, "LEFT", -3, 0)
    ApplyNameplateFont(classification, 11)
    classification:Hide()

    -- Decorative only: these follow each visible bar, not the full plate canvas.
    local healthGlow = CreateTargetBarGlow(health)
    local powerGlow = CreateTargetBarGlow(power)

    local beacon = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    beacon:SetAllPoints(overlay)
    beacon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    beacon:SetBackdropBorderColor(0.2, 0.78, 1, 1)
    local beaconLeft = beacon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    beaconLeft:SetPoint("RIGHT", beacon, "LEFT", -3, 0)
    beaconLeft:SetText(">>")
    beaconLeft:SetTextColor(1, 0.83, 0.22)
    local beaconRight = beacon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    beaconRight:SetPoint("LEFT", beacon, "RIGHT", 3, 0)
    beaconRight:SetText("<<")
    beaconRight:SetTextColor(1, 0.83, 0.22)
    beacon:Hide()

    local cast = CreateFrame("StatusBar", nil, overlay)
    cast:SetSize(112, 7)
    cast:SetPoint("TOP", health, "BOTTOM", 0, -3)
    cast:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    cast:SetStatusBarColor(0.95, 0.68, 0.16)
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(0)
    local castBackground = cast:CreateTexture(nil, "BACKGROUND")
    castBackground:SetAllPoints()
    castBackground:SetColorTexture(0.025, 0.025, 0.025, 0.92)
    CreateBorder(cast)
    local castName = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castName:SetPoint("CENTER")
    ApplyNameplateFont(castName, 8)
    cast:Hide()
    local castGlow = CreateTargetBarGlow(cast)

    local buffs, buffIcons = CreateAuraRow(overlay)
    local debuffs, debuffIcons = CreateAuraRow(overlay)
    local targetGlowTexts = { name, level, guild, threat, tagged, classification, castName }
    local targetShadowDefaults = {}
    for _, region in ipairs(targetGlowTexts) do
        targetShadowDefaults[region] = CaptureTextShadow(region)
    end
    for _, region in pairs(values) do
        targetShadowDefaults[region] = CaptureTextShadow(region)
    end

    return {
        root = root,
        overlay = overlay,
        health = health,
        healthBorder = healthBorder,
        power = power,
        values = values,
        valueHolders = valueHolders,
        name = name,
        level = level,
        guild = guild,
        threat = threat,
        threatLead = threatLead,
        tagged = tagged,
        quest = quest,
        questLoot = questLoot,
        raidIcon = raidIcon,
        relationshipIcon = relationshipIcon,
        pvpIcon = pvpIcon,
        classification = classification,
        targetBorder = healthGlow.steady,
        targetHalo = healthGlow.pulse,
        targetBarGlows = { healthGlow, powerGlow, castGlow },
        targetGlowTexts = targetGlowTexts,
        targetShadowDefaults = targetShadowDefaults,
        beacon = beacon,
        beaconLeft = beaconLeft,
        beaconRight = beaconRight,
        cast = cast,
        castName = castName,
        buffs = buffs,
        buffIcons = buffIcons,
        debuffs = debuffs,
        debuffIcons = debuffIcons,
    }
end

local function QuestRelevance(unit)
    if C_QuestLog and type(C_QuestLog.UnitIsRelatedToActiveQuest) == "function" then
        local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and IsReadable(related) and related then return true, "native", "active quest" end
    end
    if type(UnitIsQuestBoss) == "function" then
        local ok, boss = pcall(UnitIsQuestBoss, unit)
        if ok and IsReadable(boss) and boss then return true, "native-boss", "quest boss" end
    end
    if type(PS.IterateQuestProviders) == "function" then
        for id, provider in PS:IterateQuestProviders() do
            if not provider._plateSmithQuestFailed then
                local ok, related, kind, detail = pcall(provider.GetUnitRelevance, provider, unit)
                if not ok then
                    provider._plateSmithQuestFailed = tostring(related)
                    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
                    if handler then handler("PlateSmith quest provider " .. id .. ": " .. tostring(related)) end
                elseif IsReadable(related) and related == true then
                    kind = IsReadable(kind) and type(kind) == "string" and kind or id
                    detail = IsReadable(detail) and type(detail) == "string" and detail or nil
                    return true, kind, detail
                end
            end
        end
    end
    return false, "none", nil
end

local function QuestRelated(unit)
    return QuestRelevance(unit)
end

local function ThreatRecord(unit, refresh)
    local service = PS.ThreatService
    if not service then return nil end
    if refresh and type(service.RefreshUnit) == "function" then
        return service:RefreshUnit(unit)
    end
    if type(service.GetEnemy) == "function" then return service:GetEnemy(unit) end
end

local function ThreatColour(info)
    if info.tanking or info.selfHolds then return 0.25, 1, 0.3 end
    if info.lead and info.lead < 0 then return 1, 0.2, 0.15 end
    if info.percent and info.percent >= 80 then return 1, 0.62, 0.1 end
    return 1, 0.9, 0.35
end

local function ApplyCastInfo(data, channel)
    local api = channel and UnitChannelInfo or UnitCastingInfo
    if type(api) ~= "function" then return false end
    local ok, name, _, _, startMS, endMS = pcall(api, data.unit)
    if not ok or not HasValue(name) then return false end

    local secretTimes = IsSecret(startMS) or IsSecret(endMS)
    if not secretTimes and (type(startMS) ~= "number" or type(endMS) ~= "number") then
        return false
    end

    data.cast:SetMinMaxValues(startMS, endMS)
    data.cast:SetValue(GetTime() * 1000)
    data.cast:SetReverseFill(channel and true or false)
    data.castName:SetText(name)
    data.cast:Show()
    data.casting = true
    activeCasts[data] = true
    return true
end

local function HideCast(data)
    data.cast:Hide()
    data.casting = false
    activeCasts[data] = nil
end

local function UpdateCast(data)
    if data.namesOnly or not data.own or data.layout.cast.visible == false
        or (data.restrictedFriendly and not data.restrictedOverlayEnabled) then
        HideCast(data)
        if UpdateValueAnchors then UpdateValueAnchors(data) end
        return
    end
    if ApplyCastInfo(data, false) or ApplyCastInfo(data, true) then
        if UpdateValueAnchors then UpdateValueAnchors(data) end
        return
    end
    HideCast(data)
    if UpdateValueAnchors then UpdateValueAnchors(data) end
end

local function PopulateAuraIconsByIndex(api, unit, filter, icons)
    if type(api) ~= "function" then return 0, "missing" end
    local shown = 0
    for index = 1, AURA_ICON_COUNT do
        local ok, aura = pcall(api, unit, index, filter)
        if not ok then return shown, "error" end
        if not IsReadable(aura) then return shown, "protected" end
        if aura == nil then break end
        -- The client performs the source filter. Never inspect sourceUnit: it
        -- can be protected in combat even when the icon is displayable.
        local iconOK, icon = pcall(function() return aura.icon end)
        if not iconOK then return shown, "icon-error" end
        if not HasValue(icon) then break end
        if not pcall(icons[index].SetTexture, icons[index], icon) then return shown, "texture-error" end
        icons[index]:Show()
        shown = index
    end
    return shown, shown > 0 and "shown" or "none"
end

local function PopulateAuraIconsBySlots(unit, filter, icons)
    local iterate = AuraUtil and AuraUtil.ForEachAura
    if type(iterate) ~= "function" then return 0, "missing" end
    local shown = 0
    local ok = pcall(iterate, unit, filter, AURA_ICON_COUNT, function(_, icon)
        if HasValue(icon) and pcall(icons[shown + 1].SetTexture, icons[shown + 1], icon) then
            shown = shown + 1
            icons[shown]:Show()
        end
        return shown >= AURA_ICON_COUNT
    end)
    return shown, not ok and "error" or shown > 0 and "shown" or "none"
end

local function PopulateAuraIconsLegacy(kind, unit, filter, icons)
    local api = kind == "buffs" and UnitBuff or UnitDebuff
    if type(api) ~= "function" then return 0, "missing" end
    -- UnitBuff/UnitDebuff already imply HELPFUL/HARMFUL; their optional filter
    -- only needs the source restriction.
    local legacyFilter = filter:find("|PLAYER", 1, true) and "PLAYER" or nil
    local shown = 0
    for index = 1, AURA_ICON_COUNT do
        local ok, name, icon = pcall(api, unit, index, legacyFilter)
        if not ok then return shown, "error" end
        if not HasValue(name) then break end
        if not HasValue(icon) then break end
        if not pcall(icons[index].SetTexture, icons[index], icon) then return shown, "texture-error" end
        icons[index]:Show()
        shown = index
    end
    return shown, shown > 0 and "shown" or "none"
end

local function PopulateAuraIcons(kind, unit, filter, icons)
    local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local shown, indexState = PopulateAuraIconsByIndex(api, unit, filter, icons)
    if shown > 0 then return shown, "indexed" end
    -- A readable empty result or protected value is authoritative. Try other
    -- API shapes only when this API itself is missing or raises an error.
    if indexState ~= "error" and indexState ~= "missing" then
        return 0, "indexed-" .. indexState
    end
    local slotState
    shown, slotState = PopulateAuraIconsBySlots(unit, filter, icons)
    if shown > 0 then return shown, "slots" end
    local legacyState
    shown, legacyState = PopulateAuraIconsLegacy(kind, unit, filter, icons)
    if shown > 0 then return shown, "legacy" end
    return 0, "none:index=" .. indexState .. ",slots=" .. slotState .. ",legacy=" .. legacyState
end

local function ConfigureNativeAuraContainer(data, kind, filter)
    local row = data[kind]
    local container = row.nativeAuraContainer
    if not container then
        if row.nativeAuraAttempted then return false end
        row.nativeAuraAttempted = true
        local created, result = pcall(CreateFrame, "AuraContainer", nil, row, "CustomAuraContainerTemplate")
        if not created or not result or type(result.AddAuraGroup) ~= "function" then
            row.nativeAuraState = "create-error"
            row.nativeAuraError = created and "AddAuraGroup unavailable" or tostring(result):sub(1, 160)
            return false
        end
        container = result
        local configured, failure = pcall(function()
            container:SetEnabled(false)
            container:SetSize(row:GetWidth(), row:GetHeight())
            container:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            if container.SetIgnoreParentScale then container:SetIgnoreParentScale(false) end
            if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint("TOPLEFT") end
            if container.SetFlowLayoutGrowthDirection then container:SetFlowLayoutGrowthDirection(1, -1) end
            if container.SetFlowLayoutMaximumLineSize then
                container:SetFlowLayoutMaximumLineSize(row:GetWidth())
            end
            container:AddAuraGroup("platesmith", filter, {
                maxFrameCount = AURA_ICON_COUNT,
                layout = { elementSpacing = 2, elementWidth = AURA_ICON_SIZE,
                    elementHeight = AURA_ICON_SIZE },
                initializeFrame = function(button)
                    button:SetSize(AURA_ICON_SIZE, AURA_ICON_SIZE)
                    local icon = button:CreateTexture(nil, "ARTWORK")
                    icon:SetAllPoints(button)
                    button:SetIcon(icon)
                end,
            })
            container:SetUnit(data.unit)
            container:SetEnabled(true)
            container:Show()
        end)
        if not configured then
            pcall(container.SetEnabled, container, false)
            pcall(container.Hide, container)
            row.nativeAuraState = "configure-error"
            row.nativeAuraError = tostring(failure):sub(1, 160)
            return false
        end
        row.nativeAuraContainer = container
        row.nativeAuraFilter = filter
    else
        local configured, failure = pcall(function()
            container:SetUnit(data.unit)
            if row.nativeAuraFilter ~= filter then
                container:SetAuraGroupFilterString("platesmith", filter)
                row.nativeAuraFilter = filter
            end
            container:SetEnabled(true)
            container:Show()
        end)
        if not configured then
            pcall(container.SetEnabled, container, false)
            pcall(container.Hide, container)
            row.nativeAuraState = "update-error"
            row.nativeAuraError = tostring(failure):sub(1, 160)
            return false
        end
    end
    row.nativeAuraState = "ready"
    row.nativeAuraError = nil
    return true
end

local function UpdateAuraRow(data, kind)
    local row = data[kind]
    local icons = data[kind == "buffs" and "buffIcons" or "debuffIcons"]
    local enabled = db.showDebuffs
    if kind == "buffs" then enabled = db.showBuffs end
    if not data.own or not enabled or data.layout[kind].visible == false
        or not data.overlay:IsShown() then
        data[kind .. "AuraRoute"] = "disabled"
        if row.nativeAuraContainer then pcall(row.nativeAuraContainer.SetEnabled, row.nativeAuraContainer, false) end
        row:Hide()
        return
    end
    local source = kind == "buffs" and db.buffSource or db.debuffSource
    local filter = (kind == "buffs" and "HELPFUL" or "HARMFUL")
        .. (source == "mine" and "|PLAYER" or "")
    local nativeAttempted = row.nativeAuraContainer ~= nil
    -- The native aura widget only lays out while its parent is visible.
    row:Show()
    if nativeAttempted and ConfigureNativeAuraContainer(data, kind, filter) then
        for index = 1, AURA_ICON_COUNT do icons[index]:Hide() end
        data[kind .. "AuraRoute"] = "native-container"
        row:Show()
        return
    end
    -- A confirmed target token can expose auras that the dungeon nameplate
    -- token does not. Never borrow it for an unconfirmed or changed target.
    local auraUnit = data.unit
    if type(UnitIsUnit) == "function" then
        local ok, same = pcall(UnitIsUnit, data.unit, "target")
        if ok and IsReadable(same) and same == true then auraUnit = "target" end
    end
    local shown, route = PopulateAuraIcons(kind, auraUnit, filter, icons)
    if auraUnit == "target" then
        local ok, same = pcall(UnitIsUnit, data.unit, "target")
        if not ok or not IsReadable(same) or same ~= true then
            shown = 0
            route = "target-changed"
        elseif shown == 0 then
            shown, route = PopulateAuraIcons(kind, data.unit, filter, icons)
        end
    end
    if shown == 0 and not nativeAttempted and route:find("index=error", 1, true)
        and ConfigureNativeAuraContainer(data, kind, filter) then
        for index = 1, AURA_ICON_COUNT do icons[index]:Hide() end
        data[kind .. "AuraRoute"] = "native-container"
        row:Show()
        return
    end
    if shown == 0 and row.nativeAuraState and row.nativeAuraState ~= "ready" then
        route = route .. ",container=" .. row.nativeAuraState
    end
    data[kind .. "AuraRoute"] = route
    for index = shown + 1, AURA_ICON_COUNT do icons[index]:Hide() end
    row:SetShown(shown > 0)
end

local function UpdateAuras(data)
    UpdateAuraRow(data, "buffs")
    UpdateAuraRow(data, "debuffs")
end

local function UpdateQuest(data)
    local related, source, detail = QuestRelevance(data.unit)
    data.questSource = source
    data.questDetail = detail
    local itemDrop = source == "questiedb-item-drop"
    local shown = db.quest and data.layout.quest.visible ~= false and related
    data.quest:SetShown(shown and not itemDrop)
    data.questLoot:SetShown(shown and itemDrop)
end

local function ReadRaidTargetIndex(unit)
    if type(GetRaidTargetIndex) ~= "function" then return nil, "api-missing" end
    local ok, index = pcall(GetRaidTargetIndex, unit)
    if not ok then return nil, "error" end
    if not IsReadable(index) then return nil, "secret" end
    if index == nil or index == 0 then return nil, "none" end
    if type(index) ~= "number" or index < 1 or index > 8 then return nil, "invalid-" .. type(index) end
    return index, "readable"
end

local function NamePlateRootForUnit(unit)
    local callback = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(callback) ~= "function" then return nil, "api-missing" end
    local ok, root = pcall(callback, unit)
    if not ok then return nil, "error" end
    if not IsReadable(root) then return nil, "secret" end
    return root, root and "readable" or "none"
end

local function StableRaidTargetUnits()
    local candidates = { "target", "focus", "mouseover" }
    for number = 1, 5 do candidates[#candidates + 1] = "boss" .. number end
    local countOK, groupCount = pcall(type(GetNumGroupMembers) == "function" and GetNumGroupMembers or function() return 0 end)
    if not countOK then groupCount = 0 end
    groupCount = IsReadable(groupCount) and type(groupCount) == "number" and math.min(40, groupCount) or 0
    local raidOK, raid = pcall(type(IsInRaid) == "function" and IsInRaid or function() return false end)
    local prefix = raidOK and IsReadable(raid) and raid and "raid" or "party"
    local maximum = prefix == "raid" and groupCount or math.min(4, groupCount)
    for number = 1, maximum do candidates[#candidates + 1] = prefix .. number .. "target" end
    return candidates
end

local function ResolveRaidTargetIndex(data)
    local index, state = ReadRaidTargetIndex(data.unit)
    if index then return index, data.unit, "direct" end

    local candidates = StableRaidTargetUnits()
    for candidateIndex = 1, #candidates do
        local candidate = candidates[candidateIndex]
        local matched = false
        local candidateRoot = NamePlateRootForUnit(candidate)
        if candidateRoot and candidateRoot == data.root then
            matched = true
        elseif type(UnitIsUnit) == "function" then
            local ok, same = pcall(UnitIsUnit, data.unit, candidate)
            matched = ok and IsReadable(same) and same and true or false
        end
        if matched then
            index = ReadRaidTargetIndex(candidate)
            if index then return index, candidate, candidateRoot == data.root and "root" or "identity" end
        end
    end
    return nil, data.unit, state
end

-- Midnight/Forever can protect the numeric marker while still permitting it to
-- flow directly into Blizzard's texture sink. Do not compare it, calculate with
-- it, or use it as a table key on this path.
local function RenderProtectedRaidTarget(data)
    if type(GetRaidTargetIndex) ~= "function" or type(SetRaidTargetIconTexture) ~= "function" then
        return false, "sink-unavailable"
    end
    local ok, shown = pcall(function()
        local index = GetRaidTargetIndex(data.unit)
        if index then
            SetRaidTargetIconTexture(data.raidIcon, index)
            return true
        end
        return false
    end)
    if not ok then return false, "sink-error" end
    return shown and true or false, shown and "direct-sink" or "none"
end

local function UpdateRaidIcon(data)
    if not data.own or data.layout.raidIcon.visible == false then
        data.raidIconSource = "disabled"
        data.raidIcon:Hide()
        return
    end

    local protectedShown, protectedSource = RenderProtectedRaidTarget(data)
    if protectedShown then
        data.raidIconSource = protectedSource
        data.raidIcon:Show()
        return
    end

    local index = ResolveRaidTargetIndex(data)
    if not index then
        data.raidIconSource = protectedSource
        data.raidIcon:Hide()
        return
    end
    if type(SetRaidTargetIconTexture) == "function" then
        SetRaidTargetIconTexture(data.raidIcon, index)
    else
        local column = (index - 1) % 4
        local row = math.floor((index - 1) / 4)
        data.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        data.raidIcon:SetTexCoord(column / 4, (column + 1) / 4, row / 2, (row + 1) / 2)
    end
    data.raidIconSource = "readable-fallback"
    data.raidIcon:Show()
end

local function UpdateTagged(data)
    if not data.own or data.friendly or data.namesOnly or not db.showTagged
        or data.layout.tagged.visible == false or type(UnitIsTapDenied) ~= "function" then
        data.tagged:Hide()
        return
    end
    local ok, denied = pcall(UnitIsTapDenied, data.unit)
    if not ok or not IsReadable(denied) or not denied then
        data.tagged:Hide()
        return
    end
    data.tagged:Show()
end


local relationshipTextures = {
    group = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
    guild = "Interface\\GuildFrame\\GuildLogo-NoLogoSm",
}

local function UpdateRelationshipIcon(data)
    if not data.own or data.profileKey ~= "friendlyPlayer"
        or data.layout.relationshipIcon.visible == false then
        data.relationshipIcon:Hide()
        return
    end
    local relationship = FriendlyRelationship(data.unit)
    local enabled = (relationship == "group" and db.showGroupIcon)
        or (relationship == "guild" and db.showGuildIcon)
    local texture = enabled and relationshipTextures[relationship] or nil
    if not texture then
        data.relationshipIcon:Hide()
        return
    end
    data.relationshipIcon:SetTexture(texture)
    data.relationshipIcon:Show()
end

local pvpTextures = {
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    FFA = "Interface\\TargetingFrame\\UI-PVP-FFA",
}

local function UpdatePvPIcon(data)
    if not data.own or data.profileKey ~= "friendlyPlayer" or data.layout.pvpIcon.visible == false
        or (db.friendlyPvpStyle ~= "icon" and db.friendlyPvpStyle ~= "both") then
        data.pvpIcon:Hide()
        return
    end
    local texture = pvpTextures[FriendlyPvPState(data.unit)]
    if not texture then
        data.pvpIcon:Hide()
        return
    end
    data.pvpIcon:SetTexture(texture)
    data.pvpIcon:Show()
end

local classificationMarks = {
    elite = { text = "+", colour = { 1, 0.78, 0.25 } },
    rare = { text = "R", colour = { 0.68, 0.82, 1 } },
    rareelite = { text = "R+", colour = { 1, 0.78, 0.25 } },
    worldboss = { text = "BOSS", colour = { 1, 0.35, 0.25 } },
}

local function UpdateClassification(data)
    if not data.own or (data.profileKey ~= "enemy" and data.profileKey ~= "enemyDungeon") or not db.showClassification
        or data.layout.classification.visible == false or type(UnitClassification) ~= "function" then
        data.classification:Hide()
        return
    end
    local ok, kind = pcall(UnitClassification, data.unit)
    local mark = ok and IsReadable(kind) and classificationMarks[kind]
    if not mark then
        data.classification:Hide()
        return
    end
    data.classification:SetText(mark.text)
    data.classification:SetTextColor(mark.colour[1], mark.colour[2], mark.colour[3])
    data.classification:Show()
end

local function UpdateIdentity(data)
    local unit = data.unit
    local displayName = UnitDisplayNameValue(unit)
    local nameSet = HasValue(displayName) and pcall(data.name.SetText, data.name, displayName)
    if not nameSet then data.name:SetText("") end
    data.level:SetText(UnitLevel(unit))
    data.guild:Hide()
    if data.own and data.profileKey == "friendlyPlayer" and data.layout.guild.visible ~= false
        and type(GetGuildInfo) == "function" then
        local ok, guildName = pcall(GetGuildInfo, unit)
        if ok and IsReadable(guildName) and type(guildName) == "string" and guildName ~= "" then
            data.guild:SetText("<" .. guildName .. ">")
            data.guild:Show()
        end
    end
    local r, g, b = SafeColourForUnit(unit, data.friendly)
    data.name:SetTextColor(r, g, b)
    if data.profile.healthColourMode == "custom" then
        local colour = data.profile.healthColour
        data.health:SetStatusBarColor(colour.r, colour.g, colour.b)
    else
        data.health:SetStatusBarColor(r, g, b)
    end
    UpdateQuest(data)
    UpdateRelationshipIcon(data)
    UpdatePvPIcon(data)
    UpdateClassification(data)
end

local function IsDisplayNumber(value)
    return IsSecret(value) or (IsReadable(value) and type(value) == "number")
end

local function DisplayValue(region, format, first, second)
    local ok
    if HasValue(second) then
        ok = pcall(region.SetFormattedText, region, format, first, second)
    else
        ok = pcall(region.SetFormattedText, region, format, first)
    end
    if ok then region:Show() else region:SetText(""); region:Hide() end
end

local function ReadPercent(api, unit, current, maximum, power)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if type(api) == "function" and curve then
        local ok, percent
        if power then
            ok, percent = pcall(api, unit, nil, true, curve)
        else
            ok, percent = pcall(api, unit, true, curve)
        end
        if ok and IsDisplayNumber(percent) then return percent end
    end
    if IsReadable(current) and IsReadable(maximum) and type(current) == "number"
        and type(maximum) == "number" and maximum > 0 then
        return current * 100 / maximum
    end
end

local function UpdateResourceValues(data, health, healthMax, power, powerMax)
    local profile = data.profile
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = profile.valueSlots[key]
        local source = slot.source
        local region = data.values[key]
        local permitted = data.own and not data.namesOnly and data.layout[key].visible ~= false
            and source ~= "off" and data.valueAnchorFrames and data.valueAnchorFrames[key]
            and (source:sub(1, 5) ~= "power" or data.power:IsShown())
        if not permitted then
            region:Hide()
        elseif source == "healthCurrent" and IsDisplayNumber(health) then
            DisplayValue(region, "%.0f", health)
        elseif source == "healthValue" and IsDisplayNumber(health) and IsDisplayNumber(healthMax) then
            DisplayValue(region, "%.0f / %.0f", health, healthMax)
        elseif source == "healthPercent" then
            local percent = ReadPercent(UnitHealthPercent, data.unit, health, healthMax, false)
            if IsDisplayNumber(percent) then DisplayValue(region, "%.0f%%", percent) else region:Hide() end
        elseif source == "powerCurrent" and IsDisplayNumber(power) then
            DisplayValue(region, "%.0f", power)
        elseif source == "powerValue" and IsDisplayNumber(power) and IsDisplayNumber(powerMax) then
            DisplayValue(region, "%.0f / %.0f", power, powerMax)
        elseif source == "powerPercent" then
            local percent = ReadPercent(UnitPowerPercent, data.unit, power, powerMax, true)
            if IsDisplayNumber(percent) then DisplayValue(region, "%.0f%%", percent) else region:Hide() end
        elseif source ~= "threatPercent" and source ~= "leadPercent"
            and source ~= "rawThreat" and source ~= "differential" then
            region:Hide()
        end
    end
end

local function UpdateHealth(data)
    if not data.own or data.namesOnly
        or (data.restrictedFriendly and not data.restrictedOverlayEnabled) then return end
    local health, maximum = UnitHealth(data.unit), UnitHealthMax(data.unit)
    local secret = IsSecret(health) or IsSecret(maximum)
    if not secret and (type(health) ~= "number" or type(maximum) ~= "number" or maximum <= 0) then return end
    data.health:SetMinMaxValues(0, maximum)
    data.health:SetValue(health)
    local power, powerMax
    if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
        local okPower, resultPower = pcall(UnitPower, data.unit)
        local okMax, resultMax = pcall(UnitPowerMax, data.unit)
        if okPower and okMax and IsDisplayNumber(resultPower) and IsDisplayNumber(resultMax) then
            power, powerMax = resultPower, resultMax
            if IsSecret(powerMax) or powerMax > 0 then
                data.power:SetMinMaxValues(0, powerMax)
                data.power:SetValue(power)
                data.power:SetShown(data.layout.power.visible ~= false)
            else
                data.power:Hide()
            end
        else
            data.power:Hide()
        end
    else
        data.power:Hide()
    end
    if UpdateValueAnchors then UpdateValueAnchors(data) end
    UpdateResourceValues(data, health, maximum, power, powerMax)
end

local function ApplyTargetTextGlow(region, original, strength, visibleOnly)
    if not original or (visibleOnly and not region:IsShown()) then return end
    if strength then
        -- A shadow tracks the actual glyphs, including opaque names passed to SetText.
        region:SetShadowColor(1, 0.7, 0.14, strength)
        region:SetShadowOffset(1, -1)
    else
        region:SetShadowColor(original[1], original[2], original[3], original[4])
        region:SetShadowOffset(original[5], original[6])
    end
end

local function SetTargetTextGlow(data, strength, visibleOnly)
    for _, region in ipairs(data.targetGlowTexts) do
        ApplyTargetTextGlow(region, data.targetShadowDefaults[region], strength, visibleOnly)
    end
    for _, region in pairs(data.values) do
        ApplyTargetTextGlow(region, data.targetShadowDefaults[region], strength, visibleOnly)
    end
end

local function UpdateTarget(data)
    local targeted = UnitIsUnit(data.unit, "target")
    if not IsReadable(targeted) then targeted = false end
    local showHighlight = targeted and data.own and db.targetHighlightStyle ~= "off"
    local style = showHighlight and db.targetHighlightStyle or "off"
    if data.targetGlowStyle ~= style then
        data.targetGlowStyle = style
        data.targetPulseActive = style == "halo"
        for _, glow in ipairs(data.targetBarGlows) do
            glow.steady:SetShown(showHighlight)
            glow.pulse:SetShown(data.targetPulseActive)
        end
        SetTargetTextGlow(data, showHighlight and 0.7 or nil)
    elseif style == "border" then
        -- Newly shown labels can acquire the steady glow without touching other plates.
        SetTargetTextGlow(data, 0.7, true)
    end
    if targeted then
        data.healthBorder:SetBackdropBorderColor(1, 0.82, 0.12, 1)
    else
        data.healthBorder:SetBackdropBorderColor(0.05, 0.05, 0.05, 1)
    end
end

local function UpdateThreatValues(data, info)
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = data.profile.valueSlots[key]
        local source = slot.source
        if source == "threatPercent" or source == "leadPercent"
            or source == "rawThreat" or source == "differential" then
            local region = data.values[key]
            if not data.own or data.friendly or data.namesOnly or not db.threat
                or data.layout[key].visible == false or not info or not info.engaged
                or not data.valueAnchorFrames or not data.valueAnchorFrames[key] then
                region:Hide()
            elseif source == "differential" then
                if type(info.lead) == "number" then
                    region:SetText(FormatThreat(nil, info.lead))
                    region:Show()
                else
                    region:Hide()
                end
            else
                local value
                if source == "threatPercent" then
                    if info.hasOpaquePercent then value = info.percentOpaque else value = info.percent end
                elseif source == "leadPercent" then
                    if info.hasOpaqueLeadPercent then value = info.leadPercentOpaque else value = info.leadPercent end
                else
                    if info.hasOpaqueRawThreat then value = info.rawThreatOpaque else value = info.rawThreat end
                end
                if IsDisplayNumber(value) then
                    DisplayValue(region, source == "rawThreat" and "T%.0f"
                        or source == "leadPercent" and "L%.0f%%" or "%.0f%%", value)
                else
                    region:Hide()
                end
            end
        end
    end
end

local function UpdateThreat(data)
    if data.friendly or not db.threat then
        data.threat:Hide()
        data.threatLead:Hide()
        data.threat:SetText("")
        UpdateThreatValues(data, nil)
        return
    end
    local showCombined = data.layout.threat.visible ~= false
    data.threat:SetShown(showCombined)
    local info = ThreatRecord(data.unit)
    if not info or not info.engaged then
        data.threatLead:Hide()
        data.threat:SetText("")
        UpdateThreatValues(data, nil)
        return
    end
    if showCombined then
        data.threatDisplaySource = ApplyThreatText(data.threat, info)
        data.threatLeadSource = ApplyLeadSituation(data.threatLead, info)
        data.threat:SetTextColor(ThreatColour(info))
    else
        data.threatLead:Hide()
    end
    UpdateThreatValues(data, info)

    local service = PS.ThreatService
    if data.own and service and service:GetPlayerRole() == "TANK" and info.tanking == false then
        data.healthBorder:SetBackdropBorderColor(1, 0.12, 0.08, 1)
    end
end

local function ApplyAppearance(data)
    local profile = data.profile
    data.targetGlowStyle = nil
    local detailFontSize = math.max(8, profile.nameFontSize - 2)
    data.overlay:SetSize(profile.width + 16, math.max(52, profile.healthHeight + 40))
    data.health:SetSize(profile.width, profile.healthHeight)
    data.health:SetStatusBarTexture(healthTexturePaths[profile.healthTexture] or healthTexturePaths.blizzard)
    data.power:SetSize(profile.width, profile.powerHeight)
    data.power:SetStatusBarTexture(healthTexturePaths[profile.healthTexture] or healthTexturePaths.blizzard)
    data.cast:SetSize(profile.width, math.max(5, profile.healthHeight - 3))
    data.quest:SetSize(math.max(14, profile.nameFontSize + 4), math.max(14, profile.nameFontSize + 4))
    data.raidIcon:SetSize(math.max(16, profile.nameFontSize + 6), math.max(16, profile.nameFontSize + 6))
    data.relationshipIcon:SetSize(math.max(14, profile.nameFontSize + 4), math.max(14, profile.nameFontSize + 4))
    data.pvpIcon:SetSize(math.max(14, profile.nameFontSize + 4), math.max(14, profile.nameFontSize + 4))
    ApplyNameplateFont(data.name, profile.nameFontSize)
    ApplyNameplateFont(data.level, detailFontSize)
    ApplyNameplateFont(data.guild, detailFontSize)
    ApplyNameplateFont(data.threat, detailFontSize)
    ApplyNameplateFont(data.tagged, math.max(8, profile.nameFontSize - 3))
    ApplyNameplateFont(data.castName, math.max(7, profile.nameFontSize - 4))
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        ApplyNameplateFont(data.values[key], profile.valueSlots[key].fontSize)
        local colour = profile.valueSlots[key].colour
        data.values[key]:SetTextColor(colour.r, colour.g, colour.b)
        data.valueHolders[key]:SetFrameLevel(data.overlay:GetFrameLevel()
            + (profile.valueSlots[key].layer == "front" and 30 or -1))
    end
end

local valueFallbacks = {
    health = { "power", "cast" },
    power = { "health", "cast" },
    cast = { "power", "health" },
}

UpdateValueAnchors = function(data)
    data.valueAnchorFrames = data.valueAnchorFrames or {}
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = data.profile.valueSlots[key]
        local parent = slot.anchor == "canvas" and data.overlay or nil
        if not parent then
            local requested = data[slot.anchor]
            if requested and requested:IsShown() then parent = requested end
        end
        if not parent and slot.whenMissing ~= "hide" then
            for _, fallback in ipairs(valueFallbacks[slot.anchor] or {}) do
                local candidate = data[fallback]
                if candidate and candidate:IsShown() then parent = candidate break end
            end
            if not parent then parent = data.overlay end
        end
        if data.valueAnchorsDirty or data.valueAnchorFrames[key] ~= parent then
            local region = data.values[key]
            region:ClearAllPoints()
            if parent then
                local position = data.layout[key]
                region:SetPoint("CENTER", parent, "CENTER", position.x, position.y)
                if region.SetScale then region:SetScale(position.scale or 1) end
            else
                region:Hide()
            end
            data.valueAnchorFrames[key] = parent
        end
    end
    data.valueAnchorsDirty = false
end

local function ApplyComponentLayout(data)
    local function Anchor(region, key)
        local position = data.layout[key] or defaultLayout[key]
        if not position then return end
        region:ClearAllPoints()
        region:SetPoint("CENTER", data.overlay, "CENTER", position.x, position.y)
        if region.SetScale then region:SetScale(position.scale or 1) end
    end
    Anchor(data.health, "health")
    Anchor(data.power, "power")
    Anchor(data.name, "name")
    if data.layout.level and data.layout.name and data.layout.name.visible ~= false
        and data.layout.level.followName ~= false then
        local level = data.layout.level
        local baseline = data.friendly and (data.namesOnly or data.restrictedFriendly) and -85 or -70
        data.level:ClearAllPoints()
        data.level:SetPoint("RIGHT", data.name, "LEFT", -10 + level.x - baseline,
            level.y - data.layout.name.y)
        if data.level.SetScale then data.level:SetScale(level.scale or 1) end
    else
        Anchor(data.level, "level")
    end
    Anchor(data.guild, "guild")
    Anchor(data.cast, "cast")
    Anchor(data.threat, "threat")
    data.threatLead:ClearAllPoints()
    data.threatLead:SetPoint("TOP", data.threat, "BOTTOM", 0, -1)
    if data.threatLead.SetScale then data.threatLead:SetScale((data.layout.threat or defaultLayout.threat).scale or 1) end
    Anchor(data.tagged, "tagged")
    Anchor(data.quest, "quest")
    data.valueAnchorsDirty = true
    UpdateValueAnchors(data)
    Anchor(data.raidIcon, "raidIcon")
    Anchor(data.relationshipIcon, "relationshipIcon")
    Anchor(data.pvpIcon, "pvpIcon")
    Anchor(data.classification, "classification")
    Anchor(data.buffs, "buffs")
    Anchor(data.debuffs, "debuffs")
end

local function DisableRestrictedOverlay(data, reason)
    data.restrictedOverlayEnabled = false
    data.restrictedOverlayError = tostring(reason or "unavailable")
    data.overlay:Hide()
    HideCast(data)
    data.buffs:Hide()
    data.debuffs:Hide()
    for _, value in pairs(data.values) do value:Hide() end
end

local function ApplyLayout(data)
    data.own = OwnsAppearance()
    data.friendly = FriendlyUnit(data.unit)
    local restrictedFriendly = data.friendly == true and RestrictedFriendly(data.unit)
    data.restrictedFriendly = restrictedFriendly
    data.restrictedOverlayEnabled = restrictedFriendly
        and db.experimentalDungeonFriendlyText and data.own
    data.profileKey = ProfileKeyForUnit(data.unit, data.friendly)
    data.profile = db.plateProfiles[data.profileKey] or db.plateProfiles.enemy
    data.namesOnly = not restrictedFriendly and data.friendly and db.friendly == "names"
    data.layout = restrictedFriendly and data.profile.dungeonNamesLayout
        or (data.namesOnly and data.profile.namesLayout or data.profile.layout)
    data.overlay:SetScale(data.profile.scale)
    ApplyAppearance(data)
    if data.namesOnly then
        -- Values are parented outside the overlay. Switching a live plate from
        -- full to names-only must clear any previously visible value explicitly.
        for _, value in pairs(data.values) do value:Hide() end
    end

    if data.friendly == nil then
        HideCast(data)
        data.buffs:Hide()
        data.debuffs:Hide()
        data.power:Hide()
        for _, value in pairs(data.values) do value:Hide() end
        RestoreNative(data)
        data.overlay:Hide()
        return
    end

    if restrictedFriendly then
        HideCast(data)
        data.buffs:Hide()
        data.debuffs:Hide()
        data.power:Hide()
        for _, value in pairs(data.values) do value:Hide() end
        RestoreNative(data)
        data.overlay:Hide()
        data.restrictedOverlayError = nil
        if data.restrictedOverlayEnabled then
            -- Opt-in additive preview: never hide, move, or reparent Blizzard's restricted frame.
            local ok, failure = pcall(function()
                ApplyComponentLayout(data)
                data.name:SetShown(data.layout.name.visible ~= false)
                data.health:SetShown(data.layout.health.visible ~= false)
                data.level:SetShown(data.layout.level.visible ~= false)
                data.power:Hide()
                data.overlay:Show()
                UpdateIdentity(data)
                UpdateRaidIcon(data)
                UpdateHealth(data)
                UpdateTarget(data)
                UpdateThreat(data)
                UpdateTagged(data)
                UpdateCast(data)
                UpdateAuras(data)
            end)
            if not ok then DisableRestrictedOverlay(data, failure) end
        end
        return
    end

    if data.friendly and db.friendly == "off" then
        HideCast(data)
        data.buffs:Hide()
        data.debuffs:Hide()
        data.power:Hide()
        for _, value in pairs(data.values) do value:Hide() end
        RestoreNative(data)
        data.overlay:Hide()
        return
    end

    data.overlay:Show()
    if data.own then
        HideNative(data)
        data.name:SetShown(data.layout.name.visible ~= false)
        data.health:SetShown(not data.namesOnly and data.layout.health.visible ~= false)
        data.power:SetShown(false)
        data.level:SetShown(data.layout.level.visible ~= false)
        ApplyComponentLayout(data)
        if data.namesOnly then
            data.threat:SetText("")
            data.tagged:Hide()
        end
    else
        RestoreNative(data)
        data.health:Hide()
        data.power:Hide()
        for _, value in pairs(data.values) do value:Hide() end
        data.level:Hide()
        data.guild:Hide()
        data.name:Hide()
        data.threat:ClearAllPoints()
        data.threat:SetPoint("BOTTOM", data.overlay, "TOP", 0, 2)
        data.threatLead:ClearAllPoints()
        data.threatLead:SetPoint("TOP", data.threat, "BOTTOM", 0, -1)
        data.quest:ClearAllPoints()
        data.quest:SetPoint("RIGHT", data.threat, "LEFT", -4, 0)
        data.raidIcon:Hide()
        data.relationshipIcon:Hide()
        data.pvpIcon:Hide()
        data.classification:Hide()
        data.tagged:Hide()
    end

    UpdateIdentity(data)
    UpdateRaidIcon(data)
    UpdateHealth(data)
    UpdateTarget(data)
    UpdateThreat(data)
    UpdateTagged(data)
    UpdateCast(data)
    UpdateAuras(data)
end

local function AddPlate(unit)
    if not db.enabled or not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    local root = C_NamePlate.GetNamePlateForUnit(unit)
    if not root then return end
    if root.IsForbidden and root:IsForbidden() then return end

    local data = root.PlateSmithData or CreatePlate(root)
    root.PlateSmithData = data
    data.unit = unit
    active[unit] = data
    if PS.ThreatService then
        PS.ThreatService:TrackEnemy(unit, root)
        if db.threat then PS.ThreatService:RefreshUnit(unit) end
    end
    ApplyLayout(data)
end

local function ApplySpotlightStyle(data)
    local style = db.threatSpotlightStyle
    data.beacon:SetBackdropBorderColor(0.2, 0.78, 1, style == "sides" and 0 or 1)
    data.beaconLeft:SetShown(style ~= "box")
    data.beaconRight:SetShown(style ~= "box")
end

local function UpdateSpotlight(now)
    if spotlightUnit and (not active[spotlightUnit] or now >= spotlightUntil) then
        spotlightUnit, spotlightUntil = nil, nil
    end
    for unit, data in pairs(active) do
        local enemy = data.profileKey == "enemy" or data.profileKey == "enemyDungeon"
        local alpha = spotlightUnit and unit ~= spotlightUnit and enemy
            and db.threatSpotlightOthersAlpha or 1
        if data.spotlightAlpha ~= alpha then
            data.overlay:SetAlpha(alpha)
            data.spotlightAlpha = alpha
        end
    end
end

local function RemovePlate(unit)
    local data = active[unit]
    if not data then return end
    if PS.ThreatService then PS.ThreatService:UntrackEnemy(unit) end
    RestoreNative(data)
    data.nativeAlpha = nil
    data.beaconUntil = nil
    data.beacon:Hide()
    for _, glow in ipairs(data.targetBarGlows) do
        glow.steady:Hide()
        glow.pulse:Hide()
    end
    data.targetPulseActive = nil
    data.targetGlowStyle = nil
    SetTargetTextGlow(data)
    data.overlay:SetAlpha(1)
    data.spotlightAlpha = nil
    data.overlay:Hide()
    HideCast(data)
    data.buffs:Hide()
    data.debuffs:Hide()
    data.unit = nil
    active[unit] = nil
    if spotlightUnit == unit then
        spotlightUnit, spotlightUntil = nil, nil
        UpdateSpotlight(GetTime())
    end
end

local function HighlightPlate(unit, duration)
    local data = type(unit) == "string" and active[unit] or nil
    if not data or not data.unit or not data.overlay:IsShown() then return false end
    duration = math.max(1, math.min(8, tonumber(duration) or db.threatSpotlightDuration))
    if spotlightUnit and spotlightUnit ~= unit and active[spotlightUnit] then
        local previous = active[spotlightUnit]
        previous.beaconUntil = nil
        previous.beacon:Hide()
    end
    spotlightUnit, spotlightUntil = unit, GetTime() + duration
    data.beaconUntil = GetTime() + duration
    ApplySpotlightStyle(data)
    data.beacon:SetAlpha(1)
    data.beacon:Show()
    UpdateSpotlight(GetTime())
    return true
end

local function RefreshAll()
    for unit, data in pairs(active) do
        if data.unit == unit then
            ApplyLayout(data)
            ApplySpotlightStyle(data)
        end
    end
    UpdateSpotlight(GetTime())
end

local function SafePlateUpdate(data, update)
    if data.restrictedFriendly then
        if not data.restrictedOverlayEnabled then return end
        local ok, reason = pcall(update, data)
        if not ok then DisableRestrictedOverlay(data, reason) end
    else
        update(data)
    end
end

local function RefreshQuestMarkers()
    for unit, data in pairs(active) do
        if data.unit == unit then SafePlateUpdate(data, UpdateQuest) end
    end
end

local function SetOption(key, value)
    if defaults[key] == nil or key == "schemaVersion" then return false end
    db[key] = value
    if key == "scale" or key == "width" or key == "healthHeight" or key == "nameFontSize" then
        db.plateProfiles.enemy[key] = value
    end
    NormalizeSettings(db)
    if key == "hideUnstyledFriendlyNames" or key == "restrictedFriendlyNamesOnly"
        or key == "restrictedFriendlyClassColour" then ApplyFriendlyNamePolicy() end
    RefreshAll()
    return true
end

local function GetProfileSettings(profileKey)
    if not db or not db.plateProfiles then return nil end
    if profileKey == "enemyDungeon" then
        return db.plateProfiles.enemyDungeon or db.plateProfiles.enemy
    end
    profileKey = profileDefaults[profileKey] and profileKey or "enemy"
    return db.plateProfiles[profileKey]
end

local function EnsureProfileSettings(profileKey)
    if profileKey == "enemyDungeon" then
        if not db.plateProfiles.enemyDungeon then
            db.plateProfiles.enemyDungeon = CopyEnemyProfile(db.plateProfiles.enemy)
        end
        return db.plateProfiles.enemyDungeon
    end
    return GetProfileSettings(profileKey)
end

local function SetDungeonEnemyProfile(profile)
    if not db then return false end
    if profile == nil then
        db.plateProfiles.enemyDungeon = nil
    elseif type(profile) == "table" then
        db.plateProfiles.enemyDungeon = CopyEnemyProfile(NormalizeProfile(profile, db.plateProfiles.enemy))
    else
        return false
    end
    RefreshAll()
    return true
end


local function LayoutField(profileKey, variant)
    if variant == "dungeon" and (profileKey == "friendlyPlayer" or profileKey == "friendlyNPC") then
        return "dungeonNamesLayout"
    end
    return variant == "names" and profileKey ~= "enemy" and profileKey ~= "enemyDungeon"
        and "namesLayout" or "layout"
end

local function GetDefaultLayout(profileKey, variant)
    if profileKey == "enemyDungeon" then
        return NormalizeLayout(db and db.plateProfiles.enemy.layout, profileDefaults.enemy.layout)
    end
    profileKey = profileDefaults[profileKey] and profileKey or "enemy"
    local field = LayoutField(profileKey, variant)
    return NormalizeLayout(nil, profileDefaults[profileKey][field])
end

local function GetLayout(profileKey, variant)
    profileKey = profileKey == "enemyDungeon" and profileKey
        or (profileDefaults[profileKey] and profileKey or "enemy")
    local profile = GetProfileSettings(profileKey)
    local field = LayoutField(profileKey, variant)
    local fallback = profileKey == "enemyDungeon" and db.plateProfiles.enemy
        or profileDefaults[profileKey]
    return NormalizeLayout(profile and profile[field], fallback[field])
end

local function SetLayout(layout, profileKey, variant)
    if not db then return false end
    profileKey = profileKey == "enemyDungeon" and profileKey
        or (profileDefaults[profileKey] and profileKey or "enemy")
    local field = LayoutField(profileKey, variant)
    local profile = EnsureProfileSettings(profileKey)
    local fallback = profileKey == "enemyDungeon" and db.plateProfiles.enemy
        or profileDefaults[profileKey]
    profile[field] = NormalizeLayout(layout, fallback[field])
    if profileKey == "enemy" then db.layout = db.plateProfiles.enemy.layout end
    RefreshAll()
    return true
end

local function SetComponentPosition(key, x, y, profileKey, variant)
    if not db or type(key) ~= "string" or not key:match("^[%a][%w_%.]*$") then return false end
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return false end
    local layout = GetLayout(profileKey, variant)
    local current = layout[key]
    layout[key] = { x = x, y = y, visible = not current or current.visible ~= false,
        scale = current and current.scale or 1, followName = current and current.followName }
    return SetLayout(layout, profileKey, variant)
end

local function SetComponentScale(key, scale, profileKey, variant)
    if not db or type(key) ~= "string" or not key:match("^[%a][%w_%.]*$") then return false end
    scale = tonumber(scale)
    if not scale or scale ~= scale or scale < 0.5 or scale > 2 then return false end
    local layout = GetLayout(profileKey, variant)
    if not layout[key] then return false end
    layout[key].scale = scale
    return SetLayout(layout, profileKey, variant)
end

local function SetLevelFollowName(enabled, profileKey, variant)
    if not db or type(enabled) ~= "boolean" then return false end
    local layout = GetLayout(profileKey, variant)
    if not layout.level then return false end
    layout.level.followName = enabled
    return SetLayout(layout, profileKey, variant)
end

local function SetComponentVisibility(key, visible, profileKey, variant)
    if not db or type(key) ~= "string" or not key:match("^[%a][%w_%.]*$") or type(visible) ~= "boolean" then
        return false
    end
    local layout = GetLayout(profileKey, variant)
    if not layout[key] then return false end
    layout[key].visible = visible
    return SetLayout(layout, profileKey, variant)
end

local function SetProfileOption(profileKey, key, value)
    if (key ~= "scale" and key ~= "width" and key ~= "healthHeight" and key ~= "powerHeight" and key ~= "nameFontSize"
        and key ~= "healthTexture" and key ~= "healthColourMode") then
        return false
    end
    local profile = EnsureProfileSettings(profileKey)
    if not profile then return false end
    profile[key] = value
    NormalizeProfile(profile, profileKey == "enemyDungeon" and db.plateProfiles.enemy or profileDefaults[profileKey])
    if profileKey == "enemy" and (key == "scale" or key == "width" or key == "healthHeight" or key == "nameFontSize") then
        db[key] = profile[key]
        db.layout = profile.layout
    end
    RefreshAll()
    return true
end

local function SetProfileValueSlot(profileKey, key, field, value)
    local profile = GetProfileSettings(profileKey)
    local slot = profile and profile.valueSlots and profile.valueSlots[key]
    if not slot then return false end
    if field == "source" then
        if not valueSources[value] then return false end
    elseif field == "anchor" then
        if not valueAnchors[value] then return false end
    elseif field == "layer" then
        if not valueLayers[value] then return false end
    elseif field == "whenMissing" then
        if not missingAnchorModes[value] then return false end
    elseif field == "fontSize" then
        value = tonumber(value)
        if not value or value < 7 or value > 18 then return false end
    elseif field == "colour" then
        if type(value) ~= "table" then return false end
        value = NormalizeColour(value, { r = 1, g = 1, b = 1 })
    else
        return false
    end
    profile = EnsureProfileSettings(profileKey)
    slot = profile.valueSlots[key]
    slot[field] = value
    NormalizeProfile(profile, profileKey == "enemyDungeon" and db.plateProfiles.enemy or profileDefaults[profileKey])
    RefreshAll()
    return true
end

local function SetProfileValueSlots(profileKey, slots)
    if not GetProfileSettings(profileKey) or type(slots) ~= "table" then return false end
    local candidate = {}
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        local slot = slots[key]
        if type(slot) ~= "table" or not valueSources[slot.source]
            or not valueAnchors[slot.anchor] or (slot.layer ~= nil and not valueLayers[slot.layer])
            or (slot.whenMissing ~= nil and not missingAnchorModes[slot.whenMissing])
            or type(slot.fontSize) ~= "number"
            or slot.fontSize < 7 or slot.fontSize > 18 or type(slot.colour) ~= "table" then return false end
        candidate[key] = { source = slot.source, anchor = slot.anchor,
            layer = slot.layer or "front", whenMissing = slot.whenMissing or "fallback", fontSize = slot.fontSize,
            colour = NormalizeColour(slot.colour, { r = 1, g = 1, b = 1 }) }
    end
    EnsureProfileSettings(profileKey).valueSlots = candidate
    RefreshAll()
    return true
end

local function SetProfileHealthColour(profileKey, r, g, b)
    if not GetProfileSettings(profileKey) then return false end
    local profile = EnsureProfileSettings(profileKey)
    if not profile then return false end
    profile.healthColour = NormalizeColour({ r = r, g = g, b = b },
        profileKey == "enemyDungeon" and db.plateProfiles.enemy.healthColour
            or profileDefaults[profileKey].healthColour)
    profile.healthColourMode = "custom"
    RefreshAll()
    return true
end

local function SetRelationshipColour(relationship, r, g, b)
    local fallback = defaultRelationshipColours[relationship]
    if not db or not fallback then return false end
    db.relationshipColours[relationship] = NormalizeColour({ r = r, g = g, b = b }, fallback)
    RefreshAll()
    return true
end

local function ResetSettings()
    RestoreFriendlyNameCVars(true)
    RestoreRestrictedFriendlyNameCVar(true)
    ApplyRestrictedFriendlyClassColour(false)
    local settings = type(PlateSmithDB) == "table" and PlateSmithDB or {}
    for key in pairs(settings) do settings[key] = nil end
    PlateSmithDB = NormalizeSettings(settings)
    db = PlateSmithDB
    ApplyFriendlyNamePolicy()
    RefreshAll()
    return db
end

local function ScanPlates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local plates = C_NamePlate.GetNamePlates()
    for _, root in ipairs(plates) do
        if root.namePlateUnitToken then AddPlate(root.namePlateUnitToken) end
    end
end

local function ImproveNativeNameFont()
    if not db.nativeNameFont then return end
    local font = _G.SystemFont_NamePlate
    if not font or not font.GetFont or not font.SetFont then return end
    if not PS.nativeFont then
        PS.nativeFont = { font:GetFont() }
    end
    local path, size = font:GetFont()
    font:SetFont(path or STANDARD_TEXT_FONT, math.max(size or 12, 13), "OUTLINE")
end

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff60d4ffPlateSmith:|r " .. message)
    end
end

-- Probes stay close to plate state, while report UI/JSON lives in DiagnosticUI.lua.
-- Keep probe-only helpers in a child scope so they do not consume the main Lua
-- chunk's 200-active-local budget for the rest of the runtime.
local DiagnosticUI = assert(PS.DiagnosticUI, "PlateSmith DiagnosticUI missing")
local Diagnose, ProbePlayerPlate, AuraProbe
do

local function ThreatProbeState(value)
    if IsSecret(value) then return "protected/displayable" end
    if value == nil then return "none" end
    if IsReadable(value) and (type(value) == "number" or type(value) == "boolean") then return "readable" end
    return "unavailable"
end

local function ThreatProbeCall(callback, actor, mob)
    if type(callback) ~= "function" then return "api-missing" end
    if not IsSecret(mob) and mob == nil then return "no-mob" end
    local ok, value = pcall(callback, actor, mob)
    return ok and ThreatProbeState(value) or "error"
end

AuraProbe = function(unit, filter)
    local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(api) ~= "function" then return "api-missing" end
    if type(unit) ~= "string" then return "no-unit" end
    local ok, aura = pcall(api, unit, 1, filter)
    if not ok then return "error" end
    if not IsReadable(aura) then return "protected" end
    if aura == nil then return "none" end
    local iconOK, icon = pcall(function() return aura.icon end)
    if not iconOK then return "icon-error" end
    if IsSecret(icon) then return "icon-protected/displayable" end
    return icon == nil and "icon-none" or "icon-readable"
end

local function DiagnosticUnitValue(callback, ...)
    if type(callback) ~= "function" then return "api-missing" end
    local ok, value = pcall(callback, ...)
    if not ok then return "error" end
    if not IsReadable(value) then return "protected" end
    if value == nil then return "none" end
    local kind = type(value)
    return (kind == "boolean" or kind == "number" or kind == "string") and value or "unavailable"
end

Diagnose = function()
    local build = type(GetBuildInfo) == "function" and select(4, GetBuildInfo()) or "unknown"
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
    local inInstance, instanceType = IsInInstance()
    local groupCount, groupType = 0, "solo"
    if type(GetNumGroupMembers) == "function" then
        local ok, count = pcall(GetNumGroupMembers)
        if ok and IsReadable(count) and type(count) == "number" then groupCount = count end
    end
    if groupCount > 0 then
        local raid = false
        if type(IsInRaid) == "function" then
            local ok, value = pcall(IsInRaid)
            raid = ok and IsReadable(value) and value == true
        end
        groupType = raid and "raid" or "party"
    end
    local questAPI = C_QuestLog and type(C_QuestLog.UnitIsRelatedToActiveQuest) == "function"
    local report = {
        format = "platesmith-diagnostics",
        version = tostring(PS.RUNTIME_BUILD or "unknown build"),
        context = {
            build = build, provider = ExternalProvider() or "native", plates = #plates,
            instance = inInstance and instanceType or "world",
            group = { type = groupType, members = groupCount },
        },
        api = { quest = questAPI == true, secret = type(issecretvalue) == "function" },
        settings = { mode = db.mode, friendly = db.friendly },
        questProviders = DiagnosticUI.JsonArray(),
        raid = {},
    }
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        local trackedFriendly, overlayShown, overlayErrors, firstError = 0, 0, 0, nil
        for _, data in pairs(active) do
            if data.friendly == true then
                trackedFriendly = trackedFriendly + 1
                if data.overlay:IsShown() then overlayShown = overlayShown + 1 end
                if data.restrictedOverlayError then
                    overlayErrors = overlayErrors + 1
                    firstError = firstError or data.restrictedOverlayError
                end
            end
        end
        report.dungeonFriendlyOverlay = {
            enabled = db.experimentalDungeonFriendlyText == true,
            tracked = trackedFriendly, shown = overlayShown, errors = overlayErrors,
            nativeRetained = true,
        }
        if firstError then report.dungeonFriendlyOverlay.firstError = firstError:sub(1, 160) end
    end

    if type(PS.IterateQuestProviders) == "function" then
        for id, provider in PS:IterateQuestProviders() do
            local status = provider._plateSmithQuestFailed and "failed" or "ready"
            local detail = nil
            if type(provider.GetDiagnostics) == "function" then
                local ok, value = pcall(provider.GetDiagnostics, provider)
                if ok and type(value) == "string" then detail = value end
            end
            report.questProviders[#report.questProviders + 1] = {
                id = id, status = status, detail = detail or "none",
            }
        end
    end

    local targetIndex, targetIndexState = ReadRaidTargetIndex("target")
    local targetRoot, targetRootState = NamePlateRootForUnit("target")
    report.raid.api = {
        target = { index = targetIndex or "none", state = targetIndexState },
        targetPlate = { match = "unmatched", state = targetRootState },
    }
    local targetData = targetRoot and targetRoot.PlateSmithData or nil
    if not targetData and type(UnitIsUnit) == "function" then
        for unit, data in pairs(active) do
            local ok, same = pcall(UnitIsUnit, unit, "target")
            if ok and IsReadable(same) and same then
                targetData = data
                break
            end
        end
    end
    if targetData then
        local resolved, source, route = ResolveRaidTargetIndex(targetData)
        local shown = type(targetData.raidIcon.IsShown) == "function" and targetData.raidIcon:IsShown() or false
        report.raid.api.targetPlate.match = "matched"
        report.raid.plate = {
            resolved = resolved or "none", source = source or "none", route = route or "none",
            render = targetData.raidIconSource or "unknown", own = targetData.own == true,
            layout = targetData.layout.raidIcon.visible ~= false, shown = shown == true,
        }
        local nameShown = type(targetData.name.IsShown) == "function" and targetData.name:IsShown() or false
        report.target = report.target or {}
        report.target.plate = {
            profile = targetData.profileKey or "unknown",
            namesOnly = targetData.namesOnly == true,
            nameLayout = targetData.layout.name.visible ~= false,
            nameShown = nameShown == true,
            nameReadable = ReadUnitName(UnitName, targetData.unit) ~= nil,
        }
        local matchState = "api-missing"
        if type(UnitIsUnit) == "function" then
            local ok, same = pcall(UnitIsUnit, targetData.unit, "target")
            matchState = not ok and "error" or not IsReadable(same) and "protected"
                or tostring(same == true)
        end
        report.target.highlight = {
            configured = db.targetHighlightStyle,
            targetMatch = matchState,
            applied = targetData.targetGlowStyle or "none",
            nameGlowShown = (targetData.targetGlowStyle == "border"
                or targetData.targetGlowStyle == "halo") and nameShown == true,
            healthGlowShown = targetData.targetBorder:IsShown() == true,
        }
        local shownValues = {}
        for index = 1, VALUE_SLOT_COUNT do
            local key = "value" .. index
            if targetData.values[key]:IsShown() then
                shownValues[#shownValues + 1] = { slot = key,
                    source = targetData.profile.valueSlots[key].source }
            end
        end
        report.target.plate.shownValues = shownValues
        local filter = db.debuffSource == "mine" and "HARMFUL|PLAYER" or "HARMFUL"
        local buffFilter = db.buffSource == "mine" and "HELPFUL|PLAYER" or "HELPFUL"
        local buffPosition = targetData.layout.buffs
        local debuffPosition = targetData.layout.debuffs
        local shownBuffIcons, shownDebuffIcons = 0, 0
        for index = 1, AURA_ICON_COUNT do
            if targetData.buffIcons[index]:IsShown() then shownBuffIcons = shownBuffIcons + 1 end
            if targetData.debuffIcons[index]:IsShown() then shownDebuffIcons = shownDebuffIcons + 1 end
        end
        report.target.buffs = {
            enabled = db.showBuffs == true, source = db.buffSource, own = targetData.own == true,
            layout = buffPosition.visible ~= false,
            position = { x = buffPosition.x, y = buffPosition.y, scale = buffPosition.scale or 1 },
            rowShown = targetData.buffs:IsShown() == true,
            rowVisible = RegionVisibleState(targetData.buffs),
            overlayVisible = RegionVisibleState(targetData.overlay),
            iconsShown = shownBuffIcons,
            firstIconVisible = RegionVisibleState(targetData.buffIcons[1]),
            containerShown = targetData.buffs.nativeAuraContainer
                and targetData.buffs.nativeAuraContainer:IsShown() == true or false,
            route = targetData.buffsAuraRoute or "unknown",
            probe = { filter = buffFilter, target = AuraProbe("target", buffFilter),
                plate = AuraProbe(targetData.unit, buffFilter) },
        }
        report.target.debuffs = {
            enabled = db.showDebuffs == true, source = db.debuffSource, own = targetData.own == true,
            layout = debuffPosition.visible ~= false,
            position = { x = debuffPosition.x, y = debuffPosition.y, scale = debuffPosition.scale or 1 },
            rowShown = targetData.debuffs:IsShown() == true,
            rowVisible = RegionVisibleState(targetData.debuffs),
            overlayVisible = RegionVisibleState(targetData.overlay),
            iconsShown = shownDebuffIcons,
            firstIconVisible = RegionVisibleState(targetData.debuffIcons[1]),
            containerShown = targetData.debuffs.nativeAuraContainer
                and targetData.debuffs.nativeAuraContainer:IsShown() == true or false,
            targetMatch = matchState, route = targetData.debuffsAuraRoute or "unknown",
            probe = {
                filter = filter, target = AuraProbe("target", filter),
                plate = AuraProbe(targetData.unit, filter), targetAll = AuraProbe("target", "HARMFUL"),
            },
        }
        if targetData.debuffs.nativeAuraError then
            report.target.debuffs.nativeContainerError = targetData.debuffs.nativeAuraError
        end
    else
        report.raid.api.targetPlate.note = "no tracked nameplate for this target at this instant"
    end
    if PS._lastBlockedAction then
        report.protectedAction = { last = PS._lastBlockedAction }
        if PS._lastEventRegistration then
            report.protectedAction.lastEventRegistration = PS._lastEventRegistration
        end
    end

    if type(UnitExists) == "function" and UnitExists("target") then
        local displayName = ReadUnitName(GetUnitName, "target", true) or "unavailable"
        local pvpName = ReadUnitName(UnitPVPName, "target") or "unavailable"
        local legacyName = ReadUnitName(UnitName, "target") or "unavailable"
        report.target = report.target or {}
        report.target.names = { display = displayName, pvp = pvpName, legacy = legacyName }
        report.target.identity = {
            player = DiagnosticUnitValue(UnitIsPlayer, "target"),
            friendly = DiagnosticUnitValue(UnitIsFriend, "player", "target"),
            reaction = DiagnosticUnitValue(UnitReaction, "target", "player"),
            pvpFlagged = DiagnosticUnitValue(UnitIsPVP, "target"),
            attackable = DiagnosticUnitValue(UnitCanAttack, "player", "target"),
        }
        local questRelated, questSource, questDetail = QuestRelevance("target")
        report.target.quest = {
            related = questRelated == true, source = questSource or "none", detail = questDetail or "none",
        }
        local threat
        for unit in pairs(active) do
            local same = type(UnitIsUnit) == "function" and UnitIsUnit(unit, "target")
            if IsReadable(same) and same then
                threat = ThreatRecord(unit, true)
                break
            end
        end
        local threatText = threat and FormatThreatRecord(threat) or ""
        if threatText == "" and threat and (threat.hasOpaquePercent or threat.hasOpaqueLeadPercent or threat.hasOpaqueRawThreat) then
            threatText = "protected/displayable"
        end
        report.target.threat = {
            display = threatText ~= "" and threatText or "unavailable",
            differential = threat and threat.differentialState or "unavailable",
            source = threat and threat.threatMobSource or "unavailable",
            blocker = threat and threat.differentialBlocker or "none",
            engaged = threat and threat.engaged == true or false,
            playerNoEntry = threat and threat.playerThreatNoEntry == true or false,
            fallback = {
                raw = threat and threat.rawThreatState or "unavailable",
                leadPercent = threat and threat.leadPercentState or "unavailable",
                leadSituation = threat and threat.leadSituationState or "unavailable",
            },
        }

        -- Bounded, read-only probes: classify each return without converting a secret to text.
        local actors = { "player" }
        local petOwners = {}
        local threatProbe = {
            pets = { active = 0, roster = DiagnosticUI.JsonArray() },
            actors = DiagnosticUI.JsonArray(),
        }
        report.target.threatProbe = threatProbe
        local function AddPet(unit, owner)
            local ok, exists = pcall(UnitExists, unit)
            if not ok then
                threatProbe.pets.roster[#threatProbe.pets.roster + 1] = { unit = unit, exists = "error" }
            elseif not IsReadable(exists) then
                threatProbe.pets.roster[#threatProbe.pets.roster + 1] = { unit = unit, exists = "protected" }
            elseif exists then
                actors[#actors + 1] = unit
                petOwners[unit] = owner
            end
        end
        if groupType ~= "raid" then AddPet("pet", "player") end
        if groupType == "party" then
            for index = 1, math.min(4, groupCount - 1) do
                local unit = "party" .. index
                local ok, exists = pcall(UnitExists, unit)
                if ok and IsReadable(exists) and exists then actors[#actors + 1] = unit end
                AddPet("partypet" .. index, unit)
            end
        elseif groupType == "raid" then
            for index = 1, math.min(40, groupCount) do
                local unit = "raid" .. index
                if index <= 3 then
                    local ok, exists = pcall(UnitExists, unit)
                    if ok and IsReadable(exists) and exists then actors[#actors + 1] = unit end
                end
                AddPet("raidpet" .. index, unit)
            end
        end
        local petCount = 0
        for _ in pairs(petOwners) do petCount = petCount + 1 end
        threatProbe.pets.active = petCount
        if groupType == "raid" then
            threatProbe.pets.raidPlayersProbed = "first 3 slots"
            threatProbe.pets.raidPetsProbed = "all slots"
        end
        local plateUnit = targetData and targetData.unit or nil
        local guid
        if type(UnitGUID) == "function" then
            local ok, value = pcall(UnitGUID, plateUnit or "target")
            if ok then guid = value end
        end
        local guidState = IsSecret(guid) and "protected" or (guid == nil and "none" or "readable")
        threatProbe.mobIdentifiers = {
            target = "unit", plate = plateUnit and "unit" or "none", guid = guidState,
        }
        for _, actor in ipairs(actors) do
            local actorProbe = { unit = actor }
            if petOwners[actor] then
                actorProbe.owner = petOwners[actor]
                actorProbe.name = ReadUnitName(UnitName, actor) or "unavailable"
            end
            if type(UnitDetailedThreatSituation) == "function" then
                local ok, tanking, status, scaled, rawPercent, rawThreat =
                    pcall(UnitDetailedThreatSituation, actor, "target")
                if ok then
                    actorProbe.target = {
                        tanking = ThreatProbeState(tanking), status = ThreatProbeState(status),
                        scaled = ThreatProbeState(scaled), rawPercent = ThreatProbeState(rawPercent),
                        raw = ThreatProbeState(rawThreat),
                        situation = ThreatProbeCall(UnitThreatSituation, actor, "target"),
                    }
                    if IsReadable(rawThreat) and type(rawThreat) == "number" then
                        actorProbe.target.rawValue = rawThreat
                    end
                else
                    actorProbe.target = { detailed = "error" }
                end
            else
                actorProbe.target = { detailed = "api-missing" }
            end
            local function LeadPair(mob)
                return {
                    percent = ThreatProbeCall(UnitThreatPercentageOfLead, actor, mob),
                    situation = ThreatProbeCall(UnitThreatLeadSituation, actor, mob),
                }
            end
            actorProbe.lead = { target = LeadPair("target"), plate = LeadPair(plateUnit),
                guid = LeadPair(guid) }
            threatProbe.actors[#threatProbe.actors + 1] = actorProbe
        end
    end
    if PS.ThreatConsole and PS.ThreatConsole.lastHighlightCheck then
        report.threatConsole = { lastClick = PS.ThreatConsole.lastHighlightCheck }
    end
    DiagnosticUI.ShowReport(report)
end

ProbePlayerPlate = function()
    if type(UnitExists) ~= "function" or not UnitExists("target") then
        Print("Target the neutral or opposing player first, then run /platesmith playerprobe.")
        return
    end
    local root, state = NamePlateRootForUnit("target")
    local match
    for unit in pairs(active) do
        local ok, same = pcall(UnitIsUnit, unit, "target")
        if ok and IsReadable(same) and same == true then match = unit break end
    end
    local report = {
        format = "platesmith-player-probe",
        version = PS.RUNTIME_BUILD or "unknown",
        target = {
            name = ReadUnitName(GetUnitName, "target", true) or "unavailable",
            player = DiagnosticUnitValue(UnitIsPlayer, "target"),
            friendly = DiagnosticUnitValue(UnitIsFriend, "player", "target"),
            reaction = DiagnosticUnitValue(UnitReaction, "target", "player"),
            pvpFlagged = DiagnosticUnitValue(UnitIsPVP, "target"),
            attackable = DiagnosticUnitValue(UnitCanAttack, "player", "target"),
        },
        nameplate = {
            api = state,
            trackedUnit = match or "none",
            tracked = match ~= nil,
            note = (root or match) and "A nameplate frame is available for PlateSmith to test."
                or "No nameplate frame was supplied for this target at probe time; the visible name may be native overhead text.",
        },
        cvars = {
            nameplateShowEnemies = ReadCVar("nameplateShowEnemies") or "absent",
            nameplateShowAll = ReadCVar("nameplateShowAll") or "absent",
            nameplateShowEnemyPlayer = ReadCVar("nameplateShowEnemyPlayer") or "absent",
            nameplateShowEnemyPlayers = ReadCVar("nameplateShowEnemyPlayers") or "absent",
        },
    }
    DiagnosticUI.ShowReport(report)
end
end -- diagnostic helper scope

local pendingOptionsOpen = false
local targetProbeButton, targetProbeUnit, targetProbeRoot, targetProbeStale, targetProbeAction

local function DisarmTargetProbe()
    if targetProbeButton then
        if type(UnregisterStateDriver) == "function" then
            pcall(UnregisterStateDriver, targetProbeButton, "visibility")
        end
        targetProbeButton:Hide()
        targetProbeButton:SetAttribute("unit", "none")
    end
    targetProbeUnit, targetProbeRoot, targetProbeStale, targetProbeAction = nil, nil, nil, nil
end

local function ArmTargetProbe(action)
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then
        Print("Target probe can only be armed outside combat.")
        return
    end
    if type(RegisterStateDriver) ~= "function" then
        Print("Target probe unavailable: combat visibility driver is missing.")
        return
    end
    local existsOK, exists = pcall(UnitExists, "target")
    if not existsOK or not IsReadable(exists) or not exists then
        Print("Target a visible enemy nameplate first.")
        return
    end
    local root = NamePlateRootForUnit("target")
    local data = root and root.PlateSmithData or nil
    if not data and type(UnitIsUnit) == "function" then
        for _, candidate in pairs(active) do
            local ok, same = pcall(UnitIsUnit, candidate.unit, "target")
            if ok and IsReadable(same) and same == true then
                data = candidate
                break
            end
        end
    end
    if not data or type(data.unit) ~= "string" or not data.unit:match("^nameplate%d+$")
        or not data.root or active[data.unit] ~= data then
        Print("Target probe needs a currently tracked nameplate.")
        return
    end
    if not targetProbeButton then
        local button = CreateFrame("Button", "PlateSmithTargetProbeButton", UIParent,
            "SecureActionButtonTemplate,BackdropTemplate")
        button:SetSize(190, 34)
        button:SetPoint("CENTER", UIParent, "CENTER", 0, 110)
        button:SetFrameStrata("DIALOG")
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        button:SetBackdropColor(0.05, 0.06, 0.08, 0.9)
        button:SetBackdropBorderColor(0.2, 0.78, 1, 1)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        button.label = label
        button:RegisterForClicks("AnyUp")
        button:SetAttribute("type1", "target")
        button:SetScript("PostClick", function()
            if type(InCombatLockdown) == "function" and InCombatLockdown() then
                targetProbeStale = true
                return
            end
            local subject = targetProbeAction == "focus" and "focus" or "target"
            local ok, same = pcall(UnitIsUnit, subject, targetProbeUnit or "none")
            if ok and IsReadable(same) then
                Print(same and (subject .. " probe selected the bound nameplate.")
                    or (subject .. " probe did not select the bound nameplate."))
            else
                Print(subject .. " probe clicked; identity could not be read.")
            end
            DisarmTargetProbe()
        end)
        targetProbeButton = button
        PS._targetProbeButton = button
    else
        DisarmTargetProbe()
    end
    targetProbeUnit, targetProbeRoot, targetProbeStale, targetProbeAction =
        data.unit, data.root, nil, action
    targetProbeButton:SetAttribute("type1", action)
    targetProbeButton:SetAttribute("unit", data.unit)
    targetProbeButton.label:SetText("Test " .. action .. ": " .. data.unit)
    local ok = pcall(RegisterStateDriver, targetProbeButton, "visibility", "[combat] hide; show")
    if not ok then
        DisarmTargetProbe()
        Print("Target probe could not install its combat hide rule.")
        return
    end
    targetProbeButton:Show()
    Print("Probe bound to " .. data.unit .. ". Clear your target, then click the test button while the mob stays visible. It hides in combat.")
end

local function OnSlash(text)
    local command, value = text:lower():match("^(%S*)%s*(.-)$")
    if command == "" or command == "config" then
        if type(InCombatLockdown) == "function" and InCombatLockdown() then
            pendingOptionsOpen = true
            Print("Settings will open when combat ends.")
        elseif PS.OpenOptions then
            pendingOptionsOpen = false
            PS.OpenOptions()
        else
            Print("Settings are unavailable.")
        end
        return
    elseif command == "mode" and (value == "auto" or value == "own" or value == "overlay") then
        db.mode = value
    elseif command == "friendly" and (value == "names" or value == "full" or value == "off") then
        db.friendly = value
    elseif (command == "quest" or command == "threat") and (value == "on" or value == "off") then
        db[command] = value == "on"
    elseif command == "scale" and tonumber(value) then
        db.scale = math.max(0.7, math.min(1.5, tonumber(value)))
        db.plateProfiles.enemy.scale = db.scale
    elseif command == "console" then
        if not PS.ThreatConsole then
            Print("Threat Console is unavailable.")
            return
        elseif value == "on" then
            PS.ThreatConsole:Show()
        elseif value == "off" then
            PS.ThreatConsole:Hide()
        else
            PS.ThreatConsole:Toggle()
        end
        return
    elseif command == "status" then
        Print(string.format("mode=%s (%s), friendly=%s, quest=%s, threat=%s, scale=%.2f",
            db.mode, ExternalProvider() or "native", db.friendly, tostring(db.quest), tostring(db.threat), db.scale))
        return
    elseif command == "diagnose" then
        Diagnose()
        return
    elseif command == "playerprobe" then
        ProbePlayerPlate()
        return
    elseif command == "targetprobe" then
        if value == "off" then
            if type(InCombatLockdown) == "function" and InCombatLockdown() then
                targetProbeStale = true
                Print("Target probe will disarm when combat ends.")
            else
                DisarmTargetProbe()
            end
        elseif value == "" or value == "target" or value == "focus" then
            ArmTargetProbe(value == "" and "target" or value)
        else
            Print("/platesmith targetprobe [target|focus|off]")
        end
        return
    elseif command == "reset" then
        ResetSettings()
        if PS.Options and PS.Options.Refresh then PS.Options:Refresh() end
        Print("Settings reset.")
        return
    else
        Print("/platesmith mode auto|own|overlay")
        Print("/platesmith friendly names|full|off")
        Print("/platesmith quest on|off, threat on|off, scale 0.7-1.5")
        Print("/platesmith console [on|off], status, diagnose, playerprobe, targetprobe [target|focus|off], reset")
        return
    end
    RefreshAll()
    Print("Updated.")
end

local function OnUpdate(_, elapsed)
    if targetProbeUnit and (not active[targetProbeUnit]
        or active[targetProbeUnit].root ~= targetProbeRoot) then
        targetProbeStale = true
    end
    if targetProbeStale and (type(InCombatLockdown) ~= "function" or not InCombatLockdown()) then
        DisarmTargetProbe()
    end
    if pendingOptionsOpen and (type(InCombatLockdown) ~= "function" or not InCombatLockdown()) then
        pendingOptionsOpen = false
        if PS.OpenOptions then PS.OpenOptions() end
    end
    elapsedFast = elapsedFast + elapsed
    elapsedSlow = elapsedSlow + elapsed
    elapsedAuras = elapsedAuras + elapsed

    if next(activeCasts) then
        local castTime = GetTime() * 1000
        for data in pairs(activeCasts) do
            if data.restrictedFriendly then
                SafePlateUpdate(data, function(current) current.cast:SetValue(castTime) end)
            else
                data.cast:SetValue(castTime)
            end
        end
    end

    if elapsedFast >= 0.10 then
        elapsedFast = 0
        local now = GetTime()
        for _, data in pairs(active) do
            SafePlateUpdate(data, UpdateHealth)
            if data.hideNative and data.root and data.root.UnitFrame and data.root.UnitFrame.SetAlpha then
                data.root.UnitFrame:SetAlpha(0)
            end
            if data.beaconUntil then
                if now >= data.beaconUntil then
                    data.beaconUntil = nil
                    data.beacon:Hide()
                else
                    data.beacon:SetAlpha(0.45 + (0.55 * math.abs(math.sin(now * 7))))
                end
            end
            if data.targetPulseActive then
                local alpha = 0.25 + (0.45 * (0.5 + 0.5 * math.sin(now * 3)))
                for _, glow in ipairs(data.targetBarGlows) do glow.pulse:SetAlpha(alpha) end
                SetTargetTextGlow(data, 0.4 + alpha * 0.6, true)
            end
        end
        UpdateSpotlight(now)
    end

    if elapsedSlow >= 0.25 then
        elapsedSlow = 0
        for _, data in pairs(active) do
            SafePlateUpdate(data, UpdateTarget)
            SafePlateUpdate(data, UpdateThreat)
            SafePlateUpdate(data, UpdateTagged)
        end
    end
    if elapsedAuras >= 0.75 then
        elapsedAuras = 0
        for _, data in pairs(active) do SafePlateUpdate(data, UpdateAuras) end
    end
end

local eventFrame = CreateFrame("Frame")
local coreEvents = {
    "PLAYER_LOGIN",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "UNIT_TARGET",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LOGOUT",
    "GROUP_ROSTER_UPDATE",
    "UNIT_FACTION",
    "PLAYER_FLAGS_CHANGED",
    "UNIT_CLASSIFICATION_CHANGED",
    "GUILD_ROSTER_UPDATE",
    "PLAYER_GUILD_UPDATE",
    "FRIENDLIST_UPDATE",
    "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_LIST_SIZE_CHANGED",
    "RAID_TARGET_UPDATE",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_AURA",
}
for index = 1, #coreEvents do
    PS._RegisterEvent(eventFrame, coreEvents[index], "platesmith.nameplates")
end
eventFrame:SetScript("OnUpdate", OnUpdate)
eventFrame:SetScript("OnEvent", function(_, event, unit, detail)
    if event == "PLAYER_LOGIN" then
        local migrated = PlateSmithDB == nil and type(KeenPlatesDB) == "table"
        PlateSmithDB = NormalizeSettings(PlateSmithDB or KeenPlatesDB)
        db = PlateSmithDB
        if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
            pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        end
        ApplyFriendlyNamePolicy()
        if migrated then
            db.migrations = type(db.migrations) == "table" and db.migrations or {}
            db.migrations.keenplates = true
            Print("copied KeenPlates settings into PlateSmith.")
        end
        SLASH_PLATESMITH1 = "/platesmith"
        SLASH_PLATESMITH2 = "/ps"
        SLASH_PLATESMITH3 = "/keen"
        SlashCmdList.PLATESMITH = OnSlash
        DiagnosticUI.EnsureWindow()
        if PS.CreateOptions then PS.CreateOptions() end
        if PS.EnableModules then PS:EnableModules() end
        ImproveNativeNameFont()
        ScanPlates()
        Print("loaded " .. tostring(PS.RUNTIME_BUILD or "unknown build") .. ". Type /platesmith status for the active mode.")
    elseif not db then
        return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        AddPlate(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if IsReadable(unit) and unit == targetProbeUnit then
            if type(InCombatLockdown) == "function" and InCombatLockdown() then
                targetProbeStale = true
            else
                DisarmTargetProbe()
            end
        end
        RemovePlate(unit)
    elseif event == "UNIT_FACTION" or event == "PLAYER_FLAGS_CHANGED"
        or event == "UNIT_CLASSIFICATION_CHANGED" then
        RefreshAll()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE"
        or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE"
        or event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_INFO_CHANGED"
        or event == "BN_FRIEND_LIST_SIZE_CHANGED" then
        if PS.ThreatService then PS.ThreatService:MarkDirty() end
        RefreshAll()
    elseif event == "RAID_TARGET_UPDATE" or event == "PLAYER_FOCUS_CHANGED"
        or event == "UPDATE_MOUSEOVER_UNIT" or event == "UNIT_TARGET" then
        for _, data in pairs(active) do SafePlateUpdate(data, UpdateRaidIcon) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyFriendlyNamePolicy()
        RefreshAll()
        ScanPlates()
    elseif event == "PLAYER_LOGOUT" then
        RestoreFriendlyNameCVars(true)
        RestoreRestrictedFriendlyNameCVar(true)
        ApplyRestrictedFriendlyClassColour(false)
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" then
        if type(PS.ForEachModule) == "function" then PS:ForEachModule("OnQuestLogChanged", event) end
        RefreshQuestMarkers()
    elseif event == "UNIT_AURA" then
        if IsReadable(unit) and type(unit) == "string" then
            if active[unit] then
                SafePlateUpdate(active[unit], UpdateAuras)
            elseif type(UnitIsUnit) == "function" then
                for _, data in pairs(active) do
                    local ok, same = pcall(UnitIsUnit, data.unit, unit)
                    if ok and IsReadable(same) and same == true then SafePlateUpdate(data, UpdateAuras) end
                end
            end
        else
            -- Restricted aura events may carry a protected unit token. Refresh
            -- visible rows without branching or indexing on that token.
            for _, data in pairs(active) do SafePlateUpdate(data, UpdateAuras) end
        end
    elseif unit and active[unit] then
        SafePlateUpdate(active[unit], UpdateCast)
    end
end)

PS.Refresh = RefreshAll
PS.RefreshQuestMarkers = RefreshQuestMarkers
PS.GetSettings = function() return db end
PS.SetOption = SetOption
PS.GetLayout = GetLayout
PS.SetLayout = SetLayout
PS.SetComponentPosition = SetComponentPosition
PS.SetComponentScale = SetComponentScale
PS.SetLevelFollowName = SetLevelFollowName
PS.SetComponentVisibility = SetComponentVisibility
PS.GetPlateProfileSettings = GetProfileSettings
PS.GetDungeonEnemyOverride = function()
    return db and db.plateProfiles and db.plateProfiles.enemyDungeon or nil
end
PS.SetDungeonEnemyProfile = SetDungeonEnemyProfile
PS.GetDefaultLayout = GetDefaultLayout
PS.SetPlateProfileOption = SetProfileOption
PS.SetPlateValueSlot = SetProfileValueSlot
PS.SetPlateValueSlots = SetProfileValueSlots
PS.SetPlateProfileHealthColour = SetProfileHealthColour
PS.SetRelationshipColour = SetRelationshipColour
PS.ResetSettings = ResetSettings
PS.ApplyNameplateFont = ApplyNameplateFont
PS.ApplyThreatText = ApplyThreatText
PS.HighlightPlate = HighlightPlate
PS._Test = {
    Abbreviate = Abbreviate,
    FormatThreat = FormatThreat,
    FormatThreatRecord = FormatThreatRecord,
    ApplyThreatText = ApplyThreatText,
    ApplyLeadSituation = ApplyLeadSituation,
    CopyDefaults = CopyDefaults,
    IsReadable = IsReadable,
    NormalizeSettings = NormalizeSettings,
    MigrateSettings = MigrateSettings,
    QuestRelated = QuestRelated,
    QuestRelevance = QuestRelevance,
    FriendlyRelationship = FriendlyRelationship,
    SafeColourForUnit = SafeColourForUnit,
    PlayerDisplayName = PlayerDisplayName,
    UnitDisplayNameValue = UnitDisplayNameValue,
    ProfileKeyForUnit = ProfileKeyForUnit,
    ReadRaidTargetIndex = ReadRaidTargetIndex,
    ResolveRaidTargetIndex = ResolveRaidTargetIndex,
    AuraProbe = AuraProbe,
}
