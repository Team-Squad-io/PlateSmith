local _, PS = ...
local L = PS.L
local Kit = assert(PS.ThreatKit, "PlateSmith ThreatKit missing")
local Atlas = assert(PS.ThreatKitAtlas, "PlateSmith ThreatKitAtlas missing")

-- Threat window themes. A theme is data: how the chrome is drawn (art pieces from Media/Threat,
-- a code-drawn backdrop, or the client's own damage meter atlases), its metrics, fonts, bar
-- texture and text colours. The window code draws every theme with the same slots.
local Themes = {}
PS.ThreatThemes = Themes

local FLAT = "Interface\\Buttons\\WHITE8X8"

Themes.list = {
    -- Blueprint Studio's Accepted B look: iron and bronze edges on dark slate.
    { id = "forge", label = L["Forge"], kind = "art", prefix = "forge", buttons = "forge", border = 4, title = 22,
        header = 18, rowHeight = 18, spacing = 1, fillAlpha = 0.85, bar = "bar-brushed",
        titleText = { 0.93, 0.8, 0.52 }, headerText = { 0.72, 0.62, 0.46 }, text = { 0.9, 0.89, 0.87 },
        preview = "theme-forge-preview" },
    -- Studio's parchment side: parchment title and headers over a dark body.
    { id = "ledger", label = L["Ledger"], kind = "art", prefix = "ledger", buttons = "ledger", border = 4, title = 22,
        header = 18, rowHeight = 18, spacing = 1, fillAlpha = 0.85, bar = "bar-smooth",
        titleText = { 0.15, 0.1, 0.06 }, headerText = { 0.27, 0.13, 0.07 }, text = { 0.95, 0.93, 0.88 },
        digitText = { 0.96, 0.85, 0.63 },
        preview = "theme-ledger-preview" },
    { id = "glass", label = L["Glass"], kind = "art", prefix = "glass", buttons = "glass", border = 2, title = 20,
        header = 18, rowHeight = 18, spacing = 1, fillAlpha = 0.7, bar = "bar-smooth",
        titleText = { 0.96, 0.96, 0.96 }, headerText = { 0.68, 0.7, 0.74 }, text = { 0.96, 0.96, 0.96 },
        preview = "theme-glass-preview" },
    -- Code-drawn: a solid fill and a 1 px border, like Details!'s default.
    { id = "flat", label = L["Flat"], kind = "backdrop", buttons = "glass", edgeSize = 1, inset = 1, title = 18,
        header = 16, rowHeight = 18, spacing = 1, fillAlpha = 0.85, bar = "bar-flat", mono = true,
        fill = { 0.06, 0.065, 0.075 }, edge = { 0, 0, 0, 1 }, titleFill = { 0.12, 0.13, 0.15, 1 },
        titleText = { 0.92, 0.92, 0.92 }, headerText = { 0.62, 0.64, 0.68 }, text = { 0.95, 0.95, 0.95 },
        preview = "theme-flat-preview" },
    { id = "pixel", label = L["Pixel"], kind = "backdrop", buttons = "glass", edgeSize = 1, inset = 1, title = 16,
        header = 14, rowHeight = 16, spacing = 1, fillAlpha = 0.9, bar = "bar-flat", mono = true,
        fill = { 0.08, 0.08, 0.08 }, edge = { 0, 0, 0, 1 }, titleFill = { 0, 0, 0, 1 },
        titleText = { 1, 1, 1 }, headerText = { 0.7, 0.7, 0.7 }, text = { 1, 1, 1 },
        preview = "theme-pixel-preview" },
    { id = "contrast", label = L["High contrast"], kind = "backdrop", buttons = "glass", edgeSize = 2, inset = 2,
        title = 20, header = 16, rowHeight = 20, spacing = 2, fillAlpha = 1, bar = "bar-flat",
        fill = { 0, 0, 0 }, edge = { 1, 1, 1, 1 }, titleFill = { 0, 0, 0, 1 },
        titleText = { 1, 1, 1 }, headerText = { 1, 1, 1 }, text = { 1, 1, 1 },
        preview = "theme-high-contrast-preview" },
    -- The client's own tooltip border and status bar.
    { id = "blizzard", label = L["Blizzard"], kind = "backdrop", buttons = "glass", title = 20, header = 16,
        rowHeight = 18, spacing = 1, fillAlpha = 0.9, barFile = "Interface\\TargetingFrame\\UI-StatusBar",
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16, inset = 5, fill = { 0.05, 0.05, 0.08 }, edge = { 0.7, 0.7, 0.7, 1 },
        titleText = { 1, 0.82, 0 }, headerText = { 0.7, 0.7, 0.7 }, text = { 1, 1, 1 },
        preview = "theme-blizzard-preview" },
    -- Blizzard's built-in damage meter, drawn from the client's own atlases.
    { id = "meter", label = L["Blizzard Meter"], kind = "meter", buttons = "glass", title = 32, header = 16,
        rowHeight = 25, spacing = 4, inset = 6, fillAlpha = 0.9, barAtlas = "UI-HUD-CoolDownManager-Bar",
        barBackgroundAtlas = "ui-damagemeters-bar-shadowbg", backgroundAtlas = "damagemeters-background",
        headerAtlas = "ui-damagemeters-header-bar", gripAtlas = "damagemeters-scalehandle",
        titleFont = "GameFontNormalMed1", rowFont = "NumberFontNormal", fill = { 0, 0, 0 },
        titleText = { 1, 0.82, 0 }, headerText = { 0.7, 0.7, 0.7 }, text = { 1, 1, 1 },
        preview = "theme-blizzard-meter-preview" },
}

Themes.byId = {}
for _, theme in ipairs(Themes.list) do Themes.byId[theme.id] = theme end
Themes.default = "forge"

function Themes.Get(id)
    return Themes.byId[id] or Themes.byId[Themes.default]
end

function Themes.IsValid(id)
    return type(id) == "string" and Themes.byId[id] ~= nil
end

-- How far the content sits inside the window's edge.
function Themes.Inset(theme)
    return theme.border or theme.inset or 0
end

-- Kit pieces: each is drawn at its native size from its canvas's top-left. Most live on sprite
-- sheets (KitAtlas.lua, written by tools/build-atlases.py); coordinates are worked out in a
-- piece's canvas pixels and mapped onto its sheet or its own file.
function Themes.Size(name)
    local entry = Kit.assets[name]
    if not entry then return nil end
    return entry[1], entry[2], entry[3], entry[4]
end

-- A piece's file, the file's width and height, the canvas's top-left in it, and the file's wrap
-- modes (nil for a piece's own file, which wraps as its caller asks).
local function Source(name)
    local at = Atlas.pieces[name]
    if at then
        local sheet = Atlas.sheets[at[1]]
        return Kit.path .. sheet[1] .. ".png", sheet[2], sheet[3], at[2], at[3], sheet[4], sheet[5]
    end
    local cw, ch = Themes.Size(name)
    return Kit.path .. name .. ".png", cw, ch, 0, 0
end

function Themes.Path(name)
    return (Source(name))
end

-- Texture coordinates for the canvas pixels left..right, top..bottom of name.
function Themes.Coords(name, left, right, top, bottom)
    local _, width, height, x, y = Source(name)
    return (x + left) / width, (x + right) / width, (y + top) / height, (y + bottom) / height
end

-- The piece's native crop: left, right, top, bottom.
function Themes.TexCoord(name)
    local _, _, nw, nh = Themes.Size(name)
    return Themes.Coords(name, 0, nw, 0, nh)
end

-- Sets a kit file on a texture (once per file and wrap); false when the file is unknown or refused.
-- A piece on a sheet wraps as the sheet does and is cropped to its whole canvas, as its own file
-- was with no coordinates set; callers that crop set their own after this.
function Themes.SetKit(texture, name, repeatX, repeatY)
    local cw, ch = Themes.Size(name)
    if not cw then return false end
    local file, _, _, _, _, wrapX, wrapY = Source(name)
    if wrapX ~= nil then repeatX, repeatY = wrapX, wrapY end
    local key = file .. (repeatX and "x" or "") .. (repeatY and "y" or "")
    if texture.threatKitKey ~= key then
        local ok, loaded = pcall(texture.SetTexture, texture, file,
            repeatX and "REPEAT" or "CLAMP", repeatY and "REPEAT" or "CLAMP")
        texture.threatKitKey, texture.threatKitLoaded = key, ok and loaded ~= false
    end
    texture.threatKitName = name
    if wrapX ~= nil and texture.SetTexCoord then texture:SetTexCoord(Themes.Coords(name, 0, cw, 0, ch)) end
    return texture.threatKitLoaded
end

function Themes.SetAtlas(texture, atlas)
    texture.threatKitKey = nil
    if type(texture.SetAtlas) ~= "function" then return false end
    local ok, result = pcall(texture.SetAtlas, texture, atlas)
    return ok and result ~= false
end

local function Anchor(texture, parent, x, y, width, height)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    texture:SetSize(math.max(1, width), math.max(1, height))
end

-- The piece at native size, or stretched to width and height.
function Themes.Place(texture, name, parent, x, y, width, height)
    local cw, _, nw, nh = Themes.Size(name)
    if not cw or not Themes.SetKit(texture, name) then return false end
    Anchor(texture, parent, x, y, width or nw, height or nh)
    texture:SetTexCoord(Themes.Coords(name, 0, nw, 0, nh))
    return true
end

-- A run along axis "x" or "y": whole periods repeated, the last stretched a little to fit.
-- cross stretches the other axis (a tall row from a 32 px bar, for example).
function Themes.Repeat(texture, name, parent, x, y, extent, axis, cross)
    local cw, _, nw, nh = Themes.Size(name)
    if not cw then return false end
    local horizontal = axis ~= "y"
    if not Themes.SetKit(texture, name, horizontal, not horizontal) then return false end
    local period = horizontal and nw or nh
    local periods = math.max(1, math.floor(extent / period + 0.5))
    if horizontal then
        Anchor(texture, parent, x, y, extent, cross or nh)
        texture:SetTexCoord(Themes.Coords(name, 0, periods * nw, 0, nh))
    else
        Anchor(texture, parent, x, y, cross or nw, extent)
        texture:SetTexCoord(Themes.Coords(name, 0, nw, 0, periods * nh))
    end
    return true
end

-- A fill tiled at native size over width and height (fills keep their own files).
function Themes.Fill(texture, name, parent, x, y, width, height)
    local cw, ch = Themes.Size(name)
    if not cw or not Themes.SetKit(texture, name, true, true) then return false end
    Anchor(texture, parent, x, y, width, height)
    texture:SetTexCoord(0, width / cw, 0, height / ch)
    return true
end

-- A bar texture on a status bar (kit bars repeat along the bar; files and atlases stretch). The
-- bar crops its texture itself, so kit bars keep their own files.
function Themes.ApplyBar(statusBar, theme)
    if theme.barAtlas and type(statusBar.GetStatusBarTexture) == "function" then
        pcall(statusBar.SetStatusBarTexture, statusBar, FLAT)
        local texture = statusBar:GetStatusBarTexture()
        if texture and Themes.SetAtlas(texture, theme.barAtlas) then return end
    end
    if theme.barFile then
        pcall(statusBar.SetStatusBarTexture, statusBar, theme.barFile)
        return
    end
    pcall(statusBar.SetStatusBarTexture, statusBar, Themes.Path(theme.bar or "bar-flat"))
    local texture = type(statusBar.GetStatusBarTexture) == "function" and statusBar:GetStatusBarTexture() or nil
    local cw = Themes.Size(theme.bar or "bar-flat")
    if texture and cw and texture.SetTexCoord then texture:SetTexCoord(Themes.TexCoord(theme.bar or "bar-flat")) end
end

-- The state or role icon for this theme: flat themes use the monochrome set.
function Themes.Icon(texture, name, theme)
    if not name then
        texture:Hide()
        return false
    end
    local file = theme.mono and (name .. "-mono") or name
    if not Themes.SetKit(texture, file) then
        texture:Hide()
        return false
    end
    texture:SetTexCoord(Themes.TexCoord(file))
    texture:Show()
    return true
end

-- A title button's file for a state (normal, hover, pressed, disabled).
function Themes.ButtonFile(theme, button, state)
    return string.format("%s-btn-%s-%s", theme.buttons or "glass", button, state or "normal")
end

Themes.FLAT = FLAT
