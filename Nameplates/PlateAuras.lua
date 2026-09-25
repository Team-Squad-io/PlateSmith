-- Aura row creation and updates for PlateSmith-owned nameplates.
local _, PS = ...

PS._CreatePlateAuras = function(context)
    local IsReadable = context.IsReadable
    local HasValue = context.HasValue
    local GetSettings = context.GetSettings

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
        local db = GetSettings()
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

    return AURA_ICON_COUNT, CreateAuraRow, UpdateAuras
end
