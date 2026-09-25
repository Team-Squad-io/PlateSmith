local _, PS = ...

-- Copyable reports live outside the nameplate runtime chunk. Besides keeping
-- presentation separate from probes, this keeps WoW Lua 5.1's 200-local limit
-- from being consumed by JSON/window helpers.
local UI = {}
PS.DiagnosticUI = UI

local window
local jsonArrayMarker = {}

function UI.EnsureWindow()
    if not window then
        local created = CreateFrame("Frame", "PlateSmithDiagnosticsWindow", UIParent, "BackdropTemplate")
        created:SetSize(680, 430)
        created:SetPoint("CENTER")
        created:SetFrameStrata("DIALOG")
        created:SetMovable(true)
        created:SetClampedToScreen(true)
        created:EnableMouse(true)
        created:RegisterForDrag("LeftButton")
        created:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
        created:SetScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
        created:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        created:SetBackdropColor(0.025, 0.03, 0.035, 0.97)
        created:SetBackdropBorderColor(0.25, 0.72, 0.9, 0.9)

        local title = created:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", created, "TOPLEFT", 16, -15)
        title:SetText("PlateSmith Diagnostics")

        local close = CreateFrame("Button", nil, created, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", created, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() created:Hide() end)

        local scroll = CreateFrame("ScrollFrame", nil, created, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", created, "TOPLEFT", 16, -43)
        scroll:SetPoint("BOTTOMRIGHT", created, "BOTTOMRIGHT", -34, 45)
        local editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetWidth(602)
        editBox:SetHeight(360)
        editBox:SetScript("OnEscapePressed", function() created:Hide() end)
        scroll:SetScrollChild(editBox)

        local selectAll = CreateFrame("Button", nil, created, "UIPanelButtonTemplate")
        selectAll:SetSize(110, 24)
        selectAll:SetPoint("BOTTOMLEFT", created, "BOTTOMLEFT", 16, 12)
        selectAll:SetText("Select all")
        selectAll:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
        end)
        local copyHint = created:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        copyHint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
        copyHint:SetText("Press Ctrl+C to copy")

        created.editBox = editBox
        created.scroll = scroll
        created.selectAll = selectAll
        created.closeButton = close
        window = created
        PS._diagnosticWindow = created
        created:Hide()
    end
    return window
end

function UI.JsonArray()
    return setmetatable({}, jsonArrayMarker)
end

local function JsonString(value)
    local escaped = tostring(value):gsub('[%z\1-\31\\"]', function(char)
        if char == '\\' then return '\\\\' end
        if char == '"' then return '\\"' end
        if char == '\n' then return '\\n' end
        if char == '\r' then return '\\r' end
        if char == '\t' then return '\\t' end
        return string.format('\\u%04x', string.byte(char))
    end)
    return '"' .. escaped .. '"'
end

local function EncodeJson(value, depth)
    local kind = type(value)
    if kind == "string" then return JsonString(value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "null" end
        return tostring(value)
    end
    if kind ~= "table" then return "null" end
    local array = getmetatable(value) == jsonArrayMarker
    local entries = {}
    local indent = string.rep("  ", depth + 1)
    if array then
        for index = 1, #value do
            entries[#entries + 1] = indent .. EncodeJson(value[index], depth + 1)
        end
    else
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            entries[#entries + 1] = indent .. JsonString(key) .. ": "
                .. EncodeJson(value[key], depth + 1)
        end
    end
    if #entries == 0 then return array and "[]" or "{}" end
    return (array and "[" or "{") .. "\n" .. table.concat(entries, ",\n")
        .. "\n" .. string.rep("  ", depth) .. (array and "]" or "}")
end

function UI.ShowReport(report)
    local current = UI.EnsureWindow()
    local content = EncodeJson(report, 0)
    current.editBox:SetText(content)
    local _, lineCount = content:gsub("\n", "\n")
    current.editBox:SetHeight(math.max(360, (lineCount + 2) * 16))
    current:Show()
    current.editBox:SetFocus()
    current.editBox:HighlightText()
end
