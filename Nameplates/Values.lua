-- Custom parts (value slots) on owned plates: text from health, power, threat or a template, and
-- the bar, box and icon kinds. Rendered in one pass per plate flush.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local BAR_BACKGROUND = S.STYLE_DEFAULTS.background -- behind every bar (Schema defines it once)
local ThreatText = assert(PS.ThreatText, "PlateSmith ThreatText missing")

PS._CreatePlateValues = function(context)
    local IsReadable, HasValue = PS.Secret.IsReadable, PS.Secret.HasValue
    local GetSettings, Readers, Styles = context.GetSettings, context.Readers, context.Styles
    local IsDisplayNumber, ReadPercent = Readers.IsDisplayNumber, Readers.ReadPercent
    local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT
    local VALUE_KEYS, EMPTY = Styles.VALUE_KEYS, Styles.EMPTY
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

    local function RenderThreatValue(data, key, source, region)
        local info = data.threatInfo
        if not data.own or data.friendly or data.namesOnly or not GetSettings().threat
            or data.layout[key].visible == false or not info or not info.engaged then
            region:Hide()
            return
        end
        -- A readable number or nil (ThreatText.Gap), read once.
        local gap
        if source == "leadPercent" then gap = ThreatText.Gap(data.unit) end
        if source == "differential" then
            if IsReadable(info.lead) and type(info.lead) == "number" then
                region:SetText(ThreatText.Readable(nil, info.lead))
                region:Show()
            else
                region:Hide()
            end
        elseif gap then
            -- The signed gap the threat windows show, coloured by state like the threat text. When
            -- the numbers are protected there is no gap: the protected lead percentage shows (below).
            region:SetTextColor(ThreatText.StateColour(info))
            DisplayValue(region, "%+.0f", gap)
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
    -- percentages pass straight to the bar (SetValue takes them).
    local function RenderGraphic(data, key, slot, graphic)
        if not graphic or not data.valueTexts or graphic == data.valueTexts[key] then return end
        local position = data.layout[key]
        if not data.own or data.namesOnly or not position or position.visible == false or slot.source == "off" then
            graphic:Hide()
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
            if slot.kind then
                RenderGraphic(data, key, slot, region)
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

    -- Custom parts that are not text: a bar filled by a percentage, a box (a coloured rectangle) or
    -- an icon. Made on first use on the part's holder frame; the part's region (data.values[key])
    -- becomes the graphic, so placement, layering, hiding, rules and styles treat it like any part.
    local VALUE_ICONS = {
        raid1 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
        raid2 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
        raid3 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
        raid4 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
        raid5 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
        raid6 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
        raid7 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
        raid8 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
        skull = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
        quest = "Interface\\GossipFrame\\AvailableQuestIcon",
        sword = "Interface\\Icons\\INV_Sword_04",
        shield = "Interface\\Icons\\INV_Shield_06",
    }
    PS.ValueIconPaths = VALUE_ICONS
    local VALUE_GRAPHIC_SIZE = { bar = { 60, 4 }, box = { 40, 10 }, icon = { 16, 16 } }
    PS.ValueGraphicSize = VALUE_GRAPHIC_SIZE
    local WHITE_COLOUR = { r = 1, g = 1, b = 1 }

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
            graphic:SetTexture(VALUE_ICONS[slot.icon or "raid8"])
            graphic:SetVertexColor(colour.r, colour.g, colour.b)
        end
        data.values[key] = graphic
        return graphic
    end

    return { RenderValueSlots = RenderValueSlots, ApplyValueKind = ApplyValueKind }
end