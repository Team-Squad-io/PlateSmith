local _, PS = ...
local L = PS.L
local Themes = assert(PS.ThreatThemes, "PlateSmith ThreatThemes missing")
local Geometry = assert(PS.ThreatGeometry, "PlateSmith ThreatGeometry missing")
local Format = assert(PS.Format, "PlateSmith Format missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local ThreatText = assert(PS.ThreatText, "PlateSmith ThreatText missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")

-- One threat window: its frame, chrome for the chosen theme, and rows that fill the height.
-- Threat meter mode lists the group's threat on your target; tank mode lists every enemy in
-- view and who holds it. Rows are pooled and only redrawn when the threat service changed.
local Meter = {}
PS.ThreatMeter = Meter
Meter.__index = Meter

local MAX_ROWS = 40
local BUTTON_SIZE = 16
local SCROLL_WIDTH = 6
-- Title room kept for the window's name before the summary beside it is shown.
local TITLE_NAME_WIDTH, SUMMARY_MIN_WIDTH = 80, 50
local BUTTONS = { "close", "menu", "lock", "mode", "new-window" }
local BUTTON_TIPS = {
    close = L["Hide this window"], menu = L["Window menu"], lock = L["Lock or unlock"],
    mode = L["Switch between threat meter and tank mode"], ["new-window"] = L["New window"],
}
local STATE_ICONS = { TANK = "icon-tank", LOOSE = "icon-loose", IDLE = "icon-idle", YOU = "icon-you" }
-- The hold state spelt out in the STATE column (the service's tokens are never shown raw).
local STATE_LABELS = { TANK = L["TANK"], LOOSE = L["LOOSE"], IDLE = L["IDLE"], YOU = L["YOU"] }
local ROLE_ICONS = { TANK = "icon-role-tank", HEALER = "icon-role-healer", DAMAGER = "icon-role-damage" }
local IDLE_COLOUR = { 0.62, 0.65, 0.68 }
local MUTED = { 0.72, 0.72, 0.74 }
local ROW_TEXTS = { "name", "state", "on", "attackers", "value", "gap" }
local ROW_COLUMNS = { "name", "state", "on", "attackers", "gap" }
local HEADER_KEYS = { "name", "state", "on", "attackers", "you", "gap", "percent" }

-- A count through singular and plural format strings (each with one %d), or "--" when unknown.
local function FormatCount(count, singular, plural)
    if count == nil then return "--" end
    return string.format(count == 1 and singular or plural, count)
end

-- The hold state's colour from the plates' palette (standard or colour-blind); the state is
-- also spelt out, so colour never carries it alone.
local function StateColour(state)
    if state == "IDLE" then return IDLE_COLOUR end
    local palette = ThreatText.Palette()
    if state == "LOOSE" then return palette.losing end
    return palette.hold
end

-- Threat % colour on the meter: holding (hold), at or past pulling (losing), close (warning).
local function MemberColour(entry, theme)
    local palette = ThreatText.Palette()
    if entry.tanking == true then return palette.hold end
    if type(entry.percent) == "number" and entry.percent >= 100 then return palette.losing end
    if type(entry.percent) == "number" and entry.percent >= 80 then return palette.warning end
    return theme.text
end

local function ClassColour(entry)
    local colours = rawget(_G, "RAID_CLASS_COLORS")
    local colour = entry.classToken and type(colours) == "table" and colours[entry.classToken]
    if colour and type(colour.r) == "number" then return colour.r, colour.g, colour.b end
    return 0.55, 0.58, 0.62
end

-- One column of a layout, from the layout's own pool so a live resize allocates nothing.
local function Column(layout, key, x, width, justify)
    local column = layout.pool[key]
    if not column then
        column = {}
        layout.pool[key] = column
    end
    column.x, column.width, column.justify = x, width, justify
    layout[key] = column
end

-- Column positions inside a row of this width: name flexes, the rest are fixed from the right.
-- layout, when given, is refilled in place.
local function ColumnLayout(mode, width, iconSize, layout)
    layout = layout or { pool = {} }
    for _, key in ipairs(HEADER_KEYS) do layout[key] = nil end
    local columns = Geometry.Columns(mode, width, layout.columns)
    layout.columns = columns
    local left = 2 + (iconSize + 2) * 2
    local right = width - 3
    if mode == "threat" then
        Column(layout, "percent", right - 46, 46, "RIGHT")
        right = right - 52
        if columns.gap then
            Column(layout, "gap", right - 50, 50, "RIGHT")
            right = right - 56
        end
    else
        Column(layout, "you", right - 92, 92, "RIGHT")
        right = right - 98
        if columns.attackers then
            Column(layout, "attackers", right - 64, 64, "RIGHT")
            right = right - 70
        end
        if columns.on then
            Column(layout, "on", right - 84, 84, "LEFT")
            right = right - 90
        end
        Column(layout, "state", right - 44, 44, "LEFT")
        right = right - 50
    end
    Column(layout, "name", left, math.max(20, right - left), "LEFT")
    return layout
end

local function SetFont(fontString, name, fallback)
    local font = name and rawget(_G, name)
    if font then
        pcall(fontString.SetFontObject, fontString, font)
    elseif fallback then
        pcall(fontString.SetFontObject, fontString, rawget(_G, fallback) or fallback)
    end
end

local function Text(parent, layer, template)
    local text = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    return text
end

local function CreateRow(meter)
    local row = CreateFrame("StatusBar", nil, meter.body)
    row.meter = meter
    row:SetMinMaxValues(0, 100)
    row:SetValue(0)
    row.backdrop = row:CreateTexture(nil, "BACKGROUND")
    row.backdrop:SetAllPoints()
    row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight = row:CreateTexture(nil, "ARTWORK", nil, 6)
    row.highlight:Hide()
    row.selectedLeft = row:CreateTexture(nil, "ARTWORK", nil, 7)
    row.selectedMid = row:CreateTexture(nil, "ARTWORK", nil, 7)
    row.selectedRight = row:CreateTexture(nil, "ARTWORK", nil, 7)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.marker = row:CreateTexture(nil, "OVERLAY")
    row.name = Text(row)
    row.state = Text(row)
    row.on = Text(row)
    row.attackers = Text(row)
    row.value = Text(row)
    row.gap = Text(row)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(owner)
        owner.highlight:Show()
        owner.meter.console:ShowRowTooltip(owner)
    end)
    row:SetScript("OnLeave", function(owner)
        owner.highlight:Hide()
        owner.meter.console:HideRowTooltip(owner)
    end)
    row:SetScript("OnMouseUp", function(owner, button)
        if button == "LeftButton" then owner.meter.console:HighlightRow(owner) end
    end)
    -- Blank until the next render fills it.
    row:Hide()
    return row
end

-- An unavailable button keeps its disabled art whatever the mouse does.
local function SetButtonArt(button, state)
    if button.unavailable then state = "disabled" end
    button.state = state
    local theme = button.meter.theme
    local file = Themes.ButtonFile(theme, button.art, state)
    Themes.Place(button.texture, file, button, 0, 0, BUTTON_SIZE, BUTTON_SIZE)
end

local function CreateButton(meter, kind)
    local button = CreateFrame("Button", nil, meter.titleBar)
    button.meter, button.kind, button.art = meter, kind, kind
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button:SetScript("OnEnter", function(owner)
        SetButtonArt(owner, "hover")
        if GameTooltip then
            GameTooltip:SetOwner(owner, "ANCHOR_TOP")
            GameTooltip:SetText(BUTTON_TIPS[owner.kind] or "")
            if owner.unavailable and owner.kind == "new-window" then
                GameTooltip:AddLine(string.format(L["At most %d threat windows."], Geometry.MAX_WINDOWS),
                    0.72, 0.72, 0.72)
            end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(owner)
        SetButtonArt(owner, "normal")
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(owner)) then GameTooltip:Hide() end
    end)
    button:SetScript("OnMouseDown", function(owner) SetButtonArt(owner, "pressed") end)
    button:SetScript("OnMouseUp", function(owner) SetButtonArt(owner, "hover") end)
    button:SetScript("OnClick", function(owner)
        if not owner.unavailable then owner.meter.console:OnButton(owner.meter, owner.kind) end
    end)
    return button
