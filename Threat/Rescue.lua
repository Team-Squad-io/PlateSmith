local _, PS = ...
local L = PS.L
local Themes = assert(PS.ThreatThemes, "PlateSmith ThreatThemes missing")
local Geometry = assert(PS.ThreatGeometry, "PlateSmith ThreatGeometry missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local ThreatText = assert(PS.ThreatText, "PlateSmith ThreatText missing")
local Sample = assert(PS.ThreatSample, "PlateSmith ThreatSample missing")
local Secure = assert(PS.ThreatRescueSecure, "PlateSmith ThreatRescueSecure missing")

-- Rescue mode, the threat windows' third mode (docs/specs/RESCUE_MODE.md): your group in a fixed order, each
-- member coloured when they pull or have aggro (the threat service's group situation; no second scanner), and
-- a click on a member casts your bound spell on their target through the window's secure buttons
-- (Threat/RescueSecure.lua). The list is built, ordered, sized and bound only out of combat; in combat only
-- the cells (ordinary frames under the buttons) change.
local Rescue = {}
PS.ThreatRescue = Rescue

Rescue.CELL_W, Rescue.GAP, Rescue.NUMBERS_H, Rescue.STATE_W = 70, 2, 12, 92
Rescue.GLOW_SPREAD, Rescue.GLOW_RAID_SPREAD, Rescue.GLOW_OPACITY = 7, 6, 0.8
-- Members whose situation, target, range and death are re-read per refresh tick (a 40-player raid in 1.25 s).
Rescue.BACKSTOP = 8
local FAR_ALPHA, DEAD_ALPHA = 0.42, 0.6
local MAX_FLAGS = 8

Rescue.LAYOUTS = { "auto", "list", "grid" }
Rescue.FILTERS = { "everyone", "healers", "healersRanged", "group" }
Rescue.SOUNDS = {
    { key = "raidWarning", label = L["Raid warning"], kit = "RAID_WARNING", id = 8959 },
    { key = "readyCheck", label = L["Ready check"], kit = "READY_CHECK", id = 8960 },
    { key = "alarmClock", label = L["Alarm clock"], kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
}
Rescue.SOUND_GAP = { 1, 10 }
Rescue.SOUND_KEY_LENGTH = 64
Rescue.DEFAULTS = {
    rescueLayout = "auto", rescueFilter = "everyone", rescueInRaids = true, rescueSound = false,
    rescueSoundKey = "raidWarning", rescueSoundGap = 3, rescueFlash = false, rescueCooldown = false,
}
-- The border flash: in and out this many times (an AnimationGroup on the window's overlay; no ticker).
Rescue.FLASH_TIMES, Rescue.FLASH_IN, Rescue.FLASH_OUT, Rescue.FLASH_EDGE = 2, 0.12, 0.3, 3
-- A cooldown this short or shorter is the global cooldown: the taunt counts as ready.
Rescue.GCD = 1.5
local layouts, filters, sounds = {}, {}, {}
for _, value in ipairs(Rescue.LAYOUTS) do layouts[value] = true end
for _, value in ipairs(Rescue.FILTERS) do filters[value] = true end
local SOUND_CHOICES = {}
for _, sound in ipairs(Rescue.SOUNDS) do
    sounds[sound.key] = sound
    SOUND_CHOICES[#SOUND_CHOICES + 1] = { value = sound.key, label = sound.label }
end
local BOOLEAN_KEYS = { rescueInRaids = true, rescueSound = true, rescueFlash = true, rescueCooldown = true }
local FILTER_SHORT = { healers = L["Healers only"], healersRanged = L["Healers and ranged"], group = L["My group"] }

local ROLE_ICONS = { TANK = "icon-role-tank", HEALER = "icon-role-healer", DAMAGER = "icon-role-damage" }
local ROLE_RANK = { TANK = 1, HEALER = 2 }
-- Ranged damage by class alone: other members' specializations are not readable here, so a caster druid or
-- shaman dealing damage is not counted (a healer is, by role).
local RANGED = { HUNTER = true, MAGE = true, WARLOCK = true, PRIEST = true }
local STATE_WORDS = { aggro = L["AGGRO"], pulling = L["PULLING"], tank = L["HOLDING"] }
local STATE_TIPS = {
    aggro = L["An enemy is attacking them."], pulling = L["Pulling: more threat than the tank."],
    tank = L["Tanking: holding aggro."], safe = L["Safe."],
    unknown = L["The game keeps their threat private here."],
}
local WHITE = { 1, 1, 1 }
local MUTED = { 0.62, 0.65, 0.68 }
local DEAD = { 0.5, 0.5, 0.52 }
-- The header's Taunt my target on each art theme (fill, edge, text); the rest use Forge's.
local BUTTON_LOOK = {
    forge = { fill = { 0.05, 0.05, 0.06, 0.95 }, edge = { 0.93, 0.8, 0.52, 0.75 }, text = { 0.98, 0.86, 0.58 } },
    ledger = { fill = { 0.22, 0.14, 0.07, 1 }, edge = { 0.13, 0.08, 0.04, 1 }, text = { 0.98, 0.9, 0.7 } },
    glass = { fill = { 0.09, 0.1, 0.12, 0.9 }, edge = { 1, 1, 1, 0.4 }, text = { 0.96, 0.96, 0.96 } },
}
-- Sample data: the threat windows' sample group, each in one state (spec mockup a).
local SAMPLE_LOOKS = {
    Aldwyn = { state = "aggro" }, Kaelyra = { state = "pulling" }, Dunmore = { state = "safe", dead = true },
    Sethrin = { state = "safe", noTarget = true }, Morvaine = { state = "safe", far = true },
}
local SAMPLE_TANK = { state = "tank" }
local SAMPLE_SAFE = { state = "safe" }

-- A sound choice: a built-in key, or a LibSharedMedia sound ("lsm:<name>"). A saved one is kept while LSM is
-- missing (it may load later; until then the default plays); a new choice must be one LSM has now (strict).
function Rescue.IsSoundKey(value, strict)
    if sounds[value] then return true end
    if type(value) ~= "string" or #value > Rescue.SOUND_KEY_LENGTH then return false end
    local Media = PS.Media
    if not (Media and Media.IsSharedReference and Media.IsSharedReference(value)) then return false end
    return not strict or Media.SoundPath(value) ~= nil
end

-- The sound picker's choices: the built-in sounds, then LibSharedMedia's when it is installed (PS.Media).
function Rescue.SoundChoices()
    local Media = PS.Media
    if Media and Media.SoundChoices then return Media.SoundChoices(SOUND_CHOICES) end
    return SOUND_CHOICES
end

-- Saved window fields (account state, Console's NormalizeWindow): bounded, an unknown value resets.
function Rescue.NormalizeRecord(record)
    if not layouts[record.rescueLayout] then record.rescueLayout = Rescue.DEFAULTS.rescueLayout end
    if not filters[record.rescueFilter] then record.rescueFilter = Rescue.DEFAULTS.rescueFilter end
    record.rescueInRaids = record.rescueInRaids ~= false
    record.rescueSound = record.rescueSound == true
    record.rescueFlash = record.rescueFlash == true
    record.rescueCooldown = record.rescueCooldown == true
    if not Rescue.IsSoundKey(record.rescueSoundKey, false) then record.rescueSoundKey = Rescue.DEFAULTS.rescueSoundKey end
    local gap = record.rescueSoundGap
    if type(gap) ~= "number" or gap ~= gap then gap = Rescue.DEFAULTS.rescueSoundGap end
    record.rescueSoundGap = math.floor(math.max(Rescue.SOUND_GAP[1], math.min(Rescue.SOUND_GAP[2], gap)) + 0.5)
    return record
end

-- A window option's checked value, or nil when key is not Rescue's or value is refused.
function Rescue.CheckOption(key, value)
    if key == "rescueLayout" then return layouts[value] and value or nil end
    if key == "rescueFilter" then return filters[value] and value or nil end
    if BOOLEAN_KEYS[key] then return value == true end
    if key == "rescueSoundKey" then return Rescue.IsSoundKey(value, true) and value or nil end
    if key == "rescueSoundGap" then
        if type(value) ~= "number" or value ~= value then return nil end
        return math.floor(math.max(Rescue.SOUND_GAP[1], math.min(Rescue.SOUND_GAP[2], value)) + 0.5)
    end
    return nil
end

-- The fixed order: by raid group (a party is one group), then tanks, healers, the rest, then the group's own
-- order (you first in a party).
function Rescue.Before(left, right)
    if left.group ~= right.group then return left.group < right.group end
    local leftRank, rightRank = ROLE_RANK[left.role] or 3, ROLE_RANK[right.role] or 3
    if leftRank ~= rightRank then return leftRank < rightRank end
    return left.index < right.index
end

-- Whether a member is listed with this filter. playerGroup: your raid group (nil in a party, or unknown: then
-- My group only lists everyone).
function Rescue.Keep(member, filter, playerGroup)
    if filter == "healers" then return member.role == "HEALER" end
    if filter == "healersRanged" then
        return member.role == "HEALER" or (member.role ~= "TANK" and RANGED[member.classToken] == true)
    end
    if filter == "group" then return playerGroup == nil or member.group == playerGroup end
    return true
end

-- What a member's cell shows from the service's readable situation: safe, pulling, aggro, tank (a tank
-- holding) or unknown (protected, missing or not read yet: neutral, never a guess).
function Rescue.State(role, status, state)
    if state == "none" then return "safe" end
    if state ~= "readable" or type(status) ~= "number" then return "unknown" end
    if status >= 2 then return role == "TANK" and "tank" or "aggro" end
    if status == 1 and role ~= "TANK" then return "pulling" end
    return "safe"
end

function Rescue.Kind(layout, raid)
    if layout == "list" or layout == "grid" then return layout end
    return raid and "grid" or "list"
end

-- The window's size for count members: a list keeps its width and fits its rows; a grid has a column per
-- listed group (columns) as tall as the tallest. theme: a ThreatThemes entry.
function Rescue.Size(theme, rowHeight, kind, count, width, columns, tallest)
    local ranges = Geometry.WINDOW_RANGES
    local inset = Themes.Inset(theme)
    local spacing = theme.spacing or 0
    local chrome = inset * 2 + theme.title + theme.header + 2
    if kind == "grid" then
        columns = math.max(1, columns or 1)
        local gridWidth = inset * 2 + 4 + columns * Rescue.CELL_W + (columns - 1) * Rescue.GAP
        local height = chrome + Rescue.NUMBERS_H + math.max(1, tallest or 1) * (rowHeight + spacing) + 2
        return math.max(ranges.width[1], math.min(ranges.width[2], gridWidth)),
            math.max(ranges.height[1], math.min(ranges.height[2], height))
    end
    local height = chrome + math.max(1, count) * (rowHeight + spacing) + 2
    return width, math.max(ranges.height[1], math.min(ranges.height[2], height))
end

-- The body's least height with nobody listed: room for the empty-state line over two lines.
Rescue.EMPTY_H = 40

-- The window's size with nobody listed (solo, or the filter keeps nobody): the size it had before it became a Rescue
-- window (restore, a width and height) or its own, never shorter than the chrome and the empty-state line.
function Rescue.EmptySize(theme, width, height, restoreWidth, restoreHeight)
    local ranges = Geometry.WINDOW_RANGES
    local chrome = Themes.Inset(theme) * 2 + theme.title + theme.header + 2
    width = type(restoreWidth) == "number" and restoreWidth or width
    height = math.max(chrome + Rescue.EMPTY_H + 2, type(restoreHeight) == "number" and restoreHeight or height)
    return math.max(ranges.width[1], math.min(ranges.width[2], width)),
        math.max(ranges.height[1], math.min(ranges.height[2], height))
end

-- How many list rows fit the tallest window.
function Rescue.MaxRows(theme, rowHeight)
    local chrome = Themes.Inset(theme) * 2 + theme.title + theme.header + 4
    return math.max(1, math.floor((Geometry.WINDOW_RANGES.height[2] - chrome) / (rowHeight + (theme.spacing or 0))))
end

local function State(meter)
    local rescue = meter.rescue
    if not rescue then
        rescue = {
            slots = {}, candidates = {}, ordered = {}, cells = {}, numbers = {}, rects = {}, pending = {},
            count = 0, hidden = 0, kind = "list", group = "solo", lastRebuild = "none", rebuilds = 0,
            rosterRevision = -1, cursor = 0, clicks = { member = 0, header = 0 },
            bindingKeys = {}, bindingNames = {}, bindingKinds = {}, bindingStates = {}, bindingForms = {},
            reads = { dead = "unread", targetCheck = "unread", range = "unread", cooldown = "off" }, secure = "none",
            flashes = 0,
        }
        meter.rescue = rescue
    end
    return rescue
end

-- Every member of the group from the threat service's roster (its order, roles and raid groups; pets never).
-- Returns the count, whether it is a raid, and your raid group.
local function CollectLive(rescue, service)
    if service.rosterDirty or service.roleDirty then service:FlushPending() end
    if service.isSolo then return 0, false, nil end
    local raid = service.isRaid == true
    local count, playerGroup = 0, nil
    for index = 1, service.rosterCount do
        local entry = service.rosterPool[index]
        if entry.isMember and entry.unit and count < Secure.MAX_SLOTS then
            count = count + 1
            local candidate = rescue.candidates[count] or {}
            rescue.candidates[count] = candidate
            local number = tonumber(entry.unit:match("(%d+)$"))
            candidate.unit, candidate.sample = entry.unit, nil
            candidate.role, candidate.classToken = entry.role or "NONE", entry.classToken
            candidate.index = entry.unit == "player" and 0 or (number or count)
            candidate.group = raid and (entry.subgroup or math.floor(((number or count) - 1) / 5) + 1) or 1
            if entry.isPlayer then playerGroup = candidate.group end
        end
    end
    return count, raid, raid and playerGroup or nil
end

-- The threat windows' sample group (sample data, out of combat): you tanking and five members in every state.
local function CollectSample(rescue)
    local count = 0
    for index, member in ipairs(Sample.members or {}) do
        count = count + 1
        local candidate = rescue.candidates[count] or {}
        rescue.candidates[count] = candidate
        candidate.unit, candidate.role, candidate.classToken = member.unit, member.role, member.classToken
        candidate.index, candidate.group = index, 1
        candidate.sample = member
        candidate.look = member.isPlayer and SAMPLE_TANK or SAMPLE_LOOKS[member.name] or SAMPLE_SAFE
    end
    return count, false, nil
end

-- The player's class and what each modifier is bound to (names in the client's language), for the tooltip,
-- the range fade (the left binding's spell, when it goes on a target) and /ps diagnose.
local function UpdateBindings(rescue, console)
    local class = console.service and console.service:PlayerClass() or nil
    local bindings = console:RescueBindings()
    rescue.class = class
    rescue.classHasList = class ~= nil and Secure.SPELLS[class] ~= nil
    rescue.rangeSpell, rescue.headerWanted, rescue.formNeeded = nil, false, false
    for _, modifier in ipairs(Secure.MODIFIERS) do
        local key = Secure.Binding(bindings, class, modifier)
        local definition = key and Secure.Spell(class, key)
        if definition then
            local known = Secure.SpellKnown(definition.spell)
            local name = known ~= false and Secure.SpellName(definition.spell) or nil
            rescue.bindingKeys[modifier], rescue.bindingNames[modifier] = key, name
            rescue.bindingKinds[modifier], rescue.bindingForms[modifier] = definition.on, definition.form
            rescue.bindingStates[modifier] = (known == false and "missing") or (name and "known") or "unnamed"
            if definition.form and name then rescue.formNeeded = true end
            if modifier == "left" and definition.on == "target" and name then
                rescue.rangeSpell = definition.spell
                rescue.headerWanted = true
            end
        else
            rescue.bindingKeys[modifier], rescue.bindingNames[modifier] = nil, nil
            rescue.bindingKinds[modifier], rescue.bindingStates[modifier], rescue.bindingForms[modifier] = nil, nil, nil
        end
    end
    -- Bear Form's slot on the form bar, for the druid's [form:N] (read out of combat, at each rebuild).
    local service = console.service
    rescue.formSlot = rescue.formNeeded and service and service.BearFormSlot and service:BearFormSlot() or nil
    rescue.clicksOn = console:RescueClicksOn()
    if not rescue.clicksOn or rescue.sample then rescue.headerWanted = false end
end

-- Whether a bound spell was learned or lost since the last rebuild (SPELLS_CHANGED): its known answer no longer
-- matches what the buttons were given.
function Rescue.BindingsStale(meter)
    local rescue = meter.rescue
    if not rescue or not rescue.classHasList then return false end
    local bindings = meter.console:RescueBindings()
    for _, modifier in ipairs(Secure.MODIFIERS) do
        local key = Secure.Binding(bindings, rescue.class, modifier)
        local definition = key and Secure.Spell(rescue.class, key)
        if definition and (Secure.SpellKnown(definition.spell) == false) ~= (rescue.bindingStates[modifier] == "missing") then
            return true
        end
    end
    return false
end

-- The list's size (a list keeps its width) and position, written to the saved record; out of combat only.
local function Resize(meter, rescue)
    local config, theme = meter.config, meter.theme
    local rowHeight = config.rowHeight or theme.rowHeight
    local columns, tallest, run, lastGroup = 0, 0, 0, nil
    for index = 1, rescue.count do
        local group = rescue.slots[index].group
        if group ~= lastGroup then
            columns, run, lastGroup = columns + 1, 0, group
        end
        run = run + 1
        if run > tallest then tallest = run end
    end
    local width, height
    if rescue.count == 0 then
        width, height = Rescue.EmptySize(theme, config.width, config.height, config.rescueRestoreWidth, config.rescueRestoreHeight)
    else
        width, height = Rescue.Size(theme, rowHeight, rescue.kind, rescue.count, config.width, columns, tallest)
    end
    config.width, config.height = math.floor(width + 0.5), math.floor(height + 0.5)
    meter:Place()
end

-- Brings the window's secure buttons in (or parks them) before the layout, so the header's Taunt my target is
-- drawn only when a button will lie over it. True when the buttons are attached.
local function PrepareSecure(meter, rescue)
    local why
    if rescue.sample then
        why = "sample"
    elseif not rescue.clicksOn then
        why = "off"
    elseif not rescue.classHasList then
        why = "no-bindings"
    end
    if why then
        Secure.Detach(meter)
        rescue.secure = why
    else
        local ok, refused = Secure.Attach(meter)
        rescue.secure = ok and "ok" or refused or "failed"
    end
    if rescue.secure ~= "ok" then rescue.headerWanted = false end
    return rescue.secure == "ok"
end

local function DoRebuild(meter, rescue)
    local console, config = meter.console, meter.config
    local service = console.service
    local sample = console:IsSampleData()
    local count, raid, playerGroup
    if sample then
        count, raid, playerGroup = CollectSample(rescue)
    else
        count, raid, playerGroup = CollectLive(rescue, service)
    end
    rescue.sample, rescue.raid = sample, raid
    rescue.group = (sample and "party") or (service.isSolo and "solo") or (raid and "raid") or "party"
    local ordered, kept = rescue.ordered, 0
    for index = 1, count do
        local candidate = rescue.candidates[index]
        if Rescue.Keep(candidate, config.rescueFilter, playerGroup) then
            kept = kept + 1
            ordered[kept] = candidate
        end
    end
    for index = kept + 1, #ordered do ordered[index] = nil end
    table.sort(ordered, Rescue.Before)
    rescue.kind = Rescue.Kind(config.rescueLayout, raid)
    local shown = kept
    if rescue.kind == "list" then shown = math.min(kept, Rescue.MaxRows(meter.theme, config.rowHeight or meter.theme.rowHeight)) end
    for index = 1, shown do
        local slot = rescue.slots[index] or {}
        rescue.slots[index] = slot
        local candidate = ordered[index]
        slot.unit, slot.role, slot.classToken = candidate.unit, candidate.role, candidate.classToken
        slot.group, slot.index, slot.sample, slot.look = candidate.group, candidate.index, candidate.sample, candidate.look
        slot.dead, slot.noTarget, slot.far = false, false, false
        -- Aggro already shown before the rebuild is not news: no sound for it.
        local entry = not sample and service.rosterByUnit[slot.unit] or nil
        slot.wasAggro = entry ~= nil and Rescue.State(entry.role, entry.situation, entry.situationState) == "aggro"
    end
    rescue.count, rescue.hidden, rescue.filteredOut = shown, kept - shown, count - kept
    rescue.rosterRevision = service and service.rosterRevision or 0
    UpdateBindings(rescue, console)
    local attached = PrepareSecure(meter, rescue)
    Resize(meter, rescue)
    meter:Layout()
    if attached then Secure.Apply(meter, rescue.class, console:RescueBindings(), rescue.formSlot) end
    rescue.cursor = 0
end

-- Rebuilds the list: roster, filter, order, layout, size and bindings. In combat nothing changes: reason is
-- queued (roster, bindings, layout, position, visibility) for the one rebuild at combat end.
function Rescue.Rebuild(meter, reason)
    local rescue = State(meter)
    local console = meter.console
    if Secret.InCombat() then
        rescue.pending[reason or "roster"] = true
        console.rescuePending = true
        return false
    end
    for key in pairs(rescue.pending) do rescue.pending[key] = nil end
    local ok, err = pcall(DoRebuild, meter, rescue)
    rescue.rebuilds = rescue.rebuilds + 1
    rescue.lastRebuild = ok and "ok" or "error"
    rescue.lastError = not ok and tostring(err) or nil
    console:MarkDirty()
    return ok
end

-- Whether the window must hold still now: its secure buttons are its children and the UI is in combat.
function Rescue.Held(meter)
    return meter ~= nil and Secure.Attached(meter) and Secret.InCombat()
end

-- A list resizes by width only; a grid's size is fixed by its cells.
function Rescue.Resizable(meter)
    return not (meter.rescue and meter.rescue.kind == "grid")
end

-- A window switched to Rescue (out of combat: the console refuses the switch in combat).
function Rescue.Enter(meter)
    local rescue = State(meter)
    rescue.rosterRevision = -1
    return Rescue.Rebuild(meter, "layout")
end

local function HideCell(cell)
    if cell.glow and PS.TargetGlow then PS.TargetGlow.Hide(cell.glow) end
    cell.cUnit = nil
    cell:Hide()
end

-- Stops the border flash (its window hides or leaves Rescue mode).
function Rescue.StopFlash(meter)
    local flash = meter.rescueFlash
    if not flash then return end
    if flash.group:IsPlaying() then flash.group:Stop() end
    flash:Hide()
end

-- Hides Rescue's own frames (the window left Rescue mode, or redraws as a meter).
function Rescue.HideVisuals(meter)
    local rescue = meter.rescue
    if not rescue then return end
    for _, cell in ipairs(rescue.cells) do HideCell(cell) end
    for _, number in ipairs(rescue.numbers) do number:Hide() end
    local button = meter.header.rescueButton
    if button then button:Hide() end
    local cooldown = meter.header.rescueCooldown
    if cooldown then
        cooldown.wanted = false
        cooldown:Hide()
    end
    rescue.cooldownEnds = nil
    Rescue.StopFlash(meter)
end

-- Leaving Rescue mode: the buttons are parked, so the window moves and hides freely again.
function Rescue.Leave(meter)
    if not meter.rescue then return true end
    local detached = Secure.Detach(meter)
    Rescue.HideVisuals(meter)
    return detached
end

local function SetFont(text, theme)
    local font = theme.rowFont and rawget(_G, theme.rowFont) or rawget(_G, "GameFontHighlightSmall")
    if font then pcall(text.SetFontObject, text, font) end
end

local function NewText(parent, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH(justify or "LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    return text
end

local function CellEnter(cell)
    Rescue.ShowTooltip(cell.meter, cell.rescueIndex, cell)
    cell.highlight:Show()
end

local function CellLeave(cell)
    cell.highlight:Hide()
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(cell)) then GameTooltip:Hide() end
end

-- A cell is skinned as a threat row is (Meter's SkinRow): the theme's bar, the dark backdrop, the stripe.
local function SkinCell(cell, theme)
    Themes.ApplyBar(cell, theme)
    if Themes.SetKit(cell.backdrop, "bar-backdrop", true, false) then cell.backdrop:SetVertexColor(0.12, 0.12, 0.13, 0.8) end
    Themes.SetKit(cell.stripe, "row-stripe", true, false)
    cell.stripe:SetVertexColor(1, 1, 1, 0.5)
    Themes.SetKit(cell.highlight, "row-highlight", true, false)
    SetFont(cell.name, theme)
    SetFont(cell.state, theme)
    cell.rescueTheme = theme
    cell.cUnit = nil
end

local function NewCell(meter, index)
    local cell = CreateFrame("StatusBar", nil, meter.body)
    cell.meter, cell.rescueIndex = meter, index
    cell:SetMinMaxValues(0, 100)
    cell:SetValue(0)
    cell.backdrop = cell:CreateTexture(nil, "BACKGROUND")
    cell.backdrop:SetAllPoints()
    cell.stripe = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
    cell.stripe:SetAllPoints()
    cell.highlight = cell:CreateTexture(nil, "ARTWORK", nil, 6)
    cell.highlight:SetAllPoints()
    cell.highlight:Hide()
    cell.icon = cell:CreateTexture(nil, "OVERLAY")
    cell.marker = cell:CreateTexture(nil, "OVERLAY")
    cell.name = NewText(cell)
    cell.state = NewText(cell, "RIGHT")
    -- Without secure buttons over it (clicks off) the cell itself shows the tooltip.
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", CellEnter)
    cell:SetScript("OnLeave", CellLeave)
    cell:Hide()
    return cell
end

local function Cell(meter, rescue, index)
    local cell = rescue.cells[index]
    if not cell then
        cell = NewCell(meter, index)
        rescue.cells[index] = cell
    end
    if cell.rescueTheme ~= meter.theme then SkinCell(cell, meter.theme) end
    return cell
end

local function GroupLabel(meter, rescue, column)
    local number = rescue.numbers[column]
    if not number then
        number = NewText(meter.body, "CENTER")
        pcall(number.SetFontObject, number, rawget(_G, "GameFontDisableSmall"))
        rescue.numbers[column] = number
    end
    return number
end

-- The cell's parts for a list row (role icon, marker, name, the state column) or a grid cell (short name, the
-- small no-target mark at its right).
local function LayoutCellParts(cell, compact, height)
    cell.name:ClearAllPoints()
    cell.state:ClearAllPoints()
    cell.icon:ClearAllPoints()
    cell.marker:ClearAllPoints()
    if compact then
        cell.icon:Hide()
        cell.state:Hide()
        cell.name:SetPoint("LEFT", cell, "LEFT", 4, 0)
        cell.name:SetPoint("RIGHT", cell, "RIGHT", -13, 0)
        cell.marker:SetPoint("RIGHT", cell, "RIGHT", -1, 0)
        cell.marker:SetSize(12, 12)
        return
    end
    local size = math.max(8, math.min(16, height - 2))
    local y = -math.floor((height - size) / 2)
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, y)
    cell.icon:SetSize(size, size)
    cell.marker:SetPoint("TOPLEFT", cell, "TOPLEFT", 4 + size, y)
    cell.marker:SetSize(size, size)
    cell.name:SetPoint("LEFT", cell, "LEFT", 6 + size * 2, 0)
    cell.name:SetPoint("RIGHT", cell, "RIGHT", -(Rescue.STATE_W + 4), 0)
    cell.state:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    cell.state:SetWidth(Rescue.STATE_W)
    cell.state:Show()
end

-- A frame's four edges, size px wide (1 by default), in colour.
local function Edges(frame, colour, size, layer)
    size = size or 1
    frame.edges = frame.edges or {}
    for index = 1, 4 do
        local edge = frame.edges[index] or frame:CreateTexture(nil, layer or "BORDER")
        frame.edges[index] = edge
        edge:ClearAllPoints()
        if index == 1 then
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            edge:SetHeight(size)
        elseif index == 2 then
            edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            edge:SetHeight(size)
        elseif index == 3 then
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            edge:SetWidth(size)
        else
            edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            edge:SetWidth(size)
        end
        edge:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1)
    end
end

-- The header's Taunt my target: what it looks like (an ordinary frame; the secure button lies over it).
local function LayoutHeaderButton(meter, rescue, x, y)
    local header, theme = meter.header, meter.theme
    local button = header.rescueButton
    if not rescue.headerWanted then
        if button then button:Hide() end
        rescue.headerRect = nil
        return
    end
    if not button then
        button = CreateFrame("Frame", nil, header)
        button.fill = button:CreateTexture(nil, "BACKGROUND")
        button.fill:SetAllPoints()
        button.text = NewText(button)
        button.text:SetPoint("LEFT", button, "LEFT", 6, 0)
        header.rescueButton = button
    end
    local look = BUTTON_LOOK[theme.id] or BUTTON_LOOK.forge
    button.text:SetText(L["Taunt my target"])
    button.text:SetTextColor(look.text[1], look.text[2], look.text[3])
    button.fill:SetColorTexture(look.fill[1], look.fill[2], look.fill[3], look.fill[4])
    Edges(button, look.edge)
    local textWidth = button.text.GetStringWidth and button.text:GetStringWidth() or 0
    if type(textWidth) ~= "number" or textWidth <= 0 then textWidth = 96 end
    local width, height = math.ceil(textWidth) + 12, 15
    local top = math.floor((theme.header - height) / 2)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", header, "TOPLEFT", 3, -top)
    button:SetSize(width, height)
    button:Show()
    local rect = rescue.headerRect or {}
    rect.x, rect.y, rect.width, rect.height = x + 3, y + top, width, height
    rescue.headerRect = rect
end

local READY = { 0.35, 0.88, 0.4 }

local function SpellTexture(spell)
    local api = (C_Spell and C_Spell.GetSpellTexture) or rawget(_G, "GetSpellTexture")
    if type(api) ~= "function" then return nil end
    local ok, texture = pcall(api, spell)
    if not ok then return nil end
    return texture
end

local function ShowReady(rescue, display)
    rescue.cooldownEnds, display.cSecond = nil, nil
    if display.cStart ~= 0 then
        display.cStart, display.cDuration = 0, 0
        pcall(display.cooldown.SetCooldown, display.cooldown, 0, 0)
    end
    display.label:SetFormattedText(L["%s ready"], rescue.bindingNames.left or "")
    display.label:SetTextColor(READY[1], READY[2], READY[3])
end

-- Counts the shown cooldown down, from the numbers SPELL_UPDATE_COOLDOWN gave (no read): the console's refresh tick
-- calls it, and the text changes once a second at most.
function Rescue.TickCooldown(meter)
    local rescue = meter.rescue
    local display = meter.header.rescueCooldown
    local ends = rescue and rescue.cooldownEnds
    if not ends or not display or not display.wanted then return end
    local now = type(GetTime) == "function" and Secret.Number(GetTime()) or nil
    if not now then return end
    if now >= ends then return ShowReady(rescue, display) end
    local seconds = math.ceil(ends - now)
    if seconds == display.cSecond then return end
    display.cSecond = seconds
    display.label:SetFormattedText(L["%s %ds"], rescue.bindingNames.left or "", seconds)
    display.label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
end

-- Reads the main taunt's cooldown (the left binding, on a target) on SPELL_UPDATE_COOLDOWN and at each layout:
-- the swipe on its icon and "<spell> 6s" or "<spell> ready". A protected or missing answer hides it (never a
-- guess).
function Rescue.UpdateCooldown(meter)
    local rescue = meter.rescue
    local display = meter.header.rescueCooldown
    if not rescue or not display or not display.wanted then return false end
    local start, duration, enabled, state = Secret.SpellCooldown(rescue.rangeSpell)
    rescue.reads.cooldown = state
    if not (start and duration) then
        rescue.cooldownEnds = nil
        display:Hide()
        return false
    end
    display:Show()
    if enabled == false or enabled == 0 then
        -- Its cooldown waits to start: not ready, and no time to count.
        ShowReady(rescue, display)
        display.label:SetText("")
        return true
    end
    if duration <= Rescue.GCD then
        ShowReady(rescue, display)
        return true
    end
    if display.cStart ~= start or display.cDuration ~= duration then
        display.cStart, display.cDuration = start, duration
        pcall(display.cooldown.SetCooldown, display.cooldown, start, duration)
    end
    rescue.cooldownEnds, display.cSecond = start + duration, nil
    Rescue.TickCooldown(meter)
    return true
end

-- The header's taunt cooldown (Show my taunt's cooldown), at its right: the spell's icon with the client's swipe,
-- and the text beside it. Ordinary frames: they change freely in combat.
local function LayoutCooldown(meter, rescue)
    local header, config = meter.header, meter.config
    local display = header.rescueCooldown
    if not config.rescueCooldown or not rescue.rangeSpell then
        if display then
            display.wanted = false
            display:Hide()
        end
        rescue.cooldownEnds = nil
        rescue.reads.cooldown = config.rescueCooldown and "unavailable" or "off"
        return
    end
    if not display then
        display = CreateFrame("Frame", nil, header)
        display.icon = display:CreateTexture(nil, "ARTWORK")
        display.icon:SetPoint("RIGHT", display, "RIGHT", 0, 0)
        display.icon:SetSize(14, 14)
        display.cooldown = CreateFrame("Cooldown", nil, display, "CooldownFrameTemplate")
        display.cooldown:SetAllPoints(display.icon)
        if display.cooldown.SetHideCountdownNumbers then display.cooldown:SetHideCountdownNumbers(true) end
        display.label = NewText(display, "RIGHT")
        display.label:SetPoint("RIGHT", display.icon, "LEFT", -4, 0)
        header.rescueCooldown = display
    end
    display.wanted = true
    display:ClearAllPoints()
    display:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    display:SetSize(150, 15)
    SetFont(display.label, meter.theme)
    if display.spell ~= rescue.rangeSpell then
        display.spell, display.cStart, display.cDuration = rescue.rangeSpell, nil, nil
        local texture = SpellTexture(rescue.rangeSpell)
        if not (Secret.HasValue(texture) and pcall(display.icon.SetTexture, display.icon, texture)) then
            display.icon:SetTexture(nil)
        end
    end
    display.cSecond = nil
    Rescue.UpdateCooldown(meter)
end

local function HideScroll(body)
    for _, texture in ipairs(body.track) do texture:Hide() end
    for _, texture in ipairs(body.thumb) do texture:Hide() end
    -- The meter's scroll bar redraws itself when the window is a meter again.
    body.scrollTheme = nil
end

-- Places the header, body and cells from the frame's size (Meter:Layout hands over after the title). Each
-- cell's rectangle in the window is kept for its secure button, which is moved only out of combat.
function Rescue.Layout(meter, inset, top, innerWidth)
    local rescue = State(meter)
    local frame, theme, config, body = meter.frame, meter.theme, meter.config, meter.body
    for _, row in ipairs(meter.rows) do row:Hide() end
    HideScroll(body)
    local headerHeight = meter:LayoutHeader(inset, top, innerWidth, true)
    for _, label in pairs(meter.header.labels) do label:Hide() end
    LayoutHeaderButton(meter, rescue, inset, top)
    LayoutCooldown(meter, rescue)
    local frameHeight = Secret.ReadNumber(frame, "GetHeight") or config.height
    local bodyTop = top + headerHeight
    local rowHeight, spacing = config.rowHeight or theme.rowHeight, theme.spacing or 0
    local bodyWidth = innerWidth - 2
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + 1, -(bodyTop + 1))
    body:SetSize(bodyWidth, math.max(rowHeight, frameHeight - bodyTop - inset - 1))
    meter.rowHeight, meter.spacing, meter.rowWidth = rowHeight, spacing, bodyWidth
    local originX, originY = inset + 1, bodyTop + 1
    local compact = rescue.kind == "grid"
    local column, x, rowIndex, lastGroup = 0, 0, 0, nil
    for index = 1, rescue.count do
        local slot, cell = rescue.slots[index], Cell(meter, rescue, index)
        local cellX, cellY, cellWidth
        if compact then
            if slot.group ~= lastGroup then
                column, rowIndex, lastGroup = column + 1, 0, slot.group
                x = 1 + (column - 1) * (Rescue.CELL_W + Rescue.GAP)
                local number = GroupLabel(meter, rescue, column)
                number:ClearAllPoints()
                number:SetPoint("TOP", body, "TOPLEFT", x + Rescue.CELL_W / 2, 0)
                number:SetText(string.format(L["Group %d"], slot.group))
                number:SetTextColor(theme.headerText[1], theme.headerText[2], theme.headerText[3])
                number:Show()
            end
            rowIndex = rowIndex + 1
            cellX, cellY, cellWidth = x, Rescue.NUMBERS_H + (rowIndex - 1) * (rowHeight + spacing), Rescue.CELL_W
        else
            cellX, cellY, cellWidth = 0, (index - 1) * (rowHeight + spacing), bodyWidth
        end
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", body, "TOPLEFT", cellX, -cellY)
        cell:SetSize(cellWidth, rowHeight)
        cell.stripe:SetShown(not compact and index % 2 == 0)
        LayoutCellParts(cell, compact, rowHeight)
        cell.rescueCompact, cell.cUnit = compact, nil
        local rect = rescue.rects[index] or {}
        rescue.rects[index] = rect
        rect.x, rect.y, rect.width, rect.height = originX + cellX, originY + cellY, cellWidth, rowHeight
        cell:Show()
    end
    for index = rescue.count + 1, #rescue.cells do HideCell(rescue.cells[index]) end
    for index = column + 1, #rescue.numbers do rescue.numbers[index]:Hide() end
    body.more:ClearAllPoints()
    body.more:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(inset + 8), inset + 1)
    body.more:SetText(rescue.hidden > 0 and string.format(L["+%d more"], rescue.hidden) or "")
    body.empty:ClearAllPoints()
    body.empty:SetPoint("CENTER", body, "CENTER", 0, 0)
    body.empty:SetWidth(math.max(20, innerWidth - 8))
    if not Secret.InCombat() then
        Secure.Place(meter)
    elseif Secure.Attached(meter) then
        rescue.pending.layout = true
        meter.console.rescuePending = true
    end
end

local function ClassColour(classToken)
    local r, g, b = Secret.ClassColour(classToken)
    if r then return r, g, b end
    return 0.55, 0.58, 0.62
end

local function ShowGlow(cell, compact, colour)
    local Glow = PS.TargetGlow
    if not Glow then return end
    local glow = cell.glow
    if not glow then
        glow = Glow.Create(cell)
        cell.glow = glow
        Glow.Style(glow, { targetGlowSpread = compact and Rescue.GLOW_RAID_SPREAD or Rescue.GLOW_SPREAD,
            targetGlowOpacity = Rescue.GLOW_OPACITY, targetGlowPulse = true, targetGlowEven = true })
        cell.glowCompact = compact
    elseif cell.glowCompact ~= compact then
        Glow.Style(glow, { targetGlowSpread = compact and Rescue.GLOW_RAID_SPREAD or Rescue.GLOW_SPREAD,
            targetGlowOpacity = Rescue.GLOW_OPACITY, targetGlowPulse = true, targetGlowEven = true })
        cell.glowCompact = compact
    end
    -- Over the neighbouring cells (1 px apart, a glow under them would not show): the cell two levels up, its
    -- glow one.
    local base = (cell:GetParent() and cell:GetParent().GetFrameLevel and cell:GetParent():GetFrameLevel() or 0) + 1
    cell:SetFrameLevel(base + 2)
    Glow.SetLevel(glow, base + 1)
    Glow.Place(glow, cell, cell, cell, cell)
    Glow.Paint(glow, colour[1], colour[2], colour[3])
    Glow.Show(glow)
end

local function HideGlow(cell)
    if cell.glow and cell.glow.shown and PS.TargetGlow then PS.TargetGlow.Hide(cell.glow) end
end

local flags = {}

-- The member's aggro folded inside the client from the protected "holding it" answers about them (a party
-- only; the threat service keeps them per mob): the fill's and the word's alpha are picked, never read. False
-- when there are none or the client has no such sink (the cell stays neutral).
local function ShowFolded(cell, service, unit)
    local count = service.MemberHoldFlags and service:MemberHoldFlags(unit, flags, MAX_FLAGS) or 0
    if count == 0 then return false end
    local ok, alpha = true, 0
    for index = 1, count do
        if ok then ok, alpha = Secret.Pick(flags[index], 1, alpha) end
    end
    for index = 1, count do flags[index] = nil end
    if not ok then return false end
    local losing = ThreatText.Palette().losing
    if not pcall(cell.SetStatusBarColor, cell, losing[1], losing[2], losing[3], alpha) then return false end
    cell:SetValue(100)
    cell.state:SetText(L["AGGRO"])
    cell.state:SetTextColor(1, 1, 1)
    if not pcall(cell.state.SetAlpha, cell.state, alpha) then cell.state:SetText("") end
    return true
end

-- Writes one cell. look: state, dead, noTarget, far. name: readable text, opaque for the text sink. A cell is
-- written only when what it shows changed; a protected name or a folded state always goes to its sink.
local function FillCell(cell, theme, unit, look, role, classToken, name, opaque, hasOpaque, service, foldable)
    local state, dead, noTarget, far = look.state, look.dead == true, look.noTarget == true, look.far == true
    if not hasOpaque and not foldable and not cell.cFolded and cell.cUnit == unit and cell.cState == state
        and cell.cDead == dead and cell.cNoTarget == noTarget and cell.cFar == far and cell.cName == name
        and cell.cRole == role and cell.cClass == classToken and cell.cTheme == theme then
        return
    end
    cell.cUnit, cell.cState, cell.cDead, cell.cNoTarget, cell.cFar = unit, state, dead, noTarget, far
    cell.cName, cell.cRole, cell.cClass, cell.cTheme, cell.cFolded = name, role, classToken, theme, false
    local compact = cell.rescueCompact
    local palette = ThreatText.Palette()
    cell:SetAlpha((dead and DEAD_ALPHA) or (far and FAR_ALPHA) or 1)
    local fill = (not dead and state == "aggro" and palette.losing) or (not dead and state == "pulling" and palette.warning)
        or nil
    if fill then
        -- Opaque, unlike the meter's bars: these are alarms, read at a glance.
        cell:SetStatusBarColor(fill[1], fill[2], fill[3], 1)
        cell:SetValue(100)
    else
        cell:SetValue(0)
    end
    if not (hasOpaque and pcall(cell.name.SetText, cell.name, opaque)) then cell.name:SetText(name or unit or "") end
    if dead then
        cell.name:SetTextColor(DEAD[1], DEAD[2], DEAD[3])
    elseif fill then
        -- Over a full fill the name reads in white; the class shows in the role icon and the tooltip.
        cell.name:SetTextColor(1, 1, 1)
    elseif classToken then
        cell.name:SetTextColor(ClassColour(classToken))
    else
        local classFile, hasClass = Secret.ClassFile(unit)
        if not (hasClass and Secret.SetClassTextColour(cell.name, classFile)) then cell.name:SetTextColor(ClassColour(nil)) end
        cell.cClass = false
    end
    local word, wordColour = STATE_WORDS[state], WHITE
    if dead then
        word, wordColour = L["DEAD"], DEAD
    elseif noTarget and state == "safe" then
        word, wordColour = L["NO TARGET"], MUTED
    elseif far and state == "safe" then
        word, wordColour = L["OUT OF RANGE"], MUTED
    elseif state == "tank" then
        wordColour = MUTED
    end
    cell.state:SetAlpha(1)
    if compact then
        Themes.Icon(cell.marker, noTarget and "icon-idle" or nil, theme)
        cell.marker:SetAlpha(0.85)
    else
        Themes.Icon(cell.icon, ROLE_ICONS[role], theme)
        Themes.Icon(cell.marker, (state == "tank" and "icon-aggro") or (noTarget and "icon-idle") or nil, theme)
        cell.marker:SetAlpha(1)
        cell.state:SetText(word or "")
        cell.state:SetTextColor(wordColour[1], wordColour[2], wordColour[3])
    end
    if state == "aggro" and not dead then
        ShowGlow(cell, compact, palette.losing)
    else
        HideGlow(cell)
        local parent = cell:GetParent()
        cell:SetFrameLevel((parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 1)
    end
    if foldable and state == "unknown" and not dead and ShowFolded(cell, service, unit) then
        cell.cFolded = true
        if compact then cell.state:SetText("") end
    end
end

local function EmptyCell(cell)
    if cell.cUnit == false then return end
    cell.cUnit, cell.cFolded = false, false
    HideGlow(cell)
    cell:SetValue(0)
    cell:SetAlpha(1)
    cell.name:SetText("")
    cell.state:SetText("")
    Themes.Icon(cell.icon, nil, cell.rescueTheme)
    Themes.Icon(cell.marker, nil, cell.rescueTheme)
end

local SAMPLE_LOOK_FIELDS = { state = "safe" }

-- What /ps diagnose says about a read over one tick: the worst word wins (api-missing, protected, readable).
local RANK = { ["api-missing"] = 4, protected = 3, readable = 2, unavailable = 1 }
local tickReads = {}
local function Note(key, word)
    local seen = tickReads[key]
    if not seen or RANK[word] > RANK[seen] then tickReads[key] = word end
end

-- Re-reads a member's death, target and range (each a protected read: an unknown answer shows nothing). True
-- when a cell changes.
local function ReadModifiers(rescue, slot)
    local unit = slot.unit
    local deadRead = Secret.ReadBoolean(UnitIsDeadOrGhost, unit)
    Note("dead", (type(UnitIsDeadOrGhost) ~= "function" and "api-missing") or (deadRead == nil and "protected") or "readable")
    local target = Secret.TargetToken(unit)
    local exists = Secret.ReadBoolean(UnitExists, target)
    local noTarget = false
    if exists == false then
        noTarget = true
        Note("targetCheck", "readable")
    elseif exists == true then
        local hostile = Secret.ReadBoolean(UnitCanAttack, "player", target)
        local gone = Secret.ReadBoolean(UnitIsDead, target)
        noTarget = hostile == false or gone == true
        Note("targetCheck", (hostile == nil or gone == nil) and "protected" or "readable")
    else
        Note("targetCheck", "protected")
    end
    local far = false
    if rescue.rangeSpell and exists == true and not noTarget then
        local inRange = PS.Range and PS.Range.SpellInRange and PS.Range.SpellInRange(rescue.rangeSpell, target)
        far = inRange == false
        Note("range", inRange == nil and "protected" or "readable")
    elseif not rescue.rangeSpell then
        Note("range", "unavailable")
    end
    local dead = deadRead == true
    if dead == slot.dead and noTarget == slot.noTarget and far == slot.far then return false end
    slot.dead, slot.noTarget, slot.far = dead, noTarget, far
    return true
end

-- The refresh tick's share: up to budget listed members' modifiers on a rolling cursor. True when a cell
-- changes (the console redraws).
function Rescue.Tick(meter, budget)
    local rescue = meter.rescue
    if not rescue or rescue.sample or rescue.count == 0 then return false end
    local changed = false
    for key in pairs(tickReads) do tickReads[key] = nil end
    for _ = 1, math.min(budget, rescue.count) do
        rescue.cursor = rescue.cursor % rescue.count + 1
        if ReadModifiers(rescue, rescue.slots[rescue.cursor]) then changed = true end
    end
    for key, word in pairs(tickReads) do rescue.reads[key] = word end
    return changed
end

-- Plays a choice on the Master channel: a built-in sound, or a LibSharedMedia one while LSM has it (else the
-- default).
function Rescue.PlaySound(key)
    local sound = sounds[key]
    if not sound then
        local Media = PS.Media
        local path = Media and Media.SoundPath and Rescue.IsSoundKey(key, false) and Media.SoundPath(key) or nil
        if path and type(PlaySoundFile) == "function" then return (pcall(PlaySoundFile, path, "Master")) end
        sound = sounds[Rescue.DEFAULTS.rescueSoundKey]
    end
    if type(PlaySound) ~= "function" then return false end
    local id = type(SOUNDKIT) == "table" and SOUNDKIT[sound.kit] or sound.id
    return (pcall(PlaySound, id, "Master"))
end

local function HideFlash(group)
    local frame = group:GetParent()
    if frame then frame:Hide() end
end

-- The window's border flash: an overlay over its edges, made the first time it is wanted, faded in and out by an
-- AnimationGroup (no Lua per frame). An ordinary frame, so it plays in combat. False on a client without
-- animations.
local function FlashFrame(meter)
    local flash = meter.rescueFlash
    if flash ~= nil then return flash end
    flash = false
    local frame = CreateFrame("Frame", nil, meter.frame)
    if type(frame.CreateAnimationGroup) == "function" then
        frame:SetAllPoints(meter.frame)
        -- Over the cells and their secure buttons; it takes no mouse.
        frame:SetFrameLevel((meter.frame.GetFrameLevel and meter.frame:GetFrameLevel() or 0) + 12)
        if frame.EnableMouse then frame:EnableMouse(false) end
        frame:SetAlpha(0)
        local group = frame:CreateAnimationGroup()
        for index = 1, Rescue.FLASH_TIMES * 2 do
            local fade = group:CreateAnimation("Alpha")
            local rising = index % 2 == 1
            fade:SetFromAlpha(rising and 0 or 1)
            fade:SetToAlpha(rising and 1 or 0)
            fade:SetDuration(rising and Rescue.FLASH_IN or Rescue.FLASH_OUT)
            fade:SetOrder(index)
        end
        group:SetScript("OnFinished", HideFlash)
        frame.group = group
        flash = frame
    end
    frame:Hide()
    meter.rescueFlash = flash
    return flash
end

-- Flashes the border once (two pulses) in the palette's aggro red. True when it plays.
function Rescue.Flash(meter)
    local flash = FlashFrame(meter)
    if not flash then return false end
    local losing = ThreatText.Palette().losing
    Edges(flash, { losing[1], losing[2], losing[3], 1 }, Rescue.FLASH_EDGE, "OVERLAY")
    if flash.group:IsPlaying() then flash.group:Stop() end
    flash:Show()
    flash.group:Play()
    meter.rescue.flashes = meter.rescue.flashes + 1
    return true
end

local function Summary(rescue, filter, aggro, pulling)
    if rescue.lastAggro == aggro and rescue.lastPulling == pulling and rescue.lastFilter == filter then
        return rescue.summaryText
    end
    rescue.lastAggro, rescue.lastPulling, rescue.lastFilter = aggro, pulling, filter
    local text = ""
    if aggro > 0 and pulling > 0 then
        text = string.format(L["%d aggro, %d pulling"], aggro, pulling)
    elseif aggro > 0 then
        text = string.format(L["%d aggro"], aggro)
    elseif pulling > 0 then
        text = string.format(L["%d pulling"], pulling)
    end
    if text ~= "" and FILTER_SHORT[filter] then text = string.format(L["%s: %s"], FILTER_SHORT[filter], text) end
    rescue.summaryText = text
    return text
end

-- Draws the cells from the threat service (or the sample group). A roster change rebuilds the list out of
-- combat; in combat each cell keeps its token and shows whoever it names now (an emptied token empties it).
function Rescue.Render(meter, source)
    local rescue = State(meter)
    local console, config = meter.console, meter.config
    local service = console.service
    local sample = source ~= service
    if sample ~= (rescue.sample == true) or (not sample and service and rescue.rosterRevision ~= service.rosterRevision) then
        Rescue.Rebuild(meter, "roster")
    end
    local theme = meter.theme
    local aggro, pulling, newAggro = 0, 0, false
    local foldable = not rescue.raid and not rescue.sample
    for index = 1, rescue.count do
        local slot, cell = rescue.slots[index], rescue.cells[index]
        if cell then
            local state
            if slot.sample and not sample then
                -- Sample data went off in combat: no made-up member stays on show until the rebuild.
                EmptyCell(cell)
            elseif slot.sample then
                local member = slot.sample
                local look = slot.look or SAMPLE_LOOK_FIELDS
                state = look.state
                FillCell(cell, theme, slot.unit, look, member.role, member.classToken, member.name, nil, false, nil, false)
            else
                local entry = service and service.rosterByUnit[slot.unit]
                if entry then
                    state = Rescue.State(entry.role, entry.situation, entry.situationState)
                    local look = slot.lookLive or {}
                    slot.lookLive = look
                    look.state, look.dead, look.noTarget, look.far = state, slot.dead, slot.noTarget, slot.far
                    FillCell(cell, theme, slot.unit, look, entry.role, entry.classToken, entry.name, entry.nameOpaque,
                        entry.hasOpaqueName == true, service,
                        foldable and entry.role ~= "TANK" and entry.situationState == "protected")
                    -- A sound is only for a readable change to aggro, by a member other than a tank.
                    if state == "aggro" and entry.role ~= "TANK" and not slot.dead then
                        if not slot.wasAggro then newAggro = true end
                        slot.wasAggro = true
                    else
                        slot.wasAggro = false
                    end
                else
                    EmptyCell(cell)
                end
            end
            if state == "aggro" then aggro = aggro + 1 elseif state == "pulling" then pulling = pulling + 1 end
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(cell) then Rescue.ShowTooltip(meter, index, cell) end
        end
    end
    local body = meter.body
    if rescue.count == 0 then
        body.empty:SetText(rescue.group == "solo" and L["Not in a group. Rescue lists your party or raid."]
            or L["Nobody in your group matches Show."])
        body.empty:Show()
    else
        body.empty:Hide()
    end
    meter.titleBar.text:SetText(config.name or "")
    meter.titleBar.summary:SetText(Summary(rescue, config.rescueFilter, aggro, pulling))
    -- The flash is for the change only: a member who stays on aggro does not flash again.
    if newAggro and config.rescueFlash then Rescue.Flash(meter) end
    if newAggro and config.rescueSound then
        local now = type(GetTime) == "function" and GetTime() or 0
        if not rescue.soundAt or now - rescue.soundAt >= (config.rescueSoundGap or 3) then
            rescue.soundAt = now
            rescue.soundsPlayed = (rescue.soundsPlayed or 0) + 1
            Rescue.PlaySound(config.rescueSoundKey)
        end
    end
end

local ROLE_LABELS = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }

-- Whether a druid's form bindings cannot cast now: the threat service's one form reader readably says the player
-- is out of Bear Form (unknown says nothing).
local function OutOfBearForm(rescue, service)
    if not rescue.formNeeded or not service or not service.ReadPlayerForm then return false end
    return service:ReadPlayerForm(rescue.class) == "none"
end

local BEAR_FORM_NEEDED = { 1, 0.62, 0.3 }

-- What a click does, per bound modifier (a line each), and why clicks are off when they are.
local function AddClickLines(rescue, service)
    if rescue.sample then
        GameTooltip:AddLine(L["Sample data: clicks do nothing."], 0.62, 0.72, 0.82)
        return
    end
    if rescue.secure == "off" then
        GameTooltip:AddLine(L["Clicks are off (Studio › Settings › Modules › Threat › Threat windows)."], 0.62, 0.72, 0.82, true)
        return
    elseif rescue.secure == "failed" then
        GameTooltip:AddLine(L["Clicks are unavailable on this client; the window still shows who needs help."],
            0.62, 0.72, 0.82, true)
        return
    elseif rescue.secure == "no-bindings" then
        GameTooltip:AddLine(L["Your class has no taunt to bind; the window shows who needs help."], 0.62, 0.72, 0.82, true)
        return
    end
    local any = false
    for _, modifier in ipairs(Secure.MODIFIERS) do
        local name, kind, state = rescue.bindingNames[modifier], rescue.bindingKinds[modifier], rescue.bindingStates[modifier]
        if state == "known" and name then
            local text = name
            if kind == "target" then
                text = string.format(L["%s on their target"], name)
            elseif kind == "member" then
                text = string.format(L["%s on them"], name)
            end
            GameTooltip:AddDoubleLine(Secure.MODIFIER_LABELS[modifier], text, 1, 0.82, 0, 1, 1, 1)
            any = true
        elseif state == "missing" and name == nil then
            GameTooltip:AddLine(string.format(L["%s: a spell you do not know (unbound)."], Secure.MODIFIER_LABELS[modifier]),
                0.72, 0.72, 0.72, true)
        end
    end
    if not any then GameTooltip:AddLine(L["No clicks are bound."], 0.72, 0.72, 0.72) end
    if any and OutOfBearForm(rescue, service) then
        GameTooltip:AddLine(L["Bear Form needed."], BEAR_FORM_NEEDED[1], BEAR_FORM_NEEDED[2], BEAR_FORM_NEEDED[3])
    end
end

-- The member's tooltip: name in class colour, state, their target, and what each click does.
function Rescue.ShowTooltip(meter, index, owner)
    local rescue = meter and meter.rescue
    local slot = rescue and index and index <= rescue.count and rescue.slots[index]
    if not slot or not GameTooltip then return end
    local service = meter.console.service
    local entry = not slot.sample and service and service.rosterByUnit[slot.unit] or nil
    if not slot.sample and not entry then return end
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local role, classToken, look
    if slot.sample then
        role, classToken, look = slot.sample.role, slot.sample.classToken, slot.look or SAMPLE_LOOK_FIELDS
        GameTooltip:SetText(slot.sample.name or "", ClassColour(classToken))
    else
        role, classToken, look = entry.role, entry.classToken, slot.lookLive or SAMPLE_LOOK_FIELDS
        if not (entry.hasOpaqueName and pcall(GameTooltip.SetText, GameTooltip, entry.nameOpaque)) then
            GameTooltip:SetText(entry.name or slot.unit, ClassColour(classToken))
        end
    end
    if ROLE_LABELS[role] then GameTooltip:AddLine(ROLE_LABELS[role], 0.72, 0.72, 0.72) end
    local state = look.state or "unknown"
    if look.dead then
        GameTooltip:AddLine(L["Dead."], DEAD[1], DEAD[2], DEAD[3])
    else
        local colour = (state == "aggro" and ThreatText.Palette().losing) or (state == "pulling" and ThreatText.Palette().warning)
            or WHITE
        GameTooltip:AddLine(STATE_TIPS[state] or STATE_TIPS.unknown, colour[1], colour[2], colour[3])
    end
    if not slot.sample then
        local ok, targetName = pcall(UnitName, Secret.TargetToken(slot.unit))
        if ok and Secret.IsSecret(targetName) then
            pcall(GameTooltip.AddDoubleLine, GameTooltip, L["Their target"], targetName, 1, 0.82, 0, 1, 1, 1)
        elseif ok and Secret.String(targetName) then
            GameTooltip:AddLine(string.format(L["Their target: %s"], targetName), 1, 1, 1)
        end
    end
    if look.noTarget then
        GameTooltip:AddLine(L["No enemy targeted: a click on their target does nothing."], 0.72, 0.72, 0.72, true)
    elseif look.far then
        GameTooltip:AddLine(L["Their target is out of your range."], 0.72, 0.72, 0.72, true)
    end
    GameTooltip:AddLine(" ")
    AddClickLines(rescue, service)
    if next(rescue.pending) then
        GameTooltip:AddLine(L["The group changed in combat: the list is updated when combat ends."], 1, 0.82, 0.45, true)
    end
    GameTooltip:Show()
end

local function ShowHeaderTooltip(meter, owner)
    local rescue = meter.rescue
    if not rescue or not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(L["Taunt my target"])
    local name = rescue.bindingNames.left
    if name then GameTooltip:AddLine(string.format(L["Casts %s on your target, as a macro button would."], name), 1, 1, 1, true) end
    if rescue.bindingForms.left and OutOfBearForm(rescue, meter.console.service) then
        GameTooltip:AddLine(L["Bear Form needed."], BEAR_FORM_NEEDED[1], BEAR_FORM_NEEDED[2], BEAR_FORM_NEEDED[3])
    end
    GameTooltip:Show()
end

-- The secure buttons' hooked OnEnter and OnLeave (no handler of Blizzard's is replaced).
function Rescue.OnSlotEnter(button)
    local meter = button.meter
    if not meter or not meter.rescue then return end
    if button.rescueKind == "header" then return ShowHeaderTooltip(meter, button) end
    local cell = meter.rescue.cells[button.rescueIndex]
    if cell then cell.highlight:Show() end
    Rescue.ShowTooltip(meter, button.rescueIndex, button)
