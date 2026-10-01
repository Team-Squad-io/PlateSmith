local _, PS = ...

if not PS or type(PS.RegisterModule) ~= "function" then return end
local L = PS.L

-- The threat windows (PS.ThreatConsole): up to five meter windows, each in threat meter or tank
-- mode with its own theme. They are saved in account state (they are HUD layout), move and
-- resize freely, snap edge to edge and move as a group, and can follow one of Blizzard's damage
-- meter windows. All data comes from the one threat service.
local Geometry = assert(PS.ThreatGeometry, "PlateSmith ThreatGeometry missing")
local Themes = assert(PS.ThreatThemes, "PlateSmith ThreatThemes missing")
local Meter = assert(PS.ThreatMeter, "PlateSmith ThreatMeter missing")
local Sample = assert(PS.ThreatSample, "PlateSmith ThreatSample missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable = Secret.IsReadable

local REFRESH_INTERVAL = 0.25
local SNAP_INTERVAL = 0.03
local DOCK_INTERVAL = 0.2
local MAX_WINDOWS = Geometry.MAX_WINDOWS
local NAME_LENGTH = 24
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 320, 170
-- The first window's centre sits this far right of the screen's.
local FIRST_OFFSET_X = 260
local METER_WINDOWS = 3
local SNAP_COLOUR = { 1, 0.82, 0.35 }
local SNAP_GLOW_WIDTH = 12 -- the target's glow band, centred on its edges
local SNAP_PULSE_SPEED = 6 -- radians a second: about one breath a second

local ranges = Geometry.WINDOW_RANGES
local modes = { threat = true, tank = true }
local dockSides = { right = true, left = true, above = true, below = true }
local DOCK_SIDE_ORDER = { "right", "left", "above", "below" }
local dockSideLabels = { right = L["Right"], left = L["Left"], above = L["Above"], below = L["Below"] }

local ThreatConsole = { version = 1, meters = {}, dirty = true, lastSnapshotRevision = -1, lastGroupRevision = -1,
    watchedRecords = {}, tankShown = false }

local function Bounded(range, value, fallback)
    if type(value) ~= "number" or value ~= value then return fallback end
    return math.max(range[1], math.min(range[2], value))
end

local function ScreenSize()
    local width = UIParent and type(UIParent.GetWidth) == "function" and UIParent:GetWidth() or nil
    local height = UIParent and type(UIParent.GetHeight) == "function" and UIParent:GetHeight() or nil
    if type(width) ~= "number" or width <= 0 then width = 1920 end
    if type(height) ~= "number" or height <= 0 then height = 1080 end
    return width, height
end

local function TrimName(name, fallback)
    if type(name) ~= "string" then return fallback end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return fallback end
    return name:sub(1, NAME_LENGTH)
end

local function DefaultName(mode)
    return mode == "threat" and L["Threat"] or L["Tank"]
end

-- Keeps a saved window wholly on screen, as its clamped frame is drawn. True when it moved.
local function KeepOnScreen(record)
    local screenWidth, screenHeight = ScreenSize()
    local left, top = Geometry.OnScreen(record.left, record.top, record.width, record.height, screenWidth, screenHeight)
    if left == record.left and top == record.top then return false end
    record.left, record.top = left, top
    return true
end

-- A window keeps the name it was given; one never renamed is named after its mode.
local function NormalizeWindow(record, id)
    local theme = Themes.IsValid(record.theme) and record.theme or Themes.default
    record.id = id
    record.mode = modes[record.mode] and record.mode or "tank"
    local custom = record.customName == true and TrimName(record.name, nil) or nil
    record.customName = custom ~= nil
    record.name = custom or DefaultName(record.mode)
    record.theme = theme
    record.locked = record.locked == true
    record.shown = record.shown ~= false
    -- Tank mode: your current target is the first row whatever the order (on by default).
    record.targetFirst = record.targetFirst ~= false
    record.alpha = Bounded(ranges.alpha, record.alpha, 1)
    record.rowHeight = math.floor(Bounded(ranges.rowHeight, record.rowHeight, Themes.Get(theme).rowHeight) + 0.5)
    record.width = Bounded(ranges.width, record.width, DEFAULT_WIDTH)
    record.height = Bounded(ranges.height, record.height, DEFAULT_HEIGHT)
    record.left = type(record.left) == "number" and record.left == record.left and record.left or 200
    record.top = type(record.top) == "number" and record.top == record.top and record.top or 600
    record.dockMeter = (record.dockMeter == 1 or record.dockMeter == 2 or record.dockMeter == 3) and record.dockMeter or 0
    record.dockSide = dockSides[record.dockSide] and record.dockSide or "right"
    -- Resized by the player while following above or below: keeps its own width.
    record.dockOwnWidth = record.dockOwnWidth == true
    -- Place in its follow chain: lower first.
    record.dockOrder = type(record.dockOrder) == "number" and record.dockOrder == record.dockOrder and record.dockOrder or 0
    KeepOnScreen(record)
    return record
end

-- Every saved window's rectangle except skip's, oldest first, for placing a window in free space.
local function SavedRects(list, skip)
    local rects = {}
    for _, record in ipairs(list) do
        if record ~= skip then rects[#rects + 1] = Geometry.Rect(record.left, record.top, record.width, record.height) end
    end
    return rects
end

-- A free window saved on the same corner as an earlier one would hide under it: move it to
-- free space.
local function SeparateStacked(list)
    local screenWidth, screenHeight = ScreenSize()
    for index = 2, #list do
        local record = list[index]
        local stacked = false
        for earlier = 1, index - 1 do
            local other = list[earlier]
            if other.left == record.left and other.top == record.top then stacked = true break end
        end
        if stacked and record.dockMeter == 0 then
            record.left, record.top = Geometry.FreeSpot(SavedRects(list, record), record.width, record.height,
                screenWidth, screenHeight)
        end
    end
end

-- Cleans the saved list in place: at most five windows, ids 1-5 kept unique, bad values reset.
local function NormalizeWindows(list)
    if type(list) ~= "table" then return {} end
    local clean, used = {}, {}
    for _, record in ipairs(list) do
        if type(record) == "table" and #clean < MAX_WINDOWS then
            local id = record.id
            if type(id) ~= "number" or id < 1 or id > MAX_WINDOWS or id ~= math.floor(id) or used[id] then
                id = nil
                for candidate = 1, MAX_WINDOWS do
                    if not used[candidate] then id = candidate break end
                end
            end
            used[id] = true
            clean[#clean + 1] = NormalizeWindow(record, id)
        end
    end
    for index = #list, 1, -1 do list[index] = nil end
    for index, record in ipairs(clean) do list[index] = record end
    SeparateStacked(list)
    return list
end

function ThreatConsole:GetState()
    local state = type(PS.GetState) == "function" and PS.GetState() or nil
    if type(state) ~= "table" then
        self.fallbackState = self.fallbackState or {}
        state = self.fallbackState
    end
    return state
end

function ThreatConsole:GetWindows()
    local state = self:GetState()
    if type(state.threatWindows) ~= "table" then state.threatWindows = {} end
    return state.threatWindows
end

function ThreatConsole:GetWindow(id)
    for _, record in ipairs(self:GetWindows()) do
        if record.id == id then return record end
    end
    return nil
end

function ThreatConsole:GetMeter(id)
    return self.meters[id]
end

local function FreeId(list)
    for candidate = 1, MAX_WINDOWS do
        local used = false
        for _, record in ipairs(list) do
            if record.id == candidate then used = true break end
        end
        if not used then return candidate end
    end
    return nil
end

local function FirstPosition()
    local screenWidth, screenHeight = ScreenSize()
    return math.floor(screenWidth / 2 + FIRST_OFFSET_X - DEFAULT_WIDTH / 2 + 0.5), math.floor(screenHeight / 2 + DEFAULT_HEIGHT / 2 + 0.5)
end

-- Tanks start in tank mode, everyone else on the threat meter.
local function DefaultMode(service)
    local role = service and type(service.GetPlayerRole) == "function" and service:GetPlayerRole() or nil
    return role == "TANK" and "tank" or "threat"
end

function ThreatConsole:EnsureMeter(record)
    local meter = self.meters[record.id]
    local spare = self.spareMeters and self.spareMeters[record.id]
    if meter then
        if meter.config ~= record then meter:Bind(record) end
    elseif spare then
        -- Frames cannot be destroyed: a deleted window's frame (and global name) is reused.
        self.spareMeters[record.id] = nil
        meter = spare
        self.meters[record.id] = meter
        meter:Bind(record)
    else
        meter = Meter.Create(self, record)
        self.meters[record.id] = meter
        local frame = meter.frame
        if frame.SetResizeBounds then
            frame:SetResizeBounds(ranges.width[1], ranges.height[1], ranges.width[2], ranges.height[2])
        end
    end
    meter:Place()
    meter:Layout()
    if record.id == 1 or not self.window then self.window = meter.frame end
    return meter
end

function ThreatConsole:CanCreateWindow()
    return #self:GetWindows() < MAX_WINDOWS
end

-- A new window in free space: beside, below or above a saved window (the newest first), else
-- cascaded from the newest; it never lands on another window. options: mode, name, theme.
-- Returns the saved record, or nil and a reason.
function ThreatConsole:CreateWindow(options)
    options = options or {}
    local list = self:GetWindows()
    local id = FreeId(list)
    if not id then return nil, "window-limit" end
    local record = { id = id, mode = options.mode or DefaultMode(self.service), name = options.name,
        customName = options.name ~= nil, theme = options.theme, shown = true }
    local last = list[#list]
    if last then
        record.theme = record.theme or last.theme
        record.width = Bounded(ranges.width, last.width, DEFAULT_WIDTH)
        record.height = Bounded(ranges.height, last.height, DEFAULT_HEIGHT)
        local screenWidth, screenHeight = ScreenSize()
        record.left, record.top = Geometry.FreeSpot(SavedRects(list), record.width, record.height, screenWidth, screenHeight)
    else
        record.left, record.top = FirstPosition()
    end
    NormalizeWindow(record, id)
    list[#list + 1] = record
    self:EnsureMeter(record)
    if self:IsShown() then self:ApplyVisibility() end
    self:UpdateWindowButtons()
    return record
end

-- The title's new-window button looks unavailable on every window at the limit.
function ThreatConsole:UpdateWindowButtons()
    local available = self:CanCreateWindow()
    for _, meter in pairs(self.meters) do meter:SetNewWindowAvailable(available) end
end

-- Keeps an open Threat windows settings page in step with changes made from a window.
function ThreatConsole:RefreshOptions()
    local options = PS.Options
    if options and options.threatWindowDropdown and type(options.Refresh) == "function" then options:Refresh() end
end

-- Screen size or UI scale changed: pull every free window back wholly on screen.
function ThreatConsole:KeepWindowsOnScreen()
    self:EndDrag()
    for _, record in ipairs(self:GetWindows()) do
        local meter = self.meters[record.id]
        if record.dockMeter == 0 and KeepOnScreen(record) and meter then meter:Place() end
    end
end

function ThreatConsole:DeleteWindow(id)
    local list = self:GetWindows()
    for index, record in ipairs(list) do
        if record.id == id then
            table.remove(list, index)
            local meter = self.meters[id]
            if meter then
                self:EndDrag()
                self:StopSizing(meter)
                meter.frame:Hide()
                self.meters[id] = nil
                self.spareMeters = self.spareMeters or {}
                self.spareMeters[id] = meter
            end
            if self.window and meter and self.window == meter.frame then
                local first = list[1] and self.meters[list[1].id]
                self.window = first and first.frame or nil
            end
            self:ApplyVisibility()
            self:UpdateWindowButtons()
            return true
        end
    end
    return false
end

function ThreatConsole:RenameWindow(id, name)
    local record = self:GetWindow(id)
    if not record then return false, "window-missing" end
    local trimmed = TrimName(name, nil)
    if not trimmed then return false, L["Enter a name."] end
    record.name, record.customName = trimmed, true
    self:MarkDirty()
    return true
end

-- Validated writes for one window's options (mode, theme, locked, alpha, rowHeight, dockMeter,
-- dockSide, shown, targetFirst). Returns false for an unknown key or a rejected value.
function ThreatConsole:SetWindowOption(id, key, value)
    local record = self:GetWindow(id)
    if not record then return false end
    if key == "mode" then
        if not modes[value] then return false end
    elseif key == "theme" then
        if not Themes.IsValid(value) then return false end
        record.rowHeight = Themes.Get(value).rowHeight
    elseif key == "locked" or key == "shown" or key == "targetFirst" then
        value = value == true
    elseif key == "alpha" or key == "rowHeight" then
        if type(value) ~= "number" then return false end
        value = Bounded(ranges[key], value, record[key])
        if key == "rowHeight" then value = math.floor(value + 0.5) end
    elseif key == "dockMeter" then
        if value ~= 0 and value ~= 1 and value ~= 2 and value ~= 3 then return false end
    elseif key == "dockSide" then
        if not dockSides[value] then return false end
    else
        return false
    end
    record[key] = value
    if key == "mode" and not record.customName then record.name = DefaultName(value) end
    if key == "dockMeter" or key == "dockSide" then
        -- A window that starts following (or moves to another side) joins the end of that chain.
        record.dockOwnWidth = false
        self.dockSerial = math.max(self.dockSerial or 0, self:MaxDockOrder()) + 1
        record.dockOrder = self.dockSerial
    end
    local meter = self.meters[id]
    if meter then
        if key == "theme" then meter:ApplyTheme() else meter:Layout() end
        if key == "dockMeter" and value == 0 then meter:Place() end
    end
    if key == "shown" then
        if value then self:GetState().threatConsoleShown = true end
        if not value and not self:AnyWindowShown() then self:GetState().threatConsoleShown = false end
    end
    self:ApplyVisibility()
    self:MarkDirty()
    return true
end

function ThreatConsole:ShowWindow(id, shown)
    return self:SetWindowOption(id, "shown", shown ~= false)
end

function ThreatConsole:AnyWindowShown()
    for _, record in ipairs(self:GetWindows()) do
        if record.shown then return true end
    end
    return false
end

-- True while the windows are switched on and at least one of them is shown.
function ThreatConsole:IsShown()
    return self:GetState().threatConsoleShown == true and self:AnyWindowShown()
end

-- Shows or hides each frame from the saved flags, and switches the service's group read and
-- tick, the refresh and the docking follow on only while something needs them.
function ThreatConsole:ApplyVisibility()
    local on = self:GetState().threatConsoleShown == true
    local anyShown, anyDocked, anyThreat, anyTank = false, false, false, false
    for _, record in ipairs(self:GetWindows()) do
        local meter = self.meters[record.id]
        local visible = on and record.shown
        if meter then
            if visible then
                if not meter.frame:IsShown() then meter.frame:Show() end
            else
                if self.drag and self.drag.meter == meter then self:EndDrag() end
                for _, row in ipairs(meter.rows) do self:HideRowTooltip(row) end
                meter.frame:Hide()
            end
        end
        if visible then
            anyShown = true
            if record.dockMeter > 0 then anyDocked = true end
            if record.mode == "threat" then anyThreat = true else anyTank = true end
        end
    end
    -- Rebuilt by the next render from the rows the tank windows show.
    for record in pairs(self.watchedRecords) do self.watchedRecords[record] = nil end
    self.tankShown = anyTank
    if PS.Ticker then
        PS.Ticker.SetEnabled("threat.console", anyShown)
        PS.Ticker.SetEnabled("threat.dock", anyDocked)
    end
    local service = self.service
    if service and service.SetGroupThreatWanted then service:SetGroupThreatWanted(anyThreat) end
    if service and service.SyncTicker then service:SyncTicker() end
    if anyShown then
        self:MarkDirty()
        if anyDocked then self:UpdateDocking() end
    end
end

-- Switches the windows on; the choice is saved (module enable passes false, for the same effect).
function ThreatConsole:Show()
    local state = self:GetState()
    state.threatConsoleShown = true

    local list = self:GetWindows()
    if #list == 0 then self:CreateWindow() end
    if not self:AnyWindowShown() then
        for _, record in ipairs(list) do record.shown = true end
    end
    self:ApplyVisibility()
    self:Refresh(true)
end

function ThreatConsole:Hide(persist)
    self:EndDrag()
    self:StopSizing()
    local state = self:GetState()
    if persist ~= false then
        state.threatConsoleShown = false
        self:ApplyVisibility()
        return
    end
    -- A module disable hides the frames but keeps the saved choice.
    local saved = state.threatConsoleShown
    state.threatConsoleShown = false
    self:ApplyVisibility()
    state.threatConsoleShown = saved
end

function ThreatConsole:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

function ThreatConsole:MarkDirty()
    self.dirty = true
end

-- Redraws the shown windows when the service's snapshot or group read changed, or a window
-- asked for it (resize, scroll, option). The enemy snapshot is only built (and sorted) while a
-- tank window is shown. Nothing else runs on the refresh tick.
function ThreatConsole:Refresh(force)
    local service = self.service
    if not service then return end
    local snapshotRevision = self.lastSnapshotRevision
    if self.tankShown then
        service:GetSnapshot()
        snapshotRevision = service.snapshotRevision
    end
    local groupRevision = service.groupThreatRevision
    if not force and not self.dirty and snapshotRevision == self.lastSnapshotRevision
        and groupRevision == self.lastGroupRevision then
        return false
    end
    self.lastSnapshotRevision, self.lastGroupRevision = snapshotRevision, groupRevision
    self.dirty = false
    for record in pairs(self.watchedRecords) do self.watchedRecords[record] = nil end
    local source = self:Source()
    for _, meter in pairs(self.meters) do
        if meter.frame:IsShown() then meter:Render(source) end
    end
    return true
end

-- What the windows read: the threat service, or the fixed sample while sample data is on.
function ThreatConsole:Source()
    if Sample.enabled then return Sample.Source end
    return self.service
end

function ThreatConsole:IsSampleData()
    return Sample.enabled == true
end

-- Sample data is session only and never shown in combat, so it cannot be mixed with real threat.
-- Returns false when it cannot be switched on now.
function ThreatConsole:SetSampleData(on)
    on = on == true
    if on and Secret.InCombat() then return false end
    if on == Sample.enabled then return true end
    if on then Sample.Build() end
    Sample.enabled = on
    self:Refresh(true)
    return true
end

function ThreatConsole:Notify(message)
    PS.Chat.Print(message)
end

-- A group member's name line; a protected name goes straight into the tooltip's sink.
local function AddNameLine(name, unit, opaque, hasOpaque)
    if hasOpaque and pcall(GameTooltip.AddLine, GameTooltip, opaque, 1, 1, 1) then return end
    GameTooltip:AddLine(name or unit or L["Unknown"], 1, 1, 1)
end

-- Row tooltips: enemies list who is attacking and targeting them; members their threat.
function ThreatConsole:ShowActivityTooltip(row)
    local source = self:Source()
    if not row or not row.unit or not source or not GameTooltip then return end
    local attacking, attackingState = source:GetActiveAttackerCount(row.unit)
    local targeting, targetingState = source:GetTargeterCount(row.unit)
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if not (row.hasOpaqueName and pcall(GameTooltip.SetText, GameTooltip, row.enemyNameOpaque)) then
        GameTooltip:SetText(row.enemyName or L["Enemy"])
    end
    -- Inferred, never observed: the client names no damage source.
    GameTooltip:AddLine(L["Possible attackers"], 1, 0.82, 0)
    if attacking == 0 and attackingState == "no-signal" then
        GameTooltip:AddLine(L["Unknown: the game has not reported damage to this enemy."], 0.72, 0.72, 0.72)
    elseif attacking == 0 and (attackingState == "unknown" or attackingState == "partial") then
        GameTooltip:AddLine(L["Unknown (the game hides some targets here)."], 0.72, 0.72, 0.72)
    elseif attacking == 0 then
        GameTooltip:AddLine(L["No recent damage + current target match."], 0.72, 0.72, 0.72)
    else
        if attackingState == "partial" then GameTooltip:AddLine(L["At least:"], 0.72, 0.72, 0.72) end
        for index = 1, attacking do
            AddNameLine(source:GetActiveAttacker(row.unit, index))
        end
    end
    GameTooltip:AddLine(L["Inferred from recent damage to this mob + targeting it."], 0.62, 0.72, 0.82)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Currently targeting"], 1, 0.82, 0)
    -- "None" only when every member's target was read; otherwise the list is a lower bound.
    if targeting == 0 and targetingState == "none" then
        GameTooltip:AddLine(L["No group members targeting this enemy."], 0.72, 0.72, 0.72)
    elseif targeting == 0 then
        GameTooltip:AddLine(L["Targeting unknown (the game hides some targets here)."], 0.72, 0.72, 0.72)
    else
        if targetingState == "partial" then GameTooltip:AddLine(L["At least:"], 0.72, 0.72, 0.72) end
        for index = 1, targeting do
            AddNameLine(source:GetTargeter(row.unit, index))
        end
    end
    local entry = row.entry
    if type(entry) == "table" and entry.leadKept == true and type(entry.keptAt) == "number" and type(GetTime) == "function" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Gap last seen %ds ago (read while hovered or focused)."],
            math.max(0, math.floor(GetTime() - entry.keptAt))), 0.62, 0.72, 0.82)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Left-click spotlights this exact visible unit."], 0.55, 0.8, 1)
    GameTooltip:AddLine(L["Click its world plate to target it."], 0.62, 0.72, 0.82)
    GameTooltip:Show()
end

local roleLabels = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }

function ThreatConsole:ShowMemberTooltip(row)
    local entry = row and row.entry
    if not entry or not GameTooltip then return end
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if not (entry.hasOpaqueName and pcall(GameTooltip.SetText, GameTooltip, entry.nameOpaque)) then
        GameTooltip:SetText(entry.name or entry.unit or L["Unknown"])
    end
    if roleLabels[entry.role] then GameTooltip:AddLine(roleLabels[entry.role], 0.72, 0.72, 0.72) end
    if entry.isPet then GameTooltip:AddLine(L["Pet"], 0.72, 0.72, 0.72) end
    if entry.isOutside then
        GameTooltip:AddLine(L["Outside your group. Its threat total is worked out from yours (Experimental)."],
            0.72, 0.72, 0.72, true)
    end
    -- A protected enemy name cannot go through string.format: it takes the right-hand column.
    if not (row.hasOpaqueName and pcall(GameTooltip.AddDoubleLine, GameTooltip, L["On"], row.enemyNameOpaque,
        1, 0.82, 0, 1, 0.82, 0)) then
        GameTooltip:AddLine(string.format(L["On %s"], row.enemyName or L["Enemy"]), 1, 0.82, 0)
    end
    if entry.tanking == true then GameTooltip:AddLine(L["Holding aggro"], 1, 1, 1) end
    if type(entry.gap) == "number" then
        GameTooltip:AddLine(string.format(entry.tanking == true and L["%s before anyone pulls it (110%% rule)"]
            or L["%s to pulling (110%% of the holder's threat)"], PS.Format.SignedLead(entry.gap)), 1, 1, 1)
    elseif entry.hasOpaquePercent or entry.hasOpaqueRaw then
        GameTooltip:AddLine(L["The game shows this threat but keeps the numbers private."], 0.62, 0.72, 0.82)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Left-click spotlights the enemy being measured."], 0.55, 0.8, 1)
    GameTooltip:Show()
end

function ThreatConsole:ShowRowTooltip(row)
    if row and row.kind == "member" then return self:ShowMemberTooltip(row) end
    return self:ShowActivityTooltip(row)
end

function ThreatConsole:HideRowTooltip(row)
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(row)) then GameTooltip:Hide() end
end

