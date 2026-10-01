local _, PS = ...

-- One control kit for the Settings page and Blueprint Studio. Each control is
-- bound to a value with get() and set(value); Refresh() reads get() without
-- firing set(), so programmatic updates never write settings back.
PS.UI = PS.UI or {}
local Controls = {}
PS.UI.Controls = Controls

local FLAT = "Interface\\Buttons\\WHITE8X8"
local L = PS.L

-- Value captions: a 0-1 ratio as a percentage, and whole pixels or points.
function Controls.PercentText(ratio) return string.format(L["%d%%"], math.floor(ratio * 100 + 0.5)) end
function Controls.PixelText(value) return string.format(L["%d px"], value) end
function Controls.PointText(value) return string.format(L["%d pt"], value) end

-- A frame (or one of its parents) may skin the kit's controls as they are made:
-- skinControl(control, kind) with kind "checkbox", "slider" or "dropdown".
local function Skin(parent, control, kind)
    while parent do
        if parent.skinControl then return parent.skinControl(control, kind) end
        parent = parent.GetParent and parent:GetParent()
    end
end

-- A Studio surface can set its label sizes (studioLabelSize = { normal, small }); a light
-- surface also collects its labels (studioInkLabels) so the theme can ink them.
local function StudioSurface(parent)
    while parent do
        if parent.studioLabelSize or parent.studioInkLabels then return parent end
        parent = parent.GetParent and parent:GetParent()
    end
end

local function RegisterSurfaceLabel(parent, label, small)
    local surface = StudioSurface(parent)
    if not surface then return end
    local size = surface.studioLabelSize or { 16, 14 }
    label.studioFontSize = small and size[2] or size[1]
    label:SetFont("Fonts\\FRIZQT__.TTF", small and size[2] or size[1])
    -- Light text on Studio's dark panels gets the same drop shadow as its buttons and tree;
    -- inked labels on parchment have none (the theme sets it).
    if label.SetShadowColor then
        label:SetShadowColor(0, 0, 0, surface.studioInkLabels and 0 or 1)
        label:SetShadowOffset(1, -1)
    end
    if surface.studioInkLabels then
        local colour = label.GetTextColor and { label:GetTextColor() } or { 1, 0.82, 0.45, 1 }
        surface.studioInkLabels[#surface.studioInkLabels + 1] = { label = label, colour = colour }
    end
end

function Controls.Label(parent, text, x, y, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    RegisterSurfaceLabel(parent, label, template == "GameFontNormalSmall" or template == "GameFontHighlightSmall")
    return label
end

-- title plus lines; each line is text or { text, r, g, b }.
function Controls.AttachTooltip(owner, title, lines)
    local function Show(instance)
        if not GameTooltip then return end
        GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines or {}) do
            if type(line) == "table" then
                GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 0.82, line[4] or 0.45, true)
            else
                GameTooltip:AddLine(line, 1, 0.82, 0.45, true)
            end
        end
        GameTooltip:Show()
    end
    local function Hide() if GameTooltip then GameTooltip:Hide() end end
    if owner.HookScript then
        owner:HookScript("OnEnter", Show)
        owner:HookScript("OnLeave", Hide)
    else
        owner:SetScript("OnEnter", Show)
        owner:SetScript("OnLeave", Hide)
    end
    return Show, Hide
end

function Controls.StyleCheckbox(checkbox, size)
    -- The template's own box draws as a solid square behind ours unless it is hidden too.
    checkbox:SetSize(size + 6, size + 6)
    checkbox:SetNormalTexture("")
    checkbox:SetPushedTexture("")
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
        local texture = checkbox[getter] and checkbox[getter](checkbox)
        if texture and texture.SetAlpha then texture:SetAlpha(0) end
    end
    local box = checkbox:CreateTexture(nil, "BACKGROUND")
    box:SetSize(size, size)
    box:SetPoint("CENTER")
    -- A two-pixel steel rim, so an unticked box still reads as a box on dark surfaces.
    box:SetColorTexture(0.72, 0.64, 0.46, 1)
    local fill = checkbox:CreateTexture(nil, "BORDER")
    fill:SetSize(size-4, size-4)
    fill:SetPoint("CENTER")
    fill:SetColorTexture(0.13, 0.11, 0.08, 1)
    local check = checkbox:CreateTexture(nil, "OVERLAY")
    check:SetSize(size, size)
    check:SetPoint("CENTER")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkbox:SetCheckedTexture(check)
    checkbox.studioBox, checkbox.studioFill = box, fill
