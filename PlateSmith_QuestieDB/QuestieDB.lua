local PS = _G.PlateSmith
if not PS then return end
local L = PS.L

local MAX_QUESTS = 100
local MAX_OBJECTIVES = 64
local MAX_DROPS_PER_ITEM = 128
local defaults = {
    schemaVersion = 1,
    enabled = true,
    directObjectives = true,
    possibleItemDrops = true,
}

local module = {
    version = 1,
    apiMin = 1,
    apiMax = 1,
    enabled = false,
    cache = {},
    stats = { generation = 0, quests = 0, objectives = 0, npcs = 0 },
}

local IsReadable, ReadNumber = PS.Secret.IsReadable, PS.Secret.Number

local function CopyDefaults()
    local saved = type(PlateSmithQuestieDBDB) == "table" and PlateSmithQuestieDBDB or {}
    for key, value in pairs(defaults) do
        if type(saved[key]) ~= type(value) then saved[key] = value end
    end
    saved.schemaVersion = defaults.schemaVersion
    PlateSmithQuestieDBDB = saved
    return saved
end

local function NpcIDForUnit(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not IsReadable(guid) or type(guid) ~= "string" then return nil end

    local unitType, npcID
    if type(strsplit) == "function" then
        local _
        unitType, _, _, _, _, npcID = strsplit("-", guid)
    else
        unitType, npcID = guid:match("^([^-]+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
    end
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    npcID = tonumber(npcID)
    return npcID and npcID > 0 and npcID or nil
end

local function AddReason(target, npcID, reason)
    if type(npcID) ~= "number" or npcID <= 0 then return false end
    local current = target[npcID]
    if not current or (current.kind == "questiedb-item-drop" and reason.kind == "questiedb-direct") then
        target[npcID] = reason
        return current == nil
    end
    return false
end

local function ReadQuestObjectives(questID)
    local api = C_QuestLog and C_QuestLog.GetQuestObjectives
    if type(api) ~= "function" then return nil end
    local ok, objectives = pcall(api, questID)
    return ok and IsReadable(objectives) and type(objectives) == "table" and objectives or nil
end

-- QuestieDB rows are static for the session, so only the quest log's progress
-- needs re-reading on each rebuild. A failed read is not cached and is retried.
local databaseObjectives, databaseDrops = {}, {}

local function DatabaseObjectives(questID)
    local cached = databaseObjectives[questID]
    if cached ~= nil then return true, cached end
    local ok, objectives = pcall(module.lib.Quest.objectives, questID)
    if ok then databaseObjectives[questID] = type(objectives) == "table" and objectives or false end
    return ok, objectives
end

local function DatabaseDrops(itemID)
    local cached = databaseDrops[itemID]
    if cached ~= nil then return true, cached end
    local ok, drops = pcall(module.lib.Item.npcDrops, itemID)
    if ok then databaseDrops[itemID] = type(drops) == "table" and drops or false end
    return ok, drops
end

local function ClearCache(message, suppressRefresh)
    module.cache = {}
    module.lastError = message
    module.stats = {
        generation = module.stats.generation + 1,
        quests = 0,
        objectives = 0,
        npcs = 0,
    }
    module:RefreshPanel()
    if not suppressRefresh and type(PS.RefreshQuestMarkers) == "function" then PS.RefreshQuestMarkers() end
    return message == nil
end

local function RebuildCache(suppressRefresh)
    local nextCache = {}
    local quests, objectiveCount, npcCount = 0, 0, 0
    if not module.db.enabled then
        return ClearCache(nil, suppressRefresh)
    end
    local getCount = C_QuestLog and C_QuestLog.GetNumQuestLogEntries
    local getInfo = C_QuestLog and C_QuestLog.GetInfo
    if type(getCount) ~= "function" or type(getInfo) ~= "function" then
        return ClearCache("native quest-log API unavailable", suppressRefresh)
    end

    local ok, count = pcall(getCount)
    count = ok and ReadNumber(count) or nil
    if not count then
        return ClearCache("quest-log entry count unreadable", suppressRefresh)
    end
    module.lastError = nil

    for index = 1, math.min(MAX_QUESTS, math.floor(count)) do
        local infoOK, info = pcall(getInfo, index)
        local validInfo = infoOK and IsReadable(info) and type(info) == "table"
        local isHeader
        if validInfo then isHeader = info.isHeader end
        if validInfo
            and IsReadable(isHeader) and not isHeader then
            local questID = ReadNumber(info.questID)
            if questID and questID > 0 then
                local nativeObjectives = ReadQuestObjectives(questID)
                local databaseOK, questObjectives = DatabaseObjectives(questID)
                if not databaseOK then
                    module.lastError = "QuestieDB quest read failed for " .. tostring(questID)
                    questObjectives = nil
                end
                if nativeObjectives and type(questObjectives) == "table" then
                    quests = quests + 1
                    local typeOrdinals = { monster = 0, item = 0 }
                    for objectiveIndex = 1, math.min(MAX_OBJECTIVES, #nativeObjectives) do
                        local objective = nativeObjectives[objectiveIndex]
                        local objectiveType
                        if type(objective) == "table" then objectiveType = objective.type end
                        if IsReadable(objectiveType) and (objectiveType == "monster" or objectiveType == "item") then
                            typeOrdinals[objectiveType] = typeOrdinals[objectiveType] + 1
                            local unfinished = IsReadable(objective.finished) and objective.finished == false
                            if unfinished then
                                objectiveCount = objectiveCount + 1
                                local databaseType = objectiveType == "monster" and questObjectives[1] or questObjectives[3]
                                local row = type(databaseType) == "table" and databaseType[typeOrdinals[objectiveType]] or nil
                                local entityID = type(row) == "table" and ReadNumber(row[1]) or nil
                                if entityID and objectiveType == "monster" and module.db.directObjectives then
                                    local reason = {
                                        kind = "questiedb-direct",
                                        questID = questID,
                                        objectiveIndex = objectiveIndex,
                                        npcID = entityID,
                                    }
                                    if AddReason(nextCache, entityID, reason) then npcCount = npcCount + 1 end
                                elseif entityID and objectiveType == "item" and module.db.possibleItemDrops then
                                    local dropsOK, drops = DatabaseDrops(entityID)
                                    if not dropsOK then
                                        module.lastError = "QuestieDB item read failed for " .. tostring(entityID)
                                        drops = nil
                                    end
                                    if type(drops) == "table" then
                                        for dropIndex = 1, math.min(MAX_DROPS_PER_ITEM, #drops) do
                                            local npcID = ReadNumber(drops[dropIndex])
                                            if npcID then
                                                local reason = {
                                                    kind = "questiedb-item-drop",
                                                    questID = questID,
                                                    objectiveIndex = objectiveIndex,
                                                    itemID = entityID,
                                                    npcID = npcID,
                                                }
                                                if AddReason(nextCache, npcID, reason) then npcCount = npcCount + 1 end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    module.cache = nextCache
    module.stats = {
        generation = module.stats.generation + 1,
        quests = quests,
        objectives = objectiveCount,
        npcs = npcCount,
    }
    module:RefreshPanel()
    if not suppressRefresh and type(PS.RefreshQuestMarkers) == "function" then PS.RefreshQuestMarkers() end
    return true
end

local function StatusText()
    if module.lastError then return string.format(L["Unavailable: %s"], module.lastError) end
    local stats = module.stats
    return string.format(L["Ready: %d active quests, %d incomplete objectives, %d marked NPCs."],
        stats.quests, stats.objectives, stats.npcs)
end

function module:RefreshPanel()
    if not self.statusText then return end
    self.statusText:SetText(StatusText())
    for _, checkbox in ipairs(self.checkboxes or {}) do checkbox:Refresh() end
end

local function CreateCheckbox(parent, label, y, field)
    local checkbox = PS.UI.Controls.Checkbox(parent, {
        label = label, x = 20, y = y,
        get = function() return module.db and module.db[field] end,
        set = function(value)
            module.db[field] = value
            if module.enabled then RebuildCache() end
        end,
    })
    module.checkboxes = module.checkboxes or {}
    module.checkboxes[#module.checkboxes + 1] = checkbox
    return checkbox
end

function module:CreateSettings()
    if self.panel or type(PS.RegisterModuleSettings) ~= "function" then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText(L["QuestieDB"])
    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", 20, -52)
    description:SetWidth(600)
    description:SetJustifyH("LEFT")
    description:SetText(L["Quest markers from QuestieDB's database, for mobs the game does not mark itself. "
        .. "This page comes from the optional PlateSmith_QuestieDB companion and appears only while QuestieDB is installed."])

    CreateCheckbox(panel, L["Enable QuestieDB markers"], -92, "enabled")
    CreateCheckbox(panel, L["Supplement direct creature objectives"], -124, "directObjectives")
    CreateCheckbox(panel, L["Show possible item-drop mobs"], -156, "possibleItemDrops")
    self.statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    self.statusText:SetPoint("TOPLEFT", 24, -208)
    self.statusText:SetWidth(590)
    self.statusText:SetJustifyH("LEFT")
    panel:SetScript("OnShow", function() module:RefreshPanel() end)
    self.panel = panel
    PS.RegisterModuleSettings("questiedb", L["QuestieDB"], panel)
    self:RefreshPanel()
end

function module:OnInitialize()
    self.db = CopyDefaults()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.RequireContract) ~= "function"
        or type(lib.Quest) ~= "table" or type(lib.Quest.objectives) ~= "function"
        or type(lib.Item) ~= "table" or type(lib.Item.npcDrops) ~= "function" then
        error("LibQuestieDB public API is unavailable")
    end
    local ok, compatible, reason = pcall(lib.RequireContract, 1)
    if not ok or compatible ~= true then
        error(reason or compatible or "LibQuestieDB contract 1 is unavailable")
    end
    self.lib = lib

    local provider, providerError = PS:RegisterQuestProvider("platesmith.questiedb", {
        apiMin = 1,
        apiMax = 1,
        GetUnitRelevance = function(_, unit)
            if not module.enabled or not module.db.enabled then return false end
            local npcID = NpcIDForUnit(unit)
            local reasonEntry = npcID and module.cache[npcID] or nil
            if not reasonEntry then return false end
            local detail = reasonEntry.itemID
                and string.format("quest=%d item=%d npc=%d", reasonEntry.questID, reasonEntry.itemID, reasonEntry.npcID)
                or string.format("quest=%d npc=%d", reasonEntry.questID, reasonEntry.npcID)
            return true, reasonEntry.kind, detail
        end,
        GetDiagnostics = function()
            return string.format("contract=%s, cache=%d, quests=%d, generation=%d",
                tostring(lib.contractVersion or "unknown"), module.stats.npcs,
                module.stats.quests, module.stats.generation)
        end,
    })
    if not provider then error(providerError) end
    self:CreateSettings()
end

function module:OnEnable()
    self.enabled = true
    RebuildCache()
end

function module:OnDisable()
    self.enabled = false
    ClearCache(nil)
end

function module:OnQuestLogChanged(event)
    if self.enabled then RebuildCache(event ~= nil) end
end

local registered, registrationError = PS:RegisterModule("platesmith.questiedb", module)
if not registered then
    PS.Chat.ReportError("QuestieDB", registrationError)
end
