-- The plate runtime: which plates are owned, their updates from events and the ticker, and the
-- once-per-frame flush that renders values, rules, stacks and hiding under a hidden parent.
local _, PS = ...

local DiagnosticUI = assert(PS.DiagnosticUI, "PlateSmith DiagnosticUI missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local ThreatText = assert(PS.ThreatText, "PlateSmith ThreatText missing")
local NamePolicy = assert(PS.NamePolicy, "PlateSmith NamePolicy missing")
local RaidMarker = assert(PS.RaidMarker, "PlateSmith RaidMarker missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local VALUE_SLOT_COUNT = S.VALUE_SLOT_COUNT
local NormalizeCharacterSettings = S.NormalizeCharacterSettings
local IsReadable, HasValue, SameUnit = Secret.IsReadable, Secret.HasValue, Secret.SameUnit
local ApplyThreatText, ApplyThreatColour = ThreatText.Apply, ThreatText.ApplyStateColour

-- Another nameplate addon draws the plates when one runs (mode auto); Conflicts keeps the list.
local ExternalProvider = assert(PS.Conflicts, "PlateSmith Conflicts missing").Provider

local active = {}
local activeCasts = {}
local spotlightUnit, spotlightUntil, spotlightDimmed
local db
local THREAT_TRACK_RETRY = 1
local QUEST_REFRESH_INTERVAL = 0.25
local HEALTH_BACKSTOP_INTERVAL = 0.5
local AURA_EVENT_INTERVAL = 0.1
-- Cadences and budgets (tests/perf_smoke.lua measures them): the state pass visits each plate
-- that has time-based work at most every STATE_INTERVAL, a few plates a frame; social updates
-- re-read relationships at most every RELATIONSHIP_INTERVAL; plate adds and aura reads past
-- ADD_BUDGET_MS of measured time in one frame wait for the next. An add that has waited both
-- ADD_OVERDUE_FRAMES frames and ADD_OVERDUE_MS of profiler time (so a high frame rate keeps the
-- budget and a low one still caps the wait) runs whatever the budget says: ADD_OVERDUE_PER_FRAME such
-- adds a frame, one if a plate was built in the frame. A frame builds at most half a plate on any path
-- (a timed build is split over two frames, adds.Half).
-- CONTEXT_HOLD: after a resting flip is applied, the next is worked out no sooner (a city's edge).
-- Spares (PlateParts): SPARE_IDLE_MS, or SPARE_IDLE_SHARE of the last frame's length (up to ADD_BUDGET_MS),
-- is the most plate work a frame may have done for the spares entry to build in it. Warming (SPARE_WARM_*):
-- SPARE_CHURN_ADDS adds within SPARE_CHURN_SECONDS (a flight or a mount arriving), or a change into a city,
-- out of combat, raises the target to the peak plus SPARE_WARM (up to SPARE_CROWD) for SPARE_WARM_SECONDS.
local LIMITS = { STATE_INTERVAL = 0.25, STATE_PLATES_PER_FRAME = 4, NATIVE_PLATES_PER_PASS = 4,
    RELATIONSHIP_INTERVAL = 1, ADD_BUDGET_MS = 3, ADD_OVERDUE_FRAMES = 2, ADD_OVERDUE_MS = 50, ADD_OVERDUE_PER_FRAME = 2,
    RAID_FALLBACK_INTERVAL = 0.25, NATIVE_INTERVAL = 2, CONTEXT_HOLD = 2,
    SPARE_PLATES = 8, SPARE_MAX = 24, SPARE_CROWD = 64, SPARE_IDLE_MS = 1, SPARE_IDLE_SHARE = 0.05, SPARE_DELAY = 2,
    SPARE_INTERVAL = 0.1, SPARE_WARM = 16, SPARE_WARM_SECONDS = 30, SPARE_CHURN_ADDS = 8, SPARE_CHURN_SECONDS = 2 }

-- Call counts for the performance guards (PS._Test.Counters); plain integers.
local counters = { appearance = 0, componentLayout = 0, renderValues = 0, applyRules = 0, reflow = 0,
    parentVisibility = 0, updateIdentity = 0, auraReads = 0, auraRowLayouts = 0, applyLayout = 0, flushes = 0,
    deferredAdds = 0, overdueAdds = 0, batches = 0, platesBuilt = 0, sparesBuilt = 0, sparesUsed = 0, auraPasses = 0, auraReflows = 0,
    contextRelayouts = 0, contextPlates = 0, buildHalves = 0, sparesWarmed = 0 }

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

-- The phases of one plate add (performance.addPhases), timed only inside adds.Now with a profiler
-- clock. A phase's time leaves out the phases timed inside it: nested holds the time already given
-- to phases, so its own time is its span less what nested grew by during it. A phase met twice in
-- one add (placement: before and in the flush) is summed, and each is recorded once per add.
local addPhases = { on = false, nested = 0, spent = {}, ran = {},
    names = PS.Performance and PS.Performance.ADD_PHASES, Record = PS.Performance and PS.Performance.RecordPhase }

function addPhases.Start()
    if addPhases.on then return Clock(), addPhases.nested end
end

function addPhases.Stop(phase, started, nestedBefore)
    if not started then return end
    local span = Clock() - started
    addPhases.spent[phase] = (addPhases.ran[phase] and addPhases.spent[phase] or 0) + span - (addPhases.nested - nestedBefore)
    addPhases.ran[phase] = true
    addPhases.nested = nestedBefore + span
end

-- Records this add's phases and stops timing.
function addPhases.Finish()
    addPhases.on, addPhases.nested = false, 0
    for _, phase in ipairs(addPhases.names) do
        if addPhases.ran[phase] then
            addPhases.ran[phase] = false
            addPhases.Record(phase, addPhases.spent[phase])
        end
    end
end

-- Plate work queued by updates and events (the dirty mask), done by FlushPlate at most once
-- per plate per frame: one pass over the custom parts, one rules pass, one stack check and one
-- pass hiding what sits under a hidden parent. Inside a batch (an event, a ticker entry, a
-- settings refresh) marks only queue; the batch's end flushes, or the frame's first ticker entry
-- does for the bursty unit events. A mark outside any batch (a frame hook) flushes at once.
local dirtyPlates = {}
local batchDepth = 0
local FlushPlate

local function Queue(data)
    dirtyPlates[data] = true
    if batchDepth == 0 and not data.flushing then FlushPlate(data) end
end

-- What changed for the values: "health", "power", "threat", "cast", "target" (the unit's target),
-- "targeted" (whether it is yours), "all", or nil (templates and graphics). Values feed rules, and
-- both can change what shows. data.reads (TemplateReaders.PlateReads) says which kinds the plate's
-- custom parts and rules read: a kind nothing reads marks nothing, and only the pass that reads it
-- runs. data.dirtyKinds collects the kinds for the values pass.
local function MarkValues(data, kind)
    local reads = data.reads
    local values, rules = true, true
    if reads and kind and kind ~= "all" then
        values, rules = reads.values[kind] == true, reads.rules[kind] == true
        if not (values or rules) then return end
        -- A render can write a colour a rule set (the lead's state colour): the rules go on top again.
        if values and (reads.anyRules or data.ruleRegions) then rules = true end
    end
    if values then
        data.dirtyValues = true
        local kinds = data.dirtyKinds
        if not kinds then
            kinds = {}
            data.dirtyKinds = kinds
        end
        kinds[kind or "any"] = true
    end
    if rules then data.dirtyRules = true end
    data.dirtyVisibility, data.dirtyMeasure = true, true
    Queue(data)
end

local function MarkRules(data)
    data.dirtyRules, data.dirtyVisibility = true, true
    Queue(data)
end

-- A part showed or hid, or its text changed: stacks may close up or open, and pinned parts follow.
local function MarkStacks(data)
    data.dirtyStacks, data.dirtyMeasure, data.dirtyVisibility = true, true, true
    Queue(data)
end

local function MarkVisibility(data)
    data.dirtyVisibility = true
    Queue(data)
end

local function ClearKinds(data)
    local kinds = data.dirtyKinds
    if kinds then for kind in pairs(kinds) do kinds[kind] = nil end end
end

local function ClearDirty(data)
    data.dirtyValues, data.dirtyRules, data.dirtyStacks, data.dirtyMeasure, data.dirtyVisibility = false, false, false, false, false
    ClearKinds(data)
    dirtyPlates[data] = nil
end

local function FlushDirty()
    -- Bounded: a flush can queue its own plate again (a hook fired by what it showed).
    for _ = 1, 400 do
        local data = next(dirtyPlates)
        if not data then return end
        FlushPlate(data)
    end
end

-- Runs fn(a, b) as one batch; the outermost batch flushes unless defer (the frame ticker will).
local function RunBatch(defer, fn, a, b)
    counters.batches = counters.batches + 1
    batchDepth = batchDepth + 1
    local ok, reason = pcall(fn, a, b)
    batchDepth = batchDepth - 1
    if batchDepth <= 0 then
        batchDepth = 0
        if not defer then FlushDirty() end
    end
    if not ok then error(reason, 0) end
end

-- Round-robin lists of plates (the state pass, the native backstop): each plate keeps its index
-- under key, and removal swaps the last plate in, so both are O(1).
local function ListSet(list, data, key, wanted)
    local index = data[key]
    if wanted then
        if not index then
            list[#list + 1] = data
            data[key] = #list
        end
    elseif index then
        local last = list[#list]
        list[index], last[key] = last, index
        list[#list] = nil
        data[key] = nil
    end
end

-- pulses: plates whose target halo pulses (the animation entry runs only while one does or a
-- spotlight dims other plates).
local rounds = { state = {}, native = {}, stateCursor = 0, nativeCursor = 0, clock = 0, targetDueAt = 0, pulses = {} }
-- Calls of the hooks on Blizzard's plate frames (Diagnostics/Performance.lua reports them).
rounds.untimed = PS.Performance and PS.Performance.untimed or { hooks = 0 }
-- The range pass (Nameplates/Range.lua): each checked plate's data.inRange, while a layout reads it.
rounds.range = assert(PS._CreatePlateRange, "PlateSmith PlateRange missing")({
    active = active, MarkValues = MarkValues, RunBatch = RunBatch,
})

local function RegionVisibleState(region)
    if not region or type(region.IsVisible) ~= "function" then return "unavailable" end
    local ok, visible = pcall(region.IsVisible, region)
    if not ok then return "error" end
    if not IsReadable(visible) then return "protected" end
    return visible == true
end

local function OwnsAppearance()
    if db.mode == "own" then return true end
    if db.mode == "overlay" then return false end
    return PS.Conflicts.CachedProvider() == nil
end

-- friendly: the unit's friendliness (rounds.Friendly), read once by the caller.
local function RestrictedFriendly(friendly)
    return friendly == true and NamePolicy.InGroupInstance()
end

-- Whether unit is friendly to the player: UnitIsFriend, else (the client keeps it private, as for a
-- hostile player not flagged for PvP) a readable UnitReaction, 3 or less hostile and 5 or more friendly.
-- Neutral (4) or nothing readable is nil: the plate is left to Blizzard.
function rounds.Friendly(unit)
    local friendly = Secret.ReadBoolean(UnitIsFriend, "player", unit)
    if friendly ~= nil or type(UnitReaction) ~= "function" then return friendly end
    local ok, reaction = pcall(UnitReaction, unit, "player")
    if not ok or not IsReadable(reaction) or type(reaction) ~= "number" then return nil end
    if reaction <= 3 then return false end
    if reaction >= 5 then return true end
    return nil
end

local function GetSettings() return db end

local PlateIdentity = assert(PS._CreatePlateIdentity, "PlateSmith PlateIdentity missing")({
    GetSettings = GetSettings,
})
local UnitDisplayNameValue = PlateIdentity.UnitDisplayNameValue
local SafeColourForUnit = PlateIdentity.SafeColourForUnit

-- Aura work is proportional to plates that show a row: UpdateAuras reads nothing for a plate whose
-- rows are off, UNIT_AURA is ignored for it (data.aurasWanted), and the slow pass visits only plates
-- with a timed or unsettled row (auraWork.polls), switching itself off when there are none.
-- auraWork.containers: native aura containers made ahead (Auras.lua's pool), built by the spares entry.
-- auraWork.pending/order: plates whose rows are read in the frame's aura round (auraWork.Run), oldest
-- first: a UNIT_AURA's, and a timed add's own aura pass (deferring, set by adds.Now), which waits for
-- that round so the add draws the name and bars at once and its auras a frame or so later.
local auraWork = { ticker = "plates.auras", polls = {}, pending = {}, order = {}, tickerOn = true, deferring = false,
    frame = 0 }
local AURA_ICON_COUNT, CreateAuraRow, UpdateAuras, AurasNeedPoll, AurasPolled
-- auraWork.Reserve: a timed add's rows shown ahead (Auras.lua's ReserveRows).
AURA_ICON_COUNT, CreateAuraRow, UpdateAuras, AurasNeedPoll, AurasPolled, auraWork.Reserve =
    assert(PS._CreatePlateAuras, "PlateSmith PlateAuras missing")({ GetSettings = GetSettings, Counters = counters,
    Work = auraWork, PoolTaken = function() PS.Ticker.SetEnabled("plates.spares", true) end })
local function UpdatePlateAuras(data)
    -- data.auraOnly: one row of a pass the aura round split (auraWork.Read).
    local wanted = UpdateAuras(data, data.auraOnly)
    data.aurasWanted = wanted
    if wanted and AurasPolled(data) then
        auraWork.polls[data] = true
        if not auraWork.tickerOn then
            auraWork.tickerOn = true
            PS.Ticker.SetEnabled(auraWork.ticker, true)
        end
    else
        auraWork.polls[data] = nil
    end
end

-- The plate's rows are read in the frame's aura round, once however often it is queued.
-- data.auraQueuedFrame: the frame (auraWork.frame, counted by adds.Frame) it was queued in.
function auraWork.Queue(data)
    if auraWork.pending[data] then
        -- The second half of a split pass (auraWork.Read) is waiting: what queued it again may have
        -- changed the half already read, so the plate's whole pass runs instead.
        data.auraRowsLeft = nil
        return
    end
    auraWork.pending[data] = true
    auraWork.order[#auraWork.order + 1] = data
    data.auraQueuedFrame = auraWork.frame
end

-- The oldest waiting aura pass has waited AURA_WAIT_FRAMES frames: frames full of adds kept it back,
-- so the next frame's first plate work is the aura round's (adds wait a frame instead).
local AURA_WAIT_FRAMES = 2
function auraWork.Starving()
    -- Without a profiler clock nothing is budgeted, so nothing waits.
    if type(debugprofilestop) ~= "function" then return false end
    local order = auraWork.order
    for index = 1, #order do
        local data = order[index]
        if auraWork.pending[data] then return auraWork.frame - (data.auraQueuedFrame or auraWork.frame) >= AURA_WAIT_FRAMES end
    end
    return false
end

-- The plate's frames (Factory.lua): CreatePlate, the parts made on first use, and the plate font.
local PlateParts = assert(PS._CreatePlateFactory,
    "PlateSmith PlateFactory missing")({ CreateAuraRow = CreateAuraRow, GetSettings = GetSettings })
local ApplyNameplateFont = PlateParts.ApplyNameplateFont

-- Spares: plates built ahead (the "plates.spares" entry: out of combat, in a frame with no plate
-- adds, half a plate a pass) for nameplates the client has not made yet, so the add of a new
-- nameplate (a camera turn or a pull showing more plates than ever before) attaches one instead of
-- building. PlateParts.attached: nameplates given a plate this session (a root keeps its plate);
-- partial: a plate with only its first half built, never taken; the spares entry and a waiting add's
-- build (adds.Half) both finish it. warmUntil: GetTime until which the target is raised (Warm); churn,
-- churnAt: adds counted since churnAt (Churn).
PlateParts.spares, PlateParts.warmAt, PlateParts.attached = {}, math.huge, 0
PlateParts.warmUntil, PlateParts.churn, PlateParts.churnAt = 0, 0, 0
function PlateParts.TakeSpare(root)
    local spares = PlateParts.spares
    local data = spares[#spares]
    if not data then return nil end
    spares[#spares] = nil
    PlateParts.AttachPlate(data, root)
    -- A plate an add built for itself (adds.Half) waits here only until that add takes it.
    if data.builtLive then
        data.builtLive = nil
    else
        counters.sparesUsed = counters.sparesUsed + 1
    end
    if not PS.Ticker.IsEnabled("plates.spares") then PS.Ticker.SetEnabled("plates.spares", true) end
    return data
end

-- Half a plate (Factory's StartPlate, or FinishPlate on the partial one), so no frame builds a whole
-- one. Returns true when a plate was finished: it waits in spares.
function PlateParts.BuildHalf()
    local partial = PlateParts.partial
    if not partial then
        PlateParts.partial = PlateParts.StartPlate(nil)
        return false
    end
    PlateParts.partial = nil
    local spares = PlateParts.spares
    spares[#spares + 1] = PlateParts.FinishPlate(partial)
    return true
end

-- A nameplate got its plate: the most this client has had at once is kept in the account state
-- (platePeak), so the next session builds that many ahead. (In a crowd the target grows with it: the
-- spare taken, or the last one before a build, switched the spares entry on.)
function PlateParts.Attached()
    local count = PlateParts.attached + 1
    PlateParts.attached = count
    local state = PS.GetState and PS.GetState()
    if state and (type(state.platePeak) ~= "number" or count > state.platePeak) then state.platePeak = count end
end

-- How many plates (attached and spare) to have ready: the stored peak up to SPARE_MAX (built ahead
-- next session), and in a crowd SPARE_PLATES more than are attached up to SPARE_CROWD (a city's
-- client keeps making nameplates as players stream in, each a 7 ms build without a spare); at least
-- SPARE_PLATES. Warmed (Warm), the peak or the plates attached, whichever is more, plus SPARE_WARM, up to
-- SPARE_CROWD: built before a city's or a flight's nameplates arrive, so their adds take spares.
function PlateParts.SpareTarget(now)
    local state = PS.GetState and PS.GetState()
    local peak = state and type(state.platePeak) == "number" and state.platePeak or 0
    local target = math.max(LIMITS.SPARE_PLATES, math.min(peak, LIMITS.SPARE_MAX),
        math.min(PlateParts.attached + LIMITS.SPARE_PLATES, LIMITS.SPARE_CROWD))
    now = now or (type(GetTime) == "function" and GetTime() or 0)
    if now < PlateParts.warmUntil then
        target = math.max(target, math.min(math.max(peak, PlateParts.attached) + LIMITS.SPARE_WARM, LIMITS.SPARE_CROWD))
    end
    return target
end

-- Raises the target for SPARE_WARM_SECONDS (out of combat only: spares are never built in combat).
function PlateParts.Warm(now)
    if Secret.InCombat() then return end
    if now >= PlateParts.warmUntil then counters.sparesWarmed = counters.sparesWarmed + 1 end
    PlateParts.warmUntil = now + LIMITS.SPARE_WARM_SECONDS
    if not PS.Ticker.IsEnabled("plates.spares") then PS.Ticker.SetEnabled("plates.spares", true) end
end

-- Counts a plate add (adds.Request): SPARE_CHURN_ADDS within SPARE_CHURN_SECONDS warm the spares. A flight
-- or a mount arriving in a city brings its nameplates within seconds.
function PlateParts.Churn()
    local now = type(GetTime) == "function" and GetTime() or 0
    if now - PlateParts.churnAt > LIMITS.SPARE_CHURN_SECONDS then PlateParts.churnAt, PlateParts.churn = now, 0 end
    PlateParts.churn = PlateParts.churn + 1
    if PlateParts.churn >= LIMITS.SPARE_CHURN_ADDS then
        PlateParts.churnAt, PlateParts.churn = now, 0
        PlateParts.Warm(now)
    end
end

-- /ps diagnose's performance.spares: spares built ahead and taken, plates built for adds (two halves
-- each, one a frame), how many wait now, the target, whether it is warmed and how often it was.
function PlateParts.Report()
    local now = type(GetTime) == "function" and GetTime() or 0
    return { builtAhead = counters.sparesBuilt, used = counters.sparesUsed, builtForAdds = counters.platesBuilt,
        buildHalves = counters.buildHalves, waiting = #PlateParts.spares, attached = PlateParts.attached,
        target = PlateParts.SpareTarget(now), warm = now < PlateParts.warmUntil, warmed = counters.sparesWarmed }
end
if PS.Performance then PS.Performance.SpareFigures = PlateParts.Report end

-- Spares are built again SPARE_DELAY after login or a loading screen.
function PlateParts.WarmLater()
    PlateParts.warmAt = (type(GetTime) == "function" and GetTime() or 0) + LIMITS.SPARE_DELAY
    PS.Ticker.SetEnabled("plates.spares", true)
end

local Styles = assert(PS._CreatePlateStyles, "PlateSmith PlateStyles missing")({
    GetSettings = GetSettings, ApplyNameplateFont = ApplyNameplateFont,
})
local VALUE_KEYS, EMPTY = Styles.VALUE_KEYS, Styles.EMPTY

local Readers = assert(PS._CreateTemplateReaders, "PlateSmith TemplateReaders missing")({
    UnitDisplayNameValue = UnitDisplayNameValue, FriendlyRelationship = PlateIdentity.FriendlyRelationship,
})
local IsDisplayNumber = Readers.IsDisplayNumber

-- Blizzard's plate and its aura frames. The aura frames can ignore their parent's alpha,
-- so hiding the unit frame alone leaves Blizzard's own debuff icons drawn over ours.
local NATIVE_AURA_KEYS = { "AurasFrame", "BuffFrame", "DebuffFrame" }
local NATIVE_AURA_LISTS = { "DebuffListFrame", "BuffListFrame", "CrowdControlListFrame", "LossOfControlFrame" }

-- The plate's native frames, gathered into its own list (reused) whenever it is hidden again.
local function CollectNativeFrames(data)
    local frames = data.nativeFrames or {}
    data.nativeFrames = frames
    for index = #frames, 1, -1 do frames[index] = nil end
    local root = data.root
    local native = root and root.UnitFrame
    if not native then return frames end
    if native.SetAlpha then frames[1] = native end
    for pass = 1, 2 do
        local owner = pass == 1 and native or root
        for _, key in ipairs(NATIVE_AURA_KEYS) do
            local frame = type(owner) == "table" and owner[key]
            if type(frame) == "table" and frame.SetAlpha then frames[#frames + 1] = frame end
        end
    end
    -- The aura lists inside it are anchored to the health bar and can ignore their parent's
    -- alpha, so each is hidden too.
    local auras = native.AurasFrame
    for _, key in ipairs(NATIVE_AURA_LISTS) do
        local frame = type(auras) == "table" and auras[key]
        if type(frame) == "table" and frame.SetAlpha then frames[#frames + 1] = frame end
    end
    return frames
end

-- The hooks below put these back at once; a slow ticker pass covers anything they miss.
local function KeepNativeHidden(data)
    local frames = data.nativeFrames
    if not frames then return end
    for index = 1, #frames do rounds.OwnAlpha(frames[index], 0) end
end

-- The hooks read whether to hide from the frame itself (platesmithNativeHidden), not from the record
-- that hooked it, so a waiting add's stand-in record (adds.Hold) and the plate that takes over from it
-- share them. rounds.untimed counts Blizzard's calls only: PlateSmith's own alpha writes (OwnAlpha) go
-- through the SetAlpha hook too, and are skipped there (rounds.ownAlpha), so they neither count nor
-- recurse. pcall: a flag left set would stop the hook putting Blizzard's alphas back.
function rounds.OwnAlpha(frame, alpha)
    rounds.ownAlpha = true
    pcall(frame.SetAlpha, frame, alpha)
    rounds.ownAlpha = false
end
function rounds.NativeOnShow(instance)
    rounds.untimed.hooks = rounds.untimed.hooks + 1
    if instance.platesmithNativeHidden and instance.SetAlpha then rounds.OwnAlpha(instance, 0) end
end
function rounds.NativeSetAlpha(instance, alpha)
    if rounds.ownAlpha then return end
    rounds.untimed.hooks = rounds.untimed.hooks + 1
    if instance.platesmithNativeHidden and IsReadable(alpha) and type(alpha) == "number" and alpha > 0 then
        rounds.OwnAlpha(instance, 0)
    end
end

local function HideNative(data)
    data.nativeAlphas = data.nativeAlphas or {}
    local frames = CollectNativeFrames(data)
    for index = 1, #frames do
        local frame = frames[index]
        if data.nativeAlphas[frame] == nil and frame.GetAlpha then
            -- A frame a waiting add hid already (adds.Hold) keeps the alpha it had before that.
            local alpha
            if frame.platesmithNativeHidden and frame.platesmithNativeAlphaKept then
                alpha = frame.platesmithNativeAlpha
            else
                alpha = frame:GetAlpha()
            end
            data.nativeAlphas[frame], frame.platesmithNativeAlpha, frame.platesmithNativeAlphaKept = alpha, alpha, true
        end
        frame.platesmithNativeHidden = true
        if not frame.platesmithHideHooked and frame.HookScript then
            -- Blizzard's code calls these, outside any timed handler: counted (performance.frames) so the
            -- client profiler's larger figure can be told apart from PlateSmith's timed work.
            frame:HookScript("OnShow", rounds.NativeOnShow)
            -- Blizzard's plate code sets these alphas itself (target and selection changes, and its
            -- distance fade every frame while the camera turns); put them straight back rather than
            -- wait for the ticker, which showed as a flash. O(1): our own SetAlpha(0) re-enters
            -- flagged (rounds.OwnAlpha) and stops there, so the hook cannot recurse.
            if type(hooksecurefunc) == "function" then hooksecurefunc(frame, "SetAlpha", rounds.NativeSetAlpha) end
            frame.platesmithHideHooked = true
        end
    end
    data.hideNative = true
    ListSet(rounds.native, data, "nativeIndex", true)
    KeepNativeHidden(data)
end

local function RestoreNative(data)
    data.hideNative = false
    ListSet(rounds.native, data, "nativeIndex", false)
    for frame in pairs(data.nativeAlphas or EMPTY) do
        frame.platesmithNativeHidden, frame.platesmithNativeAlpha, frame.platesmithNativeAlphaKept = nil, nil, nil
    end
    for _, frame in ipairs(data.nativeFrames or EMPTY) do frame.platesmithNativeHidden = nil end
    for frame, alpha in pairs(data.nativeAlphas or EMPTY) do
        if frame.SetAlpha then rounds.OwnAlpha(frame, alpha) end
    end
end

local QuestRelevance = PS.QuestProgress.Relevance

local function ThreatRecord(unit, refresh)
    local service = PS.ThreatService
    if not service then return nil end
    if refresh and type(service.RefreshUnit) == "function" then
        return service:RefreshUnit(unit)
    end
    if type(service.GetEnemy) == "function" then return service:GetEnemy(unit) end
end

-- The client's duration object for a cast whose times are protected (newer clients): its time
-- left goes straight to SetFormattedText. nil when the client has none.
local function CastDuration(unit, channel)
    local api
    if channel then api = UnitChannelDuration else api = UnitCastingDuration end
    if type(api) ~= "function" then return nil end
    local ok, duration = pcall(api, unit)
    if ok and IsReadable(duration) and type(duration) == "table"
        and type(duration.GetRemainingDuration) == "function" then
        return duration
    end
end

-- The cast's time left, one decimal, counting down for casts and channels alike. Readable times
-- are written when the tenth changes; a protected duration goes to the sink as it is, every
-- 0.1 s. Neither: the time hides (it is never worked out from protected values).
local function UpdateCastTime(data, now)
    local text = data.castTime
    if not data.castTimeWanted then
        text:Hide()
        return
    end
    local endMS = data.castEndMS
    if endMS then
        local tenths = math.max(0, math.floor((endMS - now * 1000) / 100))
        if tenths ~= data.castTimeTenths then
            data.castTimeTenths = tenths
            text:SetFormattedText("%.1f", tenths / 10)
        end
        text:Show()
        return
    end
    local duration = data.castDuration
    if duration then
        if data.castTimeAt and now < data.castTimeAt then return end
        data.castTimeAt = now + 0.1
        local ok, remaining = pcall(duration.GetRemainingDuration, duration)
        if ok and HasValue(remaining) and pcall(text.SetFormattedText, text, "%.1f", remaining) then
            text:Show()
            return
        end
    end
    text:SetText("")
    text:Hide()
end

local function ApplyCastInfo(data, channel)
    local api = channel and UnitChannelInfo or UnitCastingInfo
    if type(api) ~= "function" then return false end
    local ok, name, _, texture, startMS, endMS, _, seventh, eighth = pcall(api, data.unit)
    if not ok or not HasValue(name) then return false end
    -- For templates and rules: the spell's name, and whether it can be interrupted (a channel
    -- reports that seventh, a cast eighth; kept as given for Colour by interrupt's sink).
    data.castSpell = name
    local notInterruptible
    if channel then notInterruptible = seventh else notInterruptible = eighth end
    data.castInterruptible = IsReadable(notInterruptible) and notInterruptible ~= true or nil
    data.castNotInterruptible = notInterruptible

    local readableTimes = IsReadable(startMS) and IsReadable(endMS)
    if readableTimes and (type(startMS) ~= "number" or type(endMS) ~= "number") then return false end
    if not readableTimes and not (HasValue(startMS) and HasValue(endMS)) then return false end
    local cast = data.cast
    if not pcall(cast.SetMinMaxValues, cast, startMS, endMS) then return false end
    cast:SetValue(GetTime() * 1000)
    cast:SetReverseFill(channel and true or false)
    if not pcall(data.castName.SetText, data.castName, name) then data.castName:SetText("") end
    local profile, icon = data.profile, data.castIcon
    data.castHidden = nil
    if profile.castIcon ~= "off" and HasValue(texture) and pcall(icon.SetTexture, icon, texture) then
        icon:Show()
    else
        icon:Hide()
    end
    data.castTimeWanted = profile.castTime ~= false
    data.castEndMS = readableTimes and endMS or nil
    data.castDuration = not readableTimes and data.castTimeWanted and CastDuration(data.unit, channel) or nil
    data.castTimeTenths, data.castTimeAt = nil, nil
    UpdateCastTime(data, GetTime())
    cast:Show()
    data.casting, data.castChannel = true, channel and true or false
    activeCasts[data] = true
    -- Colour by interrupt watches the interrupt while this cast lasts; castOnTop raises the plate.
    if PS.Interrupt then PS.Interrupt.Watch(data, profile.castInterruptColours == true) end
    PS.Stacking.PlateCasting(data, profile.castOnTop == true)
    Styles.CastColour(data)
    return true
end

-- data.castHidden: HideCast hid the bar, its icon and time, and nothing has shown them since (only
-- ApplyCastInfo and the time it starts do, and ApplyCastInfo clears it first).
local function HideCast(data)
    if not data.castHidden then
        data.cast:Hide()
        data.castIcon:Hide()
        data.castTime:Hide()
        data.castHidden = true
    end
    data.castEndMS, data.castDuration, data.castTimeTenths, data.castNotInterruptible = nil, nil, nil, nil
    data.casting = false
    activeCasts[data] = nil
    if PS.Interrupt then PS.Interrupt.Watch(data, false) end
    PS.Stacking.PlateCasting(data, false)
end

-- Everything an owned plate draws outside its overlay, plus the bars that come and go.
local function HideOwnedParts(data)
    HideCast(data)
    if data.combo then data.combo:Hide() end
    rounds.targetedBy.Release(data)
    data.buffs:Hide()
    data.debuffs:Hide()
    data.power:Hide()
    -- valuesCleared: the flush already hid every custom part (names-only).
    if not data.valuesCleared then
        for _, value in pairs(data.values) do value:Hide() end
    end
end

local UpdateValueAnchors -- (below)

-- Value text can anchor to the cast bar, and templates read the cast. A names-only plate can show
-- its cast slim under its name (Placement's NameCast).
local function UpdateCast(data)
    local slim = rounds.nameCast.Wanted(data)
    if slim ~= (data.nameCast == true) then
        rounds.SetNameCast(data, slim)
    elseif slim then
        rounds.nameCast.Place(data)
    end
    if not data.own or (data.restrictedFriendly and not data.restrictedOverlayEnabled)
        or (not slim and (data.namesOnly or data.layout.cast.visible == false)) then
        HideCast(data)
    elseif not ApplyCastInfo(data, false) and not ApplyCastInfo(data, true) then
        HideCast(data)
    end
    MarkStacks(data)
    UpdateValueAnchors(data)
    MarkValues(data, "cast")
end

-- A cast's times moved (UNIT_SPELLCAST_DELAYED, CHANNEL_UPDATE): only the bar's range and the time
-- follow; the spell, its icon and what reads the cast are unchanged. Anything else is a new cast.
local function UpdateCastTiming(data)
    if not data.casting then return UpdateCast(data) end
    local channel = data.castChannel
    local api = channel and UnitChannelInfo or UnitCastingInfo
    if type(api) ~= "function" then return UpdateCast(data) end
    local ok, name, _, _, startMS, endMS = pcall(api, data.unit)
    if not ok or not HasValue(name) then return UpdateCast(data) end
    local readableTimes = IsReadable(startMS) and IsReadable(endMS)
    if readableTimes and (type(startMS) ~= "number" or type(endMS) ~= "number") then return UpdateCast(data) end
    if not readableTimes and not (HasValue(startMS) and HasValue(endMS)) then return UpdateCast(data) end
    local cast = data.cast
    if not pcall(cast.SetMinMaxValues, cast, startMS, endMS) then return UpdateCast(data) end
    cast:SetValue(GetTime() * 1000)
    data.castEndMS = readableTimes and endMS or nil
    data.castDuration = not readableTimes and data.castTimeWanted and CastDuration(data.unit, channel) or nil
    data.castTimeTenths, data.castTimeAt = nil, nil
    UpdateCastTime(data, GetTime())
end

-- Questie draws its own quest icons on nameplates when its "nameplate icons" option is on;
-- then PlateSmith's step aside (Automatic), or always (Questie's), so a plate never shows two.
local function QuestieNameplateOption(questie)
    return questie.db and questie.db.profile and questie.db.profile.nameplateEnabled
end

local function QuestieShowsIcons()
    local questie = rawget(_G, "Questie")
    if type(questie) ~= "table" then return false end
    local ok, enabled = pcall(QuestieNameplateOption, questie)
    return ok and enabled == true
end

local function QuestIconsDeferred()
    if db.questIcons == "platesmith" then return false end
    if db.questIcons == "questie" then return type(rawget(_G, "Questie")) == "table" end
    return QuestieShowsIcons()
end
PS.QuestIconsDeferred = QuestIconsDeferred

-- Bumped by every settings refresh: a plate laid out at the current revision for the same layout
-- table (profile and variant) keeps its appearance and placement when its frame is reused.
local settingsRevision = 1

-- What the profile's layouts need at all (Schema's ThreatNeeded and QuestNeeded), worked out once
-- per settings revision, so hot paths read two booleans: nothing asks for threat or quests while
-- no layout shows or reads them.
local plateNeeds = { revision = 0, threat = true, quest = true, questProgress = false, range = false, combo = false,
    targetedBy = false }
local function PlateNeeds()
    if plateNeeds.revision ~= settingsRevision and db then
        plateNeeds.revision = settingsRevision
        plateNeeds.threat = S.ThreatNeeded(db)
        plateNeeds.quest = S.QuestNeeded(db)
        plateNeeds.questProgress = S.QuestProgressNeeded(db)
        plateNeeds.range = S.RangeNeeded(db)
        plateNeeds.combo = S.ComboNeeded(db)
        plateNeeds.targetedBy = S.TargetedByNeeded(db)
    end
    return plateNeeds
end

-- Returns whether the marker's shown state changed. A friendly player is never part of a quest, so
-- the quest APIs and providers are not asked about one.
local function UpdateQuest(data)
    local wasShown = data.quest:IsShown() or data.questLoot:IsShown()
    local related, source, detail, questID, objective = false, "none", nil, nil, nil
    if data.profileKey ~= "friendlyPlayer" and PlateNeeds().quest then
        related, source, detail, questID, objective = QuestRelevance(data.unit)
    end
    -- The objective's progress (Nameplates/QuestProgress.lua), read only while something shows it.
    if PS.QuestProgress.Update(data, related, questID, objective, PlateNeeds().questProgress) then
        MarkValues(data, "quest")
    end
    data.questSource = source
    data.questDetail = detail
    data.questRelated = related and true or false
    local itemDrop = related and PS.QuestProgress.IsItemDrop(source) or false
    data.questItemDrop = itemDrop
    local shown = related and not QuestIconsDeferred()
    data.quest:SetShown(shown and not itemDrop and data.layout.quest.visible ~= false)
    -- One marker, two looks: the quest mark, or the loot bag when the unit drops a quest item.
    data.questLoot:SetShown(shown and itemDrop and data.layout.quest.visible ~= false)
    local nowShown = data.quest:IsShown() or data.questLoot:IsShown()
    PS.QuestProgress.Display(data, nowShown)
    return nowShown ~= wasShown
end

-- Plates whose TAGGED can show (enemy plates with the part on).
local function TaggedWanted(data)
    return data.own and data.friendly == false and not data.namesOnly
        and data.layout.tagged.visible ~= false or false
end

local function UpdateTaggedState(data)
    local shown = false
    if TaggedWanted(data) then shown = Secret.ReadBoolean(UnitIsTapDenied, data.unit) == true end
    local changed = data.taggedShown ~= shown
    if changed then data.tagged:SetShown(shown) end
    data.taggedShown = shown
    return changed
end

-- Rules and stacks follow only a change.
local function UpdateTagged(data)
    if UpdateTaggedState(data) then
        MarkRules(data)
        MarkStacks(data)
    end
end

local relationshipTextures = {
    group = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
    guild = "Interface\\GuildFrame\\GuildLogo-NoLogoSm",
}

local function UpdateRelationshipIcon(data)
    if not data.own or data.profileKey ~= "friendlyPlayer"
        or data.layout.relationshipIcon.visible == false then
        data.relationshipIcon:Hide()
        return
    end
    local relationship = data.relationship
    local enabled = (relationship == "group" and db.showGroupIcon)
        or (relationship == "guild" and db.showGuildIcon)
    local texture = enabled and relationshipTextures[relationship] or nil
    if not texture then
        data.relationshipIcon:Hide()
        return
    end
    data.relationshipIcon:SetTexture(texture)
    data.relationshipIcon:Show()
end

local pvpTextures = {
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    FFA = "Interface\\TargetingFrame\\UI-PVP-FFA",
}

-- Returns whether the mark changed (data.pvpState: its texture or "none"; nil after a layout).
local function UpdatePvPIcon(data)
    local texture
    if data.own and data.profileKey == "friendlyPlayer" and data.layout.pvpIcon.visible ~= false
        and (db.friendlyPvpStyle == "icon" or db.friendlyPvpStyle == "both") then
        texture = pvpTextures[PlateIdentity.FriendlyPvPState(data.unit)]
    end
    local state = texture or "none"
    if data.pvpState == state then return false end
    data.pvpState = state
    if texture then
        data.pvpIcon:SetTexture(texture)
        data.pvpIcon:Show()
    else
        data.pvpIcon:Hide()
    end
    return true
end

local function UpdateClassification(data)
    if not data.own or data.friendly ~= false
        or data.layout.classification.visible == false or type(UnitClassification) ~= "function" then
        data.classification:Hide()
        data.classificationIcon:Hide()
        return
    end
    local ok, kind = pcall(UnitClassification, data.unit)
    PS.ApplyClassificationMark(data.classification, data.classificationIcon,
        ok and IsReadable(kind) and kind or nil, db.classificationStyle)
end

-- Target of target: the name of whoever this unit targets, coloured by class. In dungeons the
-- client protects whether the target exists and who it is, but still hands its name and class to
-- the text and colour sinks: then the name (possibly protected) goes straight to SetText and the
-- class through C_ClassColor (Secret.SetClassTextColour). Hidden when there is known to be no
-- target or no name, and (by default) while the target is known to be you.
local TARGET_NAME_COLOUR = { 0.85, 0.85, 0.95 }
local function UpdateTargetName(data)
    local region = data.targetName
    if not region then return end
    local position = data.layout and data.layout.targetName
    local target = data.targetUnit
    if not data.own or not position or position.visible == false or position.removed
        or not target or Secret.ReadBoolean(UnitExists, target) == false
        or (db.targetNameHideSelf and SameUnit(target, "player")) then
        region:Hide()
        return
    end
    local displayName = UnitDisplayNameValue(target)
    if HasValue(displayName) and not (Secret.IsReadable(displayName) and displayName == "")
        and pcall(region.SetText, region, displayName) then
        -- A rule's colour holds over the class colour (Styles.RuleColour).
        if not region.plateSmithRuleColour then
            local classFile, hasClass = Secret.ClassFile(target)
            if not (hasClass and Secret.SetClassTextColour(region, classFile)) then
                region:SetTextColor(TARGET_NAME_COLOUR[1], TARGET_NAME_COLOUR[2], TARGET_NAME_COLOUR[3])
            end
        end
        region:Show()
    else
        region:Hide()
    end
end

-- The unit's level: "??" for a level the client hides (-1); a protected level goes to the sink.
local function ApplyLevelText(region, unit)
    local ok, level = pcall(UnitLevel, unit)
    local SetPlateText = PlateIdentity.SetPlateText
    if ok and IsReadable(level) and type(level) == "number" then
        SetPlateText(region, level < 0 and "??" or level)
    elseif not (ok and HasValue(level) and SetPlateText(region, level)) then
        SetPlateText(region, "")
    end
end

-- The unit's relationship to the player (group, guild, friend, recent), read once per identity
-- update and kept on the plate: the colour, the icon and social updates share it.
local function ReadRelationship(data)
    if not data.friendly or data.profileKey ~= "friendlyPlayer" then return nil end
    return PlateIdentity.FriendlyRelationship(data.unit)
end

-- Identity follows its events (added, UNIT_NAME_UPDATE, UNIT_LEVEL, UNIT_FACTION, social updates),
-- never the ticker.
local function UpdateIdentity(data)
    counters.updateIdentity = counters.updateIdentity + 1
    local started, nested = addPhases.Start()
    local unit = data.unit
    data.relationship = ReadRelationship(data)
    local displayName = UnitDisplayNameValue(unit)
    local SetPlateText = PlateIdentity.SetPlateText
    -- /ps testname: typed text (a plain string) in the unit's name's place until cleared (rounds.SetTestName).
    if data.testName then
        SetPlateText(data.name, data.testName)
    elseif not (HasValue(displayName) and SetPlateText(data.name, displayName)) then
        SetPlateText(data.name, "")
    end
    ApplyLevelText(data.level, unit)
    -- The guild line: written only when the guild differs from the one shown (plateSmithGuild).
    local guild, guildName = data.guild, nil
    if data.own and data.profileKey == "friendlyPlayer" and data.layout.guild.visible ~= false
        and type(GetGuildInfo) == "function" then
        local ok, name = pcall(GetGuildInfo, unit)
        if ok and IsReadable(name) and type(name) == "string" and name ~= "" then guildName = name end
    end
    if guildName and guild.plateSmithGuild ~= guildName then
        guild:SetFormattedText("<%s>", guildName)
        guild.plateSmithGuild = guildName
    end
    guild:SetShown(guildName ~= nil)
    local r, g, b = SafeColourForUnit(unit, data.friendly, data.relationship, data.profileKey == "friendlyPlayer")
    data.name:SetTextColor(r, g, b)
    if data.profile.healthColourMode == "custom" then
        local colour = data.profile.healthColour
        data.health:SetStatusBarColor(colour.r, colour.g, colour.b)
    else
        data.health:SetStatusBarColor(r, g, b)
    end
    local questStarted, questNested = addPhases.Start()
    UpdateQuest(data)
    addPhases.Stop("quest", questStarted, questNested)
    UpdateRelationshipIcon(data)
    UpdatePvPIcon(data)
    UpdateClassification(data)
    UpdateTargetName(data)
    MarkRules(data)
    MarkStacks(data)
    addPhases.Stop("text", started, nested)
end

local function UpdateRaidIcon(data)
    RaidMarker.Update(data)
    MarkStacks(data)
end


-- Where parts are drawn, and the custom parts' rendering (Placement.lua, Values.lua).
local Placement = assert(PS._CreatePlatePlacement, "PlateSmith PlatePlacement missing")({
    Styles = Styles, MarkVisibility = MarkVisibility, Counters = counters,
    GetSettings = GetSettings, ApplyNameplateFont = ApplyNameplateFont,
})
local PartRegions, Transforms, SafeSize, ReadNumber = Placement.PartRegions, Placement.Transforms,
    Placement.SafeSize, Secret.ReadNumber
local RegionAlpha = Placement.RegionAlpha
local HasStacks, ReflowStacks = Placement.HasStacks, Placement.ReflowStacks
local ApplyComponentLayout, ApplyParentVisibility = Placement.ApplyComponentLayout, Placement.ApplyParentVisibility
local RestoreParentFaded = Placement.RestoreParentFaded
rounds.nameCast = Placement.NameCast
UpdateValueAnchors = Placement.UpdateValueAnchors
local Values = assert(PS._CreatePlateValues, "PlateSmith PlateValues missing")({
    GetSettings = GetSettings, Readers = Readers, Styles = Styles,
})
local RenderValueSlots, ApplyValueKind = Values.RenderValueSlots, Values.ApplyValueKind
-- Combo points on the target's plate (ComboPoints.lua).
rounds.combo = assert(PS._CreatePlateCombo, "PlateSmith PlateCombo missing")({
    active = active, RunBatch = RunBatch, MarkStacks = MarkStacks, MarkValues = MarkValues, Styles = Styles,
    AnchorPart = Placement.AnchorPart, ApplyNameplateFont = ApplyNameplateFont,
})
-- The target's soft glow (TargetGlow.lua; targetHighlightStyle "glow").
rounds.targetGlow = assert(PS._CreatePlateTargetGlow, "PlateSmith PlateTargetGlow missing")({
    Transforms = Placement.Transforms,
})
-- "Targeted by" badges on enemy plates (TargetedBy.lua).
rounds.targetedBy = assert(PS._CreatePlateTargetedBy, "PlateSmith PlateTargetedBy missing")({
    active = active, RunBatch = RunBatch, MarkStacks = MarkStacks, Styles = Styles,
    AnchorPart = Placement.AnchorPart, ApplyNameplateFont = ApplyNameplateFont,
})

local function UpdateHealth(data)
    if not data.own or data.namesOnly
        or (data.restrictedFriendly and not data.restrictedOverlayEnabled) then return end
    local unit, bar = data.unit, data.health
    local okHealth, health = pcall(UnitHealth, unit)
    local okMax, maximum = pcall(UnitHealthMax, unit)
    local valid = okHealth and okMax
    if valid and IsReadable(health) and IsReadable(maximum) then
        valid = type(health) == "number" and type(maximum) == "number" and maximum > 0
        -- The backstop pass (rounds.backstop): an unchanged readable value draws nothing.
        if valid and rounds.backstop and IsReadable(data.healthValue) and IsReadable(data.healthMaxValue)
            and data.healthValue == health and data.healthMaxValue == maximum then
            return
        end
    elseif valid then
        -- A protected value can still be shown; never compared.
        valid = HasValue(health) and HasValue(maximum)
    end
    if valid then
        local failure
        valid, failure = pcall(bar.SetMinMaxValues, bar, 0, maximum)
        if valid then valid, failure = pcall(bar.SetValue, bar, health) end
        -- A restricted plate whose sink refuses stops drawing (SafePlateUpdate turns it off).
        if not valid and data.restrictedFriendly then error(failure, 0) end
    end
    -- A freshly recycled plate may not have health yet; never keep the previous unit's text.
    if valid then
        data.healthValue, data.healthMaxValue = health, maximum
    else
        data.healthValue, data.healthMaxValue = nil, nil
    end
    -- A new value changes no part's shown state: only what reads health follows (MarkValues).
    if data.valueAnchorsDirty then UpdateValueAnchors(data) end
    MarkValues(data, "health")
end

-- A unit with no power: the client says so readably (maximum 0 or less, or no power type).
-- A protected answer keeps the bar.
local function HasNoPower(unit, maximum)
    if IsReadable(maximum) and type(maximum) == "number" and maximum <= 0 then return true end
    if type(UnitPowerType) ~= "function" then return false end
    local ok, powerType = pcall(UnitPowerType, unit)
    return ok and IsReadable(powerType) and type(powerType) == "number" and powerType < 0
end

local function UpdatePower(data)
    if not data.own or data.namesOnly
        or (data.restrictedFriendly and not data.restrictedOverlayEnabled) then return end
    -- The bar off and nothing reading power: the bar stays hidden (ApplyLayout), nothing to read.
    local reads = data.reads
    if data.layout.power.visible == false and reads and not reads.values.power and not reads.rules.power then return end
    local unit, bar = data.unit, data.power
    local wasShown = bar:IsShown()
    local okPower, power = pcall(UnitPower, unit)
    local okMax, maximum = pcall(UnitPowerMax, unit)
    -- The backstop pass (rounds.backstop): an unchanged readable value draws nothing.
    if rounds.backstop and okPower and okMax and data.powerRead and IsReadable(power) and IsReadable(maximum)
        and IsReadable(data.powerValue) and IsReadable(data.powerMaxValue)
        and data.powerValue == power and data.powerMaxValue == maximum then
        return
    end
    data.powerRead = true
    local shown = okPower and okMax and IsDisplayNumber(power) and IsDisplayNumber(maximum)
        and not HasNoPower(unit, maximum)
        and pcall(bar.SetMinMaxValues, bar, 0, maximum) and pcall(bar.SetValue, bar, power)
    if shown then
        data.powerValue, data.powerMaxValue = power, maximum
        bar:SetShown(data.layout.power.visible ~= false)
    else
        data.powerValue, data.powerMaxValue = nil, nil
        bar:Hide()
    end
    if bar:IsShown() ~= wasShown then MarkStacks(data) end
    MarkValues(data, "power")
end

-- region.plateSmithGlow: the glow strength on the text now (nil: its own shadow), so a repeat of the
-- same glow on a visible text (the target's backstop) writes nothing.
local function ApplyTargetTextGlow(region, original, strength, visibleOnly)
    if not original or (visibleOnly and (region.plateSmithGlow == strength or not region:IsShown())) then return end
    region.plateSmithGlow = strength
    if strength then
        -- A shadow tracks the actual glyphs, including opaque names passed to SetText.
        region:SetShadowColor(1, 0.7, 0.14, strength)
        region:SetShadowOffset(1, -1)
    else
        region:SetShadowColor(original[1], original[2], original[3], original[4])
        region:SetShadowOffset(original[5], original[6])
    end
end

-- data.textGlowing: some text may carry the glow, so taking it down has work to do.
local function SetTargetTextGlow(data, strength, visibleOnly)
    if not strength and not data.textGlowing then return end
    data.textGlowing = strength ~= nil
    for _, region in ipairs(data.targetGlowTexts) do
        ApplyTargetTextGlow(region, data.targetShadowDefaults[region], strength, visibleOnly)
    end
    for _, region in pairs(data.values) do
        ApplyTargetTextGlow(region, data.targetShadowDefaults[region], strength, visibleOnly)
    end
end

-- The health bar's edge: red while a tank is losing this mob, gold on the target, else dark. Set
-- only when that changes.
local ApplyHealthBorder
do
    local BORDER_COLOURS = { warning = { 1, 0.12, 0.08, 1 }, target = { 1, 0.82, 0.12, 1 }, plain = { 0.05, 0.05, 0.05, 1 } }
    -- With Threat colours on the edge, the threat colour (its table is the state) comes first.
    ApplyHealthBorder = function(data)
        local threat = PS.ThreatColours.ForPlate(data, "border")
        if not threat then
            -- Picked inside the client from protected answers: written each time, never compared.
            local folded, r, g, b = PS.ThreatColours.FoldForPlate(data, "border")
            if folded == true and pcall(data.healthBorder.SetBackdropBorderColor, data.healthBorder, r, g, b, 1) then
                data.borderState = "folded"
                return
            end
        end
        local state = "plain"
        if threat then state = threat elseif data.tankWarning then state = "warning" elseif data.targeted then state = "target" end
        if data.borderState == state then return end
        data.borderState = state
        if threat then
            data.healthBorder:SetBackdropBorderColor(threat.r, threat.g, threat.b, 1)
        else
            local colour = BORDER_COLOURS[state]
            data.healthBorder:SetBackdropBorderColor(colour[1], colour[2], colour[3], colour[4])
        end
    end
end

local function UpdateTarget(data)
    local targeted = SameUnit(data.unit, "target")
    -- The plate's own design's highlight (its own values over the general settings).
    local highlight = targeted and data.own and rounds.targetGlow.Highlight(data, db) or nil
    local showHighlight = highlight ~= nil and highlight.targetHighlightStyle ~= "off"
    local style = showHighlight and highlight.targetHighlightStyle or "off"
    local changed = data.targeted ~= targeted
    data.targeted = targeted
    if changed then PS.Stacking.PlateTargeted(data, targeted) end
    -- The state pass keeps an eye on the highlighted plate (StateTick).
    if targeted then rounds.targetPlate = data elseif rounds.targetPlate == data then rounds.targetPlate = nil end
    if data.targetGlowStyle ~= style then
        changed = true
        data.targetGlowStyle = style
        data.targetPulseActive = style == "halo"
        rounds.pulses[data] = data.targetPulseActive or nil
        -- The glow style lights the plate from behind instead of its bars' edges and text.
        local edges = showHighlight and style ~= "glow"
        -- Made the first time this plate is highlighted; never made, they have nothing to hide.
        -- data.targetGlowsHidden: every glow was hidden here or by RemovePlate, their only writers
        -- (they are made hidden), so hiding them again writes nothing.
        local glows = data.targetBarGlows or (edges and PlateParts.EnsureTargetGlows(data)) or EMPTY
        if edges or not data.targetGlowsHidden then
            for _, glow in ipairs(glows) do
                glow.steady:SetShown(edges)
                glow.pulse:SetShown(data.targetPulseActive)
            end
            data.targetGlowsHidden = not edges
        end
        SetTargetTextGlow(data, edges and 0.7 or nil)
        if style == "glow" then rounds.targetGlow.Show(data, db) else rounds.targetGlow.Hide(data) end
    elseif style == "border" then
        -- Newly shown labels can acquire the steady glow without touching other plates.
        SetTargetTextGlow(data, 0.7, true)
    end
    ApplyHealthBorder(data)
    -- A template can say whether this is your target.
    if changed then MarkValues(data, "targeted") end
    rounds.combo.Update(data)
    rounds.SyncAnimation()
end

-- idle: known to be out of combat (a tracked mob not engaged, or a friendly plate), so the threat
-- facts read false rather than unknown. Values follow only a change: another record, idle, or the
-- service's refresh of the record (its revision).
local function UpdateThreatValues(data, info, idle)
    idle = idle == true
    local revision = info and info.revision
    if data.threatValuesSet and data.threatInfo == info and data.threatIdle == idle and data.threatRevision == revision then
        return
    end
    data.threatInfo, data.threatIdle, data.threatRevision, data.threatValuesSet = info, idle, revision, true
    MarkValues(data, "threat")
    rounds.targetGlow.Recolour(data)
end

local function UpdateThreat(data)
    -- The edge goes after the record is forgotten: a threat colour reads it.
    if data.friendly or not PlateNeeds().threat then
        data.tankWarning = false
        if not (data.threatValuesSet and data.threatInfo == nil) then
            data.threat:Hide()
            data.threat:SetText("")
            ThreatText.Forget(data.threat)
            data.threatTextInfo, data.threatTextRevision = nil, nil
            UpdateThreatValues(data, nil, data.friendly == true)
        end
        ApplyHealthBorder(data)
        return
    end
    local showCombined = data.layout.threat.visible ~= false
    data.threat:SetShown(showCombined)
    local info = ThreatRecord(data.unit)
    local service = PS.ThreatService
    if not info and service and type(service.TrackEnemy) == "function" then
        -- The service only tracks units that were hostile and shown when the
        -- plate arrived. Retry occasionally for units that turned hostile later.
        local now = GetTime()
        if not data.threatTrackRetryAt or now >= data.threatTrackRetryAt then
            data.threatTrackRetryAt = now + THREAT_TRACK_RETRY
            info = service:TrackEnemy(data.unit, data.root)
        end
    end
    if not info or not info.engaged then
        data.threat:SetText("")
        ThreatText.Forget(data.threat)
        data.threatTextInfo, data.threatTextRevision = nil, nil
        data.tankWarning = false
        UpdateThreatValues(data, nil, info ~= nil)
        ApplyHealthBorder(data)
        return
    end
    -- Written once per refresh of the record (its revision), not on every state visit.
    local revision = info.revision
    if showCombined and not (revision ~= nil and data.threatTextInfo == info and data.threatTextRevision == revision) then
        ApplyThreatText(data.threat, info, ThreatText.Gap(data.unit))
        -- Coloured by state (ThreatText.StateColour), as the threat windows colour theirs.
        ApplyThreatColour(data.threat, info)
        data.threatTextInfo, data.threatTextRevision = info, revision
    end
    UpdateThreatValues(data, info)
    data.tankWarning = db.tankWarning and data.own and service ~= nil and service:GetPlayerRole() == "TANK" and info.tanking == false
    ApplyHealthBorder(data)
end


local STYLED_TEXTS = { "name", "level", "guild", "targetName", "threat", "tagged", "classification" }
-- Which custom parts a plate makes (PlateParts.EnsureValueSlot) and shows.
PlateParts.placed = setmetatable({}, { __mode = "k" })

-- Whether a custom part draws anything on this plate: owned, not names-only, placed and on, with a
-- source. An unused part's holder is hidden (ShowUsedFrames), or never made.
function PlateParts.Used(data, key)
    local slot, position = data.profile.valueSlots[key], data.layout and data.layout[key]
    return data.own and not data.namesOnly and position ~= nil and not S.TurnedOff(position)
        and slot.source ~= nil and slot.source ~= "off" or false
end

-- Custom parts whose place or size other parts follow (in a stack, pinned, or another part's
-- parent), once per layout table: made even while unused, so the layout measures and places
-- every part as it would with all of them made.
function PlateParts.Placed(layout)
    local keys = PlateParts.placed[layout]
    if keys then return keys end
    keys = {}
    local IS_VALUE_KEY = Styles.IS_VALUE_KEY
    for key, position in pairs(layout) do
        if type(position) == "table" then
            local parent = type(position.parent) == "string" and position.parent or nil
            local parentEntry = parent and layout[parent]
            if IS_VALUE_KEY[key] and (position.attach or (type(parentEntry) == "table" and parentEntry.stack)) then
                keys[key] = true
            end
            if parent and IS_VALUE_KEY[parent] then keys[parent] = true end
        end
    end
    PlateParts.placed[layout] = keys
    return keys
end

-- The cast bar as the profile draws it. A names-only plate's slim bar (Placement's NameCast) is
-- made again by UpdateCast, which every layout pass runs after this.
function rounds.CastGeometry(data)
    local profile = data.profile
    local castHeight = profile.castHeight or math.max(5, profile.healthHeight - 3)
    data.cast:SetSize(profile.castWidth or profile.width, castHeight)
    Placement.CastLayout(data, castHeight, math.max(7, profile.nameFontSize - 4))
    data.nameCast = nil
end

-- Into or out of the slim names-only cast bar; out, the layout places the bar again.
function rounds.SetNameCast(data, slim)
    if slim then
        rounds.nameCast.Apply(data)
    else
        rounds.CastGeometry(data)
        Placement.AnchorPart(data, data.cast, "cast")
    end
end

local function ApplyAppearance(data)
    counters.appearance = counters.appearance + 1
    local profile = data.profile
    local StyledFont, StyledBar = Styles.StyledFont, Styles.StyledBar
    data.targetGlowStyle = nil
    local detailFontSize = math.max(8, profile.nameFontSize - 2)
    local markSize = math.max(14, profile.nameFontSize + 4)
    data.overlay:SetSize(profile.width + 16, math.max(52, profile.healthHeight + 40))
    data.health:SetSize(profile.width, profile.healthHeight)
    StyledBar(data, "health", data.health, profile.healthTexture)
    data.power:SetSize(profile.powerWidth or profile.width, profile.powerHeight)
    StyledBar(data, "power", data.power, profile.healthTexture)
    data.quest:SetSize(markSize, markSize)
    data.questLoot:SetSize(markSize, markSize)
    data.raidIcon:SetSize(math.max(16, profile.nameFontSize + 6), math.max(16, profile.nameFontSize + 6))
    data.relationshipIcon:SetSize(markSize, markSize)
    data.pvpIcon:SetSize(markSize, markSize)
    StyledBar(data, "cast", data.cast, profile.healthTexture)
    StyledFont(data, "name", data.name, profile.nameFontSize)
    StyledFont(data, "level", data.level, detailFontSize)
    StyledFont(data, "guild", data.guild, detailFontSize)
    StyledFont(data, "targetName", data.targetName, detailFontSize)
    StyledFont(data, "threat", data.threat, detailFontSize)
    StyledFont(data, "tagged", data.tagged, math.max(8, profile.nameFontSize - 3))
    StyledFont(data, "classification", data.classification, detailFontSize)
    rounds.CastGeometry(data)
    rounds.combo.ApplyAppearance(data)
    rounds.targetedBy.ApplyAppearance(data)
    for _, key in ipairs(STYLED_TEXTS) do Styles.StyledBox(data, key, data[key]) end
    -- A custom part this plate's layout does not use is not made; one it uses is made here, before
    -- the layout places it.
    for index = 1, VALUE_SLOT_COUNT do
        local key = VALUE_KEYS[index]
        if PlateParts.Used(data, key) or (data.layout and PlateParts.Placed(data.layout)[key]) then
            PlateParts.EnsureValueSlot(data, key)
        end
        local holder = data.valueHolders[key]
        if holder then
            local slot = profile.valueSlots[key]
            local region = ApplyValueKind(data, key, slot)
            if not slot.kind then
                StyledFont(data, key, region, slot.fontSize)
                Styles.StyledBox(data, key, region)
                region:SetTextColor(slot.colour.r, slot.colour.g, slot.colour.b)
            elseif slot.kind == "bar" then
                StyledBar(data, key, region, profile.healthTexture)
            end
            if data.layout then holder:SetFrameLevel(Styles.LayerLevel(data, key)) end
        end
    end
end



-- Frames that show and hide during play (the power bar with the unit's power type, auras)
-- reflow their stack as they do.
local STACK_FRAMES = { "power", "cast", "buffs", "debuffs" }
-- What the stacks were last placed for: each frame's own shown state (plateSmithStackShown), recorded by
-- the flush that placed them.
function rounds.RecordStackFrames(data)
    for index = 1, #STACK_FRAMES do
        local frame = data[STACK_FRAMES[index]]
        if frame and frame.IsShown then frame.plateSmithStackShown = frame:IsShown() end
    end
end

local function HookStackFrames(data)
    if data.stackHooks then return end
    data.stackHooks = true
    -- These also fire when an ancestor shows or hides (the nameplate coming into view, the plate's own
    -- overlay), which changes nothing the stacks were placed for: only a change of the frame's own
    -- shown state since that placement lays them out again.
    local function Reflow(frame)
        if frame.IsShown and frame:IsShown() == frame.plateSmithStackShown then return end
        MarkStacks(data)
    end
    for _, key in ipairs(STACK_FRAMES) do
        local frame = data[key]
        if frame and frame.HookScript then
            frame:HookScript("OnShow", Reflow)
            frame:HookScript("OnHide", Reflow)
        end
    end
end

-- Rules (a part's "when ... set ..."), in list order: of the rules that hold, the last one that
-- sets colour (a colour, or a blend by health) sets it, the last opacity rule sets opacity, and
-- any hide rule hides. With none, the part keeps its normal style.
-- An empty condition always holds. Colour goes over the part's own colour (restored when no
-- rule sets it); opacity and hide are its alpha, combined with hiding under a hidden parent. A
-- blend whose health % is protected leaves the part's own colour.
local function RuleHolds(data, when)
    if when == nil or (type(when) == "string" and not when:find("%S")) then return true end
    local tree = PS.Template.CompileCondition(when)
    return tree ~= nil and PS.Template.Test(tree, Readers.Get(data))
end

-- One part's rules onto its regions (marked in now).
local function ApplyPartRules(data, key, list, now)
    if not (data.own and data.layout and data.layout[key]) then return end
    local first, second = PartRegions(data, key)
    if not first then return end
    local colourRule, alpha, hide
    for _, rule in ipairs(list) do
        if rule.enabled ~= false and RuleHolds(data, rule.when) then
            local set = rule.set
            if set == "colour" or set == "blend" then colourRule = rule
            elseif set == "alpha" then alpha = rule.alpha
            elseif set == "hide" then hide = true end
        end
    end
    local r, g, b, folded
    if colourRule and colourRule.set == "colour" then
        local colour = colourRule.colour
        if type(colour) == "table" then r, g, b = colour.r, colour.g, colour.b end
    elseif colourRule then
        r, g, b = Styles.BlendColour(colourRule.stops, Readers.Get(data)("health.percent"))
    else
        -- No rule colours it: Threat colours may (Nameplates/ThreatColours.lua), picked inside the
        -- client when only protected answers say who holds it (r, g, b then reach the setter only).
        local threat = PS.ThreatColours.ForPlate(data, key)
        if threat then
            r, g, b = threat.r, threat.g, threat.b
        else
            folded, r, g, b = PS.ThreatColours.FoldForPlate(data, key)
            if folded ~= true then folded, r, g, b = nil, nil, nil, nil end
        end
    end
    for index = 1, 2 do
        local region = index == 1 and first or second
        if region then
            if not folded then
                Styles.RuleColour(region, r, g, b)
            elseif not Styles.FoldedRuleColour(region, r, g, b) then
                Styles.RuleColour(region)
            end
            region.plateSmithRuleAlpha = hide and 0 or alpha
            region.plateSmithRuleHidden = hide or nil
            now[region] = true
        end
    end
end

local function ApplyRules(data)
    local profile = data.profile
    local rules = profile and profile.rules
    local touched = data.ruleRegions
    local ThreatColours = PS.ThreatColours
    local threat = ThreatColours.Wanted(data)
    if not touched and not (rules and next(rules)) and not threat then return end
    -- The regions ruled this time go into the plate's spare table; the two swap each call.
    local now = data.ruleSpare or {}
    data.ruleSpare = nil
    for key, list in pairs(rules or EMPTY) do ApplyPartRules(data, key, list, now) end
    -- Threat colours go on like a rule's colour, under any rule of the part's own.
    if threat then
        for _, key in ipairs(ThreatColours.RULE_PARTS) do
            if not (rules and rules[key]) and ThreatColours.Colours(data, key) then ApplyPartRules(data, key, EMPTY, now) end
        end
    end
    -- Parts whose rules went away go back to their own style.
    if touched then
        for region in pairs(touched) do
            if not now[region] then
                Styles.RuleColour(region)
                region.plateSmithRuleAlpha, region.plateSmithRuleHidden = nil, nil
                if region.SetAlpha then region:SetAlpha(RegionAlpha(region)) end
            end
            touched[region] = nil
        end
    end
    if next(now) then
        data.ruleRegions, data.ruleSpare = now, touched
    else
        data.ruleRegions, data.ruleSpare = nil, now
    end
    -- A region faded under a hidden parent stays faded (RegionAlpha).
    for region in pairs(now) do
        if region.SetAlpha then region:SetAlpha(RegionAlpha(region)) end
    end
    MarkVisibility(data)
end

-- One plate's queued work, in order: values, rules, stacks (and pinned texts), then hiding
-- under a hidden parent. The values render and the rules share one template read.
local function RunFlush(data)
    counters.flushes = counters.flushes + 1
    Readers.Begin(data)
    if data.dirtyValues then
        counters.renderValues = counters.renderValues + 1
        data.dirtyValues = false
        -- A mark made while rendering (a hook) goes into the plate's other kinds table.
        local kinds = data.dirtyKinds or EMPTY
        data.dirtyKinds, data.spareKinds = data.spareKinds, data.dirtyKinds
        local started, nested = addPhases.Start()
        RenderValueSlots(data, kinds)
        addPhases.Stop("values", started, nested)
        for kind in pairs(kinds) do kinds[kind] = nil end
    end
    if data.dirtyRules then
        counters.applyRules = counters.applyRules + 1
        data.dirtyRules = false
        local started, nested = addPhases.Start()
        ApplyRules(data)
        addPhases.Stop("rules", started, nested)
    end
    local started, nested = addPhases.Start()
    if data.dirtyStacks or data.dirtyMeasure then
        counters.reflow = counters.reflow + 1
        local measure = data.dirtyMeasure
        data.dirtyStacks, data.dirtyMeasure = false, false
        ReflowStacks(data, measure)
        rounds.RecordStackFrames(data)
    end
    if data.dirtyVisibility then
        data.dirtyVisibility = false
        ApplyParentVisibility(data)
    end
    addPhases.Stop("placement", started, nested)
end

local DisableRestrictedOverlay -- (below)

FlushPlate = function(data)
    dirtyPlates[data] = nil
    if data.flushing then return end
    -- Released, or a restricted plate PlateSmith does not draw on: nothing to do.
    if not data.unit or active[data.unit] ~= data
        or (data.restrictedFriendly and not data.restrictedOverlayEnabled) then
        ClearDirty(data)
        return
    end
    data.flushing = true
    local ok, reason
    -- What the flush itself showed can queue the plate again (a stack frame's hook).
    for _ = 1, 3 do
        ok, reason = pcall(RunFlush, data)
        if not ok or not dirtyPlates[data] then break end
        dirtyPlates[data] = nil
    end
    data.flushing = false
    if not ok then
        if data.restrictedFriendly then
            DisableRestrictedOverlay(data, reason)
        else
            error(reason, 0)
        end
    end
end

DisableRestrictedOverlay = function(data, reason)
    data.restrictedOverlayEnabled = false
    data.restrictedOverlayError = tostring(reason or "unavailable")
    data.overlay:Hide()
    HideOwnedParts(data)
    ClearDirty(data)
end

-- Plates with time-based work (threat, TAGGED: enemy plates), visited round-robin by the state pass
-- a few a frame. A friendly plate has none, so a city of players costs the state pass nothing.
function rounds.StateWanted(data)
    return data.own and data.friendly == false and (PlateNeeds().threat or TaggedWanted(data)) or false
end

function rounds.SetState(data, wanted)
    if wanted and not data.stateIndex then data.stateDueAt = 0 end
    ListSet(rounds.state, data, "stateIndex", wanted)
end

-- A part's layer frame is hidden while the layout turns the part off, and a custom part's holder
-- while it has nothing to show (no source, a names-only plate), so the client has fewer frames to
-- re-anchor as the plate moves, every frame while the camera turns. The bars and aura rows are
-- their own layer frames and keep their own shown state.
local function ShowUsedFrames(data)
    local layout = data.layout
    for key, frame in pairs(data.layerFrames) do
        if frame ~= data.health and frame ~= data.power and frame ~= data.cast and frame ~= data.buffs
            and frame ~= data.debuffs then
            local position = layout[key == "questLoot" and "quest" or key]
            frame:SetShown(position ~= nil and not S.TurnedOff(position))
        end
    end
    for key, holder in pairs(data.valueHolders) do holder:SetShown(PlateParts.Used(data, key)) end
end

local function ApplyLayout(data)
    counters.applyLayout = counters.applyLayout + 1
    -- Laid out now: a relayout still waiting for a change of place (adds.relayouts) is not needed.
    data.relayoutFrame = nil
    data.own = OwnsAppearance()
    data.friendly = rounds.Friendly(data.unit)
    local restrictedFriendly = RestrictedFriendly(data.friendly)
    data.restrictedFriendly = restrictedFriendly
    data.restrictedOverlayEnabled = restrictedFriendly
        and db.experimentalDungeonFriendlyText and data.own
    -- The plate type, then its design for where the player is (World, or a context design). A kind
    -- change has just read the plate type (KindChanged): one UnitIsPlayer read, not two.
    data.profileKey = data.nextProfileKey or PlateIdentity.ProfileKeyForUnit(data.unit, data.friendly)
    data.nextProfileKey = nil
    data.design = PS.PlateContext.DesignFor(data.profileKey)
    data.profile = PS.Designs.For(db, data.profileKey, data.design) or db.plateProfiles.enemy
    data.namesOnly = not restrictedFriendly and data.friendly and db.friendly == "names"
    data.layout = restrictedFriendly and data.profile.dungeonNamesLayout
        or (data.namesOnly and data.profile.namesLayout or data.profile.layout)
    -- What each update compares against is read again for a fresh plate or new settings.
    data.healthValue, data.healthMaxValue, data.powerRead = nil, nil, nil
    data.threatValuesSet, data.taggedShown, data.pvpState = nil, nil, nil
    data.threatTextInfo, data.threatTextRevision = nil, nil
    -- What the plate's custom parts and rules read (MarkValues skips the rest).
    data.reads = Readers.PlateReads(data.profile, data.layout, settingsRevision)
    -- The profile too: a sparse context design without layout overrides shares World's layout table.
    local prepared = data.own and data.preparedLayout == data.layout and data.preparedProfile == data.profile
        and data.preparedRevision == settingsRevision
    -- A plate PlateSmith does not draw (unknown, restricted without the opt-in text, friendly off)
    -- is only hidden below: it is not styled for its own layout, so a frame the client hands to a
    -- party member between pulls is still prepared for the enemy it comes back to.
    local undrawn = data.friendly == nil or (restrictedFriendly and not data.restrictedOverlayEnabled)
        or (data.friendly and db.friendly == "off")
    if not prepared and not undrawn then
        data.preparedLayout, data.valuesCleared = nil, nil
        data.overlay:SetScale(data.profile.scale)
        -- Value holders are parented to the root so their layer can sit behind
        -- the overlay; they must still follow the overlay's scale.
        for _, holder in pairs(data.valueHolders) do holder:SetScale(data.profile.scale) end
        local started, nested = addPhases.Start()
        ApplyAppearance(data)
        addPhases.Stop("styles", started, nested)
        ShowUsedFrames(data)
        if data.namesOnly then
            -- Values are parented outside the overlay. Switching a live plate from
            -- full to names-only must clear any previously visible value explicitly.
            for _, value in pairs(data.values) do value:Hide() end
        end
    end
    rounds.SetState(data, rounds.StateWanted(data))

    if data.friendly == nil or restrictedFriendly or (data.friendly and db.friendly == "off") then
        -- The opt-in text lays the plate out for the dungeon names layout.
        if not undrawn then data.preparedLayout = nil end
        HideOwnedParts(data)
        RestoreNative(data)
        data.overlay:Hide()
        if not restrictedFriendly then return end
        data.restrictedOverlayError = nil
        if data.restrictedOverlayEnabled then
            -- Opt-in additive preview: never hide, move, or reparent Blizzard's restricted frame.
            local ok, failure = pcall(function()
                ApplyComponentLayout(data)
                data.name:SetShown(data.layout.name.visible ~= false)
                data.health:SetShown(data.layout.health.visible ~= false)
                data.level:SetShown(data.layout.level.visible ~= false)
                data.power:Hide()
                data.overlay:Show()
                UpdateIdentity(data)
                UpdateRaidIcon(data)
                UpdateHealth(data)
                UpdateTarget(data)
                UpdateThreat(data)
                UpdateTagged(data)
                UpdateCast(data)
                UpdatePlateAuras(data)
                MarkValues(data, "all")
            end)
            if not ok then DisableRestrictedOverlay(data, failure) end
        end
        return
    end

    data.overlay:Show()
    if data.own then
        HideNative(data)
        data.name:SetShown(data.layout.name.visible ~= false)
        data.health:SetShown(not data.namesOnly and data.layout.health.visible ~= false)
        data.power:SetShown(false)
        data.level:SetShown(data.layout.level.visible ~= false)
        -- A reused frame already placed for this layout keeps its anchors; the flush's stack check
        -- places it again only if what shows differs from what it was placed for.
        if not prepared then
            if HasStacks(data.layout) then
                -- Placed once, by the flush's stack check (MarkStacks below), after the updates
                -- below have shown and hidden what they do: placing it here too only to place it
                -- again for what they changed doubled a new plate's layout work.
                data.stackStatesFor = nil
            else
                ApplyComponentLayout(data)
            end
        end
        data.preparedLayout, data.preparedProfile, data.preparedRevision = data.layout, data.profile, settingsRevision
        if data.namesOnly then
            data.threat:SetText("")
            data.tagged:Hide()
        end
    else
        data.preparedLayout = nil
        RestoreNative(data)
        RestoreParentFaded(data)
        data.health:Hide()
        data.power:Hide()
        for _, value in pairs(data.values) do value:Hide() end
        data.level:Hide()
        data.guild:Hide()
        data.targetName:Hide()
        data.name:Hide()
        data.threat:ClearAllPoints()
        data.threat:SetPoint("BOTTOM", data.overlay, "TOP", 0, 2)
        data.quest:ClearAllPoints()
        data.quest:SetPoint("RIGHT", data.threat, "LEFT", -4, 0)
        data.raidIcon:Hide()
        data.relationshipIcon:Hide()
        data.pvpIcon:Hide()
        data.classification:Hide()
        data.classificationIcon:Hide()
        data.tagged:Hide()
    end

    UpdateIdentity(data)
    local started, nested = addPhases.Start()
    UpdateRaidIcon(data)
    UpdateHealth(data)
    UpdatePower(data)
    UpdateTarget(data)
    rounds.targetedBy.Update(data)
    local threatStarted, threatNested = addPhases.Start()
    UpdateThreat(data)
    addPhases.Stop("threat", threatStarted, threatNested)
    UpdateTagged(data)
    UpdateCast(data)
    addPhases.Stop("bars", started, nested)
    started, nested = addPhases.Start()
    if auraWork.deferring and auraWork.Reserve(data) then
        -- A timed add: the rows are read in the aura round; one whose unit has an aura shows now, empty,
        -- so this add's layout already makes room for it. A plate with no row shown reads nothing below.
        data.aurasLater = true
        auraWork.Queue(data)
    else
        UpdatePlateAuras(data)
    end
    addPhases.Stop("auras", started, nested)
    started, nested = addPhases.Start()
    HookStackFrames(data)
    addPhases.Stop("placement", started, nested)
    -- Every custom part is drawn for the new layout, whichever kinds it reads.
    MarkValues(data, "all")
    MarkStacks(data)
end

local function AddPlate(unit)
    if not db.enabled or not IsReadable(unit) or type(unit) ~= "string"
        or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    local root = C_NamePlate.GetNamePlateForUnit(unit)
    if not root then return end
    if root.IsForbidden and root:IsForbidden() then return end

    local data = root.PlateSmithData
    if not data then
        data = PlateParts.TakeSpare(root)
        if not data then
            local started, nested = addPhases.Start()
            data = PlateParts.CreatePlate(root)
            counters.platesBuilt = counters.platesBuilt + 1
            addPhases.Stop("build", started, nested)
        end
        PlateParts.Attached()
    end
    root.PlateSmithData = data
    data.unit = unit
    data.targetUnit = Secret.TargetToken(unit)
    data.buffsIndexError, data.debuffsIndexError = nil, nil
    -- For /ps diagnose: when it was added, and how long it waited (and hid Blizzard's plate) if it queued.
    data.addedAt, data.addWaitFrames, data.addHeld = type(GetTime) == "function" and GetTime() or nil, nil, nil
    active[unit] = data
    if PS.ThreatService then
        local started, nested = addPhases.Start()
        PS.ThreatService:TrackEnemy(unit, root)
        if PlateNeeds().threat then PS.ThreatService:RequestRefresh(unit) end
        addPhases.Stop("threat", started, nested)
    end
    local started, nested = addPhases.Start()
    ApplyLayout(data)
    addPhases.Stop("layout", started, nested)
    started, nested = addPhases.Start()
    PS.Stacking.PlateAdded(data)
    addPhases.Stop("placement", started, nested)
end

-- Plate adds are spread over frames: once this frame's adds (with their flush) have cost
-- ADD_BUDGET_MS, further units wait in adds.pending for the next frame's first ticker entry, so a
-- burst of plates (login, a zone-in, a crowd coming into view) never makes one long frame. Without
-- a profiler clock every add runs at once. The budget is the frame's, events and ticker pass
-- together: GetTime is the same all frame, so a new reading starts a new budget. (Starting it in
-- the ticker pass alone let a frame spend it twice, once in its events and again in its pass.)
-- The frame's aura round (auraWork.Run) spends the same budget after the adds.
-- waiting: how many units in order are still pending (order also keeps entries a removal dropped).
-- cost: what the next item is expected to cost (ms), learnt from what items cost (adds.Learn): an add
-- on a frame that exists or a spare (add), half of a plate's build for an add whose nameplate has none
-- (build, adds.Half), a plate's aura pass (auras), or one whose rows have no icons yet, so it makes them
-- (fresh). The seeds are what build 1.1.1+20261003.3 measured in Orgrimmar (a whole build was 7 ms).
-- base: each kind's typical cost (an even average), which the estimate falls back towards every frame
-- (adds.Frame). relayout: a plate laid out again for a change of place (adds.RunRelayouts). overdueRan:
-- this frame's items run past the budget because they waited too long (adds.Run); built: whether this
-- frame built (half) a plate (adds.Half, the spares entry, or a whole one in adds.Now).
local adds = { pending = {}, order = {}, spent = 0, waiting = 0, overdueRan = 0, built = false,
    cost = { add = 1.6, build = 3.5, auras = 1.2, fresh = 2.5, relayout = 2 },
    base = { add = 1.6, build = 3.5, auras = 1.2, fresh = 2.5, relayout = 2 } }

-- An estimate rises at once to a dearer item and eases down slowly, so it errs high; it never sits
-- below the typical cost. One dear item no longer holds admission back for long: the estimate falls
-- half way back to the typical cost each frame, and the typical cost moves at most a tenth of the way
-- to twice itself per item, so an outlier barely moves it while a lasting change (a CPU-bound client)
-- still carries it in a few items.
function adds.Learn(kind, ms)
    local cost, base = adds.cost[kind], adds.base[kind]
    adds.base[kind] = base + (math.min(ms, base * 2) - base) * 0.1
    adds.cost[kind] = math.max(adds.base[kind], cost + (ms - cost) * (ms > cost and 0.5 or 0.1))
end

function adds.Decay()
    for kind, cost in pairs(adds.cost) do
        local base = adds.base[kind]
        if base and cost > base then adds.cost[kind] = base + (cost - base) * 0.5 end
    end
end

-- Whether an item expected to cost cost (ms) fits what the frame's budget has left. A frame's first
-- item always runs, so the queues move: a frame's plate work is the budget plus the misjudgement of
-- its last item at most, or one item alone (a frame's build).
function adds.Fits(cost)
    return adds.spent <= 0 or adds.spent + cost <= LIMITS.ADD_BUDGET_MS
end

-- What adding unit is expected to cost, and whether it needs a build first: its nameplate has no plate
-- and no spare waits (the cost is then the next half of a build's, adds.Half).
function adds.Estimate(unit)
    local root = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if root and not root.PlateSmithData and not PlateParts.spares[1] and not (root.IsForbidden and root:IsForbidden()) then
        return adds.cost.build, true
    end
    return adds.cost.add, false
end

-- Half a plate for a waiting add whose nameplate has none, with no spare waiting: the frame's build (one
-- half a frame, adds.built), timed as an add's build phase. The plate it finishes waits in spares for the
-- add, which runs when the budget lets it (in the same frame if late), its nameplate held meanwhile.
function adds.Half()
    local started = Clock()
    counters.buildHalves = counters.buildHalves + 1
    if PlateParts.BuildHalf() then
        counters.platesBuilt = counters.platesBuilt + 1
        PlateParts.spares[#PlateParts.spares].builtLive = true
    end
    adds.built = true
    if not started then return end
    local span = Clock() - started
    adds.spent = adds.spent + span
    adds.Learn("build", span)
    if addPhases.Record then addPhases.Record("build", span) end
end

-- A waiting unit leaves the queue (added now, or its plate removed); its order entry is skipped.
function adds.Drop(unit)
    if adds.pending[unit] then
        adds.pending[unit] = nil
        adds.waiting = adds.waiting - 1
    end
end

-- Whether PlateSmith draws unit's plate (and hides Blizzard's), as ApplyLayout decides: readable
-- answers only, so an unknown unit is left to Blizzard.
function adds.Drawn(unit)
    if not (db and db.enabled) or not OwnsAppearance() then return false end
    local friendly = rounds.Friendly(unit)
    if friendly == nil or RestrictedFriendly(friendly) then return false end
    return not (friendly and db.friendly == "off")
end

-- A waiting add's nameplate shows nothing until the add draws it: Blizzard's own plate (its name at
-- Blizzard's size and opacity) showed meanwhile, for up to a second in a busy city, then PlateSmith's
-- took its place at the plate's own size. Only a plate PlateSmith will draw is held, the way an add
-- hides it (HideNative, the alphas kept to put back). held: unit -> the root's plate, or a stand-in
-- { root } for a nameplate with no plate yet; queuedAt: unit -> the frame (auraWork.frame) it queued in;
-- queuedMs: unit -> the profiler clock then.
adds.held, adds.queuedAt, adds.queuedMs = {}, {}, {}
-- performance.addQueue (Diagnostics/Performance.lua): queued, held, each wait in frames and ms, overdue runs.
local function NoRecord() end
adds.record = PS.Performance and PS.Performance.RecordAddQueue or NoRecord

-- Its cost is the frame's plate work too (adds.spent), so a burst's holds leave less for the frame's adds.
function adds.Hold(unit)
    local started = Clock()
    adds.queuedMs[unit] = started
    adds.Holding(unit)
    if started then adds.spent = adds.spent + Clock() - started end
end

function adds.Holding(unit)
    adds.queuedAt[unit] = auraWork.frame
    if adds.held[unit] or not adds.Drawn(unit) then return end
    local root = C_NamePlate.GetNamePlateForUnit(unit)
    if not root or (root.IsForbidden and root:IsForbidden()) then return end
    local record = root.PlateSmithData
    -- Still another unit's plate: that unit's own removal comes first.
    if record and record.unit ~= nil then return end
    record = record or { root = root }
    HideNative(record)
    adds.held[unit] = record
    adds.record("held")
end

-- The add ran (added) or the unit went (not added): a plate that drew takes the held frames over (its
-- own HideNative or RestoreNative already ran); otherwise they are put back.
function adds.Release(unit, added)
    local queuedAt, queuedMs = adds.queuedAt[unit], adds.queuedMs[unit]
    adds.queuedAt[unit], adds.queuedMs[unit] = nil, nil
    local data = added and active[unit]
    if data and queuedAt then
        local waited, clock = auraWork.frame - queuedAt, queuedMs and Clock()
        data.addWaitFrames = waited
        adds.record("waited", waited, clock and clock - queuedMs or nil)
    end
    local record = adds.held[unit]
    if not record then return end
    adds.held[unit] = nil
    if data then data.addHeld = true end
    if data == record then return end
    if data then
        ListSet(rounds.native, record, "nativeIndex", false)
    else
        RestoreNative(record)
    end
end

-- ticker: called from the frame's ticker pass (without GetTime, the budget starts there). frameMs: the
-- last frame's length (the spares entry's idle share).
function adds.Frame(ticker)
    local now = type(GetTime) == "function" and GetTime() or nil
    if now == nil then
        if ticker then adds.spent, adds.overdueRan, adds.built = 0, 0, false end
    elseif now ~= adds.stamp then
        adds.frameMs = adds.stamp and (now - adds.stamp) * 1000 or 0
        adds.stamp, adds.spent, adds.overdueRan, adds.built, auraWork.frame = now, 0, 0, false, auraWork.frame + 1
        adds.Decay()
    end
end

-- How many frames unit has waited since it queued (0: it is not waiting).
function adds.Waited(unit)
    local queuedAt = adds.queuedAt[unit]
    return queuedAt and auraWork.frame - queuedAt or 0
end

-- Whether an item queued in frame (auraWork.frame) at ms (the profiler clock) has waited long enough
-- to run past the budget: ADD_OVERDUE_FRAMES frames and ADD_OVERDUE_MS both.
function adds.LateSince(frame, ms)
    if auraWork.frame - frame < LIMITS.ADD_OVERDUE_FRAMES then return false end
    local clock = Clock()
    return not (ms and clock) or clock - ms >= LIMITS.ADD_OVERDUE_MS
end

function adds.Late(unit)
    local queuedAt = adds.queuedAt[unit]
    return queuedAt ~= nil and adds.LateSince(queuedAt, adds.queuedMs[unit])
end

-- How many more items may run past the budget this frame: ADD_OVERDUE_PER_FRAME, one once the frame
-- has built half a plate. So a frame holds at most one half and one other overdue item.
function adds.OverdueLeft()
    return (adds.built and 1 or LIMITS.ADD_OVERDUE_PER_FRAME) - adds.overdueRan
end

-- Whether the oldest waiting add is late and may still run past the budget this frame: it then goes
-- first, ahead of the aura round's starvation guard.
function adds.Overdue()
    if adds.OverdueLeft() <= 0 then return false end
    local order = adds.order
    for index = 1, #order do
        local unit = order[index]
        if adds.pending[unit] then return adds.Late(unit) end
    end
    return false
end

local function AddAndFlush(unit)
    AddPlate(unit)
    local data = active[unit]
    if data and dirtyPlates[data] then
        local started, nested = addPhases.Start()
        FlushPlate(data)
        addPhases.Stop("flush", started, nested)
    end
end

-- A timed add leaves its aura pass to the frame's aura round (auraWork.deferring), which the same
-- budget bounds: its name and bars show now, its auras in the same frame's ticker pass when the budget
-- has room, else a frame or so later. A row that will show is shown empty by the add (auraWork.Reserve),
-- so filling it does not lay the plate out again. Keeping the aura pass out of the add keeps each add a
-- small step (a new frame's build with its icons made was a 16 ms frame on its own). Without a
-- profiler clock everything runs at once.
function adds.Now(unit)
    local started = Clock()
    if not started or not addPhases.Record then
        AddAndFlush(unit)
        return adds.Release(unit, true)
    end
    addPhases.on, addPhases.nested = true, 0
    auraWork.deferring = true
    local built = counters.platesBuilt
    local ok, reason = pcall(AddAndFlush, unit)
    auraWork.deferring = false
    adds.Release(unit, ok)
    local span = Clock() - started
    -- What no phase covers (finding the plate, its tokens, the dirty marks).
    if ok and active[unit] then addPhases.spent.other, addPhases.ran.other = span - addPhases.nested, true end
    addPhases.Finish()
    adds.spent = adds.spent + span
    if counters.platesBuilt ~= built then adds.built = true end
    if ok and active[unit] then adds.Learn(counters.platesBuilt ~= built and "build" or "add", span) end
    if not ok then error(reason, 0) end
end

-- While adds wait, a new one queues behind them (oldest first), so a run of busy frames cannot
-- keep the waiting ones back. One whose nameplate needs a build builds half a plate now if the frame
-- has not built and the half fits (adds.Half), and waits for the other half; it is added here only if
-- that finished a plate and the add still fits. Without a profiler clock every add runs at once.
function adds.Request(unit)
    if not IsReadable(unit) or type(unit) ~= "string" then return end
    adds.Frame(false)
    PlateParts.Churn()
    local first = adds.spent <= 0
    local now = adds.waiting == 0 and not (first and auraWork.Starving())
    if now and Clock() then
        local cost, build = adds.Estimate(unit)
        if build and not adds.built and adds.Fits(cost) then
            adds.Half()
            cost, build = adds.Estimate(unit)
        end
        now = not build and adds.Fits(cost)
    end
    if now then
        adds.Now(unit)
    elseif not adds.pending[unit] then
        adds.pending[unit], adds.waiting = true, adds.waiting + 1
        adds.order[#adds.order + 1] = unit
        counters.deferredAdds = counters.deferredAdds + 1
        adds.record("queued")
        adds.Hold(unit)
    end
end

-- The frame's queued adds, oldest first, while the next fits what the frame's budget has left (the
-- first of a frame always does). The queue still moves, as a frame's events add nothing while adds
-- wait (adds.Request). One that does not fit but is late (adds.Late) runs anyway while the frame has
-- overdue room (adds.OverdueLeft): a waiting add's name is hidden (adds.Hold), and a plate drawn with
-- its auras a frame later beats a missing name. One whose nameplate needs a build gets half a plate
-- (adds.Half) when the frame has not built and the half fits, or it is late and the frame has overdue
-- room and has not spent its budget (so a late half never joins an add past the budget: such a frame
-- would hold about a whole build); once a half finished its plate, its add follows on the same terms as
-- any other, so a late name's frame is its second half and its add. A build is passed over, keeping its
-- place, once the frame has built, and while it does not fit and is not late: the adds behind it on
-- frames that exist need not wait for it.
function adds.Run()
    local order, kept, stopped = adds.order, 0, false
    for index = 1, #order do
        local unit = order[index]
        if adds.pending[unit] then
            local run = not stopped
            if run then
                local cost, build = adds.Estimate(unit)
                if build and not adds.built and (adds.Fits(cost)
                    or adds.Late(unit) and adds.OverdueLeft() > 0 and adds.spent < LIMITS.ADD_BUDGET_MS) then
                    adds.Half()
                    cost, build = adds.Estimate(unit)
                end
                if build then
                    run = false
                elseif not adds.Fits(cost) then
                    if adds.OverdueLeft() > 0 and adds.Late(unit) then
                        adds.overdueRan = adds.overdueRan + 1
                        counters.overdueAdds = counters.overdueAdds + 1
                        adds.record("overdue")
                    else
                        -- Those behind a waiting add with a plate ready waited less: none is late, and
                        -- none takes the spare it waits for.
                        run, stopped = false, true
                    end
                end
            end
            if run then
                adds.Drop(unit)
                adds.Now(unit)
            else
                kept = kept + 1
                order[kept] = unit
            end
        end
    end
    for index = kept + 1, #order do order[index] = nil end
end

-- The threat spotlight: a thin line with a faint glow, fitted to what the plate draws. Warm gold
-- unless a colour is configured.
local SPOTLIGHT_COLOUR = { r = 1, g = 0.78, b = 0.3 }
local SPOTLIGHT_PADDING = 3
local SPOTLIGHT_TICKER = "plates.spotlight"
local function SpotlightColour()
    local colour = db.threatSpotlightColour
    if type(colour) == "table" and type(colour.r) == "number" and type(colour.g) == "number"
        and type(colour.b) == "number" then
        return colour
    end
    return SPOTLIGHT_COLOUR
end

-- Each style shows only its own regions: glow (rings round the health bar), arrow (above the
-- name), sides (chevrons), box, or both (box and chevrons).
local function ApplySpotlightStyle(data)
    -- A plate never spotlit has no spotlight to restyle (HighlightPlate makes it).
    if not data.beacon then return end
    local style = db.threatSpotlightStyle
    local colour = SpotlightColour()
    local box = style == "box" or style == "both"
    local sides = style == "sides" or style == "both"
    data.beacon:SetBackdropBorderColor(colour.r, colour.g, colour.b, box and 1 or 0)
    data.beaconGlow:SetBackdropBorderColor(colour.r, colour.g, colour.b, box and 0.22 or 0)
    data.beaconLeft:SetShown(sides)
    data.beaconRight:SetShown(sides)
    data.beaconLeft:SetTextColor(colour.r, colour.g, colour.b)
    data.beaconRight:SetTextColor(colour.r, colour.g, colour.b)
    data.beaconHalo:SetShown(style == "glow")
    for _, ring in ipairs(data.beaconHaloRings) do
        ring:SetBackdropBorderColor(colour.r, colour.g, colour.b, ring.plateSmithAlpha)
    end
    data.beaconArrow:SetShown(style == "arrow")
    data.beaconArrow:SetVertexColor(colour.r, colour.g, colour.b)
end

local function SetPlateAlpha(data, alpha)
    data.overlay:SetAlpha(alpha)
    for _, holder in pairs(data.valueHolders) do holder:SetAlpha(alpha) end
end

-- Other plates fade while a spotlight shows; with none showing and none faded, nothing to visit.
local function UpdateSpotlight(now)
    if spotlightUnit and (not active[spotlightUnit] or now >= spotlightUntil) then
        spotlightUnit, spotlightUntil = nil, nil
    end
    if not spotlightUnit and not spotlightDimmed then
        rounds.SyncAnimation()
        return
    end
    spotlightDimmed = false
    for unit, data in pairs(active) do
        local enemy = data.friendly == false
        local alpha = spotlightUnit and unit ~= spotlightUnit and enemy
            and db.threatSpotlightOthersAlpha or 1
        if data.spotlightAlpha ~= alpha and (alpha ~= 1 or data.spotlightAlpha ~= nil) then
            SetPlateAlpha(data, alpha)
            data.spotlightAlpha = alpha
        end
        if alpha ~= 1 then spotlightDimmed = true end
    end
    rounds.SyncAnimation()
end

local function RemovePlate(unit)
    if not IsReadable(unit) or type(unit) ~= "string" then return end
    -- A unit still waiting to be added is dropped too, and Blizzard's frames it held put back.
    adds.Drop(unit)
    adds.Release(unit, false)
    local data = active[unit]
    if not data then return end
    if PS.ThreatService then PS.ThreatService:UntrackEnemy(unit) end
    rounds.SetState(data, false)
    data.nextProfileKey = nil
    -- An aura read still waiting (UNIT_AURA's, or the add's own) is dropped; its order entry is skipped.
    auraWork.polls[data], auraWork.pending[data], data.aurasLater = nil, nil, nil
    -- What this unit's aura passes cost is not the next unit's estimate (a unit with no aura cost little).
    data.auraCost, data.auraRowsLeft = nil, nil
    RestoreNative(data)
    data.nativeAlphas = nil
    data.threatTrackRetryAt = nil
    data.threatInfo, data.threatIdle, data.threatValuesSet, data.tankWarning = nil, nil, nil, nil
    data.healthValue, data.healthMaxValue, data.powerValue, data.powerMaxValue = nil, nil, nil, nil
    data.targeted, data.relationship, data.taggedShown, data.aurasWanted, data.pvpState = nil, nil, nil, nil, nil
    data.inRange, data.questProgressText, data.questProgressPercent = nil, nil, nil
    data.beaconUntil = nil
    -- A test name is never carried to the next unit on this frame.
    if rounds.testNamePlate == data then rounds.testNamePlate = nil end
    data.testName = nil
    if data.beacon then data.beacon:Hide() end
    rounds.combo.Release(data)
    rounds.targetedBy.Release(data)
    -- Only a plate that showed the target's highlight has one to take down.
    if data.targetGlowStyle and data.targetGlowStyle ~= "off" then
        for _, glow in ipairs(data.targetBarGlows or EMPTY) do
            glow.steady:Hide()
            glow.pulse:Hide()
        end
        data.targetGlowsHidden = true
        rounds.targetGlow.Hide(data)
    end
    SetTargetTextGlow(data)
    data.targetPulseActive, rounds.pulses[data] = nil, nil
    data.targetGlowStyle = nil
    data.threatTextInfo, data.threatTextRevision, data.raidIconUnit = nil, nil, nil
    -- An aura read that errored in combat is tried again for the next unit.
    data.buffsIndexError, data.debuffsIndexError = nil, nil
    -- The next unit on this token is another mob: its native aura container is pointed again.
    data.buffs.nativeAuraBound, data.debuffs.nativeAuraBound = nil, nil
    if data.spotlightAlpha and data.spotlightAlpha ~= 1 then SetPlateAlpha(data, 1) end
    RestoreParentFaded(data)
    data.spotlightAlpha = nil
    data.overlay:Hide()
    HideOwnedParts(data)
    data.health:SetMinMaxValues(0, 1)
    data.health:SetValue(1)
    -- Sizes measured for this unit are not the next one's.
    for region in pairs(data.sizedRegions or EMPTY) do
        region.plateSmithSize = nil
        data.sizedRegions[region] = nil
    end
    data.layoutTransforms = nil
    ClearDirty(data)
    PS.Stacking.PlateRemoved(data)
    data.unit, data.targetUnit = nil, nil
    active[unit] = nil
    if spotlightUnit == unit then
        spotlightUnit, spotlightUntil = nil, nil
        UpdateSpotlight(GetTime())
    end
end

local function ReleaseAllPlates()
    for unit in pairs(active) do RemovePlate(unit) end
end

-- Adds the visible plates not already tracked for their frame.
local function ScanPlates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local plates = C_NamePlate.GetNamePlates()
    for _, root in ipairs(plates) do
        local unit = root.namePlateUnitToken
        if IsReadable(unit) and type(unit) == "string" then
            local data = active[unit]
            if not (data and data.root == root) then adds.Request(unit) end
        end
    end
end

-- Whether region is drawn now: shown, not hidden by a rule, not faded out.
local function RegionDrawn(region)
    if not (region.IsShown and region:IsShown()) or region.plateSmithRuleHidden == true then return false end
    local alpha = ReadNumber(region, "GetAlpha")
    return alpha == nil or alpha > 0.01
end

-- The arrow points down at the box's top edge, lifted while it bobs.
local function SetSpotlightArrow(data, lift)
    data.beaconArrow:ClearAllPoints()
    data.beaconArrow:SetPoint("BOTTOM", data.beacon, "TOP", 0, 1 + lift)
end

-- A drawn part's rectangle about the plate's centre, from the layout's placement and the part's
-- size, never its screen position: the client will not measure a restricted plate's regions.
local function SpotlightPartRect(data, transforms, key)
    local region, transform = data[key], transforms and transforms[key]
    if not (region and transform and RegionDrawn(region)) then return nil end
    local width, height = SafeSize(region, data)
    if not (width and height and width > 0 and height > 0) then return nil end
    local halfWidth, halfHeight = width * transform.scale / 2, height * transform.scale / 2
    return transform.x - halfWidth, transform.x + halfWidth, transform.y - halfHeight, transform.y + halfHeight
end

-- Every style centres on the plate's core: the health bar's centre, a box as wide on each side
-- as the name or bar reaches (side marks such as the quest mark and level are left out, so they
-- cannot make it lopsided), from the lowest bar to the name's top.
local SPOTLIGHT_CORE_WIDTH = { "name", "health" }
local SPOTLIGHT_CORE_HEIGHT = { "name", "health", "power", "cast" }
local function FitSpotlight(data)
    local beacon, overlay, layout = data.beacon, data.overlay, data.layout
    -- Worked out from the sizes drawn now (a pinned part follows its text live, without a re-layout).
    data.layoutTransforms = nil
    local transforms = layout and Transforms(layout, data)
    local healthLeft, healthRight, healthBottom, healthTop = SpotlightPartRect(data, transforms, "health")
    local centre
    if healthLeft then
        centre = transforms.health.x
    else
        local nameLeft, nameRight = SpotlightPartRect(data, transforms, "name")
        if nameLeft then centre = (nameLeft + nameRight) / 2 end
    end
    local halfWidth, bottom, top
    if centre then
        for _, key in ipairs(SPOTLIGHT_CORE_WIDTH) do
            local left, right = SpotlightPartRect(data, transforms, key)
            if left then halfWidth = math.max(halfWidth or 0, math.abs(left - centre), math.abs(right - centre)) end
        end
        for _, key in ipairs(SPOTLIGHT_CORE_HEIGHT) do
            local _, _, partBottom, partTop = SpotlightPartRect(data, transforms, key)
            if partBottom then
                bottom, top = math.min(bottom or math.huge, partBottom), math.max(top or -math.huge, partTop)
            end
        end
    end
    beacon:ClearAllPoints()
    local rect = data.spotlightRect or {}
    data.spotlightRect = rect
    -- The chevrons sit just outside the box, level with the health bar when it shows.
    local chevronY = 0
    if halfWidth then
        local left, right = centre - halfWidth - SPOTLIGHT_PADDING, centre + halfWidth + SPOTLIGHT_PADDING
        bottom, top = bottom - SPOTLIGHT_PADDING, top + SPOTLIGHT_PADDING
        beacon:SetPoint("BOTTOMLEFT", overlay, "CENTER", left, bottom)
        beacon:SetPoint("TOPRIGHT", overlay, "CENTER", right, top)
        if healthLeft then chevronY = transforms.health.y - (bottom + top) / 2 end
        rect.left, rect.right, rect.bottom, rect.top, rect.centre = left, right, bottom, top, centre
    else
        beacon:SetAllPoints(overlay)
        rect.left, rect.right, rect.bottom, rect.top, rect.centre = nil, nil, nil, nil, nil
    end
    PlateParts.ApplyChevronFont(data)
    data.beaconLeft:ClearAllPoints()
    data.beaconLeft:SetPoint("RIGHT", beacon, "LEFT", -2, chevronY)
    data.beaconRight:ClearAllPoints()
    data.beaconRight:SetPoint("LEFT", beacon, "RIGHT", 2, chevronY)
    local halo = data.beaconHalo
    halo:ClearAllPoints()
    if healthLeft then
        halo:SetPoint("BOTTOMLEFT", overlay, "CENTER", healthLeft - 1, healthBottom - 1)
        halo:SetPoint("TOPRIGHT", overlay, "CENTER", healthRight + 1, healthTop + 1)
    else
        halo:SetAllPoints(beacon)
    end
    SetSpotlightArrow(data, 0)
end

local function HighlightPlate(unit, duration)
    local data = type(unit) == "string" and active[unit] or nil
    if not data or not data.unit or not data.overlay:IsShown() then return false end
    duration = math.max(1, math.min(8, tonumber(duration) or db.threatSpotlightDuration))
    if spotlightUnit and spotlightUnit ~= unit and active[spotlightUnit] then
        local previous = active[spotlightUnit]
        previous.beaconUntil = nil
        previous.beacon:Hide()
    end
    spotlightUnit, spotlightUntil = unit, GetTime() + duration
    data.beaconUntil = GetTime() + duration
    if not data.beacon then
        PlateParts.EnsureBeacon(data)
        Styles.ApplyDrawOrder(data)
    end
    ApplySpotlightStyle(data)
    FitSpotlight(data)
    data.beacon:SetAlpha(1)
    data.beacon:Show()
    PS.Ticker.SetEnabled(SPOTLIGHT_TICKER, true)
    UpdateSpotlight(GetTime())
    return true
end

-- Blizzard's shared nameplate fonts have one owner (Nameplates/NativeFonts.lua).
local function ApplyNativeNameFont() PS.NativeFonts.Apply(db) end

local platesReleased = false

-- relayoutOnly: nothing in the settings changed (a zone change), so plates keep what was prepared
-- for their layouts and the profile is not marked changed. changedOnly (a change of place): only the
-- plates whose design changed are laid out again, a few a frame (adds.QueueRelayouts).
local function RefreshAllNow(relayoutOnly, changedOnly)
    -- Stacking sizes plates from their layouts, so every refresh may change them.
    PS.Stacking.Invalidate()
    -- Where plates show follows the settings and the place (a context change relayouts through here).
    PS.PlateVisibility.Apply()
    PS.Conflicts.ForgetProvider()
    if not relayoutOnly then
        PS.Profiles.MarkChanged()
        PS.Designs.Invalidate()
        settingsRevision = settingsRevision + 1
        -- A layout that now shows threat (or none that does) starts or stops the service.
        local service = PS.ThreatService
        if service and type(service.SyncTicker) == "function" then service:SyncTicker() end
    end
    rounds.range.SetWanted(db.enabled and PlateNeeds().range)
    rounds.combo.SetWanted(db.enabled and PlateNeeds().combo)
    rounds.targetedBy.SetWanted(db.enabled and PlateNeeds().targetedBy)
    -- Before the enabled check: turned off, PlateSmith puts Blizzard's fonts back too.
    ApplyNativeNameFont()
    if not db.enabled then
        ReleaseAllPlates()
        platesReleased = true
        return
    end
    if platesReleased then
        platesReleased = false
        ScanPlates()
    end
    if changedOnly then return adds.QueueRelayouts() end
    for unit, data in pairs(active) do
        if data.unit == unit then
            ApplyLayout(data)
            ApplySpotlightStyle(data)
        end
    end
    UpdateSpotlight(GetTime())
end

local function RefreshAll() RunBatch(false, RefreshAllNow) end

local function SafePlateUpdate(data, update)
    if data.restrictedFriendly then
        if not data.restrictedOverlayEnabled then return end
        local ok, reason = pcall(update, data)
        if not ok then DisableRestrictedOverlay(data, reason) end
    else
        update(data)
    end
end

-- The mark and the loot bag trade places: what sits under the marker follows a change.
local function UpdateQuestMarker(data)
    if UpdateQuest(data) then MarkStacks(data) end
end

local function RefreshQuestMarkersNow()
    for unit, data in pairs(active) do
        if data.unit == unit then SafePlateUpdate(data, UpdateQuestMarker) end
    end
end

local function RefreshQuestMarkers() RunBatch(false, RefreshQuestMarkersNow) end

-- The owned plate of the player's target, when the client names it: false when it withholds.
local function TargetPlate()
    local root, state = RaidMarker.PlateRoot("target")
    if state == "secret" or state == "error" then return false end
    local data = root and root.PlateSmithData
    if data and data.unit and active[data.unit] == data then return data end
    return nil
end

-- A target change reaches only the old and the new target's plates: the highlight, targeted, and
-- threat (the service re-reads those two records; a plate's UpdateThreat reads only the service's
-- cache and the role, never the target token, and the state pass visits the others as before).
-- Auras borrowed from the target token change on the same two plates.
local lastTargetPlate
local function RefreshTargetState()
    -- Whether there is a target at all (hastarget) changes on every plate, not only the two whose
    -- targeted changed, so what reads it (TemplateReaders' reads.hasTarget, or a volatile token) is
    -- marked on every plate. (rounds.hasTarget: the main chunk is at Lua 5.1's local limit.)
    local hasTarget = Secret.ReadBoolean(UnitExists, "target")
    local targetCame = hasTarget ~= rounds.hasTarget
    rounds.hasTarget = hasTarget
    local visited = false
    for unit, data in pairs(active) do
        if data.unit == unit then
            visited = true
            -- UpdateTarget changes nothing on a plate that is not the target now and showed no
            -- target state (targeted, a glow style other than "off", or the state pass's plate):
            -- its border already follows tankWarning, which UpdateThreat applies as it writes it.
            if data.targeted or data.targetGlowStyle ~= "off" or rounds.targetPlate == data
                or SameUnit(unit, "target") then
                SafePlateUpdate(data, UpdateTarget)
                SafePlateUpdate(data, UpdateThreat)
            end
            if targetCame and (not data.reads or data.reads.hasTarget) then MarkValues(data, "targeted") end
        end
    end
    if visited then rounds.SyncAnimation() end
    local current = TargetPlate()
    if current == false then
        for unit, data in pairs(active) do
            if data.unit == unit and data.aurasWanted then SafePlateUpdate(data, UpdatePlateAuras) end
        end
        current = nil
    else
        if lastTargetPlate and lastTargetPlate.unit and active[lastTargetPlate.unit] == lastTargetPlate then
            SafePlateUpdate(lastTargetPlate, UpdatePlateAuras)
        end
        if current and current ~= lastTargetPlate then SafePlateUpdate(current, UpdatePlateAuras) end
    end
    lastTargetPlate = current
end

-- /ps testname: one plate (the target's when set) draws text in its name's place, through the
-- plates' own font route, so a font can be checked on a live plate. nil clears it. Returns
-- whether it was set, else why not ("no-plate", or "withheld" when the client hides the target's plate).
function rounds.SetTestName(text)
    local previous = rounds.testNamePlate
    if previous then
        rounds.testNamePlate, previous.testName = nil, nil
        if previous.unit and active[previous.unit] == previous then
            RunBatch(false, SafePlateUpdate, previous, UpdateIdentity)
        end
    end
    if text == nil then return true end
    local data = TargetPlate()
    if data == false then return false, "withheld" end
    if not (data and data.own and not (data.restrictedFriendly and not data.restrictedOverlayEnabled)) then
        return false, "no-plate"
    end
    data.testName, rounds.testNamePlate = text, data
    RunBatch(false, SafePlateUpdate, data, UpdateIdentity)
    return true
end

-- What unit and social events change on a plate, each applied only where something changed.
local changes = {}

-- Group, guild and friends updates (bursty in a city) change only relationships: each friendly
-- player's is read again, and only a plate whose relationship changed updates its identity.
function changes.Relationship(data)
    if ReadRelationship(data) ~= data.relationship then UpdateIdentity(data) end
end

function changes.Relationships()
    for unit, data in pairs(active) do
        if data.unit == unit and data.profileKey == "friendlyPlayer" and data.overlay:IsShown() then
            SafePlateUpdate(data, changes.Relationship)
        end
    end
end

-- Whether the unit is now another kind of plate (friendliness, a restricted friendly, plate type, its
-- design here, or who draws it): only then is it laid out again.
function changes.KindChanged(data)
    local friendly = rounds.Friendly(data.unit)
    if friendly ~= data.friendly or OwnsAppearance() ~= data.own then return true end
    if RestrictedFriendly(friendly) ~= data.restrictedFriendly then return true end
    local plateType = PlateIdentity.ProfileKeyForUnit(data.unit, friendly)
    if plateType == data.profileKey and PS.PlateContext.DesignFor(plateType) == data.design then return false end
    -- For the ApplyLayout that follows (an enemy whose player status the client now gives is one).
    data.nextProfileKey = plateType
    return true
end

-- A unit's faction, flags or classification changed: a new kind is laid out, else its identity
-- (PvP mark, colour, classification) and TAGGED follow.
function changes.UnitKind(data)
    if changes.KindChanged(data) then
        data.threatTrackRetryAt = nil
        ApplyLayout(data)
        ApplySpotlightStyle(data)
    else
        SafePlateUpdate(data, UpdateIdentity)
        SafePlateUpdate(data, UpdateTagged)
    end
end

-- UNIT_FLAGS: tapped and PvP state. Rules and stacks follow only a change.
function changes.UnitFlags(data)
    UpdateTagged(data)
    if UpdatePvPIcon(data) then
        MarkRules(data)
        MarkStacks(data)
    end
end

-- UNIT_TARGET on a plate's unit: its target-of-target name follows (stacks only when that part
-- shows or showed), and whatever reads the target token (MarkValues).
function changes.UnitTarget(data)
    local region = data.targetName
    local wasShown = region and region:IsShown()
    UpdateTargetName(data)
    if wasShown or (region and region:IsShown()) then MarkStacks(data) end
    MarkValues(data, "target")
end

-- The player's own flags changed (AFK, PvP): other units' reactions can follow, so each plate's
-- kind is checked; enemies' colours follow their reaction.
function changes.UnitKinds()
    for unit, data in pairs(active) do
        if data.unit == unit then
            if changes.KindChanged(data) then
                data.threatTrackRetryAt = nil
                ApplyLayout(data)
                ApplySpotlightStyle(data)
            elseif data.friendly == false then
                SafePlateUpdate(data, UpdateIdentity)
            end
        end
    end
end

-- The target and focus plates are raised over the rest (Stacking), their parts levelled again.
PS.Stacking.Attach({ active = active, ApplyDrawOrder = Styles.ApplyDrawOrder })

-- The interrupt's readiness moved: casts coloured by it follow, and, when the readable answer
-- changed, whatever reads interruptReady (MarkValues skips plates that read nothing of it).
function changes.Interrupt(readyChanged)
    for data in pairs(activeCasts) do SafePlateUpdate(data, Styles.CastColour) end
    if not readyChanged then return end
    for unit, data in pairs(active) do
        if data.unit == unit then MarkValues(data, "interrupt") end
    end
end
if PS.Interrupt then
    PS.Interrupt.SetListener(function(readyChanged)
        if db then RunBatch(false, changes.Interrupt, readyChanged) end
    end)
end

local PlateSettings = assert(PS._CreatePlateSettings,
    "PlateSmith PlateSettings missing")({
    GetSettings = GetSettings,
    RefreshAll = RefreshAll,
    Relayout = function() RunBatch(false, RefreshAllNow, true) end,
})

-- Diagnostic probes read the runtime's live plate state but own their report logic.
local Diagnose, ProbePlayerPlate, AuraProbe, BuildDiagnosticReport = assert(PS._CreateDiagnosticProbes,
    "PlateSmith DiagnosticProbes missing")({
    active = active,
    GetSettings = GetSettings,
    RegionVisibleState = RegionVisibleState,
    ReadUnitName = PlateIdentity.ReadUnitName,
    ExternalProvider = ExternalProvider,
    QuestRelevance = QuestRelevance,
    ThreatRecord = ThreatRecord,
    VALUE_SLOT_COUNT = VALUE_SLOT_COUNT,
    AURA_ICON_COUNT = AURA_ICON_COUNT,
})
-- The window opened on Performance captures a report only when a report tab is chosen.
DiagnosticUI._buildReport = BuildDiagnosticReport

local pending = { kinds = false, relationships = false, relationshipsAt = 0, auras = false, aurasAt = 0,
    quests = false, questsAt = 0, raidFallback = false, raidFallbackAt = 0, raidTokens = {}, context = false,
    contextAt = 0 }

local function UpdateCastTimes(now)
    local castTime = now * 1000
    for data in pairs(activeCasts) do
        local cast = data.cast
        if not data.restrictedFriendly then
            cast:SetValue(castTime)
            UpdateCastTime(data, now)
        elseif data.restrictedOverlayEnabled and not pcall(cast.SetValue, cast, castTime) then
            DisableRestrictedOverlay(data, "cast update failed")
        elseif data.restrictedOverlayEnabled then
            UpdateCastTime(data, now)
        end
    end
end

-- One plate's rows read for the round. Timed, it counts against the frame's plate budget (adds.spent),
-- with the stack reflow a row shown or hidden asks for (flushed here, inside the time, not at the
-- batch's end), and an add's own aura pass is recorded as its "aurasLater" phase.
-- data.auraCost: what the plate's last whole aura pass cost here (for this unit), its estimate for the
-- next. budgeted (the frame's round): a pass expected to cost more than the frame's budget has left
-- (a first pass making both rows' icons, which ran as a frame's first item alone at over 7 ms) is split:
-- the buffs row now, the debuffs row in a later round (data.auraRowsLeft).
function auraWork.Read(data, budgeted)
    local started = Clock()
    local only = data.auraRowsLeft
    data.auraRowsLeft = nil
    if budgeted and started and not only and adds.spent + auraWork.Estimate(data) > LIMITS.ADD_BUDGET_MS then
        only, data.auraRowsLeft = "buffs", "debuffs"
    end
    local later = data.aurasLater
    data.aurasLater = nil
    local fresh = not (data.buffIcons[1] or data.debuffIcons[1])
    -- Work marked before the pass (this frame's deferred unit events) is flushed with it, but timed
    -- apart (earlier), so reflow is only the stack layout the pass itself asked for.
    local earlier = dirtyPlates[data] == true
    counters.auraPasses = counters.auraPasses + 1
    data.auraOnly = only
    SafePlateUpdate(data, UpdatePlateAuras)
    data.auraOnly = nil
    if data.auraRowsLeft then auraWork.Queue(data) end
    if dirtyPlates[data] and not earlier then counters.auraReflows = counters.auraReflows + 1 end
    if not started then return end
    if dirtyPlates[data] then
        local flushed = Clock()
        FlushPlate(data)
        if PS.Performance then PS.Performance.RecordAuraPhase(earlier and "earlier" or "reflow", Clock() - flushed) end
    end
    local span = Clock() - started
    adds.spent = adds.spent + span
    if later and addPhases.Record then addPhases.Record("aurasLater", span) end
    -- Half a pass teaches no estimate (the whole one's is learnt from whole passes).
    if only then return end
    data.auraCost = span
    adds.Learn(fresh and "fresh" or "auras", span)
end

-- What a plate's aura pass is expected to cost: its own last pass, else the learnt cost of a pass
-- (one that makes the rows' first icons, when the plate has none yet); half that for the row a split
-- pass left.
function auraWork.Estimate(data)
    local cost = data.auraCost
    if not cost then cost = (data.buffIcons[1] or data.debuffIcons[1]) and adds.cost.auras or adds.cost.fresh end
    return data.auraRowsLeft and cost / 2 or cost
end

-- The frame's aura round: each queued plate's rows once, oldest first. budgeted (the frame's
-- ticker pass): after the frame's adds, while the next plate's expected cost fits what their budget
-- left (the first of a frame always runs), the rest the next frame. So while a burst of adds fills
-- frames their names come first and their auras right after, and no frame runs a plate's aura pass
-- the budget has no room for. force (starving): the first live pass runs even past the budget, so
-- overdue adds taking the frame cannot keep the auras back beyond the starvation guard.
function auraWork.Run(budgeted, force)
    local order, index = auraWork.order, 0
    while index < #order do
        local data = order[index + 1]
        local live = auraWork.pending[data] and data.unit and active[data.unit] == data
        if budgeted and live and not force and not adds.Fits(auraWork.Estimate(data)) then break end
        if live then force = false end
        index = index + 1
        if auraWork.pending[data] then
            auraWork.pending[data] = nil
            if live then auraWork.Read(data, budgeted) end
        end
    end
    local remaining = #order - index
    for position = 1, remaining do order[position] = order[position + index] end
    for position = remaining + 1, remaining + index do order[position] = nil end
end

-- A change of place lays out again only the plates whose design changed there (walking into a city
-- restyles the plate types with a city design, nothing else), oldest first under the frame's add budget,
-- never every plate in one frame. A plate waiting keeps its old design, so this comes after the adds;
-- one that is late (adds.LateSince) runs past the budget as the frame's overdue item while there is room.
-- adds.relayouts: plate records; data.relayoutFrame and relayoutMs: the frame and profiler clock it queued at.
adds.relayouts = {}
function adds.QueueRelayouts()
    local list, DesignFor = adds.relayouts, PS.PlateContext.DesignFor
    for unit, data in pairs(active) do
        if data.unit == unit and not data.relayoutFrame and DesignFor(data.profileKey) ~= data.design then
            data.relayoutFrame, data.relayoutMs = auraWork.frame, Clock()
            list[#list + 1] = data
        end
    end
end

function adds.RunRelayouts()
    local list, kept, stopped = adds.relayouts, 0, false
    for index = 1, #list do
        local data = list[index]
        if not (data.relayoutFrame and data.unit and active[data.unit] == data) then
            data = nil
        elseif PS.PlateContext.DesignFor(data.profileKey) == data.design then
            -- The place changed back before its turn.
            data.relayoutFrame, data = nil, nil
        elseif not stopped and not adds.Fits(adds.cost.relayout) then
            if adds.OverdueLeft() > 0 and adds.LateSince(data.relayoutFrame, data.relayoutMs) then
                adds.overdueRan = adds.overdueRan + 1
            else
                stopped = true
            end
        end
        if data then
            if stopped then
                kept = kept + 1
                list[kept] = data
            else
                local started = Clock()
                counters.contextPlates = counters.contextPlates + 1
                ApplyLayout(data)
                ApplySpotlightStyle(data)
                if dirtyPlates[data] then FlushPlate(data) end
                if started then
                    local span = Clock() - started
                    adds.spent = adds.spent + span
                    adds.Learn("relayout", span)
                end
            end
        end
    end
    for index = kept + 1, #list do list[index] = nil end
end

local function FrameTick(now)
    -- Plate adds a burst left over, within this frame's budget. First, adds that waited too long (a
    -- hidden name), then aura passes adds kept back (one even past the budget once starving).
    if adds.order[1] and adds.Overdue() then adds.Run() end
    if auraWork.Starving() then auraWork.Run(true, adds.spent > 0) end
    if adds.order[1] then adds.Run() end
    -- Bursty events set these flags; each is applied at most once per frame.
    -- Resting flips (PLAYER_UPDATE_RESTING) at a city's edge: the context is worked out once a frame, and
    -- after a change no sooner than CONTEXT_HOLD later, so walking along the edge (or bobbing on it) changes
    -- the place at most that often; plates whose design changed are laid out again a few a frame.
    if pending.context and now >= pending.contextAt then
        pending.context = false
        if PS.PlateContext.Refresh("resting") then
            pending.contextAt = now + LIMITS.CONTEXT_HOLD
            counters.contextRelayouts = counters.contextRelayouts + 1
            -- Into a city: its crowd's nameplates come next, so the spares are built ahead of them.
            if PS.PlateContext.Current() == "city" then PlateParts.Warm(now) end
            RefreshAllNow(true, true)
        end
    end
    if adds.relayouts[1] then adds.RunRelayouts() end
    if pending.kinds then
        pending.kinds = false
        changes.UnitKinds()
    end
    if pending.relationships and now >= pending.relationshipsAt then
        pending.relationships, pending.relationshipsAt = false, now + LIMITS.RELATIONSHIP_INTERVAL
        changes.Relationships()
    end
    if pending.auras and now >= pending.aurasAt then
        pending.auras, pending.aurasAt = false, now + AURA_EVENT_INTERVAL
        for unit, data in pairs(active) do
            if data.unit == unit and data.aurasWanted then auraWork.Queue(data) end
        end
    end
    if auraWork.order[1] then auraWork.Run(true) end
    -- A token that can stand in for a withheld marker changed: the target, focus or mouseover (every
    -- stand-in resolved again, at most every RAID_FALLBACK_INTERVAL), or a group member's target
    -- (only that token tested, pending.raidTokens).
    if pending.raidFallback and now >= pending.raidFallbackAt then
        pending.raidFallback, pending.raidFallbackAt = false, now + LIMITS.RAID_FALLBACK_INTERVAL
        for token in pairs(pending.raidTokens) do pending.raidTokens[token] = nil end
        for unit, data in pairs(active) do
            if data.unit == unit and data.raidIconNeedsFallback then SafePlateUpdate(data, UpdateRaidIcon) end
        end
    elseif next(pending.raidTokens) then
        for unit, data in pairs(active) do
            if data.unit == unit and data.raidIconNeedsFallback then
                for token in pairs(pending.raidTokens) do
                    if RaidMarker.TokenChanged(data, token) then
                        SafePlateUpdate(data, UpdateRaidIcon)
                        break
                    end
                end
            end
        end
        for token in pairs(pending.raidTokens) do pending.raidTokens[token] = nil end
    end
    if pending.quests and now >= pending.questsAt then
        pending.quests = false
        pending.questsAt = now + QUEST_REFRESH_INTERVAL
        if type(PS.ForEachModule) == "function" then PS:ForEachModule("OnQuestLogChanged", pending.questEvent) end
        RefreshQuestMarkersNow()
    end
    if next(activeCasts) then UpdateCastTimes(now) end
end

-- Plate work is split by cadence; each entry is visible in the Ticker report.
PS.Ticker.Register("plates.frame", 0, function(_, now)
    if not db then return end
    -- The frame's first entry runs outside any batch; one left open by an error closes here.
    batchDepth, rounds.backstop = 0, false
    adds.Frame(true)
    RunBatch(false, FrameTick, now)
end)

-- Health and power update from their unit events; this slower pass only
-- catches a value whose event the client withheld, so an unchanged readable value costs nothing.
local function HealthTick()
    rounds.backstop = true
    for unit, data in pairs(active) do
        if data.unit == unit and not data.namesOnly then
            SafePlateUpdate(data, UpdateHealth)
            SafePlateUpdate(data, UpdatePower)
        end
    end
    rounds.backstop = false
end
PS.Ticker.Register("plates.health", HEALTH_BACKSTOP_INTERVAL, function()
    if db then RunBatch(false, HealthTick) end
end)

-- Blizzard's native frames on owned plates: the hooks restore them at once; this catches a miss,
-- a few plates a pass in turn.
PS.Ticker.Register("plates.native", LIMITS.NATIVE_INTERVAL, function()
    if not db then return end
    for _ = 1, math.min(LIMITS.NATIVE_PLATES_PER_PASS, #rounds.native) do
        rounds.nativeCursor = rounds.nativeCursor % #rounds.native + 1
        KeepNativeHidden(rounds.native[rounds.nativeCursor])
    end
end)

-- Builds spares while the attached plates and spares are fewer than SpareTarget, then native aura
-- containers while the pool wants one (one a pass), and switches itself off when both are full
-- (TakeSpare, WarmLater and a container taken from the pool switch it on again).
PS.Ticker.Register("plates.spares", LIMITS.SPARE_INTERVAL, function(_, now)
    local spares = PlateParts.spares
    local platesFull = PlateParts.attached + #spares >= PlateParts.SpareTarget(now)
    local containers = auraWork.containers
    if not (db and db.enabled) or (platesFull and not (containers and containers.Wanted(now))) then
        PS.Ticker.SetInterval("plates.spares", LIMITS.SPARE_INTERVAL)
        PS.Ticker.SetEnabled("plates.spares", false)
        return
    end
    -- Warmed and short of the target: every frame that is idle enough, not every SPARE_INTERVAL.
    PS.Ticker.SetInterval("plates.spares", not platesFull and now < PlateParts.warmUntil and 0 or LIMITS.SPARE_INTERVAL)
    -- Only out of combat, with no add waiting, in a frame that has built nothing and whose plate work (adds
    -- and aura reads: adds.spent is the frame's) came to less than SPARE_IDLE_MS, or SPARE_IDLE_SHARE of the
    -- last frame's length (at 15 fps a frame's plate work is a smaller share of it), up to the add budget.
    -- Its own time counts in the frame's plate work too.
    adds.Frame(false)
    local idle = math.min(LIMITS.ADD_BUDGET_MS, math.max(LIMITS.SPARE_IDLE_MS, (adds.frameMs or 0) * LIMITS.SPARE_IDLE_SHARE))
    if now < PlateParts.warmAt or adds.order[1] or adds.built or adds.spent >= idle or Secret.InCombat() then return end
    if platesFull then
        if not containers.Build(now) then PS.Ticker.SetEnabled("plates.spares", false) end
        return
    end
    local started = Clock()
    if PlateParts.BuildHalf() then counters.sparesBuilt = counters.sparesBuilt + 1 end
    adds.built = true
    if started then adds.spent = adds.spent + Clock() - started end
end)
PS.Ticker.SetEnabled("plates.spares", false)

-- The spotlight's pulse (and the arrow's bob) runs only while a spotlight shows.
PS.Ticker.Register(SPOTLIGHT_TICKER, 0.03, function(_, now)
    local showing = false
    if db then
        local glow, arrow = db.threatSpotlightStyle == "glow", db.threatSpotlightStyle == "arrow"
        for _, data in pairs(active) do
            if data.beaconUntil then
                if now >= data.beaconUntil then
                    data.beaconUntil = nil
                    data.beacon:Hide()
                else
                    showing = true
                    local wave = math.sin(now * (glow and 4 or 7))
                    data.beacon:SetAlpha(glow and (0.6 + 0.2 * (1 + wave)) or (0.45 + 0.55 * math.abs(wave)))
                    if arrow then SetSpotlightArrow(data, 3 * math.abs(math.sin(now * 5))) end
                end
            end
        end
    end
    if not showing then PS.Ticker.SetEnabled(SPOTLIGHT_TICKER, false) end
end)
PS.Ticker.SetEnabled(SPOTLIGHT_TICKER, false)

local ANIMATION_TICKER = "plates.animation"
function rounds.SyncAnimation()
    local wanted = next(rounds.pulses) ~= nil or spotlightUnit ~= nil or spotlightDimmed == true
    if rounds.animating ~= wanted then
        rounds.animating = wanted
        PS.Ticker.SetEnabled(ANIMATION_TICKER, wanted)
    end
end

PS.Ticker.Register(ANIMATION_TICKER, 0.10, function(_, now)
    if not db then return end
    for data in pairs(rounds.pulses) do
        if data.targetPulseActive and data.unit and active[data.unit] == data then
            local alpha = 0.25 + (0.45 * (0.5 + 0.5 * math.sin(now * 3)))
            for _, glow in ipairs(data.targetBarGlows or EMPTY) do glow.pulse:SetAlpha(alpha) end
            SetTargetTextGlow(data, 0.4 + alpha * 0.6, true)
        else
            rounds.pulses[data] = nil
        end
    end
    -- Switches the entry off once nothing pulses or dims.
    UpdateSpotlight(now)
end)
PS.Ticker.SetEnabled(ANIMATION_TICKER, false)
rounds.animating = false

-- Time-based plate work (threat, TAGGED) with no reliable event: each plate that has any is
-- visited at most every STATE_INTERVAL, at most STATE_PLATES_PER_FRAME a frame, so no frame's pass
-- grows with the plate count. Values, rules and stacks follow only what changed. The highlighted
-- plate is visited too: labels shown since pick up its glow, and a target change the client did not
-- announce takes the highlight down. rounds.clock is the pass's own time (the ticker's elapsed).
local function StateTick(elapsed)
    local now = rounds.clock + (elapsed or 0)
    rounds.clock = now
    local count = #rounds.state
    local visited, done = 0, 0
    while visited < count and done < LIMITS.STATE_PLATES_PER_FRAME and #rounds.state > 0 do
        visited = visited + 1
        rounds.stateCursor = rounds.stateCursor % #rounds.state + 1
        local data = rounds.state[rounds.stateCursor]
        if now >= data.stateDueAt then
            data.stateDueAt, done = now + LIMITS.STATE_INTERVAL, done + 1
            SafePlateUpdate(data, UpdateThreat)
            SafePlateUpdate(data, UpdateTagged)
        end
    end
    local target = rounds.targetPlate
    if target and now >= rounds.targetDueAt then
        rounds.targetDueAt = now + LIMITS.STATE_INTERVAL
        if target.unit and active[target.unit] == target then
            SafePlateUpdate(target, UpdateTarget)
        else
            rounds.targetPlate = nil
        end
    end
end
PS.Ticker.Register("plates.state", 0, function(elapsed)
    if db and (rounds.state[1] or rounds.targetPlate) then RunBatch(false, StateTick, elapsed) end
end)

-- Auras follow UNIT_AURA; this pass reads again only rows whose soonest timed aura has run out
-- (some clients send no event then) or whose read is unsettled, and turns itself off when no plate
-- has such a row.
local function AuraTick(now)
    for data in pairs(auraWork.polls) do
        if not (data.unit and active[data.unit] == data) then
            auraWork.polls[data] = nil
        elseif AurasNeedPoll(data, now) then
            SafePlateUpdate(data, UpdatePlateAuras)
        end
    end
end
PS.Ticker.Register(auraWork.ticker, 0.75, function(_, now)
    if db then RunBatch(false, AuraTick, now) end
    if next(auraWork.polls) == nil then
        auraWork.tickerOn = false
        PS.Ticker.SetEnabled(auraWork.ticker, false)
    end
end)

local eventFrame = CreateFrame("Frame")
local coreEvents = {
    "PLAYER_LOGIN",
    "ADDON_LOADED",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "UNIT_TARGET",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_LOGOUT",
    "GROUP_ROSTER_UPDATE",
    "UNIT_FACTION",
    "UNIT_FLAGS",
    "UNIT_NAME_UPDATE",
    "UNIT_LEVEL",
    "PLAYER_FLAGS_CHANGED",
    "UNIT_CLASSIFICATION_CHANGED",
    "GUILD_ROSTER_UPDATE",
    "PLAYER_GUILD_UPDATE",
    "FRIENDLIST_UPDATE",
    "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_LIST_SIZE_CHANGED",
    "RAID_TARGET_UPDATE",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_AURA",
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_UPDATE_RESTING",
}
for index = 1, #coreEvents do
    PS._RegisterEvent(eventFrame, coreEvents[index], "platesmith.nameplates")
end

-- Per-unit events that come in bursts: their plate work waits for the frame's flush.
local DEFERRED_EVENTS = {
    UNIT_AURA = true, UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true,
    UNIT_NAME_UPDATE = true, UNIT_LEVEL = true, UNIT_FLAGS = true,
    UNIT_TARGET = true, UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
}
local HEALTH_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true }
local POWER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true }
local SOCIAL_EVENTS = { GROUP_ROSTER_UPDATE = true, GUILD_ROSTER_UPDATE = true, PLAYER_GUILD_UPDATE = true,
    FRIENDLIST_UPDATE = true, BN_FRIEND_INFO_CHANGED = true, BN_FRIEND_LIST_SIZE_CHANGED = true }
local UNIT_CHANGE_EVENTS = { UNIT_FACTION = true, PLAYER_FLAGS_CHANGED = true, UNIT_CLASSIFICATION_CHANGED = true }
local CAST_TIMING_EVENTS = { UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true }

-- Unit events reach the addon for every group member, the target, focus and more. One for a readable
-- token that has no plate is dropped in OnEvent, before the profiler clock and the batch, unless the
-- token can stand in for a plate (the target's auras, a group member's target, the player's flags):
-- byEvent[event][unit] says the token has no use for that event. Each answer is worked out once per
-- token (the client's token set is bounded). Protected tokens take the full path.
local unitFilters = {}
do
    local function Memo(test)
        return setmetatable({}, { __index = function(cache, unit)
            local answer = test(unit) and true or false
            cache[unit] = answer
            return answer
        end })
    end
    local always = setmetatable({}, { __index = function() return true end })
    -- A group member's own token (its plate gets its nameplate event), the player's or a pet's.
    local noAuraStandIn = Memo(function(unit)
        return unit:find("^nameplate%d") or unit:find("^raid") or unit:find("^party") or unit == "player" or unit == "pet"
    end)
    unitFilters.candidates = Memo(RaidMarker.IsCandidateSource)
    local notCandidate = Memo(function(unit) return not unitFilters.candidates[unit] end)
    local plateToken = Memo(function(unit) return unit:find("^nameplate") end)
    unitFilters.byEvent = {
        UNIT_HEALTH = always, UNIT_MAXHEALTH = always, UNIT_POWER_UPDATE = always, UNIT_MAXPOWER = always,
        UNIT_NAME_UPDATE = always, UNIT_LEVEL = always, UNIT_FLAGS = always,
        UNIT_SPELLCAST_START = always, UNIT_SPELLCAST_STOP = always, UNIT_SPELLCAST_FAILED = always,
        UNIT_SPELLCAST_INTERRUPTED = always, UNIT_SPELLCAST_DELAYED = always, UNIT_SPELLCAST_CHANNEL_START = always,
        UNIT_SPELLCAST_CHANNEL_STOP = always, UNIT_SPELLCAST_CHANNEL_UPDATE = always,
        UNIT_AURA = noAuraStandIn, UNIT_TARGET = notCandidate,
        -- Another token (the target, a group member) can name a plate's unit; a nameplate token cannot.
        UNIT_FACTION = plateToken, UNIT_CLASSIFICATION_CHANGED = plateToken,
    }
end

-- The owned plate for a plain unit token, if it has one.
local function PlateFor(unit)
    if not IsReadable(unit) or type(unit) ~= "string" then return nil end
    return active[unit]
end

-- UNIT_AURA for a token that is not a plate's own (target, focus, boss): its plate, if any.
-- Group members' own plates receive their nameplate event.
local function AuraStandIn(unit)
    if unit:find("^nameplate%d") or unit:find("^raid") or unit:find("^party") or unit == "player" or unit == "pet" then
        return nil
    end
    local root = RaidMarker.PlateRoot(unit)
    local data = root and root.PlateSmithData
    if data and data.unit and active[data.unit] == data then return data end
end

local function HandleLogin()
    db = PS.Profiles.Load()
    PlateSmithCharacterDB = NormalizeCharacterSettings(PlateSmithCharacterDB)
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    NamePolicy.Apply()
    DiagnosticUI.EnsureWindow()
    PS.DiagnosticHistory.InstallErrorCapture(BuildDiagnosticReport)
    if PS.CreateOptions then PS.CreateOptions() end
    if PS.EnableModules then PS:EnableModules() end
    ApplyNativeNameFont()
    ScanPlates()
    PlateParts.WarmLater()
    PS.Chat.Print(string.format(PS.L["loaded %s. Type /platesmith status for the active mode."], tostring(PS.RUNTIME_BUILD)))
end

local function HandleEvent(event, unit)
    if event == "PLAYER_LOGIN" then
        HandleLogin()
    elseif event == "ADDON_LOADED" then
        -- Another nameplate addon may have loaded (mode auto).
        PS.Conflicts.ForgetProvider()
    elseif not db then
        return
    elseif HEALTH_EVENTS[event] then
        local data = PlateFor(unit)
        if data then SafePlateUpdate(data, UpdateHealth) end
    elseif POWER_EVENTS[event] then
        local data = PlateFor(unit)
        if data then SafePlateUpdate(data, UpdatePower) end
    elseif event == "UNIT_AURA" then
        if not IsReadable(unit) or type(unit) ~= "string" then
            -- Restricted aura events may carry a protected unit token. Refresh visible rows,
            -- at most every AURA_EVENT_INTERVAL, without branching or indexing on that token.
            pending.auras = true
        else
            -- Read once in the frame's flush, and only for a plate that shows an aura row.
            local data = active[unit] or AuraStandIn(unit)
            if data and data.aurasWanted then auraWork.Queue(data) end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        adds.Request(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        RemovePlate(unit)
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
        local data = PlateFor(unit)
        if data then SafePlateUpdate(data, UpdateIdentity) end
    elseif event == "UNIT_FLAGS" then
        local data = PlateFor(unit)
        if data then SafePlateUpdate(data, changes.UnitFlags) end
    elseif UNIT_CHANGE_EVENTS[event] then
        if not IsReadable(unit) or unit == "player" then
            -- The player's own flags change how every other unit reacts.
            pending.kinds = true
        elseif type(unit) == "string" then
            if active[unit] then
                changes.UnitKind(active[unit])
            elseif not unit:find("^nameplate") then
                -- Another token (target, a group member) for a plate's unit.
                for plateUnit, data in pairs(active) do
                    if data.unit == plateUnit and SameUnit(plateUnit, unit) then changes.UnitKind(data) end
                end
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if rounds.testNamePlate then rounds.SetTestName(nil) end
        RefreshTargetState()
        pending.raidFallback = true
    elseif SOCIAL_EVENTS[event] then
        if event == "GROUP_ROSTER_UPDATE" then RaidMarker.InvalidateCandidates() end
        pending.relationships = true
    elseif event == "RAID_TARGET_UPDATE" then
        for plateUnit, data in pairs(active) do
            if data.unit == plateUnit then SafePlateUpdate(data, UpdateRaidIcon) end
        end
    elseif event == "UNIT_TARGET" then
        -- A plate's unit changed target: its target-of-target name follows, and what reads it.
        local data = PlateFor(unit)
        if data then SafePlateUpdate(data, changes.UnitTarget) end
        -- A group member's target is a token that can reveal a withheld marker: only that token is
        -- tested. A protected token could be any of them.
        if not IsReadable(unit) then
            pending.raidFallback = true
        elseif unitFilters.candidates[unit] then
            pending.raidTokens[Secret.TargetToken(unit)] = true
        end
    elseif event == "PLAYER_FOCUS_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        pending.raidFallback = true
        if event == "PLAYER_FOCUS_CHANGED" then PS.Stacking.FocusChanged() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        PS.Conflicts.ForgetProvider()
        RaidMarker.InvalidateCandidates()
        NamePolicy.ZoneChanged()
        PS.PlateContext.Refresh("zone")
        NamePolicy.Apply()
        RefreshAllNow(true)
        ScanPlates()
        PlateParts.WarmLater()
    elseif event == "PLAYER_REGEN_ENABLED" then
        NamePolicy.FlushPending()
        -- Aura reads that errored during combat are tried again.
        for plateUnit, data in pairs(active) do
            if data.unit == plateUnit and (data.buffsIndexError or data.debuffsIndexError) then
                data.buffsIndexError, data.debuffsIndexError = nil, nil
                if data.aurasWanted then auraWork.Queue(data) end
            end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Plates up across a change of context (into or out of a dungeon, a battleground, a city) are
        -- laid out again for it: those whose design changed, a few a frame; every plate when the
        -- dungeon check flipped (friendly plates become Blizzard's). Blizzard's friendly names follow it.
        local wasInstance = NamePolicy.InGroupInstance()
        NamePolicy.ZoneChanged()
        local flipped = NamePolicy.InGroupInstance() ~= wasInstance
        if PS.PlateContext.Refresh("zone") or flipped then
            if PS.PlateContext.Current() == "city" then PlateParts.Warm(GetTime()) end
            if flipped then NamePolicy.Apply() end
            counters.contextRelayouts = counters.contextRelayouts + 1
            RefreshAllNow(true, not flipped)
        end
    elseif event == "PLAYER_UPDATE_RESTING" then
        pending.context = true
    elseif event == "PLAYER_LOGOUT" then
        -- A /reload in combat: the writes are tried, but one the client blocks fails unseen, so the
        -- records are kept for the next login to put back.
        NamePolicy.RestoreAll(Secret.InCombat())
        NamePolicy.FlushPending()
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" then
        -- Providers get QUEST_LOG_UPDATE when one arrived in the window, so a watch-list-only change can be skipped.
        local logSeen = pending.quests and pending.questEvent == "QUEST_LOG_UPDATE"
        pending.quests, pending.questEvent = true, logSeen and "QUEST_LOG_UPDATE" or event
    else
        local data = PlateFor(unit)
        if data then SafePlateUpdate(data, CAST_TIMING_EVENTS[event] and UpdateCastTiming or UpdateCast) end
    end
end

-- Each handler's time goes to the diagnostics' per-event table (performance.events), measured with
-- the profiler clock the ticker already uses. A plate add is timed as new (its frame was built),
-- queued (left for a later frame) or reused, so first builds do not hide in the reuse average.
do
    local RecordEvent = PS.Performance and PS.Performance.RecordEvent
    local PLATE_ADDED = PS.Performance and PS.Performance.PLATE_ADDED
    local byEvent = unitFilters.byEvent
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        local ignored = byEvent[event]
        if ignored and IsReadable(unit) and type(unit) == "string" and not active[unit] and ignored[unit] then return end
        local started = RecordEvent and Clock()
        local built, spared, queued = counters.platesBuilt, counters.sparesUsed, counters.deferredAdds
        RunBatch(DEFERRED_EVENTS[event] == true, HandleEvent, event, unit)
        if started then
            local name = event
            if event == "NAME_PLATE_UNIT_ADDED" then
                -- New: a nameplate seen for the first time, whether its plate was built or a spare.
                name = (counters.platesBuilt ~= built or counters.sparesUsed ~= spared) and PLATE_ADDED.new
                    or counters.deferredAdds ~= queued and PLATE_ADDED.queued or PLATE_ADDED.reused
            end
            RecordEvent(name, Clock() - started)
        end
    end)
end

PS.Refresh = RefreshAll
PS.RefreshQuestMarkers = RefreshQuestMarkers
PS.GetSettings = GetSettings
PS.SetOption = PlateSettings.SetOption
PS.GetLayout = PlateSettings.GetLayout
PS.SetLayout = PlateSettings.SetLayout
PS.SetComponentPosition = PlateSettings.SetComponentPosition
PS.SetComponentScale = PlateSettings.SetComponentScale
PS.SetSettingsDrag = PlateSettings.SetSettingsDrag
PS.SetComponentAttach = PlateSettings.SetComponentAttach
PS.SetComponentVisibility = PlateSettings.SetComponentVisibility
PS.SetPartShownEverywhere = PlateSettings.SetPartShownEverywhere
PS.GetPartShownState = PlateSettings.GetPartShownState
PS.PlateNeeds = PlateNeeds
PS.SetComponentAnchor = PlateSettings.SetComponentAnchor
for _, name in ipairs({ "CreateComponentGroup", "RenameComponentGroup", "SetComponentGroup", "SetComponentGroupOffset",
    "SetComponentGroupScale", "SetComponentParent", "MoveComponentGroupTo",
    "RemoveComponent", "RestoreComponent", "ResetComponent", "SetComponentStack", "SetComponentFree", "SetComponentLayer",
    "RenameComponent", "SetLayoutMeasure", "MoveComponentGroup", "DeleteComponentGroup", "ComponentGroupKeys",
    "GetPlateProfileSettings", "GetDungeonEnemyOverride", "SetDungeonEnemyProfile", "GetDefaultLayout",
    "SetPlateProfileOption", "CopyTargetHighlight", "SetPlateValueSlot", "SetPlateValueSlotFields", "SetPlateAuraLayout", "SetPartRules",
    "GetFadeState", "SetFadeEverywhere", "SetFadeAlpha",
    "SetPartStyle", "ResetValueSlot", "SaveStylePreset", "DeleteStylePreset", "ApplyStylePreset", "SetPlateProfileHealthColour",
    "SetRelationshipColour", "SetThreatColour", "SetThreatPartOwnColours", "GetCharacterSettings", "SetCharacterOption",
    "ResetSettings", "AddDesign", "RemoveDesign", "ResetDesign", "ResetDesignArea", "SlimDesign", "CopyDesign",
    "FreeValueSlot" }) do
    PS[name] = PlateSettings[name]
end
PS.ApplyNameplateFont = ApplyNameplateFont
-- Whether PlateSmith draws a unit's plate, so Blizzard's own name there is hidden (NativeFonts asks).
PS.PlateDrawsUnit = adds.Drawn
-- A part's text in its style (font, Font size, outline, shadow), for parts drawn outside this file.
PS.StyledPartFont = Styles.StyledFont
PS.ApplyThreatText = ApplyThreatText
PS.HighlightPlate = HighlightPlate
PS.ExternalProvider = ExternalProvider
PS.Diagnose = Diagnose
PS.ProbePlayerPlate = ProbePlayerPlate
PS.SetTestName = rounds.SetTestName
PS._Test = {
    Abbreviate = PS.Format.Abbreviate,
    FormatThreat = ThreatText.Readable,
    FormatThreatRecord = ThreatText.Record,
    ApplyThreatText = ApplyThreatText,
    IsReadable = IsReadable,
    NormalizeSettings = S.NormalizeSettings,
    QuestRelevance = QuestRelevance,
    FriendlyRelationship = PlateIdentity.FriendlyRelationship,
    SafeColourForUnit = SafeColourForUnit,
    UnitDisplayNameValue = UnitDisplayNameValue,
    ProfileKeyForUnit = PlateIdentity.ProfileKeyForUnit,
    ResolveRaidTargetIndex = RaidMarker.Resolve,
    AuraProbe = AuraProbe,
    FlushPlates = FlushDirty,
    Counters = counters,
    Limits = LIMITS,
    PendingAdds = function() return #adds.order end,
    PendingAuras = function() return #auraWork.order end,
    -- What the next add, build or aura pass is expected to cost (ms), as the budget judges them.
    ItemCosts = adds.cost,
    ItemBases = adds.base,
    LearnCost = adds.Learn,
    -- Plates waiting to be laid out again for a change of place.
    PendingRelayouts = function() return #adds.relayouts end,
    -- The frame's plate work so far (ms), as the spares pass reads it.
    FrameSpent = function(ms)
        if ms then adds.spent = ms end
        return adds.spent
    end,
    Spares = PlateParts.spares,
    -- The native aura containers made ahead (Auras.lua's pool).
    ContainerPool = auraWork.containers,
    -- The spare bookkeeping (attached, partial, SpareTarget).
    PlateParts = PlateParts,
    -- This frame's UNIT_AURA reads, as the frame's first ticker entry does them (the plates' flush
    -- still waits, as it does for the deferred events).
    FlushAuras = function() RunBatch(true, auraWork.Run) end,
    -- Every part of one plate marked and flushed: a flush's full cost.
    FlushPlateNow = function(data)
        MarkValues(data, "all")
        MarkStacks(data)
        FlushDirty()
    end,
    TemplateRead = function(data, token)
        Readers.Begin(data)
        return Readers.Get(data)(token)
    end,
    -- Where the parts are drawn now (a pinned part follows its text live, without a re-layout).
    PlateTransforms = function(data)
        data.layoutTransforms = nil
        return Transforms(data.layout, data)
    end,
    PlateSize = function(region) return SafeSize(region) end,
    Range = rounds.range,
    Combo = rounds.combo,
    TargetGlow = rounds.targetGlow,
    -- The names-only cast bar (Placement's NameCast), for the store shot of it.
    NameCast = rounds.nameCast,
    TargetedBy = rounds.targetedBy,
}
