-- Context designs: how each plate type looks in dungeons & raids, battlegrounds & arenas and cities
-- & inns, resolved against its World design. The one merge point; it knows nothing about zones or plates.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local L = PS.L

-- Storage (plateProfiles.<type>.contexts.<context>, made valid by Schema's NormalizeContexts):
--   full:   { full = true, design = <a whole profile> }: drawn as it is; World's changes never reach it.
--   sparse: only what differs from World, at a fixed granularity:
--     options     = { <profile option> = value, castOnNames = false, ["-"] = { <optional option> = true } }
--     layouts     = { layout | namesLayout = { <entry> = { placement = { x, y, scale, parent, attach, free,
--                     stack, gap, layer, order }, visible, removed, name (false: standard), added, deleted } } }
--     styles      = { <part> = { <field> = value, ["-"] = { <field> = true } } }
--     rules       = { <part> = <list replacing World's; {} = none here> }
--     valueSlots  = { <slot> = <whole record> }
--     auraLayouts = { buffs | debuffs = { <field> = value, ["-"] = { <optional field> = true } } }
-- deleted is a World group missing here; added is an entry only this design has (with its placement).
-- An entry or slot World no longer has (an orphan) is ignored.
-- Enemy players (plate type "enemyPlayer"): plateProfiles.enemy.players, the same sparse shape, is one
-- layer over whichever design the Enemies draw with (World or a context design), so enemy players
-- follow the Enemies everywhere except what it changes. Absent or empty: the Enemies' own table. It
-- exists (Studio's Enemy players tab can edit it) from PS.AddDesign("enemyPlayer") until
-- PS.RemoveDesign("enemyPlayer"), even while empty. Settings and the editing helpers address it as the
-- Enemies' "players" design.
local DESIGN = S.DESIGN
local CLEAR = DESIGN.CLEAR
local PLACEMENT = DESIGN.PLACEMENT
local LAYOUT_FIELDS = DESIGN.LAYOUT_FIELDS

local Designs = { revision = 0, stats = { merges = 0, hits = 0, layoutMemoHits = 0 } }
PS.Designs = Designs
local stats = Designs.stats

Designs.CONTEXTS = DESIGN.ORDER
Designs.ORDER = { world = 0, dungeon = 1, pvp = 2, city = 3 }
Designs.LABELS = { world = L["World"], dungeon = L["Dungeons & raids"], pvp = L["Battlegrounds & arenas"],
    city = L["Cities & inns"] }
Designs.AREAS = { "options", "layouts", "styles", "rules", "valueSlots", "auraLayouts" }
-- The Enemy players layer's design key on the Enemies (not a context: no place selects it).
local PLAYERS = "players"
Designs.PLAYERS = PLAYERS

-- Profile keys a sparse design's effective profile builds itself rather than taking from World.
local BUILT = { contexts = true, players = true, layout = true, namesLayout = true, styles = true, rules = true,
    valueSlots = true, auraLayouts = true }
local OPTION_EXTRAS = { healthColour = true, castOnNames = true }
-- A layout override's sub-areas, by the name Reset takes.
local SUB_AREAS = { placement = "placement", eye = "visible", presence = "removed", label = "name" }

local function Copy(map)
    local copy = {}
    for key, value in pairs(type(map) == "table" and map or {}) do copy[key] = value end
    return copy
end
local function Packed(map) return next(map) ~= nil and map or nil end

-- fn(key) once for each key of a or b.
local function EachKey(a, b, fn)
    for key in pairs(a) do fn(key) end
    for key in pairs(b) do if a[key] == nil then fn(key) end end
end

local function WorldOf(db, plateType)
    local profiles = type(db) == "table" and db.plateProfiles
    local world = type(profiles) == "table" and profiles[plateType]
    return type(world) == "table" and world or nil
end

-- The stored record of a context this plate type may store, or nil (a full record without a design
-- table counts as none).
local function RecordOf(world, plateType, context)
    if context == PLAYERS then
        return plateType == "enemy" and type(world.players) == "table" and world.players or nil
    end
    local stored, contexts = DESIGN.STORED[plateType], world.contexts
    if not (stored and stored[context]) or type(contexts) ~= "table" then return nil end
    local record = contexts[context]
    if type(record) ~= "table" or (record.full == true and type(record.design) ~= "table") then return nil end
    return record
end

-- Friendly plates' Dungeons & raids design: World's dungeonNamesLayout, which Blizzard draws.
local function IsBlizzard(plateType, context)
    local defaults = S.profileDefaults[plateType]
    return context == "dungeon" and defaults ~= nil and defaults.namesLayout ~= nil
end
Designs.IsBlizzard = IsBlizzard

-- Merges: layouts and aura rows are only ever replaced, never edited in place, so a merge of the
-- same World table and override table is kept by identity (weak keys) across revisions. The plates
-- then keep their transforms, aura containers and prepared layouts warm.
local weakKeys = { __mode = "k" }
local layoutMemo = setmetatable({}, weakKeys)
local auraMemo = setmetatable({}, weakKeys)
local function Remembered(memo, base, override)
    local byBase = memo[base]
    return byBase and byBase[override]
end
local function Remember(memo, base, override, merged)
    local byBase = memo[base]
    if not byBase then
        byBase = setmetatable({}, weakKeys)
        memo[base] = byBase
    end
    byBase[override] = merged
    return merged
end

-- A table's fields with override's on top and its "-" fields cleared (styles, aura rows, options).
local function MergeFields(base, override)
    local merged = Copy(base)
    for key, value in pairs(override) do if key ~= CLEAR then merged[key] = value end end
    for key in pairs(type(override[CLEAR]) == "table" and override[CLEAR] or {}) do merged[key] = nil end
    return merged
end

local function MergeEntry(base, override)
    local entry = Copy(base)
    if override.placement then
        for _, field in ipairs(PLACEMENT) do entry[field] = override.placement[field] end
    end
    if override.visible ~= nil then entry.visible = override.visible end
    if override.removed ~= nil then entry.removed = override.removed or nil end
    if override.name ~= nil then entry.name = override.name or nil end
    return entry
end

-- World's layout with a design's entry overrides, normalised once against the plate type's
-- default layout (which repairs a parent the design removed and any cycle it made).
function Designs.MergeLayout(base, overrides, fallback)
    local merged = Remembered(layoutMemo, base, overrides)
    if merged then
        stats.layoutMemoHits = stats.layoutMemoHits + 1
        return merged
    end
    local raw, deleted = Copy(base), nil
    for key, override in pairs(overrides) do
        local entry = base[key]
        if type(override) == "table" then
            if override.deleted then
                if S.IsGroupKey(key) and type(entry) == "table" then
                    raw[key] = nil
                    deleted = deleted or {}
                    deleted[key] = entry
                end
            elseif type(entry) == "table" then
                raw[key] = MergeEntry(entry, override)
            elseif override.added then
                raw[key] = MergeEntry({ visible = true }, override)
            end
        end
    end
    -- What still sits in a group deleted here (World put it there later) moves up to the group's
    -- parent, drawn where World draws it, so normalising does not bring the group back.
    for key, entry in pairs(deleted and raw or {}) do
        local parent = type(entry) == "table" and entry.parent
        if parent and deleted[parent] then
            local x, y, scale = tonumber(entry.x) or 0, tonumber(entry.y) or 0, tonumber(entry.scale) or 1
            local depth = 0
            while parent and deleted[parent] and depth <= S.MAX_DEPTH do
                local group = deleted[parent]
                local groupScale = tonumber(group.scale) or 1
                x, y = (tonumber(group.x) or 0) + x * groupScale, (tonumber(group.y) or 0) + y * groupScale
                scale, parent, depth = scale * groupScale, group.parent, depth + 1
            end
            local moved = Copy(entry)
            moved.parent, moved.attach, moved.x, moved.y, moved.scale = parent, nil, x, y, scale
            raw[key] = moved
        end
    end
    return Remember(layoutMemo, base, overrides, S.NormalizeLayout(raw, fallback))
end

local function MergeAuraRow(base, override)
    return Remembered(auraMemo, base, override) or Remember(auraMemo, base, override, MergeFields(base, override))
end

-- The effective profile of a sparse design: a new table. Areas without overrides are World's own
-- tables, shared by reference; every table it holds is read-only.
local function Resolve(world, record, plateType)
    stats.merges = stats.merges + 1
    local fallback = S.profileDefaults[plateType] or S.profileDefaults.enemy
    local profile = {}
    for key, value in pairs(world) do if not BUILT[key] then profile[key] = value end end
    if record.options then
        for key, value in pairs(record.options) do if key ~= CLEAR then profile[key] = value end end
        for key in pairs(type(record.options[CLEAR]) == "table" and record.options[CLEAR] or {}) do profile[key] = nil end
    end
    local layouts = type(record.layouts) == "table" and record.layouts or {}
    for _, field in ipairs(LAYOUT_FIELDS) do
        local base = world[field]
        if type(base) == "table" and type(layouts[field]) == "table" then
            profile[field] = Designs.MergeLayout(base, layouts[field], fallback[field])
        else
            profile[field] = base
        end
    end
    if record.styles then
        local styles = Copy(world.styles)
        for part, override in pairs(record.styles) do styles[part] = Packed(MergeFields(styles[part], override)) end
        profile.styles = styles
    else
        profile.styles = world.styles
    end
    if record.rules then
        local rules = Copy(world.rules)
        for part, list in pairs(record.rules) do rules[part] = #list > 0 and list or nil end
        -- Merged, a design's lists still keep within the plate's rule limits.
        profile.rules = S.NormalizeRules(rules)
    else
        profile.rules = world.rules
    end
    if record.valueSlots then
        local slots = Copy(world.valueSlots)
        for key, slot in pairs(record.valueSlots) do slots[key] = slot end
        profile.valueSlots = slots
    else
        profile.valueSlots = world.valueSlots
    end
    if record.auraLayouts then
        local auras = Copy(world.auraLayouts)
        for kind, override in pairs(record.auraLayouts) do
            if type(auras[kind]) == "table" then auras[kind] = MergeAuraRow(auras[kind], override) end
        end
        profile.auraLayouts = auras
    else
        profile.auraLayouts = world.auraLayouts
    end
    return profile
end

-- plateType -> context -> { rev, world, ctx, profile }: valid while the revision and both
-- identities match. styles, rules and valueSlots are rebuilt per revision: World edits a custom
-- part's fields in place, and every edit route calls Invalidate.
local cache = {}

-- The profile plateType draws with in context (nil or "world": World). No design for that context
-- (or one this type may not store): World. A full design: its own table. A sparse design: the
-- effective profile, merged once per revision. A cache hit allocates nothing.
local PlayersFor
function Designs.For(db, plateType, context)
    if plateType == "enemy" and context == PLAYERS then plateType, context = "enemyPlayer", nil end
    if plateType == "enemyPlayer" then return PlayersFor(db, context) end
    local world = WorldOf(db, plateType)
    if not world then return nil end
    local record = context ~= nil and context ~= "world" and RecordOf(world, plateType, context) or nil
    if not record then
        stats.hits = stats.hits + 1
        return world
    end
    if record.full == true then
        stats.hits = stats.hits + 1
        return record.design
    end
    local byType = cache[plateType]
    if not byType then
        byType = {}
        cache[plateType] = byType
    end
    local entry = byType[context]
    if entry and entry.rev == Designs.revision and entry.world == world and entry.ctx == record then
        stats.hits = stats.hits + 1
        return entry.profile
    end
    if not entry then
        entry = {}
        byType[context] = entry
    end
    entry.rev, entry.world, entry.ctx = Designs.revision, world, record
    entry.profile = Resolve(world, record, plateType)
    return entry.profile
end

-- The Enemies' players layer when it holds anything, else nil.
local function PlayersOf(world)
    local players = world and world.players
    return type(players) == "table" and next(players) ~= nil and players or nil
end

-- Enemy players in context: the Enemies' design there with the players layer on top, merged once
-- per revision and Enemies design; no layer: the Enemies' table itself.
PlayersFor = function(db, context)
    local base = Designs.For(db, "enemy", context)
    local players = PlayersOf(WorldOf(db, "enemy"))
    if not base or not players then return base end
    context = context or "world"
    local byType = cache.enemyPlayer
    if not byType then
        byType = {}
        cache.enemyPlayer = byType
    end
    local entry = byType[context]
    if entry and entry.rev == Designs.revision and entry.world == base and entry.ctx == players then
        stats.hits = stats.hits + 1
        return entry.profile
    end
    if not entry then
        entry = {}
        byType[context] = entry
    end
    entry.rev, entry.world, entry.ctx = Designs.revision, base, players
    entry.profile = Resolve(base, players, "enemy")
    return entry.profile
end

-- As For, but never reading or writing its cache: for a settings table other than the working one
-- (the Blueprint import preview's), so the plates' designs keep their cached tables. A sparse design
-- is merged again on every call.
function Designs.Peek(db, plateType, context)
    if plateType == "enemy" and context == PLAYERS then plateType, context = "enemyPlayer", nil end
    if plateType == "enemyPlayer" then
        local base = Designs.Peek(db, "enemy", context)
        local players = PlayersOf(WorldOf(db, "enemy"))
        if not base or not players then return base end
        return Resolve(base, players, "enemy")
    end
    local world = WorldOf(db, plateType)
    if not world then return nil end
    local record = context ~= nil and context ~= "world" and RecordOf(world, plateType, context) or nil
    if not record then return world end
    if record.full == true then return record.design end
    return Resolve(world, record, plateType)
end

-- Stores record as the Enemies' players layer (world: the Enemies' World); nil removes it. An empty
-- one stays (the layer exists, changing nothing), and enemy players draw with the Enemies' own tables.
function Designs.SetPlayers(world, record)
    world.players = type(record) == "table" and record or nil
end

-- Stores design (a whole, normalised profile) as world's full design for context; nil removes that
-- context's design. The dungeon override's compat routes (Settings, Blueprint's dungeonEnemy) use it.
function Designs.SetFull(world, context, design)
    if design == nil then
        if type(world.contexts) ~= "table" then return end
        world.contexts[context] = nil
        if next(world.contexts) == nil then world.contexts = nil end
        return
    end
    world.contexts = type(world.contexts) == "table" and world.contexts or {}
    world.contexts[context] = { full = true, design = design }
end

-- Every route that changes settings calls this, so the next For merges again.
function Designs.Invalidate()
    Designs.revision = Designs.revision + 1
end

-- World always; a friendly type's Dungeons & raids design always (Blizzard's); else a stored one.
-- Enemy players have the Enemies' designs (their layer sits on each).
function Designs.HasDesign(db, plateType, context)
    if plateType == "enemyPlayer" then plateType = "enemy" end
    local world = WorldOf(db, plateType)
    if not world then return false end
    if context == nil or context == "world" or IsBlizzard(plateType, context) then return true end
    return RecordOf(world, plateType, context) ~= nil
end

function Designs.IsFull(db, plateType, context)
    local world = WorldOf(db, plateType)
    local record = world and RecordOf(world, plateType, context)
    return type(record) == "table" and record.full == true
end

-- { { context = "world" }, then each design in context order: { context, full = true | nil,
-- blizzard = true | nil } }.
function Designs.List(db, plateType)
    local world = WorldOf(db, plateType)
    local list = { { context = "world" } }
    if not world then return list end
    for _, context in ipairs(Designs.CONTEXTS) do
        if IsBlizzard(plateType, context) then
            list[#list + 1] = { context = context, blizzard = true }
        else
            local record = RecordOf(world, plateType, context)
            if record then list[#list + 1] = { context = context, full = record.full == true or nil } end
        end
    end
    return list
end

-- visit(profile, plateType, context, record) for each design of plates (nil: every plate type), in
-- plate type then context order, World first. A sparse design's profile is its effective one
-- (read-only). Saved data from before schema 29 (mid-migration) may still hold the dungeon
-- override as plateProfiles.enemyDungeon: it is visited as the Enemies' dungeon design.
-- Enemy players (plates.enemyPlayer, or every plate type) are visited only while their layer holds
-- anything: on World and on each Enemies design, as "enemyPlayer" with that design's context and the
-- layer as the record. Without one they draw with the Enemies' own tables, visited already.
function Designs.EachDesign(db, plates, visit)
    local profiles = type(db) == "table" and db.plateProfiles
    if type(profiles) ~= "table" then return end
    for _, plateType in ipairs(S.profileOrder) do
        local world = profiles[plateType]
        if type(world) == "table" and (not plates or plates[plateType]) then
            visit(world, plateType, "world")
            local legacy = plateType == "enemy" and type(profiles.enemyDungeon) == "table" and profiles.enemyDungeon or nil
            for _, context in ipairs(Designs.CONTEXTS) do
                local record = RecordOf(world, plateType, context)
                if record then
                    visit(Designs.For(db, plateType, context), plateType, context, record)
                elseif legacy and context == "dungeon" then
                    visit(legacy, plateType, context)
                end
            end
        end
        local players = plateType == "enemy" and (not plates or plates.enemyPlayer) and PlayersOf(world)
        if players then
            visit(PlayersFor(db, "world"), "enemyPlayer", "world", players)
            for _, context in ipairs(Designs.CONTEXTS) do
                if RecordOf(world, plateType, context) then visit(PlayersFor(db, context), "enemyPlayer", context, players) end
            end
        end
    end
end

-- Editing (Settings): a copy of an effective profile to mutate. Its top level and its styles,
-- rules, auraLayouts and valueSlots maps are new (custom part records too); what they hold is
-- shared, so an edit replaces a part's style, rule list or aura row rather than changing it.
function Designs.WorkingCopy(effective)
    local copy = Copy(effective)
    for _, area in ipairs({ "styles", "rules", "auraLayouts" }) do
        if type(effective[area]) == "table" then copy[area] = Copy(effective[area]) end
    end
    if type(effective.valueSlots) == "table" then
        local slots = {}
        for key, slot in pairs(effective.valueSlots) do slots[key] = type(slot) == "table" and Copy(slot) or slot end
        copy.valueSlots = slots
    end
    return copy
end

local function IsOption(key)
    return type(key) == "string" and key ~= CLEAR and (OPTION_EXTRAS[key] or S.IsProfileOption(key))
end

-- What after sets differently from base, and "-" for what it clears; nil when they match.
local function FieldOverride(base, after)
    base, after = type(base) == "table" and base or {}, type(after) == "table" and after or {}
    local override, clear = {}, {}
    for key, value in pairs(after) do
        if not Table.DeepEqual(value, base[key]) then override[key] = Table.DeepCopy(value) end
    end
    for key in pairs(base) do if after[key] == nil then clear[key] = true end end
    override[CLEAR] = Packed(clear)
    return Packed(override)
end

local function Placement(entry)
    local placement = {}
    for _, field in ipairs(PLACEMENT) do placement[field] = entry[field] end
    return placement
end

-- entry (after the edit) against World's base, per sub-area; nil when they match. An order that
-- differs alone counts only with orderMatters (KeepTreeOrder decides which orders a design needs).
local function EntryOverride(key, base, entry, orderMatters)
    if type(entry) ~= "table" then
        return type(base) == "table" and S.IsGroupKey(key) and { deleted = true } or nil
    end
    if type(base) ~= "table" then
        local added = { added = true, placement = Placement(entry), removed = entry.removed == true or nil, name = entry.name }
        -- Hidden here is stored as false (absent: shown).
        if entry.visible == false then added.visible = false end
        return added
    end
    local override = {}
    for _, field in ipairs(PLACEMENT) do
        if entry[field] ~= base[field] and (orderMatters or field ~= "order") then
            override.placement = Placement(entry)
            break
        end
    end
    if (entry.visible ~= false) ~= (base.visible ~= false) then override.visible = entry.visible ~= false end
    if (entry.removed == true) ~= (base.removed == true) then override.removed = entry.removed == true end
    if entry.name ~= base.name then override.name = entry.name or false end
    return Packed(override)
end

local AREA_OVERRIDES = {
    styles = function(base, after) return FieldOverride(base, after) end,
    -- A list replaces World's whole; {} keeps World's off this part here.
    rules = function(base, after)
        local list = type(after) == "table" and after or {}
        if Table.DeepEqual(list, type(base) == "table" and base or {}) then return nil end
        return Table.DeepCopy(list)
    end,
    valueSlots = function(base, after)
        if Table.DeepEqual(after, base) or type(after) ~= "table" then return nil end
        return Table.DeepCopy(after)
    end,
    auraLayouts = function(base, after) return FieldOverride(base, after) end,
}

local function StoreOptions(world, record, before, after)
    local options, clear
    EachKey(before, after, function(key)
        local old, new = before[key], after[key]
        if not IsOption(key) or old == new or Table.DeepEqual(old, new) then return end
        if not options then
            options = Copy(record.options)
            clear = Copy(options[CLEAR])
        end
        options[key], clear[key] = nil, nil
        if not Table.DeepEqual(new, world[key]) then
            if new == nil then clear[key] = true else options[key] = Table.DeepCopy(new) end
        end
    end)
    if options then
        options[CLEAR] = Packed(clear)
        record.options = Packed(options)
    end
end

-- Tree order, as Schema's SortByTreeOrder and the normalised layouts give it: by order (a part's
-- unset order last, a group's 0), then by key.
local ROOT = ""
local function OrderOf(key, order) return order or (S.IsGroupKey(key) and 0 or 99) end
local function Before(orderA, keyA, orderB, keyB)
    if orderA ~= orderB then return orderA < orderB end
    return keyA < keyB
end

-- The editing routes renumber whole sibling lists (a new group, a part moved in, a reorder), and
-- an order alone is no override, so siblings the player never touched keep following World. Per
-- parent an edit touched, the merge must still give the sequence desired (the edited layout) has:
-- where World's orders do not, the entries this design places itself take fitting orders, and so
-- do the fewest World entries, those out of the longest run already in World's sequence.
local function KeepTreeOrder(base, entries, desired, parents)
    for parent in pairs(parents) do
        local list, merged, placed = {}, {}, {}
        for key, position in pairs(desired) do
            local own, world = entries[key], base[key]
            local placement = type(own) == "table" and own.placement
            if type(position) == "table" and (position.parent or ROOT) == parent then
                if placement then
                    list[#list + 1], merged[key], placed[key] = key, OrderOf(key, placement.order), true
                elseif type(world) == "table" and (world.parent or ROOT) == parent then
                    list[#list + 1], merged[key] = key, OrderOf(key, world.order)
                end
            end
        end
        table.sort(list, function(a, b)
            return Before(OrderOf(a, desired[a].order), a, OrderOf(b, desired[b].order), b)
        end)
        local fits = true
        for index = 2, #list do
            if not Before(merged[list[index - 1]], list[index - 1], merged[list[index]], list[index]) then
                fits = false
                break
            end
        end
        if not fits then
            -- The longest run of World's entries already in order keeps World's orders (a few
            -- dozen siblings at most).
            local length, from, best = {}, {}, nil
            for index, key in ipairs(list) do
                if not placed[key] then
                    length[index] = 1
                    for earlier = 1, index - 1 do
                        if length[earlier] and length[earlier] + 1 > length[index]
                            and Before(merged[list[earlier]], list[earlier], merged[key], key) then
                            length[index], from[index] = length[earlier] + 1, earlier
                        end
                    end
                    if not best or length[index] > length[best] then best = index end
                end
            end
            local kept = {}
            while best do
                kept[list[best]] = true
                best = from[best]
            end
            -- The others take the smallest order after the one before (a kept entry it would pass
            -- is no longer kept); past 99, every sibling is numbered in turn.
            local assigned, lastOrder, lastKey = {}, nil, nil
            for _, key in ipairs(list) do
                local order = merged[key]
                if kept[key] and lastKey and not Before(lastOrder, lastKey, order, key) then kept[key] = nil end
                if not kept[key] then
                    order = not lastKey and 0 or (key > lastKey and lastOrder or lastOrder + 1)
                    assigned[key] = order
                end
                lastOrder, lastKey = order, key
            end
            if lastOrder and lastOrder > 99 then
                for index, key in ipairs(list) do assigned[key] = index end
            end
            for key, order in pairs(assigned) do
                local own = entries[key]
                if placed[key] and own.placement.order ~= order then
                    own = Copy(own)
                    own.placement = Copy(own.placement)
                    own.placement.order = order
                    entries[key] = own
                elseif not placed[key] and order ~= merged[key] then
                    own = Copy(own)
                    own.placement = Placement(desired[key])
                    own.placement.order = order
                    entries[key] = own
                end
            end
        end
    end
end

-- exact: every placement difference counts, order included (a full design's differences).
local function StoreLayouts(world, record, before, after, exact)
    local layouts
    for _, field in ipairs(LAYOUT_FIELDS) do
        local old, new, base = before[field], after[field], world[field]
        if old ~= new and type(new) == "table" and type(base) == "table" then
            old = type(old) == "table" and old or {}
            layouts = layouts or Copy(record.layouts)
            local stored = type(layouts[field]) == "table" and layouts[field] or {}
            local entries, parents = Copy(stored), {}
            EachKey(old, new, function(key)
                if not Table.DeepEqual(old[key], new[key]) then
                    -- A placement stored before keeps its order with it.
                    local placed = type(stored[key]) == "table" and stored[key].placement ~= nil
                    entries[key] = EntryOverride(key, base[key], new[key], exact or placed)
                    if type(new[key]) == "table" then parents[new[key].parent or ROOT] = true end
                end
            end)
            if not exact then KeepTreeOrder(base, entries, new, parents) end
            layouts[field] = Packed(entries)
        end
    end
    if layouts then record.layouts = Packed(layouts) end
end

-- The design's overrides from an edit: for each area that changed between before (the effective
-- profile the edit started from) and after (its WorkingCopy, edited), an identity check first and
-- DeepEqual only where that differs, each touched override is dropped when it now matches World,
-- else a copy is stored. New override tables are written; none is changed in place. exact (a full
-- design's differences): an entry whose order alone differs keeps it as its placement.
function Designs.StoreDiff(world, record, before, after, exact)
    StoreOptions(world, record, before, after)
    StoreLayouts(world, record, before, after, exact)
    for area, diff in pairs(AREA_OVERRIDES) do
        local old = type(before[area]) == "table" and before[area] or {}
        local new = type(after[area]) == "table" and after[area] or {}
        local base = type(world[area]) == "table" and world[area] or {}
        if old ~= new then
            local map
            EachKey(old, new, function(key)
                if old[key] ~= new[key] and not Table.DeepEqual(old[key], new[key]) then
                    map = map or Copy(record[area])
                    map[key] = diff(base[key], new[key])
                end
            end)
            if map then record[area] = Packed(map) end
        end
    end
    return record
end

-- One layout entry's override made again from entry (what the design's effective entry is to be),
-- per sub-area against World's entry now; dropped when it matches. New tables, as StoreDiff writes.
-- The Show on plates shortcut uses it once World's own eye is set.
function Designs.StoreEntry(world, record, field, key, entry)
    local base = type(world[field]) == "table" and world[field] or {}
    local layouts = Copy(record.layouts)
    local entries = Copy(layouts[field])
    entries[key] = EntryOverride(key, base[key], entry, type(entries[key]) == "table" and entries[key].placement ~= nil)
    layouts[field] = Packed(entries)
    record.layouts = Packed(layouts)
end

-- The stored record of plateType's design for context (a sparse or full one), or nil: none, or
-- friendly plates' Dungeons & raids design (Blizzard's, never stored).
function Designs.Record(db, plateType, context)
    if plateType == "enemyPlayer" then plateType, context = "enemy", PLAYERS end
    local world = WorldOf(db, plateType)
    return world and context ~= nil and context ~= "world" and RecordOf(world, plateType, context) or nil
end

-- Stores record as world's sparse design for context (replacing any design there) and returns it.
function Designs.SetSparse(world, context, record)
    world.contexts = type(world.contexts) == "table" and world.contexts or {}
    world.contexts[context] = record
    return record
end

-- A new design's overrides: "world" (or nil) none, so it follows World; "light" (Cities & inns)
-- hides the aura rows (and on names-only plates the cast bar) and draws no cast bar on names here,
-- each only where World shows it.
local LIGHT_HIDDEN = { layout = { "buffs", "debuffs" }, namesLayout = { "buffs", "debuffs", "cast" } }
function Designs.Starter(world, starter)
    local record = {}
    if starter ~= "light" then return record end
    local work = Designs.WorkingCopy(world)
    work.castOnNames = false
    for field, parts in pairs(LIGHT_HIDDEN) do
        if type(world[field]) == "table" then
            local layout = Copy(world[field])
            for _, part in ipairs(parts) do
                if type(layout[part]) == "table" then
                    layout[part] = Copy(layout[part])
                    layout[part].visible = false
                end
            end
            work[field] = layout
        end
    end
    return Designs.StoreDiff(world, record, world, work)
end

-- What plateType's designs use, so a new group or custom part made in one never takes a key
-- another has: entries (every key of field's layout in each design, World's included, and every
-- key a sparse design holds an override for there, tombstones and orphans too) and slots (custom
-- parts with a source in any design, or that a sparse design overrides).
function Designs.InUse(db, plateType, field)
    local entries, slots = {}, {}
    -- Enemies and enemy players share theirs: the players layer sits on the Enemies' designs.
    local plates = (plateType == "enemy" or plateType == "enemyPlayer") and { enemy = true, enemyPlayer = true }
        or { [plateType] = true }
    Designs.EachDesign(db, plates, function(profile, _, _, record)
        for key in pairs(type(profile[field]) == "table" and profile[field] or {}) do entries[key] = true end
        for key, slot in pairs(type(profile.valueSlots) == "table" and profile.valueSlots or {}) do
            if type(slot) == "table" and slot.source ~= "off" then slots[key] = true end
        end
        if record and record.full ~= true then
            for _, map in pairs(type(record.layouts) == "table" and record.layouts or {}) do
                for key in pairs(map) do
                    slots[key] = true
                    if map == record.layouts[field] then entries[key] = true end
                end
            end
            for key in pairs(type(record.valueSlots) == "table" and record.valueSlots or {}) do slots[key] = true end
        end
    end)
    return entries, slots
end

-- The first custom-part slot no design of plateType uses (Designs.InUse), or nil when all are.
function Designs.FreeValueSlot(db, plateType)
    local _, slots = Designs.InUse(db, plateType, "layout")
    for index = 1, S.VALUE_SLOT_COUNT do
        if not slots["value" .. index] then return "value" .. index end
    end
    return nil
end

-- A sparse design holding what a full design differs from World in.
local function Diff(world, design)
    return Designs.StoreDiff(world, {}, world, design, true)
end

-- A new sparse design from another (sparse: its overrides; full: what it differs from World in),
-- for "Start from another design".
function Designs.CopyFrom(world, source)
    if type(source) ~= "table" then return nil end
    if source.full == true then return type(source.design) == "table" and Diff(world, source.design) or nil end
    return Table.DeepCopy(source)
end

-- "Slim down to differences": a full design becomes the sparse one with the same effective profile.
-- Only the player triggers it. false when record is not a full design.
function Designs.Slim(world, record)
    if type(record) ~= "table" or record.full ~= true or type(record.design) ~= "table" then return false end
    local sparse = Diff(world, record.design)
    Table.Replace(record, sparse)
    return true
end

-- Every override gone: the design follows World entirely (a full one becomes an empty sparse one).
function Designs.ResetAll(record)
    if type(record) ~= "table" then return false end
    for key in pairs(record) do record[key] = nil end
    return true
end

-- Before key takes World's parent (newParent) in layout (a copy the caller may change): when that
-- parent sits under key there, the entry on the way directly under key moves up to key's own
-- parent, drawn where it is (as a deleted group's children do), so the reset makes no cycle.
-- Returns that entry's key, or nil.
local function BreakCycle(layout, key, newParent)
    local child, current, depth = nil, newParent, 0
    while current and current ~= key and depth <= S.MAX_DEPTH do
        child, depth = current, depth + 1
        current = type(layout[current]) == "table" and layout[current].parent or nil
    end
    if current ~= key or not child or type(layout[key]) ~= "table" then return nil end
    local transforms = S.LayoutTransforms(layout)
    local drawn, parentKey = transforms[child], layout[key].parent
    local parent = parentKey and transforms[parentKey] or { x = 0, y = 0, scale = 1 }
    local entry = Copy(layout[child])
    entry.parent, entry.attach = parentKey, nil
    if drawn and parent.scale ~= 0 then
        entry.x, entry.y = (drawn.x - parent.x) / parent.scale, (drawn.y - parent.y) / parent.scale
        entry.scale = drawn.scale / parent.scale
    end
    layout[child] = S.NormalizeLayoutEntry(child, entry) or entry
    return child
end

-- A full design's area back to World's value (written as new tables; the design stays full).
local function ResetFull(world, design, area)
    local kind, key, sub = area.kind, area.key, area.sub
    if kind == "option" then
        if not IsOption(key) then return false end
        design[key] = Table.DeepCopy(world[key])
    elseif kind == "entry" then
        local field = area.field or "layout"
        local base, layout = type(world[field]) == "table" and world[field] or {}, design[field]
        if type(layout) ~= "table" then return false end
        layout = Table.DeepCopy(layout)
        local entry = base[key] and Table.DeepCopy(base[key]) or nil
        if entry and (not sub or sub == "placement") then BreakCycle(layout, key, entry.parent) end
        if sub and layout[key] and entry then
            local own = layout[key]
            if sub == "placement" then
                for _, name in ipairs(PLACEMENT) do own[name] = entry[name] end
            elseif SUB_AREAS[sub] then
                own[SUB_AREAS[sub]] = entry[SUB_AREAS[sub]]
            else
                return false
            end
        else
            layout[key] = entry
        end
        -- As an edit of a full design normalises it (Settings' LayoutFallback): a World parent group
        -- it lacks comes from World, and no parent is left dangling.
        design[field] = S.NormalizeLayout(layout, base)
    elseif kind == "style" or kind == "aura" then
        local mapKey = kind == "style" and "styles" or "auraLayouts"
        local base = type(world[mapKey]) == "table" and world[mapKey][key] or nil
        local map = Copy(design[mapKey])
        if sub then
            local own = Copy(map[key])
            own[sub] = Table.DeepCopy(base and base[sub])
            map[key] = Packed(own)
        else
            map[key] = Table.DeepCopy(base)
        end
        design[mapKey] = map
    elseif kind == "rules" or kind == "slot" then
        local mapKey = kind == "rules" and "rules" or "valueSlots"
        local map = Copy(design[mapKey])
        map[key] = Table.DeepCopy(type(world[mapKey]) == "table" and world[mapKey][key] or nil)
        design[mapKey] = map
    else
        return false
    end
    return true
end

-- One override map without key (sub: one of its fields, and from its "-" list), as new tables.
local function WithoutField(map, key, sub)
    local own = map and map[key]
    if type(own) ~= "table" then return nil end
    if sub then
        if own[sub] == nil and not (type(own[CLEAR]) == "table" and own[CLEAR][sub]) then return nil end
        own = Copy(own)
        own[sub] = nil
        local clear = Copy(own[CLEAR])
        clear[sub] = nil
        own[CLEAR] = Packed(clear)
        own = Packed(own)
    else
        own = nil
    end
    local copy = Copy(map)
    copy[key] = own
    return copy
end

-- One area back to World. area = { kind = "option" | "entry" | "style" | "rules" | "slot" | "aura",
-- key, sub, field }: entry sub is placement, eye, presence or label (field: layout, the default, or
-- namesLayout); style sub is a style field; aura key is buffs or debuffs, sub a row field. A sparse
-- design drops that override; a full one takes World's value and stays full. false when nothing
-- was there to reset. An entry's placement goes back to World's without making a parent cycle
-- (BreakCycle). plateType (default: the Enemies) names the defaults a sparse design merges against.
function Designs.Reset(world, record, area, plateType)
    if type(record) ~= "table" or type(area) ~= "table" or type(world) ~= "table" then return false end
    if record.full == true then return type(record.design) == "table" and ResetFull(world, record.design, area) end
    local kind, key, sub = area.kind, area.key, area.sub
    if kind == "option" then
        local options = record.options
        if not options or (options[key] == nil and not (type(options[CLEAR]) == "table" and options[CLEAR][key])) then
            return false
        end
        options = Copy(options)
        options[key] = nil
        local clear = Copy(options[CLEAR])
        clear[key] = nil
        options[CLEAR] = Packed(clear)
        record.options = Packed(options)
    elseif kind == "entry" then
        local field = area.field or "layout"
        local entries = type(record.layouts) == "table" and record.layouts[field]
        local own = type(entries) == "table" and entries[key]
        if type(own) ~= "table" then return false end
        local stored = entries
        local base = type(world[field]) == "table" and world[field] or nil
        local placement = own.placement ~= nil and base and type(base[key]) == "table"
        if sub then
            local name = SUB_AREAS[sub]
            -- An entry only this design has keeps its placement: World has none to go back to.
            if not name or own[name] == nil or (own.added and name == "placement") then return false end
            placement = placement and name == "placement"
            own = Copy(own)
            own[name] = nil
            own = Packed(own)
        else
            own = nil
        end
        entries = Copy(entries)
        if placement then
            local fallback = (S.profileDefaults[plateType] or S.profileDefaults.enemy)[field]
            local layout = Copy(Designs.MergeLayout(base, stored, fallback))
            local child = BreakCycle(layout, key, base[key].parent)
            if child then entries[child] = EntryOverride(child, base[child], layout[child], true) end
        end
        entries[key] = own
        local layouts = Copy(record.layouts)
        layouts[field] = Packed(entries)
        record.layouts = Packed(layouts)
    elseif kind == "style" or kind == "aura" then
        local mapKey = kind == "style" and "styles" or "auraLayouts"
        local map = WithoutField(record[mapKey], key, sub)
        if not map then return false end
        record[mapKey] = Packed(map)
    elseif kind == "rules" or kind == "slot" then
        local mapKey = kind == "rules" and "rules" or "valueSlots"
        local map = record[mapKey]
        if type(map) ~= "table" or map[key] == nil then return false end
        map = Copy(map)
        map[key] = nil
        record[mapKey] = Packed(map)
    else
        return false
    end
    return true
end

-- Which areas a design changes, from its overrides (a full design's: what differs from World):
-- { options = { key }, entries = { layout | namesLayout = { key = { placement, eye, presence, label,
-- added, deleted } } }, styles = { part = { field } }, rules = { part }, slots = { key },
-- auras = { kind = { field } }, parts = { key } (any area of that part or entry), any = true | nil }.
-- Built once per revision; World and a design that does not exist change nothing. Read-only.
local changedCache = {}
local function Changed(world, record)
    local overrides = record.full == true and Diff(world, record.design) or record
    local result = { options = {}, entries = {}, styles = {}, rules = {}, slots = {}, auras = {}, parts = {} }
    for key in pairs(type(overrides.options) == "table" and overrides.options or {}) do
        if key ~= CLEAR then result.options[key] = true end
    end
    for key in pairs(type(overrides.options) == "table" and type(overrides.options[CLEAR]) == "table"
        and overrides.options[CLEAR] or {}) do result.options[key] = true end
    for field, entries in pairs(type(overrides.layouts) == "table" and overrides.layouts or {}) do
        local marks = {}
        for key, own in pairs(entries) do
            marks[key] = { placement = own.placement ~= nil or nil, eye = own.visible ~= nil or nil,
                presence = own.removed ~= nil or nil, label = own.name ~= nil or nil, added = own.added or nil,
                deleted = own.deleted or nil }
            result.parts[key] = true
        end
        result.entries[field] = marks
    end
    for _, pair in ipairs({ { "styles", "styles" }, { "auraLayouts", "auras" } }) do
        for key, own in pairs(type(overrides[pair[1]]) == "table" and overrides[pair[1]] or {}) do
            local fields = {}
            for field in pairs(own) do if field ~= CLEAR then fields[field] = true end end
            for field in pairs(type(own[CLEAR]) == "table" and own[CLEAR] or {}) do fields[field] = true end
            result[pair[2]][key] = fields
            if pair[1] == "styles" then result.parts[key] = true end
        end
    end
    for key in pairs(type(overrides.rules) == "table" and overrides.rules or {}) do result.rules[key], result.parts[key] = true, true end
    for key in pairs(type(overrides.valueSlots) == "table" and overrides.valueSlots or {}) do
        result.slots[key], result.parts[key] = true, true
    end
    result.any = (next(result.options) or next(result.parts) or next(result.auras)) and true or nil
    return result
end

function Designs.ChangedAreas(db, plateType, context)
    if plateType == "enemyPlayer" then plateType, context = "enemy", PLAYERS end
    local world = WorldOf(db, plateType)
    local record = world and context ~= nil and context ~= "world" and RecordOf(world, plateType, context)
    if not record then return Changed({}, {}) end
    local byType = changedCache[plateType] or {}
    changedCache[plateType] = byType
    local entry = byType[context]
    if entry and entry.rev == Designs.revision and entry.world == world and entry.ctx == record then return entry.areas end
    entry = { rev = Designs.revision, world = world, ctx = record, areas = Changed(world, record) }
    byType[context] = entry
    return entry.areas
end

local function Count(map)
    local count = 0
    for key in pairs(type(map) == "table" and map or {}) do if key ~= CLEAR then count = count + 1 end end
    return count
end

-- Diagnostics (/ps diagnose's designs section): the resolver's counters, each plate type's designs,
-- how many overrides each holds, and its orphans (entries for parts World no longer has; normal).
function Designs.Report(db)
    local report = { revision = Designs.revision, merges = stats.merges, cacheHits = stats.hits,
        layoutMemoHits = stats.layoutMemoHits, designs = {}, overrides = {}, orphans = {} }
    for _, plateType in ipairs(S.profileOrder) do
        local world = WorldOf(db, plateType)
        local words = {}
        for _, design in ipairs(Designs.List(db, plateType)) do
            local word = design.context
            if design.blizzard then word = word .. " (blizzard)" elseif design.full then word = word .. " (full)" end
            words[#words + 1] = word
            local record = world and not design.blizzard and design.context ~= "world" and RecordOf(world, plateType, design.context)
            if record then
                local key = plateType .. "@" .. design.context
                local areas = Designs.ChangedAreas(db, plateType, design.context)
                local entries, orphans = 0, 0
                for field, marks in pairs(areas.entries) do
                    for entryKey in pairs(marks) do
                        entries = entries + 1
                        local base = type(world[field]) == "table" and world[field][entryKey]
                        if not record.full and base == nil and not marks[entryKey].added then orphans = orphans + 1 end
                    end
                end
                report.overrides[key] = { options = Count(areas.options), entries = entries, styles = Count(areas.styles),
                    rules = Count(areas.rules), slots = Count(areas.slots), auras = Count(areas.auras) }
                report.orphans[key] = orphans
            end
        end
        report.designs[plateType] = table.concat(words, ", ")
    end
    -- Enemy players: the Enemies' designs, with a layer of their own or without.
    local players = PlayersOf(WorldOf(db, "enemy"))
    report.designs.enemyPlayer = players and "enemies, own changes" or "enemies"
    if players then
        local areas = Designs.ChangedAreas(db, "enemy", PLAYERS)
        local entries = 0
        for _, marks in pairs(areas.entries) do for _ in pairs(marks) do entries = entries + 1 end end
        report.overrides.enemyPlayer = { options = Count(areas.options), entries = entries, styles = Count(areas.styles),
            rules = Count(areas.rules), slots = Count(areas.slots), auras = Count(areas.auras) }
    end
    return report
end
