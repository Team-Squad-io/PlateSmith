-- A quest unit's objectives: which of the player's are still outstanding (a kill, or only an item
-- the unit drops, which picks the quest mark's look) and their progress ("3/8" or "50%") for the mark
-- and {quest.progress}. Sources: the quest log's objective a provider names (QuestieDB), else the
-- unit tooltip's quest objective lines, matched to the quest log. Only readable data is used.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")
local IsReadable, Number, String = Secret.IsReadable, Secret.Number, Secret.String

local QuestProgress = {}
PS.QuestProgress = QuestProgress

-- A unit tooltip has a few lines per quest; more than this is not read.
local MAX_TOOLTIP_LINES = 40
local MAX_REFS, MAX_OBJECTIVES, NPC_CACHE_LIMIT = 8, 32, 256
-- Instances can protect a nameplate token's tooltip and GUID while "target" and "mouseover" stay
-- readable, so what those show is kept per creature ID for the other plates of that mob.
local PROXY_TOKENS = { "target", "mouseover" }

-- The quest sources drawn as the loot bag instead of the quest mark.
local ITEM_DROP_SOURCES = { ["questiedb-item-drop"] = true, ["native-item-drop"] = true }
function QuestProgress.IsItemDrop(source)
    return type(source) == "string" and ITEM_DROP_SOURCES[source] == true
end

local function Field(object, key)
    if IsReadable(object) and type(object) == "table" then return object[key] end
end

-- A whole percentage 0-100 from readable numbers, or nil.
local function Percent(value)
    value = Number(value)
    if not value then return nil end
    return math.floor(math.max(0, math.min(100, value)) + 0.5)
end

local function Counted(have, need)
    have, need = Number(have), Number(need)
    if have and need and need > 0 and have >= 0 then return have, need end
end

-- An objective line's progress: "Slain: 3/8" or "Explored: 50%". A percentage objective reports
-- 0/1 in its numbers, so a percentage in its text wins.
local function FromText(text)
    text = String(text)
    if not text then return nil end
    local percent = text:match("(%d+)%s*%%")
    if percent then return nil, nil, Percent(tonumber(percent)) end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    have, need = Counted(tonumber(have), tonumber(need))
    if have then return have, need end
end

local function QuestObjectives(questID)
    local api = C_QuestLog and C_QuestLog.GetQuestObjectives
    if type(api) ~= "function" then return false end
    local ok, objectives = pcall(api, questID)
    if not ok or not IsReadable(objectives) then return false end
    return true, type(objectives) == "table" and objectives or nil
end

-- The quest log's objective (index) of questID, while it is unfinished.
local function FromQuestLog(questID, index)
    local _, objectives = QuestObjectives(questID)
    local objective = Field(objectives, index)
    local finished = Field(objective, "finished")
    if not IsReadable(finished) or finished ~= false then return nil end
    local kind = Field(objective, "type")
    if IsReadable(kind) and kind == "progressbar" and type(GetQuestProgressBarPercent) == "function" then
        local barOK, percent = pcall(GetQuestProgressBarPercent, questID)
        percent = barOK and Percent(percent) or nil
        if percent then return nil, nil, percent end
    end
    local textHave, textNeed, textPercent = FromText(Field(objective, "text"))
    if textPercent then return nil, nil, textPercent end
    local have, need = Counted(Field(objective, "numFulfilled"), Field(objective, "numRequired"))
    if have then return have, need end
    return textHave, textNeed
end

-- Whether questID is one of the player's own quests (a group member's objectives show in the
-- tooltip too). Without the API the tooltip is taken as the player's.
local function OwnQuest(questID)
    local onQuest = C_QuestLog and C_QuestLog.IsOnQuest
    if type(onQuest) ~= "function" then return true end
    return questID ~= nil and Secret.ReadBoolean(onQuest, questID) == true
end

-- An objective's name without its count or percentage, colour codes or list dash, so the tooltip's
-- "7/7 Deviate Shambler slain" matches the quest log's "Deviate Shambler slain: 7/7".
local function ObjectiveName(text)
    text = String(text)
    if not text then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%d+%s*/%s*%d+", ""):gsub("%d+%s*%%", "")
    text = text:gsub("^[%s%-:]+", ""):gsub("[%s:]+$", "")
    return text ~= "" and text:lower() or nil
end