-- Rows never target: they spotlight the exact plate, checked by serial, root and GUID.
function ThreatConsole:HighlightRow(row)
    if not row or not row.unit or not self.service or (row.entry and row.entry.sample) then return false end
    -- The threat meter read through "target" with no plate: nothing to spotlight.
    if not row.root then
        self.lastHighlightCheck = "no-plate"
        return false
    end
    local current, reason = self.service:IsCurrentPlate(row.unit, row.serial, row.root, row.guid)
    if not current then
        self.lastHighlightCheck = reason or "unavailable"
        self:Notify(L["That nameplate is no longer available."])
        return false
    end
    if type(PS.HighlightPlate) ~= "function" or not PS.HighlightPlate(row.unit) then
        self.lastHighlightCheck = "overlay-hidden"
        return false
    end
    self.lastHighlightCheck = "highlighted"
    return true
end

-- Reused rectangles and lists for snapping and docking, which run every tick while active.
local scratchRects, scratchOthers = {}, {}

local function ScratchRect(key, left, top, width, height)
    local rect = scratchRects[key]
    if not rect then
        rect = {}
        scratchRects[key] = rect
    end
    rect.left, rect.bottom, rect.right, rect.top = left, top - height, left + width, top
    return rect
end

-- Where a window is now: its frame's edges and size when the client reports them, else what was
-- saved. The rectangle is scratch, valid until the next call.
local function CurrentRect(meter, liveSize)
    local frame, config = meter.frame, meter.config
    local left, top = config.left, config.top
    if type(frame.GetLeft) == "function" and type(frame.GetTop) == "function" then
        local frameLeft, frameTop = frame:GetLeft(), frame:GetTop()
        if type(frameLeft) == "number" and type(frameTop) == "number" then left, top = frameLeft, frameTop end
    end
    local width, height = config.width, config.height
    if liveSize then
        local frameWidth = type(frame.GetWidth) == "function" and frame:GetWidth() or nil
        local frameHeight = type(frame.GetHeight) == "function" and frame:GetHeight() or nil
        width = Bounded(ranges.width, frameWidth, width)
        height = Bounded(ranges.height, frameHeight, height)
    end
    return ScratchRect("current", left, top, width, height)
