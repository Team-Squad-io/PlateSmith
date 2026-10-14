-- The Action icon on Objects and Friendly NPCs plates: the game's own cursor icon for what you can do with the unit
-- (gather a herb, mine, read a book, talk, train), drawn by SetUnitCursorTexture on PlateSmith's own texture, and what
-- rules and custom text read from it: object.kind and object.unable come from the icon's name ("Cursor
-- Crosshair_UnableGatherHerbs_64", a path or a file ID), never from object names or IDs; interact.inrange is
-- UnitIsInInteractRange's readable answer. Read when a plate is laid out, when the interaction target changes and,
-- while such plates are up, a few at a time by a slow ticker entry (a corpse turning from loot to skin); kept per
-- plate, so only a change marks its rules and text.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local IsReadable = Secret.IsReadable

local ActionIcon = {}
PS.ActionIcon = ActionIcon
ActionIcon.TICKER = "plates.actionIcon"
ActionIcon.INTERVAL, ActionIcon.BUDGET = 0.5, 6
ActionIcon.EVENT = "PLAYER_SOFT_INTERACT_CHANGED"
-- The softinteract unit: the client's interaction target, asked when a plate's own unit gets no icon.
ActionIcon.SOFT = "softinteract"
local GREY = 0.65

-- The client's cursor names (Interface\Cursor\<name>; Unable<name> is the same kind, marked unable) -> object.kind.
-- A name not here is "other".
ActionIcon.KINDS = {
    GatherHerbs = "herb", Mine = "ore", Skin = "skin", LootAll = "loot", PickLock = "loot",
    Quest = "quest", QuestRepeatable = "quest", QuestTurnIn = "quest", Inspect = "inspect",
    Interact = "interact", Pickup = "interact", Cast = "interact", Driver = "interact", Gunner = "interact",
    Speak = "talk", Directions = "talk", Innkeeper = "talk", Trainer = "trainer", Buy = "vendor",
    Taxi = "flight", Repair = "repair", Mail = "mail",
}
-- Studio's sample icon for each kind (Test values' Object), by its cursor name.
ActionIcon.SAMPLES = { herb = "GatherHerbs", ore = "Mine", skin = "Skin", loot = "LootAll", quest = "Quest",
    inspect = "Inspect", interact = "Interact", talk = "Speak", trainer = "Trainer", vendor = "Buy", flight = "Taxi",
    repair = "Repair", mail = "Mail", other = "Point" }
-- Test values' Object choices: the kind and its sample icon.
ActionIcon.SAMPLE_CHOICES = { "herb", "ore", "inspect", "loot", "quest", "talk", "trainer" }
-- object.kind -> the Objects' type (Designs.TYPES: Studio's Objects › Type) whose layer an object draws with. A kind
-- not here (an object with no icon: unknown) draws with All objects.
ActionIcon.TYPE_OF = { herb = "herb", ore = "ore", loot = "loot", skin = "loot", quest = "quest", inspect = "book",
    talk = "service", trainer = "service", vendor = "service", flight = "service", repair = "service", mail = "service",
    interact = "other", other = "other" }
-- A type's sample kind (Studio: choosing a Type shows that kind's icon and status in the preview).
ActionIcon.TYPE_SAMPLES = { herb = "herb", ore = "ore", loot = "loot", quest = "quest", book = "inspect",
    service = "talk", other = "interact" }

local byLowerName = {}
for name, kind in pairs(ActionIcon.KINDS) do byLowerName[name:lower()] = kind end