local function ObjectiveKind(objective)
    local kind = Field(objective, "type")
    if IsReadable(kind) and kind == "item" then return "item" end
    if IsReadable(kind) and kind == "monster" then return "kill" end
    return "other"
end

-- The quest log objective (index, kind) a tooltip line is: the same name, else the only one with
-- the same count. nil when it cannot be told.
local function MatchObjective(questID, name, have, need)
    local _, objectives = QuestObjectives(questID)
    if not objectives then return nil end
    local counted, matches
    for index = 1, math.min(#objectives, MAX_OBJECTIVES) do
        local objective = objectives[index]
        if name and ObjectiveName(Field(objective, "text")) == name then return index, ObjectiveKind(objective) end
        if have then
            local objectiveHave, objectiveNeed = Counted(Field(objective, "numFulfilled"), Field(objective, "numRequired"))
            if objectiveHave == have and objectiveNeed == need then counted, matches = index, (matches or 0) + 1 end
        end
    end
    if matches == 1 then return counted, ObjectiveKind(objectives[counted]) end
end

-- A tooltip objective line: its progress, and whether it is finished (nil: unknown). Instances can
-- protect `completed` while the counts stay readable.
local function LineState(line)
    local have, need, percent = FromText(Field(line, "leftText"))
    if not percent then
        local counted, required = Counted(Field(line, "numFulfilled"), Field(line, "numRequired"))
        if counted then have, need = counted, required end
    end
    local finished
    local completed = Field(line, "completed")
    if IsReadable(completed) and type(completed) == "boolean" then
        finished = completed
    elseif percent then
        finished = percent >= 100
    elseif have then
        finished = have >= need
    end
    return finished, have, need, percent
end

-- One scratch scan, reused: refs[1..count] are the player's objective lines in the tooltip, each
-- { questID, index (in the quest log, or nil), kind ("kill", "item", "other"), finished, have, need,
-- percent }. finished nil is a line whose state is unknown.
local scan = { count = 0, refs = {} }

local function AddRef(into, questID, line)
    if into.count >= MAX_REFS then return end
    local finished, have, need, percent = LineState(line)
    local index, kind
    if finished ~= nil then index, kind = MatchObjective(questID, ObjectiveName(Field(line, "leftText")), have, need) end
    into.count = into.count + 1
    local ref = into.refs[into.count] or {}
    into.refs[into.count] = ref
    ref.questID, ref.index, ref.kind, ref.finished = questID, index, kind or "other", finished
    ref.have, ref.need, ref.percent = have, need, percent
end

-- Reads unit's tooltip into scan. Returns whether it named one of the player's quests.
local function ScanTooltip(unit)
    scan.count = 0
    local api = C_TooltipInfo and C_TooltipInfo.GetUnit
    local lineTypes = Enum and Enum.TooltipDataLineType
    if type(api) ~= "function" or type(lineTypes) ~= "table" then return false end
    local titleType, objectiveType, playerType = lineTypes.QuestTitle, lineTypes.QuestObjective, lineTypes.QuestPlayer
    if titleType == nil or objectiveType == nil then return false end
    local ok, info = pcall(api, unit)
    if not ok then return false end
    local lines = Field(info, "lines")
    if not IsReadable(lines) or type(lines) ~= "table" then return false end
    local questID, own, found, playerName = nil, false, false, nil
    for index = 1, math.min(#lines, MAX_TOOLTIP_LINES) do
        local line = lines[index]
        local kind = Field(line, "type")
        if IsReadable(kind) and kind == titleType then
            questID = Number(Field(line, "id"))
            own = OwnQuest(questID)
            found = found or own
        elseif IsReadable(kind) and playerType ~= nil and kind == playerType then
            -- In a group each member's objectives follow their name; only the player's count.
            playerName = playerName or Secret.ReadName("player")
            local name = String(Field(line, "leftText"))
            own = questID ~= nil and OwnQuest(questID) and name ~= nil and playerName ~= nil and name == playerName
        elseif IsReadable(kind) and kind == objectiveType and own then
            AddRef(scan, questID, line)
        end
    end
    return found
end

-- What a mob's tooltip showed, by creature ID and by name (instances can protect a plate's GUID
-- but not its name, or the reverse), bounded: it starts over when full. A quest log change makes the
-- counts of lines not matched to the quest log stale (generation).
local byKey, keyCount, generation = {}, 0, 0

local function NpcID(unit)
    local guid = Secret.ReadGUID(unit)
    if not guid then return nil end
    local unitType, npcID = guid:match("^([^-]+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    npcID = tonumber(npcID)
    return npcID and npcID > 0 and npcID or nil
end

-- A mob's keys: its creature ID and name. A unit whose readable GUID is not a creature's, or that
-- the game reports is a player, has none.
local function MobKeys(unit)
    local npcID = NpcID(unit)
    if not npcID and (Secret.ReadGUID(unit) or Secret.ReadBoolean(UnitIsPlayer, unit) ~= false) then return nil end
    return npcID, Secret.ReadName(unit)
end

local function Lookup(npcID, name)
    return npcID and byKey[npcID] or name and byKey[name] or nil
end

local function Keep(key, entry)
    if key == nil or byKey[key] == entry then return end
    if byKey[key] == nil then
        if keyCount >= NPC_CACHE_LIMIT then
            for old in pairs(byKey) do byKey[old] = nil end
            keyCount = 0
        end
        keyCount = keyCount + 1
    end
    byKey[key] = entry
end

-- Keeps the scan for the mob. Returns whether the kept objectives changed.
local function Remember(npcID, name)
    if npcID == nil and name == nil then return false end
    local entry = Lookup(npcID, name) or { count = 0, refs = {} }
    Keep(npcID, entry)
    Keep(name, entry)
    local changed = entry.count ~= scan.count
    for index = 1, scan.count do
        local from, to = scan.refs[index], entry.refs[index] or {}
        entry.refs[index] = to
        changed = changed or to.questID ~= from.questID or to.index ~= from.index or to.kind ~= from.kind
            or to.finished ~= from.finished or to.have ~= from.have or to.percent ~= from.percent
        to.questID, to.index, to.kind, to.finished = from.questID, from.index, from.kind, from.finished
        to.have, to.need, to.percent = from.have, from.need, from.percent
    end
    entry.count, entry.generation = scan.count, generation
    return changed
end

local function Forget(key)
    if key ~= nil and byKey[key] then byKey[key], keyCount = nil, keyCount - 1 end
end

-- Whether a ref is still outstanding (nil: unknown): the quest log's live state when the line was
-- matched to it, else what the tooltip showed while the player is still on the quest.
local function Outstanding(ref)
    if ref.index then
        local ok, objectives = QuestObjectives(ref.questID)
        if ok and not objectives then return false end
        local finished = Field(Field(objectives, ref.index), "finished")
        if IsReadable(finished) and type(finished) == "boolean" then return not finished end
    elseif C_QuestLog and type(C_QuestLog.IsOnQuest) == "function"
        and Secret.ReadBoolean(C_QuestLog.IsOnQuest, ref.questID) == false then
        return false
    end
    if ref.finished == nil then return nil end
    return not ref.finished
end

-- The outstanding objective that picks the mark: a kill (any objective but an item) first, else an
-- item; nil when none is outstanding or a line's state is unknown (the item look needs every line).
local function Choose(source)
    local kill, item, unknown
    for index = 1, source.count do
        local ref = source.refs[index]
        local outstanding = Outstanding(ref)
        if outstanding == nil then
            unknown = true
        elseif outstanding and ref.kind == "item" then
            item = item or ref
        elseif outstanding then
            kill = kill or ref
        end
    end
    if kill then return "kill", kill end
    if item and not unknown then return "item", item end
end

-- "target" or "mouseover" when the plate is that unit, for a plate whose own token is protected.
local function Proxy(unit)
    for index = 1, #PROXY_TOKENS do
        local token = PROXY_TOKENS[index]
        if Secret.SameUnit(unit, token) then return token end
    end
end

-- The unit's outstanding objective: state ("kill" or "item", nil unknown), questID and quest log
-- index (nil when a line did not match the quest log), the tooltip's have, need, percent for an
-- unmatched line, and the route that answered: the unit's own "tooltip", "target" or "mouseover"
-- (the plate is that unit), "mob" (what an earlier tooltip of the same mob showed) or "none".
function QuestProgress.Outstanding(unit)
    local source, route, fresh
    route, fresh = "none", true
    local npcID, name = MobKeys(unit)
    if ScanTooltip(unit) then
        source, route = scan, "tooltip"
        Remember(npcID, name)
    else
        local proxy = Proxy(unit)
        local proxyID, proxyName
        if proxy then proxyID, proxyName = MobKeys(proxy) end
        if proxy and ScanTooltip(proxy) then
            source, route = scan, proxy
            Remember(npcID or proxyID, name or proxyName)
        else
            source = Lookup(npcID, name) or Lookup(proxyID, proxyName)
            if source then route, fresh = "mob", source.generation == generation end
        end
    end
    if not source then return nil, nil, nil, nil, nil, nil, route end
    local state, ref = Choose(source)
    if not ref then return nil, nil, nil, nil, nil, nil, route end
    if ref.index or not fresh then return state, ref.questID, ref.index, nil, nil, nil, route end
    return state, ref.questID, nil, ref.have, ref.need, ref.percent, route
end

-- Learns what "target" or "mouseover" shows for its mob, and refreshes the quest marks when that
-- changed. A mob the game reports unrelated to the player's quests is forgotten.
function QuestProgress.Learn(token)
    if type(PS.PlateNeeds) == "function" and not PS.PlateNeeds().quest then return end
    local npcID, name = MobKeys(token)
    if npcID == nil and name == nil then return end
    local related = C_QuestLog and Secret.ReadBoolean(C_QuestLog.UnitIsRelatedToActiveQuest, token)
    if related == false then
        Forget(npcID)
        Forget(name)
        return
    end
    if ScanTooltip(token) and Remember(npcID, name) and type(PS.RefreshQuestMarkers) == "function" then
        PS.RefreshQuestMarkers()
    end
end

function QuestProgress._Forget()
    for key in pairs(byKey) do byKey[key] = nil end
    keyCount = 0
end

do
    local frame = CreateFrame("Frame")
    PS._RegisterEvent(frame, "PLAYER_TARGET_CHANGED", "platesmith.quest-progress")
    PS._RegisterEvent(frame, "UPDATE_MOUSEOVER_UNIT", "platesmith.quest-progress")
    PS._RegisterEvent(frame, "QUEST_LOG_UPDATE", "platesmith.quest-progress")
    frame:SetScript("OnEvent", function(_, event)
        if event == "QUEST_LOG_UPDATE" then
            generation = generation + 1
        elseif event == "PLAYER_TARGET_CHANGED" then
            QuestProgress.Learn("target")
        else
            QuestProgress.Learn("mouseover")
        end
    end)
end

local function ProviderRelevance(unit)
    if type(PS.IterateQuestProviders) ~= "function" then return false end
    for id, provider in PS:IterateQuestProviders() do
        if not provider._plateSmithQuestFailed then
            -- A provider may also name the objective it matched (quest ID, objective index).
            local ok, related, kind, detail, questID, objective = pcall(provider.GetUnitRelevance, provider, unit)
            if not ok then
                provider._plateSmithQuestFailed = tostring(related)
                PS.Chat.ReportError("quest provider " .. id, related)
            elseif IsReadable(related) and related == true then
                kind = IsReadable(kind) and type(kind) == "string" and kind or id
                detail = IsReadable(detail) and type(detail) == "string" and detail or nil
                return true, kind, detail, Number(questID), Number(objective)
            end
        end
    end
    return false
end

-- The native signal says only that a unit is related, not how. The player's outstanding objectives
-- pick the look: a kill (or any objective but an item) keeps the quest mark, only item drops show
-- the loot bag. Unknown: a provider's item-drop reading (QuestieDB lists only unfinished
-- objectives), else the quest mark as before; a provider's objective still gives the progress.
local function NativeRelevance(unit)
    local state, questID, objective = QuestProgress.Outstanding(unit)
    if state == "item" then return true, "native-item-drop", "quest item", questID, objective end
    if state == "kill" then return true, "native", "active quest", questID, objective end
    local related, kind, detail, providerQuest, providerObjective = ProviderRelevance(unit)
    if not related then return true, "native", "active quest" end
    if ITEM_DROP_SOURCES[kind] then return true, kind, detail, providerQuest, providerObjective end
    return true, "native", "active quest", providerQuest, providerObjective
end

-- Whether a unit is part of the player's quests: related, source (the mark's look and a diagnostic
-- label), detail, and the quest ID and quest log objective index when known. The native signal
-- decides whether; providers only fill in what it leaves out.
function QuestProgress.Relevance(unit)
    if C_QuestLog and type(C_QuestLog.UnitIsRelatedToActiveQuest) == "function" then
        local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and IsReadable(related) and related then return NativeRelevance(unit) end
    end
    if type(UnitIsQuestBoss) == "function" then
        local ok, boss = pcall(UnitIsQuestBoss, unit)
        if ok and IsReadable(boss) and boss then return true, "native-boss", "quest boss" end
    end
    local related, kind, detail, questID, objective = ProviderRelevance(unit)
    if related then return true, kind, detail, questID, objective end
    return false, "none", nil