end

local function CreateFrames(meter)
    local id = meter.config.id
    local frame = Window.Create("PlateSmithThreatWindow" .. id, {
        width = meter.config.width, height = meter.config.height, strata = "DIALOG",
        movable = false, closeButton = false, closeOnEscape = false,
        background = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
    })
    frame.meter = meter
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetClipsChildren then frame:SetClipsChildren(true) end
    frame.fill = frame:CreateTexture(nil, "BACKGROUND")
    frame.meterBackground = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.edges = {}
    for index = 1, 8 do frame.edges[index] = frame:CreateTexture(nil, "BORDER") end

    local titleBar = CreateFrame("Frame", nil, frame)
    meter.titleBar = titleBar
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar.fill = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBar.left = titleBar:CreateTexture(nil, "BORDER")
    titleBar.mid = titleBar:CreateTexture(nil, "BORDER")
    titleBar.right = titleBar:CreateTexture(nil, "BORDER")
    titleBar.emblem = titleBar:CreateTexture(nil, "ARTWORK")
    titleBar.badge = titleBar:CreateTexture(nil, "ARTWORK")
    titleBar.pieces = { titleBar.left, titleBar.mid, titleBar.right, titleBar.emblem, titleBar.badge }
    titleBar.digit = Text(titleBar, "OVERLAY", "GameFontHighlightSmall")
    titleBar.digit:SetJustifyH("CENTER")
    titleBar.text = Text(titleBar, "OVERLAY", "GameFontNormal")
    titleBar.summary = Text(titleBar, "OVERLAY", "GameFontHighlightSmall")
    titleBar.summary:SetJustifyH("RIGHT")
    meter.buttons = {}
    for _, kind in ipairs(BUTTONS) do meter.buttons[kind] = CreateButton(meter, kind) end

    local header = CreateFrame("Frame", nil, frame)
    meter.header = header
    header.left = header:CreateTexture(nil, "BORDER")
    header.mid = header:CreateTexture(nil, "BORDER")
    header.right = header:CreateTexture(nil, "BORDER")
    header.pieces = { header.left, header.mid, header.right }
    header.labels = {}
    for _, key in ipairs(HEADER_KEYS) do
        header.labels[key] = Text(header, "OVERLAY", "GameFontDisableSmall")
    end

    local body = CreateFrame("Frame", nil, frame)
    meter.body = body
    body:EnableMouse(false)
    if body.EnableMouseWheel then body:EnableMouseWheel(true) end
    body:SetScript("OnMouseWheel", function(_, delta) meter:Scroll(-(delta or 0)) end)
    if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    frame:SetScript("OnMouseWheel", function(_, delta) meter:Scroll(-(delta or 0)) end)
    body.track = { body:CreateTexture(nil, "ARTWORK"), body:CreateTexture(nil, "ARTWORK"), body:CreateTexture(nil, "ARTWORK") }
    body.thumb = { body:CreateTexture(nil, "OVERLAY"), body:CreateTexture(nil, "OVERLAY"), body:CreateTexture(nil, "OVERLAY") }
    body.empty = Text(body, "OVERLAY", "GameFontDisableSmall")
    body.empty:SetJustifyH("CENTER")
    if body.empty.SetWordWrap then body.empty:SetWordWrap(true) end
    body.more = Text(frame, "OVERLAY", "GameFontDisableSmall")
    body.more:SetJustifyH("RIGHT")

    local grip = CreateFrame("Button", nil, frame)
    meter.grip = grip
    grip:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip.texture = grip:CreateTexture(nil, "OVERLAY")
    grip.texture:SetAllPoints()
    grip:SetScript("OnMouseDown", function()
        if GameTooltip then GameTooltip:Hide() end
        meter.console:StartSizing(meter)
    end)
    grip:SetScript("OnMouseUp", function() meter.console:StopSizing(meter) end)
    grip:SetScript("OnEnter", function(instance)
        meter:SetGripArt("hover")
        if GameTooltip and meter.console:GripTooltipAllowed() then
            GameTooltip:SetOwner(instance, "ANCHOR_TOP")
            GameTooltip:SetText(L["Resize"])
            GameTooltip:AddLine(L["Drag to resize. Edges snap to windows beside or below, the screen edge "
                .. "and Blizzard's damage meter; windows side by side share one height."], 1, 0.82, 0.45, true)
            GameTooltip:AddLine(L["Windows stacked below or snapped on the right move to stay attached."],
                1, 0.82, 0.45, true)
            GameTooltip:AddLine(L["Hold Shift as you start to resize this window alone: no snapping, nothing moved."],
                0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    grip:SetScript("OnLeave", function(instance)
        meter:SetGripArt("normal")
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(instance)) then GameTooltip:Hide() end
    end)

    local function DragStart()
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(titleBar) then GameTooltip:Hide() end
        meter.console:StartDrag(meter)
    end
    local function DragStop() meter.console:StopDrag(meter) end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", DragStart)
    frame:SetScript("OnDragStop", DragStop)
    titleBar:SetScript("OnDragStart", DragStart)
    titleBar:SetScript("OnDragStop", DragStop)
    titleBar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then meter.console:OpenMenu(meter, titleBar) end
    end)
    titleBar:SetScript("OnEnter", function(owner)
        if not GameTooltip or not meter.console:GripTooltipAllowed() then return end
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText(meter.config.name or L["Threat window"])
        GameTooltip:AddLine(L["Drag to move this window and the windows snapped to it."], 1, 0.82, 0.45, true)
        GameTooltip:AddLine(L["Hold Shift to move it alone; it still snaps."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Right-click for the window menu."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    titleBar:SetScript("OnLeave", function(owner)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(owner)) then GameTooltip:Hide() end
    end)
    frame:SetScript("OnSizeChanged", function() meter:Layout() end)
    frame:SetScript("OnShow", function() meter.console:MarkDirty() end)
    meter.frame = frame
    meter.rows = {}
    return frame
end

function Meter.Create(console, config)
    local meter = setmetatable({ console = console, config = config, offset = 0, visibleRows = 1, rowCount = 0 }, Meter)
    CreateFrames(meter)
    meter:ApplyTheme()
    return meter
end

-- Rebinds a pooled window to another saved record (a deleted window's frame is reused): nothing
-- of the old window's runtime state (scroll, a resize in progress) carries over.
function Meter:Bind(config)
    local console = self.console
    if console.sizing == self then console:AbortSizing(self) end
    self.config = config
    self.offset, self.rowCount = 0, 0
    self:ApplyTheme()
end

-- The new-window button at the window limit: disabled art, and a click does nothing.
function Meter:SetNewWindowAvailable(available)
    local button = self.buttons["new-window"]
    button.unavailable = not available
    if button.SetEnabled then button:SetEnabled(available) end
    SetButtonArt(button, "normal")
end

function Meter:Place()
    local frame, config = self.frame, self.config
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", config.left, config.top)
    frame:SetSize(config.width, config.height)
end

function Meter:SetGripArt(state)
    local theme = self.theme
    if theme.gripAtlas then
        local atlas = state == "normal" and theme.gripAtlas or (theme.gripAtlas .. "-" .. state)
        -- SetAtlas sets the atlas's own coordinates; a SetTexCoord here would undo its crop.
        if Themes.SetAtlas(self.grip.texture, atlas) then return end
    end
    local file = string.format("%s-resize-grip-%s", theme.buttons or "glass", state or "normal")
    if Themes.SetKit(self.grip.texture, file) then self.grip.texture:SetTexCoord(Themes.TexCoord(file)) end
end

local function HideAll(textures)
    for _, texture in ipairs(textures) do texture:Hide() end
end

function Meter:ApplyTheme()
    local theme = Themes.Get(self.config.theme)
    self.theme = theme
    local frame = self.frame
    if theme.kind == "backdrop" then
        frame:SetBackdrop({ bgFile = theme.bgFile or Themes.FLAT, edgeFile = theme.edgeFile or Themes.FLAT,
            edgeSize = theme.edgeSize or 1,
            insets = { left = theme.inset or 1, right = theme.inset or 1, top = theme.inset or 1, bottom = theme.inset or 1 } })
        frame:SetBackdropBorderColor(theme.edge[1], theme.edge[2], theme.edge[3], theme.edge[4] or 1)
    else
        frame:SetBackdrop(nil)
    end
    SetFont(self.titleBar.text, theme.titleFont, "GameFontNormal")
    self.titleBar.text:SetTextColor(theme.titleText[1], theme.titleText[2], theme.titleText[3])
    for _, label in pairs(self.header.labels) do
        label:SetTextColor(theme.headerText[1], theme.headerText[2], theme.headerText[3])
    end
    for _, row in ipairs(self.rows) do self:SkinRow(row) end
    for _, button in pairs(self.buttons) do SetButtonArt(button, "normal") end
    self:SetGripArt("normal")
    self:Layout()
end

function Meter:SkinRow(row)
    local theme = self.theme
    Themes.ApplyBar(row, theme)
    if theme.barBackgroundAtlas and Themes.SetAtlas(row.backdrop, theme.barBackgroundAtlas) then
        row.backdrop:SetVertexColor(1, 1, 1, 1)
    elseif Themes.SetKit(row.backdrop, "bar-backdrop", true, false) then
        row.backdrop:SetVertexColor(0.12, 0.12, 0.13, 0.8)
    end
    Themes.SetKit(row.stripe, "row-stripe", true, false)
    row.stripe:SetVertexColor(1, 1, 1, 0.5)
    Themes.SetKit(row.highlight, "row-highlight", true, false)
    for _, key in ipairs(ROW_TEXTS) do
        SetFont(row[key], theme.rowFont, "GameFontHighlightSmall")
    end
end

-- The title's buttons that fit, right to left in priority order.
function Meter:LayoutButtons(width, height)
    local config = self.config
    local fits = math.max(0, math.min(#BUTTONS, math.floor((width - 70) / (BUTTON_SIZE + 2))))
    local x = width - 4
    local leftmost
    for index, kind in ipairs(BUTTONS) do
        local button = self.buttons[kind]
        if kind == "lock" then button.art = config.locked and "lock" or "unlock" end
        if index <= fits then
            x = x - BUTTON_SIZE
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self.titleBar, "TOPLEFT", x, -math.floor((height - BUTTON_SIZE) / 2))
            SetButtonArt(button, "normal")
            button:Show()
            leftmost = x
            x = x - 2
        else
            button:Hide()
        end
    end
    return leftmost or width
end

function Meter:LayoutChrome(width, height)
    local theme, frame = self.theme, self.frame
    local alpha = (theme.fillAlpha or 1) * (self.config.alpha or 1)
    local edges = frame.edges
    frame.fill:Hide()
    frame.meterBackground:Hide()
    HideAll(edges)
    if theme.kind == "art" then
        local prefix = theme.prefix .. "-frame-"
        local _, _, corner = Themes.Size(prefix .. "corner-tl")
        local border = theme.border
        if Themes.Fill(frame.fill, prefix .. "fill", frame, border, border, width - border * 2, height - border * 2) then
            frame.fill:SetAlpha(alpha)
            frame.fill:Show()
        end
        Themes.Place(edges[1], prefix .. "corner-tl", frame, 0, 0)
        Themes.Place(edges[2], prefix .. "corner-tr", frame, width - corner, 0)
        Themes.Place(edges[3], prefix .. "corner-bl", frame, 0, height - corner)
        Themes.Place(edges[4], prefix .. "corner-br", frame, width - corner, height - corner)
        Themes.Repeat(edges[5], prefix .. "edge-top", frame, corner, 0, width - corner * 2, "x")
        Themes.Repeat(edges[6], prefix .. "edge-bottom", frame, corner, height - border, width - corner * 2, "x")
        Themes.Repeat(edges[7], prefix .. "edge-left", frame, 0, corner, height - corner * 2, "y")
        Themes.Repeat(edges[8], prefix .. "edge-right", frame, width - border, corner, height - corner * 2, "y")
        for _, texture in ipairs(edges) do texture:SetShown(texture.threatKitLoaded == true) end
    elseif theme.kind == "backdrop" then
        frame:SetBackdropColor(theme.fill[1], theme.fill[2], theme.fill[3], alpha)
    elseif theme.kind == "meter" then
        local background = frame.meterBackground
        background:ClearAllPoints()
        background:SetAllPoints(frame)
        if Themes.SetAtlas(background, theme.backgroundAtlas) then
            if background.SetTextureSliceMargins then
                pcall(background.SetTextureSliceMargins, background, 20, 80, 20, 20)
            end
        else
            background:SetColorTexture(0, 0, 0, 1)
        end
        background:SetAlpha(alpha)
        background:Show()
    end
end

function Meter:LayoutTitle(inset, width)
    local theme, bar = self.theme, self.titleBar
    local height = theme.title
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", theme.kind == "meter" and 0 or inset, theme.kind == "meter" and 0 or -inset)
    bar:SetSize(width, height)
    bar.fill:Hide()
    HideAll(bar.pieces)
    local x = 4
    if theme.kind == "art" then
        local prefix = theme.prefix .. "-title-"
        Themes.Place(bar.left, prefix .. "left", bar, 0, 0)
        Themes.Repeat(bar.mid, prefix .. "mid", bar, 6, 0, width - 12, "x")
        Themes.Place(bar.right, prefix .. "right", bar, width - 6, 0)
        bar.left:Show() bar.mid:Show() bar.right:Show()
        if width >= 160 and Themes.Place(bar.emblem, prefix .. "emblem", bar, 2, math.floor((height - 20) / 2)) then
            bar.emblem:Show()
            x = 24
        end
        if Themes.Place(bar.badge, theme.prefix .. "-badge", bar, x, math.floor((height - 14) / 2)) then bar.badge:Show() end
    elseif theme.kind == "meter" then
        bar.fill:ClearAllPoints()
        bar.fill:SetAllPoints(bar)
        if Themes.SetAtlas(bar.fill, theme.headerAtlas) then
            if bar.fill.SetTextureSliceMargins then pcall(bar.fill.SetTextureSliceMargins, bar.fill, 80, 14, 80, 22) end
        else
            bar.fill:SetColorTexture(0.1, 0.08, 0.05, 0.9)
        end
        bar.fill:Show()
        x = 8
        if Themes.Place(bar.badge, "glass-badge", bar, x, math.floor((height - 14) / 2)) then bar.badge:Show() end
    else
        local colour = theme.titleFill or { 0, 0, 0, 0.5 }
        bar.fill:ClearAllPoints()
        bar.fill:SetAllPoints(bar)
        bar.fill:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1)
        bar.fill:Show()
        if Themes.Place(bar.badge, "glass-badge", bar, x, math.floor((height - 14) / 2)) then bar.badge:Show() end
    end
    bar.digit:ClearAllPoints()
    bar.digit:SetPoint("CENTER", bar, "TOPLEFT", x + 7, -math.floor(height / 2))
    bar.digit:SetText(tostring(self.config.id))
    local digit = theme.digitText or { 1, 1, 1 }
    bar.digit:SetTextColor(digit[1], digit[2], digit[3])
    bar.summary:SetTextColor(theme.titleText[1], theme.titleText[2], theme.titleText[3])
    local leftmost = self:LayoutButtons(width, height)
    -- The name keeps its room; the summary (the measured enemy, or engaged and loose counts)
    -- takes what is left beside it and is dropped when that is too little to read.
    local room = leftmost - x - 22
    local summaryWidth = math.floor((room - TITLE_NAME_WIDTH) * 0.9)
    local showSummary = summaryWidth >= SUMMARY_MIN_WIDTH
    bar.text:ClearAllPoints()
    bar.text:SetPoint("LEFT", bar, "LEFT", x + 18, 0)
    bar.text:SetWidth(math.max(20, showSummary and room - summaryWidth - 4 or room))
    bar.summary:ClearAllPoints()
    bar.summary:SetPoint("RIGHT", bar, "LEFT", leftmost - 4, 0)
    bar.summary:SetWidth(showSummary and summaryWidth or 0)
    bar.summary:SetShown(showSummary)
    return height
end

function Meter:LayoutHeader(x, y, width, shown)
    local theme, header = self.theme, self.header
    header:SetShown(shown)
    if not shown then return 0 end
    local height = theme.header
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
    header:SetSize(width, height)
    HideAll(header.pieces)
    if theme.kind == "art" then
        local prefix = theme.prefix .. "-header-"
        Themes.Place(header.left, prefix .. "left", header, 0, 0)
        Themes.Repeat(header.mid, prefix .. "mid", header, 6, 0, width - 12, "x")
        Themes.Place(header.right, prefix .. "right", header, width - 6, 0)
        header.left:Show() header.mid:Show() header.right:Show()
    end
    return height
end

local HEADER_NAMES = {
    threat = { name = L["NAME"], gap = L["GAP"], percent = L["THREAT"] },
    tank = { name = L["ENEMY"], state = L["STATE"], on = L["ON"], attackers = L["ACTIVE"], you = L["YOU"] },
}

function Meter:LayoutHeaderLabels(layout)
    local labels = self.header.labels
    local names = HEADER_NAMES[self.config.mode] or HEADER_NAMES.tank
    for key, label in pairs(labels) do
        local column = layout[key]
        if column then
            label:ClearAllPoints()
            label:SetPoint("LEFT", self.header, "LEFT", column.x + 2, 0)
            label:SetWidth(column.width)
            label:SetJustifyH(column.justify)
            label:SetText(names[key])
            label:Show()
        else
            label:Hide()
        end
    end
end

-- Rows are placed from the frame's current size; called on resize, theme or option changes.
function Meter:Layout()
    local frame, theme, config = self.frame, self.theme, self.config
    if not theme then return end
    local width = type(frame.GetWidth) == "function" and frame:GetWidth() or config.width
    local height = type(frame.GetHeight) == "function" and frame:GetHeight() or config.height
    if type(width) ~= "number" or width <= 0 then width = config.width end
    if type(height) ~= "number" or height <= 0 then height = config.height end
    self:LayoutChrome(width, height)
    local inset = Themes.Inset(theme)
    local innerWidth = width - inset * 2
    local y = inset + self:LayoutTitle(inset, theme.kind == "meter" and width or innerWidth)
    if theme.kind == "meter" then y = theme.title end
    local rowHeight = config.rowHeight or theme.rowHeight
    local spacing = theme.spacing or 0
    local roomBelow = height - y - inset
    local showHeader = roomBelow - theme.header >= (rowHeight + spacing) * 2
    y = y + self:LayoutHeader(inset, y, innerWidth, showHeader)
    local bodyHeight = math.max(rowHeight, height - y - inset - 1)
    self.visibleRows = math.min(MAX_ROWS, Geometry.VisibleRows(bodyHeight, rowHeight, spacing))
    local body = self.body
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + 1, -(y + 1))
    body:SetSize(innerWidth - 2, bodyHeight)
    self.bodyHeight = bodyHeight
    self.rowWidth = innerWidth - 2 - SCROLL_WIDTH - 3
    self.rowHeight, self.spacing = rowHeight, spacing
    local iconSize = math.max(8, math.min(16, rowHeight - 2))
    self.iconSize = iconSize
    self.columns = ColumnLayout(config.mode, self.rowWidth, iconSize, self.columns)
    self:LayoutHeaderLabels(self.columns)
    for index = 1, self.visibleRows do
        local row = self.rows[index]
        if not row then
            row = CreateRow(self)
            self.rows[index] = row
            self:SkinRow(row)
        end
        self:LayoutRow(row, index)
    end
    for index = self.visibleRows + 1, #self.rows do self.rows[index]:Hide() end
    body.empty:ClearAllPoints()
    body.empty:SetPoint("CENTER", body, "CENTER", 0, 0)
    body.empty:SetWidth(math.max(20, innerWidth - 8))
    body.more:ClearAllPoints()
    body.more:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(inset + SCROLL_WIDTH + 8), inset + 1)
    self.grip:SetShown(not config.locked)
    self.console:MarkDirty()
end

function Meter:LayoutRow(row, index)
    local height, width, iconSize = self.rowHeight, self.rowWidth, self.iconSize
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -((index - 1) * (height + self.spacing)))
    row:SetSize(width, height)
    row.stripe:ClearAllPoints()
    row.stripe:SetAllPoints()
    row.stripe:SetShown(index % 2 == 0)
    row.highlight:ClearAllPoints()
    row.highlight:SetAllPoints()
    Themes.Place(row.selectedLeft, "row-selected-left", row, 0, 0, 4, height)
    Themes.Repeat(row.selectedMid, "row-selected", row, 4, 0, math.max(1, width - 8), "x", height)
    Themes.Place(row.selectedRight, "row-selected-right", row, width - 4, 0, 4, height)
    local iconY = math.floor((height - iconSize) / 2)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -iconY)
    row.icon:SetSize(iconSize, iconSize)
    row.marker:ClearAllPoints()
    row.marker:SetPoint("TOPLEFT", row, "TOPLEFT", 4 + iconSize, -iconY)
    row.marker:SetSize(iconSize, iconSize)
    for _, key in ipairs(ROW_COLUMNS) do
        local column = self.columns[key]
        row[key]:ClearAllPoints()
        if column then
            row[key]:SetPoint("LEFT", row, "LEFT", column.x, 0)
            row[key]:SetWidth(column.width)
            row[key]:SetJustifyH(column.justify)
            row[key]:Show()
        else
            row[key]:Hide()
        end
    end
    local value = self.columns.you or self.columns.percent
    row.value:ClearAllPoints()
    row.value:SetPoint("LEFT", row, "LEFT", value.x, 0)
    row.value:SetWidth(value.width)
    row.value:SetJustifyH("RIGHT")
