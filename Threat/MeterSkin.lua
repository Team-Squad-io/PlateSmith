local _, PS = ...

-- Skin Blizzard's damage meter (PS.ThreatMeterSkin): the threat windows' look (Forge, Ledger or Glass, the theme of
-- the threat window docked to that meter window, else of the first shown one) over Blizzard_DamageMeter's windows,
-- rows, header buttons, scroll bars and breakdown pop-outs. Optional, off by default, saved account-wide (state
-- meterSkin; behaviour, not a Blueprint's). Studio › Settings › Modules › Threat › Threat windows switches it.
--
-- Visual only (docs/research/blizzard-damage-meter.md). On Blizzard's frames it calls getters and CreateTexture and
-- nothing else; on their art regions only SetAlpha, SetTexture, SetAtlas, SetTexCoord, SetBlendMode, SetVertexColor,
-- SetFont and SetTextColor, recording each original so off puts it back at once. It never anchors,
-- sizes, scripts, reparents, shows or hides their frames (Edit Mode would be tainted), never writes a field into
-- their tables (records are keyed by object here), and never reads row text or values, which are protected in
-- combat. It follows the meter with hooksecurefunc only; its own size watchers sit on UIParent.
local Themes = assert(PS.ThreatThemes, "PlateSmith ThreatThemes missing")
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local unpack = unpack or table.unpack -- luacheck: ignore 143 (Lua 5.1 global; tests also run on 5.4)

local MeterSkin = {}
PS.ThreatMeterSkin = MeterSkin

local MAX_WINDOWS = 3        -- MAX_DAMAGE_METER_SESSION_WINDOWS
local HEADER_HEIGHT = 32     -- a session window's header bar (DamageMeterSessionWindow.xml)
local BUTTON_SIZE = 16       -- the threat windows' title buttons
local CAP = 5                -- the blank button's sides, kept whole when it is stretched (the session dropdown)
local SCROLL_WIDTH, SCROLL_END = 6, 3
local BAR_ALPHA = 0.7        -- the threat windows' bars (Meter:FillMember)
local KEEP_ERRORS = 5
local FALLBACK_THEME = "forge"
-- The developer test this replaced; both at once would record each other's art as Blizzard's.
local DEV_ADDON = "PlateSmith_MeterSkin"

local active, hooked, consoleHooked, pending = false, false, false, false
local windows = {}         -- session window -> record
local sources = {}         -- breakdown pop-out -> record
local rows = {}            -- entry frame -> { backdrop, theme, skinned }
local scrollBars = {}      -- Blizzard scroll bar -> { track, thumb, skinned }
local buttons = {}         -- Blizzard button -> { kind, overlay, skinned }
local followed = {}        -- Blizzard object -> true once its method is hooked
local originals = {}       -- Blizzard region -> what it had before the skin changed it
local errors = { count = 0, recent = {} }
local mixinUpdateBackground -- DamageMeterEntryMixin.UpdateBackground after the hook (copied into later rows)

local function Note(label, err)
    errors.count = errors.count + 1
    table.insert(errors.recent, 1, label .. ": " .. tostring(err))
    errors.recent[KEEP_ERRORS + 1] = nil
end

local function Try(label, action, ...)
    local ok, err = pcall(action, ...)
    if not ok then Note(label, err) end
    return ok
end

-- A Blizzard child by key path, or nil: a client whose names differ just skips that part.
local function Child(object, ...)
    for index = 1, select("#", ...) do
        if type(object) ~= "table" then return nil end
        object = object[select(index, ...)]
    end
    return object
end

local function Pack(...)
    return { n = select("#", ...), ... }
end

-- A getter's results, only when every one is readable (nil otherwise).
local function Read(object, method)
    local getter = type(object) == "table" and object[method]
    if type(getter) ~= "function" then return nil end
    local result = Pack(pcall(getter, object))
    if not result[1] then return nil end
    local values = {}
    for index = 2, result.n do
        if not Secret.IsReadable(result[index]) then return nil end
        values[index - 1] = result[index]
    end
    return values
end

local function ReadOne(object, method)
    local values = Read(object, method)
    if values then return values[1] end
    return nil
end

local function Record(region)
    local saved = originals[region]
    if not saved then
        saved = {}
        originals[region] = saved
    end
    return saved
end

-- Sets the alpha of one of Blizzard's art regions (never a frame): 0 hides it. Blizzard sets some of these alphas
-- itself (the window background follows the transparency setting), so each pass re-reads it; the skin's own value
-- is not taken for theirs.
local function ArtAlpha(region, value)
    if type(region) ~= "table" or type(region.SetAlpha) ~= "function" then return end
    local saved = Record(region)
    local alpha = ReadOne(region, "GetAlpha")
    if type(alpha) == "number" and not (saved.hidden and math.abs(alpha - saved.applied) < 0.005) then saved.alpha = alpha end
    saved.hidden, saved.applied = true, value
    region:SetAlpha(value)
end

local function HideArt(region)
    ArtAlpha(region, 0)
end

-- What a region shows now, unless it shows the skin's own file: Blizzard may set another atlas while the skin is on
-- (the minimise button's expand art), and that is what off puts back.
local function RecordTexture(region)
    local saved = Record(region)
    local atlas = ReadOne(region, "GetAtlas")
    if not saved.texture or (type(atlas) == "string" and atlas ~= "") then
        saved.texture = { atlas = atlas, file = ReadOne(region, "GetTexture"), coords = Read(region, "GetTexCoord") }
    end
    return saved
end

-- A status bar's fill: the bar crops its texture itself, so the theme's bar keeps its own file.
local function SetBarFile(region, file)
    if type(region) ~= "table" or type(region.SetTexture) ~= "function" then return end
    RecordTexture(region)
    region:SetTexture(file)
end

-- A kit piece on one of Blizzard's button regions (its state art), cropped to the piece; blend replaces the
-- region's blend mode (a highlight drawn additively).
local function SetPiece(region, name, blend)
    if type(region) ~= "table" or type(region.SetTexture) ~= "function" or not Themes.Size(name) then return false end
    local saved = RecordTexture(region)
    region:SetTexture(Themes.Path(name))
    region:SetTexCoord(Themes.TexCoord(name))
    if blend and type(region.SetBlendMode) == "function" then
        if not saved.blendRead then saved.blend, saved.blendRead = ReadOne(region, "GetBlendMode"), true end
        region:SetBlendMode(blend)
    end
    return true
end

local function Tint(region, colour)
    if type(region) ~= "table" or type(region.SetVertexColor) ~= "function" then return end
    local saved = Record(region)
    if not saved.tinted then saved.vertex, saved.tinted = Read(region, "GetVertexColor"), true end
    region:SetVertexColor(colour[1], colour[2], colour[3])
end

-- The theme's font face, size and outline on one of Blizzard's texts. SetFont, not SetFontObject: a font object
-- brings its own justification, and their texts set their own (names and the header's labels are left-aligned).
local function SetFont(text, objectName, colour)
    local object = rawget(_G, objectName)
    if type(text) ~= "table" or type(text.SetFont) ~= "function" or type(object) ~= "table" then return end
    local face = Read(object, "GetFont")
    if not (face and face[1] and face[2]) then return end
    local saved = originals[text]
    if not (saved and saved.font) then
        local original = Read(text, "GetFont")
        if not original then return end
        saved = Record(text)
        saved.font = { face = original, colour = colour and Read(text, "GetTextColor") or nil }
    end
    text:SetFont(face[1], face[2], face[3] or "")
    -- A colour the skin could not read back (protected) is left as it is: off could not restore it.
    if colour and saved.font.colour then text:SetTextColor(colour[1], colour[2], colour[3]) end
end

local function RestoreRegion(region, saved)
    if saved.hidden then region:SetAlpha(saved.alpha or 1) end
    local texture = saved.texture
    if texture then
        if texture.atlas then
            region:SetAtlas(texture.atlas)
        elseif texture.file then
            region:SetTexture(texture.file)
            local coords = texture.coords
            if coords and #coords >= 4 then region:SetTexCoord(unpack(coords)) end
        end
    end
    if saved.blendRead and saved.blend then region:SetBlendMode(saved.blend) end
    if saved.tinted then
        local colour = saved.vertex
        if colour then
            region:SetVertexColor(colour[1], colour[2], colour[3], colour[4] or 1)
        else
            region:SetVertexColor(1, 1, 1, 1)
        end
    end
    local font = saved.font
    if font then
        if font.face then region:SetFont(font.face[1], font.face[2], font.face[3] or "") end
        local colour = font.colour
        if colour then region:SetTextColor(colour[1], colour[2], colour[3], colour[4]) end
    end
end

local function RestoreAll()
    local done = originals
    originals = {}
    for region, saved in pairs(done) do Try("restore", RestoreRegion, region, saved) end
end

-- Our own textures on their frames (CreateTexture is the one frame call the skin makes there).
local function NewTexture(parent, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    texture:Hide()
    return texture
end

local function HideAll(textures)
    if not textures then return end
    for _, texture in ipairs(textures) do texture:Hide() end
end

-- A size watcher of our own, anchored to their frame (anchoring ours to theirs is safe).
local function Watcher(target, layout)
    local watcher = CreateFrame("Frame", nil, UIParent)
    watcher:SetAllPoints(target)
    watcher:SetScript("OnSizeChanged", layout)
    return watcher
end

local function Size(watcher)
    local width, height = watcher:GetWidth(), watcher:GetHeight()
    if not (Secret.IsReadable(width) and Secret.IsReadable(height)) then return nil end
    if type(width) ~= "number" or type(height) ~= "number" or width < 1 or height < 1 then return nil end
    return width, height
end

-- The threat window's theme for meter window index (nil: the first one's): the window docked to it, else the first
-- shown threat window, else the first. Only the art themes have the pieces; any other draws Forge.
local function ThemeFor(index)
    local console = PS.ThreatConsole
    local list = console and type(console.GetWindows) == "function" and console:GetWindows() or {}
    local chosen
    for _, record in ipairs(list) do
        if index and record.dockMeter == index then chosen = record break end
    end
    if not chosen then
        for _, record in ipairs(list) do
            if record.shown then chosen = record break end
        end
    end
    chosen = chosen or list[1]
    local theme = Themes.Get(chosen and chosen.theme)
    if theme.kind ~= "art" then theme = Themes.Get(FALLBACK_THEME) end
    return theme
end

local function ButtonFile(theme, art, state)
    return Themes.ButtonFile(theme, art, state)
end

local function NewChrome(parent)
    local chrome = { fill = NewTexture(parent, "BACKGROUND", 1), edges = {} }
    for index = 1, 8 do chrome.edges[index] = NewTexture(parent, "BACKGROUND", 2) end
    return chrome
end

local function HideChrome(chrome)
    if not chrome then return end
    chrome.fill:Hide()
    HideAll(chrome.edges)
end

-- The threat window's art frame (Meter:LayoutChrome) over a parent's rect from top down.
local function LayoutChrome(chrome, theme, parent, top, width, height, alpha)
    local prefix = theme.prefix .. "-frame-"
    local _, _, corner = Themes.Size(prefix .. "corner-tl")
    local border, edges = theme.border or 0, chrome.edges
    HideChrome(chrome)
    if not corner or width < corner * 2 or height < corner * 2 then return end
    if Themes.Fill(chrome.fill, prefix .. "fill", parent, border, top + border, width - border * 2, height - border * 2) then
        chrome.fill:SetAlpha(alpha)
        chrome.fill:Show()
    end
    local bottom = top + height
    Themes.Place(edges[1], prefix .. "corner-tl", parent, 0, top)
    Themes.Place(edges[2], prefix .. "corner-tr", parent, width - corner, top)
    Themes.Place(edges[3], prefix .. "corner-bl", parent, 0, bottom - corner)
    Themes.Place(edges[4], prefix .. "corner-br", parent, width - corner, bottom - corner)
    Themes.Repeat(edges[5], prefix .. "edge-top", parent, corner, top, width - corner * 2, "x")
    Themes.Repeat(edges[6], prefix .. "edge-bottom", parent, corner, bottom - border, width - corner * 2, "x")
    Themes.Repeat(edges[7], prefix .. "edge-left", parent, 0, top + corner, height - corner * 2, "y")
    Themes.Repeat(edges[8], prefix .. "edge-right", parent, width - border, top + corner, height - corner * 2, "y")
    for _, texture in ipairs(edges) do
        if texture.threatKitLoaded == true then texture:Show() end
    end
end

local function FillAlpha(theme, window)
    local alpha = window and ReadOne(window, "GetBackgroundAlpha")
    return (theme.fillAlpha or 1) * (type(alpha) == "number" and alpha or 1)
end

-- The title's pieces at x, y over width (height: the theme's own when nil).
local function LayoutTitle(title, theme, parent, x, y, width, height)
    local prefix = theme.prefix .. "-title-"
    local _, _, side, native = Themes.Size(prefix .. "left")
    HideAll(title)
    if not side or width < side * 2 then return end
    height = height or native
    if Themes.Place(title[1], prefix .. "left", parent, x, y, nil, height)
        and Themes.Repeat(title[2], prefix .. "mid", parent, x + side, y, width - side * 2, "x", height)
        and Themes.Place(title[3], prefix .. "right", parent, x + width - side, y, nil, height) then
        for _, texture in ipairs(title) do texture:Show() end
    end
end

-- A three-slice run along a scroll bar's track or thumb (our textures on their frame, anchored to it, so they move
-- and size with it; the bar's own fade carries them).
local function NewSlices(parent, layer)
    local slices = { NewTexture(parent, layer, 7), NewTexture(parent, layer, 7), NewTexture(parent, layer, 7) }
    slices[1]:SetPoint("TOP", parent, "TOP", 0, 0)
    slices[1]:SetSize(SCROLL_WIDTH, SCROLL_END)
    slices[3]:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    slices[3]:SetSize(SCROLL_WIDTH, SCROLL_END)
    slices[2]:SetPoint("TOPLEFT", slices[1], "BOTTOMLEFT", 0, 0)
    slices[2]:SetPoint("BOTTOMRIGHT", slices[3], "TOPRIGHT", 0, 0)
    return slices
end

local function ShowSlices(slices, prefix)
    for index, part in ipairs({ "top", "mid", "bottom" }) do
        local texture, name = slices[index], prefix .. part
        if Themes.SetKit(texture, name, false, index == 2) then
            texture:SetTexCoord(Themes.TexCoord(name))
            texture:Show()
        else
            texture:Hide()
        end
    end
end

-- MinimalScrollBar: the theme's track and thumb over Blizzard's (hidden by alpha: the thumb's own code reads its
-- atlases when it resizes, so they are never replaced), and the step arrows tinted to the theme.
local function SkinScrollBar(bar, theme)
    local track, thumb = Child(bar, "Track"), Child(bar, "Track", "Thumb")
    if type(track) ~= "table" or type(track.CreateTexture) ~= "function" then return end
    local record = scrollBars[bar]
    if not record then
        record = { track = NewSlices(track, "ARTWORK") }
        if type(thumb) == "table" and type(thumb.CreateTexture) == "function" then record.thumb = NewSlices(thumb, "OVERLAY") end
        scrollBars[bar] = record
    end
    for _, key in ipairs({ "Begin", "Middle", "End" }) do
        HideArt(Child(track, key))
        HideArt(Child(thumb, key))
    end
    local prefix = theme.prefix .. "-scroll-"
    ShowSlices(record.track, prefix .. "track-")
    if record.thumb then ShowSlices(record.thumb, prefix .. "thumb-") end
    Tint(Child(bar, "Back", "Texture"), theme.headerText)
    Tint(Child(bar, "Forward", "Texture"), theme.headerText)
    record.skinned = true
end

-- A dropdown's look from its own state getters (ButtonStateBehaviorMixin): pressed, hover or normal, and whether
-- it is disabled.
local function DropdownState(button)
    local disabled = ReadOne(button, "IsEnabled") == false
    if not disabled and (ReadOne(button, "IsDown") == true or ReadOne(button, "IsMenuOpen") == true) then
        return "pressed", false
    elseif not disabled and ReadOne(button, "IsOver") == true then
        return "hover", false
    end
    return "normal", disabled
end

local function DrawSettings(record, button)
    local state, disabled = DropdownState(button)
    local name = ButtonFile(record.theme, "menu", state)
    local overlay = record.overlay
    if Themes.SetKit(overlay, name) then
        overlay:SetTexCoord(Themes.TexCoord(name))
        overlay:SetAlpha(disabled and 0.45 or 1)
        overlay:Show()
    end
end

local function DrawSession(record, button)
    local state, disabled = DropdownState(button)
    local name = ButtonFile(record.theme, "blank", state)
    local _, _, native = Themes.Size(name)
    if not native then return end
    local crops = { { 0, CAP }, { CAP, native - CAP }, { native - CAP, native } }
    for index, texture in ipairs(record.overlay) do
        if Themes.SetKit(texture, name) then
            local crop = crops[index]
            texture:SetTexCoord(Themes.Coords(name, crop[1], crop[2], 0, native))
            texture:SetAlpha(disabled and 0.45 or 1)
            texture:Show()
        end
    end
end

local function DrawButton(button)
    local record = buttons[button]
    if not (active and record) then return end
    if record.kind == "settings" then
        DrawSettings(record, button)
    elseif record.kind == "session" then
        DrawSession(record, button)
    end
end

local function OnButtonState(button)
    if active and buttons[button] then Try("button", DrawButton, button) end
end

local function FollowState(button)
    if followed[button] or type(button.OnButtonStateChanged) ~= "function" then return end
    followed[button] = true
    hooksecurefunc(button, "OnButtonStateChanged", OnButtonState)
end

-- The settings dropdown (27 px, its icon drawn by state): Blizzard's icon hidden, the theme's menu button over it.
local function SkinSettings(button, theme)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return end
    local record = buttons[button]
    if not record then
        local overlay = NewTexture(button, "OVERLAY", 7)
        overlay:SetPoint("CENTER", button, "CENTER", 0, 0)
        overlay:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        record = { kind = "settings", overlay = overlay }
        buttons[button] = record
    end
    record.theme, record.skinned = theme, true
    FollowState(button)
    HideArt(Child(button, "Icon"))
    DrawSettings(record, button)
end

-- The session dropdown (its text, 18 or 32 px wide): Blizzard's background and arrow hidden, the theme's blank
-- button behind the text, its sides kept and its middle stretched.
local function SkinSession(button, theme)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return end
    local record = buttons[button]
    if not record then
        local left, mid, right = NewTexture(button, "BORDER"), NewTexture(button, "BORDER"), NewTexture(button, "BORDER")
        left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        left:SetWidth(CAP)
        right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(CAP)
        mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
        record = { kind = "session", overlay = { left, mid, right } }
        buttons[button] = record
    end
    record.theme, record.skinned = theme, true
    FollowState(button)
    HideArt(Child(button, "Background"))
    HideArt(Child(button, "Arrow"))
    DrawSession(record, button)
end

-- A plain button whose state art Blizzard draws from its Normal, Pushed and Highlight regions (the minimise
-- button, the breakdown's close button): those regions show the theme's pieces, so every state stays the client's.
local function SkinStateButton(button, theme, art, kind)
    if type(button) ~= "table" then return end
    local record = buttons[button]
    if not record then
        record = { kind = kind }
        buttons[button] = record
    end
    record.theme = theme
    local normal = ReadOne(button, "GetNormalTexture")
    if not SetPiece(normal, ButtonFile(theme, art, "normal")) then return end
    SetPiece(ReadOne(button, "GetPushedTexture"), ButtonFile(theme, art, "pressed"))
    SetPiece(ReadOne(button, "GetHighlightTexture"), ButtonFile(theme, art, "hover"), "BLEND")
    SetPiece(ReadOne(button, "GetDisabledTexture"), ButtonFile(theme, art, "normal"))
    record.skinned = true
end

local function SkinMinimize(window)
    local record = windows[window]
    if not (active and record) then return end
    local art = ReadOne(window, "IsMinimized") == true and "expand" or "minimize"
    SkinStateButton(Child(window, "MinimizeButton"), record.theme, art, "minimize")
end

local LayoutWindow
local function OnSetMinimized(window)
    if not (active and windows[window]) then return end
    Try("minimise button", SkinMinimize, window)
    Try("layout", LayoutWindow, window)
end

-- As a threat window: the frame round the whole window and the title inside its border, where Blizzard's header
-- texts and buttons sit. Both are on MinimizeContainer, which Blizzard hides when the window is minimised; then only
-- the header shows, drawn as the title stretched to its 32 px.
LayoutWindow = function(window)
    local record = windows[window]
    if not (active and record) then return end
    local width, height = Size(record.watcher)
    if not width then return end
    local theme = record.theme
    local container = Child(window, "MinimizeContainer")
    if record.chrome and container and ReadOne(window, "IsMinimized") ~= true then
        HideAll(record.title)
        local border = theme.border or 0
        LayoutChrome(record.chrome, theme, container, 0, width, height, FillAlpha(theme, window))
        LayoutTitle(record.bodyTitle, theme, container, border, border, width - border * 2)
    else
        HideChrome(record.chrome)
        HideAll(record.bodyTitle)
        LayoutTitle(record.title, theme, window, 0, 0, width, HEADER_HEIGHT)
    end
end

local function LayoutSource(source)
    local record = sources[source]
    if not (active and record) then return end
    local width, height = Size(record.watcher)
    if width then LayoutChrome(record.chrome, record.theme, source, 0, width, height, record.theme.fillAlpha or 1) end
end

-- A row (DamageMeterEntryTemplate): a dark track behind the bar, the theme's bar texture under Blizzard's own
-- class colour, and the theme's row font. Its numbers and names stay Blizzard's text; nothing reads them.
local followEntry
local function SkinRow(row, theme)
    if not active then return end
    local bar = Child(row, "StatusBar")
    if type(bar) ~= "table" or type(bar.CreateTexture) ~= "function" then return end
    local record = rows[row]
    if not record then
        record = { backdrop = NewTexture(bar, "BACKGROUND", 1) }
        record.backdrop:SetAllPoints(bar)
        rows[row] = record
    end
    theme = theme or record.theme or ThemeFor(nil)
    record.theme = theme
    followEntry(row)
    if Themes.SetKit(record.backdrop, "bar-backdrop", true, false) then
        record.backdrop:SetVertexColor(0.12, 0.12, 0.13, 0.8)
        record.backdrop:Show()
    end
    HideArt(Child(bar, "Background"))
    HideArt(Child(bar, "BackgroundEdge"))
    local fill = ReadOne(bar, "GetStatusBarTexture")
    SetBarFile(fill, Themes.Path(theme.bar or "bar-flat"))
    ArtAlpha(fill, BAR_ALPHA)
    local font = theme.rowFont or "GameFontHighlightSmall"
    SetFont(Child(bar, "Name"), font)
    SetFont(Child(bar, "Value"), font)
    record.skinned = true
end

local function SkinRowSafely(row, theme)
    Try("row", SkinRow, row, theme)
end

-- Blizzard puts a row's background alpha back on every setup and style change (UpdateBackground).
local function OnEntryBackground(row)
    if active then SkinRowSafely(row) end
end

followEntry = function(row)
    if followed[row] then return end
    followed[row] = true
    -- A row made after the mixin was hooked already carries the hook.
    if mixinUpdateBackground and row.UpdateBackground == mixinUpdateBackground then return end
    if type(row.UpdateBackground) == "function" then hooksecurefunc(row, "UpdateBackground", OnEntryBackground) end
end

local function EachEntry(owner, action, theme)
    if type(owner) == "table" and type(owner.ForEachEntryFrame) == "function" then owner:ForEachEntryFrame(action, theme) end
end

local function OnSourceRefresh(source)
    local record = sources[source]
    if active and record then Try("breakdown rows", EachEntry, source, SkinRowSafely, record.theme) end
end

-- The breakdown pop-out (MinimizeContainer.SourceWindow): the theme's frame over common-dropdown-bg, its rows,
-- scroll bar and close button.
local function SkinSource(source, theme)
    if type(source) ~= "table" or type(source.CreateTexture) ~= "function" then return end
    local record = sources[source]
    if not record then
        record = { chrome = NewChrome(source) }
        record.watcher = Watcher(source, function() Try("breakdown layout", LayoutSource, source) end)
        sources[source] = record
        if type(source.Refresh) == "function" then hooksecurefunc(source, "Refresh", OnSourceRefresh) end
    end
    record.theme = theme
    record.watcher:Show()
    HideArt(Child(source, "Background"))
    record.skinned = true
    LayoutSource(source)
    EachEntry(source, SkinRowSafely, theme)
    local bar = Child(source, "ScrollBar")
    if bar then Try("breakdown scroll bar", SkinScrollBar, bar, theme) end
    local close = Child(source, "CloseButton")
    if close then Try("breakdown close button", SkinStateButton, close, theme, "close", "close") end
end

local function RestyleBackground(window)
    local record = windows[window]
    HideArt(Child(window, "MinimizeContainer", "Background"))
    if record and record.chrome then record.chrome.fill:SetAlpha(FillAlpha(record.theme, window)) end
end

local function OnWindowBackground(window)
    if active and windows[window] then Try("window background", RestyleBackground, window) end
end

local function OnSetupEntry(window, row)
    local record = windows[window]
    if active then SkinRowSafely(row, record and record.theme) end
end

local function SkinWindow(window, index)
    local record = windows[window]
    if not record then
        record = { index = index, title = { NewTexture(window, "BACKGROUND", 1), NewTexture(window, "BACKGROUND", 1),
            NewTexture(window, "BACKGROUND", 1) } }
        local container = Child(window, "MinimizeContainer")
        if type(container) == "table" and type(container.CreateTexture) == "function" then
            record.chrome = NewChrome(container)
            record.bodyTitle = { NewTexture(container, "BORDER"), NewTexture(container, "BORDER"), NewTexture(container, "BORDER") }
        end
        record.watcher = Watcher(window, function() Try("layout", LayoutWindow, window) end)
        windows[window] = record
        if type(window.SetupEntry) == "function" then hooksecurefunc(window, "SetupEntry", OnSetupEntry) end
        if type(window.UpdateBackground) == "function" then hooksecurefunc(window, "UpdateBackground", OnWindowBackground) end
        if type(window.SetMinimized) == "function" then hooksecurefunc(window, "SetMinimized", OnSetMinimized) end
    end
    local theme = ThemeFor(index)
    record.theme = theme
    record.watcher:Show()
    record.skinned = true
    HideArt(Child(window, "Header"))
    RestyleBackground(window)
    local font, colour = theme.titleFont or "GameFontNormal", theme.titleText
    SetFont(Child(window, "SessionTimer"), font, colour)
    SetFont(Child(window, "DamageMeterTypeDropdown", "TypeName"), font, colour)
    SetFont(Child(window, "SessionDropdown", "SessionName"), font, colour)
    LayoutWindow(window)
    Try("minimise button", SkinMinimize, window)
    Try("settings button", SkinSettings, Child(window, "SettingsDropdown"), theme)
    Try("session button", SkinSession, Child(window, "SessionDropdown"), theme)
    local container = Child(window, "MinimizeContainer")
    local bar = Child(container, "ScrollBar")
    if bar then Try("scroll bar", SkinScrollBar, bar, theme) end
    if Child(container, "LocalPlayerEntry") then SkinRowSafely(container.LocalPlayerEntry, theme) end
    Try("rows", EachEntry, window, SkinRowSafely, theme)
    Try("breakdown", SkinSource, Child(container, "SourceWindow"), theme)
end

local function SessionWindow(index)
    local meter = rawget(_G, "DamageMeter")
    if type(meter) == "table" and type(meter.GetSessionWindow) == "function" then
        local ok, window = pcall(meter.GetSessionWindow, meter, index)
        if ok and type(window) == "table" then return window end
    end
    local window = rawget(_G, "DamageMeterSessionWindow" .. index)
    return type(window) == "table" and window or nil
end

local function SkinAll()
    for index = 1, MAX_WINDOWS do
        local window = SessionWindow(index)
        if window then Try("window " .. index, SkinWindow, window, index) end
    end
end

local function OnSetupSessionWindow()
    if active then Try("new window", SkinAll) end
end

-- A threat window's theme or docking changed: a meter window whose theme follows it is skinned again.
local function OnConsoleChanged()
    if not active then return end
    for window, record in pairs(windows) do
        if record.skinned and ThemeFor(record.index) ~= record.theme then Try("theme", SkinWindow, window, record.index) end
    end
end

-- Hooks stay once made (they cannot be removed); each returns at once while the skin is off.
local function InstallHooks()
    if not hooked then
        hooked = true
        local meter = rawget(_G, "DamageMeter")
        if type(meter.SetupSessionWindow) == "function" then hooksecurefunc(meter, "SetupSessionWindow", OnSetupSessionWindow) end
        local mixin = rawget(_G, "DamageMeterEntryMixin")
        if type(mixin) == "table" and type(mixin.UpdateBackground) == "function" then
            hooksecurefunc(mixin, "UpdateBackground", OnEntryBackground)
            mixinUpdateBackground = mixin.UpdateBackground
        end
    end
    local console = PS.ThreatConsole
    if not consoleHooked and type(console) == "table" then
        consoleHooked = true
        for _, method in ipairs({ "SetWindowOption", "CreateWindow", "DeleteWindow" }) do
            if type(console[method]) == "function" then hooksecurefunc(console, method, OnConsoleChanged) end
        end
    end
end

-- Why the skin cannot run now (nil when it can).
local function Missing()
    if type(hooksecurefunc) ~= "function" then return "api-missing" end
    local addons = rawget(_G, "C_AddOns")
    if addons and type(addons.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(addons.IsAddOnLoaded, DEV_ADDON)
        if ok and loaded == true then return "blocked" end
    end
    if type(rawget(_G, "DamageMeter")) ~= "table" then return "unavailable" end
    return nil
end

local function Enable()
    active = true
    pending = false
    Try("hooks", InstallHooks)
    Try("skin", SkinAll)
end

local function Disable()
    active = false
    pending = false
    for _, record in pairs(windows) do
        Try("hide", HideAll, record.title)
        Try("hide", HideAll, record.bodyTitle)
        Try("hide", HideChrome, record.chrome)
        record.watcher:Hide()
        record.skinned = false
    end
    for _, record in pairs(sources) do
        Try("hide", HideChrome, record.chrome)
        record.watcher:Hide()
        record.skinned = false
    end
    for _, record in pairs(rows) do
        record.backdrop:Hide()
        record.skinned = false
    end
    for _, record in pairs(scrollBars) do
        HideAll(record.track)
        HideAll(record.thumb)
        record.skinned = false
    end
    for _, record in pairs(buttons) do
        local overlay = record.overlay
        if type(overlay) == "table" and overlay.Hide then overlay:Hide() else HideAll(overlay) end
        record.skinned = false
    end
    RestoreAll()
end

local function State()
    local ok, state = pcall(PS.GetState)
    if ok and type(state) == "table" then return state end
    return nil
end

function MeterSkin.IsOn()
    local state = State()
    return state ~= nil and state.meterSkin == true
end

-- Skins or restores the meter to match the setting. Off restores at once; on waits for combat to end (nothing it
-- calls is restricted, but a first skin creates frames and hooks, kept out of combat).
function MeterSkin.Apply()
    if not MeterSkin.IsOn() or Missing() then
        if active or next(originals) then Disable() end
        pending = false
        return false
    end
    if Secret.InCombat() then
        pending = not active
        if active then Try("skin", SkinAll) end
        return active
    end
    Enable()
    return true
end

-- The setting (account state, saved at once). true when it was written.
function MeterSkin.SetOn(on)
    local state = State()
    if not state then return false end
    state.meterSkin = on == true or nil
    MeterSkin.Apply()
    return true
end

local function Count(map)
    local count = 0
    for _, record in pairs(map) do
        if record.skinned then count = count + 1 end
    end
    return count
end

-- The /ps diagnose section (meterSkin): readable state words and counts only.
function MeterSkin.Report()
    local missing = Missing()
    local state
    if not MeterSkin.IsOn() then
        state = "off"
    elseif missing then
        state = missing
    elseif pending then
        state = "pending"
    elseif errors.count > 0 then
        state = "error"
    else
        state = active and "on" or "off"
    end
    local present = 0
    for index = 1, MAX_WINDOWS do
        if SessionWindow(index) then present = present + 1 end
    end
    local report = { enabled = MeterSkin.IsOn(), state = state, windows = Count(windows), meterWindows = present,
        rows = Count(rows), buttons = Count(buttons), scrollBars = Count(scrollBars), breakdowns = Count(sources),
        errors = errors.count }
    if errors.recent[1] then report.lastError = errors.recent[1] end
    if missing == "blocked" then report.devAddon = DEV_ADDON end
    return report
end

MeterSkin._Test = { errors = errors, DevAddon = DEV_ADDON, ThemeFor = ThemeFor, IsActive = function() return active end,
    IsPending = function() return pending end }

local events = CreateFrame("Frame")
MeterSkin.events = events
PS._RegisterEvent(events, "PLAYER_ENTERING_WORLD", "platesmith.meter-skin")
PS._RegisterEvent(events, "ADDON_LOADED", "platesmith.meter-skin")
PS._RegisterEvent(events, "PLAYER_REGEN_ENABLED", "platesmith.meter-skin")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_DamageMeter" then return end
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    if event == "PLAYER_ENTERING_WORLD" and (active or not MeterSkin.IsOn()) then return end
    Try("apply", MeterSkin.Apply)
end)
