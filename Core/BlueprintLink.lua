local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Chat = assert(PS.Chat, "PlateSmith Chat missing")
local Ticker = assert(PS.Ticker, "PlateSmith Ticker missing")
local L = PS.L

-- Blueprint chat links, as WeakAuras shares auras. The sender's chat box gets plain text,
-- "[PlateSmith: <name> #<id>]"; an "addon:" hyperlink is local-only and the server refuses one in a
-- chat message. A receiver with PlateSmith turns that text into a local addon link (a chat message
-- filter, using the message's author as the sender); a click whispers the sender's client over hidden
-- addon messages, which answers only for offers it made, in checksummed chunks. What arrives opens
-- Import filled in; nothing applies until the player presses Import selected. Without the filter,
-- /ps fetch <Name-Realm> <id> asks for the same offer.
local BlueprintLink = {}
PS.BlueprintLink = BlueprintLink

local PREFIX = "PlateSmith"
local PROTOCOL = 1
local LINK_ADDON, LINK_KIND = "PlateSmith", "bp"
local LINK_COLOUR = "ff60d4ff"
local PLAIN_START = "[PlateSmith: "
local PLAIN_PATTERN = "%[PlateSmith: ([^%[%]|#]+) #(%w+)%]"
local ID_CHARS, ID_LENGTH = "0123456789abcdefghijklmnopqrstuvwxyz", 4
local MAX_NAME_BYTES = 32
-- The largest share code an export can make (a 64 KiB Blueprint), the most a transfer accepts.
local MAX_BYTES = #"!PSB!" + 3 + math.ceil((PS.MAX_BLUEPRINT_BYTES or 65536) / 3) * 4
-- A data message is "1:D:<id>:<seq>:<payload>", well under the 255-byte addon message limit.
local CHUNK_BYTES = 230
local MAX_CHUNKS = math.ceil(MAX_BYTES / CHUNK_BYTES)
local OFFER_LIFETIME, MAX_OFFERS = 3600, 10
local REQUEST_LIMIT, REQUEST_WINDOW, MAX_REQUESTERS = 3, 60, 50
local MAX_OUTGOING = 3
-- Seconds to wait for the first reply, then between messages once data flows.
local REPLY_TIMEOUT, IDLE_TIMEOUT = 10, 20
-- Messages per second: a prefix may send 10 at once and then 1 a second in instances; outside, about
-- the 800 bytes a second ChatThrottleLib has long used for whispers.
local BURST, RATE_INSTANCE, RATE_WORLD = 10, 1, 4
local THROTTLE_BACKOFF = 1
local TICK_ID, TICK_INTERVAL = "blueprintLink", 0.1
-- Restriction types (PS.Restrictions) that stop addon messages; the map restriction does not.
local BLOCKING = { "chat", "combat", "encounter", "challengeMode", "pvpMatch" }
local FILTER_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
}

local offers, offerOrder = {}, {}
local requestLog = {}
local outgoing = {}
local pending
-- The send allowance refills with time, also while nothing is sent (the ticker is off then).
local tokens, refilledAt, backoffUntil = BURST, nil, 0
local stats = {
    requestsIn = 0, requestsOut = 0, transfersOk = 0, transfersFailed = 0, sendsOk = 0, sendsFailed = 0,
    rateLimited = 0, unknownOffers = 0, ignored = 0, malformed = 0,
}
local lastError = "none"
-- The filter and click route are installed only once the prefix is registered; "none" until then.
local prefixState, filterState, clickRoute = "api-missing", "none", "none"

local function Now() return type(GetTime) == "function" and GetTime() or 0 end

