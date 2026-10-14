-- Blizzard's plate stacking: the stacking, distance, scale and fade CVars a profile sets (each one on
-- its own; the rest stay the game's), the plate size its stacking spaces plates by, and the target
-- and focus overlays drawn over the rest.
-- docs/STACKING.md describes the rules; the Studio page calls the API at the end of this file.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local NamePolicy = assert(PS.NamePolicy, "PlateSmith NamePolicy missing")
local L = PS.L

local Stacking = {}
PS.Stacking = Stacking

-- The cvarRestore key the originals are captured under (NamePolicy.WriteCaptured).
local GROUP = "stacking"
local TICKER = "stacking.apply"
local EPSILON = 0.0001

Stacking.GROUPS = {
    { id = "stacking", label = L["Stacking"] },
    { id = "edges", label = L["Screen edges"] },
    { id = "distance", label = L["Distance"] },
    { id = "scale", label = L["Scale"] },
    { id = "fade", label = L["Fade"] },
}
local groupLabels = {}
for _, group in ipairs(Stacking.GROUPS) do groupLabels[group.id] = group.label end

-- Stack Nameplates' two bits (12.x clients): they replace nameplateMotion where the client has them.
local STACK_ENEMY, STACK_FRIENDLY = "nameplateStackingTypes.Enemy", "nameplateStackingTypes.Friendly"

local LABELS = {
    nameplateMotion = L["Plate arrangement"],
    [STACK_ENEMY] = L["Stack enemy plates"],
    [STACK_FRIENDLY] = L["Stack friendly plates"],
    nameplateShowOffscreen = L["Show offscreen plates"],
    nameplateMotionSpeed = L["Movement speed"],
    nameplateOverlapV = L["Vertical spacing"],
    nameplateOverlapH = L["Horizontal spacing"],
    nameplateOtherTopInset = L["Top edge inset"],
    nameplateOtherBottomInset = L["Bottom edge inset"],
    nameplateLargeTopInset = L["Top edge inset (large plates)"],
    nameplateLargeBottomInset = L["Bottom edge inset (large plates)"],
    nameplateTargetRadialPosition = L["Keep target on screen"],
    nameplateTargetBehindMaxDistance = L["Target behind you: range"],
    nameplateMaxDistance = L["View distance"],
    nameplateMinScale = L["Smallest scale"],
    nameplateMaxScale = L["Largest scale"],
    nameplateMinScaleDistance = L["Smallest scale from"],
    nameplateMaxScaleDistance = L["Largest scale within"],
    nameplateSelectedScale = L["Target scale"],
    nameplateLargerScale = L["Important unit scale"],
    nameplateMinAlpha = L["Farthest opacity"],
    nameplateMaxAlpha = L["Nearest opacity"],
    nameplateMinAlphaDistance = L["Farthest opacity from"],
    nameplateMaxAlphaDistance = L["Nearest opacity within"],
    nameplateSelectedAlpha = L["Target opacity"],
    nameplateNotSelectedAlpha = L["Non-target opacity"],
    nameplateOccludedAlphaMult = L["Behind walls opacity"],
}
-- A bitfield's bits are one row, as in Blizzard's options (Stack Nameplates: a multi-select of Enemy Units
-- and Friendly Units): the row's label, and each bit's name in its menu.
local BITFIELD_LABELS = { nameplateStackingTypes = L["Stack plates"] }
local BIT_LABELS = { [STACK_ENEMY] = L["Enemy Units"], [STACK_FRIENDLY] = L["Friendly Units"] }
local CHOICE_LABELS = {
    nameplateMotion = { [0] = L["Overlapping"], [1] = L["Stacking"] },
    nameplateTargetRadialPosition = { [0] = L["Off"], [1] = L["Target only"], [2] = L["All plates in combat"] },
}

local function Settings()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return type(settings) == "table" and settings or nil
end

local function Options()
    local settings = Settings()
    return settings and type(settings.stacking) == "table" and settings.stacking or nil
end

-- A disabled PlateSmith sets nothing of Blizzard's.
local function Active(stacking)
    local settings = Settings()
    return stacking ~= nil and settings ~= nil and settings.enabled ~= false
end

-- A number as a CVar value: at most four decimals, no trailing zeros ("41", "0.025").
local function CVarText(value)
    local text = string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
    if text == "-0" then text = "0" end
    return text
end

local function SameValue(text, value)
    local current = tonumber(text)
    return current ~= nil and math.abs(current - value) < EPSILON
end

-- Catalogue ------------------------------------------------------------------------------------

-- Whether the client has name, and its default: GetCVarInfo, else GetCVarDefault, else a read.
local function ClientCVar(name)
    local info = C_CVar and C_CVar.GetCVarInfo
    if type(info) == "function" then
        local ok, value, default = pcall(info, name)
        if ok then
            if value == nil and default == nil then return false end
            return true, default
        end
    end
    local default = NamePolicy.Default(name)
    if default ~= nil then return true, default end
    return NamePolicy.Read(name) ~= nil, nil
end

-- One bit of a bitfield CVar, when the client has the CVar, the bitfield API and the bit's enum value:
-- registered with NamePolicy, which then reads and writes it as a CVar of its own.
local function ClientBit(key, spec)
    local cvar = C_CVar
    local enum = type(Enum) == "table" and Enum[spec.enum]
    local index = type(enum) == "table" and enum[spec.bit] or nil
    if type(index) ~= "number" or type(cvar) ~= "table" or type(cvar.GetCVarBitfield) ~= "function"
        or type(cvar.SetCVarBitfield) ~= "function" or not ClientCVar(spec.bitfield) then
        NamePolicy.RegisterBit(key, nil)
        return false
    end
    NamePolicy.RegisterBit(key, spec.bitfield, index)
    if NamePolicy.Read(key) ~= nil then return true end
    NamePolicy.RegisterBit(key, nil)
    return false
end

-- motionKey: the setting that makes enemy plates stack (Stack enemy plates, else nameplateMotion), which
-- the presets, combat stacking and the preview use.
local catalogue, present, motionKey

