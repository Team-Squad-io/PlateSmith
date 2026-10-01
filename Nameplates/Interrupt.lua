-- The player's interrupt, for the cast bar's Colour by interrupt and the interruptReady condition:
-- which spell it is, whether it is ready, and the bar colour that follows from that and the cast.
-- A protected fact only reaches the client's boolean-to-colour sink, never a Lua branch.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable, IsSecret = Secret.IsReadable, Secret.IsSecret

local Interrupt = {}
PS.Interrupt = Interrupt

-- By class token, preferred first, with every rank a Classic-era client may know (ranks share one
-- cooldown). pet: looked up in the pet's spell book (the Felhunter's Spell Lock).
local SPELLS = {
    WARRIOR = { 6552, 6554, 72, 1671, 1672 }, -- Pummel, Shield Bash
    ROGUE = { 1766, 1767, 1768, 1769 }, -- Kick
    MAGE = { 2139 }, -- Counterspell
    SHAMAN = { 57994, 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, -- Wind Shear, Earth Shock
    PRIEST = { 15487 }, -- Silence
    WARLOCK = { pet = { 19244, 19647 } }, -- Spell Lock
}
Interrupt.SPELLS = SPELLS

-- A cooldown no longer than the global one counts as ready: the interrupt can go as soon as it ends.
local GLOBAL_COOLDOWN = 1.5
local TICKER = "plates.interrupt"
local WATCH_INTERVAL = 0.2

-- spell: the resolved spell ID (nil: none), resolved: whether it was looked up since spells last
-- changed. value/secret/readAt: this frame's answer. watched: casting plates coloured by it.
-- last: the answer the listener last heard ("secret", "unknown", true or false).
local state = { resolved = false, watched = {}, count = 0, used = false }

local function Answer(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if ok and IsReadable(value) then return value == true end
end

local function Known(id, pet)
    if pet then return Answer(IsSpellKnown, id, true) == true end
    if Answer(IsPlayerSpell, id) or Answer(IsSpellKnown, id) then return true end
    local book = C_SpellBook
    return book ~= nil and Answer(book.IsSpellKnown, id) == true
end

local function Resolve()
    state.resolved, state.spell = true, nil
    if type(UnitClass) ~= "function" then return end
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or not IsReadable(class) or type(class) ~= "string" then return end
    local list = SPELLS[class]
    if not list then return end
    for _, id in ipairs(list.pet or {}) do
        if Known(id, true) then
            state.spell = id
            return
        end
    end
    for _, id in ipairs(list) do
        if Known(id) then
            state.spell = id
            return
        end
    end
end

-- The player's interrupt spell ID, or nil when they have none.
function Interrupt.Spell()
    if not state.resolved then Resolve() end
    return state.spell
end

-- From readable cooldown numbers: ready when no cooldown longer than the global one runs; nil when
-- the client has no such API or withholds the numbers.
local function ReadNumbers(id)
    local duration, enabled
    local spell = C_Spell
    if spell and type(spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(spell.GetSpellCooldown, id)
        if not ok or not IsReadable(info) or type(info) ~= "table" then return nil end
        duration, enabled = info.duration, info.isEnabled
    elseif type(GetSpellCooldown) == "function" then
        local ok, _, length, active = pcall(GetSpellCooldown, id)
        if not ok then return nil end
        duration, enabled = length, active
    else
        return nil
    end
    if not IsReadable(duration) or type(duration) ~= "number" then return nil end
    if IsReadable(enabled) and (enabled == false or enabled == 0) then return false end
    return duration <= GLOBAL_COOLDOWN
end

-- From the client's cooldown duration object: IsZero, which may be protected (returned with true).
local function ReadDuration(id)
    local spell = C_Spell
    if not (spell and type(spell.GetSpellCooldownDuration) == "function") then return nil end
    local ok, duration = pcall(spell.GetSpellCooldownDuration, id)
    if not ok or not IsReadable(duration) or type(duration) ~= "table" or type(duration.IsZero) ~= "function" then
        return nil
    end
    local read, zero = pcall(duration.IsZero, duration)
    if not read then return nil end
    if IsSecret(zero) then return zero, true end
    if IsReadable(zero) and type(zero) == "boolean" then return zero, false end
end

local function Fresh()
    local id = Interrupt.Spell()
    if not id then return false, false end
    local ready = ReadNumbers(id)
    if ready ~= nil then return ready, false end
    return ReadDuration(id)
end

-- Whether the interrupt is ready: true or false when readable (no interrupt is false), a protected
-- boolean with secret true, or nil when unknown. Read at most once a frame.
local function Read()
    state.used = true
    local now = type(GetTime) == "function" and GetTime() or nil
    if now == nil or state.readAt ~= now then
        local value, secret = Fresh()
        state.value, state.secret, state.readAt = value, secret == true, now
    end
    return state.value, state.secret
end

-- For rules: true, false, or nil while the answer is protected or unknown.
function Interrupt.Ready()
    local value, secret = Read()
    if secret then return nil end
    return value
end

local Pick = Secret.Pick

-- The cast bar colour for colours (ready, cooldown, locked) and the cast's notInterruptible as the
-- cast API gave it (possibly protected). Returns true, r, g, b (each possibly protected: for
-- SetStatusBarColor only), or false when a fact is unknown or protected without a sink, so the bar
-- keeps its own colour.
function Interrupt.CastColour(colours, notInterruptible)
    local locked = colours.locked
    local lockedKnown = IsReadable(notInterruptible)
    if lockedKnown and notInterruptible == true then return true, locked.r, locked.g, locked.b end
    local value, secret = Read()
    local ready, cooldown = colours.ready, colours.cooldown
    local r, g, b
    if secret then
        local okR, okG, okB
        okR, r = Pick(value, ready.r, cooldown.r)
        okG, g = Pick(value, ready.g, cooldown.g)
        okB, b = Pick(value, ready.b, cooldown.b)
        if not (okR and okG and okB) then return false end
    elseif value == nil then
        return false
    else
        local colour = value and ready or cooldown
        r, g, b = colour.r, colour.g, colour.b
    end
    if not lockedKnown then
        local okR, okG, okB
        okR, r = Pick(notInterruptible, locked.r, r)
        okG, g = Pick(notInterruptible, locked.g, g)
        okB, b = Pick(notInterruptible, locked.b, b)
        if not (okR and okG and okB) then return false end
    end
    return true, r, g, b
end

-- A casting plate coloured by the interrupt (key: its plate data): while any is, the answer is read
-- again every WATCH_INTERVAL, since the client does not always say when a cooldown ends.
function Interrupt.Watch(key, watched)
    local was = state.watched[key] ~= nil
    if watched and not was then
        state.watched[key] = true
        state.count = state.count + 1
        if state.count == 1 then PS.Ticker.SetEnabled(TICKER, true) end
    elseif not watched and was then
        state.watched[key] = nil
        state.count = state.count - 1
        if state.count == 0 then PS.Ticker.SetEnabled(TICKER, false) end
    end
end

-- listener(readyChanged): readyChanged when the readable answer changed (whatever reads
-- interruptReady follows); false while it is protected (only the watched colours need it again).
function Interrupt.SetListener(listener) state.listener = listener end

local function Check()
    state.readAt = nil
    if not (state.used and state.listener) then return end
    local value, secret = Read()
    local answer = secret and "secret" or value
    if answer == nil then answer = "unknown" end
    if answer ~= state.last then
        state.last = answer
        state.listener(true)
    elseif secret and state.count > 0 then
        state.listener(false)
    end
end
Interrupt.Check = Check

PS.Ticker.Register(TICKER, WATCH_INTERVAL, Check)
PS.Ticker.SetEnabled(TICKER, false)

local events = CreateFrame("Frame")
for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "UNIT_PET" }) do
    PS._RegisterEvent(events, event, "platesmith.interrupt")
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_PET" and IsReadable(unit) and unit ~= "player" then return end
    if event ~= "SPELL_UPDATE_COOLDOWN" then state.resolved = false end
    Check()
end)

-- For tests: forget the resolved spell, this frame's answer and the watched plates.
function Interrupt._Reset()
    state.resolved, state.spell, state.readAt, state.last, state.used = false, nil, nil, nil, false
    for key in pairs(state.watched) do state.watched[key] = nil end
    state.count = 0
    PS.Ticker.SetEnabled(TICKER, false)
end
