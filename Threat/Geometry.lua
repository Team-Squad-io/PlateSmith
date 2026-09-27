local _, PS = ...

-- Pure maths for the threat windows: rows that fit, columns by width, snapping edge to edge,
-- snapped groups, free space for a new window, and following a Blizzard damage meter window.
-- Rectangles are { left, bottom, right, top } in UIParent coordinates (y grows upwards, as the
-- client's).
local Geometry = {}
PS.ThreatGeometry = Geometry

Geometry.SNAP_DISTANCE = 8
Geometry.TOUCH_TOLERANCE = 1.5
-- A new window with no free spot beside another steps this far down and right from the last one.
Geometry.CASCADE_STEP = 24
-- The threat meter's GAP column needs this much row width; the minimum window width keeps it.
Geometry.GAP_COLUMN_WIDTH = 200
-- The windows' limits, shared by the windows and the Threat settings page: at most MAX_WINDOWS,
-- each within WINDOW_RANGES (the narrowest still fits its title and the GAP and THREAT columns).
Geometry.MAX_WINDOWS = 5
Geometry.WINDOW_RANGES = { width = { 240, 900 }, height = { 40, 1200 }, rowHeight = { 12, 30 }, alpha = { 0, 1 } }

function Geometry.Rect(left, top, width, height)
    return { left = left, bottom = top - height, right = left + width, top = top }
end

-- Rows that fit a body of this height (at least one, so a tiny window still shows something).
function Geometry.VisibleRows(bodyHeight, rowHeight, spacing)
    spacing = spacing or 0
    if type(bodyHeight) ~= "number" or type(rowHeight) ~= "number" or rowHeight <= 0 then return 1 end
    return math.max(1, math.floor((bodyHeight + spacing) / (rowHeight + spacing)))
end

-- The first row shown after scrolling by offset, kept inside [0, total - visible].
function Geometry.ClampOffset(offset, total, visible)
    local maximum = math.max(0, (total or 0) - (visible or 0))
    return math.max(0, math.min(math.floor(tonumber(offset) or 0), maximum))
end

-- Scroll thumb position and length (fractions of the track) for a list, or nil when it all fits.
function Geometry.Thumb(offset, total, visible)
    if not total or not visible or total <= visible then return nil end
    local length = math.max(0.1, visible / total)
    local start = (1 - length) * (offset / math.max(1, total - visible))
    return start, length
end

-- Columns by content width. Tank: enemy and state and you always; who it is on, then the
-- attacker count as room allows. Threat meter: name and threat always; the gap when it fits.
-- into, when given, is filled and returned instead of a new table (layout runs on every resize).
function Geometry.Columns(mode, width, into)
    local columns = into or {}
    columns.name, columns.state, columns.you, columns.on, columns.attackers = nil, nil, nil, nil, nil
    columns.percent, columns.gap = nil, nil
    if mode == "threat" then
        columns.name, columns.percent = true, true
        columns.gap = width >= Geometry.GAP_COLUMN_WIDTH
    else
        columns.name, columns.state, columns.you = true, true, true
        columns.on = width >= 320
        columns.attackers = width >= 420
    end
    return columns
end

local function Overlaps(lowA, highA, lowB, highB, slack)
    return lowA < highB + slack and highA > lowB - slack
end

-- True when two rectangles cover a common area (touching edges do not count).
function Geometry.Intersects(a, b)
    return Overlaps(a.left, a.right, b.left, b.right, 0) and Overlaps(a.bottom, a.top, b.bottom, b.top, 0)
end

-- The closer of the current best (distance, delta, edge, target) and a candidate, within
-- threshold. Plain values, not a table: snapping runs every tick while a window is dragged.
local function Consider(distance, delta, edge, target, candidate, candidateEdge, candidateTarget, threshold)
    local candidateDistance = math.abs(candidate)
    if candidateDistance <= threshold and (not distance or candidateDistance < distance) then
        return candidateDistance, candidate, candidateEdge, candidateTarget
    end
    return distance, delta, edge, target
end

-- Where a window dropped at rect should snap: to another window's edges (side by side or
-- stacked, then lined up along the shared side) or the screen's. Returns dx, dy, the snapped
-- x and y edges (nil when that axis does not snap) and the index in others each axis snapped to
-- (nil for a screen edge).
function Geometry.Snap(rect, others, screenWidth, screenHeight, threshold)
    threshold = threshold or Geometry.SNAP_DISTANCE
    local tolerance = Geometry.TOUCH_TOLERANCE
    local xd, xDelta, xEdge, xTarget, yd, yDelta, yEdge, yTarget
    local count = others and #others or 0
    for index = 1, count do
        local other = others[index]
        if Overlaps(rect.bottom, rect.top, other.bottom, other.top, threshold) then
            xd, xDelta, xEdge, xTarget = Consider(xd, xDelta, xEdge, xTarget, other.right - rect.left, other.right, index, threshold)
            xd, xDelta, xEdge, xTarget = Consider(xd, xDelta, xEdge, xTarget, other.left - rect.right, other.left, index, threshold)
        end
        if Overlaps(rect.left, rect.right, other.left, other.right, threshold) then
            yd, yDelta, yEdge, yTarget = Consider(yd, yDelta, yEdge, yTarget, other.bottom - rect.top, other.bottom, index, threshold)
            yd, yDelta, yEdge, yTarget = Consider(yd, yDelta, yEdge, yTarget, other.top - rect.bottom, other.top, index, threshold)
        end
    end
    -- Lining up comes second: only along a side that already touches or will touch.
    for index = 1, count do
        local other = others[index]
        local dx, dy = xDelta or 0, yDelta or 0
        local touchesSide = math.abs(rect.left + dx - other.right) <= tolerance
            or math.abs(rect.right + dx - other.left) <= tolerance
        local touchesStack = math.abs(rect.top + dy - other.bottom) <= tolerance
            or math.abs(rect.bottom + dy - other.top) <= tolerance
        if touchesSide and not yDelta then
            yd, yDelta, yEdge, yTarget = Consider(yd, yDelta, yEdge, yTarget, other.top - rect.top, other.top, index, threshold)
            yd, yDelta, yEdge, yTarget = Consider(yd, yDelta, yEdge, yTarget, other.bottom - rect.bottom, other.bottom, index,
                threshold)
        end
        if touchesStack and not xDelta then
            xd, xDelta, xEdge, xTarget = Consider(xd, xDelta, xEdge, xTarget, other.left - rect.left, other.left, index, threshold)
            xd, xDelta, xEdge, xTarget = Consider(xd, xDelta, xEdge, xTarget, other.right - rect.right, other.right, index,
                threshold)
        end
    end
    if screenWidth then
        xd, xDelta, xEdge, xTarget = Consider(xd, xDelta, xEdge, xTarget, -rect.left, 0, nil, threshold)
        _, xDelta, xEdge, xTarget = Consider(xd, xDelta, xEdge, xTarget, screenWidth - rect.right, screenWidth, nil, threshold)
    end
    if screenHeight then
        yd, yDelta, yEdge, yTarget = Consider(yd, yDelta, yEdge, yTarget, screenHeight - rect.top, screenHeight, nil, threshold)
        _, yDelta, yEdge, yTarget = Consider(yd, yDelta, yEdge, yTarget, -rect.bottom, 0, nil, threshold)
    end
    return xDelta or 0, yDelta or 0, xEdge, yEdge, xTarget, yTarget
