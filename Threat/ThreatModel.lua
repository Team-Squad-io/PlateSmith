-- Threat estimates for the player's own pulls (Threat/Breakdown.lua): the threat modifiers by form and ability, the
-- flat-threat abilities' formulas, rage from damage taken and from white hits, and the armor and attack power
-- figures. The numbers are the maintainer's notes for WoW Forever (2026-11-03); one not known yet is false and says
-- so rather than guessing. Pure maths on readable numbers: nothing here reads the client.
local _, PS = ...
local L = PS.L

local Model = {}
PS.ThreatModel = Model

-- A form whose modifier multiplies all of the player's threat in it (ThreatService:ReadPlayerForm's form words).
Model.FORMS = { bear = { mod = 2.15, label = L["Bear Form"] } }

-- Abilities by their English name in lower case (the probe records Forever's spell IDs; names until then). mod: the
-- damage's threat multiplier (false: not known yet, counted as 1 and flagged). flat: the threat of each cast, by a
-- formula below, instead of damage.
Model.ABILITIES = {
    ["maul"] = { mod = 1.75 },
    ["swipe"] = { mod = 1.75 },
    ["primal bite"] = { mod = 3 },
    ["lacerate"] = { mod = false },
    ["demoralizing roar"] = { flat = "demoralizingRoar" },
    ["faerie fire"] = { flat = "faerieFire" },
    ["faerie fire (feral)"] = { flat = "faerieFire" },
    ["enrage"] = { flat = "enrage" },
}
-- Enrage: not known (nil). Measured on Forever (2026-11-09, level 24, Bear Form): the cast itself adds no threat; what
-- its rage over the next seconds adds could not be told apart from the abilities around it.
Model.ENRAGE = nil
-- Demoralizing Roar: measured on Forever (2026-11-09, level 24, Bear Form) at about 55 threat on each mob it hits,
-- not split between them: 25.6 before the form's 2.15. requiredLevel here is that measured level, not the level the
-- rank is learned at (not known), so the threat scales with the player's level from 24 and stays 25.6 below it.
Model.DEMORALIZING_ROAR = { base = 25.6, requiredLevel = 24 }

-- Rage: auto attacks (3.46 x weapon speed x 1.3 two-handed x 2 on a crit; a bear swings at 2.5) and damage taken
-- (2.5 x mitigated damage x crit or crush modifier / the level's conversion factor).
Model.RAGE = { swing = 3.46, twoHanded = 1.3, crit = 2, crush = 1.5, bearSpeed = 2.5, taken = 2.5,
    conversion = { 0.0091107836, 3.225598133, 4.2652911 } }
-- Armor: reduction = armor / (armor + 400 + 85 x enemy level), at most 75%. Attack power: Paw (the bear's swing) gains
-- 1 DPS per 14, Swipe 3% of it; Thorns 6% of spell power.
Model.ARMOR = { base = 400, perLevel = 85, cap = 0.75 }
Model.SCALING = { pawPerDPS = 14, swipe = 0.03, thorns = 0.06 }

local function Number(value) return type(value) == "number" and value == value and value or nil end

-- The ability's entry for a spell name (nil: an ordinary one, its damage's threat as it is).
function Model.Ability(name)
    return type(name) == "string" and Model.ABILITIES[name:lower()] or nil
end

-- The form's modifier (1 outside a form that has one).
function Model.FormMod(form)
    local entry = form and Model.FORMS[form]
    return entry and entry.mod or 1
end

-- Threat from amount of damage by the ability named name in form: the threat, the ability's own modifier, and whether
-- that modifier is known (false: counted as 1). nil for an amount that is not a number.
function Model.DamageThreat(amount, name, form)
    amount = Number(amount)
    if not amount then return nil end
    local entry = Model.Ability(name)
    local mod, known = 1, true
    if entry and entry.mod == false then known = false
    elseif entry and entry.mod then mod = entry.mod end
    return amount * mod * Model.FormMod(form), mod, known
end

-- Demoralizing Roar's threat per cast: base + base / requiredLevel x (playerLevel - requiredLevel). nil while any of
-- them is unknown.
function Model.DemoralizingRoar(base, requiredLevel, playerLevel)
    base, requiredLevel, playerLevel = Number(base), Number(requiredLevel), Number(playerLevel)
    if not (base and requiredLevel and playerLevel) or requiredLevel <= 0 then return nil end
    return base + base / requiredLevel * math.max(0, playerLevel - requiredLevel)
end

-- One cast's threat for a flat-threat ability (Model.ABILITIES' flat), in form: nil when its formula's numbers are
-- not known.
function Model.FlatThreat(name, playerLevel, form)
    local entry = Model.Ability(name)
    local flat = entry and entry.flat
    local threat
    if flat == "faerieFire" then
        playerLevel = Number(playerLevel)
        threat = playerLevel and 2 * playerLevel or nil
    elseif flat == "enrage" then
        local enrage = Model.ENRAGE
        threat = enrage and enrage.initial + enrage.perTick * enrage.ticks or nil
    elseif flat == "demoralizingRoar" then
        local roar = Model.DEMORALIZING_ROAR
        threat = roar and Model.DemoralizingRoar(roar.base, roar.requiredLevel, playerLevel) or nil
    end
    return threat and threat * Model.FormMod(form) or nil
end

-- The conversion factor c(L) for an enemy of level L.
function Model.Conversion(level)
    level = Number(level)
    if not level then return nil end
    local c = Model.RAGE.conversion
    return c[1] * level * level + c[2] * level + c[3]
end

-- Rage from amount of damage taken (after armor) from an enemy of level, times modifier (a crit 2, a crush 1.5).
function Model.RageFromDamageTaken(amount, level, modifier)
    amount = Number(amount)
    local conversion = Model.Conversion(level)
    if not (amount and conversion and conversion > 0) then return nil end
    return Model.RAGE.taken * amount * (Number(modifier) or 1) / conversion
end

-- Rage from one auto attack: speed (a bear's 2.5 when nil), two-handed (a bear: true), crit.
function Model.RageFromSwing(speed, twoHanded, crit)
    local rage = Model.RAGE
    local value = rage.swing * (Number(speed) or rage.bearSpeed)
    if twoHanded ~= false then value = value * rage.twoHanded end
    if crit then value = value * rage.crit end
    return value
end

-- Armor's damage reduction against an enemy of level (0 to 0.75), and the armor that reaches the cap there.
function Model.ArmorReduction(armor, level)
    armor, level = Number(armor), Number(level)
    if not (armor and level) or armor <= 0 then return armor and 0 or nil end
    local A = Model.ARMOR
    return math.min(A.cap, armor / (armor + A.base + A.perLevel * level))
end
function Model.ArmorCap(level)
    level = Number(level)
    if not level then return nil end
    local A = Model.ARMOR
    return A.cap / (1 - A.cap) * (A.base + A.perLevel * level)
end

-- What attack power and spell power add: Paw DPS, Swipe damage per hit, Thorns damage.
function Model.Scaling(attackPower, spellPower)
    local S = Model.SCALING
    attackPower, spellPower = Number(attackPower), Number(spellPower)
    return { pawDPS = attackPower and attackPower / S.pawPerDPS or nil, swipe = attackPower and attackPower * S.swipe or nil,
        thorns = spellPower and spellPower * S.thorns or nil }
end

-- A pull's estimate. pull: form, level (the player's), enemyLevel, seconds, damage (spell name -> amount), casts
-- (spell name -> count), taken (damage taken). Returns { rows (each: name, damage, casts, mod, known, threat, share,
-- flat), total, perSecond, rage (from damage taken), unknown (abilities whose modifier or formula is not known) },
-- rows by threat, highest first.
function Model.Estimate(pull)
    local rows, total, unknown = {}, 0, {}
    for name, amount in pairs(pull.damage or {}) do
        local threat, mod, known = Model.DamageThreat(amount, name, pull.form)
        if threat then
            rows[#rows + 1] = { name = name, damage = amount, mod = mod, known = known, threat = threat }
            total = total + threat
            if not known then unknown[#unknown + 1] = name end
        end
    end
    for name, count in pairs(pull.casts or {}) do
        local entry = Model.Ability(name)
        if entry and entry.flat then
            local each = Model.FlatThreat(name, pull.level, pull.form)
            local row = { name = name, casts = count, flat = true, known = each ~= nil, threat = each and each * count }
            rows[#rows + 1] = row
            if each then total = total + row.threat else unknown[#unknown + 1] = name end
        end
    end
    for _, row in ipairs(rows) do row.share = (row.threat and total > 0) and row.threat / total or nil end
    table.sort(rows, function(a, b)
        if (a.threat or -1) ~= (b.threat or -1) then return (a.threat or -1) > (b.threat or -1) end
        return a.name < b.name
    end)
    table.sort(unknown)
    local seconds = Number(pull.seconds)
    return { rows = rows, total = total, perSecond = (seconds and seconds > 0) and total / seconds or nil,
        rage = Model.RageFromDamageTaken(pull.taken, pull.enemyLevel), unknown = unknown }
end
