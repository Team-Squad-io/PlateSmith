-- Threat colours: the colour an enemy's health bar, name or health bar edge takes for its threat
-- state (Schema's colourByThreat and threatColour* settings), from the same record and reading as
-- the plate's threat text (PlateState). With only protected answers, the colour is picked inside the
-- client (FoldForPlate), as the text's colour is. A rule's colour on the part wins (Lifecycle's
-- ApplyPartRules); an unknown state or role, a unit not in combat with you or your group, or Safe
-- while it keeps the part's colour leaves the part's own colour. Studio's preview resolves the same
-- way from its test values.
local _, PS = ...
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local ThreatText = assert(PS.ThreatText, "PlateSmith ThreatText missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")

local ThreatColours = {}
PS.ThreatColours = ThreatColours

-- Each part's Apply to setting. The edge is the health bar's border, not a part; rules colour the others.
local PART_SETTINGS = { health = "threatColourHealth", name = "threatColourName", border = "threatColourBorder" }
ThreatColours.PART_SETTINGS = PART_SETTINGS
ThreatColours.RULE_PARTS = { "health", "name" }
ThreatColours.STATES, ThreatColours.PARTS = S.THREAT_COLOURS.STATES, S.THREAT_COLOURS.PARTS
ThreatColours.TANK_STATES = { "holding", "losing", "offtank", "other" }
ThreatColours.DPS_STATES = { "safe", "pulling", "aggro" }

-- Whether settings colour anything by threat, and whether they colour part.
function ThreatColours.Enabled(settings)
    if type(settings) ~= "table" or settings.colourByThreat ~= true then return false end
    for _, key in pairs(PART_SETTINGS) do
        if settings[key] == true then return true end
    end
    return false
end

function ThreatColours.Applies(settings, part)
    local key = PART_SETTINGS[part]
    return key ~= nil and type(settings) == "table" and settings.colourByThreat == true and settings[key] == true
end

-- The soft target glow's Threat colour mode asks as part "glow": it takes the shared colours whenever its
-- mode asks, whether or not Threat colours colours the bars.
ThreatColours.GLOW = "glow"
local function Asks(settings, part)
    if part == ThreatColours.GLOW then return type(settings) == "table" end
    return ThreatColours.Applies(settings, part)
end

-- The state for a role from three-valued facts (fact(name): true, false or nil). A tank: losing
-- (holding it, about to lose it), holding, another tank has it, someone else has it. A DPS or healer:
-- aggro (holding it), pulling, safe (someone else holds it). nil while the facts say none of these.
function ThreatColours.State(tank, fact)
    if tank then
        if fact("holding") == true then return fact("losing") == true and "losing" or "holding" end
        if fact("offtank") == true then return "offtank" end
        if fact("other") == true then return "other" end
        return nil
    end
    if fact("holding") == true then return "aggro" end
    if fact("pulling") == true then return "pulling" end
    if fact("other") == true then return "safe" end
    return nil
end

-- Whether the colours are a tank's: the profile's Role, or (Auto) what role.tank reads; nil when
-- Auto and the role is unknown.
function ThreatColours.IsTank(settings, autoTank)
    local role = settings.threatColourRole
    if role == "tank" then return true end
    if role == "dps" then return false end
    return autoTank()
end

-- The player's role as the role.tank condition reads it (the threat service's GetPlayerRole).
local function PlayerTanks()
    local service = PS.ThreatService
    if type(service) ~= "table" or type(service.GetPlayerRole) ~= "function" then return nil end
    local ok, role = pcall(service.GetPlayerRole, service)
    if ok and Secret.IsReadable(role) and type(role) == "string" then return role == "TANK" end
    return nil
end
ThreatColours.PlayerTanks = PlayerTanks

-- The colour ({ r, g, b }) for state on part: the part's own while Own colours is on, else the
-- shared one; nil for no state, and for Safe while Safe keeps the part's colour.
function ThreatColours.Colour(settings, part, state)
    if state == nil or (state == "safe" and settings.threatColourSafeKeep == true) then return nil end
    local own = type(settings.threatPartColours) == "table" and settings.threatPartColours[part]
    local colour = type(own) == "table" and own[state]
    if type(colour) ~= "table" then colour = type(settings.threatColours) == "table" and settings.threatColours[state] end
    if type(colour) == "table" then return colour end
    return nil
end

-- A plate's facts read from its engaged threat record, without a closure per call.
local FACTS = ThreatText.Facts
local plateInfo
local function PlateFact(name) return FACTS[name](plateInfo) end

local function Settings()
    return type(PS.GetSettings) == "function" and PS.GetSettings() or nil
end

