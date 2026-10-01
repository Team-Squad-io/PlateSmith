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

-- The countdown text as the row's Display says: its Font size (points; Auto: 45% of the icon)
-- times the profile's text size, in its font (the plate font unless it picks one;
-- Blizzard's draws Friz Quadrata), outline (outlined unless it picks one) and shadow (nil: the
-- client's own), and where it sits (timePosition; centred on the bottom edge by default). Returns
-- path, size, flags, shadow, position.
local COUNTDOWN_POINTS = {
    bottom = { "BOTTOM", 0, -1, "CENTER" }, centre = { "CENTER", 0, 0, "CENTER" }, top = { "TOP", 0, 1, "CENTER" },
    bottomright = { "BOTTOMRIGHT", 1, -1, "RIGHT" },
}
local COUNTDOWN_FONT = "Fonts\\FRIZQT__.TTF"
local OUTLINE_FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local function CountdownFont(layout, settings)
    local share = (tonumber(layout.timeSize) or 45) / 100
    -- Its Font size in points, or Auto: the row's share of the icon (timeSize, 45% unless an early
    -- 1.1.1 build set it).
    local size = tonumber(layout.timeFontSize) or math.max(8, math.floor((tonumber(layout.size) or 18) * share))
    local textScale = settings and settings.textScale
    if textScale and textScale ~= 1 then size = PS.ProfileSchema.ScaledFontSize(size, textScale) end
    local path = PS.Media.FontPath(layout.timeFont or (settings and settings.font)) or COUNTDOWN_FONT
    local position = COUNTDOWN_POINTS[layout.timePosition] and layout.timePosition or "bottom"
    return path, size, OUTLINE_FLAGS[layout.timeOutline or "outline"], layout.timeShadow, position
end

-- Where the countdown sits on its icon. Centred, a long label ("15m") and a short one ("2m") sit
-- alike; bottomright is the old corner (a label grows leftwards from it).
local function PlaceCountdown(text, icon, position)
    local point = COUNTDOWN_POINTS[position] or COUNTDOWN_POINTS.bottom
    text:ClearAllPoints()
    text:SetPoint(point[1], icon, point[1], point[2], point[3])
    if text.SetJustifyH then text:SetJustifyH(point[4]) end
end

-- Shared with Blueprint Studio's preview, so it lays auras and their countdown out exactly as the
-- plates do.
PS.LayoutAuraRow = LayoutAuraRow
PS.AuraCountdownFont, PS.PlaceAuraCountdown = CountdownFont, PlaceCountdown

