local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local Media = assert(PS.Media, "PlateSmith Media missing")

-- The one owner of Blizzard's shared nameplate font objects (docs/STANDARDS.md section 3 exception).
-- Blizzard draws the names on its own plates, including friendly plates in dungeons, with these
-- objects; changing one of them leaves plates on the others at a different size, so every object
-- this client has is changed together. Each original is captured once, before the first change,
-- and put back exactly when nothing wants a change any more.
local NativeFonts = {}
PS.NativeFonts = NativeFonts

-- Globals checked; a client without one skips it, and an alias of one already listed is changed once.
-- Reported in /ps diagnose; only WRITTEN are changed.
NativeFonts.OBJECTS = {
    "SystemFont_NamePlate", "SystemFont_NamePlateFixed", "SystemFont_LargeNamePlate",
    "SystemFont_LargeNamePlateFixed", "SystemFont_NamePlate_Outlined",
    "NamePlateFixed", "LargeNamePlate", "LargeNamePlateFixed",
}
-- The objects Blizzard's plates draw names with (the name inherits SystemFont_NamePlate and is set
-- to the _Outlined one above the health bar). The Fixed and Large objects are legacy ones no plate
-- uses; the client keeps the Fixed ones at their fixed height whatever is written.
local WRITTEN = { SystemFont_NamePlate = true, SystemFont_NamePlate_Outlined = true }
NativeFonts.OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
-- The readable outdoor treatment (nativeNameFont): at least this size, outlined, Blizzard's face.
NativeFonts.READABLE_SIZE = 13
local BACKSTOP_TICKER = "platesmith.native-fonts"
local BACKSTOP_INTERVAL = 2
local SIZE_TOLERANCE = 0.5

-- name -> { object, path, size, flags }: nil (never false) when nothing was captured.
local captured = {}
-- name -> { path, size, flags } last written, so an unchanged refresh writes nothing.
local written = {}
-- name -> true: the client did not keep the size written even straight after a re-apply.
local unsettled = {}
local mode -- nil, "readable" or "custom"
local reapplyScheduled = false

local function Settings()
    return type(PS.GetSettings) == "function" and PS.GetSettings() or nil
end

local function InInstance()
    local policy = PS.NamePolicy
    return policy ~= nil and policy.InGroupInstance() == true
end

