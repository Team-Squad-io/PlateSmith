local _, PS = ...
local Controls = assert(PS.UI and PS.UI.Controls, "PlateSmith Controls missing")

-- The panel layout kit shared by Blueprint Studio's inspector and the Settings pages: one table
-- of spacing tokens (the panels' CSS) and builders spaced only by them. A row is a grid of
-- label | control | value columns; a section is a divider, a title band (with an optional action
-- at its right) and its items; a sub-heading and help are text blocks; a card is a padded box of
-- rows. A flow (kit.Flow) stacks whichever of its items is shown top to bottom with exactly one
-- token gap between neighbours, like CSS block flow: an item's flowBefore (or the one above's
-- flowAfter, else the flow's gap) is the space between them, a hidden item takes no space, and
-- a plain group passes its first and last items' gaps out, as CSS margins do. Inside a row
-- everything is centred on the row's middle line.
--
-- Items take their flow's width (anchored at both sides), and whatever ends at a row's right end
-- (a value, a slider, a dropdown, help) is anchored to that end, so a column laid out at WIDTH
-- also fills a wider one (the inspector without its scroll bar).
--
-- Layout.New(config) makes a kit for one panel column. config:
--   width        the column's width (required)
--   palette      a palette (Layout.PALETTES) or a function returning the current one
--   tokens       overrides and additions to Layout.TOKENS
--   button(parent, text, width, height, variant)   makes a button (default: Blizzard's)
--   fieldArt(edit)          draws a value box (returns art with Layout(); default: a dark fill)
--   segmentIcon(segment, which, size)   an arrow texture for a segment (default: its word)
--   register(kind, object)  told of each "segment", "card" and "section", to repaint them
--   revert()                Escape in a value box: put the panel's values back
--   collapsible             every section folds (Section's options.collapsible, for all)
--   sectionState            the table folded sections are kept in (key -> true while folded)
--   relayout()              lays the panel out again after a section folds or opens
--   chevron(texture, open)  draws a section's fold arrow (default: Blizzard's list arrows)
local Layout = {}
PS.UI.Layout = Layout

Layout.TOKENS = {
    ROW_H = 28, ROW_GAP = 6, CONTROL_H = 24, PAD_X = 16, PAD_TOP = 16, PAD_BOTTOM = 24,
    SECTION_TOP = 14, SECTION_RULE_GAP = 8, SECTION_TITLE_H = 26, SECTION_TITLE_GAP = 10, RULE_H = 1,
    SUB_TOP = 8, SUB_GAP = 4, CARD_PAD = 8, CARD_GAP = 8,
    LABEL_W = 96, VALUE_W = 40, CONTROL_GAP = 8,
    SWATCH = 18, SWATCH_GAP = 6, AXIS_W = 12, BUTTON_H = 26, SEGMENT_ICON = 16,
    CHEVRON = 14, CHEVRON_GAP = 6,
    -- A skinned checkbox is 26 px wide with its box 4 px in; a dropdown's field starts 16 px right
    -- of the x it is given and is 20 px wider than its width (Controls.Dropdown).
    CHECK_W = 26, CHECK_INSET = 4, CHECK_TEXT_GAP = 6, DROPDOWN_INSET = 16, DROPDOWN_PADDING = 20,
    LINE_H = 14, FONT = 12, SEGMENT_FONT = 11, FIELD_FONT = 12, FONT_PATH = "Fonts\\FRIZQT__.TTF",
}

-- Palettes: text ink by role (label, value, muted, title, sub, error, ok, hint), text shadow,
-- the section divider, cards, and segmented controls.
-- A line on parchment: #8a6f47 at 0.7 (the parchment's own edge colour vanished against it).
local PARCHMENT_LINE = { 0.541, 0.435, 0.278, 0.7 }
Layout.PALETTES = {
    -- Studio's parchment: dark ink.
    parchment = {
        ink = {
            label = { 0.17, 0.11, 0.06 },   -- #2b1d10: row labels, checkbox text, a part's name
            value = { 0.29, 0.22, 0.14 },   -- #4a3824: slider readings, member names
            muted = { 0.35, 0.27, 0.19 },   -- #5a4630: help, descriptions
            title = { 0.54, 0.17, 0.07 },   -- #8a2b12: section titles
            sub = { 0.42, 0.33, 0.21 },     -- #6b5335: sub-headings
            error = { 0.62, 0.08, 0.03 },
            ok = { 0.10, 0.40, 0.10 },
            hint = { 0.60, 0.55, 0.46 },    -- a placeholder inside a dark field
        },
        shadow = 0,
        divider = PARCHMENT_LINE,
        card = { fill = { 0.863, 0.796, 0.659, 1 }, edge = PARCHMENT_LINE }, -- #dccba8
        segment = { edge = { 0.42, 0.33, 0.21, 1 }, fill = { 0.086, 0.067, 0.047, 1 }, hover = { 0.17, 0.13, 0.09, 1 },
            chosen = { 0.48, 0.165, 0.078, 1 }, text = { 0.75, 0.68, 0.56 }, chosenText = { 0.965, 0.906, 0.77 },
            off = { 0.40, 0.35, 0.28 } },
    },
    -- Studio in high contrast: a dark panel, white text, gold titles.
    contrast = {
        ink = { label = { 1, 1, 1 }, value = { 0.92, 0.92, 0.9 }, muted = { 0.86, 0.86, 0.82 }, title = { 1, 0.86, 0.3 },
            sub = { 0.86, 0.86, 0.82 }, error = { 1, 0.5, 0.45 }, ok = { 0.55, 1, 0.55 }, hint = { 0.6, 0.6, 0.6 } },
        shadow = 1,
        divider = { 0.6, 0.6, 0.6, 1 },
        card = { fill = { 0.14, 0.14, 0.14, 1 }, edge = { 0.6, 0.6, 0.6, 1 } },
        segment = { edge = { 0.8, 0.8, 0.8, 1 }, fill = { 0.08, 0.08, 0.08, 1 }, hover = { 0.22, 0.22, 0.22, 1 },
            chosen = { 0.89, 0.75, 0.13, 1 }, text = { 1, 1, 1 }, chosenText = { 0, 0, 0 }, off = { 0.5, 0.5, 0.5 } },
    },
    -- Blizzard's own dark options panels: its standard font colours (highlight white labels,
    -- normal gold titles, grey help).
    blizzard = {
        ink = { label = { 1, 1, 1 }, value = { 1, 1, 1 }, muted = { 0.62, 0.62, 0.62 }, title = { 1, 0.82, 0 },
            sub = { 1, 0.82, 0 }, error = { 1, 0.1, 0.1 }, ok = { 0.1, 1, 0.1 }, hint = { 0.5, 0.5, 0.5 } },
        shadow = 1,
        divider = { 0.45, 0.45, 0.45, 0.8 },
        card = { fill = { 0, 0, 0, 0.35 }, edge = { 0.45, 0.45, 0.45, 0.8 } },
        segment = { edge = { 0.4, 0.4, 0.4, 1 }, fill = { 0.06, 0.06, 0.06, 1 }, hover = { 0.18, 0.18, 0.18, 1 },
            chosen = { 0.55, 0.42, 0.05, 1 }, text = { 1, 1, 1 }, chosenText = { 1, 1, 1 }, off = { 0.45, 0.45, 0.45 } },
    },
}

local function Paint(texture, colour) texture:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1) end