PS._CreatePlateAuras = function(context)
    local Secret = PS.Secret
    local IsReadable, HasValue, SameUnit = Secret.IsReadable, Secret.HasValue, Secret.SameUnit
    local GetSettings, Counters = context.GetSettings, context.Counters

    -- A row holds up to this many icons; each plate type's auraLayouts says how many show and how.
    local AURA_ICON_COUNT = 8
    local DEFAULT_LAYOUT = { count = 4, columns = 4, size = 18, spacing = 2, growX = "right", growY = "up" }
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

    -- The countdown text in the row's Display choices (CountdownFont), centred under the icon
    -- (PlaceCountdown). Set only when one of them changes; the anchor goes with each change, on a
    -- reused icon as on a new one.
    -- The swipe's countdown text. The client may make it only when a countdown first runs (the
    -- game's own aura containers do), so it is looked up each time rather than once.
    local function CountdownText(swipe)
        if swipe.GetCountdownFontString then
            local ok, text = pcall(swipe.GetCountdownFontString, swipe)
            return ok and text or nil
        end
        local text = swipe.GetRegions and swipe:GetRegions()
        if text and text.GetObjectType and text:GetObjectType() == "FontString" then return text end
    end

    -- A font object per countdown look, for Cooldown:SetCountdownFont: a countdown text the client
    -- makes later starts in it.
    local countdownFonts = {}
    local function CountdownFontObject(path, size, flags)
        local key = path .. ":" .. size .. ":" .. flags
        local font = countdownFonts[key]
        if font == nil and type(CreateFont) == "function" then
            local name = "PlateSmithCountdown" .. (#countdownFonts + 1)
            countdownFonts[#countdownFonts + 1] = name
            font = CreateFont(name)
            font:SetFont(path, size, flags)
            countdownFonts[key] = name
            return name
        end
        return font
    end

    local function StyleCountdown(swipe, layout)
        local path, fontSize, flags, shadow, position = CountdownFont(layout, GetSettings and GetSettings())
        -- A styled text is not looked up again until a countdown starts (RestyleCountdown clears it).
        if swipe.plateSmithCountdownText ~= nil and swipe.plateSmithCountdownSize == fontSize
            and swipe.plateSmithCountdownPath == path and swipe.plateSmithCountdownFlags == flags
            and swipe.plateSmithCountdownShadow == shadow and swipe.plateSmithCountdownPosition == position then return end
        local text = CountdownText(swipe)
        if text == swipe.plateSmithCountdownText and swipe.plateSmithCountdownSize == fontSize
            and swipe.plateSmithCountdownPath == path and swipe.plateSmithCountdownFlags == flags
            and swipe.plateSmithCountdownShadow == shadow and swipe.plateSmithCountdownPosition == position then return end
        local look = path .. fontSize .. flags
        if swipe.SetCountdownFont and swipe.plateSmithCountdownObject ~= look then
            -- Tried once per look, whether or not the client takes it.
            swipe.plateSmithCountdownObject = look
            local fontObject = CountdownFontObject(path, fontSize, flags)
            if fontObject then pcall(swipe.SetCountdownFont, swipe, fontObject) end
        end
        -- No text yet: nothing is remembered, so the next countdown styles it (RestyleCountdown).
        if text and text.SetFont then
            text:SetFont(path, fontSize, flags)
            PlaceCountdown(text, swipe, position)
            if text.SetShadowColor and text.SetShadowOffset then
                -- The client's own shadow is kept to go back to when the row's choice is cleared.
                if shadow ~= nil and not swipe.plateSmithCountdownPlain and text.GetShadowColor and text.GetShadowOffset then
                    local red, green, blue, alpha = text:GetShadowColor()
                    local x, y = text:GetShadowOffset()
                    swipe.plateSmithCountdownPlain = { red, green, blue, alpha, x, y }
                end
                local plain = swipe.plateSmithCountdownPlain
                if shadow ~= nil then
                    text:SetShadowColor(0, 0, 0, shadow and 1 or 0)
                    text:SetShadowOffset(1, -1)
                elseif plain then
                    text:SetShadowColor(plain[1], plain[2], plain[3], plain[4])
                    text:SetShadowOffset(plain[5], plain[6])
                end
            end
            swipe.plateSmithCountdownSize, swipe.plateSmithCountdownPath = fontSize, path
            swipe.plateSmithCountdownFlags, swipe.plateSmithCountdownShadow = flags, shadow
            swipe.plateSmithCountdownPosition, swipe.plateSmithCountdownText = position, text
        end
    end

    -- The game's aura containers start each countdown themselves: the text is styled again after
    -- each one starts (it may be new, or reset), on this swipe only.
    local COUNTDOWN_STARTS = { "SetCooldown", "SetCooldownFromDurationObject", "SetCooldownDuration", "SetCooldownUNIX" }
    local function RestyleCountdown(swipe)
        if swipe.plateSmithCountdownLayout then
            swipe.plateSmithCountdownText = nil
            pcall(StyleCountdown, swipe, swipe.plateSmithCountdownLayout)
        end
    end
    local function FollowCountdowns(swipe, layout)
        swipe.plateSmithCountdownLayout = layout
        if swipe.plateSmithCountdownFollowed then return end
        swipe.plateSmithCountdownFollowed = true
        -- Method hooks only: the client refuses script handlers on these swipes ("blocked by secret
        -- aspects"), and a refused hook is skipped rather than allowed to break the container.
        if type(hooksecurefunc) == "function" then
            for _, method in ipairs(COUNTDOWN_STARTS) do
                if type(swipe[method]) == "function" then pcall(hooksecurefunc, swipe, method, RestyleCountdown) end
            end
        end
    end

    local function DisableContainer(container)
        pcall(container.SetEnabled, container, false)
        pcall(container.Hide, container)
    end

    -- row.nativeAuraBound: the unit the row's current container was pointed at and enabled for;
    -- cleared whenever it is put away, so the next use points it again.
    local function DisableRowContainer(row, container)
        row.nativeAuraBound = nil
        DisableContainer(container)
    end

    -- Each icon has a cooldown swipe that chips away as the aura runs out, and optionally its
    -- remaining time in the corner (the client's own short format: 9, 1m, 2h). A row's icons are made
    -- the first time it has a readable aura to show (BuildIcons), so a plate that never shows one (no
    -- auras, rows off, or reads the client protects, as in a dungeon) makes none.
    local function CreateAuraRow(parent)
        local row = CreateFrame("Frame", nil, parent)
        local icons = {}
        LayoutAuraRow(row, icons, DEFAULT_LAYOUT)
        row:Hide()
        return row, icons
    end

    local function BuildIcons(row, icons)
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
        -- Laid out again for the row's own shape (PlaceRow).
        row.plateSmithPlacedFor, row.plateSmithCount = nil, nil
    end

    -- Swipes run only from readable, positive durations; anything protected shows no swipe
    -- rather than a guess. Only icons shown now or last time are visited. Returns the soonest
    -- readable expiration of a shown icon (nil: none is timed).
    local function ApplyAuraTimes(icons, shown, layout, previous)
        local soonest
        local hideNumbers = layout.showDuration == false
        for index = 1, math.max(shown, previous or AURA_ICON_COUNT) do
            local icon = icons[index]
            local swipe = icon and icon.swipe
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
                    StyleCountdown(swipe, layout)
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
            if icon then icon.auraDuration, icon.auraExpiration = nil, nil end
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
            if icon and icon.plateSmithShown ~= false then
                icon:Hide()
                icon.plateSmithShown = false
            end
        end
    end

    -- A row's Timed only (layout.timedOnly) skips an aura whose duration is readable and not positive
    -- (0 or nil: passives, Devotion Aura, tracking). A protected duration is kept: the client hides
    -- it, so PlateSmith cannot tell. A skipped aura takes no icon, so a timed-only row reads past its
    -- count, up to the client's aura limit.
    local AURA_SCAN_LIMIT = 40
    local function Untimed(duration)
        return IsReadable(duration) and not (type(duration) == "number" and duration > 0)
    end

    local function PopulateAuraIconsByIndex(api, unit, filter, icons, limit, row, timedOnly)
        if type(api) ~= "function" then return 0, "missing" end
        local shown = 0
        for index = 1, timedOnly and AURA_SCAN_LIMIT or limit do
            if shown >= limit then break end
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
            if not (timedOnly and durationOK and Untimed(duration)) then
                local expirationOK, expiration = pcall(Field, aura, "expirationTime")
                if not expirationOK then expiration = nil end
                if not icons[1] then BuildIcons(row, icons) end
                if not ShowIcon(icons[shown + 1], icon, duration, expiration) then
                    return shown, "texture-error"
                end
                shown = shown + 1
            end
        end
        return shown, shown > 0 and "shown" or "none"
    end

    -- AuraUtil.ForEachAura's callback, made once: the row being filled is held here meanwhile.
    local slotIcons, slotRow, slotLimit, slotShown, slotTimedOnly = nil, nil, 0, 0, false
    local function SlotCallback(_, icon, _, _, duration, expiration)
        if slotTimedOnly and Untimed(duration) then return false end
        if HasValue(icon) and not slotIcons[1] then BuildIcons(slotRow, slotIcons) end
        if HasValue(icon) and ShowIcon(slotIcons[slotShown + 1], icon, duration, expiration) then
            slotShown = slotShown + 1
        end
        return slotShown >= slotLimit
    end

    local function PopulateAuraIconsBySlots(unit, filter, icons, limit, row, timedOnly)
        local iterate = AuraUtil and AuraUtil.ForEachAura
        if type(iterate) ~= "function" then return 0, "missing" end
        slotIcons, slotRow, slotLimit, slotShown, slotTimedOnly = icons, row, limit, 0, timedOnly == true
        local ok = pcall(iterate, unit, filter, timedOnly and AURA_SCAN_LIMIT or limit, SlotCallback)
        local shown = slotShown
        slotIcons, slotRow = nil, nil
        return shown, not ok and "error" or shown > 0 and "shown" or "none"
    end

    local function PopulateAuraIconsLegacy(kind, unit, filter, icons, limit, row, timedOnly)
        local api = kind == "buffs" and UnitBuff or UnitDebuff
        if type(api) ~= "function" then return 0, "missing" end
        -- UnitBuff/UnitDebuff already imply HELPFUL/HARMFUL; their optional filter
        -- only needs the source restriction.
        local legacyFilter = filter:find("|PLAYER", 1, true) and "PLAYER" or nil
        local shown = 0
        for index = 1, timedOnly and AURA_SCAN_LIMIT or limit do
            if shown >= limit then break end
            local ok, name, icon, _, _, duration, expiration = pcall(api, unit, index, legacyFilter)
            if not ok then return shown, "error" end
            if not HasValue(name) then break end
            if not HasValue(icon) then break end
            if not (timedOnly and Untimed(duration)) then
                if not icons[1] then BuildIcons(row, icons) end
                if not ShowIcon(icons[shown + 1], icon, duration, expiration) then return shown, "texture-error" end
                shown = shown + 1
            end
        end
        return shown, shown > 0 and "shown" or "none"
    end

    -- An indexed read of a plate's own unit that errored in combat is not tried again on every
    -- event: until combat ends or the plate gets its next unit (data[INDEX_ERROR_KEYS[kind]]), the
    -- row goes straight to the other routes, as that read would.
    local INDEX_ERROR_KEYS = { buffs = "buffsIndexError", debuffs = "debuffsIndexError" }
    local function PopulateAuraIcons(kind, unit, filter, icons, limit, data, timedOnly)
        Counters.auraReads = Counters.auraReads + 1
        local errorKey = data and unit == data.unit and INDEX_ERROR_KEYS[kind]
        local shown, indexState = 0, "error"
        if not (errorKey and data[errorKey]) then
            local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
            shown, indexState = PopulateAuraIconsByIndex(api, unit, filter, icons, limit, data[kind], timedOnly)
            if errorKey and shown == 0 and indexState == "error" and Secret.InCombat() then data[errorKey] = true end
        end
        if shown > 0 then return shown, "indexed" end
        -- A readable empty result or protected value is authoritative. Try other
        -- API shapes only when this API itself is missing or raises an error.
        if indexState ~= "error" and indexState ~= "missing" then
            return 0, indexedRoutes[indexState]
        end
        local slotState
        shown, slotState = PopulateAuraIconsBySlots(unit, filter, icons, limit, data[kind], timedOnly)
        if shown > 0 then return shown, "slots" end
        local legacyState
        shown, legacyState = PopulateAuraIconsLegacy(kind, unit, filter, icons, limit, data[kind], timedOnly)
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
    -- on the row, made once and reused; built once per layout table, and again when the plate font
    -- or text size changes (a container's countdown text is styled as its icons are made).
    local signatures = setmetatable({}, { __mode = "k" })
    local function LayoutSignature(layout)
        local settings = GetSettings and GetSettings()
        local font, textScale = settings and settings.font or "", settings and settings.textScale or 1
        local cached = signatures[layout]
        if not cached or cached.font ~= font or cached.textScale ~= textScale then
            cached = cached or {}
            cached.value = table.concat({ layout.count, layout.columns, layout.size, layout.spacing, layout.growX,
                layout.growY, tostring(layout.showDuration ~= false), layout.timeSize or 45, layout.timeFont or "",
                layout.timeOutline or "", tostring(layout.timeShadow), layout.timePosition or "", layout.timeFontSize or "", font,
                textScale }, ":")
            cached.font, cached.textScale = font, textScale
            signatures[layout] = cached
        end
        return cached.value
    end

    -- A row's full line for the layout, as LayoutAuraRow sizes it.
    local function RowSize(layout)
        return layout.columns * layout.size + (layout.columns - 1) * layout.spacing, layout.size
    end

    -- Everything but the unit and the row: a container made ahead (the pool) is made this far,
    -- and one made on first use goes on to AttachContainer at once.
    local function PrepareContainer(container, filter, layout)
        local corner, growX, growY = FlowOf(layout)
        local width, height = RowSize(layout)
        container:SetEnabled(false)
        container:SetSize(width, height)
        if container.SetIgnoreParentScale then container:SetIgnoreParentScale(false) end
        if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint(corner) end
        if container.SetFlowLayoutGrowthDirection then container:SetFlowLayoutGrowthDirection(growX, growY) end
        if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(width) end
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
                pcall(StyleCountdown, swipe, layout)
                FollowCountdowns(swipe, layout)
                if button.SetDurationCooldown then button:SetDurationCooldown(swipe) end
            end,
        })
        container:Hide()
    end

    -- A prepared container goes to its row: its strata here, its unit (RefreshContainer) and its
    -- place (Reanchor, as for any container new to the row) next.
    local function AttachContainer(container, row)
        container:SetFrameStrata(row:GetFrameStrata())
    end

    local function RefreshContainer(container, row, filter, unit)
        container:SetUnit(unit)
        if row.nativeAuraFilter ~= filter then
            container:SetAuraGroupFilterString("platesmith", filter)
            row.nativeAuraFilter = filter
        end
        container:SetEnabled(true)
        container:Show()
        row.nativeAuraBound = unit
    end

    -- Pointed at this unit, enabled and shown since: the container follows the unit's auras by
    -- itself, so pointing it again (the client reads all the unit's auras again) is skipped.
    local function StillBound(container, row, filter, unit)
        if row.nativeAuraBound ~= unit or row.nativeAuraFilter ~= filter then return false end
        local ok, shown = pcall(container.IsShown, container)
        return ok and IsReadable(shown) and shown == true
    end

    -- Containers made ahead, out of combat (Lifecycle's spares entry calls pool.Build): each layout
    -- shape a row fell back to this session, and in a group instance the enemy plates' debuff row,
    -- keeps up to POOL_PER_SHAPE ready, so a row falling back mid-pull takes one instead of paying
    -- for its creation then. pool.shapes: signature -> { layout, filter }, at most POOL_SHAPES
    -- (the oldest gives way); pool.ready: signature -> list of { container, filter }.
    local POOL_PER_SHAPE, POOL_SHAPES, POOL_RETRY = 12, 2, 10
    local pool = { shapes = {}, order = {}, ready = {}, retryAt = 0, built = 0, taken = 0 }
    if context.Work then context.Work.containers = pool end

    local function NoteShape(signature, layout, filter)
        local shape = pool.shapes[signature]
        if shape then
            shape.layout, shape.filter = layout, filter
            return
        end
        if #pool.order >= POOL_SHAPES then
            pool.shapes[table.remove(pool.order, 1)] = nil
        end
        pool.shapes[signature] = { layout = layout, filter = filter }
        pool.order[#pool.order + 1] = signature
    end

    -- The shape (and filter) the enemy plates' debuff row would fall back to in a group instance.
    local function InstanceShape(db)
        local policy = PS.NamePolicy
        if not (db and policy and policy.InGroupInstance()) then return nil end
        local profiles = db.plateProfiles
        local profile = profiles and (profiles.enemyDungeon or profiles.enemy)
        local position = profile and profile.layout and profile.layout.debuffs
        local layout = profile and profile.auraLayouts and profile.auraLayouts.debuffs
        if not layout or not position or position.visible == false or position.removed then return nil end
        return layout, FILTERS.debuffs[db.debuffSource == "mine" and "mine" or "all"]
    end

    local function ShortOf(signature)
        local ready = pool.ready[signature]
        return (ready and #ready or 0) < POOL_PER_SHAPE
    end

    -- A shape with fewer than POOL_PER_SHAPE ready, or nil.
    local function WantedShape()
        local layout, filter = InstanceShape(GetSettings())
        if layout then
            local signature = LayoutSignature(layout)
            if ShortOf(signature) then return signature, layout, filter end
        end
        for index = 1, #pool.order do
            local signature = pool.order[index]
            if ShortOf(signature) then
                local shape = pool.shapes[signature]
                return signature, shape.layout, shape.filter
            end
        end
    end

    -- After a failed build nothing is wanted for POOL_RETRY seconds (the spares entry then stops
    -- until something starts it again); rows still make their own as before.
    function pool.Wanted(now)
        return (now or 0) >= pool.retryAt and WantedShape() ~= nil
    end

    -- Makes one container for a shape short of ready ones. Returns whether it made one.
    function pool.Build(now)
        if (now or 0) < pool.retryAt then return false end
        local signature, layout, filter = WantedShape()
        if not signature then return false end
        local created, container = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not created or not container or type(container.AddAuraGroup) ~= "function" then
            pool.retryAt = (now or 0) + POOL_RETRY
            return false
        end
        if not pcall(PrepareContainer, container, filter, layout) then
            DisableContainer(container)
            pool.retryAt = (now or 0) + POOL_RETRY
            return false
        end
        local ready = pool.ready[signature] or {}
        pool.ready[signature] = ready
        ready[#ready + 1] = { container = container, filter = filter }
        pool.built = pool.built + 1
        return true
    end

    -- A ready container for the shape, and the filter it was made with; nil when none is.
    local function TakePooled(signature)
        local ready = pool.ready[signature]
        local entry = ready and ready[#ready]
        if not entry then return nil end
        ready[#ready] = nil
        pool.taken = pool.taken + 1
        if context.PoolTaken then context.PoolTaken() end
        return entry.container, entry.filter
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
            DisableRowContainer(row, container)
            container = row.nativeAuraContainers and row.nativeAuraContainers[signature]
            row.nativeAuraContainer, row.nativeAuraAttempted = container, false
            if container then
                row.nativeAuraSignature, row.nativeAuraFilter = signature, row.nativeAuraFilters[signature]
            end
        end
        if not container then
            -- One made ahead is taken first; it only needs its row and unit.
            local pooled, pooledFilter = TakePooled(signature)
            if not pooled then
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
                local prepared, failure = pcall(PrepareContainer, result, filter, layout)
                if not prepared then
                    DisableContainer(result)
                    row.nativeAuraState = "configure-error"
                    row.nativeAuraError = tostring(failure):sub(1, 160)
                    return false
                end
                pooled, pooledFilter = result, filter
            end
            container = pooled
            local attached, failure = pcall(AttachContainer, container, row)
            if not attached then
                DisableContainer(container)
                row.nativeAuraState = "configure-error"
                row.nativeAuraError = tostring(failure):sub(1, 160)
                return false
            end
            row.nativeAuraContainers = row.nativeAuraContainers or {}
            row.nativeAuraFilters = row.nativeAuraFilters or {}
            row.nativeAuraContainers[signature] = container
            row.nativeAuraContainer, row.nativeAuraFilter, row.nativeAuraSignature = container, pooledFilter, signature
            row.nativeAuraBound = nil
            -- This client makes containers and rows of this shape fall back to them: keep some ready.
            NoteShape(signature, layout, filter)
            -- Not the row's child, so it leaves with the row explicitly.
            if not row.nativeAuraHooked then
                row.nativeAuraHooked = true
                row:HookScript("OnHide", function()
                    local current = row.nativeAuraContainer
                    if current then DisableRowContainer(row, current) end
                end)
            end
        end
        if not StillBound(container, row, filter, data.unit) then
            local configured, failure = pcall(RefreshContainer, container, row, filter, data.unit)
            if not configured then
                DisableRowContainer(row, container)
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

    -- Whether the plate shows this row at all: turned off in the layout, or on a plate PlateSmith
    -- does not draw, it reads nothing.
    local function RowWanted(data, kind)
        local position = data.layout and data.layout[kind]
        return data.own and position ~= nil and position.visible ~= false and not position.removed
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
                if row.nativeAuraContainer then DisableRowContainer(row, row.nativeAuraContainer) end
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
        local timedOnly = layout.timedOnly == true
        local shown, route = PopulateAuraIcons(kind, auraUnit, filter, icons, layout.count, data, timedOnly)
        if auraUnit == "target" then
            if not SameUnit(data.unit, "target") then
                shown = 0
                route = "target-changed"
            elseif shown == 0 then
                shown, route = PopulateAuraIcons(kind, data.unit, filter, icons, layout.count, data, timedOnly)
            end
        end
        -- The readable lookup is tried first on every update; the native container is only a
        -- fallback while that lookup errors or is protected (combat; a shapeshift can turn an
        -- error into protected), so a row that fell back recovers by itself. It cannot skip untimed
        -- auras, so Timed only does not apply there. Only
        -- debuffs use it: in play its buff group also admitted harmful auras (it skips its
        -- filter for auras already matched), so unreadable buffs stay hidden instead.
        local container = row.nativeAuraContainer
        if shown > 0 then
            if container then DisableRowContainer(row, container) end
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
            DisableRowContainer(row, container)
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