end

-- A window resized from its bottom-right corner: its bottom edge snaps to the bottom of a
-- neighbour it sits beside, and its right edge to the right of a neighbour it is stacked with.
-- Returns the change to the right and bottom edges, the snapped edges and the indexes in others.
function Geometry.SnapSize(rect, others, threshold)
    threshold = threshold or Geometry.SNAP_DISTANCE
    local tolerance = Geometry.TOUCH_TOLERANCE
    local xd, xDelta, xEdge, xTarget, yd, yDelta, yEdge, yTarget
    for index = 1, others and #others or 0 do
        local other = others[index]
        local beside = (math.abs(rect.right - other.left) <= tolerance or math.abs(rect.left - other.right) <= tolerance)
            and Overlaps(rect.bottom, rect.top, other.bottom, other.top, threshold)
        local stacked = (math.abs(rect.bottom - other.top) <= tolerance or math.abs(rect.top - other.bottom) <= tolerance)
            and Overlaps(rect.left, rect.right, other.left, other.right, threshold)
        if beside then
            yd, yDelta, yEdge, yTarget = Consider(yd, yDelta, yEdge, yTarget, other.bottom - rect.bottom, other.bottom, index,
                threshold)
        end
        if stacked then
            xd, xDelta, xEdge, xTarget = Consider(xd, xDelta, xEdge, xTarget, other.right - rect.right, other.right, index,
                threshold)
        end
    end
    return xDelta or 0, yDelta or 0, xEdge, yEdge, xTarget, yTarget
end

-- Where a window of this size may sit so all of it is on a screen of this size (the frames are
-- clamped, so a saved position off screen would not be where the window is drawn).
-- Returns left and top, rounded to whole units.
function Geometry.OnScreen(left, top, width, height, screenWidth, screenHeight)
    left = math.max(0, math.min(left, screenWidth - width))
    top = math.min(screenHeight, math.max(top, height))
    return math.floor(left + 0.5), math.floor(top + 0.5)
