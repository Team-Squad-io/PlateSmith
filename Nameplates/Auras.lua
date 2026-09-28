-- Aura row creation and updates for PlateSmith-owned nameplates.
local _, PS = ...

-- The row frame is one line of the layout, centred on the component's position; each icon
-- is placed by its line and column. Right and left grow from that edge of the line,
-- centre keeps each line centred; further lines stack above (up) or below (down).
local function LayoutAuraRow(row, icons, layout, shown)
    local size, step, columns = layout.size, layout.size + layout.spacing, layout.columns
    local full = columns * size + (columns - 1) * layout.spacing
    row:SetSize(full, size)
    local lineStep = (layout.growY == "down" and -1 or 1) * step
    for index = 1, #icons do
        local icon = icons[index]
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        local line, column = math.floor((index - 1) / columns), (index - 1) % columns
        local inLine = math.max(1, math.min(columns, (shown or layout.count) - line * columns))
        local left
        if layout.growX == "left" then
            left = full / 2 - size - column * step
        elseif layout.growX == "centre" then
            left = -(inLine * size + (inLine - 1) * layout.spacing) / 2 + column * step
        else
            left = -full / 2 + column * step
        end
        icon:SetPoint("CENTER", row, "CENTER", left + size / 2, line * lineStep)
    end
end

-- Shared with Blueprint Studio's preview, so it lays auras out exactly as the plates do.
PS.LayoutAuraRow = LayoutAuraRow

