-- Where each part is drawn on an owned plate: part regions, measured sizes, layout transforms,
-- anchors, stacks, and hiding what sits under a hidden parent.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")

PS._CreatePlatePlacement = function(context)
    local IsReadable = PS.Secret.IsReadable
    local Styles, MarkVisibility, Counters = context.Styles, context.MarkVisibility, context.Counters
    local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT
    local VALUE_KEYS, IS_VALUE_KEY, EMPTY = Styles.VALUE_KEYS, Styles.IS_VALUE_KEY, Styles.EMPTY
    local UpdateValueAnchors
    -- A part's region on this plate (a value's text or graphic, or the part itself). Classification
    -- in icon style draws its icon, not its hidden text.
    local function PartRegion(data, key)
        if type(key) ~= "string" then return nil end
        if IS_VALUE_KEY[key] then return data.values and data.values[key] end
        if key == "classification" and data.classificationIcon and data.classificationIcon:IsShown() then
            return data.classificationIcon
        end
        local region = data[key]
        return type(region) == "table" and region.SetPoint and region or nil
    end

    -- Every region a part's rules and hiding apply to: classification's text and icon both, so a
    -- switch of style keeps the rule's look.
    local function PartRegions(data, key)
        if key == "classification" then return data.classification, data.classificationIcon end
        return PartRegion(data, key), nil
    end

    local function ReadNumber(region, method)
        local fn = region[method]
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, region)
        if ok and IsReadable(value) and type(value) == "number" then return value end
    end

    local function IsText(region)
        if type(region.GetObjectType) == "function" then
            local ok, kind = pcall(region.GetObjectType, region)
            return ok and kind == "FontString"
        end
        return (ReadNumber(region, "GetStringWidth") or 0) > 0
    end

    -- A text's drawn width: the rendered string, not its frame.
    local function TextWidth(region)
        return ReadNumber(region, "GetStringWidth")
    end

    -- A region's size without failing: the client can refuse to measure a restricted nameplate's
    -- regions. Text is its rendered string with its font's height; an icon or bar its own size.
    local function SafeSize(region, data)
        local width, height
        if IsText(region) then
            width = TextWidth(region)
            if region.GetFont then
                local ok, _, size = pcall(region.GetFont, region)
                if ok and IsReadable(size) and type(size) == "number" then height = size end
            end
            height = height or ReadNumber(region, "GetStringHeight") or ReadNumber(region, "GetHeight")
        else
            width, height = ReadNumber(region, "GetWidth"), ReadNumber(region, "GetHeight")
            if not width or width <= 0 then width = ReadNumber(region, "GetStringWidth") or width end
            if not height or height <= 0 then height = ReadNumber(region, "GetStringHeight") or height end
        end
        -- Refused (in combat): the last size it was measured at, so stacks and pins hold still.
        local known = region.plateSmithSize
        if not width or not height then
            if known then return known[1], known[2] end
            return nil
        end
        if known then
            known[1], known[2] = width, height
        else
            region.plateSmithSize = { width, height }
            if data then
                data.sizedRegions = data.sizedRegions or {}
                data.sizedRegions[region] = true
            end
        end
        return width, height
    end

    -- Where each layout entry is drawn (Schema's LayoutTransforms). Without stacks the result is
    -- worked out once per layout table and shared by every plate; with stacks it uses this plate's
    -- part sizes (a bar's height, a text's line), worked out when the plate is laid out. The text
    -- widths it used are kept, so a text that changes width places what is pinned to it again.
    local transformCache = setmetatable({}, { __mode = "k" })
    local stackedLayouts = setmetatable({}, { __mode = "k" })
    local function HasStacks(layout)
        local known = stackedLayouts[layout]
        if known == nil then
            known = false
            -- Stacks and Dynamic parts both need this plate's sizes.
            for _, position in pairs(layout) do
                if type(position) == "table" and (position.stack or position.attach) then known = true break end
            end
            stackedLayouts[layout] = known
        end
        return known
    end

    local function MeasurePart(data, key)
        local region = PartRegion(data, key)
        if not region or not region.GetHeight then return nil end
        local width, height = SafeSize(region, data)
        if not width then return nil end
        if IsText(region) then data.measuredWidths[key] = width end
        -- Only what the plate shows right now takes space: a hidden power bar, an idle cast bar or
        -- a missing guild line closes up (it is still placed).
        local hidden = region.IsShown and not region:IsShown() or nil
        -- An aura row stacks as its whole grid (every line it can fill).
        local aura = (key == "buffs" or key == "debuffs") and data.profile.auraLayouts
            and data.profile.auraLayouts[key]
        if aura then
            local gridWidth, gridHeight, offset = S.AuraGridBox(aura)
            return gridWidth, gridHeight, hidden, 0, offset
        end
        return width, height, hidden
    end

    local function RegionHidden(region)
        return (region.IsShown ~= nil and not region:IsShown()) or region.plateSmithRuleHidden == true
    end

    local function PartHidden(data, key)
        local region = PartRegion(data, key)
        if region == nil then return false end
        local hidden = RegionHidden(region)
        -- One quest marker, two looks: the mark hides while the loot bag shows in its place.
        if hidden and key == "quest" and region.plateSmithRuleHidden ~= true and data.questLoot then
            hidden = RegionHidden(data.questLoot)
        end
        return hidden
    end

    -- Why a part is hidden decides what happens to what is pinned to it. A bar or an aura row the
    -- plate hides (an idle cast bar, no power, no auras), a custom part, and any part a rule hides
    -- or fades out take their children with them. A mark or text with nothing to show (no
    -- classification, no quest, no guild) is absent: what is pinned to it takes its place, as when
    -- the player turns a part off (Schema's PinTarget).
    local CONTAINERS = { health = true, power = true, cast = true, buffs = true, debuffs = true }
    local function RuleHidden(region)
        return region.plateSmithRuleHidden == true or region.plateSmithRuleAlpha == 0
    end
    local function Absent(data, key)
        if CONTAINERS[key] or IS_VALUE_KEY[key] then return false end
        local region = PartRegion(data, key)
        if not region or RuleHidden(region) then return false end
        return PartHidden(data, key)
    end

    local function Transforms(layout, data)
        if data and HasStacks(layout) then
            if data.layoutTransformsFor ~= layout or not data.layoutTransforms then
                local measured = data.measuredWidths or {}
                data.measuredWidths = measured
                for key in pairs(measured) do measured[key] = nil end
                data.measure = data.measure or function(key) return MeasurePart(data, key) end
                data.absent = data.absent or function(key) return Absent(data, key) end
                data.layoutTransforms = S.LayoutTransforms(layout, data.measure, data.absent)
                data.layoutTransformsFor = layout
            end
            return data.layoutTransforms
        end
        local transforms = transformCache[layout]
        if not transforms then
            transforms = S.LayoutTransforms(layout)
            transformCache[layout] = transforms
        end
        return transforms
    end

    -- The texts whose width places a part at a worked-out spot, once per layout table. A pinned
    -- part is anchored to its parent's edge live, so it follows a width by itself; only a part
    -- placed at its transform (not pinned) under a pinned part, or in a sideways stack, moves with
    -- a width. The default layouts have none, so a new name costs no measuring.
    local HORIZONTAL = { left = true, right = true }
    local sensitiveCache = setmetatable({}, { __mode = "k" })
    local function WidthSensitive(layout)
        local keys = sensitiveCache[layout]
        if keys then return keys end
        keys = {}
        for key, position in pairs(layout) do
            -- The loot bag is anchored to the quest mark's centre live (ApplyComponentLayout).
            if type(position) == "table" and not S.IsGroupKey(key) and key ~= "questLoot" then
                local placed = not S.ATTACH_EDGES[position.attach]
                local pinnedAbove = false
                local node = key
                for _ = 0, S.MAX_DEPTH do
                    local entry = type(node) == "string" and layout[node]
                    if type(entry) ~= "table" then break end
                    local parentKey = entry.parent
                    local parent = type(parentKey) == "string" and layout[parentKey]
                    if type(parent) == "table" and HORIZONTAL[parent.stack] then
                        for other, sibling in pairs(layout) do
                            if type(sibling) == "table" and sibling.parent == parentKey then keys[other] = true end
                        end
                    end
                    if placed and node ~= key and S.ATTACH_EDGES[entry.attach] then pinnedAbove = true end
                    if pinnedAbove then keys[node] = true end
                    node = parentKey
                end
            end
        end
        sensitiveCache[layout] = keys
        return keys
    end

    -- Whether a text the transforms measured, and whose width places a part, is now drawn at
    -- another width (half a pixel or more).
    local function MeasuresChanged(data)
        local sensitive = WidthSensitive(data.layout)
        if not next(sensitive) then return false end
        for key, width in pairs(data.measuredWidths or EMPTY) do
            if sensitive[key] then
                local region = PartRegion(data, key)
                local now = region and TextWidth(region)
                if now and math.abs(now - width) >= 0.5 then return true end
            end
        end
        return false
    end

    -- Places region at key's drawn centre and scale. Offsets are in the region's own scaled units.
    -- A Dynamic part is pinned to its parent part's edge with a real anchor, so it follows that
    -- part live (a name's width as the text changes); to the part it takes the place of while its
    -- parent is turned off or absent.
    local function PlaceRegion(region, layout, key, data)
        local transform = Transforms(layout, data)[key]
        if not transform then return end
        local scale = transform.scale > 0 and transform.scale or 1
        local position = layout[key]
        local edge = position and S.ATTACH_EDGES[position.attach]
        local parentRegion = edge and data and PartRegion(data, S.PinTarget(layout, key, data.absent))
        if parentRegion then
            local parentTransform = Transforms(layout, data)[position.parent]
            local parentScale = parentTransform and parentTransform.scale or 1
            region:SetPoint(edge[3], parentRegion, edge[4], (position.x or 0) * parentScale / scale,
                (position.y or 0) * parentScale / scale)
            if region.SetScale then region:SetScale(scale) end
            return
        end
        region:SetPoint("CENTER", region.plateSmithOverlay or region:GetParent(), "CENTER", transform.x / scale, transform.y / scale)
        if region.SetScale then region:SetScale(scale) end
    end

    local function AnchorPart(data, region, key)
        if not data.layout[key] then return end
        region:ClearAllPoints()
        region.plateSmithOverlay = data.overlay
        PlaceRegion(region, data.layout, key, data)
    end

    -- Hide with the parent: a part under another part (not a group) is hidden while that part is
    -- hidden by a rule or is a bar or aura row the plate hid (HiddenUnder); a turned-off or absent
    -- parent leaves it shown. Each part keeps deciding its own shown state; this only fades what
    -- sits under a hidden parent, so it comes back with its parent without being asked again. Per
    -- layout table: the children ({ key, parent }) and parentOf (each part's part parent).
    local partChildren = setmetatable({}, { __mode = "k" })
    local function PartChildren(layout)
        local list = partChildren[layout]
        if not list then
            list = { parentOf = {} }
            for key, position in pairs(layout) do
                local parent = type(position) == "table" and position.parent
                if parent and layout[parent] and not S.IsGroupKey(parent) then
                    list[#list + 1] = { key = key, parent = parent }
                    list.parentOf[key] = parent
                end
            end
            partChildren[layout] = list
        end
        return list
    end

    -- Scratch for one ApplyParentVisibility call: key -> whether what sits under key hides with it
    -- (key, or a part it sits under, is hidden by a rule, or is a bar or aura row the plate hid).
    -- A turned-off or absent part passes the question up to its own parent.
    local hiddenScratch = {}
    local function HiddenUnder(data, layout, parentOf, key, depth)
        local known = hiddenScratch[key]
        if known ~= nil then return known end
        local result
        local region = PartRegion(data, key)
        if not S.TurnedOff(layout[key]) and region and RuleHidden(region) then
            result = true
        elseif not S.TurnedOff(layout[key]) and not Absent(data, key) and PartHidden(data, key) then
            result = true
        else
            local parent = parentOf[key]
            result = parent ~= nil and depth < S.MAX_DEPTH and HiddenUnder(data, layout, parentOf, parent, depth + 1) or false
        end
        hiddenScratch[key] = result
        return result
    end

    -- A region's alpha: 0 while faded under a hidden parent, else its rule's opacity. Set only when
    -- it changes (region.plateSmithParentFaded records the fade), so a flush with nothing to hide
    -- writes no alphas.
    local function RegionAlpha(region)
        if region.plateSmithParentFaded then return 0 end
        return region.plateSmithRuleAlpha or 1
    end

    local function Unfade(region)
        region.plateSmithParentFaded = nil
        if region.SetAlpha then region:SetAlpha(region.plateSmithRuleAlpha or 1) end
    end

    local function SetParentFaded(region, faded, into)
        if not (region and region.SetAlpha) then return end
        if faded then
            if not region.plateSmithParentFaded then
                region.plateSmithParentFaded = true
                region:SetAlpha(0)
            end
            into[region] = true
        elseif region.plateSmithParentFaded then
            Unfade(region)
        end
    end

    -- Gives every region this plate faded under a hidden parent its own alpha back.
    local function RestoreParentFaded(data)
        local faded = data.parentFaded
        if not faded then return end
        for region in pairs(faded) do
            Unfade(region)
            faded[region] = nil
        end
        data.parentFaded, data.parentFadedSpare = nil, faded
    end

    local function ApplyParentVisibility(data)
        local layout = data.layout
        if not layout then return end
        Counters.parentVisibility = Counters.parentVisibility + 1
        Styles.SyncStyleBoxes(data)
        local children = PartChildren(layout)
        local previous = data.parentFaded
        if #children == 0 then
            RestoreParentFaded(data)
            return
        end
        -- The regions faded this time go into the plate's spare table; the two swap each call.
        local faded = data.parentFadedSpare or {}
        data.parentFadedSpare = nil
        for key in pairs(hiddenScratch) do hiddenScratch[key] = nil end
        for index = 1, #children do
            local entry = children[index]
            local under = HiddenUnder(data, layout, children.parentOf, entry.parent, 0)
            local first, second = PartRegions(data, entry.key)
            SetParentFaded(first, under, faded)
            SetParentFaded(second, under, faded)
        end
        -- Faded before but not now (moved to another parent, or another layout): its own alpha back.
        if previous then
            for region in pairs(previous) do
                if not faded[region] and region.plateSmithParentFaded then Unfade(region) end
                previous[region] = nil
            end
        end
        if next(faded) then
            data.parentFaded, data.parentFadedSpare = faded, previous
        else
            data.parentFaded, data.parentFadedSpare = nil, faded
        end
    end

    -- Values are placed like every other part (a value on a bar is that bar's child); a bar that
    -- hides takes its values with it (ApplyParentVisibility).
    UpdateValueAnchors = function(data)
        if data.valueAnchorsDirty then
            for index = 1, VALUE_SLOT_COUNT do
                local key = VALUE_KEYS[index]
                local region = data.values[key]
                if region then AnchorPart(data, region, key) end
            end
            data.valueAnchorsDirty = false
        end
        MarkVisibility(data)
    end

    local LAYOUT_PARTS = { "health", "power", "name", "level", "guild", "targetName", "cast", "threat", "tagged", "quest" }
    local LATE_LAYOUT_PARTS = { "raidIcon", "relationshipIcon", "pvpIcon", "classification", "buffs", "debuffs" }

    local function ApplyComponentLayout(data)
        Counters.componentLayout = Counters.componentLayout + 1
        -- Every part is placed where the layout's hierarchy draws it, from the plate's centre.
        data.layoutTransforms = nil -- sizes may have changed with the profile
        -- Hiding under a parent is worked out again for this layout (the flush's visibility pass).
        RestoreParentFaded(data)
        for _, key in ipairs(LAYOUT_PARTS) do AnchorPart(data, data[key], key) end
        -- The loot bag takes the quest mark's place and scale.
        data.questLoot:ClearAllPoints()
        data.questLoot:SetPoint("CENTER", data.quest, "CENTER", 0, 0)
        if data.questLoot.SetScale then
            local quest = Transforms(data.layout, data).quest
            data.questLoot:SetScale(quest and quest.scale or 1)
        end
        data.valueAnchorsDirty = true
        UpdateValueAnchors(data)
        for _, key in ipairs(LATE_LAYOUT_PARTS) do AnchorPart(data, data[key], key) end
        -- The classification's icon is placed like its text, not centred on it: an empty text is
        -- 0 px wide, so an icon on its centre would sit half over the bar it is pinned to.
        if data.classificationIcon then AnchorPart(data, data.classificationIcon, "classification") end
        Styles.ApplyDrawOrder(data)
        MarkVisibility(data)
    end

    -- The stacked parts, sorted, once per layout table.
    local stackKeysCache = setmetatable({}, { __mode = "k" })
    local function StackKeys(layout)
        local keys = stackKeysCache[layout]
        if not keys then
            keys = {}
            for key, position in pairs(layout) do
                local parent = type(position) == "table" and position.parent and layout[position.parent]
                if parent and parent.stack and not position.free and position.visible ~= false and not position.removed then
                    keys[#keys + 1] = key
                end
            end
            table.sort(keys)
            -- keys.pinParents: parts a pinned part may meet (its parent and on up); while one is
            -- absent the pinned part meets the next, so their shown state places parts too.
            local pinParents, seen = {}, {}
            for _, position in pairs(layout) do
                local parent = type(position) == "table" and S.ATTACH_EDGES[position.attach] and position.parent
                for _ = 1, S.MAX_DEPTH do
                    if type(parent) ~= "string" or S.IsGroupKey(parent) or type(layout[parent]) ~= "table" then break end
                    if not seen[parent] and not CONTAINERS[parent] and not IS_VALUE_KEY[parent] then
                        seen[parent] = true
                        pinParents[#pinParents + 1] = parent
                    end
                    parent = layout[parent].parent
                end
            end
            table.sort(pinParents)
            keys.pinParents = pinParents
            stackKeysCache[layout] = keys
        end
        return keys
    end

    -- Records the stacked parts' shown state on the plate. True when it changed since the last
    -- record (or the layout did): the plate's parts are then placed again.
    local function StackStateChanged(data)
        local layout = data.layout
        local keys = StackKeys(layout)
        local states = data.stackStates
        if not states then
            states = {}
            data.stackStates = states
        end
        local changed = data.stackStatesFor ~= layout
        for index = 1, #keys do
            local region = PartRegion(data, keys[index])
            local state = 0
            if region and region.IsShown then state = region:IsShown() and 2 or 1 end
            if states[index] ~= state then
                states[index] = state
                changed = true
            end
        end
        local pinParents, count = keys.pinParents, #keys
        for index = 1, #pinParents do
            local state = Absent(data, pinParents[index]) and 1 or 2
            if states[count + index] ~= state then
                states[count + index] = state
                changed = true
            end
        end
        for index = count + #pinParents + 1, #states do states[index] = nil end
        data.stackStatesFor = layout
        return changed
    end

    -- Stacks close up or open when one of their parts shows or hides, and a part pinned to a text
    -- follows that text's width.
    local function ReflowStacks(data, measure)
        if not (data.layout and data.own and data.overlay and HasStacks(data.layout)) then return end
        local changed = StackStateChanged(data)
        if changed or (measure and MeasuresChanged(data)) then ApplyComponentLayout(data) end
    end

    return {
        PartRegions = PartRegions, ReadNumber = ReadNumber, SafeSize = SafeSize,
        HasStacks = HasStacks, Transforms = Transforms, RestoreParentFaded = RestoreParentFaded, RegionAlpha = RegionAlpha,
        ApplyParentVisibility = ApplyParentVisibility, UpdateValueAnchors = UpdateValueAnchors,
        ApplyComponentLayout = ApplyComponentLayout, StackStateChanged = StackStateChanged, ReflowStacks = ReflowStacks,
    }
end