end

-- A Blizzard meter window's rectangle in UIParent units, read only; nil when it is hidden,
-- missing, or its geometry is not readable.
local meterWindowNames, meterRectKeys = {}, {}
for index = 1, METER_WINDOWS do
    meterWindowNames[index] = "DamageMeterSessionWindow" .. index
    meterRectKeys[index] = "meter" .. index
end

local ReadNumber = Secret.ReadNumber

-- Runs every docking and snap tick, so the rectangle is scratch (valid until the next call for
-- the same meter).
function ThreatConsole:ReadMeterRect(index)
    local target = meterWindowNames[index] and rawget(_G, meterWindowNames[index])
    if type(target) ~= "table" or type(target.GetLeft) ~= "function" or type(target.IsVisible) ~= "function" then return nil end
    local ok, visible = pcall(target.IsVisible, target)
    if not ok or not IsReadable(visible) or visible ~= true then return nil end
    local left, bottom = ReadNumber(target, "GetLeft"), ReadNumber(target, "GetBottom")
    local width, height = ReadNumber(target, "GetWidth"), ReadNumber(target, "GetHeight")
    local scale = type(target.GetEffectiveScale) == "function" and ReadNumber(target, "GetEffectiveScale") or 1
    if not (left and bottom and width and height and scale) then return nil end
    local parentScale = UIParent and type(UIParent.GetEffectiveScale) == "function" and UIParent:GetEffectiveScale() or 1
    local factor = scale / ((parentScale and parentScale > 0) and parentScale or 1)
    return ScratchRect(meterRectKeys[index], left * factor, (bottom + height) * factor, width * factor, height * factor)