end

-- have, need (a count) or percent (0-100) of the unit's objective, or nil. questID and
-- objectiveIndex come from a provider or the quest relevance that named the objective it matched.
function QuestProgress.Read(unit, questID, objectiveIndex)
    questID, objectiveIndex = Number(questID), Number(objectiveIndex)
    if questID and objectiveIndex then
        local have, need, percent = FromQuestLog(questID, objectiveIndex)
        if have or percent then return have, need, percent end
    end
    local _, outstandingQuest, index, have, need, percent = QuestProgress.Outstanding(unit)
    if outstandingQuest and index then return FromQuestLog(outstandingQuest, index) end
    return have, need, percent
end

-- The progress as text ("3/8", or "38%" with format percent) and as a percentage.
function QuestProgress.Text(have, need, percent, format)
    if not percent and have and need then percent = math.floor(have * 100 / need + 0.5) end
    if format ~= "percent" and have and need then return string.format("%d/%d", have, need), percent end
    if percent then return string.format("%d%%", percent), percent end
end

-- Reads the plate's progress (wanted: something shows or reads it) into data.questProgressText
-- and data.questProgressPercent. Returns whether either changed.
function QuestProgress.Update(data, related, questID, objectiveIndex, wanted)
    local text, percent
    if related and wanted then
        local have, need, percentDone = QuestProgress.Read(data.unit, questID, objectiveIndex)
        text, percent = QuestProgress.Text(have, need, percentDone, data.profile and data.profile.questProgressFormat)
    end
    local changed = text ~= data.questProgressText or percent ~= data.questProgressPercent
    data.questProgressText, data.questProgressPercent = text, percent
    return changed