end

function Meter:Scroll(delta)
    local offset = Geometry.ClampOffset(self.offset + (delta or 0), self.rowCount, self.visibleRows)
    if offset ~= self.offset then
        self.offset = offset
        self.console:MarkDirty()
    end
end

local function SetSelected(row, selected)
    row.selectedLeft:SetShown(selected)
    row.selectedMid:SetShown(selected)
    row.selectedRight:SetShown(selected)
end

local function ClearRow(row)
    row.kind, row.unit, row.guid, row.enemyName, row.serial, row.root, row.entry = nil, nil, nil, nil, nil, nil, nil
end

-- A tank-mode row for one enemy record from the threat service's snapshot.
function Meter:FillEnemy(row, entry)
    local theme = self.theme
    row.kind, row.entry = "enemy", entry
    -- A listed enemy's lead is read on every service refresh, not throttled.
    self.console.watchedRecords[entry] = true
    row.unit, row.guid, row.enemyName = entry.unit, entry.guid, entry.enemyName
    row.serial, row.root = entry.serial, entry.root
    local isTarget = entry.threatMobSource == "target"
    local marker = isTarget and "icon-target" or (Secret.SameUnit(entry.unit, "focus") and "icon-focus" or nil)
    Themes.Icon(row.marker, marker, theme)
    SetSelected(row, isTarget)
    local state = entry.holdState or (not entry.engaged and "IDLE") or (entry.loose and "LOOSE") or "TANK"
    Themes.Icon(row.icon, STATE_ICONS[state], theme)
    local colour = StateColour(state)
    row.name:SetText(entry.enemyName or L["Unknown enemy"])
    row.name:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
    row.state:SetText(STATE_LABELS[state] or "")
    row.state:SetTextColor(colour[1], colour[2], colour[3])
    row.on:SetText(entry.engaged and entry.targetName or "")
    row.on:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
    row.attackers:SetText(FormatCount(entry.activeAttackerCount, L["%d attacker"], L["%d attackers"]))
    row.attackers:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    row.gap:SetText("")
    if not entry.engaged then
        row.value:SetText("")
    else
        ThreatText.Apply(row.value, entry)
        row.value:SetTextColor(ThreatText.Colour(entry))
    end
    row:SetStatusBarColor(colour[1], colour[2], colour[3], 0.55)
    if not entry.engaged then
        row:SetValue(0)
    elseif type(entry.percent) == "number" then
        row:SetValue(math.max(0, math.min(100, entry.percent)))
    elseif entry.hasOpaquePercent then
        -- A protected percent goes straight into the bar's own sink.
        if not pcall(row.SetValue, row, entry.percentOpaque) then row:SetValue(0) end
    else
        row:SetValue(0)
    end