end

-- Which Blizzard meter window each entry of the last OtherRects list is (nil for our windows).
local scratchMeterIndex = {}

-- What a moved or resized window can snap to: the shown windows outside group, then the shown
-- Blizzard meter windows. A scratch list of scratch rectangles.
function ThreatConsole:OtherRects(group)
    local count = 0
    for _, record in ipairs(self:GetWindows()) do
        local meter = self.meters[record.id]
        if meter and meter.frame:IsShown() and not group[record.id] then
            count = count + 1
            scratchOthers[count] = ScratchRect(record.id, record.left, record.top, record.width, record.height)
            scratchMeterIndex[count] = nil
        end
    end
    for index = 1, METER_WINDOWS do
        local rect = self:ReadMeterRect(index)
        if rect then
            count = count + 1
            scratchOthers[count] = rect
            scratchMeterIndex[count] = index
        end
    end
    for index = count + 1, #scratchOthers do scratchOthers[index], scratchMeterIndex[index] = nil, nil end
    return scratchOthers
end

-- Every other shown, free window's rectangle, keyed by id.
function ThreatConsole:WindowRects(skipDocked)
    local rects = {}
    for _, record in ipairs(self:GetWindows()) do
        local meter = self.meters[record.id]
        if meter and meter.frame:IsShown() and not (skipDocked and record.dockMeter > 0) then
            rects[record.id] = Geometry.Rect(record.left, record.top, record.width, record.height)
        end
    end
    return rects
end

local function ShiftDown()
    return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

-- Dragging moves the window's whole snapped group. Shift as the drag starts moves it alone and
-- without snapping, to pull it out of a group and drop it anywhere. Followers are anchored to the
-- dragged frame for the drag, then placed back on UIParent where they landed.
function ThreatConsole:StartDrag(meter)
    local config = meter.config
    if config.locked then return false end
    self:EndDrag()
    local rects = self:WindowRects(true)
    local free = ShiftDown()
    -- A following window is dragged alone: dropped away from the meter it stops following.
    local alone = config.dockMeter > 0 or free
    local group = alone and { [config.id] = true } or Geometry.Group(rects, config.id)
    local followers = {}
    for id in pairs(group) do
        local other = self.meters[id]
        if id ~= config.id and other and not other.config.locked then
            followers[#followers + 1] = { meter = other, dx = other.config.left - config.left,
                dy = other.config.top - config.top }
            other.frame:ClearAllPoints()
            other.frame:SetPoint("TOPLEFT", meter.frame, "TOPLEFT", other.config.left - config.left,
                other.config.top - config.top)
        end
    end
    local ok = pcall(meter.frame.StartMoving, meter.frame)
    if not ok then
        for _, follower in ipairs(followers) do follower.meter:Place() end
        if not self.dragBlockedReported then
            self.dragBlockedReported = true
            self:Notify(L["The client blocked moving the threat window right now."])
        end
        return false
    end
    self.dragBlockedReported = false
    self.drag = { meter = meter, followers = followers, group = group, free = free }
    if PS.Ticker then PS.Ticker.SetEnabled("threat.snap", true) end
    return true
end

-- The snap feedback: a line along the edge a window will join, and a border around the window
-- (or Blizzard meter) it will join. Both are PlateSmith's own frames on UIParent, laid over the
-- target's rectangle; nothing is drawn on, parented to or hooked on a Blizzard frame.
function ThreatConsole:SnapGuide()
    local guide = self.snapGuide
    if guide then return guide end
    guide = CreateFrame("Frame", nil, UIParent)
    guide:SetFrameStrata("DIALOG")
    if guide.SetFrameLevel then guide:SetFrameLevel(100) end
    guide:SetAllPoints(UIParent)
    guide.vertical = guide:CreateTexture(nil, "OVERLAY")
    guide.horizontal = guide:CreateTexture(nil, "OVERLAY")
    Themes.SetKit(guide.vertical, "snap-guide-vertical", false, true)
    Themes.SetKit(guide.horizontal, "snap-guide-horizontal", true, false)
    guide.vertical:SetVertexColor(SNAP_COLOUR[1], SNAP_COLOUR[2], SNAP_COLOUR[3], 0.9)
    guide.horizontal:SetVertexColor(SNAP_COLOUR[1], SNAP_COLOUR[2], SNAP_COLOUR[3], 0.9)

    local highlight = CreateFrame("Frame", nil, UIParent)
    highlight:SetFrameStrata("DIALOG")
    if highlight.SetFrameLevel then highlight:SetFrameLevel(99) end
    highlight.edges, highlight.glows = {}, {}
    for index = 1, 4 do
        local horizontal = index <= 2
        local texture = highlight:CreateTexture(nil, "OVERLAY")
        Themes.SetKit(texture, horizontal and "snap-guide-horizontal" or "snap-guide-vertical", horizontal, not horizontal)
        texture:SetVertexColor(SNAP_COLOUR[1], SNAP_COLOUR[2], SNAP_COLOUR[3], 0.7)
        highlight.edges[index] = texture
        -- A wider, additive band under each edge: the soft glow that pulses (PulseHighlight).
        local glow = highlight:CreateTexture(nil, "ARTWORK")
        Themes.SetKit(glow, horizontal and "snap-guide-horizontal" or "snap-guide-vertical", horizontal, not horizontal)
        glow:SetVertexColor(SNAP_COLOUR[1], SNAP_COLOUR[2], SNAP_COLOUR[3], 1)
        if glow.SetBlendMode then glow:SetBlendMode("ADD") end
        highlight.glows[index] = glow
    end
    -- A faint wash over the target, so the window being joined reads at a glance.
    highlight.fill = highlight:CreateTexture(nil, "BACKGROUND")
    highlight.fill:SetAllPoints(highlight)
    highlight.fill:SetColorTexture(SNAP_COLOUR[1], SNAP_COLOUR[2], SNAP_COLOUR[3], 1)
    highlight:Hide()
    guide.highlight = highlight
    guide:Hide()
    self.snapGuide = guide
    return guide
