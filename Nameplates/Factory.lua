-- Frame composition for one PlateSmith-owned nameplate.
local _, PS = ...
local L = PS.L
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local BAR_BACKGROUND = S.STYLE_DEFAULTS.background -- behind every bar (Schema defines it once)

-- A frame edged with four plain textures, not a backdrop: plate frames can have a size the client
-- keeps secret, and Blizzard's Backdrop works out texture coordinates from its size on every resize
-- (it errors on a secret width). SetBackdropBorderColor keeps the backdrop call its callers use.
local function SetEdgeColour(frame, red, green, blue, alpha)
    for _, edge in ipairs(frame.plateSmithEdges) do edge:SetColorTexture(red, green, blue, alpha or 1) end
end
local function SetEdgeSize(frame, size)
    local edges = frame.plateSmithEdges
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    top:SetHeight(size) bottom:SetHeight(size) left:SetWidth(size) right:SetWidth(size)
    frame.plateSmithEdgeSize = size
end
function PS.EdgeFrame(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    local top, bottom = frame:CreateTexture(nil, "BORDER"), frame:CreateTexture(nil, "BORDER")
    local left, right = frame:CreateTexture(nil, "BORDER"), frame:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", frame, "TOPLEFT") top:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    left:SetPoint("TOPLEFT", frame, "TOPLEFT") left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT") right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    frame.plateSmithEdges = { top, bottom, left, right }
    frame.SetBackdropBorderColor, frame.SetEdgeSize = SetEdgeColour, SetEdgeSize
    SetEdgeSize(frame, size or 1)
    return frame
end
local EdgeFrame = PS.EdgeFrame

