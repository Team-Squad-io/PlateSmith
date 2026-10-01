local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local Controls = assert(PS.UI and PS.UI.Controls, "PlateSmith Controls missing")
local Window = assert(PS.UI and PS.UI.Window, "PlateSmith Window missing")
local Layout = assert(PS.UI and PS.UI.Layout, "PlateSmith Layout missing")
local L = PS.L
local model = assert(Options.settingsPanelModel, "PlateSmith Options missing")
local WidgetName = model.WidgetName
local CopyEditorLayout = model.CopyEditorLayout

-- Setting-bound controls shared by the Settings page and Blueprint Studio.
-- Each one refreshes with the rest of the editor through Options.controls.
local function Register(control)
    Options.controls[#Options.controls + 1] = control
    return control
end
Options.RegisterControl = Register

-- A value change: the controls and Studio's preview follow; Studio's look is left as it is.
local function SetAndRefresh(write)
    return function(value)
        local ok = write(value)
        Options:Refresh(true)
        return ok
    end
end

-- While a slider is dragged each step is written and only the preview follows (once a frame,
-- Options:QueueRefresh); letting go refreshes everything.
local function SetAndQueue(write)
    return function(value)
        local ok = write(value)
        Options:QueueRefresh()
        return ok
    end
end

-- get, set and drag for a profile setting (PS.SetOption), bound as the Add* controls bind them.
function Options.BindSetting(key)
    local function Write(value) return PS.SetOption(key, value) end
    return function() return PS.GetSettings()[key] end, SetAndRefresh(Write), SetAndQueue(Write)
end

-- get, set and mixed for a Show on plates or aura box (Schema's PART_SWITCHES): ticked while its
-- part shows on every plate type, mixed while they differ; set shows or hides it on all of them.
function Options.BindPartSwitch(key)
    return function() return PS.GetPartShownState(key) == "all" end,
        SetAndRefresh(function(value) return PS.SetPartShownEverywhere(key, value) end),
        function() return PS.GetPartShownState(key) == "some" end
end

function Options:AddDropdown(parent, label, key, choices, x, y, controlID, helpText, width)
    local get, set = Options.BindSetting(key)
    return Register(Controls.Dropdown(parent, {
        label = label, choices = choices, x = x, y = y, help = helpText, width = width,
        name = WidgetName((controlID or "options") .. "_" .. key, "Dropdown"), get = get, set = set,
    }))
end

-- perCharacter stores the option in PlateSmithCharacterDB instead of the account-wide settings.
function Options:AddCheckbox(parent, label, key, x, y, controlID, perCharacter)
    return Register(Controls.Checkbox(parent, {
        label = label, x = x, y = y,
        name = WidgetName((controlID or "options") .. "_" .. key, "Checkbox"),
        get = function() return (perCharacter and PS.GetCharacterSettings() or PS.GetSettings())[key] end,
        set = SetAndRefresh(function(value)
            if perCharacter then return PS.SetCharacterOption(key, value) end
            return PS.SetOption(key, value)
        end),
    }))
end

function Options:AddColour(parent, label, relationship, x, y, controlID)
    return Register(Controls.ColourSwatch(parent, {
        label = label, x = x, y = y,
        name = WidgetName((controlID or "options") .. "_" .. relationship, "Colour"),
        get = function()
            local settings = PS.GetSettings()
            return settings and settings.relationshipColours and settings.relationshipColours[relationship]
        end,
        set = function(r, g, b)
            PS.SetRelationshipColour(relationship, r, g, b)
            Options:Refresh()
        end,
    }))
end

-- The Settings pages' layout: one column of the shared panel kit (UI/Layout.lua) in Blizzard's
-- palette, a label | control | value grid, scrolling when it outgrows the canvas. It is laid out
-- for the smallest canvas (about 600 px wide).
local PAGE = { x = 20, top = 16, bottom = 24, width = 540, scrollBar = 30, footer = 48 }
Options.settingsPageMetrics = PAGE
-- Folded sections, by key: the player's saved state once loaded, this table before that.
Options.settingsSectionFolds = Options.settingsSectionFolds or {}

-- Builds a page's scrolling column under its title and description. withSaveBar pins the
-- profile's Save and Revert to the page's foot. Returns the kit, the column's flow (kit.Add
-- to it; page:Relayout() places it) and the save bar.
function Options:NewSettingsPage(page, title, description, withSaveBar)
    local kit = Layout.New({
        width = PAGE.width, palette = Layout.PALETTES.blizzard,
        tokens = { LABEL_W = 170, VALUE_W = 90, CONTROL_GAP = 10 },
        sectionState = function()
            local state = PS.GetState and PS.GetState()
            return state and state.sectionFolds or Options.settingsSectionFolds
        end,
        relayout = function() page:Relayout() end,
        button = function(parent, text, width, height) return Window.Button(parent, text, width, height) end,
    })
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE.scrollBar, withSaveBar and PAGE.footer or 8)
    -- The bar shows only when the column is taller than the canvas.
    scroll.scrollBarHideable = true
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(PAGE.x * 2 + PAGE.width, 400)
    scroll:SetScrollChild(child)
    local flow = kit.Flow(CreateFrame("Frame", nil, child))
    flow:SetPoint("TOPLEFT", child, "TOPLEFT", PAGE.x, -PAGE.top)
    flow:SetSize(PAGE.width, 1)

    local header = CreateFrame("Frame", nil, flow)
    header:SetSize(PAGE.width, 26)
    header.text = kit.Text(header, title, "title")
    header.text:SetFontObject("GameFontNormalLarge")
    kit.Ink(header.text, "title")
    header.text:SetPoint("LEFT", header, "LEFT", 0, 0)
    kit.Add(flow, header)
    if description then
        local help = kit.Help(flow, description)
        help.flowBefore = kit.SUB_GAP
        kit.Add(flow, help)
    end

    page.Relayout = function()
        local height = kit.LayoutFlow(flow, 0)
        flow:SetHeight(math.max(1, height))
        child:SetHeight(height + PAGE.top + PAGE.bottom)
    end
    page:HookScript("OnShow", function(owner) owner:Relayout() end)
    page.settingsKit, page.settingsFlow, page.settingsScroll = kit, flow, scroll

    local bar
    if withSaveBar then
        bar = PS.SaveBar.Create(page)
        bar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE.scrollBar, 12)
    end
    return kit, flow, bar