end

-- The glow and wash breathe while a snap is lined up (driven by the snap tick), starting bright
-- the moment a target appears; the edges themselves stay steady.
local function PulseHighlight(highlight)
    local now = type(GetTime) == "function" and GetTime() or 0
    local phase = math.cos((now - (highlight.pulseStart or now)) * SNAP_PULSE_SPEED) * 0.5 + 0.5
    highlight.pulse = phase
    for index = 1, 4 do highlight.glows[index]:SetAlpha(0.25 + 0.45 * phase) end
    highlight.fill:SetAlpha(0.04 + 0.08 * phase)
end

local function ShowHighlight(highlight, rect)
    local width, height = rect.right - rect.left, rect.top - rect.bottom
    highlight:ClearAllPoints()
    highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, rect.bottom)
    highlight:SetSize(width, height)
    local edges = highlight.edges
    for index = 1, 4 do edges[index]:ClearAllPoints() end
    edges[1]:SetPoint("BOTTOMLEFT", highlight, "TOPLEFT", 0, -2)
    edges[1]:SetSize(width, 4)
    edges[2]:SetPoint("BOTTOMLEFT", highlight, "BOTTOMLEFT", 0, -2)
    edges[2]:SetSize(width, 4)
    edges[3]:SetPoint("BOTTOMLEFT", highlight, "BOTTOMLEFT", -2, 0)
    edges[3]:SetSize(4, height)
    edges[4]:SetPoint("BOTTOMLEFT", highlight, "BOTTOMRIGHT", -2, 0)
    edges[4]:SetSize(4, height)
    local glows, pad = highlight.glows, SNAP_GLOW_WIDTH / 2
    for index = 1, 4 do glows[index]:ClearAllPoints() end
    glows[1]:SetPoint("BOTTOMLEFT", highlight, "TOPLEFT", -pad, -pad)
    glows[1]:SetSize(width + SNAP_GLOW_WIDTH, SNAP_GLOW_WIDTH)
    glows[2]:SetPoint("BOTTOMLEFT", highlight, "BOTTOMLEFT", -pad, -pad)
    glows[2]:SetSize(width + SNAP_GLOW_WIDTH, SNAP_GLOW_WIDTH)
    glows[3]:SetPoint("BOTTOMLEFT", highlight, "BOTTOMLEFT", -pad, -pad)
    glows[3]:SetSize(SNAP_GLOW_WIDTH, height + SNAP_GLOW_WIDTH)
    glows[4]:SetPoint("BOTTOMLEFT", highlight, "BOTTOMRIGHT", -pad, -pad)
    glows[4]:SetSize(SNAP_GLOW_WIDTH, height + SNAP_GLOW_WIDTH)
    if highlight.target == nil then highlight.pulseStart = type(GetTime) == "function" and GetTime() or 0 end
    highlight.target = rect
    PulseHighlight(highlight)
    highlight:Show()
end

-- The dragged window's snap feedback, each snap tick (a resize draws its own as it sizes).
function ThreatConsole:UpdateSnapGuide()
    local drag, sizing = self.drag, self.sizing
    if sizing then return self:UpdateSizing() end
    if not drag then
        self:StopSnapFeedback()
        return
    end
    local rect = CurrentRect(drag.meter)
    if self:DragSkipsSnap(drag) then return self:DrawSnapGuide(rect) end
    local others = self:OtherRects(drag.group)
    local screenWidth, screenHeight = ScreenSize()
    local _, _, xEdge, yEdge, xTarget, yTarget = Geometry.Snap(rect, others, screenWidth, screenHeight)
    self:DrawSnapGuide(rect, others, xEdge, yEdge, xTarget, yTarget)
end

-- A drag started with Shift never snaps; pressing Shift during any drag stops snapping while held.
function ThreatConsole:DragSkipsSnap(drag)
    return drag.free == true or ShiftDown()
end

-- A line along each edge that snaps, and a border around the window or meter joined.
function ThreatConsole:DrawSnapGuide(rect, others, xEdge, yEdge, xTarget, yTarget)
    local guide = self:SnapGuide()
    if xEdge == nil and yEdge == nil then
        guide:Hide()
        guide.highlight.target = nil
        guide.highlight:Hide()
        return
    end
    guide.vertical:SetShown(xEdge ~= nil)
    guide.horizontal:SetShown(yEdge ~= nil)
    if xEdge then
        guide.vertical:ClearAllPoints()
        guide.vertical:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", xEdge - 2, rect.bottom)
        guide.vertical:SetSize(4, rect.top - rect.bottom)
    end
    if yEdge then
        guide.horizontal:ClearAllPoints()
        guide.horizontal:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, yEdge - 2)
        guide.horizontal:SetSize(rect.right - rect.left, 4)
    end
    guide:Show()
    local target = others[xTarget or yTarget or 0]
    if target then
        ShowHighlight(guide.highlight, target)
    else
        guide.highlight.target = nil
        guide.highlight:Hide()
    end
end

-- Clears the snap feedback, and stops the snap tick unless a drag or resize is still going on.
function ThreatConsole:StopSnapFeedback()
    local guide = self.snapGuide
    if guide then
        guide:Hide()
        guide.highlight.target = nil
        guide.highlight:Hide()
    end
    if PS.Ticker and not self.drag then PS.Ticker.SetEnabled("threat.snap", false) end
end

function ThreatConsole:StopDrag(meter)
    local drag = self.drag
    if not drag or (meter and drag.meter ~= meter) then return false end
    self.drag = nil
    self:StopSnapFeedback()
    local lead = drag.meter
    pcall(lead.frame.StopMovingOrSizing, lead.frame)
    if lead.frame.SetUserPlaced then pcall(lead.frame.SetUserPlaced, lead.frame, false) end
    local rect = CurrentRect(lead)
    local screenWidth, screenHeight = ScreenSize()
    local others = self:OtherRects(drag.group)
    local dx, dy, xTarget, yTarget = 0, 0, nil, nil
    if not self:DragSkipsSnap(drag) then
        local snapX, snapY, _, _, targetX, targetY = Geometry.Snap(rect, others, screenWidth, screenHeight)
        dx, dy, xTarget, yTarget = snapX, snapY, targetX, targetY
    end
    local config = lead.config
    config.left, config.top = math.floor(rect.left + dx + 0.5), math.floor(rect.top + dy + 0.5)
    -- Dropped against a side of a Blizzard meter window: the window follows it on that side.
    -- Dropped against another window: it joins that window's row (its top and height) or column
    -- (its left and width).
    local meterIndex, side, joined
    for _, target in ipairs({ xTarget or 0, yTarget or 0 }) do
        local dropped = Geometry.Rect(config.left, config.top, config.width, config.height)
        if not side and scratchMeterIndex[target] then
            side = Geometry.DockSide(dropped, others[target])
            if side then meterIndex = scratchMeterIndex[target] end
        elseif not side and not joined and others[target] then
            local left, top, width, height = Geometry.Join(dropped, others[target])
            if left then
                joined = true
                config.left, config.top = math.floor(left + 0.5), math.floor(top + 0.5)
                config.width = math.floor(Bounded(ranges.width, width, config.width) + 0.5)
                config.height = math.floor(Bounded(ranges.height, height, config.height) + 0.5)
            end
        end
    end
    KeepOnScreen(config)
    lead:Place()
    if joined then lead:Layout() end
    for _, follower in ipairs(drag.followers) do
        local followerConfig = follower.meter.config
        followerConfig.left, followerConfig.top = config.left + follower.dx, config.top + follower.dy
        KeepOnScreen(followerConfig)
        follower.meter:Place()
    end
    if side and (side ~= config.dockSide or meterIndex ~= config.dockMeter) then
        self:SetWindowOption(config.id, "dockSide", side)
        self:SetWindowOption(config.id, "dockMeter", meterIndex)
        self:RefreshOptions()
    elseif not side and config.dockMeter > 0 then
        -- Dragged away from the meter: it stays where it was dropped, following nothing.
        self:SetWindowOption(config.id, "dockMeter", 0)
        self:RefreshOptions()
    elseif side then
        self:UpdateDocking()
    end
    return true
