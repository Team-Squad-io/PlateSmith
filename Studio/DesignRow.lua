-- Studio's design row under the plate tabs: the design dropdown (World and the plate type's designs,
-- then + Add separate design and the open design's actions), the chip saying what the open design
-- follows, and at the right end Where plates show's eye (Studio/Visibility.lua) and the View menu. The
-- designs are Core/Designs.lua's, edited through Settings' design setters, so Save keeps them and
-- Revert undoes them.
local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Designs = assert(PS.Designs, "PlateSmith Designs missing")
local Schema = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")

local LABEL_FONT, LABEL, GOLD = chrome.FONT, chrome.LABEL, chrome.GOLD
-- How long a design just added says so before its chip settles to what it follows.
local ADDED_SECONDS = 8
local LIGHT_HELP = L["Fewer reads where plates crowd: Light hides buffs and debuffs, and casts under names, on these "
    .. "plates in cities and inns."]
-- A full copy's one action, in the Design menu and on its chip alike.
local FOLLOW_WORLD = L["Follow World where they match..."]
local FOLLOW_WORLD_HELP = L["Keep only what this design changes from World, so later changes to World reach it."]
-- The chip's dot: green follows another design, gold is its own (or just made), grey is Blizzard's.
local DOTS = { green = { 0.42, 0.80, 0.38 }, gold = GOLD, grey = { 0.58, 0.57, 0.55 } }
local CHIP_TEXT, CHIP_HOVER = { 0.86, 0.84, 0.79 }, { 1, 0.86, 0.45 }
local DOT_SIZE, DOT_GAP = 9, 6

local function Settings() return type(PS.GetSettings) == "function" and PS.GetSettings() or nil end

function Options:EditorPlateLabel(plateType)
    for _, definition in ipairs(self.studioModel.editorProfiles) do
        if definition.key == plateType then return definition.label end
    end
    return L["Enemies"]
end

-- A design's name in the row's menu: friendly plates' Dungeons & raids is Blizzard's, unless the
-- overlay test draws over it.
function Options:EditorDesignLabel(plateType, design, settings)
    if Designs.IsBlizzard(plateType, design) then
        settings = settings or Settings()
        if not (settings and settings.experimentalDungeonFriendlyText == true) then return L["Dungeons & raids (Blizzard)"] end
    end
    return Designs.LABELS[design] or L["World"]
end