PS._CreatePlateAuras = function(context)
    local Secret = PS.Secret
    local IsReadable, HasValue, SameUnit = Secret.IsReadable, Secret.HasValue, Secret.SameUnit
    local GetSettings, Counters = context.GetSettings, context.Counters

    -- A row holds up to this many icons; each plate type's auraLayouts says how many show and how.
    local AURA_ICON_COUNT = 8
    local DEFAULT_LAYOUT = { count = 4, columns = 4, size = 18, spacing = 2, growX = "right", growY = "up" }
    local COUNTDOWN_FONT = "Fonts\\FRIZQT__.TTF"
    local ICON_KEYS = { buffs = "buffIcons", debuffs = "debuffIcons" }
    local ROUTE_KEYS = { buffs = "buffsAuraRoute", debuffs = "debuffsAuraRoute" }
    local FILTERS = { buffs = { all = "HELPFUL", mine = "HELPFUL|PLAYER" },
        debuffs = { all = "HARMFUL", mine = "HARMFUL|PLAYER" } }
    -- Routes that are a readable, final answer: a row on one of these needs no polling.
    local SETTLED_ROUTES = { indexed = true, slots = true, legacy = true, ["indexed-none"] = true, disabled = true }

    -- Route strings from a bounded set of states, each built once.
    local indexedRoutes = setmetatable({}, { __index = function(cache, state)
        local route = "indexed-" .. state
        cache[state] = route
        return route
    end })
    local failedRoutes = {}
    local function FailedRoute(index, slots, legacy)
        local byIndex = failedRoutes[index] or {}
        failedRoutes[index] = byIndex
        local bySlots = byIndex[slots] or {}
        byIndex[slots] = bySlots
        local route = bySlots[legacy]
        if not route then
            route = "none:index=" .. index .. ",slots=" .. slots .. ",legacy=" .. legacy
            bySlots[legacy] = route
        end
        return route
    end
    local containerRoutes = {}
    local function ContainerRoute(route, state)
        local byRoute = containerRoutes[route] or {}
        containerRoutes[route] = byRoute
        local full = byRoute[state]
        if not full then
            full = route .. ",container=" .. state
            byRoute[state] = full
        end
        return full
    end

    local function Field(aura, key) return aura[key] end

    -- The countdown text sized to the icon so it never spills over; set only when the size changes.
    local function StyleCountdown(swipe, iconSize)
        local fontSize = math.max(8, math.floor(iconSize * 0.45))
        if swipe.plateSmithCountdownSize == fontSize then return end
        local text = swipe.GetRegions and swipe:GetRegions()
        if text and text.SetFont and text.GetObjectType and text:GetObjectType() == "FontString" then
            text:SetFont(COUNTDOWN_FONT, fontSize, "OUTLINE")
            text:ClearAllPoints()
            text:SetPoint("BOTTOMRIGHT", swipe, "BOTTOMRIGHT", 1, -1)
            swipe.plateSmithCountdownSize = fontSize
        end
    end

    local function DisableContainer(container)
        pcall(container.SetEnabled, container, false)
        pcall(container.Hide, container)
    end

    -- Each icon has a cooldown swipe that chips away as the aura runs out, and optionally its
    -- remaining time in the corner (the client's own short format: 9, 1m, 2h).
    local function CreateAuraRow(parent)
        local row = CreateFrame("Frame", nil, parent)
        local icons = {}
        for index = 1, AURA_ICON_COUNT do
            local icon = row:CreateTexture(nil, "OVERLAY")
            icon:Hide()
            icon.plateSmithShown = false
            local ok, swipe = pcall(CreateFrame, "Cooldown", nil, row, "CooldownFrameTemplate")
            if ok and swipe then
                swipe:SetAllPoints(icon)
                if swipe.SetDrawEdge then swipe:SetDrawEdge(false) end
                if swipe.SetReverse then swipe:SetReverse(true) end
                swipe:Hide()
                swipe.plateSmithShown = false
                icon.swipe = swipe
            end
            icons[index] = icon
        end
        LayoutAuraRow(row, icons, DEFAULT_LAYOUT)
        row:Hide()
        return row, icons
    end

    -- Swipes run only from readable, positive durations; anything protected shows no swipe
    -- rather than a guess. Only icons shown now or last time are visited. Returns the soonest
    -- readable expiration of a shown icon (nil: none is timed).
    local function ApplyAuraTimes(icons, shown, layout, previous)
        local soonest
        local hideNumbers = layout.showDuration == false
        for index = 1, math.max(shown, previous or AURA_ICON_COUNT) do
            local icon = icons[index]
            local swipe = icon.swipe
            if swipe then
                local duration, expiration
                if index <= shown then duration, expiration = icon.auraDuration, icon.auraExpiration end
                local timed = IsReadable(duration) and IsReadable(expiration) and type(duration) == "number"
                    and type(expiration) == "number" and duration > 0 and expiration > 0
                if timed then
                    if not soonest or expiration < soonest then soonest = expiration end
                    local start = expiration - duration
                    if swipe.plateSmithStart ~= start or swipe.plateSmithDuration ~= duration then
                        pcall(swipe.SetCooldown, swipe, start, duration)
                        swipe.plateSmithStart, swipe.plateSmithDuration = start, duration
                    end
                    if swipe.SetHideCountdownNumbers and swipe.plateSmithHideNumbers ~= hideNumbers then
                        swipe:SetHideCountdownNumbers(hideNumbers)
                        swipe.plateSmithHideNumbers = hideNumbers
                    end
                    StyleCountdown(swipe, layout.size)
                    if not swipe.plateSmithShown then
                        swipe:Show()
                        swipe.plateSmithShown = true
                    end
                elseif swipe.plateSmithStart or swipe.plateSmithShown ~= false then
                    if swipe.Clear then swipe:Clear() end
                    swipe.plateSmithStart, swipe.plateSmithDuration = nil, nil
                    swipe:Hide()
                    swipe.plateSmithShown = false
                end
            end
            icon.auraDuration, icon.auraExpiration = nil, nil
        end
        return soonest
    end

    -- A readable texture already on the icon is not set again.
    local function ShowIcon(icon, texture, duration, expiration)
        local readable = IsReadable(texture)
        if not (readable and icon.plateSmithTexture == texture) then
            if not pcall(icon.SetTexture, icon, texture) then return false end
            if readable then icon.plateSmithTexture = texture else icon.plateSmithTexture = nil end
        end
        if not icon.plateSmithShown then
            icon:Show()
            icon.plateSmithShown = true
        end
        icon.auraDuration, icon.auraExpiration = duration, expiration
        return true
    end

    local function HideIcons(icons, from, to)
        for index = from, to do
            local icon = icons[index]
            if icon.plateSmithShown ~= false then
                icon:Hide()
                icon.plateSmithShown = false
            end
        end
    end

    local function PopulateAuraIconsByIndex(api, unit, filter, icons, limit)
        if type(api) ~= "function" then return 0, "missing" end
        local shown = 0
        for index = 1, limit do
            local ok, aura = pcall(api, unit, index, filter)
            if not ok then return shown, "error" end
            if not IsReadable(aura) then return shown, "protected" end
            if aura == nil then break end
            -- The client performs the source filter. Never inspect sourceUnit: it
            -- can be protected in combat even when the icon is displayable.
            local iconOK, icon = pcall(Field, aura, "icon")
            if not iconOK then return shown, "icon-error" end
            if not HasValue(icon) then break end
            -- The times may be protected: kept without and/or, which would truth-test them.
            local durationOK, duration = pcall(Field, aura, "duration")
            if not durationOK then duration = nil end
            local expirationOK, expiration = pcall(Field, aura, "expirationTime")
            if not expirationOK then expiration = nil end
            if not ShowIcon(icons[index], icon, duration, expiration) then
                return shown, "texture-error"
            end
            shown = index
        end
        return shown, shown > 0 and "shown" or "none"
    end

    -- AuraUtil.ForEachAura's callback, made once: the row being filled is held here meanwhile.
    local slotIcons, slotLimit, slotShown = nil, 0, 0
    local function SlotCallback(_, icon, _, _, duration, expiration)
        if HasValue(icon) and ShowIcon(slotIcons[slotShown + 1], icon, duration, expiration) then
            slotShown = slotShown + 1
        end
        return slotShown >= slotLimit
    end

    local function PopulateAuraIconsBySlots(unit, filter, icons, limit)
        local iterate = AuraUtil and AuraUtil.ForEachAura
        if type(iterate) ~= "function" then return 0, "missing" end
        slotIcons, slotLimit, slotShown = icons, limit, 0
        local ok = pcall(iterate, unit, filter, limit, SlotCallback)
        local shown = slotShown
        slotIcons = nil
        return shown, not ok and "error" or shown > 0 and "shown" or "none"
    end

    local function PopulateAuraIconsLegacy(kind, unit, filter, icons, limit)
        local api = kind == "buffs" and UnitBuff or UnitDebuff
        if type(api) ~= "function" then return 0, "missing" end
        -- UnitBuff/UnitDebuff already imply HELPFUL/HARMFUL; their optional filter
        -- only needs the source restriction.
        local legacyFilter = filter:find("|PLAYER", 1, true) and "PLAYER" or nil
        local shown = 0
        for index = 1, limit do
            local ok, name, icon, _, _, duration, expiration = pcall(api, unit, index, legacyFilter)
            if not ok then return shown, "error" end
            if not HasValue(name) then break end
            if not HasValue(icon) then break end
            if not ShowIcon(icons[index], icon, duration, expiration) then return shown, "texture-error" end
            shown = index
        end
        return shown, shown > 0 and "shown" or "none"
    end

    -- An indexed read of a plate's own unit that errored in combat is not tried again on every
    -- event: until combat ends or the plate gets its next unit (data[INDEX_ERROR_KEYS[kind]]), the
    -- row goes straight to the other routes, as that read would.
    local INDEX_ERROR_KEYS = { buffs = "buffsIndexError", debuffs = "debuffsIndexError" }
    local function PopulateAuraIcons(kind, unit, filter, icons, limit, data)
        Counters.auraReads = Counters.auraReads + 1
        local errorKey = data and unit == data.unit and INDEX_ERROR_KEYS[kind]
        local shown, indexState = 0, "error"
        if not (errorKey and data[errorKey]) then
            local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
            shown, indexState = PopulateAuraIconsByIndex(api, unit, filter, icons, limit)
            if errorKey and shown == 0 and indexState == "error" and Secret.InCombat() then data[errorKey] = true end
        end
        if shown > 0 then return shown, "indexed" end
        -- A readable empty result or protected value is authoritative. Try other
        -- API shapes only when this API itself is missing or raises an error.
        if indexState ~= "error" and indexState ~= "missing" then
            return 0, indexedRoutes[indexState]
        end
        local slotState
        shown, slotState = PopulateAuraIconsBySlots(unit, filter, icons, limit)
        if shown > 0 then return shown, "slots" end
        local legacyState
        shown, legacyState = PopulateAuraIconsLegacy(kind, unit, filter, icons, limit)
        if shown > 0 then return shown, "legacy" end
        return 0, FailedRoute(indexState, slotState, legacyState)
    end

    -- The flow layout's start corner and growth for a layout, and the point the container is
    -- pinned to the row by. The flow layout has no centring of its own (Blizzard_CustomAuraContainer:
    -- each icon is anchored by the start corner), but when it lays out it sizes the container to
    -- what it placed. So a centred row pins the container by its middle edge and leaves its size
    -- to the client: the icons shown are centred without addon code reading how many there are
    -- (that count is the client's and may be protected). Further lines start at the widest line's
    -- left edge. Should a client not resize it, the container keeps the row's full-line width and a
    -- full line is still centred.
    local function FlowOf(layout)
        local x = layout.growX == "left" and -1 or 1
        local y = layout.growY == "down" and -1 or 1
        local corner
        if y < 0 then corner = x < 0 and "TOPRIGHT" or "TOPLEFT" else corner = x < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT" end
        local pin = corner
        if layout.growX == "centre" then pin = y < 0 and "TOP" or "BOTTOM" end
        return corner, x, y, pin
    end

    -- Group options are fixed once the group is added, so each layout shape has its own container
    -- on the row, made once and reused; built once per layout table.
    local signatures = setmetatable({}, { __mode = "k" })
    local function LayoutSignature(layout)
        local signature = signatures[layout]
        if not signature then
            signature = table.concat({ layout.count, layout.columns, layout.size, layout.spacing, layout.growX, layout.growY,
                tostring(layout.showDuration ~= false) }, ":")
            signatures[layout] = signature
        end
        return signature
    end

    local function BuildContainer(container, row, filter, layout, unit)
        local corner, growX, growY, pin = FlowOf(layout)
        container:SetEnabled(false)
        container:SetSize(row:GetWidth(), row:GetHeight())
        container:SetPoint(pin, row, pin, 0, 0)
        if container.SetIgnoreParentScale then container:SetIgnoreParentScale(false) end
        container:SetFrameStrata(row:GetFrameStrata())
        if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint(corner) end
        if container.SetFlowLayoutGrowthDirection then container:SetFlowLayoutGrowthDirection(growX, growY) end
        if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(row:GetWidth()) end
        container:AddAuraGroup("platesmith", filter, {
            maxFrameCount = layout.count,
            layout = { elementSpacing = layout.spacing, elementWidth = layout.size, elementHeight = layout.size },
            initializeFrame = function(button)
                button:SetSize(layout.size, layout.size)
                local icon = button:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints(button)
                button:SetIcon(icon)
                -- The client drives this swipe and countdown from the aura's own times,
                -- which stay secret to addon code in combat.
                local swipe = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                swipe:SetAllPoints(button)
                if swipe.EnableMouse then swipe:EnableMouse(false) end
                if swipe.SetDrawEdge then swipe:SetDrawEdge(false) end
                if swipe.SetReverse then swipe:SetReverse(true) end
                if swipe.SetHideCountdownNumbers then swipe:SetHideCountdownNumbers(layout.showDuration == false) end
                if swipe.SetCountdownAbbrevThreshold then swipe:SetCountdownAbbrevThreshold(60) end
                StyleCountdown(swipe, layout.size)
                if button.SetDurationCooldown then button:SetDurationCooldown(swipe) end
            end,
        })
        container:SetUnit(unit)
        container:SetEnabled(true)
        container:Show()
    end

    local function RefreshContainer(container, row, filter, unit)
        container:SetUnit(unit)
        if row.nativeAuraFilter ~= filter then
            container:SetAuraGroupFilterString("platesmith", filter)
            row.nativeAuraFilter = filter
        end
        container:SetEnabled(true)
        container:Show()
    end

    -- The row resizes with the layout after the container is built. A centred row's container keeps
    -- the size its own layout gave it (FlowOf).
    local function Reanchor(container, row, layout)
        local _, _, _, pin = FlowOf(layout)
        container:ClearAllPoints()
        container:SetPoint(pin, row, pin, 0, 0)
        if layout.growX ~= "centre" then container:SetSize(row:GetWidth(), row:GetHeight()) end
    end

    local function ConfigureNativeAuraContainer(data, kind, filter, layout)
        local row = data[kind]
        local signature = LayoutSignature(layout)
        local container = row.nativeAuraContainer
        if container and row.nativeAuraSignature ~= signature then
            DisableContainer(container)
            container = row.nativeAuraContainers and row.nativeAuraContainers[signature]
            row.nativeAuraContainer, row.nativeAuraAttempted = container, false
            if container then
                row.nativeAuraSignature, row.nativeAuraFilter = signature, row.nativeAuraFilters[signature]
            end
        end
        if not container then
            -- A failed creation is retried after a while, not on every aura update.
            local now = type(GetTime) == "function" and GetTime() or 0
            if row.nativeAuraAttempted and now < (row.nativeAuraRetryAt or 0) then return false end
            row.nativeAuraAttempted, row.nativeAuraRetryAt = true, now + 10
            -- Owned by UIParent and pinned to the row, never inside the nameplate: other addons
            -- (OmniCC GODMODE) sweep every nameplate's frame tree and hide any aura container
            -- they find there. Scale, alpha and visibility follow the row.
            local created, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
            if not created or not result or type(result.AddAuraGroup) ~= "function" then
                row.nativeAuraState = "create-error"
                row.nativeAuraError = created and "AddAuraGroup unavailable" or tostring(result):sub(1, 160)
                return false
            end
            container = result
            local configured, failure = pcall(BuildContainer, container, row, filter, layout, data.unit)
            if not configured then
                DisableContainer(container)
                row.nativeAuraState = "configure-error"
                row.nativeAuraError = tostring(failure):sub(1, 160)
                return false
            end
            row.nativeAuraContainers = row.nativeAuraContainers or {}
            row.nativeAuraFilters = row.nativeAuraFilters or {}
            row.nativeAuraContainers[signature] = container
            row.nativeAuraContainer, row.nativeAuraFilter, row.nativeAuraSignature = container, filter, signature
            -- Not the row's child, so it leaves with the row explicitly.
            if not row.nativeAuraHooked then
                row.nativeAuraHooked = true
                row:HookScript("OnHide", function()
                    local current = row.nativeAuraContainer
                    if current then DisableContainer(current) end
                end)
            end
        else
            local configured, failure = pcall(RefreshContainer, container, row, filter, data.unit)
            if not configured then
                DisableContainer(container)
                row.nativeAuraState = "update-error"
                row.nativeAuraError = tostring(failure):sub(1, 160)
                return false
            end
        end
        row.nativeAuraFilters[signature] = row.nativeAuraFilter
        -- Pinned to the row, it follows the row's moves; placed again only for another container or
        -- shape (the row's size follows the shape).
        local fresh = row.nativeAuraPlaced ~= container
        if fresh or row.nativeAuraPlacedSignature ~= signature then
            pcall(Reanchor, container, row, layout)
            row.nativeAuraPlaced, row.nativeAuraPlacedSignature = container, signature
            row.nativeAuraScale, row.nativeAuraAlpha = nil, nil
        end
        -- As a child it would inherit the plate's scale and fade; outside the plate it copies them,
        -- written when they change.
        local okScale, rowScale = pcall(row.GetEffectiveScale, row)
        local okParent, parentScale = UIParent ~= nil, 1
        if UIParent then okParent, parentScale = pcall(UIParent.GetEffectiveScale, UIParent) end
        if okScale and okParent and IsReadable(rowScale) and IsReadable(parentScale)
            and type(rowScale) == "number" and type(parentScale) == "number" and parentScale > 0 then
            local scale = rowScale / parentScale
            if row.nativeAuraScale ~= scale then
                pcall(container.SetScale, container, scale)
                row.nativeAuraScale = scale
            end
        end
        local okAlpha, alpha = pcall(row.GetEffectiveAlpha, row)
        if okAlpha and IsReadable(alpha) and type(alpha) == "number" and row.nativeAuraAlpha ~= alpha then
            pcall(container.SetAlpha, container, alpha)
            row.nativeAuraAlpha = alpha
        end
        row.nativeAuraState = "ready"
        row.nativeAuraError = nil
        return true
    end

    -- Lays the row out only when its shape (or, centred, the icons on its last line) changed.
    local function PlaceRow(row, icons, layout, shown)
        if row.plateSmithCount ~= layout.count or row.plateSmithColumns ~= layout.columns
            or row.plateSmithIconSize ~= layout.size or row.plateSmithSpacing ~= layout.spacing
            or row.plateSmithGrowX ~= layout.growX or row.plateSmithGrowY ~= layout.growY then
            row.plateSmithCount, row.plateSmithColumns, row.plateSmithIconSize = layout.count, layout.columns, layout.size
            row.plateSmithSpacing, row.plateSmithGrowX, row.plateSmithGrowY = layout.spacing, layout.growX, layout.growY
            row.plateSmithPlacedFor = nil
        end
        -- Centred lines depend on how many icons the last line holds.
        local placedFor = layout.growX == "centre" and shown or -1
        if row.plateSmithPlacedFor ~= placedFor then
            Counters.auraRowLayouts = Counters.auraRowLayouts + 1
            LayoutAuraRow(row, icons, layout, placedFor >= 0 and placedFor or nil)
            row.plateSmithPlacedFor = placedFor
        end
    end

    local function SetRowShown(row, shown)
        if row:IsShown() ~= shown then row:SetShown(shown) end
    end

    -- Whether the plate shows this row at all: off in the settings, turned off in the layout, or on
    -- a plate PlateSmith does not draw, it reads nothing.
    local function RowWanted(data, kind)
        local db = GetSettings()
        local enabled = db.showDebuffs
        if kind == "buffs" then enabled = db.showBuffs end
        local position = data.layout and data.layout[kind]
        return data.own and enabled and position ~= nil and position.visible ~= false and not position.removed
            and not (data.restrictedFriendly and not data.restrictedOverlayEnabled)
            and data.overlay:IsShown() or false
    end

    local function UpdateAuraRow(data, kind, targeted)
        local db = GetSettings()
        local row = data[kind]
        local icons = data[ICON_KEYS[kind]]
        local routeKey = ROUTE_KEYS[kind]
        if not RowWanted(data, kind) then
            data[routeKey] = "disabled"
            row.plateSmithPoll, row.plateSmithExpireAt = nil, nil
            -- Put away once; a row that stays off costs nothing on later updates.
            if row.plateSmithActive ~= false then
                row.plateSmithActive = false
                if row.nativeAuraContainer then DisableContainer(row.nativeAuraContainer) end
                row:Hide()
            end
            return false
        end
        row.plateSmithActive = true
        local layout = data.profile and data.profile.auraLayouts and data.profile.auraLayouts[kind] or DEFAULT_LAYOUT
        local source = kind == "buffs" and db.buffSource or db.debuffSource
        local filter = FILTERS[kind][source == "mine" and "mine" or "all"]
        -- A confirmed target token can expose auras that the dungeon nameplate
        -- token does not. Never borrow it for an unconfirmed or changed target.
        local auraUnit = data.unit
        if targeted then auraUnit = "target" end
        local previous = row.plateSmithShownCount or AURA_ICON_COUNT
        local shown, route = PopulateAuraIcons(kind, auraUnit, filter, icons, layout.count, data)
        if auraUnit == "target" then
            if not SameUnit(data.unit, "target") then
                shown = 0
                route = "target-changed"
            elseif shown == 0 then
                shown, route = PopulateAuraIcons(kind, data.unit, filter, icons, layout.count, data)
            end
        end
        -- The readable lookup is tried first on every update; the native container is only a
        -- fallback while that lookup errors or is protected (combat; a shapeshift can turn an
        -- error into protected), so a row that fell back recovers by itself. Only
        -- debuffs use it: in play its buff group also admitted harmful auras (it skips its
        -- filter for auras already matched), so unreadable buffs stay hidden instead.
        local container = row.nativeAuraContainer
        if shown > 0 then
            if container then DisableContainer(container) end
        elseif kind == "debuffs" and (route:find("index=error", 1, true) or route == "indexed-protected") then
            -- The native aura widget only lays out while its row is visible.
            PlaceRow(row, icons, layout, 0)
            if not row:IsShown() then row:Show() end
            if ConfigureNativeAuraContainer(data, kind, filter, layout) then
                HideIcons(icons, 1, AURA_ICON_COUNT)
                ApplyAuraTimes(icons, 0, layout, previous)
                row.plateSmithShownCount = 0
                data[routeKey] = "native-container"
                row.plateSmithPoll, row.plateSmithExpireAt = true, nil
                return true
            end
        elseif container then
            DisableContainer(container)
        end
        if shown == 0 and row.nativeAuraState and row.nativeAuraState ~= "ready" then
            route = ContainerRoute(route, row.nativeAuraState)
        end
        data[routeKey] = route
        HideIcons(icons, shown + 1, math.max(shown, previous))
        -- Timed auras can run out without an event on some clients: the slow pass reads the row
        -- again once the soonest one has expired. An unsettled read retries on every pass.
        row.plateSmithExpireAt = ApplyAuraTimes(icons, shown, layout, previous)
        row.plateSmithShownCount = shown
        row.plateSmithPoll = not SETTLED_ROUTES[route] or nil
        PlaceRow(row, icons, layout, shown)
        SetRowShown(row, shown > 0)
        return true
    end

    -- Returns whether the plate shows either row (it then wants UNIT_AURA and the slow pass).
    local function UpdateAuras(data)
        -- The target token is confirmed only on the plate the target highlight marked (data.targeted,
        -- which follows every target change).
        local targeted = false
        if data.targeted and (RowWanted(data, "buffs") or RowWanted(data, "debuffs")) then
            targeted = SameUnit(data.unit, "target")
        end
        local buffs = UpdateAuraRow(data, "buffs", targeted)
        local debuffs = UpdateAuraRow(data, "debuffs", targeted)
        return buffs or debuffs
    end

    -- Whether the slow aura pass should read this plate again: an unsettled read, or a timed aura
    -- that has run out.
    local function RowNeedsPoll(row, now)
        return row.plateSmithPoll or (row.plateSmithExpireAt ~= nil and now >= row.plateSmithExpireAt)
    end
    local function AurasNeedPoll(data, now)
        now = now or GetTime()
        return (RowNeedsPoll(data.buffs, now) or RowNeedsPoll(data.debuffs, now)) and true or false
    end

    -- Whether the slow pass has anything to wait for on this plate.
    local function AurasPolled(data)
        local buffs, debuffs = data.buffs, data.debuffs
        return (buffs.plateSmithPoll or buffs.plateSmithExpireAt or debuffs.plateSmithPoll or debuffs.plateSmithExpireAt)
            and true or false
    end

    return AURA_ICON_COUNT, CreateAuraRow, UpdateAuras, AurasNeedPoll, AurasPolled
end