local function Detect()
    if catalogue then return catalogue end
    catalogue, present = {}, {}
    for _, spec in ipairs(S.STACKING_CVARS) do
        local key = spec[1]
        local exists, clientDefault
        if spec.bitfield then
            exists = ClientBit(key, spec)
        else
            exists, clientDefault = ClientCVar(key)
        end
        if exists then
            local default = S.StackingValue(key, clientDefault)
            if default == nil then default = spec.default end
            local entry = { key = key, label = LABELS[key] or key, group = spec[2], groupLabel = groupLabels[spec[2]],
                kind = spec[3], default = default, ignored = spec.ignored == true, bitfield = spec.bitfield }
            if spec.bitfield then
                entry.bitLabel = BIT_LABELS[key] or entry.label
                entry.bitfieldLabel = BITFIELD_LABELS[spec.bitfield] or spec.bitfield
            end
            if spec.choices then
                entry.choices = {}
                for index, value in ipairs(spec.choices) do
                    entry.choices[index] = { value = value, label = CHOICE_LABELS[key] and CHOICE_LABELS[key][value] or tostring(value) }
                end
                entry.min, entry.max, entry.step = spec.choices[1], spec.choices[#spec.choices], 1
            else
                entry.min, entry.max, entry.step = spec[4], spec[5], spec[6]
            end
            catalogue[#catalogue + 1] = entry
            present[key] = entry
        end
    end
    -- One way to choose stacking: where the client has the per-type bits, Plate arrangement is not offered.
    if present[STACK_ENEMY] and present.nameplateMotion then
        for index, entry in ipairs(catalogue) do
            if entry.key == "nameplateMotion" then table.remove(catalogue, index) break end
        end
        present.nameplateMotion = nil
    end
    motionKey = present[STACK_ENEMY] and STACK_ENEMY or present.nameplateMotion and "nameplateMotion" or nil
    return catalogue
end

-- The CVars this client has, in UI order: { key, label, group, groupLabel, kind (choice, toggle or
-- number), min, max, step, default (the client's), choices = { { value, label } }, ignored (the game no
-- longer reads it: shown, never written), bitfield (a bit of that CVar), and for a bit bitLabel (its name in
-- the bitfield's menu, Blizzard's) and bitfieldLabel (the one row its bitfield's bits share) }. Read only.
function Stacking.Catalogue() return Detect() end

function Stacking.Entry(key)
    Detect()
    return present[key]
end

-- True: one setting (Plate arrangement) stacks friendly and enemy plates alike on this client; false
-- where they are chosen apart (Stack enemy plates, Stack friendly plates) or there is none.
function Stacking.MotionShared()
    Detect()
    return present.nameplateMotion ~= nil
end

-- The setting that makes enemy plates stack on this client (nil: none).
function Stacking.MotionKey()
    Detect()
    return motionKey
end

-- Plate size -----------------------------------------------------------------------------------

-- The parts a plate draws most of the time set its stacking size: the health and power bars, the
-- name, the level, and the cast bar's height kept free while idle. Aura rows (only while there
-- are auras), markers, text lines under the bars and custom parts are left out, so a plate is not
-- spaced for what it rarely shows. A turned-off part is left out too.
local SIZED_PARTS = { "health", "power", "cast", "name", "level" }
local SIZE_LIMITS = { minWidth = 48, minHeight = 18, maxWidth = 320, maxHeight = 160 }
Stacking.SIZE_LIMITS = SIZE_LIMITS
-- A name is sized as a typical 12-letter name (half an em a letter); the level as two digits.
local NAME_LETTERS, LETTER_WIDTH = 12, 0.5

-- Part sizes from the profile alone (a plate's live sizes differ per unit), text at the drawn size.
local function StaticMeasure(profile, textScale)
    local width = tonumber(profile.width) or 112
    local healthHeight = tonumber(profile.healthHeight) or 10
    local styles = type(profile.styles) == "table" and profile.styles or nil
    local font = S.ScaledFontSize(S.StyledFontSize(tonumber(profile.nameFontSize) or 14, styles and styles.name), textScale)
    return function(key)
        if key == "health" then return width, healthHeight end
        if key == "power" then return tonumber(profile.powerWidth) or width, tonumber(profile.powerHeight) or 5 end
        if key == "cast" then
            return tonumber(profile.castWidth) or width, tonumber(profile.castHeight) or math.max(5, healthHeight - 3)
        end
        if key == "name" then return font * LETTER_WIDTH * NAME_LETTERS, font end
        if key == "level" then return font * LETTER_WIDTH * 2, font end
        if key == "buffs" or key == "debuffs" then
            local aura = type(profile.auraLayouts) == "table" and profile.auraLayouts[key]
            local gridWidth, gridHeight, offset = S.AuraGridBox(aura)
            if gridWidth then return gridWidth, gridHeight, nil, 0, offset end
            return nil
        end
        if S.IsGroupKey(key) or key:match("^value%d+$") then return nil end
        -- Combo points show on your target's plate only, so in a stack they take no room here. Blocks (no
        -- shape: every profile before 1.2.0) keep the size they always had, so those plates keep theirs.
        local combo = key == "combo" and styles and styles.combo
        if combo and combo.pipShape then return 0, 0, true end
        return 16, 12
    end
end

-- The drawn bounds of a layout's sized parts: width, height (profile scale applied), or nil.
local function LayoutBounds(profile, layout, textScale)
    if type(profile) ~= "table" or type(layout) ~= "table" then return nil end
    local measure = StaticMeasure(profile, textScale)
    local transforms = S.LayoutTransforms(layout, measure)
    local left, bottom, right, top
    for _, key in ipairs(SIZED_PARTS) do
        local position, transform = layout[key], transforms[key]
        if type(position) == "table" and not S.TurnedOff(position) and transform then
            local width, height = measure(key)
            local halfWidth, halfHeight = width * transform.scale / 2, height * transform.scale / 2
            left = math.min(left or math.huge, transform.x - halfWidth)
            right = math.max(right or -math.huge, transform.x + halfWidth)
            bottom = math.min(bottom or math.huge, transform.y - halfHeight)
            top = math.max(top or -math.huge, transform.y + halfHeight)
        end
    end
    if not left then return nil end
    local scale = tonumber(profile.scale) or 1
    return (right - left) * scale, (top - bottom) * scale
end

local function Clamp(width, height)
    return math.floor(math.max(SIZE_LIMITS.minWidth, math.min(SIZE_LIMITS.maxWidth, width)) + 0.5),
        math.floor(math.max(SIZE_LIMITS.minHeight, math.min(SIZE_LIMITS.maxHeight, height)) + 0.5)
end

local function Union(sizes)
    local width, height
    for _, size in ipairs(sizes) do
        if size[1] then width, height = math.max(width or 0, size[1]), math.max(height or 0, size[2]) end
    end
    if not width then return nil end
    return { Clamp(width, height) }
end

-- The plate sizes the shown layouts draw: { enemy = { w, h }, friendly = { w, h } | nil,
-- friendlyLocked = true in a dungeon or raid, where Blizzard owns friendly plates }. Each plate type
-- uses its design for where the player is (PlateContext); enemy plates the Enemies' and Enemy
-- players' (one size covers both), friendly plates Players' and Friendly NPCs' names-only or full
-- layout as each shows (Schema's FRIENDLY.Mode), whichever is larger. Blizzard has one friendly size for
-- both, so while either shows Blizzard's own plates none is set: those keep Blizzard's size.
local function DesignHere(settings, plateType)
    local context = PS.PlateContext
    local design = context and context.DesignFor(plateType, settings) or "world"
    return PS.Designs.For(settings, plateType, design) or settings.plateProfiles[plateType]
end

function Stacking.FrameSizes(settings)
    settings = settings or Settings()
    local profiles = settings and settings.plateProfiles
    if type(profiles) ~= "table" then return {} end
    local inInstance = NamePolicy.InGroupInstance()
    local enemy, players = DesignHere(settings, "enemy"), DesignHere(settings, "enemyPlayer")
    local enemySizes = { { LayoutBounds(enemy, enemy and enemy.layout, settings.textScale) } }
    -- Without a layer of their own enemy players draw with the Enemies' table.
    if players ~= enemy then enemySizes[2] = { LayoutBounds(players, players and players.layout, settings.textScale) } end
    local result = { enemy = Union(enemySizes) }
    if inInstance then
        result.friendlyLocked = true
    elseif not S.FRIENDLY.Any(settings, "off") then
        local friendlySizes = {}
        for _, plateType in ipairs(S.FRIENDLY.TYPES) do
            local design = DesignHere(settings, plateType)
            local field = S.FRIENDLY.Mode(settings, plateType) == "full" and "layout" or "namesLayout"
            friendlySizes[#friendlySizes + 1] = { LayoutBounds(design, design and design[field], settings.textScale) }
        end
        result.friendly = Union(friendlySizes)
    end
    return result
end

local SIZE_KINDS = { enemy = "Enemy", friendly = "Friendly" }
local sizes = { applied = {}, originals = {}, hooked = false }

-- Whether this client can size Blizzard's plates (C_NamePlate.SetNamePlateEnemySize and the
-- friendly one).
function Stacking.SizeSupport()
    return type(C_NamePlate) == "table" and type(C_NamePlate.SetNamePlateEnemySize) == "function"
        and type(C_NamePlate.SetNamePlateFriendlySize) == "function"
end

local function ReadSize(kind)
    local getter = C_NamePlate and C_NamePlate["GetNamePlate" .. SIZE_KINDS[kind] .. "Size"]
    if type(getter) ~= "function" then return nil end
    local ok, width, height = pcall(getter)
    if ok and Secret.IsReadable(width) and Secret.IsReadable(height) and type(width) == "number"
        and type(height) == "number" and width > 0 and height > 0 then
        return { width, height }
    end
    return nil
end

-- Blizzard's own size when the client cannot say: its driver's base size, else 110 x 45.
local function BlizzardDefaultSize()
    local driver = _G.NamePlateDriverFrame
    local width = type(driver) == "table" and rawget(driver, "baseNamePlateWidth")
    local height = type(driver) == "table" and rawget(driver, "baseNamePlateHeight")
    if type(width) == "number" and type(height) == "number" then return { width, height } end
    return { 110, 45 }
end

local function SetSize(kind, size)
    local setter = C_NamePlate["SetNamePlate" .. SIZE_KINDS[kind] .. "Size"]
    return pcall(setter, size[1], size[2])
end

local function RestoreSize(kind)
    if not sizes.applied[kind] then return end
    if Secret.InCombat() then
        sizes.pending = true
        return
    end
    SetSize(kind, sizes.originals[kind] or BlizzardDefaultSize())
    sizes.applied[kind] = nil
end

local function RestoreSizes()
    for kind in pairs(SIZE_KINDS) do RestoreSize(kind) end
end

local ApplySizes
-- Blizzard sets its own sizes again when its plate options change (a scale CVar, the screen
-- size): that is its new original, and the matched size goes back on top.
local function DriverUpdated()
    if not next(sizes.applied) then return end
    for kind in pairs(sizes.applied) do sizes.originals[kind] = ReadSize(kind) or sizes.originals[kind] end
    sizes.applied = {}
    ApplySizes()
end

local function HookDriver()
    if sizes.hooked then return end
    local driver = _G.NamePlateDriverFrame
    if type(hooksecurefunc) ~= "function" or type(driver) ~= "table"
        or type(driver.UpdateNamePlateOptions) ~= "function" then return end
    sizes.hooked = pcall(hooksecurefunc, driver, "UpdateNamePlateOptions", DriverUpdated)
end

ApplySizes = function()
    local stacking = Options()
    if not (Active(stacking) and stacking.matchFrameSize) or (PS.ExternalProvider and PS.ExternalProvider()) then
        RestoreSizes()
        return
    end
    if not Stacking.SizeSupport() then return end
    if Secret.InCombat() then
        sizes.pending = true
        return
    end
    sizes.pending = nil
    local wanted = Stacking.FrameSizes()
    for kind in pairs(SIZE_KINDS) do
        local size = wanted[kind]
        local applied = sizes.applied[kind]
        -- Blizzard's friendly plates in a dungeon are not ours to size: left as they are.
        local locked = kind == "friendly" and wanted.friendlyLocked
        if size and not locked then
            if not applied or applied[1] ~= size[1] or applied[2] ~= size[2] then
                if not applied and sizes.originals[kind] == nil then sizes.originals[kind] = ReadSize(kind) end
                if SetSize(kind, size) then sizes.applied[kind] = size end
            end
        elseif not locked then
            RestoreSize(kind)
        end
    end
    HookDriver()
end

-- The sizes PlateSmith has set: { enemy = { w, h }, friendly = { w, h } } (empty when none).
function Stacking.AppliedSizes() return sizes.applied end

-- Target and focus on top ----------------------------------------------------------------------

-- The target's overlay (and the focus's, when chosen) is raised over every other plate's, so its
-- parts draw on top where plates overlap. Only PlateSmith's own frames move; the level each had
-- is put back when it stops being the target or focus, or the plate goes.
-- A casting plate (the cast bar's castOnTop) rises too, under the target and focus: casting holds
-- the plates that want it, and a plate raised for a role keeps that role's boost until it ends.
local BOOST = { target = 200, focus = 100, cast = 50 }
local MAX_LEVEL = 9000
local onTop = { wanted = {}, raised = {}, casting = {} }
local attached = {}

-- Lifecycle's plate table and draw-order refresh (Styles.ApplyDrawOrder), which places a plate's
-- parts over its overlay's level.
function Stacking.Attach(context)
    attached.active = context.active
    attached.ApplyDrawOrder = context.ApplyDrawOrder
end

local function Reorder(data)
    if attached.ApplyDrawOrder and data.layout then pcall(attached.ApplyDrawOrder, data) end
end

local function Lower(data)
    local base = data.stackingBaseLevel
    if base == nil then return end
    data.stackingBaseLevel, data.stackingBoost = nil, nil
    pcall(data.overlay.SetFrameLevel, data.overlay, base)
    Reorder(data)
end

local function Raise(data, boost)
    local overlay = data.overlay
    if data.stackingBoost == boost then return end
    if data.stackingBaseLevel == nil then
        local ok, level = pcall(overlay.GetFrameLevel, overlay)
        if not ok or type(level) ~= "number" then return end
        data.stackingBaseLevel = level
    end
    if pcall(overlay.SetFrameLevel, overlay, math.min(MAX_LEVEL, data.stackingBaseLevel + boost)) then
        data.stackingBoost = boost
        Reorder(data)
    end
end

local function SyncOnTop()
    local stacking = Options()
    local target = stacking and stacking.targetOnTop and onTop.wanted.target or nil
    local focus = stacking and stacking.focusOnTop and onTop.wanted.focus or nil
    if focus == target then focus = nil end
    for role, data in pairs(onTop.raised) do
        if data ~= target and data ~= focus then
            if onTop.casting[data] then Raise(data, BOOST.cast) else Lower(data) end
        end
        onTop.raised[role] = nil
    end
    if target then
        Raise(target, BOOST.target)
        onTop.raised.target = target
    end
    if focus then
        Raise(focus, BOOST.focus)
        onTop.raised.focus = focus
    end
end

local function Plate(data)
    return type(data) == "table" and type(data.overlay) == "table" and data or nil
end

-- A plate became, or stopped being, the target (Lifecycle's UpdateTarget).
function Stacking.PlateTargeted(data, targeted)
    data = Plate(data)
    if not data then return end
    if targeted then
        onTop.wanted.target = data
    elseif onTop.wanted.target == data then
        onTop.wanted.target = nil
    end
    SyncOnTop()
end

-- The focus plate: found among the owned plates only while the option is on.
function Stacking.FocusChanged()
    local stacking = Options()
    local found
    if stacking and stacking.focusOnTop and attached.active then
        for unit, data in pairs(attached.active) do
            if data.unit == unit and Secret.SameUnit(unit, "focus") then found = data break end
        end
    end
    onTop.wanted.focus = Plate(found)
    SyncOnTop()
end

function Stacking.PlateAdded(data)
    local stacking = Options()
    if stacking and stacking.focusOnTop and Plate(data) and Secret.SameUnit(data.unit, "focus") then
        onTop.wanted.focus = data
        SyncOnTop()
    end
end

local function RaisedForRole(data)
    return onTop.raised.target == data or onTop.raised.focus == data
end

-- A plate started or stopped casting with castOnTop (Lifecycle's cast updates).
function Stacking.PlateCasting(data, casting)
    data = Plate(data)
    if not data then return end
    if casting then
        if onTop.casting[data] then return end
        onTop.casting[data] = true
        if not RaisedForRole(data) then Raise(data, BOOST.cast) end
    elseif onTop.casting[data] then
        onTop.casting[data] = nil
        if not RaisedForRole(data) then Lower(data) end
    end
end

function Stacking.PlateRemoved(data)
    if type(data) ~= "table" then return end
    onTop.casting[data] = nil
    for role, wanted in pairs(onTop.wanted) do
        if wanted == data then onTop.wanted[role] = nil end
    end
    for role, raised in pairs(onTop.raised) do
        if raised == data then onTop.raised[role] = nil end
    end
    if Plate(data) then Lower(data) end
end

-- The plate raised for role ("target" or "focus"), or nil.
function Stacking.RaisedPlate(role) return onTop.raised[role] end

-- CVars ----------------------------------------------------------------------------------------

-- Combat switch: nil until tried, then "allowed" or "refused" (the client would not take the
-- stacking switch, MotionKey, as combat began). combatSwitched: stacking is on for this fight.
local combat = { probe = nil, switched = false }
local wanted = {}

-- A value the profile keeps that PlateSmith writes: the client has the CVar and the game still reads it.
local function Settable(key)
    Detect()
    local entry = present[key]
    return entry ~= nil and not entry.ignored
end

-- A setting the profile sets that was changed outside PlateSmith (Blizzard's Options, another addon): the
-- outside value becomes the original to give back and PlateSmith's goes back on top, once. Written over
-- again within KEEP_INTERVAL (an addon that writes it back at once), PlateSmith's waits that long, so the
-- two are not fought every pass. kept: when PlateSmith last put a setting back over an outside change;
-- told: the settings chat has named this session.
local KEEP_INTERVAL = 2
local kept, told = {}, {}

local function Now()
    return type(GetTime) == "function" and GetTime() or nil
end

-- Said once a session per setting, so a change made in Blizzard's Options does not seem to be ignored.
local function TellKept(key, outside, value)
    if told[key] or not (PS.Chat and PS.Chat.Print) then return end
    told[key] = true
    local entry = present[key]
    local number = tonumber(outside)
    local text = number and CVarText(number) or tostring(outside)
    PS.Chat.Print(string.format(L["%s was changed outside PlateSmith, to %s. This profile sets it to %s, so PlateSmith "
        .. "put that back; give it back to the game (Studio › Settings › Stacking & distance) to use %s."],
        entry and entry.label or key, text, CVarText(value), text))
end

-- Writes the wanted CVars (each original captured once) and puts back any captured CVar that is
-- no longer wanted. During combat NamePolicy queues the writes for PLAYER_REGEN_ENABLED, and one given back keeps its
-- record until then (NamePolicy.Release), so a value queued is what counts as the CVar's now. A record
-- of an ignored CVar (written by an older PlateSmith) is put back like any other; one changed outside
-- PlateSmith since its last write is left as it is (NamePolicy.RestoreGroup).
local function ApplyCVars(stacking)
    if not Active(stacking) then
        NamePolicy.Release(GROUP)
        return
    end
    Detect()
    for key in pairs(wanted) do wanted[key] = nil end
    for key, value in pairs(stacking.values) do
        if Settable(key) then wanted[key] = value end
    end
    if combat.switched and motionKey then wanted[motionKey] = 1 end
    for key in pairs(NamePolicy.GroupNames(GROUP)) do
        if wanted[key] == nil then NamePolicy.Release(GROUP, key) end
    end
    local now, again = Now(), false
    for key, value in pairs(wanted) do
        local outside, new = NamePolicy.Adopt(GROUP, key)
        if SameValue(NamePolicy.Pending(key) or NamePolicy.Read(key), value) then
            NamePolicy.Held(GROUP, key)
        elseif outside ~= nil and now and kept[key] and now - kept[key] < KEEP_INTERVAL then
            again = true
        else
            if outside ~= nil then
                kept[key] = now
                if new then TellKept(key, outside, value) end
            end
            NamePolicy.WriteCaptured(GROUP, key, CVarText(value))
        end
    end
    return again
end

-- Once a session, before the first write: when every CVar the profile sets without a record already
-- holds the profile's value, PlateSmith most likely left them there (the saved file lost its record,
-- or the game closed before logout put them back; after a normal logout they hold the player's own).
-- Each one not at the client's default is marked lost and the default stands in for its original,
-- so giving it back to the game restores Blizzard's default. Only a numeric value tells: a switch
-- such as nameplateMotion = 1 alone is as likely the player's own.
local checked = false
local function CheckOriginals(stacking)
    if checked then return end
    checked = true
    if not Active(stacking) then return end
    Detect()
    local record = NamePolicy.CapturedGroup(GROUP) or {}
    local lost, telling = {}, false
    for key, value in pairs(stacking.values) do
        if Settable(key) and record[key] == nil then
            if not SameValue(NamePolicy.Read(key), value) then return end
            local default = NamePolicy.Default(key)
            if default == nil or not SameValue(default, value) then
                lost[#lost + 1] = key
                telling = telling or present[key].kind == "number"
            end
        end
    end
    if not telling then return end
    for _, key in ipairs(lost) do NamePolicy.MarkLost(GROUP, key) end
end

-- True while the original of a CVar PlateSmith sets was lost: giving it back to the game restores
-- Blizzard's default for it (the Studio page says so, and /ps diagnose lists it).
function Stacking.OriginalsMissing()
    return NamePolicy.OriginalsMissing(GROUP)
end

-- How many of this client's settings the profile sets (PlateSmith writes them); 0 while PlateSmith is
-- disabled, when it sets none.
function Stacking.OwnedCount()
    local stacking = Options()
    if not Active(stacking) then return 0 end
    Detect()
    local count = 0
    for key in pairs(stacking.values) do
        if Settable(key) then count = count + 1 end
    end
    return count
end

-- For diagnostics: { owned (how many settings PlateSmith sets), originals = "missing" (lost, see
-- above), "recorded" or "none" }.
function Stacking.Report()
    local originals = "none"
    if Stacking.OriginalsMissing() then
        originals = "missing"
    elseif NamePolicy.CapturedGroup(GROUP) then
        originals = "recorded"
    end
    return { owned = Stacking.OwnedCount(), originals = originals }
end

-- live: a stacking CVar may have changed outside PlateSmith (CVAR_UPDATE, the page opening), so the next
-- pass also shows the live values on Studio's page.
local dirty, live = false, false

-- Brings the client in line with the settings: CVars, plate sizes and the raised plates. Safe to
-- call at any time; nothing is written that already holds.
function Stacking.Apply()
    dirty = false
    PS.Ticker.SetEnabled(TICKER, false)
    local stacking = Options()
    if not stacking or not (PS.Profiles and PS.Profiles.State()) then return false end
    CheckOriginals(stacking)
    local again = ApplyCVars(stacking)
    ApplySizes()
    SyncOnTop()
    if again then Stacking.Invalidate() end
    if live then
        live = false
        local options = PS.Options
        if options and type(options.RefreshEditorStacking) == "function" then options:RefreshEditorStacking() end
    end
    return true
end

-- The settings may have changed (every refresh): applied on the next ticker pass, so a burst of
-- edits (a drag in Studio) is applied once.
function Stacking.Invalidate()
    if dirty then return end
    dirty = true
    PS.Ticker.SetEnabled(TICKER, true)
end

PS.Ticker.Register(TICKER, 0.2, function()
    if dirty then Stacking.Apply() end
end)
PS.Ticker.SetEnabled(TICKER, false)

-- A stacking CVar may have changed outside PlateSmith (CVAR_UPDATE; Studio's page opening, for a client that
-- sends none): checked on the next pass. A setting the profile sets keeps its value, the outside one becoming
-- its original (ApplyCVars); any other is only read, and the open page shows it.
function Stacking.LiveChanged()
    live = true
    Stacking.Invalidate()
end

-- The catalogue's CVars by lower-case name (a bitfield under its own name), for CVAR_UPDATE.
local watched
local function Watched(name)
    if not Secret.IsReadable(name) or type(name) ~= "string" then return true end
    if not watched then
        watched = {}
        for _, entry in ipairs(Detect()) do watched[string.lower(entry.bitfield or entry.key)] = true end
    end
    return watched[string.lower(name)] == true
end

-- Puts every captured stacking CVar and plate size back (logout).
function Stacking.RestoreAll(immediate)
    NamePolicy.RestoreGroup(GROUP, nil, immediate)
    if not Secret.InCombat() then RestoreSizes() end
end

-- Combat began (PLAYER_REGEN_DISABLED, just before the lockdown): with combat stacking on, stacking
-- is switched on for the fight. The first try proves whether the client allows it; a refusal
-- turns the option off for the session (CanCombatSwitch).
function Stacking.CombatStarted()
    local stacking = Options()
    if not (Active(stacking) and stacking.combatStacking) or combat.probe == "refused" then return end
    local key = Stacking.MotionKey()
    if not key then return end
    if PS.Profiles and PS.Profiles.State() then CheckOriginals(stacking) end
    if SameValue(NamePolicy.Read(key), 1) then return end
    local ok, written = pcall(NamePolicy.WriteCaptured, GROUP, key, "1", true)
    if ok and written and SameValue(NamePolicy.Read(key), 1) then
        combat.probe, combat.switched = "allowed", true
    else
        combat.probe = "refused"
    end
end

-- Combat ended: queued writes land first, then the out-of-combat state is applied.
function Stacking.CombatEnded()
    combat.switched = false
    NamePolicy.FlushPending()
    Stacking.Apply()
end

-- Whether combat stacking can work here: true only once the client took the switch; false with
-- "refused" or "untested" (the second result) otherwise.
function Stacking.CanCombatSwitch()
    return combat.probe == "allowed", combat.probe or "untested"
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT",
    "CVAR_UPDATE" }) do
    PS._RegisterEvent(eventFrame, event, "platesmith.stacking")
end
eventFrame:SetScript("OnEvent", function(_, event, name)
    if not Settings() then return end
    if event == "CVAR_UPDATE" then
        if Watched(name) then Stacking.LiveChanged() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Stacking.CombatStarted()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Stacking.CombatEnded()
    elseif event == "PLAYER_LOGOUT" then
        Stacking.RestoreAll(true)
    else
        -- After the zone's own handlers (the instance check); a CVar changed while loading (the client, another
        -- addon at login) is caught as any outside change.
        Stacking.LiveChanged()
    end
end)

-- Settings API (for the Studio page) -----------------------------------------------------------

-- Every change goes through the profile: it needs Save to keep, and Revert puts it back.
local function Mutate(change)
    local settings = Settings()
    if not settings then return false end
    if type(settings.stacking) ~= "table" then settings.stacking = S.NormalizeStacking(nil) end
    if change(settings.stacking) == false then return false end
    if type(PS.Refresh) == "function" then PS.Refresh() end
    Stacking.Apply()
    return true
end

local function MatchesPreset(stacking, name)
    local preset = S.STACKING_PRESETS[name]
    if not preset then return false end
    for key, value in pairs(preset) do
        if Settable(key) then
            local current = stacking.values[key]
            if current == nil or math.abs(current - value) >= EPSILON then return false end
        end
    end
    return true
end

-- A CVar's value: what the profile sets ("setting": PlateSmith writes it), else the client's live value
-- ("client": the game's own, read each time, so a change in Blizzard's Options shows), else its default
-- ("default", only when the client's cannot be read). nil for a CVar this client does not have. An
-- ignored CVar always reads the client's: a value the profile kept is not used. A client number outside
-- PlateSmith's range is shown as it is (Forever ships nameplateMinAlphaDistance -100000 and
-- nameplateNotSelectedAlpha -1, "not used"), never clamped into a value the game does not hold.
function Stacking.Get(key)
    local entry = Stacking.Entry(key)
    if not entry then return nil end
    local stacking, value = Options(), nil
    if stacking and not entry.ignored then value = stacking.values[key] end
    if value ~= nil then return value, "setting" end
    local text = NamePolicy.Read(key)
    if entry.kind == "number" then
        value = tonumber(text)
        if value ~= value then value = nil end
    else
        value = S.StackingValue(key, text)
    end
    if value ~= nil then return value, "client" end
    return entry.default, "default"
end

-- Whether Blizzard stacks plates now: "stacking" while any kind of plate stacks, "overlapping", or
-- nil on a client without a stacking setting. values (optional) override the current ones.
function Stacking.Arrangement(values)
    Detect()
    local found
    for _, key in ipairs({ "nameplateMotion", STACK_ENEMY, STACK_FRIENDLY }) do
        if present[key] then
            local value = values and values[key]
            if value == nil then value = Stacking.Get(key) end
            if value == 1 then return "stacking" end
            found = "overlapping"
        end
    end
    return found
end

-- Sets a CVar's value: PlateSmith writes it from now on (nil: it is the game's own again, put back
-- as it was). False for a CVar this client lacks or the game ignores, or a value it cannot take. A
-- value that leaves the chosen preset makes it "custom".
function Stacking.Set(key, value)
    if not Settable(key) then return false end
    local valid
    if value ~= nil then
        valid = S.StackingValue(key, value)
        if valid == nil then return false end
    end
    return Mutate(function(stacking)
        stacking.values[key] = valid
        if stacking.preset ~= "custom" and not MatchesPreset(stacking, stacking.preset) then stacking.preset = "custom" end
    end)
end

-- tight, normal or loose writes that preset's values (docs/STACKING.md); custom keeps the values.
function Stacking.ApplyPreset(name)
    if not S.stackingPresetNames[name] then return false end
    Detect()
    return Mutate(function(stacking)
        for key, value in pairs(S.STACKING_PRESETS[name] or {}) do
            if Settable(key) then stacking.values[key] = value end
        end
        stacking.preset = name
    end)
end

function Stacking.Preset()
    local stacking = Options()
    return stacking and stacking.preset or S.stackingDefaults.preset
end

-- Every catalogued CVar to the client's default, and every one the game's own again (the Studio
-- page's reset): the defaults become the recorded originals, the profile's values are cleared
-- (preset custom) and Apply puts each back to its default. A bitfield has no default per bit: its
-- whole CVar is written with the client's default once its bits are back. An ignored CVar is left.
-- The writes queue in combat for PLAYER_REGEN_ENABLED. Returns true and the CVars the client reports
-- no default for (left as they are), or false without settings.
function Stacking.ResetToDefaults()
    if not (Settings() and PS.Profiles and PS.Profiles.State()) then return false, {} end
    Detect()
    local left, fields, order = {}, {}, {}
    for _, entry in ipairs(catalogue) do
        if entry.bitfield then
            if not fields[entry.bitfield] then
                fields[entry.bitfield], order[#order + 1] = true, entry.bitfield
            end
        elseif not entry.ignored then
            local default = NamePolicy.Default(entry.key)
            if default == nil then
                left[#left + 1] = entry.key
            else
                NamePolicy.SetOriginal(GROUP, entry.key, default)
            end
        end
    end
    local done = Mutate(function(stacking) stacking.values, stacking.preset = {}, "custom" end)
    for _, cvar in ipairs(order) do
        local default = NamePolicy.Default(cvar)
        if default == nil then left[#left + 1] = cvar else NamePolicy.Write(cvar, default) end
    end
    return done, left
end

-- The on/off options: targetOnTop, focusOnTop, matchFrameSize, combatStacking.
Stacking.OPTIONS = S.STACKING_OPTIONS
local isOption = {}
for _, name in ipairs(S.STACKING_OPTIONS) do isOption[name] = true end

function Stacking.GetOption(name)
    if not isOption[name] then return nil end
    local stacking = Options()
    if stacking and stacking[name] ~= nil then return stacking[name] end
    return S.stackingDefaults[name]
end

function Stacking.SetOption(name, value)
    if not isOption[name] or type(value) ~= "boolean" then return false end
    local done = Mutate(function(stacking) stacking[name] = value end)
    if done and name == "focusOnTop" then Stacking.FocusChanged() end
    return done
end

-- Preview ----------------------------------------------------------------------------------------

-- The CVars the preview model reads, in catalogue order: a change to any of them moves the diagram.
-- Its units are enemies, so Stack enemy plates (where the client has it) is their arrangement.
Stacking.PREVIEW_KEYS = { "nameplateMotion", STACK_ENEMY, "nameplateMotionSpeed", "nameplateOverlapV", "nameplateOverlapH",
    "nameplateMaxDistance", "nameplateMinScale", "nameplateMaxScale", "nameplateMinScaleDistance",
    "nameplateMaxScaleDistance", "nameplateSelectedScale", "nameplateMinAlpha", "nameplateMaxAlpha",
    "nameplateMinAlphaDistance", "nameplateMaxAlphaDistance", "nameplateSelectedAlpha", "nameplateNotSelectedAlpha" }
local previewed = {}
for _, key in ipairs(Stacking.PREVIEW_KEYS) do previewed[key] = true end

function Stacking.Previewed(key)
    return previewed[key] == true
end

-- Three units in a row, heads UNIT_GAP plate widths apart: near, your target at mid range, far.
Stacking.PREVIEW_UNITS = { { distance = 8 }, { distance = 20, target = true }, { distance = 34 } }
local UNIT_GAP = 0.4
-- A CVar the client lacks is a behaviour it lacks: no scaling or fading (the spacing keeps
-- Blizzard's usual values, so the diagram still shows plates). The distances fall back to Schema's.
local PREVIEW_NEUTRAL = { nameplateMotion = 0, nameplateMotionSpeed = 0, nameplateOverlapV = 1.1,
    nameplateOverlapH = 0.8, nameplateMinScale = 1, nameplateMaxScale = 1, nameplateSelectedScale = 1,
    nameplateMinAlpha = 1, nameplateMaxAlpha = 1, nameplateSelectedAlpha = 1, nameplateNotSelectedAlpha = 1 }
local schemaDefault = {}
for _, spec in ipairs(S.STACKING_CVARS) do schemaDefault[spec[1]] = spec.default end

-- Blizzard's help for the scale and alpha distance CVars: the Max value holds within MaxDistance of
-- the camera, the Min value from MinDistance short of the view distance, a straight line between.
-- When the two ranges meet or cross, the near value holds up to its distance and the far one after.
local function Ramp(distance, near, far, nearValue, farValue)
    if distance <= near then return nearValue end
    if distance >= far then return farValue end
    return nearValue + (farValue - nearValue) * (distance - near) / (far - near)
end

-- A geometry model for the UI's diagram (pure: values in, shapes out). Three units stand in a row,
-- 8, 20 and 34 yards away (the middle one your target), and each plate sits on its unit's head:
-- - scale: the distance scale (nameplateMaxScale within nameplateMaxScaleDistance, nameplateMinScale
--   from nameplateMinScaleDistance short of nameplateMaxDistance), times nameplateSelectedScale for
--   the target;
-- - alpha: the distance fade the same way (nameplateMaxAlpha, nameplateMinAlpha and their distances),
--   times nameplateSelectedAlpha for the target and nameplateNotSelectedAlpha for the others;
-- - a unit beyond nameplateMaxDistance has no plate;
-- - Overlapping (Stack enemy plates off, else nameplateMotion 0): each plate stays on its unit.
--   Stacking: each plate moves up until it is overlapV times the two plates' mean height from any
--   plate within overlapH times their mean width of it; Blizzard's stacking moves plates up only.
-- values (optional) override the current CVars (the keys in PREVIEW_KEYS) and may carry width, height
-- and targetOnTop; otherwise the client's values, the matched enemy size and the option. Returns
-- { motion, speed, width, height, overlapV, overlapH, viewDistance, targetOnTop,
--   plates = { { x, y, width, height, scale, alpha, target, shown, distance, unitX, unitY } },
--   bounds = { left, bottom, right, top } }: x, y are plate centres, y up, the first unit's head at
-- 0, 0; a plate's width and height are its scaled size, the model's the unscaled plate's.
function Stacking.PreviewModel(values)
    values = type(values) == "table" and values or {}
    local function Present(key) return values[key] ~= nil or Stacking.Entry(key) ~= nil end
    local function Value(key)
        local value = tonumber(values[key])
        if value == nil and Stacking.Entry(key) then value = tonumber((Stacking.Get(key))) end
        if value == nil then value = PREVIEW_NEUTRAL[key] end
        if value == nil then value = schemaDefault[key] end
        return value
    end
    local width, height = tonumber(values.width), tonumber(values.height)
    if not (width and height) then
        -- A layout the size model cannot measure must not stop the diagram: the bar's size stands in.
        local ok, frameSizes = pcall(Stacking.FrameSizes)
        local size = ok and type(frameSizes) == "table" and frameSizes.enemy or nil
        local settings = Settings()
        local enemy = settings and settings.plateProfiles and settings.plateProfiles.enemy
        width = width or (size and size[1]) or (enemy and enemy.width) or 112
        height = height or (size and size[2]) or math.max(SIZE_LIMITS.minHeight, (enemy and enemy.healthHeight or 10) + 12)
    end
    local targetOnTop = values.targetOnTop
    if type(targetOnTop) ~= "boolean" then targetOnTop = Stacking.GetOption("targetOnTop") == true end
    local arrangement = (values[STACK_ENEMY] ~= nil or Stacking.Entry(STACK_ENEMY)) and STACK_ENEMY or "nameplateMotion"
    local motion = Value(arrangement) == 1 and "stacking" or "overlapping"
    local overlapV, overlapH = Value("nameplateOverlapV"), Value("nameplateOverlapH")
    local viewDistance = Present("nameplateMaxDistance") and Value("nameplateMaxDistance") or nil
    local rampEnd = viewDistance or schemaDefault.nameplateMaxDistance
    local model = { motion = motion, speed = math.max(0, Value("nameplateMotionSpeed")), width = width, height = height,
        overlapV = overlapV, overlapH = overlapH, viewDistance = viewDistance, targetOnTop = targetOnTop, plates = {} }
    local left, bottom, right, top = math.huge, math.huge, -math.huge, -math.huge
    for index, unit in ipairs(Stacking.PREVIEW_UNITS) do
        local target, distance = unit.target == true, unit.distance
        local shown = viewDistance == nil or distance <= viewDistance
        local scale = Ramp(distance, Value("nameplateMaxScaleDistance"), rampEnd - Value("nameplateMinScaleDistance"),
            Value("nameplateMaxScale"), Value("nameplateMinScale"))
        local alpha = Ramp(distance, Value("nameplateMaxAlphaDistance"), rampEnd - Value("nameplateMinAlphaDistance"),
            Value("nameplateMaxAlpha"), Value("nameplateMinAlpha"))
        -- A negative multiplier is the client's "not used" (Forever ships nameplateNotSelectedAlpha -1).
        local function Multiplier(key)
            local value = Value(key)
            return (value and value >= 0) and value or 1
        end
        if target then
            scale, alpha = scale * Multiplier("nameplateSelectedScale"), alpha * Multiplier("nameplateSelectedAlpha")
        else
            alpha = alpha * Multiplier("nameplateNotSelectedAlpha")
        end
        scale, alpha = math.max(0.05, scale), math.max(0, math.min(1, alpha))
        local plateWidth, plateHeight = width * scale, height * scale
        local unitX, unitY = (index - 1) * UNIT_GAP * width, 0
        local y = unitY + plateHeight / 2
        if motion == "stacking" and shown then
            for _ = 1, #Stacking.PREVIEW_UNITS do
                local moved = false
                for _, other in ipairs(model.plates) do
                    if other.shown then
                        local apartX = overlapH * (plateWidth + other.width) / 2
                        local apartY = overlapV * (plateHeight + other.height) / 2
                        if math.abs(other.x - unitX) < apartX and math.abs(other.y - y) < apartY - EPSILON then
                            y, moved = other.y + apartY, true
                        end
                    end
                end
                if not moved then break end
            end
        end
        model.plates[index] = { x = unitX, y = y, width = plateWidth, height = plateHeight, scale = scale, alpha = alpha,
            target = target, shown = shown, distance = distance, unitX = unitX, unitY = unitY }
        left, right, bottom = math.min(left, unitX), math.max(right, unitX), math.min(bottom, unitY)
        if shown then
            left, right = math.min(left, unitX - plateWidth / 2), math.max(right, unitX + plateWidth / 2)
            top = math.max(top, y + plateHeight / 2)
        end
    end
    model.bounds = { left = left, bottom = bottom, right = right, top = math.max(top, 0) }
    return model
end

-- One animation step of a plate gliding from `from` to `to` over `elapsed` seconds. Blizzard's help
-- calls nameplateMotionSpeed the rate plates animate to their places; the preview reads it as the
-- share of the remaining way covered each 60th of a second, and 0 as a jump. Returns the new place
-- and true once it is within `settle` (default 0.5) of `to`.
function Stacking.PreviewGlide(from, to, speed, elapsed, settle)
    speed, elapsed, settle = tonumber(speed) or 0, math.max(0, tonumber(elapsed) or 0), tonumber(settle) or 0.5
    if speed <= 0 or speed >= 1 or math.abs(to - from) <= settle then return to, true end
    local remaining = (to - from) * (1 - speed) ^ (elapsed * 60)
    if math.abs(remaining) <= settle then return to, true end
    return to - remaining, false
end

-- For the suites: detection again (a new mocked client) and the combat probe forgotten; newSession
-- also runs the login check for lost originals again.
function Stacking._Reset(newSession)
    if newSession then checked, kept, told = false, {}, {} end
    catalogue, present, motionKey, watched, live = nil, nil, nil, nil, false
    combat.probe, combat.switched = nil, false
    sizes.applied, sizes.originals, sizes.pending, sizes.hooked = {}, {}, nil, false
    onTop.wanted, onTop.raised, onTop.casting = {}, {}, {}
end