-- The open design is one the row can reset, remove or copy into (not World, not Blizzard's).
local function Stored(self)
    local design = self.editorDesign
    return design ~= "world" and not Designs.IsBlizzard(self.editorProfile, design)
end

-- Contexts the open plate type can have a design for and has none yet, in order.
function Options:EditorMissingDesigns(settings)
    settings = settings or Settings()
    local missing, stored = {}, Schema.DESIGN.STORED[self.editorProfile] or {}
    for _, design in ipairs(Designs.CONTEXTS) do
        if stored[design] and not (settings and Designs.HasDesign(settings, self.editorProfile, design)) then
            missing[#missing + 1] = design
        end
    end
    return missing
end

-- World, then this plate type's designs; the open one checked.
function Options:EditorDesignChoiceItems()
    local settings, items = Settings(), {}
    for _, entry in ipairs(settings and Designs.List(settings, self.editorProfile) or { { context = "world" } }) do
        local design = entry.context
        items[#items + 1] = { text = self:EditorDesignLabel(self.editorProfile, design, settings),
            checked = design == self.editorDesign, func = function() self:SetEditorDesign(design) end }
    end
    return items
end

-- + Add separate design's submenu: the contexts this plate type has no design for. Cities & inns starts
-- the same as World or Light.
function Options:EditorAddDesignItems()
    local items = {}
    for _, design in ipairs(self:EditorMissingDesigns()) do
        local label = Designs.LABELS[design]
        if design == "city" then
            items[#items + 1] = { text = label, children = {
                { text = L["Same as World"], tooltip = { title = L["Same as World"],
                    text = L["A design that follows World until you change something in it."] },
                    func = function() self:AddEditorDesign(design, "world") end },
                { text = L["Light: no auras or casts on names"], tooltip = { title = L["Light"], text = LIGHT_HELP },
                    func = function() self:AddEditorDesign(design, "light") end },
            }, childWidth = 250 }
        else
            items[#items + 1] = { text = label, func = function() self:AddEditorDesign(design, "world") end }
        end
    end
    return items
end

-- Adds the open plate type's design for design (starter: "world" or "light") and opens it; its chip says
-- it was just added for a few seconds.
function Options:AddEditorDesign(design, starter)
    if not PS.AddDesign(self.editorProfile, design, starter) then return false end
    self:SetEditorDesign(design)
    self.editorDesignAdded = design
    self.editorDesignAddedAt = (self.editorDesignAddedAt or 0) + 1
    local token = self.editorDesignAddedAt
    self:RefreshEditorDesignRow()
    if C_Timer and C_Timer.After then
        C_Timer.After(ADDED_SECONDS, function()
            if self.editorDesignAddedAt == token then self:SettleEditorDesignChip() end
        end)
    end
    return true
end

-- A design just added: its chip settles to what it follows.
function Options:SettleEditorDesignChip()
    self.editorDesignAdded = nil
    self:RefreshEditorDesignRow()
end

-- After a design action: the open design again (World if it went), redrawn from the settings.
local function AfterDesignChange(self, design)
    if not self:SetEditorDesign(design) then self:SetEditorDesign("world") end
end

-- The open design's actions (empty on World and on Blizzard's design).
function Options:EditorDesignActionItems()
    local plateType, design = self.editorProfile, self.editorDesign
    local settings = Settings()
    if not Stored(self) or not settings then return {} end
    local plate, label = self:EditorPlateLabel(plateType), Designs.LABELS[design]
    local items = {}
    items[#items + 1] = { text = L["Reset this design to World..."], func = function()
        self:ConfirmStudioAction(string.format(L["Reset %s › %s to World? Everything changed in this design goes, and it "
            .. "follows World again. Revert undoes it until you save."], plate, label), L["Reset"], function()
            if PS.ResetDesign(plateType, design) then AfterDesignChange(self, design) end
        end)
    end }
    items[#items + 1] = { text = L["Use World again..."], func = function()
        self:ConfirmStudioAction(string.format(L["Stop using a separate design for %s in %s? They use World there "
            .. "again. Revert undoes it until you save."], plate, label), L["Use World"], function()
            if PS.RemoveDesign(plateType, design) then AfterDesignChange(self, "world") end
        end)
    end }
    local sources = {}
    for _, entry in ipairs(Designs.List(settings, plateType)) do
        local source = entry.context
        if source ~= "world" and source ~= design and not entry.blizzard then
            local sourceLabel = Designs.LABELS[source]
            sources[#sources + 1] = { text = sourceLabel, func = function()
                self:ConfirmStudioAction(string.format(L["Start %s › %s again from a copy of %s? What this design "
                    .. "changed goes. Revert undoes it until you save."], plate, label, sourceLabel), L["Copy"], function()
                    if PS.CopyDesign(plateType, source, design) then AfterDesignChange(self, design) end
                end)
            end }
        end
    end
    items[#items + 1] = { text = L["Start from another design..."], children = sources, disabled = #sources == 0,
        tooltip = #sources == 0 and L["This plate type has no other design to copy."] or nil }
    if Designs.IsFull(settings, plateType, design) then
        items[#items + 1] = { text = FOLLOW_WORLD, func = function() self:ConfirmSlimEditorDesign() end,
            tooltip = { title = FOLLOW_WORLD, text = FOLLOW_WORLD_HELP } }
    end
    return items
end

-- The dropdown's menu: the designs, a divider, + Add separate design (the places still missing), then
-- the open design's actions. On World and Blizzard's design the actions show, unavailable, saying why.
function Options:EditorDesignMenuItems()
    local items = self:EditorDesignChoiceItems()
    items[#items + 1] = { separator = true }
    local adds = self:EditorAddDesignItems()
    items[#items + 1] = { text = L["+ Add separate design"], children = adds, childWidth = 210, disabled = #adds == 0,
        tooltip = { title = L["Separate design for..."], text = #adds > 0
            and L["A design of its own for one kind of place. It follows World except what you change in it."]
            or L["This plate type already has a design for every kind of place."] } }
    local actions = self:EditorDesignActionItems()
    if #actions == 0 then
        local why = self.editorDesign == "world"
            and L["World is the design every place starts from. Choose another design to reset, remove or copy it."]
            or L["Blizzard draws this design. It cannot be removed."]
        for _, text in ipairs({ L["Reset this design to World..."], L["Use World again..."], L["Start from another design..."] }) do
            actions[#actions + 1] = { text = text, disabled = true, tooltip = why }
        end
    end
    for _, item in ipairs(actions) do items[#items + 1] = item end
    return items
end

-- Follow World where they match: a full copy keeps only what differs from World (Designs' SlimDesign).
function Options:ConfirmSlimEditorDesign()
    local plateType, design = self.editorProfile, self.editorDesign
    local settings = Settings()
    if not (settings and Designs.IsFull(settings, plateType, design)) then return false end
    self:ConfirmStudioAction(L["Keep only what this design changes from World? It looks the same now. From now on, "
        .. "changes to World reach this design unless you changed that same thing here."], L["Follow World"], function()
        if PS.SlimDesign(plateType, design) then AfterDesignChange(self, design) end
    end)
    return true
end

-- What the open design follows, for its chip: "added", "sparse", "full", "blizzard", "players" (Enemy
-- players, once customised) or nil (World, or Enemy players not customised yet: no chip).
function Options:EditorDesignChipKind(settings)
    if self.editorProfile == "enemyPlayer" then return not self:IsEditorPlayersLocked(settings) and "players" or nil end
    local design = self.editorDesign
    if design == "world" then return nil end
    if Designs.IsBlizzard(self.editorProfile, design) then
        return self:IsEditorBlizzardNames(settings) and "blizzard" or nil
    end
    if settings and Designs.IsFull(settings, self.editorProfile, design) then return "full" end
    return self.editorDesignAdded == design and "added" or "sparse"
end

-- How many things the open design (or the Enemy players layer) changes from what it follows: each
-- option, part and aura row Designs.ChangedAreas names (Marks' state, so read once per revision).
function Options:EditorDesignChangeCount()
    local areas = self.EditorChangedAreas and self:EditorChangedAreas().here
    if not areas then return 0 end
    local count = 0
    for _, map in ipairs({ areas.options, areas.parts, areas.auras }) do
        for _ in pairs(map) do count = count + 1 end
    end
    return count
end

-- A sparse design's word: what it follows, and how much it changes ("Follows World · 3 changes").
local function Follows(self, word)
    local count = self:EditorDesignChangeCount()
    if count == 0 then return word end
    return string.format(count == 1 and L["%s · 1 change"] or L["%s · %d changes"], word, count)
end

-- The chip's word, dot and tooltip sentence for kind.
local function ChipLook(self, kind)
    if kind == "added" then
        return L["Just added"], DOTS.gold, string.format(L["%s in %s now follow World except what you change here."],
            self:EditorPlateLabel(self.editorProfile), Designs.LABELS[self.editorDesign])
    elseif kind == "sparse" then
        return Follows(self, L["Follows World"]), DOTS.green, L["Follows World except what you change here (marked in "
            .. "the parts list and the inspector)."]
    elseif kind == "full" then
        return L["Full copy"], DOTS.gold, L["Made before 1.2.0 (or from an older Blueprint): changes to World don't reach it."]
    elseif kind == "players" then
        return Follows(self, L["Follows Enemies"]), DOTS.green, L["Enemy players follow Enemies (in every place) except "
            .. "what you change here."]
    end
    return L["Blizzard draws these"], DOTS.grey, L["Blizzard draws friendly names in dungeons & raids: you can change their "
        .. "font, size and colours, not their layout."]
end

-- Enemy players are opt-in: until their layer exists (PS.AddDesign("enemyPlayer")) the tab shows only a
-- note and a Customise button on the empty preview, and nothing on it can change (Settings refuses an
-- edit to a layer that does not exist, and the gate hides every control), so no layer is made by accident.
function Options:IsEditorPlayersLocked(settings)
    if self.editorProfile ~= "enemyPlayer" then return false end
    settings = settings or Settings()
    return not (settings and Designs.Record(settings, "enemyPlayer"))
end

function Options:CustomiseEditorPlayers()
    if not PS.AddDesign("enemyPlayer") then return false end
    self:Refresh(true)
    return true
end

-- The layer's two actions (the chip's menu): its changes go, or the layer itself, each asked first.
function Options:ConfirmResetEditorPlayers()
    self:ConfirmStudioAction(L["Reset Enemy players to the Enemies? Everything changed on this tab goes; they "
        .. "stay customisable. Revert undoes it until you save."], L["Reset"], function()
        if PS.ResetDesign("enemyPlayer") then self:Refresh(true) end
    end)
end

function Options:ConfirmStopEditorPlayers()
    self:ConfirmStudioAction(L["Stop customising enemy players? Everything changed on this tab goes, and they use "
        .. "your Enemies plates again. Revert undoes it until you save."], L["Stop customising"], function()
        if PS.RemoveDesign("enemyPlayer") then self:Refresh(true) end
    end)
end

-- What the gate hides while it shows, by Options field: the preview's plate (its stage, with the selection
-- handles), controls and Test values button, the model's note, and the parts list's and inspector's
-- contents. The grid, the design row's eye and View, the scroll bars (withheld), the open Test values panel
-- and the model (PlaceEditorModel) are handled on their own.
local GATED = { "editorPreviewStage", "editorPreviewControls", "editorTestButton", "editorModelNote", "editorListTitle",
    "editorAddButton", "editorSearchField", "editorListScroll", "editorComponentHolder" }
local PLACEHOLDER_INK = PS.UI.Layout.PALETTES.studio.ink.muted

local function Placeholder(panel)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetFont(LABEL_FONT, 14)
    -- Narrow enough to break into two even lines in either panel.
    text:SetPoint("CENTER", panel, "CENTER", 0, 0)
    text:SetWidth(168)
    text:SetJustifyH("CENTER")
    if text.SetWordWrap then text:SetWordWrap(true) end
    text:SetText(L["Customise enemy players to edit their plates."])
    text:Hide()
    return text
end

-- The gate: a clear frame over the preview's picture (under the plate tabs; it takes the pointer and the
-- wheel there) with the note and the button centred on it, and a line in the empty parts list and
-- inspector. Made the first time it shows.
local function BuildPlayersGate(self)
    local canvas, layout = self.editorCanvas, self.editorPreviewLayout
    local gate = CreateFrame("Frame", nil, canvas)
    gate:SetFrameLevel(canvas:GetFrameLevel() + 100)
    gate:EnableMouse(true)
    if gate.EnableMouseWheel then gate:EnableMouseWheel(true) end
    gate:SetScript("OnMouseWheel", function() end)
    gate:SetPoint("TOPLEFT", canvas, "TOPLEFT", layout.pictureInset, -layout.pictureTop)
    gate:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -layout.pictureInset, layout.pictureInset)
    local card = CreateFrame("Frame", nil, gate)
    card:SetSize(420, 168)
    card:SetPoint("CENTER", gate, "CENTER", 0, 0)
    -- No fill of its own: it sits on the preview's plain dark picture, one colour throughout.
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetFont(LABEL_FONT, 17)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    title:SetPoint("TOP", card, "TOP", 0, -20)
    title:SetText(L["Enemy players use your Enemies plates."])
    local note = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetFont(LABEL_FONT, 13)
    note:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
    note:SetPoint("TOP", title, "BOTTOM", 0, -10)
    note:SetWidth(370)
    note:SetJustifyH("CENTER")
    if note.SetWordWrap then note:SetWordWrap(true) end
    note:SetText(L["Customise them to change only enemy players' plates, such as their names or buffs. They follow "
        .. "Enemies in every place, except what you change."])
    local button = chrome.CreateStudioButton(card, L["Customise for enemy players"], 260, 32, "primary")
    button:SetPoint("BOTTOM", card, "BOTTOM", 0, 18)
    button:SetScript("OnClick", function() Options:CustomiseEditorPlayers() end)
    PS.UI.Controls.AttachTooltip(button, L["Customise for enemy players"], { L["Adds an Enemy players layer: what you "
        .. "change on this tab applies to enemy players only. Save keeps it."] })
    gate.card, gate.title, gate.note, gate.button = card, title, note, button
    gate.listNote, gate.inspectorNote = Placeholder(self.editorList), Placeholder(self.editorInspector)
    gate.listNote:SetTextColor(PLACEHOLDER_INK[1], PLACEHOLDER_INK[2], PLACEHOLDER_INK[3])
    -- Each hidden frame's shown state when the gate went up, put back when it goes.
    gate.was = {}
    self.editorPlayersGate = gate
    return gate
end

-- Everything the gate hides (GATED, the grid, the row's eye and View), in a fixed order.
local function GatedFrames(self)
    local frames, row, grid = {}, self.editorDesignRow, self.editorGrid
    for _, field in ipairs(GATED) do
        if self[field] then frames[#frames + 1] = self[field] end
    end
    if grid and grid.frame then frames[#frames + 1] = grid.frame end
    if row and row.view then frames[#frames + 1] = row.view end
    if row and row.eye then frames[#frames + 1] = row.eye end
    return frames
end

-- Up or down with the open tab. While it is up (editorPlayersGated) the tree and the inspector are neither
-- built nor laid out (Editor's RefreshEditorComponentList, RefreshEditorInspectorContext, Inspector's
-- LayoutEditorInspector), and the model stays hidden (PlaceEditorModel); the refresh that takes it down
-- (a tab switch or Customise) builds them again.
function Options:RefreshEditorPlayersGate(settings)
    local locked = self.editorCanvas ~= nil and self:IsEditorPlayersLocked(settings)
    local gate = self.editorPlayersGate
    if not gate and not locked then return end
    gate = gate or BuildPlayersGate(self)
    if locked == (self.editorPlayersGated == true) then return end
    self.editorPlayersGated = locked
    gate:SetShown(locked)
    gate.listNote:SetShown(locked)
    gate.inspectorNote:SetShown(locked)
    if locked and self.inspectorKit then self.inspectorKit.Ink(gate.inspectorNote, "muted") end
    for _, frame in ipairs(GatedFrames(self)) do
        if locked then
            gate.was[frame] = frame:IsShown() and true or false
            frame:Hide()
        else
            frame:SetShown(gate.was[frame] ~= false)
            gate.was[frame] = nil
        end
    end
    for _, field in ipairs({ "editorListScrollBar", "editorComponentScrollBar" }) do
        local bar = self[field]
        if bar then
            bar.withheld = locked
            bar:Sync()
        end
    end
    -- An open Test values panel closes with the gate and opens again after it.
    local panel = self.editorTestPanel
    if locked then
        gate.testPanelOpen = panel ~= nil and panel:IsShown()
        if panel then panel:Hide() end
    elseif gate.testPanelOpen and panel then
        panel:Show()
    end
    if self.PlaceEditorModel then self:PlaceEditorModel() end
    -- The preview's picture goes plain behind the gate, and back to the player's choice after it.
    local stage = self.editorStageArt
    if stage then
        stage.plain = (self.editorPlainStage or locked) and true or false
        if self.LayoutEditorArt then self:LayoutEditorArt() end
    end
end

-- The chip's menu: a full copy can follow World where they match (the Design menu's same action); the
-- Enemy players layer can go back to the Enemies or stop.
function Options:EditorDesignChipItems()
    local kind = self.editorDesignChip and self.editorDesignChip.kind
    if kind == "players" then
        return {
            { text = L["Reset to Enemies..."], func = function() self:ConfirmResetEditorPlayers() end,
                disabled = self:EditorDesignChangeCount() == 0,
                tooltip = { title = L["Reset to Enemies..."], text = L["Every change on this tab goes; enemy players stay "
                    .. "customisable."] } },
            { text = L["Stop customising..."], func = function() self:ConfirmStopEditorPlayers() end,
                tooltip = { title = L["Stop customising..."], text = L["The Enemy players layer goes: enemy players use "
                    .. "your Enemies plates again."] } },
        }
    end
    if kind ~= "full" then return {} end
    return { { text = FOLLOW_WORLD, func = function() self:ConfirmSlimEditorDesign() end,
        tooltip = { title = FOLLOW_WORLD, text = FOLLOW_WORLD_HELP } } }
end

local function PaintChip(self, settings)
    local chip = self.editorDesignChip
    if not chip then return end
    local kind = self:EditorDesignChipKind(settings)
    chip.kind = kind
    chip:SetShown(kind ~= nil)
    if not kind then return end
    local word, dot, sentence = ChipLook(self, kind)
    chip.text:SetText(word)
    chip.dot:SetVertexColor(dot[1], dot[2], dot[3], 1)
    chip:SetWidth(DOT_SIZE + DOT_GAP + math.ceil(chip.text:GetStringWidth()) + 4)
    chip.tip[1] = sentence
    chip.tip[2] = kind == "full" and { L["Click: follow World where they match."], 0.86, 0.86, 0.86 }
        or kind == "players" and { L["Click: reset to Enemies, or stop customising."], 0.86, 0.86, 0.86 } or nil
    -- The open design's name heads the tooltip.
    chip.tipTitle[1] = kind == "players" and self:EditorPlateLabel("enemyPlayer")
        or string.format(L["%s › %s"], self:EditorPlateLabel(self.editorProfile), Designs.LABELS[self.editorDesign] or "")
end

-- The row, its chip and the eye, from the settings. Enemy players have no designs of their own (their
-- one layer sits on the Enemies'), so the dropdown gives way to the chip there.
function Options:RefreshEditorDesignRow(settings)
    local row = self.editorDesignRow
    if not row then return end
    settings = settings or Settings()
    local players = self.editorProfile == "enemyPlayer"
    row.label:SetShown(not players)
    row.dropdown:SetShown(not players)
    -- The field names the place only; its menu and the chip say Blizzard draws it.
    row.dropdown:SetText(Designs.LABELS[self.editorDesign] or L["World"])
    PaintChip(self, settings)
    row.chip:ClearAllPoints()
    if players then row.chip:SetPoint("LEFT", row, "LEFT", 0, 0)
    else row.chip:SetPoint("LEFT", row.dropdown, "RIGHT", 14, 0) end
    if self.RefreshPlateVisibilityEye then self:RefreshPlateVisibilityEye(settings) end
    self:RefreshEditorPlayersGate(settings)
end

-- View: how the preview looks, never what the plates do: Plain dark background, a model behind the
-- plate (PreviewModel.lua) and the sample name's alphabet.
function Options:EditorViewMenuItems()
    local models = {}
    local choice = self:EditorModelChoice()
    for _, entry in ipairs(self.editorModelChoices) do
        local value = entry.value
        models[#models + 1] = { text = entry.label, checked = value == choice, func = function() self:SetEditorModel(value) end }
    end
    local names = {}
    local script = self:EditorSampleScript().value
    for _, entry in ipairs(self.editorSampleScripts) do
        local value = entry.value
        names[#names + 1] = { text = entry.label, checked = value == script, func = function()
            self.editorSampleScript = value
            self:RefreshEditorAppearance(PS.GetSettings())
        end }
    end
    return {
        { text = L["Plain dark background"], checked = self.editorPlainStage == true,
            func = function() self:SetEditorPlainStage(not self.editorPlainStage) end,
            tooltip = { title = L["Plain dark background"], text = L["A plain dark stage behind the preview instead of the "
                .. "world picture."] } },
        { text = L["Model"], children = models, childWidth = 150,
            tooltip = { title = L["Model"], text = L["A 3D model behind the preview plate, to judge it over a body."] } },
        { text = L["Sample name"], children = names, childWidth = 150,
            tooltip = { title = L["Sample name"], text = L["The sample's name in another alphabet, to check the plates' "
                .. "font draws it."] } },
    }
end

-- A chip with a menu: a full copy's, and the Enemy players layer's.
local function Clickable(kind) return kind == "full" or kind == "players" end

-- Built with the preview (Frame.lua), under the plate tabs; Chrome's LayoutEditorPreviewPanel places it.
function Options:BuildEditorDesignRow(canvas)
    local row = CreateFrame("Frame", nil, canvas)
    row:SetSize(560, 30)
    row:SetFrameLevel(canvas:GetFrameLevel() + 6)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetFont(LABEL_FONT, 15)
    label:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
    label:SetText(L["Design:"])
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label = label
    local dropdown = PS.UI.Controls.MenuField(row, { name = "PlateSmithEditorDesignDropdown", width = 214, height = 30,
        minMenuWidth = 240, items = function() return Options:EditorDesignMenuItems() end })
    chrome.SkinDropdown(dropdown)
    dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
    PS.UI.Controls.AttachTooltip(dropdown, L["Design"], { L["Choose which design you are editing, add a separate design "
        .. "for a kind of place, or reset, remove or copy the open one."] })
    row.dropdown = dropdown

    -- The chip: a dot and a word for what the open design follows; the tooltip says it whole.
    local chip = CreateFrame("Button", nil, row)
    chip:SetHeight(24)
    local dot = chip:CreateTexture(nil, "ARTWORK")
    dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    dot:SetSize(DOT_SIZE, DOT_SIZE)
    dot:SetPoint("LEFT", chip, "LEFT", 0, 0)
    chip.dot = dot
    local word = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    word:SetFont(LABEL_FONT, 14)
    word:SetTextColor(CHIP_TEXT[1], CHIP_TEXT[2], CHIP_TEXT[3])
    word:SetPoint("LEFT", dot, "RIGHT", DOT_GAP, 0)
    if word.SetWordWrap then word:SetWordWrap(false) end
    chip.text = word
    chip.tip, chip.tipTitle = { "" }, { "" }
    PS.UI.Controls.AttachTooltip(chip, function() return chip.tipTitle[1] end, chip.tip)
    chip:HookScript("OnEnter", function(instance)
        if Clickable(instance.kind) then word:SetTextColor(CHIP_HOVER[1], CHIP_HOVER[2], CHIP_HOVER[3]) end
    end)
    chip:HookScript("OnLeave", function() word:SetTextColor(CHIP_TEXT[1], CHIP_TEXT[2], CHIP_TEXT[3]) end)
    chip:SetScript("OnClick", function(instance)
        if not Clickable(instance.kind) then return end
        PS.UI.Menu.Toggle(instance, function() return Options:EditorDesignChipItems() end, { width = 240 })
    end)
    chip:Hide()
    row.chip = chip
    self.editorDesignChip = chip

    -- The right end: View, and Where plates show's eye before it.
    local view = PS.UI.Controls.MenuField(row, { name = "PlateSmithEditorViewMenu", width = 92, height = 30,
        minMenuWidth = 220, items = function() return Options:EditorViewMenuItems() end })
    chrome.SkinDropdown(view)
    view:SetText(L["View"])
    view:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    PS.UI.Controls.AttachTooltip(view, L["View"], { L["How the preview looks: a plain background, a model behind the "
        .. "plate, the sample name's alphabet. Your plates do not change."] })
    row.view = view
    self.editorViewMenu = view
    self.editorDesignRow = row
    if self.BuildPlateVisibilityEye then row.eye = self:BuildPlateVisibilityEye(row, view) end
    return row
end