-- Results by the texture's name, and by file ID (made the first time the client hands one: GetFileIDFromPath of
-- every known name). Names are few (the client's cursor set), so the cache is bounded and starts over when full.
local NAME_CACHE_LIMIT = 64
local kindByName, unableByName, cursorByName, cached = {}, {}, {}, 0
local kindByFile, unableByFile, cursorByFile

-- The kind, whether it is an Unable icon, and the cursor's name in lower case without Unable ("gatherherbs").
local function ClassifyName(name)
    local base = name:match("Crosshair_(%a+)") or name:gsub("%.%w+$", ""):match("(%a+)$")
    if not base then return "other", false, nil end
    local lower = base:lower()
    local unable = lower:sub(1, 6) == "unable" and #lower > 6
    if unable then lower = lower:sub(7) end
    return byLowerName[lower] or "other", unable, lower
end

local function FileMap()
    if kindByFile then return end
    kindByFile, unableByFile, cursorByFile = {}, {}, {}
    local lookup = type(GetFileIDFromPath) == "function" and GetFileIDFromPath or nil
    if not lookup then return end
    for name, kind in pairs(ActionIcon.KINDS) do
        for _, unable in ipairs({ false, true }) do
            local ok, id = pcall(lookup, "Interface\\Cursor\\" .. (unable and "Unable" or "") .. name)
            if ok and IsReadable(id) and type(id) == "number" then
                kindByFile[id], unableByFile[id], cursorByFile[id] = kind, unable, name:lower()
            end
        end
    end
end

-- The kind and whether it is an Unable icon, for what GetTexture gave (a readable name or file ID), and the cursor's
-- name (lower case, without Unable; nil for a file ID no known name has); nil, nil when nothing readable names it.
function ActionIcon.Classify(value)
    if not IsReadable(value) then return nil, nil end
    if type(value) == "string" and value ~= "" then
        local kind = kindByName[value]
        if not kind then
            if cached >= NAME_CACHE_LIMIT then
                kindByName, unableByName, cursorByName, cached = {}, {}, {}, 0
            end
            local unable, cursor
            kind, unable, cursor = ClassifyName(value)
            kindByName[value], unableByName[value], cursorByName[value], cached = kind, unable, cursor, cached + 1
        end
        return kind, unableByName[value], cursorByName[value]
    end
    if type(value) == "number" then
        FileMap()
        local kind = kindByFile[value]
        if kind then return kind, unableByFile[value], cursorByFile[value] end
        return "other", false, nil
    end
    return nil, nil
end

-- Draws unit's cursor icon on texture. Returns whether the client drew one, and its texture (a name or file ID, as
-- GetTexture gives it; nil when unreadable). Missing API, an error or a false answer: nothing drawn.
local function Draw(texture, unit)
    local set = SetUnitCursorTexture
    if type(set) ~= "function" or not texture then return false, nil end
    local ok, answer = pcall(set, texture, unit)
    if not ok or (IsReadable(answer) and answer == false) then return false, nil end
    local getter = texture.GetTexture
    local value
    if type(getter) == "function" then
        local okTexture, read = pcall(getter, texture)
        if okTexture and IsReadable(read) then value = read end
    end
    -- An unknown answer with nothing set is no icon.
    if not (IsReadable(answer) and answer == true) and value == nil then return false, nil end
    return true, value
end
ActionIcon.Draw = Draw

-- The icon for unit, else the interaction target's when unit is that target (the client may draw it only for that).
function ActionIcon.Read(texture, unit)
    local drawn, value = Draw(texture, unit)
    if not drawn and Secret.SameUnit(unit, ActionIcon.SOFT) then drawn, value = Draw(texture, ActionIcon.SOFT) end
    return drawn, value
end

-- UnitIsInInteractRange's answer: a readable boolean, else nil (unknown).
function ActionIcon.InRange(unit)
    if type(UnitIsInInteractRange) ~= "function" then return nil end
    local ok, value = pcall(UnitIsInInteractRange, unit)
    if ok and IsReadable(value) and type(value) == "boolean" then return value end
    return nil
end

-- The look for the icon's state and the part's Can't use choice (style iconUnable: nil as the game gives it, grey,
-- hide): whether it shows, and whether it is greyed. Plates and Studio's preview share it.
function ActionIcon.Look(unable, choice)
    if unable == true and choice == "hide" then return false, false end
    return true, unable == true and choice == "grey"
end

function ActionIcon.Grey(texture, grey)
    if type(texture.SetDesaturated) == "function" then pcall(texture.SetDesaturated, texture, grey) end
    local shade = grey and GREY or 1
    texture:SetVertexColor(shade, shade, shade)
end

