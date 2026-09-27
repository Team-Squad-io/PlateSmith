local _, PS = ...
local L = PS.L

-- Bar textures and fonts. Built-in choices always exist; when the optional
-- LibSharedMedia-3.0 is loaded its registered media are offered as well.
-- Stored LSM choices are "lsm:<name>", so a missing library or a removed
-- media entry falls back to the built-in default instead of failing.
local Media = {}
PS.Media = Media

local LSM_PREFIX = "lsm:"
local statusBars = {
    { value = "blizzard", label = L["Blizzard"], path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { value = "flat", label = L["Flat"], path = "Interface\\Buttons\\WHITE8X8" },
}
local statusBarByKey = {}
for _, entry in ipairs(statusBars) do statusBarByKey[entry.value] = entry end
local fonts = {
    { value = "default", label = L["Blizzard nameplate font"] },
    { value = "friz", label = L["Friz Quadrata"], path = "Fonts\\FRIZQT__.TTF" },
    { value = "arialn", label = L["Arial Narrow"], path = "Fonts\\ARIALN.TTF" },
    { value = "morpheus", label = L["Morpheus"], path = "Fonts\\MORPHEUS.TTF" },
    { value = "skurri", label = L["Skurri"], path = "Fonts\\SKURRI.TTF" },
}
local fontByKey = {}
for _, entry in ipairs(fonts) do fontByKey[entry.value] = entry end

local function SharedMedia()
    if type(LibStub) ~= "table" and type(LibStub) ~= "function" then return nil end
    local ok, library = pcall(LibStub, "LibSharedMedia-3.0", true)
    return ok and library or nil
end

-- A well-formed LSM reference, even if LSM is absent here.
local function IsSharedReference(value)
    return type(value) == "string" and #value <= 80 and value:sub(1, #LSM_PREFIX) == LSM_PREFIX and #value > #LSM_PREFIX
end

function Media.IsStatusBar(value) return statusBarByKey[value] ~= nil or IsSharedReference(value) end
function Media.IsFont(value) return fontByKey[value] ~= nil or IsSharedReference(value) end

local function SharedChoices(builtIn, kind)
    local choices = {}
    for _, entry in ipairs(builtIn) do choices[#choices + 1] = { value = entry.value, label = entry.label } end
    local library = SharedMedia()
    if library and type(library.List) == "function" then
        local ok, names = pcall(library.List, library, kind)
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                if type(name) == "string" then choices[#choices + 1] = { value = LSM_PREFIX .. name, label = name } end
            end
        end
    end
    return choices
end

function Media.StatusBarChoices() return SharedChoices(statusBars, "statusbar") end
function Media.FontChoices() return SharedChoices(fonts, "font") end

local function Fetch(kind, value)
    if type(value) ~= "string" or value:sub(1, #LSM_PREFIX) ~= LSM_PREFIX then return nil end
    local library = SharedMedia()
    if not library or type(library.Fetch) ~= "function" then return nil end
    local ok, path = pcall(library.Fetch, library, kind, value:sub(#LSM_PREFIX + 1), true)
    return ok and type(path) == "string" and path or nil
end

function Media.StatusBarPath(value)
    local entry = statusBarByKey[value]
    if entry then return entry.path end
    return Fetch("statusbar", value) or statusBars[1].path
end

-- nil means "use Blizzard's multilingual nameplate font object".
function Media.FontPath(value)
    local entry = fontByKey[value]
    if entry then return entry.path end
    return Fetch("font", value)
end
