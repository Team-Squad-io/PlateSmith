-- Frame composition for one PlateSmith-owned nameplate.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

PS._CreatePlateFactory = function(context)
    local CreateAuraRow = context.CreateAuraRow
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

    return CreatePlate, ApplyNameplateFont
end