end

-- A section title a little larger than the rows, as Blizzard's own headings.
function Options.SettingsSection(kit, flow, title, options)
    local section = kit.Section(flow, title, options)
    section.title:SetFontObject("GameFontNormal")
    kit.Ink(section.title, "title")
    kit.Add(flow, section)
    return section
end

local function CreatePage(name)
    local page = CreateFrame("Frame")
    page.name = name
    page:SetScript("OnShow", function() Options:Refresh() end)
    return page
end

-- Plate appearance lives in Blueprint Studio; this page only points there.
local function BuildMainPage(panel)
    local kit, flow = Options:NewSettingsPage(panel, "PlateSmith",
        L["Plate appearance and layout are edited in Blueprint Studio (/ps). The Threat and Profiles pages hold "
            .. "the rest."])
    local row, editor = kit.ButtonRow(flow, L["Open Blueprint Studio"], 200)
    editor:SetScript("OnClick", function() PS.OpenVisualEditor() end)
    row.flowBefore = kit.SECTION_TOP
    kit.Add(flow, row)
    Options.editorButton = editor
    -- The live Performance view (/ps perf): watching it captures no diagnostics report.
    local troubleshooting = Options.SettingsSection(kit, flow, L["Troubleshooting"], { collapsible = false })
    local perfRow, perf = kit.ButtonRow(troubleshooting, L["Open performance view"], 200)
    perf:SetScript("OnClick", function() PS.DiagnosticUI.ShowPerformance() end)
    kit.Add(troubleshooting, perfRow)
    kit.Add(troubleshooting, kit.Help(troubleshooting, L["PlateSmith's live CPU cost, refreshed once a second while "
        .. "shown (/ps perf). /ps diagnose opens the full report to share."]))
    Options.performanceButton = perf
    panel:Relayout()
end

function PS.CreateOptions()
    if Options.panel then return Options.panel end

    if type(PS.GetLayout) == "function" then
        Options.editorLayout = CopyEditorLayout(PS.GetLayout())
    end

    local panel = CreatePage("PlateSmith")
    Options.panel = panel
    BuildMainPage(panel)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        Options.category = category
        Options.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    -- Threat (with the threat windows) and Profiles, in that order under PlateSmith.
    local threatPage = CreatePage(L["Threat"])
    Options:BuildThreatPage(threatPage)
    Options.threatPanel = threatPage
    PS.RegisterModuleSettings("threat", L["Threat"], threatPage)
    -- The threat windows' "settings" route (ThreatConsole:OpenSettings) opens the Threat page.
    Options.moduleSettings.threatWindows = Options.moduleSettings.threat

    local profilesPage = CreatePage(L["Profiles"])
    Options:BuildProfilesPage(profilesPage)
    Options.profilesPanel = profilesPage
    PS.RegisterModuleSettings("profiles", L["Profiles"], profilesPage)

    Options:Refresh()
    return panel
end

function PS.RegisterModuleSettings(id, title, panel)
    if type(id) ~= "string" or type(title) ~= "string" or not panel then
        return nil, "module settings require an id, title, and panel"
    end
    PS.CreateOptions()
    Options.moduleSettings = Options.moduleSettings or {}
    if Options.moduleSettings[id] then return nil, "module settings are already registered" end

    panel.name = title
    if Settings and Settings.RegisterCanvasLayoutSubcategory and Options.category then
        local category = Settings.RegisterCanvasLayoutSubcategory(Options.category, panel, title)
        Settings.RegisterAddOnCategory(category)
        Options.moduleSettings[id] = category
        return category
    elseif InterfaceOptions_AddCategory then
        panel.parent = "PlateSmith"
        InterfaceOptions_AddCategory(panel)
        Options.moduleSettings[id] = panel
        return panel
    end
    return nil, "module settings are unavailable on this client"
end

function PS.OpenOptions()
    PS.CreateOptions()
    if Settings and Settings.OpenToCategory and Options.categoryID then
        Settings.OpenToCategory(Options.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
    end
end
