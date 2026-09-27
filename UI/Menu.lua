local _, PS = ...

-- PlateSmith's one menu: context menus (right-click on a HUD window, Studio's menus) and every
-- dropdown's list (Controls.Dropdown). Its own frame rather than UIDropDownMenu or a StaticPopup,
-- so opening it never touches Blizzard's shared menu state. items: { text, func, checked,
-- disabled, title, children, tooltip = { title, text } } in order; { separator = true } draws a
-- gap. An item with children opens them in a submenu beside it; with a func as well, clicking it
-- runs the func. A list longer than MAX_ROWS scrolls with the mouse wheel.
PS.UI = PS.UI or {}
local Menu = {}
PS.UI.Menu = Menu

local ROW_HEIGHT, WIDTH, PADDING, MAX_ROWS = 18, 190, 6, 20
Menu.ROW_HEIGHT, Menu.PADDING, Menu.MAX_ROWS = ROW_HEIGHT, PADDING, MAX_ROWS
local frames = {}
local CreateRow, Build

local function Sound()
    if type(PlaySound) ~= "function" or type(SOUNDKIT) ~= "table" then return end
    local kit = SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if kit then pcall(PlaySound, kit) end
end
Menu.PlaySound = Sound

local function Tooltip(row)
    local tip = row.item and row.item.tooltip
    if not tip or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if type(tip) == "table" then
        GameTooltip:SetText(tip.title or row.item.text or "")
        if tip.text then GameTooltip:AddLine(tip.text, 1, 0.82, 0.45, true) end
    else
        GameTooltip:SetText(row.item.text or "")
        GameTooltip:AddLine(tip, 1, 0.82, 0.45, true)
    end
    GameTooltip:Show()
end

-- Draws the frame's items from its scroll offset.
local function Render(frame)
    local items, offset = frame.items or {}, frame.offset or 0
    local count = math.min(#items, MAX_ROWS)
    for index = 1, count do
        local row = frame.rows[index] or CreateRow(frame)
        frame.rows[index] = row
        local item = items[offset + index]
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING - (index - 1) * ROW_HEIGHT)
        row.label:SetText(item.separator and "" or (item.text or ""))
        row.check:SetText(item.checked and "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t" or "")
        row.arrow:SetText(item.children and not item.separator and ">" or "")
        if item.title then
            row.label:SetTextColor(1, 0.82, 0)
        elseif item.disabled then
            row.label:SetTextColor(0.5, 0.5, 0.5)
        else
            row.label:SetTextColor(1, 1, 1)
        end
        if row.SetEnabled then row:SetEnabled(not (item.disabled or item.title or item.separator)) end
        row:Show()
    end
    for index = count + 1, #frame.rows do
        frame.rows[index].item = nil
        frame.rows[index]:Hide()
    end
    frame.visibleRows = count
    return count
end

