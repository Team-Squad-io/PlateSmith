local _, PS = ...
local L = PS.L
local Options = PS.Options

-- The first-run setup: on a fresh install (Profiles.Load found no profiles and set state.firstRunDone
-- to false), Studio's first open shows it over Studio in two steps. Step 1 asks how this character plays
-- (four role cards; a card sets This character tanks and Colour by threat at once, Skip changes nothing),
-- step 2 offers the look presets (the role's suggestion chosen, Start with it confirms, Back returns,
-- Skip keeps the default). Finishing either way, or Escape at any step, sets firstRunDone to true, so it
-- never shows again. Existing installs never have firstRunDone false, so for them nothing here is built.
-- Role cards: a row of four. Look cards: three rows of three, each its sketch over its name and description.
-- A look card is tall enough for its sketch, name and two lines of description with room under them.
local PANEL = { width = 1060, height = 720, cardWidth = 236, gap = 16, top = 144, roleHeight = 372,
    lookWidth = 316, lookHeight = 150, lookGap = 8, lookColumns = 3 }
-- The card's plate sketch: the preset's Enemies sizes at this scale, in a box this tall and inset.
local SKETCH = { scale = 1.2, height = 68, inset = 8, health = 0.72, cast = 0.6 }
-- A role card's threat colour sample: a bar per state, straight on the card.
local SAMPLE = { top = 108, height = 120, row = 26, bar = 64, barHeight = 13 }
-- The look step 2 starts on when the role suggests none (PlateSmith's own defaults).
local DEFAULT_LOOK = "platesmith"
local STEPS = 2
local SETS_ON = L["Colour by threat: On"]
-- Each sets This character tanks (and Colour by threat on); look is the look it suggests for step 2.
-- samples: the threat colours the card shows, as { state, label }.
local ROLES = {
    { id = "tank", label = L["Tank"], tankRole = "always", look = "tank",
        lede = L["You hold enemies on you."],
        sets = { L["This character tanks: Always"], SETS_ON, L["Suggests the Tank look"] },
        samples = { { "holding", L["Holding aggro"] }, { "losing", L["Losing it"] } },
        help = L["Tank threat colours: blue while you hold an enemy's aggro, yellow while you are losing it."] },
    { id = "healer", label = L["Healer"], tankRole = "never", look = "healer",
        lede = L["You keep your group alive."],
        sets = { L["This character tanks: Never"], SETS_ON, L["Suggests the Healer look"] },
        samples = { { "pulling", L["Pulling threat"] }, { "aggro", L["You have aggro"] } },
        help = L["Threat colours warn you as you pull threat and once an enemy is on you. The Healer look has "
            .. "thick friendly bars with health %."] },
    { id = "dps", label = L["DPS"], tankRole = "never",
        lede = L["You deal the damage."],
        sets = { L["This character tanks: Never"], SETS_ON, L["Suggests no look"] },
        samples = { { "pulling", L["Pulling threat"] }, { "aggro", L["You have aggro"] } },
        help = L["Threat colours warn you as you pull threat and once an enemy is on you."] },
    { id = "hybrid", label = L["Hybrid"], tankRole = "adaptive",
        lede = L["You swap roles by stance, form or spec."],
        sets = { L["This character tanks: Adaptive"], SETS_ON, L["Suggests no look"] },
        samples = { { "holding", L["Tanking: holding"] }, { "losing", L["Tanking: losing it"] },
            { "pulling", L["Otherwise: pulling"] }, { "aggro", L["Otherwise: aggro"] } },
        help = L["For druids, warriors and paladins who swap roles: tank colours while in a tank form, stance or "
            .. "spec, DPS colours otherwise."] },
}
local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }

function Options:FirstRunPending()
    local state = PS.GetState and PS.GetState()
    return type(state) == "table" and state.firstRunDone == false
end

