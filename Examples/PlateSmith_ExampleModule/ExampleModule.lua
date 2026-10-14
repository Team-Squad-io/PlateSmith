local _, addon = ...
local PS = _G.PlateSmith

if not PS or type(PS.RegisterModule) ~= "function" then return end

local Module = {
    version = 1,
    apiMin = 1,
    apiMax = 1,
}
addon.Module = Module

local ACCENTS = {
    blue = { 0.20, 0.65, 1.00 },
    gold = { 0.95, 0.65, 0.15 },
    green = { 0.20, 0.85, 0.35 },
}

local function ParseAccent(value)
    if type(value) ~= "string" or not ACCENTS[value] then
        return nil, "example accent must be blue, gold, or green"
    end
    return value
end

function Module:RefreshPreview()
    if not self.previewFrame or not self.previewTexture then return end

    local color = ACCENTS[self.accent] or ACCENTS.gold
    self.previewTexture:SetColorTexture(color[1], color[2], color[3], 1)
    self.previewFrame:SetShown(self.enabled == true)
end

function Module:SetAccent(value)
    local accent = ParseAccent(value)
    if not accent then return false end

    self.accent = accent
    self.db.accent = accent
    self:RefreshPreview()
    return true
end

function Module:CreatePreview(component)
    local frame = self.previewFrame
    if not frame then
        frame = CreateFrame("Frame", nil, component)
        frame.texture = frame:CreateTexture(nil, "ARTWORK")
        frame.texture:SetAllPoints()
        frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.label:SetPoint("CENTER")
        frame.label:SetText("EXT")
        self.previewFrame = frame
        self.previewTexture = frame.texture
    else
        frame:SetParent(component)
    end

    frame:ClearAllPoints()
    frame:SetAllPoints(component)
    self:RefreshPreview()
end

function Module:OnInitialize()
    if type(PS.RegisterEditorComponent) ~= "function"
        or type(PS.RegisterBlueprintField) ~= "function" then
        error("PlateSmith visual extension APIs are unavailable")
    end

    local database = type(_G.PlateSmithExampleModuleDB) == "table"
        and _G.PlateSmithExampleModuleDB or {}
    _G.PlateSmithExampleModuleDB = database
    self.db = database
    self.accent = ParseAccent(database.accent) or "gold"
    self.db.accent = self.accent

    local componentRegistered, componentError = PS:RegisterEditorComponent("example.badge", {
        label = "Example accent badge",
        x = 72,
        y = -25,
        width = 34,
        height = 18,
        create = function(component) self:CreatePreview(component) end,
        refresh = function() self:RefreshPreview() end,
    })
    if not componentRegistered then error(componentError) end

    local fieldRegistered, fieldError = PS:RegisterBlueprintField("example.accent", {
        export = function() return self.accent end,
        parse = ParseAccent,
        apply = function(value) return self:SetAccent(value) end,
    })
    if not fieldRegistered then error(fieldError) end

    -- Style extensions (PlateSmith.STYLE_API_VERSION): {example.accent} in value templates, and
    -- {level:example.brackets} to wrap a readable value in angle brackets.
    if type(PS.RegisterTextToken) == "function" then
        local tokenRegistered, tokenError = PS:RegisterTextToken("example.accent", {
            styleApiMin = 1, styleApiMax = 1,
            kind = "text", label = "Example accent", sample = "gold",
            read = function() return self.enabled and self:ShowsAccent() and self.accent or nil end,
        })
        if not tokenRegistered then error(tokenError) end
        local formatterRegistered, formatterError = PS:RegisterFormatter("example.brackets", {
            styleApiMin = 1, styleApiMax = 1, label = "Angle brackets",
            format = function(value) return "<" .. tostring(value) .. ">" end,
        })
        if not formatterRegistered then error(formatterError) end
    end

    -- Studio › Settings › Modules › Example: the accent (this addon's own SavedVariables, saved at once) and a
    -- profile setting declared up front (kept with Save, undone by Revert, shared in Blueprints).
    if type(PS.RegisterStudioSettings) == "function" then
        local L = PS:Locale("example")
        local settingsRegistered, settingsError = PS:RegisterStudioSettings("example", {
            studioApiMin = 1, studioApiMax = 1,
            title = L["Example"], icon = "Interface\\Icons\\INV_Misc_Gem_01",
            summary = L["The example module's settings."],
            settings = { showAccent = { type = "boolean", default = true } },
            -- Custom text reading {example.accent} shows the change at once.
            OnSettingsChanged = function() PS:InvalidateFact("example.accent") end,
            build = function(_, kit)
                local section = kit.Section(nil, L["Accent"], { summary = function() return self.accent end })
                kit.Choice(section, { label = L["Accent"], choices = {
                        { value = "blue", label = L["Blue"] }, { value = "gold", label = L["Gold"] },
                        { value = "green", label = L["Green"] } },
                    bind = kit.Custom({ get = function() return self.accent end,
                        set = function(value) return self:SetAccent(value) end }),
                    help = L["The badge's colour in Studio's preview, and what {example.accent} reads."] })
                kit.Check(section, { label = L["Accent in custom text"], bind = kit.Profile("showAccent"),
                    help = L["Off: {example.accent} reads nothing. Part of your profile: kept with Save."] })
            end,
        })
        if not settingsRegistered then error(settingsError) end
    end
end

-- Whether custom text shows the accent (the profile setting above; on without PlateSmith 1.3.0's settings).
function Module:ShowsAccent()
    return type(PS.GetModuleOption) ~= "function" or PS:GetModuleOption("example", "showAccent") ~= false
end

function Module:OnEnable()
    self.enabled = true
    self:RefreshPreview()
end

function Module:OnDisable()
    self.enabled = false
    if self.previewFrame then self.previewFrame:Hide() end
end

local registered, reason = PS:RegisterModule("example", Module)
if not registered then error(reason) end
