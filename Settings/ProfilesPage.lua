local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Profiles = assert(PS.Profiles, "PlateSmith Profiles missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local L = PS.L

-- Settings > PlateSmith > Profiles: choose, create, copy, rename, and delete
-- profiles. Loading settings into the working copy (copy from, reset) still
-- needs Save; actions on whole profiles apply at once. Names and deletes are asked in
-- PlateSmith's own dialogs (Studio's), never a StaticPopup.

local function Report(ok, reason)
    if not ok then Chat.Print(string.format(L["Profile change failed: %s"], L[reason or "unknown error"])) end
    Options:Refresh()
    return ok, reason
end

-- accept(name) returns ok, reason. As in Studio, a refusal keeps the name window open with the
-- reason shown under the box.
local function AskName(prompt, initial, accept)
    return Options:PromptStudioName(prompt, initial, function(name)
        local ok, reason = accept(name)
        Options:Refresh()
        return ok, reason
    end)
end

local function ConfirmDelete(name)
    return Options:ConfirmStudioAction(string.format(L["Delete the profile \"%s\"? This cannot be undone."], name),
        L["Delete"], function() Report(Profiles.Delete(name)) end)
end

-- Profiles other than the active one, for the copy and delete pickers.
local function OtherProfiles()
    local choices, active = {}, Profiles.Active()
    for _, name in ipairs(Profiles.List()) do
        if name ~= active then choices[#choices + 1] = { value = name, label = name } end
    end
    return choices
end

local function AllProfiles()
    local choices = {}
    for _, name in ipairs(Profiles.List()) do choices[#choices + 1] = { value = name, label = name } end
    return choices
end

local Register = Options.RegisterControl

function Options:BuildProfilesPage(page)
    local kit, flow, bar = self:NewSettingsPage(page, L["Profiles"],
        L["Each character uses one profile. Edits apply straight away but are kept only when you press Save."], true)

    local this = Options.SettingsSection(kit, flow, L["This character's profile"])
    local activeRow, active = kit.DropdownRow(this, L["Active profile"], {
        choices = AllProfiles, name = "PlateSmithProfilesActiveDropdown",
        get = Profiles.Active, set = function(name) Report(Profiles.Switch(name)) end,
    })
    Register(active)
    kit.Add(this, activeRow)
    kit.Add(this, kit.ControlHelp(this, L["Save or revert unsaved changes before switching."]))
    local actionsRow, actions = kit.ButtonsRow(this, "", {
        { L["New profile"], 110, function()
            AskName(L["Name for the new profile:"], "", function(name) return Profiles.Create(name) end)
        end },
        { L["Duplicate"], 100, function()
            local current = Profiles.Active()
            AskName(L["Name for the copy:"], string.format(L["%s copy"], current),
                function(name) return Profiles.Create(name, current) end)
        end },
        { L["Rename"], 100, function()
            AskName(L["New name for this profile:"], Profiles.Active(), function(name) return Profiles.Rename(name) end)
        end },
    })
    kit.Add(this, actionsRow)
    -- Asked first, as in Studio; Revert still undoes it until you save.
    local resetRow, resetButtons = kit.ButtonsRow(this, "", { { L["Reset to defaults"], 150, function()
        Options:ConfirmStudioAction(L["Reset every setting and position in this profile to the defaults? "
            .. "Revert undoes it until you save."], L["Reset settings"], function()
                PS.ResetSettings()
                Options:Refresh()
            end)
    end } })
    kit.Add(this, resetRow)
    Options.resetButton = resetButtons[1]

    -- A new profile from a built-in preset, named after it (Core/ProfilePresets.lua).
    local presets = PS.ProfilePresets
    local chosenPreset = presets.LIST[1].id
    local presetChoices = {}
    for _, preset in ipairs(presets.LIST) do
        presetChoices[#presetChoices + 1] = { value = preset.id, label = preset.name, help = preset.description }
    end
    local presetRow, presetDropdown = kit.DropdownRow(this, L["New from preset"], {
        choices = presetChoices, name = "PlateSmithProfilesPresetDropdown",
        get = function() return chosenPreset end, set = function(id) chosenPreset = id end,
    })
    Register(presetDropdown)
    kit.Add(this, presetRow)
    local createRow, createButtons = kit.ButtonsRow(this, "", { { L["Create"], 100, function()
        Report(Profiles.CreateFromPreset(chosenPreset))
    end } })
    kit.Add(this, createRow)
    kit.Add(this, kit.ControlHelp(this, L["Makes a new profile from the preset and switches to it. Your profiles are not changed."]))
    Options.profilePresetDropdown, Options.profilePresetCreate = presetDropdown, createButtons[1]

    local others = Options.SettingsSection(kit, flow, L["Other profiles"])
    local copyRow, copy = kit.DropdownRow(others, L["Copy settings from"], {
        choices = OtherProfiles, name = "PlateSmithProfilesCopyDropdown", placeholder = L["Choose a profile"],
        get = function() return nil end, set = function(name) Report(Profiles.CopyFrom(name)) end,
    })
    Register(copy)
    kit.Add(others, copyRow)
    kit.Add(others, kit.ControlHelp(others, L["Loads another profile's settings into this one. Press Save to keep them."]))
    local deleteRow, deleteDropdown = kit.DropdownRow(others, L["Delete a profile"], {
        choices = OtherProfiles, name = "PlateSmithProfilesDeleteDropdown", placeholder = L["Choose a profile"],
        get = function() return nil end, set = function(name) ConfirmDelete(name) end,
    })
    Register(deleteDropdown)
    kit.Add(others, deleteRow)

    Options.profilesSaveBar = bar
    Options.profileButtons = { new = actions[1], duplicate = actions[2], rename = actions[3], delete = deleteDropdown }
    page:Relayout()
end