local function Text(parent, size, colour, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
    text:SetFont(Options.studioChrome.FONT, size)
    text:SetTextColor(colour[1], colour[2], colour[3])
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    return text
end

local function Solid(parent, layer, sublevel, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer, nil, sublevel)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function RoleOf(id)
    for _, role in ipairs(ROLES) do if role.id == id then return role end end
end

-- The look a role suggests (none: PlateSmith's own).
local function SuggestedLook(id)
    local role = RoleOf(id)
    return role and role.look or DEFAULT_LOOK
end

-- A visible text custom part on the health bar (Sleek's health %, Tank's boxed lead), or nil.
local function BarValue(profile)
    for index = 1, 8 do
        local key = "value" .. index
        local position, slot = profile.layout[key], profile.valueSlots and profile.valueSlots[key]
        if position and slot and position.visible ~= false and not position.removed and slot.anchor == "health"
            and (slot.source == "healthPercent" or slot.source == "leadPercent" or slot.source == "template") then
            return key, position
        end
    end
end

-- A sketch of the preset's enemy plate, drawn from its built settings: bar sizes, texture, border
-- and background, the name's font, size, outline and place, the level, a value on the bar and the
-- cast bar. Not Studio's preview: that is one live plate, and nine of them would cost Studio's first
-- open hundreds of frames.
local function DrawSketch(box, settings)
    local S, Media = PS.ProfileSchema, PS.Media
    local profile = settings.plateProfiles.enemy
    local styles = profile.styles or {}
    local health, nameStyle = styles.health or {}, styles.name or {}
    local k = SKETCH.scale
    local width, height = math.floor(profile.width * k + 0.5), math.max(4, math.floor(profile.healthHeight * k + 0.5))
    local castHeight = math.max(4, math.floor((profile.castHeight or math.max(5, profile.healthHeight - 3)) * k + 0.5))

    local bar = CreateFrame("Frame", nil, box)
    bar:SetSize(width, height)
    bar:SetPoint("CENTER", box, "CENTER", 0, 4)
    local border = health.border and health.border > 0 and math.max(1, math.floor(health.border * k + 0.5)) or 0
    local edge = health.borderColour or { r = 0, g = 0, b = 0, a = 1 }
    local back = health.background or { r = 0.05, g = 0.05, b = 0.05, a = 0.75 }
    local frameEdge = Solid(bar, "BACKGROUND", 0, edge.r, edge.g, edge.b, edge.a or 1)
    frameEdge:SetPoint("TOPLEFT", bar, "TOPLEFT", -border, border)
    frameEdge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", border, -border)
    frameEdge:SetShown(border > 0)
    local fillBack = Solid(bar, "BACKGROUND", 1, back.r, back.g, back.b, back.a or 1)
    fillBack:SetAllPoints(bar)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    Media.SetStatusBar(fill, health.texture or profile.healthTexture)
    local colour = profile.healthColour
    fill:SetVertexColor(colour.r, colour.g, colour.b)
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(math.floor(width * SKETCH.health + 0.5))

    local castStyle = styles.cast or {}
    local cast = bar:CreateTexture(nil, "ARTWORK")
    Media.SetStatusBar(cast, castStyle.texture or profile.healthTexture)
    local castColour = S.CAST_COLOUR
    cast:SetVertexColor(castColour.r, castColour.g, castColour.b)
    cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -math.max(3, border + 2))
    cast:SetSize(math.floor(width * SKETCH.cast + 0.5), castHeight)
    local castBack = Solid(bar, "BACKGROUND", 1, back.r, back.g, back.b, back.a or 1)
    castBack:SetPoint("TOPLEFT", cast, "TOPLEFT", 0, 0)
    castBack:SetSize(width, castHeight)

    local name = bar:CreateFontString(nil, "OVERLAY")
    local size = math.max(9, math.floor(profile.nameFontSize * k * 0.82 + 0.5))
    local flags = OUTLINES[nameStyle.outline or "outline"] or "OUTLINE"
    name:SetFont(Media.FontPath(nameStyle.font) or Options.studioChrome.FONT, size, flags)
    name:SetText(L["Defias Pillager"])
    name:SetTextColor(1, 0.92, 0.88)
    if nameStyle.shadow then
        name:SetShadowColor(0, 0, 0, 1)
        name:SetShadowOffset(1, -1)
    end
    local layout = profile.layout
    local namePlace, levelPlace = layout.name or {}, layout.level or {}
    local level = bar:CreateFontString(nil, "OVERLAY")
    level:SetFont(Options.studioChrome.FONT, math.max(9, size - 2), flags)
    level:SetText("60")
    level:SetTextColor(1, 0.82, 0)
    local levelShown = levelPlace.visible ~= false and not levelPlace.removed
    if namePlace.parent == "health" and namePlace.free then
        name:SetPoint("CENTER", bar, "CENTER", 0, 0)
    elseif namePlace.parent == "health" and namePlace.attach == "right" and (namePlace.x or 0) < 0 then
        -- Pinned inside the bar from its left end (Blizzard's).
        name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    elseif namePlace.parent == "level" and levelShown then
        level:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 2, 3)
        name:SetPoint("LEFT", level, "RIGHT", 3, 0)
    else
        name:SetPoint("BOTTOM", bar, "TOP", 0, 3 + math.floor((namePlace.y or 19) / 8))
    end
    level:SetShown(levelShown)
    if levelShown and levelPlace.parent == "health" and levelPlace.attach == "right" then
        level:SetPoint("LEFT", bar, "RIGHT", math.max(3, (levelPlace.x or 0) * k) + border, 0)
    elseif levelShown and namePlace.parent ~= "level" then
        level:SetPoint("RIGHT", name, "LEFT", -3, 0)
    end

    local valueKey, valuePlace = BarValue(profile)
    local value = bar:CreateFontString(nil, "OVERLAY")
    value:SetFont(Options.studioChrome.FONT, math.max(9, math.floor(size * 0.8)), "OUTLINE")
    value:SetText("72%")
    value:SetShown(valueKey ~= nil)
    if valuePlace and valuePlace.attach == "right" then
        value:SetPoint("LEFT", bar, "RIGHT", 4 + border, 0)
        value:SetTextColor(1, 0.85, 0.3)
    else
        value:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    end
    -- A rounded level box: Blizzard's art behind the level (Blizzard's look).
    local levelStyle = styles.level or {}
    local levelBox
    if levelShown and levelStyle.box and levelStyle.boxShape == "rounded" then
        levelBox = CreateFrame("Frame", nil, bar)
        levelBox:SetPoint("TOPLEFT", level, "TOPLEFT", -3, 3)
        levelBox:SetPoint("BOTTOMRIGHT", level, "BOTTOMRIGHT", 3, -3)
        PS.StyleBox.Rounded(levelBox, true)
        -- The digits on the box's own frame, so the art (its background) stays under them.
        level:SetParent(levelBox)
    end
    box.sketch = { bar = bar, fill = fill, cast = cast, name = name, level = level, value = value, border = border,
        levelBox = levelBox }
    return box.sketch
