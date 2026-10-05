local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Theme = assert(PS.StudioTheme, "PlateSmith StudioTheme missing")

-- Blueprint Studio's look: the Accepted B kit (Kit.lua, drawn by Theme.lua). Studio is one frame
-- whose rectangle is the kit's canvas (1440 x 900 by default): the painted outer frame with its
-- centred plaque and shaped close corner, a header band (Layout, the Studio / Settings toggle,
-- Profile), a footer band, and between them the panels: in Studio the component tree, the
-- preview and the inspector; in Settings the categories and a category's page.

local SetStudioButtonState
local studioButtons = {}

-- An enabled primary button (Save) pulses while it is on screen: one ticker entry, on only while
-- such a button shows its glow.
local GLOW_TICKER = "studio.primary-glow"
local glowButtons = {}
local function UpdateGlowTicker()
    local pulsing = false
    for _, button in ipairs(glowButtons) do
        if button.studioGlowShown and button:IsVisible() then pulsing = true break end
    end
    PS.Ticker.SetEnabled(GLOW_TICKER, pulsing)
end
PS.Ticker.Register(GLOW_TICKER, 0.03, function(_, now)
    local alpha = 0.18 + 0.32 * (0.5 + 0.5 * math.sin((now or 0) * 3))
    for _, button in ipairs(glowButtons) do
        if button.studioGlowShown then
            for _, texture in ipairs(button.studioGlow.textures) do texture:SetAlpha(alpha) end
        end
    end
end)
PS.Ticker.SetEnabled(GLOW_TICKER, false)

-- The kit's layout, in its own pixels; W and H are Studio's width and height. Panels start 10 px
-- below the header's rail (the kit sets them straight on it) and end 14 px above the footer's.
local FRAME = {
    panelTop = 170, panelBottom = 116, left = 40, right = 38, gap = 8, tree = 298, inspector = 338,
    plaque = { width = 232, top = 1 },
    headerControls = 101, footerButtons = 88,
}
-- The inspector's parchment starts inside its rail; the scroll bar's lane is at its right.
local INSPECTOR = { width = FRAME.inspector, rail = 8, lane = 32 }
-- The footer's CPU readout: right-aligned, its right end this far from Studio's right edge (just
-- left of Revert), refreshed every interval seconds while Studio shows.
local CPU_READOUT = { right = 381, width = 200, height = 22, gap = 16, interval = 3, ticker = "studio.cpu-readout" }
-- Settings' categories panel: the search box across its top, then a row per category.
local CATEGORIES = { top = 12, searchX = 12, searchH = 34, searchGap = 12, rowStep = 46 }
-- The preview panel's rows (canvas units from its top-left): the design row under the tabs, the foot's
-- controls footY above its bottom, Test values after Snap and its panel panelGap above the foot. The picture
-- (world or plain dark) fills the panel under the tabs, from pictureTop, pictureInset inside its other edges.
local PREVIEW = { side = 16, rowTop = 54, rowHeight = 30, footY = 49, snapX = 243, testGap = 16, panelGap = 6,
    pictureTop = 48, pictureInset = 8 }
Options.editorPreviewLayout = PREVIEW

-- Button families: the variant picks the kit's colour (red actions, gold Save, dark utility)
-- and the height its 26, 28 or 32 px set; labels are drawn by the addon.
local BUTTON_FAMILIES = { primary = "button-gold", action = "button-red", tab = "plate-tab", toggle = "toggle" }
local function ButtonHeight(variant, height)
    if variant == "tab" then return 40 end
    if variant == "toggle" then return 32 end
    if height <= 26 then return 26 elseif height <= 29 then return 28 end
    return 32
end
-- Studio's font and text colours: light labels on its dark panels, gold titles.
local FONT = PS.UI.Layout.TOKENS.FONT_PATH
local LABEL, GOLD = { 0.87, 0.85, 0.81 }, { 0.89, 0.75, 0.13 }

SetStudioButtonState = function(button, selected)
    button.studioSelected = selected and true or false
    local enabled = button:IsEnabled()
    local selectable = button.studioVariant == "tab" or button.studioVariant == "toggle"
        or button.studioVariant == "category"
    -- An enabled primary button (Save) rests lit and glows, so it reads as the thing to press.
    local primaryLit = button.studioVariant == "primary" and enabled
    local state = not enabled and "disabled" or button.studioPressed and "pressed"
        or selectable and button.studioSelected and "selected" or button.studioHover and "hover"
        or primaryLit and "selected" or "normal"
    button.studioState = state
    if button.studioArt then button.studioArt:SetState(state) end
    if button.studioRow then
        Theme.Place(button.studioRow, "settings-category-row-" .. state, button, 0, 0, button:GetWidth(), button:GetHeight())
    end
    local lit = enabled and (button.studioHover or button.studioSelected)
    button.label:SetTextColor(lit and 1 or LABEL[1], lit and 0.93 or LABEL[2], lit and 0.80 or LABEL[3])
    if not enabled then button.label:SetTextColor(0.50, 0.48, 0.45) end
    if primaryLit then button.label:SetTextColor(1, 0.87, 0.45) end
    if button.studioGlow then
        local glowing = primaryLit and not button.studioHover and not button.studioPressed
        button.studioGlow:SetShown(glowing)
        if glowing ~= button.studioGlowShown then
            button.studioGlowShown = glowing
            UpdateGlowTicker()
        end
    end
    if button.studioVariant == "tab" and button.studioSelected then button.label:SetTextColor(1, 0.90, 0.72) end
    button.label:ClearAllPoints()
    local justify = button.studioVariant == "category" and "LEFT" or "CENTER"
    button.label:SetPoint(justify, button, justify, justify == "LEFT" and 12 or 0, state == "pressed" and -1 or 0)
end

