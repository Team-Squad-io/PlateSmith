-- Saved profile and layout mutation; rendering refreshes stay with the nameplate owner.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local L = PS.L

PS._CreatePlateSettings = function(context)
    local GetSettings = context.GetSettings
    local RefreshAll = context.RefreshAll
    local Relayout = context.Relayout or RefreshAll
    local NamePolicy = assert(PS.NamePolicy, "PlateSmith NamePolicy missing")
    local defaults = S.defaults
    local profileDefaults = S.profileDefaults
    local defaultRelationshipColours = S.defaultRelationshipColours
    local NormalizeSettings = S.NormalizeSettings
    local NormalizeProfile = S.NormalizeProfile
    local NormalizeLayout = S.NormalizeLayout
    local NormalizeColour = S.NormalizeColour
    local CopyEnemyProfile = S.CopyEnemyProfile
    local characterDefaults = S.characterDefaults
    local NormalizeCharacterSettings = S.NormalizeCharacterSettings

    -- nil is the enemy profile; an unknown name must not fall back to editing the enemy profile.
    local function ResolveProfileKey(profileKey)
        if profileKey == nil then return "enemy" end
        if profileKey == "enemyDungeon" or profileDefaults[profileKey] then return profileKey end
        return nil
    end

    -- What a profile falls back to: the dungeon override follows the enemy profile.
    local function ProfileFallback(db, profileKey)
        return profileKey == "enemyDungeon" and db.plateProfiles.enemy or profileDefaults[profileKey]
    end

    local function GetProfileSettings(profileKey)
        local db = GetSettings()
        if not db or not db.plateProfiles then return nil end
        if profileKey == "enemyDungeon" then
            return db.plateProfiles.enemyDungeon or db.plateProfiles.enemy
        end
        profileKey = profileDefaults[profileKey] and profileKey or "enemy"
        return db.plateProfiles[profileKey]
    end

    local function EnsureProfileSettings(profileKey)
        local db = GetSettings()
        if profileKey == "enemyDungeon" then
            if not db.plateProfiles.enemyDungeon then
                db.plateProfiles.enemyDungeon = CopyEnemyProfile(db.plateProfiles.enemy)
            end
            return db.plateProfiles.enemyDungeon
        end
        return GetProfileSettings(profileKey)
    end

    -- The one route for a profile edit: resolves the key, makes the dungeon override on its first
    -- edit, runs mutate(profile, db, profileKey) and refreshes the plates. mutate returns false to
    -- refuse. It writes only values it has made valid, so the profile stays normalized without a
    -- whole NormalizeProfile per keystroke. Checks that need no profile run before this, so a
    -- refused edit never creates the dungeon override.
    local function MutateProfile(profileKey, mutate)
        local db = GetSettings()
        profileKey = ResolveProfileKey(profileKey)
        if not db or not profileKey then return false end
        local profile = EnsureProfileSettings(profileKey)
        if not profile or mutate(profile, db, profileKey) == false then return false end
        RefreshAll()
        return true
    end

    local function SetProfileOption(profileKey, key, value)
        if not S.IsProfileOption(key) then return false end
        return MutateProfile(profileKey, function(profile, db, resolved)
            profile[key] = S.ProfileOptionValue(profile, key, value, ProfileFallback(db, resolved))
            if resolved == "enemy" and S.ENEMY_ALIASES[key] then db[key] = profile[key] end
        end)
    end

    local function SetOption(key, value)
        local db = GetSettings()
        if defaults[key] == nil or key == "schemaVersion" then return false end
        -- The top-level sizes are the enemy profile's.
        if S.ENEMY_ALIASES[key] then return SetProfileOption("enemy", key, value) end
        local valid = S.SettingValue(key, value)
        if valid ~= nil then
            db[key] = valid
        else
            db[key] = value
            NormalizeSettings(db)
        end
        if key == "hideUnstyledFriendlyNames" or key == "restrictedFriendlyNamesOnly"
            or key == "restrictedFriendlyClassColour" then NamePolicy.Apply() end
        RefreshAll()
        return true
    end

    local function SetDungeonEnemyProfile(profile)
        local db = GetSettings()
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
        local db = GetSettings()
        if profileKey == "enemyDungeon" then
            return NormalizeLayout(db and db.plateProfiles.enemy.layout, profileDefaults.enemy.layout)
        end
        profileKey = profileDefaults[profileKey] and profileKey or "enemy"
        local field = LayoutField(profileKey, variant)
        return NormalizeLayout(nil, profileDefaults[profileKey][field])
    end

    -- A normalized copy of a layout (the enemy's for a dungeon override that does not exist yet).
    local function GetLayout(profileKey, variant)
        local db = GetSettings()
        profileKey = profileKey == "enemyDungeon" and profileKey
            or (profileDefaults[profileKey] and profileKey or "enemy")
        local profile = GetProfileSettings(profileKey)
        local field = LayoutField(profileKey, variant)
        return NormalizeLayout(profile and profile[field], ProfileFallback(db, profileKey)[field])
    end

    local function SetLayout(layout, profileKey, variant)
        local db = GetSettings()
        profileKey = ResolveProfileKey(profileKey)
        if not db or not profileKey then return false end
        local field = LayoutField(profileKey, variant)
        local profile = EnsureProfileSettings(profileKey)
        profile[field] = NormalizeLayout(layout, ProfileFallback(db, profileKey)[field])
        if profileKey == "enemy" then db.layout = db.plateProfiles.enemy.layout end
        RefreshAll()
        return true
    end

    -- The stored layout, for reading (a copy of the enemy's while the dungeon override does not
    -- exist).
    local function ReadLayout(profileKey, variant)
        local db = GetSettings()
        profileKey = ResolveProfileKey(profileKey)
        if not db or not profileKey then return {} end
        local profile = profileKey == "enemyDungeon" and db.plateProfiles.enemyDungeon or db.plateProfiles[profileKey]
        local layout = profile and profile[LayoutField(profileKey, variant)]
        return layout or GetLayout(profileKey, variant)
    end

    -- Edits a copy of a layout: edit(layout) changes it and returns a true value (its result), or
    -- false to refuse. The copy then replaces the stored layout, normalized once, or as it is
    -- when validated (the edit wrote only valid values). A stored layout is never changed in
    -- place: the nameplates cache what they work out per layout table. The dungeon override is
    -- made by the first edit that succeeds.
    local function EditLayout(profileKey, variant, edit, validated)
        local db = GetSettings()
        profileKey = ResolveProfileKey(profileKey)
        if not db or not profileKey then return false end
        local field = LayoutField(profileKey, variant)
        local profile = profileKey == "enemyDungeon" and db.plateProfiles.enemyDungeon or db.plateProfiles[profileKey]
        if not profile or type(profile[field]) ~= "table" then
            local copy = GetLayout(profileKey, variant)
            local result = edit(copy)
            if not result then return false end
            return SetLayout(copy, profileKey, variant) and result
        end
        local layout = Table.DeepCopy(profile[field])
        local result = edit(layout)
        if not result then return false end
        profile[field] = validated and layout or NormalizeLayout(layout, ProfileFallback(db, profileKey)[field])
        if profileKey == "enemy" then db.layout = profile.layout end
        RefreshAll()
        return result
    end

    local function SetComponentPosition(key, x, y, profileKey, variant)
        x, y = tonumber(x), tonumber(y)
        if not S.PartKey(key) or not x or not y then return false end
        x, y = S.Bounded(S.layoutRanges.x, x), S.Bounded(S.layoutRanges.y, y)
        return EditLayout(profileKey, variant, function(layout)
            local position = layout[key]
            if position then
                position.x, position.y = x, y
            else
                layout[key] = { x = x, y = y, visible = true, scale = 1 }
            end
            return true
        end, true)
    end

    local function SetComponentScale(key, scale, profileKey, variant)
        scale = tonumber(scale)
        if not S.PartKey(key) or not S.InRange(S.layoutRanges.scale, scale) then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[key] then return false end
            layout[key].scale = S.ComponentScale(scale)
            return true
        end, true)
    end

    -- The hierarchy (Schema's LayoutTransforms): each entry may have a parent, a part or a group.
    -- Moving an entry to another parent keeps it where and as large as it is on the plate.
    local ROOT = { x = 0, y = 0, scale = 1 }

    -- Part sizes for laying out stacks (Studio supplies its preview's while open): without them a
    -- stacked part's drawn place is its stored offset, not where its stack puts it.
    local layoutMeasure
    local function SetLayoutMeasure(measure)
        layoutMeasure = type(measure) == "function" and measure or nil
        return true
    end

    local function Drawn(layout, key)
        local transform = S.LayoutTransforms(layout, layoutMeasure)[key] or ROOT
        return transform.x, transform.y, transform.scale
    end

    -- Sets key's offset and scale under its current parent so it is drawn at (x, y) at drawnScale.
    -- A part moved this way is placed statically (Dynamic pins to one parent's edge).
    local function PlaceDrawn(layout, key, x, y, drawnScale)
        local position = layout[key]
        position.attach = nil
        local parent = position.parent and layout[position.parent]
            and S.LayoutTransforms(layout, layoutMeasure)[position.parent] or ROOT
        position.scale = S.ComponentScale(drawnScale / parent.scale)
        position.x = S.Bounded(S.layoutRanges.x, (x - parent.x) / parent.scale)
        position.y = S.Bounded(S.layoutRanges.y, (y - parent.y) / parent.scale)
    end

    -- A part whose default is pinned to the parent it has now takes the default's pin (edge, gap
    -- and scale): the default's drawn place without sizes would put it on its parent's centre.
    local function PinAsDefault(position, default)
        if not (default and default.attach and position.parent == default.parent) then return false end
        position.attach, position.x, position.y, position.scale = default.attach, default.x, default.y, default.scale
        return true
    end

    -- Whether key sits somewhere under ancestor.
    local function IsUnder(layout, key, ancestor)
        local current, depth = layout[key] and layout[key].parent, 0
        while current and depth <= S.MAX_DEPTH do
            if current == ancestor then return true end
            current, depth = layout[current] and layout[current].parent, depth + 1
        end
        return false
    end

    -- Parent links from key up to the top, and from key down to its deepest descendant.
    local function Depth(layout, key)
        local depth, current = 0, layout[key] and layout[key].parent
        while current and depth <= S.MAX_DEPTH do
            depth, current = depth + 1, layout[current] and layout[current].parent
        end
        return depth
    end
    local function Height(layout, key, guard)
        if guard > S.MAX_DEPTH then return guard end
        local height = 0
        for child, position in pairs(layout) do
            if type(position) == "table" and position.parent == key then
                height = math.max(height, 1 + Height(layout, child, guard + 1))
            end
        end
        return height
    end

    -- parentKey's children (nil: the roots) in tree order, without except.
    local function Children(layout, parentKey, except)
        local keys = {}
        for key, position in pairs(layout) do
            if key ~= except and type(position) == "table" and position.parent == parentKey then keys[#keys + 1] = key end
        end
        return S.SortByTreeOrder(layout, keys)
    end

    -- Moves key under parentKey (nil: a root), before beforeKey (nil: last), without moving it
    -- on the plate; the new siblings are renumbered in order. Never under itself or its own
    -- children, nor deeper than the hierarchy allows.
    local function SetComponentParent(key, parentKey, beforeKey, profileKey, variant)
        return EditLayout(profileKey, variant, function(layout)
            local position = layout[key]
            if not position then return false end
            if parentKey ~= nil then
                if not layout[parentKey] or parentKey == key or IsUnder(layout, parentKey, key) then return false end
                if Depth(layout, parentKey) + 1 + Height(layout, key, 0) > S.MAX_DEPTH then return false end
            end
            if position.parent ~= parentKey then
                local x, y, scale = Drawn(layout, key)
                position.parent, position.free = parentKey, nil
                PlaceDrawn(layout, key, x, y, scale)
            end
            local siblings = Children(layout, parentKey, key)
            local index = #siblings + 1
            for siblingIndex, sibling in ipairs(siblings) do
                if sibling == beforeKey then index = siblingIndex break end
            end
            table.insert(siblings, index, key)
            for order, sibling in ipairs(siblings) do layout[sibling].order = math.min(order, 99) end
            return true
        end, true)
    end

    -- Static (edge nil) or Dynamic, pinned to its parent part's left, right, top or bottom edge.
    -- Pinning snaps it to that edge: a 4 px gap, centred along it (nudge it from there). Static
    -- keeps it where it is drawn (with Studio's sizes; without them it keeps its offset). A group
    -- parent is only Static.
    local PIN_GAP = { left = { -4, 0 }, right = { 4, 0 }, top = { 0, 4 }, bottom = { 0, -4 } }
    local function SetComponentAttach(key, edge, profileKey, variant)
        return EditLayout(profileKey, variant, function(layout)
            local position = layout[key]
            if not position or (edge ~= nil and not S.ATTACH_EDGES[edge]) then return false end
            if edge and (not position.parent or S.IsGroupKey(position.parent) or not layout[position.parent]) then
                return false
            end
            if edge then
                position.attach = edge
                position.x, position.y = PIN_GAP[edge][1], PIN_GAP[edge][2]
                return true
            end
            local x, y = Drawn(layout, key)
            position.attach = nil
            if layoutMeasure then
                local ox, oy = position.x, position.y
                position.x, position.y = 0, 0
                local base = S.LayoutTransforms(layout, layoutMeasure)[key]
                local parent = S.LayoutTransforms(layout, layoutMeasure)[position.parent] or ROOT
                if base and parent.scale ~= 0 then
                    position.x = math.floor((x - base.x) / parent.scale + 0.5)
                    position.y = math.floor((y - base.y) / parent.scale + 0.5)
                else
                    position.x, position.y = ox, oy
                end
            end
            return true
        end)
    end

    -- Deletes a built-in part: it leaves the tree and the plate (removed, hidden); what sat under
    -- it moves up to its parent without moving on the plate, except that a part pinned to it stays
    -- pinned, now to that parent (it takes the deleted part's place, as with the part turned off).
    -- RestoreComponent puts it back.
    local function RemoveComponent(key, profileKey, variant)
        return EditLayout(profileKey, variant, function(layout)
            local position = layout[key]
            if not position or S.IsGroupKey(key) or key:match("^value%d+$") or position.removed then return false end
            local partParent = position.parent and not S.IsGroupKey(position.parent) and layout[position.parent]
            for _, child in ipairs(Children(layout, key)) do
                if partParent and layout[child].attach then
                    layout[child].parent = position.parent
                else
                    local x, y, scale = Drawn(layout, child)
                    layout[child].parent = position.parent
                    PlaceDrawn(layout, child, x, y, scale)
                end
            end
            position.removed, position.visible = true, false
            return true
        end)
    end

    -- Puts a deleted part back, drawn where and as large as the default layout draws it: under
    -- parentKey when given, else its default parent when that is in the layout, else the top.
    local function RestoreComponent(key, parentKey, profileKey, variant)
        local defaultLayoutFor = GetDefaultLayout(profileKey, variant)
        return EditLayout(profileKey, variant, function(layout)
            local position = layout[key]
            if not position or not defaultLayoutFor[key] or S.IsGroupKey(key) then return false end
            local drawn = S.LayoutTransforms(defaultLayoutFor)[key] or ROOT
            local parent = parentKey
            local defaultParent = defaultLayoutFor[key].parent
            if parent == nil and defaultParent and layout[defaultParent] and not layout[defaultParent].removed then
                parent = defaultParent
            end
            if parent ~= nil and (not layout[parent] or parent == key or IsUnder(layout, parent, key)) then parent = nil end
            position.removed, position.visible, position.parent = nil, true, parent
            if not PinAsDefault(position, defaultLayoutFor[key]) then PlaceDrawn(layout, key, drawn.x, drawn.y, drawn.scale) end
            local siblings = Children(layout, parent, key)
            siblings[#siblings + 1] = key
            for order, sibling in ipairs(siblings) do layout[sibling].order = order end
            return true
        end)
    end

    -- Puts a part (or group) back to its default place and size, keeping its place in the tree.
    local function ResetComponent(key, profileKey, variant)
        local defaultLayoutFor = GetDefaultLayout(profileKey, variant)
        return EditLayout(profileKey, variant, function(layout)
            if not layout[key] then return false end
            if not S.IsGroupKey(key) and PinAsDefault(layout[key], defaultLayoutFor[key]) then return true end
            local drawn = not S.IsGroupKey(key) and defaultLayoutFor[key] and S.LayoutTransforms(defaultLayoutFor)[key] or ROOT
            PlaceDrawn(layout, key, drawn.x, drawn.y, drawn.scale)
            return true
        end)
    end

    -- Stacks key's children (stack = down, up, right, left; nil: each keeps its own place).
    local function SetComponentStack(key, stack, gap, profileKey, variant)
        if stack ~= nil and not S.STACK_DIRECTIONS[stack] then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[key] then return false end
            layout[key].stack = stack
            layout[key].gap = stack and S.Bounded(S.STACK_GAP, gap, layout[key].gap or 4) or nil
            return true
        end)
    end

    -- key's drawing layer (-10 to 10; nil: from its place in the tree).
    local function SetComponentLayer(key, layer, profileKey, variant)
        if layer ~= nil and not tonumber(layer) then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[key] then return false end
            layout[key].layer = layer and S.Bounded(S.LAYER_RANGE, layer) or nil
            return true
        end)
    end

    -- A free child keeps its own place in a stacking parent (the player put it there by hand).
    local function SetComponentFree(key, free, profileKey, variant)
        if type(free) ~= "boolean" then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[key] then return false end
            layout[key].free = free or nil
            return true
        end)
    end

    -- The quest-loot bag anchored to the quest mark (anchor "quest") or not (nil): its parent.
    local function SetComponentAnchor(key, anchor, profileKey, variant)
        return SetComponentParent(key, anchor, nil, profileKey, variant)
    end

    local function GroupKeys(layout)
        local keys = {}
        for key in pairs(layout) do if S.IsGroupKey(key) then keys[#keys + 1] = key end end
        return S.SortByTreeOrder(layout, keys, 0)
    end

    -- A new group is an empty node at the top of the tree. Returns its key.
    local function CreateComponentGroup(name, profileKey, variant)
        local created = EditLayout(profileKey, variant, function(layout)
            local keys = GroupKeys(layout)
            if #keys >= S.MAX_GROUPS then return false end
            local index = 1
            for _, key in ipairs(keys) do index = math.max(index, tonumber(key:match("%d+")) + 1) end
            for order, key in ipairs(Children(layout, nil)) do layout[key].order = order + 1 end
            local key = "group." .. index
            layout[key] = { x = 0, y = 0, visible = true, name = S.NormalizeGroupName(name) or ("Group " .. index),
                order = 1 }
            return key
        end)
        return created or nil
    end

    local function RenameComponentGroup(groupKey, name, profileKey, variant)
        local normalized = S.NormalizeGroupName(name)
        if not S.IsGroupKey(groupKey) or not normalized then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[groupKey] then return false end
            layout[groupKey].name = normalized
            return true
        end)
    end

    -- A part's name in Studio's tree; a group's is RenameComponentGroup. Blank: the standard name.
    local function RenameComponent(key, name, profileKey, variant)
        if S.IsGroupKey(key) then return RenameComponentGroup(key, name, profileKey, variant) end
        if name ~= nil and type(name) ~= "string" then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[key] then return false end
            layout[key].name = name and S.NormalizeGroupName(name) or nil
            return true
        end)
    end

    -- A part into a group (nil: out to the top), keeping where it is drawn.
    local function SetComponentGroup(key, groupKey, profileKey, variant)
        if groupKey ~= nil and not S.IsGroupKey(groupKey) then return false end
        return SetComponentParent(key, groupKey, nil, profileKey, variant)
    end

    -- Moves the group's offset, so everything under it moves with it.
    local function SetComponentGroupOffset(groupKey, x, y, profileKey, variant)
        x, y = tonumber(x), tonumber(y)
        if not S.IsGroupKey(groupKey) or not x or not y then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[groupKey] then return false end
            layout[groupKey].x, layout[groupKey].y = x, y
            return true
        end)
    end

    -- Scales a group (everything under it with it); its offset can move at the same time, to
    -- keep a corner or the centre in place.
    local function SetComponentGroupScale(groupKey, scale, x, y, profileKey, variant)
        scale = tonumber(scale)
        if not S.IsGroupKey(groupKey) or not scale then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[groupKey] then return false end
            layout[groupKey].scale = S.ComponentScale(scale)
            if tonumber(x) and tonumber(y) then layout[groupKey].x, layout[groupKey].y = tonumber(x), tonumber(y) end
            return true
        end)
    end

    -- Moves an entry next to targetKey, under the same parent (after it when after is true).
    local function MoveComponentGroupTo(groupKey, targetKey, after, profileKey, variant)
        local layout = ReadLayout(profileKey, variant)
        if not layout[groupKey] or not layout[targetKey] or groupKey == targetKey then return false end
        local parentKey = layout[targetKey].parent
        local before = targetKey
        if after then
            local siblings = Children(layout, parentKey, groupKey)
            before = nil
            for index, sibling in ipairs(siblings) do
                if sibling == targetKey then before = siblings[index + 1] break end
            end
        end
        return SetComponentParent(groupKey, parentKey, before, profileKey, variant)
    end

    -- Moves an entry up (-1) or down (1) among its siblings.
    local function MoveComponentGroup(groupKey, direction, profileKey, variant)
        return EditLayout(profileKey, variant, function(layout)
            if not layout[groupKey] then return false end
            local siblings = Children(layout, layout[groupKey].parent)
            for index, key in ipairs(siblings) do
                if key == groupKey then
                    local other = siblings[index + direction]
                    if not other then return false end
                    siblings[index], siblings[index + direction] = other, key
                    for order, entry in ipairs(siblings) do layout[entry].order = order end
                    return true
                end
            end
            return false
        end)
    end

    -- Deletes a group; what was under it moves up to the group's parent, staying where it is.
    local function DeleteComponentGroup(groupKey, profileKey, variant)
        if not S.IsGroupKey(groupKey) then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[groupKey] then return false end
            local parentKey = layout[groupKey].parent
            for _, key in ipairs(Children(layout, groupKey)) do
                local x, y, scale = Drawn(layout, key)
                layout[key].parent = parentKey
                PlaceDrawn(layout, key, x, y, scale)
            end
            layout[groupKey] = nil
            return true
        end)
    end

    local function SetComponentVisibility(key, visible, profileKey, variant)
        if not S.PartKey(key) or type(visible) ~= "boolean" then return false end
        return EditLayout(profileKey, variant, function(layout)
            if not layout[key] then return false end
            layout[key].visible = visible
            return true
        end, true)
    end

    -- A Show on plates or aura box (Schema's PART_SWITCHES): its parts' eyes, in every layout the
    -- plate types that use them draw with now (Schema's EachLiveLayout), all on or all off. Other
    -- layouts keep their own eyes; a deleted part stays deleted.
    local function SetPartShownEverywhere(key, visible)
        local db = GetSettings()
        local switch = S.partSwitches[key]
        if not db or not switch or type(visible) ~= "boolean" then return false end
        local found = false
        S.EachLiveLayout(db, switch, function(layout, profile, field)
            local copy
            for _, part in ipairs(switch.parts) do
                local position = layout[part]
                if type(position) == "table" and not position.removed then
                    found = true
                    if (position.visible ~= false) ~= visible then
                        copy = copy or Table.DeepCopy(layout)
                        copy[part].visible = visible
                    end
                end
            end
            -- A new table, never an edit in place (EditLayout says why).
            if copy then profile[field] = copy end
        end)
        if not found then return false end
        db.layout = db.plateProfiles.enemy.layout
        RefreshAll()
        return true
    end

    local function GetPartShownState(key) return S.PartShownState(GetSettings(), key) end

    -- Fractional sizes are accepted and rounded; NaN and out-of-range sizes are not.
    local function FontSizeAllowed(value)
        return type(value) == "number" and value == value
            and value >= S.valueFontRange[1] and value <= S.valueFontRange[2]
    end

    -- One custom-part field made valid: true and the value to store (nil clears an optional
    -- field), or false.
    local function SlotFieldValue(field, value)
        if field == "source" then return S.valueSources[value] ~= nil, value end
        if field == "anchor" then return S.valueAnchors[value] ~= nil, value end
        if field == "layer" then return S.valueLayers[value] ~= nil, value end
        if field == "whenMissing" then return S.missingAnchorModes[value] ~= nil, value end
        if field == "fontSize" then
            value = tonumber(value)
            if not FontSizeAllowed(value) then return false end
            return true, math.floor(value + 0.5)
        end
        if field == "colour" then
            if type(value) ~= "table" then return false end
            return true, NormalizeColour(value, S.DEFAULT_VALUE_SLOT.colour)
        end
        if field == "name" then
            -- Any text; blank clears it back to the default name.
            if value ~= nil and type(value) ~= "string" then return false end
            return true, S.NormalizeValueName(value)
        end
        if field == "kind" then
            if value ~= nil and not S.valueKinds[value] then return false end
            return true, value ~= "text" and value or nil
        end
        if field == "width" or field == "height" then
            if value ~= nil and not S.InRange(field == "width" and S.VALUE_WIDTH or S.VALUE_HEIGHT, value) then return false end
            return true, value
        end
        if field == "icon" then
            if value ~= nil and not S.valueIcons[value] then return false end
            return true, value
        end
        if field == "template" then
            -- Any text (a template that does not compile shows nothing until fixed).
            if value ~= nil and type(value) ~= "string" then return false end
            return true, S.NormalizeValueTemplate(value)
        end
        return false
    end

    local function ExistingSlot(profileKey, key)
        local resolved = ResolveProfileKey(profileKey)
        local profile = resolved and GetProfileSettings(resolved)
        return profile and profile.valueSlots and profile.valueSlots[key]
    end

    local function SetProfileValueSlot(profileKey, key, field, value)
        if not ExistingSlot(profileKey, key) then return false end
        local ok, stored = SlotFieldValue(field, value)
        if not ok then return false end
        return MutateProfile(profileKey, function(profile) profile.valueSlots[key][field] = stored end)
    end

    -- Several fields of one custom part at once, with one refresh: fields = { field = value }.
    -- false clears an optional field (name, template, kind, width, height, icon). All are checked
    -- before any is written, so a refused field leaves the part as it was.
    local CLEARABLE = { name = true, template = true, kind = true, width = true, height = true, icon = true }
    local function SetValueSlotFields(profileKey, key, fields)
        if type(fields) ~= "table" or not ExistingSlot(profileKey, key) then return false end
        local checked = {}
        for field, value in pairs(fields) do
            if value == false and CLEARABLE[field] then value = nil end
            local ok, stored = SlotFieldValue(field, value)
            if not ok then return false end
            checked[#checked + 1] = { field = field, value = stored }
        end
        return MutateProfile(profileKey, function(profile)
            local slot = profile.valueSlots[key]
            for _, entry in ipairs(checked) do slot[entry.field] = entry.value end
        end)
    end

    -- One field of a plate type's buff or debuff row layout (count, columns, size, spacing,
    -- growX, growY, showDuration); out-of-range or unknown values are refused.
    local function SetProfileAuraLayout(profileKey, kind, field, value)
        local range = S.auraLayoutRanges[field]
        local choices = field == "growX" and S.auraGrowX or field == "growY" and S.auraGrowY
        local flag = field == "showDuration"
        if (kind ~= "buffs" and kind ~= "debuffs") or not (range or choices or flag) then return false end
        if range and not S.InRange(range, value) then return false end
        if choices and not choices[value] then return false end
        if flag and type(value) ~= "boolean" then return false end
        -- A new table, not an edit in place: the plates key their aura containers by it.
        return MutateProfile(profileKey, function(profile)
            local aura = Table.DeepCopy(profile.auraLayouts[kind])
            aura[field] = value
            profile.auraLayouts[kind] = aura
        end)
    end

    -- A part's rules, replaced whole (Studio edits a copy and writes it back); nil clears them.
    local function SetPartRules(profileKey, key, list)
        if not S.PartKey(key) or (list ~= nil and type(list) ~= "table") then return false end
        return MutateProfile(profileKey, function(profile)
            profile.rules = profile.rules or {}
            profile.rules[key] = list and S.NormalizePartRules(profile.rules, key, list) or nil
        end)
    end

    -- Settings › Fading: a fade rule preset (ProfilePresets' fadeNonTarget, fadeOutOfRange) on every
    -- part the enemy plates show, found again by its condition. They stay ordinary rules, so Studio
    -- shows and edits them part by part; the shortcut only reads them back.
    local FADE_PRESETS = { fadeNonTarget = true, fadeOutOfRange = true }
    local function FadeRule(id)
        local preset = FADE_PRESETS[id] and PS.ProfilePresets and PS.ProfilePresets.Rule(id)
        return preset and preset.rules[1]
    end
    local function IsFade(rule, fade)
        return type(rule) == "table" and rule.set == "alpha" and rule.when == fade.when
    end
    -- visit(profile, key) for each part a fade applies to, in key order: shown, not deleted, and for
    -- a custom part one in use. The loot bag is not a part of its own in Studio, so it is left out.
    local function EachFadePart(db, visit)
        S.EachPlateLayout(db, S.ENEMY_PLATES, function(layout, profile)
            local keys = {}
            for key, position in pairs(layout) do
                if type(position) == "table" and not S.IsGroupKey(key) and key ~= "questLoot" and not S.TurnedOff(position) then
                    local slot = key:match("^value%d+$") and profile.valueSlots and profile.valueSlots[key]
                    if not key:match("^value%d+$") or (type(slot) == "table" and slot.source ~= "off") then
                        keys[#keys + 1] = key
                    end
                end
            end
            table.sort(keys)
            for _, key in ipairs(keys) do visit(profile, key) end
        end)
    end

    -- "all", "none" or "some" of those parts have the fade, and its opacity (the first found, else
    -- the preset's); nil for an unknown fade or when no enemy plate shows a part.
    local function GetFadeState(id)
        local fade, db = FadeRule(id), GetSettings()
        if not fade or not db then return nil end
        local on, off, alpha = 0, 0, nil
        EachFadePart(db, function(profile, key)
            local found
            for _, rule in ipairs(profile.rules and profile.rules[key] or {}) do
                if IsFade(rule, fade) then found = rule break end
            end
            if found then
                on, alpha = on + 1, alpha or found.alpha
            else
                off = off + 1
            end
        end)
        if on + off == 0 then return nil end
        return (on == 0 and "none") or (off == 0 and "all") or "some", alpha or fade.alpha
    end

    -- write(list) gets a copy of each part's rules and returns its new list (nil: unchanged). A
    -- list is replaced whole, never edited in place; the plates refresh once.
    local function EditFades(write)
        local changed = false
        EachFadePart(GetSettings(), function(profile, key)
            local rules = profile.rules or {}
            local list = write(Table.DeepCopy(rules[key] or {}))
            if list then
                profile.rules = rules
                rules[key] = #list > 0 and S.NormalizePartRules(rules, key, list) or nil
                changed = true
            end
        end)
        if changed then RefreshAll() end
        return changed
    end

    -- On: each of those parts gets the fade once, last (so it wins over the part's own opacity
    -- rules), at the current opacity; off: the fade goes from all of them.
    local function SetFadeEverywhere(id, enabled)
        local fade = FadeRule(id)
        if not fade or not GetSettings() or type(enabled) ~= "boolean" then return false end
        local _, alpha = GetFadeState(id)
        return EditFades(function(list)
            local kept, removed = {}, false
            for _, rule in ipairs(list) do
                if IsFade(rule, fade) then removed = true else kept[#kept + 1] = rule end
            end
            if enabled then kept[#kept + 1] = { when = fade.when, set = "alpha", alpha = alpha or fade.alpha } end
            if enabled or removed then return kept end
        end)
    end

    -- The fade's opacity (0-1) on every part that has it, in place; the others are left alone.
    local function SetFadeAlpha(id, alpha)
        local fade = FadeRule(id)
        if not fade or not GetSettings() or type(alpha) ~= "number" or alpha ~= alpha or alpha < 0 or alpha > 1 then
            return false
        end
        return EditFades(function(list)
            local found = false
            for _, rule in ipairs(list) do
                if IsFade(rule, fade) then rule.alpha, found = alpha, true end
            end
            if found then return list end
        end)
    end

    -- One field of a part's style (Schema's NormalizeStyles); nil clears it. Colour by health is
    -- a blend rule (SetPartRules), not a style field.
    local STYLE_FIELDS = { font = true, outline = true, shadow = true, box = true, boxColour = true, boxBorder = true,
        padding = true, texture = true, background = true, border = true, borderColour = true,
        pipFill = true, pipEmpty = true, pipWidth = true, pipHeight = true, pipSpacing = true,
        badgeSize = true, badgeSpacing = true, badgeOrientation = true, badgeInitial = true }
    local function SetPartStyle(profileKey, key, field, value)
        if not S.PartKey(key) or not STYLE_FIELDS[field] then return false end
        return MutateProfile(profileKey, function(profile)
            profile.styles = profile.styles or {}
            local style = Table.DeepCopy(profile.styles[key] or {})
            style[field] = value
            profile.styles[key] = S.NormalizeStyles({ [key] = style })[key]
        end)
    end

    -- A custom part back to an unused slot: its settings, style and rules all cleared, so the next
    -- part added there starts fresh.
    local function ResetValueSlot(profileKey, key)
        if type(key) ~= "string" or not key:match("^value%d+$") or not ExistingSlot(profileKey, key) then return false end
        return MutateProfile(profileKey, function(profile)
            profile.valueSlots[key] = S.DefaultValueSlot()
            if profile.styles then profile.styles[key] = nil end
            if profile.rules then profile.rules[key] = nil end
        end)
    end

    -- Saved styles (shared by every profile): save a part's style and rules under a name, or
    -- delete one. Applying one writes its style and rules to a part (ApplyStylePreset).
    -- Presets are the player's (account state, not a profile): they survive Revert and profile
    -- switches. Returns false and a reason a player can read when the name is empty or every
    -- preset slot is used.
    local function SaveStylePreset(name, kind, style, rules)
        local state = PS.GetState()
        if type(name) ~= "string" or not S.PRESET_KINDS[kind] then return false, "not a preset" end
        local clean = S.PresetName(name)
        if not clean then return false, L["Type a name."] end
        local presets = state.stylePresets or {}
        local count = 0
        for _ in pairs(presets) do count = count + 1 end
        if not presets[clean] and count >= S.MAX_PRESETS then
            return false, string.format(L["All %d presets are used: delete one first."], S.MAX_PRESETS)
        end
        presets[clean] = { kind = kind, style = style and Table.DeepCopy(style) or nil,
            rules = rules and Table.DeepCopy(rules) or nil }
        state.stylePresets = S.NormalizeStylePresets(presets)
        return state.stylePresets[clean] ~= nil
    end

    local function DeleteStylePreset(name)
        local state = PS.GetState()
        if not (state.stylePresets and state.stylePresets[name]) then return false end
        state.stylePresets[name] = nil
        return true
    end

    -- A preset (saved, or given as a table) onto key: its style replaces the part's and its rules
    -- replace the part's rules; a preset without one leaves that alone.
    local function ApplyStylePreset(profileKey, key, preset)
        if type(preset) == "string" then
            local presets = PS.GetState().stylePresets
            preset = presets and presets[preset]
        end
        if type(preset) ~= "table" or not S.PartKey(key) then return false end
        return MutateProfile(profileKey, function(profile)
            if preset.style then
                profile.styles = profile.styles or {}
                profile.styles[key] = S.NormalizeStyles({ [key] = preset.style })[key]
            end
            if preset.rules then
                profile.rules = profile.rules or {}
                profile.rules[key] = S.NormalizePartRules(profile.rules, key, preset.rules)
            end
        end)
    end

    local function SetProfileHealthColour(profileKey, r, g, b)
        return MutateProfile(profileKey, function(profile, db, resolved)
            profile.healthColour = NormalizeColour({ r = r, g = g, b = b }, ProfileFallback(db, resolved).healthColour)
            profile.healthColourMode = "custom"
        end)
    end

    local function SetRelationshipColour(relationship, r, g, b)
        local db = GetSettings()
        local fallback = defaultRelationshipColours[relationship]
        if not db or not fallback then return false end
        db.relationshipColours[relationship] = NormalizeColour({ r = r, g = g, b = b }, fallback)
        RefreshAll()
        return true
    end

    local function GetCharacterSettings()
        PlateSmithCharacterDB = NormalizeCharacterSettings(PlateSmithCharacterDB)
        return PlateSmithCharacterDB
    end

    local function SetCharacterOption(key, value)
        if characterDefaults[key] == nil or type(value) ~= type(characterDefaults[key]) then return false end
        if key == "tankRole" and not S.validTankRoles[value] then return false end
        GetCharacterSettings()[key] = value
        local service = PS.ThreatService
        if key == "tankRole" and service and type(service.RebuildRoster) == "function" then
            service:RebuildRoster()
            service:MarkDirty()
        end
        -- Not a profile setting: the plates update, but the profile is not marked changed (nothing
        -- to compare with the saved one) and what each plate prepared for its layout is kept.
        Relayout()
        return true
    end

    -- Resets the working copy; the saved profile changes only on Save.
    local function ResetSettings()
        NamePolicy.RestoreAll()
        PS.Profiles.Reset()
        return GetSettings()
    end

    return {
        SetOption = SetOption,
        GetLayout = GetLayout,
        SetLayout = SetLayout,
        SetComponentPosition = SetComponentPosition,
        SetComponentScale = SetComponentScale,
        SetComponentAttach = SetComponentAttach,
        SetComponentVisibility = SetComponentVisibility,
        SetPartShownEverywhere = SetPartShownEverywhere,
        GetPartShownState = GetPartShownState,
        GetPlateProfileSettings = GetProfileSettings,
        GetDungeonEnemyOverride = function()
            local db = GetSettings()
            return db and db.plateProfiles and db.plateProfiles.enemyDungeon or nil
        end,
        SetDungeonEnemyProfile = SetDungeonEnemyProfile,
        GetDefaultLayout = GetDefaultLayout,
        SetPlateProfileOption = SetProfileOption,
        SetPlateValueSlot = SetProfileValueSlot,
        SetPlateValueSlotFields = SetValueSlotFields,
        SetPlateAuraLayout = SetProfileAuraLayout,
        SetPartRules = SetPartRules,
        GetFadeState = GetFadeState,
        SetFadeEverywhere = SetFadeEverywhere,
        SetFadeAlpha = SetFadeAlpha,
        SetPartStyle = SetPartStyle,
        ResetValueSlot = ResetValueSlot,
        SaveStylePreset = SaveStylePreset,
        DeleteStylePreset = DeleteStylePreset,
        ApplyStylePreset = ApplyStylePreset,
        SetPlateProfileHealthColour = SetProfileHealthColour,
        SetRelationshipColour = SetRelationshipColour,
        GetCharacterSettings = GetCharacterSettings,
        SetCharacterOption = SetCharacterOption,
        ResetSettings = ResetSettings,
        SetComponentAnchor = SetComponentAnchor,
        CreateComponentGroup = CreateComponentGroup,
        RenameComponentGroup = RenameComponentGroup,
        SetComponentGroup = SetComponentGroup,
        SetComponentGroupOffset = SetComponentGroupOffset,
        SetComponentGroupScale = SetComponentGroupScale,
        SetComponentParent = SetComponentParent,
        RemoveComponent = RemoveComponent,
        SetComponentStack = SetComponentStack,
        SetComponentFree = SetComponentFree,
        SetComponentLayer = SetComponentLayer,
        RenameComponent = RenameComponent,
        SetLayoutMeasure = SetLayoutMeasure,
        RestoreComponent = RestoreComponent,
        ResetComponent = ResetComponent,
        MoveComponentGroupTo = MoveComponentGroupTo,
        MoveComponentGroup = MoveComponentGroup,
        DeleteComponentGroup = DeleteComponentGroup,
        ComponentGroupKeys = GroupKeys,
    }
end