end

-- Lit while pointed at or chosen; the chosen card also has a gold edge.
local function SetCardLit(card, lit)
    local chosen = card.chosen == true
    lit = lit or chosen
    card.lit:SetShown(lit)
    card.edge:SetShown(chosen)
    card.title:SetTextColor(lit and 1 or 0.89, lit and 0.9 or 0.75, lit and 0.6 or 0.13)
end

-- A card's frame on one step's page: the backing, the hover light and the chosen card's gold edge, in
-- rows of columns from top, centred.
local function CardFrame(page, index, width, height, columns, gap)
    local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
    local card = CreateFrame("Button", nil, page)
    card:SetSize(width, height)
    local left = (PANEL.width - columns * width - (columns - 1) * gap) / 2
    card:SetPoint("TOPLEFT", page, "TOPLEFT", left + column * (width + gap), -PANEL.top - row * (height + gap))
    local gold = Options.studioChrome.GOLD
    card.edge = Solid(card, "BACKGROUND", -1, gold[1], gold[2], gold[3], 1)
    card.edge:SetPoint("TOPLEFT", card, "TOPLEFT", -2, 2)
    card.edge:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 2, -2)
    local back = Solid(card, "BACKGROUND", 0, 0.09, 0.085, 0.08, 0.95)
    back:SetAllPoints(card)
    card.lit = Solid(card, "BACKGROUND", 1, 0.89, 0.75, 0.13, 0.16)
    card.lit:SetAllPoints(card)
    card:SetScript("OnEnter", function(instance) SetCardLit(instance, true) end)
    card:SetScript("OnLeave", function(instance) SetCardLit(instance, false) end)
    return card
