local _, PS = ...
local Profiles = assert(PS.Profiles, "PlateSmith Profiles missing")
local L = PS.L

-- The active profile's name with Save and Revert, which stay disabled until
-- the working copy differs from the saved profile. Blueprint Studio and the
-- Settings pages each show one; they all follow the same profile.
local SaveBar = {}
PS.SaveBar = SaveBar

local UNSAVED = "|cffffc94a%s|r"

-- An action that cannot apply now looks unavailable: disabled and dimmed. Buttons that draw their
-- own disabled state are not dimmed a second time.
local function SetEnabled(button, enabled)
    button:SetEnabled(enabled)
    if not button.drawsDisabledState then button:SetAlpha(enabled and 1 or 0.45) end
end
SaveBar.SetAvailable = SetEnabled

-- makeButton(parent, text, width, height, primary) lets a surface use its own
-- button style; the default is Blizzard's panel button.
function SaveBar.Create(parent, makeButton)
    makeButton = makeButton or function(owner, text, width, height)
        return PS.UI.Window.Button(owner, text, width, height)
    end
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(420, 26)

    local save = makeButton(bar, L["Save"], 92, 26, true)
    save:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    local revert = makeButton(bar, L["Revert"], 92, 26, false)
    revert:SetPoint("RIGHT", save, "LEFT", -9, 0)
    local status = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("RIGHT", revert, "LEFT", -12, 0)
    status:SetWidth(215)
    status:SetJustifyH("RIGHT")

    function bar:Refresh()
        local dirty = Profiles.IsDirty()
        local text = string.format(L["Profile: %s"], tostring(Profiles.Active() or Profiles.DEFAULT))
        if dirty then text = text .. "  " .. string.format(UNSAVED, L["Unsaved changes"]) end
        status:SetText(text)
        SetEnabled(save, dirty)
        SetEnabled(revert, dirty)
    end

    save:SetScript("OnClick", function() Profiles.Save() end)
    -- Hooked, not set: Studio buttons use OnEnter/OnLeave for their own hover art.
    save:HookScript("OnEnter", function(owner)
        if not GameTooltip or not Profiles.IsDirty() then return end
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText(L["Unsaved changes"])
        for _, path in ipairs(Profiles.Changes(8)) do GameTooltip:AddLine(path, 0.86, 0.86, 0.86) end
        GameTooltip:Show()
    end)
    save:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    revert:SetScript("OnClick", function()
        Profiles.Revert()
        if PS.Options then PS.Options:Refresh() end
    end)
    bar:SetScript("OnShow", function(owner) owner:Refresh() end)
    Profiles.Subscribe(function() bar:Refresh() end)

    bar.saveButton, bar.revertButton, bar.status = save, revert, status
    bar:Refresh()
    return bar
end
