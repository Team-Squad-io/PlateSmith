local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local S = assert(PS.ProfileSchema, "PlateSmith ProfileSchema missing")
local Dev = assert(PS._Dev, "PlateSmith _Dev missing")
local L = PS.L

-- Slash commands and the Addon Compartment entry. Everything here goes through
-- the public PS.* API, so commands never reach into plate internals.
local Commands = {}
PS.Commands = Commands

local pendingOptionsOpen = false

-- The deferred tick runs only while something waits for combat to end.
local function SetPending(pending)
    pendingOptionsOpen = pending
    PS.Ticker.SetEnabled("commands.deferred", pending)
end

-- The Blizzard Settings panel is protected in combat; opening waits for it to end.
function Commands.OpenSettings()
    if Secret.InCombat() then
        SetPending(true)
        Chat.Print(L["Settings will open when combat ends."])
    elseif PS.OpenOptions then
        SetPending(false)
        PS.OpenOptions()
    else
        Chat.Print(L["Settings are unavailable."])
    end
end

-- The command syntax stays literal; what each command does is translated. Players are shown these
-- three; the others keep working unlisted (docs/DEVELOPER_COMMANDS.md).
local USAGE = {
    { "/ps", L["Open Blueprint Studio."] },
    { "/ps diagnose", L["Open the diagnostics report."] },
    { "/ps console", L["Show or hide the threat windows."] },
}

local function Usage()
    Chat.Print(L["PlateSmith commands (/platesmith or /ps):"])
    for _, line in ipairs(USAGE) do Chat.Print(line[1] .. " - " .. line[2]) end
end

-- The developer commands live in Dev/PlateSmith_Dev (installed by deploy -Dev, never packaged), which registers
-- them here; without it each says so in one line. "console sample" is the console's developer form. Only these
-- names can be registered, so the developer addon adds no command of its own.
local DEV_COMMANDS = {
    status = true, perf = true, performance = true, fetch = true, playerprobe = true, testname = true,
    ["console sample"] = true,
}
local devHandlers = {}

-- handler(value, rawValue): value lower-cased, rawValue as typed. nil removes it. False for a name not listed.
function Dev.RegisterCommand(name, handler)
    if not DEV_COMMANDS[name] or (handler ~= nil and type(handler) ~= "function") then return false end
    devHandlers[name] = handler
    return true
end

local function RunDev(name, value, rawValue)
    local handler = devHandlers[name]
    if handler then return handler(value, rawValue) end
    Chat.Print(L["That's a developer command (PlateSmith_Dev)."])
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

-- /ps mode: who draws the plates. /ps scale: only the Enemies' World design's Plate settings › Scale (the top-level
-- scale is its alias), so it says that rather than "plate scale". Each goes through PS.SetOption, which clamps.
local function Choice(key) return function(value) return S.enumSettings[key][value] and value or nil end end
local settingCommands = {
    mode = Choice("mode"), scale = tonumber,
}

-- /ps friendly names|full|blizzard [players|npcs]: Studio's Show as for one friendly plate type, or both
-- with no type (as before each had its own), through PS.SetFriendlyMode. off: blizzard's stored name, kept as an alias.
local FRIENDLY_TYPES = { players = "friendlyPlayer", player = "friendlyPlayer", npcs = "friendlyNPC", npc = "friendlyNPC" }
local function Friendly(value)
    local mode, plateType
    for typed in value:gmatch("%S+") do
        local word = typed == "blizzard" and "off" or typed
        if S.FRIENDLY.MODES[word] and not mode then
            mode = word
        elseif FRIENDLY_TYPES[word] and not plateType then
            plateType = FRIENDLY_TYPES[word]
        else
            return Usage()
        end
    end
    if not mode or not PS.SetFriendlyMode(plateType, mode) then return Usage() end
    Chat.Print(L["Updated. /ps save keeps it in this profile."])
end

function Commands.Run(text)
    local rawCommand, rawValue = text:match("^%s*(%S*)%s*(.-)%s*$")
    local command, value = rawCommand:lower(), rawValue:lower()
    local devName = (command == "console" and value == "sample") and "console sample" or command
    if DEV_COMMANDS[devName] then
        RunDev(devName, value, rawValue)
    elseif command == "" or command == "studio" or command == "editor" then
        PS.OpenVisualEditor()
    elseif command == "config" or command == "settings" then
        Commands.OpenSettings()
    elseif settingCommands[command] then
        local parsed = settingCommands[command](value)
        if parsed == nil then return Usage() end
        PS.SetOption(command, parsed)
        if command == "scale" then
            Chat.Print(string.format(L["Enemy plates' scale (World design) is %.2f. /ps save keeps it in this profile."],
                PS.GetSettings().scale))
        else
            Chat.Print(L["Updated. /ps save keeps it in this profile."])
        end
    elseif command == "friendly" then
        Friendly(value)
    elseif command == "console" then
        local console = PS.ThreatConsole
        if not console then return Chat.Print(L["Threat windows are unavailable."]) end
        if value == "on" then console:Show() elseif value == "off" then console:Hide() else console:Toggle() end
    elseif command == "diagnose" then
        Diagnose(value)
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
        SetPending(false)
        if PS.OpenOptions then PS.OpenOptions() end
    end
end)
PS.Ticker.SetEnabled("commands.deferred", false)

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
