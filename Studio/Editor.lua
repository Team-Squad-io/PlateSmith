local _, PS = ...
local L = PS.L

local Options = assert(PS.Options, "PlateSmith EditorComponents missing")
local catalog = assert(Options.editorCatalog)
local Schema = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local editorDefaults = catalog.editorDefaults
local editorOrder = catalog.editorOrder
local editorLabels = catalog.editorLabels
local editorDefinitions = catalog.editorDefinitions
local VALUE_SLOT_COUNT = catalog.VALUE_SLOT_COUNT
local editorProfiles = {
    { key = "enemy", label = L["Enemies"], sampleName = L["Training Raider"] },
    { key = "friendlyPlayer", label = L["Players"], sampleName = L["Your Character"] },
    { key = "friendlyNPC", label = L["Friendly NPCs"], sampleName = L["Innkeeper Allison"] },
}
-- The inspector's controls for each part (Inspector's contexts); parts with none of their own
-- (shown, hidden and moved from the tree and the preview) use "other".
local editorContextForKey = {
    name = "name", level = "level", guild = "guild", targetName = "targetName",
    health = "health", power = "power", cast = "cast", questLoot = "questLoot",
    raidIcon = "raidIcon", relationshipIcon = "relationshipIcon", pvpIcon = "pvpIcon", classification = "classification",
    buffs = "buffs", debuffs = "debuffs",
}
-- Parts whose plates also follow a profile-wide switch. The tree's eye drives it: showing the
-- part turns its switch on, so nothing Studio no longer offers can keep a shown part off.
local PART_SWITCHES = { quest = "quest", questLoot = "quest", threat = "threat", tagged = "showTagged",
    buffs = "showBuffs", debuffs = "showDebuffs", classification = "showClassification" }
for index = 1, VALUE_SLOT_COUNT do editorContextForKey["value" .. index] = "value" end
local editorDescriptions = {
    name = L["The unit's name."],
    level = L["The unit's level. By default it is pinned left of the name."],
    guild = L["A friendly player's guild, when the client supplies it."],
    targetName = L["Who this unit is targeting, when the client allows it."],
    health = L["The unit's health bar."],
    power = L["The unit's power (mana, rage, energy). Hidden on units without power."],
    cast = L["The unit's current cast, with its spell icon, name and time left."],
    threat = L["Your threat % and lead on this unit, when the client allows it."],
    tagged = L["Appears when another player or group has tagged this mob."],
    quest = L["Marks a unit that is part of an active quest. When it drops a quest item, a loot bag shows here instead."],
    questLoot = L["Shows instead of the quest mark when the unit can drop a quest item."],
    raidIcon = L["Shows the assigned Blizzard raid target icon."],
    relationshipIcon = L["Marks current group or guild members outdoors."],
    pvpIcon = L["Marks a PvP-flagged friendly player outdoors."],
    classification = L["Shows elite, rare, rare elite, or world-boss status."],
    buffs = L["Buffs on this unit."],
    debuffs = L["Debuffs on this unit."],
}
for index = 1, VALUE_SLOT_COUNT do
    editorDescriptions["value" .. index] = L["A custom part: choose what it shows, then anchor and place it."]
end
local editorBlueprint = assert(Options.editorBlueprint, "PlateSmith EditorBlueprint missing")
local CopyEditorLayout = editorBlueprint.CopyLayout
Options.editorProfile = "enemy"
Options.editorContext = "world"
-- 100% is the plate's size in game. The preview zooms from 100% to 300%; it opens fitted, as
-- large as shows the whole plate up to PREVIEW_FIT_ZOOM.
local PREVIEW_ZOOM_MIN, PREVIEW_ZOOM_MAX, PREVIEW_ZOOM_DEFAULT = 1, 3, 1
local PREVIEW_FIT_ZOOM = 2
Options.editorPreviewZoom = PREVIEW_ZOOM_DEFAULT
Options.editorPreviewFit = true
Options.editorSnap = true

-- Friendly plates keep two layouts outdoors: names only and full plate (positions differ; styles
-- and rules are shared). Studio edits the one the plates use unless the preview's switch picks
-- the other (editorFriendlyView, for this session).
function Options:EditorLiveFriendlyView()
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return settings and settings.friendly == "names" and "names" or "full"
end

function Options:EditorFriendlyView()
    return self.editorFriendlyView or self:EditorLiveFriendlyView()
end

function Options:SetEditorFriendlyView(view)
    if view ~= "names" and view ~= "full" then return false end
    self.editorFriendlyView = view ~= self:EditorLiveFriendlyView() and view or nil
    return self:SetEditorProfile(self.editorProfile)
end

function Options:CurrentEditorVariant()
    if self.editorProfile == "enemy" or self.editorProfile == "enemyDungeon" then return "full" end
    if self.editorContext == "dungeon" then return "dungeon" end
    return self:EditorFriendlyView()
end

local modeChoices = {
    { value = "auto", label = L["Automatic"] },
    { value = "own", label = L["PlateSmith skin"] },
    { value = "overlay", label = L["Overlay only"] },
}

local friendlyChoices = {
    { value = "names", label = L["Names only"] },
    { value = "full", label = L["Full plates"] },
    { value = "off", label = L["Blizzard plates"] },
}

local classificationStyleChoices = {
    { value = "icon", label = L["Blizzard icons"] },
    { value = "words", label = L["Words (Elite, Rare, Boss)"] },
    { value = "letters", label = L["Letters (+, R, R+, BOSS)"] },
}
local friendlyPvpChoices = {
    { value = "off", label = L["Off"] },
    { value = "colour", label = L["Name colour"] },
    { value = "icon", label = L["Faction icon"] },
    { value = "both", label = L["Colour and icon"] },
}

local targetHighlightChoices = {
    { value = "off", label = L["Off"], help = L["No extra glow. The health bar keeps its normal target edge."] },
    { value = "border", label = L["Steady glow"],
        help = L["Gold light follows the selected plate's text and visible bars, without a box around the whole plate."] },
    { value = "halo", label = L["Pulsing glow"], help = L["The same text-and-bar glow gently pulses around the selected plate."] },
}

local auraSourceChoices = {
    { value = "mine", label = L["Only mine (pet included)"] },
    { value = "all", label = L["Everyone's"] },
}

local function AddLabel(parent, text, x, y, template)
    return PS.UI.Controls.Label(parent, text, x, y, template)
end

local function WidgetName(key, suffix)
    local safeKey = key:gsub("[^%w_]", "_")
    return "PlateSmith" .. safeKey:sub(1, 1):upper() .. safeKey:sub(2) .. suffix
end

function Options:GetEditorLayout()
    return CopyEditorLayout(self.editorLayout)
end

function Options:ApplyEditorLayout(layout)
    PS.SetLayout(layout, self.editorProfile, self:CurrentEditorVariant())
    self:ReloadEditorLayout()
end

local ROW_HEIGHT, HEADER_HEIGHT, GROUP_GAP = 29, 30, 8

-- Folded groups show only their header bar; they stay folded for the session.
function Options:ToggleEditorGroup(groupKey)
    self.editorFoldedGroups = self.editorFoldedGroups or {}
    self.editorFoldedGroups[groupKey] = not self.editorFoldedGroups[groupKey] or nil
    self:RefreshEditorComponentList(PS.GetSettings())
end

-- A component's name in Studio: a custom value's own name when it has one.
function Options:EditorComponentLabel(key)
    local position = type(key) == "string" and not key:match("^group%.%d+$") and self.editorLayout and self.editorLayout[key]
    if position and position.name and not key:match("^value%d+$") then return position.name end
    if type(key) == "string" and key:match("^value%d+$") then
        local profile = PS.GetPlateProfileSettings(self.editorProfile)
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if slot and slot.name then return slot.name end
    end
    return editorLabels[key] or key
end

-- Studio's confirm window: text, the action's button label, and what it does. One window,
-- reused; Escape or Cancel leaves everything as it was. PlateSmith's own window, not a
-- StaticPopup (that taints Blizzard's secure popup state).
function Options:ConfirmStudioAction(text, actionLabel, onConfirm)
    local dialog = self.editorConfirmDialog
    if not dialog then
        local Window = PS.UI.Window
        local chrome = self.studioChrome
        dialog = Window.Create("PlateSmithStudioConfirmDialog", {
            width = 420, height = 150, closeButton = false, closeOnEscape = true, movable = false,
            border = Window.colours.studio,
        })
        chrome.DressStudioDialog(dialog)
        dialog.text = chrome.DialogText(dialog, 26)
        -- The action (red: it changes things) and Cancel (dark).
        dialog.remove = chrome.CreateStudioButton(dialog, L["Remove"], 150, 32, "action")
        dialog.remove:SetScript("OnClick", function()
            dialog:Hide()
            if dialog.onConfirm then dialog.onConfirm() end
        end)
        dialog.remove:SetPoint("BOTTOM", dialog, "BOTTOM", -84, 22)
        dialog.cancel = chrome.CreateStudioButton(dialog, L["Cancel"], 150, 32)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() end)
        dialog.cancel:SetPoint("BOTTOM", dialog, "BOTTOM", 84, 22)
        self.editorConfirmDialog = dialog
    end
    dialog.onConfirm = onConfirm
    dialog.text:SetText(text)
    dialog.remove.label:SetText(actionLabel)
    dialog:Show()
    return dialog
end

-- Studio's name window (new, duplicate or rename a profile): a question, an edit box with its
-- current text highlighted, OK and Cancel. onAccept(text) returns ok, reason; a refusal shows
-- its reason and keeps the window open. PlateSmith's own window, not a StaticPopup.
function Options:PromptStudioName(text, initial, onAccept)
    local dialog = self.editorNameDialog
    if not dialog then
        local Window = PS.UI.Window
        local chrome = self.studioChrome
        dialog = Window.Create("PlateSmithStudioNameDialog", {
            width = 420, height = 190, closeButton = false, closeOnEscape = true, movable = false,
            border = Window.colours.studio,
        })
        chrome.DressStudioDialog(dialog)
        dialog.text = chrome.DialogText(dialog, 24)
        local edit = PS.UI.Controls.EditBox(dialog, { height = 32, fontSize = 15, insets = { 10, 10 },
            maxLetters = PS.Profiles.MAX_NAME_LENGTH, fill = { 0.02, 0.02, 0.03, 1 }, rule = { 0.89, 0.75, 0.13, 0.8 } })
        edit:SetPoint("TOPLEFT", dialog, "TOPLEFT", 40, -56)
        edit:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -40, -56)
        dialog.edit = edit
        dialog.error = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dialog.error:SetFont(chrome.FONT, 13)
        dialog.error:SetTextColor(1, 0.45, 0.4)
        dialog.error:SetPoint("TOP", edit, "BOTTOM", 0, -8)
        local function Accept()
            local ok, reason = true, nil
            if dialog.onAccept then ok, reason = dialog.onAccept(edit:GetText()) end
            if ok then
                edit:ClearFocus()
                dialog:Hide()
            else
                -- Settings' refusals are English keys; Studio's own are already translated.
                dialog.error:SetText(reason and L[tostring(reason)] or L["That name cannot be used."])
            end
        end
        dialog.ok = chrome.CreateStudioButton(dialog, L["OK"], 150, 32, "primary")
        dialog.ok:SetScript("OnClick", Accept)
        dialog.ok:SetPoint("BOTTOM", dialog, "BOTTOM", -84, 22)
        dialog.cancel = chrome.CreateStudioButton(dialog, L["Cancel"], 150, 32)
        dialog.cancel:SetScript("OnClick", function() edit:ClearFocus() dialog:Hide() end)
        dialog.cancel:SetPoint("BOTTOM", dialog, "BOTTOM", 84, 22)
        edit:SetScript("OnEnterPressed", Accept)
        edit:SetScript("OnEscapePressed", function() edit:ClearFocus() dialog:Hide() end)
        self.editorNameDialog = dialog
    end
    dialog.onAccept = onAccept
    dialog.text:SetText(text)
    dialog.error:SetText("")
    dialog.edit:SetText(initial or "")
    dialog:Show()
    dialog.edit:SetFocus()
    if dialog.edit.HighlightText then dialog.edit:HighlightText() end
    return dialog
end

function Options:ConfirmRemoveValueSlot(key)
    return self:ConfirmStudioAction(string.format(L["Remove %s from this plate?"], self:EditorComponentLabel(key)),
        L["Remove"], function() self:RemoveValueSlot(key) end)
end

-- Selects a custom value and puts the cursor in its name, all of it highlighted to type over.
function Options:BeginEditorRename(key)
    if type(key) ~= "string" or not key:match("^value%d+$") then return false end
    if self.selectedComponent ~= key then self:SelectEditorComponent(key) end
    local edit = self.editorComponentNameEdit
    if not edit then return false end
    edit:SetFocus()
    if edit.HighlightText then edit:HighlightText() end
    return true
end