-- Whether a plate can take threat colours now: an owned enemy plate in combat with you or your
-- group (an engaged threat record), with Threat colours on.
function ThreatColours.Wanted(data)
    local info = data.threatInfo
    return data.own == true and data.friendly == false and type(info) == "table" and info.engaged == true
        and ThreatColours.Enabled(Settings())
end

-- The state a plate's record says, from the facts its threat text is coloured by (ThreatText.Facts:
-- isTanking, else the threat status, else the scaled percent, else the mob's own readable target;
-- the threat service's kept read for its hold included). nil while unknown.
local function PlateState(tank, info)
    plateInfo = info
    local ok, state = pcall(ThreatColours.State, tank, PlateFact)
    plateInfo = nil
    if not ok then return nil end
    return state
end
ThreatColours.PlateState = PlateState

-- Settings, record and role for a plate's part, or nil when it takes no threat colour.
local function PlateContext(data, part)
    local settings = Settings()
    if not Asks(settings, part) or data.own ~= true or data.friendly ~= false then return nil end
    local info = data.threatInfo
    if type(info) ~= "table" or info.engaged ~= true then return nil end
    local tank = ThreatColours.IsTank(settings, PlayerTanks)
    if tank == nil then return nil end
    return settings, info, tank
end

-- A plate's threat colour for part ({ r, g, b }), or nil: the part keeps its own colour (or takes
-- a folded one: FoldForPlate).
function ThreatColours.ForPlate(data, part)
    local settings, info, tank = PlateContext(data, part)
    if not settings then return nil end
    return ThreatColours.Colour(settings, part, PlateState(tank, info))
end

-- One step of a fold inside the client (Secret.Pick, channel by channel): colour when the flag
-- (protected) is true, else r, g, b (themselves possibly protected). True and the new r, g, b.
local function FoldStep(flag, colour, r, g, b)
    local okR, nr = Secret.Pick(flag, colour.r, r)
    local okG, ng = Secret.Pick(flag, colour.g, g)
    local okB, nb = Secret.Pick(flag, colour.b, b)
    if okR and okG and okB then return true, nr, ng, nb end
    return false
end

-- With no readable state, the client's protected "holding it" answers the threat service keeps
-- (holdFlags: yours first with holdFlagsHaveSelf, then each folded member's, holdFlagStates TANK
-- for a tank) pick the colour inside the client, as the threat text's colour folds them: a tank's
-- holding colour for yours, offtank for another tank's, other for anyone else's or none; a DPS or
-- healer's aggro for yours, else safe. Only with your own answer (without it nothing says you do
-- not hold it), and not while Safe keeps the part's colour (no colour to fold from). Lua never
-- branches on an answer. True and r, g, b (protected: for a setter only), else false.
local function Fold(settings, part, tank, info)
    local count = info.holdFlagCount
    if info.holdFlagsHaveSelf ~= true or type(count) ~= "number" or count < 1 or type(info.holdFlags) ~= "table" then
        return false
    end
    local colour = ThreatColours.Colour
    local base, mine = colour(settings, part, tank and "other" or "safe"), colour(settings, part, tank and "holding" or "aggro")
    if not (base and mine) then return false end
    local flags, states = info.holdFlags, info.holdFlagStates
    local r, g, b = base.r, base.g, base.b
    if tank then
        local offtank = colour(settings, part, "offtank")
        for index = 2, count do
            if offtank and type(states) == "table" and states[index] == "TANK" then
                local ok
                ok, r, g, b = FoldStep(flags[index], offtank, r, g, b)
                if not ok then return false end
            end
        end
    end
    return FoldStep(flags[1], mine, r, g, b)
end

-- A plate's threat colour for part folded in the client (Fold) when its record reads no state;
-- true and protected r, g, b for the part's setter, else false (ForPlate's colour, or none).
function ThreatColours.FoldForPlate(data, part)
    local settings, info, tank = PlateContext(data, part)
    if not settings or PlateState(tank, info) ~= nil then return false end
    return Fold(settings, part, tank, info)
end

-- Whether part takes a threat colour now, readable or folded.
function ThreatColours.Colours(data, part)
    return ThreatColours.ForPlate(data, part) ~= nil or ThreatColours.FoldForPlate(data, part) == true
end

-- Studio's preview: the colour for part from its test values (samples: token -> value). A friendly
-- sample, or one out of combat, keeps the part's colour as a plate would.
function ThreatColours.ForSample(settings, part, samples)
    if not Asks(settings, part) or type(samples) ~= "table" then return nil end
    if samples.friendly == true or samples.combat == false then return nil end
    local tank = ThreatColours.IsTank(settings, function() return samples["role.tank"] == true end)
    local state = ThreatColours.State(tank, function(name) return samples["threat." .. name] end)
    return ThreatColours.Colour(settings, part, state)
end
