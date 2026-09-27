local _, PS = ...

-- The single route for chat output and error reports. Messages printed
-- before the chat frame exists are queued and flushed at login.
local Chat = {}
PS.Chat = Chat

local PREFIX = "|cff60d4ffPlateSmith:|r "
local pending = {}

local function ChatFrame()
    return DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" and DEFAULT_CHAT_FRAME or nil
end

function Chat.Print(message)
    local text = PREFIX .. tostring(message)
    local frame = ChatFrame()
    if frame then
        frame:AddMessage(text)
        return true
    end
    pending[#pending + 1] = text
    return false
end

function Chat.Flush()
    local frame = ChatFrame()
    if not frame then return end
    for index = 1, #pending do frame:AddMessage(pending[index]) end
    for index = #pending, 1, -1 do pending[index] = nil end
end

-- Reports go to the active error handler (BugSack when installed) and name
-- the build so a pasted report identifies the exact copy that failed.
function Chat.ReportError(scope, message)
    local text = string.format("PlateSmith %s %s: %s", tostring(PS.RUNTIME_BUILD or "unknown"),
        tostring(scope), tostring(message))
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    if handler then
        handler(text)
    else
        Chat.Print("|cffff5555" .. text .. "|r")
    end
    return text
end
