local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Profiles = assert(PS.Profiles, "PlateSmith Profiles missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local L = PS.L

-- Profiles: choose, create, copy, rename and delete profiles, and this character's automatic switching. Their one home
-- is Studio › Settings › Profiles (built here with Studio's settings kit, so it works in combat); Game Options'
-- Profiles page opens it. Loading settings into the working copy (copy from, reset) still needs Save; actions on whole
-- profiles apply at once. Names and deletes are asked in PlateSmith's own dialogs (Studio's), never a StaticPopup.
-- Studio's Profile menu is the quick switcher over the same PS.Profiles calls.

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

-- "Don't switch", then every profile, for the automatic-switching rules.
local function RuleChoices()
    local choices = { { value = "", label = L["Don't switch"] } }
    for _, name in ipairs(Profiles.List()) do choices[#choices + 1] = { value = name, label = name } end
    return choices
end

-- This character's automatic switching (Core/AutoProfile.lua) into section: saved at once, like the tank role,
-- since it is a per-character choice rather than part of a profile's design.
local function BuildAutoProfileRows(kit, section)
    local Auto = PS.AutoProfile
    kit.Add(section, kit.Help(section, L["This character can change profile by itself when it enters other content "
        .. "or changes specialization. It waits until combat ends and until unsaved changes are saved or reverted."]))
    -- Audit #7: designs per place are the one route for a look; switching is for whole setups. Both read the place
    -- through NamePolicy.InstanceType, so a scenario is open world to each.
    kit.Add(section, kit.Help(section, L["To change how plates look in a kind of place, give them a design "
        .. "there in Studio (the Design menu). Switch profiles for whole different setups, such as per specialization. "
        .. "Scenarios and delves count as open world, as they do for designs."]))
    local dropdowns = {}
    local function RuleRow(key, label)
        local row, dropdown = kit.DropdownRow(section, label, {
            choices = RuleChoices, name = "PlateSmithAutoProfile_" .. key .. "Dropdown",
            get = function() return (Auto.Rules() or {})[key] or "" end,
            set = function(name) Report(Auto.SetRule(key, name)) end,
        })
        Register(dropdown)
        kit.Add(section, row)
        dropdowns[key] = dropdown
    end
    local contentLabels = { world = L["Open world"], dungeon = L["Dungeons"], raid = L["Raids"],
        pvp = L["Battlegrounds & arenas"] }
    for _, key in ipairs(Auto.CONTENT) do
        RuleRow(key, contentLabels[key])
        -- Separate rows here (the rules keep dungeon and raid apart); Studio has one design for both.
        if key == "raid" then
            kit.Add(section, kit.ControlHelp(section, L["Studio's Dungeons & raids designs apply in both."]))
        end
    end
    local specs = Auto.SpecCount()
    for index = 1, specs do RuleRow(Auto.SPEC_KEYS[index], Auto.SpecLabel(index)) end
    if specs > 0 then
        local row, dropdown = kit.DropdownRow(section, L["When both apply"], {
            choices = { { value = "content", label = L["Content decides"] },
                { value = "spec", label = L["Specialization decides"] } },
            name = "PlateSmithAutoProfilePrecedenceDropdown",
            get = function() return (Auto.Rules() or {}).precedence or "content" end,
            set = function(value) Report(Auto.SetPrecedence(value)) end,
        })
        Register(dropdown)
        kit.Add(section, row)
        dropdowns.precedence = dropdown
    else
        kit.Add(section, kit.Help(section, L["This client has no specializations to switch by."]))
    end
    Options.autoProfileDropdowns = dropdowns
    Options.autoProfileSection = section
end

-- Studio › Settings › Profiles (Inspector defines the page; Page and Section are its settings kit's): this character's
-- profile, the other profiles, and automatic switching.
function Options:BuildProfileSettings(SK, Page, Section)
    local page = Page("profiles",
        L["Each character uses one profile. Edits apply straight away but are kept only when you press Save."])
    local this = Section(page, "profileThis", L["This character's profile"], function()
        return tostring(Profiles.Active() or Profiles.DEFAULT)
    end)
    local activeRow, active = SK.DropdownRow(this, L["Active profile"], {
        choices = AllProfiles, name = "PlateSmithProfilesActiveDropdown",
        get = Profiles.Active, set = function(name) Report(Profiles.Switch(name)) end,
    })
    Register(active)
    SK.Add(this, activeRow)
    SK.Add(this, SK.ControlHelp(this, L["Save or revert unsaved changes before switching."]))
    local actionsRow = SK.ButtonsRow(this, nil, {
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
    SK.Add(this, actionsRow)
    -- Reset is the Settings footer's Reset settings (one control for it), under every Settings page.
    SK.Add(this, SK.Help(this, L["Reset settings, at the foot of Settings, puts every setting and position in this "
        .. "profile back to the defaults; Revert undoes it until you save."]))

    -- A new profile from a built-in preset, named after it (Core/ProfilePresets.lua).
    local presets = PS.ProfilePresets
    local chosenPreset = presets.LIST[1].id
    local presetChoices = {}
    for _, preset in ipairs(presets.LIST) do
        presetChoices[#presetChoices + 1] = { value = preset.id, label = preset.name, help = preset.description }
    end
    local presetRow, presetDropdown = SK.DropdownRow(this, L["New from preset"], {
        choices = presetChoices, name = "PlateSmithProfilesPresetDropdown",
        get = function() return chosenPreset end, set = function(id) chosenPreset = id end,
    })
    Register(presetDropdown)
    SK.Add(this, presetRow)
    local createRow = SK.ButtonsRow(this, nil, { { L["Create"], 100, function()
        Report(Profiles.CreateFromPreset(chosenPreset))
    end } })
    SK.Add(this, createRow)
    SK.Add(this, SK.ControlHelp(this, L["Makes a new profile from the preset and switches to it. Your profiles are not changed."]))
    Options.profilePresetDropdown, Options.profilePresetCreate = presetDropdown, createRow.buttons[1]

    local others = Section(page, "profileOthers", L["Other profiles"])
    local copyRow, copy = SK.DropdownRow(others, L["Copy settings from"], {
        choices = OtherProfiles, name = "PlateSmithProfilesCopyDropdown", placeholder = L["Choose a profile"],
        get = function() return nil end, set = function(name) Report(Profiles.CopyFrom(name)) end,
    })
    Register(copy)
    SK.Add(others, copyRow)
    SK.Add(others, SK.ControlHelp(others, L["Loads another profile's settings into this one. Press Save to keep them."]))
    local deleteRow, deleteDropdown = SK.DropdownRow(others, L["Delete a profile"], {
        choices = OtherProfiles, name = "PlateSmithProfilesDeleteDropdown", placeholder = L["Choose a profile"],
        get = function() return nil end, set = function(name) ConfirmDelete(name) end,
    })
    Register(deleteDropdown)
    SK.Add(others, deleteRow)

    BuildAutoProfileRows(SK, Section(page, "autoProfile", L["Automatic switching"]))

    local actions = actionsRow.buttons
    Options.profileButtons = { new = actions[1], duplicate = actions[2], rename = actions[3], delete = deleteDropdown }
    return page
end

-- Studio's Profile menu › Switch automatically...: Settings › Profiles at Automatic switching (in combat too).
function Options:OpenAutoProfileSettings()
    return self:OpenSettingsCategory("profiles", function() return self.autoProfileSection end)
end

-- Game Options' Profiles page: a launcher (Panel.lua's BuildLauncherPage), as Threat's and every module's is.
function Options:BuildProfilesPage(page)
    page.profilesOpenButton = self:BuildLauncherPage(page, L["Profiles"], L["Profiles are in Blueprint Studio › "
        .. "Settings › Profiles: switch, create, copy, rename, delete and reset them, and choose when this character "
        .. "switches by itself."], function() Options:OpenSettingsCategory("profiles") end)
end
