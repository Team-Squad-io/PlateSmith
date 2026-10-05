-- Where the player is, as a context design key, and which design each plate type draws with here.
-- Precedence: battlegrounds & arenas, then dungeons & raids, then cities & inns, then World.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local NamePolicy = assert(PS.NamePolicy, "PlateSmith NamePolicy missing")
local Designs = assert(PS.Designs, "PlateSmith Designs missing")

local PlateContext = {}
PS.PlateContext = PlateContext

-- context: the active context, nil until first asked. resting: true, false or "unknown".
-- evaluations: how many times the context was worked out (diagnostics and the performance guards).
local state = { context = nil, resting = "unknown", changes = 0, lastAt = nil, lastCause = nil, evaluations = 0 }
PlateContext.state = state

-- DesignFor's answers for the active context and Designs.revision: at most one key per plate type.
local designs = { context = nil, revision = nil, db = nil, byType = {} }

-- IsResting through pcall: unreadable, failing or missing reads "unknown", which counts as not resting.
-- Older clients answer 1 or nil.
local function ReadResting()
    if type(IsResting) ~= "function" then return "unknown" end
    local ok, resting = pcall(IsResting)
    if not ok or not Secret.IsReadable(resting) then return "unknown" end
    return resting == true or resting == 1
end

-- City needs a readable "not in an instance"; an unknown instance type is World. Scenarios and delves
-- are World too, as InGroupInstance has always said.
local function Evaluate()
    state.evaluations = state.evaluations + 1
    local kind = NamePolicy.InstanceType()
    state.resting = ReadResting()
    if kind == "pvp" or kind == "arena" then return "pvp" end
    if NamePolicy.InGroupInstance() then return "dungeon" end
    if state.resting == true and kind == "none" then return "city" end
    return "world"
end

function PlateContext.Current()
    if state.context == nil then state.context = Evaluate() end
    return state.context
end

-- Works the context out again (after a zone or resting change). Returns whether it changed from
-- what plates were drawn for; the first answer is no change, since nothing was drawn for an earlier one.
-- cause: "zone" or "resting", for diagnostics.
function PlateContext.Refresh(cause)
    local previous = state.context
    local context = Evaluate()
    state.context = context
    if previous == nil or previous == context then return false end
    state.changes = state.changes + 1
    state.lastAt = type(GetTime) == "function" and GetTime() or nil
    state.lastCause = cause or "zone"
    return true
end

local function Settings() return type(PS.GetSettings) == "function" and PS.GetSettings() or nil end

-- The design plateType draws with here: the active context when the type has a design for it (a
-- friendly type always has Dungeons & raids, Blizzard's), else "world". O(1): kept per context and
-- settings revision. db: other settings than the live ones (worked out, not kept).
function PlateContext.DesignFor(plateType, db)
    local context = PlateContext.Current()
    if context == "world" then return "world" end
    local live = Settings()
    if db ~= nil and db ~= live then
        return Designs.HasDesign(db, plateType, context) and context or "world"
    end
    local byType = designs.byType
    if designs.context ~= context or designs.revision ~= Designs.revision or designs.db ~= live then
        for key in pairs(byType) do byType[key] = nil end
        designs.context, designs.revision, designs.db = context, Designs.revision, live
    end
    local design = byType[plateType]
    if design == nil then
        design = Designs.HasDesign(live, plateType, context) and context or "world"
        byType[plateType] = design
    end
    return design
end

-- /ps diagnose's designs section (with Designs.Report's resolver counters and designs).
function PlateContext.Report()
    local lastChange = "none"
    if state.changes > 0 then
        local now = type(GetTime) == "function" and GetTime() or nil
        lastChange = {
            cause = state.lastCause or "unknown",
            secondsAgo = (now and state.lastAt) and math.floor((now - state.lastAt) * 10 + 0.5) / 10 or "unknown",
        }
    end
    return {
        context = PlateContext.Current(), instanceType = NamePolicy.InstanceType() or "unknown",
        resting = state.resting, contextChanges = state.changes, lastContextChange = lastChange,
        evaluations = state.evaluations,
    }
end
