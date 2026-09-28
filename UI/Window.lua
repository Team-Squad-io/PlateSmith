local _, PS = ...

-- Shared construction for PlateSmith's standalone windows (the Blueprint window,
-- Studio's dialogs, diagnostics, the threat windows), so backdrop, dragging, layering, Escape
-- handling, and resizing behave the same everywhere.
PS.UI = PS.UI or {}
local Window = {}
PS.UI.Window = Window

local FLAT = "Interface\\Buttons\\WHITE8X8"

Window.colours = {
    background = { 0.025, 0.03, 0.035, 0.97 },
    accent = { 0.25, 0.72, 0.9, 0.9 },
    studio = { 0.58, 0.42, 0.19, 0.95 },
}

-- Escape hides the named frame; Blizzard's UISpecialFrames needs a global name.
function Window.CloseOnEscape(name)
    if type(UISpecialFrames) ~= "table" then return end
    for _, existing in ipairs(UISpecialFrames) do
        if existing == name then return end
    end
    table.insert(UISpecialFrames, name)
end

-- spec: width, height, title, titleFont, strata, border, background,
-- movable (default true), closeButton (default true), closeOnEscape (default true),
-- resizable = { minWidth, minHeight, maxWidth, maxHeight }, onSizeChanged
function Window.Create(name, spec)
    spec = spec or {}
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(spec.width or 640, spec.height or 420)
    frame:SetPoint("CENTER")
    -- Above Blueprint Studio's raised panels, which share the DIALOG strata.
    frame:SetFrameStrata(spec.strata or "FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    local background, border = spec.background or Window.colours.background, spec.border or Window.colours.accent
    frame:SetBackdropColor(background[1], background[2], background[3], background[4])
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])

    if spec.movable ~= false then
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
        frame:SetScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
    end

    if spec.title then
        frame.title = frame:CreateFontString(nil, "OVERLAY", spec.titleFont or "GameFontNormal")
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -15)
        frame.title:SetText(spec.title)
    end

    if spec.closeButton ~= false then
        frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
        frame.closeButton:SetScript("OnClick", function() frame:Hide() end)
    end

    if spec.closeOnEscape ~= false and name then Window.CloseOnEscape(name) end

    local bounds = spec.resizable
    if bounds then
        frame:SetResizable(true)
        if frame.SetResizeBounds then frame:SetResizeBounds(bounds[1], bounds[2], bounds[3], bounds[4]) end
        local grip = CreateFrame("Button", nil, frame)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        if grip.SetNormalTexture then grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end
        grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    end
    if spec.onSizeChanged then frame:SetScript("OnSizeChanged", spec.onSizeChanged) end

    frame:Hide()
    return frame
end

-- The scroll bar of ScrollEditBox and ScrollText: arrows at the ends of a track, and a thumb
-- sized to the visible share that follows the scroll offset (wheel, keys, cursor, drag, code).
-- It sits inside the scroll frame's right edge and hides when the content fits; the content
-- then takes its width. Our own bar, not Blizzard's scroll templates, which taint and did not
-- follow a content height set from Lua.
local BAR = { width = 16, gap = 4, arrow = 16, minThumb = 20, step = 36, padding = 8 }
Window.scrollBar = BAR
local ARROW_ART = "Interface\\Buttons\\UI-ScrollBar-Scroll%sButton-%s"

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end