end

function Rescue.OnSlotLeave(button)
    local meter = button.meter
    local cell = meter and meter.rescue and meter.rescue.cells[button.rescueIndex]
    if cell then cell.highlight:Hide() end
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(button)) then GameTooltip:Hide() end
end

-- Applies everything queued in combat: one rebuild per Rescue window with work queued.
function Rescue.OnCombatEnd(meter)
    local rescue = meter.rescue
    if not rescue or not next(rescue.pending) then return false end
    return Rescue.Rebuild(meter, "combat")
end

local function PendingWords(rescue)
    local words = {}
    for _, key in ipairs({ "roster", "bindings", "layout", "position", "visibility", "combat" }) do
        if rescue.pending[key] then words[#words + 1] = key end
    end
    return #words > 0 and table.concat(words, ",") or "none"
end

-- The situation read over the listed members: readable, protected, folded (a party's protected answers
-- folded), api-missing, or unread.
local function SituationWord(rescue, service)
    if type(UnitThreatSituation) ~= "function" then return "api-missing" end
    if rescue.sample or not service then return "unread" end
    local word = "unread"
    for index = 1, rescue.count do
        local entry = service.rosterByUnit[rescue.slots[index].unit]
        local state = entry and entry.situationState
        if state == "protected" then
            return rescue.raid and "protected" or "folded"
        elseif state == "readable" or state == "none" then
            word = "readable"
        elseif state == "error" or state == "unavailable" then
            word = state
        end
    end
    return word
end

-- /ps diagnose: one window's Rescue facts, readable values and state words only.
function Rescue.Report(meter, console)
    local rescue = State(meter)
    local config = meter.config
    local service = console.service
    local bindings = {}
    for _, modifier in ipairs(Secure.MODIFIERS) do
        local key = rescue.bindingKeys[modifier]
        if key then bindings[modifier] = string.format("%s %s", key, rescue.bindingStates[modifier] or "unknown") end
    end
    local buttons = 0
    local pool = meter.rescueButtons
    if pool and pool.attached then
        for index = 1, rescue.count do
            local written = pool.slots[index].rescueAttributes
            if written and written.unit then buttons = buttons + 1 end
        end
    end
    return {
        group = rescue.group, layout = config.rescueLayout, kind = rescue.kind, filter = config.rescueFilter,
        hiddenInRaid = config.rescueInRaids == false and service and service.isRaid == true or false,
        slots = rescue.count, more = rescue.hidden, buttons = buttons, secure = rescue.secure,
        clicksSetting = console:RescueClicksOn() and "on" or "off",
        pending = PendingWords(rescue), lastRebuild = rescue.lastRebuild, rebuilds = rescue.rebuilds,
        bindingsClass = rescue.class or "protected", bindings = bindings,
        situation = SituationWord(rescue, service), situationReads = service and service.situationReads or 0,
        range = rescue.reads.range, targetCheck = rescue.reads.targetCheck, dead = rescue.reads.dead,
        cooldown = config.rescueCooldown and rescue.reads.cooldown or "off",
        flash = config.rescueFlash and string.format("on, %d played", rescue.flashes) or "off",
        formSlot = (not rescue.formNeeded and "not used") or rescue.formSlot or "unavailable",
        sound = config.rescueSound and (rescue.soundAt and string.format("on, last %.0fs ago",
            (type(GetTime) == "function" and GetTime() or 0) - rescue.soundAt) or "on") or "off",
        clicks = { member = rescue.clicks.member or 0, header = rescue.clicks.header or 0 },
    }
end

Rescue._Test = { State = State, CollectLive = CollectLive, FillCell = FillCell, ReadModifiers = ReadModifiers }