end

-- A threat-meter row for one group member's threat on the measured enemy.
function Meter:FillMember(row, entry, record, pinned)
    local theme = self.theme
    row.kind, row.entry = "member", entry
    row.unit, row.guid, row.enemyName = record.unit, record.guid, record.enemyName
    row.serial, row.root = record.serial, record.root
    Themes.Icon(row.icon, ROLE_ICONS[entry.role], theme)
    local marker = (entry.tanking == true and "icon-aggro") or (pinned and "icon-pin") or (entry.isPlayer and "icon-you") or nil
    Themes.Icon(row.marker, marker, theme)
    SetSelected(row, entry.isPlayer == true)
    local r, g, b = ClassColour(entry)
    row.name:SetText(entry.name or entry.unit or L["Unknown"])
    row.name:SetTextColor(r, g, b)
    row.state:SetText("")
    row.on:SetText("")
    row.attackers:SetText("")
    local colour = MemberColour(entry, theme)
    row.value:SetTextColor(colour[1], colour[2], colour[3])
    if type(entry.percent) == "number" then
        row.value:SetText(Format.Percent(entry.percent))
        row:SetValue(math.max(0, math.min(100, entry.percent)))
    elseif entry.hasOpaquePercent then
        if not pcall(row.value.SetFormattedText, row.value, "%.0f%%", entry.percentOpaque) then row.value:SetText("--") end
        if not pcall(row.SetValue, row, entry.percentOpaque) then row:SetValue(0) end
    else
        row.value:SetText("--")
        row:SetValue(0)
    end
    row.gap:SetText(type(entry.gap) == "number" and Format.SignedLead(entry.gap) or "")
    row.gap:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    row:SetStatusBarColor(r, g, b, 0.7)
