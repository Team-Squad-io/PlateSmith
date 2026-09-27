local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local L = PS.L
local SCALE = S.profileRanges.scale

-- Slash commands and the Addon Compartment entry. Everything here goes through
-- the public PS.* API, so commands never reach into plate internals.
local Commands = {}
PS.Commands = Commands

local pendingOptionsOpen = false

-- The Blizzard Settings panel is protected in combat; opening waits for it to end.
function Commands.OpenSettings()
    if Secret.InCombat() then
        pendingOptionsOpen = true
        Chat.Print(L["Settings will open when combat ends."])
    elseif PS.OpenOptions then
        pendingOptionsOpen = false
        PS.OpenOptions()
    else
        Chat.Print(L["Settings are unavailable."])
    end
end

-- The command syntax stays literal; what each command does is translated.
local USAGE = {
    { "/ps", L["Open Blueprint Studio."] },
    { "/ps config", L["Open Settings."] },
    { "/ps save | revert", L["Keep or undo unsaved changes."] },
    { "/ps profile [name]", L["List profiles, or switch to one."] },
    { "/ps console [on|off]", L["Show or hide the threat windows."] },
    { "/ps console sample", L["Show or hide sample data in the threat windows (out of combat)."] },
    { "/ps status", L["Show the profile and any active restrictions."] },
    { "/ps diagnose [history [on|off]]", L["Open the diagnostics report."] },
    { "/ps mode auto|own|overlay", L["Who draws the plates."] },
    { "/ps friendly names|full|off", L["How friendly plates show outdoors."] },
    { string.format("/ps quest on|off, threat on|off, scale %s-%s, reset", SCALE[1], SCALE[2]),
        L["Quick settings; /ps save keeps them."] },
    { "/ps playerprobe", L["Test tools for bug reports."] },
}

local function Usage()
    Chat.Print(L["PlateSmith commands (/platesmith or /ps):"])
    for _, line in ipairs(USAGE) do Chat.Print(line[1] .. " - " .. line[2]) end
end

local function Status()
    local db = PS.GetSettings()
    local profile = tostring(PS.Profiles.Active()) .. (PS.Profiles.IsDirty() and " (unsaved)" or "")
    Chat.Print(string.format("%s: profile=%s, mode=%s (%s), friendly=%s, quest=%s, threat=%s, scale=%.2f, restrictions=%s",
        tostring(PS.RUNTIME_BUILD), profile, db.mode, PS.ExternalProvider() or "native", db.friendly,
        tostring(db.quest), tostring(db.threat), db.scale, PS.Restrictions.Summary()))
end

local function Diagnose(value)
    local window = PS.DiagnosticUI
    if value == "history" then
        window.ShowHistory()
    elseif value == "history on" or value == "history off" then
        PS.DiagnosticHistory.SetEnabled(value == "history on")
        Chat.Print(value == "history on" and L["Diagnostic history on."] or L["Diagnostic history off."])
    else
        PS.Diagnose()
    end
end

-- No name lists the profiles; a name (any case) switches to it.
local function Profile(name)
    local Profiles = PS.Profiles
    if name == "" then
        Chat.Print(string.format(L["Profile: %s. Available: %s"], Profiles.Active(), table.concat(Profiles.List(), ", ")))
        return
    end
    local ok, reason = Profiles.Switch(Profiles.Find(name) or name)
    if ok then
        if PS.Options and PS.Options.Refresh then PS.Options:Refresh() end
        Chat.Print(string.format(L["Switched to profile %s."], Profiles.Active()))
    else
        Chat.Print(string.format(L["Profile change failed: %s"], L[reason or "unknown error"]))
    end
end

-- Commands that only change a setting; each is applied through PS.SetOption, which clamps scale.
local function Choice(key) return function(value) return S.enumSettings[key][value] and value or nil end end
local function Switch(value) if value == "on" then return true elseif value == "off" then return false end end
local settingCommands = {
    mode = Choice("mode"), friendly = Choice("friendly"), quest = Switch, threat = Switch, scale = tonumber,
}

function Commands.Run(text)
    local rawCommand, rawValue = text:match("^%s*(%S*)%s*(.-)%s*$")
    local command, value = rawCommand:lower(), rawValue:lower()
    if command == "" or command == "studio" or command == "editor" then
        PS.OpenVisualEditor()
    elseif command == "config" or command == "settings" then
        Commands.OpenSettings()
    elseif settingCommands[command] then
        local parsed = settingCommands[command](value)
        if parsed == nil then return Usage() end
        PS.SetOption(command, parsed)
        Chat.Print(L["Updated. /ps save keeps it in this profile."])
    elseif command == "console" then
        local console = PS.ThreatConsole
        if not console then return Chat.Print(L["Threat windows are unavailable."]) end
        if value == "sample" then
            if not console:SetSampleData(not console:IsSampleData()) then
                return Chat.Print(L["Sample data is not available in combat."])
            end
            console:RefreshOptions()
            Chat.Print(console:IsSampleData() and L["The threat windows show sample data until you enter combat."]
                or L["The threat windows show live threat."])
        elseif value == "on" then console:Show() elseif value == "off" then console:Hide() else console:Toggle() end
    elseif command == "status" then
        Status()
    elseif command == "diagnose" then
        Diagnose(value)
    elseif command == "playerprobe" then
        PS.ProbePlayerPlate()
    elseif command == "reset" then
        PS.ResetSettings()
        if PS.Options and PS.Options.Refresh then PS.Options:Refresh() end
        Chat.Print(L["Settings reset to defaults. /ps save keeps it in this profile."])
    elseif command == "save" then
        PS.Profiles.Save()
        Chat.Print(string.format(L["Saved profile %s."], PS.Profiles.Active()))
    elseif command == "revert" then
        PS.Profiles.Revert()
        if PS.Options and PS.Options.Refresh then PS.Options:Refresh() end
        Chat.Print(string.format(L["Reverted to the saved profile %s."], PS.Profiles.Active()))
    elseif command == "profile" then
        Profile(rawValue)
    else
        Usage()
    end
end

SLASH_PLATESMITH1 = "/platesmith"
SLASH_PLATESMITH2 = "/ps"
SlashCmdList.PLATESMITH = Commands.Run

PS.Ticker.Register("commands.deferred", 0, function()
    if pendingOptionsOpen and not Secret.InCombat() then
        pendingOptionsOpen = false
        if PS.OpenOptions then PS.OpenOptions() end
    end
end)

-- Addon Compartment (the minimap addon menu), declared in the TOC.
function PlateSmith_OnAddonCompartmentClick()
    Commands.OpenSettings()
end

function PlateSmith_OnAddonCompartmentEnter(_, menuButton)
    if not GameTooltip then return end
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:SetText("PlateSmith")
    GameTooltip:AddLine(L["Click to open settings."], 1, 1, 1)
    GameTooltip:AddLine(tostring(PS.RUNTIME_BUILD), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function PlateSmith_OnAddonCompartmentLeave()
    if GameTooltip then GameTooltip:Hide() end
end
