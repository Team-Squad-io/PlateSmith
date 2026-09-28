-- Frame composition for one PlateSmith-owned nameplate.
local _, PS = ...
local L = PS.L
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

PS._CreatePlateFactory = function(context)
    local CreateAuraRow = context.CreateAuraRow
    local GetSettings = context.GetSettings
    local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT

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

    local OUTLINE_FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
    local function ReadFont(object)
        if not (object and object.GetFont) then return nil end
        local ok, path, height, flags = pcall(object.GetFont, object)
        if not ok then return nil end
        return type(path) == "string" and path or nil, type(height) == "number" and height or nil, flags or ""
    end

    -- The one route for plate text and Studio's preview: the plate font (settings.font) at size,
    -- then the part's style (font, outline). The default font is Blizzard's multilingual family
    -- (CJK glyphs), scaled to size. The client keeps a face set with SetFont over a font object
    -- set later, so text that had its own face (another profile's style) is given the family's
    -- face, height and outline explicitly when the family does not take.
    local function ApplyNameplateFont(fontString, size, style)
        if not fontString then return end
        size = tonumber(size) or 12
        fontString.plateSmithFontSize = size
        local settings = GetSettings and GetSettings()
        local path = PS.Media.FontPath(style and style.font or (settings and settings.font))
        local flags = OUTLINE_FLAGS[style and style.outline or "outline"] or "OUTLINE"
        local family = _G.SystemFont_Outline or _G.SystemFont_NamePlate
        local familyPath, familyHeight, familyFlags = ReadFont(family)
        if not path and family and fontString.SetFontObject and flags == "OUTLINE" then
            fontString:SetFontObject(family)
            local taken = not fontString.plateSmithOwnFace
            if not taken and familyPath then
                local nowPath, nowHeight, nowFlags = ReadFont(fontString)
                taken = nowPath == familyPath and nowHeight == familyHeight and nowFlags == familyFlags
            end
            if taken then
                fontString.plateSmithOwnFace = nil
                if fontString.SetTextScale then
                    fontString:SetTextScale(size / (familyHeight or 13))
                elseif fontString.SetFontHeight then
                    fontString:SetFontHeight(size)
                end
                return
            end
            flags = familyFlags or flags
        end
        if not fontString.SetFont then return end
        -- Never the text's current face: that may be the stale one.
        path = path or familyPath or STANDARD_TEXT_FONT
        if fontString.SetTextScale then fontString:SetTextScale(1) end
        fontString:SetFont(path, size, flags)
        fontString.plateSmithOwnFace = true
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
        health.plateSmithBackground = healthBackground
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
        power.plateSmithBackground = powerBackground
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

        -- Every part has its own frame over the plate, so the layout's drawing order (frame levels)
        -- can put any part over any other: text over a bar as easily as a bar over text.
        local layerFrames = { health = health, power = power }
        local function Layer(key)
            local frame = CreateFrame("Frame", nil, overlay)
            frame:SetAllPoints(overlay)
            layerFrames[key] = frame
            return frame
        end
        local name = Layer("name"):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("BOTTOM", health, "TOP", 0, 3)
        ApplyNameplateFont(name, 12)
        name:SetJustifyH("CENTER")
        local level = Layer("level"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        level:SetPoint("RIGHT", health, "LEFT", -4, 0)
        ApplyNameplateFont(level, 10)

        -- The unit's target, by name (target of target); hidden until the unit has one.
        local targetName = Layer("targetName"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ApplyNameplateFont(targetName, 10)
        targetName:SetTextColor(0.85, 0.85, 0.95)
        targetName:Hide()
        local guild = Layer("guild"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        guild:SetPoint("TOP", name, "BOTTOM", 0, -3)
        ApplyNameplateFont(guild, 10)
        guild:SetTextColor(0.68, 0.85, 0.76)
        guild:Hide()

        local threat = Layer("threat"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        threat:SetPoint("TOP", health, "BOTTOM", 0, -3)
        ApplyNameplateFont(threat, 10)

        local tagged = Layer("tagged"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tagged:SetPoint("TOP", health, "BOTTOM", 0, -3)
        tagged:SetText(L["TAGGED"])
        tagged:SetTextColor(0.72, 0.72, 0.72)
        ApplyNameplateFont(tagged, 9)
        tagged:Hide()

        local quest = Layer("quest"):CreateTexture(nil, "OVERLAY")
        quest:SetSize(16, 16)
        quest:SetPoint("RIGHT", name, "LEFT", -3, 0)
        quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        quest:SetBlendMode("BLEND")
        quest:Hide()

        local questLoot = Layer("questLoot"):CreateTexture(nil, "OVERLAY")
        questLoot:SetSize(16, 16)
        questLoot:SetPoint("CENTER", quest, "CENTER", 0, 0)
        questLoot:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        questLoot:SetMask("Interface\\AddOns\\PlateSmith\\Media\\QuestLootMask.png")
        questLoot:Hide()

        local raidIcon = Layer("raidIcon"):CreateTexture(nil, "OVERLAY")
        raidIcon:SetSize(18, 18)
        raidIcon:SetPoint("LEFT", name, "RIGHT", 3, 0)
        raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        raidIcon:Hide()

        local relationshipIcon = Layer("relationshipIcon"):CreateTexture(nil, "OVERLAY")
        relationshipIcon:SetSize(16, 16)
        relationshipIcon:SetPoint("BOTTOM", name, "TOP", 0, 3)
        relationshipIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
        relationshipIcon:Hide()

        local pvpIcon = Layer("pvpIcon"):CreateTexture(nil, "OVERLAY")
        pvpIcon:SetSize(18, 18)
        pvpIcon:SetPoint("LEFT", name, "RIGHT", 4, 0)
        pvpIcon:Hide()

        local classification = Layer("classification"):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        classification:SetPoint("RIGHT", level, "LEFT", -3, 0)
        ApplyNameplateFont(classification, 11)
        classification:Hide()
        -- The icon style draws Blizzard's own mark, centred where the text would be.
        local classificationIcon = layerFrames.classification:CreateTexture(nil, "OVERLAY")
        classificationIcon:SetSize(18, 18)
        classificationIcon:SetPoint("CENTER", classification, "CENTER", 0, 0)
        classificationIcon:Hide()

        -- Decorative only: these follow each visible bar, not the full plate canvas.
        local healthGlow = CreateTargetBarGlow(health)
        local powerGlow = CreateTargetBarGlow(power)

        -- The threat spotlight: a thin line with a faint glow just outside it (Lifecycle fits it).
        local beacon = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        beacon:SetAllPoints(overlay)
        beacon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        beacon:SetBackdropBorderColor(1, 0.78, 0.3, 1)
        local beaconGlow = CreateFrame("Frame", nil, beacon, "BackdropTemplate")
        beaconGlow:SetPoint("TOPLEFT", beacon, "TOPLEFT", -2, 2)
        beaconGlow:SetPoint("BOTTOMRIGHT", beacon, "BOTTOMRIGHT", 2, -2)
        beaconGlow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        beaconGlow:SetBackdropBorderColor(1, 0.78, 0.3, 0.22)
        beaconGlow:EnableMouse(false)
        local beaconLeft = beacon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        beaconLeft:SetPoint("RIGHT", beacon, "LEFT", -3, 0)
        beaconLeft:SetText(">>")
        beaconLeft:SetTextColor(1, 0.83, 0.22)
        local beaconRight = beacon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        beaconRight:SetPoint("LEFT", beacon, "RIGHT", 3, 0)
        beaconRight:SetText("<<")
        beaconRight:SetTextColor(1, 0.83, 0.22)
        -- The glow style: fading rings around the health bar only (Lifecycle places the frame).
        local beaconHalo = CreateFrame("Frame", nil, beacon)
        beaconHalo:EnableMouse(false)
        local haloRings = {}
        for index, ring in ipairs({ { 0, 1, 0.9 }, { 1, 2, 0.4 }, { 3, 2, 0.16 } }) do
            local frame = CreateFrame("Frame", nil, beaconHalo, "BackdropTemplate")
            frame:SetPoint("TOPLEFT", beaconHalo, "TOPLEFT", -ring[1], ring[1])
            frame:SetPoint("BOTTOMRIGHT", beaconHalo, "BOTTOMRIGHT", ring[1], -ring[1])
            frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = ring[2] })
            frame:SetBackdropBorderColor(1, 0.78, 0.3, ring[3])
            frame:EnableMouse(false)
            frame.plateSmithAlpha = ring[3]
            haloRings[index] = frame
        end
        beaconHalo:Hide()
        -- The arrow style: Blizzard's minimap quest arrow, flipped to point down at the name.
        local beaconArrow = beacon:CreateTexture(nil, "OVERLAY")
        beaconArrow:SetSize(18, 18)
        beaconArrow:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
        beaconArrow:SetTexCoord(0, 1, 1, 0)
        if beaconArrow.SetDesaturated then beaconArrow:SetDesaturated(true) end
        beaconArrow:Hide()
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
        cast.plateSmithBackground = castBackground
        CreateBorder(cast)
        local castName = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        castName:SetPoint("CENTER")
        ApplyNameplateFont(castName, 8)
        -- The time left inside the bar's right end, and the spell's icon beside the bar; the
        -- profile places both (Lifecycle's ApplyCastLayout).
        local castTime = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        castTime:SetPoint("RIGHT", cast, "RIGHT", -3, 0)
        ApplyNameplateFont(castTime, 8)
        castTime:Hide()
        local castIcon = cast:CreateTexture(nil, "OVERLAY")
        castIcon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
        castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castIcon:Hide()
        cast:Hide()
        local castGlow = CreateTargetBarGlow(cast)

        local buffs, buffIcons = CreateAuraRow(overlay)
        local debuffs, debuffIcons = CreateAuraRow(overlay)
        layerFrames.cast, layerFrames.buffs, layerFrames.debuffs = cast, buffs, debuffs
        local targetGlowTexts = { name, level, guild, threat, tagged, classification, castName, castTime }
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
            targetName = targetName,
            threat = threat,
            tagged = tagged,
            quest = quest,
            questLoot = questLoot,
            raidIcon = raidIcon,
            relationshipIcon = relationshipIcon,
            pvpIcon = pvpIcon,
            classification = classification,
            classificationIcon = classificationIcon,
            targetBorder = healthGlow.steady,
            targetHalo = healthGlow.pulse,
            targetBarGlows = { healthGlow, powerGlow, castGlow },
            targetGlowTexts = targetGlowTexts,
            targetShadowDefaults = targetShadowDefaults,
            beacon = beacon,
            beaconGlow = beaconGlow,
            beaconLeft = beaconLeft,
            beaconRight = beaconRight,
            beaconHalo = beaconHalo,
            beaconHaloRings = haloRings,
            beaconArrow = beaconArrow,
            cast = cast,
            castName = castName,
            castTime = castTime,
            castIcon = castIcon,
            buffs = buffs,
            buffIcons = buffIcons,
            debuffs = debuffs,
            debuffIcons = debuffIcons,
            layerFrames = layerFrames,
        }
    end

    return CreatePlate, ApplyNameplateFont
end