end

-- Scroll piece names per theme, built once rather than on every render.
local scrollNames = {}
local function ScrollNames(theme)
    local names = scrollNames[theme]
    if not names then
        local prefix = theme.kind == "art" and (theme.prefix .. "-scroll-") or "scroll-"
        names = {}
        for _, part in ipairs({ "track", "thumb" }) do
            names[part] = { prefix .. part .. "-top", prefix .. part .. "-mid", prefix .. part .. "-bottom" }
        end
        scrollNames[theme] = names
    end
    return names
end

local function ThreeSlice(body, textures, names, x, y, extent)
    extent = math.max(7, extent)
    Themes.Place(textures[1], names[1], body, x, y)
    Themes.Repeat(textures[2], names[2], body, x, y + 3, extent - 6, "y")
    Themes.Place(textures[3], names[3], body, x, y + extent - 3)
    for index = 1, 3 do textures[index]:SetShown(textures[index].threatKitLoaded == true) end
end

-- The textures are placed only when the thumb, the size or the theme changed.
function Meter:UpdateScrollbar(total)
    local body = self.body
    local start, length = Geometry.Thumb(self.offset, total, self.visibleRows)
    local x = (self.rowWidth or 0) + 3
    local bodyHeight = self.bodyHeight or (self.visibleRows * self.rowHeight)
    if body.scrollStart == start and body.scrollLength == length and body.scrollX == x
        and body.scrollHeight == bodyHeight and body.scrollTheme == self.theme then
        return
    end
    body.scrollStart, body.scrollLength, body.scrollX, body.scrollHeight = start, length, x, bodyHeight
    body.scrollTheme = self.theme
    HideAll(body.track)
    HideAll(body.thumb)
    if not start then return end
    local names = ScrollNames(self.theme)
    ThreeSlice(body, body.track, names.track, x, 0, bodyHeight)
    ThreeSlice(body, body.thumb, names.thumb, x, math.floor(start * bodyHeight), math.floor(length * bodyHeight))