-- Rename in the tree, on the row itself (right-click > Rename, or double-click a group or
-- part): an edit box over the row's label, its name highlighted to type over. Enter or
-- clicking away keeps it, Escape cancels, blank goes back to the default name.
function Options:BeginEditorTreeRename(key)
    if type(key) ~= "string" or not (self.editorLayout and self.editorLayout[key]) then return false end
    local isGroup = key:match("^group%.%d+$")
    local row = isGroup and self.editorCustomGroupHeaders and self.editorCustomGroupHeaders[key]
        or self.editorComponentButtons and self.editorComponentButtons[key]
    if not (row and row.label) then return false end
    -- The row being named is the selected one.
    if isGroup and self.editorSelectedGroup ~= key then self:SelectEditorGroup(key)
    elseif not isGroup and self.selectedComponent ~= key then self:SelectEditorComponent(key) end
    local edit = self.editorTreeRenameEdit
    if not edit then
        edit = PS.UI.Controls.EditBox(row, { fontSize = 15, colour = { 1, 0.86, 0.3 }, insets = { 4, 4 },
            maxLetters = Schema.VALUE_NAME_LENGTH, fill = { 0.03, 0.03, 0.04, 0.95 }, rule = { 0.89, 0.75, 0.13, 0.9 } })
        local function Finish(instance, keep)
            if not instance.renaming then return end
            local renamingKey, label = instance.renaming, instance.renamingLabel
            instance.renaming = nil
            instance:ClearFocus()
            instance:Hide()
            if label then label:Show() end
            if not keep then return end
            local text = instance:GetText()
            -- Each path refreshes the tree and the inspector.
            if renamingKey:match("^group%.%d+$") then
                self:RenameEditorGroup(renamingKey, text)
            elseif renamingKey:match("^value%d+$") then
                PS.SetPlateValueSlot(self.editorProfile, renamingKey, "name", text)
                self:RefreshEditorAppearance(PS.GetSettings())
            else
                -- A built-in part's own name in the tree (blank: its standard name).
                PS.RenameComponent(renamingKey, text, self.editorProfile, self:CurrentEditorVariant())
                self:ReloadEditorLayout()
            end
        end
        edit:SetScript("OnEnterPressed", function(instance) Finish(instance, true) end)
        edit:SetScript("OnEscapePressed", function(instance) Finish(instance, false) end)
        edit:SetScript("OnEditFocusLost", function(instance) Finish(instance, true) end)
        edit.Finish = Finish
        self.editorTreeRenameEdit = edit
    end
    if edit.renaming then edit.Finish(edit, true) end
    edit:SetParent(row)
    edit:SetFrameLevel(row:GetFrameLevel() + 5)
    edit:ClearAllPoints()
    edit:SetPoint("LEFT", row.label, "LEFT", -4, 0)
    edit:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    edit:SetHeight(24)
    local position = self.editorLayout and self.editorLayout[key]
    edit:SetText(isGroup and (position and position.name or row.label:GetText() or "") or self:EditorComponentLabel(key))
    edit.renaming, edit.renamingLabel = key, row.label
    row.label:Hide()
    edit:Show()
    edit:SetFocus()
    if edit.HighlightText then edit:HighlightText() end
    return true
end

function Options:RemoveValueSlot(key)
    if type(key) ~= "string" or not key:match("^value%d+$") then return false end
    -- Everything goes (settings, style, rules): the next part added here starts fresh.
    if not PS.ResetValueSlot(self.editorProfile, key) then return false end
    self:RefreshEditorAppearance(PS.GetSettings())
    if self.selectedComponent == key then self:SelectEditorComponent("health") end
    return true
end

-- The tree: groups and parts as one hierarchy, children indented under their parent.
local TREE_INDENT = 26

