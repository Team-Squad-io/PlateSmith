local _, PS = ...
local L = PS.L
local Template = assert(PS.Template, "PlateSmith Template missing")

-- What every rule and custom text word means: the one source for Studio's rule reference (Settings › Help), the
-- README's Rules section (tools/build-rule-reference.py) and the editors' hints. The words and their kinds are
-- Template.tokens'; their former names Template.FORMER_NAMES'. A test fails while a built-in token has no entry here.
local RuleWords = {}
PS.RuleWords = RuleWords

RuleWords.TOPICS = {
    { id = "unit", label = L["Unit"] }, { id = "range", label = L["Range"] }, { id = "pvp", label = L["PvP"] },
    { id = "health", label = L["Health & power"] },
    { id = "cast", label = L["Cast"] }, { id = "threat", label = L["Threat"] }, { id = "quest", label = L["Quest"] },
    { id = "level", label = L["Level"] }, { id = "objects", label = L["Objects"] }, { id = "you", label = L["You"] },
}

-- Which plate types have a word (a value on the others is missing, so a condition on it is unknown).
local PLATES = {
    all = L["every plate type"], units = L["all but Objects"], enemies = L["Enemies, Enemy players"],
    players = L["Players, Enemy players"], friends = L["Players"], interact = L["Objects, Friendly NPCs"],
    objects = L["Objects"], npcs = L["Enemies, Friendly NPCs"],
}
RuleWords.PLATES = PLATES
-- The plate types (Studio's tabs, Options.editorProfile) each of PLATES covers; all is every one.
local PLATE_TYPES = {
    units = { enemy = true, enemyPlayer = true, friendlyPlayer = true, friendlyNPC = true },
    enemies = { enemy = true, enemyPlayer = true }, players = { friendlyPlayer = true, enemyPlayer = true },
    friends = { friendlyPlayer = true }, interact = { object = true, friendlyNPC = true }, objects = { object = true },
    npcs = { enemy = true, friendlyNPC = true },
}

-- { word, topic, plates, what it means, an example }, in each topic's order.
RuleWords.WORDS = {
    { "name", "unit", "all", L["The unit's name."], "{name:max:12}" },
    { "target", "unit", "units", L["The name of whoever the unit targets; missing when it targets no one."],
        "{target:else:none}" },
    { "guild", "unit", "players", L["A player's guild."], "[if guild]<{guild}>[end]" },
    { "unit.player", "unit", "units", L["The unit is a player."], "unit.player = false" },
    { "unit.friendly", "unit", "all", L["The plate is a friendly one (Players, Friendly NPCs)."], "unit.friendly = false" },
    { "unit.hostile", "unit", "units", L["The unit is hostile to you."], "unit.hostile and unit.player" },
    { "unit.neutral", "unit", "units", L["The unit is neutral: it will not attack first."], "unit.neutral" },
    { "unit.elite", "unit", "units", L["The unit is elite (rare elites and world bosses too)."],
        "unit.elite and unit.tagged = false" },
    { "unit.rare", "unit", "units", L["The unit is rare (rare elites too)."], "unit.rare" },
    { "unit.boss", "unit", "units", L["The unit is a world boss."], "unit.boss" },
    { "unit.tagged", "unit", "enemies", L["Another player or group has tagged the mob: you get no credit for it."],
        "unit.tagged" },
    { "unit.target", "unit", "units", L["The unit is your target."], "you.hastarget and unit.target = false" },
    { "unit.focus", "unit", "units", L["The unit is your focus."], "unit.focus" },
    { "unit.ingroup", "unit", "friends", L["The player is in your group."], "unit.ingroup" },
    { "unit.inguild", "unit", "friends", L["The player is in your guild."], "unit.inguild and unit.ingroup = false" },
    { "unit.id", "unit", "npcs", L["An NPC's ID from the game."], "unit.id = 6740" },
    { "unit.creature", "unit", "units", L["The unit's creature type, the same word in every language (notspecified: "
        .. "the game's Not specified). Unknown where the game keeps it private or has none (objects)."],
        "unit.creature = beast or unit.creature = critter" },
    { "creature", "unit", "units", L["The unit's creature type as the game names it, in your game's language."],
        "{creature}" },
    { "targeted.count", "unit", "enemies", L["How many of your group or raid (not you) target the unit. Only answers "
        .. "the game gives are counted; unknown while it gives none."], "targeted.count >= 3" },
    { "unit.behind", "unit", "units", L["Your target's or focus's plate is behind the camera, as the game says; false on "
        .. "every other plate and while the game gives no readable answer. Not a direction or line of sight. The Behind you "
        .. "part shows it."],
        "unit.behind = false or unit.target = false" },
    { "unit.inrange", "range", "units", L["Your spells reach the unit, from your spellbook: harmful ones on enemies, "
        .. "helpful ones (heals, buffs) on friends. Unknown until PlateSmith has checked it, while one that may be too close "
        .. "cannot tell, and where the game withholds the answer (some in combat). The Range part shows it."],
        "unit.inrange = false" },
    { "range.known", "range", "units", L["PlateSmith has a range answer for the unit; false until it has checked and "
        .. "where the game withholds it, never unknown. A part hidden by it shows only while the range is known."],
        "range.known = false or unit.inrange" },
    { "range.band", "range", "units", L["How far the unit is, from the spells you know (not exact yards): melee (within "
        .. "5 yards), near (20), far (your longest spell's reach) or out (beyond it)."], "range.band = melee" },
    { "range", "range", "units", L["The band as text from your spells' own ranges: the nearest reach the unit is within "
        .. "(<5, <20, <30) or 30+ past your longest. Not exact yards."], "{range}" },
    { "pvp.flagged", "pvp", "players", L["The unit is flagged for PvP."], "pvp.flagged = false" },
    { "pvp.ffa", "pvp", "players", L["The unit is flagged for free-for-all PvP."], "pvp.ffa" },
    { "pvp.faction", "pvp", "players", L["The unit's faction."], "pvp.faction = horde" },
    { "pvp.sanctuary", "pvp", "units", L["The unit is in a sanctuary, where no one can be attacked."],
        "pvp.sanctuary = false and pvp.flagged" },
    { "pvp.you", "pvp", "all", L["You are flagged for PvP yourself."], "pvp.you and pvp.flagged" },
    { "health", "health", "units", L["Hit points."], "{health:short}" },
    { "health.max", "health", "units", L["Maximum hit points."], "{health} / {health.max}" },
    { "health.percent", "health", "units", L["Health, 0 to 100 (write the % yourself)."], "health.percent < 35" },
    { "health.missing", "health", "units", L["Hit points missing."], "{health.missing:short}" },
    { "power", "health", "units", L["The unit's power (mana, rage, energy...), while its power bar shows."], "{power}" },
    { "power.max", "health", "units", L["Maximum power, while the power bar shows."], "{power.max}" },
    { "power.percent", "health", "units", L["Power, 0 to 100, while the power bar shows."], "power.percent < 20" },
    { "cast.active", "cast", "units", L["The unit is casting or channelling."], "cast.active and cast.interruptible = false" },
    { "cast.interruptible", "cast", "units", L["The unit is casting something that can be interrupted."],
        "cast.interruptible and cast.interruptready" },
    { "cast.interruptready", "cast", "all", L["Your interrupt is ready (false on cooldown or with none; unknown where "
        .. "the game withholds it)."], "cast.interruptready = false" },
    { "cast.name", "cast", "units", L["The spell's name, while it casts."], "{cast.name:max:16}" },
    { "role.tank", "threat", "all", L["You are a tank: Always, Never, or your group role, stance or form (Settings › "
        .. "Modules › Threat)."], "role.tank and threat.losing" },
    { "threat.holding", "threat", "enemies", L["The mob is attacking you (you have its aggro)."], "threat.holding" },
    { "threat.losing", "threat", "enemies", L["You hold it, but someone else is close to pulling it."], "threat.losing" },
    { "threat.pulling", "threat", "enemies", L["You do not hold it, but you are close to pulling it."],
        "role.tank = false and threat.pulling" },
    { "threat.other", "threat", "enemies", L["It is in combat and someone else holds it."], "threat.other" },
    { "threat.offtank", "threat", "enemies", L["Another tank in your group holds it."], "threat.offtank" },
    { "threat.loose", "threat", "enemies", L["Someone who is not a tank holds it (the Tank window's LOOSE)."],
        "threat.loose" },
    { "threat.percent", "threat", "enemies", L["Your threat on it, 0 to 100."], "{threat.percent}%" },
    { "threat.lead", "threat", "enemies", L["While you hold it, your margin before anyone pulls it; otherwise how far "
        .. "you are behind."], "{threat.lead:short}" },
    { "threat.leadpercent", "threat", "enemies", L["Your threat as a percentage of the next highest (while you hold it) "
        .. "or of the holder's."], "threat.leadpercent > 110" },
    { "threat.raw", "threat", "enemies", L["Your raw threat."], "{threat.raw:short}" },
    { "threat.hold", "threat", "enemies", L["Who holds it: YOU, TANK or LOOSE."], "{threat.hold}" },
    { "quest.needed", "quest", "units", L["The unit is part of a quest in your log."], "quest.needed" },
    { "quest.drop", "quest", "enemies", L["It drops an item a quest in your log needs."], "quest.drop" },
    { "quest.progress", "quest", "units", L["Its objective's progress from your quest log, as 3/8 or 50%."],
        "{quest.progress}" },
    { "quest.percent", "quest", "units", L["Its objective's progress, 0 to 100."], "quest.percent >= 50" },
    { "level", "level", "units", L["The unit's level (-1 where the game hides it)."], "level >= 60" },
    { "level.smart", "level", "units", L["The level with its mark's letters: 14+ elite, 14R rare, 14B boss."],
        "{level.smart}" },
    { "level.diff", "level", "units", L["Its level against yours."], "level.diff > 2" },
    { "classification", "level", "units", L["Elite, Rare, Rare elite or Boss."], "{classification:upper}" },
    { "object.kind", "objects", "interact", L["What the game's own cursor icon says the unit is for."],
        "object.kind = herb" },
    { "object.unable", "objects", "interact", L["The icon says you can't yet (a skill too low, a locked chest)."],
        "object.unable" },
    { "interact.inrange", "objects", "interact", L["The unit is within reach."], "interact.inrange = false" },
    { "object.id", "objects", "objects", L["An object's ID from the game."], "object.id = 175734" },
    { "object.quest", "objects", "objects", L["A quest database (PlateSmith_QuestieDB) lists the object for a quest "
        .. "in your log."], "object.quest" },
    { "object.skill", "objects", "objects", L["The skill level the object needs, once known."], "object.skill > 100" },
    { "object.cangather", "objects", "objects", L["Your skill reaches it."], "object.cangather = false" },
    { "object.cancultivate", "objects", "objects", L["Cultivation (the Tauren racial) is ready for this herb."],
        "object.cancultivate" },
    { "you.combat", "you", "all", L["You are in combat."], "you.combat = false" },
    { "you.instance", "you", "all", L["You are in an instance (a dungeon, raid, battleground, arena or scenario)."],
        "you.instance" },
    { "you.hastarget", "you", "all", L["You have a target at all."], "you.hastarget and unit.target = false" },
    { "combo", "you", "enemies", L["Your combo points on your target's plate (0 to 5)."], "combo >= 4" },
}

-- How words combine: { what, its meaning, an example }.
RuleWords.OPERATORS = {
    { "and  or  not  ( )", L["Combine conditions; not comes first, then and, then or."],
        "unit.elite and (unit.rare or unit.boss)" },
    { "<  <=  >  >=  =  !=", L["Compare a number word with a number (== is the same as =)."], "health.percent < 35" },
    { "= true  = false", L["A flag is true or false (== and != too): x = false is not x."], "pvp.flagged = false" },
    { "= word  != word", L["A word with values is = or != one of them."], "object.kind = herb" },
    { "[if ...]  [elseif ...]  [else]  [end]", L["Custom text shows a part only while its condition holds, up to four "
        .. "deep; {word} writes a value."], "[if health.percent < 35]LOW[else]{health:short}[end]" },
}
RuleWords.UNKNOWN = L["A value the game hides, or one that is missing (no target, no guild), is unknown. not, and and "
    .. "or carry it (unknown and false is false, unknown or true is true), and a rule or [if] applies only while its "
    .. "condition is true, so an unknown one fails closed whichever way it is written: x = false is not true while x is "
    .. "unknown. A number alone is true when it is not zero, text when it is not empty."]

local KINDS = { number = L["number"], percent = L["percent"], signed = L["signed number"], text = L["text"],
    flag = L["flag"] }

-- A word's kind as the reference says it: "flag", "number"..., or "one of: a, b, c" for a word with values.
function RuleWords.Kind(word)
    local values = Template.enums[word]
    if values then
        local names = {}
        for name in pairs(values) do names[#names + 1] = name end
        table.sort(names)
        return string.format(L["one of: %s"], table.concat(names, ", "))
    end
    return KINDS[Template.tokens[word]] or Template.tokens[word]
end

-- The names a word also answers to: its former names (FORMER_NAMES) and other aliases, sorted.
local function OtherNames(word)
    local former, aliases = {}, {}
    for name, target in pairs(Template.aliases) do
        if target == word then
            if Template.FORMER_NAMES[name] then former[#former + 1] = name else aliases[#aliases + 1] = name end
        end
    end
    table.sort(former)
    table.sort(aliases)
    return former, aliases
end

-- Every entry in topic order: { word, topic, plates (label), text, example, kind, former = { names }, aliases }.
function RuleWords.Entries()
    local list = {}
    for _, topic in ipairs(RuleWords.TOPICS) do
        for _, word in ipairs(RuleWords.WORDS) do
            if word[2] == topic.id then
                local former, aliases = OtherNames(word[1])
                list[#list + 1] = { word = word[1], topic = topic.id, plates = PLATES[word[3]], text = word[4],
                    example = word[5], kind = RuleWords.Kind(word[1]), former = former, aliases = aliases }
            end
        end
    end
    return list
end

-- What does not agree with Template: built-in tokens without an entry, and entries that name no token (or a topic or
-- plates that do not exist). Empty when the reference is complete.
function RuleWords.Problems()
    local problems, described, topics = {}, {}, {}
    for _, topic in ipairs(RuleWords.TOPICS) do topics[topic.id] = true end
    for _, word in ipairs(RuleWords.WORDS) do
        if described[word[1]] then problems[#problems + 1] = "twice: " .. word[1] end
        described[word[1]] = true
        if not Template.tokens[word[1]] then problems[#problems + 1] = "no such token: " .. word[1] end
        if not topics[word[2]] or not PLATES[word[3]] then problems[#problems + 1] = "bad topic or plates: " .. word[1] end
    end
    for _, token in ipairs(Template.ListTokens()) do
        if token.builtin and not described[token.id] then problems[#problems + 1] = "no description: " .. token.id end
    end
    table.sort(problems)
    return problems
end

-- The flags and the words with values, for the editors' one-line hints ("unit.elite unit.rare ..."; "pvp.faction =
-- alliance, horde or neutral" as "pvp.faction (alliance, horde, neutral)").
function RuleWords.FlagNames()
    local flags, enums = {}, {}
    for _, entry in ipairs(RuleWords.Entries()) do
        local kind = Template.tokens[entry.word]
        if kind == "flag" then flags[#flags + 1] = entry.word
        elseif kind == "enum" then enums[#enums + 1] = entry.word end
    end
    return table.concat(flags, " "), table.concat(enums, " ")
end

-- Every word custom text can write as {word} (all but flags), in topic order, then other addons' tokens: the custom
-- text editor's list, so a new token is listed once it has its entry here.
function RuleWords.ValueNames()
    local names = {}
    for _, entry in ipairs(RuleWords.Entries()) do
        if Template.tokens[entry.word] ~= "flag" then names[#names + 1] = "{" .. entry.word .. "}" end
    end
    for _, token in ipairs(Template.ListTokens()) do
        if not token.builtin and token.kind ~= "flag" then names[#names + 1] = "{" .. token.id .. "}" end
    end
    return table.concat(names, " ")
end

-- A condition on word to start from (Studio's + Word): a flag alone, a word with values = one of them, a number
-- compared; each as the word's example writes it where that compiles (range.band = melee, targeted.count >= 3), else
-- the first value or > 0. nil for a text word (custom text shows it; a condition has no use for it).
function RuleWords.Starter(word, example)
    local kind = Template.tokens[word]
    if kind == "flag" then return word end
    if kind ~= "enum" and kind ~= "number" and kind ~= "percent" and kind ~= "signed" then return nil end
    local clause = type(example) == "string" and example:match("^" .. word:gsub("%p", "%%%0") .. "%s*[<>=!]+%s*[%w%.%-]+")
    if clause and Template.CompileCondition(clause) then return clause end
    local values = Template.enums[word]
    if values then
        local names = {}
        for name in pairs(values) do names[#names + 1] = name end
        table.sort(names)
        return names[1] and word .. " = " .. names[1] or nil
    end
    return word .. " > 0"
end

-- The words a condition can use on plateType (Studio's tab; nil: every plate type), by topic as Help lists them:
-- { { id, label, words = { { word, text, starter } } } }, a topic with none left out.
function RuleWords.Conditions(plateType)
    local topics, byTopic = {}, {}
    for _, topic in ipairs(RuleWords.TOPICS) do
        byTopic[topic.id] = { id = topic.id, label = topic.label, words = {} }
        topics[#topics + 1] = byTopic[topic.id]
    end
    for _, word in ipairs(RuleWords.WORDS) do
        local on = PLATE_TYPES[word[3]]
        local starter = RuleWords.Starter(word[1], word[5])
        if starter and (plateType == nil or on == nil or on[plateType]) then
            local list = byTopic[word[2]].words
            list[#list + 1] = { word = word[1], text = word[4], starter = starter }
        end
    end
    local shown = {}
    for _, topic in ipairs(topics) do if #topic.words > 0 then shown[#shown + 1] = topic end end
    return shown
end

-- Where a condition may start: the beginning, or after and, or, not or "(".
local function OpensClause(head)
    if head == "" or head:sub(-1) == "(" then return true end
    local last = head:match("([%w%.]+)$")
    return last == "and" or last == "or" or last == "not"
end

-- text with starter added (Studio's + Word): at cursor (a byte offset, as an edit box gives it) where a condition may
-- start there, joined to what follows by and; else at the end after " and " (or after a trailing and, or, not). Returns
-- the condition and the offset just past starter, or nil when it would be longer than limit.
function RuleWords.InsertCondition(text, starter, cursor, limit)
    text = type(text) == "string" and text or ""
    local result, stop
    cursor = tonumber(cursor)
    local head = cursor and text:sub(1, cursor):match("^(.-)%s*$")
    if text:match("^%s*$") then
        result, stop = starter, #starter
    elseif head and cursor < #text and OpensClause(head) then
        local tail = text:sub(cursor + 1):match("^%s*(.-)$")
        local first = tail:match("^([%w%.]+)")
        local join = ((tail == "" or tail:sub(1, 1) == ")") and "") or ((first == "and" or first == "or") and " ")
            or " and "
        local before = (head == "" or head:sub(-1) == "(") and head or head .. " "
        result, stop = before .. starter .. join .. tail, #before + #starter
    else
        local trimmed = text:match("^(.-)%s*$")
        local before = trimmed .. (OpensClause(trimmed) and " " or " and ")
        result, stop = before .. starter, #before + #starter
    end
    if limit and #result > limit then return nil end
    return result, stop
end

-- The README's Rules reference (tools/build-rule-reference.py writes it between its markers; a test compares).
-- retired: ProfilePresets' retired rule presets and the built-in options that do their jobs, when loaded.
local function Code(text) return "`" .. text .. "`" end
function RuleWords.Markdown()
    local lines = { "Every word, grouped by topic. **Also** lists its other names: the one it had before 1.3.2, which keeps "
        .. "working, and short names.", "" }
    local topic
    for _, entry in ipairs(RuleWords.Entries()) do
        if entry.topic ~= topic then
            topic = entry.topic
            for _, known in ipairs(RuleWords.TOPICS) do
                if known.id == topic then
                    if #lines > 2 then lines[#lines + 1] = "" end
                    lines[#lines + 1] = "### " .. known.label
                end
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "| Word | Also | Kind | Means | Example | Plates |"
            lines[#lines + 1] = "|---|---|---|---|---|---|"
        end
        local former = {}
        for _, name in ipairs(entry.former) do former[#former + 1] = Code(name) end
        for _, name in ipairs(entry.aliases) do former[#former + 1] = Code(name) end
        lines[#lines + 1] = string.format("| %s | %s | %s | %s | %s | %s |", Code(entry.word), table.concat(former, " "),
            entry.kind, entry.text, Code(entry.example), entry.plates)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Operators"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| Write | Means | Example |"
    lines[#lines + 1] = "|---|---|---|"
    for _, operator in ipairs(RuleWords.OPERATORS) do
        lines[#lines + 1] = string.format("| %s | %s | %s |", Code((operator[1]:gsub("%s%s+", " "))), operator[2],
            Code(operator[3]))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = RuleWords.UNKNOWN
    local presets = PS.ProfilePresets
    if presets and presets.BUILT_IN then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "### Presets that are built-in options now"
        lines[#lines + 1] = ""
        for _, option in ipairs(presets.BUILT_IN) do
            local names = {}
            for _, preset in ipairs(presets.RULES) do
                if preset.builtIn == option.id then names[#names + 1] = "**" .. preset.name .. "**" end
            end
            lines[#lines + 1] = string.format("- %s: %s (%s).", table.concat(names, ", "), option.name, option.home)
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Rules made from them stay ordinary rules. Rules › Presets › **Built in** opens each."
    end
    return table.concat(lines, "\n") .. "\n"
end
