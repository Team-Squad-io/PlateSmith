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

-- Blizzard's Settings panel runs CloseAllWindows on its transitions (closing back to the game menu, for one),
-- which hides every UISpecialFrames window: closing the panel closed Studio with it. The panel (HIGH strata)
-- also sits under every PlateSmith window. So while it shows, PlateSmith's Escape windows leave that list
-- (back a frame after it hides, past its close's own CloseAllWindows), and outside combat each shown one
-- keeps Escape from the rest of the UI and closes itself: Escape closes the top window first, as it looks.
-- In combat the key cannot be kept, so Escape closes the panel and the windows stay.
local escape = { names = {}, frames = {}, catchers = {}, afterClose = {}, held = false }
Window._escape = escape

local function SettingsPanelShown()
    local panel = SettingsPanel
    return type(panel) == "table" and panel.IsShown ~= nil and panel:IsShown() == true
end

local function InCombat() return PS.Secret ~= nil and PS.Secret.InCombat() == true end

-- A window off the list keeps its slot under a name no global has (Blizzard's CloseSpecialWindows skips it), so the
-- other addons' slots never move: shifting them from the panel's OnShow hook would taint each one.
local HELD = "PlateSmith escape held: "

local function SetListed(name, listed)
    if type(UISpecialFrames) ~= "table" then return end
    local held = HELD .. name
    for index, existing in ipairs(UISpecialFrames) do
        if existing == name then
            if not listed then UISpecialFrames[index] = held end
            return
        elseif existing == held then
            if listed then UISpecialFrames[index] = name end
            return
        end
    end
    if listed then table.insert(UISpecialFrames, name) end
end

-- From a frame's OnKeyDown: whether the key stops there (keep) or passes on to the rest of the UI; returns keep. Never
-- in combat, where the client blocks the change (ADDON_ACTION_BLOCKED): a frame takes the keyboard only out of combat
-- and passing keys on (Window.TakeKeyboard), so in combat every key passes on and nothing is kept.
function Window.KeepKey(frame, keep)
    if InCombat() then return false end
    if frame.SetPropagateKeyboardInput then pcall(frame.SetPropagateKeyboardInput, frame, not keep) end
    return keep == true
end

-- Out of combat: frame takes the keyboard (on), passing every key on until its OnKeyDown keeps one (KeepKey), or
-- lets it go. Returns whether it changed.
function Window.TakeKeyboard(frame, on)
    if not frame or InCombat() then return false end
    if on and frame.SetPropagateKeyboardInput then pcall(frame.SetPropagateKeyboardInput, frame, true) end
    if frame.EnableKeyboard then pcall(frame.EnableKeyboard, frame, on and true or false) end
    return true
end

-- On, a catcher takes the keyboard passing every key on until its handler keeps one: it never starts out
-- keeping keys, which it could not undo in combat (where that setting cannot change).
local function SetCatching(catcher, on)
    if not catcher then return end
    if on and catcher.SetPropagateKeyboardInput then pcall(catcher.SetPropagateKeyboardInput, catcher, true) end
    if catcher.EnableKeyboard then pcall(catcher.EnableKeyboard, catcher, on) end
end

-- A keyboard-only child over the window (no mouse), made the first time the panel shows with it. It lets
-- go of the keyboard when it keeps an Escape and takes it again when its window next shows.
local function Catcher(name)
    if escape.catchers[name] then return escape.catchers[name] end
    local frame = escape.frames[name] or _G[name]
    if type(frame) ~= "table" or not frame.Hide then return nil end
    local catcher = CreateFrame("Frame", nil, frame)
    catcher:SetAllPoints(frame)
    catcher:SetScript("OnKeyDown", function(owner, key)
        if not Window.KeepKey(owner, key == "ESCAPE") then return end
        if owner.EnableKeyboard then pcall(owner.EnableKeyboard, owner, false) end
        frame:Hide()
    end)
    catcher:SetScript("OnShow", function(owner) SetCatching(owner, escape.held and not InCombat()) end)
    escape.catchers[name] = catcher
    return catcher
end

local function Hold()
    escape.held = true
    local catching = not InCombat()
    for _, name in ipairs(escape.names) do
        SetListed(name, false)
        SetCatching(Catcher(name), catching)
    end
end

local function Relist()
    if escape.held or SettingsPanelShown() then return end
    for _, name in ipairs(escape.names) do SetListed(name, true) end
    local after = escape.afterClose
    escape.afterClose = {}
    for _, callback in ipairs(after) do
        local ok, failure = pcall(callback)
        if not ok and PS.Chat then PS.Chat.ReportError("settings panel closed", failure) end
    end
end

local function Release()
    escape.held = false
    for _, name in ipairs(escape.names) do SetCatching(escape.catchers[name], false) end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, Relist) else Relist() end
end

-- True once the panel's show and hide are followed (false on a client without Blizzard's Settings panel).
local function WatchSettingsPanel()
    if escape.watching then return true end
    local panel = SettingsPanel
    if type(panel) ~= "table" or not panel.HookScript then return false end
    escape.watching = true
    panel:HookScript("OnShow", Hold)
    panel:HookScript("OnHide", Release)
    return true
end
Window.WatchSettingsPanel = WatchSettingsPanel

