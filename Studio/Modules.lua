local _, PS = ...
local Options = assert(PS.Options, "PlateSmith editor model missing")
local ModuleSettings = assert(PS.ModuleSettings, "PlateSmith ModuleSettings missing")
local chrome = assert(Options.studioChrome, "PlateSmith StudioChrome missing")
local Table = assert(PS.Table, "PlateSmith Table missing")
local L = PS.L
local WidgetName = assert(Options.studioModel, "PlateSmith Studio model missing").WidgetName

-- Studio › Settings › Modules: each module's page (PlateSmith:RegisterStudioSettings, Core/ModuleSettings.lua), built
-- the first time it is wanted from the kit facade below, which is the module contract (docs/MODULES.md, "Studio
-- settings"): Studio's own rows behind a small, versioned set of calls, so Studio can change underneath. A page's
-- build and callbacks are contained: a failure shows an error card in its place, and the fifth turns it off.
local PREFIX = "module:"
local MAX_ROWS, SLOW_MS = 80, 20
local SAVED_AT_ONCE = L["Saved at once: Save and Revert do not change it."]

local function KeyOf(id) return PREFIX .. id end
Options.ModuleSettingsKey = KeyOf
local function EntryOf(key)
    if type(key) ~= "string" or key:sub(1, #PREFIX) ~= PREFIX then return nil end
    return ModuleSettings.Get(key:sub(#PREFIX + 1))
end
Options.ModuleSettingsEntry = EntryOf

local function Clock() return type(debugprofilestop) == "function" and debugprofilestop() or nil end

-- The Modules group's categories: PlateSmith's own (Threat) first, then the companions by title. Rebuilt only when
-- a module registers.
local categories = { count = -1, list = {} }
function Options:ModuleSettingsCategories()
    local registered = ModuleSettings.List()
    if categories.count ~= #registered then
        local list = {}
        for _, entry in ipairs(registered) do
            entry.category = entry.category or { key = KeyOf(entry.id), label = entry.title, module = entry, icon = entry.icon,
                summary = entry.summary or L["A module: an addon that adds to PlateSmith."] }
            list[#list + 1] = entry.category
        end
        table.sort(list, function(left, right)
            local a, b = left.module, right.module
            if a.builtin ~= b.builtin then return a.builtin end
            if a.builtin then return a.order < b.order end
            if left.label:lower() ~= right.label:lower() then return left.label:lower() < right.label:lower() end
            return a.order < b.order
        end)
        categories.count, categories.list = #registered, list
    end
    return categories.list
end

local function Same(left, right)
    if type(left) == "table" and type(right) == "table" then return Table.DeepEqual(left, right) end
    return left == right
end

-- Whether a module's profile settings differ from the saved profile (its row's unsaved dot): a built-in's own keys,
-- a companion's modules["<id>"].
function Options:ModuleSettingsUnsaved(entry)
    local Profiles = PS.Profiles
    if not (entry and Profiles and Profiles.IsDirty()) then return false end
    local working, saved = PS.GetSettings(), Profiles.Saved()
    if type(working) ~= "table" or type(saved) ~= "table" then return false end
    if entry.builtin then
        for _, key in ipairs(entry.profileKeys or {}) do
            if not Same(working[key], saved[key]) then return true end
        end
        return false
    end
    local mine = type(working.modules) == "table" and working.modules[entry.id] or nil
    local theirs = type(saved.modules) == "table" and saved.modules[entry.id] or nil
    return not Same(mine, theirs)
end

-- What a row's tooltip and an error card say about a page that cannot show (nil: it can).
function Options:ModuleSettingsProblem(entry)
    if entry.state == "api-missing" then
        if entry.note == "needs an update" then
            return string.format(L["%s needs an update to work with this PlateSmith."], entry.title)
        end
        return string.format(L["%s needs a newer PlateSmith."], entry.title)
    end
    local state = PS._ModuleState and PS._ModuleState(entry.id)
    if state == "failed" then return string.format(L["%s failed to load. /ps diagnose has the details."], entry.title) end
    if entry.state == "disabled" or entry.buildFailed then
        return string.format(L["%s's settings could not be shown. /ps diagnose has the details."], entry.title)
    end
    return nil
end

-- The page's content replaced by one card saying why (a build that failed, a page turned off, an API it lacks).
local function ShowErrorCard(entry)
    local panel, SK = entry.panel, Options.settingsKit
    if not panel or not SK then return end
    for _, item in ipairs(panel.flowItems) do item.frame:Hide() end
    local card = panel.moduleErrorCard
    if not card then
        card = SK.Card(panel)
        card.message = SK.Add(card, SK.Help(card, ""))
        SK.Ink(card.message.text, "label")
        panel.moduleErrorCard = card
    end
    card.message.text:SetText(Options:ModuleSettingsProblem(entry) or "")
    panel.flowItems = { { frame = card } }
    card:Show()
    if Options.editorSettingsWorkspace and Options.editorSettingsWorkspace:IsShown() then Options:LayoutEditorSettingsPanels() end
end

-- Core/ModuleSettings.lua's Fail: the fifth contained error turned the page off.
function Options:OnModuleSettingsFailed(entry)
    ShowErrorCard(entry)
end

-- The facade a module's build(page, kit) gets. Every row takes one spec table; Studio adds the widget, its name, the
-- refresh guard, tooltip help and the search entry. Module callbacks (get, set, choices, summary, shown, onClick, text)
-- run under pcall: an error reads as the fallback, is reported once and counts towards the page's five.
local function NewKit(entry, panel)
    local SK, parts = Options.settingsKit, Options.settingsPageKit
    local kit = { version = PS.STUDIO_API_VERSION }
    local rows, serial = 0, 0

    local function Guard(fn, fallback)
        if type(fn) ~= "function" then return function() return fallback end end
        return function(...)
            if entry.state == "disabled" then return fallback end
            local ok, result, second = pcall(fn, ...)
            if ok then return result, second end
            ModuleSettings.Fail(entry, result)
            return fallback
        end
    end
    local function Row()
        rows = rows + 1
        if rows > MAX_ROWS then error(string.format("a module's settings page has at most %d rows", MAX_ROWS), 3) end
    end
    local function Name(spec, kind)
        serial = serial + 1
        if entry.builtin and spec.name then return WidgetName(spec.name, kind) end
        return WidgetName("module_" .. entry.id .. "_" .. serial, kind)
    end
    local function Flow(section, what)
        if type(section) ~= "table" or type(section.flowItems) ~= "table" then
            error(what .. " needs a section from kit.Section", 3)
        end
        return section
    end

    -- Bindings: where a row's value lives.
    local function Binding(scope, key, get, set)
        return { kitBinding = true, scope = scope, key = key, get = get, set = set }
    end
    local function Declared(key, scope, what)
        local spec = entry.settings[key]
        if not spec or spec.scope ~= scope then
            error(string.format("%s: declare %s in settings with scope %s", what, tostring(key), scope), 3)
        end
    end
    function kit.Profile(key)
        if entry.builtin then
            return Binding("profile", key, function() return PS.GetSettings()[key] end,
                function(value) return PS.SetOption(key, value) end)
        end
        Declared(key, "profile", "kit.Profile")
        return Binding("profile", key, function() return ModuleSettings.Value(entry.id, key) end,
            function(value) return ModuleSettings.Set(entry.id, key, value) end)
    end
    function kit.Character(key)
        if entry.builtin then
            return Binding("character", key, function() return PS.GetCharacterSettings()[key] end,
                function(value) return PS.SetCharacterOption(key, value) end)
        end
        Declared(key, "character", "kit.Character")
        return Binding("character", key, function() return ModuleSettings.Value(entry.id, key) end,
            function(value) return ModuleSettings.Set(entry.id, key, value) end)
    end
    function kit.Own(store, key)
        if type(store) ~= "table" or key == nil then error("kit.Own needs the module's table and a key", 2) end
        return Binding("own", key, function() return store[key] end, function(value)
            store[key] = value
            ModuleSettings.Changed(entry, key, value)
            return true
        end)
    end
    function kit.Custom(spec)
        if type(spec) ~= "table" or type(spec.get) ~= "function" or type(spec.set) ~= "function" then
            error("kit.Custom needs { get = function, set = function }", 2)
        end
        return Binding("custom", spec.key, spec.get, function(value) return spec.set(value) ~= false end)
    end
    function kit.Value(key)
        if entry.builtin then return PS.GetSettings()[key] end
        return ModuleSettings.Value(entry.id, key)
    end

    -- get, set (a change: everything follows), drag (a slider's step: the preview follows) and the binding.
    local function Bound(spec, what)
        local binding = spec.bind
        if type(binding) ~= "table" or not binding.kitBinding then
            error(what .. " needs bind = kit.Profile(key), kit.Character(key), kit.Own(table, key) or kit.Custom{...}", 3)
        end
        local get, write = Guard(binding.get), Guard(binding.set, false)
        return get, function(value)
            local ok = write(value)
            Options:Refresh(true)
            return ok
        end, function(value)
            local ok = write(value)
            Options:QueueRefresh()
            return ok
        end, binding
    end
    -- A made row into its section: shown while spec.shown says, its help and (saved at once) its note as its tooltip,
    -- its control refreshed with Studio's (only while its page shows).
    local function Place(section, row, control, spec, binding)
        SK.Add(section, row, spec.shown ~= nil and Guard(spec.shown, false) or nil)
        if type(spec.help) == "string" and spec.help ~= "" then SK.Add(section, SK.ControlHelp(section, spec.help)) end
        if binding and (binding.scope == "own" or binding.scope == "character") then
            SK.Add(section, SK.ControlHelp(section, SAVED_AT_ONCE))
        end
        if control then
            if entry.builtin and spec.id then parts.Bind(spec.id, control) else Options.RegisterControl(control) end
        end
        return control, row
    end
    local function Label(spec, what)
        if type(spec) ~= "table" then error(what .. " needs a spec table", 3) end
        if spec.label ~= nil and type(spec.label) ~= "string" then error(what .. ": label must be text", 3) end
        return spec.label
    end

    -- A folding section; options: summary() (shown at its title while folded), key (its fold state; default the title).
    function kit.Section(_, title, options)
        if type(title) ~= "string" or title == "" then error("kit.Section needs a title", 2) end
        options = type(options) == "table" and options or {}
        local foldKey = ("m:" .. entry.id .. ":" .. tostring(options.key or title)):sub(1, 64)
        local summary = options.summary and Guard(options.summary, "") or nil
        local section = parts.Section(panel, nil, title, summary, foldKey)
        if entry.builtin and options.anchor then entry.sections = entry.sections or {} entry.sections[options.anchor] = section end
        return section
    end
    function kit.SubHeader(section, text)
        Row()
        return SK.Add(Flow(section, "kit.SubHeader"), SK.SubHeader(section, tostring(text or "")))
    end
    function kit.Help(section, text)
        return SK.Add(Flow(section, "kit.Help"), SK.Help(section, tostring(text or "")))
    end
    -- A line under the row above; text may be a function, read on each refresh.
    function kit.Note(section, text)
        local note = SK.Add(Flow(section, "kit.Note"), SK.Note(section, type(text) == "string" and text or ""))
        if type(text) == "function" then
            local read = Guard(text, "")
            Options.RegisterControl({ Refresh = function() note.text:SetText(tostring(read() or "")) end })
        end
        return note
    end
    function kit.Check(section, spec)
        Row()
        local label = Label(spec, "kit.Check")
        local get, set, _, binding = Bound(spec, "kit.Check")
        local row, box = SK.CheckRow(Flow(section, "kit.Check"), nil, { text = label, name = Name(spec, "Checkbox"),
            get = function() return get() == true end, set = set })
        return Place(section, row, box, spec, binding)
    end
    function kit.Slider(section, spec)
        Row()
        local label = Label(spec, "kit.Slider")
        if type(spec.min) ~= "number" or type(spec.max) ~= "number" or spec.min >= spec.max then
            error("kit.Slider needs min < max", 2)
        end
        local get, set, drag, binding = Bound(spec, "kit.Slider")
        local format = spec.format
        if type(format) == "string" then
            local pattern = format
            format = function(value) return string.format(pattern, value) end
        end
        local row, slider = SK.SliderRow(Flow(section, "kit.Slider"), label, { min = spec.min, max = spec.max,
            step = spec.step or 1, name = Name(spec, "Slider"), format = format and Guard(format, "") or nil,
            get = function() return tonumber(get()) or spec.min end, set = set, drag = drag })
        return Place(section, row, slider, spec, binding)
    end
    function kit.Choice(section, spec)
        Row()
        local label = Label(spec, "kit.Choice")
        local get, set, _, binding = Bound(spec, "kit.Choice")
        local choices = spec.choices
        if type(choices) == "function" then
            choices = Guard(choices, {})
        elseif type(choices) ~= "table" then
            error("kit.Choice needs choices: { { value, label }, ... } or a function returning them", 2)
        end
        local row, dropdown = SK.DropdownRow(Flow(section, "kit.Choice"), label, { choices = choices, get = get, set = set,
            name = Name(spec, "Dropdown") })
        return Place(section, row, dropdown, spec, binding)
    end
    function kit.Swatch(section, spec)
        Row()
        local label = Label(spec, "kit.Swatch")
        local get, set, _, binding = Bound(spec, "kit.Swatch")
        local row, swatch = SK.SwatchRow(Flow(section, "kit.Swatch"), label, { name = Name(spec, "Colour"),
            get = get, set = function(r, g, b) return set({ r = r, g = g, b = b }) end })
        return Place(section, row, swatch, spec, binding)
    end
    function kit.Segmented(section, spec)
        Row()
        local label = Label(spec, "kit.Segmented")
        local get, set, _, binding = Bound(spec, "kit.Segmented")
        if type(spec.choices) ~= "table" or #spec.choices == 0 then error("kit.Segmented needs choices", 2) end
        local row = SK.Row(Flow(section, "kit.Segmented"), label)
        local control = SK.Segmented(row, { choices = spec.choices, get = get, set = set, name = Name(spec, "Segmented") })
        return Place(section, row, control, spec, binding)
    end
    function kit.Button(section, spec)
        Row()
        if type(spec) ~= "table" or type(spec.text) ~= "string" then error("kit.Button needs { text, onClick }", 2) end
        local row, button = SK.ButtonRow(Flow(section, "kit.Button"), spec.text, tonumber(spec.width) or 240)
        local click = Guard(spec.onClick)
        button:SetScript("OnClick", function()
            click()
            Options:Refresh(true)
        end)
        if spec.available then
            local available = Guard(spec.available, false)
            Options.RegisterControl({ Refresh = function() PS.SaveBar.SetAvailable(button, available() and true or false) end })
        end
        Place(section, row, nil, spec)
        return button, row
    end
    function kit.Buttons(section, spec)
        Row()
        if type(spec) ~= "table" or type(spec.buttons) ~= "table" or #spec.buttons == 0 then
            error("kit.Buttons needs { buttons = { { text, onClick, width }, ... } }", 2)
        end
        local list = {}
        for index, button in ipairs(spec.buttons) do
            local click = Guard(button.onClick or button[2])
            list[index] = { tostring(button.text or button[1] or ""), tonumber(button.width or button[3]) or 110, function()
                click()
                Options:Refresh(true)
            end }
        end
        local row, made = SK.ButtonsRow(Flow(section, "kit.Buttons"), spec.label, list)
        Place(section, row, nil, spec)
        return made, row
    end
    -- A read-only value: its label, then the text (a string, or a function read on each refresh) wrapped in the
    -- control column.
    function kit.Text(section, spec)
        Row()
        local label = Label(spec, "kit.Text")
        local frame = SK.Help(Flow(section, "kit.Text"), "", SK.CONTROL_X)
        frame.kitSearchHelp = nil
        SK.Ink(frame.text, "value")
        if label then
            frame.label = SK.Text(frame, label, "label")
            frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.label:SetWidth(SK.LABEL_W)
            frame.kitSearchLabel = label
        end
        local read = type(spec.text) == "function" and Guard(spec.text, "") or nil
        frame.text:SetText(read and "" or tostring(spec.text or ""))
        if read then Options.RegisterControl({ Refresh = function() frame.text:SetText(tostring(read() or "")) end }) end
        Place(section, frame, nil, spec)
        return frame
    end
    function kit.Has(name) return type(kit[name]) == "function" end
    -- The page's rows read their values again (after the module's own state changed). Cheap while the page is hidden.
    function kit.Refresh() Options:Refresh(true) end
    function kit.IsShown() return panel.IsVisible ~= nil and panel:IsVisible() == true end
    -- PlateSmith's own pages (Threat) build some rows from Studio's kit directly; never a companion's.
    if entry.builtin then
        kit.internal = { SK = SK, Bind = parts.Bind, Button = chrome.CreateStudioButton, panel = panel, entry = entry,
            Section = kit.Section }
    end
    return kit
end
Options._NewModuleSettingsKit = NewKit

-- A module's page: the facade over the shared page pieces (Inspector's Page and Section), its build timed and
-- contained. Returns the build for Inspector's EditorSettingsPage (which runs it through BuildLater), or nil.
function Options:ModuleSettingsBuilder(key)
    local entry = EntryOf(key)
    if not entry or not self.settingsPageKit or entry.panel then return nil end
    return function()
        local panel = self.settingsPageKit.Page(key)
        entry.panel, panel.moduleEntry = panel, entry
        if panel.HookScript and entry.OnShow then
            panel:HookScript("OnShow", function()
                if entry.state ~= "disabled" then
                    local ok, failure = pcall(entry.OnShow)
                    if not ok then ModuleSettings.Fail(entry, failure) end
                end
            end)
        end
        if entry.state == "api-missing" or entry.state == "disabled" or PS._ModuleState(entry.id) == "failed" then
            ShowErrorCard(entry)
            return
        end
        local kit = NewKit(entry, panel)
        local started = Clock()
        -- (Lua 5.1's xpcall passes no arguments.)
        local ok, failure = xpcall(function() return entry.build(panel, kit) end, PS._Traceback)
        local finished = Clock()
        entry.buildMs = started and finished and finished - started or nil
        entry.slow = entry.buildMs ~= nil and entry.buildMs > SLOW_MS or nil
        if not ok then
            entry.buildFailed = true
            ModuleSettings.Fail(entry, failure)
            ShowErrorCard(entry)
        end
    end
end

-- Studio opened at a module's page (Settings › Modules › its title), from anywhere: its Game Options page, a link, the
-- threat windows' menu. Works in combat (Studio's frames are not protected). section: an anchor a built-in page named.
function Options:OpenModuleSettings(id, section)
    local entry = ModuleSettings.Get(id)
    if not entry then return false end
    if not (self.editor and self.editor:IsShown()) and not (PS.OpenVisualEditor and PS.OpenVisualEditor()) then
        return false
    end
    local key = KeyOf(id)
    self:SetEditorInspectorPage(key)
    self:SetSettingsCategory(key)
    local frame = section and entry.sections and entry.sections[section]
    if frame and self.settingsSearch then
        self.settingsSearch.Pick({ place = "studio", category = key, frame = frame, section = frame })
    end
    return true
end

function PS.OpenModuleSettings(...)
    local id, section = PS._Args(...)
    return Options:OpenModuleSettings(id, section)
end