end

local function CreateLookCard(page, preset, index)
    local card = CardFrame(page, index, PANEL.lookWidth, PANEL.lookHeight, PANEL.lookColumns, PANEL.lookGap)
    local box = CreateFrame("Frame", nil, card)
    box:SetPoint("TOPLEFT", card, "TOPLEFT", SKETCH.inset, -SKETCH.inset)
    box:SetPoint("TOPRIGHT", card, "TOPRIGHT", -SKETCH.inset, -SKETCH.inset)
    box:SetHeight(SKETCH.height)
    Options.studioChrome.CreateStageBackdrop(box):Layout(PANEL.lookWidth - 2 * SKETCH.inset, SKETCH.height)
    card.box = box
    card.title = Text(card, 16, Options.studioChrome.GOLD)
    card.title:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
    card.title:SetText(preset.name)
    card.description = Text(card, 12, { 0.8, 0.78, 0.74 })
    card.description:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.description:SetWidth(PANEL.lookWidth - 20)
    card.description:SetJustifyH("LEFT")
    if card.description.SetJustifyV then card.description:SetJustifyV("TOP") end
    if card.description.SetMaxLines then card.description:SetMaxLines(2) end
    card.description:SetText(preset.description)
    card.presetId = preset.id
    local settings = PS.ProfilePresets.Build(preset.id)
    if settings then DrawSketch(box, settings) end
    -- A click chooses the look; Start with it confirms.
    card:SetScript("OnClick", function(instance) Options:SelectFirstRunPreset(instance.presetId, true) end)
    SetCardLit(card, false)
    return card
end

-- The role's threat colours as they will show: a short bar per state in the profile's colour, straight
-- on the card (no box of its own), each with a dark edge.
local function DrawSamples(card, role)
    local box = CreateFrame("Frame", nil, card)
    box:SetPoint("TOPLEFT", card, "TOPLEFT", 3, -SAMPLE.top)
    box:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -SAMPLE.top)
    box:SetHeight(SAMPLE.height)
    card.sampleBox = box
    local colours = PS.GetSettings().threatColours or {}
    local defaults = PS.ProfileSchema.THREAT_COLOURS.defaults
    local first = (SAMPLE.height - #role.samples * SAMPLE.row) / 2 + (SAMPLE.row - SAMPLE.barHeight) / 2
    card.samples = {}
    for index, sample in ipairs(role.samples) do
        local state, label = sample[1], sample[2]
        local colour = colours[state] or defaults[state]
        local y = -math.floor(first + (index - 1) * SAMPLE.row + 0.5)
        local edge = Solid(box, "BORDER", 0, 0, 0, 0, 1)
        edge:SetPoint("TOPLEFT", box, "TOPLEFT", 13, y + 1)
        edge:SetSize(SAMPLE.bar + 2, SAMPLE.barHeight + 2)
        local bar = Solid(box, "ARTWORK", 0, colour.r, colour.g, colour.b, 1)
        bar:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
        bar:SetSize(SAMPLE.bar, SAMPLE.barHeight)
        local text = Text(box, 13, { 0.88, 0.86, 0.82 })
        text:SetPoint("LEFT", edge, "RIGHT", 10, 0)
        text:SetText(label)
        card.samples[index] = { state = state, bar = bar, label = text }
    end
end

local function CreateRoleCard(page, role, index)
    local card = CardFrame(page, index, PANEL.cardWidth, PANEL.roleHeight, 4, PANEL.gap)
    local light = { 0.88, 0.86, 0.82 }
    card.title = Text(card, 24, Options.studioChrome.GOLD)
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -18)
    card.title:SetText(role.label)
    card.lede = Text(card, 14, light)
    card.lede:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -10)
    card.lede:SetWidth(PANEL.cardWidth - 32)
    card.lede:SetJustifyH("LEFT")
    if card.lede.SetJustifyV then card.lede:SetJustifyV("TOP") end
    card.lede:SetText(role.lede)
    DrawSamples(card, role)
    local heading = Text(card, 12, { 0.62, 0.60, 0.56 })
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -(SAMPLE.top + SAMPLE.height + 18))
    heading:SetText(L["Sets"])
    card.sets = {}
    local previous = heading
    for line, text in ipairs(role.sets) do
        local set = Text(card, 14, light)
        set:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, line == 1 and -8 or -7)
        set:SetWidth(PANEL.cardWidth - 32)
        set:SetJustifyH("LEFT")
        set:SetText(text)
        card.sets[line] = set
        previous = set
    end
    card.roleId = role.id
    card:SetScript("OnClick", function(instance) Options:PickFirstRunRole(instance.roleId) end)
    PS.UI.Controls.AttachTooltip(card, role.label, { role.help,
        L["It also turns Colour by threat on, so enemy plates show your threat."] })
    SetCardLit(card, false)
    return card