end

-- A mixed box (it stands for several values that differ): a short bar in place of the tick. The
-- box reads unticked underneath, so a click ticks it.
local function AddMixedLook(checkbox, spec)
    local mark = checkbox:CreateTexture(nil, "OVERLAY")
    mark:SetSize(10, 3)
    mark:SetPoint("CENTER")
    mark:SetColorTexture(1, 0.82, 0.2, 1)
    mark:Hide()
    checkbox.mixedMark = mark
    if not spec.mixedTip then return end
    local function Show(instance)
        if not instance.mixed or not GameTooltip then return end
        GameTooltip:SetOwner(instance, "ANCHOR_RIGHT")
        GameTooltip:SetText(spec.label or "")
        GameTooltip:AddLine(spec.mixedTip, 1, 0.82, 0.45, true)
        GameTooltip:Show()
    end
    local function Hide(instance) if instance.mixed and GameTooltip then GameTooltip:Hide() end end
    local hook = checkbox.HookScript and "HookScript" or "SetScript"
    checkbox[hook](checkbox, "OnEnter", Show)
    checkbox[hook](checkbox, "OnLeave", Hide)
end

-- spec: label, x, y, get, set, name, labelTemplate, tooltip = { title, lines }; mixed(), when
-- given, true shows the mixed look (and spec.mixedTip in the tooltip); clicking it sets true.
function Controls.Checkbox(parent, spec)
    local checkbox = CreateFrame("CheckButton", spec.name, parent, "UICheckButtonTemplate")
    Controls.StyleCheckbox(checkbox, 18)
    checkbox:SetPoint("TOPLEFT", spec.x or 0, spec.y or 0)
    local text = checkbox:CreateFontString(nil, "ARTWORK", spec.labelTemplate or "GameFontHighlight")
    text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    text:SetText(spec.label or "")
    RegisterSurfaceLabel(parent, text, spec.labelTemplate == "GameFontHighlightSmall")
    checkbox.label = text
    checkbox:SetScript("OnClick", function(instance)
        if instance.refreshing then return end
        if instance.mixedMark then
            instance.mixed = false
            instance.mixedMark:Hide()
        end
        spec.set(instance:GetChecked() and true or false)
    end)
    function checkbox:Refresh()
        self.refreshing = true
        local mixed = spec.mixed and spec.mixed() and true or false
        self.mixed = mixed
        self:SetChecked(not mixed and spec.get() and true or false)
        if self.mixedMark then self.mixedMark:SetShown(mixed) end
        self.refreshing = false
    end
    if spec.tooltip then Controls.AttachTooltip(checkbox, spec.tooltip.title or spec.label, spec.tooltip.lines) end
    Skin(parent, checkbox, "checkbox")
    -- After the skin, so the bar draws over its box and its hover hooks stay.
    if spec.mixed then AddMixedLook(checkbox, spec) end
    return checkbox
end

