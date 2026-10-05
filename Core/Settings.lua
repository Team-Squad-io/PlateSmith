-- Saved profile and layout mutation; rendering refreshes stay with the nameplate owner.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local Designs = assert(PS.Designs, "PlateSmith Designs missing")
local L = PS.L

PS._CreatePlateSettings = function(context)
    local GetSettings = context.GetSettings
    local RefreshNow = context.RefreshAll
    -- While a slider is dragged (SetSettingsDrag, from the kit's sliders), each step is stored at once
    -- and Studio's preview follows it, but the live plates are laid out and styled again at most every
    -- DRAG_REFRESH seconds (a step relaid every plate, about 15-30 ms with a dozen of them); the
    -- slider's own write on release refreshes them in full. Anything a release leaves goes next tick.
    local DRAG_REFRESH, DRAG_TICKER = 0.15, "settings.drag"
    local drag = { active = false, pending = false }
    local function RefreshAll()
        if drag.active then
            drag.pending = true
            PS.Profiles.MarkChanged()
            PS.Ticker.SetEnabled(DRAG_TICKER, true)
            return
        end
        if drag.pending then
            drag.pending = false
            PS.Ticker.SetEnabled(DRAG_TICKER, false)
        end
        RefreshNow()
    end
    PS.Ticker.Register(DRAG_TICKER, DRAG_REFRESH, function()
        if drag.pending then
            drag.pending = false
            RefreshNow()
        elseif not drag.active then
            PS.Ticker.SetEnabled(DRAG_TICKER, false)
        end
    end)
    PS.Ticker.SetEnabled(DRAG_TICKER, false)
    local function SetSettingsDrag(active)
        drag.active = active == true
        if not drag.active and not drag.pending then PS.Ticker.SetEnabled(DRAG_TICKER, false) end
        return true
    end
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

    -- An edit target: "<plate type>" (its World design) or "<plate type>@<context>" (that context's
    -- design); "enemyDungeon" is "enemy@dungeon" (modules); nil is "enemy". "enemyPlayer" is the Enemy
    -- players layer, edited as the Enemies' "players" design (Designs.PLAYERS) against Enemies' World.
    -- Returns the plate type and the context (nil: World), or nil when target is not one: an
    -- unknown name must not fall back to editing the enemy profile. Friendly plates' "dungeon" is
    -- their Dungeons & raids design, Blizzard's: World's dungeonNamesLayout.
    local function ResolveProfileKey(target)
        if target == nil then return "enemy" end
        if target == "enemyDungeon" then return "enemy", "dungeon" end
        if target == "enemyPlayer" or target == "enemyPlayer@world" then return "enemy", Designs.PLAYERS end
        if type(target) ~= "string" then return nil end
        local plateType, design = target:match("^(%w+)@(%w+)$")
        plateType = plateType or target
        if not profileDefaults[plateType] then return nil end
        if design == "world" then design = nil end
        if design and not (S.DESIGN.STORED[plateType][design] or Designs.IsBlizzard(plateType, design)) then return nil end
        return plateType, design
    end

    -- What a profile option or layout falls back to: World for a context's design, else the plate
    -- type's defaults.
    local function ProfileFallback(db, plateType, design)
        return design and db.plateProfiles[plateType] or profileDefaults[plateType]
    end

    -- The Enemies' Dungeons & raids design (once "enemyDungeon", the dungeon override), or nil.
    local function DungeonDesign(db)
        return Designs.HasDesign(db, "enemy", "dungeon") and Designs.For(db, "enemy", "dungeon") or nil
    end

    -- The profile target draws with: World's, a full design's own table, or a sparse design's
    -- effective profile (read-only: shared with World and the resolver's cache). A context with no
    -- design draws with World's.
    local function GetProfileSettings(target)
        local db = GetSettings()
        if not db or not db.plateProfiles then return nil end
        local plateType, design = ResolveProfileKey(target)
        if not plateType then plateType, design = "enemy", nil end
        return Designs.For(db, plateType, design)
    end

    -- The one route for a profile edit, for plateType's design (nil: World; a friendly plate's
    -- Blizzard design is World). mutate(profile, db, plateType, design) edits World or a full design
    -- in place; a sparse design's edit goes to a working copy of its effective profile, and only what
    -- changed is stored, as overrides (Designs.StoreDiff), each dropped when it matches World. A
    -- context with no design refuses, and so does mutate returning false; a refused edit changes
    -- nothing. mutate writes only values it has made valid, so the profile stays normalized without a
    -- whole NormalizeProfile per keystroke.
    -- The Enemy players layer takes edits only while it exists (PS.AddDesign("enemyPlayer") makes it), so
    -- nothing makes one by accident; it stays when an edit leaves it empty. glow: the edit changes only the
    -- soft glow's look (a design's own glow option), so only the glow showing it restyles, as SetOption's;
    -- except in a sparse design, whose plates hold its resolved profile (replaced by the edit) until they are
    -- laid out again, which the refresh does (held back while a slider is dragged).
    local function RestyleGlow(db)
        PS.Profiles.MarkChanged()
        PS.TargetGlow.RestyleShown(db)
    end
    local function Mutate(db, plateType, design, mutate, glow)
        local world = db.plateProfiles[plateType]
        if not design then
            if mutate(world, db, plateType) == false then return false end
        else
            local players = design == Designs.PLAYERS
            local record = Designs.Record(db, plateType, design)
            if record and record.full == true then
                if mutate(record.design, db, plateType, design) == false then return false end
            elseif record then
                glow = false
                local before = Designs.For(db, plateType, design)
                local work = Designs.WorkingCopy(before)
                if mutate(work, db, plateType, design) == false then return false end
                Designs.StoreDiff(world, record, before, work)
                if players then Designs.SetPlayers(world, record) end
            else
                return false
            end
        end
        -- Studio may read the designs again before the refresh runs.
        Designs.Invalidate()
        if glow and PS.TargetGlow and PS.TargetGlow.RestyleShown then RestyleGlow(db) else RefreshAll() end
        return true
    end

    local function MutateProfile(target, mutate, glow)
        local db = GetSettings()
        local plateType, design = ResolveProfileKey(target)
        if not db or not plateType then return false end
        if design and Designs.IsBlizzard(plateType, design) then design = nil end
        return Mutate(db, plateType, design, mutate, glow)
    end

    local function SetProfileOption(target, key, value)
        if key == "castOnNames" then
            -- A context design's own (false: its names-only plates draw no cast bar); World has none.
            if type(value) ~= "boolean" then return false end
            return MutateProfile(target, function(profile, _, _, design)
                if not design then return false end
                if value then profile.castOnNames = nil else profile.castOnNames = false end
            end)
        end
        if not S.IsProfileOption(key) then return false end
        return MutateProfile(target, function(profile, db, plateType, design)
            profile[key] = S.ProfileOptionValue(profile, key, value, ProfileFallback(db, plateType, design))
            if plateType == "enemy" and not design and S.ENEMY_ALIASES[key] then db[key] = profile[key] end
        end, S.glowSettings[key] == true)
    end

    -- The target highlight target draws (its design's own over the general settings) written into every
    -- plate type's World design, so they all look the same; their other designs keep their own.
    local function CopyTargetHighlight(target)
        local db = GetSettings()
        local source = db and GetProfileSettings(target)
        if not source then return false end
        local highlight = S.HIGHLIGHT.Resolve(db, source)
        for _, plateType in ipairs({ "enemy", "friendlyPlayer", "friendlyNPC" }) do
            local world = db.plateProfiles[plateType]
            for _, key in ipairs(S.HIGHLIGHT.KEYS) do world[key] = S.HIGHLIGHT.Value(key, Table.DeepCopy(highlight[key])) end
        end
        Designs.Invalidate()
        RefreshAll()
        return true
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
        -- The soft glow's look reaches only the glow showing it: no plate is laid out again.
        if S.glowSettings[key] and PS.TargetGlow and PS.TargetGlow.RestyleShown then
            PS.Profiles.MarkChanged()
            PS.TargetGlow.RestyleShown(db)
            return true
        end
        RefreshAll()
        return true
    end

    -- Compat (modules, Blueprint's dungeonEnemy): a table becomes the Enemies' full Dungeons & raids
    -- design; nil removes that design.
    local function SetDungeonEnemyProfile(profile)
        local db = GetSettings()
        if not db then return false end
        local enemy = db.plateProfiles.enemy
        if profile == nil then
            Designs.SetFull(enemy, "dungeon", nil)
        elseif type(profile) == "table" then
            Designs.SetFull(enemy, "dungeon", CopyEnemyProfile(NormalizeProfile(profile, enemy)))
        else
            return false
        end
        Designs.Invalidate()
        RefreshAll()
        return true
    end

    -- Which layout a variant ("full", "names" or "dungeon") of a plate type's design draws with.
    local function LayoutField(plateType, design, variant)
        if profileDefaults[plateType].namesLayout then
            if variant == "dungeon" or design == "dungeon" then return "dungeonNamesLayout" end
            if variant == "names" then return "namesLayout" end
        end
        return "layout"
    end

    -- A layout target: plate type, the design edited (nil: World) and the layout field, or nil.
    -- Friendly plates' dungeon layout is World's (it is their Blizzard design).
    local function LayoutTarget(target, variant)
        local plateType, design = ResolveProfileKey(target)
        if not plateType then return nil end
        local field = LayoutField(plateType, design, variant)
        if field == "dungeonNamesLayout" then design = nil end
        return plateType, design, field
    end

    -- What a layout is normalized against: a full design's, World's (as the dungeon override's
    -- always was); World's and a sparse design's (merged against them), the defaults.
    local function LayoutFallback(db, plateType, design, field)
        if design and Designs.IsFull(db, plateType, design) then return db.plateProfiles[plateType][field] end
        return profileDefaults[plateType][field]
    end

    -- What Reset puts back: the defaults, or for a context's design World's layout.
    local function GetDefaultLayout(target, variant)
        local db = GetSettings()
        local plateType, design, field = LayoutTarget(target, variant)
        if not plateType then plateType, design, field = "enemy", nil, "layout" end
        if design then return NormalizeLayout(db and db.plateProfiles[plateType][field], profileDefaults[plateType][field]) end
        return NormalizeLayout(nil, profileDefaults[plateType][field])
    end

    -- A normalized copy of the layout target draws with (World's for a context with no design).
    local function GetLayout(target, variant)
        local db = GetSettings()
        local plateType, design, field = LayoutTarget(target, variant)
        if not plateType then plateType, design, field = "enemy", nil, "layout" end
        local profile = db and Designs.For(db, plateType, design)
        local fallback = db and LayoutFallback(db, plateType, design, field) or profileDefaults[plateType][field]
        return NormalizeLayout(profile and profile[field], fallback)
    end

    -- Edits a copy of target's layout: edit(layout) changes it and returns a true value (its
    -- result), or false to refuse. The copy then replaces the stored layout, normalized once, or as
    -- it is when validated (the edit wrote only valid values). A stored layout is never changed in
    -- place: the nameplates cache what they work out per layout table. A sparse design's copy is of
    -- its effective layout, and only the entries the edit changed are stored, per sub-area.
    local function EditLayout(target, variant, edit, validated)
        local db = GetSettings()
        local plateType, design, field = LayoutTarget(target, variant)
        if not db or not plateType then return false end
        local fallback = LayoutFallback(db, plateType, design, field)
        local result
        local done = Mutate(db, plateType, design, function(profile)
            local layout = type(profile[field]) == "table" and Table.DeepCopy(profile[field]) or NormalizeLayout(nil, fallback)
            result = edit(layout)
            if not result then return false end
            profile[field] = validated and layout or NormalizeLayout(layout, fallback)
            if plateType == "enemy" and not design then db.layout = profile.layout end
        end)
        return done and result
    end

    local function SetLayout(layout, target, variant)
        return EditLayout(target, variant, function(copy)
            Table.Replace(copy, Table.DeepCopy(type(layout) == "table" and layout or {}))
            return true
        end)
    end

    -- The layout target draws with, for reading only (World's for a context with no design).
    local function ReadLayout(target, variant)
        local db = GetSettings()
        local plateType, design, field = LayoutTarget(target, variant)
        if not db or not plateType then return {} end
        local profile = Designs.For(db, plateType, design)
        return profile and profile[field] or GetLayout(target, variant)
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

    -- A new group is an empty node at the top of the tree. Returns its key: one no design of the
    -- plate type uses there (World's and a context's groups never share a key).
    local function CreateComponentGroup(name, profileKey, variant)
        local db = GetSettings()
        local plateType, _, field = LayoutTarget(profileKey, variant)
        local inUse = db and plateType and Designs.InUse(db, plateType, field) or {}
        local created = EditLayout(profileKey, variant, function(layout)
            local keys = GroupKeys(layout)
            if #keys >= S.MAX_GROUPS then return false end
            local index = 1
            for _, key in ipairs(keys) do index = math.max(index, tonumber(key:match("%d+")) + 1) end
            for key in pairs(inUse) do
                if S.IsGroupKey(key) then index = math.max(index, tonumber(key:match("%d+")) + 1) end
            end
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
    -- layouts keep their own eyes; a deleted part stays deleted. Every design: World and each full
    -- design are set; a sparse design follows World's eye, so only one with its own eye for the part
    -- is set, through its override (dropped where it now matches World). The Enemy players layer is
    -- one record for every place: it is set once, from its World visit (an Enemies context design's
    -- entry must not be stored in it).
    local function SetPartShownEverywhere(key, visible)
        local db = GetSettings()
        local switch = S.partSwitches[key]
        if not db or not switch or type(visible) ~= "boolean" then return false end
        local found, own = false, {}
        S.EachLiveLayout(db, switch, function(layout, profile, field, plateType, design, record)
            if plateType == "enemyPlayer" and design ~= "world" then return end
            local sparse = record and record.full ~= true
            local entries = sparse and type(record.layouts) == "table" and record.layouts[field] or nil
            local copy
            for _, part in ipairs(switch.parts) do
                local position = layout[part]
                if type(position) == "table" and not position.removed then
                    if not sparse then
                        found = true
                        if (position.visible ~= false) ~= visible then
                            copy = copy or Table.DeepCopy(layout)
                            copy[part].visible = visible
                        end
                    elseif type(entries) == "table" and type(entries[part]) == "table" and entries[part].visible ~= nil then
                        found = true
                        local entry = Table.DeepCopy(position)
                        entry.visible = visible
                        local world = db.plateProfiles[plateType == "enemyPlayer" and "enemy" or plateType]
                        own[#own + 1] = { world = world, record = record, field = field, part = part, entry = entry }
                    end
                end
            end
            -- A new table, never an edit in place (EditLayout says why).
            if copy then profile[field] = copy end
        end)
        if not found then return false end
        -- After World's eyes, so an override that now matches World's goes.
        for _, edit in ipairs(own) do
            Designs.StoreEntry(edit.world, edit.record, edit.field, edit.part, edit.entry)
            if edit.world.players == edit.record then Designs.SetPlayers(edit.world, edit.record) end
        end
        db.layout = db.plateProfiles.enemy.layout
        Designs.Invalidate()
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
        local profile = ResolveProfileKey(profileKey) and GetProfileSettings(profileKey)
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
    -- growX, growY, showDuration, timeSize, and the countdown's timeFont, timeFontSize, timeOutline, timeShadow and timePosition,
    -- which nil clears, and timedOnly, which nil or false turns off); out-of-range or unknown values are refused.
    local function SetProfileAuraLayout(profileKey, kind, field, value)
        local range = S.auraLayoutRanges[field] or field == "timeFontSize" and S.STYLE_FONT_SIZE or nil
        local choices = field == "growX" and S.auraGrowX or field == "growY" and S.auraGrowY
            or field == "timeOutline" and S.STYLE_OUTLINES or field == "timePosition" and S.auraTimePositions
        local flag = field == "showDuration" or field == "timeShadow" or field == "timedOnly"
        local optional = (S.auraTimeFields[field] or field == "timedOnly") and value == nil
        if (kind ~= "buffs" and kind ~= "debuffs") or not (range or choices or flag or field == "timeFont") then return false end
        if not optional then
            if range and not S.InRange(range, value) then return false end
            if choices and not choices[value] then return false end
            if flag and type(value) ~= "boolean" then return false end
            if field == "timeFont" and not PS.Media.IsFont(value) then return false end
        end
        -- Off is stored as absent, as the Schema keeps it.
        if field == "timedOnly" and value == false then value = nil end
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
    -- Whether a fade applies to key in profile: a part shown there, not deleted, and for a custom
    -- part one in use. The loot bag is not a part of its own in Studio, so it is left out.
    local function Fadeable(profile, key)
        local position = type(profile.layout) == "table" and profile.layout[key]
        if type(position) ~= "table" or S.IsGroupKey(key) or key == "questLoot" or S.TurnedOff(position) then return false end
        if not key:match("^value%d+$") then return true end
        local slot = type(profile.valueSlots) == "table" and profile.valueSlots[key]
        return type(slot) == "table" and slot.source ~= "off"
    end

    -- visit(profile, key, plateType, design, record) for each part a fade applies to (Fadeable), in
    -- key order. Every enemy design: World's and each full design's parts; a sparse design takes
    -- World's rules, so only the parts it has its own rules for, and those it shows where World's
    -- visit does not reach them (hidden or unused in World). The Enemy players layer's own rules are
    -- the same in every place: it is visited once, on World, against the Enemies' World.
    local function EachFadePart(db, visit)
        local enemyWorld = db.plateProfiles.enemy
        Designs.EachDesign(db, S.ENEMY_PLATES, function(profile, plateType, design, record)
            if type(profile.layout) ~= "table" or (plateType == "enemyPlayer" and design ~= "world") then return end
            local own = record and record.full ~= true and (type(record.rules) == "table" and record.rules or {}) or nil
            local keys = {}
            for key in pairs(profile.layout) do
                if Fadeable(profile, key) and (not own or own[key] ~= nil or not Fadeable(enemyWorld, key)) then
                    keys[#keys + 1] = key
                end
            end
            table.sort(keys)
            for _, key in ipairs(keys) do visit(profile, key, plateType, design, record) end
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
    -- list is replaced whole, never edited in place; the plates refresh once. A sparse design's
    -- lists are stored as its overrides (one that now matches World's goes).
    local function EditFades(write)
        local db = GetSettings()
        local changed, sparse = false, {}
        EachFadePart(db, function(profile, key, plateType, design, record)
            local rules = profile.rules or {}
            local list = write(Table.DeepCopy(rules[key] or {}))
            if not list then return end
            changed = true
            if record and record.full ~= true then
                local edit = sparse[record] or { plateType = plateType, design = design, lists = {} }
                sparse[record], edit.lists[key] = edit, list
            else
                profile.rules = rules
                rules[key] = #list > 0 and S.NormalizePartRules(rules, key, list) or nil
            end
        end)
        if not changed then return false end
        Designs.Invalidate()
        for record, edit in pairs(sparse) do
            local before = Designs.For(db, edit.plateType, edit.design)
            local work = Designs.WorkingCopy(before)
            work.rules = work.rules or {}
            for key, list in pairs(edit.lists) do
                work.rules[key] = #list > 0 and S.NormalizePartRules(work.rules, key, list) or nil
            end
            local world = db.plateProfiles[edit.plateType == "enemyPlayer" and "enemy" or edit.plateType]
            Designs.StoreDiff(world, record, before, work)
            if world.players == record then Designs.SetPlayers(world, record) end
        end
        Designs.Invalidate()
        RefreshAll()
        return true
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
    local STYLE_FIELDS = S.DESIGN.STYLE_FIELDS
    local function SetPartStyle(profileKey, key, field, value)
        if not S.PartKey(key) or not STYLE_FIELDS[field] then return false end
        if field == "fontSize" and value ~= nil and not S.InRange(S.STYLE_FONT_SIZE, value) then return false end
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
        return MutateProfile(profileKey, function(profile, db, plateType, design)
            profile.healthColour = NormalizeColour({ r = r, g = g, b = b }, ProfileFallback(db, plateType, design).healthColour)
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

    -- A threat colour (Nameplates/ThreatColours.lua): the shared one, or with part that part's own
    -- while its Own colours is on.
    local function SetThreatColour(state, r, g, b, part)
        local db = GetSettings()
        local fallback = S.THREAT_COLOURS.defaults[state]
        if not db or not fallback then return false end
        local colour = NormalizeColour({ r = r, g = g, b = b }, fallback)
        if part == nil then
            db.threatColours[state] = colour
        else
            local own = S.THREAT_COLOURS.isPart[part] and db.threatPartColours[part]
            if not own then return false end
            own[state] = colour
        end
        RefreshAll()
        return true
    end

    -- A part's Own colours: on starts from the shared colours, off goes back to them.
    local function SetThreatPartOwnColours(part, on)
        local db = GetSettings()
        if not db or not S.THREAT_COLOURS.isPart[part] then return false end
        if on then
            if not db.threatPartColours[part] then db.threatPartColours[part] = Table.DeepCopy(db.threatColours) end
        else
            db.threatPartColours[part] = nil
        end
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

    -- Context designs as wholes (Studio's design row): plateType's design for a context. Like any
    -- edit, each needs Save and Revert undoes it. The logic is Designs'.
    local designs = {}
    -- World, the stored record (nil: none yet) and the settings, or nil when plateType cannot store
    -- a design for context (friendly plates' Dungeons & raids design is Blizzard's: always there).
    local function DesignOf(plateType, design)
        local db = GetSettings()
        -- The Enemy players layer: "enemyPlayer" (its one design, whatever the context named) or the
        -- Enemies' "players"; added (empty), reset and removed, never copied or slimmed.
        if plateType == "enemyPlayer" or (plateType == "enemy" and design == Designs.PLAYERS) then
            if not db then return nil end
            return db.plateProfiles.enemy, Designs.Record(db, "enemy", Designs.PLAYERS), db, true
        end
        local stored = S.DESIGN.STORED[plateType]
        if not db or not stored or not stored[design] then return nil end
        return db.plateProfiles[plateType], Designs.Record(db, plateType, design)
    end
    local function DesignsChanged()
        Designs.Invalidate()
        RefreshAll()
        return true
    end

    -- A new design that follows World: starter "world" (or nil) with no overrides, or "light"
    -- (Cities & inns only; Designs.Starter). false when it exists already.
    function designs.AddDesign(plateType, design, starter)
        local world, record, _, players = DesignOf(plateType, design)
        if not world or record then return false end
        if players then
            -- Enemy players' one layer: no place named, no starter.
            if (design ~= nil and design ~= "world") or (starter ~= nil and starter ~= "world") then return false end
            Designs.SetPlayers(world, {})
            return DesignsChanged()
        end
        if starter ~= nil and starter ~= "world" and not (starter == "light" and design == "city") then return false end
        Designs.SetSparse(world, design, Designs.Starter(world, starter))
        return DesignsChanged()
    end

    -- "Use World again": the design goes.
    function designs.RemoveDesign(plateType, design)
        local world, record, _, players = DesignOf(plateType, design)
        if not record or (players and design ~= nil and design ~= "world") then return false end
        if players then Designs.SetPlayers(world, nil) else Designs.SetFull(world, design, nil) end
        return DesignsChanged()
    end

    -- Every override goes; the design stays, following World (a full one becomes sparse).
    function designs.ResetDesign(plateType, design)
        local world, record, _, players = DesignOf(plateType, design)
        if not record or not Designs.ResetAll(record) then return false end
        if players then Designs.SetPlayers(world, record) end
        return DesignsChanged()
    end

    -- One area back to World (Designs.Reset's area): a full design takes World's value and stays full.
    function designs.ResetDesignArea(plateType, design, area)
        local world, record, _, players = DesignOf(plateType, design)
        if not record or not Designs.Reset(world, record, area, players and "enemy" or plateType) then return false end
        if players then Designs.SetPlayers(world, record) end
        return DesignsChanged()
    end

    -- "Slim down to differences": a full design becomes the sparse one that draws the same.
    function designs.SlimDesign(plateType, design)
        local world, record, _, players = DesignOf(plateType, design)
        if not record or players or not Designs.Slim(world, record) then return false end
        return DesignsChanged()
    end

    -- "Start from another design": to's design becomes a sparse copy of from's ("world": none, so it
    -- follows World), made if to had none.
    function designs.CopyDesign(plateType, from, to)
        local world, _, _, players = DesignOf(plateType, to)
        if not world or players or from == to then return false end
        local copy = {}
        if from ~= "world" then
            local _, source = DesignOf(plateType, from)
            copy = source and Designs.CopyFrom(world, source)
            if not copy then return false end
        end
        Designs.SetSparse(world, to, copy)
        return DesignsChanged()
    end

    -- A custom-part slot free in every design of target's plate type (Designs.FreeValueSlot), or nil.
    function designs.FreeValueSlot(target)
        local db = GetSettings()
        local plateType = ResolveProfileKey(target)
        return db and plateType and Designs.FreeValueSlot(db, plateType) or nil
    end

    local api = {
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
        GetDungeonEnemyOverride = function() return DungeonDesign(GetSettings()) end,
        SetDungeonEnemyProfile = SetDungeonEnemyProfile,
        GetDefaultLayout = GetDefaultLayout,
        SetPlateProfileOption = SetProfileOption,
        CopyTargetHighlight = CopyTargetHighlight,
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
        SetThreatColour = SetThreatColour,
        SetThreatPartOwnColours = SetThreatPartOwnColours,
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
        SetSettingsDrag = SetSettingsDrag,
        RestoreComponent = RestoreComponent,
        ResetComponent = ResetComponent,
        MoveComponentGroupTo = MoveComponentGroupTo,
        MoveComponentGroup = MoveComponentGroup,
        DeleteComponentGroup = DeleteComponentGroup,
        ComponentGroupKeys = GroupKeys,
    }
    for name, fn in pairs(designs) do api[name] = fn end
    return api
end