end

-- Everything that follows the step, the role and the chosen look: the shown page, the step's words, the
-- chosen cards, Back, Skip's place and help, and the Start button.
local function UpdatePicker(picker)
    local step = picker.step
    picker.rolePage:SetShown(step == 1)
    picker.lookPage:SetShown(step == 2)
    picker.stepLabel:SetText(string.format(L["Step %d of %d"], step, STEPS))
    if step == 1 then
        picker.heading:SetText(L["How do you play this character?"])
        picker.intro:SetText(L["This decides when PlateSmith treats you as a tank, for threat colours, rules and "
            .. "the threat windows. It is saved for this character at once."])
    else
        picker.heading:SetText(L["Pick a look"])
        picker.intro:SetText(L["Start makes the chosen look a new profile, named after it, that you can change here. "
            .. "Profile › New from preset has them all."])
    end
    for _, card in ipairs(picker.roleCards) do
        card.chosen = card.roleId == picker.role
        SetCardLit(card, false)
    end
    for _, card in ipairs(picker.cards) do
        card.chosen = card.presetId == picker.selected
        SetCardLit(card, false)
    end
    local role = RoleOf(picker.role)
    picker.roleNote:SetText(role and string.format(L["This character: %s"], role.label) or "")
    picker.back:SetShown(step == 2)
    picker.roleNote:SetShown(step == 2)
    picker.start:SetShown(step == 2)
    picker.skip:ClearAllPoints()
    if step == 2 then
        picker.skip:SetPoint("RIGHT", picker.start, "LEFT", -12, 0)
    else
        picker.skip:SetPoint("BOTTOMRIGHT", picker.panel, "BOTTOMRIGHT", -40, 24)
    end
    picker.skipHelp[1] = step == 1
        and L["Leaves this character's role and threat colours as they are, and goes on to the looks."]
        or L["Keeps PlateSmith's default look (a role you chose stays). This does not show again."]
    local preset = picker.selected and PS.ProfilePresets.Get(picker.selected)
    picker.start.label:SetText(preset and string.format(L["Start with %s"], preset.name) or L["Start with this look"])
    PS.SaveBar.SetAvailable(picker.start, preset ~= nil)
end