end

-- A hidden frame never receives OnDragStop, so hiding must finish the drag itself.
function ThreatConsole:EndDrag()
    if self.drag then self:StopDrag(self.drag.meter) end
end

-- The cursor in UIParent units, or nil when the client does not report it.
local function CursorPosition()
    if type(GetCursorPosition) ~= "function" then return nil end
    local x, y = GetCursorPosition()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local scale = UIParent and type(UIParent.GetEffectiveScale) == "function" and UIParent:GetEffectiveScale() or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return x / scale, y / scale
end

local sizingState, sizingRow, sizingColumn, skipBottom, skipRight = {}, {}, {}, {}, {}
-- Windows a resize pushes along (below the row, right of the column), each after the one it rests on.
local pushDown, downParents, pushRight, rightParents, pushSources = {}, {}, {}, {}, {}
-- The grip re-enters under the cursor as its window resizes: no tooltip until this long after.
local GRIP_TOOLTIP_QUIET = 0.2

local function ClearPushes()
    for index = #pushDown, 1, -1 do pushDown[index] = nil end
    for index = #pushRight, 1, -1 do pushRight[index] = nil end
    for key in pairs(downParents) do downParents[key] = nil end
    for key in pairs(rightParents) do rightParents[key] = nil end
end

-- The source a chain of pushed windows starts from.
local function PushRoot(parents, key)
    while parents[key] ~= nil do key = parents[key] end
    return key
end

-- How far the resized edge may go before a pushed window would leave the screen: its movement
-- is the new size less its chain's source's size at the start.
local function PushLimit(rects, order, parents, vertical, screenWidth)
    local limit
    for _, key in ipairs(order) do
        local rect, root = rects[key], rects[PushRoot(parents, key)]
        local room
        if vertical then
            room = root.top - root.bottom + rect.bottom
        else
            room = root.right - root.left + screenWidth - rect.right
        end
        if not limit or room < limit then limit = room end
    end
    return limit
end

local function SetPushSources(id, line)
    for key in pairs(pushSources) do pushSources[key] = nil end
    pushSources[id] = true
    for key in pairs(line) do pushSources[key] = true end
    return pushSources
end

-- The windows that resize with a window: the free, unlocked, shown windows in its row take its
-- height and those in its column its width, and the windows stacked below them or beside them
-- on the right move to stay attached. Shift, or a following window, resizes alone. Only the
-- window itself is left out of what the resize snaps to.
function ThreatConsole:LinkSizing(meter, alone)
    local group = self.sizingGroup or {}
    self.sizingGroup = group
    for id in pairs(group) do group[id] = nil end
    local id = meter.config.id
    group[id] = true
    ClearPushes()
    sizingState.maxWidth, sizingState.maxHeight = nil, nil
    if alone or meter.config.dockMeter > 0 then
        for key in pairs(sizingRow) do sizingRow[key] = nil end
        for key in pairs(sizingColumn) do sizingColumn[key] = nil end
        return
    end
    local rects = self:WindowRects(true)
    for key in pairs(rects) do
        local record = self:GetWindow(key)
        if key ~= id and record and record.locked then rects[key] = nil end
    end
    Geometry.Line(rects, id, false, sizingRow)
    Geometry.Line(rects, id, true, sizingColumn)
    sizingRow[id], sizingColumn[id] = nil, nil
    Geometry.Pushed(rects, SetPushSources(id, sizingRow), true, pushDown, downParents)
    Geometry.Pushed(rects, SetPushSources(id, sizingColumn), false, pushRight, rightParents)
    local screenWidth = ScreenSize()
    local maxHeight = PushLimit(rects, pushDown, downParents, true, screenWidth)
    local maxWidth = PushLimit(rects, pushRight, rightParents, false, screenWidth)
    -- Never below the size at the start, so the window does not jump.
    sizingState.maxHeight = maxHeight and math.max(maxHeight, sizingState.height or 0)
    sizingState.maxWidth = maxWidth and math.max(maxWidth, sizingState.width or 0)
end

-- Moves the pushed windows onto the edges they rest on, which the resize has just moved.
function ThreatConsole:PushAttached()
    for _, id in ipairs(pushDown) do
        local record, parent, meter = self:GetWindow(id), self:GetWindow(downParents[id]), self.meters[id]
        if record and parent and meter then
            record.top = parent.top - parent.height
            meter:Place()
        end
    end
    for _, id in ipairs(pushRight) do
        local record, parent, meter = self:GetWindow(id), self:GetWindow(rightParents[id]), self.meters[id]
        if record and parent and meter then
            record.left = parent.left + parent.width
            meter:Place()
        end
    end
end

-- The grip's tooltip shows only on a plain hover: not while resizing, not just after, and not
-- while the button is held from a drag elsewhere.
function ThreatConsole:GripTooltipAllowed()
    if self.sizing or self.drag then return false end
    if type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") == true then return false end
    local ended = self.sizingEndedAt
    local now = type(GetTime) == "function" and GetTime() or nil
    if ended and type(now) == "number" and now - ended < GRIP_TOOLTIP_QUIET then return false end
    return true
end

-- The corner grip resizes by following the cursor itself rather than the client's StartSizing,
-- which owns the size until the button is released and so cannot snap as it goes. The top-left
-- stays put; the bottom and right edges snap (Shift: no snap) and the size is kept in bounds and
-- on screen. A transient OnUpdate on the grip runs it while the button is held.
function ThreatConsole:StartSizing(meter)
    if meter.config.locked then return false end
    self:StopSizing()
    local x, y = CursorPosition()
    if not x then return false end
    local rect = CurrentRect(meter, true)
    local state = sizingState
    state.x, state.y = x, y
    state.left, state.top = rect.left, rect.top
    state.width, state.height = rect.right - rect.left, rect.top - rect.bottom
    state.startWidth = meter.config.width
    self.sizing = meter
    self:LinkSizing(meter, ShiftDown())
    local grip = meter.grip
    if grip and grip.SetScript then grip:SetScript("OnUpdate", function() self:UpdateSizing() end) end
    return true
end

-- One step of a resize: the size under the cursor, snapped, applied to the window and the
-- windows linked to it.
function ThreatConsole:UpdateSizing(final)
    local meter = self.sizing
    if not meter then return end
    if not final and type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") == false then
        -- The button came up where the grip could not hear it.
        return self:StopSizing(meter)
    end
    local x, y = CursorPosition()
    if not x then return end
    local state, config = sizingState, meter.config
    local screenWidth = ScreenSize()
    local width = math.min(state.width + x - state.x, screenWidth - state.left, state.maxWidth or math.huge)
    local height = math.min(state.height - (y - state.y), state.top, state.maxHeight or math.huge)
    width, height = Bounded(ranges.width, width, config.width), Bounded(ranges.height, height, config.height)
    local rect = ScratchRect("sizing", state.left, state.top, width, height)
    local others = self:OtherRects(self.sizingGroup)
    local xEdge, yEdge, xTarget, yTarget
    if not ShiftDown() then
        for key in pairs(skipBottom) do skipBottom[key] = nil end
        for key in pairs(skipRight) do skipRight[key] = nil end
        -- A linked window's shared edge moves with this one, so that edge does not snap to it.
        for id in pairs(sizingRow) do
            if scratchRects[id] then skipBottom[scratchRects[id]] = true end
        end
        for id in pairs(sizingColumn) do
            if scratchRects[id] then skipRight[scratchRects[id]] = true end
        end
        -- A pushed window moves with the edge it rests on, so that edge does not snap to it either.
        for _, id in ipairs(pushDown) do
            if scratchRects[id] then skipBottom[scratchRects[id]] = true end
        end
        for _, id in ipairs(pushRight) do
            if scratchRects[id] then skipRight[scratchRects[id]] = true end
        end
        local dRight, dBottom
        dRight, dBottom, xEdge, yEdge, xTarget, yTarget = Geometry.SnapSize(rect, others, nil, screenWidth, skipBottom,
            skipRight)
        width = math.min(Bounded(ranges.width, width + dRight, width), state.maxWidth or math.huge)
        height = math.min(Bounded(ranges.height, height - dBottom, height), state.maxHeight or math.huge)
        rect = ScratchRect("sizing", state.left, state.top, width, height)
    end
    width, height = math.floor(width + 0.5), math.floor(height + 0.5)
    if width ~= config.width or height ~= config.height then
        config.width, config.height = width, height
        meter.frame:SetSize(width, height)
        for id in pairs(sizingRow) do self:ResizeLinked(id, nil, height) end
        for id in pairs(sizingColumn) do self:ResizeLinked(id, width, nil) end
        self:PushAttached()
    end
    self:DrawSnapGuide(rect, others, xEdge, yEdge, xTarget, yTarget)
