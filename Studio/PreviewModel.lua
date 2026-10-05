local _, PS = ...
local L = PS.L
local Options = assert(PS.Options, "PlateSmith editor model missing")

-- A 3D model behind Studio's preview plate (View › Model): you, your target or a creature,
-- so the plate can be judged over a body. A Studio view preference (state.studioPreviewModel), never
-- in a profile or Blueprint. The model frame is made on first use, so Off costs nothing; every model
-- call is pcalled, and a client without models says so instead.
local PreviewModel = { api = "none", lastError = "none" }
Options.editorPreviewModel = PreviewModel

-- Hogger (a gnoll), in every Classic-era client.
PreviewModel.CREATURE_DISPLAY = 384
-- The model's full rect in stage units, so it keeps one proportion to the plate at every zoom. In game
-- a health bar (BAR_WIDTH, the default plate's) is about 1.5 times a body's shoulders and a third of
-- its height: the frame is three bars tall (the full-body camera fits the body to its height) and
-- WIDE times that across, room for a weapon or a spell's glow held out to the side. Its top is GAP
-- under the plate's lowest part.
PreviewModel.BAR_WIDTH, PreviewModel.GAP, PreviewModel.WIDE = 112, 4, 0.8
PreviewModel.HEIGHT = 3 * PreviewModel.BAR_WIDTH
PreviewModel.WIDTH = PreviewModel.WIDE * PreviewModel.HEIGHT
PreviewModel.CAMERA_DISTANCE = 1
-- The client draws a model outside its parents' clip rects but cuts it at its own frame. So the frame
-- is the part of the full rect inside the free preview, and the view is moved back over the full rect
-- (clipMethod: "insets" or "translation"), which cuts the body at the preview's edges without
-- shrinking it. A client with neither ("none") gets the whole frame inside the preview, smaller where
-- it does not fit, and hidden under MIN_HEIGHT.
PreviewModel.MIN_HEIGHT = 80
PreviewModel.clipMethod = "none"
-- Chrome's LayoutEditorPreviewPanel: plate-type tabs and the design row at the top (it ends 84 down),
-- the zoom, Snap, Test values and nudge row at the foot, the friendly layout switch above it.
PreviewModel.INSETS = { left = 12, right = 12, top = 90, bottom = 53, switch = 92, panelGap = 6 }

local function Rect(left, right, top, bottom) return { left = left, right = right, top = top, bottom = bottom } end

-- Where the model goes (canvas units from the canvas centre, y up). zoom and pan are the stage's;
-- plateBottom is the plate's lowest shown part (stage units); area is EditorModelArea; crop says the
-- client can cut the view at the frame. Returns full (the whole model's rect), visible (the frame:
-- full inside area), cut (how much of full each side lost) and fit (visible's share of full's size
-- without crop); or nil and why nothing would show.
function PreviewModel.Geometry(zoom, panX, panY, plateBottom, area, crop)
    local x, top = panX * zoom, (panY + plateBottom - PreviewModel.GAP) * zoom
    local width, height = PreviewModel.WIDTH * zoom, PreviewModel.HEIGHT * zoom
    if crop then
        local full = Rect(x - width / 2, x + width / 2, top, top - height)
        local visible = Rect(math.max(full.left, area.left), math.min(full.right, area.right),
            math.min(full.top, area.top), math.max(full.bottom, area.bottom))
        if visible.right <= visible.left or visible.top <= visible.bottom then return nil, "outside" end
        return { full = full, visible = visible, fit = 1, cut = Rect(visible.left - full.left, full.right - visible.right,
            full.top - visible.top, visible.bottom - full.bottom) }
    end
    if top > area.top or top <= area.bottom or x <= area.left or x >= area.right then return nil, "outside" end
    local fit = math.min(1, (top - area.bottom) / height, 2 * (x - area.left) / width, 2 * (area.right - x) / width)
    if height * fit < PreviewModel.MIN_HEIGHT then return nil, "no-room" end
    local placed = Rect(x - width * fit / 2, x + width * fit / 2, top, top - height * fit)
    return { full = placed, visible = placed, fit = fit, cut = Rect(0, 0, 0, 0) }
end

local function Size(area) return math.max(0, area.right - area.left) * math.max(0, area.top - area.bottom) end

-- The free part of the preview the model may use (canvas units from its centre, y up): under the design
-- row and above the foot. An open Test values panel (rising from the foot) takes the larger free part
-- beside it or above it.
function Options:EditorModelArea()
    local canvas, insets = self.editorCanvas, PreviewModel.INSETS
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local switch = false
    for _, button in pairs(self.editorFriendlyViewButtons or {}) do switch = switch or button:IsShown() == true end
    local area = Rect(-width / 2 + insets.left, width / 2 - insets.right, height / 2 - insets.top,
        -height / 2 + (switch and insets.switch or insets.bottom))
    local panel, layout = self.editorTestPanel, self.editorPreviewLayout
    if not (panel and panel:IsShown() and layout) then return area end
    local left = -width / 2 + (self.editorTestPanelLeft or insets.left)
    local right, top = left + panel:GetWidth(), -height / 2 + layout.footY - layout.panelGap + panel:GetHeight()
    local gap, best = insets.panelGap, nil
    for _, part in ipairs({
        Rect(area.left, area.right, area.top, math.max(area.bottom, top + gap)),
        Rect(area.left, math.min(area.right, left - gap), area.top, area.bottom),
        Rect(math.max(area.left, right + gap), area.right, area.top, area.bottom),
    }) do
        if not best or Size(part) > Size(best) then best = part end
    end
    return best
end

Options.editorModelChoices = {
    { value = "off", label = L["Off"] },
    { value = "player", label = L["You"] },
    { value = "target", label = L["Target"] },
    { value = "creature", label = L["Creature"] },
}

function Options:EditorModelChoice()
    local state = PS.GetState and PS.GetState()
    local choice = state and state.studioPreviewModel
    for _, entry in ipairs(self.editorModelChoices) do
        if entry.value == choice then return choice end
    end
    return "off"
end

-- method on the model, pcalled: true, or false and why (a missing method included).
local function Call(model, method, ...)
    local callback = model[method]
    if type(callback) ~= "function" then return false, method .. " unavailable" end
    local ok, reason = pcall(callback, model, ...)
    if not ok then return false, tostring(reason) end
    return true
end

-- How this client can cut the model's view at its frame (PreviewModel.clipMethod). Insets are tried
-- with negative values and read back where the client can: a client that clamps them is not trusted.
local function ClipMethod(frame)
    if Call(frame, "SetViewInsets", -1, -2, -3, -4) then
        local read = type(frame.GetViewInsets) ~= "function"
        if not read then
            local ok, left, right, top, bottom = pcall(frame.GetViewInsets, frame)
            read = ok and type(left) == "number" and type(right) == "number" and type(top) == "number"
                and type(bottom) == "number" and math.abs(left + 1) < 0.01 and math.abs(right + 2) < 0.01
                and math.abs(top + 3) < 0.01 and math.abs(bottom + 4) < 0.01
        end
        Call(frame, "SetViewInsets", 0, 0, 0, 0)
        if read then return "insets" end
    end
    if Call(frame, "SetViewTranslation", 0, 0) then return "translation" end
    return "none"
end

local function Fail(reason)
    PreviewModel.lastError = reason
    PreviewModel.note = L["Not available on this client."]
    if PreviewModel.frame then PreviewModel.frame:Hide() end
end

-- The PlayerModel on the canvas at the stage's level, under every part (they sit above it). It does
-- not take the zoom's scale: a model drawn under a scaled parent grew faster than its frame and was
-- cut at the frame's top, so its frame is sized from the zoom instead (PlaceEditorModel). A client
-- without one is remembered, so it is not tried on every refresh.
local function ModelFrame(canvas, stage)
    if PreviewModel.frame or PreviewModel.api == "unavailable" then return PreviewModel.frame end
    local ok, frame = pcall(CreateFrame, "PlayerModel", nil, canvas)
    if not ok or type(frame) ~= "table" or type(frame.SetUnit) ~= "function" then
        PreviewModel.api = "unavailable"
        Fail(not ok and tostring(frame) or "PlayerModel unavailable")
        if ok and type(frame) == "table" and frame.Hide then frame:Hide() end
        return nil
    end
    PreviewModel.api = "PlayerModel"
    PreviewModel.frame = frame
    PreviewModel.clipMethod = ClipMethod(frame)
    Call(frame, "SetIgnoreParentScale", true)
    Call(frame, "SetScale", 1)
    frame:SetSize(PreviewModel.WIDTH, PreviewModel.HEIGHT)
    frame:SetFrameLevel(stage:GetFrameLevel())
    -- Only a backdrop: clicks, drags and the wheel go through it to the preview and its parts.
    frame:EnableMouse(false)
    Call(frame, "EnableMouseWheel", false)
    frame:Hide()
    return frame
end

-- The model's note on the preview, under View.
function Options:RefreshEditorModelNote()
    if not self.editorModelNote then return end
    local hidden = PreviewModel.shown and not PreviewModel.geometry
    self.editorModelNote:SetText(hidden and L["No room here: zoom out or pan to see the model."] or PreviewModel.note or "")
end

-- Under the lowest shown part (the plate's centre when nothing below it is shown), from the zoom and
-- pan (PreviewModel.Geometry), or hidden. keepBottom: only the zoom, pan or preview size changed.
function Options:PlaceEditorModel(keepBottom)
    local frame, canvas = PreviewModel.frame, self.editorCanvas
    if not (frame and PreviewModel.shown and self.editorPreviewStage and canvas) then return end
    -- The Enemy players gate (DesignRow.lua) leaves the preview empty.
    if self.editorPlayersGated then
        frame:Hide()
        return
    end
    if not (keepBottom and PreviewModel.plateBottom) then
        local bottom = 0
        for key in pairs(self.editorComponents or {}) do
            local _, y, _, halfHeight = self:EditorComponentBounds(key)
            if y and y - halfHeight < bottom then bottom = y - halfHeight end
        end
        PreviewModel.plateBottom = bottom
    end
    local method = PreviewModel.clipMethod
    local geometry, why = PreviewModel.Geometry(self.editorPreviewZoom or 1, self.editorPreviewPanX or 0,
        self.editorPreviewPanY or 0, PreviewModel.plateBottom, self:EditorModelArea(), method ~= "none")
    PreviewModel.geometry, PreviewModel.hiddenBy = geometry, why
    if not geometry then
        frame:Hide()
        self:RefreshEditorModelNote()
        return
    end
    -- Canvas units to the model's own (it ignores its parents' scale where the client can).
    local canvasScale, ownScale = canvas:GetEffectiveScale(), frame:GetEffectiveScale()
    local units = type(canvasScale) == "number" and type(ownScale) == "number" and canvasScale > 0
        and ownScale > 0 and canvasScale / ownScale or 1
    local full, visible, cut = geometry.full, geometry.visible, geometry.cut
    local ok, reason = true, nil
    if method == "insets" then
        -- The client's view is the frame less its insets (Blizzard's ScriptAnimatedModelScene:GetSceneSize),
        -- so negative insets grow it back to the full rect, and the frame cuts what is outside.
        ok, reason = Call(frame, "SetViewInsets", -cut.left * units, -cut.right * units, -cut.top * units,
            -cut.bottom * units)
    elseif method == "translation" then
        -- A view the frame's size: the camera comes closer by the share of the height that is shown, and
        -- the view moves to where the full rect's centre is.
        local shown = (visible.top - visible.bottom) / (full.top - full.bottom)
        ok, reason = Call(frame, "SetViewTranslation", ((full.left + full.right) - (visible.left + visible.right)) / 2 * units,
            ((full.top + full.bottom) - (visible.top + visible.bottom)) / 2 * units)
        if ok then ok, reason = Call(frame, "SetCamDistanceScale", PreviewModel.CAMERA_DISTANCE * shown) end
    end
    if not ok then
        -- This client refused it after all: the next method down, placed again.
        PreviewModel.lastError = reason
        PreviewModel.clipMethod = method == "insets" and "translation" or "none"
        Call(frame, "SetViewInsets", 0, 0, 0, 0)
        Call(frame, "SetViewTranslation", 0, 0)
        Call(frame, "SetCamDistanceScale", PreviewModel.CAMERA_DISTANCE)
        return self:PlaceEditorModel(true)
    end
    frame:SetSize((visible.right - visible.left) * units, (visible.top - visible.bottom) * units)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", canvas, "CENTER", visible.left * units, visible.top * units)
    frame:Show()
    self:RefreshEditorModelNote()