local function OpenLevel(level, anchor, items, beside, width)
    local frame = frames[level] or Build(level)
    frame.items, frame.offset = items, 0
    -- Opening on a long list starts with the checked item in view.
    for index, item in ipairs(items) do
        if item.checked and index > MAX_ROWS then frame.offset = math.min(#items - MAX_ROWS, index - 1) break end
    end
    local count = Render(frame)
    frame:SetWidth(width or WIDTH)
    frame:SetHeight(PADDING * 2 + count * ROW_HEIGHT)
    if frame.EnableMouseWheel then frame:EnableMouseWheel(#items > MAX_ROWS) end
    frame:ClearAllPoints()
    if anchor and beside then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", PADDING, PADDING)
    elseif anchor then
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    return frame
end

CreateRow = function(frame)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    -- A disabled item still explains itself on hover.
    if row.SetMotionScriptsWhileDisabled then row:SetMotionScriptsWhileDisabled(true) end
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.12)
    row.check = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.arrow = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.arrow:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Anchored on both sides without wrapping, so a long label is cut short with "..." inside
    -- the menu's width instead of spilling past it.
    row.label:SetPoint("LEFT", row, "LEFT", 18, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    -- Pointing at an item with children opens them; any other item closes an open submenu.
    row:SetScript("OnEnter", function(owner)
        local item = owner.item
        Tooltip(owner)
        if frame.level ~= 1 then return end
        if item and item.children and not item.disabled then OpenLevel(2, owner, item.children, true)
        elseif frames[2] then frames[2]:Hide() end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(owner)
        local item = owner.item
        if not item or item.disabled or item.title or item.separator then return end
        if item.children and not item.func then
            if frame.level == 1 then OpenLevel(2, owner, item.children, true) end
            return
        end
        Sound()
        Menu.Close()
        if item.func then item.func() end
    end)
    return row
end

Build = function(level)
    local frame = PS.UI.Window.Create(level == 1 and "PlateSmithContextMenu" or "PlateSmithContextSubmenu", {
        width = WIDTH, height = 40, strata = "FULLSCREEN_DIALOG", movable = false, closeButton = false,
        closeOnEscape = level == 1, background = { 0.03, 0.035, 0.04, 0.97 }, border = { 0.58, 0.42, 0.19, 0.95 },
    })
    frame.rows, frame.level = {}, level
    frame:SetScript("OnMouseWheel", function(owner, delta)
        local items = owner.items or {}
        local limit = math.max(0, #items - MAX_ROWS)
        owner.offset = math.max(0, math.min(limit, (owner.offset or 0) - delta))
        Render(owner)
    end)
    if level == 1 then
        -- A click anywhere outside the menu, its submenu and the field that opened it closes them
        -- (the field's own click toggles the menu).
        frame:SetScript("OnEvent", function(owner, event)
            if event ~= "GLOBAL_MOUSE_DOWN" or (owner.IsMouseOver and owner:IsMouseOver()) then return end
            local sub = frames[2]
            if sub and sub:IsShown() and sub.IsMouseOver and sub:IsMouseOver() then return end
            local field = Menu.owner
            if field and field.IsMouseOver and field:IsMouseOver() then return end
            Menu.Close()
        end)
        -- Escape closes the menu and nothing else (outside combat, where the key can be kept from
        -- the rest of the UI; in combat UISpecialFrames still closes it).
        frame:SetScript("OnKeyDown", function(owner, key)
            local keep = key == "ESCAPE"
            if owner.SetPropagateKeyboardInput then pcall(owner.SetPropagateKeyboardInput, owner, not keep) end
            if keep then Menu.Close() end
        end)
        frame:SetScript("OnHide", function(owner)
            if owner.UnregisterEvent then pcall(owner.UnregisterEvent, owner, "GLOBAL_MOUSE_DOWN") end
            if owner.EnableKeyboard then pcall(owner.EnableKeyboard, owner, false) end
            if frames[2] then frames[2]:Hide() end
            local field = Menu.owner
            Menu.owner = nil
            if field and field.OnMenuClosed then field:OnMenuClosed() end
        end)
        Menu.frame = frame
    else
        Menu.submenu = frame
    end
    frames[level] = frame
    return frame
end

-- options: width (the menu's width; a dropdown passes its field's), owner (the frame that opened
-- it: clicking it again closes the menu, and the menu closes when it hides).
function Menu.Open(anchor, items, options)
    options = options or {}
    if frames[2] then frames[2]:Hide() end
    if frames[1] and frames[1]:IsShown() then frames[1]:Hide() end
    local frame = OpenLevel(1, anchor, items, false, options.width)
    Menu.owner = options.owner
    local owner = options.owner
    if owner and not owner.menuHideHooked and owner.HookScript then
        owner.menuHideHooked = true
        owner:HookScript("OnHide", function(instance) if Menu.owner == instance then Menu.Close() end end)
    end
    if frame.RegisterEvent then pcall(frame.RegisterEvent, frame, "GLOBAL_MOUSE_DOWN") end
    if frame.EnableKeyboard and not PS.Secret.InCombat() then pcall(frame.EnableKeyboard, frame, true) end
    return frame
end

-- Opens the menu for owner, or closes it when owner's menu is already open (a dropdown's click).
function Menu.Toggle(owner, items, options)
    Sound()
    if Menu.IsOpenFor(owner) then
        Menu.Close()
        return nil
    end
    options = options or {}
    options.owner = owner
    return Menu.Open(owner, type(items) == "function" and items() or items, options)
end

function Menu.IsOpenFor(owner)
    return Menu.IsOpen() and Menu.owner == owner
end

function Menu.Close()
    if frames[2] then frames[2]:Hide() end
    if frames[1] then frames[1]:Hide() end
end

function Menu.IsOpen()
    return frames[1] ~= nil and frames[1]:IsShown()
end