-- The icon's size, square: the raid mark's (from the plate type's name size), before the part's Scale.
function ActionIcon.Size(nameFontSize)
    return math.max(16, (tonumber(nameFontSize) or 14) + 6)
end

-- The kind of unit's icon read on a texture of the module's own (never shown), for a plate about to be laid out:
-- its kind, or nil when the client draws none or names none readably.
local scratch
local function Peek(unit)
    if not scratch then
        if type(CreateFrame) ~= "function" then return nil end
        local frame = CreateFrame("Frame")
        frame:Hide()
        scratch = frame:CreateTexture(nil, "OVERLAY")
    end
    local drawn, value = ActionIcon.Read(scratch, unit)
    if not drawn then return nil end
    return ActionIcon.Classify(value)
end

function ActionIcon.PeekKind(unit)
    return (Peek(unit))
end

-- What unit's icon says now (ObjectHover's cursor and tooltip): the cursor's name (lower case, without Unable),
-- whether it is the Unable one, and the kind; nil when the client draws none or names none readably.
function ActionIcon.PeekCursor(unit)
    local kind, unable, cursor = Peek(unit)
    if not kind then return nil end
    return cursor, unable == true, kind
end

-- The plate side. context: active (unit -> plate), RunBatch, MarkStacks, MarkValues, Styles, AnchorPart (Placement),
-- ObjectChanged(data, typeChanged) (an object's type or Can't use changed: Lifecycle lays it out again or fades it).
-- A plate's icon is made the first time it is wanted; the event and the ticker entry run only while a layout of an
-- Objects or Friendly NPCs design shows the part or reads its facts, or every object's kind is wanted (SetWanted's
-- objects: an object type's layer, the fade, the Status text), the entry only while such a plate is up.
PS._CreatePlateActionIcon = function(context)
    local active, RunBatch, MarkStacks, MarkValues = context.active, context.RunBatch, context.MarkStacks, context.MarkValues
    local Styles, AnchorPart, ObjectChanged = context.Styles, context.AnchorPart, context.ObjectChanged
    -- soft: the plate the interaction target was on at the last PLAYER_SOFT_INTERACT_CHANGED.
    local Pass = { wanted = false, objects = false, ticking = false, cursor = 0, listening = false, laying = false,
        soft = nil }
    -- Plates whose icon or facts are read, in a round-robin list (each keeps its index as actionIconIndex).
    local rows = {}
    Pass.rows = rows

    local function ListSet(data, wanted)
        local index = data.actionIconIndex
        if wanted then
            if not index then
                rows[#rows + 1] = data
                data.actionIconIndex = #rows
            end
        elseif index then
            local last = rows[#rows]
            rows[index], last.actionIconIndex = last, index
            rows[#rows] = nil
            data.actionIconIndex = nil
        end
    end

    local function PartShown(data)
        local position = data.layout and data.layout.actionIcon
        return position ~= nil and not S.TurnedOff(position)
    end

    local function ReadsFacts(data)
        local reads = data.reads
        return reads ~= nil and (reads.rules.object == true or reads.values.object == true)
    end

    local function Wanted(data)
        return Pass.wanted and data.unit ~= nil and data.own == true
            and (data.object == true or data.profileKey == "friendlyNPC")
            and (PartShown(data) or ReadsFacts(data) or (data.object == true and Pass.objects))
    end

    -- The Objects type for a plate about to be laid out (Lifecycle's ApplyLayout), while types are read: from the kind
    -- this plate already read for its unit, else a read of its own. nil: All objects.
    function Pass.TypeFor(data)
        if not (Pass.wanted and Pass.objects and data.unit) then return nil end
        local kind = data.objectKind
        if kind == nil then kind = ActionIcon.PeekKind(data.unit) end
        return kind and ActionIcon.TYPE_OF[kind] or nil
    end

    local function Choice(data)
        local styles = data.profile and data.profile.styles
        return styles and styles.actionIcon and styles.actionIcon.iconUnable or nil
    end

    local function ApplySize(data)
        local size = ActionIcon.Size(data.profile and data.profile.nameFontSize)
        data.actionIcon:SetSize(size, size)
    end

    local function Ensure(data)
        if data.actionIcon then return data.actionIcon end
        local layer = CreateFrame("Frame", nil, data.overlay)
        layer:SetAllPoints(data.overlay)
        data.layerFrames.actionIcon = layer
        local icon = layer:CreateTexture(nil, "OVERLAY")
        icon:Hide()
        data.actionIcon, data.actionIconGrey = icon, nil
        ApplySize(data)
        if data.layout and data.layout.actionIcon then AnchorPart(data, icon, "actionIcon") end
        layer:SetFrameLevel(Styles.LayerLevel(data, "actionIcon"))
        data.stackStatesFor = nil
        MarkStacks(data)
        return icon
    end

    -- Forgets the plate's facts; whatever reads them follows (a layout marks everything anyway).
    local function ClearFacts(data, mark)
        if data.objectKind ~= nil or data.objectUnable ~= nil or data.interactInRange ~= nil then
            data.objectKind, data.objectUnable, data.interactInRange = nil, nil, nil
            if mark then MarkValues(data, "object") end
        end
    end

    local function SetShown(data, shown)
        local icon = data.actionIcon
        if icon and (icon:IsShown() and true or false) ~= shown then
            icon:SetShown(shown)
            MarkStacks(data)
        end
    end

    -- One read of the plate's icon and range; only a change marks its rules and text, or its stacks.
    local function Refresh(data)
        local icon = data.actionIcon
        if not icon or not data.unit then return end
        local drawn, value = ActionIcon.Read(icon, data.unit)
        local kind, unable
        if drawn then kind, unable = ActionIcon.Classify(value) end
        local inRange = ActionIcon.InRange(data.unit)
        if data.objectKind ~= kind or data.objectUnable ~= unable or data.interactInRange ~= inRange then
            local unableChanged = data.objectUnable ~= unable
            data.objectKind, data.objectUnable, data.interactInRange = kind, unable, inRange
            MarkValues(data, "object")
            -- An object whose type changed (a chest emptied) draws with that type's design: laid out again, which
            -- reads it once more (not while it is being laid out: its type was read just before).
            if data.object and ObjectChanged then
                local typeChanged = Pass.objects and (kind and ActionIcon.TYPE_OF[kind] or nil) ~= data.objectType
                if typeChanged and not Pass.laying then
                    ObjectChanged(data, true)
                    return
                elseif unableChanged then
                    ObjectChanged(data, false)
                end
            end
        end
        local shown, grey = false, false
        if drawn and PartShown(data) then shown, grey = ActionIcon.Look(unable, Choice(data)) end
        if shown and data.actionIconGrey ~= grey then
            data.actionIconGrey = grey
            ActionIcon.Grey(icon, grey)
        end
        SetShown(data, shown)
    end
    Pass.Refresh = Refresh

    local events = CreateFrame("Frame")
    Pass.events = events
    -- A client that does not know the event is not asked to register it (the ticker entry still reads the plates).
    -- Asked once.
    local eventValid
    local function EventValid()
        if eventValid == nil then
            eventValid = true
            local utils = C_EventUtils
            if type(utils) == "table" and type(utils.IsEventValid) == "function" then
                local ok, valid = pcall(utils.IsEventValid, ActionIcon.EVENT)
                if ok and IsReadable(valid) then eventValid = valid == true end
            end
        end
        return eventValid
    end
    local function Sync()
        local listening = Pass.wanted and EventValid()
        if listening ~= Pass.listening then
            Pass.listening = listening
            if listening then
                PS._RegisterEvent(events, ActionIcon.EVENT, "platesmith.action-icon")
            elseif type(events.UnregisterEvent) == "function" then
                pcall(events.UnregisterEvent, events, ActionIcon.EVENT)
            end
        end
        -- Asleep while no such plate is up; enabling again would restart the entry's wait, so only a change is written.
        local ticking = Pass.wanted and #rows > 0
        if ticking ~= Pass.ticking then
            Pass.ticking = ticking
            PS.Ticker.SetEnabled(ActionIcon.TICKER, ticking)
        end
    end

    -- A plate was laid out: its icon made, placed and read, or hidden and its facts forgotten.
    function Pass.Update(data)
        local wanted = Wanted(data)
        if wanted then
            Ensure(data)
            Pass.laying = true
            Refresh(data)
            Pass.laying = false
        else
            SetShown(data, false)
            ClearFacts(data, false)
        end
        ListSet(data, wanted)
        Sync()
    end

    -- Sized and greyed again after a settings change (ApplyAppearance).
    function Pass.ApplyAppearance(data)
        if not data.actionIcon then return end
        ApplySize(data)
        if data.actionIconGrey ~= nil then ActionIcon.Grey(data.actionIcon, data.actionIconGrey) end
    end

    function Pass.Release(data)
        if data.actionIcon then data.actionIcon:Hide() end
        data.objectKind, data.objectUnable, data.interactInRange = nil, nil, nil
        if Pass.soft == data then Pass.soft = nil end
        ListSet(data, false)
        Sync()
    end

    -- Whether data is a listed plate on its unit now.
    local function Listed(data)
        return data ~= nil and data.actionIconIndex ~= nil and rows[data.actionIconIndex] == data and data.unit ~= nil
            and active[data.unit] == data
    end

    -- Every listed plate. Last first: a refresh can lay its plate out again (ObjectChanged), which may take it off the
    -- list at once, moving the last row (already read) into its place.
    local function RefreshRows()
        for index = #rows, 1, -1 do
            local data = rows[index]
            if data and data.unit and active[data.unit] == data then Refresh(data) end
        end
    end

    -- The backstop: a few plates a pass, in turn, so a state the client changes without an event (a looted corpse,
    -- a chest opened by someone else, walking into reach) shows within a few passes.
    function Pass.Tick()
        local count = #rows
        if count == 0 then return Sync() end
        for _ = 1, math.min(ActionIcon.BUDGET, count) do
            -- A refresh can take plates off the list (ObjectChanged).
            if #rows == 0 then break end
            Pass.cursor = Pass.cursor % #rows + 1
            local data = rows[Pass.cursor]
            if data.unit and active[data.unit] == data then Refresh(data) end
        end
    end
    PS.Ticker.Register(ActionIcon.TICKER, ActionIcon.INTERVAL, function() RunBatch(false, Pass.Tick) end)
    PS.Ticker.SetEnabled(ActionIcon.TICKER, false)

    -- The plate of the interaction target now (its nameplate's), or nil; false when the client cannot say.
    local function SoftPlate()
        local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        if type(get) ~= "function" then return false end
        local ok, root = pcall(get, ActionIcon.SOFT)
        if not ok or not IsReadable(root) then return false end
        if type(root) ~= "table" then return nil end
        if type(root.IsForbidden) == "function" then
            local okForbidden, forbidden = pcall(root.IsForbidden, root)
            if not okForbidden or not IsReadable(forbidden) or forbidden == true then return nil end
        end
        return root.PlateSmithData
    end

    -- The interaction target changed: the icons of the plate it left and the one it is on may have (the backstop reads
    -- the rest). A client that cannot name the target's plate reads every plate.
    local function RefreshSoft()
        local now = SoftPlate()
        if now == false then
            Pass.soft = nil
            return RefreshRows()
        end
        local before = Pass.soft
        Pass.soft = Listed(now) and now or nil
        if before ~= Pass.soft and Listed(before) then Refresh(before) end
        if Listed(Pass.soft) then Refresh(Pass.soft) end
    end
    events:SetScript("OnEvent", function()
        if Pass.wanted and #rows > 0 then RunBatch(false, RefreshSoft) end
    end)

    -- On while a layout shows the part or reads its facts, or (objects) every object's kind is wanted. Off: no event,
    -- no ticker, every icon hidden.
    function Pass.SetWanted(wanted, objects)
        wanted = wanted and true or false
        Pass.objects = wanted and objects == true
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        if not wanted then
            for index = #rows, 1, -1 do
                local data = rows[index]
                SetShown(data, false)
                ClearFacts(data, true)
                ListSet(data, false)
            end
        end
        Sync()
    end

    ActionIcon._pass = Pass
    return Pass
end

-- For /ps diagnose (context.actionIcon): whether the pass runs (and for every object), the plates it reads, and for
-- each (up to six) what the client gave: drawn or not, the kind, unable, in range and the type it draws with. Never
-- reads a protected value.
function ActionIcon.Report()
    local Array = PS.Json and PS.Json.Array or function() return {} end
    local pass = ActionIcon._pass
    local report = { wanted = pass ~= nil and pass.wanted or false, plates = pass and #pass.rows or 0,
        objects = pass ~= nil and pass.objects or false,
        -- A client without the icon API is not a problem (no icon shows): unavailable, not api-missing.
        api = type(SetUnitCursorTexture) == "function" and "readable" or "unavailable", read = Array() }
    for index = 1, math.min(6, pass and #pass.rows or 0) do
        local data = pass.rows[index]
        report.read[#report.read + 1] = { kind = data.objectKind or "unknown", unable = data.objectUnable,
            inRange = data.interactInRange, shown = data.actionIcon ~= nil and data.actionIcon:IsShown() == true,
            object = data.object == true, type = data.objectType or (data.object and "all" or nil) }
    end
    return report
end