-- spec: label, min, max, step, x, y, width, format(value), get, set, name; captions = false
-- leaves out the range captions under the track's ends (the value alone reads at its right).
function Controls.Slider(parent, spec)
    local width = spec.width or 230
    local format = spec.format or tostring
    local titleLabel = spec.label and Controls.Label(parent, spec.label, spec.x, spec.y)
    local valueText = spec.valueText
    if not valueText then
        valueText = Controls.Label(parent, "", spec.x + width - 30, spec.y, "GameFontHighlightSmall")
        valueText:SetJustifyH("RIGHT")
    end
    local slider = CreateFrame("Slider", spec.name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", spec.x, spec.y - (spec.label and 22 or 0))
    slider:SetSize(width, 17)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(spec.min, spec.max)
    slider:SetValueStep(spec.step)
    slider:SetObeyStepOnDrag(true)
    slider.valueText = valueText
    slider.titleLabel = titleLabel
    for _, endpoint in ipairs({ { "Low", spec.min, "BOTTOMLEFT" }, { "High", spec.max, "BOTTOMRIGHT" } }) do
        local label = slider[endpoint[1]] or (spec.name and _G[spec.name .. endpoint[1]])
        if spec.captions == false then
            if label then
                label:SetText("")
                label:Hide()
            end
        else
            if not label then
                label = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                label:SetPoint(endpoint[3] == "BOTTOMLEFT" and "TOPLEFT" or "TOPRIGHT", slider, endpoint[3], 0, -2)
            end
            label:SetText(format(endpoint[2]))
            RegisterSurfaceLabel(parent, label, true)
            slider[endpoint[1]] = label
        end
    end
    -- Without captions, the template's own text (its Low, High and title strings, which an
    -- unnamed slider cannot reach by name) stays empty and hidden too.
    if spec.captions == false and slider.GetRegions then
        for _, region in ipairs({ slider:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                region:SetText("")
                region:Hide()
            end
        end
    end
    -- While dragged, the slider writes only when its stepped value changes, and refreshes leave
    -- its thumb to the pointer (setting it back mid-drag made it stutter). spec.drag(value)
    -- replaces spec.set while dragging when given; letting go writes through spec.set.
    slider:SetScript("OnValueChanged", function(instance, value)
        if instance.refreshing then return end
        value = math.floor(value / spec.step + 0.5) * spec.step
        if instance.dragging and instance.lastWritten == value then return end
        instance.lastWritten = value
        local write = instance.dragging and spec.drag or spec.set
        if write(value) ~= false then valueText:SetText(format(value)) end
    end)
    slider:HookScript("OnMouseDown", function(instance)
        instance.dragging, instance.lastWritten = true, nil
    end)
    slider:HookScript("OnMouseUp", function(instance)
        if not instance.dragging then return end
        instance.dragging = false
        if spec.drag then
            local value = math.floor((instance:GetValue() or 0) / spec.step + 0.5) * spec.step
            instance.lastWritten = value
            if spec.set(value) ~= false then valueText:SetText(format(value)) end
        end
    end)
    function slider:Refresh()
        local value = spec.get()
        if type(value) ~= "number" then return end
        if not self.dragging then
            self.refreshing = true
            self:SetValue(value)
            self.refreshing = false
        end
        valueText:SetText(format(value))
    end
    Skin(parent, slider, "slider")
    return slider
end

-- A field that opens PS.UI.Menu under it, as wide as the field. Clicking anywhere on the field
-- opens or closes the menu; the menu closes on Escape, on a click elsewhere and when the field
-- hides. spec: name, width, height, items() -> Menu items, minMenuWidth (a narrow field's menu
-- is at least this wide, so its items are not cut short). field.Text is its font string (named
-- "<name>Text" for scripts that look it up by name); field:SetText/GetText set and read it.
local PLAIN = { fill = { 0, 0, 0, 0.5 }, edge = { 0.35, 0.35, 0.35, 1 }, hover = { 0.75, 0.75, 0.75, 1 } }
function Controls.MenuField(parent, spec)
    local field = CreateFrame("Button", spec.name, parent, "BackdropTemplate")
    field:SetSize(spec.width or 200, spec.height or 24)
    if field.SetBackdrop then field:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 }) end
    local text = field:CreateFontString(spec.name and (spec.name .. "Text") or nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", field, "LEFT", 8, 0)
    text:SetPoint("RIGHT", field, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    field.Text = text
    local arrow = field:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetSize(20, 20)
    arrow:SetPoint("RIGHT", field, "RIGHT", -2, 0)
    field.arrow = arrow
    -- The plain look (a skin replaces PaintState and hides the arrow).
    function field:PaintState(state)
        if not self.SetBackdropColor then return end
        local edge = state == "hover" and PLAIN.hover or PLAIN.edge
        self:SetBackdropColor(PLAIN.fill[1], PLAIN.fill[2], PLAIN.fill[3], PLAIN.fill[4])
        self:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
    end
    function field:SetText(value) text:SetText(value or "") end
    function field:GetText() return text:GetText() end
    function field:MenuItems() return spec.items() end
    function field:ToggleMenu()
        local width = math.max(self:GetWidth(), spec.minMenuWidth or 0)
        return PS.UI.Menu.Toggle(self, function() return self:MenuItems() end, { width = width })
    end
    function field:OnMenuClosed() self:PaintState(self.IsMouseOver and self:IsMouseOver() and "hover" or "normal") end
    field:SetScript("OnClick", function(instance) instance:ToggleMenu() end)
    field:HookScript("OnEnter", function(instance) instance:PaintState("hover") end)
    field:HookScript("OnLeave", function(instance)
        if not PS.UI.Menu.IsOpenFor(instance) then instance:PaintState("normal") end
    end)
    field:PaintState("normal")
    return field
end

-- spec: label, choices (array of { value, label, help, children } or a function returning one),
-- x, y, width, get, set, name, placeholder, help (adds a "?" button and hover text). A choice's
-- children (choices too) open beside it; the choice's own value, if any, is set by clicking it.
-- The field starts 16 px right of x and is width + 20 wide (where Blizzard's dropdown drew its
-- field), so callers keep their coordinates.
function Controls.Dropdown(parent, spec)
    local function Choices() return type(spec.choices) == "function" and spec.choices() or spec.choices end
    -- The label sits clear of the field: at Studio's larger label sizes it moves up (not the
    -- field down, so nothing below shifts).
    local labelLift, titleLabel = 0, nil
    if spec.label then
        local label = Controls.Label(parent, spec.label, spec.x + 16, spec.y)
        titleLabel = label
        labelLift = math.max(0, math.floor((label.studioFontSize or 12) - 10))
        if labelLift > 0 then
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", spec.x + 16, spec.y + labelLift)
        end
    end
    local dropdown
    local function Items(choices, current)
        local items = {}
        for _, choice in ipairs(choices) do
            local selected = choice
            local item = { text = selected.label, checked = selected.value ~= nil and current == selected.value }
            if selected.help then item.tooltip = { title = selected.label, text = selected.help } end
            if selected.value ~= nil then
                item.func = function()
                    spec.set(selected.value)
                    dropdown:Refresh()
                end
            end
            if selected.children then
                item.children = Items(selected.children, current)
                for _, child in ipairs(item.children) do item.checked = item.checked or child.checked end
            end
            items[#items + 1] = item
        end
        return items
    end
    dropdown = Controls.MenuField(parent, { name = spec.name, width = (spec.width or 180) + 20, height = 24,
        items = function() return Items(Choices(), spec.get()) end })
    dropdown.plateSmithDropdown = true
    dropdown.labelLift = labelLift
    dropdown.titleLabel = titleLabel
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x + 16, spec.y - (spec.label and 22 or 4))
    local function Find(choices, current)
        for _, choice in ipairs(choices) do
            if choice.value ~= nil and choice.value == current then return choice end
            local child = choice.children and Find(choice.children, current)
            if child then return choice.value == nil and choice or child end
        end
    end
    function dropdown:Refresh()
        local choices = Choices()
        local found = Find(choices, spec.get())
        self:SetText(found and found.label or spec.placeholder or (choices[1] and choices[1].label) or "")
    end
    if spec.help then
        local lines = { spec.help }
        for _, choice in ipairs(Choices()) do
            if choice.help then lines[#lines + 1] = { choice.label .. ": " .. choice.help, 0.86, 0.86, 0.86 } end
        end
        Controls.AttachTooltip(dropdown, spec.label or "", lines)
        local helpButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        helpButton:SetPoint("LEFT", dropdown, "RIGHT", 8, 0)
        helpButton:SetSize(18, 18)
        helpButton:SetText("?")
        Controls.AttachTooltip(helpButton, spec.label or "", lines)
        dropdown.helpButton = helpButton
    end
    Skin(parent, dropdown, "dropdown")
    return dropdown
end

-- A plain edit box. spec: x, y (TOPLEFT in parent), width, height, fontSize, colour { r, g, b },
-- fill and rule ({ r, g, b, a }: a background, and a line along its foot), insets
-- { left, right, top, bottom }, maxLetters, multiLine.
function Controls.EditBox(parent, spec)
    local edit = CreateFrame("EditBox", nil, parent)
    if spec.x then edit:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x, spec.y or 0) end
    edit:SetSize(spec.width or 100, spec.height or 24)
    edit:SetAutoFocus(false)
    if spec.multiLine then edit:SetMultiLine(true) end
    edit:SetFont("Fonts\\FRIZQT__.TTF", spec.fontSize or 14, "")
    local colour = spec.colour or { 0.95, 0.93, 0.88 }
    edit:SetTextColor(colour[1], colour[2], colour[3])
    if spec.maxLetters and edit.SetMaxLetters then edit:SetMaxLetters(spec.maxLetters) end
    local insets = spec.insets
    if insets and edit.SetTextInsets then edit:SetTextInsets(insets[1], insets[2], insets[3] or 0, insets[4] or 0) end
    if spec.fill then
        edit.fill = edit:CreateTexture(nil, "BACKGROUND")
        edit.fill:SetAllPoints(edit)
        edit.fill:SetColorTexture(spec.fill[1], spec.fill[2], spec.fill[3], spec.fill[4] or 1)
    end
    if spec.rule then
        edit.rule = edit:CreateTexture(nil, "BORDER")
        edit.rule:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", 0, 0)
        edit.rule:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, 0)
        edit.rule:SetHeight(1)
        edit.rule:SetColorTexture(spec.rule[1], spec.rule[2], spec.rule[3], spec.rule[4] or 1)
    end
    return edit
