local _, PS = ...

if not PS or type(PS.RegisterModule) ~= "function" then return end

local REFRESH_INTERVAL = 0.25
local POSITION_SAVE_INTERVAL = 0.1
local MAX_ROWS = 14

local ThreatConsole = { dirty = true, refreshElapsed = 0, positionElapsed = 0 }

local function Abbreviate(value)
    if type(value) ~= "number" then return nil end
    local absolute = math.abs(value)
    if absolute >= 1000000 then return string.format("%.1fm", value / 1000000) end
    if absolute >= 1000 then return string.format("%.1fk", value / 1000) end
    return tostring(value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5))
end

local function FormatThreat(percent, differential)
    local percentText = type(percent) == "number" and string.format("%d%%", math.floor(percent + 0.5)) or nil
    local differentialText = type(differential) == "number"
        and ((differential > 0 and "+" or "") .. Abbreviate(differential)) or nil
    if percentText and differentialText then return percentText .. " " .. differentialText end
    return percentText or differentialText or "--"
end

local function FormatHoldState(entry)
    if entry.holdState then return entry.holdState end
    if not entry.engaged then return "IDLE" end
    return entry.loose and "LOOSE" or "TANK"
end

local function FormatCount(count, singular, plural)
    if count == nil then return "--" end
    return count == 1 and ("1 " .. singular) or (count .. " " .. plural)
end

local function SetStatusColour(fontString, state)
    if state == "LOOSE" then
        fontString:SetTextColor(1, 0.25, 0.18)
    elseif state == "IDLE" then
        fontString:SetTextColor(0.62, 0.65, 0.68)
    else
        fontString:SetTextColor(0.25, 1, 0.38)
    end
end

local function CreateColumnText(parent, x, width, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("LEFT", parent, "LEFT", x, 0)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function CreateRow(parent, index, module)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -50 - ((index - 1) * 18))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -50 - ((index - 1) * 18))
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.background:SetColorTexture(0.08, 0.08, 0.08, index % 2 == 0 and 0.7 or 0.45)
    row.target = CreateColumnText(row, 3, 86)
    row.enemy = CreateColumnText(row, 92, 104)
    row.state = CreateColumnText(row, 200, 52, "GameFontNormalSmall")
    row.attacking = CreateColumnText(row, 256, 74)
    row.targeting = CreateColumnText(row, 334, 74)
    row.threat = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.threat:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.threat:SetWidth(94)
    row.threat:SetJustifyH("RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(owner) module:ShowActivityTooltip(owner) end)
    row:SetScript("OnLeave", function(owner) module:HideActivityTooltip(owner) end)
    row:SetScript("OnMouseUp", function(owner, button)
        if button == "LeftButton" then module:HighlightRow(owner) end
    end)
    return row
end

local function CreateHeader(frame, text, x, width, justify)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -31)
    label:SetWidth(width)
    label:SetJustifyH(justify or "LEFT")
    label:SetText(text)
    return label
end

local function CreateWindow(module)
    local settings = type(PS.GetSettings) == "function" and PS.GetSettings() or nil
    local frame = CreateFrame("Frame", "PlateSmithThreatConsole", UIParent, "BackdropTemplate")
    frame:SetSize(568, 58 + (MAX_ROWS * 18))
    frame:SetPoint("CENTER", UIParent, "CENTER", settings and settings.threatConsoleX or 260,
        settings and settings.threatConsoleY or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner)
        local ok = pcall(owner.StartMoving, owner)
        if ok then
            module.dragging, module.positionElapsed = true, 0
            module.dragBlockedReported = false
        elseif not module.dragBlockedReported then
            module.dragBlockedReported = true
            module:Notify("The client blocked moving the threat window right now.")
        end
    end)
    frame:SetScript("OnDragStop", function(owner)
        if not module.dragging then return end
        pcall(owner.StopMovingOrSizing, owner)
        module.dragging = false
        module:SavePosition()
    end)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.025, 0.03, 0.035, 0.94)
    frame:SetBackdropBorderColor(0.25, 0.72, 0.9, 0.9)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -8)
    frame.title:SetText("PlateSmith Threat")
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -9)
    frame.summary:SetJustifyH("RIGHT")
    frame.headers = {
        CreateHeader(frame, "TARGET", 11, 86), CreateHeader(frame, "ENEMY", 100, 104),
        CreateHeader(frame, "STATE", 208, 52), CreateHeader(frame, "ATTACKING", 264, 74),
        CreateHeader(frame, "TARGETING", 342, 74), CreateHeader(frame, "YOU", 464, 94, "RIGHT"),
    }
    frame.rows = {}
    for index = 1, MAX_ROWS do frame.rows[index] = CreateRow(frame, index, module) end
    frame:SetScript("OnUpdate", function(_, elapsed) module:OnUpdate(elapsed) end)
    frame:SetScript("OnShow", function() module:MarkDirty() end)
    frame:Hide()
    return frame