local function BuildPicker(options)
    local chrome = options.studioChrome
    local editor = options.editor
    -- Over all of Studio (its panels share the DIALOG strata), under its dialogs and menus.
    local picker = CreateFrame("Frame", "PlateSmithFirstRunPicker", editor)
    picker:SetAllPoints(editor)
    picker:SetFrameStrata("FULLSCREEN")
    picker:EnableMouse(true)
    local veil = Solid(picker, "BACKGROUND", 0, 0, 0, 0, 0.72)
    veil:SetAllPoints(picker)

    local panel = CreateFrame("Frame", nil, picker)
    panel:SetSize(PANEL.width, PANEL.height)
    panel:SetPoint("CENTER", picker, "CENTER", 0, -34) -- clear of the header's logo
    panel:EnableMouse(true)
    picker.panel = panel
    panel.art = chrome.CreatePanelArt(panel, "dark")
    panel:SetScript("OnSizeChanged", function() panel.art:Layout() end)
    panel.art:Layout()

    local title = Text(panel, 24, chrome.GOLD)
    title:SetPoint("TOP", panel, "TOP", 0, -26)
    title:SetText(L["Welcome to PlateSmith"])
    picker.stepLabel = Text(panel, 13, { 0.72, 0.70, 0.66 })
    picker.stepLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -40, -34)
    picker.heading = Text(panel, 19, { 0.96, 0.93, 0.86 })
    picker.heading:SetPoint("TOP", title, "BOTTOM", 0, -14)
    local intro = Text(panel, 13, { 0.80, 0.78, 0.74 })
    intro:SetPoint("TOP", picker.heading, "BOTTOM", 0, -8)
    intro:SetWidth(PANEL.width - 160)
    intro:SetJustifyH("CENTER")
    picker.title, picker.intro = title, intro

    -- Step 1: the role cards, and where to change the role later.
    picker.rolePage = CreateFrame("Frame", nil, panel)
    picker.rolePage:SetAllPoints(panel)
    picker.roleCards = {}
    for index, role in ipairs(ROLES) do picker.roleCards[index] = CreateRoleCard(picker.rolePage, role, index) end
    local later = Text(picker.rolePage, 12, { 0.62, 0.60, 0.56 })
    later:SetPoint("TOP", picker.rolePage, "TOP", 0, -(PANEL.top + PANEL.roleHeight + 22))
    later:SetText(L["Change both later in Settings › Behaviour & display › Threat colours."])
    picker.roleLater = later

    -- Step 2: the look cards.
    picker.lookPage = CreateFrame("Frame", nil, panel)
    picker.lookPage:SetAllPoints(panel)
    picker.cards = {}
    for index, preset in ipairs(PS.ProfilePresets.LIST) do
        picker.cards[index] = CreateLookCard(picker.lookPage, preset, index)
    end

    picker.start = chrome.CreateStudioButton(panel, L["Start with this look"], 230, 32, "primary")
    picker.start:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 24)
    picker.start:SetScript("OnClick", function() Options:StartFirstRun() end)
    PS.UI.Controls.AttachTooltip(picker.start, L["Start with this look"], {
        L["Makes the chosen look your profile. Choose a look above first."] })
    picker.skip = chrome.CreateStudioButton(panel, L["Skip"], 130, 32)
    picker.skip:SetScript("OnClick", function() Options:SkipFirstRunStep() end)
    picker.skipHelp = { "" }
    PS.UI.Controls.AttachTooltip(picker.skip, L["Skip"], picker.skipHelp)
    picker.back = chrome.CreateStudioButton(panel, L["Back"], 130, 32)
    picker.back:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 40, 24)
    picker.back:SetScript("OnClick", function() Options:FirstRunBack() end)
    PS.UI.Controls.AttachTooltip(picker.back, L["Back"], { L["Back to the role; the one you chose stays."] })
    picker.roleNote = Text(panel, 13, { 0.72, 0.70, 0.66 })
    picker.roleNote:SetPoint("LEFT", picker.back, "RIGHT", 16, 0)
    picker.message = Text(panel, 13, { 1, 0.45, 0.4 })
    picker.message:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 50, 66)
    picker.message:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 66)
    picker.message:SetJustifyH("LEFT")
    picker.hint = Text(panel, 12, { 0.62, 0.60, 0.56 })
    picker.hint:SetPoint("RIGHT", picker.skip, "LEFT", -16, 0)
    picker.hint:SetText(L["Escape skips setup."])

    -- Escape skips it all and nothing else: outside combat the key is kept from the rest of the UI (Studio
    -- stays open); every other key passes on. In combat the key cannot be kept: Escape closes Studio
    -- with it, and OnHide counts that as Skip.
    picker:SetScript("OnKeyDown", function(owner, key)
        local keep = key == "ESCAPE"
        if owner.SetPropagateKeyboardInput then pcall(owner.SetPropagateKeyboardInput, owner, not keep) end
        if keep then Options:FinishFirstRun("escape") end
    end)
    picker:SetScript("OnHide", function(owner)
        if owner.EnableKeyboard then pcall(owner.EnableKeyboard, owner, false) end
        if not owner.finished then Options:FinishFirstRun("closed") end
    end)
    picker:Hide()
    options.editorFirstRun = picker
    picker.step = 1
    UpdatePicker(picker)
    return picker
end

