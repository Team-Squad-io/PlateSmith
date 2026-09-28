-- Other nameplate addons: which are running (the plate runtime's provider check reads this), and
-- the once-a-session notice that explains the overlay and offers to disable them.
local _, PS = ...
local L = PS.L
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local Layout = assert(PS.UI and PS.UI.Layout, "PlateSmith Layout missing")

local Conflicts = {}
PS.Conflicts = Conflicts

local function Loaded(name)
    local check = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(check) ~= "function" then return false end
    local ok, loaded = pcall(check, name)
    return ok and Secret.IsReadable(loaded) and loaded and true or false
end

-- ElvUI and Tukui are whole UIs: they count only while their nameplates module is on. An answer
-- that cannot be read (another version's layout, an error) is nil, and nil never warns.
local function ElvUIPlates()
    local ok, enabled = pcall(function()
        local elv = _G.ElvUI
        local engine = type(elv) == "table" and elv[1]
        return engine.private.nameplates.enable
    end)
    if ok and type(enabled) == "boolean" then return enabled end
end

local function TukuiPlates()
    local ok, enabled = pcall(function()
        local tukui = _G.Tukui
        local config
        if type(tukui.unpack) == "function" then
            config = select(2, tukui:unpack())
        else
            config = tukui[2]
        end
        return config.NamePlates.Enable
    end)
    if ok and type(enabled) == "boolean" then return enabled end
end

-- In provider order: the first loaded one is the plate provider in mode auto. Labels are the
-- addons' own names (brand names stay literal).
Conflicts.KNOWN = {
    { addon = "Kui_Nameplates", label = "KuiNameplates" },
    { addon = "Plater", label = "Plater" },
    { addon = "TidyPlates", label = "Tidy Plates" },
    { addon = "TidyPlates_ThreatPlates", label = "Threat Plates" },
    { addon = "NeatPlates", label = "NeatPlates" },
    { addon = "Platynator", label = "Platynator" },
    { addon = "nPlates", label = "nPlates" },
    { addon = "ElvUI", label = "ElvUI", suite = true, check = ElvUIPlates },
    { addon = "Tukui", label = "Tukui", suite = true, check = TukuiPlates },
}

local function Running(entry)
    if not Loaded(entry.addon) then return false end
    return entry.check == nil or entry.check() == true
end

-- The first running nameplate addon's folder name, or nil. Called per plate: no allocation.
function Conflicts.Provider()
    for _, entry in ipairs(Conflicts.KNOWN) do
        if Running(entry) then return entry.addon end
    end
end

-- Every running nameplate addon's entry, in list order.
function Conflicts.Detect()
    local found = {}
    for _, entry in ipairs(Conflicts.KNOWN) do
        if Running(entry) then found[#found + 1] = entry end
    end
    return found
end

-- "A", "A and B", "A, B and C", through translatable list formats.
function Conflicts.JoinNames(names)
    local count = #names
    if count == 0 then return "" end
    if count == 1 then return tostring(names[1]) end
    local text = tostring(names[1])
    for index = 2, count - 1 do text = string.format(L["%s, %s"], text, tostring(names[index])) end
    return string.format(L["%s and %s"], text, tostring(names[count]))
end

-- A dismissal belongs to this exact set of addons; a new set shows the notice again.
function Conflicts.SetKey(found)
    local names = {}
    for index, entry in ipairs(found) do names[index] = entry.addon end
    table.sort(names)
    return table.concat(names, "+")
end

local function NoticeState()
    local state = type(PS.GetState) == "function" and PS.GetState() or nil
    if type(state) ~= "table" then return nil end
    if type(state.conflictNotice) ~= "table" then state.conflictNotice = { dismissed = {} } end
    if type(state.conflictNotice.dismissed) ~= "table" then state.conflictNotice.dismissed = {} end
    return state.conflictNotice
end

function Conflicts.IsDismissed(key)
    local notice = NoticeState()
    return notice ~= nil and notice.dismissed[key] == true
end

function Conflicts.Dismiss(key)
    local notice = NoticeState()
    if notice then notice.dismissed[key] = true end
end

local function Mode()
    local db = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    return type(db) == "table" and db.mode or "auto"
end

-- What the notice says for these addons: title, body, warning (two or more), suite (ElvUI or
-- Tukui: turn their plates off instead), hint, and the addons a button may disable.
function Conflicts.Notice(found, mode)
    local labels, suites, removable = {}, {}, {}
    for _, entry in ipairs(found) do
        labels[#labels + 1] = entry.label
        if entry.suite then suites[#suites + 1] = entry.label else removable[#removable + 1] = entry end
    end
    local names = Conflicts.JoinNames(labels)
    local own = mode == "own"
    local notice = { key = Conflicts.SetKey(found), own = own, disable = removable,
        title = L["Another nameplate addon is running"], hint = L["Change later: /ps mode"],
        keep = own and L["Close"] or L["Keep overlay"] }
    if own then
        notice.body = string.format(L["PlateSmith found %s. PlateSmith is set to draw its own plates (/ps mode own), "
            .. "so you may see two sets of plates. Disable %s and reload, or use /ps mode auto."], names, names)
    else
        notice.body = string.format(L["PlateSmith found %s. PlateSmith is running as a light overlay on its plates "
            .. "(quest markers and threat), so you don't see two sets of plates. To use PlateSmith's own plates, "
            .. "disable %s and reload."], names, names)
    end
    if #found >= 2 then
        notice.warning = string.format(L["Warning: %s will overlap each other. Keep only one of them enabled."], names)
    end
    if #suites > 0 then
        notice.suite = string.format(L["%s: turn off its nameplates in its own settings instead of disabling "
            .. "the whole addon."], Conflicts.JoinNames(suites))
    end
    return notice
end

-- Disables the addon for this character, then reloads. A failed disable does not reload.
function Conflicts.DisableAndReload(entry)
    local disable = C_AddOns and C_AddOns.DisableAddOn or _G.DisableAddOn
    if type(disable) ~= "function" then return false end
    local ok, reason = pcall(disable, entry.addon, Secret.ReadName("player"))
    if not ok then
        PS.Chat.ReportError("disable " .. entry.addon, reason)
        return false
    end
    local reload = C_UI and C_UI.Reload or _G.ReloadUI
    if type(reload) == "function" then reload() end
    return true
end

-- A reload needs confirming, through PlateSmith's own dialog (never a StaticPopup).
function Conflicts.RequestDisable(entry)
    local options = PS.Options
    if not options or type(options.ConfirmStudioAction) ~= "function" then
        PS.Chat.Print(string.format(L["Disable %s in the AddOns list, then reload."], entry.label))
        return false
    end
    options:ConfirmStudioAction(string.format(L["Disable %s for this character and reload the interface?"], entry.label),
        L["Disable and reload"], function() Conflicts.DisableAndReload(entry) end)
    return true
end

local WIDTH, PAD, GAP, TOP, BUTTON_H = 460, 18, 10, 44, 24
local INK = Layout.PALETTES.blizzard.ink

local function TextHeight(text, value)
    local height = text.GetStringHeight and text:GetStringHeight()
    if type(height) == "number" and height > 0 then return height end
    return math.max(1, math.ceil(#value / 70)) * 14
end

local function TextBlock(frame, role)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    if text.SetJustifyV then text:SetJustifyV("TOP") end
    if text.SetWordWrap then text:SetWordWrap(true) end
    text:SetWidth(WIDTH - 2 * PAD)
    local ink = INK[role]
    text:SetTextColor(ink[1], ink[2], ink[3])
    return text
end

local function CreateNotice()
    local frame = Window.Create("PlateSmithConflictNotice", { width = WIDTH, height = 240,
        title = L["Another nameplate addon is running"] })
    local title = INK.title
    frame.title:SetTextColor(title[1], title[2], title[3])
    frame.body, frame.warning = TextBlock(frame, "label"), TextBlock(frame, "error")
    frame.suite, frame.hint = TextBlock(frame, "label"), TextBlock(frame, "muted")
    local half = (WIDTH - 2 * PAD - GAP) / 2
    frame.disableButtons = {}
    for index = 1, 2 do
        frame.disableButtons[index] = Window.Button(frame, "", half, BUTTON_H, function(button)
            if button.entry then Conflicts.RequestDisable(button.entry) end
        end)
    end
    frame.disableMenu = Window.Button(frame, L["Disable an addon and reload..."], WIDTH - 2 * PAD, BUTTON_H,
        function(button)
            local items = {}
            for _, entry in ipairs(frame.notice and frame.notice.disable or {}) do
                items[#items + 1] = { text = string.format(L["Disable %s and reload"], entry.label),
                    func = function() Conflicts.RequestDisable(entry) end }
            end
            PS.UI.Menu.Toggle(button, items, { width = WIDTH - 2 * PAD })
        end)
    frame.keep = Window.Button(frame, L["Keep overlay"], half, BUTTON_H, function() frame:Hide() end)
    frame.dismiss = Window.Button(frame, L["Don't show again"], half, BUTTON_H, function()
        if frame.notice then Conflicts.Dismiss(frame.notice.key) end
        frame:Hide()
    end)
    return frame
end

local function Render(frame, notice)
    frame.notice = notice
    local y = -TOP
    for _, key in ipairs({ "body", "warning", "suite", "hint" }) do
        local text, value = frame[key], notice[key]
        text:ClearAllPoints()
        if value then
            text:SetText(value)
            text:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
            text:Show()
            y = y - TextHeight(text, value) - GAP
        else
            text:SetText("")
            text:Hide()
        end
    end
    y = y - 4
    local disable = notice.disable
    for index, button in ipairs(frame.disableButtons) do
        local entry = #disable <= 2 and disable[index] or nil
        button.entry = entry
        button:ClearAllPoints()
        if entry then
            button:SetText(string.format(L["Disable %s and reload"], entry.label))
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (index - 1) * (button:GetWidth() + GAP), y)
            button:Show()
        else
            button:Hide()
        end
    end
    frame.disableMenu:ClearAllPoints()
    if #disable > 2 then
        frame.disableMenu:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
        frame.disableMenu:Show()
    else
        frame.disableMenu:Hide()
    end
    if #disable > 0 then y = y - BUTTON_H - GAP end
    frame.keep:SetText(notice.keep)
    frame.keep:ClearAllPoints()
    frame.keep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
    frame.dismiss:ClearAllPoints()
    frame.dismiss:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
    frame:SetHeight(math.floor(-y + BUTTON_H + PAD + 0.5))
end

function Conflicts.ShowNotice(found)
    local frame = Conflicts.frame or CreateNotice()
    Conflicts.frame = frame
    Render(frame, Conflicts.Notice(found, Mode()))
    frame:Show()
    return frame
end

-- Once a session, never in combat (it waits for PLAYER_REGEN_ENABLED) and never in a loading
-- screen (it waits LOADING_DELAY seconds after PLAYER_ENTERING_WORLD).
local LOADING_DELAY = 2
local session = { done = false, readyAt = nil, waitingCombat = false }
Conflicts._session = session

function Conflicts.TryShow()
    if session.done then return false end
    if Secret.InCombat() then
        session.waitingCombat = true
        return false
    end
    session.waitingCombat = false
    local found = Conflicts.Detect()
    if #found == 0 then return false end
    session.done = true
    if Conflicts.IsDismissed(Conflicts.SetKey(found)) then return false end
    Conflicts.ShowNotice(found)
    return true
end

local function Now() return type(GetTime) == "function" and GetTime() or 0 end

PS.Ticker.Register("conflicts.notice", 0.5, function()
    if session.readyAt and Now() < session.readyAt then return end
    session.readyAt = nil
    PS.Ticker.SetEnabled("conflicts.notice", false)
    Conflicts.TryShow()
end)
PS.Ticker.SetEnabled("conflicts.notice", false)

function Conflicts.OnEvent(event)
    if event == "PLAYER_LOGIN" then
        Conflicts.atLogin = Conflicts.Detect()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if session.done then return end
        session.readyAt = Now() + LOADING_DELAY
        PS.Ticker.SetEnabled("conflicts.notice", true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if session.waitingCombat and not session.readyAt then Conflicts.TryShow() end
    end
end

-- The diagnostics report's section: plain folder names and state words.
function Conflicts.Report()
    local found, addons = Conflicts.Detect(), PS.Json.Array()
    for index, entry in ipairs(found) do addons[index] = entry.addon end
    local elvui = "not-loaded"
    if Loaded("ElvUI") then
        local enabled = ElvUIPlates()
        elvui = enabled == true and "plates-on" or enabled == false and "plates-off" or "unknown"
    end
    local mode = Mode()
    return { addons = addons, count = #found, elvui = elvui,
        plates = #found == 0 and "none" or mode == "own" and "own" or "overlay" }
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    PS._RegisterEvent(eventFrame, event, "platesmith.conflicts")
end
eventFrame:SetScript("OnEvent", function(_, event) Conflicts.OnEvent(event) end)