-- Escape hides the named frame (frame: the window itself, else the global of that name); Blizzard's
-- UISpecialFrames needs a global name.
function Window.CloseOnEscape(name, frame)
    if type(UISpecialFrames) ~= "table" then return end
    local known = false
    for _, existing in ipairs(escape.names) do
        if existing == name then known = true break end
    end
    if not known then escape.names[#escape.names + 1] = name end
    escape.frames[name] = frame or escape.frames[name]
    WatchSettingsPanel()
    if escape.watching and SettingsPanelShown() then Hold() elseif not escape.held then SetListed(name, true) end
end

-- Runs callback once, the frame after Blizzard's Settings panel next closes; false (and nothing kept)
-- when the panel is not showing.
function Window.WhenSettingsPanelCloses(callback)
    if not (WatchSettingsPanel() and SettingsPanelShown()) or type(callback) ~= "function" then return false end
    escape.afterClose[#escape.afterClose + 1] = callback
    return true
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

    if spec.closeOnEscape ~= false and name then Window.CloseOnEscape(name, frame) end

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
    bar.Wheel = Wheel
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
    -- The box covers the view and takes the pointer, so it passes the wheel on itself.
    if editBox.EnableMouseWheel then editBox:EnableMouseWheel(true) end
    editBox:SetScript("OnMouseWheel", bar.Wheel)
    editBox:SetScript("OnTextChanged", function() Window.RefreshScroll(scroll) end)
    -- A cursor that moved (typing, arrow keys, a selection being dragged) is brought into view. One
    -- reported where it already was (the client can report it again as it lays the text out) is left
    -- alone, so the wheel and the bar can move away from it.
    editBox:SetScript("OnCursorChanged", function(box, x, y, _, lineHeight)
        if box.cursorX == x and box.cursorY == y then return end
        box.cursorX, box.cursorY = x, y
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

-- Replaces the text of a ScrollEditBox or ScrollText, back at the top with nothing selected, and resizes
-- the content to it: its height is the text's plus a small padding, so the scroll ends at the last line.
-- Selecting it for copying is the caller's explicit step (a Copy or Select all button).
function Window.SetScrollText(scroll, text)
    local target = scroll.textTarget or scroll:GetScrollChild()
    target:SetText(tostring(text or ""))
    if target.HighlightText then target:HighlightText(0, 0) end
    if target.SetCursorPosition then target:SetCursorPosition(0) end
    scroll:SetVerticalScroll(0)
    Window.RefreshScroll(scroll)
end

-- A tab strip: flat tabs on a hairline, the selected one in gold with an underline and a faint
-- fill, the others dim until hovered. Colours default to Blizzard's panel inks.
Window.colours.tab = {
    selected = { 1, 0.82, 0 }, normal = { 0.62, 0.62, 0.62 }, hover = { 1, 1, 1 },
    fill = { 1, 1, 1, 0.06 }, hoverFill = { 1, 1, 1, 0.03 }, line = { 0.45, 0.45, 0.45, 0.8 }, accent = { 1, 0.82, 0, 1 },
}
local TAB = { height = 26, padding = 14, minWidth = 72, gap = 2, accent = 2 }
Window.tabMetrics = TAB

-- spec: tabs = { { key, text }, ... }, onSelect(key), colours (Window.colours.tab by default),
-- font (default GameFontNormal). The caller anchors the strip (its TOPLEFT and TOPRIGHT) and
-- calls strip:Select(key); strip.buttons[key]:SetText(text) re-measures a tab.
function Window.Tabs(parent, spec)
    local colours = spec.colours or Window.colours.tab
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(TAB.height)
    strip.line = strip:CreateTexture(nil, "BORDER")
    strip.line:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    strip.line:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    strip.line:SetHeight(1)
    strip.line:SetColorTexture(colours.line[1], colours.line[2], colours.line[3], colours.line[4])
    strip.buttons, strip.order = {}, {}

    local function Paint(button)
        local chosen = strip.selected == button.key
        local ink = chosen and colours.selected or button.hover and colours.hover or colours.normal
        button.label:SetTextColor(ink[1], ink[2], ink[3], 1)
        local fill = chosen and colours.fill or button.hover and colours.hoverFill or nil
        if fill then button.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4]) end
        button.fill:SetShown(fill ~= nil)
        button.accent:SetShown(chosen)
    end

    local function Place()
        local x = 0
        for _, button in ipairs(strip.order) do
            button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
            x = x + button:GetWidth() + TAB.gap
        end
    end

    for _, tab in ipairs(spec.tabs) do
        local key = tab[1]
        local button = CreateFrame("Button", nil, strip)
        button.key = key
        button:SetHeight(TAB.height)
        button.fill = button:CreateTexture(nil, "BACKGROUND")
        button.fill:SetAllPoints(button)
        button.accent = button:CreateTexture(nil, "ARTWORK")
        button.accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        button.accent:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        button.accent:SetHeight(TAB.accent)
        button.accent:SetColorTexture(colours.accent[1], colours.accent[2], colours.accent[3], colours.accent[4])
        button.label = button:CreateFontString(nil, "OVERLAY", spec.font or "GameFontNormal")
        button.label:SetPoint("CENTER", button, "CENTER", 0, 1)
        function button:SetText(text)
            self.label:SetText(text)
            local width = self.label.GetStringWidth and self.label:GetStringWidth() or 0
            self:SetWidth(math.max(TAB.minWidth, math.ceil(tonumber(width) or 0) + 2 * TAB.padding))
            Place()
        end
        function button:GetText() return self.label:GetText() end
        button:SetScript("OnEnter", function(instance) instance.hover = true Paint(instance) end)
        button:SetScript("OnLeave", function(instance) instance.hover = false Paint(instance) end)
        button:SetScript("OnClick", function()
            if spec.onSelect then spec.onSelect(key) else strip:Select(key) end
        end)
        strip.buttons[key] = button
        strip.order[#strip.order + 1] = button
        button:SetText(tab[2])
    end

    function strip:Select(key)
        self.selected = key
        for _, button in ipairs(self.order) do Paint(button) end
    end
    return strip
end

function Window.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, height or 24)
    button:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end