end

function ThreatConsole:ResizeLinked(id, width, height)
    local record, meter = self:GetWindow(id), self.meters[id]
    if not record or not meter then return end
    record.width, record.height = width or record.width, height or record.height
    meter.frame:SetSize(record.width, record.height)
end

-- Ends a resize without saving anything more (the window was rebound to another record).
function ThreatConsole:AbortSizing(meter)
    if not self.sizing or (meter and self.sizing ~= meter) then return false end
    local grip = self.sizing.grip
    if grip and grip.SetScript then grip:SetScript("OnUpdate", nil) end
    self.sizing = nil
    self.sizingEndedAt = type(GetTime) == "function" and GetTime() or nil
    ClearPushes()
    self:StopSnapFeedback()
    return true
end

-- Ends a resize: the size reached is kept (it was saved as it changed).
function ThreatConsole:StopSizing(meter)
    local sizing = self.sizing
    if not sizing or (meter and sizing ~= meter) then return false end
    self:UpdateSizing(true)
    self:AbortSizing(sizing)
    local config = sizing.config
    -- Resized while following above or below: it keeps this width instead of the meter's, until
    -- it is snapped back to the meter's width.
    if config.dockMeter > 0 and (config.dockSide == "above" or config.dockSide == "below")
        and config.width ~= sizingState.startWidth then
        local meterRect = self:ReadMeterRect(config.dockMeter)
        config.dockOwnWidth = not (meterRect and math.abs(meterRect.right - meterRect.left - config.width) < 1)
    end
    if config.dockMeter == 0 then KeepOnScreen(config) end
    sizing:Place()
    sizing:Layout()
    for _, line in ipairs({ sizingRow, sizingColumn }) do
        for id in pairs(line) do
            local linked = self.meters[id]
            if linked then
                linked:Place()
                linked:Layout()
            end
            line[id] = nil
        end
    end
    return true
end

-- Keys for the chain of windows following one meter window on one side.
local dockKeys = {}
for index = 1, METER_WINDOWS do
    dockKeys[index] = {}
    for side in pairs(dockSides) do dockKeys[index][side] = "dock" .. index .. side end
end
local chainEnds, chainMeters, dockQueue = {}, {}, {}

function ThreatConsole:MaxDockOrder()
    local highest = 0
    for _, record in ipairs(self:GetWindows()) do
        if type(record.dockOrder) == "number" and record.dockOrder > highest then highest = record.dockOrder end
    end
    return highest
end

-- Follows the Blizzard meter windows, on the side each window chose. Several windows following
-- one meter on one side chain: the first sits flush against the meter, each next one against
-- the one before, in window order. Left and right match the meter's height with the titles
-- level; above and below match its width unless the player resized the window. While the meter
-- is hidden its followers stay where they last docked, and rejoin it when it shows again.
-- Blizzard's frames are only read; nothing is anchored to, hooked on or set on them.
function ThreatConsole:UpdateDocking()
    local on = self:GetState().threatConsoleShown == true
    for key in pairs(chainEnds) do chainEnds[key], chainMeters[key] = nil, nil end
    -- Followers in the order they joined (insertion sort into a reused list; at most five).
    local count = 0
    for _, record in ipairs(self:GetWindows()) do
        if record.dockMeter > 0 then
            local slot = count + 1
            while slot > 1 and dockQueue[slot - 1].dockOrder > record.dockOrder do
                dockQueue[slot] = dockQueue[slot - 1]
                slot = slot - 1
            end
            dockQueue[slot] = record
            count = count + 1
        end
    end
    for index = count + 1, #dockQueue do dockQueue[index] = nil end
    local dragged = self.drag and self.drag.meter
    for index = 1, count do
        local record = dockQueue[index]
        local meter = self.meters[record.id]
        if meter and meter ~= dragged and on and record.shown then
            local key = dockKeys[record.dockMeter][record.dockSide]
            local anchor = chainEnds[key]
            if anchor == nil then
                anchor = self:ReadMeterRect(record.dockMeter) or false
                chainEnds[key], chainMeters[key] = anchor, anchor
            end
            if anchor then
                local meterRect, vertical = chainMeters[key], record.dockSide == "above" or record.dockSide == "below"
                local span
                if vertical then
                    span = not record.dockOwnWidth and meterRect.right - meterRect.left
                else
                    span = meterRect.top - meterRect.bottom
                end
                local left, top, width, height = Geometry.DockRect(anchor, record.dockSide, record.width, record.height, span)
                width = math.floor(Bounded(ranges.width, width, record.width) + 0.5)
                height = math.floor(Bounded(ranges.height, height, record.height) + 0.5)
                left, top = Geometry.OnScreen(left, top, width, height, ScreenSize())
                if left ~= record.left or top ~= record.top or width ~= record.width or height ~= record.height then
                    record.left, record.top, record.width, record.height = left, top, width, height
                    meter:Place()
                end
                chainEnds[key] = ScratchRect(key, left, top, width, height)
            end
        end
    end
end

-- Settings are protected in combat: then the shared route queues the main page instead.
function ThreatConsole:OpenSettings()
    if Secret.InCombat() and PS.Commands and PS.Commands.OpenSettings then return PS.Commands.OpenSettings() end
    if type(PS.OpenOptions) ~= "function" then return end
    PS.OpenOptions()
    local category = PS.Options and PS.Options.moduleSettings and PS.Options.moduleSettings.threatWindows
    if category and Settings and Settings.OpenToCategory and category.GetID then
        pcall(Settings.OpenToCategory, category:GetID())
    end
end

function ThreatConsole:PromptRename(id)
    local record = self:GetWindow(id)
    local options = PS.Options
    if not record or not options or type(options.PromptStudioName) ~= "function" then return false end
    local dialog = options:PromptStudioName(L["Name for this threat window:"], record.name, function(text)
        local ok, reason = self:RenameWindow(id, text)
        if ok then self:RefreshOptions() end
        return ok, reason
    end)
    -- The shared name box allows a profile name's length; a window name is shorter. The limit is
    -- put back when the box closes, for the next profile prompt.
    local edit = type(dialog) == "table" and dialog.edit
    if edit and edit.SetMaxLetters then
        edit:SetMaxLetters(NAME_LENGTH)
        if not dialog.threatNameLimitHooked and dialog.HookScript then
            dialog.threatNameLimitHooked = true
            dialog:HookScript("OnHide", function()
                edit:SetMaxLetters(PS.Profiles and PS.Profiles.MAX_NAME_LENGTH or 32)
            end)
        end
    end
    return true
end

function ThreatConsole:ConfirmDelete(id)
    local record = self:GetWindow(id)
    local options = PS.Options
    if not record then return false end
    if not options or type(options.ConfirmStudioAction) ~= "function" then
        local deleted = self:DeleteWindow(id)
        self:RefreshOptions()
        return deleted
    end
    options:ConfirmStudioAction(string.format(L["Delete the threat window \"%s\"?"], record.name), L["Delete"], function()
        self:DeleteWindow(id)
        self:RefreshOptions()
    end)
    return true
end

