local _, PS = ...
local L = PS.L

-- PlateSmith's own button on the minimap's edge, for minimaps without the Addon Compartment (Forever's
-- classic-style one): left-click opens Blueprint Studio, right-click Studio's Settings, a drag moves it round the
-- edge. No library. It is the player's, account-wide (state, never a profile or a Blueprint): shown unless
-- Settings › Studio › Show minimap button is off (minimapButtonHidden), at minimapButtonAngle (degrees from the
-- right, anticlockwise). A plain button: nothing here is protected, so it works the same in combat.
local MinimapButton = {}
PS.MinimapButton = MinimapButton

MinimapButton.DEFAULT_ANGLE = 225
MinimapButton.ICON = "Interface\\AddOns\\PlateSmith\\Media\\PlateSmithIcon"
-- How far past the minimap's edge the button's centre sits (px).
local RIM_OUTSET = 5
-- (Lua 5.1 has atan2; newer Lua's atan takes y and x.)
local atan2 = math.atan2 or math.atan

local button

local function State()
    return type(PS.GetState) == "function" and PS.GetState() or nil
end

local function MinimapFrame() return rawget(_G, "Minimap") end

-- The minimap's shape as another addon (a square-minimap skin) reports it through GetMinimapShape, else ROUND.
local function Shape()
    local getShape = rawget(_G, "GetMinimapShape")
    if type(getShape) ~= "function" then return "ROUND" end
    local ok, shape = pcall(getShape)
    return ok and type(shape) == "string" and shape or "ROUND"
end

function MinimapButton.Shown()
    local state = State()
    return not (state and state.minimapButtonHidden == true)
end

function MinimapButton.Angle()
    local state = State()
    return state and tonumber(state.minimapButtonAngle) or MinimapButton.DEFAULT_ANGLE
end

-- Where the button's centre sits from the minimap's centre at angle (degrees), for a minimap width by height: on a
-- round one's rim; on any other shape (square, or a corner or side of one) on the square's edge.
function MinimapButton.Offset(angle, width, height, shape)
    local radians = math.rad(angle)
    local x, y = math.cos(radians), math.sin(radians)
    if shape ~= "ROUND" then
        local reach = math.max(math.abs(x), math.abs(y))
        x, y = x / reach, y / reach
    end
    return x * (width / 2 + RIM_OUTSET), y * (height / 2 + RIM_OUTSET)
end

local function Place()
    local minimap = MinimapFrame()
    if not (button and minimap) then return end
    local width, height = tonumber(minimap:GetWidth()) or 140, tonumber(minimap:GetHeight()) or 140
    local x, y = MinimapButton.Offset(MinimapButton.Angle(), width, height, Shape())
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

-- The angle from the minimap's centre to the cursor, kept (rounded to 0.1 degree) and the button placed there.
local function FollowCursor()
    local minimap, state = MinimapFrame(), State()
    if not (minimap and state and type(GetCursorPosition) == "function") then return end
    local centreX, centreY = minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = tonumber(minimap:GetEffectiveScale())
    if not (tonumber(centreX) and tonumber(centreY) and tonumber(cursorX) and tonumber(cursorY) and scale and scale > 0) then
        return
    end
    local angle = math.deg(atan2(cursorY / scale - centreY, cursorX / scale - centreX)) % 360
    state.minimapButtonAngle = math.floor(angle * 10 + 0.5) / 10 % 360
    Place()
end

local function ShowTooltip(owner)
    if not GameTooltip or owner.dragging then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("PlateSmith")
    GameTooltip:AddLine(L["Left-click: open or close Blueprint Studio."], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: open or close Studio's Settings."], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move this button round the minimap."], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Studio › Settings › Studio hides it."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- LeftButton opens Studio, RightButton Studio's Settings (the header's Settings toggle); each closes what it opens
-- when that is already showing (Left: Studio on any page; Right: Settings), as Studio's close button does (unsaved
-- changes ask first). Right-click over Studio's parts page goes to Settings.
function MinimapButton.Click(mouseButton)
    if GameTooltip then GameTooltip:Hide() end
    local options = PS.Options
    local editor = options and options.editor
    if editor and editor:IsShown() then
        local onSettings = options.editorWorkspacePage == "settings"
        if mouseButton ~= "RightButton" or onSettings then
            local close = options.editorCloseButton
            local onClick = close and close:GetScript("OnClick")
            if onClick then return onClick(close) end
            return editor:Hide()
        end
    end
    if mouseButton == "RightButton" then return PS.OpenStudioSettings() end
    return PS.OpenVisualEditor()
end

-- The minimap's own button look: a dark disc, the icon and the tracking button's ring.
local function Create(minimap)
    local made = CreateFrame("Button", "PlateSmithMinimapButton", minimap)
    made:SetSize(31, 31)
    made:SetFrameStrata("MEDIUM")
    made:SetFrameLevel((tonumber(minimap:GetFrameLevel()) or 1) + 8)
    made:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    made:RegisterForDrag("LeftButton")
    made:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = made:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", made, "TOPLEFT", 7, -5)
    local icon = made:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(MinimapButton.ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", made, "TOPLEFT", 7, -6)
    local ring = made:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetPoint("TOPLEFT", made, "TOPLEFT", 0, 0)
    made.icon = icon
    made:SetScript("OnClick", function(_, mouseButton) MinimapButton.Click(mouseButton) end)
    made:SetScript("OnEnter", ShowTooltip)
    made:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- A transient OnUpdate while the mouse drags, cleared when it ends (STANDARDS section 4).
    made:SetScript("OnDragStart", function(self)
        self.dragging = true
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", FollowCursor)
    end)
    made:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragging = nil
        FollowCursor()
    end)
    made:Hide()
    return made
end

-- Shows the button where the player put it, or hides it (made the first time it shows; nothing without a minimap).
-- True while it shows.
function MinimapButton.Apply()
    if not MinimapButton.Shown() then
        if button then button:Hide() end
        return false
    end
    local minimap = MinimapFrame()
    if not minimap then return false end
    button = button or Create(minimap)
    Place()
    button:Show()
    return true
end

-- Settings › Studio › Show minimap button.
function MinimapButton.SetShown(on)
    local state = State()
    if not state then return false end
    local was = state.minimapButtonHidden ~= true
    state.minimapButtonHidden = on ~= true or nil
    MinimapButton.Apply()
    if was ~= (on == true) and PS.ActivityLog then PS.ActivityLog.Account("minimap", on == true and "shown" or "hidden") end
    return true
end

function MinimapButton.Frame() return button end