end

function ThreatConsole:GetSettings()
    return type(PS.GetSettings) == "function" and PS.GetSettings() or nil
end

function ThreatConsole:BuildSnapshot()
    if not self.service then return self.emptySnapshot, 0, 0, 0, 0 end
    return self.service:GetSnapshot()
end

function ThreatConsole:SavePosition()
    local settings = self:GetSettings()
    if not settings or not self.window or type(self.window.GetCenter) ~= "function"
        or not UIParent or type(UIParent.GetCenter) ~= "function" then return false end
    local x, y = self.window:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if type(x) ~= "number" or type(y) ~= "number" or type(parentX) ~= "number" or type(parentY) ~= "number" then
        return false
    end
    settings.threatConsoleX = math.floor(x - parentX + 0.5)
    settings.threatConsoleY = math.floor(y - parentY + 0.5)
    return true
end

function ThreatConsole:ShowActivityTooltip(row)
    if not row or not row.unit or not self.service or not GameTooltip then return end
    local attacking = self.service:GetActiveAttackerCount(row.unit)
    local targeting = self.service:GetTargeterCount(row.unit)
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.enemyName or "Enemy")
    GameTooltip:AddLine("Actively attacking", 1, 0.82, 0)
    if attacking == 0 then
        GameTooltip:AddLine("No recent damage + current target match.", 0.72, 0.72, 0.72)
    else
        local anyInferred = false
        for index = 1, attacking do
            local name, _, inferred = self.service:GetActiveAttacker(row.unit, index)
            if inferred then anyInferred = true end
            GameTooltip:AddLine((name or "Unknown") .. (inferred and " (inferred)" or ""), 1, 1, 1)
        end
        if anyInferred then
            GameTooltip:AddLine("Inferred = mob damage plus a matching current target.", 0.62, 0.72, 0.82)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Currently targeting", 1, 0.82, 0)
    if targeting == 0 then
        GameTooltip:AddLine("No group members targeting this enemy.", 0.72, 0.72, 0.72)
    else
        for index = 1, targeting do
            local name = self.service:GetTargeter(row.unit, index)
            GameTooltip:AddLine(name or "Unknown", 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click spotlights this exact visible unit.", 0.55, 0.8, 1)
    GameTooltip:AddLine("Click its world plate to target it.", 0.62, 0.72, 0.82)
    GameTooltip:Show()
end

function ThreatConsole:HideActivityTooltip(row)
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(row)) then GameTooltip:Hide() end
end

ThreatConsole.ShowAttackerTooltip = ThreatConsole.ShowActivityTooltip
ThreatConsole.HideAttackerTooltip = ThreatConsole.HideActivityTooltip