-- Shows the setup over Studio when a fresh install's choice is still to make. Built here, on the
-- open that shows it; a failure is reported and counts as Skip, so Studio itself still opens.
function Options:ShowFirstRunIfPending()
    if not self:FirstRunPending() or not (self.editor and self.editor:IsShown()) then return false end
    local ok, picker = pcall(function() return self.editorFirstRun or BuildPicker(self) end)
    if not ok then
        PS.Chat.ReportError("studio first run", picker)
        PS.GetState().firstRunDone = true
        return false
    end
    picker.finished, picker.role, picker.selected, picker.chosenByHand = nil, nil, nil, nil
    picker.step = 1
    picker.message:SetText("")
    UpdatePicker(picker)
    picker:Show()
    if picker.EnableKeyboard and not PS.Secret.InCombat() then pcall(picker.EnableKeyboard, picker, true) end
    return true
end

-- Step 1 or 2. Step 2 starts on the role's suggested look unless a card was clicked already.
function Options:ShowFirstRunStep(step)
    local picker = self.editorFirstRun
    if not (picker and (step == 1 or step == 2)) then return false end
    picker.step = step
    if step == 2 and not picker.chosenByHand then picker.selected = SuggestedLook(picker.role) end
    picker.message:SetText("")
    UpdatePicker(picker)
    return true
end

-- Skip: on step 1 on to the looks with nothing changed; on step 2 the end, keeping the default profile.
function Options:SkipFirstRunStep()
    local picker = self.editorFirstRun
    if picker and picker.step == 1 then return self:ShowFirstRunStep(2) end
    self:FinishFirstRun("skip")
    return true
end

-- Back to step 1; the chosen role stays (applied, and its card marked).
function Options:FirstRunBack()
    return self:ShowFirstRunStep(1)
end

-- how: "preset", "skip", "escape" or "closed" (Studio closed under it).
function Options:FinishFirstRun(how)
    local state = PS.GetState()
    if state then state.firstRunDone = true end
    self.firstRunChoice = how
    local picker = self.editorFirstRun
    if picker then
        picker.finished = true
        if picker:IsShown() then picker:Hide() end
    end
end

-- Colour by threat on for the active profile; saved at once when nothing else was unsaved.
local function ThreatColoursOn(wasClean)
    if PS.GetSettings().colourByThreat == true then return end
    PS.SetOption("colourByThreat", true)
    if wasClean then PS.Profiles.Save() end
end

-- A role card: This character tanks (always for Tank, never for Healer and DPS, adaptive for Hybrid) and
-- Colour by threat on, saved at once, so they stay however the setup ends. Then on to step 2.
function Options:PickFirstRunRole(id)
    local role = RoleOf(id)
    if not role then return false end
    local wasClean = not PS.Profiles.IsDirty()
    if not PS.SetCharacterOption("tankRole", role.tankRole) then return false end
    ThreatColoursOn(wasClean)
    local picker = self.editorFirstRun
    if picker then
        picker.role = id
        self:ShowFirstRunStep(2)
    end
    self:Refresh(true)
    return true
end

-- A card click chooses its look (byHand: the player's own pick, which a role no longer changes).
function Options:SelectFirstRunPreset(id, byHand)
    local picker = self.editorFirstRun
    if not (picker and PS.ProfilePresets.Get(id)) then return false end
    picker.selected = id
    if byHand then picker.chosenByHand = true end
    picker.message:SetText("")
    UpdatePicker(picker)
    return true
end

-- Start with this look: the chosen card's preset becomes the profile.
function Options:StartFirstRun()
    local picker = self.editorFirstRun
    if not (picker and picker.step == 2 and picker.selected) then return false end
    return self:PickFirstRunPreset(picker.selected)
end

-- A look preset becomes the profile, as Profile › New from preset does.
function Options:PickFirstRunPreset(id)
    local ok, reason = PS.Profiles.CreateFromPreset(id)
    local picker = self.editorFirstRun
    if not ok then
        if picker then picker.message:SetText(string.format(L["Profile change failed: %s"], L[reason or "unknown error"])) end
        return false, reason
    end
    if picker and picker.role then ThreatColoursOn(true) end
    self:FinishFirstRun("preset")
    self:Refresh(true)
    return true, reason -- reason: the new profile's name
end