-- A hairline exactly one physical pixel tall at any UI scale (a 1-unit line vanished below 1).
local function Hairline(texture, fallback)
    local height = fallback
    if PixelUtil and PixelUtil.GetNearestPixelSize and texture.GetEffectiveScale then
        local ok, size = pcall(PixelUtil.GetNearestPixelSize, 1, texture:GetEffectiveScale(), 1)
        if ok and type(size) == "number" and size > 0 then height = size end
    end
    texture:SetHeight(height)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end
Layout.Hairline = Hairline

-- Blizzard's list arrows (its Settings category list), else the quest log's plus and minus.
local function DefaultChevron(texture, open)
    local atlas = open and "Options_ListExpand_Right_Expanded" or "Options_ListExpand_Right"
    if texture.SetAtlas and texture:SetAtlas(atlas) then return end
    texture:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
end

function Layout.New(config)
    local K = {}
    for key, value in pairs(Layout.TOKENS) do K[key] = value end
    for key, value in pairs(config.tokens or {}) do K[key] = value end
    K.WIDTH = assert(config.width, "Layout.New needs a width")
    K.CONTROL_X = K.LABEL_W + K.CONTROL_GAP
    K.VALUE_X = K.WIDTH - K.VALUE_W
    K.CONTROL_W = K.VALUE_X - K.CONTROL_GAP - K.CONTROL_X
    K.WIDE = K.WIDTH - K.CONTROL_X
    -- A table, or a function returning one (saved state that loads after the kit is made).
    local localState = {}
    local function Folds()
        local state = config.sectionState
        if type(state) == "function" then state = state() end
        return type(state) == "table" and state or localState
    end
    K.Folds = Folds
    local function Register(kind, object) if config.register then config.register(kind, object) end end
    -- An x measured from a row's left, as an offset from its right end (for right anchors).
    local function FromRight(x) return x - K.WIDTH end

    -- Width follows the flow explicitly (not through anchors), so art laid out for a size (a
    -- field's or a track's slices) is laid out again at once, on every client and in renders.
    -- fn(width) runs now at the row's width (WIDTH until a flow sizes it) and on every change.
    function K.OnWidth(row, fn)
        row.kitWidthFns = row.kitWidthFns or {}
        row.kitWidthFns[#row.kitWidthFns + 1] = fn
        fn(row.kitWidth or K.WIDTH)
    end
    local function SetItemWidth(frame, width)
        if not width or width <= 0 then return end
        frame:SetWidth(width)
        if frame.kitWidth == width then return end
        frame.kitWidth = width
        for _, fn in ipairs(frame.kitWidthFns or {}) do fn(width) end
    end
    K.SetItemWidth = SetItemWidth
    -- Sets a control's width and lays out its art for it.
    local function Resize(control, width)
        control:SetWidth(math.max(1, width))
        if control.kitField and control.kitField.Layout then control.kitField:Layout() end
        if control.kitTrack and control.kitTrack.Layout then control.kitTrack:Layout() end
    end
    -- control spans from x in row to margin (measured from the row's right end) as the row resizes.
    local function Span(row, control, x, margin)
        K.OnWidth(row, function(width) Resize(control, width - margin - x) end)
    end

    -- The palette now (a theme can change it; Paint and Ink read it each time).
    function K.Palette()
        local palette = config.palette
        if type(palette) == "function" then palette = palette() end
        return palette or Layout.PALETTES.parchment
    end

    -- Inks text by role, with the palette's shadow.
    function K.Ink(text, role)
        text.studioInk = role
        local palette = K.Palette()
        local colour = palette.ink[role] or palette.ink.label
        text:SetTextColor(colour[1], colour[2], colour[3], 1)
        if text.SetShadowColor then text:SetShadowColor(0, 0, 0, palette.shadow or 0) end
        return text
    end

    -- A line of inked text in parent, not yet placed (the caller anchors it).
    function K.Text(parent, text, role)
        local label = Controls.Label(parent, text, 0, 0, "GameFontHighlightSmall")
        label:ClearAllPoints()
        label:SetFont(K.FONT_PATH, K.FONT)
        label:SetJustifyH("LEFT")
        return K.Ink(label, role or "label")
    end

    -- Wrapped text in width: its measured height (a client that measures none: an estimate).
    function K.TextHeight(text, width)
        local height = text.GetStringHeight and text:GetStringHeight() or 0
        if height and height > 0 then return math.ceil(height) end
        local perLine = math.max(1, math.floor(width / (K.FONT * 0.5)))
        return math.max(1, math.ceil(#(text:GetText() or "") / perLine)) * K.LINE_H
    end
    local TextHeight = K.TextHeight

    function K.Flow(frame, gap)
        frame.flowItems, frame.flowGap = {}, gap
        return frame
    end

    -- visible(): whether the item shows now (nil: always).
    function K.Add(flow, frame, visible)
        flow.flowItems[#flow.flowItems + 1] = { frame = frame, visible = visible }
        return frame
    end

    -- The gap a frame asks above it (side "flowBefore") or below it ("flowAfter"); a plain group
    -- without its own passes out its first or last shown item's (a section or card has its own
    -- padding, so nothing inside it leaks out).
    local function Margin(frame, side)
        if frame[side] then return frame[side] end
        local edge = frame.flowTransparent and frame.flowEdges and frame.flowEdges[side]
        return edge and Margin(edge, side) or nil
    end
    K.Margin = Margin

    -- Places the flow's shown items from top (default 0) down; returns where the last one ends.
    -- An item with Measure() sizes itself (a nested flow, a section, wrapping text); the rest keep
    -- their height. A nested flow with nothing shown is hidden and takes no space. Each item
    -- spans the flow's width.
    function K.LayoutFlow(flow, top)
        local y, first, previous = top or 0, nil, nil
        local width = flow:GetWidth()
        for _, item in ipairs(flow.flowItems) do
            local frame = item.frame
            local shown = item.visible == nil or item.visible() and true or false
            local height = 0
            if shown then
                SetItemWidth(frame, width)
                height = frame.Measure and frame:Measure() or frame:GetHeight()
                if frame.flowItems and height <= 0 then shown = false end
            end
            frame:SetShown(shown)
            if shown then
                if previous then
                    y = y + (Margin(frame, "flowBefore") or Margin(previous, "flowAfter") or flow.flowGap or K.ROW_GAP)
                end
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", flow, "TOPLEFT", 0, -y)
                y = y + height
                first, previous = first or frame, frame
            end
        end
        flow.flowEdges = { flowBefore = first, flowAfter = previous }
        return y
    end

    -- A plain flow of items (a part of a section that shows or hides as one).
    function K.Group(parent, gap)
        local frame = K.Flow(CreateFrame("Frame", nil, parent), gap)
        frame:SetSize(K.WIDTH, 1)
        frame.flowTransparent = true
        function frame:Measure()
            local height = K.LayoutFlow(self, 0)
            self:SetHeight(math.max(1, height))
            return height
        end
        return frame
    end

    -- Whether a section is folded now (its key in the shared state).
    function K.IsFolded(key) return key ~= nil and Folds()[key] == true end
    function K.SetFolded(key, folded)
        if key == nil then return end
        Folds()[key] = folded and true or nil
        if config.relayout then config.relayout() end
    end

    -- A section: SECTION_TOP above its divider, then its title band, SECTION_TITLE_GAP, its items.
    -- options: collapsible (config.collapsible for every section), key (its fold state; default
    -- the title), summary() (shown at the band's right while folded). A foldable band is a
    -- button with a chevron before the title; the actions at its right keep their own clicks.
    -- Folded, the body is hidden and takes no space.
    function K.Section(parent, title, options)
        options = options or {}
        local section = K.Flow(CreateFrame("Frame", nil, parent))
        section:SetSize(K.WIDTH, 1)
        section.flowBefore = K.SECTION_TOP
        section.rule = section:CreateTexture(nil, "ARTWORK", nil, 7)
        section.rule:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
        section.rule:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
        section.rule:SetWidth(K.WIDTH)
        Hairline(section.rule, K.RULE_H)
        Paint(section.rule, K.Palette().divider)
        local collapsible = options.collapsible
        if collapsible == nil then collapsible = config.collapsible and true or false end
        local band = CreateFrame(collapsible and "Button" or "Frame", nil, section)
        band:SetHeight(K.SECTION_TITLE_H)
        band:SetWidth(K.WIDTH)
        band:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(K.RULE_H + K.SECTION_RULE_GAP))
        band:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -(K.RULE_H + K.SECTION_RULE_GAP))
        section.band = band
        section.title = K.Text(band, title, "title")
        section.title:SetPoint("LEFT", band, "LEFT", collapsible and K.CHEVRON + K.CHEVRON_GAP or 0, 0)
        section.foldKey = collapsible and (options.key or title) or nil
        section.summaryOf = options.summary
        if collapsible then
            section.chevron = band:CreateTexture(nil, "ARTWORK")
            section.chevron:SetSize(K.CHEVRON, K.CHEVRON)
            section.chevron:SetPoint("LEFT", band, "LEFT", 0, 0)
            section.summary = K.Text(band, "", "muted")
            section.summary:SetJustifyH("RIGHT")
            if section.summary.SetWordWrap then section.summary:SetWordWrap(false) end
            band:SetScript("OnClick", function()
                if PS.UI.Menu and PS.UI.Menu.PlaySound then PS.UI.Menu.PlaySound() end
                K.SetFolded(section.foldKey, not K.IsFolded(section.foldKey))
                section:RefreshHeader()
            end)
        end
        -- The chevron and, folded, the summary (left of the band's action, if it has one).
        function section:RefreshHeader()
            if not self.chevron then return end
            local folded = K.IsFolded(self.foldKey)
            if config.chevron then config.chevron(self.chevron, not folded) else DefaultChevron(self.chevron, not folded) end
            local text = folded and self.summaryOf and self.summaryOf() or ""
            self.summary:SetText(text)
            self.summary:ClearAllPoints()
            if self.accessory then
                self.summary:SetPoint("RIGHT", self.accessory, "LEFT", -K.CONTROL_GAP, 0)
            else
                self.summary:SetPoint("RIGHT", band, "RIGHT", 0, 0)
            end
            self.summary:SetShown(text ~= "")
        end
        local head = K.RULE_H + K.SECTION_RULE_GAP + K.SECTION_TITLE_H
        function section:Measure()
            self:RefreshHeader()
            if K.IsFolded(self.foldKey) then
                for _, item in ipairs(self.flowItems) do item.frame:Hide() end
                self.flowEdges = {}
                self:SetHeight(head)
                return head
            end
            local height = K.LayoutFlow(self, head + K.SECTION_TITLE_GAP)
            if not self.flowEdges.flowBefore then height = head end
            self:SetHeight(height)
            return height
        end
        function section:Paint() Paint(self.rule, K.Palette().divider) end
        section:RefreshHeader()
        Register("section", section)
        return section
    end

    -- The one action at the right of a section's title, on the title's middle line.
    function K.Accessory(section, frame)
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", section.band, "RIGHT", 0, 0)
        section.accessory = frame
        if section.RefreshHeader then section:RefreshHeader() end
        return frame
    end

    -- A sub-heading: SUB_TOP above it, SUB_GAP below, at the labels' size in its own ink.
    function K.SubHeader(parent, text)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(K.WIDTH, K.LINE_H)
        frame.flowBefore, frame.flowAfter = K.SUB_TOP, K.SUB_GAP
        frame.text = K.Text(frame, text, "sub")
        frame.text:SetPoint("LEFT", frame, "LEFT", 0, 0)
        return frame
    end

    -- A row: ROW_H tall, its label in the label column. inset (a card's padding) moves the label
    -- in and the row's right end (row.right) back; the control column stays where every row has it.
    function K.Row(parent, label, inset)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(K.WIDTH, K.ROW_H)
        row.inset = inset or 0
        row.right = K.WIDTH - row.inset
        if label then
            row.label = K.Text(row, label, "label")
            row.label:SetPoint("LEFT", row, "LEFT", row.inset, 0)
            row.label:SetWidth(K.LABEL_W - row.inset)
            if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        end
        return row
    end

    -- The row's value column: right-aligned at the row's right end, as every slider's reading.
    function K.Value(row)
        local text = K.Text(row, "", "value")
        text:SetWidth(K.VALUE_W)
        text:SetJustifyH("RIGHT")
        text:SetPoint("RIGHT", row, "RIGHT", FromRight(row.right), 0)
        return text
    end

    -- A slider in row from x (default: the control column) to the value column, its reading at
    -- the right; with no width given it stretches with the row.
    function K.Slider(row, spec, x)
        local stretch = spec.width == nil
        spec.x, spec.y = x or K.CONTROL_X, 0
        spec.width = spec.width or (row.right - K.VALUE_W - K.CONTROL_GAP - spec.x)
        spec.valueText, spec.captions = spec.valueText or K.Value(row), false
        spec.format = spec.format or Controls.PixelText
        local slider = Controls.Slider(row, spec)
        slider:ClearAllPoints()
        slider:SetPoint("LEFT", row, "LEFT", spec.x, 0)
        if stretch then Span(row, slider, spec.x, row.inset + K.VALUE_W + K.CONTROL_GAP) end
        return slider
    end

    function K.SliderRow(parent, label, spec)
        local row = K.Row(parent, label)
        row.control = K.Slider(row, spec)
        return row, row.control
    end

    -- A dropdown's field CONTROL_H tall from x to right in row (right measured from the row's
    -- left; the field's right end follows the row's).
    function K.FitDropdown(dropdown, row, x, right)
        dropdown:ClearAllPoints()
        dropdown:SetPoint("LEFT", row, "LEFT", x, 0)
        dropdown:SetSize(right - x, K.CONTROL_H)
        if dropdown.kitField then dropdown.kitField.fit = true end
        Span(row, dropdown, x, K.WIDTH - right)
        if dropdown.kitText then dropdown.kitText:SetFont(K.FONT_PATH, K.FIELD_FONT) end
        if dropdown.Text and not dropdown.kitText then dropdown.Text:SetFont(K.FONT_PATH, K.FIELD_FONT) end
    end

    -- A dropdown in row from x (default: the control column) to right (default: the row's end).
    function K.Dropdown(row, spec, x, right)
        x, right = x or K.CONTROL_X, right or row.right
        spec.x, spec.y, spec.width = x - K.DROPDOWN_INSET, 0, right - x - K.DROPDOWN_PADDING
        local dropdown = Controls.Dropdown(row, spec)
        K.FitDropdown(dropdown, row, x, right)
        return dropdown
    end

    -- A dropdown across the control and value columns.
    function K.DropdownRow(parent, label, spec)
        local row = K.Row(parent, label)
        row.control = K.Dropdown(row, spec)
        return row, row.control
    end

    -- A checkbox at the control column's start with its short label after it (spec.text), in
    -- every row alike; the row grows when the label wraps.
    function K.RowCheck(row, spec)
        spec.label, spec.x, spec.y = spec.text or "", K.CONTROL_X - K.CHECK_INSET, 0
        spec.labelTemplate = "GameFontHighlightSmall"
        local checkbox = Controls.Checkbox(row, spec)
        checkbox:ClearAllPoints()
        checkbox:SetPoint("LEFT", row, "LEFT", spec.x, 0)
        -- Its label belongs to the row (a check button owns and recolours text of its own).
        local text = checkbox.label
        if text.SetParent then text:SetParent(row) end
        text:SetFont(K.FONT_PATH, K.FONT)
        text:ClearAllPoints()
        text:SetPoint("LEFT", checkbox, "RIGHT", K.CHECK_TEXT_GAP, 0)
        local width = row.right - (spec.x + K.CHECK_W + K.CHECK_TEXT_GAP)
        text:SetWidth(width)
        K.OnWidth(row, function(rowWidth)
            width = rowWidth - row.inset - (spec.x + K.CHECK_W + K.CHECK_TEXT_GAP)
            text:SetWidth(width)
        end)
        text:SetJustifyH("LEFT")
        if text.SetWordWrap then text:SetWordWrap(true) end
        K.Ink(text, "label")
        function row:Measure()
            local height = math.max(K.ROW_H, (text:GetText() or "") == "" and 0 or TextHeight(text, width))
            self:SetHeight(height)
            return height
        end
        row.control = checkbox
        return checkbox
    end

    function K.CheckRow(parent, label, spec)
        local row = K.Row(parent, label, spec.inset)
        return row, K.RowCheck(row, spec)
    end

    -- A colour row: the swatch starts the label column, its label after it, so the row's slider
    -- (spec.alpha = true: its opacity) lines up with every other slider.
    function K.SwatchRow(parent, label, spec)
        local row = K.Row(parent, nil, spec.inset)
        spec.x, spec.y, spec.size = row.inset, 0, K.SWATCH
        if spec.alpha then
            spec.alpha = { x = K.CONTROL_X, y = 0, width = row.right - K.VALUE_W - K.CONTROL_GAP - K.CONTROL_X,
                valueX = 0, valueWidth = K.VALUE_W, captions = false }
        end
        local swatch = Controls.ColourSwatch(row, spec)
        swatch:ClearAllPoints()
        swatch:SetPoint("LEFT", row, "LEFT", row.inset, 0)
        if label then
            row.label = K.Text(row, label, "label")
            row.label:SetPoint("LEFT", row, "LEFT", row.inset + K.SWATCH + K.SWATCH_GAP, 0)
        end
        local slider = swatch.alphaSlider
        if slider then
            slider:ClearAllPoints()
            slider:SetPoint("LEFT", row, "LEFT", K.CONTROL_X, 0)
            Span(row, slider, K.CONTROL_X, row.inset + K.VALUE_W + K.CONTROL_GAP)
            local value = slider.valueText
            value:ClearAllPoints()
            value:SetPoint("RIGHT", row, "RIGHT", FromRight(row.right), 0)
            K.Ink(value, "value")
        end
        row.control = swatch
        return row, swatch
    end

    -- Help: muted text wrapped across the column (from x, default 0: the control column puts it
    -- under its control); it measures its own height.
    function K.Help(parent, text, x)
        x = x or 0
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(K.WIDTH, K.LINE_H)
        local label = K.Text(frame, text, "muted")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        label:SetWidth(K.WIDTH - x)
        if label.SetWordWrap then label:SetWordWrap(true) end
        frame.text = label
        function frame:Measure()
            local width = (self.kitWidth or K.WIDTH) - x
            label:SetWidth(width)
            local height = TextHeight(label, width)
            self:SetHeight(height)
            return height
        end
        return frame
    end

    -- Help under the control of the row above it: in the control column, ROW_GAP / 2 below.
    function K.ControlHelp(parent, text)
        local help = K.Help(parent, text, K.CONTROL_X)
        help.flowBefore = math.floor(K.ROW_GAP / 2)
        return help
    end

    -- A row of mutually exclusive choices, equal widths from the control column. spec: choices
    -- ({ value, label, icon, tooltip }; icon "left", "right", "top" or "bottom" draws that arrow
    -- through config.segmentIcon), get, set, enabled(value) (a segment it refuses keeps its fill
    -- with its word or arrow dimmed, and its tooltip adds spec.disabledTip), name, x, width
    -- (default: to the row's end, following it).
    function K.Segmented(parent, spec)
        local control = CreateFrame("Frame", spec.name, parent)
        local count = #spec.choices
        control:SetPoint("LEFT", parent, "LEFT", spec.x or K.CONTROL_X, 0)
        control.segments = {}
        for index, choice in ipairs(spec.choices) do
            local segment = CreateFrame("Button", nil, control)
            segment.edge = segment:CreateTexture(nil, "BACKGROUND")
            segment.edge:SetAllPoints(segment)
            segment.fill = segment:CreateTexture(nil, "ARTWORK")
            segment.fill:SetPoint("TOPLEFT", segment, "TOPLEFT", K.RULE_H, -K.RULE_H)
            segment.fill:SetPoint("BOTTOMRIGHT", segment, "BOTTOMRIGHT", -K.RULE_H, K.RULE_H)
            segment.label = segment:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            segment.label:SetFont(K.FONT_PATH, K.SEGMENT_FONT)
            segment.label:SetPoint("CENTER", segment, "CENTER", 0, 0)
            segment.label:SetText(choice.label)
            if segment.label.SetShadowColor then segment.label:SetShadowColor(0, 0, 0, 0) end
            segment.icon = choice.icon and config.segmentIcon and config.segmentIcon(segment, choice.icon, K.SEGMENT_ICON)
            if segment.icon then segment.label:Hide() end
            segment.value = choice.value
            -- A refused segment still explains itself on hover.
            if segment.SetMotionScriptsWhileDisabled then segment:SetMotionScriptsWhileDisabled(true) end
            segment:SetScript("OnClick", function(instance)
                if instance:IsEnabled() and spec.get() ~= choice.value then spec.set(choice.value) end
            end)
            segment:SetScript("OnEnter", function(instance)
                instance.hover = true
                control:Paint()
                if not GameTooltip then return end
                GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
                GameTooltip:SetText(choice.tooltip or choice.label)
                if not instance:IsEnabled() and spec.disabledTip then
                    GameTooltip:AddLine(spec.disabledTip, 1, 0.82, 0.45, true)
                end
                GameTooltip:Show()
            end)
            segment:SetScript("OnLeave", function(instance)
                instance.hover = false
                control:Paint()
                if GameTooltip then GameTooltip:Hide() end
            end)
            control.segments[index] = segment
        end
        -- Neighbours share their 1 px edge, so every segment is the same width.
        function control:Resize(width)
            local each = math.floor((width + count - 1) / count)
            self:SetSize(each * count - (count - 1), K.CONTROL_H)
            for index, segment in ipairs(self.segments) do
                segment:ClearAllPoints()
                segment:SetPoint("TOPLEFT", self, "TOPLEFT", (index - 1) * (each - 1), 0)
                segment:SetSize(each, K.CONTROL_H)
            end
        end
        if spec.width then
            control:Resize(spec.width)
        else
            local inset = parent.inset or 0
            K.OnWidth(parent, function(width) control:Resize(width - inset - (spec.x or K.CONTROL_X)) end)
        end
        function control:Paint()
            local ink = K.Palette().segment
            local current = spec.get()
            for _, segment in ipairs(self.segments) do
                local chosen, enabled = segment.value == current, segment:IsEnabled()
                Paint(segment.edge, ink.edge)
                Paint(segment.fill, chosen and ink.chosen or (segment.hover and enabled) and ink.hover or ink.fill)
                local text = chosen and ink.chosenText or enabled and ink.text or ink.off
                segment.label:SetTextColor(text[1], text[2], text[3])
                if segment.icon then segment.icon:SetVertexColor(text[1], text[2], text[3], 1) end
            end
        end
        function control:Refresh()
            for _, segment in ipairs(self.segments) do
                segment:SetEnabled(not spec.enabled or spec.enabled(segment.value) and true or false)
            end
            self:Paint()
        end
        Register("segment", control)
        return control
    end

    -- A value box CONTROL_H tall from x in row, width wide (config.fieldArt draws it); one that
    -- reaches the row's end follows it. Enter or leaving the box commits (onCommit(edit)); Escape
    -- puts the panel's values back (config.revert).
    function K.ValueBox(row, x, width, onCommit, maxLetters)
        local edit = Controls.EditBox(row, { width = width, height = K.CONTROL_H, fontSize = K.FIELD_FONT,
            colour = { 0.87, 0.85, 0.81 }, insets = { K.CARD_PAD, K.CARD_PAD }, maxLetters = maxLetters,
            fill = not config.fieldArt and { 0.06, 0.05, 0.04, 0.92 } or nil })
        edit:SetPoint("LEFT", row, "LEFT", x, 0)
        if config.fieldArt then
            edit.kitField = config.fieldArt(edit)
            edit:SetScript("OnSizeChanged", function() edit.kitField:Layout() end)
            edit.kitField:Layout()
        end
        if row.right and x + width >= row.right - 0.5 then Span(row, edit, x, row.inset) end
        -- Enter commits and lets go; the focus loss that follows does not commit again.
        edit:SetScript("OnEnterPressed", function()
            onCommit(edit)
            edit.committed = true
            edit:ClearFocus()
        end)
        edit:SetScript("OnEditFocusGained", function() edit.committed = nil end)
        edit:SetScript("OnEditFocusLost", function()
            if edit.committed then edit.committed = nil return end
            onCommit(edit)
        end)
        edit:SetScript("OnEscapePressed", function()
            edit.committed = true
            edit:ClearFocus()
            if config.revert then config.revert() end
        end)
        return edit
    end

    -- Offset X and Y on one row: two value boxes, each half the control column, that commit together.
    function K.OffsetRow(parent, label, onCommit)
        local row = K.Row(parent, label)
        local axes = {}
        for index, axis in ipairs({ "X", "Y" }) do
            axes[index] = K.Text(row, axis, "label")
            row[axis:lower()] = K.ValueBox(row, K.CONTROL_X, K.AXIS_W, onCommit, 5)
        end
        K.OnWidth(row, function(width)
            local half = math.floor((width - K.CONTROL_X - K.CONTROL_GAP) / 2)
            for index, axis in ipairs({ "x", "y" }) do
                local x = K.CONTROL_X + (index - 1) * (half + K.CONTROL_GAP)
                axes[index]:ClearAllPoints()
                axes[index]:SetPoint("LEFT", row, "LEFT", x, 0)
                local box = row[axis]
                box:ClearAllPoints()
                box:SetPoint("LEFT", row, "LEFT", x + K.AXIS_W, 0)
                Resize(box, half - K.AXIS_W)
            end
        end)
        return row
    end

    -- A card: a flow of rows on the palette's card fill with a 1 px edge, CARD_PAD inside it and
    -- CARD_GAP above it. Its rows take kit.Row(card, label, kit.CARD_PAD).
    function K.Card(parent)
        local card = K.Flow(CreateFrame("Frame", nil, parent, "BackdropTemplate"))
        card:SetSize(K.WIDTH, K.CARD_PAD * 2)
        card.flowBefore = K.CARD_GAP
        if card.SetBackdrop then
            card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = K.RULE_H })
        end
        function card:Paint()
            if not self.SetBackdropColor then return end
            local colours = K.Palette().card
            self:SetBackdropColor(colours.fill[1], colours.fill[2], colours.fill[3], colours.fill[4])
            self:SetBackdropBorderColor(colours.edge[1], colours.edge[2], colours.edge[3], colours.edge[4])
        end
        card:Paint()
        function card:Measure()
            local height = K.LayoutFlow(self, K.CARD_PAD) + K.CARD_PAD
            self.cardHeight = height
            self:SetHeight(height)
            return height
        end
        Register("card", card)
        return card
    end

    local function MakeButton(row, text, width, variant)
        if config.button then return config.button(row, text, width, K.BUTTON_H, variant) end
        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(width, K.BUTTON_H)
        button:SetText(text)
        return button
    end

    -- A button at the start of its own row, or across it (width nil).
    function K.ButtonRow(parent, text, width, variant, x)
        local row = K.Row(parent, nil)
        local button = MakeButton(row, text, width or K.WIDTH, variant)
        button:SetPoint("LEFT", row, "LEFT", x or 0, 0)
        if not width then K.OnWidth(row, function(rowWidth) button:SetWidth(rowWidth - (x or 0)) end) end
        row.button = button
        return row, button
    end

    -- Buttons side by side, CONTROL_GAP apart, from the control column (from the row's start when
    -- the row has no label). buttons: { { text, width, onClick }, ... }; returns the row and them.
    function K.ButtonsRow(parent, label, buttons)
        local row = K.Row(parent, label)
        local x, made = label and K.CONTROL_X or 0, {}
        for index, spec in ipairs(buttons) do
            local button = MakeButton(row, spec[1], spec[2])
            button:SetPoint("LEFT", row, "LEFT", x, 0)
            if spec[3] then button:SetScript("OnClick", spec[3]) end
            x = x + spec[2] + K.CONTROL_GAP
            made[index] = button
        end
        row.buttons = made
        return row, made
    end

    return K
end
