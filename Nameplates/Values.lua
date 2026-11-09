-- Custom parts (value slots) on owned plates: text from health, power, threat or a template, and
-- the bar, box and icon kinds. Rendered in one pass per plate flush.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Media = assert(PS.Media, "PlateSmith Media missing")
local BAR_BACKGROUND = S.STYLE_DEFAULTS.background -- behind every bar (Schema defines it once)
local ThreatText = assert(PS.ThreatText, "PlateSmith ThreatText missing")

-- Images (custom parts of kind icon; Studio's Image): the one route that draws a part's picture, for the plates and
-- Studio's preview alike. Draw sets the texture (its file or atlas), its coordinates (a kit piece's or the atlas's,
-- mirrored and turned: S.IMAGE), its blend, and a kit piece's nine-slice margins while it is fitted to a part. False
-- when the picture is missing on this install: the plates then draw nothing and the preview its placeholder. unit: the
-- plate's, for a unit picture (Media's unit:<name>; the preview passes none and draws its sample).
local ValueImage = {}
PS.ValueImage = ValueImage
-- The size a part of each kind starts at (a slot without its own Width and Height).
ValueImage.SIZE = { bar = { 60, 4 }, box = { 40, 10 }, icon = { 16, 16 } }
local IMAGE = S.IMAGE
function ValueImage.Draw(texture, slot, unit)
    local how, value, entry = Media.Picture(Media.SlotPicture(slot), unit)
    if not how then return false end
    local turns = (IMAGE.ROTATIONS[slot.rotation] or 0) + (entry and entry.turn or 0)
    if how == "atlas" then
        if not pcall(texture.SetAtlas, texture, value) then return false end
        -- The atlas's own coordinates, mirrored or turned only when asked (SetAtlas set them).
        if slot.flipX or slot.flipY or turns % 4 ~= 0 then
            local ok, info = pcall(C_Texture.GetAtlasInfo, value)
            if ok and type(info) == "table" and type(info.leftTexCoord) == "number" then
                local coords = { info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord }
                texture:SetTexCoord(Media.PictureCoords(coords, slot.flipX, slot.flipY, turns))
            end
        end
    else
        if not pcall(texture.SetTexture, texture, value) then return false end
        texture:SetTexCoord(Media.PictureCoords(entry and entry.coords, slot.flipX, slot.flipY, turns))
    end
    if texture.SetBlendMode then texture:SetBlendMode(entry and entry.blend or "BLEND") end
    local slice = slot.fit and entry and entry.slice
    if slice and texture.SetTextureSliceMargins then
        texture.plateSmithSliced = pcall(texture.SetTextureSliceMargins, texture, slice[1], slice[2], slice[3], slice[4])
    elseif texture.plateSmithSliced and texture.ClearTextureSlice then
        pcall(texture.ClearTextureSlice, texture)
        texture.plateSmithSliced = nil
    end
    return true
end

