-- Threat colours: the colour an enemy's health bar, name or health bar edge takes for its threat
-- state (Schema's colourByThreat and threatColour* settings), from the same record and reading as
-- the plate's threat text (PlateState). With only protected answers, the colour is picked inside the
-- client by who holds the mob (PickByHolder), as the text's colour is. A rule's colour on the part wins
-- (Lifecycle's ApplyPartRules); an unknown state or role, a unit not in combat with you or your group,
-- or Safe while it keeps the part's colour leaves the part's own colour. Studio's preview resolves the
-- same way from its test values. Colour rules on threat are picked by the same answers (FoldRules).
-- Grey when tagged by others (GreyWhenTagged) goes over them on the health bar, under a colour rule.
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

local L = PS.L
-- Each state's name and meaning: Studio's swatches and the legends (LegendLines) both use these.
ThreatColours.STATE_LABELS = {
    holding = L["Holding"], losing = L["Losing it"], offtank = L["Other tank has it"], other = L["Someone else has it"],
    safe = L["Safe"], pulling = L["Pulling"], aggro = L["Aggro"],
}
ThreatColours.STATE_HELP = {
    holding = L["You hold its threat."],
    losing = L["You hold it, but someone is close to taking it."],
    offtank = L["Another tank in your group holds it."],
    other = L["Someone who is not a tank holds it."],
    safe = L["A tank or someone else holds it, and you are not close."],
    pulling = L["You are close to taking it from whoever holds it."],
    aggro = L["You hold its threat."],
}

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
-- The threat edge on Blizzard's own plates (Extras.lua) asks as part "extras": it takes the shared colours whenever
-- its extra is on, on a plate PlateSmith does not draw (data.extras), as the glow there does.
ThreatColours.EXTRAS = "extras"
local function Asks(settings, part)
    if part == ThreatColours.GLOW or part == ThreatColours.EXTRAS then return type(settings) == "table" end
    return ThreatColours.Applies(settings, part)
end
-- Whether the plate takes threat colours for part: an owned plate, or Blizzard's with the extras (the edge and glow).
local function Drawn(data, part)
    if data.own == true then return true end
    return data.extras == true and (part == ThreatColours.GLOW or part == ThreatColours.EXTRAS)
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

-- What the threat service's reason word (GetPlayerRoleReason) says, and "profile" while the profile
-- fixes the role (threatColourRole).
local REASONS = {
    profile = L["this profile"], setting = L["your setting"], group = L["group role"], spec = L["specialization"],
    bear = L["Bear Form"], stance = L["Defensive Stance"], fury = L["Righteous Fury"], presence = L["tanking presence"],
    escape = L["Bear Form on healing talents"], nobear = L["not in Bear Form"], nostance = L["not in Defensive Stance"],
    cat = L["Cat Form"], moonkin = L["Moonkin Form"], tree = L["Tree of Life"], travel = L["travel form"],
    caster = L["caster form"],
    nofury = L["no Righteous Fury"], nopresence = L["no tanking presence"], notank = L["no tanking stance, form or aura"],
    class = L["your class does not tank"], none = L["no role found"],
}
local ROLE_NAMES = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["DPS"], NONE = L["DPS"] }

-- Whom threat colours colour as now: tank (true, false, or nil when the role cannot be read, and the
-- plates then keep their colours), the role's name and the reason's text. The same answer IsTank gives
-- the plates (the profile's fixed role, else the threat service's).
function ThreatColours.ColouringAs(settings)
    local fixed = type(settings) == "table" and settings.threatColourRole or nil
    if fixed == "tank" then return true, L["Tank"], REASONS.profile end
    if fixed == "dps" then return false, L["DPS & healer"], REASONS.profile end
    local service = PS.ThreatService
    local ok, role, reason = false, nil, nil
    if type(service) == "table" and type(service.GetPlayerRoleReason) == "function" then
        ok, role, reason = pcall(service.GetPlayerRoleReason, service)
    end
    if not ok or not Secret.IsReadable(role) or not ROLE_NAMES[role] then return nil, L["Unknown"], REASONS.none end
    local why = Secret.IsReadable(reason) and REASONS[reason] or REASONS.none
    return role == "TANK", ROLE_NAMES[role], why
end

-- "Colouring as: Tank (Bear Form)", for Studio's Modules › Threat › Your role, the
-- threat windows and /ps diagnose.
function ThreatColours.ColouringAsText(settings)
    local _, name, why = ThreatColours.ColouringAs(settings)
    return string.format(L["Colouring as: %s (%s)"], name, why)
end

-- A colour swatch inside text: a white square tinted to the colour (0-255 channels).
local SWATCH = "|TInterface\\Buttons\\WHITE8X8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t"
local function Channel(value)
    if type(value) ~= "number" then return 0 end
    return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
end

-- The legend for a role's plate colours (tank: holding, losing, another tank's, someone else's; DPS
-- and healers: safe, pulling, aggro): one line per state, its swatch in the shared colour and what it
-- means. Safe while it keeps the part's colour has no swatch and says so.
function ThreatColours.LegendLines(settings, tank)
    settings = type(settings) == "table" and settings or {}
    local colours = type(settings.threatColours) == "table" and settings.threatColours or {}
    local lines = {}
    for _, state in ipairs(tank and ThreatColours.TANK_STATES or ThreatColours.DPS_STATES) do
        local colour = colours[state]
        if state == "safe" and settings.threatColourSafeKeep == true then
            lines[#lines + 1] = string.format(L["%s: %s Keeps the part's own colour."], ThreatColours.STATE_LABELS[state],
                ThreatColours.STATE_HELP[state])
        else
            local swatch = type(colour) == "table"
                and string.format(SWATCH, Channel(colour.r), Channel(colour.g), Channel(colour.b)) or ""
            lines[#lines + 1] = string.format(L["%s %s: %s"], swatch, ThreatColours.STATE_LABELS[state],
                ThreatColours.STATE_HELP[state])
        end
    end
    return lines