end

local function FitsFree(rects, left, top, width, height, screenWidth, screenHeight)
    if left < 0 or top > screenHeight or left + width > screenWidth or top - height < 0 then return false end
    local candidate = Geometry.Rect(left, top, width, height)
    for index = 1, #rects do
        if Geometry.Intersects(candidate, rects[index]) then return false end
    end
    return true
end

local function SameCorner(rects, left, top)
    for index = 1, #rects do
        if math.abs(rects[index].left - left) < 1 and math.abs(rects[index].top - top) < 1 then return true end
    end
    return false
end

-- A top-left for a new window of this size that overlaps none of rects (a list, the last one
-- the newest): right of, below, left of, then above each window from the newest back. With no
-- free spot it cascades from the newest window, clamped to the screen, onto a corner no window
-- already has. Returns left and top.
function Geometry.FreeSpot(rects, width, height, screenWidth, screenHeight)
    for index = #rects, 1, -1 do
        local rect = rects[index]
        local spots = {
            rect.right, rect.top, rect.left, rect.bottom, rect.left - width, rect.top, rect.left, rect.top + height,
        }
        for spot = 1, #spots, 2 do
            if FitsFree(rects, spots[spot], spots[spot + 1], width, height, screenWidth, screenHeight) then
                return spots[spot], spots[spot + 1]
            end
        end
    end
    local last = rects[#rects]
    if not last then return Geometry.OnScreen(0, screenHeight, width, height, screenWidth, screenHeight) end
    local step = Geometry.CASCADE_STEP
    for offset = 1, 40 do
        local left, top = Geometry.OnScreen(last.left + step * offset, last.top - step * offset, width, height,
            screenWidth, screenHeight)
        if not SameCorner(rects, left, top) then return left, top end
    end
    return Geometry.OnScreen(last.left, last.top, width, height, screenWidth, screenHeight)
end

-- True when two rectangles share an edge (they touch and overlap along it).
function Geometry.Touching(a, b, tolerance)
    tolerance = tolerance or Geometry.TOUCH_TOLERANCE
    local sideBySide = (math.abs(a.right - b.left) <= tolerance or math.abs(a.left - b.right) <= tolerance)
        and Overlaps(a.bottom, a.top, b.bottom, b.top, -tolerance)
    local stacked = (math.abs(a.top - b.bottom) <= tolerance or math.abs(a.bottom - b.top) <= tolerance)
        and Overlaps(a.left, a.right, b.left, b.right, -tolerance)
    return sideBySide or stacked
end

-- The keys of every rectangle joined to rects[start] through shared edges (start included).
function Geometry.Group(rects, start)
    local group, queue = { [start] = true }, { start }
    local index = 1
    while queue[index] do
        local current = rects[queue[index]]
        for key, rect in pairs(rects) do
            if not group[key] and Geometry.Touching(current, rect) then
                group[key] = true
                queue[#queue + 1] = key
            end
        end
        index = index + 1
    end
    return group
end

-- Our window beside a Blizzard meter window (or the window before it in a chain of followers):
-- anchor is that rectangle already in UIParent units. Sides: right and left sit level with its
-- top (the titles line up) and take span as the height; above and below take span as the width.
-- span defaults to the anchor's matching size; false keeps the window's own. Returns left, top,
-- width, height.
function Geometry.DockRect(anchor, side, width, height, span)
    local vertical = side == "above" or side == "below"
    if span == nil then span = vertical and anchor.right - anchor.left or anchor.top - anchor.bottom end
    if vertical then
        width = span or width
        if side == "above" then return anchor.left, anchor.top + height, width, height end
        return anchor.left, anchor.bottom, width, height
    end
    height = span or height
    if side == "left" then return anchor.left - width, anchor.top, width, height end
    return anchor.right, anchor.top, width, height
end

-- The side of meter a window at rect has joined: sharing that edge and overlapping along it.
-- nil when it touches no side.
function Geometry.DockSide(rect, meter, tolerance)
    tolerance = tolerance or Geometry.TOUCH_TOLERANCE
    local alongY = Overlaps(rect.bottom, rect.top, meter.bottom, meter.top, -tolerance)
    local alongX = Overlaps(rect.left, rect.right, meter.left, meter.right, -tolerance)
    if alongY and math.abs(rect.left - meter.right) <= tolerance then return "right" end
    if alongY and math.abs(rect.right - meter.left) <= tolerance then return "left" end
    if alongX and math.abs(rect.bottom - meter.top) <= tolerance then return "above" end
    if alongX and math.abs(rect.top - meter.bottom) <= tolerance then return "below" end
    return nil
end