local function UpdateTicker()
    Ticker.SetEnabled(TICK_ID, #outgoing > 0 or pending ~= nil)
end

-- Names ------------------------------------------------------------------------------------------

local function ReadRealm(getter)
    if type(getter) ~= "function" then return nil end
    local ok, realm = pcall(getter)
    realm = ok and Secret.String(realm) or nil
    return realm and (realm:gsub("[%s%-]", "")) or nil
end

local function OwnRealm()
    return ReadRealm(GetNormalizedRealmName) or ReadRealm(GetRealmName)
end

-- "Name-Realm" for a readable character name, adding this realm when none is given; nil for
-- anything that cannot be one (a link or command may hold any text).
local function FullName(name)
    name = Secret.String(name)
    if not name or #name > 64 or name:find("[%s:|%%]") then return nil end
    local character, realm = name:match("^([^%-]+)%-(.+)$")
    if character then return not realm:find("-", 1, true) and name or nil end
    if name:find("-", 1, true) then return nil end
    local own = OwnRealm()
    return own and name .. "-" .. own or nil
end

local function PlayerName()
    local name, realm
    if type(UnitFullName) == "function" then
        local ok, unitName, unitRealm = pcall(UnitFullName, "player")
        if ok then name, realm = Secret.String(unitName), Secret.String(unitRealm) end
    end
    name = name or Secret.ReadName("player")
    if not name then return nil end
    realm = realm and realm:gsub("[%s%-]", "") or ""
    return FullName(realm ~= "" and name .. "-" .. realm or name)
end

-- Character names differ only in case for the server, so a typed name matches the sender's.
local function SameName(left, right)
    return left ~= nil and right ~= nil and left:lower() == right:lower()
end

-- The name without this realm, for chat lines.
local function Display(full)
    local character, realm = tostring(full):match("^([^%-]+)%-(.+)$")
    if character and realm == OwnRealm() then return character end
    return tostring(full)
end

local function ValidId(id)
    return type(id) == "string" and #id >= ID_LENGTH and #id <= 8 and id:match("^[%da-z]+$") ~= nil
end

-- A Blueprint's name as chat text: no link, bracket or id characters, at most 32 bytes (cut before a
-- partial UTF-8 character).
local function LinkName(name)
    name = type(name) == "string" and name or ""
    name = name:gsub("[%c|%[%]#]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #name > MAX_NAME_BYTES then
        name = name:sub(1, MAX_NAME_BYTES):gsub("[\192-\255][\128-\191]*$", ""):gsub("%s+$", "")
    end
    if name == "" then name = L["Blueprint"] end
    return name
end

-- Link text ----------------------------------------------------------------------------------------

function BlueprintLink.PlainText(name, id)
    return string.format("[PlateSmith: %s #%s]", LinkName(name), id)
end

-- The local, clickable form of a link from sender (a full name).
function BlueprintLink.Hyperlink(sender, id, name)
    return string.format("|c%s|Haddon:%s:%s:%s:%s|h[PlateSmith: %s]|h|r", LINK_COLOUR, LINK_ADDON, LINK_KIND,
        sender, id, LinkName(name))
end

-- sender, id from a clicked link's data ("addon:PlateSmith:bp:<sender>:<id>"), or nil.
function BlueprintLink.ParseLink(link)
    link = Secret.String(link)
    if not link then return nil end
    local sender, id = link:match("^addon:" .. LINK_ADDON .. ":" .. LINK_KIND .. ":([^:|]+):([^:|]+)$")
    sender = FullName(sender)
    if not sender or not ValidId(id) then return nil end
    return sender, id
end

-- Chat message filter: each "[PlateSmith: <name> #<id>]" in a readable message becomes a link to its
-- author (the player for a whisper they sent). A protected message or author is left as it is.
function BlueprintLink.ChatFilter(_, event, message, author, ...)
    local text = Secret.String(message)
    if not text or not text:find(PLAIN_START, 1, true) then return end
    local sender
    if event == "CHAT_MSG_WHISPER_INFORM" then sender = PlayerName() else sender = FullName(author) end
    if not sender then return end
    local changed = false
    local result = text:gsub(PLAIN_PATTERN, function(name, id)
        if not ValidId(id) then return nil end
        changed = true
        return BlueprintLink.Hyperlink(sender, id, name)
    end)
    if not changed then return end
    return false, result, author, ...
end

-- Restrictions ---------------------------------------------------------------------------------------

-- True while the client restricts chat or addon messages (instance combat, encounters, keystones, PvP
-- matches) or will not say: nothing is sent or requested then.
function BlueprintLink.Restricted()
    local api = type(C_ChatInfo) == "table" and C_ChatInfo.InChatMessagingLockdown
    if type(api) == "function" then
        local ok, locked = pcall(api)
        if not ok or not Secret.IsReadable(locked) or locked == true then return true end
    end
    local report = PS.Restrictions and PS.Restrictions.Report() or {}
    for _, key in ipairs(BLOCKING) do
        local state = report[key]
        if state ~= nil and state ~= "clear" then return true end
    end
    return false
end

local function SayRestricted()
    lastError = "restricted"
    Chat.Print(L["Blueprint links can't be used right now (combat, an encounter or chat restrictions). Try again later."])
end

-- Sending ------------------------------------------------------------------------------------------

-- "ok", "throttled", "restricted", "offline" or "send-failed" for one addon message.
local function Send(message, target)
    local api = type(C_ChatInfo) == "table" and C_ChatInfo.SendAddonMessage
    if type(api) ~= "function" then return "send-failed" end
    local ok, result = pcall(api, PREFIX, message, "WHISPER", target)
    if not ok or not Secret.IsReadable(result) then return "send-failed" end
    if result == nil or result == true then return "ok" end
    if result == false then return "send-failed" end
    local enum = type(Enum) == "table" and type(Enum.SendAddonMessageResult) == "table" and Enum.SendAddonMessageResult or {}
    if result == (enum.Success or 0) then return "ok" end
    if result == (enum.AddonMessageThrottle or 3) or result == (enum.ChannelThrottle or 8) then return "throttled" end
    if result == (enum.AddOnMessageLockdown or 11) then return "restricted" end
    if result == (enum.TargetOffline or 12) then return "offline" end
    return "send-failed"
end

-- Adler-32 of the text as eight hex digits.
function BlueprintLink._Checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

-- The header then the data messages for a share code.
function BlueprintLink._Chunk(code, id)
    local count = math.ceil(#code / CHUNK_BYTES)
    local messages = { string.format("%d:H:%s:%d:%d:%s", PROTOCOL, id, count, #code, BlueprintLink._Checksum(code)) }
    for seq = 1, count do
        messages[#messages + 1] = string.format("%d:D:%s:%d:%s", PROTOCOL, id, seq,
            code:sub((seq - 1) * CHUNK_BYTES + 1, seq * CHUNK_BYTES))
    end
    return messages
end

local function PruneOffers(now)
    for index = #offerOrder, 1, -1 do
        local id = offerOrder[index]
        if offers[id].expires <= now then
            offers[id] = nil
            table.remove(offerOrder, index)
        end
    end
end

local function NewId()
    for _ = 1, 20 do
        local characters = {}
        for index = 1, ID_LENGTH do
            local pick = math.random(1, #ID_CHARS)
            characters[index] = ID_CHARS:sub(pick, pick)
        end
        local id = table.concat(characters)
        if not offers[id] then return id end
    end
end

-- Offers the Blueprint as exported now under the active profile's name: the chat text, or nil and a
-- reason. The same Blueprint offered again keeps its id and starts its hour again.
function BlueprintLink.Offer()
    local code, reason = PS.ExportShareCode()
    if not code then return nil, reason end
    if #code > MAX_BYTES then return nil, "blueprint is too large" end
    local now = Now()
    PruneOffers(now)
    local name = LinkName(PS.Profiles and PS.Profiles.Active())
    for index, id in ipairs(offerOrder) do
        local offer = offers[id]
        if offer.code == code and offer.name == name then
            offer.expires = now + OFFER_LIFETIME
            table.remove(offerOrder, index)
            offerOrder[#offerOrder + 1] = id
            return BlueprintLink.PlainText(name, id), id
        end
    end
    while #offerOrder >= MAX_OFFERS do offers[table.remove(offerOrder, 1)] = nil end
    local id = NewId()
    if not id then return nil, "no free link id" end
    offers[id] = { code = code, name = name, expires = now + OFFER_LIFETIME }
    offerOrder[#offerOrder + 1] = id
    return BlueprintLink.PlainText(name, id), id
end

-- Puts text in the open chat box, or opens one with it. Never sends.
local function InsertText(text)
    local util = type(ChatFrameUtil) == "table" and ChatFrameUtil or nil
    local insert = util and util.InsertLink or ChatEdit_InsertLink
    local open = util and util.OpenChat or ChatFrame_OpenChat
    if type(insert) == "function" then
        local ok, inserted = pcall(insert, text)
        if ok and Secret.IsReadable(inserted) and inserted == true then return true end
    end
    if type(open) == "function" and pcall(open, text) then return true end
    return false
end

-- Export's Link in chat: offers the Blueprint and puts its text in the chat box for the player to send.
function BlueprintLink.InsertInChat()
    if BlueprintLink.Restricted() then return false, SayRestricted() end
    if prefixState ~= "registered" then
        Chat.Print(L["Blueprint links are unavailable on this client."])
        return false
    end
    local text, reason = BlueprintLink.Offer()
    if not text then
        Chat.Print(string.format(L["Blueprint export failed: %s"], tostring(reason)))
        return false
    end
    if not InsertText(text) then
        Chat.Print(L["Open a chat box, then press Link in chat again."])
        return false
    end
    Chat.Print(L["Press Enter to share the link. It works for an hour while you stay online."])
    return true, text
end

-- Requests from one player: REQUEST_LIMIT a REQUEST_WINDOW, counted before the offer is looked up so ids
-- cannot be guessed quickly; at most MAX_REQUESTERS players are tracked at once.
local function AllowRequest(from, now)
    local log = requestLog[from]
    if not log then
        local tracked = 0
        for name, entry in pairs(requestLog) do
            if now - entry.start >= REQUEST_WINDOW then requestLog[name] = nil else tracked = tracked + 1 end
        end
        if tracked >= MAX_REQUESTERS then return false end
        log = { start = now, count = 0 }
        requestLog[from] = log
    elseif now - log.start >= REQUEST_WINDOW then
        log.start, log.count = now, 0
    end
    if log.count >= REQUEST_LIMIT then return false end
    log.count = log.count + 1
    return true
end

local function HandleRequest(from, body, now)
    stats.requestsIn = stats.requestsIn + 1
    if not ValidId(body) then stats.malformed = stats.malformed + 1 return end
    if not AllowRequest(from, now) then stats.rateLimited = stats.rateLimited + 1 return end
    PruneOffers(now)
    local offer = offers[body]
    if not offer then stats.unknownOffers = stats.unknownOffers + 1 return end
    if BlueprintLink.Restricted() then lastError = "restricted" return end
    for _, transfer in ipairs(outgoing) do
        if transfer.to == from then return end
    end
    if #outgoing >= MAX_OUTGOING then stats.ignored = stats.ignored + 1 return end
    outgoing[#outgoing + 1] = { to = from, id = body, messages = BlueprintLink._Chunk(offer.code, body), next = 1 }
    Chat.Print(string.format(L["Sending your Blueprint %s to %s."], offer.name, Display(from)))
    UpdateTicker()
end

local function SendStep(now)
    local transfer = outgoing[1]
    if not transfer then return end
    if BlueprintLink.Restricted() then
        stats.sendsFailed = stats.sendsFailed + #outgoing
        for index = #outgoing, 1, -1 do outgoing[index] = nil end
        lastError = "restricted"
        Chat.Print(L["Stopped sending a Blueprint: chat is restricted right now."])
        return
    end
    local inInstance = false
    if type(IsInInstance) == "function" then
        local ok, value = pcall(IsInInstance)
        inInstance = not ok or not Secret.IsReadable(value) or value == true
    end
    tokens = math.min(BURST, tokens + (now - (refilledAt or now)) * (inInstance and RATE_INSTANCE or RATE_WORLD))
    refilledAt = now
    while transfer and tokens >= 1 and now >= backoffUntil do
        local state = Send(transfer.messages[transfer.next], transfer.to)
        if state == "ok" then
            tokens = tokens - 1
            transfer.next = transfer.next + 1
            if transfer.next > #transfer.messages then
                table.remove(outgoing, 1)
                stats.sendsOk = stats.sendsOk + 1
                transfer = outgoing[1]
            end
        elseif state == "throttled" then
            tokens, backoffUntil = 0, now + THROTTLE_BACKOFF
        else
            table.remove(outgoing, 1)
            stats.sendsFailed = stats.sendsFailed + 1
            lastError = state
            transfer = outgoing[1]
        end
    end
end

-- Receiving ----------------------------------------------------------------------------------------

local FAILURE_TEXT = {
    timeout = L["%s didn't respond: they may be offline or busy, or the link has expired."],
    stalled = L["The Blueprint from %s stopped arriving. Try the link again."],
    ["checksum-mismatch"] = L["The Blueprint from %s arrived damaged. Try the link again."],
    oversize = L["The Blueprint from %s is too large to accept."],
    malformed = L["%s sent something PlateSmith can't read."],
    ["invalid-blueprint"] = L["%s sent something that isn't a PlateSmith Blueprint."],
}

local function Fail(reason)
    local from = pending.from
    pending = nil
    stats.transfersFailed = stats.transfersFailed + 1
    lastError = reason
    Chat.Print(string.format(FAILURE_TEXT[reason], Display(from)))
    UpdateTicker()
end

-- Opens Import with the text in it. Never imports.
local function OpenImport(text, from)
    local options = PS.Options
    if type(options) ~= "table" or type(options.ShowImportBlueprintText) ~= "function" then
        Chat.Print(L["Blueprint Studio is unavailable."])
        return false
    end
    options:ShowImportBlueprintText(text)
    Chat.Print(string.format(L["%s's Blueprint is in Import. Choose its sections and press Import selected to use it."],
        Display(from)))
    return true
end

local function TryComplete()
    local header = pending.header
    if not header or pending.received < header.count then return end
    local parts = {}
    for seq = 1, header.count do
        if not pending.chunks[seq] then return end
        parts[seq] = pending.chunks[seq]
    end
    local text = table.concat(parts)
    if #text ~= header.bytes or BlueprintLink._Checksum(text) ~= header.checksum then return Fail("checksum-mismatch") end
    -- The normal decode: a share code that names a PlateSmith Blueprint. Import validates it fully.
    local describe = PS.BlueprintDescribe
    if not text:match("^!PSB%d+!") or type(describe) ~= "function" or not describe(text) then
        return Fail("invalid-blueprint")
    end
    local from = pending.from
    pending = nil
    stats.transfersOk = stats.transfersOk + 1
    UpdateTicker()
    OpenImport(text, from)
end

-- Only the pending request's sender and id are heard; anything else is ignored.
local function Expected(from, id)
    return pending ~= nil and SameName(from, pending.from) and id == pending.id
end

local function HandleHeader(from, body, now)
    local id, count, bytes, checksum = body:match("^([^:]+):(%d+):(%d+):(%x+)$")
    if not Expected(from, id) then stats.ignored = stats.ignored + 1 return end
    count, bytes = tonumber(count), tonumber(bytes)
    if bytes > MAX_BYTES or count > MAX_CHUNKS then return Fail("oversize") end
    if pending.header then return end
    if bytes < 1 or count < 1 or #checksum ~= 8 then return Fail("malformed") end
    pending.header = { count = count, bytes = bytes, checksum = checksum:lower() }
    pending.deadline = now + IDLE_TIMEOUT
    -- Data that came first beyond the announced count is dropped.
    for seq, payload in pairs(pending.chunks) do
        if seq > count then
            pending.chunks[seq] = nil
            pending.received, pending.bytes = pending.received - 1, pending.bytes - #payload
        end
    end
    if pending.bytes > bytes then return Fail("oversize") end
    if count > 20 then Chat.Print(string.format(L["Receiving %s's Blueprint..."], Display(from))) end
    TryComplete()
end

local function HandleData(from, body, now)
    local id, seq, payload = body:match("^([^:]+):(%d+):(.+)$")
    if not Expected(from, id) then stats.ignored = stats.ignored + 1 return end
    seq = tonumber(seq)
    local limit = pending.header and pending.header.count or MAX_CHUNKS
    if seq < 1 or seq > limit or #payload > CHUNK_BYTES or not payload:match("^[%w%+/=!]+$") then
        stats.malformed, lastError = stats.malformed + 1, "malformed"
        return
    end
    if pending.chunks[seq] then return end
    pending.chunks[seq] = payload
    pending.received, pending.bytes = pending.received + 1, pending.bytes + #payload
    pending.deadline = now + IDLE_TIMEOUT
    if pending.bytes > (pending.header and pending.header.bytes or MAX_BYTES) then return Fail("oversize") end
    TryComplete()
end

-- CHAT_MSG_ADDON: only readable whispers on PlateSmith's prefix, from a valid name, are read.
function BlueprintLink.OnAddonMessage(prefix, text, channel, sender)
    if Secret.String(prefix) ~= PREFIX then return end
    text, channel = Secret.String(text), Secret.String(channel)
    local from = FullName(sender)
    if not text or channel ~= "WHISPER" or not from or #text > 255 then return end
    local version, kind, body = text:match("^(%d+):(%u):(.*)$")
    if not version then stats.malformed = stats.malformed + 1 return end
    if tonumber(version) ~= PROTOCOL then lastError = "unsupported-version" return end
    local now = Now()
    if kind == "R" then
        HandleRequest(from, body, now)
    elseif kind == "H" then
        HandleHeader(from, body, now)
    elseif kind == "D" then
        HandleData(from, body, now)
    else
        stats.malformed = stats.malformed + 1
    end
end

-- Asks sender (Name or Name-Realm) for offer id; the player's own link opens without asking.
function BlueprintLink.Request(sender, id)
    local from = FullName(sender)
    id = type(id) == "string" and id:gsub("^#", ""):lower() or nil
    if not from or not ValidId(id) then
        Chat.Print(L["That Blueprint link is not valid."])
        return false
    end
    if SameName(from, PlayerName()) then
        PruneOffers(Now())
        local offer = offers[id]
        if not offer then
            Chat.Print(L["That Blueprint link has expired."])
            return false
        end
        return OpenImport(offer.code, from)
    end
    if BlueprintLink.Restricted() then return false, SayRestricted() end
    if prefixState ~= "registered" then
        Chat.Print(L["Blueprint links are unavailable on this client."])
        return false
    end
    if pending then
        Chat.Print(string.format(L["Still waiting for %s's Blueprint. Try again when it arrives."], Display(pending.from)))
        return false
    end
    local state = Send(string.format("%d:R:%s", PROTOCOL, id), from)
    if state ~= "ok" then
        lastError = state
        if state == "restricted" then
            SayRestricted()
        elseif state == "offline" then
            Chat.Print(string.format(L["%s is offline."], Display(from)))
        else
            Chat.Print(L["Couldn't ask for the Blueprint. Try again in a moment."])
        end
        return false
    end
    stats.requestsOut = stats.requestsOut + 1
    local now = Now()
    pending = { from = from, id = id, deadline = now + REPLY_TIMEOUT, chunks = {}, received = 0, bytes = 0 }
    Chat.Print(string.format(L["Asking %s for the Blueprint..."], Display(from)))
    UpdateTicker()
    return true
end

-- A click on any hyperlink: true when it was a PlateSmith Blueprint link.
function BlueprintLink.OnLinkClicked(link)
    local sender, id = BlueprintLink.ParseLink(link)
    if not sender then return false end
    BlueprintLink.Request(sender, id)
    return true
end

local function Step(_, now)
    SendStep(now)
    if pending and now >= pending.deadline then
        Fail((pending.header or pending.received > 0) and "stalled" or "timeout")
    end
    UpdateTicker()
end

-- Diagnostics ---------------------------------------------------------------------------------------

-- linkPath: addon-link (the filter makes local addon links; clicks arrive through EventRegistry),
-- filter (the same links; clicks through a SetItemRef hook), command (no filter or click route: only
-- /ps fetch), none (no addon messages).
function BlueprintLink.Report()
    local path = "command"
    if prefixState ~= "registered" then
        path = "none"
    elseif filterState == "installed" and clickRoute == "event-registry" then
        path = "addon-link"
    elseif filterState == "installed" and clickRoute == "hook" then
        path = "filter"
    end
    PruneOffers(Now())
    return {
        linkPath = path, prefix = prefixState, chatFilter = filterState, clickRoute = clickRoute,
        state = BlueprintLink.Restricted() and "restricted" or "clear",
        offers = #offerOrder, sending = #outgoing, waiting = pending ~= nil,
        requestsIn = stats.requestsIn, requestsOut = stats.requestsOut,
        transfersOk = stats.transfersOk, transfersFailed = stats.transfersFailed,
        sendsOk = stats.sendsOk, sendsFailed = stats.sendsFailed, rateLimited = stats.rateLimited,
        unknownOffers = stats.unknownOffers, ignored = stats.ignored, malformed = stats.malformed,
        lastError = lastError,
    }
end

-- Setup ---------------------------------------------------------------------------------------------

local function RegisterPrefix()
    local api = type(C_ChatInfo) == "table" and C_ChatInfo or nil
    if not api or type(api.RegisterAddonMessagePrefix) ~= "function" or type(api.SendAddonMessage) ~= "function" then
        return "api-missing"
    end
    local ok, result = pcall(api.RegisterAddonMessagePrefix, PREFIX)
    if not ok then return "error" end
    if not Secret.IsReadable(result) then return "protected" end
    local enum = type(Enum) == "table" and type(Enum.RegisterAddonMessagePrefixResult) == "table"
        and Enum.RegisterAddonMessagePrefixResult or {}
    -- Older clients answer true; a duplicate is still registered.
    if result == true or (result ~= nil and (result == (enum.Success or 0) or result == enum.DuplicatePrefix)) then
        return "registered"
    end
    if type(api.IsAddonMessagePrefixRegistered) == "function" then
        local okRegistered, registered = pcall(api.IsAddonMessagePrefixRegistered, PREFIX)
        if okRegistered and Secret.IsReadable(registered) and registered == true then return "registered" end
    end
    return "rejected"
end

local function InstallFilter()
    local add = type(ChatFrameUtil) == "table" and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if type(add) ~= "function" then return "api-missing" end
    for _, event in ipairs(FILTER_EVENTS) do
        if not pcall(add, event, BlueprintLink.ChatFilter) then return "error" end
    end
    return "installed"
end

-- EventRegistry's SetItemRef callback is how the client hands addon links to addons; a secure hook on
-- SetItemRef is the fallback. SetItemRef itself is never replaced.
local function InstallClickRoute()
    local registry = EventRegistry
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        local ok = pcall(registry.RegisterCallback, registry, "SetItemRef", function(_, link)
            BlueprintLink.OnLinkClicked(link)
        end, BlueprintLink)
        if ok then return "event-registry" end
    end
    if type(hooksecurefunc) == "function" and type(SetItemRef) == "function" then
        if pcall(hooksecurefunc, "SetItemRef", function(link) BlueprintLink.OnLinkClicked(link) end) then return "hook" end
    end
    return "api-missing"
end

prefixState = RegisterPrefix()
if prefixState == "registered" then
    local frame = CreateFrame("Frame")
    PS._RegisterEvent(frame, "CHAT_MSG_ADDON", "BlueprintLink")
    frame:SetScript("OnEvent", function(_, _, ...) BlueprintLink.OnAddonMessage(...) end)
    filterState = InstallFilter()
    clickRoute = InstallClickRoute()
end
Ticker.Register(TICK_ID, TICK_INTERVAL, Step)
Ticker.SetEnabled(TICK_ID, false)