end

local BLANK, FULL = { 0, 0, 0, 0 }, { 0, 1, 0, 1 }

-- The mark's progress text, beside the mark or in its place (the mark keeps its size, so what is
-- pinned to it stays put, and draws nothing). markShown: the mark or its loot bag shows.
function QuestProgress.Display(data, markShown)
    local mode = data.profile and data.profile.questProgress or "off"
    local text = data.questProgressText
    local shown = markShown and mode ~= "off" and text ~= nil
    local label = data.questProgressLabel
    if shown and not label then
        local layer = data.quest.GetParent and data.quest:GetParent()
        if not (layer and layer.CreateFontString) then return end
        label = layer:CreateFontString(nil, "OVERLAY")
        label:SetTextColor(1, 0.82, 0)
        data.questProgressLabel = label
    end
    if label then
        if shown then
            -- In the quest part's Display choices (font, size, outline, shadow).
            local size = math.max(8, ((data.profile and data.profile.nameFontSize) or 12) - 2)
            if PS.StyledPartFont then
                PS.StyledPartFont(data, "quest", label, size)
            elseif PS.ApplyNameplateFont then
                PS.ApplyNameplateFont(label, size)
            end
            label:SetText(text)
            label:ClearAllPoints()
            if mode == "instead" then
                label:SetPoint("CENTER", data.quest, "CENTER", 0, 0)
            else
                label:SetPoint("RIGHT", data.quest, "LEFT", -1, 0)
            end
            -- A rule's opacity on the mark reaches the text at the next rules pass; until then it
            -- starts at the mark's.
            label:SetAlpha(data.quest.plateSmithRuleAlpha or 1)
            label:Show()
        else
            label:Hide()
        end
    end
    local blank = shown and mode == "instead" or false
    if (data.questMarkBlank or false) ~= blank then
        data.questMarkBlank = blank
        local coords = blank and BLANK or FULL
        for _, region in ipairs({ data.quest, data.questLoot }) do
            if region and region.SetTexCoord then region:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
        end
    end
end
