-- Hovering an Objects plate's name: the game's interaction cursor for the object, and a small tooltip (its name, its
-- type and the Status text's line when known). The game sets no mouseover for a plate, so each object plate gets one
-- frame of its own over its Backdrop when that wraps the name, else the Name part's box (else the name), that takes
-- mouse motion only: SetMouseMotionEnabled(true) and SetMouseClickEnabled(false), never EnableMouse, so a left-click
-- still opens the object and right-drag still turns the camera (live, Forever 1.60.1.70338). It sits on UIParent
-- (anchored, never measured: plates cannot be), is made
-- the first time its plate wants it and stays with that plate; hidden with its motion off when the plate goes, stops
-- being an object or the settings turn it off. Event-driven only: OnEnter, OnLeave and combat starting.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local ActionIcon = assert(PS.ActionIcon, "PlateSmith ActionIcon missing")
local ObjectStatus = assert(PS.ObjectStatus, "PlateSmith ObjectStatus missing")
local L = PS.L
local IsReadable, HasValue = Secret.IsReadable, Secret.HasValue

local ObjectHover = {}
PS.ObjectHover = ObjectHover
-- Combat starting takes the cursor and tooltip down; nothing shows on hover until it ends.
ObjectHover.EVENT = "PLAYER_REGEN_DISABLED"
ObjectHover.NAME_COLOUR = { 1, 0.82, 0 }
ObjectHover.TYPE_COLOUR = { 0.8, 0.8, 0.8 }

-- SetCursor's tokens for the client's cursor names (ActionIcon's: lower case, without Unable), as the client's own
-- table names them: <TOKEN>_CURSOR, and <TOKEN>_ERROR_CURSOR for the greyed "can't" one (Blizzard's merchant frame
-- uses BUY_ERROR_CURSOR). Live, Forever takes the token form (INTERACT_CURSOR, MAIL_CURSOR) and refuses a cursor path
-- or bare name; a name not here is tried as its upper case.
ObjectHover.TOKENS = { interact = "INTERACT", inspect = "INSPECT", gatherherbs = "GATHER", mine = "MINE",
    lootall = "LOOT_ALL", picklock = "LOCK", skin = "SKIN", skinalliance = "SKIN_ALLIANCE", skinhorde = "SKIN_HORDE",
    quest = "QUEST", questrepeatable = "QUEST_REPEATABLE", questturnin = "QUEST_TURNIN", speak = "SPEAK", mail = "MAIL",
    buy = "BUY", taxi = "TAXI", trainer = "TRAINER", repair = "REPAIR", repairnpc = "REPAIRNPC",
    innkeeper = "INNKEEPER", pickup = "PICKUP", point = "POINT", cast = "CAST", attack = "ATTACK", item = "ITEM" }

-- What SetCursor is offered for a cursor, in order: the token, then the icon's own file. The Unable one's forms are
-- its error token and Unable file; when none is taken, the in-range cursor's is used rather than none.
function ObjectHover.Forms(name, unable)
    local token = ObjectHover.TOKENS[name] or name:upper()
    if unable then
        return { token .. "_ERROR_CURSOR", "Interface\\Cursor\\Unable" .. name .. ".blp" }
    end
    return { token .. "_CURSOR", "Interface\\Cursor\\" .. name .. ".blp" }
end

-- The form each cursor took this session ("mail", "unablemail"), or false when it took none.
local chosen = {}
ObjectHover._chosen = chosen

-- SetCursor with value: taken unless it errors or answers a readable false.
local function Try(value)
    local ok, result = pcall(SetCursor, value)
    return ok and not (IsReadable(result) and result == false)
end

-- Sets the cursor for name (Unable or not): the form taken, or nil when there is none.
local function SetFor(name, unable)
    if type(SetCursor) ~= "function" then return nil end
    local key = unable and "unable" .. name or name
    local form = chosen[key]
    if form and not Try(form) then form = nil end
    if form == nil then
        form = false
        for _, value in ipairs(ObjectHover.Forms(name, unable)) do
            if Try(value) then
                form = value
                break
            end
        end
        chosen[key] = form
    end
    if form then return form end
    if unable then return SetFor(name, false) end
    return nil
end
ObjectHover.SetCursor = SetFor

-- The plate side. context: active (unit -> plate), GetSettings, EntryID (the plate's readable object ID).
PS._CreatePlateObjectHover = function(context)
    local active, GetSettings, EntryID = context.active, context.GetSettings, context.EntryID
    local Pass = { wanted = false, entered = nil, supported = nil, frames = 0, active = active }
    local events = CreateFrame("Frame")
    Pass.events = events

    -- The region a plate's frame covers: the Backdrop when it fits round the name (Backdrop.lua; made with the plate's
    -- layout), the Name part's box behind when its style has one, else the name.
    local function Region(data)
        if PS.Backdrop.WrapsName(data) then return data.backdrop end
        local boxes = data.styleBoxes
        local box = boxes and boxes.name
        if box and box.plateSmithText == data.name then return box end
        return data.name
    end

    local function OwnsTooltip(tooltip, frame)
        if type(tooltip.IsOwned) ~= "function" then return true end
        local ok, owned = pcall(tooltip.IsOwned, tooltip, frame)
        return not ok or not IsReadable(owned) or owned == true
    end

    local function Leave(frame)
        if Pass.entered == frame then Pass.entered = nil end
        if frame.plateSmithCursor then
            frame.plateSmithCursor = nil
            if type(ResetCursor) == "function" then pcall(ResetCursor) end
        end
        if frame.plateSmithTooltip then
            frame.plateSmithTooltip = nil
            local tooltip = rawget(_G, "GameTooltip")
            if type(tooltip) == "table" and OwnsTooltip(tooltip, frame) then pcall(tooltip.Hide, tooltip) end
        end
    end
    Pass.Leave = Leave

    -- The tooltip's title: the unit's name when readable, else the plate's own name text (which a display sink takes
    -- even when Lua may not read it), else "Object".
    local function Title(tooltip, data)
        local colour = ObjectHover.NAME_COLOUR
        local name = Secret.ReadName(data.unit)
        if name and pcall(tooltip.SetText, tooltip, name, colour[1], colour[2], colour[3]) then return end
        local region = data.name
        if region and type(region.GetText) == "function" then
            local ok, text = pcall(region.GetText, region)
            if ok and HasValue(text) and not (IsReadable(text) and text == "")
                and pcall(tooltip.SetText, tooltip, text, colour[1], colour[2], colour[3]) then return end
        end
        tooltip:SetText(L["Object"], colour[1], colour[2], colour[3])
    end

    local function Fill(tooltip, frame, data, kind, unable)
        tooltip:SetOwner(frame, "ANCHOR_CURSOR")
        Title(tooltip, data)
        local objectType = kind and ActionIcon.TYPE_OF[kind]
        local label = objectType and PS.Designs.TYPE_LABELS[objectType]
        if label then
            local colour = ObjectHover.TYPE_COLOUR
            tooltip:AddLine(label, colour[1], colour[2], colour[3])
        end
        local id = EntryID(data)
        local text, colourKey = ObjectStatus.Text(id, unable, kind, id and data.entryGUID)
        if text then
            local colour = ObjectStatus.COLOURS[colourKey] or ObjectStatus.COLOURS.plain
            tooltip:AddLine(text, colour[1], colour[2], colour[3])
            local yours, hint = ObjectStatus.SkillDetail(id)
            local plain = ObjectStatus.COLOURS.plain
            if yours then tooltip:AddLine(yours, plain[1], plain[2], plain[3]) end
            if hint then tooltip:AddLine(hint, colour[1], colour[2], colour[3]) end
        end
        tooltip:Show()
    end

    local function ShowTooltip(frame, data, kind, unable)
        local tooltip = rawget(_G, "GameTooltip")
        if type(tooltip) ~= "table" or type(tooltip.SetOwner) ~= "function" then return false end
        -- These lines are PlateSmith's, not the game's object tooltip: the Status capture skips them.
        ObjectStatus.paused = true
        local ok = pcall(Fill, tooltip, frame, data, kind, unable)
        ObjectStatus.paused = nil
        return ok
    end

    local function Enter(frame)
        local data = frame.plateSmithData
        if not (Pass.wanted and data and data.objectHover == frame and data.unit and data.object) then return end
        -- In combat nothing changes the cursor or shows a tooltip.
        if Secret.InCombat() then return end
        -- The name not showing (empty, or its plate hidden since it was laid out): nothing to point at.
        local region = frame.plateSmithRegion
        if not region then return end
        local okVisible, visible = pcall(region.IsVisible, region)
        if not (okVisible and IsReadable(visible) and visible == true) then return end
        if Pass.entered and Pass.entered ~= frame then Leave(Pass.entered) end
        Pass.entered = frame
        local db = GetSettings()
        local name, unable, kind = ActionIcon.PeekCursor(data.unit)
        if db.objectHoverCursor == true and name then
            frame.plateSmithCursor = SetFor(name, unable) ~= nil or nil
        end
        if db.objectHoverTooltip == true then
            frame.plateSmithTooltip = ShowTooltip(frame, data, kind, unable) or nil
        end
    end

    local function OnEnter(frame) pcall(Enter, frame) end
    local function OnLeave(frame) pcall(Leave, frame) end
    Pass.OnEnter, Pass.OnLeave = OnEnter, OnLeave

    -- A frame that takes mouse motion and never clicks; nil (asked once) where the client cannot make one.
    local function Make(data)
        if Pass.supported == false or type(CreateFrame) ~= "function" then return nil end
        local frame = CreateFrame("Frame", nil, UIParent)
        Pass.supported = type(frame.SetMouseMotionEnabled) == "function" and type(frame.SetMouseClickEnabled) == "function"
        if not Pass.supported then
            frame:Hide()
            return nil
        end
        frame:SetMouseClickEnabled(false)
        frame:SetMouseMotionEnabled(false)
        frame:SetFrameStrata("BACKGROUND")
        frame:SetScript("OnEnter", OnEnter)
        frame:SetScript("OnLeave", OnLeave)
        frame:Hide()
        data.objectHover = frame
        Pass.frames = Pass.frames + 1
        return frame
    end

    function Pass.Release(data)
        local frame = data.objectHover
        if not frame then return end
        if Pass.entered == frame then Leave(frame) end
        if frame:IsShown() then
            frame:Hide()
            pcall(frame.SetMouseMotionEnabled, frame, false)
        end
        frame.plateSmithData = nil
    end

    local function Wanted(data)
        local layout = data.layout
        return Pass.wanted and data.object == true and data.own == true and data.unit ~= nil and layout ~= nil
            and layout.name ~= nil and layout.name.visible ~= false
    end

    -- A plate was laid out: its frame placed over its name and shown, or released.
    function Pass.Update(data)
        if not Wanted(data) then return Pass.Release(data) end
        local frame = data.objectHover or Make(data)
        if not frame then return end
        local region = Region(data)
        if frame.plateSmithRegion ~= region then
            if Pass.entered == frame then Leave(frame) end
            frame:ClearAllPoints()
            frame:SetAllPoints(region)
            frame.plateSmithRegion = region
        end
        frame.plateSmithData = data
        if not frame:IsShown() then
            frame:SetMouseClickEnabled(false)
            frame:SetMouseMotionEnabled(true)
            frame:Show()
        end
    end

    events:SetScript("OnEvent", function()
        if Pass.entered then OnLeave(Pass.entered) end
    end)

    -- On while PlateSmith draws objects and the hover cursor or tooltip is on (Schema.HoverNeeded). Off: every frame
    -- released, the combat event dropped.
    function Pass.SetWanted(wanted)
        wanted = wanted and true or false
        if wanted == Pass.wanted then return end
        Pass.wanted = wanted
        if wanted then
            PS._RegisterEvent(events, ObjectHover.EVENT, "platesmith.object-hover")
        else
            if type(events.UnregisterEvent) == "function" then pcall(events.UnregisterEvent, events, ObjectHover.EVENT) end
            for _, data in pairs(active) do Pass.Release(data) end
        end
    end

    ObjectHover._pass = Pass
    return Pass
end

-- For /ps diagnose (context.objectHover): whether it runs, whether the client can make a motion-only frame, the frames
-- made and shown, and the kind of SetCursor form each cursor took ("token", "unable-token", "file" or "none"; never
-- the token itself, whose "ERROR" the summary would flag).
function ObjectHover.Report()
    local pass = ObjectHover._pass
    local shown = 0
    for _, data in pairs(pass and pass.active or {}) do
        if data.objectHover and data.objectHover:IsShown() then shown = shown + 1 end
    end
    local forms = {}
    for key, form in pairs(chosen) do
        forms[key] = not form and "none" or form:find("_ERROR_CURSOR$") and "unable-token"
            or form:find("_CURSOR$") and "token" or "file"
    end
    return { wanted = pass ~= nil and pass.wanted or false, cursorApi = type(SetCursor) == "function" and "readable"
        or "unavailable", motionOnly = pass == nil and "unknown" or pass.supported == nil and "unknown"
        or pass.supported and "readable" or "unavailable", made = pass and pass.frames or 0, shown = shown, forms = forms }
end
