-- Read-only diagnostics for live nameplates. The runtime supplies its current state
-- without exposing plate ownership through the public module API.
local _, PS = ...
-- Add-ons a report names with their state (optional companions and what they build on).
local REPORTED_ADDONS = { "PlateSmith_QuestieDB", "QuestieDB", "Questie", "LibSharedMedia-3.0" }
local L = PS.L
local DiagnosticUI = assert(PS.DiagnosticUI, "PlateSmith DiagnosticUI missing")

PS._CreateDiagnosticProbes = function(context)
    local active = context.active
    local GetSettings = context.GetSettings
    local Secret = PS.Secret
    local IsSecret = Secret.IsSecret
    local IsReadable = Secret.IsReadable
    local RegionVisibleState = context.RegionVisibleState
    local ReadUnitName = context.ReadUnitName
    local ExternalProvider = context.ExternalProvider
    local QuestRelevance = context.QuestRelevance
    local ThreatRecord = context.ThreatRecord
    local FormatThreatRecord = PS.ThreatText.Record
    local ReadRaidTargetIndex = PS.RaidMarker.ReadIndex
    local NamePlateRootForUnit = PS.RaidMarker.PlateRoot
    local ResolveRaidTargetIndex = PS.RaidMarker.Resolve
    local ReadCVar = PS.NamePolicy.Read
    local Print = PS.Chat.Print
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
        if IsReadable(mob) and mob == nil then return "no-mob" end
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

    -- A frame's rectangle, rounded, when every edge and size can be read.
    local function ReadRect(frame)
        local ok, left, bottom, width, height = pcall(function()
            return frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
        end)
        if not ok then return nil end
        -- Each checked by position: ipairs would stop at the first nil (an unplaced frame has no left).
        local values = { left, bottom, width, height }
        for index = 1, 4 do
            local value = values[index]
            if not IsReadable(value) or type(value) ~= "number" then return nil end
        end
        return { left = math.floor(left + 0.5), bottom = math.floor(bottom + 0.5),
            width = math.floor(width + 0.5), height = math.floor(height + 0.5) }
    end

    -- A font object's or text's size and outline, read only.
    local function FontState(object)
        if type(object) ~= "table" or type(object.GetFont) ~= "function" then return "api-missing" end
        local ok, _, height, flags = pcall(object.GetFont, object)
        if not ok then return "error" end
        if not IsReadable(height) or not IsReadable(flags) then return "protected" end
        return { height = type(height) == "number" and math.floor(height * 10 + 0.5) / 10 or "unavailable",
            outline = type(flags) == "string" and flags ~= "" and flags or "none" }
    end

    local function ReadScale(region)
        if type(region.GetEffectiveScale) ~= "function" then return "api-missing" end
        local ok, scale = pcall(region.GetEffectiveScale, region)
        if not ok then return "error" end
        if not IsReadable(scale) then return "protected" end
        return type(scale) == "number" and math.floor(scale * 100 + 0.5) / 100 or "unavailable"
    end

    -- Blizzard's name on a plate: shown, its font and font object, and its drawn scale (read only).
    local function NativeNameState(root)
        local native = type(root) == "table" and root.UnitFrame
        local region = type(native) == "table" and native.name
        if type(region) ~= "table" then return "unavailable" end
        local state = { visible = RegionVisibleState(region), font = FontState(region), scale = ReadScale(region) }
        if type(region.GetFontObject) == "function" then
            local ok, object = pcall(region.GetFontObject, region)
            state.fontObject = "none"
            if ok and type(object) == "table" and type(object.GetName) == "function" then
                local named, name = pcall(object.GetName, object)
                if named and IsReadable(name) and type(name) == "string" then state.fontObject = name end
            end
        end
        if type(native.GetAlpha) == "function" then
            local ok, alpha = pcall(native.GetAlpha, native)
            state.alpha = ok and IsReadable(alpha) and type(alpha) == "number" and math.floor(alpha * 100 + 0.5) / 100
                or "unavailable"
        end
        return state
    end

    -- Each tracked friendly plate in a dungeon or raid (at most 12): what PlateSmith shows on it and how
    -- Blizzard's own name is drawn, so two name sizes on screen can be traced to their frames.
    local function FriendlyPlateStates()
        local list = PS.Json.Array()
        for unit, data in pairs(active) do
            if #list >= 12 then break end
            if data.unit == unit and data.friendly == true then
                list[#list + 1] = {
                    unit = unit, profile = tostring(data.profileKey or "unknown"),
                    restricted = data.restrictedFriendly == true, overlay = data.overlay:IsShown() == true,
                    name = RegionVisibleState(data.name), native = NativeNameState(data.root),
                }
            end
        end
        return list
    end

    -- The tracked plate of the player's target: its frame's plate, else a plate matching "target".
    local function TargetPlate()
        local root, rootState = NamePlateRootForUnit("target")
        local data = root and root.PlateSmithData or nil
        if not data then
            for _, candidate in pairs(active) do
                if Secret.SameUnit(candidate.unit, "target") then data = candidate break end
            end
        end
        return data, root, rootState
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

    -- Stacking: management, preset, options, what the client allows, and each catalogued CVar's
    -- current value (CVars are plain strings, never secret).
    local function StackingReport(Stacking)
        local ok, section = pcall(Stacking.Report)
        if not ok or type(section) ~= "table" then return { state = "failed" } end
        local readCVar = C_CVar and C_CVar.GetCVar or GetCVar
        local okPreset, preset = pcall(Stacking.Preset)
        section.preset = okPreset and tostring(preset) or "error"
        section.options = {}
        for _, name in ipairs(Stacking.OPTIONS or {}) do
            local okOption, value = pcall(Stacking.GetOption, name)
            if okOption then section.options[name] = value == true else section.options[name] = "error" end
        end
        local okSize, sizeSupport = pcall(Stacking.SizeSupport)
        section.sizeSupport = okSize and sizeSupport == true
        local okCombat, allowed, probe = pcall(Stacking.CanCombatSwitch)
        section.combatSwitch = okCombat and (allowed == true and "allowed" or tostring(probe or "untested")) or "error"
        section.cvars = {}
        local okCatalogue, catalogue = pcall(Stacking.Catalogue)
        for _, entry in ipairs(okCatalogue and type(catalogue) == "table" and catalogue or {}) do
            local value = "api-missing"
            if type(readCVar) == "function" then
                local okRead, text = pcall(readCVar, entry.key)
                value = not okRead and "error" or type(text) == "string" and text or "unavailable"
            end
            section.cvars[entry.key] = value
        end
        return section
    end

    local function BuildReport()
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
            questProviders = PS.Json.Array(),
            restrictions = PS.Restrictions.Report(),
            profile = {
                active = tostring(PS.Profiles.Active()), unsaved = PS.Profiles.IsDirty(),
                -- The profile Studio's header names, so a Studio out of step with the plates shows.
                studio = PS.Options and PS.Options.editorNamedProfileDropdown
                    and tostring(PS.Options.editorNamedProfileDropdown:GetText()) or "none",
                changes = PS.Json.Array(PS.Profiles.Changes(10)),
            },
            performance = PS.Performance.Report(),
            raid = {},
        }
        if PS.Conflicts then report.conflicts = PS.Conflicts.Report() end
        if PS.AutoProfile then report.autoProfile = PS.AutoProfile.Report() end
        -- Modules (the QuestieDB companion and any extension) and the add-ons they rely on, so a report
        -- shows why an optional feature is off: not installed, disabled, or loaded but failing.
        report.modules = {}
        if type(PS.IterateModules) == "function" then
            for id, module in PS:IterateModules() do
                report.modules[#report.modules + 1] = { id = id, version = tostring(module.version or "unknown"),
                    state = tostring(module._plateSmithState or "registered") }
            end
        end
        report.addons = {}
        local addOns = C_AddOns or {}
        for _, name in ipairs(REPORTED_ADDONS) do
            local state = "missing"
            local okLoaded, loaded = pcall(addOns.IsAddOnLoaded or IsAddOnLoaded, name)
            if okLoaded and loaded == true then
                state = "loaded"
            else
                local okInfo, _, _, _, loadable, reason = pcall(addOns.GetAddOnInfo or GetAddOnInfo, name)
                if okInfo and reason == "DISABLED" then
                    state = "disabled"
                elseif okInfo and reason == "MISSING" then
                    state = "missing"
                elseif okInfo and (loadable or reason) then
                    state = reason and string.lower(tostring(reason)) or "not-loaded"
                end
            end
            report.addons[name] = state
        end
        if PS.Stacking then report.stacking = StackingReport(PS.Stacking) end
        if PS.NativeFonts then report.nativeFonts = PS.NativeFonts.Report() end
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
            if firstError then
                report.dungeonFriendlyOverlay.firstError = PS.Format.Truncate(tostring(firstError), 160, 160)
            end
            -- Every shared nameplate font object Blizzard's names may use, and what PlateSmith does to them.
            report.dungeonFriendlyOverlay.nameFont = PS.NativeFonts and PS.NativeFonts.Report() or "api-missing"
            report.dungeonFriendlyOverlay.plates = FriendlyPlateStates()
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
        local targetData, _, targetRootState = TargetPlate()
        report.raid.api = {
            target = { index = targetIndex or "none", state = targetIndexState },
            targetPlate = { match = "unmatched", state = targetRootState },
        }
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
                healthGlowShown = targetData.targetBorder ~= nil and targetData.targetBorder:IsShown() == true,
            }
            local shownValues = {}
            for index = 1, VALUE_SLOT_COUNT do
                local key = "value" .. index
                local region = targetData.values[key]
                if region and region:IsShown() then
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
                local buff, debuff = targetData.buffIcons[index], targetData.debuffIcons[index]
                if buff and buff:IsShown() then shownBuffIcons = shownBuffIcons + 1 end
                if debuff and debuff:IsShown() then shownDebuffIcons = shownDebuffIcons + 1 end
            end
            report.target.buffs = {
                enabled = PS.GetPartShownState("showBuffs") ~= "none", source = db.buffSource, own = targetData.own == true,
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
                enabled = PS.GetPartShownState("showDebuffs") ~= "none", source = db.debuffSource, own = targetData.own == true,
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
            -- Blizzard's own plate aura frames: whether any can still draw over the owned plate.
            local blizzard = {}
            local native = targetData.root and targetData.root.UnitFrame
            local auras = native and native.AurasFrame
            for _, entry in ipairs({ { "unitFrame", native }, { "auras", auras },
                { "debuffList", auras and auras.DebuffListFrame }, { "buffList", auras and auras.BuffListFrame } }) do
                local frame = entry[2]
                if type(frame) == "table" and frame.GetAlpha then
                    local ok, alpha = pcall(frame.GetAlpha, frame)
                    local okIgnore, ignores = pcall(function() return frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha() end)
                    blizzard[entry[1]] = { alpha = ok and IsReadable(alpha) and alpha or "unreadable",
                        shown = RegionVisibleState(frame),
                        ignoresParentAlpha = okIgnore and IsReadable(ignores) and ignores == true or false }
                end
            end
            report.target.blizzardAuras = blizzard
            -- Anything else still drawn on this plate that is not PlateSmith's: frames under the
            -- plate root that are visible with an effective alpha above zero, by key path.
            local drawn, overlay = {}, targetData.overlay
            local function KeyOf(parent, child)
                for key, value in pairs(parent) do
                    if value == child and type(key) == "string" then return key end
                end
                return child.GetName and child:GetName() or (child.GetObjectType and child:GetObjectType()) or "?"
            end
            local function Walk(frame, path, depth)
                if depth > 6 or #drawn >= 20 or frame == overlay or not frame.GetChildren then return end
                local ok, children = pcall(function() return { frame:GetChildren() } end)
                if not ok then return end
                for _, child in ipairs(children) do
                    if child ~= overlay then
                        local childPath = path .. "." .. KeyOf(frame, child)
                        local okVisible, visible = pcall(child.IsVisible, child)
                        local okAlpha, alpha = pcall(function() return child.GetEffectiveAlpha and child:GetEffectiveAlpha() end)
                        if okVisible and IsReadable(visible) and visible == true and okAlpha and IsReadable(alpha)
                            and type(alpha) == "number"
                            and alpha > 0.01 and #drawn < 20 then
                            drawn[#drawn + 1] = childPath .. string.format(" (%.2f)", alpha)
                        end
                        Walk(child, childPath, depth + 1)
                    end
                end
            end
            if targetData.root then Walk(targetData.root, "plate", 1) end
            report.target.blizzardDrawn = drawn
            -- Where the native container and its first aura button actually are, against the row.
            local function Rect(frame)
                if type(frame) ~= "table" or not frame.GetLeft then return nil end
                local rect = ReadRect(frame)
                if not rect then return "unavailable" end
                rect.shown = RegionVisibleState(frame)
                return rect
            end
            for _, kind in ipairs({ "buffs", "debuffs" }) do
                local row = targetData[kind]
                local container = row.nativeAuraContainer
                local firstButton
                if container and container.GetChildren then
                    local ok, child = pcall(container.GetChildren, container)
                    firstButton = ok and child or nil
                end
                report.target[kind].geometry = { row = Rect(row), container = Rect(container), button = Rect(firstButton) }
            end
            if targetData.debuffs.nativeAuraError then
                report.target.debuffs.nativeContainerError = targetData.debuffs.nativeAuraError
            end
        else
            report.raid.api.targetPlate.note = "no tracked nameplate for this target at this instant"
        end
        local stageArt = PS.Options and PS.Options.editorStageArt
        if stageArt then report.studio = { previewMask = stageArt.maskStatus or "none" } end
        if PS._lastBlockedAction then
            report.protectedAction = { last = PS._lastBlockedAction }
            if PS._lastEventRegistration then
                report.protectedAction.lastEventRegistration = PS._lastEventRegistration
            end
        end

        if Secret.UnitExists("target") then
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
            -- Which route told the outstanding objective, through "target" and through its plate's token
            -- (instances can protect the plate token's tooltip).
            if PS.QuestProgress and questRelated == true then
                local state, _, _, _, _, _, route = PS.QuestProgress.Outstanding("target")
                report.target.quest.objective, report.target.quest.route = state or "unknown", route
                if targetData and targetData.unit then
                    local plateState, _, _, _, _, _, plateRoute = PS.QuestProgress.Outstanding(targetData.unit)
                    report.target.quest.plateObjective, report.target.quest.plateRoute = plateState or "unknown", plateRoute
                end
                report.target.quest.progress = targetData and targetData.questProgressText or "none"
            end
            local threat = targetData and targetData.unit and ThreatRecord(targetData.unit, true) or nil
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
                hold = threat and threat.holdState or "unavailable",
                playerRole = PS.ThreatService and string.format("%s (%s)", PS.ThreatService:GetPlayerRole())
                    or "unavailable",
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
                pets = { active = 0, roster = PS.Json.Array() },
                actors = PS.Json.Array(),
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
            local guidState = not IsReadable(guid) and "protected" or (guid == nil and "none" or "readable")
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
                -- A GUID is not a unit token: the client rejects it, so it is not probed.
                actorProbe.lead = { target = LeadPair("target"), plate = LeadPair(plateUnit) }
                threatProbe.actors[#threatProbe.actors + 1] = actorProbe
            end
            -- The threat meter's question in one line: can the other members' threat be read?
            local readable, protected, others = 0, 0, 0
            for _, actorProbe in ipairs(threatProbe.actors) do
                if actorProbe.unit ~= "player" then
                    others = others + 1
                    local raw = actorProbe.target and actorProbe.target.raw
                    if raw == "readable" then
                        readable = readable + 1
                    elseif raw == "protected/displayable" then
                        protected = protected + 1
                    end
                end
            end
            threatProbe.groupThreat = others == 0 and "no other members probed"
                or string.format("%d of %d readable, %d protected", readable, others, protected)
        end
        -- What the client lets us read about each engaged mob's own target (the Tank window's ON
        -- column): up to 8 tracked engaged enemies, read-only, classified, never converted to text.
        local service = PS.ThreatService
        if service and type(service.enemyOrder) == "table" then
            local function Readability(callback, unit)
                if type(callback) ~= "function" then return "api-missing" end
                local ok, value = pcall(callback, unit)
                if not ok then return "error" end
                return IsReadable(value) and "readable" or "protected"
            end
            local mobTargets = PS.Json.Array()
            for index = 1, service.enemyCount or 0 do
                local record = service.enemyOrder[index]
                if #mobTargets >= 8 then break end
                if record and record.unit and record.engaged and record.targetToken then
                    mobTargets[#mobTargets + 1] = {
                        unit = record.targetToken, hold = record.holdState or "unavailable",
                        exists = Readability(UnitExists, record.targetToken),
                        name = Readability(UnitName, record.targetToken),
                    }
                end
            end
            report.threatMobTargets = mobTargets
            -- Who targets each engaged mob, how readable the members' targets are, damage events.
            if type(service.TargetingReport) == "function" then report.threatTargeting = service:TargetingReport() end
            -- The hover route: the last mouseover event, the plate it named and the read through it,
            -- then how each engaged plate's gap was read (readable facts only).
            local probe = service.mouseoverProbe or {}
            local now = type(GetTime) == "function" and GetTime() or 0
            local hoverPlates = PS.Json.Array()
            for index = 1, service.enemyCount or 0 do
                local record = service.enemyOrder[index]
                if #hoverPlates >= 8 then break end
                if record and record.unit and record.engaged then
                    hoverPlates[#hoverPlates + 1] = {
                        unit = record.unit, source = record.threatMobSource or "unavailable",
                        differential = record.differentialState or "unavailable",
                        blocker = record.differentialBlocker or "none",
                        gap = type(record.lead) == "number" and record.lead or "none",
                        kept = record.leadKept == true,
                    }
                end
            end
            report.threatMouseover = {
                events = probe.events or 0, eventsWhileAsleep = probe.asleep or 0,
                lastEventAgo = type(probe.eventAt) == "number" and string.format("%.1fs", now - probe.eventAt) or "never",
                matched = probe.matched == nil and "never" or (probe.matched or "no record"),
                route = probe.route or "never",
                lastRead = probe.readUnit and {
                    unit = probe.readUnit, ago = string.format("%.1fs", now - (probe.readAt or now)),
                    token = probe.token or "unavailable", playerRaw = probe.playerRaw or "unavailable",
                    playerTanking = probe.playerTanking or "unavailable", playerPercent = probe.playerPercent or "unavailable",
                    differential = probe.differential, blocker = probe.blocker, groupRead = probe.groupRead,
                    gap = probe.lead, kind = probe.leadKind, display = probe.display ~= "" and probe.display or "none",
                } or "never",
                plates = hoverPlates,
            }
            -- Settings › Experimental: whether each test is on and what the game allowed.
            if type(service.ExperimentalReport) == "function" then
                local ok, experimental = pcall(service.ExperimentalReport, service)
                report.experimental = ok and experimental or { state = "failed" }
            end
        end
        -- Blizzard's damage meter windows, read only (a threat window can dock beside them).
        local meter = rawget(_G, "DamageMeter")
        if type(meter) == "table" and meter.GetObjectType then
            local windows = PS.Json.Array()
            for index = 1, 3 do
                local name = "DamageMeterSessionWindow" .. index
                local window = rawget(_G, name)
                if type(window) == "table" and window.GetLeft then
                    windows[#windows + 1] = { name = name, shown = RegionVisibleState(window) == true,
                        rect = ReadRect(window) or "unplaced" }
                end
            end
            local enabled = ReadCVar("damageMeterEnabled")
            report.blizzardMeter = { shown = RegionVisibleState(meter) == true, enabled = enabled or "unknown", windows = windows }
        else
            report.blizzardMeter = { present = false }
        end
        if PS.ThreatConsole and type(PS.ThreatConsole.Report) == "function" then
            local ok, windows = pcall(PS.ThreatConsole.Report, PS.ThreatConsole)
            report.threatConsole = ok and windows or { state = "failed" }
        end
        -- "Targeted by" badges: per member, whether the target and engaged plates' comparisons read.
        if PS.TargetedBy and type(PS.TargetedBy.Report) == "function" then
            local ok, targeted = pcall(PS.TargetedBy.Report)
            report.targetedBy = ok and targeted or { state = "failed" }
        end
        return report
    end

    -- A probe that fails (a value the client withholds in combat, say) must not leave /ps diagnose
    -- silent: the window still opens, on a short report naming the failure.
    local function Diagnose()
        local ok, report = pcall(BuildReport)
        if not ok then
            local reason = tostring(report)
            PS.Chat.ReportError("diagnose", reason)
            report = { format = "platesmith-diagnostics", version = tostring(PS.RUNTIME_BUILD or "unknown build"),
                reportError = reason, performance = PS.Performance.Report() }
        end
        DiagnosticUI.ShowReport(report, "manual")
    end

    local function ProbePlayerPlate()
        if not Secret.UnitExists("target") then
            Print(L["Target the neutral or opposing player first, then run /platesmith playerprobe."])
            return
        end
        local targetData, root, state = TargetPlate()
        local match = targetData and targetData.unit or nil
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
        DiagnosticUI.ShowReport(report, "player probe")
    end

    return Diagnose, ProbePlayerPlate, AuraProbe, BuildReport
end
