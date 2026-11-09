local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local L = PS.L

-- Bringing a profile up to its look's latest version (ProfilePresets.LOOK_VERSION): the Profile menu's item and, once
-- per version when Studio opens, a What's new window with the version's notes (ProfilePresets.LookNotes). Both open the
-- import review with the look's latest version (BlueprintWindow's ShowLookUpdate), whose What's new? shows the same
-- notes; nothing changes until Update selected, and then as unsaved changes (Save keeps, Revert undoes).
local LookUpdate = {}
Options.LookUpdate = LookUpdate

local WIDTH, TEXT_X, TOP = 540, 26, 58

-- The look db (the working settings) was made from, when it is behind the latest version: its preset, else nil (no
-- look, an unknown one, or up to date). A look without a readable version is version 1's.
function LookUpdate.Behind(db)
    db = db or PS.GetSettings()
    local Presets = PS.ProfilePresets
    local preset = db and type(db.look) == "string" and Presets.Get(db.look) or nil
    if not preset or (tonumber(db.lookVersion) or 1) >= Presets.LOOK_VERSION then return nil end
    return preset
end

-- The Profile menu's items after New from preset: Update to the latest <Look>... (marked as a new version) for a profile
-- behind its look; Update to a look's latest style... (a look each) for one that records none (made before 1.3.0); none
-- for an up-to-date one. They show whether or not the What's new window is on. With unsaved changes they wait, so
-- Revert undoes just the update.
function LookUpdate.MenuItems(dirty)
    local db = PS.GetSettings()
    local tip = dirty and L["Save or revert your changes first, so Revert can undo just the update."] or nil
    local preset = LookUpdate.Behind(db)
    if preset then
        local id = preset.id
        return { { text = string.format(L["Update to the latest %s... |cff8fe08f(new version)|r"], preset.name), disabled = dirty,
            tooltip = tip or { title = string.format(L["Update to the latest %s"], preset.name), text = string.format(
                L["This profile was made from version %d of the %s look; it is now version %d. Review what the update would "
                    .. "change on your profile and pick what to take."], tonumber(db.lookVersion) or 1, preset.name,
                PS.ProfilePresets.LOOK_VERSION) },
            func = function() LookUpdate.Open(id) end } }
    end
    if db and db.look ~= nil then return {} end
    local looks = {}
    for _, look in ipairs(PS.ProfilePresets.LIST) do
        local id = look.id
        looks[#looks + 1] = { text = look.name, disabled = dirty, tooltip = { title = look.name, text = look.description },
            func = function() LookUpdate.Open(id) end }
    end
    return { { text = L["Update to a look's latest style..."], children = looks, disabled = dirty, tooltip = tip
        or L["This profile was made before looks kept a version. Review what a look's latest style would change on it "
            .. "and pick what to take."] } }
end

-- Whether Studio tells this player when a look has a new version: account state (lookNewsOff), one setting for every
-- profile, shown in Settings › Studio and in the window's own box. Personal; never needs Save.
function LookUpdate.Enabled()
    local state = PS.GetState and PS.GetState()
    return not (state and state.lookNewsOff == true)
end
function LookUpdate.SetEnabled(on)
    local state = PS.GetState and PS.GetState()
    if not state then return false end
    state.lookNewsOff = not on or nil
    local row, dialog = Options.editorLookNewsCheckbox, LookUpdate.dialog
    if row and row.Refresh then row:Refresh() end
    if dialog then dialog.tell:SetChecked(LookUpdate.Enabled()) end
    return true
end

-- The review for look id; the window goes.
function LookUpdate.Open(id)
    LookUpdate.Hide()
    return Options:ShowLookUpdate(id)
end

function LookUpdate.Hide()
    if LookUpdate.dialog then LookUpdate.dialog:Hide() end
end

