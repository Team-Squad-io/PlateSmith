local _, PS = ...
local Kit = assert(PS.StudioKit, "PlateSmith StudioKit missing")
local Atlas = assert(PS.StudioKitAtlas, "PlateSmith StudioKitAtlas missing")

-- Draws Studio from the Accepted B kit (Kit.lua): every piece at its native size from its
-- canvas's top-left, placed by x and y from its parent's top-left. Straight runs repeat whole
-- periods (stretched a little to fit exactly, so both ends keep their joins); fills tile at a
-- display scale. Composite pieces: nine-slice frames and rings, and three-slice controls.
-- Most pieces live on sprite sheets (KitAtlas.lua, written by tools/build-atlases.py), so
-- coordinates are worked out in a piece's canvas pixels and mapped onto its sheet or own file.
local Theme = {}
PS.StudioTheme = Theme

local function Size(name)
    local entry = Kit.assets[name]
    if not entry then return nil end
    return entry[1], entry[2], entry[3], entry[4]
end
Theme.Size = Size

-- A piece's file, the file's width and height, the canvas's top-left in it, and the file's wrap
-- modes (nil for a piece's own file, which wraps as its caller asks).
local function Source(name)
    local at = Atlas.pieces[name]
    if at then
        local sheet = Atlas.sheets[at[1]]
        return Kit.path .. sheet[1] .. ".png", sheet[2], sheet[3], at[2], at[3], sheet[4], sheet[5]
    end
    local cw, ch = Size(name)
    return Kit.path .. name .. ".png", cw, ch, 0, 0
end

function Theme.Path(name)
    return (Source(name))
end

-- Texture coordinates for the canvas pixels left..right, top..bottom of name.
function Theme.Coords(name, left, right, top, bottom)
    local _, width, height, x, y = Source(name)
    return (x + left) / width, (x + right) / width, (y + top) / height, (y + bottom) / height
end

-- The piece's native crop: left, right, top, bottom.
function Theme.TexCoord(name)
    local _, _, nw, nh = Size(name)
    return Theme.Coords(name, 0, nw, 0, nh)
end

-- Sets name's file on texture (once), with its wrap modes; false when the client refuses it.
-- A sheet always wraps as the sheet does.
function Theme.Set(texture, name, repeatX, repeatY)
    local file, _, _, _, _, wrapX, wrapY = Source(name)
    if wrapX ~= nil then repeatX, repeatY = wrapX, wrapY end
    local key = file .. (repeatX and "x" or "") .. (repeatY and "y" or "")
    if texture.kitKey ~= key then
        local ok, loaded = pcall(texture.SetTexture, texture, file,
            repeatX and "REPEAT" or "CLAMP", repeatY and "REPEAT" or "CLAMP")
        texture.kitKey, texture.kitLoaded = key, ok and loaded ~= false
    end
    texture.kitName = name
    return texture.kitLoaded
end

local function Anchor(texture, parent, x, y, width, height)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    texture:SetSize(math.max(1, width), math.max(1, height))
end

-- The piece at native size (or stretched to width, height).
function Theme.Place(texture, name, parent, x, y, width, height)
    local cw, _, nw, nh = Size(name)
    if not cw then return false end
    Theme.Set(texture, name)
    Anchor(texture, parent, x, y, width or nw, height or nh)
    texture:SetTexCoord(Theme.Coords(name, 0, nw, 0, nh))
    return true
end

-- A straight run of extent along axis ("x" or "y"): whole periods, the last absorbing the rest.
-- thickness (optional) draws the run across a different size than the piece's own.
function Theme.Repeat(texture, name, parent, x, y, extent, axis, thickness)
    local cw, _, nw, nh = Size(name)
    if not cw then return false end
    local horizontal = axis ~= "y"
    Theme.Set(texture, name, horizontal, not horizontal)
    local period = horizontal and nw or nh
    local periods = math.max(1, math.floor(extent / period + 0.5))
    if horizontal then
        Anchor(texture, parent, x, y, extent, thickness or nh)
        texture:SetTexCoord(Theme.Coords(name, 0, periods * nw, 0, nh))
    else
        Anchor(texture, parent, x, y, thickness or nw, extent)
        texture:SetTexCoord(Theme.Coords(name, 0, nw, 0, periods * nh))
    end
    return true
end

-- A fill tiled over width, height, each tile shown at scale (1 draws it at its own size). Fills
-- tile on both axes, so they keep their own files.
function Theme.Fill(texture, name, parent, x, y, width, height, scale)
    local cw, ch = Size(name)
    if not cw then return false end
    Theme.Set(texture, name, true, true)
    Anchor(texture, parent, x, y, width, height)
    texture:SetTexCoord(0, width / (cw * (scale or 1)), 0, height / (ch * (scale or 1)))
    return true
end

-- A picture covering width, height without distortion, cropped equally from both sides.
function Theme.Cover(texture, name, parent, x, y, width, height)
    local cw, ch = Size(name)
    if not cw then return false end
    Theme.Set(texture, name)
    Anchor(texture, parent, x, y, width, height)
    local box, picture = width / math.max(1, height), cw / ch
    if box > picture then
        local span = picture / box
        texture:SetTexCoord(Theme.Coords(name, 0, cw, (1 - span) / 2 * ch, (1 + span) / 2 * ch))
    else
        local span = box / picture
        texture:SetTexCoord(Theme.Coords(name, (1 - span) / 2 * cw, (1 + span) / 2 * cw, 0, ch))
    end
    return true
end

-- Nine-slice frames and rings. A family's corner size and rail thickness come from its pieces;
-- Layout(x, y, width, height) places them round that rectangle of the parent.
local PARTS = { "corner-tl", "corner-tr", "corner-bl", "corner-br", "edge-top", "edge-bottom", "edge-left", "edge-right" }

function Theme.NineSlice(parent, family, layer, sublevel)
    local ring = { parent = parent, family = family, textures = {} }
    for index, part in ipairs(PARTS) do
        local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
        texture.kitPart = part
        ring.textures[index] = texture
    end
    function ring:Layout(x, y, width, height)
        local _, _, c = Size(family .. "-corner-tl")
        local _, _, _, top = Size(family .. "-edge-top")
        local _, _, left = Size(family .. "-edge-left")
        local _, _, cornerRight = Size(family .. "-corner-tr")
        local _, _, _, cornerBottom = Size(family .. "-corner-bl")
        local t = self.textures
        Theme.Place(t[1], family .. "-corner-tl", parent, x, y)
        Theme.Place(t[2], family .. "-corner-tr", parent, x + width - cornerRight, y)
        Theme.Place(t[3], family .. "-corner-bl", parent, x, y + height - cornerBottom)
        Theme.Place(t[4], family .. "-corner-br", parent, x + width - cornerRight, y + height - cornerBottom)
        Theme.Repeat(t[5], family .. "-edge-top", parent, x + c, y, width - c - cornerRight, "x")
        Theme.Repeat(t[6], family .. "-edge-bottom", parent, x + c, y + height - top, width - c - cornerRight, "x")
        Theme.Repeat(t[7], family .. "-edge-left", parent, x, y + c, height - c - cornerBottom, "y")
        Theme.Repeat(t[8], family .. "-edge-right", parent, x + width - left, y + c, height - c - cornerBottom, "y")
    end
    function ring:SetShown(shown)
        for _, texture in ipairs(self.textures) do texture:SetShown(shown and texture.kitLoaded) end
    end
    return ring
end

-- A horizontal three-slice control: prefix-state-left / -mid / -right (with a height suffix
-- for the buttons' 26 and 28 px sets). Layout(width) sizes it to the parent frame; with fit set,
-- the pieces are drawn at the parent's height too (a compact field in an inspector row).
function Theme.ThreeSlice(parent, prefix, height)
    local strip = { parent = parent, prefix = prefix, height = height, state = "normal", textures = {} }
    for index = 1, 3 do
        strip.textures[index] = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    end
    function strip:Name(side)
        local suffix = (self.height and self.height ~= 32) and ("-" .. self.height) or ""
        return string.format("%s-%s%s-%s", self.prefix, self.state, suffix, side)
    end
    function strip:Layout()
        local width = self.parent:GetWidth()
        local _, _, capLeft = Size(self:Name("left"))
        local _, _, capRight = Size(self:Name("right"))
        if not capLeft or not capRight then return end
        local drawn = self.fit and self.parent:GetHeight() or nil
        if drawn and drawn <= 0 then drawn = nil end
        local t = self.textures
        Theme.Place(t[1], self:Name("left"), self.parent, 0, 0, drawn and capLeft, drawn)
        Theme.Repeat(t[2], self:Name("mid"), self.parent, capLeft, 0, math.max(1, width - capLeft - capRight), "x", drawn)
        Theme.Place(t[3], self:Name("right"), self.parent, width - capRight, 0, drawn and capRight, drawn)
    end
    function strip:SetState(state)
        self.state = state
        self:Layout()
    end
    function strip:SetShown(shown)
        for _, texture in ipairs(self.textures) do texture:SetShown(shown and texture.kitLoaded) end
    end
    return strip
end

-- A single stateful piece (checkbox, arrow, close button): prefix-state.
function Theme.StatePiece(texture, prefix, state, parent, x, y)
    local name = prefix .. "-" .. (state or "normal")
    if not Size(name) then name = prefix .. "-normal" end
    return Theme.Place(texture, name, parent or texture:GetParent(), x or 0, y or 0)
end