function ThreatConsole:Notify(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffd6a84bPlateSmith:|r " .. message)
    end
end

function ThreatConsole:HighlightRow(row)
    if not row or not row.unit or not self.service then return false end
    local current, reason = self.service:IsCurrentPlate(row.unit, row.serial, row.root, row.guid)
    if not current then
        self.lastHighlightCheck = reason or "unavailable"
        self:Notify("That nameplate is no longer available.")
        return false
    end
    if type(PS.HighlightPlate) ~= "function" or not PS.HighlightPlate(row.unit) then
        self.lastHighlightCheck = "overlay-hidden"
        return false
    end
    self.lastHighlightCheck = "highlighted"
    return true
end

ThreatConsole.TargetRow = ThreatConsole.HighlightRow

function ThreatConsole:Refresh()
    local snapshot, count, totalVisible, totalLoose, totalEngaged = self:BuildSnapshot()
    local visibleRows = math.min(count, MAX_ROWS)
    local previousTarget
    for index = 1, MAX_ROWS do
        local row, entry = self.window.rows[index], snapshot[index]
        if index <= visibleRows and entry then
            row.target:SetText(entry.targetName ~= previousTarget and entry.targetName or "  -")
            row.enemy:SetText(entry.enemyName or "Unknown enemy")
            local state = FormatHoldState(entry)
            row.state:SetText(state)
            SetStatusColour(row.state, state)
            row.attacking:SetText(FormatCount(entry.activeAttackerCount, "active", "active"))
            row.targeting:SetText(FormatCount(entry.targeterCount, "target", "targets"))
            if not entry.engaged then
                row.threat:SetText("")
            elseif type(PS.ApplyThreatText) == "function" then
                PS.ApplyThreatText(row.threat, entry)
            else
                row.threat:SetText(FormatThreat(entry.playerPercent, entry.playerDifferential))
            end
            row.unit, row.guid, row.enemyName = entry.unit, entry.guid, entry.enemyName
            row.serial, row.root = entry.serial, entry.root
            row:Show()
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then self:ShowActivityTooltip(row) end
            previousTarget = entry.targetName
        else
            self:HideActivityTooltip(row)
            row.unit, row.guid, row.enemyName = nil, nil, nil
            row.serial, row.root = nil, nil
            row:Hide()
        end
    end
    self.window.summary:SetText(string.format("%d visible  |  %d engaged  |  %d loose", totalVisible, totalEngaged, totalLoose))
    self.window:SetHeight(58 + (math.max(visibleRows, 1) * 18))
    self.dirty = false
end

function ThreatConsole:MarkDirty()
    self.dirty = true
    if self.service then self.service:MarkDirty() end
end

function ThreatConsole:OnUpdate(elapsed)
    if not self.window or not self.window:IsShown() then return end
    if self.dragging then
        self.positionElapsed = self.positionElapsed + elapsed
        if self.positionElapsed >= POSITION_SAVE_INTERVAL then
            self.positionElapsed = 0
            self:SavePosition()
        end
    end
    self.refreshElapsed = self.refreshElapsed + elapsed
    if self.refreshElapsed < REFRESH_INTERVAL then return end
    self.refreshElapsed = self.refreshElapsed - REFRESH_INTERVAL
    self:Refresh()
end

function ThreatConsole:Show(persist)
    if not self.window then return end
    if persist ~= false then
        local settings = self:GetSettings()
        if settings then settings.threatConsoleShown = true end
    end
    self.window:Show()
    self.refreshElapsed = 0
    self:Refresh()
end

function ThreatConsole:Hide(persist)
    if not self.window then return end
    if persist ~= false then
        local settings = self:GetSettings()
        if settings then settings.threatConsoleShown = false end
    end
    for index = 1, #self.window.rows do self:HideActivityTooltip(self.window.rows[index]) end
    self.window:Hide()
end

function ThreatConsole:Toggle()
    if self.window and self.window:IsShown() then self:Hide() else self:Show() end
end

function ThreatConsole:OnInitialize()
    self.service = PS.ThreatService or PS:GetModule("platesmith.threat-service")
    if not self.service then error("ThreatService must load before ThreatConsole") end
    self.emptySnapshot = {}
    self.window = CreateWindow(self)
end

function ThreatConsole:OnEnable()
    self:MarkDirty()
    local settings = self:GetSettings()
    if settings and settings.threatConsoleShown then self:Show(false) end
end

function ThreatConsole:OnDisable()
    self:SavePosition()
    self:Hide(false)
end

ThreatConsole._Test = {
    FormatThreat = FormatThreat, FormatHoldState = FormatHoldState, FormatCount = FormatCount,
    MaxRows = MAX_ROWS, RefreshInterval = REFRESH_INTERVAL, PositionSaveInterval = POSITION_SAVE_INTERVAL,
}

local registered = PS:RegisterModule("platesmith.threat-console", ThreatConsole)
if registered then PS.ThreatConsole = registered end