end

-- Opens Blizzard's colour picker; apply(r, g, b) runs on every change and on
-- cancel with the original colour, so callers need a single write path.
-- The picker opens on the current colour. It can call back while it is being set up, before
-- it holds that colour (it read as black and replaced the colour on every click), so calls
-- made during setup are ignored: nothing has been picked yet.
function Controls.OpenColourPicker(colour, apply, cancel)
    if not ColorPickerFrame or not colour then return false end
    local previous = { r = colour.r or 1, g = colour.g or 1, b = colour.b or 1 }
    local opening = true
    local function Apply()
        if opening or not ColorPickerFrame.GetColorRGB then return end
        local r, g, b = ColorPickerFrame:GetColorRGB()
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
        apply(r, g, b)
    end
    local function Cancel()
        if cancel then cancel(previous) else apply(previous.r, previous.g, previous.b) end
    end
    if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
        ColorPickerFrame:SetupColorPickerAndShow({ r = previous.r, g = previous.g, b = previous.b,
            swatchFunc = Apply, cancelFunc = Cancel })
    else
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Apply, Cancel
        if ColorPickerFrame.SetColorRGB then ColorPickerFrame:SetColorRGB(previous.r, previous.g, previous.b) end
        ColorPickerFrame:Show()
    end
    opening = false
    return true
