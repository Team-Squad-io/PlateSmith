-- Blizzard's plate stacking, managed: its stacking, distance, scale and fade CVars, the plate size
-- its stacking spaces plates by, and the target and focus overlays drawn over the rest.
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

local LABELS = {
    nameplateMotion = L["Plate arrangement"],
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
local CHOICE_LABELS = {
    nameplateMotion = { [0] = L["Overlapping"], [1] = L["Stacking"] },
    nameplateTargetRadialPosition = { [0] = L["Off"], [1] = L["Target only"], [2] = L["All plates in combat"] },
}

-- Names a client could use for separate friendly and enemy stacking. Neither Retail nor Classic
-- is known to have them; they are probed so a client that does is reported (MotionShared).
local SEPARATE_MOTION_CVARS = { "nameplateMotionFriendly", "nameplateMotionEnemy", "nameplateOverlapVFriendly",
    "nameplateOverlapVEnemy" }

local function Settings()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return type(settings) == "table" and settings or nil
end

local function Options()
    local settings = Settings()
    return settings and type(settings.stacking) == "table" and settings.stacking or nil
end

local function Managed(stacking)
    local settings = Settings()
    return stacking and stacking.managed == true and settings and settings.enabled ~= false
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
    local getDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if type(getDefault) == "function" then
        local ok, default = pcall(getDefault, name)
        if ok and default ~= nil then return true, default end
    end
    return NamePolicy.Read(name) ~= nil, nil
end

local catalogue, present, motionShared

local function Detect()
    if catalogue then return catalogue end
    catalogue, present = {}, {}
    for _, spec in ipairs(S.STACKING_CVARS) do
        local key = spec[1]
        local exists, clientDefault = ClientCVar(key)
        if exists then
            local default = S.StackingValue(key, clientDefault)
            if default == nil then default = spec.default end
            local entry = { key = key, label = LABELS[key] or key, group = spec[2], groupLabel = groupLabels[spec[2]],
                kind = spec[3], default = default }
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
    motionShared = true
    for _, name in ipairs(SEPARATE_MOTION_CVARS) do
        if ClientCVar(name) then motionShared = false end
    end
    return catalogue
end

-- The CVars this client has, in UI order: { key, label, group, groupLabel, kind (choice or
-- number), min, max, step, default (the client's), choices = { { value, label } } }. Read only.
function Stacking.Catalogue() return Detect() end

function Stacking.Entry(key)
    Detect()
    return present[key]
end

-- True: friendly and enemy plates share one set of stacking CVars on this client.
function Stacking.MotionShared()
    Detect()
    return motionShared
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

-- Part sizes from the profile alone (a plate's live sizes differ per unit).
local function StaticMeasure(profile)
    local width = tonumber(profile.width) or 112
    local healthHeight = tonumber(profile.healthHeight) or 10
    local font = tonumber(profile.nameFontSize) or 12
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
        return 16, 12
    end
end

-- The drawn bounds of a layout's sized parts: width, height (profile scale applied), or nil.
local function LayoutBounds(profile, layout)
    if type(profile) ~= "table" or type(layout) ~= "table" then return nil end
    local measure = StaticMeasure(profile)
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
-- friendlyLocked = true in a dungeon or raid, where Blizzard owns friendly plates }. Enemies use
-- the dungeon override inside a group instance; friendly plates use the names-only or full
-- layouts (players' and NPCs', whichever is larger), or none while friendly plates are off.
function Stacking.FrameSizes(settings)
    settings = settings or Settings()
    local profiles = settings and settings.plateProfiles
    if type(profiles) ~= "table" then return {} end
    local inInstance = NamePolicy.InGroupInstance()
    local enemy = inInstance and profiles.enemyDungeon or profiles.enemy
    local result = { enemy = Union({ { LayoutBounds(enemy, enemy and enemy.layout) } }) }
    if inInstance then
        result.friendlyLocked = true
    elseif settings.friendly ~= "off" then
        local field = settings.friendly == "full" and "layout" or "namesLayout"
        local player, npc = profiles.friendlyPlayer, profiles.friendlyNPC
        result.friendly = Union({ { LayoutBounds(player, player and player[field]) },
            { LayoutBounds(npc, npc and npc[field]) } })
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
    if not (Managed(stacking) and stacking.matchFrameSize) or (PS.ExternalProvider and PS.ExternalProvider()) then
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
local BOOST = { target = 200, focus = 100 }
local MAX_LEVEL = 9000
local onTop = { wanted = {}, raised = {} }
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
        if data ~= target and data ~= focus then Lower(data) end
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

function Stacking.PlateRemoved(data)
    if type(data) ~= "table" then return end
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

-- Combat switch: nil until tried, then "allowed" or "refused" (the client would not take
-- nameplateMotion as combat began). combatSwitched: stacking is on for this fight.
local combat = { probe = nil, switched = false }
local wanted = {}

-- Writes the wanted CVars (each original captured once) and puts back any captured CVar that is
-- no longer wanted. During combat NamePolicy queues the writes for PLAYER_REGEN_ENABLED.
local function ApplyCVars(stacking)
    if not Managed(stacking) then
        NamePolicy.RestoreGroup(GROUP)
        return
    end
    Detect()
    for key in pairs(wanted) do wanted[key] = nil end
    for key, value in pairs(stacking.values) do
        if present[key] then wanted[key] = value end
    end
    if combat.switched then wanted.nameplateMotion = 1 end
    local captured = NamePolicy.CapturedGroup(GROUP)
    if captured then
        for key in pairs(captured) do
            if wanted[key] == nil then NamePolicy.RestoreGroup(GROUP, key) end
        end
    end
    for key, value in pairs(wanted) do
        if not SameValue(NamePolicy.Read(key), value) then NamePolicy.WriteCaptured(GROUP, key, CVarText(value)) end
    end
end

local dirty = false

-- Brings the client in line with the settings: CVars, plate sizes and the raised plates. Safe to
-- call at any time; nothing is written that already holds.
function Stacking.Apply()
    dirty = false
    PS.Ticker.SetEnabled(TICKER, false)
    local stacking = Options()
    if not stacking or not (PS.Profiles and PS.Profiles.State()) then return false end
    ApplyCVars(stacking)
    ApplySizes()
    SyncOnTop()
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
    if not (Managed(stacking) and stacking.combatStacking) or combat.probe == "refused" then return end
    if not Stacking.Entry("nameplateMotion") then return end
    if SameValue(NamePolicy.Read("nameplateMotion"), 1) then return end
    local ok, written = pcall(NamePolicy.WriteCaptured, GROUP, "nameplateMotion", "1", true)
    if ok and written and SameValue(NamePolicy.Read("nameplateMotion"), 1) then
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
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
    PS._RegisterEvent(eventFrame, event, "platesmith.stacking")
end
eventFrame:SetScript("OnEvent", function(_, event)
    if not Settings() then return end
    if event == "PLAYER_REGEN_DISABLED" then
        Stacking.CombatStarted()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Stacking.CombatEnded()
    elseif event == "PLAYER_LOGOUT" then
        Stacking.RestoreAll(true)
    else
        -- After the zone's own handlers (the instance check), and again if the client reset a CVar.
        Stacking.Invalidate()
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
        if present[key] then
            local current = stacking.values[key]
            if current == nil or math.abs(current - value) >= EPSILON then return false end
        end
    end
    return true
end

-- A CVar's value: what the profile sets ("setting"), else the client's ("client"), else its
-- default ("default"). nil for a CVar this client does not have.
function Stacking.Get(key)
    local entry = Stacking.Entry(key)
    if not entry then return nil end
    local stacking = Options()
    local value = stacking and stacking.values[key]
    if value ~= nil then return value, "setting" end
    value = S.StackingValue(key, NamePolicy.Read(key))
    if value ~= nil then return value, "client" end
    return entry.default, "default"
end

-- Sets a CVar's value (nil: back to the client's own). False for a CVar this client lacks or a
-- value it cannot take. A value that leaves the chosen preset makes it "custom".
function Stacking.Set(key, value)
    if not Stacking.Entry(key) then return false end
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
            if present[key] then stacking.values[key] = value end
        end
        stacking.preset = name
    end)
end

function Stacking.Preset()
    local stacking = Options()
    return stacking and stacking.preset or S.stackingDefaults.preset
end

-- Off: every captured CVar and plate size goes back and nothing more is written.
function Stacking.SetManaged(managed)
    if type(managed) ~= "boolean" then return false end
    return Mutate(function(stacking) stacking.managed = managed end)
end

function Stacking.IsManaged()
    local stacking = Options()
    return stacking ~= nil and stacking.managed == true
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

-- A small geometry model for the UI's diagram: three units standing close together (heads 0.3 of
-- a plate apart, left to right) and where their plates are drawn. Overlapping: each plate sits on
-- its unit. Stacking: each plate moves up until it is overlapV plate heights from any plate that
-- is within overlapH plate widths of it, as Blizzard's stacking does. values (optional) override
-- the current CVars (nameplateMotion, nameplateOverlapV, nameplateOverlapH) and may carry width
-- and height; otherwise the matched enemy size, else the enemy health bar. Returns
-- { motion, width, height, overlapV, overlapH, plates = { { x, y, width, height, unitX, unitY } },
-- bounds = { left, bottom, right, top } }; x, y are centres, y up, the first unit at 0, 0.
function Stacking.PreviewModel(values)
    values = type(values) == "table" and values or {}
    local function Value(key, fallback)
        local value = tonumber(values[key])
        if value == nil and Stacking.Entry(key) then value = Stacking.Get(key) end
        return value or fallback
    end
    local width, height = tonumber(values.width), tonumber(values.height)
    if not (width and height) then
        local size = Stacking.FrameSizes().enemy
        local settings = Settings()
        local enemy = settings and settings.plateProfiles and settings.plateProfiles.enemy
        width = width or (size and size[1]) or (enemy and enemy.width) or 112
        height = height or (size and size[2]) or math.max(SIZE_LIMITS.minHeight, (enemy and enemy.healthHeight or 10) + 12)
    end
    local motion = Value("nameplateMotion", 0) == 1 and "stacking" or "overlapping"
    local overlapV, overlapH = Value("nameplateOverlapV", 1.1), Value("nameplateOverlapH", 0.8)
    local model = { motion = motion, width = width, height = height, overlapV = overlapV, overlapH = overlapH, plates = {} }
    local left, bottom, right, top = math.huge, math.huge, -math.huge, -math.huge
    for index = 1, 3 do
        local unitX, unitY = (index - 1) * 0.3 * width, 0
        local y = unitY
        if motion == "stacking" then
            for _ = 1, 3 do
                local moved = false
                for _, other in ipairs(model.plates) do
                    if math.abs(other.x - unitX) < width * overlapH and math.abs(other.y - y) < height * overlapV then
                        y, moved = other.y + height * overlapV, true
                    end
                end
                if not moved then break end
            end
        end
        model.plates[index] = { x = unitX, y = y, width = width, height = height, unitX = unitX, unitY = unitY }
        left, right = math.min(left, unitX - width / 2), math.max(right, unitX + width / 2)
        bottom, top = math.min(bottom, y - height / 2), math.max(top, y + height / 2)
    end
    model.bounds = { left = left, bottom = bottom, right = right, top = top }
    return model
end

-- For the suites: detection again (a new mocked client) and the combat probe forgotten.
function Stacking._Reset()
    catalogue, present, motionShared = nil, nil, nil
    combat.probe, combat.switched = nil, false
    sizes.applied, sizes.originals, sizes.pending, sizes.hooked = {}, {}, nil, false
    onTop.wanted, onTop.raised = {}, {}
end