-- Look id's notes after version from, as the window's text: a gold heading per version, then its lines.
function LookUpdate.NotesText(id, from)
    local parts = {}
    for _, note in ipairs(PS.ProfilePresets.LookNotes(id, from)) do
        parts[#parts + 1] = "|cffffd100" .. string.format(L["Version %d"], note.version) .. "|r"
        for _, line in ipairs(note.lines) do parts[#parts + 1] = "- " .. line end
    end
    return table.concat(parts, "\n")
end

-- A font string's wrapped height; where the client reports none, its lines at 18 px.
local function TextHeight(text)
    local height = text.GetStringHeight and text:GetStringHeight()
    if type(height) == "number" and height > 0 then return height end
    local _, breaks = tostring(text:GetText() or ""):gsub("\n", "")
    return (breaks + 1) * 18
end
LookUpdate.TextHeight = TextHeight

-- A notes window in Studio's dialog look (ConfirmStudioAction's chrome): a gold title and dialog.notes, NOTES_TOP below
-- its top; Escape closes it. This window's and the release What's new window's (Studio/WhatsNew.lua).
LookUpdate.NOTES_TOP, LookUpdate.NOTES_X = TOP, TEXT_X
function LookUpdate.NotesDialog(name, width)
    local Window, chrome = PS.UI.Window, Options.studioChrome
    local dialog = Window.Create(name, {
        width = width, height = 300, title = "", closeButton = false, closeOnEscape = true, movable = false,
        border = Window.colours.studio,
    })
    chrome.DressStudioDialog(dialog)
    local notes = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    notes:SetFont(chrome.FONT, 14)
    notes:SetTextColor(0.93, 0.90, 0.84)
    notes:SetPoint("TOPLEFT", dialog, "TOPLEFT", TEXT_X, -TOP)
    notes:SetWidth(width - 2 * TEXT_X)
    notes:SetJustifyH("LEFT")
    if notes.SetSpacing then notes:SetSpacing(3) end
    dialog.notes = notes
    return dialog
end

-- The look's dialog: the title, the notes, and for an offer the line that nothing changes yet, the opt-out box, Review
-- changes... and Not now. Escape is Not now.
local function Dialog()
    if LookUpdate.dialog then return LookUpdate.dialog end
    local chrome = Options.studioChrome
    local dialog = LookUpdate.NotesDialog("PlateSmithLookNewsDialog", WIDTH)
    local notes = dialog.notes
    local after = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    after:SetFont(chrome.FONT, 13)
    after:SetTextColor(chrome.LABEL[1], chrome.LABEL[2], chrome.LABEL[3])
    after:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -14)
    after:SetWidth(WIDTH - 2 * TEXT_X)
    after:SetJustifyH("LEFT")
    after:SetText(L["Nothing changes on your profile until you review the update and choose what to take."])
    dialog.after = after
    local tell = chrome.KitCheckbox(dialog, L["Tell me when a look has a new version"], function(box)
        LookUpdate.SetEnabled(box:GetChecked() and true or false)
    end)
    tell:SetPoint("TOPLEFT", after, "BOTTOMLEFT", -4, -10)
    PS.UI.Controls.AttachTooltip(tell, L["Tell me when a look has a new version"], { L["Untick it and this window does not "
        .. "show again, for any profile; Studio's Profile menu still offers the update. The same setting is in Settings › "
        .. "Studio."] })
    dialog.tell = tell
    local review = chrome.CreateStudioButton(dialog, L["Review changes..."], 170, 32, "primary")
    review:SetScript("OnClick", function() if dialog.look then LookUpdate.Open(dialog.look) end end)
    review:SetPoint("BOTTOM", dialog, "BOTTOM", -94, 22)
    PS.UI.Controls.AttachTooltip(review, L["Review changes"], { L["What the look's latest version would change on this "
        .. "profile, design by design. Nothing changes until you press Update selected; then Save keeps it and Revert "
        .. "undoes it."] })
    dialog.review = review
    local close = chrome.CreateStudioButton(dialog, L["Not now"], 170, 32)
    close:SetScript("OnClick", function() dialog:Hide() end)
    dialog.close = close
    dialog:Hide()
    LookUpdate.dialog = dialog
    return dialog
end

-- The What's new window for look id since version from. offer (Studio opening for a profile behind its look): the line
-- that nothing changes yet, the opt-out, Review changes... and Not now. Without it (the review's What's new?): the
-- notes and Close.
function LookUpdate.ShowNotes(id, from, offer)
    local preset = PS.ProfilePresets.Get(id)
    if not preset then return nil end
    offer = offer == true
    local dialog = Dialog()
    dialog.look, dialog.profile, dialog.offer = id, PS.Profiles.Active(), offer
    dialog.title:SetText(string.format(offer and L["The %s look has a new version"] or L["What's new in the %s look"],
        preset.name))
    dialog.notes:SetText(LookUpdate.NotesText(id, from))
    dialog.after:SetShown(offer)
    dialog.tell:SetShown(offer)
    dialog.tell:SetChecked(LookUpdate.Enabled())
    dialog.review:SetShown(offer)
    dialog.close.label:SetText(offer and L["Not now"] or L["Close"])
    dialog.close:ClearAllPoints()
    dialog.close:SetPoint("BOTTOM", dialog, "BOTTOM", offer and 94 or 0, 22)
    local height = TOP + TextHeight(dialog.notes) + 74
    if offer then height = height + 14 + TextHeight(dialog.after) + 38 end
    dialog:SetHeight(math.floor(height + 0.5))
    dialog:Show()
    -- Over the import review when opened from it (both are full-screen dialogs).
    if dialog.Raise then dialog:Raise() end
    return dialog
end

-- Studio opened (/ps): the window for the active profile once per LOOK_VERSION, recorded in the profile at once
-- (Profiles.NoteLookNotice), so it does not come back until the version rises again. Not while it is turned off
-- (Enabled), in combat (a later open shows it) or with unsaved changes, never for a profile that records no look.
function LookUpdate.Opened()
    local db = PS.GetSettings()
    local preset = LookUpdate.Behind(db)
    local version = PS.ProfilePresets.LOOK_VERSION
    if not preset or not LookUpdate.Enabled() or (tonumber(db.lookNoticed) or 0) >= version or PS.Secret.InCombat()
        or PS.Profiles.IsDirty() then
        return nil
    end
    PS.Profiles.NoteLookNotice(version)
    return LookUpdate.ShowNotes(preset.id, db.lookVersion, true)
end

-- After a profile change: the offer goes once its profile is no longer active or no longer behind, or with unsaved
-- changes (the update waits for those).
function LookUpdate.Refresh()
    local dialog = LookUpdate.dialog
    if not (dialog and dialog.offer and dialog:IsShown()) then return end
    if PS.Profiles.Active() ~= dialog.profile or not LookUpdate.Behind() or PS.Profiles.IsDirty() then dialog:Hide() end
end