end

-- spec: x, y, size, label, get -> { r, g, b[, a] }, set(r, g, b[, a]), cancel(previous),
-- beforeOpen() to capture related state, name. alpha = { x, y, width, valueX, valueY,
-- valueWidth, captions } adds an opacity slider at those places in parent: picking a colour keeps the
-- opacity, the slider keeps the colour; drag(r, g, b, a), when given, takes the slider's steps
-- while it is dragged.
function Controls.ColourSwatch(parent, spec)
    local swatch = CreateFrame("Button", spec.name, parent, "BackdropTemplate")
    swatch:SetPoint("TOPLEFT", spec.x or 0, spec.y or 0)
    swatch:SetSize(spec.size or 24, spec.size or 24)
    swatch:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    swatch:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    if spec.label then Controls.Label(parent, spec.label, (spec.x or 0) + 34, (spec.y or 0) - 5) end
    local function Alpha()
        local colour = spec.get()
        return colour and colour.a or 1
    end
    local set = spec.set
    if spec.alpha then
        set = function(r, g, b) return spec.set(r, g, b, Alpha()) end
        local function WithAlpha(write)
            return function(a)
                local colour = spec.get()
                if not colour then return false end
                return write(colour.r, colour.g, colour.b, a)
            end
        end
        local place = spec.alpha
        local valueText = Controls.Label(parent, "", place.valueX, place.valueY or spec.y or 0, "GameFontHighlightSmall")
        if place.valueWidth then
            valueText:SetWidth(place.valueWidth)
            valueText:SetJustifyH("RIGHT")
        end
        swatch.alphaSlider = Controls.Slider(parent, {
            min = 0, max = 1, step = 0.05, x = place.x, y = place.y or (spec.y or 0) - 4, width = place.width,
            valueText = valueText, format = Controls.PercentText, get = Alpha, captions = place.captions,
            drag = spec.drag and WithAlpha(spec.drag), set = WithAlpha(spec.set),
        })
    end
    swatch:SetScript("OnClick", function()
        if spec.beforeOpen then spec.beforeOpen() end
        Controls.OpenColourPicker(spec.get(), set, spec.cancel)
    end)
    function swatch:Refresh()
        local colour = spec.get()
        if colour then self:SetBackdropColor(colour.r, colour.g, colour.b, 1) end
        if self.alphaSlider then self.alphaSlider:Refresh() end
    end
    return swatch
end
