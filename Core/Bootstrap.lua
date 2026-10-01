local addonName, PS = ...

PS = PS or {}
_G.PlateSmith = PS
PS.RUNTIME_BUILD = "1.1.0"

-- The two clients the TOC targets: Forever (1.x interface) and retail (Midnight).
function PS.ClientFlavor()
    local interface = type(GetBuildInfo) == "function" and select(4, GetBuildInfo()) or nil
    return type(interface) == "number" and interface >= 100000 and "retail" or "forever"
end

-- Chat loads next; these paths only run after every file has loaded.
local function Print(message)
    if PS.Chat then PS.Chat.Print(message) end
end

function PS._RegisterEvent(frame, event, scope)
    if not frame or type(frame.RegisterEvent) ~= "function" then return false end
    local stage = tostring(scope or "unknown") .. " -> " .. tostring(event or "unknown")
    PS._lastEventRegistration = stage
    PS._activeEventRegistration = stage
    local ok, registered = pcall(frame.RegisterEvent, frame, event)
    PS._activeEventRegistration = nil
    if not ok or registered == false then
        Print("event registration rejected at " .. stage .. ": " .. tostring(ok and "returned false" or registered))
        return false
    end
    return true
end

local function HandleBlockedAction(blockedAddon, blockedFunction)
    if blockedAddon ~= addonName and blockedAddon ~= "PlateSmith" then return end
    local detail = tostring(blockedFunction or "unknown")
    local message = "client blocked protected action: " .. detail
    if detail:find("RegisterEvent", 1, true) then
        local stage = PS._activeEventRegistration or PS._lastEventRegistration
        if stage then message = message .. " during " .. stage end
    end
    PS._lastBlockedAction = message
    Print(message .. ".")
end

-- This listener is intentionally the first PlateSmith runtime frame created.
-- It must exist before any other addon file can attempt a protected operation.
local bootstrapFrame = CreateFrame("Frame")
bootstrapFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
bootstrapFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
bootstrapFrame:RegisterEvent("PLAYER_LOGIN")
bootstrapFrame:SetScript("OnEvent", function(_, event, blockedAddon, blockedFunction)
    if event == "PLAYER_LOGIN" then
        if PS.Chat then PS.Chat.Flush() end
    else
        HandleBlockedAction(blockedAddon, blockedFunction)
    end
end)

PS._Diagnostics = {
    HandleBlockedAction = HandleBlockedAction,
}