end

-- Shows the chosen model (or hides it). Target without a target, or a creature the client refuses,
-- shows you instead with a note.
function Options:ApplyEditorModel()
    local choice = self:EditorModelChoice()
    PreviewModel.note, PreviewModel.shown, PreviewModel.geometry, PreviewModel.hiddenBy = nil, nil, nil, nil
    if choice == "off" then
        if PreviewModel.frame then PreviewModel.frame:Hide() end
    elseif self.editorPreviewStage and self.editorCanvas then
        local frame = ModelFrame(self.editorCanvas, self.editorPreviewStage)
        if frame then
            local ok, reason, unit = false, nil, "player"
            if choice == "creature" then
                ok, reason = Call(frame, "SetDisplayInfo", PreviewModel.CREATURE_DISPLAY)
                if ok then
                    unit = PreviewModel.CREATURE_DISPLAY
                else
                    PreviewModel.lastError, PreviewModel.note = reason, L["No creature here: showing you."]
                end
            elseif choice == "target" then
                if PS.Secret.ReadBoolean(UnitExists, "target") == true then
                    unit = "target"
                else
                    PreviewModel.note = L["No target: showing you."]
                end
            end
            if not ok then ok, reason = Call(frame, "SetUnit", unit) end
            if ok then
                PreviewModel.shown = unit
                frame:Show()
                Call(frame, "SetFacing", 0)
                -- The whole body, centred, at the client's own distance (CAMERA_DISTANCE scales it).
                Call(frame, "SetPortraitZoom", 0)
                Call(frame, "SetCamDistanceScale", PreviewModel.CAMERA_DISTANCE)
                Call(frame, "SetPosition", 0, 0, 0)
                self:PlaceEditorModel()
            else
                Fail(reason)
            end
        else
            PreviewModel.note = L["Not available on this client."]
        end
    end
    self:RefreshEditorModelNote()
