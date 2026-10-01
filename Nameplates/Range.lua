-- Whether an enemy plate's unit is within reach (the inrange condition): the range answers of the
-- player's own class spells, or the interact distance out of combat. A few plates are checked per
-- tick, only while an enemy layout reads inrange; an answer the client withholds is unknown (nil).
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

local Range = {}
PS.Range = Range

-- Harmful spells per class (first ranks), longest reach first. A unit is in range while any known
-- one reaches it, so a melee spell covers a ranged one's minimum range.
Range.CLASS_SPELLS = {
    DRUID = { 5176, 8921, 6807, 1082 },   -- Wrath, Moonfire, Maul, Claw
    HUNTER = { 75, 2973 },                -- Auto Shot, Raptor Strike
    MAGE = { 133, 116, 2136 },            -- Fireball, Frostbolt, Fire Blast
    PALADIN = { 20271, 853 },             -- Judgement, Hammer of Justice
    PRIEST = { 585, 589, 8092 },          -- Smite, Shadow Word: Pain, Mind Blast
    ROGUE = { 2764, 1752 },               -- Throw, Sinister Strike
    SHAMAN = { 403, 8042 },               -- Lightning Bolt, Earth Shock
    WARLOCK = { 686, 172, 348 },          -- Shadow Bolt, Corruption, Immolate
    WARRIOR = { 100, 2764, 78 },          -- Charge, Throw, Heroic Strike
}
-- CheckInteractDistance's follow distance (about 28 yards).
local INTERACT_DISTANCE = 4
Range.PLATES_PER_TICK = 4
Range.INTERVAL = 0.2
Range.TICKER = "plates.range"

-- The class's spells the player knows, worked out once and again when the spellbook changes. A
-- client with no known-spell API keeps them all: the range API answers nothing for an unknown one.
local known
local function IsKnown(spell)
    local api = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown
    if type(api) ~= "function" then return true end
    return Secret.ReadBoolean(api, spell) == true
end

local function KnownSpells()
    if known then return known end
    known = {}
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and Secret.String(class) or nil
    for _, spell in ipairs(class and Range.CLASS_SPELLS[class] or {}) do
        if IsKnown(spell) then known[#known + 1] = spell end
    end
    return known
end

function Range.Invalidate() known = nil end

-- true or false from a readable answer (a boolean, or 1 and 0 from older APIs); nil otherwise.
local function Answer(ok, value)
    if not ok or not IsReadable(value) then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
    return nil
end

-- true, false, or nil when nothing readable answered.
function Range.Check(unit)
    local api = C_Spell and C_Spell.IsSpellInRange
    local answered = false
    if type(api) == "function" then
        local spells = KnownSpells()
        for index = 1, #spells do
            local answer = Answer(pcall(api, spells[index], unit))
            if answer then return true end
            if answer == false then answered = true end
        end
    end
    if answered then return false end
    -- The interact distance is protected in combat, so it is asked only out of it.
    if type(CheckInteractDistance) == "function" and not Secret.InCombat() then
        return Answer(pcall(CheckInteractDistance, unit, INTERACT_DISTANCE))
    end
    return nil
end

-- The plate pass. context: active (unit -> plate), MarkValues, RunBatch. Each tick checks up to
-- PLATES_PER_TICK plates whose rules or text read inrange, in turn over a list of the active plates
-- taken again once a round, so no tick's work grows with the plate count. The entry is off while
-- nothing reads inrange (SetWanted).
PS._CreatePlateRange = function(context)
    local active, MarkValues, RunBatch = context.active, context.MarkValues, context.RunBatch
    local Pass = { wanted = false }
    local round, cursor = {}, 0

    local function Reads(data)
        local reads = data.reads
        return data.own and data.friendly == false and reads ~= nil
            and (reads.rules.range == true or reads.values.range == true)
    end

    -- What reads the answer follows only a change.
    local function Set(data, inRange)
        if data.inRange ~= inRange then
            data.inRange = inRange
            MarkValues(data, "range")
        end
    end

    local function Refill()
        for index = #round, 1, -1 do round[index] = nil end
        for unit, data in pairs(active) do
            if data.unit == unit then round[#round + 1] = data end
        end
        cursor = 0
    end

    function Pass.Tick()
        local checked, refilled = 0, false
        while checked < Range.PLATES_PER_TICK do
            if cursor >= #round then
                if refilled then break end
                Refill()
                refilled = true
                if #round == 0 then break end
            end
            cursor = cursor + 1
            local data = round[cursor]
            if data.unit and active[data.unit] == data then
                if Reads(data) then
                    Set(data, Range.Check(data.unit))
                    checked = checked + 1
                elseif data.inRange ~= nil then
                    Set(data, nil)
                end
            end
        end
    end

    -- On while a layout reads inrange; off, every plate's answer is forgotten.
    function Pass.SetWanted(wanted)
        wanted = wanted and true or false
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        PS.Ticker.SetEnabled(Range.TICKER, wanted)
        if not wanted then
            for unit, data in pairs(active) do
                if data.unit == unit then data.inRange = nil end
            end
            for index = #round, 1, -1 do round[index] = nil end
            cursor = 0
        end
    end

    PS.Ticker.Register(Range.TICKER, Range.INTERVAL, function() RunBatch(false, Pass.Tick) end)
    PS.Ticker.SetEnabled(Range.TICKER, false)
    return Pass
end

-- Learned, unlearned or replaced spells change which ones are asked.
do
    local frame = CreateFrame("Frame")
    PS._RegisterEvent(frame, "SPELLS_CHANGED", "platesmith.range")
    frame:SetScript("OnEvent", function() Range.Invalidate() end)
end