-- A font string's wrapped height at width. Where no height is reported, lines are counted,
-- wrapping at about half the font size per character.
local function MeasureText(fontString, width, text)
    fontString:SetWidth(width)
    if text ~= nil then fontString:SetText(text) end
    local height = fontString.GetStringHeight and fontString:GetStringHeight()
    if type(height) == "number" and height > 0 then return height end
    local size = fontString.GetFont and select(2, fontString:GetFont())
    size = tonumber(size) or 12
    local lines = 0
    for line in (tostring(fontString:GetText() or "") .. "\n"):gmatch("([^\n]*)\n") do
        lines = lines + math.max(1, math.ceil(#line * size * 0.5 / math.max(1, width)))
    end
    return lines * (size + 2)
end

-- Sizes the scroll child to its content (plus a small bottom padding, never a minimum), with
-- the bar's width reserved only when the content is taller than the view, then syncs the bar.
function Window.RefreshScroll(scroll)
    local bar, child = scroll.scrollBar, scroll:GetScrollChild()
    if not bar or not child or not scroll.measure then return end
    bar.refreshing = true
    local full, view = scroll:GetWidth() or 0, scroll:GetHeight() or 0
    if full > 0 then
        local function Fit(width)
            child:SetWidth(width)
            return math.floor(scroll.measure(width) + BAR.padding + 0.5)
        end
        local height = Fit(full)
        bar.reserved = height - view > 1
        if bar.reserved then height = Fit(math.max(1, full - BAR.width - BAR.gap)) end
        child:SetHeight(height)
    end
    bar.refreshing = false
    bar:Sync()
end

local function ArrowButton(bar, direction)
    local button = CreateFrame("Button", nil, bar)
    button:SetSize(BAR.width, BAR.arrow)
    button:SetPoint(direction, bar, direction, 0, 0)
    local name = direction == "TOP" and "Up" or "Down"
    button.art = button:CreateTexture(nil, "ARTWORK")
    button.art:SetAllPoints(button)
    button.art:SetTexCoord(0.2, 0.8, 0.25, 0.75)
    function button:Paint(state) self.art:SetTexture(string.format(ARROW_ART, name, state)) end
    button:Paint("Up")
    if button.SetHighlightTexture then button:SetHighlightTexture(string.format(ARROW_ART, name, "Highlight")) end
    button:SetScript("OnMouseDown", function(instance) if instance:IsEnabled() then instance:Paint("Down") end end)
    button:SetScript("OnMouseUp", function(instance) if instance:IsEnabled() then instance:Paint("Up") end end)
    button:SetScript("OnEnable", function(instance) instance:Paint("Up") end)
    button:SetScript("OnDisable", function(instance) instance:Paint("Disabled") end)
    return button
end

function Window.ScrollBar(scroll)
    local bar = CreateFrame("Frame", nil, scroll)
    bar:SetWidth(BAR.width)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    bar:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5)
    bar.range, bar.view, bar.content = 0, 0, 0
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetColorTexture(0, 0, 0, 0.45)
    bar.up, bar.down = ArrowButton(bar, "TOP"), ArrowButton(bar, "BOTTOM")
    bar.track:SetPoint("TOPLEFT", bar.up, "BOTTOMLEFT", 0, 0)
    bar.track:SetPoint("BOTTOMRIGHT", bar.down, "TOPRIGHT", 0, 0)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(BAR.width - 4)
    thumb.art = thumb:CreateTexture(nil, "ARTWORK")
    thumb.art:SetAllPoints(thumb)
    thumb.art:SetColorTexture(0.5, 0.56, 0.62, 0.9)
    bar.thumb = thumb

    -- The track between the arrows (from the scroll frame's height: the bar is as tall).
    function bar:TrackHeight() return math.max(0, (scroll:GetHeight() or 0) - 2 * BAR.arrow) end

    function bar:SetOffset(offset)
        scroll:SetVerticalScroll(Clamp(offset, 0, self.range))
        self:Place()
    end

    function bar:Place()
        local track, range = self:TrackHeight(), self.range
        local thumbHeight = math.min(track, math.max(BAR.minThumb, track * self.view / math.max(1, self.content)))
        local offset = Clamp(scroll:GetVerticalScroll() or 0, 0, range)
        local y = range > 0 and (track - thumbHeight) * offset / range or 0
        self.thumbHeight, self.thumbTop = thumbHeight, y
        thumb:SetHeight(thumbHeight)
        thumb:SetPoint("TOP", self, "TOP", 0, -(BAR.arrow + y))
        self.up:SetEnabled(offset > 0)
        self.down:SetEnabled(offset < range)
    end

    -- From the heights RefreshScroll set, so a range the client has not recomputed yet is never
    -- used; an offset past the end moves back to it, so there is no empty scroll past the text.
    function bar:Sync()
        local child = scroll:GetScrollChild()
        local view = scroll:GetHeight() or 0
        local content = child and child:GetHeight() or 0
        local range = content - view
        if range <= 1 then range = 0 end
        self.range, self.view, self.content = range, view, content
        if (scroll:GetVerticalScroll() or 0) > range then scroll:SetVerticalScroll(range) end
        local shown = range > 0
        self:SetShown(shown)
        -- The client resized the content itself (a typed line): lay out again with or without the bar.
        if shown ~= (self.reserved == true) and not self.refreshing and scroll:GetWidth() > 0 then
            return Window.RefreshScroll(scroll)
        end
        self:Place()
    end

    local function Step(direction) bar:SetOffset((scroll:GetVerticalScroll() or 0) + direction * BAR.step) end
    bar.up:SetScript("OnClick", function() Step(-1) end)
    bar.down:SetScript("OnClick", function() Step(1) end)
    local function Wheel(_, delta) Step(-delta) end
    for _, frame in ipairs({ scroll, bar }) do
        if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
        frame:SetScript("OnMouseWheel", Wheel)
    end

    -- A click on the track pages towards it.
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(instance)
        if type(GetCursorPosition) ~= "function" or not thumb.GetTop or not thumb:GetTop() then return end
        local _, y = GetCursorPosition()
        y = y / (instance:GetEffectiveScale() or 1)
        local page = math.max(BAR.step, instance.view - BAR.step)
        instance:SetOffset((scroll:GetVerticalScroll() or 0) + (y > thumb:GetTop() and -page or page))
    end)

    -- Dragging the thumb: a transient OnUpdate while the button is held, cleared on release.
    local function StopDrag(instance) instance:SetScript("OnUpdate", nil) end
    thumb:SetScript("OnMouseDown", function(instance)
        if type(GetCursorPosition) ~= "function" then return end
        local scale = instance:GetEffectiveScale() or 1
        local startY = select(2, GetCursorPosition()) / scale
        local startOffset = scroll:GetVerticalScroll() or 0
        instance:SetScript("OnUpdate", function()
            local travel = bar:TrackHeight() - (bar.thumbHeight or 0)
            if travel <= 0 then return end
            local moved = startY - select(2, GetCursorPosition()) / scale
            bar:SetOffset(startOffset + moved * bar.range / travel)
        end)
    end)
    thumb:SetScript("OnMouseUp", StopDrag)
    thumb:SetScript("OnHide", StopDrag)

    scroll:SetScript("OnScrollRangeChanged", function() bar:Sync() end)
    scroll:SetScript("OnVerticalScroll", function() bar:Place() end)
    scroll:SetScript("OnSizeChanged", function() Window.RefreshScroll(scroll) end)
    scroll.scrollBar = bar
    bar:Hide()
    return bar
end

-- A scrolling, selectable text box with PlateSmith's scroll bar. The caller anchors the returned
-- scroll frame and sets text through SetScrollText. spec.plain leaves out the bar and the
-- sizing (the caller brings its own, as Studio's Blueprint window does).
function Window.ScrollEditBox(parent, spec)
    spec = spec or {}
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(spec.font or "GameFontHighlightSmall")
    if editBox.SetMaxLetters then editBox:SetMaxLetters(spec.maxLetters or 0) end
    editBox:SetScript("OnEscapePressed", function() parent:Hide() end)
    scroll:SetScrollChild(editBox)
    if spec.plain then return scroll, editBox end

    -- An edit box reports no text height, so a hidden font string of the same font measures it.
    local measure = scroll:CreateFontString(nil, "BACKGROUND")
    measure:SetFontObject(spec.font or "GameFontHighlightSmall")
    measure:SetJustifyH("LEFT")
    if measure.SetNonSpaceWrap then measure:SetNonSpaceWrap(true) end
    measure:Hide()
    scroll.textMeasure = measure
    scroll.measure = function(width) return MeasureText(measure, width, editBox:GetText() or "") end
    local bar = Window.ScrollBar(scroll)
    editBox:SetScript("OnTextChanged", function() Window.RefreshScroll(scroll) end)
    -- The cursor (typing, arrow keys, a selection being dragged) stays in view.
    editBox:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        local offset, view = scroll:GetVerticalScroll() or 0, scroll:GetHeight() or 0
        local top, line = -(tonumber(y) or 0), tonumber(lineHeight) or 14
        if top < offset then
            bar:SetOffset(top)
        elseif top + line > offset + view then
            bar:SetOffset(top + line - view)
        end
    end)
    -- The box is only as tall as its lines, so a click below them still focuses it.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    return scroll, editBox
end

-- A scrolling, read-only text area with PlateSmith's scroll bar; child.text is the FontString.
-- A child holding other content sets scroll.measure(width) to return its height.
function Window.ScrollText(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    text:SetJustifyH("LEFT")
    if text.SetJustifyV then text:SetJustifyV("TOP") end
    child.text = text
    scroll:SetScrollChild(child)
    scroll.measure = function(width) return MeasureText(text, width) end
    scroll.textTarget = text
    Window.ScrollBar(scroll)
    return scroll, child
end

-- Replaces the text of a ScrollEditBox or ScrollText, back at the top, and resizes the content
-- to it: its height is the text's plus a small padding, so the scroll ends at the last line.
function Window.SetScrollText(scroll, text)
    local target = scroll.textTarget or scroll:GetScrollChild()
    target:SetText(tostring(text or ""))
    if target.SetCursorPosition then target:SetCursorPosition(0) end
    scroll:SetVerticalScroll(0)
    Window.RefreshScroll(scroll)
end

function Window.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, height or 24)
    button:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end