end

function Options:SetEditorModel(choice)
    local state = PS.GetState and PS.GetState()
    if not state then return false end
    local valid = false
    for _, entry in ipairs(self.editorModelChoices) do valid = valid or entry.value == choice end
    if not valid then return false end
    state.studioPreviewModel = choice
    self:ApplyEditorModel()
    return true
end

-- /ps diagnose: report.studio.model.
function Options:EditorModelReport()
    local report = { choice = self:EditorModelChoice(), api = PreviewModel.api, created = PreviewModel.frame ~= nil,
        shown = PreviewModel.shown or "none", lastError = PreviewModel.lastError,
        clipMethod = PreviewModel.frame and PreviewModel.clipMethod or "none" }
    local geometry = PreviewModel.geometry
    if PreviewModel.shown then
        report.zoom = self.editorPreviewZoom
        report.plateBottom = PreviewModel.plateBottom
        if geometry then
            local full, visible, cut = geometry.full, geometry.visible, geometry.cut
            report.full = Rect(full.left, full.right, full.top, full.bottom)
            report.visible = Rect(visible.left, visible.right, visible.top, visible.bottom)
            report.cut = Rect(cut.left, cut.right, cut.top, cut.bottom)
            report.fit = geometry.fit
        else
            report.placed = "hidden: " .. tostring(PreviewModel.hiddenBy)
        end
        local frame = PreviewModel.frame
        report.effectiveScale = frame and PS.Secret.ReadNumber(frame, "GetEffectiveScale") or "unavailable"
    end
    return report
end