-- What the settings want here: "custom" (the chosen Blizzard name font), "readable" (outdoors
-- only) or nil (Blizzard's own). The chosen font wins wherever it applies, so the two never fight.
function NativeFonts.Wanted(settings, inInstance)
    if type(settings) ~= "table" or settings.enabled == false then return nil end
    if settings.blizzardNameFont == true and (settings.blizzardNameFontScope == "everywhere" or inInstance) then
        return "custom"
    end
    if settings.nativeNameFont == true and not inInstance then return "readable" end
    return nil
end

local function Usable(object)
    return type(object) == "table" and type(object.GetFont) == "function" and type(object.SetFont) == "function"
end

-- path, size and flags now, or nil when the client does not answer with readable values.
local function Read(object)
    local ok, path, size, flags = pcall(object.GetFont, object)
    if not ok or not Secret.IsReadable(path) or not Secret.IsReadable(size) or not Secret.IsReadable(flags) then
        return nil
    end
    if type(path) ~= "string" or type(size) ~= "number" or size ~= size then return nil end
    return path, size, type(flags) == "string" and flags or ""
end

-- The objects this client has, each once, in OBJECTS order (names and objects), refilled per pass.
local seen, names, objects = {}, {}, {}
local function CollectObjects()
    for key in pairs(seen) do seen[key] = nil end
    local count = 0
    for _, name in ipairs(NativeFonts.OBJECTS) do
        local object = _G[name]
        if WRITTEN[name] and Usable(object) and not seen[object] then
            seen[object] = true
            count = count + 1
            names[count], objects[count] = name, object
        end
    end
    for index = count + 1, #names do names[index], objects[index] = nil, nil end
    return count
end

local function Capture(name, object)
    local record = captured[name]
    if record then return record end
    local path, size, flags = Read(object)
    -- An original that cannot be read could not be put back, so that object is left alone.
    if not path then return nil end
    record = { object = object, path = path, size = size, flags = flags }
    captured[name] = record
    return record
end

-- The original's flags other than its outline (SLUG, the client's text renderer; FIXEDHEIGHT, a
-- font drawn at a large size and scaled down), kept on every write: dropping them changes how the
-- client draws the names.
local function OtherFlags(flags)
    local kept = {}
    for token in string.gmatch(string.upper(flags or ""), "[%w]+") do
        if token ~= "OUTLINE" and token ~= "THICKOUTLINE" and token ~= "THICK" then kept[#kept + 1] = token end
    end
    return kept
end
local function JoinFlags(outline, flags)
    local parts = OtherFlags(flags)
    if outline ~= "" then table.insert(parts, 1, outline) end
    return table.concat(parts, ", ")
end

local function Target(settings, record)
    if mode == "custom" then
        local S = PS.ProfileSchema
        local range = S and S.settingRanges and S.settingRanges.blizzardNameFontSize or { 8, 20, true }
        local size = S and S.Bounded(range, settings.blizzardNameFontSize, 12) or 12
        return Media.FontPath(settings.blizzardNameFontFace) or record.path, size,
            JoinFlags(NativeFonts.OUTLINES[settings.blizzardNameFontOutline] or "OUTLINE", record.flags)
    end
    return record.path, math.max(record.size, NativeFonts.READABLE_SIZE), JoinFlags("OUTLINE", record.flags)
end

-- force: Blizzard gives each name its own text height on every plate add and options pass, over
-- the object's size; only a real change of the object makes the client lay its names out again, so
-- a forced write sets a different size first, then the target (what Plater and EUI do).
local function Write(name, object, path, size, flags, force)
    local last = written[name]
    if not force and last and last[1] == path and last[2] == size and last[3] == flags then return end
    if force then pcall(object.SetFont, object, path, size + 1, flags) end
    if pcall(object.SetFont, object, path, size, flags) then
        written[name] = { path, size, flags }
    end
end

local function OutlineKind(flags)
    flags = string.upper(flags or "")
    if flags:find("THICK", 1, true) then return "thick" end
    if flags:find("OUTLINE", 1, true) then return "outline" end
    return "none"
end

-- Whether the object still holds what was written (size and outline; the face path may come back
-- spelled differently).
local function Kept(name, object)
    local last = written[name]
    if not last then return true end
    local _, size, flags = Read(object)
    if not size then return true end
    return math.abs(size - last[2]) <= SIZE_TOLERANCE and OutlineKind(flags) == OutlineKind(last[3])
end

local ScheduleReapply
local hooked = {}
-- Blizzard sets these objects again when its plate options change (the nameplate size, a scale
-- CVar, the screen size), and sometimes a moment later; each re-application runs next frame and
-- 0.1 s later (what Threat Plates does). The hooks run after Blizzard's function and only schedule.
local function HookDriver()
    local driver = _G.NamePlateDriverFrame
    if type(hooksecurefunc) ~= "function" or type(driver) ~= "table" then return end
    for _, method in ipairs({ "UpdateNamePlateOptions", "UpdateNamePlateSize" }) do
        if not hooked[method] and type(driver[method]) == "function" then
            hooked[method] = pcall(hooksecurefunc, driver, method, function() ScheduleReapply() end)
        end
    end
    -- Each plate add re-stamps that name's height; in instances (where the names are Blizzard's own
    -- and cannot be sized one by one) the objects are re-asserted once per frame after adds.
    if not hooked.OnNamePlateAdded and type(driver.OnNamePlateAdded) == "function" then
        hooked.OnNamePlateAdded = pcall(hooksecurefunc, driver, "OnNamePlateAdded", function()
            if mode and InInstance() then NativeFonts.AfterAdd() end
        end)
    end
end

-- Puts every captured original back exactly and forgets it (a later change captures afresh).
function NativeFonts.Restore()
    for name, record in pairs(captured) do
        pcall(record.object.SetFont, record.object, record.path, record.size, record.flags)
        captured[name], written[name], unsettled[name] = nil, nil, nil
    end
    mode = nil
    if PS.Ticker then PS.Ticker.SetEnabled(BACKSTOP_TICKER, false) end
end

-- Applies what the settings (default: the working copy) want here. force writes even an unchanged
-- font, for after Blizzard reset the objects.
function NativeFonts.Apply(settings, force)
    settings = settings or Settings()
    local wanted = NativeFonts.Wanted(settings, InInstance())
    if not wanted then
        NativeFonts.Restore()
        return nil
    end
    local changed = wanted ~= mode
    mode = wanted
    for index = 1, CollectObjects() do
        local name, object = names[index], objects[index]
        local record = Capture(name, object)
        if record then
            local path, size, flags = Target(settings, record)
            Write(name, object, path, size, flags, force or changed)
        end
    end
    HookDriver()
    if PS.Ticker then PS.Ticker.SetEnabled(BACKSTOP_TICKER, true) end
    -- Blizzard may set its own font again straight after a zone change or a new choice.
    if changed then ScheduleReapply() end
    return mode