PS._CreatePlateValues = function(context)
    local IsReadable, HasValue = PS.Secret.IsReadable, PS.Secret.HasValue
    local Readers, Styles, RegionAlpha = context.Readers, context.Styles, context.RegionAlpha
    local IsDisplayNumber, ReadPercent = Readers.IsDisplayNumber, Readers.ReadPercent
    local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT
    local VALUE_KEYS, EMPTY = Styles.VALUE_KEYS, Styles.EMPTY
    local WHITE_COLOUR = { r = 1, g = 1, b = 1 }
    local function DisplayValue(region, format, first, second)
        local ok
        if HasValue(second) then
            ok = pcall(region.SetFormattedText, region, format, first, second)
        else
            ok = pcall(region.SetFormattedText, region, format, first)
        end
        if ok then region:Show() else region:SetText(""); region:Hide() end
    end

    -- Custom parts (value slots), rendered in one pass per flush. Each source reads what its update
    -- stored on the plate (health, power, threat) or the shared template reader.
    local THREAT_SOURCES = { threatPercent = true, leadPercent = true, rawThreat = true, differential = true }
    local HEALTH_SOURCES = { healthCurrent = true, healthValue = true, healthPercent = true }
    local POWER_SOURCES = { powerCurrent = true, powerValue = true, powerPercent = true }

    local function RenderResource(data, key, source, region)
        if not data.own or data.namesOnly or data.layout[key].visible == false
            or (POWER_SOURCES[source] and not data.power:IsShown()) then
            region:Hide()
            return
        end
        local current, maximum, api, power
        if HEALTH_SOURCES[source] then
            current, maximum, api, power = data.healthValue, data.healthMaxValue, UnitHealthPercent, false
        else
            current, maximum, api, power = data.powerValue, data.powerMaxValue, UnitPowerPercent, true
        end
        if source == "healthCurrent" or source == "powerCurrent" then
            if IsDisplayNumber(current) then DisplayValue(region, "%.0f", current) else region:Hide() end
        elseif source == "healthValue" or source == "powerValue" then
            if IsDisplayNumber(current) and IsDisplayNumber(maximum) then
                DisplayValue(region, "%.0f / %.0f", current, maximum)
            else
                region:Hide()
            end
        else
            local percent = ReadPercent(api, data.unit, current, maximum, power)
            if IsDisplayNumber(percent) then DisplayValue(region, "%.0f%%", percent) else region:Hide() end
        end
    end

    -- A plate holds no threat record while no layout needs threat (Lifecycle's PlateNeeds).
    local function RenderThreatValue(data, key, source, region)
        local info = data.threatInfo
        if not data.own or data.friendly or data.namesOnly
            or data.layout[key].visible == false or not info or not info.engaged then
            region:Hide()
            return
        end
        -- A readable number or nil (ThreatText.Gap), read once.
        local gap
        if source == "leadPercent" then gap = ThreatText.Gap(data.unit) end
        -- A kept gap is marked "~" (with its age when the profile shows it: ThreatText.MarkKept).
        if source == "differential" then
            if IsReadable(info.lead) and type(info.lead) == "number" then
                region:SetText(ThreatText.MarkKept(info, ThreatText.Readable(nil, info.lead)))
                region:Show()
            else
                region:Hide()
            end
        elseif gap then
            -- The signed gap the threat windows show, coloured by state like the threat text (grey
            -- or fading when kept, as the profile says). When the numbers are protected there is
            -- no gap: the protected lead percentage shows (below).
            ThreatText.ApplyStateColour(region, info)
            region:SetText(ThreatText.MarkKept(info, string.format("%+.0f", gap)))
            region:Show()
        elseif source == "rawThreat" then
            local raw, hasRaw = ThreatText.SinkRawThreat(info)
            if hasRaw then DisplayValue(region, "%s", raw) else region:Hide() end
        else
            local value
            if source == "threatPercent" then
                if info.hasOpaquePercent then value = info.percentOpaque else value = info.percent end
            elseif info.hasOpaqueLeadPercent then
                value = info.leadPercentOpaque
            else
                value = info.leadPercent
            end
            if IsDisplayNumber(value) then
                DisplayValue(region, source == "leadPercent" and PS.L["L%.0f%%"] or "%.0f%%", value)
            else
                region:Hide()
            end
        end
    end

    -- Bars fill from their percentage; boxes and icons show while their part is on. Protected
    -- percentages pass straight to the bar (SetValue takes them). A bar or icon from a module's source
    -- (Core/ModuleSources.lua) fills from its token or shows its reader's texture, hiding when it has none.
    local Sources = PS.ModuleSources
    -- An image's tint (S.IMAGE) from the unit: class (a player's, else its reaction), reaction or threat, each by the
    -- reader the target glow's colour modes use (one reader per fact), else its own colour. A protected colour goes
    -- only to the colour setter (Styles.OwnColour, which a rule's colour still wins over).
    local function PaintTint(data, slot, texture)
        local tint, has, r, g, b = slot.tint, false, nil, nil, nil
        if tint == "threat" then
            local Threat = PS.ThreatColours
            local colour = Threat.ForPlate(data, Threat.GLOW)
            if colour then
                has, r, g, b = true, colour.r, colour.g, colour.b
            else
                has, r, g, b = Threat.FoldForPlate(data, Threat.GLOW)
            end
        elseif tint == "class" or tint == "reaction" then
            if tint == "class" and PS.Secret.ReadBoolean(UnitIsPlayer, data.unit) == true then
                local cr, cg, cb, folded = PS.PlateColours.UnitClassChannels(data.unit)
                if folded ~= nil then has, r, g, b = true, cr, cg, cb end
            end
            local reaction = not has and PS.TargetGlow.Reaction(data.unit, data.friendly)
            if reaction then has, r, g, b = true, reaction[1], reaction[2], reaction[3] end
        end
        if not has then
            local colour = slot.colour or WHITE_COLOUR
            r, g, b = colour.r, colour.g, colour.b
        end
        Styles.OwnColour(texture, r, g, b)
    end

    local function RenderGraphic(data, key, slot, graphic, all, threat)
        if not graphic or not data.valueTexts or graphic == data.valueTexts[key] then return end
        local position = data.layout[key]
        local module = slot.source == "template" and Sources.SlotSource(slot) or nil
        if not data.own or data.namesOnly or not position or position.visible == false or slot.source == "off"
            or graphic.plateSmithMissing then
            graphic:Hide()
        elseif module and slot.kind == "bar" then
            local percent = Sources.BarPercent(module, Readers.Get(data)(Sources.Bar(module).token))
            if HasValue(percent) and pcall(graphic.SetValue, graphic, percent) then graphic:Show() else graphic:Hide() end
        elseif module then
            local texture = Sources.IconTexture(module, data.unit)
            if HasValue(texture) and pcall(graphic.SetTexture, graphic, texture) then graphic:Show() else graphic:Hide() end
        elseif slot.kind == "bar" then
            local percent
            if slot.source == "healthPercent" then
                percent = ReadPercent(UnitHealthPercent, data.unit, data.healthValue, data.healthMaxValue, false)
            elseif slot.source == "powerPercent" and data.power:IsShown() then
                percent = ReadPercent(UnitPowerPercent, data.unit, data.powerValue, data.powerMaxValue, true)
            elseif slot.source == "threatPercent" and data.threatInfo and data.threatInfo.engaged then
                if data.threatInfo.hasOpaquePercent then
                    percent = data.threatInfo.percentOpaque
                else
                    percent = data.threatInfo.percent
                end
            end
            if HasValue(percent) and pcall(graphic.SetValue, graphic, percent) then graphic:Show() else graphic:Hide() end
        else
            -- A tint from the unit follows a new unit (all) and, by threat, threat.
            local tint = slot.kind == "icon" and slot.tint
            if tint and tint ~= "bar" and (all or (threat and tint == "threat")) then PaintTint(data, slot, graphic) end
            graphic:Show()
        end
    end

    -- Whether a template reads a kind that changed (or reads something with no event of its own).
    local function TemplateChanged(reads, kinds)
        if not reads or reads.volatile then return true end
        for kind in pairs(kinds) do
            if reads[kind] then return true end
        end
        return false
    end

    -- kinds: what changed (Lifecycle's MarkValues): health, power and threat sources follow their
    -- kind; a template follows a kind it reads (data.reads.slots), or any change without a kind.
    local function RenderValueSlots(data, kinds)
        local all = kinds.all
        local health, power, threat = all or kinds.health, all or kinds.power, all or kinds.threat
        local everyTemplate = all or kinds.any
        local slotReads = data.reads and data.reads.slots or EMPTY
        local slots, values = data.profile.valueSlots, data.values
        -- A names-only or unowned plate shows no custom parts: hidden once, then nothing to do
        -- until the plate is laid out again (ApplyLayout clears valuesCleared).
        if not data.own or data.namesOnly then
            if data.valuesCleared then return end
            data.valuesCleared = true
            for index = 1, VALUE_SLOT_COUNT do
                local key = VALUE_KEYS[index]
                local region = values[key]
                if region then region:Hide() end
                local text = data.valueTexts and data.valueTexts[key]
                if text and text ~= region then text:Hide() end
            end
            return
        end
        data.valuesCleared = nil
        local resources = health or power
        for index = 1, VALUE_SLOT_COUNT do
            local key = VALUE_KEYS[index]
            local slot = slots[key]
            local source = slot.source
            local region = values[key]
            -- No region: a part this plate's layout does not use, never made (Lifecycle).
            if region then
                if slot.kind then
                    RenderGraphic(data, key, slot, region, all, threat)
                elseif not region.SetText then
                    -- Still the picture of the image the part was (a decoration set's text put in its slot): hidden
                    -- until the plate's appearance gives it its text again (ApplyValueKind).
                    region:Hide()
                elseif source == "template" then
                    if not data.own or data.namesOnly or data.layout[key].visible == false or not slot.template then
                        region:Hide()
                    elseif everyTemplate or TemplateChanged(slotReads[key], kinds) then
                        region:SetShown(PS.Template.Apply(region, slot.template, Readers.Get(data)))
                    end
                elseif THREAT_SOURCES[source] then
                    if threat then RenderThreatValue(data, key, source, region) end
                elseif HEALTH_SOURCES[source] then
                    if health then RenderResource(data, key, source, region) end
                elseif POWER_SOURCES[source] then
                    if power then RenderResource(data, key, source, region) end
                elseif resources then
                    region:Hide()
                end
            end
        end
    end

    -- Custom parts that are not text: a bar filled by a percentage, a box (a coloured rectangle) or
    -- an image (ValueImage). Made on first use on the part's holder frame; the part's region (data.values[key])
    -- becomes the graphic, so placement, layering, hiding, rules and styles treat it like any part.
    local VALUE_GRAPHIC_SIZE = ValueImage.SIZE

    -- An image tinted by its bar (tint "bar") takes every colour that bar is given: one hook per bar, made the first
    -- time an image asks, runs as PlateSmith colours it (on events, never polled). The colour may be protected: it is
    -- only handed to the image's setter.
    local function OnBarColour(bar, r, g, b)
        for texture in pairs(bar.plateSmithTinted) do
            if texture.plateSmithTintBar == bar then Styles.OwnColour(texture, r, g, b) end
        end
    end
    local function TintFromBar(data, key, texture)
        local old = texture.plateSmithTintBar
        if old then old.plateSmithTinted[texture], texture.plateSmithTintBar = nil, nil end
        local position = data.layout and data.layout[key]
        local parent = position and position.parent
        local bar = parent and (Styles.IS_VALUE_KEY[parent] and data.values[parent] or data[parent])
        if type(bar) ~= "table" or not bar.GetStatusBarColor then return false end
        if not bar.plateSmithTinted then
            bar.plateSmithTinted = {}
            hooksecurefunc(bar, "SetStatusBarColor", OnBarColour)
        end
        bar.plateSmithTinted[texture], texture.plateSmithTintBar = true, bar
        local ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
        if ok then Styles.OwnColour(texture, r, g, b) end
        return ok
    end

    local function ValueGraphic(data, key, kind)
        data.valueGraphics = data.valueGraphics or {}
        local graphics = data.valueGraphics[key] or {}
        data.valueGraphics[key] = graphics
        if graphics[kind] then return graphics[kind] end
        local holder = data.valueHolders[key]
        local graphic
        if kind == "bar" then
            graphic = CreateFrame("StatusBar", nil, holder)
            graphic:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            graphic:SetMinMaxValues(0, 100)
            local background = graphic:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints(graphic)
            background:SetColorTexture(BAR_BACKGROUND.r, BAR_BACKGROUND.g, BAR_BACKGROUND.b, BAR_BACKGROUND.a)
            graphic.plateSmithBackground = background
        else
            graphic = holder:CreateTexture(nil, "ARTWORK")
        end
        graphic:Hide()
        graphics[kind] = graphic
        return graphic
    end

    -- Puts key's region in place for its kind: the text, or the graphic (the text hidden).
    local function ApplyValueKind(data, key, slot)
        data.valueTexts = data.valueTexts or {}
        local text = data.valueTexts[key] or data.values[key]
        data.valueTexts[key] = text
        local kind = slot.kind
        for graphicKind, graphic in pairs(data.valueGraphics and data.valueGraphics[key] or EMPTY) do
            if graphicKind ~= kind then graphic:Hide() end
        end
        if not kind then
            data.values[key] = text
            return text
        end
        text:Hide()
        local graphic = ValueGraphic(data, key, kind)
        local size = VALUE_GRAPHIC_SIZE[kind]
        graphic:SetSize(slot.width or size[1], slot.height or size[2])
        local colour = slot.colour or WHITE_COLOUR
        if kind == "bar" then
            graphic:SetStatusBarColor(colour.r, colour.g, colour.b)
        elseif kind == "box" then
            graphic:SetColorTexture(colour.r, colour.g, colour.b, 0.85)
        else
            -- A module's icon shows its reader's texture (RenderGraphic): drawn whole.
            if slot.source == "template" and Sources.SlotSource(slot) then
                graphic:SetTexCoord(0, 1, 0, 1)
                graphic.plateSmithMissing = nil
            else
                graphic.plateSmithMissing = not ValueImage.Draw(graphic, slot, data.unit) or nil
            end
            local tint = slot.tint
            if tint ~= "bar" and graphic.plateSmithTintBar then
                graphic.plateSmithTintBar.plateSmithTinted[graphic], graphic.plateSmithTintBar = nil, nil
            end
            if not tint then
                graphic.plateSmithOwnColour = nil
                graphic:SetVertexColor(colour.r, colour.g, colour.b)
            elseif tint ~= "bar" or not TintFromBar(data, key, graphic) then
                PaintTint(data, slot, graphic)
            end
        end
        -- Its own opacity, under its rules' and a hidden parent's (Placement's RegionAlpha).
        if kind ~= "bar" and graphic.plateSmithOwnAlpha ~= slot.alpha then
            graphic.plateSmithOwnAlpha = slot.alpha
            graphic:SetAlpha(RegionAlpha(graphic))
        end
        data.values[key] = graphic
        return graphic
    end

    return { RenderValueSlots = RenderValueSlots, ApplyValueKind = ApplyValueKind }
end