PS._CreatePlateFactory = function(context)
    local CreateAuraRow = context.CreateAuraRow
    local GetSettings = context.GetSettings

    local function CreateBorder(parent)
        local border = EdgeFrame(parent, 1)
        border:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
        border:SetBackdropBorderColor(0.05, 0.05, 0.05, 1)
        return border
    end

    local function CreateTargetBarGlow(bar)
        -- Keep both layers attached to the bar itself, never to the whole plate canvas.
        local steady = EdgeFrame(bar, 1)
        steady:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
        steady:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
        steady:SetBackdropBorderColor(1, 0.72, 0.16, 0.65)
        steady:EnableMouse(false)
        steady:Hide()

        local pulse = EdgeFrame(bar, 2)
        pulse:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 3)
        pulse:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 3, -3)
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
    local ReadFont = PS.Media.ReadFont

    -- The one route for plate text and Studio's preview: the plate font (settings.font) at the part's
    -- Font size (style.fontSize, points; without one, size: Auto) times the profile's text size
    -- (settings.textScale), then the part's style (font, outline). plateSmithFontSize keeps the
    -- part's Auto size, so applying it again never scales twice.
    -- The default font is Blizzard's multilingual family (CJK glyphs), scaled to size. The client
    -- keeps a face set with SetFont over a font object set later, so text that had its own face
    -- (another profile's style) is given the family's face, height and outline explicitly when the
    -- family does not take.
    local function ApplyNameplateFont(fontString, size, style)
        if not fontString then return end
        size = tonumber(size) or 12
        fontString.plateSmithFontSize = size
        local settings = GetSettings and GetSettings()
        size = S.ScaledFontSize(S.StyledFontSize(size, style), settings and settings.textScale)
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
        -- Never the text's current face: that may be the stale one. A chosen face or outline keeps
        -- Blizzard's faces for other alphabets (Media.FontFamily); SetFont only where that cannot be.
        path = path or familyPath
        if path and PS.Media.SetFamilyFont(fontString, path, size, flags) then return end
        if not fontString.SetFont then return end
        path = path or STANDARD_TEXT_FONT
        if fontString.SetTextScale then fontString:SetTextScale(1) end
        fontString:SetFont(path, size, flags)
        fontString.plateSmithOwnFace = true
    end

    -- Plates built ahead (spares) wait under this hidden frame of ours until a nameplate takes one.
    local spareHolder
    local function SpareHolder()
        if not spareHolder then
            spareHolder = CreateFrame("Frame", nil, UIParent)
            spareHolder:Hide()
        end
        return spareHolder
    end

    -- Puts a plate on its nameplate: its overlay (ours, never Blizzard's) parented to the root,
    -- centred and levelled over it. Once attached a plate stays with that root (root.PlateSmithData),
    -- as the client reuses the root.
    local function AttachPlate(data, root)
        local overlay = data.overlay
        if overlay:GetParent() ~= root then overlay:SetParent(root) end
        overlay:ClearAllPoints()
        overlay:SetPoint("CENTER", root, "CENTER", 0, 0)
        overlay:SetFrameLevel((root:GetFrameLevel() or 0) + 20)
        data.root = root
    end

    -- A part's own frame over the plate (layerFrames[key]).
    local function Layer(overlay, layerFrames, key)
        local frame = CreateFrame("Frame", nil, overlay)
        frame:SetAllPoints(overlay)
        layerFrames[key] = frame
        return frame
    end

    -- A plate is built in two halves, in one order: StartPlate makes its frame, bars, texts and
    -- quest marks, FinishPlate its icons, cast bar, aura rows and text shadows. CreatePlate runs both
    -- at once; a spare is built one half a pass and taken only once finished. root nil: a spare,
    -- built ahead for a nameplate the client has not made yet (AttachPlate).
    local function StartPlate(root)
        local overlay = CreateFrame("Frame", nil, root or SpareHolder())
        overlay:SetSize(128, 52)
        if root then
            overlay:SetPoint("CENTER", root, "CENTER", 0, 0)
            overlay:SetFrameLevel((root:GetFrameLevel() or 0) + 20)
        end

        local health = CreateFrame("StatusBar", nil, overlay)
        health:SetSize(112, 10)
        health:SetPoint("CENTER", overlay, "CENTER", 0, 0)
        health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        health:SetMinMaxValues(0, 1)
        health:SetValue(1)
        local healthBackground = health:CreateTexture(nil, "BACKGROUND")
        healthBackground:SetAllPoints()
        healthBackground:SetColorTexture(BAR_BACKGROUND.r, BAR_BACKGROUND.g, BAR_BACKGROUND.b, BAR_BACKGROUND.a)
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
        powerBackground:SetColorTexture(BAR_BACKGROUND.r, BAR_BACKGROUND.g, BAR_BACKGROUND.b, BAR_BACKGROUND.a)
        power.plateSmithBackground = powerBackground
        CreateBorder(power)
        power:Hide()

        -- Custom parts are made when a layout first uses one (EnsureValueSlot).
        local values, valueHolders = {}, {}

        -- Every part has its own frame over the plate, so the layout's drawing order (frame levels)
        -- can put any part over any other: text over a bar as easily as a bar over text.
        local layerFrames = { health = health, power = power }
        local name = Layer(overlay, layerFrames, "name"):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("BOTTOM", health, "TOP", 0, 3)
        ApplyNameplateFont(name, 12)
        name:SetJustifyH("CENTER")
        local level = Layer(overlay, layerFrames, "level"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        level:SetPoint("RIGHT", health, "LEFT", -4, 0)
        ApplyNameplateFont(level, 10)

        -- The unit's target, by name (target of target); hidden until the unit has one.
        local targetName = Layer(overlay, layerFrames, "targetName"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ApplyNameplateFont(targetName, 10)
        targetName:SetTextColor(0.85, 0.85, 0.95)
        targetName:Hide()
        local guild = Layer(overlay, layerFrames, "guild"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        guild:SetPoint("TOP", name, "BOTTOM", 0, -3)
        ApplyNameplateFont(guild, 10)
        guild:SetTextColor(0.68, 0.85, 0.76)
        guild:Hide()

        local threat = Layer(overlay, layerFrames, "threat"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        threat:SetPoint("TOP", health, "BOTTOM", 0, -3)
        ApplyNameplateFont(threat, 10)

        local tagged = Layer(overlay, layerFrames, "tagged"):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tagged:SetPoint("TOP", health, "BOTTOM", 0, -3)
        tagged:SetText(L["TAGGED"])
        tagged:SetTextColor(0.72, 0.72, 0.72)
        ApplyNameplateFont(tagged, 9)
        tagged:Hide()

        local quest = Layer(overlay, layerFrames, "quest"):CreateTexture(nil, "OVERLAY")
        quest:SetSize(16, 16)
        quest:SetPoint("RIGHT", name, "LEFT", -3, 0)
        quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        quest:SetBlendMode("BLEND")
        quest:Hide()

        local questLoot = Layer(overlay, layerFrames, "questLoot"):CreateTexture(nil, "OVERLAY")
        questLoot:SetSize(16, 16)
        questLoot:SetPoint("CENTER", quest, "CENTER", 0, 0)
        questLoot:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        questLoot:SetMask("Interface\\AddOns\\PlateSmith\\Media\\QuestLootMask.png")
        questLoot:Hide()

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
            layerFrames = layerFrames,
        }
    end

    local function FinishPlate(data)
        local overlay, health, layerFrames, name, level = data.overlay, data.health, data.layerFrames, data.name, data.level
        local raidIcon = Layer(overlay, layerFrames, "raidIcon"):CreateTexture(nil, "OVERLAY")
        raidIcon:SetSize(18, 18)
        raidIcon:SetPoint("LEFT", name, "RIGHT", 3, 0)
        raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        raidIcon:Hide()

        local relationshipIcon = Layer(overlay, layerFrames, "relationshipIcon"):CreateTexture(nil, "OVERLAY")
        relationshipIcon:SetSize(16, 16)
        relationshipIcon:SetPoint("BOTTOM", name, "TOP", 0, 3)
        relationshipIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
        relationshipIcon:Hide()

        local pvpIcon = Layer(overlay, layerFrames, "pvpIcon"):CreateTexture(nil, "OVERLAY")
        pvpIcon:SetSize(18, 18)
        pvpIcon:SetPoint("LEFT", name, "RIGHT", 4, 0)
        pvpIcon:Hide()

        local classification = Layer(overlay, layerFrames, "classification"):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        classification:SetPoint("RIGHT", level, "LEFT", -3, 0)
        ApplyNameplateFont(classification, 11)
        classification:Hide()
        -- The icon style draws Blizzard's own mark, centred where the text would be.
        local classificationIcon = layerFrames.classification:CreateTexture(nil, "OVERLAY")
        classificationIcon:SetSize(18, 18)
        classificationIcon:SetPoint("CENTER", classification, "CENTER", 0, 0)
        classificationIcon:Hide()
        data.raidIcon, data.relationshipIcon, data.pvpIcon = raidIcon, relationshipIcon, pvpIcon
        data.classification, data.classificationIcon = classification, classificationIcon

        local cast = CreateFrame("StatusBar", nil, overlay)
        cast:SetSize(112, 7)
        cast:SetPoint("TOP", health, "BOTTOM", 0, -3)
        cast:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        cast:SetStatusBarColor(0.95, 0.68, 0.16)
        cast:SetMinMaxValues(0, 1)
        cast:SetValue(0)
        local castBackground = cast:CreateTexture(nil, "BACKGROUND")
        castBackground:SetAllPoints()
        castBackground:SetColorTexture(BAR_BACKGROUND.r, BAR_BACKGROUND.g, BAR_BACKGROUND.b, BAR_BACKGROUND.a)
        cast.plateSmithBackground = castBackground
        CreateBorder(cast)
        local castName = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        castName:SetPoint("CENTER")
        ApplyNameplateFont(castName, 8)
        -- The time left inside the bar's right end, and the spell's icon beside the bar; the
        -- profile places both (Placement's CastLayout).
        local castTime = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        castTime:SetPoint("RIGHT", cast, "RIGHT", -3, 0)
        ApplyNameplateFont(castTime, 8)
        castTime:Hide()
        local castIcon = cast:CreateTexture(nil, "OVERLAY")
        castIcon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
        castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castIcon:Hide()
        cast:Hide()

        -- The rows' icons are made the first time a row is shown (Auras.lua).
        local buffs, buffIcons = CreateAuraRow(overlay)
        local debuffs, debuffIcons = CreateAuraRow(overlay)
        layerFrames.cast, layerFrames.buffs, layerFrames.debuffs = cast, buffs, debuffs
        local targetGlowTexts = { data.name, data.level, data.guild, data.threat, data.tagged, data.classification,
            castName, castTime }
        local targetShadowDefaults = {}
        for _, region in ipairs(targetGlowTexts) do
            targetShadowDefaults[region] = CaptureTextShadow(region)
        end

        -- The target glow (targetBarGlows, targetBorder, targetHalo) and the threat spotlight
        -- (beacon...) are made on first use (EnsureTargetGlows, EnsureBeacon).
        data.targetGlowTexts, data.targetShadowDefaults = targetGlowTexts, targetShadowDefaults
        data.cast, data.castName, data.castTime, data.castIcon = cast, castName, castTime, castIcon
        data.buffs, data.buffIcons, data.debuffs, data.debuffIcons = buffs, buffIcons, debuffs, debuffIcons
        return data
    end

    local function CreatePlate(root) return FinishPlate(StartPlate(root)) end

    -- Parts a plate may never need are made the first time it does, so a new plate frame (a city of
    -- names-only players, most enemies) costs only what it draws. Each returns the part, made once.

    -- A custom part's holder and text (value1..valueN). The holder sits on the root so its layer can
    -- go behind the overlay; it takes the overlay's scale and the plate's spotlight fade as made.
    local function EnsureValueSlot(data, key)
        local holder = data.valueHolders[key]
        if holder then return holder end
        holder = CreateFrame("Frame", nil, data.root)
        holder:SetAllPoints(data.overlay)
        holder:SetScale(data.profile and data.profile.scale or 1)
        if data.spotlightAlpha and data.spotlightAlpha ~= 1 then holder:SetAlpha(data.spotlightAlpha) end
        local value = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("CENTER", data.health, "CENTER")
        value:SetJustifyH("CENTER")
        ApplyNameplateFont(value, 9)
        value:Hide()
        data.targetShadowDefaults[value] = CaptureTextShadow(value)
        data.values[key] = value
        data.valueHolders[key] = holder
        return holder
    end

    -- The target highlight on each bar: decorative only, following the bar, not the plate canvas.
    local function EnsureTargetGlows(data)
        local glows = data.targetBarGlows
        if glows then return glows end
        local healthGlow = CreateTargetBarGlow(data.health)
        glows = { healthGlow, CreateTargetBarGlow(data.power), CreateTargetBarGlow(data.cast) }
        data.targetBarGlows, data.targetBorder, data.targetHalo = glows, healthGlow.steady, healthGlow.pulse
        return glows
    end

    -- The threat spotlight: a thin line with a faint glow just outside it (Lifecycle fits it).
    local function EnsureBeacon(data)
        if data.beacon then return data.beacon end
        local beacon = EdgeFrame(data.overlay, 1)
        beacon:SetAllPoints(data.overlay)
        beacon:SetBackdropBorderColor(1, 0.78, 0.3, 1)
        local beaconGlow = EdgeFrame(beacon, 2)
        beaconGlow:SetPoint("TOPLEFT", beacon, "TOPLEFT", -2, 2)
        beaconGlow:SetPoint("BOTTOMRIGHT", beacon, "BOTTOMRIGHT", 2, -2)
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
            local frame = EdgeFrame(beaconHalo, ring[2])
            frame:SetPoint("TOPLEFT", beaconHalo, "TOPLEFT", -ring[1], ring[1])
            frame:SetPoint("BOTTOMRIGHT", beaconHalo, "BOTTOMRIGHT", ring[1], -ring[1])
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
        data.beacon, data.beaconGlow, data.beaconLeft, data.beaconRight = beacon, beaconGlow, beaconLeft, beaconRight
        data.beaconHalo, data.beaconHaloRings, data.beaconArrow = beaconHalo, haloRings, beaconArrow
        return beacon
    end

    -- The spotlight's chevrons follow the plate font and the text size; with Blizzard's font at
    -- 100% they keep the large font object they were made with. Set only when either changes. A face
    -- set with SetFont outlasts a later font object, so going back sets the object's own face too.
    local function ApplyChevronFont(data)
        local settings = GetSettings and GetSettings()
        local font, textScale = settings and settings.font, settings and settings.textScale or 1
        if not data.beaconLeft or (data.beaconFont == font and data.beaconTextScale == textScale) then return end
        data.beaconFont, data.beaconTextScale = font, textScale
        local large = _G.GameFontNormalLarge
        local path = PS.Media.FontPath(font)
        local own = path ~= nil or textScale ~= 1
        local largePath, largeHeight, largeFlags = ReadFont(large)
        for _, chevron in ipairs({ data.beaconLeft, data.beaconRight }) do
            if large and chevron.SetFontObject then chevron:SetFontObject(large) end
            if chevron.SetFont and (own or chevron.plateSmithOwnFace) then
                chevron:SetFont(path or largePath or STANDARD_TEXT_FONT, S.ScaledFontSize(largeHeight or 16, textScale),
                    largeFlags or "")
            end
            chevron.plateSmithOwnFace = own or nil
        end
    end

    return {
        CreatePlate = CreatePlate, StartPlate = StartPlate, FinishPlate = FinishPlate, AttachPlate = AttachPlate,
        ApplyNameplateFont = ApplyNameplateFont, ApplyChevronFont = ApplyChevronFont,
        EnsureValueSlot = EnsureValueSlot, EnsureTargetGlows = EnsureTargetGlows, EnsureBeacon = EnsureBeacon,
    }
end