local function CreateStudioButton(parent, text, width, height, variant)
    local button = CreateFrame("Button", nil, parent)
    local drawn = variant == "category" and height or ButtonHeight(variant, height)
    button:SetSize(width, drawn)
    button.studioVariant = variant
    button.drawsDisabledState = true
    if variant == "category" then
        button.studioRow = button:CreateTexture(nil, "BACKGROUND")
    else
        local family = BUTTON_FAMILIES[variant] or "button-dark"
        button.studioArt = Theme.ThreeSlice(button, family, (family:find("^button%-")) and drawn or nil)
    end
    if variant == "primary" then
        -- A soft pulse of the gold's hover art over it while there is something to save.
        local glow = Theme.ThreeSlice(button, "button-gold", drawn)
        glow.state = "hover"
        for _, texture in ipairs(glow.textures) do
            if texture.SetDrawLayer then texture:SetDrawLayer("ARTWORK", 1) end
            if texture.SetBlendMode then texture:SetBlendMode("ADD") end
        end
        glow:Layout()
        button.studioGlow = glow
        glowButtons[#glowButtons + 1] = button
        button:HookScript("OnShow", UpdateGlowTicker)
        button:HookScript("OnHide", UpdateGlowTicker)
    end
    studioButtons[#studioButtons + 1] = button
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText(text)
    button.studioFontSize = variant == "category" and 17 or drawn >= 32 and 16 or 14
    label:SetFont(FONT, button.studioFontSize)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    button.label = label
    button:SetScript("OnSizeChanged", function(instance)
        if instance.studioArt then instance.studioArt:Layout() end
        if instance.studioGlow then instance.studioGlow:Layout() end
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    button:SetScript("OnEnter", function(instance)
        instance.studioHover = true
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    button:SetScript("OnLeave", function(instance)
        instance.studioHover = false
        instance.studioPressed = false
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    button:SetScript("OnMouseDown", function(instance)
        instance.studioPressed = instance:IsEnabled()
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    button:SetScript("OnMouseUp", function(instance)
        instance.studioPressed = false
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    button:SetScript("OnDisable", function(instance)
        instance.studioPressed, instance.studioHover = false, false
        SetStudioButtonState(instance, instance.studioSelected)
    end)
    button:SetScript("OnEnable", function(instance) SetStudioButtonState(instance, instance.studioSelected) end)
    SetStudioButtonState(button, false)
    return button
end

-- A vertical scroll bar for a plain ScrollFrame, from the kit's pieces: arrow buttons, a track
-- (top, repeating middle, bottom) and a thumb of the same three parts sized to the visible share.
local SCROLL_STEP = 30
local SCROLL = { width = 21, arrow = { 20, 25 }, thumb = 13, cap = 5 }

-- A plain frame, not a client Slider: which way a vertical Slider's value runs differs between client
-- builds, and dragging its thumb ran backwards on one. The bar keeps the offset and reads the drag from
-- the cursor itself, so down is always down.
local function CreateStudioScrollBar(scroll, parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(SCROLL.width)
    bar:EnableMouse(true)
    bar.position, bar.thumbTop = 0, 0
    bar.trackArt = {}
    for index = 1, 3 do bar.trackArt[index] = bar:CreateTexture(nil, "BACKGROUND") end
    bar.track = bar.trackArt[2]
    -- With snapTops (the list's row tops), scrolling stops only on a whole row, never half one.
    local function Snap(offset)
        local tops, range = bar.snapTops, bar.range or 0
        if not tops or #tops == 0 then return offset end
        local best, distance = range, math.abs(range - offset)
        for _, top in ipairs(tops) do
            if top <= range and math.abs(top - offset) < distance then best, distance = top, math.abs(top - offset) end
        end
        return best
    end
    -- Scrolls to offset, clamped and snapped, with the thumb there; onScrolled hears of each new
    -- offset or range.
    local function ScrollTo(offset)
        local range = bar.range or 0
        local position = Snap(math.max(0, math.min(range, offset or 0)))
        bar.position = position
        if (scroll:GetVerticalScroll() or 0) ~= position then scroll:SetVerticalScroll(position) end
        bar:PlaceThumbArt(position)
        if bar.onScrolled and (bar.heardPosition ~= position or bar.heardRange ~= range) then
            bar.heardPosition, bar.heardRange = position, range
            bar.onScrolled(position)
        end
    end
    local function Step(direction)
        local current = scroll:GetVerticalScroll() or 0
        if not bar.snapTops or #bar.snapTops == 0 then return ScrollTo(current + direction * SCROLL_STEP) end
        local target = direction > 0 and (bar.range or 0) or 0
        for _, top in ipairs(bar.snapTops) do
            if direction > 0 and top > current + 0.5 then target = math.min(top, bar.range or 0) break end
            if direction < 0 and top < current - 0.5 then target = top end
        end
        ScrollTo(target)
    end
    for _, direction in ipairs({ -1, 1 }) do
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(SCROLL.arrow[1], SCROLL.arrow[2])
        button:SetPoint(direction < 0 and "BOTTOM" or "TOP", bar, direction < 0 and "TOP" or "BOTTOM", 0, 0)
        button.art = button:CreateTexture(nil, "ARTWORK")
        button.kitPrefix = direction < 0 and "scroll-up" or "scroll-down"
        Theme.StatePiece(button.art, button.kitPrefix, "normal", button)
        button:SetScript("OnEnter", function(instance) Theme.StatePiece(instance.art, instance.kitPrefix, "hover", instance) end)
        button:SetScript("OnLeave", function(instance) Theme.StatePiece(instance.art, instance.kitPrefix, "normal", instance) end)
        button:SetScript("OnMouseDown", function(instance) Theme.StatePiece(instance.art, instance.kitPrefix, "pressed", instance) end)
        button:SetScript("OnMouseUp", function(instance) Theme.StatePiece(instance.art, instance.kitPrefix, "hover", instance) end)
        button:SetScript("OnClick", function() Step(direction) end)
        bar[direction < 0 and "up" or "down"] = button
    end
    bar.thumbArt = {}
    for index = 1, 3 do bar.thumbArt[index] = bar:CreateTexture(nil, "OVERLAY") end
    -- thumbTop: the thumb's distance below the bar's top, which a press hit-tests.
    function bar:PlaceThumbArt(position)
        local range, thumbHeight = self.range or 0, self.thumbHeight or 0
        local offset = range > 0 and position / range * math.max(0, self:GetHeight() - thumbHeight) or 0
        self.thumbTop = offset
        local x = (SCROLL.width - SCROLL.thumb) / 2
        local top, mid, bottom = self.thumbArt[1], self.thumbArt[2], self.thumbArt[3]
        Theme.Place(top, "scroll-thumb-normal-top", self, x, offset)
        Theme.Repeat(mid, "scroll-thumb-normal-mid", self, x, offset + SCROLL.cap,
            math.max(1, thumbHeight - 2 * SCROLL.cap), "y")
        Theme.Place(bottom, "scroll-thumb-normal-bottom", self, x, offset + thumbHeight - SCROLL.cap)
    end
    local function Wheel(_, delta) Step(-delta) end
    for _, frame in ipairs({ scroll, bar }) do
        if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
        frame:SetScript("OnMouseWheel", Wheel)
    end

    -- The cursor's height in the bar's coordinates, or nil without the API.
    local function CursorY()
        if type(GetCursorPosition) ~= "function" then return nil end
        local _, y = GetCursorPosition()
        if type(y) ~= "number" then return nil end
        return y / (bar:GetEffectiveScale() or 1)
    end
    -- The drag: a transient OnUpdate set on the press over the thumb and cleared on release, on hide,
    -- or when the button is found up (a release the bar missed). Cursor down = content down.
    local function StopDrag()
        bar.dragging = nil
        bar:SetScript("OnUpdate", nil)
    end
    local function FollowDrag()
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return StopDrag() end
        local y = CursorY()
        local travel = bar:GetHeight() - (bar.thumbHeight or 0)
        if not y or travel <= 0 then return end
        ScrollTo(bar.dragOffset + (bar.dragY - y) * (bar.range or 0) / travel)
    end
    -- A press on the track above or below the thumb pages by one view.
    bar:SetScript("OnMouseDown", function(instance, button)
        if button and button ~= "LeftButton" then return end
        local y, top = CursorY(), instance.GetTop and instance:GetTop()
        if not y or type(top) ~= "number" or (instance.range or 0) <= 0 then return end
        local below, current = top - y, scroll:GetVerticalScroll() or 0
        if below < instance.thumbTop then
            ScrollTo(current - scroll:GetHeight())
        elseif below > instance.thumbTop + (instance.thumbHeight or 0) then
            ScrollTo(current + scroll:GetHeight())
        else
            instance.dragging, instance.dragY, instance.dragOffset = true, y, current
            instance:SetScript("OnUpdate", FollowDrag)
        end
    end)
    bar:SetScript("OnMouseUp", StopDrag)
    bar:SetScript("OnHide", StopDrag)

    function bar:Sync()
        -- From the heights, so a range the client has not yet recomputed is never used.
        local view, child = scroll:GetHeight(), scroll:GetScrollChild()
        local range = math.max(0, (child and child:GetHeight() or 0) - view)
        -- A few pixels of overflow is rounding, not content: no bar for it.
        if range < 4 then range = 0 end
        local height = self:GetHeight()
        self.range, self.thumbHeight = range, math.max(24, height * view / math.max(1, view + range))
        Theme.Place(self.trackArt[1], "scroll-track-normal-top", self, 0, 0)
        Theme.Repeat(self.trackArt[2], "scroll-track-normal-mid", self, 0, SCROLL.cap, math.max(1, height - 2 * SCROLL.cap), "y")
        Theme.Place(self.trackArt[3], "scroll-track-normal-bottom", self, 0, height - SCROLL.cap)
        -- Always scrolled here, so an offset past a shorter page's end never hides its top.
        ScrollTo(scroll:GetVerticalScroll() or 0)
        -- withheld: hidden whatever the range (the Enemy players gate empties the list and the inspector).
        local shown = range > 0 and not self.withheld
        self:SetShown(shown)
        self.up:SetShown(shown)
        self.down:SetShown(shown)
    end

    -- Scrolls to offset (clamped, and snapped to a row when the list snaps) with the thumb there.
    function bar:ScrollToOffset(offset)
        self:Sync()
        ScrollTo(offset)
    end

    scroll:SetScript("OnScrollRangeChanged", function() bar:Sync() end)
    return bar
end

-- A small stage for a plate sketch (the first-run look cards, the import preview's cards): Studio's world
-- picture (the preview's shared texture) cropped to the box and darkened, in a thin bronze frame with a
-- shadow inside its top and left; flat dark where the art is missing. stage:Layout(width, height) crops
-- the picture again for the box's size (only when it changes).
local STAGE = { dim = 0.6, rim = { 0.45, 0.35, 0.21, 1 }, shadow = { 0, 0, 0, 0.8 } }
local function CreateStageBackdrop(box)
    local function Solid(layer, sublevel, colour)
        local texture = box:CreateTexture(nil, layer, nil, sublevel)
        texture:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
        return texture
    end
    local stage = { picture = box:CreateTexture(nil, "BACKGROUND", nil, 0), lines = {} }
    stage.dim = Solid("BACKGROUND", 1, { 0, 0, 0, STAGE.dim })
    stage.dim:SetAllPoints(box)
    local rim, shadow = STAGE.rim, STAGE.shadow
    -- { colour, from point, to point, x, y, horizontal }: the rim round the box, the shadow inside it.
    for _, line in ipairs({
        { rim, "TOPLEFT", "TOPRIGHT", 0, 0, true }, { rim, "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, true },
        { rim, "TOPLEFT", "BOTTOMLEFT", 0, 0, false }, { rim, "TOPRIGHT", "BOTTOMRIGHT", 0, 0, false },
        { shadow, "TOPLEFT", "TOPRIGHT", 1, -1, true }, { shadow, "TOPLEFT", "BOTTOMLEFT", 1, -1, false },
    }) do
        local texture = Solid("BORDER", 0, line[1])
        texture:SetPoint(line[2], box, line[2], line[4], line[5])
        texture:SetPoint(line[3], box, line[3], line[6] and -line[4] or line[4], line[6] and line[5] or -line[5])
        if line[6] then texture:SetHeight(1) else texture:SetWidth(1) end
        stage.lines[#stage.lines + 1] = texture
    end
    function stage:Layout(width, height)
        if self.laidWidth == width and self.laidHeight == height then return self end
        self.laidWidth, self.laidHeight = width, height
        if not Theme.Cover(self.picture, "preview-world-backdrop", box, 0, 0, width, height) then
            self.picture:SetAllPoints(box)
            self.picture:SetColorTexture(0.025, 0.03, 0.04, 1)
        end
        return self
    end
    box.stage = stage
    return stage
end

-- Panel art in a panel frame's own coordinates: the kit's section frame, and inside it the dark
-- fill with its edge shading, the inspector's parchment with its shading, or the preview's
-- world picture (and dimmer) or plain dark.
local function CreatePanelArt(frame, kind)
    local art = { frame = frame, kind = kind }
    art.fill = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    if kind == "preview" then art.dimmer = frame:CreateTexture(nil, "BACKGROUND", nil, 1) end
    -- The rail (and the parchment's shading) sit above the panel's content, so scrolled rows
    -- pass under the frame's edge instead of being cut off in the open.
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
    art.overlay = overlay
    if kind == "dark" then art.shade = Theme.NineSlice(frame, "edge-shade", "BORDER", 0) end
    if kind == "parchment" then art.shade = Theme.NineSlice(overlay, "parchment-edge-shade", "BORDER", 0) end
    art.rail = Theme.NineSlice(overlay, "section", "ARTWORK", 2)
    -- Laid out again only when its size or look changes.
    function art:Layout()
        local w, h = self.frame:GetWidth(), self.frame:GetHeight()
        if self.laidWidth == w and self.laidHeight == h and self.laidKind == self.kind and self.laidPlain == self.plain
            and self.laidTop == self.previewTop then
            return
        end
        self.laidWidth, self.laidHeight, self.laidKind, self.laidPlain, self.laidTop = w, h, self.kind, self.plain, self.previewTop
        if self.kind == "preview" then
            local inset = PREVIEW.pictureInset
            local top = self.previewTop or inset
            if self.plain then
                Theme.Fill(self.fill, "preview-plain-dark", self.frame, inset, top, w - 2 * inset, h - top - inset, 1)
                self.dimmer:Hide()
            else
                Theme.Cover(self.fill, "preview-world-backdrop", self.frame, inset, top, w - 2 * inset, h - top - inset)
                Theme.Fill(self.dimmer, "preview-dimmer", self.frame, inset, top, w - 2 * inset, h - top - inset, 1)
                self.dimmer:SetShown(self.dimmer.kitLoaded)
            end
        elseif self.kind == "parchment" then
            Theme.Fill(self.fill, "inspector-parchment-fill", self.frame, 8, 8, w - 16, h - 16, 1)
            self.shade:Layout(8, 8, w - 16, h - 16)
        else
            Theme.Fill(self.fill, "outer-fill", self.frame, 0, 0, w, h, 1)
            if self.shade then self.shade:Layout(10, 10, w - 20, h - 20) end
        end
        self.rail:Layout(0, 0, w, h)
        self.fill:SetShown(self.fill.kitLoaded)
    end
    return art
end

-- The painted outer frame: corners, the close corner (the kit's top-right), the rails between
-- them, the plaque with its transitions and mounts, the logo, and the optional rivets and gems.
local SHELL_PARTS = {
    "cornerTL", "cornerBL", "cornerBR", "closeBox", "left", "right", "topLeft", "transitionLeft",
    "transitionRight", "topRight", "bottom", "bodyFill", "headerFill", "footerFill", "headerRail", "footerRail",
    "plaque", "mountLeft", "mountRight", "logo", "gemLeft", "gemRight",
    "rivetHeaderLeft", "rivetFooterLeft", "rivetFooterRight", "rivetCornerLeft", "rivetCornerRight",
    "rivetPlaqueLeft", "rivetPlaqueRight", "rivetPlaqueSmallLeft", "rivetPlaqueSmallRight", "rivetClose", "rivetCloseTop",
}
local SHELL_LAYERS = {
    bodyFill = { "BACKGROUND", -3 }, headerFill = { "BACKGROUND", -2 }, footerFill = { "BACKGROUND", -2 },
    headerRail = { "BORDER", 2 }, footerRail = { "BORDER", 2 },
    plaque = { "ARTWORK", 4 }, logo = { "ARTWORK", 6 }, mountLeft = { "ARTWORK", 5 }, mountRight = { "ARTWORK", 5 },
}

local function CreateEditorShell(editor)
    local shell = {}
    for _, part in ipairs(SHELL_PARTS) do
        local layer = SHELL_LAYERS[part]
        local texture = editor:CreateTexture(nil, layer and layer[1] or (part:find("^rivet") or part:find("^gem"))
            and "OVERLAY" or "ARTWORK", nil, layer and layer[2] or (part:find("^corner") or part == "closeBox") and 3 or 1)
        texture.kitPart = part
        shell[part] = texture
    end
    return shell
end

local function PlaqueLeft(width)
    return math.floor(width / 2) - FRAME.plaque.width / 2
end

function Options:LayoutEditorShell()
    local shell, editor = self.editorShell, self.editor
    if not shell or not editor then return end
    local W, H = editor:GetWidth(), editor:GetHeight()
    local laid = self.editorShellLaid
    if laid and laid[1] == W and laid[2] == H then return end
    self.editorShellLaid = { W, H }
    local px = PlaqueLeft(W)
    local place = {
        cornerTL = { "outer-corner-tl", 12, 55 }, cornerBL = { "outer-corner-bl", 12, H - 132 },
        cornerBR = { "outer-corner-br", W - 114, H - 132 }, closeBox = { "close-box", W - 123, 47 },
        transitionLeft = { "plaque-transition-left", px - 32, 66 },
        transitionRight = { "plaque-transition-right", px + FRAME.plaque.width, 66 },
        plaque = { "plaque", px, FRAME.plaque.top }, logo = { "logo", px, FRAME.plaque.top },
        -- The plaque's top rivets, at about 70% of the kit's 33 px on the same centres.
        mountLeft = { "plaque-mount", px - 5, 57, 24, 25 }, mountRight = { "plaque-mount", px + 215, 57, 24, 25 },
        gemLeft = { "side-gem-left", 7, math.floor(413 + (H - 900) * 0.48 + 0.5) },
        gemRight = { "side-gem-right", W - 39, math.floor(413 + (H - 900) * 0.48 + 0.5) },
        rivetHeaderLeft = { "rivet-small", 10, 153 }, rivetFooterLeft = { "rivet-small", 10, H - 144 },
        rivetFooterRight = { "rivet-small", W - 33, H - 144 },
        rivetCornerLeft = { "rivet-corner", 18, H - 54 }, rivetCornerRight = { "rivet-corner", W - 44, H - 54 },
        rivetPlaqueLeft = { "rivet-large", px - 5, 57, 24, 25 }, rivetPlaqueRight = { "rivet-large", px + 215, 57, 24, 25 },
        rivetPlaqueSmallLeft = { "rivet-plaque-small", px + 5, 129 },
        rivetPlaqueSmallRight = { "rivet-plaque-small", px + 204, 129 },
        rivetCloseTop = { "rivet-small", W - 107, 57 }, rivetClose = { "rivet-close", W - 49, 129 },
    }
    for part, spec in pairs(place) do Theme.Place(shell[part], spec[1], editor, spec[2], spec[3], spec[4], spec[5]) end
    Theme.Repeat(shell.left, "outer-edge-left", editor, 12, 167, H - 299, "y")
    Theme.Repeat(shell.right, "outer-edge-right", editor, W - 34, 159, H - 291, "y")
    Theme.Repeat(shell.topLeft, "outer-edge-top", editor, 108, 66, px - 32 - 108, "x")
    Theme.Repeat(shell.topRight, "outer-edge-top", editor, px + FRAME.plaque.width + 32, 66,
        W - 123 - (px + FRAME.plaque.width + 32), "x")
    Theme.Repeat(shell.bottom, "outer-edge-bottom", editor, 116, H - 51, W - 230, "x")
    -- The body behind and between the panels, from the header down to the bottom moulding; the
    -- kit's proofs sat on a dark ground, so its placements leave it out.
    Theme.Fill(shell.bodyFill, "outer-fill", editor, 34, 84, W - 68, H - 84 - 51, 1)
    Theme.Fill(shell.headerFill, "outer-fill", editor, 34, 84, W - 68, 76, 1)
    Theme.Fill(shell.footerFill, "outer-fill", editor, 34, H - 106, W - 68, 55, 1)
    Theme.Repeat(shell.headerRail, "header-edge-bottom", editor, 36, 152, W - 72, "x")
    Theme.Repeat(shell.footerRail, "footer-edge-top", editor, 36, H - 102, W - 72, "x")
    for _, texture in pairs(shell) do texture:SetShown(texture.kitLoaded) end
end

-- The panels' rectangles for Studio's width and height: { x, y, width, height } of the tree (or
-- Settings categories), the preview, the inspector, and Settings' page (preview and inspector).
function Options:EditorPanelRects(width, height)
    local top, bottom = FRAME.panelTop, height - FRAME.panelBottom
    local inspectorX = width - FRAME.right - FRAME.inspector
    local previewX = FRAME.left + FRAME.tree + FRAME.gap
    return {
        tree = { FRAME.left, top, FRAME.tree, bottom - top },
        preview = { previewX, top, inspectorX - FRAME.gap - previewX, bottom - top },
        inspector = { inspectorX, top, FRAME.inspector, bottom - top },
        page = { previewX, top, width - FRAME.right - previewX, bottom - top },
    }
end

local function PlaceRect(frame, parent, rect)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", rect[1], -rect[2])
    frame:SetSize(rect[3], rect[4])
end

function Options:LayoutEditorArt()
    self:LayoutEditorShell()
    for _, art in ipairs(self.editorPanelArt or {}) do art:Layout() end
    for _, button in ipairs(studioButtons) do
        if button.studioArt then button.studioArt:Layout() end
        if button.studioGlow then button.studioGlow:Layout() end
    end
    -- Value boxes and fields drawn from three-slice art follow their frames' sizes.
    for _, field in ipairs(self.editorKitFields or {}) do field:Layout() end
end

-- Whether the plates use the colour-blind threat palette (Settings › Threat › Palette, or its
-- Follow colour-blind mode with the game's option on).
local function PlatesColourBlind()
    local ThreatText = PS.ThreatText
    if not (ThreatText and ThreatText.Palette) then return false end
    return ThreatText.Palette() == ThreatText.Palette(true)
end

-- This player's accessibility options: { colourBlind, highContrast } (personal, never saved in
-- a profile). Colour-blind friendly is state studioColourBlind: nil follows the plates' palette,
-- true is on, "off" is off. Read on every row and handle, so it is kept until SetStudioAccess
-- or the plates' palette changes it; callers must not change the table.
function Options:StudioAccess()
    local state = PS.GetState and PS.GetState()
    local choice = state and state.studioColourBlind
    local plates = choice == nil and PlatesColourBlind() or nil
    local access = self.studioAccess
    if access and access.state == state and access.choice == choice and access.plates == plates then return access end
    access = { state = state, choice = choice, plates = plates, colourBlind = choice == true or plates == true,
        highContrast = state and state.studioHighContrast == true or false }
    self.studioAccess = access
    return access
end

-- The Accessibility row's choices: follow (naming what the plates use now), on, off.
function Options.StudioColourBlindChoices()
    return {
        { value = "follow", label = string.format(L["Follow the plates' palette (%s)"],
            PlatesColourBlind() and L["On"] or L["Off"]) },
        { value = "on", label = L["On"] },
        { value = "off", label = L["Off"] },
    }
end

function Options:StudioColourBlindChoice()
    local state = PS.GetState and PS.GetState()
    local choice = state and state.studioColourBlind
    return choice == true and "on" or choice == "off" and "off" or "follow"
end

-- colourBlind takes true or "on", false or "off", nil or "follow"; highContrast a boolean.
function Options:SetStudioAccess(key, enabled)
    local state = PS.GetState and PS.GetState()
    local field = key == "colourBlind" and "studioColourBlind" or key == "highContrast" and "studioHighContrast"
    if not state or not field then return false end
    if key == "colourBlind" then
        if enabled == true or enabled == "on" then
            enabled = true
        elseif enabled == false or enabled == "off" then
            enabled = "off"
        elseif enabled == nil or enabled == "follow" then
            enabled = nil
        else
            return false
        end
    elseif type(enabled) ~= "boolean" then
        return false
    end
    state[field] = enabled
    self.studioAccess = nil
    -- High contrast starts the preview on the plain dark ground (the world picture is busy).
    if key == "highContrast" and enabled then self.editorPlainStage = true end
    self:Refresh()
    return true
end

-- The kit's look for Studio's shared controls: checkboxes, sliders and dropdowns.
-- The tree's show/hide toggles: an eye (open shown, crossed hidden, half-lit for a group with
-- some parts hidden) in the checkbox's states, instead of a tick.
local function PaintVisibilityEye(checkbox, state)
    state = state or checkbox.eyeState or "normal"
    checkbox.eyeState = state
    local look = checkbox.mixed and "mixed" or checkbox:GetChecked() and "shown" or "hidden"
    if look == "mixed" then state = "normal" end
    if checkbox.IsEnabled and not checkbox:IsEnabled() then state = "disabled" end
    Theme.Place(checkbox.kitBox, "visibility-" .. look .. "-" .. state, checkbox, 0, 0)
end

local function SkinVisibilityEye(checkbox)
    checkbox:SetSize(26, 28)
    local box = checkbox:CreateTexture(nil, "BACKGROUND", nil, 2)
    checkbox.kitBox = box
    -- No tick: the eye itself shows the state.
    local none = checkbox:CreateTexture(nil, "OVERLAY")
    checkbox:SetCheckedTexture(none)
    checkbox.checkedTexture = none
    local setChecked = checkbox.SetChecked
    function checkbox.SetChecked(instance, ...)
        setChecked(instance, ...)
        PaintVisibilityEye(instance)
    end
    if checkbox.HookScript then
        checkbox:HookScript("OnEnter", function(instance) PaintVisibilityEye(instance, "hover") end)
        checkbox:HookScript("OnLeave", function(instance) PaintVisibilityEye(instance, "normal") end)
        checkbox:HookScript("OnMouseDown", function(instance) PaintVisibilityEye(instance, "pressed") end)
        checkbox:HookScript("OnMouseUp", function(instance) PaintVisibilityEye(instance, "hover") end)
        checkbox:HookScript("OnClick", function(instance) PaintVisibilityEye(instance) end)
    end
    PaintVisibilityEye(checkbox, "normal")
end

local function SkinCheckbox(checkbox)
    if checkbox.kitSkinned then return end
    checkbox.kitSkinned = true
    for _, key in ipairs({ "studioBox", "studioFill" }) do
        if checkbox[key] then checkbox[key]:Hide() end
    end
    if checkbox.visibilityEye then return SkinVisibilityEye(checkbox) end
    checkbox:SetSize(26, 28)
    local box = checkbox:CreateTexture(nil, "BACKGROUND", nil, 2)
    Theme.Place(box, "checkbox-empty-normal", checkbox, 0, 0)
    checkbox.kitBox = box
    local tick = checkbox:CreateTexture(nil, "OVERLAY")
    Theme.Place(tick, "checkbox-ticked-normal", checkbox, 0, 0)
    checkbox:SetCheckedTexture(tick)
    checkbox.checkedTexture = tick
    checkbox:SetScript("OnEnter", checkbox:GetScript("OnEnter"))
    if checkbox.HookScript then
        checkbox:HookScript("OnEnter", function(instance) Theme.Place(instance.kitBox, "checkbox-empty-hover", instance, 0, 0) end)
        checkbox:HookScript("OnLeave", function(instance) Theme.Place(instance.kitBox, "checkbox-empty-normal", instance, 0, 0) end)
    end
    -- The kit lights the box while its row's label is pointed at (Layout's labelled check rows).
    function checkbox:KitHover(on)
        Theme.Place(self.kitBox, on and "checkbox-empty-hover" or "checkbox-empty-normal", self, 0, 0)
    end
end

local function SkinSlider(slider)
    if slider.kitSkinned then return end
    slider.kitSkinned = true
    if slider.SetBackdrop then pcall(slider.SetBackdrop, slider, nil) end
    if slider.NineSlice then slider.NineSlice:Hide() end
    local track = CreateFrame("Frame", nil, slider)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(8)
    track:SetFrameLevel(math.max(0, slider:GetFrameLevel() - 1))
    slider.kitTrack = Theme.ThreeSlice(track, "slider-track", nil)
    slider.kitTrack:Layout()
    track:SetScript("OnSizeChanged", function() slider.kitTrack:Layout() end)
    local thumbPath = Theme.Path("slider-thumb-normal")
    slider:SetThumbTexture(thumbPath)
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(14, 16)
        thumb:SetTexCoord(Theme.TexCoord("slider-thumb-normal"))
    end
    slider.studioThumb = thumbPath
    -- The range captions sit under the track's ends, inside the column rather than past its edge.
    local name = slider.GetName and slider:GetName()
    for _, spec in ipairs({ { "Low", "TOPLEFT", "BOTTOMLEFT" }, { "High", "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local caption = slider[spec[1]] or name and _G[name .. spec[1]]
        if caption and caption.ClearAllPoints then
            caption:ClearAllPoints()
            caption:SetPoint(spec[2], slider, spec[3], 0, -1)
        end
    end
end

-- A dropdown (Controls.MenuField) in the kit's art: its field three-slice and arrow, lit
-- together on hover and while its menu is open. The field itself is the button, so a click
-- anywhere on it opens and closes the menu.
local function SkinDropdown(dropdown)
    if dropdown.kitSkinned then return end
    dropdown.kitSkinned = true
    if dropdown.SetBackdrop then dropdown:SetBackdrop(nil) end
    if dropdown.arrow then dropdown.arrow:Hide() end
    dropdown.kitField = Theme.ThreeSlice(dropdown, "dropdown-field", nil)
    dropdown.kitField:Layout()
    local arrow = dropdown:CreateTexture(nil, "OVERLAY")
    dropdown.kitArrow = arrow
    local function PlaceArrow(state)
        Theme.Place(arrow, "dropdown-arrow-" .. state, dropdown, 0, 0)
        arrow:ClearAllPoints()
        arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    end
    PlaceArrow("normal")
    function dropdown:PaintState(state)
        state = PS.UI.Menu.IsOpenFor(self) and "hover" or state or "normal"
        self.kitField:SetState(state)
        PlaceArrow(state)
    end
    dropdown:SetScript("OnSizeChanged", function() dropdown.kitField:Layout() end)
    -- The choice reads from the field's left, at the labels' size, above the field's art.
    local text = dropdown.Text
    if text then
        if text.SetDrawLayer then text:SetDrawLayer("OVERLAY", 7) end
        text:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
        text:SetFont(FONT, 15)
        text:SetJustifyH("LEFT")
        text:ClearAllPoints()
        text:SetPoint("LEFT", dropdown, "LEFT", 12, 0)
        text:SetPoint("RIGHT", dropdown, "RIGHT", -30, 0)
    end
    dropdown.kitText = text
    dropdown.studioSkin = { dropdown }
end

-- The inspector's labels and the kit's segments, cards and sections in the current look, from
-- position marks[list] + 1 of each list (marks nil: all of them). Studio builds pages and contexts
-- on demand (Inspector.lua), so their pieces are given the look as they are made.
local THEMED_LISTS = { "editorSegments", "editorCards", "editorSections" }
local function PaintKitObjects(self, marks)
    local kit, inspector = self.inspectorKit, self.editorInspector
    local labels = kit and inspector and inspector.studioInkLabels or {}
    for index = (marks and marks.labels or 0) + 1, #labels do
        local entry = labels[index]
        local label = entry.label
        kit.Ink(label, label.studioInk or (entry.colour[1] > 0.9 and entry.colour[3] < 0.5 and "title" or "label"))
    end
    for _, key in ipairs(THEMED_LISTS) do
        local list = self[key] or {}
        for index = (marks and marks[key] or 0) + 1, #list do list[index]:Paint() end
    end
end

-- Where each themed list ends now, for PaintEditorThemeSince after something is built.
function Options:EditorThemeMarks()
    local inspector = self.editorInspector
    local marks = { labels = inspector and inspector.studioInkLabels and #inspector.studioInkLabels or 0,
        fields = #(self.editorKitFields or {}) }
    for _, key in ipairs(THEMED_LISTS) do marks[key] = #(self[key] or {}) end
    return marks
end

function Options:PaintEditorThemeSince(marks)
    if not self.editor then return end
    PaintKitObjects(self, marks)
    local fields = self.editorKitFields or {}
    for index = (marks.fields or 0) + 1, #fields do fields[index]:Layout() end
end

function Options:ApplyEditorTheme()
    local editor = self.editor
    if not editor then return end
    local stage = self.editorStageArt
    -- Plain while the user picks it, and behind the Enemy players gate (nothing to look at there).
    if stage then stage.plain = (self.editorPlainStage or self.editorPlayersGated) and true or false end
    self:LayoutEditorArt()
    for _, button in ipairs(studioButtons) do SetStudioButtonState(button, button.studioSelected) end
    local access = self:StudioAccess()
    -- The inspector is parchment, its labels inked (dark brown, headings russet, help and
    -- sub-headings a lighter brown); in high contrast it is a dark panel with white text and
    -- gold headings.
    local art = self.editorInspectorArt
    if art then
        art.kind = access.highContrast and "dark" or "parchment"
        if art.shade then art.shade:SetShown(not access.highContrast) end
        art:Layout()
    end
    -- The inspector's kit (UI/Layout.lua) inks in the palette for the current look: each label
    -- keeps its role; one the kit did not ink is a heading when its template was gold, else a label.
    local kit = self.inspectorKit
    PaintKitObjects(self)
    if kit and self.editorComponentNameEdit then kit.Ink(self.editorComponentNameEdit, "label") end
    if kit and self.editorComponentTitle then kit.Ink(self.editorComponentTitle, "label") end
    -- The model's note grows and brightens in high contrast.
    local note = self.editorModelNote
    if note then
        note:SetFont(FONT, access.highContrast and 14 or 12)
        if access.highContrast then note:SetTextColor(0.95, 0.93, 0.88) else note:SetTextColor(0.62, 0.60, 0.56) end
    end
    -- Snap guides: thicker lines for either option.
    local thick = access.highContrast or access.colourBlind
    if self.editorSnapGuideX then self.editorSnapGuideX:SetWidth(thick and 2 or 1) end
    if self.editorSnapGuideY then self.editorSnapGuideY:SetHeight(thick and 2 or 1) end
    for _, bar in ipairs({ self.editorListScrollBar, self.editorComponentScrollBar, self.editorSettingsScrollBar }) do
        if bar then bar:Sync() end
    end
    self:PlaceEditorTitle()
    self:ApplyEditorListInk()
end

-- View › Plain dark background: the kit's dark fill behind the preview instead of the world picture.
function Options:SetEditorPlainStage(on)
    self.editorPlainStage = on and true or false
    self:ApplyEditorTheme()
    return self.editorPlainStage
end

-- Settings: the categories down the left, one category's page at a time on the right. Pages
-- are the panels built by the inspector (their keys), in the order shown.
local SETTINGS_CATEGORIES = {
    { key = "plate", label = L["Behaviour & display"], summary = L["Shared settings for the active profile."] },
    { key = "stacking", label = L["Stacking & distance"],
        summary = L["How Blizzard stacks, spaces, scales and fades plates, and which draws on top."] },
    { key = "auras", label = L["Aura defaults"], summary = L["Which buffs and debuffs the plates show."] },
    { key = "relations", label = L["Relationships"], summary = L["How friendly players are marked outdoors."] },
    -- tooltip: the page header's "?" (Options.editorSettingsHelp).
    { key = "experimental", label = L["Experimental"], summary = L["Tests of what the game allows. Each is off by default."],
        tooltip = L["Each option here tests something the game may or may not allow on this client. They are off by "
            .. "default and cost nothing while off. Turn one on, play, then run /ps diagnose: its experimental section "
            .. "says whether each one worked."] },
    { key = "studio", label = L["Studio"], summary = L["Studio's size and accessibility. Personal; never needs Save."] },
    { key = "help", label = L["Help"], summary = L["How Blueprint Studio works, and PlateSmith's commands."] },
}

function Options:SettingsCategoryList()
    local list = {}
    for _, category in ipairs(SETTINGS_CATEGORIES) do
        if not category.hidden then list[#list + 1] = category end
    end
    return list
end

-- A category's key, label and summary, listed now or not.
function Options:SettingsCategoryInfo(key)
    for _, category in ipairs(SETTINGS_CATEGORIES) do
        if category.key == key then return category end
    end
    return nil
end

function Options:SetSettingsCategory(key)
    -- Picking a category (or leaving Settings) ends a search: its rows go back to their pages.
    local search = self.settingsSearch
    if search and search.IsBusy() then search.Clear() end
    local found
    for _, category in ipairs(self:SettingsCategoryList()) do
        if category.key == key then found = category end
    end
    for _, category in ipairs(SETTINGS_CATEGORIES) do
        if not found and category.key == key then found = category end
    end
    found = found or SETTINGS_CATEGORIES[1]
    -- Another category opens at its top, as Blizzard's Settings do.
    local viewport = self.editorSettingsViewport
    if found.key ~= self.editorSettingsCategory and viewport and viewport.SetVerticalScroll then
        viewport:SetVerticalScroll(0)
    end
    self.editorSettingsCategory = found.key
    if self.editorSettingsTitle then self.editorSettingsTitle:SetText(found.label) end
    if self.editorSettingsSummary then self.editorSettingsSummary:SetText(found.summary) end
    local help = self.editorSettingsHelp
    if help then
        help.helpTitle, help.helpText = found.label, found.tooltip
        help:SetShown(found.tooltip ~= nil)
    end
    self:LayoutEditorSettingsPanels()
    return true
end

function Options:LayoutEditorSettingsPanels()
    local content, viewport, pages = self.editorSettingsContent, self.editorSettingsViewport, self.editorInspectorPages
    if not content or not viewport or not pages then return end
    local width = viewport:GetWidth()
    content:SetWidth(width)
    local current = self.editorSettingsCategory or "plate"
    local settingsOpen = self.editorWorkspacePage == "settings"
    -- Search results replace the category's page (which is not laid out: it lent them its rows).
    local search = self.settingsSearch
    local searching = search and search.IsActive() or false
    -- A page is built the first time it shows.
    if settingsOpen and not searching and self.EditorSettingsPage then self:EditorSettingsPage(current) end
    -- The shown page is laid out at the page's width (its sections in one or two columns).
    for _, panel in ipairs(self.editorSettingsPanels or {}) do
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        local shown = settingsOpen and not searching and panel.settingsKey == current
        panel:SetShown(shown)
        if shown and panel.Relayout then panel:Relayout(width) end
    end
    local page = pages[current]
    local height = page and page:GetHeight() or 1
    if search then
        local found = search.LayoutResults(width, settingsOpen)
        if searching then height = found end
    end
    content:SetHeight(math.max(1, height))
    for index, row in ipairs(self.editorSettingsCategoryRows or {}) do
        local category = self:SettingsCategoryList()[index]
        row:SetShown(category ~= nil)
        if category then
            row.categoryKey = category.key
            row.label:SetText(category.label)
            SetStudioButtonState(row, not searching and category.key == current)
        end
    end
    if self.editorSettingsScrollBar then self.editorSettingsScrollBar:Sync() end
end

-- Studio or Settings (the header toggle). "components" is Studio; any settings page opens Settings.
function Options:SetEditorInspectorPage(page)
    if page ~= "components" and self.EditorSettingsPage then self:EditorSettingsPage(page) end
    if not self.editorInspectorPages or not self.editorInspectorPages[page] then return end
    self.editorInspectorPage = page
    local settingsOpen = page ~= "components"
    self.editorWorkspacePage = settingsOpen and "settings" or "preview"
    if settingsOpen and self.EditorSettingsCategories then self:EditorSettingsCategories() end
    if settingsOpen then
        if page ~= "plate" or not self.editorSettingsCategory then self.editorSettingsCategory = page end
        if self.editorSettingsViewport and self.editorSettingsViewport.SetVerticalScroll then
            self.editorSettingsViewport:SetVerticalScroll(0)
        end
    end
    for _, frame in ipairs({ self.editorList, self.editorCanvas, self.editorInspector }) do
        frame:SetShown(not settingsOpen)
    end
    for _, frame in ipairs({ self.editorSettingsWorkspace, self.editorSettingsCategoriesPanel }) do
        if frame then frame:SetShown(settingsOpen) end
    end
    self.editorInspectorPages.components:SetShown(not settingsOpen)
    self:SetSettingsCategory(self.editorSettingsCategory or "plate")
    if self.editorStudioToggle then SetStudioButtonState(self.editorStudioToggle, not settingsOpen) end
    if self.editorSettingsButton then SetStudioButtonState(self.editorSettingsButton, settingsOpen) end
    for _, button in ipairs(self.editorStudioFooterButtons or {}) do button:SetShown(not settingsOpen) end
    for _, button in ipairs(self.editorSettingsFooterButtons or {}) do button:SetShown(settingsOpen) end
    self:RefreshEditorInspectorContext()
end

-- The subtitle under the logo; Studio's title is the plaque's logo layer.
function Options:PlaceEditorTitle()
    local editor = self.editor
    if not editor or not self.editorSubtitle then return end
    self.editorSubtitle:ClearAllPoints()
    self.editorSubtitle:SetPoint("CENTER", editor, "TOPLEFT", math.floor(editor:GetWidth() / 2), -137)
    -- Studio stays clamped to the screen with the plaque's top, not just its frame.
    if editor.SetClampRectInsets then editor:SetClampRectInsets(0, 0, 0, 0) end
end

function Options:PlaceEditorCloseButton()
    local close, editor = self.editorCloseButton, self.editor
    if not close or not editor then return end
    close:ClearAllPoints()
    close:SetPoint("TOPLEFT", editor, "TOPLEFT", editor:GetWidth() - 75, -69)
end

function Options:ReflowVisualEditor()
    local editor, canvas, inspector = self.editor, self.editorCanvas, self.editorInspector
    if not editor or not canvas or not inspector then return end
    local width = editor.GetWidth and editor:GetWidth() or 1440
    local height = editor.GetHeight and editor:GetHeight() or 900
    local rects = self:EditorPanelRects(width, height)
    PlaceRect(self.editorList, editor, rects.tree)
    PlaceRect(canvas, editor, rects.preview)
    PlaceRect(inspector, editor, rects.inspector)
    if self.editorSettingsCategoriesPanel then PlaceRect(self.editorSettingsCategoriesPanel, editor, rects.tree) end
    if self.editorSettingsWorkspace then PlaceRect(self.editorSettingsWorkspace, editor, rects.page) end
    -- The workbench is the whole body, for anything still anchored to it.
    PlaceRect(self.editorWorkbench, editor, { FRAME.left, FRAME.panelTop, width - FRAME.left - FRAME.right,
        height - FRAME.panelBottom - FRAME.panelTop })

    -- Header controls, centred on the header band.
    local px = PlaqueLeft(width)
    local y = FRAME.headerControls
    if self.editorStudioToggle then
        self.editorStudioToggle:ClearAllPoints()
        self.editorStudioToggle:SetPoint("TOPLEFT", editor, "TOPLEFT", px + 244, -y)
        self.editorSettingsButton:ClearAllPoints()
        self.editorSettingsButton:SetPoint("TOPLEFT", editor, "TOPLEFT", px + 343, -y)
    end
    if self.editorNamedProfileDropdown then
        -- The picker's field is 34 px tall, centred on its label's line (y + 17).
        self.editorNamedProfileDropdown:ClearAllPoints()
        self.editorNamedProfileDropdown:SetPoint("TOPLEFT", editor, "TOPLEFT", width - 236, -y)
        self.editorNamedProfileDropdown:SetSize(126, 34)
    end
    if self.editorProfileLabel then
        self.editorProfileLabel:ClearAllPoints()
        self.editorProfileLabel:SetPoint("RIGHT", editor, "TOPLEFT", width - 246, -(y + 17))
    end
    self:PlaceEditorCloseButton()

    -- Footer buttons, on the footer band's centre line.
    local footerY = height - FRAME.footerButtons
    local footer = self.editorFooterLayout or {}
    for _, entry in ipairs(footer) do
        entry.button:ClearAllPoints()
        entry.button:SetPoint("TOPLEFT", editor, "TOPLEFT", entry.right and width - entry.x or entry.x, -footerY)
    end
    -- The CPU readout sits just left of Revert; the unsaved-changes notice takes the middle before it.
    local readout = self.editorCpuReadout
    if readout then
        readout:ClearAllPoints()
        readout:SetPoint("RIGHT", editor, "TOPLEFT", width - CPU_READOUT.right, -(footerY + 16))
        readout:SetSize(CPU_READOUT.width, CPU_READOUT.height)
    end
    if self.editorProfileNotice then
        self.editorProfileNotice:ClearAllPoints()
        self.editorProfileNotice:SetPoint("LEFT", editor, "TOPLEFT", 520, -(footerY + 16))
        local reserved = readout and CPU_READOUT.right + CPU_READOUT.width + CPU_READOUT.gap or 380
        self.editorProfileNotice:SetWidth(math.max(1, width - 520 - reserved))
    end

    self:LayoutEditorTree()
    self:LayoutEditorPreviewPanel()
    self:LayoutEditorInspectorPanel()
    self:LayoutEditorSettingsPage()
    if not self.editorBuilding then self:RefreshEditorComponentList(PS.GetSettings()) end
    self:LayoutEditorArt()
    self:UpdateEditorGrid()
    if self.editorPreviewFit and not self.editorDrag then self:FitEditorPreview(self.editorPreviewFitZoom) end
end

-- The tree panel: its title, + Group and + Value, the search field, then the list and its bar.
function Options:LayoutEditorTree()
    local list = self.editorList
    if not list then return end
    local w, h = list:GetWidth(), list:GetHeight()
    local function At(frame, x, y, fw, fh)
        if not frame then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", list, "TOPLEFT", x, -y)
        if fw then frame:SetWidth(fw) end
        if fh then frame:SetHeight(fh) end
    end
    At(self.editorListTitle, 14, 14)
    At(self.editorAddButton, 13, 44, w - 30)
    if self.editorAddButton and self.editorAddButton.studioArt then self.editorAddButton.studioArt:Layout() end
    At(self.editorSearchField, 12, 87, w - 30, 34)
    if self.editorSearchField then
        self.editorSearchField.field:Layout()
        Theme.Place(self.editorSearchField.icon, "search-icon-normal", self.editorSearchField, 8, 5)
    end
    At(self.editorListScroll, 9, 130, w - 44, h - 130 - 14)
    if self.editorListContent then self.editorListContent:SetWidth(w - 44) end
    if self.editorListScrollBar then
        self.editorListScrollBar:ClearAllPoints()
        self.editorListScrollBar:SetPoint("TOPLEFT", list, "TOPLEFT", w - 31, -156)
        self.editorListScrollBar:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", w - 31, 39)
    end
end

-- The preview panel: plate-type tabs across its top, the design row beneath them (the design, its chip,
-- Where plates show's eye and View, the model's note under View), the stage, and the zoom, Snap, Test
-- values and nudge controls along its foot; Test values' panel opens upwards from its button.
function Options:LayoutEditorPreviewPanel()
    local canvas = self.editorCanvas
    if not canvas then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local tabs = self.editorPlateTabs or {}
    local tabWidth = math.floor((w - 16 - 2 * (#tabs - 1)) / math.max(1, #tabs))
    for index, tab in ipairs(tabs) do
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8 + (index - 1) * (tabWidth + 2), -7)
        tab:SetWidth(index == #tabs and (w - 16 - (index - 1) * (tabWidth + 2)) or tabWidth)
    end
    if self.editorStageArt then self.editorStageArt.previewTop = PREVIEW.pictureTop end
    local row = self.editorDesignRow
    if row then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", canvas, "TOPLEFT", PREVIEW.side, -PREVIEW.rowTop)
        row:SetSize(math.max(1, w - 2 * PREVIEW.side), PREVIEW.rowHeight)
    end
    local note = self.editorModelNote
    if note then
        note:ClearAllPoints()
        note:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -PREVIEW.side, -(PREVIEW.rowTop + PREVIEW.rowHeight + 4))
        note:SetWidth(math.max(1, w - 2 * PREVIEW.side))
    end
    -- The friendly layout switch: the preview's lower left, above its controls.
    for index, key in ipairs({ "names", "full" }) do
        local button = self.editorFriendlyViewButtons and self.editorFriendlyViewButtons[key]
        if button then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16 + (index - 1) * 108, -(h - 88))
        end
    end
    local footY = h - PREVIEW.footY
    local function Foot(frame, x, fromRight)
        if not frame then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", fromRight and w - x or x, -footY)
    end
    Foot(self.editorZoomOutButton, 14)
    if self.editorZoomText then
        self.editorZoomText:ClearAllPoints()
        self.editorZoomText:SetPoint("CENTER", canvas, "TOPLEFT", 81, -(footY + 16))
    end
    Foot(self.editorZoomInButton, 115)
    Foot(self.editorFitButton, 164)
    local snap = self.editorSnapCheckbox
    if snap then
        snap:ClearAllPoints()
        snap:SetPoint("TOPLEFT", canvas, "TOPLEFT", PREVIEW.snapX, -(footY + 3))
    end
    -- Test values after Snap's label, centred on the foot's line; its panel opens upwards from it, inside
    -- the preview (moved left where the preview is too narrow for it).
    local test = self.editorTestButton
    if test then
        local x = PREVIEW.snapX + (snap and snap:GetWidth() + 6 + snap.label:GetStringWidth() or 0) + PREVIEW.testGap
        x = math.floor(x + 0.5)
        test:ClearAllPoints()
        test:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -(footY + 3))
        local panel = self.editorTestPanel
        if panel then
            self.editorTestPanelLeft = math.max(PREVIEW.side - 4, math.min(x, w - 12 - panel:GetWidth()))
            panel:ClearAllPoints()
            panel:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", self.editorTestPanelLeft, -(footY - PREVIEW.panelGap))
        end
    end
    if self.editorMoveControls then
        self.editorMoveControls:ClearAllPoints()
        self.editorMoveControls:SetPoint("TOPLEFT", canvas, "TOPLEFT", w - 218, -footY)
    end
    if self.editorPreviewStage then
        self.editorPreviewStage:ClearAllPoints()
        self.editorPreviewStage:SetPoint("CENTER", canvas, "CENTER", self.editorPreviewPanX or 0, self.editorPreviewPanY or 0)
    end
    if self.PlaceEditorModel then self:PlaceEditorModel(true) end
end

-- The inspector panel: one scrolling column on the parchment, its bar inside the right rail.
function Options:LayoutEditorInspectorPanel()
    local inspector = self.editorInspector
    if not inspector then return end
    local w, h = inspector:GetWidth(), inspector:GetHeight()
    local scroll, rail, lane = self.editorComponentScroll, INSPECTOR.rail, INSPECTOR.lane
    if scroll then
        scroll:ClearAllPoints()
        -- The parchment inside the rail, up to the scroll bar's lane (kept whether or not the bar
        -- shows, so nothing shifts); the scroll child adds the padding (Inspector's INSPECTOR_PAD).
        scroll:SetPoint("TOPLEFT", inspector, "TOPLEFT", rail, -rail)
        scroll:SetSize(w - rail - lane, h - rail * 2)
    end
    local pad = self.editorInspectorPad
    local contentWidth = w - rail - lane - pad.left - pad.right
    if self.editorComponentContent then self.editorComponentContent:SetWidth(contentWidth) end
    if self.editorComponentHolder then self.editorComponentHolder:SetWidth(contentWidth + pad.left + pad.right) end
    if not self.editorBuilding then self:LayoutEditorInspector() end
    if self.editorComponentScrollBar then
        self.editorComponentScrollBar:ClearAllPoints()
        self.editorComponentScrollBar:SetPoint("TOPLEFT", inspector, "TOPLEFT", w - lane, -37)
        self.editorComponentScrollBar:SetPoint("BOTTOMLEFT", inspector, "BOTTOMLEFT", w - lane, 37)
    end
end

-- Settings' page panel: the category's title and summary, a rule, then its controls (scrolling).
function Options:LayoutEditorSettingsPage()
    local page = self.editorSettingsWorkspace
    if not page then return end
    local w, h = page:GetWidth(), page:GetHeight()
    if self.editorSettingsTitle then
        self.editorSettingsTitle:ClearAllPoints()
        self.editorSettingsTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 22, -18)
        if self.editorSettingsHelp then
            self.editorSettingsHelp:ClearAllPoints()
            self.editorSettingsHelp:SetPoint("LEFT", self.editorSettingsTitle, "RIGHT", 8, 0)
        end
    end
    if self.editorSettingsSummary then
        self.editorSettingsSummary:ClearAllPoints()
        self.editorSettingsSummary:SetPoint("TOPLEFT", page, "TOPLEFT", 22, -60)
    end
    if self.editorSettingsRule then
        self.editorSettingsRule:ClearAllPoints()
        self.editorSettingsRule:SetPoint("TOPLEFT", page, "TOPLEFT", 22, -100)
        self.editorSettingsRule:SetWidth(w - 44 - 26)
    end
    if self.editorSettingsViewport then
        self.editorSettingsViewport:ClearAllPoints()
        self.editorSettingsViewport:SetPoint("TOPLEFT", page, "TOPLEFT", 22, -118)
        self.editorSettingsViewport:SetSize(w - 44 - 26, h - 118 - 20)
    end
    if self.editorSettingsScrollBar then
        self.editorSettingsScrollBar:ClearAllPoints()
        self.editorSettingsScrollBar:SetPoint("TOPLEFT", page, "TOPLEFT", w - 28, -35)
        self.editorSettingsScrollBar:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", w - 28, 35)
    end
    -- The search box tops the categories panel; the categories follow under it.
    local categories, search = self.editorSettingsCategoriesPanel, self.editorSettingsSearch
    local rowsTop = CATEGORIES.top
    if search and categories then
        search:ClearAllPoints()
        search:SetPoint("TOPLEFT", categories, "TOPLEFT", CATEGORIES.searchX, -CATEGORIES.top)
        search:SetSize(categories:GetWidth() - 2 * CATEGORIES.searchX, CATEGORIES.searchH)
        search.field:Layout()
        Theme.Place(search.icon, "search-icon-normal", search, 8, 5)
        rowsTop = CATEGORIES.top + CATEGORIES.searchH + CATEGORIES.searchGap
    end
    for index, row in ipairs(self.editorSettingsCategoryRows or {}) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", categories, "TOPLEFT", 8, -(rowsTop + (index - 1) * CATEGORIES.rowStep))
    end
    self:LayoutEditorSettingsPanels()
end

function Options:GetStudioScale()
    local state = PS.GetState and PS.GetState()
    return state and state.studioScale or 1
end

-- The player's chosen Studio size (60-130%, in 5% steps). A personal preference: it applies at
-- once and never needs Save.
function Options:SetStudioScale(scale)
    local state = PS.GetState and PS.GetState()
    local range = PS.ProfileSchema.studioScaleRange
    if not state or type(scale) ~= "number" then return false end
    state.studioScale = math.max(range[1], math.min(range[2], math.floor(scale * 20 + 0.5) / 20))
    self:FitVisualEditorToScreen()
    return true
end

-- The chosen scale, reduced further only when Studio would not fit the screen.
function Options:FitVisualEditorToScreen()
    local editor = self.editor
    if not editor then return end
    local scale = self:GetStudioScale()
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if screenWidth and screenHeight and screenWidth > 0 and screenHeight > 0 then
        scale = math.min(scale, (screenWidth - 40) / editor:GetWidth(), (screenHeight - 40) / editor:GetHeight())
    end
    editor:SetScale(math.max(0.5, scale))
    -- Studio can grow to fill the screen at the chosen size, never below the kit's 1440 x 900.
    if editor.SetResizeBounds and screenWidth and screenHeight and screenWidth > 0 then
        local chosen = self:GetStudioScale()
        editor:SetResizeBounds(1440, 900, math.max(1440, math.floor((screenWidth - 40) / chosen)),
            math.max(900, math.floor((screenHeight - 40) / chosen)))
    end
    self:RefreshStudioScaleControls()
    self:ReflowVisualEditor()
end

-- Settings › Studio's size row (built with that page, when it is first shown).
function Options:RefreshStudioScaleControls()
    if not self.editorStudioScaleText then return end
    self.editorStudioScaleText:SetText(PS.UI.Controls.PercentText(self:GetStudioScale()))
    self.editorStudioSmaller:SetEnabled(self:GetStudioScale() > PS.ProfileSchema.studioScaleRange[1])
    self.editorStudioLarger:SetEnabled(self:GetStudioScale() < PS.ProfileSchema.studioScaleRange[2])
end

-- The client loads a texture file the first time something shows it, drawing nothing until it
-- arrives, so a control's hover or pressed art blinked out on its first use. Studio shows every
-- state's pieces once, invisibly, when it is built, so they are ready when needed (one texture
-- per file: most states share a sprite sheet).
local function PreloadStudioArt(parent)
    local states, names, files = {}, {}, {}
    for name in pairs(PS.StudioKit.assets) do
        if name:find("%-hover") or name:find("%-pressed") or name:find("%-selected") or name:find("%-disabled") then
            states[#states + 1] = name
        end
    end
    table.sort(states)
    for _, name in ipairs(states) do
        local file = Theme.Path(name)
        if not files[file] then
            files[file] = true
            names[#names + 1] = name
        end
    end
    local preload = {}
    for index, name in ipairs(names) do
        local texture = parent:CreateTexture(nil, "BACKGROUND")
        texture:SetSize(1, 1)
        texture:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        texture:SetAlpha(0)
        Theme.Set(texture, name)
        texture:Show()
        preload[index] = texture
    end
    return preload
end

-- The kit's close button (normal, hover and pressed art); the caller places it and sets its click.
local function CreateCloseButton(parent)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(31, 31)
    close.art = close:CreateTexture(nil, "ARTWORK")
    local function State(state) Theme.Place(close.art, "close-button-" .. state, close, 0, 0) end
    State("normal")
    close:SetScript("OnEnter", function() State("hover") end)
    close:SetScript("OnLeave", function() State("normal") end)
    close:SetScript("OnMouseDown", function() State("pressed") end)
    close:SetScript("OnMouseUp", function() State("hover") end)
    return close
end

-- Studio's dialogs (confirm, unsaved changes, Blueprints) in the kit's look: its dark panel with
-- the section frame instead of the flat window, a gold title, and the kit's close button.
local function DressStudioDialog(frame)
    if frame.studioDressed then return frame end
    frame.studioDressed = true
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    local art = CreatePanelArt(frame, "dark")
    frame.studioArt = art
    if frame.HookScript then frame:HookScript("OnSizeChanged", function() art:Layout() end) end
    art:Layout()
    if frame.title then
        frame.title:SetFont(FONT, 19)
        frame.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -18)
    end
    if frame.closeButton then
        frame.closeButton:Hide()
        local close = CreateCloseButton(frame)
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
        close:SetFrameLevel(frame:GetFrameLevel() + 25)
        close:SetScript("OnClick", function() frame:Hide() end)
        frame.closeButton = close
    end
    return frame
end

-- A dialog's message: centred across it, y below its top.
local function DialogText(dialog, y)
    local text = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetFont(FONT, 15)
    text:SetTextColor(0.93, 0.90, 0.84)
    text:SetPoint("TOPLEFT", dialog, "TOPLEFT", 26, -y)
    text:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -26, -y)
    text:SetJustifyH("CENTER")
    return text
end

-- A panel's art that follows its frame's size and Studio's relayouts (LayoutEditorArt).
local function TrackPanelArt(frame, kind)
    local art = CreatePanelArt(frame, kind)
    Options.editorPanelArt = Options.editorPanelArt or {}
    Options.editorPanelArt[#Options.editorPanelArt + 1] = art
    frame:SetScript("OnSizeChanged", function() art:Layout() end)
    return art
end

-- A show / hide eye (a tree row's, a group's, the inspector header's) with its tooltip. The click
-- handler is set before the skin, which hooks the click (SetScript afterwards would drop the hooks).
local function CreateVisibilityEye(parent, onClick, title, lines)
    local eye = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    PS.UI.Controls.StyleCheckbox(eye, 18)
    eye.visibilityEye = true
    eye:SetScript("OnClick", onClick)
    if title then PS.UI.Controls.AttachTooltip(eye, title, lines) end
    SkinCheckbox(eye)
    return eye
end

-- The footer's line of PlateSmith's own CPU cost: the client profiler's recent average per frame
-- and its share of a frame at the current frame rate. Its ticker entry runs only while it shows.
function Options:RefreshEditorCpuReadout()
    local readout = self.editorCpuReadout
    if not readout then return end
    if not readout:IsVisible() then
        PS.Ticker.SetEnabled(CPU_READOUT.ticker, false)
        return
    end
    local Performance = PS.Performance
    local ms, share
    if Performance and Performance.RecentCost then ms, share = Performance.RecentCost() end
    local text, over = L["PlateSmith CPU: no profiler data"], false
    if ms and share then
        text = string.format(L["PlateSmith %.2f ms · %.1f%% of frame"], ms, share)
    elseif ms then
        text = string.format(L["PlateSmith %.2f ms per frame"], ms)
    end
    local budget = PS.DiagnosticSummary and PS.DiagnosticSummary.frameBudgetMs
    if ms and budget then over = ms > budget end
    readout.text:SetText(text)
    if over then readout.text:SetTextColor(1, 0.45, 0.38)
    elseif ms then readout.text:SetTextColor(0.72, 0.70, 0.66)
    else readout.text:SetTextColor(0.50, 0.48, 0.45) end
    readout.lastText = text
end

PS.Ticker.Register(CPU_READOUT.ticker, CPU_READOUT.interval, function() Options:RefreshEditorCpuReadout() end)
PS.Ticker.SetEnabled(CPU_READOUT.ticker, false)

function Options:BuildEditorCpuReadout(editor, level)
    local readout = CreateFrame("Button", nil, editor)
    readout:SetFrameLevel(level)
    readout:SetSize(CPU_READOUT.width, CPU_READOUT.height)
    local text = readout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetFont(FONT, 12)
    text:SetJustifyH("RIGHT")
    text:SetPoint("RIGHT", readout, "RIGHT", 0, 0)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    if text.SetWordWrap then text:SetWordWrap(false) end
    readout.text = text
    readout:SetScript("OnShow", function()
        PS.Ticker.SetEnabled(CPU_READOUT.ticker, true)
        Options:RefreshEditorCpuReadout()
    end)
    readout:SetScript("OnHide", function() PS.Ticker.SetEnabled(CPU_READOUT.ticker, false) end)
    readout:SetScript("OnClick", function() PS.DiagnosticUI.ShowPerformance() end)
    PS.UI.Controls.AttachTooltip(readout, L["PlateSmith's CPU time"], {
        L["The time PlateSmith's code took per frame, on average over the last few seconds (the client's addon "
            .. "profiler), and that as a share of one frame at your current frame rate."],
        { string.format(L["Refreshed every %d s while Studio is open. Click for the live Performance view (/ps perf)."],
            CPU_READOUT.interval), 0.86, 0.86, 0.86 },
    })
    self.editorCpuReadout = readout
    return readout
end

-- Studio's frame skins the kit's controls as they are made inside it (Controls' skinControl);
-- Blizzard's Settings panel keeps its own look.
local SKINS = { checkbox = SkinCheckbox, slider = SkinSlider, dropdown = SkinDropdown }
local function SkinControl(control, kind)
    local skin = SKINS[kind]
    if skin then skin(control) end
end

Options.studioChrome = {
    DressStudioDialog = DressStudioDialog,
    DialogText = DialogText,
    CreateCloseButton = CreateCloseButton,
    SkinDropdown = SkinDropdown,
    SkinControl = SkinControl,
    SetStudioButtonState = SetStudioButtonState,
    CreateStudioButton = CreateStudioButton,
    CreateStudioScrollBar = CreateStudioScrollBar,
    CreatePanelArt = CreatePanelArt,
    CreateStageBackdrop = CreateStageBackdrop,
    TrackPanelArt = TrackPanelArt,
    CreateVisibilityEye = CreateVisibilityEye,
    CreateEditorShell = CreateEditorShell,
    PreloadStudioArt = PreloadStudioArt,
    SkinCheckbox = SkinCheckbox,
    INSPECTOR = INSPECTOR,
    FONT = FONT,
    LABEL = LABEL,
    GOLD = GOLD,
}