function Options:RefreshEditorComponentList(settings, revealKey)
    local content = self.editorListContent
    if not content then return end
    local layout = self.editorLayout or {}
    self.editorCustomGroupHeaders = self.editorCustomGroupHeaders or {}
    for key in pairs(layout) do
        if key:match("^group%.%d+$") and not self.editorCustomGroupHeaders[key] and self.CreateEditorGroupHeader then
            self.editorCustomGroupHeaders[key] = self:CreateEditorGroupHeader(content, key)
        end
    end
    for _, header in pairs(self.editorCustomGroupHeaders) do header:Hide() end
    for _, button in pairs(self.editorComponentButtons or {}) do button:Hide() end
    -- Who sits under whom, and each group's parts (all, and shown), worked out once.
    local tree = self:EditorTreeIndex(settings)
    local counts = self:EditorTreeCounts(settings)
    -- The search field narrows the tree to parts whose name contains its text, with their parents.
    local query = self.editorSearchText and self.editorSearchText:lower() or ""
    local matched
    if query ~= "" then
        matched = {}
        for key in pairs(layout) do
            if not key:match("^group%.%d+$") and self:IsEditorComponentRelevant(key, settings)
                and self:EditorComponentLabel(key):lower():find(query, 1, true) then
                local current, depth = key, 0
                while current and depth <= Schema.MAX_DEPTH do
                    matched[current] = true
                    current, depth = layout[current] and layout[current].parent, depth + 1
                end
            end
        end
    end
    local width, y, revealTop, tops, rows = content:GetWidth(), 0, nil, {}, {}
    local headers = {}
    -- The Plate row: the whole plate's size and scale.
    local plateRow = self.editorPlateRow
    if plateRow then
        plateRow:ClearAllPoints()
        plateRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        plateRow:SetWidth(width)
        plateRow:SetSelected(self.editorInspectingPlate)
        plateRow:SetShown(query == "")
        if query == "" then
            tops[#tops + 1] = 0
            rows[#rows + 1] = { frame = plateRow, top = 0, height = HEADER_HEIGHT - 2 }
            y = HEADER_HEIGHT + 2
        end
    end

    local function Visible(key)
        if matched then return matched[key] end
        if key:match("^group%.%d+$") then
            -- A group whose parts this plate type does not use is hidden; an empty one shows.
            return #self:EditorTreeChildren(key, settings, tree) > 0 or counts.all[key] == nil
        end
        return true
    end

    local function Node(key, parentKey, depth, last)
        local isGroup = key:match("^group%.%d+$") ~= nil
        local indent = depth * TREE_INDENT
        local children = {}
        for _, child in ipairs(self:EditorTreeChildren(key, settings, tree)) do
            if Visible(child) then children[#children + 1] = child end
        end
        local folded = self.editorFoldedGroups and self.editorFoldedGroups[key] and query == ""
        if isGroup then
            local header = self.editorCustomGroupHeaders[key]
            if not header then return end
            headers[#headers + 1] = header
            header:SetSelected(self.editorSelectedGroup == key)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
            header:SetWidth(width - indent)
            header.label:SetText(self:EditorNodeLabel(key))
            header:Show()
            tops[#tops + 1] = y
            rows[#rows + 1] = { frame = header, top = y, height = HEADER_HEIGHT - 4, key = key, parentKey = parentKey,
                depth = depth, isGroup = true }
            -- Three states: all shown, none shown, or mixed (the eye's half-lit look).
            local total, shown = counts.used[key] or 0, counts.shown[key] or 0
            local tick = header.visibility
            tick.mixed = shown > 0 and shown < total
            tick:SetChecked(shown > 0 and not tick.mixed)
            header.folded = folded and true or false
            if header.SetFolded then header:SetFolded(header.folded) end
            y = y + HEADER_HEIGHT
        else
            local button = self.editorComponentButtons[key]
            if not button then return end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
            button:SetWidth(width - indent)
            button.label:SetText(self:EditorComponentLabel(key))
            tops[#tops + 1] = y
            rows[#rows + 1] = { frame = button, top = y, height = ROW_HEIGHT - 1, key = key, partKey = key,
                parentKey = parentKey, depth = depth }
            -- The connector from the parent's eye: none at the top level; it stops at the last child.
            if button.connectors then
                local bright = self:StudioAccess().highContrast
                for _, line in ipairs(button.connectors) do
                    line:SetShown(depth > 0)
                    line:SetColorTexture(bright and 0.95 or 0.72, bright and 0.85 or 0.58, bright and 0.6 or 0.36, bright and 1 or 0.9)
                end
                button.connectors[1]:SetHeight(last and 15 or ROW_HEIGHT)
            end
            if button.visibility then button.visibility:SetChecked(self:IsEditorPartShown(key, settings)) end
            -- A part with children folds like a group.
            if button.fold then
                button.fold:SetShown(#children > 0)
                button.fold:SetFolded(folded and true or false)
            end
            button:Show()
            if key == revealKey then revealTop = y end
            y = y + ROW_HEIGHT
        end
        local top = tops[#tops]
        if folded then
            if revealKey and self:IsEditorUnder(revealKey, key) then revealTop = y - (isGroup and HEADER_HEIGHT or ROW_HEIGHT) end
            return
        end
        for index, child in ipairs(children) do Node(child, key, depth + 1, index == #children) end
        -- A part with children, not its parent's last: its line down to the next sibling runs past
        -- its children's rows, so the parent's line has no break.
        if not isGroup and #children > 0 and not last and depth > 0 then
            local button = self.editorComponentButtons[key]
            if button and button.connectors then button.connectors[1]:SetHeight(y - top) end
        end
        if isGroup then y = y + GROUP_GAP end
    end
    local roots = {}
    for _, key in ipairs(self:EditorTreeChildren(nil, settings, tree)) do
        if Visible(key) then roots[#roots + 1] = key end
    end
    for index, key in ipairs(roots) do Node(key, nil, 0, index == #roots) end
    -- No gap after the last group: the list ends at its last row.
    if #roots > 0 and roots[#roots]:match("^group%.%d+$") then y = y - GROUP_GAP end
    content:SetHeight(math.max(1, y))
    self.editorTreeHeaders = headers

    local scroll = self.editorListScroll
    local viewHeight = scroll:GetHeight()
    if scroll.GetVerticalScroll and scroll.SetVerticalScroll then
        local offset = math.min(scroll:GetVerticalScroll() or 0, math.max(0, y - viewHeight))
        if revealTop then
            if revealTop < offset then offset = revealTop
            elseif revealTop + ROW_HEIGHT > offset + viewHeight then offset = revealTop + ROW_HEIGHT - viewHeight end
        end
        scroll:SetVerticalScroll(math.max(0, offset))
    end
    self.editorListRows = rows
    if self.editorListScrollBar then
        self.editorListScrollBar.snapTops = tops
        self.editorListScrollBar.onScrolled = function(offset) self:FadeEditorListOverflow(offset) end
        self.editorListScrollBar:Sync()
    end
    self:FadeEditorListOverflow(scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0)
    self:ApplyEditorListInk()
end

-- Rows the list's bottom edge would cut through are hidden (and unclickable) until scrolled to,
-- so the list only ever shows whole rows.
function Options:FadeEditorListOverflow(offset)
    local scroll = self.editorListScroll
    if not scroll or not self.editorListRows then return end
    local bottom = (offset or 0) + scroll:GetHeight()
    for _, row in ipairs(self.editorListRows) do
        local whole = row.top + row.height <= bottom + 0.5
        row.frame:SetAlpha(whole and 1 or 0)
        if row.frame.EnableMouse then row.frame:EnableMouse(whole) end
    end
end

-- The tree's labels: light on its dark panel, the selected part in gold (white and yellow in
-- high contrast).
function Options:ApplyEditorListInk()
    local highContrast = self:StudioAccess().highContrast
    for key, button in pairs(self.editorComponentButtons or {}) do
        local selected = key == self.selectedComponent
        if highContrast then
            button.label:SetTextColor(1, selected and 0.86 or 1, selected and 0.2 or 1)
        else
            button.label:SetTextColor(selected and 1 or 0.93, selected and 0.82 or 0.87, selected and 0.12 or 0.73)
        end
        button.label:SetShadowColor(0, 0, 0, 1)
    end
end

-- Whether the tree's eye shows key as shown: in this layout, and not kept off by its switch.
function Options:IsEditorPartShown(key, settings)
    local position = self.editorLayout and self.editorLayout[key]
    if not position or position.visible == false then return false end
    local switch = PART_SWITCHES[key]
    settings = settings or PS.GetSettings()
    return not (switch and settings and settings[switch] == false)
end

-- Shows or hides key in this layout; showing it also turns its switch on.
local function WritePartVisibility(self, key, visible)
    PS.SetComponentVisibility(key, visible, self.editorProfile, self:CurrentEditorVariant())
    local switch = PART_SWITCHES[key]
    local settings = PS.GetSettings()
    if visible and switch and settings and settings[switch] == false then PS.SetOption(switch, true) end
end

function Options:SetEditorGroupVisibility(groupKey, visible)
    for _, key in ipairs(editorOrder) do
        if self:IsEditorUnder(key, groupKey) and self:IsEditorComponentRelevant(key) then
            WritePartVisibility(self, key, visible)
        end
    end
    self:ReloadEditorLayout()
end

-- Whether this plate type can take another value, and the free slot it would use.
function Options:EditorFreeValueSlot()
    if self.editorProfile ~= "enemy" and self.editorProfile ~= "enemyDungeon"
        and self.editorContext ~= "dungeon"
        and self:EditorFriendlyView() ~= "full" then return nil, "plate" end
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    if not profile or not profile.valueSlots then return nil, "plate" end
    for index = 1, VALUE_SLOT_COUNT do
        local key = "value" .. index
        if profile.valueSlots[key].source == "off" then return key end
    end
    return nil, "full"
end

-- Adds a value showing source (default Health %), inside the selected group if there is one.
function Options:AddValueSlot(source, kind)
    local key = self:EditorFreeValueSlot()
    if not key then return false end
    PS.SetPlateValueSlot(self.editorProfile, key, "kind", kind)
    if not PS.SetPlateValueSlot(self.editorProfile, key, "source", source or "healthPercent") then return false end
    if self.editorSelectedGroup then
        PS.SetComponentParent(key, self.editorSelectedGroup, nil, self.editorProfile, self:CurrentEditorVariant())
    end
    self:ReloadEditorLayout()
    self:SelectEditorComponent(key)
    return true
end

-- A copy of a value in a free slot: its settings, a little below it, under the same parent.
function Options:DuplicateEditorValue(key)
    local copy = self:EditorFreeValueSlot()
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    local slot = profile and profile.valueSlots and profile.valueSlots[key]
    local position = self.editorLayout and self.editorLayout[key]
    if not copy or not slot or not position then return false end
    PS.ResetValueSlot(self.editorProfile, copy)
    -- One write, one refresh: every field is checked before any is stored.
    local fields = {}
    for _, field in ipairs({ "kind", "source", "anchor", "layer", "whenMissing", "fontSize", "template", "width",
        "height", "icon", "colour" }) do
        if slot[field] ~= nil then fields[field] = slot[field] end
    end
    PS.SetPlateValueSlotFields(self.editorProfile, copy, fields)
    -- Its style and rules come along: a duplicate looks and behaves the same.
    local style = profile.styles and profile.styles[key]
    if style then PS.ApplyStylePreset(self.editorProfile, copy, { style = style }) end
    local rules = profile.rules and profile.rules[key]
    if rules then PS.SetPartRules(self.editorProfile, copy, rules) end
    local variant = self:CurrentEditorVariant()
    PS.SetComponentParent(copy, position.parent, nil, self.editorProfile, variant)
    PS.SetComponentPosition(copy, position.x, position.y - 12, self.editorProfile, variant)
    PS.SetComponentScale(copy, position.scale or 1, self.editorProfile, variant)
    self:ReloadEditorLayout()
    self:SelectEditorComponent(copy)
    return copy
end

-- Puts a deleted part back (inside the selected group if there is one) and selects it.
function Options:AddEditorComponent(key)
    if not PS.RestoreComponent(key, self.editorSelectedGroup, self.editorProfile, self:CurrentEditorVariant()) then
        return false
    end
    self.editorSelectedGroup = nil
    self:ReloadEditorLayout()
    self:SelectEditorComponent(key)
    return true
end

function Options:RemoveEditorComponent(key)
    if not PS.RemoveComponent(key, self.editorProfile, self:CurrentEditorVariant()) then return false end
    if self.selectedComponent == key then self.selectedComponent = nil end
    self:ReloadEditorLayout()
    self:SelectEditorPlate()
    return true
end

function Options:ResetEditorNode(key)
    if not PS.ResetComponent(key, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self:ReloadEditorLayout()
    self:RefreshEditorInspectorContext()
    self:UpdateEditorSelectionHandles()
    return true
end

-- Delete, by kind: a group (its contents move up), a value (its slot is freed), a built-in part
-- (it can be added back from + Add). Each asks first.
function Options:DeleteEditorNode(key)
    if key:match("^group%.%d+$") then return self:ConfirmDeleteEditorGroup(key) end
    if key:match("^value%d+$") then return self:ConfirmRemoveValueSlot(key) end
    return self:ConfirmStudioAction(string.format(L["Delete %s? Add it back any time from + Add."],
        self:EditorComponentLabel(key)), L["Delete"], function() self:RemoveEditorComponent(key) end)
end

-- The + Add menu: { text, func, disabled, children } entries. Parts by type; one that is on the
-- plate (or not used by this plate type) is listed but off, with the reason.
local ADD_MENU = {
    { label = L["Text"], keys = { "name", "level", "guild", "threat", "tagged", "targetName" } },
    { label = L["Bars"], keys = { "health", "power", "cast" } },
    { label = L["Icons"], keys = { "quest", "questLoot", "raidIcon", "relationshipIcon", "pvpIcon", "classification" } },
    { label = L["Auras"], keys = { "buffs", "debuffs" } },
}

function Options:EditorAddMenuEntries()
    local entries = { { text = L["Group"], func = function() self:AddEditorGroup() end } }
    local listed = {}
    local function PartEntry(key)
        listed[key] = true
        local position = self.editorLayout and self.editorLayout[key]
        local label = self:EditorComponentLabel(key)
        local entry = { text = label, func = function() self:AddEditorComponent(key) end }
        if not self:IsEditorComponentRelevant(key, nil, true) then
            entry.disabled, entry.text = true, string.format(L["%s (not used here)"], label)
        elseif not (position and position.removed) then
            entry.disabled, entry.text = true, string.format(L["%s (on the plate)"], label)
        end
        return entry
    end
    for _, category in ipairs(ADD_MENU) do
        local children = {}
        for _, key in ipairs(category.keys) do children[#children + 1] = PartEntry(key) end
        entries[#entries + 1] = { text = category.label, children = children }
    end
    -- Parts other addons registered.
    local others = {}
    for _, key in ipairs(editorOrder) do
        if not listed[key] and not key:match("^value%d+$") then others[#others + 1] = PartEntry(key) end
    end
    if #others > 0 then entries[#entries + 1] = { text = L["Other"], children = others } end
    local free, reason = self:EditorFreeValueSlot()
    local values = {}
    for _, choice in ipairs(catalog.valueSourceChoices or {}) do
        values[#values + 1] = { text = choice.label, disabled = not free,
            func = function() self:AddValueSlot(choice.value) end }
    end
    local valueText = L["Value"]
    if not free then
        valueText = reason == "full" and L["Value (all in use)"] or L["Value (not on this plate type)"]
    end
    entries[#entries + 1] = { text = valueText, children = values, disabled = not free }
    -- Shapes: a bar filled by a percentage, a box, an icon (custom parts that are not text).
    local shapes = {
        { text = L["Bar (health %)"], func = function() self:AddValueSlot("healthPercent", "bar") end },
        { text = L["Bar (power %)"], func = function() self:AddValueSlot("powerPercent", "bar") end },
        { text = L["Bar (threat %)"], func = function() self:AddValueSlot("threatPercent", "bar") end },
        { text = L["Box"], func = function() self:AddValueSlot("static", "box") end },
        { text = L["Icon"], func = function() self:AddValueSlot("static", "icon") end },
    }
    for _, shape in ipairs(shapes) do shape.disabled = not free end
    entries[#entries + 1] = { text = L["Shape"], children = shapes, disabled = not free }
    return entries
end

-- Whether key is the first part its parent's stack lays out (it holds the stack's place).
function Options:IsEditorStackFirst(key)
    local layout = self.editorLayout or {}
    local position = layout[key]
    if not position or not position.parent then return false end
    for _, sibling in ipairs(self:EditorTreeChildren(position.parent)) do
        if self:IsEditorStacked(sibling) then return sibling == key end
    end
    return false
end

-- Stacks a node's children (down, up, right, left; nil: free).
function Options:SetEditorStack(key, stack, gap)
    if not PS.SetComponentStack(key, stack, gap, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self:ReloadEditorLayout()
    self:RefreshEditorInspectorContext()
    self:UpdateEditorSelectionHandles()
    return true
end

-- Layers: Bring to front / Send to back set a layer past every other part's; Reset returns to
-- the tree's order.
function Options:SetEditorLayer(key, layer)
    if not PS.SetComponentLayer(key, layer, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self:ReloadEditorLayout()
    self:RefreshEditorComponentLayers()
    return true
end

function Options:EditorLayerExtreme(front, except)
    local extreme = 0
    for key, position in pairs(self.editorLayout or {}) do
        local layer = key ~= except and type(position) == "table" and tonumber(position.layer)
        if layer then extreme = front and math.max(extreme, layer) or math.min(extreme, layer) end
    end
    return extreme
end

function Options:ReturnEditorComponentToStack(key)
    if not PS.SetComponentFree(key, false, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self:ReloadEditorLayout()
    self:UpdateEditorSelectionHandles()
    return true
end

-- A tree row's menu: Rename (groups, values), Duplicate (values), Return to stack, Reset, Delete.
function Options:EditorContextMenuEntries(key)
    local entries = {}
    local position = self.editorLayout and self.editorLayout[key]
    local parent = position and position.parent and self.editorLayout[position.parent]
    if position and position.free and parent and parent.stack then
        entries[#entries + 1] = { text = L["Return to stack"], func = function() self:ReturnEditorComponentToStack(key) end }
    end
    -- Everything can be renamed: groups and values by their own name, built-in parts by a name
    -- shown in Studio's tree (blank goes back to the standard one).
    entries[#entries + 1] = { text = L["Rename"], func = function() self:BeginEditorTreeRename(key) end }
    if key:match("^value%d+$") then
        entries[#entries + 1] = { text = L["Duplicate"], disabled = not self:EditorFreeValueSlot(),
            func = function() self:DuplicateEditorValue(key) end }
    end
    entries[#entries + 1] = { text = L["Bring to front"], func = function()
        self:SetEditorLayer(key, math.min(10, self:EditorLayerExtreme(true, key) + 1))
    end }
    entries[#entries + 1] = { text = L["Send to back"], func = function()
        self:SetEditorLayer(key, math.max(-10, self:EditorLayerExtreme(false, key) - 1))
    end }
    if position and position.layer then
        entries[#entries + 1] = { text = L["Layer from the tree"], func = function() self:SetEditorLayer(key, nil) end }
    end
    entries[#entries + 1] = { text = L["Reset position and size"], func = function() self:ResetEditorNode(key) end }
    entries[#entries + 1] = { text = L["Delete"], func = function() self:DeleteEditorNode(key) end }
    return entries
end

-- Shows entries in PlateSmith's own menu under anchor (entries with children open a submenu),
-- so Studio's menus never touch Blizzard's shared dropdown state.
function Options:ShowEditorMenu(entries, anchor)
    self.editorMenuEntries = entries
    return PS.UI.Menu.Open(anchor, entries)
end

function Options:OpenEditorAddMenu(anchor) self:ShowEditorMenu(self:EditorAddMenuEntries(), anchor) end
function Options:OpenEditorContextMenu(key, anchor) self:ShowEditorMenu(self:EditorContextMenuEntries(key), anchor) end

function Options:RefreshEditorInspectorContext()
    local key = self.selectedComponent
    local plate = self.editorInspectingPlate and not key
    self:RefreshEditorBreadcrumb()
    local groupKey = not key and self.editorSelectedGroup
    local group = groupKey and self.editorLayout and self.editorLayout[groupKey]
    if groupKey and not group then self.editorSelectedGroup = nil end
    if self.editorComponentTitle then
        self.editorComponentTitle:SetText(group and (group.name or L["Group"]) or plate and L["Plate"]
            or key and self:EditorComponentLabel(key) or L["Select a part"])
    end
    local nameEdit = self.editorComponentNameEdit
    if nameEdit then
        local renamable = key and key:match("^value%d+$") and true or false
        nameEdit.studioEditing = false
        nameEdit:ClearFocus()
        nameEdit:SetText(renamable and self:EditorComponentLabel(key) or "")
        nameEdit:SetShown(renamable)
        if self.editorComponentTitle then self.editorComponentTitle:SetShown(not renamable) end
    end
    if self.editorComponentDescription then
        self.editorComponentDescription:SetText(group and L["A group of parts."]
            or plate and L["The whole plate's scale, for this plate type."]
            or key and (editorDescriptions[key] or L["A part of the plate."]) or "")
    end
    local selectedContext = group and "group" or plate and "plate" or key and (editorContextForKey[key] or "other")
    local movable = key and self:IsEditorComponentRelevant(key)
        and editorDefinitions[key] and editorDefinitions[key].movable ~= false
    -- What the inspector shows (Inspector's sections read it as they lay out).
    self.editorInspectorSelection = { key = key, group = group and groupKey or nil, plate = plate,
        context = selectedContext, movable = movable and true or false }
    if group and self.groupControlsRefresh then self.groupControlsRefresh() end
    for contextKey, frame in pairs(self.editorContextFrames or {}) do
        frame:SetShown(contextKey == selectedContext)
    end
    if self.editorSurnameControl then
        self.editorSurnameControl:SetShown(key == "name" and self.editorProfile == "friendlyPlayer")
    end
    if self.editorCoordinateX and self.editorCoordinateY then
        local position = key and self.editorLayout and self.editorLayout[key]
        self.editorCoordinateX:SetText(position and tostring(position.x) or "")
        self.editorCoordinateY:SetText(position and tostring(position.y) or "")
    end
    if self.editorComponentScaleSlider then self.editorComponentScaleSlider:Refresh() end
    if self.editorPlacementRefresh then self.editorPlacementRefresh() end
    if self.editorMoveControls then
        self.editorMoveControls:SetShown(movable and self.editorInspectorPage == "components" and true or false)
    end
    if self.valueControlsRefresh then self.valueControlsRefresh() end
    if self.LayoutEditorInspector then self:LayoutEditorInspector() end
end

function Options:RefreshEditorComponentLayers()
    if not self.editorPreviewStage or not self.editorComponents then return end
    local profile = type(PS.GetPlateProfileSettings) == "function"
        and PS.GetPlateProfileSettings(self.editorProfile) or nil
    -- The same drawing order as the plates (Schema's DrawOrder); the selection outline and its
    -- handles draw above it all.
    local base = self.editorPreviewStage:GetFrameLevel()
    local rank, count = Schema.DrawOrder(self.editorLayout or {})
    for key, component in pairs(self.editorComponents) do
        local slot = key:match("^value%d+$") and profile and profile.valueSlots[key] or nil
        local level = slot and slot.layer ~= "front" and 1 or 2 + count - (rank[key] or count)
        -- A faint ghost (turned off, hidden by a rule, an unlit sample) sits under every drawn
        -- part, so a press over a drawn part never picks the ghost.
        if component:IsShown() and not self:IsEditorPartDrawn(key) then level = 0 end
        component:SetFrameLevel(base + level)
    end
end

-- The tree's Plate row: the inspector shows the plate's own size and scale.
function Options:SelectEditorPlate()
    -- One selection at a time: a selected group lets go (its heading and outline).
    self.editorSelectedGroup = nil
    self:SelectEditorComponent(nil, true)
    return true
end

-- Selects a part (nil: none; plate: the Plate row instead). Clears a selected group unless key
-- is nil.
function Options:SelectEditorComponent(key, plate)
    -- An open colour picker belongs to the part it was opened for: close it before the selection
    -- changes, so it cannot write to the next part.
    if key ~= self.selectedComponent and ColorPickerFrame and ColorPickerFrame.IsShown and ColorPickerFrame:IsShown() then
        ColorPickerFrame:Hide()
    end
    self.editorInspectingPlate = plate and key == nil or false
    if key ~= nil then self.editorSelectedGroup = nil end
    if key and not self:IsEditorComponentRelevant(key) then
        key = self:IsEditorComponentRelevant("name") and "name" or nil
    end
    if key and not editorDefinitions[key] then return end
    local changed = self.selectedComponent ~= key
    self.selectedComponent = key
    -- The tree rebuild also sets the rows' eyes and labels.
    self:RefreshEditorComponentList(PS.GetSettings(), key)
    if changed and self.editorComponentScroll then self.editorComponentScroll:SetVerticalScroll(0) end
    -- The selection outline is the handles' box (tight to a text part's string); the part's own
    -- frame border stays off, or a text wider than its frame shows a second box through it.
    for _, component in pairs(self.editorComponents or {}) do
        if component.SetBackdropBorderColor then component:SetBackdropBorderColor(1, 0.72, 0.12, 0) end
    end
    for componentKey, button in pairs(self.editorComponentButtons or {}) do
        if button.selection then button.selection:SetShown(componentKey == key) end
    end
    self:RefreshEditorComponentLayers()
    self:UpdateEditorSelectionHandles()
    -- Either refreshes the inspector once.
    if key and self.editorWorkspacePage ~= "settings" and self.editorInspectorPage ~= "components" then
        self:SetEditorInspectorPage("components")
    else
        self:RefreshEditorInspectorContext()
    end
end

-- A press on a part in the preview selects it, unless it belongs to the selected group: then
-- the group stays selected, so dragging moves the whole group.
function Options:PressEditorComponent(key)
    local group = self.editorSelectedGroup
    if group and not self.selectedComponent and self:IsEditorUnder(key, group) then return end
    if self.selectedComponent ~= key then self:SelectEditorComponent(key) end
end

-- Handles at the selected component's corners and edge midpoints. They belong to the scaled
-- stage, so their size is divided by the zoom to stay the same on screen. Dragging one moves
-- that side (or corner) and keeps the opposite one where it was: bars change their own sizes
-- (plate width, bar heights), aura rows their icons per line, lines and icon size, anything
-- else its scale (corners only, as it keeps its shape).
local HANDLE_POINTS = {
    { "TOPLEFT", -1, 1 }, { "TOP", 0, 1 }, { "TOPRIGHT", 1, 1 }, { "LEFT", -1, 0 },
    { "RIGHT", 1, 0 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOM", 0, -1 }, { "BOTTOMRIGHT", 1, -1 },
}
local HANDLE_SIZE, HANDLE_HIT = 12, 22 -- drawn size, clickable size (screen pixels)
local HANDLE_COLOURS = { normal = { 1, 0.80, 0.16 }, hover = { 1, 0.96, 0.70 }, pressed = { 1, 0.50, 0.08 } }
local OUTLINE_WIDTH = 2 -- the selection outline, screen pixels
-- Which profile size each bar's handles change: horizontal handles, then vertical ones, with
-- Schema's range and the step. (The health bar's width is the plate's; the power and cast bars
-- have their own, or follow it.)
local function BarSize(key, range, step) return { key = key, range = range, step = step } end
local profileRanges, optionalRanges = Schema.profileRanges, Schema.optionalProfileRanges
local BAR_SIZES = {
    health = { width = BarSize("width", profileRanges.width, 2), height = BarSize("healthHeight", profileRanges.healthHeight, 1) },
    power = { width = BarSize("powerWidth", optionalRanges.powerWidth, 2), height = BarSize("powerHeight", profileRanges.powerHeight, 1) },
    cast = { width = BarSize("castWidth", optionalRanges.castWidth, 2), height = BarSize("castHeight", optionalRanges.castHeight, 1) },
}

-- The size each bar is drawn at: its own, or the one it follows.
local function BarSizes(profile)
    local width = profile.width or 112
    return { width = width, healthHeight = profile.healthHeight, powerHeight = profile.powerHeight,
        powerWidth = profile.powerWidth or width, castWidth = profile.castWidth or width,
        castHeight = profile.castHeight or math.max(5, (profile.healthHeight or 10) - 3) }
end
local AURA_ROWS = { buffs = true, debuffs = true }
local AURA_RANGES = Schema.auraLayoutRanges

local function Stepped(size, value)
    local range, step = size.range, size.step
    return math.max(range[1], math.min(range[2], math.floor(value / step + 0.5) * step))
end

local function Clamp(range, value)
    return math.max(range[1], math.min(range[2], math.floor(value + 0.5)))
end

-- Placement in the hierarchy (Schema's LayoutTransforms): a part is drawn at its parent's centre
-- plus its offset times the parent's drawn scale; its drawn scale is its own times the parent's.
-- A pinned part is the exception: an offset from its place on the parent's edge.
local ROOT_TRANSFORM = { x = 0, y = 0, scale = 1 }

-- A part's size in its own units for stacking and pinning (nil: not on the stage): what it
-- draws. Text parts measure as their text (a level pinned to the name meets the name's text),
-- aura rows as their whole grid, anything else as its frame (sized like the plate's).
function Options:EditorMeasure(key)
    local component = self.editorComponents and self.editorComponents[key]
    local position = self.editorLayout and self.editorLayout[key]
    if not component or not position or not self:IsEditorComponentRelevant(key) then return nil end
    local gridWidth, gridHeight, offset = self:EditorAuraGrid(key)
    if gridWidth then return gridWidth, gridHeight, nil, 0, offset end
    local textWidth, textHeight = self:EditorTextSize(key)
    if textWidth then return textWidth, textHeight end
    return component:GetWidth() or 0, component:GetHeight() or 0
end

-- A text part's drawn text size (name, level, guild, threat, tagged, values); nil otherwise.
local TEXT_PARTS = { name = true, level = true, guild = true, threat = true, tagged = true, targetName = true }
function Options:EditorTextSize(key)
    if not (TEXT_PARTS[key] or (type(key) == "string" and key:match("^value%d+$"))) then return nil end
    if key:match("^value%d+$") then
        local profile = PS.GetPlateProfileSettings(self.editorProfile)
        local slot = profile and profile.valueSlots and profile.valueSlots[key]
        if slot and slot.kind then return nil end
    end
    local component = self.editorComponents and self.editorComponents[key]
    local text = component and component.previewText
    if not (text and text.GetStringWidth and text.GetStringHeight) then return nil end
    -- As the plates measure text (Placement's SafeSize): the rendered string's width and its
    -- font's height, never the font string's frame.
    local width, height = text:GetStringWidth(), nil
    if text.GetFont then
        local _, size = text:GetFont()
        if type(size) == "number" and size > 0 then height = size end
    end
    height = height or text:GetStringHeight()
    if not width or width <= 0 or not height or height <= 0 then return nil end
    return width, height
end

-- How far a part's drawn content sits inside its frame on each side, in its own units: a text
-- part's frame is wider than its text (for easy grabbing); anything else draws its frame.
function Options:EditorContentInset(key)
    local component = self.editorComponents and self.editorComponents[key]
    local width, height = self:EditorTextSize(key)
    if not (component and width) then return 0, 0 end
    return ((component:GetWidth() or width) - width) / 2, ((component:GetHeight() or height) - height) / 2
end

-- An aura row's whole grid in its own units (Schema's AuraGridBox): width, height, and the
-- grid centre's offset from the row frame (its first line). nil for other parts.
function Options:EditorAuraGrid(key)
    if not AURA_ROWS[key] then return nil end
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    local aura = profile and profile.auraLayouts and profile.auraLayouts[key]
    if not aura then return nil end
    return Schema.AuraGridBox(aura)
end

-- Every entry's drawn transform, with stacks laid out from the preview's sizes. Worked out once
-- and kept until the layout copy is replaced or InvalidateEditorTransforms is called: after an
-- entry of the copy changes in place, and after the preview's sizes change (its refresh).
local NO_LAYOUT = {}
function Options:EditorTransforms()
    local layout = self.editorLayout or NO_LAYOUT
    if self.editorTransforms and self.editorTransformsLayout == layout then return self.editorTransforms end
    self.editorMeasureFunction = self.editorMeasureFunction or function(key) return self:EditorMeasure(key) end
    self.editorAbsentFunction = self.editorAbsentFunction or function(key) return self:IsEditorPartAbsent(key) end
    self.editorTransforms = Schema.LayoutTransforms(layout, self.editorMeasureFunction, self.editorAbsentFunction)
    self.editorTransformsLayout = layout
    return self.editorTransforms
end

-- Whether the preview shows nothing for key because it is off (its eye, its switch in Settings,
-- or a part this plate type does not use): what is pinned to it takes its place, as on the plates.
function Options:IsEditorPartAbsent(key)
    local component = self.editorComponents and self.editorComponents[key]
    return component ~= nil and not component.targetPreviewVisible
end

local function Showing(region)
    return region ~= nil and (not region.IsShown or region:IsShown() and true or false)
end

-- Whether key is on the stage at full strength: shown, not turned off or hidden by a rule, and
-- drawing something (not a faint sample, such as TAGGED on an untagged unit, nor an empty mark).
-- Only these make a group's or a family's box, and only these are pressed over other parts.
function Options:IsEditorPartDrawn(key)
    local component = self.editorComponents and self.editorComponents[key]
    if not (component and component.previewFitVisible and not component.previewRuleHidden) then return false end
    if not Showing(component) then return false end
    if component.previewBar or component.previewTexture or component.auraIcons then return true end
    if Showing(component.previewIcon) then return true end
    local text = component.previewText
    if not text then return true end
    local alpha = text.GetAlpha and text:GetAlpha() or 1
    return Showing(text) and (text.GetText == nil or (text:GetText() or "") ~= "") and alpha >= 0.99
end

-- The part key's pin meets in the preview (Schema's PinTarget), or nil when it is not pinned.
function Options:EditorPinTarget(key)
    self.editorAbsentFunction = self.editorAbsentFunction or function(part) return self:IsEditorPartAbsent(part) end
    return Schema.PinTarget(self.editorLayout or NO_LAYOUT, key, self.editorAbsentFunction)
end

function Options:InvalidateEditorTransforms()
    self.editorTransforms = nil
end

-- A fresh working copy of the edited layout (after Settings changed it).
function Options:ReloadEditorLayoutCopy()
    self.editorLayout = CopyEditorLayout(type(PS.GetLayout) == "function"
        and PS.GetLayout(self.editorProfile, self:CurrentEditorVariant()) or nil)
    self.editorTransforms = nil
    return self.editorLayout
end

-- Where key's centre is drawn now (a stacked part where its stack puts it).
function Options:EditorDrawnCentre(key)
    local position = self.editorLayout and self.editorLayout[key]
    if not position then return 0, 0 end
    local transform = self:EditorTransforms()[key]
    if not transform then return 0, 0 end
    return transform.x, transform.y
end

-- Whether key is laid out by its parent's stack (not free, and its parent stacks).
function Options:IsEditorStacked(key)
    local layout = self.editorLayout or {}
    local position = layout[key]
    local parent = position and position.parent and layout[position.parent]
    return parent and parent.stack ~= nil and not position.free and self:EditorMeasure(key) ~= nil or false
end

function Options:EditorPlacement(key)
    local layout = self.editorLayout or {}
    local position = type(key) == "string" and layout[key]
    if not position then return 0, 0, 1, 1 end
    local transforms = self:EditorTransforms()
    local parent = position.parent and layout[position.parent] and transforms[position.parent] or ROOT_TRANSFORM
    local originX, originY = parent.x, parent.y
    -- A pinned part's offset starts at its parent's edge (and its own facing edge), not the
    -- parent's centre: the origin moves out by that difference.
    local transform = position.attach and transforms[key]
    if transform then
        originX = transform.x - (position.x or 0) * parent.scale
        originY = transform.y - (position.y or 0) * parent.scale
    end
    return originX, originY, parent.scale, parent.scale * (position.scale or 1)
end

function Options:EditorDrawnScale(key)
    local _, _, _, drawn = self:EditorPlacement(key)
    return drawn
end

-- Where key's centre is drawn on the stage for the stored offset (x, y).
function Options:EditorVisualCentre(key, x, y)
    local originX, originY, scale = self:EditorPlacement(key)
    return originX + x * scale, originY + y * scale
end

-- The stored offset that draws key's centre at (cx, cy).
function Options:EditorStoredOffset(key, cx, cy)
    local originX, originY, scale = self:EditorPlacement(key)
    return (cx - originX) / scale, (cy - originY) / scale
end

-- Whether key sits somewhere under ancestor in the tree.
function Options:IsEditorUnder(key, ancestor)
    local layout = self.editorLayout or {}
    local current, depth = layout[key] and layout[key].parent, 0
    while current and depth <= Schema.MAX_DEPTH do
        if current == ancestor then return true end
        current, depth = layout[current] and layout[current].parent, depth + 1
    end
    return false
end

-- A tree node's name: a group's own, or the part's label.
function Options:EditorNodeLabel(key)
    local position = self.editorLayout and self.editorLayout[key]
    if key:match("^group%.%d+$") then return position and position.name or L["Group"] end
    return self:EditorComponentLabel(key)
end

-- After a resize step, moves the part so the side or corner opposite the dragged handle stays put.
function Options:KeepEditorResizeEdge()
    local resize = self.editorResize
    local key = resize and resize.key
    local position = key and self.editorLayout and self.editorLayout[key]
    if not position then return end
    local _, _, hw, hh = self:EditorComponentBounds(key)
    if not hw then return end
    local x, y = self:EditorStoredOffset(key, resize.cx + resize.sx * (hw - resize.hw),
        resize.cy + resize.sy * (hh - resize.hh))
    x = Schema.Bounded(Schema.layoutRanges.x, math.floor(x + 0.5))
    y = Schema.Bounded(Schema.layoutRanges.y, math.floor(y + 0.5))
    if x == position.x and y == position.y then return end
    PS.SetComponentPosition(key, x, y, self.editorProfile, self:CurrentEditorVariant())
    -- The part and everything laid out from it; the inspector follows when the handle is let go.
    self:ReloadEditorLayoutCopy()
    self:RefreshEditorLayout()
end

-- A group's drawn bounds (centre and half size) from the parts under it drawn at full strength
-- (IsEditorPartDrawn: a hidden target's name or an unlit TAGGED does not stretch it), or from
-- every part on the stage when none is; nil when nothing under it is on the stage.
function Options:EditorGroupBounds(groupKey)
    local left, right, bottom, top
    for pass = 1, 2 do
        for key in pairs(self.editorLayout or {}) do
            if self:IsEditorUnder(key, groupKey) and (pass == 2 or self:IsEditorPartDrawn(key))
                and self:EditorComponentBounds(key) then
                local x, y, hw, hh = self:EditorSelectionBox(key)
                if x then
                    left, right = math.min(left or x - hw, x - hw), math.max(right or x + hw, x + hw)
                    bottom, top = math.min(bottom or y - hh, y - hh), math.max(top or y + hh, y + hh)
                end
            end
        end
        if left then break end
    end
    if not left then return nil end
    return (left + right) / 2, (bottom + top) / 2, (right - left) / 2, (top - bottom) / 2
end

-- Scales a group around a point of the stage (default: its centre), which stays where it is:
-- the group's offset moves so that point keeps its place as everything under it grows or shrinks.
-- light (a corner handle's step): only the preview's layout follows.
function Options:SetEditorGroupScale(groupKey, scale, pivotX, pivotY, start, light)
    local group = self.editorLayout and self.editorLayout[groupKey]
    if not group then return false end
    scale = Schema.ComponentScale(scale)
    start = start or { scale = group.scale or 1, x = group.x, y = group.y }
    local originX, originY, parentScale = self:EditorPlacement(groupKey)
    local drawnX, drawnY = originX + start.x * parentScale, originY + start.y * parentScale
    if not pivotX then
        local cx, cy = self:EditorGroupBounds(groupKey)
        pivotX, pivotY = cx or drawnX, cy or drawnY
    end
    local ratio = scale / start.scale
    local newX, newY = pivotX - ratio * (pivotX - drawnX), pivotY - ratio * (pivotY - drawnY)
    local x = math.floor((newX - originX) / parentScale + 0.5)
    local y = math.floor((newY - originY) / parentScale + 0.5)
    if not PS.SetComponentGroupScale(groupKey, scale, x, y, self.editorProfile, self:CurrentEditorVariant()) then
        return false
    end
    if light then
        -- With the group selected, the layout refresh moves its handles too.
        self:ReloadEditorLayoutCopy()
        self:RefreshEditorLayout()
    else
        self:ReloadEditorLayout()
        self:UpdateEditorSelectionHandles()
    end
    return true
end

-- Writes one aura-row field when it changed; true if it did.
local function WriteAuraField(self, key, current, field, value)
    return value ~= nil and current[field] ~= value and PS.SetPlateAuraLayout(self.editorProfile, key, field, value) and true
        or false
end

function Options:UpdateEditorResize()
    local resize = self.editorResize
    if not resize or type(GetCursorPosition) ~= "function" then return end
    local cursorX, cursorY = GetCursorPosition()
    local stageScale = self.editorPreviewStage:GetEffectiveScale()
    if type(cursorX) ~= "number" or not stageScale or stageScale <= 0 then return end
    -- How far the dragged side has moved outwards, in stage units.
    local dx = (cursorX - resize.cursorX) / stageScale * resize.sx
    local dy = (cursorY - resize.cursorY) / stageScale * resize.sy
    local key, start = resize.key, resize.start
    if resize.group then
        -- A group scales evenly from its corners, the opposite corner staying put.
        local grow = math.max((resize.hw * 2 + dx) / (resize.hw * 2), (resize.hh * 2 + dy) / (resize.hh * 2))
        local target = Schema.ComponentScale(math.floor(start.scale * grow * 20 + 0.5) / 20)
        if target ~= (self.editorLayout[resize.group].scale or 1) then
            resize.changed = self:SetEditorGroupScale(resize.group, target, resize.cx - resize.sx * resize.hw,
                resize.cy - resize.sy * resize.hh, start, true) or resize.changed
        end
        return
    end
    local profile = PS.GetPlateProfileSettings(self.editorProfile)
    local changed = false
    -- Each step writes only what changed and redraws the preview; the rest follows on letting go.
    local bar = BAR_SIZES[key]
    if bar then
        -- Bar sizes are in plate units, drawn at the plate's scale and the part's own.
        local unit = start.scale * (profile and profile.scale or 1)
        for axis = 1, 2 do
            local size, delta = bar.width, resize.sx ~= 0 and dx
            if axis == 2 then size, delta = bar.height, resize.sy ~= 0 and dy end
            if delta then
                local value = Stepped(size, start[size.key] + delta / unit)
                if profile and profile[size.key] ~= value then
                    PS.SetPlateProfileOption(self.editorProfile, size.key, value)
                    changed = true
                end
            end
        end
        if changed then self:RefreshEditorPreview() end
    elseif start.aura then
        -- An aura row is a grid: its sides set icons per line and lines, its corners icon size.
        local aura = start.aura
        local pitch = (aura.size + aura.spacing) * start.scale
        local lines = math.max(1, math.ceil(aura.count / math.max(1, aura.columns)))
        local size, columns, count
        if resize.sx ~= 0 and resize.sy ~= 0 then
            local grow = math.max((resize.hw * 2 + dx) / (resize.hw * 2), (resize.hh * 2 + dy) / (resize.hh * 2))
            size = Clamp(AURA_RANGES.size, aura.size * grow)
        elseif resize.sx ~= 0 then
            columns = Clamp(AURA_RANGES.columns, (resize.hw * 2 + dx + aura.spacing * start.scale) / pitch)
            count = math.min(AURA_RANGES.count[2], columns * lines)
        else
            local rows = Clamp(AURA_RANGES.count, (resize.hh * 2 + dy + aura.spacing * start.scale) / pitch)
            count = Clamp(AURA_RANGES.count, aura.columns * rows)
        end
        local current = profile and profile.auraLayouts and profile.auraLayouts[key] or NO_LAYOUT
        changed = WriteAuraField(self, key, current, "size", size)
        changed = WriteAuraField(self, key, current, "columns", columns) or changed
        changed = WriteAuraField(self, key, current, "count", count) or changed
        if changed then self:RefreshEditorPreview() end
    else
        local grow = math.max(resize.sx ~= 0 and (resize.hw * 2 + dx) / (resize.hw * 2) or 0,
            resize.sy ~= 0 and (resize.hh * 2 + dy) / (resize.hh * 2) or 0)
        local target = Schema.ComponentScale(math.floor(start.ownScale * grow * 20 + 0.5) / 20)
        if target ~= (self.editorLayout[key].scale or 1)
            and PS.SetComponentScale(key, target, self.editorProfile, self:CurrentEditorVariant()) then
            self:ReloadEditorLayoutCopy()
            self:RefreshEditorLayout()
            changed = true
        end
    end
    if changed then
        resize.changed = true
        self:KeepEditorResizeEdge()
    end
end

function Options:StartEditorResize(handle)
    if type(GetCursorPosition) ~= "function" then return end
    local key = self.selectedComponent
    local groupKey = not key and self.editorSelectedGroup
    local cursorX, cursorY = GetCursorPosition()
    if groupKey then
        local group = self.editorLayout and self.editorLayout[groupKey]
        local cx, cy, hw, hh = self:EditorGroupBounds(groupKey)
        if not group or not cx then return end
        self.editorResize = { group = groupKey, sx = handle.sx, sy = handle.sy, cursorX = cursorX, cursorY = cursorY,
            cx = cx, cy = cy, hw = math.max(1, hw), hh = math.max(1, hh),
            start = { scale = group.scale or 1, x = group.x, y = group.y } }
        handle:SetScript("OnUpdate", function() self:UpdateEditorResize() end)
        return
    end
    local position = key and self.editorLayout and self.editorLayout[key]
    if not position then return end
    local cx, cy, hw, hh = self:EditorComponentBounds(key)
    if not cx then return end
    local profile = PS.GetPlateProfileSettings(self.editorProfile) or {}
    local aura = AURA_ROWS[key] and profile.auraLayouts and profile.auraLayouts[key]
    local start = BarSizes(profile)
    start.scale, start.ownScale = self:EditorDrawnScale(key), position.scale or 1
    start.aura = aura and { count = aura.count, columns = aura.columns, size = aura.size, spacing = aura.spacing or 0 }
    self.editorResize = { key = key, sx = handle.sx, sy = handle.sy, cursorX = cursorX, cursorY = cursorY,
        cx = cx, cy = cy, hw = math.max(1, hw), hh = math.max(1, hh), start = start }
    handle:SetScript("OnUpdate", function() self:UpdateEditorResize() end)
end

function Options:StopEditorResize(handle)
    local resize = self.editorResize
    if resize then self:UpdateEditorResize() end
    self.editorResize = nil
    handle:SetScript("OnUpdate", nil)
    -- The steps redrew only the preview: now the controls and the inspector.
    if resize and resize.changed then self:Refresh(true) end
end

-- A handle's look: gold with a dark rim, lighter and larger under the pointer, orange while held.
function Options:PaintEditorHandle(handle)
    local state = handle.pressed and "pressed" or handle.hover and "hover" or "normal"
    local size = (handle.baseSize or HANDLE_SIZE) * (state == "normal" and 1 or 1.3)
    if self:StudioAccess().highContrast then size = size * 1.25 end
    local zoom = self.editorPreviewZoom or 1
    local colour = HANDLE_COLOURS[state]
    handle.state = state
    handle.art:SetColorTexture(colour[1], colour[2], colour[3], 1)
    handle.art:SetSize(size, size)
    handle.border:SetSize(size + 4 / zoom, size + 4 / zoom)
end

-- A selected text part's box: this much (stage px) outside its drawn text on each side.
local SELECTION_PADDING = { 3, 2 }

local function Edges(region)
    if not (region and region.GetLeft and region.GetRight) then return nil end
    local ok, left, right = pcall(region.GetLeft, region)
    if ok then ok, right = pcall(region.GetRight, region) end
    if ok and type(left) == "number" and type(right) == "number" then return left, right end
    return nil
end

-- Where a text part's drawn string is centred across its frame: the offset from the frame's
-- centre, in the frame's units. Its anchor and JustifyH place it (TAGGED is pinned by its left
-- edge, and a string can be wider than its frame); 0 until the client has laid it out.
local function TextCentreOffset(component, text, width)
    local left, right = Edges(text)
    local frameLeft, frameRight = Edges(component)
    if not (left and frameLeft) then return 0 end
    local centre = (left + right) / 2
    local justify = text.GetJustifyH and text:GetJustifyH()
    if right - left > width then
        if justify == "LEFT" then centre = left + width / 2 elseif justify == "RIGHT" then centre = right - width / 2 end
    end
    return centre - (frameLeft + frameRight) / 2
end

-- The selection box on the stage (centre, half size) and its centre's offset from the part's
-- frame (stage units). A text part's box hugs its drawn string: the string's width and the
-- larger of its font's size and its measured height (an outline draws past the font size), plus
-- the padding. Anything else is its drawn bounds (a bar, an icon, an aura row's grid).
function Options:EditorSelectionBox(key)
    local width, height = self:EditorTextSize(key)
    if not width then
        local cx, cy, hw, hh = self:EditorComponentBounds(key)
        if not cx then return nil end
        return cx, cy, hw, hh, 0
    end
    local cx, cy = self:EditorDrawnCentre(key)
    local component = self.editorComponents[key]
    local text = component.previewText
    local measured = text.GetStringHeight and text:GetStringHeight()
    if type(measured) == "number" and measured > height then height = measured end
    local scale = self:EditorDrawnScale(key)
    local dx = TextCentreOffset(component, text, width) * scale
    return cx + dx, cy, width * scale / 2 + SELECTION_PADDING[1], height * scale / 2 + SELECTION_PADDING[2], dx
end

-- A faint outline (no handles) around the selected part and everything drawn under it (what is
-- pinned or stacked to it), so it shows what moves with the part. Hidden unless that reaches
-- past the selection box by more than its padding: a part with nothing drawn under it (only
-- turned-off or unlit parts) has the one box.
function Options:EditorFamilyBounds(key)
    local cx, cy, hw, hh = self:EditorSelectionBox(key)
    if not cx then return nil end
    local ownLeft, ownRight, ownBottom, ownTop = cx - hw, cx + hw, cy - hh, cy + hh
    local left, right, bottom, top = ownLeft, ownRight, ownBottom, ownTop
    for other in pairs(self.editorComponents or {}) do
        if other ~= key and self:IsEditorUnder(other, key) and self:IsEditorPartDrawn(other) then
            local x, y, halfWidth, halfHeight = self:EditorSelectionBox(other)
            if x then
                left, right = math.min(left, x - halfWidth), math.max(right, x + halfWidth)
                bottom, top = math.min(bottom, y - halfHeight), math.max(top, y + halfHeight)
            end
        end
    end
    local padX, padY = SELECTION_PADDING[1], SELECTION_PADDING[2]
    if ownLeft - left <= padX and right - ownRight <= padX and ownBottom - bottom <= padY and top - ownTop <= padY then
        return nil
    end
    return (left + right) / 2, (bottom + top) / 2, (right - left) / 2, (top - bottom) / 2
end

function Options:UpdateEditorFamilyOutline(key)
    local stage = self.editorPreviewStage
    if not stage then return end
    local outline = self.editorFamilyOutline
    local cx, cy, hw, hh
    if key then cx, cy, hw, hh = self:EditorFamilyBounds(key) end
    if not cx then
        if outline then outline:Hide() end
        return
    end
    if not outline then
        outline = CreateFrame("Frame", nil, stage)
        outline.edges = {}
        for index, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local edge = outline:CreateTexture(nil, "OVERLAY")
            edge:SetPoint(side[1], outline, side[1], 0, 0)
            edge:SetPoint(side[2], outline, side[2], 0, 0)
            edge.horizontal = index <= 2
            outline.edges[index] = edge
        end
        self.editorFamilyOutline = outline
    end
    local width = 1 / (self.editorPreviewZoom or 1)
    for _, edge in ipairs(outline.edges) do
        if edge.horizontal then edge:SetHeight(width) else edge:SetWidth(width) end
        edge:SetColorTexture(1, 0.8, 0.16, 0.35)
    end
    outline:ClearAllPoints()
    outline:SetPoint("CENTER", stage, "CENTER", cx, cy)
    outline:SetSize(hw * 2 + 4, hh * 2 + 4)
    outline:SetFrameLevel(stage:GetFrameLevel() + 59)
    outline:Show()
end

function Options:UpdateEditorSelectionHandles()
    local stage = self.editorPreviewStage
    if not stage then return end
    local handles = self.editorSelectionHandles
    if not handles then
        handles = CreateFrame("Frame", nil, stage)
        -- The handles also live in their own list: some clients keep a frame's regions in its
        -- array part, so the frame itself is not iterated.
        handles.list = {}
        -- The selection outline, drawn with the handles above every part (so an overlapping
        -- row never hides it).
        handles.edges = {}
        for index, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local edge = handles:CreateTexture(nil, "OVERLAY", nil, 0)
            edge:SetColorTexture(1, 0.80, 0.16, 0.95)
            edge:SetPoint(side[1], handles, side[1], 0, 0)
            edge:SetPoint(side[2], handles, side[2], 0, 0)
            edge.horizontal = index <= 2
            handles.edges[index] = edge
        end
        for index, spec in ipairs(HANDLE_POINTS) do
            local handle = CreateFrame("Button", nil, handles)
            handle.point, handle.sx, handle.sy = spec[1], spec[2], spec[3]
            handle.border = handle:CreateTexture(nil, "OVERLAY", nil, 1)
            handle.border:SetPoint("CENTER")
            handle.border:SetColorTexture(0.10, 0.06, 0.02, 0.95)
            handle.art = handle:CreateTexture(nil, "OVERLAY", nil, 2)
            handle.art:SetPoint("CENTER")
            handle:EnableMouse(true)
            handle:SetScript("OnEnter", function(instance)
                instance.hover = true
                self:PaintEditorHandle(instance)
            end)
            handle:SetScript("OnLeave", function(instance)
                instance.hover = false
                self:PaintEditorHandle(instance)
            end)
            handle:SetScript("OnMouseDown", function(instance)
                instance.pressed = true
                self:PaintEditorHandle(instance)
                self:StartEditorResize(instance)
            end)
            handle:SetScript("OnMouseUp", function(instance)
                instance.pressed = false
                self:PaintEditorHandle(instance)
                self:StopEditorResize(instance)
            end)
            handle:SetScript("OnHide", function(instance)
                instance.pressed, instance.hover = false, false
                self:StopEditorResize(instance)
            end)
            handles[index] = handle
            handles.list[index] = handle
        end
        self.editorSelectionHandles = handles
    end
    local key = self.selectedComponent
    local groupKey = not key and self.editorSelectedGroup
    local target
    if groupKey then
        -- A selected group's box spans its shown members; its corners scale the group.
        local cx, cy, hw, hh = self:EditorGroupBounds(groupKey)
        if cx then
            self.editorGroupBox = self.editorGroupBox or CreateFrame("Frame", nil, stage)
            target = self.editorGroupBox
            target:ClearAllPoints()
            target:SetPoint("CENTER", stage, "CENTER", cx, cy)
            target:SetSize(math.max(1, hw * 2), math.max(1, hh * 2))
            target:SetFrameLevel(stage:GetFrameLevel() + 40)
        end
    else
        local component = key and self.editorComponents and self.editorComponents[key]
        local position = component and self.editorLayout and self.editorLayout[key]
        if component and position and position.visible ~= false and component:IsShown() then target = component end
    end
    if not target then
        handles:Hide()
        self:UpdateEditorFamilyOutline(nil)
        return
    end
    handles:ClearAllPoints()
    -- The box is tight to the part's own drawn rect: a text part's drawn string (EditorSelectionBox),
    -- centred on the string rather than its frame; anything else its frame (an icon, a bar, a row).
    local textWidth = not groupKey and self:EditorTextSize(key)
    local boxWidth, boxHeight, boxOffset
    if textWidth then boxWidth, boxHeight, boxOffset = select(3, self:EditorSelectionBox(key)) end
    if boxWidth then
        handles:SetPoint("CENTER", target, "CENTER", boxOffset, 0)
        handles:SetSize(boxWidth * 2, boxHeight * 2)
    else
        handles:SetAllPoints(target)
    end
    if groupKey then self:RefreshEditorGroupOutlines() end
    self:UpdateEditorFamilyOutline(not groupKey and key or nil)
    -- Above every part on the stage.
    handles:SetFrameLevel(stage:GetFrameLevel() + 60)
    local zoom = self.editorPreviewZoom or 1
    -- The handles belong to the stage (not the part), so only the zoom is undone.
    local size = HANDLE_SIZE / zoom
    local highContrast = self:StudioAccess().highContrast
    local outline = (highContrast and 3 or OUTLINE_WIDTH) / zoom
    for _, edge in ipairs(handles.edges) do
        if edge.horizontal then edge:SetHeight(outline) else edge:SetWidth(outline) end
        edge:SetColorTexture(1, highContrast and 0.92 or 0.80, highContrast and 0 or 0.16, highContrast and 1 or 0.95)
    end
    local bar = BAR_SIZES[key]
    for _, handle in ipairs(handles.list) do
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", handles, handle.point, 0, 0)
        handle:SetSize(size * HANDLE_HIT / HANDLE_SIZE, size * HANDLE_HIT / HANDLE_SIZE)
        handle.baseSize = size
        self:PaintEditorHandle(handle)
        handle:SetFrameLevel(handles:GetFrameLevel() + 1)
        -- Bars offer the handles that change one of their sizes; aura rows all eight; anything
        -- else its corners, as it scales evenly.
        local corner = handle.sx ~= 0 and handle.sy ~= 0
        local usable
        if groupKey then
            usable = corner
        elseif bar then
            usable = (handle.sx ~= 0 and handle.sy == 0 and bar.width) or (handle.sy ~= 0 and handle.sx == 0 and bar.height)
        elseif AURA_ROWS[key] then
            usable = true
        else
            usable = corner
        end
        handle:SetShown(usable and true or false)
    end
    handles:Show()
end

function Options:SetEditorComponentVisibility(key, visible)
    if not self:IsEditorComponentRelevant(key) then return false end
    if not (self.editorLayout and self.editorLayout[key]) then return false end
    WritePartVisibility(self, key, visible and true or false)
    -- The refresh redraws the tree and the inspector; clicking another part's eye selects it.
    self:ReloadEditorLayout()
    if self.selectedComponent ~= key then self:SelectEditorComponent(key) end
    return true
end

function Options:PositionEditorComponent(key)
    local component = self.editorComponents and self.editorComponents[key]
    local position = self.editorLayout and self.editorLayout[key]
    if not component or not position then return end
    component:ClearAllPoints()
    local originX, originY, positionScale, scale = self:EditorPlacement(key)
    component:SetScale(scale)
    -- Pinned to a parent's edge: anchored to the parent's drawn text or frame, as on the plates,
    -- so it meets the name exactly however wide it renders.
    local edge = position.attach and Schema.ATTACH_EDGES[position.attach]
    local pinTarget = edge and self:EditorPinDepth(key) and self:EditorPinTarget(key)
    local parentComponent = pinTarget and self.editorComponents and self.editorComponents[pinTarget]
    if parentComponent then
        local _, _, parentScale = self:EditorPlacement(key)
        -- Parts meet with what they draw (a text's measured string, not its wider frame), as on
        -- the plates: both frames' insets are taken off, the parent's in its own drawn scale.
        local ownX, ownY = self:EditorContentInset(key)
        local targetX, targetY = self:EditorContentInset(pinTarget)
        local targetScale = self:EditorDrawnScale(pinTarget) / scale
        -- The parent may still hang off this part from an earlier layout (a caller placing one
        -- part alone): the client refuses that anchor, so the part falls back to its place below.
        if pcall(component.SetPoint, component, edge[3], parentComponent, edge[4],
            ((position.x or 0) * parentScale) / scale - edge[1] * (ownX + targetX * targetScale),
            ((position.y or 0) * parentScale) / scale - edge[2] * (ownY + targetY * targetScale)) then
            return
        end
        component:ClearAllPoints()
    end
    -- Where the hierarchy (and its stacks) draw it; the part's own offsets are in its drawn units.
    local transform = self:EditorTransforms()[key]
    local x = transform and transform.x or originX + position.x * positionScale
    local y = transform and transform.y or originY + position.y * positionScale
    component:SetPoint("CENTER", self.editorPreviewStage or self.editorCanvas, "CENTER", x / scale, y / scale)
end

-- This layout's groups, in tree order: { key, name, members (what sits directly under it and is
-- shown, in order), total (parts under it at any depth, used or not by this plate type) }.
function Options:EditorCustomGroups(settings)
    local groups, layout = {}, self.editorLayout or {}
    local tree, counts = self:EditorTreeIndex(settings), self:EditorTreeCounts(settings)
    for key, position in pairs(layout) do
        if key:match("^group%.%d+$") then
            groups[#groups + 1] = { key = key, name = position.name or L["Group"], order = position.order or 0,
                members = self:EditorTreeChildren(key, settings, tree), total = counts.all[key] or 0 }
        end
    end
    table.sort(groups, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        return left.key < right.key
    end)
    local byKey = {}
    for _, group in ipairs(groups) do byKey[group.key] = group end
    return groups, byKey
end

-- Who sits directly under whom in the tree: parent key (TREE_ROOT for the top level) -> its
-- children in order. The tree shows groups and the parts this plate type uses; a part under one
-- it does not use shows at the top level.
local TREE_ROOT, NO_CHILDREN = {}, {}
function Options:EditorTreeIndex(settings)
    local layout, rank, shown, tree = self.editorLayout or {}, {}, {}, {}
    for position, key in ipairs(editorOrder) do rank[key] = position end
    local buttons = self.editorComponentButtons
    for key, position in pairs(layout) do
        if type(position) == "table" and (key:match("^group%.%d+$")
            or (buttons and buttons[key] ~= nil and self:IsEditorComponentRelevant(key, settings))) then
            shown[key] = true
        end
    end
    for key in pairs(shown) do
        local parent = layout[key].parent
        if not (parent and shown[parent]) then parent = TREE_ROOT end
        tree[parent] = tree[parent] or {}
        table.insert(tree[parent], key)
    end
    local function Before(left, right)
        local a, b = layout[left].order or 99, layout[right].order or 99
        if a ~= b then return a < b end
        local ra, rb = rank[left] or 999, rank[right] or 999
        if ra ~= rb then return ra < rb end
        return left < right
    end
    for _, children in pairs(tree) do table.sort(children, Before) end
    return tree
end

-- What sits directly under parentKey (nil: the top level), in order; tree is an
-- EditorTreeIndex to read from (one is made when not given). The list must not be changed.
function Options:EditorTreeChildren(parentKey, settings, tree)
    tree = tree or self:EditorTreeIndex(settings)
    return tree[parentKey == nil and TREE_ROOT or parentKey] or NO_CHILDREN
end

-- Per ancestor key: how many parts sit under it at any depth (all), how many this plate type
-- uses (used), and how many of those are shown (shown, as the eye shows them).
function Options:EditorTreeCounts(settings)
    local layout = self.editorLayout or {}
    local counts = { all = {}, used = {}, shown = {} }
    for key, position in pairs(layout) do
        if type(position) == "table" and not key:match("^group%.%d+$") then
            local used = self:IsEditorComponentRelevant(key, settings)
            local visible = used and self:IsEditorPartShown(key, settings)
            local current, depth = position.parent, 0
            while current and layout[current] and depth <= Schema.MAX_DEPTH do
                counts.all[current] = (counts.all[current] or 0) + 1
                if used then counts.used[current] = (counts.used[current] or 0) + 1 end
                if visible then counts.shown[current] = (counts.shown[current] or 0) + 1 end
                current, depth = layout[current].parent, depth + 1
            end
        end
    end
    return counts
end

local function Variant(self) return self:CurrentEditorVariant() end

-- A fresh copy of the layout, then the preview (which lays it out), the tree and the inspector.
function Options:ReloadEditorLayout()
    self:ReloadEditorLayoutCopy()
    self:RefreshEditorAppearance(PS.GetSettings())
end

function Options:AddEditorGroup()
    local key = PS.CreateComponentGroup(nil, self.editorProfile, Variant(self))
    if not key then return false end
    self:ReloadEditorLayout()
    self:SelectEditorGroup(key)
    return key
end

-- A selected group: the inspector shows it, and dragging any member in the preview moves them all.
function Options:SelectEditorGroup(groupKey)
    if not (self.editorLayout and self.editorLayout[groupKey]) then return false end
    self.editorSelectedGroup = groupKey
    self:SelectEditorComponent(nil)
    self:RefreshEditorGroupOutlines()
    return true
end

function Options:RefreshEditorGroupOutlines()
    local groupKey = self.editorSelectedGroup
    for key, component in pairs(self.editorComponents or {}) do
        if component.SetBackdropBorderColor and key ~= "quest" then
            -- Only drawn members: a ghost's box would show faint where nothing is drawn.
            local member = groupKey and self:IsEditorUnder(key, groupKey) and self:IsEditorPartDrawn(key)
            if member then component:SetBackdropBorderColor(1, 0.72, 0.12, 0.9)
            elseif key ~= self.selectedComponent then component:SetBackdropBorderColor(0, 0, 0, 0) end
        end
    end
end

-- The layout reloads below refresh the tree and the inspector with the preview.
function Options:SetEditorComponentGroup(key, groupKey)
    if not PS.SetComponentGroup(key, groupKey, self.editorProfile, Variant(self)) then return false end
    self:ReloadEditorLayout()
    self:RefreshEditorGroupOutlines()
    return true
end

function Options:SetEditorGroupOffset(groupKey, x, y)
    if not PS.SetComponentGroupOffset(groupKey, x, y, self.editorProfile, Variant(self)) then return false end
    self:ReloadEditorLayout()
    return true
end

function Options:RenameEditorGroup(groupKey, name)
    if not PS.RenameComponentGroup(groupKey, name, self.editorProfile, Variant(self)) then return false end
    self:ReloadEditorLayout()
    return true
end

-- Moves groupKey to targetKey's place in the tree (after it when after is true).
function Options:MoveEditorGroupTo(groupKey, targetKey, after)
    if not PS.MoveComponentGroupTo(groupKey, targetKey, after, self.editorProfile, Variant(self)) then return false end
    self:ReloadEditorLayout()
    return true
end

-- Moves a node under parentKey (nil: the top level), before beforeKey (nil: last).
function Options:MoveEditorNode(key, parentKey, beforeKey)
    self:SupplyEditorMeasure()
    if not PS.SetComponentParent(key, parentKey, beforeKey, self.editorProfile, Variant(self)) then return false end
    self:ReloadEditorLayout()
    self:RefreshEditorGroupOutlines()
    self:UpdateEditorSelectionHandles()
    return true
end

function Options:DeleteEditorGroup(groupKey)
    if not PS.DeleteComponentGroup(groupKey, self.editorProfile, Variant(self)) then return false end
    self.editorSelectedGroup = nil
    self:ReloadEditorLayout()
    self:SelectEditorComponent("health")
    return true
end

function Options:ConfirmDeleteEditorGroup(groupKey)
    local group = self.editorLayout and self.editorLayout[groupKey]
    if not group then return nil end
    return self:ConfirmStudioAction(string.format(L["Delete the group %s? Its parts stay where they are."], group.name or ""),
        L["Delete"], function() self:DeleteEditorGroup(groupKey) end)
end

-- Tree drag and drop (EditorTreeDropPlace says where a drop lands). A label follows the pointer
-- and a gold line (or a lit heading) shows where the drop will land.
function Options:EditorTreeRowUnderCursor()
    local cursorY = type(GetCursorPosition) == "function" and select(2, GetCursorPosition())
    for _, row in ipairs(self.editorListRows or {}) do
        local frame = row.frame
        if row.key and frame:IsShown() and frame.IsMouseOver and frame:IsMouseOver() then
            -- How far down the row the pointer is, 0 (top) to 1 (bottom).
            local fraction = 0.5
            if cursorY and frame.GetTop and frame.GetBottom and frame.GetEffectiveScale then
                local top, bottom, scale = frame:GetTop(), frame:GetBottom(), frame:GetEffectiveScale()
                if top and bottom and scale and scale > 0 and top > bottom then
                    fraction = math.max(0, math.min(1, (top - cursorY / scale) / (top - bottom)))
                end
            end
            return row, fraction
        end
    end
    return nil
end

-- Where dropping over row lands, by how far down it the pointer is (like a scene hierarchy): the
-- top quarter puts the node before that row, the bottom quarter after it (same parent), the
-- middle under it (last child). Never under the dragged node itself or one of its children.
-- Returns { parent, before, line (the row top the line sits on), indent, into (the row) }.
function Options:EditorTreeDropPlace(drag, row, fraction)
    if not drag or not row or not row.key then return nil end
    local key = drag.key
    if row.key == key or self:IsEditorUnder(row.key, key) then return nil end
    fraction = fraction or 0.5
    if fraction > 0.25 and fraction < 0.75 then
        return { parent = row.key, into = row }
    end
    local indent = (row.depth or 0) * TREE_INDENT
    if fraction <= 0.25 then
        return { parent = row.parentKey, before = row.key, line = row.top, indent = indent }
    end
    -- After row: before its next sibling, or last under its parent.
    local siblings = self:EditorTreeChildren(row.parentKey)
    local before
    for index, sibling in ipairs(siblings) do
        if sibling == row.key then before = siblings[index + 1] break end
    end
    if before == key then return nil end
    local rows, lineTop = self.editorListRows or {}, row.top + row.height + 1
    -- The line goes below the row's own children, if they are shown.
    for _, candidate in ipairs(rows) do
        if candidate.key and self:IsEditorUnder(candidate.key, row.key) then lineTop = candidate.top + candidate.height + 1 end
    end
    return { parent = row.parentKey, before = before, line = lineTop, indent = indent }
end

function Options:ShowEditorTreeDrop(place)
    local into = place and place.into
    for _, header in ipairs(self.editorTreeHeaders or {}) do
        if header.dropTarget then header.dropTarget:SetShown(into ~= nil and into.frame == header) end
    end
    for _, button in pairs(self.editorComponentButtons or {}) do
        if button.hoverArt then button.hoverArt:SetShown(into ~= nil and into.frame == button) end
    end
    local line = self.editorTreeDropLine
    if not line and self.editorListContent then
        line = self.editorListContent:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetColorTexture(1, 0.78, 0.25, 0.95)
        self.editorTreeDropLine = line
    end
    if not line then return end
    line:SetShown(place ~= nil and place.line ~= nil)
    if place and place.line then
        local indent = (place.indent or 0) + 8
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", self.editorListContent, "TOPLEFT", indent, -place.line + 1)
        local access = self:StudioAccess()
        line:SetSize(math.max(1, self.editorListContent:GetWidth() - indent),
            (access.colourBlind or access.highContrast) and 3 or 2)
    end
end

function Options:StartEditorTreeDrag(kind, key)
    self.editorTreeDrag = { kind = kind, key = key }
    local editor = self.editor
    if editor and not self.editorTreeGhost then
        local ghost = CreateFrame("Frame", nil, editor)
        ghost:SetSize(1, 1)
        ghost:SetFrameLevel(editor:GetFrameLevel() + 60)
        ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ghost.text:SetPoint("LEFT", ghost, "LEFT", 0, 0)
        ghost.text:SetTextColor(1, 0.86, 0.45)
        self.editorTreeGhost = ghost
    end
    local ghost = self.editorTreeGhost
    if ghost then
        ghost.text:SetText(self:EditorNodeLabel(key))
        ghost:Show()
    end
    local list = self.editorList
    if list then
        list:SetScript("OnUpdate", function()
            local row, fraction = self:EditorTreeRowUnderCursor()
            self:ShowEditorTreeDrop(self:EditorTreeDropPlace(self.editorTreeDrag, row, fraction))
            if ghost and type(GetCursorPosition) == "function" and editor.GetLeft and editor:GetLeft() then
                local x, y = GetCursorPosition()
                local scale = editor:GetEffectiveScale()
                ghost:ClearAllPoints()
                ghost:SetPoint("LEFT", editor, "BOTTOMLEFT", x / scale - editor:GetLeft() + 16, y / scale - editor:GetBottom())
            end
        end)
    end
end

function Options:StopEditorTreeDrag()
    local drag = self.editorTreeDrag
    self.editorTreeDrag = nil
    if self.editorList then self.editorList:SetScript("OnUpdate", nil) end
    if self.editorTreeGhost then self.editorTreeGhost:Hide() end
    local row, fraction = self:EditorTreeRowUnderCursor()
    local place = self:EditorTreeDropPlace(drag, row, fraction)
    self:ShowEditorTreeDrop(nil)
    if not place then return false end
    return self:MoveEditorNode(drag.key, place.parent, place.before)
end

function Options:UpdateEditorGrid()
    local grid, canvas, stage = self.editorGrid, self.editorCanvas, self.editorPreviewStage
    if not grid or not canvas or not stage then return end
    local zoom = self.editorPreviewZoom or 1
    for _, entry in ipairs(grid.vertical) do
        local line = entry.texture
        line:ClearAllPoints()
        line:SetPoint("CENTER", stage, "CENTER", entry.offset, 0)
        line:SetSize((entry.offset == 0 and 2 or 1) / zoom, (canvas:GetHeight() - 92) / zoom)
    end
    for _, entry in ipairs(grid.horizontal) do
        local line = entry.texture
        line:ClearAllPoints()
        line:SetPoint("CENTER", stage, "CENTER", 0, entry.offset)
        line:SetSize((canvas:GetWidth() - 22) / zoom, (entry.offset == 0 and 2 or 1) / zoom)
    end
end

-- The stage is scaled by the zoom, so its anchor offset is in stage units: the canvas point
-- shown at the centre of the preview. Zooming keeps that point; panning moves it.
function Options:SetEditorPreviewPan(x, y)
    self.editorPreviewPanX, self.editorPreviewPanY = x, y
    if not self.editorPreviewStage then return end
    self.editorPreviewStage:ClearAllPoints()
    self.editorPreviewStage:SetPoint("CENTER", self.editorCanvas, "CENTER", x, y)
end

function Options:SetEditorPreviewZoom(zoom, fitted)
    zoom = tonumber(zoom)
    if not zoom then return false end
    self.editorPreviewFit = fitted and true or false
    self.editorPreviewZoom = fitted and math.max(PREVIEW_ZOOM_MIN, math.min(PREVIEW_ZOOM_MAX, zoom))
        or math.max(PREVIEW_ZOOM_MIN, math.min(PREVIEW_ZOOM_MAX, math.floor(zoom * 4 + 0.5) / 4))
    if self.editorPreviewStage then self.editorPreviewStage:SetScale(self.editorPreviewZoom) end
    if not fitted then self:SetEditorPreviewPan(self.editorPreviewPanX or 0, self.editorPreviewPanY or 0) end
    self:UpdateEditorGrid()
    self:UpdateEditorSelectionHandles()
    if self.editorZoomText then self.editorZoomText:SetText(PS.UI.Controls.PercentText(self.editorPreviewZoom)) end
    -- - and + are off at 100% and 300%.
    if self.editorZoomOutButton then self.editorZoomOutButton:SetEnabled(self.editorPreviewZoom > PREVIEW_ZOOM_MIN + 0.001) end
    if self.editorZoomInButton then self.editorZoomInButton:SetEnabled(self.editorPreviewZoom < PREVIEW_ZOOM_MAX - 0.001) end
    return true
end

-- A shown component's centre and half size on the stage (stage units): its position, the bar
-- a value is attached to, the level's name-following offset, its text and its scale.
function Options:EditorComponentBounds(key)
    local component = self.editorComponents and self.editorComponents[key]
    local position = self.editorLayout and self.editorLayout[key]
    if not component or not position or not component.previewFitVisible then return nil end
    local x, y = self:EditorDrawnCentre(key)
    local width, height = component:GetWidth(), component:GetHeight()
    local text = component.previewText
    local textWidth, textHeight = self:EditorTextSize(key)
    if textWidth then
        -- A text part's box hugs its text (its frame is wider, for easy grabbing).
        width, height = textWidth + 6, textHeight + 4
    else
        if text and text.GetStringWidth then width = math.max(width, text:GetStringWidth()) end
        if text and text.GetStringHeight then height = math.max(height, text:GetStringHeight()) end
    end
    local scale = self:EditorDrawnScale(key)
    -- A multi-line aura row: the box covers every line, not only the first.
    local gridWidth, gridHeight, offset = self:EditorAuraGrid(key)
    if gridWidth then
        width, height = math.max(width, gridWidth), gridHeight
        y = y + offset * scale
    end
    return x, y, width * scale / 2, height * scale / 2
end

-- Fits the plate's shown parts about its centre; zoom fixes the zoom (Studio opens at 100%), otherwise it is
-- the largest in range that shows them all. A refit on resize keeps whichever was asked for.
function Options:FitEditorPreview(zoom)
    self.editorPreviewFitZoom = zoom
    local canvas, stage = self.editorCanvas, self.editorPreviewStage
    if not canvas or not stage or not self.editorLayout then return false end
    local left, right, bottom, top
    for key in pairs(self.editorComponents or {}) do
        local x, y, hw, hh = self:EditorComponentBounds(key)
        if x then
            hw, hh = hw + 3, hh + 3
            left, right = math.min(left or x-hw, x-hw), math.max(right or x+hw, x+hw)
            bottom, top = math.min(bottom or y-hh, y-hh), math.max(top or y+hh, y+hh)
        end
    end
    -- Across, the plate's own centre (x = 0, where it sits over the unit) stays in the middle, so
    -- parts on one side only (TAGGED, the classification) do not pull it off centre: the wider
    -- side sets the width. Up and down, the parts' bounds are centred.
    local halfWidth = left and math.max(math.abs(left), math.abs(right)) or 0
    zoom = zoom or (left and math.min(PREVIEW_FIT_ZOOM, (canvas:GetWidth()-32) / math.max(1, 2 * halfWidth),
        (canvas:GetHeight()-112) / math.max(1, top-bottom)) or PREVIEW_ZOOM_DEFAULT)
    zoom = math.max(PREVIEW_ZOOM_MIN, math.min(PREVIEW_ZOOM_MAX, zoom))
    self:SetEditorPreviewZoom(zoom, true)
    -- The preview's lower controls take a little more room.
    self:SetEditorPreviewPan(0, 12/zoom - (bottom and (bottom+top)/2 or 0))
    return true
end

-- Dragging the empty preview pans it; the mouse wheel zooms in quarter steps.
function Options:StartEditorPan()
    if type(GetCursorPosition) ~= "function" or not self.editorPreviewStage then return end
    local cursorX, cursorY = GetCursorPosition()
    self.editorPan = { cursorX = cursorX, cursorY = cursorY,
        x = self.editorPreviewPanX or 0, y = self.editorPreviewPanY or 0 }
    self.editorCanvas:SetScript("OnUpdate", function()
        local pan = self.editorPan
        local x, y = GetCursorPosition()
        local scale = self.editorPreviewStage:GetEffectiveScale()
        if not pan or type(x) ~= "number" or not scale or scale <= 0 then return end
        self.editorPreviewFit = false
        self:SetEditorPreviewPan(pan.x + (x - pan.cursorX) / scale, pan.y + (y - pan.cursorY) / scale)
    end)
end

function Options:StopEditorPan()
    self.editorPan = nil
    if self.editorCanvas then self.editorCanvas:SetScript("OnUpdate", nil) end
end

-- Snapping lines up an edge or the centre of the dragged component with the plate's centre
-- and edges, the plate's text and bar rows, and every other shown component's edges and
-- centre.
local SNAP_DISTANCE = 6

-- The lines key snaps to and its half size: { x = lines, y = lines, hw, hh }. The other parts
-- stay put while one is dragged, so a drag collects them once.
function Options:EditorSnapLines(key)
    local profile = type(PS.GetPlateProfileSettings) == "function"
        and PS.GetPlateProfileSettings(self.editorProfile) or PS.GetSettings()
    local plate = ((profile and profile.width or 112) * (profile and profile.scale or 1)) / 2
    local linesX, linesY = { 0, -plate, plate }, { 0, 16, -13 }
    for other in pairs(self.editorComponents or {}) do
        local ox, oy, ohw, ohh
        if other ~= key then ox, oy, ohw, ohh = self:EditorComponentBounds(other) end
        if ox then
            linesX[#linesX + 1], linesX[#linesX + 2], linesX[#linesX + 3] = ox - ohw, ox, ox + ohw
            linesY[#linesY + 1], linesY[#linesY + 2], linesY[#linesY + 3] = oy - ohh, oy, oy + ohh
        end
    end
    local _, _, hw, hh = self:EditorComponentBounds(key)
    local component = self.editorComponents and self.editorComponents[key]
    hw = hw or (component and component.GetWidth and component:GetWidth() / 2) or 0
    hh = hh or (component and component.GetHeight and component:GetHeight() / 2) or 0
    return { x = linesX, y = linesY, hw = hw, hh = hh }
end

-- centre moved onto the nearest line within reach of its centre or either edge (tried in that
-- order), and the line (nil when none is in reach).
local function Nearest(centre, half, lines)
    local best, line
    for _, target in ipairs(lines) do
        for side = 0, 2 do
            local shift = target - (centre + (side == 0 and 0 or side == 1 and -half or half))
            if math.abs(shift) <= SNAP_DISTANCE and (not best or math.abs(shift) < math.abs(best)) then
                best, line = shift, target
            end
        end
    end
    return centre + (best or 0), line
end

-- The snapped centre for key at (x, y) and the lines it snapped to (nil when free on an axis).
-- lines: EditorSnapLines(key), when the caller has them.
function Options:SnapEditorPosition(key, x, y, lines)
    if not self.editorSnap then return x, y end
    lines = lines or self:EditorSnapLines(key)
    local lineX, lineY
    x, lineX = Nearest(x, lines.hw, lines.x)
    y, lineY = Nearest(y, lines.hh, lines.y)
    return x, y, lineX, lineY
end

function Options:SetEditorComponentPosition(key, x, y, snap)
    if not self:IsEditorComponentRelevant(key) or editorDefinitions[key].movable == false then return false end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x ~= x or y ~= y then return false end
    if snap then
        local cx, cy = self:EditorVisualCentre(key, x, y)
        cx, cy = self:SnapEditorPosition(key, cx, cy)
        x, y = self:EditorStoredOffset(key, cx, cy)
    end
    x = Schema.Bounded(Schema.layoutRanges.x, x)
    y = Schema.Bounded(Schema.layoutRanges.y, y)
    PS.SetComponentPosition(key, x, y, self.editorProfile, self:CurrentEditorVariant())
    self:ReloadEditorLayoutCopy()
    -- The part and everything laid out from it: its children, a stack's next parts, pinned parts.
    self:RefreshEditorLayout()
    self:RefreshEditorInspectorContext()
    return true
end

-- light (a slider step): only the preview's layout follows; letting go refreshes the inspector.
function Options:SetEditorComponentScale(key, scale, light)
    if not self:IsEditorComponentRelevant(key) then return false end
    scale = tonumber(scale)
    if not scale or scale ~= scale then return false end
    scale = Schema.ComponentScale(scale)
    if not PS.SetComponentScale(key, scale, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self:ReloadEditorLayoutCopy()
    self:RefreshEditorLayout()
    if not light then self:RefreshEditorInspectorContext() end
    return true
end

-- Studio's preview sizes for Settings' drawn positions (stacks, pinned parts).
function Options:SupplyEditorMeasure()
    self.editorMeasureFunction = self.editorMeasureFunction or function(key) return self:EditorMeasure(key) end
    if PS.SetLayoutMeasure then PS.SetLayoutMeasure(self.editorMeasureFunction) end
end

-- Placement: Free (edge nil) keeps the part where it is drawn (with the preview's sizes);
-- pinned to the parent part's edge, it snaps to that edge (Settings' SetComponentAttach), and
-- its X and Y are then an offset from that spot.
function Options:SetEditorAttach(key, edge)
    self:SupplyEditorMeasure()
    if not PS.SetComponentAttach(key, edge, self.editorProfile, self:CurrentEditorVariant()) then return false end
    self:ReloadEditorLayout()
    self:UpdateEditorSelectionHandles()
    return true
end

-- Placement: the part's parent (its anchor), keeping it where it is drawn.
function Options:SetEditorAnchor(key, parentKey)
    if parentKey == "" then parentKey = nil end
    return self:MoveEditorNode(key, parentKey, nil)
end

function Options:NudgeEditorComponent(dx, dy)
    local key = self.selectedComponent
    local position = key and self.editorLayout and self.editorLayout[key]
    if not position then return false end
    local step = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and 10 or 1
    return self:SetEditorComponentPosition(key, position.x + dx * step, position.y + dy * step, false)
end

function Options:CaptureEditorComponent(key)
    local component = self.editorComponents and self.editorComponents[key]
    local canvas = self.editorPreviewStage or self.editorCanvas
    if not component or not canvas or not component.GetCenter or not canvas.GetCenter then return end
    local componentX, componentY = component:GetCenter()
    local canvasX, canvasY = canvas:GetCenter()
    if not componentX or not componentY or not canvasX or not canvasY then return end
    -- GetCenter is in each frame's own scale: the part's (its drawn scale on the stage) and the
    -- stage's. The difference, in stage units, is the drawn centre, stored in the tree.
    local scale = self:EditorDrawnScale(key)
    local x, y = self:EditorStoredOffset(key, componentX * scale - canvasX, componentY * scale - canvasY)
    self:SetEditorComponentPosition(key, x, y, true)
end

function Options:UpdateEditorDrag()
    local drag = self.editorDrag
    if not drag or type(GetCursorPosition) ~= "function" then return end
    local cursorX, cursorY = GetCursorPosition()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then return end
    local stage = self.editorPreviewStage or self.editorCanvas
    local scale = stage and stage.GetEffectiveScale and stage:GetEffectiveScale()
        or self.editorPreviewZoom or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    -- Drags work on the drawn stage, so the part (or group) moves exactly with the pointer.
    local x = drag.startX + (cursorX - drag.cursorX) / scale
    local y = drag.startY + (cursorY - drag.cursorY) / scale
    if drag.group then
        local localX, localY = self:EditorStoredOffset(drag.group, x, y)
        localX, localY = math.floor(localX + 0.5), math.floor(localY + 0.5)
        if localX == drag.x and localY == drag.y then return end
        drag.x, drag.y = localX, localY
        -- The copy's group moves in place, so the drawn places are worked out again; with the
        -- group selected, the layout refresh also moves its handles.
        local group = self.editorLayout[drag.group]
        group.x, group.y = localX, localY
        self:InvalidateEditorTransforms()
        self:RefreshEditorLayout()
        return
    end
    local lineX, lineY
    -- Holding Shift moves freely for as long as it is held.
    local free = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
    if self.editorSnap and not free then
        drag.snapLines = drag.snapLines or self:EditorSnapLines(drag.key)
        x, y, lineX, lineY = self:SnapEditorPosition(drag.key, x, y, drag.snapLines)
    end
    -- Unrounded while dragging; the drop commits a rounded position.
    x = math.max(Schema.layoutRanges.x[1], math.min(Schema.layoutRanges.x[2], x))
    y = math.max(Schema.layoutRanges.y[1], math.min(Schema.layoutRanges.y[2], y))
    drag.x, drag.y = x, y
    -- The selection handles are anchored to the part, so they follow it.
    drag.component:ClearAllPoints()
    -- The part's own offsets are in its drawn units.
    drag.component:SetPoint("CENTER", stage, "CENTER", x / drag.partScale, y / drag.partScale)
    if self.editorCoordinateX and self.editorCoordinateY then
        local storedX, storedY = self:EditorStoredOffset(drag.key, x, y)
        storedX, storedY = math.floor(storedX + 0.5), math.floor(storedY + 0.5)
        if storedX ~= drag.shownX or storedY ~= drag.shownY then
            drag.shownX, drag.shownY = storedX, storedY
            self.editorCoordinateX:SetText(tostring(storedX))
            self.editorCoordinateY:SetText(tostring(storedY))
        end
    end
    if self.editorSnapGuideX then
        self.editorSnapGuideX:SetShown(lineX ~= nil)
        self.editorSnapGuideX:ClearAllPoints()
        self.editorSnapGuideX:SetPoint("CENTER", stage, "CENTER", lineX or x, 0)
    end
    if self.editorSnapGuideY then
        self.editorSnapGuideY:SetShown(lineY ~= nil)
        self.editorSnapGuideY:ClearAllPoints()
        self.editorSnapGuideY:SetPoint("CENTER", stage, "CENTER", 0, lineY or y)
    end
end

-- While a component is dragged, every other shown component shows its box to line up with.
function Options:ShowEditorComponentOutlines(shown)
    for key, component in pairs(self.editorComponents or {}) do
        if key ~= self.selectedComponent and component.SetBackdropBorderColor and key ~= "quest" then
            component:SetBackdropBorderColor(0.85, 0.75, 0.5, shown and self:IsEditorPartDrawn(key) and 0.55 or 0)
        end
    end
end

function Options:StartEditorDrag(key, component)
    if editorDefinitions[key].movable == false then return end
    -- With a custom group selected, dragging one of its members moves the whole group.
    local groupKey = self.editorSelectedGroup
    local member = groupKey and self:IsEditorUnder(key, groupKey)
    if member and type(GetCursorPosition) == "function" then
        local cursorX, cursorY = GetCursorPosition()
        local group = self.editorLayout[groupKey]
        local startX, startY = self:EditorVisualCentre(groupKey, group.x, group.y)
        self.editorDrag = { key = key, group = groupKey, component = component, cursorX = cursorX, cursorY = cursorY,
            startX = startX, startY = startY, x = group.x, y = group.y }
        component:SetScript("OnUpdate", function() self:UpdateEditorDrag() end)
        return
    end
    if self.selectedComponent ~= key then self:SelectEditorComponent(key) end
    if type(GetCursorPosition) ~= "function" then component:StartMoving() return end
    local cursorX, cursorY = GetCursorPosition()
    local position = self.editorLayout and self.editorLayout[key]
    if not position or type(cursorX) ~= "number" or type(cursorY) ~= "number" then return end
    local startX, startY = self:EditorDrawnCentre(key)
    self.editorDrag = { key = key, component = component, cursorX = cursorX, cursorY = cursorY,
        startX = startX, startY = startY, x = startX, y = startY, partScale = self:EditorDrawnScale(key) }
    component:SetScript("OnUpdate", function() self:UpdateEditorDrag() end)
    self:ShowEditorComponentOutlines(true)
end

function Options:StopEditorDrag(key, component)
    if editorDefinitions[key].movable == false then return end
    if self.editorDrag and self.editorDrag.key == key then self:UpdateEditorDrag() end
    component:SetScript("OnUpdate", nil)
    if self.editorSnapGuideX then self.editorSnapGuideX:Hide() end
    if self.editorSnapGuideY then self.editorSnapGuideY:Hide() end
    self:ShowEditorComponentOutlines(false)
    local drag = self.editorDrag
    self.editorDrag = nil
    if drag and drag.group then
        self:SetEditorGroupOffset(drag.group, drag.x, drag.y)
        return
    end
    if drag and drag.key == key then
        -- Put somewhere by hand, a stacked part (other than the stack's first) leaves the stack.
        if self:IsEditorStacked(key) and not self:IsEditorStackFirst(key) then
            PS.SetComponentFree(key, true, self.editorProfile, self:CurrentEditorVariant())
            self:ReloadEditorLayoutCopy()
        end
        local x, y = self:EditorStoredOffset(key, drag.x, drag.y)
        self:SetEditorComponentPosition(key, x, y, false)
    else
        component:StopMovingOrSizing()
        self:CaptureEditorComponent(key)
    end
end

-- How many pins key's anchor chain has above it (0: placed from the stage); nil when the chain
-- leads back to key or runs deeper than a layout can nest.
function Options:EditorPinDepth(key)
    local depth, node = 0, key
    for _ = 1, Schema.MAX_DEPTH + 1 do
        local position = self.editorLayout and self.editorLayout[node]
        local edge = position and position.attach and Schema.ATTACH_EDGES[position.attach]
        local target = edge and self:EditorPinTarget(node)
        if not (target and self.editorComponents and self.editorComponents[target]) then return depth end
        if target == key then return nil end
        depth, node = depth + 1, target
    end
    return nil
end

-- Every component is let go first, then placed parents first: a part is only ever anchored to one
-- already placed for this layout, never to one still anchored to it from the last layout (a
-- profile or plate type that pins them the other way round), which the client refuses.
local layoutScratch, depthScratch = {}, {}
function Options:RefreshEditorLayout()
    if not self.editorCanvas then return end
    local components = self.editorComponents or {}
    local order = layoutScratch
    for index = #order, 1, -1 do order[index] = nil end
    for index, key in ipairs(editorOrder) do
        local component = components[key]
        if component then
            component:ClearAllPoints()
            order[#order + 1] = key
            depthScratch[key] = (self:EditorPinDepth(key) or 0) * 1000 + index
        end
    end
    table.sort(order, function(left, right) return depthScratch[left] < depthScratch[right] end)
    for _, key in ipairs(order) do self:PositionEditorComponent(key) end
    -- A selected group's box is measured from its members, so it follows every change.
    if self.editorSelectedGroup and not self.selectedComponent then self:UpdateEditorSelectionHandles() end
end

function Options:ResetEditorLayout()
    local defaults = type(PS.GetDefaultLayout) == "function"
        and PS.GetDefaultLayout(self.editorProfile, self:CurrentEditorVariant()) or editorDefaults
    self:ApplyEditorLayout(defaults)
    self:SelectEditorComponent((self:CurrentEditorVariant() == "names"
        or self:CurrentEditorVariant() == "dungeon") and "name" or "health")
end

Options.studioModel = {
    editorProfiles = editorProfiles,
    modeChoices = modeChoices,
    friendlyChoices = friendlyChoices,
    friendlyPvpChoices = friendlyPvpChoices,
    classificationStyleChoices = classificationStyleChoices,
    targetHighlightChoices = targetHighlightChoices,
    auraSourceChoices = auraSourceChoices,
    AddLabel = AddLabel,
    WidgetName = WidgetName,
}

Options.settingsPanelModel = {
    WidgetName = WidgetName,
    CopyEditorLayout = CopyEditorLayout,
}

-- Everything from the settings: the layout copy, every control, the preview (which lays the
-- parts out) and Studio's look. light: a value changed, so the look (ApplyEditorTheme, a pass
-- over all of Studio's art) is left as it is; Studio opening, accessibility and the preview's
-- plain background take the full refresh.
function Options:Refresh(light)
    local settings = PS.GetSettings()
    if not settings then return end
    if type(PS.GetLayout) == "function" then self:ReloadEditorLayoutCopy() end
    -- One failing control must not leave the guard set, or every slider would
    -- silently stop saving until /reload.
    self.refreshing = true
    local failure
    for _, control in ipairs(self.controls) do
        local ok, message = pcall(control.Refresh, control, settings)
        if not ok and not failure then failure = message end
    end
    self.refreshing = false
    if failure then PS.Chat.ReportError("options refresh", failure) end
    self:RefreshEditorAppearance(settings)
    if not light then self:ApplyEditorTheme() end
end

-- What a dragged slider changes, and nothing else: the preview's look, layout and outline (as
-- the resize handles do). The tree, the controls and the inspector refresh when it is let go.
function Options:RefreshEditorPreview()
    local settings = PS.GetSettings()
    if not settings or not self.editor then return end
    if type(PS.GetLayout) == "function" then self:ReloadEditorLayoutCopy() end
    self:RefreshEditorAppearance(settings, true)
    self:UpdateEditorSelectionHandles()
end

-- A dragged slider can step several times a frame: each step is written at once, the preview
-- follows once on the next frame. Without a timer it follows at once.
function Options:QueueRefresh()
    if not (C_Timer and C_Timer.After) then return self:RefreshEditorPreview() end
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        self:RefreshEditorPreview()
    end)
end

-- Register display changes at addon load rather than when the editor is opened;
-- Forever may protect new event subscriptions after the UI has entered combat.
local editorDisplayEventFrame = CreateFrame("Frame")
PS._RegisterEvent(editorDisplayEventFrame, "DISPLAY_SIZE_CHANGED", "platesmith.blueprint-editor")
editorDisplayEventFrame:SetScript("OnEvent", function()
    Options:FitVisualEditorToScreen()
end)
