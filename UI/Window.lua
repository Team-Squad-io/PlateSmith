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

-- A scrolling, selectable text box. The caller anchors the returned scroll frame. spec.plain
-- leaves out Blizzard's scroll bar (the caller brings its own).
function Window.ScrollEditBox(parent, spec)
    spec = spec or {}
    local scroll = CreateFrame("ScrollFrame", nil, parent, not spec.plain and "UIPanelScrollFrameTemplate" or nil)
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(spec.font or "GameFontHighlightSmall")
    if editBox.SetMaxLetters then editBox:SetMaxLetters(spec.maxLetters or 0) end
    editBox:SetScript("OnEscapePressed", function() parent:Hide() end)
    scroll:SetScrollChild(editBox)
    return scroll, editBox
end

-- A scrolling, read-only text area; child.text is the FontString.
function Window.ScrollText(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    text:SetJustifyH("LEFT")
    if text.SetJustifyV then text:SetJustifyV("TOP") end
    child.text = text
    scroll:SetScrollChild(child)
    return scroll, child
end

-- Text sized to its content, so scrolling covers exactly what was written.
function Window.SetScrollText(target, text, lineHeight, minimumHeight)
    local _, lines = tostring(text or ""):gsub("\n", "\n")
    target:SetHeight(math.max(minimumHeight or 300, (lines + 2) * (lineHeight or 16)))
end

function Window.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, height or 24)
    button:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end