end

-- Draws the rows from the service. Tank mode reads the enemy snapshot; threat meter mode the
-- group's threat on your target, keeping your own row in view (pinned) when it scrolls off.
function Meter:Render(service)
    local config, body = self.config, self.body
    local visible = self.visibleRows
    local count, entries, record, summary
    if config.mode == "threat" then
        record, count, entries = service:GetGroupThreat()
        if not record then count = 0 end
        summary = record and (record.enemyName or "") or ""
    else
        local _, loose, engaged
        entries, count, _, loose, engaged = service:GetSnapshot()
        summary = string.format(L["%d engaged, %d loose"], engaged or 0, loose or 0)
    end
    self.rowCount = count
    self.offset = Geometry.ClampOffset(self.offset, count, visible)
    local pinnedIndex
    if record then
        for index = 1, count do
            if entries[index].isPlayer then pinnedIndex = index break end
        end
        if pinnedIndex and pinnedIndex > self.offset and pinnedIndex <= self.offset + visible then pinnedIndex = nil end
    end
    for index = 1, visible do
        local row = self.rows[index]
        local entryIndex = self.offset + index
        if pinnedIndex and index == visible then entryIndex = pinnedIndex end
        local entry = entryIndex <= count and entries[entryIndex] or nil
        if entry then
            if record then
                self:FillMember(row, entry, record, entryIndex == pinnedIndex)
            else
                self:FillEnemy(row, entry)
            end
            row:Show()
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then self.console:ShowRowTooltip(row) end
        else
            self.console:HideRowTooltip(row)
            ClearRow(row)
            row:Hide()
        end
    end
    -- Rows below the view. The pinned row takes the last slot; pinned from above the view, it
    -- pushes one more row out below.
    local hidden = count - self.offset - visible
    if pinnedIndex and pinnedIndex <= self.offset then hidden = hidden + 1 end
    body.more:SetText(hidden > 0 and string.format(L["+%d more"], hidden) or "")
    if count == 0 then
        body.empty:SetText(config.mode == "threat" and L["Target an enemy to measure threat."] or L["No enemies in view."])
        body.empty:Show()
    else
        body.empty:Hide()
    end
    self.titleBar.text:SetText(config.name or "")
    self.titleBar.summary:SetText(summary)
    self:UpdateScrollbar(count)
end

Meter._Test = {
    ColumnLayout = ColumnLayout, FormatCount = FormatCount, StateColour = StateColour, StateLabels = STATE_LABELS,
}