end

-- "Colouring as" and the legend for that role, one line each: Studio's Threat colours and Settings ›
-- Threat › Your role show it. While the role cannot be read only the first line.
function ThreatColours.RoleLegendText(settings)
    local tank = ThreatColours.ColouringAs(settings)
    local text = ThreatColours.ColouringAsText(settings)
    if tank == nil then return text end
    return text .. "\n" .. table.concat(ThreatColours.LegendLines(settings, tank), "\n")
end

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
    if not Asks(settings, part) or not Drawn(data, part) or data.friendly ~= false then return nil end
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

-- Whether a record keeps your own protected "holding it" answer (the threat service's holdFlags:
-- yours first with holdFlagsHaveSelf, then each folded member's, holdFlagStates TANK for a tank).
-- Without it nothing says you do not hold the mob, so nothing is picked from the others.
local function HasOwnAnswer(info)
    local count = info.holdFlagCount
    return info.holdFlagsHaveSelf == true and type(count) == "number" and count >= 1 and type(info.holdFlags) == "table"
end

-- The one fold of those answers, inside the client (Secret.PickColour): you* when your answer says
-- you hold the mob, else tank* when another tank's says they do (only withTank), else other*. Any
-- colour may itself be protected (one picked before); Lua never branches on an answer. True and
-- r, g, b (protected: for a setter only), else false (no answer of your own, or no sink).
function ThreatColours.PickByHolder(info, youR, youG, youB, withTank, tankR, tankG, tankB, otherR, otherG, otherB)
    if not HasOwnAnswer(info) then return false end
    local flags, states = info.holdFlags, info.holdFlagStates
    local r, g, b = otherR, otherG, otherB
    if withTank and type(states) == "table" then
        for index = 2, info.holdFlagCount do
            if states[index] == "TANK" then
                local ok
                ok, r, g, b = Secret.PickColour(flags[index], tankR, tankG, tankB, r, g, b)
                if not ok then return false end
            end
        end
    end
    return Secret.PickColour(flags[1], youR, youG, youB, r, g, b)
end
local PickByHolder = ThreatColours.PickByHolder

local function Channels(colour)
    if colour then return colour.r, colour.g, colour.b end
end

-- A plate's threat colour for part picked by who holds it (PickByHolder) when its record reads no
-- state: a tank's holding colour for you, offtank for another tank, other for anyone else or no one;
-- a DPS or healer's aggro for you, else safe. Not while Safe keeps the part's colour (no colour to
-- pick from). True and protected r, g, b for the part's setter, else false (ForPlate's colour, or none).
function ThreatColours.FoldForPlate(data, part)
    local settings, info, tank = PlateContext(data, part)
    if not settings or PlateState(tank, info) ~= nil then return false end
    local colour = ThreatColours.Colour
    local mine, other = colour(settings, part, tank and "holding" or "aggro"), colour(settings, part, tank and "other" or "safe")
    if not (mine and other) then return false end
    local offtank = tank and colour(settings, part, "offtank") or nil
    local tr, tg, tb = Channels(offtank)
    return PickByHolder(info, mine.r, mine.g, mine.b, offtank ~= nil, tr, tg, tb, other.r, other.g, other.b)
