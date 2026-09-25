local addonName, PS = ...

PS = PS or {}
_G.PlateSmith = PS
PS.RUNTIME_BUILD = "0.1.0-alpha.2"

local pendingMessages = {}
local registrationHistory = {}
local MAX_HISTORY = 12

local function Chat(message)
    local text = "|cff55ccffPlateSmith:|r " .. tostring(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(text)
        return true
    end
    pendingMessages[#pendingMessages + 1] = text
    return false
end

local function Flush()
    if not DEFAULT_CHAT_FRAME or type(DEFAULT_CHAT_FRAME.AddMessage) ~= "function" then return end
    for index = 1, #pendingMessages do DEFAULT_CHAT_FRAME:AddMessage(pendingMessages[index]) end
    for index = #pendingMessages, 1, -1 do pendingMessages[index] = nil end
end

local function RememberRegistration(scope, event)
    local stage = tostring(scope or "unknown") .. " -> " .. tostring(event or "unknown")
    PS._lastEventRegistration = stage
    registrationHistory[#registrationHistory + 1] = stage
    if #registrationHistory > MAX_HISTORY then table.remove(registrationHistory, 1) end
    return stage
end

function PS._RegisterEvent(frame, event, scope)
    if not frame or type(frame.RegisterEvent) ~= "function" then return false end
    local stage = RememberRegistration(scope, event)
    PS._activeEventRegistration = stage
    local ok, registered = pcall(frame.RegisterEvent, frame, event)
    PS._activeEventRegistration = nil
    if not ok or registered == false then
        Chat("event registration rejected at " .. stage .. ": " .. tostring(ok and "returned false" or registered))
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
    Chat(message .. ".")
end

-- This listener is intentionally the first PlateSmith runtime frame created.
-- It must exist before any other addon file can attempt a protected operation.
local diagnosticFrame = CreateFrame("Frame")
diagnosticFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
diagnosticFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
diagnosticFrame:RegisterEvent("PLAYER_LOGIN")
diagnosticFrame:SetScript("OnEvent", function(_, event, blockedAddon, blockedFunction)
    if event == "PLAYER_LOGIN" then
        Flush()
    else
        HandleBlockedAction(blockedAddon, blockedFunction)
    end
end)

PS.FlushEarlyDiagnostics = Flush
PS._Diagnostics = {
    HandleBlockedAction = HandleBlockedAction,
    RegistrationHistory = registrationHistory,
}
