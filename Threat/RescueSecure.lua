local _, PS = ...
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")

-- Rescue mode's secure side (docs/specs/RESCUE_MODE.md section 5): each Rescue window's pool of
-- SecureActionButtonTemplate buttons (a slot per listed member and the header's Taunt my target), the
-- attribute plan from the class's bindings, the unit watch, and parking. Attributes, points, sizes, levels,
-- parents and shown state are written only out of combat, in one pass per rebuild; in combat only the
-- client's unit watch shows or hides a slot. PlateSmith's code never casts or targets: a click runs the
-- button's own macro text, written out of combat from the player's chosen spells.
local Secure = { MAX_SLOTS = 40 }
PS.ThreatRescueSecure = Secure

-- What each class can bind, per spell: where it goes. target: the member's target (harmful), member: the
-- member (helpful), self: no unit (an area taunt). Spell IDs are first ranks; /cast by name casts the highest.
-- form: cast only in that form (bear: Bear or Dire Bear Form, [form:N] with the form bar's slot), so outside it a
-- click does nothing instead of raising the game's error.
Secure.SPELLS = {
    WARRIOR = {
        { key = "taunt", spell = 355, on = "target" },
        { key = "mockingBlow", spell = 694, on = "target" },
        { key = "challengingShout", spell = 1161, on = "self" },
        { key = "intervene", spell = 3411, on = "member" },
    },
    DRUID = {
        { key = "growl", spell = 6795, on = "target", form = "bear" },
        { key = "challengingRoar", spell = 5209, on = "self", form = "bear" },
    },
    PALADIN = {
        { key = "judgement", spell = 20271, on = "target" },
        { key = "blessingOfProtection", spell = 1022, on = "member" },
    },
}
Secure.DEFAULTS = {
    WARRIOR = { left = "taunt", right = "mockingBlow", shiftLeft = "challengingShout" },
    DRUID = { left = "growl", right = "challengingRoar" },
    PALADIN = { left = "judgement", shiftLeft = "blessingOfProtection" },
}
Secure.MODIFIERS = { "left", "right", "shiftLeft", "ctrlLeft", "altLeft" }
Secure.MODIFIER_LABELS = {
    left = L["Left-click"], right = L["Right-click"], shiftLeft = L["Shift + left-click"],
    ctrlLeft = L["Ctrl + left-click"], altLeft = L["Alt + left-click"],
}
local ATTRIBUTES = {
    left = { "type1", "macrotext1" }, right = { "type2", "macrotext2" },
    shiftLeft = { "shift-type1", "shift-macrotext1" }, ctrlLeft = { "ctrl-type1", "ctrl-macrotext1" },
    altLeft = { "alt-type1", "alt-macrotext1" },
}
Secure.ATTRIBUTES = ATTRIBUTES
-- Every attribute a slot can carry, so a rebuild clears what the new plan leaves out.
local ATTRIBUTE_NAMES = { "unit" }
for _, modifier in ipairs(Secure.MODIFIERS) do
    ATTRIBUTE_NAMES[#ATTRIBUTE_NAMES + 1] = ATTRIBUTES[modifier][1]
    ATTRIBUTE_NAMES[#ATTRIBUTE_NAMES + 1] = ATTRIBUTES[modifier][2]
end
Secure.ATTRIBUTE_NAMES = ATTRIBUTE_NAMES
local MAX_CLASSES = 16
-- The window's buttons sit this many levels above it, over the cells (an aggro cell is raised two).
local BUTTON_LEVELS = 10

local spellByKey = {}
for class, list in pairs(Secure.SPELLS) do
    spellByKey[class] = {}
    for _, definition in ipairs(list) do spellByKey[class][definition.key] = definition end
end

function Secure.Spell(class, key)
    local list = type(class) == "string" and spellByKey[class]
    return list and type(key) == "string" and list[key] or nil
end

-- The spell's name in the client's language, or nil.
function Secure.SpellName(spell)
    local api = C_Spell and C_Spell.GetSpellName
    if type(api) == "function" then
        local ok, name = pcall(api, spell)
        name = ok and Secret.String(name) or nil
        if name then return name end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spell)
        return ok and Secret.String(name) or nil
    end
    return nil
end

-- Whether the player knows the spell: true, false, or nil when the client will not say (then it is bound,
-- and the game reports an unknown spell itself).
function Secure.SpellKnown(spell)
    local api = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown
    if type(api) ~= "function" then return nil end
    return Secret.ReadBoolean(api, spell)
end

-- Saved bindings (account state rescueBindings): per class with a list, per modifier a key from that list
-- or "none" (Nothing). Other classes, modifiers and keys are dropped, so the class default applies.
function Secure.NormalizeBindings(list)
    if type(list) ~= "table" then return {} end
    local classes = {}
    for class in pairs(list) do
        if type(class) == "string" and spellByKey[class] then classes[#classes + 1] = class end
    end
    table.sort(classes)
    local clean, count = {}, 0
    for _, class in ipairs(classes) do
        local entry = list[class]
        if count < MAX_CLASSES and type(entry) == "table" then
            local kept, any = {}, false
            for _, modifier in ipairs(Secure.MODIFIERS) do
                local key = entry[modifier]
                if key == "none" or Secure.Spell(class, key) then
                    kept[modifier], any = key, true
                end
            end
            if any then
                clean[class], count = kept, count + 1
            end
        end
    end
    return clean
end

-- The key bound to a modifier: the saved choice, else the class default; nil for Nothing.
function Secure.Binding(bindings, class, modifier)
    local entry = type(bindings) == "table" and bindings[class]
    local key = type(entry) == "table" and entry[modifier] or nil
    if key == nil then key = Secure.DEFAULTS[class] and Secure.DEFAULTS[class][modifier] end
    if key == "none" or not Secure.Spell(class, key) then return nil end
    return key
end

-- The class's list as dropdown choices (Nothing first); empty for a class with no list.
function Secure.Choices(class)
    local choices = {}
    if not spellByKey[class] then return choices end
    choices[1] = { value = "none", label = L["Nothing"] }
    for _, definition in ipairs(Secure.SPELLS[class]) do
        local name = Secure.SpellName(definition.spell) or definition.key
        local label = name
        if definition.on == "target" then
            label = string.format(L["%s on their target"], name)
        elseif definition.on == "member" then
            label = string.format(L["%s on them"], name)
        end
        if definition.form == "bear" then label = string.format(L["%s (Bear Form)"], label) end
        choices[#choices + 1] = { value = definition.key, label = label }
    end
    return choices
end

-- The macro for one binding. target: harm and nodead on the member's target, so nothing is cast when it is
-- missing, friendly or dead; member: help and nodead on the member; self: no unit. A form spell adds the form's
-- condition with formSlot, its slot on the form bar (1, Bear Form's usual slot, when the client did not say).
function Secure.MacroText(definition, name, unit, header, formSlot)
    local form = definition.form and string.format("form:%d", formSlot or 1) or nil
    if definition.on == "self" then
        if form then return string.format("/cast [%s] %s", form, name) end
        return string.format("/cast %s", name)
    end
    local conditions = definition.on == "member" and "help,nodead" or "harm,nodead"
    if form then conditions = conditions .. "," .. form end
    local target = unit
    if definition.on ~= "member" then target = header and "target" or Secret.TargetToken(unit) end
    return string.format("/cast [@%s,%s] %s", target, conditions, name)
end

-- The attributes for one slot (a member token such as "party2") or the header (header true: unit "target" and
-- only the left binding, when it goes on a target): out[attribute] = value, and states[modifier] = "known",
-- "missing" (the player lacks the spell) or "unnamed" (the client gave no name), nil for Nothing. Unbound
-- modifiers stay unset. formSlot: Bear Form's slot on the form bar (MacroText).
function Secure.Plan(class, bindings, unit, header, out, states, formSlot)
    for key in pairs(out) do out[key] = nil end
    if states then for key in pairs(states) do states[key] = nil end end
    out.unit = unit
    for _, modifier in ipairs(Secure.MODIFIERS) do
        local key = (not header or modifier == "left") and Secure.Binding(bindings, class, modifier) or nil
        local definition = key and Secure.Spell(class, key)
        if definition and header and definition.on ~= "target" then definition = nil end
        if definition then
            local known = Secure.SpellKnown(definition.spell)
            local name = known ~= false and Secure.SpellName(definition.spell) or nil
            if name then
                local names = ATTRIBUTES[modifier]
                out[names[1]] = "macro"
                out[names[2]] = Secure.MacroText(definition, name, unit, header, formSlot)
            end
            if states then states[modifier] = (known == false and "missing") or (name and "known") or "unnamed" end
        end
    end
    return out
end

-- Whether the plan binds anything.
function Secure.Bound(plan)
    for _, modifier in ipairs(Secure.MODIFIERS) do
        if plan[ATTRIBUTES[modifier][1]] then return true end
    end
    return false
end

local function OnEnter(button)
    local Rescue = PS.ThreatRescue
    if Rescue then Rescue.OnSlotEnter(button) end
end

local function OnLeave(button)
    local Rescue = PS.ThreatRescue
    if Rescue then Rescue.OnSlotLeave(button) end
end

-- Counted for /ps diagnose; nothing about the unit is read.
local function PostClick(button)
    local rescue = button.meter and button.meter.rescue
    if not rescue then return end
    local kind = button.rescueKind
    rescue.clicks[kind] = (rescue.clicks[kind] or 0) + 1
end

-- Whether the client acts on a press (ActionButtonUseKeyDown); off when it will not say.
function Secure.KeyDown()
    local cvar = C_CVar and C_CVar.GetCVarBool
    if type(cvar) == "function" then
        local value = Secret.ReadBoolean(cvar, "ActionButtonUseKeyDown")
        if value ~= nil then return value end
    end
    if type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, "ActionButtonUseKeyDown")
        if ok and Secret.IsReadable(value) then return value == "1" end
    end
    return false
end

-- A slot is registered for one edge only, the one the client acts on, with a matching useOnKeyDown: registered for
-- both, a client whose template does not filter by edge would cast twice per click. Out of combat only.
local function SetClickEdge(button, keyDown)
    if button.rescueKeyDown == keyDown then return end
    button.rescueKeyDown = keyDown
    if button.RegisterForClicks then button:RegisterForClicks(keyDown and "AnyDown" or "AnyUp") end
    button:SetAttribute("useOnKeyDown", keyDown)
end

local function NewButton(meter, kind, index)
    local button = CreateFrame("Button", nil, meter.frame, "SecureActionButtonTemplate")
    button.meter, button.rescueKind, button.rescueIndex = meter, kind, index
    if button.EnableMouse then button:EnableMouse(true) end
    SetClickEdge(button, Secure.KeyDown())
    if button.HookScript then
        button:HookScript("OnEnter", OnEnter)
        button:HookScript("OnLeave", OnLeave)
        button:HookScript("PostClick", PostClick)
    end
    button:Hide()
    return button
end

-- Parked buttons wait here, out of their window, while it is not a Rescue window or its clicks are off: a
-- window with secure children cannot move, resize or hide in combat, so one without them stays free.
local park
local function Park()
    if not park then
        park = CreateFrame("Frame", nil, UIParent)
        park:Hide()
    end
    return park
end

local function Watch(button, on)
    if on == (button.rescueWatched == true) then
        if on and not button.rescueWatchAPI then button:Show() end
        return
    end
    button.rescueWatched = on
    if on then
        local ok = type(RegisterUnitWatch) == "function" and pcall(RegisterUnitWatch, button)
        button.rescueWatchAPI = ok and true or false
        -- Without the client's unit watch the slot shows while it is listed (out of combat, at each rebuild).
        if not ok then button:Show() end
    else
        if button.rescueWatchAPI and type(UnregisterUnitWatch) == "function" then pcall(UnregisterUnitWatch, button) end
        button.rescueWatchAPI = nil
        button:Hide()
    end
end

-- Writes only what changed (the button remembers what it was given).
local function WritePlan(button, values)
    local written = button.rescueAttributes
    if not written then
        written = {}
        button.rescueAttributes = written
    end
    for _, name in ipairs(ATTRIBUTE_NAMES) do
        local value = values[name]
        if written[name] ~= value then
            button:SetAttribute(name, value)
            written[name] = value
        end
    end
end

local EMPTY = {}

-- True while a window's buttons are its children: it then holds still in combat.
function Secure.Attached(meter)
    local pool = meter.rescueButtons
    return pool ~= nil and pool.attached == true
end

-- Makes (once) or brings back the window's buttons, out of combat. False and why: "combat", "failed" (the
-- client refused the template; the window then shows who needs help without clicks).
function Secure.Attach(meter)
    if Secret.InCombat() then return false, "combat" end
    local pool = meter.rescueButtons
    if not pool then
        if meter.rescueSecureState == "failed" then return false, "failed" end
        local ok, made = pcall(function()
            local list = { slots = {} }
            for index = 1, Secure.MAX_SLOTS do list.slots[index] = NewButton(meter, "member", index) end
            list.header = NewButton(meter, "header", 0)
            return list
        end)
        if not ok then
            meter.rescueSecureState = "failed"
            return false, "failed"
        end
        pool = made
        meter.rescueButtons = pool
    end
    if not pool.attached then
        for _, button in ipairs(pool.slots) do button:SetParent(meter.frame) end
        pool.header:SetParent(meter.frame)
        pool.attached = true
    end
    meter.rescueSecureState = "ok"
    return true
end

-- Clears, unwatches and parks the window's buttons, out of combat. False in combat (the caller queues it).
function Secure.Detach(meter)
    local pool = meter.rescueButtons
    if not pool or not pool.attached then return true end
    if Secret.InCombat() then return false end
    -- Unanchored too: a protected button still anchored to the window would keep the window protected in combat.
    for _, button in ipairs(pool.slots) do
        WritePlan(button, EMPTY)
        Watch(button, false)
        button:ClearAllPoints()
        button:SetParent(Park())
    end
    WritePlan(pool.header, EMPTY)
    pool.header:Hide()
    pool.header:ClearAllPoints()
    pool.header:SetParent(Park())
    pool.attached = false
    return true
end

local function Place(button, frame, rect, level)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", rect.x, -rect.y)
    button:SetSize(rect.width, rect.height)
    if button.SetFrameLevel then button:SetFrameLevel(level) end
end

-- Puts each button over its cell (Rescue's layout keeps each cell's rectangle in the window), out of combat.
function Secure.Place(meter)
    local pool, rescue = meter.rescueButtons, meter.rescue
    if not pool or not pool.attached or not rescue or Secret.InCombat() then return false end
    local frame = meter.frame
    local level = (frame.GetFrameLevel and frame:GetFrameLevel() or 0) + BUTTON_LEVELS
    for index = 1, math.min(rescue.count, Secure.MAX_SLOTS) do
        local rect = rescue.rects[index]
        if rect then Place(pool.slots[index], frame, rect, level) end
    end
    if rescue.headerRect then Place(pool.header, frame, rescue.headerRect, level) end
    return true
end

local scratchPlan = {}

-- The rebuild's one pass, out of combat: slot i carries the plan for the i-th listed member and watches its
-- token; slots past the list are cleared and hidden. The header carries the left binding on "target". False
-- in combat. formSlot: Bear Form's slot (Plan).
function Secure.Apply(meter, class, bindings, formSlot)
    local pool, rescue = meter.rescueButtons, meter.rescue
    if not pool or not pool.attached or not rescue then return false end
    if Secret.InCombat() then return false end
    rescue.bound = false
    -- The player may have changed Cast on key down since the buttons were made.
    local keyDown = Secure.KeyDown()
    SetClickEdge(pool.header, keyDown)
    for index = 1, Secure.MAX_SLOTS do
        local button, slot = pool.slots[index], index <= rescue.count and rescue.slots[index] or nil
        SetClickEdge(button, keyDown)
        if slot and slot.unit and not slot.sample then
            Secure.Plan(class, bindings, slot.unit, false, scratchPlan, nil, formSlot)
            if Secure.Bound(scratchPlan) then rescue.bound = true end
            WritePlan(button, scratchPlan)
            Watch(button, true)
        else
            WritePlan(button, EMPTY)
            Watch(button, false)
        end
    end
    Secure.Plan(class, bindings, "target", true, scratchPlan, nil, formSlot)
    rescue.headerBound = Secure.Bound(scratchPlan) and rescue.headerRect ~= nil
    if rescue.headerBound then
        WritePlan(pool.header, scratchPlan)
        pool.header:Show()
    else
        WritePlan(pool.header, EMPTY)
        pool.header:Hide()
    end
    Secure.Place(meter)
    return true
end

Secure._Test = { Park = Park }