end

-- Whether part takes a threat colour now, readable or folded.
function ThreatColours.Colours(data, part)
    return ThreatColours.ForPlate(data, part) ~= nil or ThreatColours.FoldForPlate(data, part) == true
end

-- Colour rules on protected threat answers (Lifecycle's ApplyPartRules), with or without Colour by
-- threat. Where nothing readable says who holds a mob (dungeons and raids) a threat condition is
-- unknown and its rule would never hold. So it is read in each state PickByHolder can pick (you hold
-- it, another tank does, someone else does) and, when it is true or false in each, PickByHolder picks
-- between its colour and the one under it. A condition still unknown in one of them (threat.losing,
-- threat.pulling, a protected health %), and blend, opacity and hide rules, do not apply.
--
-- Each state is a view of the plate's record with who holds it set; every other field reads through
-- to the record, so ThreatText.Facts answer as they would there. Threat tokens read the view's facts,
-- any other token the plate's own reader.
local WORLD_FACTS = { tanking = "holding", ["threat.holding"] = "holding", ["threat.losing"] = "losing",
    ["threat.pulling"] = "pulling", ["threat.other"] = "other", ["threat.offtank"] = "offtank" }
-- (threat.loose is not folded: whether your holding it is loose depends on your role and group, which a view does not
-- say, so it reads the record's own answer there, unknown where the record is UNKNOWN: the rule does not apply.)
local YOU, TANK, OTHER = 1, 2, 3
local WORLDS = {
    [YOU] = { tanking = true, holdState = "YOU", targetUnit = "player", targetIsPlayer = true },
    [TANK] = { tanking = false, holdState = "TANK", targetUnit = "group", targetIsPlayer = false },
    [OTHER] = { tanking = false, holdState = "LOOSE", targetUnit = false, targetIsPlayer = false },
}
-- Private keys on a view: the record and the plate reader it is bound to.
local RECORD, PLATE_READ = {}, {}
local VIEW = { __index = function(view, field) return rawget(view, RECORD)[field] end }

-- A plate's three views and a token reader for each: made once per plate (data.threatRuleWorlds) and
-- bound to its record and reader at the start of each FoldRules call, so no state is shared between
-- plates and nothing is allocated after the first call.
local function BindWorlds(data, info, read)
    local worlds = data.threatRuleWorlds
    if not worlds then
        worlds = { views = {}, reads = {} }
        for index, holder in ipairs(WORLDS) do
            local view = setmetatable({ tanking = holder.tanking, holdState = holder.holdState,
                targetUnit = holder.targetUnit, targetIsPlayer = holder.targetIsPlayer }, VIEW)
            worlds.views[index] = view
            worlds.reads[index] = function(token)
                local fact = WORLD_FACTS[token]
                if fact then return FACTS[fact](view) end
                return view[PLATE_READ](token)
            end
        end
        data.threatRuleWorlds = worlds
    end
    for _, view in ipairs(worlds.views) do view[RECORD], view[PLATE_READ] = info, read end
    return worlds.reads
end

-- A condition's three-valued answer in one state.
local function HoldsIn(tree, read)
    local ok, answer = pcall(PS.Template.Evaluate, tree, read)
    if ok then return answer end
    return nil
end

local function HasOtherTank(info)
    local states = info.holdFlagStates
    if type(states) ~= "table" then return false end
    for index = 2, info.holdFlagCount do
        if states[index] == "TANK" then return true end
    end
    return false
end

-- The rule's colour where it holds, else the colour under it.
local function Either(holds, colour, r, g, b)
    if holds then return colour.r, colour.g, colour.b end
    return r, g, b
end

-- Whether a plate's colour rules can be folded now: an owned enemy in combat whose record reads
-- no hold state but keeps your own protected answer (as PickByHolder needs).
function ThreatColours.RulesFoldable(data)
    local info = data.threatInfo
    if data.own ~= true or data.friendly ~= false or type(info) ~= "table" or info.engaged ~= true then return false end
    return HasOwnAnswer(info) and FACTS.holding(info) == nil
end

-- A part's colour rules from list[from] on (those after the last one that holds) folded over r, g, b
-- (the colour under them: a rule's, Threat colours' or the part's own; possibly protected) in list
-- order, each result the colour under the next, on a plate RulesFoldable says can. read reads the
-- plate's tokens. True and r, g, b (for a setter only) when a rule was folded, else false.
function ThreatColours.FoldRules(data, list, from, read, r, g, b)
    local info, Template = data.threatInfo, PS.Template
    local reads = BindWorlds(data, info, read)
    local tanks, folded = HasOtherTank(info), false
    for index = from, #list do
        local rule = list[index]
        local colour, when = rule.colour, rule.when
        if rule.enabled ~= false and rule.set == "colour" and type(colour) == "table" and type(when) == "string" then
            local tree = Template.CompileCondition(when)
            if tree and Template.Evaluate(tree, read) == nil then
                local you, other, tank = HoldsIn(tree, reads[YOU]), HoldsIn(tree, reads[OTHER]), nil
                if tanks then tank = HoldsIn(tree, reads[TANK]) end
                if you ~= nil and other ~= nil and not (tanks and tank == nil) and (you or other or tank) then
                    local yr, yg, yb = Either(you, colour, r, g, b)
                    local tr, tg, tb = Either(tank, colour, r, g, b)
                    local xr, xg, xb = Either(other, colour, r, g, b)
                    local ok
                    -- Another tank's answer needs walking only where it changes the colour.
                    ok, r, g, b = PickByHolder(info, yr, yg, yb, tank ~= nil and tank ~= other, tr, tg, tb, xr, xg, xb)
                    if not ok then return false end
                    folded = true
                end
            end
        end
    end
    if folded then return true, r, g, b end
    return false
end

-- Grey when tagged by others (Schema's greyWhenTagged): the health bar's colour on an enemy plate while another
-- player or group has tagged the mob (tapped: UnitIsTapDenied read readable and true; protected or unknown is
-- false, so the bar keeps its colour). It wins over threat colours, as Blizzard's tapped grey wins over its
-- in-combat red (CompactUnitFrame_UpdateHealthColor): a tagged mob gives you no credit, whoever holds it. A colour
-- rule on the health bar still wins (Lifecycle's ApplyPartRules). nil when the bar keeps its own colour. The plates
-- and Studio's preview (GreyForSample) both ask here.
ThreatColours.TAGGED_GREY = { r = 0.5, g = 0.5, b = 0.5 }
function ThreatColours.GreyWhenTagged(settings, enemy, tapped)
    if enemy == true and tapped == true and type(settings) == "table" and settings.greyWhenTagged == true then
        return ThreatColours.TAGGED_GREY
    end
    return nil
end

-- Studio's preview: the health bar's grey from its test values (Tagged), on an enemy design.
function ThreatColours.GreyForSample(settings, samples, enemy)
    if type(samples) ~= "table" or samples.friendly == true then return nil end
    return ThreatColours.GreyWhenTagged(settings, enemy, samples.tagged == true)
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
