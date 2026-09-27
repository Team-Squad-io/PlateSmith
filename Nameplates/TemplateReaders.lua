-- Template tokens read live for a plate (Core/Template.lua), and the readers that cache them for
-- one plate update. Protected values are passed on as they are; the template only shows them, so
-- a reader never truth-tests or compares one (an explicit branch, or IsReadable first).
local _, PS = ...
local L = PS.L

PS._CreateTemplateReaders = function(context)
    local Secret = PS.Secret
    local IsReadable, IsSecret = Secret.IsReadable, Secret.IsSecret
    local UnitDisplayNameValue = context.UnitDisplayNameValue
    local FriendlyRelationship = context.FriendlyRelationship
    local MARKS = PS.ClassificationMarks
    local HOLD_WORDS = { TANK = L["TANK"], YOU = L["YOU"], LOOSE = L["LOOSE"] }
    local Readers = {}

    local function Call(api, ...)
        if type(api) ~= "function" then return nil end
        local ok, value = pcall(api, ...)
        if ok then return value end
    end

    -- A number a display sink can take: readable, or protected but still displayable.
    local function IsDisplayNumber(value)
        return IsSecret(value) or (IsReadable(value) and type(value) == "number")
    end
    Readers.IsDisplayNumber = IsDisplayNumber

    -- The client's percentage (a curve, so a protected value stays displayable), or one worked
    -- out from readable values.
    local function ReadPercent(api, unit, current, maximum, power)
        local curve = CurveConstants and CurveConstants.ScaleTo100
        if type(api) == "function" and curve then
            local ok, percent
            if power then
                ok, percent = pcall(api, unit, nil, true, curve)
            else
                ok, percent = pcall(api, unit, true, curve)
            end
            if ok and IsDisplayNumber(percent) then return percent end
        end
        if IsReadable(current) and IsReadable(maximum) and type(current) == "number"
            and type(maximum) == "number" and maximum > 0 then
            return current * 100 / maximum
        end
    end
    Readers.ReadPercent = ReadPercent

    -- "<unit>target", made once per unit token.
    local targetTokens = {}
    function Readers.TargetToken(unit)
        local token = targetTokens[unit]
        if not token then
            token = unit .. "target"
            targetTokens[unit] = token
        end
        return token
    end

    local function ReadClassification(unit)
        local kind = Call(UnitClassification, unit)
        if IsReadable(kind) and type(kind) == "string" then return kind end
    end
    local function ReadReaction(unit)
        local reaction = Call(UnitReaction, unit, "player")
        if IsReadable(reaction) and type(reaction) == "number" then return reaction end
    end
    local function EngagedThreat(data)
        local info = data.threatInfo
        if info and info.engaged == true then return info end
    end

    -- Threat facts for rules, three-valued (ThreatText.Facts): out of combat they read false.
    local THREAT_FACTS = PS.ThreatText.Facts
    local function ThreatFacts(data)
        local info = EngagedThreat(data)
        if info then return info end
        if data.threatIdle == true then return false end
    end
    local function ThreatFact(name)
        local fact = THREAT_FACTS[name]
        return function(data)
            local info = ThreatFacts(data)
            if info == false then return false end
            if info then return fact(info) end
        end
    end

    -- reader(data, unit, read): read reads another token for the same plate and update.
    local TEMPLATE_READERS = {
        ["health"] = function(_, unit) return Call(UnitHealth, unit) end,
        ["health.max"] = function(_, unit) return Call(UnitHealthMax, unit) end,
        ["health.percent"] = function(_, unit, read)
            return ReadPercent(UnitHealthPercent, unit, read("health"), read("health.max"), false)
        end,
        ["health.missing"] = function(_, _, read)
            local current, maximum = read("health"), read("health.max")
            if IsReadable(current) and IsReadable(maximum) and type(current) == "number" and type(maximum) == "number" then
                return maximum - current
            end
        end,
        ["power"] = function(data, unit)
            if not data.power:IsShown() then return nil end
            return Call(UnitPower, unit)
        end,
        ["power.max"] = function(data, unit)
            if not data.power:IsShown() then return nil end
            return Call(UnitPowerMax, unit)
        end,
        ["power.percent"] = function(data, unit, read)
            if not data.power:IsShown() then return nil end
            return ReadPercent(UnitPowerPercent, unit, read("power"), read("power.max"), true)
        end,
        ["threat.percent"] = function(data)
            local info = EngagedThreat(data)
            if not info then return nil end
            if info.hasOpaquePercent then return info.percentOpaque end
            return info.percent
        end,
        ["threat.lead"] = function(data)
            local info = EngagedThreat(data)
            local lead = info and info.lead
            if IsReadable(lead) and type(lead) == "number" then return lead end
        end,
        ["threat.raw"] = function(data)
            local info = EngagedThreat(data)
            if not info then return nil end
            if info.hasOpaqueRawThreat then return info.rawThreatOpaque end
            return info.rawThreat
        end,
        ["level"] = function(_, unit) return Call(UnitLevel, unit) end,
        ["name"] = function(_, unit) return UnitDisplayNameValue(unit) end,
        ["target"] = function(data)
            local target = data.targetUnit
            if not target or not Secret.UnitExists(target) then return nil end
            return UnitDisplayNameValue(target)
        end,
        ["tagged"] = function(_, unit) return Call(UnitIsTapDenied, unit) end,
        ["elite"] = function(_, unit)
            local kind = ReadClassification(unit)
            if kind == nil then return nil end -- unreadable: unknown, not false
            return kind == "elite" or kind == "rareelite" or kind == "worldboss"
        end,
        ["rare"] = function(_, unit)
            local kind = ReadClassification(unit)
            if kind == nil then return nil end
            return kind == "rare" or kind == "rareelite"
        end,
        ["boss"] = function(_, unit)
            local kind = ReadClassification(unit)
            if kind == nil then return nil end
            return kind == "worldboss"
        end,
        ["casting"] = function(data) return data.casting == true end,
        ["combat"] = function() return Call(UnitAffectingCombat, "player") end,
        ["tanking"] = function(data)
            local info = data.threatInfo
            if not info then return false end -- no threat record: not tanking it
            local tanking = info.tanking
            if not IsReadable(tanking) then return nil end
            return tanking == true
        end,
        ["targeted"] = function(_, unit) return Call(UnitIsUnit, unit, "target") end,
        ["player"] = function(_, unit) return Call(UnitIsPlayer, unit) end,
        ["focus"] = function(_, unit) return Call(UnitIsUnit, unit, "focus") end,
        ["level.smart"] = function(_, unit, read)
            local level = read("level")
            if not IsReadable(level) or type(level) ~= "number" then return level end
            local text = level < 0 and "??" or tostring(level)
            local mark = MARKS[ReadClassification(unit) or ""]
            return mark and text .. mark.suffix or text
        end,
        ["level.diff"] = function(_, _, read)
            local level, own = read("level"), Call(UnitLevel, "player")
            if IsReadable(level) and IsReadable(own) and type(level) == "number" and type(own) == "number" and level > 0 then
                return level - own
            end
        end,
        ["classification"] = function(_, unit)
            local mark = MARKS[ReadClassification(unit) or ""]
            return mark and mark.word
        end,
        ["guild"] = function(_, unit)
            local name = Call(GetGuildInfo, unit)
            if IsReadable(name) and type(name) == "string" and name ~= "" then return name end
        end,
        ["cast.name"] = function(data)
            if data.casting == true then return data.castSpell end
        end,
        ["threat.hold"] = function(data)
            local info = data.threatInfo
            local hold = info and info.holdState
            if IsReadable(hold) and type(hold) == "string" then return HOLD_WORDS[hold] end
        end,
        ["hostile"] = function(_, unit)
            local reaction = ReadReaction(unit)
            if reaction == nil then return nil end
            return reaction <= 3
        end,
        ["neutral"] = function(_, unit)
            local reaction = ReadReaction(unit)
            if reaction == nil then return nil end
            return reaction == 4
        end,
        ["interruptible"] = function(data) return data.casting == true and data.castInterruptible == true end,
        ["questdrop"] = function(data) return data.questSource == "questiedb-item-drop" end,
        ["pvp"] = function(_, unit) return Call(UnitIsPVP, unit) end,
        ["instance"] = function() return Call(IsInInstance) end,
        ["ingroup"] = function(_, unit) return FriendlyRelationship(unit) == "group" end,
        ["inguild"] = function(_, unit) return FriendlyRelationship(unit) == "guild" end,
        ["quest"] = function(data) return data.questRelated == true end,
        ["friendly"] = function(data) return data.friendly == true end,
        -- The player's effective role (assigned, the Tank role choice, or adaptive tank evidence).
        ["role.tank"] = function()
            local service = PS.ThreatService
            if not service or type(service.GetPlayerRole) ~= "function" then return nil end
            local role = service:GetPlayerRole()
            if IsReadable(role) and type(role) == "string" then return role == "TANK" end
        end,
        ["threat.holding"] = ThreatFact("holding"),
        ["threat.losing"] = ThreatFact("losing"),
        ["threat.pulling"] = ThreatFact("pulling"),
        ["threat.other"] = ThreatFact("other"),
        ["threat.offtank"] = ThreatFact("offtank"),
    }

    -- One reader per plate, made once. Its cache holds for one plate update (the values render
    -- and the rules share it); Begin starts a new one. Whether a token was read is kept apart from
    -- its value, so a protected value is never compared with nil.
    function Readers.Begin(data)
        local reader = data.templateReader
        if reader then reader.stale = true end
    end

    function Readers.Get(data)
        local reader = data.templateReader
        if not reader then
            local known, values = {}, {}
            local function Read(token)
                if not known[token] then
                    known[token] = true
                    local read = TEMPLATE_READERS[token]
                    if read then
                        values[token] = read(data, data.unit, Read)
                    elseif PS.Template.ReadExtension then
                        -- A token or fact another addon registered (Template.RegisterToken).
                        values[token] = PS.Template.ReadExtension(token, data.unit, Read)
                    end
                end
                return values[token]
            end
            reader = { known = known, values = values, read = Read, stale = false }
            data.templateReader = reader
        elseif reader.stale then
            local known, values = reader.known, reader.values
            for token in pairs(known) do known[token], values[token] = nil, nil end
            reader.stale = false
        end
        return reader.read
    end

    return Readers
end