-- True when a shown window is joined to anything: following a meter, or sharing an edge with
-- another shown window or a Blizzard meter window.
function ThreatConsole:IsGrouped(id)
    local record, meter = self:GetWindow(id), self.meters[id]
    if not record or not meter or not meter.frame:IsShown() then return false end
    if record.dockMeter > 0 then return true end
    local rect = Geometry.Rect(record.left, record.top, record.width, record.height)
    for _, other in ipairs(self:OtherRects({ [id] = true })) do
        if Geometry.Touching(rect, other) then return true end
    end
    return false
end

-- Takes a window out of its group: it stops following a meter and moves clear of every other
-- window and meter window, so nothing moves or resizes with it any more. The rest stay put.
function ThreatConsole:DetachWindow(id)
    local record, meter = self:GetWindow(id), self.meters[id]
    if not record or not meter or record.locked or not self:IsGrouped(id) then return false end
    self:EndDrag()
    self:StopSizing()
    if record.dockMeter > 0 then self:SetWindowOption(id, "dockMeter", 0) end
    -- OtherRects hands out scratch rectangles; DetachSpot needs them to hold still.
    local others = {}
    for index, other in ipairs(self:OtherRects({ [id] = true })) do
        others[index] = Geometry.Rect(other.left, other.top, other.right - other.left, other.top - other.bottom)
    end
    local screenWidth, screenHeight = ScreenSize()
    record.left, record.top = Geometry.DetachSpot(Geometry.Rect(record.left, record.top, record.width, record.height),
        others, screenWidth, screenHeight)
    KeepOnScreen(record)
    meter:Place()
    self:MarkDirty()
    return true
end

-- The title's right-click menu. Option changes made here also refresh an open settings page.
function ThreatConsole:MenuItems(meter)
    local config = meter.config
    local id = config.id
    local function Set(key, value)
        return function()
            self:SetWindowOption(id, key, value)
            self:RefreshOptions()
        end
    end
    local items = {
        { text = string.format(L["Window %d: %s"], id, config.name), title = true },
        { text = L["Threat meter"], checked = config.mode == "threat", func = Set("mode", "threat") },
        { text = L["Tank"], checked = config.mode == "tank", func = Set("mode", "tank") },
        { text = L["Target first"], checked = config.targetFirst ~= false, disabled = config.mode ~= "tank",
            func = Set("targetFirst", config.targetFirst == false) },
        { separator = true },
    }
    for _, theme in ipairs(Themes.list) do
        items[#items + 1] = { text = theme.label, checked = config.theme == theme.id, func = Set("theme", theme.id) }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = config.locked and L["Unlock"] or L["Lock"], func = Set("locked", not config.locked) }
    items[#items + 1] = { text = L["Detach from group"], disabled = config.locked or not self:IsGrouped(id),
        func = function()
            self:DetachWindow(id)
            self:RefreshOptions()
        end }
    -- The menu has no submenus: "Follow damage meter" is a group of radio items (off or a side),
    -- then which of Blizzard's meter windows while following.
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = L["Follow damage meter"], title = true }
    items[#items + 1] = { text = L["Off"], checked = config.dockMeter == 0, func = Set("dockMeter", 0) }
    for _, side in ipairs(DOCK_SIDE_ORDER) do
        items[#items + 1] = { text = dockSideLabels[side], checked = config.dockMeter > 0 and config.dockSide == side,
            func = function()
                self:SetWindowOption(id, "dockSide", side)
                if config.dockMeter == 0 then self:SetWindowOption(id, "dockMeter", 1) end
                self:RefreshOptions()
            end }
    end
    if config.dockMeter > 0 then
        for index = 1, METER_WINDOWS do
            items[#items + 1] = { text = string.format(L["Meter window %d"], index), checked = config.dockMeter == index,
                func = Set("dockMeter", index) }
        end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = L["New window"], disabled = not self:CanCreateWindow(),
        func = function() self:OnButton(meter, "new-window") end }
    items[#items + 1] = { text = L["Rename..."], func = function() self:PromptRename(id) end }
    items[#items + 1] = { text = L["Hide window"], func = Set("shown", false) }
    items[#items + 1] = { text = L["Delete window..."], func = function() self:ConfirmDelete(id) end }
    items[#items + 1] = { text = L["Sample data"], checked = self:IsSampleData(), disabled = Secret.InCombat(),
        func = function()
            self:SetSampleData(not self:IsSampleData())
            self:RefreshOptions()
        end }
    items[#items + 1] = { text = L["Threat window settings..."], func = function() self:OpenSettings() end }
    return items
end

function ThreatConsole:OpenMenu(meter, anchor)
    local menu = PS.UI and PS.UI.Menu
    if not menu then return nil end
    return menu.Open(anchor or meter.titleBar, self:MenuItems(meter))
end

function ThreatConsole:OnButton(meter, kind)
    local config = meter.config
    if kind == "close" then
        self:ShowWindow(config.id, false)
    elseif kind == "menu" then
        self:OpenMenu(meter, meter.buttons.menu)
    elseif kind == "lock" then
        self:SetWindowOption(config.id, "locked", not config.locked)
    elseif kind == "mode" then
        self:SetWindowOption(config.id, "mode", config.mode == "threat" and "tank" or "threat")
    elseif kind == "new-window" then
        -- At the limit the button already looks unavailable; nothing to report.
        if not self:CanCreateWindow() then return end
        self:CreateWindow()
    end
    self:RefreshOptions()
end

-- A diagnostics section: readable window facts only.
function ThreatConsole:Report()
    local windows = PS.Json and PS.Json.Array and PS.Json.Array() or {}
    for _, record in ipairs(self:GetWindows()) do
        local meter = self.meters[record.id]
        windows[#windows + 1] = { id = record.id, mode = record.mode, theme = record.theme, shown = record.shown,
            visible = meter and meter.frame:IsShown() or false, dock = record.dockMeter > 0 and
                string.format("meter %d %s", record.dockMeter, record.dockSide) or "none" }
    end
    return { on = self:GetState().threatConsoleShown == true, windows = windows,
        sample = Sample.enabled == true, lastClick = self.lastHighlightCheck or "none" }
end

function ThreatConsole:OnInitialize()
    self.service = PS.ThreatService or PS:GetModule("platesmith.threat-service")
    if not self.service then error("ThreatService must load before ThreatConsole") end
    local list = NormalizeWindows(self:GetWindows())
    self:GetState().threatWindows = list
    if #list == 0 then self:CreateWindow() end
    for _, record in ipairs(list) do self:EnsureMeter(record) end
    self:UpdateWindowButtons()
    self:ApplyVisibility()
end

function ThreatConsole:OnEnable()
    self:MarkDirty()
    if self:GetState().threatConsoleShown then self:Show(false) end
end

function ThreatConsole:OnDisable()
    self:Hide(false)
end

ThreatConsole._Test = { NormalizeWindows = NormalizeWindows, NameLength = NAME_LENGTH, RefreshInterval = REFRESH_INTERVAL }

local registered = PS:RegisterModule("platesmith.threat-console", ThreatConsole)
if registered then PS.ThreatConsole = registered end

PS.Ticker.Register("threat.console", REFRESH_INTERVAL, function() ThreatConsole:Refresh() end)
PS.Ticker.Register("threat.snap", SNAP_INTERVAL, function() ThreatConsole:UpdateSnapGuide() end)
PS.Ticker.Register("threat.dock", DOCK_INTERVAL, function() ThreatConsole:UpdateDocking() end)
PS.Ticker.SetEnabled("threat.console", false)
PS.Ticker.SetEnabled("threat.snap", false)
PS.Ticker.SetEnabled("threat.dock", false)

-- Registered at load: Forever may refuse new event subscriptions once the UI is in combat.
local screenEvents = CreateFrame("Frame")
ThreatConsole.screenEvents = screenEvents
PS._RegisterEvent(screenEvents, "UI_SCALE_CHANGED", "platesmith.threat-console")
PS._RegisterEvent(screenEvents, "DISPLAY_SIZE_CHANGED", "platesmith.threat-console")
PS._RegisterEvent(screenEvents, "PLAYER_REGEN_DISABLED", "platesmith.threat-console")
screenEvents:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_DISABLED" then return ThreatConsole:KeepWindowsOnScreen() end
    if ThreatConsole:IsSampleData() then
        ThreatConsole:SetSampleData(false)
        ThreatConsole:RefreshOptions()
    end
end)