end

local function ReapplyNow()
    if mode then NativeFonts.Apply(nil, true) end
end
local function ReapplyLast()
    reapplyScheduled = false
    ReapplyNow()
end

ScheduleReapply = function()
    if not mode or reapplyScheduled then return end
    if not (C_Timer and type(C_Timer.After) == "function") then
        ReapplyNow()
        return
    end
    reapplyScheduled = true
    C_Timer.After(0, ReapplyNow)
    C_Timer.After(0.1, ReapplyLast)
end
NativeFonts.ScheduleReapply = ScheduleReapply

-- After a plate add: straight away (the hook runs after Blizzard set the new name's height and
-- before the frame is drawn, so the name never shows at Blizzard's size), for the first few adds of
-- a frame; then one pass next frame for any later in it. Each pass lays every name out again.
local IMMEDIATE_PER_FRAME = 3
local addFrameTime, addFrameCount = nil, 0
function NativeFonts.AfterAdd()
    local now = type(GetTime) == "function" and GetTime() or nil
    if now ~= addFrameTime then addFrameTime, addFrameCount = now, 0 end
    addFrameCount = addFrameCount + 1
    if addFrameCount <= IMMEDIATE_PER_FRAME then ReapplyNow() end
    NativeFonts.ScheduleFrame()
end

-- One forced pass next frame, however many plates were added this one.
local framePassScheduled = false
local function FramePass()
    framePassScheduled = false
    ReapplyNow()
end
function NativeFonts.ScheduleFrame()
    if not mode or framePassScheduled then return end
    if not (C_Timer and type(C_Timer.After) == "function") then return ReapplyNow() end
    framePassScheduled = true
    C_Timer.After(0, FramePass)
end

-- The backstop for a reset no event announced: an object that lost the written size or outline is
-- written again. One the client changes straight back is left (unsettled) rather than rewritten
-- every pass.
function NativeFonts.CheckKept()
    if not mode then return end
    local settings = Settings()
    for index = 1, CollectObjects() do
        local name, object = names[index], objects[index]
        local record = captured[name]
        if record and not unsettled[name] and not Kept(name, object) then
            local path, size, flags = Target(settings, record)
            Write(name, object, path, size, flags, true)
            if not Kept(name, object) then unsettled[name] = true end
        end
    end
end

function NativeFonts.Mode() return mode end

-- Blizzard's own font for an object (Studio's preview of its names): the captured original while
-- PlateSmith has changed it, else what the object holds now; nil when neither can be read. Reads only.
function NativeFonts.Original(name)
    local record = captured[name]
    if record then return record.path, record.size, record.flags end
    local object = WRITTEN[name] and _G[name]
    if mode or not Usable(object) then return nil end
    return Read(object)
end

-- For /ps diagnose: the owner's state and every listed object (none when this client lacks it).
function NativeFonts.Report()
    local report = { mode = mode or "none", objects = {} }
    local reported = {}
    for _, name in ipairs(NativeFonts.OBJECTS) do
        local object = _G[name]
        local entry
        if object == nil then
            entry = "none"
        elseif not Usable(object) then
            entry = "api-missing"
        elseif reported[object] then
            entry = { alias = reported[object] }
        else
            reported[object] = name
            local path, size, flags = Read(object)
            if not path then
                entry = "protected"
            else
                entry = { height = math.floor(size * 10 + 0.5) / 10, outline = flags ~= "" and flags or "none",
                    captured = captured[name] ~= nil, kept = not unsettled[name] }
            end
        end
        report.objects[name] = entry
    end
    return report
end

if PS.Ticker then
    PS.Ticker.Register(BACKSTOP_TICKER, BACKSTOP_INTERVAL, NativeFonts.CheckKept)
    PS.Ticker.SetEnabled(BACKSTOP_TICKER, false)
end

local RESET_CVARS = { nameplate = true, uiscale = true, useuiscale = true }
local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CVAR_UPDATE",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    PS._RegisterEvent(eventFrame, event, "platesmith.native-fonts")
end
eventFrame:SetScript("OnEvent", function(_, event, name)
    if not mode then return end
    if event == "CVAR_UPDATE" then
        if not Secret.IsReadable(name) or type(name) ~= "string" then return end
        local lower = string.lower(name)
        if not (RESET_CVARS[lower] or lower:find("nameplate", 1, true)) then return end
    end
    ScheduleReapply()
end)
