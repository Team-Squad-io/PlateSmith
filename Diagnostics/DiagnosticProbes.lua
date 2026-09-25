-- Read-only diagnostics for live nameplates. The runtime supplies its current state
-- without exposing plate ownership through the public module API.
local _, PS = ...
local DiagnosticUI = assert(PS.DiagnosticUI, "PlateSmith DiagnosticUI missing")

PS._CreateDiagnosticProbes = function(context)
    local active = context.active
    local GetSettings = context.GetSettings
    local IsSecret = context.IsSecret
    local IsReadable = context.IsReadable
    local RegionVisibleState = context.RegionVisibleState
    local ReadUnitName = context.ReadUnitName
    local ExternalProvider = context.ExternalProvider
    local QuestRelevance = context.QuestRelevance
    local ThreatRecord = context.ThreatRecord
    local FormatThreatRecord = context.FormatThreatRecord
    local ReadRaidTargetIndex = context.ReadRaidTargetIndex
    local NamePlateRootForUnit = context.NamePlateRootForUnit
    local ResolveRaidTargetIndex = context.ResolveRaidTargetIndex
    local ReadCVar = context.ReadCVar
    local Print = context.Print
    local VALUE_SLOT_COUNT = context.VALUE_SLOT_COUNT
    local AURA_ICON_COUNT = context.AURA_ICON_COUNT

    local function ThreatProbeState(value)
        if IsSecret(value) then return "protected/displayable" end
        if value == nil then return "none" end
        if IsReadable(value) and (type(value) == "number" or type(value) == "boolean") then return "readable" end
        return "unavailable"
    end

    local function ThreatProbeCall(callback, actor, mob)
        if type(callback) ~= "function" then return "api-missing" end
        if not IsSecret(mob) and mob == nil then return "no-mob" end
        local ok, value = pcall(callback, actor, mob)
        return ok and ThreatProbeState(value) or "error"
    end

    local function AuraProbe(unit, filter)
        local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        if type(api) ~= "function" then return "api-missing" end
        if type(unit) ~= "string" then return "no-unit" end
        local ok, aura = pcall(api, unit, 1, filter)
        if not ok then return "error" end
        if not IsReadable(aura) then return "protected" end
        if aura == nil then return "none" end
        local iconOK, icon = pcall(function() return aura.icon end)
        if not iconOK then return "icon-error" end
        if IsSecret(icon) then return "icon-protected/displayable" end
        return icon == nil and "icon-none" or "icon-readable"
    end

    local function DiagnosticUnitValue(callback, ...)
        if type(callback) ~= "function" then return "api-missing" end
        local ok, value = pcall(callback, ...)
        if not ok then return "error" end
        if not IsReadable(value) then return "protected" end
        if value == nil then return "none" end
        local kind = type(value)
        return (kind == "boolean" or kind == "number" or kind == "string") and value or "unavailable"
    end

    local function Diagnose()
        local db = GetSettings()
        local build = type(GetBuildInfo) == "function" and select(4, GetBuildInfo()) or "unknown"
        local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
        local inInstance, instanceType = IsInInstance()
        local groupCount, groupType = 0, "solo"
        if type(GetNumGroupMembers) == "function" then
            local ok, count = pcall(GetNumGroupMembers)
            if ok and IsReadable(count) and type(count) == "number" then groupCount = count end
        end
        if groupCount > 0 then
            local raid = false
            if type(IsInRaid) == "function" then
                local ok, value = pcall(IsInRaid)
                raid = ok and IsReadable(value) and value == true
            end
            groupType = raid and "raid" or "party"
        end
        local questAPI = C_QuestLog and type(C_QuestLog.UnitIsRelatedToActiveQuest) == "function"
        local report = {
            format = "platesmith-diagnostics",
            version = tostring(PS.RUNTIME_BUILD or "unknown build"),
            context = {
                build = build, provider = ExternalProvider() or "native", plates = #plates,
                instance = inInstance and instanceType or "world",
                group = { type = groupType, members = groupCount },
            },
            api = { quest = questAPI == true, secret = type(issecretvalue) == "function" },
            settings = { mode = db.mode, friendly = db.friendly },
            questProviders = DiagnosticUI.JsonArray(),
            raid = {},
        }
        if inInstance and (instanceType == "party" or instanceType == "raid") then
            local trackedFriendly, overlayShown, overlayErrors, firstError = 0, 0, 0, nil
            for _, data in pairs(active) do
                if data.friendly == true then
                    trackedFriendly = trackedFriendly + 1
                    if data.overlay:IsShown() then overlayShown = overlayShown + 1 end
                    if data.restrictedOverlayError then
                        overlayErrors = overlayErrors + 1
                        firstError = firstError or data.restrictedOverlayError
                    end
                end
            end
            report.dungeonFriendlyOverlay = {
                enabled = db.experimentalDungeonFriendlyText == true,
                tracked = trackedFriendly, shown = overlayShown, errors = overlayErrors,
                nativeRetained = true,
            }
            if firstError then report.dungeonFriendlyOverlay.firstError = firstError:sub(1, 160) end
        end

        if type(PS.IterateQuestProviders) == "function" then
            for id, provider in PS:IterateQuestProviders() do
                local status = provider._plateSmithQuestFailed and "failed" or "ready"
                local detail = nil
                if type(provider.GetDiagnostics) == "function" then
                    local ok, value = pcall(provider.GetDiagnostics, provider)
                    if ok and type(value) == "string" then detail = value end
                end
                report.questProviders[#report.questProviders + 1] = {
                    id = id, status = status, detail = detail or "none",
                }
            end
        end

        local targetIndex, targetIndexState = ReadRaidTargetIndex("target")
        local targetRoot, targetRootState = NamePlateRootForUnit("target")
        report.raid.api = {
            target = { index = targetIndex or "none", state = targetIndexState },
            targetPlate = { match = "unmatched", state = targetRootState },
        }
        local targetData = targetRoot and targetRoot.PlateSmithData or nil
        if not targetData and type(UnitIsUnit) == "function" then
            for unit, data in pairs(active) do
                local ok, same = pcall(UnitIsUnit, unit, "target")
                if ok and IsReadable(same) and same then
                    targetData = data
                    break
                end
            end
        end
        if targetData then
            local resolved, source, route = ResolveRaidTargetIndex(targetData)
            local shown = type(targetData.raidIcon.IsShown) == "function" and targetData.raidIcon:IsShown() or false
            report.raid.api.targetPlate.match = "matched"
            report.raid.plate = {
                resolved = resolved or "none", source = source or "none", route = route or "none",
                render = targetData.raidIconSource or "unknown", own = targetData.own == true,
                layout = targetData.layout.raidIcon.visible ~= false, shown = shown == true,
            }
            local nameShown = type(targetData.name.IsShown) == "function" and targetData.name:IsShown() or false
            report.target = report.target or {}
            report.target.plate = {
                profile = targetData.profileKey or "unknown",
                namesOnly = targetData.namesOnly == true,
                nameLayout = targetData.layout.name.visible ~= false,
                nameShown = nameShown == true,
                nameReadable = ReadUnitName(UnitName, targetData.unit) ~= nil,
            }
            local matchState = "api-missing"
            if type(UnitIsUnit) == "function" then
                local ok, same = pcall(UnitIsUnit, targetData.unit, "target")
                matchState = not ok and "error" or not IsReadable(same) and "protected"
                    or tostring(same == true)
            end
            report.target.highlight = {
                configured = db.targetHighlightStyle,
                targetMatch = matchState,
                applied = targetData.targetGlowStyle or "none",
                nameGlowShown = (targetData.targetGlowStyle == "border"
                    or targetData.targetGlowStyle == "halo") and nameShown == true,
                healthGlowShown = targetData.targetBorder:IsShown() == true,
            }
            local shownValues = {}
            for index = 1, VALUE_SLOT_COUNT do
                local key = "value" .. index
                if targetData.values[key]:IsShown() then
                    shownValues[#shownValues + 1] = { slot = key,
                        source = targetData.profile.valueSlots[key].source }
                end
            end
            report.target.plate.shownValues = shownValues
            local filter = db.debuffSource == "mine" and "HARMFUL|PLAYER" or "HARMFUL"
            local buffFilter = db.buffSource == "mine" and "HELPFUL|PLAYER" or "HELPFUL"
            local buffPosition = targetData.layout.buffs
            local debuffPosition = targetData.layout.debuffs
            local shownBuffIcons, shownDebuffIcons = 0, 0
            for index = 1, AURA_ICON_COUNT do
                if targetData.buffIcons[index]:IsShown() then shownBuffIcons = shownBuffIcons + 1 end
                if targetData.debuffIcons[index]:IsShown() then shownDebuffIcons = shownDebuffIcons + 1 end
            end
            report.target.buffs = {
                enabled = db.showBuffs == true, source = db.buffSource, own = targetData.own == true,
                layout = buffPosition.visible ~= false,
                position = { x = buffPosition.x, y = buffPosition.y, scale = buffPosition.scale or 1 },
                rowShown = targetData.buffs:IsShown() == true,
                rowVisible = RegionVisibleState(targetData.buffs),
                overlayVisible = RegionVisibleState(targetData.overlay),
                iconsShown = shownBuffIcons,
                firstIconVisible = RegionVisibleState(targetData.buffIcons[1]),
                containerShown = targetData.buffs.nativeAuraContainer
                    and targetData.buffs.nativeAuraContainer:IsShown() == true or false,
                route = targetData.buffsAuraRoute or "unknown",
                probe = { filter = buffFilter, target = AuraProbe("target", buffFilter),
                    plate = AuraProbe(targetData.unit, buffFilter) },
            }
            report.target.debuffs = {
                enabled = db.showDebuffs == true, source = db.debuffSource, own = targetData.own == true,
                layout = debuffPosition.visible ~= false,
                position = { x = debuffPosition.x, y = debuffPosition.y, scale = debuffPosition.scale or 1 },
                rowShown = targetData.debuffs:IsShown() == true,
                rowVisible = RegionVisibleState(targetData.debuffs),
                overlayVisible = RegionVisibleState(targetData.overlay),
                iconsShown = shownDebuffIcons,
                firstIconVisible = RegionVisibleState(targetData.debuffIcons[1]),
                containerShown = targetData.debuffs.nativeAuraContainer
                    and targetData.debuffs.nativeAuraContainer:IsShown() == true or false,
                targetMatch = matchState, route = targetData.debuffsAuraRoute or "unknown",
                probe = {
                    filter = filter, target = AuraProbe("target", filter),
                    plate = AuraProbe(targetData.unit, filter), targetAll = AuraProbe("target", "HARMFUL"),
                },
            }
            if targetData.debuffs.nativeAuraError then
                report.target.debuffs.nativeContainerError = targetData.debuffs.nativeAuraError
            end
        else
            report.raid.api.targetPlate.note = "no tracked nameplate for this target at this instant"
        end
        if PS._lastBlockedAction then
            report.protectedAction = { last = PS._lastBlockedAction }
            if PS._lastEventRegistration then
                report.protectedAction.lastEventRegistration = PS._lastEventRegistration
            end
        end

        if type(UnitExists) == "function" and UnitExists("target") then
            local displayName = ReadUnitName(GetUnitName, "target", true) or "unavailable"
            local pvpName = ReadUnitName(UnitPVPName, "target") or "unavailable"
            local legacyName = ReadUnitName(UnitName, "target") or "unavailable"
            report.target = report.target or {}
            report.target.names = { display = displayName, pvp = pvpName, legacy = legacyName }
            report.target.identity = {
                player = DiagnosticUnitValue(UnitIsPlayer, "target"),
                friendly = DiagnosticUnitValue(UnitIsFriend, "player", "target"),
                reaction = DiagnosticUnitValue(UnitReaction, "target", "player"),
                pvpFlagged = DiagnosticUnitValue(UnitIsPVP, "target"),
                attackable = DiagnosticUnitValue(UnitCanAttack, "player", "target"),
            }
            local questRelated, questSource, questDetail = QuestRelevance("target")
            report.target.quest = {
                related = questRelated == true, source = questSource or "none", detail = questDetail or "none",
            }
            local threat
            for unit in pairs(active) do
                local same = type(UnitIsUnit) == "function" and UnitIsUnit(unit, "target")
                if IsReadable(same) and same then
                    threat = ThreatRecord(unit, true)
                    break
                end
            end
            local threatText = threat and FormatThreatRecord(threat) or ""
            if threatText == "" and threat and (threat.hasOpaquePercent or threat.hasOpaqueLeadPercent or threat.hasOpaqueRawThreat) then
                threatText = "protected/displayable"
            end
            report.target.threat = {
                display = threatText ~= "" and threatText or "unavailable",
                differential = threat and threat.differentialState or "unavailable",
                source = threat and threat.threatMobSource or "unavailable",
                blocker = threat and threat.differentialBlocker or "none",
                engaged = threat and threat.engaged == true or false,
                playerNoEntry = threat and threat.playerThreatNoEntry == true or false,
                fallback = {
                    raw = threat and threat.rawThreatState or "unavailable",
                    leadPercent = threat and threat.leadPercentState or "unavailable",
                    leadSituation = threat and threat.leadSituationState or "unavailable",
                },
            }

            -- Bounded, read-only probes: classify each return without converting a secret to text.
            local actors = { "player" }
            local petOwners = {}
            local threatProbe = {
                pets = { active = 0, roster = DiagnosticUI.JsonArray() },
                actors = DiagnosticUI.JsonArray(),
            }
            report.target.threatProbe = threatProbe
            local function AddPet(unit, owner)
                local ok, exists = pcall(UnitExists, unit)
                if not ok then
                    threatProbe.pets.roster[#threatProbe.pets.roster + 1] = { unit = unit, exists = "error" }
                elseif not IsReadable(exists) then
                    threatProbe.pets.roster[#threatProbe.pets.roster + 1] = { unit = unit, exists = "protected" }
                elseif exists then
                    actors[#actors + 1] = unit
                    petOwners[unit] = owner
                end
            end
            if groupType ~= "raid" then AddPet("pet", "player") end
            if groupType == "party" then
                for index = 1, math.min(4, groupCount - 1) do
                    local unit = "party" .. index
                    local ok, exists = pcall(UnitExists, unit)
                    if ok and IsReadable(exists) and exists then actors[#actors + 1] = unit end
                    AddPet("partypet" .. index, unit)
                end
            elseif groupType == "raid" then
                for index = 1, math.min(40, groupCount) do
                    local unit = "raid" .. index
                    if index <= 3 then
                        local ok, exists = pcall(UnitExists, unit)
                        if ok and IsReadable(exists) and exists then actors[#actors + 1] = unit end
                    end
                    AddPet("raidpet" .. index, unit)
                end
            end
            local petCount = 0
            for _ in pairs(petOwners) do petCount = petCount + 1 end
            threatProbe.pets.active = petCount
            if groupType == "raid" then
                threatProbe.pets.raidPlayersProbed = "first 3 slots"
                threatProbe.pets.raidPetsProbed = "all slots"
            end
            local plateUnit = targetData and targetData.unit or nil
            local guid
            if type(UnitGUID) == "function" then
                local ok, value = pcall(UnitGUID, plateUnit or "target")
                if ok then guid = value end
            end
            local guidState = IsSecret(guid) and "protected" or (guid == nil and "none" or "readable")
            threatProbe.mobIdentifiers = {
                target = "unit", plate = plateUnit and "unit" or "none", guid = guidState,
            }
            for _, actor in ipairs(actors) do
                local actorProbe = { unit = actor }
                if petOwners[actor] then
                    actorProbe.owner = petOwners[actor]
                    actorProbe.name = ReadUnitName(UnitName, actor) or "unavailable"
                end
                if type(UnitDetailedThreatSituation) == "function" then
                    local ok, tanking, status, scaled, rawPercent, rawThreat =
                        pcall(UnitDetailedThreatSituation, actor, "target")
                    if ok then
                        actorProbe.target = {
                            tanking = ThreatProbeState(tanking), status = ThreatProbeState(status),
                            scaled = ThreatProbeState(scaled), rawPercent = ThreatProbeState(rawPercent),
                            raw = ThreatProbeState(rawThreat),
                            situation = ThreatProbeCall(UnitThreatSituation, actor, "target"),
                        }
                        if IsReadable(rawThreat) and type(rawThreat) == "number" then
                            actorProbe.target.rawValue = rawThreat
                        end
                    else
                        actorProbe.target = { detailed = "error" }
                    end
                else
                    actorProbe.target = { detailed = "api-missing" }
                end
                local function LeadPair(mob)
                    return {
                        percent = ThreatProbeCall(UnitThreatPercentageOfLead, actor, mob),
                        situation = ThreatProbeCall(UnitThreatLeadSituation, actor, mob),
                    }
                end
                actorProbe.lead = { target = LeadPair("target"), plate = LeadPair(plateUnit),
                    guid = LeadPair(guid) }
                threatProbe.actors[#threatProbe.actors + 1] = actorProbe
            end
        end
        if PS.ThreatConsole and PS.ThreatConsole.lastHighlightCheck then
            report.threatConsole = { lastClick = PS.ThreatConsole.lastHighlightCheck }
        end
        DiagnosticUI.ShowReport(report)
    end

    local function ProbePlayerPlate()
        if type(UnitExists) ~= "function" or not UnitExists("target") then
            Print("Target the neutral or opposing player first, then run /platesmith playerprobe.")
            return
        end
        local root, state = NamePlateRootForUnit("target")
        local match
        for unit in pairs(active) do
            local ok, same = pcall(UnitIsUnit, unit, "target")
            if ok and IsReadable(same) and same == true then match = unit break end
        end
        local report = {
            format = "platesmith-player-probe",
            version = PS.RUNTIME_BUILD or "unknown",
            target = {
                name = ReadUnitName(GetUnitName, "target", true) or "unavailable",
                player = DiagnosticUnitValue(UnitIsPlayer, "target"),
                friendly = DiagnosticUnitValue(UnitIsFriend, "player", "target"),
                reaction = DiagnosticUnitValue(UnitReaction, "target", "player"),
                pvpFlagged = DiagnosticUnitValue(UnitIsPVP, "target"),
                attackable = DiagnosticUnitValue(UnitCanAttack, "player", "target"),
            },
            nameplate = {
                api = state,
                trackedUnit = match or "none",
                tracked = match ~= nil,
                note = (root or match) and "A nameplate frame is available for PlateSmith to test."
                    or "No nameplate frame was supplied for this target at probe time; the visible name may be native overhead text.",
            },
            cvars = {
                nameplateShowEnemies = ReadCVar("nameplateShowEnemies") or "absent",
                nameplateShowAll = ReadCVar("nameplateShowAll") or "absent",
                nameplateShowEnemyPlayer = ReadCVar("nameplateShowEnemyPlayer") or "absent",
                nameplateShowEnemyPlayers = ReadCVar("nameplateShowEnemyPlayers") or "absent",
            },
        }
        DiagnosticUI.ShowReport(report)
    end

    return Diagnose, ProbePlayerPlate, AuraProbe
end
